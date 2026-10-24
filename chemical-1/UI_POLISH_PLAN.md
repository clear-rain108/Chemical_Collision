# UI 视觉打磨推进计划

> **最后更新**: 2026-10-24  
> **当前状态**: P1 / P1.x / P2 完成（P2 追加：警告 toast 右移 + 样式工厂 + 悬停流畅化）  
> **相关文档**: [ARCHITECTURE.md](./ARCHITECTURE.md) 第 8 节「表现层 - GameUI.gd」

---

## 1. 总览

| 阶段 | 内容 | 状态 |
|------|------|------|
| **P1** | 可读性与布局打磨（9 项） | ✅ 完成 |
| **P1.x** | 手牌悬停抖动 / 切换过敏 / 选中后发黑 | ✅ 完成（本轮追加） |
| **P2** | 面板与卡牌描边 / 圆角 / 阴影统一 + 警告 toast 右移 | ✅ 完成（2026-10-24） |
| **P2.x** | 手牌悬停切换流畅化（4 个根因） | ✅ 完成（2026-10-24） |
| P4 / P5 / P7 | 内容待与使用者逐条确认后细化 | ⏳ 未展开 |

---

## 2. P1 完成清单

| # | 问题 | 处理 | 位置 |
|---|------|------|------|
| 1 | 日志区文字不可读 | `LogLabel` 改深色 `Color(0.22,0.26,0.32)`、字号 13、区域 `(824,100)-(1136,420)` | `Main.tscn` |
| 2 | 桌面小卡压住"桌面:"文字 | 槽位改为 `table_label.bottom + 4`（y≈186），580px 内水平居中，多张自动压缩步长 | `GameUI.gd::_update_table_cards` |
| 3 | 牌区之间大片空白 | 垂直轴重排：信息 62–150 / 桌面文字 152–182 / 桌面牌槽 186–276 / 手牌标签 282 / 手牌 310–468 / 提示栏 478–526 | `Main.tscn` |
| 4 | 牌面下重、上下失衡 | 化合价 y 66→72、字号 11→13（紧凑模式同步） | `GameUI.gd` |
| 5 | 族标记（右上）看不见 | 固定深灰 `Color(0.3,0.32,0.36)`、字号 9→11、宽 52；迷你卡同步 | `GameUI.gd` |
| 6 | 卡牌与浅蓝背景对比弱 | 边框 `#A1A8B5` + 投影 `(0.1,0.15,0.22,0.14)` / size 3 / offset (0,2) | `GameUI.gd` |
| 7 | 状态栏重复显示自己的手牌数 | `_format_player_status()` 只列 AI 手牌 | `GameUI.gd` |
| 9 | 叠卡太松、露白多 | `CARD_STEP_MAX` 66→60（8 张：露 60 / 重叠 35） | `GameUI.gd` |

顺带修掉的缺陷：

- `_build_status_bar()` 里的 `position += Vector2(0,60)` 位移 hack —— 会让"按场景坐标摆放"的元素运行期错位（桌面小卡压字的真因），已删除，坐标以 `Main.tscn` 为准
- "等待 AI 行动中…" 白字在浅蓝底上不可见 → `Color(0.33,0.4,0.5)`
- 顶部状态条背景宽 1280 超出 1152 视口 → 收窄
- 教程高亮框坐标随布局重排同步更新

---

## 3. P1.x 手牌悬停抖动修复

**现象**：鼠标停在两张牌的重叠窄条处时，卡牌随鼠标移动抽搐；牌间切换过于灵敏（划过即弹起、信息栏刷屏）。

**根因**（三处叠加）：

1. 悬停靠 `mouse_entered / mouse_exited` 驱动，而悬停本身把牌上移 20px —— 鼠标落在牌下沿 20px 内时形成
   `抬起 → 让出底部 → exited → 落回 → entered → 再抬起` 的死循环
2. 重叠区（8 张时宽 35px）两张牌的 `z_index` 随悬停变化，pick 结果在两者间来回翻转
3. Button 自带的 `hover` StyleBox 是引擎独立判定，与上面两套不同步，边框单独闪烁

