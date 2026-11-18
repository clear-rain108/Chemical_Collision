# ============================================================
# tutorial/Level0Overlay.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4f，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 1080-1469 行 --------
func _level0_start_phase1() -> void:
	_ui.game_manager.set_tutorial_level0_phase(1)
	_ui.level0_step = 0
	_ui.level0_ui_highlight_steps = _level0_ui_steps()
	_level0_show_ui_step(0)


# 第零关 Phase 1 的 6 步标注数据（纯数据、无副作用）：
# 抽成函数是为了让 tests/verify_tool_buttons.gd 能直接取「按钮区」矩形，
# 不必为了读一条数据先去造 GameManager + 刷 UI。
func _level0_ui_steps() -> Array:
	return [
		{
			"title": "玩家顺序和手牌数",
			"desc": "这是【玩家顺序和手牌数】\n显示每位玩家的名字、AI标签、手牌张数，以及当前轮到谁（◄标记）",
			"target": "info_label",
			"pos": Vector2(20, 60),
			"size": Vector2(460, 88),
		},
		{
			"title": "桌面的牌",
			"desc": "这是【桌面的牌】\n显示当前桌面上的牌是谁打出的、牌型是什么、有无特殊状态（如免疫、接炸中）",
			"target": "table_label",
			"pos": Vector2(20, 150),
			"size": Vector2(600, 130),
		},
		{
			"title": "手牌区",
			"desc": "这是【手牌区】\n你的手牌在这里显示，每张牌为95×118px的原子牌面，牌多时自动重叠排列，鼠标悬停可展开查看\n点击可选中（黄色高亮）",
			"target": "hand_container",
			"pos": Vector2(16, 308),
			"size": Vector2(804, 160),
		},
		{
			"title": "出牌区",
			"desc": "这是【出牌区】\n选中手牌后在此选择牌型：单质/化合物/族炸，也可跳过或查看提示",
			"target": "action_panel",
			# 高亮框 = 1 行面板矩形；几何只有一处定义（§九 ACTION_PANEL_*），
			# 折行 / 触屏档都由 _action_panel_hl_rect() 跟随，改几何不会漏改这里
			"pos": _ui._action_panel_hl_rect().position,
			"size": _ui._action_panel_hl_rect().size,
		},
		{
			"title": "其他细节（右面板）",
			"desc": "这是【其他细节-右面板】\n游戏日志逐条记录每一手牌（谁出了什么、轮到谁）；第零关练习阶段这里换成「规则提醒」，写着当前该记住的出牌规则\n点标题条可折叠 / 展开",
			"target": "log_label",
			# 高亮框 = 右栏面板的实况矩形（见 _right_panel_hl_rect()）：
			# 折叠 / 日志条数 / 规则提醒占用都会改面板大小，写死矩形必然画歪
			"pos": _ui._right_panel_hl_rect().position,
			"size": _ui._right_panel_hl_rect().size,
		},
		{
			"title": "其他细节（按钮区）",
			"desc": "这是【其他细节-按钮区】\n包括显示提示按钮、帮助按钮（查看规则）、退出游戏按钮",
			"target": "quit_button",
			# 高亮框 = 工具行 bbox 外扩 6px；几何只有一处定义（§八之四 TOOL_ROW_HL_*），
			# 触屏档由 _tool_row_hl_rect() 跟随放大的工具行，改几何不会漏改这里
			"pos": _ui._tool_row_hl_rect().position,
			"size": _ui._tool_row_hl_rect().size,
		},
	]


