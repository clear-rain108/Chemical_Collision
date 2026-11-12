# 验证 GameUI 的联机分支（P11-C1-c Step 3）
#   A 段（本文件前半）：假会话 + 零网络 —— 视图归属 / 只读门控 / 面板文案 / 信号接线
#   B 段（_test_real_enet）：3 个进程内 Main.tscn 实例 + 真实 ENet 往返
#
# 要守住的四条（对应 MULTIPLAYER_TASKS.md 决策 D6~D9）：
#   D6 视图归属：客人只看自己的手牌 / 自己的可用牌型，与「当前行动者」无关
#   D7 热座开关：挂了会话就不再是热座（3 人局不能被交接遮罩卡死）
#   D1 提交语义：客人返回 0 = 已发出，界面必须停在「已提交，等待主机裁决…」
#   D8 AI 代打：联机下 UI 的 AI 计时器必须关掉，AI 只由主机 host_step_ai 推进
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const NetTransportScript = preload("res://scripts/net/ENetTransport.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")

var fails: int = 0
var checks: int = 0


# ------------------------------------------------------------
# 假会话：只实现 GameUI / ActionRouter 用到的那几个查询与信号。
# 故意不继承 NetSession —— 逼着 UI 只依赖接口，而不是偷偷读内部字段。
# ------------------------------------------------------------
class FakeSession:
	extends RefCounted

	signal seat_assigned(seat: int)
	signal room_changed()
	signal game_started()
	signal state_applied(ev: Dictionary, result: int)
	signal intent_rejected(seq: int, code: int)
	signal sequence_pending(seat: int, remain_ms: int)
	signal sequence_cleared()
	signal desync_detected(local_hash: int, host_hash: int)
	signal session_closed(reason: String)
	signal error_raised(code: int, detail: String)

	var role: int = 2                 # 2 = NetSession.Role.CLIENT
	var my_seat: int = 1
	var playing: bool = true
	var turn_seat: int = 1
	var pending: int = -1
	var desynced: bool = false
	var polls: int = 0
	var submits: Array = []
	var ai_calls: int = 0
	var closed_reason: String = ""

	# 联机 UI 会按 AI 人数调节流（D17）；假会话只需要给出一个数
	func ai_count() -> int:
		return 0

	func is_playing() -> bool:
		return playing

	func is_host() -> bool:
		return role == 1

	func is_watcher() -> bool:
		return my_seat < 0

	func is_desynced() -> bool:
		return desynced

	func is_my_turn() -> bool:
		return playing and not is_watcher() and not desynced and turn_seat == my_seat

	func pending_seat() -> int:
		return pending

	func is_my_sequence_pending() -> bool:
		return pending >= 0 and pending == my_seat

	func can_submit() -> bool:
		return playing and not is_watcher() and not desynced and pending < 0

	func poll() -> void:
		polls += 1

	func submit(intent_type: String, payload: Dictionary = {}) -> int:
		submits.append({"type": intent_type, "payload": payload.duplicate(true)})
		return 0

	func all_seats_ready() -> bool:
		return true

	func host_step_ai(_max_steps: int = 1) -> int:
		ai_calls += 1
		return 0

	func close(reason: String = "") -> void:
		if not playing and closed_reason != "":
			return
		playing = false
		closed_reason = reason
		session_closed.emit(reason)

	func my_hand_uids() -> Array:
		return []

	func seat_name(seat: int) -> String:
		return "座位%d" % seat

	func is_seat_ai(_seat: int) -> bool:
		return false


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 3 个真人座位、0 AI：单机下这就是「热座」，正好用来验证 D7
	scene.game_manager = GameManagerScript.new()
	scene.game_manager.init_game(3, 0)
	scene.call("_refresh_ui")

	_test_single_player_baseline(scene)

	var fake := FakeSession.new()
	fake.my_seat = 1
	fake.turn_seat = 0            # 轮到座位 0（不是我）
	scene.call("attach_session", fake)
	await process_frame
	await process_frame

	_test_attach(scene, fake)
	_test_other_turn_view(scene, fake)
	await _test_ai_gate(scene)
	await _test_my_turn_and_submit(scene, fake)
	await _test_sequence(scene, fake)
	_test_watcher(scene, fake)
	await _test_polling(scene, fake)
	_test_quit(scene, fake)
	_test_net_over_notice(scene)

	# A 段收尾：把假会话场景摘掉，再跑 B 段（真 ENet，3 个进程内实例）
	scene.queue_free()
	await process_frame
	await _test_real_enet()

	if fails == 0:
		print("ALL UI ONLINE TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d TEST(S) FAILED" % [fails, checks])
	quit(0 if fails == 0 else 1)


