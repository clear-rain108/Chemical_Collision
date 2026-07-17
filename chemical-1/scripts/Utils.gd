# ============================================================
# Utils.gd - 工具函数：牌型判定、化合价检测、族炸检测
# 牌型系统：单质 / 化合物 / 族炸 / 有机物 / 顺序
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
const DIATOMIC_SYMBOLS = ["H", "N", "O", "F", "Cl"]


# ============================================================
# 二、牌型检测（优先级：顺序 → 有机物 → 单质 → 双原子 → 族炸 → 化合物）
# ============================================================
# 判定一组牌的牌型
# skip_clan_bomb: 指定"化合物"或"有机物"路径时设为 true，跳过族炸检测
static func detect_pattern(cards: Array, skip_clan_bomb: bool = false) -> int:
	if cards.is_empty():
		return -1

	# 1 张 → 单质
	if cards.size() == 1:
		return CardPattern.ELEMENT

	# 2 张同元素 → 双原子分子单质 / 非法
	if cards.size() == 2 and _is_same_element(cards):
		if cards[0].symbol in DIATOMIC_SYMBOLS:
			return CardPattern.ELEMENT   # 双原子分子单质
		return -1  # 非法

	# 检查族炸（同族不同元素 ≥2 张）— 优先于顺序（如 Fe/Co/Ni 同族且连续应识别为族炸）
	if not skip_clan_bomb:
		if _is_clan_bomb(cards):
			return CardPattern.CLAN_BOMB

	# 检查顺序（≥3张连续原子序数）— 族炸之后检测
	if cards.size() >= 3 and _is_sequence(cards):
		return CardPattern.SEQUENCE

	# 检查有机物（必须在化合物检查之前，因为有机物是特殊化合物）
	if _is_organic(cards):
		return CardPattern.ORGANIC

	# 检查化合物（多元素化合价匹配，≥2 张）
	if cards.size() >= 2 and _is_compound(cards):
		# 确保不是纯单质的双原子分子伪装
		if not _is_same_element(cards):
			return CardPattern.COMPOUND

	# 默认非法组合
	return -1


# 检查是否同元素
static func _is_same_element(cards: Array) -> bool:
	if cards.size() < 2:
		return true
	var symbol = cards[0].symbol
	for c in cards:
		if c.symbol != symbol:
			return false
	return true


# ============================================================
# 三、顺序检测（≥3张连续原子序数）
# ============================================================
# 出牌的顺序变更（顺时针变为逆时针，逆时针变为顺时针）
# 打出顺序的玩家选择让下一名玩家打出特定牌型，否则罚抽2张
static func _is_sequence(cards: Array) -> bool:
	if cards.size() < 3:
		return false
	# 按原子序数排序
	var sorted_cards = cards.duplicate()
	sorted_cards.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)
	for i in range(sorted_cards.size() - 1):
		if sorted_cards[i + 1].atomic_number - sorted_cards[i].atomic_number != 1:
			return false
	return true


