# ============================================================
# GameUI.gd - 游戏主界面控制脚本
# 页面管理 / 牌面渲染 / 出牌步骤流 / AI策略 / 着色 / 教程
# ============================================================

extends Control

const GameManagerScript = preload("res://scripts/GameManager.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

# ============================================================
# 一、页面引用
# ============================================================
var game_manager: RefCounted = null
var start_page: Control = null
var game_page: Control = null
var end_page: Control = null
var help_page_rules: Control = null
var help_page_cards: Control = null
var start_button: Button = null
var end_label: Label = null
var end_button: Button = null
var help_rules_back_btn: Button = null
var help_rules_to_cards_btn: Button = null
var help_cards_back_btn: Button = null
var help_cards_to_rules_btn: Button = null
var help_btn: Button = null
var player_spin: SpinBox = null
var ai_spin: SpinBox = null

# ============================================================
# 二、UI 控件引用
# ============================================================
var hand_container: Control = null      # 手牌区 (HFlowContainer)
var info_label: Label = null            # 牌权状态
var deck_count_label: Label = null      # 牌库计数
var table_label: Label = null           # 桌面信息
var log_label: Label = null             # 游戏日志
var card_info_label: Label = null       # 可出牌型提示
var action_panel: Control = null        # 操作按钮区
var hint_button: Button = null          # 显示提示
var quit_button: Button = null          # 退出游戏
var tutorial_label: Label = null        # 教程引导文本

# ============================================================
# 三、游戏状态
# ============================================================
var selected_indices: Array = []        # 选中的手牌索引
var step_mode: int = 0                  # 0=选牌 1=牌型 2=化合价 3=弃牌
var compound_selections: Array = []     # 化合价选择 [{symbol, valence}]
var hand_buttons: Array = []            # 手牌按钮列表
var log_lines: Array = []               # 日志行缓存
const MAX_LOG_LINES = 6
var ai_triggered: bool = false          # AI 自动操作防重复

# ============================================================
# 第零关覆盖层 (Phase 1: UI介绍, Phase 2: 流程说明)
# ============================================================
var level0_overlay: Control = null
var level0_active: bool = false
var level0_step: int = 0                # 覆盖层内步骤
var level0_ui_highlight_steps: Array = []  # UI 介绍步骤数据
var level0_flow_steps: Array = []       # 流程介绍步骤数据
var level0_flow_index: int = 0          # 流程介绍当前索引


# ============================================================
# 四、初始化
# ============================================================
func _ready() -> void:
	_setup_pages()
	_show_start_page()


# -------- 绑定所有页面和按钮引用 --------
func _setup_pages() -> void:
	start_page = get_node_or_null("StartPage")
	game_page = get_node_or_null("GamePage")
	end_page = get_node_or_null("EndPage")
	help_page_rules = get_node_or_null("HelpPage_Rules")
	help_page_cards = get_node_or_null("HelpPage_Cards")

	if start_page:
		start_button = start_page.get_node_or_null("StartButton")
		player_spin = start_page.get_node_or_null("PlayerCountSpin")
		var tut_btn = start_page.get_node_or_null("TutorialBtn")
		if tut_btn:
			tut_btn.pressed.connect(_on_show_tutorial_page)
		ai_spin = start_page.get_node_or_null("AiCountSpin")
		if start_button:
			start_button.pressed.connect(_on_start_game)
		var exit_btn = start_page.get_node_or_null("ExitButton")
		if exit_btn:
			exit_btn.pressed.connect(_on_exit_program)

	# 教学引导页按钮绑定
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page:
		var tut0 = tut_page.get_node_or_null("Tutorial0Btn")
		var tut1 = tut_page.get_node_or_null("Tutorial1Btn")
		var tut2 = tut_page.get_node_or_null("Tutorial2Btn")
		var tut_back = tut_page.get_node_or_null("TutorialBackBtn")
		if tut0: tut0.pressed.connect(_on_start_tutorial.bind(0))
		if tut1: tut1.pressed.connect(_on_start_tutorial.bind(1))
		if tut2: tut2.pressed.connect(_on_start_tutorial.bind(2))
		if tut_back: tut_back.pressed.connect(_on_tutorial_back)

	if end_page:
		end_label = end_page.get_node_or_null("EndLabel")
		end_button = end_page.get_node_or_null("EndButton")
		if end_button:
			end_button.pressed.connect(_show_start_page)

	if help_page_rules:
		help_rules_back_btn = help_page_rules.get_node_or_null("HelpRulesBackBtn")
		help_rules_to_cards_btn = help_page_rules.get_node_or_null("HelpRulesToCardsBtn")
		if help_rules_back_btn:
			help_rules_back_btn.pressed.connect(_on_help_back)
		if help_rules_to_cards_btn:
			help_rules_to_cards_btn.pressed.connect(_on_help_show_cards)

	if help_page_cards:
		help_cards_back_btn = help_page_cards.get_node_or_null("HelpCardsBackBtn")
		help_cards_to_rules_btn = help_page_cards.get_node_or_null("HelpCardsToRulesBtn")
		if help_cards_back_btn:
			help_cards_back_btn.pressed.connect(_on_help_back)
		if help_cards_to_rules_btn:
			help_cards_to_rules_btn.pressed.connect(_on_help_show_rules)

	if game_page:
		hand_container = game_page.get_node_or_null("HandContainer")
		info_label = game_page.get_node_or_null("InfoLabel")
		table_label = game_page.get_node_or_null("TableLabel")
		log_label = game_page.get_node_or_null("LogLabel")
		card_info_label = game_page.get_node_or_null("CardInfoLabel")
		action_panel = game_page.get_node_or_null("ActionPanel")
		hint_button = game_page.get_node_or_null("HintButton")
		quit_button = game_page.get_node_or_null("QuitButton")
		help_btn = game_page.get_node_or_null("HelpBtn")
		tutorial_label = game_page.get_node_or_null("TutorialLabel")
		deck_count_label = game_page.get_node_or_null("DeckCountLabel")
		if hint_button:
			hint_button.toggled.connect(_on_hint_toggled)
		if quit_button:
			quit_button.pressed.connect(_on_quit_game)
		if help_btn:
			help_btn.pressed.connect(_on_show_help)


# ============================================================
# 五、页面切换
# ============================================================
func _show_start_page() -> void:
	if start_page: start_page.visible = true
	if game_page: game_page.visible = false
	if end_page: end_page.visible = false
	var tut_page = get_node_or_null("TutorialPage")
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	if tut_page: tut_page.visible = false

func _on_show_help() -> void:
	if help_page_rules: help_page_rules.visible = true
	if game_page: game_page.visible = false

func _on_show_tutorial_page() -> void:
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = true
	if start_page: start_page.visible = false

func _on_tutorial_back() -> void:
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	if start_page: start_page.visible = true

func _on_help_back() -> void:
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	if game_page: game_page.visible = true

func _on_help_show_cards() -> void:
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = true

func _on_help_show_rules() -> void:
	if help_page_cards: help_page_cards.visible = false
	if help_page_rules: help_page_rules.visible = true


# ============================================================
# 六、游戏启动
# ============================================================
func _on_start_game() -> void:
	var total = int(player_spin.value) if player_spin else 4
	var ai = int(ai_spin.value) if ai_spin else 3
	if total < GameManagerScript.MIN_PLAYERS or total > GameManagerScript.MAX_PLAYERS:
		total = 4
	if ai >= total:
		_show_info_simple("AI 人数不能等于或超过总玩家人数！请重新设置。")
		return
	start_page.visible = false
	game_page.visible = true
	end_page.visible = false
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	_init_game(total, ai)


func _on_start_tutorial(level: int) -> void:
	game_manager = GameManagerScript.new()
	var ok = game_manager.init_tutorial(level)
	if not ok:
		_show_info_simple("教程初始化失败！")
		return
	start_page.visible = false
	game_page.visible = true
	end_page.visible = false
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	_step_reset()

	if level == 0:
		# 第零关：先走 Phase 1 (UI 介绍)
		_level0_start_phase1()
	else:
		_refresh_ui()


func _connect_node(btn, cb: Callable) -> void:
	if btn: btn.pressed.connect(cb)


# ============================================================
# 七、系统操作
# ============================================================
func _on_exit_program() -> void:
	get_tree().quit()

func _on_quit_game() -> void:
	if game_manager: game_manager.phase = 2
	_show_end_page("游戏已退出")

func _show_info_simple(text: String) -> void:
	if info_label: info_label.text = text
	else: push_warning(text)

func _init_game(total: int = 4, ai: int = 3) -> void:
	game_manager = GameManagerScript.new()
	var ok = game_manager.init_game(total, ai)
	if not ok:
		push_error("init_game failed with total=%d ai=%d, retrying defaults" % [total, ai])
		ok = game_manager.init_game(4, 3)
		if not ok:
			push_error("CRITICAL: init_game also failed with defaults!")
			_show_end_page("初始化失败")
			return
	_step_reset()
	_refresh_ui()


# ============================================================
# 七之一、第零关：Phase 1 — UI 标注介绍
# ============================================================
func _level0_start_phase1() -> void:
	game_manager.tutorial_level0_phase = 1
	level0_active = true
	level0_step = 0

	# 构建 UI 标注步骤（按顺序：玩家顺序/手牌数 → 桌面牌 → 手牌区 → 出牌区 → 其他细节）
	level0_ui_highlight_steps = [
		{
			"title": "玩家顺序和手牌数",
			"desc": "这是【玩家顺序和手牌数】\n显示每位玩家的名字、AI标签、手牌张数，以及当前轮到谁（◄标记）",
			"target": "info_label",
			"pos": Vector2(20, 50),
			"size": Vector2(460, 90),
		},
		{
			"title": "桌面的牌",
			"desc": "这是【桌面的牌】\n显示当前桌面上的牌是谁打出的、牌型是什么、有无特殊状态（如免疫、接炸中）",
			"target": "table_label",
			"pos": Vector2(20, 150),
			"size": Vector2(600, 50),
		},
		{
			"title": "手牌区",
			"desc": "这是【手牌区】\n你的手牌在这里显示，每张牌为95×118px的原子牌面，点击可选中（黄色高亮）",
			"target": "hand_container",
			"pos": Vector2(20, 237),
			"size": Vector2(900, 373),
		},
		{
			"title": "出牌区",
			"desc": "这是【出牌区】\n选中手牌后在此选择牌型：单质/化合物/族炸，也可跳过或查看提示",
			"target": "action_panel",
			"pos": Vector2(8, 599),
			"size": Vector2(460, 45),
		},
		{
			"title": "其他细节（右面板）",
			"desc": "这是【其他细节-右面板】\n包括游戏日志、牌库剩余数、手牌上限和教程引导文本，帮助你了解当前对局动态",
			"target": "log_label",
			"pos": Vector2(750, 10),
			"size": Vector2(400, 350),
		},
		{
			"title": "其他细节（按钮区）",
			"desc": "这是【其他细节-按钮区】\n包括显示提示按钮、帮助按钮（查看规则）、退出游戏按钮",
			"target": "quit_button",
			"pos": Vector2(420, 565),
			"size": Vector2(355, 38),
		},
	]
	_level0_show_ui_step(0)


# -------- 显示 UI 标注步骤 --------
func _level0_show_ui_step(idx: int) -> void:
	# 先刷新基础 UI
	_refresh_ui()

	if idx >= level0_ui_highlight_steps.size():
		# Phase 1 结束，进入 Phase 2
		_level0_start_phase2()
		return

	var step_data = level0_ui_highlight_steps[idx]
	level0_step = idx

	# 创建覆盖层
	_level0_ensure_overlay()

	# 清空覆盖层
	for child in level0_overlay.get_children():
		child.queue_free()

	# 半透明遮罩（除高亮区外）- 使用 anchors 覆盖全屏
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_left = 0
	bg.anchor_top = 0
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	level0_overlay.add_child(bg)

	# 高亮矩形（"挖洞"效果通过绘制透明矩形边框实现）
	var hl_border = ColorRect.new()
	hl_border.color = Color(1, 1, 0, 0)
	hl_border.position = step_data.pos
	hl_border.size = step_data.size
	hl_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level0_overlay.add_child(hl_border)

	# 高亮方框（黄色粗边框）
	var hl_outline = _level0_make_outline_rect(step_data.pos, step_data.size, Color(1, 0.85, 0, 1), 4)
	level0_overlay.add_child(hl_outline)

	# 文本提示框（560x270，根据高亮位置自适应避免遮挡）
	var tbx = 20
	var tby = 350
	var tbw = 560
	var tbh = 270
	# 检查高亮区域是否与提示框重叠，若重叠则移动提示框
	var hl_bottom = step_data.pos.y + step_data.size.y
	if hl_bottom > tby + 40 or (step_data.pos.x < tbx + tbw and step_data.pos.x + step_data.size.x > tbx):
		if step_data.pos.x > 600:
			# 高亮在右侧，提示框移到左侧
			tbx = 20
		elif step_data.pos.y > 450:
			# 高亮在底部，提示框移到上方
			tby = 50
		else:
			# 高亮在中间（如手牌区），提示框移到右侧
			tbx = 620
			tby = 50
	var tip_bg = ColorRect.new()
	tip_bg.color = Color(1, 1, 0.85, 0.95)
	tip_bg.position = Vector2(tbx, tby)
	tip_bg.size = Vector2(tbw, tbh)
	level0_overlay.add_child(tip_bg)

	var tip_border = _level0_make_outline_rect(Vector2(tbx, tby), Vector2(tbw, tbh), Color(1, 0.6, 0, 1), 3)
	level0_overlay.add_child(tip_border)

	var tip_title = Label.new()
	tip_title.text = step_data.title
	tip_title.add_theme_font_size_override("font_size", 18)
	tip_title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	tip_title.position = Vector2(tbx + 24, tby + 14)
	tip_title.size = Vector2(tbw - 48, 24)
	level0_overlay.add_child(tip_title)

	var tip_desc = Label.new()
	tip_desc.text = step_data.desc
	tip_desc.add_theme_font_size_override("font_size", 14)
	tip_desc.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	tip_desc.position = Vector2(tbx + 24, tby + 44)
	tip_desc.size = Vector2(tbw - 48, 150)
	tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level0_overlay.add_child(tip_desc)

	# 步骤指示器
	var step_indicator = Label.new()
	step_indicator.text = "%d / %d" % [idx + 1, level0_ui_highlight_steps.size()]
	step_indicator.add_theme_font_size_override("font_size", 13)
	step_indicator.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	step_indicator.position = Vector2(tbx + tbw - 100, tby + tbh - 26)
	step_indicator.size = Vector2(80, 20)
	level0_overlay.add_child(step_indicator)

	# "下一步"按钮
	var next_btn = Button.new()
	next_btn.text = "下一步 →" if idx < level0_ui_highlight_steps.size() - 1 else "继续 →"
	next_btn.custom_minimum_size = Vector2(150, 42)
	next_btn.add_theme_font_size_override("font_size", 16)
	next_btn.position = Vector2(tbx + 24, tby + tbh - 56)
	next_btn.size = Vector2(150, 42)
	next_btn.pressed.connect(_level0_ui_next_step)
	level0_overlay.add_child(next_btn)


func _level0_make_outline_rect(pos: Vector2, size: Vector2, color: Color, width: int) -> Control:
	var c = Control.new()
	c.position = pos
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 上边
	var top = ColorRect.new()
	top.color = color
	top.position = Vector2(0, 0)
	top.size = Vector2(size.x, width)
	c.add_child(top)
	# 下边
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.position = Vector2(0, size.y - width)
	bottom.size = Vector2(size.x, width)
	c.add_child(bottom)
	# 左边
	var left = ColorRect.new()
	left.color = color
	left.position = Vector2(0, 0)
	left.size = Vector2(width, size.y)
	c.add_child(left)
	# 右边
	var right = ColorRect.new()
	right.color = color
	right.position = Vector2(size.x - width, 0)
	right.size = Vector2(width, size.y)
	c.add_child(right)
	return c


func _level0_ui_next_step() -> void:
	level0_step += 1
	_level0_show_ui_step(level0_step)


func _level0_ensure_overlay() -> void:
	if level0_overlay == null:
		level0_overlay = Control.new()
		level0_overlay.name = "Level0Overlay"
		level0_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		level0_overlay.anchor_left = 0
		level0_overlay.anchor_top = 0
		level0_overlay.anchor_right = 1
		level0_overlay.anchor_bottom = 1
		game_page.add_child(level0_overlay)
	elif not level0_overlay.is_inside_tree():
		game_page.add_child(level0_overlay)


# ============================================================
# 七之二、第零关：Phase 2 — 流程介绍
# ============================================================
func _level0_start_phase2() -> void:
	game_manager.tutorial_level0_phase = 2
	level0_flow_index = 0
	level0_flow_steps = [
		"游戏开始，每名玩家从牌堆中抽8张牌，\n你需要通过巧妙组合并预判其他玩家，尽快将所有手牌打出，最先打完所有手牌者获胜",
		"游戏中有单质、化合物与族炸这三种最基本的牌型，\n你将会在下面几个关卡了解他们的打法",
		"游玩时，你可以选择出牌或者跳过，出牌时，你应当考虑最基础的几个规则：\n越大越小、同类同出和牌权争夺。接下来就以一场对局来呈现吧",
	]
	_level0_show_flow_step(0)


func _level0_show_flow_step(idx: int) -> void:
	# 刷新基础UI
	_refresh_ui()

	# 清除旧覆盖层
	if level0_overlay:
		level0_overlay.queue_free()
		level0_overlay = null

	if idx >= level0_flow_steps.size():
		# 流程介绍结束，进入牌局 Phase 3
		_level0_start_phase3()
		return

	level0_flow_index = idx
	_level0_ensure_overlay()

	# 清除旧内容
	for child in level0_overlay.get_children():
		child.queue_free()

	# 半透明背景 - 使用 anchors 覆盖全屏
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_left = 0
	bg.anchor_top = 0
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	level0_overlay.add_child(bg)

	# 对话框
	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0.95, 0.95, 1, 0.97)
	dialog_bg.position = Vector2(100, 250)
	dialog_bg.size = Vector2(900, 180)
	level0_overlay.add_child(dialog_bg)

	var dialog_border = _level0_make_outline_rect(Vector2(100, 250), Vector2(900, 180), Color(0.3, 0.5, 0.8, 1), 3)
	level0_overlay.add_child(dialog_border)

	# 标题
	var title = Label.new()
	title.text = "游戏流程介绍 %d/3" % (idx + 1)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.position = Vector2(130, 260)
	title.size = Vector2(840, 28)
	level0_overlay.add_child(title)

	# 内容
	var content = Label.new()
	content.text = level0_flow_steps[idx]
	content.add_theme_font_size_override("font_size", 16)
	content.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	content.position = Vector2(130, 300)
	content.size = Vector2(840, 80)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level0_overlay.add_child(content)

	# 按钮
	var btn_text = "下一步 →" if idx < level0_flow_steps.size() - 1 else "开始对局！"
	var next_btn = Button.new()
	next_btn.text = btn_text
	next_btn.custom_minimum_size = Vector2(180, 45)
	next_btn.add_theme_font_size_override("font_size", 18)
	next_btn.position = Vector2(450, 370)
	next_btn.size = Vector2(180, 45)
	next_btn.pressed.connect(_level0_flow_next_step)
	level0_overlay.add_child(next_btn)


