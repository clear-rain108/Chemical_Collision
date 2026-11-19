# ============================================================
# scripts/ui/TableArea.gd
# 顶部状态栏（InfoLabel 玩家链 / 桌面文案）+ 桌面迷你卡槽（72×90，横向压缩居中）。
# 状态（status_bar_label / table_label / table_card_buttons / _table_sig）留在 root ——
# _refresh_ui 编排与 _update_info_label 都要读。
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 3，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 3185-3214 行 --------
# ============================================================
# 八之二、顶部状态栏（当前玩家 / 手牌数 / 上限 / 牌库 / 桌面）
# ============================================================
func _build_status_bar() -> void:
	if not _ui.game_page or _ui.status_bar_label != null:
		return
	# 深蓝灰背景条（60px，覆盖顶部）
	var bar = ColorRect.new()
	bar.color = Color(0.173, 0.243, 0.314, 1.0)   # #2C3E50
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1152, 60)
	_ui._layer(0).add_child(bar)

	# 状态栏文字
	var lbl = Label.new()
	lbl.position = Vector2(16, 8)
	lbl.size = Vector2(1240, 44)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui._layer(0).add_child(lbl)
	_ui.status_bar_label = lbl

	# 状态栏已整合信息，隐藏被遮挡/冗余的旧标签
	var title = _ui.game_page.get_node_or_null("TitleLabel")
	if title: title.visible = false
	var deck = _ui.game_page.get_node_or_null("DeckCountLabel")
	if deck: deck.visible = false
	# 下方标签的纵向坐标已直接写在 Main.tscn 中（不再运行时下移，避免与桌面牌重叠）



# -------- 搬运自 scripts/GameUI.gd 第 3216-3243 行 --------
func _update_status_bar() -> void:
	if not _ui.status_bar_label or not _ui.game_manager:
		return
	var cp = _ui.game_manager.get_current_player()
	if cp == null:
		_ui.status_bar_label.text = ""
		return
	var ai_tag = "(人机)" if cp.is_ai else ""
	var cooling = "❄" if cp.clan_bomb_cooling else ""
	var pass_tag = "⏸" if cp.has_passed else ""
	var hand_limit = _ui.game_manager.get_hand_limit()
	var db = _ui.game_manager.get_database()
	var deck_remain = db.get_remaining_count() if db else 0
	# 桌面信息
	var table_txt = "桌面: 空"
	if _ui.game_manager.get_table_player_index() >= 0:
		var tp = _ui.game_manager.get_players()[_ui.game_manager.get_table_player_index()]
		# 桌面牌型以「打出时记录的 table_pattern」为准；按牌面重新检测会把
		# 「既是族炸又能配成化合物」的牌（如 N + P）显示成另一种，与判定结果矛盾。
		var pat = _ui.game_manager.get_table_pattern()
		if pat < 0:
			pat = _ui.CardPatternsScript.detect_pattern(_ui.game_manager.get_table_cards())
		var pn = _ui.CardPatternsScript.get_pattern_name(pat)
		table_txt = "桌面: %s 打出 %s" % [tp.player_name, pn]
	_ui.status_bar_label.text = "▶ %s %s%s%s  手牌 %d/%d  ｜  牌库 %d  ｜  %s" % [
		cp.player_name, ai_tag, cooling, pass_tag,
		cp.get_hand_count(), hand_limit, deck_remain, table_txt
	]


