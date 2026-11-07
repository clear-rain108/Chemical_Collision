# ============================================================
# CompoundSolver.gd - 化合物形成模块
# 职责：化合物检测 / 化合价配平 / IUPAC 命名 / 有机物识别
# 牌型系统：单质 / 化合物 / 族炸 / 有机物 / 顺序
# ============================================================

const CardDataScript = preload("res://scripts/CardData.gd")

# ============================================================
# 一、命名常量表（数据表驱动，后续扩展只需加条目）
# ============================================================

# 罗马数字对照表
const ROMAN_NUMERALS = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

# 中文变价金属低/高价对照表（用于"亚某"命名法）
const VARIABLE_METAL_CN_NAMES = {
	"Fe": {"low": "亚铁", "high": "铁", "low_val": 2, "high_val": 3},
	"Cu": {"low": "亚铜", "high": "铜", "low_val": 1, "high_val": 2},
	"Cr": {"low": "亚铬", "high": "铬", "low_val": 2, "high_val": 3},
	"Mn": {"low": "亚锰", "high": "锰", "low_val": 2, "high_val": 4},
	"Co": {"low": "亚钴", "high": "钴", "low_val": 2, "high_val": 3},
	"Sn": {"low": "亚锡", "high": "锡", "low_val": 2, "high_val": 4},
	"Pb": {"low": "亚铅", "high": "铅", "low_val": 2, "high_val": 4},
	"Hg": {"low": "亚汞", "high": "汞", "low_val": 1, "high_val": 2},
}

# 含氧阴离子映射表（阴离子 → 中文名）
const OXYANION_MAP = {
	"SO4": {"name": "硫酸", "charge": -2},
	"SO3": {"name": "亚硫酸", "charge": -2},
	"NO3": {"name": "硝酸", "charge": -1},
	"NO2": {"name": "亚硝酸", "charge": -1},
	"CO3": {"name": "碳酸", "charge": -2},
	"PO4": {"name": "磷酸", "charge": -3},
	"ClO4": {"name": "高氯酸", "charge": -1},
	"ClO3": {"name": "氯酸", "charge": -1},
	"ClO2": {"name": "亚氯酸", "charge": -1},
	"ClO": {"name": "次氯酸", "charge": -1},
	"MnO4": {"name": "高锰酸", "charge": -1},
	"CrO4": {"name": "铬酸", "charge": -2},
	"Cr2O7": {"name": "重铬酸", "charge": -2},
	"SiO3": {"name": "硅酸", "charge": -2},
	"SiO4": {"name": "原硅酸", "charge": -4},
}

# 含氧酸对应的酸分子式映射（用于检测酸式化合物）
const OXYACID_FORMULAS = {
	"H2SO4": "硫酸",
	"H2SO3": "亚硫酸",
	"HNO3": "硝酸",
	"HNO2": "亚硝酸",
	"H2CO3": "碳酸",
	"H3PO4": "磷酸",
	"HClO4": "高氯酸",
	"HClO3": "氯酸",
	"HClO2": "亚氯酸",
	"HClO": "次氯酸",
	"HMnO4": "高锰酸",
	"H2CrO4": "铬酸",
	"H2Cr2O7": "重铬酸",
	"H2SiO3": "硅酸",
	"H4SiO4": "原硅酸",
}

# 酸式盐阴离子映射（HSO4^- 等）
const ACID_SALT_ANIONS = {
	"HSO4": "硫酸氢",
	"HCO3": "碳酸氢",
	"HSO3": "亚硫酸氢",
	"HPO4": "磷酸氢",
	"H2PO4": "磷酸二氢",
}

# 非金属中文名对应表
const NONMETAL_CN_NAMES = {
	"H": "氢", "He": "氦", "B": "硼", "C": "碳", "N": "氮",
	"O": "氧", "F": "氟", "Ne": "氖", "Si": "硅", "P": "磷",
	"S": "硫", "Cl": "氯", "Ar": "氩", "Br": "溴", "I": "碘",
}

# ------------------------------------------------------------
# 特殊化合物中文名（**只影响显示，不参与任何合法性判定**）
# ------------------------------------------------------------
# key = 无下标数字化学式（formula_key，如 Fe3O4 / H2O），value = 中文名。
# 为什么需要它：
#   1) 默认命名是「负价元素名 + 化 + 正价金属名」（NaCl → 氯化钠），
#      遇到混合价态（Fe₃O₄ = Fe(+3)×2 + Fe(+2)）没有单一价态可套，会编出错名字；
#   2) 习惯名（H₂O = 水）、非金属作正价（CO = 一氧化碳）也不遵守这套构词法。
# 收录原则（≤ 30 条，可玩性优先）：
#   a) 教材 / 生活里一眼认得的；b) 用本作牌库的价态真能打出来（张数 ≤ 手牌 8 张）；
#   c) key 必须与 _assign_valences 产出的 formula_key 完全一致
#      —— 注意化学式按「正价在前」排列，氨是 H3N 而不是 NH3。
# 表里没有的组合仍走原命名逻辑（含氧酸 / 酸式盐 / 二元化合物），不会退化成空白。
const SPECIAL_NAMES = {
	# 水
	"H2O": "水",
	# 碳氧化物
	"CO": "一氧化碳", "CO2": "二氧化碳",
	# 氨与氢化物
	"H3N": "氨", "NaH": "氢化钠", "KH": "氢化钾", "LiH": "氢化锂", "CaH2": "氢化钙",
	# 硫 / 磷氧化物
	"SO2": "二氧化硫", "SO3": "三氧化硫", "P2O5": "五氧化二磷",
	# 铁系（Fe3O4 是混合价态：Fe(+3)×2 + Fe(+2)）
	"FeO": "氧化亚铁", "Fe2O3": "三氧化二铁", "Fe3O4": "四氧化三铁",
	# 铜系
	"CuO": "氧化铜", "Cu2O": "氧化亚铜",
	# 锰 / 铬 / 铝 / 硅
	"MnO2": "二氧化锰", "Cr2O3": "三氧化二铬", "CrO3": "三氧化铬",
	"Al2O3": "三氧化二铝", "SiO2": "二氧化硅",
	# 碱金属 / 碱土金属 / 锌的氧化物
	"Na2O": "氧化钠", "K2O": "氧化钾", "MgO": "氧化镁", "CaO": "氧化钙", "ZnO": "氧化锌",
	# 过氧化物（O 取 −1、且必须成对 —— H₂O₂ / Na₂O₂ / K₂O₂ / CaO₂）
	"H2O2": "过氧化氢", "Na2O2": "过氧化钠", "K2O2": "过氧化钾", "CaO2": "过氧化钙",
}

