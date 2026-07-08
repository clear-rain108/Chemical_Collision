# 化学碰撞 — 玩法规则与程序实现文档

> **版本**: 6.0  
> **日期**: 2026-07-08  
> **引擎**: Godot 4.x / GDScript

---

## 目录

1. [游戏概览](#1-游戏概览)
2. [牌库](#2-牌库)
3. [三种牌型](#3-三种牌型)
4. [牌权轮转规则](#4-牌权轮转规则)
5. [单质](#5-单质)
6. [化合物](#6-化合物)
7. [族炸](#7-族炸)
8. [比大小规则](#8-比大小规则)
9. [接牌规则](#9-接牌规则)
10. [游戏流程](#10-游戏流程)
11. [UI 页面说明](#11-ui-页面说明)
12. [文件结构](#12-文件结构)

---

## 1. 游戏概览

| 属性 | 值 |
|------|-----|
| 牌库 | 前三周期 18 种元素 × 6 张 = 108 张 |
| 玩家 | 3~8 人（1 人类 + N AI） |
| 初始手牌 | 每人 8 张 |
| 牌型 | 单质 / 化合物 / 族炸 |
| 出牌规则 | 必须比桌面牌更大（原子序数和 → 小 = 大） |
| 牌权轮转 | 出牌 → 接牌/过 → 总人数-1 连续过 → 牌权移交 → 新一轮 |
| 族炸特权 | 无视比大小，3 张族炸 > 2 张族炸 |

---

## 2. 牌库

### 元素分布

| 周期 | 元素 |
|------|------|
| 1 | H(氢 IA), He(氦 0) |
| 2 | Li(锂 IA), Be(铍 IIA), B(硼 IIIA), C(碳 IVA), N(氮 VA), O(氧 VIA), F(氟 VIIA), Ne(氖 0) |
| 3 | Na(钠 IA), Mg(镁 IIA), Al(铝 IIIA), Si(硅 IVA), P(磷 VA), S(硫 VIA), Cl(氯 VIIA), Ar(氩 0) |

---

## 3. 三种牌型

```
detect_pattern(cards, skip_clan_bomb=false) 判定优先级:
  1. 1 张 → 单质
  2. 2 张同元素 & H/N/O/F/Cl → 单质（双原子分子 X₂）
  3. 同族 ≥2 不同元素 & skip_clan_bomb=false → 族炸
  4. 化合价可配平 → 化合物
  5. 否则 → 非法
```

---

## 4. 牌权轮转规则

### 规则描述

**非族炸出牌流程**：

```
1. 游戏开始，一名玩家拥有牌权，自由出牌（桌面为空）。
   若出族炸 → 进入族炸接炸链；若是其他 → 进入步骤 2。

2. 下一名玩家（顺时针）选择：
   - 接牌：出更大的牌（同牌型或族炸）
   - 过：抽 1 张牌，标记 has_passed，回合结束

3. 继续步骤 2，直到出现总人数-1 名玩家连续选择过。

4. 此时，牌权交给最后一名选择过的玩家的下一名玩家。
   该玩家自由出牌（新一轮开始，桌面清空，所有玩家 pass 重置）。
```

**牌权轮转示例（4 人游戏）**：

```
玩家 1 → AI 2 → AI 3 → AI 4

回合 1: 玩家 1 自由出牌 [Na]（桌面 = Na）
回合 2: AI 2 接牌 [He]（桌面 = He，He 原子序数 2 < Na 原子序数 11 → 更大）
回合 3: AI 3 过（抽 1 张，标记 passed）
回合 4: AI 4 过（抽 1 张，标记 passed）
回合 5: 玩家 1 过（抽 1 张，标记 passed）
  → 总人数-1 = 3 人连续过 → 牌权交给 AI 2 的下一名玩家 = AI 3
  → 新一轮！AI 3 自由出牌（桌面清空，pass 重置）
```

### 实现

```gdscript
// GameManager.gd next_turn()
func next_turn() -> void:
	if clan_bomb_chain_active:
		_intercept_next(); return

	var unpassed = _get_unpassed_players()
	if unpassed.size() <= 1:
		_start_new_round(); return

	// 顺时针找下一个未 pass 的玩家
	var next_idx = current_player_index
	for _i in range(players.size()):
		next_idx = (next_idx + 1) % players.size()
		var p = players[next_idx]
		if p.get_hand_count() > 0 and not p.has_passed:
			current_player_index = next_idx; return

	_start_new_round()

// _start_new_round() — 牌权交给最后一名玩家的下一名玩家
func _start_new_round() -> void:
	table_cards.clear()
	is_round_starter = true
	_reset_all_passes()
	clan_bomb_chain_active = false

	// 顺时针前进 1 名玩家
	current_player_index = (current_player_index + 1) % players.size()
	for _i in range(players.size()):
		var p = players[current_player_index]
		if p.get_hand_count() > 0:
			return
		current_player_index = (current_player_index + 1) % players.size()
```

---

## 5. 单质

| 形式 | 牌数 | 条件 | 示例 |
|------|------|------|------|
| 单张元素 | 1 | 任意元素 | He, Na, C |
| 双原子分子 | 2 | 同元素且符号 ∈ {H, N, O, F, Cl} | H₂, O₂ |

**实现**：`DIATOMIC_SYMBOLS = ["H", "N", "O", "F", "Cl"]`

---

## 6. 化合物

### 规则

| 约束 | 说明 |
|------|------|
| 元素数量 | ≥2 种 |
| 2 元素 | GCD 最简比（rp = nv/g, rn = pv/g） |
| 3+ 元素 | 每种恰好 1 张 + 总电荷 = 0 |
| 金属优先 | 金属作为正价 |
| 比例校验 | play_cards 中 remove_cards 之前调用 ratio_ok |

### 玩家步骤

```
选牌 → "合成化合物" → 为每种元素选化合价 → 确认打出
  → 按 GCD 比例精确收集牌张 → play_cards(cards, custom_valences)
```

### 示例

| 手牌 | 比例 | 化学式 | 通过 |
|------|------|--------|------|
| Na + Cl | 1:1 | NaCl | ✅ |
| Al ×2 + O ×3 | 2:3 | Al₂O₃ | ✅ |
| Na ×2 + Cl ×2 | 1:1 (双倍) | - | ❌ |

---

## 7. 族炸

### 规则

| 条件 | 说明 |
|------|------|
| 元素 | ≥2 张不同元素，全部同族 |
| 等级 | 3 张 > 2 张 |
| 冷却 | 打出族炸后直到打出化合物前不能再出族炸 |
| 接炸 | 顺时针询问，接炸需出更大的族炸 |
| 牌权 | 无人接炸 → 最后一个出炸者自由出牌 |

### 接炸链流程

```
A 出族炸 → owner=A, chain_active=true
  → 顺时针询问 B（跳过 A）
	→ B 出更大的族炸 → owner=B, chain 继续
	→ B 跳过 → has_passed=true, 不抽牌, chain 继续
  → 所有非 owner 玩家均已 pass
	→ 桌面清空, owner 自由出牌（新一轮）
```

### 示例

| 手牌 | 族 | 类型 | 有效 |
|------|-----|------|------|
| H + Li | IA | 2 张族炸 | ✅ |
| He + Ne + Ar | 0 | 3 张族炸 | ✅ |
| H + H | IA | - | ❌ 需要不同元素 |

---

## 8. 比大小规则

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

原子序数和相同 → 比相对原子质量总和 → 质量大者牌更弱。

---

## 9. 接牌规则

```
桌面空 → 任意牌型（自由出牌）
桌面单质 → 更大的单质/族炸
桌面化合物 → 更大的化合物/族炸
  例外：溢出化合物（牌数 > 玩家数）→ 免疫
族炸 → 接炸链（只能出族炸）
```

---

## 10. 游戏流程

```
Start Page → 选择人数 → Start Game
  ↓
GameManager.init_game(total, ai)
  ├── 108 张牌洗牌 → 每人发 8 张
  └── is_round_starter = true

回合循环:
  _refresh_ui() → 圆形状态 + 桌面 + 手牌按钮
  人类操作 → step0 选牌 → step1 选牌型 → step2 化合价
  AI 操作 → _ai_try_play() → 候选遍历 play_cards()
  play_cards() → detect_pattern + 比大小 + 化合物比例校验
  牌权轮转 → next_turn() → 接牌/过 → 总人数-1 连续过 → 新一轮
  族炸 → 接炸链 → 无人接 → 出炸者自由出牌
  手牌 = 0 → GAME_OVER → End Page
```

---

## 11. UI 页面说明

| 页面 | 功能 |
|------|------|
| StartPage | 标题 + 总玩家人数 SpinBox(3–8) + AI 人数 SpinBox + 开始游戏 + 退出程序 |
| HelpPage | 游戏规则 + 牌型示例 + 接牌规则 + 返回 |
| GamePage | 游戏主界面（圆形状态/手牌/操作面板/日志/提示） |
| EndPage | 获胜者 + 返回主页 |

---

## 12. 文件结构

| 文件 | 角色 |
|------|------|
| `scripts/Utils.gd` | detect_pattern / get_compound_formula / compare_cards |
| `scripts/GameManager.gd` | play_cards / 牌权轮转 / 接炸链 / 冷却 / 溢出免疫 |
| `scripts/GameUI.gd` | 选牌 UI / 步骤流程 / AI 候选 / 着色 |
| `scripts/CardData.gd` | 卡牌属性 + 序列化 |
| `scripts/CardDatabase.gd` | 牌库生成 + Fisher-Yates 洗牌 |
| `Main.tscn` | 4 页场景布局 |

---

**文档版本**: 6.0  
**最后更新**: 2026-07-08