# ------------------------------------------------------------
# 小工具：面板 / 手牌区的当前内容（同一帧里新旧子节点并存，必须跳过 queue_free 的）
# ------------------------------------------------------------
func _panel_buttons(scene) -> Array:
	var out: Array = []
	for c in scene.action_panel.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _panel_labels(scene) -> Array:
	var out: Array = []
	for c in scene.action_panel.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _hand_texts(scene) -> String:
	var out: Array = []
	for c in scene.hand_container.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(c.text)
	return "\n".join(out)


# ------------------------------------------------------------
# 1) 单机基线：这些行为在挂了会话之后必须整体改变
# ------------------------------------------------------------
func _test_single_player_baseline(scene) -> void:
	var gm = scene.game_manager
	_check(scene.net_session == null, "单机：net_session 为空")
	_check(scene.call("_is_hotseat"), "单机 3 真人 → 判定为热座")
	_check(scene.call("_hand_view_player") == gm.get_current_player(),
		"单机：手牌视角 = 当前行动者")
	_check(scene.call("_view_player") == gm.get_current_player(),
		"单机：_view_player = 当前行动者")
	_check(scene.call("_net_wait_text") == "", "单机：没有等待文案")
	_check(scene.call("_net_can_operate") == false, "单机：_net_can_operate 恒为 false（不参与门控）")


# ------------------------------------------------------------
# 2) attach_session：装配 + D7（热座关闭）+ 进牌桌
# ------------------------------------------------------------
func _test_attach(scene, fake) -> void:
	var gm = scene.game_manager
	_check(scene.net_session == fake, "attach_session 后 net_session 已就位")
	_check(scene.action_router != null and scene.action_router.session == fake,
		"动作层已切到联机分支（router.session = 会话）")
	_check(scene.action_router.game == gm, "动作层持有同一个 GameManager")
	_check(scene.call("_my_seat") == 1, "本地座位 = 1")
	_check(scene.call("_is_hotseat") == false, "D7：挂了会话就不再是热座")
	_check(scene.call("_hotseat_handoff_pending") == false,
		"D7：联机不弹交接遮罩（3 真人局不会被卡死）")
	_check(scene.game_page.visible, "联机开局：已切到牌桌 GamePage")
	_check(scene._hotseat_ready_seat == -1, "装配时清空热座认领残留")
	_check(scene.call("_view_player") == gm.players[1], "D6：_view_player = 自己座位（players[1]）")


# ------------------------------------------------------------
# 3) 别人回合：只看自己的牌、只读、面板只给等待文案
# ------------------------------------------------------------
func _test_other_turn_view(scene, fake) -> void:
	var gm = scene.game_manager
	var me = gm.players[1]
	_check(gm.get_current_player() == gm.players[0], "当前行动者是座位 0（不是我）")
	_check(scene.call("_hand_view_player") == me,
		"D6：手牌视角仍是自己（不跟着当前行动者走）")
	scene.call("_refresh_ui")

	_check(scene._hand_read_only, "别人回合：手牌只读")
	_check(scene.call("_can_reorder_hand") == false, "别人回合：不允许拖拽重排")
	# 渲染出来的必须是「我」的牌，且顺序与数据层一致（只读不排序）
	var n: int = scene.hand_buttons.size()
	var same: bool = n == me.hand.size() and n > 0
	for i in range(mini(n, me.hand.size())):
		if scene.hand_buttons[i].get_meta("card") != me.hand[i]:
			same = false
			break
	_check(same, "别人回合：手牌区渲染的是自己的 %d 张牌（非当前行动者）" % n)
	_check(_hand_texts(scene) == "", "别人回合：手牌区没有「等待」占位文字（看的到牌）")

	var btns: Array = _panel_buttons(scene)
	var labels: Array = _panel_labels(scene)
	_check(btns.is_empty(), "别人回合：操作面板没有任何按钮")
	_check(labels.size() == 1, "别人回合：操作面板只有一句等待提示（实际 %d 个 Label）" % labels.size())
	if labels.size() == 1:
		_check(labels[0].text.begins_with("等待") and labels[0].text.contains(gm.players[0].player_name),
			"等待文案写明在等谁：%s" % labels[0].text)

	# 选中的牌必须来自「我」的手牌（索引来自我这边的手牌按钮）
	scene.selected_indices = [0]
	var picked: Array = scene.call("_sel_cards")
	_check(picked.size() == 1 and picked[0] == me.hand[0],
		"D6：_sel_cards 取的是自己手牌（不是当前行动者的）")
	scene.selected_indices = []


