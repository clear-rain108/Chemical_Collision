# ============================================================
# ActionRouter.gd - 动作路由层（P11-C1-c Step 1）
#
# 职责：把 UI 的十来处动作收口成 6 个方法，按「单机 / 联机」分派：
#   · 单机（session == null）：直接调用 GameManager，返回码与今天逐字等价
#     —— 这是重构成败的判据：verify_action_router 用同 seed 双实例对拍，一步一码比对。
#   · 联机：先本地只读预检（validate_play / auto_play_preview），
#     合法才把牌转成 uid 意图交给 NetSession.submit()。
#
# 为什么单机必须「等价」而不是另写一套：
#   UI 里所有 _handle_result(code) 分支（飞牌 / 提示 / 两阶段弹窗）都按
#   play_cards 的返回码写的；只要本层在单机下换一个码，41 套单机测试就全得跟着改。
#
# 为什么联机要先预检（决策 D1，见 MULTIPLAYER_TASKS.md §2）：
#   NetSession.submit() 在客人侧恒返回 0（= 已发出），而 0 在单机语义里是「成功」。
#   UI 若把它当成功，会立刻 _handle_result(0) → 飞牌动画 + 清选中 → 与主机裁决脱节。
#   所以联机分支的返回值只表达「这笔意图有没有发出去」：
#     >= 0  已发出（awaiting_reply() == true，等 state_applied / intent_rejected）
#     < 0   本地预检就没过，压根没发包（可以直接把规则原因贴给玩家）
#   预检用的 validate_play 与主机将来裁决用的是同一份 _evaluate_play，
#   因此「本地说能出、主机说不能」只可能来自回合/座位这类会话层校验（由主机拒）。
#
# 设计理由与后续步骤：MULTIPLAYER_TASKS.md / MULTIPLAYER_ARCHITECTURE.md §9.2
# ============================================================
extends RefCounted

const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")

# 本层自用错误码：与规则码（-1..-8）、协议码（-100..）都不重叠
const ERR_NO_GAME = -200       # 没注入 GameManager
const ERR_NO_SESSION = -201    # 联机分支却没有会话

# ---- 外部注入 ----
var game = null                # GameManager（必需）
var session = null             # NetSession（单机为 null）

# ---- 待裁决意图（仅客人侧有意义）----
var _awaiting: bool = false
var _awaiting_type: String = ""
var _awaiting_uids: Array = []

# ---- 最近一次动作的结果（UI 用来提示）----
var _last_code: int = 0
var _last_reason: String = ""


# ============================================================
# 一、装配
# ============================================================
# 单机：setup(game_manager)
# 联机：setup(game_manager, net_session)
# 重复 setup 是安全的（信号只连一次）。
func setup(game_manager, net_session = null) -> void:
	game = game_manager
	session = net_session
	_clear_awaiting()
	_last_code = 0
	_last_reason = ""
	if session == null:
		return
	# 客人侧：等主机裁决 → 清「已发出」标记
	if not session.state_applied.is_connected(_on_state_applied):
		session.state_applied.connect(_on_state_applied)
	if not session.intent_rejected.is_connected(_on_intent_rejected):
		session.intent_rejected.connect(_on_intent_rejected)
	# 会话结束 / 状态分叉：不能继续挂着「已发出」，否则 UI 永远置灰
	if not session.session_closed.is_connected(_on_session_closed):
		session.session_closed.connect(_on_session_closed)
	if not session.desync_detected.is_connected(_on_desync_detected):
		session.desync_detected.connect(_on_desync_detected)


# ============================================================
# 二、查询接口（UI 只用这些，不碰 game / session 内部）
# ============================================================
# 是否已进入联机（房间已建立；未开局也算）
func has_session() -> bool:
	return session != null and int(session.role) != int(NetSessionScript.Role.NONE)


# 是否「联机且对局进行中」：动作分派 / UI 视图归属都看这个
func is_online() -> bool:
	return has_session() and session.is_playing()


# 本端操作哪个座位：联机 = 自己的座位；单机 / 热座 = 当前行动者
func local_seat() -> int:
	if has_session():
		return int(session.my_seat)
	if game == null:
		return -1
	return game.current_player_index


# 客人侧：上一笔意图已发出、主机还没裁决
func awaiting_reply() -> bool:
	return _awaiting


func awaiting_type() -> String:
	return _awaiting_type


