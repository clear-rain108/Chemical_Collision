# UI 视觉打磨推进计划

> **最后更新**: 2026-11-04  
> **当前状态**: P1 / P1.x / P2 / P3 / P5 / P6 / P7 / P8 / P9 / P10 / P10.1 / P11 完成；移动端触屏 A1/B/C 与 v14.5 第零关反馈修复已落地（见 ARCHITECTURE §12）。**未展开**：P4《美术升级方向》其余条目（核对结果见 §6）  
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
| **P9** | 卤族互化统一到引擎（B 方案：规则只写在 `play_cards()`，F+Cl 作族炸始终合法） | ✅ 完成（见 §8.6；ARCHITECTURE §5.2） |
| **P10 / P10.1** | 元素限制（前 20 号 + 可勾选扩展）+ 4 条补充规则合成一小页 + chip 紧凑化 | ✅ 完成（见 §8.7） |
| **P11** | 游戏页工具按钮统一画风（`_style_game_tool_buttons()` 接管样式 + 几何归一） | ✅ 完成（见 §8.8） |
| **P12** | 化学规则收口：假化合物拦截 + 顺序约束只作用于被指定玩家（非 UI 改动） | ✅ 完成（2026-11-04；见 GAMEPLAY_RULES §9 / §16.2、COMPOUND_MECHANISM_COMPARISON §6） |
| **批次 A** | P4 批次 A 的纯代码条目：F1 多价元素卡面溢出 / F2 触屏拖拽死区 / A1 按钮·日志·价态 chip / A2 手牌·桌面动效 / A3 出牌·抽牌·弃牌动画 | 🚧 进行中（F1 ✅ / F2 ✅，见 §13） |
| **P4** | 美术升级方向文档的其余条目（卡牌重绘 / 字体 / 图标 / 音频 / A5 悬停与选中放大） | ⏳ 未展开（§6 核对表 22 项：✅9 / △1 / ❌12；按 §6.2 分批次 A（纯代码）/ 批次 B（需素材）推进） |

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

27 个自动化测试（全部在 `--headless` 下运行，无 FAIL 即通过）：