# ------------------------------------------------------------
# 4) D8：联机下 UI 的 AI 计时器必须关掉（客人绝不能本地替 AI 出牌）
# ------------------------------------------------------------
func _test_ai_gate(scene) -> void:
	var gm = scene.game_manager
	var ai_backup: bool = gm.players[0].is_ai
	gm.players[0].is_ai = true
	scene.ai_triggered = false
	scene.call("_refresh_ui")
	_check(scene.ai_triggered == false,
		"D8：联机下不给 AI 起本地计时器（单机会在这里置 ai_triggered）")
	_check(scene._net_ai_wait == 0.0, "D8：客人不累计主机专用 AI 节流")
	var h0: int = gm.state_hash()
	await process_frame
	await process_frame
	_check(gm.state_hash() == h0, "D8：两帧之内本地局面没有被偷偷改动（hash 未变）")
	gm.players[0].is_ai = ai_backup


# 通过 UI 真入口提交一笔（手牌到上限时走「弃牌跳过」分支）
func _submit_via_ui(scene) -> String:
	var gm = scene.game_manager
	var me = gm.players[1]
	if me.get_hand_count() >= gm.get_hand_limit():
		scene.step_mode = 3
		scene.selected_indices = [0]
		scene.call("_on_discard_mode")
		return NetProtocolScript.INTENT_DISCARD_PASS
	scene.call("_on_pass")
	return NetProtocolScript.INTENT_PASS


# ------------------------------------------------------------
# 5) 轮到我：可操作 → 提交 → 待裁决 → 裁决 / 被拒
# ------------------------------------------------------------
func _test_my_turn_and_submit(scene, fake) -> void:
	var gm = scene.game_manager
	var me = gm.players[1]
	fake.turn_seat = 1
	scene.call("_refresh_ui")
	_check(scene.call("_net_can_operate"), "轮到我：_net_can_operate = true")
	_check(scene._hand_read_only == false, "轮到我：手牌可操作")
	_check(scene.call("_can_reorder_hand"), "轮到我：允许拖拽重排")
	_check(_panel_buttons(scene).size() >= 3,
		"轮到我：操作面板恢复按钮（%d 个）" % _panel_buttons(scene).size())
	_check(_panel_labels(scene).is_empty(), "轮到我：没有等待文案")

	var h0: int = gm.state_hash()
	var n0: int = me.hand.size()
	var want_type: String = _submit_via_ui(scene)
	_check(fake.submits.size() == 1, "D1：客人提交了一笔意图（%d 笔）" % fake.submits.size())
	if fake.submits.size() == 1:
		_check(String(fake.submits[0]["type"]) == want_type,
			"意图类型正确：%s" % String(fake.submits[0]["type"]))
	_check(scene.action_router.awaiting_reply(), "D1：提交后 awaiting_reply = true")
	_check(gm.state_hash() == h0, "D1：客人提交后本地 hash 不变（等主机裁决）")
	_check(me.hand.size() == n0, "D1：客人提交后本地手牌不变")

	var labels: Array = _panel_labels(scene)
	_check(labels.size() == 1 and labels[0].text.contains("已提交"),
		"D1：面板显示「已提交，等待主机裁决…」")
	scene.call("_refresh_ui")
	_check(scene._hand_read_only, "D1：待裁决期间手牌只读")
	_check(scene.call("_net_can_operate") == false, "D1：待裁决期间不能再次提交")

	# 主机裁决回来（state_applied）→ 解除等待，面板恢复
	fake.state_applied.emit({"type": "pass", "by": 1}, 0)
	await process_frame
	_check(scene.action_router.awaiting_reply() == false, "state_applied 后解除「待裁决」")
	_check(_panel_buttons(scene).size() >= 3, "裁决回来后操作面板恢复按钮")

	# 主机拒绝（intent_rejected）→ 解除等待 + 提示原因
	var before: int = fake.submits.size()
	var _t2: String = _submit_via_ui(scene)
	_check(fake.submits.size() == before + 1, "被拒前又提交了一笔（共 %d 笔）" % fake.submits.size())
	fake.intent_rejected.emit(9, -2)
	_check(scene.action_router.awaiting_reply() == false, "intent_rejected 后解除「待裁决」")
	_check(scene._warning_label != null and scene._warning_label.text.contains("主机拒绝"),
		"被拒后弹出「主机拒绝：…」提示")


