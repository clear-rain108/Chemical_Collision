# 化学碰撞 — 程序架构与实现文档

> **版本**: 8.0  
> **日期**: 2026-07-09  
> **引擎**: Godot 4.x / GDScript

---

## 目录

1. [项目概览](#1-项目概览)
2. [文件结构](#2-文件结构)
3. [数据层](#3-数据层)
4. [逻辑层](#4-逻辑层)
5. [表现层](#5-表现层)
6. [场景结构](#6-场景结构)
7. [数据流](#7-数据流)
8. [关键算法](#8-关键算法)

---

## 1. 项目概览

"化学碰撞"是一款以元素周期表为主题的多人卡牌对战游戏。项目按 **MVC 分层**组织：

```
┌─────────────────────────────────────────┐
│                      表现层              │
│  Main.tscn  GameUI.gd                   │
│  5页UI  着色与状态渲染  按钮交互         │
│  手牌上限检查  牌库计数  卤族互化检查     │
├─────────────────────────────────────────┤
│                      逻辑层              │
│  GameManager.gd  →  规则引擎 & 牌权轮转  │
│  Utils.gd        →  牌型判定 & 化合物   │
├─────────────────────────────────────────┤
│                      数据层              │
│  CardData.gd      →  卡牌属性定义       │
│  CardDatabase.gd  →  牌库生成 & 洗牌    │
└─────────────────────────────────────────┘
```

---

## 2. 文件结构

```
chemical-1/
├── project.godot                      ← 引擎配置
├── Main.tscn                          ← 5 页场景（Start/Help_Rules/Help_Cards/Game/End）
├── scripts/
│   ├── CardData.gd                    ← 13 属性 + 16 族常量
│   ├── CardDatabase.gd                ← 28 种元素（卤族10/HOS各8/主族6/副族4）= 172 张
│   ├── GameManager.gd                 ← 规则引擎（牌权轮转、接炸链、化合物校验）
│   ├── GameUI.gd                      ← UI 控制器（着色、步骤流、AI、手牌上限、卤族互化、牌库计数）
│   └── Utils.gd                       ← 工具函数（detect_pattern、get_compound_formula、compare_cards）
├── CHEMICAL_COLLISION_GAME.md         ← 游戏设计文档 (v8.0)
├── GAMEPLAY_RULES.md                  ← 玩法规则与程序实现 (v8.0)
├── ARCHITECTURE.md                    ← 本文档 (v8.0)
├── COLORING_DOCUMENTATION.md          ← 元素着色文档 (v2.0)
└── COMPOUND_MECHANISM_COMPARISON.md   ← 化合物机制新旧对比
```

---

## 3. 数据层

### 3.1 CardDatabase.gd — 牌库

**牌张数分级**（新增常量）:

```gdscript
const HALOGEN_SYMBOLS = ["F", "Cl", "Br"]    # 卤族 10 张
const HIGH_COUNT_SYMBOLS = ["O", "S", "H"]    # 高张数 8 张
const MAIN_COPIES = 6                          # 主族 6 张
const SUB_COPIES = 4                           # 副族 4 张
const HALOGEN_COPIES = 10
const HIGH_COPIES = 8
```

**牌数分配**:
| 张数 | 数量 | 元素 |
|------|------|------|
| 10 张 | 3 种 | F, Cl, Br |
| 8 张 | 3 种 | H, O, S |
| 6 张 | 15 种 | He, Li, Be, B, C, N, Ne, Na, Mg, Al, Si, P, Ar, K, Ca |
| 4 张 | 7 种 | Cr, Mn, Fe, Co, Ni, Cu, Zn |

**总牌数**: 172 张

### 3.2 CardData.gd — 卡牌数据模型

16 族常量已覆盖第四周期副族：IA / IIA / IIIA / IVA / VA / VIA / VIIA / 0 / IB / IIB / IIIB / IVB / VB / VIB / VIIB / VIII

---

## 4. 逻辑层

### 4.1 新增：卤族互化检查

位置：`GameUI.gd` `_on_choose_compound()` 步骤 1

```gdscript
func _is_halogen_only(symbols: Array) -> bool:
    var halogen = ["F", "Cl", "Br"]
    for sym in symbols:
        if sym not in halogen:
            return false
    return true
```

选中全部为卤族元素时阻止进入化合价选择步骤，提示"卤族元素(F/Cl/Br)之间不可互相化合！请加入金属或其他非金属元素。"

---

## 5. 表现层

### 5.1 双帮助页导航

**HelpPage_Rules**（游戏规则介绍）:
- 内容：游戏规则、牌型、比大小、接牌、手牌上限
- 按钮：`[返回]` → 回到游戏页 | `[查看卡牌介绍 →]` → 跳转 HelpPage_Cards

**HelpPage_Cards**（卡牌介绍）:
- 内容：元素总览、着色对照、常用化学式、不可化合组合
- 按钮：`[返回]` → 回到游戏页 | `[← 查看规则介绍]` → 跳转 HelpPage_Rules

两个页面都使用 `HelpPage_Rules` / `HelpPage_Cards` 节点名，返回按钮位于可视区间左下方 (20-120px)。

---

## 6. 场景结构

```
Main (Control)
├── StartPage
├── HelpPage_Rules       ← 游戏规则介绍页
│   ├── [返回] 按钮       ← _on_help_back()
│   └── [查看卡牌介绍→]   ← _on_help_show_cards()
├── HelpPage_Cards       ← 卡牌介绍页
│   ├── [返回] 按钮       ← _on_help_back()
│   └── [← 查看规则介绍]   ← _on_help_show_rules()
├── GamePage             ← 深蓝背景，黑色文本
│   ├── GameBackground   ← Color(0.45,0.62,0.95)
│   ├── DeckCountLabel   ← 牌库剩余 + 手牌上限
│   ├── InfoLabel        ← 牌权状态 + 手牌数
│   ├── TableLabel       ← 桌面牌型
│   ├── HandContainer    ← HFlowContainer (6张/行)
│   ├── ActionPanel      ← 操作按钮
│   └── CardInfoLabel    ← 提示文本
└── EndPage
```

---

## 7. 关键算法

### 7.1 牌张数动态计算（CardDatabase.gd generate_deck）

```
for elem in elem_data:
    sym = elem[0]
    copies = SUB_COPIES
    if sym in HALOGEN_SYMBOLS:
        copies = HALOGEN_COPIES       # 10
    elif sym in HIGH_COUNT_SYMBOLS:
        copies = HIGH_COPIES          # 8
    elif sym not in SUBGROUP_SYMBOLS:
        copies = MAIN_COPIES          # 6
    // 副族保持 SUB_COPIES = 4
```

### 7.2 卤族互化检测（GameUI.gd _on_choose_compound）

```
选中牌型 → 提取不重复元素符号 → _is_halogen_only(symbols)?
    → Yes: 提示阻止
    → No: 继续进入化合价选择
```

---

**文档版本**: 8.0  
**最后更新**: 2026-07-09