func _level0_flow_next_step() -> void:
	level0_flow_index += 1
	_level0_show_flow_step(level0_flow_index)


# ============================================================
# 七之三、第零关：Phase 3 — 牌局
# ============================================================
func _level0_start_phase3() -> void:
	game_manager.tutorial_level0_phase = 3

	# 清除覆盖层
	if level0_overlay:
		level0_overlay.queue_free()
		level0_overlay = null

	level0_active = false
	_refresh_ui()

	# 创建持久规则提示标签
	_level0_create_rule_tips()

	# 显示牌局开场提示
	var intro_tip = _level0_make_tip_box("对局开始！请尝试出牌吧。\nAI默认只出单质和化合物。", 3.0)
	game_page.add_child(intro_tip)


# -------- 第零关规则提示标签（右上角持久显示） --------
var level0_rule_tip_label: Label = null

func _level0_create_rule_tips() -> void:
	if level0_rule_tip_label:
		level0_rule_tip_label.queue_free()
	level0_rule_tip_label = Label.new()
	level0_rule_tip_label.name = "Level0RuleTips"
	level0_rule_tip_label.position = Vector2(950, 370)
	level0_rule_tip_label.size = Vector2(220, 220)
	level0_rule_tip_label.add_theme_font_size_override("font_size", 13)
	level0_rule_tip_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	level0_rule_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level0_rule_tip_label.text = ""
	game_page.add_child(level0_rule_tip_label)
	_level0_update_rule_tips()


