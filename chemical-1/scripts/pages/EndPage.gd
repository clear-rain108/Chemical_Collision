# ============================================================
# pages/EndPage.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4e，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 967-1175 行 --------
func _build_end_page() -> void:
	if not _ui.end_page:
		return
	# 老版本 Main.tscn 的静态子节点整段清掉，保证只有一套 UI
	for c in _ui.end_page.get_children():
		_ui.end_page.remove_child(c)
		c.queue_free()
	_ui._page_backdrop(_ui.end_page, "EndBg", [
		{"t": "H₂O", "p": Vector2(30, 470), "fs": 72},
		{"t": "CO₂", "p": Vector2(884, 60), "fs": 56},
		{"t": "NaCl", "p": Vector2(58, 40), "fs": 48},
		{"t": "O₂", "p": Vector2(1000, 520), "fs": 44},
	], [
		{"s": "H", "p": Vector2(56, 300), "a": -0.13},
		{"s": "O", "p": Vector2(986, 330), "a": 0.12},
	])

	# -------- 结算卡 --------
	var card := Panel.new()
	card.name = "EndCard"
	card.position = _ui.END_CARD_POS
	card.size = _ui.END_CARD_SIZE
	var cs = _ui._make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.96)
	card.add_theme_stylebox_override("panel", cs)
	_ui.end_page.add_child(card)
	_ui._end_card = card

	# 顶部状态条：只留上方两个圆角，才能贴住卡片圆角不露直角
	var bar := Panel.new()
	bar.name = "EndStatusBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(_ui.END_CARD_SIZE.x, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = _ui.START_C_ACCENT
	bs.corner_radius_top_left = _ui.CARD_RADIUS
	bs.corner_radius_top_right = _ui.CARD_RADIUS
	bs.corner_detail = 6
	bar.add_theme_stylebox_override("panel", bs)
	card.add_child(bar)
	_ui._end_status_bar = bar


	# -------- 结果标题 / 描述 / 分隔线 --------
	_ui._end_title = _ui._start_label("游戏结束", 36, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	_ui._end_title.name = "EndTitle"
	_ui._end_title.position = Vector2(0, 34)
	_ui._end_title.size = Vector2(_ui.END_CARD_SIZE.x, 48)
	card.add_child(_ui._end_title)

	_ui.end_label = _ui._start_label("", 18, _ui.START_C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_ui.end_label.name = "EndLabel"
	_ui.end_label.position = Vector2(0, 88)
	_ui.end_label.size = Vector2(_ui.END_CARD_SIZE.x, 26)
	card.add_child(_ui.end_label)

	var div := ColorRect.new()
	div.name = "EndDivider"
	div.color = _ui.END_C_DIVIDER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	div.position = Vector2(32, 124)
	div.size = Vector2(_ui.END_CARD_SIZE.x - 64, 1)
	card.add_child(div)

	# -------- 统计块：总回合 / 剩余牌库 / 剩余手牌 --------
	var captions := ["总回合", "剩余牌库", "剩余手牌"]
	_ui._end_stat_values.clear()
	for i in range(captions.size()):
		var tile := Panel.new()
		tile.name = "EndStat%d" % i
		tile.position = Vector2(38 + i * 196, 142)
		tile.size = Vector2(172, 76)
		tile.add_theme_stylebox_override("panel", _end_stat_style())
		card.add_child(tile)

		var val = _ui._start_label("—", 26, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
		val.name = "EndStat%dValue" % i
		val.position = Vector2(0, 10)
		val.size = Vector2(172, 34)
		tile.add_child(val)
		_ui._end_stat_values.append(val)

		var cap = _ui._start_label(captions[i], 13, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		cap.name = "EndStat%dCaption" % i
		cap.position = Vector2(0, 46)
		cap.size = Vector2(172, 22)
		tile.add_child(cap)

	# -------- 按钮组：返回主页（主）/ 再来一局（次）/ 教学引导（幽灵）--------
	_ui.end_button = _ui._page_primary_btn("返回主页", func() -> void: pass, Vector2(260, 50), "EndButton", 20)
	_ui.end_button.position = Vector2(92, 240)
	card.add_child(_ui.end_button)

	_ui._end_restart_btn = _ui._page_secondary_btn("再来一局", _on_end_restart, Vector2(180, 42),
		"EndRestartBtn", 17)
	_ui._end_restart_btn.position = Vector2(368, 244)
	card.add_child(_ui._end_restart_btn)

	_ui._end_tutorial_btn = _ui._page_ghost_btn("教学引导", _ui._on_show_tutorial_page, Vector2(120, 30),
		"EndTutorialBtn", 15)
	_ui._end_tutorial_btn.position = Vector2(260, 304)
	card.add_child(_ui._end_tutorial_btn)

	_ui._end_rule_note = _ui._start_label("", 13, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_ui._end_rule_note.name = "EndRuleNote"
	_ui._end_rule_note.position = Vector2(0, 346)
	_ui._end_rule_note.size = Vector2(_ui.END_CARD_SIZE.x, 20)
	card.add_child(_ui._end_rule_note)

	# D24：对局模式一行（只有非标准局才有字，标准局留空 —— 老玩家界面零变化）
	var mode_note = _ui._start_label("", 15, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	mode_note.name = "EndModeNote"
	mode_note.position = Vector2(0, 372)
	mode_note.size = Vector2(_ui.END_CARD_SIZE.x, 24)
	card.add_child(mode_note)


func _end_stat_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _ui.END_C_STAT_BG
	sb.set_corner_radius_all(8)
	sb.corner_detail = 6
	return sb


# 本局是否为教程局（level 1/2 或 level0 已进入引导流程）
func _is_tutorial_run() -> bool:
	return _ui.game_manager != null and (_ui.game_manager.tutorial_level >= 1
		or _ui.game_manager.tutorial_level0_phase >= 1)


# -------- 数据填充：把 game_manager 的状态映射到结算卡（幂等，只改文本 / 颜色 / 连接）--------
func _fill_end_page(custom_text: String) -> void:
	if not _ui._end_card:
		return
	var is_tutorial = _is_tutorial_run()
	var w = _ui.game_manager.get_winner() if _ui.game_manager else null
	var head := "游戏结束"
	var head_col = _ui.START_C_ACCENT
	var desc := custom_text
	if w != null:
		var human_win: bool = not w.is_ai
		head = "胜利！" if human_win else "本局结束"
		head_col = _ui.START_C_ACCENT if human_win else _ui.START_C_SUB
		if desc == "":
			desc = "获胜者：%s" % w.player_name
	elif custom_text == "游戏已退出":
		head = "游戏已退出"
		head_col = _ui.END_C_NEUTRAL
		# 描述不复读标题：给出下一步动作
		if desc == custom_text:
			desc = "本局未分胜负，随时再来一局"
	elif custom_text != "":
		head_col = _ui.END_C_WARN
		head = custom_text
		if desc == custom_text:
			desc = "请返回主页重新开始"
	if desc == "":
		desc = "本局结束"
	if _ui._end_title:
		_ui._end_title.text = head
	if _ui.end_label:
		_ui.end_label.text = desc
	if _ui._end_status_bar:
		var sb: StyleBoxFlat = _ui._end_status_bar.get_theme_stylebox("panel")
		if sb:
			sb.bg_color = head_col

	# -------- 统计三件套：总回合 / 剩余牌库 / 剩余手牌 --------
	var turns := "—"
	var deck_left := "—"
	var hand_left := "—"
	if _ui.game_manager:
		turns = str(_ui.game_manager.turn_count)
		var db = _ui.game_manager.get_database()
		if db:
			deck_left = str(db.get_remaining_count())
		if w != null:
			hand_left = str(w.hand.size())
		else:
			var ps = _ui.game_manager.get_players()
			if ps.size() > 0:
				hand_left = str(ps[0].hand.size())
	var texts := [turns, deck_left, hand_left]
	for i in range(_ui._end_stat_values.size()):
		if _ui._end_stat_values[i]:
			_ui._end_stat_values[i].text = texts[i]

	# -------- 规则回顾 --------
	if _ui._end_rule_note:
		if _ui.game_manager:
			var org := "有机物 ✓" if _ui.game_manager.get_organic_rules_enabled() else "有机物 ✗"
			var seq := "顺序 ✓" if _ui.game_manager.get_sequence_rules_enabled() else "顺序 ✗"
			var hal := "卤族互化 ✓" if _ui.game_manager.get_halogen_exchange_allowed() else "卤族互化 ✗"
			var lim := "元素 %d 种" % _ui.game_manager.get_allowed_element_count()
			_ui._end_rule_note.text = "本局规则：%s    %s    %s    %s" % [org, seq, hal, lim]
		else:
			_ui._end_rule_note.text = ""

	# -------- 对局模式（D24）：与规则行分开放，规则行已经占满 640 宽 --------
	var mode_note = _ui.end_page.get_node_or_null("EndCard/EndModeNote") if _ui.end_page else null
	if mode_note:
		if _ui.game_manager and not _ui.game_manager.is_standard_game_mode():
			var mode_diff: String = _ui.game_manager.get_game_mode_summary()
			mode_note.text = "对局模式：%s" % (mode_diff if mode_diff != "" else _ui.game_manager.get_game_mode_name())
		else:
			mode_note.text = ""

	# -------- 按钮去向：教程局回关卡列表，自由局回开始页 --------
	if _ui.end_button:
		_ensure_end_button_connected(_ui._on_show_tutorial_page if is_tutorial else _ui._show_start_page)
		_ui.end_button.text = "返回关卡" if is_tutorial else "返回主页"
	if _ui._end_restart_btn:
		_ui._end_restart_btn.text = "再试一次" if is_tutorial else "再来一局"
	if _ui._end_tutorial_btn:
		_ui._end_tutorial_btn.visible = not is_tutorial


# 「再来一局」：自由局按开始页当前设置重开；教程局重开同一关（level0 也传 0）
func _on_end_restart() -> void:
	if _is_tutorial_run():
		_ui._on_start_tutorial(_ui.game_manager.tutorial_level)
	else:
		_ui._on_start_game()


# -------- 搬运自 scripts/GameUI.gd 第 2607-2635 行 --------
func _show_end_page(custom_text: String) -> void:
	# 已被 _refresh_ui 反复调用：已在结算页时只刷新数据，不重播淡入 / 入场动画（否则每帧闪一下）
	var already_shown: bool = _ui.end_page.visible and is_equal_approx(_ui.end_page.modulate.a, 1.0)
	_ui.start_page.visible = false
	_ui.game_page.visible = false
	_ui.end_page.visible = true
	if _ui.help_page: _ui.help_page.visible = false
	# 结束页独占屏幕：教学关卡列表（可能刚从开始页打开）也一并收起，
	# 否则它会盖在 EndPage 之上（TutorialPage 在 Main.tscn 里排在 EndPage 之后）
	var tut_page = _ui.get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	# 先填数据（标题 / 统计 / 按钮去向），再淡入：观众看到的第一帧就是最终态
	_fill_end_page(custom_text)
	if already_shown:
		return
	_ui._fade_in_page(_ui.end_page)
	_ui._page_deco_float(_ui.end_page)
	_ui._animate_page_intro(_ui.end_page, ["EndCard"])


func _ensure_end_button_connected(target: Callable) -> void:
	if _ui.end_button == null:
		return
	if _ui.end_button.pressed.is_connected(_ui._show_start_page):
		_ui.end_button.pressed.disconnect(_ui._show_start_page)
	if _ui.end_button.pressed.is_connected(_ui._on_show_tutorial_page):
		_ui.end_button.pressed.disconnect(_ui._on_show_tutorial_page)
	if not _ui.end_button.pressed.is_connected(target):
		_ui.end_button.pressed.connect(target)