func _level0_show_ui_step(idx: int) -> void:
	_ui._refresh_ui()

	if idx >= _ui.level0_ui_highlight_steps.size():
		_level0_start_phase2()
		return

	var step_data = _ui.level0_ui_highlight_steps[idx]
	_ui.level0_step = idx
	# 右栏面板的几何会随「折叠 / 日志条数 / 规则提醒是否占用」变化，建 steps 时的坐标是快照，
	# 直接画会框住一片空白 → 展示时按节点实况刷新（_refresh_ui() 刚跑过，_layout_log_panel() 已算好几何）
	if step_data.get("target", "") == "log_label":
		var rp: Rect2 = _ui._right_panel_hl_rect()
		step_data["pos"] = rp.position
		step_data["size"] = rp.size
	_level0_ensure_overlay()

	for child in _ui.level0_overlay.get_children():
		child.queue_free()

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_left = 0
	bg.anchor_top = 0
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.level0_overlay.add_child(bg)

	var hl_border = ColorRect.new()
	hl_border.color = Color(1, 1, 0, 0)
	hl_border.position = step_data.pos
	hl_border.size = step_data.size
	hl_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.level0_overlay.add_child(hl_border)

	var hl_outline = _level0_make_outline_rect(step_data.pos, step_data.size, Color(1, 0.85, 0, 1), 4)
	_ui.level0_overlay.add_child(hl_outline)

	var tbx = 20
	var tby = 350
	var tbw = 520          # 620+520=1140 < 1152：手牌区那一步不再把框推出画布
	var tbh = 270
	var hl_bottom = step_data.pos.y + step_data.size.y
	if hl_bottom > tby + 40 or (step_data.pos.x < tbx + tbw and step_data.pos.x + step_data.size.x > tbx):
		if step_data.pos.x > 600:
			tbx = 20
		elif step_data.pos.y > 450:
			tby = 50
		else:
			tbx = 620
			tby = 50
	# 越界兜底：无论命中哪个分支，都不许把提示框推出 1152×648 画布（留 20px 边距）
	var canvas: Vector2 = _ui.game_page.size if _ui.game_page != null else Vector2(1152, 648)
	tbx = clampi(tbx, 20, maxi(20, int(canvas.x) - tbw - 20))
	tby = clampi(tby, 20, maxi(20, int(canvas.y) - tbh - 20))
	var tip_bg = ColorRect.new()
	tip_bg.color = Color(1, 1, 0.85, 0.95)
	tip_bg.position = Vector2(tbx, tby)
	tip_bg.size = Vector2(tbw, tbh)
	_ui.level0_overlay.add_child(tip_bg)

	var tip_border = _level0_make_outline_rect(Vector2(tbx, tby), Vector2(tbw, tbh), Color(1, 0.6, 0, 1), 3)
	_ui.level0_overlay.add_child(tip_border)

	var tip_title = Label.new()
	# 顺序很重要：Label 的 size 会被「未换行时的最小宽度」撑大，
	# 必须先开 autowrap 再定 size，否则文字会画到框外（实机截图 bug）
	tip_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_title.text = step_data.title
	tip_title.add_theme_font_size_override("font_size", 18)
	tip_title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	tip_title.position = Vector2(tbx + 24, tby + 14)
	tip_title.size = Vector2(tbw - 48, 24)
	_ui.level0_overlay.add_child(tip_title)

	var tip_desc = Label.new()
	tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_desc.text = step_data.desc
	tip_desc.add_theme_font_size_override("font_size", 14)
	tip_desc.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	tip_desc.position = Vector2(tbx + 24, tby + 44)
	tip_desc.size = Vector2(tbw - 48, 150)
	_ui.level0_overlay.add_child(tip_desc)

	# 步骤计数挪到右上角：提示框底部整行留给三个出口按钮
	var step_indicator = Label.new()
	step_indicator.text = "%d / %d" % [idx + 1, _ui.level0_ui_highlight_steps.size()]
	step_indicator.add_theme_font_size_override("font_size", 13)
	step_indicator.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	step_indicator.position = Vector2(tbx + tbw - 96, tby + 16)
	step_indicator.size = Vector2(72, 20)
	_ui.level0_overlay.add_child(step_indicator)

	# 三个出口（P15-A）：老实现只有「下一步」，而遮罩是 MOUSE_FILTER_STOP 全屏铺满，
	# 玩家必须把 6 步点完才能摸牌，想换关卡只能杀进程。
	var guide_h: float = float(_ui._touch_btn_h(42))
	var guide_y: float = float(tby) + 206.0
	var next_text := "下一步 →" if idx < _ui.level0_ui_highlight_steps.size() - 1 else "继续 →"
	_ui.level0_overlay.add_child(_level0_guide_btn(
		Vector2(tbx + 24, guide_y), Vector2(130, guide_h), next_text, _level0_ui_next_step))
	_ui.level0_overlay.add_child(_level0_guide_btn(
		Vector2(tbx + 166, guide_y), Vector2(130, guide_h), "跳过引导", _level0_skip_guide))
	_ui.level0_overlay.add_child(_level0_guide_btn(
		Vector2(tbx + 308, guide_y), Vector2(120, guide_h), "返回关卡", _level0_exit_guide))


