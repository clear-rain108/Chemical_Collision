# ============================================================
# CardDatabase.gd - 牌库生成与洗牌
# 前四周期+碘 29 种元素（卤族10张，H/O/S 8张，主族6张，副族4张）
# 补充规则「元素限制」：基础池 = 前 20 号元素（H~Ca），其余 9 种为可勾选扩展
# ============================================================

const CardDataScript = preload("res://scripts/CardData.gd")

# ============================================================
# 一、张数分级常量
# ============================================================
# 副族标识（这些元素只生成 4 张）
const SUBGROUP_SYMBOLS = ["Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn"]
# 特殊张数元素
const HALOGEN_SYMBOLS = ["F", "Cl", "Br", "I"]    # 卤族 10 张
const HIGH_COUNT_SYMBOLS = ["O", "S", "H"]    # 高张数 8 张
const MAIN_COPIES = 6
const SUB_COPIES = 4
const HALOGEN_COPIES = 10
const HIGH_COPIES = 8

# 「元素限制」基础池上限：原子序数 ≤ 20（H ~ Ca，共 20 种）
const BASE_ELEMENT_MAX_NUMBER = 20
# 扩展元素分组标签（元素选择小页按此分组展示）
const EXTRA_GROUP_SUB = "副族"
const EXTRA_GROUP_HALOGEN = "卤族"

# ============================================================
# 二、元素基础数据（29 种）
# ============================================================
static func get_element_data() -> Array:
	return [
		# === 第一周期 ===
		# 符号, 中文名, 英文名, 原子序数, 族, 周期, 类型, 单质形态, 最外层电子, 常见化合价, 电负性, 原子质量, 描述
		["H", "氢", "Hydrogen", 1, CardDataScript.GROUP_IA, 1, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 1, [1, -1], 2.20, 1.008, "宇宙中最丰富的元素"],
		["He", "氦", "Helium", 2, CardDataScript.GROUP_0, 1, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 2, [0], 0.0, 4.003, "最轻的稀有气体"],
		# === 第二周期 ===
		["Li", "锂", "Lithium", 3, CardDataScript.GROUP_IA, 2, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.98, 6.941, "最轻的金属"],
		["Be", "铍", "Beryllium", 4, CardDataScript.GROUP_IIA, 2, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.57, 9.012, "轻质高强度金属"],
		["B", "硼", "Boron", 5, CardDataScript.GROUP_IIIA, 2, CardDataScript.TYPE_METALLOID, CardDataScript.FORM_SOLID, 3, [3], 2.04, 10.811, "硬度仅次于金刚石"],
		["C", "碳", "Carbon", 6, CardDataScript.GROUP_IVA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 4, [4, 2, -4], 2.55, 12.011, "生命的基础元素"],
		["N", "氮", "Nitrogen", 7, CardDataScript.GROUP_VA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 5, [-3, 3, 5], 3.04, 14.007, "大气中含量最多的气体"],
		["O", "氧", "Oxygen", 8, CardDataScript.GROUP_VIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 6, [-2, -1], 3.44, 15.999, "维持生命必需的气体"],
		["F", "氟", "Fluorine", 9, CardDataScript.GROUP_VIIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1], 3.98, 18.998, "最活泼的非金属"],
		["Ne", "氖", "Neon", 10, CardDataScript.GROUP_0, 2, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 8, [0], 0.0, 20.180, "霓虹灯中发光的气体"],
		# === 第三周期 ===
		["Na", "钠", "Sodium", 11, CardDataScript.GROUP_IA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.93, 22.990, "活泼的碱金属"],
		["Mg", "镁", "Magnesium", 12, CardDataScript.GROUP_IIA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.31, 24.305, "叶绿素的核心元素"],
		["Al", "铝", "Aluminium", 13, CardDataScript.GROUP_IIIA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 3, [3], 1.61, 26.982, "地壳中含量最丰富的金属"],
		["Si", "硅", "Silicon", 14, CardDataScript.GROUP_IVA, 3, CardDataScript.TYPE_METALLOID, CardDataScript.FORM_SOLID, 4, [4], 1.90, 28.086, "半导体工业的核心"],
		["P", "磷", "Phosphorus", 15, CardDataScript.GROUP_VA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 5, [-3, 3, 5], 2.19, 30.974, "DNA的重要组成部分"],
		["S", "硫", "Sulfur", 16, CardDataScript.GROUP_VIA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 6, [-2, 4, 6], 2.58, 32.066, "火山口常见的黄色物质"],
		["Cl", "氯", "Chlorine", 17, CardDataScript.GROUP_VIIA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1, 1, 3, 5, 7], 3.16, 35.453, "消毒和漂白的重要元素"],
		["Ar", "氩", "Argon", 18, CardDataScript.GROUP_0, 3, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 8, [0], 0.0, 39.948, "大气中第三多的气体"],
		# === 第四周期（排除 Sc,Ti,V,Ga,Ge,As,Se,Kr） ===
		["K", "钾", "Potassium", 19, CardDataScript.GROUP_IA, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.82, 39.098, "植物生长必需元素"],
		["Ca", "钙", "Calcium", 20, CardDataScript.GROUP_IIA, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.00, 40.078, "骨骼和牙齿的主要成分"],
		["Cr", "铬", "Chromium", 24, CardDataScript.GROUP_VIB, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [2, 3, 6], 1.66, 51.996, "不锈钢的关键成分"],
		["Mn", "锰", "Manganese", 25, CardDataScript.GROUP_VIIB, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2, 4, 7], 1.55, 54.938, "炼钢中的重要添加剂"],
		["Fe", "铁", "Iron", 26, CardDataScript.GROUP_VIII, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2, 3], 1.83, 55.845, "地壳中最丰富的过渡金属"],
		["Co", "钴", "Cobalt", 27, CardDataScript.GROUP_VIII, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2, 3], 1.88, 58.933, "电池和磁性合金的重要元素"],
		["Ni", "镍", "Nickel", 28, CardDataScript.GROUP_VIII, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2, 3], 1.91, 58.693, "硬币和不锈钢的组成元素"],
		["Cu", "铜", "Copper", 29, CardDataScript.GROUP_IB, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1, 2], 1.90, 63.546, "优良的电导体"],
		["Zn", "锌", "Zinc", 30, CardDataScript.GROUP_IIB, 4, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.65, 65.380, "镀锌防腐的重要金属"],
		["Br", "溴", "Bromine", 35, CardDataScript.GROUP_VIIA, 4, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_LIQUID, 7, [-1, 1, 5], 2.96, 79.904, "唯一常温下液态的非金属"],
		# === 第五周期 ===
		["I", "碘", "Iodine", 53, CardDataScript.GROUP_VIIA, 5, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 7, [-1, 1, 5, 7], 2.66, 126.90, "紫黑色固体，升华产生紫色蒸气"],
	]


