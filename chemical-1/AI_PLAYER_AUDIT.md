# AI 与玩家出牌逻辑对照审计文档

> **日期**: 2026-07-11（初版） / 2026-11-04（v1.2 复核：化合价统一、上限弃牌已实现、假化合物拦截）  
> **版本**: 1.2

---

## 1. 概述

本文档系统梳理 AI出牌逻辑（`AIPlayer.gd _try_play()`）与玩家出牌逻辑（`GameUI.gd _on_element/_on_clan_bomb/_on_choose_compound/_on_confirm_compound`）的差异，确保两者行为一致。

---

## 2. 出牌流程图

```
play_cards(player_index, cards, custom_valences) → int
                   ↑
    ┌──────────────┴──────────────┐
    │                             │
  玩家操作                      AI操作
 _on_element / _on_clan_bomb    AIPlayer._try_play()
 _on_confirm_compound           AIPlayer._try_clan_bomb()
    │                             │
    ├─ 牌型校验                   ├─ 族炸尝试
    ├─ 卤族互化检查               ├─ 化合物配对
    ├─ 化合价选择                 ├─ 双原子分子
    └─ play_cards()              └─ 单质 → pass
         │
    GameManager.play_cards()
    ├─ detect_pattern()
    ├─ 族炸判定 (冷却/免疫)
    ├─ 牌型匹配
    ├─ 比大小
    ├─ 化合物比例校验
    ├─ remove_cards
    ├─ 教程检查
    └─ next_turn()
```

---

## 3. 逐项对照表

| 检查项 | 玩家逻辑 | AI逻辑 | 一致? |
|--------|---------|--------|:----:|
| 族炸禁用检查 | `play_cards()` 中 `clan_bomb_disabled → -3` | 同样走 `play_cards()` | ✅ |
| 族炸冷却检查 | `play_cards()` 中 `clan_bomb_cooling → -3`（**优先于接炸链**，链中同样拦截） | 同样走 `play_cards()` | ✅ |
| 溢出化合物免疫族炸 | `play_cards()` 中 `compound_immune → -4` | 同样走 `play_cards()` | ✅ |
| 接炸模式只出族炸 | `play_cards()` 中 `clan_bomb_chain_active → -1` | 同样走 `play_cards()` | ✅ |
| 牌型匹配检查 | `play_cards()` 中 pattern match | 同样走 `play_cards()` | ✅ |
| 比大小检查 | `play_cards()` 中 compare_cards | 同样走 `play_cards()` | ✅ |
| 化合物比例校验 | `play_cards()` 中 ratio_ok | 同样走 `play_cards()` | ✅ |
| **卤族互化检查** | `play_cards()`: `pattern==COMPOUND && !halogen_exchange_allowed && is_halogen_mix → -7`（`_on_choose_compound()` 另有预检，只为提前提示） | 同样走 `play_cards()`；AI 侧 `_is_ai_halogen_pair()` 只是少做无用尝试 | ✅ |
| 单质牌型检测 | `_on_element()`: `detect_pattern == ELEMENT` | 内联在 `play_cards()` 中 | ✅ |
| 族炸牌型检测 | `_on_clan_bomb()`: `detect_pattern == CLAN_BOMB` | 内联在 `play_cards()` 中 | ✅ |
| 化合物化合价选择 | 玩家逐元素选择 → custom_valences（候选价 = `card.common_valence` 全价） | AI 调 `get_valence_pairs()` 取默认解，不自算 | ✅ |
| 双原子分子 | 玩家需手动选2张同元素 | AI: O(n²) 配对搜索 | 🔶 |
| 跳过抽牌 | `_on_pass()` 检查上限 → `player_pass()` | `play_cards` 全失败 → `player_pass()` | ✅ |
| 上限弃牌 | `_on_pass()` → `_on_discard_mode()` → 弃牌 | `player_pass()` 内 AI 达上限自动弃 1 张（`_ai_pick_discard`） | ✅ |
| 教程进度检查 | `play_cards()`: `_check_tutorial_progress()` | 同样走 `play_cards()` (但 AI 不支持教程) | ✅ |

---

## 4. 差异详解

### 4.1 ✅ 化合价选择（已统一到唯一出口）

