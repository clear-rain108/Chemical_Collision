# 化学碰撞（Chemical Collision）联机架构设计文档

> 版本：v1.2 ｜ 状态：**设计定稿；P11-B 地基、P11-C1-a 传输、P11-C1-b 会话层均已实现；P11-C1-c Step 0 真机冒烟脚本已就绪**
> 适用范围：3~8 人朋友局（默认 4），跨局域网 P2P（无端口映射条件）
> 相关文档：[`ARCHITECTURE.md`](ARCHITECTURE.md)（单机架构）、[`GAMEPLAY_RULES.md`](GAMEPLAY_RULES.md)（规则）、[`UI_POLISH_PLAN.md`](UI_POLISH_PLAN.md)（UI 计划）

---

## 0. 一页速览（TL;DR）

| 问题 | 结论 |
|---|---|
| 能不能不做端口映射就联机？ | 能。但**必须有一台公网信令服务器**（极小、几乎不吃带宽），或用虚拟局域网 / 隧道工具绕开 |
| 能不能"纯 P2P、零外部依赖"？ | **不能**。对称 NAT / 手机热点 / 公司网下打洞必失败，必须中继兜底 |
| 同步方式选什么？ | **主机权威 + 事件重放 + 状态哈希校验**（不是逐帧状态同步） |
| 需要改单机逻辑吗？ | **不需要**。`GameManager` 只新增只读/事件 API，单机调用路径一行未变 |
| 推荐落地顺序？ | Tailscale 验证 → ENet 局域网 → WebRTC 跨网 → 打磨（见 §10） |
| 当前进度 | P11-B 地基已完成：种子化洗牌、牌 uid、快照、FNV 哈希、`apply_event`、传输层抽象、回环传输、新测试套件。**P11-C1-a 已完成**：`ENetTransport`（局域网 / Tailscale 直连）+ 55 项自动化测试。**P11-C1-b 已完成**：`NetSession` 房间 / 座位 / 主机权威裁决 / 两阶段冻结 / 超时托管 / 掉线保留 / token 重连 / 观战 + 111 项自动化测试。**P11-C1-c Step 0 已完成**：`tests/net_smoke.gd` 真机冒烟（3 个独立进程走真实 ENet，本机实测打完一整局 32 笔事件，三端逐笔 `state_hash` 相同、0 拒绝、0 分叉） |

本次地基交付物（对应 §13 / 附录 A）：

- `scripts/CardData.gd`：新增 `uid`（= 牌库生成下标，两端天然一致）
- `scripts/CardDatabase.gd`：`shuffle(rng_seed)` 支持确定性洗牌（默认行为不变）
- `scripts/GameManager.gd`：`init_game(..., rng_seed)` / `to_snapshot()` / `state_hash()` / `apply_event()` / `event_log`
- `scripts/net/NetProtocol.gd`、`NetTransport.gd`、`LoopbackTransport.gd`
- `tests/verify_net_foundation.gd`（8 组 54 项断言，全部通过；原有 19 套测试零回归）

P11-C1-a 追加交付物（真实网络传输层）：

- `scripts/net/ENetTransport.gd`：`ENetMultiplayerPeer` 原始包封装（不挂 `SceneMultiplayer`）
- `tests/verify_enet_transport.gd`（11 组 55 项断言，全部通过；同进程 127.0.0.1 真实 UDP，无需第二台机器）
- `scripts/net/NetTransport.gd`：补充接口契约注释（peer_id ≠ 座位号）

P11-C1-b 追加交付物（会话层）：

- `scripts/net/NetSession.gd`：房间生命周期、座位分配与 `peer_id ↔ seat` 映射、主机权威裁决与广播、两阶段（指定牌型）冻结、超时托管、掉线座位保留、token 重连、观战与满员拒绝
- `scripts/net/NetProtocol.gd`：新增 `ready / peer_left / peer_joined` 消息、`ERR_NO_PENDING / ERR_NOT_READY / ERR_ROOM_FULL / ERR_DUPLICATE_SEQ / ERR_DESYNC`、`var_to_bytes` 线格式编解码（`encode` / `decode`）
- `tests/verify_net_session.gd`（17 组 107 项断言，全部通过；真实 ENet + 3 个独立 `GameManager` 实例，指纹是真两端各自重放出来的）

---

## 1. 目标与非目标

### 1.1 是目标

| # | 目标 | 理由 |
|---|---|---|
| G1 | 3~8 人朋友局（默认 4，建房时定），房主建局、房间码加入 | 玩法定位（非公开对战）+ D17 可调座位数 |
| G2 | **零侵入**：联机代码不改变单机任何行为 | 现有 19 套测试必须继续通过 |
| G3 | 传输层可替换（ENet / WebRTC / 未来 Steam） | 环境会变（今天 Tailscale，明天 WebRTC） |
| G4 | 任何一步都可校验一致性 | 化学牌型判定复杂，静默分歧 = 灾难 |
| G5 | 顺带得到断线重连 / 回放 | 事件日志的副产品，几乎零成本 |
| G6 | AI 只在主机运行 | 复用现有 `AIPlayer`，客人不需要 AI 逻辑 |

### 1.2 不是目标

| # | 非目标 | 说明 |
|---|---|---|
| N1 | 公开匹配 / 排位 / MMR | 朋友局不需要 |
| N2 | 账号系统 / 云存档 / 内购 | 超出范围 |
| N3 | 专业反作弊 | 用**信任模型**（§8 A 档），朋友局可接受 |
| N4 | 移动端优先 | 桌面（Windows）优先 |
| N5 | 语音 / 观战 / 直播 | 不做 |
| N6 | 专用服务器托管 | 房主即服务器（listen server） |

---

## 2. 约束：为什么"纯 P2P 直连"不成立

NAT 之后的机器没有公网可达地址。让 A、B 两台机器直连只有三条路：

| 路径 | 是否可行 | 说明 |
|---|---|---|
| ① 端口映射（UPnP / 手动转发） | ❌ 本项目不可用 | 用户无法操作路由器；运营商级 NAT（CGNAT）下映射也无效 |
| ② **打洞（hole punching）** | ✅ 主路径 | 双方先各自向同一台公网信令服务器发包，服务器回告对方"我看到你的地址是 x.x.x.x:port"，两边同时向该地址发包 → NAT 临时开洞 → **数据真正点对点**，延迟最低 |
| ③ **中继（relay）** | ✅ 兜底 | 打洞失败时数据全程经服务器转发 |

**关键结论**：路径 ②③ 都以"存在一台公网信令服务器"为前提。所以：

- "完全不需要任何服务器"的 P2P 在用户网络条件下**不成立**；
- 打洞成功率经验值 80~90%（全锥形 / 限制锥形 NAT 容易成功；**对称 NAT**——校园网、公司网、手机热点常见——基本失败）；
- 因此任何承诺"100% 能连"的方案都必须准备中继，纯直连无法保证。

### 2.1 四种绕开端口映射的现实手段

| 方案 | 玩家需安装 | 公网服务器 | 延迟 | 成功率 | 定位 |
|---|---|---|---|---|---|
| **A. 虚拟局域网**（Tailscale / ZeroTier）+ ENet | 每人 1 个客户端并登录 | ❌ 不需要 | 最低（真直连） | ~99% | **P11-C1 验证首选** |
| **B. WebRTC**（DataChannel）+ 迷你信令 | 无 | ✅ 需要（可免费托管 / 免部署） | 低（直连）/ 中（TURN） | ~85% 直连 | **P11-C2 正式版** |
| **C. 隧道**（playit.gg / ngrok）+ ENet | 仅房主 | ❌ 用它的公网入口 | 中（走中继） | ~99% | 备选，房主须常开工具 |
| **D. Steam P2P**（GodotSteam） | Steam 客户端 | ❌（Valve SDR） | 中低 | ~99% | 若将来上架 Steam |

> 注：Godot 4 桌面端**不自带** WebRTC 实现，需官方 `webrtc-native` GDExtension（MIT，基于 libdatachannel，支持 4.1+，Windows/Linux/macOS/Android/iOS 各带一份库）；Web 导出走浏览器原生实现，无需插件。导出时必须为每个目标平台各带一份动态库，否则在别人机器上启动即崩。

---

## 3. 方案选型

### 3.1 决策

**分两步走，不一次到位：**

| 阶段 | 传输 | 目的 | 为什么先做这个 |
|---|---|---|---|
| **P11-C1** | ENet 直连（`ENetMultiplayerPeer`）+ 虚拟局域网 | 打通并验证"规则同步 / 手牌隐藏 / AI 只在主机跑"这些真正的难点 | 虚拟局域网把 NAT 全部绕过，调试环境最干净；改传输层以外零成本 |
| **P11-C2** | WebRTC（`WebRTCMultiplayerPeer`）+ 信令 | 正式体验："输 6 位房间码就能连" | 玩家零安装；跨 NAT 由 ICE 打洞 + TURN 兜底 |
| P11-D | 可选 Steam P2P | 若上架 Steam | Valve SDR 免费且穿透率最高 |

### 3.2 为什么用 `NetTransport` 抽象而不是直接写 ENet

- 今天用 ENet，明天换 WebRTC，上层（`NetSession` / `GameManager` / `GameUI`）**零改动**
- 测试用 `LoopbackTransport`，**不需要开端口、不需要联网**就能验证完整协议
- 每种传输的坑不同（ENet 有 `peer_id`，WebRTC 要先建 `WebRTCPeerConnection` 再挂 `WebRTCMultiplayerPeer`），把它们关在实现类里

### 3.3 信令服务器的两种落地方式

| 方式 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **零部署 MVP** | 用免费 HTTP pub/sub（如 `ntfy.sh`）交换 SDP / ICE，房间码当 topic | 一行服务器代码都不用写 | 依赖第三方可用性 / 限速；数据经第三方 |
| **自建极简信令** | 约 30~100 行 WebSocket 中转，部署到 Cloudflare Workers / Deno Deploy / 任意 VPS | 可控、可加房间码校验 | 需要一次性部署 |

推荐：先用"零部署"把 P11-C2 走通，稳定后再换成自建信令（协议层不变，只换 `SignalingClient` 实现）。

### 3.4 TURN 兜底