```bat
set GD=D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe
for %f in (ai_discard clan_bomb_cooling compound_chemistry constraint element_limit end_page halogen hand_layout hand_reorder hand_runtime hand_view help_page hint integration logger motion net_foundation organic refactor sequence sequence_lock sequence_table start_page tool_buttons touch_ui tutorial tutorial_layout) do (
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
| `verify_compound_chemistry` | **化学规则 P12**（`get_valence_pairs` 价态裁决 / NCl·BrN·IN 拒绝 / NCl₃·NI₃·BCl₃·ClF 保留 / Fe 1 张 + Cl 2 张只认 Fe(+2) / 引擎空式子与 `ratio_ok=false` 一律 -1 / 提示与 AI 同源）（38 条） |
| `verify_sequence_lock` | **顺序约束只锁被指定玩家**（set 时按反转方向选 target / 非 target 出牌不受限 / 跳过与弃牌罚抽 2 张 / 族炸与接炸链不解除 / 覆盖与快照 / state_hash 含 target）（52 条） |
| `verify_hand_view` / `verify_tool_buttons` / `verify_touch_ui` / `verify_tutorial_layout` / `verify_clan_bomb_cooling` / `verify_net_foundation` | 手牌视图 / 工具按钮几何与样式 / 触屏 A1·B·C（53 条，见 ARCHITECTURE §12.5）/ 教程提示框布局 / 族炸冷却 / 联机协议地基（54 条） |
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
| 「按序 ⇅」按钮 | `GameUI.gd` §八之三 | 仅手动模式显示，位置 **(338, 558) 112×32** —— P11 起并进游戏页工具行（与「显示提示 / 帮助 / 退出游戏」同基线、同高、间距 10），见 §8.8；点击走 `force = true` 并退回自动模式 |
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
| 未按指定牌型出 | `player_fail_sequence_constraint()`：罚抽 2 张 + `has_passed` + 约束解除 | ✅ 只对被指定的那名玩家生效 |
| 族炸打断 | ❌ 已修正：族炸**不再**解除顺序约束（`sequence_constraint_target` 只由该玩家自己出牌 / 跳过结算） | ✅ |
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
| 元素池 | `ElementPoolPanel` (46,356) 1060×168 | 标题 + `ElementPoolStats` 统计（"21 种 · 138 张 ｜ 额外元素：Fe"）+ 9 个 chip（104×28，**9 个一行**：Cr Mn Fe Co Ni Cu Zn Br I）+ 分隔线 + 固定池清单 `ElementPoolBase0/1`（前 20 号符号，数据取自 `CardDatabase`） |
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

#### P10.1 试玩反馈修复（chip 过大 + 编辑器诊断）

| 问题 | 处理 |
|---|---|
| 元素 chip 132×34、7 个一行（第 2 行只剩 Br/I），右侧与下方大片留白 | chip 收到 **104×28**、字号 15 → 13、内边距 12 → 10，9 个排成**一整行**（`x = 20 + i*112`，右边界 1020 ≤ 1020）；腾出的下半区改为「固定加入 · 前 20 号元素（H ~ Ca）」清单，由 `get_base_element_symbols()` 生成两行符号（`ElementPoolBase0/1`），后续新增元素自动跟随，不需要再改 UI |
| `chip.size = 104×28` 被夹回 270×32 | `custom_minimum_size` / `size` 必须在 `add_child()` **之后**设置：节点在树外时 `update_minimum_size()` 直接返回，`set_size()` 仍按旧的最小尺寸夹取 |
| 编辑器里一批红 / 黄诊断 | 红：`--check-only` 与 Godot 自带 LSP（`--lsp-port` + `textDocument/didOpen`）对 `GameManager` / `CardDatabase` / `HelpContent` 的诊断均为空，旧红是 godot-tools 缓存了磁盘中间状态；黄：GameUI 的 9 条真实警告逐条修掉——`INT_AS_ENUM_WITHOUT_CAST`×2（`align: int` → `HorizontalAlignment`）、`SHADOWED_VARIABLE`（小页 `help_btn` → `supp_help_btn`）、`SHADOWED_GLOBAL_IDENTIFIER`（`wrap` → `wrap_box`、`mini` → `mini_btn`）、`SHADOWED_VARIABLE_BASE_CLASS`（参数 `size` → `rect_size`）、`UNUSED_VARIABLE`（删掉未用的 `cp_idx`）、`INTEGER_DIVISION`×2（改 `int(x / 3.0)`）；另修 `GameManager.set_tutorial_level0_phase(phase)` 参数遮蔽成员 → `new_phase` |

---

### 8.8 P11 游戏页工具按钮统一（样式接管 + 几何归一）

**问题**：`GamePage` 的「显示提示 / 帮助 / 退出游戏」是全场**唯一没接管主题**的控件 ——
`Main.tscn` 里只有 `text` + `font_size = 13`，`GameUI.gd` 也从未给它们套样式，于是它们一直画 Godot
**默认主题**：灰 `#6B6B6B` 实底、4px 圆角、无描边、无阴影。旁边是「白卡 + 1px 中性边 + 8 圆角 + 软投影」
的卡片与「`#2C3E50` + 蓝光晕」的操作按钮 —— 三套语言挤在一屏。几何上三颗按钮的 y 分别是
567 / 568 / 569、宽 130 / 100 / 100、间距 8 / 9，基线不齐看着发飘。更实际的问题是「显示提示」是
`toggle_mode`，**开 / 关两态长得一模一样**，按下后玩家看不出提示到底生效没有。

**方案**：只做「样式接管 + 几何归一」，文本 / 信号 / 行为一律不动
（`_on_hint_toggled` / `_on_show_help` / `_on_quit_game` 原样保留）。

