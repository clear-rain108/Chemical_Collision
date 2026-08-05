# ============================================================
# Utils.gd - 工具函数：牌型判定、化合价检测、族炸检测
# 牌型系统：单质 / 化合物 / 族炸 / 有机物 / 顺序
# IUPAC 命名：二元化合物 / 含氧酸 / 含氧酸盐
# ============================================================

const CardDataScript = preload("res://scripts/CardData.gd")

# ============================================================
# 一、牌型枚举与常量
# ============================================================
enum CardPattern {
	ELEMENT,      # 单质（1 张，或双原子分子的 2 张同元素）
	COMPOUND,     # 化合物（多元素化合价匹配）
	CLAN_BOMB,    # 族炸（同族 ≥2 张不同元素）
	ORGANIC,      # 有机物（甲烷CH4、乙烷C2H6、丙烷C3H8及单一卤代物）
	SEQUENCE,     # 顺序（≥3张连续原子序数的牌）
}

# 双原子分子元素符号集合（自然界中以 X₂ 形式存在）
const DIATOMIC_SYMBOLS = ["H", "N", "O", "F", "Cl", "Br", "I"]

# ============================================================
# 一之二、罗马数字对照表
# ============================================================
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

# 金属中文名 → CardData name_cn 本身就有，直接取

# ============================================================
# 二、牌型检测（优先级：族炸 → 顺序 → 有机物 → 化合物）
# ============================================================
static func detect_pattern(cards: Array, skip_clan_bomb: bool = false) -> int:
	if cards.is_empty():
		return -1

	if cards.size() == 1:
		return CardPattern.ELEMENT

	if cards.size() == 2 and _is_same_element(cards):
		if cards[0].symbol in DIATOMIC_SYMBOLS:
			return CardPattern.ELEMENT
		return -1

	if not skip_clan_bomb:
		if _is_clan_bomb(cards):
			return CardPattern.CLAN_BOMB

	if cards.size() >= 3 and _is_sequence(cards):
		return CardPattern.SEQUENCE

	if _is_organic(cards):
		return CardPattern.ORGANIC

	if cards.size() >= 2 and _is_compound(cards):
		if not _is_same_element(cards):
			return CardPattern.COMPOUND

	return -1


static func _is_same_element(cards: Array) -> bool:
	if cards.size() < 2:
		return true
	var symbol = cards[0].symbol
	for c in cards:
		if c.symbol != symbol:
			return false
	return true


# ============================================================
# 三、顺序检测
# ============================================================
static func _is_sequence(cards: Array) -> bool:
	if cards.size() < 3:
		return false
	var sorted_cards = cards.duplicate()
	sorted_cards.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)
	for i in range(sorted_cards.size() - 1):
		if sorted_cards[i + 1].atomic_number - sorted_cards[i].atomic_number != 1:
			return false
	return true


# ============================================================
# 四、有机物检测
# ============================================================
static func _is_organic(cards: Array) -> bool:
	if cards.size() < 5:
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
	if halogen_included == "" and symbols.size() == 2:
		match c_count:
			1: return h_count == 4
			2: return h_count == 6
			3: return h_count == 8
		return false
	if halogen_included != "" and symbols.size() == 3:
		if symbols.size() != 3:
			return false
		match c_count:
			1: return h_count + halogen_count == 4
			2: return h_count + halogen_count == 6
			3: return h_count + halogen_count == 8
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
	if halogen_sym == "":
		return base_name
	else:
		return "%s(一%s代)" % [base_name, halogen_sym]


# ============================================================
# 五、族炸检测
# ============================================================
static func _is_clan_bomb(cards: Array) -> bool:
	if cards.size() < 2:
		return false
	var group_name = cards[0].group
	var symbols_seen: Array = []
	for c in cards:
		if c.group != group_name:
			return false
		if c.symbol in symbols_seen:
			return false
		symbols_seen.append(c.symbol)
	return symbols_seen.size() >= 2


# ============================================================
# 六、化合物检测与配平
# ============================================================
static func _is_compound(cards: Array) -> bool:
	if cards.size() < 2:
		return false
	for c in cards:
		if c.element_type == CardDataScript.TYPE_NOBLE_GAS:
			return false
	if _can_balance_valence(cards):
		return true
	return false