func _level0_make_outline_rect(pos: Vector2, rect_size: Vector2, color: Color, width: int) -> Control:
	var c = Control.new()
	c.position = pos
	c.size = rect_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top = ColorRect.new()
	top.color = color
	top.position = Vector2(0, 0)
	top.size = Vector2(rect_size.x, width)
	c.add_child(top)
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.position = Vector2(0, rect_size.y - width)
	bottom.size = Vector2(rect_size.x, width)
	c.add_child(bottom)
	var left = ColorRect.new()
	left.color = color
	left.position = Vector2(0, 0)
	left.size = Vector2(width, rect_size.y)
	c.add_child(left)
	var right = ColorRect.new()
	right.color = color
	right.position = Vector2(rect_size.x - width, 0)
	right.size = Vector2(width, rect_size.y)
	c.add_child(right)
	return c


func _level0_ui_next_step() -> void:
	_ui.level0_step += 1
	_level0_show_ui_step(_ui.level0_step)


# 引导阶段的通用出口按钮（Phase 1 提示框底部 / Phase 2 对话框底部共用）：
# 位置尺寸由调用方给（两处对话框的行高与列宽不同），字号统一走触屏档
func _level0_guide_btn(pos: Vector2, btn_size: Vector2, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = btn_size
	b.add_theme_font_size_override("font_size", _ui._touch_fs(15, 2))
	b.position = pos
	b.size = btn_size
	b.pressed.connect(cb)
	return b


# 「跳过引导」：Phase 1 / Phase 2 都一步跳到牌局练习（开场提示与规则提醒照常给）。
# 遮罩是 MOUSE_FILTER_STOP 全屏，不给这条出口玩家就只能把 6+3 步点完才能摸牌。
func _level0_skip_guide() -> void:
	if _ui.game_manager == null:
		return
	_level0_start_phase3()


# 「返回关卡」：引导中途退出教学 → 回教学引导页重选关卡。
# _on_show_tutorial_page() 只处理「从开始页 / 结算页过来」的可见性，
# 这里必须自己把 GamePage 藏掉，否则引导页会被压在游戏页下面（点了像没反应）。
func _level0_exit_guide() -> void:
	if _ui.level0_overlay:
		_ui.level0_overlay.queue_free()
		_ui.level0_overlay = null
	_ui.level0_ui_highlight_steps = []
	_ui.level0_flow_steps = []
	_level0_clear_rule_tips()
	if _ui.game_manager:
		_ui.game_manager.phase = 2   # 本局作废：别让残留的 AI 计时器在后台继续推进
	if _ui.game_page:
		_ui.game_page.visible = false
	_ui._on_show_tutorial_page()


func _level0_ensure_overlay() -> void:
	if _ui.level0_overlay == null:
		_ui.level0_overlay = Control.new()
		_ui.level0_overlay.name = "Level0Overlay"
		_ui.level0_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		_ui.level0_overlay.anchor_left = 0
		_ui.level0_overlay.anchor_top = 0
		_ui.level0_overlay.anchor_right = 1
		_ui.level0_overlay.anchor_bottom = 1
		_ui._layer(1).add_child(_ui.level0_overlay)
	elif not _ui.level0_overlay.is_inside_tree():
		_ui._layer(1).add_child(_ui.level0_overlay)


# ============================================================
# 七之二、第零关：Phase 2 — 流程介绍
# ============================================================
func _level0_start_phase2() -> void:
	_ui.game_manager.set_tutorial_level0_phase(2)
	_ui.level0_flow_index = 0
	_ui.level0_flow_steps = [
		"游戏开始，每名玩家从牌堆中抽8张牌，\n你需要通过巧妙组合并预判其他玩家，尽快将所有手牌打出，最先打完所有手牌者获胜",
		"游戏中有单质、化合物与族炸这三种最基本的牌型，\n你将会在下面几个关卡了解他们的打法",
		"游玩时，你可以选择出牌或者跳过，出牌时，你应当考虑最基础的几个规则：\n越大越小、同类同出和牌权争夺。接下来就以一场对局来呈现吧",
	]
	_level0_show_flow_step(0)


func _level0_show_flow_step(idx: int) -> void:
	_ui._refresh_ui()

	if _ui.level0_overlay:
		_ui.level0_overlay.queue_free()
		_ui.level0_overlay = null

	if idx >= _ui.level0_flow_steps.size():
		_level0_start_phase3()
		return

	_ui.level0_flow_index = idx
	_level0_ensure_overlay()

	for child in _ui.level0_overlay.get_children():
		child.queue_free()

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_left = 0
	bg.anchor_top = 0
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.level0_overlay.add_child(bg)

	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0.95, 0.95, 1, 0.97)
	dialog_bg.position = Vector2(100, 250)
	dialog_bg.size = Vector2(900, 190)
	_ui.level0_overlay.add_child(dialog_bg)

	var dialog_border = _level0_make_outline_rect(Vector2(100, 250), Vector2(900, 190), Color(0.3, 0.5, 0.8, 1), 3)
	_ui.level0_overlay.add_child(dialog_border)

	var title = Label.new()
	title.text = "游戏流程介绍 %d/%d" % [idx + 1, _ui.level0_flow_steps.size()]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.position = Vector2(130, 260)
	title.size = Vector2(840, 28)
	_ui.level0_overlay.add_child(title)

	var content = Label.new()
	# autowrap 必须在 size 之前：否则 size 会被「未换行整行宽」撑大
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.text = _ui.level0_flow_steps[idx]
	content.add_theme_font_size_override("font_size", 16)
	content.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	content.position = Vector2(130, 300)
	content.size = Vector2(840, 80)
	_ui.level0_overlay.add_child(content)

	# 底部三个出口：下一步 / 跳过引导 / 返回关卡（与 Phase 1 同一套按钮与语义）
	var btn_text = "下一步 →" if idx < _ui.level0_flow_steps.size() - 1 else "开始对局！"
	var flow_btn_h := float(_ui._touch_btn_h(45))
	_ui.level0_overlay.add_child(_level0_guide_btn(
		Vector2(316, 382), Vector2(150, flow_btn_h), btn_text, _level0_flow_next_step))
	_ui.level0_overlay.add_child(_level0_guide_btn(
		Vector2(478, 382), Vector2(150, flow_btn_h), "跳过引导", _level0_skip_guide))
	_ui.level0_overlay.add_child(_level0_guide_btn(
		Vector2(640, 382), Vector2(150, flow_btn_h), "返回关卡", _level0_exit_guide))


