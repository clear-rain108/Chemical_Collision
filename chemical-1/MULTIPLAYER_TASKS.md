# 联机改造 · 任务推进表（P11-C1-c）

> 用途：每一步开工前**复查**这里的范围与验收标准，收工时勾选并记 commit。
> 计划正文与设计理由见 [`MULTIPLAYER_ARCHITECTURE.md`](MULTIPLAYER_ARCHITECTURE.md) §9.2 / §10 / 附录 D。
> 最后更新：2026-11-11

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
| 2 | **主机代 AI 入口** | `NetSession.host_act_for_seat()` / `host_step_ai()`<br>`AIPlayer.plan()` 只读化<br>`tests/verify_ai_plan.gd`（新）+ `verify_net_session.gd` G19 | AI 座位动作被广播、三端 hash 一致；人类座位 / 非主机调用被拒；≥115 项 | ✅ 已完成（G19 后 `verify_net_session` 150 项、`verify_ai_plan` 156 项、全量 44 套绿） |
| 3a | **视图归属（防作弊）** | `GameUI`：`_hand_view_player` / `_view_player` / `_sel_cards` / `_hotseat_handoff_pending` / AI 调度 gate / 面板禁用 / `_process → _update_net()` | 联机只看得到自己手牌；非我方回合显示「等待 X」；单机 41 套 + `verify_touch_ui` / `verify_hand_view` 零回归 | ✅ 已完成（`verify_ui_online` A 段 69 项；全量 45 套绿） |
| 3b | **动作收口 + 信号接线** | 10 处动作改走 `ActionRouter`（`_router()` 惰性装配）；会话信号 8 个接线；主机 `host_step_ai()` 节流代打 | 单机全量零回归；联机 3 端打完一局 hash 全程一致 | ✅ 已完成（B 段 3 实例真 ENet：24 项；单机全量零回归） |
| 4 | **房间页** | `GameUI._build_room_page()`（代码建页 + 6 个 helper）<br>`tests/verify_room_page.gd`（新） | 开房 / 加入 / 座位表 / 开始按钮状态正确；不改 `.tscn` 结构 | ✅ 已完成（142 项：A 段零网络 111 项 + B 段 3 实例真 ENet 31 项；全量 46 套绿） |
| 5 | **真机联调 + 文档收口** | 3 端真窗口一局；文档 §9.2 → §9.1、§10 打勾、附录 D 补「UI 接线」 | 真窗口 3 人打完一局无报错、无分叉；文档与代码一致 | ⬜ 未开始 |

状态图例：⬜ 未开始 ｜ 🟨 进行中 ｜ ✅ 已完成 ｜ ⛔ 受阻（写明原因）

---

## 2. 已定稿的设计决策（实现时不许跑偏）