| 项目 | 建议 |
|---|---|
| STUN | 公共 `stun:stun.l.google.com:19302`（打洞用，免费） |
| TURN | 对称 NAT 时才需要；可用 Cloudflare 的 TURN 免费额度，或自建 `coturn`（需一台小 VPS） |
| 策略 | 先只配 STUN 试连；失败再提示"你的网络需要中继"并切 TURN 配置 |

---

## 4. 分层架构

```
┌───────────────────────────────────────────────────────────────┐
│ GameUI (Control, 现有文件，几乎不改)                           │
│   └─ ActionRouter（新增薄层）                                  │
│        ├─ 单机：直接调 GameManager（零延迟，行为与今天完全一致）│
│        └─ 联机：NetSession.submit(intent)                      │
├───────────────────────────────────────────────────────────────┤
│ NetSession (Node, 新增)：房间生命周期 / 超时 / 重连 / 广播       │
│   ├─ HostAuthority：validate_intent → apply_event → 广播       │
│   └─ ClientReplica：收 applied → apply_event → 比对 state_hash │
│   └─ 持有 GameManager 实例（主机与客人各一份，逻辑同源）         │
├───────────────────────────────────────────────────────────────┤
│ NetProtocol（新增，纯静态）：消息常量 / 意图构造 / 校验 / 裁剪   │
├───────────────────────────────────────────────────────────────┤
│ NetTransport（新增，接口）                                     │
│   ├─ LoopbackTransport（已实现：进程内回环，测试用）            │
│   ├─ ENetTransport（P11-C1）                                   │
│   └─ WebRTCTransport（P11-C2）                                 │
├───────────────────────────────────────────────────────────────┤
│ GameManager (RefCounted, 现有文件，只新增只读/事件 API)          │
│ CardDatabase / AIPlayer / CardPatterns / CompoundSolver（不变） │
└───────────────────────────────────────────────────────────────┘
```

### 4.1 依赖规则（强约束）

| 规则 | 说明 |
|---|---|
| R1 | **下层不知道上层存在**：`GameManager` 不得 `preload` 任何 `scripts/net/*` |
| R2 | `NetProtocol` 只做数据形状，不含任何网络 / 引擎调用 |
| R3 | `NetSession` 是唯一知道"主机 / 客人"区别的地方 |
| R4 | `GameUI` 不直接碰 `NetTransport`，只碰 `NetSession`（或单机时的 `GameManager`） |
| R5 | 单机路径**不加载** `scripts/net/*`（避免任何启动开销与风险） |

### 4.2 各层职责

| 层 | 有状态？ | 职责 | 不该做的事 |
|---|---|---|---|
| `GameManager` | ✅ 一局状态 | 规则判定、回合推进、快照、事件应用 | 发包、计时、UI |
| `NetProtocol` | ❌ | 消息/字段定义、意图校验、快照裁剪 | 保存房间状态 |
| `NetTransport` | ✅ 连接状态 | 建立连接、收发字节、派发连接事件 | 理解游戏语义 |
| `NetSession` | ✅ 会话状态 | 座位映射、序号、超时、断线重连、事件广播 | 规则判定（交给 GameManager） |
| `ActionRouter` | ❌ | 把 UI 动作转成"本地直接执行"或"网络意图" | 持有游戏状态 |

---

## 5. 同步模型：主机权威 + 事件重放 + 哈希校验

### 5.1 为什么不用状态同步

| 模型 | 做法 | 本项目的适用性 |
|---|---|---|
| 状态同步 | 每帧/每步广播完整状态 | 包大、需要差分、把 UI 细节（动画/选中）混进网络层 |
| **事件同步（采用）** | 只广播"谁做了什么"，各方本地跑同一套确定性逻辑 | 一局事件 300~600 条 × 几十字节；天然支持回放/重连；复用现有纯逻辑引擎 |

关键前提（已具备）：

- `GameManager` 是纯 `RefCounted`，无 Node、无 signal、无 IO → 可在任何端同步跑
- 出牌校验是纯函数式（`play_cards(...) -> int`），不依赖时间/UI
- 洗牌已可种子化（本次地基）

### 5.2 授权模型

| 模型 | 谁说了算 | 采用 |
|---|---|---|
| P2P 全对等（每人都能改状态） | 一人作弊则全员分叉 | ❌ |
| **主机权威（listen server）** | **只有主机**执行 `apply_event`，客人只重放主机广播的事件 | ✅ |
| 专用服务器 | 最公平 | ❌ 朋友局没有服务器 |

主机权威带来的确定性好处：客人**永远不会**自己决定一个动作是否合法，只服从 `applied` 消息；客人本地重放只是为了得到同一份画面与同一套手牌，并用 `state_hash` 自检。

### 5.3 一致性校验

| 机制 | 说明 |
|---|---|
| `state_hash()` | FNV-1a 32 位，对"规范化状态串"取指纹（手牌按 uid 排序 → 顺序无关；化合价字典按键排序，数组值先降序规范化 → `[3,2]` 与 `[2,3]` 同哈希） |
| 何时比对 | 每条 `applied` 后客人本地算一次，与主机下发的 `hash` 比较；握手后比一次；重连后比一次 |
| 不一致处理 | 开发期：`push_warning` + 打印 diff + 拉全量 `snapshot`；发布期：静默拉 `snapshot` 修复 |
| 为什么不用 Godot 内建 `hash()` | 其算法与整型宽度不保证跨平台/跨版本一致 |

`state_hash()` 覆盖字段：种子、当前玩家、回合数、阶段、胜者、首出标记、方向、免疫标记、族炸链（状态+持有者）、禁炸标记、顺序约束（牌型+激活+被指定的座位 `sequence_constraint_target`）、桌面（uids/牌型/出牌者/化合价）、牌库余量、每座位（名字/手牌 uid 集合/跳过标记/冷却标记/是否 AI）、日志条数。

---

## 6. 协议定义（v1）

### 6.1 消息表

| 消息 | 方向 | 字段 | 说明 |
|---|---|---|---|
| `hello` | C→S | `proto, name, app_version` | 客人打招呼 |
| `welcome` | S→C | `seat, room_code, seed, config{...}, seats[{seat,name,is_ai}]` | 分配座位 + 下发本局配置 |
| `game_start` | S→all | `seed, config, seats, hand_uids{seat:[]}`（每人只收自己那份） | 开局 |
| `intent` | C→S | `seq, type, by, ...payload` | 客户端请求一个动作 |
| `applied` | S→all | `seq, by, result, events[], hash` | 主机执行完，广播权威结果 |
| `rejected` | S→C | `seq, code` | 主机拒绝（`code` 复用 `-1..-8` 规则码 / `-100..-104` 协议码） |
| `turn` | S→all | `current, deadline_ms, seq` | 轮到谁 + 超时时刻 |
| `pending_sequence` | S→all | `by, deadline_ms` | 「顺序牌型」两阶段：等该玩家选指定牌型 |
| `snapshot` | S→C | 全量快照（经 `strip_snapshot` 按座位裁剪） | 加入 / 重连 / 失配修复 |
| `ping` / `pong` | 双向 | `t0` | RTT 显示 & 掉线判定（10s 无响应视为掉线） |
| `peer_left` / `peer_joined` | S→all | `seat, name` | 座位变化提示（是否续局由房主决定） |

### 6.2 时序

**握手**

```
客人                                    主机
 │  hello{proto,name}                    │
 │ ─────────────────────────────────────>│
 │                                       ├─ 分配座位 seat=N
 │                                       ├─ 生成 room_code / seed
 │  welcome{seat, room_code, seed, config, seats}
 │ <──────────────────────────────────────│
 │  snapshot（按座位裁剪，用于中途加入）    │
 │ <──────────────────────────────────────│
 │  ready                                 │
 │ ─────────────────────────────────────>│
 │  game_start{seed, config, seats, 本人手牌}
 │ <──────────────────────────────────────│
```

**一个动作**

```
客人(seat=2)                           主机                                其他客人
 │  intent{seq=17, type:"play", by:2, uids:[31,88], valences:{"Fe":3}}
 │ ──────────────────────────────────>│
 │                                    ├─ validate_intent → 0
 │                                    ├─ apply_event(ev) → result=0
 │                                    ├─ hash = state_hash()
 │  applied{seq=17, by:2, result:0, events:[ev], hash}
 │ <──────────────────────────────────│──────────────────────────────────>
 │ ├─ 本地 apply_event(ev)            ├─ turn{current:3,...}              │
 │ ├─ 比对 hash                       │                                     │
 │  turn{current:3, deadline_ms}      │
 │ <──────────────────────────────────│──────────────────────────────────>
```

> **混合价态（v4）的 valences 形状**：`{"Fe":[3,3,2],"O":-2}` —— 数组 = 该元素**每张牌各一个价**，
> 长度必须等于该元素在这手牌里的张数，全部降序（表示规范化，副本可互换）。
> `int` 写法（每张同价）保持不变，老客户端 / 老存档继续可用。
> `apply_event` 的 `_valences_from()` 会把 JSON 折返后的 float 数组转回 int 并重新降序，
> `state_hash()` 里同一字典的 `[3,2]` 与 `[2,3]` 指纹相同 —— 两端不会因为书写顺序误报失配。
> 回归：`tests/verify_valence_plan.gd` 第十二部分（JSON 往返 / 指纹 / 主机·客人事件重放 / 快照一致）。


**规则拒绝**

```
客人                                   主机
 │  intent{seq=18, type:"play", ...}    │
 │ ──────────────────────────────────>│
 │                                    ├─ apply_event → result = -2（牌不够大）
 │                                    ├─ 状态未变 → 不广播 applied、不写 event_log
 │  rejected{seq:18, code:-2}           │
 │ <──────────────────────────────────│
 │  → UI 复用 _handle_result(-2) 的文案（"牌不够大！"）
```

要点：

- `seq` 由客人本地单调递增，用于去重与应答匹配
- 主机只在**状态确实推进**（result >= 0）时广播 `applied` 并写 `event_log`
- 拒绝不会改变任何一方的状态 → 天然幂等

### 6.3 两阶段提交：顺序牌型

现有单机流程（`GameUI._handle_result`）：

1. `play_cards(...)` 返回 `1` → 顺序牌已打出、**牌权已经移交**（`GameManager.play_cards` 内部调用了 `next_turn()`）
2. UI 弹窗让该玩家选「下一个必须打出的牌型」
3. 选择 → `set_sequence_constraint(pattern)`；或点「跳过指定」→ 清约束 + `next_turn()`