| | 玩家 | AI |
|--|------|----|
| 方式 | 化合价面板列出每张牌 `common_valence` 的全部价，玩家点选 | 直接取 `get_valence_pairs()` 的默认解 |
| 代码 | `_update_valence_buttons()` → `_on_select_valence()`（候选 = `card.common_valence`） | `AIPlayer._try_play()` 调 `get_valence_pairs()`（旧「正价取 max / 负价取 min」已删除） |
| 灵活性 | 可在多个合法解之间改选（例：Fe 1 张 + Cl 2 张，选 Fe(+2) 才能成立） | 只取默认解（金属优先取最高价） |
| 影响 | 面板是超集，选到 `NCl` 这类组合会被引擎 `-1` 拒绝 | AI 会错过「低价金属」写法，但不会提出非法组合 |

**评价**: 裁决仍在同一处 —— `play_cards()` 的 `_assign_valences(cards, cv)`（`ratio_ok == false` 即 `-1`）。
面板 / AI / 提示给的价都要过它，因此不存在「哪条路径绕开引擎」的问题；
差异只是 AI 用 `get_valence_pairs()` 收敛了候选域（不会枚举低价金属），玩家则可手选。
回归：`tests/verify_compound_chemistry.gd`。

### 4.2 🔶 双原子分子 (AI vs 玩家)

| | 玩家 | AI |
|--|------|----|
| 方式 | 手动选择2张同元素 | O(n²) 配对搜索 DIATOMIC_SYMBOLS 中的元素 |
| 代码 | `_on_element()` 统一处理 | `AIPlayer._try_play()`: 单独循环检查 `c.symbol in DIATOMIC_SYMBOLS` |

**评价**: 差异可接受。功能等价，只是处理路径不同。

### 4.3 🟢 AI 上限弃牌 ✅ 已修复

| | 玩家 | AI |
|--|------|----|
| 检查 | `_on_pass()`: `hand_count >= hand_limit → _on_discard_mode()` | `GameManager.player_pass()` 内统一判定 |
| 现状 | 弹「弃牌模式」，手动选 1 张后 `player_discard_and_pass()` | 达上限时 `_ai_pick_discard()` 自动挑 1 张弃掉再抽 |
| 一致性 | — | ✅ 与人类共用同一条 `player_pass()` 上限分支 |

**说明**: 旧审计认为「AI 手牌会超过上限」，实际入口已收进 `player_pass()`，
人类只多一层 UI 选择（弃哪张），规则判定完全一致。回归：`tests/verify_ai_discard.gd`。

### 4.4 🟢 卤族互化检查 ✅ 已统一到引擎

旧实现是两处**局部补丁**（`GameUI._is_halogen_only()` + `AIPlayer._is_ai_halogen_pair()`），
「提示」按钮和族炸路径都没被覆盖，导致 F+Cl 能以化合物形式打出。

现在规则只写在一个地方：`GameManager.play_cards()` 在 `pattern == COMPOUND` 且
`halogen_exchange_allowed == false` 时用 `is_halogen_mix(cards)` 判定并返回 `-7`。
人类 / AI / 提示三条路径共用；F+Cl 作为**族炸**始终合法（B 方案）。
开始页勾选「允许卤族互化」后放行，AI 也能通过 `_pair_valences()` 合成 ClF。

回归：`tests/verify_halogen.gd`。

### 4.5 🟢 假化合物拦截 ✅ 已统一到引擎（2026-11-04）

旧实现里 `get_compound_formula()` 遇到「找不到一正一负」的组合会给出空式子，
但 `play_cards()` 仍有放行路径，于是 AI 偶尔能打出 `NCl` / `BrN` / `IN` 这类不存在的化合物。

现在：

| 规则 | 位置 | 结果 |
|---|---|---|
| 式子为空 或 `ratio_ok == false` | `GameManager.play_cards()` | 一律 `-1`（已删除永假分支） |
| 唯一价态裁决 | `GameManager.play_cards()` → `CompoundSolver._assign_valences(cards, cv)` | 面板 / AI / 提示给的价都过这一处 |
| 电负性有序 | `_assign_valences()` | 正价元素的电负性必须 ≤ 负价元素，倒置即拒绝 |
| 搜索兜底 | `_search_valences()` | 2~3 种元素按实际张数做电荷平衡 DFS |

