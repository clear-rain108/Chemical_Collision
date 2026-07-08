# ⚗️ 化学碰撞 (Chemical Collision) — 游戏设计文档

> **版本**: 5.1  
> **日期**: 2026-07-08  
> **引擎**: Godot 4.x  
> **语言**: GDScript  
> **当前状态**: 全功能完成（含出牌比大小 + 轮次逻辑 + 族炸接炸链）

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [卡牌系统](#3-卡牌系统)
4. [牌库系统](#4-牌库系统)
5. [游戏管理器](#5-游戏管理器)
6. [UI 系统](#6-ui-系统)
7. [工具函数（牌型系统）](#7-工具函数牌型系统)
8. [化合物系统 —— 多元素支持](#8-化合物系统--多元素支持)
9. [族炸系统](#9-族炸系统)
10. [比大小规则](#10-比大小规则)
11. [场景配置](#11-场景配置)
12. [UI 页面说明](#12-ui-页面说明)
13. [逻辑链路](#13-逻辑链路)
14. [着色规则](#14-着色规则)
15. [扩展方向](#15-扩展方向)

---

## 1. 项目概览

"化学碰撞"是一款以化学元素周期表为主题的多人卡牌对战游戏。

### 核心特性

| 特性 | 说明 |
|------|------|
| **牌库规模** | 108 张牌，前三周期 18 种元素各 6 张 |
| **玩家数量** | 3~8 人（1 人类 + N AI，开始页可配置） |
| **初始手牌** | 每人 8 张 |
| **牌型系统** | 3 种牌型：**单质** / **化合物** / **族炸** |
| **出牌规则** | 必须比桌面牌更大才能出牌（起手者/族炸除外） |
| **化合物规则** | 多元素化合价匹配，金属优先正价，电荷平衡严格校验 |
| **族炸机制** | 同族 ≥2 张不同元素 → 抢夺牌权，无论大小都能打出 |
| **接炸链** | 族炸后顺时针询问接炸，无人接则出炸者自由出牌 |
| **AI 对手** | 内置 AI，按候选优先顺序出牌，完全复用 `play_cards` 后端 |
| **UI 着色** | H 浅蓝、O 蓝色、N 蓝紫、C/B/Si/S 黄色、P 红白、卤族绿色、稀有气体白色 |

### 技术约束

- 不使用 `class_name`，全部通过 `preload` 加载依赖
- UI 根节点为 `Control`
- `init_game()` 返回 `bool`，参数非法时回退默认值
- Godot 4.3+ 兼容

---

## 2. 文件结构

```
chemical-1/
├── project.godot                  # 引擎配置（主场景 Main.tscn）
├── Main.tscn                      # 主场景（4 页：Start/Game/Help/End）
├── icon.svg                       # 项目图标
├── scripts/
│   ├── CardData.gd                # 卡牌数据结构（13 个属性 + 序列化）
│   ├── CardDatabase.gd            # 牌库生成（18 种 × 6 张 = 108） + 洗牌 + 抽牌
│   ├── GameManager.gd             # 多人管理 + 回合轮转 + 出牌比大小 + Pass 轮次 + 接炸链
│   ├── GameUI.gd                  # 主界面控制（手牌按钮 / AI 候选 / 着色 / 圆形状态 / 复合步骤）
│   └── Utils.gd                   # 工具函数（牌型判定 / 多元素化合物 / 比大小 / skip_clan_bomb）
├── CHEMICAL_COLLISION_GAME.md     # 本文档（v5.1）
├── GAMEPLAY_RULES.md              # 玩法规则与程序实现文档（v5.0）
└── COMPOUND_MECHANISM_COMPARISON.md  # 化合物机制新旧对比
```

---

## 3. 卡牌系统

### 3.1 CardData.gd

每张卡牌表示一个化学元素，包含以下 13 个属性：

| 属性 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `symbol` | String | 元素符号 | `"Na"` |
| `name_cn` | String | 中文名称 | `"钠"` |
| `name_en` | String | 英文名称 | `"Sodium"` |
| `atomic_number` | int | 原子序数 | `11` |
| `group` | String | 所属族 | `"IA"` |
| `period` | int | 周期 | `3` |
| `element_type` | String | 元素类型 | `"金属"` / `"非金属"` / `"准金属"` / `"稀有气体"` |
| `single_form` | String | 单质形态 | `"固体"` / `"液体"` / `"气体"` / `"人造"` |
| `valence_electrons` | int | 最外层电子数 | `1` |
| `common_valence` | Array | 常见化合价列表 | `[1]` / `[-2, 4, 6]` |
| `electronegativity` | float | 电负性 | `0.93` |
| `atomic_weight` | float | 相对原子质量 | `22.99` |
| `description` | String | 描述文本 | `"活泼的碱金属"` |

### 3.2 族常量定义

```
IA, IIA, IIIA, IVA, VA, VIA, VIIA, 0        ← 主族 + 稀有气体
IIIB, IVB, VB, VIB, VIIB, VIII, IB, IIB      ← 副族
```

---

## 4. 牌库系统

### 4.1 CardDatabase.gd

牌库包含 **前三周期 18 种元素**（从 ¹H 到 ¹⁸Ar），每种 6 张，共 108 张。

| 周期 | 元素 |
|------|------|
| 第 1 周期 | H(氢), He(氦) |
| 第 2 周期 | Li(锂), Be(铍), B(硼), C(碳), N(氮), O(氧), F(氟), Ne(氖) |
| 第 3 周期 | Na(钠), Mg(镁), Al(铝), Si(硅), P(磷), S(硫), Cl(氯), Ar(氩) |

---

## 5. 游戏管理器

### 5.1 GameManager.gd

#### 枚举

```gdscript
enum PlayResult { OK(0), NOT_STRONGER(-2), INVALID_PATTERN(-1), CANT_BOMB(-3), TYPE_MISMATCH(-4) }
enum GamePhase { INIT, PLAYING, GAME_OVER }
```

#### 核心函数

```
init_game(player_count, ai_count) → bool
  ├── 验证参数（3 ≤ player ≤ 8, ai < player）
  ├── CardDatabase → generate_deck() → shuffle()
  ├── 创建 PlayerInfo 数组 → 每人发 8 张
  └── phase = PLAYING, is_round_starter = true

play_cards(player_index, cards, custom_valences={}) → int
  ├── detect_pattern(cards, skip_bomb) → custom_valences 存在时跳过族炸检测
  ├── 非起手者 & 族炸冷却 & 比大小检查
  ├── **化合物比例校验**（remove_cards 之前）：ratio_ok 必须为 true
  ├── 族炸 → 启动接炸链，检查胜利
  └── OK → 切换回合

player_pass(player_index)
  ├── 接炸模式：跳过不抽牌
  └── 正常模式：抽 1 张 → next_turn()
```

#### 接炸链

```
族炸 → clan_bomb_chain_active=true, owner=player
  → _intercept_next() 顺时针询问非 owner 玩家
  → 所有非 owner 已 pass → _finish_clan_bomb_chain()
  → 清桌面，owner 自由出牌
```

#### 族炸冷却

打出族炸 → `clan_bomb_cooling=true`  
打出化合物 → `clan_bomb_cooling=false`  
状态显示为 `❄` 图标

---

## 6. UI 系统

### 6.1 Main.tscn — 4 页布局

```
Main (Control)
├── StartPage          ← 标题 + SpinBox(3–8 玩家, 1–7 AI) + Start Game 按钮
├── HelpPage           ← 游戏规则 + 牌型示例 + Back 按钮
├── GamePage           ← 游戏主界面
│   ├── InfoLabel      ← 圆形状态（● 玩家1 ◄ → ● AI1 ❄ → ...）
│   ├── TableLabel     ← 桌面牌型 + 免疫/接炸状态
│   ├── HandContainer  ← 手牌按钮（金属灰/非金属绿/稀有气体白/特殊着色）
│   ├── ActionPanel    ← step0:出牌+跳过 / step1:单质+化合物+族炸+返回 / step2:化合价选择
│   ├── HintButton     ← 切换提示显示
│   ├── HelpBtn        ← 打开帮助页
│   ├── QuitButton     ← 退出到结束页
│   ├── CardInfoLabel  ← 提示文本（屏幕中右位置）
│   └── LogLabel       ← 游戏日志
└── EndPage            ← 获胜者 + Return 按钮
```

### 6.2 交互流程

**人类玩家回合**：
1. 点击手牌按钮选中/取消（黄色 `✓`）
2. 点击 "出牌(选牌型)" → step1（选单质/化合物/族炸）
3. 化合物模式 → step2（为每种元素选化合价 → 确认打出）
4. 点击 "跳过" → Pass

**AI 玩家回合**：
1. 1.5s 延迟 → `_ai_try_play()` 生成候选
2. 族炸 → 化合物 → 双原子分子 → 单质单张
3. 全部过不了 → Pass

### 6.3 圆形状态显示

```
● 玩家 1 ◄  →  ● AI 1 ❄  →  ● AI 2 ⏸  →  ● AI 3
```

- `●` = 玩家节点
- `→` = 顺时针方向
- `◄` = 当前回合
- `❄` = 禁炸冷却
- `⏸` = 已跳过

---

## 7. 工具函数（牌型系统）

### 7.1 牌型枚举

```gdscript
enum CardPattern { ELEMENT, COMPOUND, CLAN_BOMB }
```

### 7.2 牌型判定

```
detect_pattern(cards, skip_clan_bomb=false):
  1. 1 张 → ELEMENT
  2. 2 张同元素 & H/N/O/F/Cl → ELEMENT（双原子分子）
  3. skip_clan_bomb=false & 同族 ≥2 不同元素 → CLAN_BOMB
  4. 化合价可配平 → COMPOUND
  5. 否则 → -1（非法）
```

> `skip_clan_bomb` 标志：当 `custom_valences.size() >= 2` 时设为 true，强制走化合物路径。

---

## 8. 化合物系统 —— 多元素支持

### 8.1 规则

| 约束 | 说明 |
|------|------|
| 元素数量 | ≥2 种 |
| 化合价 | 存在正价 + 负价 |
| 稀有气体 | 不能参与 |
| 2 元素 | GCD 最简比（`rp = nv/g`, `rn = pv/g`） |
| 3+ 元素 | 每种恰好 1 张 + 总电荷 = 0 |
| 金属优先 | 金属作为正价（阳离子） |

### 8.2 比例校验（play_cards 中）

```gdscript
// 在 remove_cards 之前调用
if pattern == COMPOUND:
	var fi = get_compound_formula(cards, custom_valences)
	if not fi.is_empty() and not fi.get("ratio_ok", false):
		return -1  // 拒绝出牌
```

### 8.3 玩家化合物流程

```
选牌 → "合成化合物" → 为每种元素选化合价 → 确认打出
  → 按 GCD 比例精确收集牌张 → play_cards(cards, custom_valences)
```

---

## 9. 族炸系统

### 9.1 规则

| 条件 | 说明 |
|------|------|
| 元素 | ≥2 张不同元素，全部同族 |
| 等级 | 3 张族炸 > 2 张族炸（不论族序数） |
| 冷却 | 打出族炸后直到打出化合物前不能再出族炸 |
| 接炸 | 顺时针询问，接炸需出更大的族炸 |

### 9.2 族炸示例

| 手牌 | 族 | 类型 | 有效 |
|------|-----|------|------|
| H + Li | IA | 2 张族炸 | ✅ |
| He + Ne + Ar | 0 | 3 张族炸 | ✅ |
| H + H | IA | - | ❌ 需要不同元素 |
| Na + Cl | 不同族 | - | ❌ 不同族 |

---

## 10. 比大小规则

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

### 接牌规则

```
自由出牌 → 任意牌型
桌面单质 → 只能出更大的单质/族炸
桌面化合物 → 只能出更大的化合物/族炸
  例外：溢出化合物（牌数 > 玩家数）→ 免疫！只能出族炸
族炸 → 进入接炸链（只能出族炸）
```

---

## 11. 场景配置

```ini
[application]
config/name="Chemical1"
run/main_scene="res://Main.tscn"
config/icon="res://icon.svg"
```

- 启动场景：`Main.tscn`
- 渲染模式：D3D12（Windows）
- 物理引擎：Jolt Physics

---

## 12. UI 页面说明

| 页面 | 功能 |
|------|------|
| StartPage | 标题 + 玩家人数 SpinBox(3–8) + AI 人数 SpinBox(1–7) + "Start Game" |
| HelpPage | 牌型示例 + 接牌规则 + 接炸规则 |
| GamePage | 完整游戏界面（圆形状态/手牌/操作面板/日志/提示） |
| EndPage | 获胜者显示 + "Return" 回到开始页 |

---

## 13. 逻辑链路

```
Start Page → 选择人数 → Start Game
  ↓
GameManager.init_game(total, ai) → 108 张牌洗牌 → 发牌
  ↓
回合循环:
  _refresh_ui() → 圆形状态 + 桌面信息 + 手牌按钮
  _update_card_info_label() → 提示当前可出牌型
  人类操作 → step0 选牌 → step1 选牌型 → step2 化合价(化合物模式)
  AI 操作 → _ai_try_play() → 候选遍历 play_cards()
  play_cards() → detect_pattern + 比大小 + 化合物比例校验
  族炸 → 接炸链 → 无人接 → 出炸者自由出牌
  Pass → 抽 1 张 → next_turn()
  手牌 = 0 → GAME_OVER → End Page
```

---

## 14. 着色规则

| 元素/组 | 颜色 | RGB |
|---------|------|-----|
| H | 浅蓝 | `(0.4, 0.7, 1.0)` |
| O | 蓝色 | `(0.0, 0.3, 1.0)` |
| N | 蓝紫 | `(0.4, 0.2, 0.8)` |
| C, B, Si, S | 黄色 | `(1.0, 0.9, 0.1)` |
| P | 红白 | `(1.0, 0.85, 0.85)` |
| 卤族 (F, Cl) | 绿色 | `(0.0, 0.7, 0.2)` |
| 其余金属 | 灰色 | `(0.5, 0.5, 0.5)` |
| 其余非金属/准金属 | 绿色 | `(0.0, 0.7, 0.2)` |
| 稀有气体 | 白色 | `(0.95, 0.95, 0.95)` |
| 选中 | 黄色 | `(1.0, 1.0, 0.0)` |

---

## 15. 扩展方向

- 角色系统：不同初始手牌/特殊技能
- 网络联机：多人实时对战
- 动画&音效：族炸特效、出牌动画
- 牌面美术：元素图标/插画

---

**文档版本**: 5.1  
**最后更新**: 2026-07-08  
**适用引擎**: Godot 4.3+
