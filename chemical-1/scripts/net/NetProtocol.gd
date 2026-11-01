# ============================================================
# NetProtocol.gd - 联机协议定义（P11-B 地基）
# 职责：消息类型常量 / 意图构造 / 主机侧校验 / 快照裁剪
# 纯静态工具：不持有状态、不接触网络，单机流程不实例化也不加载。
# 协议字段与流程图见 MULTIPLAYER_ARCHITECTURE.md
# ============================================================
extends RefCounted

const PROTO_VERSION = 1

# ---- 消息类型（字符串常量便于 JSON 直传）----
const MSG_HELLO = "hello"
const MSG_WELCOME = "welcome"
const MSG_GAME_START = "game_start"
const MSG_INTENT = "intent"
const MSG_APPLIED = "applied"
const MSG_REJECTED = "rejected"
const MSG_TURN = "turn"
const MSG_PENDING_SEQUENCE = "pending_sequence"
const MSG_SNAPSHOT = "snapshot"
const MSG_PING = "ping"
const MSG_PONG = "pong"

# ---- 客户端意图类型（与 GameManager.apply_event 的 type 完全一致）----
const INTENT_PLAY = "play"
const INTENT_PASS = "pass"
const INTENT_DISCARD_PASS = "discard_pass"
const INTENT_SEQUENCE_PICK = "sequence_pick"
const INTENT_SEQUENCE_SKIP = "sequence_skip"

const INTENT_TYPES = [
	INTENT_PLAY,
	INTENT_PASS,
	INTENT_DISCARD_PASS,
	INTENT_SEQUENCE_PICK,
	INTENT_SEQUENCE_SKIP,
]

# ---- 错误码（-1..-8 是规则码，勿复用）----
const ERR_UNKNOWN_MESSAGE = -100
const ERR_BAD_EVENT = -101
const ERR_NOT_YOUR_TURN = -102
const ERR_GAME_OVER = -103
const ERR_WRONG_SEAT = -104


static func is_known_message(msg_type: String) -> bool:
	return msg_type in [
		MSG_HELLO, MSG_WELCOME, MSG_GAME_START, MSG_INTENT, MSG_APPLIED,
		MSG_REJECTED, MSG_TURN, MSG_PENDING_SEQUENCE, MSG_SNAPSHOT,
		MSG_PING, MSG_PONG,
	]


# 构造一笔客户端意图：{type, by} + payload 平铺
# 例：make_intent(INTENT_PLAY, 1, {"uids": [12, 44], "valences": {"H": 1}, "pattern": -1})
static func make_intent(intent_type: String, by: int, payload: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = {"type": intent_type, "by": by}
	for k in payload:
		ev[k] = payload[k]
	return ev


# 主机侧轻量校验（不含规则判定 —— 规则由 apply_event → play_cards 负责）
# seat：发送者的座位号（由连接映射得到，不信任 payload 里的 by）
# current_player：GameManager.current_player_index
# 注意：sequence_pick / sequence_skip 发生在「牌权已移交」之后，跳过回合校验，
#       由主机依据 pending_sequence 状态判断它是否属于该玩家。
static func validate_intent(ev: Dictionary, seat: int, player_count: int,
		current_player: int, game_over: bool) -> int:
	if not (ev is Dictionary):
		return ERR_BAD_EVENT
	var intent_type := String(ev.get("type", ""))
	if not (intent_type in INTENT_TYPES):
		return ERR_BAD_EVENT
	var by := int(ev.get("by", -1))
	if by < 0 or by >= player_count:
		return ERR_WRONG_SEAT
	if by != seat:
		return ERR_WRONG_SEAT       # 谁也不许替别人出牌
	if game_over:
		return ERR_GAME_OVER
	if intent_type == INTENT_SEQUENCE_PICK or intent_type == INTENT_SEQUENCE_SKIP:
		return 0
	if by != current_player:
		return ERR_NOT_YOUR_TURN
	return 0


# 快照裁剪：只保留座位 seat 自己的手牌 uid，其他人只留张数。
# 返回的是深拷贝，调用方可安全修改，不会污染主机状态。
static func strip_snapshot(snapshot: Dictionary, seat: int) -> Dictionary:
	var out := snapshot.duplicate(true)
	var seats = out.get("players", [])
	if not (seats is Array):
		return out
	for i in range(seats.size()):
		if not (seats[i] is Dictionary):
			continue
		if i == seat:
			continue
		seats[i]["hand_uids"] = []   # hand_count 保留，供 UI 显示对手张数
	out["view_seat"] = seat
	return out
