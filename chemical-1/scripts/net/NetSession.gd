# ============================================================
# NetSession.gd - 联机会话层（P11-C1-b）
# 职责：
#   1) 房间生命周期：握手 → 座位分配 → 开局 → 对局 → 结束
#   2) 主机权威：只有主机 apply_event 的结果算数，客人只重放主机广播的事件
#   3) 一致性自检：每笔事件后 state_hash() 比对，失配立即报警
#   4) 断线容忍：座位保留 + token 身份复用 + 超时托管
#
# 三条来自实测的硬约束（见 MULTIPLAYER_ARCHITECTURE.md 附录 C）：
#   · peer_id 不是座位号：ENet 客人的 peer_id 是随机 32 位整数，必须走映射表
#   · 传输层 close() 后不可再 poll()：本层关闭后所有入口直接返回
#   · GameManager 没有 from_snapshot()：恢复局面一律用「同 seed init_game +
#     replay_events(event_log)」，日志条数也能重建，state_hash() 才对得上
#
# 设计文档：MULTIPLAYER_ARCHITECTURE.md §6（协议）/ 附录 D（实现说明 + 已知限制）
# ============================================================
extends RefCounted

const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")

# ---- 角色 / 会话状态 ----
enum Role { NONE, HOST, CLIENT }
enum State { IDLE, CONNECTING, LOBBY, PLAYING, OVER, CLOSED }
enum SeatState { EMPTY, ONLINE, OFFLINE }

# ---- 默认参数 ----
const DEFAULT_MAX_PLAYERS = 4
const DEFAULT_PENDING_TIMEOUT_MS = 15000    # 顺序牌型两阶段的等待上限
const DEFAULT_RECONNECT_GRACE_MS = 60000    # 掉线后座位保留时长
const WATCHER_SEAT = -1                     # 观战者：不占座位、无操作权
const HOST_PEER_ID = 1                      # ENet / Loopback 的主机 peer_id 恒为 1

# ENet 服务端的**连接名额**要预留余量，不能直接等于座位数：
#   ① 掉线重连时旧连接在 ENet 侧还没完全释放，会和新连接同时占名额；
#   ② 观战者不占座位，但仍要占一个连接。
# 名额正好等于座位数时，重连和观战都会被 ENet 直接拒掉（表现为永远 CONNECTING），
# 上层连拒绝消息都发不出去。留 4 个余量，代价只是几条空连接槽。
const RECONNECT_SLACK = 4


# ---- 信号 ----
signal seat_assigned(seat: int)                          # welcome 之后，客人得知自己的座位
signal room_changed()                                    # 座位表变化（加入 / 离开 / 上线 / 掉线）
signal game_started()                                    # game_start 应用完，可以切到牌桌
signal state_applied(ev: Dictionary, result: int)        # 每笔事件应用完 → UI 刷新
signal intent_rejected(seq: int, code: int)              # 自己的意图被主机拒绝
signal sequence_pending(seat: int, remain_ms: int)       # 两阶段：等待该座位指定牌型
signal sequence_cleared()                                # 两阶段结束
signal desync_detected(local_hash: int, host_hash: int)  # 状态分叉
signal peer_left(seat: int, peer_name: String, grace_ms: int)
signal peer_joined(seat: int, peer_name: String)
signal session_closed(reason: String)
signal error_raised(code: int, detail: String)

# ---- 外部注入 ----
var game = null                 # GameManager 实例（外部持有，本层不 new）
var transport = null            # NetTransport 实例（ENet / Loopback …）

# ---- 基础 ----
var role: int = Role.NONE
var state: int = State.IDLE
var local_name: String = "玩家"

# ---- 可调参数（测试会改小） ----
var max_players: int = DEFAULT_MAX_PLAYERS
var pending_sequence_timeout_ms: int = DEFAULT_PENDING_TIMEOUT_MS
var reconnect_grace_ms: int = DEFAULT_RECONNECT_GRACE_MS
var allow_watchers: bool = true

# ---- 房间 / 座位表 ----
var my_seat: int = WATCHER_SEAT
var room_code: String = ""
var _seat_state: Dictionary = {}        # seat → SeatState
var _seat_token: Dictionary = {}        # seat → token（重连凭据）
var _token_seat: Dictionary = {}        # token → seat
var _seat_name: Dictionary = {}         # seat → 昵称（只给 UI 用，绝不写进 GameManager）
var _peer_seat: Dictionary = {}         # peer_id → seat
var _seat_peer: Dictionary = {}         # seat → peer_id
var _offline_deadline: Dictionary = {}  # seat → ticks_msec（grace 到期时刻）
var _ready_seats: Dictionary = {}       # seat → true（仅主机维护）

# ---- 对局 ----
var _seed: int = -1
var _player_count: int = 4
var _ai_count: int = 0
var _config: Dictionary = {}
var _pending: Dictionary = {}           # 仅主机：{"seat":int, "seq":int, "deadline":int}
var _pending_seat: int = WATCHER_SEAT   # 客户端视角：谁正在选牌型
var _my_seq: int = 0                    # 本端已提交的意图序号
var _last_seq: Dictionary = {}          # 仅主机：seat → 已应用的最大 seq（去重）
var _my_token: String = ""
var _desynced: bool = false
var _last_hash: int = 0
var _closed_reason: String = ""


