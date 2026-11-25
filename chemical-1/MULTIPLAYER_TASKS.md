# 联机改造 · 任务推进表（P11-C1-c）

> 用途：每一步开工前**复查**这里的范围与验收标准，收工时勾选并记 commit。
> 计划正文与设计理由见 [`MULTIPLAYER_ARCHITECTURE.md`](MULTIPLAYER_ARCHITECTURE.md) §9.2 / §10 / 附录 D。
> 最后更新：2026-11-19

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
| 4 | **房间页** | `GameUI._build_room_page()`（代码建页 + 6 个 helper）<br>`tests/verify_room_page.gd`（新） | 开房 / 加入 / 座位表 / 开始按钮状态正确；不改 `.tscn` 结构 | ✅ 已完成（151 项：A 段零网络 120 项 + B 段 3 实例真 ENet 31 项；全量 46 套绿） |
| 4b | **房间人数 3~8（D17）** | `NetSession` `MIN_PLAYERS/MAX_PLAYERS/seat_capacity()/ai_count()`<br>`GameUI` 座位数微调框 + 8 张座位卡按容量显隐/等分<br>`tests/verify_room_page.gd`（+35 项，含容量 8 三端真 ENet）<br>`tests/verify_net_session.gd` G21（+20 项） | 3~8 全档可建房；`start_game(9)` → 8、`start_game(2)` → 3；8 座位三端玩家数与指纹一致；6~8 人牌桌状态区不越界 | ✅ 已完成（`verify_room_page` 186 项、`verify_net_session` 180 项、全量 46 套绿） |
| 4c | **真机联调前置：INTERNET 权限 + 诊断开关（D18）** | `export_presets.cfg` `permissions/internet=true`（pre1005.2）<br>`NetSession` 追踪 API + `GameUI --net-trace`<br>`tests/verify_net_session.gd` G20（+8 项） | `aapt2 dump permissions` 能看到 `android.permission.INTERNET`；`--net-trace` 下两端 trace 行逐笔同指纹 | ✅ 已完成（`chemical-pre1005.2-debug.apk`；无设备，真机复测待接线） |
| 4d | **大厅 AI 补位数以会话为准（D19）** | `NetSession.lobby_ai` / `set_lobby_ai()` / `lobby_ai_cap()` / `online_humans()` / `_host_broadcast_lobby()`<br>`MSG_LOBBY` 协议消息 + welcome 带 `ai_count`<br>`GameUI._room_refresh()` 读会话值 + 客人 `editable = false`<br>`tests/verify_net_session.gd` G22（19 项）+ `verify_room_page.gd` 5c（10 项） | 房主改 AI 数 → 客人 1 秒内同步；客人 `set_lobby_ai` 是空操作且污染不了房主；第三人加入后上限自动收紧；开局后 `lobby_ai == ai_count` 三端一致 | ✅ 已完成（`verify_net_session` 221 项、`verify_room_page` 199 项） |
| 4e | **房主收房，客人当场知道（D20）** | `MSG_BYE` + `NetSession.close()` 里「先广播再补 `poll()` 一次」<br>`_on_peer_disconnected()` 先判「客人 + peer 1」<br>`GameUI._net_over_notice` / sticky toast / `_update_card_info_label()` 抢占 / `_clear_net_over_notice()`<br>`verify_net_session.gd` G23（14 项）+ `verify_ui_online.gd` 9b（5 项） | 房主 `close()` → 客人 1 秒内收尾并写明原因；BYE 到不了也要收尾；终止提示整页刷新后仍在，新局能清掉 | ✅ 已完成（G23 两条路都绿；`verify_ui_online` 101 项） |
| 4f | **心跳 + 底层失活兜底（D21）** | `heartbeat_ms = 1000` / `heartbeat_timeout_ms = 12000` + `_poll_timeouts()`<br>`ENetTransport._was_connected` / `_reap_inactive()`（先 drain 包再补 `disconnected`，先摘 `_peer` 再 `close()`）<br>`verify_net_session.gd` G24（8 项） | 房主不再 `poll()`（= 杀进程）后客人 400ms 级收尾（测试阈值）并给出「心跳超时」原因；IP 写错（根本没连上）不会被误判掉线 | ✅ 已完成（G24 8 项；`verify_enet_transport` 55 项零回归） |
| 4g | **化合物质疑投票（D22，协议 v2）** | `scripts/net/VoteBox.gd`（新，纯逻辑）<br>`NetSession` 投票生命周期 + `can_claim` / `cast_vote` / 快照 `vote` 字段<br>`GameManager.validate_play_claim()` / `compound_rulings` 白名单 / `apply_event("compound_ruling")`<br>`ActionRouter.claimable()` / `claim_compound()`<br>`ui/VoteUI.gd`（新）+ `OnlineUI` 三信号转发 + `ActionPanel` 配不平时转质疑<br>`tests/verify_vote_box.gd` / `verify_net_vote.gd` / `verify_vote_ui.gd`（新）+ `verify_action_router.gd` C 段 | 只有 `-1` / `-7` 能进投票，`-2/-4` 等牌权问题硬拒；全票赞成 → 落子 + 白名单（进指纹）；一票反对 / 超时 / 无人可投 → 撤销 + 罚抽 1 张；投票期间 `-111` 全场冻结、AI 0 步；掉线者出分母；三端逐笔同指纹、0 分叉 | ✅ 已完成（`verify_vote_box` 50 / `verify_net_vote` 83 / `verify_vote_ui` 47 / `verify_action_router` 94；全量 52 套绿） |
| 5 | **真机联调 + 文档收口** | 3 端真窗口一局；文档 §9.2 → §9.1、§10 打勾、附录 D 补「UI 接线」（D13 + D19/D20/D21） | 真窗口 3 人打完一局无报错、无分叉；房主退出 / 杀进程客人都能当场看到原因；菜单 / 牌桌全程无「状态分叉」 | 🟨 进行中（APK `pre1005.4` 已出，等手机插线走拓扑 A 复测 D19/D20/D21） |

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
| D8 | UI 里的 AI 计时器在联机**关掉**，AI 只由主机 `_update_net() → host_step_ai()` 按节流代打（客人还没 ready 时不推进）。节流默认 1.2s，AI ≥3 个降到 0.8s、≥5 个降到 0.6s（D17：8 座位最多 7 个 AI，1.2s 走一轮要 8 秒多） | 客人本地跑那个计时器＝私自 `play_cards`，立刻与主机分叉；主机不代打则 AI 回合永远停住 | `GameUI._update_hand_buttons()` / `_update_net()` / `_net_ai_delay()` / `_ai_auto_play()` |
| D9 | 联机分支一律「先预检再提交」，界面状态只认会话回调：客人返回 0 仅表示**已发出**，面板停在「已提交，等待主机裁决…」 | 与 D1 同一语义在 UI 侧的落地：飞牌 / 清选中 / 写日志都必须等 `state_applied` 回来 | `GameUI._dispatch_result()` |
| D10 | 顺序牌型弹窗只在 `sequence_pending(seat == my_seat)` 时弹；`pick / skip` 走 `ActionRouter`，收窗统一走 `sequence_cleared → _hide_sequence_overlay()` | 客人弹了不该自己选的窗＝替别人做决定；不统一收窗会在超时 / 掉线 / 会话结束时留个遮罩挡住操作 | `GameUI._online_on_sequence_pending()` / `_show_sequence_constraint_dialog()` / `_hide_sequence_overlay()` |
| D11 | 联机退出 = `session.close(reason)` + 结算页，**不写** `game.phase` | 本端写 phase 只是本地作废，主机那份局面不受影响，客人却以为自己结束了 | `GameUI._on_quit_game()` |
| D12 | 大厅**没有 ready 握手**：`MSG_READY` 的语义是「快照重建完成（带 `events` 计数）」，只在开局后发；房间里 `all_seats_ready()` 恒为 false | 拿 ready 做开局门控 = 永远开不了局（`NetSession` 从没在大厅收过 ready）。闸门只能是「在线人类 + AI ∈ [3,4]」，掉线座位另算 | `GameUI._room_start_block_reason()` / `_room_start_disabled_reason()` |
| D13 | 会话只有**一个装配口** `_room_bind_session()` → `attach_session()`；离开房间一律走 `_room_teardown()`（`close()` + `attach_session(null)` + 丢掉大厅那份空 `GameManager`） | 闭着的会话若留在 `net_session` 上，单机「开始游戏」会被 `_on_start_game()` 的联机分支拦成「请从房间页开局」；大厅那份 `GameManager` 的 players 为空，留着会污染下一次单机开局 | `GameUI._room_bind_session()` / `_room_teardown()` / `_room_leave()` / `_close_room_page()` |
| D14 | `room_code` 只是**辨认用的 4 位数**，不代表任何地址：页面副标题写死「房号仅用于辨认，客人需填房主 IP」，房主页直接显示本机 IPv4 列表 | 房间码 → 地址需要信令服务器（P11-C2）；让用户以为「输房号就能连」是最贵的误解 | `GameUI._room_ip_text()` / `_room_local_ips()` / `RoomSubtitle` |
| D15 | 房间**最少 3 座位、最多可到 capacity**：`GameManager.MIN_PLAYERS = 3`，`NetSession.start_game()` 把 total clamp 到 `[3, 8]` —— 2 座位会在 `init_game` 里直接失败；AI 只能补到 `capacity - 在线人类数`（capacity 见 D17） | 少于 3 人开局必然初始化失败，不如在按钮上就拦住并写清「至少 3 个（当前 N）」 | `GameUI._room_refresh()`（`ai_cap`）/ `_room_start_block_reason()` |
| D16 | 开始页入场动画的名单提成常量 `START_INTRO_ORDER`，**必须在开始页加按钮时同步登记** | 名单漏登的节点不淡入也不上浮，页面淡入一结束就以终态"抢先"出现 —— Step 4 的 `RoomEntryBtn` 就这么漏过一次，肉眼现象是「这颗按钮没有动画」。测试用「开始页直接子节点里的 Button 必须全在名单里」兜底 | `GameUI.START_INTRO_ORDER` / `verify_room_page._test_intro_animation()` |
| D17 | 房间座位数**建房时可选 3~8（默认 4），创建后固定**：`NetSession.start_host()` 记下 `max_players`，welcome 把它下发给客人；`seat_capacity()` 是唯一读数口。ENet 连接名额 = `capacity + RECONNECT_SLACK`（4），开局后不再改 | 规则层本来就吃 3~8（`PlayerManager.MIN/MAX_PLAYERS`），4 只是联机层的旧上限；容量固定在建房时 = 重连名额 / 满员拒绝 / 座位卡张数三处判断永远一致，不会出现「中途改人数后 ENet 名额不够」 | `NetSession.start_host()` / `seat_capacity()` / `GameUI._room_seat_capacity()` / `ROOM_DEFAULT_SEATS` |
| D18 | 联机诊断开关 `--net-trace`：每个会话把**每笔权威事件的指纹**打成一行 `HOST seat=… tick=… ev=… hash=…` / `CLIENT …`，同时留 512 行内存副本 `trace_log`；默认关闭 | 真机没有控制台，`adb logcat -s godot:V` 只能看到 print；两端逐笔对齐才能定位「第几笔开始分叉」。缓冲让无头测试不必抓 stdout | `NetSession.enable_trace()` / `_trace_line()` / `GameUI.net_trace_requested()` |
| D19 | 大厅 AI 补位数**以会话为准**：`NetSession.lobby_ai`，只有房主能写（`set_lobby_ai()` 对非主机 / 非 `LOBBY` 是空操作），clamp 到 `seat_capacity() - online_humans()`；变了就广播 `MSG_LOBBY`，welcome 也带 `ai_count`；客人微调框 `editable = false` | AI 数只活在房间页控件里时，客人那份没人写值 —— 真机表现是「房主补了 2 个 AI，客人座位卡还是空位」，两边心里的人数对不上 | `NetSession.lobby_ai` / `set_lobby_ai()` / `lobby_ai_cap()` / `_host_broadcast_lobby()` / `GameUI._room_refresh()` |
| D20 | 联机终止原因**钉在牌桌上**：`session_closed` / `desync_detected` 写 `_net_over_notice`，`_update_card_info_label()` 非空就显示 `⚠ <原因>` 并直接 return；toast 用 sticky（不挂 2.5 秒计时器）；`_clear_net_over_notice()` 由回开始页 / 单机新局 / 联机开局 / 离开房间共用 | 只弹 toast 的话 2.5 秒后牌桌只剩「等待 X 行动…」，看起来像卡死。房主 `close()` 里还要先广播 `MSG_BYE` 再补 `poll()` 一次才关服，否则包留在队列里一起被丢掉 | `NetSession.close()` / `MSG_BYE` / `GameUI._online_on_session_closed()` / `_update_card_info_label()` |
| D21 | 掉线判定三条路，按时延：① `ENetTransport.poll()` 发现底层 `CONNECTION_DISCONNECTED` → `_reap_inactive()` 立刻补派发 `disconnected`（客人视角 peer 1）；② 收到 BYE；③ `heartbeat_ms = 1000` / `heartbeat_timeout_ms = 12000` 兜底；`_was_connected` 区分「连上后又断」与「根本没连上」 | ENet 客人在服务端消失时不保证收到 `peer_disconnected`，只能等引擎自己的超时（几十秒起）。另外 `_on_peer_disconnected()` **必须**在查座位表之前判「客人 + peer 1」：客人的 `_peer_seat` 没有「座位 0 ↔ 主机」映射，查表会当成陌生 peer 忽略 —— 这是「房主退出了，客人还在等待」的真因 | `ENetTransport._reap_inactive()` / `NetSession._on_peer_disconnected()` / `MSG_PING` / `_client_check_heartbeat()` |
| D22 | 「配不平 `-1` / 卤族互化 `-7`」这两条**化学性**拒绝交其他真人全票裁定；投票结论以**一笔 `compound_ruling` 权威事件**落地（通过 = 落子 + 记白名单；不通过 = 罚抽 1 张）。其余拒绝码（`-2/-3/-4/-6/-8`）是牌权问题，硬拒不可投票。开票前**必须**再跑一次普通 `validate_play`：`>=0` 就当普通出牌落子，只有 `<0` 才开票 | ① 判定权让渡给玩家，但**不能让人用质疑绕过接牌 / 牌型判定**（否则「-4 接不上」也能投票，牌权规则就废了）；② 结论必须是事件而不是消息，三端才能靠重放对齐指纹 —— 投票过程（谁投了谁）不进 `event_log`；③ 白名单粒度取「元素组成多重集」并进快照 + `state_hash`：重连的客人重放同一笔 `compound_ruling` 时必须能算出同一个白名单，否则那一笔会再次配平失败 → `-109` 分叉 | `GameManager.validate_play_claim()` / `compound_rulings` / `apply_event("compound_ruling")`；`NetSession._claim_rule_code()` / `_host_apply_claim()` / `_host_open_vote()` / `_host_resolve_vote()`；`net/VoteBox.gd`；`ActionRouter.claimable()` / `claim_compound()`；`ui/VoteUI.gd` |

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
| 2026-11-11 | Step 4 房间页 | `GameUI` 新增 `_build_room_page()`（代码建页，不动 `.tscn`）：标题 / 副标题（写死 D14「房号仅用于辨认」）/ 建房卡（昵称 + 端口 + 本机 IP + 创建 + 房号）/ 加入卡（昵称 + 端口 + 房主 IP + 加入 + 离开）/ 4 张固定座位卡 / AI 人数 / 开始对局 / 提示区；闸门纯函数 `_room_start_block_reason(online, ai, is_host, state, offline)`（D12 不看 ready、D15 只认 3~4）；`_room_bind_session()` 唯一装配口 + `_room_teardown()` 唯一收尾口（D13）；`_room_refresh()` 派生 AI 上限与三颗按钮状态；本机 IP 过滤回环 / 链路本地 / IPv6；新增 `tests/verify_room_page.gd` 151 项（A 段零网络 120 项：结构 / 开始页按钮几何 / 入场名单覆盖性 + 真播一遍 / 开关页 / 闸门边界 / 假会话座位表与信号 / 离开收尾 / 单机红线；B 段 3 实例真 ENet 31 项：页面建房 → 2 客人从页面加入 → 昵称 + 房号 + 座位表 → 3 人 + 1 AI 开局 → 三端进牌桌 4 玩家 → 客人离开后座位保留掉线）；B 段端口改为 47855 起逐个探测（并发跑不再假失败）；全量 46 套绿 | 本次提交 |
| 2026-11-12 | 修「联机对战」没有入场动画 | 真因：`_animate_start_page()` 的入场名单硬编码，Step 4 新加的 `RoomEntryBtn` 没登记 → 它不淡入也不上浮，页面淡入一结束就以终态"抢先"出现。修法：名单提成常量 `START_INTRO_ORDER`（D16）并补登在 `StartButton` 之前。`verify_room_page` 新增 9 项（名单覆盖性 / 不陈旧 / 视觉顺序 / 真播一遍首帧 a=0 & y=500 + 落位 a=1 & y=486）；负向验证：临时拿掉登记会立刻 4 项 FAIL。顺带修 `联机对战 124x52` 的精确比较（高度会落到 52.00012）→ 改容差，B 段端口 47855 起探测（并发跑两遍不再假失败） | 本次提交 |
| 2026-11-12 | 真机联机卡点：APK 没有 INTERNET 权限（D18） | 复盘 `chemical-pre1005.1-debug.apk`：`aapt2 dump permissions` 只有 `VIBRATE` → `export_presets.cfg: permissions/internet=false`，Android 上 ENet 的 UDP socket 建不起来（表现是永远 CONNECTING）。改成 `true` 重新导出 `chemical-pre1005.2-debug.apk`，aapt2 复核到 `android.permission.INTERNET` + `VIBRATE`，包名仍是 `com.clearrain.chemicalcollision`。同时补 `--net-trace`（打包进 `pre1005.3`）：`NetSession.enable_trace()` 把每笔权威事件打成 `HOST/CLIENT seat=… tick=… ev=… hash=…` 并留 512 行 `trace_log`；`GameUI._ready()` 扫 `--net-trace`（与 `--touch-ui` 同一套参数扫描）并在 `attach_session()` 打开；`verify_net_session` G20 8 项（默认关 / 8 位十六进制 / 两端末行同指纹 / 关闭清空） | 本次提交 |
| 2026-11-12 | 房间人数 3~8（D17） | 规则层早已支持 3~8，只有联机层 `start_host()` / `start_game()` 把人数 clamp 在 `[2,4]`、房间页写死 `ROOM_MAX_SEATS = 4`。改法：`NetSession` 加 `MIN_PLAYERS=3 / MAX_PLAYERS=8 / DEFAULT_MAX_PLAYERS=4` + `seat_capacity()` / `ai_count()`；`GameUI` 加「座位数」微调框（3~8，默认 4，进房锁定）、8 张座位卡按容量显隐（3~4 沿用 24+i*256/240×122，5~8 等分 1012px、8 张各 119px、昵称 16px+clip_text）、AI 上限 = capacity − 在线人类、闸门加 `capacity` 参数（默认 4 保持老调用可用）、`_format_player_status()` 名字链每 4 人换行 + AI 手牌行每 4 条换行且总行数 ≤4（6~8 人不再压到「桌面: …」）；主机 AI 节流按人数缩短（≥5 个 AI → 0.6s/手）。测试：`verify_room_page` +35 项（8 张卡 / 等分几何 / 「2/4」「3/3」「3/8」/ 闸门 3·8·9 边界 / 容量 8 三端真 ENet 8 玩家指纹一致），`verify_net_session` G21 +20 项（`start_host(8)` 同步容量、`start_game(9)`→8、`start_game(2)`→3、8 座位 7 AI 事件流指纹一致）；全量 46 套绿 | 本次提交 |
| 2026-11-19 | 化合物质疑投票（D22，协议 v2） | 「配不平 / 卤族互化」这类**化学性**拒绝不再由引擎一言堂，改交其他真人裁定：出牌被拒且码 ∈ {`-1`,`-7`} → 主机开票（分母 = 除出题人的在线真人，AI / 观战不参与），**全票赞成**才落子并把这个「元素组成多重集」记进 `compound_rulings` 白名单（进快照 + `state_hash`，否则重连客人重放 `compound_ruling` 会再配平失败 → `-109`）；一票反对 / 20 秒超时 / 无人可投 → 出牌撤销 + 罚抽 1 张。四层拆分：`net/VoteBox.gd`（纯逻辑 50 项）/ `NetSession`（开票时机、广播、掉线出分母、`-111` 冻结、AI 0 步）/ `GameManager`（`validate_play_claim` 只放宽两条 + 白名单）/ `ui/VoteUI.gd`（只读快照遮罩）。`PROTO_VERSION 1→2`，新增 `vote_request / vote_cast / vote_state / vote_result` 四条消息与 `-111/-112/-113` 三个错误码（新旧 APK 不能同房）。守门：`_claim_rule_code` 先跑普通 `validate_play`，`>=0` 就当普通出牌落子，只有 `<0` 才开票 —— 防玩家用质疑绕过接牌 / 牌型判定。测试：`verify_vote_box` 50 / `verify_net_vote` 83（四张真 ENet 牌桌：通过、否决、超时、投票人掉线）/ `verify_vote_ui` 47（遮罩 / 冻结面板 / 非投票人 / 倒计时自愈 / 重连补开 / 桌面标记）/ `verify_action_router` C 段 9 项；负向自检把 `allow_override` 改回 false → 4 项立刻转红；全量 52 套绿 | 本次提交 |
| 2026-11-12 | 真机三人局四个反馈：客人能改 AI 数 / 客人看不到房主补的 AI / 房主退出客人无提示 / 房主杀进程客人卡住（D19 · D20 · D21） | **D19**：大厅 AI 数搬进 `NetSession.lobby_ai`，只有房主能写（`set_lobby_ai()` 对非主机 / 非 `LOBBY` 空操作），clamp 到 `seat_capacity() - online_humans()`；新增 `MSG_LOBBY` 广播 + welcome 带 `ai_count`（新人一步到位）；房间页读会话值、客人微调框 `editable = false`，`_room_ai_sync` 挡住 `value_changed` 回推。**D20**：`close()` 里「置 CLOSED → 广播 `MSG_BYE` → 补 `poll()` 一次 → 关服」；`_on_peer_disconnected()` **先判「客人 + peer 1」**再查座位表（客人的 `_peer_seat` 没有「座位 0 ↔ 主机」映射，原来一律被当陌生 peer 忽略 —— 这才是「房主退出了客人还在等待」的真因）；`GameUI._net_over_notice` + sticky toast + `_update_card_info_label()` 非空即 `⚠ <原因>` 并 return，`_clear_net_over_notice()` 统一清。**D21**：主机每 1s 广播 `MSG_PING`，客人 12s 没收到任何包就判失联；`ENetTransport` 加 `_was_connected` + `_reap_inactive()`（先把队列里剩的包 drain 出来再补派发 `disconnected`，先摘 `_peer` 再 `close()`），房主 `close()` / 杀进程时客人同帧收尾，心跳只做兜底。测试：`verify_net_session` G22 19 项 + G23 14 项（BYE 与关服两条路都测）+ G24 8 项；`verify_room_page` 5c 10 项（房主回推 / 会话值同步 / 客人只读且硬改被挡回）；`verify_ui_online` 9b 5 项 + 分叉 3 项（提示常驻、整页刷新不被覆盖、清掉后回到回合文本）。现状：`verify_net_session` 221 项、`verify_room_page` 199 项、`verify_ui_online` 101 项、`verify_enet_transport` 55 项全绿 | 本次提交 |
| 2026-11-20 | 真机 -109 误报：指纹里混进了 UI 队列长度（D23，协议 v3） | 现象：Android 开房 / 加入后**主机弹一次**「座位 N 重建后指纹不一致（对端 3801224070 / 主机 3767668832，第 0 笔）」，但游戏完全正常（能出牌、能投票）。根因：v2 的 `_canonical_string()` 末尾是 `parts.append("logs=%d" % log_messages.size())`，而 `log_messages` 是 **UI 待消费队列** —— `SidePanels._update_log_label()` 每刷新一帧就 `flush_logs()` 把它清空（`GameLogger.flush_logs()` 内部 `clear()`），于是同一局面能出两个指纹（手机 `_send_ready()` 时 logs=2 / 主机 `_host_on_ready()` 重算时 logs=0）。之所以只吓人不拦人：`_host_on_ready()` 只 `error_raised.emit` 不置 `_desynced`，手机侧比的又是 `game_start` 里带的 hash（那一瞬两端都还没 flush）。修法：指纹只放规则状态，**删掉该行**（进度已由 `turn=` 覆盖；精确事件进度由 ready 握手比 `event_log.size()` + 每笔 applied 逐笔比把关）。两个「更好」的替代都不行：`event_log.size()` 会让单机直调 `play_cards/player_pass` 与 `apply_event` 的指纹分开（`verify_ai_plan` B 段当场转红）；给 `GameLogger` 加「累计写入数」会被规则层大量 `log_messages.append(...)` 绕过。`PROTO_VERSION 2→3`（指纹语义变了，新旧包不能同房）。新增 `tests/verify_state_hash_ui.gd` 21 项：S0 指纹不再含 `logs=`/`events=` + 旧公式反向自检；S1 flush 前后指纹不变；S2 两端 flush 节奏不同仍同指纹；S3 主机边打边 flush vs 客人 `replay_events()` 对齐；S4 `to_snapshot()["log_count"]` UI 语义保留；S5 复现 `_host_on_ready` 场景。顺带记录：headless 里没有 UI、没人 `flush_logs()`，所以这个量恰好是常量 —— 52 套全绿也查不出，真机才暴露。全量 53 套绿 | 本次提交 |


---

## 5. 明确不做（缓到后续阶段）

| 项 | 原因 | 去向 |
|---|---|---|
| 踢人（`disconnect_peer`） | `NetTransport` 未暴露该能力 | P11-C1 收尾 / P11-D |
| 房间码 → 地址发现层 | 需要信令服务器，与 P11-C2 一起做 | P11-C2 |
| 跨 NAT（WebRTC + TURN） | 独立传输层 | P11-C2 |
| 观战者 UI（只读视角） | 协议已支持，UI 未做 | P11-D 打磨 |
| 飞牌动画的联机版 | 取 D2，先跳过 | P11-D 打磨 |
