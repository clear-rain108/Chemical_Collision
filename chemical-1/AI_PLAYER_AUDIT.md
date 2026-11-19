# AI 与玩家出牌逻辑对照审计文档

> **版本**: 2.0（2026-11-18 重写）
> **历史**: v1.0 2026-07-11 初版 / v1.2 2026-11-04 复核（化合价统一、上限弃牌、假化合物拦截）
>
> **v2.0 为什么重写**：旧文全部围绕 `AIPlayer._try_play()` —— 这个方法在联机改造
> （P11-C1-c Step 2）时已经被拆成 `plan()` + `_execute_local()`，入口、返回值、调用链全变了。
> 现在本文按**当前代码**写：AI 先产出只读「意图」，再落子或交给主机广播。

---

## 1. 概述

出牌合法性**只有一处真源**：`GameManager.play_cards()`（底层 `_evaluate_play()`，
只读孪生是 `validate_play()`）。人类、AI、提示三条路径的差别只在「怎么凑出这一手」，
判不判得过永远由引擎说了算。

| 角色 | 入口 | 说明 |
|---|---|---|
| 人类 | `scripts/game/GameFlow.gd` → `_ui._router()` → `net/ActionRouter.gd` | 单机直接调 `GameManager`；联机把动作发成 intent，等主机裁决后广播 |
| AI（单机） | `AIPlayer.auto_play(gm, refresh)` = `plan()` + `_execute_local()` | 逐字复刻改造前的写路径（`play_cards` / `player_pass`），**不写** `event_log`。**驱动方是 UI**：`HandView._update_ai_schedule()` 起 1.5s 定时器 → `GameFlow._ai_auto_play()`，按「回合号 + 行动者」双键令牌「一手只排一次」 |
| AI（联机） | 主机 `NetSession.host_step_ai()` → `make_intent → _validate_for_seat → _host_apply` | 与人类 intent 同一条裁决链；客人重放同一笔事件，局面逐笔对齐 |
| 提示 | `HintAdvisor.suggest()`（全静态、只读） | 每个候选都过 `validate_play()`，「说能打、点了被拒」结构上不可能 |

**为什么 AI 先出「计划」再落子**：`plan()` 只读，返回一笔 `{"type": ...}` 意图。
主机必须把 AI 的动作变成**可广播的事件**；直接落子在联机里等于「主机自己改局面」，
客人重放不出来 → 立刻分叉。

```
              GameManager.play_cards(player_index, cards, custom_valences)   ← 唯一裁决
                                   ↑
     ┌─────────────────────────────┼─────────────────────────────┐
   人类                        AI（单机）                    AI（联机，主机代打）
GameFlow._on_*              AIPlayer.plan()                NetSession.host_step_ai()
 → ActionRouter                （只读意图）                   → make_intent
 → play_cards / pass_turn    → _execute_local()              → _validate_for_seat
                             → play_cards / player_pass      → _host_apply → 广播
```

---

## 2. AI 的计划类型（`AIPlayer.plan(game_manager, seat)`）

| type | payload | 单机落点（`_execute_local`） | 备注 |
|---|---|---|---|
| `play` | `uids` / `valences` / `pattern` | `play_cards(idx, cards, cv, pattern)` | 返回 `1`（顺序牌）时额外清顺序约束 + `next_turn()`，与改造前逐字一致 |
| `pass` | — | `player_pass(idx)` | 达手牌上限时由 `player_pass()` 自动弃 1 张（`_ai_pick_discard`） |
| `sequence_skip` | — | 清顺序约束 + `next_turn()` | 桌面是顺序且手上接不上 |
| `sequence_pick` | `pattern` | `set_sequence_constraint(pattern)` | AI 反制顺序 |
| `{}` | — | 什么都不做 | 无对局 / 座位非法 / 不是 AI / 已结束 / 手牌为空 |

`plan()` 内部只做分派，所有 `_plan_*` 都是纯读（不改手牌 / 桌面 / 轮转 / rng / 日志）：