# ============================================================
# 一、生命周期
# ============================================================
# transport 由外部创建并注入（便于测试换实现、便于 UI 复用）
func setup(game_manager, net_transport) -> void:
	game = game_manager
	transport = net_transport
	if transport != null:
		transport.peer_connected.connect(_on_peer_connected)
		transport.peer_disconnected.connect(_on_peer_disconnected)
		transport.packet_received.connect(_on_packet)


# 房主：监听端口，自己是 seat 0
func start_host(port: int, player_slots: int = DEFAULT_MAX_PLAYERS,
		host_name: String = "房主") -> int:
	if transport == null or game == null:
		return -1
	_reset_session()
	role = Role.HOST
	local_name = host_name
	max_players = clampi(player_slots, 2, 4)
	if transport.host(port, max_players + RECONNECT_SLACK) != 0:
		role = Role.NONE
		return -1
	_seed = _make_seed()
	room_code = "%04d" % (_seed % 10000)
	my_seat = 0
	_seat_state[0] = SeatState.ONLINE
	_seat_name[0] = local_name
	_seat_token[0] = _new_token()
	_token_seat[_seat_token[0]] = 0
	_seat_peer[0] = HOST_PEER_ID
	_peer_seat[HOST_PEER_ID] = 0
	_ready_seats[0] = true
	state = State.LOBBY
	room_changed.emit()
	return 0


# 客人：发起连接（真正连上以 seat_assigned 为准）
func start_client(address: String, port: int, client_name: String = "玩家") -> int:
	if transport == null or game == null:
		return -1
	var token := _my_token
	_reset_session()
	_my_token = token          # _reset_session 不清 token：重连要靠它
	role = Role.CLIENT
	local_name = client_name
	if transport.join(address, port) != 0:
		role = Role.NONE
		return -1
	state = State.CONNECTING
	return 0


# 重连：沿用上次拿到的 token，主机凭它恢复原座位
func start_client_resume(address: String, port: int, token: String,
		client_name: String = "玩家") -> int:
	_my_token = token
	return start_client(address, port, client_name)


func close(reason: String = "主动退出") -> void:
	if state == State.CLOSED:
		return
	_closed_reason = reason
	state = State.CLOSED
	if transport != null:
		transport.close()
	_pending.clear()
	_pending_seat = WATCHER_SEAT
	session_closed.emit(reason)


func _reset_session() -> void:
	state = State.IDLE
	my_seat = WATCHER_SEAT
	room_code = ""
	_seat_state.clear()
	_seat_token.clear()
	_token_seat.clear()
	_seat_name.clear()
	_peer_seat.clear()
	_seat_peer.clear()
	_offline_deadline.clear()
	_ready_seats.clear()
	_pending.clear()
	_pending_seat = WATCHER_SEAT
	_my_seq = 0
	_last_seq.clear()
	_seed = -1
	_config.clear()
	_desynced = false
	_last_hash = 0
	_closed_reason = ""


# ============================================================
# 二、查询接口（UI / ActionRouter 只用这些）
# ============================================================
func is_host() -> bool:
	return role == Role.HOST


func is_playing() -> bool:
	return state == State.PLAYING


func is_desynced() -> bool:
	return _desynced


func is_watcher() -> bool:
	return my_seat == WATCHER_SEAT


func last_hash() -> int:
	return _last_hash


func get_token() -> String:
	return _my_token


func seat_count() -> int:
	return _seat_state.size()


func seat_name(seat: int) -> String:
	return String(_seat_name.get(seat, ""))


func seat_is_online(seat: int) -> bool:
	return int(_seat_state.get(seat, SeatState.EMPTY)) == SeatState.ONLINE


# 座位是不是 AI 托管（AI 座位排在人类座位之后）
func is_seat_ai(seat: int) -> bool:
	if game == null or seat < 0:
		return false
	return seat >= _player_count - _ai_count


func seat_of_peer(peer_id: int) -> int:
	return int(_peer_seat.get(peer_id, WATCHER_SEAT))


func peer_of_seat(seat: int) -> int:
	return int(_seat_peer.get(seat, 0))


# 本地座位的手牌 uid（A 档信任模型下 game 里其实全都有，这里只暴露该看的）
func my_hand_uids() -> Array:
	if game == null or is_watcher():
		return []
	return game.get_hand_uids(my_seat)


func is_my_turn() -> bool:
	if game == null or is_watcher() or _desynced:
		return false
	if is_seat_ai(my_seat) or game.is_game_over():
		return false
	return game.current_player_index == my_seat


# 现在能不能操作：对局中 + 有座位 + 无待处理两阶段 + 状态未分叉
func can_submit() -> bool:
	if state != State.PLAYING or game == null or is_watcher() or _desynced:
		return false
	if game.is_game_over():
		return false
	if pending_seat() != WATCHER_SEAT:
		return false
	return true


