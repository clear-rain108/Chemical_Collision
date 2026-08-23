# ============================================================
# TutorialController.gd - 教程关卡控制器
# 职责：教程关卡初始化 / 预设手牌 / 引导文本 / 进度检查
# 从 GameManager 拆出的独立模块（行为与原先完全一致）
# ============================================================
extends RefCounted

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const PlayerManagerScript = preload("res://scripts/PlayerManager.gd")

# 教程状态（由外部 GameManager 委托访问）
var tutorial_level: int = 0
var tutorial_step: int = 0
var tutorial_guidance: String = ""
var tutorial_success: String = ""
var tutorial_level0_phase: int = 0
var ai_no_draw: bool = false
var level0_rule_tip: String = ""
var level0_last_player_action: String = ""

# 规则引擎引用（用于访问 players/database 等游戏状态）
var game_manager: RefCounted = null


func _init(gm: RefCounted = null):
	game_manager = gm


# ============================================================
# 一、关卡初始化
# ============================================================
# 初始化教程关卡（需在调用前由 GameManager 清空玩家并准备牌库）
func init_tutorial(level: int) -> bool:
	var gm = game_manager
	if gm == null:
		return false
	tutorial_level = level
	tutorial_level0_phase = 0
	ai_no_draw = false
	level0_rule_tip = ""
	level0_last_player_action = ""

	if level == 0:
		_init_level0_deck()
		gm.players.append(PlayerManagerScript.PlayerInfo.new("玩家", false))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 1", true))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 2", true))

		# AI 固定手牌：O, S, C, Si, H, Mg 各1张
		_set_preset_hand(gm.players[1], ["O", "S", "C", "Si", "H", "Mg"])
		_set_preset_hand(gm.players[2], ["O", "S", "C", "Si", "H", "Mg"])

		# AI 各补2张非0族随机牌
		for ai_idx in [1, 2]:
			var ai = gm.players[ai_idx]
			var non_noble_pool: Array = []
			for card in gm.database.deck:
				if card.group != "0":
					non_noble_pool.append(card)
			non_noble_pool.shuffle()
			for card in non_noble_pool:
				if ai.get_hand_count() >= 8:
					break
				var new_card = _copy_card(card)
				ai.add_card(new_card)
				gm.database.deck.erase(card)

		var player_cards = gm.database.draw_cards(8)
		for card in player_cards:
			gm.players[0].add_card(card)
		gm.players[0].sort_hand_by_atomic_number()

		ai_no_draw = true
		gm.clan_bomb_disabled = false
		tutorial_level0_phase = 0
		tutorial_step = 0
		tutorial_success = ""
		tutorial_guidance = ""
		_update_tutorial_level0_guidance()

	elif level == 1:
		gm.clan_bomb_disabled = true
		gm.players.append(PlayerManagerScript.PlayerInfo.new("玩家", false))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 1", true))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 2", true))
		_set_preset_hand(gm.players[0], ["Na","Cl","Ca","O","He","Li","F","Mg","S","Ne"])
		_set_preset_hand(gm.players[1], ["K","Br","B","C","Al","Si","N","P"])
		_set_preset_hand(gm.players[2], ["H","Be","Ar","Cr","Mn","Fe","Co","Ni"])
	elif level == 2:
		gm.players.append(PlayerManagerScript.PlayerInfo.new("玩家", false))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 1", true))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 2", true))
		gm.players.append(PlayerManagerScript.PlayerInfo.new("AI 3", true))
		_set_preset_hand(gm.players[0], ["H","Li","Na","Cl","K","O","Ca","F","He","Ne"])
		_set_preset_hand(gm.players[1], ["Mg","S","Al","P","B","Si","C","N","Br","Be"])
		_set_preset_hand(gm.players[2], ["Ar","Cr","Mn","Fe","Co","Ni","Cu","Zn"])
		_set_preset_hand(gm.players[3], ["He","Ne","O","F","Cl","Ar","K","Ca"])
	else:
		return false

	if level != 0:
		tutorial_step = 1
		tutorial_success = ""
		_update_tutorial_guidance()

	return true


# ============================================================
# 二、辅助方法
# ============================================================
func _init_level0_deck() -> void:
	var gm = game_manager
	var first18 = ["H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar"]
	var full_db = CardDatabaseScript.new()
	full_db.generate_deck()
	gm.database.deck.clear()
	var counts: Dictionary = {}
	for sym in first18:
		counts[sym] = 0
	for card in full_db.deck:
		if card.symbol in first18 and counts[card.symbol] < 3:
			gm.database.deck.append(_copy_card(card))
			counts[card.symbol] += 1
	gm.database.shuffle()


