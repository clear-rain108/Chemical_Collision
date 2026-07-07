extends Node

const CardDatabase = preload("res://card_database.gd")


func _ready() -> void:
	# 隐藏 warning：test 脚本独立运行，不依赖 CardDatabase class_name
	# (因为 card_database.gd 已注册为全局类名)

	print("========================================")
	print("CardDatabase.generate_deck() 测试")
	print("========================================")

	var deck: Array = CardDatabase.generate_deck()

	print("牌库大小: ", deck.size(), " (期望: 108)")

	if not deck.is_empty():
		var first_card = deck[0]
		print("第一张牌: ", first_card)
		print("  name_cn:       ", first_card.name_cn)
		print("  symbol:        ", first_card.symbol)
		print("  atomic_number: ", first_card.atomic_number)
		print("  group:         ", first_card.group)
		print("  valences:      ", first_card.valences)
		print("  atomic_mass:   ", first_card.atomic_mass)

		# 统计每种元素的数量
		var counts: Dictionary = {}
		for card in deck:
			var sym: String = card.symbol
			counts[sym] = counts.get(sym, 0) + 1

		var all_6: bool = true
		for sym in counts:
			if counts[sym] != 6:
				print("  ❌ ", sym, " 只有 ", counts[sym], " 张 (期望 6)")
				all_6 = false

		if all_6:
			print("✅ 每种元素均为 6 张，测试通过！")
		else:
			print("❌ 元素数量异常")
	else:
		print("❌ 牌库为空，测试失败！")

	print("========================================")