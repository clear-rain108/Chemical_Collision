# ============================================================
# net/VoteBox.gd - 化合物质疑投票（D22，纯逻辑，不碰网络 / 不碰 UI）
#
# 场景：玩家打出化学性不合法的化合物（配不平 -1 / 卤族互化 -7）。
# 单机直接拒绝；联机不硬拒，而是把这一手交给**其他真人**裁定：
#   · 全部赞成 → 本局视为合法并落子（并且这个「元素组成」记入白名单）
#   · 有任何一人反对 / 超时无人全票 → 出牌撤销 + 罚抽 1 张
#
# 为什么把状态机单独拎出来（而不是塞进 NetSession）：
#   ① 它是纯函数式的（open / cast / remove_voter / settle_cause / resolve），
#      可以完全不碰 ENet 地测完 11 项边界（tests/verify_vote_box.gd）；
#   ② 主机是唯一权威：投票箱只存在于主机，客人手里只有 snapshot（镜像），
#      于是「谁投了什么」不可能被客人自己篡改。
#
# 三条硬口径（投票结果必须逐笔可复现，见 MULTIPLAYER_ARCHITECTURE.md）：
#   1) 分母 = 开票那一刻在线的**人类**座位（排除出题人自己、排除 AI、排除观战）；
#   2) 掉线立即出分母：票也一并作废 —— 否则「掉线者早先投的反对票」会永远
#      卡住一个已经不在场的人；
#   3) 只有「全部赞成」才算通过。弃权不存在：不投 = 超时 = 不通过（20s）。
# ============================================================
extends RefCounted

# ---- 收口原因（进事件 / 进日志 / 进测试断言）----
const CAUSE_ALL_YES = "all_yes"        # 全票赞成 → 通过
const CAUSE_REJECTED = "rejected"      # 有人反对 → 驳回
const CAUSE_TIMEOUT = "timeout"        # 超时没投完 → 视为不通过
const CAUSE_NO_VOTER = "no_voter"      # 分母清空（投票人全掉线）→ 不通过

# 本层自用错误码：与规则码（-1..-8）、协议码（-100..-113）对齐但不重复定义
const ERR_NO_VOTE = -112
const ERR_NOT_VOTER = -113

# ---- 投票箱状态 ----
var vid: int = 0                      # 本局内自增的投票号（1 起；0 = 没有投票）
var by: int = -1                      # 出题人座位
var voters: Array = []                # 分母：开票时冻结的人类座位（升序）
var votes: Dictionary = {}            # seat(int) → bool（true = 赞成）
var claim: Dictionary = {}            # 待裁定的出牌：{uids, valences, pattern}
var reason: String = ""               # 引擎给的人话驳回原因（UI 直接展示）
var opened_at: int = 0                # 开票时刻（ms）
var deadline: int = 0                 # 收口截止时刻（ms）
var resolved: bool = false            # 已收口
var approved: bool = false            # 收口结论
var cause: String = ""                # 收口原因（上面四个常量之一）


# 开票。voter_seats 由调用方（主机）算好并**冻结**：投票期间掉线只做减法，
# 不做加法 —— 否则「后进来的人」会被拉进一个已经进行了一半的投票。
func open(id: int, proposer: int, voter_seats: Array, claim_payload: Dictionary,
		reject_reason: String, now_ms: int, timeout_ms: int) -> void:
	vid = int(id)
	by = int(proposer)
	voters = []
	for s in voter_seats:
		var seat := int(s)
		if seat == by or seat < 0:
			continue
		if not voters.has(seat):
			voters.append(seat)
	voters.sort()
	votes.clear()
	claim = claim_payload.duplicate(true)
	reason = String(reject_reason)
	opened_at = int(now_ms)
	deadline = int(now_ms) + maxi(1, int(timeout_ms))
	resolved = false
	approved = false
	cause = ""


func is_open() -> bool:
	return vid > 0 and not resolved


func has_voter(seat: int) -> bool:
	return voters.has(int(seat))


func has_voted(seat: int) -> bool:
	return votes.has(int(seat))


func total() -> int:
	return voters.size()


func approve_count() -> int:
	var n := 0
	for s in voters:
		if bool(votes.get(int(s), false)):
			n += 1
	return n


func reject_count() -> int:
	var n := 0
	for s in voters:
		if votes.has(int(s)) and not bool(votes[int(s)]):
			n += 1
	return n


# 还没投的座位（UI 显示「等待 x / y」用）
func pending_seats() -> Array:
	var out: Array = []
	for s in voters:
		if not votes.has(int(s)):
			out.append(int(s))
	return out


# 投票（主机侧唯一入口）。
# 返回：0 = 已记录 / 幂等重复；ERR_NO_VOTE = 已收口；ERR_NOT_VOTER = 不在分母里。
# 第一票有效：重复投同一值幂等返回 0，改票不允许（避免「等人投完再翻牌」的拉扯）。
func cast(seat: int, yes: bool) -> int:
	if not is_open():
		return ERR_NO_VOTE
	var s := int(seat)
	if not voters.has(s):
		return ERR_NOT_VOTER
	if votes.has(s):
		return 0
	votes[s] = bool(yes)
	return 0


# 掉线：从分母里移除，连带作废它已投的票。
# 返回 true = 确实移除了（调用方据此决定要不要广播新状态 / 复查收口）。
func remove_voter(seat: int) -> bool:
	var s := int(seat)
	if not voters.has(s):
		return false
	voters.erase(s)
	votes.erase(s)
	return true


func all_yes() -> bool:
	if voters.is_empty():
		return false
	for s in voters:
		if not votes.has(int(s)) or not bool(votes[int(s)]):
			return false
	return true


func any_no() -> bool:
	return reject_count() > 0


# 现在该不该自动收口（"" = 还要继续等）
func settle_cause() -> String:
	if resolved:
		return cause
	if voters.is_empty():
		return CAUSE_NO_VOTER
	if any_no():
		return CAUSE_REJECTED        # 一票否决，不必等剩下的人
	if all_yes():
		return CAUSE_ALL_YES
	return ""


func expired(now_ms: int) -> bool:
	return is_open() and int(now_ms) >= deadline


func remain_ms(now_ms: int) -> int:
	if resolved:
		return 0
	return maxi(0, deadline - int(now_ms))


# 收口，返回结论快照。override_cause 非空表示「由调用方判定原因」（超时 / 掉线兜底）；
# 空字符串表示「按当前票型自动判定」，尚未投完时兜底成超时不通过。
func resolve(override_cause: String = "") -> Dictionary:
	if resolved:
		return snapshot(opened_at)
	var c := String(override_cause)
	if c == "":
		c = settle_cause()
	if c == "":
		c = CAUSE_TIMEOUT
	resolved = true
	cause = c
	approved = (c == CAUSE_ALL_YES)
	return snapshot(opened_at)


# 广播 / 本地镜像用的扁平快照（全部基础类型，var_to_bytes 可直传）。
# votes 用 int 键：两端都是 Godot，不需要走 JSON 的 float 归一。
func snapshot(now_ms: int = 0) -> Dictionary:
	return {
		"vid": vid,
		"by": by,
		"voters": voters.duplicate(),
		"votes": votes.duplicate(),
		"claim": claim.duplicate(true),
		"reason": reason,
		"total": total(),
		"approve_count": approve_count(),
		"reject_count": reject_count(),
		"remain_ms": remain_ms(now_ms),
		"resolved": resolved,
		"approved": approved,
		"cause": cause,
	}
