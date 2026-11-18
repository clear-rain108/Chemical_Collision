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
# UI 层拆分（Slice 1，见 UI_LAYER_REFACTOR.md）：
# GameUI.gd 从此只做「门面 + 状态持有者」，实现按功能搬进 scripts/ui/*.gd。
#   · 状态与常量全部留在本文件（测试直读 scene.xxx / scene.CARD_W）
#   · 模块是 RefCounted，只持有回指 _ui，不碰节点树、不复制任何状态
#   · 本文件留同名转发方法 → 全项目 100+ 处调用点与 46 套测试零改动
const UIThemeScript = preload("res://scripts/ui/UITheme.gd")
const TouchMetricsScript = preload("res://scripts/ui/TouchMetrics.gd")
const ToastScript = preload("res://scripts/ui/Toast.gd")
const PageRouterScript = preload("res://scripts/ui/PageRouter.gd")
const CardMotionScript = preload("res://scripts/ui/CardMotion.gd")
const HandViewScript = preload("res://scripts/ui/HandView.gd")
# Slice 3（交互链）
const ToolRowScript = preload("res://scripts/ui/ToolRow.gd")
const TableAreaScript = preload("res://scripts/ui/TableArea.gd")
const SidePanelsScript = preload("res://scripts/ui/SidePanels.gd")
const ActionPanelScript = preload("res://scripts/ui/ActionPanel.gd")
const HintFlowScript = preload("res://scripts/game/HintFlow.gd")
const GameFlowScript = preload("res://scripts/game/GameFlow.gd")
# Slice 4（页面与联机）
const PageChromeScript = preload("res://scripts/pages/PageChrome.gd")

# 模块实例：_init 里创建（见下方 _init 的注释）。
# 命名避开 Control 自带的 theme / 已用的 toast_layer，统一 ui_ 前缀。
var ui_theme = null                      # 样式工厂（panel_style / card_color）
var ui_touch = null                      # 触屏档几何与字号
var ui_toast = null                      # 右栏警告 toast
var ui_router = null                     # 页面切换 + 层容器
var ui_motion = null                     # 牌面动效（幽灵牌飞行 / 小卡入场 / 发牌淡入）
var ui_hand = null                       # 手牌渲染 / 重叠布局 / 悬停 / 拖拽重排 / 价态自适应
var ui_tool = null                       # 工具行三按钮样式 + 几何归一
var ui_table = null                      # 顶部状态栏 + 桌面文案/小卡槽
var ui_side = null                       # 桌面小卡 / 右栏日志 / 「按序 ⇅」/ 信息栏
var ui_action = null                     # 操作面板（出牌步骤流按钮）+ 按钮工厂 _mkb
var ui_hint = null                       # 提示按钮（HintAdvisor → 自动选牌 + 说明）
var ui_flow = null                       # 开局 / 交互回调 / 结果处理 / 步骤重置
var ui_page = null                       # 页面通用零件（渐变底 / 水印 / 装饰牌 / 按钮三件套 / 入场动画）

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
var _net_trace: bool = false            # --net-trace：会话装配时打开逐笔指纹追踪（真机排障）
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
# Slice 1 起实现在 scripts/ui/TouchMetrics.gd（static 方法，脚本级调用
# GameUIScript.resolve_touch_profile(...) 语义不变 —— verify_touch_flag 用它）。
static func resolve_touch_profile(is_mobile: bool, args: Array) -> bool:
	return TouchMetricsScript.resolve_touch_profile(is_mobile, args)


# 当前进程的命令行参数：Godot 自带参数与「-- 之后的用户参数」都扫一遍，
# 于是 `godot --path . --touch-ui` 与 `godot --path . -- --touch-ui` 都能生效。
static func touch_profile_args() -> Array:
	return TouchMetricsScript.touch_profile_args()


# 联机诊断开关（--net-trace）：装配会话时打开「逐笔事件 + 指纹」追踪。
# 真机上拿不到控制台输出，只能靠 adb logcat 收 print；打开后每笔权威事件一行。
# 与触屏档共用同一套参数扫描（自带参数 + `--` 之后的用户参数）。
static func net_trace_requested(args: Array) -> bool:
	for raw in args:
		if String(raw) == "--net-trace":
			return true
	return false



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
# 8 座位时一行绝对放不下 8 个名字（460px / 14px ≈ 32 字），所以名字链每 4 人强制换行。
# AI 手牌行同样每 4 条换行；两者加起来最多 4 行，超出的「补充规则 / 方向」不再追加
# —— 宁可少显示次要信息，也不能把状态栏挤进下面 y=152 的「桌面: …」。
const PLAYER_STATUS_PER_LINE := 4

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


# 模块实例在这里创建（早于 _ready，也早于子节点的 _ready —— 子节点先就绪，
# 万一有人在子节点里回调本节点的方法，转发目标必须已存在）。
func _init() -> void:
	ui_theme = UIThemeScript.new(self)
	ui_touch = TouchMetricsScript.new(self)
	ui_toast = ToastScript.new(self)
	ui_router = PageRouterScript.new(self)
	ui_motion = CardMotionScript.new(self)
	ui_hand = HandViewScript.new(self)
	ui_tool = ToolRowScript.new(self)
	ui_table = TableAreaScript.new(self)
	ui_side = SidePanelsScript.new(self)
	ui_action = ActionPanelScript.new(self)
	ui_hint = HintFlowScript.new(self)
	ui_flow = GameFlowScript.new(self)
	ui_page = PageChromeScript.new(self)


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
	# 联机诊断：只在显式 --net-trace 时开，默认零输出
	_net_trace = net_trace_requested(touch_profile_args())
	if _net_trace:
		print("[net] 追踪已开启（--net-trace）：每笔权威事件打一行，可用 adb logcat -s godot:V 收")
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
	ui_router._ensure_layers()


