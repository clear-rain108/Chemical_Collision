# UI 层重构：GameUI.gd 按功能拆分

> 本文档是重构的**计划 + 进度台账**。每完成一片，回来把 ⬜ 改成 ✅ 并填「§8 完成记录」。
> 最后更新：2026-11-17（Slice 1 落盘）

## 0. 背景与已定决策

`scripts/GameUI.gd` 目前 **7651 行 / 326 KB**，单文件承担 6 个页面、样式工厂、手牌视图、
悬停/拖拽状态机、出牌步骤流、联机接线、房间页、第零关引导。三个直接后果：

1. **性能**：点一张牌就 `_update_hand_buttons()` 全量销毁重建（`GameUI.gd:4804-4810`），
   单次点击 ≈ 104 个节点增删 + 39 个 StyleBoxFlat + 80~100 次 `get_string_size()` → 真机掉帧尖峰。
2. **维护**：任何 UI 改动都在一个 7.6k 行文件里 diff，review 成本极高。
3. **风险**：性能修复与结构问题纠缠在同一处，无法分开验证。

| 决策 | 结论 |
|---|---|
| 范围 | **A：全量 5 片**（Slice 0~5），root 降到 ≈1000 行 |
| 拆分方式 | **门面（Facade）+ 组合（RefCounted 模块回引 host）**：不改节点树、不改方法名、不搬字段 |
| 前置清理 | ~~回滚 `project.godot`~~ → **判断已证伪**：`window/stretch/aspect="keep"` 是 Godot 4.7 的**引擎默认值**（`ProjectSettings.property_get_revert()` 实测返回 `"keep"`），引擎每次 save 都会删掉「等于默认值」的键，行为完全不变。改为**接受**规范化后的文件，把被删掉的注释原文记进 §8.3 |
| `export_presets.cfg` | **保留**工作树改动（release 输出路径），随重构一起提交 |
| 文档先行 | 本文档先落盘，再动代码 |

**先例**：`tests/verify_refactor.gd` 是上一轮（引擎层拆 CardPatterns / CompoundSolver /
PlayerManager / AIPlayer / GameLogger）的验证脚本。本次是同一套做法的第二轮，对象换成 UI 层。

**为什么必须分片**：GDScript 没有 IDE 级 "Move Method"（VS Code + godot-tools 不支持），
7600 行一次性搬运的 diff 无法 review，失败时也无法定位是哪一段搬错 —— 只能手工切片。

---

## 1. 不可破的约束（违反即 46 套测试红）

### 1.1 测试对根节点的耦合面（证据）

| 类型 | 证据（文件:行） | 约束 |
|---|---|---|
| 方法反射调用 | `verify_hand_layout.gd:73/194/199/227` `scene.call("_update_hand_buttons")`；`:619/633/639/643` `_make_panel_style`；`:325/359` `_hover_hit_index`；`verify_room_page.gd:388/516/570/607/643/666` `_room_bind_session`；`verify_ui_online.gd:533/621` `_update_net` | root 保留**全部**同名同签名方法 |
| 字段直读 | `scene.hand_buttons` / `selected_indices` / `step_mode` / `game_manager` | 字段留 root |
| 字段直**写** | `verify_hand_layout.gd:250/350` `scene.hand_buttons = arr`；`verify_ui_online.gd:129/489` `scene.game_manager = ...`；`verify_room_page.gd:669`；大量 `scene.selected_indices = [...]`、`scene.step_mode = 2/3` | 必须是普通 `var`，**不得**改成 getter/setter 代理 |
| 常量直读 | `verify_hand_view.gd:54`、`verify_motion.gd:255/256/275` → `scene.CARD_W` / `scene.CARD_H` | 常量名留 root（用别名） |
| 节点路径 | 各页测试大量 `scene.get_node("GamePage/…")`、`RoomPage/…` | 节点树一个都不动 |
| 场景入口 | 28 处 `load("res://Main.tscn").instantiate()` | `Main.tscn` 的 `script` 路径不变 |

### 1.2 铁律（Slice 5 同步写进 ARCHITECTURE.md）

1. **状态只留 root**：模块不持有 `selected_indices` / `hand_buttons` / `step_mode` 的副本。
2. **模块只持有一个 `_ui` 回引**；`create_tween()` / `get_tree()` / `queue_redraw()` 一律走 `_ui.`
   （`RefCounted` 没有这些方法，且生命周期必须绑在 root 上）。
3. **常量可下沉，但 root 必须留 `const X := Mod.X` 别名**（禁止在 root 写字面量）。
4. **不加 `class_name`**，一律 `preload` + `const`（沿用工程现有风格）。
5. **不改测试**。任何导致需要改测试的改动 = 方案错了，回退重做。