联机映射：

```
客人A: intent{seq=9, type:"play", by:0, uids:[...]}       ← 打出顺序
主机 : apply_event → 1
主机 : applied{seq:9, result:1, events:[ev], hash}
主机 : pending_sequence{by:0, deadline_ms}               ← 只等 A 的第二步
其他客人：UI 显示「A 正在指定牌型…」，锁定操作
客人A: intent{seq=10, type:"sequence_pick", by:0, pattern:2}   （或 sequence_skip）
主机 : apply_event → 0（内部调用 set_sequence_constraint / next_turn）
主机 : applied{seq:10, ...} + turn{current:...}
```

注意：`sequence_pick` 发生在牌权已移交之后，`NetProtocol.validate_intent` 对这两类意图**跳过回合校验**，改由主机的 `pending_sequence` 状态判断归属（超时则自动 `sequence_skip`）。

### 6.4 返回码 / 错误码

| 码 | 含义 | 来源 | UI 处理 |
|---|---|---|---|
| `0` | 成功 | `GameManager` | 正常刷新 |
| `1` | 打出顺序，待指定牌型 | `GameManager` | 弹 `_show_sequence_constraint_dialog` |
| `-1` | 非法出牌 | `GameManager` | `_handle_result` 文案 |
| `-2` | 牌不够大 | `GameManager` | 同上；细分原因见 `GameManager.last_reject_reason`（打平 / 原子序数和不够 / 族炸张数不够 / 牌型压制），`_handle_result` 会拼在「牌不够大！」下面一行 |
| `-3` | 不能出族炸 | `GameManager` | 同上 |
| `-4` | 牌型不匹配 | `GameManager` | 同上 |
| `-6` | 不符合顺序指定牌型 | `GameManager` | 同上 |
| `-7` | 卤族不可互化 | `GameManager` | 同上 |
| `-8` | 元素不在本局牌库 | `GameManager` | 同上 |
| `-100` | 未知事件 / 消息类型 | `GameManager.EVENT_UNKNOWN` / `NetProtocol` | 断线 / 忽略 |
| `-101` | 事件载荷非法（uid 不存在/重复、座位越界） | `GameManager.EVENT_BAD_PAYLOAD` | 记日志并断开 |
| `-102` | 未轮到你 | `NetProtocol.ERR_NOT_YOUR_TURN` | 忽略（本地 UI 竞态） |
| `-103` | 对局已结束 | `NetProtocol.ERR_GAME_OVER` | 忽略 |
| `-104` | 座位不匹配（替别人操作） | `NetProtocol.ERR_WRONG_SEAT` | 断开（疑似作弊/错乱） |

---

## 7. 确定性要求（必须守住的红线）

### 7.1 种子化洗牌

```gdscript
# scripts/CardDatabase.gd
func shuffle(rng_seed: int = -1) -> void
```

| 参数 | 行为 | 使用场景 |
|---|---|---|
| `< 0`（默认） | 走全局 `randi()`，**与历史版本逐位一致** | 单机、教程、所有现有测试 |
| `>= 0` | 独立 `RandomNumberGenerator.seed = rng_seed` | 联机、回放、双端一致性测试 |

`GameManager.init_game(player_count, ai_count, rng_seed = -1)` 把种子记录在 `deck_seed` 上并下发给 `shuffle()`。默认值 `-1` 保证**所有既有调用点零改动**。

### 7.2 牌 uid

| 项 | 定义 |
|---|---|
| 语义 | 牌在 `generate_deck()` 产物中的下标（`0 .. 牌库张数-1`） |
| 为什么不随机 UUID | 生成顺序只取决于 `allowed_symbols`（元素限制配置），与洗牌、与运行时间都无关 → **同配置的两端天然一致**，不需要额外同步 uid 分配 |
| 用途 | 一切网络寻址（出牌 `uids`、快照 `hand_uids`、事件日志） |
| 注意 | 手工构造的卡（教程预设、单测）`uid` 保持 `0`，**不参与联机寻址**；联机局一律由 `generate_deck()` 生成 |
| 兼容 | `CardData.to_dict()` 新增 `"uid"`；`from_dict()` 缺字段时默认 `0`（旧存档可读） |

### 7.3 手牌顺序

- 手牌顺序是 **UI 偏好**（玩家可拖拽、可手动排列 `hand_manual_order`），不参与判定。
- `state_hash()` 对手牌 **按 uid 排序后** 再指纹化 → 两端手动排列不同也不会误报失配。
- 出牌用 `uids` 寻址，不依赖下标 → 顺序差异不影响正确性。
- `to_snapshot()` 保留真实顺序（重连后能还原玩家排好的手牌）。

### 7.4 禁止项清单（写联机代码时逐条自查）

| ❌ 禁止 | ✅ 替代 |
|---|---|
| `randi()` / `randf()` / `shuffle()` 无种子 | 用引擎已有的 `deck_seed` 派生的 `RandomNumberGenerator` |
| 用浮点做规则判定 | 原子序数 / 化合价等一律整型（现有代码已如此；电负性仅用于展示） |
| 依赖帧率 / 真实时间推进游戏状态 | 时间只用于超时与动画；状态推进必须由事件驱动 |
| 遍历 `Dictionary` 顺序参与判定或哈希 | 先 `keys.sort()`（见 `_sorted_pairs`） |
| 在规则层读 UI / 节点 / 文件 | 规则层保持纯数据 |
| 用 `hash()` 内建做跨端校验 | `GameManager.state_hash()`（FNV-1a 32 位，自实现） |

---

## 8. 手牌可见性：两档可选

| 档 | 做法 | 对手牌可见？ | 防作弊 | 附加成本 |
|---|---|---|---|---|
| **A. 信任模型（默认采用）** | 客人端跑**完整引擎**（所有座位手牌都在内存），UI 只渲染自己的 | ✅ 内存里能看到 | ❌ 内存修改器可读 | **0** |
| **B. 视图模型** | 客人只收 `my_hand + others.hand_count`，渲染层改为 `NetPlayerView` | ❌ | ✅ | +2~3 天，需改 UI 渲染路径 |

**决策：先 A，B 作为可选 Phase 2。** 理由：

- 朋友局（G1）是明确前提，A 的权衡可接受，并会在开始页提示"联机为朋友局信任模式"
- A 档下 `GameUI` 几乎不用改（它本来就只渲染 `get_current_player()` 的手牌）
- B 档要动 `_update_hand_buttons` / `_format_player_status` / `AIPlayer` 的输入来源，风险大、收益低

若将来做 B 档，改动点清单（仅登记，不在本次范围）：

| 文件 | 改动 |
|---|---|
| `scripts/GameManager.gd` | `players[i].hand` 只对本地座位有实体卡；他人仅 `hand_count` |
| `scripts/GameUI.gd` | 手牌渲染改读 `NetSession.my_hand_uids()`；对手区只读张数 |
| `scripts/AIPlayer.gd` | 只能在主机实例上运行（已满足） |
| `NetProtocol` | `strip_snapshot` 已按座位裁剪（本次已实现） |

---

## 9. 与现有代码的映射

### 9.1 本次已完成（P11-B 地基）

| 文件 | 改动 | 兼容性 |
|---|---|---|
| `scripts/CardData.gd` | `var uid`；`to_dict` 输出 `uid`；`from_dict` 读 `uid`（缺省 0） | 旧存档可读 |
| `scripts/CardDatabase.gd` | `generate_deck` 赋 `uid = deck.size()`；`shuffle(rng_seed = -1)` | 无参行为逐位不变 |
| `scripts/GameManager.gd` | `init_game(..., rng_seed = -1)`、`deck_seed`、`event_log`、`to_snapshot()`、`state_hash()`、`apply_event()`、`is_valid_seat()`、`get_hand_uids()` | 全是新增 + 一个带默认值的参数 |
| `scripts/net/NetProtocol.gd` | 消息常量、`make_intent`、`validate_intent`、`strip_snapshot`、`is_known_message` | 新文件，单机不加载 |
| `scripts/net/NetTransport.gd` | 传输接口（host/join/send/broadcast/poll/close + 3 个信号） | 新文件 |
| `scripts/net/LoopbackTransport.gd` | 进程内回环实现（测试用，含断线事件） | 新文件 |
| `scripts/net/ENetTransport.gd` | **P11-C1-a**：`ENetMultiplayerPeer` 原始包封装（host/join/poll/send/broadcast/close），信号维护 peer 集合 | 新文件，单机不加载 |
| `scripts/net/NetSession.gd` | **P11-C1-b**：房间生命周期、座位分配、主机权威裁决、两阶段冻结、超时托管、掉线保留、token 重连、观战 | 新文件，单机不加载 |
| `tests/verify_net_foundation.gd` | 8 组 54 项断言 | 新测试 |
| `tests/verify_enet_transport.gd` | **P11-C1-a**：11 组 55 项断言（127.0.0.1 真实 UDP 回环） | 新测试 |
| `tests/verify_net_session.gd` | **P11-C1-b**：18 组 111 项断言（真实 ENet，3 个独立 `GameManager`） | 新测试 |
| `tests/net_smoke.gd` | **P11-C1-c Step 0**：真机联机冒烟（`--host` / `--join`，3 个独立进程 + 带缓冲的逐行日志），自动出牌走 `HintAdvisor` 只读建议 | 新工具，单机不加载 |

### 9.2 客户端阶段改动（P11-C1-c：已完成）

| 文件 | 改动 | 阶段 |
|---|---|---|
| `scripts/net/ActionRouter.gd`（新）✅ | 把 `GameUI` 的 8 处出牌 / 2 处跳过收口成 `submit(intent)`（Step 1） | P11-C1 ✅ |
| `scripts/GameUI.gd` ✅ | ① ✅ 10 处动作改走 `ActionRouter`；② ✅ 联机时 AI 由主机驱动（客人显示"等待 X 行动"）；③ ✅ 新增房间页（建房 / 加入 / 本机 IP / 座位表 / 开局闸门 / 离开收尾） | P11-C1 ✅ |
| `scripts/net/WebRTCTransport.gd`（新） | `WebRTCMultiplayerPeer` + ICE + 信令客户端 | P11-C2 |
| `scripts/net/SignalingClient.gd`（新） | 零部署 MVP（ntfy.sh）或自建 WebSocket | P11-C2 |
| `scripts/net/NetSession.gd` | 接入真机 UI 前的加固项：踢人（`ENetMultiplayerPeer.disconnect_peer`，当前 `NetTransport` 未暴露）、房间码 → 地址的发现层 | P11-C1 收尾 |

