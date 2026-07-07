# ============================================================
# GameManager.gd - 多人发牌与玩家管理
# 迭代 3+：回合轮转 + 出牌比大小 + Pass 轮次 + 日志系统
# ============================================================

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

const MIN_PLAYERS = 3
const MAX_PLAYERS = 6
const INITIAL_HAND_SIZE = 8

enum PlayerState {
	HUMAN_WAITING,
	HUMAN_ACTIVE,
	AI_WAITING,
	AI_ACTIVE,
}

enum GamePhase {
	INIT,
	PLAYING,
	GAME_OVER,
}

enum PlayResult {
	OK,
	NOT_STRONGER,
	INVALID_PATTERN,
}

class PlayerInfo:
	var player_name: String = ""
	var hand: Array = []
	var is_ai: bool = false
	var state: int = PlayerState.HUMAN_WAITING
	var has_passed: bool = false

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

	func clear_hand() -> void:
		hand.clear()

	func sort_hand_by_atomic_number() -> void:
		hand.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)

	func get_hand_display() -> String:
		if hand.is_empty():
			return "[empty]"
		var names: Array = []
		for card in hand:
			names.append(card.symbol)
		return ", ".join(names)


var database: RefCounted = null
var players: Array = []
var current_player_index: int = 0
var phase: int = GamePhase.INIT
var round_number: int = 0
var winner_index: int = -1
var table_cards: Array = []
var table_player_index: int = -1
var is_round_starter: bool = true
var log_messages: Array = []


func init_game(player_count: int = 4, ai_count: int = 3) -> void:
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		push_error("Player count must be %d~%d" % [MIN_PLAYERS, MAX_PLAYERS])
		return
	if ai_count >= player_count:
		push_error("AI count must be less than total players")
		return

	phase = GamePhase.INIT
	players.clear()
	table_cards.clear()
	table_player_index = -1
	winner_index = -1
	round_number = 0
	current_player_index = 0
	is_round_starter = true
	log_messages.clear()

	database = CardDatabaseScript.new()
	database.generate_deck()
	database.shuffle()

	var human_count = player_count - ai_count
	for i in range(player_count):
		var p_name: String
		var is_ai: bool
		if i < human_count:
			p_name = "Player %d" % (i + 1)
			is_ai = false
		else:
			p_name = "AI %d" % (i + 1 - human_count)
			is_ai = true
		var player = PlayerInfo.new(p_name, is_ai)
		players.append(player)

	for player in players:
		var cards = database.draw_cards(INITIAL_HAND_SIZE)
		for card in cards:
			player.add_card(card)
		player.sort_hand_by_atomic_number()

	phase = GamePhase.PLAYING
	round_number = 1
	log_messages.append("===== Game Started =====")
	log_messages.append("Players: %d (%d human + %d AI)" % [player_count, human_count, ai_count])
	log_messages.append("Hands: %d cards each" % INITIAL_HAND_SIZE)
	log_messages.append("Turn: %s (free play)" % players[current_player_index].player_name)


func get_current_player() -> PlayerInfo:
	if players.is_empty():
		return null
	return players[current_player_index]


