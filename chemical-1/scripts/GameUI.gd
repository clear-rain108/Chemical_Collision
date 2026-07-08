# ============================================================
# GameUI.gd - 游戏主界面控制脚本
# 多元素化合物 + 精确牌张收集 + 电荷平衡验证
# Updated: 2026-07-08 16:20
# ============================================================

extends Control

const GameManagerScript = preload("res://scripts/GameManager.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

var game_manager: RefCounted = null

# 页面
var start_page: Control = null
var game_page: Control = null
var end_page: Control = null
var help_page: Control = null
var start_button: Button = null
var end_label: Label = null
var end_button: Button = null
var help_back_btn: Button = null
var help_btn: Button = null
var player_spin: SpinBox = null
var ai_spin: SpinBox = null

# UI
var hand_container: Control = null
var info_label: Label = null
var table_label: Label = null
var log_label: Label = null
var card_info_label: Label = null
var action_panel: Control = null
var hint_button: Button = null
var quit_button: Button = null

# 状态
var selected_indices: Array = []
var step_mode: int = 0
var compound_selections: Array = []
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
	help_page = get_node_or_null("HelpPage")

	if start_page:
		start_button = start_page.get_node_or_null("StartButton")
		player_spin = start_page.get_node_or_null("PlayerCountSpin")
		ai_spin = start_page.get_node_or_null("AiCountSpin")
		if start_button:
			start_button.pressed.connect(_on_start_game)

	if end_page:
		end_label = end_page.get_node_or_null("EndLabel")
		end_button = end_page.get_node_or_null("EndButton")
		if end_button:
			end_button.pressed.connect(_show_start_page)

	if help_page:
		help_back_btn = help_page.get_node_or_null("HelpBackBtn")
		if help_back_btn:
			help_back_btn.pressed.connect(_on_help_back)

	if game_page:
		hand_container = game_page.get_node_or_null("HandContainer")
		info_label = game_page.get_node_or_null("InfoLabel")
		table_label = game_page.get_node_or_null("TableLabel")
		log_label = game_page.get_node_or_null("LogLabel")
		card_info_label = game_page.get_node_or_null("CardInfoLabel")
		action_panel = game_page.get_node_or_null("ActionPanel")
		hint_button = game_page.get_node_or_null("HintButton")
		quit_button = game_page.get_node_or_null("QuitButton")
		help_btn = game_page.get_node_or_null("HelpBtn")
		if hint_button:
			hint_button.toggled.connect(_on_hint_toggled)
		if quit_button:
			quit_button.pressed.connect(_on_quit_game)
		if help_btn:
			help_btn.pressed.connect(_on_show_help)


func _show_start_page() -> void:
	if start_page: start_page.visible = true
	if game_page: game_page.visible = false
	if end_page: end_page.visible = false
	if help_page: help_page.visible = false


func _on_show_help() -> void:
	if help_page: help_page.visible = true
	if game_page: game_page.visible = false


func _on_help_back() -> void:
	if help_page: help_page.visible = false
	if game_page: game_page.visible = true


func _on_start_game() -> void:
	var total = 4
	var ai = 3
	if player_spin and ai_spin:
		total = clampi(int(player_spin.value), GameManagerScript.MIN_PLAYERS, GameManagerScript.MAX_PLAYERS)
		ai = clampi(int(ai_spin.value), 1, total - 1)
	if ai >= total:
		ai = max(1, total - 1)
	start_page.visible = false
	game_page.visible = true
	end_page.visible = false
	if help_page: help_page.visible = false
	_init_game(total, ai)


func _on_quit_game() -> void:
	if game_manager: game_manager.phase = 2
	_show_end_page("游戏已退出")


func _init_game(total: int = 4, ai: int = 3) -> void:
	game_manager = GameManagerScript.new()
	var ok = game_manager.init_game(total, ai)
	if not ok:
		push_error("init_game failed with total=%d ai=%d, retrying defaults" % [total, ai])
		ok = game_manager.init_game(4, 3)
		if not ok:
			push_error("CRITICAL: init_game also failed with defaults!")
			_show_end_page("初始化失败")
			return
	_step_reset()
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
	_update_card_info_label()


func _update_info_label() -> void:
	if info_label and game_manager:
		info_label.text = _format_player_status()


func _format_player_status() -> String:
	if game_manager == null or game_manager.players.is_empty():
		return "等待游戏初始化..."
	var parts: Array = []
	for i in range(game_manager.players.size()):
		var p = game_manager.players[i]
		var is_current = (i == game_manager.current_player_index)
		var ai_tag = "(AI)" if p.is_ai else ""
		var cooling = "❄" if p.clan_bomb_cooling else ""
		var pass_tag = "⏸" if p.has_passed else ""
		var highlight = " ◄" if is_current else ""
		var label = "%s %s%s%s%s" % [p.player_name, ai_tag, cooling, pass_tag, highlight]
		parts.append(label)

	if parts.is_empty():
		return "等待游戏初始化..."
	var result = "● %s" % parts[0]
	for j in range(1, parts.size()):
		result += " → ● %s" % parts[j]
	return result


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
		while log_lines.size() > MAX_LOG_LINES:
			log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _update_card_info_label() -> void:
	if not card_info_label or not game_manager: return
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai:
		card_info_label.text = ""
		return
	var hint = game_manager.get_available_patterns(game_manager.current_player_index())
	card_info_label.text = "提示: " + hint


func _update_action_panel() -> void:
	if not action_panel or not game_manager: return
	for child in action_panel.get_children():
		child.queue_free()
	var cp = game_manager.get_current_player()
	if cp == null or cp.is_ai or game_manager.is_game_over(): return

	if step_mode == 0:
		action_panel.add_child(_mkb("出牌(选牌型)", _on_step_next, selected_indices.is_empty()))
		action_panel.add_child(_mkb("跳过", _on_pass, false))
	elif step_mode == 1:
		action_panel.add_child(_mkb("作为单质打出", _on_element, false))
		action_panel.add_child(_mkb("合成化合物", _on_choose_compound, false))
		action_panel.add_child(_mkb("作为族炸打出", _on_clan_bomb, false))
		action_panel.add_child(_mkb("返回", _on_back, false))
	elif step_mode == 2:
		_update_valence_buttons()


func _mkb(text: String, cb: Callable, dis: bool) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 45)
	b.add_theme_font_size_override("font_size", 16)
	b.disabled = dis
	b.pressed.connect(cb)
	return b


