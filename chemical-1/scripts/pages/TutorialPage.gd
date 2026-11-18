# ============================================================
# pages/TutorialPage.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4f，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 616-626 行 --------
func _on_show_tutorial_page() -> void:
	var tut_page = _ui.get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = true
	if _ui.start_page: _ui.start_page.visible = false
	if _ui.end_page: _ui.end_page.visible = false
	_ui._fade_in_page(tut_page)
	_ui._page_deco_float(tut_page)
	_ui._animate_page_intro(tut_page, [
		"TutorialTitle", "TutorialSubtitle", "TutorialAccent",
		"Tutorial0Btn", "Tutorial1Btn", "Tutorial2Btn", "TutorialBackBtn",
	])


# -------- 搬运自 scripts/GameUI.gd 第 628-634 行 --------
func _on_tutorial_back() -> void:
	var tut_page = _ui.get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	if _ui.start_page: _ui.start_page.visible = true
	if _ui.end_page: _ui.end_page.visible = false
	_ui._fade_in_page(_ui.start_page)
	_ui._animate_start_page()


# -------- 搬运自 scripts/GameUI.gd 第 1002-1138 行 --------
func _build_tutorial_page() -> void:
	var page = _ui.get_node_or_null("TutorialPage")
	if page == null:
		return
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	_ui._page_backdrop(page, "TutorialBg", [
		{"t": "H₂O", "p": Vector2(36, 430), "fs": 68},
		{"t": "CO₂", "p": Vector2(896, 70), "fs": 54},
		{"t": "CH₄", "p": Vector2(1000, 500), "fs": 46},
	], [
		{"s": "Cl", "p": Vector2(64, 96), "a": -0.12},
		{"s": "Na", "p": Vector2(984, 300), "a": 0.13},
	])

	# -------- 标题块（与开始页同档字号：40 / 16 / 72×4）--------
	var title = _ui._start_label("教学引导", 40, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "TutorialTitle"
	title.position = Vector2(0, 64)
	title.size = Vector2(1152, 52)
	page.add_child(title)

	var sub = _ui._start_label("从认识牌面到族炸接炸，三步上手", 16, _ui.START_C_SUB,
		HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "TutorialSubtitle"
	sub.position = Vector2(0, 120)
	sub.size = Vector2(1152, 24)
	page.add_child(sub)

	var accent := ColorRect.new()
	accent.name = "TutorialAccent"
	accent.color = _ui.START_C_ACCENT
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent.position = Vector2(540, 150)
	accent.size = Vector2(72, 4)
	page.add_child(accent)

	# -------- 三张关卡卡 --------
	var levels := [
		{"t": "游戏入门", "d": "熟悉游戏界面、了解基础流程与核心规则 · 限前3周期牌库"},
		{"t": "基础入门", "d": "原子牌·单质·化合物·比大小 / 禁止族炸"},
		{"t": "族炸进阶", "d": "族炸接炸·溢出化合物·手牌上限"},
	]
	_ui._tut_cards.clear()
	for i in range(levels.size()):
		var card = _make_level_card(i, levels[i]["t"], levels[i]["d"])
		card.position = Vector2(_ui.TUT_CARD_X, _ui.TUT_CARD_Y0 + i * (_ui.TUT_CARD_H + _ui.TUT_CARD_GAP))
		page.add_child(card)
		_ui._tut_cards.append(card)

	# -------- 返回 --------
	# 回调统一由 _setup_pages() 连接（与开始页按钮一致），这里不传，避免重复 connect
	var back = _ui._page_ghost_btn("← 返回", func() -> void: pass, Vector2(160, 42),
		"TutorialBackBtn", 16)
	back.position = Vector2(496, 544)
	page.add_child(back)


# 关卡卡：整卡一个 Button；hover 只改描边 / 阴影（720 宽做 1.05 缩放会顶到装饰牌）
func _make_level_card(idx: int, title_text: String, desc_text: String) -> Button:
	var b := Button.new()
	b.name = "Tutorial%dBtn" % idx
	b.custom_minimum_size = Vector2(_ui.TUT_CARD_W, _ui.TUT_CARD_H)
	b.size = Vector2(_ui.TUT_CARD_W, _ui.TUT_CARD_H)
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _level_card_style(false, false))
	b.add_theme_stylebox_override("hover", _level_card_style(true, false))
	b.add_theme_stylebox_override("pressed", _level_card_style(false, true))
	b.add_theme_stylebox_override("focus", _ui._make_panel_style("tab_off"))
	b.mouse_entered.connect(_ui._on_level_card_hover.bind(b, true))
	b.mouse_exited.connect(_ui._on_level_card_hover.bind(b, false))

	var badge := Panel.new()
	badge.name = "LevelBadge"
	badge.position = Vector2(24, 28)
	badge.size = Vector2(48, 48)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = _ui.START_C_ACCENT
	bs.set_corner_radius_all(8)
	badge.add_theme_stylebox_override("panel", bs)
	b.add_child(badge)

	var num = _ui._start_label(str(idx), 24, Color(1, 1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	num.name = "LevelBadgeNum"
	num.position = Vector2(0, 11)
	num.size = Vector2(48, 32)
	badge.add_child(num)

	var tl = _ui._start_label(title_text, 20, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	tl.name = "Tutorial%dTitle" % idx
	tl.position = Vector2(92, 18)
	tl.size = Vector2(470, 28)
	b.add_child(tl)

	var dl = _ui._start_label(desc_text, 14, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	dl.name = "Tutorial%dDesc" % idx
	dl.position = Vector2(92, 50)
	dl.size = Vector2(470, 40)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(dl)

	var go = _ui._start_label("开始 →", 15, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	go.name = "Tutorial%dGo" % idx
	go.position = Vector2(600, 40)
	go.size = Vector2(96, 24)
	b.add_child(go)
	return b


func _level_card_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	var sb = _ui._make_panel_style("card")
	sb.bg_color = Color(1, 1, 1, 0.96)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	if hover:
		sb.border_color = _ui.START_C_ACCENT
		sb.set_border_width_all(_ui.BORDER_W_ACTIVE)
		sb.shadow_color = Color(0.176, 0.478, 0.702, 0.22)
		sb.shadow_size = 8
	if pressed:
		sb.bg_color = Color(0.937, 0.965, 0.988, 1.0)
		sb.border_color = _ui.START_C_ACCENT
		sb.set_border_width_all(_ui.BORDER_W_ACTIVE)
	return sb


# 关卡卡 hover：「开始 →」由主题蓝加深，作为卡片被选中的视觉提示
func _on_level_card_hover(card: Button, entered: bool) -> void:
	if not is_instance_valid(card):
		return
	var col = _ui.START_C_ACCENT_DARK if entered else _ui.START_C_ACCENT
	for c in card.get_children():
		if c is Label and String(c.name).begins_with("Tutorial") and String(c.name).ends_with("Go"):
			c.add_theme_color_override("font_color", col)