# 开始页控件查找：P6 起人数框 / 规则开关 / 补充规则入口都挂在 SettingsCard 卡片内，
# 不再是 StartPage 的直接子节点 → 统一用递归查找，避免又退回「按路径取不到 = 静默失效」
func _start_child(node_name: String) -> Node:
	if start_page == null or not is_instance_valid(start_page):
		return null
	return start_page.find_child(node_name, true, false)


func _make_layer(layer_name: String, z: int) -> Control:
	return ui_router._make_layer(layer_name, z)


# -------- 视觉规范工厂：卡牌 / 面板 / 按钮 / toast 的唯一样式来源 --------
# kind: card / card_selected / card_hover / card_hover_selected
#       mini_card / mini_card_hover / button / tab_on / tab_off
#       toast_warning / toast_info
func _make_panel_style(kind: String) -> StyleBoxFlat:
	return ui_theme._make_panel_style(kind)


# 共享样式模板（只读，Slice 2b）：高频重绘点用它，避免「每次重建都新分配一批 StyleBox」
func _panel_style_template(kind: String) -> StyleBoxFlat:
	return ui_theme._panel_style_template(kind)


# 统一填充底色 / 描边 / 圆角 / 阴影，避免各调用点各写一套数值
func _style_base(sb: StyleBoxFlat, bg: Color, border: Color, width: int, radius: int, shadow: bool) -> void:
	ui_theme._style_base(sb, bg, border, width, radius, shadow)


# 取层时必须保证已创建（脚本内各处直接调用，避免 _ready 之外的入口拿到 null）
func _layer(kind: int) -> Control:
	return ui_router._layer(kind)


# ============================================================
# 五、页面切换
# ============================================================
# -------- 页面淡入基础设施（P3） --------
# 根节点下的常驻同色底：页面淡入时 alpha 降到 0 露出的仍是 #E6F0FA，
# 因此不会闪出窗口默认清屏色（深灰）。挂在根节点而非 GamePage，
# 因为 GamePage 自身在切换时会被隐藏。
func _ensure_page_backdrop() -> void:
	ui_router._ensure_page_backdrop()


func _all_pages() -> Array:
	return ui_router._all_pages()


# 目标页淡入；其余页 alpha 复位（避免「淡入中途被切走」留下半透明页）
func _fade_in_page(page) -> void:
	ui_router._fade_in_page(page)


func _show_start_page() -> void:
	ui_router._show_start_page()

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
# 房间页（P11-C1-c Step 4，决策 D12~D17 见 MULTIPLAYER_TASKS.md）
#   · 座位数 3~8，建房时由房主选（默认 4），创建后固定（D17）：
#     规则层本来就吃 3~8（GameManager.MIN_PLAYERS / MAX_PLAYERS），
#     联机层只是过去把 start_host / start_game 硬 clamp 到 4。
#   · 大厅没有 ready 握手：客人的 MSG_READY 是「快照重建完成」，开局后才发。
#     所以开局闸门是「在线人类数 + AI 数 ∈ [3, capacity]」，不是 all_seats_ready()。
# ------------------------------------------------------------
const ROOM_MIN_SEATS := 3                 # = GameManager.MIN_PLAYERS
const ROOM_MAX_SEATS := 8                 # = NetSession.MAX_PLAYERS / GameManager.MAX_PLAYERS
const ROOM_DEFAULT_SEATS := 4             # 默认仍是 4：老玩家的牌桌手感不变
const ROOM_DEFAULT_PORT := 47800          # = ENetTransport.DEFAULT_PORT
const ROOM_CONNECT_TIMEOUT_S := 8.0       # create_client 是异步的，连不上没有任何回调
enum RoomMode { IDLE, HOSTING, CONNECTING, JOINED }
var _room_page: Control = null
var _room_mode: int = RoomMode.IDLE
var _room_connect_wait: float = 0.0
var _room_join_target: String = ""        # 只用于「连不上 xxx」的提示文案
var _room_closing: bool = false           # 主动关会话时的重入闸（close 会同步发 session_closed）
# 联机终止的原因（房主收房 / 失联 / 状态分叉）：钉在界面上直到回开始页。
# 为什么单独存一份（D20）：toast 2.5 秒就消失，而 card_info 每帧都被回合提示覆盖，
# 房主退出后客人只会看到「等待 X 行动…」，看起来就是卡死。
var _net_over_notice: String = ""
var _room_ai_sync: bool = false           # 往 AI 微调框里写值时的重入闸（会触发 value_changed）
var _room_seat_cards: Array = []          # 最多 8 张座位卡（Panel），按容量显隐
var _room_seat_nos: Array = []            # 座位卡上的「座位 N」Label
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
var _room_seat_spin: SpinBox = null        # 座位数 3~8（建房前可调，进房后锁定）


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


# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _page_bg_into(parent: Control, bg_name: String, band_name: String) -> void:
	ui_page._page_bg_into(parent, bg_name, band_name)



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


# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _start_label(text: String, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	return ui_page._start_label(text, fs, col, align)



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


# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _page_primary_btn(text: String, cb: Callable, sz: Vector2, node_name: String = "", fs: int = 20) -> Button:
	return ui_page._page_primary_btn(text, cb, sz, node_name, fs)

func _page_secondary_btn(text: String, cb: Callable, sz: Vector2, node_name: String = "", fs: int = 19) -> Button:
	return ui_page._page_secondary_btn(text, cb, sz, node_name, fs)

func _page_ghost_btn(text: String, cb: Callable, sz: Vector2, node_name: String = "", fs: int = 16) -> Button:
	return ui_page._page_ghost_btn(text, cb, sz, node_name, fs)



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


# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _animate_page_intro(page: Control, order: Array) -> void:
	ui_page._animate_page_intro(page, order)

func _page_deco_float(page: Control) -> void:
	ui_page._page_deco_float(page)



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
# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _page_gradient_band(page: Control) -> void:
	ui_page._page_gradient_band(page)

