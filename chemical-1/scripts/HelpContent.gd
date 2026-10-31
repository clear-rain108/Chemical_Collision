# ============================================================
# HelpContent.gd - 帮助中心文案与结构（P5）
# 职责：3 个 tab 的卡片数据（纯数据，不含任何 UI 逻辑）
# 与 TutorialUI.gd 同风格：extends RefCounted + static，便于单测与后续改文案
#
# 行格式：{"k": kind, "t": 文本}
#   sub  卡内小标题（15px 深蓝灰）
#   p    正文（14px）
#   li   条目（14px，自动加「·」前缀）
#   ex   示例 / 化学式（13px 灰）
#   warn 禁止项 / 警示（14px 红）
#   gap  空行（8px）
#   demo 迷你卡示例行（图鉴专用）：{"k": "demo", "cards": [{sym, label}, ...]}
#
# 卡片格式：{"title": 标题, "accent": 强调色, "lines": [行...]}
# tab 格式：{"id", "label", "layout": "grid2"|"cards", "cards": [...]}
# ============================================================

extends RefCounted

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardDataScript = preload("res://scripts/CardData.gd")

# ---- 强调色（卡片左侧色条）----
const ACCENT_BLUE := Color(0.176, 0.478, 0.702, 1.0)     # 目标 / 流程
const ACCENT_GREEN := Color(0.235, 0.545, 0.353, 1.0)    # 牌型 / 比较
const ACCENT_RED := Color(0.753, 0.224, 0.169, 1.0)      # 禁止 / 特例
const ACCENT_ORANGE := Color(0.878, 0.541, 0.145, 1.0)   # 上限 / 弃牌
const ACCENT_PURPLE := Color(0.545, 0.404, 0.686, 1.0)   # 补充规则
const ACCENT_GRAY := Color(0.451, 0.498, 0.565, 1.0)     # 图例 / 统计


# ============================================================
# 一、行构造辅助（写数据时更短、少出错）
# ============================================================
static func _p(t: String) -> Dictionary:
	return {"k": "p", "t": t}

static func _sub(t: String) -> Dictionary:
	return {"k": "sub", "t": t}

static func _li(t: String) -> Dictionary:
	return {"k": "li", "t": t}

static func _ex(t: String) -> Dictionary:
	return {"k": "ex", "t": t}

static func _warn(t: String) -> Dictionary:
	return {"k": "warn", "t": t}

static func _gap() -> Dictionary:
	return {"k": "gap"}

static func _demo(syms: Array) -> Dictionary:
	return {"k": "demo", "cards": syms}

static func _c(title: String, accent: Color, lines: Array) -> Dictionary:
	return {"title": title, "accent": accent, "lines": lines}


# ============================================================
# 二、三个 tab 的元信息与内容
# ============================================================
static func get_tabs() -> Array:
	return [
		{"id": "rules", "label": "游戏规则", "layout": "grid2", "cards": get_rule_cards()},
		{"id": "cards", "label": "卡牌图鉴", "layout": "cards", "cards": get_card_cards(), "grid_after": 1},
		{"id": "supp", "label": "补充规则", "layout": "grid2", "cards": get_supp_cards()},
	]


static func get_tab_labels() -> Array:
	var out: Array = []
	for t in get_tabs():
		out.append(t.get("label", ""))
	return out