### 9.3 明确不改的文件

`scripts/CardPatterns.gd`、`scripts/CompoundSolver.gd`、`scripts/PlayerManager.gd`、`scripts/GameLogger.gd`、`scripts/HintAdvisor`、所有 `.tscn` 场景结构、`project.godot`（P11-C1 之前）。

---

## 10. 分阶段路线与验收标准

| 阶段 | 内容 | 验收标准 | 预估 |
|---|---|---|---|
| **P11-B 地基** ✅ | 种子化洗牌、uid、快照、哈希、事件、传输抽象、回环、测试 | 新测试全绿；原有 19 套零回归 | 已完成 |
| **P11-A 热座** | 同机 2~3 人轮流操作（只显示当前操作者手牌） | 不开网络也能两人打完一局；切换时手牌不串 | 0.5~1 天 |
| **P11-C1-a ENet 传输** ✅ | `ENetTransport`（`ENetMultiplayerPeer` 原始包模式）+ 127.0.0.1 自动化测试 | 55 项断言全绿；41 套既有测试零回归 | 已完成 |
| **P11-C1-b 会话层** ✅ | `NetSession`（房间 / 座位 / 主机权威 / 两阶段冻结 / 托管 / 重连 / 观战）+ 真实 ENet 三方测试 | 111 项断言全绿；`state_hash` 逐事件一致 | 已完成 |
| **P11-C1-c Step 0 冒烟** ✅ | `tests/net_smoke.gd`：3 个独立进程真机联机，逐笔打印 `applied#N ... hash=H`，末尾打 `final_hash` 供三端比对 | 三端 `final_hash` 相同；本机实测整局 32 笔事件、0 拒绝、0 分叉 | 已完成 |
| **P11-C1-c Step 3 UI 联机化** ✅ | `GameUI.attach_session()` 装配口（视图归属 D6 / 热座关闭 D7 / AI 计时器门控 D8 / 结果分派 D9 / 弹窗收窗 D10 / 退出 D11）+ 10 处动作走 `ActionRouter`；`verify_ui_online` 93 项 | A 段假会话 69 项 + B 段 3 实例真 ENet 24 项全绿；单机全量零回归 | 已完成 |
| **P11-C1-c Step 4 房间页** ✅ | `GameUI._build_room_page()`（代码建页）：建房 / 加入 / 座位卡 / AI 补位 / 开局闸门 / 离开收尾；`verify_room_page` 151 项 | A 段零网络 120 项 + B 段 3 实例真 ENet 31 项（页面建房 → 2 客人加入 → 3 人 + 1 AI 开局 → 三端进牌桌）全绿；不改 `.tscn`，全量 46 套零回归 | 已完成 |
| **P11-C1-c Step 4b 人数 3~8（D17）+ 4c INTERNET/--net-trace（D18）** ✅ | `NetSession` `MIN/MAX_PLAYERS` + `seat_capacity()` / `ai_count()`；`GameUI` 座位数微调框 + 8 张座位卡按容量显隐等分 + 状态区每 4 人换行 + AI 节流按人数缩短；`export_presets.cfg` 开 INTERNET（pre1005.2）；`--net-trace` 逐笔指纹 | `verify_room_page` 186 项（含容量 8 三端真 ENet 8 玩家指纹一致）、`verify_net_session` 180 项（G20 追踪 / G21 容量边界）、全量 46 套绿；`aapt2 dump permissions` 见 INTERNET | 已完成 |
| **P11-C1 局域网** | `ActionRouter` + 房间页 + 接真机 UI；配 Tailscale 跨网直连 | 同 WiFi / Tailscale 下 3~8 人打完一整局，`state_hash` 全程一致 | 剩 ~2 天 |
| **P11-C2 跨 NAT** | `webrtc-native` 插件 + 信令 + TURN 兜底 | 异地 2 人（无端口映射）输入房间码即可开局，失配自动修复 | 3~5 天 |
| **P11-D 打磨** | 超时自动 pass、断线重连、RTT 显示、回放、房间码 UI 优化 | 拔网线 30s 内可恢复；回放可完整重现一局 | 2~3 天 |

里程碑判定（每阶段都必须同时满足）：

1. 新阶段测试套件全绿
2. 原有 19 套单机测试全绿（零回归）
3. 真窗口跑一局无脚本错误 / 无泄漏警告
4. `state_hash` 在整局中每一步都一致（开发期把它打到日志）

---

## 11. 测试策略

### 11.1 三层

| 层 | 工具 | 覆盖 | 是否需要网络 |
|---|---|---|---|
| L1 引擎确定性 | `tests/verify_net_foundation.gd` | 种子、uid、快照、哈希、事件应用、边界 | ❌ |
| L1.5 真实传输（P11-C1-a 新增） | `tests/verify_enet_transport.gd` | 真实 UDP 握手、定向/广播、8KB 分片、100 包有序、三人房间、断线、端口占用 | ❌（同进程 127.0.0.1） |
| L2 协议全流程（P11-C1 新增） | `tests/verify_net_session.gd` | 真实 ENet 三端：握手、座位、建局、事件流、拒绝路径、两阶段、托管、掉线重连、观战、满员拒绝、`ready` 指纹比对时序（111 项） | ❌（同进程 127.0.0.1） |
| L3 真网络（P11-C1-c Step 0） | `tests/net_smoke.gd` + 多开 `--headless` | 跨进程 / 跨机器的真实 UDP：座位上线、开局同步、逐笔账本、终局指纹 | ✅ |

### 11.2 运行方式

```bash
# 单个套件
godot --headless --path . --script tests/verify_net_foundation.gd

# 全部套件（Windows cmd）
for %f in (tests\verify_*.gd) do @(echo === %f === & godot --headless --path . --script %f 2>&1 | findstr TESTS)
```

（`verify_logger.gd` 只打印单条 PASS 后退出，不含 `TESTS` 汇总行，属既有行为。）

真机冒烟（3 个独立进程，最少 3 人；同机可用 `127.0.0.1` 多开）：

```bash
# 终端 1：房主（会打印本机可用 IP + 房号）
godot --headless --path . --script tests/net_smoke.gd -- --host --port 47800 --duration 60
# 终端 2 / 3：客人（把 127.0.0.1 换成房主 IP 即可跨机器）
godot --headless --path . --script tests/net_smoke.gd -- --join 127.0.0.1 --port 47800 --duration 60
```

客人要先于房主 `start_game()` 连上（房主默认等 60s）。判读：三端 `[tag] applied#N by=… type=… hash=…` 逐行一致，末尾 `SMOKE FINAL final_hash=H` 三端相同即通过；`--manual` 关掉自动出牌，改成人工出牌观察。

### 11.3 断言范式（沿用现有约定）

```gdscript
extends SceneTree

var fails: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)

func _finish() -> void:
	if fails == 0:
		print("ALL XXX TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d XXX TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)
```

### 11.4 双端一致性测试怎么造

不需要真实网络：造两个 `GameManager`（同 seed）+ 一条预置事件流，逐条 `apply_event` 并比对 `state_hash()`。`verify_net_foundation.gd._test_event_replay_consistency` 就是范本（剧本只用"必然合法"的动作：首轮单张 + 跳过，避免依赖具体牌面）。

---

## 12. 风险登记

| # | 风险 | 影响 | 概率 | 缓解 |
|---|---|---|---|---|
| R1 | 对称 NAT / 校园网打洞失败 | 连不上 | 中高 | TURN 中继兜底；先用 Tailscale 验证功能 |
| R2 | `webrtc-native` 与 Godot 4.7 的 GDExtension 兼容性未实测 | 阻塞 P11-C2 | 中 | 动工前先做 30 分钟验证：放插件 → `WebRTCPeerConnection.create_default() != null` |
| R3 | 导出漏带各平台动态库 | 别人机器启动即崩 | 中 | 导出清单写明"每个目标平台各带一份"；先在朋友机器上试跑 |
| R4 | 主机作弊（房主可改牌） | 公平性 | 高（但朋友局可接受） | 文档声明；公开对战需专用服务器（非目标） |
| R5 | 两端逻辑漂移 | 表现不一致、无法继续 | 低（有 hash 校验） | 每步 hash 比对 + 失配自动拉快照；同一版本号校验（`hello.app_version`） |
| R6 | 手牌顺序差异误报失配 | 误拉快照 | 低 | hash 对手牌 uid 排序后计算；已实现并有测试 |
| R7 | 顺序牌型两阶段被卡住（玩家掉线） | 对局停住 | 中 | `pending_sequence` 带超时，主机超时自动 `sequence_skip` |
| R8 | 人类玩家手牌达上限时 pass 需弃牌（当前由 UI 层处理） | 联机流程缺口 | 中 | P11-C1 中把 `discard_pass` 做成独立意图（`apply_event` 已支持） |
| R9 | 帧同步误用（有人把逻辑塞进 `_process`） | 不确定性 | 低 | §7.4 红线清单 + code review |
| R10 | 事件日志膨胀 | 内存 | 极低 | 一局 < 1000 条；结束即清 |

---

## 13. 决策记录（ADR 摘要）

| # | 决策 | 理由 | 替代方案为何不选 |
|---|---|---|---|
| ADR-1 | **事件同步**，非状态同步 | 包小、可回放、复用纯逻辑引擎 | 状态同步要把 UI 细节混进网络层，且差分复杂 |
| ADR-2 | **主机权威** | 无需服务器，单人决策避免分叉 | 全对等：一人作弊全盘分叉 |
| ADR-3 | **uid = 牌库生成下标** | 两端天然一致，无需分配协议 | 随机 UUID 需额外同步；自增 id 依赖调用顺序 |
| ADR-4 | **洗牌默认 `-1`（随机）** | 单机行为逐位不变，19 套测试零回归 | 默认改种子化会破坏现有随机性预期 |
| ADR-5 | **自实现 FNV-1a 32 位** | 跨平台 / 跨版本稳定 | Godot `hash()` 不保证一致 |
| ADR-6 | **手牌信任模型（A 档）** | 零成本，朋友局可接受 | 视图模型要改 UI 渲染路径，风险大 |
| ADR-7 | **传输层抽象 + 回环实现** | 可换 ENet/WebRTC/Steam；测试无需联网 | 直连写 ENet 会把协议绑死在一种传输上 |
| ADR-8 | **单机路径不加载 `scripts/net/*`** | 零启动开销、零回归风险 | 全局单例会污染单机初始化 |