func _page_watermarks(page: Control, specs: Array) -> void:
	ui_page._page_watermarks(page, specs)

func _page_deco_cards(page: Control, cards: Array) -> void:
	ui_page._page_deco_cards(page, cards)

func _page_backdrop(page: Control, bg_name: String, marks: Array, cards: Array) -> void:
	ui_page._page_backdrop(page, bg_name, marks, cards)



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

# -------- 以下方法已搬进 scripts/game/GameFlow.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _on_start_game() -> void:
	ui_flow._on_start_game()

func _on_start_tutorial(level: int) -> void:
	ui_flow._on_start_tutorial(level)

func _connect_node(btn, cb: Callable) -> void:
	ui_flow._connect_node(btn, cb)

func _on_exit_program() -> void:
	ui_flow._on_exit_program()

func _on_quit_game() -> void:
	ui_flow._on_quit_game()

func _reset_quit_confirm() -> void:
	ui_flow._reset_quit_confirm()

func _show_info_simple(text: String) -> void:
	ui_flow._show_info_simple(text)

func _apply_start_page_rules(gm) -> void:
	ui_flow._apply_start_page_rules(gm)

func _init_game(total: int = 4, ai: int = 3) -> void:
	ui_flow._init_game(total, ai)

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

# -------- 以下方法已搬进 scripts/ui/TableArea.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _build_status_bar() -> void:
	ui_table._build_status_bar()


# -------- 以下方法已搬进 scripts/ui/TableArea.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _update_status_bar() -> void:
	ui_table._update_status_bar()


# -------- 以下方法已搬进 scripts/ui/TableArea.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _format_player_status() -> String:
	return ui_table._format_player_status()


var table_card_buttons: Array = []

# -------- 以下方法已搬进 scripts/ui/TableArea.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _update_table_label() -> void:
	ui_table._update_table_label()


# -------- 以下方法已搬进 scripts/ui/TableArea.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _table_type_color(pat: int) -> Color:
	return ui_table._table_type_color(pat)

func _set_table_text(txt: String, pat: int) -> void:
	ui_table._set_table_text(txt, pat)

func _tween_table_label_reveal() -> void:
	ui_table._tween_table_label_reveal()


# -------- 以下方法已搬进 scripts/ui/CardMotion.gd（Slice 2a 纯搬运，这里只留同名转发） --------
func _animate_mini_card_in(btn: Control, i: int) -> void:
	ui_motion._animate_mini_card_in(btn, i)

func _make_fly_ghost(btn: Control) -> Control:
	return ui_motion._make_fly_ghost(btn)

func _bezier2(a: Vector2, c: Vector2, b: Vector2, p: float) -> Vector2:
	return ui_motion._bezier2(a, c, b, p)

func _place_ghost(ghost: Control, to_pos: Vector2) -> void:
	ui_motion._place_ghost(ghost, to_pos)

func _fly_ghost(ghost: Control, to_pos: Vector2, to_scale: float, ms: int, delay: float, arc: float = 0.0) -> void:
	ui_motion._fly_ghost(ghost, to_pos, to_scale, ms, delay, arc)

func _capture_play_fly_in() -> Array:
	return ui_motion._capture_play_fly_in()

func _replay_play_fly_in(snaps: Array) -> void:
	ui_motion._replay_play_fly_in(snaps)

func _fly_discarded_card() -> void:
	ui_motion._fly_discarded_card()

func _animate_new_hand_cards() -> void:
	ui_motion._animate_new_hand_cards()

func _snap_card_position(btn: Control, to_pos: Vector2) -> void:
	ui_motion._snap_card_position(btn, to_pos)



# -------- 以下方法已搬进 scripts/ui/SidePanels.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _build_mini_card_button(card, custom_valence = null) -> Button:
	return ui_side._build_mini_card_button(card, custom_valence)

func _build_hand_reorder_button() -> void:
	ui_side._build_hand_reorder_button()

func _update_hand_reorder_button() -> void:
	ui_side._update_hand_reorder_button()

func _on_hand_reorder() -> void:
	ui_side._on_hand_reorder()


# -------- 以下方法已搬进 scripts/ui/SidePanels.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _ensure_log_panel() -> void:
	ui_side._ensure_log_panel()

func _on_log_title_pressed() -> void:
	ui_side._on_log_title_pressed()

func _layout_log_panel() -> void:
	ui_side._layout_log_panel()

func _log_title_text() -> String:
	return ui_side._log_title_text()

func _log_line_h() -> float:
	return ui_side._log_line_h()

func _set_log_visible(on: bool) -> void:
	ui_side._set_log_visible(on)

func _update_log_label() -> void:
	ui_side._update_log_label()

func _clear_net_over_notice() -> void:
	ui_side._clear_net_over_notice()



# -------- 以下方法已搬进 scripts/ui/SidePanels.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _update_card_info_label() -> void:
	ui_side._update_card_info_label()

func _update_deck_count() -> void:
	ui_side._update_deck_count()

func _update_tutorial_label() -> void:
	ui_side._update_tutorial_label()



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


# -------- 以下方法已搬进 scripts/ui/ActionPanel.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _update_action_panel() -> void:
	ui_action._update_action_panel()

func _action_btn_h() -> float:
	return ui_action._action_btn_h()

func _fit_action_panel() -> void:
	ui_action._fit_action_panel()

func _action_panel_h() -> float:
	return ui_action._action_panel_h()

func _action_panel_rows() -> int:
	return ui_action._action_panel_rows()

func _action_panel_hl_rect() -> Rect2:
	return ui_action._action_panel_hl_rect()

func _right_panel_hl_rect() -> Rect2:
	return ui_action._right_panel_hl_rect()

func _mkb(text: String, cb: Callable, dis: bool) -> Button:
	return ui_action._mkb(text, cb, dis)

