# 化学碰撞 — 程序架构与实现文档

> **版本**: 7.0  
> **日期**: 2026-07-09  
> **引擎**: Godot 4.x / GDScript

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [数据层](#3-数据层)
4. [逻辑层](#4-逻辑层)
5. [表现层](#5-表现层)
6. [场景结构](#6-场景结构)
7. [数据流](#7-数据流)
8. [关键算法](#8-关键算法)

---

## 1. 项目概览

"化学碰撞"是一款以元素周期表为主题的多人卡牌对战游戏。项目按 **MVC 分层**组织：

```
┌─────────────────────────────────────────┐
│                      表现层              │
│  Main.tscn  GameUI.gd                   │
│  4页UI  着色与状态渲染  按钮交互         │
│  手牌上限检查  牌库计数                  │
├─────────────────────────────────────────┤
│                      逻辑层              │
│  GameManager.gd  →  规则引擎 & 牌权轮转  │
│  Utils.gd        →  牌型判定 & 化合物   │
├─────────────────────────────────────────┤
│                      数据层              │
│  CardData.gd      →  卡牌属性定义       │
│  CardDatabase.gd  →  牌库生成 & 洗牌    │
└─────────────────────────────────────────┘
```

---

## 2. 文件结构

```
chemical-1/
├── project.godot                      ← 引擎配置（主场景 Main.tscn）
├── Main.tscn                          ← 场景文件（4 页：Start/Game/Help/End）
├── scripts/
│   ├── CardData.gd                    ← 数据模型（13 个属性 + 16 族常量）
│   ├── CardDatabase.gd                ← 牌库（28 种，主族 6 张 / 副族 4 张 = 154 张）
│   ├── GameManager.gd                 ← 规则引擎（牌权轮转、族炸接炸链、化合物校验）
│   ├── GameUI.gd                      ← UI 控制器（着色、步骤流、AI、手牌上限、牌库计数）
│   └── Utils.gd                       ← 工具函数（detect_pattern、get_compound_formula、compare_cards）
├── CHEMICAL_COLLISION_GAME.md         ← 游戏设计文档 (v7.0)
├── GAMEPLAY_RULES.md                  ← 玩法规则与程序实现文档 (v7.0)
├── ARCHITECTURE.md                    ← 本文档（程序架构与实现）(v7.0)
├── COLORING_DOCUMENTATION.md          ← 元素着色文档 (v2.0)
└── COMPOUND_MECHANISM_COMPARISON.md   ← 化合物机制新旧对比
```

---

## 3. 数据层

### 3.1 CardData.gd — 卡牌数据模型

**文件**: `scripts/CardData.gd`（139 行）

**职责**: 定义单张卡牌的数据结构。

**关键属性**:

| 属性 | 类型 | 代码位置 | 说明 |
|------|------|----------|------|
| `symbol` | String | L36 | 元素符号 "Na" |
| `name_cn` | String | L37 | 中文名 "钠" |
| `name_en` | String | L38 | 英文名 "Sodium" |
| `atomic_number` | int | L39 | 原子序数 1–35 |
| `group` | String | L40 | 族 "IA"/"VIIA"/"VIII"/... |
| `period` | int | L41 | 周期 1–4 |
| `element_type` | String | L42 | "金属"/"非金属"/"准金属"/"稀有气体" |
| `common_valence` | Array | L45 | 化合价列表 e.g. `[1]` `[-1,1,5]` |
| `atomic_weight` | float | L47 | 相对原子质量，用于排序平局 |

**16 族常量** (L7–L22): IA / IIA / IIIA / IVA / VA / VIA / VIIA / 0 / IB / IIB / IIIB / IVB / VB / VIB / VIIB / VIII

**关键方法**:
| 方法 | 位置 | 说明 |
|------|------|------|
| `get_display_name()` | L71 | 返回 "Na 钠" 格式 |
| `get_full_info()` | L76 | tooltip 文本（英文名/原子序数/族/化合价/质量） |
| `can_bond_with(other)` | L91 | 判断两元素化合价是否正负可配平 |

### 3.2 CardDatabase.gd — 牌库

**文件**: `scripts/CardDatabase.gd`（101 行）

**职责**: 生成 154 张牌的牌库（前四周期 28 种元素），提供洗牌和抽牌功能。

**数据结构**:
```gdscript
static func get_element_data() -> Array   # 28 条元素数据
const SUBGROUP_SYMBOLS = ["Cr","Mn","Fe","Co","Ni","Cu","Zn"]
const MAIN_COPIES = 6                     # 主族 6 张
const SUB_COPIES = 4                      # 副族 4 张

var deck: Array = []                      # 当前牌库（154 张）
```

**关键方法**:
| 方法 | 位置 | 说明 |
|------|------|------|
| `generate_deck()` | L82 | 21种×6 + 7种×4 = 154 张 |
| `shuffle()` | L92 | Fisher-Yates 洗牌 |
| `draw_card()` | L102 | 弹出栈顶 |
| `draw_cards(n)` | L109 | 批量抽牌 |
| `get_remaining_count()` | L120 | 牌库剩余数量 |

**牌数分配**:
| 周期 | 主族（各6张） | 副族（各4张） |
|------|------------|------------|
| 1 | H, He | — |
| 2 | Li, Be, B, C, N, O, F, Ne | — |
| 3 | Na, Mg, Al, Si, P, S, Cl, Ar | — |
| 4 | K, Ca, Br | Cr, Mn, Fe, Co, Ni, Cu, Zn |

---

## 4. 逻辑层

### 4.1 GameManager.gd — 规则引擎

**文件**: `scripts/GameManager.gd`（411 行）

**职责**: 回合管理、出牌校验、族炸接炸链、牌权轮转、玩家状态。

**核心数据结构**:
```gdscript
var players: Array = []                  # L14 — PlayerInfo 数组
var current_player_index: int = 0        # L15 — 当前回合玩家索引
var table_cards: Array = []              # L18 — 桌面牌组
var table_pattern: int = -1              # L20 — 桌面牌型，限制接牌类型
var is_round_starter: bool = true        # L21 — 是否自由出牌
var clan_bomb_chain_active: bool = false # L25 — 接炸链激活
var clan_bomb_owner: int = -1            # L26 — 接炸链引爆者
var compound_immune: bool = false        # L23 — 溢出化合物免疫
var database: RefCounted                 # L13 — 牌库引用（含 get_remaining_count）
```

**PlayerInfo 内部类** (L28–L61):
```gdscript
class PlayerInfo:
    var player_name: String
    var hand: Array             # 手牌（CardData 列表）
    var is_ai: bool             # 是否 AI
    var has_passed: bool        # 本轮是否 Pass
    var clan_bomb_cooling: bool # 是否被族炸冷却
    
    func get_hand_count() -> int   # 手牌数量
    func sort_hand_by_atomic_number()  # 原子序数排序
```

**核心函数流程图**:

```
init_game(total, ai) → bool                        # L64
  ├── 验证 (3 ≤ total ≤ 8, ai < total)
  ├── create Database → shuffle → deal（每人8张）
  └── return true

play_cards(idx, cards, cv={}) → int                # L116
  ├── detect_pattern(cards, skip_bomb)
  ├── 族炸? → 冷却检查 → 接炸比较 → 启动链
  ├── 非族炸? → 牌型匹配检查 → 比大小
  ├── 化合物? → get_compound_formula() → ratio_ok?
  ├── remove_cards → update table
  ├── 族炸? → mark cooling → 接炸链 → 胜利检查
  ├── 化合物? → 解除冷却 → 溢出免疫
  └── next_turn() 或 胜利

player_pass(idx)                                    # L217
  ├── 接炸模式? → mark pass，不抽牌
  └── 正常模式? → mark pass，抽 1 张

next_turn()                                         # L236
  ├── 接炸链? → _intercept_next()
  ├── unpassed ≤ 1? → _start_new_round()
  └── 找下一位有牌 & 未 pass 的玩家

_start_new_round()                                  # L282
  ├── clear table
  ├── current_player_index = (idx + 1) % total
  ├── 顺时针找有牌玩家
  └── is_round_starter = true

_intercept_next()                                   # L258
  └── 找下一位未 pass 且非 owner 玩家

_finish_clan_bomb_chain()                           # L269
  └── 清桌面，owner 自由出牌
```

### 4.2 Utils.gd — 工具函数

**文件**: `scripts/Utils.gd`（279 行）

**职责**: 牌型判定、化合价配平、比大小。

**牌型枚举** (L9–L13):
```gdscript
enum CardPattern { ELEMENT, COMPOUND, CLAN_BOMB }
```

**detect_pattern** (L21–L47):

```
输入: cards: Array, skip_clan_bomb: bool = false
流程:
  1. cards.size() == 1 → ELEMENT
  2. cards.size() == 2 && same element && in {H,N,O,F,Cl} → ELEMENT (X₂)
  3. !skip_clan_bomb && 同族不同元素 ≥2 → CLAN_BOMB
  4. cards.size() ≥ 2 && 配平可配 → COMPOUND
  5. else → -1
```

> `skip_clan_bomb` 标志: 当 `custom_valences.size() >= 2` 时由 `play_cards` 传递，禁止族炸检测，强制走化合物路径。

**get_compound_formula** (L113–L176):

```
输入: cards: Array, custom_valences: Dictionary
流程:
  1. 统计每种元素的出现次数 → elem_counts
  2. 分类: 正价列表(pos_list), 负价列表(neg_list)
     - 如果有 custom_valences → 按用户选择
     - 否则 → 金属优先正价，非金属优先负价
  3. ratio_ok = Σ count×valence == 0
  4. 生成 Unicode 化学式 (H₂, NaCl, Al₂O₃, KBr, FeCl₂)
```

**compare_cards** (L213–L252):

```
输入: cards_a, cards_b: Array
返回: 1 (a 更大), -1 (b 更大), 0 (相等)
流程:
  1. 族炸 vs 非族炸 → 族炸大
  2. 族炸 vs 族炸 → 3 张 > 2 张，同数量比序数和
  3. 化合物 vs 化合物 → 序数和小→大
  4. 单质 vs 单质 → 序数和小→大
  5. 跨牌型: 族炸 > 化合物 > 单质
```

**_compare_by_total_atomic** (L255–L270):
```
序数和相同时 → 比 atomic_weight 总和 → 质量大→牌弱势
```

**双原子分子** (L16):
```gdscript
const DIATOMIC_SYMBOLS = ["H", "N", "O", "F", "Cl"]
```

---

## 5. 表现层

### 5.1 GameUI.gd — UI 控制器

**文件**: `scripts/GameUI.gd`（690 行）

**职责**: 页面管理、手牌渲染、出牌步骤流、AI 候选、状态显示、手牌上限检查、牌库计数。

**关键变量**:
```gdscript
var game_manager: RefCounted     # L12 — 规则引擎引用
var deck_count_label: Label       # L31 — 牌库计数标签
var selected_indices: Array       # L38 — 选中的手牌索引
var step_mode: int                # L39 — 0=选牌 / 1=选牌型 / 2=选化合价
var compound_selections: Array    # L40 — 用户选择的化合价 [{symbol, valence}]
```

**页面管理**:

| 函数 | 位置 | 说明 |
|------|------|------|
| `_setup_pages()` | L57 | 绑定所有按钮 + SpinBox + DeckCountLabel |
| `_show_start_page()` | L96 | 重置所有页面可见性 |
| `_on_start_game()` | L112 | 人数验证 → 初始化游戏 |
| `_on_exit_program()` | L132 | `get_tree().quit()` |
| `_show_end_page()` | L590 | 显示获胜者 |

**状态渲染**:

| 函数 | 位置 | 说明 |
|------|------|------|
| `_format_player_status()` | L162 | 圆形状态：● 玩家1 ◄ → ● AI1 ❄ → ● AI2 ⏸；含手牌数 |
| `_update_deck_count()` | 新增 | 牌库剩余 + 手牌上限 显示 |

**手牌渲染** (`_update_hand_buttons()`, L318–350):

```
人类玩家回合:
  sort_hand_by_atomic_number() → 生成 Button → 着色 → 选中黄色高亮
  HFlowContainer 自动换行（容器宽 920px，每行约 6 张 140px 卡牌）
AI 回合:
  Label("等待 AI 行动中...") → 1.5s 定时器 → _ai_auto_play()

着色规则 (_get_card_color, L290–307):
  优先级: 精确符号 > 族匹配 > 类型匹配
  H 天蓝 / O 深蓝 / N 紫色 / F,Cl 浅绿色 / Br 棕色
  C,B,Si,S 亮黄 / P 浅粉 / 金属灰 / 稀有气体白
```

**出牌步骤流** (`_update_action_panel()`, L252–270):

```
step0: "出牌(选牌型)" "跳过"
step1: "作为单质打出" "合成化合物" "作为族炸打出" "返回"
step2: _update_valence_buttons() → 为每种元素选化合价 → "确认打出"
```

**手牌上限检查** (`_on_pass()`, L551–558):

```
手牌数 ≥ min(玩家数×4, 18) → 阻止跳过，提示"手牌已达上限"
手牌数 < 上限 → 正常 player_pass()
```

**化合物确认** (`_on_confirm_compound()`, L462):

```
1. 构建 custom_valences dict
2. 验证正价 + 负价各一
3. 统计每种元素的可用数量
4. GCD 计算比例 → na, nb
5. 精确收集 na + nb 张牌
6. play_cards(idx, compound_cards, custom_valences)
7. 电荷平衡验证 (3+ 元素)
```

**AI 策略** (`_ai_try_play()`, L620):

```
优先顺序: 族炸 → 化合物 (O(n²) 配对) → 双原子分子 → 单质单张
  每一步都调用 play_cards() → 检查 OK
  全部过不了? → player_pass()
```

---

## 6. 场景结构

### 6.1 Main.tscn — 4 页布局

**文件**: `Main.tscn`（371 行）

```
Main (Control)                       ← 脚本 GameUI.gd
├── StartPage                        ← 开始页（初始可见）
│   ├── StartTitle                   ← "化学碰撞 Chemical Collision"
│   ├── PlayerCountLabel             ← "总玩家人数:"
│   ├── PlayerCountSpin              ← SpinBox 3–8
│   ├── AiCountLabel                 ← "AI 人数:"
│   ├── AiCountSpin                  ← SpinBox 0–7
│   ├── StartButton                  ← "开始游戏"
│   └── ExitButton                   ← "退出程序"
├── HelpPage                         ← 帮助页（横版双栏）
│   ├── HelpBackground               ← 浅蓝白背景 Color(0.92,0.95,0.98)
│   ├── HelpTitle                    ← "帮助与规则"
│   ├── HelpLeftColumn               ← 左栏：规则详解/牌型/比大小/接牌/手牌上限
│   ├── HelpRightColumn              ← 右栏：28种元素总览/着色对照/常用化学式
│   └── HelpBackBtn                  ← "返回"
├── GamePage                         ← 游戏页
│   ├── GameBackground               ← 深蓝背景 Color(0.45,0.62,0.95)
│   ├── TitleLabel                   ← "化学碰撞"（黑色）
│   ├── DeckCountLabel               ← 牌库剩余 + 手牌上限（黑色）
│   ├── InfoLabel                    ← 牌权状态 + 手牌数（黑色）
│   ├── TableLabel                   ← 桌面牌型（黑色）
│   ├── HandContainer (HFlow)        ← 手牌按钮（920px宽，6/行自动换行）
│   ├── ActionPanel (HBox)           ← 操作按钮
│   ├── HintButton                   ← "显示提示"
│   ├── HelpBtn                      ← "帮助"
│   ├── QuitButton                   ← "退出游戏"
│   ├── CardInfoLabel                ← 提示文本（黑色）
│   └── LogLabel                     ← 游戏日志
└── EndPage                          ← 结束页
    ├── EndTitle                     ← "游戏结束"
    ├── EndLabel                     ← 获胜者
    └── EndButton                    ← "返回主页"
```

---

## 7. 数据流

### 7.1 启动流程

```
Main.tscn 加载
  → Main 节点挂载 GameUI.gd
    → _ready()
      → _setup_pages()  ← 绑定 UI 引用（含 DeckCountLabel）
      → _show_start_page()  ← 显示开始页

用户点击 "开始游戏"
  → _on_start_game()
    → int(spin.value) → total, ai
    → 验证 (ai < total)
    → _init_game(total, ai)
      → GameManager.new() → init_game(total, ai)
        → CardDatabase.new() → generate_deck() → shuffle()
        → 创建 PlayerInfo[] → 发牌 8 张/人
        → return true
      → _refresh_ui()
```

### 7.2 回合循环

```
_refresh_ui()
  ├── InfoLabel ← _format_player_status()（含手牌数）
  ├── TableLabel ← table_cards 状态
  ├── ActionPanel  ← 按钮状态
  ├── HandContainer ← 手牌渲染
  ├── CardInfoLabel ← 可出牌型提示
  └── DeckCountLabel ← 牌库剩余 + 手牌上限

人类操作:
  选牌 → 选牌型 → play_cards(idx, cards, cv) → OK → _refresh_ui()
  跳过 → 手牌上限检查 → player_pass(idx) → _refresh_ui()

AI 操作:
  1.5s 延迟 → _ai_try_play() → play_cards 遍历 → pass → _refresh_ui()

play_cards() 内部:
  detect_pattern → 比大小/牌型匹配 → 化合物比例 → remove_cards
  → 族炸链启动 / 正常 next_turn / 胜利 → GAME_OVER

next_turn() 内部:
  族炸? → _intercept_next()
  unpassed ≤ 1? → _start_new_round()
  顺时针找下一玩家
```

### 7.3 牌权轮转流程

```
玩家 A 出牌 [Na]
  → play_cards(A, [Na])
    → remove_cards → table_cards=[Na] → next_turn()
      → next_idx = A+1 = B → B 回合

玩家 B 接牌 [He] (必须 > Na)
  → play_cards(B, [He])
    → compare([He], [Na]) → He:2 < Na:11 → OK
    → table_cards=[He] → next_turn()

玩家 C 过 → 上限检查 → player_pass(C) → mark passed → 抽牌
玩家 D 过 → 上限检查 → player_pass(D) → mark passed → 抽牌
玩家 A 过 → 上限检查 → player_pass(A) → mark passed → 抽牌
  → next_turn() → unpassed.size()=1 (只有 B) → _start_new_round()
    → current_idx = B → B+1 = C → C 自由出牌
```

---

## 8. 关键算法

### 8.1 牌型检测（`Utils.gd` L21–47）

```
detect_pattern(cards, skip_clan_bomb=false):
  ┌─ cards.size() == 1 ───────────────────→ ELEMENT
  ├─ size==2 && same element && {H,N,O,F,Cl} → ELEMENT (X₂)
  ├─ size==2 && same element && !H,N,O,F,Cl  → -1 (非法)
  ├─ !skip_clan_bomb && _is_clan_bomb() ──→ CLAN_BOMB
  ├─ _is_compound(cards) ────────────────→ COMPOUND
  └─ else ────────────────────────────────→ -1
```

### 8.2 族炸检测（`Utils.gd` L59–74）

```
_is_clan_bomb(cards):
  var group = cards[0].group
  var seen = []
  for c in cards:
    if c.group != group → return false
    if c.symbol in seen → return false  (must be different elements)
    seen.append(c.symbol)
  return seen.size() >= 2
```

### 8.3 化合物配平（`Utils.gd` L113–176）

```
get_compound_formula(cards, custom_valences):

  // Step 1: 统计元素
  elem_counts = {Na:1, Cl:1, K:1, Br:1, ...}

  // Step 2: 正负价分类
  pos_list: [{symbol, valence, count}, ...]   ← metal / custom
  neg_list: [{symbol, valence, count}, ...]

  // Step 3: 电荷平衡验证
  total_pos = Σ pos.count × pos.valence
  total_neg = Σ neg.count × neg.valence
  ratio_ok = (total_pos == total_neg && total_pos > 0)

  // Step 4: 化学式生成
  for e in pos_list: formula += e.symbol + subscript(e.count)
  for e in neg_list: formula += e.symbol + subscript(e.count)
  // Na₁Cl₁ → "NaCl", Al₂O₃ → "Al₂O₃", KBr → "KBr"
```

### 8.4 比大小（`Utils.gd` L213–252）

```
compare_cards(a, b):
  pattern_a = detect_pattern(a)
  pattern_b = detect_pattern(b)

  if pattern_a == CLAN_BOMB && pattern_b != CLAN_BOMB → a 大
  if both CLAN_BOMB:
    a.size >= 3 → a 大
    b.size >= 3 → b 大
    same size → _compare_atomic(a, b)
  if same pattern → _compare_atomic(a, b)
  cross-pattern: CLAN_BOMB > COMPOUND > ELEMENT

_compare_atomic(a, b):
  sum_a = Σ atomic_number(a)
  sum_b = Σ atomic_number(b)
  if sum_a < sum_b → a 大
  if sum_a > sum_b → b 大
  // tiebreak: 比 atomic_weight 总和 → 质量大 → 牌弱势
```

### 8.5 牌权轮转（`GameManager.gd` L236–300）

```
next_turn():
  if clan_bomb_chain_active: _intercept_next(); return

  var unpassed = [players with hand>0 && !has_passed]
  if unpassed.size() <= 1:
    _start_new_round(); return  // 总人数-1 人连续过

  // 顺时针找下一个未 pass 的玩家
  for i in range(total):
    next_idx = (current + 1 + i) % total
    if players[next_idx].hand > 0 && !players[next_idx].has_passed:
      current_player_index = next_idx; return

  _start_new_round()

_start_new_round():
  clear table
  current_player_index = (current + 1) % total  // 顺推一名玩家
  for i in range(total):
    if players[current].hand > 0:
      is_round_starter = true; return
    current_player_index = (current + 1) % total
```

### 8.6 手牌上限计算（`GameUI.gd` L553）

```
_on_pass():
  var hand_limit = min(players.size() * 4, 18)
  if cp.get_hand_count() >= hand_limit:
    show_info("手牌已达上限 (X张)，无法跳过抽牌！请出牌。")
    return  // 阻止跳过
  game_manager.player_pass(...)
```

### 8.7 牌库计数（`GameUI.gd` 新增）

```
_update_deck_count():
  var count = database.get_remaining_count()
  var hand_limit = min(players.size() * 4, 18)
  deck_count_label.text = "牌库剩余: %d张  手牌上限: %d张" % [count, hand_limit]
```

---

**文档版本**: 7.0  
**最后更新**: 2026-07-09