func _level0_flow_next_step() -> void:
	_ui.level0_flow_index += 1
	_level0_show_flow_step(_ui.level0_flow_index)


# ============================================================
# 七之三、第零关：Phase 3 — 牌局
# ============================================================
func _level0_start_phase3() -> void:
	_ui.game_manager.set_tutorial_level0_phase(3)

	if _ui.level0_overlay:
		_ui.level0_overlay.queue_free()
		_ui.level0_overlay = null

	_ui.level0_ui_highlight_steps = []
	_ui.level0_flow_steps = []
	_ui._refresh_ui()

	_level0_create_rule_tips()

	var intro_tip = _level0_make_tip_box("对局开始！请尝试出牌吧。\n本关 AI 每回合只出 1 张单质，不会抢在你前面打完。", 3.0)
	_ui._layer(2).add_child(intro_tip)


func _level0_create_rule_tips() -> void:
	_level0_clear_rule_tips()
	# 与 LogLabel 同格：两者互斥显示，结构上不可能再重叠；几何统一交给 _layout_rule_tips()
	var home: Vector2 = Vector2(824, 300)
	if _ui.log_label and is_instance_valid(_ui.log_label):
		home = _ui.log_label.get_meta("home", _ui.log_label.position)
	_ui.level0_rule_tip_bg = Panel.new()
	_ui.level0_rule_tip_bg.name = "Level0RuleTipsBg"
	_ui.level0_rule_tip_bg.set_meta("home", home)
	_ui.level0_rule_tip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.level0_rule_tip_bg.add_theme_stylebox_override("panel", _ui._make_panel_style("toast_info"))
	_ui._layer(0).add_child(_ui.level0_rule_tip_bg)

	# 标题条：和日志同一套可折叠交互（默认展开，点一下收成 26px 一行）
	_ui._rule_tip_title = _ui._make_right_column_title("Level0RuleTipsTitle", "规则提醒")
	_ui._rule_tip_title.pressed.connect(_ui._on_rule_tip_title_pressed)
	_ui.level0_rule_tip_bg.add_child(_ui._rule_tip_title)

	_ui.level0_rule_tip_label = Label.new()
	_ui.level0_rule_tip_label.name = "Level0RuleTips"
	_ui.level0_rule_tip_label.add_theme_font_size_override("font_size", 13)
	_ui.level0_rule_tip_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	_ui.level0_rule_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui.level0_rule_tip_label.text = ""
	_ui._layer(0).add_child(_ui.level0_rule_tip_label)
	_level0_update_rule_tips()
	_layout_rule_tips()



