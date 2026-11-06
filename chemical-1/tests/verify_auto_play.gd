# 验证「先出后验」`GameManager.auto_play()`（P14-C）
#   1) 候选优先级固定：有机物 → 单质 → 化合物 → 顺序 → 族炸
#   2) 化合物优先于族炸（同族元素既能族炸又能配成化合物时，选化学意义的那条）
#   3) 预览只读：不落子、不动手牌 / 桌面
#   4) 全都非法时返回负数，并留下可读原因（不再只有「非法出牌！」）
#   5) 真出牌：auto_play 落子后桌面牌型正确、那几张牌从手牌消失
#   6) 界面入口：「直接出牌 ⚡」按钮存在，点了能出；非法组合会弹提示且不动手牌
# 运行：Godot --headless --path . -s tests/verify_auto_play.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const COMPOUND = CardPatternsScript.CardPattern.COMPOUND
const ELEMENT = CardPatternsScript.CardPattern.ELEMENT
const CLAN_BOMB = CardPatternsScript.CardPattern.CLAN_BOMB
const SEQUENCE = CardPatternsScript.CardPattern.SEQUENCE
const ORGANIC = CardPatternsScript.CardPattern.ORGANIC

const SEED := 20260301
const AUTO_BTN_PREFIX = "直接出牌"

var fails: int = 0
var total: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	total += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


func _cards(syms: Array) -> Array:
	var out: Array = []
	for s in syms:
		out.append(_card(s))
	return out


# 新局：0 号位首出（桌面空），规则全开便于覆盖顺序 / 有机物分支
func _new_gm():
	var gm = GameManagerScript.new()
	gm.init_game(4, 3, SEED)
	gm.organic_rules_enabled = true
	gm.sequence_rules_enabled = true
	var p = gm.players[0]
	p.hand.clear()
	var n := 0
	for s in ["Na", "Cl", "H", "H", "Li", "Fe", "Co", "Ni", "C", "N", "O"]:
		var c = _card(s)
		c.uid = 900 + n
		p.hand.append(c)
		n += 1
	return gm


func _preview(gm, syms: Array) -> Dictionary:
	return gm.auto_play_preview(0, _cards(syms))


# 从手牌里取出真实卡牌对象（play_cards 靠 uid 移除，用新造的卡会移除不掉）
func _take(gm, seat: int, syms: Array) -> Array:
	var out: Array = []
	var p = gm.players[seat]
	for s in syms:
		for c in p.hand:
			if c.symbol == s and c not in out:
				out.append(c)
				break
	return out