**修复**：

- 命中区改用**静止坐标**计算（`_card_hover_rect` = base ∪ 抬起位置），悬停状态不参与判定 → 不可能自激
- 不连引擎信号，改 `_process → _update_hand_hover()` 轮询；`_update_hover_at(mp)` 可注入鼠标位置供测试
- 重叠区归属"最上层"（索引最大），但鼠标仍在当前牌**核心区**（`_card_core_rect`）内则保持 → 窄条处不回跳
- 目标需稳定 `HOVER_SWITCH_DELAY_MS = 110ms` 才切换；移出手牌区立即复位
- 边框样式改由 `_apply_hover()` 切换 `normal` StyleBox；引擎的 `hover` / `pressed` / `focus` 三项全部显式接管
  （细节见 3.1，漏掉会被默认深色主题盖成灰块）

**验证**：`tests/verify_hand_layout.gd` 新增 8 条断言（命中区覆盖上浮区 / 核心区不相交 / 重叠归属 /
40 次判定恒定 / 首帧不抬起 / 稳定后抬起 / 切换后前张落下 / 最多一张抬起），全部通过。

---

## 3.1 选中后卡牌"发黑"修复

**现象**：点击选牌后，鼠标停留的那张牌整块变成半透明深灰，牌面内容发暗（截图见修复前后的对照）。

**根因**：Godot 默认（深色）主题里 Button 的 `hover` 是 `StyleBoxFlat bg=(0.225,0.225,0.225,0.6)`（半透明深灰）、
`focus` 是 `bg=(1,1,1,0.75)`（半透明白罩）。3 节为消除"双判定闪烁"删掉了
`add_theme_stylebox_override("hover", …)`，于是引擎的 hover 态**回退到默认主题**，在真实鼠标悬停/点击后
糊在牌面上。自动化截图直接调 `_apply_hover()`、绕过了引擎 hover 态，所以上一轮没暴露。

**修复**：

- `_build_card_button()` 显式接管 `hover` / `pressed` / `focus`：前两者指向当前 `normal` 的**同一个 StyleBox**，
  后者用 `StyleBoxEmpty`（去掉点击后的焦点白罩）
- `_apply_hover()` 切换时同时更新 `normal / hover / pressed` 三者 → 引擎状态判定无论怎么翻，画面完全一致；
  判定仍唯一（状态机），不会重新引入闪烁
- 顺带修：**选中牌的悬停样式改为深一档浅黄 `#FFFAB8` + 深橙边**，避免悬停的浅蓝把"已选中"的浅黄整个盖掉

**验证**：`verify_hand_layout` 新增 6 条断言（hover/pressed 与 normal 同源、focus 为 StyleBoxEmpty、
选中悬停仍为黄色系、边框仍为暖色、取消选中恢复白底）；悬停/选中态截图确认无灰块、选中状态清晰可辨。

---

## 3.2 浮层被手牌穿透（显示层级冲突）

**现象**：① 「选择下一名玩家必须打出的牌型」弹窗被手牌"打洞"——悬停/选中的牌浮在白色面板之上；
② 黄底红框的「不是有效族炸！」大提示框与手牌互相穿插：未选中的牌被黄框盖住，选中/悬停的牌又浮在黄框上。

**根因**：`GamePage` 下**只有手牌**设置了 `z_index`（悬停 100 / 选中 50），而所有运行时浮层
（`_show_sequence_constraint_dialog()` 的 overlay、`_show_center_warning()` 的提示框、第零关 overlay、
顶部状态栏、桌面小卡）都只是 `game_page.add_child()`，z 保持 0。Godot 的 CanvasItem 排序是
**z_index 优先于树顺序** → 手牌整体压在所有浮层之上。附带后果：弹窗遮罩的 `mouse_filter=STOP`
也拦不住 z 更高的手牌，弹窗开着仍能点牌。