# -------- 搬运自 scripts/GameUI.gd 第 1489-1612 行 --------
func _on_rule_tip_title_pressed() -> void:
	_ui._rule_tip_collapsed = not _ui._rule_tip_collapsed
	_layout_rule_tips()


# 规则提醒几何：与日志同一条公式（标题 26 + 间距 6 + 正文），正文高度用 Label 实测最小高度
func _layout_rule_tips() -> void:
	if _ui.level0_rule_tip_bg == null or not is_instance_valid(_ui.level0_rule_tip_bg):
		return
	if _ui.level0_rule_tip_label == null or not is_instance_valid(_ui.level0_rule_tip_label):
		return
	var home: Vector2 = _ui.level0_rule_tip_bg.get_meta("home", Vector2(824, 300))
	var panel_w: float = _ui.LOG_W + _ui.LOG_PANEL_PAD
	var body_w: float = panel_w - _ui.LOG_TEXT_PAD - _ui.LOG_PANEL_PAD
	# 先定宽再量高：autowrap 的 Label 只有在宽度确定后才能算出换行后的真实高度
	_ui.level0_rule_tip_label.size = Vector2(body_w, _ui.LOG_CONTENT_MAX_H)
	var body_h: float = _ui.LOG_CONTENT_MIN_H
	if not _ui._rule_tip_collapsed:
		body_h = clampf(_ui.level0_rule_tip_label.get_minimum_size().y, _ui.LOG_CONTENT_MIN_H, _ui.LOG_CONTENT_MAX_H)
	var panel_h: float = _ui.LOG_PANEL_PAD + _ui.LOG_TITLE_H + _ui.LOG_PANEL_PAD
	if not _ui._rule_tip_collapsed:
		panel_h += _ui.LOG_BODY_GAP + body_h
	_ui.level0_rule_tip_bg.position = home
	_ui.level0_rule_tip_bg.size = Vector2(panel_w, panel_h)
	if _ui._rule_tip_title and is_instance_valid(_ui._rule_tip_title):
		_ui._rule_tip_title.position = Vector2(0, _ui.LOG_PANEL_PAD)
		_ui._rule_tip_title.size = Vector2(panel_w, _ui.LOG_TITLE_H)
		_ui._rule_tip_title.text = "规则提醒 %s" % ("▸" if _ui._rule_tip_collapsed else "▾")
	_ui.level0_rule_tip_label.position = Vector2(home.x + _ui.LOG_TEXT_PAD, home.y + _ui.LOG_TITLE_H + _ui.LOG_BODY_GAP)
	_ui.level0_rule_tip_label.size = Vector2(body_w, body_h)
	_ui.level0_rule_tip_label.visible = not _ui._rule_tip_collapsed and _ui.level0_rule_tip_bg.visible