func _on_hint_toggled(_pressed: bool) -> void:
	_update_card_info_label()


# ==== 元素着色规则 ====
func _get_card_color(card) -> Color:
	var sym = card.symbol
	if sym == "H": return Color(0.4, 0.7, 1.0)
	if sym == "O": return Color(0.0, 0.3, 1.0)
	if sym == "N": return Color(0.4, 0.2, 0.8)
	if sym in ["C", "B", "Si", "S"]: return Color(1.0, 0.9, 0.1)
	if sym == "P": return Color(1.0, 0.85, 0.85)
	if card.group in ["VIIA"]: return Color(0.0, 0.7, 0.2)
	match card.element_type:
		"金属": return Color(0.5, 0.5, 0.5)
		"非金属": return Color(0.0, 0.7, 0.2)
		"准金属": return Color(0.0, 0.7, 0.2)
		"稀有气体": return Color(0.95, 0.95, 0.95)
	return Color(0.8, 0.8, 0.8)


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
			var col = _get_card_color(card)
			btn.add_theme_color_override("font_color", col)
			if i in selected_indices:
				btn.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
				btn.text = "✓ " + card.get_display_name()
			btn.pressed.connect(_on_card_clicked.bind(i))
			hand_container.add_child(btn)
			hand_buttons.append(btn)


