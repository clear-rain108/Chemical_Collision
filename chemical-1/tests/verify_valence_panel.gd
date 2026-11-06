# 验证化合价面板 P14-B：把「为什么被拒」直接摆在玩家面前 + 一键配平
#   1) 面板显示总电荷 Σ（按张数累加）：Na +1 / Cl -1 → Σ = 0（已配平 ✓）
#   2) H,H,C,N 选 H=-1 / C=+4 / N=-3 → Σ = -1（红字），点「确认打出」→ 提示写明「H×2 多带了」
#   3) 引擎拒绝时写 last_reject_reason（=「非法出牌！」后面那行），不再只有一句空话
#   4) 「自动配平 ▶」：可行解直接打出，玩家不必猜价
#   5) 已经配平（Σ=0）时不显示「自动配平 ▶」（不打扰）
# 运行：Godot --headless --path . -s tests/verify_valence_panel.gd
extends SceneTree

const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")

const COMPOUND = CardPatternsScript.CardPattern.COMPOUND
const AUTO_BTN_PREFIX = "自动配平"

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


# 把当前玩家的手牌换成指定符号序列（与 verify_mixed_valence_ui 同一套约定）
func _set_hand(scene, syms: Array) -> void:
	var p = scene.game_manager.get_current_player()
	p.hand.clear()
	var n := 0
	for s in syms:
		var c = _card(s)
		c.uid = 700 + n
		p.hand.append(c)
		n += 1
	scene.selected_indices = []
	scene.compound_selections.clear()
	scene.step_mode = 2
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


func _sum_label(scene):
	for c in scene.action_panel.get_children():
		if c is Label and c.name == "ValenceSumLabel":
			return c
	return null


func _panel_text(scene) -> String:
	var parts: Array = []
	for c in scene.action_panel.get_children():
		if c is Button:
			parts.append("[%s]" % c.text)
		elif c is Label:
			parts.append(c.text)
	return " ".join(parts)


func _warn_text(scene) -> String:
	if not is_instance_valid(scene._warning_label):
		return ""
	return String(scene._warning_label.text)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._init_game(4, 3)
	for _w in range(3):
		await process_frame
	var gm = scene.game_manager

	# ---- 0) 引擎侧：拒绝原因（只读，不动局面）----
	var dup_cards := _cards(["H", "H", "C", "N"])
	var dup_cv := {"H": -1, "C": 4, "N": -3}
	var r0: int = gm.validate_play(0, dup_cards, dup_cv, COMPOUND)
	_check(r0 == -1, "H₂+C+N（H=-1）引擎拒绝（返回 %d）" % r0)
	var why0: String = gm.get_last_reject_reason()
	_check(why0.find("Σ = -1") >= 0, "拒绝原因写明总电荷 Σ = -1（实际「%s」）" % why0)

	# 空 cv（让求解器自动配价）也要有人话原因：H₃O 这种比例不成立的组合
	var fake_cards := _cards(["H", "H", "H", "O"])
	var r1: int = gm.validate_play(0, fake_cards, {}, COMPOUND)
	_check(r1 == -1, "H₃O（比例不成立）引擎拒绝（返回 %d）" % r1)
	_check(gm.get_last_reject_reason().find("配不出") >= 0,
		"自动配价失败时给出「配不出化学式」原因（实际「%s」）" % gm.get_last_reject_reason())

	# ---- 1) 面板 Σ：配平组合 → 绿字「已配平」----
	_set_hand(scene, ["Na", "Cl"])
	await process_frame
	_select_all(scene)
	await process_frame
	scene._on_select_valence("Na", 1)
	scene._on_select_valence("Cl", -1)
	await process_frame
	var sum_lbl = _sum_label(scene)
	_check(sum_lbl != null, "面板出现总电荷 Σ 标签（面板：%s）" % _panel_text(scene))
	if sum_lbl != null:
		_check(String(sum_lbl.text).find("Σ = 0") >= 0 and String(sum_lbl.text).find("已配平") >= 0,
			"Na(+1) + Cl(-1) → Σ = 0（实际「%s」）" % sum_lbl.text)
		var ok_color: Color = sum_lbl.get_theme_color("font_color")
		_check(ok_color.g > ok_color.r, "Σ = 0 用绿色系显示（实际 %s）" % str(ok_color))
	_check(_panel_button(scene, AUTO_BTN_PREFIX) == null,
		"已配平时不显示「自动配平」按钮（%s）" % _panel_text(scene))

	# ---- 2) 面板 Σ：配不平组合 → 红字 + 点确认后提示「H×2 多带了」----
	_set_hand(scene, ["H", "H", "C", "N"])
	await process_frame
	_select_all(scene)
	await process_frame
	scene._on_select_valence("H", -1)
	scene._on_select_valence("C", 4)
	scene._on_select_valence("N", -3)
	await process_frame
	sum_lbl = _sum_label(scene)
	_check(sum_lbl != null and String(sum_lbl.text).find("Σ = -1") >= 0,
		"H,H,C,N（H=-1）→ 面板显示 Σ = -1（实际「%s」）" % (String(sum_lbl.text) if sum_lbl else "缺失"))
	if sum_lbl != null:
		var bad_color: Color = sum_lbl.get_theme_color("font_color")
		_check(bad_color.r > bad_color.g, "Σ ≠ 0 用红色系显示（实际 %s）" % str(bad_color))
	_check(scene._selection_charge_sum() == -1,
		"_selection_charge_sum() 按张数累加（期望 -1，实际 %d）" % scene._selection_charge_sum())
	var confirm_btn = _panel_button(scene, "确认打出")
	_check(confirm_btn != null, "配不平也允许点「确认打出」（由引擎给出原因，而不是界面先拦）")
	if confirm_btn != null:
		confirm_btn.emit_signal("pressed")
		await process_frame
		var wtxt := _warn_text(scene)
		_check(wtxt.find("H×2") >= 0 and wtxt.find("多带了") >= 0,
			"提示点名「H×2 多带了」（实际「%s」）" % wtxt)
		_check(wtxt.find("Σ = -1") >= 0, "提示同时给出 Σ = -1（实际「%s」）" % wtxt)

	# ---- 3) 「自动配平 ▶」：可行解直接打出 ----
	_set_hand(scene, ["H", "C", "N"])
	await process_frame
	_select_all(scene)
	await process_frame
	var auto_btn = _panel_button(scene, AUTO_BTN_PREFIX)
	_check(auto_btn != null, "H + C + N 显示「自动配平 ▶」（面板：%s）" % _panel_text(scene))
	if auto_btn != null:
		var expect_cv: Dictionary = CompoundSolverScript.get_uniform_valence_pairs(_cards(["H", "C", "N"]))
		_check(not expect_cv.is_empty(), "求解器给出 H/C/N 的可行价（%s）" % str(expect_cv))
		auto_btn.emit_signal("pressed")
		for _w in range(3):
			await process_frame
		_check(gm.get_table_pattern() == COMPOUND,
			"点「自动配平」后桌面牌型 = 化合物（实际 %d）" % gm.get_table_pattern())
		_check(scene.selected_indices.is_empty(), "出牌后选中状态已清空")
		var played_cv: Dictionary = gm.get_table_custom_valences()
		_check(not played_cv.is_empty(), "桌面记录了所用化合价（%s）" % str(played_cv))

	if fails == 0:
		print("ALL VALENCE PANEL TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d VALENCE PANEL TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)