func _run() -> void:
	# ---------------- 1) 候选优先级（引擎层，只读预览）----------------
	var gm = _new_gm()

	var p_org: Dictionary = _preview(gm, ["C", "H", "H", "H", "H"])
	_check(int(p_org["pattern"]) == ORGANIC,
		"CH₄ → 有机物优先（实际 %d）" % int(p_org["pattern"]))

	var p_elem: Dictionary = _preview(gm, ["H", "H"])
	_check(int(p_elem["pattern"]) == ELEMENT, "H₂ → 单质（实际 %d）" % int(p_elem["pattern"]))

	var p_comp: Dictionary = _preview(gm, ["Na", "Cl"])
	_check(int(p_comp["pattern"]) == COMPOUND, "Na+Cl → 化合物（实际 %d）" % int(p_comp["pattern"]))
	_check(not p_comp["custom_valences"].is_empty(),
		"化合物候选带上配平价（%s）" % str(p_comp["custom_valences"]))

	# 同族不同元素：VA 族 N+P 既能族炸又能配成化合物 PN —— 化合物优先
	# （CardPatterns.compare_cards 的注释里举的正是这个例子）
	var p_pref: Dictionary = _preview(gm, ["N", "P"])
	_check(int(p_pref["pattern"]) == COMPOUND,
		"N+P（同族且能配平）优先当化合物（实际 %d）" % int(p_pref["pattern"]))

	# 纯同族、配不成化合物的 → 族炸
	var p_bomb: Dictionary = _preview(gm, ["Li", "Na"])
	_check(int(p_bomb["pattern"]) == CLAN_BOMB,
		"Li+Na（配不成化合物）→ 族炸（实际 %d）" % int(p_bomb["pattern"]))

	# 26/27/28 既是 VIII 族炸又是顺序 → 顺序在后，但族炸与顺序都合法时取先到的？
	# 候选顺序：化合物（无解）→ 顺序 → 族炸，所以这里应命中顺序
	var p_seq: Dictionary = _preview(gm, ["Fe", "Co", "Ni"])
	_check(int(p_seq["pattern"]) == SEQUENCE,
		"Fe+Co+Ni 顺序规则开启 → 顺序（实际 %d）" % int(p_seq["pattern"]))

	# ---------------- 2) 预览只读 ----------------
	var hand_before: int = gm.players[0].get_hand_count()
	var table_before: int = gm.get_table_cards().size()
	var p_ro: Dictionary = _preview(gm, ["Na", "Cl"])
	_check(gm.players[0].get_hand_count() == hand_before and gm.get_table_cards().size() == table_before,
		"auto_play_preview 只读（手牌 %d / 桌面 %d 未变）" % [hand_before, table_before])
	_check(int(p_ro["code"]) == int(p_comp["code"]), "同一组牌预览两次结果一致（幂等）")

	# ---------------- 3) 全非法：返回负数 + 有原因 ----------------
	var p_bad: Dictionary = _preview(gm, ["N", "Cl"])
	_check(int(p_bad["code"]) < 0, "N+Cl 无任何合法牌型（返回 %d）" % int(p_bad["code"]))
	_check(str(p_bad["reason"]) != "", "失败时给出原因（「%s」）" % str(p_bad["reason"]))

	# ---------------- 4) 真出牌 ----------------
	var gm2 = _new_gm()
	var na_cl := _take(gm2, 0, ["Na", "Cl"])
	var before2: int = gm2.players[0].get_hand_count()
	var code2: int = gm2.auto_play(0, na_cl)
	_check(code2 == 0, "auto_play(Na+Cl) 返回 0（实际 %d）" % code2)
	_check(gm2.get_table_pattern() == COMPOUND, "桌面牌型 = 化合物（实际 %d）" % gm2.get_table_pattern())
	_check(gm2.players[0].get_hand_count() == before2 - 2,
		"手牌减 2（%d → %d）" % [before2, gm2.players[0].get_hand_count()])
	var logs := str(gm2.log_messages)
	_check(logs.find("氯化钠") >= 0, "日志写入化合物名「氯化钠」（%s）" % logs)

	var gm3 = _new_gm()
	var bad_cards := _take(gm3, 0, ["N", "Cl"])
	var before3: int = gm3.players[0].get_hand_count()
	var code3: int = gm3.auto_play(0, bad_cards)
	_check(code3 < 0, "auto_play(N+Cl) 被拒（实际 %d）" % code3)
	_check(gm3.players[0].get_hand_count() == before3, "被拒后手牌不变（%d）" % gm3.players[0].get_hand_count())
	_check(gm3.get_last_reject_reason() != "", "被拒后 last_reject_reason 非空")

	# ---------------- 5) 界面入口 ----------------
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._on_start_game()
	for _w in range(4):
		await process_frame
	_set_hand(scene, ["N", "Cl"])
	await process_frame
	_select_all(scene)
	await process_frame
	var bad_btn = _panel_button(scene, AUTO_BTN_PREFIX)
	_check(bad_btn != null, "非法组合也显示「直接出牌」（先出后验，不预判置灰）")
	if bad_btn != null:
		var hand_now: int = scene.game_manager.get_current_player().get_hand_count()
		bad_btn.emit_signal("pressed")
		await process_frame
		_check(scene.game_manager.get_current_player().get_hand_count() == hand_now,
			"N+Cl 点「直接出牌」不会动牌（%d）" % hand_now)
		_check(_warn_text(scene) != "", "并弹出可读提示（「%s」）" % _warn_text(scene))

	_set_hand(scene, ["Na", "Cl"])
	await process_frame
	_select_all(scene)
	await process_frame
	var btn = _panel_button(scene, AUTO_BTN_PREFIX)
	_check(btn != null, "操作面板出现「直接出牌 ⚡」（面板：%s）" % _panel_text(scene))
	if btn != null:
		btn.emit_signal("pressed")
		for _w in range(3):
			await process_frame
		_check(scene.game_manager.get_table_pattern() == COMPOUND,
			"点「直接出牌」后桌面牌型 = 化合物（实际 %d）" % scene.game_manager.get_table_pattern())

	if fails == 0:
		print("ALL AUTO PLAY TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d AUTO PLAY TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)


# ---- 界面辅助（与 verify_valence_panel 同一套约定）----
func _set_hand(scene, syms: Array) -> void:
	var p = scene.game_manager.get_current_player()
	p.hand.clear()
	var n := 0
	for s in syms:
		var c = _card(s)
		c.uid = 800 + n
		p.hand.append(c)
		n += 1
	scene.selected_indices = []
	scene.step_mode = 0
	scene._refresh_ui()


func _select_all(scene) -> void:
	scene.selected_indices.clear()
	for i in range(scene.game_manager.get_current_player().hand.size()):
		scene.selected_indices.append(i)
	scene._update_action_panel()


func _panel_button(scene, prefix: String):
	for c in scene.action_panel.get_children():
		if c is Button and String(c.text).begins_with(prefix):
			return c
	return null


func _panel_text(scene) -> String:
	var parts: Array = []
	for c in scene.action_panel.get_children():
		if c is Button:
			parts.append("[%s]" % c.text)
	return " ".join(parts)


func _warn_text(scene) -> String:
	if not is_instance_valid(scene._warning_label):
		return ""
	return String(scene._warning_label.text)