```
plan(gm, seat)
├─ 第0关（tutorial_level == 0 且 phase >= 1）→ _plan_level0()   # 刻意放水：每回合 1 张单质
├─ 族炸链中（clan_bomb_chain_active）→ 冷却则 pass / 否则 _plan_clan_bomb()
└─ 常规 _plan_regular()
   ├─ 桌面是顺序 → _find_sequence() 接顺序（不主动出顺序）
   ├─ 族炸：_group_by_group() 同族 ≥2 张
   ├─ 化合物：O(n²) 配对 + _pair_valences()（= CompoundSolver.get_valence_pairs）
   ├─ 多分子化合物（L4a / AI_RATIO_COMPOUND）：_ratio_cards() 按最简比凑牌
   ├─ 双原子分子：DIATOMIC_SYMBOLS 配对
   ├─ 单质：任意 1 张
   └─ 全败 → pass
```

---

## 3. 逐项对照表

| 检查项 | 玩家逻辑 | AI 逻辑 | 一致? |
|---|---|:---:|:---:|
| 族炸禁用检查 | `play_cards()`：`clan_bomb_disabled → -3` | 同样走 `play_cards()` | ✅ |
| 族炸冷却检查 | `play_cards()`：`clan_bomb_cooling → -3`（优先于接炸链） | 同样走 `play_cards()`；`plan()` 里也会先跳过 | ✅ |
| 溢出化合物免疫族炸 | `play_cards()`：`compound_immune → -4` | 同样走 `play_cards()` | ✅ |
| 接炸模式只出族炸 | `play_cards()`：`clan_bomb_chain_active → -1` | `plan()` 在链中只产出族炸 / pass | ✅ |
| 牌型匹配检查 | `play_cards()`：`table_pattern != pattern → -4` | 同样走 `play_cards()` | ✅ |
| 比大小检查 | `play_cards()`：`compare_cards ≤ 0 → -2` | 同样走 `play_cards()` | ✅ |
| 化合物比例校验 | `play_cards()`：`ratio_ok == false → -1` | 同样走 `play_cards()` | ✅ |
| 卤族互化检查 | `play_cards()`：`COMPOUND && !halogen_exchange_allowed && is_halogen_mix → -7`（`ActionPanel` 另有预检，只为止住点击） | 同样走 `play_cards()`；`_plan_regular()` 里少做无用尝试 | ✅ |
| 单质牌型检测 | `GameFlow._on_element()`：`detect_pattern == ELEMENT` 才发 | `_plan_play([c], {}, -1)`，引擎再定牌型 | ✅ |
| 族炸牌型检测 | `GameFlow._on_clan_bomb()`：`detect_pattern == CLAN_BOMB` 才发 | `_plan_clan_bomb()` → `_plan_play(..., CLAN_BOMB)` | ✅ |
| 顺序牌 | `GameFlow._on_sequence()` / `ActionPanel` 的「按序」按钮 | `_find_sequence()` + `sequence_pick` / 接顺序 | ✅ |
| 化合物化合价 | 面板逐元素选 → `custom_valences`（候选 = `card.common_valence` 全价） | `get_valence_pairs()` 默认解，不自算 | ✅（AI 覆盖更窄，见 §4.1） |
| 双原子分子 | 手动选 2 张同元素 | `DIATOMIC_SYMBOLS` 配对搜索 | 🔶（路径不同，功能等价） |
| 跳过 / 上限弃牌 | `_on_pass()`：达上限 → `step_mode = 3` 手动选 1 张弃 | `_plan_pass()` → `player_pass()` 内自动弃 1 张 | ✅（人类只多一步「弃哪张」） |
| 教程进度检查 | `play_cards()`：`_check_tutorial_progress()` | 同样走 `play_cards()`（第零关由 `_plan_level0()` 放水） | ✅ |
| 联机裁决 | 客人 `ActionRouter` 发 intent，等主机裁决 | 主机 `host_step_ai()` 走同一条 `make_intent → 裁决 → 广播` | ✅ |

