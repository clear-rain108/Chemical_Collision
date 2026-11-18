# ============================================================
# pages/HelpPage.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4d，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 606-613 行 --------
func _on_show_help() -> void:
	if _ui.help_page:
		_ui.help_page.visible = true
		# 游戏内「帮助」按钮固定从「游戏规则」开始；补充规则有开始页专门入口
		_set_help_tab(0)
	if _ui.game_page: _ui.game_page.visible = false
	_ui._fade_in_page(_ui.help_page)



# -------- 搬运自 scripts/GameUI.gd 第 634-669 行 --------
func _on_help_back() -> void:
	if _ui.help_page: _ui.help_page.visible = false
	if _ui.start_page and _ui.start_page.visible:
		pass   # 从开始页打开帮助，返回开始页
	elif _ui.game_page and _ui.game_page.visible:
		_ui.game_page.visible = true  # 游戏中的帮助，返回游戏页
	else:
		if _ui.game_page: _ui.game_page.visible = true
	# 只有「游戏页从隐藏 → 可见」需要淡入；从开始页打开帮助时开始页一直在下层，无需动画
	if _ui.game_page and _ui.game_page.visible:
		_ui._fade_in_page(_ui.game_page)

# 3 个跳转入口只切换 Tab：不重建页面、不做页面淡入
# （verify_motion 断言切 Tab 不能产生淡入 tween）
func _on_help_show_cards() -> void:
	_open_help_at_tab(1)

func _on_help_show_supp() -> void:
	_open_help_at_tab(2)

func _on_help_show_rules() -> void:
	_open_help_at_tab(0)


# 从帮助中心外部（开始页「补充规则」按钮）进入时，help_page 可能仍是隐藏的
func _open_help_at_tab(idx: int) -> void:
	if _ui.help_page == null:
		return
	if not _ui.help_page.visible:
		_ui.help_page.visible = true
		if _ui.game_page: _ui.game_page.visible = false
		_set_help_tab(idx)
		_ui._fade_in_page(_ui.help_page)
		return
	_set_help_tab(idx)



