# UI 视觉打磨推进计划

> **最后更新**: 2026-10-31  
> **当前状态**: P1 / P1.x / P2 / P3 / P5 / P6 / P7 / P8 完成（P7：手牌拖拽重排 + 选中索引修复，见 §9；P8：结束页 / 教学引导页画风统一，见 §10）  
> **相关文档**: [ARCHITECTURE.md](./ARCHITECTURE.md) 第 8 节「表现层 - GameUI.gd」

---

## 1. 总览

| 阶段 | 内容 | 状态 |
|------|------|------|
| **P1** | 可读性与布局打磨（9 项） | ✅ 完成 |
| **P1.x** | 手牌悬停抖动 / 切换过敏 / 选中后发黑 | ✅ 完成（本轮追加） |
| **P2** | 面板与卡牌描边 / 圆角 / 阴影统一 + 警告 toast 右移 | ✅ 完成（2026-10-24） |
| **P2.x** | 手牌悬停切换流畅化（4 个根因） | ✅ 完成（2026-10-24） |
| **P3** | 动效与排版：页面淡入 / 按钮缩放发光 / 卡牌字号 | ✅ 完成（2026-10-30，见 §4.1） |
| **P5** | 帮助中心重构：3 个独立页合并为单页 3 Tab + 滚动 + 卡片（Plan B 新手向） | ✅ 完成（2026-10-30，见 §7） |
| **P6** | 提示按钮「自动选最优组合 + 解释」/ 开始页全部代码生成 / 旧帮助页节点清理 | ✅ 完成（2026-10-31，见 §8；含 §8.5 收尾修复） |
| **P7** | 手牌拖拽重排（拖动换位 / 一次拖动转手动排列 / 「按序 ⇅」恢复 / 新牌追加末尾 / `selected_indices` 索引→对象修复） | ✅ 完成（2026-10-31，见 §9） |
| **P8** | 结束页 / 教学引导页与开始页统一画风（共用渐变带 + 水印 + 装饰牌 + 白卡；结算卡加状态条与 3 统计块；关卡卡整卡可点） | ✅ 完成（2026-10-31，见 §10） |
| P4 / P7 其余 | 美术升级方向文档的其余条目（卡牌重绘 / 字体 / 图标 / 音频 / A5 悬停与选中放大） | ⏳ 未展开（核对结果见 §6） |

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

## 4.1 P3 完成清单（页面淡入 / 按钮缩放 / 卡牌字号）

**来源**：《化学碰撞美术升级方向》§4.2 字号层级、§5.4 按钮悬停、§7.3 页面切换、§7.4 按钮缩放。
三项均为纯代码改动，不依赖美术资源。

### 页面淡入（文档 §7.3）

| 项 | 实现 |
|---|---|
| 骨架 | `_ensure_page_backdrop()` 在根节点下建常驻同色底 `PageBackdrop`（`#E6F0FA`、`z_index = -100`、首个子节点、不拦鼠标） |
| 淡入 | `_fade_in_page(page)`：目标页 `modulate.a` 0→1，220ms `TRANS_QUAD / EASE_OUT`；同一时刻只保留一个补间 |
| 复位 | 每次淡入先把**其余页**的 `modulate.a` 复位为 1，避免"淡入中途被切走"留下半透明页 |
| 语义 | `visible` 仍**同步**设置，不做延迟隐藏 —— 交叉淡化必须延迟隐藏旧页，而 `_on_help_back()` 等处会同步读 `*.visible` 判断去向，延迟会引入竞态 |
| 覆盖 | 开始页 / 教程页 / 帮助页 / 游戏页 / 结束页的**跨页**切换；帮助页内部 tab（规则 / 图鉴 / 补充）保持即时切换，避免每次点标签闪一下 |

### 按钮缩放与悬停发光（文档 §5.4 / §7.4）

| 项 | 实现 |
|---|---|
| 缩放 | `_mkb()` 内接 `mouse_entered/exited` + `button_down/up` → `_tween_button_scale()`；悬停 1.05、按下 0.96、90ms `TRANS_CUBIC` |
| pivot | `pivot_offset` 居中（`custom_minimum_size * 0.5`，并在 `resized` 时跟随实际尺寸） |
| 防抖 | 缩放只向外扩，不会把指针挤出原边界，`entered/exited` 不自激；每按钮只保留一个补间（`btn_scale_tween` meta） |
| 禁用 | `disabled` 按钮直接早退，不缩放、不发光 |
| 发光 | 悬停样式 `shadow_color = (0.35, 0.55, 0.85, 0.55)`、`shadow_size = 6`、`shadow_offset = 0`（`StyleBoxFlat` 没有真发光，用半透明外扩阴影模拟） |

### 卡牌字号（文档 §4.2）

| 元素 | 原 | 现 |
|---|---|---|
| 元素符号 `CardSymbol` | 26px | **28px**（紧凑牌面仍 21px） |
| 中文名 `CardName` | 12px | **14px**（紧凑牌面仍 12px） |

> 字号在 `_build_card_button()` 与 `_apply_card_compact()` **两处**都定义，只改前者会在重排时被覆盖。
> 坐标未动：`Label.size` 会被字体最小高度撑大，但字形仍自顶部绘制，垂直间距按字形算仍然安全
> （符号 20+28=48 ≤ 中文名 48；中文名 48+14=62 ≤ 化合价 72）。

**不做**（留待 P4/P5）：卡牌内阴影与磨砂纹理、横向渐变、化合价圆底标签、族符号用族主题色（与 P1 结论冲突）、
选中态放大到 105×130、按钮图标与圆角 6px、出牌/抽牌/弃牌动画、牌型揭示与族炸特效、音频。

