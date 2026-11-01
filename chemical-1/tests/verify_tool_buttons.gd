# 验证游戏页工具按钮（显示提示 / 帮助 / 退出游戏）的美术统一 —— 方案 A + B1：
#   1) 样式接管：不再画引擎默认主题（normal / hover / pressed / disabled / focus 全自定义）
#   2) 语义态：提示 toggle 的「开」= 主题蓝实底（原来开/关长得一模一样）；
#      退出按钮只把 hover / pressed 转暖红，静止态仍与其它按钮同色
#   3) 几何归一：等高 32、同基线 y=558、间距 10、右边界对齐 x=820；「按序 ⇅」并进同一行
#   4) 教程第零关「按钮区」高亮框完整包住三颗按钮，且与常量同源
#   5) 悬停缩放：pivot 居中 + 1.05（与 _mkb 共用 _attach_btn_motion）
extends SceneTree

const STATES := ["normal", "hover", "pressed", "disabled"]
const NORMAL_BG := Color(0.173, 0.243, 0.314, 1.0)   # #2C3E50，与出牌按钮同源

var fails: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


# headless 下不能用 create_timer（无帧推进），统一轮询 is_running()
func _wait_meta_tween(node: Node, key: String) -> void:
	var tw = node.get_meta(key, false)
	var guard: int = 0
	while tw is Tween and tw.is_valid() and tw.is_running() and guard < 600:
		await process_frame
		guard += 1


func _buttons(scene) -> Array:
	return [
		["显示提示", scene.hint_button],
		["帮助", scene.help_btn],
		["退出游戏", scene.quit_button],
	]


