# ============================================================
# tests/verify_vote_ui.gd - 化合物质疑投票的界面层（D22 · S5）
#
# 只测「界面是否如实反映权威状态」，不重复协议 / 规则（那两段在
# verify_net_vote.gd 与 verify_vote_box.gd 里）。用一个假会话把
# NetSession 的投票读口换成可控开关，于是这里能精确构造：
#   U1 开票：遮罩挂到 OverlayLayer / 牌面按元素配色 / 票型与分母照抄快照
#   U2 冻结：投票期间操作面板只剩一句等待文案，一个按钮都不给
#   U3 投票：点赞成 → cast_vote 只发一次 → 按钮锁死并写明「已投」
#   U4 非投票人：出题人 / 观战者按钮禁用，提示「你不在名单里」
#   U5 收口：通过 / 反对 / 超时 / 无人可投 四种文案各自正确
#   U6 倒计时：tick 刷新剩余秒数；投票已被收口但遮罩还开着 → 自愈关闭
#   U7 重连：attach_session 时正在投票 → 自动补开遮罩
#   U8 收尾：会话关闭 / 新开局 → 遮罩必须消失（否则永远盖着牌桌）
#   U9 桌面：通过的那一手在桌面上带「（投票认定）」标记
#
# 运行：godot --headless --path . --script tests/verify_vote_ui.gd
# ============================================================
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const PLAYER_COUNT = 3
const COMPOUND = CardPatternsScript.CardPattern.COMPOUND

var fails: int = 0
var checks: int = 0


# ------------------------------------------------------------
# 假会话：只实现 UI 用到的那几个读口 + 三个投票信号。
# 故意不继承 NetSession —— 逼着界面只依赖接口。
# ------------------------------------------------------------
class FakeVoteSession:
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
	signal vote_opened(state: Dictionary)
	signal vote_updated(state: Dictionary)
	signal vote_resolved(result: Dictionary)

	var role: int = 2
	var my_seat: int = 1
	var playing: bool = true
	var turn_seat: int = 1
	var pending: int = -1
	var desynced: bool = false

	# 投票快照（空 = 没有投票）
	var snap: Dictionary = {}
	var remain: int = 0
	var casts: Array = []

	func ai_count() -> int: return 0
	func is_playing() -> bool: return playing
	func is_host() -> bool: return role == 1
	func is_watcher() -> bool: return my_seat < 0
	func is_desynced() -> bool: return desynced
	func is_my_turn() -> bool: return playing and my_seat >= 0 and turn_seat == my_seat
	func pending_seat() -> int: return pending
	func is_my_sequence_pending() -> bool: return pending >= 0 and pending == my_seat
	func all_seats_ready() -> bool: return true
	func poll() -> void: pass
	func close(reason: String = "") -> void:
		playing = false
		snap = {}
		session_closed.emit(reason)

	func host_step_ai(_max_steps: int = 1) -> int: return 0
	func my_hand_uids() -> Array: return []
	func is_seat_ai(_seat: int) -> bool: return false
	func seat_name(seat: int) -> String: return "玩家%d" % (int(seat) + 1)

	# 投票期间全场冻结：服务端那边就是 can_submit() == false
	func can_submit() -> bool:
		return playing and my_seat >= 0 and not desynced and pending < 0 and snap.is_empty()

	func can_claim() -> bool:
		return playing and my_seat >= 0 and snap.is_empty()

	func vote_open() -> bool:
		return not snap.is_empty() and not bool(snap.get("resolved", false))

	func vote_state() -> Dictionary: return snap.duplicate(true)
	func vote_remain_ms() -> int: return remain

	func am_i_voter() -> bool:
		if snap.is_empty():
			return false
		var voters = snap.get("voters", [])
		return voters is Array and (voters as Array).has(my_seat)

	func my_vote() -> int:
		var votes = snap.get("votes", {})
		if not (votes is Dictionary) or not (votes as Dictionary).has(my_seat):
			return -1
		return 1 if bool(votes[my_seat]) else 0

	func cast_vote(approve: bool) -> int:
		if snap.is_empty():
			return -112
		casts.append(approve)
		return 0

	func submit(intent_type: String, payload: Dictionary = {}) -> int:
		return 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	scene.game_manager = GameManagerScript.new()
	scene.game_manager.init_game(PLAYER_COUNT, 0, 20250104)
	scene.call("_refresh_ui")

	var fake := FakeVoteSession.new()
	fake.my_seat = 1
	fake.turn_seat = 1
	scene.call("attach_session", fake)
	await process_frame

	var ui = scene.ui_vote
	_check(ui != null, "U1 GameUI 持有 ui_vote 实例")
	_check(not ui.is_open(), "U1 开局没有投票遮罩")

	var snap := _make_snap(scene)
	if snap.is_empty():
		_check(false, "U1 构造投票快照失败（该种子手牌不足）")
		_finish()
		return

	_test_open(scene, fake, snap)
	_test_freeze_panel(scene, fake)
	_test_cast(scene, fake, snap)
	_test_update(scene, fake, snap)
	_test_non_voter(scene, fake, snap)
	_test_resolve_text(ui)
	_test_tick(scene, fake, snap)
	_test_reconnect(scene, fake, snap)
	_test_session_closed(scene, fake, snap)
	_test_table_marker(scene)
	_finish()