func _attach_btn_motion(b: Button) -> void:
	ui_action._attach_btn_motion(b)

func _tween_button_scale(btn: Button, target: float) -> void:
	ui_action._tween_button_scale(btn, target)

func _on_button_hover_scale(btn: Button, entered: bool) -> void:
	ui_action._on_button_hover_scale(btn, entered)

func _on_button_press_scale(btn: Button, down: bool) -> void:
	ui_action._on_button_press_scale(btn, down)

func _touch_fs(base: int, bonus: int = TOUCH_FS_BONUS) -> int:
	return ui_touch._touch_fs(base, bonus)


func _touch_btn_h(base_h: int) -> int:
	return ui_touch._touch_btn_h(base_h)


func _tool_btn_h() -> float:
	return ui_touch._tool_btn_h()


func _tool_btn_top() -> float:
	return ui_touch._tool_btn_top()


func _tool_btn_gap() -> float:
	return ui_touch._tool_btn_gap()


# 工具行左边界：右边界固定 820，间距变宽 → 左边界自动左移（教程高亮框跟着走）
func _tool_row_left() -> float:
	return ui_touch._tool_row_left()


func _reorder_btn_left() -> float:
	return ui_touch._reorder_btn_left()


# 教程第零关「按钮区」高亮框：工具行 bbox 外扩 TOOL_ROW_HL_PAD
# （DESKTOP 时与 TOOL_ROW_HL_POS / TOOL_ROW_HL_SIZE 逐值相等，见 verify_touch_ui）
func _tool_row_hl_rect() -> Rect2:
	return ui_touch._tool_row_hl_rect()


# 起拖阈值：越过它就开始跟手（触屏 10px ≈7dp，桌面 6px）
func _drag_arm_threshold() -> float:
	return ui_touch._drag_arm_threshold()


# 确认阈值：鼠标 6px 就够，手指需要 24px 才算有意重排（<24px 视为点选，见 _finish_drag）
func _drag_threshold() -> float:
	return ui_touch._drag_threshold()


# 选中牌静止时相对 base_pos 的上浮量：触屏常驻上浮，桌面 0（悬停已足够表达）
func _selected_lift() -> float:
	return ui_touch._selected_lift()


# -------- 页面级触控放大：开始页 / 帮助页 / 结算页 / 教学页的按钮统一过一遍 --------
# 这些页面的按钮是代码生成的、尺寸由各调用点手写（220×56 / 150×38 / 270×32 ...），
# 逐个改调用点既啰嗦又容易漏；改为构建完成后统一兜底：
#   · 渲染高度 < TOUCH_BTN_MIN_H 的，拉到 48（位置按中心不变微调，不跳行）
#   · 字号 +TOUCH_FS_BONUS
# 容器内的按钮（PanelContainer / VBox）position 会被容器覆盖，改为靠 custom_minimum_size 生效。
func _apply_touch_sizing(root: Node) -> void:
	ui_touch._apply_touch_sizing(root)


# 还原：把 _apply_touch_sizing 改过的按钮逐颗恢复（size / 最小高 / 坐标 / 字号）。
# 为什么要还原而不是重建页面：这些按钮是代码生成的，位置写在各调用点，
# 重建一遍等于重跑 _setup_pages（会重连信号、重播入场动画），关个开关不该这么重。
func _revert_touch_sizing(root: Node) -> void:
	ui_touch._revert_touch_sizing(root)


# ============================================================
# 九之二、触屏档运行时开关（P14-D）
# ============================================================
# 为什么需要界面开关：--touch-ui 只在启动时生效，真机上玩家想「把按钮调大」只能改系统设置；
# 桌面上也总得开终端加参数。开始页「触屏界面」开关 = set_touch_ui()，
# 与命令行 / 平台判定共用同一个 _touch_ui 字段，几何取值函数自然跟着变。
func is_touch_ui() -> bool:
	return ui_touch.is_touch_ui()


func set_touch_ui(on: bool) -> void:
	ui_touch.set_touch_ui(on)


# 把当前档位刷到所有已构建的页面 + 游戏页（可逆：关掉时逐颗还原，不重建页面）
func _apply_touch_profile_everywhere() -> void:
	ui_touch._apply_touch_profile_everywhere()


func _reposition_reorder_button() -> void:
	ui_touch._reposition_reorder_button()


# 开始页开关的文字 / 按下态跟随 _touch_ui（命令行强制开启时也显示「开」）
func _sync_touch_toggle() -> void:
	ui_touch._sync_touch_toggle()


func _on_touch_ui_toggled(pressed: bool) -> void:
	ui_touch._on_touch_ui_toggled(pressed)


func _collect_buttons(root: Node) -> Array:
	return ui_touch._collect_buttons(root)


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


# -------- 以下方法已搬进 scripts/ui/ToolRow.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _style_game_tool_buttons() -> void:
	ui_tool._style_game_tool_buttons()

func _style_tool_btn(b: Button, is_toggle: bool, danger: bool) -> void:
	ui_tool._style_tool_btn(b, is_toggle, danger)


# -------- 以下方法已搬进 scripts/game/HintFlow.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _on_hint_toggled(pressed: bool) -> void:
	ui_hint._on_hint_toggled(pressed)

func _apply_hint() -> void:
	ui_hint._apply_hint()

func _clear_hint() -> void:
	ui_hint._clear_hint()


# ============================================================
# 十一、元素着色规则
# ============================================================
func _get_card_color(card) -> Color:
	return ui_theme._get_card_color(card)


# -------- 以下方法已搬进 scripts/ui/HandView.gd（Slice 2a 纯搬运，这里只留同名转发） --------
func _update_hand_buttons() -> void:
	ui_hand._update_hand_buttons()

func _human_players() -> Array:
	return ui_hand._human_players()

func _hand_view_player(actor = null):
	return ui_hand._hand_view_player(actor)

