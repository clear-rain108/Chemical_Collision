# ============================================================
# GameUI.gd - 游戏主界面控制脚本
# 页面管理 / 牌面渲染 / 出牌步骤流 / AI策略 / 着色 / 教程
# 补充规则：有机物合成按钮 / 顺序指定牌型弹窗
# ============================================================

extends Control

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")
const AIPlayerScript = preload("res://scripts/AIPlayer.gd")

# ============================================================
# 一、页面引用
# ============================================================
var game_manager: RefCounted = null
var start_page: Control = null
var game_page: Control = null
var end_page: Control = null
var help_page_rules: Control = null
var help_page_cards: Control = null
var help_page_supp: Control = null
var start_button: Button = null
var end_label: Label = null
var end_button: Button = null
var help_rules_back_btn: Button = null
var help_rules_to_cards_btn: Button = null
var help_rules_to_supp_btn: Button = null
var help_cards_back_btn: Button = null
var help_cards_to_rules_btn: Button = null
var help_cards_to_supp_btn: Button = null
var help_supp_back_btn: Button = null
var help_supp_to_rules_btn: Button = null
var help_supp_to_cards_btn: Button = null
var help_btn: Button = null
var player_spin: SpinBox = null
var ai_spin: SpinBox = null

# ============================================================
# 二、UI 控件引用
# ============================================================
var hand_container: Control = null      # 手牌区 (Control，手动重叠布局)
var info_label: Label = null            # 牌权状态
var deck_count_label: Label = null      # 牌库计数
var status_bar_label: Label = null      # 顶部状态栏（当前玩家/手牌/牌库/桌面）
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
var _card_info_backup: String = ""      # hover 详情覆盖前的信息栏文本
var _card_info_detail_shown: bool = false  # 信息栏当前是否在显示 hover 详情
var step_mode: int = 0                  # 0=选牌 1=牌型 2=化合价 3=弃牌
var compound_selections: Array = []     # 化合价选择 [{symbol, valence}]
var hand_buttons: Array = []            # 手牌按钮列表
# 悬停状态机（-1 = 无）：命中判定用静止坐标，悬停状态不影响判定结果
var _hover_idx: int = -1                # 当前抬起的牌索引
var _hover_pending_idx: int = -1        # 正在等待稳定的目标索引
var _hover_pending_at: int = 0          # 目标开始等待的时间戳（毫秒）
var log_lines: Array = []               # 日志行缓存
const MAX_LOG_LINES = 6
var ai_triggered: bool = false          # AI 自动操作防重复

# 手牌重叠布局参数
const CARD_W := 95.0                    # 卡牌宽度
const CARD_H := 118.0                   # 卡牌高度
const CARD_GAP := 8.0                   # 不重叠时的间隙
const HOVER_LIFT := 20.0                # 悬停上浮高度
const CARD_STEP_MAX := 60.0             # 叠卡时每张最多露出的宽度（0.63×牌宽）
const HOVER_SWITCH_DELAY_MS := 60       # 命中某张牌后需稳定的毫秒数（跟手，不再等 110ms）
const HOVER_LEAVE_DELAY_MS := 140       # 仍在手牌容器内但已不在任何牌上（牌列下方）时的留出延迟
const HOVER_ANIM_MS := 80               # 抬起 / 落下补间时长（三次缓出）
const HOVER_EXIT_GRACE := 14.0          # 手牌上沿容错带：抬起牌顶边与容器顶边重合，贴边滑过不落牌

# ---- GamePage 内的 CanvasItem 层级 ----
# z_index 优先于树顺序：运行时新增的浮层必须挂进对应层容器，
# 否则任何抬高 z 的节点（手牌选中 10 / 悬停 20）都会穿透浮层
# （历史 bug：手牌穿透「顺序指定」弹窗、警告框被手牌打洞）
const Z_CONTENT := 0            # 内容层：桌面小卡 / 顶部状态栏 / 规则提醒
const Z_HAND_SELECTED := 10     # 选中手牌
const Z_HAND_HOVER := 20        # 悬停手牌（手牌内部最高）
const Z_SCRIM := 100            # 模态层：全屏遮罩 + 弹窗
const Z_TOAST := 110            # 提示层：警告框 / 引导提示（压在模态之上）

# ---- 视觉规范（P2）：圆角 / 描边 / 阴影的唯一来源 ----
# 所有 StyleBoxFlat 必须由 _make_panel_style(kind) 产出；
# 调用点只允许改 bg_color（hover/pressed/disabled），不要再手写 border / radius / shadow。
const CARD_RADIUS := 8          # 卡牌（含桌面小卡）
const PANEL_RADIUS := 10        # 面板 / 提示框
const BORDER_W := 1             # 普通元素描边
const BORDER_W_ACTIVE := 2      # 选中 / 焦点 / 警告描边
const BORDER_NEUTRAL := Color(0.63, 0.66, 0.71, 1.0)    # #A1A8B5
const BORDER_FOCUS := Color(0.35, 0.55, 0.85, 1.0)      # 主题蓝
const BORDER_SELECT := Color(0.9, 0.65, 0.1, 1.0)       # 橙金
const BORDER_SELECT_HOVER := Color(0.85, 0.55, 0.0, 1.0)
const BORDER_WARN := Color(0.906, 0.298, 0.235, 1.0)    # #E74C3C
const SHADOW_COLOR := Color(0.1, 0.15, 0.22, 0.14)
const SHADOW_SIZE := 3
const SHADOW_OFFSET := Vector2(0, 2)

# ---- 警告 toast：右栏上部空白格 ----
# LogLabel 从 y=300 起、TutorialLabel 从 y=186 起、InfoLabel 只到 x=480，
# 因此 (824,62)-(1136,178) 不与任何静态节点相交，也就不会遮住手牌。
const TOAST_DURATION := 2.5
const WARNING_TOAST_RECT := Rect2(824, 62, 312, 116)

# 三个层容器（GamePage 的直接子节点，_ensure_layers() 幂等创建）
var content_layer: Control = null
var overlay_layer: Control = null
var toast_layer: Control = null

# 警告 toast（单例复用：连续报错只更新文本并重置计时，不叠框、不被旧计时器提前熄灭）
var _warning_toast: Control = null
var _warning_label: Label = null
var _warning_seq: int = 0

# ============================================================
# 第零关覆盖层 (Phase 1: UI介绍, Phase 2: 流程说明)
# ============================================================
var level0_overlay: Control = null
var level0_active: bool = false
var level0_step: int = 0
var level0_ui_highlight_steps: Array = []
var level0_flow_steps: Array = []
var level0_flow_index: int = 0


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
	help_page_supp = get_node_or_null("HelpPage_Supp")

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

	# 补充规则勾选框（两个独立勾选框）
	var organic_cb = start_page.get_node_or_null("OrganicCheckBox") if start_page else null
	if organic_cb:
		organic_cb.toggled.connect(_on_organic_toggled)
	var seq_cb = start_page.get_node_or_null("SequenceCheckBox") if start_page else null
	if seq_cb:
		seq_cb.toggled.connect(_on_sequence_toggled)

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

	# 补充规则帮助页按钮绑定
	if help_page_supp:
		help_supp_back_btn = help_page_supp.get_node_or_null("HelpSuppBackBtn")
		help_supp_to_rules_btn = help_page_supp.get_node_or_null("HelpSuppToRulesBtn")
		help_supp_to_cards_btn = help_page_supp.get_node_or_null("HelpSuppToCardsBtn")
		if help_supp_back_btn:
			help_supp_back_btn.pressed.connect(_on_help_back)
		if help_supp_to_rules_btn:
			help_supp_to_rules_btn.pressed.connect(_on_help_show_rules)
		if help_supp_to_cards_btn:
			help_supp_to_cards_btn.pressed.connect(_on_help_show_cards)
	# 规则页和卡牌页跳转补充规则页按钮
	if help_page_rules:
		help_rules_to_supp_btn = help_page_rules.get_node_or_null("HelpRulesToSuppBtn")
		if help_rules_to_supp_btn:
			help_rules_to_supp_btn.pressed.connect(_on_help_show_supp)
	if help_page_cards:
		help_cards_to_supp_btn = help_page_cards.get_node_or_null("HelpCardsToSuppBtn")
		if help_cards_to_supp_btn:
			help_cards_to_supp_btn.pressed.connect(_on_help_show_supp)
	# 开始页补充规则按钮
	var supp_help_btn = start_page.get_node_or_null("SupplementaryHelpBtn") if start_page else null
	if supp_help_btn:
		supp_help_btn.pressed.connect(_on_help_show_supp)

	# 游戏页帮助按钮也指向补充规则
	if help_page_supp:
		# help_btn 已在上面绑定 _on_show_help，保留原有行为
		pass

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
		_ensure_layers()
		_build_status_bar()
		if hint_button:
			hint_button.toggled.connect(_on_hint_toggled)
		if quit_button:
			quit_button.pressed.connect(_on_quit_game)
		if help_btn:
			help_btn.pressed.connect(_on_show_help)