### 1.3 禁止事项

- ❌ 改 `Main.tscn` 节点树 / 节点名 / `unique_id`
- ❌ 改任何 `tests/*.gd`
- ❌ 在拆分 commit 里「顺手」改游戏行为或调参（2b 除外，它专门做性能）
- ❌ 把 root 字段搬进模块后再在 root 留 `@export` 或属性代理

---

## 2. 目标架构（21 个模块）

| # | 模块 | 来源行段（当前 GameUI.gd） | 约行数 | 职责 |
|---|---|---|---|---|
| 0 | `scripts/GameUI.gd`（门面） | 1–330、333–532、612–750、3264–3286 | **≈950** | 常量/字段/装配/`_refresh_ui` 编排/`_process` 分发/全部转发 |
| 1 | `scripts/ui/UITheme.gd` | 226–254、4751–4775、533–611 | 140 | 视觉常量、`panel_style(kind)`、`card_color()`（+StyleBox 缓存） |
| 2 | `scripts/ui/TouchMetrics.gd` | 146–183、4336–4536 | 240 | 触屏档判定/几何取值/运行时开关 |
| 3 | `scripts/ui/PageRouter.gd` | 620–750 | 130 | `_show_*_page` / 淡入 / 返回 |
| 4 | `scripts/ui/PageWidgets.gd` | 825–860、1269–1402、2011–2077 | 260 | 按钮工厂 / 渐变带 / 背景 |
| 5 | `scripts/ui/HandView.gd` | 76–103、124–145、4776–5898 | **≈1200** | 手牌渲染/重叠布局/悬停状态机/命中/拖拽重排/价态自适应 |
| 6 | `scripts/ui/TableArea.gd` | 314、3287–3402 | 180 | 顶部状态栏 + 桌面文案 |
| 7 | `scripts/ui/SidePanels.gd` | 53–59、3403–3574、3817–4065 | 340 | 桌面小卡 + 日志/规则提醒面板 + 「按序」按钮 |
| 8 | `scripts/ui/CardMotion.gd` | 270–287、3575–3816 | 250 | 幽灵牌飞行 / 小卡入场 / 发牌淡入 |
| 9 | `scripts/ui/ActionPanel.gd` | 4066–4335、5899–6062 | 440 | 操作面板 + 步骤流按钮 + 化合价面板 |
| 10 | `scripts/ui/ToolRow.gd` | 4537–4668 | 130 | 提示/帮助/退出三按钮样式接管 |
| 11 | `scripts/ui/Toast.gd` | 289–299、6547–6614 | 90 | 信息/警告 toast |
| 12 | `scripts/pages/StartPage.gd` | 66–262、751–1098 | 350 | 开始页 + 设置 |
| 13 | `scripts/pages/SuppRulesPage.gd` | 1099–1543 | 445 | 补充规则页 + 元素池 |
| 14 | `scripts/pages/HelpPage.gd` | 1544–2010 | 465 | 帮助中心（3 Tab + 图鉴） |
| 15 | `scripts/pages/EndPage.gd` | 2078–2304 | 227 | 结算页 |
| 16 | `scripts/pages/TutorialPage.gd` | 2305–2457 | 153 | 关卡引导页 |
| 17 | `scripts/pages/RoomPage.gd` | 6990–7651 + 房间字段 | **≈700** | 房间页（组房/加入/座位/AI/开局） |
| 18 | `scripts/tutorial/Level0Overlay.gd` | 323–327、2727–3263 | 540 | 第零关 Phase1/2/3 |
| 19 | `scripts/game/GameFlow.gd` | 90–91、2458–2726、6063–6539、6646–6676 | 750 | 开局/系统操作/交互回调/结果处理/步骤重置 |
| 20 | `scripts/game/HintFlow.gd` | 92–98、4669–4750 | 90 | 提示按钮 → HintAdvisor |
| 21 | `scripts/net/OnlineUI.gd` | 112–122、6677–7007 | 350 | `attach_session`/`_update_net`/`_online_on_*` |

### 2.1 代码模板

```gdscript
# ---------------- root: scripts/GameUI.gd ----------------
const HandViewScript = preload("res://scripts/ui/HandView.gd")

const CARD_W := HandViewScript.CARD_W     # 95.0（测试直读 scene.CARD_W）
const CARD_H := HandViewScript.CARD_H     # 118.0

var hand_buttons: Array = []              # 字段留 root（测试直写）
var selected_indices: Array = []
var step_mode: int = 0

var hand_view: RefCounted = null

func _ready() -> void:
	hand_view = HandViewScript.new(self)  # 注入 host

# 测试兼容转发：名字/签名一字不改
func _update_hand_buttons() -> void:
	hand_view.update_buttons()
```