func _is_hotseat() -> bool:
	return ui_hand._is_hotseat()

func _hotseat_handoff_pending() -> bool:
	return ui_hand._hotseat_handoff_pending()

func _on_hotseat_handoff_confirmed() -> void:
	ui_hand._on_hotseat_handoff_confirmed()

func _render_hotseat_handoff(actor) -> void:
	ui_hand._render_hotseat_handoff(actor)

func _selected_cards(cp) -> Array:
	return ui_hand._selected_cards(cp)

func _remap_selection(cp, cards: Array) -> void:
	ui_hand._remap_selection(cp, cards)

func _hand_order_sig(cp) -> String:
	return ui_hand._hand_order_sig(cp)


# -------- 以下方法已搬进 scripts/ui/HandView.gd（Slice 2a 纯搬运，这里只留同名转发） --------
func _layout_hand_cards() -> void:
	ui_hand._layout_hand_cards()

func _apply_card_compact(btn: Button, compact: bool) -> void:
	ui_hand._apply_card_compact(btn, compact)

func _can_reorder_hand() -> bool:
	return ui_hand._can_reorder_hand()

func _update_hand_drag() -> void:
	ui_hand._update_hand_drag()

func _begin_drag(idx: int) -> void:
	ui_hand._begin_drag(idx)

func _make_drag_ghost(src: Button, alpha: float = DRAG_GHOST_ALPHA) -> Control:
	return ui_hand._make_drag_ghost(src, alpha)

func _make_drag_line() -> ColorRect:
	return ui_hand._make_drag_line()

func _update_drag_follow() -> void:
	ui_hand._update_drag_follow()

func _insert_slot_at(x: float) -> int:
	return ui_hand._insert_slot_at(x)

func _slot_x(slot: int) -> float:
	return ui_hand._slot_x(slot)

func _hand_base_y() -> float:
	return ui_hand._hand_base_y()

func _finish_drag(drop_pos: Vector2 = Vector2.INF) -> void:
	ui_hand._finish_drag(drop_pos)

func _clear_drag_suppress() -> void:
	ui_hand._clear_drag_suppress()

func _reset_drag_visuals() -> void:
	ui_hand._reset_drag_visuals()

func _cancel_drag() -> void:
	ui_hand._cancel_drag()


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


# -------- 以下方法已搬进 scripts/ui/HandView.gd（Slice 2a 纯搬运，这里只留同名转发） --------
func _card_hover_rect(btn: Button) -> Rect2:
	return ui_hand._card_hover_rect(btn)

func _card_raised_rect(btn: Button) -> Rect2:
	return ui_hand._card_raised_rect(btn)

func _card_core_rect(idx: int) -> Rect2:
	return ui_hand._card_core_rect(idx)

func _hover_hit_index(mp: Vector2) -> int:
	return ui_hand._hover_hit_index(mp)

func _hit_card_at(mp: Vector2) -> int:
	return ui_hand._hit_card_at(mp)

func _hover_hit_index_padded(mp: Vector2, pad: float) -> int:
	return ui_hand._hover_hit_index_padded(mp, pad)

func _set_hover_index(idx: int) -> void:
	ui_hand._set_hover_index(idx)

func _update_hand_hover() -> void:
	ui_hand._update_hand_hover()

func _hover_keep_above(gmp: Vector2, gr: Rect2) -> bool:
	return ui_hand._hover_keep_above(gmp, gr)

func _update_hover_at(mp: Vector2) -> void:
	ui_hand._update_hover_at(mp)

func _on_hand_card_hover(btn: Button, hovered: bool) -> void:
	ui_hand._on_hand_card_hover(btn, hovered)

func _apply_hover(btn: Button, hovered: bool) -> void:
	ui_hand._apply_hover(btn, hovered)

func _tween_card_y(btn: Button, target_y: float) -> void:
	ui_hand._tween_card_y(btn, target_y)

func _kill_hover_tween(btn: Button) -> void:
	ui_hand._kill_hover_tween(btn)

func _tween_card_scale(btn: Button, target: float) -> void:
	ui_hand._tween_card_scale(btn, target)

func _kill_scale_tween(btn: Button) -> void:
	ui_hand._kill_scale_tween(btn)

func _show_card_detail(btn: Button) -> void:
	ui_hand._show_card_detail(btn)

func _restore_card_info() -> void:
	ui_hand._restore_card_info()

func _card_summary_text(card) -> String:
	return ui_hand._card_summary_text(card)

func _valence_token(v: int) -> String:
	return ui_hand._valence_token(v)

func _format_valence_full(vals: Array) -> String:
	return ui_hand._format_valence_full(vals)

func _format_valence_tight(vals: Array) -> String:
	return ui_hand._format_valence_tight(vals)

func _format_valence_pair(vals: Array) -> String:
	return ui_hand._format_valence_pair(vals)

func _sorted_valences(vals: Array) -> Array:
	return ui_hand._sorted_valences(vals)

func _fit_card_valence(lbl: Label, card, max_w: float, base_fs: int) -> void:
	ui_hand._fit_card_valence(lbl, card, max_w, base_fs)

func _sync_valence_chip(lbl: Label) -> void:
	ui_hand._sync_valence_chip(lbl)

func _valence_fits(font: Font, txt: String, fs: int, max_w: float) -> bool:
	return ui_hand._valence_fits(font, txt, fs, max_w)

func _valence_width(font: Font, txt: String, fs: int) -> float:
	return ui_hand._valence_width(font, txt, fs)

func _restore_hover_after_rebuild() -> void:
	ui_hand._restore_hover_after_rebuild()

func _build_card_button(card, idx: int) -> Button:
	return ui_hand._build_card_button(card, idx)

func _update_valence_buttons() -> void:
	ui_hand._update_valence_buttons()

func _sel_cards() -> Array:
	return ui_hand._sel_cards()

