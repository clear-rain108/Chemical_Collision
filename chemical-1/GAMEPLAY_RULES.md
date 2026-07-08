# 化学碰撞 — 玩法规则与程序实现文档

> **版本**: 5.0  
> **日期**: 2026-07-07  
> **引擎**: Godot 4.x / GDScript

---

## 目录

1. [游戏概览](#1-游戏概览)
2. [牌库](#2-牌库)
3. [三种牌型](#3-三种牌型)
4. [单质](#4-单质)
5. [化合物 — 多元素支持](#5-化合物--多元素支持)
6. [族炸](#6-族炸)
7. [比大小规则](#7-比大小规则)
8. [接牌规则](#8-接牌规则)
9. [游戏流程](#9-游戏流程)
10. [UI 页面说明](#10-ui-页面说明)
11. [文件结构](#11-文件结构)

---

## 1. 游戏概览

| 属性 | 值 |
|------|-----|
| 牌库 | 前三周期 18 种元素 × 6 张 = 108 张 |
| 玩家 | 3~6 人（1 人类 + N AI） |
| 初始手牌 | 每人 8 张 |
| 牌型 | 单质 / 化合物 / 族炸 |
| 出牌规则 | 必须比桌面牌**更大**（原子序数和 → 小 = 大） |
| 族炸特权 | 无视比大小，3 张族炸 > 2 张族炸 |

---

## 2. 牌库

### 元素分布

| 周期 | 元素 |
|------|------|
| 1 | H(氢 IA), He(氦 0) |
| 2 | Li(锂 IA), Be(铍 IIA), B(硼 IIIA), C(碳 IVA), N(氮 VA), O(氧 VIA), F(氟 VIIA), Ne(氖 0) |
| 3 | Na(钠 IA), Mg(镁 IIA), Al(铝 IIIA), Si(硅 IVA), P(磷 VA), S(硫 VIA), Cl(氯 VIIA), Ar(氩 0) |

### 卡牌属性

| 属性 | 说明 | 用于 |
|------|------|------|
| `symbol` | 元素符号 | 显示 |
| `name_cn` | 中文名 | 手牌显示 |
| `name_en` | 英文名 | tooltip |
| `atomic_number` | 原子序数 | **比大小** |
| `atomic_weight` | 相对原子质量 | **tiebreak** |
| `group` | 所属族 | **族炸判定** |
| `element_type` | 金属/非金属/准金属/稀有气体 | **正负价选择 + 着色** |
| `common_valence` | 化合价列表 | **化合物配平** |

---

## 3. 三种牌型

```
detect_pattern(cards, skip_clan_bomb=false) 判定优先级:
  1. 1 张牌 → ELEMENT（单质）
  2. 2 张同元素 & H/N/O/F/Cl → ELEMENT（双原子分子 X₂）
  3. 同族且 ≥2 种不同元素 且 skip_clan_bomb=false → CLAN_BOMB
  4. 化合价可配平 → COMPOUND（化合物）
  5. 否则 → 非法 (-1)
```

> `skip_clan_bomb` 标志：当玩家/系统明确选择"化合物"路径时设为 true

---

## 4. 单质

| 形式 | 牌数 | 条件 | 示例 |
|------|------|------|------|
| 单张元素 | 1 | 任意元素 | `He`, `Na`, `C` |
| 双原子分子 | 2 | 相同元素且符号 ∈ {H, N, O, F, Cl} | `H₂`, `N₂`, `O₂`, `F₂`, `Cl₂` |

### 实现

```gdscript
// Utils.gd
const DIATOMIC_SYMBOLS = ["H", "N", "O", "F", "Cl"]

func get_element_display(cards):
	if cards.size() == 1: return cards[0].symbol
	if cards.size() == 2: return cards[0].symbol + _to_subscript(2)  // "H₂"
```

---

## 5. 化合物 — 多元素支持

### 5.1 规则

| 约束 | 说明 |
|------|------|
| 元素数量 | ≥2 种（无上限） |
| 化合价 | 存在正价元素 + 负价元素 |
| 稀有气体 | **不能**参与（He/Ne/Ar 化合价=0） |
| 2 元素化合物 | GCD 最简比验证（化合价之比的倒数） |
| 3+ 元素化合物 | 每种恰好 1 张，总电荷 = 0 |
| 金属优先 | 金属作为正价（阳离子） |

### 5.2 玩家步骤

```
选牌(step0) → 点击"出牌(选牌型)"
  → "合成化合物"(step1→step2)
	→ 为每种选中元素选择化合价
	→ "确认打出"
	  → 按 GCD 比例精确收集牌张
	  → play_cards(cards, custom_valences)
```

### 5.3 程序实现

```gdscript
// Utils.gd get_compound_formula(cards, custom_valences)
// 多元素版本 — 任意数量元素的电荷平衡验证
//
// custom_valences = {Na:1, Cl:-1, O:-2, H:1, ...}
//
// 2 元素：GCD 最简比 + ratio_ok
// 3+ 元素：每种元素出现次数 → charge = Σ count×valence
//   ratio_ok = (total_pos == total_neg && total_pos > 0)
//
// 公式：正价元素在前 → 下标 → 负价元素在后 → 下标
```

### 5.4 在 play_cards 中的比例校验（最关键的安全网）

```gdscript
// GameManager.gd 第 148-152 行
// 在 remove_cards 之前校验
if pattern == CardPattern.COMPOUND:
	var fi = UtilsScript.get_compound_formula(cards, custom_valences)
	if not fi.is_empty() and not fi.get("ratio_ok", false):
		return -1  // 比例不匹配 → 拒绝出牌，卡牌不动
```

### 5.5 精确牌张收集（GameUI.gd _on_confirm_compound）

```gdscript
// 2 元素化合物：GCD 计算 na=nb
//   遍历选中牌，按精确数量收集每种元素的牌
//   只收集 na + nb 张牌 → 多余牌留回手牌

// 3+ 元素：每种恰好 1 张 + 总电荷 = 0
//   否则返回错误
```

### 5.6 示例表

| 手牌选择 | 化合价 | 比例 | 化学式 | 通过 |
|---------|--------|------|--------|------|
| Na + Cl | Na(+1), Cl(-1) | 1:1 | NaCl | ✅ |
| Al + Al + O + O + O | Al(+3), O(-2) | 2:3 | Al₂O₃ | ✅ |
| Na + Na + Cl + Cl | Na(+1), Cl(-1) | 1:1 (actual≠) | - | ❌ |
| He + anything | - | - | - | ❌ |

---

## 6. 族炸

### 6.1 规则

| 条件 | 说明 |
|------|------|
| 元素 | ≥2 张**不同**元素 |
| 族 | 全部属于**同一族** |
| 等级 | **3 张族炸 > 2 张族炸**（不论族序数） |
| 冷却 | 打出族炸后 **直到打出化合物前**不能再出族炸 |
| 接炸 | 族炸后顺时针询问其他玩家接炸（需出更大的族炸） |
| 牌权 | 无人接炸 → 最后一个出炸者自由出牌 |

### 6.2 接炸链流程

```
玩家 A 出族炸 → owner=A, chain_active=true
  → 顺时针询问 B（跳过 A）
	→ B 出更大的族炸 → owner=B, chain 继续
	→ B 跳过 → 不抽牌，chain 继续
  → 所有非 owner 玩家都已 pass
	→ 桌面清空，owner 自由出牌（新一轮）
```

---

## 7. 比大小规则

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

## 8. 接牌规则

```
自由出牌（桌面空）→ 任意牌型可出
桌面是单质 → 只能出更大的单质/族炸
桌面是化合物 → 只能出更大的化合物/族炸
  例外：溢出化合物（牌数 > 玩家数）→ 免疫！只能出族炸
族炸 → 进入接炸链（只能出族炸）
```

---

## 9. 游戏流程

```
Start Page → Start Game
  ↓
GameManager.init_game(4, 3)
  ├── CardDatabase: 18 种 × 6 = 108 张 → 洗牌
  ├── 创建 4 个 PlayerInfo (1 人类 + 3 AI)
  └── 每人发 8 张牌 → is_round_starter=true

回合循环:
  人类出牌: 选牌 → 选牌型 → play_cards() → 结果
  AI 出牌: 1.5s 延迟 → 候选 → play_cards() → Pass 如果全失败
  族炸接炸: 族炸 → 接炸链 → 无人接 → 出击者自由出牌
  Pass: 跳过 → 抽 1 张 → next_turn()
  胜利: hand.count == 0 → GAME_OVER → End Page
```

---

## 10. UI 页面说明

| 页面 | 功能 |
|------|------|
| StartPage | 标题 + Start Game 按钮 |
| GamePage | 完整游戏界面（状态/手牌/日志/操作面板/Help 按钮） |
| HelpPage | 牌型示例 + 接牌规则 + 接炸规则详细说明 |
| EndPage | 获胜者显示 + Return 按钮回到开始页 |

---

## 11. 文件结构

| 文件 | 角色 |
|------|------|
| `scripts/Utils.gd` | detect_pattern / get_compound_formula / compare_cards |
| `scripts/GameManager.gd` | play_cards / 接炸链 / 冷却 / 溢出免疫 |
| `scripts/GameUI.gd` | 选牌 UI / 步骤流程 / AI 候选 / 多元素确认 |
| `scripts/CardData.gd` | 卡牌属性常量 + 序列化 |
| `scripts/CardDatabase.gd` | 牌库生成 + Fisher-Yates 洗牌 |
| `Main.tscn` | 场景布局 / 4 页面结构 |

---

**文档版本**: 5.0  
**最后更新**: 2026-07-07  
**当前状态**: 全功能完成 ✅