---

## 附录 A：地基 API 用法（P11-B）

```gdscript
const GameManagerScript = preload("res://scripts/GameManager.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")

# 1) 确定性开局（联机：主机生成 seed 后广播给所有人）
var gm = GameManagerScript.new()
gm.element_limit_enabled = true
gm.allowed_extra_elements = ["Fe", "Cu"]
gm.init_game(4, 0, 20261101)          # 4 名人类，种子固定

# 2) 构造一笔意图并校验（主机侧）
var intent := NetProtocolScript.make_intent("play", 0, {"uids": [31, 88], "pattern": -1})
var code := NetProtocolScript.validate_intent(intent, 0, 4, gm.current_player_index, gm.is_game_over())
if code == 0:
	var result := gm.apply_event(intent)   # 0 / 1 / -1..-8 / -100 / -101

# 3) 一致性指纹 & 快照
var h: int = gm.state_hash()
var snap: Dictionary = gm.to_snapshot()
var for_seat1: Dictionary = NetProtocolScript.strip_snapshot(snap, 1)  # 他人手牌 uid 清空

# 4) 事件日志（回放 / 重连）
print(gm.event_log.size())   # 已成功推进局面的事件条数
```

## 附录 B：常见问题

**Q1：为什么不直接 P2P，非要一个服务器？**
A：NAT 后的机器没有公网地址，双方要靠公网服务器交换"你看起来是哪个地址"才能同时打洞（§2）。服务器只转发几百字节，几乎不耗带宽，但不能没有。

**Q2：客人也跑完整引擎，会不会被看牌？**
A：会（A 档信任模型）。朋友局可接受；如需防护走 B 档（§8）。

**Q3：房主断线怎么办？**
A：房主即服务器，对局结束。P11-D 可加"快照 + 事件日志移交"，让另一人接管（不保证一致则直接从快照续）。

**Q4：AI 在联机里怎么跑？**
A：只有主机跑 `AIPlayer`（复用现有 1.5s 延迟逻辑），结果作为普通事件广播。客人只显示"等待 AI 行动"。

**Q5：可以直接开房间给陌生人吗？**
A：不建议。信任模型 + 主机权威意味着房主能改牌，也没有匹配/踢人/举报机制（§1.2 N1/N3）。

**Q6：这套地基会不会拖慢单机？**
A：不会。单机路径不加载 `scripts/net/*`；`GameManager` 新增的都是按需调用的函数，`init_game(4, 3)` 等旧调用完全等价。

---

## 附录 C：ENet 传输实测结论（P11-C1-a）

> Godot 4.7.2 ｜ 2026-11 ｜ 全部在 `--headless` 下自动化验证（`tests/verify_enet_transport.gd`，55 项断言）

### C.1 必须走「原始包」模式

`ENetMultiplayerPeer` 一旦赋给 `multiplayer.multiplayer_peer`，就会被 `SceneMultiplayer` 接管，只剩 `@rpc` / 场景复制两条路，**无法收发任意 `PackedByteArray`**。本项目用的是底层的 `set_target_peer` + `put_packet` / `get_packet`，完全绕开 `SceneMultiplayer`：

```gdscript
var peer := ENetMultiplayerPeer.new()
peer.create_server(port, max_players - 1)      # 房主自己不算 client
peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
peer.set_target_peer(peer_id)                  # 定向；0 = 广播
peer.put_packet(data)

# 每帧：peer.poll() 之后
while peer.get_available_packet_count() > 0:
	var from := peer.get_packet_peer()         # 必须先取 peer，再取包
	var data := peer.get_packet()
```

### C.2 三条与 Loopback 不一致的语义（写 NetSession 之前必读）

| # | 实测差异 | 后果 | 处理 |
|---|---|---|---|
| 1 | `ENetMultiplayerPeer` **没有 `get_peers()`**（`MultiplayerPeer` 也未暴露） | 拿不到在线列表 | `ENetTransport` 用 `peer_connected` / `peer_disconnected` 信号自己维护 `_peers` 字典，`get_peers()` 返回其升序快照 |
| 2 | 客人的 `get_unique_id()` 是**随机 32 位整数**（实测 `754867515`），只有主机恒为 `1` | 沿用 Loopback 的「host=1 / client=2」假设会让座位映射全错 | `NetSession` 必须建立 `peer_id ↔ seat` 映射表，**不能拿 peer_id 当座位索引**（已写进 `NetTransport.gd` 接口契约） |
| 3 | `close()` 之后再 `poll()`，引擎刷 `ERROR: The multiplayer instance isn't currently active.` | 关房间后 UI 仍每帧 poll → 日志被刷屏 | `close()` 先把 `_peer` 置 `null` 再 `close()`；`poll()` 首行判空直接返回 |

### C.3 已验证的行为（可以放心依赖）

| 行为 | 实测结果 |
|---|---|
| 同进程内 `create_server` + 多个 `create_client("127.0.0.1", port)` | ✅ 可行，握手 ~6ms → **无需第二台机器即可自动化测试** |
| `create_client` 的返回时机 | 立即返回 0（只代表「发起」）；真正连上要等 `peer_connected`，连不上的地址也不返回错误 |
| `set_target_peer(0)` | 广播给所有已连接 peer，主机自己不会收到 |
| 8 KB 单包 | ✅ 自动分片，逐字节完整 |
| 连发 100 包 | ✅ 全部到达且严格有序（`TRANSFER_MODE_RELIABLE`） |
| 同端口二次 `create_server` | 返回 `20 (ERR_CANT_CREATE)` → `host()` 转成 `-1` |
| 客人主动 `close()` | 主机在下一次 `poll()` 收到 `peer_disconnected(uid)` |

### C.4 端口与局域网提示

- 默认端口 `47800`（`ENetTransport.DEFAULT_PORT`）：固定端口便于房主直接报给客人，随机端口对朋友局不友好。
- 测试用 `47811 / 47812 / 47813` 三个候选依次尝试，避免端口被占导致误报。
- Windows 首次监听会弹防火墙确认框；C1-d 房间页必须把「已监听 / 未监听」显示出来，否则用户点错一次就是静默失败。
- 异地联机不做打洞：直接上 Tailscale / ZeroTier，`ENetTransport` 一行不用改（见 §2.1 方案 A）。

### C.5 退出时的坑：客户端 `close()` 之后不能立刻 `quit()`

**现象**：测试跑完（全部 PASS，汇总行都打印了），进程却永远不退出 —— 内存不再变化、CPU 归零，CI 里表现为「挂起 / 超时」，看起来像是断言逻辑死循环，实际死引擎退出阶段。

**定位**：用 4 个最小脚本二分（2026-11，Godot 4.7.2 headless）：

| 脚本做的事 | 进程退出 |
|---|---|
| 只 `print` + `quit()`（不碰 ENet） | ✅ 正常 |
| `create_server`（没人连）+ `close()` + `quit()` | ✅ 正常 |
| `create_server` + `create_client` 连上 + `close()` + **立刻** `quit()` | ❌ **卡死** |
| 同上，但 `close()` 后 `OS.delay_msec(800)` 再 `quit()` | ✅ 正常 |

**结论**：ENet 客户端断开后的底层收尾是**异步**的，`ENetMultiplayerPeer.close()` 返回时还有未完成的断开 / 线程收尾；此时立刻让引擎退出会挂住。主机侧 + 无连接两种情况都不受影响，所以「小测试不卡、大测试卡」极具迷惑性。

**写法**：网络测试的 `_finish()` 在 `quit()` 前留一小段：

```gdscript
func _finish() -> void:
	...
	OS.delay_msec(600)      # ENet 客户端 close() 后异步收尾，立刻 quit 会卡死
	quit(1 if fails > 0 else 0)
```

`tests/verify_net_session.gd` 已按此实现（见文件头注释）。

---

## 附录 D：`NetSession` 实现说明（P11-C1-b）

> 源码：`scripts/net/NetSession.gd` ｜ 测试：`tests/verify_net_session.gd`（107 项）
> 层次：`GameManager`（纯逻辑）→ `NetSession`（房间 / 权威 / 一致性）→ `NetTransport`（ENet / Loopback）

### D.1 状态机

```
role:  NONE ──start_host──► HOST
       NONE ──start_client─► CLIENT
state: IDLE ─► CONNECTING ─► LOBBY ─► PLAYING ─► OVER
                              └──────── CLOSED（任何阶段都可进入，不可逆）
```

- `LOBBY` 之前（`IDLE/CONNECTING`）**不分配座位**：主机只在收到 `hello` 时才写座位表，所以「发起连接」≠「进房间」。
- `PLAYING` 之后不再接纳新玩家：`_assign_new_seat()` 直接返回 `WATCHER_SEAT`，把后到的人变成观战者（否则座位表与 `GameManager` 的 `player_count` 会错位，`apply_event` 的越界校验立刻炸）。

### D.2 消息流

| 消息 | 方向 | 用途 |
|---|---|---|
| `hello` | C→S | 报昵称 + `proto` + `token`（空 = 首次，非空 = 申请恢复座位） |
| `welcome` | S→C | 座位、token、房间码、座位表、配置、`resume` 标记、（重连时）两阶段剩余时间 |
| `snapshot` | S→C | 已开局则紧跟 `welcome` 发：`seed` + `event_log` + `hash` + 座位表 |
| `game_start` | S→all | 开局：`seed` / `player_count` / `ai_count` / 配置 / 座位表 / `hash` |
| `intent` | C→S | `{seq, ev}`；`seq` 单调递增，主机用它去重 |
| `applied` | S→all | 权威结果：`{by, result, ev, hash}`，客人**只重放这条** |
| `rejected` | S→C | `{seq, code}`；`ERR_ROOM_FULL` 会让客人本地 `close()` |
| `pending_sequence` | S→all | `{seat, remain_ms}`；`seat = -1` 表示窗口关闭 |
| `ready` | C→S | 快照重放完，附 `{hash, events}`；主机只在 `events` 与本地相同（同一时刻）时才比对，否则就是拿旧指纹比新局面 —— 实测会稳定误报 `ERR_DESYNC` |
| `peer_left` / `peer_joined` | S→all | 座位掉线（座位保留）/ 座位（重新）上线 |

