# 临时验证脚本2：验证 GameManager + AIPlayer 集成
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")
	var AIPlayerScript = load("res://scripts/AIPlayer.gd")

	# 1. 创建游戏管理器
	var gm = GameManagerScript.new()
	var ok = gm.init_game(4, 3)
	assert(ok, "init_game(4,3) 应成功")
	assert(gm.players.size() == 4, "应有4名玩家")
	assert(gm.get_current_player() != null, "当前玩家不应为null")
	assert(gm.is_game_over() == false, "游戏未结束")

	# 2. 检查常量转发
	assert(GameManagerScript.MIN_PLAYERS == 3, "MIN_PLAYERS=3")
	assert(GameManagerScript.MAX_PLAYERS == 8, "MAX_PLAYERS=8")

	# 3. 测试日志模块集成
	assert(gm.logger != null, "logger 已创建")
	gm.flush_logs()  # 清空初始化日志
	assert(gm.logger.get_log_count() == 0, "flush后logger应为空")

	# 4. 玩家属性测试
	var p0 = gm.get_current_player()
	assert(p0.is_ai == false, "玩家0是人类")
	assert(p0.get_hand_count() == 8, "初始手牌8张")

	# 5. AIPlayer 决策调用（不实际出牌，只确认接口可调用且不崩溃）
	# 由于是 headless 且未连接 UI，_refresh_ui 回调为空，测试 auto_play 空安全
	var empty_cb = Callable()
	AIPlayerScript.auto_play(gm, empty_cb)
	# auto_play 应因当前玩家是人类而直接返回
	print("PASS: AIPlayer.auto_play 空安全")

	# 6. 非法人数校验
	assert(gm.init_game(2, 1) == false, "init_game(2,1) 应失败")
	assert(gm.init_game(9, 1) == false, "init_game(9,1) 应失败")

	print("ALL INTEGRATION TESTS PASSED")
	quit(0)