# -------- 搬运自 scripts/GameUI.gd 第 3245-3297 行 --------
func _format_player_status() -> String:
	if _ui.game_manager == null or _ui.game_manager.get_player_count() == 0:
		return "等待游戏初始化..."
	var n: int = int(_ui.game_manager.get_player_count())
	var cp_idx = _ui.game_manager.get_current_player_index()
	# 名字链：每 PLAYER_STATUS_PER_LINE 人一行（3~4 人仍是 1 行，6~8 人才换行）
	var chain_lines: Array = []
	var row: Array = []
	for i in range(n):
		var p = _ui.game_manager.get_players()[i]
		var is_current = (i == cp_idx)
		var ai_tag = "(人机)" if p.is_ai else ""
		var cooling = "❄" if p.clan_bomb_cooling else ""
		var pass_tag = "⏸" if p.has_passed else ""
		var highlight = " ◄" if is_current else ""
		row.append("%s %s%s%s%s" % [p.player_name, ai_tag, cooling, pass_tag, highlight])
		if row.size() >= _ui.PLAYER_STATUS_PER_LINE or i == n - 1:
			chain_lines.append("● " + " → ● ".join(row))
			row = []
	if chain_lines.is_empty():
		return "等待游戏初始化..."
	var lines: Array = chain_lines
	# AI 手牌：自己的手牌数已在顶部状态栏显示，这里只列 AI 的，避免信息重复
	var counts: Array = []
	for i in range(n):
		var pl = _ui.game_manager.get_players()[i]
		if not pl.is_ai:
			continue
		counts.append("%s: %d张" % [pl.player_name, pl.get_hand_count()])
	var ci := 0
	while ci < counts.size():
		var seg: Array = counts.slice(ci, mini(ci + _ui.PLAYER_STATUS_PER_LINE, counts.size()))
		lines.append(("手牌: " if ci == 0 else "　　　") + " | ".join(seg))
		ci += _ui.PLAYER_STATUS_PER_LINE
	# 补充规则 / 方向：只在还留得下行数时追加（8 座位时这两行会被挤掉）
	var has_rules: bool = _ui.game_manager.get_organic_rules_enabled() \
		or _ui.game_manager.get_sequence_rules_enabled() \
		or _ui.game_manager.get_halogen_exchange_allowed() \
		or _ui.game_manager.get_element_limit_enabled()
	if has_rules and lines.size() < _ui.INFO_LABEL_MAX_LINES - 1:
		var rules_list: Array = []
		if _ui.game_manager.get_organic_rules_enabled(): rules_list.append("有机物胜利")
		if _ui.game_manager.get_sequence_rules_enabled(): rules_list.append("顺序牌型")
		if _ui.game_manager.get_halogen_exchange_allowed(): rules_list.append("允许卤族互化")
		if _ui.game_manager.get_element_limit_enabled():
			var extras: Array = _ui.game_manager.get_allowed_extra_elements()
			var extra_txt := "无额外元素" if extras.is_empty() else "/".join(extras)
			rules_list.append("元素限制（前20号 + %s）" % extra_txt)
		lines.append("【补充规则】" + " + ".join(rules_list))
	if lines.size() < _ui.INFO_LABEL_MAX_LINES and not _ui.game_manager.get_direction_clockwise():
		lines.append("方向: ← 逆时针")
	return "\n".join(lines)