func _selection_charge_sum() -> int:
	return ui_hand._selection_charge_sum()

func _uniform_valence_for_selection() -> Dictionary:
	return ui_hand._uniform_valence_for_selection()

func _mixed_valence_for_selection() -> Dictionary:
	return ui_hand._mixed_valence_for_selection()

func _mixed_valence_text(cv: Dictionary) -> String:
	return ui_hand._mixed_valence_text(cv)

func _valence_text_of(sym: String, v) -> String:
	return ui_hand._valence_text_of(sym, v)

func _on_card_pressed() -> void:
	ui_hand._on_card_pressed()

func _on_card_clicked(index: int) -> void:
	ui_hand._on_card_clicked(index)

func _apply_card_selection(index: int) -> void:
	ui_hand._apply_card_selection(index)

# 选中 / 取消选中后的单张刷新（Slice 2b：不再整排重建）
func _refresh_card_selection_visual(idx: int) -> void:
	ui_hand._refresh_card_selection_visual(idx)

# 「直接出牌 ⚡」= 先出后验（P14-C）：玩家只负责选牌，牌型交给引擎按固定优先级挑。
# 与旧的「出牌(选牌型)」并存 —— 老玩家 / 教程仍走三步，新玩家一键出。
# 失败时不做界面预判，直接把引擎写的 last_reject_reason 拼进提示（P14-B 已修好这条链路）。
# -------- 以下方法已搬进 scripts/game/GameFlow.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _on_auto_play() -> void:
	ui_flow._on_auto_play()

func _on_step_next() -> void:
	ui_flow._on_step_next()

func _on_element() -> void:
	ui_flow._on_element()

func _on_sequence() -> void:
	ui_flow._on_sequence()

func _on_clan_bomb() -> void:
	ui_flow._on_clan_bomb()

# -------- 以下方法已搬进 scripts/ui/ActionPanel.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _on_choose_compound() -> void:
	ui_action._on_choose_compound()

func _on_choose_organic() -> void:
	ui_action._on_choose_organic()

func _on_select_valence(symbol: String, valence: int) -> void:
	ui_action._on_select_valence(symbol, valence)

func _on_confirm_compound() -> void:
	ui_action._on_confirm_compound()

func _on_reset_valence() -> void:
	ui_action._on_reset_valence()


# 混合价态一键出牌（v4）：Fe₃O₄ 这类「同元素多价」的组合走这条路径。
# cv 由 _mixed_valence_for_selection() 求出并校验过配平，这里只负责收集卡牌并交给引擎。
# -------- 以下方法已搬进 scripts/game/GameFlow.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _on_confirm_mixed_valence(cv: Dictionary) -> void:
	ui_flow._on_confirm_mixed_valence(cv)

func _on_confirm_auto_valence(cv: Dictionary) -> void:
	ui_flow._on_confirm_auto_valence(cv)

func _play_selected_compound(cv: Dictionary) -> void:
	ui_flow._play_selected_compound(cv)

func _on_back() -> void:
	ui_flow._on_back()

func _on_pass() -> void:
	ui_flow._on_pass()

func _on_discard_mode() -> void:
	ui_flow._on_discard_mode()

func _handle_result(result: int) -> void:
	ui_flow._handle_result(result)

func _show_sequence_constraint_dialog() -> void:
	ui_flow._show_sequence_constraint_dialog()

func _step_reset() -> void:
	ui_flow._step_reset()

func _show_info(text: String) -> void:
	ui_toast._show_info(text)


# 右栏警告 toast（黄底橙红边，2.5 秒自动消失）
# 位置固定在右栏上部空白格，不再压在手牌 / 操作区 / 卡牌信息之上。
# 单例复用：连续报错只更新文本并重置计时，不叠框、也不会被上一次的计时器提前熄灭。
func _show_center_warning(text: String, sticky: bool = false) -> void:
	ui_toast._show_center_warning(text, sticky)


func _ensure_warning_toast() -> void:
	ui_toast._ensure_warning_toast()


# 开局 / 进教程时清掉上一局残留的警告；seq 自增让未到期的计时器失效
func _hide_warning_toast() -> void:
	ui_toast._hide_warning_toast()

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
# -------- 以下方法已搬进 scripts/game/GameFlow.gd（Slice 3 纯搬运，这里只留同名转发） --------
func _ai_auto_play() -> void:
	ui_flow._ai_auto_play()

func _is_halogen_only(symbols: Array) -> bool:
	return ui_flow._is_halogen_only(symbols)

func _gcd(a: int, b: int) -> int:
	return ui_flow._gcd(a, b)

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
	# --net-trace：每个新装配的会话都打开追踪（重建 / 重连后的新会话也不会漏）
	if session != null and _net_trace:
		session.enable_trace(true)
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
	# 牌桌上房主退出 / 失联：把原因钉在界面上（D20）。只弹 toast 的话 2.5 秒后
	# 就只剩「等待 X 行动…」，看起来像卡死 —— 这正是真机反馈的那个问题。
	_net_over_notice = msg
	_show_info(msg)
	_show_center_warning(msg, true)
	# 单机 / 房间页关着：只有真的有一局在打才刷新（0 玩家时刷 = 读空局面）
	if game_manager != null and game_manager.get_player_count() > 0:
		_refresh_ui()


func _online_on_desync(local_hash: int, host_hash: int) -> void:
	# 分叉后不再推进，弹窗留着只会让人以为还能选
	_hide_sequence_overlay()
	_net_over_notice = "状态分叉（本端 %d / 主机 %d），已停止推进" % [int(local_hash), int(host_hash)]
	_show_info(_net_over_notice)
	# 终局提示必须常驻：toast 2.5 秒就没，牌桌上看不出「这局已经停了」（D20）
	_show_center_warning(_net_over_notice, true)
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
	if _net_ai_wait < _net_ai_delay():
		return
	_net_ai_wait = 0.0
	# host_step_ai 内部走 host_act_for_seat → _host_apply → state_applied，
	# 界面刷新由 _online_on_state_applied 负责，这里不再重复刷
	net_session.host_step_ai(1)


