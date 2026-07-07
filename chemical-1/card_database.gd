extends Object
class_name CardDatabase

const CardData = preload("res://card_data.gd")

static var _element_data = [
	{ "name_cn": "氢", "symbol": "H",  "atomic_number": 1,  "group": "IA",   "valences": [1, -1],           "atomic_mass": 1.008  },
	{ "name_cn": "氦", "symbol": "He", "atomic_number": 2,  "group": "0族",  "valences": [0],               "atomic_mass": 4.0026 },
	{ "name_cn": "锂", "symbol": "Li", "atomic_number": 3,  "group": "IA",   "valences": [1],               "atomic_mass": 6.94   },
	{ "name_cn": "铍", "symbol": "Be", "atomic_number": 4,  "group": "IIA",  "valences": [2],               "atomic_mass": 9.0122 },
	{ "name_cn": "硼", "symbol": "B",  "atomic_number": 5,  "group": "IIIA", "valences": [3],               "atomic_mass": 10.81  },
	{ "name_cn": "碳", "symbol": "C",  "atomic_number": 6,  "group": "IVA",  "valences": [4, 2, -4],        "atomic_mass": 12.011 },
	{ "name_cn": "氮", "symbol": "N",  "atomic_number": 7,  "group": "VA",   "valences": [3, 5, -3],        "atomic_mass": 14.007 },
	{ "name_cn": "氧", "symbol": "O",  "atomic_number": 8,  "group": "VIA",  "valences": [-2, -1],          "atomic_mass": 15.999 },
	{ "name_cn": "氟", "symbol": "F",  "atomic_number": 9,  "group": "VIIA", "valences": [-1],              "atomic_mass": 18.998 },
	{ "name_cn": "氖", "symbol": "Ne", "atomic_number": 10, "group": "0族",  "valences": [0],               "atomic_mass": 20.180 },
	{ "name_cn": "钠", "symbol": "Na", "atomic_number": 11, "group": "IA",   "valences": [1],               "atomic_mass": 22.990 },
	{ "name_cn": "镁", "symbol": "Mg", "atomic_number": 12, "group": "IIA",  "valences": [2],               "atomic_mass": 24.305 },
	{ "name_cn": "铝", "symbol": "Al", "atomic_number": 13, "group": "IIIA", "valences": [3],               "atomic_mass": 26.982 },
	{ "name_cn": "硅", "symbol": "Si", "atomic_number": 14, "group": "IVA",  "valences": [4, -4],           "atomic_mass": 28.085 },
	{ "name_cn": "磷", "symbol": "P",  "atomic_number": 15, "group": "VA",   "valences": [3, 5, -3],        "atomic_mass": 30.974 },
	{ "name_cn": "硫", "symbol": "S",  "atomic_number": 16, "group": "VIA",  "valences": [2, 4, 6, -2],     "atomic_mass": 32.06  },
	{ "name_cn": "氯", "symbol": "Cl", "atomic_number": 17, "group": "VIIA", "valences": [7, 1, -1],        "atomic_mass": 35.45  },
	{ "name_cn": "氩", "symbol": "Ar", "atomic_number": 18, "group": "0族",  "valences": [0],               "atomic_mass": 39.948 },
]


static func generate_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for elem in _element_data:
		for i in range(6):
			var card := CardData.new()
			card.name_cn = elem["name_cn"]
			card.symbol = elem["symbol"]
			card.atomic_number = elem["atomic_number"]
			card.group = elem["group"]
			var val_arr: Array[int] = []
			for v in elem["valences"]:
				val_arr.append(v)
			card.valences = val_arr
			card.atomic_mass = elem["atomic_mass"]
			deck.append(card)
	return deck