| 维度 | 改前 | 改后 |
|---|---|---|
| 底色 / 描边 / 圆角 / 阴影 | 引擎默认：`#6B6B6B` / 无 / 4px / 无 | `_make_panel_style("button")` 同源：`#2C3E50` / 1px `#668CB2` / 8px / 3px 软投影 |
| hover | 默认浅灰提亮，无光晕 | 与 `_mkb` 同参：`#455F80` 底 + 亮蓝边 + 6px 蓝色光晕 |
| pressed | 默认深灰 | 普通档 `#1F2B3B`；「显示提示」改 **主题蓝 `#2D7AB3` 实底**（= 开态） |
| hover_pressed | 无 | 「显示提示」开着再悬停 → 蓝色 `lightened(0.12)`，不闪回深蓝灰 |
| disabled | 默认灰 | 同色 35% 透明 |
| focus | 默认白框 | `StyleBoxEmpty`（点击后不再跳出画风的焦点环） |
| 字号 / 字色 | 13 / 默认 | 14 / 白（悬停、按下均白） |
| 「退出游戏」 | 与其它按钮同色 | **只**把 hover / pressed 转暖红（`BORDER_WARN` + 浅红底 + 红字）；静止态不变 —— 它是「结束本局进结算页」的半破坏性动作，不该和「帮助」抢注意力 |
| 几何 | y 567 / 568 / 569，130 / 100 / 100，间距 8 / 9 | 统一高 **32**、同一基线 **y=558**、间距 **10**、右边界 **x=820**；宽 132 / 96 / 112 |
| 悬停缩放 | 无（默认主题按钮不缩放） | 复用 `_attach_btn_motion()`：pivot 居中 + 1.05 / 0.96 |
| 「按序 ⇅」 | 单独一行 (704, 528) 112×30 | 并进同一行 (338, 558) 112×32 —— 手动排列模式下整行是 `[按序 ⇅][显示提示][帮助][退出游戏]` |

**为什么右边界钉在 820**：`HandContainer` 与 `CardInfoLabel` 的右边缘都是 820，`LogLabel` 从 824 起。
整行从右往左排（宽度改了三处常量也不会漂），上边留 32px（信息栏底边 526）、下边留 9px（出牌区顶边 599）。

**关键实现**

| 改动 | 位置 | 要点 |
|---|---|---|
| `TOOL_BTN_*` / `REORDER_BTN_*` / `TOOL_ROW_HL_*` | `GameUI.gd` §八之四 | 几何唯一来源；`TOOL_ROW_LEFT` / `REORDER_BTN_LEFT` / 教程高亮框都由右边界与宽度**推导** |
| `_style_game_tool_buttons()` | 同上，`_setup_pages()` 尾部调用 | 先排几何再上样式；三颗按钮走 `[button, width]` 表，加按钮只加一行 |
| `_style_tool_btn(b, is_toggle, danger)` | 同上 | 6 个状态项全覆盖；`is_toggle` → 蓝实底开态，`danger` → 暖红悬停 / 按下 |
| `_attach_btn_motion(b)` | 同上，从 `_mkb()` 尾部抽出 | `_mkb` 与工具按钮共用；pivot 先取 `size`、为 0 时回落 `custom_minimum_size`，再由 `resized` 校正 |
| `_level0_ui_steps()` | 同上 | 从 `_level0_start_phase1()` 抽出的**纯数据**函数，「按钮区」一步直接用 `TOOL_ROW_HL_*`（行 bbox 外扩 6px）；测试也能直接读，不必先造 GM + 刷 UI |
| `Main.tscn` | `HintButton` / `HelpBtn` / `QuitButton` | offset 同步成 460/558/592/590、602/558/698/590、708/558/820/590，`font_size` 13 → 14（运行期以脚本常量为准，场景只是编辑器预览） |

**踩到的坑（都已锁进测试）**

1. 只改 `normal` 不够：Godot 的 `hover` / `pressed` / `disabled` / `focus` 是**独立主题项**，
   没覆盖的话真实鼠标一停上去就掉回默认深灰主题（同一个坑 `_build_card_button()` 也踩过）。
2. 引擎默认主题的 `Button` 只列了 5 个 stylebox，但「toggle 开着 + 悬停」时
   `get_draw_mode()` 返回 `DRAW_HOVER_PRESSED(4)` —— `hover_pressed` override 真的会被用到；
   测试用一颗探针按钮把这条钉死，避免写成死代码。
3. `Button.size` 在树外会被 `custom_minimum_size` 夹取 → 先设最小尺寸再设 `size`。

**验收**：23 个测试套件全绿（新增 `tests/verify_tool_buttons.gd` **109 条**：绑定 4 / 样式接管 52 /
悬停光晕 10 / 语义态 12 / 几何 8 / 相邻区块不重叠 5 / 按序按钮 5 / 教程高亮框 7 / 悬停缩放 6）；

---

## 13. 批次 A 实施记录（缺陷修复 + P4 批次 A 打磨）

P4《美术升级方向》核对表里 12 项 ❌ 中有 5 项是纯代码可做的（不需要素材），
连同两个试玩反馈的缺陷（F1 / F2）一起按「一次一个主题、一次一个提交」推进。

### 13.1 F1：多价元素化合价画出卡边

