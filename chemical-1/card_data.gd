extends Resource
class_name CardData


@export var name_cn: String = ""          ## 中文名
@export var symbol: String = ""           ## 元素符号
@export var atomic_number: int = 0        ## 原子序数
@export var group: String = ""            ## 族序数（如 "IA", "IIA", ... "0族"）
@export var valences: Array[int] = []     ## 常见化合价列表
@export var atomic_mass: float = 0.0      ## 相对原子质量


func _to_string() -> String:
	return symbol + "(" + name_cn + ")"