func play_cards(player_index: int, cards: Array) -> int:
	if player_index < 0 or player_index >= players.size():
		return PlayResult.INVALID_PATTERN
	if cards.is_empty():
		return PlayResult.INVALID_PATTERN

	var player = players[player_index]
	var pattern = UtilsScript.detect_pattern(cards)
	if pattern == -1:
		return PlayResult.INVALID_PATTERN

	if not is_round_starter:
		var cmp = UtilsScript.compare_cards(cards, table_cards)
		if cmp <= 0:
			return PlayResult.NOT_STRONGER
	else:
		is_round_starter = false

	_reset_all_passes()

	# 构建日志
	var pname = UtilsScript.get_pattern_name(pattern)
	var elem_name = UtilsScript.get_element_display(cards)
	var card_str = _cards_to_string(cards)
	var log_msg = "%s played %s (%s)" % [player.player_name, card_str, pname]

	if pattern == UtilsScript.CardPattern.ELEMENT and elem_name != "":
		log_msg += " = " + elem_name

	if pattern == UtilsScript.CardPattern.COMPOUND:
		var formula_info = UtilsScript.get_compound_formula(cards)
		if not formula_info.is_empty():
			var f = formula_info.get("formula", "??")
			log_msg += " = " + f
			if not formula_info.get("ratio_ok", false):
				var r = formula_info.get("ratio", {})
				log_msg += " (ratio mismatch! need %d:%d)" % [r.get("ratio_pos", 1), r.get("ratio_neg", 1)]
				log_messages.append(log_msg)
				return PlayResult.INVALID_PATTERN

	if pattern == UtilsScript.CardPattern.CLAN_BOMB:
		log_msg += " --CLAN BOMB! %s group! Steal turn!" % cards[0].group

	# 从手牌移除
	player.remove_cards(cards)
	table_cards = cards.duplicate()
	table_player_index = player_index

	log_messages.append(log_msg)

	if pattern == UtilsScript.CardPattern.CLAN_BOMB:
		if player.get_hand_count() == 0:
			phase = GamePhase.GAME_OVER
			winner_index = player_index
			log_messages.append("===== GAME OVER! Winner: %s =====" % player.player_name)
		return PlayResult.OK

	if player.get_hand_count() == 0:
		phase = GamePhase.GAME_OVER
		winner_index = player_index
		log_messages.append("===== GAME OVER! Winner: %s =====" % player.player_name)
		return PlayResult.OK

	next_turn()
	return PlayResult.OK


func player_pass(player_index: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	var player = players[player_index]
	player.has_passed = true
	var drawn = database.draw_cards(1)
	if drawn.size() > 0:
		player.add_card(drawn[0])
		player.sort_hand_by_atomic_number()
	var drawn_str = drawn[0].symbol if drawn.size() > 0 else "empty"
	log_messages.append("%s passed, drew: %s" % [player.player_name, drawn_str])
	next_turn()


func next_turn() -> void:
	var unpassed = _get_unpassed_players()
	if unpassed.size() <= 1:
		_start_new_round(unpassed)
		return

	var next_idx = current_player_index
	for _i in range(players.size()):
		next_idx = (next_idx + 1) % players.size()
		var p = players[next_idx]
		if p.get_hand_count() > 0 and not p.has_passed:
			current_player_index = next_idx
			round_number += 1
			log_messages.append("Turn: %s (round %d)" % [p.player_name, round_number])
			return

	_start_new_round([])


func _start_new_round(unpassed: Array) -> void:
	table_cards.clear()
	table_player_index = -1
	is_round_starter = true
	_reset_all_passes()

	var found = false
	for _i in range(players.size()):
		var p = players[current_player_index]
		if p.get_hand_count() > 0:
			found = true
			break
		current_player_index = (current_player_index + 1) % players.size()

	if not found:
		var alive = _get_alive_players()
		if alive.size() == 1:
			phase = GamePhase.GAME_OVER
			winner_index = players.find(alive[0])
			return
		for i in range(players.size()):
			if players[i].get_hand_count() > 0:
				current_player_index = i
				found = true
				break

	round_number += 1
	log_messages.append("====== New Round! %s free play ======" % players[current_player_index].player_name)


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
	var info = "===== Status =====\n"
	for i in range(players.size()):
		var p = players[i]
		var marker = ""
		if i == current_player_index:
			marker = " <- "
		var ai_tag = "[AI]" if p.is_ai else "[P]"
		var pass_tag = " [Pass]" if p.has_passed else ""
		info += "%s %s: %d cards%s%s\n" % [ai_tag, p.player_name, p.get_hand_count(), pass_tag, marker]
	if table_player_index >= 0:
		var tp = players[table_player_index]
		var pat = UtilsScript.detect_pattern(table_cards)
		var pn = UtilsScript.get_pattern_name(pat)
		var el = UtilsScript.get_element_display(table_cards)
		info += "Table: %s played %s (%s" % [tp.player_name, _cards_to_string(table_cards), pn]
		if pat == UtilsScript.CardPattern.ELEMENT and el != "":
			info += " " + el
		info += ")\n"
	else:
		info += "Table: empty (free play)\n"
	info += "Deck: %d cards left\n" % database.get_remaining_count()
	return info


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
	return phase == GamePhase.GAME_OVER


func get_winner() -> PlayerInfo:
	if winner_index < 0 or winner_index >= players.size():
		return null
	return players[winner_index]