func _level0_update_rule_tips() -> void:
	if not level0_rule_tip_label or not game_manager or game_manager.tutorial_level0_phase != 3:
		return

	# 根据玩家操作状态高亮对应规则
	var rules_info = "── 规则提醒 ──\n\n"
	var tip = game_manager.level0_rule_tip

	if tip == "越大越小":
		rules_info += "● 越大越小\n原子序数和越小牌越大\n同牌型必须出更大的牌才能接上\n\n"
		rules_info += "  同类同出\n桌面单质→只能接单质\n桌面化合物→只能接化合物\n\n"
		rules_info += "  牌权争夺\n打出族炸可抢牌权\n超越牌型限制"
	elif tip == "同类同出":
		rules_info += "  越大越小\n原子序数和越小牌越大\n\n"
		rules_info += "● 同类同出\n桌面单质→只能接单质\n桌面化合物→只能接化合物\n牌型必须匹配\n\n"
		rules_info += "  牌权争夺\n打出族炸可抢牌权\n超越牌型限制"
	elif tip == "牌权争夺":
		rules_info += "  越大越小\n原子序数和越小牌越大\n\n"
		rules_info += "  同类同出\n桌面单质→只能接单质\n桌面化合物→只能接化合物\n\n"
		rules_info += "● 牌权争夺\n你打出了族炸！\n族炸可超越牌型限制\n但要注意冷却❄"
	else:
		rules_info += "  越大越小\n原子序数和越小牌越大\n\n"
		rules_info += "  同类同出\n同类牌型才能接牌\n\n"
		rules_info += "  牌权争夺\n族炸可超越牌型限制"

	level0_rule_tip_label.text = rules_info