# ------------------------------------------------------------
# 6) 两阶段（顺序牌型）：只有「等我选」才弹窗，收窗走 sequence_cleared
# ------------------------------------------------------------
func _test_sequence(scene, fake) -> void:
	fake.pending = 1
	fake.sequence_pending.emit(1, 15000)
	_check(scene._seq_overlay != null, "轮到我选牌型：弹出顺序牌型弹窗")
	scene.call("_refresh_ui")
	_check(scene.call("_net_can_operate") == false, "待选牌型：不能提交动作")
	_check(scene._hand_read_only, "待选牌型：手牌只读")
	var labels: Array = _panel_labels(scene)
	_check(labels.size() == 1 and labels[0].text.contains("弹窗"),
		"待选牌型：面板提示「请先在弹窗中选择牌型…」")

	fake.pending = -1
	fake.sequence_cleared.emit()
	_check(scene._seq_overlay == null, "sequence_cleared 后弹窗已关闭")
	scene.call("_refresh_ui")
	_check(_panel_buttons(scene).size() >= 3, "收窗后操作面板恢复按钮")

	# 别人选牌型：本端只刷等待态，不弹窗
	fake.sequence_pending.emit(0, 8000)
	_check(scene._seq_overlay == null, "别人选牌型：本端不弹窗")
	fake.sequence_cleared.emit()

	# 状态分叉：已经弹出来的窗口必须被收掉，否则遮罩会一直挡住界面
	fake.pending = 1
	fake.sequence_pending.emit(1, 5000)
	_check(scene._seq_overlay != null, "分叉前：顺序牌型弹窗已弹出")
	fake.desync_detected.emit(11, 22)
	_check(scene._seq_overlay == null, "状态分叉：顺序牌型弹窗被收掉（不留遮罩）")
	# D20：分叉原因必须钉在卡牌信息栏，不能下一帧就被回合提示盖掉
	scene.call("_update_card_info_label")
	var info_after_desync := String(scene.card_info_label.text)
	_check(info_after_desync.begins_with("⚠ ") and info_after_desync.find("状态分叉") >= 0,
		"状态分叉：卡牌信息栏显示「⚠ 状态分叉…」（实际 %s）" % info_after_desync)
	_check(scene._warning_toast != null and scene._warning_toast.visible,
		"状态分叉：toast 就地弹出（不挂 2.5 秒计时器）")
	# 清掉，免得污染后面的用例（真实流程里由新局 / 回开始页清）
	scene.call("_clear_net_over_notice")
	scene.call("_update_card_info_label")
	_check(not String(scene.card_info_label.text).begins_with("⚠ "),
		"清掉提示后卡牌信息栏回到回合文本（实际 %s）" % String(scene.card_info_label.text))
	fake.pending = -1
	fake.sequence_cleared.emit()


# ------------------------------------------------------------
# 7) 观战：无座位 → 谁的牌都不显示，面板只给「观战中」
# ------------------------------------------------------------
func _test_watcher(scene, fake) -> void:
	var seat_backup: int = fake.my_seat
	fake.my_seat = -1
	scene.call("_refresh_ui")
	_check(scene.call("_view_player") == null, "观战：_view_player = null")
	_check(scene.call("_hand_view_player") == null, "观战：手牌视角 = null")
	_check(scene.hand_buttons.is_empty(), "观战：手牌区一张牌都不渲染")
	_check(_hand_texts(scene).contains("观战"), "观战：手牌区写明「观战中」")
	_check(scene.call("_net_wait_text").contains("观战"), "观战：面板等待文案 = 观战中")
	_check(scene.call("_net_can_operate") == false, "观战：不能操作")
	_check(_panel_buttons(scene).is_empty(), "观战：面板没有任何按钮")
	fake.my_seat = seat_backup
	scene.call("_refresh_ui")


