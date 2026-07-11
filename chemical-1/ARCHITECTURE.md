# 化学碰撞 — 程序架构与实现文档

> **版本**: 12.0  
> **日期**: 2026-07-11  
> **引擎**: Godot 4.x / GDScript

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [数据层 - CardData.gd](#3-数据层---carddatagd)
4. [数据层 - CardDatabase.gd](#4-数据层---carddatabasegd)
5. [逻辑层 - Utils.gd](#5-逻辑层---utilsgd)
6. [逻辑层 - GameManager.gd](#6-逻辑层---gamemanagergd)
7. [表现层 - GameUI.gd](#7-表现层---gameuigd)
8. [场景结构 - Main.tscn](#8-场景结构---maintscn)
9. [数据流](#9-数据流)
10. [关键算法](#10-关键算法)

---

## 1. 项目概览

"化学碰撞"是一款以元素周期表为主题的多人卡牌对战游戏。项目按 **MVC 分层**组织：

```
┌─────────────────────────────────────────┐
│                      表现层              │
│  Main.tscn  GameUI.gd                   │
│  6页UI  着色与牌面渲染  按钮交互         │
│  手牌上限检查  牌库计数  教程引导        │
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
├── project.godot                      ← 引擎配置
├── Main.tscn                          ← 6 页场景
├── scripts/
│   ├── CardData.gd                    ← 数据模型：13属性+16族常量+序列化
│   ├── CardDatabase.gd                ← 牌库：28种元素(卤族10/高8/主6/副4)=172张
│   ├── GameManager.gd                 ← 规则引擎：play_cards/牌权/接炸/上限弃牌/教程
│   ├── GameUI.gd                      ← UI控制器：牌面渲染/步骤流/AI/着色/教程
│   └── Utils.gd                       ← 工具函数：detect_pattern/compound/compare
├── CHEMICAL_COLLISION_GAME.md         ← 游戏设计文档
├── GAMEPLAY_RULES.md                  ← 玩法规则文档
├── ARCHITECTURE.md                    ← 本文档
├── COLORING_DOCUMENTATION.md          ← 元素着色文档
├── COMPOUND_MECHANISM_COMPARISON.md   ← 化合物机制对比
└── AI_PLAYER_AUDIT.md                ← AI与玩家逻辑对照审计
```

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

**职责**: 牌库生成（172张）与 Fisher-Yates 洗牌。

### 张数分级

| 常量 | 元素 | 张数 |
|------|------|------|
| HALOGEN_SYMBOLS | F, Cl, Br | 10 |
| HIGH_COUNT_SYMBOLS | H, O, S | 8 |
| SUBGROUP_SYMBOLS | Cr~Zn (7种) | 4 |
| 其余主族 (15种) | — | 6 |

### 模块结构

| 模块 | 行号 | 说明 |
|------|------|------|
| 张数常量 | L9-16 | 四级张数定义 |
| 元素数据 | L19-54 | 28种元素原始数据（13字段/元素）|
| 牌库生成 | L60-79 | generate_deck() 按 sym 动态计算 copies |
| 洗牌与抽牌 | L83-106 | Fisher-Yates shuffle, draw_card, draw_cards |
| 查询 | L110-111 | get_remaining_count() |

---

## 5. 逻辑层 - Utils.gd

**职责**: 牌型判定、化合物配平、比大小。所有方法均为 `static`。

### 牌型检测优先级

```
detect_pattern(cards, skip_clan_bomb=false):
  1. 1张 → ELEMENT
  2. 2张同元素 & H/N/O/F/Cl → ELEMENT (X₂)
  3. !skip_clan_bomb & 同族≥2不同元素 → CLAN_BOMB
  4. ≥2张 & 化合价可配平 → COMPOUND
  5. 否则 → -1
```

### 模块结构

| 模块 | 行号 | 说明 |
|------|------|------|
| 枚举与常量 | L8-17 | CardPattern enum, DIATOMIC_SYMBOLS |
| 牌型检测 | L20-58 | detect_pattern, _is_same_element |
| 族炸检测 | L62-77 | _is_clan_bomb |
| 化合物检测 | L81-176 | _is_compound, _can_balance_valence, get_compound_formula |
| 单质显示 | L181-205 | get_element_display, _to_subscript |
| 比大小 | L210-270 | compare_cards, _compare_by_total_atomic |
| 辅助 | L274-279 | get_pattern_name |

---

## 6. 逻辑层 - GameManager.gd

**职责**: 回合管理、出牌校验、族炸接炸链、教程关卡、上限弃牌。

### PlayerInfo 内部类

```
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
| _get_hand_limit() | min(players×4, 18) |

### 核心函数流程

```
init_game(total, ai) → bool
play_cards(idx, cards, cv) → int
  ├─ detect_pattern → 族炸/非族炸判定
  ├─ 族炸: 冷却/免疫/接炸比较 → next_turn()（牌权移交）
  ├─ 化合物: 比例校验 → 溢出检查
  └─ 非族炸: 牌型匹配 → 比大小
player_pass(idx) → 上限检查 → 抽牌 → next_turn()
player_discard_and_pass(idx, card) → 上限弃牌
next_turn() → 族炸链? _intercept_next() : 找下一位未pass玩家
_init_tutorial(level) → 预设手牌 + 教程步骤初始化
_check_tutorial_progress(pattern, human) → 进度检查
```

---

## 7. 表现层 - GameUI.gd

**职责**: 页面管理、牌面渲染、步骤流、AI、着色、教程显示。

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

### AI 策略

```
_ai_auto_play():
  族炸链中 → 冷却跳过 / 出族炸
  否则 → _ai_try_play():
    ├─ 族炸尝试（同族≥2张）
    ├─ 化合物配对 O(n²)（跳过卤族互化对）
    ├─ 双原子分子配对
    ├─ 单质单张
    └─ 全部失败 → player_pass()
```

---

## 8. 场景结构 - Main.tscn

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

## 9. 数据流

```
Start Page → 选择模式（自由/第一关/第二关）
  ↓
GameManager.init_game / init_tutorial
  ├── 172张牌洗牌 / 预设手牌
  └── phase=1

回合循环:
  _refresh_ui() → 状态/桌面/手牌/牌库计数/教程
  人类: 选牌→选牌型→卤族互化→化合价→play_cards
  AI: 1.5s延迟→_ai_try_play→play_cards
  pass: 上限→弃牌模式 / 正常→抽1张→next_turn
  族炸: clan_bomb_chain_active→next_turn→_intercept_next
  溢出: compound_immune→免疫族炸
  手牌=0 → GAME_OVER
```

---

## 10. 关键算法

| 算法 | 位置 | 复杂度 |
|------|------|--------|
| detect_pattern | Utils.gd L21-47 | O(n) |
| _is_clan_bomb | Utils.gd L62-77 | O(n) |
| get_compound_formula | Utils.gd L113-176 | O(n) |
| compare_cards | Utils.gd L213-252 | O(n) |
| generate_deck | CardDatabase.gd L61-79 | O(28×copies) |
| shuffle | CardDatabase.gd L83-89 | O(n) Fisher-Yates |
| _ai_try_play | GameUI.gd | O(n²) 化合物配对 |
| _intercept_next | GameManager.gd | O(n) 顺时针查找 |

---

**文档版本**: 12.0  
**最后更新**: 2026-07-11