# -------- 临时提示方框 (自动消失) --------
func _level0_make_tip_box(text: String, duration: float = 2.5) -> Control:
	var box = Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.color = Color(1, 1, 0.85, 0.95)
	bg.position = Vector2(200, 350)
	bg.size = Vector2(700, 70)
	box.add_child(bg)

	var border = _level0_make_outline_rect(Vector2(200, 350), Vector2(700, 70), Color(1, 0.6, 0, 1), 3)
	box.add_child(border)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	lbl.position = Vector2(220, 355)
	lbl.size = Vector2(660, 60)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)

	# 自动消失
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(box.queue_free)

	return box


# ============================================================
# 八、UI 刷新（核心渲染循环）
# ============================================================
func _refresh_ui() -> void:
	if game_manager == null or game_manager.is_game_over():
		_show_end_page("")
		return
	_update_info_label()
	_update_table_label()
	_update_log_label()
	_update_action_panel()
	_update_hand_buttons()
	_update_card_info_label()
	_update_deck_count()
	_update_tutorial_label()
	_level0_update_rule_tips()


# -------- 牌权状态显示（含手牌数） --------
func _update_info_label() -> void:
	if info_label and game_manager:
		info_label.text = _format_player_status()

func _format_player_status() -> String:
	if game_manager == null or game_manager.players.is_empty():
		return "等待游戏初始化..."
	var parts: Array = []
	var cp_idx = game_manager.get_current_player_index()
	for i in range(game_manager.players.size()):
		var p = game_manager.players[i]
		var is_current = (i == cp_idx)
		var ai_tag = "(AI)" if p.is_ai else ""
		var cooling = "❄" if p.clan_bomb_cooling else ""
		var pass_tag = "⏸" if p.has_passed else ""
		var highlight = " ◄" if is_current else ""
		var label = "%s %s%s%s%s" % [p.player_name, ai_tag, cooling, pass_tag, highlight]
		parts.append(label)
	if parts.is_empty(): return "等待游戏初始化..."
	var result = "● %s" % parts[0]
	for j in range(1, parts.size()):
		result += " → ● %s" % parts[j]
	var counts: Array = []
	for i in range(game_manager.players.size()):
		counts.append("%s: %d张" % [game_manager.players[i].player_name, game_manager.players[i].get_hand_count()])
	result += "\n手牌: " + " | ".join(counts)
	return result


var table_card_buttons: Array = []  # 桌面区迷你卡牌按钮

# -------- 桌面信息显示（含迷你卡牌） --------
func _update_table_label() -> void:
	if not table_label or not game_manager: return

	# 清除旧桌面迷你卡牌
	for btn in table_card_buttons:
		if is_instance_valid(btn): btn.queue_free()
	table_card_buttons.clear()

	if game_manager.table_player_index >= 0:
		var p = game_manager.players[game_manager.table_player_index]
		var cards = game_manager.table_cards
		var pat = UtilsScript.detect_pattern(cards)
		var pn = UtilsScript.get_pattern_name(pat)
		var en = UtilsScript.get_element_display(cards)
		var syms: Array = []
		for c in cards: syms.append(c.symbol)
		var txt = "桌面: %s 打出 %s" % [p.player_name, pn]
		if en != "": txt += " " + en
		if game_manager.compound_immune: txt += " [免疫]"
		if game_manager.clan_bomb_chain_active: txt += " ⚠接炸中"
		table_label.text = txt

		# 渲染桌面迷你卡牌 (72×90px，比手牌略小)
		# 位于桌面右侧、手牌区上方，避免与手牌重叠
		for i in range(cards.size()):
			var mini = _build_mini_card_button(cards[i])
			mini.position = Vector2(500 + i * 80, 105)
			game_page.add_child(mini)
			table_card_buttons.append(mini)
	else:
		table_label.text = "桌面: 空"