# 当前是不是在等我选「顺序牌型」
func is_my_sequence_pending() -> bool:
	return not is_watcher() and pending_seat() == my_seat


# 正在等谁选「顺序牌型」（-1 = 没有待处理）；主机读内部状态，客人读广播值
func pending_seat() -> int:
	if role == Role.HOST:
		return int(_pending.get("seat", WATCHER_SEAT))
	return _pending_seat


# ============================================================
# 三、每帧驱动
# ============================================================
# 由宿主（GameUI._process / 测试循环）每帧调用一次
func poll() -> void:
	if state == State.CLOSED or transport == null:
		return
	transport.poll()
	_poll_timeouts()


# ---- 传输层事件 ----
func _on_peer_connected(peer_id: int) -> void:
	if role == Role.CLIENT:
		# 客人：连上就报身份；带 token 表示「我是回来重连的」
		_send_hello(peer_id)
	# 主机：只等对端 hello，此时不分配座位


func _on_peer_disconnected(peer_id: int) -> void:
	var seat := seat_of_peer(peer_id)
	if seat == WATCHER_SEAT:
		return
	_peer_seat.erase(peer_id)
	_seat_peer.erase(seat)
	if role == Role.HOST:
		_handle_seat_offline(seat)
		return
	# 客人视角
	if peer_id == HOST_PEER_ID:
		close("与主机的连接已断开")
		return
	_seat_state[seat] = SeatState.OFFLINE
	room_changed.emit()


func _on_packet(peer_id: int, data: PackedByteArray) -> void:
	if state == State.CLOSED:
		return
	var msg := NetProtocolScript.decode(data)
	if msg.is_empty():
		return
	_dispatch(peer_id, msg)


func _dispatch(peer_id: int, msg: Dictionary) -> void:
	var mtype := String(msg.get("type", ""))
	match mtype:
		NetProtocolScript.MSG_HELLO:
			if role == Role.HOST:
				_host_on_hello(peer_id, msg)
		NetProtocolScript.MSG_READY:
			if role == Role.HOST:
				_host_on_ready(peer_id, msg)
		NetProtocolScript.MSG_WELCOME:
			if role == Role.CLIENT:
				_client_on_welcome(peer_id, msg)
		NetProtocolScript.MSG_GAME_START:
			if role == Role.CLIENT:
				_client_on_game_start(msg)
		NetProtocolScript.MSG_INTENT:
			if role == Role.HOST:
				_host_on_intent(peer_id, msg)
		NetProtocolScript.MSG_APPLIED:
			if role == Role.CLIENT:
				_client_on_applied(msg)
		NetProtocolScript.MSG_REJECTED:
			if role == Role.CLIENT:
				_client_on_rejected(msg)
		NetProtocolScript.MSG_PENDING_SEQUENCE:
			if role == Role.CLIENT:
				_client_on_pending_sequence(msg)
		NetProtocolScript.MSG_SNAPSHOT:
			if role == Role.CLIENT:
				_client_on_snapshot(msg)
		NetProtocolScript.MSG_PEER_LEFT:
			if role == Role.CLIENT:
				_client_on_peer_left(msg)
		NetProtocolScript.MSG_PEER_JOINED:
			if role == Role.CLIENT:
				_client_on_peer_joined(msg)
		_:
			if role == Role.HOST:
				error_raised.emit(NetProtocolScript.ERR_UNKNOWN_MESSAGE, "未知消息: " + mtype)


# ============================================================
# 四、握手
# ============================================================
func _send_hello(to_peer: int) -> void:
	_send(to_peer, {
		"type": NetProtocolScript.MSG_HELLO,
		"proto": NetProtocolScript.PROTO_VERSION,
		"name": local_name,
		"token": _my_token,        # 空 = 首次连接；非空 = 申请恢复原座位
	})


# ---- 主机：收到 hello → 分配 / 恢复座位 → welcome ----
func _host_on_hello(peer_id: int, msg: Dictionary) -> void:
	var proto := int(msg.get("proto", 0))
	var peer_name := String(msg.get("name", "玩家"))
	if peer_name == "":
		peer_name = "玩家"
	if proto != NetProtocolScript.PROTO_VERSION:
		_send(peer_id, {
			"type": NetProtocolScript.MSG_REJECTED, "seq": 0,
			"code": NetProtocolScript.ERR_BAD_EVENT, "detail": "协议版本不一致",
		})
		error_raised.emit(NetProtocolScript.ERR_BAD_EVENT,
			"协议版本不一致：对端 %d / 本端 %d" % [proto, NetProtocolScript.PROTO_VERSION])
		return

	# 同一个 peer 重复 hello：幂等忽略，不重复占座
	var known := seat_of_peer(peer_id)
	if known != WATCHER_SEAT and seat_is_online(known):
		return

	var token := String(msg.get("token", ""))

	# ① token 命中且该座位处于掉线保留期 → 恢复原座位
	var resume_seat := _seat_of_token_if_offline(token)
	if resume_seat != WATCHER_SEAT:
		_bind_peer(peer_id, resume_seat, peer_name, token)   # 内含 peer_joined 广播
		_send_welcome(peer_id, resume_seat, token, true, peer_name)
		return

	# ② 新面孔：只在对局开始前占座
	var seat := _assign_new_seat()
	if seat == WATCHER_SEAT:
		if not allow_watchers:
			_send(peer_id, {
				"type": NetProtocolScript.MSG_REJECTED, "seq": 0,
				"code": NetProtocolScript.ERR_ROOM_FULL, "detail": "房间已满",
			})
			return
		# 观战者：拿到 WATCHER_SEAT，只收广播不能操作，不发重连凭据
		_peer_seat[peer_id] = WATCHER_SEAT
		_send_welcome(peer_id, WATCHER_SEAT, "", false, peer_name)
		return

	var new_token := _new_token()
	_bind_peer(peer_id, seat, peer_name, new_token)
	_send_welcome(peer_id, seat, new_token, false, peer_name)


