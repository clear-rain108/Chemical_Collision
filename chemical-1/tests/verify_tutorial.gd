# 临时验证脚本4：验证教程控制器解耦后的教程初始化
extends SceneTree

func _init():
	var GameManagerScript = load("res://scripts/GameManager.gd")

	# 1. 教程关卡1（禁止族炸）
	var gm = GameManagerScript.new()
	var ok = gm.init_tutorial(1)
	assert(ok, "init_tutorial(1) 应成功")
	assert(gm.players.size() == 3, "关卡1应有3名玩家")
	assert(gm.tutorial_level == 1, "tutorial_level 应同步为1")
	assert(gm.tutorial_step == 1, "tutorial_step 应同步为1")
	assert(gm.clan_bomb_disabled == true, "关卡1应禁止族炸")
	assert(gm.tutorial_controller != null, "教程控制器应已创建")

	# 2. 教程关卡2
	gm = GameManagerScript.new()
	ok = gm.init_tutorial(2)
	assert(ok, "init_tutorial(2) 应成功")
	assert(gm.players.size() == 4, "关卡2应有4名玩家")
	assert(gm.tutorial_level == 2, "tutorial_level 应同步为2")

	# 3. 第0关
	gm = GameManagerScript.new()
	ok = gm.init_tutorial(0)
	assert(ok, "init_tutorial(0) 应成功")
	assert(gm.players.size() == 3, "第0关应有3名玩家")
	assert(gm.ai_no_draw == true, "第0关AI不抽牌")
	assert(gm.tutorial_level0_phase == 0, "第0关初始阶段为0")

	# 4. 非法关卡
	assert(gm.init_tutorial(99) == false, "非法关卡应失败")

	print("ALL TUTORIAL TESTS PASSED")
	quit(0)
