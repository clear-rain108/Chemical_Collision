# ============================================================
# tests/verify_ui_perf.gd - UI 增量刷新（Slice 2b）
#
# 这一片是本轮**唯一允许改行为**的：手牌区不再「一点就整排重建」。
# 断言不看耗时（机器相关、CI 不稳），只看「该不该重建」这个可判定的不变量：
#   1) 选中 / 取消选中：只改这一张牌的样式与层级，按钮对象一个都不许换
#   2) 牌没变（同对象 / 同顺序）时重复调用 _update_hand_buttons()：复用旧按钮，
#      不新建 / 不销毁节点，但状态（选中 / 只读）必须重刷到位
#   3) 样式工厂：高频重绘点用共享模板（同一实例），改属性的调用点拿独立实例
#
# 用法：godot --headless --path . --script tests/verify_ui_perf.gd
# ============================================================
extends SceneTree

var fails: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _ids(arr: Array) -> Array:
	var out: Array = []
	for o in arr:
		out.append(o.get_instance_id() if is_instance_valid(o) else -1)
	return out


func _run():
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	scene.call("_on_start_game")
	for _w in range(5):
		await process_frame

	_test_select_without_rebuild(scene)
	await _test_reuse_buttons(scene)
	await _test_style_template(scene)

	if fails == 0:
		print("ALL UI PERF TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


# ------------------------------------------------------------
# 1) 选中 / 取消选中：单张刷新，整排不重建
# ------------------------------------------------------------
func _test_select_without_rebuild(scene) -> void:
	var n: int = scene.hand_buttons.size()
	_check(n >= 2, "开局手牌 ≥2 张 (n=%d)" % n)
	if n < 2:
		return
	var before: Array = _ids(scene.hand_buttons)
	var btn0 = scene.hand_buttons[0]

	scene.call("_apply_card_selection", 0)
	_check(scene.selected_indices == [0],
		"点选后 selected_indices = [0]（实际 %s）" % str(scene.selected_indices))
	_check(_ids(scene.hand_buttons) == before,
		"点选不会重建整排（按钮对象 id 全同）")
	_check(is_instance_valid(btn0) and scene.hand_buttons[0] == btn0,
		"第 0 张仍是同一个 Button 实例（没有被 queue_free 重造）")

	var sb = btn0.get_theme_stylebox("normal")
	_check(sb is StyleBoxFlat and sb.bg_color.is_equal_approx(Color(1.0, 1.0, 0.82, 1.0)),
		"点选后底色变浅黄（%s）" % str(sb.bg_color))
	_check(sb != null and sb == btn0.get_theme_stylebox("hover")
		and sb == btn0.get_theme_stylebox("pressed"),
		"点选后 normal / hover / pressed 仍同源（不会回退默认深色主题）")
	_check(btn0.z_index == 10, "点选后 z_index=10（实际 %d）" % btn0.z_index)

	# 悬停档也要跟着换：否则选中牌一悬停就变回浅蓝，看不出选中
	var sbh = btn0.get_meta("sb_hover", null)
	_check(sbh is StyleBoxFlat and sbh.bg_color.r > 0.9 and sbh.bg_color.b < 0.9,
		"点选后悬停样式仍为黄色系（%s）" % (str(sbh.bg_color) if sbh is StyleBoxFlat else "null"))

	scene.call("_apply_card_selection", 0)
	_check(scene.selected_indices.is_empty(), "再点一次取消选中")
	_check(_ids(scene.hand_buttons) == before, "取消选中同样不重建整排")
	var sb2 = btn0.get_theme_stylebox("normal")
	_check(sb2 is StyleBoxFlat and sb2.bg_color.is_equal_approx(Color(0.973, 0.976, 0.988, 1.0)),
		"取消选中后恢复白底（%s）" % str(sb2.bg_color))
	_check(btn0.z_index == 0, "取消选中后 z_index=0（实际 %d）" % btn0.z_index)
	_check(btn0.get_meta("sb_hover", null) != null
		and (btn0.get_meta("sb_hover") as StyleBoxFlat).bg_color.b >= 0.9,
		"取消选中后悬停样式回到浅蓝系")


# ------------------------------------------------------------
# 2) 牌没变 → 复用旧按钮；只重刷状态，不新建节点
# ------------------------------------------------------------
func _test_reuse_buttons(scene) -> void:
	if scene.hand_buttons.is_empty():
		_check(false, "复用测试：手牌为空")
		return
	var n0: int = scene.hand_container.get_child_count()
	var before: Array = _ids(scene.hand_buttons)

	scene.call("_update_hand_buttons")
	_check(_ids(scene.hand_buttons) == before, "牌没变时重复调用不换手牌按钮（复用旧按钮）")
	_check(scene.hand_container.get_child_count() == n0,
		"牌没变时重复调用子节点数不变（%d → %d）" % [n0, scene.hand_container.get_child_count()])

	await process_frame
	scene.call("_update_hand_buttons")
	_check(_ids(scene.hand_buttons) == before, "隔帧再调一次仍复用（AI 计时器 / 状态刷新路径）")

	# 3) 复用路径也必须把「选中态」重刷到位（不能因为省事就把状态一起省了）
	if scene.hand_buttons.size() >= 2:
		scene.selected_indices = [1]
		scene.call("_update_hand_buttons")
		var b1 = scene.hand_buttons[1]
		var sb = b1.get_theme_stylebox("normal")
		_check(_ids(scene.hand_buttons) == before, "改选中后仍是同一批按钮（复用，不重建）")
		_check(sb is StyleBoxFlat and sb.bg_color.is_equal_approx(Color(1.0, 1.0, 0.82, 1.0)),
			"复用路径重刷选中样式（第 1 张浅黄，实际 %s）" % str(sb.bg_color))
		_check(b1.z_index == 10, "复用路径重刷选中层级 z_index=10（实际 %d）" % b1.z_index)
		_check(abs(b1.scale.x - scene.HAND_SELECT_SCALE) < 0.01,
			"复用路径重刷选中缩放 %.2f（实际 %.2f）" % [scene.HAND_SELECT_SCALE, b1.scale.x])
		scene.selected_indices = []
		scene.call("_update_hand_buttons")
		_check(abs(scene.hand_buttons[1].scale.x - 1.0) < 0.01,
			"取消选中且牌没变 → 缩放回 1.0（复用路径也走整排落位）")


# ------------------------------------------------------------
# 4) 样式工厂：模板共享 / 复制品互不影响
# ------------------------------------------------------------
func _test_style_template(scene) -> void:
	var tpl_a = scene.call("_panel_style_template", "card")
	var tpl_b = scene.call("_panel_style_template", "card")
	_check(tpl_a is StyleBoxFlat and tpl_a == tpl_b,
		"同一 kind 两次取模板返回同一实例（缓存生效，零分配）")

	var one = scene.call("_make_panel_style", "card")
	var two = scene.call("_make_panel_style", "card")
	_check(one is StyleBoxFlat and one != two,
		"_make_panel_style 仍返回全新实例（要改属性的调用点靠它隔离）")
	if one is StyleBoxFlat:
		one.bg_color = Color(1, 0, 0, 1)
	var tpl_c = scene.call("_panel_style_template", "card")
	_check(tpl_c is StyleBoxFlat
		and tpl_c.bg_color.is_equal_approx(Color(0.973, 0.976, 0.988, 1.0)),
		"改一次性实例不会污染共享模板（%s）" % str(tpl_c.bg_color))

	# 高频重绘点（手牌卡面 / 价态圆底）必须直接用模板，否则「零分配」没落地
	if not scene.hand_buttons.is_empty():
		var btn = scene.hand_buttons[0]
		var sb = btn.get_theme_stylebox("normal")
		var expect_sel: bool = 0 in scene.selected_indices
		var expect = scene.call("_panel_style_template", "card_selected" if expect_sel else "card")
		_check(sb == expect, "手牌卡面样式就是共享模板本身（同一实例）")
		_check(btn.get_theme_stylebox("hover") == btn.get_theme_stylebox("normal"),
			"手牌 hover 态与 normal 同源（引擎状态切换不可见）")
		_check(btn.get_meta("sb_hover", null)
			== scene.call("_panel_style_template", "card_hover_selected" if expect_sel else "card_hover"),
			"手牌悬停样式（meta sb_hover）走模板")
		var chip = btn.get_node_or_null("CardValenceChip")
		if chip != null:
			_check(chip.get_theme_stylebox("panel") == scene.call("_panel_style_template", "valence_chip"),
				"价态圆底样式走模板")