**现象**：Cl / I / S / Cr 等元素的卡面「常见化合价」一行会画到卡片右边界外面，
紧凑档（8 张以上重叠）更明显，触屏档 15px 时半个字符串贴在牌外。

**根因**：`CardValence` 是固定 85×18（紧凑 44×18）的 `Label`，文本直接由
`card.common_valence` 拼成 `" ".join()`，**既没有 `clip_text` 也没有换行**。
实测（`ThemeDB` 默认字体）：

| 元素 | 价态 | 13px | 15px | 可用宽（85−6） |
|---|---|---|---|---|
| Cl | `-1 +1 +3 +5 +7` | **85.0** | **98.0** | 79 |
| I | `-1 +1 +5 +7` | 67.0 | 77.0 | 79 |
| N / S / Br | `-3 +3 +5` 等 | 49.0 | 56.0 | 79 |
| Cr / Mn | `+2 +3 +6` | 52.0 | 60.0 | 79 |

13px 时 Cl 的宽度**正好等于整张卡宽 85**，所以一直是「压线溢出」，触屏放大后就明显了。
帮助页图鉴（迷你卡 96 宽）早就有「只留前 2 个 + …」的裁剪，卡面却一直没做 —— 两套实现分叉。

**方案：单一 `_fit_card_valence()` 分级收缩链**（`full → tight → 降字号 → brief → clip`）

| 档 | 文本 | 触发条件 | 例（Cl） |
|---|---|---|---|
| 1 全价 | `_format_valence_full()`（带空格） | 放得下就用，最易读 | 13px 单卡不触发 |
| 2 去空格 | `_format_valence_tight()` | 全价超宽但去空格够 | `-1+1+3+5+7` = 72 ≤ 79 |
| 3 降字号 | tight + 逐档 −1px | 仍超宽，逐档试到 `CARD_VAL_MIN_FS = 10` | 触屏 15 → 14（77 ≤ 79） |
| 4 两端价 | `_format_valence_brief()` | 降到下限还超宽 | 紧凑档 `-1 +7…` @10 = 32 ≤ 38 |
| 5 兜底 | `clip_text = true` | 任何数据 / 字体下都不再画出卡边 | 同左 |

- `_format_valence_brief()` 只留「最低价 + 最高价」+「…」：Cl 在化合物里最常用的就是 -1 / +7；
  中间的 +1/+3/+5 不丢 —— 悬停信息栏（`_card_summary_text`）仍显示全价、化合价面板是逐价按钮。
- 两个价以内**原样返回**（不动数据顺序，H 仍是 `+1 -1`）；3 个以上才排序取首尾。
- 实测宽写进 `label.set_meta("fit_w", w)`：A1 的圆底价态 chip 直接用它算底宽，不再重复测量。
- 帮助页 `_help_valence_text()` 改为委托 `_format_valence_brief()`，两处规则合一。

| 位置 | 改动 |
|---|---|
| `GameUI.gd` 常量区 | `CARD_VAL_PAD = 6` / `CARD_VAL_MIN_FS = 10` |
| `_valence_token` / `_format_valence_full/tight/brief` / `_fit_card_valence` / `_valence_width/fits` | 新增（紧接 `_card_summary_text`，化合价文本的唯一实现） |
| `_build_card_button()` | 价态 Label 改为「建好 → add_child → `_fit_card_valence`」，不再手拼字符串 |
| `_apply_card_compact()` | 尺寸定下来后重新 fit（紧凑档可用宽 38），字号/文本随档位重算 |
| `_help_valence_text()` | 委托 `_format_valence_brief()`（删掉「前 2 个 + …」旧实现） |
| `_card_summary_text()` | 复用 `_format_valence_full()`（原来内联拼一份） |
| `tests/verify_hand_layout.gd` | **+6**：Cl 全宽不溢出（72 ≤ 79）/ `clip_text` 兜底 / 紧凑档不溢出（32 ≤ 38 且文本为 `-1 +7…`）/ 双价不降级 / 两价原样 / 多价排序 / 图鉴同源 |
| `tests/verify_touch_ui.gd` | 价态字号断言由「恒等于 15」放宽为「落在 11~15 自适应区间」—— 首张牌恰好是 Cl 时会合法地降到 14 / 11 |