线格式：`[magic "CHM1" u32][body_len u32][var_to_bytes(dict)]`。用 `var_to_bytes` 而不是 JSON —— JSON 会把 `uid` / `seq` / `hash` 全变成 float，漏一处就是「`uid` 12.0 找不到手牌」的静默 bug。8 字节头让畸形包在 `bytes_to_var` 之前就被丢掉，不会让引擎刷 `Invalid data`。

### D.3 座位与身份

- **`peer_id ≠ seat`**：ENet 客人的 `peer_id` 是随机 32 位整数，`NetSession` 维护双向表 `_peer_seat` / `_seat_peer`，并用 `seat_of_peer()` 作为唯一入口。
- **token**：每座位一枚 32 位 hex 随机串。掉线时座位、昵称、token 全部保留（只把状态置 `OFFLINE`），带 token 重连进来 `_seat_of_token_if_offline()` 命中即恢复原座位，**token 不换发**（客人不必更新本地存档）。
- **不许顶号**：座位 `ONLINE` 时任何 token 都不作数，走「新面孔」分支。
- **观战者**：`seat = -1`，收全量广播但不能提交（`can_submit()` 为假，主机侧还会用 `ERR_NOT_READY` 兜底）。
- **ENet 名额要留余量**：`create_server(port, max_players - 1)` 时名额正好等于座位数，会让「掉线重连（旧连接未释放）+ 观战」被 ENet 直接拒掉，表现为永远 `CONNECTING`、上层连拒绝消息都发不出去。故 `host()` 传 `max_players + RECONNECT_SLACK(4)`。

### D.4 主机裁决（唯一权威）

```
_on_intent(peer, msg):
  seat = seat_of_peer(peer)              # 不信任 payload 里的 by
  seat == -1                 → ERR_NOT_READY      （观战者）
  seq <= 该座位已用最大 seq  → ERR_DUPLICATE_SEQ  （重投 / 重放）
  state != PLAYING           → ERR_NOT_READY
  by != seat                 → ERR_WRONG_SEAT     （谁也不许替别人出牌）
  两阶段窗口开着 且 不是等待方 → ERR_NOT_YOUR_TURN
  两阶段窗口开着 且 是普通意图 → ERR_BAD_EVENT
  无窗口却发 sequence_*       → ERR_NO_PENDING
  其余 → GameManager.apply_event → result
result < 0 → 回 rejected（局面不动、不进 event_log）
result >= 0 → 记 hash → 广播 applied（含 ev 与 hash）→ 本地 state_applied
```

客人永远不自己 apply 自己的意图，只重放主机 `applied` 里那条 `ev`，然后把本地 `state_hash()` 与报文里的 `hash` 对比；不一致即 `desync_detected`（`NetProtocol.ERR_DESYNC`），且只报一次。

### D.5 两阶段冻结（顺序牌型）

`GameManager.apply_event` 用 `result == 1` 表示「打出了顺序牌型，牌权已经移交，但约束还没指定」。这中间的空档就是最容易分叉的地方：若客人这时又能出牌，双方对「谁是当前玩家」的理解会立刻分叉。

处理：
1. `result == 1` → 主机开窗 `{seat, deadline}`，广播 `pending_sequence{seat, remain_ms}`；
2. 窗口内 `_validate_for_seat` **只**接受等待方本人的 `sequence_pick` / `sequence_skip`，其余一律 `ERR_NOT_YOUR_TURN` / `ERR_BAD_EVENT`；
3. 等待方结算完（`was == seat` 且 result != 1）→ 关窗，广播 `pending_sequence{seat: -1}` + `sequence_cleared`；
4. 超时（默认 15s）→ 主机代替该座位 `sequence_skip`（即「托管」），成功后正常广播；万一跳票也被规则拒绝，则强制关窗并 `error_raised` —— **宁可少一条规则，也不能让整局卡死**；
5. 等待方掉线 → 立刻走同一套托管，不等超时。

UI 侧只需要：`is_my_sequence_pending()` 为真时弹出「指定牌型」面板，`sequence_pending(seat, ms)` 的 `ms` 就是倒计时。

### D.6 重连与恢复

`GameManager` **没有** `from_snapshot()`，所以恢复一律是「同 `seed` `init_game` + 重放 `event_log`」：

```gdscript
_apply_config_and_init()                      # init_game(player_count, ai_count, seed)
game.replay_events(msg["event_log"])          # 逐条 apply，日志条数也一起重建
_last_hash = game.state_hash()                # 与主机 compare
```

日志条数一并重建这点很关键：`state_hash()` 里含 `event_log` 计数，用 `to_snapshot()` 反序列化（如果存在）也对不上。恢复后客人回 `ready{hash, events}`，主机用它核对。

`events` 不能省：`ready` 是**快照重放完成那一刻**发出的，等主机 `poll()` 到这条消息，主机自己往往已经多打了几笔事件。只带 `hash` 就只能拿「旧指纹」比「新局面」，每局开局必报 `ERR_DESYNC`（真机三进程实测，见 D.10）。现在的规则是：**只有 `events` 与主机本地 `event_log.size()` 相同（同一时刻）才比对指纹**，否则只记 ready。真正逐笔把关的是客人侧 `_client_on_applied` 里的事件后比对。

### D.7 已知限制

| # | 限制 | 说明 |
|---|---|---|
| 1 | 不会踢人 | `NetTransport` 只暴露 `close()`，没有 `disconnect_peer`。满员拒绝时靠客人自己收到 `ERR_ROOM_FULL` 后 `close()`；恶意端挂着不关会占一个连接名额（有 `RECONNECT_SLACK` 兜着） |
| 2 | 房间码只是标识 | 4 位数字便于口头报号，**不做发现**：客人仍需知道 IP（局域网 / Tailscale） |
| 3 | 掉线座位永不回收 | 宽限期只清计时器，座位与 token 一直保留（`reconnect_grace_ms` 到点后不再提示）。要在「一局结束后」腾座位得由 UI 层显式重置房间 |
| 4 | 信任模型 A 档 | 客人本地有完整 `GameManager`，技术上能看牌；主机能改牌（§8、R4） |
| 5 | 主机掉线 = 对局结束 | 客人侧收到与主机断开就直接 `close("与主机的连接已断开")` |

### D.8 用法

```gdscript
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")

var session = NetSessionScript.new()
session.setup(game_manager, ENetTransportScript.new())   # GameManager 由外部持有
session.seat_assigned.connect(func(seat): ...)
session.state_applied.connect(func(ev, r): refresh_table())
session.sequence_pending.connect(func(seat, ms): show_pick_panel(seat, ms))
session.session_closed.connect(func(reason): back_to_menu(reason))

# 房主
session.start_host(47800, 4, "小明")
session.start_game(4, 0)          # 座位都 ready 之后

# 客人（token 非空 = 带重连凭据回来）
session.start_client("192.168.1.7", 47800, "小红")
session.start_client_resume("192.168.1.7", 47800, saved_token, "小红")

# 渲染 / 逻辑帧里各一次
session.poll()

# 提交意图：主机直接裁决，客人发出去等广播（本地不改局面）
session.submit("play", {"uids": [12, 44], "pattern": -1})
session.skip_sequence()
```

### D.9 测试怎么写的（可复用经验）

- **手工 pump，不用帧循环**：`_pump(peers, cond, timeout)` 里循环 `for p in peers: p["s"].poll()` + `OS.delay_msec(3)`，直到条件成立或超时。断言里的等待都是「等某个可观测状态」，不是睡固定时长。
- **每个端点一个独立 `GameManager`**：三份 `GameManager` 各持一份牌库，`state_hash()` 一致才是真一致（共享一个对象是自欺欺人）。
- **真实 ENet，不是 Loopback**：顺序牌窗口、掉线重连、观战、满员拒绝都需要真实 `peer_id` 与真实断开语义，Loopback 一对一测不出来。
- **直接驱动内部状态机**：两阶段相关的断言用 `_update_pending_after_apply(seat, result)` 直接开窗，不去赌「手上正好有顺序牌」；`by` 伪造 / 重号用 `transport.send_to()` 发原始包才做得到。

### D.10 真机三进程冒烟抓到的两个坑（P11-C1-c Step 0）

`tests/net_smoke.gd` 第一次多开真机跑，抓到的两个问题都不是「网络问题」，而是**协议语义**问题：

| # | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | 每局开局房主必报两条 `ERR_DESYNC：座位 N 重建后指纹不一致`，可三端 `final_hash` 其实一样 | `ready` 只带 `hash`，而它是「快照重放完那一刻」发出的；等主机 `poll()` 到，主机自己往往已经多打了几笔 —— 拿旧指纹比新局面，100% 误报 | `ready` 加 `events`（该指纹对应第几笔事件），主机只在 `events == event_log.size()` 时比对；逐笔把关交给客人侧 `_client_on_applied`（回归断言：G18） |
| 2 | 只推进 1 笔事件就卡住，客人刷出 1596 条 `intent_rejected` | 冒烟脚本自己「瞎试单张」：客人 `submit()` 恒返回 0（本地不裁决），于是它在同一张非法牌上无限重试 | 自动出牌改用 `HintAdvisor.suggest(game)`（和「提示」按钮同一套只读判定），把返回的 `indices / pattern / valence` 直接转成意图 |

教训：**写联机脚本前先想清楚「谁的返回值能当结果」** —— 主机 `submit()` 返回裁决码，客人只返回「已发出」。任何靠返回码做自适应重试的逻辑，在联机版本里都必须改成「等 `state_applied` / `intent_rejected` 信号」。

同一次冒烟也顺手确认了「三端逐笔账本」这套判读方式好用：每端自己决策（房主出 `H+K` 族炸、客人出 `H+Na` / `AlN` 化合物），但 `applied#N by=… type=… hash=…` 三端逐行完全相同，32 笔事件打完一整局、0 拒绝、0 分叉。真机联调就看这三行末尾的 `final_hash` 是否一致。
- **退出要留余量**：见附录 C.5。

