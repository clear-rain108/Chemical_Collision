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
const StartPageScript = preload("res://scripts/pages/StartPage.gd")
const SuppRulesPageScript = preload("res://scripts/pages/SuppRulesPage.gd")
const HelpPageScript = preload("res://scripts/pages/HelpPage.gd")
const EndPageScript = preload("res://scripts/pages/EndPage.gd")
const TutorialPageScript = preload("res://scripts/pages/TutorialPage.gd")
const Level0OverlayScript = preload("res://scripts/tutorial/Level0Overlay.gd")
const OnlineUIScript = preload("res://scripts/net/OnlineUI.gd")
const RoomPageScript = preload("res://scripts/pages/RoomPage.gd")
const VoteUIScript = preload("res://scripts/ui/VoteUI.gd")

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
var ui_start = null                      # 开始页（标题 / 设置卡 / 按钮区 / 装饰牌 / 内联提示）
var ui_supp = null                       # 补充规则小页（4 张规则卡 / 元素池 / 勾选摘要）
var ui_help = null                       # 帮助中心（3 Tab 骨架 / 卡片 / 图鉴小卡 / 进出路由）
var ui_end = null                        # 结算页（结算卡 / 统计块 / 按钮去向 / 淡入）
var ui_tut = null                        # 教学引导页（三张关卡卡 / 进出路由 / 入场错峰）
var ui_level0 = null                     # 第零关引导覆盖层（三步流程 / 高亮框 / 规则提醒）
var ui_online = null                     # 联机接线（会话装配 / 座位视角 / 权威事件回调 / 每帧推进）
var ui_room = null                       # 房间页（建房 / 加入 / 座位表 / 开局闸门 / 收尾）
var ui_vote = null                       # 化合物质疑投票遮罩（D22 联机；单机恒不开）

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
# 第零关规则提醒（挂在 ContentLayer 上，跨局不清 → 由 _level0_clear_rule_tips 显式回收）
var level0_rule_tip_label: Label = null
var level0_rule_tip_bg: Panel = null
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
var ai_triggered: bool = false          # 是否有待执行的 AI 定时器（verify_ui_online D8 依赖）
var ai_armed_actor: int = -1            # 与 ai_armed_turn 组成令牌（回合号 + 行动者）：换手漏 turn_count 时也不会卡死
var ai_armed_turn: int = -1             # 已排程的回合号（gm.turn_count）：同一手只排一次
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
	ui_start = StartPageScript.new(self)
	ui_supp = SuppRulesPageScript.new(self)
	ui_help = HelpPageScript.new(self)
	ui_end = EndPageScript.new(self)
	ui_tut = TutorialPageScript.new(self)
	ui_level0 = Level0OverlayScript.new(self)
	ui_online = OnlineUIScript.new(self)
	ui_room = RoomPageScript.new(self)
	ui_vote = VoteUIScript.new(self)


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

# -------- 以下方法已搬进 scripts/pages/HelpPage.gd（Slice 4d 纯搬运，这里只留同名转发） --------
func _on_show_help() -> void:
	ui_help._on_show_help()

# -------- 以下方法已搬进 scripts/pages/TutorialPage.gd（Slice 4f 纯搬运，这里只留同名转发） --------
func _on_show_tutorial_page() -> void:
	ui_tut._on_show_tutorial_page()


# -------- 以下方法已搬进 scripts/pages/TutorialPage.gd（Slice 4f 纯搬运，这里只留同名转发） --------
func _on_tutorial_back() -> void:
	ui_tut._on_tutorial_back()


# -------- 以下方法已搬进 scripts/pages/HelpPage.gd（Slice 4d 纯搬运，这里只留同名转发） --------
func _on_help_back() -> void:
	ui_help._on_help_back()

func _on_help_show_cards() -> void:
	ui_help._on_help_show_cards()

func _on_help_show_supp() -> void:
	ui_help._on_help_show_supp()

func _on_help_show_rules() -> void:
	ui_help._on_help_show_rules()

func _open_help_at_tab(idx: int) -> void:
	ui_help._open_help_at_tab(idx)


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


# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _build_start_page() -> void:
	ui_start._build_start_page()

func _start_page_bg() -> void:
	ui_start._start_page_bg()

# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _page_bg_into(parent: Control, bg_name: String, band_name: String) -> void:
	ui_page._page_bg_into(parent, bg_name, band_name)



# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _start_page_decor() -> void:
	ui_start._start_page_decor()

func _start_make_deco_card(sym: String, pos: Vector2, angle: float) -> Panel:
	return ui_start._start_make_deco_card(sym, pos, angle)

# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _start_label(text: String, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	return ui_page._start_label(text, fs, col, align)



# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _start_page_title() -> void:
	ui_start._start_page_title()

func _start_page_settings() -> void:
	ui_start._start_page_settings()

func _start_setting_label(node_name: String, text: String, pos: Vector2) -> Label:
	return ui_start._start_setting_label(node_name, text, pos)



# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _start_page_buttons() -> void:
	ui_start._start_page_buttons()


# -------- 以下方法已搬进 scripts/pages/SuppRulesPage.gd（Slice 4c 纯搬运，这里只留同名转发） --------
func _build_supp_rules_page() -> void:
	ui_supp._build_supp_rules_page()

func _supp_rule_card(page: Control, node_name: String, title: String, desc: String, pos: Vector2) -> Button:
	return ui_supp._supp_rule_card(page, node_name, title, desc, pos)

func _build_element_pool(page: Control) -> void:
	ui_supp._build_element_pool(page)

func _symbols_joined(syms: Array) -> String:
	return ui_supp._symbols_joined(syms)


# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _page_primary_btn(text: String, cb: Callable, sz: Vector2, node_name: String = "", fs: int = 20) -> Button:
	return ui_page._page_primary_btn(text, cb, sz, node_name, fs)

func _page_secondary_btn(text: String, cb: Callable, sz: Vector2, node_name: String = "", fs: int = 19) -> Button:
	return ui_page._page_secondary_btn(text, cb, sz, node_name, fs)

func _page_ghost_btn(text: String, cb: Callable, sz: Vector2, node_name: String = "", fs: int = 16) -> Button:
	return ui_page._page_ghost_btn(text, cb, sz, node_name, fs)



# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _start_make_primary(text: String, pos: Vector2, sz: Vector2) -> Button:
	return ui_start._start_make_primary(text, pos, sz)

func _start_make_secondary(node_name: String, text: String, pos: Vector2, sz: Vector2) -> Button:
	return ui_start._start_make_secondary(node_name, text, pos, sz)

func _start_make_ghost(node_name: String, text: String, pos: Vector2, sz: Vector2) -> Button:
	return ui_start._start_make_ghost(node_name, text, pos, sz)

func _start_make_spin(min_v: int, max_v: int, val: int, node_name: String) -> SpinBox:
	return ui_start._start_make_spin(min_v, max_v, val, node_name)



# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _start_make_toggle(node_name: String, text: String, pos: Vector2) -> Button:
	return ui_start._start_make_toggle(node_name, text, pos)



# -------- 动效：入场错峰淡入 + 装饰牌缓慢浮动（只动子节点，不动页面级 modulate）--------
# 入场名单必须覆盖开始页上每一个可见节点（顺序 = 视觉从上到下 / 从左到右）。
# 漏登记 = 那个节点不淡入也不上浮，页面淡入一结束就"抢先"以终态出现（Step 4 的
# RoomEntryBtn 就这么漏过一次）—— 测试 START_INTRO_ORDER 覆盖性断言会拦住这类遗漏。
const START_INTRO_ORDER := [
	"StartTitle", "StartSubtitle", "StartAccent", "StartMeta", "DecorCards",
	"SettingsCard", "StartRuleHint", "RoomEntryBtn", "StartButton", "TutorialBtn", "ExitButton",
]


# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _animate_start_page() -> void:
	ui_start._animate_start_page()



# -------- 以下方法已搬进 scripts/pages/PageChrome.gd（Slice 4a 纯搬运，这里只留同名转发） --------
func _animate_page_intro(page: Control, order: Array) -> void:
	ui_page._animate_page_intro(page, order)

func _page_deco_float(page: Control) -> void:
	ui_page._page_deco_float(page)



# -------- 以下方法已搬进 scripts/pages/StartPage.gd（Slice 4b 纯搬运，这里只留同名转发） --------
func _start_flash_rule_hint(text: String, col: Color = START_C_ACCENT) -> void:
	ui_start._start_flash_rule_hint(text, col)


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