func _update_valence_buttons() -> void:
	if not action_panel or not game_manager: return
	for child in action_panel.get_children():
		child.queue_free()
	var cp = game_manager.get_current_player()

	var elem_map: Dictionary = {}
	for _idx in selected_indices:
		var card = cp.hand[_idx]
		if not elem_map.has(card.symbol):
			elem_map[card.symbol] = card

	if elem_map.size() < 2:
		action_panel.add_child(_mkb("至少选两种元素 (返回)", _on_back, false))
		return

	var all_assigned = true
	for sym in elem_map:
		var card = elem_map[sym]
		var already = null
		for sel in compound_selections:
			if sel.symbol == sym:
				already = sel
				break
		if already == null:
			all_assigned = false
		for v in card.common_valence:
			if already != null and already.valence == v:
				break
			action_panel.add_child(_mkb("%s (%+d)" % [sym, v], _on_select_valence.bind(sym, v), false))

	if not all_assigned:
		action_panel.add_child(_mkb("返回", _on_back, false))
	else:
		var info = ""
		for sel in compound_selections:
			info += "%s%+d " % [sel.symbol, sel.valence]
		var lbl = Label.new()
		lbl.text = info
		action_panel.add_child(lbl)
		action_panel.add_child(_mkb("确认打出", _on_confirm_compound, false))
		action_panel.add_child(_mkb("重选化合价", _on_reset_valence, false))
		action_panel.add_child(_mkb("返回", _on_back, false))


func _on_card_clicked(index: int) -> void:
	if step_mode != 0: return
	if index in selected_indices: selected_indices.erase(index)
	else: selected_indices.append(index)
	_update_hand_buttons()
	_update_action_panel()


func _on_step_next() -> void:
	step_mode = 1
	_update_action_panel()


func _on_element() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if UtilsScript.detect_pattern(cards) != UtilsScript.CardPattern.ELEMENT:
		_show_info("不是有效单质！")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.current_player_index, cards)
	_handle_result(result)


func _on_clan_bomb() -> void:
	var cp = game_manager.get_current_player()
	var cards: Array = []
	for _idx in selected_indices: cards.append(cp.hand[_idx])
	if UtilsScript.detect_pattern(cards) != UtilsScript.CardPattern.CLAN_BOMB:
		_show_info("不是有效族炸！")
		_on_back()
		return
	var result = game_manager.play_cards(game_manager.current_player_index, cards)
	_handle_result(result)


func _on_choose_compound() -> void:
	var cp = game_manager.get_current_player()
	var symbols: Array = []
	for _idx in selected_indices:
		var s = cp.hand[_idx].symbol
		if s not in symbols: symbols.append(s)
	if symbols.size() < 2:
		_show_info("化合物至少需要两种不同元素！")
		_on_back()
		return
	step_mode = 2
	compound_selections.clear()
	_update_action_panel()


func _on_select_valence(symbol: String, valence: int) -> void:
	for sel in compound_selections:
		if sel.symbol == symbol: return
	compound_selections.append({"symbol": symbol, "valence": valence})
	_update_action_panel()


func _on_confirm_compound() -> void:
	var cp = game_manager.get_current_player()

	var custom_valences: Dictionary = {}
	for sel in compound_selections:
		custom_valences[sel.symbol] = sel.valence

	var has_pos = false
	var has_neg = false
	for sel in compound_selections:
		if sel.valence > 0: has_pos = true
		elif sel.valence < 0: has_neg = true
	if not has_pos or not has_neg:
		_show_info("需要正价和负价元素！")
		return

	var available: Dictionary = {}
	for _idx in selected_indices:
		var card = cp.hand[_idx]
		available[card.symbol] = available.get(card.symbol, 0) + 1

	var valence_list: Array = []
	for sel in compound_selections:
		valence_list.append({
			"symbol": sel.symbol,
			"v": abs(sel.valence),
			"sign": -1 if sel.valence < 0 else 1,
			"avail": available.get(sel.symbol, 0)
		})

	if valence_list.size() == 2:
		var a = valence_list[0]
		var b = valence_list[1]
		if a.sign * b.sign > 0:
			_show_info("需要一正一负两种价态！")
			return
		var g = _gcd(a.v, b.v)
		var na = b.v / g
		var nb = a.v / g
		if a.avail < na or b.avail < nb:
			_show_info("手牌不足！需 %s×%d + %s×%d" % [a.symbol, na, b.symbol, nb])
			return
		var ccards: Array = []
		for _idx in selected_indices:
			var card = cp.hand[_idx]
			if card.symbol == a.symbol:
				var already = 0
				for cc in ccards:
					if cc.symbol == a.symbol: already += 1
				if already < na: ccards.append(card)
			elif card.symbol == b.symbol:
				var already = 0
				for cc in ccards:
					if cc.symbol == b.symbol: already += 1
				if already < nb: ccards.append(card)
		if ccards.size() != na + nb:
			_show_info("收集卡牌出错！")
			return
		var result = game_manager.play_cards(game_manager.current_player_index, ccards, custom_valences)
		_handle_result(result)
		return

	var total_charge = 0
	var all_one = true
	for e in valence_list:
		if e.avail != 1: all_one = false
		total_charge += e.sign * e.v
	if all_one and total_charge == 0:
		var ccards: Array = []
		for _idx in selected_indices: ccards.append(cp.hand[_idx])
		var result = game_manager.play_cards(game_manager.current_player_index, ccards, custom_valences)
		_handle_result(result)
		return

	_show_info("仅支持 2 元素化合物（多元素需每种恰好 1 张且电荷平衡）")