# -------- 构建桌面迷你卡牌 (72×90px) --------
func _build_mini_card_button(card) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(72, 90)
	btn.tooltip_text = card.get_full_info()

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.97, 0.97, 0.98, 1.0)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.7, 0.7, 0.75, 1.0)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.9, 0.93, 0.98, 1.0)
	style_hover.border_color = Color(0.3, 0.5, 0.8, 1.0)
	btn.add_theme_stylebox_override("hover", style_hover)

	# 原子序数 (左上，8px)
	var l_num = Label.new()
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", 8)
	l_num.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	l_num.position = Vector2(3, 1)
	btn.add_child(l_num)

	# 族 (右上，7px)
	var l_group = Label.new()
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", 7)
	l_group.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(32, 10)
	l_group.position = Vector2(37, 2)
	btn.add_child(l_group)

	# 符号 (中上，15px着色)
	var l_sym = Label.new()
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", 15)
	l_sym.add_theme_color_override("font_color", _get_card_color(card))
	l_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sym.size = Vector2(65, 18)
	l_sym.position = Vector2(4, 18)
	btn.add_child(l_sym)

	# 中文名 (中，9px)
	var l_name = Label.new()
	l_name.text = card.name_cn
	l_name.add_theme_font_size_override("font_size", 9)
	l_name.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1))
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_name.size = Vector2(65, 12)
	l_name.position = Vector2(4, 38)
	btn.add_child(l_name)

	# 化合价 (中下，8px)
	var val_str = ""
	for v in card.common_valence:
		if val_str != "": val_str += " "
		if v > 0: val_str += "+%d" % v
		else: val_str += "%d" % v
	var l_val = Label.new()
	l_val.text = val_str
	l_val.add_theme_font_size_override("font_size", 8)
	l_val.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2, 1))
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_val.size = Vector2(65, 10)
	l_val.position = Vector2(4, 52)
	btn.add_child(l_val)

	# 相对原子质量 (左下，7px)
	var l_mass = Label.new()
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", 7)
	l_mass.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	l_mass.position = Vector2(2, 78)
	btn.add_child(l_mass)

	return btn


# -------- 游戏日志 --------
func _update_log_label() -> void:
	if not log_label or not game_manager: return
	var new_logs = game_manager.flush_logs()
	if new_logs.is_empty(): return
	for msg in new_logs:
		log_lines.push_back(msg)
		while log_lines.size() > MAX_LOG_LINES:
			log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


# -------- 可出牌型提示 --------
func _update_card_info_label() -> void:
	if not card_info_label or not game_manager: return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		card_info_label.text = ""
		return
	var hint = game_manager.get_available_patterns(game_manager.get_current_player_index())
	card_info_label.text = "提示: " + hint


# -------- 牌库计数 + 手牌上限 --------
func _update_deck_count() -> void:
	if not deck_count_label or not game_manager: return
	var db = game_manager.database
	if db: deck_count_label.text = "牌库剩余: %d张" % db.get_remaining_count()
	else: deck_count_label.text = "牌库剩余: —"
	if game_manager:
		var hand_limit = min(game_manager.players.size() * 4, 18)
		deck_count_label.text += "  手牌上限: %d张" % hand_limit


# -------- 教程引导文本 --------
func _update_tutorial_label() -> void:
	if not tutorial_label or not game_manager: return
	if game_manager.tutorial_level > 0 or game_manager.tutorial_level0_phase >= 3:
		tutorial_label.visible = true
		if game_manager.tutorial_level == 0 and game_manager.tutorial_level0_phase == 3:
			tutorial_label.text = "【第零关】牌局练习 - 试试出牌！"
		else:
			var display = game_manager.get_tutorial_display()
			if game_manager.tutorial_success != "":
				game_manager.tutorial_success = ""
			tutorial_label.text = display
	else:
		tutorial_label.visible = false


# ============================================================
# 九、操作面板（出牌步骤流）
# ============================================================
func _update_action_panel() -> void:
	if not action_panel or not game_manager: return
	for child in action_panel.get_children():
		child.queue_free()
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai or game_manager.is_game_over(): return

	if step_mode == 0:
		# Step0: 选牌阶段 → 出牌/跳过
		action_panel.add_child(_mkb("出牌(选牌型)", _on_step_next, selected_indices.is_empty()))
		var hand_limit = min(game_manager.players.size() * 4, 18)
		if cp.get_hand_count() >= hand_limit:
			action_panel.add_child(_mkb("弃牌跳过(上限)", _on_pass, false))
		else:
			action_panel.add_child(_mkb("跳过", _on_pass, false))
	elif step_mode == 1:
		# Step1: 选牌型 → 单质/化合物/族炸/返回 (接炸中只显示族炸)
		if game_manager.clan_bomb_chain_active and game_manager.get_current_player_index() != game_manager.clan_bomb_owner:
			action_panel.add_child(_mkb("作为族炸打出", _on_clan_bomb, false))
			action_panel.add_child(_mkb("返回", _on_back, false))
		else:
			action_panel.add_child(_mkb("作为单质打出", _on_element, false))
			action_panel.add_child(_mkb("合成化合物", _on_choose_compound, false))
			action_panel.add_child(_mkb("作为族炸打出", _on_clan_bomb, false))
			action_panel.add_child(_mkb("返回", _on_back, false))
	elif step_mode == 2:
		# Step2: 化合价选择
		_update_valence_buttons()
	elif step_mode == 3:
		# Step3: 上限弃牌确认
		action_panel.add_child(_mkb("确认弃置", _on_pass, selected_indices.size() != 1))
		action_panel.add_child(_mkb("取消", _on_back, false))


func _mkb(text: String, cb: Callable, dis: bool) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 45)
	b.add_theme_font_size_override("font_size", 16)
	b.disabled = dis
	b.pressed.connect(cb)
	return b


# ============================================================
# 十、提示按钮
# ============================================================
func _on_hint_toggled(pressed: bool) -> void:
	if pressed: _update_card_info_label()
	else: card_info_label.text = ""


