# ============================================================
# Utils.gd - 工具函数：牌型判定、化合价检测、族炸检测
# 牌型系统：单质 / 化合物 / 族炸
# ============================================================

const CardDataScript = preload("res://scripts/CardData.gd")

# 牌型枚举
enum CardPattern {
	ELEMENT,      # 单质（1 张，或双原子分子的 2 张同元素）
	COMPOUND,     # 化合物（多元素化合价匹配）
	CLAN_BOMB,    # 族炸（同族 ≥2 张不同元素）
}

# 双原子分子元素符号集合（自然界中以 X₂ 形式存在）
const DIATOMIC_SYMBOLS = ["H", "N", "O", "F", "Cl"]


# 判定一组牌的牌型
static func detect_pattern(cards: Array) -> int:
	if cards.is_empty():
		return -1

	# 1 张 → 单质
	if cards.size() == 1:
		return CardPattern.ELEMENT

	# 2 张同元素 → 双原子分子单质 / 族炸检查
	if cards.size() == 2 and _is_same_element(cards):
		if cards[0].symbol in DIATOMIC_SYMBOLS:
			return CardPattern.ELEMENT   # 双原子分子单质
		return -1  # 非法

	# 检查族炸（同族不同元素 ≥2 张）
	if _is_clan_bomb(cards):
		return CardPattern.CLAN_BOMB

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


# 检查是否为族炸（同族 ≥2 张不同元素）
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


# 检查是否为化合物（多元素化合价匹配）
static func _is_compound(cards: Array) -> bool:
	if cards.size() < 2:
		return false

	# 检查是否有稀有气体（通常不形成化合物）
	for c in cards:
		if c.element_type == CardDataScript.TYPE_NOBLE_GAS:
			return false

	# 计算化合价代数和是否能配平
	if _can_balance_valence(cards):
		return true

	return false


# 检查化合价是否能配平
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


# 获取化合价配平比例（用于化合物显示）
# 返回值包含 formula 和 ratio_check（出牌数量是否匹配最简比）
static func get_compound_formula(cards: Array) -> Dictionary:
	if not _is_compound(cards):
		return {}

	# 统计每种元素的出现次数（用于比值检查）
	var elem_counts: Dictionary = {}
	for c in cards:
		if not elem_counts.has(c.symbol):
			elem_counts[c.symbol] = 0
		elem_counts[c.symbol] += 1

	# 为每种元素选取其最大正价或负价
	var pos_info: Array = []   # [{symbol, valence}]
	var neg_info: Array = []   # [{symbol, valence}]

	for c in cards:
		var max_pos = 0
		var max_neg = 0
		for v in c.common_valence:
			if v > 0 and v > max_pos:
				max_pos = v
			elif v < 0 and v < max_neg:
				max_neg = v

		if max_pos > 0:
			pos_info.append({"symbol": c.symbol, "valence": max_pos})
			break  # 只用第一次出现的正价元素定比（简化）

	if pos_info.is_empty():
		return {}

	for c in cards:
		var max_neg = 0
		for v in c.common_valence:
			if v < 0 and v < max_neg:
				max_neg = v
		if max_neg < 0:
			neg_info.append({"symbol": c.symbol, "valence": abs(max_neg)})
			break  # 只用第一次出现的负价元素定比

	if neg_info.is_empty():
		return {}

	var pos_val = pos_info[0].valence
	var neg_val = neg_info[0].valence
	var pos_symbol = pos_info[0].symbol
	var neg_symbol = neg_info[0].symbol

	# 最简整数比：正价 a 个原子 × neg_val，负价 b 个原子 × pos_val
	# pos_val * a = neg_val * b  →  a:b = neg_val:pos_val
	var g = _gcd(pos_val, neg_val)
	var ratio_pos = neg_val / g    # 正价元素需要的原子数
	var ratio_neg = pos_val / g    # 负价元素需要的原子数

	# 检查出牌数量是否匹配最简比
	var ratio_ok = false
	if elem_counts.has(pos_symbol) and elem_counts.has(neg_symbol):
		var actual_pos = elem_counts[pos_symbol]
		var actual_neg = elem_counts[neg_symbol]
		# 检查比例是否匹配（允许倍数放大）
		if actual_pos > 0 and actual_neg > 0:
			var k = float(actual_pos) / ratio_pos
			if k >= 1 and k == floor(k):
				if int(actual_neg) == int(ratio_neg * k):
					ratio_ok = true

	# 构建化学式
	var formula = ""
	formula += pos_symbol
	if ratio_neg > 1:
		formula += str(ratio_neg)
	formula += neg_symbol
	if ratio_pos > 1:
		formula += str(ratio_pos)

	return {
		"formula": formula,
		"ratio_ok": ratio_ok,
		"ratio": {"pos_symbol": pos_symbol, "neg_symbol": neg_symbol,
				  "pos_val": pos_val, "neg_val": neg_val,
				  "ratio_pos": ratio_pos, "ratio_neg": ratio_neg},
		"actual_counts": elem_counts,
	}


# 最大公约数
static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return a


# 获取单质的显示名称
static func get_element_display(cards: Array) -> String:
	if cards.size() == 1:
		return cards[0].symbol
	if cards.size() == 2 and _is_same_element(cards) and cards[0].symbol in DIATOMIC_SYMBOLS:
		return cards[0].symbol + "₂"
	return ""


# 比较两组牌的大小
# 序数越小牌越大 — 返回 1 表示 cards_a 更大，-1 表示 cards_b 更大，0 表示相等
static func compare_cards(cards_a: Array, cards_b: Array) -> int:
	var pattern_a = detect_pattern(cards_a)
	var pattern_b = detect_pattern(cards_b)

	if pattern_a == -1 or pattern_b == -1:
		return 0

	# 族炸 > 其他一切
	if pattern_a == CardPattern.CLAN_BOMB and pattern_b != CardPattern.CLAN_BOMB:
		return 1
	if pattern_b == CardPattern.CLAN_BOMB and pattern_a != CardPattern.CLAN_BOMB:
		return -1

	# 都是族炸：3张 > 2张不论序数大小；同数量比原子序数和（小→大）
	if pattern_a == CardPattern.CLAN_BOMB and pattern_b == CardPattern.CLAN_BOMB:
		if cards_a.size() != cards_b.size():
			# 3 张一定大于 2 张，不论族序数
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

	# 不同牌型：按优先级
	var priority = {
		CardPattern.CLAN_BOMB: 2,
		CardPattern.COMPOUND: 1,
		CardPattern.ELEMENT: 0,
	}
	if priority[pattern_a] != priority[pattern_b]:
		return 1 if priority[pattern_a] > priority[pattern_b] else -1

	return _compare_by_total_atomic(cards_a, cards_b)


# 原子序数和越小牌越大（逆转比较）
static func _compare_by_total_atomic(cards_a: Array, cards_b: Array) -> int:
	var sum_a = 0
	var sum_b = 0
	for c in cards_a:
		sum_a += c.atomic_number
	for c in cards_b:
		sum_b += c.atomic_number
	# 序数和小 → 牌大 → 返回 1
	return 1 if sum_a < sum_b else (-1 if sum_a > sum_b else 0)


# 牌型名称
static func get_pattern_name(pattern: int) -> String:
	match pattern:
		CardPattern.ELEMENT: return "单质"
		CardPattern.COMPOUND: return "化合物"
		CardPattern.CLAN_BOMB: return "族炸！"
	return "非法"