# 混合价态搜索的组合数上限（超过直接放弃：宁可这一手判非法，也不能在联机对局里卡帧）。
# 典型 Fe₃O₄ = 3 张 Fe（价域 2 个）+ 4 张 O（价域 1 个）→ 组合数 4，远低于上限。
const MIXED_NODE_CAP := 5000

# ============================================================
# 二、有机物检测（视为化合物的子类）
# ============================================================
static func is_organic(cards: Array) -> bool:
	if cards.size() < 4:
		return false
	var elem_counts: Dictionary = {}
	for c in cards:
		if not elem_counts.has(c.symbol):
			elem_counts[c.symbol] = 0
		elem_counts[c.symbol] += 1
	if not elem_counts.has("C") or not elem_counts.has("H"):
		return false
	var c_count = elem_counts["C"]
	var h_count = elem_counts["H"]
	var symbols = elem_counts.keys()
	var halogen_symbols = ["F", "Cl", "Br", "I"]
	var halogen_included = ""
	var halogen_count = 0
	for sym in symbols:
		if sym in halogen_symbols:
			if halogen_included == "":
				halogen_included = sym
			elif halogen_included != "":
				return false
			halogen_count = elem_counts[sym]

	# ---- 烷烃（无卤素，C+H）：CH4 / C2H6 / C3H8 ----
	if halogen_included == "" and symbols.size() == 2:
		match c_count:
			1: return h_count == 4
			2: return h_count == 6
			3: return h_count == 8
		return false

	# ---- 卤代烷烃（C+H+单一卤素）：一卤代物 ----
	if halogen_included != "" and symbols.size() == 3:
		match c_count:
			1: return h_count + halogen_count == 4
			2: return h_count + halogen_count == 6
			3: return h_count + halogen_count == 8
		return false

	# ---- 含氧有机物（C+H+O，无卤素）：甲醛/甲醇/乙醇/甲酸/乙酸 ----
	if halogen_included == "" and symbols.size() == 3 and elem_counts.has("O"):
		var o_count = elem_counts["O"]
		match [c_count, h_count, o_count]:
			[1, 2, 1]: return true   # 甲醛 CH2O
			[1, 4, 1]: return true   # 甲醇 CH3OH
			[2, 6, 1]: return true   # 乙醇 C2H5OH
			[1, 2, 2]: return true   # 甲酸 HCOOH
			[2, 4, 2]: return true   # 乙酸 CH3COOH
		return false

	return false


static func get_organic_name(cards: Array) -> String:
	var elem_counts: Dictionary = {}
	for c in cards:
		if not elem_counts.has(c.symbol):
			elem_counts[c.symbol] = 0
		elem_counts[c.symbol] += 1
	var c_count = elem_counts.get("C", 0)
	var h_count = elem_counts.get("H", 0)
	var halogen_symbols = ["F", "Cl", "Br"]
	var halogen_sym = ""
	for sym in elem_counts:
		if sym in halogen_symbols:
			halogen_sym = sym
	var base_name = ""
	match c_count:
		1: base_name = "甲烷 CH4"
		2: base_name = "乙烷 C2H6"
		3: base_name = "丙烷 C3H8"
	# 含氧有机物（无卤素，C+H+O）：甲醛/甲醇/乙醇/甲酸/乙酸
	if halogen_sym == "" and elem_counts.has("O"):
		var o_count = elem_counts.get("O", 0)
		match [c_count, h_count, o_count]:
			[1, 2, 1]: return "甲醛 CH2O"
			[1, 4, 1]: return "甲醇 CH3OH"
			[2, 6, 1]: return "乙醇 C2H5OH"
			[1, 2, 2]: return "甲酸 HCOOH"
			[2, 4, 2]: return "乙酸 CH3COOH"
	if halogen_sym == "":
		return base_name
	else:
		return "%s(一%s代)" % [base_name, halogen_sym]


# ============================================================
# 三、化合物检测与配平
# ============================================================
# 是否可构成化合物（牌型识别用）。
# 判定 = 「默认配平（金属 / 含氧酸根 / H 化物）能成立」或「存在按张数电荷平衡的价态分配」。
# 这样 NCl / BrN / IN（非金属之间 1:1、电荷对不上或电负性倒置）不再被判成化合物，
# 而 NCl₃ / NI₃ / BCl₃ / ClF 这类真实化合物仍然成立。
# v4：再补一层「混合价态」判定 —— Fe₃O₄（Fe +3/+3/+2）只有混合解，
# 漏掉这层的话牌型识别会说它不是化合物，玩家照着打反而被拒。
static func is_compound(cards: Array) -> bool:
	if cards.size() < 2:
		return false
	for c in cards:
		if c.element_type == CardDataScript.TYPE_NOBLE_GAS:
			return false
	if not _assign_valences(cards, {}).is_empty():
		return true
	if not _search_valences(cards).is_empty():
		return true
	return not _search_mixed_valences(cards).is_empty()


# 获取化合价配平比例与化学式
# custom_valences: {symbol: valence} 当用户指定化合价时使用
static func get_compound_formula(cards: Array, custom_valences: Dictionary = {}) -> Dictionary:
	return _assign_valences(cards, custom_valences)