# token 命中且座位离线 → 返回原座位号；否则 WATCHER_SEAT
func _seat_of_token_if_offline(token: String) -> int:
	if token == "" or not _token_seat.has(token):
		return WATCHER_SEAT
	var seat := int(_token_seat[token])
	if seat == WATCHER_SEAT:
		return WATCHER_SEAT
	if int(_seat_state.get(seat, SeatState.OFFLINE)) != SeatState.OFFLINE:
		return WATCHER_SEAT       # 座位已被人占着 → 不许顶号
	return seat


# 空座位分配：对局开始后不再接纳新玩家（避免座位表与 GameManager 玩家数错位）
func _assign_new_seat() -> int:
	if state != State.LOBBY:
		return WATCHER_SEAT
	for i in range(max_players):
		if not _seat_state.has(i) or int(_seat_state[i]) == SeatState.EMPTY:
			return i
	return WATCHER_SEAT


func _bind_peer(peer_id: int, seat: int, peer_name: String, token: String) -> void:
	_peer_seat[peer_id] = seat
	if seat == WATCHER_SEAT:
		return
	_seat_peer[seat] = peer_id
	_seat_name[seat] = peer_name
	_seat_token[seat] = token
	_token_seat[token] = seat
	_seat_state[seat] = SeatState.ONLINE
	_offline_deadline.erase(seat)
	_ready_seats[seat] = false
	room_changed.emit()
	# 广播给房间里所有人（含刚加入者自己，无害）：
	# 只发 welcome 的话，大厅里已经坐下的人永远看不到新玩家 —— 座位表和
	# 玩家列表会一直缺人，直到下一次 snapshot/game_start 才补上。
	_broadcast({
		"type": NetProtocolScript.MSG_PEER_JOINED,
		"seat": seat,
		"name": peer_name,
	})
	peer_joined.emit(seat, peer_name)


# ---- 主机：welcome（+ 已开局时紧跟一条 snapshot）----
func _send_welcome(to_peer: int, seat: int, token: String, resume: bool,
		peer_name: String) -> void:
	var welcome := {
		"type": NetProtocolScript.MSG_WELCOME,
		"proto": NetProtocolScript.PROTO_VERSION,
		"seat": seat,
		"token": token,
		"name": peer_name,
		"room_code": room_code,
		"resume": resume,
		"max_players": max_players,
		"started": state != State.LOBBY,
		"seats": _seat_list(),
		"config": _config,
	}
	if resume and pending_seat() != WATCHER_SEAT:
		# 只告知剩余时间，不重置计时 —— 否则断线就能无限拖延
		welcome["pending"] = {"seat": pending_seat(), "remain_ms": _pending_remain_ms()}
	_send(to_peer, welcome)
	if state != State.LOBBY:
		_send(to_peer, _make_snapshot_msg())


func _seat_list() -> Array:
	var out: Array = []
	for key in _seat_state.keys():
		var s := int(key)
		out.append({
			"seat": s,
			"name": String(_seat_name.get(s, "")),
			"online": int(_seat_state[s]) == SeatState.ONLINE,
			"is_host": s == 0,
		})
	out.sort_custom(func(a, b): return int(a["seat"]) < int(b["seat"]))
	return out


# 中途加入 / 重连 / 失配修复的统一恢复包。
# 客人用「同 seed init_game + replay_events(event_log)」重建 —— 不做快照反序列化，
# 因为 GameManager 只有 to_snapshot()，且 hash 里含日志条数，快照补不回来。
func _make_snapshot_msg() -> Dictionary:
	return {
		"type": NetProtocolScript.MSG_SNAPSHOT,
		"seed": _seed,
		"player_count": _player_count,
		"ai_count": _ai_count,
		"config": _config,
		"event_log": game.event_log.duplicate(true),
		"hash": game.state_hash(),
		"seats": _seat_list(),
		"pending_seat": pending_seat(),
		"remain_ms": _pending_remain_ms(),
	}


func _pending_remain_ms() -> int:
	if pending_seat() == WATCHER_SEAT:
		return 0
	return maxi(0, int(_pending.get("deadline", 0)) - Time.get_ticks_msec())