# -------- 以下方法已搬进 scripts/pages/HelpPage.gd（Slice 4d 纯搬运，这里只留同名转发） --------
func _build_help_page() -> Control:
	return ui_help._build_help_page()

func _set_top_bar_rect(ctrl: Control, top: float, height: float) -> void:
	ui_help._set_top_bar_rect(ctrl, top, height)

func _style_help_tab(btn: Button, selected: bool) -> void:
	ui_help._style_help_tab(btn, selected)

func _set_help_tab(idx: int) -> void:
	ui_help._set_help_tab(idx)

func _fill_help_tab(idx: int) -> void:
	ui_help._fill_help_tab(idx)

func _fill_help_cards(body: VBoxContainer, tab: Dictionary) -> void:
	ui_help._fill_help_cards(body, tab)

func _make_help_card(data: Dictionary) -> PanelContainer:
	return ui_help._make_help_card(data)

func _make_help_hsep() -> ColorRect:
	return ui_help._make_help_hsep()

func _append_help_line(parent: VBoxContainer, line: Dictionary) -> void:
	ui_help._append_help_line(parent, line)

func _make_help_demo_row(symbols: Array) -> HBoxContainer:
	return ui_help._make_help_demo_row(symbols)

func _make_help_mini_card(card, show_valence: bool = false) -> PanelContainer:
	return ui_help._make_help_mini_card(card, show_valence)

func _help_valence_text(card) -> String:
	return ui_help._help_valence_text(card)

func _help_symbol_color(card) -> Color:
	return ui_help._help_symbol_color(card)

