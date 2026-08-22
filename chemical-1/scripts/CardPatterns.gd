# ============================================================
# CardPatterns.gd - 牌型计算模块
# 职责：牌型判定 / 顺序检测 / 族炸检测 / 比大小
# 牌型系统：单质 / 化合物 / 族炸 / 有机物 / 顺序
# ============================================================

const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")

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

	if CompoundSolverScript.is_organic(cards):
		return CardPattern.ORGANIC

	if cards.size() >= 2 and CompoundSolverScript.is_compound(cards):
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
# 四、族炸检测
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
# 五、单质显示
# ============================================================
static func get_element_display(cards: Array) -> String:
	if cards.size() == 1:
		return cards[0].symbol
	if cards.size() == 2 and _is_same_element(cards) and cards[0].symbol in DIATOMIC_SYMBOLS:
		return cards[0].symbol + CompoundSolverScript._to_subscript(2)
	return ""


# ============================================================
# 六、比大小规则
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
# 七、辅助方法
# ============================================================
static func get_pattern_name(pattern: int) -> String:
	match pattern:
		CardPattern.ELEMENT: return "单质"
		CardPattern.COMPOUND: return "化合物"
		CardPattern.CLAN_BOMB: return "族炸！"
		CardPattern.ORGANIC: return "有机物！"
		CardPattern.SEQUENCE: return "顺序"
	return "非法"