**为什么不用 `autowrap_mode`**：价态是「一行 + 短串」，折行会把 18px 高的 Label 变两行压到原子量；
放大卡面 / 缩字号又会破坏与符号、中文名的视觉层级。分级收缩能保住「小价元素保持原样」这个前提 ——
只有真的放不下（Cl / I 这类 4~5 价格式）才让位。

### 13.2 F2：触屏拖拽「按住后牌不动、松手还点不中」

**现象**（真机）：按住一张牌拖动时，前 300ms 牌完全不动（幽灵牌不出现、插入线不出现），
像卡了一样；如果手指只挪了十几像素就松手，那次点击还会被吞掉 —— 表现为「点了没反应」。

**根因**：`_update_hand_drag()` 里有两道闸串联：

```gdscript
if moved >= _drag_threshold():            # 触屏 24px
    if _touch_ui and Time.get_ticks_msec() - _drag_press_at < TOUCH_DRAG_LONG_PRESS_MS:
        return                            # 还要再等 300ms
    _begin_drag(...)
```

- 第一道 24px 是为了区分「手指抖动」和「有意拖拽」，但**起拖**也被它挡住了；
- 第二道 300ms 长按是后来补的（因为起拖门槛降到 10 也会误判），两道叠起来最坏 300ms + 24px 才跟手；
- 起拖前 `_drag_suppress_click` 没置位，但**起拖后**置位了 —— 松手若判定为「已完成拖拽」就会吞掉 pressed，
  而真正落库又要 `slot != from`，于是 10~24px 这一档变成「既没重排、也没点选」的静默失败。

**方案：把「跟手」与「确认」拆成两档，判定全部挪到松手时**

| 常量 | 值 | 语义 |
|---|---|---|
| `TOUCH_DRAG_ARM_MOVE` | 10 | 位移 ≥10px 立即起拖（幽灵牌 + 插入线跟手），不再等长按 |
| `TOUCH_DRAG_THRESHOLD` | 24 | 松手时**累计最大位移** ≥24px 才落库重排 |
| （删除）`TOUCH_DRAG_LONG_PRESS_MS` | — | 长按闸整个去掉，`_drag_press_at` 成员一并删除 |

- `_drag_max_move`（新成员）在按下时清零、在 `_update_drag_follow()` 里 `maxf` 单调累计；
  `_finish_drag()` 用它判定：`_touch_ui && _drag_max_move < 24` → **回退成点选**。
- 关键不等式：**起拖门槛（10）< 回退门槛（24）**，因此「跟手了」永远不会让一次点选丢失
  —— 这是旧实现最致命的地方（吞掉 pressed 且不重排）。
- 回退走 `_apply_card_selection(idx)`（从 `_on_card_clicked` 抽出的共享路径），
  振动反馈 / 提示作废 / 三个 `_update_*` 全部复用；`_drag_suppress_click` 仍延后一帧清除，
  挡住 Button 补发的那次 pressed，不会「选中又立刻取消」。
- 软启动视觉：触屏源牌 0.55（桌面 0.28）、幽灵牌 0.9（桌面 0.85）——
  10px 就起拖意味着绝大多数点选都会短暂进入拖拽态，一步淡到底会闪一下。

| 位置 | 改动 |
|---|---|
| `GameUI.gd` 常量区 | `TOUCH_DRAG_ARM_MOVE` / `TOUCH_DRAG_THRESHOLD` / `TOUCH_DRAG_SOURCE_ALPHA` / `TOUCH_DRAG_GHOST_ALPHA`；删 `TOUCH_DRAG_LONG_PRESS_MS` |
| 成员变量 | 删 `_drag_press_at`，加 `_drag_max_move` |
| `_drag_arm_threshold()` | 新增：触屏 10 / 桌面 `DRAG_THRESHOLD(6)`（桌面单档，行为不变） |
| `_update_hand_drag()` | 用 `_drag_arm_threshold()` 起拖，去掉长按分支，累计 `_drag_max_move` |
| `_update_drag_follow()` | 累计 `_drag_max_move` |
| `_begin_drag()` / `_make_drag_ghost()` | 触屏软启动透明度（`_make_drag_ghost` 加 `alpha` 参数） |
| `_finish_drag()` | 触屏位移 <24px → 回退成点选，`call_deferred("_clear_drag_suppress")` |
| `_on_card_clicked()` / `_apply_card_selection()` | 抽出共享选中路径 |
| `tests/verify_touch_ui.gd` | **+2 +1 段**：10/24 两档分离、起拖 < 确认（不等式回归锁）、12px 松手回退成点选（且顺序不变、视觉已清理）、40px 松手真的重排且不额外选中；桌面基准断言追加 `_drag_arm_threshold() == 6` |
| `tests/verify_hand_reorder.gd` | **+4**：桌面单档（6/6）、`_drag_max_move` 单调不减、桌面位移 0 也照常重排（回退分支只属于触屏）、重排后不选中 |

