# 临时验证脚本8：验证顺序指定"化合物"时有机物满足约束（问题3d）
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")
	var CardPatternsScript = load("res://scripts/CardPatterns.gd")
	var CardDataScript = load("res://scripts/CardData.gd")

	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	gm.organic_rules_enabled = true

	# 构造 CH4 有机物
	var H = CardDataScript.new("H", "氢", "Hydrogen", 1, CardDataScript.GROUP_IA, 1, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 1, [1, -1], 2.20, 1.008, "氢")
	var C = CardDataScript.new("C", "碳", "Carbon", 6, CardDataScript.GROUP_IVA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 4, [4, -4], 2.55, 12.011, "碳")
	var methane = [C, H, H, H, H]

	# 激活顺序约束：指定"化合物"
	gm.sequence_constraint_active = true
	gm.sequence_constraint = CardPatternsScript.CardPattern.COMPOUND
	gm.table_player_index = 0  # 玩家0是出顺序者
	gm.is_round_starter = false

	# 玩家1 试图打有机物满足"化合物"约束
	var p1 = gm.players[1]
	p1.hand.clear()
	for card in methane:
		p1.hand.append(card)
	var r = gm.play_cards(1, methane, {"_organic": true}, CardPatternsScript.CardPattern.COMPOUND)
	assert(r == 0, "有机物应满足'化合物'约束，r=%d" % r)
	print("PASS: 顺序指定'化合物'时有机物满足约束")

	# 反向验证：约束"化合物"时，普通化合物也满足
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	gm2.organic_rules_enabled = true
	var Na = CardDataScript.new("Na", "钠", "Sodium", 11, CardDataScript.GROUP_IA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.93, 22.990, "钠")
	var Cl = CardDataScript.new("Cl", "氯", "Chlorine", 17, CardDataScript.GROUP_VIIA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1, 1, 3, 5, 7], 3.16, 35.453, "氯")
	gm2.sequence_constraint_active = true
	gm2.sequence_constraint = CardPatternsScript.CardPattern.COMPOUND
	gm2.table_player_index = 0
	gm2.is_round_starter = false
	var p1b = gm2.players[1]
	p1b.hand.clear()
	p1b.hand.append(Na); p1b.hand.append(Cl)
	var r2 = gm2.play_cards(1, [Na, Cl], {Na.symbol: 1, Cl.symbol: -1}, CardPatternsScript.CardPattern.COMPOUND)
	assert(r2 == 0, "普通化合物应满足'化合物'约束，r=%d" % r2)
	print("PASS: 顺序指定'化合物'时普通化合物满足约束")

	print("ALL CONSTRAINT TESTS PASSED")
	quit(0)
