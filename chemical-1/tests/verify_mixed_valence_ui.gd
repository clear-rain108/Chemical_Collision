# 验证混合价态的面板入口（v4）：人类能不能真的把 Fe₃O₄ 打出去
#   1) Na + Cl（统一价态能解）→ 面板**不**出现混合入口（不打扰玩家）
#   2) N + Cl（假化合物，统一 / 混合都无解）→ 也不出现
#   3) 3Fe + 4O（统一无解、混合有解）→ 出现「混合价态自动配平 ▶」，并写明 Fe +3/+3/+2
#   4) 点它 → 引擎接受，桌面牌型 = 化合物，日志写「四氧化三铁」
# 运行：Godot --headless --path . -s tests/verify_mixed_valence_ui.gd
extends SceneTree

const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const COMPOUND = CardPatternsScript.CardPattern.COMPOUND
const MIXED_BTN_PREFIX = "混合价态"

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


# 把当前玩家的手牌换成指定的符号序列（uid 唯一：pressed 回调里不会再走 uid 校验，但保持真实）
func _set_hand(scene, syms: Array) -> void:
	var p = scene.game_manager.get_current_player()
	p.hand.clear()
	var n := 0
	for s in syms:
		var c = _card(s)
		c.uid = 500 + n
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


func _mixed_button(scene):
	for c in scene.action_panel.get_children():
		if c is Button and String(c.text).begins_with(MIXED_BTN_PREFIX):
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


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._init_game(4, 3)
	for _w in range(3):
		await process_frame

	# ---- 1) 统一价态能解：不显示混合入口 ----
	_set_hand(scene, ["Na", "Cl"])
	await process_frame
	_select_all(scene)
	await process_frame
	_check(_mixed_button(scene) == null, "Na + Cl 不显示混合入口（统一解已够用）")
	_check(_panel_text(scene).find("Na") >= 0, "化合价面板正常列出单价选项（%s）" % _panel_text(scene))

	# ---- 2) 假化合物：同样没有混合入口 ----
	_set_hand(scene, ["N", "Cl"])
	await process_frame
	_select_all(scene)
	await process_frame
	_check(_mixed_button(scene) == null, "N + Cl 不显示混合入口（混合搜索同样无解）")

	# ---- 3) Fe₃O₄：出现混合入口 + 方案文本 ----
	_set_hand(scene, ["Fe", "Fe", "Fe", "O", "O", "O", "O"])
	await process_frame
	_select_all(scene)
	await process_frame
	var btn = _mixed_button(scene)
	_check(btn != null, "3Fe + 4O 显示「混合价态自动配平」入口（面板：%s）" % _panel_text(scene))
	_check(_panel_text(scene).find("+3/+3/+2") >= 0,
		"面板写明混合方案 Fe +3/+3/+2（%s）" % _panel_text(scene))

	# ---- 4) 点按钮 → 真的打出去 ----
	if btn != null:
		btn.emit_signal("pressed")
		for _w in range(3):
			await process_frame
		var gm = scene.game_manager
		_check(gm.get_table_pattern() == COMPOUND,
			"点「混合价态自动配平」后桌面牌型 = 化合物（实际 %d）" % gm.get_table_pattern())
		_check(gm.get_table_custom_valences().get("Fe", null) is Array,
			"桌面化合价记录为混合数组（%s）" % str(gm.get_table_custom_valences()))
		var logs := str(gm.log_messages)
		_check(logs.find("四氧化三铁") >= 0, "日志写入「四氧化三铁」（%s）" % logs)
		_check(scene.selected_indices.is_empty(), "出牌后选中状态已清空")

	if fails == 0:
		print("ALL MIXED VALENCE UI TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d MIXED VALENCE UI TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)