```gdscript
# ---------------- module: scripts/ui/HandView.gd ----------------
extends RefCounted

const CARD_W := 95.0                      # 唯一真源
const CARD_H := 118.0

var _ui: Control                          # host 回引

func _init(ui: Control) -> void:
	_ui = ui

func update_buttons() -> void:
	var hc: Control = _ui.hand_container  # 直接读宿主字段，不做第二份状态
	var sel: Array = _ui.selected_indices
	var tw: Tween = _ui.create_tween()    # Tween 必须由 Node 创建
	await _ui.get_tree().create_timer(0.1).timeout
```

**引用环说明**：`Node → 模块 → Node` **不是**泄漏。`RefCounted` 环只在「纯 RefCounted 互引」时才靠
引用计数泄漏；root 是 `Node`，场景释放时其成员变量清空，模块计数归零正常析构。
唯一注意：模块不要被外部对象（Tween 回调等）长期持有 —— 现状也没有。

---

## 3. 进度看板

### Slice 0 —— 前置（无代码重构）
- ✅ `project.godot`：核实为**引擎规范化重写**而非配置丢失（`aspect="keep"` 是 4.7 默认值，
  `property_get_revert()` 实测 = `"keep"`），接受重写结果，注释原文存 §8.3
- ✅ 新建 `tools/run_tests.gd`（原计划的 `.bat` 因 LF 换行不可用，见 §5.2）
- ✅ 新建 `tools/gen_facade_list.gd`（门面清单机械生成器）
- ✅ 新建 `tests/verify_ui_facade.gd`（门面完整性守卫，见 §5.3）
- ✅ 全量基线跑完：**47/47 全绿**（见 §8.1）
- 验收：`git status` 只剩 `export_presets.cfg` + 本文件 + tools/tests 新增；基线全绿

### Slice 1 —— 立规矩（风险最低）✅ 2026-11-17 完成
- ✅ `ui/UITheme.gd`（125 行）：`_make_panel_style` / `_style_base` / `_get_card_color`
  （StyleBox 缓存留到 2b —— 那一步才允许改行为）
- ✅ `ui/TouchMetrics.gd`（256 行）：触屏档判定（两个 static）/ 11 个几何取值函数 / 运行时开关 /
  按钮兜底放大与还原
- ✅ `ui/Toast.gd`（90 行）：`_show_info` / `_show_center_warning` / `_ensure_warning_toast` /
  `_hide_warning_toast`
- ✅ `ui/PageRouter.gd`（133 行）：`_ensure_layers` / `_make_layer` / `_layer` /
  `_ensure_page_backdrop` / `_all_pages` / `_fade_in_page` / `_show_start_page`
- ✅ root 补 33 个**同名**转发方法 + 4 个模块字段（`ui_theme` / `ui_touch` / `ui_toast` / `ui_router`），
  `_init` 注入回引；**常量一个没搬**（`scene.CARD_W` / `scene.PAGE_BG_COLOR` 仍直接命中 root）
- 结果：root **7651 → 7357 行**（−294），模块合计 604 行
  （比目标 ≈7000 高：转发方法 33×3 行 + 原注释按铁律保留在 root）
- 验证：**47/47 全绿**，重点 `verify_ui_facade`(13) / `verify_motion`(91) / `verify_touch_ui`(65) /
  `verify_touch_flag`(19) / `verify_touch_toggle`(27) / `verify_hand_layout`(225) / `verify_ui_online`(101)；
  另 `--quit-after 60` 冒烟：0 ERROR / 0 WARNING
- commit：`【重构】UI 层拆分 1/5：样式/触屏档/toast/页面路由 抽为模块`

### Slice 2a —— 纯搬运（零行为变化）✅
- ✅ `ui/CardMotion.gd`（200 行）：`_animate_mini_card_in` / `_make_fly_ghost` / `_bezier2` /
  `_place_ghost` / `_fly_ghost` / `_capture_play_fly_in` / `_replay_play_fly_in` /
  `_fly_discarded_card` / `_animate_new_hand_cards` / `_snap_card_position`（10 个方法）
- ✅ `ui/HandView.gd`（1329 行）：手牌渲染 / 重叠布局 / 悬停状态机 / 命中 / 拖拽重排 / 价态自适应，
  共 **65 个方法**，分 3 段搬运（段与段之间刻意跳过 root 的 `_process`）