| # | 决策 | 理由 | 落地位置 |
|---|---|---|---|
| D1 | 客人提交**先本地 `validate_play()` 预检**，非法就地返回规则码、不发包；合法才 `submit()`，并置 `awaiting_reply()` | `submit()` 在客人侧恒返回 0，而 0 在单机里表示「成功」。UI 若当成功处理会误触发飞牌 / 误清选中 | `ActionRouter.play()` / `auto_play()` |
| D2 | **联机第一版跳过飞牌动画**（`_capture_play_fly_in` 只在单机跑） | 飞牌依赖 `selected_indices` 且必须在 `_refresh_ui` 之前；信号驱动刷新会把每笔广播都当「我出的牌」 | `GameUI._handle_result()` / `state_applied` 回调 |
| D3 | AI 先抽成只读 `AIPlayer.plan(gm, seat) -> Dictionary`，`auto_play()` 改成 `plan()` + 落子 | 主机无法把「直接落子」变成可广播的 intent；抽成 plan 后单机行为不变，联机可复用同一套候选优先级 | ✅ `scripts/AIPlayer.gd`（`plan` / `_execute_local`）＋ `NetSession.host_step_ai()` |
| D4 | 联机所有动作只走 `ActionRouter`，UI 不再直接碰 `game_manager` 的写接口 | 客人直写本地 `GameManager` = 立即分叉 | `GameUI` 10 处动作点 |
| D5 | 房间页用**代码建页**（照 `_build_supp_rules_page()`），不动 `Main.tscn` | 现有页面全是代码建；改 tscn 会拖累 UI 布局测试 | `GameUI.gd` |
| D6 | 联机视图恒为**本地座位**：手牌视角、可用牌型、`_sel_cards()` 全按 `my_seat` 取，与 `get_current_player()` 无关 | 用当前行动者的下标去查 `get_available_patterns()` / 手牌就是白送情报；客人选中的索引来自自己的手牌按钮，拿去索引别人的手牌会取成另一张牌 | `GameUI._hand_view_player()` / `_view_player()` / `_sel_cards()` / `_update_card_info_label()` |
| D7 | 挂了会话就**不再是热座**：`_is_hotseat()` 恒 false，装配时清空 `_hotseat_ready_seat` / `_hand_read_only` | 每个玩家盯自己那块屏；同屏交接遮罩会把 3 真人局直接卡死 | `GameUI._is_hotseat()` / `attach_session()` |
| D8 | UI 里的 AI 计时器在联机**关掉**，AI 只由主机 `_update_net() → host_step_ai()` 按 1.2s 节流代打（客人还没 ready 时不推进） | 客人本地跑那个计时器＝私自 `play_cards`，立刻与主机分叉；主机不代打则 AI 回合永远停住 | `GameUI._update_hand_buttons()` / `_update_net()` / `_ai_auto_play()` |
| D9 | 联机分支一律「先预检再提交」，界面状态只认会话回调：客人返回 0 仅表示**已发出**，面板停在「已提交，等待主机裁决…」 | 与 D1 同一语义在 UI 侧的落地：飞牌 / 清选中 / 写日志都必须等 `state_applied` 回来 | `GameUI._dispatch_result()` |
| D10 | 顺序牌型弹窗只在 `sequence_pending(seat == my_seat)` 时弹；`pick / skip` 走 `ActionRouter`，收窗统一走 `sequence_cleared → _hide_sequence_overlay()` | 客人弹了不该自己选的窗＝替别人做决定；不统一收窗会在超时 / 掉线 / 会话结束时留个遮罩挡住操作 | `GameUI._online_on_sequence_pending()` / `_show_sequence_constraint_dialog()` / `_hide_sequence_overlay()` |
| D11 | 联机退出 = `session.close(reason)` + 结算页，**不写** `game.phase` | 本端写 phase 只是本地作废，主机那份局面不受影响，客人却以为自己结束了 | `GameUI._on_quit_game()` |
| D12 | 大厅**没有 ready 握手**：`MSG_READY` 的语义是「快照重建完成（带 `events` 计数）」，只在开局后发；房间里 `all_seats_ready()` 恒为 false | 拿 ready 做开局门控 = 永远开不了局（`NetSession` 从没在大厅收过 ready）。闸门只能是「在线人类 + AI ∈ [3,4]」，掉线座位另算 | `GameUI._room_start_block_reason()` / `_room_start_disabled_reason()` |
| D13 | 会话只有**一个装配口** `_room_bind_session()` → `attach_session()`；离开房间一律走 `_room_teardown()`（`close()` + `attach_session(null)` + 丢掉大厅那份空 `GameManager`） | 闭着的会话若留在 `net_session` 上，单机「开始游戏」会被 `_on_start_game()` 的联机分支拦成「请从房间页开局」；大厅那份 `GameManager` 的 players 为空，留着会污染下一次单机开局 | `GameUI._room_bind_session()` / `_room_teardown()` / `_room_leave()` / `_close_room_page()` |
| D14 | `room_code` 只是**辨认用的 4 位数**，不代表任何地址：页面副标题写死「房号仅用于辨认，客人需填房主 IP」，房主页直接显示本机 IPv4 列表 | 房间码 → 地址需要信令服务器（P11-C2）；让用户以为「输房号就能连」是最贵的误解 | `GameUI._room_ip_text()` / `_room_local_ips()` / `RoomSubtitle` |
| D15 | 房间**最少 3 座位**：`GameManager.MIN_PLAYERS = 3`，`NetSession.start_game()` 把 total clamp 到 2..4 —— 2 座位会在 `init_game` 里直接失败；AI 只能补到 `4 - 在线人类数` | 少于 3 人开局必然初始化失败，不如在按钮上就拦住并写清「至少 3 个（当前 N）」 | `GameUI._room_refresh()`（`ai_cap`）/ `_room_start_block_reason()` |