# -------- 搬运自 scripts/GameUI.gd 第 905-1339 行 --------
func _build_help_page() -> Control:
	_ui.help_tab_btns.clear()
	_ui.help_scrolls.clear()
	_ui.help_bodies.clear()
	_ui._help_filled = [false, false, false]
	_ui._help_tab = 0

	var page := Control.new()
	page.name = "HelpPage"
	page.visible = false
	page.z_index = _ui.Z_CONTENT
	_ui.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.name = "HelpBg"
	bg.color = _ui.PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- 顶部标题栏：深蓝灰 + 白字标题 + 右侧返回按钮 ----
	var header := ColorRect.new()
	header.name = "HelpHeader"
	header.color = _ui.HELP_C_HEADER
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(header)
	_set_top_bar_rect(header, 0.0, _ui.HELP_HEADER_H)

	var title := Label.new()
	title.text = "帮助中心"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	title.anchor_left = 0.0
	title.anchor_right = 0.0
	title.anchor_top = 0.0
	title.anchor_bottom = 1.0
	title.offset_left = _ui.HELP_MARGIN
	title.offset_right = _ui.HELP_MARGIN + 240.0
	title.offset_top = 0.0
	title.offset_bottom = 0.0

	var back = _ui._mkb("← 返回游戏", _on_help_back, false)
	back.name = "HelpBackBtn"
	back.custom_minimum_size = Vector2(132, 36)
	header.add_child(back)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.anchor_top = 0.0
	back.anchor_bottom = 0.0
	back.offset_left = -(_ui.HELP_MARGIN + 132.0)
	back.offset_right = -_ui.HELP_MARGIN
	back.offset_top = (_ui.HELP_HEADER_H - 36.0) * 0.5
	back.offset_bottom = back.offset_top + 36.0

	# ---- Tab 栏：白底 + 底部 1px 分隔线 + 3 个等宽 Tab ----
	var tabbar := ColorRect.new()
	tabbar.name = "HelpTabBar"
	tabbar.color = _ui.HELP_C_TABBAR_BG
	tabbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(tabbar)
	_set_top_bar_rect(tabbar, _ui.HELP_HEADER_H, _ui.HELP_TABBAR_H)

	var divider := ColorRect.new()
	divider.color = _ui.HELP_C_DIVIDER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabbar.add_child(divider)
	divider.anchor_left = 0.0
	divider.anchor_right = 1.0
	divider.anchor_top = 1.0
	divider.anchor_bottom = 1.0
	divider.offset_left = 0.0
	divider.offset_right = 0.0
	divider.offset_top = -1.0
	divider.offset_bottom = 0.0

	var tab_row := HBoxContainer.new()
	tab_row.name = "HelpTabRow"
	tab_row.add_theme_constant_override("separation", 8)
	tabbar.add_child(tab_row)
	tab_row.anchor_left = 0.0
	tab_row.anchor_right = 1.0
	tab_row.anchor_top = 0.0
	tab_row.anchor_bottom = 1.0
	tab_row.offset_left = _ui.HELP_MARGIN
	tab_row.offset_right = -_ui.HELP_MARGIN
	tab_row.offset_top = 0.0
	tab_row.offset_bottom = 0.0

	var labels: Array = _ui.HelpContentScript.get_tab_labels()
	for i in range(labels.size()):
		var tb := Button.new()
		tb.name = "HelpTab%d" % i
		tb.text = labels[i]
		tb.custom_minimum_size = Vector2(180, 40)
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 16)
		tb.pressed.connect(_ui._set_help_tab.bind(i))
		tab_row.add_child(tb)
		_ui.help_tab_btns.append(tb)

	# ---- 内容区：每个 Tab 一个 ScrollContainer（各自保留滚动位置）----
	for i in range(labels.size()):
		var scroll := ScrollContainer.new()
		scroll.name = "HelpScroll%d" % i
		scroll.visible = (i == 0)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(scroll)
		scroll.anchor_left = 0.0
		scroll.anchor_right = 1.0
		scroll.anchor_top = 0.0
		scroll.anchor_bottom = 1.0
		scroll.offset_left = _ui.HELP_MARGIN
		scroll.offset_right = -_ui.HELP_MARGIN
		scroll.offset_top = _ui.HELP_BODY_TOP
		scroll.offset_bottom = -16.0

		var body := VBoxContainer.new()
		body.name = "HelpBody%d" % i
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", int(_ui.HELP_CARD_GAP))
		scroll.add_child(body)

		_ui.help_scrolls.append(scroll)
		_ui.help_bodies.append(body)

	for i in range(_ui.help_tab_btns.size()):
		_style_help_tab(_ui.help_tab_btns[i], i == 0)

	return page


# 横向铺满 + 指定纵向位置（标题栏 / Tab 栏共用）
func _set_top_bar_rect(ctrl: Control, top: float, height: float) -> void:
	ctrl.anchor_left = 0.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_top = top
	ctrl.offset_bottom = top + height


# Tab 选中态：白底 + 3px 蓝色下划线 + 蓝字；未选中：透明底 + 灰字
func _style_help_tab(btn: Button, selected: bool) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var style = _ui._make_panel_style("tab_on" if selected else "tab_off")
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col = _ui.HELP_C_TAB_ON if selected else _ui.HELP_C_TAB_OFF
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_hover_color", col)
	btn.add_theme_color_override("font_pressed_color", col)
	# 选中态加粗视觉：字号放大 1px（主题无粗体字体，靠尺寸差区分）
	btn.add_theme_font_size_override("font_size", 17 if selected else 16)