- ✅ root 补 **75 个同名转发**（10 + 65）+ 2 个模块字段（`ui_motion` / `ui_hand`），`_init` 注入回引；
  **仍然一个常量都没搬**（`scene.CARD_W` 等命中继续落在 root）
- 结果：root **7357 → 6098 行**（−1259），模块合计 1529 行
  （比目标 ≈5600 高 500：75 个转发方法 × 3 行 ≈ 225 行 + 原注释按铁律保留在 root）
- 与本文档原计划的**三处偏差**（都偏保守，行为未变）：
  1. 模块字段名统一 `ui_*` 前缀（`ui_hand`），不叫 `hand_view` —— 与 Slice 1 的
     `ui_theme` / `ui_touch` / `ui_toast` / `ui_router` 保持一致
  2. `_process` **没有**改成 `hand_view.process(delta)`：它仍留在 root（唯一引擎钩子），
     内部调用的 `_update_hand_drag()` / `_update_hand_hover()` 现在是转发方法，顺序一字未动（R5）
  3. `_on_auto_play`（「直接出牌 ⚡」）留在 root：它走 `game_manager` 出牌链路，归 Slice 3 的 GameFlow
- 验证：**47/47 全绿**，重点 `hand_layout`(225) / `hand_view`(60) / `hand_runtime`(17) /
  `hand_reorder`(54) / `motion`(91) / `touch_ui`(65) / `valence_chip`(19) / `mixed_valence_ui`(9)；
  另 `--quit-after 60` 冒烟：0 ERROR / 0 WARNING
- commit：`【重构】UI 层拆分 2/5a-1：牌面动效抽为 ui/CardMotion.gd`
  + `【重构】UI 层拆分 2/5a-2：手牌视图抽为 ui/HandView.gd`
  （分两笔只为 review：动效与手牌是两块互不相干的断言集，红了一眼能定位）

### Slice 2b —— 性能修复（这一步才改行为）
- ⬜ 选中/取消只改 1~2 张牌的 stylebox / z_index，不重建
- ⬜ `update_buttons()` 加签名早退 + 按 `uid` diff 复用旧按钮
- ⬜ `_make_panel_style` 复用缓存实例（Slice 1 已建缓存，这里统一调用点）
- ⬜ 新增 `tests/verify_ui_perf.gd`：
  1. 选中/取消后按钮对象 id 不变
  2. 同签名连调两次不新建节点（子节点数不变）
  3. `_make_panel_style("card")` 两次返回同一 Resource 实例
  4. 桌面签名不变时小卡对象 id 不变
  5. 操作面板清单不变时按钮 id 不变
- 验证：`verify_ui_perf`（新）+ 6 套手牌测试 + 全量
- commit：`【性能】手牌增量刷新：选中不重建 + 同签名早退 + uid 复用`

> **为什么 2a / 2b 必须拆两个 commit**：「搬错了」和「优化改错了」混在一起时，
> 只有全量测试红才知道是哪一个。

### Slice 3 —— 交互链
- ⬜ `ui/ActionPanel.gd` ⬜ `ui/TableArea.gd` ⬜ `ui/SidePanels.gd` ⬜ `ui/ToolRow.gd`
- ⬜ `game/GameFlow.gd` ⬜ `game/HintFlow.gd`
- 目标：root → **≈3400 行**
- 验证：`action_panel_fit` / `tool_buttons` / `log_panel` / `auto_play` / `halogen` /
  `mixed_valence_ui` / `valence_panel` / `hint` / `clan_bomb_cooling` / `end_page` + 全量
- commit：`【重构】UI 层拆分 3/5：操作面板/桌面区/侧栏/出牌流程 抽为模块`

### Slice 4 —— 页面与联机（行数最多，与主循环无关）
- ⬜ `pages/StartPage.gd` ⬜ `pages/SuppRulesPage.gd` ⬜ `pages/HelpPage.gd`
- ⬜ `pages/EndPage.gd` ⬜ `pages/TutorialPage.gd` ⬜ `pages/RoomPage.gd`
- ⬜ `tutorial/Level0Overlay.gd` ⬜ `net/OnlineUI.gd`
- 目标：root → **≈900–1100 行**（常量 + 字段 + 装配 + 转发）
- 验证：`start_page` / `help_page` / `end_page` / `tutorial_layout` / `room_page` /
  `ui_online` / `touch_toggle` + 全量 46 套
- commit：`【重构】UI 层拆分 4/5：6 个页面 + 第零关引导 + 联机接线 抽为模块`