# ============================================================
# 四之二、层容器（Content / Overlay / Toast）
# ============================================================
# Main.tscn 里的静态节点全在 z=0；运行时新增节点按语义挂进三个层：
#   ContentLayer(z=0)   → 与静态节点同层，靠树序叠在静态节点之上
#   OverlayLayer(z=100) → 模态弹窗 + 全屏遮罩，必须盖住手牌（手牌最高 z=20）
#   ToastLayer(z=110)   → 警告 / 提示，必须盖住模态层
func _ensure_layers() -> void:
	if not game_page:
		return
	if not is_instance_valid(content_layer):
		content_layer = _make_layer("ContentLayer", Z_CONTENT)
	if not is_instance_valid(overlay_layer):
		overlay_layer = _make_layer("OverlayLayer", Z_SCRIM)
	if not is_instance_valid(toast_layer):
		toast_layer = _make_layer("ToastLayer", Z_TOAST)


func _make_layer(layer_name: String, z: int) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.z_index = z
	# 层自身不参与鼠标拾取，事件仍会落到其子节点
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.anchor_left = 0
	layer.anchor_top = 0
	layer.anchor_right = 1
	layer.anchor_bottom = 1
	layer.offset_left = 0
	layer.offset_top = 0
	layer.offset_right = 0
	layer.offset_bottom = 0
	game_page.add_child(layer)
	return layer


# -------- 视觉规范工厂：卡牌 / 面板 / 按钮 / toast 的唯一样式来源 --------
# kind: card / card_selected / card_hover / card_hover_selected
#       mini_card / mini_card_hover / button / toast_warning / toast_info
func _make_panel_style(kind: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match kind:
		"card":
			_style_base(sb, Color(0.973, 0.976, 0.988, 1.0), BORDER_NEUTRAL, BORDER_W, CARD_RADIUS, true)
		"card_selected":
			_style_base(sb, Color(1.0, 1.0, 0.82, 1.0), BORDER_SELECT, BORDER_W_ACTIVE, CARD_RADIUS, true)
		"card_hover":
			_style_base(sb, Color(0.9, 0.93, 0.98, 1.0), BORDER_FOCUS, BORDER_W_ACTIVE, CARD_RADIUS, true)
		"card_hover_selected":
			_style_base(sb, Color(1.0, 0.98, 0.72, 1.0), BORDER_SELECT_HOVER, BORDER_W_ACTIVE, CARD_RADIUS, true)
		"mini_card":
			_style_base(sb, Color(0.973, 0.976, 0.988, 0.92), BORDER_NEUTRAL, BORDER_W, CARD_RADIUS, false)
		"mini_card_hover":
			_style_base(sb, Color(0.9, 0.93, 0.98, 0.95), BORDER_FOCUS, BORDER_W, CARD_RADIUS, false)
		"button":
			_style_base(sb, Color(0.173, 0.243, 0.314, 1.0), Color(0.4, 0.55, 0.7, 1.0), BORDER_W, CARD_RADIUS, true)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
		"toast_warning":
			_style_base(sb, Color(1.0, 0.953, 0.851, 0.97), BORDER_WARN, BORDER_W_ACTIVE, PANEL_RADIUS, true)
		"toast_info":
			_style_base(sb, Color(1.0, 1.0, 0.85, 0.95), Color(1.0, 0.6, 0.0, 1.0), BORDER_W_ACTIVE, PANEL_RADIUS, true)
		_:
			_style_base(sb, Color(0.973, 0.976, 0.988, 1.0), BORDER_NEUTRAL, BORDER_W, CARD_RADIUS, true)
	return sb


# 统一填充底色 / 描边 / 圆角 / 阴影，避免各调用点各写一套数值
func _style_base(sb: StyleBoxFlat, bg: Color, border: Color, width: int, radius: int, shadow: bool) -> void:
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	if shadow:
		sb.shadow_color = SHADOW_COLOR
		sb.shadow_size = SHADOW_SIZE
		sb.shadow_offset = SHADOW_OFFSET


# 取层时必须保证已创建（脚本内各处直接调用，避免 _ready 之外的入口拿到 null）
func _layer(kind: int) -> Control:
	_ensure_layers()
	match kind:
		1: return overlay_layer
		2: return toast_layer
		_: return content_layer


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
	if help_page_supp: help_page_supp.visible = false
	_ensure_end_button_connected(_show_start_page)

	# 回到主界面时清空上一局日志，避免残留
	log_lines.clear()
	if log_label:
		log_label.text = "游戏日志:"

func _on_show_help() -> void:
	if help_page_rules: help_page_rules.visible = true
	if game_page: game_page.visible = false

func _on_show_tutorial_page() -> void:
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = true
	if start_page: start_page.visible = false
	if end_page: end_page.visible = false

func _on_tutorial_back() -> void:
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	if start_page: start_page.visible = true
	if end_page: end_page.visible = false

func _on_help_back() -> void:
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	if help_page_supp: help_page_supp.visible = false
	if start_page and start_page.visible:
		pass   # 从开始页打开帮助，返回开始页
	elif game_page and game_page.visible:
		game_page.visible = true  # 游戏中的帮助，返回游戏页
	else:
		if game_page: game_page.visible = true

func _on_help_show_cards() -> void:
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = true
	if help_page_supp: help_page_supp.visible = false

func _on_help_show_supp() -> void:
	if help_page_cards: help_page_cards.visible = false
	if help_page_rules: help_page_rules.visible = false
	if help_page_supp: help_page_supp.visible = true

func _on_help_show_rules() -> void:
	if help_page_cards: help_page_cards.visible = false
	if help_page_rules: help_page_rules.visible = true
	if help_page_supp: help_page_supp.visible = false


# ============================================================
# 六、游戏启动
# ============================================================
func _on_organic_toggled(pressed: bool) -> void:
	if pressed:
		_show_info_simple("已启用有机物胜利规则")
	else:
		_show_info_simple("已禁用有机物胜利规则")

func _on_sequence_toggled(pressed: bool) -> void:
	if pressed:
		_show_info_simple("已启用顺序牌型规则")
	else:
		_show_info_simple("已禁用顺序牌型规则")

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
	_hide_warning_toast()   # 清掉上一局残留的警告 toast

	if level == 0:
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
	# 读取开始页的补充规则勾选框状态（两个独立勾选框）
	var organic_cb = start_page.get_node_or_null("OrganicCheckBox") if start_page else null
	if organic_cb:
		game_manager.organic_rules_enabled = organic_cb.button_pressed
	var seq_cb_node = start_page.get_node_or_null("SequenceCheckBox") if start_page else null
	if seq_cb_node:
		game_manager.sequence_rules_enabled = seq_cb_node.button_pressed
	var ok = game_manager.init_game(total, ai)
	if not ok:
		push_error("init_game failed with total=%d ai=%d, retrying defaults" % [total, ai])
		ok = game_manager.init_game(4, 3)
		if not ok:
			push_error("CRITICAL: init_game also failed with defaults!")
			_show_end_page("初始化失败")
			return
	_step_reset()
	_hide_warning_toast()   # 新一局开始：隐藏上一局残留的警告 toast
	_refresh_ui()


# ============================================================
# 七之一、第零关：Phase 1 — UI 标注介绍
# ============================================================
func _level0_start_phase1() -> void:
	game_manager.set_tutorial_level0_phase(1)
	level0_active = true
	level0_step = 0

	level0_ui_highlight_steps = [
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


func _level0_show_ui_step(idx: int) -> void:
	_refresh_ui()

	if idx >= level0_ui_highlight_steps.size():
		_level0_start_phase2()
		return

	var step_data = level0_ui_highlight_steps[idx]
	level0_step = idx
	_level0_ensure_overlay()

	for child in level0_overlay.get_children():
		child.queue_free()

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_left = 0
	bg.anchor_top = 0
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	level0_overlay.add_child(bg)

	var hl_border = ColorRect.new()
	hl_border.color = Color(1, 1, 0, 0)
	hl_border.position = step_data.pos
	hl_border.size = step_data.size
	hl_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level0_overlay.add_child(hl_border)

	var hl_outline = _level0_make_outline_rect(step_data.pos, step_data.size, Color(1, 0.85, 0, 1), 4)
	level0_overlay.add_child(hl_outline)

	var tbx = 20
	var tby = 350
	var tbw = 560
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

	var step_indicator = Label.new()
	step_indicator.text = "%d / %d" % [idx + 1, level0_ui_highlight_steps.size()]
	step_indicator.add_theme_font_size_override("font_size", 13)
	step_indicator.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	step_indicator.position = Vector2(tbx + tbw - 100, tby + tbh - 26)
	step_indicator.size = Vector2(80, 20)
	level0_overlay.add_child(step_indicator)

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
	var top = ColorRect.new()
	top.color = color
	top.position = Vector2(0, 0)
	top.size = Vector2(size.x, width)
	c.add_child(top)
	var bottom = ColorRect.new()
	bottom.color = color
	bottom.position = Vector2(0, size.y - width)
	bottom.size = Vector2(size.x, width)
	c.add_child(bottom)
	var left = ColorRect.new()
	left.color = color
	left.position = Vector2(0, 0)
	left.size = Vector2(width, size.y)
	c.add_child(left)
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
		_layer(1).add_child(level0_overlay)
	elif not level0_overlay.is_inside_tree():
		_layer(1).add_child(level0_overlay)


# ============================================================
# 七之二、第零关：Phase 2 — 流程介绍
# ============================================================
func _level0_start_phase2() -> void:
	game_manager.set_tutorial_level0_phase(2)
	level0_flow_index = 0
	level0_flow_steps = [
		"游戏开始，每名玩家从牌堆中抽8张牌，\n你需要通过巧妙组合并预判其他玩家，尽快将所有手牌打出，最先打完所有手牌者获胜",
		"游戏中有单质、化合物与族炸这三种最基本的牌型，\n你将会在下面几个关卡了解他们的打法",
		"游玩时，你可以选择出牌或者跳过，出牌时，你应当考虑最基础的几个规则：\n越大越小、同类同出和牌权争夺。接下来就以一场对局来呈现吧",
	]
	_level0_show_flow_step(0)


func _level0_show_flow_step(idx: int) -> void:
	_refresh_ui()

	if level0_overlay:
		level0_overlay.queue_free()
		level0_overlay = null

	if idx >= level0_flow_steps.size():
		_level0_start_phase3()
		return

	level0_flow_index = idx
	_level0_ensure_overlay()

	for child in level0_overlay.get_children():
		child.queue_free()

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.anchor_left = 0
	bg.anchor_top = 0
	bg.anchor_right = 1
	bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	level0_overlay.add_child(bg)

	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0.95, 0.95, 1, 0.97)
	dialog_bg.position = Vector2(100, 250)
	dialog_bg.size = Vector2(900, 180)
	level0_overlay.add_child(dialog_bg)

	var dialog_border = _level0_make_outline_rect(Vector2(100, 250), Vector2(900, 180), Color(0.3, 0.5, 0.8, 1), 3)
	level0_overlay.add_child(dialog_border)

	var title = Label.new()
	title.text = "游戏流程介绍 %d/3" % (idx + 1)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.position = Vector2(130, 260)
	title.size = Vector2(840, 28)
	level0_overlay.add_child(title)

	var content = Label.new()
	content.text = level0_flow_steps[idx]
	content.add_theme_font_size_override("font_size", 16)
	content.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	content.position = Vector2(130, 300)
	content.size = Vector2(840, 80)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level0_overlay.add_child(content)

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
	game_manager.set_tutorial_level0_phase(3)

	if level0_overlay:
		level0_overlay.queue_free()
		level0_overlay = null

	level0_active = false
	_refresh_ui()

	_level0_create_rule_tips()

	var intro_tip = _level0_make_tip_box("对局开始！请尝试出牌吧。\nAI默认只出单质和化合物。", 3.0)
	_layer(2).add_child(intro_tip)


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
	_layer(0).add_child(level0_rule_tip_label)
	_level0_update_rule_tips()


func _level0_update_rule_tips() -> void:
	if not level0_rule_tip_label or not game_manager or game_manager.tutorial_level0_phase != 3:
		return

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


func _level0_make_tip_box(text: String, duration: float = 2.5) -> Control:
	var box = Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = Panel.new()
	bg.position = Vector2(200, 350)
	bg.size = Vector2(700, 70)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", _make_panel_style("toast_info"))
	box.add_child(bg)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	lbl.position = Vector2(220, 355)
	lbl.size = Vector2(660, 60)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)

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
	_update_status_bar()
	_update_log_label()
	_update_action_panel()
	_update_hand_buttons()
	_update_card_info_label()
	_update_deck_count()
	_update_tutorial_label()
	_level0_update_rule_tips()


