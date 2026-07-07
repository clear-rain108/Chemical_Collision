extends RefCounted

var name_cn: String
var symbol: String
var atomic_number: int
var group: String       # 族序数，如 "IA", "0族"
var valences: Array    # 常见化合价，如 [1, -1]
var atomic_mass: float

func _init(p_name, p_symbol, p_z, p_group, p_valences, p_mass):
    name_cn = p_name
    symbol = p_symbol
    atomic_number = p_z
    group = p_group
    valences = p_valences
    atomic_mass = p_mass

func card_name() -> String:
    return "%s(%s)" % [symbol, name_cn]