# ============================================================
# 十一、元素着色规则
# 优先级: 精确符号 > 族匹配(VIIA) > 类型匹配
# ============================================================
func _get_card_color(card) -> Color:
	var sym = card.symbol
	if sym == "H": return Color(0.4, 0.7, 1.0)
	if sym == "O": return Color(0.0, 0.3, 1.0)
	if sym == "N": return Color(0.4, 0.2, 0.8)
	if sym == "F": return Color(0.56, 1.0, 0.56)  # 浅绿色
	if sym == "Cl": return Color(0.56, 1.0, 0.56)  # 浅绿色
	if sym == "Br": return Color(0.6, 0.4, 0.2)  # 棕色
	if sym in ["C", "B", "Si", "S"]: return Color(1.0, 0.9, 0.1)
	if sym == "P": return Color(1.0, 0.85, 0.85)
	if card.group in ["VIIA"]: return Color(0.0, 0.7, 0.2)
	match card.element_type:
		"金属": return Color(0.5, 0.5, 0.5)
		"非金属": return Color(0.0, 0.7, 0.2)
		"准金属": return Color(0.0, 0.7, 0.2)
		"稀有气体": return Color(0.95, 0.95, 0.95)
	return Color(0.8, 0.8, 0.8)


# ============================================================
# 十二、手牌渲染（原子牌面）
# ============================================================
func _update_hand_buttons() -> void:
	if not hand_container or not game_manager: return
	for child in hand_container.get_children():
		child.queue_free()
	hand_buttons.clear()
	ai_triggered = false

	var cp = game_manager.get_current_player()
	if cp == null: return

	if cp.is_ai:
		# AI 回合：显示等待标签
		var wl = Label.new()
		wl.text = "等待 %s 行动中..." % cp.player_name
		wl.add_theme_font_size_override("font_size", 28)
		hand_container.add_child(wl)
		if not ai_triggered:
			ai_triggered = true
			var timer = get_tree().create_timer(1.5)
			timer.timeout.connect(_ai_auto_play)
	else:
		# 人类玩家：渲染牌面按钮
		cp.sort_hand_by_atomic_number()
		for i in range(cp.hand.size()):
			var card = cp.hand[i]
			var btn = _build_card_button(card, i)
			hand_container.add_child(btn)
			hand_buttons.append(btn)


# -------- 构建单张原子牌面 (95×118px 白底圆角牌面) --------
func _build_card_button(card, idx: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(95, 118)
	btn.tooltip_text = card.get_full_info()

	# 正常样式：白底 + 灰色边框 + 圆角
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.97, 0.97, 0.98, 1.0)
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = Color(0.7, 0.7, 0.75, 1.0)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style_normal)

	# 悬浮样式：边框变蓝
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.9, 0.93, 0.98, 1.0)
	style_hover.border_color = Color(0.3, 0.5, 0.8, 1.0)
	btn.add_theme_stylebox_override("hover", style_hover)

	# 选中样式：黄底 + 金色加粗边框
	if idx in selected_indices:
		var style_sel = style_normal.duplicate()
		style_sel.bg_color = Color(1.0, 1.0, 0.8, 1.0)
		style_sel.border_color = Color(1.0, 0.7, 0.0, 1.0)
		style_sel.border_width_left = 3
		style_sel.border_width_right = 3
		style_sel.border_width_top = 3
		style_sel.border_width_bottom = 3
		btn.add_theme_stylebox_override("normal", style_sel)

	# 原子序数 (左上)
	var l_num = Label.new()
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", 11)
	l_num.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	l_num.position = Vector2(4, 2)
	btn.add_child(l_num)

	# 族 (右上)
	var l_group = Label.new()
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", 9)
	l_group.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(48, 14)
	l_group.position = Vector2(43, 3)
	btn.add_child(l_group)

	# 符号 (中上，20px着色)
	var l_sym = Label.new()
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", 20)
	l_sym.add_theme_color_override("font_color", _get_card_color(card))
	l_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sym.size = Vector2(85, 22)
	l_sym.position = Vector2(5, 22)
	btn.add_child(l_sym)

	# 中文名 (中，11px)
	var l_name = Label.new()
	l_name.text = card.name_cn
	l_name.add_theme_font_size_override("font_size", 11)
	l_name.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1))
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_name.size = Vector2(85, 15)
	l_name.position = Vector2(5, 48)
	btn.add_child(l_name)

	# 化合价 (中下，标注正负)
	var val_str = ""
	for v in card.common_valence:
		if val_str != "": val_str += " "
		if v > 0: val_str += "+%d" % v
		else: val_str += "%d" % v
	var l_val = Label.new()
	l_val.text = val_str
	l_val.add_theme_font_size_override("font_size", 10)
	l_val.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2, 1))
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_val.size = Vector2(85, 13)
	l_val.position = Vector2(5, 65)
	btn.add_child(l_val)

	# 相对原子质量 (左下)
	var l_mass = Label.new()
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", 9)
	l_mass.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	l_mass.position = Vector2(3, 102)
	btn.add_child(l_mass)

	btn.pressed.connect(_on_card_clicked.bind(idx))
	return btn


# ============================================================
# 十三、化合价选择面板
# ============================================================
func _update_valence_buttons() -> void:
	if not action_panel or not game_manager: return
	for child in action_panel.get_children():
		child.queue_free()
	var cp = game_manager.get_current_player()

	var elem_map: Dictionary = {}
	for _idx in selected_indices:
		var card = cp.hand[_idx]
		if not elem_map.has(card.symbol):
			elem_map[card.symbol] = card

	if elem_map.size() < 2:
		action_panel.add_child(_mkb("至少选两种元素 (返回)", _on_back, false))
		return

	var all_assigned = true
	for sym in elem_map:
		var card = elem_map[sym]
		var already = null
		for sel in compound_selections:
			if sel.symbol == sym:
				already = sel
				break
		if already == null:
			all_assigned = false
			for v in card.common_valence:
				action_panel.add_child(_mkb("%s (%+d)" % [sym, v], _on_select_valence.bind(sym, v), false))

	if not all_assigned:
		action_panel.add_child(_mkb("返回", _on_back, false))
	else:
		var info = ""
		for sel in compound_selections:
			info += "%s%+d " % [sel.symbol, sel.valence]
		var lbl = Label.new()
		lbl.text = info
		action_panel.add_child(lbl)
		action_panel.add_child(_mkb("确认打出", _on_confirm_compound, false))
		action_panel.add_child(_mkb("重选化合价", _on_reset_valence, false))
		action_panel.add_child(_mkb("返回", _on_back, false))


# ============================================================
# 十四、用户交互回调
# ============================================================
func _on_card_clicked(index: int) -> void:
	if step_mode != 0 and step_mode != 3: return
	if index in selected_indices: selected_indices.erase(index)
	else: selected_indices.append(index)
	_update_hand_buttons()
	_update_action_panel()