# 彻底清掉第零关规则提醒（跨局 / 退出教学时必须调）：
# 它挂在 ContentLayer 上，不随 GamePage 隐藏或 GameManager 重建而消失
func _level0_clear_rule_tips() -> void:
	if _ui.level0_rule_tip_label and is_instance_valid(_ui.level0_rule_tip_label):
		_ui.level0_rule_tip_label.queue_free()
	_ui.level0_rule_tip_label = null
	if _ui._rule_tip_title and is_instance_valid(_ui._rule_tip_title):
		_ui._rule_tip_title.queue_free()
	_ui._rule_tip_title = null
	if _ui.level0_rule_tip_bg and is_instance_valid(_ui.level0_rule_tip_bg):
		_ui.level0_rule_tip_bg.queue_free()
	_ui.level0_rule_tip_bg = null
	if _ui.log_label and is_instance_valid(_ui.log_label):
		_ui._set_log_visible(true)


# 规则提醒 / 日志共用右栏同一格：互斥可见，永远不可能叠在一起
func _level0_set_rule_tips_visible(on: bool) -> void:
	if _ui.level0_rule_tip_bg and is_instance_valid(_ui.level0_rule_tip_bg):
		_ui.level0_rule_tip_bg.visible = on
	if _ui.level0_rule_tip_label and is_instance_valid(_ui.level0_rule_tip_label):
		_ui.level0_rule_tip_label.visible = on and not _ui._rule_tip_collapsed
	if _ui.log_label and is_instance_valid(_ui.log_label):
		_ui._set_log_visible(not on)


func _level0_update_rule_tips() -> void:
	if _ui.game_manager == null:
		return
	# 只有「第零关 · 牌局练习」这一段显示规则提醒；其余局面一律隐藏并让日志回到原位
	var in_level0_play: bool = _ui.game_manager.tutorial_level == 0 \
			and _ui.game_manager.tutorial_level0_phase == 3
	if not in_level0_play:
		if _ui.level0_rule_tip_label and is_instance_valid(_ui.level0_rule_tip_label):
			_ui.level0_rule_tip_label.text = ""
		_level0_set_rule_tips_visible(false)
		return
	if _ui.level0_rule_tip_label == null or not is_instance_valid(_ui.level0_rule_tip_label):
		return
	_level0_set_rule_tips_visible(true)
	_ui.level0_rule_tip_label.text = _level0_rule_tips_text()
	_layout_rule_tips()


# 第零关只教「越大越小 / 同类同出」：族炸是本关不引导的内容，规则层仍允许手打，
# 只有玩家自己真的打出族炸时，才补一条「牌权争夺」说明（避免默认就把新手带偏）
func _level0_rule_tips_text() -> String:
	var tip: String = _ui.game_manager.level0_rule_tip
	# 面板已经有「规则提醒」标题条，正文直接进规则条目，不再重复一行标题
	var rules_info = ""
	if tip == "越大越小":
		rules_info += "● 越大越小\n原子序数和越小牌越大\n同牌型必须出更大的牌才能接上\n\n"
		rules_info += "  同类同出\n桌面单质→只能接单质\n桌面化合物→只能接化合物\n"
	elif tip == "同类同出":
		rules_info += "  越大越小\n原子序数和越小牌越大\n\n"
		rules_info += "● 同类同出\n桌面单质→只能接单质\n桌面化合物→只能接化合物\n牌型必须匹配\n"
	else:
		rules_info += "  越大越小\n原子序数和越小牌越大\n\n"
		rules_info += "  同类同出\n同类牌型才能接牌\n"
	if tip == "牌权争夺":
		rules_info += "\n● 牌权争夺\n你打出了族炸！\n族炸可超越牌型限制\n但要注意冷却❄"
	return rules_info


func _level0_make_tip_box(text: String, duration: float) -> Control:
	var box = Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = Panel.new()
	bg.position = Vector2(200, 350)
	bg.size = Vector2(700, 70)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", _ui._make_panel_style("toast_info"))
	box.add_child(bg)

	var lbl = Label.new()
	# autowrap 必须在 size 之前，否则中文字符串会把 Label 撑出背景板
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	lbl.position = Vector2(220, 355)
	lbl.size = Vector2(660, 60)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)

	var timer = _ui.get_tree().create_timer(duration)
	timer.timeout.connect(box.queue_free)

	return box
