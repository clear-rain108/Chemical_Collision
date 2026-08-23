# 临时验证脚本9：顺序桌面时下家出牌不受大小比较限制（问题1修复）
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")
	var CardPatternsScript = load("res://scripts/CardPatterns.gd")
	var CardDataScript = load("res://scripts/CardData.gd")

	var gm = GameManagerScript.new()
	gm.init_game(4, 3)

	# 构造顺序牌：Ne(10), Na(11), Mg(12)
	var Ne = CardDataScript.new("Ne", "氖", "Neon", 10, CardDataScript.GROUP_0, 2, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 8, [0], 0.0, 20.180, "氖")
	var Na = CardDataScript.new("Na", "钠", "Sodium", 11, CardDataScript.GROUP_IA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.93, 22.990, "钠")
	var Mg = CardDataScript.new("Mg", "镁", "Magnesium", 12, CardDataScript.GROUP_IIA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 2, [2], 1.31, 24.305, "镁")
	var seq_cards = [Ne, Na, Mg]

	# 模拟上家（玩家0）已打出顺序并指定化合物约束
	gm.sequence_constraint_active = true
	gm.sequence_constraint = CardPatternsScript.CardPattern.COMPOUND
	gm.table_player_index = 0
	gm.is_round_starter = false
	# 桌面保留顺序牌（顺序打出后桌面不清空）
	gm.table_cards = seq_cards
	gm.table_pattern = CardPatternsScript.CardPattern.SEQUENCE

	# 下家（玩家1）出氟化锂 LiF（化合物）
	var Li = CardDataScript.new("Li", "锂", "Lithium", 3, CardDataScript.GROUP_IA, 2, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.98, 6.941, "锂")
	var F = CardDataScript.new("F", "氟", "Fluorine", 9, CardDataScript.GROUP_VIIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1], 3.98, 18.998, "氟")
	var lif = [Li, F]

	# 验证 LiF 检测为化合物
	assert(CardPatternsScript.detect_pattern(lif, true) == CardPatternsScript.CardPattern.COMPOUND, "LiF 应为化合物")

	# 下家打出 LiF（intended=COMPOUND）
	var p1 = gm.players[1]
	p1.hand.clear()
	p1.hand.append(Li)
	p1.hand.append(F)
	var r = gm.play_cards(1, lif, {Li.symbol: 1, F.symbol: -1}, CardPatternsScript.CardPattern.COMPOUND)
	assert(r == 0, "顺序桌面下打出化合物应成功（不受大小比较限制），r=%d" % r)
	print("PASS: 顺序桌面下家出化合物成功")

	# 反向验证：桌面是单质时，下家出化合物仍应被拒绝（确保没有破坏原逻辑）
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	gm2.is_round_starter = false
	gm2.table_cards = [Na]
	gm2.table_pattern = CardPatternsScript.CardPattern.ELEMENT
	gm2.table_player_index = 0
	var p1b = gm2.players[1]
	p1b.hand.clear()
	p1b.hand.append(Li)
	p1b.hand.append(F)
	var r2 = gm2.play_cards(1, lif, {Li.symbol: 1, F.symbol: -1}, CardPatternsScript.CardPattern.COMPOUND)
	assert(r2 != 0, "单质桌面下出化合物应被拒绝（r=%d）" % r2)
	print("PASS: 单质桌面下家出化合物被拒绝（原逻辑未破坏）")

	print("ALL SEQUENCE-TABLE TESTS PASSED")
	quit(0)
