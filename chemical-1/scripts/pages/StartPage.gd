# ============================================================
# pages/StartPage.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4b，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 747-769 行 --------
func _build_start_page() -> void:
	if not _ui.start_page:
		return
	# 场景里若残留静态子节点（老版本 Main.tscn），先整段清掉，保证只有一套 UI
	for c in _ui.start_page.get_children():
		_ui.start_page.remove_child(c)
		c.queue_free()
	_start_page_bg()
	_start_page_decor()
	_start_page_title()
	_start_page_settings()
	_start_page_buttons()
	# P10：补充规则小页（盖在开始页之上，默认隐藏）
	_ui._build_supp_rules_page()
	# Step 4：房间页（同样盖在开始页之上，默认隐藏）
	_ui._build_room_page()


# -------- 背景：同色底 + 45° 渐变带 --------
func _start_page_bg() -> void:
	_ui._page_bg_into(_ui.start_page, "StartPageBg", "GradientBand")




# -------- 搬运自 scripts/GameUI.gd 第 776-863 行 --------
# -------- 装饰：元素水印 + 5 张倾斜装饰牌 --------
func _start_page_decor() -> void:
	var marks := Control.new()
	marks.name = "Watermarks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.start_page.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var specs := [
		{"t": "H₂O", "p": Vector2(34, 60), "fs": 76},
		{"t": "CO₂", "p": Vector2(880, 34), "fs": 64},
		{"t": "NaCl", "p": Vector2(96, 520), "fs": 54},
		{"t": "CH₄", "p": Vector2(946, 540), "fs": 58},
		{"t": "O₂", "p": Vector2(520, 596), "fs": 44},
	]
	for s in specs:
		var lb := Label.new()
		lb.text = s["t"]
		lb.add_theme_font_size_override("font_size", int(s["fs"]))
		lb.add_theme_color_override("font_color", _ui.START_C_WATERMARK)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.position = s["p"]
		marks.add_child(lb)

	var holder := Control.new()
	holder.name = "DecorCards"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.start_page.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cards := [
		{"s": "H", "p": Vector2(38, 392), "a": -0.14},
		{"s": "O", "p": Vector2(118, 476), "a": 0.10},
		{"s": "Cl", "p": Vector2(1002, 400), "a": 0.13},
		{"s": "Na", "p": Vector2(922, 484), "a": -0.10},
		{"s": "Fe", "p": Vector2(1046, 96), "a": 0.16},
	]
	for c in cards:
		holder.add_child(_start_make_deco_card(c["s"], c["p"], c["a"]))


