# 临时验证脚本6b：直接验证顺序约束罚抽逻辑（不经过完整 play_cards 顺序流程）
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")

	# 测试 player_fail_sequence_constraint：罚抽2 + 结束约束 + 下下名自由出牌
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)

	# 手动激活顺序约束（模拟玩家0打出顺序后指定"化合物"）
	gm.sequence_constraint_active = true
	gm.sequence_constraint = 1  # COMPOUND
	gm.table_player_index = 0   # 玩家0是出顺序者
	gm.is_round_starter = false

	# 下一名玩家（玩家1）跳过 → player_pass 应罚抽2
	var p1 = gm.players[1]
	var before = p1.get_hand_count()
	gm.player_pass(1)
	assert(p1.get_hand_count() == before + 2, "顺序约束下跳过应罚抽2张")
	assert(gm.sequence_constraint_active == false, "罚抽后约束已结束")
	print("PASS: 顺序约束下跳过罚抽2张")

	# 普通跳过仍只抽1
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	var p1b = gm2.players[1]
	var before2 = p1b.get_hand_count()
	gm2.player_pass(1)
	assert(p1b.get_hand_count() == before2 + 1, "普通跳过仍只抽1张")
	print("PASS: 普通跳过抽1")

	print("ALL SEQUENCE PENALTY TESTS PASSED")
	quit(0)
