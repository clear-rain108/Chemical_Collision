# ============================================================
# GameManager.gd - 多人发牌与玩家管理
# 族炸接炸链 + 冷却 + 同牌型接牌
# ============================================================

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

const MIN_PLAYERS = 3
const MAX_PLAYERS = 6
const INITIAL_HAND_SIZE = 8

var database: RefCounted = null
var players: Array = []
var current_player_index: int = 0
var phase: int = 0
var winner_index: int = -1
var table_cards: Array = []
var table_player_index: int = -1
var table_pattern: int = -1    # 桌面牌型（用于限制接牌类型）
var is_round_starter: bool = true
var log_messages: Array = []
var compound_immune: bool = false  # 溢出化合物免疫族炸

var clan_bomb_chain_active: bool = false
var clan_bomb_owner: int = -1

class PlayerInfo:
	var player_name: String = ""
	var hand: Array = []
	var is_ai: bool = false
	var has_passed: bool = false
	var clan_bomb_cooling: bool = false

	func _init(p_name: String, ai: bool = false):
		player_name = p_name
		is_ai = ai

	func get_hand_count() -> int:
		return hand.size()

	func add_card(card) -> void:
		if card != null:
			hand.append(card)

	func remove_cards(cards: Array) -> void:
		for card in cards:
			var idx = hand.find(card)
			if idx >= 0:
				hand.remove_at(idx)

	func sort_hand_by_atomic_number() -> void:
		hand.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)

	func get_hand_display() -> String:
		if hand.is_empty():
			return "[空]"
		var names: Array = []
		for card in hand:
			names.append(card.symbol)
		return ", ".join(names)


func init_game(player_count: int = 4, ai_count: int = 3) -> void:
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return
	if ai_count >= player_count:
		return

	phase = 0
	players.clear()
	table_cards.clear()
	table_player_index = -1
	table_pattern = -1
	winner_index = -1
	current_player_index = 0
	is_round_starter = true
	compound_immune = false
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	log_messages.clear()

	database = CardDatabaseScript.new()
	database.generate_deck()
	database.shuffle()

	var human_count = player_count - ai_count
	for i in range(player_count):
		var p_name = "玩家 %d" % (i + 1) if i < human_count else "AI %d" % (i + 1 - human_count)
		players.append(PlayerInfo.new(p_name, i >= human_count))

	for player in players:
		var cards = database.draw_cards(INITIAL_HAND_SIZE)
		for card in cards:
			player.add_card(card)
		player.sort_hand_by_atomic_number()

	phase = 1
	log_messages.append("===== 游戏开始 =====")
	log_messages.append("当前回合: %s (自由出牌)" % players[current_player_index].player_name)


func get_current_player() -> PlayerInfo:
	if players.is_empty():
		return null
	return players[current_player_index]


func get_current_player_index() -> int:
	return current_player_index


