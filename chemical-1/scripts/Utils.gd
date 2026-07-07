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
# skip_clan_bomb: 指定"化合物"路径时设为 true，跳过族炸检测
static func detect_pattern(cards: Array, skip_clan_bomb: bool = false) -> int:
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

	# 检查族炸（同族不同元素 ≥2 张）— 可选跳过
	if not skip_clan_bomb:
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


# 获取化合价配平比例
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

	# 多元素化合物形成规则 (支持 2+ 元素)
	# - custom_valences 中的元素决定正/负价划分
	# - 所有正价元素在前，所有负价元素在后
	# - 2 元素: GCD 计算最简比
	# - 3+ 元素: 玩家必须提供准确的原子数 (charge balance: Σ count×valence = 0)

	var pos_list: Array = []    # [{symbol, valence, count}]
	var neg_list: Array = []

	if custom_valences.size() >= 2:
		# 使用自定义化合价
		for sym in custom_valences:
			var v = custom_valences[sym]
			var cnt = elem_counts.get(sym, 0)
			if v > 0:
				pos_list.append({"symbol": sym, "valence": abs(v), "count": cnt})
			else:
				neg_list.append({"symbol": sym, "valence": abs(v), "count": cnt})
	else:
		# 自动检测：按 is_metal 分类
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
	}


# 最大公约数
static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return a


# 获取单质的显示名称（含 Unicode 下标）
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


# 原子序数和越小牌越大（逆转比较）。平局时比相对原子质量（质量大→牌小）
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


# 牌型名称
static func get_pattern_name(pattern: int) -> String:
	match pattern:
		CardPattern.ELEMENT: return "单质"
		CardPattern.COMPOUND: return "化合物"
		CardPattern.CLAN_BOMB: return "族炸！"
	return "非法"