func _update_info_label() -> void:
	if info_label and game_manager:
		info_label.text = _format_player_status()

# ============================================================
# 八之二、顶部状态栏（当前玩家 / 手牌数 / 上限 / 牌库 / 桌面）
# ============================================================
func _build_status_bar() -> void:
	if not game_page or status_bar_label != null:
		return
	# 深蓝灰背景条（60px，覆盖顶部）
	var bar = ColorRect.new()
	bar.color = Color(0.173, 0.243, 0.314, 1.0)   # #2C3E50
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1152, 60)
	_layer(0).add_child(bar)

	# 状态栏文字
	var lbl = Label.new()
	lbl.position = Vector2(16, 8)
	lbl.size = Vector2(1240, 44)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_layer(0).add_child(lbl)
	status_bar_label = lbl

	# 状态栏已整合信息，隐藏被遮挡/冗余的旧标签
	var title = game_page.get_node_or_null("TitleLabel")
	if title: title.visible = false
	var deck = game_page.get_node_or_null("DeckCountLabel")
	if deck: deck.visible = false
	# 下方标签的纵向坐标已直接写在 Main.tscn 中（不再运行时下移，避免与桌面牌重叠）


func _update_status_bar() -> void:
	if not status_bar_label or not game_manager:
		return
	var cp_idx = game_manager.get_current_player_index()
	var cp = game_manager.get_current_player()
	if cp == null:
		status_bar_label.text = ""
		return
	var ai_tag = "(AI)" if cp.is_ai else ""
	var cooling = "❄" if cp.clan_bomb_cooling else ""
	var pass_tag = "⏸" if cp.has_passed else ""
	var hand_limit = game_manager.get_hand_limit()
	var db = game_manager.get_database()
	var deck_remain = db.get_remaining_count() if db else 0
	# 桌面信息
	var table_txt = "桌面: 空"
	if game_manager.get_table_player_index() >= 0:
		var tp = game_manager.get_players()[game_manager.get_table_player_index()]
		var pat = CardPatternsScript.detect_pattern(game_manager.get_table_cards())
		var pn = CardPatternsScript.get_pattern_name(pat)
		table_txt = "桌面: %s 打出 %s" % [tp.player_name, pn]
	status_bar_label.text = "▶ %s %s%s%s  手牌 %d/%d  ｜  牌库 %d  ｜  %s" % [
		cp.player_name, ai_tag, cooling, pass_tag,
		cp.get_hand_count(), hand_limit, deck_remain, table_txt
	]