func play_cards(player_index: int, cards: Array) -> int:
	if player_index < 0 or player_index >= players.size() or cards.is_empty():
		return -1

	var player = players[player_index]
	var pattern = UtilsScript.detect_pattern(cards)
	if pattern == -1:
		return -1

	# === 族炸判定 ===
	if pattern == UtilsScript.CardPattern.CLAN_BOMB:
		if not clan_bomb_chain_active and player.clan_bomb_cooling:
			return -3
		if clan_bomb_chain_active:
			if table_cards.size() > 0:
				var cmp = UtilsScript.compare_cards(cards, table_cards)
				if cmp <= 0:
					return -2
	else:
		# 非族炸：检查是否可以接当前桌面
		if clan_bomb_chain_active:
			return -1  # 接炸模式只能出族炸
		if not is_round_starter:
			if table_pattern == UtilsScript.CardPattern.ELEMENT and pattern != UtilsScript.CardPattern.ELEMENT:
				return -4  # 单质后只能接单质或族炸
			if table_pattern == UtilsScript.CardPattern.COMPOUND and pattern != UtilsScript.CardPattern.COMPOUND:
				# 但如果 compound_immune，不允许任何接牌
				if compound_immune:
					return -4  # 免疫化合物无法被接
				return -4  # 化合物后只能接化合物或族炸
			if table_cards.size() > 0:
				var cmp = UtilsScript.compare_cards(cards, table_cards)
				if cmp <= 0:
					return -2

	# 从手牌移除
	player.remove_cards(cards)
	table_cards = cards.duplicate()
	table_pattern = pattern
	table_player_index = player_index
	compound_immune = false  # 默认不免疫，下面特殊设置

	# 构建日志
	var pname = UtilsScript.get_pattern_name(pattern)
	var elem_name = UtilsScript.get_element_display(cards)
	var card_str = _cards_to_string(cards)
	var log_msg = "%s 打出了 %s (%s" % [player.player_name, card_str, pname]
	if pattern == UtilsScript.CardPattern.ELEMENT and elem_name != "":
		log_msg += " " + elem_name
	if pattern == UtilsScript.CardPattern.COMPOUND:
		var fi = UtilsScript.get_compound_formula(cards)
		if not fi.is_empty():
			log_msg += " " + fi.get("formula", "??")
	log_msg += ")"

	log_messages.append(log_msg)

	if pattern == UtilsScript.CardPattern.CLAN_BOMB:
		player.clan_bomb_cooling = true
		clan_bomb_chain_active = true
		clan_bomb_owner = player_index
		for i in range(players.size()):
			if i != player_index:
				players[i].has_passed = false
		is_round_starter = false
		# Bug3 修复: 族炸后检查手牌是否清空
		if player.get_hand_count() == 0:
			phase = 2
			winner_index = player_index
			log_messages.append("===== 游戏结束！获胜者: %s =====" % player.player_name)
		return 0

	if pattern == UtilsScript.CardPattern.COMPOUND:
		player.clan_bomb_cooling = false
		# 溢出检查：牌数 > 玩家数 → 免疫
		if cards.size() > players.size():
			compound_immune = true
			log_messages.append("⚠ 溢出化合物！免疫接炸")

	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	_reset_all_passes()
	is_round_starter = false

	if player.get_hand_count() == 0:
		phase = 2
		winner_index = player_index
		log_messages.append("===== 游戏结束！获胜者: %s =====" % player.player_name)
		return 0

	next_turn()
	return 0