# ============================================================
# 五、客人侧：welcome / snapshot
# ============================================================
func _client_on_welcome(peer_id: int, msg: Dictionary) -> void:
	if peer_id != HOST_PEER_ID:
		return                       # 座位只能由主机分配，别人说了不算
	my_seat = int(msg.get("seat", WATCHER_SEAT))
	var new_token := String(msg.get("token", ""))
	if new_token != "":
		_my_token = new_token
	room_code = String(msg.get("room_code", ""))
	max_players = int(msg.get("max_players", DEFAULT_MAX_PLAYERS))
	_take_config(msg.get("config", null))
	_sync_seat_list(msg.get("seats", []))
	_pending_seat = WATCHER_SEAT
	var pend = msg.get("pending", null)
	if pend is Dictionary:
		_pending_seat = int(pend.get("seat", WATCHER_SEAT))
		sequence_pending.emit(_pending_seat, int(pend.get("remain_ms", 0)))
	# 未开局 → 待在房间；已开局 → 紧跟的 snapshot 会把它建成 PLAYING
	if state != State.PLAYING:
		state = State.LOBBY
	room_changed.emit()
	seat_assigned.emit(my_seat)
	if my_seat == WATCHER_SEAT:
		_send_ready()                # 观战者没有基准 hash，只确认「welcome 已收到」


func _sync_seat_list(list) -> void:
	if not (list is Array) or list.is_empty():
		return                      # 空表一律不动：宁可保留旧座位表，也别清空
	_seat_state.clear()
	_seat_name.clear()
	for item in list:
		if not (item is Dictionary):
			continue
		var s := int(item.get("seat", WATCHER_SEAT))
		if s == WATCHER_SEAT:
			continue
		_seat_state[s] = SeatState.ONLINE if bool(item.get("online", true)) else SeatState.OFFLINE
		_seat_name[s] = String(item.get("name", ""))


# 快照重建 = 同 seed init_game + 重放 event_log。
# 连日志条数一起重建，所以 state_hash() 里的 logs 计数也能与主机对齐 ——
# 这正是「用 to_snapshot() 反序列化」做不到的（GameManager 也没有那个函数）。
func _client_on_snapshot(msg: Dictionary) -> void:
	_seed = int(msg.get("seed", -1))
	_player_count = int(msg.get("player_count", _player_count))
	_ai_count = int(msg.get("ai_count", _ai_count))
	_take_config(msg.get("config", null))
	if _seed < 0 or not _apply_config_and_init():
		error_raised.emit(NetProtocolScript.ERR_DESYNC, "快照重建：init_game 失败")
		return
	var events = msg.get("event_log", [])
	if not (events is Array):
		events = []
	var applied: int = int(game.replay_events(events))
	if applied < 0:
		error_raised.emit(NetProtocolScript.ERR_DESYNC,
			"快照重建失败（重放返回 %d，共 %d 条）" % [applied, events.size()])
		return
	_last_hash = game.state_hash()
	_sync_seat_list(msg.get("seats", []))
	_sync_pending_from(msg)
	state = State.PLAYING
	room_changed.emit()
	game_started.emit()
	_send_ready()
	var host_hash := int(msg.get("hash", 0))
	if host_hash != 0 and _last_hash != host_hash:
		_desync_detected(host_hash)


func _sync_pending_from(msg: Dictionary) -> void:
	_pending_seat = int(msg.get("pending_seat", WATCHER_SEAT))
	if _pending_seat == WATCHER_SEAT:
		sequence_cleared.emit()
	else:
		sequence_pending.emit(_pending_seat, int(msg.get("remain_ms", 0)))


# 告知主机「我这边已经重建完，指纹是这个」——主机据此确认重连/加入成功
func _send_ready() -> void:
	_send(HOST_PEER_ID, {
		"type": NetProtocolScript.MSG_READY,
		"seat": my_seat,
		"hash": _last_hash,
		# 报「这个指纹对应第几笔事件」。只报 hash 不够用：主机收到 ready 时
		# 自己可能已经多打了几笔，拿旧指纹比新局面必然误报 -109（实测过）。
		"events": _local_event_count(),
	})


func _local_event_count() -> int:
	if game == null:
		return 0
	return game.event_log.size()



# ---- 客人：房间事件 / 拒绝 / 两阶段通知 ----
func _client_on_peer_left(msg: Dictionary) -> void:
	var seat := int(msg.get("seat", WATCHER_SEAT))
	if seat == WATCHER_SEAT:
		return
	_seat_state[seat] = SeatState.OFFLINE
	room_changed.emit()
	peer_left.emit(seat, String(msg.get("name", seat_name(seat))),
		int(msg.get("grace_ms", reconnect_grace_ms)))


func _client_on_peer_joined(msg: Dictionary) -> void:
	var seat := int(msg.get("seat", WATCHER_SEAT))
	if seat == WATCHER_SEAT:
		return
	_seat_state[seat] = SeatState.ONLINE
	var nm := String(msg.get("name", ""))
	if nm != "":
		_seat_name[seat] = nm
	room_changed.emit()
	peer_joined.emit(seat, seat_name(seat))