**验收**：`tests/verify_motion.gd` 44 条（淡入 19 / 按钮 15 / 字号 10）；12 个测试套件全绿；真实窗口 `--quit-after 240` 无 ERROR/WARNING。

---

## 4.2 原 P2 草案（存档）

**目标**：GamePage 内所有面板（状态栏、信息栏、桌面栏、日志、操作区）与卡牌的描边、圆角、阴影统一到一套视觉规范。

- 抽取 `_make_panel_style(kind)` 工厂：`panel_flat` / `panel_log` / `card` / `card_selected`
- 三级描边：普通元素 1px `#A1A8B5`；选中/焦点 2px 主题蓝；危险/警告 2px 橙
- 圆角统一 8px（卡牌）/ 10px（面板）；阴影统一 `(0.1,0.15,0.22,0.14)` size 3 offset (0,2)
- 验收：4 态截图（8 张 / 悬停 / 选中 / 桌面出牌）+ 11 个测试保持全绿

---

## 5. 验证基线

19 个自动化测试（全部在 `--headless` 下运行，无 FAIL 即通过）：

```bat
set GD=D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
for %f in (hand_layout hand_runtime hand_reorder integration constraint logger organic refactor sequence sequence_table tutorial ai_discard motion help_page hint start_page end_page halogen element_limit) do (
  %GD% --path . --headless --script res://tests/verify_%f.gd
)
```