func _on_reset_valence() -> void:
	compound_selections.clear()
	_update_action_panel()


func _on_back() -> void:
	step_mode = 0
	compound_selections.clear()
	_update_action_panel()


func _on_pass() -> void:
	game_manager.player_pass(game_manager.current_player_index)
	_step_reset()
	_refresh_ui()


func _handle_result(result: int) -> void:
	if result == 0:
		_step_reset()
		_refresh_ui()
		return
	var msg = "非法出牌！"
	if result == -2: msg = "牌不够大！"
	elif result == -3: msg = "不能出族炸！"
	elif result == -4: msg = "牌型不匹配！"
	_show_info(msg)
	_on_back()


func _step_reset() -> void:
	selected_indices.clear()
	step_mode = 0
	compound_selections.clear()


func _show_info(text: String) -> void:
	if info_label and game_manager:
		info_label.text = _format_player_status() + "\n" + text


func _show_end_page(custom_text: String) -> void:
	start_page.visible = false
	game_page.visible = false
	end_page.visible = true
	if end_label:
		if game_manager:
			var w = game_manager.get_winner()
			if w:
				end_label.text = "获胜者: %s" % w.player_name
				return
		end_label.text = custom_text if custom_text != "" else "游戏结束"


# ==== AI ====
func _ai_auto_play() -> void:
	if game_manager == null or game_manager.is_game_over(): return
	var cp = game_manager.get_current_player()
	if cp == null or not cp.is_ai or cp.hand.is_empty(): return
	if game_manager.clan_bomb_chain_active:
		if cp.clan_bomb_cooling: game_manager.player_pass(game_manager.current_player_index)
		else: _ai_try_clan_bomb(cp)
		_refresh_ui()
		return
	_ai_try_play(cp)
	_refresh_ui()


func _ai_try_clan_bomb(p):
	var bg = _group_by_group(p.hand)
	for g in bg:
		if bg[g].size() >= 2:
			if game_manager.play_cards(game_manager.current_player_index, bg[g].duplicate()) == 0: return
	game_manager.player_pass(game_manager.current_player_index)


func _ai_try_play(p):
	if not p.clan_bomb_cooling:
		var bg = _group_by_group(p.hand)
		for g in bg:
			if bg[g].size() >= 2:
				if game_manager.play_cards(game_manager.current_player_index, bg[g].duplicate()) == 0: return

	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			var fi = UtilsScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				var cv: Dictionary = {}
				var counts = fi.get("actual_counts", {})
				for sym in counts:
					var sample = p.hand[i] if p.hand[i].symbol == sym else p.hand[j]
					var v = 0
					for val in sample.common_valence:
						if val > 0: v = val; break
					if v == 0: v = -abs(sample.common_valence[0])
					cv[sym] = v
				if game_manager.play_cards(game_manager.current_player_index, pair, cv) == 0: return

	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in UtilsScript.DIATOMIC_SYMBOLS:
			for j in range(p.hand.size()):
				if i != j and p.hand[j].symbol == c.symbol:
					var dp = [p.hand[i], p.hand[j]]
					if game_manager.play_cards(game_manager.current_player_index, dp) == 0: return
					break

	for c in p.hand:
		if game_manager.play_cards(game_manager.current_player_index, [c]) == 0: return
	game_manager.player_pass(game_manager.current_player_index)


func _group_by_group(hand: Array) -> Dictionary:
	var r = {}
	for c in hand:
		if not r.has(c.group): r[c.group] = []
		r[c.group].append(c)
	return r


func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return abs(a)