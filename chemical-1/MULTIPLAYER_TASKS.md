# 联机改造 · 任务推进表（P11-C1-c）

> 用途：每一步开工前**复查**这里的范围与验收标准，收工时勾选并记 commit。
> 计划正文与设计理由见 [`MULTIPLAYER_ARCHITECTURE.md`](MULTIPLAYER_ARCHITECTURE.md) §9.2 / §10 / 附录 D。
> 最后更新：2026-11-10

---

## 0. 已完成（基线）

| 阶段 | 交付物 | 验收 | 提交 |
|---|---|---|---|
| P11-B 地基 | 种子洗牌 / 牌 uid / 快照 / `state_hash` / `apply_event` / 传输抽象 / 回环 | 54 项 | `f4ae817` 之前 |
| P11-C1-a 传输 | `scripts/net/ENetTransport.gd` | 55 项 | `f4ae817` |
| P11-C1-b 会话层 | `scripts/net/NetSession.gd` | 111 项 | `d9390b7` |
| P11-C1-c Step 0 冒烟 | `tests/net_smoke.gd`（3 进程真机） | 三端 `final_hash` 一致，实测 32 / 27 笔两组 | `0b78187` |

---

## 1. 推进表

| # | 步骤 | 交付物 | 验收（必须全绿） | 状态 |
|---|---|---|---|---|
| 1 | **ActionRouter 路由层** | `scripts/net/ActionRouter.gd`（新）<br>`tests/verify_action_router.gd`（新） | 单机返回码 / `state_hash` 与直调等价；客人提交后本地 hash 不变；非法牌本地预检不发包；41 套单机零回归 | ✅ 已完成（67 项 + 全量 43 套绿） |
| 2 | **主机代 AI 入口** | `NetSession.host_act_for_seat()`<br>`verify_net_session.gd` G19 | AI 座位动作被广播、三端 hash 一致；人类座位 / 非主机调用被拒；≥115 项 | ⬜ 未开始 |
| 3a | **视图归属（防作弊）** | `GameUI`：`_hand_view_player` / `_hotseat_handoff_pending` / AI 调度 gate / 面板禁用 / `poll()` | 联机只看得到自己手牌；非我方回合显示「等待 X」；单机 41 套 + `verify_touch_ui` / `verify_hand_view` 零回归 | ⬜ 未开始 |
| 3b | **动作收口 + 信号接线** | 10 处动作改走 `ActionRouter`；5 个信号接线 | 单机全量零回归；联机 3 端打完一局 hash 全程一致 | ⬜ 未开始 |
| 4 | **房间页** | `GameUI._build_room_page()`（代码建页）<br>`tests/verify_room_page.gd`（新） | 开房 / 加入 / 座位表 / 开始按钮状态正确；不改 `.tscn` 结构 | ⬜ 未开始 |
| 5 | **真机联调 + 文档收口** | 3 端真窗口一局；文档 §9.2 → §9.1、§10 打勾、附录 D 补「UI 接线」 | 真窗口 3 人打完一局无报错、无分叉；文档与代码一致 | ⬜ 未开始 |

状态图例：⬜ 未开始 ｜ 🟨 进行中 ｜ ✅ 已完成 ｜ ⛔ 受阻（写明原因）

---

## 2. 已定稿的设计决策（实现时不许跑偏）

| # | 决策 | 理由 | 落地位置 |
|---|---|---|---|
| D1 | 客人提交**先本地 `validate_play()` 预检**，非法就地返回规则码、不发包；合法才 `submit()`，并置 `awaiting_reply()` | `submit()` 在客人侧恒返回 0，而 0 在单机里表示「成功」。UI 若当成功处理会误触发飞牌 / 误清选中 | `ActionRouter.play()` / `auto_play()` |
| D2 | **联机第一版跳过飞牌动画**（`_capture_play_fly_in` 只在单机跑） | 飞牌依赖 `selected_indices` 且必须在 `_refresh_ui` 之前；信号驱动刷新会把每笔广播都当「我出的牌」 | `GameUI._handle_result()` / `state_applied` 回调 |
| D3 | AI 先抽成只读 `AIPlayer.plan(gm) -> Dictionary`，`auto_play()` 改成 `plan()` + 落子 | 主机无法把「直接落子」变成可广播的 intent；抽成 plan 后单机行为不变，联机可复用同一套候选优先级 | `scripts/AIPlayer.gd` |
| D4 | 联机所有动作只走 `ActionRouter`，UI 不再直接碰 `game_manager` 的写接口 | 客人直写本地 `GameManager` = 立即分叉 | `GameUI` 10 处动作点 |
| D5 | 房间页用**代码建页**（照 `_build_supp_rules_page()`），不动 `Main.tscn` | 现有页面全是代码建；改 tscn 会拖累 UI 布局测试 | `GameUI.gd` |

---

## 3. 每步收工前必跑（复查清单）

```bat
:: 单个新套件
godot --headless --path . --script tests\verify_action_router.gd
godot --headless --path . --script tests\verify_net_session.gd
godot --headless --path . --script tests\verify_enet_transport.gd

:: 单机全量（零回归硬门槛）
for %f in (tests\verify_*.gd) do @(echo === %f === & godot --headless --path . --script %f 2>&1 | findstr TESTS)

:: 真机三进程（Step 3b / 5 必跑）
:: 三个终端分别：--host / --join 127.0.0.1 / --join 127.0.0.1（--port 47800）
godot --headless --path . --script tests\net_smoke.gd -- --host --port 47800 --duration 60
```

判读标准：`state_hash` 逐笔一致、`SMOKE FINAL final_hash` 三端相同、`rejected=0`、`desync=0`。

---

## 4. 进度日志（每完成一步追加一行）

| 日期 | 步骤 | 结果 | 提交 |
|---|---|---|---|
| 2026-11-10 | Step 0 冒烟脚本 | 三进程一局 32 笔 / 27 笔，三端 hash 一致；顺带修掉 `ready` 误报 -109 | `0b78187` |
| 2026-11-10 | Step 1 路由层 | `ActionRouter` 6 个动作 × 单机/联机双路；`verify_action_router` 67 项（A 段同 seed 双实例逐步对拍 16 步，B 段三进程 ENet 验已发出/已裁决/-102/-105/预检不发包）；全量 43 套测试绿 | 已提交 |

---

## 5. 明确不做（缓到后续阶段）

| 项 | 原因 | 去向 |
|---|---|---|
| 踢人（`disconnect_peer`） | `NetTransport` 未暴露该能力 | P11-C1 收尾 / P11-D |
| 房间码 → 地址发现层 | 需要信令服务器，与 P11-C2 一起做 | P11-C2 |
| 跨 NAT（WebRTC + TURN） | 独立传输层 | P11-C2 |
| 观战者 UI（只读视角） | 协议已支持，UI 未做 | P11-D 打磨 |
| 飞牌动画的联机版 | 取 D2，先跳过 | P11-D 打磨 |
