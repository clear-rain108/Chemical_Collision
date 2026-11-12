# ============================================================
# net_smoke.gd - 真机 / 多进程联机冒烟（P11-C1-c Step 0 的验收脚本）
#
# 为什么需要它：
#   tests/verify_net_session.gd 是**单进程内**的三个端点，证明的是「逻辑正确」；
#   它证明不了「两台机器之间 UDP 真的通、防火墙没拦、两端进程独立时 hash 仍然
#   逐笔一致」。这个脚本就是补上这一层：每个进程一个 GameManager，靠真实 ENet
#   打完整一局，把每笔事件的 hash 打在屏幕上，给你肉眼 / CI 对比。
#
# 用法（最少 3 人才能开局：PlayerManager.MIN_PLAYERS = 3）：
#   终端 1：godot --headless --path . --script tests/net_smoke.gd -- --host
#   终端 2：godot --headless --path . --script tests/net_smoke.gd -- --join 127.0.0.1
#   终端 3：godot --headless --path . --script tests/net_smoke.gd -- --join 127.0.0.1
#
#   跨机器：把 127.0.0.1 换成房主打印出来的局域网 / Tailscale IP。
#   手机（等 UI 接通后）同理：填同一个 IP + 端口。
#
# 怎么判读：
#   三个终端里的 `applied#N by=X type=Y result=Z hash=H` 应当逐行对齐，
#   最后的 `=== SMOKE ... final_hash=H ===` 三端必须相同；
#   任何一端出现 `!!! 分叉` 或 `=== SMOKE FAIL ===` 就是真问题。
#
# 参数（全部可省略，但 --host / --join 必须给一个）：
#   --host                 当房主（监听端口）
#   --join <ip>            当客人（连房主）
#   --port <n>             端口，默认 47800
#   --seats <n>            座位数，默认 3；3~8（超出会被 clamp，< 3 抬到 3）
#   --ai <n>               AI 座位数，默认 0（AI 座位排在人类之后，容量 8 时可到 7）
#   --name <文本>          昵称，默认取计算机名
#   --duration <秒>        自动打牌的时间上限，默认 60
#   --connect <秒>         等别人加入 / 等开局的超时，默认 60
#   --linger <毫秒>        结束后再收一会儿包，默认 1200
#   --manual               不自动出牌（只想验证「连得上」时用）
#   --help                 打印本说明
#
# 退出码：0 = 没分叉；1 = 分叉 / 连不上 / 超时。
#
# 注意：ENet 客户端 close() 之后不能立刻 quit()（会卡在引擎退出阶段），
#       所以 _finish() 里留了 600ms，详见 MULTIPLAYER_ARCHITECTURE.md 附录 C.5。
# ============================================================
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")
# 只读建议器：和「提示」按钮同一套判定，能保证「它说能出」主机就真的收
const HintAdvisorScript = preload("res://scripts/HintAdvisor.gd")

const DEFAULT_PORT := 47800
const HARD_MIN_SEATS := 3      # PlayerManager.MIN_PLAYERS：2 人开不了局
const HARD_MAX_SEATS := 8      # PlayerManager.MAX_PLAYERS / NetSession.MAX_PLAYERS（D17）
const TICK_MS := 5             # 每次 poll 之间的间隔

var _opt: Dictionary = {}
var _session = null
var _game = null
var _log: FileAccess = null
var _tag: String = "smoke"
var _applied: int = 0
var _rejected: int = 0
var _desync: int = 0
var _steps: int = 0
var _closed_reason: String = ""
var _fail_reason: String = ""


func _init() -> void:
	_opt = _parse_args()
	var role_tag := String(_opt["role"])
	if role_tag == "":
		role_tag = "help"
	_tag = "%s-%d" % [role_tag, OS.get_process_id()]
	_log = FileAccess.open("user://net_smoke_%s.log" % _tag, FileAccess.WRITE)
	if bool(_opt["help"]) or String(_opt["role"]) == "":
		_print_help()
		# _init 阶段直接 quit() 会漏掉引擎收尾，统一走延迟
		call_deferred("_finish", 0 if bool(_opt["help"]) else 1)
		return
	call_deferred("_run")