func _run():
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_test_bind(scene)
	_test_style_override(scene)
	_test_hover_glow(scene)
	_test_semantic_states(scene)
	_test_geometry(scene)
	_test_row_clearance(scene)
	_test_reorder_row(scene)
	_test_tutorial_rect(scene)
	await _test_motion(scene)

	if fails == 0:
		print("ALL TOOL BUTTON TESTS PASSED")
	else:
		print("%d TOOL BUTTON TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---------------- 1. 绑定 ----------------
func _test_bind(scene) -> void:
	_check(scene.hint_button is Button, "显示提示按钮已绑定")
	_check(scene.help_btn is Button, "帮助按钮已绑定")
	_check(scene.quit_button is Button, "退出游戏按钮已绑定")
	_check(scene.hint_button.name == "HintButton" and scene.help_btn.name == "HelpBtn"
			and scene.quit_button.name == "QuitButton",
		"仍是 Main.tscn 的原节点（样式接管没有重建控件，信号不受影响）")


# ---------------- 2. 样式接管 ----------------
func _test_style_override(scene) -> void:
	var base_bg: Color = scene._make_panel_style("button").bg_color
	_check(base_bg.is_equal_approx(NORMAL_BG), "基准底色 = 出牌按钮的深蓝灰 #2C3E50")
	for pair in _buttons(scene):
		var nm: String = pair[0]
		var b: Button = pair[1]
		var n = b.get_theme_stylebox("normal")
		_check(n is StyleBoxFlat, "%s：normal 是自定义 StyleBoxFlat（不再是引擎默认主题）" % nm)
		if n is StyleBoxFlat:
			_check(n.bg_color.is_equal_approx(base_bg), "%s：底色与出牌按钮同源 %s" % [nm, str(n.bg_color)])
			_check(n.corner_radius_top_left == scene.CARD_RADIUS,
				"%s：圆角 = CARD_RADIUS(%d)（默认主题是 4）" % [nm, scene.CARD_RADIUS])
			_check(n.border_width_left == scene.BORDER_W, "%s：1px 描边（默认主题没有）" % nm)
			_check(n.shadow_size == scene.SHADOW_SIZE,
				"%s：软投影与卡片同参(%d)" % [nm, scene.SHADOW_SIZE])
		# 只改 normal 会让 hover / pressed 落回引擎默认主题 → 逐态检查
		for st in STATES:
			var sb = b.get_theme_stylebox(st)
			_check(sb is StyleBoxFlat, "%s：%s 已接管" % [nm, st])
			if sb is StyleBoxFlat:
				_check(sb.corner_radius_top_left == scene.CARD_RADIUS,
					"%s：%s 圆角与 normal 一致" % [nm, st])
		_check(b.get_theme_stylebox("focus") is StyleBoxEmpty, "%s：focus 置空（无默认焦点环）" % nm)
		_check(b.get_theme_font_size("font_size") == 14,
			"%s：字号 14（实际 %d）" % [nm, b.get_theme_font_size("font_size")])
		_check(b.get_theme_color("font_color").is_equal_approx(Color(1, 1, 1, 1)), "%s：字色白" % nm)
		var d = b.get_theme_stylebox("disabled")
		_check(d is StyleBoxFlat and d.bg_color.a < 0.5, "%s：禁用态半透明" % nm)


# ---------------- 3. 悬停光晕（提亮 + 蓝光） ----------------
func _test_hover_glow(scene) -> void:
	for pair in [["显示提示", scene.hint_button], ["帮助", scene.help_btn]]:
		var nm: String = pair[0]
		var b: Button = pair[1]
		var h = b.get_theme_stylebox("hover")
		_check(h is StyleBoxFlat, "%s：hover 是 StyleBoxFlat" % nm)
		if not (h is StyleBoxFlat):
			continue
		_check(h.bg_color.is_equal_approx(Color(0.27, 0.38, 0.5, 1.0)),
			"%s：hover 底色与出牌按钮完全一致" % nm)
		_check(h.border_color.is_equal_approx(Color(0.55, 0.75, 0.95, 1.0)), "%s：hover 边框提亮" % nm)
		_check(h.shadow_color.a >= 0.5 and h.shadow_size == 6, "%s：hover 有蓝色光晕（尺寸 6）" % nm)
		_check(not h.bg_color.is_equal_approx(b.get_theme_stylebox("normal").bg_color),
			"%s：hover 与 normal 有区分" % nm)


# ---------------- 4. 语义态（toggle 开 / 破坏性悬停） ----------------
func _test_semantic_states(scene) -> void:
	# —— 显示提示：toggle，pressed 就是「开」态 ——
	var hb = scene.hint_button
	_check(hb.toggle_mode, "显示提示仍是 toggle 按钮")
	var on_sb = hb.get_theme_stylebox("pressed")
	_check(on_sb is StyleBoxFlat, "提示：pressed（开启态）是 StyleBoxFlat")
	if on_sb is StyleBoxFlat:
		_check(on_sb.bg_color.is_equal_approx(scene.START_C_ACCENT),
			"提示：开启态 = 主题蓝实底 %s（原来开/关不可辨）" % str(on_sb.bg_color))
		_check(not on_sb.bg_color.is_equal_approx(hb.get_theme_stylebox("normal").bg_color),
			"提示：开 / 关两态可辨")
	var on_hover = hb.get_theme_stylebox("hover_pressed")
	_check(on_hover is StyleBoxFlat, "提示：hover_pressed（开着再悬停）已接管")
	if on_hover is StyleBoxFlat and on_sb is StyleBoxFlat:
		_check(on_hover.bg_color.v > on_sb.bg_color.v,
			"提示：开着再悬停只把蓝色提亮一档（不会闪回深蓝灰）")
	# 引擎默认主题的 Button 只列了 5 档，但「toggle 开着 + 悬停」确实走 DRAW_HOVER_PRESSED，
	# 用一颗探针按钮把这件事钉住 —— 否则上面那条 override 可能是永远不会被用到的死代码
	var probe := Button.new()
	probe.toggle_mode = true
	root.add_child(probe)
	probe.notification(Control.NOTIFICATION_MOUSE_ENTER)
	probe.set_pressed_no_signal(true)
	_check(probe.get_draw_mode() == 4,
		"引擎在「开着 + 悬停」时走 DRAW_HOVER_PRESSED(4)（实际 %d）" % probe.get_draw_mode())
	probe.queue_free()

	# —— 退出游戏：只有 hover / pressed 转暖红 ——
	var qb = scene.quit_button
	var qh = qb.get_theme_stylebox("hover")
	_check(qh is StyleBoxFlat and qh.border_color.is_equal_approx(scene.BORDER_WARN),
		"退出按钮：hover 边框 = 警告红")
	_check(qb.get_theme_color("font_hover_color").is_equal_approx(scene.BORDER_WARN),
		"退出按钮：hover 字色 = 警告红")
	var qp = qb.get_theme_stylebox("pressed")
	_check(qp is StyleBoxFlat and qp.border_color.is_equal_approx(scene.BORDER_WARN),
		"退出按钮：pressed 也是暖色（不会悬停红 → 按下又变蓝灰）")
	var qn = qb.get_theme_stylebox("normal")
	_check(qn is StyleBoxFlat and qn.bg_color.is_equal_approx(NORMAL_BG),
		"退出按钮：静止态仍与其它按钮同色（只有悬停才警示）")

	# —— 帮助按钮不误伤 ——
	_check(scene.help_btn.get_theme_color("font_hover_color").is_equal_approx(Color(1, 1, 1, 1)),
		"帮助按钮：hover 仍是白字（暖红只给退出）")


# ---------------- 5. 几何归一 ----------------
func _test_geometry(scene) -> void:
	var hb = scene.hint_button
	var hh = scene.help_btn
	var qb = scene.quit_button
	var h: int = scene.TOOL_BTN_H
	_check(hb.size.is_equal_approx(Vector2(scene.TOOL_BTN_W_HINT, h)),
		"提示 132×32（实际 %s）" % str(hb.size))
	_check(hh.size.is_equal_approx(Vector2(scene.TOOL_BTN_W_HELP, h)),
		"帮助 96×32（实际 %s）" % str(hh.size))
	_check(qb.size.is_equal_approx(Vector2(scene.TOOL_BTN_W_QUIT, h)),
		"退出 112×32（实际 %s）" % str(qb.size))
	_check(hb.position.y == scene.TOOL_BTN_TOP and hh.position.y == scene.TOOL_BTN_TOP
			and qb.position.y == scene.TOOL_BTN_TOP,
		"三颗按钮同一基线 y=%d（原来 567 / 568 / 569）" % scene.TOOL_BTN_TOP)
	_check(is_equal_approx(hh.position.x, hb.position.x + hb.size.x + scene.TOOL_BTN_GAP),
		"提示→帮助 间距 %d（实际 %.0f）"
			% [scene.TOOL_BTN_GAP, hh.position.x - hb.position.x - hb.size.x])
	_check(is_equal_approx(qb.position.x, hh.position.x + hh.size.x + scene.TOOL_BTN_GAP),
		"帮助→退出 间距 %d（实际 %.0f）"
			% [scene.TOOL_BTN_GAP, qb.position.x - hh.position.x - hh.size.x])
	_check(is_equal_approx(qb.position.x + qb.size.x, scene.TOOL_BTN_RIGHT),
		"右边界对齐 x=%d（与手牌列 / 信息栏同一条竖线）" % scene.TOOL_BTN_RIGHT)
	_check(hb.text == "显示提示" and hh.text == "帮助" and qb.text == "退出游戏",
		"文本未被改写（只动样式和几何）")


# ---------------- 6. 与相邻区块不重叠 ----------------
func _test_row_clearance(scene) -> void:
	var hb = scene.hint_button
	var qb = scene.quit_button
	var row := Rect2(hb.position,
			Vector2(qb.position.x + qb.size.x - hb.position.x, hb.size.y))
	print("  工具行 bbox = %s" % str(row))
	var info := Rect2(scene.card_info_label.position, scene.card_info_label.size)
	var actions := Rect2(scene.action_panel.position, scene.action_panel.size)
	_check(not row.intersects(info), "工具行不压 CardInfoLabel")
	_check(not row.intersects(actions), "工具行不压 ActionPanel（出牌区）")
	_check(row.position.y >= info.position.y + info.size.y,
		"工具行在信息栏下方（gap %.0f）" % (row.position.y - info.position.y - info.size.y))
	_check(row.position.y + row.size.y <= actions.position.y,
		"工具行在出牌区上方（gap %.0f）" % (actions.position.y - row.position.y - row.size.y))
	_check(Rect2(Vector2.ZERO, scene.game_page.size).encloses(row), "工具行完全在 GamePage 内")


# ---------------- 7. 「按序 ⇅」并进同一行 ----------------
func _test_reorder_row(scene) -> void:
	var rb = scene._reorder_btn
	_check(rb is Button, "「按序 ⇅」按钮已创建")
	if not (rb is Button):
		return
	_check(rb.size.is_equal_approx(Vector2(scene.REORDER_BTN_W, scene.TOOL_BTN_H)),
		"按序按钮与工具行等高 112×32（实际 %s）" % str(rb.size))
	_check(rb.position.y == scene.TOOL_BTN_TOP,
		"按序按钮与工具行同一基线 y=%d（原来 528，和工具行两行错位）" % scene.TOOL_BTN_TOP)
	_check(is_equal_approx(scene.hint_button.position.x,
			rb.position.x + rb.size.x + scene.TOOL_BTN_GAP),
		"按序→提示 间距 %d" % scene.TOOL_BTN_GAP)
	_check(not rb.visible, "按序按钮默认隐藏（仍只在手动排列模式出现）")


# ---------------- 8. 教程高亮框跟着走 ----------------
func _test_tutorial_rect(scene) -> void:
	var steps: Array = scene._level0_ui_steps()
	_check(steps.size() == 6, "教程第零关仍是 6 步（实际 %d）" % steps.size())
	var box := Rect2()
	var found := false
	for s in steps:
		if s.get("target", "") == "quit_button":
			box = Rect2(s["pos"], s["size"])
			found = true
			break
	_check(found, "教程第零关有「按钮区」步骤")
	if not found:
		return
	print("  教程高亮框 = %s" % str(box))
	for pair in _buttons(scene):
		var nm: String = pair[0]
		var b: Button = pair[1]
		var r := Rect2(b.position, b.size)
		_check(box.encloses(r), "高亮框完整包住 %s %s" % [nm, str(r)])
	var row := Rect2(Vector2(scene.TOOL_ROW_LEFT, scene.TOOL_BTN_TOP),
			Vector2(scene.TOOL_BTN_RIGHT - scene.TOOL_ROW_LEFT, scene.TOOL_BTN_H))
	_check(box.encloses(row), "高亮框包住整条工具行（左右各留 6px 余量）")
	_check(is_equal_approx(box.position.x, scene.TOOL_ROW_LEFT - scene.TOOL_ROW_HL_PAD)
			and is_equal_approx(box.position.y, scene.TOOL_BTN_TOP - scene.TOOL_ROW_HL_PAD)
			and is_equal_approx(box.size.x, scene.TOOL_ROW_HL_SIZE.x)
			and is_equal_approx(box.size.y, scene.TOOL_ROW_HL_SIZE.y),
		"高亮框与 TOOL_ROW_HL_* 常量同源（改几何不会漏改教程）")


# ---------------- 9. 悬停缩放 ----------------
func _test_motion(scene) -> void:
	var b = scene.help_btn
	_check(b.pivot_offset.is_equal_approx(b.size * 0.5),
		"工具按钮 pivot 居中（pivot=%s size=%s）" % [str(b.pivot_offset), str(b.size)])
	_check(b.mouse_entered.get_connections().size() > 0, "工具按钮已接入悬停缩放")
	_check(b.button_down.get_connections().size() > 0, "工具按钮已接入按下缩放")

	scene._on_button_hover_scale(b, true)
	await _wait_meta_tween(b, "btn_scale_tween")
	_check(abs(b.scale.x - scene.BUTTON_HOVER_SCALE) < 0.01,
		"悬停放大到 %.2f（实际 %.2f）" % [scene.BUTTON_HOVER_SCALE, b.scale.x])
	_check(abs(b.scale.y - b.scale.x) < 0.001, "缩放等比（x = y）")

	scene._on_button_hover_scale(b, false)
	await _wait_meta_tween(b, "btn_scale_tween")
	_check(abs(b.scale.x - 1.0) < 0.01, "移出后回落到 1.0（实际 %.2f）" % b.scale.x)