var deck: Array = []   # 当前牌库


# ============================================================
# 三、牌库生成（按张数分级）
# ============================================================
# allowed_symbols：只生成这些元素的牌；传空数组 = 全部 29 种（默认 / 教程局）
func generate_deck(allowed_symbols: Array = []) -> void:
	deck.clear()
	var elem_data = get_element_data()
	var filtered := not allowed_symbols.is_empty()
	for elem in elem_data:
		var sym = elem[0]
		if filtered and not (sym in allowed_symbols):
			continue
		var copies = get_copies(sym)
		for _copy in range(copies):
			var card = CardDataScript.new(
				elem[0], elem[1], elem[2], elem[3], elem[4],
				elem[5], elem[6], elem[7], elem[8], elem[9],
				elem[10], elem[11], elem[12]
			)
			# uid = 生成下标：牌库结构唯一且与洗牌无关（联机事件寻址用）
			card.uid = deck.size()
			deck.append(card)


# ============================================================
# 四、洗牌与抽牌（Fisher-Yates 算法）
# ============================================================
# rng_seed < 0（默认）：走全局 randi()，单机行为与历史版本完全一致。
# rng_seed >= 0：用独立 RandomNumberGenerator，同一 seed 在任意机器 / 任意次运行
#   都得到同一副牌序 —— 联机确定性（主机权威 + 事件重放）的前提。
func shuffle(rng_seed: int = -1) -> void:
	var n = deck.size()
	if rng_seed < 0:
		for i in range(n - 1, 0, -1):
			var j = randi() % (i + 1)
			var temp = deck[i]
			deck[i] = deck[j]
			deck[j] = temp
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in range(n - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp


func draw_card():
	if deck.is_empty():
		return null
	return deck.pop_back()


func draw_cards(count: int) -> Array:
	var drawn: Array = []
	for _i in range(count):
		var card = draw_card()
		if card == null:
			break
		drawn.append(card)
	return drawn


# ============================================================
# 五、查询方法
# ============================================================
func get_remaining_count() -> int:
	return deck.size()


# ============================================================
# 六、「元素限制」元素池（基础 20 种 + 可选扩展）
# ============================================================
# 单个元素的牌库张数（牌库生成 / 图鉴 / 元素限制统计共用这一处）
static func get_copies(sym: String) -> int:
	if sym in HALOGEN_SYMBOLS:
		return HALOGEN_COPIES
	if sym in HIGH_COUNT_SYMBOLS:
		return HIGH_COPIES
	if sym in SUBGROUP_SYMBOLS:
		return SUB_COPIES
	return MAIN_COPIES


# 原子序数（找不到返回 0）—— 「前 20 号元素」的判定依据
static func get_atomic_number(sym: String) -> int:
	for row in get_element_data():
		if row[0] == sym:
			return int(row[3])
	return 0


# 基础池：前 20 号元素（H ~ Ca，20 种，牌库 134 张）
static func get_base_element_symbols() -> Array:
	var out: Array = []
	for row in get_element_data():
		if int(row[3]) <= BASE_ELEMENT_MAX_NUMBER:
			out.append(row[0])
	return out


# 可额外加入的元素（现牌库中序数 > 20 的 9 种：副族 7 + 卤族 2）
# 返回 [{symbol, name_cn, number, group, group_label}]，保持 get_element_data 的周期顺序
static func get_optional_elements() -> Array:
	var out: Array = []
	for row in get_element_data():
		if int(row[3]) <= BASE_ELEMENT_MAX_NUMBER:
			continue
		out.append({
			"symbol": row[0],
			"name_cn": row[1],
			"number": int(row[3]),
			"group": row[4],
			"group_label": EXTRA_GROUP_HALOGEN if row[0] in HALOGEN_SYMBOLS else EXTRA_GROUP_SUB,
		})
	return out


# 本局牌库允许的元素符号集合：限制关闭 → 空数组（= 全部 29 种）
static func get_allowed_symbols(limit_enabled: bool, extra_symbols: Array) -> Array:
	if not limit_enabled:
		return []
	var out := get_base_element_symbols()
	for sym in extra_symbols:
		if not (sym in out):
			out.append(sym)
	return out


# 按允许集合统计牌库张数（UI 显示「本局牌库 N 张」，空数组 = 182 张）
static func get_deck_size(allowed_symbols: Array = []) -> int:
	var filtered := not allowed_symbols.is_empty()
	var total := 0
	for row in get_element_data():
		if filtered and not (row[0] in allowed_symbols):
			continue
		total += get_copies(row[0])
	return total