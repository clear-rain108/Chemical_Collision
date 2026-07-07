# ============================================================
# CardDatabase.gd - 牌库生成与洗牌
# 迭代 2：前三周期 18 种元素，每种 6 张 = 108 张
# ============================================================

const CardDataScript = preload("res://scripts/CardData.gd")

# 前三周期 18 种元素基础数据
static func get_element_data() -> Array:
	return [
		# 符号, 中文名, 英文名, 原子序数, 族, 周期, 类型, 单质形态, 最外层电子, 常见化合价, 电负性, 原子质量, 描述
		["H", "氢", "Hydrogen", 1, CardDataScript.GROUP_IA, 1, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 1, [1, -1], 2.20, 1.008, "宇宙中最丰富的元素"],
		["He", "氦", "Helium", 2, CardDataScript.GROUP_0, 1, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 2, [0], 0.0, 4.003, "最轻的稀有气体"],
		["Li", "锂", "Lithium", 3, CardDataScript.GROUP_IA, 2, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.98, 6.941, "最轻的金属"],
		["Be", "铍", "Beryllium", 4, CardDataScript.GROUP_IIA, 2, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.57, 9.012, "轻质高强度金属"],
		["B", "硼", "Boron", 5, CardDataScript.GROUP_IIIA, 2, CardDataScript.TYPE_METALLOID, CardDataScript.FORM_SOLID, 3, [3], 2.04, 10.811, "硬度仅次于金刚石"],
		["C", "碳", "Carbon", 6, CardDataScript.GROUP_IVA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 4, [4, -4], 2.55, 12.011, "生命的基础元素"],
		["N", "氮", "Nitrogen", 7, CardDataScript.GROUP_VA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 5, [-3, 3, 5], 3.04, 14.007, "大气中含量最多的气体"],
		["O", "氧", "Oxygen", 8, CardDataScript.GROUP_VIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 6, [-2], 3.44, 15.999, "维持生命必需的气体"],
		["F", "氟", "Fluorine", 9, CardDataScript.GROUP_VIIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1], 3.98, 18.998, "最活泼的非金属"],
		["Ne", "氖", "Neon", 10, CardDataScript.GROUP_0, 2, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 8, [0], 0.0, 20.180, "霓虹灯中发光的气体"],
		["Na", "钠", "Sodium", 11, CardDataScript.GROUP_IA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.93, 22.990, "活泼的碱金属"],
		["Mg", "镁", "Magnesium", 12, CardDataScript.GROUP_IIA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.31, 24.305, "叶绿素的核心元素"],
		["Al", "铝", "Aluminium", 13, CardDataScript.GROUP_IIIA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 3, [3], 1.61, 26.982, "地壳中含量最丰富的金属"],
		["Si", "硅", "Silicon", 14, CardDataScript.GROUP_IVA, 3, CardDataScript.TYPE_METALLOID, CardDataScript.FORM_SOLID, 4, [4], 1.90, 28.086, "半导体工业的核心"],
		["P", "磷", "Phosphorus", 15, CardDataScript.GROUP_VA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 5, [-3, 3, 5], 2.19, 30.974, "DNA的重要组成部分"],
		["S", "硫", "Sulfur", 16, CardDataScript.GROUP_VIA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 6, [-2, 4, 6], 2.58, 32.066, "火山口常见的黄色物质"],
		["Cl", "氯", "Chlorine", 17, CardDataScript.GROUP_VIIA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1, 1, 3, 5, 7], 3.16, 35.453, "消毒和漂白的重要元素"],
		["Ar", "氩", "Argon", 18, CardDataScript.GROUP_0, 3, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 8, [0], 0.0, 39.948, "大气中第三多的气体"],
	]


const COPIES_PER_ELEMENT = 6
const TOTAL_CARDS = 108  # 18 × 6

var deck: Array = []   # 当前牌库


# 生成牌库（18 种元素 × 6 张 = 108 张）
func generate_deck() -> void:
	deck.clear()
	var elem_data = get_element_data()
	for elem in elem_data:
		for _copy in range(COPIES_PER_ELEMENT):
			var card = CardDataScript.new(
				elem[0], elem[1], elem[2], elem[3], elem[4],
				elem[5], elem[6], elem[7], elem[8], elem[9],
				elem[10], elem[11], elem[12]
			)
			deck.append(card)


# 洗牌（Fisher-Yates 洗牌算法）
func shuffle() -> void:
	var n = deck.size()
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp


# 从牌库顶部抽一张牌
func draw_card():
	if deck.is_empty():
		return null
	return deck.pop_back()


# 从牌库抽指定数量
func draw_cards(count: int) -> Array:
	var drawn: Array = []
	for _i in range(count):
		var card = draw_card()
		if card == null:
			break
		drawn.append(card)
	return drawn


# 获取牌库剩余数量
func get_remaining_count() -> int:
	return deck.size()