**修复**：引入三个层容器（`_ensure_layers()` 幂等创建，在 `_setup_pages()` 内调用）：

| 层 | z_index | 承载 |
|---|---|---|
| `ContentLayer` | 0 | 顶部状态栏 / 桌面小卡 / 第零关规则提醒 |
| `OverlayLayer` | 100 | 全屏遮罩 + 模态弹窗（第零关引导、顺序指定弹窗） |
| `ToastLayer` | 110 | 警告框 / 引导提示（`_show_center_warning`、`_level0_make_tip_box`） |

手牌 z 降为 选中 `10` / 悬停 `20`（只在手牌内部置顶），所有运行时节点改走 `_layer(0/1/2)`。

**验证**：`verify_hand_layout` 既有 z 断言改为 10/20，并新增 `_test_layers()` 9 条断言
（三层存在 / z 序 / 铺满全屏 / 层不拦鼠标 / 顺序弹窗落在 OverlayLayer / 警告框落在 ToastLayer）；
11 个套件全绿，`--quit-after 300` 无 ERROR；截图确认弹窗与警告框完整覆盖手牌。

**遗留（P2，已解决）**：`_show_center_warning()` 位置仍是写死的 `(300,360) 800×110`，正好压在手牌区上
（会被遮挡 2.5s）。层级已正确，若要连"遮挡"一起消除，已在 3.5 改为右栏 toast。

---

## 3.3 教程引导文本与桌面小卡重叠

**现象**：教程关卡 1 第 2 步，引导文本「【第2步】很好！现在试试合成化合物…」被桌面打出的
单质 H 小卡盖住中间一截（文字被"打洞"），且「金属优先正价，非金属优先负价。」与
「✓ 正确！你打出了一张单质。」两行紧贴，整块文本挤成一坨。

**根因**（纯布局，与 z_index 无关）：

1. `TutorialLabel` 原 rect 为 `(225,185) 900×40`，而桌面小卡槽是 `(20,186) 580×90`
   （`_update_table_label()` 里 `slot_y = table_label.bottom + 4 = 186`）→ 两者**矩形完全重叠**，
   桌面一出牌小卡就压住引导文本第一行。
2. `get_tutorial_display()` 返回「引导 2 行 + 成功提示 1 行」，14px 折行后共 **4 行 ≈ 98px**，
   而 Label 只有 40px（2 行）→ 后两行溢出到 225..284。
3. `LogLabel` 当时在 `(824,100) 312×320`，与教程文本右半边（824..1125）也重叠。

**修复**（`Main.tscn`）：

| 节点 | 原 rect | 新 rect | 理由 |
|---|---|---|---|
| `TutorialLabel` | (225,185) 900×40 | **(620,186) 505×98** | 桌面小卡槽右侧，高度容纳 4 行；加 `line_spacing=6` 提升可读性 |
| `LogLabel` | (824,100) 312×320 | **(824,300) 312×300** | 下移让出教程文本区域，高度基本不变（300 vs 320） |

**验证**：`verify_hand_layout` 新增 `_test_tutorial_layout()` 10 条断言（与桌面小卡槽 / 日志区 /
InfoLabel / HandLabel / HandContainer / CardInfoLabel 均不相交，宽 ≥480、高 ≥96）；11 个套件全绿。
实机截图确认 4 行文本完整显示、右侧日志独立、无任何压盖。

**约束**：以后调整这几块位置时必须复算「桌面小卡槽（最多 8 张，横向 20..600）」与「日志区」。

---

## 3.4 手牌悬停切换流畅化（4 个根因）

**现象**：鼠标沿手牌上沿横向滑过时，抬起的牌频繁"掉下来又上去"；从一张牌移到相邻牌有时要
停顿半拍才响应；抬起/落下是一格一跳的瞬移，不跟手。

**根因与修复**：

