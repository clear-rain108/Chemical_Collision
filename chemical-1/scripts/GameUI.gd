# ============================================================
# GameUI.gd - 游戏主界面控制脚本
# 页面管理 / 牌面渲染 / 出牌步骤流 / AI策略 / 着色 / 教程
# 补充规则：有机物合成按钮 / 顺序指定牌型弹窗
# ============================================================

extends Control

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")
const AIPlayerScript = preload("res://scripts/AIPlayer.gd")
const HelpContentScript = preload("res://scripts/HelpContent.gd")
const HintAdvisorScript = preload("res://scripts/HintAdvisor.gd")

# ============================================================
# 一、页面引用
# ============================================================
var game_manager: RefCounted = null
var start_page: Control = null
var game_page: Control = null
var end_page: Control = null
# 帮助中心（P5）：单页 + 3 Tab + 滚动容器 + 卡片，全部由 _build_help_page() 代码生成
# 旧节点 HelpPage_Rules / HelpPage_Cards / HelpPage_Supp 已在 P6 从 Main.tscn 删除
var help_page: Control = null            # 帮助中心根节点
var help_tab_btns: Array = []            # 3 个 Tab 按钮
var help_scrolls: Array = []             # 3 个 ScrollContainer（每个 Tab 独立滚动位置）
var help_bodies: Array = []              # 3 个内容根 VBoxContainer
var _help_tab: int = 0                   # 当前 Tab 索引
var _help_filled: Array = [false, false, false]   # 懒加载标记：首次切到该 Tab 才构建卡片
var _help_elements: Array = []           # 图鉴用 29 张 CardData 缓存（只造一次）
var start_button: Button = null
var end_label: Label = null
var end_button: Button = null
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
# ------------------------------------------------------------
# 手牌重排（P7）：数据层的顺序才是真源
#   · 拖动改的是 PlayerInfo.hand 的数组顺序，界面每次重建都照抄，不做第二套顺序；
#   · selected_indices 只能存索引，重排 / 抽牌后必须按「卡片对象」重新映射，
#     否则选中的会变成另一张牌（历史隐患，本次一并修掉）。
# ------------------------------------------------------------
var _drag_press_idx: int = -1           # 左键按下时命中的手牌索引（-1 = 未按下）
var _drag_press_pos: Vector2 = Vector2.ZERO   # 按下时的全局鼠标坐标（算阈值用）
var _drag_press_at: int = 0             # 按下时刻（触屏长按判定用）
var _drag_active: bool = false          # 是否已越过阈值、进入拖拽
var _drag_from: int = -1                # 拖拽源下标（进入拖拽时快照）
var _drag_slot: int = -1                # 当前插入槽位（0..n，表示插到第 slot 张之前）
var _drag_grab: Vector2 = Vector2.ZERO  # 抓取点相对牌左上角的偏移
var _drag_ghost: Control = null         # 跟手的幽灵牌
var _drag_line: ColorRect = null        # 插入位置指示线
var _drag_suppress_click: bool = false  # 拖拽刚结束 → 吞掉 Button 补发的 pressed
var _reorder_btn: Button = null         # 「按序」按钮（仅在手动排列模式下可见）
var _reorder_tip: String = ""           # 一次性提示：重排完成后显示在下方信息栏
var _card_info_backup: String = ""      # hover 详情覆盖前的信息栏文本
var _card_info_detail_shown: bool = false  # 信息栏当前是否在显示 hover 详情
var step_mode: int = 0                  # 0=选牌 1=牌型 2=化合价 3=弃牌
var compound_selections: Array = []     # 化合价选择 [{symbol, valence}]
# 提示按钮（P6）：_on_hint_toggled → HintAdvisor.suggest() 自动选牌 + 写一句说明；
# 说明文本存在 _hint_text 里，_update_card_info_label() 优先显示它，
# 直到局面变了（换人 / 手牌数变化）或玩家自己动了牌
var _hint_text: String = ""
var _hint_owner: int = -1
var _hint_hand_size: int = -1
var _hint_order_sig: String = ""        # 提示生效时的手牌顺序签名（重排后提示自动作废）
var hand_buttons: Array = []            # 手牌按钮列表
# 悬停状态机（-1 = 无）：命中判定用静止坐标，悬停状态不影响判定结果
var _hover_idx: int = -1                # 当前抬起的牌索引
var _hover_pending_idx: int = -1        # 正在等待稳定的目标索引
var _hover_pending_at: int = 0          # 目标开始等待的时间戳（毫秒）
var log_lines: Array = []               # 日志行缓存
const MAX_LOG_LINES = 6
var ai_triggered: bool = false          # AI 自动操作防重复
var _hand_read_only: bool = false       # 手牌区只读（AI 回合显示玩家自己的牌，但不可操作）
# 热座交接（B2）：已确认「正在看自己手牌」的人类座位；-1 = 还没人确认。
# 只记座位号不记人 → 同一位玩家连续行动（顺序牌型的二次选择）不会重复弹遮罩。
var _hotseat_ready_seat: int = -1

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

# 拖拽重排（P7）
const DRAG_THRESHOLD := 6.0             # 移动超过该距离才算拖拽（否则仍按点击处理）
const DRAG_GHOST_ALPHA := 0.85          # 幽灵牌不透明度
const DRAG_SOURCE_ALPHA := 0.28         # 原位牌淡出程度（表示"这张被拿起来了"）
const DRAG_LINE_W := 3.0                # 插入指示线宽度

# ------------------------------------------------------------
# 触屏档案（Android / 移动端，A1+B+C）
# ------------------------------------------------------------
# 铁律：本节以上的所有 const 都是「桌面基准值」，24 套 headless 测试直接读它们做断言；
# 移动端的放大值一律走 *_touch() 取值函数，**const 一个都不改** ——
# 于是 _touch_ui=false（桌面 / 自动化）时行为与 P11 逐像素一致，
# _touch_ui=true（真机）时按钮/字号/手势切到触控档。
# 换算基准：1080p 手机横屏 2340×1080 → 缩放 1.667 → 1 逻辑 px ≈ 0.667dp，
#   32px 的工具行只有 21dp（Android 建议 ≥48dp），必须放大。
var _touch_ui: bool = false             # 触屏档案开关（_ready 里按 OS.has_feature("mobile") 置位）
var _quit_confirm_pending: bool = false # 触屏「退出游戏」二次确认（防误触直接跳结算页）
const TOUCH_BTN_MIN_H := 48             # 触控目标最小高度（≈32dp）
const TOUCH_FS_BONUS := 2               # 页面按钮 / 标签字号通用加成
const TOUCH_TOOL_BTN_H := 48            # 工具行：32 → 48（下沿 590，仍让 ActionPanel 9px）
const TOUCH_TOOL_BTN_TOP := 542         # 工具行顶：558 → 542（上让 CardInfoLabel 16px）
const TOUCH_TOOL_BTN_GAP := 20          # 工具行间距：10 → 20（"帮助"与"退出游戏"不再贴脸误触）
const TOUCH_DRAG_THRESHOLD := 24.0      # 拖动阈值：6 → 24（≈16dp，手指抖动不再被判成拖拽）
const TOUCH_DRAG_LONG_PRESS_MS := 300   # 长按多久才进入重排（未达时长松手 = 纯点选）
const TOUCH_SELECT_LIFT := 10.0         # 选中牌常驻上浮（与悬停 20 区分，一眼看出选了谁）
const TOUCH_HIT_PAD := 8.0              # 触屏命中外扩缓冲（≈5dp，手指比鼠标粗）


# ---- GamePage 内的 CanvasItem 层级 ----
# z_index 优先于树顺序：运行时新增的浮层必须挂进对应层容器，
# 否则任何抬高 z 的节点（手牌选中 10 / 悬停 20）都会穿透浮层
# （历史 bug：手牌穿透「顺序指定」弹窗、警告框被手牌打洞）
const Z_CONTENT := 0            # 内容层：桌面小卡 / 顶部状态栏 / 规则提醒
const Z_HAND_SELECTED := 10     # 选中手牌
const Z_HAND_HOVER := 20        # 悬停手牌（手牌内部最高）
const Z_DRAG := 30              # 拖拽幽灵牌 / 插入线（高于悬停牌，仍低于模态 100）
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

# ---- 动效规范（P3）：页面淡入 / 按钮缩放 ----
# 页面淡入采用「根节点常驻同色底 + 目标页 modulate 0→1」，不改 visible 语义：
# 交叉淡化必须延迟隐藏旧页，而 _on_help_back() 等处会同步读 *.visible 判断去向，
# 延迟隐藏会引入竞态，故一律保持 visible 同步，只做视觉层淡入。
const PAGE_BG_COLOR := Color(0.902, 0.941, 0.98, 1.0)   # #E6F0FA，与各页背景同色
const PAGE_FADE_MS := 220                                # 页面淡入时长
const BUTTON_HOVER_SCALE := 1.05                         # 按钮悬停放大
const BUTTON_PRESS_SCALE := 0.96                         # 按钮按下回缩
const BUTTON_SCALE_MS := 90                              # 缩放补间时长

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

# 页面淡入补间（全局单例：同一时刻只允许一个页面在淡入）
var _page_fade_tween: Tween = null

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
	# 触屏档案（Android / iOS）：只影响按钮尺寸、字号与手势，不改任何布局坐标
	_touch_ui = OS.has_feature("mobile")
	_ensure_page_backdrop()   # 必须先于任何页面淡入，否则第一帧会闪出窗口清屏色
	_setup_pages()
	_show_start_page()


# -------- 绑定所有页面和按钮引用 --------
func _setup_pages() -> void:
	start_page = get_node_or_null("StartPage")
	# 开始页全部子节点代码生成（P6）；必须在下面所有 get_node_or_null 之前完成
	_build_start_page()
	game_page = get_node_or_null("GamePage")
	end_page = get_node_or_null("EndPage")
	# 旧 3 个帮助页节点已在 P6 从 Main.tscn 删除，代码不再有任何引用
	# 结束页 / 教学引导页（P8）同样全部代码生成；必须在下面取 EndLabel / Tutorial*Btn 之前完成
	_build_end_page()
	_build_tutorial_page()

	if start_page:
		start_button = _start_child("StartButton")
		# 人数 / AI 数 / 规则开关 / 补充规则入口都嵌在 SettingsCard 里，
		# 必须用 _start_child() 递归查找（P6 起 start_page 的直接子节点只剩视觉块）
		player_spin = _start_child("PlayerCountSpin")
		var tut_btn = _start_child("TutorialBtn")
		if tut_btn:
			tut_btn.pressed.connect(_on_show_tutorial_page)
		ai_spin = _start_child("AiCountSpin")
		if start_button:
			start_button.pressed.connect(_on_start_game)
		# AI 座位数联动：AI ≤ 总人数 - 1，总人数一变就把 AI 数一起压下来
		if player_spin and ai_spin:
			player_spin.value_changed.connect(_on_player_count_changed)
			ai_spin.max_value = maxi(0, int(player_spin.value) - 1)
		var exit_btn = _start_child("ExitButton")
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

	# 补充规则（P10：四条开关都在小页里，仍是独立的 toggle 按钮）
	var organic_cb = _start_child("OrganicCheckBox")
	if organic_cb:
		organic_cb.toggled.connect(_on_organic_toggled)
	var seq_cb = _start_child("SequenceCheckBox")
	if seq_cb:
		seq_cb.toggled.connect(_on_sequence_toggled)
	var halogen_cb = _start_child("HalogenCheckBox")
	if halogen_cb:
		halogen_cb.toggled.connect(_on_halogen_toggled)

	if end_page:
		# 结束页子节点全在结算卡 EndCard 之内（P8）
		var el = end_page.get_node_or_null("EndCard/EndLabel")
		if el:
			end_label = el
		var eb = end_page.get_node_or_null("EndCard/EndButton")
		if eb:
			end_button = eb
			if not eb.pressed.is_connected(_show_start_page):
				eb.pressed.connect(_show_start_page)

	# 补充规则小页（P10）：开始页入口 → 小页；小页里的「查看完整说明」才跳帮助中心第 3 个 Tab
	var supp_entry = _start_child("SupplementaryHelpBtn")
	if supp_entry:
		supp_entry.pressed.connect(_open_supp_rules)
	var element_limit_cb = _start_child("ElementLimitCheckBox")
	if element_limit_cb:
		element_limit_cb.toggled.connect(_on_element_limit_toggled)
	for info in CardDatabaseScript.get_optional_elements():
		var chip = _start_child("ElementChip_" + str(info["symbol"]))
		if chip:
			chip.toggled.connect(_on_element_chip_toggled)
	# 小页里的「返回 / 完成 / 查看完整说明」在构建时已用回调绑定（_page_*_btn 的 cb 参数），
	# 这里不能再 connect 一次，否则 Signal 已连接报错

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
		_build_hand_reorder_button()
		if hint_button:
			hint_button.toggled.connect(_on_hint_toggled)
		if quit_button:
			quit_button.pressed.connect(_on_quit_game)
		if help_btn:
			help_btn.pressed.connect(_on_show_help)
		# 工具行（提示 / 帮助 / 退出）：接管引擎默认主题 + 几何归一，见「八之四」
		_style_game_tool_buttons()

	# 帮助中心（P5）：单页 + 3 Tab + 滚动 + 卡片，全部代码生成（不改 Main.tscn）
	help_page = _build_help_page()

	# 触屏档（B）：页面级按钮统一补到 48px 高 + 字号 +2。
	# 这些页面的按钮尺寸由各调用点手写（220×56 / 150×38 / 270×32 …），
	# 逐个改调用点既啰嗦又容易漏；改为构建完成后过一遍
	# （_touch_ui = false 时函数第一行就 return，桌面与 24 套测试完全不受影响）。
	_apply_touch_sizing(start_page)
	_apply_touch_sizing(end_page)
	_apply_touch_sizing(get_node_or_null("TutorialPage"))
	_apply_touch_sizing(help_page)
	_apply_touch_sizing(_supp_rules_page)


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


# 开始页控件查找：P6 起人数框 / 规则开关 / 补充规则入口都挂在 SettingsCard 卡片内，
# 不再是 StartPage 的直接子节点 → 统一用递归查找，避免又退回「按路径取不到 = 静默失效」
func _start_child(node_name: String) -> Node:
	if start_page == null or not is_instance_valid(start_page):
		return null
	return start_page.find_child(node_name, true, false)


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
#       mini_card / mini_card_hover / button / tab_on / tab_off
#       toast_warning / toast_info
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
		"tab_on":
			# 帮助中心 Tab（选中）：白底 + 底部 3px 蓝色下划线
			_style_base(sb, Color(1.0, 1.0, 1.0, 1.0), Color(0, 0, 0, 0), 0, 0, false)
			sb.border_color = HELP_C_TAB_ON
			sb.border_width_bottom = 3
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
		"tab_off":
			# 帮助中心 Tab（未选中）：透明底 + 无描边
			_style_base(sb, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, false)
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
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
# -------- 页面淡入基础设施（P3） --------
# 根节点下的常驻同色底：页面淡入时 alpha 降到 0 露出的仍是 #E6F0FA，
# 因此不会闪出窗口默认清屏色（深灰）。挂在根节点而非 GamePage，
# 因为 GamePage 自身在切换时会被隐藏。
func _ensure_page_backdrop() -> void:
	if get_node_or_null("PageBackdrop") != null:
		return
	var bg := ColorRect.new()
	bg.name = "PageBackdrop"
	bg.color = PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(bg, 0)


func _all_pages() -> Array:
	return [
		start_page, game_page, end_page, help_page,
		get_node_or_null("TutorialPage"),
	]


# 目标页淡入；其余页 alpha 复位（避免「淡入中途被切走」留下半透明页）
func _fade_in_page(page) -> void:
	if page == null or not is_instance_valid(page):
		return
	for p in _all_pages():
		if p != null and is_instance_valid(p) and p != page:
			p.modulate.a = 1.0
	if _page_fade_tween != null and _page_fade_tween.is_valid():
		_page_fade_tween.kill()
	page.modulate.a = 0.0
	_page_fade_tween = create_tween()
	_page_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_page_fade_tween.tween_property(page, "modulate:a", 1.0, PAGE_FADE_MS / 1000.0)


func _show_start_page() -> void:
	_close_supp_rules()   # 从结束页 / 帮助页回来时不能还停在上一次打开的小页上
	if start_page: start_page.visible = true
	if game_page: game_page.visible = false
	if end_page: end_page.visible = false
	var tut_page = get_node_or_null("TutorialPage")
	if help_page: help_page.visible = false
	if tut_page: tut_page.visible = false
	_ensure_end_button_connected(_show_start_page)

	# 回到主界面时清空上一局日志，避免残留
	log_lines.clear()
	if log_label:
		log_label.text = "游戏日志:"
	_fade_in_page(start_page)
	_animate_start_page()   # 子节点错峰淡入 + 装饰牌浮动（不触碰 start_page.modulate）