func _format_player_status() -> String:
	if game_manager == null or game_manager.get_player_count() == 0:
		return "等待游戏初始化..."
	var parts: Array = []
	var cp_idx = game_manager.get_current_player_index()
	for i in range(game_manager.get_player_count()):
		var p = game_manager.get_players()[i]
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
	# 自己的手牌数已在顶部状态栏显示，这里只列 AI 的，避免信息重复
	var counts: Array = []
	for i in range(game_manager.get_player_count()):
		var pl = game_manager.get_players()[i]
		if not pl.is_ai: continue
		counts.append("%s: %d张" % [pl.player_name, pl.get_hand_count()])
	if not counts.is_empty():
		result += "\n手牌: " + " | ".join(counts)
	# 补充规则状态
	if game_manager.get_organic_rules_enabled() or game_manager.get_sequence_rules_enabled():
		var rules_list: Array = []
		if game_manager.get_organic_rules_enabled(): rules_list.append("有机物胜利")
		if game_manager.get_sequence_rules_enabled(): rules_list.append("顺序牌型")
		result += "\n【补充规则】" + " + ".join(rules_list)
	if not game_manager.get_direction_clockwise():
		result += "\n方向: ← 逆时针"
	return result


var table_card_buttons: Array = []

func _update_table_label() -> void:
	if not table_label or not game_manager: return

	for btn in table_card_buttons:
		if is_instance_valid(btn): btn.queue_free()
	table_card_buttons.clear()

	if game_manager.get_table_player_index() >= 0:
		var p = game_manager.get_players()[game_manager.get_table_player_index()]
		var cards = game_manager.get_table_cards()
		var pat = CardPatternsScript.detect_pattern(cards)
		var pn = CardPatternsScript.get_pattern_name(pat)
		var en = CardPatternsScript.get_element_display(cards)
		var syms: Array = []
		for c in cards: syms.append(c.symbol)
		var txt = "桌面: %s 打出 %s" % [p.player_name, pn]
		if en != "": txt += " " + en
		if pat == CardPatternsScript.CardPattern.COMPOUND:
			var table_cv = game_manager.get_table_custom_valences()
			var fi = CompoundSolverScript.get_compound_formula(cards, table_cv)
			if not fi.is_empty():
				var formula = fi.get("formula", "")
				if formula != "":
					txt += " " + formula
					var comp_name = CompoundSolverScript.get_compound_name(cards, table_cv)
					if comp_name != "":
						txt += "（" + comp_name + "）"
		if game_manager.is_compound_immune(): txt += " [免疫]"
		if game_manager.is_clan_bomb_chain_active(): txt += " ⚠接炸中"
		table_label.text = txt

		# 为桌面迷你卡牌计算每个元素的化合价
		var card_valences: Dictionary = {}
		if pat == CardPatternsScript.CardPattern.ELEMENT:
			for i in range(cards.size()):
				card_valences[i] = 0
		elif pat == CardPatternsScript.CardPattern.COMPOUND:
			var fi2 = CompoundSolverScript.get_compound_formula(cards, game_manager.get_table_custom_valences())
			if not fi2.is_empty():
				# 按化学式的标准顺序（正电性在前，负电性在后，同内按电负性递增）重排卡牌
				# 这样桌面小卡牌的物理顺序与化学式字符串一致
				var pos_list2: Array = fi2.get("pos_list", [])
				var neg_list2: Array = fi2.get("neg_list", [])
				var ordered_cards: Array = []
				for e in pos_list2:
					for _ei in range(e.count):
						for c in cards:
							if c.symbol == e.symbol and c not in ordered_cards:
								ordered_cards.append(c)
								break
				for e in neg_list2:
					for _ei in range(e.count):
						for c in cards:
							if c.symbol == e.symbol and c not in ordered_cards:
								ordered_cards.append(c)
								break
				if ordered_cards.size() == cards.size():
					cards = ordered_cards
				# 计算每个元素的化合价（按重排后的索引）
				for e in pos_list2 + neg_list2:
					for i in range(cards.size()):
						if cards[i].symbol == e.symbol:
							card_valences[i] = e.ox_state
		elif pat == CardPatternsScript.CardPattern.SEQUENCE:
			# 顺序牌按原子序数升序显示（与玩家选择顺序无关，体现连续序列）
			var sorted_cards: Array = cards.duplicate()
			sorted_cards.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)
			cards = sorted_cards
			for i in range(cards.size()):
				card_valences[i] = 0

		# 桌面牌槽位："桌面: …"文字下方的那一行，多张时自动压缩并水平居中
		var slot_left := 20.0
		var slot_w := 580.0
		var slot_y := 186.0
		if table_label:
			slot_y = table_label.position.y + table_label.size.y + 4.0
		var mini_step: float = 80.0
		if cards.size() > 1:
			mini_step = min(80.0, (slot_w - 72.0) / float(cards.size() - 1))
		var row_w: float = 72.0 + mini_step * float(cards.size() - 1)
		var start_x: float = slot_left + max(0.0, (slot_w - row_w) * 0.5)
		for i in range(cards.size()):
			var cv = null
			if card_valences.has(i):
				cv = card_valences[i]
			var mini = _build_mini_card_button(cards[i], cv)
			mini.position = Vector2(start_x + i * mini_step, slot_y)
			_layer(0).add_child(mini)
			table_card_buttons.append(mini)
	else:
		table_label.text = "桌面: 空"


func _build_mini_card_button(card, custom_valence = null) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(72, 90)
	btn.tooltip_text = card.get_full_info()

	var style_normal = _make_panel_style("mini_card")
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("pressed", style_normal)

	var style_hover = _make_panel_style("mini_card_hover")
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var l_num = Label.new()
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", 8)
	l_num.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	l_num.position = Vector2(3, 1)
	btn.add_child(l_num)

	var l_group = Label.new()
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", 8)
	l_group.add_theme_color_override("font_color", Color(0.32, 0.34, 0.38, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(32, 10)
	l_group.position = Vector2(37, 2)
	btn.add_child(l_group)

	var l_sym = Label.new()
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", 15)
	l_sym.add_theme_color_override("font_color", _get_card_color(card))
	l_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sym.size = Vector2(65, 18)
	l_sym.position = Vector2(4, 18)
	btn.add_child(l_sym)

	var l_name = Label.new()
	l_name.text = card.name_cn
	l_name.add_theme_font_size_override("font_size", 9)
	l_name.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1))
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_name.size = Vector2(65, 12)
	l_name.position = Vector2(4, 38)
	btn.add_child(l_name)

	# 化合价显示：如果提供了自定义化合价就用它，否则显示常见化合价
	if custom_valence != null:
		# 单质/双原子分子显示 0，化合物显示实际氧化态
		var v = custom_valence
		var val_str = ""
		if v > 0: val_str = "+%d" % v
		elif v < 0: val_str = "%d" % v
		else: val_str = "0"
		var l_val = Label.new()
		l_val.text = val_str
		l_val.add_theme_font_size_override("font_size", 8)
		l_val.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2, 1))
		l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_val.size = Vector2(65, 10)
		l_val.position = Vector2(4, 52)
		btn.add_child(l_val)

	var l_mass = Label.new()
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", 7)
	l_mass.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	l_mass.position = Vector2(2, 78)
	btn.add_child(l_mass)

	return btn


func _update_log_label() -> void:
	if not log_label or not game_manager: return
	var new_logs = game_manager.flush_logs()
	if new_logs.is_empty(): return
	for msg in new_logs:
		log_lines.push_back(msg)
		while log_lines.size() > MAX_LOG_LINES:
			log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _update_card_info_label() -> void:
	if not card_info_label or not game_manager: return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		card_info_label.text = ""
		return
	var hint = game_manager.get_available_patterns(game_manager.get_current_player_index())
	card_info_label.text = "提示: " + hint