保留 / 排除对照：

| 组合 | 判定 | 说明 |
|---|---|---|
| NCl / BrN / IN | ❌ | 1:1 凑不出 0 电荷（N 价域只有 -3/+3/+5，卤素 -1/+1/+5/+7） |
| NCl₃ | ✅ | N(+3) + 3×Cl(-1)（N 3.04 ≤ Cl 3.16） |
| NI₃ | ✅ | N(-3) + 3×I(+1)（I 2.66 ≤ N 3.04） |
| BCl₃ | ✅ | B(+3) + 3×Cl(-1) |
| ClF | ✅ | 卤族互化开启后 Cl(+1) + F(-1) |

回归：`tests/verify_compound_chemistry.gd`（38 项，含 Fe(+2)+2Cl(-1) / Fe(+3) 用例）。

---

## 5. 牌型检测路径对比

| 牌型 | 玩家路径 | AI路径 | 公共路径 |
|------|---------|--------|----------|
| 单质 (1张) | `_on_element()` | `AIPlayer._try_play()` 末尾循环 | `play_cards()` → `detect_pattern()` |
| 单质 (双原子) | `_on_element()` | `AIPlayer._try_play()` 双原子循环 | `play_cards()` → `detect_pattern()` |
| 化合物 | `_on_choose_compound()` → `_on_confirm_compound()` | `AIPlayer._try_play()` 配对循环 | `play_cards()` → `detect_pattern()` → `get_compound_formula()` |
| 族炸 | `_on_clan_bomb()` | `AIPlayer._try_clan_bomb()` / `AIPlayer._try_play()` 族炸循环 | `play_cards()` → `detect_pattern()` |

---

## 6. 统一规则 (play_cards 中生效)

以下规则对所有玩家（人类+AI）统一在 `GameManager.play_cards()` 中生效：

| 规则 | 代码位置 | 对AI生效 |
|------|----------|:-------:|
| 族炸禁用 | `clan_bomb_disabled → return -3` | ✅ |
| 族炸冷却 | `clan_bomb_cooling → return -3`（先于接炸链判定，链中不放行） | ✅ |
| 溢出免疫族炸 | `compound_immune → return -4` | ✅ |
| 接炸模式限制 | `clan_bomb_chain_active → return -1` (非族炸) | ✅ |
| 牌型匹配 | `table_pattern != pattern → return -4` | ✅ |
| 比大小 | `compare_cards ≤ 0 → return -2` | ✅ |
| 化合物比例 | `ratio_ok == false → return -1` | ✅ |
| 化合物式子为空 | `formula == "" → return -1`（假化合物拦截） | ✅ |
| 顺序约束 | `sequence_constraint_active && idx == sequence_constraint_target && pattern 不符 → return -6` | ✅ |
| 卤族互化 | `pattern==COMPOUND && !halogen_exchange_allowed && is_halogen_mix → return -7` | ✅ |
| 接炸抽牌 | `player_pass()` 中统一抽1张 | ✅ |
| 接炸上限弃牌 | `player_pass()` 中统一抽1张 | 🔴 见 4.3 |

---

## 7. 结论

- **§3 逐项对照 15 项中 14 项一致**，唯一 🔶 是「双原子分子处理路径」：
  玩家手动选两张同元素，AI 用 `DIATOMIC_SYMBOLS` 做配对搜索 —— 功能等价，仅路径不同。
- **历史差异已全部收敛**：
  - 化合价选择 → AI / 提示统一用 `CompoundSolver.get_valence_pairs()` 取价，
    人类面板列 `common_valence` 全价，三者最终都由 `play_cards → _assign_valences` 裁决
  - AI 上限弃牌 → `player_pass()` 内自动弃 1 张（回归 `tests/verify_ai_discard.gd`）
  - 假化合物 → 空式子 / `ratio_ok == false` 一律 `-1`（回归 `tests/verify_compound_chemistry.gd`）
- **顺序约束**：`play_cards()` 只在 `idx == sequence_constraint_target` 时校验，
  人类与 AI 走同一判定，别人出牌 / 跳过 / 族炸都不会解除（回归 `tests/verify_sequence_lock.gd`）。

---

**文档版本**: 1.2  
**最后更新**: 2026-11-04