# 验证手牌拖拽重排（P7）
# 覆盖：数据层手动顺序 / 「按序」恢复 / 索引→卡片对象映射 / 拖出区外取消 / 布局回归
# 说明：拖拽本身由 _process 轮询真实鼠标驱动，headless 下鼠标恒为 (0,0)，
# 因此测试直接调用 _begin_drag() → 注入 _drag_slot → _finish_drag(落点)
# 复用同一套状态机，验证的是真实落库路径，而不是另写一份逻辑。
extends SceneTree

var fails: int = 0
var scene = null
var hc: Control = null
var cp = null

func _init():
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)

func _is_sorted(hand: Array) -> bool:
	for i in range(1, hand.size()):
		if hand[i - 1].atomic_number > hand[i].atomic_number:
			return false
	return true

# 手牌区内的一个落点（用于"松手仍在手牌区"的场景）
func _drop_inside() -> Vector2:
	return hc.get_global_rect().position + Vector2(20, 20)

func _run():
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_on_start_game")
	await process_frame
	await process_frame

	hc = scene.get_node_or_null("GamePage/HandContainer")
	cp = scene.game_manager.get_current_player()
	_check(hc != null, "手牌容器存在")
	_check(cp != null and not cp.is_ai, "开局当前玩家是人类玩家")
	if hc == null or cp == null or cp.is_ai:
		print("ABORT: 无法进入玩家回合")
		quit(1)
		return

	# ---------- A. 默认仍是自动排列（回归锁） ----------
	_check(not cp.hand_manual_order, "默认处于自动排列模式（hand_manual_order = false）")
	_check(_is_sorted(cp.hand), "开局手牌按原子序数升序")
	_check(scene._reorder_btn != null and not scene._reorder_btn.visible, "自动排列模式下「按序」按钮隐藏")

	scene.call("_update_hand_buttons")
	await process_frame
	_check(_is_sorted(cp.hand), "自动模式下重建手牌仍保持升序")

	# ---------- B. 数据层边界 ----------
	var n0: int = cp.hand.size()
	_check(not cp.move_card(-1, 2), "越界源下标 move_card 返回 false")
	_check(not cp.move_card(n0, 0), "越界目标下标 move_card 返回 false")
	_check(not cp.move_card(0, 0), "原地不动 move_card 返回 false 且不改顺序")
	_check(cp.hand.size() == n0 and _is_sorted(cp.hand), "上述非法调用均未改动手牌")

	# ---------- C. 拖拽一次：首张拖到第 4 张之前 ----------
	var dragged = cp.hand[0]
	scene.call("_begin_drag", 0)
	_check(scene._drag_active, "越过阈值后进入拖拽状态")
	_check(scene._drag_from == 0, "拖拽源下标为 0")
	_check(scene._drag_ghost != null and is_instance_valid(scene._drag_ghost), "拖拽时生成跟手幽灵牌")
	_check(scene._drag_line != null and is_instance_valid(scene._drag_line), "拖拽时显示插入指示线")
	scene._drag_slot = 4                       # 插到第 4 张之前
	scene.call("_finish_drag", _drop_inside())
	await process_frame
	await process_frame
	_check(cp.hand[3] == dragged, "拖到第 4 张之前后，原首张落到下标 3")
	_check(cp.hand.size() == n0, "重排不改变手牌张数")
	_check(cp.hand_manual_order, "拖拽后进入手动排列模式")
	_check(cp.hand[0] == dragged or cp.hand.find(dragged) == 3, "重排结果与数据层一致")
	_check(not is_instance_valid(scene._drag_ghost), "松手后幽灵牌已释放")
	_check(not is_instance_valid(scene._drag_line), "松手后插入指示线已释放")
	_check(scene._reorder_tip == "", "重排提示已被信息栏消费")
	_check(scene._reorder_btn.visible, "手动排列模式下「按序」按钮出现")

	# ---------- D. 按钮与数据层一一对应 ----------
	var ok_meta := true
	for i in range(cp.hand.size()):
		var b = scene.hand_buttons[i]
		if not is_instance_valid(b) or b.get_meta("card", false) != cp.hand[i]:
			ok_meta = false
	_check(ok_meta, "每个按钮的 card meta 与 PlayerInfo.hand 顺序逐一对应")

	# ---------- E. 手动模式下重建不打回按序 ----------
	var order_before: Array = cp.hand.duplicate()
	scene.call("_update_hand_buttons")
	await process_frame
	_check(cp.hand == order_before, "手动模式下重建手牌不再自动排序")
	_check(not _is_sorted(cp.hand) or _is_sorted(order_before), "手动顺序未被自动排序覆盖")

	# ---------- F. 手动模式下抽到的新牌追加到末尾 ----------
	var new_card = scene.game_manager.get_database().draw_card()
	if new_card != null:
		cp.add_card(new_card)
		cp.sort_hand_by_atomic_number()
		var expected: Array = order_before.duplicate()
		expected.append(new_card)
		_check(cp.hand == expected, "手动模式下抽牌：已有顺序不变，新牌追加到末尾")
	else:
		print("SKIP: 牌库已空，跳过抽牌追加用例")
	_check(cp.hand_manual_order, "抽牌后仍处于手动排列模式")

	# ---------- G. 索引 → 卡片对象 映射 ----------
	scene.selected_indices = [0, 2]
	await process_frame
	scene.call("_update_hand_buttons")
	await process_frame
	var keep0 = cp.hand[0]
	var keep2 = cp.hand[2]
	cp.move_card(5, 0)
	scene.call("_update_hand_buttons")
	await process_frame
	_check(scene.selected_indices.has(cp.hand.find(keep0)), "重排后选中仍跟随原第 0 张")
	_check(scene.selected_indices.has(cp.hand.find(keep2)), "重排后选中仍跟随原第 2 张")
	_check(scene.selected_indices.size() == 2, "重排后选中数量不变")

	# ---------- H. 拖出容器 → 取消 ----------
	scene.selected_indices = []
	await process_frame
	scene.call("_update_hand_buttons")
	await process_frame
	scene.call("_begin_drag", 1)
	var before_out: Array = cp.hand.duplicate()
	scene._drag_slot = 6
	scene.call("_finish_drag", Vector2(-500, -500))
	await process_frame
	_check(cp.hand == before_out, "拖到手牌区外松手 → 顺序不变")
	_check(scene._drag_from == -1 and not scene._drag_active, "取消后拖拽状态已复位")

	# ---------- I. 插入槽位判定 ----------
	var hb: Array = scene.hand_buttons
	var b0 = hb[0]
	var last = hb[hb.size() - 1]
	var x_left: float = b0.get_meta("base_pos", b0.position).x + 2.0
	var x_right: float = last.get_meta("base_pos", last.position).x + 95.0
	_check(int(scene.call("_insert_slot_at", x_left)) == 0, "指针在首张左半区 → 插入槽 0")
	_check(int(scene.call("_insert_slot_at", x_right)) == hb.size(), "指针在最右牌右侧 → 插入槽 = 末尾")

	# ---------- J. 顺序签名随顺序变化 ----------
	var sig_before: String = scene.call("_hand_order_sig", cp)
	cp.move_card(0, 1)
	var sig_after: String = scene.call("_hand_order_sig", cp)
	_check(sig_before != sig_after, "手牌顺序变化 → 顺序签名变化（提示会随之作废）")

	# ---------- K. 「按序」恢复 ----------
	scene.call("_on_hand_reorder")
	await process_frame
	_check(_is_sorted(cp.hand), "点「按序」后手牌恢复升序")
	_check(not cp.hand_manual_order, "点「按序」后退回自动排列模式")
	_check(not scene._reorder_btn.visible, "退回自动模式后「按序」按钮隐藏")
	_check(cp.hand.size() == n0 + (1 if new_card != null else 0), "全程未丢失手牌")

	# ---------- L. 拖拽后的补发 pressed 被吞 ----------
	scene.selected_indices = []
	scene._drag_suppress_click = true
	scene.call("_on_card_clicked", 0)
	await process_frame
	_check(scene.selected_indices.is_empty(), "拖拽结束后的补发 pressed 不会误选中")
	_check(not scene._drag_suppress_click, "抑制标志只生效一次")

	# ---------- M. 满手牌（18 张上限）重排后布局仍合法 ----------
	var guard := 0
	while cp.hand.size() < 18 and guard < 40:
		cp.hand.append(cp.hand[0])
		guard += 1
	cp.move_card(17, 0)
	scene.call("_update_hand_buttons")
	await process_frame
	await process_frame
	hb = scene.hand_buttons
	_check(hb.size() == 18, "补满后手牌 18 张 (%d)" % hb.size())
	var ok_bounds := true
	var ok_size := true
	for b in hb:
		if not is_instance_valid(b):
			continue
		if b.position.x < -0.01 or b.position.x + 95.0 > hc.size.x + 0.01:
			ok_bounds = false
		if abs(b.size.x - 95.0) > 0.01 or abs(b.size.y - 118.0) > 0.01:
			ok_size = false
	_check(ok_size, "18 张时每张牌尺寸仍为 95x118")
	_check(ok_bounds, "18 张重排后全部在容器水平范围内")

	# ---------- N. 教程关重排门控（第零关引导/流程阶段禁用，练习阶段与第一/二关放行） ----------
	# 只改 GM 上的教程字段，避开「AI 回合只读（_hand_read_only）」这个与门控无关的变量
	scene._hand_read_only = false
	scene.step_mode = 0
	var gm_n = scene.game_manager
	gm_n.tutorial_level = 0
	gm_n.tutorial_level0_phase = 1
	_check(not scene.call("_can_reorder_hand"), "第零关 UI 标注阶段(phase 1)：禁用重排（引导框按固定坐标绘制）")
	gm_n.tutorial_level0_phase = 2
	_check(not scene.call("_can_reorder_hand"), "第零关流程介绍阶段(phase 2)：禁用重排")
	gm_n.tutorial_level0_phase = 3
	_check(scene.call("_can_reorder_hand"), "第零关牌局练习阶段(phase 3)：允许重排（实机反馈的手牌不可拖）")
	gm_n.tutorial_level = 1
	gm_n.tutorial_level0_phase = 0
	_check(scene.call("_can_reorder_hand"), "第一关：允许重排")
	gm_n.tutorial_level = 2
	_check(scene.call("_can_reorder_hand"), "第二关：允许重排")
	gm_n.tutorial_level = 0
	gm_n.tutorial_level0_phase = 0
	_check(scene.call("_can_reorder_hand"), "自由模式（tutorial_level=0 且 phase=0）：允许重排")

	print("")
	if fails == 0:
		print("ALL HAND REORDER TESTS PASSED")
		quit(0)
	else:
		print("%d TEST(S) FAILED" % fails)
		quit(1)
