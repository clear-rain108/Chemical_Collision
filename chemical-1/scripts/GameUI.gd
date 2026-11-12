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
# 联机（P11-C1-c Step 3）：动作走 ActionRouter，局面刷新走 NetSession 信号
const ActionRouterScript = preload("res://scripts/net/ActionRouter.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
# 房间页（Step 4）：会话与传输都由页内创建，建好后一律交给 attach_session() 装配
const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")

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
var _log_panel: Panel = null            # 日志底板（半透明圆角，与 log_label 同显隐）
var _log_title: Button = null           # 日志标题条（点一下折叠 / 展开）
var _log_visible: bool = true           # 整体显隐（规则提醒占用右栏时为 false）
var _log_collapsed: bool = false        # 折叠态：只留 26px 标题条
var _rule_tip_title: Button = null      # 规则提醒标题条
var _rule_tip_collapsed: bool = false   # 规则提醒折叠态
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
var _drag_press_pos: Vector2 = Vector2.ZERO   # 按下时的全局坐标（算阈值用）
var _drag_max_move: float = 0.0         # 本次按下到松手的最大位移（触屏「回退成点选」判定用）
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

# ------------------------------------------------------------
# 联机（P11-C1-c Step 3，决策 D6~D11 见 MULTIPLAYER_TASKS.md）
#   · net_session == null 时，本文件所有联机分支都不生效 —— 单机路径逐字不变
#   · 装配只有一处入口：attach_session(session)（房间页 / 测试都走它）
#   · 动作统一走 action_router（单机 = 直连 GameManager，返回码与今天等价）
# ------------------------------------------------------------
const NET_AI_DELAY_S := 1.2             # 联机 AI 思考节流（对齐单机 1.5s 的节奏）
var net_session = null                  # NetSession 实例；单机恒 null
var action_router = null                # ActionRouter 实例；attach_session 时创建
var _net_ai_wait: float = 0.0           # 联机 AI 计时累加（仅主机用）
var _seq_overlay: Control = null        # 顺序牌型弹窗（sequence_cleared 时收掉）

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

# 卡面化合价文本（多价元素会顶出卡边，见 _fit_card_valence）
# 实测：Cl "-1 +1 +3 +5 +7" 在 13px 下 85px（=整张卡宽），触屏 15px 达 98px；
# 紧凑档 label 只有 44 宽 → 必须按可用宽度收缩，否则文字画到卡片外面。
const CARD_VAL_PAD := 6                 # 价态文本在 label 内的左右留白（85 → 可用 79，44 → 38）
# 收缩下限：旧值 10 会把「+4+2-4」这类 3 价元素压成糊字（截图反馈「不美观」）。
# P14-A 起统一策略：宁可退到「首末价」也不降字号 —— 卡面显示的价数可变，字号不变。
const CARD_VAL_MIN_FS := 11

# 拖拽重排（P7）
const DRAG_THRESHOLD := 6.0             # 移动超过该距离才算拖拽（否则仍按点击处理）
const DRAG_GHOST_ALPHA := 0.85          # 幽灵牌不透明度
const DRAG_SOURCE_ALPHA := 0.28         # 原位牌淡出程度（表示"这张被拿起来了"）
const DRAG_LINE_W := 3.0                # 插入指示线宽度
# 触屏软启动：起拖门槛只有 10px，绝大多数「点选 + 手抖」都会走到 _finish_drag 的回退分支，
# 淡出若一步到底（0.28）会闪一下；源牌 0.55 / 幽灵 0.9，回退时几乎看不出变化。
const TOUCH_DRAG_SOURCE_ALPHA := 0.55
const TOUCH_DRAG_GHOST_ALPHA := 0.9

# ------------------------------------------------------------
# 触屏档案（Android / 移动端，A1+B+C）
# ------------------------------------------------------------
# 铁律：本节以上的所有 const 都是「桌面基准值」，24 套 headless 测试直接读它们做断言；
# 移动端的放大值一律走 *_touch() 取值函数，**const 一个都不改** ——
# 于是 _touch_ui=false（桌面 / 自动化）时行为与 P11 逐像素一致，
# _touch_ui=true（真机）时按钮/字号/手势切到触控档。
# 换算基准：1080p 手机横屏 2340×1080 → 缩放 1.667 → 1 逻辑 px ≈ 0.667dp，
#   32px 的工具行只有 21dp（Android 建议 ≥48dp），必须放大。
var _touch_ui: bool = false             # 触屏档案开关（_ready 里按平台特性 / 命令行置位）
var _touch_ui_manual: bool = false      # 玩家在开始页手动拨过开关（P14-D，仅用于提示文案 / 测试断言）
var _quit_confirm_pending: bool = false # 触屏「退出游戏」二次确认（防误触直接跳结算页）
var _ap_refit_left: int = 2             # A6-2：出牌面板被最小尺寸夹住时的剩余重算次数（防死循环）
const TOUCH_BTN_MIN_H := 48             # 触控目标最小高度（≈32dp）
const TOUCH_FS_BONUS := 2               # 页面按钮 / 标签字号通用加成
const TOUCH_TOOL_BTN_H := 48            # 工具行：32 → 48（下沿 590，仍让 ActionPanel 9px）
const TOUCH_TOOL_BTN_TOP := 542         # 工具行顶：558 → 542（上让 CardInfoLabel 16px）
const TOUCH_TOOL_BTN_GAP := 20          # 工具行间距：10 → 20（"帮助"与"退出游戏"不再贴脸误触）
const TOUCH_DRAG_ARM_MOVE := 10.0       # 按下后位移 ≥10px 立即起拖跟手（≈7dp，不再等 300ms 长按）
const TOUCH_DRAG_THRESHOLD := 24.0      # 确认阈值（≈16dp）：松手总位移 ≥24px 才算重排，<24px 回退成点选
const TOUCH_SELECT_LIFT := 10.0         # 选中牌常驻上浮（与悬停 20 区分，一眼看出选了谁）
const TOUCH_HIT_PAD := 8.0              # 触屏命中外扩缓冲（≈5dp，手指比鼠标粗）

# ---- 触屏档案的「怎么判定」（A6-1：让桌面也能开触控档）----
# 判定顺序：命令行强制 > 平台特性（OS.has_feature("mobile")）。
#   --touch-ui   桌面 / CI 上强制打开触控档 —— 不用真机就能看到 48px 按钮、
#                10px 选中上浮、24px 拖拽阈值到底长什么样
#   --desktop-ui 真机上强制关掉 —— 排查「是不是触屏档导致的」时用
# 两者同时出现时**后写的那个赢**（与常见 CLI 习惯一致）。
# 纯函数（不读全局状态）：测试可以直接喂参数，不用真的重启进程。
static func resolve_touch_profile(is_mobile: bool, args: Array) -> bool:
	var profile := is_mobile
	for raw in args:
		var a := String(raw)
		if a == "--touch-ui":
			profile = true
		elif a == "--desktop-ui":
			profile = false
	return profile


# 当前进程的命令行参数：Godot 自带参数与「-- 之后的用户参数」都扫一遍，
# 于是 `godot --path . --touch-ui` 与 `godot --path . -- --touch-ui` 都能生效。
static func touch_profile_args() -> Array:
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	return args



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
const BUTTON_RADIUS := 6        # 按钮（比卡牌小一档：同一屏里按钮更小，8px 会显得过圆）
const PANEL_RADIUS := 10        # 面板 / 提示框
const CHIP_RADIUS := 5          # 圆底 chip（卡面价态 / 元素 chip）
const CARD_VAL_CHIP_H := 16     # 卡面价态圆底高度
const CARD_VAL_CHIP_PAD := 5    # 圆底在文字左右各多出的宽度
const CARD_VAL_Y := 72.0        # 卡面价态行（圆底 + 文字）的纵向位置
const LOG_PANEL_PAD := 10       # 右栏面板的上 / 下 / 右留白（左侧贴齐正文，别再压到退出按钮）
const LOG_TITLE_H := 26         # 右栏可折叠标题条高度（折叠后整体只剩 10+26+10 = 46）
const LOG_TEXT_PAD := 12        # 标题 / 正文相对面板左边缘的缩进
const LOG_BODY_GAP := 6         # 标题条与正文之间的间距
const LOG_CONTENT_MIN_H := 40   # 正文最小高度（只有 1 行时也不塌成一条缝）
const LOG_CONTENT_MAX_H := 280  # 正文最大高度（日志 6 行 / 规则提醒 10 行都够）
const LOG_W := 312              # 右栏面板宽度（面板 = LOG_W + LOG_PANEL_PAD = 322）
const RIGHT_PANEL_HL_PAD := 4   # 教程第零关「其他细节（右面板）」高亮框相对面板的外扩量
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
const TABLE_TEXT_COLOR := Color(0.17, 0.24, 0.31, 1.0)  # 桌面文字常态（单质 / 空桌）

# ---- 动效规范（P3）：页面淡入 / 按钮缩放 ----
# 页面淡入采用「根节点常驻同色底 + 目标页 modulate 0→1」，不改 visible 语义：
# 交叉淡化必须延迟隐藏旧页，而 _on_help_back() 等处会同步读 *.visible 判断去向，
# 延迟隐藏会引入竞态，故一律保持 visible 同步，只做视觉层淡入。
const PAGE_BG_COLOR := Color(0.902, 0.941, 0.98, 1.0)   # #E6F0FA，与各页背景同色
const PAGE_FADE_MS := 220                                # 页面淡入时长
const BUTTON_HOVER_SCALE := 1.05                         # 按钮悬停放大
const BUTTON_PRESS_SCALE := 0.96                         # 按钮按下回缩
const BUTTON_SCALE_MS := 90                              # 缩放补间时长
# 手牌缩放（A2）：手牌是主角，悬停档比按钮再大一格；选中档小于悬停档，
# 保证「悬停中的选中牌」不会被撑得压住邻居（命中判定用静态矩形，缩放不参与）。
const HAND_HOVER_SCALE := 1.06                           # 悬停放大
const HAND_SELECT_SCALE := 1.04                          # 选中常驻放大（触屏没有悬停，靠它示意）
const HAND_SCALE_MS := 120                               # 手牌缩放补间时长
# 桌面区（A2）：小卡入场 + 牌型文字换行淡入
# A5 整体放慢：160ms 的入场在 60fps 下只有 9 帧，观感接近「瞬间出现」，
# 320ms 才有「滑进来」的过程感；顺序出牌时 4 张牌要逐个看清，stagger 也一起加倍。
const TABLE_REVEAL_MS := 300                             # 「桌面: …」文本变化时淡入时长
const MINI_CARD_IN_MS := 320                             # 小卡入场（0.9 → 1.0 + 淡入）时长
const MINI_CARD_IN_STAGGER := 0.08                       # 多张小卡依次入场的间隔（秒）
# 出牌 / 弃牌 / 抽牌（A3）：全部走「幽灵牌」——原按钮会被 _refresh_ui 整块重建，
# 只有 duplicate 出来的副本能跨过重建继续飞行。
# A5：原 260/240/180ms 都压在 0.3s 以内，牌几乎「闪」过去；统一放慢到 0.4~0.5s，
# 并给飞行动画加抛物线抬升（直线平移在小屏上会被看成「原地淡出」）。
const PLAY_FLY_MS := 480                                 # 出牌：手牌 → 桌面小卡的飞行时长
const PLAY_FLY_SCALE := 0.76                             # 终点缩放（95×118 → 72×90 小卡）
const PLAY_FLY_ARC := 40.0                               # 飞行弧线中点抬高（二次贝塞尔控制点）
const DISCARD_FLY_MS := 420                              # 弃牌：向上抬起并淡出
const DISCARD_FLY_LIFT := 64.0                           # 弃牌抬起高度
const DEAL_IN_MS := 380                                  # 新抽的牌落下 + 淡入时长（首次渲染也算「发牌」）
const DEAL_IN_DROP := 52.0                               # 落下的起点高度（牌从手牌区上方落进来）
const DEAL_IN_STAGGER := 0.06                            # 多张新牌依次入场的间隔（秒）

# ---- 警告 toast：右栏上部空白格 ----
# LogLabel 从 y=300 起、TutorialLabel 从 y=186 起、InfoLabel 只到 x=480，
# 因此 (824,62)-(1136,178) 不与任何静态节点相交，也就不会遮住手牌。
const TOAST_DURATION := 2.5
const WARNING_TOAST_RECT := Rect2(824, 62, 312, 116)

# ---- 左上状态栏（InfoLabel）行数上限 ----
# InfoLabel 是 (20,62)-(480,150)：14px 字只放得下 4 行，再往下就是 y=152 的「桌面: …」。
# 它只负责常驻状态（玩家链 / AI 手牌 / 补充规则 / 方向）；一次性消息一律走右栏 toast，
# 两边同时显示还会撞行（P14-E）。
const INFO_LABEL_MAX_LINES := 4

# 三个层容器（GamePage 的直接子节点，_ensure_layers() 幂等创建）
var content_layer: Control = null
var overlay_layer: Control = null
var toast_layer: Control = null

# 警告 toast（单例复用：连续报错只更新文本并重置计时，不叠框、不被旧计时器提前熄灭）
var _warning_toast: Control = null
var _warning_label: Label = null
var _warning_seq: int = 0
var _table_sig: String = ""             # 桌面小卡内容签名（同一批牌不重播入场动画）
var _hand_seen_cards: Array = []        # 上次渲染过的卡片对象（判定「新抽到的牌」→ 发牌淡入）

# 页面淡入补间（全局单例：同一时刻只允许一个页面在淡入）
var _page_fade_tween: Tween = null

# ============================================================
# 第零关覆盖层 (Phase 1: UI介绍, Phase 2: 流程说明)
# ============================================================
var level0_overlay: Control = null
var level0_step: int = 0
var level0_ui_highlight_steps: Array = []
var level0_flow_steps: Array = []
var level0_flow_index: int = 0


# ============================================================
# 四、初始化
# ============================================================
func _ready() -> void:
	# 触屏档案（Android / iOS）：只影响按钮尺寸、字号与手势，不改任何布局坐标。
	# A6-1：桌面 / CI 可以用 --touch-ui 强制打开（--desktop-ui 强制关掉），
	# 这样触控档的布局不用真机也能看、也能进自动化测试。
	var is_mobile := OS.has_feature("mobile")
	_touch_ui = resolve_touch_profile(is_mobile, touch_profile_args())
	if _touch_ui != is_mobile:
		print("[UI] 触屏档案 = %s（命令行强制；平台 mobile=%s）" % [str(_touch_ui), str(is_mobile)])
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
	# 触屏界面开关（P14-D）：不用命令行也能切触控档
	var touch_tg = _start_child("TouchUIToggle")
	if touch_tg:
		touch_tg.toggled.connect(_on_touch_ui_toggled)

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
	# 房间页（Step 4）：开始页「联机对战」→ 建房 / 加入。
	# 页内按钮在 _build_room_page() 里已用回调绑定，这里不再 connect（否则报已连接）
	var room_entry = _start_child("RoomEntryBtn")
	if room_entry:
		room_entry.pressed.connect(_open_room_page)
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
		# 状态栏几何只有 4 行（y=62~150，14px 字）；历史 bug：_show_info() 把拒绝原因拼在后面，
		# 第 5 行开始溢出到 y=152 的「桌面: …」上（P14-E 真机截图）。引擎级兜底，别再溢出。
		if info_label:
			info_label.max_lines_visible = INFO_LABEL_MAX_LINES
			info_label.clip_text = true
		table_label = game_page.get_node_or_null("TableLabel")
		log_label = game_page.get_node_or_null("LogLabel")
		_ensure_log_panel()
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
	_apply_touch_sizing(_room_page)
	# 开关初值跟随当前档位（--touch-ui / 平台判定），用 no_signal 避免误触发一次「已开启」提示
	_sync_touch_toggle()


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
			# 按钮圆角比卡牌小一档（BUTTON_RADIUS=6）：按钮尺寸更小，8px 在同一屏会显得过圆
			_style_base(sb, Color(0.173, 0.243, 0.314, 1.0), Color(0.4, 0.55, 0.7, 1.0), BORDER_W, BUTTON_RADIUS, true)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
		"log_panel":
			# 日志底板：白色半透明 + 中性描边，压在浅蓝背景上把日志框住。
			# 半透明是为了不切断右侧留白的整体感（不透明白卡会像多出一块面板）。
			_style_base(sb, Color(1.0, 1.0, 1.0, 0.62), BORDER_NEUTRAL, BORDER_W, PANEL_RADIUS, true)
		"log_title":
			# 右栏折叠标题条：半透明白底 + 底部 1px 分隔线（叠在同色底板上要能看出是「一条」）
			_style_base(sb, Color(1.0, 1.0, 1.0, 0.42), Color(0.83, 0.87, 0.92, 1.0), 0, BUTTON_RADIUS, false)
			sb.border_width_bottom = 1
			sb.content_margin_left = LOG_TEXT_PAD
			sb.content_margin_right = 8
		"log_title_hover":
			# 悬停只把底色提亮一档，不换描边（避免标题条跳动）
			_style_base(sb, Color(1.0, 1.0, 1.0, 0.72), Color(0.83, 0.87, 0.92, 1.0), 0, BUTTON_RADIUS, false)
			sb.border_width_bottom = 1
			sb.content_margin_left = LOG_TEXT_PAD
			sb.content_margin_right = 8
		"valence_chip":
			# 卡面价态圆底：极浅暖底，把 12~15px 的红色价态文字从白卡面上托起来
			_style_base(sb, Color(0.98, 0.93, 0.93, 1.0), Color(0, 0, 0, 0), 0, CHIP_RADIUS, false)
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
	# Step 4：回开始页 = 离开房间（关会话 + 断开装配，D13）。没有会话时是空操作
	_close_room_page()
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
	# 教学局残留的规则提醒也一并清掉（它挂在 ContentLayer 上，会跟着进下一局）
	_level0_clear_rule_tips()
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

# ------------------------------------------------------------
# 房间页（P11-C1-c Step 4，决策 D12~D15 见 MULTIPLAYER_TASKS.md）
#   · 座位只能是 3~4：GameManager.MIN_PLAYERS = 3，而 NetSession.start_game()
#     把 player_count clamp 到 2..4 —— 2 座位会在 init_game 里直接失败。
#   · 大厅没有 ready 握手：客人的 MSG_READY 是「快照重建完成」，开局后才发。
#     所以开局闸门是「在线人类数 + AI 数 ∈ [3,4]」，不是 all_seats_ready()。
# ------------------------------------------------------------
const ROOM_MIN_SEATS := 3                 # = GameManager.MIN_PLAYERS
const ROOM_MAX_SEATS := 4                 # = NetSession.DEFAULT_MAX_PLAYERS
const ROOM_DEFAULT_PORT := 47800          # = ENetTransport.DEFAULT_PORT
const ROOM_CONNECT_TIMEOUT_S := 8.0       # create_client 是异步的，连不上没有任何回调
enum RoomMode { IDLE, HOSTING, CONNECTING, JOINED }
var _room_page: Control = null
var _room_mode: int = RoomMode.IDLE
var _room_connect_wait: float = 0.0
var _room_join_target: String = ""        # 只用于「连不上 xxx」的提示文案
var _room_closing: bool = false           # 主动关会话时的重入闸（close 会同步发 session_closed）
var _room_seat_cards: Array = []          # 4 张座位卡（Panel）
var _room_seat_names: Array = []          # 座位卡上的昵称 Label
var _room_seat_states: Array = []         # 座位卡上的状态 Label
var _room_code_label: Label = null
var _room_hint_label: Label = null
var _room_host_ip_label: Label = null
var _room_host_name_edit: LineEdit = null
var _room_host_port_spin: SpinBox = null
var _room_join_name_edit: LineEdit = null
var _room_addr_edit: LineEdit = null
var _room_join_port_spin: SpinBox = null
var _room_create_btn: Button = null
var _room_join_btn: Button = null
var _room_leave_btn: Button = null
var _room_start_btn: Button = null
var _room_ai_spin: SpinBox = null


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
	# Step 4：房间页（同样盖在开始页之上，默认隐藏）
	_build_room_page()


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

	# P14-D：触屏界面开关。放在「补充规则」同一行的右侧 —— 卡内还剩约 250px，
	# 不改卡片高度（第 3 个开关曾把开局按钮挤出卡外，见 P10 的注释）。
	# 它不是游戏规则，所以不进补充规则小页，就摆在设置卡上随手可切。
	var touch_tg := _start_make_toggle("TouchUIToggle", "触屏界面 · 关", Vector2(344, 129))
	touch_tg.custom_minimum_size = Vector2(240, 32)
	touch_tg.size = Vector2(240, 32)
	touch_tg.add_theme_font_size_override("font_size", 15)
	touch_tg.tooltip_text = "按钮更高、字号 +2、手势更跟手（真机 / 平板推荐开启，随时可切回）"
	card.add_child(touch_tg)


func _start_setting_label(node_name: String, text: String, pos: Vector2) -> Label:
	var lb := _start_label(text, START_FS_LABEL, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	lb.name = node_name
	lb.position = pos
	lb.size = Vector2(230, 32)
	return lb


# -------- 按钮区 --------
# Step 4：开始页纵向已排到 632，只剩这一行有空间 —— 「开始游戏 / 联机对战」并排。
# 单机那颗字号 22 → 20：宽度从 260 收到 124，「开始游戏」四个字才不会撑破按钮。
func _start_page_buttons() -> void:
	start_button = _page_primary_btn("开始游戏", func() -> void: pass,
		Vector2(124, 52), "StartButton", 20)
	start_button.position = Vector2(446, 486)
	start_page.add_child(start_button)
	start_page.add_child(_start_make_secondary("RoomEntryBtn", "联机对战", Vector2(582, 486), Vector2(124, 52)))
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
# 入场名单必须覆盖开始页上每一个可见节点（顺序 = 视觉从上到下 / 从左到右）。
# 漏登记 = 那个节点不淡入也不上浮，页面淡入一结束就"抢先"以终态出现（Step 4 的
# RoomEntryBtn 就这么漏过一次）—— 测试 START_INTRO_ORDER 覆盖性断言会拦住这类遗漏。
const START_INTRO_ORDER := [
	"StartTitle", "StartSubtitle", "StartAccent", "StartMeta", "DecorCards",
	"SettingsCard", "StartRuleHint", "RoomEntryBtn", "StartButton", "TutorialBtn", "ExitButton",
]


func _animate_start_page() -> void:
	if not start_page:
		return
	_page_deco_float(start_page)
	_animate_page_intro(start_page, START_INTRO_ORDER)


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


# 常见化合价文本：与手牌卡面同一套裁剪规则（放不下只留两端价，Cl → -1 +7）
# 迷你卡只有 96 宽，Cl 的 5 个价全写会撑破卡片；原先是「前 2 个 + …」的独立实现，
# 与卡面 _fit_card_valence 不一致，现统一走 _format_valence_pair。
func _help_valence_text(card) -> String:
	if card == null:
		return "—"
	return _format_valence_pair(card.common_valence)


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
		{"t": "H₂O", "p": Vector2(30, 470), "fs": 72},
		{"t": "CO₂", "p": Vector2(884, 60), "fs": 56},
		{"t": "NaCl", "p": Vector2(58, 40), "fs": 48},
		{"t": "O₂", "p": Vector2(1000, 520), "fs": 44},
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
		{"t": "H₂O", "p": Vector2(36, 430), "fs": 68},
		{"t": "CO₂", "p": Vector2(896, 70), "fs": 54},
		{"t": "CH₄", "p": Vector2(1000, 500), "fs": 46},
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
	# 联机（Step 3）：开局只能由房间页 → session.start_game() 驱动。
	# 这里若不拦住，会在本地 new 一个 GameManager，直接和会话手里的那份分叉。
	if net_session != null:
		_show_info("联机对局请从房间页开局（本页仅用于单机 / 教程）")
		return
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
	_level0_clear_rule_tips()   # 清掉上一局第零关的规则提醒（否则会盖在教程 1/2 或正常对局的日志上）

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
	# 联机（Step 3，D11）：退出 = 关闭会话，绝不写 game.phase
	#   （本端写 phase 只是本地作废，主机那份局面不受影响，客人却以为自己结束了）
	if net_session != null:
		net_session.close("主动退出对局")
		_show_end_page("已退出联机对局")
		return
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


# 开始页 4 条补充规则 → GameManager（Step 4 从 _init_game 抽出来，单机行为逐字不变）
# 联机：房主这份会进 game_start 的 config 下发给客人；客人建房时读到的值会被
# NetSession._apply_config() 用主机的配置覆盖，所以客人这边填什么都不影响牌库。
func _apply_start_page_rules(gm) -> void:
	if gm == null:
		return
	# 读取开始页的补充规则勾选框状态（三个独立勾选框，嵌在 SettingsCard 内）
	var organic_cb = _start_child("OrganicCheckBox")
	if organic_cb:
		gm.organic_rules_enabled = organic_cb.button_pressed
	var seq_cb_node = _start_child("SequenceCheckBox")
	if seq_cb_node:
		gm.sequence_rules_enabled = seq_cb_node.button_pressed
	var halogen_cb_node = _start_child("HalogenCheckBox")
	if halogen_cb_node:
		gm.halogen_exchange_allowed = halogen_cb_node.button_pressed
	# 元素限制（P10）：前 20 号元素 + 小页里勾选的扩展元素
	var limit_cb_node = _start_child("ElementLimitCheckBox")
	gm.element_limit_enabled = limit_cb_node != null and limit_cb_node.button_pressed
	gm.allowed_extra_elements = _selected_extra_elements() if gm.element_limit_enabled else []


func _init_game(total: int = 4, ai: int = 3) -> void:
	# 新一局：教学局残留的规则提醒 / 日志缓存必须清掉，否则会跟着进正常对局
	_level0_clear_rule_tips()
	log_lines.clear()
	if log_label:
		log_label.text = "游戏日志:"
	game_manager = GameManagerScript.new()
	# 读取开始页的补充规则勾选框状态（三个独立勾选框，嵌在 SettingsCard 内）
	_apply_start_page_rules(game_manager)
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
			# 高亮框 = 1 行面板矩形；几何只有一处定义（§九 ACTION_PANEL_*），
			# 折行 / 触屏档都由 _action_panel_hl_rect() 跟随，改几何不会漏改这里
			"pos": _action_panel_hl_rect().position,
			"size": _action_panel_hl_rect().size,
		},
		{
			"title": "其他细节（右面板）",
			"desc": "这是【其他细节-右面板】\n游戏日志逐条记录每一手牌（谁出了什么、轮到谁）；第零关练习阶段这里换成「规则提醒」，写着当前该记住的出牌规则\n点标题条可折叠 / 展开",
			"target": "log_label",
			# 高亮框 = 右栏面板的实况矩形（见 _right_panel_hl_rect()）：
			# 折叠 / 日志条数 / 规则提醒占用都会改面板大小，写死矩形必然画歪
			"pos": _right_panel_hl_rect().position,
			"size": _right_panel_hl_rect().size,
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


func _level0_show_ui_step(idx: int) -> void:
	_refresh_ui()

	if idx >= level0_ui_highlight_steps.size():
		_level0_start_phase2()
		return

	var step_data = level0_ui_highlight_steps[idx]
	level0_step = idx
	# 右栏面板的几何会随「折叠 / 日志条数 / 规则提醒是否占用」变化，建 steps 时的坐标是快照，
	# 直接画会框住一片空白 → 展示时按节点实况刷新（_refresh_ui() 刚跑过，_layout_log_panel() 已算好几何）
	if step_data.get("target", "") == "log_label":
		var rp: Rect2 = _right_panel_hl_rect()
		step_data["pos"] = rp.position
		step_data["size"] = rp.size
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
	var canvas: Vector2 = game_page.size if game_page != null else Vector2(1152, 648)
	tbx = clampi(tbx, 20, maxi(20, int(canvas.x) - tbw - 20))
	tby = clampi(tby, 20, maxi(20, int(canvas.y) - tbh - 20))
	var tip_bg = ColorRect.new()
	tip_bg.color = Color(1, 1, 0.85, 0.95)
	tip_bg.position = Vector2(tbx, tby)
	tip_bg.size = Vector2(tbw, tbh)
	level0_overlay.add_child(tip_bg)

	var tip_border = _level0_make_outline_rect(Vector2(tbx, tby), Vector2(tbw, tbh), Color(1, 0.6, 0, 1), 3)
	level0_overlay.add_child(tip_border)

	var tip_title = Label.new()
	# 顺序很重要：Label 的 size 会被「未换行时的最小宽度」撑大，
	# 必须先开 autowrap 再定 size，否则文字会画到框外（实机截图 bug）
	tip_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_title.text = step_data.title
	tip_title.add_theme_font_size_override("font_size", 18)
	tip_title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	tip_title.position = Vector2(tbx + 24, tby + 14)
	tip_title.size = Vector2(tbw - 48, 24)
	level0_overlay.add_child(tip_title)

	var tip_desc = Label.new()
	tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_desc.text = step_data.desc
	tip_desc.add_theme_font_size_override("font_size", 14)
	tip_desc.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	tip_desc.position = Vector2(tbx + 24, tby + 44)
	tip_desc.size = Vector2(tbw - 48, 150)
	level0_overlay.add_child(tip_desc)

	# 步骤计数挪到右上角：提示框底部整行留给三个出口按钮
	var step_indicator = Label.new()
	step_indicator.text = "%d / %d" % [idx + 1, level0_ui_highlight_steps.size()]
	step_indicator.add_theme_font_size_override("font_size", 13)
	step_indicator.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	step_indicator.position = Vector2(tbx + tbw - 96, tby + 16)
	step_indicator.size = Vector2(72, 20)
	level0_overlay.add_child(step_indicator)

	# 三个出口（P15-A）：老实现只有「下一步」，而遮罩是 MOUSE_FILTER_STOP 全屏铺满，
	# 玩家必须把 6 步点完才能摸牌，想换关卡只能杀进程。
	var guide_h: float = float(_touch_btn_h(42))
	var guide_y: float = float(tby) + 206.0
	var next_text := "下一步 →" if idx < level0_ui_highlight_steps.size() - 1 else "继续 →"
	level0_overlay.add_child(_level0_guide_btn(
		Vector2(tbx + 24, guide_y), Vector2(130, guide_h), next_text, _level0_ui_next_step))
	level0_overlay.add_child(_level0_guide_btn(
		Vector2(tbx + 166, guide_y), Vector2(130, guide_h), "跳过引导", _level0_skip_guide))
	level0_overlay.add_child(_level0_guide_btn(
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
	level0_step += 1
	_level0_show_ui_step(level0_step)


# 引导阶段的通用出口按钮（Phase 1 提示框底部 / Phase 2 对话框底部共用）：
# 位置尺寸由调用方给（两处对话框的行高与列宽不同），字号统一走触屏档
func _level0_guide_btn(pos: Vector2, btn_size: Vector2, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = btn_size
	b.add_theme_font_size_override("font_size", _touch_fs(15, 2))
	b.position = pos
	b.size = btn_size
	b.pressed.connect(cb)
	return b


# 「跳过引导」：Phase 1 / Phase 2 都一步跳到牌局练习（开场提示与规则提醒照常给）。
# 遮罩是 MOUSE_FILTER_STOP 全屏，不给这条出口玩家就只能把 6+3 步点完才能摸牌。
func _level0_skip_guide() -> void:
	if game_manager == null:
		return
	_level0_start_phase3()


# 「返回关卡」：引导中途退出教学 → 回教学引导页重选关卡。
# _on_show_tutorial_page() 只处理「从开始页 / 结算页过来」的可见性，
# 这里必须自己把 GamePage 藏掉，否则引导页会被压在游戏页下面（点了像没反应）。
func _level0_exit_guide() -> void:
	if level0_overlay:
		level0_overlay.queue_free()
		level0_overlay = null
	level0_ui_highlight_steps = []
	level0_flow_steps = []
	_level0_clear_rule_tips()
	if game_manager:
		game_manager.phase = 2   # 本局作废：别让残留的 AI 计时器在后台继续推进
	if game_page:
		game_page.visible = false
	_on_show_tutorial_page()


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
	dialog_bg.size = Vector2(900, 190)
	level0_overlay.add_child(dialog_bg)

	var dialog_border = _level0_make_outline_rect(Vector2(100, 250), Vector2(900, 190), Color(0.3, 0.5, 0.8, 1), 3)
	level0_overlay.add_child(dialog_border)

	var title = Label.new()
	title.text = "游戏流程介绍 %d/%d" % [idx + 1, level0_flow_steps.size()]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.position = Vector2(130, 260)
	title.size = Vector2(840, 28)
	level0_overlay.add_child(title)

	var content = Label.new()
	# autowrap 必须在 size 之前：否则 size 会被「未换行整行宽」撑大
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.text = level0_flow_steps[idx]
	content.add_theme_font_size_override("font_size", 16)
	content.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	content.position = Vector2(130, 300)
	content.size = Vector2(840, 80)
	level0_overlay.add_child(content)

	# 底部三个出口：下一步 / 跳过引导 / 返回关卡（与 Phase 1 同一套按钮与语义）
	var btn_text = "下一步 →" if idx < level0_flow_steps.size() - 1 else "开始对局！"
	var flow_btn_h := float(_touch_btn_h(45))
	level0_overlay.add_child(_level0_guide_btn(
		Vector2(316, 382), Vector2(150, flow_btn_h), btn_text, _level0_flow_next_step))
	level0_overlay.add_child(_level0_guide_btn(
		Vector2(478, 382), Vector2(150, flow_btn_h), "跳过引导", _level0_skip_guide))
	level0_overlay.add_child(_level0_guide_btn(
		Vector2(640, 382), Vector2(150, flow_btn_h), "返回关卡", _level0_exit_guide))


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

	level0_ui_highlight_steps = []
	level0_flow_steps = []
	_refresh_ui()

	_level0_create_rule_tips()

	var intro_tip = _level0_make_tip_box("对局开始！请尝试出牌吧。\n本关 AI 每回合只出 1 张单质，不会抢在你前面打完。", 3.0)
	_layer(2).add_child(intro_tip)


var level0_rule_tip_label: Label = null
var level0_rule_tip_bg: Panel = null

func _level0_create_rule_tips() -> void:
	_level0_clear_rule_tips()
	# 与 LogLabel 同格：两者互斥显示，结构上不可能再重叠；几何统一交给 _layout_rule_tips()
	var home: Vector2 = Vector2(824, 300)
	if log_label and is_instance_valid(log_label):
		home = log_label.get_meta("home", log_label.position)
	level0_rule_tip_bg = Panel.new()
	level0_rule_tip_bg.name = "Level0RuleTipsBg"
	level0_rule_tip_bg.set_meta("home", home)
	level0_rule_tip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level0_rule_tip_bg.add_theme_stylebox_override("panel", _make_panel_style("toast_info"))
	_layer(0).add_child(level0_rule_tip_bg)

	# 标题条：和日志同一套可折叠交互（默认展开，点一下收成 26px 一行）
	_rule_tip_title = _make_right_column_title("Level0RuleTipsTitle", "规则提醒")
	_rule_tip_title.pressed.connect(_on_rule_tip_title_pressed)
	level0_rule_tip_bg.add_child(_rule_tip_title)

	level0_rule_tip_label = Label.new()
	level0_rule_tip_label.name = "Level0RuleTips"
	level0_rule_tip_label.add_theme_font_size_override("font_size", 13)
	level0_rule_tip_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	level0_rule_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level0_rule_tip_label.text = ""
	_layer(0).add_child(level0_rule_tip_label)
	_level0_update_rule_tips()
	_layout_rule_tips()


# 右栏可折叠标题条的共用构造（日志 / 规则提醒同一套外观与交互，避免两处各写一遍样式）
func _make_right_column_title(node_name: String, text: String) -> Button:
	var title := Button.new()
	title.name = node_name
	title.text = "%s ▾" % text
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.focus_mode = Control.FOCUS_NONE
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.22, 0.26, 0.32, 1))
	title.add_theme_color_override("font_hover_color", Color(0.12, 0.16, 0.22, 1))
	title.add_theme_color_override("font_pressed_color", Color(0.12, 0.16, 0.22, 1))
	title.add_theme_stylebox_override("normal", _make_panel_style("log_title"))
	title.add_theme_stylebox_override("hover", _make_panel_style("log_title_hover"))
	title.add_theme_stylebox_override("pressed", _make_panel_style("log_title"))
	title.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return title


func _on_rule_tip_title_pressed() -> void:
	_rule_tip_collapsed = not _rule_tip_collapsed
	_layout_rule_tips()


# 规则提醒几何：与日志同一条公式（标题 26 + 间距 6 + 正文），正文高度用 Label 实测最小高度
func _layout_rule_tips() -> void:
	if level0_rule_tip_bg == null or not is_instance_valid(level0_rule_tip_bg):
		return
	if level0_rule_tip_label == null or not is_instance_valid(level0_rule_tip_label):
		return
	var home: Vector2 = level0_rule_tip_bg.get_meta("home", Vector2(824, 300))
	var panel_w: float = LOG_W + LOG_PANEL_PAD
	var body_w: float = panel_w - LOG_TEXT_PAD - LOG_PANEL_PAD
	# 先定宽再量高：autowrap 的 Label 只有在宽度确定后才能算出换行后的真实高度
	level0_rule_tip_label.size = Vector2(body_w, LOG_CONTENT_MAX_H)
	var body_h: float = LOG_CONTENT_MIN_H
	if not _rule_tip_collapsed:
		body_h = clampf(level0_rule_tip_label.get_minimum_size().y, LOG_CONTENT_MIN_H, LOG_CONTENT_MAX_H)
	var panel_h: float = LOG_PANEL_PAD + LOG_TITLE_H + LOG_PANEL_PAD
	if not _rule_tip_collapsed:
		panel_h += LOG_BODY_GAP + body_h
	level0_rule_tip_bg.position = home
	level0_rule_tip_bg.size = Vector2(panel_w, panel_h)
	if _rule_tip_title and is_instance_valid(_rule_tip_title):
		_rule_tip_title.position = Vector2(0, LOG_PANEL_PAD)
		_rule_tip_title.size = Vector2(panel_w, LOG_TITLE_H)
		_rule_tip_title.text = "规则提醒 %s" % ("▸" if _rule_tip_collapsed else "▾")
	level0_rule_tip_label.position = Vector2(home.x + LOG_TEXT_PAD, home.y + LOG_TITLE_H + LOG_BODY_GAP)
	level0_rule_tip_label.size = Vector2(body_w, body_h)
	level0_rule_tip_label.visible = not _rule_tip_collapsed and level0_rule_tip_bg.visible


# 彻底清掉第零关规则提醒（跨局 / 退出教学时必须调）：
# 它挂在 ContentLayer 上，不随 GamePage 隐藏或 GameManager 重建而消失
func _level0_clear_rule_tips() -> void:
	if level0_rule_tip_label and is_instance_valid(level0_rule_tip_label):
		level0_rule_tip_label.queue_free()
	level0_rule_tip_label = null
	if _rule_tip_title and is_instance_valid(_rule_tip_title):
		_rule_tip_title.queue_free()
	_rule_tip_title = null
	if level0_rule_tip_bg and is_instance_valid(level0_rule_tip_bg):
		level0_rule_tip_bg.queue_free()
	level0_rule_tip_bg = null
	if log_label and is_instance_valid(log_label):
		_set_log_visible(true)


# 规则提醒 / 日志共用右栏同一格：互斥可见，永远不可能叠在一起
func _level0_set_rule_tips_visible(on: bool) -> void:
	if level0_rule_tip_bg and is_instance_valid(level0_rule_tip_bg):
		level0_rule_tip_bg.visible = on
	if level0_rule_tip_label and is_instance_valid(level0_rule_tip_label):
		level0_rule_tip_label.visible = on and not _rule_tip_collapsed
	if log_label and is_instance_valid(log_label):
		_set_log_visible(not on)


func _level0_update_rule_tips() -> void:
	if game_manager == null:
		return
	# 只有「第零关 · 牌局练习」这一段显示规则提醒；其余局面一律隐藏并让日志回到原位
	var in_level0_play: bool = game_manager.tutorial_level == 0 \
			and game_manager.tutorial_level0_phase == 3
	if not in_level0_play:
		if level0_rule_tip_label and is_instance_valid(level0_rule_tip_label):
			level0_rule_tip_label.text = ""
		_level0_set_rule_tips_visible(false)
		return
	if level0_rule_tip_label == null or not is_instance_valid(level0_rule_tip_label):
		return
	_level0_set_rule_tips_visible(true)
	level0_rule_tip_label.text = _level0_rule_tips_text()
	_layout_rule_tips()


# 第零关只教「越大越小 / 同类同出」：族炸是本关不引导的内容，规则层仍允许手打，
# 只有玩家自己真的打出族炸时，才补一条「牌权争夺」说明（避免默认就把新手带偏）
func _level0_rule_tips_text() -> String:
	var tip: String = game_manager.level0_rule_tip
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
	# autowrap 必须在 size 之前，否则中文字符串会把 Label 撑出背景板
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	lbl.position = Vector2(220, 355)
	lbl.size = Vector2(660, 60)
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
		# 桌面牌型以「打出时记录的 table_pattern」为准；按牌面重新检测会把
		# 「既是族炸又能配成化合物」的牌（如 N + P）显示成另一种，与判定结果矛盾。
		var pat = game_manager.get_table_pattern()
		if pat < 0:
			pat = CardPatternsScript.detect_pattern(game_manager.get_table_cards())
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
		# 同 _update_status_bar：桌面牌型一律取 table_pattern（打出时的真相）
		var pat = game_manager.get_table_pattern()
		if pat < 0:
			pat = CardPatternsScript.detect_pattern(cards)
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
		_set_table_text(txt, pat)

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
				# 混合价态（Fe₃O₄）按「每张牌一个价」显示：Fe 三张分别是 +3 / +3 / +2，
				# 而不是把平均值或其中一个价重复三遍。
				for e in pos_list2 + neg_list2:
					var plan: Array = e.get("plan", [])
					var k := 0
					for i in range(cards.size()):
						if cards[i].symbol == e.symbol:
							if bool(e.get("mixed", false)) and k < plan.size():
								card_valences[i] = int(plan[k])
							else:
								card_valences[i] = e.ox_state
							k += 1
		elif pat == CardPatternsScript.CardPattern.SEQUENCE:
			# 顺序牌按原子序数升序显示（与玩家选择顺序无关，体现连续序列）
			var sorted_cards: Array = cards.duplicate()
			sorted_cards.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)
			cards = sorted_cards
			for i in range(cards.size()):
				card_valences[i] = 0

		# 内容签名：同一批牌（uid）+ 同一牌型 → 不重播入场动画。
		# AI 每次行动都会走 _refresh_ui 整块重建小卡，不去重的话桌面会一直闪。
		var new_sig := "%d|" % pat
		for c in cards:
			new_sig += "%s%d," % [c.symbol, c.uid]
		var replay: bool = new_sig != _table_sig
		_table_sig = new_sig

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
			if replay:
				_animate_mini_card_in(mini_btn, i)
	else:
		_table_sig = ""
		_set_table_text("桌面: 空", -1)


# -------- 桌面「桌面: …」文本：按牌型上色 + 换行淡入（A2） --------
# 以前无论打出什么牌型都是同一行深灰小字，玩家要读完整句才知道发生了什么；
# 牌型色让「化合物 / 族炸 / 顺序」一眼可辨（族炸还会额外带 ⚠ 文案）。
func _table_type_color(pat: int) -> Color:
	match pat:
		CardPatternsScript.CardPattern.COMPOUND: return Color(0.11, 0.45, 0.29, 1.0)   # 深绿
		CardPatternsScript.CardPattern.CLAN_BOMB: return Color(0.69, 0.23, 0.18, 1.0)  # 深红
		CardPatternsScript.CardPattern.ORGANIC: return Color(0.55, 0.36, 0.10, 1.0)    # 琥珀
		CardPatternsScript.CardPattern.SEQUENCE: return Color(0.40, 0.29, 0.62, 1.0)   # 深紫
	return TABLE_TEXT_COLOR                                                          # 单质 / 空桌


func _set_table_text(txt: String, pat: int) -> void:
	if table_label == null or not is_instance_valid(table_label):
		return
	var changed: bool = table_label.text != txt
	table_label.text = txt
	table_label.add_theme_color_override("font_color", _table_type_color(pat))
	if changed:
		_tween_table_label_reveal()


# 淡入而不是瞬间换字：桌面是全场视线焦点，"啪"一下换掉容易被当成误刷
func _tween_table_label_reveal() -> void:
	if table_label == null or not is_instance_valid(table_label):
		return
	var old = table_label.get_meta("reveal_tween", false)
	if old is Tween and old.is_valid():
		old.kill()
	table_label.modulate = Color(1, 1, 1, 0.15)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(table_label, "modulate:a", 1.0, TABLE_REVEAL_MS / 1000.0)
	table_label.set_meta("reveal_tween", tw)


# 桌面小卡入场：0.9 → 1.0 缩放 + 淡入（stagger 40ms）。
# 刻意不动 position —— 小卡位置是布局真值，测试与"桌面小卡槽"断言都按它算。
func _animate_mini_card_in(btn: Control, i: int) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.scale = Vector2(0.9, 0.9)
	btn.modulate = Color(1, 1, 1, 0)
	var old = btn.get_meta("mini_in_tween", false)
	if old is Tween and old.is_valid():
		old.kill()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var delay: float = MINI_CARD_IN_STAGGER * float(i)
	tw.tween_property(btn, "scale", Vector2.ONE, MINI_CARD_IN_MS / 1000.0).set_delay(delay)
	tw.tween_property(btn, "modulate:a", 1.0, MINI_CARD_IN_MS / 1000.0).set_delay(delay)
	btn.set_meta("mini_in_tween", tw)


# ============================================================
# 出牌 / 弃牌 / 抽牌（A3）
# ============================================================
# 为什么都走「幽灵牌」：_refresh_ui() 会把手牌整块重建（旧按钮 remove_child + queue_free），
# 任何「移动原按钮」的写法都会在半路凭空消失。duplicate 出来的副本挂在 ContentLayer 上
#（不随 hand_container 重建销毁），坐标一律用 global_position，跨容器也一致。
func _make_fly_ghost(btn: Control) -> Control:
	if btn == null or not is_instance_valid(btn):
		return null
	var ghost := btn.duplicate() as Control
	if ghost == null:
		return null
	ghost.name = "FlyGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = Z_DRAG
	# 手牌此刻可能正被悬停放大到 1.06，飞行统一从 1.0 起，避免终点缩放算不准
	ghost.scale = Vector2.ONE
	ghost.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
	_layer(0).add_child(ghost)
	ghost.global_position = btn.global_position
	return ghost


# 二次贝塞尔取点（p = 0..1）：_fly_ghost 的抛物弧用它，避免手写两段 position 补间
func _bezier2(a: Vector2, c: Vector2, b: Vector2, p: float) -> Vector2:
	var q: float = 1.0 - p
	return a * (q * q) + c * (2.0 * q * p) + b * (p * p)


func _place_ghost(ghost: Control, to_pos: Vector2) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	ghost.global_position = to_pos


# arc > 0 时走抛物线（出牌）：中点抬高 arc，终点仍是 to_pos，落点精度不变
func _fly_ghost(ghost: Control, to_pos: Vector2, to_scale: float, ms: int, delay: float, arc: float = 0.0) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	var dur: float = ms / 1000.0
	var from_pos: Vector2 = ghost.global_position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if arc > 0.0:
		var ctrl: Vector2 = (from_pos + to_pos) * 0.5 + Vector2(0, -arc)
		var steps = tw.tween_method(
			func(p: float): _place_ghost(ghost, _bezier2(from_pos, ctrl, to_pos, p)),
			0.0, 1.0, dur)
		steps.set_delay(delay)
	else:
		tw.tween_property(ghost, "global_position", to_pos, dur).set_delay(delay)
	tw.tween_property(ghost, "scale", Vector2(to_scale, to_scale), dur).set_delay(delay)
	# 末 40% 才淡出：前段要看清「是哪张牌飞过去了」
	tw.tween_property(ghost, "modulate:a", 0.0, dur * 0.6).set_delay(delay + dur * 0.4)
	tw.chain().tween_callback(ghost.queue_free)
	ghost.set_meta("fly_tween", tw)


# 出牌：抢在 _step_reset / _refresh_ui 之前拍下被选中手牌的位置（此时按钮还在）
func _capture_play_fly_in() -> Array:
	var snaps: Array = []
	if hand_container == null:
		return snaps
	for idx in selected_indices:
		if idx < 0 or idx >= hand_buttons.size():
			continue
		var btn = hand_buttons[idx]
		if not is_instance_valid(btn):
			continue
		var ghost := _make_fly_ghost(btn)
		if ghost == null:
			continue
		btn.visible = false          # 原位立刻空出来（旧按钮马上会被重建释放）
		snaps.append({"card": btn.get_meta("card", null), "ghost": ghost})
	return snaps


# 出牌收尾：桌面小卡已就位 → 幽灵牌飞到对应小卡上并淡出。
# 配对按「卡片对象」而不是下标：化合物的小卡会按化学式重排，下标对不上。
func _replay_play_fly_in(snaps: Array) -> void:
	if snaps.is_empty():
		return
	var used: Array = []
	for i in range(snaps.size()):
		var ghost = snaps[i].get("ghost", null)
		if ghost == null or not is_instance_valid(ghost):
			continue
		var card = snaps[i].get("card", null)
		var target: Rect2 = Rect2()
		for k in range(table_card_buttons.size()):
			if k in used:
				continue
			var mb = table_card_buttons[k]
			if is_instance_valid(mb) and mb.get_meta("card", null) == card:
				target = Rect2(mb.global_position, mb.size)
				used.append(k)
				break
		if target.size == Vector2.ZERO:
			# 桌面没对上（理论上不会）→ 至少朝桌面小卡槽飞过去，别原地消失
			var slot := Rect2(Vector2(20, 186), Vector2(72, 90))
			target = slot
		var to: Vector2 = target.position + (target.size - Vector2(CARD_W, CARD_H)) * 0.5
		_fly_ghost(ghost, to, PLAY_FLY_SCALE, PLAY_FLY_MS, 0.03 * float(i), PLAY_FLY_ARC)


# 弃牌：从原位向上抬起并淡出 —— 「这张牌离开手牌」的唯一视觉出口
func _fly_discarded_card() -> void:
	if hand_container == null or selected_indices.size() != 1:
		return
	var idx: int = selected_indices[0]
	if idx < 0 or idx >= hand_buttons.size():
		return
	var btn = hand_buttons[idx]
	if not is_instance_valid(btn):
		return
	var ghost := _make_fly_ghost(btn)
	if ghost == null:
		return
	btn.visible = false
	_fly_ghost(ghost, ghost.global_position + Vector2(0, -DISCARD_FLY_LIFT), 0.92, DISCARD_FLY_MS, 0.0)


# 抽牌 / 发牌：新出现的卡片对象从手牌区上方 DEAL_IN_DROP 处落下 + 淡入
#（开局 8 张全部算新增 → 自带一次发牌入场）。
# 只动 position / modulate：scale 归悬停 / 选中缩放补间管，两边同时改会互相拉扯。
# 落点用 _layout_hand_cards() 写好的 meta("base_pos")（真实布局结果）；
# 补间结束时强制归位 —— 入场途中若发生重排，base_pos 已是新值，这一句把牌钉回真值。
func _animate_new_hand_cards() -> void:
	var now_cards: Array = []
	var order: int = 0
	for b in hand_buttons:
		if not is_instance_valid(b):
			continue
		var c = b.get_meta("card", null)
		if c == null:
			continue
		now_cards.append(c)
		if c in _hand_seen_cards:
			continue
		var base_pos: Vector2 = b.get_meta("base_pos", b.position)
		var old = b.get_meta("deal_in_tween", false)
		if old is Tween and old.is_valid():
			old.kill()
		b.position = base_pos + Vector2(0, -DEAL_IN_DROP)
		b.modulate = Color(1, 1, 1, 0.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var delay: float = DEAL_IN_STAGGER * float(order)
		tw.tween_property(b, "position", base_pos, DEAL_IN_MS / 1000.0).set_delay(delay)
		# 透明度比位移先走完（0.7 倍时长）：牌落到位时已经实心，不会有「落定才显形」的断层
		tw.tween_property(b, "modulate:a", 1.0, DEAL_IN_MS / 1000.0 * 0.7).set_delay(delay)
		tw.chain().tween_callback(func(): _snap_card_position(b, base_pos))
		b.set_meta("deal_in_tween", tw)
		order += 1
	_hand_seen_cards = now_cards


# 入场收尾：无论补间被谁打断，牌都必须停在布局真值上
func _snap_card_position(btn: Control, to_pos: Vector2) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.position = to_pos


func _build_mini_card_button(card, custom_valence = null) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(72, 90)
	btn.tooltip_text = card.get_full_info()
	# 出牌飞入按「卡片对象」配对小卡（化合物会按化学式重排，下标对不上）
	btn.set_meta("card", card)

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


# -------- 右栏日志（A1 底板 + A4 可折叠标题条） --------
# 挂 GamePage 直接子节点（跟随页面显隐），插在 LogLabel 之前 —— 同级按树顺序绘制，
# 底板必须先画；mouse_filter = IGNORE 保证它不吃手牌 / 按钮的点击。
# 标题条是唯一新增的可点元素（折叠开关），也挂在 GamePage 上、紧跟底板。
func _ensure_log_panel() -> void:
	if _log_panel != null and is_instance_valid(_log_panel):
		return
	if log_label == null or not is_instance_valid(log_label):
		return
	var page := log_label.get_parent()
	if page == null:
		return
	# 记下 LogLabel 在 Main.tscn 里的设计位置：之后所有几何都从它推导，
	# 折叠只改 LogLabel 的 y / 高度，不会把自己的基准挪掉
	if not log_label.has_meta("home"):
		log_label.set_meta("home", log_label.position)
	var panel := Panel.new()
	panel.name = "LogPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_panel_style("log_panel"))
	page.add_child(panel)
	page.move_child(panel, log_label.get_index())
	_log_panel = panel

	var title := _make_right_column_title("LogTitleBar", "游戏日志")
	title.pressed.connect(_on_log_title_pressed)
	page.add_child(title)
	page.move_child(title, panel.get_index() + 1)
	_log_title = title
	_layout_log_panel()


# 点标题条：折叠 / 展开。折叠状态跟着这个 GameUI 实例走（跨回合保留，不写存档）
func _on_log_title_pressed() -> void:
	_log_collapsed = not _log_collapsed
	_layout_log_panel()


# 右栏日志几何的唯一出口：底板 / 标题条 / 正文一起算，「折叠」与「展开」只差正文高度。
# 高度按「行数 × 行高」推（日志最多 MAX_LOG_LINES 行），不再写死 300px 让右栏空一大片。
func _layout_log_panel() -> void:
	if log_label == null or not is_instance_valid(log_label):
		return
	if _log_panel == null or not is_instance_valid(_log_panel):
		return
	if _log_title == null or not is_instance_valid(_log_title):
		return
	var home: Vector2 = log_label.get_meta("home", log_label.position)
	var panel_w: float = LOG_W + LOG_PANEL_PAD
	var body_w: float = panel_w - LOG_TEXT_PAD - LOG_PANEL_PAD
	var body_h: float = LOG_CONTENT_MIN_H
	if not _log_collapsed:
		# 先把宽度定下来，autowrap 的 Label 才能量出真实换行高度（长行折行时不会被裁）
		log_label.size = Vector2(body_w, LOG_CONTENT_MAX_H)
		var rows: int = maxi(log_lines.size(), 1)
		var need: float = maxf(float(rows) * _log_line_h(), log_label.get_minimum_size().y)
		body_h = clampf(need, LOG_CONTENT_MIN_H, LOG_CONTENT_MAX_H)
	var panel_h: float = LOG_PANEL_PAD + LOG_TITLE_H + LOG_PANEL_PAD
	if not _log_collapsed:
		panel_h += LOG_BODY_GAP + body_h
	# 左边缘 = 正文设计位置（原 814 的底板会压到退出按钮右边缘 820）
	_log_panel.position = Vector2(home.x, home.y - LOG_PANEL_PAD)
	_log_panel.size = Vector2(panel_w, panel_h)
	# 标题条是 GamePage 的子节点（紧跟底板以便画在上面），所以位置要加回底板原点
	_log_title.position = Vector2(home.x, home.y)
	_log_title.size = Vector2(panel_w, LOG_TITLE_H)
	_log_title.text = _log_title_text()
	log_label.position = Vector2(home.x + LOG_TEXT_PAD, home.y + LOG_TITLE_H + LOG_BODY_GAP)
	log_label.size = Vector2(body_w, body_h)
	log_label.visible = _log_visible and not _log_collapsed


func _log_title_text() -> String:
	var arrow: String = "▸" if _log_collapsed else "▾"
	var n: int = log_lines.size()
	if n <= 0:
		return "游戏日志 %s" % arrow
	return "游戏日志 · %d 条 %s" % [n, arrow]


# 单行日志的行高：中文字体 ascent+descent 再加 2px 呼吸，宁可多给 1~2px 也不裁字
func _log_line_h() -> float:
	var fs: int = log_label.get_theme_font_size("font_size")
	var font: Font = log_label.get_theme_font("font")
	return maxf(font.get_height(fs) + 2.0, float(fs) + 4.0)


# 日志区显隐的唯一出口：规则提醒占用右栏同一格时，日志 / 底板 / 标题条一起让位
func _set_log_visible(on: bool) -> void:
	_ensure_log_panel()
	_log_visible = on
	if log_label and is_instance_valid(log_label):
		log_label.visible = on and not _log_collapsed
	if _log_panel and is_instance_valid(_log_panel):
		_log_panel.visible = on
	if _log_title and is_instance_valid(_log_title):
		_log_title.visible = on


func _update_log_label() -> void:
	if not log_label or not game_manager: return
	var new_logs = game_manager.flush_logs()
	if new_logs.is_empty(): return
	for msg in new_logs:
		log_lines.push_back(msg)
		while log_lines.size() > MAX_LOG_LINES:
			log_lines.pop_front()
	log_label.text = "\n".join(log_lines)
	_layout_log_panel()


func _update_card_info_label() -> void:
	if not card_info_label or not game_manager: return
	var pi: int = game_manager.get_current_player_index()
	var cp = game_manager.get_current_player()
	if cp == null:
		card_info_label.text = ""
		return
	# 联机（Step 3，D6）：视角与「可用牌型」都只按自己的座位算 ——
	# 用当前行动者的下标去查 get_available_patterns() 就是白送别人手牌情报。
	if net_session != null:
		if net_session.is_watcher():
			card_info_label.text = "观战中：不显示任何玩家的手牌"
			return
		cp = _view_player()
		if cp == null:
			card_info_label.text = ""
			return
		if not _net_can_operate():
			if action_router != null and action_router.awaiting_reply():
				card_info_label.text = "已提交，等待主机裁决…"
			else:
				var actor = game_manager.get_current_player()
				var who: String = actor.player_name if actor != null else "对手"
				card_info_label.text = "等待 %s 行动中… 现在不是你的回合，手牌仅供查看" % who
			return
		pi = int(net_session.my_seat)
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
		if _hint_owner == pi \
				and _hint_hand_size == cp.hand.size() \
				and _hint_order_sig == _hand_order_sig(cp):
			card_info_label.text = _hint_text
			return
		_clear_hint()
	var hint = game_manager.get_available_patterns(pi)
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
# A6-2：面板从「460 宽单行 HBox」改成「贴底 + 自动折行的 HFlowContainer」。
# 老问题（实测）：HBoxContainer 不受父级宽度约束，选项一多就向右无限扩张 ——
#   · Cl + I = 5+4 价 + 返回 = 10 个按钮 → 面板宽 1640，末尾 3 个（含「返回」）落在 x>1152 的屏幕外；
#   · Fe + Cl + O = 9 个按钮 → 1472 宽，「Cl (+7)」「返回」同样点不到；
#   · 触屏档按钮 58 高、面板顶 599 → 下沿 657 > 648 画布，底部出血 9px。
# 现在：面板占满底部整条空白（x 8..1144），按宽度折行，行数向上累加；
#       下沿固定 644，上沿 = 644 - 行数×行高 —— 1 行时与 P11 逐像素一致（顶 599）。
# 几何唯一出口是 _fit_action_panel()：宽度先定，行数自己按 FlowContainer 的换行规则数，
# 不依赖「容器排序后再量」的异步时序，同一帧内就能给出确定矩形（测试可直接断言）。
const ACTION_PANEL_LEFT := 8.0
const ACTION_PANEL_RIGHT := 1144.0          # 左右各留 8px（画布 1152）
const ACTION_PANEL_BOTTOM := 644.0          # 下沿：648 画布留 4px
const ACTION_PANEL_BTN_H := 45              # 桌面行高；触屏走 _touch_btn_h() → 48
const ACTION_PANEL_BTN_W := 160             # _mkb 的默认按钮宽
const ACTION_PANEL_BTN_W_NARROW := 132      # 行数会超过 MAX_ROWS 时收窄（一行 6 → 8 个）
const ACTION_PANEL_MAX_ROWS := 3            # 上限：再高就会盖住 CardInfoLabel
const ACTION_PANEL_REFIT_TRIES := 2         # 最小尺寸缓存没刷新时最多重算几次（保底，不死循环）
const ACTION_PANEL_W := ACTION_PANEL_RIGHT - ACTION_PANEL_LEFT


func _update_action_panel() -> void:
	if not action_panel or not game_manager: return
	for child in action_panel.get_children():
		child.queue_free()
	# 热座交接未认领前不给任何操作按钮：否则可以绕过遮罩直接点「跳过 / 出牌」
	if _hotseat_handoff_pending():
		_fit_action_panel()
		return
	# 联机（Step 3，D1/D6）：非我回合 / 已提交待裁决 / 观战 / 待选牌型
	#   → 只给一句等待提示，一个按钮都不给（客人绝不能替别人「点」出牌）
	if net_session != null:
		var wait_text := _net_wait_text()
		if wait_text != "":
			action_panel.add_child(_mk_wait_label(wait_text))
			_fit_action_panel()
			return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai or game_manager.is_game_over():
		_fit_action_panel()
		return

	if step_mode == 0:
		# 先出后验（P14-C）：选好牌 → 点「直接出牌 ⚡」，引擎按固定优先级自己挑牌型
		# （有机物 → 单质 → 化合物 → 顺序 → 族炸），第一个合法候选才落子。
		# 老的三步流程（出牌(选牌型) → 单质/化合物/顺序/族炸）原样保留，
		# 教程文案（TutorialController / TutorialUI 里的「出牌(选牌型)」）不用改。
		action_panel.add_child(_mkb("直接出牌 ⚡", _on_auto_play, selected_indices.is_empty()))
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
	_fit_action_panel()


# 面板行高：桌面 45，触屏 48（TOUCH_BTN_MIN_H，≈32dp；旧值 58 会让下沿出血 9px）
func _action_btn_h() -> float:
	return float(_touch_btn_h(ACTION_PANEL_BTN_H))


# 面板「贴底 + 向上折行」的唯一几何出口。
# 顺序：宽度先定 → 数行数（必要时收窄）→ 高度 = 行数×行高 + (行数-1)×行距 → 整块贴到 BOTTOM。
# 之所以自己数行而不等容器排序：FlowContainer 的 sort 是 deferred 的，同一帧里读 size 还是旧值；
# 这里按同一套换行规则（累加最小宽 + h_separation，超宽换行）先算出来，测试就能同步断言。
func _fit_action_panel() -> void:
	if action_panel == null or not is_instance_valid(action_panel):
		return
	var want_h := _action_panel_h()
	action_panel.size = Vector2(ACTION_PANEL_W, want_h)
	# 贴底用「实际尺寸」而不是 want_h：Container 的最小高度是缓存值（FlowContainer 的最小高度
	# 取决于当前宽度），刚换掉一整批按钮时本帧还会夹在旧内容的高度上 —— 照样贴住 644，绝不出血。
	action_panel.position = Vector2(ACTION_PANEL_LEFT, ACTION_PANEL_BOTTOM - action_panel.size.y)
	action_panel.queue_sort()
	# 被夹住就等一帧缓存刷新后再算一次（重试有上限，不会死循环）
	if not is_equal_approx(action_panel.size.y, want_h) and _ap_refit_left > 0:
		_ap_refit_left -= 1
		_fit_action_panel.call_deferred()
	else:
		_ap_refit_left = ACTION_PANEL_REFIT_TRIES


# 面板高度：行数 × 行高 + (行数-1) × 行距；行数超上限先收窄按钮再算
func _action_panel_h() -> float:
	var rows := _action_panel_rows()
	if rows > ACTION_PANEL_MAX_ROWS:
		# 极端局面（4 种元素 × 多价）：把按钮收窄，让面板不超过 3 行，
		# 否则上沿会盖住 CardInfoLabel（478~526）甚至手牌。
		# 注意 Button 的最小宽 = max(custom_minimum_size, 文字宽)，短文本（"Cl (+7)"）才收得动。
		for c in action_panel.get_children():
			if c is Button and not c.is_queued_for_deletion():
				c.custom_minimum_size = Vector2(ACTION_PANEL_BTN_W_NARROW, c.custom_minimum_size.y)
		rows = _action_panel_rows()
	var v_sep := float(action_panel.get_theme_constant("v_separation"))
	return _action_btn_h() * float(rows) + v_sep * float(maxi(rows - 1, 0))


# 折行行数：与 FlowContainer::_resort 同一套规则（累加最小宽 + h_separation，放不下就换行）。
# 必须跳过 queue_free() 掉的旧子节点 —— _update_action_panel 先 queue_free 再加新按钮，
# 同一帧里新旧同时在树上，不跳过行数会算成两倍。
func _action_panel_rows() -> int:
	var sep := float(action_panel.get_theme_constant("h_separation"))
	var rows := 1
	var row_w := 0.0
	for c in action_panel.get_children():
		if not (c is Control) or c.is_queued_for_deletion() or not c.visible:
			continue
		var cw: float = (c as Control).get_combined_minimum_size().x
		if row_w > 0.0 and row_w + sep + cw > ACTION_PANEL_W:
			rows += 1
			row_w = cw
		else:
			row_w = cw if row_w <= 0.0 else row_w + sep + cw
	return rows


# 1 行面板的设计矩形：教程第零关「出牌区」高亮框用它（触屏 48 高 → 顶边上移 3px）
func _action_panel_hl_rect() -> Rect2:
	var h := _action_btn_h()
	return Rect2(Vector2(ACTION_PANEL_LEFT, ACTION_PANEL_BOTTOM - h), Vector2(ACTION_PANEL_W, h))


# 教程第零关「其他细节（右面板）」的高亮矩形：右栏几何由 _layout_log_panel() / _layout_rule_tips()
# 决定（折叠、日志条数、规则提醒是否占用都会变），所以读节点实况再外扩 4px。
# 老实现写死 (750,10) 400×350 —— 框住的是状态栏下方一整片空白，日志面板反而只有下半截在框里。
func _right_panel_hl_rect() -> Rect2:
	var node: Control = null
	if level0_rule_tip_bg != null and is_instance_valid(level0_rule_tip_bg) and level0_rule_tip_bg.visible:
		node = level0_rule_tip_bg
	elif _log_panel != null and is_instance_valid(_log_panel) and _log_panel.visible:
		node = _log_panel
	if node == null or node.size.x <= 0.0:
		# 兜底（正常时序到不了：_ensure_log_panel() 在 _ready 里就建好了）：设计位置 + 折叠态高度
		var home: Vector2 = Vector2(824, 300)
		if log_label != null and is_instance_valid(log_label):
			home = log_label.get_meta("home", home)
		return Rect2(Vector2(home.x, home.y - LOG_PANEL_PAD),
				Vector2(LOG_W + LOG_PANEL_PAD, LOG_PANEL_PAD * 2.0 + LOG_TITLE_H))
	var pad: float = float(RIGHT_PANEL_HL_PAD)
	return Rect2(node.position - Vector2(pad, pad), node.size + Vector2(pad, pad) * 2.0)


func _mkb(text: String, cb: Callable, dis: bool) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(ACTION_PANEL_BTN_W, _action_btn_h())   # 触屏 48 高 ≈ 32dp（旧 58 会出血）
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


# 起拖阈值：越过它就开始跟手（触屏 10px ≈7dp，桌面 6px）
# 触屏「起拖」与「确认重排」刻意分成两档：10px 起拖是为了手指一动牌就跟（消除 300ms 死区），
# 24px（_drag_threshold）才是松手时判定「真的换位」的门槛 —— 中间那 10~24px 松手会回退成点选。
func _drag_arm_threshold() -> float:
	return TOUCH_DRAG_ARM_MOVE if _touch_ui else DRAG_THRESHOLD


# 确认阈值：鼠标 6px 就够，手指需要 24px 才算有意重排（<24px 视为点选，见 _finish_drag）
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
		# 记住原始几何 / 字号：P14-D 的开关可以随时关掉触控档，必须逐颗还原。
		# 只记第一次（开→关→开 反复切换时，原点始终是桌面档的值）。
		if not b.has_meta("touch_orig"):
			b.set_meta("touch_orig", {
				"size": b.size,
				"cms": b.custom_minimum_size,
				"pos": b.position,
				"fs": b.get_theme_font_size("font_size"),
			})
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


# 还原：把 _apply_touch_sizing 改过的按钮逐颗恢复（size / 最小高 / 坐标 / 字号）。
# 为什么要还原而不是重建页面：这些按钮是代码生成的，位置写在各调用点，
# 重建一遍等于重跑 _setup_pages（会重连信号、重播入场动画），关个开关不该这么重。
func _revert_touch_sizing(root: Node) -> void:
	if root == null:
		return
	for b in _collect_buttons(root):
		if b.has_meta("touch_sized"):
			b.remove_meta("touch_sized")
		if not b.has_meta("touch_orig"):
			continue
		var orig: Dictionary = b.get_meta("touch_orig")
		b.remove_meta("touch_orig")
		# 顺序要紧：最小尺寸 → 字号 → size。
		# 反过来会被「当前」最小尺寸反复夹住（实测：先写 size 会停在 48，再停在 42 ——
		# 都是旧字号撑出来的最小高度，看着像没还原）。
		b.custom_minimum_size = orig["cms"]
		var fs: int = int(orig["fs"])
		if fs > 0:
			b.add_theme_font_size_override("font_size", fs)
		b.size = orig["size"]
		b.position = orig["pos"]
		b.pivot_offset = b.size * 0.5


# ============================================================
# 九之二、触屏档运行时开关（P14-D）
# ============================================================
# 为什么需要界面开关：--touch-ui 只在启动时生效，真机上玩家想「把按钮调大」只能改系统设置；
# 桌面上也总得开终端加参数。开始页「触屏界面」开关 = set_touch_ui()，
# 与命令行 / 平台判定共用同一个 _touch_ui 字段，几何取值函数自然跟着变。
func is_touch_ui() -> bool:
	return _touch_ui


func set_touch_ui(on: bool) -> void:
	if on == _touch_ui:
		_sync_touch_toggle()
		return
	_touch_ui = on
	_touch_ui_manual = true
	print("[UI] 触屏档案 = %s（开始页开关）" % str(on))
	_apply_touch_profile_everywhere()
	_sync_touch_toggle()


# 把当前档位刷到所有已构建的页面 + 游戏页（可逆：关掉时逐颗还原，不重建页面）
func _apply_touch_profile_everywhere() -> void:
	for p in [start_page, end_page, get_node_or_null("TutorialPage"), help_page, _supp_rules_page]:
		if p == null:
			continue
		if _touch_ui:
			_apply_touch_sizing(p)
		else:
			_revert_touch_sizing(p)
	if game_page == null:
		return
	# 游戏页：工具行 / 按序按钮吃 _touch_btn_*() 几何，手牌与操作面板吃 _touch_fs()，
	# 都在下一次重建时取值 —— 这里主动触发一次重建。
	_style_game_tool_buttons()
	_reposition_reorder_button()
	if game_manager != null and not game_manager.is_game_over():
		_refresh_ui()


func _reposition_reorder_button() -> void:
	if not is_instance_valid(_reorder_btn):
		return
	var h: float = _tool_btn_h()
	_reorder_btn.custom_minimum_size = Vector2(REORDER_BTN_W, h)
	_reorder_btn.size = Vector2(REORDER_BTN_W, h)
	_reorder_btn.position = Vector2(_reorder_btn_left(), _tool_btn_top())
	_reorder_btn.add_theme_font_size_override("font_size", _touch_fs(14, 4))


# 开始页开关的文字 / 按下态跟随 _touch_ui（命令行强制开启时也显示「开」）
func _sync_touch_toggle() -> void:
	var tg = _start_child("TouchUIToggle")
	if tg == null:
		return
	if tg.button_pressed != _touch_ui:
		# 不能用 button_pressed = _touch_ui：那会补发 toggled → 触发「已开启」提示 + 重复 set
		tg.set_pressed_no_signal(_touch_ui)
	tg.text = "触屏界面 · 开" if _touch_ui else "触屏界面 · 关"


func _on_touch_ui_toggled(pressed: bool) -> void:
	set_touch_ui(pressed)
	_start_flash_rule_hint("触屏界面已开启（按钮更高、字号 +2）" if pressed else "触屏界面已关闭")


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
	# 联机（Step 3）：只有轮到我、且没有待裁决 / 待选牌型时才给提示 ——
	# HintAdvisor 读的是「当前行动者」的手牌，别人回合点提示等于偷看别人的牌
	if net_session != null and not _net_can_operate():
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
	if net_session != null:
		# 联机（Step 3，D6）：只读与否只看「是不是我这一手」，与 actor 无关：
		#   别人回合 / 已提交待裁决 / 待我选牌型 → 只读（看得到自己牌，点不动）
		_hand_read_only = view == null or not _net_can_operate()
	else:
		_hand_read_only = view != null and actor != null and view != actor
	# 选中快照必须抢在 hand_buttons.clear() 之前：旧按钮上的 card meta 是
	# 「玩家看见并点中的那张牌」的唯一可靠来源（数据层顺序可能已被拖拽 / 抽牌排序改过）
	var keep_selected: Array = _selected_cards(view)
	# 旧按钮即将销毁，悬停状态机必须一并清零，否则会指向失效索引
	_hover_idx = -1
	_hover_pending_idx = -1
	# 先 remove_child 再 queue_free：避免旧牌残留在容器中干扰重叠布局
	# 发牌入场的补间挂在旧按钮上，重建前先杀掉 —— 否则补间会去碰已释放的节点（脚本报错）
	for child in hand_container.get_children():
		var old_deal = child.get_meta("deal_in_tween", false)
		if old_deal is Tween and old_deal.is_valid():
			old_deal.kill()
		hand_container.remove_child(child)
		child.queue_free()
	hand_buttons.clear()
	ai_triggered = false

	# AI 调度与手牌渲染解耦：即使显示的是玩家自己的牌，也要继续推动 AI 行动
	# 联机（Step 3，D8）：AI 只能由主机 _update_net() 代打（走 host_step_ai → 广播）。
	#   客人若也跑这个计时器，就是本地私自 play_cards → 立刻与主机分叉。
	var ai_acting: bool = actor != null and actor.is_ai and not game_manager.is_game_over()
	if ai_acting and not ai_triggered and net_session == null:
		ai_triggered = true
		var timer = get_tree().create_timer(1.5)
		timer.timeout.connect(_ai_auto_play)

	if view == null:
		# 热座的 AI 回合：谁的牌都不能显示（同屏多人会互相看到手牌）
		if actor != null:
			var wl = Label.new()
			wl.text = "等待 %s 行动中..." % actor.player_name
			if net_session != null and net_session.is_watcher():
				wl.text = "观战中：不显示任何玩家的手牌"
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
	# 抽牌 / 发牌入场（A3）：只对新出现的卡片对象做一次淡入
	_animate_new_hand_cards()
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
# 联机改造（P11-C1-c Step 3，D6）：联机时视角恒为「自己的座位」，
# 与「当前行动者」无关 —— 客人永远只看到自己的牌，轮到别人时手牌只读。
func _hand_view_player(actor = null):
	if game_manager == null:
		return null
	if net_session != null:
		return _view_player()
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
# 联机（Step 3，D7）恒为 false：每个玩家盯自己那块屏，同屏交接遮罩只会把对局卡死。
func _is_hotseat() -> bool:
	if net_session != null:
		return false
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
		# 缩放同理：重排是「瞬时整排落位」，残留的缩放补间会把牌撑在 1.06 上
		_kill_scale_tween(btn)
		btn.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
		# 悬停中的牌保持放大档（重建后 _hover_idx 不变，状态机不会重新触发）
		var sc: float = HAND_HOVER_SCALE if i == _hover_idx else (HAND_SELECT_SCALE if i in selected_indices else 1.0)
		btn.scale = Vector2(sc, sc)
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
	var chip = btn.get_node_or_null("CardValenceChip")
	var vl = chip.get_node_or_null("CardValence") if chip else null
	if chip and vl:
		# 行几何交给 chip 的 meta：紧凑档左对齐（露出左条要读得到），常规档居中。
		# 文字自身永远在粉底内居中 —— 粉底就是它的父节点，不可能再错位。
		var row_w: float = 44.0 if compact else 85.0
		chip.set_meta("row_x", 6.0 if compact else 5.0)
		chip.set_meta("row_w", row_w)
		chip.set_meta("row_align", HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 行宽先扣掉两侧 padding，保证 fit 出来的文字两侧恒有 CHIP_PAD 的粉底余量
		var card = btn.get_meta("card") if btn.has_meta("card") else null
		_fit_card_valence(vl, card, row_w - CARD_VAL_CHIP_PAD * 2.0, _touch_fs(13, 2))


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
	# 联机（Step 3）：只有「轮到我、且没有待裁决 / 待选牌型」才允许拖
	if net_session != null and not _net_can_operate():
		return false
	# 热座交接未认领：手牌还盖着，重排按钮 / 拖拽都该消失
	if _hotseat_handoff_pending():
		return false
	# 教程关：只有第零关「UI 标注 / 流程介绍」阶段禁用（高亮框按固定坐标绘制，拖牌会让提示错位）；
	# 第零关练习阶段（phase 3）与第一 / 二关都允许重排 —— 实测反馈「教程里手牌不能拖」
	# 注意 tutorial_level==0 也是「自由模式」的默认值，必须看 tutorial_level0_phase 才能区分
	if game_manager.tutorial_level == 0 and game_manager.tutorial_level0_phase >= 1 \
			and game_manager.tutorial_level0_phase < 3:
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
			_drag_max_move = 0.0
			_drag_suppress_click = false
		return
	if _drag_press_idx >= hand_buttons.size():
		_drag_press_idx = -1
		return
	# 未达起拖位移 = 普通点击，交给 Button 自己的 pressed
	var moved: float = get_global_mouse_position().distance_to(_drag_press_pos)
	_drag_max_move = maxf(_drag_max_move, moved)
	if moved >= _drag_arm_threshold():
		# 触屏档（C）：10px 就起拖（手指一动牌就跟），不再等 300ms 长按 ——
		# 旧实现「长按 300ms + 24px」在真机上是「按住后牌不动、松手还点不中」，
		# 现在把判定挪到松手时：总位移 <24px 一律按点选处理（见 _finish_drag）。
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
	# 触屏档：10px 就起拖（远早于 24px 的确认阈值），此刻可能只是「想点选但手抖」——
	# 所以软启动：源牌只淡到 0.55、幽灵牌提到 0.9；若最终回退成点选，视觉上不会闪一下深灰。
	if _touch_ui:
		btn.modulate = Color(1, 1, 1, TOUCH_DRAG_SOURCE_ALPHA)
		_drag_ghost = _make_drag_ghost(btn, TOUCH_DRAG_GHOST_ALPHA)
	else:
		btn.modulate = Color(1, 1, 1, DRAG_SOURCE_ALPHA)
		_drag_ghost = _make_drag_ghost(btn)
	_drag_line = _make_drag_line()
	_update_drag_follow()


# 幽灵牌：复制被拖的牌（复刻牌面），只要不吃鼠标就不会干扰判定
func _make_drag_ghost(src: Button, alpha: float = DRAG_GHOST_ALPHA) -> Control:
	var ghost := src.duplicate() as Control
	if ghost == null:
		return null
	ghost.name = "DragGhost"
	ghost.z_index = Z_DRAG
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.modulate = Color(1, 1, 1, alpha)
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
	# 累计最大位移：跟手位置可能来回晃，但「松手时判点选」只看这次按下走过多远
	_drag_max_move = maxf(_drag_max_move, get_global_mouse_position().distance_to(_drag_press_pos))
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
	# 触屏档：起拖门槛只有 10px（为了跟手），松手时总位移仍不到 24px → 判为「点选」。
	# 这样手指小幅抖动既能看到牌跟手，也不会丢掉那次点击（历史 bug：点击被吞 = 点了没反应）。
	# 这里必须走 _apply_card_selection：pressed 已被 _drag_suppress_click 吞掉，不会重复选中。
	if _touch_ui and from >= 0 and _drag_max_move < _drag_threshold():
		_reset_drag_visuals()
		_drag_active = false
		_drag_from = -1
		_drag_slot = -1
		_drag_press_idx = -1
		_apply_card_selection(from)
		call_deferred("_clear_drag_suppress")
		return
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
func _process(delta: float) -> void:
	# 联机（Step 3，D8）：先 poll 会话（收包 + 超时），主机再按节流推进 AI 座位。
	# 单机时 net_session == null，这一行直接返回，等于不存在。
	_update_net(delta)
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
		# 缩放同拍：1.06 让"正在看的那张"从整排里跳出来（pivot 居中，命中判定不受影响）
		_tween_card_scale(btn, HAND_HOVER_SCALE)
		_show_card_detail(btn)
	else:
		var idx: int = btn.get_meta("hand_idx", -1)
		btn.z_index = Z_HAND_SELECTED if idx in selected_indices else 0
		# 落回时把「选中常驻上浮」一起算进去：否则触屏上刚选中的牌被悬停一次、
		# 松手后又落回原位，选中的视觉提示就消失了
		var rest_lift: float = _selected_lift() if idx in selected_indices else 0.0
		_tween_card_y(btn, base.y - rest_lift)
		_tween_card_scale(btn, HAND_SELECT_SCALE if idx in selected_indices else 1.0)
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


# -------- 手牌缩放补间（A2）：悬停 1.06 / 选中 1.04 / 常态 1.0 --------
# 为什么放在手牌上而不是给卡牌换更大的贴图：命中判定用的是静态 _card_hover_rect()，
# scale 不参与几何计算，所以放大既不会自激抖动，也不会把点数判给邻居。
# meta 键与 hover_tween 分开：重排只 kill 位移补间时，缩放能自己收敛到目标值。
func _tween_card_scale(btn: Button, target: float) -> void:
	if not is_instance_valid(btn): return
	_kill_scale_tween(btn)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(target, target), HAND_SCALE_MS / 1000.0)
	btn.set_meta("scale_tween", tw)


func _kill_scale_tween(btn: Button) -> void:
	if not is_instance_valid(btn): return
	var tw = btn.get_meta("scale_tween", false)
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
	var vs: String = _format_valence_full(card.common_valence)
	if vs == "":
		vs = "N/A"
	return "%s %s  |  原子序数 %d  |  族 %s  |  %s  |  化合价 %s  |  相对原子质量 %.2f" % [
		card.symbol, card.name_cn, card.atomic_number, card.group,
		card.element_type, vs, card.atomic_weight]


# ============================================================
# 化合价文本：格式化 + 按可用宽度自适应
# ============================================================
# 为什么需要这一层：card.common_valence 最多 5 个价（Cl = [-1,1,3,5,7]），
#   "-1 +1 +3 +5 +7" 在 13px 下实测 85px —— 正好等于整张卡宽（85），触屏 15px 达 98px，
#   Label 默认不裁剪，于是文字直接画到卡片右边界之外（多价元素卡面溢出 bug）。
# 帮助页图鉴（迷你卡 96 宽）早就有「只留两个价 + …」的裁剪，卡面一直没做；
# 本次把两处收敛到同一套：全价 → 去空格 → 降字号 → 两端价 + …。
func _valence_token(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)


func _format_valence_full(vals: Array) -> String:
	var parts: Array = []
	for v in vals:
		parts.append(_valence_token(v))
	return " ".join(parts)


func _format_valence_tight(vals: Array) -> String:
	var s := ""
	for v in vals:
		s += _valence_token(v)
	return s


# 放不下全价时只留「最低价 + 最高价」，**不再加省略号**（P14-A）：
#   "-1 +7…" 里的 "…" 既占宽度、又像渲染残缺（真机截图反馈「不美观」），
#   而 "首价 末价" 本身就是「区间」语义，读起来是「-1 到 +7」，不省略也不误导。
# 中间的 +1/+3/+5 不丢：悬停信息栏 _card_summary_text 仍显示全价，化合价选择面板是逐价按钮，
#   帮助页图鉴的迷你卡下方也有一行完整说明。
# 两个价以内原样返回（不动数据顺序，H 仍是 "+1 -1"，与历史显示一致）；
# 3 个以上才排序取首尾（数据顺序不保证升序，H 的数据就是 [1, -1]）。
func _format_valence_pair(vals: Array) -> String:
	if vals.is_empty():
		return "—"
	if vals.size() <= 2:
		return _format_valence_full(vals)
	var sorted_vals: Array = _sorted_valences(vals)
	return "%s %s" % [_valence_token(sorted_vals[0]), _valence_token(sorted_vals[-1])]


func _sorted_valences(vals: Array) -> Array:
	var out: Array = vals.duplicate()
	out.sort()
	return out


# 分级收缩（P14-A 重写）：全价 → 去空格 → 字距降 1 档 → 首末价（回原字号）
# 与旧实现的区别：
#   · 旧实现最后一档是「首末价 + … 且字号压到 10px」，紧凑档 3 价元素（C/N/P/S/Br）
#     显示成 10px 的 "+4+2-4"，糊在一起；5 价元素（Cl/I）变成 "-1 +7…" 截断。
#   · 现在改为：字号最多降 1 档（13 → 12，触屏 15 → 14），再放不下就退「首末价」并**回升原字号**，
#     所以同一排手牌里价态字号只有 12/13（触屏 14/15）两档，且永远不出现省略号。
# 末档落定后 clip_text=true 兜底：任何数据 / 字体 / 极端窄行下都不会画出卡片右边界。
# 实际文本宽写进 meta("fit_w")、档位写进 meta("val_mode")（full/tight/pair/clip），
# 圆底价态 chip（A1）与测试直接复用，不再各量一遍。
func _fit_card_valence(lbl: Label, card, max_w: float, base_fs: int) -> void:
	if lbl == null:
		return
	lbl.clip_text = true
	var vals: Array = card.common_valence if card != null else []
	if vals.is_empty():
		lbl.text = "N/A"
		lbl.add_theme_font_size_override("font_size", base_fs)
		lbl.set_meta("fit_w", 0.0)
		lbl.set_meta("val_mode", "none")
		_sync_valence_chip(lbl)
		return
	var font: Font = lbl.get_theme_font("font")
	# 触屏档把收缩下限一起抬 1 档（11 → 12）：手机上 11px 已经读不清，
	# 宽度不够时宁可退到「首末价」，也不要缩成一团糊字。
	var min_fs: int = mini(_touch_fs(CARD_VAL_MIN_FS, 1), base_fs)
	var txt_full: String = _format_valence_full(vals)
	var txt_tight: String = _format_valence_tight(vals)
	var txt_pair: String = _format_valence_pair(vals)
	var best_text := ""
	var best_fs := 0
	var best_mode := ""
	if _valence_fits(font, txt_full, base_fs, max_w):
		# 最常见的情况：单 / 双价元素原样显示（+2、+1 -1、+2 +3）
		best_text = txt_full
		best_fs = base_fs
		best_mode = "full"
	elif _valence_fits(font, txt_tight, base_fs, max_w):
		# 3~5 个价、常规档：去掉空格就够（Cl 13px 全价 85 → 72）
		best_text = txt_tight
		best_fs = base_fs
		best_mode = "tight"
	else:
		# 紧凑档 / 触屏放大档：字距（tight）只降 1 档；再放不下就退「首末价」并**回升原字号**
		var fs: int = base_fs - 1
		if fs >= min_fs and _valence_fits(font, txt_tight, fs, max_w):
			best_text = txt_tight
			best_fs = fs
			best_mode = "tight"
		if best_text == "":
			# 信息少了，字号就不该再小：首末价从原字号开始试，必要时才降到 min_fs
			fs = base_fs
			while fs >= min_fs:
				if _valence_fits(font, txt_pair, fs, max_w):
					best_text = txt_pair
					best_fs = fs
					best_mode = "pair"
					break
				fs -= 1
		if best_text == "":
			# 极端窄行（44px 行宽 + 触屏字号）：连「首末价」都放不下 → 只留首价并 clip
			var sorted_vals: Array = _sorted_valences(vals)
			best_text = _valence_token(sorted_vals[0])
			best_fs = min_fs
			best_mode = "clip"
	lbl.text = best_text
	lbl.add_theme_font_size_override("font_size", best_fs)
	lbl.set_meta("fit_w", minf(_valence_width(font, best_text, best_fs), max_w))
	lbl.set_meta("val_mode", best_mode)
	_sync_valence_chip(lbl)


# 卡面价态圆底：chip 是 label 的父节点，因此只需定 chip 的矩形 ——
#   · 宽 = 实测文字宽 + 左右 padding（不超过整行宽，文字两侧恒留 CHIP_PAD）
#   · 横坐标 = 行起点（紧凑档左对齐）或 行内居中（常规档）
# 旧实现把 chip 当 label 的兄弟节点、按「居中于 label」算坐标，而紧凑牌面把 label
# 改成左对齐 → 粉底整体右偏 9~13px（截图里 +2 / 0 的粉块跑到文字右边）。
func _sync_valence_chip(lbl: Label) -> void:
	var chip := lbl.get_parent() as Control
	if chip == null or chip.name != "CardValenceChip":
		return
	var fit_w: float = float(lbl.get_meta("fit_w", 0.0))
	var row_x: float = float(chip.get_meta("row_x", 5.0))
	var row_w: float = float(chip.get_meta("row_w", 85.0))
	var align: int = int(chip.get_meta("row_align", HORIZONTAL_ALIGNMENT_CENTER))
	# 行宽已扣掉两侧 padding（见调用点），这里再加回来就是粉底宽
	var w: float = minf(fit_w + CARD_VAL_CHIP_PAD * 2.0, row_w)
	var x: float = row_x if align == HORIZONTAL_ALIGNMENT_LEFT else row_x + (row_w - w) * 0.5
	chip.position = Vector2(x, CARD_VAL_Y + 1.0)
	chip.size = Vector2(w, CARD_VAL_CHIP_H)
	chip.visible = fit_w > 0.0


func _valence_fits(font: Font, txt: String, fs: int, max_w: float) -> bool:
	return _valence_width(font, txt, fs) <= max_w


func _valence_width(font: Font, txt: String, fs: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


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

	# 价态圆底（A1）：Panel 作为 Label 的父节点 —— 粉底与文字物理绑定，
	# 不会再出现「粉底按居中算、文字按左对齐排」的错位（截图回归：紧凑档粉底整体右偏）。
	# 行几何（起点 / 宽度 / 对齐）存在 chip 的 meta 上，宽度由 _fit_card_valence()
	# 实测的文字宽决定（见 _sync_valence_chip）。
	var l_val_chip := Panel.new()
	l_val_chip.name = "CardValenceChip"
	l_val_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_val_chip.set_meta("row_x", 5.0)
	l_val_chip.set_meta("row_w", 85.0)
	l_val_chip.set_meta("row_align", HORIZONTAL_ALIGNMENT_CENTER)
	l_val_chip.add_theme_stylebox_override("panel", _make_panel_style("valence_chip"))
	btn.add_child(l_val_chip)

	var l_val = Label.new()
	l_val.name = "CardValence"
	l_val.add_theme_font_size_override("font_size", _touch_fs(13, 2))
	l_val.add_theme_color_override("font_color", Color(0.55, 0.2, 0.2, 1))
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_val_chip.add_child(l_val)
	l_val.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 全价优先；放不下时自动去空格 / 降字号 / 只留两端价（不会画出卡边）
	_fit_card_valence(l_val, card, 85.0 - CARD_VAL_CHIP_PAD * 2.0, _touch_fs(13, 2))

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

	# ---- 混合价态入口（v4）----
	# Fe₃O₄ 这类「同一元素每张牌取不同价」的组合，下面「每种元素一个价」的按钮
	# 永远配不平（3 张 Fe 同价时总电荷必是 3 的倍数，压不过 4 张 O 的 -8）。
	# 只在「统一价态无解 + 混合价态有解」时出现，平时不打扰玩家。
	var mixed_cv := _mixed_valence_for_selection()
	if not mixed_cv.is_empty():
		action_panel.add_child(_mkb("混合价态自动配平 ▶", _on_confirm_mixed_valence.bind(mixed_cv), false))
		var mixed_lbl = Label.new()
		mixed_lbl.text = _mixed_valence_text(mixed_cv)
		action_panel.add_child(mixed_lbl)

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

	# ---- 一键配平（P14-B）----
	# 玩家不用再逐个猜价：求解器给出可行解（且引擎已确认 ratio_ok）就直接打出去。
	# 只在「还没选完」或「选完了但 Σ ≠ 0」时出现 —— 已经配平的组合不再多一颗按钮打扰。
	var sel_sum: int = _selection_charge_sum()
	var uniform_cv := _uniform_valence_for_selection()
	if not uniform_cv.is_empty() and (not all_assigned or sel_sum != 0):
		action_panel.add_child(_mkb("自动配平 ▶", _on_confirm_auto_valence.bind(uniform_cv), false))

	if not all_assigned:
		action_panel.add_child(_mkb("返回", _on_back, false))
	else:
		var info = ""
		for sel in compound_selections:
			info += "%s%+d " % [sel.symbol, sel.valence]
		var lbl = Label.new()
		lbl.text = info
		action_panel.add_child(lbl)
		# 总电荷 Σ（P14-B）：按「张数」累加，玩家唯一能自查的量。
		# 真机截图里 H,H,C,N 被拒就是因为 2×(-1)+4+(-3) = -1 —— 以前界面根本不显示这个数。
		var sum_lbl = Label.new()
		sum_lbl.name = "ValenceSumLabel"
		# 0 不写成 "+0"：配平时直接给一个正向反馈，比 "Σ = +0（需 0）" 好读
		sum_lbl.text = "Σ = 0（已配平 ✓）" if sel_sum == 0 else "Σ = %+d（需 0）" % sel_sum
		sum_lbl.tooltip_text = "总电荷 = Σ(每种元素的张数 × 所选化合价)，等于 0 才能配平"
		sum_lbl.add_theme_font_size_override("font_size", _touch_fs(14, 2))
		sum_lbl.add_theme_color_override("font_color",
			Color(0.13, 0.45, 0.18, 1.0) if sel_sum == 0 else Color(0.76, 0.16, 0.13, 1.0))
		action_panel.add_child(sum_lbl)
		action_panel.add_child(_mkb("确认打出", _on_confirm_compound, false))
		action_panel.add_child(_mkb("重选化合价", _on_reset_valence, false))
		action_panel.add_child(_mkb("返回", _on_back, false))


# 当前选中的卡牌：复用 _selected_cards(cp)（P7 已有实现，优先取按钮 meta，
# 拖拽重排后索引对不上也不会取错牌）
func _sel_cards() -> Array:
	if game_manager == null:
		return []
	# 联机（Step 3，D6）：选中的永远是「自己手牌」里的牌 —— 用 get_current_player()
	# 会在别人回合读到别人的手牌（索引来自我这边的手牌按钮，取出来就是另一张牌）
	return _selected_cards(_view_player())


# 面板所选化合价的「总电荷 Σ」：按张数累加（2 张 H 就是 2 份价），
# 与 _on_confirm_compound() 的判定口径一致 —— 界面显示与引擎判定不再各算一套。
func _selection_charge_sum() -> int:
	var total: int = 0
	for card in _sel_cards():
		for sel in compound_selections:
			if sel.symbol == card.symbol:
				total += int(sel.valence)
				break
	return total


# 统一价态可行解（每元素一个价）。有解且引擎确认比例 OK → 才给「自动配平 ▶」按钮。
# 与 _mixed_valence_for_selection() 互斥：统一解优先，混合解只在统一无解时出现。
func _uniform_valence_for_selection() -> Dictionary:
	var cards := _sel_cards()
	if cards.size() < 2:
		return {}
	var cv: Dictionary = CompoundSolverScript.get_uniform_valence_pairs(cards)
	if cv.is_empty():
		return {}
	var fi = CompoundSolverScript.get_compound_formula(cards, cv)
	if fi.is_empty() or not bool(fi.get("ratio_ok", false)):
		return {}
	return cv


# 当前选中的牌组：统一价态无解、混合价态有解 → 返回混合价字典；否则 {}
# （返回的字典直接喂给 play_cards，形如 {"Fe": [3, 3, 2], "O": -2}）
func _mixed_valence_for_selection() -> Dictionary:
	var cards := _sel_cards()
	if cards.size() < 2:
		return {}
	# 统一解已经能打 → 不提供混合入口（保持「主流解优先」）
	if not CompoundSolverScript.get_uniform_valence_pairs(cards).is_empty():
		return {}
	var mixed: Dictionary = CompoundSolverScript.get_mixed_valence_pairs(cards)
	if mixed.is_empty():
		return {}
	var has_array := false
	for sym in mixed:
		if mixed[sym] is Array:
			has_array = true
	if not has_array:
		return {}
	# 真正会用这个字典出牌 → 先确认它确实配平，避免玩家点了按钮又收到「非法出牌」
	var fi = CompoundSolverScript.get_compound_formula(cards, mixed)
	if fi.is_empty() or not bool(fi.get("ratio_ok", false)):
		return {}
	return mixed


# 混合价态的可读文本：{"Fe": [3,3,2], "O": -2} → "混合价态：Fe +3/+3/+2，O -2"
# 混合（数组）的元素排在前面 —— 玩家最需要核对的就是它。
func _mixed_valence_text(cv: Dictionary) -> String:
	var parts: Array = []
	for sym in cv:
		if not (cv[sym] is Array):
			continue
		parts.append(_valence_text_of(sym, cv[sym]))
	for sym in cv:
		if cv[sym] is Array:
			continue
		parts.append(_valence_text_of(sym, cv[sym]))
	return "混合价态：" + "，".join(parts)


func _valence_text_of(sym: String, v) -> String:
	if v is Array:
		var seg: Array = []
		for x in v:
			seg.append("%+d" % int(x))
		return "%s %s" % [sym, "/".join(seg)]
	return "%s %+d" % [sym, int(v)]




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
	_apply_card_selection(index)


# 选中 / 取消选中（Button 点击与触屏「起拖后回退成点选」共用同一条路径）
func _apply_card_selection(index: int) -> void:
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

# 「直接出牌 ⚡」= 先出后验（P14-C）：玩家只负责选牌，牌型交给引擎按固定优先级挑。
# 与旧的「出牌(选牌型)」并存 —— 老玩家 / 教程仍走三步，新玩家一键出。
# 失败时不做界面预判，直接把引擎写的 last_reject_reason 拼进提示（P14-B 已修好这条链路）。
func _on_auto_play() -> void:
	if game_manager == null:
		return
	var cp = _view_player()
	if cp == null or cp.is_ai:
		return
	if net_session != null and not _net_can_operate():
		return
	var cards := _sel_cards()
	if cards.is_empty():
		_show_info("请先选择要打出的牌")
		return
	_clear_hint()
	var result: int = _router().auto_play(cards)
	_dispatch_result(result)

func _on_step_next() -> void:
	_clear_hint()
	step_mode = 1
	_update_action_panel()
	_update_card_info_label()

func _on_element() -> void:
	var cards := _sel_cards()
	if CardPatternsScript.detect_pattern(cards) != CardPatternsScript.CardPattern.ELEMENT:
		_show_info("不是有效单质！")
		_on_back()
		return
	var result = _router().play(cards, {}, CardPatternsScript.CardPattern.ELEMENT)
	_dispatch_result(result)

func _on_sequence() -> void:
	var cards := _sel_cards()
	# 玩家选择"作为顺序"：顺序优先于族炸检测（如 Fe+Co+Ni 既是族炸又是顺序）
	if CardPatternsScript.detect_pattern(cards, false, true) != CardPatternsScript.CardPattern.SEQUENCE:
		_show_info("不是有效顺序！需≥3张连续原子序数的牌。")
		_on_back()
		return
	var result = _router().play(cards, {}, CardPatternsScript.CardPattern.SEQUENCE)
	_dispatch_result(result)

func _on_clan_bomb() -> void:
	var cards := _sel_cards()
	if CardPatternsScript.detect_pattern(cards) != CardPatternsScript.CardPattern.CLAN_BOMB:
		_show_info("不是有效族炸！")
		_on_back()
		return
	var result = _router().play(cards, {}, CardPatternsScript.CardPattern.CLAN_BOMB)
	_dispatch_result(result)

func _on_choose_compound() -> void:
	var cp = _view_player()
	var cards: Array = _sel_cards()
	var symbols: Array = []
	for card in cards:
		var s = card.symbol
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
	if CardPatternsScript.detect_pattern(cards, true) == CardPatternsScript.CardPattern.ORGANIC:
		var custom_valences = {"_organic": true}
		var result = _router().play(cards, custom_valences, CardPatternsScript.CardPattern.ORGANIC)
		# 日志只在本端真落子时写（联机要等主机裁决，写早了就是假消息）
		if net_session == null:
			if result == 0:
				log_lines.push_back("🎉 %s 打出有机物，立即获胜！" % cp.player_name)
			else:
				_show_info("有机物打出失败！")
		_dispatch_result(result)
		return

	step_mode = 2
	compound_selections.clear()
	_update_action_panel()

func _on_choose_organic() -> void:
	var cp = _view_player()
	var cards: Array = _sel_cards()
	# 检查是否为有机物
	if CardPatternsScript.detect_pattern(cards, true) != CardPatternsScript.CardPattern.ORGANIC:
		_show_info("不是有效有机物！有机物包括：甲烷CH4、乙烷C2H6、丙烷C3H8及他们的单一卤代物。\n卤代物只能包含一种卤族元素(F/Cl/Br)。")
		_on_back()
		return
	# 打出有机物，标记 _organic 跳过族炸检测
	var custom_valences = {"_organic": true}
	var result = _router().play(cards, custom_valences, CardPatternsScript.CardPattern.ORGANIC)
	if net_session != null:
		_dispatch_result(result)
		return
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
	# 选中牌一次性拍快照（重排 / 抽牌后 selected_indices 可能已对不上，_sel_cards 内部按按钮 meta 兜底）
	var sel_cards: Array = _sel_cards()

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
	for card in sel_cards:
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
		for card in sel_cards:
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
		var result = _router().play(ccards, custom_valences, CardPatternsScript.CardPattern.COMPOUND)
		_dispatch_result(result)
		return

	# 3+ 元素化合物：总电荷 Σ = 0 即可（不再要求「每种恰好 1 张」）。
	# 引擎侧同口径（_search_valences 支持 2~3 元素、按张数加权），所以
	# H×2 + S + O×4 能直接出 H₂SO₄，H×2 + O×2 能出 H₂O₂，Ca + O×2 能出 CaO₂。
	# P14-B：失败提示要说清是哪一项不对 —— 真机截图里玩家选了 H,H,C,N，
	# 旧提示只说「仅支持 2 元素化合物」，完全不知道问题在哪。
	var total_charge = 0
	for e in valence_list:
		total_charge += e.sign * e.v * e.avail   # 按张数累加：2 张 H 就是 2 份价
	if total_charge == 0:
		var ccards: Array = sel_cards.duplicate()
		var result = _router().play(ccards, custom_valences, CardPatternsScript.CardPattern.COMPOUND)
		_dispatch_result(result)
		return

	# 逐项列出「价 × 张数」，玩家一眼能看出哪个元素多带了 / 少带了
	var parts: Array = []
	for e in valence_list:
		parts.append("%s%+d×%d" % [e.symbol, e.sign * e.v, e.avail])
	_show_info("化合价配不平：%s → Σ = %+d（需 0）。\n正负价按张数相乘相加必须为 0，例如 H(−1)×2+C(+4)+N(−3)=0。" \
		% [" + ".join(parts), total_charge])

func _on_reset_valence() -> void:
	compound_selections.clear()
	_update_action_panel()


# 混合价态一键出牌（v4）：Fe₃O₄ 这类「同元素多价」的组合走这条路径。
# cv 由 _mixed_valence_for_selection() 求出并校验过配平，这里只负责收集卡牌并交给引擎。
func _on_confirm_mixed_valence(cv: Dictionary) -> void:
	_play_selected_compound(cv)


# 「自动配平 ▶」（P14-B）：统一价态可行解一键打出，走的是与混合价态完全相同的一条路径。
# 有了它，玩家不必靠猜「到底该选哪个价」——被拒一次就点一下，引擎自己给答案。
func _on_confirm_auto_valence(cv: Dictionary) -> void:
	_play_selected_compound(cv)


# 用给定的 {symbol: valence} 把当前选中的牌当化合物打出（统一 / 混合价态共用）
func _play_selected_compound(cv: Dictionary) -> void:
	if game_manager == null:
		return
	var ccards := _sel_cards()
	if ccards.size() < 2:
		_show_info("请先选择要打出的化合物卡牌！")
		return
	var result = _router().play(ccards, cv.duplicate(true), CardPatternsScript.CardPattern.COMPOUND)
	_dispatch_result(result)


func _on_back() -> void:
	_clear_hint()
	step_mode = 0
	compound_selections.clear()
	_update_action_panel()
	_update_card_info_label()

func _on_pass() -> void:
	if net_session != null and not _net_can_operate():
		return
	var cp = _view_player()
	if cp == null:
		return
	var hand_limit = game_manager.get_hand_limit()
	if cp.get_hand_count() >= hand_limit:
		_on_discard_mode()
		return
	var code: int = _router().pass_turn()
	if net_session == null:
		# 单机：与重构前逐字一致（跳过不该走 _handle_result 的「出牌成功」提示与飞牌）
		_step_reset()
		_refresh_ui()
		return
	_dispatch_result(code)

func _on_discard_mode() -> void:
	if net_session != null and not _net_can_operate():
		return
	var cp = _view_player()
	if cp == null:
		return
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
	var picked: Array = _sel_cards()
	if picked.size() != 1:
		_show_info("请选择恰好1张牌弃置！")
		return
	var card = picked[0]
	# 弃牌抬起（A3）：同样抢在数据层改动 / 重建之前（hand_buttons 此时还是旧的一批）
	# 联机不播：局面要等主机裁决，先飞走会让人以为已经弃掉了
	if net_session == null:
		_fly_discarded_card()
	var code: int = _router().discard_and_pass(card)
	if net_session == null:
		step_mode = 0
		_step_reset()
		_refresh_ui()
		return
	_dispatch_result(code)


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

		# 出牌飞入（A3）：必须抢在 _step_reset / _refresh_ui 之前 —— 那时手牌按钮还在原位。
		# 幽灵牌挂在 ContentLayer 上，_refresh_ui 重建手牌后仍然存在，随后飞向桌面小卡。
		var fly_snaps: Array = _capture_play_fly_in()
		_step_reset()
		_refresh_ui()
		_replay_play_fly_in(fly_snaps)
		return
	elif result == 1:  # 打出顺序，需要选择指定牌型
		_step_reset()
		_show_sequence_constraint_dialog()
		return
	var msg = "非法出牌！"
	if result == -1:
		# 化合物配不平 / 牌型不成立：引擎把人话原因写在 last_reject_reason 里（P14-B）。
		# 以前 -1 只有一句「非法出牌！」，玩家根本不知道是 Σ≠0 还是多带了一张牌。
		if game_manager != null:
			var why1: String = game_manager.get_last_reject_reason()
			if why1 != "":
				msg = "非法出牌！\n" + why1
	elif result == -2:
		# 引擎把 -2 的细分原因写在 last_reject_reason 里：
		# 牌型被压制 / 族炸张数不够 / 原子序数和不够 / 与桌面打平
		msg = "牌不够大！"
		if game_manager != null:
			var why: String = game_manager.get_last_reject_reason()
			if why != "":
				msg += "\n" + why
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
	# 兜底（P14-E）：toast 2.5 秒就自动消失，把同一条拒绝原因留在手牌下方的信息栏
	# （CardInfoLabel 是 804×48、autowrap，两行放得下），下一次操作刷新时自动回到「提示: …」。
	if card_info_label:
		card_info_label.text = msg


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
	desc.text = "打出「顺序」后，出牌方向已反转。\n请选择让下一名玩家打出哪种牌型（只约束这一名玩家，\n其他人出牌 / 族炸 / 跳过都不会替它解除），\n否则该玩家将被罚抽2张牌。"
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
			var code: int = _router().pick_sequence(p)
			overlay.queue_free()
			_seq_overlay = null
			if net_session == null:
				_refresh_ui()
			else:
				_dispatch_result(code)
		# 与操作面板同一套按钮样式（P2 统一）
		var btn = _mkb(patterns[i].name, choose, false)
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 15)
		btn.position = Vector2(320 + (i % 3) * 150, 370 + int(i / 3.0) * 50)
		overlay.add_child(btn)

	# 取消按钮（不指定，视为放弃权利）
	var cancel_cb := func():
		var code: int = _router().skip_sequence()
		overlay.queue_free()
		_seq_overlay = null
		if net_session == null:
			_refresh_ui()
		else:
			_dispatch_result(code)
	var cancel_btn = _mkb("跳过指定", cancel_cb, false)
	cancel_btn.custom_minimum_size = Vector2(140, 40)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.position = Vector2(470, 370 + int(patterns.size() / 3.0) * 50 + 10)
	overlay.add_child(cancel_btn)

	_layer(1).add_child(overlay)
	_seq_overlay = overlay


# ============================================================
func _step_reset() -> void:
	_clear_hint()
	selected_indices.clear()
	step_mode = 0
	compound_selections.clear()

func _show_info(text: String) -> void:
	# 状态栏只刷新「常驻状态」（牌权链 / AI 手牌 / 补充规则 / 方向），不再把消息拼在后面。
	# 为什么（P14-E）：InfoLabel 高 88px 只够 4 行，_format_player_status() 本身就要 3~4 行，
	# 再拼一行拒绝原因就顶出边界、压在 y=152 的「桌面: …」上（真机截图里那团灰字）。
	# 消息的唯一出口是右栏 toast —— 本来两个地方就在显示同一句话，属于重复。
	if info_label and game_manager:
		info_label.text = _format_player_status()
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
	# 联机（Step 3，D8）：AI 只能由主机 _update_net() 代打，本入口仅单机可用
	if net_session != null:
		return
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


# ============================================================
# 十八、联机（P11-C1-c Step 3）
# ------------------------------------------------------------
# 三条不许破的线：
#   ① 单机红线：所有联机逻辑都在 `net_session != null` 分支里；不挂会话时本段代码
#      一次都不执行（44 套单机测试逐字不变）。
#   ② 视图归属（D6）：客人只看到自己的手牌 / 自己的可用牌型，与「当前行动者」无关。
#   ③ 主机权威（D1）：客人提交后返回 0 只代表「已发出」，界面一律停在
#      「已提交，等待主机裁决…」，直到 state_applied / intent_rejected 回来。
# 装配只有一个入口 attach_session()：房间页传入会话，测试传入假会话 / 真实会话。
# ============================================================

# 动作层懒装配：测试常常直接换 game_manager 而不走 attach_session，
# 这里保证「第一次动手时」router 一定指向当前的 GameManager（单机 session = null）。
func _router():
	if action_router == null:
		action_router = ActionRouterScript.new()
		action_router.setup(game_manager, net_session)
	elif action_router.game != game_manager:
		action_router.setup(game_manager, net_session)
	return action_router


# 装配联机会话。session == null 表示退回单机（动作层同时切回直连 GameManager）。
func attach_session(session) -> void:
	net_session = session
	if action_router == null:
		action_router = ActionRouterScript.new()
	action_router.setup(game_manager, session)
	# 换座 / 重连后残留的热座认领与只读态必须清零（D7）
	_hotseat_ready_seat = -1
	_hand_read_only = false
	_net_ai_wait = 0.0
	if session == null:
		_hide_sequence_overlay()
		return
	_connect_online_signals(session)
	# 会话已经在对局中（重连 / 热加入）：直接切到牌桌，不必等 game_started
	if session.is_playing() and game_manager != null:
		_enter_online_game()


# -------- 座位 / 视图归属 --------
func _my_seat() -> int:
	if net_session == null:
		return -1
	return int(net_session.my_seat)


# 本地视角的玩家：单机 = 当前行动者；联机 = 自己座位（观战 = null）
func _view_player():
	if game_manager == null:
		return null
	if net_session == null:
		return game_manager.get_current_player()
	var seat := _my_seat()
	if seat < 0 or seat >= game_manager.players.size():
		return null
	return game_manager.players[seat]


# 现在这份手牌能不能动：对局中 + 轮到我 + 没有待处理两阶段 + 没有待裁决意图
func _net_can_operate() -> bool:
	if net_session == null or action_router == null:
		return false
	if not net_session.can_submit():
		return false
	if not net_session.is_my_turn():
		return false
	return not action_router.awaiting_reply()


# 操作面板的等待文案（"" = 该显示正常按钮）
func _net_wait_text() -> String:
	if net_session == null:
		return ""
	if net_session.is_watcher():
		return "观战中：本轮由其他玩家操作"
	if action_router != null and action_router.awaiting_reply():
		return "已提交，等待主机裁决…"
	if net_session.is_my_sequence_pending():
		return "请先在弹窗中选择牌型（或跳过指定）"
	if not net_session.is_my_turn():
		var actor = game_manager.get_current_player() if game_manager != null else null
		var who: String = actor.player_name if actor != null else "对手"
		return "等待 %s 行动…" % who
	return ""


# 等待提示用一个 Label（与按钮同高，_fit_action_panel 的行数计算对 Control 一视同仁）
func _mk_wait_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.33, 0.4, 0.5, 1))
	lbl.custom_minimum_size = Vector2(0, _action_btn_h())
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


# -------- 动作结果分派（D1 / D2）--------
# 单机：原样交给 _handle_result（返回码 = 规则码，飞牌 / 弹窗 / 提示全靠它）
# 联机：客人侧 0 只代表「已发出」；主机侧规则码当场有效，但 1 = 轮到自己选牌型
func _dispatch_result(code: int) -> void:
	if net_session == null:
		_handle_result(code)
		return
	if action_router != null and action_router.awaiting_reply():
		# 客人：等 state_applied / intent_rejected，先把自己刷成「已提交」态
		_update_action_panel()
		_update_card_info_label()
		return
	if int(code) == 0:
		return                      # 主机：_host_apply 已广播并触发 _online_on_state_applied
	if int(code) == 1:
		_step_reset()
		_show_sequence_constraint_dialog()
		return
	var why: String = action_router.last_reason() if action_router != null else ""
	if why == "":
		why = ActionRouterScript.describe_code(int(code))
	_show_info("操作被拒绝：" + why)
	_on_back()


# -------- 信号接线（attach_session 可能因重连被重复调用，必须只连一次）--------
func _connect_online_signals(session) -> void:
	if not session.game_started.is_connected(_online_on_game_started):
		session.game_started.connect(_online_on_game_started)
	if not session.state_applied.is_connected(_online_on_state_applied):
		session.state_applied.connect(_online_on_state_applied)
	if not session.intent_rejected.is_connected(_online_on_intent_rejected):
		session.intent_rejected.connect(_online_on_intent_rejected)
	if not session.sequence_pending.is_connected(_online_on_sequence_pending):
		session.sequence_pending.connect(_online_on_sequence_pending)
	if not session.sequence_cleared.is_connected(_online_on_sequence_cleared):
		session.sequence_cleared.connect(_online_on_sequence_cleared)
	if not session.session_closed.is_connected(_online_on_session_closed):
		session.session_closed.connect(_online_on_session_closed)
	if not session.desync_detected.is_connected(_online_on_desync):
		session.desync_detected.connect(_online_on_desync)
	if not session.error_raised.is_connected(_online_on_error):
		session.error_raised.connect(_online_on_error)


# -------- 信号回调 --------
func _online_on_game_started() -> void:
	_enter_online_game()


func _online_on_state_applied(_ev: Dictionary, _result: int) -> void:
	if game_manager == null:
		return
	# 主机自己的一手在 submit() 里当场落子（同步），客人靠重放；
	# 两条路径都在这里收口：清步骤态 → 整屏重画（_refresh_ui 负责结算页）
	_step_reset()
	_refresh_ui()


func _online_on_intent_rejected(_seq: int, code: int) -> void:
	_show_info("主机拒绝：" + ActionRouterScript.describe_code(int(code)))
	_step_reset()
	_refresh_ui()


func _online_on_sequence_pending(seat: int, remain_ms: int) -> void:
	if game_manager == null:
		return
	if seat != _my_seat():
		# 别人在选牌型：轮不到我，先把面板刷成等待态
		_refresh_ui()
		return
	_show_sequence_constraint_dialog()
	_refresh_ui()
	_show_info("请选择下一名玩家必须打出的牌型（%d 秒内）" % maxi(1, int(remain_ms / 1000)))


func _online_on_sequence_cleared() -> void:
	_hide_sequence_overlay()
	_refresh_ui()


func _online_on_session_closed(reason: String) -> void:
	# 会话没了，此刻还开着的顺序牌型弹窗就永远等不到 sequence_cleared 了
	_hide_sequence_overlay()
	# 自己主动关的（离开房间 / 退出对局）：调用方已在收尾，别再刷一遍提示
	if _room_closing:
		return
	_room_mode = RoomMode.IDLE
	_room_connect_wait = 0.0
	var msg := "联机已结束"
	if reason != "":
		msg += "：" + reason
	# 房间里掉线（房主离开 / 连不上 / 被拒）：留在房间页显示原因。
	# 大厅里 game_manager 的 players 是空的，这时 _refresh_ui() 会去读空局面，
	# 所以绝不能落到下面的通用分支（Step 4 修掉的隐患，见 D13）
	if _room_page != null and is_instance_valid(_room_page) and _room_page.visible:
		_room_teardown()
		_room_hint(msg)
		return
	_show_info(msg)
	# 单机 / 房间页关着：只有真的有一局在打才刷新（0 玩家时刷 = 读空局面）
	if game_manager != null and game_manager.get_player_count() > 0:
		_refresh_ui()


func _online_on_desync(local_hash: int, host_hash: int) -> void:
	# 分叉后不再推进，弹窗留着只会让人以为还能选
	_hide_sequence_overlay()
	_show_info("状态分叉（本端 %d / 主机 %d），已停止推进" % [int(local_hash), int(host_hash)])
	_refresh_ui()


func _online_on_error(code: int, detail: String) -> void:
	_show_info("联机错误 %d：%s" % [int(code), String(detail)])


# 顺序牌型弹窗的唯一关闭口（两个回调 / 超时 / 会话结束都走它）
func _hide_sequence_overlay() -> void:
	if _seq_overlay != null and is_instance_valid(_seq_overlay):
		_seq_overlay.queue_free()
	_seq_overlay = null


# -------- 每帧驱动（_process 第一行）--------
func _update_net(delta: float) -> void:
	if net_session == null:
		return
	# ① 收包 / 超时 / 断线宽限：所有角色都必须 poll，否则永远收不到包
	net_session.poll()
	# ①之二 房间页：ENet 的 create_client 是异步的，连不上时一个回调都不会来，
	#       只能自己计时给条出路（否则客人会永远停在「正在连接…」）
	if _room_mode == RoomMode.CONNECTING:
		_room_connect_wait += delta
		if _room_connect_wait >= ROOM_CONNECT_TIMEOUT_S:
			var target := _room_join_target
			_room_teardown()
			_room_hint("连不上 %s：检查房主 IP / 端口 / 防火墙是否放行" % target)
			return
	if game_manager == null:
		return
	# ② 主机代打 AI 座位（D8）：单机那份「AI 计时器」在联机被关掉了，
	#    不在这里推进，AI 回合会永远停住
	if not net_session.is_host():
		return
	if not net_session.is_playing() or game_manager.is_game_over():
		return
	# 客人还没按快照重建完就替 AI 出牌 → 客人重放必分叉（host_step_ai 内部也有这道门，
	# 这里提前挡住，顺带清零节流，避免重建完成后立刻连打好几手）
	if not net_session.all_seats_ready():
		_net_ai_wait = 0.0
		return
	var cp = game_manager.get_current_player()
	if cp == null or not cp.is_ai:
		_net_ai_wait = 0.0
		return
	_net_ai_wait += delta
	if _net_ai_wait < NET_AI_DELAY_S:
		return
	_net_ai_wait = 0.0
	# host_step_ai 内部走 host_act_for_seat → _host_apply → state_applied，
	# 界面刷新由 _online_on_state_applied 负责，这里不再重复刷
	net_session.host_step_ai(1)


# -------- 进牌桌（联机版 _on_start_game：局面由会话给，不在这里 new GameManager）--------
func _enter_online_game() -> void:
	if game_manager == null:
		return
	start_page.visible = false
	game_page.visible = true
	end_page.visible = false
	if help_page: help_page.visible = false
	# 教学关卡列表可能刚从开始页打开，会盖在 GamePage 上
	var tut_page = get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	_close_supp_rules()
	# Step 4：房间页挂在开始页下面，跟着 start_page 一起藏起来；
	# 这里只隐藏、绝不 teardown —— 开局后会话还要用
	if _room_page != null and is_instance_valid(_room_page):
		_room_page.visible = false
	_hide_warning_toast()
	_hotseat_ready_seat = -1
	log_lines.clear()
	if log_label:
		log_label.text = "游戏日志:"
	_fade_in_page(game_page)
	_step_reset()
	_refresh_ui()


# ============================================================
# 十九、房间页（P11-C1-c Step 4）
# ------------------------------------------------------------
# 为什么代码建页（D5）：现有 6 个页面全是代码生成；改 Main.tscn 会拖累一批
# 布局测试，而这一页只有联机时才用得上。
#
# 三条不许破的线：
#   ① 单机红线：不点「联机对战」就一行都不会执行（页默认隐藏、会话默认 null）。
#   ② 会话只有一个装配口 _room_bind_session() → attach_session()（D13）；
#      离开房间一律 _room_teardown()：close 会话 + attach_session(null) +
#      丢掉大厅那份空 GameManager。闭着的会话绝不许留在 net_session 上，
#      否则单机「开始游戏」会被 D6 拦成「请从房间页开局」。
#   ③ 座位 3~4（D15）：GameManager.MIN_PLAYERS = 3 且 NetSession.start_game()
#      把 player_count clamp 到 2..4 —— 2 座位会在 init_game 里直接失败。
#
# 大厅没有 ready 握手（D12）：客人的 MSG_READY 是「快照重建完成」，开局后才发，
# 所以 all_seats_ready() 在大厅恒为 false。开局闸门只能是「在线人类数 + AI 数
# ∈ [3,4]」，拿 ready 门控等于永远开不了局。
# ============================================================

func _build_room_page() -> void:
	if not start_page:
		return
	var page := Control.new()
	page.name = "RoomPage"
	page.visible = false
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	start_page.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_room_page = page
	_page_bg_into(page, "RoomBg", "RoomBand")

	var back := _page_ghost_btn("‹ 返回", _close_room_page, Vector2(140, 34), "RoomBackBtn", 15)
	back.position = Vector2(46, 34)
	page.add_child(back)

	page.add_child(_room_label("RoomTitle", "联机对战", Vector2(0, 62), Vector2(1152, 46),
		34, START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER))

	# D14：房号只是辨认用的 4 位数，不代表任何地址（发现层在 P11-C2）。
	# 副标题必须写死这句，别让人以为「输房号就能连」
	page.add_child(_room_label("RoomSubtitle",
		"局域网 / Tailscale 直连 · 3~4 人 · 房号仅用于辨认，客人需填房主 IP",
		Vector2(0, 110), Vector2(1152, 20), START_FS_META, START_C_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER))

	_room_host_card(page)
	_room_join_card(page)
	_room_seats_panel(page)

	_room_hint_label = _room_label("RoomHintLabel", "", Vector2(46, 556), Vector2(1060, 22),
		START_FS_META, START_C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	page.add_child(_room_hint_label)

	page.add_child(_room_label("RoomAiLabel", "AI 人数", Vector2(46, 592), Vector2(110, 34),
		START_FS_LABEL, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	_room_ai_spin = _start_make_spin(0, ROOM_MAX_SEATS - 1, 0, "RoomAiSpin")
	_room_ai_spin.position = Vector2(162, 590)
	_room_ai_spin.size = Vector2(150, 38)
	_room_ai_spin.tooltip_text = "空座位由 AI 补上（人类座位在前，AI 在后）"
	_room_ai_spin.value_changed.connect(_on_room_ai_changed)
	page.add_child(_room_ai_spin)

	_room_start_btn = _page_primary_btn("开始对局", _room_start, Vector2(260, 50), "RoomStartBtn", 20)
	_room_start_btn.position = Vector2(846, 586)
	_room_start_btn.disabled = true
	page.add_child(_room_start_btn)

	_room_refresh()


# 房间页统一的小标签工厂：_start_label() 只给字号 / 颜色 / 对齐，尺寸由调用点定
func _room_label(node_name: String, text: String, pos: Vector2, sz: Vector2,
		fs: int = START_FS_META, col: Color = START_C_TITLE,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lb := _start_label(text, fs, col, align)
	lb.name = node_name
	lb.position = pos
	lb.size = sz
	return lb


# 带白底 + 主题蓝焦点框的单行输入框（与 _start_make_spin 里的 LineEdit 同一套画风）
func _room_line_edit(node_name: String, text: String, pos: Vector2, sz: Vector2) -> LineEdit:
	var le := LineEdit.new()
	le.name = node_name
	le.text = text
	le.position = pos
	le.size = sz
	le.custom_minimum_size = sz
	le.add_theme_font_size_override("font_size", 17)
	le.add_theme_color_override("font_color", START_C_TITLE)
	var n := _make_panel_style("mini_card")
	n.bg_color = Color(1, 1, 1, 1)
	n.content_margin_left = 10
	n.content_margin_right = 6
	le.add_theme_stylebox_override("normal", n)
	var f: StyleBoxFlat = n.duplicate()
	f.border_color = START_C_ACCENT
	f.set_border_width_all(BORDER_W_ACTIVE)
	le.add_theme_stylebox_override("focus", f)
	return le


# -------- 建房卡：昵称 / 端口 / 本机 IP / 创建 --------
func _room_host_card(page: Control) -> void:
	var card := Panel.new()
	card.name = "RoomHostCard"
	card.position = Vector2(46, 146)
	card.size = Vector2(520, 210)
	var cs := _make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.94)
	card.add_theme_stylebox_override("panel", cs)
	page.add_child(card)

	card.add_child(_room_label("RoomHostTitle", "建房（房主）", Vector2(24, 10), Vector2(300, 24),
		START_FS_LABEL, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	card.add_child(_room_label("RoomHostNameLabel", "昵称", Vector2(24, 46), Vector2(60, 36),
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_room_host_name_edit = _room_line_edit("RoomHostNameEdit", "房主",
		Vector2(88, 46), Vector2(156, 36))
	card.add_child(_room_host_name_edit)
	card.add_child(_room_label("RoomHostPortLabel", "端口", Vector2(256, 46), Vector2(56, 36),
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_room_host_port_spin = _start_make_spin(1024, 65535, ROOM_DEFAULT_PORT, "RoomPortSpin")
	_room_host_port_spin.position = Vector2(316, 46)
	_room_host_port_spin.size = Vector2(130, 36)
	card.add_child(_room_host_port_spin)

	_room_host_ip_label = _room_label("RoomHostIpLabel", "本机 IP：检测中…",
		Vector2(24, 90), Vector2(470, 40), START_FS_META, START_C_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT)
	_room_host_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_room_host_ip_label)

	_room_create_btn = _page_primary_btn("创建房间", _room_start_host, Vector2(200, 44), "RoomCreateBtn", 19)
	_room_create_btn.position = Vector2(24, 140)
	card.add_child(_room_create_btn)

	_room_code_label = _room_label("RoomCodeLabel", "房号 ----", Vector2(240, 152), Vector2(260, 26),
		START_FS_LABEL, START_C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	card.add_child(_room_code_label)


# -------- 加入卡：昵称 / 端口 / 房主 IP / 加入 + 离开 --------
func _room_join_card(page: Control) -> void:
	var card := Panel.new()
	card.name = "RoomJoinCard"
	card.position = Vector2(586, 146)
	card.size = Vector2(520, 210)
	var cs := _make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.94)
	card.add_theme_stylebox_override("panel", cs)
	page.add_child(card)

	card.add_child(_room_label("RoomJoinTitle", "加入房间（客人）", Vector2(24, 10), Vector2(300, 24),
		START_FS_LABEL, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	card.add_child(_room_label("RoomJoinNameLabel", "昵称", Vector2(24, 46), Vector2(60, 36),
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_room_join_name_edit = _room_line_edit("RoomJoinNameEdit", "玩家",
		Vector2(88, 46), Vector2(156, 36))
	card.add_child(_room_join_name_edit)
	card.add_child(_room_label("RoomJoinPortLabel", "端口", Vector2(256, 46), Vector2(56, 36),
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_room_join_port_spin = _start_make_spin(1024, 65535, ROOM_DEFAULT_PORT, "RoomJoinPortSpin")
	_room_join_port_spin.position = Vector2(316, 46)
	_room_join_port_spin.size = Vector2(130, 36)
	card.add_child(_room_join_port_spin)

	card.add_child(_room_label("RoomJoinAddrLabel", "房主 IP", Vector2(24, 92), Vector2(84, 36),
		START_FS_META, START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_room_addr_edit = _room_line_edit("RoomAddrEdit", "127.0.0.1",
		Vector2(112, 92), Vector2(210, 36))
	_room_addr_edit.tooltip_text = "房主页面上「本机 IP」那一串（如 192.168.1.7）"
	card.add_child(_room_addr_edit)
	card.add_child(_room_label("RoomJoinAddrHint", "例 192.168.1.7",
		Vector2(330, 96), Vector2(170, 24), START_FS_META, START_C_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT))

	_room_join_btn = _page_primary_btn("加入房间", _room_join, Vector2(180, 44), "RoomJoinBtn", 19)
	_room_join_btn.position = Vector2(24, 140)
	card.add_child(_room_join_btn)
	_room_leave_btn = _page_secondary_btn("离开房间", _room_leave, Vector2(150, 44), "RoomLeaveBtn", 17)
	_room_leave_btn.position = Vector2(216, 140)
	_room_leave_btn.disabled = true
	card.add_child(_room_leave_btn)



# -------- 座位表：固定 4 张卡（max_players 恒为 4）--------
# 为什么不用动态重建：座位数只在 1..4 之间变，4 张卡直接摆好改文字最省事，
# 测试也能按名字 "RoomSeatName_0" 稳定取到，不用担心重建时机。
func _room_seats_panel(page: Control) -> void:
	var panel := Panel.new()
	panel.name = "RoomSeatsPanel"
	panel.position = Vector2(46, 372)
	panel.size = Vector2(1060, 176)
	var st := _make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.94)
	panel.add_theme_stylebox_override("panel", st)
	page.add_child(panel)

	panel.add_child(_room_label("RoomSeatsTitle", "座位表（人类座位在前，AI 座位在后）",
		Vector2(24, 8), Vector2(700, 24), START_FS_LABEL, START_C_TITLE,
		HORIZONTAL_ALIGNMENT_LEFT))

	_room_seat_cards.clear()
	_room_seat_names.clear()
	_room_seat_states.clear()
	for i in range(ROOM_MAX_SEATS):
		var sc := Panel.new()
		sc.name = "RoomSeatCard_%d" % i
		sc.position = Vector2(24 + i * 256, 38)
		sc.size = Vector2(240, 122)
		var ss := _make_panel_style("mini_card")
		ss.bg_color = Color(0.965, 0.976, 0.99, 1.0)
		ss.border_color = Color(0.85, 0.89, 0.94, 1.0)
		ss.set_border_width_all(1)
		sc.add_theme_stylebox_override("panel", ss)
		panel.add_child(sc)

		sc.add_child(_room_label("RoomSeatNo_%d" % i, "座位 %d" % (i + 1),
			Vector2(14, 8), Vector2(212, 18), START_FS_META, START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT))
		var nm := _room_label("RoomSeatName_%d" % i, "空位",
			Vector2(14, 30), Vector2(212, 30), 20, START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(nm)
		var stt := _room_label("RoomSeatState_%d" % i, "—",
			Vector2(14, 72), Vector2(212, 20), START_FS_META, START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(stt)
		_room_seat_cards.append(sc)
		_room_seat_names.append(nm)
		_room_seat_states.append(stt)


# -------- 整页刷新：座位表 / 房号 / 提示 / 4 颗按钮的可用态 --------
func _room_refresh() -> void:
	if _room_page == null or not is_instance_valid(_room_page):
		return
	var online := _room_online_humans()
	var offline := _room_offline_humans()
	var seat_total := int(net_session.seat_count()) if net_session != null else 0
	var my_seat := int(net_session.my_seat) if net_session != null else -1

	# AI 上限 = 剩下的空座位（总座位最多 4）：3 个真人在线就一个 AI 也加不了
	if _room_ai_spin != null:
		var ai_cap := maxi(0, ROOM_MAX_SEATS - online)
		_room_ai_spin.max_value = ai_cap
		if int(_room_ai_spin.value) > ai_cap:
			_room_ai_spin.value = ai_cap      # Range 会把超限值压回 max
	var ai := _room_ai_value()
	var planned := online + ai

	for i in range(ROOM_MAX_SEATS):
		var name_text := "空位"
		var state_text := "—"
		var taken := false
		if i < seat_total:
			taken = true
			name_text = String(net_session.seat_name(i))
			if name_text == "":
				name_text = "玩家 %d" % (i + 1)
			if not net_session.seat_is_online(i):
				state_text = "掉线中 · 座位保留"
			elif i == 0 and net_session.is_host():
				state_text = "房主 · 你" if my_seat == i else "房主"
			elif my_seat == i:
				state_text = "你 · 在线"
			else:
				state_text = "在线"
		elif i >= online and (i - online) < ai:
			# 人类座位永远排在前面 → 第 online 个之后的空座位才是 AI
			taken = true
			name_text = "AI %d" % (i - online + 1)
			state_text = "AI 托管"
		if i >= _room_seat_names.size():
			continue
		_room_seat_names[i].text = name_text
		_room_seat_names[i].add_theme_color_override("font_color",
			START_C_TITLE if taken else START_C_MUTED)
		_room_seat_states[i].text = state_text
		_room_seat_states[i].add_theme_color_override("font_color",
			START_C_ACCENT if taken else START_C_MUTED)

	if _room_code_label != null:
		var code := String(net_session.room_code) if net_session != null else ""
		_room_code_label.text = ("房号 " + code) if code != "" else "房号 ----"
	if _room_host_ip_label != null:
		_room_host_ip_label.text = _room_ip_text()

	var joined := net_session != null
	if _room_create_btn != null:
		_room_create_btn.disabled = joined
	if _room_join_btn != null:
		_room_join_btn.disabled = joined
	if _room_leave_btn != null:
		_room_leave_btn.disabled = not joined
	if _room_start_btn != null:
		var reason := _room_start_disabled_reason()
		_room_start_btn.disabled = reason != ""
		if reason == "":
			_room_start_btn.text = "开始对局"
		elif joined and not net_session.is_host():
			_room_start_btn.text = "等待房主开始"
		elif joined:
			_room_start_btn.text = "开始对局 · %d/%d 座位" % [mini(planned, ROOM_MAX_SEATS), ROOM_MAX_SEATS]
		else:
			_room_start_btn.text = "开始对局"
	# 掉线提示只在提示区空着时补一句（否则会盖掉「xxx 加入了」这类操作反馈）
	if offline > 0 and _room_hint_label != null and _room_hint_label.text == "":
		_room_hint_label.text = "有玩家掉线，座位会保留 %d 秒等重连" % int(int(net_session.reconnect_grace_ms) / 1000)


# -------- 本机 IP：房主要把这一串报给客人（D14：房号不是地址）--------
func _room_local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.find(":") >= 0:
			continue                 # IPv6 不列：手输太长，局域网 IPv4 够用
		if s.begins_with("127."):
			continue                 # 回环：本机自测用，别当房主地址报给客人
		if s.begins_with("169.254."):
			continue                 # 链路本地地址：实际连不通
		out.append(s)
	out.sort()
	return out


func _room_ip_text() -> String:
	var ips := _room_local_ips()
	if ips.is_empty():
		return "本机 IP：未检测到局域网地址（同一台机器自测可用 127.0.0.1）"
	var txt := ""
	for ip in ips:
		if txt != "":
			txt += " / "
		txt += String(ip)
	return "本机 IP：%s（客人填这一串）" % txt


# -------- 开局闸门（D12 / D15）--------
# 纯函数：只吃 5 个数，不碰会话 / 控件，测试可以逐格喂边界。
# 返回 "" = 可以开局；其余 = 直接显示给用户的原因
func _room_start_block_reason(online_humans: int, ai_count: int, is_host: bool,
		room_state: int, offline_seats: int = 0) -> String:
	if not is_host:
		return "等待房主开始"
	if room_state == NetSessionScript.State.PLAYING:
		return "对局已开始"
	if room_state != NetSessionScript.State.LOBBY:
		return "房间未就绪"
	var total := int(online_humans) + int(ai_count)
	if total < ROOM_MIN_SEATS:
		return "座位不足：至少 %d 个（当前 %d）" % [ROOM_MIN_SEATS, total]
	if total > ROOM_MAX_SEATS:
		return "座位超限：最多 %d 个（当前 %d）" % [ROOM_MAX_SEATS, total]
	if int(offline_seats) > 0:
		return "有玩家掉线，等重连后再开局"
	return ""


# 会话 → 闸门参数。state 用 is_playing() 反推，不去读会话内部字段
# （假会话只需要实现 is_host / is_playing / seat_count / seat_is_online 这几条查询）
func _room_start_disabled_reason() -> String:
	if net_session == null:
		return "还没加入房间"
	var st := NetSessionScript.State.LOBBY
	if net_session.is_playing():
		st = NetSessionScript.State.PLAYING
	return _room_start_block_reason(_room_online_humans(), _room_ai_value(),
		net_session.is_host(), st, _room_offline_humans())


func _room_can_start() -> bool:
	return _room_start_disabled_reason() == ""


func _room_online_humans() -> int:
	if net_session == null:
		return 0
	var n := 0
	for s in range(int(net_session.seat_count())):
		if net_session.seat_is_online(s):
			n += 1
	return n


func _room_offline_humans() -> int:
	if net_session == null:
		return 0
	var n := 0
	for s in range(int(net_session.seat_count())):
		if not net_session.seat_is_online(s):
			n += 1
	return n


func _room_ai_value() -> int:
	return int(_room_ai_spin.value) if _room_ai_spin != null else 0


# -------- 页面开关 --------
func _open_room_page() -> void:
	if _room_page == null or not is_instance_valid(_room_page):
		return
	_room_page.visible = true
	_room_refresh()
	_fade_in_page(_room_page)


func _close_room_page() -> void:
	_room_teardown()
	if _room_page != null and is_instance_valid(_room_page):
		_room_page.visible = false


# 离开房间 / 回开始页 / 连不上：唯一的收尾口（D13）
func _room_teardown() -> void:
	if _room_closing:
		return
	_room_closing = true
	_room_mode = RoomMode.IDLE
	_room_connect_wait = 0.0
	_room_join_target = ""
	var s = net_session
	if s != null:
		s.close("离开房间")
		attach_session(null)
	# 大厅那份 GameManager 只是给会话占位（players 为空）：留着会让下一次单机开局
	# 带着空 players 进 _refresh_ui。真打过的对局（players 非空）绝不在这里丢
	if game_manager != null and game_manager.get_player_count() == 0:
		game_manager = null
	_room_hint("")
	_room_closing = false
	_room_refresh()


func _room_leave() -> void:
	if net_session == null:
		_room_hint("还不在房间里")
		return
	_room_teardown()
	_room_hint("已离开房间")


func _room_hint(text: String) -> void:
	if _room_hint_label != null and is_instance_valid(_room_hint_label):
		_room_hint_label.text = text


# -------- 建房（房主 = seat 0）--------
func _room_start_host() -> void:
	if net_session != null:
		_room_hint("已经在房间里了：先「离开房间」再新建")
		return
	var port := int(_room_host_port_spin.value) if _room_host_port_spin != null else ROOM_DEFAULT_PORT
	var nm := "房主"
	if _room_host_name_edit != null and _room_host_name_edit.text.strip_edges() != "":
		nm = _room_host_name_edit.text.strip_edges()
	# 大厅也要一份 GameManager：补充规则要在开局前定下来，随 game_start 的 config 下发
	game_manager = GameManagerScript.new()
	_apply_start_page_rules(game_manager)
	var s = NetSessionScript.new()
	s.setup(game_manager, ENetTransportScript.new())
	s.max_players = ROOM_MAX_SEATS
	# 观战者 UI 还没做（见 MULTIPLAYER_TASKS §5）：满员直接拒，别给个看不见的观战位
	s.allow_watchers = false
	_room_bind_session(s)
	if s.start_host(port, ROOM_MAX_SEATS, nm) != 0:
		_room_teardown()
		_room_hint("端口 %d 建不起来（多半被占用）：换一个端口再试" % port)
		return
	_room_mode = RoomMode.HOSTING
	_room_hint("房间已创建：把本机 IP + 端口 %d 告诉客人" % port)
	_room_refresh()


# -------- 加入（客人）--------
func _room_join() -> void:
	if net_session != null:
		_room_hint("已经在房间里了：先「离开房间」再加入")
		return
	var addr := "127.0.0.1"
	if _room_addr_edit != null:
		addr = _room_addr_edit.text.strip_edges()
	if addr == "":
		_room_hint("请填房主 IP（房主页面「本机 IP」那一串，如 192.168.1.7）")
		return
	var port := int(_room_join_port_spin.value) if _room_join_port_spin != null else ROOM_DEFAULT_PORT
	var nm := "玩家"
	if _room_join_name_edit != null and _room_join_name_edit.text.strip_edges() != "":
		nm = _room_join_name_edit.text.strip_edges()
	# 客人这份 GameManager 只为「手上有个对象」：牌库 / 规则最终由主机
	# game_start 的 config + seed 覆盖（NetSession._apply_config_and_init）
	game_manager = GameManagerScript.new()
	_apply_start_page_rules(game_manager)
	var s = NetSessionScript.new()
	s.setup(game_manager, ENetTransportScript.new())
	s.max_players = ROOM_MAX_SEATS
	s.allow_watchers = false
	_room_bind_session(s)
	if s.start_client(addr, port, nm) != 0:
		_room_teardown()
		_room_hint("地址填错了：%s" % addr)
		return
	_room_mode = RoomMode.CONNECTING
	_room_connect_wait = 0.0
	_room_join_target = "%s:%d" % [addr, port]
	_room_hint("正在连接 %s …（连不上 %d 秒后自动放弃）" % [_room_join_target, int(ROOM_CONNECT_TIMEOUT_S)])
	_room_refresh()


# -------- 开局（只有房主能点，闸门见 _room_start_block_reason）--------
func _room_start() -> void:
	var reason := _room_start_disabled_reason()
	if reason != "":
		_room_hint(reason)
		_room_refresh()
		return
	var ai := _room_ai_value()
	var total := _room_online_humans() + ai
	if net_session.start_game(total, ai) != 0:
		_room_hint("开局失败：房间状态异常，请离开后重新建房")
		return
	_room_mode = RoomMode.JOINED
	_room_refresh()   # game_started → _enter_online_game() 已把整页切走


# -------- 会话绑定 / 回调 --------
# 房间页唯一的会话装配口：既复用 Step 3 的 attach_session（视图归属 / 动作层 /
# 8 个对局信号），又额外挂 3 个大厅信号。D13：别在别处直接给 net_session 赋值。
func _room_bind_session(s) -> void:
	attach_session(s)
	if not s.room_changed.is_connected(_room_refresh):
		s.room_changed.connect(_room_refresh)
	if not s.seat_assigned.is_connected(_room_on_seat_assigned):
		s.seat_assigned.connect(_room_on_seat_assigned)
	if not s.peer_joined.is_connected(_room_on_peer_joined):
		s.peer_joined.connect(_room_on_peer_joined)
	if not s.peer_left.is_connected(_room_on_peer_left):
		s.peer_left.connect(_room_on_peer_left)


# 客人收到 welcome（含自己座位）+ 快照后到这儿；seat < 0 = 观战
func _room_on_seat_assigned(seat: int) -> void:
	_room_mode = RoomMode.JOINED
	_room_connect_wait = 0.0
	_room_join_target = ""
	if int(seat) < 0:
		_room_hint("房间已满：你以观战身份进入（对局中只能看，不能出牌）")
	else:
		_room_hint("已加入：你是座位 %d，房主开局后自动进入牌桌" % (int(seat) + 1))
	_room_refresh()


func _room_on_peer_joined(seat: int, peer_name: String) -> void:
	_room_hint("%s 加入了（座位 %d）" % [String(peer_name), int(seat) + 1])
	_room_refresh()


func _room_on_peer_left(seat: int, peer_name: String, grace_ms: int) -> void:
	_room_hint("%s 离开了（座位 %d 保留 %d 秒等重连）" % [
		String(peer_name), int(seat) + 1, int(int(grace_ms) / 1000)])
	_room_refresh()


func _on_room_ai_changed(_value: float) -> void:
	_room_refresh()



