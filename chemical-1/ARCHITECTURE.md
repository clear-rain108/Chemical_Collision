# 化学碰撞 — 程序架构与实现文档

> **版本**: 14.7  
> **日期**: 2026-11-04  
> **引擎**: Godot 4.x / GDScript

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [数据层 - CardData.gd](#3-数据层---carddatagd)
4. [数据层 - CardDatabase.gd](#4-数据层---carddatabasegd)
5. [逻辑层 - 牌型计算](#5-逻辑层---牌型计算cardpatternsgd--compoundsolvergd)
6. [逻辑层 - GameManager.gd](#6-逻辑层---gamemanagergd)
7. [逻辑层 - 辅助模块](#7-逻辑层---辅助模块)
8. [表现层 - GameUI.gd](#8-表现层---gameuigd)
9. [场景结构 - Main.tscn](#9-场景结构---maintscn)
10. [数据流](#10-数据流)
11. [关键算法](#11-关键算法)
12. [触屏档案（A1/B/C）](#12-触屏档案a1bc)

---

## 1. 项目概览

"化学碰撞"是一款以元素周期表为主题的多人卡牌对战游戏。项目按 **MVC 分层**组织：

```
┌─────────────────────────────────────────┐
│                      表现层              │
│  Main.tscn  GameUI.gd  TutorialUI.gd    │
│  6页UI  着色与牌面渲染  按钮交互          │
│  教程引导显示                             │
├─────────────────────────────────────────┤
│                      逻辑层              │
│  GameManager.gd   →  规则引擎 & 牌权轮转  │
│  CardPatterns.gd  →  牌型判定 & 比大小   │
│  CompoundSolver.gd → 化合物配平 & 命名   │
│  AIPlayer.gd      →  AI 出牌策略        │
│  PlayerManager.gd →  人数规划 & 玩家     │
│  GameLogger.gd    →  信息记录           │
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
├── project.godot                      ← 引擎配置
├── Main.tscn                          ← 6 页场景
├── scripts/
│   ├── CardData.gd                    ← 数据模型：13属性+16族常量+序列化
│   ├── CardDatabase.gd                ← 牌库：29种元素(卤族10/高8/主6/副4)=182张
│   ├── PlayerManager.gd               ← 人数规划：PlayerInfo类/玩家创建/发牌/手牌上限
│   ├── GameLogger.gd                  ← 信息记录：统一日志模块
│   ├── CardPatterns.gd                ← 牌型计算：detect_pattern/族炸/顺序/比大小
│   ├── CompoundSolver.gd              ← 化合物形成：配平/IUPAC命名/有机物识别
│   ├── GameManager.gd                 ← 规则引擎：play_cards/牌权/接炸/上限弃牌
│   ├── AIPlayer.gd                    ← AI决策：出牌策略（族炸/化合物/双原子/单质/接顺序；卤族互化读开关）
│   ├── TutorialController.gd          ← 教程状态机：关卡初始化/预设手牌/进度检查
│   ├── TutorialUI.gd                  ← 教程内容：引导文本/成功提示（静态）
│   ├── HelpContent.gd                 ← 帮助中心内容：3 Tab 卡片数据（静态）
│   └── GameUI.gd                      ← UI控制器：页面切换/牌面渲染/步骤流/着色
├── tests/
│   ├── verify_refactor.gd             ← 模块单测（牌型/化合物/日志/玩家/Q4牌型选择）
│   ├── verify_integration.gd          ← 集成测试（GameManager + AIPlayer）
│   ├── verify_logger.gd               ← 日志转发测试
│   ├── verify_tutorial.gd             ← 教程控制器集成测试
│   ├── verify_ai_discard.gd           ← AI 上限自动弃牌测试（Q1+Q2）
│   ├── verify_hand_layout.gd          ← 手牌布局 / 悬停状态机 / 样式工厂 / 警告 toast
│   ├── verify_hand_reorder.gd         ← 手牌拖拽重排（手动排列 / 按序恢复 / 选中索引进→对象）
│   ├── verify_motion.gd               ← 动效与排版：页面淡入 / 按钮缩放 / 卡牌字号
│   ├── verify_help_page.gd            ← 帮助中心：结构 / Tab 懒加载 / 字号 / 牌库数字
│   ├── verify_end_page.gd             ← 结束页 / 教学页：结构画风 / 四态文案 / 按钮去向 / 统计数字
│   └── verify_halogen.gd              ← 卤族互化：引擎 -7 / 族炸不误伤 / 提示 / AI / UI / 教程
├── CHEMICAL_COLLISION_GAME.md         ← 游戏设计文档
├── GAMEPLAY_RULES.md                  ← 玩法规则文档
├── ARCHITECTURE.md                    ← 本文档
├── COLORING_DOCUMENTATION.md          ← 元素着色文档
├── COMPOUND_MECHANISM_COMPARISON.md   ← 化合物机制对比
└── AI_PLAYER_AUDIT.md                ← AI与玩家逻辑对照审计
```

### 功能划分概览

| 功能维度 | 模块 | 说明 |
|---------|------|------|
| **UI** | GameUI.gd / TutorialUI.gd | 页面切换、牌面渲染、出牌步骤流、教程引导显示 |
| **牌型计算** | CardPatterns.gd + CompoundSolver.gd | 纯静态函数：牌型检测、化合物配平、命名、比大小 |
| **牌的使用和打出** | GameManager.gd | 出牌合法性校验、桌面状态、回合轮转 |
| **信息记录** | GameLogger.gd | 统一日志写入/缓存/获取 |
| **人数规划** | PlayerManager.gd | 玩家创建、发牌、手牌上限计算 |
| **AI决策** | AIPlayer.gd | AI 出牌策略（独立于 UI） |
| **教程控制** | TutorialController.gd | 教程关卡状态机、预设手牌、进度检查 |
| **数据层** | CardData.gd + CardDatabase.gd | 卡牌数据结构、牌库生成与洗牌 |


---

## 3. 数据层 - CardData.gd

**职责**: 定义单张化学元素卡牌的数据结构。

### 模块结构

| 模块 | 行号 | 说明 |
|------|------|------|
| 族常量（16个）| L7-22 | IA~VIII + 稀有气体 |
| 元素类型常量 | L24-28 | 金属/非金属/准金属/稀有气体 |
| 单质形态常量 | L30-34 | 固体/液体/气体/人造 |
| 属性字段（13个）| L38-50 | symbol, name_cn, atomic_number, group... |
| 构造函数 | L54-68 | 13参数初始化 |
| 显示方法 | L72-84 | get_display_name(), get_full_info() |
| 逻辑判断 | L87-102 | is_same_group(), can_bond_with() |
| 序列化 | L105-139 | to_dict(), from_dict() |

---

## 4. 数据层 - CardDatabase.gd

**职责**: 牌库生成（182张）与 Fisher-Yates 洗牌。

### 张数分级

| 常量 | 元素 | 张数 |
|------|------|------|
| HALOGEN_SYMBOLS | F, Cl, Br, I | 10 |
| HIGH_COUNT_SYMBOLS | H, O, S | 8 |
| SUBGROUP_SYMBOLS | Cr~Zn (7种) | 4 |
| 其余主族 (15种) | — | 6 |

### 模块结构

| 模块 | 行号 | 说明 |
|------|------|------|
| 张数常量 | L9-16 | 四级张数定义 |
| 元素数据 | L19-54 | 29种元素原始数据（13字段/元素）|
| 牌库生成 | L60-79 | generate_deck() 按 sym 动态计算 copies |
| 洗牌与抽牌 | L83-106 | Fisher-Yates shuffle, draw_card, draw_cards |
| 查询 | L110-111 | get_remaining_count() |

---

## 5. 逻辑层 - 牌型计算（CardPatterns.gd + CompoundSolver.gd）

**职责**: 牌型判定、化合物配平、命名、比大小。所有方法均为 `static`，无状态、可独立测试。

### 5.1 CardPatterns.gd（牌型计算核心）

**职责**: 牌型枚举、牌型检测、族炸/顺序检测、比大小。

```gdscript
CardPatterns.detect_pattern(cards, skip_clan_bomb=false):
  1. 1张 → ELEMENT
  2. 2张同元素 & H/N/O/F/Cl → ELEMENT (X₂)
  3. !skip_clan_bomb & 同族≥2不同元素 → CLAN_BOMB
  4. ≥3张连续原子序数 → SEQUENCE
  5. is_organic() → ORGANIC
  6. is_compound() → COMPOUND
  7. 否则 → -1
```

| 模块 | 说明 |
|------|------|
| CardPattern 枚举 + DIATOMIC_SYMBOLS | 牌型定义与双原子分子元素集 |
| detect_pattern / _is_same_element | 牌型检测总入口 |
| _is_sequence / _is_clan_bomb | 顺序 / 族炸检测 |
| compare_cards / _compare_by_total_atomic | 比大小（族炸>有机物>化合物>单质）|
| get_pattern_name / get_element_display | 牌型中文名 / 单质显示 |

### 5.2 CompoundSolver.gd（化合物形成模块）

**职责**: 化合物检测、化合价配平、IUPAC 命名、有机物识别。**后续扩展只需修改此文件**。

| 模块 | 说明 |
|------|------|
| 命名常量表 | OXYANION_MAP / OXYACID_FORMULAS / ACID_SALT_ANIONS / VARIABLE_METAL_CN_NAMES / NONMETAL_CN_NAMES（数据表驱动）|
| is_compound | 化合物合法性检测 =「默认配平成功 或 价态搜索可配平」，二者都要求电负性有序 |
| _assign_valences | **唯一价态分配入口**：默认配平（金属取最高正价 / 非金属取最低负价 / 无金属时提升 H 与酸中心原子）；显式化合价走同一函数校验 |
| _search_valences / _valence_domains / _dfs_valences / _valence_assignment_ok | 默认配平失败时的价态搜索：2~3 种元素、按实际张数电荷平衡、正价元素电负性 ≤ 负价元素（NCl₃/BCl₃/ClF 由此识别，NCl/BrN/IN 被排除）|
| get_valence_pairs | AI / 提示共用的价态出口（默认配平优先，失败再搜索）；人类面板列 `common_valence` 全价，最终由 `_assign_valences` 裁决 |
| get_compound_formula | 配平 + 化学式生成（`ratio_ok=false` 即视为打不出）|
| get_compound_name / _try_get_oxy_name | IUPAC 命名（含氧酸/含氧酸盐/酸式盐）|
| is_organic / get_organic_name | 有机物识别与命名（CH4/C2H6/C3H8 及单一卤代物）|
| _to_subscript / _gcd | 化学式下标渲染 / 配平辅助 |

**扩展点**（数据表驱动，修改数据即扩展能力）：
- 新增含氧酸 → `OXYANION_MAP` 加条目
- 新增有机物 → `is_organic()` / `get_organic_name()` 扩展匹配分支
- 新增变价金属命名 → `VARIABLE_METAL_CN_NAMES` 加条目

### 5.3 依赖方向

```
CardPatterns.detect_pattern()  → 判断 COMPOUND/ORGANIC 时调用
		↓（单向，无环）
CompoundSolver.is_compound() / is_organic()
```

---

## 6. 逻辑层 - GameManager.gd

**职责**: 回合管理、出牌校验、族炸接炸链、顺序牌型约束（`sequence_constraint_target`：只作用于被指定的那名玩家）、上限弃牌（牌的使用和打出）。玩家信息已拆至 PlayerManager，日志已拆至 GameLogger。

### PlayerInfo 玩家信息类（已拆至 PlayerManager.gd）

```
PlayerManager.PlayerInfo
属性: player_name, hand, is_ai, has_passed, clan_bomb_cooling, hand_manual_order
方法: get_hand_count(), add_card(), remove_cards(),
	  sort_hand_by_atomic_number(force := false), move_card(from_idx, to_idx)
```

> **手牌顺序的唯一真源是 `hand` 数组本身**，界面每次都照抄数组顺序，不存第二套顺序。
> - `sort_hand_by_atomic_number()`：`hand_manual_order` 为 true 时直接返回 —— 抽牌、
>   出牌、换人触发的所有自动排序都不会打回玩家的手动排列；`force=true` 只给「按序」按钮用，
>   排完即把标志复位为 false（回到自动模式）。
> - `move_card(from, to)`：拖拽落库的唯一入口，`remove_at` + `insert`，成功即进入手动模式；
>   越界 / 原地不动返回 false，调用方据此跳过整排重绘。

### 核心变量

| 变量 | 说明 |
|------|------|
| clan_bomb_chain_active | 族炸接炸链激活 |
| clan_bomb_owner | 接炸链引爆者索引 |
| clan_bomb_disabled | 禁用族炸（第一关） |
| tutorial_level | 0=自由模式, 1=第一关, 2=第二关 |
| tutorial_step | 当前教程步骤 |
| turn_count | 本局累计换手次数（`next_turn()` 每次推进 +1，`init_game` / `init_tutorial` 归零）；结束页「总回合」的唯一来源 |
| compound_immune | 溢出化合物免疫族炸 |
| organic_rules_enabled | 补充规则：有机物胜利（开始页 `OrganicCheckBox` 写入） |
| sequence_rules_enabled | 补充规则：顺序牌型（开始页 `SequenceCheckBox` 写入） |
| halogen_exchange_allowed | 补充规则：允许卤族互化（默认 `false`；只放开 COMPOUND，族炸始终合法） |
| element_limit_enabled | 补充规则：元素限制（默认 `false`；`true` 时牌库 = 前 20 号 + `allowed_extra_elements`） |
| allowed_extra_elements | 元素限制额外放行的符号（如 `["Fe","Cu"]`；关闭限制时忽略） |
| table_custom_valences | 桌面化合物实际化合价（play_cards 出牌时保存，渲染化学式/排序/化合价显示用）|
| sequence_constraint | 顺序牌指定牌型（`CardPattern.Pattern`；`-1` = 未指定）|
| sequence_constraint_active | 约束是否生效（`set_sequence_constraint()` 置 true；只有被指定的玩家结算后才置 false）|
| sequence_constraint_target | 被指定的座位号（`-1` = 无目标）。`set_sequence_constraint()` 取「**反转方向**上的下一名」（顺序牌在 `play_cards()` 里已先反转方向），并跳过手牌为空的玩家；`play_cards()` 只在 `player_index == sequence_constraint_target` 时校验，别人出牌 / 族炸 / 接炸链结束 / 跳过都不解除 |
| _get_hand_limit() | min(players×4, 18) |

### 核心函数流程

```
init_game(total, ai) → bool   （牌库 = generate_deck(get_allowed_symbols())，元素限制时只含前 20 号 + 勾选扩展）
play_cards(idx, cards, cv) → int
  ├─ 元素限制：开关开启且含越界元素 → -8（is_element_allowed 兜底）
  ├─ detect_pattern → 族炸/非族炸判定
  ├─ 化合物 + 开关关闭 + 含≥2种卤素 → -7（卤族互化，is_halogen_mix）
  ├─ 顺序约束：仅 idx == sequence_constraint_target 时校验，牌型不符 → -6
  ├─ 族炸: 冷却/免疫/接炸比较 → next_turn()（牌权移交）
  │        └─ 若 idx 正是 target 且约束为「族炸」→ 视为完成，清约束
  ├─ 化合物: 式子为空 或 ratio_ok=false → -1（假化合物拦截）
  │        └─ 保存 table_custom_valences → 溢出检查
  └─ 非族炸: 牌型匹配 → 比大小
player_pass(idx) → 上限检查 → 抽牌 → next_turn()
  └─ idx == target 时：罚抽 2 张并结束约束（达上限先弃 1 张）
player_discard_and_pass(idx, card) → 上限弃牌（target 额外罚抽 2 张并结束约束）
set_sequence_constraint(p) → target = 反转方向上的下一名（跳过空手牌）+ 日志 + next_turn()
player_fail_sequence_constraint(idx) → 罚抽 2 张 + has_passed + 清约束 + next_turn()
next_turn() → 族炸链? _intercept_next() : 找下一位未pass玩家
_init_tutorial(level) → 预设手牌 + 教程步骤初始化（含顺序约束三字段复位）
_check_tutorial_progress(pattern, human) → 进度检查
```

## 7. 逻辑层 - 辅助模块

### 7.1 PlayerManager.gd（人数规划）

**职责**: 玩家数量规划 / PlayerInfo 玩家信息类 / 发牌 / 手牌上限。

| 模块 | 说明 |
|------|------|
| MIN/MAX_PLAYERS / INITIAL_HAND_SIZE | 人数与初始手牌常量 |
| PlayerInfo 类 | player_name/hand/is_ai/has_passed/clan_bomb_cooling |
| create_players / validate_player_count | 玩家创建与配置校验 |
| deal_initial_hands | 初始发牌 |
| get_hand_limit | min(玩家数×4, 18) |

### 7.2 GameLogger.gd（信息记录）

**职责**: 统一游戏日志的写入、缓存与获取。规则层只调 `add_log`，UI 层通过 `flush_logs` 消费。

### 7.3 AIPlayer.gd（AI 决策）

**职责**: AI 自动出牌策略（族炸/化合物/双原子分子/单质/跳过），与 UI 解耦。

```gdscript
AIPlayer.auto_play(game_manager, ui_refresh)
  ├─ 第0关：仅出基础牌，AI 不抽牌
  ├─ 族炸链：冷却→跳过 / 否则出更大族炸
  └─ 常规：族炸→化合物 O(n²)（`halogen_exchange_allowed` 关闭时跳过纯卤素对）→双原子→单质→pass
```

> 化合物化合价**不再由 AI 自算**（旧实现「正价取 max / 负价取 min」已删），统一调用
> `CompoundSolver.get_valence_pairs()` —— 与提示按钮同一个取价出口；人类面板仍列
> `common_valence` 全价，但三条路径最终都由 `play_cards()` 的 `_assign_valences` 裁决，
> 因此 AI 不会提出引擎拒绝的假化合物（NCl / BrN / IN）。

### 7.4 TutorialController.gd（教程控制）

**职责**: 教程关卡状态机、预设手牌、引导文本生成、进度检查（从 GameManager 解耦）。

| 模块 | 说明 |
|------|------|
| init_tutorial | 关卡1/2预设手牌、第0关牌库与AI手牌 |
| check_tutorial_progress | 出牌后进度判定与步骤推进 |
| _update_tutorial_guidance | 关卡1/2引导文本 |
| _update_tutorial_level0_guidance | 第0关引导文本 |

### 7.5 TutorialUI.gd（教程内容）

**职责**: 静态教程文本（引导文本/成功提示/进度判定），无状态。

---


---

## 8. 表现层 - GameUI.gd

**职责**: 页面管理、牌面渲染、步骤流、着色、教程显示。AI 策略已拆至 AIPlayer.gd。

### 页面管理

| 页面节点 | 说明 |
|----------|------|
| StartPage | 开始页（P6：**全部子节点代码生成** + 渐变带/水印/装饰牌/错峰淡入） |
| TutorialPage | 教学引导页（P8：**全部子节点代码生成** —— 标题块 + 3 张 720×104 关卡卡 + 返回，整卡即按钮） |
| HelpPage | 帮助中心（P5：单页 + 3 Tab + 滚动 + 卡片，**全部代码生成**） |
| ~~HelpPage_Rules / _Cards / _Supp~~ | P6 已从 Main.tscn 整段删除（P5 的文案校对备份完成使命） |
| GamePage | 游戏主界面（牌面+操作） |
| EndPage | 结束页（P8：**全部子节点代码生成** —— 结算卡 + 顶部状态条 + 3 统计块 + 按钮组） |

**页面淡入**（P3）：根节点下有一个常驻同色底 `PageBackdrop`（`#E6F0FA`、`z_index = -100`、首个子节点、
`MOUSE_FILTER_IGNORE`），由 `_ensure_page_backdrop()` 在 `_ready` 里幂等创建（必须早于任何淡入）。
跨页切换调用 `_fade_in_page(page)`：先把**其余页**的 `modulate.a` 复位为 1，再把目标页
`modulate.a` 从 0 补间到 1（220ms `TRANS_QUAD / EASE_OUT`，全局单例 `_page_fade_tween`，重复调用先 `kill()`）。

| 约束 | 原因 |
|---|---|
| `visible` 仍**同步**设置，不延迟隐藏旧页 | 真正的交叉淡化必须延迟隐藏旧页，而 `_on_help_back()` 会**同步**读 `*.visible` 判断返回到哪一页，延迟隐藏会引入竞态 |
| 常驻同色底必须在根节点、且先于所有页面绘制 | 淡入瞬间 alpha=0，露出的必须是同色背景，否则会闪出窗口清屏色（深灰） |
| 帮助页内部 tab（规则 / 图鉴 / 补充）不淡入 | 同层即时切换更自然，每次点标签闪一下反而劣化。P5 后这条由「切 Tab 只改 Scroll `visible`」结构性保证（`_set_help_tab` 不碰 `_fade_in_page`），`verify_motion` / `verify_help_page` 各有一条断言锁死 |

### 结束页 / 教学引导页（P8：与开始页同一套画风）

**动机**：结束页是 4 个 Label + 1 个默认灰按钮、教学页是 11 个散落的 Label/Button，与 P6 重做后的开始页
（渐变带 + 水印 + 装饰牌 + 白卡）完全脱节。

| 复用零件 | 作用 |
|---|---|
| `_page_backdrop(page, bg_name, marks, cards)` | 同色底 + 45° 渐变带 + 元素水印 + 倾斜装饰牌，两页一行接入 |
| `_page_primary_btn` / `_page_secondary_btn` / `_page_ghost_btn` | 按钮三件套（蓝底 / 白底蓝边 / 透明），开始页的 `_start_make_*` 已是其薄壳 |
| `_animate_page_intro(page, order)` / `_page_deco_float(page)` | 子节点错峰淡入 + 装饰牌浮动（不碰页面级 `modulate`） |

**结束页**：`EndCard` 640×420 @ (256,114)，结构 = 顶部 6px 状态条 + 标题 + 描述 + 分隔线 +
3 个统计块（总回合 / 剩余牌库 / 剩余手牌）+ 按钮组（返回主页或返回关卡 / 再来一局或再试一次 / 教学引导）。

| 状态 | 判定 | 状态条 | 标题 |
|---|---|---|---|
| 玩家获胜 | `winner_index` 指向非 AI | `START_C_ACCENT` 主题蓝 | 胜利！ |
| AI 获胜 | `winner_index` 指向 AI | `START_C_SUB` 深灰 | 本局结束 |
| 中途退出 | 自定义文案「游戏已退出」 | `END_C_NEUTRAL` 中性灰 | 游戏已退出 |
| 初始化失败 | 其它自定义文案 | `END_C_WARN` 警示红 | 透传文案 |

**教学引导页**：标题块（40 / 16 / 72×4 强调条）+ 3 张 720×104 关卡卡 + 返回。
关卡卡整卡就是一个 `Button`（`Tutorial0Btn/1Btn/2Btn` 名字不变，`_setup_pages` 的 `pressed.connect` 零改动），
hover 只改描边 / 阴影 / 「开始 →」颜色 —— 720 宽做 1.05 缩放会顶到装饰牌。

| 约束 | 原因 |
|---|---|
| 骨架只在 `_build_end_page()` / `_build_tutorial_page()` 建一次，`_fill_end_page()` 只填数据 | `_show_end_page()` 被 `_refresh_ui()` 反复调用，重建会丢焦点并抖动 |
| 页面级 `modulate` 归 `_fade_in_page` 独占 | `verify_motion` 锁死页面淡入语义；入场动画只动子节点 |
| `_animate_page_intro` 的目标 y 记在节点 meta `intro_base_y` | 反复进入时若拿「当前 position」当目标，上次动画没播完会累积 +14 偏移 |
| `_show_end_page()` 无条件收起 `TutorialPage` | `TutorialPage` 在 `Main.tscn` 里排在 `EndPage` 之后，漏关会整块盖住结算卡 |

### 帮助中心（P5：单页 + 3 Tab + 滚动 + 卡片）

**动机**：原 3 个独立帮助页（`Main.tscn:404-616`）用 4 栏横排 + 11/12px 字号 + 空格对齐，
新手读不动；且按钮坐标三页各不相同（返回按钮位置逐页漂移）。

**结构**（`_build_help_page()` 一次性生成，`Main.tscn` 零改动）：

```
HelpPage (Control, full rect, visible=false)
├ HelpBg        ColorRect #E6F0FA（与 PAGE_BG_COLOR 同色）
├ HelpHeader    ColorRect #2C3E50, h=56
│  ├ Label "帮助中心" 20px 白字
│  └ HelpBackBtn  _mkb("← 返回游戏") 132×36，锚右
├ HelpTabBar    ColorRect 白色, y=56, h=48 + 底部 1px 分隔线
│  └ HelpTabRow HBox ×3 HelpTab{0,1,2}（180×40，选中=白底 3px 蓝下划线 + 蓝字 17px）
└ HelpScroll{0,1,2}  ScrollContainer y=116, 左右 24, 底 16（横向滚动禁用）
   └ HelpBody{0,1,2}  VBoxContainer（separation 16）
```

**设计约束**：

| 约束 | 原因 |
|---|---|
| 每个 Tab 一个独立 `ScrollContainer` | 切换只改 `visible`，三个 Tab 各自保留滚动位置，不会互相顶到顶部 |
| 懒加载（`_help_filled`） | 开局不建 20+ 卡片；`_on_show_help()` / `_open_help_at_tab()` 首次进入才调 `_fill_help_tab()` |
| `_set_help_tab()` 不调 `_fade_in_page()` | `verify_motion.gd:101` 断言切 Tab 不新建淡入补间 |
| 方法名 `_on_help_show_cards/supp/rules` 保持不变 | `verify_motion.gd:99` 直接调用；内部改为 `_open_help_at_tab(1/2/0)` |
| 卡片高度按内容自适应，行内两列由 `GridContainer` 拉平 | 不做固定高度，避免中文长句被裁 |
| 图鉴 29 张迷你卡用 `GridContainer(columns=7)` | 1152 宽下每列约 148px，5 行；`size_flags_horizontal = EXPAND_FILL` 让卡宽随列宽自适应 |

**文案与数据**：全部在 `scripts/HelpContent.gd`（`extends RefCounted`，纯静态数据，零 UI 依赖，
与 `TutorialUI.gd` 同风格），行格式 `{"k", "t"}`：

| k | 渲染 | 字色 / 字号 |
|---|---|---|
| `sub` | 卡内小标题 | `#2C3E50` / 15px |
| `p` | 正文 | `#2B3340` / 14px |
| `li` | 条目（自动加「· 」） | `#2B3340` / 14px，缩进 4 |
| `ex` | 示例 / 化学式 | `#6B7280` / 13px，缩进 14 |
| `warn` | 警示（自动加「⚠ 」） | `#C0392B` / 14px，缩进 4 |
| `gap` | 8px 空白 | — |
| `demo` | 一行迷你卡（图鉴「看三张典型牌」） | 96×124 |

`get_element_cards()` / `get_total_cards()` / `get_element_copies(sym)` 从 `CardDatabase.get_element_data()`
派生，**牌库数字只有一个来源**：29 种 / 182 张（卤族 ×10、H·O·S ×8、主族 ×6、副族 ×4）。
旧文案里的「28 种 / 172 张」已修正，`verify_help_page` 断言文案中不再出现这两个数字。

**图鉴符号色**：`_help_symbol_color(card)` 在原 `_get_card_color()` 之上做一次兜底 ——
亮度 > 0.90（稀有气体的 `(0.95,0.95,0.95)`）统一 `darkened(0.5)`，
否则白底卡面上的 He / Ne / Ar 几乎不可见。


### 提示按钮（P6：自动选最优组合 + 解释）

`HintButton` 是 `toggle_mode` 按钮，但点下去**不再只是显示一句话**，而是直接把一组「现在就能打出去」的牌选好：

```
点击 → HintAdvisor.suggest(game_manager)
	 → {indices, pattern, valence, organic, label, text}
	 → selected_indices = indices
	 → 化合物：compound_selections = valence，step_mode = 2（面板直接是「确认打出」）
	   其余：step_mode = 1（面板是「作为单质 / 合成化合物 / 族炸 / 顺序打出」）
	 → _hint_text 写进 CardInfoLabel
```

| 模块 | 职责 |
|---|---|
| `scripts/HintAdvisor.gd`（全 `static`，**只读**） | `suggest()` / `is_playable()` / `compound_valence_for()`；候选覆盖单质、双原子、族炸、顺序、有机物、2/3 元素化合物（卤族互化关闭时不生成纯卤素化合物候选） |
| `GameUI._apply_hint()` | 把建议落到 `selected_indices` / `compound_selections` / `step_mode`，并 `_update_hand_buttons()` |
| `GameUI._clear_hint()` | 清空 `_hint_text` 并 `hint_button.set_pressed_no_signal(false)` |
| `_update_card_info_label()` | `_hint_text` 非空时优先显示；`_hint_owner` / `_hint_hand_size` 变化即作废回默认「可用牌型」 |

**铁律**：`HintAdvisor._check()` 必须与 `GameManager.play_cards()` 的校验逐条一致，否则玩家照着提示点会得到
「非法出牌」。最容易漏的两条是 **桌面是化合物时，有机物也会被判 `-4`（牌型不匹配）**，
以及 **`pattern == COMPOUND` 且开关关闭时纯卤素组合返回 `-7`（卤族互化）**，提示必须跟着过滤。
`tests/verify_hint.gd` 对每条建议都用「全新 GameManager + 同样参数」再跑一次
`play_cards` 做交叉验证（返回必须 ≥ 0）；`tests/verify_halogen.gd` 专门锁死 F+Cl 只能建议族炸。

作废时机：`_on_card_clicked`（玩家自己动牌）、`_on_back`、`_step_reset`（出牌后/新一局）、
以及局面变化（换人 / 手牌数变化）。返回时 `selected_indices` 仍保留（原行为，方便换牌型重出）。


### 手牌渲染

`_build_card_button()` — 95×118px 白底圆角牌面（字号层级：符号 28 / 中文名 14 / 化合价 13 / 族 11 / 序数 12 / 质量 9）：
- 左上：原子序数 | 右上：族 | 中上：元素符号(着色) | 中：中文名 | 中下：化合价(±标注) | 左下：相对原子质量
- **字号要在 `_apply_card_compact()` 里再写一遍**：只改 `_build_card_button()` 会在下次重排时被覆盖；
  紧凑牌面用 符号 21 / 中文名 12（左对齐，保证露出的窄条可读）
- **化合价文本必须按可用宽度收缩**：`card.common_valence` 最多 5 个价（Cl = `-1 +1 +3 +5 +7`），
  实测 13px 下 85px（正好等于整张卡宽）、触屏 15px 达 98px、紧凑档 label 只有 44 宽 ——
  而 `Label` 默认**不裁剪**，文字会直接画到卡片右边界之外（多价元素卡面溢出）。
  `_fit_card_valence()` 分级收缩：**全价 → 去空格 → 逐档降字号（下限 `CARD_VAL_MIN_FS = 10`）
  → 只留两端价 + 「…」**，末档 `clip_text = true` 兜底；实测文本宽写进 `meta("fit_w")`，
  圆底价态 chip 与测试直接复用，不再各量一遍。帮助页图鉴（迷你卡 96 宽）走同一套
  `_format_valence_brief()`，不再各维护一份裁剪规则。
- `Label.size` 会被字体最小高度撑大，但字形仍自顶部绘制 —— 判断是否压字要按**字号**算，不要按 `size` 算

布局 `_layout_hand_cards()`：一行居中；张数超过"不重叠容量"后按
`step = min(CARD_STEP_MAX=60, (可用宽 - 牌宽) / (n-1))` 压缩重叠，
重叠露出不足 72% 时切换紧凑牌面（内容左对齐，保证左侧窄条可读）。

### 手牌重排（拖拽 + 按序按钮）

玩家可以拖动任意一张手牌换位置。**顺序的唯一真源是 `PlayerInfo.hand` 数组**，
界面每次重建都照抄数组顺序，不存在第二套「显示顺序」。

| 环节 | 实现 | 关键点 |
|------|------|--------|
| 起手判定 | `_process → _update_hand_drag()` 轮询。桌面单档：位移 `DRAG_THRESHOLD = 6px` 即拖拽。触屏**两档**：`TOUCH_DRAG_ARM_MOVE = 10px` 起拖跟手、`TOUCH_DRAG_THRESHOLD = 24px` 才算确认重排（松手位移 <24px 回退成点选） | 不接 `gui_input`：`accept_event()` 只挡得住「传给别的控件」的事件，挡不住同一个 Button 自己补发的 `pressed`，拖完会顺带把牌选中 |
| 拖拽视觉 | 原位牌 `modulate.a = 0.28`；半透明幽灵牌（`duplicate()`，`mouse_filter = IGNORE`）+ 3px 主题蓝插入线，均挂 `hand_container`，`z = Z_DRAG(30)`。触屏软启动用 0.55 / 0.9（差一档就回退成点选，一步淡到底会闪） | 与 A1 幽灵牌动画同一约定：独立节点、不改容器布局时序；重建前 `_cancel_drag()` 一律回收 |
| 落点 | 鼠标 x 落在某张牌中点左侧 → 插入该牌之前；全在右侧 → 末尾（`_insert_slot_at` / `_slot_x`，用 `base_pos` 静止坐标） | 用静止坐标而不是当前 `position`，否则落下补间未走完时指示线会漂 |
| 落库 | `PlayerInfo.move_card(from, to)` = `remove_at` + `insert`，成功即 `hand_manual_order = true`；`to = slot - 1 if slot > from` | 越界 / 原地不动返回 false → 不重绘；松手在容器外（`in_zone == false`）丢弃本次拖拽 |
| 自动排序失效 | `sort_hand_by_atomic_number()` 在 `hand_manual_order` 为 true 时直接返回 | `GameManager`（抽牌后）与 `TutorialController` 的既有调用点无需改动，自动全部跳过 |
| 恢复按序 | 手牌区下方「按序 ⇅」按钮（`_reorder_btn`，仅手动模式可见）→ `sort_hand_by_atomic_number(true)` | `force=true` 是唯一能打断手动顺序的入口，排完标志复位回自动模式 |
| 禁用场景 | `_can_reorder_hand()`：教程关（`tutorial_level > 0` 或 `tutorial_level0_phase > 0`，含第零关练习阶段）/ `step_mode` 非 0、3 / 非玩家回合 / 页面不可见 | 教程引导高亮框按固定坐标绘制，拖牌会让提示错位 |

**坑：`selected_indices` 是索引，顺序一变就全部失效。**
选中的牌必须按「卡片对象」跟踪，而对象只能从**上一帧按钮的 `card` meta** 拿到
（数据层数组此刻可能已被 `move_card` / 抽牌后的排序改过，旧索引取 `hand[i]` 会取到别的牌）：

```
_build_card_button()      → btn.set_meta("card", card)
_update_hand_buttons()    → ① _selected_cards(cp)：遍历 selected_indices，用 hand_buttons[i].get_meta("card")
							取对象（必须抢在 hand_buttons.clear() 之前！）
						  ② sort_hand_by_atomic_number()
						  ③ _remap_selection(cp, cards)：cp.hand.find(card) 重新算出索引
```

提示文本同理：`_hint_owner` + `_hint_hand_size` 之外再加 `_hint_order_sig`（顺序签名），
玩家重排后提示立即作废，避免「提示的牌」和「高亮的牌」对不上。
回归测试：`tests/verify_hand_reorder.gd`（48 项，其中「自动排列回归锁」保证默认行为不变）。

**触屏为什么要两档**：旧实现「长按 300ms + 位移 24px」才起拖，真机上是
「按住后牌一动不动（最多 300ms 无反馈）→ 松手时若没走满 24px，那次 `pressed` 又被
`_drag_suppress_click` 吞掉」= 点了没反应。现在把判定拆成两段：10px 立即起拖跟手
（`_update_hand_drag`），松手时用**本次按下的累计最大位移** `_drag_max_move` 判断 ——
≥24px 才落库重排，<24px 走 `_apply_card_selection()` 回退成点选（与 Button 的
`_on_card_clicked` 共用同一条选中路径）。起拖门槛（10）< 回退门槛（24）是必须保持的不等式，
`verify_touch_ui` 直接断言 `_drag_arm_threshold() < _drag_threshold()`。

### 悬停交互（防抖动状态机）

悬停效果 = 上浮 20px + 置顶 + 高亮边框 + 下方信息栏显示详情。关键约束：

| 机制 | 实现 | 为什么必须这样 |
|------|------|----------------|
| 判定几何固定 | `_card_hover_rect()` = 静止位置 ∪ 抬起位置 `{base-(0,20), 115×138}`，只用 `base_pos` 算 | 若命中区随"抬起"变化，会出现 抬起→让出底部20px→移出→落回→再进入 的自激抖动 |
| 不用引擎信号 | 不连 `mouse_entered/mouse_exited`，改由 `_process → _update_hand_hover()` 轮询 | 引擎 pick 结果会随 `position`/`z_index` 变化翻转 |
| 重叠归属 | 命中重叠时取索引最大（最上层）；但鼠标仍在当前牌"核心区"`_card_core_rect()` 内则保持 | 重叠窄条处两张牌互相抢 hover，表现为抽搐 |
| 抬起牌优先 | 已抬起的牌以 `z=20` 压住相邻牌，`_card_raised_rect()`（= 静止位置上方 20px 的绘制矩形）命中时直接保持，不再走静态规则 | 否则指针明明在抬起牌画出来的区域里，静态规则却判给被压住的后一张 → 沿顶栏滑过时逐张乱跳 |
| 分级切换延迟 | 命中某张牌 `HOVER_SWITCH_DELAY_MS = 60ms`；仍在容器内但不在任何牌上（牌列下方）`HOVER_LEAVE_DELAY_MS = 140ms` | 60ms 跟手；140ms 让底边轻微抖动不落牌。旧的固定 110ms 对核心区也生效，显得迟钝 |
| 顶边容错 | `_hover_keep_above()`：抬起牌顶边与容器顶边重合，越界 14px（`HOVER_EXIT_GRACE`）内仍算在牌上 | 贴边滑过时不再「越界 1px 就落牌、回来再等延迟」 |
| 升降动画 | `_tween_card_y()`：`HOVER_ANIM_MS = 80ms`、`TRANS_CUBIC/EASE_OUT`；`z_index` 仍立即切换；每张牌只保留一个 tween，`_layout_hand_cards()` 重排前先 kill | 位置瞬移是「生硬」的主因；重排不 kill 会把牌拉回旧坐标 |
| 缩放（A2） | `_tween_card_scale()`：悬停 `HAND_HOVER_SCALE = 1.06` / 选中 `HAND_SELECT_SCALE = 1.04` / 常态 1.0，`HAND_SCALE_MS = 120ms`；pivot 在 `_layout_hand_cards()` 里居中 | 只抬 20px 在整排里仍不够跳；而 `scale` **不参与** `_card_hover_rect()` 命中计算，所以放大不会引发自激遮挡抖动（与按钮 `_attach_btn_motion` 同一套思路） |
| 样式同源 | `_apply_hover()` 同时改 `position / z_index / scale` 与 **normal / hover / pressed 三个主题项**（三者指向同一 StyleBox） | 引擎 `hover` 态是第二套判定；未覆盖时会回退到默认深色主题（`bg=(0.225,0.225,0.225,0.6)`）——鼠标一停到牌上，整张牌就被盖成半透明深灰 |

- 状态字段：`_hover_idx`（当前抬起）/ `_hover_pending_idx`（待稳定目标）/ `_hover_pending_at`（时间戳）
- 按钮 meta：`base_pos` / `hand_idx` / `sb_normal` / `sb_hover` / `hover_tween`（位移补间）/ `scale_tween`（缩放补间）
  —— **两个 meta 键必须分开**：重排只 kill 位移补间，缩放会在下一帧自己收敛到目标档
- `_layout_hand_cards()` 里会话式地重设 `btn.scale`（悬停牌保持 1.06、选中 1.04、其余 1.0），
  否则重排会把正在悬停的牌「压扁」回 1.0，而 `_hover_idx` 没变、状态机不会重新触发
- `_update_hover_at(mp)` 是可注入鼠标位置的核心判定，自动化测试据此验证防抖；
  `_on_hand_card_hover(btn, bool)` 保留为公共入口（测试与外部直接调用）
- headless 环境（自动化测试）跳过 `_process` 轮询，避免 `(0,0)` 误触发
- 测试等待补间**不能**用固定 `create_timer`（headless 下单帧可能就超过等待时长，补间一步未走）；
  `_wait_hover_anim()` 轮询 `hover_tween.is_running()` 直到全部结束

### 卡牌状态样式（选中 / 悬停 / 焦点）

**唯一来源**：所有 `StyleBoxFlat`（手牌四态 / 桌面小卡 / 操作按钮 / toast）都由
`_make_panel_style(kind)` 产出，`_style_base()` 统一填底色、描边宽度、圆角、阴影。
调用点只允许 `duplicate()` 后改 `bg_color` / `border_color`（hover / pressed / disabled），
**禁止再手写** `border_width_*` / `corner_radius_*` / `shadow_*` —— 这三类数值一旦分散，
就会出现"同样的牌圆角 6/8 混用、有的有投影有的没有"。

| kind | 圆角 | 描边 | 阴影 | 用途 |
|---|---|---|---|---|
| `card` / `card_selected` / `card_hover` / `card_hover_selected` | 8 | 1px 中性 / 2px 橙金 / 2px 蓝 / 2px 深橙 | 3px | 手牌四态 |
| `mini_card` / `mini_card_hover` | 8 | 1px 中性 / 1px 蓝 | 无（密度高） | 桌面小卡 |
| `button` | **6** | 1px 蓝灰 + 内边距 10/6 | 3px | 操作面板 / 顺序指定弹窗 / 工具行 |
| `toast_warning` / `toast_info` | 10 | 2px 警告红 / 2px 橙 | 3px | 右栏警告 toast / 第零关提示框 |
| `log_panel` | 10 | 1px 中性 | 3px | 右下日志底板（白 62% 半透明） |
| `valence_chip` | 5 | 无 | 无 | 卡面价态圆底（极浅暖底 `#FAEDED`，宽度随实测文字宽） |

**按钮圆角单独一档（`BUTTON_RADIUS = 6`）**：按钮比卡牌小得多（32~58 高），
同为 8px 时弧长占比过大、看起来「像药丸」，视觉上反而比卡牌更圆；
6px 让「卡牌 8 / 按钮 6 / 面板 10 / chip 5」形成一档递进。
`verify_tool_buttons` 与 `verify_hand_layout` 都断言 `== BUTTON_RADIUS`，
`verify_hand_layout` 另加一条 `BUTTON_RADIUS < CARD_RADIUS` 的回归锁。

`_build_card_button()` 为每张牌生成样式并**显式覆盖 Button 的全部状态项**：

| 状态 | 未选中 | 已选中 |
|------|--------|--------|
| `normal` | 白底 `#F8F9FC` + 1px 浅灰边 + 轻投影(3px) | 浅黄 `#FFFFD1` + 2px 橙金边 |
| `hover`（抬起时） | 浅蓝 `#E6EDFA` + 2px 蓝边 | 深一档浅黄 `#FFFAB8` + 2px 深橙边 |
| `pressed` | 与 `normal` 同源 | 与 `normal` 同源 |
| `focus` | `StyleBoxEmpty`（无框） | 同左 |

- **三者必须同源**：`hover` / `pressed` 都指向当前 `normal` 的**同一个 StyleBox 对象**。引擎无论
  认为鼠标是否悬停，绘制结果都完全一致 → 判定仍只由状态机负责，视觉上也不会出现第二个闪烁源。
- **必须显式覆盖**：Godot 默认（深色）主题的 `hover` 是 `bg=(0.225,0.225,0.225,0.6)` 半透明深灰、
  `focus` 是 `bg=(1,1,1,0.75)` 白罩。漏掉任何一项，真实鼠标悬停/点击后都会糊在牌面上
  —— 这正是"选中后卡牌发黑"的根因（自动化截图直接调 `_apply_hover` 绕过了引擎 hover 态，所以没暴露）。
- **选中牌的悬停保留黄色系**（只加深、换深橙边），否则悬停的浅蓝会把"已选中"的浅黄整个盖掉，
  用户看不出哪张被选了。

### 按钮交互（`_mkb`：缩放 + 悬停发光，P3）

操作面板与弹窗按钮统一由 `_mkb(text, cb, dis)` 产出，并接上缩放补间：

| 项 | 实现 |
|---|---|
| 缩放 | 悬停 1.05、按下 0.96，90ms `TRANS_CUBIC`；`pivot_offset` 居中，由 `_attach_btn_motion()` 统一接线（先取 `size`，树外 size 为 0 时回落 `custom_minimum_size`，随后 `resized` 跟随实际 size） |
| 发光 | 悬停 StyleBox 用 `shadow_color = (0.35, 0.55, 0.85, 0.55)` + `shadow_size = 6` + `offset = 0` 模拟光晕（`StyleBoxFlat` 没有真发光，只能靠外扩阴影） |
| 单补间 | 每按钮只保留一个补间（meta `btn_scale_tween`，起新动画前先 `kill()`），与手牌 `hover_tween` 同一约束 |
| 不自激 | 缩放只向外扩，不会把指针挤出原边界 → `mouse_entered / mouse_exited` 不会反复翻转 |
| 禁用 | `disabled` 直接早退，不缩放也不发光（避免暗示可点击） |

> 手牌按钮**不走** `_mkb()`：它由 `_build_card_button()` 生成，悬停由 `_process` 轮询状态机驱动，
> 不能接 `mouse_entered / mouse_exited`（会自激，见上一节）。

### 游戏页工具按钮（提示 / 帮助 / 退出，P11）

这三颗按钮是 `GamePage` 里**唯一点名存在**的原生 `Button`（`Main.tscn` 只给了 `text`），
一直没人接管主题，于是画的是引擎默认主题（灰底 / 4px 圆角 / 无描边 / 无阴影），
与页面其余部分两套语言。P11 起由 `GameUI.gd` §八之四接管：

| 函数 | 职责 |
|---|---|
| `_style_game_tool_buttons()` | `_setup_pages()` 尾部调用：先按常量排几何（`[button, width]` 表），再逐颗上样式 |
| `_style_tool_btn(b, is_toggle, danger)` | 单颗按钮的 6 个状态项全覆盖；`is_toggle` → 开态蓝实底，`danger` → 暖红悬停/按下 |
| `_attach_btn_motion(b)` | 从 `_mkb()` 尾部抽出的公共接线（pivot 居中 + `resized` 校正 + hover/press 缩放） |

| 状态 | 取值 |
|---|---|
| `normal` | `_make_panel_style("button")`：`#2C3E50` + 1px `#668CB2` + 6 圆角（`BUTTON_RADIUS`）+ 3px 软投影 |
| `hover` | `#455F80` + 亮蓝边 + 6px 蓝光晕（与 `_mkb` 同参）；`danger` 档（退出游戏）改 `BORDER_WARN` 暖红 |
| `pressed` | `#1F2B3B`；`is_toggle` 档（显示提示）改主题蓝 `#2D7AB3` —— 这就是 **toggle 开态** |
| `hover_pressed` | `is_toggle` 档：主题蓝 `lightened(0.12)` + 8px 蓝光晕 |
| `disabled` | 同色 35% 透明 |
| `focus` | `StyleBoxEmpty`（否则点击后跳出默认白焦点环） |

几何由常量**推导**而非写死：`TOOL_BTN_TOP/H/GAP/RIGHT` + 三档宽度 →
`TOOL_ROW_LEFT`、`REORDER_BTN_LEFT`（「按序 ⇅」并进同一行）、`TOOL_ROW_HL_*`（教程高亮框）。
整行右边界 `x=820`，与 `HandContainer` / `CardInfoLabel` 的右边缘同一条竖线（`LogLabel` 从 824 起）。

> 为什么 6 个状态项都要覆盖：Godot 的 `hover` / `pressed` / `disabled` / `focus` 是**独立主题项**，
> 只改 `normal` 时真实鼠标一停上去就会掉回默认深灰主题（同一坑在 `_build_card_button()` 也踩过）。
> 另外「toggle 开着 + 悬停」走的是 `get_draw_mode() == DRAW_HOVER_PRESSED(4)`，
> 只覆盖 `pressed` 会在移入时闪一帧深蓝灰。

### 层级与浮层（Content / Overlay / Toast）

Godot 的 `CanvasItem` 排序是 **`z_index` 优先于树顺序**。`GamePage` 下的静态节点全在 z=0，
运行时新增的浮层若也留 z=0，就会被任何抬高 z 的节点穿透 —— 历史 bug：悬停手牌 z=100 /
选中手牌 z=50 直接跑到「顺序指定」弹窗与警告框之上（表现为弹窗被牌"打洞"、警告框被手牌
半遮半掩），而且弹窗遮罩的 `mouse_filter=STOP` 也拦不住它们（点得到牌）。

统一约定（`GameUI.gd` 顶部常量）：

| 层 | z_index | 承载内容 | 挂载方式 |
|---|---|---|---|
| `ContentLayer` | `Z_CONTENT = 0` | 顶部状态栏、桌面小卡、第零关规则提醒 | `_layer(0)` |
| 手牌（`HandContainer` 内） | 选中 `Z_HAND_SELECTED = 10` / 悬停 `Z_HAND_HOVER = 20` | 只在手牌内部相对置顶 | `_layout_hand_cards()` / `_apply_hover()` |
| `OverlayLayer` | `Z_SCRIM = 100` | 全屏遮罩 + 模态弹窗（第零关引导、顺序指定弹窗） | `_layer(1)` |
| `ToastLayer` | `Z_TOAST = 110` | 警告 toast / 引导提示（`_show_center_warning`、`_level0_make_tip_box`） | `_layer(2)` |

- 警告 toast 固定落在右栏上部空白格 `WARNING_TOAST_RECT = (824,62,312,116)`（见「视觉规范工厂」），
  `LogLabel` 从 y=300 起、`TutorialLabel` 从 y=186 起、`InfoLabel` 只到 x=480 → 不与任何静态节点相交。
  `_show_center_warning()` 单例复用同一个 `Panel`：连续报错只更新文本并用 `_warning_seq` 作废旧计时器，
  不会叠框也不会被上一条提前熄灭；`_init_game()` / `_on_start_tutorial()` 调 `_hide_warning_toast()` 清场。

- 三个层由 `_ensure_layers()` 幂等创建（`_setup_pages()` 内调用），都是 `GamePage` 的直接子节点、
  全屏 anchor、`mouse_filter = IGNORE`（层自身不拦截，事件仍落到子节点）。
- **新增运行时浮层必须挂进对应层**，不要直接 `game_page.add_child()`；手牌 z 只允许 0 / 10 / 20，
  且必须小于 `Z_SCRIM`，否则会重现穿透。
- 回归测试：`tests/verify_hand_layout.gd → _test_layers()` 断言层 z 序、层铺满、
  顺序弹窗落在 `OverlayLayer`、警告框落在 `ToastLayer`。

### 桌面区（小卡 + 牌型文字）

`_update_table_label()` 每次都**整块重建**桌面小卡（先 `queue_free` 旧的再 `_build_mini_card_button()`
逐张新建），因为桌面小卡的化合价 / 排序都要按化合物化学式实时重算。因此动效必须解决两个问题：

| 问题 | 处理 |
|---|---|
| AI 每次行动都会走 `_refresh_ui` → 整块重建 → 小卡每帧重播入场会一直闪 | 内容签名 `_table_sig = "牌型|符号+uid,…"`：签名不变就不播入场（`replay` 标志） |
| 小卡位置是布局真值（测试与「桌面小卡槽」断言都按 `position` 算） | 入场只动 `scale`（0.9 → 1.0）与 `modulate:a`（0 → 1），**一个像素都不动 position**；多张按 `MINI_CARD_IN_STAGGER = 40ms` 依次入场 |
| 「桌面: …」换字容易被当成误刷 | `_set_table_text()` 文本变化时从 `a=0.15` 淡入（`TABLE_REVEAL_MS = 180ms`）；文本未变不重播 |
| 玩家要读完整句才知道打了什么牌型 | `_table_type_color()` 按牌型上色：单质深灰蓝 / 化合物深绿 / 族炸深红 / 有机物琥珀 / 顺序深紫 |

- 补间 meta：小卡 `mini_in_tween`、桌面文字 `reveal_tween`（都先 kill 旧的再建新的，避免叠加）
- 回归测试：`verify_motion.gd → _test_hand_and_table_motion()` 锁死「入场不动 position」「文本未变不重播」「三种牌型色互相可区分」

### 出牌 / 弃牌 / 抽牌动效（A3）

三处都靠「幽灵牌」（`_make_fly_ghost()`）：**原按钮会被 `_refresh_ui()` 整块重建
（`remove_child` + `queue_free`）**，任何「移动原按钮」的写法都会在半路凭空消失。
幽灵牌是 `duplicate()` 出来的副本，挂在 `ContentLayer`（不随 `hand_container` 重建销毁），
坐标统一用 `global_position`，跨容器也一致。

| 场景 | 实现 | 关键点 |
|---|---|---|
| 出牌 | `_capture_play_fly_in()` 抢在 `_step_reset()` / `_refresh_ui()` 之前拍下被选中手牌的幽灵牌（并把原位 `visible = false`）；`_replay_play_fly_in()` 在刷新后让它们飞向桌面小卡 | 与小卡**按卡片对象配对**（化合物的小卡会按化学式重排，下标对不上）；终点 `PLAY_FLY_SCALE = 0.76`（95×118 → 72×90）；末 40% 才淡出，前段看清是哪张 |
| 弃牌 | `_fly_discarded_card()`：向上抬 `DISCARD_FLY_LIFT = 46px` 后淡出 | 同样抢在 `player_discard_and_pass()` / 重建之前；弃牌是「牌离开手牌」，没有落点，所以只做抬起 |
| 抽牌 / 发牌 | `_animate_new_hand_cards()`：按卡片对象比对 `_hand_seen_cards`，只对新出现的牌做 `modulate:a` 0→1 淡入 | 开局 8 张全部「新出现」→ 自带一次发牌入场；**只动 alpha**，`scale` 归悬停 / 选中缩放补间管（两边同时改会互相拉扯） |

- 补间 meta：幽灵牌 `fly_tween`、新牌 `deal_in_tween`；幽灵牌播完 `queue_free()` 自清理
- 已知缺口：**弃牌 → 牌库堆的飞行**没做（牌库没有可视节点，只有一个文字计数）；
  AI 出牌走 `AIPlayer.auto_play(gm, _refresh_ui)`，不经过 `_handle_result()`，
  所以 AI 出牌只有桌面小卡入场，没有手牌飞入
- 回归测试：`verify_motion.gd → _test_play_and_discard_motion()`（发牌淡入 / 同批不重播 /
  幽灵牌挂 ContentLayer + `mouse_filter=IGNORE` + `z=Z_DRAG` / 播完自释放 / 弃牌向上抬起）

### 教程引导文本布局

`TutorialLabel` 显示 `TutorialController.get_tutorial_display()`，即
`引导文本 + "\n" + 成功提示`，最长折成 **4 行**（14px 字号 + `line_spacing=6` → 98px 高）。
它必须同时避开三块动态内容：

| 节点 | rect（视口 1152×648） | 说明 |
|---|---|---|
| `TutorialLabel` | (620, 186) 505×98 | 桌面小卡槽右侧 |
| 桌面小卡槽 | (20, 186) 580×90 | `_update_table_label()` 动态生成 72×90 小卡 |
| `LogLabel` | (824, 300) 312×300 | 右下日志 |

- **历史 bug**：原位置 `(225,185) 900×40` 与桌面小卡槽 `(20,186) 580×90` 完全叠在一起
  —— 桌面一开始出牌，小卡就压掉引导文本第一行（表现为文字被"打洞"）；40px 高度也只
  容得下 2 行，「引导 2 行 + ✓ 成功提示 1 行」必然溢出。日志区当时在 `(824,100)`，
  也与教程文本右半边重叠。
- **约束**：教程文本改动位置时必须复算「桌面小卡槽（小卡最多 8 张，横向 20..600）」
  与「日志区」，且高度 ≥ 96px。
- 回归测试：`verify_hand_layout.gd → _test_tutorial_layout()` 断言教程文本与桌面小卡槽 /
  日志区 / InfoLabel / HandLabel / HandContainer / CardInfoLabel 均不相交，宽高足够 4 行。

### 动态 Label 的 autowrap 顺序（踩过两次）

`Label.size` 会被 `get_combined_minimum_size()` 抬到「不换行时整行宽」。所以
**必须先把 `autowrap_mode` 打开，再设 `text` / `size`**：

```gdscript
lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 先
lbl.text = desc
lbl.size = Vector2(w, h)                             # 后
```

反过来写（`size` 在前）时，`size` 会被 clamp 到那一步的最小宽度（中文长句 ≈ 640px），
之后即使再打开 autowrap 也不会缩回去 —— 文字直接画到黄色提示框外面（触屏实机截图 bug）。
第零关的 `tip_desc` / `tip_title` / 流程介绍 `content` / `_level0_make_tip_box` 的 `lbl`
四处已按此顺序修好，并由 `tests/verify_tutorial_layout.gd` 断言宽度恰好等于设定值（472 / 840 / 660）。

### 第零关「规则提醒」槽位（方案 B：与日志同格互斥）

| 节点 | rect | 说明 |
|---|---|---|
| `LogPanel` | (814, 290) 332×320 | 常态：日志底板（`log_panel` 样式，白 62% + 圆角 10 + 中性描边） |
| `LogLabel` | (824, 300) 312×300 | 常态：右下日志 |
| `Level0RuleTipsBg` | (824, 300) 312×300 | 第零关练习阶段：浅黄面板（`toast_info` 样式） |
| `Level0RuleTips` | (838, 312) 284×276 | 同上，内缩 14/12 的行文区 |

- **互斥可见**：`_level0_set_rule_tips_visible(on)` 一处控制 —— 练习阶段日志
  （文字 + 底板）让位，其余局面提醒隐藏 + 日志复位 ⇒ 结构上不可能再出现
  「日志数字」与「规则提醒」叠字
- 日志显隐的唯一出口是 `_set_log_visible(on)`：同时切 `LogLabel` 与 `LogPanel`，
  任何新代码都不许直接写 `log_label.visible = ...`（否则会留下「底板还在、字没了」的鬼影）
- `LogPanel` 由 `_ensure_log_panel()` 惰性创建并**插到 `LogLabel` 之前**：
  同级节点按树顺序绘制，底板必须先画；几何由 `LogLabel.position/size` 外扩
  `LOG_PANEL_PAD = 10` 推导，以后调日志区位置时底板自动跟上
- 历史 bug：规则提醒硬编码 `(950,370) 220×220`，右边界 1170 > 画布 1152，且整块躺在
  `LogLabel` (824..1136 × 300..600) 里 —— 既被屏幕裁掉又和日志叠字
- 生命周期：`_level0_clear_rule_tips()` 在 `_init_game()` / `_on_start_tutorial()` /
  `_show_start_page()` 调用（提醒挂在 `ContentLayer`，不随 `GamePage` 隐藏或 `GameManager` 重建而消失）

### 出牌步骤流

```
step0: 选牌 → "出牌(选牌型)" + "跳过/弃牌跳过"
step1: 族炸链中: "作为族炸打出" + "返回"
	   否则: "作为单质" + "合成化合物" + "作为族炸" + "返回"
step2: 化合价选择 → "确认打出"
step3: 上限弃牌 → "确认弃置" + "取消"
```

### 元素着色

优先级：精确符号 > 族匹配(VIIA) > 类型匹配(金属/非金属/准金属/稀有气体)

### AI 策略（已拆至 AIPlayer.gd）

```
AIPlayer.auto_play(game_manager, ui_refresh):
  族炸链中 → 冷却跳过 / 出族炸
  否则 → _try_play():
	├─ 接顺序（仅桌面是顺序时出顺序，不主动出）
	├─ 族炸尝试（同族≥2张）
	├─ 化合物配对 O(n²)（`halogen_exchange_allowed` 关闭时跳过纯卤素对；化合价优先取公式配平结果，
	│   失败时遍历常见价找一正一负兜底 → 卤族互化打开后可出 ClF）
	├─ 双原子分子配对
	├─ 单质单张
	└─ 全部失败 → player_pass()（达上限时自动弃1张）
```

---

## 9. 场景结构 - Main.tscn

```
Main (Control) ← GameUI.gd
├── StartPage          ← 空容器；子节点全部由 _build_start_page() 生成（P6）
├── TutorialPage       ← 空容器；子节点全部由 _build_tutorial_page() 生成（P8）
├── GamePage           ← 游戏主界面
│   ├── GameBackground ← Color(0.78,0.88,0.98)
│   ├── TitleLabel / InfoLabel / TableLabel / DeckCountLabel
│   ├── HandLabel / HandContainer (Control，手动重叠布局)
│   ├── ActionPanel (HBox) / CardInfoLabel / TutorialLabel
│   └── HintButton / HelpBtn / QuitButton   ← 工具行：样式 + 几何由 _style_game_tool_buttons() 接管（§8）
└── EndPage            ← 空容器；子节点全部由 _build_end_page() 生成（P8）
```

> P6 后 `Main.tscn` 只剩 373 行：`StartPage` 是空容器，`HelpPage` 由 `_build_help_page()` 生成，
> 旧 `HelpPage_Rules / _Cards / _Supp`（589 行）已删除。开始页生成的节点名与旧场景逐一对应
> （`StartButton` / `PlayerCountSpin` / `AiCountSpin` / `OrganicCheckBox` / `SequenceCheckBox` /
> `TutorialBtn` / `ExitButton` / `SupplementaryHelpBtn`）。
>
> ⚠ **节点名一致 ≠ 路径一致**：人数框 / AI 框嵌在 `SettingsCard` 卡片内，只有 `StartButton` /
> `TutorialBtn` / `ExitButton` 直接挂在 `StartPage` 下；P10 起 4 条补充规则开关（含 `ElementLimitCheckBox`）
> 和 9 个 `ElementChip_*` 又移进了 `SuppRulesPage` 小页（`SettingsCard` 只剩「补充规则」入口
> `SupplementaryHelpBtn` + 摘要 `SuppRulesSummary`）。取这些控件必须走 `_start_child(name)`
> （内部 `find_child(name, true, false)` 递归查找）；用 `start_page.get_node_or_null(...)` 会拿到
> `null` 并**静默失效**（踩过的坑：AI 人数永远 3、AI 上限锁死 7、补充规则开关永远关、点入口没反应）。
>
> 人数约束：`1 ≤ AI ≤ 总人数 - 1`（至少 1 个对手、至少留 1 个座位给人类；AI=0 时其余座位
> 是没人操作的人类，开局即卡死）。`_on_player_count_changed()` 在总人数变化时同步压
> `ai_spin.max_value` 并在越界时用 `StartRuleHint` 告知；`_on_start_game()` 再对上下限各 clamp
> 一次，防御脚本 / 键盘输入绕过 UI 的路径。

---

## 10. 数据流

```
Start Page → 选择模式（自由/第一关/第二关）
  ↓
GameManager.init_game / init_tutorial
  ├── 182张牌洗牌 / 预设手牌
  └── phase=1

回合循环:
  _refresh_ui() → 状态/桌面/手牌/牌库计数/教程
  人类: 选牌→选牌型→卤族互化→化合价→play_cards
  AI: 1.5s延迟→AIPlayer.auto_play→play_cards
  pass: 上限→弃牌模式 / 正常→抽1张→next_turn
  族炸: clan_bomb_chain_active→next_turn→_intercept_next
  溢出: compound_immune→免疫族炸
  手牌=0 → GAME_OVER
```

---

## 11. 关键算法

| 算法 | 位置 | 复杂度 |
|------|------|--------|
| detect_pattern | CardPatterns.gd | O(n) |
| _is_clan_bomb | CardPatterns.gd | O(n) |
| get_compound_formula | CompoundSolver.gd（配平 + 化学式；空式子 / `ratio_ok=false` 即打不出）| O(n) |
| `_assign_valences` | CompoundSolver.gd（唯一价态分配入口：默认配平 + 电负性有序校验）| O(n) |
| `_search_valences` | CompoundSolver.gd（默认配平失败时的价态搜索：2~3 种元素 DFS、按实际张数电荷平衡；>3 种元素不做搜索）| O(价域^元素种数) |
| compare_cards | CardPatterns.gd | O(n) |
| generate_deck | CardDatabase.gd | O(28×copies) |
| shuffle | CardDatabase.gd | O(n) Fisher-Yates |
| _try_play (AI) | AIPlayer.gd | O(n²) 化合物配对 |
| _intercept_next | GameManager.gd | O(n) 顺时针查找 |

---

## 12. 触屏档案（A1 / B / C）

> 目标：桌面（1152×648 鼠标）与 Android 手机（touch）共用同一份场景与脚本，
> **不新增第二套 UI、不复制场景**。

### 12.1 铁律：`const` 是桌面基准，放大只走运行时取值函数

`GameUI.gd` 里所有几何 `const`（`TOOL_BTN_H=32` / `TOOL_BTN_TOP=558` / `DRAG_THRESHOLD=6` …）
都被 `tests/verify_*.gd` 逐值断言。手机适配因此分两层：

| 层 | 谁读 | 桌面 | 触屏 |
|----|------|------|------|
| `const TOOL_BTN_H` 等 | 测试 / 默认值 | 32 | 32（永不改） |
| `_tool_btn_h()` 等取值函数 | 运行期调用点 | 32 | 48 |

```gdscript
var _touch_ui: bool = false            # _ready(): _touch_ui = OS.has_feature("mobile")

func _tool_btn_h() -> float:           # 桌面回常量，触屏回放大值
	return float(TOUCH_TOOL_BTN_H) if _touch_ui else float(TOOL_BTN_H)
```

桌面路径**逐像素不变**，23 套老测试零改动；触屏路径由 `tests/verify_touch_ui.gd`（53 断言）覆盖。
`headless` 下 `OS.has_feature("mobile")` 为 false，所以自动化测试永远走桌面层。

### 12.2 A1 屏幕适配（`project.godot`）

| 项 | 值 | 原因 |
|----|----|------|
| `display/window/stretch/aspect` | `keep` | `expand` 只在画布比例变大时才扩展，手机横屏（20:9 ≈ 2.22）比设计画布（16:9 ≈ 1.78）**更宽** → 右边留一条空白，UI 全挤在左半边 |
| `rendering/environment/defaults/default_clear_color` | `#E6F0FA` | `keep` 留出的边框色，与页面底色（`PAGE_BG_COLOR`）同值 → 看不出「黑框」 |
| `renderer/rendering_method.mobile` | `gl_compatibility` | 老机型兼容，避免 Vulkan 崩溃 |

### 12.3 B 触控尺寸

| 项 | 桌面 | 触屏 | 备注 |
|----|------|------|------|
| 工具行（提示 / 帮助 / 退出） | 32 高，gap 10，top 558 | **48 / 20 / 542** | 右界固定 820，左界 460 → 440；48 高仍夹在信息栏(底 526)与出牌区(顶 599)之间 |
| 「按序 ⇅」 | 与工具行同行，左界 338 | 左界 308 | 跟着工具行左移 |
| 出牌区按钮 `_mkb` | 45 高 / 字号 16 | **58 / 18** | 58 ≈ 39dp |
| 卡牌字号（序/族/符号/名/价/质量） | 12 / 11 / 28 / 14 / 13 / 9 | **+2 / +2 / +4 / +3 / +2 / +3** | 统一走 `_touch_fs(base, bonus)` |
| 开始页 / 帮助页 / 结算页 / 教学页按钮 | 各调用点手写 | 高度补到 ≥48，字号 +2 | `_apply_touch_sizing()` 构建后统一兜底 |

两个容易踩的坑：

1. **`_apply_touch_sizing()` 必须幂等**：开始页与「补充规则」小页是父子关系，递归会扫两次，
   用 `set_meta("touch_sized")` 挡住第二次，否则字号变成 +4。
2. **`_style_game_tool_buttons()` 必须先刷样式再定 `size`**：字号会抬高 Button 的最小尺寸，
   先设 `size` 会被 clamp 到「旧字号」的 min —— 触屏 48 切回桌面时高度会僵在 ~40 而不是 32。

### 12.4 C 触控交互（`_touch_ui` 生效时）

| 痛点 | 桌面行为 | 触屏行为 |
|------|---------|---------|
| 悬停粘住 | 轮询鼠标位置 → 抬起牌 + 信息栏显示详情 | **只在按住时**抬起，松手立即落下并还原信息栏（Android 没有 `mouse_exited`，抬起状态会永远粘在最后点过的那张牌上） |
| 点选时手抖被判成拖拽 | 位移 ≥ `DRAG_THRESHOLD`(6px) 即重排 | **两档**：`TOUCH_DRAG_ARM_MOVE`(10px) 起拖跟手、`TOUCH_DRAG_THRESHOLD`(24px) 松手才确认重排；<24px 回退成点选（起拖门槛 < 回退门槛，所以点击永远不会被吞） |
| 手指压在牌缝 / 边缘外 | 严格矩形，未命中即忽略 | 严格命中优先；全落空时才用外扩 `TOUCH_HIT_PAD`(8px) 兜底，不会抢走正常判定 |
| 看不出选中了哪张 | 悬停抬起 20px + 黄色描边 | 选中的牌**常驻上浮 10px**（悬停后落下也保留），且 `z_index=Z_HAND_SELECTED` |
| 误点「退出游戏」 | 立刻进结算页 | 二次确认：按钮变「确认退出?」，3 秒内再点才执行，超时自动回滚文字 |
| 没有触摸反馈 | — | 选牌时 `Input.vibrate_handheld(30)`（需 `permissions/vibrate=true`，已开） |

实现要点：

- `_layout_hand_cards()` 里 `base_pos` 存的是**未上浮**的静止位置，`position` 才减去选中上浮。
  所有命中判定（`_card_hover_rect` / `_card_core_rect` / `_hit_card_at`）都基于 `base_pos`，
  所以上浮只影响画面，不影响判定；`_apply_hover(btn,false)` 落回时也要减 `_selected_lift()`，
  否则刚选中的牌被悬停一次、松手就归位，选中提示消失。
- 触屏档不接 `mouse_entered/exited` 缩放（会永远停在 1.05），改「按下 0.96 / 松手回 1.0」。

### 12.5 测试与回归

```bash
godot --headless --path . --script tests/verify_touch_ui.gd
```

53 项断言分 8 组：桌面基准 10、工具行几何 15、字号 8、命中缓冲 4、选中上浮 6、
页面按钮 3、退出二次确认 5、**关档归零 2**。最后一组会把 `_touch_ui` 切回 `false`
并重跑 `_style_game_tool_buttons()`，确认触屏放大值没有漏进桌面路径。
（v14.7 起又并入「拖拽两档」一组：起拖 / 确认阈值分离、12px 松手回退成点选、
40px 松手真的重排、桌面基准断言追加 `_drag_arm_threshold() == 6`。）

### 12.6 触屏实测反馈修复（v14.5）

| 反馈 | 根因 | 修法 |
|---|---|---|
| 第零关提示一上来就推荐**族炸** | `HintAdvisor._score()` 里 `P_CLAN=400` 高于化合物/单质，族炸恒被选中 | `_candidates()` 只在**第零关教学**（`tutorial_level == 0 and tutorial_level0_phase >= 1`）不生成族炸候选；`_check()` / `is_playable()` 不动 → 玩家手动照样能打 |
| 教程里**手牌拖不动** | `_can_reorder_hand()` 只要 `tutorial_level > 0 or phase > 0` 就 false，把整个教程锁死 | 收紧为 `tutorial_level == 0 and 1 <= phase < 3`：只有「UI 标注 / 流程介绍」禁用，练习阶段与第一 / 二关放开 |
| 提示框**文字跑到框外** / 框被推出屏幕 | `size` 在 `autowrap_mode` 之前设置（见 §8）；`tbx=620 + tbw=560 = 1180 > 1152` | 四处 Label 改成「先 autowrap 后 size」；`tbw 560→520`，并把 `tbx/tby` 用 `clampi` 夹进画布（留 20px 边距） |
| 日志数字与规则提醒**叠字**「666」 | 规则提醒 `(950,370) 220×220` 整个躺在 `LogLabel` (824..1136 × 300..600) 里，且右边界 1170 越出画布 | 规则提醒搬到 `LogLabel` 同格（824,300 / 312×300）+ 浅黄背景板，两者互斥可见；文案只讲「越大越小 / 同类同出」，玩家真打出族炸才补「牌权争夺」 |
| 退出教程后规则提醒**还留在正常对局** | 提醒挂在 `ContentLayer`，`_level0_update_rule_tips()` 在非第零关时只 `return`，既不隐藏也不释放 | 新增 `_level0_clear_rule_tips()`（释放 + 日志复位），在 `_init_game()` / `_on_start_tutorial()` / `_show_start_page()` 调用；`_refresh_ui()` 路径改为「隐藏 + 清文本 + 日志复位」 |

回归：`tests/verify_hint.gd`（L0 不推荐族炸 / 自由模式与第二关照旧推荐）、
`tests/verify_tutorial.gd`（L0 `clan_bomb_disabled == false`、L1 `== true`、L0 引导文案）、
`tests/verify_hand_reorder.gd` 最后一组（phase 1/2 禁用、phase 3 与 L1/L2/自由模式放行）、
`tests/verify_tutorial_layout.gd`（6 个提示框 rect 全在 1152×648 内、Label 宽度不被撑大、
规则提醒与日志互斥、四类退出路径后提醒被释放）。

---

**文档版本**: 14.7  
**最后更新**: 2026-11-02