### Slice 5 —— 收尾
- ⬜ `ARCHITECTURE.md` 新增「UI 分层与刷新约定」小节（铁律 1~5、模块表、`_process` 唯一钩子）
- ⬜ 删除死文件 `scripts/TutorialUI.gd` + `.uid`（全项目零引用）
- ⬜ 修 `CardData.gd:7` 自引用 preload
- ⬜ 重写 `AI_PLAYER_AUDIT.md`（现文围绕已不存在的 `AIPlayer._try_play()`）
- ⬜ `project.godot`：删 `3d/physics_engine="Jolt Physics"`（纯 2D 冗余）
- ⬜ `export_presets.cfg`：`exclude_filter="tests/*"`（先确认 `net_smoke.gd` 是否需上真机）
- ⬜ 重新导出 APK `pre1005.5`，真机 A/B 对比
- commit：`【清理】死代码与过期文档 + ARCHITECTURE UI 分层小节 + 导出过滤`

---

## 4. 每片的机械流程（照做，不要临场发挥）

### 4.1 搬运时的等价改写表

| 原代码（在 root 内） | 搬到模块后 | 说明 |
|---|---|---|
| `_foo()`（调用同模块内方法） | `_foo()` | 直接调用，**绝不**写成 `_ui._foo()`（会经 root 转发再回来 = 无限递归） |
| `_bar()`（调用别的方法，且 `_bar` 已搬走） | `_ui.<那片的模块>._bar()` | 跨模块直连，不经 root |
| `_baz()`（调用别的方法，`_baz` 还在 root） | `_ui._baz()` | 临时形态；`_baz` 搬走后改成上一行 |
| `get_tree()` / `create_tween()` / `queue_redraw()` / `add_child()` | `_ui.get_tree()` / `_ui.create_tween()` / `_ui.queue_redraw()` / `_ui.add_child()` | `RefCounted` 没有这些 |
| `foo_field` | `_ui.foo_field` | 状态只留 root |
| `CARD_W`（常量） | 若常量已下沉：`CARD_W`（模块内本地常量）；root 侧写 `const CARD_W := ModScript.CARD_W` | 一处真源 |
| `btn.pressed.connect(_on_x)` | `btn.pressed.connect(_ui._on_x)` | **必须指向 root**，保证测试的反射/spy 语义不变 |
| `func _x() -> void:` 里有 `await` | root 转发必须写成 `func _x() -> void: await mod.x()` | 漏 `await` 会让调用方提前继续 |

### 4.2 每一步的四道闸

1. **搬之前**先 `grep -n "_被搬方法名"` 全项目，确认除了本文件没别人调（有就记下来，改成 `_ui.`）。
2. **搬之后** `Godot --headless --check-only --script scripts/GameUI.gd`（或直接跑 `verify_ui_facade`）
   —— 语法错误比逻辑错误便宜一百倍。
3. **跑该片列的必跑测试**（§5.1），再跑 `verify_ui_facade`，再跑全量。
4. **行数记账**：`(Get-Content scripts/GameUI.gd).Count` 记进 §8，看是不是符合预期；差太多说明搬漏或搬多。

### 4.3 命名与文件约定

- 模块文件头两行注释写清「从 GameUI.gd 的哪些方法搬来 + 属于哪一片」。
- 类名不加 `class_name`；root 侧 `const XxxScript = preload("res://scripts/xxx/Xxx.gd")`。
- 模块一律 `extends RefCounted`，构造函数固定 `func _init(ui: Control) -> void: _ui = ui`。
- 模块里**不查节点**（`_ui.get_node_or_null(...)` 只允许在 `_ready` 之后调用的方法里出现）。
  构造函数只存回引，不碰节点树 —— `_init` 时场景还没 `add_child`。

---

## 5. 验证矩阵

### 5.1 每片的必跑测试

| 片 | 新增模块 | 必跑（除全量外） |
|---|---|---|
| 0 | — | `verify_ui_facade`（新增） |
| 1 | UITheme / TouchMetrics / Toast / PageRouter | `hand_layout` `touch_ui` `touch_flag` `touch_toggle` `log_panel` `help_page` `tutorial_layout` |
| 2a | HandView / CardMotion | `hand_layout` `hand_view` `hand_runtime` `hand_reorder` `motion` `touch_ui` `valence_chip` `mixed_valence_ui` |
| 2b | —（改行为） | `ui_perf`（新增）+ 2a 全部 + `action_panel_fit` |
| 3 | ActionPanel / TableArea / SidePanels / ToolRow / GameFlow / HintFlow | `action_panel_fit` `action_router` `tool_buttons` `log_panel` `auto_play` `halogen` `hint` `clan_bomb_cooling` `end_page` `valence_panel` `constraint` |
| 4 | 6 个 Page + Level0Overlay + OnlineUI | `start_page` `help_page` `end_page` `tutorial_layout` `tutorial` `room_page` `ui_online` `integration` |
| 5 | —（清理） | 全量 + 真机 |

