# ============================================================
# pages/PageChrome.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4a，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 766-793 行 --------
# 开始页 / 补充规则小页共用：渐变背景（只换节点名）
func _page_bg_into(parent: Control, bg_name: String, band_name: String) -> void:
	var bg := ColorRect.new()
	bg.name = bg_name
	bg.color = _ui.PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var grad := Gradient.new()
	grad.set_color(0, _ui.PAGE_BG_COLOR)
	grad.set_color(1, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 1.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.width = 256
	tex.height = 256

	var band := TextureRect.new()
	band.name = band_name
	band.texture = tex
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# -------- 搬运自 scripts/GameUI.gd 第 884-891 行 --------
func _start_label(text: String, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.horizontal_alignment = align
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


# -------- 搬运自 scripts/GameUI.gd 第 1177-1249 行 --------
# -------- 按钮三件套（P8：开始页 / 结束页 / 教学引导页共用的唯一样式来源）--------
# 主按钮：主题蓝底 + 深蓝边；hover 提亮 + 蓝色光晕
func _page_primary_btn(text: String, cb: Callable, sz: Vector2, node_name: String, fs: int) -> Button:
	var b = _ui._mkb(text, cb, false)
	if node_name != "":
		b.name = node_name
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fs)
	var n: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	n.bg_color = _ui.START_C_ACCENT
	n.border_color = _ui.START_C_ACCENT_DARK
	b.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = _ui.START_C_ACCENT.lightened(0.12)
	h.border_color = _ui.START_C_ACCENT
	h.shadow_color = Color(0.176, 0.478, 0.702, 0.5)
	h.shadow_size = 8
	h.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate()
	p.bg_color = _ui.START_C_ACCENT_DARK
	b.add_theme_stylebox_override("pressed", p)
	b.pivot_offset = sz * 0.5
	return b


# 次按钮：白底 + 主题蓝描边 + 蓝字
func _page_secondary_btn(text: String, cb: Callable, sz: Vector2, node_name: String, fs: int) -> Button:
	var b = _ui._mkb(text, cb, false)
	if node_name != "":
		b.name = node_name
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fs)
	var n: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	n.bg_color = Color(1, 1, 1, 0.96)
	n.border_color = _ui.START_C_ACCENT
	n.set_border_width_all(_ui.BORDER_W_ACTIVE)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_color_override("font_color", _ui.START_C_ACCENT)
	b.add_theme_color_override("font_hover_color", _ui.START_C_ACCENT_DARK)
	b.add_theme_color_override("font_pressed_color", _ui.START_C_ACCENT_DARK)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.92, 0.96, 1.0, 1.0)
	b.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate()
	p.bg_color = Color(0.85, 0.92, 0.98, 1.0)
	b.add_theme_stylebox_override("pressed", p)
	b.pivot_offset = sz * 0.5
	return b


# 幽灵按钮：透明底 + 灰字，hover 蓝字 + 10% 蓝底
func _page_ghost_btn(text: String, cb: Callable, sz: Vector2, node_name: String, fs: int) -> Button:
	var b = _ui._mkb(text, cb, false)
	if node_name != "":
		b.name = node_name
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", _ui.START_C_MUTED)
	b.add_theme_color_override("font_hover_color", _ui.START_C_ACCENT)
	b.add_theme_color_override("font_pressed_color", _ui.START_C_ACCENT_DARK)
	for st in ["normal", "pressed"]:
		var s = _ui._make_panel_style("tab_off")
		s.bg_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(st, s)
	var h = _ui._make_panel_style("tab_off")
	h.bg_color = Color(0.176, 0.478, 0.702, 0.1)
	b.add_theme_stylebox_override("hover", h)
	b.pivot_offset = sz * 0.5
	return b


# -------- 搬运自 scripts/GameUI.gd 第 1379-1428 行 --------
# 通用：任意页面子节点错峰淡入（第 i 个节点延迟 i×50ms；每个节点一条独立补间，
# 淡入与上浮并行，互不排队 —— 共用一个 tween 会串成 3 秒）
# 只碰子节点的 modulate / position；页面级 modulate 归 _fade_in_page 独占
func _animate_page_intro(page: Control, order: Array) -> void:
	if page == null or not is_instance_valid(page):
		return
	for t in _ui._page_intro_tweens:
		if t is Tween and t.is_valid():
			t.kill()
	_ui._page_intro_tweens.clear()
	var i := 0
	for n in order:
		var node = page.get_node_or_null(n)
		if node == null or not (node is Control):
			continue
		# 目标位置固定为首次入场时的位置：_show_end_page 会被反复调用，
		# 若拿「当前 position」当目标，上次动画没播完就会累积偏移
		if not node.has_meta("intro_base_y"):
			node.set_meta("intro_base_y", node.position.y)
		var target_y: float = float(node.get_meta("intro_base_y"))
		node.modulate.a = 0.0
		node.position.y = target_y + 14.0
		var delay := i * 0.05
		var t := page.create_tween()
		t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(node, "modulate:a", 1.0, 0.26).set_delay(delay)
		t.parallel().tween_property(node, "position:y", target_y, 0.3).set_delay(delay)
		_ui._page_intro_tweens.append(t)
		i += 1


# 通用：装饰牌缓慢浮动（每页只启动一次，has_meta 去重）
func _page_deco_float(page: Control) -> void:
	if page == null or not is_instance_valid(page):
		return
	var holder = page.get_node_or_null("DecorCards")
	if holder == null or holder.has_meta("float_started"):
		return
	holder.set_meta("float_started", true)
	var i := 0
	for card in holder.get_children():
		if not (card is Control):
			continue
		var base_y: float = card.position.y
		var dur := 1.8 + i * 0.22
		var t := card.create_tween().set_loops()
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(card, "position:y", base_y - 7.0, dur)
		t.tween_property(card, "position:y", base_y, dur)
		i += 1


# -------- 搬运自 scripts/GameUI.gd 第 1921-1982 行 --------
# 45° 渐变带（同色底 → 白，左下最亮），开始页同款
func _page_gradient_band(page: Control) -> void:
	var grad := Gradient.new()
	grad.set_color(0, _ui.PAGE_BG_COLOR)
	grad.set_color(1, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 1.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.width = 256
	tex.height = 256

	var band := TextureRect.new()
	band.name = "GradientBand"
	band.texture = tex
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# 元素水印：只负责氛围，一律 ASCII 化学式（默认中文字体没有下标字形）
func _page_watermarks(page: Control, specs: Array) -> void:
	var marks := Control.new()
	marks.name = "Watermarks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in specs:
		var lb := Label.new()
		lb.text = s["t"]
		lb.add_theme_font_size_override("font_size", int(s["fs"]))
		lb.add_theme_color_override("font_color", _ui.START_C_WATERMARK)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.position = s["p"]
		marks.add_child(lb)


# 倾斜装饰牌（白底 + 真实元素配色，半透明）；holder 名固定 DecorCards 供浮动动效查找
func _page_deco_cards(page: Control, cards: Array) -> void:
	var holder := Control.new()
	holder.name = "DecorCards"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for c in cards:
		holder.add_child(_ui._start_make_deco_card(c["s"], c["p"], c["a"]))


# 页面底 + 渐变带 + 水印 + 装饰牌（结束页 / 教学页共用的三段式背景）
func _page_backdrop(page: Control, bg_name: String, marks: Array, cards: Array) -> void:
	var bg := ColorRect.new()
	bg.name = bg_name
	bg.color = _ui.PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_gradient_band(page)
	_page_watermarks(page, marks)
	_page_deco_cards(page, cards)