# -------- 搬运自 scripts/GameUI.gd 第 3301-3415 行 --------
func _update_table_label() -> void:
	if not _ui.table_label or not _ui.game_manager: return

	if _ui.game_manager.get_table_player_index() >= 0:
		var p = _ui.game_manager.get_players()[_ui.game_manager.get_table_player_index()]
		var cards = _ui.game_manager.get_table_cards()
		# 同 _update_status_bar：桌面牌型一律取 table_pattern（打出时的真相）
		var pat = _ui.game_manager.get_table_pattern()
		if pat < 0:
			pat = _ui.CardPatternsScript.detect_pattern(cards)
		var pn = _ui.CardPatternsScript.get_pattern_name(pat)
		var en = _ui.CardPatternsScript.get_element_display(cards)
		var syms: Array = []
		for c in cards: syms.append(c.symbol)
		var txt = "桌面: %s 打出 %s" % [p.player_name, pn]
		if en != "": txt += " " + en
		if pat == _ui.CardPatternsScript.CardPattern.COMPOUND:
			var table_cv = _ui.game_manager.get_table_custom_valences()
			var fi = _ui.CompoundSolverScript.get_compound_formula(cards, table_cv)
			if not fi.is_empty():
				var formula = fi.get("formula", "")
				if formula != "":
					txt += " " + formula
					var comp_name = _ui.CompoundSolverScript.get_compound_name(cards, table_cv)
					if comp_name != "":
						txt += "（" + comp_name + "）"
		if _ui.game_manager.is_compound_immune(): txt += " [免疫]"
		if _ui.game_manager.is_clan_bomb_chain_active(): txt += " ⚠接炸中"
		_set_table_text(txt, pat)

		# 为桌面迷你卡牌计算每个元素的化合价
		var card_valences: Dictionary = {}
		if pat == _ui.CardPatternsScript.CardPattern.ELEMENT:
			for i in range(cards.size()):
				card_valences[i] = 0
		elif pat == _ui.CardPatternsScript.CardPattern.COMPOUND:
			var fi2 = _ui.CompoundSolverScript.get_compound_formula(cards, _ui.game_manager.get_table_custom_valences())
			if not fi2.is_empty():
				# 按化学式的标准顺序（正电性在前，负电性在后，同内按电负性递增）重排卡牌
				# 这样桌面小卡牌的物理顺序与化学式字符串一致
				var pos_list2: Array = fi2.get("pos_list", [])
				var neg_list2: Array = fi2.get("neg_list", [])
				var ordered_cards: Array = []
				for e in pos_list2:
					for _ei in range(e.count):
						for c in cards:
							if c.symbol == e.symbol and c not in ordered_cards:
								ordered_cards.append(c)
								break
				for e in neg_list2:
					for _ei in range(e.count):
						for c in cards:
							if c.symbol == e.symbol and c not in ordered_cards:
								ordered_cards.append(c)
								break
				if ordered_cards.size() == cards.size():
					cards = ordered_cards
				# 计算每个元素的化合价（按重排后的索引）
				# 混合价态（Fe₃O₄）按「每张牌一个价」显示：Fe 三张分别是 +3 / +3 / +2，
				# 而不是把平均值或其中一个价重复三遍。
				for e in pos_list2 + neg_list2:
					var plan: Array = e.get("plan", [])
					var k := 0
					for i in range(cards.size()):
						if cards[i].symbol == e.symbol:
							if bool(e.get("mixed", false)) and k < plan.size():
								card_valences[i] = int(plan[k])
							else:
								card_valences[i] = e.ox_state
							k += 1
		elif pat == _ui.CardPatternsScript.CardPattern.SEQUENCE:
			# 顺序牌按原子序数升序显示（与玩家选择顺序无关，体现连续序列）
			var sorted_cards: Array = cards.duplicate()
			sorted_cards.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)
			cards = sorted_cards
			for i in range(cards.size()):
				card_valences[i] = 0

		# 内容签名：同一批牌（uid）+ 同一牌型 → 不重播入场动画。
		# AI 每次行动都会走 _refresh_ui 整块重建小卡，不去重的话桌面会一直闪。
		var new_sig := "%d|" % pat
		for c in cards:
			new_sig += "%s%d," % [c.symbol, c.uid]
		var replay: bool = new_sig != _ui._table_sig
		_ui._table_sig = new_sig

		# 桌面牌槽位："桌面: …"文字下方的那一行，多张时自动压缩并水平居中
		var slot_left := 20.0
		var slot_w := 580.0
		var slot_y := 186.0
		if _ui.table_label:
			slot_y = _ui.table_label.position.y + _ui.table_label.size.y + 4.0
		var mini_step: float = 80.0
		if cards.size() > 1:
			mini_step = min(80.0, (slot_w - 72.0) / float(cards.size() - 1))
		var row_w: float = 72.0 + mini_step * float(cards.size() - 1)
		var start_x: float = slot_left + max(0.0, (slot_w - row_w) * 0.5)
		# 同一批牌 + 同一牌型 → 复用现有小卡：只重算槽位，不销毁 / 不重建 / 不重播动画。
		# 槽位本身必须重算：「桌面: …」文字换行后高度会变，小卡得跟着下移。
		if not replay and _reuse_mini_cards(cards.size()):
			for i in range(cards.size()):
				_ui.table_card_buttons[i].position = Vector2(start_x + i * mini_step, slot_y)
			return
		_clear_mini_cards()
		for i in range(cards.size()):
			var cv = null
			if card_valences.has(i):
				cv = card_valences[i]
			var mini_btn = _ui._build_mini_card_button(cards[i], cv)
			mini_btn.position = Vector2(start_x + i * mini_step, slot_y)
			_ui._layer(0).add_child(mini_btn)
			_ui.table_card_buttons.append(mini_btn)
			if replay:
				_ui._animate_mini_card_in(mini_btn, i)
	else:
		_clear_mini_cards()
		_ui._table_sig = ""
		_set_table_text("桌面: 空", -1)