### 5.2 运行器：`tools/run_tests.gd`

> 原本打算写 `tools/run_tests.bat`，实测不可行：cmd 用 **GBK 代码页**读 UTF-8 的批处理，
> 含中文的 `rem` 行会被拆成多段执行、`if errorlevel` 判断失效（实测日志前 6 行全是
> `'*.gd（依次，失败会打印' is not recognized...` 这类残渣）。
> 改成 Godot 自编排：`OS.execute` 逐个跑子进程，拿真实退出码。

```bat
rem 全量（~100s，超过 30s 上限时用后台）
start /b Gd --headless --path . --script tools/run_tests.gd > %TEMP%\cc_tests.log 2>&1
rem 单套 / 多套
Gd --headless --path . --script tools/run_tests.gd -- verify_hand_layout
Gd --headless --path . --script tools/run_tests.gd -- verify_hand_layout verify_motion
```

输出形如：

```
PASS  verify_hand_layout               (128 checks)
FAIL  verify_motion                    exit=1 FAIL: 飞行中牌应在半路
RESULT: 46/47 PASSED
```

### 5.3 门面守卫：`tests/verify_ui_facade.gd`

守住三件事：77 个测试反射调用的方法都在、4 个直写字段存在且**可写**、`CARD_W/CARD_H` 常量还在。

清单来源是机械抽取（`tools/gen_facade_list.gd`），不是手写：

```bat
Gd --headless --path . --script tools/gen_facade_list.gd
```

把输出数组粘进 `verify_ui_facade.gd` 的 `MUST_HAVE_METHODS`。
**每片结束后重跑一次生成器**，若清单变了（说明某套测试新增了反射调用）要同步。

### 5.4 搬运工具：`tools/move_funcs.gd`

Slice 2a 起不再手抄实现（1000 行手抄必出错），改由工具按**行区间**机械搬运：

```bat
Gd --headless --path . --script tools/move_funcs.gd -- ^
  --from=scripts/GameUI.gd --to=scripts/ui/HandView.gd --field=ui_hand ^
  --also=create_tween,get_tree,get_global_mouse_position ^
  --range=4398-4639,4641-4960,4978-5727
```

它做且只做四件机械事：

1. 把每个区间整段（含注释）搬进目标模块；
2. 段内**借用 root 的标识符**（常量 / 字段 / 方法）自动改成 `_ui.X` —— 只改 root 上真实存在的符号，
   并跳过局部变量、参数、lambda 参数、字符串、`#` 注释与 `a.b` 的右侧；
3. 段内 `:= _ui.x` 一律降级成 `= _ui.x`（`:=` 无法从动态类型推断，见 §8.4 第 2 条）；
4. 源文件原位替换成**同名转发方法**（参数/返回类型照抄，默认值仍由转发器承担）。

`--also=` 是给**引擎自带实例方法**用的：`create_tween` / `get_tree` / `get_global_mouse_position`
这些不是 root 的自定义符号，但在模块里同样只能经 `_ui` 调用 —— 漏进白名单的表现是
`Function "create_tween()" not found in base "RefCounted"`，`--check-only` 会当场点名。

搬完必做的三件事：`--check-only` 跑新模块与 root → **全量测试** → `--quit-after 60` 冒烟。


---

## 6. 风险登记

