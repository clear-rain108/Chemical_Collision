# ============================================================
# CardData.gd - 卡牌数据结构（含单质形态）
# 定义单张化学元素卡牌的所有属性
# ============================================================

# ============================================================
# 一、族常量定义（16个周期表族）
# ============================================================
const GROUP_IA = "IA"       # 碱金属
const GROUP_IIA = "IIA"     # 碱土金属
const GROUP_IIIA = "IIIA"   # 硼族
const GROUP_IVA = "IVA"     # 碳族
const GROUP_VA = "VA"       # 氮族
const GROUP_VIA = "VIA"     # 氧族
const GROUP_VIIA = "VIIA"   # 卤素
const GROUP_0 = "0"         # 稀有气体
const GROUP_IB = "IB"       # 铜族
const GROUP_IIB = "IIB"     # 锌族
const GROUP_IIIB = "IIIB"   # 钪族
const GROUP_IVB = "IVB"     # 钛族
const GROUP_VB = "VB"       # 钒族
const GROUP_VIB = "VIB"     # 铬族
const GROUP_VIIB = "VIIB"   # 锰族
const GROUP_VIII = "VIII"   # 铁族/铂族

# ============================================================
# 二、元素类型常量
# ============================================================
const TYPE_METAL = "金属"
const TYPE_NONMETAL = "非金属"
const TYPE_METALLOID = "准金属"
const TYPE_NOBLE_GAS = "稀有气体"

# ============================================================
# 三、单质形态常量
# ============================================================
const FORM_SOLID = "固体"
const FORM_LIQUID = "液体"
const FORM_GAS = "气体"
const FORM_SYNTHETIC = "人造"

# ============================================================
# 四、卡牌属性字段
# ============================================================
var symbol: String = ""             # 元素符号，如 "H"
var name_cn: String = ""            # 中文名称，如 "氢"
var name_en: String = ""            # 英文名称，如 "Hydrogen"
var atomic_number: int = 0          # 原子序数
var group: String = ""              # 所属族
var period: int = 0                 # 周期
var element_type: String = ""       # 元素类型（金属/非金属/准金属/稀有气体）
var single_form: String = ""        # 单质形态（固体/液体/气体/人造）
var valence_electrons: int = 0      # 最外层电子数
var common_valence: Array = []      # 常见化合价列表，如 [1, 2]
var electronegativity: float = 0.0  # 电负性
var atomic_weight: float = 0.0      # 相对原子质量
var description: String = ""        # 描述文本


# ============================================================
# 五、构造函数
# ============================================================
func _init(sym: String = "", namecn: String = "", nameen: String = "",
		anum: int = 0, grp: String = "", per: int = 0, etype: String = "",
		sform: String = "", valence_e: int = 0, c_valence: Array = [],
		eneg: float = 0.0, aweight: float = 0.0, desc: String = ""):
	symbol = sym
	name_cn = namecn
	name_en = nameen
	atomic_number = anum
	group = grp
	period = per
	element_type = etype
	single_form = sform
	valence_electrons = valence_e
	common_valence = c_valence
	electronegativity = eneg
	atomic_weight = aweight
	description = desc


# ============================================================
# 六、显示方法
# ============================================================
# 获取卡牌显示文本（符号 + 中文名）
func get_display_name() -> String:
	return "%s %s" % [symbol, name_cn]


# 获取完整信息文本（英文名/原子序数/族/化合价/质量）
func get_full_info() -> String:
	var valence_str = " ".join(common_valence) if common_valence.size() > 0 else "N/A"
	return """%s
  Atomic #: %d
  Group: %s
  Valence: %s
  Mass: %.2f""" % [name_en, atomic_number, group, valence_str, atomic_weight]


# ============================================================
# 七、逻辑判断方法
# ============================================================
# 判断是否为同族
func is_same_group(other) -> bool:
	return other != null and group != "" and group == other.group


# 检查化合价是否匹配（是否存在一正一负可配平）
func can_bond_with(other) -> bool:
	if other == null:
		return false
	for v1 in common_valence:
		for v2 in other.common_valence:
			if v1 > 0 and v2 < 0:
				return true
			if v1 < 0 and v2 > 0:
				return true
	return false


# ============================================================
# 八、序列化方法
# ============================================================
# JSON 序列化
func to_dict() -> Dictionary:
	return {
		"symbol": symbol,
		"name_cn": name_cn,
		"name_en": name_en,
		"atomic_number": atomic_number,
		"group": group,
		"period": period,
		"element_type": element_type,
		"single_form": single_form,
		"valence_electrons": valence_electrons,
		"common_valence": common_valence,
		"electronegativity": electronegativity,
		"atomic_weight": atomic_weight,
		"description": description,
	}


# JSON 反序列化
static func from_dict(data: Dictionary):
	var card = load("res://scripts/CardData.gd").new()
	card.symbol = data.get("symbol", "")
	card.name_cn = data.get("name_cn", "")
	card.name_en = data.get("name_en", "")
	card.atomic_number = data.get("atomic_number", 0)
	card.group = data.get("group", "")
	card.period = data.get("period", 0)
	card.element_type = data.get("element_type", "")
	card.single_form = data.get("single_form", "")
	card.valence_electrons = data.get("valence_electrons", 0)
	card.common_valence = data.get("common_valence", [])
	card.electronegativity = data.get("electronegativity", 0.0)
	card.atomic_weight = data.get("atomic_weight", 0.0)
	card.description = data.get("description", "")
	return card