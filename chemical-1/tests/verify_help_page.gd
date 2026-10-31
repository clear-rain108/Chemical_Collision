# 验证帮助中心（P5）：单页 + 3 Tab + 滚动容器 + 卡片
#   1) 结构：HelpPage 代码生成 / 标题栏 / Tab 栏 / 3×ScrollContainer / 返回按钮
#   2) 懒加载：切到才构建 —— Tab0 9 卡 2 列 / Tab1 29 迷你卡 7 列 / Tab2 6 卡
#   3) 规范：无 11px 以下文字、无空格对齐、卡片标题 17 / 正文 14、选中 Tab 有下划线
#   4) 数据：29 种元素 / 182 张（不再出现 28 种 / 172 张）
#   5) 旧 3 页已从 Main.tscn 删除（P6 清理，不留备份节点）
extends SceneTree

const HelpContentScript = preload("res://scripts/HelpContent.gd")

var fails: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _collect(node: Node, cls: String, out: Array) -> void:
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		_collect(c, cls, out)


func _labels(node: Node) -> Array:
	var out: Array = []
	_collect(node, "Label", out)
	return out


func _finish() -> void:
	if fails == 0:
		print("ALL HELP TESTS PASSED")
	else:
		print("%d HELP TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var help = scene.get_node_or_null("HelpPage")
	_check(help != null, "HelpPage 由 _build_help_page() 代码生成（Main.tscn 未新增节点）")
	if help == null:
		_finish()
		return

	# ---------------- 1. 结构 ----------------
	_check(not help.visible, "帮助中心初始不可见")
	_check(help.get_node_or_null("HelpHeader") != null, "存在顶部标题栏 HelpHeader")
	_check(help.get_node_or_null("HelpTabBar") != null, "存在 Tab 栏 HelpTabBar")
	_check(scene.help_tab_btns.size() == 3, "Tab 按钮 3 个 (实际 %d)" % scene.help_tab_btns.size())
	_check(scene.help_scrolls.size() == 3, "ScrollContainer 3 个 (实际 %d)" % scene.help_scrolls.size())
	_check(scene.help_bodies.size() == 3, "内容根 VBox 3 个 (实际 %d)" % scene.help_bodies.size())

	var names: Array = []
	for b in scene.help_tab_btns:
		names.append(b.text)
	_check(names == ["游戏规则", "卡牌图鉴", "补充规则"], "Tab 文案与顺序正确 %s" % str(names))
	_check(scene.help_tab_btns[0].custom_minimum_size == Vector2(180, 40), "Tab 尺寸 180×40")
	_check(abs(scene.help_tab_btns[0].size.x - 180.0) < 1.0,
		"Tab 实际宽度等于 180（下划线铺满按钮）实际 %.1f" % scene.help_tab_btns[0].size.x)

	for i in range(scene.help_scrolls.size()):
		_check(scene.help_scrolls[i].get_child_count() == 1, "Scroll%d 只挂一个内容容器" % i)
		_check(scene.help_scrolls[i].horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"Scroll%d 关闭横向滚动（永不出现横向滚动条）" % i)

	var back = help.get_node_or_null("HelpHeader/HelpBackBtn")
	_check(back != null, "标题栏右侧有返回按钮")
	_check(back != null and back.pressed.get_connections().size() > 0, "返回按钮已连接")

	for n in ["HelpPage_Rules", "HelpPage_Cards", "HelpPage_Supp"]:
		_check(scene.get_node_or_null(n) == null, "旧页 %s 已从 Main.tscn 删除（P6 清理）" % n)

	# ---------------- 2. 懒加载 ----------------
	for i in range(3):
		_check(scene.help_bodies[i].get_child_count() == 0, "Tab%d 进入前不构建内容" % i)

	scene._on_show_help()
	await process_frame
	_check(help.visible, "点「帮助」后 HelpPage 可见")
	_check(scene.help_bodies[0].get_child_count() == 1, "Tab0 首次进入即构建内容")
	_check(scene.help_bodies[1].get_child_count() == 0, "Tab1 仍未构建（懒加载生效）")

	var g0: Array = []
	_collect(scene.help_bodies[0], "GridContainer", g0)
	_check(g0.size() == 1 and g0[0].columns == 2, "Tab0 用 2 列卡片网格")
	_check(g0.size() == 1 and g0[0].get_child_count() == 9,
		"Tab0 共 9 张卡 (实际 %d)" % (g0[0].get_child_count() if g0.size() == 1 else -1))

	# 切 Tab：只改可见性，不新建淡入补间
	var tw_before = scene._page_fade_tween
	scene._on_help_show_cards()
	await process_frame
	_check(scene.help_scrolls[1].visible and not scene.help_scrolls[0].visible, "切 Tab 只改 Scroll 可见性")
	_check(scene._page_fade_tween == tw_before, "切 Tab 不新建页面淡入补间")
	_check(scene.help_bodies[1].get_child_count() > 0, "Tab1 首次进入即构建内容")
	_check(scene.help_bodies[2].get_child_count() == 0, "Tab2 仍未构建（懒加载生效）")

	var pc1: Array = []
	_collect(scene.help_bodies[1], "PanelContainer", pc1)
	var minis: Array = []
	var big_cards: Array = []
	for p in pc1:
		if p.custom_minimum_size.x <= 120.0 and p.custom_minimum_size.y <= 140.0:
			minis.append(p)
		else:
			big_cards.append(p)
	_check(minis.size() == 32, "图鉴迷你卡 32 张 = 29 网格 + 3 示例 (实际 %d)" % minis.size())
	_check(big_cards.size() == 4, "图鉴 4 张说明/速查卡 (实际 %d)" % big_cards.size())

	var g1: Array = []
	_collect(scene.help_bodies[1], "GridContainer", g1)
	var grid7 = null
	for g in g1:
		if g.columns == 7:
			grid7 = g
	_check(grid7 != null, "图鉴元素网格为 7 列")
	_check(grid7 != null and grid7.get_child_count() == 29,
		"图鉴网格 29 项 (实际 %d)" % (grid7.get_child_count() if grid7 != null else -1))

	scene._on_help_show_supp()
	await process_frame
	_check(scene.help_scrolls[2].visible, "切到 Tab2 可见")
	var g2: Array = []
	_collect(scene.help_bodies[2], "GridContainer", g2)
	_check(g2.size() == 1 and g2[0].get_child_count() == 6,
		"Tab2 共 6 张卡 (实际 %d)" % (g2[0].get_child_count() if g2.size() == 1 else -1))

	# 补充规则文案必须指向开始页真实存在的开关名（曾写成不存在的「规则补充」复选框）
	var supp_text := ""
	for card in HelpContentScript.get_supp_cards():
		supp_text += str(card.get("title", "")) + "|"
		for line in card.get("lines", []):
			supp_text += str(line.get("t", "")) + "|"
	_check(supp_text.find("规则补充") == -1, "补充规则文案不再引用不存在的「规则补充」复选框")
	_check(supp_text.find("有机物胜利规则") >= 0 and supp_text.find("顺序牌型规则") >= 0,
		"补充规则文案指向开始页真实开关「有机物胜利规则」/「顺序牌型规则」")
	_check(supp_text.find("桌面清空") == -1, "顺序牌型不再写成「桌面清空」（实际是抢走牌权、不比大小）")
	# 第三条补充规则：允许卤族互化（开关名必须与开始页一致）
	_check(supp_text.find("允许卤族互化") >= 0, "补充规则含「允许卤族互化」开关说明")
	_check(supp_text.find("ClF") >= 0, "允许卤族互化给出 ClF 示例")

	# 第四条补充规则：元素限制（前 20 号 + 可选副族 / 卤族扩展）
	_check(supp_text.find("元素限制") >= 0, "补充规则含「元素限制」开关说明")
	_check(supp_text.find("前 20 号") >= 0, "元素限制写明前 20 号元素")
	_check(supp_text.find("Cr") >= 0 and supp_text.find("Zn") >= 0, "元素限制列出可选副族 Cr ~ Zn")
	_check(supp_text.find("Br") >= 0 or supp_text.find("碘") >= 0, "元素限制提到 Br / I 扩展")

	scene._on_help_show_rules()
	await process_frame
	_check(scene.help_scrolls[0].visible and not scene.help_scrolls[1].visible, "可切回 Tab0")

	# ---------------- 3. 视觉规范 ----------------
	var on_sb = scene.help_tab_btns[0].get_theme_stylebox("normal")
	var off_sb = scene.help_tab_btns[1].get_theme_stylebox("normal")
	_check(on_sb is StyleBoxFlat and on_sb.border_width_bottom == 3, "选中 Tab 有 3px 蓝色下划线")
	_check(off_sb is StyleBoxFlat and off_sb.border_width_bottom == 0, "未选中 Tab 无下划线")
	_check(scene.help_tab_btns[0].get_theme_color("font_color").is_equal_approx(scene.HELP_C_TAB_ON),
		"选中 Tab 用主题蓝字")
	_check(scene.help_tab_btns[1].get_theme_color("font_color").is_equal_approx(scene.HELP_C_TAB_OFF),
		"未选中 Tab 用灰字")

	var all_labels: Array = []
	for b in scene.help_bodies:
		all_labels.append_array(_labels(b))
	all_labels.append_array(_labels(scene.help_tab_btns[0].get_parent()))
	all_labels.append_array(_labels(help.get_node("HelpHeader")))
	_check(all_labels.size() > 60, "帮助页文字节点数量合理 (%d)" % all_labels.size())

	var too_small: Array = []
	for lb in all_labels:
		var fs = lb.get_theme_font_size("font_size")
		if fs < 11:
			too_small.append("%s=%d" % [str(lb.text).substr(0, 6), fs])
	_check(too_small.is_empty(), "帮助页无 11px 以下文字 %s" % str(too_small))

	var title_fs := -1
	var body_fs := -1
	for lb in all_labels:
		if lb.text == "怎么赢":
			title_fs = lb.get_theme_font_size("font_size")
		if str(lb.text).begins_with("先把自己手牌全部打完"):
			body_fs = lb.get_theme_font_size("font_size")
	_check(title_fs == scene.HELP_FS_TITLE, "卡片标题 17px (实际 %d)" % title_fs)
	_check(body_fs == scene.HELP_FS_BODY, "卡片正文 14px (实际 %d)" % body_fs)

	var no_wrap: Array = []
	for lb in all_labels:
		var txt := str(lb.text)
		if txt.length() >= 20 and lb.autowrap_mode == TextServer.AUTOWRAP_OFF:
			no_wrap.append(txt.substr(0, 10))
	_check(no_wrap.is_empty(), "20 字以上长文本都开启自动换行 %s" % str(no_wrap))

	# ---------------- 4. 文案数据 ----------------
	var spaced: Array = []
	var all_text := ""
	for tab in HelpContentScript.get_tabs():
		for card in tab.get("cards", []):
			all_text += str(card.get("title", "")) + "|"
			for line in card.get("lines", []):
				var t: String = str(line.get("t", ""))
				all_text += t + "|"
				if t.find("  ") >= 0:
					spaced.append(t.substr(0, 12))
	_check(spaced.is_empty(), "文案不用连续空格对齐 %s" % str(spaced))
	_check(HelpContentScript.get_element_cards().size() == 29,
		"牌库 29 种元素 (实际 %d)" % HelpContentScript.get_element_cards().size())
	_check(HelpContentScript.get_total_cards() == 182,
		"牌库共 182 张 (实际 %d)" % HelpContentScript.get_total_cards())
	_check(all_text.find("28 种") < 0, "文案不再出现「28 种」")
	_check(all_text.find("172") < 0, "文案不再出现「172 张」")
	_check(all_text.find("29 种") >= 0, "文案写的是「29 种」")
	_check(all_text.find("182") >= 0, "文案写的是「182 张」")

	# ---------------- 5. 返回后状态 ----------------
	scene._on_help_back()
	await process_frame
	_check(not help.visible, "返回后 HelpPage 隐藏")
	_check(scene.start_page.visible or scene.game_page.visible, "返回后回到某个主页面")

	_finish()