# 统一化合价分配（唯一入口）。返回 {} = 这组牌构不成合法化合物：
#   1) 稀有气体 / 不足 2 张
#   2) 没有正价或没有负价（如 NCl 无氧时两个非金属都只能作负价）
#   3) 电负性倒置（正价元素电负性 > 负价元素，如 Cl 作 +3 与 N 作 -3 的「ClN」）
static func _assign_valences(cards: Array, custom_valences: Dictionary = {}) -> Dictionary:
	if cards.size() < 2:
		return {}
	for c in cards:
		if c.element_type == CardDataScript.TYPE_NOBLE_GAS:
			return {}

	# 统计每种元素并收集完整 card 数据
	var elem_counts: Dictionary = {}
	var elem_cards: Dictionary = {}   # symbol → card reference
	for c in cards:
		if not elem_counts.has(c.symbol):
			elem_counts[c.symbol] = 0
			elem_cards[c.symbol] = c
		elem_counts[c.symbol] += 1

	# 正/负价分类 (同时记录氧化态用于命名)
	var pos_list: Array = []    # [{symbol, valence, count, electronegativity, name_cn, name_en, ox_state}]
	var neg_list: Array = []

	if custom_valences.size() >= 2 and not custom_valences.has("_organic"):
		for sym in custom_valences:
			var raw = custom_valences[sym]
			var cnt: int = int(elem_counts.get(sym, 0))
			var card_data = elem_cards.get(sym)
			if cnt <= 0:
				continue   # 价态表里多给了本手牌没有的元素：忽略，不参与化学式与电荷
			var plan := _valence_plan_of(raw, cnt)
			if plan.is_empty():
				return {}
			var charge := 0
			for pv in plan:
				charge += int(pv)
			var avg := float(charge) / float(plan.size())
			var entry := {
				"symbol": sym, "valence": absf(avg), "count": cnt,
				# charge = 这几种元素「所有副本」加起来的净电荷：
				# 混合价态下 count * valence 不再等于它（如 Fe₃O₄ 的 3×8/3 = 8），
				# 电荷平衡一律走这个字段，避免浮点误差。
				"charge": absi(charge),
				"mixed": _plan_is_mixed(plan),
				"plan": plan,
				"electronegativity": card_data.electronegativity if card_data else 0.0,
				"name_cn": card_data.name_cn if card_data else sym,
				"name_en": card_data.name_en if card_data else sym,
				# ox_state 只服务于「单价的」命名 / 显示路径；混合价态没有单价，
				# 命名走 SPECIAL_NAMES，桌面小卡走 plan（每张各显示各的价）。
				"ox_state": int(round(avg)),
			}
			if charge > 0:
				pos_list.append(entry)
			elif charge < 0:
				neg_list.append(entry)
			else:
				return {}   # 净电荷 0（如 Fe 取 [+1, -1]）放哪边都不成立
	else:
		for sym in elem_counts:
			var card_data = elem_cards.get(sym)
			if card_data == null: continue
			var mp = 0; var mn = 0
			for v in card_data.common_valence:
				if v > 0 and v > mp:
					mp = v
				elif v < 0 and v < mn:
					mn = v
			# 准金属（B [3] / Si [4]）与金属同口径：以最高正价作正价元素。
			# 只认 TYPE_METAL 时准金属既不进 pos 也不进 neg，会从化学式与电荷里
			# 凭空消失：[Si,H,H,Cl,Cl] 被算成「2HCl」（原子数 2 不是 5），
			# 而 BCl₃ / SiO₂ 反倒配不出来。口径与 _valence_domains 保持一致。
			var metal_like: bool = (card_data.element_type == CardDataScript.TYPE_METAL
					or card_data.element_type == CardDataScript.TYPE_METALLOID)
			if metal_like and mp > 0:
				pos_list.append({
					"symbol": sym, "valence": mp, "count": elem_counts[sym],
					"electronegativity": card_data.electronegativity,
					"name_cn": card_data.name_cn, "name_en": card_data.name_en,
					"ox_state": mp,
				})
			elif mn < 0:
				neg_list.append({
					"symbol": sym, "valence": abs(mn), "count": elem_counts[sym],
					"electronegativity": card_data.electronegativity,
					"name_cn": card_data.name_cn, "name_en": card_data.name_en,
					"ox_state": mn,
				})
			else:
				# 兜底：既没有正价可作金属、也没有负价 —— 绝不能静默丢弃，
				# 否则这个元素会从化学式和电荷里消失（「2HCl」那类 bug）。
				# 判「配不出」后上层会回落到价态搜索 / 给玩家明确的拒绝原因。
				return {}

	# 兜底：无金属正价时，识别非金属正价元素（酸/氢化物，如 HClO 中 H、Cl 为正价）
	# 规则1：H 恒提升为正价 (+1)
	# 规则2：若存在 O 负价，则将"非H非O且拥有正价"的元素中电负性最小者提升为正价（酸的中心原子）
	if pos_list.is_empty() and not neg_list.is_empty():
		var remaining_neg: Array = []
		var has_oxygen = false
		for e in neg_list:
			if e.symbol == "O":
				has_oxygen = true
		var best_central = null
		for e in neg_list:
			if e.symbol == "H":
				e.valence = 1
				e.ox_state = 1
				pos_list.append(e)
			else:
				var cd = elem_cards.get(e.symbol)
				var mp2 = 0
				if cd:
					for v in cd.common_valence:
						if v > 0 and v > mp2:
							mp2 = v
				if e.symbol != "O" and mp2 > 0:
					if best_central == null or e.electronegativity < best_central.electronegativity:
						best_central = e
				remaining_neg.append(e)
		if has_oxygen and best_central != null:
			var cd = elem_cards.get(best_central.symbol)
			var mp2 = 0
			if cd:
				for v in cd.common_valence:
					if v > 0 and v > mp2:
						mp2 = v
			best_central.valence = mp2
			best_central.ox_state = mp2
			remaining_neg.erase(best_central)
			pos_list.append(best_central)
		neg_list = remaining_neg

	if pos_list.is_empty() or neg_list.is_empty(): return {}

	# 电负性校验（化学合理性）：正价元素的电负性必须不大于负价元素。
	# 违反者即「假化合物」——例如 N 作 -3、Cl 作 +3 得到的「ClN」，化学上并不存在；
	# 而 NCl₃（N 为 +3、Cl 为 -1）、ClF（Cl +1、F -1）等真实化合物都能通过。
	for pe in pos_list:
		for ne in neg_list:
			if pe.electronegativity > ne.electronegativity + 0.001:
				return {}

	# 按电负性排序（规范要求：正价元素按电负性递增，负价元素按电负性递增）
	pos_list.sort_custom(func(a, b): return a.electronegativity < b.electronegativity)
	neg_list.sort_custom(func(a, b): return a.electronegativity < b.electronegativity)

	# 电荷平衡验证
	var total_pos = 0; var total_neg = 0
	for e in pos_list: total_pos += _entry_charge(e)
	for e in neg_list: total_neg += _entry_charge(e)
	var ratio_ok = (absi(total_pos) == absi(total_neg) and total_pos != 0)

	# 构建化学式（下标）与 formula_key（纯 ASCII 数字，SPECIAL_NAMES 的 key）
	# 按最简整数比约分：4H+2O 旧实现显示 H₄O₂，现在 2H₂O（系数在前、下标最简）；
	# 2Na+2Br 旧实现显示 Na₂Br₂，现在 2NaBr。名字仍按最简式的组成命名（溴化钠）。
	# 过氧根例外：O 全部取 −1 时不能用 gcd（H₂O₂ 的 H:O 是 1:1，gcd 会约成 HO），
	# 改按「过氧根个数」约分：count(O)/2 就是分子个数（2H+2O → H₂O₂、4H+4O → 2H₂O₂）。
	var peroxy := false
	var g := 0
	for e in neg_list:
		if String(e.symbol) != "O":
			continue
		# 每个 O 的价态绝对值：1 → 过氧根（O 取 −1），2 → 正常氧化物。
		# 不能直接比 ox_state：负价元素的 ox_state 存的是绝对值（1 而不是 −1）。
		var o_count: int = maxi(1, int(e.count))
		# 下面两处是**有意的整数除法**：价态/张数、O 数/2 落在整数上才有意义
		# （不整除说明这组牌根本不是过氧根，丢弃小数部分正是想要的判定）。
		@warning_ignore("integer_division")
		var unit_val: int = absi(_entry_charge(e)) / o_count
		if unit_val == 1:
			peroxy = true
			@warning_ignore("integer_division")
			g = maxi(1, o_count / 2)
	if g < 1:
		# 初值必须是 0：gcd(1, n) 恒为 1，用 1 起算等于根本没约分
		g = 0
		for e in pos_list:
			g = _gcd(g, int(e.count))
		for e in neg_list:
			g = _gcd(g, int(e.count))
		if g < 1:
			g = 1

	var formula_base = ""
	var formula_key = ""
	var mixed := false
	for e in pos_list:
		@warning_ignore("integer_division")
		var n_pos: int = int(e.count) / g
		formula_base += e.symbol + ("" if n_pos == 1 else _to_subscript(n_pos))
		formula_key += e.symbol + ("" if n_pos == 1 else str(n_pos))
		if bool(e.get("mixed", false)): mixed = true
	for e in neg_list:
		@warning_ignore("integer_division")
		var n_neg: int = int(e.count) / g
		formula_base += e.symbol + ("" if n_neg == 1 else _to_subscript(n_neg))
		formula_key += e.symbol + ("" if n_neg == 1 else str(n_neg))
		if bool(e.get("mixed", false)): mixed = true
	# 系数：这组牌其实是 g 个相同的分子，g > 1 时写成 2H₂O / 2NaBr
	var formula: String = (str(g) + formula_base) if g > 1 else formula_base

	return {
		"formula": formula,
		"formula_base": formula_base,
		"formula_key": formula_key,
		"coefficient": g,
		"peroxy": peroxy,
		"mixed": mixed,
		"ratio_ok": ratio_ok,
		"total_positive": total_pos,
		"total_negative": total_neg,
		"actual_counts": elem_counts,
		"pos_list": pos_list,
		"neg_list": neg_list,
	}


