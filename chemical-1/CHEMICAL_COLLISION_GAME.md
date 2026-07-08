# ⚗️ 化学碰撞 (Chemical Collision) — 游戏设计文档

> **版本**: 6.0  
> **日期**: 2026-07-08  
> **引擎**: Godot 4.x  
> **语言**: GDScript  
> **当前状态**: 全功能完成

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [卡牌系统](#3-卡牌系统)
4. [牌库系统](#4-牌库系统)
5. [游戏管理器](#5-游戏管理器)
6. [UI 系统](#6-ui-系统)
7. [工具函数（牌型系统）](#7-工具函数牌型系统)
8. [化合物系统](#8-化合物系统)
9. [族炸系统](#9-族炸系统)
10. [牌权轮转规则](#10-牌权轮转规则)
11. [比大小规则](#11-比大小规则)
12. [接牌规则](#12-接牌规则)
13. [逻辑链路](#13-逻辑链路)
14. [着色规则](#14-着色规则)
15. [扩展方向](#15-扩展方向)

---

## 1. 项目概览

"化学碰撞"是一款以化学元素周期表为主题的多人卡牌对战游戏。

### 核心特性

| 特性 | 说明 |
|------|------|
| 牌库规模 | 108 张牌，前三周期 18 种元素各 6 张 |
| 玩家数量 | 3~8 人（1 人类 + N AI，开始页可配置） |
| 初始手牌 | 每人 8 张 |
| 牌型系统 | 3 种：单质 / 化合物 / 族炸 |
| 出牌规则 | 必须比桌面牌更大（起手者/族炸除外） |
| 牌权轮转 | 出牌 → 下一名玩家接牌/过 → 总人数-1 人连续过 → 牌权移交 → 新一轮 |
| 族炸机制 | 同族 ≥2 张不同元素 → 抢夺牌权，接炸链独立处理 |

---

## 2. 文件结构

```
chemical-1/
├── project.godot
├── Main.tscn                         # 4 页：Start / Game / Help / End
├── scripts/
│   ├── CardData.gd                   # 13 个属性 + 序列化
│   ├── CardDatabase.gd               # 18 种 × 6 张 = 108 张
│   ├── GameManager.gd                # 多人管理 + 牌权轮转 + 接炸链
│   ├── GameUI.gd                     # 手牌按钮 / AI / 着色 / 圆形状态
│   └── Utils.gd                      # 牌型判定 / 多元素化合物 / 比大小
├── CHEMICAL_COLLISION_GAME.md        # 本文档 (v6.0)
└── GAMEPLAY_RULES.md                 # 玩法规则与程序实现 (v6.0)
```

---

## 3. 卡牌系统

每张卡牌表示一个化学元素，包含 13 个属性：

| 属性 | 类型 | 示例 |
|------|------|------|
| `symbol` | String | `"Na"` |
| `name_cn` | String | `"钠"` |
| `atomic_number` | int | `11` |
| `group` | String | `"IA"` |
| `element_type` | String | `"金属"` |
| `common_valence` | Array | `[1]` |
| `atomic_weight` | float | `22.99` |

---

## 4. 牌库系统

牌库包含前三周期 18 种元素，每种 6 张，共 108 张。

| 周期 | 元素 |
|------|------|
| 1 | H, He |
| 2 | Li, Be, B, C, N, O, F, Ne |
| 3 | Na, Mg, Al, Si, P, S, Cl, Ar |

---

## 5. 游戏管理器

### 5.1 Core Functions

```
init_game(player_count, ai_count) → bool
  ├── 验证参数 (3 ≤ player ≤ 8, ai < player)
  ├── CardDatabase → generate_deck() → shuffle()
  ├── 创建 PlayerInfo 数组 → 每人发 8 张
  └── phase = PLAYING, is_round_starter = true

play_cards(player_index, cards, custom_valences={}) → int
  ├── detect_pattern(cards, skip_bomb)
  ├── 比大小 & 冷却 & 牌型匹配检查
  ├── 化合物比例校验 (remove_cards 之前)
  ├── 族炸 → 启动接炸链
  └── OK → next_turn()

player_pass(player_index)
  ├── 接炸模式：跳过不抽牌
  └── 正常模式：抽 1 张 → next_turn()
```

---

## 6. UI 系统

### 6.1 Main.tscn — 4 页布局

```
Main (Control)
├── StartPage          ← 标题 + SpinBox(3–8 玩家, AI) + 开始游戏 + 退出程序
├── HelpPage           ← 游戏规则 + 牌型示例 + 返回按钮
├── GamePage           ← 游戏主界面
│   ├── InfoLabel      ← ● 玩家1 ◄ → ● AI1 ❄ → ● AI2 ⏸ → ...
│   ├── TableLabel     ← 桌面牌型
│   ├── HandContainer  ← 手牌按钮（着色规则）
│   ├── ActionPanel    ← step0/step1/step2 出牌流程
│   ├── CardInfoLabel  ← 提示文本
│   └── LogLabel       ← 游戏日志
└── EndPage            ← 获胜者 + 返回主页
```

---

## 7. 工具函数

### 7.1 牌型判定

```
detect_pattern(cards, skip_clan_bomb=false):
  1. 1 张 → ELEMENT
  2. 2 张同元素 & H/N/O/F/Cl → ELEMENT (X₂)
  3. skip_clan_bomb=false & 同族 ≥2 不同元素 → CLAN_BOMB
  4. 化合价可配平 → COMPOUND
  5. 否则 → -1
```

---

## 8. 化合物系统

| 约束 | 说明 |
|------|------|
| 元素数量 | ≥2 种 |
| 2 元素 | GCD 最简比 (rp = nv/g, rn = pv/g) |
| 3+ 元素 | 每种恰好 1 张 + 总电荷 = 0 |
| 金属优先 | 金属作为正价 |
| 比例校验 | play_cards 中 remove_cards 之前调用 ratio_ok |

---

## 9. 族炸系统

| 条件 | 说明 |
|------|------|
| 元素 | ≥2 张不同元素，全部同族 |
| 等级 | 3 张 > 2 张 |
| 冷却 | 打出族炸后直到打出化合物前不能再出族炸 |
| 接炸 | 顺时针询问，接炸需出更大的族炸 |

### 接炸链流程

```
A 出族炸 → owner=A, chain_active=true
  → 顺时针询问 B (跳过 A)
	→ B 出更大的族炸 → owner=B
	→ B 跳过 → 不抽牌
  → 所有非 owner 已 pass
  → 桌面清空，owner 自由出牌
```

---

## 10. 牌权轮转规则

### 规则描述

```
1. 游戏开始，一名玩家拥有牌权，自由出牌。
   若为族炸，依照族炸接炸链设计；若是其他，进入下一步。

2. 下一名玩家出牌，他选择接牌或过。

3. 继续第 2 步，直到出现总人数-1 名玩家连续选择过。

4. 此时，将牌权交给最后一名选择过的玩家的下一名玩家，
   其自由出牌（新一轮开始，桌面清空）。
```

### 实现（GameManager.gd `_start_new_round`）

```gdscript
func _start_new_round() -> void:
	table_cards.clear()
	table_pattern = -1
	table_player_index = -1
	is_round_starter = true
	_reset_all_passes()
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	compound_immune = false

	# 牌权交给最后一名跳过的玩家的下一名玩家
	current_player_index = (current_player_index + 1) % players.size()
	for _i in range(players.size()):
		var p = players[current_player_index]
		if p.get_hand_count() > 0:
			log_messages.append("====== 新一轮！%s 自由出牌 ======")
			return
		current_player_index = (current_player_index + 1) % players.size()
```

### 牌权轮转示例

```
4 人游戏：P1 → P2 → AI1 → AI2

桌面：P1 打出 Na
  → AI1 接单质 He（更大）
  → AI2 过（抽 1 张）
  → P1 过（抽 1 张）
  → 总人数-1=3 人连续过 → 牌权交给 P1（最后出的下一名玩家）
  → P1 自由出牌
```

---

## 11. 比大小规则

### 优先级

```
族炸 > 化合物 > 单质
```

### 同牌型比较

| 牌型 | 规则 |
|------|------|
| 族炸 vs 族炸 | 3 张 > 2 张；同数量比原子序数和（小→大） |
| 化合物 vs 化合物 | 原子序数和（小→大） |
| 单质 vs 单质 | 原子序数和（小→大） |

### tiebreak

原子序数和相同时，比相对原子质量总和 → 质量大者牌更弱。

---

## 12. 接牌规则

```
自由出牌 → 任意牌型
桌面单质 → 更大的单质/族炸
桌面化合物 → 更大的化合物/族炸
  例外：溢出化合物（牌数 > 玩家数）→ 免疫！只能出族炸
族炸 → 接炸链（只能出族炸）
```

---

## 13. 逻辑链路

```
Start Page → 选择人数 → Start Game
  ↓
GameManager.init_game(total, ai) → 108 张牌洗牌 → 发牌
  ↓
回合循环:
  _refresh_ui() → 圆形状态 + 桌面信息 + 手牌按钮
  人类操作 → step0 选牌 → step1 选牌型 → step2 化合价(化合物)
  AI 操作 → _ai_try_play() → 候选遍历 play_cards()
  play_cards() → detect_pattern + 比大小 + 化合物比例校验
  牌权轮转 → next_turn() → 接牌/过 → 总人数-1 连续过 → 新一轮
  族炸 → 接炸链 → 无人接 → 出炸者自由出牌
  手牌 = 0 → GAME_OVER → End Page
```

---

## 14. 着色规则

| 元素/组 | 颜色 |
|---------|------|
| H | 浅蓝 |
| O | 蓝色 |
| N | 蓝紫 |
| C, B, Si, S | 黄色 |
| P | 红白 |
| 卤族 (F, Cl) | 绿色 |
| 其余金属 | 灰色 |
| 其余非金属/准金属 | 绿色 |
| 稀有气体 | 白色 |

---

**文档版本**: 6.0  
**最后更新**: 2026-07-08