# 切 Tab：只改 visible + 懒加载内容；绝不做页面淡入
func _set_help_tab(idx: int) -> void:
	if _ui.help_page == null or idx < 0 or idx >= _ui.help_tab_btns.size():
		return
	_ui._help_tab = idx
	for i in range(_ui.help_tab_btns.size()):
		_style_help_tab(_ui.help_tab_btns[i], i == idx)
		if i < _ui.help_scrolls.size():
			_ui.help_scrolls[i].visible = (i == idx)
	if idx < _ui._help_filled.size() and not _ui._help_filled[idx]:
		_fill_help_tab(idx)
		_ui._help_filled[idx] = true


# 构建某个 Tab 的卡片（首次切到该 Tab 时执行一次）
func _fill_help_tab(idx: int) -> void:
	var tabs: Array = _ui.HelpContentScript.get_tabs()
	if idx < 0 or idx >= tabs.size() or idx >= _ui.help_bodies.size():
		return
	var body: VBoxContainer = _ui.help_bodies[idx]
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

	var tab: Dictionary = tabs[idx]
	if tab.get("layout", "grid2") == "cards":
		_fill_help_cards(body, tab)
		return

	# 常规 2 列卡片流
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", int(_ui.HELP_CARD_GAP))
	grid.add_theme_constant_override("v_separation", int(_ui.HELP_CARD_GAP))
	body.add_child(grid)
	for card_data in tab.get("cards", []):
		grid.add_child(_make_help_card(card_data))


# 图鉴 Tab：通栏说明卡 → 7 列元素网格 → 底部 2 列速查卡
func _fill_help_cards(body: VBoxContainer, tab: Dictionary) -> void:
	var cards: Array = tab.get("cards", [])
	var grid_after: int = int(tab.get("grid_after", -1))

	var grid := GridContainer.new()
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for card in _help_element_cards():
		grid.add_child(_make_help_mini_card(card))

	var bottom := GridContainer.new()
	bottom.columns = 2
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("h_separation", int(_ui.HELP_CARD_GAP))
	bottom.add_theme_constant_override("v_separation", int(_ui.HELP_CARD_GAP))

	for i in range(cards.size()):
		var slot = _make_help_card(cards[i])
		if i <= grid_after:
			body.add_child(slot)      # 网格之前的通栏卡
		else:
			bottom.add_child(slot)    # 网格之后的 2 列速查卡
		if i == grid_after:
			body.add_child(grid)
	if bottom.get_child_count() > 0:
		body.add_child(bottom)