func _update_deck_count() -> void:
	if not deck_count_label or not game_manager: return
	var db = game_manager.get_database()
	if db: deck_count_label.text = "牌库剩余: %d张" % db.get_remaining_count()
	else: deck_count_label.text = "牌库剩余: —"
	if game_manager:
		var hand_limit = game_manager.get_hand_limit()
		deck_count_label.text += "  手牌上限: %d张" % hand_limit


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
		action_panel.add_child(_mkb("出牌(选牌型)", _on_step_next, selected_indices.is_empty()))
		var hand_limit = game_manager.get_hand_limit()
		if cp.get_hand_count() >= hand_limit:
			action_panel.add_child(_mkb("弃牌跳过(上限)", _on_pass, false))
		else:
			action_panel.add_child(_mkb("跳过", _on_pass, false))
	elif step_mode == 1:
		if game_manager.is_clan_bomb_chain_active() and game_manager.get_current_player_index() != game_manager.get_clan_bomb_owner():
			action_panel.add_child(_mkb("作为族炸打出", _on_clan_bomb, false))
			action_panel.add_child(_mkb("返回", _on_back, false))
		else:
			action_panel.add_child(_mkb("作为单质打出", _on_element, false))
			action_panel.add_child(_mkb("合成化合物", _on_choose_compound, false))
			if game_manager.get_sequence_rules_enabled():
				action_panel.add_child(_mkb("作为顺序打出", _on_sequence, false))
			action_panel.add_child(_mkb("作为族炸打出", _on_clan_bomb, false))
			action_panel.add_child(_mkb("返回", _on_back, false))
	elif step_mode == 2:
		_update_valence_buttons()
	elif step_mode == 3:
		action_panel.add_child(_mkb("确认弃置", _on_pass, selected_indices.size() != 1))
		action_panel.add_child(_mkb("取消", _on_back, false))


func _mkb(text: String, cb: Callable, dis: bool) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 45)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.disabled = dis

	# 深蓝灰圆角按钮样式（P2：统一由 _make_panel_style("button") 产出）
	var style_normal = _make_panel_style("button")
	b.add_theme_stylebox_override("normal", style_normal)

	# 悬停：背景变亮
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	style_hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	b.add_theme_stylebox_override("hover", style_hover)

	# 按下：略暗
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	b.add_theme_stylebox_override("pressed", style_pressed)

	# 禁用：半透明
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.173, 0.243, 0.314, 0.35)
	b.add_theme_stylebox_override("disabled", style_disabled)

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
# ============================================================
func _get_card_color(card) -> Color:
	var sym = card.symbol
	if sym == "H": return Color(0.4, 0.7, 1.0)
	if sym == "O": return Color(0.0, 0.3, 1.0)
	if sym == "N": return Color(0.4, 0.2, 0.8)
	if sym == "F": return Color(0.56, 1.0, 0.56)
	if sym == "Cl": return Color(0.56, 1.0, 0.56)
	if sym == "Br": return Color(0.6, 0.4, 0.2)
	if sym == "I": return Color(0.35, 0.0, 0.35)  # 紫黑色
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
	# 重建会销毁当前 hover 的按钮，先还原信息栏，避免详情文本滞留
	_restore_card_info()
	# 旧按钮即将销毁，悬停状态机必须一并清零，否则会指向失效索引
	_hover_idx = -1
	_hover_pending_idx = -1
	# 先 remove_child 再 queue_free：避免旧牌残留在容器中干扰重叠布局
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()
	hand_buttons.clear()
	ai_triggered = false

	var cp = game_manager.get_current_player()
	if cp == null: return

	if cp.is_ai:
		var wl = Label.new()
		wl.text = "等待 %s 行动中..." % cp.player_name
		wl.add_theme_font_size_override("font_size", 28)
		# 手牌区背景是浅蓝，默认白色字几乎不可见
		wl.add_theme_color_override("font_color", Color(0.33, 0.4, 0.5, 1))
		# Control 容器不会自动布局子节点，需显式定位
		wl.position = Vector2(200, 20)
		wl.size = Vector2(420, 48)
		hand_container.add_child(wl)
		if not ai_triggered:
			ai_triggered = true
			var timer = get_tree().create_timer(1.5)
			timer.timeout.connect(_ai_auto_play)
	else:
		cp.sort_hand_by_atomic_number()
		for i in range(cp.hand.size()):
			var card = cp.hand[i]
			var btn = _build_card_button(card, i)
			hand_container.add_child(btn)
			hand_buttons.append(btn)
		_layout_hand_cards()
		_restore_hover_after_rebuild()


# -------- 手牌重叠排列：一行居中，牌多时自动压缩间距 --------
func _layout_hand_cards() -> void:
	if not hand_container: return
	var n = hand_buttons.size()
	if n == 0: return
	var avail = hand_container.size.x
	# 不叠卡时能容纳的最大张数；超过后主动叠起（step 上限 CARD_STEP_MAX）
	var plain_max: int = int((avail + CARD_GAP) / (CARD_W + CARD_GAP))
	var step := CARD_W + CARD_GAP
	if n > plain_max and n > 1:
		step = min(CARD_STEP_MAX, (avail - CARD_W) / float(n - 1))
	var total = CARD_W + step * (n - 1)
	var start_x = max(0.0, (avail - total) * 0.5)
	var base_y = hand_container.size.y - CARD_H - HOVER_LIFT
	# 重叠到露出不足 72% 时切换紧凑牌面（内容靠左，保证露出的左条整齐可读）
	var compact = step < CARD_W * 0.72
	for i in range(n):
		var btn = hand_buttons[i]
		if not is_instance_valid(btn): continue
		btn.size = Vector2(CARD_W, CARD_H)
		# 重排会覆盖 position：先杀掉进行中的升降补间，否则动画会把牌拉回旧位置
		_kill_hover_tween(btn)
		btn.position = Vector2(start_x + i * step, base_y)
		btn.set_meta("base_pos", btn.position)
		btn.set_meta("hand_idx", i)
		btn.z_index = Z_HAND_SELECTED if i in selected_indices else 0
		_apply_card_compact(btn, compact)


# -------- 紧凑牌面：重叠时内容左对齐，保证左侧可见区域信息完整 --------
func _apply_card_compact(btn: Button, compact: bool) -> void:
	var sym = btn.get_node_or_null("CardSymbol")
	if sym:
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		sym.position = Vector2(6, 22) if compact else Vector2(5, 20)
		sym.size = Vector2(44, 26) if compact else Vector2(85, 26)
		sym.add_theme_font_size_override("font_size", 21 if compact else 26)
	var nm = btn.get_node_or_null("CardName")
	if nm:
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		nm.position = Vector2(6, 49) if compact else Vector2(5, 48)
		nm.size = Vector2(44, 15) if compact else Vector2(85, 15)
	var vl = btn.get_node_or_null("CardValence")
	if vl:
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		vl.position = Vector2(6, 72) if compact else Vector2(5, 72)
		vl.size = Vector2(44, 18) if compact else Vector2(85, 18)


# -------- 悬停判定：固定矩形 + 状态机（不用 mouse_entered/exited） --------
# 卡牌抬起会改变自身几何。若用引擎 enter/exit 判定就会自激抖动：
# 抬起 → 让出底部 20px → exited → 落回 → entered → 再抬起 → ……
# 重叠区还会出现两张牌互相抢 hover。这里改为用「静止坐标」算命中区，
# 悬停状态永远不参与判定，因此不可能自激。
func _process(_delta: float) -> void:
	_update_hand_hover()


# 命中区 = 静止位置 ∪ 抬起位置（上扩 HOVER_LIFT）：上浮后的区域仍归属该牌
func _card_hover_rect(btn: Button) -> Rect2:
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	return Rect2(base - Vector2(0, HOVER_LIFT), Vector2(CARD_W, CARD_H + HOVER_LIFT))


# 抬起牌的"实际绘制矩形"：z_index=20 让抬起牌压住相邻牌，
# 因此这块区域里的指针必须归它，否则视觉在 A 上、判定却给了 B（顶栏滑过时逐张乱跳）
func _card_raised_rect(btn: Button) -> Rect2:
	if not is_instance_valid(btn): return Rect2()
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	return Rect2(base - Vector2(0, HOVER_LIFT), Vector2(CARD_W, CARD_H))