func _copy_card(card):
	return CardDataScript.from_dict(card.to_dict())


func _set_preset_hand(player: PlayerManagerScript.PlayerInfo, symbols: Array) -> void:
	var gm = game_manager
	for sym in symbols:
		var card = _find_card_by_symbol(sym)
		if card != null:
			player.add_card(card)
	player.sort_hand_by_atomic_number()


func _find_card_by_symbol(sym: String):
	var gm = game_manager
	for card in gm.database.deck:
		if card.symbol == sym:
			gm.database.deck.erase(card)
			return CardDataScript.from_dict(card.to_dict())
	return null


# ============================================================
# 三、引导文本与进度检查
# ============================================================
func _update_tutorial_guidance() -> void:
	if tutorial_level == 1:
		match tutorial_step:
			1: tutorial_guidance = "【第1步】观察手牌：每张牌显示元素符号+中文名。鼠标悬停可查看原子序数、族、化合价、相对质量。\n点击选中一张牌，再点「出牌(选牌型)」→「作为单质打出」试试！"
			2: tutorial_guidance = "【第2步】很好！现在试试合成化合物：选中两种不同元素(如Na和Cl)，点「合成化合物」→为每种选化合价→确认打出。\n金属优先正价，非金属优先负价。"
			3: tutorial_guidance = "【第3步】继续练习！尝试不同的单质和化合物组合。\n记住：原子序数和越小，牌力越大。桌面牌必须被你出的牌压过。"
			_: tutorial_guidance = "【练习中】继续出牌直到打光手牌！随时可跳过抽牌。"
	elif tutorial_level == 2:
		match tutorial_step:
			1: tutorial_guidance = "【第1步】熟悉族炸：选中同族≥2张不同元素(如H+Li都是IA族)，点「作为族炸打出」。\n族炸可以抢牌权，比普通牌更强！"
			2: tutorial_guidance = "【第2步】族炸打出后进入冷却❄，必须出一个化合物来解除冷却。\n选中两种元素合成化合物，像Na+Cl=NaCl。"
			3: tutorial_guidance = "【第3步】试试接炸！当AI打出族炸后，你如果也有同族牌可出更大族炸接炸。\n也可以跳过让AI接炸。"
			4: tutorial_guidance = "【第4步】注意手牌上限！手牌达到上限时不能跳过，需选择1张弃置。\n继续练习直到打完所有手牌！"
			_: tutorial_guidance = "【练习中】继续游戏！利用族炸+化合物完成对局。"


func _update_tutorial_level0_guidance() -> void:
	if tutorial_level != 0:
		return
	match tutorial_level0_phase:
		1: tutorial_guidance = ""
		2: tutorial_guidance = ""
		3: tutorial_guidance = "【牌局中】尝试出牌！你可以打出单质、化合物或族炸。AI默认只出单质和化合物。"


func check_tutorial_progress(pattern: int, player_is_human: bool) -> void:
	if not player_is_human:
		return
	tutorial_success = ""
	var advanced = false

	if tutorial_level == 0:
		pass
	elif tutorial_level == 1:
		if tutorial_step == 1 and pattern == CardPatternsScript.CardPattern.ELEMENT:
			tutorial_success = "✓ 正确！你打出了一张单质。"
			advanced = true
		elif tutorial_step == 2 and pattern == CardPatternsScript.CardPattern.COMPOUND:
			tutorial_success = "✓ 正确！你成功合成了一个化合物。"
			advanced = true
		elif tutorial_step == 3 and pattern == CardPatternsScript.CardPattern.COMPOUND:
			tutorial_success = "✓ 很好！继续练习。"
			advanced = true
	elif tutorial_level == 2:
		if tutorial_step == 1 and pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
			tutorial_success = "✓ 正确！你打出了族炸，抢到了牌权！注意你进入了冷却❄。"
			advanced = true
		elif tutorial_step == 2 and pattern == CardPatternsScript.CardPattern.COMPOUND:
			tutorial_success = "✓ 正确！打出化合物解除了族炸冷却。"
			advanced = true
		elif tutorial_step == 3 and pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
			tutorial_success = "✓ 正确！你成功接炸了！"
			advanced = true
		elif tutorial_step == 4:
			tutorial_success = "继续练习！"
			advanced = true

	if advanced and tutorial_step < 5:
		tutorial_step += 1
		_update_tutorial_guidance()


func get_tutorial_display() -> String:
	var text = tutorial_guidance
	if tutorial_success != "":
		text += "\n" + tutorial_success
	return text