| # | 根因 | 修复 |
|---|------|------|
| R1 | 抬起牌 `z_index=20` 压住相邻牌，但命中仍用静止规则（重叠取索引最大）→ 指针明明在抬起牌画出来的区域里，判定却给被压住的后一张，于是"落下→后一张抬起→再判回"来回翻 | `_card_raised_rect()`：已抬起牌的绘制矩形优先命中，命中即保持 |
| R2 | 固定 `HOVER_SWITCH_DELAY_MS = 110ms` 对"明确进入目标牌核心区"也生效，显得迟钝 | 分级：命中某张牌 `60ms`；仍在容器内但不在任何牌上（牌列下方）`HOVER_LEAVE_DELAY_MS = 140ms` |
| R3 | `_apply_hover()` 直接 `btn.position = …`，一格跳变 | `_tween_card_y()`：`HOVER_ANIM_MS = 80ms` + `TRANS_CUBIC/EASE_OUT`；`z_index` 仍立即切换；每张牌只保留一个 tween，`_layout_hand_cards()` 重排前 `_kill_hover_tween()`，否则动画会把牌拉回旧坐标 |
| R4 | 抬起牌顶边与容器顶边重合（`base_y = 20 = HOVER_LIFT`），沿顶边滑动时越界 1px 就落牌、回来再等一次延迟 | `_hover_keep_above()`：横向仍在牌列、纵向越界 ≤ `HOVER_EXIT_GRACE = 14px` 时保持 |

**行为变化（有意）**：抬起牌覆盖的重叠窄条现在归抬起牌自己（视觉与判定一致）。
要切到后一张，指针需越过抬起牌的右边缘 —— 之前"一进窄条就换牌"会让指针还压在抬起牌上时它就落下。

**验证**：`verify_hand_layout.gd → _test_hover_smoothness()` 18 条断言（R1 优先级 / 40 次判定恒定 /
R1b 越界切换 / R2 60ms 生效 / R2b 140ms 留出 / R3 当帧不瞬移 + 补间到达 / R3b 重排杀补间 /
R4 容错带内外与横向越界），既有 `_test_case()` / `_test_hover_debounce()` 的位置断言改为
`await _wait_hover_anim()` 后再比。

**测试注意**：Tween 以帧步进，headless 下单帧可能就超过固定等待时长（补间一步未走）。
`_wait_hover_anim()` 改为轮询 `hover_tween.is_running()`，不用 `create_timer`。

---

## 3.5 警告提示右移 + 视觉规范工厂（P2）

**现象**：① 出牌不合理时的黄底红框提示写死在 `(300,360) 800×110`，正好盖住手牌 / 卡牌信息栏 /
操作区 2.5 秒；且每次报错 `new` 一个节点，连续报错会叠框、上一条的计时器还会把新框提前关掉。
② 圆角/描边/阴影散落在 `_build_card_button` / `_build_mini_card_button` / `_mkb` /
`_level0_make_tip_box` 四处，同一类元素出现 6px 与 8px 混用。

**修复**：

| 项 | 内容 |
|---|---|
| 位置 | `_show_center_warning()` 改为右栏 toast：`WARNING_TOAST_RECT = (824,62,312,116)`（LogLabel 从 y=300 起、TutorialLabel 从 y=186 起、InfoLabel 只到 x=480 → 不与任何静态节点相交） |
| 生命周期 | 单例复用同一个 `Panel`（`_ensure_warning_toast()` 幂等创建），连续报错只更新文本；`_warning_seq` 自增让旧 `SceneTreeTimer` 作废；`_init_game()` / `_on_start_tutorial()` 调 `_hide_warning_toast()` |
| 样式 | `_make_panel_style(kind)` + `_style_base()` 成为唯一来源：`card` / `card_selected` / `card_hover` / `card_hover_selected` / `mini_card` / `mini_card_hover` / `button` / `toast_warning` / `toast_info` |
| 数值 | 圆角 8（卡 / 按钮）/ 10（面板 toast）、描边 1px `#A1A8B5` / 2px（选中·焦点·警告）、阴影 `(0.1,0.15,0.22,0.14)` size 3 offset (0,2)；小卡无投影 |
| 颜色 | **原值不变**：`#F8F9FC` / `#FFFFD1` / `#E6EEFA` / `#FFFAB8`，边框 `#A1A8B5` / `#E6A61A` / `#5989D9` / `#D98C00`；既有 4 态断言全部保留 |
| 顺带 | 顺序指定弹窗的按钮改用 `_mkb()`（与操作面板同一套样式）；第零关提示框由 `ColorRect + 描边矩形` 改为 `Panel + toast_info` |