static func _can_balance_valence(cards: Array) -> bool:
	var has_positive = false
	var has_negative = false
	for c in cards:
		for v in c.common_valence:
			if v > 0:
				has_positive = true
			elif v < 0:
				has_negative = true
	return has_positive and has_negative


# 获取化合价配平比例与化学式
# custom_valences: {symbol: valence} 当用户指定化合价时使用
static func get_compound_formula(cards: Array, custom_valences: Dictionary = {}) -> Dictionary:
	if not _is_compound(cards):
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
			var v = custom_valences[sym]
			var cnt = elem_counts.get(sym, 0)
			var card_data = elem_cards.get(sym)
			if v > 0:
				pos_list.append({
					"symbol": sym, "valence": abs(v), "count": cnt,
					"electronegativity": card_data.electronegativity if card_data else 0.0,
					"name_cn": card_data.name_cn if card_data else sym,
					"name_en": card_data.name_en if card_data else sym,
					"ox_state": v,
				})
			else:
				neg_list.append({
					"symbol": sym, "valence": abs(v), "count": cnt,
					"electronegativity": card_data.electronegativity if card_data else 0.0,
					"name_cn": card_data.name_cn if card_data else sym,
					"name_en": card_data.name_en if card_data else sym,
					"ox_state": v,
				})
	else:
		for sym in elem_counts:
			var card_data = elem_cards.get(sym)
			if card_data == null: continue
			var mp = 0; var mn = 0
			var best_v_pos = 0; var best_v_neg = 0
			for v in card_data.common_valence:
				if v > 0 and v > mp:
					mp = v
				elif v < 0 and v < mn:
					mn = v
			if card_data.element_type == CardDataScript.TYPE_METAL and mp > 0:
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

	if pos_list.is_empty() or neg_list.is_empty(): return {}

	# 按电负性排序（规范要求：正价元素按电负性递增，负价元素按电负性递增）
	pos_list.sort_custom(func(a, b): return a.electronegativity < b.electronegativity)
	neg_list.sort_custom(func(a, b): return a.electronegativity < b.electronegativity)

	# 电荷平衡验证
	var total_pos = 0; var total_neg = 0
	for e in pos_list: total_pos += e.count * e.valence
	for e in neg_list: total_neg += e.count * e.valence
	var ratio_ok = (total_pos == total_neg and total_pos > 0)

	# 构建化学式
	var formula = ""
	for e in pos_list: formula += e.symbol + ("" if e.count == 1 else _to_subscript(e.count))
	for e in neg_list: formula += e.symbol + ("" if e.count == 1 else _to_subscript(e.count))

	return {
		"formula": formula,
		"ratio_ok": ratio_ok,
		"total_positive": total_pos,
		"total_negative": total_neg,
		"actual_counts": elem_counts,
		"pos_list": pos_list,
		"neg_list": neg_list,
	}


# ============================================================
# 六之二、IUPAC 化合物命名
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

	# 先尝试匹配含氧酸/含氧酸盐/酸式盐
	var oxy_name = _try_get_oxy_name(fi, pos_list, neg_list)
	if oxy_name != "":
		return oxy_name

	# 默认按二元化合物处理
	if pos_list.size() == 1 and neg_list.size() == 1:
		return _name_binary_compound(pos_list[0], neg_list[0], pos_list[0].ox_state)
	else:
		# 多元化合物：直接用化学式 + 系统命名
		return fi.get("formula", "")


