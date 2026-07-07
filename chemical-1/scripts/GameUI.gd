# ============================================================
# GameUI.gd - 游戏主界面控制脚本
# 玩家与 AI 统一出牌逻辑
# ============================================================

extends Control

const GameManagerScript = preload("res://scripts/GameManager.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

var game_manager: RefCounted = null

# 页面
var start_page: Control = null
var game_page: Control = null
var end_page: Control = null
var start_button: Button = null
var end_label: Label = null
var end_button: Button = null

# UI
var hand_container: Control = null
var info_label: Label = null
var table_label: Label = null
var log_label: Label = null
var action_panel: Control = null
var hint_button: Button = null
var quit_button: Button = null

# 状态
var selected_indices: Array = []
var hand_buttons: Array = []
var log_lines: Array = []
const MAX_LOG_LINES = 6
var ai_triggered: bool = false


func _ready() -> void:
	_setup_pages()
	_show_start_page()


func _setup_pages() -> void:
	start_page = get_node_or_null("StartPage")
	game_page = get_node_or_null("GamePage")
	end_page = get_node_or_null("EndPage")

	if start_page:
		start_button = start_page.get_node_or_null("StartButton")
		if start_button: start_button.pressed.connect(_on_start_game)

	if end_page:
		end_label = end_page.get_node_or_null("EndLabel")
		end_button = end_page.get_node_or_null("EndButton")
		if end_button: end_button.pressed.connect(_show_start_page)

	if game_page:
		hand_container = game_page.get_node_or_null("HandContainer")
		info_label = game_page.get_node_or_null("InfoLabel")
		table_label = game_page.get_node_or_null("TableLabel")
		log_label = game_page.get_node_or_null("LogLabel")
		action_panel = game_page.get_node_or_null("ActionPanel")
		hint_button = game_page.get_node_or_null("HintButton")
		quit_button = game_page.get_node_or_null("QuitButton")
		if hint_button: hint_button.toggled.connect(_on_hint_toggled)
		if quit_button: quit_button.pressed.connect(_on_quit_game)


func _show_start_page() -> void:
	if start_page: start_page.visible = true
	if game_page: game_page.visible = false
	if end_page: end_page.visible = false


func _on_start_game() -> void:
	start_page.visible = false
	game_page.visible = true
	end_page.visible = false
	_init_game()


func _on_quit_game() -> void:
	if game_manager: game_manager.phase = 2
	_show_end_page("游戏已退出")


func _init_game() -> void:
	game_manager = GameManagerScript.new()
	game_manager.init_game(4, 3)
	selected_indices.clear()
	_refresh_ui()


func _refresh_ui() -> void:
	if game_manager == null or game_manager.is_game_over():
		_show_end_page("")
		return
	_update_info_label()
	_update_table_label()
	_update_log_label()
	_update_action_panel()
	_update_hand_buttons()


func _update_info_label() -> void:
	if info_label and game_manager:
		info_label.text = game_manager.get_all_players_info()


func _update_table_label() -> void:
	if not table_label or not game_manager: return
	if game_manager.table_player_index >= 0:
		var p = game_manager.players[game_manager.table_player_index]
		var cards = game_manager.table_cards
		var pat = UtilsScript.detect_pattern(cards)
		var pn = UtilsScript.get_pattern_name(pat)
		var en = UtilsScript.get_element_display(cards)
		var syms: Array = []
		for c in cards: syms.append(c.symbol)
		var txt = "桌面: %s 打出 %s (%s" % [p.player_name, ", ".join(syms), pn]
		if pat == UtilsScript.CardPattern.ELEMENT and en != "": txt += " " + en
		if pat == UtilsScript.CardPattern.COMPOUND:
			var fi = UtilsScript.get_compound_formula(cards)
			if not fi.is_empty(): txt += " " + fi.get("formula", "??")
		txt += ")"
		if game_manager.compound_immune: txt += " [免疫]"
		if game_manager.clan_bomb_chain_active: txt += " ⚠接炸中"
		table_label.text = txt
	else:
		table_label.text = "桌面: 空"


func _update_log_label() -> void:
	if not log_label or not game_manager: return
	var new_logs = game_manager.flush_logs()
	if new_logs.is_empty(): return
	for msg in new_logs:
		log_lines.push_back(msg)
		while log_lines.size() > MAX_LOG_LINES: log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _update_action_panel() -> void:
	if not action_panel or not game_manager: return
	for child in action_panel.get_children():
		child.queue_free()

	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai or game_manager.is_game_over(): return

	# 统一出牌：选中牌 → 一键打出
	var play_btn = Button.new()
	play_btn.text = "出牌"
	play_btn.custom_minimum_size = Vector2(160, 45)
	play_btn.add_theme_font_size_override("font_size", 18)
	play_btn.disabled = selected_indices.is_empty()
	play_btn.pressed.connect(_on_play_pressed)
	action_panel.add_child(play_btn)

	var pass_btn = Button.new()
	pass_btn.text = "跳过"
	pass_btn.custom_minimum_size = Vector2(160, 45)
	pass_btn.add_theme_font_size_override("font_size", 18)
	pass_btn.pressed.connect(_on_pass_pressed)
	action_panel.add_child(pass_btn)


func _on_hint_toggled(pressed: bool) -> void:
	if pressed and game_manager:
		var hint = game_manager.get_available_patterns(game_manager.get_current_player_index())
		if info_label: info_label.text = game_manager.get_all_players_info() + "\n提示: " + hint
	else:
		_update_info_label()


func _update_hand_buttons() -> void:
	if not hand_container or not game_manager: return
	for child in hand_container.get_children():
		child.queue_free()
	hand_buttons.clear()
	ai_triggered = false

	var cp = game_manager.get_current_player()
	if cp == null: return

	if cp.is_ai:
		var wl = Label.new()
		wl.text = "等待 %s 行动中..." % cp.player_name
		wl.add_theme_font_size_override("font_size", 28)
		hand_container.add_child(wl)
		if not ai_triggered:
			ai_triggered = true
			var timer = get_tree().create_timer(1.5)
			timer.timeout.connect(_ai_auto_play)
	else:
		cp.sort_hand_by_atomic_number()
		for i in range(cp.hand.size()):
			var card = cp.hand[i]
			var btn = Button.new()
			btn.text = card.get_display_name()
			btn.tooltip_text = card.get_full_info()
			btn.custom_minimum_size = Vector2(140, 55)
			btn.add_theme_font_size_override("font_size", 16)
			match card.element_type:
				"金属": btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
				"非金属": btn.add_theme_color_override("font_color", Color(0.0, 0.7, 0.2))
				"准金属": btn.add_theme_color_override("font_color", Color(0.0, 0.7, 0.2))
				"稀有气体": btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
			if i in selected_indices:
				btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
				btn.text = "✓ " + card.get_display_name()
			var idx = i
			btn.pressed.connect(_on_card_clicked.bind(idx))
			hand_container.add_child(btn)
			hand_buttons.append(btn)


func _on_card_clicked(index: int) -> void:
	if index in selected_indices:
		selected_indices.erase(index)
	else:
		selected_indices.append(index)
	_update_hand_buttons()
	_update_action_panel()


# ==== 统一出牌入口（玩家）====
func _on_play_pressed() -> void:
	if selected_indices.is_empty() or not game_manager: return
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for idx in selected_indices:
		cards.append(cp.hand[idx])

	# 统一交由后端判定
	var result = game_manager.play_cards(game_manager.current_player_index, cards)
	if result == 0:
		selected_indices.clear()
		_refresh_ui()
		return
	# 显示错误
	var msg = ""
	if result == -1: msg = "非法牌型！仅支持: 单质、双原子分子(H₂/N₂/O₂/F₂/Cl₂)、化合物(正确比例)、族炸"
	elif result == -2: msg = "牌不够大！"
	elif result == -3: msg = "族炸冷却中，需先打出化合物"
	elif result == -4: msg = "牌型不匹配！"
	_show_info(msg)


func _on_pass_pressed() -> void:
	game_manager.player_pass(game_manager.current_player_index)
	selected_indices.clear()
	_refresh_ui()


# ==== AI 出牌（与玩家同一入口 play_cards）====
func _ai_auto_play() -> void:
	if game_manager == null or game_manager.is_game_over(): return
	var cp = game_manager.get_current_player()
	if cp == null or not cp.is_ai or cp.hand.is_empty(): return

	# 接炸模式只出族炸
	if game_manager.clan_bomb_chain_active:
		if cp.clan_bomb_cooling:
			game_manager.player_pass(game_manager.current_player_index)
		else:
			_ai_try_clan_bomb(cp)
		_refresh_ui()
		return

	# 正常模式：候选出牌
	_ai_try_play(cp)
	_refresh_ui()


func _ai_try_clan_bomb(player) -> void:
	var by_group = _group_by_group(player.hand)
	for grp in by_group:
		if by_group[grp].size() >= 2:
			if game_manager.play_cards(game_manager.current_player_index, by_group[grp].duplicate()) == 0:
				return
	game_manager.player_pass(game_manager.current_player_index)


func _ai_try_play(player) -> void:
	# 族炸
	if not player.clan_bomb_cooling:
		var by_group = _group_by_group(player.hand)
		for grp in by_group:
			if by_group[grp].size() >= 2:
				if game_manager.play_cards(game_manager.current_player_index, by_group[grp].duplicate()) == 0:
					return

	# 化合物（尝试每对不同元素）
	for i in range(player.hand.size()):
		for j in range(i + 1, player.hand.size()):
			var pair = [player.hand[i], player.hand[j]]
			var fi = UtilsScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				if game_manager.play_cards(game_manager.current_player_index, pair) == 0:
					return

	# 双原子分子
	for i in range(player.hand.size()):
		var card = player.hand[i]
		if card.symbol in UtilsScript.DIATOMIC_SYMBOLS:
			for j in range(player.hand.size()):
				if i != j and player.hand[j].symbol == card.symbol:
					if game_manager.play_cards(game_manager.current_player_index, [player.hand[i], player.hand[j]]) == 0:
						return
					break

	# 单质单张
	for card in player.hand:
		if game_manager.play_cards(game_manager.current_player_index, [card]) == 0:
			return

	# 全出不了 → 跳过
	game_manager.player_pass(game_manager.current_player_index)


func _group_by_group(hand: Array) -> Dictionary:
	var result = {}
	for card in hand:
		if not result.has(card.group): result[card.group] = []
		result[card.group].append(card)
	return result


func _show_info(text: String) -> void:
	if info_label and game_manager:
		info_label.text = game_manager.get_all_players_info() + "\n" + text


func _show_end_page(custom_text: String) -> void:
	start_page.visible = false
	game_page.visible = false
	end_page.visible = true
	if end_label:
		if game_manager:
			var w = game_manager.get_winner()
			if w:
				end_label.text = "获胜者: %s\n%s" % [w.player_name, w.get_hand_display()]
				return
		end_label.text = custom_text if custom_text != "" else "游戏结束"