# ------------------------------------------------------------
# 8) 每帧驱动：_process 必须先 poll 会话
# ------------------------------------------------------------
func _test_polling(scene, fake) -> void:
	var p0: int = fake.polls
	await process_frame
	await process_frame
	await process_frame
	_check(fake.polls > p0, "_process 每帧 poll 会话（%d → %d）" % [p0, fake.polls])


# ------------------------------------------------------------
# 9b) 终局提示常驻（D20 / D21）：房主退出 / 失联 / 分叉的原因不能只闪 2.5 秒
#     真机反馈：房主退出后，客人牌桌只剩「等待 玩家 1 行动…」，看起来像卡死。
# ------------------------------------------------------------
func _test_net_over_notice(scene) -> void:
	scene.call("_online_on_session_closed", "与主机的连接已断开")
	var notice := String(scene._net_over_notice)
	_check(notice.find("联机已结束") >= 0 and notice.find("与主机的连接已断开") >= 0,
		"会话关闭 → 原因写进常驻提示（%s）" % notice)
	_check(scene._warning_toast != null and scene._warning_toast.visible
			and String(scene._warning_label.text).find("联机已结束") >= 0,
		"会话关闭 → toast 显示原因（sticky，不自动消失）")
	var info := String(scene.card_info_label.text)
	_check(info.begins_with("⚠ ") and info.find("联机已结束") >= 0,
		"卡牌信息栏被终止提示占住（实际 %s）" % info)
	# 继续收包 / 每帧刷新都不能把这句话顶掉
	scene.call("_update_card_info_label")
	scene.call("_refresh_ui")
	scene.call("_update_card_info_label")
	_check(String(scene.card_info_label.text).find("联机已结束") >= 0,
		"刷新之后仍是终止提示（实际 %s）" % String(scene.card_info_label.text))
	# 回开始页 / 新局：这句必须清掉，否则下一局一进牌桌就顶着上一局的告警
	scene.call("_clear_net_over_notice")
	scene.call("_update_card_info_label")
	_check(not String(scene.card_info_label.text).begins_with("⚠ "),
		"清掉后不再显示「⚠ …」（实际 %s）" % String(scene.card_info_label.text))


# ------------------------------------------------------------
# 10) 退出：联机路径只关会话，不写 game.phase
# ------------------------------------------------------------
func _test_quit(scene, fake) -> void:
	var gm = scene.game_manager
	# 退出时还开着的顺序牌型弹窗，必须在会话关闭时被收掉
	fake.pending = 1
	fake.sequence_pending.emit(1, 5000)
	_check(scene._seq_overlay != null, "退出前：顺序牌型弹窗已弹出")
	fake.pending = -1
	scene._quit_confirm_pending = false
	scene.call("_on_quit_game")
	_check(fake.playing == false, "退出：会话已关闭")
	_check(fake.closed_reason != "", "退出：关闭原因已写入（%s）" % fake.closed_reason)
	_check(gm.phase != 2, "D11：联机退出不写 game.phase（本端不擅自结束对局）")
	_check(scene.end_page.visible, "退出后进入结算页")
	_check(scene._seq_overlay == null, "退出：会话关闭后顺序牌型弹窗被收掉")


# ============================================================
# B 段：3 个进程内 Main.tscn 实例 + 真实 ENet（决策 B-段）
#   验证的是「UI 装配 + 会话 + 动作路由」整条链路在真网络上跑通：
#   · 每端只看自己的手牌（D6）
#   · 客人提交只发包、不写本地局面（D1）
#   · 主机 _update_net 代打 AI 座位（D8）
#   · 三端 state_hash / event_log 逐笔一致，无分叉告警
# ============================================================
const PORT_UI = 47827
const UI_CONNECT_TIMEOUT_MS = 8000
const UI_PLAY_TIMEOUT_MS = 45000
const UI_STEPS = 6


