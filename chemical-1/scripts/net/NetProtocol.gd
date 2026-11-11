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
# P11-C1-b 增补：连接状态双向确认 / 座位变化广播
const MSG_READY = "ready"                # C→S：快照重放完，附本地指纹供主机核对
const MSG_PEER_LEFT = "peer_left"        # S→all：某座位掉线，座位保留等待重连
const MSG_PEER_JOINED = "peer_joined"    # S→all：某座位（重新）上线

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
# P11-C1-b 增补
const ERR_NO_PENDING = -105      # 没有待处理的顺序牌型，却收到 sequence_pick / sequence_skip
const ERR_NOT_READY = -106       # 未开局 / 观战者（seat = -1）提交意图
const ERR_ROOM_FULL = -107       # 房间满员，且本局不允许中途观战
const ERR_DUPLICATE_SEQ = -108   # 重复序号（同一意图被重投）
const ERR_DESYNC = -109          # 重连重放后 state_hash 仍与主机不符
# P11-C1-c 增补
const ERR_NOT_HOST = -110        # 非主机调用主机专属接口（host_act_for_seat / host_step_ai）


static func is_known_message(msg_type: String) -> bool:
	return msg_type in [
		MSG_HELLO, MSG_WELCOME, MSG_GAME_START, MSG_INTENT, MSG_APPLIED,
		MSG_REJECTED, MSG_TURN, MSG_PENDING_SEQUENCE, MSG_SNAPSHOT,
		MSG_PING, MSG_PONG, MSG_READY, MSG_PEER_LEFT, MSG_PEER_JOINED,
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


# ============================================================
# 消息编解码（P11-C1-b）
# ============================================================
# 为什么用 var_to_bytes 而不是 JSON：
#   JSON 会把所有数字变成 float —— uids / seq / hash 都要显式转回 int，
#   漏一处就是「uid 12.0 找不到手牌」这类静默 bug。var_to_bytes 保留 int 类型。
# 外层加 8 字节头（魔数 + body 长度）：
#   畸形包在进 bytes_to_var 之前就被拦下，不会让引擎刷 "Invalid data" 报错。
const WIRE_MAGIC = 0x43484D31        # "CHM1"
const WIRE_HEADER_SIZE = 8


# 字典 → 线格式字节：[magic u32][body_len u32][var_to_bytes(msg)]
static func encode(msg: Dictionary) -> PackedByteArray:
	var body := var_to_bytes(msg)
	var out := PackedByteArray()
	out.resize(WIRE_HEADER_SIZE)
	out.encode_u32(0, WIRE_MAGIC)
	out.encode_u32(4, body.size())
	out.append_array(body)
	return out


# 线格式字节 → 字典；任何不合规输入一律返回空字典（调用方按「丢弃」处理）
static func decode(data: PackedByteArray) -> Dictionary:
	if data == null or data.size() < WIRE_HEADER_SIZE:
		return {}
	if data.decode_u32(0) != WIRE_MAGIC:
		return {}
	if int(data.decode_u32(4)) != data.size() - WIRE_HEADER_SIZE:
		return {}
	var body := data.slice(WIRE_HEADER_SIZE)
	var value = bytes_to_var(body)
	if not (value is Dictionary):
		return {}
	return value


# sequence_pick / sequence_skip 发生在「牌权已移交」之后，不算普通回合意图
static func is_sequence_intent(intent_type: String) -> bool:
	return intent_type == INTENT_SEQUENCE_PICK or intent_type == INTENT_SEQUENCE_SKIP