func _on_step_next() -> void:
	step_mode = 1
	_update_action_panel()

# -------- 打出牌型 --------
func _on_element() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if UtilsScript.detect_pattern(cards) != UtilsScript.CardPattern.ELEMENT:
		_show_info("不是有效单质！")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.get_current_player_index(), cards)
	_handle_result(result)

func _on_clan_bomb() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if UtilsScript.detect_pattern(cards) != UtilsScript.CardPattern.CLAN_BOMB:
		_show_info("不是有效族炸！")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.get_current_player_index(), cards)
	_handle_result(result)

func _on_choose_compound() -> void:
	var cp = game_manager.get_current_player()
	var symbols: Array = []
	for _idx in selected_indices:
		var s = cp.hand[_idx].symbol
		if s not in symbols: symbols.append(s)
	if symbols.size() < 2:
		_show_info("化合物至少需要两种不同元素！")
		_on_back()
		return
	# 禁止卤族元素互化 (F/Cl/Br 之间)
	if _is_halogen_only(symbols):
		_show_info("卤族元素(F/Cl/Br)之间不可互相化合！请加入金属或其他非金属元素。")
		_on_back()
		return
	step_mode = 2
	compound_selections.clear()
	_update_action_panel()

func _on_select_valence(symbol: String, valence: int) -> void:
	for sel in compound_selections:
		if sel.symbol == symbol: return
	compound_selections.append({"symbol": symbol, "valence": valence})
	_update_action_panel()

func _on_confirm_compound() -> void:
	var cp = game_manager.get_current_player()
	var gm_idx = game_manager.get_current_player_index()

	var custom_valences: Dictionary = {}
	for sel in compound_selections:
		custom_valences[sel.symbol] = sel.valence

	var has_pos = false
	var has_neg = false
	for sel in compound_selections:
		if sel.valence > 0: has_pos = true
		elif sel.valence < 0: has_neg = true
	if not has_pos or not has_neg:
		_show_info("需要正价和负价元素！")
		return

	var available: Dictionary = {}
	for _idx in selected_indices:
		var card = cp.hand[_idx]
		available[card.symbol] = available.get(card.symbol, 0) + 1

	var valence_list: Array = []
	for sel in compound_selections:
		valence_list.append({
			"symbol": sel.symbol,
			"v": abs(sel.valence),
			"sign": -1 if sel.valence < 0 else 1,
			"avail": available.get(sel.symbol, 0)
		})

	if valence_list.size() == 2:
		# 2元素化合物：GCD 最简比
		var a = valence_list[0]
		var b = valence_list[1]
		if a.sign * b.sign > 0:
			_show_info("需要一正一负两种价态！")
			return
		var g = _gcd(a.v, b.v)
		var na = b.v / g
		var nb = a.v / g
		if a.avail < na or b.avail < nb:
			_show_info("手牌不足！需 %s×%d + %s×%d" % [a.symbol, na, b.symbol, nb])
			return
		var ccards: Array = []
		for _idx in selected_indices:
			var card = cp.hand[_idx]
			if card.symbol == a.symbol:
				var already = 0
				for cc in ccards:
					if cc.symbol == a.symbol: already += 1
				if already < na: ccards.append(card)
			elif card.symbol == b.symbol:
				var already = 0
				for cc in ccards:
					if cc.symbol == b.symbol: already += 1
				if already < nb: ccards.append(card)
		if ccards.size() != na + nb:
			_show_info("收集卡牌出错！")
			return
		var result = game_manager.play_cards(gm_idx, ccards, custom_valences)
		_handle_result(result)
		return

	# 3+元素化合物：每种恰好1张 + 总电荷=0
	var total_charge = 0
	var all_one = true
	for e in valence_list:
		if e.avail != 1: all_one = false
		total_charge += e.sign * e.v
	if all_one and total_charge == 0:
		var ccards: Array = []
		for _idx in selected_indices: ccards.append(cp.hand[_idx])
		var result = game_manager.play_cards(gm_idx, ccards, custom_valences)
		_handle_result(result)
		return

	_show_info("仅支持 2 元素化合物（多元素需每种恰好 1 张且电荷平衡）")

func _on_reset_valence() -> void:
	compound_selections.clear()
	_update_action_panel()

func _on_back() -> void:
	step_mode = 0
	compound_selections.clear()
	_update_action_panel()

# -------- 跳过与上限弃牌 --------
func _on_pass() -> void:
	var cp = game_manager.get_current_player()
	var hand_limit = min(game_manager.players.size() * 4, 18)
	if cp.get_hand_count() >= hand_limit:
		_on_discard_mode()
		return
	game_manager.player_pass(game_manager.get_current_player_index())
	_step_reset()
	_refresh_ui()

func _on_discard_mode() -> void:
	var cp = game_manager.get_current_player()
	var hand_limit = min(game_manager.players.size() * 4, 18)
	if cp.get_hand_count() < hand_limit:
		step_mode = 0
		selected_indices.clear()
		_update_action_panel()
		_update_hand_buttons()
		return
	if step_mode != 3:
		step_mode = 3
		selected_indices.clear()
		_show_info("手牌已达上限 (%d张)，请选择1张牌弃置。" % hand_limit)
		_update_action_panel()
		_update_hand_buttons()
		return
	if selected_indices.size() != 1:
		_show_info("请选择恰好1张牌弃置！")
		return
	var card = cp.hand[selected_indices[0]]
	game_manager.player_discard_and_pass(game_manager.get_current_player_index(), card)
	step_mode = 0
	_step_reset()
	_refresh_ui()


# ============================================================
# 十五、结果处理与状态重置
# ============================================================
func _handle_result(result: int) -> void:
	if result == 0:
		# 第0关：牌局阶段，玩家操作后检查是否需要显示规则提示
		if game_manager != null and game_manager.tutorial_level0_phase == 3:
			var tip = game_manager.level0_rule_tip
			if tip == "越大越小":
				var tip_box = _level0_make_tip_box("【越大越小】\n同牌型比较时，原子序数和越小的牌越大。桌面牌必须被你出的牌压过（你的牌要更大）！", 4.0)
				game_page.add_child(tip_box)
			elif tip == "同类同出":
				# 同类同出提示在打出单质/化合物时已经通过level0_last_player_action记录
				if game_manager.clan_bomb_chain_active:
					pass  # 族炸的"牌权争夺"已记录
			elif tip == "牌权争夺":
				var tip_box = _level0_make_tip_box("【牌权争夺】\n你打出了族炸！族炸可以超越牌型限制，直接抢到牌权。但注意：打出族炸后进入冷却❄，需要用化合物解除。", 4.5)
				game_page.add_child(tip_box)

		_step_reset()
		_refresh_ui()
		return
	var msg = "非法出牌！"
	if result == -2: msg = "牌不够大！"
	elif result == -3: msg = "不能出族炸！"
	elif result == -4: msg = "牌型不匹配！"
	_show_info(msg)
	_on_back()