**验收**：`verify_hand_layout` / `verify_touch_ui` / `verify_hand_reorder` /
`verify_hand_view` / `verify_hand_runtime` / `verify_help_page` 全绿。

### 13.3 A1：按钮圆角 / 日志底板 / 卡面价态圆底

三项都是「同一屏里还差一口气」的细节，不改任何交互行为：

| # | 问题 | 处理 |
|---|---|---|
| A1-1 | 按钮与卡牌同为 8px 圆角，但按钮只有 32~58 高，弧长占比过大 → 看起来比卡牌更圆（像药丸） | 新增 `BUTTON_RADIUS = 6`，`_make_panel_style("button")` 改用它；圆角形成「chip 5 / 按钮 6 / 卡牌 8 / 面板 10」的递进 |
| A1-2 | 6 行日志直接压在浅蓝背景上，右栏里没有任何边界，视线找不到落点 | 新增 `_make_panel_style("log_panel")`（白 62% + 圆角 10 + 1px 中性边 + 软投影）+ `_ensure_log_panel()` 惰性创建 `LogPanel`（插在 `LogLabel` 之前、不吃鼠标）+ `_set_log_visible()` 作为唯一显隐出口 |
| A1-3 | 价态是 12~15px 的红色小字，孤零零漂在白卡上；标签化后一眼能扫到 | `CardValenceChip`（`valence_chip` 样式，极浅暖底 `#FAEDED`，圆角 5），宽度 = `meta("fit_w") + 2×CARD_VAL_CHIP_PAD`（不超过 label 宽），水平居中于 label；F1 的实测宽直接复用，不再重复测量 |

**为什么 chip 宽度不写死**：紧凑档（8 张以上重叠）label 只有 44 宽、Cl 的文字只有 32 宽，
写死 85 的底会把相邻牌露出的窄条糊掉；跟着 `fit_w` 走，文字缩档时底也一起缩。

**为什么日志底板要单独一个节点而不是给 Label 加 StyleBox**：`Label` 没有 panel 主题项
（只有 `normal` 的 `StyleBoxEmpty`），硬塞会把文字挤进内边距；独立 `Panel` 还能保证
「底板在文字之下、鼠标穿透」，并且显隐不受 `Label.text` 换行高度影响。

| 位置 | 改动 |
|---|---|
| `GameUI.gd` 视觉规范区 | `BUTTON_RADIUS = 6` / `CHIP_RADIUS = 5` / `CARD_VAL_CHIP_H = 16` / `CARD_VAL_CHIP_PAD = 5` / `LOG_PANEL_PAD = 10` |
| `_make_panel_style()` | `button` 改用 `BUTTON_RADIUS`；新增 `log_panel` / `valence_chip` 两种 kind |
| `_build_card_button()` | 价态 label 前建 `CardValenceChip`（同级、树顺序在前） |
| `_fit_card_valence()` / `_sync_valence_chip()` | 收缩完文字后同步圆底几何；找不到 chip 就静默跳过（图鉴 / 裸 Label 复用同一条收缩链） |
| `_ensure_log_panel()` / `_set_log_visible()` | 惰性创建 + 唯一显隐出口；`_level0_clear_rule_tips()` / `_level0_set_rule_tips_visible()` 里的两处直接赋值改为调用它 |
| `tests/verify_hand_layout.gd` | **+10**：圆底节点存在 / 树顺序在 label 之前 / 走工厂（`CHIP_RADIUS`）/ 不吃鼠标 / 宽度 = fit_w+padding（72+10=82）/ 紧凑档不超出 label；日志底板存在 / 不吃鼠标 / 半透明 / 走面板规范 / 包住 LogLabel / 与规则提醒同步隐藏恢复 / `_ensure_log_panel` 幂等 |
| `tests/verify_tool_buttons.gd`（2 处）与 `tests/verify_hand_layout.gd`（1 处） | 按钮圆角断言 `CARD_RADIUS → BUTTON_RADIUS`（4 条），另加 `BUTTON_RADIUS < CARD_RADIUS` 回归锁 |