# -------- Tab 1：游戏规则（面向第一次上手，最关键的放最前）--------
static func get_rule_cards() -> Array:
	return [
		_c("怎么赢", ACCENT_BLUE, [
			_p("先把自己手牌全部打完的人获胜。"),
			_li("出牌顺序顺时针，轮到你时必须出比桌面上更大的牌"),
			_li("出不了牌就「跳过」并抽 1 张"),
			_gap(),
			_sub("记住这两句就够了"),
			_ex("打光手牌 = 赢；出不了 = 跳过抽 1 张"),
		]),
		_c("一回合做什么", ACCENT_BLUE, [
			_li("① 点选手牌（可多选，再点一次取消）"),
			_li("② 点「出牌(选牌型)」"),
			_li("③ 选单质 / 化合物 / 族炸 / 顺序"),
			_li("④ 出牌成功 → 牌权轮到下一位"),
			_gap(),
			_sub("出不了牌时"),
			_li("点「跳过」→ 抽 1 张 → 轮到下一位"),
			_warn("手牌达到上限时不能跳过，必须弃 1 张（见「跳过与弃牌」）"),
		]),
		_c("三种牌型", ACCENT_GREEN, [
			_sub("单质 ELEMENT"),
			_li("1 张任意元素牌；或 2 张同元素的双原子分子"),
			_ex("H₂ / N₂ / O₂ / F₂ / Cl₂"),
			_gap(),
			_sub("化合物 COMPOUND"),
			_li("≥2 种不同元素，化合价能配平"),
			_li("金属取正价、非金属取负价，两元素取最简整数比"),
			_ex("Na⁺ + Cl⁻ → NaCl；Al³⁺ + O²⁻ → Al₂O₃"),
			_gap(),
			_sub("族炸 CLAN BOMB"),
			_li("≥2 张同族的不同元素，张数越多越大"),
			_ex("H + Li（IA 族 2 张）；He + Ne + Ar（0 族 3 张）"),
			_warn("打出族炸后进入冷却 ❄，必须用化合物解除，期间不能再出族炸"),
		]),
		_c("怎么比大小", ACCENT_GREEN, [
			_p("牌型优先：族炸 > 有机物 > 化合物 > 单质"),
			_li("同牌型比「原子序数和」——越小越强"),
			_ex("He(序数和 2) 能压过 O₂(8+8=16)"),
			_li("序数和相同时比原子质量和——越大越弱"),
			_li("顺序牌型不参与比大小（见「补充规则」）"),
		]),
		_c("怎么接牌", ACCENT_GREEN, [
			_li("桌面空 → 任意牌型自由出"),
			_li("桌面是单质 → 只能接更大的单质，或族炸"),
			_li("桌面是化合物 → 只能接更大的化合物，或族炸"),
			_li("族炸可以接任何牌型（越级压牌）"),
			_gap(),
			_sub("接炸"),
			_li("族炸打出后，顺时针询问所有人是否接更大的族炸"),
			_li("接炸成功者成为桌面主人；不接的人抽 1 张并标记 ⏸"),
			_li("接炸期间只能出族炸"),
			_warn("溢出化合物（张数 ≥ 玩家数）免疫所有接牌，包括族炸"),
		]),
		_c("跳过与弃牌", ACCENT_ORANGE, [
			_sub("跳过"),
			_li("出不了牌时点「跳过」，抽 1 张，轮到下一位"),
			_gap(),
			_sub("手牌上限"),
			_li("上限 = min(玩家数 × 4, 18)"),
			_ex("4 人 → 16 张；5 人 → 18 张；6~8 人 → 18 张"),
			_gap(),
			_sub("到达上限后"),
			_li("不能跳过，必须选 1 张弃置"),
			_li("弃置后标记 ⏸，牌权轮转"),
			_li("降到上限以下即恢复正常"),
		]),
		_c("卤族特例", ACCENT_RED, [
			_p("F、Cl、Br、I 是卤族元素。"),
			_warn("卤族之间不能互相化合！"),
			_ex("✗ F+Cl、✗ F+Br、✗ Cl+Br、✗ Cl+I"),
			_li("卤族只能和金属、或其他非金属化合"),
			_ex("✓ Na+F → NaF；✓ Ca+Cl → CaCl₂；✓ Fe+Br → FeBr₂"),
			_gap(),
			_sub("例外"),
			_li("F+Cl 等同族组合作为「族炸」打出不受此限制"),
			_li("可在开始页勾选「允许卤族互化」放开化合物限制"),
		]),
		_c("牌库构成", ACCENT_GRAY, [
			_li("29 种元素（前四周期 + 碘），共 182 张"),
			_li("卤族 4 种（F/Cl/Br/I）× 10 = 40 张"),
			_li("H、O、S 各 8 张 = 24 张"),
			_li("其余主族 15 种 × 6 = 90 张"),
			_li("副族 7 种（Cr/Mn/Fe/Co/Ni/Cu/Zn）× 4 = 28 张"),
			_ex("40 + 24 + 90 + 28 = 182 张"),
		]),
		_c("图标说明", ACCENT_GRAY, [
			_li("▶ 当前该谁行动"),
			_li("❄ 该玩家处于族炸冷却"),
			_li("⏸ 该玩家本回合已跳过"),
			_li("黄色高亮：你已选中的手牌"),
			_li("灰色卡牌：紧凑牌面（牌多时自动收缩）"),
		]),
	]


# -------- Tab 2：卡牌图鉴（迷你卡网格由 UI 层按 get_element_cards() 生成）--------
static func get_card_cards() -> Array:
	return [
		_c("怎么读一张牌", ACCENT_ORANGE, [
			_li("左上角：原子序数（比大小时按它求和）"),
			_li("右上角：所属族（能否组成族炸看这里）"),
			_li("中间大字：元素符号，颜色代表元素类别"),
			_li("其下依次是中文名、常见化合价"),
			_li("左下角：相对原子质量（序数和打平时的裁判）"),
			_gap(),
			_sub("看三张典型牌"),
			_demo(["Na", "O", "Cl"]),
		]),
		_c("全部 29 种元素", ACCENT_GRAY, [
			_p("按周期排列，卡牌下方数字为该元素在牌库中的张数。"),
			_ex("卤族 ×10 · H/O/S ×8 · 主族 ×6 · 副族 ×4 · 合计 182 张"),
		]),
		_c("族速查", ACCENT_BLUE, [
			_sub("主族（可组族炸）"),
			_li("IA 族：H / Li / Na / K"),
			_li("IIA 族：Be / Mg / Ca"),
			_li("IIIA 族：B / Al"),
			_li("IVA 族：C / Si"),
			_li("VA 族：N / P"),
			_li("VIA 族：O / S"),
			_li("VIIA 族（卤素）：F / Cl / Br / I"),
			_li("0 族（稀有气体）：He / Ne / Ar"),
			_gap(),
			_sub("副族"),
			_li("VIB：Cr；VIIB：Mn"),
			_li("VIII：Fe / Co / Ni"),
			_li("IB：Cu；IIB：Zn"),
		]),
		_c("类别速查", ACCENT_GREEN, [
			_li("金属：Na/Mg/Al/K/Ca 与全部副族 → 取正价"),
			_li("非金属：H/B/C/N/O/P/S/F/Cl/Br/I → 取负价（H 可正可负）"),
			_li("准金属：B / Si → 按非金属取负价"),
			_li("稀有气体：He/Ne/Ar → 不能形成化合物"),
			_warn("卤族之间（F/Cl/Br/I）互不化合"),
		]),
	]


