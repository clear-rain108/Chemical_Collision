# 化学碰撞 — 程序架构与实现文档

> **版本**: 13.0  
> **日期**: 2026-08-06  
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
│   ├── AIPlayer.gd                    ← AI决策：出牌策略（族炸/化合物/双原子/单质/接顺序）
│   ├── TutorialController.gd          ← 教程状态机：关卡初始化/预设手牌/进度检查
│   ├── TutorialUI.gd                  ← 教程内容：引导文本/成功提示（静态）
│   └── GameUI.gd                      ← UI控制器：页面切换/牌面渲染/步骤流/着色
├── tests/
│   ├── verify_refactor.gd             ← 模块单测（牌型/化合物/日志/玩家/Q4牌型选择）
│   ├── verify_integration.gd          ← 集成测试（GameManager + AIPlayer）
│   ├── verify_logger.gd               ← 日志转发测试
│   ├── verify_tutorial.gd             ← 教程控制器集成测试
│   └── verify_ai_discard.gd           ← AI 上限自动弃牌测试（Q1+Q2）
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
| is_compound / _can_balance_valence | 化合物合法性检测 |
| get_compound_formula | 配平 + 化学式生成（含非金属正价兜底：无金属时提升 H 及酸中心原子为正价）|
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

**职责**: 回合管理、出牌校验、族炸接炸链、上限弃牌（牌的使用和打出）。玩家信息已拆至 PlayerManager，日志已拆至 GameLogger。

### PlayerInfo 玩家信息类（已拆至 PlayerManager.gd）

```
PlayerManager.PlayerInfo
属性: player_name, hand, is_ai, has_passed, clan_bomb_cooling
方法: get_hand_count(), add_card(), remove_cards(), sort_hand_by_atomic_number()
```

### 核心变量

| 变量 | 说明 |
|------|------|
| clan_bomb_chain_active | 族炸接炸链激活 |
| clan_bomb_owner | 接炸链引爆者索引 |
| clan_bomb_disabled | 禁用族炸（第一关） |
| tutorial_level | 0=自由模式, 1=第一关, 2=第二关 |
| tutorial_step | 当前教程步骤 |
| compound_immune | 溢出化合物免疫族炸 |
| table_custom_valences | 桌面化合物实际化合价（play_cards 出牌时保存，渲染化学式/排序/化合价显示用）|
| _get_hand_limit() | min(players×4, 18) |

### 核心函数流程

```
init_game(total, ai) → bool
play_cards(idx, cards, cv) → int
  ├─ detect_pattern → 族炸/非族炸判定
  ├─ 族炸: 冷却/免疫/接炸比较 → next_turn()（牌权移交）
  ├─ 化合物: 比例校验 → 保存 table_custom_valences → 溢出检查
  └─ 非族炸: 牌型匹配 → 比大小
player_pass(idx) → 上限检查 → 抽牌 → next_turn()
player_discard_and_pass(idx, card) → 上限弃牌
next_turn() → 族炸链? _intercept_next() : 找下一位未pass玩家
_init_tutorial(level) → 预设手牌 + 教程步骤初始化
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
  └─ 常规：族炸→化合物 O(n²)→双原子→单质→pass
```

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
| StartPage | 开始页（模式选择+教学引导入口） |
| TutorialPage | 教学引导页（关卡选择） |
| HelpPage_Rules | 规则介绍（4栏横排） |
| HelpPage_Cards | 卡牌图鉴（4栏横排） |
| GamePage | 游戏主界面（牌面+操作） |
| EndPage | 结束页 |

### 手牌渲染

`_build_card_button()` — 95×118px 白底圆角牌面：
- 左上：原子序数 | 右上：族 | 中上：元素符号(着色) | 中：中文名 | 中下：化合价(±标注) | 左下：相对原子质量

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
	├─ 化合物配对 O(n²)（跳过卤族互化对；化合价直接取公式配平结果，如 HCl 中 H=+1、Cl=-1）
	├─ 双原子分子配对
	├─ 单质单张
	└─ 全部失败 → player_pass()（达上限时自动弃1张）
```

---

## 9. 场景结构 - Main.tscn

```
Main (Control) ← GameUI.gd
├── StartPage          ← 标题 + SpinBox + 开始游戏 + 退出 + [教学引导]
├── TutorialPage       ← 教学引导页：关卡1/关卡2 + 返回
├── HelpPage_Rules     ← 规则介绍（4栏）
├── HelpPage_Cards     ← 卡牌图鉴（4栏）
├── GamePage           ← 游戏主界面
│   ├── GameBackground ← Color(0.78,0.88,0.98)
│   ├── TitleLabel / InfoLabel / TableLabel / DeckCountLabel
│   ├── HandLabel / HandContainer (HFlow)
│   ├── ActionPanel (HBox) / CardInfoLabel / TutorialLabel
│   └── HintButton / HelpBtn / QuitButton
└── EndPage
```

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
| get_compound_formula | CompoundSolver.gd（含非金属正价兜底）| O(n) |
| compare_cards | CardPatterns.gd | O(n) |
| generate_deck | CardDatabase.gd | O(28×copies) |
| shuffle | CardDatabase.gd | O(n) Fisher-Yates |
| _try_play (AI) | AIPlayer.gd | O(n²) 化合物配对 |
| _intercept_next | GameManager.gd | O(n) 顺时针查找 |

---

**文档版本**: 15.0  
**最后更新**: 2026-08-22