# ------------------------------------------------------------
# 三之一½、化合价表达式的规范化（统一价 / 混合价的唯一入口）
# ------------------------------------------------------------
# 化合价有两种写法，引擎内部一律先规范成「每张牌一个价」的数组 plan：
#   int        → [v, v, ...]    统一价态（v3 以来的写法，联机协议 / 存档原样兼容）
#   Array      → 降序规范化      混合价态（Fe₃O₄ 的 Fe = [+3, +3, +2]）
# 非法一律返回 []（调用方据此判 {} = 不是化合物）：
#   a) 长度 ≠ 张数（少给一张 / 多给一张都对不上具体卡）；
#   b) 含 0（0 价在本作里没有意义）；
#   c) 同一元素跨正负（「一张 Fe 当正价、另一张当负价」化学上不成立）。
# 降序是**表示规范化**而不是「把价派给某一张牌」：同元素副本完全等价，
# 排序只为让面板 / 桌面 / 联机指纹对同一组合给出同一个字符串。
static func _valence_plan_of(raw, count: int) -> Array:
	if count <= 0:
		return []
	var plan: Array = []
	if raw is Array:
		if raw.size() != count:
			return []
		var sign_val := 0
		for v in raw:
			var iv := int(v)
			if iv == 0:
				return []
			var s := 1 if iv > 0 else -1
			if sign_val != 0 and s != sign_val:
				return []
			sign_val = s
			plan.append(iv)
		plan.sort()
		plan.reverse()
		return plan
	var single := int(raw)
	if single == 0:
		return []
	for _i in range(count):
		plan.append(single)
	return plan


# plan 里是否真的「一元素多价」（Fe₃O₄ 的 [+3, +3, +2] → true，NaCl 的 [1] → false）
static func _plan_is_mixed(plan: Array) -> bool:
	if plan.size() < 2:
		return false
	for v in plan:
		if int(v) != int(plan[0]):
			return true
	return false