**验证**：`_test_warning_toast()` 约 20 条（位置/尺寸、不拦鼠标、toast_warning 样式、与 8 个静态节点均不相交、
在窗口内、连续报错不叠框、文本更新、可隐藏）；`_test_style_factory()` 17 条（各 kind 圆角/描边/阴影/内边距、
4 态颜色锁死、真实手牌样式来自工厂）。

---

## 4. P2 完成清单

**目标**：GamePage 内所有面板与卡牌的描边、圆角、阴影统一到一套视觉规范。

| # | 项 | 实现 |
|---|---|---|
| 1 | 样式工厂 | `_make_panel_style(kind)` / `_style_base()`，kind 见 3.5 |
| 2 | 三级描边 | 普通 1px `#A1A8B5`；选中/焦点 2px 橙金·主题蓝；警告 2px `#E74C3C` |
| 3 | 圆角 / 阴影 | 卡牌与按钮 8、面板/toast 10；阴影统一 size 3 offset (0,2)，桌面小卡无投影 |
| 4 | 调用点收敛 | 手牌、桌面小卡、操作按钮、顺序指定弹窗、第零关提示框、警告 toast 全部走工厂 |
| 5 | 警告提示 | 居中大框 → 右栏 toast（见 3.5） |

**不做**：`Main.tscn` 里静态节点的布局与颜色、`_apply_hover()` 的 `sb_normal/sb_hover` meta 机制保持不变。

**验收**：11 个测试套件全绿（`verify_hand_layout` 100+ 条）、`--quit-after 300` 无 ERROR。

---

## 4.1 原 P2 草案（存档）

**目标**：GamePage 内所有面板（状态栏、信息栏、桌面栏、日志、操作区）与卡牌的描边、圆角、阴影统一到一套视觉规范。

- 抽取 `_make_panel_style(kind)` 工厂：`panel_flat` / `panel_log` / `card` / `card_selected`
- 三级描边：普通元素 1px `#A1A8B5`；选中/焦点 2px 主题蓝；危险/警告 2px 橙
- 圆角统一 8px（卡牌）/ 10px（面板）；阴影统一 `(0.1,0.15,0.22,0.14)` size 3 offset (0,2)
- 验收：4 态截图（8 张 / 悬停 / 选中 / 桌面出牌）+ 11 个测试保持全绿

---

## 5. 验证基线

11 个自动化测试（全部在 `--headless` 下运行，无 FAIL 即通过）：

```bat
set GD=D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
for %f in (hand_layout hand_runtime integration constraint logger organic refactor sequence sequence_table tutorial ai_discard) do (
  %GD% --path . --headless --script res://tests/verify_%f.gd
)
```

| 测试 | 覆盖 |
|------|------|
| `verify_hand_layout` | 手牌尺寸/居中/叠卡步长/紧凑牌面/悬停上浮/**防抖状态机**/**选中与悬停样式**/**悬停流畅化（R1–R4）**/**警告 toast 布局**/**样式工厂**（120+ 条） |
| `verify_hand_runtime` | 真实手牌渲染与点击流程 |
| `verify_integration` | 端到端对局 |
| `verify_constraint` | 化合价与牌型约束 |
| `verify_logger` | 日志转发 |
| `verify_organic` | 有机物胜利规则 |
| `verify_refactor` | 模块拆分回归 |
| `verify_sequence` / `verify_sequence_table` | 顺序牌型与桌面判定 |
| `verify_tutorial` | 教程关卡状态机 |
| `verify_ai_discard` | 手牌上限自动弃牌 |