| # | 风险 | 会在哪炸 | 缓解 |
|---|---|---|---|
| R1 | **转发漏写**：方法搬走但 root 没留同名方法 | 对应测试 `Invalid call. Nonexistent function` | `verify_ui_facade` 每片必跑，直接点名缺哪个 |
| R2 | **无限递归**：root `_foo()` 转发给模块，模块里又写 `_ui._foo()` | 栈溢出，测试直接崩 | §4.1 第一行铁规；搬完 `grep "_ui._<本模块方法名>"` 一遍 |
| R3 | **双源状态**：模块里又存一份 `selected_indices` | 悬停/选中不同步，`hand_layout` 偶发红 | 铁律 1；code review 只看模块里有没有 `var sel` 之类 |
| R4 | **await 丢失**：异步方法转发没 `await` | 页面淡入、飞行结束后置位提前发生 → `motion` / `end_page` 时序断言红 | §4.1 最后一行；翻 `_ui.gd` 里所有含 `await` 的方法逐个核对 |
| R5 | **`_process` 顺序变化** | 手牌悬停抖动、`hand_runtime` 红 | Slice 2a 只把「手牌那一段」整段搬进 `hand_view.process(delta)`，root 里段前段后代码位置不动 |
| R6 | **`_init` 里碰节点树** | 启动即崩（场景未 add_child） | §4.3 最后一条：构造函数只存回引 |
| R7 | **preload 循环** | 解析期报 `cyclic reference` | 依赖单向：模块**不** preload `GameUI.gd`，只用 `_ui` 动态调用 |
| R8 | **Tween 生命周期**：tween 绑定在 root 上、回调指向模块 | 极端情况下 `queue_free` 后回调打到已析构模块 | Tween 一律 `_ui.create_tween()`（随 root 释放）；模块不留 `var tw` 以外的外部引用 |
| R9 | **触屏档运行时切换**（`verify_touch_toggle`） | 切到触屏后几何没变 | `TouchMetrics` 只读 `_ui` 上的开关字段，不自己缓存判定结果 |
| R10 | **行号漂移** | 后续片段「来源行段」全失效 | 一律按**方法名**定位，不按行号；本文档行号只作首次定位参考 |
| R11 | **编辑器再次改写 `project.godot`** | `aspect="keep"` 又丢 | 提交前 `git diff project.godot` 必看；一旦有 diff 先 `git checkout --` 再重做配置 |
| R12 | **测试被顺手改** | 违背铁律 5，失去对照基准 | 提交前 `git status tests/` 只允许出现 `verify_ui_facade.gd` 和 `verify_ui_perf.gd`（新增） |

---

## 7. 回滚

- 每片一个 commit，**回滚粒度 = 一片**：
  - 整片撤销：`git revert --no-edit <sha>`
  - 只救文件：`git checkout <sha>~1 -- scripts/GameUI.gd scripts/ui scripts/pages scripts/game scripts/net`
- Slice 2b（性能）**单独成 commit**：若真机反而更卡，只 revert 2b，结构成果保留。
- 若不小心改了测试：`git checkout -- tests/`（但 `verify_ui_facade.gd` / `verify_ui_perf.gd` 是新增文件，不受影响）。
- 最坏情况：`git checkout <重构前最后一个 commit> -- scripts/GameUI.gd` —— 回到重构前单文件
  （本片所有模块文件留着不用也无害，因为它们不被任何地方 preload 时不会进包）。

---

## 8. 完成记录

### 8.1 基线（Slice 0 结束时实测）

| 项 | 值 |
|---|---|
| 日期 | 2026-11-17 |
| 套数 | **47 / 47 PASSED**（46 套原有 + 1 套新增 `verify_ui_facade`） |
| 失败 | `FAIL:` 0 条，`ABORT:` 0 条（对全量日志 `findstr` 实测） |
| `GameUI.gd` | **7651 行** |
| `project.godot` | 由 Godot 4.7.2 规范化重写（删默认值 `aspect="keep"` + 手写注释丢失，**行为不变**，原文存 §8.3） |
| 命令行 | `start /b <Godot> --headless --path . --script tools/run_tests.gd > %TEMP%\cc_tests.log 2>&1` |

> 注：`verify_logger.gd` 只打印 1 条 `PASS:`（其余靠退出码），所以「PASS 条数」不能用来判断套数。

### 8.2 每片账本（做完就填）

| 片 | commit | GameUI.gd 行数 | 新增模块行数 | 测试 | 备注 |
|---|---|---|---|---|---|
| 0 | — | 7651（未动代码） | 0（新增 tools/ + 1 测试） | 47/47 ✅ | 回滚 project.godot |
| 1 | （待提交） | 7357（−294） | **604**（UITheme 125 / TouchMetrics 256 / Toast 90 / PageRouter 133） | 47/47 ✅ | 常量未搬；33 个转发方法 |
| 2a | | | | | |
| 2b | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |

### 8.3 `project.godot` 中被引擎删掉的手写注释（原文存档）

> Godot 4.7.2 在 save `project.godot` 时会：①删除所有等于默认值的键；②丢弃全部 `;` 注释；
> ③按内部顺序重排 `[rendering]` 的键。以下两段是重写后丢失的原文，内容仍然有效，只是不再写在配置里。

```ini
[display]

window/stretch/mode="canvas_items"
; 手机适配（A1）：设计画布固定 1152×648，用 keep 等比缩放 + 居中，
; 左右留出的边框由 default_clear_color 涂成页面底色（#E6F0FA），
; 不再是 expand 的「右侧缺一块」。桌面 16:9 全屏不受影响（比例吻合 → 无边）。
window/stretch/aspect="keep"        ; ← 4.7 的默认值，已由引擎删除，行为不变
```