func _on_show_help() -> void:
	if help_page:
		help_page.visible = true
		# 游戏内「帮助」按钮固定从「游戏规则」开始；补充规则有开始页专门入口
		_set_help_tab(0)
	if game_page: game_page.visible = false
	_fade_in_page(help_page)

func _on_show_tutorial_page() -> void:
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = true
	if start_page: start_page.visible = false
	if end_page: end_page.visible = false
	_fade_in_page(tut_page)
	_page_deco_float(tut_page)
	_animate_page_intro(tut_page, [
		"TutorialTitle", "TutorialSubtitle", "TutorialAccent",
		"Tutorial0Btn", "Tutorial1Btn", "Tutorial2Btn", "TutorialBackBtn",
	])

func _on_tutorial_back() -> void:
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	if start_page: start_page.visible = true
	if end_page: end_page.visible = false
	_fade_in_page(start_page)
	_animate_start_page()

func _on_help_back() -> void:
	if help_page: help_page.visible = false
	if start_page and start_page.visible:
		pass   # 从开始页打开帮助，返回开始页
	elif game_page and game_page.visible:
		game_page.visible = true  # 游戏中的帮助，返回游戏页
	else:
		if game_page: game_page.visible = true
	# 只有「游戏页从隐藏 → 可见」需要淡入；从开始页打开帮助时开始页一直在下层，无需动画
	if game_page and game_page.visible:
		_fade_in_page(game_page)

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
	if help_page == null:
		return
	if not help_page.visible:
		help_page.visible = true
		if game_page: game_page.visible = false
		_set_help_tab(idx)
		_fade_in_page(help_page)
		return
	_set_help_tab(idx)


# ============================================================
# 五之一、开始页（P6：全部代码生成 + 装饰美术）
# ============================================================
# 设计要点
#   1. Main.tscn 只保留 StartPage 空容器，子节点全部由 _build_start_page() 生成，
#      节点名与旧场景完全一致 → _setup_pages()/_init_game()/_on_start_game() 零改动
#   2. 装饰全部程序化（45° 渐变带 + 元素水印 + 倾斜装饰牌），不依赖任何图片素材；
#      文案里的化学式一律用 ASCII（H2O / CO2），避免默认中文字体缺下标字形
#   3. 只动子节点的 modulate / position，绝不动 start_page.modulate
#      （verify_motion 断言页面级 modulate 的淡入语义，动了就会误伤）
const START_FS_TITLE := 52
const START_FS_SUB := 18
const START_FS_LABEL := 18
const START_FS_META := 13
const START_C_TITLE := Color(0.169, 0.2, 0.251, 1.0)     # #2B3340 主标题
const START_C_SUB := Color(0.42, 0.55, 0.67, 1.0)        # #6B8CAB 副标题
const START_C_ACCENT := Color(0.176, 0.478, 0.702, 1.0)  # #2D7AB3 主题蓝（与帮助页一致）
const START_C_ACCENT_DARK := Color(0.13, 0.38, 0.58, 1.0)
const START_C_MUTED := Color(0.451, 0.498, 0.565, 1.0)   # #737F90 次要文字
const START_C_WATERMARK := Color(0.176, 0.478, 0.702, 0.12)

# 页面入场补间（开始页 / 结束页 / 教学引导页共用一套错峰淡入，切页时统一 kill）
var _page_intro_tweens: Array = []

# 结束页（P8：子节点全部代码生成，与开始页同一套画风）
var _end_card: Panel = null
var _end_title: Label = null
var _end_status_bar: Panel = null
var _end_stat_values: Array = []
var _end_restart_btn: Button = null
var _end_tutorial_btn: Button = null
var _end_rule_note: Label = null

# 补充规则小页（P10）：整页容器 / 元素池统计 / 9 个元素 chip
var _supp_rules_page: Control = null
var _supp_element_stats: Label = null
var _supp_element_chips: Dictionary = {}


func _build_start_page() -> void:
	if not start_page:
		return
	# 场景里若残留静态子节点（老版本 Main.tscn），先整段清掉，保证只有一套 UI
	for c in start_page.get_children():
		start_page.remove_child(c)
		c.queue_free()
	_start_page_bg()
	_start_page_decor()
	_start_page_title()
	_start_page_settings()
	_start_page_buttons()
	# P10：补充规则小页（盖在开始页之上，默认隐藏）
	_build_supp_rules_page()


# -------- 背景：同色底 + 45° 渐变带 --------
func _start_page_bg() -> void:
	_page_bg_into(start_page, "StartPageBg", "GradientBand")


# 开始页 / 补充规则小页共用：渐变背景（只换节点名）
func _page_bg_into(parent: Control, bg_name: String, band_name: String) -> void:
	var bg := ColorRect.new()
	bg.name = bg_name
	bg.color = PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var grad := Gradient.new()
	grad.set_color(0, PAGE_BG_COLOR)
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