# 一个元素（可能混合价）对总电荷的贡献：优先用规范化时算好的 charge，
# 默认配平分支的元素条目没有 charge，回落到 count * valence。
static func _entry_charge(e: Dictionary) -> int:
	if e.has("charge"):
		return int(e["charge"])
	return int(e.get("count", 0)) * int(e.get("valence", 0))


# ------------------------------------------------------------
# 三之二、默认配平失败时的「价态搜索」
# ------------------------------------------------------------
# 默认配平只给「金属取最高价 / 非金属取最低价 / 含氧酸根提升中心原子」这一套主流解，
# 像 NCl₃（N 为 +3）、BCl₃（B 为 +3）、ClF（Cl 为 +1）这类需要"非金属作正价"的组合
# 只能靠搜索找到。搜索同时要求：
#   a) 至少一正一负；b) 按实际张数加权后总电荷 = 0；c) 正价元素电负性 ≤ 负价元素。
# 价域口径（v4）：
#   金属 / 准金属 → **全部正价，降序**（Fe 有 +3/+2，Cu 有 +2/+1）；
#   非金属 → common_valence 原顺序（负价在前，多负价的元素先试最负）。
# 降序不是随便定的：把「常见高价」排前面，同一组牌有多个解时先命中的就是主流解
#   Fe + 3O → Fe(+3)（Fe₂O₃）；Fe + O → +3 电荷不平，自动退到 +2（FeO）。
# 旧实现只给最高正价，Cu₂O(Cu +1) / FeO(Fe +2) / FeCl₂(Fe +2) 这类常见低价化合物
# 根本搜不出来 —— 玩家在面板手选低价，反而被引擎判成非法。
# 只枚举 2~3 种元素（与化合价面板能力对齐）。
static func _search_valences(cards: Array) -> Dictionary:
	var elems = _valence_domains(cards)
	if elems.size() < 2 or elems.size() > 3:
		return {}
	return _dfs_valences(elems, 0, {})


# 每元素的候选价域：[{symbol, count, card, values}]
# allow_peroxide=false：不把 O 的 −1 放进价域。混合价态搜索（3 张 O 拆成 −2/−1/−1）
# 用它 —— 过氧根是「整对 O 都取 −1」的统一解，不该由混合搜索拼出来。
static func _valence_domains(cards: Array, allow_peroxide: bool = true) -> Array:
	var elems: Array = []
	var index: Dictionary = {}
	for c in cards:
		if index.has(c.symbol):
			elems[index[c.symbol]]["count"] += 1
			continue
		var vals: Array = []
		var metal_like: bool = (c.element_type == CardDataScript.TYPE_METAL \
				or c.element_type == CardDataScript.TYPE_METALLOID)
		if metal_like:
			for v in c.common_valence:
				if v > 0 and v not in vals:
					vals.append(v)
			vals.sort()
			vals.reverse()   # 降序：高价优先（常见化合物优先命中）
		else:
			for v in c.common_valence:
				if v == 0:
					continue
				if not allow_peroxide and String(c.symbol) == "O" and int(v) == -1:
					continue
				vals.append(v)
		if vals.is_empty():
			return []
		index[c.symbol] = elems.size()
		elems.append({"symbol": c.symbol, "count": 1, "card": c, "values": vals})
	return elems


static func _dfs_valences(elems: Array, idx: int, chosen: Dictionary) -> Dictionary:
	if idx >= elems.size():
		return chosen.duplicate() if _valence_assignment_ok(elems, chosen) else {}
	for v in elems[idx]["values"]:
		chosen[elems[idx]["symbol"]] = int(v)
		var found = _dfs_valences(elems, idx + 1, chosen)
		if not found.is_empty():
			return found
	chosen.erase(elems[idx]["symbol"])
	return {}


# 电荷平衡（按实际张数加权）+ 正负价齐全 + 电负性有序
static func _valence_assignment_ok(elems: Array, chosen: Dictionary) -> bool:
	var total := 0
	var pos_elec := -1.0
	var neg_elec := 999.0
	var has_pos := false
	var has_neg := false
	for e in elems:
		var v: int = int(chosen.get(e["symbol"], 0))
		# 过氧根必须成对：O 取 −1 时张数须为偶数且 ≥2。
		# H₂O₂ / Na₂O₂ / CaO₂ 成立；H₃O₃ / Na₂O₃ 这类不存在的组合在这里被挡掉，
		# 不需要额外的「过氧化物白名单」。
		if String(e["symbol"]) == "O" and v == -1:
			var o_count: int = int(e["count"])
			if o_count < 2 or o_count % 2 != 0:
				return false
		if v > 0:
			has_pos = true
			pos_elec = maxf(pos_elec, e["card"].electronegativity)
		elif v < 0:
			has_neg = true
			neg_elec = minf(neg_elec, e["card"].electronegativity)
		total += int(e["count"]) * v
	if not (has_pos and has_neg):
		return false
	if total != 0:
		return false
	return pos_elec <= neg_elec + 0.001


