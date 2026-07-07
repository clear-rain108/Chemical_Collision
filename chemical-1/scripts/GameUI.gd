# ============================================================
# GameUI.gd - 游戏主界面控制脚本
# ============================================================

extends Control

const GameManagerScript = preload("res://scripts/GameManager.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

var game_manager: RefCounted = null
var selected_indices: Array = []
var log_lines: Array = []
const MAX_LOG_LINES = 6
var hint_timer: float = 0.0
var hint_pending: String = ""

var hand_container: Control = null
var info_label: Label = null
var table_label: Label = null
var log_label: Label = null
var hint_label: Label = null
var action_panel: Control = null
var play_btn: Button = null
var pass_btn: Button = null

var hand_buttons: Array = []


func _ready() -> void:
	_setup_ui_references()
	_init_game()


func _process(delta: float) -> void:
	if hint_timer > 0:
		hint_timer -= delta
		if hint_timer <= 0:
			if hint_label:
				hint_label.text = ""
			hint_pending = ""


func _setup_ui_references() -> void:
	hand_container = get_node_or_null("HandContainer")
	info_label = get_node_or_null("InfoLabel")
	table_label = get_node_or_null("TableLabel")
	log_label = get_node_or_null("LogLabel")
	hint_label = get_node_or_null("HintLabel")
	action_panel = get_node_or_null("ActionPanel")

	if action_panel:
		play_btn = action_panel.get_node_or_null("PlayButton")
		pass_btn = action_panel.get_node_or_null("PassButton")

		if play_btn:
			play_btn.pressed.connect(_on_play_pressed)
		if pass_btn:
			pass_btn.pressed.connect(_on_pass_pressed)


func _init_game() -> void:
	game_manager = GameManagerScript.new()
	game_manager.init_game(4, 3)
	selected_indices.clear()
	_refresh_ui()


func _refresh_ui() -> void:
	if game_manager == null or game_manager.is_game_over():
		_show_game_over()
		return

	_update_info_label()
	_update_table_label()
	_update_log_label()
	_update_hint_label()
	_update_hand_buttons()
	_update_action_buttons()


func _update_info_label() -> void:
	if info_label and game_manager:
		info_label.text = game_manager.get_all_players_info()


func _update_table_label() -> void:
	if not table_label or not game_manager:
		return
	if game_manager.table_player_index >= 0:
		var p = game_manager.players[game_manager.table_player_index]
		var cards = game_manager.table_cards
		var pattern = UtilsScript.detect_pattern(cards)
		var pname = UtilsScript.get_pattern_name(pattern)
		var element_name = UtilsScript.get_element_display(cards)
		var syms: Array = []
		for c in cards:
			syms.append(c.symbol)
		var txt = "桌面: %s 打出 %s (%s" % [p.player_name, ", ".join(syms), pname]
		if pattern == UtilsScript.CardPattern.ELEMENT and element_name != "":
			txt += " " + element_name
		if pattern == UtilsScript.CardPattern.COMPOUND:
			var fi = UtilsScript.get_compound_formula(cards)
			if not fi.is_empty():
				txt += " " + fi.get("formula", "??")
		txt += ")"
		if game_manager.clan_bomb_chain_active:
			txt += " ⚠接炸中"
		table_label.text = txt
	else:
		table_label.text = "桌面: 空"


func _update_log_label() -> void:
	if not log_label or not game_manager:
		return
	var new_logs = game_manager.flush_logs()
	if new_logs.is_empty():
		return
	for msg in new_logs:
		log_lines.push_back(msg)
		while log_lines.size() > MAX_LOG_LINES:
			log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _update_hint_label() -> void:
	if not hint_label or not game_manager:
		return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return
	var hint = game_manager.get_available_patterns(game_manager.get_current_player_index())
	_show_hint(hint)


func _show_hint(text: String) -> void:
	if hint_label:
		hint_label.text = text
	hint_timer = 3.0
	hint_pending = text


func _update_hand_buttons() -> void:
	if not hand_container or not game_manager:
		return

	for child in hand_container.get_children():
		child.queue_free()
	hand_buttons.clear()

	var current_player = game_manager.get_current_player()
	if current_player == null:
		return

	if current_player.is_ai:
		var wait_label = Label.new()
		wait_label.text = "等待 %s 行动中..." % current_player.player_name
		wait_label.add_theme_font_size_override("font_size", 28)
		hand_container.add_child(wait_label)

		var timer = get_tree().create_timer(1.5)
		timer.timeout.connect(_ai_auto_play)
	else:
		_clear_selection()
		current_player.sort_hand_by_atomic_number()

		for i in range(current_player.hand.size()):
			var card = current_player.hand[i]
			var btn = Button.new()
			btn.text = card.get_display_name()
			btn.tooltip_text = card.get_full_info()
			btn.custom_minimum_size = Vector2(140, 55)
			btn.add_theme_font_size_override("font_size", 16)

			match card.element_type:
				"金属": btn.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
				"非金属": btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
				"准金属": btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.3))
				"稀有气体": btn.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))

			var idx = i
			btn.pressed.connect(_on_card_clicked.bind(idx))
			hand_container.add_child(btn)
			hand_buttons.append(btn)


func _update_action_buttons() -> void:
	var can_act = false
	if game_manager and not game_manager.is_game_over():
		var cp = game_manager.get_current_player()
		if cp and not cp.is_ai:
			can_act = true

	if play_btn:
		play_btn.disabled = not can_act or selected_indices.is_empty()
	if pass_btn:
		pass_btn.disabled = not can_act