---

## 3. 每步收工前必跑（复查清单）

```bat
:: 单个新套件
godot --headless --path . --script tests\verify_action_router.gd
godot --headless --path . --script tests\verify_ai_plan.gd
godot --headless --path . --script tests\verify_net_session.gd
godot --headless --path . --script tests\verify_enet_transport.gd
godot --headless --path . --script tests\verify_ui_online.gd
godot --headless --path . --script tests\verify_room_page.gd

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
| 2026-11-11 | Step 2 主机代 AI | `AIPlayer` 拆成只读 `plan(game_manager, seat)` + 单机 `_execute_local()`（`auto_play()` 签名不变）；`NetSession.host_act_for_seat()` / `host_step_ai()` 复用 `make_intent → _validate_for_seat → _host_apply` 同一条裁决链，`NetProtocol.ERR_NOT_HOST = -110`；新增 `verify_ai_plan` 156 项（只读性 / 单机落子 ≡ `apply_event` 重放 20 手逐笔对拍 / 计划复核 / 覆盖 / 边界），G19 39 项；全量 44 套绿 | 已提交 |
| 2026-11-11 | Step 3 UI 联机化 | `GameUI` 加 `net_session / action_router` 装配口 `attach_session()`：视图归属（D6）/ 热座关闭（D7）/ AI 计时器联机门控（D8）/ 结果分派（D9）/ 弹窗收窗（D10）/ 退出只关会话（D11）；10 处动作改走 `ActionRouter`（`_router()` 惰性装配，单机路径逐字等价）；`_process → _update_net()` 每帧 poll + 主机 `host_step_ai(1)` 1.2s 节流；新增 `verify_ui_online` 93 项（A 段假会话 69 项 + B 段 3 实例真 ENet 24 项：三端 hash / event_log 一致、客人提交不动本地局面、AI 座位由主机代打广播）；全量 45 套绿 | `25d0007` |
| 2026-11-11 | Step 4 房间页 | `GameUI` 新增 `_build_room_page()`（代码建页，不动 `.tscn`）：标题 / 副标题（写死 D14「房号仅用于辨认」）/ 建房卡（昵称 + 端口 + 本机 IP + 创建 + 房号）/ 加入卡（昵称 + 端口 + 房主 IP + 加入 + 离开）/ 4 张固定座位卡 / AI 人数 / 开始对局 / 提示区；闸门纯函数 `_room_start_block_reason(online, ai, is_host, state, offline)`（D12 不看 ready、D15 只认 3~4）；`_room_bind_session()` 唯一装配口 + `_room_teardown()` 唯一收尾口（D13）；`_room_refresh()` 派生 AI 上限与三颗按钮状态；本机 IP 过滤回环 / 链路本地 / IPv6；新增 `verify_room_page` 142 项（A 段零网络 111 项：结构 / 开始页按钮几何 / 开关页 / 闸门边界 / 假会话座位表与信号 / 离开收尾 / 单机红线；B 段 3 实例真 ENet 31 项：页面建房 → 2 客人从页面加入 → 昵称 + 房号 + 座位表 → 3 人 + 1 AI 开局 → 三端进牌桌 4 玩家 → 客人离开后座位保留掉线）；全量 46 套绿 | 本次提交 |

---

## 5. 明确不做（缓到后续阶段）

| 项 | 原因 | 去向 |
|---|---|---|
| 踢人（`disconnect_peer`） | `NetTransport` 未暴露该能力 | P11-C1 收尾 / P11-D |
| 房间码 → 地址发现层 | 需要信令服务器，与 P11-C2 一起做 | P11-C2 |
| 跨 NAT（WebRTC + TURN） | 独立传输层 | P11-C2 |
| 观战者 UI（只读视角） | 协议已支持，UI 未做 | P11-D 打磨 |
| 飞牌动画的联机版 | 取 D2，先跳过 | P11-D 打磨 |