# ------------------------------------------------------------
# 三之三、混合价态搜索（v4）：同一元素的多张牌各取不同价
# ------------------------------------------------------------
# 典型：Fe₃O₄ = Fe(+3)×2 + Fe(+2)×1。3 张 Fe 若同价，总电荷必是 3 的倍数，
# 而 4 张 O 的 -2 之和是 -8 ——「每元素一个价」永远配不平，只能靠混合价。
# 规则：
#   1) **只在统一搜索失败后调用**（统一解优先，保证主流解与可复现性）；
#   2) 每元素各副本必须同号（不许「一张 Fe 当正价、另一张当负价」）；
#   3) 正价元素电负性 ≤ 负价元素（与统一搜索同一条化学约束）；
#   4) 末元素用有界 DP 反解剩余电荷，其余元素枚举「非递增组合」——
#      副本互换不产生新解，组合数从排列数级别的爆炸降到 C(n+k-1, n)；
#   5) 组合数 > MIXED_NODE_CAP 直接放弃：联机对局宁可判非法，也不能卡帧。
static func _search_mixed_valences(cards: Array) -> Dictionary:
	# 过氧根不进混合搜索：3 张 O 拆成 −2/−1/−1 会拼出「过氧化某」这种不存在的组合
	var elems = _valence_domains(cards, false)
	if elems.size() < 2 or elems.size() > 3:
		return {}
	var estimate := 1
	var has_mixed_potential := false
	for e in elems:
		var count: int = int(e["count"])
		var values: Array = e["values"]
		var pos_n := 0
		var neg_n := 0
		for v in values:
			if int(v) > 0: pos_n += 1
			else: neg_n += 1
		# 混合的前提：某元素 ≥2 张，且同号价域里至少 2 个值
		if count >= 2 and (pos_n >= 2 or neg_n >= 2):
			has_mixed_potential = true
		estimate *= _multiset_count(count, values.size())
	if not has_mixed_potential or estimate > MIXED_NODE_CAP:
		return {}
	var found := _search_mixed_signs(elems, 0)
	if found.is_empty():
		return {}
	var cv: Dictionary = {}
	for sym in found:
		var plan: Array = (found[sym] as Array).duplicate()
		plan.sort()
		plan.reverse()
		if _plan_is_mixed(plan):
			cv[sym] = plan
		else:
			cv[sym] = int(plan[0])
	return cv


# 穷举「哪些元素作正价」的符号分配（2~3 元素 → ≤8 种），逐个尝试 DFS
static func _search_mixed_signs(elems: Array, mask: int) -> Dictionary:
	var n: int = elems.size()
	if mask >= (1 << n):
		return {}
	var domains: Array = []
	var pos_elec := -1.0
	var neg_elec := 999.0
	var has_pos := false
	var has_neg := false
	for i in range(n):
		var e = elems[i]
		var positive: bool = (mask & (1 << i)) != 0
		var dom: Array = []
		for v in e["values"]:
			var iv := int(v)
			if (positive and iv > 0) or (not positive and iv < 0):
				dom.append(iv)
		if dom.is_empty():
			return _search_mixed_signs(elems, mask + 1)
		domains.append(dom)
		var enc: float = float(e["card"].electronegativity)
		if positive:
			has_pos = true
			pos_elec = maxf(pos_elec, enc)
		else:
			has_neg = true
			neg_elec = minf(neg_elec, enc)
	# 必须有正有负，且正价侧电负性不大于负价侧（同统一搜索的化学约束）
	if not (has_pos and has_neg) or pos_elec > neg_elec + 0.001:
		return _search_mixed_signs(elems, mask + 1)
	var plan := _dfs_mixed_valences(elems, domains, 0, [], 0)
	if plan.is_empty():
		return _search_mixed_signs(elems, mask + 1)
	return plan


# 前 n-1 个元素枚举组合，末元素交给 DP 反解
static func _dfs_mixed_valences(elems: Array, domains: Array, idx: int,
		chosen: Array, charge: int) -> Dictionary:
	var n: int = elems.size()
	if idx >= n - 1:
		var last_vals := _solve_last_valence(domains[idx], int(elems[idx]["count"]), -charge)
		if last_vals.is_empty():
			return {}
		var out: Dictionary = {}
		for i in range(n - 1):
			out[elems[i]["symbol"]] = (chosen[i] as Array).duplicate()
		out[elems[n - 1]["symbol"]] = last_vals
		return out
	for combo in _valence_combos(domains[idx], int(elems[idx]["count"])):
		var sum := 0
		for v in combo:
			sum += int(v)
		if not _mixed_charge_reachable(elems, domains, idx + 1, charge + sum):
			continue
		chosen.append(combo)
		var found := _dfs_mixed_valences(elems, domains, idx + 1, chosen, charge + sum)
		chosen.pop_back()
		if not found.is_empty():
			return found
	return {}


# 末元素：给定副本数与目标电荷，用有界 DP 反解出一组价（降序返回，无解返回 []）。
# 状态 = (已用副本数, 当前和)，逐层推进并记录首选前驱 → 结果确定（同一输入永远同一答案）。
static func _solve_last_valence(dom: Array, count: int, target: int) -> Array:
	if count <= 0:
		return []
	var parent: Dictionary = {}
	var frontier: Array = [Vector2i(0, 0)]
	for k in range(count):
		var next_frontier: Array = []
		for st in frontier:
			for v in dom:
				var key := Vector2i(k + 1, st.y + int(v))
				if parent.has(key):
					continue
				parent[key] = {"prev": st, "v": int(v)}
				next_frontier.append(key)
		frontier = next_frontier
		if frontier.is_empty():
			return []
	var goal := Vector2i(count, target)
	if not parent.has(goal):
		return []
	var vals: Array = []
	var cur: Vector2i = goal
	while cur.x > 0:
		var info: Dictionary = parent[cur]
		vals.append(int(info["v"]))
		cur = info["prev"]
	vals.sort()
	vals.reverse()
	return vals


# 长度为 count 的「非递增组合」（同元素副本可互换 → 只枚举组合，不枚举排列）
static func _valence_combos(dom: Array, count: int) -> Array:
	var out: Array = []
	_collect_valence_combos(dom, count, 0, [], out)
	return out


static func _collect_valence_combos(dom: Array, count: int, start: int,
		cur: Array, out: Array) -> void:
	if cur.size() == count:
		out.append(cur.duplicate())
		return
	for i in range(start, dom.size()):
		cur.append(int(dom[i]))
		_collect_valence_combos(dom, count, i, cur, out)
		cur.pop_back()


# 剪枝：剩下的元素（含末元素）能否把 partial 抵消回 0（区间判定，只看可达范围）
static func _mixed_charge_reachable(elems: Array, domains: Array, start: int, partial: int) -> bool:
	var lo := partial
	var hi := partial
	for i in range(start, elems.size()):
		var cnt: int = int(elems[i]["count"])
		var dom: Array = domains[i]
		var dmin := int(dom[0])
		var dmax := int(dom[0])
		for v in dom:
			dmin = mini(dmin, int(v))
			dmax = maxi(dmax, int(v))
		lo += cnt * dmin
		hi += cnt * dmax
	return lo <= 0 and 0 <= hi