# 装饰牌：白底 + 真实元素配色，整体半透明，只负责氛围
func _start_make_deco_card(sym: String, pos: Vector2, angle: float) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(94, 120)
	panel.position = pos
	panel.size = Vector2(94, 120)
	panel.pivot_offset = Vector2(47, 60)
	panel.rotation = angle
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = _ui._make_panel_style("card")
	style.bg_color = Color(1, 1, 1, 0.9)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var card = _ui._help_find_card(sym)
	var sym_col = _ui.START_C_TITLE
	var name_cn := "元素"
	var num := 0
	if card != null:
		sym_col = _ui._help_symbol_color(card)
		name_cn = card.name_cn
		num = card.atomic_number

	var l_num = _ui._start_label(str(num), 12, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	l_num.position = Vector2(8, 6)
	l_num.size = Vector2(40, 16)
	panel.add_child(l_num)

	var l_sym = _ui._start_label(sym, 32, sym_col, HORIZONTAL_ALIGNMENT_CENTER)
	l_sym.position = Vector2(0, 26)
	l_sym.size = Vector2(94, 40)
	panel.add_child(l_sym)

	var l_name = _ui._start_label(name_cn, 13, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	l_name.position = Vector2(0, 72)
	l_name.size = Vector2(94, 18)
	panel.add_child(l_name)

	var l_w = _ui._start_label("%.1f" % (card.atomic_weight if card != null else 0.0), 12,
		_ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l_w.position = Vector2(0, 94)
	l_w.size = Vector2(94, 16)
	panel.add_child(l_w)

	return panel




# -------- 搬运自 scripts/GameUI.gd 第 870-969 行 --------
# -------- 标题区：主标题 + 英文副标题 + 强调条 + 元信息 --------
func _start_page_title() -> void:
	var title = _ui._start_label("化学碰撞", _ui.START_FS_TITLE, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "StartTitle"
	_ui.start_page.add_child(title)
	title.position = Vector2(0, 92)
	title.size = Vector2(1152, 64)

	var sub = _ui._start_label("CHEMICAL COLLISION", _ui.START_FS_SUB, _ui.START_C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "StartSubtitle"
	_ui.start_page.add_child(sub)
	sub.position = Vector2(0, 160)
	sub.size = Vector2(1152, 26)

	var accent := ColorRect.new()
	accent.name = "StartAccent"
	accent.color = _ui.START_C_ACCENT
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.start_page.add_child(accent)
	accent.position = Vector2(540, 196)
	accent.size = Vector2(72, 4)

	var meta = _ui._start_label("29 种元素 · 182 张牌 · 3-8 人同屏 · 出完手牌即胜",
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	meta.name = "StartMeta"
	_ui.start_page.add_child(meta)
	meta.position = Vector2(0, 210)
	meta.size = Vector2(1152, 20)


# -------- 设置卡：人数 / AI 数 / 补充规则入口（P10 起四条补充规则收进独立小页）--------
func _start_page_settings() -> void:
	var card := Panel.new()
	card.name = "SettingsCard"
	card.position = Vector2(266, 246)
	card.size = Vector2(620, 210)
	var cs = _ui._make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.94)
	card.add_theme_stylebox_override("panel", cs)
	_ui.start_page.add_child(card)

	card.add_child(_start_setting_label("PlayerCountLabel", "总玩家人数", Vector2(32, 26)))
	var ps = _start_make_spin(3, 8, 4, "PlayerCountSpin")
	ps.position = Vector2(300, 20)
	ps.size = Vector2(150, 38)
	card.add_child(ps)

	card.add_child(_start_setting_label("AiCountLabel", "AI 人数", Vector2(32, 72)))
	var ai_s = _start_make_spin(1, 3, 3, "AiCountSpin")
	ai_s.position = Vector2(300, 66)
	ai_s.size = Vector2(150, 38)
	card.add_child(ai_s)

	var div := ColorRect.new()
	div.name = "SettingsDivider"
	div.color = Color(0.85, 0.89, 0.94, 1.0)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	div.position = Vector2(32, 118)
	div.size = Vector2(556, 1)
	card.add_child(div)

	# P10：4 条补充规则（有机物 / 顺序 / 卤族互化 / 元素限制）合成一小页，
	# 设置卡只留一个入口 + 一行摘要，避免第 4 个开关把人数和开局按钮挤没
	var entry = _start_make_ghost("SupplementaryHelpBtn", "补充规则 · 默认 ▸",
		Vector2(32, 128), Vector2(300, 34))
	entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	entry.tooltip_text = "有机物胜利 / 顺序牌型 / 允许卤族互化 / 元素限制"
	card.add_child(entry)

	var sum = _ui._start_label("", _ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	sum.name = "SuppRulesSummary"
	sum.position = Vector2(32, 170)
	sum.size = Vector2(556, 20)
	card.add_child(sum)

	# 勾选反馈写在这里：开始页看不到 GamePage 的 InfoLabel
	var rule_hint = _ui._start_label("", _ui.START_FS_META, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	rule_hint.name = "StartRuleHint"
	_ui.start_page.add_child(rule_hint)
	rule_hint.position = Vector2(266, 462)
	rule_hint.size = Vector2(620, 20)
	rule_hint.modulate.a = 0.0

	# P14-D：触屏界面开关。放在「补充规则」同一行的右侧 —— 卡内还剩约 250px，
	# 不改卡片高度（第 3 个开关曾把开局按钮挤出卡外，见 P10 的注释）。
	# 它不是游戏规则，所以不进补充规则小页，就摆在设置卡上随手可切。
	var touch_tg = _start_make_toggle("TouchUIToggle", "触屏界面 · 关", Vector2(344, 129))
	touch_tg.custom_minimum_size = Vector2(240, 32)
	touch_tg.size = Vector2(240, 32)
	touch_tg.add_theme_font_size_override("font_size", 15)
	touch_tg.tooltip_text = "按钮更高、字号 +2、手势更跟手（真机 / 平板推荐开启，随时可切回）"
	card.add_child(touch_tg)


func _start_setting_label(node_name: String, text: String, pos: Vector2) -> Label:
	var lb = _ui._start_label(text, _ui.START_FS_LABEL, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	lb.name = node_name
	lb.position = pos
	lb.size = Vector2(230, 32)
	return lb


# -------- 搬运自 scripts/GameUI.gd 第 972-983 行 --------
# -------- 按钮区 --------
# Step 4：开始页纵向已排到 632，只剩这一行有空间 —— 「开始游戏 / 联机对战」并排。
# 单机那颗字号 22 → 20：宽度从 260 收到 124，「开始游戏」四个字才不会撑破按钮。
func _start_page_buttons() -> void:
	_ui.start_button = _ui._page_primary_btn("开始游戏", func() -> void: pass,
		Vector2(124, 52), "StartButton", 20)
	_ui.start_button.position = Vector2(446, 486)
	_ui.start_page.add_child(_ui.start_button)
	_ui.start_page.add_child(_start_make_secondary("RoomEntryBtn", "联机对战", Vector2(582, 486), Vector2(124, 52)))
	_ui.start_page.add_child(_start_make_secondary("TutorialBtn", "教学引导", Vector2(446, 546), Vector2(260, 46)))
	_ui.start_page.add_child(_start_make_ghost("ExitButton", "退出程序", Vector2(476, 598), Vector2(200, 34)))



# -------- 搬运自 scripts/GameUI.gd 第 1165-1219 行 --------
# -------- 开始页按钮薄壳：保持旧签名，视觉/动效零变化 --------
func _start_make_primary(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b = _ui._page_primary_btn(text, func() -> void: pass, sz, "StartButton", 22)
	b.position = pos
	return b


func _start_make_secondary(node_name: String, text: String, pos: Vector2, sz: Vector2) -> Button:
	var b = _ui._page_secondary_btn(text, func() -> void: pass, sz, node_name, 19)
	b.position = pos
	return b


func _start_make_ghost(node_name: String, text: String, pos: Vector2, sz: Vector2) -> Button:
	var b = _ui._page_ghost_btn(text, func() -> void: pass, sz, node_name, 16)
	b.position = pos
	return b


# -------- SpinBox：白底 + 主题蓝焦点边框 --------
func _start_make_spin(min_v: int, max_v: int, val: int, node_name: String) -> SpinBox:
	var sp := SpinBox.new()
	sp.name = node_name
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = 1
	sp.value = val
	sp.allow_greater = false
	sp.allow_lesser = false
	sp.custom_minimum_size = Vector2(150, 38)
	sp.add_theme_font_size_override("font_size", 18)

	var le := sp.get_line_edit()
	le.add_theme_font_size_override("font_size", 18)
	le.add_theme_color_override("font_color", _ui.START_C_TITLE)
	var n = _ui._make_panel_style("mini_card")
	n.bg_color = Color(1, 1, 1, 1)
	n.content_margin_left = 10
	n.content_margin_right = 6
	n.content_margin_top = 4
	n.content_margin_bottom = 4
	le.add_theme_stylebox_override("normal", n)
	var f: StyleBoxFlat = n.duplicate()
	f.border_color = _ui.BORDER_FOCUS
	f.set_border_width_all(_ui.BORDER_W_ACTIVE)
	le.add_theme_stylebox_override("focus", f)

	# 内部上下箭头按钮：去掉默认灰块，白卡面上更干净
	for child in sp.get_children():
		if child is Button:
			for st in ["normal", "hover", "pressed"]:
				var s = _ui._make_panel_style("tab_off")
				s.bg_color = Color(0, 0, 0, 0) if st != "hover" else Color(0.176, 0.478, 0.702, 0.12)
				child.add_theme_stylebox_override(st, s)
	return sp


# -------- 搬运自 scripts/GameUI.gd 第 1222-1272 行 --------
# -------- 规则开关：未选白底灰边 / 选中主题蓝底白字 + 左侧 4px 强调条 --------
func _start_make_toggle(node_name: String, text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(270, 32)
	b.size = Vector2(270, 32)
	b.position = pos
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", _ui.START_C_TITLE)
	b.add_theme_color_override("font_hover_color", _ui.START_C_TITLE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1, 1))

	var off = _ui._make_panel_style("mini_card")
	off.bg_color = Color(1, 1, 1, 1)
	off.content_margin_left = 12
	off.content_margin_right = 12
	off.content_margin_top = 4
	off.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", off)
	var hover: StyleBoxFlat = off.duplicate()
	hover.bg_color = Color(0.96, 0.98, 1.0, 1.0)
	hover.border_color = _ui.BORDER_FOCUS
	b.add_theme_stylebox_override("hover", hover)

	var on = _ui._make_panel_style("mini_card")
	on.bg_color = _ui.START_C_ACCENT
	on.border_color = _ui.START_C_ACCENT_DARK
	on.border_width_left = 4
	on.content_margin_left = 12
	on.content_margin_right = 12
	on.content_margin_top = 4
	on.content_margin_bottom = 4
	b.add_theme_stylebox_override("pressed", on)
	var on_hover: StyleBoxFlat = on.duplicate()
	on_hover.bg_color = _ui.START_C_ACCENT.lightened(0.08)
	b.add_theme_stylebox_override("hover_pressed", on_hover)

	var sk = _ui._make_panel_style("tab_off")
	b.add_theme_stylebox_override("focus", sk)

	b.mouse_entered.connect(_ui._on_button_hover_scale.bind(b, true))
	b.mouse_exited.connect(_ui._on_button_hover_scale.bind(b, false))
	b.button_down.connect(_ui._on_button_press_scale.bind(b, true))
	b.button_up.connect(_ui._on_button_press_scale.bind(b, false))
	b.pivot_offset = Vector2(135, 16)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	return b


# -------- 搬运自 scripts/GameUI.gd 第 1285-1289 行 --------
func _animate_start_page() -> void:
	if not _ui.start_page:
		return
	_ui._page_deco_float(_ui.start_page)
	_ui._animate_page_intro(_ui.start_page, _ui.START_INTRO_ORDER)


# -------- 搬运自 scripts/GameUI.gd 第 1301-1319 行 --------
# 勾选补充规则 / 人数自动纠正时在开始页内联提示 2 秒（GamePage 的 InfoLabel 此刻不可见）
func _start_flash_rule_hint(text: String, col: Color) -> void:
	if not _ui.start_page:
		return
	var lb = _ui.start_page.get_node_or_null("StartRuleHint")
	if lb == null:
		return
	lb.add_theme_color_override("font_color", col)
	lb.text = text
	lb.modulate.a = 1.0
	# get_meta(name, null) 在 Godot 里等同于单参数调用（仍然报错），改判 has_meta
	var old = lb.get_meta("tween") if lb.has_meta("tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var t: Tween = lb.create_tween()
	t.tween_interval(1.4)
	t.tween_property(lb, "modulate:a", 0.0, 0.5)
	lb.set_meta("tween", t)