# 核心区 = 静止位置中「没被后一张牌盖住」的那一段；重叠区不算 → 实现滞回
func _card_core_rect(idx: int) -> Rect2:
	if idx < 0 or idx >= hand_buttons.size(): return Rect2()
	var btn = hand_buttons[idx]
	if not is_instance_valid(btn): return Rect2()
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	var w: float = CARD_W
	if idx + 1 < hand_buttons.size() and is_instance_valid(hand_buttons[idx + 1]):
		var nb = hand_buttons[idx + 1]
		var nb_base: Vector2 = nb.get_meta("base_pos", nb.position)
		w = clampf(nb_base.x - base.x, 8.0, CARD_W)
	return Rect2(base - Vector2(0, HOVER_LIFT), Vector2(w, CARD_H + HOVER_LIFT))


# 鼠标位置命中的牌：越靠后的牌画得越上，重叠区归它（取最大索引）
func _hover_hit_index(mp: Vector2) -> int:
	var hit := -1
	for i in range(hand_buttons.size()):
		var b = hand_buttons[i]
		if not is_instance_valid(b): continue
		if _card_hover_rect(b).has_point(mp):
			hit = i
	return hit


# 真正执行切换：先落下旧牌再抬起新牌，信息栏顺序才不会串
func _set_hover_index(idx: int) -> void:
	if idx == _hover_idx: return
	if _hover_idx >= 0 and _hover_idx < hand_buttons.size():
		var old = hand_buttons[_hover_idx]
		if is_instance_valid(old): _apply_hover(old, false)
	_hover_idx = idx
	_hover_pending_idx = -1
	if idx >= 0 and idx < hand_buttons.size():
		var nb = hand_buttons[idx]
		if is_instance_valid(nb): _apply_hover(nb, true)


func _update_hand_hover() -> void:
	if hand_container == null or not is_instance_valid(hand_container): return
	# headless（自动化测试）没有真实鼠标，跳过轮询，避免 (0,0) 误触发
	if DisplayServer.get_name() == "headless": return
	if not hand_container.is_visible_in_tree(): return
	if hand_buttons.is_empty():
		_hover_idx = -1
		_hover_pending_idx = -1
		return
	# 离开手牌区立即复位（离开要跟手，不加延迟）
	var gr: Rect2 = hand_container.get_global_rect()
	var gmp: Vector2 = get_global_mouse_position()
	if not gr.has_point(gmp):
		# 抬起牌顶边正好与容器顶边重合：沿顶边滑动时给 HOVER_EXIT_GRACE 的容错带，
		# 否则越界 1px 就落牌、再回来又要等一次延迟，表现为"抖动"
		if _hover_idx >= 0 and _hover_keep_above(gmp, gr):
			return
		if _hover_idx != -1: _set_hover_index(-1)
		_hover_pending_idx = -1
		return
	var mp: Vector2 = hand_container.get_local_mouse_position()
	_update_hover_at(mp)


# 顶边容错带：横向仍在手牌范围内，纵向略微越过容器的上沿
func _hover_keep_above(gmp: Vector2, gr: Rect2) -> bool:
	return gmp.y < gr.position.y \
		and gmp.y >= gr.position.y - HOVER_EXIT_GRACE \
		and gmp.x >= gr.position.x and gmp.x < gr.end.x


# 核心判定（鼠标位置可注入）：自动化测试用它脱离真实鼠标验证防抖
func _update_hover_at(mp: Vector2) -> void:
	# 1) 已抬起的牌以 z=20 压住相邻牌：它画出来的矩形内必须归它自己，
	#    否则鼠标沿顶栏滑过时会不断判给被压住的后一张，形成来回跳
	if _hover_idx >= 0 and _hover_idx < hand_buttons.size():
		var cur = hand_buttons[_hover_idx]
		if is_instance_valid(cur) and _card_raised_rect(cur).has_point(mp):
			_hover_pending_idx = -1
			return
	# 2) 仍在当前牌核心区内（哪怕别的牌也命中）= 保持，重叠窄条处不回跳
	if _hover_idx >= 0 and _card_core_rect(_hover_idx).has_point(mp):
		_hover_pending_idx = -1
		return
	var hit := _hover_hit_index(mp)
	if hit == _hover_idx:
		_hover_pending_idx = -1
		return
	# 3) 分级稳定时间：命中某张牌 60ms（跟手）；
	#    仍在容器内但不在任何牌上（牌列下方）140ms，避免底边轻微抖动就落牌
	var delay := HOVER_LEAVE_DELAY_MS
	if hit >= 0 and _card_core_rect(hit).has_point(mp):
		delay = HOVER_SWITCH_DELAY_MS
	if hit != _hover_pending_idx:
		_hover_pending_idx = hit
		_hover_pending_at = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - _hover_pending_at >= delay:
		_set_hover_index(hit)


# -------- 悬停上浮 + 置顶（公共入口，保留原签名供测试/外部直接调用） --------
func _on_hand_card_hover(btn: Button, hovered: bool) -> void:
	if not is_instance_valid(btn): return
	var idx: int = hand_buttons.find(btn)
	if hovered:
		if _hover_idx != idx:
			if _hover_idx >= 0 and _hover_idx < hand_buttons.size():
				var old = hand_buttons[_hover_idx]
				if is_instance_valid(old): _apply_hover(old, false)
			_hover_idx = idx
		_apply_hover(btn, true)
	else:
		if idx == _hover_idx: _hover_idx = -1
		_apply_hover(btn, false)
	_hover_pending_idx = -1


# -------- 抬起/落下：位置、层级、边框样式三者同源，避免各自闪烁 --------
func _apply_hover(btn: Button, hovered: bool) -> void:
	if not is_instance_valid(btn): return
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	if hovered:
		btn.z_index = Z_HAND_HOVER
		# 层级立即生效，位置交给补间： 80ms 三次缓出，抬起/落下不再一格跳
		_tween_card_y(btn, base.y - HOVER_LIFT)
		_show_card_detail(btn)
	else:
		var idx: int = btn.get_meta("hand_idx", -1)
		btn.z_index = Z_HAND_SELECTED if idx in selected_indices else 0
		_tween_card_y(btn, base.y)
		_restore_card_info()
	# 悬停外观由本状态机驱动（引擎自带 hover 态是另一套判定，会独立闪）。
	# normal/hover/pressed 三者始终指向同一个 StyleBox：引擎无论认为是否悬停，
	# 画出来都一样 → 既不会闪，也不会回退到默认深色主题（那就是"选中后发黑"）。
	# 注意：get_meta 的第二参数不能用 null（Godot 会当作"无默认值"报错）
	var key: String = "sb_hover" if hovered else "sb_normal"
	var sb = btn.get_meta(key, false)
	if sb is StyleBox:
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)


# -------- 升降补间：每张牌只保留一个 tween，重排 / 反向移动时先 kill --------
# 本工程首个 Tween 用法，注意两点：
#   1) tween 由节点创建，节点释放后 tween 自动失效，回调里不必再判空；
#   2) meta 的第二参数不能用 null（Godot 会当作"无默认值"报错），这里用 false 兜底。
func _tween_card_y(btn: Button, target_y: float) -> void:
	if not is_instance_valid(btn): return
	_kill_hover_tween(btn)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position:y", target_y, HOVER_ANIM_MS / 1000.0)
	btn.set_meta("hover_tween", tw)


func _kill_hover_tween(btn: Button) -> void:
	if not is_instance_valid(btn): return
	var tw = btn.get_meta("hover_tween", false)
	if tw is Tween and tw.is_valid():
		tw.kill()


# -------- 悬停详情写进下方固定信息栏（替代原生 tooltip，避免浮框遮挡整排手牌） --------
func _show_card_detail(btn: Button) -> void:
	if not card_info_label or not game_manager: return
	var idx: int = btn.get_meta("hand_idx", -1)
	var cp = game_manager.get_current_player()
	if cp == null or idx < 0 or idx >= cp.hand.size(): return
	if not _card_info_detail_shown:
		_card_info_backup = card_info_label.text
		_card_info_detail_shown = true
	card_info_label.text = _card_summary_text(cp.hand[idx])


func _restore_card_info() -> void:
	if not card_info_label or not _card_info_detail_shown: return
	card_info_label.text = _card_info_backup
	_card_info_detail_shown = false