---

## 4. 差异详解

### 4.1 ✅ 化合价选择（已统一到唯一出口）

| | 玩家 | AI |
|--|------|----|
| 方式 | 化合价面板列出每张牌 `common_valence` 的全部价，玩家点选 | 直接取 `get_valence_pairs()` 的默认解 |
| 代码 | `HandView._update_valence_buttons()` → `GameFlow._play_selected_compound(cv)` | `AIPlayer._plan_regular()` → `_pair_valences()`（旧「正价取 max / 负价取 min」已删） |
| 灵活性 | 可在多个合法解之间改选（例：Fe 1 张 + Cl 2 张，选 Fe(+2) 才能成立） | 只取默认解（金属优先取最高价） |
| 影响 | 面板是超集，选到 `NCl` 这类组合会被引擎 `-1` 拒绝 | AI 会错过「低价金属」写法，但不会提出非法组合 |

**评价**：裁决仍在同一处 —— `play_cards()` 的 `_assign_valences(cards, cv)`（`ratio_ok == false` 即 `-1`）。
面板 / AI / 提示给的价都要过它，因此不存在「哪条路径绕开引擎」的问题；
差异只是 AI 用 `get_valence_pairs()` 收敛了候选域（不会枚举低价金属），玩家则可手选。
回归：`tests/verify_compound_chemistry.gd`。

### 4.2 🔶 双原子分子（AI vs 玩家）

| | 玩家 | AI |
|--|------|----|
| 方式 | 手动选择 2 张同元素 | O(n²) 配对搜索 `DIATOMIC_SYMBOLS` 中的元素 |
| 代码 | `GameFlow._on_element()` 统一处理 | `_plan_regular()` 里单独循环：`c.symbol in DIATOMIC_SYMBOLS` |

**评价**：差异可接受。功能等价，只是处理路径不同；最终仍走
`play_cards() → detect_pattern()`。

### 4.3 🟢 AI 上限弃牌 ✅ 走同一条 `player_pass()`

| | 玩家 | AI |
|--|------|----|
| 检查 | `GameFlow._on_pass()`：`hand_count >= hand_limit → step_mode = 3`（弃牌模式） | `GameManager.player_pass()` 内统一判定 |
| 现状 | 弹「请选择 1 张牌弃置」，选完 `discard_and_pass(card)` | 达上限时 `_ai_pick_discard()` 自动挑 1 张弃掉再抽 |
| 一致性 | — | ✅ 与人类共用同一条 `player_pass()` 上限分支 |

回归：`tests/verify_ai_discard.gd`。

### 4.4 🟢 卤族互化检查 ✅ 已统一到引擎

旧实现是两处**局部补丁**（`GameUI._is_halogen_only()` + `AIPlayer._is_ai_halogen_pair()`），
「提示」按钮和族炸路径都没被覆盖，导致 F+Cl 能以化合物形式打出。

现在规则只写在一个地方：`GameManager.play_cards()` 在 `pattern == COMPOUND` 且
`halogen_exchange_allowed == false` 时用 `is_halogen_mix(cards)` 判定并返回 `-7`。
人类 / AI / 提示三条路径共用；F+Cl 作为**族炸**始终合法（B 方案）。
开始页勾选「允许卤族互化」后放行，AI 也能通过 `_pair_valences()` 合成 ClF。

`GameFlow._is_halogen_only()`（UI 侧预检）只为「合成化合物」按钮提前挡住，判据与引擎一致；
`AIPlayer._is_ai_halogen_pair()` 现在只用于「少做一次注定失败的尝试」。回归：`tests/verify_halogen.gd`。

### 4.5 🟢 假化合物拦截 ✅ 已统一到引擎

