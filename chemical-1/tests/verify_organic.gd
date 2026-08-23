# 临时验证脚本7：验证有机物通过"合成化合物"路径打出（含氧有机物扩展）
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")
	var CardPatternsScript = load("res://scripts/CardPatterns.gd")
	var CompoundSolverScript = load("res://scripts/CompoundSolver.gd")
	var CardDataScript = load("res://scripts/CardData.gd")

	var H = CardDataScript.new("H", "氢", "Hydrogen", 1, CardDataScript.GROUP_IA, 1, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 1, [1, -1], 2.20, 1.008, "氢")
	var C = CardDataScript.new("C", "碳", "Carbon", 6, CardDataScript.GROUP_IVA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 4, [4, -4], 2.55, 12.011, "碳")
	var O = CardDataScript.new("O", "氧", "Oxygen", 8, CardDataScript.GROUP_VIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 6, [-2], 3.44, 15.999, "氧")

	# 1. 含氧有机物检测验证
	var methane = [C, H, H, H, H]          # CH4 烷烃
	var formaldehyde = [C, H, H, O]        # 甲醛 CH2O
	var methanol = [C, H, H, H, H, O]      # 甲醇 CH3OH
	var ethanol = [C, C, H, H, H, H, H, H, O]  # 乙醇 C2H5OH
	var formic = [C, H, H, O, O]           # 甲酸 HCOOH
	var acetic = [C, C, H, H, H, H, O, O]  # 乙酸 CH3COOH

	assert(CompoundSolverScript.is_organic(methane), "CH4应为有机物")
	assert(CompoundSolverScript.is_organic(formaldehyde), "甲醛 CH2O 应为有机物")
	assert(CompoundSolverScript.is_organic(methanol), "甲醇 CH3OH 应为有机物")
	assert(CompoundSolverScript.is_organic(ethanol), "乙醇 C2H5OH 应为有机物")
	assert(CompoundSolverScript.is_organic(formic), "甲酸 HCOOH 应为有机物")
	assert(CompoundSolverScript.is_organic(acetic), "乙酸 CH3COOH 应为有机物")

	assert(CardPatternsScript.detect_pattern(formaldehyde, true) == CardPatternsScript.CardPattern.ORGANIC, "甲醛 detect 应为有机物")
	assert(CompoundSolverScript.get_organic_name(formaldehyde) == "甲醛 CH2O", "甲醛命名")
	assert(CompoundSolverScript.get_organic_name(methanol) == "甲醇 CH3OH", "甲醇命名")
	assert(CompoundSolverScript.get_organic_name(ethanol) == "乙醇 C2H5OH", "乙醇命名")
	assert(CompoundSolverScript.get_organic_name(formic) == "甲酸 HCOOH", "甲酸命名")
	assert(CompoundSolverScript.get_organic_name(acetic) == "乙酸 CH3COOH", "乙酸命名")
	print("PASS: 含氧有机物检测与命名")

	# 2. 甲醛通过"合成化合物"路径（intended_pattern=COMPOUND 放行 ORGANIC）打出获胜
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	gm.organic_rules_enabled = true
	var p0 = gm.players[0]
	p0.hand.clear()
	for card in formaldehyde:
		p0.hand.append(card)
	var r = gm.play_cards(0, formaldehyde, {"_organic": true}, CardPatternsScript.CardPattern.COMPOUND)
	assert(r == 0, "甲醛通过化合物路径应打出成功，r=%d" % r)
	assert(gm.is_game_over() == true, "甲醛打出应立即获胜")
	print("PASS: 甲醛通过化合物路径打出并获胜")

	print("ALL ORGANIC TESTS PASSED")
	quit(0)