func _client_on_rejected(msg: Dictionary) -> void:
	var seq := int(msg.get("seq", 0))
	var code := int(msg.get("code", 0))
	if code == NetProtocolScript.ERR_ROOM_FULL:
		close("房间已满，无法加入")
		return
	intent_rejected.emit(seq, code)


func _client_on_pending_sequence(msg: Dictionary) -> void:
	var seat := int(msg.get("seat", WATCHER_SEAT))
	if seat == WATCHER_SEAT:
		_pending_seat = WATCHER_SEAT
		sequence_cleared.emit()
		return
	_pending_seat = seat
	sequence_pending.emit(seat, int(msg.get("remain_ms", 0)))


# ============================================================
# 六、开局（仅主机）
# ============================================================
# 房主点「开始」：定配置 + 定 seed → 本地 init_game → 广播 game_start
func start_game(player_count: int = 4, ai_count: int = 0) -> int:
	if role != Role.HOST or state != State.LOBBY or game == null:
		return -1
	_player_count = clampi(player_count, 2, 4)
	_ai_count = clampi(ai_count, 0, _player_count - 1)
	_config = _make_config()
	if not _apply_config_and_init():
		return -1
	state = State.PLAYING
	_last_hash = game.state_hash()
	_broadcast({
		"type": NetProtocolScript.MSG_GAME_START,
		"seed": _seed,
		"player_count": _player_count,
		"ai_count": _ai_count,
		"config": _config,
		"seats": _seat_list(),
		"hash": _last_hash,
	})
	room_changed.emit()
	game_started.emit()
	return 0


# 影响 generate_deck 的开关必须两端完全一致，否则牌库 uid 与牌序全错
func _make_config() -> Dictionary:
	return {
		"element_limit_enabled": bool(game.element_limit_enabled),
		"allowed_extra_elements": game.allowed_extra_elements.duplicate(),
		"organic_rules_enabled": bool(game.organic_rules_enabled),
		"sequence_rules_enabled": bool(game.sequence_rules_enabled),
		"halogen_exchange_allowed": bool(game.halogen_exchange_allowed),
	}


# 配置字典只在两端搬：逐键手抄，避免「Variant 赋给 Dictionary」的运行时类型错
func _take_config(cfg) -> void:
	if not (cfg is Dictionary):
		return
	_config.clear()
	for k in cfg:
		_config[k] = cfg[k]


func _apply_config() -> void:
	if game == null or _config.is_empty():
		return
	game.element_limit_enabled = bool(_config.get("element_limit_enabled", false))
	var extra = _config.get("allowed_extra_elements", [])
	game.allowed_extra_elements = extra.duplicate() if extra is Array else []
	game.organic_rules_enabled = bool(_config.get("organic_rules_enabled", false))
	game.sequence_rules_enabled = bool(_config.get("sequence_rules_enabled", false))
	game.halogen_exchange_allowed = bool(_config.get("halogen_exchange_allowed", false))


func _apply_config_and_init() -> bool:
	_apply_config()
	if _seed < 0 or game == null:
		return false
	if not game.init_game(_player_count, _ai_count, _seed):
		return false
	_last_hash = game.state_hash()
	return true


# 种子必须 >= 0 才会走确定性洗牌（GameManager 里 <0 表示「随机」）
func _make_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483646)


# 重连凭据：与规则无关，用真随机（不参与 hash，不进 event_log）
func _new_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


# ============================================================
# 七、动作提交（上层 ActionRouter 的唯一入口）
# ============================================================
func _send(to_peer: int, msg: Dictionary) -> void:
	if transport == null:
		return
	transport.send_to(to_peer, NetProtocolScript.encode(msg))


func _broadcast(msg: Dictionary) -> void:
	if transport == null:
		return
	transport.broadcast(NetProtocolScript.encode(msg))


# 提交一笔意图：主机当场裁决并广播，客人发给主机等 applied
# 返回：主机 = 规则码（0 / 1 / -1..-8 / -100 / -101）；客人 = 0 表示已发出
func submit(intent_type: String, payload: Dictionary = {}) -> int:
	if state != State.PLAYING or game == null:
		return NetProtocolScript.ERR_NOT_READY
	if _desynced:
		return NetProtocolScript.ERR_DESYNC
	if is_watcher():
		return NetProtocolScript.ERR_NOT_READY
	var ev := NetProtocolScript.make_intent(intent_type, my_seat, payload)
	if role == Role.HOST:
		var code := _validate_for_seat(my_seat, ev)
		if code != 0:
			return code
		return _host_apply(my_seat, ev)
	_my_seq += 1
	_send(HOST_PEER_ID, {
		"type": NetProtocolScript.MSG_INTENT,
		"seq": _my_seq,
		"ev": ev,
	})
	return 0


# 两阶段：指定「下一个必须打出的牌型」
func submit_sequence(pattern: int) -> int:
	return submit(NetProtocolScript.INTENT_SEQUENCE_PICK, {"pattern": pattern})