func _step_reset() -> void:
	selected_indices.clear()
	step_mode = 0
	compound_selections.clear()

func _show_info(text: String) -> void:
	if info_label and game_manager:
		info_label.text = _format_player_status() + "\n" + text

func _show_end_page(custom_text: String) -> void:
	var tut_page = get_node_or_null("TutorialPage")
	start_page.visible = false
	game_page.visible = false
	end_page.visible = true
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	var is_tutorial = (game_manager != null and (game_manager.tutorial_level >= 1 or game_manager.tutorial_level0_phase >= 1))
	if end_label:
		if game_manager:
			var w = game_manager.get_winner()
			if w:
				end_label.text = "获胜者: %s" % w.player_name
				# 教学关卡：返回按钮指向教学引导页
				if is_tutorial:
					if tut_page: tut_page.visible = false
					if end_button:
						end_button.pressed.disconnect(_show_start_page)
						end_button.pressed.connect(_on_show_tutorial_page)
				return
		end_label.text = custom_text if custom_text != "" else "游戏结束"
	if is_tutorial:
		if tut_page: tut_page.visible = false


# ============================================================
# 十六、AI 自动操作策略
# ============================================================
func _ai_auto_play() -> void:
	if game_manager == null or game_manager.is_game_over(): return
	var cp = game_manager.get_current_player()
	if cp == null or not cp.is_ai or cp.hand.is_empty(): return
	var gm_idx = game_manager.get_current_player_index()
	# 第0关AI：族炸链中直接跳过（不能出族炸），其余只出单质和化合物
	if game_manager.tutorial_level == 0 and game_manager.tutorial_level0_phase >= 1:
		if game_manager.clan_bomb_chain_active:
			game_manager.player_pass(gm_idx)
		else:
			_ai_try_play_level0(cp, gm_idx)
		_refresh_ui()
		return

	if game_manager.clan_bomb_chain_active:
		if cp.clan_bomb_cooling: game_manager.player_pass(gm_idx)
		else: _ai_try_clan_bomb(cp, gm_idx)
		_refresh_ui()
		return

	# 非第0关AI：使用完整策略
	_ai_try_play(cp, gm_idx)
	_refresh_ui()

# -------- 第0关AI：只出单质或化合物 --------
func _ai_try_play_level0(p, gm_idx: int):
	# 1. 化合物配对 O(n²)（跳过卤族互化对）
	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			if _is_ai_halogen_pair(pair):
				continue
			var fi = UtilsScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				var cv: Dictionary = {}
				for sym in fi.get("actual_counts", {}):
					var sample = p.hand[i] if p.hand[i].symbol == sym else p.hand[j]
					var v = 0
					for val in sample.common_valence:
						if val > 0: v = val; break
					if v == 0: v = -abs(sample.common_valence[0])
					cv[sym] = v
				if game_manager.play_cards(gm_idx, pair, cv) == 0: return

	# 2. 双原子分子配对
	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in UtilsScript.DIATOMIC_SYMBOLS:
			for j in range(p.hand.size()):
				if i != j and p.hand[j].symbol == c.symbol:
					var dp = [p.hand[i], p.hand[j]]
					if game_manager.play_cards(gm_idx, dp) == 0: return
					break

	# 3. 单质单张
	for c in p.hand:
		if game_manager.play_cards(gm_idx, [c]) == 0: return

	# 4. 全部失败 → 跳过
	game_manager.player_pass(gm_idx)

# -------- AI 族炸尝试 --------
func _ai_try_clan_bomb(p, gm_idx: int):
	var bg = _group_by_group(p.hand)
	for g in bg:
		if bg[g].size() >= 2:
			if game_manager.play_cards(gm_idx, bg[g].duplicate()) == 0: return
	game_manager.player_pass(gm_idx)

# -------- AI 出牌优先顺序: 族炸 → 化合物 → 双原子 → 单质 --------
func _ai_try_play(p, gm_idx: int):
	# 1. 族炸尝试
	if not p.clan_bomb_cooling:
		var bg = _group_by_group(p.hand)
		for g in bg:
			if bg[g].size() >= 2:
				if game_manager.play_cards(gm_idx, bg[g].duplicate()) == 0: return

	# 2. 化合物配对 O(n²)（跳过卤族互化对）
	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			if _is_ai_halogen_pair(pair):
				continue
			var fi = UtilsScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				var cv: Dictionary = {}
				var counts = fi.get("actual_counts", {})
				for sym in counts:
					var sample = p.hand[i] if p.hand[i].symbol == sym else p.hand[j]
					var v = 0
					for val in sample.common_valence:
						if val > 0: v = val; break
					if v == 0: v = -abs(sample.common_valence[0])
					cv[sym] = v
				if game_manager.play_cards(gm_idx, pair, cv) == 0: return

	# 3. 双原子分子配对
	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in UtilsScript.DIATOMIC_SYMBOLS:
			for j in range(p.hand.size()):
				if i != j and p.hand[j].symbol == c.symbol:
					var dp = [p.hand[i], p.hand[j]]
					if game_manager.play_cards(gm_idx, dp) == 0: return
					break

	# 4. 单质单张
	for c in p.hand:
		if game_manager.play_cards(gm_idx, [c]) == 0: return

	# 5. 全部失败 → 跳过
	game_manager.player_pass(gm_idx)

# -------- AI 辅助函数 --------
func _group_by_group(hand: Array) -> Dictionary:
	var r = {}
	for c in hand:
		if not r.has(c.group): r[c.group] = []
		r[c.group].append(c)
	return r

func _is_ai_halogen_pair(pair: Array) -> bool:
	var halogen = ["F", "Cl", "Br"]
	if pair[0].symbol != pair[1].symbol and pair[0].symbol in halogen and pair[1].symbol in halogen:
		return true
	return false


# ============================================================
# 十七、验证函数（卤族互化检查）
# ============================================================
func _is_halogen_only(symbols: Array) -> bool:
	var halogen = ["F", "Cl", "Br"]
	for sym in symbols:
		if sym not in halogen:
			return false
	return true


func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return abs(a)