**验收**：`verify_hand_layout` / `verify_tool_buttons` / `verify_hand_view` / `verify_hand_runtime` /
`verify_touch_ui` / `verify_start_page` / `verify_motion` / `verify_tutorial_layout` /
`verify_help_page` 全绿。

### 13.4 A2：手牌悬停 / 选中缩放 + 桌面区动效

**问题**：手牌悬停只有「抬 20px」，在 16 张叠牌里主角感不足；选中只换底色（触屏再加 10px 上浮），
手指粗的时候几乎看不出。桌面区更平：小卡整块重建时「啪」地出现，「桌面: …」无论打出什么牌型
都是同一行深灰小字，玩家得读完整句才知道刚才是化合物还是族炸。

| 项 | 改动 |
|---|---|
| 手牌缩放 | `_tween_card_scale()`：悬停 `1.06` / 选中 `1.04` / 常态 `1.0`，`HAND_SCALE_MS = 120`；pivot 在 `_layout_hand_cards()` 居中；`scale_tween` 与 `hover_tween` **分开两个 meta 键** |
| 重排不压扁 | `_layout_hand_cards()` 里按「悬停 > 选中 > 常态」会话式重设 `btn.scale`（重排后 `_hover_idx` 没变，状态机不会重新触发） |
| 桌面文字配色 | `_table_type_color()`：单质深灰蓝 `#2B3D4F` / 化合物深绿 / 族炸深红 / 有机物琥珀 / 顺序深紫 |
| 桌面文字淡入 | `_set_table_text()`：文本变化才从 `a=0.15` 淡入（`TABLE_REVEAL_MS = 180`），未变不重播 |
| 小卡入场 | `_animate_mini_card_in()`：`0.9 → 1.0` 缩放 + 淡入，`MINI_CARD_IN_MS = 160` + 40ms stagger；**不动 position**（槽位是布局真值） |
| 入场去重 | `_table_sig = "牌型|符号+uid,…"` —— AI 每次行动都会 `_refresh_ui` 整块重建小卡，不去重会一直闪 |

**为什么缩放不会让命中判定抖动**：悬停 / 点击命中用的是 `_card_hover_rect()`（只读 `base_pos`，
尺寸写死 `CARD_W × (CARD_H + HOVER_LIFT)`），`scale` 完全不参与 —— 与按钮 `_attach_btn_motion()`
同一个思路。代价是放大后的牌绘制区会比命中区宽约 3px（每边），肉眼不可察。

| 位置 | 改动 |
|---|---|
| `GameUI.gd` 动效规范区 | `HAND_HOVER_SCALE = 1.06` / `HAND_SELECT_SCALE = 1.04` / `HAND_SCALE_MS = 120` / `TABLE_REVEAL_MS = 180` / `MINI_CARD_IN_MS = 160` / `MINI_CARD_IN_STAGGER = 0.04` / `TABLE_TEXT_COLOR` |
| `_apply_hover()` | 位置补间旁并排加缩放补间（悬停 1.06、落回按选中态取 1.04 / 1.0） |
| `_layout_hand_cards()` | kill `scale_tween` + 设 pivot + 按状态重设 scale |
| `_tween_card_scale()` / `_kill_scale_tween()` | 新增（与位移补间同构，meta 键独立） |
| `_table_type_color()` / `_set_table_text()` / `_tween_table_label_reveal()` / `_animate_mini_card_in()` | 新增；`_update_table_label()` 改用它们，并计算 `_table_sig` 决定是否播入场 |
| `tests/verify_motion.gd` | **+13**：pivot 居中 / 选中档 < 悬停档 / 悬停 1.06 / 等比 / 选中 1.04 / 取消选中回 1.0 / 重排不残留补间 / 三种牌型色可区分 / 文字淡入起点 / 淡入收敛 / 文本未变不重播 / 小卡入场起点 / 小卡收敛且不动 position |

**验收**：27 套测试全绿（`verify_motion` 覆盖 13 条新断言，`verify_hand_layout` / `verify_sequence_table` /
`verify_integration` 的桌面小卡位置断言未受影响 —— 因为入场刻意不动 position）。

`--headless --quit-after 90` 无 ERROR；真实窗口核对 4 组状态（常态 / 悬停 / 提示开 / 退出悬停）。