func _say(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


# ---- 参数解析 ----
# 同时读 OS.get_cmdline_args() 与 user_args：`-- --host` 和 `--host` 两种写法
# 都能用（和 GameUI 的 --touch-ui 保持一致），未知参数（引擎自己的 --headless
# / --path / --script …）一律忽略。
func _parse_args() -> Dictionary:
	var out := {
		"role": "",
		"address": "",
		"port": DEFAULT_PORT,
		"seats": HARD_MIN_SEATS,
		"ai": 0,
		"name": String(OS.get_environment("COMPUTERNAME")),
		"duration_ms": 60000,
		"connect_ms": 60000,
		"linger_ms": 1200,
		"auto": true,
		"help": false,
	}
	if String(out["name"]).strip_edges() == "":
		out["name"] = "玩家"
	var all: Array = []
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	var i := 0
	while i < all.size():
		var a := String(all[i])
		match a:
			"--host":
				out["role"] = "host"
			"--join":
				out["role"] = "client"
				i += 1
				if i < all.size():
					out["address"] = String(all[i])
			"--port":
				i += 1
				if i < all.size():
					out["port"] = int(String(all[i]))
			"--seats":
				i += 1
				if i < all.size():
					out["seats"] = int(String(all[i]))
			"--ai":
				i += 1
				if i < all.size():
					out["ai"] = int(String(all[i]))
			"--name":
				i += 1
				if i < all.size():
					out["name"] = String(all[i])
			"--duration":
				i += 1
				if i < all.size():
					out["duration_ms"] = int(float(String(all[i])) * 1000.0)
			"--connect":
				i += 1
				if i < all.size():
					out["connect_ms"] = int(float(String(all[i])) * 1000.0)
			"--linger":
				i += 1
				if i < all.size():
					out["linger_ms"] = int(String(all[i]))
			"--manual":
				out["auto"] = false
			"--help":
				out["help"] = true
		i += 1
	# GameManager 的硬下限：座位数 < 3 直接 init_game 失败，提前抬上去并说明
	if int(out["seats"]) < HARD_MIN_SEATS:
		out["seats"] = HARD_MIN_SEATS
		print("[smoke] 座位数下限 %d（PlayerManager.MIN_PLAYERS），已抬到 %d"
			% [HARD_MIN_SEATS, HARD_MIN_SEATS])
	out["seats"] = clampi(int(out["seats"]), HARD_MIN_SEATS, HARD_MAX_SEATS)   # D17：线上 3~8 座
	out["ai"] = clampi(int(out["ai"]), 0, int(out["seats"]) - 1)
	return out


func _print_help() -> void:
	print("""
net_smoke.gd - 真机联机冒烟（最少 3 人，因为 GameManager.MIN_PLAYERS = 3）

  godot --headless --path . --script tests/net_smoke.gd -- --host [--port 47800]
  godot --headless --path . --script tests/net_smoke.gd -- --join <房主IP> [--port 47800]

可选：--seats 3~8  --ai 0  --name 昵称  --duration 60  --connect 60
      --linger 1200  --manual  --help

判读：三端 applied#N ... hash=H 逐行一致，末尾 final_hash 相同即通过。
""".strip_edges())


# ============================================================
# 二、主流程
# ============================================================
func _run() -> void:
	_game = GameManagerScript.new()
	_session = NetSessionScript.new()
	_session.setup(_game, ENetTransportScript.new())
	_hook()
	_say("=== SMOKE 启动 === %s  昵称=%s  端口=%d  座位=%d  AI=%d  自动出牌=%s"
		% [_tag, String(_opt["name"]), int(_opt["port"]), int(_opt["seats"]),
			int(_opt["ai"]), "是" if bool(_opt["auto"]) else "否"])
	if String(_opt["role"]) == "host":
		if not _host_phase():
			_finish(1)
			return
	elif not _client_phase():
		_finish(1)
		return
	if bool(_opt["auto"]):
		_play_loop()
	_linger()
	_finish(0 if (_desync == 0 and _fail_reason == "") else 1)


func _host_phase() -> bool:
	var rc: int = _session.start_host(int(_opt["port"]), int(_opt["seats"]), String(_opt["name"]))
	if rc != 0:
		_fail("监听端口 %d 失败（多半被别的程序 / 没退干净的旧进程占着）" % int(_opt["port"]))
		return false
	_say("=== SMOKE 房间已创建 ===")
	_say("房号=%s  端口=%d  座位=%d" % [_session.room_code, int(_opt["port"]), int(_opt["seats"])])
	_say("其他机器请填下面任一地址（本机多开用 127.0.0.1）：")
	for ip in IP.get_local_addresses():
		if _is_lan_ipv4(ip):
			_say("    %s:%d" % [ip, int(_opt["port"])])
	_say("    127.0.0.1:%d" % int(_opt["port"]))
	if not _wait_until(Callable(self, "_all_seats_online"), int(_opt["connect_ms"])):
		_fail("等不到 %d 个座位全部上线：核对 IP / 端口是否一致、防火墙是否放行 UDP %d"
			% [int(_opt["seats"]), int(_opt["port"])])
		return false
	_say("全员上线 %s" % _seat_table_text())
	if _session.start_game(int(_opt["seats"]), int(_opt["ai"])) != 0:
		_fail("start_game 失败（座位 %d / AI %d）" % [int(_opt["seats"]), int(_opt["ai"])])
		return false
	_say("已下发开局（seed 由房主生成，两端同牌序）")
	return true


func _client_phase() -> bool:
	var addr := String(_opt["address"]).strip_edges()
	if addr == "":
		_fail("--join 后面要跟房主 IP，例如 --join 192.168.1.7")
		return false
	if _session.start_client(addr, int(_opt["port"]), String(_opt["name"])) != 0:
		_fail("发起连接失败：地址「%s」不合法" % addr)
		return false
	_say("正在连接 %s:%d ……" % [addr, int(_opt["port"])])
	if not _wait_until(Callable(self, "_is_in_game"), int(_opt["connect_ms"])):
		_fail("连不上 / 开局超时：确认房主已 --host、IP 与端口一致、Windows 防火墙放行 UDP %d"
			% int(_opt["port"]))
		return false
	if _session.is_watcher():
		_say("!! 进来时已经开局，只拿到观战位（本进程不出牌）")
	_say("已进入对局：座位=%d 房间=%s %s"
		% [int(_session.my_seat), _session.room_code, _seat_table_text()])
	return true


# ============================================================
# 三、自动出牌（手牌里挨个试单张，试不出来就 pass）
# ============================================================
func _play_loop() -> void:
	var deadline := Time.get_ticks_msec() + int(_opt["duration_ms"])
	while true:
		if _desync > 0:
			return
		if _closed_reason != "":
			_fail("会话被关闭：%s" % _closed_reason)
			return
		if _session.is_over() or _game.is_game_over():
			_say("=== SMOKE 对局正常结束 ===")
			return
		if Time.get_ticks_msec() >= deadline:
			_say("达到时长上限 %d 秒，停止自动出牌（不是错误）"
				% int(int(_opt["duration_ms"]) / 1000))
			return
		_session.poll()
		# 两阶段窗口里 can_submit() 为假，所以先处理「指定牌型」再谈出牌
		if _session.is_my_sequence_pending():
			_take_sequence()
		elif _session.is_my_turn() and _session.can_submit():
			_take_play()
		OS.delay_msec(TICK_MS)


func _take_sequence() -> void:
	_steps += 1
	var code: int = _session.skip_sequence()
	_say("[%s] step=%d 两阶段：跳过指定 -> %d" % [_tag, _steps, code])


# 用 HintAdvisor（只读建议器，「提示」按钮同一套判定）挑一手合法牌。
# 为什么不自己瞎试：客人调用 submit() 恒返回 0（要等主机裁决），
# 早先「挨张试单张」的写法会一直撞规则拒绝，实测白刷了 1596 条 rejected。
func _take_play() -> void:
	_steps += 1
	var hint: Dictionary = HintAdvisorScript.suggest(_game)
	if hint.is_empty():
		var code: int = _session.submit(NetProtocolScript.INTENT_PASS)
		_say("[%s] step=%d 无牌可接，pass -> %d" % [_tag, _steps, code])
		return
	var hand_uids: Array = _session.my_hand_uids()
	var uids: Array = []
	for idx in hint.get("indices", []):
		if int(idx) >= 0 and int(idx) < hand_uids.size():
			uids.append(int(hand_uids[int(idx)]))
	if uids.is_empty():
		return
	var valences: Dictionary = {}
	var v = hint.get("valence", {})
	if v is Dictionary:
		valences = (v as Dictionary).duplicate(true)
	if bool(hint.get("organic", false)):
		valences = {"_organic": true}
	var payload := {
		"uids": uids,
		"valences": valences,
		"pattern": int(hint.get("pattern", -1)),
	}
	var code2: int = _session.submit(NetProtocolScript.INTENT_PLAY, payload)
	_say("[%s] step=%d 出牌 %s uids=%s -> %d"
		% [_tag, _steps, String(hint.get("label", "")), str(uids), code2])


func _linger() -> void:
	if _session == null:
		return
	var deadline := Time.get_ticks_msec() + maxi(0, int(_opt["linger_ms"]))
	while Time.get_ticks_msec() < deadline:
		_session.poll()
		OS.delay_msec(TICK_MS)


# ============================================================
# 四、信号 → 账本（三端逐行对比就靠这些）
# ============================================================
func _hook() -> void:
	_session.seat_assigned.connect(func(seat: int) -> void:
		_say("[%s] 座位分配 = %d（房间 %s）" % [_tag, seat, _session.room_code]))
	_session.peer_joined.connect(func(seat: int, nm: String) -> void:
		_say("[%s] 座位 %d 上线：%s" % [_tag, seat, nm]))
	_session.peer_left.connect(func(seat: int, nm: String, grace: int) -> void:
		_say("[%s] 座位 %d 掉线：%s（宽限 %d ms）" % [_tag, seat, nm, grace]))
	_session.game_started.connect(func() -> void:
		_say("[%s] 开局：座位=%d 手牌=%d 张 %s"
			% [_tag, int(_session.my_seat), _session.my_hand_uids().size(), _seat_table_text()]))
	_session.state_applied.connect(_on_applied)
	_session.intent_rejected.connect(func(seq: int, code: int) -> void:
		_rejected += 1
		_say("[%s] 意图被拒 seq=%d code=%d" % [_tag, seq, code]))
	_session.sequence_pending.connect(func(seat: int, ms: int) -> void:
		_say("[%s] 两阶段：等待座位 %d 指定牌型（%d ms）" % [_tag, seat, ms]))
	_session.sequence_cleared.connect(func() -> void:
		_say("[%s] 两阶段：窗口关闭" % _tag))
	_session.desync_detected.connect(func(local_hash: int, host_hash: int) -> void:
		_desync += 1
		_say("!!! 分叉 local=%d host=%d" % [local_hash, host_hash]))
	_session.session_closed.connect(func(reason: String) -> void:
		_closed_reason = reason
		_say("[%s] 会话关闭：%s" % [_tag, reason]))
	_session.error_raised.connect(func(code: int, detail: String) -> void:
		_say("!!! error_raised code=%d %s" % [code, detail]))


func _on_applied(ev: Dictionary, result: int) -> void:
	_applied += 1
	_say("[%s] applied#%d by=%d type=%s result=%d hash=%d"
		% [_tag, _applied, int(ev.get("by", -1)), String(ev.get("type", "")),
			result, int(_session.last_hash())])


# ============================================================
# 五、工具
# ============================================================
func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + maxi(500, timeout_ms)
	var next_report := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if _session == null:
			return false
		_session.poll()
		if _closed_reason != "":
			return false
		if bool(cond.call()):
			return true
		if Time.get_ticks_msec() >= next_report:
			next_report += 3000
			_say("… 等待中：座位 %d 个 %s" % [_session.seat_count(), _seat_table_text()])
		OS.delay_msec(TICK_MS)
	return bool(cond.call())


func _all_seats_online() -> bool:
	if _session == null:
		return false
	for i in range(int(_opt["seats"])):
		if not _session.seat_is_online(i):
			return false
	return true


func _is_in_game() -> bool:
	return _session != null and _session.is_playing()


func _seat_table_text() -> String:
	var text := "座位表["
	for i in range(_session.seat_count()):
		if i > 0:
			text += ", "
		text += "%d:%s(%s)" % [i, _session.seat_name(i),
			"在线" if _session.seat_is_online(i) else "离线"]
	return text + "]"


func _is_lan_ipv4(ip: String) -> bool:
	if ip.find(".") < 0 or ip.find(":") >= 0:
		return false            # 只要 IPv4，跳过 IPv6
	if ip.begins_with("127.") or ip.begins_with("169.254."):
		return false            # 回环 / 链路本地（自动分配的，填了也连不上）
	return true


func _fail(msg: String) -> void:
	_fail_reason = msg
	_say("!!! " + msg)


func _finish(code: int = 0) -> void:
	if _session != null and _session.state != NetSessionScript.State.CLOSED:
		_session.close("冒烟结束")
	var final_hash := 0
	var over := false
	if _game != null:
		final_hash = int(_game.state_hash())
		over = bool(_game.is_game_over())
	_say("")
	_say("=== SMOKE RESULT seat=%d applied=%d rejected=%d desync=%d game_over=%s ==="
		% [(-1 if _session == null else int(_session.my_seat)), _applied, _rejected,
			_desync, "是" if over else "否"])
	_say("=== SMOKE FINAL final_hash=%d ===" % final_hash)
	if _fail_reason != "":
		_say("=== SMOKE 失败原因：%s ===" % _fail_reason)
	_say("=== SMOKE %s ===" % ("OK" if code == 0 else "FAIL"))
	if _log != null:
		_log.flush()
		_log = null
	# ENet 客户端 close() 之后立刻 quit() 会卡在引擎退出阶段（附录 C.5）
	OS.delay_msec(600)
	quit(code)