# 刚提交那笔意图涉及的 uid（Step 3b 补飞牌动画时按它对牌）
func awaiting_uids() -> Array:
	return _awaiting_uids.duplicate()


# 最近一次动作的结果码：单机 = 规则码；联机客人 = 已发出 0 / 本地预检失败码 / 主机拒绝码
func last_code() -> int:
	return _last_code


# 最近一次失败的人话原因（单机取 GameManager.last_reject_reason）
func last_reason() -> String:
	return _last_reason


# 现在能不能操作：联机看会话（对局中 + 有座位 + 无两阶段 + 未分叉），单机看是否已结束
func can_act() -> bool:
	if game == null:
		return false
	if has_session():
		return session.can_submit() and not _awaiting
	return not game.is_game_over()


# ============================================================
# 三、六个动作
# ============================================================
# 出牌（单质 / 顺序 / 族炸 / 化合物 / 有机物统一入口）
#   cards   ：本端 GameManager 里的 CardData 对象（UI 直接给选中的牌）
#   valences：化合价字典；有机物传 {"_organic": true}
#   pattern ：明确的牌型（CardPattern 枚举）；-1 = 交给引擎检测
func play(cards: Array, valences: Dictionary = {}, pattern: int = -1) -> int:
	if game == null:
		return _fail(ERR_NO_GAME, "内部错误：没有对局实例")
	if not has_session():
		return _remember(game.play_cards(game.current_player_index, cards, valences, pattern))
	# ---- 联机：本地只读预检，判据与主机裁决同源 ----
	var seat := local_seat()
	var pre: int = int(game.validate_play(seat, cards, valences, pattern))
	if pre < 0:
		# 没发包：把引擎写好的原因留给自己用（与单机 -1/-2 的提示完全一致）
		return _fail(pre, game.get_last_reject_reason())
	return _submit(NetProtocolScript.INTENT_PLAY, {
		"uids": _uids_of(cards),
		"valences": valences.duplicate(true),
		"pattern": pattern,
	})


# 「直接出牌 ⚡」：玩家只选牌，牌型由引擎按固定优先级挑
# 联机关键点：候选顺序必须在**本端**算出来后随意图发走（pattern + valences 都写明），
# 否则主机会自己再挑一次，两端就可能出成不同牌型（state_hash 立刻分叉）。
func auto_play(cards: Array) -> int:
	if game == null:
		return _fail(ERR_NO_GAME, "内部错误：没有对局实例")
	if not has_session():
		return _remember(game.auto_play(game.current_player_index, cards))
	var seat := local_seat()
	var plan: Dictionary = game.auto_play_preview(seat, cards)
	var code: int = int(plan.get("code", -1))
	if code < 0:
		return _fail(code, String(plan.get("reason", "")))
	var cv = plan.get("custom_valences", {})
	return _submit(NetProtocolScript.INTENT_PLAY, {
		"uids": _uids_of(cards),
		"valences": (cv as Dictionary).duplicate(true) if cv is Dictionary else {},
		"pattern": int(plan.get("pattern", -1)),
	})


# 跳过回合（手牌达上限时 UI 应先走 discard_and_pass，见 GameUI._on_pass）
func pass_turn() -> int:
	if game == null:
		return _fail(ERR_NO_GAME, "内部错误：没有对局实例")
	if not has_session():
		game.player_pass(game.current_player_index)
		return _remember(0)
	return _submit(NetProtocolScript.INTENT_PASS, {})


# 手牌达上限：弃 1 张并跳过
func discard_and_pass(card) -> int:
	if game == null:
		return _fail(ERR_NO_GAME, "内部错误：没有对局实例")
	if card == null:
		return _fail(-1, "请先选择要弃置的牌")
	if not has_session():
		game.player_discard_and_pass(game.current_player_index, card)
		return _remember(0)
	return _submit(NetProtocolScript.INTENT_DISCARD_PASS, {"uid": int(card.uid)})


# 两阶段：指定下一名玩家必须打出的牌型
func pick_sequence(pattern: int) -> int:
	if game == null:
		return _fail(ERR_NO_GAME, "内部错误：没有对局实例")
	if not has_session():
		game.set_sequence_constraint(pattern)
		return _remember(0)
	return _submit(NetProtocolScript.INTENT_SEQUENCE_PICK, {"pattern": pattern})