# 两阶段：跳过指定
func skip_sequence() -> int:
	return submit(NetProtocolScript.INTENT_SEQUENCE_SKIP)


# ============================================================
# 八、主机：意图校验 + 权威执行
# ============================================================
func _host_on_intent(peer_id: int, msg: Dictionary) -> void:
	var seat := seat_of_peer(peer_id)
	var seq := int(msg.get("seq", 0))
	if seat == WATCHER_SEAT:
		_reject(peer_id, seq, NetProtocolScript.ERR_NOT_READY)   # 观战者不许操作
		return
	if seq <= int(_last_seq.get(seat, 0)):
		_reject(peer_id, seq, NetProtocolScript.ERR_DUPLICATE_SEQ)
		return
	if state != State.PLAYING:
		_reject(peer_id, seq, NetProtocolScript.ERR_NOT_READY)
		return
	var ev = msg.get("ev", null)
	if not (ev is Dictionary):
		_reject(peer_id, seq, NetProtocolScript.ERR_BAD_EVENT)
		return
	var code := _validate_for_seat(seat, ev)
	if code != 0:
		_reject(peer_id, seq, code)
		return
	_last_seq[seat] = seq
	var result := _host_apply(seat, ev)
	if result < 0:
		_reject(peer_id, seq, result)


# 主机侧校验：两阶段优先于普通回合校验
func _validate_for_seat(seat: int, ev: Dictionary) -> int:
	var intent_type := String(ev.get("type", ""))
	if not (intent_type in NetProtocolScript.INTENT_TYPES):
		return NetProtocolScript.ERR_BAD_EVENT
	if int(ev.get("by", -1)) != seat:
		return NetProtocolScript.ERR_WRONG_SEAT          # 谁也不许替别人出牌
	var pend := pending_seat()
	if pend != WATCHER_SEAT:
		# 两阶段冻结：牌权已移交但约束还没定，此时只接受「本人指定/跳过」
		if seat != pend:
			return NetProtocolScript.ERR_NOT_YOUR_TURN
		if not NetProtocolScript.is_sequence_intent(intent_type):
			return NetProtocolScript.ERR_BAD_EVENT
		return 0
	if NetProtocolScript.is_sequence_intent(intent_type):
		return NetProtocolScript.ERR_NO_PENDING
	return NetProtocolScript.validate_intent(ev, seat, _player_count,
		game.current_player_index, game.is_game_over())


# 权威执行：成功 → 更新指纹 + 广播 applied + 维护两阶段；失败 → 原样返回规则码
func _host_apply(seat: int, ev: Dictionary) -> int:
	var result: int = int(game.apply_event(ev))
	if result < 0:
		return result
	_last_hash = game.state_hash()
	_broadcast({
		"type": NetProtocolScript.MSG_APPLIED,
		"by": seat,
		"result": result,
		"ev": ev,
		"hash": _last_hash,
	})
	_update_pending_after_apply(seat, result)
	state_applied.emit(ev, result)
	if game.is_game_over():
		state = State.OVER
	return result


# 两阶段状态机：result == 1（打出顺序牌）→ 开等待窗口；本人结算完 → 关闭
func _update_pending_after_apply(seat: int, result: int) -> void:
	var was := pending_seat()
	if result == 1:
		_pending = {
			"seat": seat,
			"seq": 0,
			"deadline": Time.get_ticks_msec() + maxi(1, pending_sequence_timeout_ms),
		}
		_broadcast({
			"type": NetProtocolScript.MSG_PENDING_SEQUENCE,
			"seat": seat,
			"remain_ms": _pending_remain_ms(),
		})
		return
	if was != WATCHER_SEAT and seat == was:
		_pending.clear()
		_broadcast({
			"type": NetProtocolScript.MSG_PENDING_SEQUENCE,
			"seat": WATCHER_SEAT,
			"remain_ms": 0,
		})
		sequence_cleared.emit()


func _reject(peer_id: int, seq: int, code: int) -> void:
	_send(peer_id, {
		"type": NetProtocolScript.MSG_REJECTED,
		"seq": seq,
		"code": code,
	})


# ============================================================
# 九、客人侧：开局 / 权威事件回放
# ============================================================
func _client_on_game_start(msg: Dictionary) -> void:
	_seed = int(msg.get("seed", -1))
	_player_count = int(msg.get("player_count", 4))
	_ai_count = int(msg.get("ai_count", 0))
	_take_config(msg.get("config", null))
	if _seed < 0 or not _apply_config_and_init():
		error_raised.emit(NetProtocolScript.ERR_DESYNC, "开局：init_game 失败")
		return
	_sync_seat_list(msg.get("seats", []))
	_pending_seat = WATCHER_SEAT
	state = State.PLAYING
	_last_hash = game.state_hash()
	_send_ready()
	room_changed.emit()
	game_started.emit()
	var host_hash := int(msg.get("hash", 0))
	if host_hash != 0 and _last_hash != host_hash:
		_desync_detected(host_hash)