# -------- Tab 3：补充规则（对应开始页的三个独立开关：有机物胜利 / 顺序牌型 / 允许卤族互化）--------
static func get_supp_cards() -> Array:
	return [
		_c("有机物胜利", ACCENT_PURPLE, [
			_p("打出有机物立即获胜！"),
			_li("需在开始页勾选「有机物胜利规则」才会启用"),
			_gap(),
			_sub("认可的有机物"),
			_li("甲烷 CH₄、乙烷 C₂H₆、丙烷 C₃H₈"),
			_li("单一卤代物：烷烃中 1 个 H 被 F/Cl/Br 取代"),
			_ex("CH₃Cl（甲烷取代 1 个 H）"),
			_warn("卤代物只能含一种卤素元素"),
			_gap(),
			_sub("牌力"),
			_p("族炸 > 有机物 > 化合物 > 单质"),
		]),
		_c("顺序牌型", ACCENT_PURPLE, [
			_li("≥3 张连续原子序数的牌"),
			_ex("H(1) + He(2) + Li(3)；B(5) + C(6) + N(7) + O(8)"),
			_li("顺序不比大小，可直接压过桌面任何牌"),
			_li("打出后抢走牌权，由你指定下一位必须出的牌型"),
			_li("需在开始页勾选「顺序牌型规则」才可用"),
		]),
		_c("顺序四特性", ACCENT_PURPLE, [
			_sub("① 没有大小比较"),
			_li("可以抢走桌面任何牌的牌权"),
			_gap(),
			_sub("② 方向反转"),
			_li("打出顺序后，出牌方向反转（顺时针 ↔ 逆时针）"),
			_gap(),
			_sub("③ 指定牌型"),
			_li("弹出对话框，选定下一家必须打的牌型"),
			_warn("不按指定牌型出 → 罚抽 2 张并跳过本回合"),
			_gap(),
			_sub("④ 只约束下一家"),
			_li("再下一家恢复自由出牌"),
		]),
		_c("族炸打断", ACCENT_RED, [
			_li("族炸可以打断顺序牌型的约束"),
			_li("族炸打出后，顺序约束立即解除"),
			_li("接炸流程照常进行"),
			_warn("处于族炸冷却 ❄ 的玩家不能接炸"),
		]),
		_c("允许卤族互化", ACCENT_PURPLE, [
			_p("默认关闭：F/Cl/Br/I 之间不能互相化合。"),
			_li("勾选后，卤素之间可以组成化合物"),
			_ex("Cl⁺¹ + F⁻¹ → ClF（一氟化氯）"),
			_gap(),
			_sub("只放开「化合物」"),
			_li("族炸不受影响：F+Cl 当族炸打出本来就不是化合"),
			_li("不勾选时 AI 与「提示」同样不会给出卤素互化化合物"),
			_warn("开关在开始页设置，仅对下一局生效"),
		]),
	]


# ============================================================
# 三、牌库派生数据（图鉴网格 / 张数统计）
# ============================================================
# 张数分级与 CardDatabase 保持一致（卤族 10 / H·O·S 8 / 副族 4 / 其余 6）
static func get_element_copies(sym: String) -> int:
	if sym in CardDatabaseScript.HALOGEN_SYMBOLS:
		return CardDatabaseScript.HALOGEN_COPIES
	if sym in CardDatabaseScript.HIGH_COUNT_SYMBOLS:
		return CardDatabaseScript.HIGH_COPIES
	if sym in CardDatabaseScript.SUBGROUP_SYMBOLS:
		return CardDatabaseScript.SUB_COPIES
	return CardDatabaseScript.MAIN_COPIES


# 图鉴用：按周期顺序返回全部 CardData 实例（零依赖，不需要 GameManager）
static func get_element_cards() -> Array:
	var out: Array = []
	for row in CardDatabaseScript.get_element_data():
		out.append(CardDataScript.new(
			row[0], row[1], row[2], row[3], row[4], row[5], row[6],
			row[7], row[8], row[9], row[10], row[11], row[12]
		))
	return out


static func get_total_cards() -> int:
	var total := 0
	for row in CardDatabaseScript.get_element_data():
		total += get_element_copies(row[0])
	return total
