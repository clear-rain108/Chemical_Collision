# ⚗️ 化学碰撞 (Chemical Collision) — 游戏设计文档

> **版本**: 3.0  
> **日期**: 2026-07-07  
> **引擎**: Godot 4.x  
> **语言**: GDScript  
> **当前状态**: 全迭代完成（核心玩法可运行）

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [卡牌系统](#3-卡牌系统)
4. [牌库系统](#4-牌库系统)
5. [游戏管理器](#5-游戏管理器)
6. [UI 系统](#6-ui-系统)
7. [工具函数（牌型系统）](#7-工具函数牌型系统)
8. [场景配置](#8-场景配置)
9. [逻辑链路](#9-逻辑链路)
10. [扩展方向](#10-扩展方向)

---

## 1. 项目概览

"化学碰撞"是一款以化学元素周期表为主题的多人卡牌对战游戏。玩家使用包含 108 张元素牌的牌组，通过出牌比大小、组合化合物、触发"族炸"等机制进行对战，目标是率先打光手牌。

### 核心特性

| 特性 | 说明 |
|------|------|
| **牌库规模** | 108 张牌，前三周期 18 种元素各 6 张 |
| **玩家数量** | 3~6 人（支持人机混合） |
| **初始手牌** | 每人 8 张 |
| **牌型系统** | 3 种牌型：**单质** / **化合物** / **族炸** |
| **出牌规则** | 必须比桌面牌更大才能出牌（起手者/族炸除外） |
| **族炸机制** | 同族 ≥2 张不同元素 → 抢夺牌权，无论大小都能打出 |
| **AI 对手** | 内置 AI，按优先级生成候选，逐个尝试比大小出牌 |
| **UI 着色** | 金属蓝/非金属红/准金属绿/稀有气体紫 |

### 技术约束

- 不使用 `class_name`，全部通过 `preload` 加载依赖
- UI 根节点为 `Control`
- Godot 4.2+ / 4.7 兼容

---

## 2. 文件结构

```
chemical-1/
├── project.godot                  # 引擎配置（主场景 Main.tscn）
├── Main.tscn                      # 主场景（Control 根布局）
├── icon.svg                       # 项目图标
├── scripts/
│   ├── CardData.gd                # 卡牌数据结构（13 个属性 + 序列化）
│   ├── CardDatabase.gd            # 牌库生成（18 种 × 6 张 = 108） + 洗牌 + 抽牌
│   ├── GameManager.gd             # 多人管理 + 回合轮转 + 出牌比大小 + Pass 轮次
│   ├── GameUI.gd                  # 主界面控制（手牌按钮 / AI 候选出牌 / 按钮绑定）
│   └── Utils.gd                   # 工具函数（牌型判定 / 化合物 / 比大小）
└── CHEMICAL_COLLISION_GAME.md     # 本文档
```

---

## 3. 卡牌系统

### 3.1 CardData.gd

每张卡牌表示一个化学元素，包含以下 13 个属性：

| 属性 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `symbol` | String | 元素符号 | `"Na"` |
| `name_cn` | String | 中文名称 | `"钠"` |
| `name_en` | String | 英文名称 | `"Sodium"` |
| `atomic_number` | int | 原子序数 | `11` |
| `group` | String | 所属族 | `"IA"` |
| `period` | int | 周期 | `3` |
| `element_type` | String | 元素类型 | `"金属"` / `"非金属"` / `"准金属"` / `"稀有气体"` |
| `single_form` | String | 单质形态 | `"固体"` / `"液体"` / `"气体"` / `"人造"` |
| `valence_electrons` | int | 最外层电子数 | `1` |
| `common_valence` | Array | 常见化合价列表 | `[1]` / `[-2, 4, 6]` |
| `electronegativity` | float | 电负性 | `0.93` |
| `atomic_weight` | float | 相对原子质量 | `22.99` |
| `description` | String | 描述文本 | `"活泼的碱金属"` |

---

## 4. 牌库系统

### 4.1 CardDatabase.gd

#### 元素数据

牌库包含 **前三周期 18 种元素**（从 ¹H 到 ¹⁸Ar）：

| 周期 | 元素 |
|------|------|
| 第 1 周期 | H(氢), He(氦) |
| 第 2 周期 | Li(锂), Be(铍), B(硼), C(碳), N(氮), O(氧), F(氟), Ne(氖) |
| 第 3 周期 | Na(钠), Mg(镁), Al(铝), Si(硅), P(磷), S(硫), Cl(氯), Ar(氩) |

每种元素 **6 张**，牌库总数 18 × 6 = **108 张**。

#### 各族分布

| 族 | 元素 | 族炸可用 |
|-----|------|----------|
| IA | H, Li, Na | ✅ (3 种) |
| IIA | Be, Mg | ✅ (2 种) |
| IIIA | B, Al | ✅ (2 种) |
| IVA | C, Si | ✅ (2 种) |
| VA | N, P | ✅ (2 种) |
| VIA | O, S | ✅ (2 种) |
| VIIA | F, Cl | ✅ (2 种) |
| 0 (稀有气体) | He, Ne, Ar | ✅ (3 种) |

> **所有 8 个族都有 ≥2 种元素，均可触发族炸。**

---

## 5. 游戏管理器

### 5.1 GameManager.gd

#### 枚举

```gdscript
enum PlayResult { OK, NOT_STRONGER, INVALID_PATTERN }
enum GamePhase { INIT, PLAYING, GAME_OVER }
```

#### 游戏流程

```
init_game(player_count=4, ai_count=3)
  ├── CardDatabase → generate_deck() → shuffle()
  ├── 创建 PlayerInfo 数组 → 每人发 8 张
  └── phase = PLAYING, is_round_starter = true

play_cards(player_index, cards) → PlayResult
  ├── detect_pattern() → 非法返回 INVALID_PATTERN
  ├── 非起手者 & compare_cards ≤ 0 → NOT_STRONGER
  ├── 从手牌移除，更新桌面，重置 pass
  ├── 族炸 → 不切换回合
  ├── 手牌 0 → GAME_OVER
  └── next_turn()

player_pass(player_index)
  ├── has_passed = true + 抽 1 张
  └── next_turn()

next_turn()
  ├── 存活 ≤1 → GAME_OVER
  ├── 未 pass ≤1 → 新一轮（清桌面，自由出牌）
  └── 顺时针找下一个未 pass 玩家
```

#### 轮次逻辑

```
初始：桌面空，is_round_starter = true（自由出牌）
出牌时：非起手者必须 > 桌面牌（族炸除外）
Pass：抽 1 张 + next_turn()
只剩 1 个未 pass → 新一轮开始
```

---

## 6. UI 系统

### 6.1 Main.tscn 场景结构

```
Main (Control)
├── TitleLabel            ← "Chemical Collision"
├── InfoLabel             ← 玩家状态
├── TableLabel            ← 桌面信息
├── HandLabel             ← "My Hand:"
├── HandContainer (HFlowContainer)
└── ActionPanel
    ├── PlayButton        ← "Play Cards"
    └── PassButton        ← "Pass Draw"
```

### 6.2 交互流程

**人类玩家回合**：
1. 点击手牌按钮选中/取消（黄色 `✓`）
2. 点击 "Play Cards" → 判定牌型 → 比大小出牌
3. 不够大？提示 "Must play bigger cards or Pass"
4. 点击 "Pass Draw" → 抽 1 张 → 结束回合

**AI 玩家回合**：
1. 显示 "Waiting for AI X..."
2. 生成候选（族炸 > 化合物 > 双原子分子 > 单质单张）
3. 遍历候选比大小，全部不过则 Pass

### 6.3 元素类型着色

| 类型 | 颜色 |
|------|------|
| 金属 | 蓝色 |
| 非金属 | 红色 |
| 准金属 | 绿色 |
| 稀有气体 | 紫色 |
| 选中 | 黄色 |

---

## 7. 工具函数（牌型系统）

### 7.1 牌型枚举

```gdscript
enum CardPattern {
    ELEMENT,     # 单质（1 张，或双原子分子的 2 张同元素）
    COMPOUND,    # 化合物（多元素化合价匹配）
    CLAN_BOMB,   # 族炸（同族 ≥2 张不同元素）
}
```

### 7.2 牌型判定规则

```
detect_pattern(cards):
  1. cards.size() == 1 → ELEMENT（单质单张）
  2. cards.size() == 2 & 同元素 & 属于双原子分子(H/N/O/F/Cl) → ELEMENT（X₂）
  3. 同族不同元素 ≥2 → CLAN_BOMB
  4. 多元素化合价可配平 → COMPOUND
  5. 否则 → -1（非法）
```

### 7.3 双原子分子单质

自然界中以双原子分子（X₂）形式存在的元素：

| 符号 | 单质形式 |
|------|----------|
| H | H₂ |
| N | N₂ |
| O | O₂ |
| F | F₂ |
| Cl | Cl₂ |

打出 2 张同元素 H/N/O/F/Cl 牌 → 视为单质 X₂，显示 "单质 H₂" 等。

> 注意：其他元素只支持单张出牌（如 He 只能出 1 张 He）。

### 7.4 化合物检测

```gdscript
_is_compound(cards):
  ├── 拒绝稀有气体
  └── 正价 + 负价可配平

get_compound_formula(cards):
  └── 交叉下标生成化学式 (Na + Cl → "NaCl")
```

### 7.5 牌型比较

```gdscript
compare_cards:
  族炸 > 其他一切
  族炸 vs 族炸：数量多 > 原子序数和大
  化合物 vs 化合物：原子序数和大
  单质 vs 单质：原子序数和大
  跨牌型优先级：族炸 > 化合物 > 单质
```

---

## 8. 场景配置

### 8.1 project.godot

```ini
[application]
config/name="Chemical1"
run/main_scene="res://Main.tscn"
config/icon="res://icon.svg"
```

---

## 9. 逻辑链路

### 完整游戏流程

```
启动 → Main.tscn → GameUI._ready()
  └── GameManager.init_game(4, 3)
       ├── CardDatabase 生成 108 张 (18种 × 6)
       ├── Fisher-Yates 洗牌
       ├── 创建 4 玩家 (1 人类 + 3 AI)
       ├── 发牌 4×8 = 32 张
       └── is_round_starter = true

回合循环:
  _refresh_ui()
    ├── InfoLabel ← get_all_players_info()
    ├── TableLabel ← 桌面 (单质X₂/化合物/族炸)
    ├── _update_hand_buttons()
    └── _update_action_buttons()

  人类操作:
    ├── 选中手牌 (黄色 ✓)
    ├── Play → detect_pattern()
    │    ├── 非法 → "Only single/diatomic/compound/clan bomb"
    │    ├── NOT_STRONGER → "Must play bigger or Pass"
    │    └── OK → play_cards() → _refresh_ui()
    └── Pass → player_pass() → _refresh_ui()

  AI 操作 (_ai_auto_play):
    ├── _ai_find_candidates()
    │    (族炸 > 化合物 > X₂ > 单张)
    ├── 遍历候选 try play_cards()
    └── 全不过 → Pass

game_over:
  └── _show_game_over()
```

### 族炸特殊流程

```
CLAN_BOMB:
  ├── 跳过比大小检查
  ├── 从手牌移除，更新桌面
  ├── 检查胜利
  └── 不调用 next_turn()（保持牌权）
```

---

## 10. 扩展方向

- **角色系统**: 不同初始手牌 / 特殊技能
- **网络联机**: 多人实时对战
- **动画&音效**: 族炸特效、出牌动画
- **牌面美术**: 元素图标/插画

---

**文档版本**: 3.0  
**最后更新**: 2026-07-07  
**适用引擎**: Godot 4.x  
**当前状态**: 全迭代完成 ✅