# 客人：重放主机广播的权威事件。
# 任何一步失败或指纹不符 → 立刻标记分叉并停止推进（绝不带病继续）。
func _client_on_applied(msg: Dictionary) -> void:
	if state != State.PLAYING or game == null:
		return
	var ev = msg.get("ev", null)
	if not (ev is Dictionary):
		return
	var result: int = int(game.apply_event(ev))
	_last_hash = game.state_hash()
	var host_hash := int(msg.get("hash", 0))
	if result < 0:
		_desync_detected(host_hash)
		return
	if host_hash != 0 and _last_hash != host_hash:
		_desync_detected(host_hash)
		return
	state_applied.emit(ev, int(msg.get("result", result)))
	if game.is_game_over():
		state = State.OVER


func _desync_detected(host_hash: int) -> void:
	if _desynced:
		return
	_desynced = true
	desync_detected.emit(_last_hash, host_hash)


# ============================================================
# 十、主机侧：ready 确认
# ============================================================
func _host_on_ready(peer_id: int, msg: Dictionary) -> void:
	var seat := seat_of_peer(peer_id)
	if seat == WATCHER_SEAT:
		return
	_ready_seats[seat] = true
	var client_hash := int(msg.get("hash", -1))
	var client_events := int(msg.get("events", -1))
	# 只在「对端报的进度 == 主机此刻的进度」时才比对指纹。
	# 为什么：ready 是快照重放完成那一刻发出的，等主机 poll 到它，主机很可能
	# 已经多打了几笔事件；拿旧指纹比新局面会稳定误报 -109（真机冒烟实测）。
	# 真正逐笔把关的是客人侧 _client_on_applied 里的事件后比对，这里只是兜底。
	if state == State.PLAYING and client_hash > 0 and game != null \
			and client_events == game.event_log.size():
		var host_hash: int = int(game.state_hash())
		if client_hash != host_hash:
			error_raised.emit(NetProtocolScript.ERR_DESYNC,
				"座位 %d 重建后指纹不一致（对端 %d / 主机 %d，第 %d 笔）"
				% [seat, client_hash, host_hash, client_events])



# 所有人类座位是否都已就绪（开局前的硬前置）
func all_seats_ready() -> bool:
	if role != Role.HOST:
		return true
	for key in _seat_state.keys():
		var s := int(key)
		if int(_seat_state[s]) != SeatState.ONLINE:
			continue
		if is_seat_ai(s):
			continue
		if not bool(_ready_seats.get(s, false)):
			return false
	return true


# ============================================================
# 十一、掉线 / 重连 / 超时（仅主机裁决）
# ============================================================
# 某座位掉线 → 标 OFFLINE、保留座位与 token、广播，必要时立刻托管两阶段
func _handle_seat_offline(seat: int) -> void:
	if seat == WATCHER_SEAT:
		return
	_seat_state[seat] = SeatState.OFFLINE
	_offline_deadline[seat] = Time.get_ticks_msec() + maxi(1000, reconnect_grace_ms)
	_ready_seats[seat] = false
	room_changed.emit()
	_broadcast({
		"type": NetProtocolScript.MSG_PEER_LEFT,
		"seat": seat,
		"name": seat_name(seat),
		"grace_ms": reconnect_grace_ms,
	})
	peer_left.emit(seat, seat_name(seat), reconnect_grace_ms)
	# 掉的正是两阶段里被等的那个座位 → 不干等，按「跳过」托管，牌权立刻流转
	if pending_seat() == seat:
		_take_over_pending(seat)


# 主机代替 seat 结束两阶段（超时 / 掉线共用）
func _take_over_pending(seat: int) -> void:
	var ev := NetProtocolScript.make_intent(NetProtocolScript.INTENT_SEQUENCE_SKIP, seat)
	var code := _host_apply(seat, ev)
	if code >= 0:
		return
	# 跳过也被拒（极端情况）：强制关窗，宁可少一条规则也不能让整局卡死
	_pending.clear()
	_broadcast({
		"type": NetProtocolScript.MSG_PENDING_SEQUENCE,
		"seat": WATCHER_SEAT,
		"remain_ms": 0,
	})
	sequence_cleared.emit()
	error_raised.emit(code, "两阶段托管失败，已强制放行")


# 主机每帧检查：① 两阶段超时 → 托管；② 掉线宽限到期 → 清计时器（座位仍保留）
func _poll_timeouts() -> void:
	if role != Role.HOST:
		return
	var now := Time.get_ticks_msec()
	if state == State.PLAYING and pending_seat() != WATCHER_SEAT \
			and int(_pending.get("deadline", 0)) <= now:
		_take_over_pending(pending_seat())
	# 宽限到期只是不再提示，座位与 token 一直留着，重连随时能回来（见 R11）
	for key in _offline_deadline.keys():
		if int(_offline_deadline[key]) <= now:
			_offline_deadline.erase(key)


# ============================================================
# 十二、收尾
# ============================================================
# 对局结束后回到房间态评估：这里只提供查询，切状态由 UI 决定
func is_over() -> bool:
	return state == State.OVER


func closed_reason() -> String:
	return _closed_reason