# 两阶段：放弃指定（等价于 UI「跳过指定」按钮）
func skip_sequence() -> int:
	if game == null:
		return _fail(ERR_NO_GAME, "内部错误：没有对局实例")
	if not has_session():
		game.sequence_constraint_active = false
		game.sequence_constraint = -1
		game.sequence_constraint_target = -1
		game.next_turn()
		return _remember(0)
	return _submit(NetProtocolScript.INTENT_SEQUENCE_SKIP, {})


# ============================================================
# 四、内部：提交 / 结果记账
# ============================================================
func _submit(intent_type: String, payload: Dictionary) -> int:
	if session == null:
		return _fail(ERR_NO_SESSION, "内部错误：没有联机会话")
	var code: int = int(session.submit(intent_type, payload))
	# 主机：submit 当场裁决，返回值就是规则码（同步落子 + 广播）
	if session.is_host():
		if code < 0:
			return _fail(code, game.get_last_reject_reason())
		_last_code = code
		_last_reason = ""
		return code
	# 客人：<0 是会话层自己拦下的（未开局 / 观战 / 分叉），这些根本没有发包
	if code < 0:
		return _fail(code, describe_code(code))
	_awaiting = true
	_awaiting_type = intent_type
	var pending_uids = payload.get("uids", [])
	_awaiting_uids = pending_uids.duplicate() if pending_uids is Array else []
	_last_code = 0
	_last_reason = ""
	return 0


func _remember(code: int) -> int:
	_last_code = int(code)
	_last_reason = ""
	if game != null and int(code) < 0:
		_last_reason = game.get_last_reject_reason()
	return _last_code


func _fail(code: int, reason: String) -> int:
	_last_code = int(code)
	_last_reason = String(reason)
	return _last_code


func _clear_awaiting() -> void:
	_awaiting = false
	_awaiting_type = ""
	_awaiting_uids = []


# 牌对象 → uid 列表（联机事件只认 uid：下标是 UI 的本地概念）
func _uids_of(cards) -> Array:
	var out: Array = []
	if not (cards is Array):
		return out
	for c in cards:
		if c == null:
			continue
		out.append(int(c.uid))
	return out


# ============================================================
# 五、信号回调
# ============================================================
# 主机广播的每笔事件都会走到这里（含别人的）；只认「自己那笔、类型对得上」的
func _on_state_applied(ev: Dictionary, result: int) -> void:
	if not _awaiting:
		return
	if int(ev.get("by", -1)) != local_seat():
		return
	if String(ev.get("type", "")) != _awaiting_type:
		return
	_clear_awaiting()
	_last_code = int(result)
	_last_reason = ""


func _on_intent_rejected(seq: int, code: int) -> void:
	if not _awaiting:
		return
	_clear_awaiting()
	_last_code = int(code)
	_last_reason = describe_code(int(code))


func _on_session_closed(reason: String) -> void:
	_clear_awaiting()
	_last_reason = String(reason)


func _on_desync_detected(local_hash: int, host_hash: int) -> void:
	_clear_awaiting()
	_last_code = NetProtocolScript.ERR_DESYNC
	_last_reason = "状态分叉（本端 %d / 主机 %d），已停止推进" % [int(local_hash), int(host_hash)]


# ============================================================
# 六、错误码 → 人话（UI / 日志共用）
# ============================================================
# 规则码（-1..-8）与 GameUI._handle_result 的措辞保持一致，避免同一件事两种说法。
static func describe_code(code: int) -> String:
	match int(code):
		0:
			return ""
		1:
			return "打出顺序牌，需要指定下一名玩家的牌型"
		-1:
			return "非法出牌"
		-2:
			return "牌不够大"
		-3:
			return "不能出族炸（族炸冷却中或本局禁用）"
		-4:
			return "牌型接不上当前桌面"
		-6:
			return "不符合顺序指定的牌型约束"
		-7:
			return "卤族元素(F/Cl/Br/I)之间不可互相化合"
		-8:
			return "该元素不在本局牌库中"
		-100:
			return "未知消息类型"
		-101:
			return "事件格式错误"
		-102:
			return "还没轮到你"
		-103:
			return "对局已结束"
		-104:
			return "座位不符"
		-105:
			return "当前没有待指定的顺序牌型"
		-106:
			return "对局未开始 / 观战者不能操作"
		-107:
			return "房间已满"
		-108:
			return "重复提交"
		-109:
			return "状态分叉，已停止推进"
		ERR_NO_GAME:
			return "内部错误：没有对局实例"
		ERR_NO_SESSION:
			return "内部错误：没有联机会话"
	return "未知错误（%d）" % int(code)