# ============================================================
# 四、有机物检测
# ============================================================
# 有机物的牌型定义（单质有机物）：
#   甲烷 CH4：C × 1 + H × 4
#   乙烷 C2H6：C × 2 + H × 6
#   丙烷 C3H8：C × 3 + H × 8
# 单一卤代物：上述化合物中一个 H 被一种卤族元素（F/Cl/Br）替换
#   例如：CH3Cl（C×1 + H×3 + Cl×1）、C2H5F（C×2 + H×5 + F×1）
static func _is_organic(cards: Array) -> bool:
	if cards.size() < 5:
		return false

	# 统计元素种类
	var elem_counts: Dictionary = {}
	for c in cards:
		if not elem_counts.has(c.symbol):
			elem_counts[c.symbol] = 0
		elem_counts[c.symbol] += 1

	# 必须包含 C 和 H
	if not elem_counts.has("C") or not elem_counts.has("H"):
		return false

	var c_count = elem_counts["C"]
	var h_count = elem_counts["H"]

	var symbols = elem_counts.keys()
	var halogen_symbols = ["F", "Cl", "Br"]

	# 检查卤代物：只能有一种卤族元素
	var halogen_included = ""
	var halogen_count = 0
	for sym in symbols:
		if sym in halogen_symbols:
			if halogen_included == "":
				halogen_included = sym
			elif halogen_included != "":  # 存在两种及以上不同卤族元素
				return false
			halogen_count = elem_counts[sym]

	# 基础烷烃（无卤代）
	if halogen_included == "" and symbols.size() == 2:
		# 只有 C 和 H
		match c_count:
			1: return h_count == 4    # CH4
			2: return h_count == 6    # C2H6
			3: return h_count == 8    # C3H8
		return false

	# 单一卤代物（C + H + 一种卤族 X）
	if halogen_included != "" and symbols.size() == 3:
		# 确认只有 C, H 和一种卤族元素
		if symbols.size() != 3:
			return false
		match c_count:
			1: return h_count + halogen_count == 4    # CH4 卤代：H + X = 4
			2: return h_count + halogen_count == 6    # C2H6 卤代：H + X = 6
			3: return h_count + halogen_count == 8    # C3H8 卤代：H + X = 8
		return false

	return false


# 获取有机物的显示名称
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
	var halogen_cnt = 0
	for sym in elem_counts:
		if sym in halogen_symbols:
			halogen_sym = sym
			halogen_cnt = elem_counts[sym]

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
# 五、族炸检测（同族 ≥2 张不同元素）
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
			return false  # 同一元素不允许
		symbols_seen.append(c.symbol)

	return symbols_seen.size() >= 2


# ============================================================
# 六、化合物检测与配平
# ============================================================
# 检查是否为化合物（多元素化合价匹配，排除稀有气体）
static func _is_compound(cards: Array) -> bool:
	if cards.size() < 2:
		return false

	for c in cards:
		if c.element_type == CardDataScript.TYPE_NOBLE_GAS:
			return false

	if _can_balance_valence(cards):
		return true

	return false


# 检查化合价是否能配平（是否存在一正一负）
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

	# 统计每种元素
	var elem_counts: Dictionary = {}
	for c in cards:
		if not elem_counts.has(c.symbol):
			elem_counts[c.symbol] = 0
		elem_counts[c.symbol] += 1

	# 正/负价分类
	var pos_list: Array = []    # [{symbol, valence, count}]
	var neg_list: Array = []

	if custom_valences.size() >= 2:
		# 使用用户自定义化合价
		for sym in custom_valences:
			var v = custom_valences[sym]
			var cnt = elem_counts.get(sym, 0)
			if v > 0:
				pos_list.append({"symbol": sym, "valence": abs(v), "count": cnt})
			else:
				neg_list.append({"symbol": sym, "valence": abs(v), "count": cnt})
	else:
		# 自动检测：金属优先正价，非金属优先负价
		for sym in elem_counts:
			var sample = null
			for c in cards:
				if c.symbol == sym: sample = c; break
			if sample == null: continue
			var mp = 0; var mn = 0
			for v in sample.common_valence:
				if v > 0 and v > mp: mp = v
				elif v < 0 and v < mn: mn = v
			if sample.element_type == CardDataScript.TYPE_METAL and mp > 0:
				pos_list.append({"symbol": sym, "valence": mp, "count": elem_counts[sym]})
			elif mn < 0:
				neg_list.append({"symbol": sym, "valence": abs(mn), "count": elem_counts[sym]})

	if pos_list.is_empty() or neg_list.is_empty(): return {}

	# 电荷平衡验证
	var total_pos = 0; var total_neg = 0
	for e in pos_list: total_pos += e.count * e.valence
	for e in neg_list: total_neg += e.count * e.valence
	var ratio_ok = (total_pos == total_neg and total_pos > 0)

	# 构建化学式（含 Unicode 下标）
	var formula = ""
	for e in pos_list: formula += e.symbol + ("" if e.count == 1 else _to_subscript(e.count))
	for e in neg_list: formula += e.symbol + ("" if e.count == 1 else _to_subscript(e.count))

	return {
		"formula": formula,
		"ratio_ok": ratio_ok,
		"total_positive": total_pos,
		"total_negative": total_neg,
		"actual_counts": elem_counts,
	}