旧实现里 `get_compound_formula()` 遇到「找不到一正一负」的组合会给出空式子，
但 `play_cards()` 仍有放行路径，于是 AI 偶尔能打出 `NCl` / `BrN` / `IN` 这类不存在的化合物。

现在：

| 规则 | 位置 | 结果 |
|---|---|---|
| 式子为空 或 `ratio_ok == false` | `GameManager.play_cards()` | 一律 `-1`（永假分支已删） |
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

回归：`tests/verify_compound_chemistry.gd`。

### 4.6 🟡 AI 覆盖范围（已知，非 bug）

| 牌型 | 人类 | AI | 说明 |
|---|---|---|---|
| 2 元素化合物 | ✅ | ✅ | 含多分子（2Na+2Br → 2NaBr） |
| 混合价态（Fe₃O₄ = 3Fe+4O） | ✅ | ❌ | 面板顶部「混合价态自动配平」按钮；AI 不做逐张价态猜测 |
| 3+ 元素化合物（H₂SO₄） | ✅ | ❌ | `_search_valences()` 支持 2~3 种元素；AI 只枚举 2 元素配对 |
| 顺序牌 | ✅ | ✅ | AI 只在桌面已是顺序时接，不主动出 |

结论：AI 是人类的**子集**，不会提出引擎拒绝的组合（`verify_ai_plan.gd` 的「计划复核」段
对每个计划都跑 `validate_play()` 断言 ≥ 0）。

---

## 5. 牌型检测路径对比

| 牌型 | 玩家路径 | AI 路径 | 公共路径 |
|---|---|---|---|
| 单质（1 张） | `GameFlow._on_element()` | `_plan_regular()` 末尾单张循环 | `play_cards()` → `detect_pattern()` |
| 单质（双原子） | `GameFlow._on_element()` | `_plan_regular()` 的 `DIATOMIC_SYMBOLS` 配对 | `play_cards()` → `detect_pattern()` |
| 化合物 | `ActionPanel`/化合价面板 → `GameFlow._play_selected_compound(cv)` | `_plan_regular()` 配对循环 + `_pair_valences()` | `play_cards()` → `detect_pattern()` → `get_compound_formula()` |
| 有机物 | `ActionPanel` 有机物按钮 → `router.play(..., ORGANIC)` | 不尝试（AI 覆盖范围外） | `play_cards()` → `detect_pattern()` |
| 族炸 | `GameFlow._on_clan_bomb()` | `_plan_clan_bomb()` | `play_cards()` → `detect_pattern()` |
| 顺序 | `GameFlow._on_sequence()` / 「按序」按钮 | `_find_sequence()` + `sequence_pick` / 接顺序 | `play_cards()` → `detect_pattern()` |
| 直接出牌 | `GameFlow._on_auto_play()` → `router.auto_play(cards)` | 无对应（AI 自己挑牌） | `GameManager.auto_play_preview()` 只读预览 + `play_cards()` |

---

## 6. 统一规则（全部在 `play_cards()` 内生效）

以下规则对**所有**玩家（人类 + AI + 主机代打）统一生效，没有「AI 例外」：

| 规则 | 代码位置 | 对 AI 生效 |
|---|---|:---:|
| 族炸禁用 | `clan_bomb_disabled → -3` | ✅ |
| 族炸冷却 | `clan_bomb_cooling → -3`（先于接炸链判定） | ✅ |
| 溢出免疫族炸 | `compound_immune → -4` | ✅ |
| 接炸模式限制 | `clan_bomb_chain_active → -1`（非族炸） | ✅ |
| 牌型匹配 | `table_pattern != pattern → -4` | ✅ |
| 比大小 | `compare_cards ≤ 0 → -2` | ✅ |
| 化合物比例 | `ratio_ok == false → -1` | ✅ |
| 化合物式子为空 | `formula == "" → -1`（假化合物拦截） | ✅ |
| 顺序约束 | `sequence_constraint_active && idx == target && pattern 不符 → -6` | ✅ |
| 卤族互化 | `COMPOUND && !halogen_exchange_allowed && is_halogen_mix → -7` | ✅ |
| 接炸抽牌 | `player_pass()` 内统一抽 1 张 | ✅ |
| 上限弃牌 | `player_pass()` 内统一判定（达上限自动弃 1 张） | ✅ |

