# 验证联机会话层（P11-C1-b NetSession）
#   覆盖：握手/座位分配、peer↔seat 映射、开局同步、意图裁决与广播、
#         两阶段（指定牌型）冻结、超时托管、掉线座位保留、token 重连、观战与满员拒绝。
#
# 为什么用真实 ENet 而不是 Loopback：Loopback 只能一对一，测不了「三方 gossip」，
# 也测不出「客人 peer_id 是随机大整数」这个真实约束。
# 每个端点持有**独立的 GameManager 实例**：断言里的「指纹一致」是真两端各自
# 重放出来的，不是共享同一个对象糊弄过去的。
#
# 注意：ENet 客户端 close() 之后不能立刻 quit()（引擎会卡在退出阶段，测试全 PASS
#       但进程不退）。_finish() 里因此留了 600ms，详见
#       MULTIPLAYER_ARCHITECTURE.md 附录 C.5。
#
# 运行：godot --headless --path . --script tests/verify_net_session.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")

const PORT_MAIN = 47821
const PORT_FULL = 47824
const PORT_AI = 47826            # G19 专用端口（47821/47824 已被 G1/G17 占用）
const PORT_CAP8 = 47830          # G21：8 座位房间
const PORT_CAP3 = 47832          # G21：下限 3 座位房间
const PORT_LOBBY = 47834         # G22：大厅 AI 补位数（D19）
const PORT_BYE = 47836           # G23：房主收房广播（D20）
const PORT_BYE2 = 47837          # G23②：房主真关服（bye 可能丢）
const PORT_HB = 47838            # G24：心跳超时（D21）
const CONNECT_TIMEOUT_MS = 5000
const IO_TIMEOUT_MS = 3000
const PLAYER_COUNT = 3          # seat 0 = 房主，1 = 客人A，2 = 客人B

var fails: int = 0
var checks: int = 0
var events: Array = []          # 所有信号先落这里，便于事后按端点断言
var _log: FileAccess = null     # 逐行刷盘：headless 下 stdout 是块缓冲，
                                # 长跑测试如果中途卡住，重定向文件里啥都看不到。
                                # 写 user://（不进仓库），跑完可直接删。

func _init() -> void:
	_log = FileAccess.open("user://net_session_test.log", FileAccess.WRITE)
	call_deferred("_run")