func _on_card_clicked(index: int) -> void:
	var cp = game_manager.get_current_player() if game_manager else null
	if cp == null:
		return

	if index in selected_indices:
		selected_indices.erase(index)
	else:
		selected_indices.append(index)

	for i in range(hand_buttons.size()):
		var btn = hand_buttons[i]
		if i in selected_indices:
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
			btn.text = "✓ " + cp.hand[i].get_display_name()
		else:
			var card = cp.hand[i]
			match card.element_type:
				"金属": btn.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
				"非金属": btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
				"准金属": btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.3))
				"稀有气体": btn.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
			btn.text = card.get_display_name()

	_update_action_buttons()


func _on_play_pressed() -> void:
	if selected_indices.is_empty() or not game_manager:
		return

	var current_player = game_manager.get_current_player()
	if current_player == null or current_player.is_ai:
		return

	var selected_cards: Array = []
	for idx in selected_indices:
		selected_cards.append(current_player.hand[idx])

	var pattern = UtilsScript.detect_pattern(selected_cards)
	if pattern == -1:
		_show_hint("非法出牌！")
		return

	var result = game_manager.play_cards(game_manager.current_player_index, selected_cards)
	if result == -1:
		_show_hint("非法出牌！接炸模式只能出族炸")
		return
	if result == -2:
		_show_hint("牌不够大！需要打出比桌面更大的牌")
		return
	if result == -3:
		_show_hint("不能出族炸！需先打出化合物以解锁")
		return

	_clear_selection()
	_refresh_ui()


func _on_pass_pressed() -> void:
	if game_manager == null:
		return
	game_manager.player_pass(game_manager.current_player_index)
	_clear_selection()
	_refresh_ui()


func _ai_auto_play() -> void:
	if game_manager == null or game_manager.is_game_over():
		return

	var current_player = game_manager.get_current_player()
	if current_player == null or not current_player.is_ai:
		return

	if current_player.hand.is_empty():
		return

	# 接炸模式：只能出族炸
	if game_manager.clan_bomb_chain_active:
		if current_player.clan_bomb_cooling:
			# 被冷却，不能出族炸，跳过
			game_manager.player_pass(game_manager.current_player_index)
		else:
			var by_group = _group_by_group(current_player.hand)
			var bombs: Array = []
			for grp in by_group:
				if by_group[grp].size() >= 2:
					bombs.append(by_group[grp].duplicate())
			if bombs.is_empty():
				game_manager.player_pass(game_manager.current_player_index)
			else:
				# 尝试每个族炸候选
				var played = false
				for bomb in bombs:
					if game_manager.play_cards(game_manager.current_player_index, bomb) == 0:
						played = true
						break
				if not played:
					game_manager.player_pass(game_manager.current_player_index)
		_refresh_ui()
		return

	# 正常模式
	var candidates = _ai_find_candidates(current_player)

	if candidates.is_empty():
		game_manager.player_pass(game_manager.current_player_index)
		_refresh_ui()
		return

	for candidate in candidates:
		var result = game_manager.play_cards(game_manager.current_player_index, candidate)
		if result == 0:
			_refresh_ui()
			return

	game_manager.player_pass(game_manager.current_player_index)
	_refresh_ui()


func _ai_find_candidates(player) -> Array:
	var result: Array = []

	if not player.clan_bomb_cooling:
		var by_group = _group_by_group(player.hand)
		for grp in by_group:
			if by_group[grp].size() >= 2:
				result.append(by_group[grp].duplicate())

	for i in range(player.hand.size()):
		for j in range(i + 1, player.hand.size()):
			var pair = [player.hand[i], player.hand[j]]
			var fi = UtilsScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				var r = fi.get("ratio", {})
				var pos_sym = r.get("pos_symbol", "")
				var neg_sym = r.get("neg_symbol", "")
				var rp = r.get("ratio_pos", 1)
				var rn = r.get("ratio_neg", 1)
				if _try_collect_compound_candidate(player, pos_sym, neg_sym, rp, rn, result):
					continue
				result.append(pair)

	for i in range(player.hand.size()):
		var card = player.hand[i]
		if card.symbol in UtilsScript.DIATOMIC_SYMBOLS:
			for j in range(player.hand.size()):
				if i != j and player.hand[j].symbol == card.symbol:
					result.append([player.hand[i], player.hand[j]])
					break

	for card in player.hand:
		result.append([card])

	return result


func _try_collect_compound_candidate(player, pos_sym: String, neg_sym: String, rp: int, rn: int, result: Array) -> bool:
	var pos_cards: Array = []
	var neg_cards: Array = []
	for card in player.hand:
		if card.symbol == pos_sym and pos_cards.size() < rp:
			pos_cards.append(card)
		elif card.symbol == neg_sym and neg_cards.size() < rn:
			neg_cards.append(card)
	if pos_cards.size() == rp and neg_cards.size() == rn:
		var compound: Array = []
		compound.append_array(pos_cards)
		compound.append_array(neg_cards)
		result.append(compound)
		return true
	return false


func _group_by_group(hand: Array) -> Dictionary:
	var result = {}
	for card in hand:
		if not result.has(card.group):
			result[card.group] = []
		result[card.group].append(card)
	return result


func _clear_selection() -> void:
	selected_indices.clear()
	_update_action_buttons()


func _show_game_over() -> void:
	if info_label and game_manager:
		var winner = game_manager.get_winner()
		if winner:
			info_label.text = "===== 游戏结束 =====\n获胜者: %s\n%s" % [winner.player_name, winner.get_hand_display()]
		else:
			info_label.text = "===== 游戏结束 ====="

	if hand_container:
		for child in hand_container.get_children():
			child.queue_free()
		hand_buttons.clear()

	if action_panel:
		action_panel.visible = false

	_update_log_label()