# 化学碰撞（Chemical Collision）联机架构设计文档

> 版本：v1.0 ｜ 状态：**设计定稿，地基（P11-B）已实现**
> 适用范围：3~4 人朋友局，跨局域网 P2P（无端口映射条件）
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
| 当前进度 | P11-B 地基已完成：种子化洗牌、牌 uid、快照、FNV 哈希、`apply_event`、传输层抽象、回环传输、新测试套件 |

本次地基交付物（对应 §13 / 附录 A）：

- `scripts/CardData.gd`：新增 `uid`（= 牌库生成下标，两端天然一致）
- `scripts/CardDatabase.gd`：`shuffle(rng_seed)` 支持确定性洗牌（默认行为不变）
- `scripts/GameManager.gd`：`init_game(..., rng_seed)` / `to_snapshot()` / `state_hash()` / `apply_event()` / `event_log`
- `scripts/net/NetProtocol.gd`、`NetTransport.gd`、`LoopbackTransport.gd`
- `tests/verify_net_foundation.gd`（8 组 54 项断言，全部通过；原有 19 套测试零回归）

---

## 1. 目标与非目标

### 1.1 是目标

| # | 目标 | 理由 |
|---|---|---|
| G1 | 3~4 人朋友局，房主建局、房间码加入 | 玩法定位（非公开对战） |
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
| `state_hash()` | FNV-1a 32 位，对"规范化状态串"取指纹（手牌按 uid 排序 → 顺序无关；化合价字典按键排序） |
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
| `-2` | 牌不够大 | `GameManager` | 同上 |
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
| `tests/verify_net_foundation.gd` | 8 组 54 项断言 | 新测试 |

### 9.2 后续阶段改动（未开始）

| 文件 | 改动 | 阶段 |
|---|---|---|
| `scripts/net/ENetTransport.gd`（新） | `ENetMultiplayerPeer` 封装 | P11-C1 |
| `scripts/net/NetSession.gd`（新） | 房间生命周期、协议编解码、超时、重连 | P11-C1 |
| `scripts/net/ActionRouter.gd`（新） | 把 `GameUI` 的 8 处出牌 / 2 处跳过收口成 `submit(intent)` | P11-C1 |
| `scripts/GameUI.gd` | ① 10 处动作改走 `ActionRouter`；② 联机时 AI 由主机驱动（客人显示"等待 X 行动"）；③ 新增房间页（建局 / 加入 / 房间码 / 座位列表） | P11-C1 |
| `scripts/net/WebRTCTransport.gd`（新） | `WebRTCMultiplayerPeer` + ICE + 信令客户端 | P11-C2 |
| `scripts/net/SignalingClient.gd`（新） | 零部署 MVP（ntfy.sh）或自建 WebSocket | P11-C2 |
| `tests/verify_net_session.gd`（新） | 用 `LoopbackTransport` 跑完整握手 + 一局全流程 + 断线重连 | P11-C1 |

### 9.3 明确不改的文件

`scripts/CardPatterns.gd`、`scripts/CompoundSolver.gd`、`scripts/PlayerManager.gd`、`scripts/GameLogger.gd`、`scripts/HintAdvisor`、所有 `.tscn` 场景结构、`project.godot`（P11-C1 之前）。

---

## 10. 分阶段路线与验收标准

| 阶段 | 内容 | 验收标准 | 预估 |
|---|---|---|---|
| **P11-B 地基** ✅ | 种子化洗牌、uid、快照、哈希、事件、传输抽象、回环、测试 | 新测试全绿；原有 19 套零回归 | 已完成 |
| **P11-A 热座** | 同机 2~3 人轮流操作（只显示当前操作者手牌） | 不开网络也能两人打完一局；切换时手牌不串 | 0.5~1 天 |
| **P11-C1 局域网** | `ENetTransport` + `NetSession` + 房间页 + 主机权威；配 Tailscale 跨网直连 | 同 WiFi / Tailscale 下 3~4 人打完一整局，`state_hash` 全程一致 | 3~5 天 |
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
| L2 协议全流程（P11-C1 新增） | `tests/verify_net_session.gd` + `LoopbackTransport` | 握手、建局、一局事件流、拒绝路径、断线重连 | ❌（进程内回环） |
| L3 真网络 | 手动 / 双开客户端 | 实际 NAT、延迟、丢包、平台差异 | ✅ |

### 11.2 运行方式

```bash
# 单个套件
godot --headless --path . --script tests/verify_net_foundation.gd

# 全部套件（Windows cmd）
for %f in (tests\verify_*.gd) do @(echo === %f === & godot --headless --path . --script %f 2>&1 | findstr TESTS)
```

（`verify_logger.gd` 只打印单条 PASS 后退出，不含 `TESTS` 汇总行，属既有行为。）

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