```ini
[rendering]

textures/vram_compression/import_etc2_astc=true
; 留边色 = 页面底色 #E6F0FA（与 GameUI.PAGE_BG_COLOR 同值）：
; 手机宽高比与 16:9 不符时，keep 留出的两条边和页面底色连成一片，看不出"黑框"
environment/defaults/default_clear_color=Color(0.902, 0.941, 0.98, 1)
```

### 8.4 变更日志

- 2026-11-17 Slice 0：新增 `tools/run_tests.gd`（Godot 自编排测试运行器，`OS.execute` 拿真实退出码）、
  `tools/gen_facade_list.gd`（门面清单机械生成器）、`tests/verify_ui_facade.gd`（77 方法 / 4 字段 / 2 常量的门面守卫）；
  基线 **47/47 全绿**（约 2300 条断言，`FAIL:` 0、`ABORT:` 0）。
- 2026-11-17 结论更正：原计划「回滚 `project.godot`」**不成立**。`window/stretch/aspect="keep"` 是 Godot 4.7
  的引擎默认值（`ProjectSettings.property_get_revert("display/window/stretch/aspect")` 实测返回 `keep`），
  引擎每次保存都会删掉等于默认值的键 —— 删掉与写上完全等价。真正损失的是两段手写注释，已原文归档到 §8.4。
- 2026-11-17 工具方案更正：原计划 `tools/run_tests.bat` **不可行**。cmd 用 GBK 代码页读 UTF-8 批处理，
  含中文的 `rem` 行被拆成多段执行、`if errorlevel` 判断失效（实测日志前 6 行全是残渣），
  无法承担「每片必须全绿」的把关职责，故改为 `.gd` 编排器。
- 2026-11-17 **Slice 1 完成**：新增 `scripts/ui/{UITheme,TouchMetrics,Toast,PageRouter}.gd`（604 行），
  root 7651 → 7357 行，47/47 全绿。三条必须记住的实现细节（都是本轮踩出来的）：
  1. **模块字段 `var _ui = null` 不能写类型**。GDScript 对静态类型做成员解析：写成 `_ui: Control` 时，
     `_ui.CARD_W` 会在**编译期**报「Control 无成员 CARD_W」（常量和私有方法都不是静态类型上的成员），
     只有动态类型（Variant）才能同时读到 root 的 const 与私有方法。
  2. **`:=` 无法从动态类型推断**：`var timer := _ui.get_tree().create_timer(...)` 直接编译失败
     （`Cannot infer the type of "timer"`），必须 `var timer: SceneTreeTimer = ...`。
     同理 `_touch_fs(base, bonus = TOUCH_FS_BONUS)` 的默认值是编译期常量、不能跨脚本取 →
     模块里改成必填两参，root 转发方法保留原默认值，调用点零改动。
  3. **常量下沉推迟到 Slice 5**：`verify_hand_view:54`、`verify_motion:63/255/256/275` 直读
     `scene.CARD_W` / `scene.CARD_H` / `scene.PAGE_BG_COLOR`。本轮让这些命中继续留在 root，
     避免 40+ 处引用一次性改动；真正下沉时用 `const CARD_W := HandViewScript.CARD_W` 别名（铁律 3）。
- 2026-11-17 **Slice 2a 完成**：新增 `scripts/ui/CardMotion.gd`（200 行 / 10 方法）与
  `scripts/ui/HandView.gd`（1329 行 / 65 方法），root 7357 → **6098 行**，47/47 全绿、
  `--quit-after 60` 冒烟 0 ERROR / 0 WARNING。同时新增搬运工具 `tools/move_funcs.gd`（§5.4）。
  本轮踩出的两条新坑（都自带编译器保护，不会静默出错）：
  4. **引擎自带实例方法不会被自动加前缀**。`create_tween()` / `get_tree()` /
     `get_global_mouse_position()` 不是 root 的自定义符号，工具只认 root 符号表 →
     原样落进模块就变成 RefCounted 上不存在的调用。用 `--also=` 显式登记；
     `--check-only` 会当场点名（`Function "create_tween()" not found in base "RefCounted"`）。
  5. **跨模块调用一律绕回 root 转发器，默认值由转发器补齐**。`_ui._make_drag_ghost(src)` 命中 root 的
     同名转发，转发器再按 `alpha = DRAG_GHOST_ALPHA` 补默认值 → 模块签名可以没有默认值，
     而全项目调用点一个字都不用改。前提仍是「转发方法名 = 原方法名」这条铁律。
  另：`_process` 保持 root 原样（唯一引擎钩子），只把它调用的 `_update_hand_drag()` /
  `_update_hand_hover()` 换成转发方法 —— R5 的「顺序变化」风险因此为 0。




