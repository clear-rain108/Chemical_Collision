# 临时验证脚本：验证重构后的 CardPatterns / CompoundSolver / PlayerManager / AIPlayer / GameLogger 模块
extends SceneTree

func _init():
	var CardDataScript = load("res://scripts/CardData.gd")
	var CardPatternsScript = load("res://scripts/CardPatterns.gd")
	var CompoundSolverScript = load("res://scripts/CompoundSolver.gd")
	var PlayerManagerScript = load("res://scripts/PlayerManager.gd")
	var GameLoggerScript = load("res://scripts/GameLogger.gd")
	var AIPlayerScript = load("res://scripts/AIPlayer.gd")

	# 1. GameLogger 测试
	var logger = GameLoggerScript.new()
	logger.add_log("测试日志1")
	logger.add_log("测试日志2")
	assert(logger.get_log_count() == 2, "GameLogger: 日志数量应为2")
	var logs = logger.flush_logs()
	assert(logs.size() == 2, "GameLogger: flush_logs 应返回2条")
	assert(logger.get_log_count() == 0, "GameLogger: flush后应为0")
	print("PASS: GameLogger")

	# 2. PlayerManager 测试
	var players = PlayerManagerScript.create_players(4, 3)
	assert(players.size() == 4, "PlayerManager: 应创建4名玩家")
	assert(players[0].is_ai == false, "PlayerManager: 玩家0应为人类")
	assert(players[3].is_ai == true, "PlayerManager: 玩家3应为AI")
	assert(PlayerManagerScript.validate_player_count(4, 3) == true, "PlayerManager: 合法配置")
	assert(PlayerManagerScript.validate_player_count(2, 1) == false, "PlayerManager: 非法配置")
	assert(PlayerManagerScript.get_hand_limit(4) == 16, "PlayerManager: 4人上限16")
	assert(PlayerManagerScript.get_hand_limit(8) == 18, "PlayerManager: 8人上限18")
	var p = players[0]
	p.add_card(null)
	assert(p.get_hand_count() == 0, "PlayerManager: add_card(null) 不应增加")
	print("PASS: PlayerManager")

	# 3. CardPatterns / CompoundSolver 测试（构建两对卡牌）
	var H = CardDataScript.new("H", "氢", "Hydrogen", 1, CardDataScript.GROUP_IA, 1, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 1, [1, -1], 2.20, 1.008, "氢")
	var O = CardDataScript.new("O", "氧", "Oxygen", 8, CardDataScript.GROUP_VIA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 6, [-2], 3.44, 15.999, "氧")
	var Na = CardDataScript.new("Na", "钠", "Sodium", 11, CardDataScript.GROUP_IA, 3, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.93, 22.990, "钠")
	var Cl = CardDataScript.new("Cl", "氯", "Chlorine", 17, CardDataScript.GROUP_VIIA, 3, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_GAS, 7, [-1, 1, 3, 5, 7], 3.16, 35.453, "氯")
	var Li = CardDataScript.new("Li", "锂", "Lithium", 3, CardDataScript.GROUP_IA, 2, CardDataScript.TYPE_METAL, CardDataScript.FORM_SOLID, 1, [1], 0.98, 6.941, "锂")
	var He = CardDataScript.new("He", "氦", "Helium", 2, CardDataScript.GROUP_0, 1, CardDataScript.TYPE_NOBLE_GAS, CardDataScript.FORM_GAS, 2, [0], 0.0, 4.003, "氦")

	# 单质检测
	assert(CardPatternsScript.detect_pattern([H]) == CardPatternsScript.CardPattern.ELEMENT, "单张应为单质")
	# 双原子分子
	assert(CardPatternsScript.detect_pattern([H, H]) == CardPatternsScript.CardPattern.ELEMENT, "双原子H2应为单质")
	# 族炸：H + Li 同族IA
	assert(CardPatternsScript.detect_pattern([H, Li]) == CardPatternsScript.CardPattern.CLAN_BOMB, "H+Li同族应为族炸")
	# 化合物：Na + Cl
	assert(CardPatternsScript.detect_pattern([Na, Cl]) == CardPatternsScript.CardPattern.COMPOUND, "Na+Cl应为化合物")
	var fi = CompoundSolverScript.get_compound_formula([Na, Cl])
	assert(fi.get("formula") == "NaCl", "NaCl化学式应为NaCl")
	assert(CompoundSolverScript.get_compound_name([Na, Cl]) == "氯化钠", "NaCl应命名氯化钠")
	# 化合物：H + O (H2O)
	var fi2 = CompoundSolverScript.get_compound_formula([H, H, O])
	assert(fi2.get("formula") == "H₂O", "H2O化学式应为H₂O")
	# 稀有气体不能成化合物
	assert(CardPatternsScript.detect_pattern([He, H]) != CardPatternsScript.CardPattern.COMPOUND, "He+H不应为化合物")
	# 有机物：CH4 (1 C + 4 H)
	var C = CardDataScript.new("C", "碳", "Carbon", 6, CardDataScript.GROUP_IVA, 2, CardDataScript.TYPE_NONMETAL, CardDataScript.FORM_SOLID, 4, [4, -4], 2.55, 12.011, "碳")
	var methane = [C, H, H, H, H]
	assert(CompoundSolverScript.is_organic(methane), "CH4应为有机物")
	assert(CardPatternsScript.detect_pattern(methane) == CardPatternsScript.CardPattern.ORGANIC, "CH4检测应为有机物")

	print("PASS: CardPatterns + CompoundSolver")

	# 4. 比大小测试：Na(11) > H(1)，所以出H压不了Na
	var cmp = CardPatternsScript.compare_cards([H], [Na])
	assert(cmp > 0, "单质H应大于Na（原子序数和更小）")

	print("PASS: compare_cards")

	# 5. AIPlayer 静态存在性检查
	assert(AIPlayerScript.auto_play != null, "AIPlayer.auto_play 应存在")

	print("ALL TESTS PASSED")
	quit(0)