新增规则时**只改 `_evaluate_play()`**，不要在任何 UI / AI 分支里复制条件 ——
`HintAdvisor._check()` 就是直接调 `validate_play()`，所以「提示说能打、点了被拒」才不可能发生。

---

## 7. 联机等价性（为什么 `plan()` 必须只读）

| 断言 | 谁盯着 |
|---|---|
| `plan()` 不改手牌 / 桌面 / 轮转 / rng / 日志 | `tests/verify_ai_plan.gd` A 段（只读性） |
| 单机 `auto_play()` 的每一步 ≡ `apply_event()` 重放同一笔 intent | `verify_ai_plan.gd` B 段（20 手逐笔对拍） |
| `validate_play()` 通过 ⇒ `play_cards()` 返回同一个码 | `tests/verify_validate_play.gd` |
| 主机代打的结果三端 hash 一致 | `tests/verify_net_session.gd` / `verify_ui_online.gd` B 段（真 ENet） |

`_execute_local()` 刻意**不走** `apply_event()`：那会往 `event_log` 里写联机事件，
而单机对局不需要这份日志（`GameManager.state_hash` 只统计 `log_messages`）。

---

## 8. 回归测试清单

| 主题 | 测试 |
|---|---|
| 计划只读 + 单机落子等价 | `tests/verify_ai_plan.gd`（156 项） |
| AI 上限自动弃牌 | `tests/verify_ai_discard.gd` |
| 化合价 / 假化合物 | `tests/verify_compound_chemistry.gd` |
| 卤族互化（三条路径） | `tests/verify_halogen.gd` |
| 提示与引擎一致 | `tests/verify_hint.gd` / `verify_validate_play.gd` |
| 直接出牌（预览只读 + 真出牌） | `tests/verify_auto_play.gd` |
| 主机代 AI / 三端一致 | `tests/verify_net_session.gd` / `verify_ui_online.gd` |
| 集成（GameManager + AIPlayer） | `tests/verify_integration.gd` |
| 单机 AI 接力（刷新 → 排程 → 定时器 → 下一家） | `tests/verify_ai_chain.gd`（18 项，真 1.5s 定时器跑两轮 + D 段族炸接炸链终局） |

**2026-11-19 补记（族炸接炸链终局卡死）**：`GameManager._finish_clan_bomb_chain()` 原来只换牌权、
不推进 `turn_count`，UI 的排程令牌（当时只看回合号）因此误判「这一手已排过」，单机停在
「无人接炸！XX 自由出牌」后再也不动。修法：引擎补 `turn_count += 1`，同时把令牌升级成
「回合号 + 行动者 instance_id」双键 —— 以后漏一次 `+1` 只会多排一次定时器，不会再卡死。
负向验证：只回退引擎那行 `+1` → D 段立刻红；恢复后全绿。

---

## 9. 结论

- 裁决只有一处：`GameManager.play_cards()`（`_evaluate_play()`），人类 / AI / 提示 / 联机主机
  全部排队进同一条链；**AI 没有任何规则侧的特权**，只是候选域更窄。
- AI 的「决策」与「落子」已经分离：`plan()` 只读、可广播；`auto_play()` 只是单机便捷包装。
- 剩余差异只有两类，且都不是 bug：
  1. 双原子分子走 `DIATOMIC_SYMBOLS` 配对（玩家手选），功能等价；
  2. AI 不覆盖混合价态 / 3+ 元素化合物（人类面板专属）。
- 顺序约束、上限弃牌、假化合物、卤族互化四条历史差异都已收敛到引擎，并各有一套测试锁死。

---

**文档版本**: 2.1
**最后更新**: 2026-11-19