# 一个端点 = 一棵 Main.tscn + 独立 GameManager + 独立 NetSession/ENetTransport
func _make_ui():
	var ui = load("res://Main.tscn").instantiate()
	root.add_child(ui)
	var gm = GameManagerScript.new()
	var tr = NetTransportScript.new()
	var s = NetSessionScript.new()
	s.setup(gm, tr)
	ui.game_manager = gm
	ui.call("attach_session", s)
	return ui


func _all_seats(uis: Array) -> bool:
	if uis[0].net_session.seat_count() < 3:
		return false
	for i in range(1, uis.size()):
		if int(uis[i].net_session.my_seat) < 0:
			return false
	return true


func _all_playing(uis: Array) -> bool:
	for ui in uis:
		if not ui.net_session.is_playing():
			return false
	return true


# 三端事件流是否已追平（条数 + 指纹都要一致）
func _logs_equal(uis: Array) -> bool:
	var g0 = uis[0].game_manager
	var n: int = g0.event_log.size()
	for i in range(1, uis.size()):
		var g = uis[i].game_manager
		if g.event_log.size() != n or g.state_hash() != g0.state_hash():
			return false
	return true


func _ui_of_seat(uis: Array, seat: int):
	for ui in uis:
		if int(ui.net_session.my_seat) == seat:
			return ui
	return null