# -------- 卡牌详情压成单行，便于在信息栏一次读完 --------
func _card_summary_text(card) -> String:
	if card == null: return ""
	var vs := "N/A"
	if card.common_valence.size() > 0:
		var parts: Array = []
		for v in card.common_valence:
			parts.append(("+%d" % v) if v > 0 else str(v))
		vs = " ".join(parts)
	return "%s %s  |  原子序数 %d  |  族 %s  |  %s  |  化合价 %s  |  相对原子质量 %.2f" % [
		card.symbol, card.name_cn, card.atomic_number, card.group,
		card.element_type, vs, card.atomic_weight]


# -------- 点击重排后鼠标未移动，需主动恢复悬停状态 --------
func _restore_hover_after_rebuild() -> void:
	if hand_buttons.is_empty(): return
	var mp: Vector2 = hand_container.get_local_mouse_position()
	# 用与轮询相同的命中矩形和「取最上层」规则，保证两条路径结果一致
	var hit := _hover_hit_index(mp)
	if hit >= 0:
		_set_hover_index(hit)


func _build_card_button(card, idx: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.size = Vector2(CARD_W, CARD_H)   # Control 容器不分配尺寸，需显式设置
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# 不用原生 tooltip：它会浮在鼠标旁遮住整排手牌，改由下方 CardInfoLabel 显示

	var is_selected: bool = idx in selected_indices
	# 正常态 / 选中态走同一套规范（圆角 8、1px 中性边 / 2px 橙金边、轻投影）
	var style_base = _make_panel_style("card_selected" if is_selected else "card")

	# 悬停样式：未选中 → 浅蓝；已选中 → 保留黄色系（只加深），
	# 否则悬停会把"已选中"的浅黄整个盖掉，用户看不出哪张被选了
	var style_hover = _make_panel_style("card_hover_selected" if is_selected else "card_hover")

	btn.add_theme_stylebox_override("normal", style_base)
	# 引擎的 hover / pressed / focus 态必须一并接管，否则会回退到默认（深色）主题：
	# 鼠标停在牌上时整张牌被画成半透明深灰 —— 也就是"选中后发黑"的真正原因。
	# hover / pressed 与 normal 同源，引擎状态切换不可见，判定仍只由状态机负责。
	btn.add_theme_stylebox_override("hover", style_base)
	btn.add_theme_stylebox_override("pressed", style_base)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())   # 去掉点击后的焦点框
	# 两套样式存进 meta，_apply_hover() 在抬起/落下时切换
	btn.set_meta("sb_normal", style_base)
	btn.set_meta("sb_hover", style_hover)

	var l_num = Label.new()
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", 12)
	l_num.add_theme_color_override("font_color", Color(0.25, 0.28, 0.32, 1))
	l_num.position = Vector2(4, 2)
	btn.add_child(l_num)

	var l_group = Label.new()
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", 11)
	# 固定深灰：族名用元素类别色时（如稀有气体近白）几乎看不见
	l_group.add_theme_color_override("font_color", Color(0.3, 0.32, 0.36, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(52, 15)
	l_group.position = Vector2(38, 2)
	btn.add_child(l_group)

	var l_sym = Label.new()
	l_sym.name = "CardSymbol"
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", 26)
	l_sym.add_theme_color_override("font_color", _get_card_color(card))
	l_sym.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.25))
	l_sym.add_theme_constant_override("outline_size", 2)
	l_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sym.size = Vector2(85, 26)
	l_sym.position = Vector2(5, 20)
	btn.add_child(l_sym)

	var l_name = Label.new()
	l_name.name = "CardName"
	l_name.text = card.name_cn
	l_name.add_theme_font_size_override("font_size", 12)
	l_name.add_theme_color_override("font_color", Color(0.1, 0.12, 0.14, 1))
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_name.size = Vector2(85, 15)
	l_name.position = Vector2(5, 48)
	btn.add_child(l_name)

	var val_str = ""
	for v in card.common_valence:
		if val_str != "": val_str += " "
		if v > 0: val_str += "+%d" % v
		else: val_str += "%d" % v
	var l_val = Label.new()
	l_val.name = "CardValence"
	l_val.text = val_str
	l_val.add_theme_font_size_override("font_size", 13)
	l_val.add_theme_color_override("font_color", Color(0.55, 0.2, 0.2, 1))
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_val.size = Vector2(85, 18)
	l_val.position = Vector2(5, 72)
	btn.add_child(l_val)

	var l_mass = Label.new()
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", 9)
	l_mass.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	l_mass.position = Vector2(3, 102)
	btn.add_child(l_mass)

	btn.pressed.connect(_on_card_clicked.bind(idx))
	# 不再连接 mouse_entered/mouse_exited：悬停由 _update_hand_hover() 轮询固定矩形判定，
	# 否则卡牌上浮会改变自身拾取几何，导致进入/离开无限翻转（抽搐）
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

func _on_element() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if CardPatternsScript.detect_pattern(cards) != CardPatternsScript.CardPattern.ELEMENT:
		_show_info("不是有效单质！")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.get_current_player_index(), cards, {}, CardPatternsScript.CardPattern.ELEMENT)
	_handle_result(result)

func _on_sequence() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	# 玩家选择"作为顺序"：顺序优先于族炸检测（如 Fe+Co+Ni 既是族炸又是顺序）
	if CardPatternsScript.detect_pattern(cards, false, true) != CardPatternsScript.CardPattern.SEQUENCE:
		_show_info("不是有效顺序！需≥3张连续原子序数的牌。")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.get_current_player_index(), cards, {}, CardPatternsScript.CardPattern.SEQUENCE)
	_handle_result(result)

func _on_clan_bomb() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if CardPatternsScript.detect_pattern(cards) != CardPatternsScript.CardPattern.CLAN_BOMB:
		_show_info("不是有效族炸！")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.get_current_player_index(), cards, {}, CardPatternsScript.CardPattern.CLAN_BOMB)
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
	if _is_halogen_only(symbols):
		_show_info("卤族元素(F/Cl/Br/I)之间不可互相化合！请加入金属或其他非金属元素。")
		_on_back()
		return

	# 自动识别有机物：选中牌组若实际为有机物（甲醛/甲醇/乙醇/甲酸/乙酸/烷烃等），
	# 直接按有机物打出（跳过化合价选择），有机物打出即获胜
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if CardPatternsScript.detect_pattern(cards, true) == CardPatternsScript.CardPattern.ORGANIC:
		var custom_valences = {"_organic": true}
		var result = game_manager.play_cards(game_manager.get_current_player_index(), cards, custom_valences, CardPatternsScript.CardPattern.ORGANIC)
		if result == 0:
			log_lines.push_back("🎉 %s 打出有机物，立即获胜！" % cp.player_name)
		else:
			_show_info("有机物打出失败！")
		_handle_result(result)
		return

	step_mode = 2
	compound_selections.clear()
	_update_action_panel()

func _on_choose_organic() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	# 检查是否为有机物
	if CardPatternsScript.detect_pattern(cards, true) != CardPatternsScript.CardPattern.ORGANIC:
		_show_info("不是有效有机物！有机物包括：甲烷CH4、乙烷C2H6、丙烷C3H8及他们的单一卤代物。\n卤代物只能包含一种卤族元素(F/Cl/Br)。")
		_on_back()
		return
	# 打出有机物，标记 _organic 跳过族炸检测
	var custom_valences = {"_organic": true}
	var result = game_manager.play_cards(game_manager.get_current_player_index(), cards, custom_valences, CardPatternsScript.CardPattern.ORGANIC)
	if result == 0:
		# 有机物打出成功
		log_lines.push_back("🎉 %s 打出有机物，立即获胜！" % cp.player_name)
		_handle_result(result)
	else:
		_show_info("有机物打出失败！")
		_on_back()

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
		var result = game_manager.play_cards(gm_idx, ccards, custom_valences, CardPatternsScript.CardPattern.COMPOUND)
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
		var result = game_manager.play_cards(gm_idx, ccards, custom_valences, CardPatternsScript.CardPattern.COMPOUND)
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