func _finish() -> void:
	if fails == 0:
		print("ALL VOTE UI TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d VOTE UI TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------
# 小工具
# ------------------------------------------------------------
func _make_snap(scene) -> Dictionary:
	var hand: Array = scene.game_manager.players[0].hand
	if hand.size() < 2:
		return {}
	var a = hand[0]
	var b = null
	for c in hand:
		if String(c.symbol) != String(a.symbol):
			b = c
			break
	if b == null:
		return {}
	return {
		"vid": 1, "by": 0, "voters": [1, 2], "votes": {},
		"claim": {
			"uids": [int(a.uid), int(b.uid)],
			"valences": {String(a.symbol): 1, String(b.symbol): -1},
			"pattern": COMPOUND,
		},
		"reason": "这组牌不构成任何合法牌型（单质 / 化合物 / 顺序 / 族炸 / 有机物）",
		"total": 2, "approve_count": 0, "reject_count": 0,
		"remain_ms": 15000, "resolved": false, "approved": false, "cause": "",
	}


func _open(scene, fake, snap: Dictionary, remain: int = 15000) -> void:
	fake.snap = snap.duplicate(true)
	fake.remain = remain
	fake.vote_opened.emit(snap.duplicate(true))


func _live_children(node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if not c.is_queued_for_deletion():
			out.append(c)
	return out


# ------------------------------------------------------------
# U1 开票：遮罩位置 / 牌面 / 票型 / 按钮可用性
# ------------------------------------------------------------
func _test_open(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	_open(scene, fake, snap)
	_check(ui.is_open(), "U1 开票后遮罩出现")
	_check(ui._overlay.get_parent() == scene.overlay_layer,
		"U1 遮罩挂在 OverlayLayer（盖住手牌与工具行）")
	_check(ui._overlay.mouse_filter == Control.MOUSE_FILTER_STOP,
		"U1 遮罩吞掉所有点击（投票期间不能点牌桌）")
	var uids: Array = snap["claim"]["uids"]
	_check(_live_children(ui._cards_row).size() == uids.size(),
		"U1 待裁定的 %d 张牌都画出来了" % uids.size())
	_check(ui._who.text.find("玩家1") >= 0, "U1 写明是谁提请裁定：%s" % ui._who.text)
	_check(ui._reason.text.find("引擎判定：") == 0 and ui._reason.text.length() > 6,
		"U1 带上引擎的人话原因（不是空白）：%s" % ui._reason.text)
	_check(ui._tally.text.find("分母 2 人") >= 0, "U1 分母照抄快照：%s" % ui._tally.text)
	_check(ui._tally.text.find("待投：玩家2、玩家3") >= 0,
		"U1 未投名单由 voters - votes 算出：%s" % ui._tally.text)
	_check(not ui._yes.disabled and not ui._no.disabled,
		"U1 我是投票人 → 两个按钮都可点")
	_check(ui._hint.text.find("全票赞成") >= 0, "U1 默认提示讲清通过 / 不通过后果")


# ------------------------------------------------------------
# U2 冻结：面板只剩一句等待文案，一个按钮都不给
# ------------------------------------------------------------
func _test_freeze_panel(scene, fake) -> void:
	var btn: Array = []
	var lbl: Array = []
	for c in _live_children(scene.action_panel):
		if c is Button:
			btn.append(c)
		elif c is Label:
			lbl.append(c)
	_check(scene.call("_net_can_operate") == false, "U2 投票期间不能操作手牌")
	_check(scene.call("_net_wait_text") == "正在投票裁定上一手牌，等待结果…",
		"U2 等待文案说明是在等票（不是卡住）")
	_check(btn.is_empty(), "U2 操作面板没有任何按钮（实际 %d）" % btn.size())
	_check(lbl.size() == 1 and lbl[0].text.find("投票") >= 0,
		"U2 操作面板只有一句投票提示")
	_check(not fake.can_submit(), "U2 会话层 can_submit = false（与服务端 -111 一致）")


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


# ------------------------------------------------------------
# U3 投票：只发一次，发完锁死并写明「已投」
# ------------------------------------------------------------
func _test_cast(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	ui._yes.pressed.emit()
	_check(fake.casts.size() == 1 and bool(fake.casts[0]),
		"U3 点赞成 → 向会话发出 1 张赞成票 (实际 %s)" % str(fake.casts))
	_check(ui._yes.disabled and ui._no.disabled, "U3 投完立刻锁死两个按钮")
	_check(ui._hint.text.find("已投赞成") >= 0, "U3 提示已投：%s" % ui._hint.text)
	# 宿主广播回来的票型里同样有这一票 → 仍然是锁死的（幂等，不会「解锁」）
	fake.snap = snap.duplicate(true)
	fake.snap["votes"] = {1: true}
	fake.snap["approve_count"] = 1
	fake.vote_updated.emit(fake.snap.duplicate(true))
	_check(ui._yes.disabled and ui._no.disabled, "U3 票型回传后依旧锁死（不能翻牌）")
	_check(ui._tally.text.find("赞成 1") >= 0, "U3 票型实时刷新：%s" % ui._tally.text)


# ------------------------------------------------------------
# U4 票型变化 / 未投名单 / 我这一票在快照里的回显
# ------------------------------------------------------------
func _test_update(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	fake.snap = snap.duplicate(true)
	fake.snap["votes"] = {1: true}
	fake.snap["approve_count"] = 1
	fake.vote_updated.emit(fake.snap.duplicate(true))
	_check(ui._tally.text.find("待投：玩家3") >= 0,
		"U4 已投的人从「待投」里消失：%s" % ui._tally.text)
	_check(ui._hint.text.find("已投赞成") >= 0, "U4 我的票回显成「已投赞成」")

	fake.snap["votes"] = {1: false, 2: true}
	fake.snap["approve_count"] = 1
	fake.snap["reject_count"] = 1
	fake.vote_updated.emit(fake.snap.duplicate(true))
	_check(ui._tally.text.find("反对 1") >= 0 and ui._tally.text.find("待投") < 0,
		"U4 全投完 → 不再显示待投：%s" % ui._tally.text)
	_check(ui._hint.text.find("已投反对") >= 0, "U4 一票反对也如实回显")


# ------------------------------------------------------------
# U5 非投票人（出题人 / 观战者）：按钮禁用 + 明确说「你不在名单里」
# ------------------------------------------------------------
func _test_non_voter(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	fake.my_seat = 0                     # 出题人自己
	fake.snap = snap.duplicate(true)
	fake.vote_updated.emit(fake.snap.duplicate(true))
	_check(ui._yes.disabled and ui._no.disabled, "U5 出题人不能给自己投票（按钮禁用）")
	_check(ui._hint.text.find("不在这次投票的名单里") >= 0,
		"U5 出题人看到「你不参与裁定」：%s" % ui._hint.text)

	fake.my_seat = -1                    # 观战者
	fake.vote_updated.emit(fake.snap.duplicate(true))
	_check(ui._yes.disabled and ui._no.disabled, "U5 观战者也不能投票")

	fake.my_seat = 1                     # 复原
	fake.vote_updated.emit(fake.snap.duplicate(true))
	_check(not ui._yes.disabled, "U5 回到投票人视角后按钮恢复可点")


# ------------------------------------------------------------
# U6 四种结论文案
# ------------------------------------------------------------
func _test_resolve_text(ui) -> void:
	_check(ui.call("_result_text", {"approved": true}).find("落子") >= 0,
		"U6 通过 → 文案讲「落子」")
	_check(ui.call("_result_text", {"approved": false, "cause": "rejected"}).find("有人反对") >= 0,
		"U6 反对 → 文案讲「有人反对」")
	_check(ui.call("_result_text", {"approved": false, "cause": "timeout"}).find("超时") >= 0,
		"U6 超时 → 文案讲「超时」")
	_check(ui.call("_result_text", {"approved": false, "cause": "no_voter"}).find("离线") >= 0,
		"U6 无人可投 → 文案讲「都离线了」")
	var t: String = ui.call("_result_text", {"approved": false, "cause": "rejected"})
	_check(t.find("罚抽 1 张") >= 0, "U6 未通过的结论必须写明罚抽 1 张")


# ------------------------------------------------------------
# U7 倒计时 + 「投票已收口但遮罩还开着」的自愈
# ------------------------------------------------------------
func _test_tick(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	_open(scene, fake, snap, 7300)
	ui.tick(0.016)
	_check(ui._timer.text.find("剩余 8 秒") >= 0, "U7 倒计时按毫秒四舍五入到秒：%s" % ui._timer.text)
	# 服务端收口了（vote_open 变 false），但 result 包丢了 → tick 必须自己收干净
	fake.snap = {}
	ui.tick(0.016)
	_check(not ui.is_open(), "U7 投票没了 → tick 自动关掉遮罩（不会永久盖住牌桌）")


# ------------------------------------------------------------
# U8 重连 / 中局加入：attach_session 时正在投票 → 自动补开
# ------------------------------------------------------------
func _test_reconnect(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	_check(not ui.is_open(), "U8 前置：遮罩已关")
	fake.snap = snap.duplicate(true)
	fake.remain = 5000
	scene.call("attach_session", fake)
	_check(ui.is_open(), "U8 重连时正在投票 → 遮罩自动补开（不靠信号，靠拉快照）")
	_check(ui._cards_row.get_child_count() == 2, "U8 补开时牌面也照常渲染")


# ------------------------------------------------------------
# U9 会话关闭：遮罩必须消失
# ------------------------------------------------------------
func _test_session_closed(scene, fake, snap: Dictionary) -> void:
	var ui = scene.ui_vote
	fake.snap = snap.duplicate(true)
	scene.call("attach_session", fake)
	_check(ui.is_open(), "U9 前置：投票遮罩开着")
	fake.close("房主离开了房间")
	_check(not ui.is_open(), "U9 会话关闭 → 遮罩消失（否则永远等不到 vote_resolved）")


# ------------------------------------------------------------
# U10 桌面标记：投票认定的那一手在桌面上必须自证来源
# ------------------------------------------------------------
func _test_table_marker(scene) -> void:
	# 退回单机，用同一份 GameManager 真跑一笔「投票通过」事件（V0 同口径）
	scene.call("attach_session", null)
	_check(scene.net_session == null, "U10 退回单机（动作层同步切回直连）")
	var gm = scene.game_manager
	var hit := _find_claimable(gm, 0)
	if hit.is_empty():
		_check(false, "U10 该种子没找到可质疑组合（测试前提失败）")
		return
	var uids: Array = []
	for c in hit["cards"]:
		uids.append(int(c.uid))
	var ev := {"type": "compound_ruling", "by": 0, "approved": true, "uids": uids,
		"valences": hit["cv"], "pattern": COMPOUND}
	_check(int(gm.apply_event(ev)) == 0, "U10 「投票通过」事件落子成功")
	_check(gm.is_compound_legalized(hit["cards"]), "U10 该组成已进白名单")
	scene.call("_update_table_label")
	_check(String(scene.table_label.text).find("（投票认定）") >= 0,
		"U10 桌面文案标注「（投票认定）」：%s" % scene.table_label.text)
	# 同一组牌若不是以化合物打出（牌型不同），不该被贴上投票标记
	gm.table_pattern = CardPatternsScript.CardPattern.ELEMENT
	scene.call("_update_table_label")
	_check(String(scene.table_label.text).find("（投票认定）") < 0,
		"U10 非化合物牌型不加「（投票认定）」")


# 手上找一组「配不平但值得质疑」的两张牌（与 verify_net_vote 同口径）
func _find_claimable(gm, seat: int) -> Dictionary:
	var hand: Array = gm.players[seat].hand
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			var a = hand[i]
			var b = hand[j]
			if String(a.symbol) == String(b.symbol):
				continue
			var cv := {String(a.symbol): 1, String(b.symbol): -1}
			var pair := [a, b]
			if int(gm.validate_play(seat, pair, cv, COMPOUND)) != -1:
				continue
			if int(gm.validate_play_claim(seat, pair, cv, COMPOUND)) < 0:
				continue
			return {"cards": pair, "cv": cv}
	return {}
