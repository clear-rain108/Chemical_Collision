# 临时验证脚本5：验证 AI 达上限自动弃牌（Q1+Q2）
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")
	var gm = GameManagerScript.new()
	var ok = gm.init_game(4, 3)
	assert(ok, "init_game 成功")

	# 模拟 AI 手牌达到上限（4人上限 = 16）
	var ai = gm.players[1]
	assert(ai.is_ai, "玩家1是AI")
	# 从牌库补充牌到 16 张
	var db = gm.get_database()
	while ai.get_hand_count() < 16:
		var cards = db.draw_cards(1)
		if cards.is_empty(): break
		ai.add_card(cards[0])
	assert(ai.get_hand_count() == 16, "AI手牌应为16（达上限）")

	# 记录弃牌前手牌数
	var before_count = ai.get_hand_count()
	# AI 跳过（player_pass）应自动弃 1 张
	gm.player_pass(1)
	assert(ai.get_hand_count() == before_count - 1, "AI达上限跳过应自动弃1张")

	# 检查日志
	var logs = gm.flush_logs()
	var has_discard_log = false
	for l in logs:
		if l.find("自动弃置") >= 0:
			has_discard_log = true
	assert(has_discard_log, "日志应包含自动弃置记录")

	# 人类玩家达上限跳过时不自动弃牌（由 UI 处理）
	var human = gm.players[0]
	var db2 = gm.get_database()
	while human.get_hand_count() < 16:
		var cards = db2.draw_cards(1)
		if cards.is_empty(): break
		human.add_card(cards[0])
	var human_before = human.get_hand_count()
	gm.player_pass(0)
	assert(human.get_hand_count() == human_before, "人类玩家达上限跳过不自动弃牌")

	print("ALL AI DISCARD TESTS PASSED")
	quit(0)
