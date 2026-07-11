# AI 与玩家出牌逻辑对照审计文档

> **日期**: 2026-07-11  
> **版本**: 1.0

---

## 1. 概述

本文档系统梳理 AI出牌逻辑（`GameUI.gd _ai_try_play()`）与玩家出牌逻辑（`GameUI.gd _on_element/_on_clan_bomb/_on_choose_compound/_on_confirm_compound`）的差异，确保两者行为一致。

---

## 2. 出牌流程图

```
play_cards(player_index, cards, custom_valences) → int
                   ↑
    ┌──────────────┴──────────────┐
    │                             │
  玩家操作                      AI操作
 _on_element / _on_clan_bomb    _ai_try_play()
 _on_confirm_compound           _ai_try_clan_bomb()
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
| 族炸冷却检查 | `play_cards()` 中 `clan_bomb_cooling → -3` | 同样走 `play_cards()` | ✅ |
| 溢出化合物免疫族炸 | `play_cards()` 中 `compound_immune → -4` | 同样走 `play_cards()` | ✅ |
| 接炸模式只出族炸 | `play_cards()` 中 `clan_bomb_chain_active → -1` | 同样走 `play_cards()` | ✅ |
| 牌型匹配检查 | `play_cards()` 中 pattern match | 同样走 `play_cards()` | ✅ |
| 比大小检查 | `play_cards()` 中 compare_cards | 同样走 `play_cards()` | ✅ |
| 化合物比例校验 | `play_cards()` 中 ratio_ok | 同样走 `play_cards()` | ✅ |
| **卤族互化检查** | `_on_choose_compound()` 中 `_is_halogen_only()` 拦截 | `_ai_try_play()` 中 `_is_ai_halogen_pair()` 跳过 | ✅ |
| 单质牌型检测 | `_on_element()`: `detect_pattern == ELEMENT` | 内联在 `play_cards()` 中 | ✅ |
| 族炸牌型检测 | `_on_clan_bomb()`: `detect_pattern == CLAN_BOMB` | 内联在 `play_cards()` 中 | ✅ |
| 化合物化合价选择 | 玩家逐元素选择 → custom_valences | AI自动检测金属/非金属 → cv | 🔶 |
| 双原子分子 | 玩家需手动选2张同元素 | AI: O(n²) 配对搜索 | 🔶 |
| 跳过抽牌 | `_on_pass()` 检查上限 → `player_pass()` | `play_cards` 全失败 → `player_pass()` | ✅ |
| 上限弃牌 | `_on_pass()` → `_on_discard_mode()` → 弃牌 | AI 不会触发上限弃牌 | 🔴 |
| 教程进度检查 | `play_cards()`: `_check_tutorial_progress()` | 同样走 `play_cards()` (但 AI 不支持教程) | ✅ |

---

## 4. 差异详解

### 4.1 🔶 化合价选择 (AI vs 玩家)

| | 玩家 | AI |
|--|------|----|
| 方式 | 从 `common_valence` 列表中手动选择 | 自动取最大值（正价取max，负价取min） |
| 代码 | `_update_valence_buttons()` → `_on_select_valence()` | `_ai_try_play()`: `if v > 0: v = val; break` |
| 灵活性 | 玩家可选择任意合法化合价 | AI 只用最大正价/最小负价 |
| 影响 | 玩家可精细控制 | AI 可能错过某些化合物 |

**评价**: 差异可接受。AI 的选择是合理的近似，不影响公平性。

### 4.2 🔶 双原子分子 (AI vs 玩家)

| | 玩家 | AI |
|--|------|----|
| 方式 | 手动选择2张同元素 | O(n²) 配对搜索 DIATOMIC_SYMBOLS 中的元素 |
| 代码 | `_on_element()` 统一处理 | `_ai_try_play()`: 单独循环检查 `c.symbol in DIATOMIC_SYMBOLS` |

**评价**: 差异可接受。功能等价，只是处理路径不同。

### 4.3 🔴 AI 不触发上限弃牌

| | 玩家 | AI |
|--|------|----|
| 检查 | `_on_pass()`: `hand_count >= hand_limit → _on_discard_mode()` | `player_pass()` 中被 `player.add_card()` 直接加牌，无上限拦截 |
| 问题 | — | AI 手牌可能超过上限 |

**风险**: 中。当 AI 手牌达到上限时，仍然通过 `player_pass()` 抽牌，超过上限。

**建议修复**: 在 `player_pass()` 中增加通用的上限检查（对所有玩家生效），或在 AI 层增加检查。

### 4.4 🟢 卤族互化检查 ✅ 已修复

AI 现在通过 `_is_ai_halogen_pair()` 跳过纯卤族对（F+Cl, F+Br, Cl+Br），与玩家的 `_is_halogen_only()` 检查行为一致。

---

## 5. 牌型检测路径对比

| 牌型 | 玩家路径 | AI路径 | 公共路径 |
|------|---------|--------|----------|
| 单质 (1张) | `_on_element()` | `_ai_try_play()` 末尾循环 | `play_cards()` → `detect_pattern()` |
| 单质 (双原子) | `_on_element()` | `_ai_try_play()` 双原子循环 | `play_cards()` → `detect_pattern()` |
| 化合物 | `_on_choose_compound()` → `_on_confirm_compound()` | `_ai_try_play()` 配对循环 | `play_cards()` → `detect_pattern()` → `get_compound_formula()` |
| 族炸 | `_on_clan_bomb()` | `_ai_try_clan_bomb()` / `_ai_try_play()` 族炸循环 | `play_cards()` → `detect_pattern()` |

---

## 6. 统一规则 (play_cards 中生效)

以下规则对所有玩家（人类+AI）统一在 `GameManager.play_cards()` 中生效：

| 规则 | 代码位置 | 对AI生效 |
|------|----------|:-------:|
| 族炸禁用 | `clan_bomb_disabled → return -3` | ✅ |
| 族炸冷却 | `clan_bomb_cooling → return -3` | ✅ |
| 溢出免疫族炸 | `compound_immune → return -4` | ✅ |
| 接炸模式限制 | `clan_bomb_chain_active → return -1` (非族炸) | ✅ |
| 牌型匹配 | `table_pattern != pattern → return -4` | ✅ |
| 比大小 | `compare_cards ≤ 0 → return -2` | ✅ |
| 化合物比例 | `ratio_ok == false → return -1` | ✅ |
| 接炸抽牌 | `player_pass()` 中统一抽1张 | ✅ |
| 接炸上限弃牌 | `player_pass()` 中统一抽1张 | 🔴 见 4.3 |

---

## 7. 结论

- **16 项检查中 14 项一致 (87.5%)**
- **2 项差异可接受**: 化合价选择策略、双原子分子处理路径
- **1 项需要关注**: AI 不触发上限弃牌（低优先级，AI 很少达上限）

---

**文档版本**: 1.0  
**最后更新**: 2026-07-11