| 测试 | 覆盖 |
|------|------|
| `verify_hand_layout` | 手牌尺寸/居中/叠卡步长/紧凑牌面/悬停上浮/**防抖状态机**/**选中与悬停样式**/**悬停流畅化（R1–R4）**/**警告 toast 布局**/**样式工厂**（120+ 条） |
| `verify_hand_reorder` | **手牌拖拽重排 P7**（自动排列回归锁 / move_card 边界 / 拖拽落库 / 按钮 card meta 对应 / 手动模式不打回按序 / 抽牌追加末尾 / 选中索引跟随对象 / 拖出区外取消 / 插入槽判定 / 顺序签名 / 按序恢复 / 补发 pressed 被吞 / 18 张布局）（44 条） |
| `verify_motion` | **页面淡入**（同色底 / 目标页 modulate / visible 同步 / 中途切换）/ **按钮缩放**（pivot、1.05、0.96、禁用不缩放、单补间、悬停发光）/ **结束页入场**（子节点淡入 / 上浮基准不累积）/ **卡牌字号**（28 / 14，紧凑 21 / 12，互不重叠）（53 条） |
| `verify_hand_runtime` | 真实手牌渲染与点击流程 |
| `verify_hint` | 提示引擎与「提示」按钮（建议合法性交叉验证；F+Cl 只建议族炸） |
| `verify_halogen` | **卤族互化 P9**（引擎 -7 / F+Cl 族炸不误伤 / 提示不给 ClF / AI 读开关 / UI 预检 / 教程默认禁止） |
| `verify_element_limit` | **元素限制 P10**（前 20 号 20 种 134 张 / 扩展池 7+2 / 牌库过滤 / 越界牌 -8 / 族炸不误伤 / 教程强制全量 / 小页 4 开关 + 9 chip + 统计 / 勾 chip 自动开限制 / 开局写入）（55 条） |
| `verify_start_page` | 开始页人数/AI 联动、补充规则小页（入口 → 4 开关 + 元素池 → 帮助页）、卡片不重叠 |
| `verify_end_page` | **结束页 / 教学页 P8**（同套装饰零件 / 结算卡圆角与阴影 / 按钮三件套 / 四态标题与状态条配色 / 三统计块取数 / 按钮文案与去向 / 教学页整卡按钮 / turn_count 归零与自增 / 重复展示不重播动画）（105 条） |
| `verify_integration` | 端到端对局 |
| `verify_constraint` | 化合价与牌型约束 |
| `verify_logger` | 日志转发 |
| `verify_organic` | 有机物胜利规则 |
| `verify_refactor` | 模块拆分回归 |
| `verify_sequence` / `verify_sequence_table` | 顺序牌型与桌面判定 |
| `verify_tutorial` | 教程关卡状态机 |
| `verify_ai_discard` | 手牌上限自动弃牌 |
| `verify_help_page` | **帮助中心 P5**（结构 / Tab 懒加载 / 2 列卡片 + 7 列图鉴 / 字号 ≥11 / 无空格对齐 / 29 种 182 张 / 旧页备份）（57 条） |

> 已知非缺陷：测试进程退出时固定报 `572 ObjectDB instances were leaked at exit`，在 P3 之前的
> `88cfe60` 上同样存在（已用 `git stash` 做过基线对比），与本轮改动无关。

---

## 6. 美术升级方向核对（2026-10-30）

对照桌面的《化学碰撞美术升级方向》（3053 字，后半段被截断，待使用者补全），逐节核对当前实现：

| 文档节 | 内容 | 进度 | 说明 |
|---|---|---|---|
| §2 色板 | 主背景 `#E6F0FA` / 卡牌 `#F8F9FC` / 状态栏·按钮 `#2C3E50` / 警示 `#E74C3C` | ✅ | 与设计稿同值 |
| §2 色板 | 族炸 `#E67E22` / 成功 `#27AE60` / 金属金 `#D4AF37` / 非金属 `#3498DB` / 准金属·稀有气体 `#9B59B6`·`#BDC3C7` | ❌ | 全代码无这些值；当前沿用 P1 族色规则（文档允许元素符号着色豁免） |
| §3 字体 | Roboto Slab / Noto Serif / Source Code Pro / Noto Sans SC | — | 文档自注「暂不考虑加入」，现无自定义字体与 Theme |
| §4.1 卡牌 | 95×118 手牌 / 72×90 迷你卡 / 迷你卡半透明圆角 | ✅ | 迷你卡 alpha 0.92 |
| §4.1 卡牌 | 内阴影 + 磨砂纹理 / 横向微渐变 | ❌ | 纯 `StyleBoxFlat` 平涂，无贴图 |
| §4.2 字号 | 元素符号 28 / 中文名 14 | ✅ | P3 完成（见 §4.1） |
| §4.2 字号 | 化合价「圆底标签」/ 族符号用族主题色 / 序数加粗 | ❌ | 纯文字；族色与 P1「固定深灰」结论冲突；加粗需字体变体 |
| §4.2 交互 | 悬停亮蓝边 + 上浮 | ✅ | P1.x 状态机 |
| §4.2 交互 | 悬停「轻微放大」/ 选中放大至 105×130 | ❌ | 手牌不走 `_mkb()`，未接缩放；全文件无 `scale` |
| §4.3 稀有元素 | 卤族光晕 / 过渡金属金线 / 人造元素水印 | ❌ | 牌库仅前四周期天然元素，人造元素项无对象 |
| §5.1 状态栏 | `#2C3E50` 60px + 白字 + 内容顺序 | ✅ | 缺头像（无素材） |
| §5.2 桌面区 | 「出牌展示区背景框」 | ❌ | 仅 `TableLabel` 文字 + 小卡 |
| §5.2 日志 | 仅最近 3 条 + 小号 + 半透明底 | △ | `MAX_LOG_LINES = 6`、13px、无底色 |
| §5.3 手牌 | 重叠排列 / 与操作面板衔接 | ✅ | 已优于要求（自动叠卡 + 紧凑牌面） |
| §5.3 手牌 | 悬停「自动展开」邻近牌 | ❌ | 只上浮 |
| §5.4 按钮 | 禁用半透明 | ✅ | alpha 0.35 |
| §5.4 按钮 | 悬停发光 + 缩放 | ✅ | P3 完成（半透明阴影发光 + 1.05 / 0.96） |
| §5.4 按钮 | 圆角 6px / 图标 + 文字 | ❌ | 统一 8px；纯文字 |
| §5.5 教程 | 气泡对话框 + 三角箭头 | ❌ | 纯文本 `TutorialLabel`（位置已在右上） |
| §5.6 帮助 | 卡片式容器 + 图鉴缩略图网格 | ❌ | 仍是 4 栏纯 `Label` |
| §6 图标装饰 | 5 个功能图标 / 四角仪器轮廓 + 周期表网格 / 旋转原子核指示器 | ❌ | 全无；当前用 `▶` 文字标记当前玩家 |
| §7.1 动效 | 出牌 / 抽牌 / 弃牌 | ❌ | 无 |
| §7.2 动效 | 牌型揭示 / 族炸特效 / 化合物聚光 | ❌ | 无 |
| §7.3 动效 | 页面切换淡入淡出 | ✅ | P3 完成（淡入 220ms，`visible` 保持同步） |
| §7.4 动效 | 按钮悬停 1.05 / 点击 0.95 | ✅ | P3 完成（按下取 0.96） |
| §8 音频 | BGM 3 首 / SFX 8 个 / 音频管理 | ❌ | 项目内 0 个音频文件、无 `AudioStreamPlayer`、无 bus 布局 |

### 6.1 待拍板的冲突

1. **§4.2 族符号用族主题色** ↔ P1 已改固定深灰（稀有气体族色近白，白牌上看不见）。建议保留现状，或改为「族色加深 40%」后再用。
2. **§4.2 元素符号 28px** ↔ 已实现（P3）；若真实截图显示挤压，优先微调 `CardName` 位置而不是回退符号字号。
3. **§5.2 日志 3 条** ↔ 现 6 条（P1 为提高信息量设定），降为 3 条会丢回合信息，需确认。
4. **§5.4 按钮圆角 6px** ↔ 工厂统一 8px；可加 `BUTTON_RADIUS` 常量做单点改动，不影响其它 kind。
5. **§4.1 卡牌内阴影 / 磨砂纹理** ↔ `StyleBoxFlat` 不支持内阴影，需「外框 + 内衬」双层 stylebox 或九宫格贴图（依赖美术资源）。

### 6.2 建议排期

- **批次 A（纯代码，可继续推进）**：出牌 / 抽牌 / 弃牌「幽灵牌」动画、牌型揭示文字动效、日志 3 条、
  化合价圆底标签、按钮圆角常量、手牌悬停与选中缩放。
  > 关键技术点：桌面槽位坐标由 `_update_table_label()` 动态计算，手牌重建会立刻触发 `_layout_hand_cards()` 重排 ——
  > 位移动画必须用**独立于容器的幽灵节点**，动画结束才真正刷新 UI，否则会与重排打架
  > （R3 已踩过该坑，`_kill_hover_tween()` / `btn_scale_tween` 是现成的「每对象一补间」模式）。
- **批次 B（需美术 / 音频资源）**：5 个功能图标、四角仪器轮廓 + 周期表网格、卡牌纹理与内阴影、
  族炸全屏光晕 + 震屏、化合物原子聚合、BGM + SFX。
  > 音频需先确认是否允许提交 ogg 资源；项目当前无 `default_bus_layout.tres`，需要新建 BGM / SFX 两条总线。

---

## 7. P5 完成清单（帮助中心重构，Plan B 新手向）

**问题**：3 个独立帮助页（`Main.tscn:404-616`）被用户评为"看不懂"——
4 栏横排 1112px 挤在一屏、正文字号 11/12px、用空格对齐列（比例字体下必然错位）、
`□` 被误读成复选框、5 种前缀符号同一字号堆叠、按钮是默认灰底、
三页返回按钮坐标各不相同、规则与补充内容互相重复，且数据写错（28 种 / 172 张）。

**方案**：合并为 **1 个 HelpPage**，3 个 Tab（游戏规则 / 卡牌图鉴 / 补充规则）+ 滚动容器 + 卡片布局。

| 改动 | 位置 | 要点 |
|---|---|---|
| `HelpContent.gd`（新增 290 行） | `scripts/` | 3 个 Tab 的纯数据：9 张规则卡、4 张图鉴卡 + 元素派生、4 张补充卡；行样式 `sub/p/li/ex/warn/gap/demo` |
| `_build_help_page()` + 14 个辅助函数（新增约 460 行） | `scripts/GameUI.gd` §五之二 | 标题栏 56px `#2C3E50` / Tab 栏 48px 白底 + 选中 3px 蓝下划线 / 3 个 ScrollContainer / 2 列卡片 / 7 列图鉴网格 / 懒加载 |
| 旧 3 页引用全删 | `scripts/GameUI.gd` | 9 个按钮变量 + 3 处 `get_node` + 9 处 `visible=false` 全部收敛成 `help_page` |
| `tab_on` / `tab_off` 两种 stylebox | `_make_panel_style()` | 遵守"样式唯一来源"，不手写 StyleBoxFlat |
| 牌库数字修正 | `HelpContent.gd` / `CardDatabase.gd:22` | 28 种 / 172 张 → **29 种 / 182 张**，且改为从 `CardDatabase` 派生，不再硬编码 |
| `verify_help_page.gd`（新增） | `tests/` | 57 条断言 |

**排版规则**（治"空格对齐"和"字号过小"）：

| 层级 | 表现 |
|---|---|
| 卡片标题 | 17px `#2C3E50` + 左侧 4px 强调色条 + 1px 分隔线 |
| 小标题 | 15px `#2C3E50`，无前缀 |
| 正文 / 条目 | 14px `#2B3340`；条目自动加「· 」，缩进 4 |
| 示例 / 化学式 | 13px `#6B7280`，缩进 14 |
| 警示 | 14px `#C0392B`，自动加「⚠ 」 |
| 列对齐 | **一律用 `GridContainer` / `HBoxContainer` 布局**，不再用连续空格 |
| 字号下限 | 帮助页任何文字 ≥ 11px（测试锁死） |

**刻意不做**：

- ~~不改 `Main.tscn`（旧 3 页原样保留，`visible=false`，作为文案校对备份；确认无需回查后可整段删除）~~

---

## 9. P7 完成清单（手牌拖拽重排）

**问题**：手牌顺序完全由系统决定（每次刷新强制按原子序数升序），玩家没法按自己的思路整理；
同时 `selected_indices` 只存下标，顺序一变（抽牌后自动排序 / 重排）选中就会指向另一张牌。

**方案**：拖动换位 + 一次拖动转入手动排列 + 「按序 ⇅」恢复自动排序；顺序的唯一真源是 `PlayerInfo.hand`。

| 改动 | 位置 | 要点 |
|---|---|---|
| `hand_manual_order` + `move_card()` | `PlayerManager.PlayerInfo` | 手动模式标志；`move_card` = `remove_at` + `insert`，成功即进入手动模式 |
| `sort_hand_by_atomic_number(force := false)` | 同上 | 手动模式下直接 return → `GameManager` / `TutorialController` 既有调用点零改动 |
| 拖拽状态机 | `GameUI.gd` §十二之二 | `_process → _update_hand_drag()` 轮询 + 6px 阈值；幽灵牌 + 插入线（`Z_DRAG = 30`）；松手落库、拖出区外取消 |
| 「按序 ⇅」按钮 | `GameUI.gd` §八之三 | 仅手动模式显示，位置 (704, 528)，与 CardInfoLabel / HintButton / 日志栏均不重叠；点击走 `force = true` 并退回自动模式 |
| 选中索引 → 卡片对象 | `GameUI._selected_cards()` / `_remap_selection()` | 按钮 `set_meta("card", card)`；重建前用**旧按钮的 meta** 取对象（必须早于 `hand_buttons.clear()`），排序后再用 `hand.find()` 重算索引 |
| 提示作废 | `_hint_order_sig` | 顺序签名一变就作废 `_hint_text`，避免「提示的牌」与「高亮的牌」错位 |
| `verify_hand_reorder.gd`（新增） | `tests/` | 44 条断言，含「自动排列回归锁」 |

**为什么不用 `gui_input`**：`accept_event()` 只阻止事件继续传给**其他**控件，同一个 Button 的
`_gui_input` 仍会执行并在松手时补发 `pressed`，结果就是「拖完顺手把牌选中」。改用轮询 +
`_drag_suppress_click`，并在松手后 `call_deferred` 清除标志（pressed 与实际 `_process` 的先后顺序不确定）。

**刻意不做**：纵向拖到桌面出牌（会误触出牌流程）、拖拽排序补间动画（整排重绘是瞬时的，补间会与重建打架）、
AI 手牌顺序记忆（AI 不需要）、拖动时自动滚动手牌（单行且全部可见）。

**验收**：16 个测试套件全绿（新增 `verify_hand_reorder` 44 条）；真实窗口 `--quit-after 240` 与
真实窗口跑 `verify_hand_reorder` 均无 ERROR/WARNING。
  → P6 已按该注记整段删除（见 §8）
- 不引入切 Tab 动画（避免与 `verify_motion` 的"切 Tab 不淡入"断言冲突）
- 不给图鉴迷你卡加 hover / 点击交互（图鉴是查阅用的静态页）

**验收**：13 个测试套件全绿（新增 `verify_help_page` 57 条）；真实窗口 `--quit-after 240` 无 ERROR/WARNING；

---

## 8. P6 完成清单（提示按钮 / 开始页代码生成 / 旧帮助页清理）

**背景**：`HintButton` 原来是 `toggle_mode` 开关，`_on_hint_toggled()` 只是把
`CardInfoLabel` 换成 `GameManager.get_available_patterns()` 的一句摘要 —— 玩家看完仍要自己
从 8 张手牌里挑牌、再逐级点「出牌(选牌型) → 合成化合物 → 选化合价 → 确认打出」。
新手在第 4 步之前就放弃。同时 `Main.tscn` 里还留着 P5 废弃的 3 个帮助页节点（589 行死数据），
开始页的 11 个静态子节点也不支持任何装饰/动效。

### 8.1 提示按钮（方案 C：自动选牌 + 解释）

新增 `scripts/HintAdvisor.gd`（约 440 行，全 `static`、**只读**，不碰任何玩家/牌状态）：

| 对外接口 | 说明 |
|---|---|
| `suggest(gm) -> Dictionary` | 返回 `{indices, pattern, valence, organic, label, text}`；无解返回 `{}` |
| `is_playable(gm, indices) -> bool` | 一组手牌下标此刻能否打出（与 `suggest` 共用 `_check`） |
| `compound_valence_for(cards) -> Dictionary` | 给 UI 面板用的 `{symbol: ±价}`（2 元素一正一负 / 3+ 元素总电荷 0） |

候选覆盖：单张单质 / 双原子单质 / 族炸（整族 + 每种少一张的变体）/ 顺序（仅规则开启时）/
有机物（CH4、C2H6、C3H8、一卤代、含氧 5 种模板）/ 化合物（2 元素按 gcd 配平、3 元素每种 1 张且电荷为 0）。
评分：能赢 1000 > 有机物 900 > 族炸 400 > 化合物 300 > 单质 100 > 顺序 50，同档张数多者优先。

**`_check()` 逐条对齐 `GameManager.play_cards()`**（这是本方案成立的前提，注释里逐段标注了对应行）：

| play_cards 的检查 | `_check` 的对应实现 |
|---|---|
| `skip_bomb = cv.size()>=2 or cv.has("_organic")` | 同式推导，再 `detect_pattern(cards, skip_bomb, prefer_sequence)` |
| `intended_pattern` 与检测结果必须一致（有机物可当化合物） | 同条件放行 `organic_rules_enabled and pattern==ORGANIC and intended==COMPOUND` |
| 顺序指定牌型约束（起始者/桌面玩家豁免） | 同条件（含「指定化合物时有机物也算」） |
| 桌面单质只能接单质、桌面化合物只能接化合物、接炸链只能出族炸 | 同条件 |
| 比大小 `compare_cards(...) <= 0 → -2` | 同条件（桌面是顺序时跳过比较） |
| 化合物 `ratio_ok` 校验 | 同条件（`get_compound_formula` 的 `ratio_ok`） |

> 关键坑：`table_pattern == COMPOUND` 时 `pattern != COMPOUND` 会被 `play_cards` 判 `-4`，
> 有机物（`ORGANIC`）同样被拒 —— 提示必须照样过滤，否则玩家照着点会「非法出牌」。

GameUI 侧（`_on_hint_toggled` 重写）：

1. 点一下 → `suggest()` → 自动写 `selected_indices`，化合物再把 `compound_selections` 填好
2. `step_mode` 直接推到能出牌的那一步（化合物 = 2「确认打出」，其余 = 1「选牌型」）
3. `_hint_text` 存进信息栏，`_update_card_info_label()` 优先显示它（`_hint_owner` / `_hint_hand_size` 变化即作废）
4. 动牌（`_on_card_clicked`）/ 返回（`_on_back`）/ 出牌后（`_step_reset`）自动 `_clear_hint()`
   并把 `hint_button` 复位（`set_pressed_no_signal(false)`，否则下次点击会先触发「取消」）
5. 无解时给「建议跳过 / 弃牌」而不是沉默

### 8.2 开始页改为代码生成 + 装饰美术

- `Main.tscn` 的 `StartPage` 只剩空容器（删除 173 行静态子节点），全部由 `_build_start_page()` 生成，
  **节点名与旧场景完全一致**（`StartButton` / `PlayerCountSpin` / `AiCountSpin` / `OrganicCheckBox` /
  `SequenceCheckBox` / `TutorialBtn` / `ExitButton` / `SupplementaryHelpBtn`）
- ⚠ **节点名一致不等于路径一致**（P6 收尾修复）：人数框 / AI 框 / 两个规则开关 / 补充规则入口都被
  放进了 `SettingsCard` 卡片内，而绑定代码当时仍按「StartPage 直接子节点」取值 → 全部拿到 `null`
  且静默失效。现在统一走 `_start_child(name)`（`find_child(name, true, false)` 递归查找），
  并新增 `tests/verify_start_page.gd` 把这个层级契约锁住
- 美术全部程序化，不依赖图片：45° `GradientTexture2D` 渐变带、5 处元素水印（H2O/CO2/NaCl/CH4/O2）、
  5 张倾斜装饰牌（真实元素配色 + 原子序数 + 中文名 + 原子量）
- 交互层次：主按钮（主题蓝实心）/ 次级按钮（白底蓝边）/ 幽灵按钮（透明底灰字）三级
- 规则开关从 `CheckBox` 换成 `Button(toggle_mode)`：未选白底灰边、选中主题蓝底白字 + 左侧 4px 强调条
  （`button_pressed` / `toggled` 语义与 `CheckBox` 一致，`_init_game()` 读状态不用改）
- 勾选反馈落在新增的 `StartRuleHint`（2 秒淡出）：开始页看不到 `GamePage` 的 `InfoLabel`
- 入场：10 个元素错峰淡入（`modulate:a` + 上移 14px，每级 50ms 间隔）；装饰牌 5 个正弦浮动循环
  —— **只动子节点，绝不碰 `start_page.modulate`**（`verify_motion` 锁死了页面级淡入语义）
- tween 全部由 `start_page` / `card` / `label` 创建（`node.create_tween()`），节点释放即自动回收

### 8.3 旧帮助页节点删除

`Main.tscn` 删除 `HelpPage_Rules` / `HelpPage_Cards` / `HelpPage_Supp` 共 589 行（P5 的校对备份），
`verify_help_page.gd` 的断言由「旧页仍在树中且隐藏」改为「旧页已从 Main.tscn 删除」。

### 8.4 验收

| 项 | 结果 |
|---|---|
| `tests/verify_hint.gd`（新增，105 条） | 全部通过：每条建议都用**新 GM 再调一次 `play_cards`** 交叉验证，覆盖单质/双原子/NaCl/CaCl2/NaOH/CH4/族炸/顺序/桌面限制/无解 |
| 13 个测试套件 | 全绿（`ALL HINT TESTS PASSED` 等 13 行，0 FAILED） |
| 真实窗口 `--quit-after 240` | 无 ERROR / WARNING |
| `--check-only` | `HintAdvisor.gd` / `GameUI.gd` / `verify_hint.gd` 均无解析错误 |

> 已知非缺陷：`verify_tutorial` 退出时报 `5 resources still in use`，`--verbose` 显示是
> `CardData / CardDatabase / GameLogger / TutorialController / GameManager` 五个 GDScript 常驻缓存，
> 与本轮改动的 tween 无关。

6 张真实截图（3 Tab 顶部 + 滚动到底）逐张核对排版。

### 8.5 P6 收尾修复（试玩反馈的 3 个问题）

| 现象 | 根因 | 修法 |
|---|---|---|
| 帮助页「看三张典型牌」第 4 行显示 `×6 / ×8 / ×10`，与同卡文案「其下依次是中文名、常见化合价」矛盾 | `_make_help_mini_card()` 原本只服务 29 种元素网格（那里确实该显示牌库张数），被示例行复用后语义串了 | 加 `show_valence` 参数：示例行传 `true` → `_help_valence_text()`（`+1 / -2 / -1 +1…`，最多 2 个价态 + 「…」防溢出 96px 卡宽）；网格保持 `×N` |
| 开始页「查看补充规则 >」点了没反应 | `SupplementaryHelpBtn` 嵌在 `SettingsCard` 内，`start_page.get_node_or_null()` 取不到 → 信号根本没连上 | 统一改 `_start_child()`（`find_child(name, true, false)`）递归查找 |
| 人数怎么填都能开局，且永远 3 AI / 1 人类 | 同源：`player_spin` / `ai_spin` 为 `null` → `_on_start_game()` 走兜底 `4 / 3`；`OrganicCheckBox` / `SequenceCheckBox`（P9 起再加 `HalogenCheckBox`）同样为 `null`，三条补充规则开关也一起失效 | 同一个 `_start_child()` 修复；另加 **`1 ≤ AI ≤ 总人数 - 1`** 联动：`_on_player_count_changed()` 压 `ai_spin.max_value` 并用 `StartRuleHint` 告知，`_on_start_game()` 再对上下限各 clamp 一次兜底（AI=0 时其余座位是没人操作的人类，会直接卡死，故下限 1） |

附带修复：`_start_flash_rule_hint()` 里的 `get_meta("tween", null)` 在 Godot 中等同单参数调用，
meta 不存在时会刷 `ERROR`；改为 `has_meta()` 判定，并给 `StartRuleHint` 加颜色参数。

验收：新增 `tests/verify_start_page.gd`（30 条断言）全绿；14 个测试套件全绿、0 FAILED；
真实窗口 `--resolution 1152x648 --quit-after 300` 无 ERROR / WARNING。

### 8.6 补充规则复查（同类问题排查）

两条补充规则（有机物胜利 / 顺序牌型）走的就是 8.5 里修好的同一条 `_start_child()` 链路，
逐项核对后**功能侧无死链**：

| 环节 | 实现位置 | 结论 |
|---|---|---|
| 开关 → 开局写入 | `GameUI._init_game()` → `organic_rules_enabled` / `sequence_rules_enabled` | ✅ 两条开关互不影响 |
| 有机物打出即胜 | `GameManager.play_cards()` 有机物分支 | ✅ |
| 顺序 → 方向反转 | `direction_clockwise = not direction_clockwise` | ✅ 顺/逆时针提示同步 |
| 顺序 → 指定牌型 | `play_cards()` 返回 `1` → `GameUI` 弹「单质 / 化合物 / 族炸」三选框 | ✅ |
| 未按指定牌型出 | `player_fail_sequence_constraint()`：罚抽 2 张 + `has_passed` + 约束解除 | ✅ |
| 族炸打断 | 族炸分支 `sequence_constraint_active = false`，接炸链照常 | ✅ |
| 游戏页规则提示 | `get_organic_rules_enabled()` / `get_sequence_rules_enabled()` 拼信息栏 | ✅ |

唯一残留的是**文案**（和第 1 个问题同类型：写的东西界面上不存在）：

- 帮助 Tab3 两张卡都写「需在开始页勾选『规则补充』」，但 P6 开始页早已拆成
  「有机物胜利规则」/「顺序牌型规则」两个独立开关，界面上找不到「规则补充」这个复选框
  → 改为指向真实开关名
- 「顺序牌型」卡写「打出后桌面清空」，实际是 `table_pattern = SEQUENCE`（牌权被抢、
  不再比大小），桌面仍会展示刚打出的顺序牌 → 改为「打出后抢走牌权（不比大小）」

回归锁：`verify_help_page.gd` 新增 3 条断言（文案不含「规则补充」、必须指向两个真实开关名、
不含「桌面清空」）；`verify_start_page.gd` 新增各 1 条（只勾有机物时顺序仍关闭 / 只勾顺序时
有机物仍关闭）。

---

## 10. P8 完成清单（结束页 / 教学引导页画风统一）

**动机**：开始页在 P6 已经重做成「同色底 + 45° 渐变带 + 元素水印 + 倾斜装饰牌 + 白卡」，
结束页却还是 4 个 Label + 1 个默认灰按钮（连 hover 都没有），教学页是 11 个散落的 Label / Button 平铺。
三页同属「游戏外壳」，画风不能分裂。

**方案（B 档）**：不追求炫技，先把三页拉到同一条基准线 —— 状态条 + 标题 + 3 个统计块 + 按钮组。

| 页面 | 结构 |
|---|---|
| 结束页 | 640×420 白卡（圆角 8 + 阴影 + 96% 不透明）+ 顶部 6px 状态条 + 标题 36 + 描述 18 + 分隔线 + 3 个统计块（172×76：总回合 / 剩余牌库 / 剩余手牌）+ 主 / 次 / 幽灵三按钮 + 规则回顾 |
| 教学页 | 标题 40 + 副标题 16 + 72×4 强调条 + 3 张 720×104 关卡卡（48 蓝色序号块 / 20 标题 / 14 描述 / 15「开始 →」）+ 返回 |

**关键决策**

| 决策 | 原因 |
|---|---|
| 三页共用 `_page_backdrop()` 与按钮三件套 `_page_primary_btn` / `_secondary` / `_ghost` | 一份样式来源；开始页的 `_start_make_*` 退化成薄壳，视觉零变化 |
| 骨架 `_build_end_page()` / `_build_tutorial_page()` 只建一次，`_fill_end_page()` 只填数据 | `_show_end_page()` 被 `_refresh_ui()` 反复调用，重建会丢焦点、装饰牌浮动重启 |
| 状态条按四态换色（主题蓝 / 深灰 / 中性灰 / 警示红） | 不加图标也能一眼区分胜负 / 退出 / 失败 |
| 统计块数字 26px 主题蓝、标签 13px 灰 | 与开始页「29 种元素 · 182 张牌」同档，最小字号守住 13 |
| 关卡卡整卡即 Button，hover 只改描边 / 阴影 /「开始 →」颜色 | 720 宽做 1.05 缩放会顶到装饰牌；整卡可点比 96px 小按钮好点太多 |
| 主按钮文案与去向随模式切换（返回主页 / 返回关卡），次按钮（再来一局 / 再试一次） | 教程局结束后应回关卡列表，而不是回开始页 |
| `turn_count` 放进 GameManager，`next_turn()` 自增 | 结算页要显示「总回合」，界面层不该自己数 |
| `_animate_page_intro` 把目标 y 记在节点 meta `intro_base_y` | 修掉反复进入结束页时 +14 累积偏移的真 bug |

**顺带修掉的 3 个真 bug**（都属于「节点名在、路径不在」或「漏关另一页」）

1. `_setup_pages()` 仍在结束页根下取 `EndLabel` / `EndButton`，P8 后它们在 `EndCard` 里 → 拿到 null，
   结束页文案与按钮连接全部失效（`verify_end_page` 的「退出态标题」一条直接抓到）。
2. `_show_end_page()` 原来只在教程局关 `TutorialPage`；而 `TutorialPage` 排在 `EndPage` 之后，
   从开始页点「教学引导」再开局结束时，整块关卡列表会盖住结算卡（截图核对时发现）。
3. 退出态原本只改状态条颜色，标题仍是「游戏结束」、描述复读自定义文案 → 改为
   「游戏已退出 / 本局未分胜负，随时再来一局」，失败态描述写「请返回主页重新开始」。

**验收**：17 个测试套件全绿（新增 `verify_end_page` 105 条；`verify_motion` 44 → 53 条）；
真实窗口 `--quit-after 240` 无 ERROR / WARNING；开始页 / 教学页 / 胜利结算 / 教程局退出 4 张截图逐一核对，
三页的渐变带走向、水印位置、卡片圆角与阴影、按钮高度均一致。

---

### 8.6 P9 卤族互化统一到引擎（B 方案）

**问题**：禁止卤族互化只在「合成化合物」按钮里拦（`GameUI._is_halogen_only()`），
「提示」按钮（`HintAdvisor`）与 AI 的两元素化合物路径都能打出 ClF（F 只有 −1 价、Cl 含 +1 价）。

**方案（B）：只拦化合物，族炸始终合法**

| 位置 | 改动 |
|---|---|
| `GameManager` | 新增 `halogen_exchange_allowed`（默认 false）+ `is_halogen_mix(cards)`；`play_cards()` 在 `pattern == COMPOUND` 时返回 `-7`；`init_tutorial()` 复位 |
| `GameUI` | `_handle_result()` 显示 `-7` 文案；`_on_choose_compound()` 改成读开关；开始页新增 `HalogenCheckBox`「允许卤族互化」（`(32,168)` 宽 270），`SupplementaryHelpBtn` 移到 `(318,168)` 宽 240；信息栏与结算页「本局规则」同步 |
| `AIPlayer` | 两元素化合物循环读开关；`_pair_valences()` 增加「遍历常见价找一正一负」兜底，开关打开后可合成 ClF |
| `HintAdvisor` | `_compound_candidates()` 跳过纯卤素候选，`_check()` 加同一判定；族炸候选保留 |
| `HelpContent` | 补充规则 Tab 新增「允许卤族互化」卡；「卤族特例」卡补「族炸不受限 / 可开关放行」 |

**为什么不能挂在「含两种卤素」上**：`detect_pattern([F,Cl])` 默认走族炸，
只有带 `cv`（`skip_bomb`）时才成 COMPOUND —— 判定必须依赖 `pattern == COMPOUND`，否则会误伤族炸。

**验收**：18 个测试套件全绿（新增 `verify_halogen`；`verify_hint` / `verify_start_page` /
`verify_help_page` / `verify_tutorial` 各加断言）。

---

### 8.7 P10 元素限制 + 补充规则合成一小页

**问题**：P9 之后 `SettingsCard`（620×210）里已有 3 个开关 + 入口，再加第 4 条「元素限制」
放不下（第 4 个开关只能压到卡外或挤掉人数框）；同时补充规则分散在「开关 + 帮助页」两处，
玩家看不到"这局到底开了几条"。

**方案：4 条补充规则收进 `SuppRulesPage` 小页，设置卡只留入口 + 一行摘要**

| 区域 | 位置 / 尺寸 | 内容 |
|---|---|---|
| 设置卡入口 | `SupplementaryHelpBtn` (32,128) 300×34 + `SuppRulesSummary` (32,170) 556×20 | "补充规则 · N 项已开启 ▸" + "已启用：有机物 · 顺序…" |
| 小页标题 | (0,62) 1152×46 + 副标题 (0,110) | 「补充规则」/「默认全部关闭；勾选后仅对下一局生效」 |
| 规则卡 ×4 | 2×2：(46,146) (586,146) (46,250) (586,250)，每张 520×92 | toggle（484×34）+ 13px 说明；节点名沿用 `OrganicCheckBox` / `SequenceCheckBox` / `HalogenCheckBox` / `ElementLimitCheckBox` |
| 元素池 | `ElementPoolPanel` (46,356) 1060×168 | 标题 + `ElementPoolStats` 统计（"21 种 · 138 张 ｜ 额外元素：Fe"）+ 9 个 chip（132×34，7 个/行：Cr Mn Fe Co Ni Cu Zn + Br I） |
| 底部 | `SuppRulesHelpBtn` (46,570) 240×34 / `SuppRulesDoneBtn` (846,566) 260×44 | 跳帮助中心 Tab3 / 关闭小页 |

**元素限制规则**：默认关闭（29 种 182 张）；打开后牌库 = 前 20 号（H~Ca，20 种 134 张）+
勾选的扩展元素（副族 7 种各 4 张、Br/I 各 10 张）。9 个扩展全勾回落到 182 张，与老玩法完全一致。

| 位置 | 改动 |
|---|---|
| `CardDatabase` | `get_copies()` 抽出张数分级（`HelpContent` 改为委托）；`get_atomic_number()` / `get_base_element_symbols()` / `get_optional_elements()`（序数 >20 自动派生）/ `get_allowed_symbols()` / `get_deck_size()`；`generate_deck(allowed_symbols = [])` |
| `GameManager` | `element_limit_enabled` + `allowed_extra_elements`；`is_element_allowed()` / `get_allowed_symbols()` / `get_allowed_element_count()` / `get_deck_size()`；牌库按允许集合生成；`play_cards()` 越界牌返回 `-8`；`init_tutorial()` 强制关闭（预设手牌含 Fe） |
| `GameUI` | `_build_supp_rules_page()` / `_supp_rule_card()` / `_build_element_pool()`；`_sync_supp_rules_summary()` 统一出口（入口文字 / 摘要 / 统计 / chip 压暗）；勾 chip 自动开限制；`_init_game()` 写入；信息栏与结算页加元素种数；`-8` 文案 |
| `HelpContent` | 补充规则 Tab 新增「元素限制」卡（Tab2 5 → 6 张） |

**为什么 chip 不做 disabled**：限制关闭时把 chip 置灰但可点，点一下就自动打开「元素限制」——
省掉"先开开关再选元素"的两步，也避免玩家勾了元素却没生效（旧版最容易踩的静默失效）。

**验收**：19 个测试套件全绿（新增 `verify_element_limit` 55 条；`verify_start_page` 改走小页路径 +
`verify_help_page` Tab2 6 卡 + 元素限制文案断言）。
