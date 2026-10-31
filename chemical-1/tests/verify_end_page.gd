# 验证结束页 / 教学引导页（P8）的画风统一与交互接线
# 覆盖：
#   1) 两页子节点全部代码生成，并带回开始页同一套装饰（同色底 / 45° 渐变带 / 水印 / 装饰牌）
#   2) 不再是默认灰底按钮：EndButton / 关卡卡都是自绘 StyleBoxFlat + 已接缩放动效
#   3) 结束页四态（胜利 / AI 获胜 / 中途退出 / 初始化失败）的标题、状态条颜色、统计数字
#   4) 按钮去向：自由局回开始页、教程局回关卡列表；「再来一局」按模式重开
#   5) turn_count 归零 / 自增，入场动画不改写页面级 modulate
extends SceneTree

var fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels(c, out)


func _min_font_size(node: Node) -> int:
	var labels: Array = []
	_labels(node, labels)
	var min_fs := 999
	for lb in labels:
		var fs: int = lb.get_theme_font_size("font_size")
		if fs > 0 and fs < min_fs:
			min_fs = fs
	return min_fs


func _finish() -> void:
	if fails == 0:
		print("ALL END PAGE TESTS PASSED")
	else:
		print("%d END PAGE TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var end_page = scene.get_node_or_null("EndPage")
	var tut_page = scene.get_node_or_null("TutorialPage")
	_check(end_page != null, "EndPage 容器存在")
	_check(tut_page != null, "TutorialPage 容器存在")
	if end_page == null or tut_page == null:
		_finish()
		return

	var title = end_page.get_node_or_null("EndCard/EndTitle")
	var desc = end_page.get_node_or_null("EndCard/EndLabel")
	var status = end_page.get_node_or_null("EndCard/EndStatusBar")
	var card = end_page.get_node_or_null("EndCard")
	var end_btn = end_page.get_node_or_null("EndCard/EndButton")
	var restart = end_page.get_node_or_null("EndCard/EndRestartBtn")
	var tut_entry = end_page.get_node_or_null("EndCard/EndTutorialBtn")

	# ---------- A. 结构 & 画风（与开始页同一套）----------
	_check(end_page.get_node_or_null("EndBg") is ColorRect, "结束页有同色底色 EndBg")
	_check(end_page.get_node_or_null("GradientBand") is TextureRect, "结束页有 45° 渐变带")
	_check(end_page.get_node_or_null("Watermarks") != null, "结束页有元素水印")
	_check(end_page.get_node_or_null("DecorCards") != null, "结束页有倾斜装饰牌")
	_check(card is Panel, "结算卡 EndCard 是 Panel")
	if card is Panel:
		var cs = card.get_theme_stylebox("panel")
		_check(cs is StyleBoxFlat and cs.corner_radius_top_left == 8,
			"结算卡圆角 8（与开始页卡片一致）")
		_check(cs is StyleBoxFlat and cs.bg_color.get_luminance() > 0.9, "结算卡白底")
		_check(cs is StyleBoxFlat and cs.shadow_size >= 3, "结算卡带阴影（有卡片层次）")
	_check(status is Panel, "顶部状态条 EndStatusBar 存在")
	for n in ["EndTitle", "EndLabel", "EndRuleNote"]:
		_check(end_page.get_node_or_null("EndCard/" + n) is Label, "结束页节点 %s 保留" % n)
	for i in range(3):
		_check(end_page.get_node_or_null("EndCard/EndStat%d/EndStat%dValue" % [i, i]) is Label,
			"统计块 %d 数值节点存在" % i)
		_check(end_page.get_node_or_null("EndCard/EndStat%d/EndStat%dCaption" % [i, i]) is Label,
			"统计块 %d 标签节点存在" % i)

	_check(tut_page.get_node_or_null("GradientBand") is TextureRect, "教学页有 45° 渐变带")
	_check(tut_page.get_node_or_null("Watermarks") != null, "教学页有元素水印")
	_check(tut_page.get_node_or_null("DecorCards") != null, "教学页有倾斜装饰牌")
	_check(tut_page.get_node_or_null("TutorialTitle") is Label, "教学页标题节点保留")
	_check(tut_page.get_node_or_null("TutorialAccent") is ColorRect, "教学页强调条存在")
	for i in range(3):
		var lc = tut_page.get_node_or_null("Tutorial%dBtn" % i)
		_check(lc is Button, "关卡卡 %d 是按钮（整卡可点）" % i)
		if lc is Button:
			_check(lc.has_theme_stylebox_override("normal"), "关卡卡 %d 用自绘样式（非默认灰）" % i)
			var ls = lc.get_theme_stylebox("normal")
			_check(ls is StyleBoxFlat and ls.bg_color.get_luminance() > 0.9, "关卡卡 %d 白底" % i)
		_check(tut_page.get_node_or_null("Tutorial%dBtn/Tutorial%dDesc" % [i, i]) is Label,
			"关卡卡 %d 描述节点保留" % i)
	_check(tut_page.get_node_or_null("TutorialBackBtn") is Button, "返回按钮存在")

	# ---------- B. 按钮：自绘样式 + 缩放动效 + 已接线 ----------
	_check(end_btn != null, "主按钮 EndButton 存在")
	if end_btn:
		_check(end_btn.has_theme_stylebox_override("normal"), "主按钮用自绘样式（非默认灰）")
		var es = end_btn.get_theme_stylebox("normal")
		_check(es is StyleBoxFlat and es.bg_color.b > 0.5 and es.bg_color.r < 0.4,
			"主按钮是主题蓝底")
		_check(end_btn.mouse_entered.get_connections().size() > 0, "主按钮已接 hover 动效")
		_check(end_btn.pressed.get_connections().size() > 0, "主按钮已接 pressed")
		_check(is_equal_approx(end_btn.pivot_offset.x, end_btn.size.x * 0.5),
			"主按钮 pivot 居中（缩放不跑偏）")
	_check(restart != null, "「再来一局」次按钮存在")
	if restart:
		_check(restart.has_theme_stylebox_override("normal"), "次按钮用自绘样式（白底蓝边）")
		var rs = restart.get_theme_stylebox("normal")
		_check(rs is StyleBoxFlat and rs.bg_color.get_luminance() > 0.9, "次按钮白底")
		_check(restart.pressed.get_connections().size() > 0, "次按钮已接 pressed")
	_check(tut_entry != null, "「教学引导」幽灵按钮存在")
	if tut_entry:
		var gs = tut_entry.get_theme_stylebox("normal")
		_check(gs is StyleBoxFlat and gs.bg_color.a < 0.05, "幽灵按钮透明底")
	var back_btn = tut_page.get_node_or_null("TutorialBackBtn")
	if back_btn:
		_check(back_btn.pressed.get_connections().size() > 0, "返回按钮已接 pressed")
		_check(back_btn.has_theme_stylebox_override("normal"), "返回按钮用自绘样式")
	for i in range(3):
		var lc = tut_page.get_node_or_null("Tutorial%dBtn" % i)
		if lc:
			_check(lc.pressed.get_connections().size() > 0, "关卡卡 %d 已接 pressed" % i)
			_check(lc.mouse_entered.get_connections().size() > 0, "关卡卡 %d 已接 hover" % i)

	# ---------- C. 布局安全区 & 字号下限 ----------
	_check(card != null and card.position.x >= 0
		and card.position.x + card.size.x <= 1152, "结算卡横向不越界")
	_check(card != null and card.position.y >= 0
		and card.position.y + card.size.y <= 648, "结算卡纵向不越界")
	var prev_right := -999.0
	for i in range(3):
		var tile = card.get_node_or_null("EndStat%d" % i) if card else null
		if tile:
			_check(tile.position.x >= prev_right, "统计块 %d 不与前一块重叠" % i)
			prev_right = tile.position.x + tile.size.x
	_check(card != null and prev_right <= card.size.x, "统计块整体在卡片内")
	_check(_min_font_size(card) >= 13, "结算卡内最小字号 ≥ 13（实际 %d）" % _min_font_size(card))
	var lc0 = tut_page.get_node_or_null("Tutorial0Btn")
	if lc0:
		_check(_min_font_size(lc0) >= 14, "关卡卡内最小字号 ≥ 14（实际 %d）" % _min_font_size(lc0))

	# ---------- D. 中途退出态 ----------
	scene.call("_on_start_game")
	await process_frame
	await process_frame
	var gm = scene.game_manager
	_check(gm != null, "自由局开局成功")
	_check(gm != null and gm.turn_count == 0, "新开局 turn_count 归零")
	var db = gm.get_database() if gm else null
	scene.call("_on_quit_game")
	await process_frame
	_check(end_page.visible, "退出后结束页可见")
	_check(not scene.get_node("GamePage").visible, "退出后游戏页隐藏")
	_check(title != null and title.text == "游戏已退出",
		"退出态标题「游戏已退出」（实际 %s）" % (title.text if title else "null"))
	_check(desc != null and desc.text == "本局未分胜负，随时再来一局", "退出态描述给出下一步")
	if status:
		var sb = status.get_theme_stylebox("panel")
		_check(sb is StyleBoxFlat and sb.bg_color.is_equal_approx(Color(0.604, 0.647, 0.694, 1.0)),
			"退出态状态条为中性灰")
	var v0 = card.get_node_or_null("EndStat0/EndStat0Value") if card else null
	_check(v0 != null and gm != null and v0.text == str(gm.turn_count), "总回合取 turn_count")
	var v1 = card.get_node_or_null("EndStat1/EndStat1Value") if card else null
	_check(v1 != null and db != null and v1.text == str(db.get_remaining_count()),
		"剩余牌库与数据层一致")
	var v2 = card.get_node_or_null("EndStat2/EndStat2Value") if card else null
	_check(v2 != null and gm != null and v2.text == str(gm.get_players()[0].hand.size()),
		"无胜者时剩余手牌取人类玩家")
	_check(not tut_page.visible, "退出时教学关卡列表也收起（不压在结束页上）")
	_check(tut_entry != null and tut_entry.visible, "自由局「教学引导」入口可见")
	_check(end_btn != null and end_btn.text == "返回主页", "自由局主按钮文案「返回主页」")
	_check(end_btn != null and end_btn.pressed.is_connected(scene._show_start_page),
		"自由局主按钮连到开始页")

	# ---------- E. 胜利 / AI 获胜 / 初始化失败 ----------
	gm.phase = 2
	gm.winner_index = 0
	scene.call("_show_end_page", "")
	await process_frame
	_check(title != null and title.text == "胜利！", "人类获胜标题「胜利！」")
	_check(desc != null and desc.text.begins_with("获胜者："), "人类获胜显示获胜者")
	if status:
		_check(status.get_theme_stylebox("panel").bg_color.is_equal_approx(
			Color(0.176, 0.478, 0.702, 1.0)), "获胜状态条为主题蓝")
	gm.winner_index = 1
	scene.call("_show_end_page", "")
	await process_frame
	_check(title != null and title.text == "本局结束", "AI 获胜标题「本局结束」")
	gm.winner_index = -1
	gm.phase = 0
	scene.call("_show_end_page", "初始化失败")
	await process_frame
	_check(title != null and title.text == "初始化失败", "初始化失败标题透传")
	_check(desc != null and desc.text == "请返回主页重新开始", "失败态描述给出下一步")
	if status:
		_check(status.get_theme_stylebox("panel").bg_color.is_equal_approx(
			Color(0.906, 0.298, 0.235, 1.0)), "失败态状态条为警示红")

	# ---------- F. 教程局：回关卡列表 + 再试一次 ----------
	scene.call("_on_start_tutorial", 1)
	await process_frame
	await process_frame
	_check(scene.game_manager != null and scene.game_manager.tutorial_level == 1,
		"教程局 tutorial_level = 1")
	scene.call("_on_quit_game")
	await process_frame
	_check(not tut_page.visible, "教程局结束时教学页被收起")
	_check(end_btn != null and end_btn.text == "返回关卡", "教程局主按钮文案「返回关卡」")
	_check(restart != null and restart.text == "再试一次", "教程局次按钮文案「再试一次」")
	_check(tut_entry != null and not tut_entry.visible, "教程局隐藏「教学引导」入口")
	_check(end_btn != null and end_btn.pressed.is_connected(scene._on_show_tutorial_page),
		"教程局主按钮连到关卡列表")
	restart.emit_signal("pressed")
	await process_frame
	await process_frame
	_check(not end_page.visible and scene.get_node("GamePage").visible,
		"「再试一次」直接回到游戏页")
	_check(scene.game_manager != null and scene.game_manager.tutorial_level == 1,
		"「再试一次」重开的仍是同一关")

	# ---------- G. 自由局「再来一局」+ turn_count ----------
	scene.call("_on_start_game")
	await process_frame
	await process_frame
	var t0: int = scene.game_manager.turn_count
	scene.game_manager.next_turn()
	_check(scene.game_manager.turn_count == t0 + 1, "next_turn 推进一回合，总回合 +1")
	scene.call("_on_quit_game")
	await process_frame
	_check(restart != null and restart.text == "再来一局", "自由局次按钮文案「再来一局」")
	restart.emit_signal("pressed")
	await process_frame
	await process_frame
	_check(not end_page.visible and scene.get_node("GamePage").visible,
		"「再来一局」重开自由局")
	_check(scene.game_manager != null and scene.game_manager.turn_count == 0,
		"重开后 turn_count 归零")

	# ---------- H. 入场动效：页面 modulate 只由 _fade_in_page 负责 ----------
	scene.call("_on_quit_game")
	await process_frame
	_check(card != null and card.modulate.a < 1.0, "结算卡入场从透明开始")
	_check(end_page.modulate.a < 1.0, "页面淡入从透明开始")
	await create_timer(0.45).timeout
	_check(card != null and is_equal_approx(card.position.y, 114.0), "结算卡落位到 END_CARD_POS.y")
	_check(card != null and is_equal_approx(card.modulate.a, 1.0), "结算卡淡入完成")
	_check(is_equal_approx(end_page.modulate.a, 1.0), "页面淡入完成（a=1）")
	_check(end_page.get_node_or_null("DecorCards").has_meta("float_started"),
		"结束页装饰牌浮动只启动一次")

	# 已在结算页时重复展示（_refresh_ui 会反复进来）：只刷新数据，不重播动画
	scene._show_end_page("游戏已退出")
	_check(is_equal_approx(end_page.modulate.a, 1.0), "已在结算页时重复展示不重播淡入（防刷新闪烁）")
	_check(card != null and is_equal_approx(card.position.y, 114.0), "重复展示不重播入场动画")
	_check(title != null and title.text == "游戏已退出", "重复展示仍刷新文案")

	_finish()