# AI 节流按人数缩短（D17）：8 座位最多 7 个 AI，还按 1.2s 走一轮要 8 秒多，
# 真人对局里那是纯等待。3~4 个 AI 保持接近单机手感，5 个以上再压一档。
func _net_ai_delay() -> float:
	var ai := int(net_session.ai_count()) if net_session != null else 0
	if ai >= 5:
		return NET_AI_DELAY_S * 0.5          # 7 个 AI → 0.6s/手，一轮约 4 秒
	if ai >= 3:
		return NET_AI_DELAY_S * 0.66         # 3~4 个 AI → 0.8s/手
	return NET_AI_DELAY_S


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
	_clear_net_over_notice()       # 新一局开局：上一局的终止提示作废
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
		"局域网 / Tailscale 直连 · 3~8 人（房主可调座位数） · 房号仅用于辨认，客人需填房主 IP",
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

	# D17：座位数建房前由房主定（3~8，默认 4），进房后锁定（客人只读显示房主的设置）
	page.add_child(_room_label("RoomSeatLabel", "座位数", Vector2(340, 592), Vector2(110, 34),
		START_FS_LABEL, START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	_room_seat_spin = _start_make_spin(ROOM_MIN_SEATS, ROOM_MAX_SEATS, ROOM_DEFAULT_SEATS,
		"RoomSeatSpin")
	_room_seat_spin.position = Vector2(456, 590)
	_room_seat_spin.size = Vector2(150, 38)
	_room_seat_spin.tooltip_text = "本房间总座位数（3~8）：创建后固定，人类坐满后空位由 AI 补"
	_room_seat_spin.value_changed.connect(_on_room_seat_changed)
	page.add_child(_room_seat_spin)

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



# -------- 座位表：一次建 8 张卡，按「当前容量」显隐 + 重排（D17）--------
# 为什么先全建再显隐：容量只在建房前变（3~8），重建节点会让测试按名字取控件
# 变得时序敏感；8 张卡一次性建好，刷新时只改 visible / 位置 / 字号最稳。
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
	_room_seat_nos.clear()
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

		var no := _room_label("RoomSeatNo_%d" % i, "座位 %d" % (i + 1),
			Vector2(14, 8), Vector2(212, 18), START_FS_META, START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(no)
		var nm := _room_label("RoomSeatName_%d" % i, "空位",
			Vector2(14, 30), Vector2(212, 30), 20, START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(nm)
		var stt := _room_label("RoomSeatState_%d" % i, "—",
			Vector2(14, 72), Vector2(212, 20), START_FS_META, START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(stt)
		_room_seat_cards.append(sc)
		_room_seat_nos.append(no)
		_room_seat_names.append(nm)
		_room_seat_states.append(stt)
	_room_layout_seats(ROOM_DEFAULT_SEATS)


# 座位卡按容量重排：
#   3~4 张沿用老位置（24 + i*256，240×122）—— 牌桌手感 / 老截图 / 老测试都不变
#   5~8 张挤成一行（等分 1012px，间距 8）：n=8 时每张 119px，昵称 16px + 裁切
func _room_layout_seats(capacity: int) -> void:
	var n := clampi(int(capacity), ROOM_MIN_SEATS, ROOM_MAX_SEATS)
	var tight := n > 4
	var gap := 8.0 if tight else 16.0
	var w := 240.0
	if tight:
		w = floorf((1012.0 - float(n - 1) * gap) / float(n))
	var pad := 8.0 if tight else 14.0
	for i in range(_room_seat_cards.size()):
		var card = _room_seat_cards[i]
		if not (card is Control) or not is_instance_valid(card):
			continue
		card.visible = i < n
		if not card.visible:
			continue
		var x := 24.0 + float(i) * (w + gap) if tight else float(24 + i * 256)
		card.position = Vector2(x, 38.0)
		card.size = Vector2(w, 122.0)
		if i < _room_seat_nos.size():
			var no = _room_seat_nos[i]
			no.position = Vector2(pad, 8)
			no.size = Vector2(w - pad * 2.0, 18)
		if i < _room_seat_names.size():
			var nm = _room_seat_names[i]
			nm.position = Vector2(pad, 30)
			nm.size = Vector2(w - pad * 2.0, 30)
			nm.clip_text = true
			nm.add_theme_font_size_override("font_size", 16 if tight else 20)
		if i < _room_seat_states.size():
			var stt = _room_seat_states[i]
			stt.position = Vector2(pad, 72)
			stt.size = Vector2(w - pad * 2.0, 20)
			stt.clip_text = true


# -------- 整页刷新：座位表 / 房号 / 提示 / 4 颗按钮的可用态 --------
func _room_refresh() -> void:
	if _room_page == null or not is_instance_valid(_room_page):
		return
	var online := _room_online_humans()
	var offline := _room_offline_humans()
	var seat_total := int(net_session.seat_count()) if net_session != null else 0
	var my_seat := int(net_session.my_seat) if net_session != null else -1
	var capacity := _room_seat_capacity()
	var tight := capacity > 4
	_room_layout_seats(capacity)

	# AI 上限 = 剩下的空座位（总座位 = 本房间容量）：真人坐满就一个 AI 也加不了
	# D19：在房里时 AI 数由房主定（NetSession.lobby_ai 广播同步），客人只读同一份值
	if _room_ai_spin != null:
		var ai_cap := maxi(0, capacity - online)
		var want := mini(int(_room_ai_spin.value), ai_cap)
		var follows_host: bool = net_session != null and net_session.has_method("set_lobby_ai")
		if follows_host:
			want = mini(int(net_session.lobby_ai), ai_cap)
		_room_ai_sync = true                  # 写值会触发 value_changed，先挡住回推
		_room_ai_spin.max_value = ai_cap
		if int(_room_ai_spin.value) != want:
			_room_ai_spin.value = want        # Range 会把超限值压回 max
		_room_ai_sync = false
		# 大厅 AI 数只有房主能定：客人能点却改了不生效，比根本点不动更误导
		_room_ai_spin.editable = not follows_host or net_session.is_host()
	var ai := _room_ai_value()
	var planned := online + ai

	for i in range(capacity):
		var name_text := "空位"
		var state_text := "—"
		var taken := false
		if i < seat_total:
			taken = true
			name_text = String(net_session.seat_name(i))
			if name_text == "":
				name_text = "玩家 %d" % (i + 1)
			if not net_session.seat_is_online(i):
				state_text = "掉线·保留" if tight else "掉线中 · 座位保留"
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
	if _room_seat_spin != null:
		_room_seat_spin.value = capacity
		_room_seat_spin.editable = not joined   # 进房后锁定：容量在建房时就定了
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
			_room_start_btn.text = "开始对局 · %d/%d 座位" % [mini(planned, capacity), capacity]
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


# -------- 开局闸门（D12 / D15 / D17）--------
# 纯函数：只吃几个数，不碰会话 / 控件，测试可以逐格喂边界。
# capacity = 本房间座位数（3~8，默认 4 保持老行为）
# 返回 "" = 可以开局；其余 = 直接显示给用户的原因
func _room_start_block_reason(online_humans: int, ai_count: int, is_host: bool,
		room_state: int, offline_seats: int = 0,
		capacity: int = ROOM_DEFAULT_SEATS) -> String:
	if not is_host:
		return "等待房主开始"
	if room_state == NetSessionScript.State.PLAYING:
		return "对局已开始"
	if room_state != NetSessionScript.State.LOBBY:
		return "房间未就绪"
	var cap := clampi(int(capacity), ROOM_MIN_SEATS, ROOM_MAX_SEATS)
	var total := int(online_humans) + int(ai_count)
	if total < ROOM_MIN_SEATS:
		return "座位不足：至少 %d 个（当前 %d）" % [ROOM_MIN_SEATS, total]
	if total > cap:
		return "座位超限：最多 %d 个（当前 %d）" % [cap, total]
	if int(offline_seats) > 0:
		return "有玩家掉线，等重连后再开局"
	return ""


# 会话 → 闸门参数。state 用 is_playing() 反推，不去读会话内部字段
# （假会话只需要实现 is_host / is_playing / seat_count / seat_is_online / seat_capacity）
func _room_start_disabled_reason() -> String:
	if net_session == null:
		return "还没加入房间"
	var st := NetSessionScript.State.LOBBY
	if net_session.is_playing():
		st = NetSessionScript.State.PLAYING
	return _room_start_block_reason(_room_online_humans(), _room_ai_value(),
		net_session.is_host(), st, _room_offline_humans(), _room_seat_capacity())


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
	_clear_net_over_notice()       # 离开房间 = 终止提示作废（房间页有自己的常驻提示行）
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
	var capacity := _room_seat_capacity()
	var nm := "房主"
	if _room_host_name_edit != null and _room_host_name_edit.text.strip_edges() != "":
		nm = _room_host_name_edit.text.strip_edges()
	# 大厅也要一份 GameManager：补充规则要在开局前定下来，随 game_start 的 config 下发
	game_manager = GameManagerScript.new()
	_apply_start_page_rules(game_manager)
	var s = NetSessionScript.new()
	s.setup(game_manager, ENetTransportScript.new())
	s.max_players = capacity
	# 观战者 UI 还没做（见 MULTIPLAYER_TASKS §5）：满员直接拒，别给个看不见的观战位
	s.allow_watchers = false
	_room_bind_session(s)
	if s.start_host(port, capacity, nm) != 0:
		_room_teardown()
		_room_hint("端口 %d 建不起来（多半被占用）：换一个端口再试" % port)
		return
	_room_mode = RoomMode.HOSTING
	_room_hint("房间已创建（%d 座位）：把本机 IP + 端口 %d 告诉客人" % [capacity, port])
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
	# 客人还不知道房主的容量：先填默认值，收 welcome 时会被 max_players 覆盖成房主那档
	s.max_players = ROOM_DEFAULT_SEATS
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


# 房主改 AI 数：先落到会话（clamp + 广播 MSG_LOBBY），再由 room_changed 回来刷新界面。
# 客人这份是只读的（_room_refresh 里 editable = false），就算走到这里也会被 set_lobby_ai 挡掉。
func _on_room_ai_changed(_value: float) -> void:
	if _room_ai_sync:
		return                       # _room_refresh 同步值引起的回调，不要回推给会话
	if net_session != null and net_session.has_method("set_lobby_ai"):
		net_session.set_lobby_ai(_room_ai_value())
	_room_refresh()


# 座位数改了：AI 上限 / 座位卡张数 / 开局按钮文案都要跟着重算（D17）
func _on_room_seat_changed(_value: float) -> void:
	_room_refresh()


# 当前房间的座位容量：
#   在房里 → 会话定下的容量（客人靠 welcome 的 max_players 同步，和房主一致）
#   还没建房 → 座位数微调框的值（默认 4）
func _room_seat_capacity() -> int:
	if net_session != null:
		# has_method 兜底：测试里的假会话只实现自己用到的查询，缺这条就退回默认容量
		if net_session.has_method("seat_capacity"):
			return clampi(int(net_session.seat_capacity()), ROOM_MIN_SEATS, ROOM_MAX_SEATS)
		return ROOM_DEFAULT_SEATS
	if _room_seat_spin != null:
		return clampi(int(_room_seat_spin.value), ROOM_MIN_SEATS, ROOM_MAX_SEATS)
	return ROOM_DEFAULT_SEATS