# -------- 搬运自 scripts/GameUI.gd 第 3417-3451 行 --------
# -------- 桌面「桌面: …」文本：按牌型上色 + 换行淡入（A2） --------
# 以前无论打出什么牌型都是同一行深灰小字，玩家要读完整句才知道发生了什么；
# 牌型色让「化合物 / 族炸 / 顺序」一眼可辨（族炸还会额外带 ⚠ 文案）。
func _table_type_color(pat: int) -> Color:
	match pat:
		_ui.CardPatternsScript.CardPattern.COMPOUND: return Color(0.11, 0.45, 0.29, 1.0)   # 深绿
		_ui.CardPatternsScript.CardPattern.CLAN_BOMB: return Color(0.69, 0.23, 0.18, 1.0)  # 深红
		_ui.CardPatternsScript.CardPattern.ORGANIC: return Color(0.55, 0.36, 0.10, 1.0)    # 琥珀
		_ui.CardPatternsScript.CardPattern.SEQUENCE: return Color(0.40, 0.29, 0.62, 1.0)   # 深紫
	return _ui.TABLE_TEXT_COLOR                                                          # 单质 / 空桌


func _set_table_text(txt: String, pat: int) -> void:
	if _ui.table_label == null or not is_instance_valid(_ui.table_label):
		return
	var changed: bool = _ui.table_label.text != txt
	_ui.table_label.text = txt
	_ui.table_label.add_theme_color_override("font_color", _table_type_color(pat))
	if changed:
		_tween_table_label_reveal()


# 淡入而不是瞬间换字：桌面是全场视线焦点，"啪"一下换掉容易被当成误刷
func _tween_table_label_reveal() -> void:
	if _ui.table_label == null or not is_instance_valid(_ui.table_label):
		return
	var old = _ui.table_label.get_meta("reveal_tween", false)
	if old is Tween and old.is_valid():
		old.kill()
	_ui.table_label.modulate = Color(1, 1, 1, 0.15)
	var tw = _ui.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ui.table_label, "modulate:a", 1.0, _ui.TABLE_REVEAL_MS / 1000.0)
	_ui.table_label.set_meta("reveal_tween", tw)


# ============================================================
# 桌面小卡：复用判定 / 清空（Slice 6 性能片，本轮唯一改行为处）
# ============================================================
# 为什么在这里判而不是靠 _table_sig：sig 只说「内容是同一批牌」，还得确认
# 那批节点确实还活着（结算页 / 换页时可能被别处清掉），两个条件都满足才复用。
func _reuse_mini_cards(n: int) -> bool:
	if _ui.table_card_buttons.size() != n:
		return false
	for btn in _ui.table_card_buttons:
		if not is_instance_valid(btn) or btn.is_queued_for_deletion():
			return false
	return true


# 清空只做 queue_free：同一帧里新按钮照常 add_child（行数计算会跳过待删节点），
# 与旧实现的时序完全一致，调用方无须关心帧边界。
func _clear_mini_cards() -> void:
	for btn in _ui.table_card_buttons:
		if is_instance_valid(btn) and not btn.is_queued_for_deletion():
			btn.queue_free()
	_ui.table_card_buttons.clear()