# 尝试匹配含氧酸/含氧酸盐名称
static func _try_get_oxy_name(fi: Dictionary, pos_list: Array, neg_list: Array) -> String:
	var formula = fi.get("formula", "")

	# 检查是否为纯含氧酸（只有 H + 非金属 + O）
	if pos_list.size() == 1 and pos_list[0].symbol == "H":
		if neg_list.size() >= 2:
			# 检查是否匹配已知含氧酸
			for acid_formula in OXYACID_FORMULAS:
				if formula == acid_formula:
					return OXYACID_FORMULAS[acid_formula]

	# 检查是否为含氧酸盐或酸式盐
	if pos_list.size() >= 1:
		# 构建阴离子标识符
		var anion_combo = ""
		for e in neg_list:
			anion_combo += e.symbol + str(e.count)

		# 检查标准含氧阴离子
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
# 七、单质显示
# ============================================================
static func get_element_display(cards: Array) -> String:
	if cards.size() == 1:
		return cards[0].symbol
	if cards.size() == 2 and _is_same_element(cards) and cards[0].symbol in DIATOMIC_SYMBOLS:
		return cards[0].symbol + _to_subscript(2)
	return ""


static func _to_subscript(n: int) -> String:
	var chars = {0: "₀", 1: "₁", 2: "₂", 3: "₃", 4: "₄", 5: "₅", 6: "₆", 7: "₇", 8: "₈", 9: "₉"}
	if n < 10:
		return chars[n]
	var s = str(n)
	var result = ""
	for c in s:
		result += chars[int(c)]
	return result


# ============================================================
# 八、比大小规则
# ============================================================
static func compare_cards(cards_a: Array, cards_b: Array) -> int:
	var pattern_a = detect_pattern(cards_a)
	var pattern_b = detect_pattern(cards_b)

	if pattern_a == -1 or pattern_b == -1:
		return 0

	if pattern_a == CardPattern.SEQUENCE or pattern_b == CardPattern.SEQUENCE:
		return 0

	if pattern_a == CardPattern.CLAN_BOMB and pattern_b != CardPattern.CLAN_BOMB:
		return 1
	if pattern_b == CardPattern.CLAN_BOMB and pattern_a != CardPattern.CLAN_BOMB:
		return -1

	if pattern_a == CardPattern.CLAN_BOMB and pattern_b == CardPattern.CLAN_BOMB:
		if cards_a.size() != cards_b.size():
			if cards_a.size() >= 3:
				return 1
			if cards_b.size() >= 3:
				return -1
			return 1 if cards_a.size() > cards_b.size() else -1
		return _compare_by_total_atomic(cards_a, cards_b)

	if pattern_a == CardPattern.COMPOUND and pattern_b == CardPattern.COMPOUND:
		return _compare_by_total_atomic(cards_a, cards_b)

	if pattern_a == CardPattern.ELEMENT and pattern_b == CardPattern.ELEMENT:
		return _compare_by_total_atomic(cards_a, cards_b)

	if pattern_a == CardPattern.ORGANIC and pattern_b == CardPattern.ORGANIC:
		return _compare_by_total_atomic(cards_a, cards_b)

	var priority = {
		CardPattern.CLAN_BOMB: 3,
		CardPattern.ORGANIC: 2,
		CardPattern.COMPOUND: 1,
		CardPattern.ELEMENT: 0,
		CardPattern.SEQUENCE: -1,
	}
	if priority[pattern_a] != priority[pattern_b]:
		return 1 if priority[pattern_a] > priority[pattern_b] else -1

	return _compare_by_total_atomic(cards_a, cards_b)


static func _compare_by_total_atomic(cards_a: Array, cards_b: Array) -> int:
	var sum_a = 0; var sum_b = 0
	var mass_a: float = 0.0; var mass_b: float = 0.0
	for c in cards_a:
		sum_a += c.atomic_number
		mass_a += c.atomic_weight
	for c in cards_b:
		sum_b += c.atomic_number
		mass_b += c.atomic_weight
	if sum_a < sum_b: return 1
	if sum_a > sum_b: return -1
	if mass_a > mass_b: return -1
	if mass_a < mass_b: return 1
	return 0


# ============================================================
# 九、辅助方法
# ============================================================
static func get_pattern_name(pattern: int) -> String:
	match pattern:
		CardPattern.ELEMENT: return "单质"
		CardPattern.COMPOUND: return "化合物"
		CardPattern.CLAN_BOMB: return "族炸！"
		CardPattern.ORGANIC: return "有机物！"
		CardPattern.SEQUENCE: return "顺序"
	return "非法"


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return a