# 从 kinds 个价里取 total 张（可重复）的组合数 C(total + kinds - 1, total)
static func _multiset_count(total: int, kinds: int) -> int:
	if total <= 0 or kinds <= 0:
		return 1
	var n: int = total + kinds - 1
	var k: int = mini(total, kinds - 1)
	var result := 1
	for i in range(k):
		# 组合数递推：每步 (n-i) 都能被 (i+1) 整除，整数除法是精确的，不用浮点。
		@warning_ignore("integer_division")
		result = result * (n - i) / (i + 1)
	return result


# 供 AI / 提示 / 化合价面板使用：返回按实际张数可行的 {symbol: valence}，无解返回 {}
# 求解优先级（决定「同一组牌打出什么」，所以要稳定且可解释）：
#   1) 默认配平（金属最高价 / 非金属最低价 / 含氧酸根）—— 主流解，v3 行为不变
#   2) 统一价态搜索（每元素一个价，按张数电荷平衡）
#   3) 混合价态搜索（同元素各副本可取不同价，如 Fe₃O₄）
# 统一解永远优先于混合解：Fe + 3O 是 Fe₂O₃（Fe +3），不会给出 Fe +3/+3/+2 之类
# 的「更奇怪但数学上也成立」的解；也让 state_hash / 联机回放对同一手牌可复现。
static func get_valence_pairs(cards: Array) -> Dictionary:
	var uniform := get_uniform_valence_pairs(cards)
	if not uniform.is_empty():
		return uniform
	return _search_mixed_valences(cards)


# 统一价态解（每元素一个价）：默认配平优先，其次按张数搜索。无解返回 {}。
# UI 用它判断「要不要给玩家一个混合价态入口」（统一无解 + 混合有解 才显示）。
static func get_uniform_valence_pairs(cards: Array) -> Dictionary:
	var fi = _assign_valences(cards, {})
	if not fi.is_empty() and fi.get("ratio_ok", false):
		return _cv_from_formula(fi)
	return _search_valences(cards)


# 混合价态解（可能含 Array 值）。无解返回 {}。
static func get_mixed_valence_pairs(cards: Array) -> Dictionary:
	return _search_mixed_valences(cards)


# 从 _assign_valences 的化学式结果反推 {symbol: valence}
# （混合价态返回每张牌一个价的数组，其余返回 int）
static func _cv_from_formula(fi: Dictionary) -> Dictionary:
	var cv: Dictionary = {}
	for e in fi.get("pos_list", []) + fi.get("neg_list", []):
		if bool(e.get("mixed", false)):
			cv[e.symbol] = (e.get("plan", []) as Array).duplicate()
		else:
			cv[e.symbol] = int(e.get("ox_state", 0))
	return cv


# ============================================================
# 四、IUPAC 化合物命名
# ============================================================
static func get_compound_name(cards: Array, custom_valences: Dictionary = {}) -> String:
	if cards.size() < 2:
		return ""

	var fi = get_compound_formula(cards, custom_valences)
	if fi.is_empty() or not fi.get("ratio_ok", false):
		return ""

	var pos_list: Array = fi.get("pos_list", [])
	var neg_list: Array = fi.get("neg_list", [])
	if pos_list.is_empty() or neg_list.is_empty():
		return ""

	# 特殊命名表优先（显示层覆盖）：Fe₃O₄ / H₂O / CO 这类默认构词法拼不对的组合。
	# 只查表、不参与合法性判定 —— 表里查不到就继续走原来的命名逻辑。
	var key := str(fi.get("formula_key", ""))
	if SPECIAL_NAMES.has(key):
		return SPECIAL_NAMES[key]

	# 混合价态没有「一个」价态数字，亚铁/铁、氧化某这套构词法不成立；
	# 表里没收录时只显示化学式（宁可少个名字，也不编一个错的）。
	if bool(fi.get("mixed", false)):
		return ""

	# 先尝试匹配含氧酸/含氧酸盐/酸式盐
	var oxy_name = _try_get_oxy_name(fi, pos_list, neg_list)
	if oxy_name != "":
		return oxy_name

	# 默认按二元化合物处理
	if pos_list.size() == 1 and neg_list.size() == 1:
		return _name_binary_compound(pos_list[0], neg_list[0], pos_list[0].ox_state)
	else:
		# 多元化合物：直接用化学式 + 系统命名（formula_base：不带系数前缀，
		# 否则 2NaBr 会被当成名字的一部分，出现「2NaBr」这种名字）
		return fi.get("formula_base", fi.get("formula", ""))


# 尝试匹配含氧酸/含氧酸盐名称
static func _try_get_oxy_name(fi: Dictionary, pos_list: Array, neg_list: Array) -> String:
	# 含氧酸/含氧盐的比对表 key 是 ASCII（H2SO4 这种），必须用 formula_key；
	# 旧实现拿下标式（H₂SO₄）去比，永远不相等 —— 含氧酸命名一直没生效过。
	var formula = fi.get("formula_key", fi.get("formula", ""))

	# 检查是否为纯含氧酸（只有 H + 非金属 + O）
	if pos_list.size() == 1 and pos_list[0].symbol == "H":
		if neg_list.size() >= 2:
			# 检查是否匹配已知含氧酸
			for acid_formula in OXYACID_FORMULAS:
				if formula == acid_formula:
					return OXYACID_FORMULAS[acid_formula]

	# 检查是否为含氧酸盐或酸式盐
	if pos_list.size() >= 1:
		# 检查标准含氧阴离子（匹配直接用 neg_list，不需要拼字符串）
		for oxy_key in OXYANION_MAP:
			# 简化匹配：按符号顺序拼接
			if _match_anion_combo(neg_list, oxy_key):
				var acid_name = OXYANION_MAP[oxy_key].name
				# 构建盐名称：金属名 + 酸根名（去掉"酸"字）
				var salt_suffix = acid_name.substr(0, acid_name.length() - 1)  # 去掉"酸"
				var cation_name = ""
				if pos_list.size() == 1:
					cation_name = _get_metal_name_with_stock(pos_list[0])
				else:
					cation_name = formula  # fallback
				return salt_suffix + cation_name

		# 检查酸式阴离子
		for acid_key in ACID_SALT_ANIONS:
			if _match_anion_combo(neg_list, acid_key):
				var anion_name = ACID_SALT_ANIONS[acid_key]
				var cation_name = ""
				if pos_list.size() == 1:
					cation_name = _get_metal_name_with_stock(pos_list[0])
				else:
					cation_name = formula
				return anion_name + cation_name

	return ""