# 手动泵：等价于每端一帧 _process 的联机部分（不等真实帧，测试才够快）
func _pump_until(uis: Array, cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for ui in uis:
			ui.call("_update_net", 0.02)
		if bool(cond.call()):
			return true
		OS.delay_msec(2)
	return false


# 让某个端点在它自己的回合「跳过 / 弃牌跳过」（总合法，不依赖手牌）
func _act(ui) -> void:
	var gm = ui.game_manager
	var me = gm.get_current_player()
	if me.get_hand_count() >= gm.get_hand_limit():
		ui.step_mode = 3
		ui.selected_indices = [0]
		ui.call("_on_discard_mode")
	else:
		ui.call("_on_pass")


# ------------------------------------------------------------
# B 段主流程
# ------------------------------------------------------------
func _test_real_enet() -> void:
	var uis: Array = []
	for i in range(3):
		uis.append(_make_ui())
	await process_frame
	await process_frame

	var host = uis[0]
	var hs = host.net_session
	_check(hs.start_host(PORT_UI, 3, "房主") == 0,
		"B：主机在端口 %d 监听（名额预留 4 个给重连 / 观战）" % PORT_UI)
	for i in range(1, 3):
		_check(uis[i].net_session.start_client("127.0.0.1", PORT_UI, "客人%d" % i) == 0,
			"B：客人 %d 发起连接" % i)
	_check(_pump_until(uis, func() -> bool: return _all_seats(uis), UI_CONNECT_TIMEOUT_MS),
		"B：三个端点完成握手 / 座位分配")
	if not _all_seats(uis):
		# 连不上就别继续往下断言（后面全是依赖座位号的调用）
		for ui in uis:
			ui.net_session.close("连接失败")
		_check(false, "B：连接阶段失败，后续联机断言跳过")
		return
	_check(hs.seat_count() == 3, "B：房主看到 3 个座位（实际 %d）" % hs.seat_count())
	_check(int(uis[1].net_session.my_seat) != int(uis[2].net_session.my_seat),
		"B：两个客人拿到不同座位")

	# 3 座位 + 1 AI：座位 2 是 AI，正好验证主机代打（D8）
	_check(hs.start_game(3, 1) == 0, "B：主机开局（3 座位 / 1 AI）")
	_check(_pump_until(uis, func() -> bool: return _all_playing(uis), UI_CONNECT_TIMEOUT_MS),
		"B：三端都进入 PLAYING（快照重放完成）")
	_check(host.game_page.visible, "B：房主 UI 已切到牌桌（game_started → _enter_online_game）")
	_check(uis[1].game_page.visible, "B：客人 UI 已切到牌桌")
	_check(uis[2].game_page.visible, "B：第二位客人 UI 已切到牌桌")

	# D6：每端视角 = 自己的座位，渲染的也是自己的牌
	var view_ok := true
	var hand_ok := true
	var detail := ""
	for i in range(3):
		var ui = uis[i]
		var seat := int(ui.net_session.my_seat)
		if ui.call("_my_seat") != seat or ui.call("_view_player") != ui.game_manager.players[seat]:
			view_ok = false
			detail += "端点%d 视角不对 " % i
			continue
		var me = ui.game_manager.players[seat]
		var btns: Array = ui.hand_buttons
		if btns.size() != me.hand.size():
			hand_ok = false
			detail += "端点%d 渲染 %d/实有 %d " % [i, btns.size(), me.hand.size()]
			continue
		for k in range(btns.size()):
			if btns[k].get_meta("card") != me.hand[k]:
				hand_ok = false
				detail += "端点%d 第%d张不是自己的牌 " % [i, k]
				break
	_check(view_ok, "B：D6 每端视角都是自己的座位（%s）" % ("OK" if view_ok else detail))
	_check(hand_ok, "B：D6 每端手牌区渲染的都是自己的牌（%s）" % ("OK" if hand_ok else detail))

	# ---- 真打几手：轮到的端点自己点「跳过 / 弃牌跳过」，AI 座位交给主机代打 ----
	var host_gm = host.game_manager
	var base_events: int = host_gm.event_log.size()
	var guest_submit_checked := false
	var guard := Time.get_ticks_msec() + UI_PLAY_TIMEOUT_MS
	while Time.get_ticks_msec() < guard and host_gm.event_log.size() < base_events + UI_STEPS:
		for ui in uis:
			ui.call("_update_net", 0.05)
		var seat := int(host_gm.current_player_index)
		var actor = _ui_of_seat(uis, seat)
		if actor != null:
			var s = actor.net_session
			if s.can_submit() and s.is_my_turn() and not actor.action_router.awaiting_reply():
				if not s.is_host() and not guest_submit_checked:
					# 客人提交那一刻：本地局面必须一动不动（等主机裁决）
					var local_hash: int = actor.game_manager.state_hash()
					var local_size: int = actor.game_manager.get_current_player().hand.size()
					var local_log: int = actor.game_manager.event_log.size()
					_act(actor)
					_check(actor.action_router.awaiting_reply(),
						"B：D1 客人提交后 awaiting_reply = true")
					_check(actor.game_manager.state_hash() == local_hash,
						"B：D1 客人提交不改本地 state_hash")
					_check(actor.game_manager.get_current_player().hand.size() == local_size,
						"B：D1 客人提交不改本地手牌")
					_check(actor.game_manager.event_log.size() == local_log,
						"B：D1 客人提交不写本地 event_log")
					guest_submit_checked = true
				else:
					_act(actor)
		OS.delay_msec(2)

	# 收尾：把最后几笔广播也收齐（主机最后一手可能刚发出，客人下一轮才读到）
	_check(_pump_until(uis, func() -> bool: return _logs_equal(uis), 4000),
		"B：三端收齐最后几笔广播")

	var n_events: int = host_gm.event_log.size()
	_check(n_events > base_events,
		"B：对局推进了 %d 笔事件（%d → %d）" % [n_events - base_events, base_events, n_events])
	_check(guest_submit_checked, "B：至少发生过一次「客人提交 → 等主机裁决」")

	var hash_ok := true
	var log_ok := true
	var detail2 := ""
	for i in range(1, 3):
		var g = uis[i].game_manager
		if g.state_hash() != host_gm.state_hash():
			hash_ok = false
			detail2 += "端点%d hash %d≠%d " % [i, g.state_hash(), host_gm.state_hash()]
		if g.event_log.size() != n_events:
			log_ok = false
			detail2 += "端点%d 事件 %d≠%d " % [i, g.event_log.size(), n_events]
	_check(hash_ok, "B：三端 state_hash 一致（%s）" % ("OK" if hash_ok else detail2))
	_check(log_ok, "B：三端 event_log 条数一致（%s）" % ("OK" if log_ok else detail2))

	# D8 的正面证明：座位 2（AI）的动作是主机代打后广播出去的
	var ai_acted := false
	for ev in host_gm.event_log:
		if int(ev.get("by", -1)) == 2:
			ai_acted = true
			break
	_check(ai_acted, "B：D8 AI 座位（seat 2）由主机 _update_net 代打并广播")
	_check(host.net_session.is_desynced() == false and uis[1].net_session.is_desynced() == false
			and uis[2].net_session.is_desynced() == false,
		"B：全程没有触发分叉告警")

	for ui in uis:
		ui.net_session.close("测试结束")
	await process_frame