# -------- 装饰：元素水印 + 5 张倾斜装饰牌 --------
func _start_page_decor() -> void:
	var marks := Control.new()
	marks.name = "Watermarks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_page.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var specs := [
		{"t": "H2O", "p": Vector2(34, 60), "fs": 76},
		{"t": "CO2", "p": Vector2(880, 34), "fs": 64},
		{"t": "NaCl", "p": Vector2(96, 520), "fs": 54},
		{"t": "CH4", "p": Vector2(946, 540), "fs": 58},
		{"t": "O2", "p": Vector2(520, 596), "fs": 44},
	]
	for s in specs:
		var lb := Label.new()
		lb.text = s["t"]
		lb.add_theme_font_size_override("font_size", int(s["fs"]))
		lb.add_theme_color_override("font_color", START_C_WATERMARK)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.position = s["p"]
		marks.add_child(lb)

	var holder := Control.new()
	holder.name = "DecorCards"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_page.add_child(holder)
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

	var style := _make_panel_style("card")
	style.bg_color = Color(1, 1, 1, 0.9)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var card = _help_find_card(sym)
	var sym_col := START_C_TITLE
	var name_cn := "元素"
	var num := 0
	if card != null:
		sym_col = _help_symbol_color(card)
		name_cn = card.name_cn
		num = card.atomic_number

	var l_num := _start_label(str(num), 12, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	l_num.position = Vector2(8, 6)
	l_num.size = Vector2(40, 16)
	panel.add_child(l_num)

	var l_sym := _start_label(sym, 32, sym_col, HORIZONTAL_ALIGNMENT_CENTER)
	l_sym.position = Vector2(0, 26)
	l_sym.size = Vector2(94, 40)
	panel.add_child(l_sym)

	var l_name := _start_label(name_cn, 13, START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	l_name.position = Vector2(0, 72)
	l_name.size = Vector2(94, 18)
	panel.add_child(l_name)

	var l_w := _start_label("%.1f" % (card.atomic_weight if card != null else 0.0), 12,
		START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l_w.position = Vector2(0, 94)
	l_w.size = Vector2(94, 16)
	panel.add_child(l_w)

	return panel


func _start_label(text: String, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	lb.horizontal_alignment = align
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


# -------- 标题区：主标题 + 英文副标题 + 强调条 + 元信息 --------
func _start_page_title() -> void:
	var title := _start_label("化学碰撞", START_FS_TITLE, START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "StartTitle"
	start_page.add_child(title)
	title.position = Vector2(0, 92)
	title.size = Vector2(1152, 64)

	var sub := _start_label("CHEMICAL COLLISION", START_FS_SUB, START_C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "StartSubtitle"
	start_page.add_child(sub)
	sub.position = Vector2(0, 160)
	sub.size = Vector2(1152, 26)

	var accent := ColorRect.new()
	accent.name = "StartAccent"
	accent.color = START_C_ACCENT
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_page.add_child(accent)
	accent.position = Vector2(540, 196)
	accent.size = Vector2(72, 4)

	var meta := _start_label("29 种元素 · 182 张牌 · 3-8 人同屏 · 出完手牌即胜",
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	meta.name = "StartMeta"
	start_page.add_child(meta)
	meta.position = Vector2(0, 210)
	meta.size = Vector2(1152, 20)


# -------- 设置卡：人数 / AI 数 / 补充规则入口（P10 起四条补充规则收进独立小页）--------
func _start_page_settings() -> void:
	var card := Panel.new()
	card.name = "SettingsCard"
	card.position = Vector2(266, 246)
	card.size = Vector2(620, 210)
	var cs := _make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.94)
	card.add_theme_stylebox_override("panel", cs)
	start_page.add_child(card)

	card.add_child(_start_setting_label("PlayerCountLabel", "总玩家人数", Vector2(32, 26)))
	var ps := _start_make_spin(3, 8, 4, "PlayerCountSpin")
	ps.position = Vector2(300, 20)
	ps.size = Vector2(150, 38)
	card.add_child(ps)

	card.add_child(_start_setting_label("AiCountLabel", "AI 人数", Vector2(32, 72)))
	var ai_s := _start_make_spin(1, 3, 3, "AiCountSpin")
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
	var entry := _start_make_ghost("SupplementaryHelpBtn", "补充规则 · 默认 ▸",
		Vector2(32, 128), Vector2(300, 34))
	entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	entry.tooltip_text = "有机物胜利 / 顺序牌型 / 允许卤族互化 / 元素限制"
	card.add_child(entry)

	var sum := _start_label("", START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	sum.name = "SuppRulesSummary"
	sum.position = Vector2(32, 170)
	sum.size = Vector2(556, 20)
	card.add_child(sum)

	# 勾选反馈写在这里：开始页看不到 GamePage 的 InfoLabel
	var rule_hint := _start_label("", START_FS_META, START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	rule_hint.name = "StartRuleHint"
	start_page.add_child(rule_hint)
	rule_hint.position = Vector2(266, 462)
	rule_hint.size = Vector2(620, 20)
	rule_hint.modulate.a = 0.0


func _start_setting_label(node_name: String, text: String, pos: Vector2) -> Label:
	var lb := _start_label(text, START_FS_LABEL, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	lb.name = node_name
	lb.position = pos
	lb.size = Vector2(230, 32)
	return lb


# -------- 按钮区 --------
func _start_page_buttons() -> void:
	start_button = _start_make_primary("开始游戏", Vector2(446, 486), Vector2(260, 52))
	start_page.add_child(start_button)
	start_page.add_child(_start_make_secondary("TutorialBtn", "教学引导", Vector2(446, 546), Vector2(260, 46)))
	start_page.add_child(_start_make_ghost("ExitButton", "退出程序", Vector2(476, 598), Vector2(200, 34)))


# ============================================================
# 五之二、补充规则小页（P10：四条补充规则合成一小页）
# ============================================================
# 为什么单独一页：SettingsCard 里已有「总人数 / AI 人数 / 开始游戏」三块，
# 再加第 4 条补充规则就会把开局按钮挤到卡外（旧布局 4 个开关已占满 210px 高的卡）。
# 这一页 = 4 张规则卡 + 元素池（前 20 号固定 / 9 种扩展可勾选）+ 说明入口。
func _build_supp_rules_page() -> void:
	var page := Control.new()
	page.name = "SuppRulesPage"
	page.visible = false
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	start_page.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_supp_rules_page = page
	_page_bg_into(page, "SuppRulesBg", "SuppRulesBand")

	var back := _page_ghost_btn("‹ 返回", _close_supp_rules, Vector2(140, 34), "SuppRulesBackBtn", 15)
	back.position = Vector2(46, 34)
	page.add_child(back)

	var title := _start_label("补充规则", 34, START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "SuppRulesTitle"
	title.position = Vector2(0, 62)
	title.size = Vector2(1152, 46)
	page.add_child(title)

	var sub := _start_label("默认全部关闭；勾选后仅对下一局生效",
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "SuppRulesSubtitle"
	sub.position = Vector2(0, 110)
	sub.size = Vector2(1152, 20)
	page.add_child(sub)

	_supp_rule_card(page, "OrganicCheckBox", "有机物胜利",
		"打出 CH4 / C2H6 / C3H8 或单一卤代物立即获胜", Vector2(46, 146))
	_supp_rule_card(page, "SequenceCheckBox", "顺序牌型",
		"≥3 张连续原子序数：抢牌权 + 反转方向 + 指定下家牌型", Vector2(586, 146))
	_supp_rule_card(page, "HalogenCheckBox", "允许卤族互化",
		"F/Cl/Br/I 之间可互相化合（如 ClF）；族炸始终不受影响", Vector2(46, 250))
	_supp_rule_card(page, "ElementLimitCheckBox", "元素限制",
		"牌库只保留前 20 号元素（H~Ca），可再挑副族 / 卤族加入", Vector2(586, 250))

	_build_element_pool(page)

	var supp_help_btn := _page_ghost_btn("查看完整说明 >", _on_help_show_supp,
		Vector2(240, 34), "SuppRulesHelpBtn", 15)
	supp_help_btn.position = Vector2(46, 570)
	page.add_child(supp_help_btn)

	var done := _page_primary_btn("完成", _close_supp_rules, Vector2(260, 44), "SuppRulesDoneBtn", 20)
	done.position = Vector2(846, 566)
	page.add_child(done)

	_sync_supp_rules_summary()


# 一张规则卡：标题做成 toggle 按钮（与旧开始页开关同一套样式），下面一行说明
func _supp_rule_card(page: Control, node_name: String, title: String, desc: String,
		pos: Vector2) -> Button:
	var card := Panel.new()
	card.name = node_name + "Card"
	card.position = pos
	card.size = Vector2(520, 92)
	var st := _make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.96)
	card.add_theme_stylebox_override("panel", st)
	page.add_child(card)

	var btn := _start_make_toggle(node_name, title, Vector2(18, 12))
	btn.size = Vector2(484, 34)
	btn.custom_minimum_size = Vector2(484, 34)
	btn.add_theme_font_size_override("font_size", 17)
	card.add_child(btn)

	var d := _start_label(desc, START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	d.position = Vector2(18, 52)
	d.size = Vector2(484, 32)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(d)
	return btn


# 元素池：前 20 号固定加入；9 种扩展元素（副族 7 + Br/I）按 chip 勾选
func _build_element_pool(page: Control) -> void:
	var area := Panel.new()
	area.name = "ElementPoolPanel"
	area.position = Vector2(46, 356)
	area.size = Vector2(1060, 168)
	var st := _make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.96)
	area.add_theme_stylebox_override("panel", st)
	page.add_child(area)

	var t := _start_label("元素池", 17, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	t.position = Vector2(20, 10)
	t.size = Vector2(160, 24)
	area.add_child(t)

	_supp_element_stats = _start_label("", START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_supp_element_stats.name = "ElementPoolStats"
	_supp_element_stats.position = Vector2(180, 12)
	_supp_element_stats.size = Vector2(860, 20)
	area.add_child(_supp_element_stats)

	var tip := _start_label("前 20 号元素（H ~ Ca）固定加入；勾选下面的元素可额外加进牌库",
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	tip.name = "ElementPoolTip"
	tip.position = Vector2(20, 36)
	tip.size = Vector2(1020, 18)
	area.add_child(tip)

	# chip 104×28 + 间距 8 → 9 个排一行（9*104 + 8*8 = 1000，池内宽 1020）
	var items := CardDatabaseScript.get_optional_elements()
	for i in range(items.size()):
		var info: Dictionary = items[i]
		var sym := str(info["symbol"])
		var chip := _start_make_toggle("ElementChip_" + sym,
			"%s %s · %d" % [sym, str(info["name_cn"]), int(info["number"])],
			Vector2(20 + i * 112, 62))
		chip.add_theme_font_size_override("font_size", 13)
		# 104 宽 + 13px：内边距从 toggle 默认的 12 收到 10，避免 "Cr 铬 · 24" 贴边
		for st_name in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := chip.get_theme_stylebox(st_name) as StyleBoxFlat
			if sb != null:
				sb.content_margin_left = 10
				sb.content_margin_right = 10
		chip.tooltip_text = "%s%s（原子序数 %d）；勾选后加入牌库" % [
			str(info["group_label"]), sym, int(info["number"])]
		area.add_child(chip)
		# 尺寸必须在入树后设置：树外 update_minimum_size() 不生效，
		# 会把 size 夹回 _start_make_toggle 的 270×32
		chip.custom_minimum_size = Vector2(104, 28)
		chip.size = Vector2(104, 28)
		_supp_element_chips[sym] = chip

	# 分隔线 + 基础池清单：数据取自 CardDatabase，后续新增元素自动跟随，无需改 UI
	var div := ColorRect.new()
	div.name = "ElementPoolDivider"
	div.color = Color(0.886, 0.914, 0.945, 1.0)
	div.position = Vector2(20, 96)
	div.size = Vector2(1020, 1)
	area.add_child(div)

	var base_title := _start_label("固定加入 · 前 20 号元素（H ~ Ca）",
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	base_title.name = "ElementPoolBaseTitle"
	base_title.position = Vector2(20, 102)
	base_title.size = Vector2(1020, 18)
	area.add_child(base_title)

	var base_syms := CardDatabaseScript.get_base_element_symbols()
	for line in range(2):
		var lbl := _start_label(_symbols_joined(base_syms.slice(line * 10, line * 10 + 10)),
			13, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
		lbl.name = "ElementPoolBase%d" % line
		lbl.position = Vector2(20, 122 + line * 20)
		lbl.size = Vector2(1020, 18)
		area.add_child(lbl)


# 把符号数组拼成 "H  ·  He  ·  Li" 形式（元素池基础清单用）
func _symbols_joined(syms: Array) -> String:
	var parts := PackedStringArray()
	for s in syms:
		parts.append(str(s))
	return "  ·  ".join(parts)


# -------- 按钮三件套（P8：开始页 / 结束页 / 教学引导页共用的唯一样式来源）--------
# 主按钮：主题蓝底 + 深蓝边；hover 提亮 + 蓝色光晕
func _page_primary_btn(text: String, cb: Callable, sz: Vector2,
		node_name: String = "", fs: int = 20) -> Button:
	var b := _mkb(text, cb, false)
	if node_name != "":
		b.name = node_name
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fs)
	var n: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	n.bg_color = START_C_ACCENT
	n.border_color = START_C_ACCENT_DARK
	b.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = START_C_ACCENT.lightened(0.12)
	h.border_color = START_C_ACCENT
	h.shadow_color = Color(0.176, 0.478, 0.702, 0.5)
	h.shadow_size = 8
	h.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate()
	p.bg_color = START_C_ACCENT_DARK
	b.add_theme_stylebox_override("pressed", p)
	b.pivot_offset = sz * 0.5
	return b


# 次按钮：白底 + 主题蓝描边 + 蓝字
func _page_secondary_btn(text: String, cb: Callable, sz: Vector2,
		node_name: String = "", fs: int = 19) -> Button:
	var b := _mkb(text, cb, false)
	if node_name != "":
		b.name = node_name
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fs)
	var n: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	n.bg_color = Color(1, 1, 1, 0.96)
	n.border_color = START_C_ACCENT
	n.set_border_width_all(BORDER_W_ACTIVE)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_color_override("font_color", START_C_ACCENT)
	b.add_theme_color_override("font_hover_color", START_C_ACCENT_DARK)
	b.add_theme_color_override("font_pressed_color", START_C_ACCENT_DARK)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.92, 0.96, 1.0, 1.0)
	b.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate()
	p.bg_color = Color(0.85, 0.92, 0.98, 1.0)
	b.add_theme_stylebox_override("pressed", p)
	b.pivot_offset = sz * 0.5
	return b


# 幽灵按钮：透明底 + 灰字，hover 蓝字 + 10% 蓝底
func _page_ghost_btn(text: String, cb: Callable, sz: Vector2,
		node_name: String = "", fs: int = 16) -> Button:
	var b := _mkb(text, cb, false)
	if node_name != "":
		b.name = node_name
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", START_C_MUTED)
	b.add_theme_color_override("font_hover_color", START_C_ACCENT)
	b.add_theme_color_override("font_pressed_color", START_C_ACCENT_DARK)
	for st in ["normal", "pressed"]:
		var s := _make_panel_style("tab_off")
		s.bg_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(st, s)
	var h := _make_panel_style("tab_off")
	h.bg_color = Color(0.176, 0.478, 0.702, 0.1)
	b.add_theme_stylebox_override("hover", h)
	b.pivot_offset = sz * 0.5
	return b


# -------- 开始页按钮薄壳：保持旧签名，视觉/动效零变化 --------
func _start_make_primary(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := _page_primary_btn(text, func() -> void: pass, sz, "StartButton", 22)
	b.position = pos
	return b


func _start_make_secondary(node_name: String, text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := _page_secondary_btn(text, func() -> void: pass, sz, node_name, 19)
	b.position = pos
	return b


func _start_make_ghost(node_name: String, text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := _page_ghost_btn(text, func() -> void: pass, sz, node_name, 16)
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
	le.add_theme_color_override("font_color", START_C_TITLE)
	var n := _make_panel_style("mini_card")
	n.bg_color = Color(1, 1, 1, 1)
	n.content_margin_left = 10
	n.content_margin_right = 6
	n.content_margin_top = 4
	n.content_margin_bottom = 4
	le.add_theme_stylebox_override("normal", n)
	var f: StyleBoxFlat = n.duplicate()
	f.border_color = BORDER_FOCUS
	f.set_border_width_all(BORDER_W_ACTIVE)
	le.add_theme_stylebox_override("focus", f)

	# 内部上下箭头按钮：去掉默认灰块，白卡面上更干净
	for child in sp.get_children():
		if child is Button:
			for st in ["normal", "hover", "pressed"]:
				var s := _make_panel_style("tab_off")
				s.bg_color = Color(0, 0, 0, 0) if st != "hover" else Color(0.176, 0.478, 0.702, 0.12)
				child.add_theme_stylebox_override(st, s)
	return sp


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
	b.add_theme_color_override("font_color", START_C_TITLE)
	b.add_theme_color_override("font_hover_color", START_C_TITLE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1, 1))

	var off := _make_panel_style("mini_card")
	off.bg_color = Color(1, 1, 1, 1)
	off.content_margin_left = 12
	off.content_margin_right = 12
	off.content_margin_top = 4
	off.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", off)
	var hover: StyleBoxFlat = off.duplicate()
	hover.bg_color = Color(0.96, 0.98, 1.0, 1.0)
	hover.border_color = BORDER_FOCUS
	b.add_theme_stylebox_override("hover", hover)

	var on := _make_panel_style("mini_card")
	on.bg_color = START_C_ACCENT
	on.border_color = START_C_ACCENT_DARK
	on.border_width_left = 4
	on.content_margin_left = 12
	on.content_margin_right = 12
	on.content_margin_top = 4
	on.content_margin_bottom = 4
	b.add_theme_stylebox_override("pressed", on)
	var on_hover: StyleBoxFlat = on.duplicate()
	on_hover.bg_color = START_C_ACCENT.lightened(0.08)
	b.add_theme_stylebox_override("hover_pressed", on_hover)

	var sk := _make_panel_style("tab_off")
	b.add_theme_stylebox_override("focus", sk)

	b.mouse_entered.connect(_on_button_hover_scale.bind(b, true))
	b.mouse_exited.connect(_on_button_hover_scale.bind(b, false))
	b.button_down.connect(_on_button_press_scale.bind(b, true))
	b.button_up.connect(_on_button_press_scale.bind(b, false))
	b.pivot_offset = Vector2(135, 16)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	return b


# -------- 动效：入场错峰淡入 + 装饰牌缓慢浮动（只动子节点，不动页面级 modulate）--------
func _animate_start_page() -> void:
	if not start_page:
		return
	_page_deco_float(start_page)
	_animate_page_intro(start_page, [
		"StartTitle", "StartSubtitle", "StartAccent", "StartMeta", "DecorCards",
		"SettingsCard", "StartRuleHint", "StartButton", "TutorialBtn", "ExitButton",
	])


# 通用：任意页面子节点错峰淡入（第 i 个节点延迟 i×50ms；每个节点一条独立补间，
# 淡入与上浮并行，互不排队 —— 共用一个 tween 会串成 3 秒）
# 只碰子节点的 modulate / position；页面级 modulate 归 _fade_in_page 独占
func _animate_page_intro(page: Control, order: Array) -> void:
	if page == null or not is_instance_valid(page):
		return
	for t in _page_intro_tweens:
		if t is Tween and t.is_valid():
			t.kill()
	_page_intro_tweens.clear()
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
		_page_intro_tweens.append(t)
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


# 勾选补充规则 / 人数自动纠正时在开始页内联提示 2 秒（GamePage 的 InfoLabel 此刻不可见）
func _start_flash_rule_hint(text: String, col: Color = START_C_ACCENT) -> void:
	if not start_page:
		return
	var lb = start_page.get_node_or_null("StartRuleHint")
	if lb == null:
		return
	lb.add_theme_color_override("font_color", col)
	lb.text = text
	lb.modulate.a = 1.0
	# get_meta(name, null) 在 Godot 里等同于单参数调用（仍然报错），改判 has_meta
	var old = lb.get_meta("tween") if lb.has_meta("tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var t := lb.create_tween()
	t.tween_interval(1.4)
	t.tween_property(lb, "modulate:a", 0.0, 0.5)
	lb.set_meta("tween", t)


# ============================================================
# 五之二、帮助中心（P5：单页 + 3 Tab + 滚动容器 + 卡片）
# ============================================================
# 设计要点
#   1. 完全代码生成：Main.tscn 不新增任何节点（旧 3 个帮助页保留但 visible=false）
#   2. 每个 Tab 一个 ScrollContainer + VBoxContainer，切换只改 visible
#      → 各 Tab 保留自己的滚动位置，不会互相顶动
#   3. 卡片懒加载：首次切到某 Tab 才构建内容（_help_filled），避免开局就建 20+ 卡片
#   4. 切 Tab 绝不调用 _fade_in_page（页面级淡入只用于「进出帮助中心」）
#      verify_motion 会断言切 Tab 不产生淡入 tween
const HELP_HEADER_H := 56.0        # 顶部标题栏高度
const HELP_TABBAR_H := 48.0        # Tab 栏高度
const HELP_MARGIN := 24.0          # 左右安全边距（与游戏页对齐）
const HELP_CARD_GAP := 16.0        # 卡片间距
const HELP_CARD_MIN_W := 500.0     # 两列卡片最小宽度（1152 宽下实际约 544/列）
const HELP_BODY_TOP := HELP_HEADER_H + HELP_TABBAR_H + 12.0
const HELP_ACCENT_BAR_W := 4.0     # 卡片标题左侧强调色条宽度
const HELP_FS_TITLE := 17          # 卡片标题
const HELP_FS_SUB := 15            # 卡内小标题
const HELP_FS_BODY := 14           # 正文 / 条目 / 警示
const HELP_FS_FX := 13             # 示例 / 化学式
const HELP_C_HEADER := Color(0.173, 0.243, 0.314, 1.0)   # #2C3E50 标题栏
const HELP_C_TEXT := Color(0.169, 0.2, 0.251, 1.0)       # #2B3340 正文
const HELP_C_SUB := Color(0.173, 0.243, 0.314, 1.0)      # #2C3E50 小标题
const HELP_C_EX := Color(0.42, 0.45, 0.49, 1.0)          # #6B7280 示例
const HELP_C_WARN := Color(0.753, 0.224, 0.169, 1.0)     # #C0392B 警示
const HELP_C_TAB_ON := Color(0.176, 0.478, 0.702, 1.0)   # 选中 Tab 文字/下划线
const HELP_C_TAB_OFF := Color(0.478, 0.522, 0.584, 1.0)  # 未选中 Tab 文字
const HELP_C_TABBAR_BG := Color(1.0, 1.0, 1.0, 1.0)
const HELP_C_DIVIDER := Color(0.85, 0.88, 0.92, 1.0)


func _build_help_page() -> Control:
	help_tab_btns.clear()
	help_scrolls.clear()
	help_bodies.clear()
	_help_filled = [false, false, false]
	_help_tab = 0

	var page := Control.new()
	page.name = "HelpPage"
	page.visible = false
	page.z_index = Z_CONTENT
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.name = "HelpBg"
	bg.color = PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- 顶部标题栏：深蓝灰 + 白字标题 + 右侧返回按钮 ----
	var header := ColorRect.new()
	header.name = "HelpHeader"
	header.color = HELP_C_HEADER
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(header)
	_set_top_bar_rect(header, 0.0, HELP_HEADER_H)

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
	title.offset_left = HELP_MARGIN
	title.offset_right = HELP_MARGIN + 240.0
	title.offset_top = 0.0
	title.offset_bottom = 0.0

	var back := _mkb("← 返回游戏", _on_help_back, false)
	back.name = "HelpBackBtn"
	back.custom_minimum_size = Vector2(132, 36)
	header.add_child(back)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.anchor_top = 0.0
	back.anchor_bottom = 0.0
	back.offset_left = -(HELP_MARGIN + 132.0)
	back.offset_right = -HELP_MARGIN
	back.offset_top = (HELP_HEADER_H - 36.0) * 0.5
	back.offset_bottom = back.offset_top + 36.0

	# ---- Tab 栏：白底 + 底部 1px 分隔线 + 3 个等宽 Tab ----
	var tabbar := ColorRect.new()
	tabbar.name = "HelpTabBar"
	tabbar.color = HELP_C_TABBAR_BG
	tabbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(tabbar)
	_set_top_bar_rect(tabbar, HELP_HEADER_H, HELP_TABBAR_H)

	var divider := ColorRect.new()
	divider.color = HELP_C_DIVIDER
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
	tab_row.offset_left = HELP_MARGIN
	tab_row.offset_right = -HELP_MARGIN
	tab_row.offset_top = 0.0
	tab_row.offset_bottom = 0.0

	var labels: Array = HelpContentScript.get_tab_labels()
	for i in range(labels.size()):
		var tb := Button.new()
		tb.name = "HelpTab%d" % i
		tb.text = labels[i]
		tb.custom_minimum_size = Vector2(180, 40)
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 16)
		tb.pressed.connect(_set_help_tab.bind(i))
		tab_row.add_child(tb)
		help_tab_btns.append(tb)

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
		scroll.offset_left = HELP_MARGIN
		scroll.offset_right = -HELP_MARGIN
		scroll.offset_top = HELP_BODY_TOP
		scroll.offset_bottom = -16.0

		var body := VBoxContainer.new()
		body.name = "HelpBody%d" % i
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", int(HELP_CARD_GAP))
		scroll.add_child(body)

		help_scrolls.append(scroll)
		help_bodies.append(body)

	for i in range(help_tab_btns.size()):
		_style_help_tab(help_tab_btns[i], i == 0)

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
	var style := _make_panel_style("tab_on" if selected else "tab_off")
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var col := HELP_C_TAB_ON if selected else HELP_C_TAB_OFF
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_hover_color", col)
	btn.add_theme_color_override("font_pressed_color", col)
	# 选中态加粗视觉：字号放大 1px（主题无粗体字体，靠尺寸差区分）
	btn.add_theme_font_size_override("font_size", 17 if selected else 16)


# 切 Tab：只改 visible + 懒加载内容；绝不做页面淡入
func _set_help_tab(idx: int) -> void:
	if help_page == null or idx < 0 or idx >= help_tab_btns.size():
		return
	_help_tab = idx
	for i in range(help_tab_btns.size()):
		_style_help_tab(help_tab_btns[i], i == idx)
		if i < help_scrolls.size():
			help_scrolls[i].visible = (i == idx)
	if idx < _help_filled.size() and not _help_filled[idx]:
		_fill_help_tab(idx)
		_help_filled[idx] = true


# 构建某个 Tab 的卡片（首次切到该 Tab 时执行一次）
func _fill_help_tab(idx: int) -> void:
	var tabs: Array = HelpContentScript.get_tabs()
	if idx < 0 or idx >= tabs.size() or idx >= help_bodies.size():
		return
	var body: VBoxContainer = help_bodies[idx]
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
	grid.add_theme_constant_override("h_separation", int(HELP_CARD_GAP))
	grid.add_theme_constant_override("v_separation", int(HELP_CARD_GAP))
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
	bottom.add_theme_constant_override("h_separation", int(HELP_CARD_GAP))
	bottom.add_theme_constant_override("v_separation", int(HELP_CARD_GAP))

	for i in range(cards.size()):
		var slot := _make_help_card(cards[i])
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
	var style := _make_panel_style("card")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(HELP_CARD_MIN_W, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	card.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)

	var accent := ColorRect.new()
	accent.color = data.get("accent", HELP_C_TAB_ON)
	accent.custom_minimum_size = Vector2(HELP_ACCENT_BAR_W, 18)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(accent)

	var title := Label.new()
	title.text = data.get("title", "")
	title.add_theme_font_size_override("font_size", HELP_FS_TITLE)
	title.add_theme_color_override("font_color", HELP_C_SUB)
	head.add_child(title)

	vb.add_child(_make_help_hsep())

	for line in data.get("lines", []):
		_append_help_line(vb, line)
	return card


# 1px 分隔线（卡片标题与正文之间）
func _make_help_hsep() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = HELP_C_DIVIDER
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
	var fs := HELP_FS_BODY
	var col := HELP_C_TEXT
	var indent := 0
	match kind:
		"sub":
			fs = HELP_FS_SUB
			col = HELP_C_SUB
		"li":
			text = "· " + text
			indent = 4
		"ex":
			fs = HELP_FS_FX
			col = HELP_C_EX
			indent = 14
		"warn":
			text = "⚠ " + text
			col = HELP_C_WARN
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
	var style := _make_panel_style("mini_card")
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
	var l_num := _help_label(str(card.atomic_number), 11, Color(0.35, 0.37, 0.4, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	l_num.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l_num)
	top.add_child(_help_label(card.group, 11, Color(0.32, 0.34, 0.38, 1.0), HORIZONTAL_ALIGNMENT_RIGHT))

	vb.add_child(_help_label(card.symbol, 26, _help_symbol_color(card), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_help_label(card.name_cn, 13, HELP_C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if show_valence:
		vb.add_child(_help_label(_help_valence_text(card), 12,
			Color(0.55, 0.2, 0.2, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		vb.add_child(_help_label("×%d" % HelpContentScript.get_element_copies(card.symbol), 12,
			Color(0.36, 0.39, 0.44, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_help_label("%.1f" % card.atomic_weight, 11, Color(0.45, 0.48, 0.52, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	return panel


# 常见化合价文本：正价带 +、负价带 -（与手牌卡面 CardValence 一致）
# 迷你卡宽度只有 96，多价元素（Cl 有 5 个）只显示前 2 个 + 「…」，避免撑破卡片
func _help_valence_text(card) -> String:
	var parts: Array = []
	var total: int = card.common_valence.size()
	for i in range(mini(total, 2)):
		var v: int = card.common_valence[i]
		parts.append(("+%d" % v) if v > 0 else str(v))
	if parts.is_empty():
		return "—"
	return " ".join(parts) + ("…" if total > 2 else "")


# 图鉴专用符号色：原配色里稀有气体是 (0.95,0.95,0.95)，
# 在白底卡面上几乎不可见 → 亮度 > 0.90 的统一加深后使用
func _help_symbol_color(card) -> Color:
	var c: Color = _get_card_color(card)
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
	if _help_elements.is_empty():
		_help_elements = HelpContentScript.get_element_cards()
	return _help_elements


func _help_find_card(sym: String):
	for card in _help_element_cards():
		if card.symbol == sym:
			return card
	return null


# ============================================================
# 五之三、页面通用零件（P8：结束页 / 教学引导页与开始页共用同一套画风）
# ============================================================
# 45° 渐变带（同色底 → 白，左下最亮），开始页同款
func _page_gradient_band(page: Control) -> void:
	var grad := Gradient.new()
	grad.set_color(0, PAGE_BG_COLOR)
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
		lb.add_theme_color_override("font_color", START_C_WATERMARK)
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
		holder.add_child(_start_make_deco_card(c["s"], c["p"], c["a"]))


# 页面底 + 渐变带 + 水印 + 装饰牌（结束页 / 教学页共用的三段式背景）
func _page_backdrop(page: Control, bg_name: String, marks: Array, cards: Array) -> void:
	var bg := ColorRect.new()
	bg.name = bg_name
	bg.color = PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_gradient_band(page)
	_page_watermarks(page, marks)
	_page_deco_cards(page, cards)


# ============================================================
# 五之四、结束页（P8：结算卡 + 统计块 + 按钮组）
# ============================================================
# 设计要点
#   1. 与开始页同一套画风：同色底 + 45° 渐变带 + 水印 + 装饰牌 + 白卡（圆角 10 + 阴影）
#   2. 骨架只在 _build_end_page() 建一次；_show_end_page() 会被 _refresh_ui() 反复调用，
#      因此只填数据（幂等），绝不重建节点
#   3. 节点名 EndLabel / EndButton 保持不变 → _ensure_end_button_connected() 零改动
const END_CARD_POS := Vector2(256, 114)
const END_CARD_SIZE := Vector2(640, 420)
const END_C_STAT_BG := Color(0.949, 0.969, 0.992, 1.0)   # #F2F7FD 统计块浅蓝底
const END_C_DIVIDER := Color(0.851, 0.878, 0.910, 1.0)   # #D9E0E8 分隔线
const END_C_NEUTRAL := Color(0.604, 0.647, 0.694, 1.0)   # #9AA5B1 中途退出
const END_C_WARN := Color(0.906, 0.298, 0.235, 1.0)      # #E74C3C 初始化失败


func _build_end_page() -> void:
	if not end_page:
		return
	# 老版本 Main.tscn 的静态子节点整段清掉，保证只有一套 UI
	for c in end_page.get_children():
		end_page.remove_child(c)
		c.queue_free()
	_page_backdrop(end_page, "EndBg", [
		{"t": "H2O", "p": Vector2(30, 470), "fs": 72},
		{"t": "CO2", "p": Vector2(884, 60), "fs": 56},
		{"t": "NaCl", "p": Vector2(58, 40), "fs": 48},
		{"t": "O2", "p": Vector2(1000, 520), "fs": 44},
	], [
		{"s": "H", "p": Vector2(56, 300), "a": -0.13},
		{"s": "O", "p": Vector2(986, 330), "a": 0.12},
	])

	# -------- 结算卡 --------
	var card := Panel.new()
	card.name = "EndCard"
	card.position = END_CARD_POS
	card.size = END_CARD_SIZE
	var cs := _make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.96)
	card.add_theme_stylebox_override("panel", cs)
	end_page.add_child(card)
	_end_card = card

	# 顶部状态条：只留上方两个圆角，才能贴住卡片圆角不露直角
	var bar := Panel.new()
	bar.name = "EndStatusBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(END_CARD_SIZE.x, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = START_C_ACCENT
	bs.corner_radius_top_left = CARD_RADIUS
	bs.corner_radius_top_right = CARD_RADIUS
	bs.corner_detail = 6
	bar.add_theme_stylebox_override("panel", bs)
	card.add_child(bar)
	_end_status_bar = bar


	# -------- 结果标题 / 描述 / 分隔线 --------
	_end_title = _start_label("游戏结束", 36, START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	_end_title.name = "EndTitle"
	_end_title.position = Vector2(0, 34)
	_end_title.size = Vector2(END_CARD_SIZE.x, 48)
	card.add_child(_end_title)

	end_label = _start_label("", 18, START_C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	end_label.name = "EndLabel"
	end_label.position = Vector2(0, 88)
	end_label.size = Vector2(END_CARD_SIZE.x, 26)
	card.add_child(end_label)

	var div := ColorRect.new()
	div.name = "EndDivider"
	div.color = END_C_DIVIDER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	div.position = Vector2(32, 124)
	div.size = Vector2(END_CARD_SIZE.x - 64, 1)
	card.add_child(div)

	# -------- 统计块：总回合 / 剩余牌库 / 剩余手牌 --------
	var captions := ["总回合", "剩余牌库", "剩余手牌"]
	_end_stat_values.clear()
	for i in range(captions.size()):
		var tile := Panel.new()
		tile.name = "EndStat%d" % i
		tile.position = Vector2(38 + i * 196, 142)
		tile.size = Vector2(172, 76)
		tile.add_theme_stylebox_override("panel", _end_stat_style())
		card.add_child(tile)

		var val := _start_label("—", 26, START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
		val.name = "EndStat%dValue" % i
		val.position = Vector2(0, 10)
		val.size = Vector2(172, 34)
		tile.add_child(val)
		_end_stat_values.append(val)

		var cap := _start_label(captions[i], 13, START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		cap.name = "EndStat%dCaption" % i
		cap.position = Vector2(0, 46)
		cap.size = Vector2(172, 22)
		tile.add_child(cap)

	# -------- 按钮组：返回主页（主）/ 再来一局（次）/ 教学引导（幽灵）--------
	end_button = _page_primary_btn("返回主页", func() -> void: pass, Vector2(260, 50), "EndButton", 20)
	end_button.position = Vector2(92, 240)
	card.add_child(end_button)

	_end_restart_btn = _page_secondary_btn("再来一局", _on_end_restart, Vector2(180, 42),
		"EndRestartBtn", 17)
	_end_restart_btn.position = Vector2(368, 244)
	card.add_child(_end_restart_btn)

	_end_tutorial_btn = _page_ghost_btn("教学引导", _on_show_tutorial_page, Vector2(120, 30),
		"EndTutorialBtn", 15)
	_end_tutorial_btn.position = Vector2(260, 304)
	card.add_child(_end_tutorial_btn)

	_end_rule_note = _start_label("", 13, START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_end_rule_note.name = "EndRuleNote"
	_end_rule_note.position = Vector2(0, 346)
	_end_rule_note.size = Vector2(END_CARD_SIZE.x, 20)
	card.add_child(_end_rule_note)


func _end_stat_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = END_C_STAT_BG
	sb.set_corner_radius_all(8)
	sb.corner_detail = 6
	return sb


# 本局是否为教程局（level 1/2 或 level0 已进入引导流程）
func _is_tutorial_run() -> bool:
	return game_manager != null and (game_manager.tutorial_level >= 1
		or game_manager.tutorial_level0_phase >= 1)


# -------- 数据填充：把 game_manager 的状态映射到结算卡（幂等，只改文本 / 颜色 / 连接）--------
func _fill_end_page(custom_text: String) -> void:
	if not _end_card:
		return
	var is_tutorial := _is_tutorial_run()
	var w = game_manager.get_winner() if game_manager else null
	var head := "游戏结束"
	var head_col := START_C_ACCENT
	var desc := custom_text
	if w != null:
		var human_win: bool = not w.is_ai
		head = "胜利！" if human_win else "本局结束"
		head_col = START_C_ACCENT if human_win else START_C_SUB
		if desc == "":
			desc = "获胜者：%s" % w.player_name
	elif custom_text == "游戏已退出":
		head = "游戏已退出"
		head_col = END_C_NEUTRAL
		# 描述不复读标题：给出下一步动作
		if desc == custom_text:
			desc = "本局未分胜负，随时再来一局"
	elif custom_text != "":
		head_col = END_C_WARN
		head = custom_text
		if desc == custom_text:
			desc = "请返回主页重新开始"
	if desc == "":
		desc = "本局结束"
	if _end_title:
		_end_title.text = head
	if end_label:
		end_label.text = desc
	if _end_status_bar:
		var sb: StyleBoxFlat = _end_status_bar.get_theme_stylebox("panel")
		if sb:
			sb.bg_color = head_col

	# -------- 统计三件套：总回合 / 剩余牌库 / 剩余手牌 --------
	var turns := "—"
	var deck_left := "—"
	var hand_left := "—"
	if game_manager:
		turns = str(game_manager.turn_count)
		var db = game_manager.get_database()
		if db:
			deck_left = str(db.get_remaining_count())
		if w != null:
			hand_left = str(w.hand.size())
		else:
			var ps = game_manager.get_players()
			if ps.size() > 0:
				hand_left = str(ps[0].hand.size())
	var texts := [turns, deck_left, hand_left]
	for i in range(_end_stat_values.size()):
		if _end_stat_values[i]:
			_end_stat_values[i].text = texts[i]

	# -------- 规则回顾 --------
	if _end_rule_note:
		if game_manager:
			var org := "有机物 ✓" if game_manager.get_organic_rules_enabled() else "有机物 ✗"
			var seq := "顺序 ✓" if game_manager.get_sequence_rules_enabled() else "顺序 ✗"
			var hal := "卤族互化 ✓" if game_manager.get_halogen_exchange_allowed() else "卤族互化 ✗"
			var lim := "元素 %d 种" % game_manager.get_allowed_element_count()
			_end_rule_note.text = "本局规则：%s    %s    %s    %s" % [org, seq, hal, lim]
		else:
			_end_rule_note.text = ""

	# -------- 按钮去向：教程局回关卡列表，自由局回开始页 --------
	if end_button:
		_ensure_end_button_connected(_on_show_tutorial_page if is_tutorial else _show_start_page)
		end_button.text = "返回关卡" if is_tutorial else "返回主页"
	if _end_restart_btn:
		_end_restart_btn.text = "再试一次" if is_tutorial else "再来一局"
	if _end_tutorial_btn:
		_end_tutorial_btn.visible = not is_tutorial


# 「再来一局」：自由局按开始页当前设置重开；教程局重开同一关（level0 也传 0）
func _on_end_restart() -> void:
	if _is_tutorial_run():
		_on_start_tutorial(game_manager.tutorial_level)
	else:
		_on_start_game()


# ============================================================
# 五之五、教学引导页（P8：三张关卡卡 + 标题块 + 返回）
# ============================================================
# 整卡即按钮：Tutorial0Btn / 1 / 2 就是 720×104 的白卡本身（内部 Label 全部不参与拾取），
# 因此 _setup_pages() 里的 pressed.connect(_on_start_tutorial.bind(i)) 零改动
const TUT_CARD_X := 216.0
const TUT_CARD_W := 720.0
const TUT_CARD_H := 104.0
const TUT_CARD_GAP := 16.0
const TUT_CARD_Y0 := 176.0

var _tut_cards: Array = []


func _build_tutorial_page() -> void:
	var page = get_node_or_null("TutorialPage")
	if page == null:
		return
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	_page_backdrop(page, "TutorialBg", [
		{"t": "H2O", "p": Vector2(36, 430), "fs": 68},
		{"t": "CO2", "p": Vector2(896, 70), "fs": 54},
		{"t": "CH4", "p": Vector2(1000, 500), "fs": 46},
	], [
		{"s": "Cl", "p": Vector2(64, 96), "a": -0.12},
		{"s": "Na", "p": Vector2(984, 300), "a": 0.13},
	])

	# -------- 标题块（与开始页同档字号：40 / 16 / 72×4）--------
	var title := _start_label("教学引导", 40, START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "TutorialTitle"
	title.position = Vector2(0, 64)
	title.size = Vector2(1152, 52)
	page.add_child(title)

	var sub := _start_label("从认识牌面到族炸接炸，三步上手", 16, START_C_SUB,
		HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "TutorialSubtitle"
	sub.position = Vector2(0, 120)
	sub.size = Vector2(1152, 24)
	page.add_child(sub)

	var accent := ColorRect.new()
	accent.name = "TutorialAccent"
	accent.color = START_C_ACCENT
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
	_tut_cards.clear()
	for i in range(levels.size()):
		var card := _make_level_card(i, levels[i]["t"], levels[i]["d"])
		card.position = Vector2(TUT_CARD_X, TUT_CARD_Y0 + i * (TUT_CARD_H + TUT_CARD_GAP))
		page.add_child(card)
		_tut_cards.append(card)

	# -------- 返回 --------
	# 回调统一由 _setup_pages() 连接（与开始页按钮一致），这里不传，避免重复 connect
	var back := _page_ghost_btn("← 返回", func() -> void: pass, Vector2(160, 42),
		"TutorialBackBtn", 16)
	back.position = Vector2(496, 544)
	page.add_child(back)


# 关卡卡：整卡一个 Button；hover 只改描边 / 阴影（720 宽做 1.05 缩放会顶到装饰牌）
func _make_level_card(idx: int, title_text: String, desc_text: String) -> Button:
	var b := Button.new()
	b.name = "Tutorial%dBtn" % idx
	b.custom_minimum_size = Vector2(TUT_CARD_W, TUT_CARD_H)
	b.size = Vector2(TUT_CARD_W, TUT_CARD_H)
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _level_card_style(false, false))
	b.add_theme_stylebox_override("hover", _level_card_style(true, false))
	b.add_theme_stylebox_override("pressed", _level_card_style(false, true))
	b.add_theme_stylebox_override("focus", _make_panel_style("tab_off"))
	b.mouse_entered.connect(_on_level_card_hover.bind(b, true))
	b.mouse_exited.connect(_on_level_card_hover.bind(b, false))

	var badge := Panel.new()
	badge.name = "LevelBadge"
	badge.position = Vector2(24, 28)
	badge.size = Vector2(48, 48)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = START_C_ACCENT
	bs.set_corner_radius_all(8)
	badge.add_theme_stylebox_override("panel", bs)
	b.add_child(badge)

	var num := _start_label(str(idx), 24, Color(1, 1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	num.name = "LevelBadgeNum"
	num.position = Vector2(0, 11)
	num.size = Vector2(48, 32)
	badge.add_child(num)

	var tl := _start_label(title_text, 20, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	tl.name = "Tutorial%dTitle" % idx
	tl.position = Vector2(92, 18)
	tl.size = Vector2(470, 28)
	b.add_child(tl)

	var dl := _start_label(desc_text, 14, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	dl.name = "Tutorial%dDesc" % idx
	dl.position = Vector2(92, 50)
	dl.size = Vector2(470, 40)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(dl)

	var go := _start_label("开始 →", 15, START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	go.name = "Tutorial%dGo" % idx
	go.position = Vector2(600, 40)
	go.size = Vector2(96, 24)
	b.add_child(go)
	return b


func _level_card_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	var sb := _make_panel_style("card")
	sb.bg_color = Color(1, 1, 1, 0.96)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	if hover:
		sb.border_color = START_C_ACCENT
		sb.set_border_width_all(BORDER_W_ACTIVE)
		sb.shadow_color = Color(0.176, 0.478, 0.702, 0.22)
		sb.shadow_size = 8
	if pressed:
		sb.bg_color = Color(0.937, 0.965, 0.988, 1.0)
		sb.border_color = START_C_ACCENT
		sb.set_border_width_all(BORDER_W_ACTIVE)
	return sb


# 关卡卡 hover：「开始 →」由主题蓝加深，作为卡片被选中的视觉提示
func _on_level_card_hover(card: Button, entered: bool) -> void:
	if not is_instance_valid(card):
		return
	var col := START_C_ACCENT_DARK if entered else START_C_ACCENT
	for c in card.get_children():
		if c is Label and String(c.name).begins_with("Tutorial") and String(c.name).ends_with("Go"):
			c.add_theme_color_override("font_color", col)


# ============================================================
# 六、游戏启动
# ============================================================
func _on_organic_toggled(pressed: bool) -> void:
	if pressed:
		_show_info_simple("已启用有机物胜利规则")
	else:
		_show_info_simple("已禁用有机物胜利规则")
	_start_flash_rule_hint("已启用有机物胜利规则" if pressed else "已禁用有机物胜利规则")
	_sync_supp_rules_summary()

func _on_sequence_toggled(pressed: bool) -> void:
	if pressed:
		_show_info_simple("已启用顺序牌型规则")
	else:
		_show_info_simple("已禁用顺序牌型规则")
	_start_flash_rule_hint("已启用顺序牌型规则" if pressed else "已禁用顺序牌型规则")
	_sync_supp_rules_summary()

# 允许卤族互化（补充规则）：默认关闭 = 沿用硬规则「F/Cl/Br/I 之间不可化合」
func _on_halogen_toggled(pressed: bool) -> void:
	if pressed:
		_show_info_simple("已允许卤族互化（F/Cl/Br/I 之间可互相化合）")
	else:
		_show_info_simple("已禁止卤族互化")
	_start_flash_rule_hint("已允许卤族互化" if pressed else "已禁止卤族互化")
	_sync_supp_rules_summary()

# 元素限制（补充规则）：默认关闭 = 29 种元素全上桌
func _on_element_limit_toggled(pressed: bool) -> void:
	if pressed:
		_show_info_simple("已启用元素限制（前 20 号元素 + 自选扩展）")
	else:
		_show_info_simple("已关闭元素限制（29 种元素全部上桌）")
	_start_flash_rule_hint("已启用元素限制" if pressed else "已关闭元素限制")
	_sync_supp_rules_summary()

# 点元素 chip 时自动打开「元素限制」，否则勾了也不生效，容易被当成 bug
func _on_element_chip_toggled(_pressed: bool) -> void:
	var limit_cb = _start_child("ElementLimitCheckBox")
	if limit_cb and not limit_cb.button_pressed:
		limit_cb.button_pressed = true
	_sync_supp_rules_summary()


# 勾选状态 → 设置卡入口文字 / 摘要行 / 元素池统计（唯一出口，避免多处各写一套文案）
func _sync_supp_rules_summary() -> void:
	var on: Array = []
	var organic_cb = _start_child("OrganicCheckBox")
	if organic_cb and organic_cb.button_pressed: on.append("有机物")
	var seq_cb = _start_child("SequenceCheckBox")
	if seq_cb and seq_cb.button_pressed: on.append("顺序")
	var hal_cb = _start_child("HalogenCheckBox")
	if hal_cb and hal_cb.button_pressed: on.append("卤族互化")
	var limit_cb = _start_child("ElementLimitCheckBox")
	var limit_on: bool = limit_cb != null and limit_cb.button_pressed
	var extras := _selected_extra_elements()
	if limit_on:
		var parts: Array = ["前20号"]
		for s in extras:
			parts.append(str(s))
		on.append("元素限制 " + "/".join(parts))

	var entry = _start_child("SupplementaryHelpBtn")
	if entry:
		if on.is_empty():
			entry.text = "补充规则 · 默认 ▸"
		else:
			entry.text = "补充规则 · %d 项已开启 ▸" % on.size()

	var sum_label = _start_child("SuppRulesSummary")
	if sum_label:
		if on.is_empty():
			sum_label.text = "全部为默认：29 种元素 · 182 张牌 · 无特殊规则"
		else:
			sum_label.text = "已启用：" + " · ".join(on)

	if _supp_element_stats:
		var syms := CardDatabaseScript.get_allowed_symbols(limit_on, extras)
		var kinds: int = syms.size() if not syms.is_empty() else CardDatabaseScript.get_element_data().size()
		var extra_txt := "额外元素：无" if extras.is_empty() else "额外元素：" + "/".join(extras)
		_supp_element_stats.text = "%d 种 · %d 张 ｜ %s" % [
			kinds, CardDatabaseScript.get_deck_size(syms), extra_txt]

	# 未开限制时元素池只是「预选」：压暗提示尚未生效（仍可点，点了会自动开限制）
	for sym in _supp_element_chips.keys():
		var chip = _supp_element_chips[sym]
		if is_instance_valid(chip):
			chip.modulate.a = 1.0 if limit_on else 0.55


func _selected_extra_elements() -> Array:
	var out: Array = []
	for info in CardDatabaseScript.get_optional_elements():
		var sym := str(info["symbol"])
		var chip = _supp_element_chips.get(sym)
		if chip == null or not is_instance_valid(chip):
			chip = _start_child("ElementChip_" + sym)
		if chip and chip.button_pressed:
			out.append(sym)
	return out


func _open_supp_rules() -> void:
	if _supp_rules_page == null or not is_instance_valid(_supp_rules_page):
		return
	_sync_supp_rules_summary()
	_supp_rules_page.visible = true


func _close_supp_rules() -> void:
	if _supp_rules_page and is_instance_valid(_supp_rules_page):
		_supp_rules_page.visible = false

# 总人数变化 → AI 上限跟着变（AI 至少给人类留 1 个座位）
# 例：总人数 4 → AI 最多 3；把总人数改回 3 时 AI 会自动从 3 降到 2
func _on_player_count_changed(value: float) -> void:
	if ai_spin == null:
		return
	var seat_for_ai := maxi(0, int(value) - 1)
	var before := int(ai_spin.value)
	ai_spin.max_value = seat_for_ai   # Range 会自动把超限的 value 压回 max
	if before > seat_for_ai:
		_start_flash_rule_hint("AI 人数已自动降为 %d（最多 = 总人数 - 1）" % seat_for_ai)

func _on_start_game() -> void:
	var total = int(player_spin.value) if player_spin else 4
	var ai = int(ai_spin.value) if ai_spin else 3
	if total < GameManagerScript.MIN_PLAYERS or total > GameManagerScript.MAX_PLAYERS:
		total = 4
	# 防御：AI 至少 1 人（0 AI 时其余座位是没人操作的人类，开局即卡死），
	# 且最多 total-1（至少给人类留 1 个座位）
	if ai < 1:
		ai = 1
		if ai_spin:
			ai_spin.value = ai
	if ai > total - 1:
		ai = total - 1
		if ai_spin:
			ai_spin.value = ai   # 只压当前值，不动 max_value（否则会把上限永久锁死）
	start_page.visible = false
	game_page.visible = true
	end_page.visible = false
	if help_page: help_page.visible = false
	_close_supp_rules()
	_fade_in_page(game_page)
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
	if help_page: help_page.visible = false
	_fade_in_page(game_page)
	_step_reset()
	_hotseat_ready_seat = -1   # 教程单机：顺手清零，回到主开始页也不会带着旧座位
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
	# 触屏档（C）：工具行三颗按钮本来就挨得近，「帮助」和「退出游戏」很容易点串，
	# 而退出会直接结束本局（跳结算页）。触屏改成「二次确认」：
	# 第一次点 → 按钮自己变成「确认退出?」并 3 秒倒计时，再点一次才真的结束。
	if _touch_ui and not _quit_confirm_pending:
		_quit_confirm_pending = true
		if quit_button != null and is_instance_valid(quit_button):
			quit_button.text = "确认退出?"
		_show_info_simple("再点一次「确认退出?」结束本局（3 秒内有效）")
		get_tree().create_timer(3.0).timeout.connect(_reset_quit_confirm)
		return
	_quit_confirm_pending = false
	if quit_button != null and is_instance_valid(quit_button):
		quit_button.text = "退出游戏"
	if game_manager: game_manager.phase = 2
	_show_end_page("游戏已退出")


# 二次确认超时回滚：按钮文字复位，下次点击重新从「退出游戏」开始
func _reset_quit_confirm() -> void:
	if not _quit_confirm_pending:
		return
	_quit_confirm_pending = false
	if quit_button != null and is_instance_valid(quit_button):
		quit_button.text = "退出游戏"

func _show_info_simple(text: String) -> void:
	if info_label: info_label.text = text
	else: push_warning(text)

func _init_game(total: int = 4, ai: int = 3) -> void:
	game_manager = GameManagerScript.new()
	# 读取开始页的补充规则勾选框状态（三个独立勾选框，嵌在 SettingsCard 内）
	var organic_cb = _start_child("OrganicCheckBox")
	if organic_cb:
		game_manager.organic_rules_enabled = organic_cb.button_pressed
	var seq_cb_node = _start_child("SequenceCheckBox")
	if seq_cb_node:
		game_manager.sequence_rules_enabled = seq_cb_node.button_pressed
	var halogen_cb_node = _start_child("HalogenCheckBox")
	if halogen_cb_node:
		game_manager.halogen_exchange_allowed = halogen_cb_node.button_pressed
	# 元素限制（P10）：前 20 号元素 + 小页里勾选的扩展元素
	var limit_cb_node = _start_child("ElementLimitCheckBox")
	game_manager.element_limit_enabled = limit_cb_node != null and limit_cb_node.button_pressed
	game_manager.allowed_extra_elements = _selected_extra_elements() if game_manager.element_limit_enabled else []
	var ok = game_manager.init_game(total, ai)
	if not ok:
		push_error("init_game failed with total=%d ai=%d, retrying defaults" % [total, ai])
		ok = game_manager.init_game(4, 3)
		if not ok:
			push_error("CRITICAL: init_game also failed with defaults!")
			_show_end_page("初始化失败")
			return
	_step_reset()
	_hotseat_ready_seat = -1   # 新一局：谁都没认领屏幕（热座第一步也要先点）
	_hide_warning_toast()   # 新一局开始：隐藏上一局残留的警告 toast
	_refresh_ui()


# ============================================================
# 七之一、第零关：Phase 1 — UI 标注介绍
# ============================================================
func _level0_start_phase1() -> void:
	game_manager.set_tutorial_level0_phase(1)
	level0_active = true
	level0_step = 0
	level0_ui_highlight_steps = _level0_ui_steps()
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
			# 高亮框 = 工具行 bbox 外扩 6px；几何只有一处定义（§八之四 TOOL_ROW_HL_*），
			# 触屏档由 _tool_row_hl_rect() 跟随放大的工具行，改几何不会漏改这里
			"pos": _tool_row_hl_rect().position,
			"size": _tool_row_hl_rect().size,
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
	if game_manager.get_organic_rules_enabled() or game_manager.get_sequence_rules_enabled() \
			or game_manager.get_halogen_exchange_allowed() or game_manager.get_element_limit_enabled():
		var rules_list: Array = []
		if game_manager.get_organic_rules_enabled(): rules_list.append("有机物胜利")
		if game_manager.get_sequence_rules_enabled(): rules_list.append("顺序牌型")
		if game_manager.get_halogen_exchange_allowed(): rules_list.append("允许卤族互化")
		if game_manager.get_element_limit_enabled():
			var extras: Array = game_manager.get_allowed_extra_elements()
			var extra_txt := "无额外元素" if extras.is_empty() else "/".join(extras)
			rules_list.append("元素限制（前20号 + %s）" % extra_txt)
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
			var mini_btn = _build_mini_card_button(cards[i], cv)
			mini_btn.position = Vector2(start_x + i * mini_step, slot_y)
			_layer(0).add_child(mini_btn)
			table_card_buttons.append(mini_btn)
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


# ============================================================
# 八之三、手牌「按序 ⇅」按钮（P7）
# ============================================================
# 只在「玩家手动拖拽过 + 当前可操作」时出现，是手动排列模式唯一的出口。
# 位置 (338,558) = 工具行（显示提示 / 帮助 / 退出游戏）左侧同一基线：
# 手动排列模式下整行变成 [按序 ⇅][显示提示][帮助][退出游戏]，间距与高度完全一致；
# 上不压 CardInfoLabel（底边 526）、下不压 ActionPanel（顶边 599）。
func _build_hand_reorder_button() -> void:
	if not game_page or is_instance_valid(_reorder_btn):
		return
	var b := _mkb("按序 ⇅", _on_hand_reorder, false)
	b.name = "HandReorderBtn"
	b.custom_minimum_size = Vector2(REORDER_BTN_W, _tool_btn_h())
	b.size = Vector2(REORDER_BTN_W, _tool_btn_h())
	b.position = Vector2(_reorder_btn_left(), _tool_btn_top())
	b.add_theme_font_size_override("font_size", _touch_fs(14, 4))
	b.tooltip_text = "按原子序数升序重新排列手牌（恢复自动排序）"
	b.visible = false
	_layer(0).add_child(b)
	_reorder_btn = b


func _update_hand_reorder_button() -> void:
	if not is_instance_valid(_reorder_btn):
		return
	var cp = null
	if game_manager != null:
		cp = game_manager.get_current_player()
	# AI 回合 / 自动排列模式下没有「恢复自动排序」可言 → 直接隐藏
	_reorder_btn.visible = cp != null and not cp.is_ai and cp.hand_manual_order and _can_reorder_hand()


func _on_hand_reorder() -> void:
	if game_manager == null:
		return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return
	_cancel_drag()
	# force=true：只有这个显式入口能打断玩家排好的顺序，排完即退回自动模式
	cp.sort_hand_by_atomic_number(true)
	_reorder_tip = "已按原子序数重新排列手牌"
	_update_hand_buttons()
	_update_card_info_label()
	_update_hand_reorder_button()


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
	if cp == null:
		card_info_label.text = ""
		return
	if cp.is_ai:
		# 手牌区此时显示玩家自己的牌（只读），这里说明在等谁，
		# 否则玩家会误以为界面卡住
		card_info_label.text = "等待 %s 行动中… 现在不是你的回合，手牌仅供查看" % cp.player_name
		return
	# 热座：手牌还盖着，先说清楚该把屏幕交给谁
	if _hotseat_handoff_pending():
		card_info_label.text = "轮到 %s：请把屏幕交给 TA，自行点击上方按钮查看手牌" % cp.player_name
		return
	# 一次性提示（重排完成等）：只显示到下一次刷新，不占用提示按钮的状态
	if _reorder_tip != "":
		card_info_label.text = _reorder_tip
		_reorder_tip = ""
		return
	# 提示（P6）：_apply_hint() 写入的建议优先于默认「可用牌型」，
	# 但局面一变（换人 / 手牌数变了 / 顺序被玩家重排）就作废，避免选中残留误导玩家
	if _hint_text != "":
		if _hint_owner == game_manager.get_current_player_index() \
				and _hint_hand_size == cp.hand.size() \
				and _hint_order_sig == _hand_order_sig(cp):
			card_info_label.text = _hint_text
			return
		_clear_hint()
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
	# 热座交接未认领前不给任何操作按钮：否则可以绕过遮罩直接点「跳过 / 出牌」
	if _hotseat_handoff_pending():
		return
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
		var in_chain: bool = game_manager.is_clan_bomb_chain_active() \
				and game_manager.get_current_player_index() != game_manager.get_clan_bomb_owner()
		if in_chain:
			# 接炸链中：冷却期间同样不能出族炸，只能跳过（见 GAMEPLAY_RULES「族炸冷却」）
			if cp.clan_bomb_cooling:
				if cp.get_hand_count() >= game_manager.get_hand_limit():
					action_panel.add_child(_mkb("弃牌跳过(上限)", _on_pass, false))
				else:
					action_panel.add_child(_mkb("跳过(❄冷却中不能接炸)", _on_pass, false))
			else:
				action_panel.add_child(_mkb("作为族炸打出", _on_clan_bomb, false))
			action_panel.add_child(_mkb("返回", _on_back, false))
		else:
			action_panel.add_child(_mkb("作为单质打出", _on_element, false))
			action_panel.add_child(_mkb("合成化合物", _on_choose_compound, false))
			if game_manager.get_sequence_rules_enabled():
				action_panel.add_child(_mkb("作为顺序打出", _on_sequence, false))
			# 冷却 / 禁炸时按钮保留但要置灰，避免「点了才报错」
			if cp.clan_bomb_cooling:
				action_panel.add_child(_mkb("族炸❄冷却中", _on_clan_bomb, true))
			elif game_manager.clan_bomb_disabled:
				action_panel.add_child(_mkb("族炸已禁用", _on_clan_bomb, true))
			else:
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
	b.custom_minimum_size = Vector2(160, 58 if _touch_ui else 45)   # 触屏 58 高 ≈ 39dp
	b.add_theme_font_size_override("font_size", _touch_fs(16, 2))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.disabled = dis

	# 深蓝灰圆角按钮样式（P2：统一由 _make_panel_style("button") 产出）
	var style_normal = _make_panel_style("button")
	b.add_theme_stylebox_override("normal", style_normal)

	# 悬停：背景变亮 + 主题蓝发光（P3 · 美术文档 §5.4「悬停时亮色发光」）
	# StyleBoxFlat 的 shadow 是背景外扩绘制，配合半透明亮蓝即可当光晕用
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	style_hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	style_hover.shadow_color = Color(0.35, 0.55, 0.85, 0.55)
	style_hover.shadow_size = 6
	style_hover.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("hover", style_hover)

	# 按下：略暗
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	b.add_theme_stylebox_override("pressed", style_pressed)

	# 禁用：半透明
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.173, 0.243, 0.314, 0.35)
	b.add_theme_stylebox_override("disabled", style_disabled)

	# 缩放交互（P3 · 美术文档 §7.4）：pivot 居中，悬停 1.05 / 按下 0.96
	# 与游戏页工具按钮共用同一套接线（见 _attach_btn_motion）
	_attach_btn_motion(b)

	b.pressed.connect(cb)
	return b


# -------- 缩放交互接线（P3）：pivot 居中 + 悬停 1.05 / 按下 0.96 --------
# 缩放只向外扩，不会把指针挤出原边界，因此 entered/exited 不会自激抖动。
# pivot 取值有讲究：_mkb 生成的按钮此刻还没进容器（size=0），直接读 size 会得到 0，
# 缩放就会绕着左上角甩 → 用 custom_minimum_size 兜底；工具按钮来自 Main.tscn，
# 进树前已有 size，直接用 size。两者随后都由 resized 校正到 size*0.5。
func _attach_btn_motion(b: Button) -> void:
	# 幂等：_mkb / _style_game_tool_buttons / _style_tool_btn 都可能被重复调用
	# （重排、切档、测试），重复 connect 会刷一串 "already connected" ERROR，
	# 并在 resized 上挂多个相同 lambda
	if b.has_meta("btn_motion_attached"):
		return
	b.set_meta("btn_motion_attached", true)
	b.pivot_offset = (b.size if b.size != Vector2.ZERO else b.custom_minimum_size) * 0.5
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	# 触屏档不接 hover：Android 把「最后一次触摸位置」当成鼠标位置，
	# mouse_entered 之后永远等不到 mouse_exited → 按钮会一直停在 1.05 倍。
	# 触控语义改成「按下 0.96、松手回 1.0」，见 _on_button_press_scale。
	if not _touch_ui:
		b.mouse_entered.connect(_on_button_hover_scale.bind(b, true))
		b.mouse_exited.connect(_on_button_hover_scale.bind(b, false))
	b.button_down.connect(_on_button_press_scale.bind(b, true))
	b.button_up.connect(_on_button_press_scale.bind(b, false))


# -------- 按钮缩放补间（P3）：每个按钮只保留一个 tween --------
func _tween_button_scale(btn: Button, target: float) -> void:
	if not is_instance_valid(btn):
		return
	var tw = btn.get_meta("btn_scale_tween", false)
	if tw is Tween and tw.is_valid():
		tw.kill()
	tw = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2.ONE * target, BUTTON_SCALE_MS / 1000.0)
	btn.set_meta("btn_scale_tween", tw)


func _on_button_hover_scale(btn: Button, entered: bool) -> void:
	if not is_instance_valid(btn) or btn.disabled:
		return
	_tween_button_scale(btn, BUTTON_HOVER_SCALE if entered else 1.0)


func _on_button_press_scale(btn: Button, down: bool) -> void:
	if not is_instance_valid(btn) or btn.disabled:
		return
	if down:
		_tween_button_scale(btn, BUTTON_PRESS_SCALE)
	else:
		# 松开后指针通常仍在按钮内（说明还悬停着），回到悬停尺寸；
		# 触屏档没有悬停语义，一律回 1.0，否则 is_hovered() 恒真 → 按钮永远放大
		_tween_button_scale(btn, 1.0 if _touch_ui or not btn.is_hovered() else BUTTON_HOVER_SCALE)


# ============================================================
# 九之一、触屏档取值函数（A1+B+C）
# ============================================================
# 为什么是函数而不是常量：本文件所有几何 const 都带自动化断言（tests/verify_*.gd），
# 直接改常量会把 24 套测试的期望值全部打翻。这里把「桌面值」和「触屏值」分成两层：
#   const ...         桌面基准（测试读它）
#   _xxx() -> float   运行时取值（触屏档换成放大后的值）
# 调用点因此全部改用函数，桌面下返回值与常量逐值相等。
func _touch_fs(base: int, bonus: int = TOUCH_FS_BONUS) -> int:
	return base + bonus if _touch_ui else base


func _touch_btn_h(base_h: int) -> int:
	return maxi(base_h, TOUCH_BTN_MIN_H) if _touch_ui else base_h


func _tool_btn_h() -> float:
	return float(TOUCH_TOOL_BTN_H) if _touch_ui else float(TOOL_BTN_H)


func _tool_btn_top() -> float:
	return float(TOUCH_TOOL_BTN_TOP) if _touch_ui else float(TOOL_BTN_TOP)


func _tool_btn_gap() -> float:
	return float(TOUCH_TOOL_BTN_GAP) if _touch_ui else float(TOOL_BTN_GAP)


# 工具行左边界：右边界固定 820，间距变宽 → 左边界自动左移（教程高亮框跟着走）
func _tool_row_left() -> float:
	return TOOL_BTN_RIGHT - (TOOL_BTN_W_HINT + TOOL_BTN_W_HELP + TOOL_BTN_W_QUIT) - _tool_btn_gap() * 2.0


func _reorder_btn_left() -> float:
	return _tool_row_left() - _tool_btn_gap() - REORDER_BTN_W


# 教程第零关「按钮区」高亮框：工具行 bbox 外扩 TOOL_ROW_HL_PAD
# （DESKTOP 时与 TOOL_ROW_HL_POS / TOOL_ROW_HL_SIZE 逐值相等，见 verify_touch_ui）
func _tool_row_hl_rect() -> Rect2:
	var pad := float(TOOL_ROW_HL_PAD)
	var left := _tool_row_left()
	return Rect2(
			Vector2(left - pad, _tool_btn_top() - pad),
			Vector2(TOOL_BTN_RIGHT - left + pad * 2.0, _tool_btn_h() + pad * 2.0))


# 拖拽阈值：鼠标 6px 就够，手指轻微抖动就有 12~20px
func _drag_threshold() -> float:
	return TOUCH_DRAG_THRESHOLD if _touch_ui else DRAG_THRESHOLD


# 选中牌静止时相对 base_pos 的上浮量：触屏常驻上浮，桌面 0（悬停已足够表达）
func _selected_lift() -> float:
	return TOUCH_SELECT_LIFT if _touch_ui else 0.0


# -------- 页面级触控放大：开始页 / 帮助页 / 结算页 / 教学页的按钮统一过一遍 --------
# 这些页面的按钮是代码生成的、尺寸由各调用点手写（220×56 / 150×38 / 270×32 ...），
# 逐个改调用点既啰嗦又容易漏；改为构建完成后统一兜底：
#   · 渲染高度 < TOUCH_BTN_MIN_H 的，拉到 48（位置按中心不变微调，不跳行）
#   · 字号 +TOUCH_FS_BONUS
# 容器内的按钮（PanelContainer / VBox）position 会被容器覆盖，改为靠 custom_minimum_size 生效。
func _apply_touch_sizing(root: Node) -> void:
	if not _touch_ui or root == null:
		return
	for b in _collect_buttons(root):
		# 幂等：start_page 与补充规则小页是父子关系，会被递归扫两次；
		# 不打标记的话字号会 +2 +2 叠成 +4
		if b.has_meta("touch_sized"):
			continue
		b.set_meta("touch_sized", true)
		var old_h: float = b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y
		if old_h > 0.0 and old_h < float(TOUCH_BTN_MIN_H):
			var new_h: int = TOUCH_BTN_MIN_H
			b.custom_minimum_size = Vector2(b.custom_minimum_size.x, new_h)
			b.size = Vector2(b.size.x, new_h)
			b.position = Vector2(b.position.x, b.position.y - (new_h - old_h) * 0.5)
			b.pivot_offset = b.size * 0.5
		var fs: int = b.get_theme_font_size("font_size")
		if fs > 0:
			b.add_theme_font_size_override("font_size", fs + TOUCH_FS_BONUS)


func _collect_buttons(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c.get_child_count() > 0:
			out.append_array(_collect_buttons(c))
	return out


# ============================================================
# 八之四、游戏页工具按钮（显示提示 / 帮助 / 退出游戏）
# ============================================================
# 历史问题（本次修）：这三颗按钮是 GamePage 里唯一没有接管样式的控件，一直画引擎
# 默认主题（灰 #6B6B6B 实底 / 4px 圆角 / 无描边 / 无阴影 / 13px 灰白字），与页面其余
# 部分两套语言都不同源：卡片是「白底 + 1px 中性边 + 8 圆角 + 软投影」，按钮是
# 「深蓝灰 #2C3E50 + 8 圆角 + 悬停蓝色光晕」。另外三个节点 y 分别是 567/568/569、
# 宽 130/100/100 —— 基线不齐、间距不一，肉眼看着发飘。
#
# 本节的职责只有两件事：样式接管 + 几何归一。文本、信号、行为一律不动。
#   · 底 / 边 / 圆角 / 阴影全部取自 _make_panel_style("button")，不再出现手写数值
#   · hover 复用 _mkb 的亮蓝光晕；focus 置空，免得默认焦点环跳出画风
#   · 「显示提示」是 toggle：pressed / hover_pressed 换成主题蓝实底 → 开启态一眼可辨
#   · 「退出游戏」是半破坏性动作（_on_quit_game → 结算页，不是退程序）：仅 hover 转暖红
#
# 几何：运行期以本节常量为准（Main.tscn 的 offset 只是编辑器预览，两边保持同步），
# 整行右边界对齐 x=820 —— 与 HandContainer / CardInfoLabel 右边缘同一条竖线
# （LogLabel 从 x=824 起）。手动排列模式的「按序 ⇅」并进同一行左侧。
const TOOL_BTN_TOP := 558          # 上让 CardInfoLabel(底 526) 32px，下让 ActionPanel(顶 599) 9px
const TOOL_BTN_H := 32
const TOOL_BTN_GAP := 10
const TOOL_BTN_RIGHT := 820
const TOOL_BTN_W_HINT := 132
const TOOL_BTN_W_HELP := 96
const TOOL_BTN_W_QUIT := 112
const TOOL_ROW_LEFT := TOOL_BTN_RIGHT - (TOOL_BTN_W_HINT + TOOL_BTN_W_HELP + TOOL_BTN_W_QUIT + TOOL_BTN_GAP * 2)
const REORDER_BTN_W := 112
const REORDER_BTN_LEFT := TOOL_ROW_LEFT - TOOL_BTN_GAP - REORDER_BTN_W
# 教程第零关「按钮区」高亮框：工具行 bbox 外扩 6px（_level0_ui_steps 直接引用）
const TOOL_ROW_HL_PAD := 6
const TOOL_ROW_HL_POS := Vector2(TOOL_ROW_LEFT - TOOL_ROW_HL_PAD, TOOL_BTN_TOP - TOOL_ROW_HL_PAD)
const TOOL_ROW_HL_SIZE := Vector2(
		TOOL_BTN_RIGHT - TOOL_ROW_LEFT + TOOL_ROW_HL_PAD * 2,
		TOOL_BTN_H + TOOL_ROW_HL_PAD * 2)


func _style_game_tool_buttons() -> void:
	if hint_button == null or help_btn == null or quit_button == null:
		return
	# 几何归一：等高、同基线、等间距，右边界固定 → 三颗按钮不会再「各自为政」
	# 触屏档：高 48、间距 20、顶边 542（_tool_btn_*() 取运行时值，const 仍是桌面基准）
	var row: Array = [
		[hint_button, TOOL_BTN_W_HINT, true, false],
		[help_btn, TOOL_BTN_W_HELP, false, false],
		[quit_button, TOOL_BTN_W_QUIT, false, true],
	]
	# 先刷样式（含字号）再定几何：字号会改变按钮的最小尺寸，若先设 size，
	# 它会被 clamp 到「旧字号」的 min —— 触屏档 48 切回桌面档时高度就僵在 ~40 回不到 32。
	for entry in row:
		_style_tool_btn(entry[0], entry[2], entry[3])
	var x: float = _tool_row_left()
	var h: float = _tool_btn_h()
	var top: float = _tool_btn_top()
	for entry in row:
		var b: Button = entry[0]
		var w: int = entry[1]
		b.custom_minimum_size = Vector2(w, h)
		b.size = Vector2(w, h)
		b.position = Vector2(x, top)
		x += w + _tool_btn_gap()


# 单颗工具按钮的四态样式（normal / hover / pressed / disabled / focus）
# is_toggle: toggle 按钮的 pressed 同时就是「ON」态 → 换成主题蓝实底
# danger:    半破坏性动作 → hover / pressed 走暖红
func _style_tool_btn(b: Button, is_toggle: bool, danger: bool) -> void:
	var normal := _make_panel_style("button")
	b.add_theme_stylebox_override("normal", normal)

	# 悬停：提亮 + 主题蓝发光（参数与 _mkb 完全一致，见 P3「悬停时亮色发光」）
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	hover.shadow_color = Color(0.35, 0.55, 0.85, 0.55)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("hover", hover)

	# 按下：略暗（与 _mkb 同色）
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	b.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.173, 0.243, 0.314, 0.35)
	b.add_theme_stylebox_override("disabled", disabled)

	# 焦点框置空：否则键盘/点击后会出现默认主题的蓝框，跳出「白卡 + 深蓝灰按钮」的画风
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	b.add_theme_font_size_override("font_size", _touch_fs(14, 4))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))

	if is_toggle:
		# 开启态（toggle ON）：主题蓝实底 + 深蓝边 + 蓝光晕
		var on_style := _make_panel_style("button")
		on_style.bg_color = START_C_ACCENT
		on_style.border_color = START_C_ACCENT_DARK
		on_style.shadow_color = Color(0.176, 0.478, 0.702, 0.45)
		on_style.shadow_size = 6
		on_style.shadow_offset = Vector2.ZERO
		b.add_theme_stylebox_override("pressed", on_style)
		# 开启态 + 悬停：只把蓝色提亮一档，别退回深蓝灰，否则「按着 + 移入」会闪一下
		var on_hover := on_style.duplicate() as StyleBoxFlat
		on_hover.bg_color = START_C_ACCENT.lightened(0.12)
		on_hover.border_color = START_C_ACCENT
		on_hover.shadow_color = Color(0.176, 0.478, 0.702, 0.6)
		on_hover.shadow_size = 8
		b.add_theme_stylebox_override("hover_pressed", on_hover)

	if danger:
		# 「退出游戏」= 结束本局进结算页：悬停转暖红（BORDER_WARN 与警告 toast 同色）
		var danger_hover := normal.duplicate() as StyleBoxFlat
		danger_hover.bg_color = Color(1.0, 0.953, 0.925, 1.0)
		danger_hover.border_color = BORDER_WARN
		danger_hover.shadow_color = Color(0.906, 0.298, 0.235, 0.45)
		danger_hover.shadow_size = 6
		danger_hover.shadow_offset = Vector2.ZERO
		b.add_theme_stylebox_override("hover", danger_hover)
		b.add_theme_color_override("font_hover_color", BORDER_WARN)
		# 按下也走暖色：否则「悬停红 → 按下又变蓝灰」会割裂
		var danger_pressed := danger_hover.duplicate() as StyleBoxFlat
		danger_pressed.bg_color = Color(0.996, 0.902, 0.882, 1.0)
		b.add_theme_stylebox_override("pressed", danger_pressed)
		b.add_theme_color_override("font_pressed_color", BORDER_WARN)

	_attach_btn_motion(b)


# ============================================================
# 十、提示按钮（P6：自动选中最优可出组合 + 说明）
# ============================================================
# 交互设计（方案 C）
#   点一下 → HintAdvisor 找出「马上就能打出去」的组合 → 自动勾选手牌
#   并把 step_mode 推到对应的下一步（化合物直接到「确认打出」）
#   → 玩家只需再点一次面板按钮即可出牌
# 再点一下（toggle 取消）→ 清空提示，不动已选的牌
func _on_hint_toggled(pressed: bool) -> void:
	if not pressed:
		_clear_hint()
		_update_card_info_label()
		return
	# 热座交接未认领：提示会暴露「有没有能打的组合」，也等于替下一位玩家先看了牌
	if _hotseat_handoff_pending():
		if hint_button != null and is_instance_valid(hint_button):
			hint_button.set_pressed_no_signal(false)
		return
	_apply_hint()


func _apply_hint() -> void:
	if game_manager == null or game_manager.is_game_over():
		return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return

	var adv: Dictionary = HintAdvisorScript.suggest(game_manager)
	if adv.is_empty():
		_clear_hint()
		_hint_text = "提示：当前没有能直接打出的组合，建议「跳过」或按上限弃牌。"
		_hint_owner = game_manager.get_current_player_index()
		_hint_hand_size = cp.hand.size()
		_hint_order_sig = _hand_order_sig(cp)
		_update_card_info_label()
		return

	# 1) 勾选手牌（顺序稳定：按手牌下标升序，卡面重叠时高亮看起来更自然）
	var idxs: Array = adv["indices"].duplicate()
	idxs.sort()
	selected_indices.clear()
	for i in idxs:
		selected_indices.append(int(i))

	# 2) 化合物把化合价也填好，玩家直接点「确认打出」；其余牌型停在选牌型面板
	compound_selections.clear()
	var pattern: int = adv["pattern"]
	if pattern == CardPatternsScript.CardPattern.COMPOUND:
		var val: Dictionary = adv["valence"]
		for sym in val:
			compound_selections.append({"symbol": sym, "valence": val[sym]})
		step_mode = 2
	else:
		step_mode = 1
		compound_selections.clear()

	_hint_text = adv["text"]
	_hint_owner = game_manager.get_current_player_index()
	_hint_hand_size = cp.hand.size()
	_update_hand_buttons()
	# 重建时可能自动排序（自动排列模式），签名必须在刷新之后取，
	# 否则签名与真实顺序不一致，提示会在下一次刷新时被误判成"局面已变"而作废
	_hint_order_sig = _hand_order_sig(cp)
	_update_action_panel()
	_update_card_info_label()


func _clear_hint() -> void:
	_hint_text = ""
	_hint_owner = -1
	_hint_hand_size = -1
	_hint_order_sig = ""
	# 牌被改动 / 局面推进后，提示按钮不能继续按着，否则下次点击会先触发「取消」
	if hint_button != null and is_instance_valid(hint_button) and hint_button.button_pressed:
		hint_button.set_pressed_no_signal(false)


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
		# 稀有气体：原为近白 (0.95)，在白卡面上与底色几乎融成一片 → 改青色。
		# 色相刻意与「非金属 / 准金属 = 绿 (0,0.7,0.2)」「N = 紫 (0.4,0.2,0.8)」拉开距离
		"稀有气体": return Color(0.0, 0.6, 0.65)
	return Color(0.8, 0.8, 0.8)


# ============================================================
# 十二、手牌渲染（原子牌面）
# ============================================================
func _update_hand_buttons() -> void:
	if not hand_container or not game_manager: return
	# 重建会销毁当前 hover 的按钮，先还原信息栏，避免详情文本滞留
	_restore_card_info()
	# 拖拽幽灵牌 / 指示线也是容器子节点，重建前必须收掉，否则引用悬空
	_cancel_drag()
	var actor = game_manager.get_current_player()
	# 视角座位：单人类模式永远看自己（AI 回合只读）；热座模式只看当前人类。
	# 旧实现在 AI 回合直接把手牌区换成一句「等待 XX 行动中...」，
	# 玩家整轮看不到自己的牌 → 改成始终显示自己的手牌，只是不可操作。
	var view = _hand_view_player(actor)
	_hand_read_only = view != null and actor != null and view != actor
	# 选中快照必须抢在 hand_buttons.clear() 之前：旧按钮上的 card meta 是
	# 「玩家看见并点中的那张牌」的唯一可靠来源（数据层顺序可能已被拖拽 / 抽牌排序改过）
	var keep_selected: Array = _selected_cards(view)
	# 旧按钮即将销毁，悬停状态机必须一并清零，否则会指向失效索引
	_hover_idx = -1
	_hover_pending_idx = -1
	# 先 remove_child 再 queue_free：避免旧牌残留在容器中干扰重叠布局
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()
	hand_buttons.clear()
	ai_triggered = false

	# AI 调度与手牌渲染解耦：即使显示的是玩家自己的牌，也要继续推动 AI 行动
	var ai_acting: bool = actor != null and actor.is_ai and not game_manager.is_game_over()
	if ai_acting and not ai_triggered:
		ai_triggered = true
		var timer = get_tree().create_timer(1.5)
		timer.timeout.connect(_ai_auto_play)

	if view == null:
		# 热座的 AI 回合：谁的牌都不能显示（同屏多人会互相看到手牌）
		if actor != null:
			var wl = Label.new()
			wl.text = "等待 %s 行动中..." % actor.player_name
			wl.add_theme_font_size_override("font_size", 28)
			# 手牌区背景是浅蓝，默认白色字几乎不可见
			wl.add_theme_color_override("font_color", Color(0.33, 0.4, 0.5, 1))
			# Control 容器不会自动布局子节点，需显式定位
			wl.position = Vector2(200, 20)
			wl.size = Vector2(420, 48)
			hand_container.add_child(wl)
		_update_hand_reorder_button()
		return

	# 热座交接：多人类同屏时，轮到某个真人先盖住手牌区，
	# 由 TA 自己点一下再展示 —— 否则上一位玩家的牌会直接摊在下一位面前（同一块屏）。
	if _hotseat_handoff_pending():
		_render_hotseat_handoff(actor)
		_update_hand_reorder_button()
		return

	# 只读视角不能排序：自动排序会把手动排列覆盖掉，而玩家此刻并不能操作
	if not _hand_read_only:
		# 自动排列模式下这里会排序；手动排列模式直接返回，玩家排好的顺序得以保留
		view.sort_hand_by_atomic_number()
	# 顺序可能已变 → 用卡片对象把选中索引重算一遍
	_remap_selection(view, keep_selected)
	for i in range(view.hand.size()):
		var card = view.hand[i]
		var btn = _build_card_button(card, i)
		# 只读：不接鼠标（保持视觉不变，也不会误改选中态）
		if _hand_read_only:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hand_container.add_child(btn)
		hand_buttons.append(btn)
	_layout_hand_cards()
	if not _hand_read_only:
		_restore_hover_after_rebuild()
	# 「按序」按钮只在「手动排列 + 可操作阶段」出现
	_update_hand_reorder_button()


# 人类座位列表（PlayerManager 保证人类排在 0..H-1，H = 总人数 - AI 数）
func _human_players() -> Array:
	var out: Array = []
	if game_manager == null:
		return out
	for p in game_manager.players:
		if p != null and not p.is_ai:
			out.append(p)
	return out


# 手牌视角座位：
#   单人类（1 人 + N AI）：永远看自己；AI 回合只读 → 修掉「AI 回合看不到自己的牌」
#   热座（多人类）    ：只看当前人类；AI 回合返回 null，由调用方显示等待提示
#                        （同屏多人绝不能同时显示各自手牌）
# 联机改造（P11-C1）时改成返回「本地座位」即可，guest 永远只有自己。
func _hand_view_player(actor = null):
	if game_manager == null:
		return null
	var a = actor
	if a == null:
		a = game_manager.get_current_player()
	if a == null:
		return null
	var humans: Array = _human_players()
	if humans.size() <= 1:
		if a.is_ai:
			return humans[0] if humans.size() == 1 else a
		return a
	if a.is_ai:
		return null
	return a


# -------- 热座交接（B2）--------
# 同屏多人类时，谁轮到谁就得先「认领」屏幕：手牌默认盖住，本人点一下才展示。
# 单人类（1 人 + N AI）用不上 —— 只有一个能看牌的人，遮罩只会多一步点击。
func _is_hotseat() -> bool:
	return _human_players().size() >= 2


# 当前是否「该展示手牌但还没人认领」：只有热座 + 当前是人类时才成立
func _hotseat_handoff_pending() -> bool:
	if game_manager == null or not _is_hotseat():
		return false
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return false
	return _hotseat_ready_seat != game_manager.get_current_player_index()


# 认领成功：记下座位并立刻重画手牌 / 操作面板
func _on_hotseat_handoff_confirmed() -> void:
	if game_manager == null:
		return
	_hotseat_ready_seat = game_manager.get_current_player_index()
	_update_hand_buttons()
	_update_action_panel()
	_update_card_info_label()


# 交接遮罩：整块盖住手牌区（此帧根本没有渲染任何牌，遮罩只是「请先认领」的入口）
func _render_hotseat_handoff(actor) -> void:
	if hand_container == null or not is_instance_valid(hand_container):
		return
	var who: String = actor.player_name if actor != null else "下一位玩家"
	var btn := Button.new()
	btn.name = "HotseatHandoffBtn"
	btn.position = Vector2.ZERO
	btn.size = hand_container.size
	btn.text = "轮到 %s · 点击查看手牌" % who
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	# 与操作面板按钮同一套样式，玩家一眼能认出「这是个要点的按钮」
	var style := _make_panel_style("button")
	btn.add_theme_stylebox_override("normal", style)
	var style_hover = style.duplicate()
	style_hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	style_hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	btn.add_theme_stylebox_override("hover", style_hover)
	var style_pressed = style.duplicate()
	style_pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.pressed.connect(_on_hotseat_handoff_confirmed)
	hand_container.add_child(btn)

	# 副提示（Button 不支持多行文本）→ 单独 Label 盖在按钮内，不能吃鼠标
	var tip := Label.new()
	tip.name = "HotseatHandoffTip"
	tip.text = "请先把屏幕交给 %s，其他人回避后再点击" % who
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	tip.position = Vector2(0, hand_container.size.y - 44.0)
	tip.size = Vector2(hand_container.size.x, 26)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tip)


# -------- 选中状态：索引 ↔ 卡片对象 的双向保护 --------
# selected_indices 只能存索引（出牌 / 化合价等处都按索引用），
# 所以顺序一变就必须用卡片对象把索引重新算出来，不能直接沿用旧索引。
func _selected_cards(cp) -> Array:
	var out: Array = []
	if cp == null: return out
	for idx in selected_indices:
		var i: int = int(idx)
		if i < 0:
			continue
		var card = null
		# 优先用「上一帧渲染的按钮」取对象：数据层顺序可能已经被外部改掉
		# （拖拽落库、抽牌后自动排序），旧索引对不上新数组，但按钮 meta 里
		# 记的仍是玩家真正看见并点中的那张牌
		if i < hand_buttons.size() and is_instance_valid(hand_buttons[i]) \
				and hand_buttons[i].has_meta("card"):
			card = hand_buttons[i].get_meta("card")
		elif i < cp.hand.size():
			card = cp.hand[i]
		if card != null:
			out.append(card)
	return out


func _remap_selection(cp, cards: Array) -> void:
	selected_indices.clear()
	if cp == null: return
	for card in cards:
		var at: int = cp.hand.find(card)
		# 同一张牌在手牌里最多出现一次；重复引用（测试里补牌会出现）只保留首个
		if at >= 0 and not selected_indices.has(at):
			selected_indices.append(at)


# 手牌顺序签名：原子序数 + 符号按当前顺序拼起来。
# 提示（_hint_text）靠它判断"玩家是否动过这张牌的位置"，顺序一变提示立即作废。
func _hand_order_sig(cp) -> String:
	if cp == null:
		return ""
	var parts: Array = []
	for c in cp.hand:
		parts.append("%d%s" % [c.atomic_number, c.symbol])
	return ",".join(parts)


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
		var at_x: float = start_x + i * step
		# 触屏档（C）：选中的牌常驻上浮 TOUCH_SELECT_LIFT（≈7dp），与「悬停 20」区分 ——
		# 触屏没有悬停语义，不加这个就完全看不出选了哪几张，容易重复点/漏点。
		# base_pos 必须存「未上浮」的静止位置：命中判定 / 拖拽 / 悬停全都基于它。
		var lift: float = _selected_lift() if i in selected_indices else 0.0
		btn.position = Vector2(at_x, base_y - lift)
		btn.set_meta("base_pos", Vector2(at_x, base_y))
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
		sym.add_theme_font_size_override("font_size", _touch_fs(21 if compact else 28, 4))
	var nm = btn.get_node_or_null("CardName")
	if nm:
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		nm.position = Vector2(6, 49) if compact else Vector2(5, 48)
		nm.size = Vector2(44, 15) if compact else Vector2(85, 15)
		nm.add_theme_font_size_override("font_size", _touch_fs(12 if compact else 14, 2))
	var vl = btn.get_node_or_null("CardValence")
	if vl:
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		vl.position = Vector2(6, 72) if compact else Vector2(5, 72)
		vl.size = Vector2(44, 18) if compact else Vector2(85, 18)


# ============================================================
# 十二之二、手牌拖拽重排（P7）
# ============================================================
# 为什么用 _process 轮询而不是 gui_input：
#   Control 的 gui_input 信号与 Button 内部的 _gui_input 处理作用在同一个控件上，
#   accept_event() 只能阻止事件继续传给其他控件，挡不住这个 Button 自己补发的
#   pressed —— 拖完松手会顺带把那张牌选中。这里沿用项目已有的 _process 轮询风格，
#   用 _drag_suppress_click 明确吞掉拖拽后的那次 pressed，行为可预测。
# 顺序真源：拖动只改 PlayerInfo.hand 的数组顺序，界面每次重建照抄，不存第二套顺序。

# 当前局面是否允许拖拽（教程关 / 非选牌阶段 / 非玩家回合一律禁止）
func _can_reorder_hand() -> bool:
	if game_manager == null or game_manager.is_game_over():
		return false
	# 只读视角（AI 回合查看自己的牌）不许改顺序
	if _hand_read_only:
		return false
	# 热座交接未认领：手牌还盖着，重排按钮 / 拖拽都该消失
	if _hotseat_handoff_pending():
		return false
	# 教程关（含第 0 关引导阶段）禁用：引导高亮框按固定坐标绘制，拖牌会让提示错位
	if game_manager.tutorial_level > 0 or game_manager.tutorial_level0_phase > 0:
		return false
	# 只在「选牌 / 弃牌」阶段允许，选牌型 / 选化合价时手牌是只读参照
	if step_mode != 0 and step_mode != 3:
		return false
	if hand_container == null or not is_instance_valid(hand_container):
		return false
	if not hand_container.is_visible_in_tree():
		return false
	if game_page == null or not game_page.visible:
		return false
	return true


# 每帧驱动拖拽状态机（headless 无真实鼠标，直接跳过）
func _update_hand_drag() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _drag_active:
			_finish_drag()
		_drag_press_idx = -1
		return
	if _drag_active:
		_update_drag_follow()
		return
	if not _can_reorder_hand():
		_drag_press_idx = -1
		return
	if _drag_press_idx < 0:
		# 首次检测到按下：直接用命中判定取源牌，不依赖悬停状态机是否已经抬起
		# （压在 60ms 稳定延迟内的快速拖动也能立刻生效）
		# 用 _hit_card_at：已抬起的牌压住相邻牌，它的绘制区归它自己
		var mp: Vector2 = hand_container.get_local_mouse_position()
		var hit: int = _hit_card_at(mp)
		if hit >= 0:
			_drag_press_idx = hit
			_drag_press_pos = get_global_mouse_position()
			_drag_press_at = Time.get_ticks_msec()
			_drag_suppress_click = false
		return
	if _drag_press_idx >= hand_buttons.size():
		_drag_press_idx = -1
		return
	# 未越过阈值 = 普通点击，交给 Button 自己的 pressed
	var moved: float = get_global_mouse_position().distance_to(_drag_press_pos)
	if moved >= _drag_threshold():
		# 触屏档（C）：阈值 6→24 之外，还要求按住够长（300ms）才算「有意重排」。
		# 手指点选时横向滑动普遍 12~20px，只按距离判定会把它当拖拽 →
		# 牌跟着乱跑，而且那次 pressed 被 _drag_suppress_click 吞掉，表现为「点了没反应」。
		if _touch_ui and Time.get_ticks_msec() - _drag_press_at < TOUCH_DRAG_LONG_PRESS_MS:
			return
		_begin_drag(_drag_press_idx)


func _begin_drag(idx: int) -> void:
	if idx < 0 or idx >= hand_buttons.size():
		return
	var btn = hand_buttons[idx]
	if not is_instance_valid(btn):
		return
	_drag_active = true
	_drag_from = idx
	_drag_slot = idx
	# 拖拽期间吞掉 Button 补发的 pressed，避免"拖完顺带选中"
	_drag_suppress_click = true
	# 收起悬停态：牌要淡出，抬起补间和详情文本都得先还原
	_set_hover_index(-1)
	_restore_card_info()
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	_drag_grab = hand_container.get_local_mouse_position() - base
	btn.modulate = Color(1, 1, 1, DRAG_SOURCE_ALPHA)
	_drag_ghost = _make_drag_ghost(btn)
	_drag_line = _make_drag_line()
	_update_drag_follow()


# 幽灵牌：复制被拖的牌（复刻牌面），只要不吃鼠标就不会干扰判定
func _make_drag_ghost(src: Button) -> Control:
	var ghost := src.duplicate() as Control
	if ghost == null:
		return null
	ghost.name = "DragGhost"
	ghost.z_index = Z_DRAG
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.modulate = Color(1, 1, 1, DRAG_GHOST_ALPHA)
	hand_container.add_child(ghost)
	return ghost


# 插入位置指示线（主题蓝竖线，高度与牌同高）
func _make_drag_line() -> ColorRect:
	var line := ColorRect.new()
	line.name = "DragInsertLine"
	line.color = BORDER_FOCUS
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = Z_DRAG
	line.size = Vector2(DRAG_LINE_W, CARD_H)
	hand_container.add_child(line)
	return line


func _update_drag_follow() -> void:
	var mp: Vector2 = hand_container.get_local_mouse_position()
	if is_instance_valid(_drag_ghost):
		_drag_ghost.position = mp - _drag_grab
	_drag_slot = _insert_slot_at(mp.x)
	if is_instance_valid(_drag_line):
		var lx: float = _slot_x(_drag_slot)
		_drag_line.position = Vector2(lx - DRAG_LINE_W * 0.5, _hand_base_y())
		_drag_line.size = Vector2(DRAG_LINE_W, CARD_H)


# 插入槽位：鼠标落在哪张牌中点的左侧就插在它前面，全在右侧则插到末尾
func _insert_slot_at(x: float) -> int:
	var n: int = hand_buttons.size()
	for i in range(n):
		var b = hand_buttons[i]
		if not is_instance_valid(b):
			continue
		var bx: float = b.get_meta("base_pos", b.position).x
		if x < bx + CARD_W * 0.5:
			return i
	return n


# 槽位对应的 x（用静止坐标 base_pos，不受落下补间影响）
func _slot_x(slot: int) -> float:
	var n: int = hand_buttons.size()
	if n == 0:
		return hand_container.size.x * 0.5
	if slot < 0:
		slot = 0
	if slot < n:
		var b = hand_buttons[slot]
		if is_instance_valid(b):
			return b.get_meta("base_pos", b.position).x
	var last = hand_buttons[n - 1]
	if is_instance_valid(last):
		return last.get_meta("base_pos", last.position).x + CARD_W
	return hand_container.size.x * 0.5


func _hand_base_y() -> float:
	return hand_container.size.y - CARD_H - HOVER_LIFT


# 松手：槽位 → 目标下标 → 改数据层顺序 → 整排重建
# drop_pos 默认取真实鼠标位置；自动化测试（headless 鼠标恒在 0,0）可注入落点
func _finish_drag(drop_pos: Vector2 = Vector2.INF) -> void:
	if not _drag_active:
		return
	var from: int = _drag_from
	var slot: int = _drag_slot
	var gp: Vector2 = get_global_mouse_position() if drop_pos == Vector2.INF else drop_pos
	var in_zone: bool = hand_container.get_global_rect().has_point(gp)
	_reset_drag_visuals()
	_drag_active = false
	_drag_from = -1
	_drag_slot = -1
	_drag_press_idx = -1
	var cp = game_manager.get_current_player() if game_manager != null else null
	var moved: bool = false
	if in_zone and cp != null and not cp.is_ai and from >= 0 and slot >= 0:
		# 抽出源牌后，落在它后面的槽位整体左移一格
		var to: int = slot if slot <= from else slot - 1
		moved = cp.move_card(from, to)
	if moved:
		_reorder_tip = "已切换为手动排列，点『按序 ⇅』可恢复自动排序"
	else:
		_reorder_tip = ""
	# 顺序已变（或需要复位淡出效果）→ 整排重建；拖拽后的 pressed 由抑制标志吞掉
	_update_hand_buttons()
	_update_card_info_label()
	_update_hand_reorder_button()
	# 抑制标志延后一帧清除：pressed 可能在本帧稍后由 Button 发出
	call_deferred("_clear_drag_suppress")


func _clear_drag_suppress() -> void:
	_drag_suppress_click = false


# 清掉幽灵牌 / 指示线，并把原位牌的不透明度还原
func _reset_drag_visuals() -> void:
	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null
	if is_instance_valid(_drag_line):
		_drag_line.queue_free()
	_drag_line = null
	if _drag_from >= 0 and _drag_from < hand_buttons.size():
		var b = hand_buttons[_drag_from]
		if is_instance_valid(b):
			b.modulate = Color(1, 1, 1, 1)


# 重建手牌 / 切阶段时强制收尾（不落到数据层，顺序不变）
func _cancel_drag() -> void:
	_reset_drag_visuals()
	_drag_active = false
	_drag_from = -1
	_drag_slot = -1
	_drag_press_idx = -1


# -------- 悬停判定：固定矩形 + 状态机（不用 mouse_entered/exited） --------
# 卡牌抬起会改变自身几何。若用引擎 enter/exit 判定就会自激抖动：
# 抬起 → 让出底部 20px → exited → 落回 → entered → 再抬起 → ……
# 重叠区还会出现两张牌互相抢 hover。这里改为用「静止坐标」算命中区，
# 悬停状态永远不参与判定，因此不可能自激。
func _process(_delta: float) -> void:
	# 拖拽优先：拖拽期间不跑悬停状态机（否则牌会随鼠标反复抬起/落下抖动）
	_update_hand_drag()
	if _drag_active:
		return
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


# 指针真正指着的那张牌 —— 点击 / 拖拽起点都用它，保证「所见即所得」：
#   1) 已抬起的牌 z_index=20，压住了左右相邻牌，它的绘制矩形内一律归它；
#      若这里仍按最大索引取，玩家看着 Ca（已抬起）、点下去却选中被它盖住的右侧那张。
#   2) 没有抬起牌（刚移过来、还在 60ms 稳定延迟内快速点击）时，
#      按静止几何取最大索引 —— 静止堆叠时后一张本来就画在前一张上面。
func _hit_card_at(mp: Vector2) -> int:
	if _hover_idx >= 0 and _hover_idx < hand_buttons.size():
		var cur = hand_buttons[_hover_idx]
		if is_instance_valid(cur) and _card_raised_rect(cur).has_point(mp):
			return _hover_idx
	var hit: int = _hover_hit_index(mp)
	# 触屏档（C）：手指比鼠标粗，落点常压在牌边缘外 3~6px 或牌缝里，
	# 严格命中不到就白点一次。这里只做「兜底」——严格命中优先，
	# 否则才用外扩 TOUCH_HIT_PAD 的矩形找最近的一张，不会改变正常点选的判定。
	if hit < 0 and _touch_ui:
		hit = _hover_hit_index_padded(mp, TOUCH_HIT_PAD)
	return hit


# 命中矩形外扩版本（触屏兜底用）：仍按「越靠右的牌画得越上」取最大索引
func _hover_hit_index_padded(mp: Vector2, pad: float) -> int:
	var hit := -1
	for i in range(hand_buttons.size()):
		var b = hand_buttons[i]
		if not is_instance_valid(b): continue
		if _card_hover_rect(b).grow(pad).has_point(mp):
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
	# 触屏档（C）：Android 把「最后一次手指位置」当成鼠标位置，手指抬起后没有
	# mouse_exited → 抬起状态永远粘在最后点过的那张牌上：牌不落、下方信息栏一直
	# 显示它的详情，再点别的牌还要先等 60ms 悬停切换，手感就是「慢半拍 / 不知道选没选」。
	# 所以触控下悬停只在「按住」期间存在：松手立即落下并还原信息栏。
	if _touch_ui and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _hover_idx != -1: _set_hover_index(-1)
		_hover_pending_idx = -1
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
	# 只读视角不跑悬停状态机：牌不该抬起，否则看着像可点。
	# 唯一的强制点放在这里 —— _update_hand_hover 与测试注入都必须经过它。
	if _hand_read_only:
		if _hover_idx != -1: _set_hover_index(-1)
		_hover_pending_idx = -1
		return
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
		# 落回时把「选中常驻上浮」一起算进去：否则触屏上刚选中的牌被悬停一次、
		# 松手后又落回原位，选中的视觉提示就消失了
		var rest_lift: float = _selected_lift() if idx in selected_indices else 0.0
		_tween_card_y(btn, base.y - rest_lift)
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
	# 牌对象本身也存一份：重建 / 重排后靠它确认"这个按钮画的是哪张牌"，
	# 不再依赖 hand_idx（索引会随重排变化）
	btn.set_meta("card", card)
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
	l_num.name = "CardNumber"          # 具名：触屏档测试按名字取字号（校验 12 → 14）
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", _touch_fs(12, 2))
	l_num.add_theme_color_override("font_color", Color(0.25, 0.28, 0.32, 1))
	l_num.position = Vector2(4, 2)
	btn.add_child(l_num)

	var l_group = Label.new()
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", _touch_fs(11, 2))
	# 固定深灰：不跟随元素类别色（类别色深浅差异大，族名要保持稳定可读）
	l_group.add_theme_color_override("font_color", Color(0.3, 0.32, 0.36, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(52, 15)
	l_group.position = Vector2(38, 2)
	btn.add_child(l_group)

	var l_sym = Label.new()
	l_sym.name = "CardSymbol"
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", _touch_fs(28, 4))
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
	l_name.add_theme_font_size_override("font_size", _touch_fs(14, 3))
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
	l_val.add_theme_font_size_override("font_size", _touch_fs(13, 2))
	l_val.add_theme_color_override("font_color", Color(0.55, 0.2, 0.2, 1))
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_val.size = Vector2(85, 18)
	l_val.position = Vector2(5, 72)
	btn.add_child(l_val)

	var l_mass = Label.new()
	l_mass.name = "CardMass"           # 具名：触屏档测试按名字取字号（校验 9 → 12）
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", _touch_fs(9, 3))
	l_mass.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	l_mass.position = Vector2(3, 102)
	btn.add_child(l_mass)

	# 点击目标由「静止几何 + 取最上层」重算（与悬停同规则），
	# 不直接用 Button 原生拾取：悬停抬升会把牌上移，原生拾取会落到被让开的下层牌
	btn.pressed.connect(_on_card_pressed)
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
# Button 原生拾取用的是「当前几何」，而悬停抬起的牌已经上移了 HOVER_LIFT：
# 鼠标落在重叠区下沿时，抬起牌让出的那条带会判给被它压住的下层牌 ——
# 视觉上最上层是抬起的那张，点中的却是下面那张。
# 这里改用与悬停 / 拖拽同一套「所见即所得」规则重新定位（见 _hit_card_at）。
func _on_card_pressed() -> void:
	if hand_container == null or hand_buttons.is_empty():
		return
	var idx: int = _hit_card_at(hand_container.get_local_mouse_position())
	if idx < 0 or idx >= hand_buttons.size():
		return
	_on_card_clicked(idx)


func _on_card_clicked(index: int) -> void:
	# 拖拽结束后 Button 会补发一次 pressed：吞掉，避免"拖完顺带选中"
	if _drag_suppress_click:
		_drag_suppress_click = false
		return
	# 只读视角（AI 回合查看自己的手牌）不接受选牌
	if _hand_read_only:
		return
	if step_mode != 0 and step_mode != 3: return
	# 玩家自己动牌 → 提示作废，回到用户自己的选择
	if _hint_text != "":
		_clear_hint()
	if index in selected_indices: selected_indices.erase(index)
	else: selected_indices.append(index)
	# 触屏档（C）：30ms 轻震，作为「选中 / 取消」的触摸反馈
	# （Android 需要在 export_presets 打开 permissions/vibrate，已开；桌面 / 无马达设备静默无效）
	if _touch_ui:
		Input.vibrate_handheld(30)
	_update_hand_buttons()
	_update_action_panel()
	_update_card_info_label()

func _on_step_next() -> void:
	_clear_hint()
	step_mode = 1
	_update_action_panel()
	_update_card_info_label()

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
	# 卤族互化：默认禁止（硬规则）；开始页勾选「允许卤族互化」后放行。
	# 引擎侧 play_cards() 同样会拦（返回 -7），这里只是提前给出更友好的提示。
	if not game_manager.get_halogen_exchange_allowed() and _is_halogen_only(symbols):
		_show_info("卤族元素(F/Cl/Br/I)之间不可互相化合！请加入金属或其他非金属元素，或在开始页勾选『允许卤族互化』。")
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
	_clear_hint()
	step_mode = 0
	compound_selections.clear()
	_update_action_panel()
	_update_card_info_label()

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
	elif result == -3:
		var cp_err = game_manager.get_current_player() if game_manager != null else null
		if cp_err != null and cp_err.clan_bomb_cooling:
			msg = "族炸冷却中 ❄：需先打出一张化合物才能解除冷却"
		else:
			msg = "不能出族炸！"
	elif result == -4: msg = "牌型不匹配！"
	elif result == -6: msg = "不符合顺序指定的牌型约束！"
	elif result == -7: msg = "卤族元素(F/Cl/Br/I)之间不可互相化合！（可在开始页勾选『允许卤族互化』）"
	elif result == -8: msg = "该元素不在本局牌库中（已开启『元素限制』：前 20 号元素 + 自选扩展）"
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
		btn.position = Vector2(320 + (i % 3) * 150, 370 + int(i / 3.0) * 50)
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
	cancel_btn.position = Vector2(470, 370 + int(patterns.size() / 3.0) * 50 + 10)
	overlay.add_child(cancel_btn)

	_layer(1).add_child(overlay)


# ============================================================
func _step_reset() -> void:
	_clear_hint()
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
	# 已被 _refresh_ui 反复调用：已在结算页时只刷新数据，不重播淡入 / 入场动画（否则每帧闪一下）
	var already_shown: bool = end_page.visible and is_equal_approx(end_page.modulate.a, 1.0)
	start_page.visible = false
	game_page.visible = false
	end_page.visible = true
	if help_page: help_page.visible = false
	# 结束页独占屏幕：教学关卡列表（可能刚从开始页打开）也一并收起，
	# 否则它会盖在 EndPage 之上（TutorialPage 在 Main.tscn 里排在 EndPage 之后）
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	# 先填数据（标题 / 统计 / 按钮去向），再淡入：观众看到的第一帧就是最终态
	_fill_end_page(custom_text)
	if already_shown:
		return
	_fade_in_page(end_page)
	_page_deco_float(end_page)
	_animate_page_intro(end_page, ["EndCard"])


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
# UI 侧预检（符号数组）：与引擎 GameManager.is_halogen_mix(cards) 判据一致。
# 真正的规则判定在 play_cards()（返回 -7），这里只为「合成化合物」按钮提前挡住。
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