func player_pass(player_index: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	var player = players[player_index]

	if clan_bomb_chain_active:
		player.has_passed = true
		log_messages.append("%s 不接炸" % player.player_name)
	else:
		player.has_passed = true
		var drawn = database.draw_cards(1)
		if drawn.size() > 0:
			player.add_card(drawn[0])
			player.sort_hand_by_atomic_number()
		log_messages.append("%s 跳过回合" % player.player_name)

	next_turn()


func next_turn() -> void:
	if clan_bomb_chain_active:
		_intercept_next()
		return

	var unpassed = _get_unpassed_players()
	if unpassed.size() <= 1:
		_start_new_round()
		return

	var next_idx = current_player_index
	for _i in range(players.size()):
		next_idx = (next_idx + 1) % players.size()
		var p = players[next_idx]
		if p.get_hand_count() > 0 and not p.has_passed:
			current_player_index = next_idx
			return

	_start_new_round()


func _intercept_next() -> void:
	var next_idx = clan_bomb_owner
	for _i in range(players.size()):
		next_idx = (next_idx + 1) % players.size()
		if next_idx != clan_bomb_owner and players[next_idx].get_hand_count() > 0 and not players[next_idx].has_passed:
			current_player_index = next_idx
			return

	_finish_clan_bomb_chain()


func _finish_clan_bomb_chain() -> void:
	clan_bomb_chain_active = false
	var owner_idx = clan_bomb_owner
	clan_bomb_owner = -1
	table_cards.clear()
	table_pattern = -1
	table_player_index = -1
	is_round_starter = true
	_reset_all_passes()
	current_player_index = owner_idx
	log_messages.append("无人接炸！%s 自由出牌" % players[owner_idx].player_name)


func _start_new_round() -> void:
	table_cards.clear()
	table_pattern = -1
	table_player_index = -1
	is_round_starter = true
	_reset_all_passes()
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	compound_immune = false

	for _i in range(players.size()):
		var p = players[current_player_index]
		if p.get_hand_count() > 0:
			log_messages.append("====== 新一轮！%s 自由出牌 ======" % p.player_name)
			return
		current_player_index = (current_player_index + 1) % players.size()

	var alive = _get_alive_players()
	if alive.size() == 1:
		phase = 2
		winner_index = players.find(alive[0])
		return
	for i in range(players.size()):
		if players[i].get_hand_count() > 0:
			current_player_index = i
			return


func _reset_all_passes() -> void:
	for p in players:
		p.has_passed = false


func _get_unpassed_players() -> Array:
	var result: Array = []
	for p in players:
		if p.get_hand_count() > 0 and not p.has_passed:
			result.append(p)
	return result


func _get_alive_players() -> Array:
	var alive: Array = []
	for p in players:
		if p.get_hand_count() > 0:
			alive.append(p)
	return alive


func get_all_players_info() -> String:
	var info = "===== 状态 =====\n"
	for i in range(players.size()):
		var p = players[i]
		var marker = ""
		if i == current_player_index:
			marker = " ← "
		var ai_tag = "[AI]" if p.is_ai else "[P]"
		var pass_tag = " [跳过]" if p.has_passed else ""
		var bomb_tag = " [禁炸]" if p.clan_bomb_cooling else ""
		info += "%s %s: %d 张牌%s%s%s\n" % [ai_tag, p.player_name, p.get_hand_count(), pass_tag, bomb_tag, marker]
	if table_player_index >= 0:
		var tp = players[table_player_index]
		var pat = UtilsScript.detect_pattern(table_cards)
		var pn = UtilsScript.get_pattern_name(pat)
		var el = UtilsScript.get_element_display(table_cards)
		info += "桌面: %s 打出 %s (%s" % [tp.player_name, _cards_to_string(table_cards), pn]
		if pat == UtilsScript.CardPattern.ELEMENT and el != "":
			info += " " + el
		info += ")"
		if compound_immune:
			info += " [免疫]"
		info += "\n"
	else:
		info += "桌面: 空 (自由出牌)\n"
	if clan_bomb_chain_active:
		info += "⚠ 接炸中！%s 的族炸等待被接\n" % players[clan_bomb_owner].player_name
	info += "牌库: %d 张\n" % database.get_remaining_count()
	return info


func get_available_patterns(player_idx: int) -> String:
	if player_idx < 0 or player_idx >= players.size():
		return ""
	var p = players[player_idx]
	if clan_bomb_chain_active:
		if player_idx == clan_bomb_owner:
			return "等待他人接炸..."
		return "仅可出: 更大的族炸 / 跳过"
	if is_round_starter or table_cards.is_empty():
		var s = "自由出牌: 单质+化合物"
		if not p.clan_bomb_cooling:
			s += "+族炸"
		s += " / 跳过"
		return s
	if p.clan_bomb_cooling:
		return "需要打出更大的牌 / 跳过"
	if table_pattern == UtilsScript.CardPattern.ELEMENT:
		return "桌面是单质，只能出更大的单质/族炸 / 跳过"
	if table_pattern == UtilsScript.CardPattern.COMPOUND:
		if compound_immune:
			return "桌面化合物免疫，只能出族炸/跳过"
		return "桌面是化合物，只能出更大的化合物/族炸 / 跳过"
	return "需要打出更大的牌 / 跳过"


func flush_logs() -> Array:
	var logs = log_messages.duplicate()
	log_messages.clear()
	return logs


func _cards_to_string(cards: Array) -> String:
	if cards.is_empty():
		return "[]"
	var syms: Array = []
	for c in cards:
		syms.append(c.symbol)
	return "[%s]" % ", ".join(syms)


func is_game_over() -> bool:
	return phase == 2


func get_winner() -> PlayerInfo:
	if winner_index < 0 or winner_index >= players.size():
		return null
	return players[winner_index]