# 匹配阴离子组合
static func _match_anion_combo(neg_list: Array, key: String) -> bool:
	# 简化匹配：提取 key 中的元素符号和数量，与 neg_list 比较
	var key_symbols = {}
	var i = 0
	while i < key.length():
		var ch = key.unicode_at(i)
		if ch >= 65 and ch <= 90:  # A-Z uppercase
			var sym = key[i]
			i += 1
			var ch2 = key.unicode_at(i) if i < key.length() else 0
			while i < key.length() and ch2 >= 97 and ch2 <= 122:  # a-z lowercase
				sym += key[i]
				i += 1
				ch2 = key.unicode_at(i) if i < key.length() else 0
			var num_str = ""
			var ch3 = key.unicode_at(i) if i < key.length() else 0
			while i < key.length() and ch3 >= 48 and ch3 <= 57:  # 0-9
				num_str += key[i]
				i += 1
				ch3 = key.unicode_at(i) if i < key.length() else 0
			var cnt = 1 if num_str == "" else int(num_str)
			key_symbols[sym] = cnt
		else:
			i += 1

	if key_symbols.is_empty():
		return false

	# 比较 neg_list
	for e in neg_list:
		if not key_symbols.has(e.symbol):
			return false
		if key_symbols[e.symbol] != e.count:
			return false

	return neg_list.size() == key_symbols.size()


# 获取含 stock 记号的金属名（如 "铁(III)" 或 "亚铁"）
static func _get_metal_name_with_stock(pos_entry: Dictionary) -> String:
	var sym = pos_entry.symbol
	var ox_state = pos_entry.get("ox_state", 0)
	var cn_name = pos_entry.get("name_cn", sym)

	if VARIABLE_METAL_CN_NAMES.has(sym):
		var v = VARIABLE_METAL_CN_NAMES[sym]
		if ox_state == v.low_val:
			return v.low
		elif ox_state == v.high_val:
			return v.high
		else:
			# 其他价态，使用罗马数字
			return "%s(%s)" % [cn_name, ROMAN_NUMERALS[ox_state] if ox_state < ROMAN_NUMERALS.size() else str(ox_state)]

	return cn_name


# 二元化合物命名
static func _name_binary_compound(pos_entry: Dictionary, neg_entry: Dictionary, ox_state: int) -> String:
	var pos_sym = pos_entry.symbol
	var neg_sym = neg_entry.symbol

	# 负价非金属中文名 + "化"后缀
	var neg_cn = NONMETAL_CN_NAMES.get(neg_sym, neg_entry.get("name_cn", neg_sym))
	if neg_cn.length() > 2 and neg_cn.ends_with("气"):
		pass  # 保留原名

	# 金属中文名（含变价处理）
	var pos_name = ""
	if VARIABLE_METAL_CN_NAMES.has(pos_sym):
		var v = VARIABLE_METAL_CN_NAMES[pos_sym]
		if ox_state == v.low_val:
			pos_name = v.low
		elif ox_state == v.high_val:
			pos_name = v.high
		else:
			pos_name = pos_entry.get("name_cn", pos_sym)
	else:
		pos_name = pos_entry.get("name_cn", pos_sym)

	# 特殊的非金属化物（HCl, H2S, NH3 等含氢化合物）
	if pos_sym == "H":
		return neg_cn + "化氢"

	return neg_cn + "化" + pos_name


# ============================================================
# 五、辅助方法
# ============================================================
static func _to_subscript(n: int) -> String:
	var chars = {0: "₀", 1: "₁", 2: "₂", 3: "₃", 4: "₄", 5: "₅", 6: "₆", 7: "₇", 8: "₈", 9: "₉"}
	if n < 10:
		return chars[n]
	var s = str(n)
	var result = ""
	for c in s:
		result += chars[int(c)]
	return result


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return a


# 单分子原子数（B′ 溢出化合物的判定口径）。
# 旧口径是「牌数 ≥ 人数」，可以被「两张小分子叠着打」刷到：
# 2Na+2Br 是 4 张牌，但每个 NaBr 只有 2 个原子，和 4 人局的「溢出」毫无关系。
# 优先用配平算出的分子个数 coefficient（过氧根也算得准：H₂O₂ → 4 个原子）；
# 配不出化学式时退化为 gcd 口径（过氧根会偏小 → 宁可判不免疫，也不放水）。
static func get_formula_atom_count(cards: Array) -> int:
	if cards.is_empty():
		return 0
	var g := 0
	var cv: Dictionary = get_uniform_valence_pairs(cards)
	if not cv.is_empty():
		var fi: Dictionary = get_compound_formula(cards, cv)
		if not fi.is_empty() and bool(fi.get("ratio_ok", false)):
			g = int(fi.get("coefficient", 0))
	if g < 1:
		var counts: Dictionary = {}
		for c in cards:
			counts[c.symbol] = int(counts.get(c.symbol, 0)) + 1
		for sym in counts:
			g = _gcd(g, int(counts[sym]))
	if g < 1:
		g = 1
	# 单分子原子数 = 牌数 / 分子个数，是有意的整数除法（配平后必然整除）
	@warning_ignore("integer_division")
	return cards.size() / g

