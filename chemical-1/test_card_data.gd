extends Node

const CardData = preload("res://card_data.gd")


func _ready() -> void:
	print("========================================")
	print("CardData 实例化测试")
	print("========================================")

	# 创建氢元素卡牌
	var hydrogen := CardData.new()
	hydrogen.name_cn = "氢"
	hydrogen.symbol = "H"
	hydrogen.atomic_number = 1
	hydrogen.group = "IA"
	hydrogen.valences = [1, -1]
	hydrogen.atomic_mass = 1.008

	print("卡牌 _to_string: ", hydrogen)
	print("  name_cn:       ", hydrogen.name_cn)
	print("  symbol:        ", hydrogen.symbol)
	print("  atomic_number: ", hydrogen.atomic_number)
	print("  group:         ", hydrogen.group)
	print("  valences:      ", hydrogen.valences)
	print("  atomic_mass:   ", hydrogen.atomic_mass)
	print("========================================")
	print("CardData 测试通过 ✓")