### D.11 房间页接线说明（P11-C1-c Step 4）

房间页整页由 `GameUI._build_room_page()` 代码生成（D5：不改 `Main.tscn`），挂在 `start_page` 下且默认 `visible = false` —— **不点「联机对战」就一行都不会执行**（单机红线）。

**节点树（全部可 `_start_child(name)` 递归取到，便于测试）**

```
StartPage
├─ StartButton / RoomEntryBtn / TutorialBtn / ExitButton   ← 开始页那一行（Step 4 把 260 宽拆成 124+124）
└─ RoomPage                        (RoomBg / RoomBand 背景 + ‹ 返回)
   ├─ RoomTitle / RoomSubtitle    ← 副标题写死 D14：「房号仅用于辨认，客人需填房主 IP」
   ├─ RoomHostCard                ← 昵称 RoomHostNameEdit / 端口 RoomPortSpin / RoomHostIpLabel /
   │                                 RoomCreateBtn / RoomCodeLabel
   ├─ RoomJoinCard                ← RoomJoinNameEdit / RoomJoinPortSpin / RoomAddrEdit /
   │                                 RoomJoinBtn / RoomLeaveBtn
   ├─ RoomSeatsPanel              ← 最多 8 张 RoomSeatCard_i（RoomSeatName_i / RoomSeatState_i），按容量显隐
   ├─ RoomHintLabel               ← 操作反馈（「xx 加入了」「座位不足…」）
   ├─ RoomAiSpin                  ← 0 ~ (capacity - 在线人类)
   ├─ RoomSeatSpin                ← 3~8 座位数（建房前可调，进房后锁定）
   └─ RoomStartBtn                ← 房主才可用（D12 闸门）
```

座位卡**一次建 8 张，只按容量显隐 + 重排**（D17）：容量只在建房前变（3~8），重建节点既麻烦又让测试取节点不稳（名字恒为 `RoomSeatCard_i` / `RoomSeatName_i` / `RoomSeatState_i`）。

| 容量 | 几何 | 昵称字号 |
|---|---|---|
| 3~4 | 沿用老位置 `24 + i×256`，每张 240×122（手感 / 老截图不变） | 20 |
| 5~8 | 一行等分：`w = floor((1012 - (n-1)×8) / n)`，间距 8；n=8 → 119px/张，右边缘 1032 ≤ 1036 | 16 + `clip_text` |

`_room_layout_seats(capacity)` 是唯一的几何入口，`_room_refresh()` 每次都调它（幂等）；状态文案在窄卡上退化成短词（「掉线·保留」），否则 119px 一定被裁成半句。

**开始页入场名单**（`START_INTRO_ORDER`，`GameUI.gd:1428`）——**在开始页加按钮必须同步登记**：

```gdscript
const START_INTRO_ORDER := [
	"StartTitle", "StartSubtitle", "StartAccent", "StartMeta", "DecorCards",
	"SettingsCard", "StartRuleHint", "RoomEntryBtn", "StartButton", "TutorialBtn", "ExitButton",
]
```

`_animate_page_intro()` 只认这个名单：名单里的节点会被摆成 `modulate.a = 0` + `position.y + 14`，然后按 `i × 50ms` 错峰淡入上浮；**不在名单里的节点什么都不做** —— 页面级淡入（`_fade_in_page`，0.2s）一结束，它就以终态"抢先"出现。Step 4 的 `RoomEntryBtn` 就这么漏过一次，肉眼现象是「这颗按钮没有入场动画，别的按钮还在淡入它已经定住了」。回归断言在 `verify_room_page._test_intro_animation()`：① 开始页直接子节点里的 `Button` 必须全部在名单里；② 名单里没有失效名字；③ `RoomEntryBtn` 排在 `StartButton` 之前；④ 真回一次开始页，首帧 `a≈0` 且 `y≈500`，播完 `a≈1` 且落回 486。

**`_room_refresh()` 是唯一的派生点**（任何 `room_changed` / AI 数值变化 / 开关页都调它）：

| 派生项 | 规则 |
|---|---|
| 座位卡张数 | `capacity = _room_seat_capacity()`（会话 `seat_capacity()` / 未建房时取微调框值），只露前 capacity 张并重排 |
| 座位名 / 状态 | 人类按 `seat_name(i)`，`online == false` → 「掉线中 · 座位保留」（窄卡「掉线·保留」）；AI 排在人类之后 → 「AI k」+「AI 托管」 |
| 房号 | `"房号 " + room_code`（空则「房号 ----」） |
| 本机 IP | `_room_local_ips()` 过滤 IPv6 / `127.*` / `169.254.*`，空则提示用 127.0.0.1 自测 |
| AI 上限 | `maxi(0, capacity - 在线人类数)`；`max_value` 压小后 Range 会把 `value` 一起压回 |
| 座位数微调框 | 值 = capacity；进房间后 `editable = false`（容量在建房时定死，客人只读显示房主的设置） |
| 三颗按钮 | 进房间后「创建 / 加入」禁用、「离开」可用；开局按钮文本 = `开始对局` / `等待房主开始` / `开始对局 · N/capacity 座位` |

**开局闸门是纯函数**（`_room_start_block_reason(online_humans, ai_count, is_host, room_state, offline_seats = 0, capacity = ROOM_DEFAULT_SEATS)`，返回 `""` 才放行）：非房主 → 「等待房主开始」；`PLAYING` → 「对局已开始」；非 `LOBBY` → 「房间未就绪」；`total < 3` / `> capacity` → 座位数不足 / 超限；有掉线座位 → 等重连。**不看 `all_seats_ready()`**（D12：大厅里它恒为 false）。`capacity` 带默认值 4，所以老的 5 参数调用照样编译、语义不变（`verify_room_page` 的纯函数段就是这么逐格喂边界的）。

**收尾只有一条路**：`_room_teardown()` = `close(reason)` → `attach_session(null)` → 丢掉 `players` 为空的大厅 `GameManager` → 清提示 → `_room_refresh()`；`_room_closing` 闸门防止 `close()` 同步回的 `session_closed` 递归进来。`_room_leave()` / `_close_room_page()` / `_show_start_page()` 都走它。

**测试踩到的三个坑**（`verify_room_page.gd` 里已绕开）：

1. 开始页入场补间会把子节点 `position.y` 先 +14 再落回，量几何前必须等它播完（`_settle_start_page()`），且比较用距离容差（`_vec_eq()`）而不是 `==`，收尾会留下 1e-4 级残差。
2. 卡片里的控件不是页的直接子节点（`RoomCreateBtn` 在 `RoomHostCard` 里、`RoomSeatName_i` 在 `RoomSeatsPanel/RoomSeatCard_i` 里），断言一律走 `_start_child()` 递归查找，别用 `page.get_node_or_null("RoomCreateBtn")`。
3. 3 个在线人类**已经够开局**（D15 下限是 3），B 段别再断言「3 人 + 0 AI 被拦」——要拦只能靠 2 人或掉线座位。
4. 容量 ≥5 时座位卡几何会变（等分 / 字号 / clip_text）：断言卡宽、卡位、可见张数一律按 `capacity` 算，别写死 240。

### D.12 房间人数 3~8（D17）与诊断开关 --net-trace（D18）

**为什么原来只有 4**：规则层一直支持 3~8（`PlayerManager.MIN_PLAYERS = 3` / `MAX_PLAYERS = 8`，开局页单机选项也是 3~8、牌库 182 张够 8 人各 22 张），只有联机层在 `NetSession.start_host()` / `start_game()` 里把人数 `clampi(..., 2, 4)`，房间页又把 `ROOM_MAX_SEATS` 写死成 4。

**现在的链路**

| 环节 | 行为 |
|---|---|
| 建房 | `GameUI._room_start_host()` 取 `_room_seat_capacity()`（微调框 3~8，默认 `ROOM_DEFAULT_SEATS = 4`）→ `s.max_players = capacity` → `start_host(port, capacity, nm)`，后者自己再 clamp 一次 `[MIN_PLAYERS, MAX_PLAYERS]` |
| ENet 名额 | `capacity + RECONNECT_SLACK(4)`：容量 8 → 12 个连接名额，重连 / 观战不会被 ENet 直接拒 |
| 下发 | welcome 带 `max_players`，客人 `_client_on_welcome()` 覆盖自己的 `max_players` → `seat_capacity()` 两端一致 |
| 开局 | `start_game(total, ai)` 里 `_player_count = clampi(total, 3, 8)`；容量 8 + 5 AI = 8 人 |
| 改容量 | 只在建房前；进房后微调框 `editable = false`。**中途改会让「ENet 名额 / 满员拒绝 / 座位卡张数」三处判断前后矛盾**，所以不提供 |

**6~8 人牌桌的状态区约束**：`InfoLabel` 只有 460×88 / 14px / 最多 4 行（`INFO_LABEL_MAX_LINES`），下面是 y=152 的 `TableLabel`。`_format_player_status()` 因此改成：名字链每 `PLAYER_STATUS_PER_LINE = 4` 人强制换行；AI 手牌行同样每 4 条换行；两者加起来若已占满 4 行，「补充规则 / 方向」不再追加（宁可少显示次要信息，也不能压到桌面行）。3~4 人时输出与旧版逐字相同。

**AI 节流按人数缩短**（`GameUI._net_ai_delay()`）：默认 1.2s，`ai_count >= 3` → 0.8s，`>= 5` → 0.6s。7 个 AI 一轮从 8.4s 压到约 4.2s。

**`--net-trace`（D18）**

```bat
:: 桌面双开（拓扑 A：手机当房主时，PC 两开当客人）
godot --path . --net-trace --position 0,0
godot --path . --net-trace --position 1200,0
:: Android：命令行参数走 intent extra 不方便，默认在 UI 里断开再连即可；
:: 需要抓时用 adb shell am start 附 --es ... 或在导出预设里带参数
adb logcat -s godot:V
```

每笔权威事件一行，主机 / 客人各一份：

```
[net] HOST seat=0 tick=4 ev=pass hash=12a5f271
[net] CLIENT seat=0 tick=4 ev=pass hash=12a5f271
```