func _on_pass() -> void:
	var cp = game_manager.get_current_player()
	var hand_limit = game_manager.get_hand_limit()
	if cp.get_hand_count() >= hand_limit:
		_on_discard_mode()
		return
	game_manager.player_pass(game_manager.get_current_player_index())
	_step_reset()
	_refresh_ui()

func _on_discard_mode() -> void:
	var cp = game_manager.get_current_player()
	var hand_limit = game_manager.get_hand_limit()
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
	if result == 0:  # 成功打出（普通牌型）或有机物胜利/手牌出完
		if game_manager != null and game_manager.tutorial_level0_phase == 3:
			var tip = game_manager.level0_rule_tip
			if tip == "越大越小":
				var tip_box = _level0_make_tip_box("【越大越小】\n同牌型比较时，原子序数和越小的牌越大。桌面牌必须被你出的牌压过（你的牌要更大）！", 4.0)
				_layer(2).add_child(tip_box)
			elif tip == "牌权争夺":
				var tip_box = _level0_make_tip_box("【牌权争夺】\n你打出了族炸！族炸可以超越牌型限制，直接抢到牌权。但注意：打出族炸后进入冷却❄，需要用化合物解除。", 4.5)
				_layer(2).add_child(tip_box)

		_step_reset()
		_refresh_ui()
		return
	elif result == 1:  # 打出顺序，需要选择指定牌型
		_step_reset()
		_show_sequence_constraint_dialog()
		return
	var msg = "非法出牌！"
	if result == -2: msg = "牌不够大！"
	elif result == -3: msg = "不能出族炸！"
	elif result == -4: msg = "牌型不匹配！"
	elif result == -6: msg = "不符合顺序指定的牌型约束！"
	_show_info(msg)
	_on_back()


# ============================================================
# 十五之二、顺序指定牌型弹窗
# ============================================================
func _show_sequence_constraint_dialog() -> void:
	# 创建弹窗
	var overlay = Control.new()
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.anchor_left = 0; bg.anchor_top = 0
	bg.anchor_right = 1; bg.anchor_bottom = 1
	overlay.add_child(bg)

	var panel = ColorRect.new()
	panel.color = Color(0.95, 0.95, 1, 0.97)
	panel.position = Vector2(300, 250)
	panel.size = Vector2(500, 250)
	overlay.add_child(panel)

	var title = Label.new()
	title.text = "选择下一名玩家必须打出的牌型"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.position = Vector2(320, 260)
	title.size = Vector2(460, 30)
	overlay.add_child(title)

	var desc = Label.new()
	desc.text = "打出「顺序」后，出牌方向已反转。\n请选择让下一名玩家打出哪种牌型，\n否则该玩家将被罚抽2张牌。"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1))
	desc.position = Vector2(320, 295)
	desc.size = Vector2(460, 65)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(desc)

	# 可选择：单质、化合物、族炸（有机物并入化合物，不单独列出）
	var patterns = [
		{"name": "单质", "pattern": CardPatternsScript.CardPattern.ELEMENT},
		{"name": "化合物", "pattern": CardPatternsScript.CardPattern.COMPOUND},
		{"name": "族炸", "pattern": CardPatternsScript.CardPattern.CLAN_BOMB},
	]

	for i in range(patterns.size()):
		var p = patterns[i].pattern
		var choose := func():
			game_manager.set_sequence_constraint(p)
			overlay.queue_free()
			_refresh_ui()
		# 与操作面板同一套按钮样式（P2 统一）
		var btn = _mkb(patterns[i].name, choose, false)
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 15)
		btn.position = Vector2(320 + (i % 3) * 150, 370 + (i / 3) * 50)
		overlay.add_child(btn)

	# 取消按钮（不指定，视为放弃权利）
	var cancel_cb := func():
		game_manager.sequence_constraint_active = false
		game_manager.sequence_constraint = -1
		game_manager.next_turn()
		overlay.queue_free()
		_refresh_ui()
	var cancel_btn = _mkb("跳过指定", cancel_cb, false)
	cancel_btn.custom_minimum_size = Vector2(140, 40)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.position = Vector2(470, 370 + patterns.size() / 3 * 50 + 10)
	overlay.add_child(cancel_btn)

	_layer(1).add_child(overlay)


# ============================================================
func _step_reset() -> void:
	selected_indices.clear()
	step_mode = 0
	compound_selections.clear()

func _show_info(text: String) -> void:
	if info_label and game_manager:
		info_label.text = _format_player_status() + "\n" + text
	# 同时显示居中的大号提示框（出牌不合理等错误提示醒目可见）
	_show_center_warning(text)


# 右栏警告 toast（黄底橙红边，2.5 秒自动消失）
# 位置固定在右栏上部空白格，不再压在手牌 / 操作区 / 卡牌信息之上。
# 单例复用：连续报错只更新文本并重置计时，不叠框、也不会被上一次的计时器提前熄灭。
func _show_center_warning(text: String) -> void:
	_ensure_warning_toast()
	if not is_instance_valid(_warning_toast) or not is_instance_valid(_warning_label):
		return
	_warning_label.text = text
	_warning_toast.visible = true
	_warning_seq += 1
	var seq := _warning_seq
	var timer := get_tree().create_timer(TOAST_DURATION)
	timer.timeout.connect(func():
		# 期间又弹了新提示（seq 变了）→ 这次计时作废
		if seq == _warning_seq and is_instance_valid(_warning_toast):
			_warning_toast.visible = false
	)


func _ensure_warning_toast() -> void:
	if is_instance_valid(_warning_toast):
		return

	var panel := Panel.new()
	panel.name = "WarningToast"
	panel.position = WARNING_TOAST_RECT.position
	panel.size = WARNING_TOAST_RECT.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _make_panel_style("toast_warning"))

	var lbl := Label.new()
	lbl.position = Vector2(12, 8)
	lbl.size = WARNING_TOAST_RECT.size - Vector2(24, 16)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.05, 0.05, 1.0))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	_layer(2).add_child(panel)
	_warning_toast = panel
	_warning_label = lbl


# 开局 / 进教程时清掉上一局残留的警告；seq 自增让未到期的计时器失效
func _hide_warning_toast() -> void:
	_warning_seq += 1
	if is_instance_valid(_warning_toast):
		_warning_toast.visible = false

func _show_end_page(custom_text: String) -> void:
	var tut_page = get_node_or_null("TutorialPage")
	start_page.visible = false
	game_page.visible = false
	end_page.visible = true
	if help_page_rules: help_page_rules.visible = false
	if help_page_cards: help_page_cards.visible = false
	if help_page_supp: help_page_supp.visible = false
	var is_tutorial = (game_manager != null and (game_manager.tutorial_level >= 1 or game_manager.tutorial_level0_phase >= 1))
	if end_label:
		if game_manager:
			var w = game_manager.get_winner()
			if w:
				end_label.text = "获胜者: %s" % w.player_name
				if is_tutorial:
					if tut_page: tut_page.visible = false
					if end_button:
						_ensure_end_button_connected(_on_show_tutorial_page)
				else:
					_ensure_end_button_connected(_show_start_page)
				return
		end_label.text = custom_text if custom_text != "" else "游戏结束"
	_ensure_end_button_connected(_show_start_page)
	if is_tutorial:
		if tut_page: tut_page.visible = false


func _ensure_end_button_connected(target: Callable) -> void:
	if end_button == null:
		return
	if end_button.pressed.is_connected(_show_start_page):
		end_button.pressed.disconnect(_show_start_page)
	if end_button.pressed.is_connected(_on_show_tutorial_page):
		end_button.pressed.disconnect(_on_show_tutorial_page)
	if not end_button.pressed.is_connected(target):
		end_button.pressed.connect(target)


# ============================================================
# 十六、AI 自动操作策略
# ============================================================
func _ai_auto_play() -> void:
	AIPlayerScript.auto_play(game_manager, _refresh_ui)


# ============================================================
# 十七、验证函数（卤族互化检查）
# ============================================================
func _is_halogen_only(symbols: Array) -> bool:
	var halogen = ["F", "Cl", "Br", "I"]
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