# 最大公约数
static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return a


# ============================================================
# 七、单质显示
# ============================================================
# 获取单质的显示名称（含 Unicode 下标，如 H₂）
static func get_element_display(cards: Array) -> String:
	if cards.size() == 1:
		return cards[0].symbol
	if cards.size() == 2 and _is_same_element(cards) and cards[0].symbol in DIATOMIC_SYMBOLS:
		return cards[0].symbol + _to_subscript(2)
	return ""


# 数字转 Unicode 下标字符
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
# 八、比大小规则（族炸 > 化合物 > 单质 → 原子序数和小=大）
#  顺序没有大小比较，不能接通常牌
# ============================================================
# 比较两组牌的大小
# 返回 1 表示 cards_a 更大，-1 表示 cards_b 更大，0 表示相等
static func compare_cards(cards_a: Array, cards_b: Array) -> int:
	var pattern_a = detect_pattern(cards_a)
	var pattern_b = detect_pattern(cards_b)

	if pattern_a == -1 or pattern_b == -1:
		return 0

	# 顺序不能进行大小比较
	if pattern_a == CardPattern.SEQUENCE or pattern_b == CardPattern.SEQUENCE:
		return 0

	# 族炸 > 其他一切
	if pattern_a == CardPattern.CLAN_BOMB and pattern_b != CardPattern.CLAN_BOMB:
		return 1
	if pattern_b == CardPattern.CLAN_BOMB and pattern_a != CardPattern.CLAN_BOMB:
		return -1

	# 都是族炸：3张 > 2张不论序数大小；同数量比原子序数和（小→大）
	if pattern_a == CardPattern.CLAN_BOMB and pattern_b == CardPattern.CLAN_BOMB:
		if cards_a.size() != cards_b.size():
			if cards_a.size() >= 3:
				return 1
			if cards_b.size() >= 3:
				return -1
			return 1 if cards_a.size() > cards_b.size() else -1
		return _compare_by_total_atomic(cards_a, cards_b)

	# 都是化合物：原子序数和小的更大
	if pattern_a == CardPattern.COMPOUND and pattern_b == CardPattern.COMPOUND:
		return _compare_by_total_atomic(cards_a, cards_b)

	# 都是单质：原子序数和小的更大
	if pattern_a == CardPattern.ELEMENT and pattern_b == CardPattern.ELEMENT:
		return _compare_by_total_atomic(cards_a, cards_b)

	# 都是有机物：原子序数和小的更大
	if pattern_a == CardPattern.ORGANIC and pattern_b == CardPattern.ORGANIC:
		return _compare_by_total_atomic(cards_a, cards_b)

	# 不同牌型：按优先级
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


# 原子序数和越小牌越大。平局时比相对原子质量（质量大→牌小）
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
	# 序数和相同 → 比相对原子质量（大→小，即大质量牌"更弱"）
	if mass_a > mass_b: return -1
	if mass_a < mass_b: return 1
	return 0


# ============================================================
# 九、辅助方法
# ============================================================
# 牌型名称
static func get_pattern_name(pattern: int) -> String:
	match pattern:
		CardPattern.ELEMENT: return "单质"
		CardPattern.COMPOUND: return "化合物"
		CardPattern.CLAN_BOMB: return "族炸！"
		CardPattern.ORGANIC: return "有机物！"
		CardPattern.SEQUENCE: return "顺序"
	return "非法"