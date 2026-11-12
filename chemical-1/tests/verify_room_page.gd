# 验证房间页（P11-C1-c Step 4）—— 建房 / 加入 / 座位表 / 开局闸门 / 离开房间
#   A 段：零网络 —— 页面结构 / 按钮几何 / 闸门纯函数 / 假会话座位表 / 收尾语义
#   B 段：3 个进程内 Main.tscn 实例 + 真实 ENet —— 房主建房 → 2 客人加入 → AI 补位 → 开局
#
# 要守住的五条（对应 MULTIPLAYER_TASKS.md 决策 D12~D15）：
#   ① 单机红线：不点「联机对战」就一行都不跑（页隐藏、net_session 恒为 null）
#   ② 座位 3~4：2 座位会在 GameManager.init_game 里直接失败（MIN_PLAYERS = 3）
#   ③ 大厅没有 ready 握手 → 闸门只能看「在线人类 + AI ∈ [3,4]」，不是 all_seats_ready()
#   ④ 离开房间 = close + attach_session(null)：闭着的会话绝不能留在 net_session 上
#   ⑤ 房号只是辨认用的 4 位数，不是地址 —— 客人必须手填房主 IP（D14）
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")

var fails: int = 0


# ------------------------------------------------------------
# 假会话：只实现房间页用到的查询 + 全部信号，逼 UI 只依赖接口（同 verify_ui_online）
# 刻意不继承 NetSession：房间页要是偷偷读内部字段，这里就会炸
# ------------------------------------------------------------
class RoomFake:
	extends RefCounted

	signal seat_assigned(seat: int)
	signal room_changed()
	signal game_started()
	signal state_applied(ev: Dictionary, result: int)
	signal intent_rejected(seq: int, code: int)
	signal sequence_pending(seat: int, remain_ms: int)
	signal sequence_cleared()
	signal desync_detected(local_hash: int, host_hash: int)
	signal peer_left(seat: int, peer_name: String, grace_ms: int)
	signal peer_joined(seat: int, peer_name: String)
	signal session_closed(reason: String)
	signal error_raised(code: int, detail: String)

	var role: int = 1                     # 1 = 房主
	var my_seat: int = 0
	var playing: bool = false
	var closed_reason: String = ""
	var room_code: String = "7391"
	var names: Array = ["房主", "阿明"]
	var online: Array = [true, true]
	var ai_flags: Array = [false, false]
	var reconnect_grace_ms: int = 15000
	var start_calls: Array = []

	func is_host() -> bool:
		return role == 1

	func is_playing() -> bool:
		return playing

	func is_watcher() -> bool:
		return my_seat < 0

	func is_desynced() -> bool:
		return false

	func is_my_turn() -> bool:
		return false

	func pending_seat() -> int:
		return -1

	func is_my_sequence_pending() -> bool:
		return false

	func can_submit() -> bool:
		return playing

	func poll() -> void:
		pass

	func submit(_intent_type: String, _payload: Dictionary = {}) -> int:
		return 0

	func all_seats_ready() -> bool:
		return false                     # 大厅里恒为 false —— 闸门绝不能拿它开局（D12）

	func host_step_ai(_max_steps: int = 1) -> int:
		return 0

	func my_hand_uids() -> Array:
		return []

	func seat_count() -> int:
		return names.size()

	func seat_name(seat: int) -> String:
		return String(names[seat]) if seat >= 0 and seat < names.size() else ""

	func seat_is_online(seat: int) -> bool:
		return bool(online[seat]) if seat >= 0 and seat < online.size() else false

	func is_seat_ai(seat: int) -> bool:
		return bool(ai_flags[seat]) if seat >= 0 and seat < ai_flags.size() else false

	func start_game(total: int = 4, ai_count: int = 0) -> int:
		start_calls.append({"total": total, "ai": ai_count})
		return 0

	func close(reason: String = "") -> void:
		if not playing and closed_reason != "":
			return
		playing = false
		closed_reason = reason
		session_closed.emit(reason)


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _finish() -> void:
	if fails == 0:
		print("ALL ROOM PAGE TESTS PASSED")
	else:
		print("%d ROOM PAGE TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


func _count_ai(gm) -> int:
	var n := 0
	for p in gm.get_players():
		if p != null and p.is_ai:
			n += 1
	return n


# 位置用距离比：入场补间收尾会留下 1e-4 级残差，直接用 == 会假报警
func _vec_eq(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.5


# 开始页入场动画会先把子节点 position.y +14 再落回（_animate_page_intro），
# 量几何前必须等它播完，否则量到的是动画中途的位置
func _settle_start_page(scene) -> void:
	var want := {"StartButton": 486.0, "RoomEntryBtn": 486.0, "TutorialBtn": 546.0, "ExitButton": 598.0}
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		var ready := true
		for nm in want.keys():
			var node = scene._start_child(nm)
			if node == null or not is_instance_valid(node):
				continue
			if not is_equal_approx(node.position.y, float(want[nm])) \
					or float(node.modulate.a) < 0.999:
				ready = false
				break
		if ready:
			return
		await process_frame


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await _settle_start_page(scene)

	_test_structure(scene)
	_test_start_page_buttons(scene)
	await _test_intro_animation(scene)
	_test_open_close(scene)
	_test_gate_pure(scene)
	await _test_fake_session(scene)
	await _test_leave(scene)
	await _test_single_player_red_line(scene)
	await _test_real_enet()
	_finish()



# ------------------------------------------------------------
# 1) 页面结构：节点齐不齐、座位卡是不是 4 张、默认是否隐藏
# ------------------------------------------------------------
func _test_structure(scene) -> void:
	var page = scene._room_page
	_check(page != null, "房间页已构建（_room_page 非空）")
	if page == null:
		return
	_check(String(page.name) == "RoomPage", "房间页节点名 = RoomPage（实际 %s）" % String(page.name))
	_check(page.get_parent() == scene.start_page, "房间页挂在开始页下（跟着开始页一起藏）")
	_check(not page.visible, "房间页默认隐藏（不点「联机对战」根本不可见）")
	_check(scene.net_session == null, "默认没有会话 —— 单机红线：一行联机代码都没跑")
	for n in ["RoomBackBtn", "RoomHostCard", "RoomJoinCard", "RoomSeatsPanel",
			"RoomCodeLabel", "RoomHintLabel", "RoomHostIpLabel",
			"RoomHostNameEdit", "RoomPortSpin", "RoomCreateBtn",
			"RoomJoinNameEdit", "RoomJoinPortSpin", "RoomAddrEdit",
			"RoomJoinBtn", "RoomLeaveBtn", "RoomAiSpin", "RoomStartBtn",
			"RoomSeatCard_0", "RoomSeatCard_3"]:
		# 卡片里的控件不是页的直接子节点：一律走 _start_child 递归找
		_check(scene._start_child(n) != null, "房间页含 %s" % n)
	_check(scene._room_seat_names.size() == 4 and scene._room_seat_states.size() == 4,
		"座位卡数组各 4 项（实际 %d / %d）" % [scene._room_seat_names.size(), scene._room_seat_states.size()])
	for i in range(4):
		var nm = scene._start_child("RoomSeatName_%d" % i)
		var txt := "-" if nm == null else String(nm.text)
		_check(nm != null and txt == "空位", "座位 %d 初始显示「空位」（实际 %s）" % [i + 1, txt])
	# 默认值：端口 47800 / 房主 IP 127.0.0.1 / AI 0
	_check(int(scene._room_host_port_spin.value) == 47800,
		"建房端口默认 47800（实际 %d）" % int(scene._room_host_port_spin.value))
	_check(int(scene._room_join_port_spin.value) == 47800,
		"加入端口默认 47800（实际 %d）" % int(scene._room_join_port_spin.value))
	_check(String(scene._room_addr_edit.text) == "127.0.0.1",
		"房主 IP 默认 127.0.0.1（实际 %s）" % String(scene._room_addr_edit.text))
	_check(int(scene._room_ai_spin.value) == 0, "AI 人数默认 0")
	_check(int(scene._room_ai_spin.min_value) == 0 and int(scene._room_ai_spin.max_value) == 4,
		"AI 人数范围 0~4（实际 %d~%d）" % [int(scene._room_ai_spin.min_value), int(scene._room_ai_spin.max_value)])
	# 副标题必须写死「客人填房主 IP」（D14），否则客人会以为输房号就能连
	var sub = page.get_node_or_null("RoomSubtitle")
	_check(sub != null and String(sub.text).find("IP") >= 0, "副标题提示客人要填房主 IP（D14）")


# ------------------------------------------------------------
# 2) 开始页按钮行：单机 / 联机并排，且不挤掉教学与退出
# ------------------------------------------------------------
func _test_start_page_buttons(scene) -> void:
	var sb = scene._start_child("StartButton")
	var rb = scene._start_child("RoomEntryBtn")
	_check(sb != null and rb != null, "开始页同时有「开始游戏」与「联机对战」")
	if sb == null or rb == null:
		return
	_check(_vec_eq(sb.position, Vector2(446, 486)), "开始游戏在 (446,486)（实际 %s）" % str(sb.position))
	_check(_vec_eq(sb.size, Vector2(124, 52)), "开始游戏 124x52（实际 %s）" % str(sb.size))
	_check(_vec_eq(rb.position, Vector2(582, 486)), "联机对战在 (582,486)（实际 %s）" % str(rb.position))
	# 尺寸同样用容差（custom_minimum_size 与字体度量会让高度落到 52.00012 这种值）
	_check(_vec_eq(rb.size, Vector2(124, 52)), "联机对战 124x52（实际 %s）" % str(rb.size))
	_check(sb.position.x + sb.size.x <= rb.position.x,
		"两颗按钮不重叠（%d → %d）" % [int(sb.position.x + sb.size.x), int(rb.position.x)])
	_check(rb.position.x + rb.size.x <= 1152.0,
		"联机对战不出画布（右边 %d ≤ 1152）" % int(rb.position.x + rb.size.x))
	var tb = scene._start_child("TutorialBtn")
	var eb = scene._start_child("ExitButton")
	_check(tb != null and _vec_eq(tb.position, Vector2(446, 546)), "教学引导仍在 (446,546)")
	_check(eb != null and _vec_eq(eb.position, Vector2(476, 598)), "退出程序仍在 (476,598)")


# ------------------------------------------------------------
# 2b) 入场动画：开始页每个按钮都要参与错峰淡入
#     Step 4 新增「联机对战」时漏登记 START_INTRO_ORDER，表现是它不淡入、不上浮，
#     页面淡入一结束就以终态"抢先"出现（和其它按钮完全不同步）
# ------------------------------------------------------------
func _test_intro_animation(scene) -> void:
	var order: Array = scene.START_INTRO_ORDER
	# ① 覆盖性：开始页「直接子节点里的按钮」必须全部登记（以后再加按钮漏加会被抓到）
	var missing: Array = []
	for ch in scene.start_page.get_children():
		if ch is Button and not ch.is_queued_for_deletion():
			if order.find(String(ch.name)) < 0:
				missing.append(String(ch.name))
	_check(missing.is_empty(), "开始页所有按钮都登记进 START_INTRO_ORDER（漏：%s）" % str(missing))
	# ② 不陈旧：登记的名字都得真的存在（改名 / 删节点后忘了改名单）
	var absent: Array = []
	for n in order:
		if scene.start_page.get_node_or_null(String(n)) == null:
			absent.append(String(n))
	_check(absent.is_empty(), "START_INTRO_ORDER 里没有失效名字（缺：%s）" % str(absent))
	# ③ 视觉顺序：联机对战排在开始游戏之前（同一行，左 → 右）
	var i_room: int = order.find("RoomEntryBtn")
	var i_start: int = order.find("StartButton")
	_check(i_room >= 0 and i_start > i_room, "联机对战排在开始游戏之前（%d → %d）" % [i_room, i_start])

	# ④ 真跑一遍：回到开始页那一帧，联机对战 = 透明 + 靠下 14px（和别的按钮同时起步）
	scene._show_start_page()
	var rb = scene._start_child("RoomEntryBtn")
	_check(rb != null, "联机对战按钮存在")
	if rb == null:
		return
	var sb = scene._start_child("StartButton")
	_check(float(rb.modulate.a) < 0.2, "联机对战从透明淡入（a=%.2f）" % float(rb.modulate.a))
	_check(rb.position.y > 490.0, "联机对战自下方上浮（y=%.1f，基准 486）" % rb.position.y)
	_check(sb != null and float(sb.modulate.a) < 0.2,
		"开始游戏同时也在透明态 —— 两颗同批起步")
	# ⑤ 播完落位
	await _settle_start_page(scene)
	_check(abs(float(rb.modulate.a) - 1.0) < 0.01,
		"联机对战淡入收敛到不透明（a=%.2f）" % float(rb.modulate.a))
	_check(_vec_eq(rb.position, Vector2(582, 486)), "联机对战落回 (582,486)（实际 %s）" % str(rb.position))


# ------------------------------------------------------------
# 3) 入口 / 返回：点了才打开，返回即收尾
# ------------------------------------------------------------
func _test_open_close(scene) -> void:
	var page = scene._room_page
	scene._start_child("RoomEntryBtn").pressed.emit()
	_check(page != null and page.visible, "点「联机对战」打开房间页")
	_check(scene._room_hint_label.text == "", "刚打开时提示区是空的")
	scene._start_child("RoomBackBtn").pressed.emit()
	_check(page != null and not page.visible, "点「‹ 返回」关闭房间页")
	_check(scene.net_session == null, "关页后没有残留会话")


# ------------------------------------------------------------
# 4) 开局闸门（纯函数）：3~4 座位 / 只有房主能开 / 掉线等待
# ------------------------------------------------------------
func _test_gate_pure(scene) -> void:
	var lobby: int = NetSessionScript.State.LOBBY
	var playing: int = NetSessionScript.State.PLAYING
	var connecting: int = NetSessionScript.State.CONNECTING
	_check(scene._room_start_block_reason(4, 0, false, lobby) == "等待房主开始",
		"客人不能开局（闸门返回「等待房主开始」）")
	_check(scene._room_start_block_reason(4, 0, true, playing) == "对局已开始",
		"对局中不能再开局")
	_check(scene._room_start_block_reason(4, 0, true, connecting) == "房间未就绪",
		"还没握手时不能开局")
	var short2: String = scene._room_start_block_reason(2, 0, true, lobby)
	_check(short2 != "" and short2.find("3") >= 0, "2 人类不足 3 → 拦住（%s）" % short2)
	_check(scene._room_start_block_reason(1, 1, true, lobby) != "",
		"1 人类 + 1 AI = 2 仍不足 3")
	_check(scene._room_start_block_reason(3, 0, true, lobby) == "", "3 人类可开局")
	_check(scene._room_start_block_reason(1, 2, true, lobby) == "", "1 人类 + 2 AI = 3 可开局")
	_check(scene._room_start_block_reason(2, 2, true, lobby) == "", "2 人类 + 2 AI = 4 可开局")
	var over: String = scene._room_start_block_reason(4, 1, true, lobby)
	_check(over != "" and over.find("4") >= 0, "5 座位超限 → 拦住（%s）" % over)
	_check(scene._room_start_block_reason(3, 0, true, lobby, 1) != "", "有座位掉线时不开局（等重连）")
	_check(scene._room_start_block_reason(3, 0, true, lobby, 0) == "", "掉线数 0 时正常可开局")


# ------------------------------------------------------------
# 5) 假会话：座位表 / 房号 / 按钮可用态 / AI 上限 / 信号回调
# ------------------------------------------------------------
func _test_fake_session(scene) -> void:
	_check(scene._room_start_disabled_reason() == "还没加入房间",
		"没有会话时闸门返回「还没加入房间」")
	_check(not scene._room_can_start(), "没有会话时不能开局")

	var fake := RoomFake.new()
	scene.call("_room_bind_session", fake)
	scene.call("_room_refresh")   # 建房 / 加入成功后页面自己会刷；这里手动补一次
	await process_frame
	_check(scene.net_session == fake, "会话已装配（_room_bind_session → attach_session）")
	_check(scene.action_router != null, "动作层已随之重装（Step 3 的装配口）")

	# 2 人在线：座位 / 房号 / 按钮三组断言
	_check(_seat_name(scene, 0) == "房主", "座位 1 = 房主（实际 %s）" % _seat_name(scene, 0))
	_check(_seat_state(scene, 0).find("你") >= 0, "座位 1 标「房主 · 你」（实际 %s）" % _seat_state(scene, 0))
	_check(_seat_name(scene, 1) == "阿明", "座位 2 = 阿明（实际 %s）" % _seat_name(scene, 1))
	_check(_seat_state(scene, 1) == "在线", "座位 2 标「在线」（实际 %s）" % _seat_state(scene, 1))
	_check(_seat_name(scene, 2) == "空位", "座位 3 仍是空位")
	_check(String(scene._room_code_label.text).find("7391") >= 0,
		"房号显示在页面上（%s）" % String(scene._room_code_label.text))
	_check(scene._room_create_btn.disabled and scene._room_join_btn.disabled,
		"在房间里：创建 / 加入都禁用")
	_check(not scene._room_leave_btn.disabled, "在房间里：离开可用")
	_check(scene._room_start_btn.disabled, "2 人 + 0 AI 时开局按钮禁用")
	_check(String(scene._room_start_btn.text).find("2/4") >= 0,
		"禁用时按钮写明当前座位数（%s）" % String(scene._room_start_btn.text))

	# AI 上限 = 4 - 在线人类数；AI 座位排在人类之后
	_check(int(scene._room_ai_spin.max_value) == 2,
		"2 人在线 → AI 上限 2（实际 %d）" % int(scene._room_ai_spin.max_value))
	scene._room_ai_spin.value = 1
	await process_frame
	_check(_seat_name(scene, 2) == "AI 1", "AI 补在人类之后（座位 3 = %s）" % _seat_name(scene, 2))
	_check(_seat_state(scene, 2) == "AI 托管", "AI 座位状态「AI 托管」（实际 %s）" % _seat_state(scene, 2))
	_check(not scene._room_start_btn.disabled, "2 人 + 1 AI = 3 → 开局按钮恢复可用")

	fake.names = ["房主", "阿明", "小刚"]
	fake.online = [true, true, true]
	fake.room_changed.emit()
	await process_frame
	_check(int(scene._room_ai_spin.max_value) == 1,
		"3 人在线 → AI 上限 1（实际 %d）" % int(scene._room_ai_spin.max_value))

	fake.names = ["房主", "阿明", "小刚", "小美"]
	fake.online = [true, true, true, true]
	fake.room_changed.emit()
	await process_frame
	_check(int(scene._room_ai_spin.max_value) == 0, "4 人在线 → AI 上限 0")
	_check(int(scene._room_ai_spin.value) == 0,
		"上限压到 0 时 AI 数跟着回到 0（实际 %d）" % int(scene._room_ai_spin.value))
	_check(not scene._room_start_btn.disabled, "4 人在线 → 直接可开局")

	# 掉线：座位保留 + 提示 + 闸门拦
	fake.online = [true, false, true, true]
	scene._room_hint("")
	fake.room_changed.emit()
	await process_frame
	_check(_seat_state(scene, 1) == "掉线中 · 座位保留",
		"掉线座位保留并标注（实际 %s）" % _seat_state(scene, 1))
	_check(scene._room_offline_humans() == 1, "掉线座位计数 1（实际 %d）" % scene._room_offline_humans())
	_check(String(scene._room_hint_label.text).find("掉线") >= 0,
		"提示区自动补一句掉线提醒（%s）" % String(scene._room_hint_label.text))
	_check(scene._room_start_btn.disabled, "有座位掉线时开局按钮禁用")
	# 三个大厅信号 → 提示文案
	scene._room_hint("")
	fake.peer_joined.emit(2, "小刚")
	_check(String(scene._room_hint_label.text).find("小刚") >= 0,
		"peer_joined → 提示「小刚 加入了」（%s）" % String(scene._room_hint_label.text))
	fake.peer_left.emit(2, "小刚", 15000)
	_check(String(scene._room_hint_label.text).find("15") >= 0,
		"peer_left → 提示写清保留秒数（%s）" % String(scene._room_hint_label.text))
	scene._room_join_target = "1.2.3.4:47800"
	fake.seat_assigned.emit(0)
	_check(String(scene._room_hint_label.text).find("座位 1") >= 0,
		"seat_assigned(0) → 提示「你是座位 1」（%s）" % String(scene._room_hint_label.text))
	_check(scene._room_join_target == "", "收到座位分配后清掉连接目标（不再倒计时超时）")
	fake.seat_assigned.emit(-1)
	_check(String(scene._room_hint_label.text).find("观战") >= 0,
		"seat_assigned(-1) → 提示观战身份（%s）" % String(scene._room_hint_label.text))

	# 本机 IP 列表：过滤回环 / 链路本地 / IPv6
	var bad := ""
	for ip in scene._room_local_ips():
		var s := String(ip)
		if s.find(":") >= 0 or s.begins_with("127.") or s.begins_with("169.254."):
			bad = s
	_check(bad == "", "本机 IP 过滤掉回环 / 链路本地 / IPv6（脏值：%s）" % bad)
	_check(String(scene._room_ip_text()).find("本机 IP") >= 0, "_room_ip_text() 带「本机 IP：」前缀")

	# 座位不够时点开始：只给原因，不真的 start_game
	fake.names = ["房主", "阿明"]
	fake.online = [true, true]
	scene._room_ai_spin.value = 0
	scene._room_hint("")
	fake.room_changed.emit()
	await process_frame
	scene.call("_room_start")
	_check(fake.start_calls.is_empty(), "座位不足时点「开始对局」不会真的 start_game")
	_check(String(scene._room_hint_label.text).find("座位不足") >= 0,
		"并给出「座位不足」提示（%s）" % String(scene._room_hint_label.text))

	# 3 座位：真的开局，参数 = 在线人类 + AI
	scene._room_ai_spin.value = 1
	await process_frame
	_check(scene._room_can_start(), "2 人 + 1 AI = 3 → 闸门放行")
	scene.call("_room_start")
	_check(fake.start_calls.size() == 1,
		"3 座位点开始 → 真的调 start_game（%d 次）" % fake.start_calls.size())
	if fake.start_calls.size() == 1:
		var args: Dictionary = fake.start_calls[0]
		_check(int(args["total"]) == 3 and int(args["ai"]) == 1,
			"start_game(3, 1)（实际 total=%d ai=%d）" % [int(args["total"]), int(args["ai"])])


func _seat_name(scene, i: int) -> String:
	return String(scene._room_seat_names[i].text)


func _seat_state(scene, i: int) -> String:
	return String(scene._room_seat_states[i].text)


# ------------------------------------------------------------
# 6) 离开房间：close + attach_session(null) + 丢掉空局面 GameManager（D13）
# ------------------------------------------------------------
func _test_leave(scene) -> void:
	var fake := RoomFake.new()
	scene.call("_room_bind_session", fake)
	# 大厅里那份占位 GameManager（players 为空）离开时必须丢掉，
	# 否则下一次单机开局会带着空 players 进 _refresh_ui
	scene.game_manager = GameManagerScript.new()
	scene.call("_room_refresh")
	await process_frame
	_check(not scene._room_leave_btn.disabled, "在房间里「离开房间」可用")
	scene.call("_room_leave")
	await process_frame
	_check(fake.closed_reason != "", "离开房间会 close 会话（原因：%s）" % fake.closed_reason)
	_check(scene.net_session == null, "离开后 attach_session(null)：闭会话绝不留在 net_session 上（D13）")
	_check(scene.game_manager == null, "空局面的大厅 GameManager 被丢掉")
	_check(String(scene._room_hint_label.text) == "已离开房间",
		"提示「已离开房间」（实际 %s）" % String(scene._room_hint_label.text))
	_check(scene._room_leave_btn.disabled and not scene._room_create_btn.disabled,
		"离开后：离开禁用，创建 / 加入恢复可用")
	_check(scene._room_start_btn.disabled, "离开后开局按钮回到禁用")
	scene.call("_room_leave")
	_check(String(scene._room_hint_label.text) == "还不在房间里",
		"再点离开只提示「还不在房间里」（实际 %s）" % String(scene._room_hint_label.text))
	_check(not scene._room_closing, "收尾闸已复位（_room_closing = false）")


# ------------------------------------------------------------
# 7) 单机红线：房间页用不用，单机「开始游戏」都照旧
# ------------------------------------------------------------
func _test_single_player_red_line(scene) -> void:
	scene.call("_show_start_page")
	await process_frame
	_check(scene.net_session == null, "回开始页后 net_session 仍为 null")
	scene.call("_on_start_game")
	await process_frame
	_check(scene.game_manager != null and scene.game_manager.get_players().size() == 4,
		"单机开局不受房间页影响（4 人）")
	_check(scene.net_session == null, "单机开局不会顺手挂会话")
	_check(scene.game_page.visible and not scene._room_page.visible,
		"单机开局进牌桌，房间页保持隐藏")
	scene.call("_show_start_page")
	await process_frame
	_check(scene.game_manager != null, "回开始页不丢掉刚打过的 GameManager（players 非空）")

# ============================================================
# B 段：3 个进程内 Main.tscn 实例 + 真实 ENet
#   验证「房间页 → 会话 → 开局」整条链路真能跑通：
#   · 房主用页面建房，客人用页面加入（D14：手填 127.0.0.1）
#   · 三端房号一致、座位表按昵称显示
#   · 3 人 + 1 AI = 4 → 房主开局，三端进牌桌
#   · 客人点开局无效；客人离开后房主看到「掉线 · 座位保留」
# ============================================================
const PORT_ROOM = 47855
const ROOM_CONNECT_TIMEOUT_MS = 8000
const ROOM_PLAY_TIMEOUT_MS = 20000


func _make_ui():
	var ui = load("res://Main.tscn").instantiate()
	root.add_child(ui)
	return ui


func _pump_until(uis: Array, cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for ui in uis:
			if is_instance_valid(ui):
				ui.call("_update_net", 0.02)
		if bool(cond.call()):
			return true
		OS.delay_msec(2)
	return false


func _all_joined(uis: Array) -> bool:
	if uis[0].net_session == null or int(uis[0].net_session.seat_count()) < 3:
		return false
	for i in range(1, uis.size()):
		if uis[i].net_session == null or int(uis[i].net_session.my_seat) < 0:
			return false
	return true


func _all_playing(uis: Array) -> bool:
	for ui in uis:
		if ui.net_session == null or not ui.net_session.is_playing():
			return false
	return true


func _free_all(uis: Array) -> void:
	for ui in uis:
		if is_instance_valid(ui):
			ui.call("_room_teardown")
			ui.queue_free()


# 端口探测：B 段跑真实 ENet，固定端口一旦被占（并发跑两遍 / 上次没退干净）就会假失败。
# 从 PORT_ROOM 起逐个试，第一个「页面建房成功」的端口就是本次用的端口。
func _pick_free_port(ui) -> int:
	for p in range(PORT_ROOM, PORT_ROOM + 20):
		ui._room_host_port_spin.value = p
		ui.call("_room_start_host")
		if ui.net_session != null and ui.net_session.is_host():
			return p
		ui.call("_room_teardown")
	return -1




func _test_real_enet() -> void:
	var uis: Array = []
	for i in range(3):
		uis.append(_make_ui())
	await process_frame
	await process_frame

	var host = uis[0]
	host.call("_open_room_page")
	var port: int = _pick_free_port(host)
	_check(port > 0, "B：房主用页面建房成功（端口 %d）" % port)
	if port <= 0:
		_check(false, "B：%d~%d 全被占用，真机段跑不了（提示：%s）"
			% [PORT_ROOM, PORT_ROOM + 19, String(host._room_hint_label.text)])
		_free_all(uis)
		return
	_check(host._room_page.visible, "B：建房后仍停在房间页等客人")
	var code := String(host.net_session.room_code)
	_check(code != "", "B：房号已生成（%s）" % code)
	_check(String(host._room_code_label.text).find(code) >= 0, "B：房号显示在页面上")
	_check(String(host._room_host_ip_label.text).find("本机 IP") >= 0, "B：页面上给了本机 IP")

	for i in range(1, 3):
		var guest = uis[i]
		guest.call("_open_room_page")
		guest._room_join_name_edit.text = "客人%d" % i
		guest._room_join_port_spin.value = port
		guest._room_addr_edit.text = "127.0.0.1"
		guest.call("_room_join")
		_check(guest.net_session != null,
			"B：客人 %d 发起连接（提示：%s）" % [i, String(guest._room_hint_label.text)])

	var ok: bool = _pump_until(uis, func() -> bool: return _all_joined(uis), ROOM_CONNECT_TIMEOUT_MS)
	_check(ok, "B：两端客人都握手完成并拿到座位")
	if not ok:
		_free_all(uis)
		return

	_check(int(host.net_session.seat_count()) == 3,
		"B：房主看到 3 个座位（实际 %d）" % int(host.net_session.seat_count()))
	_check(int(host.net_session.my_seat) == 0 and host.net_session.is_host(), "B：房主 = 座位 1（seat 0）")
	_check(int(uis[1].net_session.seat_count()) == 3, "B：客人也看到 3 个座位")
	_check(not uis[1].net_session.is_host(), "B：客人不是房主")
	_check(String(uis[1].net_session.room_code) == code,
		"B：客人拿到的房号与房主一致（%s / %s）" % [String(uis[1].net_session.room_code), code])
	_check(host._room_online_humans() == 3, "B：在线人类 3（实际 %d）" % host._room_online_humans())
	_check(int(host._room_ai_spin.max_value) == 1,
		"B：3 人在线 → AI 上限 1（实际 %d）" % int(host._room_ai_spin.max_value))
	_check(host._room_start_disabled_reason() == "", "B：3 人在线 → 闸门放行（D15 下限就是 3）")
	_check(_seat_name(host, 1) == "客人1", "B：座位 2 显示客人昵称（实际 %s）" % _seat_name(host, 1))

	host._room_ai_spin.value = 1
	await process_frame
	_check(host._room_can_start(), "B：3 人 + 1 AI = 4 → 房主可以开局")
	_check(String(uis[1]._room_start_disabled_reason()) == "等待房主开始",
		"B：客人闸门恒为「等待房主开始」")
	uis[1].call("_room_start")
	_check(not uis[1].net_session.is_playing(), "B：客人点开局无效（不改会话状态）")

	host.call("_room_start")
	ok = _pump_until(uis, func() -> bool: return _all_playing(uis), ROOM_PLAY_TIMEOUT_MS)
	_check(ok, "B：房主开局 → 三端都进入对局")
	if ok:
		_check(int(host.game_manager.get_players().size()) == 4, "B：4 个玩家（3 人 + 1 AI）")
		_check(_count_ai(host.game_manager) == 1,
			"B：AI 座位 1 个（实际 %d）" % _count_ai(host.game_manager))
		_check(int(uis[2].game_manager.get_players().size()) == 4, "B：客人也重建出 4 个玩家")
		_check(not host._room_page.visible, "B：开局后房间页自动隐藏")
		_check(host.game_page.visible, "B：房主进入牌桌")
		_check(uis[1].game_page.visible, "B：客人也自动进入牌桌")
		_check(host.net_session != null, "B：开局后会话仍在（房间页没被拆掉）")

		# 客人离开：房主看到座位变掉线（保留，等重连）
		uis[2].call("_room_leave")
		_check(uis[2].net_session == null, "B：客人离开房间后会话已释放")
		var left_ok: bool = _pump_until([host, uis[1]],
			func() -> bool: return host._room_offline_humans() >= 1, 5000)
		_check(left_ok, "B：房主看到座位 3 掉线（座位保留等重连）")
		_check(int(host.net_session.seat_count()) == 3, "B：掉线不删座位（仍是 3 个）")

	_free_all(uis)


