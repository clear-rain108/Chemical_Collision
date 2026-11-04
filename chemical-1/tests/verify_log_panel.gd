# 验证右栏「日志 / 规则提醒」的可折叠标题栏：
#   · 标题条常驻（26px），点一下折叠成一条、再点展开；
#   · 展开高度跟着内容走（6 行日志不再固定 300px 空一大片）；
#   · 底板左边缘不再压到「退出」按钮上；
#   · 折叠只收自己的高度，不改变「规则提醒占位时日志让位」的互斥关系。
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

func _run():
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	# 开局拿 6 条真实日志（默认最多 6 行）
	scene.call("_on_start_game")
	for _i in range(6):
		await process_frame

	_test_title_bar(scene)
	var panel = _nodes(scene)["panel"]
	if panel == null:
		print("ABORT: 缺 LogPanel / LogTitleBar，跳过后续几何断言")
		quit(1)
		return
	_test_expanded(scene)
	_test_collapse(scene)
	_test_log_visibility(scene)
	await _test_rule_tips(scene)
	_test_idempotent(scene)

	if fails == 0:
		print("ALL LOG PANEL TESTS PASSED")
	else:
		print("%d LOG PANEL TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


func _nodes(scene) -> Dictionary:
	var page = scene.game_page
	return {
		"panel": page.get_node_or_null("LogPanel") if page else null,
		"title": page.get_node_or_null("LogTitleBar") if page else null,
		"label": scene.log_label,
	}


# ---------------- 一、标题条存在且可点 ----------------
func _test_title_bar(scene) -> void:
	var n := _nodes(scene)
	var panel = n["panel"]
	var title: Button = n["title"]
	_check(panel is Panel, "日志底板存在（LogPanel）")
	_check(title is Button, "日志标题条存在且是 Button（LogTitleBar）")
	if panel == null or title == null:
		return
	_check(title.get_index() == panel.get_index() + 1,
		"标题条紧跟在底板之后（画在底板之上）")
	_check(title.mouse_filter == Control.MOUSE_FILTER_STOP, "标题条可点（mouse_filter=STOP）")
	_check(title.text.contains("游戏日志"), "标题文字含「游戏日志」：%s" % title.text)
	_check(title.text.contains("▾"), "默认展开，标题带展开箭头 ▾：%s" % title.text)
	_check(title.size.y >= 24.0 and title.size.y <= 32.0,
		"标题条高度在 24~32（实际 %.1f）" % title.size.y)
	# 底板左边缘不能再压到「退出」按钮


# ---------------- 二、展开：高度跟着内容走 ----------------
func _test_expanded(scene) -> void:
	var n := _nodes(scene)
	var panel: Panel = n["panel"]
	var title: Button = n["title"]
	var label: Label = n["label"]
	_check(scene.log_lines.size() > 0, "已有真实日志（%d 行）" % scene.log_lines.size())
	var r_panel := Rect2(panel.position, panel.size)
	var r_label := Rect2(label.position, label.size)
	_check(r_panel.encloses(r_label), "底板完整包住日志文字（%s ⊇ %s）" % [str(r_panel), str(r_label)])
	_check(label.visible, "展开态日志文字可见")
	# 标题条在底板坐标系内、日志文字在 GamePage 坐标系内 —— 统一用全局矩形比纵向顺序
	var r_title_abs: Rect2 = title.get_global_rect()
	var r_label_abs: Rect2 = label.get_global_rect()
	_check(r_label_abs.position.y >= r_title_abs.end.y - 0.5,
		"日志文字在标题条下方（label.top=%.1f title.bottom=%.1f）"
			% [r_label_abs.position.y, r_title_abs.end.y])
	# 6 行日志不该留出 300px 的空板（旧实现固定 300）
	_check(panel.size.y < 260.0,
		"展开高度按内容收（%.1f < 260，旧实现固定 300）" % panel.size.y)
	_check(panel.size.y > 90.0, "展开高度够放 6 行（%.1f > 90）" % panel.size.y)
	_check(label.size.x > 240.0, "日志文字宽够读（%.1f）" % label.size.x)
	var title_box := Rect2(title.position, title.size)
	_check(title_box.position.x >= r_panel.position.x - 0.5
			and title_box.end.x <= r_panel.end.x + 0.5
			and title_box.position.y >= r_panel.position.y - 0.5
			and title_box.end.y <= r_panel.end.y + 0.5,
		"标题条在底板内水平铺满（%s vs %s）" % [str(title_box), str(r_panel)])
	_check(label.get_theme_font_size("font_size") >= 12,
		"日志字号保持 13（实际 %d）" % label.get_theme_font_size("font_size"))


# ---------------- 三、点标题折叠 / 再点展开 ----------------
func _test_collapse(scene) -> void:
	var n := _nodes(scene)
	var panel: Panel = n["panel"]
	var title: Button = n["title"]
	var label: Label = n["label"]
	var h_expanded: float = panel.size.y
	title.emit_signal("pressed")
	_check(scene._log_collapsed, "点击标题后进入折叠态")
	_check(not label.visible, "折叠后日志文字隐藏")
	_check(panel.visible, "折叠后底板仍在（只剩标题条，不是整个消失）")
	_check(title.visible, "折叠后标题条仍可见（可再点开）")
	_check(absf(panel.size.y - 46.0) < 0.5,
		"折叠高度 = 10+26+10 = 46（实际 %.1f）" % panel.size.y)
	_check(title.text.contains("▸"), "折叠态标题带 ▸：%s" % title.text)
	_check(panel.size.y < h_expanded, "折叠比展开矮（%.1f < %.1f）" % [panel.size.y, h_expanded])

	title.emit_signal("pressed")
	_check(not scene._log_collapsed, "再点一次恢复展开态")
	_check(label.visible, "展开后日志文字恢复")
	_check(absf(panel.size.y - h_expanded) < 0.5,
		"展开高度回到折叠前（%.1f vs %.1f）" % [panel.size.y, h_expanded])
	_check(title.text.contains("▾"), "展开态标题带 ▾：%s" % title.text)

	# 折叠状态跨回合保留：刷新 UI（会重写日志文本）不会把折叠撑回去
	title.emit_signal("pressed")
	scene.call("_update_log_label")
	scene.call("_refresh_ui")
	_check(scene._log_collapsed and absf(panel.size.y - 46.0) < 0.5,
		"刷新 / 新的日志不会自动展开（%.1f）" % panel.size.y)
	title.emit_signal("pressed")

	var quit_btn = scene.quit_button
	if quit_btn != null:
		var quit_right: float = quit_btn.get_global_rect().end.x
		var panel_left: float = panel.get_global_rect().position.x
		_check(panel_left >= quit_right + 2.0,
			"底板左边缘（%.1f）离开退出按钮右边缘（%.1f）" % [panel_left, quit_right])



# ---------------- 四、与「规则提醒占位」的互斥关系保持不变 ----------------
func _test_log_visibility(scene) -> void:
	var n := _nodes(scene)
	var panel: Panel = n["panel"]
	var title: Button = n["title"]
	scene.call("_set_log_visible", false)
	_check(not panel.visible and not title.visible and not n["label"].visible,
		"整体隐藏时底板 / 标题 / 文字一起让位")
	scene.call("_set_log_visible", true)
	_check(panel.visible and title.visible and n["label"].visible,
		"恢复显示时三者一起回来")


# ---------------- 五、规则提醒同样可折叠 ----------------
func _test_rule_tips(scene) -> void:
	scene.call("_level0_create_rule_tips")
	await process_frame
	var bg: Panel = scene.level0_rule_tip_bg
	var label: Label = scene.level0_rule_tip_label
	var title: Button = bg.get_node_or_null("Level0RuleTipsTitle") if bg else null
	_check(bg != null and label != null, "规则提醒底板 / 文字已创建")
	_check(title is Button, "规则提醒标题条存在（Level0RuleTipsTitle）")
	if bg == null or label == null or title == null:
		return

	# 造出完整文案（真实对局里由 _level0_update_rule_tips 写入）
	label.text = scene.call("_level0_rule_tips_text")
	scene.call("_layout_rule_tips")
	await process_frame
	scene.call("_level0_set_rule_tips_visible", true)
	var r_bg := Rect2(bg.position, bg.size)
	var r_lbl := Rect2(label.position, label.size)
	_check(r_bg.encloses(r_lbl), "规则底板包住文字（%s ⊇ %s）" % [str(r_bg), str(r_lbl)])
	_check(not scene.log_label.visible, "规则提醒占位时日志让位（互斥不变）")
	_check(r_bg.end.x <= 1152.5 and r_bg.end.y <= 648.5,
		"规则提醒不出画布（%s）" % str(r_bg))
	_check(bg.size.y < 260.0, "规则提醒高度按内容收（%.1f < 260，旧实现固定 300）" % bg.size.y)
	_check(title.text.contains("规则提醒") and title.text.contains("▾"),
		"规则提醒标题文字：%s" % title.text)

	title.emit_signal("pressed")
	_check(scene._rule_tip_collapsed, "点击规则提醒标题进入折叠态")
	_check(not label.visible, "折叠后规则文字隐藏")
	_check(absf(bg.size.y - 46.0) < 0.5, "规则提醒折叠高度 46（实际 %.1f）" % bg.size.y)
	_check(title.text.contains("▸"), "规则提醒折叠态带 ▸：%s" % title.text)
	title.emit_signal("pressed")
	_check(not scene._rule_tip_collapsed and label.visible, "再点恢复展开")


# ---------------- 六、重复调用不叠层 ----------------
func _test_idempotent(scene) -> void:
	var page = scene.game_page
	scene.call("_ensure_log_panel")
	scene.call("_ensure_log_panel")
	scene.call("_layout_log_panel")
	var count: int = 0
	for c in page.get_children():
		if c.name == "LogPanel":
			count += 1
	_check(count == 1, "重复 _ensure_log_panel 不叠第二块底板（%d）" % count)
	var tcount: int = 0
	for c in page.get_children():
		if c.name == "LogTitleBar":
			tcount += 1
	_check(tcount == 1, "重复 _ensure_log_panel 不叠第二个标题条（%d）" % tcount)
	if scene.level0_rule_tip_bg != null:
		var rcount: int = 0
		for c in scene.level0_rule_tip_bg.get_children():
			if c.name == "Level0RuleTipsTitle":
				rcount += 1
		_check(rcount == 1, "重复 _level0_create_rule_tips 不叠第二个标题条（%d）" % rcount)