func _help_label(text: String, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	return ui_help._help_label(text, fs, col, align)

func _help_element_cards() -> Array:
	return ui_help._help_element_cards()

func _help_find_card(sym: String):
	return ui_help._help_find_card(sym)

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


# -------- 以下方法已搬进 scripts/pages/EndPage.gd（Slice 4e 纯搬运，这里只留同名转发） --------
func _build_end_page() -> void:
	ui_end._build_end_page()

func _end_stat_style() -> StyleBoxFlat:
	return ui_end._end_stat_style()

func _is_tutorial_run() -> bool:
	return ui_end._is_tutorial_run()

func _fill_end_page(custom_text: String) -> void:
	ui_end._fill_end_page(custom_text)

func _on_end_restart() -> void:
	ui_end._on_end_restart()



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


# -------- 以下方法已搬进 scripts/pages/TutorialPage.gd（Slice 4f 纯搬运，这里只留同名转发） --------
func _build_tutorial_page() -> void:
	ui_tut._build_tutorial_page()

func _make_level_card(idx: int, title_text: String, desc_text: String) -> Button:
	return ui_tut._make_level_card(idx, title_text, desc_text)

func _level_card_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	return ui_tut._level_card_style(hover, pressed)

func _on_level_card_hover(card: Button, entered: bool) -> void:
	ui_tut._on_level_card_hover(card, entered)



# ============================================================
# 六、游戏启动
# ============================================================
# -------- 以下方法已搬进 scripts/pages/SuppRulesPage.gd（Slice 4c 纯搬运，这里只留同名转发） --------
func _on_organic_toggled(pressed: bool) -> void:
	ui_supp._on_organic_toggled(pressed)

func _on_sequence_toggled(pressed: bool) -> void:
	ui_supp._on_sequence_toggled(pressed)

func _on_halogen_toggled(pressed: bool) -> void:
	ui_supp._on_halogen_toggled(pressed)

func _on_element_limit_toggled(pressed: bool) -> void:
	ui_supp._on_element_limit_toggled(pressed)

func _on_element_chip_toggled(_pressed: bool) -> void:
	ui_supp._on_element_chip_toggled(_pressed)

func _sync_supp_rules_summary() -> void:
	ui_supp._sync_supp_rules_summary()

func _selected_extra_elements() -> Array:
	return ui_supp._selected_extra_elements()

func _open_supp_rules() -> void:
	ui_supp._open_supp_rules()

func _close_supp_rules() -> void:
	ui_supp._close_supp_rules()

# 总人数变化 → AI 上限跟着变（AI 至少给人类留 1 个座位）
# 例：总人数 4 → AI 最多 3；把总人数改回 3 时 AI 会自动从 3 降到 2
func _on_player_count_changed(value: float) -> void:
	if ai_spin == null:
		return
	var seat_for_ai := maxi(0, int(value) - 1)
	var before := int(ai_spin.value)
	ai_spin.max_value = seat_for_ai   # Range 会自动把超限的 value 压回 max
	if before > seat_for_ai:
		_start_flash_rule_hint("人机人数已自动降为 %d（最多 = 总人数 - 1）" % seat_for_ai)

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

# -------- 以下方法已搬进 scripts/tutorial/Level0Overlay.gd（Slice 4f 纯搬运，这里只留同名转发） --------
func _level0_start_phase1() -> void:
	ui_level0._level0_start_phase1()

func _level0_ui_steps() -> Array:
	return ui_level0._level0_ui_steps()

func _level0_show_ui_step(idx: int) -> void:
	ui_level0._level0_show_ui_step(idx)

func _level0_make_outline_rect(pos: Vector2, rect_size: Vector2, color: Color, width: int) -> Control:
	return ui_level0._level0_make_outline_rect(pos, rect_size, color, width)

func _level0_ui_next_step() -> void:
	ui_level0._level0_ui_next_step()

func _level0_guide_btn(pos: Vector2, btn_size: Vector2, text: String, cb: Callable) -> Button:
	return ui_level0._level0_guide_btn(pos, btn_size, text, cb)

func _level0_skip_guide() -> void:
	ui_level0._level0_skip_guide()

func _level0_exit_guide() -> void:
	ui_level0._level0_exit_guide()

func _level0_ensure_overlay() -> void:
	ui_level0._level0_ensure_overlay()

func _level0_start_phase2() -> void:
	ui_level0._level0_start_phase2()

func _level0_show_flow_step(idx: int) -> void:
	ui_level0._level0_show_flow_step(idx)

func _level0_flow_next_step() -> void:
	ui_level0._level0_flow_next_step()

func _level0_start_phase3() -> void:
	ui_level0._level0_start_phase3()

func _level0_create_rule_tips() -> void:
	ui_level0._level0_create_rule_tips()


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


# -------- 以下方法已搬进 scripts/tutorial/Level0Overlay.gd（Slice 4f 纯搬运，这里只留同名转发） --------
func _on_rule_tip_title_pressed() -> void:
	ui_level0._on_rule_tip_title_pressed()

func _layout_rule_tips() -> void:
	ui_level0._layout_rule_tips()

func _level0_clear_rule_tips() -> void:
	ui_level0._level0_clear_rule_tips()

func _level0_set_rule_tips_visible(on: bool) -> void:
	ui_level0._level0_set_rule_tips_visible(on)

func _level0_update_rule_tips() -> void:
	ui_level0._level0_update_rule_tips()

func _level0_rule_tips_text() -> String:
	return ui_level0._level0_rule_tips_text()

func _level0_make_tip_box(text: String, duration: float = 2.5) -> Control:
	return ui_level0._level0_make_tip_box(text, duration)


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

# -------- 以下方法已搬进 scripts/pages/EndPage.gd（Slice 4e 纯搬运，这里只留同名转发） --------
func _show_end_page(custom_text: String) -> void:
	ui_end._show_end_page(custom_text)

func _ensure_end_button_connected(target: Callable) -> void:
	ui_end._ensure_end_button_connected(target)



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

# -------- 以下方法已搬进 scripts/net/OnlineUI.gd（Slice 4g 纯搬运，这里只留同名转发） --------
func _router():
	return ui_online._router()

func attach_session(session) -> void:
	ui_online.attach_session(session)

func _my_seat() -> int:
	return ui_online._my_seat()

func _view_player():
	return ui_online._view_player()

func _net_can_operate() -> bool:
	return ui_online._net_can_operate()

func _net_wait_text() -> String:
	return ui_online._net_wait_text()

func _mk_wait_label(text: String) -> Label:
	return ui_online._mk_wait_label(text)

func _dispatch_result(code: int) -> void:
	ui_online._dispatch_result(code)

func _connect_online_signals(session) -> void:
	ui_online._connect_online_signals(session)

func _online_on_game_started() -> void:
	ui_online._online_on_game_started()

func _online_on_state_applied(_ev: Dictionary, _result: int) -> void:
	ui_online._online_on_state_applied(_ev, _result)

func _online_on_intent_rejected(_seq: int, code: int) -> void:
	ui_online._online_on_intent_rejected(_seq, code)

func _online_on_sequence_pending(seat: int, remain_ms: int) -> void:
	ui_online._online_on_sequence_pending(seat, remain_ms)

func _online_on_sequence_cleared() -> void:
	ui_online._online_on_sequence_cleared()

func _online_on_session_closed(reason: String) -> void:
	ui_online._online_on_session_closed(reason)

func _online_on_desync(local_hash: int, host_hash: int) -> void:
	ui_online._online_on_desync(local_hash, host_hash)

func _online_on_error(code: int, detail: String) -> void:
	ui_online._online_on_error(code, detail)

func _hide_sequence_overlay() -> void:
	ui_online._hide_sequence_overlay()

func _update_net(delta: float) -> void:
	ui_online._update_net(delta)

func _net_ai_delay() -> float:
	return ui_online._net_ai_delay()

func _enter_online_game() -> void:
	ui_online._enter_online_game()


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

# -------- 以下方法已搬进 scripts/pages/RoomPage.gd（Slice 4h 纯搬运，这里只留同名转发） --------
func _build_room_page() -> void:
	ui_room._build_room_page()

func _room_label(node_name: String, text: String, pos: Vector2, sz: Vector2, fs: int = START_FS_META, col: Color = START_C_TITLE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return ui_room._room_label(node_name, text, pos, sz, fs, col, align)

func _room_line_edit(node_name: String, text: String, pos: Vector2, sz: Vector2) -> LineEdit:
	return ui_room._room_line_edit(node_name, text, pos, sz)

func _room_host_card(page: Control) -> void:
	ui_room._room_host_card(page)

func _room_join_card(page: Control) -> void:
	ui_room._room_join_card(page)

func _room_seats_panel(page: Control) -> void:
	ui_room._room_seats_panel(page)

func _room_layout_seats(capacity: int) -> void:
	ui_room._room_layout_seats(capacity)

func _room_refresh() -> void:
	ui_room._room_refresh()

func _room_local_ips() -> Array:
	return ui_room._room_local_ips()

func _room_ip_text() -> String:
	return ui_room._room_ip_text()

func _room_start_block_reason(online_humans: int, ai_count: int, is_host: bool, room_state: int, offline_seats: int = 0, capacity: int = ROOM_DEFAULT_SEATS) -> String:
	return ui_room._room_start_block_reason(online_humans, ai_count, is_host, room_state, offline_seats, capacity)

func _room_start_disabled_reason() -> String:
	return ui_room._room_start_disabled_reason()

func _room_can_start() -> bool:
	return ui_room._room_can_start()

func _room_online_humans() -> int:
	return ui_room._room_online_humans()

func _room_offline_humans() -> int:
	return ui_room._room_offline_humans()

func _room_ai_value() -> int:
	return ui_room._room_ai_value()

func _open_room_page() -> void:
	ui_room._open_room_page()

func _close_room_page() -> void:
	ui_room._close_room_page()

func _room_teardown() -> void:
	ui_room._room_teardown()

func _room_leave() -> void:
	ui_room._room_leave()

func _room_hint(text: String) -> void:
	ui_room._room_hint(text)

func _room_start_host() -> void:
	ui_room._room_start_host()

func _room_join() -> void:
	ui_room._room_join()

func _room_start() -> void:
	ui_room._room_start()

func _room_bind_session(s) -> void:
	ui_room._room_bind_session(s)

func _room_on_seat_assigned(seat: int) -> void:
	ui_room._room_on_seat_assigned(seat)

func _room_on_peer_joined(seat: int, peer_name: String) -> void:
	ui_room._room_on_peer_joined(seat, peer_name)

func _room_on_peer_left(seat: int, peer_name: String, grace_ms: int) -> void:
	ui_room._room_on_peer_left(seat, peer_name, grace_ms)

func _on_room_ai_changed(_value: float) -> void:
	ui_room._on_room_ai_changed(_value)

func _on_room_seat_changed(_value: float) -> void:
	ui_room._on_room_seat_changed(_value)

func _room_seat_capacity() -> int:
	return ui_room._room_seat_capacity()