`tick` = 本地 `event_log.size()`，`hash` = `state_hash()` 的低 32 位。**两端从第一笔开始逐行对齐**：第一行 `tick`/`hash` 就对不上 → 开局配置 / 洗牌分叉；中间某行开始不同 → 那一笔的 `ev` 就是元凶；出现 `CLIENT mismatch` / `DESYNC` 行则是逐笔比对已经失败（`_client_on_applied` 里判定）。`trace_log` 是同批行的内存副本（上限 512 行，`enable_trace(false)` 清空），无头测试直接断言它，不必抓 stdout。

**Android 权限**：ENet 要建 UDP socket，APK 必须有 `android.permission.INTERNET`。`export_presets.cfg` 里跑 `permissions/internet=false` 时，表现是「房间建得起来、客人永远 CONNECTING」，且 logcat 里没有权限拒绝的显式报错 —— 这是 `pre1005.1` 真机联调卡住的真因。导出后一定要复核：

```bat
aapt2 dump permissions <apk>   :: 必须同时看到 INTERNET 与 VIBRATE
```

### D.13 真机三个体验问题的收口：大厅 AI 数 / 房主收房 / 心跳失联（D19 · D20 · D21）

`chemical-pre1005.3-debug.apk` 三人真机局暴露的问题，本质是**同一件事的三个切面**：大厅里的状态没有唯一真值，会话终止也没有可靠通知。

| 真机现象 | 真因 | 修法（决策） |
|---|---|---|
| 客人也能改 AI 数，改完两边不一致 | AI 数只活在 `RoomAiSpin` 这个控件里，`NetSession` 完全不知道它的存在 | 大厅 AI 数搬进会话（D19）：`NetSession.lobby_ai`，房主唯一可写 |
| 房主把空位补成 AI，客人座位卡还是「空位」 | 同上 —— 客人那份控件没人给它写值 | `MSG_LOBBY` 广播 + welcome 带 `ai_count`（D19） |
| 房主退出，客人牌桌还停在「等待 X 行动…」 | ① 客人侧从来没登记「座位 0 ↔ 主机 peer」，`_on_peer_disconnected` 直接当陌生 peer 忽略；② BYE 包在引擎关服时被连队列一起清掉 | 先因优先判主机 + BYE 兜底 + 底层失活立刻收尾（D20） |
| 房主杀进程 / 断网，客人同样卡住 | ENet 客人在服务端消失时**不保证**收到 `peer_disconnected`，只能等到 ENet 自己的超时（几十秒～几分钟） | 心跳 12s 兜底 + `_reap_inactive` 立刻派发（D21） |

#### D19：大厅 AI 补位数以会话为准

| 环节 | 行为 |
|---|---|
| 存储 | `NetSession.lobby_ai`（默认 0）。**只由房主写**，客人读同一份 |
| 写入 | `set_lobby_ai(n)`：非 `HOST` 或非 `LOBBY` **原值返回、什么也不做**；房主写入时 clamp 到 `[0, lobby_ai_cap()]`，`lobby_ai_cap() = seat_capacity() - online_humans()` |
| 下发 | 变了就 `_host_broadcast_lobby()` → `MSG_LOBBY{ai_count, max_players, seats}`；`welcome` 也带 `ai_count`，**新进来的人一步到位**，不用等下一轮广播 |
| 接收 | `_client_on_lobby()` 只认 `peer_id == HOST_PEER_ID` 且 `state != PLAYING`（开局后 AI 数由 `game_start` 定，中途再变会和已落地的玩家数打架） |
| 开局 | `start_game()` 里 `lobby_ai = _ai_count`：大厅里选的值就地变成本局 AI 数，房间页重进时显示同一个数 |
| 有人加入 | `_bind_peer()` 里先 `lobby_ai = clampi(lobby_ai, 0, lobby_ai_cap())` 再广播 —— 真人不许被 AI 顶掉 |
| 界面 | `_room_refresh()` 读 `net_session.lobby_ai` 写进微调框（`_room_ai_sync` 挡住 `value_changed` 回推），客人 `editable = false`：能点却改不动，比根本点不动更误导 |

`has_method("set_lobby_ai")` 是真的兜底，不是摆设：`verify_room_page` 的 `RoomFake` 刻意只实现用到的接口，缺这个方法时房间页退回「本地微调框说了算」的老行为，不会炸。

#### D20：房主收房，客人当场知道

`NetSession.close(reason)` 的主机分支做三件事，顺序不能换：

```gdscript
state = State.CLOSED                                   # ① 先关闸：之后回放的包一律被守卫挡掉
_broadcast({"type": MSG_BYE, "reason": reason})        # ② 广播
transport.poll()                                       #    补 poll 一次把队列刷出去，再关服
transport.close()
```

`transport.poll()` 那一行是关键：只 `broadcast` 不 `poll`，包还躺在 ENet 发送队列里，紧跟着的 `close()` 会把它一起丢掉。客人侧 `_client_on_bye()` → `close("房主结束了本局")`，UI 侧钉一句常驻提示。

**但 BYE 只是锦上添花**。实测（Godot 4.7.2，同一台机器）：房主 `close()` 之后，客人那端的 `ENetMultiplayerPeer` 往往已经是「状态 `DISCONNECTED` + 收包队列被清空」，BYE 根本没机会进 `NetSession`。所以真正兜底的是下一条。

#### 客人侧掉线的三条路（按生效顺序）

| 顺序 | 触发 | 代码 | 时延 |
|---|---|---|---|
| 1 | 底层 ENet 被引擎置为未激活（房主 `close()` / 杀进程 / 断网） | `ENetTransport.poll()` 发现 `_was_connected and get_connection_status() == CONNECTION_DISCONNECTED` → `_reap_inactive()` 补派发一次 `disconnected` | 同一帧 |
| 2 | 收到由 `close()` 刷出的 BYE | `NetSession._client_on_bye()` | 同一帧（能到的话） |
| 3 | 12 秒一个包都没收到 | `NetSession._poll_timeouts()` → `_client_check_heartbeat()` | `heartbeat_timeout_ms` |

两个坑写在这里免得后人再踩：

1. **`_on_peer_disconnected()` 必须在查座位表之前判「客人 + peer 1」。** 客人的 `_peer_seat` / `_seat_peer` 只由主机侧维护（座位是主机分配的），查表只会得到 `WATCHER_SEAT` 被当成陌生 peer 忽略 —— 这正是 D20 之前「房主退出、客人一直等待」的真因，光加 BYE 是修不掉的。
2. **`_reap_inactive()` 里先摘 `_peer` 再 `peer.close()`**，并且要把**已经收进队列的包先搬进 `_pending`** 再补发 `disconnected`。抢在补发前面 drain，客人拿到的就是「房主结束了本局」；顺序反了就只能给笼统的「与主机的连接已断开」。

`_was_connected` 用来区分「连上后又断了」和「IP 写错、根本没连上」：后者必须留给界面自己的 8 秒连接超时提示，不然一 `poll()` 就把会话关掉，用户连原因都看不到。

#### D21：心跳（异常退出 / 丢包的最后一道网）

房主在对局中每 `heartbeat_ms = 1000` 广播一条 `MSG_PING`；客人任何包（含 ping）都刷新 `_last_rx_ms`，超过 `heartbeat_timeout_ms = 12000` 没刷新就 `close("与主机的连接已断开（心跳超时 12 秒）")`。12 秒是「比 ENet 自己的超时短一个数量级、又不至于把一次卡顿判成掉线」的折中；测试把它压到 400ms 跑（G24）。

心跳**不参与任何裁决**：它只更新 `_last_rx_ms` 与 `disconnected` 判定，不进 `event_log`、不进 `state_hash`，所以不会引入新的分叉面。

#### 界面：终止提示要钉住，不能被回合文本盖掉

`GameUI` 的四处改动：

| 改动 | 理由 |
|---|---|
| `_net_over_notice`（`session_closed` / `desync_detected` 时写入） | 只弹 toast 的话 2.5 秒后就只剩「等待 X 行动…」，看起来像卡死 —— 真机反馈的就是这个 |
| `_update_card_info_label()` 一进来先看 `_net_over_notice`，非空就显示 `⚠ <原因>` 并**直接 return** | 卡牌信息栏每帧都在按回合重算，晚一步就被覆盖 |
| `_show_center_warning(text, sticky = true)` | sticky 不挂自动消失计时器；`_warning_seq` 自增让上一条未到期的计时器自行作废 |
| `_clear_net_over_notice()` | 回开始页 / 单机新局 / 联机开局 / 离开房间四个入口共用，避免下一局顶着上一局的告警 |

#### 测试

| 套件 | 新增 | 覆盖 |
|---|---|---|
| `verify_net_session` G22（19 项） | 大厅 AI 数 | clamp 到 `容量 - 在线人类`、客人同步、客人 `set_lobby_ai` 是空操作且污染不了房主、第三人加入后上限收紧、`welcome.ai_count` 一步到位、开局后 `lobby_ai == ai_count` 且三端指纹一致 |
| `verify_net_session` G23（14 项） | 收房 / 关服两条路 | ① 传输层发 BYE → 客人 `close("房主结束了本局")`；② `host.close()` → 客人 0ms 内收尾（原因二选一），两条都不许误报分叉 |
| `verify_net_session` G24（8 项） | 心跳 | 阈值压到 400ms、房主不再 `poll()`（模拟杀进程）、客人在 400ms 后自己关会话且原因是心跳超时、房主端状态不受影响 |
| `verify_room_page` 5c（10 项） | 客人只读 | 房主改 → 回推会话 → 座位卡长 AI；会话值变 → 微调框同步且不回推；客人 `editable = false`、硬改被挡回 |
| `verify_ui_online` 9b（5 项）+ 分叉（3 项） | 提示常驻 | `session_closed` 后 `_net_over_notice` / sticky toast / 卡牌信息栏 `⚠ …`，整页刷新后仍是终止提示；分叉同样钉住；`_clear_net_over_notice()` 后回到回合文本 |

现状：`verify_net_session` 221 项、`verify_room_page` 199 项、`verify_ui_online` 101 项，全绿。

真机判读顺序：客人改 AI 数点不动 → 房主补 2 个 AI 客人立刻看到 `AI 1 / AI 2` → 房主页点「离开房间」客人 1 秒内出现 `⚠ 联机已结束` → 换成房主直接杀进程，客人应在同一帧收尾（拿不到就等 12 秒心跳，仍应出现同样提示）。