# 一张内容卡：左侧强调色条 + 标题 + 分隔线 + 若干行
func _make_help_card(data: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style = _ui._make_panel_style("card")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(_ui.HELP_CARD_MIN_W, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	card.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)

	var accent := ColorRect.new()
	accent.color = data.get("accent", _ui.HELP_C_TAB_ON)
	accent.custom_minimum_size = Vector2(_ui.HELP_ACCENT_BAR_W, 18)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(accent)

	var title := Label.new()
	title.text = data.get("title", "")
	title.add_theme_font_size_override("font_size", _ui.HELP_FS_TITLE)
	title.add_theme_color_override("font_color", _ui.HELP_C_SUB)
	head.add_child(title)

	vb.add_child(_make_help_hsep())

	for line in data.get("lines", []):
		_append_help_line(vb, line)
	return card


# 1px 分隔线（卡片标题与正文之间）
func _make_help_hsep() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = _ui.HELP_C_DIVIDER
	sep.custom_minimum_size = Vector2(0, 1)
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


# 渲染一行：sub / p / li / ex / warn / gap / demo
# 层级靠字号 + 颜色 + 缩进区分，不再依赖空格对齐（比例字体下空格对不齐）
func _append_help_line(parent: VBoxContainer, line: Dictionary) -> void:
	var kind: String = line.get("k", "p")

	if kind == "gap":
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(gap)
		return

	if kind == "demo":
		parent.add_child(_make_help_demo_row(line.get("cards", [])))
		return

	var text: String = line.get("t", "")
	var fs = _ui.HELP_FS_BODY
	var col = _ui.HELP_C_TEXT
	var indent := 0
	match kind:
		"sub":
			fs = _ui.HELP_FS_SUB
			col = _ui.HELP_C_SUB
		"li":
			text = "· " + text
			indent = 4
		"ex":
			fs = _ui.HELP_FS_FX
			col = _ui.HELP_C_EX
			indent = 14
		"warn":
			text = "⚠ " + text
			col = _ui.HELP_C_WARN
			indent = 4
		_:
			pass

	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if indent > 0:
		var wrap_box := MarginContainer.new()
		wrap_box.add_theme_constant_override("margin_left", indent)
		wrap_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap_box.add_child(lb)
		parent.add_child(wrap_box)
	else:
		parent.add_child(lb)


# 图鉴示例行（「看三张典型牌」）
func _make_help_demo_row(symbols: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for sym in symbols:
		var card = _help_find_card(str(sym))
		if card == null:
			continue
		var holder := MarginContainer.new()
		holder.custom_minimum_size = Vector2(96, 0)
		holder.add_child(_make_help_mini_card(card, true))
		row.add_child(holder)
	return row


# 图鉴迷你卡：竖向流式布局，宽度随网格列自适应（不再用绝对坐标）
# show_valence = true 时第 4 行显示常见化合价（「看三张典型牌」示例），
# 否则显示牌库张数 ×N（29 种元素网格，卡片文案已说明「下方数字为张数」）
func _make_help_mini_card(card, show_valence: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(96, 124)
	var style = _ui._make_panel_style("mini_card")
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	var top := HBoxContainer.new()
	vb.add_child(top)
	var l_num = _help_label(str(card.atomic_number), 11, Color(0.35, 0.37, 0.4, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	l_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l_num)
	top.add_child(_help_label(card.group, 11, Color(0.32, 0.34, 0.38, 1.0), HORIZONTAL_ALIGNMENT_RIGHT))

	vb.add_child(_help_label(card.symbol, 26, _help_symbol_color(card), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_help_label(card.name_cn, 13, _ui.HELP_C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if show_valence:
		vb.add_child(_help_label(_help_valence_text(card), 12,
			Color(0.55, 0.2, 0.2, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		vb.add_child(_help_label("×%d" % _ui.HelpContentScript.get_element_copies(card.symbol), 12,
			Color(0.36, 0.39, 0.44, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_help_label("%.1f" % card.atomic_weight, 11, Color(0.45, 0.48, 0.52, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	return panel


# 常见化合价文本：与手牌卡面同一套裁剪规则（放不下只留两端价，Cl → -1 +7）
# 迷你卡只有 96 宽，Cl 的 5 个价全写会撑破卡片；原先是「前 2 个 + …」的独立实现，
# 与卡面 _fit_card_valence 不一致，现统一走 _format_valence_pair。
func _help_valence_text(card) -> String:
	if card == null:
		return "—"
	return _ui._format_valence_pair(card.common_valence)


# 图鉴专用符号色：原配色里稀有气体是 (0.95,0.95,0.95)，
# 在白底卡面上几乎不可见 → 亮度 > 0.90 的统一加深后使用
func _help_symbol_color(card) -> Color:
	var c: Color = _ui._get_card_color(card)
	if c.get_luminance() > 0.90:
		c = c.darkened(0.5)
	return c


func _help_label(text: String, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.horizontal_alignment = align
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


# 29 张 CardData 只造一次，图鉴 Tab / 示例行共用
func _help_element_cards() -> Array:
	if _ui._help_elements.is_empty():
		_ui._help_elements = _ui.HelpContentScript.get_element_cards()
	return _ui._help_elements


func _help_find_card(sym: String):
	for card in _help_element_cards():
		if card.symbol == sym:
			return card
	return null