func _log_line(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		_log_line("PASS: " + msg)
	else:
		fails += 1
		_log_line("FAIL: " + msg)


func _finish() -> void:
	if fails == 0:
		_log_line("ALL NET SESSION TESTS PASSED (%d checks)" % checks)
	else:
		_log_line("%d/%d NET SESSION TESTS FAILED" % [fails, checks])
	if _log != null:
		_log.flush()
		_log = null
	# ENet 客户端 close() 之后底层收尾是异步的：立刻 quit() 会让引擎卡死
	# 在退出阶段（测试全 PASS，但进程不退，CI 里表现为挂起 / 超时）。
	# 实测最小复现：host+join 后马上 close 再 quit → 永不退出；
	# 中间留几百毫秒 → 正常退出。这里统一留一小段。
	OS.delay_msec(600)
	quit(1 if fails > 0 else 0)


# ---- 工具 ----
# 端点 = 一个 transport + 一个 session + 一个独立 GameManager
func _make_peer(tag: String) -> Dictionary:
	var gm = GameManagerScript.new()
	var tr = ENetTransportScript.new()
	var s = NetSessionScript.new()
	s.setup(gm, tr)
	_hook(tag, s)
	return {"tag": tag, "gm": gm, "tr": tr, "s": s}


func _hook(tag: String, s) -> void:
	s.seat_assigned.connect(func(seat): events.append({"t": tag, "k": "seat", "seat": int(seat)}))
	s.game_started.connect(func(): events.append({"t": tag, "k": "started"}))
	s.state_applied.connect(func(ev, r):
		events.append({"t": tag, "k": "applied", "type": String(ev.get("type", "")),
			"by": int(ev.get("by", -1)), "result": int(r)}))
	s.intent_rejected.connect(func(seq, code):
		events.append({"t": tag, "k": "rejected", "seq": int(seq), "code": int(code)}))
	s.sequence_pending.connect(func(seat, ms):
		events.append({"t": tag, "k": "pending", "seat": int(seat), "ms": int(ms)}))
	s.sequence_cleared.connect(func(): events.append({"t": tag, "k": "cleared"}))
	s.desync_detected.connect(func(l, h):
		events.append({"t": tag, "k": "desync", "local": int(l), "host": int(h)}))
	s.peer_left.connect(func(seat, nm, g):
		events.append({"t": tag, "k": "left", "seat": int(seat), "name": String(nm)}))
	s.peer_joined.connect(func(seat, nm):
		events.append({"t": tag, "k": "joined", "seat": int(seat), "name": String(nm)}))
	s.session_closed.connect(func(reason):
		events.append({"t": tag, "k": "closed", "reason": String(reason)}))
	s.error_raised.connect(func(code, detail):
		events.append({"t": tag, "k": "error", "code": int(code), "detail": String(detail)}))


# 没有帧循环：手动 pump 所有端点直到条件满足或超时
func _pump(peers: Array, cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for p in peers:
			p["s"].poll()
		if bool(cond.call()):
			return true
		OS.delay_msec(3)
	return false


func _ev(tag: String, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if String(e["t"]) == tag and String(e["k"]) == kind:
			out.append(e)
	return out


func _count(tag: String, kind: String) -> int:
	return _ev(tag, kind).size()


# 某座位手牌的第一张 uid（首手任意单张都是合法单质）
func _first_uid(gm, seat: int) -> int:
	if seat < 0 or seat >= gm.players.size():
		return -1
	for c in gm.players[seat].hand:
		return int(c.uid)
	return -1


# 追踪缓冲末行的指纹段（"hash=xxxxxxxx" 之后的 8 位）；空缓冲 → ""
func _trace_hash_tail(s) -> String:
	if s.trace_log.is_empty():
		return ""
	var line := String(s.trace_log[s.trace_log.size() - 1])
	var at := line.find("hash=")
	if at < 0:
		return ""
	return line.substr(at + 5, 8)


# ============================================================
# 主流程
# ============================================================
func _run() -> void:
	var host = _make_peer("host")
	var c1 = _make_peer("c1")
	var c2 = _make_peer("c2")
	var peers := [host, c1, c2]

	# ---- G1 房间建立 / 座位分配 ----
	_check(int(host["s"].start_host(PORT_MAIN, PLAYER_COUNT, "房主")) == 0,
		"G1 房主监听 %d 成功" % PORT_MAIN)
	_check(host["s"].state == NetSessionScript.State.LOBBY, "G1 房主进入 LOBBY")
	_check(host["s"].my_seat == 0, "G1 房主座位 = 0")
	_check(host["s"].room_code.length() == 4, "G1 房号是 4 位数字（%s）" % host["s"].room_code)

	_check(int(c1["s"].start_client("127.0.0.1", PORT_MAIN, "客人A")) == 0, "G1 客人A 发起连接")
	_check(int(c2["s"].start_client("127.0.0.1", PORT_MAIN, "客人B")) == 0, "G1 客人B 发起连接")

	var seated := _pump(peers, func(): return c1["s"].my_seat == 1 and c2["s"].my_seat == 2, CONNECT_TIMEOUT_MS)
	_check(seated, "G1 两台客人按顺序拿到座位")
	_check(c1["s"].my_seat == 1, "G1 客人A 座位 = 1")
	_check(c2["s"].my_seat == 2, "G1 客人B 座位 = 2")
	_check(host["s"].seat_is_online(1) and host["s"].seat_is_online(2), "G1 主机端座位 1/2 均为 ONLINE")
	_check(_count("c1", "seat") >= 1, "G1 客人A 收到 seat_assigned")

	# ---- G2 peer_id 与座位解耦 ----
	var p1: int = int(c1["tr"].local_id)
	var p2: int = int(c2["tr"].local_id)
	_check(p1 > 1 and p2 > 1, "G2 客人 peer_id 是随机大整数（%d / %d），不是座位号" % [p1, p2])
	_check(p1 != p2, "G2 两个客人 peer_id 互不相同")
	_check(host["s"].seat_of_peer(p1) == 1, "G2 peer→seat：客人A 的 peer 映射到座位 1")
	_check(host["s"].peer_of_seat(1) == p1, "G2 seat→peer：座位 1 映射回客人A 的 peer")
	_check(host["s"].seat_of_peer(999999) == NetSessionScript.WATCHER_SEAT, "G2 未知 peer → WATCHER_SEAT(-1)")

	# ---- G3 房间信息同步 ----
	_check(c1["s"].room_code == host["s"].room_code, "G3 房号同步（%s）" % c1["s"].room_code)
	_check(c1["s"].max_players == host["s"].max_players, "G3 人数上限同步 = %d" % c1["s"].max_players)
	_check(c1["s"].seat_name(0) == "房主", "G3 客人看到房主昵称")
	_pump(peers, func(): return c1["s"].seat_count() >= 3, IO_TIMEOUT_MS)
	_check(c1["s"].seat_count() >= 3, "G3 客人端座位表有 3 个座位（实得 %d）" % c1["s"].seat_count())
	_check(c1["s"].state == NetSessionScript.State.LOBBY, "G3 未开局时客人处于 LOBBY")

	# ---- G4 重复 hello 幂等 ----
	var seats_before: int = host["s"].seat_count()
	var token_before := String(host["s"]._seat_token.get(1, ""))
	c1["s"]._send_hello(NetSessionScript.HOST_PEER_ID)      # 模拟弱网重发 hello
	_pump(peers, func(): return false, 200)
	_check(host["s"].seat_count() == seats_before, "G4 重复 hello 不新增座位")
	_check(String(host["s"]._seat_token.get(1, "")) == token_before, "G4 重复 hello 不换发 token")
	_check(c1["s"].my_seat == 1, "G4 客人座位不变")

	# ---- G5 开局：seed / 配置 / 指纹 ----
	_check(int(host["s"].start_game(PLAYER_COUNT, 0)) == 0, "G5 房主 start_game 成功")
	_check(host["s"].state == NetSessionScript.State.PLAYING, "G5 房主进入 PLAYING")
	_pump(peers, func(): return c1["s"].state == NetSessionScript.State.PLAYING and c2["s"].state == NetSessionScript.State.PLAYING, IO_TIMEOUT_MS)
	_check(c1["s"].state == NetSessionScript.State.PLAYING, "G5 客人A 进入 PLAYING")
	_check(c2["s"].state == NetSessionScript.State.PLAYING, "G5 客人B 进入 PLAYING")
	_check(_count("c1", "started") >= 1 and _count("c2", "started") >= 1, "G5 两端都收到 game_started")
	_check(c1["s"].last_hash() == host["s"].last_hash(), "G5 开局后客人A 指纹与主机一致")
	_check(c2["s"].last_hash() == host["s"].last_hash(), "G5 开局后客人B 指纹与主机一致")
	_check(c1["s"].game.event_log.is_empty(), "G5 开局时事件日志为空")
	_check(host["gm"].current_player_index == 0, "G5 首手轮到房主（座位 0）")

	# ---- G6 房主本地出牌：权威执行 + 广播 ----
	var uid0 := _first_uid(host["gm"], 0)
	_check(uid0 >= 0, "G6 房主手牌可读")
	var code0: int = int(host["s"].submit("play", {"uids": [uid0], "valences": {}, "pattern": -1}))
	_check(code0 == 0, "G6 房主出单张成功（返回 %d）" % code0)
	_pump(peers, func(): return _count("c1", "applied") >= 1 and _count("c2", "applied") >= 1, IO_TIMEOUT_MS)
	_check(_count("c1", "applied") == 1, "G6 客人A 收到 1 条 applied")
	_check(_count("c2", "applied") == 1, "G6 客人B 收到 1 条 applied")
	_check(c1["s"].last_hash() == host["s"].last_hash(), "G6 出牌后客人A 指纹与主机一致")
	_check(c2["s"].last_hash() == host["s"].last_hash(), "G6 出牌后客人B 指纹与主机一致")
	_check(c1["s"].game.event_log.size() == 1 and host["gm"].event_log.size() == 1, "G6 两端事件日志都只有 1 条")
	_check(host["gm"].current_player_index == 1, "G6 牌权轮到座位 1")

	# ---- G7 越位提交：主机拒绝，且不污染状态 ----
	var uid2 := _first_uid(c2["gm"], 2)
	var hash_before: int = host["s"].last_hash()
	_check(int(c2["s"].submit("play", {"uids": [uid2], "valences": {}, "pattern": -1})) == 0,
		"G7 客人B 的意图已发出（本地不做回合校验）")
	_pump(peers, func(): return _count("c2", "rejected") >= 1, IO_TIMEOUT_MS)
	var rej7 := _ev("c2", "rejected")
	_check(not rej7.is_empty() and int(rej7[0]["code"]) == NetProtocolScript.ERR_NOT_YOUR_TURN,
		"G7 主机拒绝越位提交（ERR_NOT_YOUR_TURN）")
	_check(host["s"].last_hash() == hash_before, "G7 被拒的意图不改变主机指纹")
	_check(host["gm"].event_log.size() == 1, "G7 被拒的意图不进事件日志")

	# ---- G8 客人正常提交：应用 + 三方一致 ----
	_check(int(c1["s"].submit("pass")) == 0, "G8 客人A 提交 pass")
	_pump(peers, func(): return _count("c1", "applied") >= 2 and _count("c2", "applied") >= 2, IO_TIMEOUT_MS)
	_check(_count("c1", "applied") >= 2, "G8 客人A 收到 pass 的 applied 广播")
	_check(_count("c2", "applied") >= 2, "G8 客人B 收到 pass 的 applied 广播")
	_check(c1["s"].last_hash() == host["s"].last_hash(), "G8 pass 后客人A 指纹一致")
	_check(c2["s"].last_hash() == host["s"].last_hash(), "G8 pass 后客人B 指纹一致")
	_check(host["gm"].event_log.size() == 2, "G8 主机事件日志 2 条")

	# ---- G9 伪造 by：谁也替不了别人出牌 ----
	c1["tr"].send_to(NetSessionScript.HOST_PEER_ID, NetProtocolScript.encode({
		"type": NetProtocolScript.MSG_INTENT,
		"seq": 100,
		"ev": {"type": "pass", "by": 0},
	}))
	_pump(peers, func(): return _count("c1", "rejected") >= 1, IO_TIMEOUT_MS)
	var rej9 := _ev("c1", "rejected")
	_check(rej9.size() >= 1 and int(rej9[rej9.size() - 1]["code"]) == NetProtocolScript.ERR_WRONG_SEAT,
		"G9 伪造 by 被拒（ERR_WRONG_SEAT）")
	_check(host["gm"].event_log.size() == 2, "G9 伪造意图不进事件日志")

	# ---- G10 重复 seq：重投同一笔意图只生效一次 ----
	var seq_dup := int(c1["s"]._my_seq)     # 客人A 已经用过的序号
	c1["tr"].send_to(NetSessionScript.HOST_PEER_ID, NetProtocolScript.encode({
		"type": NetProtocolScript.MSG_INTENT,
		"seq": 1,
		"ev": {"type": "pass", "by": 1},
	}))
	_pump(peers, func(): return _count("c1", "rejected") >= 2, IO_TIMEOUT_MS)
	var rej10 := _ev("c1", "rejected")
	_check(rej10.size() >= 2 and int(rej10[rej10.size() - 1]["code"]) == NetProtocolScript.ERR_DUPLICATE_SEQ,
		"G10 重复序号被拒（ERR_DUPLICATE_SEQ，曾用 seq=%d）" % seq_dup)

	# ---- G11 两阶段冻结：主机开窗 → 全网同步等待方 ----
	# 用 result=1 直接驱动状态机（真实触发要求手牌里恰好有顺序牌，测试不该赌手牌）
	host["s"]._update_pending_after_apply(1, 1)
	_pump(peers, func(): return c1["s"].pending_seat() == 1 and c2["s"].pending_seat() == 1, IO_TIMEOUT_MS)
	_check(host["s"].pending_seat() == 1, "G11 主机记下等待座位 1")
	_check(c1["s"].pending_seat() == 1, "G11 客人A 同步到等待座位 1")
	_check(c2["s"].pending_seat() == 1, "G11 客人B 同步到等待座位 1")
	_check(_count("c1", "pending") >= 1, "G11 客人A 收到 sequence_pending")
	_check(c1["s"].is_my_sequence_pending(), "G11 座位 1 是等待方 → is_my_sequence_pending = true")
	_check(not host["s"].is_my_sequence_pending(), "G11 房主（座位 0）不是等待方")
	_check(not c2["s"].can_submit(), "G11 两阶段窗口内普通操作被禁止")
	_check(host["s"]._pending_remain_ms() > 0, "G11 窗口带剩余时间（UI 可画倒计时）")

	# ---- G12 关窗 + 没有待处理时发 sequence_pick ----
	host["s"]._update_pending_after_apply(1, 0)
	_check(host["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, "G12 结算后窗口关闭")
	_pump(peers, func(): return c1["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, IO_TIMEOUT_MS)
	_check(c1["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, "G12 客人A 同步到窗口关闭")
	_check(int(c1["s"].submit_sequence(1)) == 0, "G12 客人A 的 sequence_pick 已发出")
	_pump(peers, func(): return _count("c1", "rejected") >= 3, IO_TIMEOUT_MS)
	var rej12 := _ev("c1", "rejected")
	_check(not rej12.is_empty() and int(rej12[rej12.size() - 1]["code"]) == NetProtocolScript.ERR_NO_PENDING,
		"G12 无待处理却指定牌型 → ERR_NO_PENDING")

	# ---- G13 超时托管：窗口到期后主机代替该座位跳过 ----
	host["s"].pending_sequence_timeout_ms = 60
	host["s"]._update_pending_after_apply(1, 1)
	_check(host["s"].pending_seat() == 1, "G13 重新打开两阶段窗口")
	var t0 := Time.get_ticks_msec()
	var timed_out := _pump(peers, func(): return host["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, 3000)
	_check(timed_out, "G13 超时后窗口被自动关闭（托管生效）")
	_check(Time.get_ticks_msec() - t0 < 2000, "G13 托管在超时附近触发，没有长等")
	_pump(peers, func(): return c1["s"].pending_seat() == NetSessionScript.WATCHER_SEAT and c2["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, IO_TIMEOUT_MS)
	_check(c1["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, "G13 客人A 同步到窗口关闭")
	_check(c1["s"].last_hash() == host["s"].last_hash(), "G13 托管后客人A 指纹仍一致")
	_check(c2["s"].last_hash() == host["s"].last_hash(), "G13 托管后客人B 指纹仍一致")
	_check(_count("c1", "cleared") >= 1, "G13 客人A 收到 sequence_cleared")

	# ---- G14 掉线：座位 / 昵称 / token 全部保留 ----
	var token_c1 := String(c1["s"].get_token())
	_check(token_c1.length() > 0, "G14 客人A 持有重连凭据（%d 字符 hex）" % token_c1.length())
	c1["tr"].close()
	var went_offline := _pump([host, c2], func(): return not host["s"].seat_is_online(1), CONNECT_TIMEOUT_MS)
	_check(went_offline, "G14 主机检测到座位 1 掉线")
	_check(host["s"].seat_name(1) == "客人A", "G14 掉线后昵称仍保留（座位没被回收）")
	_check(String(host["s"]._seat_token.get(1, "")) == token_c1, "G14 掉线后 token 保留，重连可复用")
	_pump([host, c2], func(): return _count("c2", "left") >= 1, IO_TIMEOUT_MS)
	_check(_count("host", "left") >= 1, "G14 主机本地发出 peer_left")
	_check(_count("c2", "left") >= 1, "G14 客人B 收到 peer_left 广播")
	_check(c1["tr"].get_peers().is_empty(), "G14 掉线方本端连接已断开（不再有对端）")

	# ---- G15 重连：token 身份复用 + 快照重建 ----
	_check(int(c1["s"].start_client_resume("127.0.0.1", PORT_MAIN, token_c1, "客人A")) == 0,
		"G15 客人A 带 token 重连")
	var resumed := _pump([host, c2, c1], func(): return c1["s"].state == NetSessionScript.State.PLAYING and host["s"].seat_is_online(1), CONNECT_TIMEOUT_MS)
	_check(resumed, "G15 重连完成并回到 PLAYING")
	_check(c1["s"].my_seat == 1, "G15 重连拿回原座位 1")
	_check(c1["s"].get_token() == token_c1, "G15 重连沿用同一 token（主机没换发）")
	_check(c1["s"].last_hash() == host["s"].last_hash(), "G15 重放后指纹与主机一致")
	_check(c1["s"].game.event_log.size() == host["gm"].event_log.size(),
		"G15 事件日志条数与主机一致（%d）" % host["gm"].event_log.size())
	_check(_count("c1", "started") >= 2, "G15 重连后重新触发 game_started（UI 可重建牌桌）")
	_check(_count("c2", "joined") >= 1, "G15 客人B 收到 peer_joined 广播")
	_check(not c1["s"].is_desynced(), "G15 重连全程未触发 desync")

	# ---- G16 观战：对局中首次加入只读 ----
	var c3 = _make_peer("c3")
	_check(int(c3["s"].start_client("127.0.0.1", PORT_MAIN, "观众")) == 0, "G16 第三位客人发起连接")
	var watching := _pump([host, c1, c2, c3], func(): return c3["s"].state == NetSessionScript.State.PLAYING, CONNECT_TIMEOUT_MS)
	_check(watching, "G16 观战者收到快照并进入 PLAYING")
	_check(c3["s"].my_seat == NetSessionScript.WATCHER_SEAT, "G16 对局中首次加入 → 观战（seat -1）")
	_check(c3["s"].is_watcher(), "G16 is_watcher() = true")
	_check(not c3["s"].can_submit(), "G16 观战者不能操作")
	_check(int(c3["s"].submit("pass")) == NetProtocolScript.ERR_NOT_READY, "G16 观战者提交意图被本地拒绝")
	_check(c3["s"].last_hash() == host["s"].last_hash(), "G16 观战者快照指纹与主机一致")
	_check(c3["s"].game.event_log.size() == host["gm"].event_log.size(), "G16 观战者日志条数一致")

	# ---- G17 满员 + 禁止观战 → 明确拒绝 ----
	# 容量下限是 3（D17），所以「满员」= 房主 + 2 客人，第 3 个客人才该被拒。
	var h2 = _make_peer("h2")
	var d1 = _make_peer("d1")
	var d2 = _make_peer("d2")
	var d3 = _make_peer("d3")
	h2["s"].allow_watchers = false
	_check(int(h2["s"].start_host(PORT_FULL, 3, "房主2")) == 0, "G17 第二个房间监听 %d" % PORT_FULL)
	_check(int(d1["s"].start_client("127.0.0.1", PORT_FULL, "D1")) == 0, "G17 第一个客人发起连接")
	_check(_pump([h2, d1], func(): return d1["s"].my_seat == 1, CONNECT_TIMEOUT_MS),
		"G17 第一个客人拿到座位 1")
	_check(int(d2["s"].start_client("127.0.0.1", PORT_FULL, "D2")) == 0, "G17 第二个客人发起连接")
	_check(_pump([h2, d1, d2], func(): return d2["s"].my_seat == 2, CONNECT_TIMEOUT_MS),
		"G17 第二个客人拿到座位 2（3 座位坐满）")
	_check(int(d3["s"].start_client("127.0.0.1", PORT_FULL, "D3")) == 0, "G17 第三个客人发起连接")
	var refused := _pump([h2, d1, d2, d3], func(): return d3["s"].state == NetSessionScript.State.CLOSED, CONNECT_TIMEOUT_MS)
	_check(refused, "G17 房间满 + 禁止观战 → 新客人被拒绝")
	_check(d3["s"].my_seat == NetSessionScript.WATCHER_SEAT, "G17 被拒的客人没有座位")
	_check(_count("d3", "closed") >= 1, "G17 被拒的客人收到 session_closed")
	_check(d1["s"].my_seat == 1, "G17 被拒事件不影响已有客人")

	# ---- G18 ready 比对的时序（真机三进程冒烟抓到的误报）----
	# 背景：ready 是「快照重放完那一刻」发出的，等主机 poll 到它，主机往往已经
	# 多打了几笔事件。老实现直接拿客户端旧指纹比主机新局面 → 每局开局必报
	# ERR_DESYNC。现在 ready 带 events，进度不同就只记 ready、不比对。
	var err_before := _count("host", "error")
	var bad_hash: int = int(host["gm"].state_hash()) + 1
	var ready_peer: int = host["s"].peer_of_seat(1)
	host["s"]._host_on_ready(ready_peer, {"hash": bad_hash, "events": 0})
	_check(_count("host", "error") == err_before,
		"G18 进度不同（对端 0 笔 / 主机 %d 笔）→ 不比对、不误报 -109"
		% host["gm"].event_log.size())
	host["s"]._host_on_ready(ready_peer, {"hash": bad_hash, "events": host["gm"].event_log.size()})
	_check(_count("host", "error") == err_before + 1, "G18 同一进度 + 指纹不同 → 照常报错")
	var errs18 := _ev("host", "error")
	_check(not errs18.is_empty() and int(errs18[errs18.size() - 1]["code"]) == NetProtocolScript.ERR_DESYNC,
		"G18 报的码是 ERR_DESYNC")
	host["s"]._host_on_ready(ready_peer, {"hash": 0, "events": 0})
	_check(_count("host", "error") == err_before + 1, "G18 hash=0（大厅 / 未初始化）不当分叉")

	# ---- G19 主机代 AI 座位动作（P11-C1-c Step 2 / 决策 D3）----
	# 独立房间：3 人 1 AI → 座位 0/1 是人，座位 2 是 AI
	# （is_seat_ai 的判定：seat >= player_count - ai_count）
	var h3 = _make_peer("h3")
	var e1 = _make_peer("e1")
	_check(int(h3["s"].start_host(PORT_AI, 3, "AI房主")) == 0, "G19 第三个房间监听 %d" % PORT_AI)
	_check(int(h3["s"].host_act_for_seat(2, "pass")) == NetProtocolScript.ERR_NOT_READY,
		"G19 未开局时代打 → ERR_NOT_READY")
	_check(int(h3["s"].host_step_ai()) == 0, "G19 未开局时 host_step_ai 返回 0")
	_check(int(e1["s"].start_client("127.0.0.1", PORT_AI, "AI客人")) == 0, "G19 真人客人发起连接")
	_check(_pump([h3, e1], func(): return e1["s"].my_seat == 1, CONNECT_TIMEOUT_MS),
		"G19 真人客人拿到座位 1")
	_check(int(h3["s"].start_game(3, 1)) == 0, "G19 start_game(3, 1) 成功（座位 2 = AI）")
	_check(h3["s"].is_seat_ai(2) and not h3["s"].is_seat_ai(1) and not h3["s"].is_seat_ai(0),
		"G19 主机判定：座位 2 是 AI，座位 0/1 是人")
	_check(_pump([h3, e1], func(): return e1["s"].state == NetSessionScript.State.PLAYING, CONNECT_TIMEOUT_MS),
		"G19 客人进入 PLAYING")
	_check(e1["s"].is_seat_ai(2), "G19 客人端对 AI 座位的判定与主机一致")
	_pump([h3, e1], func(): return h3["s"].all_seats_ready(), IO_TIMEOUT_MS)
	_check(h3["s"].all_seats_ready(), "G19 客人 ready 后主机 all_seats_ready = true")

	var h19: int = int(h3["s"].last_hash())
	var ev19: int = int(h3["gm"].event_log.size())
	_check(int(e1["s"].host_act_for_seat(2, "pass")) == NetProtocolScript.ERR_NOT_HOST,
		"G19 客人端代打 → ERR_NOT_HOST")
	_check(int(h3["s"].host_act_for_seat(1, "pass")) == NetProtocolScript.ERR_WRONG_SEAT,
		"G19 主机代打人类座位 → ERR_WRONG_SEAT")
	_check(int(h3["s"].host_act_for_seat(99, "pass")) == NetProtocolScript.ERR_WRONG_SEAT,
		"G19 座位越界 → ERR_WRONG_SEAT")
	_check(int(h3["s"].host_act_for_seat(-1, "pass")) == NetProtocolScript.ERR_WRONG_SEAT,
		"G19 观战座位（-1）→ ERR_WRONG_SEAT")
	_check(int(h3["s"].host_act_for_seat(2, "bogus")) == NetProtocolScript.ERR_BAD_EVENT,
		"G19 未知意图类型 → ERR_BAD_EVENT")
	_check(int(h3["s"].host_act_for_seat(2, "pass")) == NetProtocolScript.ERR_NOT_YOUR_TURN,
		"G19 未轮到 AI 座位 → ERR_NOT_YOUR_TURN")
	_check(int(h3["s"].last_hash()) == h19 and h3["gm"].event_log.size() == ev19,
		"G19 所有被拒的代打都没动局面 / 事件日志")
	_check(int(h3["s"].host_step_ai()) == 0, "G19 轮到人类（座位 0）时 host_step_ai 返回 0")

	# 把牌权推到 AI 座位：座位 0 出单张 → 座位 1 跳过 → 座位 2（AI）
	var u0 := _first_uid(h3["gm"], 0)
	_check(int(h3["s"].submit("play", {"uids": [u0], "valences": {}, "pattern": -1})) == 0,
		"G19 房主出单张（牌权 → 座位 1）")
	_pump([h3, e1], func(): return h3["gm"].current_player_index == 1, IO_TIMEOUT_MS)
	_check(int(e1["s"].submit("pass")) == 0, "G19 客人A 跳过（牌权 → 座位 2 / AI）")
	_pump([h3, e1], func(): return h3["gm"].current_player_index == 2, IO_TIMEOUT_MS)
	_check(h3["gm"].current_player_index == 2, "G19 牌权轮到 AI 座位 2")
	_check(e1["s"].game.current_player_index == 2, "G19 客人端牌权同步到座位 2")

	# 抢跑门控：客人还没 rebuild 完就替 AI 出手，客人重放必分叉
	var hash_gate: int = int(h3["s"].last_hash())
	h3["s"]._ready_seats[1] = false
	_check(int(h3["s"].host_step_ai()) == 0, "G19 客人未 ready → host_step_ai 被门控（返回 0）")
	_check(int(h3["s"].last_hash()) == hash_gate and h3["gm"].current_player_index == 2,
		"G19 门控期间 AI 一步没走（局面不动）")
	h3["s"]._ready_seats[1] = true

	# 代打：AI 计划 → 一笔意图 → 与人类完全相同的裁决链 → 广播 applied
	var applied_before: int = _count("e1", "applied")
	var steps19: int = int(h3["s"].host_step_ai())
	_check(steps19 >= 1, "G19 host_step_ai 替 AI 走了一手（%d 步）" % steps19)
	_check(h3["gm"].event_log.size() > ev19 + 1, "G19 主机事件日志里多出 AI 那一笔")
	_pump([h3, e1], func(): return _count("e1", "applied") > applied_before, IO_TIMEOUT_MS)
	_check(_count("e1", "applied") > applied_before, "G19 客人收到 AI 那一笔的 applied 广播")
	_check(e1["s"].last_hash() == h3["s"].last_hash(), "G19 代打后客人指纹与主机一致")
	_check(e1["s"].game.event_log.size() == h3["gm"].event_log.size(),
		"G19 两端事件日志条数一致（%d）" % h3["gm"].event_log.size())
	var last_ai_ev = h3["gm"].event_log[h3["gm"].event_log.size() - 1]
	_check(int(last_ai_ev.get("by", -1)) == 2, "G19 日志里那一笔的 by = 2（替 AI 座位发言）")
	_check(not e1["s"].is_desynced(), "G19 代打全程未触发 desync")

	# 两阶段：AI 座位自己出了顺序牌 → 主机同轮收窗，不干等 15s 超时
	h3["s"]._update_pending_after_apply(2, 1)
	_check(h3["s"].pending_seat() == 2, "G19 为 AI 座位开两阶段窗口")
	_pump([h3, e1], func(): return e1["s"].pending_seat() == 2, IO_TIMEOUT_MS)
	_check(e1["s"].pending_seat() == 2, "G19 客人同步到等待方 = 座位 2")
	var skip_before: int = int(h3["gm"].event_log.size())
	var skip_applied: int = _count("e1", "applied")
	_check(int(h3["s"].host_step_ai()) >= 1, "G19 host_step_ai 立刻替 AI 收窗（不等超时）")
	_check(h3["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, "G19 窗口已关闭")
	var skip_ev = h3["gm"].event_log[h3["gm"].event_log.size() - 1]
	_check(h3["gm"].event_log.size() == skip_before + 1
			and String(skip_ev.get("type", "")) == "sequence_skip"
			and int(skip_ev.get("by", -1)) == 2,
		"G19 收窗那一笔是 sequence_skip / by = 2")
	_pump([h3, e1], func(): return e1["s"].pending_seat() == NetSessionScript.WATCHER_SEAT \
		and _count("e1", "applied") > skip_applied, IO_TIMEOUT_MS)
	_check(e1["s"].pending_seat() == NetSessionScript.WATCHER_SEAT, "G19 客人同步到窗口关闭")
	_check(e1["s"].last_hash() == h3["s"].last_hash(), "G19 收窗后客人指纹仍一致")
	_check(not h3["s"].is_my_sequence_pending(), "G19 主机自己不在待指定状态")

	# ---- G20 诊断追踪（--net-trace，D1）----
	# 目的：真机上逐笔比对「主机 HOST 行」与「客人 CLIENT 行」，定位第一笔分叉。
	# 这里断言三件事：默认零输出、开关能落到缓冲、两端末行指纹一致。
	_check(not host["s"].trace_enabled and host["s"].trace_log.is_empty(),
		"G20 默认不追踪（trace_enabled=false，缓冲为空）")
	_check(host["s"]._hash_text(255) == "000000ff",
		"G20 指纹显示为 8 位十六进制（%s）" % host["s"]._hash_text(255))
	host["s"].enable_trace(true)
	c1["s"].enable_trace(true)
	var actor20: int = int(host["gm"].current_player_index)
	var seat_sessions := {0: host["s"], 1: c1["s"], 2: c2["s"]}
	var c1_applied_before: int = _count("c1", "applied")
	var c2_applied_before: int = _count("c2", "applied")
	# 跟出可以「过」，首出只能出牌 —— 先试 pass，不为 0 再退回出单张
	var code20: int = int(seat_sessions[actor20].submit("pass"))
	if code20 != 0:
		var uid20 := _first_uid(host["gm"], actor20)
		code20 = int(seat_sessions[actor20].submit("play",
			{"uids": [uid20], "valences": {}, "pattern": -1}))
	_check(code20 == 0, "G20 追踪期间推进了一笔权威事件（座位 %d）" % actor20)
	_pump(peers, func(): return _count("c1", "applied") > c1_applied_before \
		and _count("c2", "applied") > c2_applied_before, IO_TIMEOUT_MS)
	_check(_count("c1", "applied") > c1_applied_before, "G20 客人A 收到该笔 applied")
	var host_lines: Array = host["s"].trace_log
	var c1_lines: Array = c1["s"].trace_log
	_check(host_lines.size() >= 1
			and String(host_lines[host_lines.size() - 1]).begins_with("HOST seat="),
		"G20 主机每笔权威事件留一行 HOST（实得 %d 行）" % host_lines.size())
	_check(c1_lines.size() >= 1
			and String(c1_lines[c1_lines.size() - 1]).begins_with("CLIENT seat="),
		"G20 客人每笔回放留一行 CLIENT（实得 %d 行）" % c1_lines.size())
	_check(_trace_hash_tail(host["s"]) == _trace_hash_tail(c1["s"])
			and _trace_hash_tail(host["s"]).length() == 8,
		"G20 两端末行指纹一致（%s）" % _trace_hash_tail(host["s"]))
	host["s"].enable_trace(false)
	_check(not host["s"].trace_enabled and host["s"].trace_log.is_empty(),
		"G20 关掉追踪会清空缓冲")

	# ---- G21 座位容量 3~8（D17：房间人数可调，默认 4）----
	# 规则层本来就吃 3~8，这里守的是「联机层不再把 start_host / start_game clamp 到 4」。
	var h8 = _make_peer("h8")
	var g8 = _make_peer("g8")
	_check(int(h8["s"].start_host(PORT_CAP8, 8, "八人房主")) == 0,
		"G21 start_host(8) 成功")
	_check(int(h8["s"].seat_capacity()) == 8,
		"G21 房主容量 = 8（实际 %d）" % int(h8["s"].seat_capacity()))
	_check(int(g8["s"].start_client("127.0.0.1", PORT_CAP8, "八人客人")) == 0,
		"G21 客人发起连接")
	_check(_pump([h8, g8], func(): return g8["s"].my_seat == 1, CONNECT_TIMEOUT_MS),
		"G21 客人拿到座位 1")
	_check(int(g8["s"].seat_capacity()) == 8,
		"G21 客人从 welcome 同步容量 8（实际 %d）" % int(g8["s"].seat_capacity()))
	_check(int(h8["s"].start_game(9, 7)) == 0, "G21 start_game(9, 7) 成功")
	_check(int(h8["gm"].get_player_count()) == 8,
		"G21 玩家数 9 被压到上限 8（实际 %d）" % int(h8["gm"].get_player_count()))
	_check(int(h8["s"].ai_count()) == 7, "G21 AI 7 个（实际 %d）" % int(h8["s"].ai_count()))
	_check(_pump([h8, g8], func(): return g8["s"].state == NetSessionScript.State.PLAYING \
		and h8["s"].all_seats_ready(), CONNECT_TIMEOUT_MS),
		"G21 8 座位客人进入 PLAYING 且 ready")
	_check(int(g8["s"].game.get_player_count()) == 8, "G21 客人端也是 8 个玩家")
	_check(g8["s"].last_hash() == h8["s"].last_hash(), "G21 8 座位开局指纹一致")

	# 7 个 AI 座位：房主出单张后连推几步，逐笔同步到客人并与指纹对齐
	var u8 := _first_uid(h8["gm"], 0)
	_check(int(h8["s"].submit("play", {"uids": [u8], "valences": {}, "pattern": -1})) == 0,
		"G21 房主出单张（牌权 → 座位 1 / AI）")
	var advanced := 0
	for i in range(8):
		if h8["gm"].is_game_over() or int(h8["gm"].current_player_index) == 0:
			break
		advanced += int(h8["s"].host_step_ai(4))
		_pump([h8, g8], func(): return g8["s"].game.event_log.size() \
			>= h8["gm"].event_log.size(), IO_TIMEOUT_MS)
	_check(advanced >= 2, "G21 host_step_ai 在 7 个 AI 座位间推了 %d 步" % advanced)
	_pump([h8, g8], func(): return g8["s"].game.event_log.size() \
		== h8["gm"].event_log.size(), IO_TIMEOUT_MS)
	_check(g8["s"].last_hash() == h8["s"].last_hash(), "G21 推几步后两端指纹仍一致")
	_check(g8["s"].game.event_log.size() == h8["gm"].event_log.size(),
		"G21 8 座位事件流条数一致（%d）" % h8["gm"].event_log.size())
	_check(not g8["s"].is_desynced(), "G21 8 座位全程未分叉")

	# 下限：容量 3 + start_game(2) → 压到 3（2 座位会让 init_game 直接失败）
	var h3b = _make_peer("h3b")
	_check(int(h3b["s"].start_host(PORT_CAP3, 1, "三人房主")) == 0,
		"G21 start_host(1) 仍能建房（下限自动抬到 3）")
	_check(int(h3b["s"].seat_capacity()) == 3,
		"G21 容量下限 = 3（实际 %d）" % int(h3b["s"].seat_capacity()))
	_check(int(h3b["s"].start_game(2, 0)) == 0, "G21 start_game(2, 0) 成功")
	_check(int(h3b["gm"].get_player_count()) == 3,
		"G21 玩家数 2 被抬到下限 3（实际 %d）" % int(h3b["gm"].get_player_count()))

	# ---- G22 大厅 AI 补位数（D19）----
	# 复刻真机问题：房主把空座位补成 AI，客人那边却还是 0 —— 座位卡写「空位」、
	# 心里算的人数与房主不一致。AI 数必须从一开始就进会话状态并广播，不能只留在本地控件里。
	var hl = _make_peer("hl")
	var gl = _make_peer("gl")
	_check(int(hl["s"].start_host(PORT_LOBBY, 4, "大厅房主")) == 0, "G22 大厅房主监听成功")
	_check(int(gl["s"].start_client("127.0.0.1", PORT_LOBBY, "大厅客人")) == 0,
		"G22 大厅客人发起连接")
	_pump([hl, gl], func(): return gl["s"].my_seat == 1, CONNECT_TIMEOUT_MS)
	_check(gl["s"].my_seat == 1, "G22 大厅客人拿到座位 1")
	_check(int(hl["s"].lobby_ai_cap()) == 2,
		"G22 AI 上限 = 容量 4 - 在线人类 2 = 2（实际 %d）" % int(hl["s"].lobby_ai_cap()))
	_check(int(hl["s"].set_lobby_ai(3)) == 2,
		"G22 房主要 3 个 AI 被压到上限（实际 %d）" % int(hl["s"].lobby_ai))
	_pump([hl, gl], func(): return int(gl["s"].lobby_ai) == int(hl["s"].lobby_ai), IO_TIMEOUT_MS)
	_check(int(gl["s"].lobby_ai) == 2,
		"G22 客人同步到房主的 AI 数（实际 %d）" % int(gl["s"].lobby_ai))
	hl["s"].set_lobby_ai(1)
	_pump([hl, gl], func(): return int(gl["s"].lobby_ai) == 1, IO_TIMEOUT_MS)
	_check(int(gl["s"].lobby_ai) == 1, "G22 房主改成 1，客人跟着改成 1")
	# 客人只读：能调用也改不动，更不会污染房主
	_check(int(gl["s"].set_lobby_ai(2)) == 1, "G22 客人 set_lobby_ai 是空操作")
	_pump([hl, gl], func(): return false, 200)
	_check(int(hl["s"].lobby_ai) == 1,
		"G22 客人改不动房主的大厅 AI 数（实际 %d）" % int(hl["s"].lobby_ai))
	# 第三个人坐下 → 上限降到 1，新人靠 welcome 字段直接拿到同一个值
	var gl2 = _make_peer("gl2")
	_check(int(gl2["s"].start_client("127.0.0.1", PORT_LOBBY, "大厅客人二")) == 0,
		"G22 第三个客人发起连接")
	_pump([hl, gl, gl2], func(): return gl2["s"].my_seat == 2, CONNECT_TIMEOUT_MS)
	_check(gl2["s"].my_seat == 2, "G22 第三个客人拿到座位 2")
	_check(int(hl["s"].lobby_ai_cap()) == 1,
		"G22 3 人在线 → AI 上限 1（实际 %d）" % int(hl["s"].lobby_ai_cap()))
	_check(int(hl["s"].lobby_ai) == 1,
		"G22 上限收紧后房主的 AI 数仍在合法范围内（实际 %d）" % int(hl["s"].lobby_ai))
	_pump([hl, gl, gl2], func(): return int(gl2["s"].lobby_ai) == int(hl["s"].lobby_ai), IO_TIMEOUT_MS)
	_check(int(gl2["s"].lobby_ai) == int(hl["s"].lobby_ai),
		"G22 后进来的客人直接拿到房主的大厅 AI 数（%d）" % int(gl2["s"].lobby_ai))
	# 开局：大厅的 AI 数就地变成对局 AI 数，三端一致
	_check(int(hl["s"].start_game(4, int(hl["s"].lobby_ai))) == 0, "G22 用大厅 AI 数开局成功")
	_pump([hl, gl, gl2], func(): return gl["s"].state == NetSessionScript.State.PLAYING \
		and gl2["s"].state == NetSessionScript.State.PLAYING, CONNECT_TIMEOUT_MS)
	_check(gl["s"].state == NetSessionScript.State.PLAYING, "G22 客人进入 PLAYING")
	_check(int(gl["s"].ai_count()) == int(hl["s"].ai_count()),
		"G22 开局 AI 数两端一致（%d / %d）" % [int(gl["s"].ai_count()), int(hl["s"].ai_count())])
	_check(int(gl["s"].lobby_ai) == int(gl["s"].ai_count()),
		"G22 开局后 lobby_ai 与 ai_count 对齐（%d）" % int(gl["s"].lobby_ai))
	_check(gl["s"].last_hash() == hl["s"].last_hash(), "G22 大厅 AI 数开局后指纹一致")

	# ---- G23 房主收房：客人立刻拿到原因（D20）----
	# 分两段测，因为真机上这是**两条不同的路**：
	#   ① bye 包能到 → 「房主结束了本局」（局域网上多半能到）
	#   ② bye 到不了 → 底层 ENet 失活被 ENetTransport 立刻识别 → 「与主机的连接已断开」
	# 实测（Godot 4.7.2）：房主 close() 后，客人端的 ENetMultiplayerPeer 常常已经是
	# 「状态 DISCONNECTED + 收包队列被清空」，bye 根本没机会进 NetSession —— 所以 ②
	# 才是主路，① 是锦上添花。两条都必须在 1 秒级收尾，不能靠 12 秒心跳兜底。
	var hb = _make_peer("hb")
	var gb = _make_peer("gb")
	_check(int(hb["s"].start_host(PORT_BYE, 3, "收房房主")) == 0, "G23 房主监听成功")
	_check(int(gb["s"].start_client("127.0.0.1", PORT_BYE, "收房客人")) == 0,
		"G23 客人发起连接")
	_pump([hb, gb], func(): return gb["s"].my_seat == 1, CONNECT_TIMEOUT_MS)
	_check(int(hb["s"].start_game(3, 1)) == 0, "G23 对局开始成功")
	_pump([hb, gb], func(): return gb["s"].state == NetSessionScript.State.PLAYING, CONNECT_TIMEOUT_MS)
	_check(gb["s"].state == NetSessionScript.State.PLAYING, "G23 客人进入 PLAYING")
	# ① bye 包本身：房主直接在传输层发一条（等价于 close() 里那一条，但不关服），
	#    这样断言只测「客人收到 bye 之后的行为」，不受 ENet 收尾时序影响。
	hb["tr"].broadcast(NetProtocolScript.encode({
		"type": NetProtocolScript.MSG_BYE, "reason": "离开房间",
	}))
	var bye_ok: bool = _pump([gb], func(): return gb["s"].state == NetSessionScript.State.CLOSED,
		IO_TIMEOUT_MS)
	_check(bye_ok, "G23 客人收到 bye 就关会话（不等 ENet 超时）")
	var closed23 := _ev("gb", "closed")
	_check(not closed23.is_empty() and String(closed23[closed23.size() - 1]["reason"]) == "房主结束了本局",
		"G23 客人拿到的关闭原因写明房主收房（%s）"
		% ("" if closed23.is_empty() else String(closed23[closed23.size() - 1]["reason"])))
	_check(_count("gb", "desync") == 0, "G23 收房不会被误判成分叉")

	# ② 房主真的收房（close() → ENet 关服，bye 可能丢）：客人也必须秒级收尾
	var hb2 = _make_peer("hb2")
	var gb2 = _make_peer("gb2")
	_check(int(hb2["s"].start_host(PORT_BYE2, 3, "关服房主")) == 0, "G23 关服房主监听成功")
	_check(int(gb2["s"].start_client("127.0.0.1", PORT_BYE2, "关服客人")) == 0,
		"G23 关服客人发起连接")
	_pump([hb2, gb2], func(): return gb2["s"].my_seat == 1, CONNECT_TIMEOUT_MS)
	_check(int(hb2["s"].start_game(3, 1)) == 0, "G23 关服对局开始成功")
	_pump([hb2, gb2], func(): return gb2["s"].state == NetSessionScript.State.PLAYING,
		CONNECT_TIMEOUT_MS)
	_check(gb2["s"].state == NetSessionScript.State.PLAYING, "G23 关服客人进入 PLAYING")
	var t23b := Time.get_ticks_msec()
	hb2["s"].close("离开房间")
	var shut_ok: bool = _pump([gb2], func(): return gb2["s"].state == NetSessionScript.State.CLOSED,
		IO_TIMEOUT_MS)
	_check(shut_ok, "G23 房主关服后客人 %d ms 内收尾（不等 ENet / 心跳超时）"
		% (Time.get_ticks_msec() - t23b))
	var closed23b := _ev("gb2", "closed")
	var reason23b := "" if closed23b.is_empty() else String(closed23b[closed23b.size() - 1]["reason"])
	_check(reason23b != "" and (reason23b == "与主机的连接已断开" or reason23b == "房主结束了本局"),
		"G23 关服后客人拿到明确的关闭原因（%s）" % reason23b)
	_check(_count("gb2", "desync") == 0, "G23 关服不会被误判成分叉")

	# ---- G24 心跳超时：房主异常退出（没有 bye）也能判失联（D21）----
	var hh = _make_peer("hh")
	var gh = _make_peer("gh")
	_check(int(hh["s"].start_host(PORT_HB, 3, "心跳房主")) == 0, "G24 房主监听成功")
	gh["s"].heartbeat_timeout_ms = 400          # 测试把 12 秒压到 0.4 秒
	_check(int(gh["s"].start_client("127.0.0.1", PORT_HB, "心跳客人")) == 0,
		"G24 客人发起连接")
	_pump([hh, gh], func(): return gh["s"].my_seat == 1, CONNECT_TIMEOUT_MS)
	_check(int(hh["s"].start_game(3, 1)) == 0, "G24 对局开始成功")
	_pump([hh, gh], func(): return gh["s"].state == NetSessionScript.State.PLAYING, CONNECT_TIMEOUT_MS)
	_check(gh["s"].state == NetSessionScript.State.PLAYING, "G24 客人进入 PLAYING")
	# 房主不再 poll（= 进程被杀 / 断网）：客人只是收不到包，ENet 不会报 disconnected
	var hb_t0 := Time.get_ticks_msec()
	var hb_timeout: bool = _pump([gh],
		func(): return gh["s"].state == NetSessionScript.State.CLOSED, 3000)
	var hb_elapsed := Time.get_ticks_msec() - hb_t0
	_check(hb_timeout, "G24 收不到包 %d ms 后客人自己关会话" % hb_elapsed)
	_check(hb_elapsed >= 300,
		"G24 没有过早误判（%d ms ≥ 400ms 心跳门槛附近）" % hb_elapsed)
	var closed24 := _ev("gh", "closed")
	_check(not closed24.is_empty() and String(closed24[closed24.size() - 1]["reason"]).find("心跳超时") >= 0,
		"G24 关闭原因是心跳超时（%s）"
		% ("" if closed24.is_empty() else String(closed24[closed24.size() - 1]["reason"])))
	# 房主这端不受影响：它没有对端失联的概念
	_check(hh["s"].state == NetSessionScript.State.PLAYING, "G24 房主端状态不受影响")

	# ---- 收尾：全程无分叉 + close 幂等 ----
	_check(_count("c1", "desync") == 0 and _count("c2", "desync") == 0, "全程没有出现状态分叉")
	for p in [host, c1, c2, c3, h2, d1, d2, d3, h3, e1, h8, g8, h3b, hl, gl, gl2, hb, gb,
			hb2, gb2, hh, gh]:
		p["s"].close("测试结束")
		p["s"].close("重复关闭")
	_check(true, "close 可重复调用不炸")
	_finish()




