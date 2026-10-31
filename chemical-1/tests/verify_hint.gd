# 验证「提示」按钮（P6 方案 C：自动选中最优可出组合 + 信息栏解释）
#   1) 数据层：HintAdvisor.suggest() 给出的 indices 一定真的能打出
#      —— 每条用例都用「全新 GameManager + 同样的参数」再调一次 play_cards 交叉验证
#   2) 牌型覆盖：单质 / 双原子单质 / 化合物（2 元素配平、3 元素电荷平衡）/ 有机物 / 族炸 / 顺序
#   3) 桌面限制：接不上桌面时不给建议，并提示「跳过」
#   4) UI 层：点提示 → 自动选牌 + 填好化合价 + 信息栏解释；
#      动牌 / 返回 / 出牌后提示自动作废，按钮也复位
extends SceneTree

const HintScript = preload("res://scripts/HintAdvisor.gd")
const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

var fails: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _finish() -> void:
	if fails == 0:
		print("ALL HINT TESTS PASSED")
	else:
		print("%d HINT TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源，保证化合价 / 原子序数一致）----
func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


# ---- 全新 GM + 指定手牌（人类玩家 = players[0]）----
func _gm_with_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	var p = gm.get_current_player()
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))
	return gm


func _cards_of(gm, indices: Array) -> Array:
	var cp = gm.get_current_player()
	var out: Array = []
	for i in indices:
		out.append(cp.hand[int(i)])
	return out


# ---- 按建议里的牌型真的打出一次（交叉验证：不能被 play_cards 判非法）----
func _play_as(gm, adv: Dictionary) -> int:
	var cards := _cards_of(gm, adv["indices"])
	var idx: int = gm.get_current_player_index()
	var p: int = adv["pattern"]
	if p == CardPatternsScript.CardPattern.COMPOUND:
		return gm.play_cards(idx, cards, adv["valence"], CardPatternsScript.CardPattern.COMPOUND)
	if p == CardPatternsScript.CardPattern.ORGANIC:
		return gm.play_cards(idx, cards, {"_organic": true}, CardPatternsScript.CardPattern.ORGANIC)
	if p == CardPatternsScript.CardPattern.ELEMENT:
		return gm.play_cards(idx, cards, {}, CardPatternsScript.CardPattern.ELEMENT)
	if p == CardPatternsScript.CardPattern.CLAN_BOMB:
		return gm.play_cards(idx, cards, {}, CardPatternsScript.CardPattern.CLAN_BOMB)
	if p == CardPatternsScript.CardPattern.SEQUENCE:
		return gm.play_cards(idx, cards, {}, CardPatternsScript.CardPattern.SEQUENCE)
	return -99


# 建议必须自洽：有 indices / 有文案 / 下标合法 / 真能打出
func _check_suggestion(gm, adv: Dictionary, tag: String) -> void:
	_check(not adv.is_empty(), "%s：有建议" % tag)
	if adv.is_empty():
		return
	_check(not adv["indices"].is_empty(), "%s：indices 非空" % tag)
	_check(str(adv.get("text", "")).begins_with("提示"), "%s：文案以「提示」开头 → %s" % [tag, adv.get("text", "")])
	var cp = gm.get_current_player()
	var in_range := true
	for i in adv["indices"]:
		if int(i) < 0 or int(i) >= cp.hand.size():
			in_range = false
	_check(in_range, "%s：indices 都在手牌范围内" % tag)
	_check(HintScript.is_playable(gm, adv["indices"]), "%s：is_playable 认为可打出" % tag)
	var result := _play_as(gm, adv)
	_check(result >= 0, "%s：play_cards 实际返回 %d（0=成功 / 1=顺序成功后选牌型）" % [tag, result])


func _run() -> void:
	# ---------------- 1. 空输入 ----------------
	_check(HintScript.suggest(null).is_empty(), "suggest(null) 返回空")
	var gm_empty = _gm_with_hand([])
	_check(HintScript.suggest(gm_empty).is_empty(), "空手牌返回空建议")
	_check(not HintScript.is_playable(gm_empty, [0]), "空手牌 is_playable([0]) = false")

	# ---------------- 2. 单质 ----------------
	var gm1 = _gm_with_hand(["Fe"])
	var adv1 = HintScript.suggest(gm1)
	_check(adv1.get("pattern", -1) == CardPatternsScript.CardPattern.ELEMENT, "单张 Fe → 单质")
	_check_suggestion(gm1, adv1, "单质 Fe")

	var gm2 = _gm_with_hand(["H", "H"])
	var adv2 = HintScript.suggest(gm2)
	_check(adv2.get("pattern", -1) == CardPatternsScript.CardPattern.ELEMENT and adv2["indices"].size() == 2,
		"H+H → H2 双原子单质（2 张）")
	_check_suggestion(gm2, adv2, "双原子 H2")

	# ---------------- 3. 化合物：2 元素配平 ----------------
	var gm3 = _gm_with_hand(["Na", "Cl"])
	var adv3 = HintScript.suggest(gm3)
	_check(adv3.get("pattern", -1) == CardPatternsScript.CardPattern.COMPOUND, "Na+Cl → 化合物")
	_check(int(adv3["valence"].get("Na", 0)) == 1 and int(adv3["valence"].get("Cl", 0)) == -1,
		"NaCl 化合价 +1 / -1（实际 %s）" % str(adv3.get("valence", {})))
	_check(adv3["indices"].size() == 2, "NaCl 用 2 张牌")
	_check_suggestion(gm3, adv3, "化合物 NaCl")

	var gm4 = _gm_with_hand(["Ca", "Cl", "Cl"])
	var adv4 = HintScript.suggest(gm4)
	_check(adv4.get("pattern", -1) == CardPatternsScript.CardPattern.COMPOUND and adv4["indices"].size() == 3,
		"Ca+2Cl → CaCl2（1:2，共 3 张）")
	_check_suggestion(gm4, adv4, "化合物 CaCl2")

	# ---------------- 4. 化合物：3 元素电荷平衡 ----------------
	var gm5 = _gm_with_hand(["Na", "O", "H"])
	var adv5 = HintScript.suggest(gm5)
	_check(adv5.get("pattern", -1) == CardPatternsScript.CardPattern.COMPOUND and adv5["indices"].size() == 3,
		"Na+O+H → NaOH（3 元素各 1 张，总电荷 0）")
	_check_suggestion(gm5, adv5, "化合物 NaOH")

	# ---------------- 5. 有机物 ----------------
	var gm6 = _gm_with_hand(["C", "H", "H", "H", "H"])
	var adv6 = HintScript.suggest(gm6)
	_check(adv6.get("pattern", -1) == CardPatternsScript.CardPattern.ORGANIC and adv6["indices"].size() == 5,
		"CH4 → 有机物（5 张）")
	_check_suggestion(gm6, adv6, "有机物 CH4")

	# ---------------- 6. 族炸优先于顺序 ----------------
	var gm7 = _gm_with_hand(["Fe", "Co", "Ni"])
	gm7.sequence_rules_enabled = true
	var adv7 = HintScript.suggest(gm7)
	_check(adv7.get("pattern", -1) == CardPatternsScript.CardPattern.CLAN_BOMB,
		"Fe+Co+Ni 既是族炸又是顺序时优先族炸（实际 %d）" % adv7.get("pattern", -1))
	_check_suggestion(gm7, adv7, "族炸 Fe+Co+Ni")

	# ---------------- 7. 顺序：受规则开关控制 ----------------
	var gm8 = _gm_with_hand(["C", "N", "O"])
	gm8.sequence_rules_enabled = false
	var adv8 = HintScript.suggest(gm8)
	_check(adv8.get("pattern", -1) != CardPatternsScript.CardPattern.SEQUENCE,
		"顺序规则关闭时不给顺序建议（实际 %d）" % adv8.get("pattern", -1))
	_check_suggestion(gm8, adv8, "顺序关闭 C/N/O")

	var gm9 = _gm_with_hand(["C", "N", "O"])
	gm9.sequence_rules_enabled = true
	var adv9 = HintScript.suggest(gm9)
	_check(adv9.get("pattern", -1) == CardPatternsScript.CardPattern.SEQUENCE, "顺序规则开启后给顺序建议")
	_check_suggestion(gm9, adv9, "顺序 C/N/O")

	# ---------------- 8. 桌面限制 ----------------
	var gm10 = _gm_with_hand(["Na", "Cl"])
	gm10.is_round_starter = false
	gm10.table_pattern = CardPatternsScript.CardPattern.ELEMENT
	gm10.table_cards = [_card("Fe")]
	gm10.table_player_index = 1
	var adv10 = HintScript.suggest(gm10)
	_check(adv10.get("pattern", -1) == CardPatternsScript.CardPattern.ELEMENT,
		"桌面是单质 Fe 时只建议单质（实际 %d）" % adv10.get("pattern", -1))
	_check(not HintScript.is_playable(gm10, [0, 1]), "Na+Cl 化合物接不上单质桌面 → is_playable false")
	_check_suggestion(gm10, adv10, "接单质桌面")

	var gm11 = _gm_with_hand(["I"])
	gm11.is_round_starter = false
	gm11.table_pattern = CardPatternsScript.CardPattern.ELEMENT
	gm11.table_cards = [_card("Na")]
	gm11.table_player_index = 1
	_check(HintScript.suggest(gm11).is_empty(), "I 压不过桌面 Na → 不给建议")
	_check(not HintScript.is_playable(gm11, [0]), "I 压不过桌面 Na → is_playable false")

	# ---------------- 9. 越界与化合价工具 ----------------
	var gm12 = _gm_with_hand(["Na", "Cl"])
	_check(not HintScript.is_playable(gm12, [0, 9]), "越界下标 → is_playable false")
	var cv = HintScript.compound_valence_for([_card("Na"), _card("Cl")])
	_check(int(cv.get("Na", 0)) == 1 and int(cv.get("Cl", 0)) == -1,
		"compound_valence_for(Na,Cl) = {Na:1, Cl:-1}")
	_check(HintScript.compound_valence_for([_card("Fe")]).is_empty(), "单张牌给不出化合物化合价 → {}")

	# 纯卤素手牌（F+Cl）：默认只能建议族炸 —— 化合物路径被「禁止卤族互化」拦掉
	var gm_h = _gm_with_hand(["F", "Cl"])
	var adv_h: Dictionary = HintScript.suggest(gm_h)
	_check(int(adv_h.get("pattern", -1)) == CardPatternsScript.CardPattern.CLAN_BOMB,
		"F+Cl 只建议族炸，不建议化合物（实际牌型 %d）" % int(adv_h.get("pattern", -1)))
	_check_suggestion(gm_h, adv_h, "纯卤素 F+Cl")

	# 族炸冷却 + 补充规则「允许卤族互化」打开 → 才建议 ClF 化合物
	var gm_h2 = _gm_with_hand(["F", "Cl"])
	gm_h2.get_current_player().clan_bomb_cooling = true
	gm_h2.halogen_exchange_allowed = true
	var adv_h2: Dictionary = HintScript.suggest(gm_h2)
	_check(int(adv_h2.get("pattern", -1)) == CardPatternsScript.CardPattern.COMPOUND,
		"开关打开+冷却：F+Cl 才建议化合物（实际牌型 %d）" % int(adv_h2.get("pattern", -1)))
	_check_suggestion(gm_h2, adv_h2, "允许卤族互化 ClF")

	await _run_ui()
	_finish()


# ============================================================
# UI 层：点提示 → 自动选牌 + 填价 + 信息栏解释；动牌 / 返回后作废
# ============================================================
func _run_ui() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_check(scene.hint_button != null, "帮助按钮之外的 HintButton 已绑定")
	_check(scene.card_info_label != null, "信息栏 CardInfoLabel 已绑定")
	if scene.hint_button == null or scene.card_info_label == null:
		return

	scene._init_game(4, 3)
	await process_frame
	_check(scene.game_manager != null, "开局后 game_manager 已创建")
	_check(scene.card_info_label.text.begins_with("提示"), "未点提示时信息栏是默认「提示: 可用牌型」")

	# 固定手牌 Na + Cl（一定能合成 NaCl）
	var p = scene.game_manager.get_current_player()
	p.hand.clear()
	p.hand.append(_card("Na"))
	p.hand.append(_card("Cl"))
	scene._refresh_ui()
	await process_frame

	# 模拟玩家真的按下提示按钮（信号会走 _on_hint_toggled）
	scene.hint_button.set_pressed_no_signal(true)
	scene._on_hint_toggled(true)

	_check(scene._hint_text.begins_with("提示"), "点提示后写入说明：%s" % scene._hint_text)
	_check(scene.selected_indices == [0, 1], "自动选中 Na+Cl（实际 %s）" % str(scene.selected_indices))
	_check(scene.step_mode == 2, "化合物提示直接把面板推到「确认打出」(step_mode=2)")
	_check(scene.compound_selections.size() == 2, "化合价已自动填好 2 条")
	_check(scene.card_info_label.text == scene._hint_text, "信息栏显示提示文案而不是「可用牌型」")
	_check(scene.action_panel.get_child_count() > 0, "操作面板已重建")
	var has_confirm := false
	for c in scene.action_panel.get_children():
		if c is Button and c.text == "确认打出":
			has_confirm = true
	_check(has_confirm, "操作面板出现「确认打出」按钮（玩家一步即可出牌）")

	# 刷新 UI 不会覆盖提示（guard 生效）
	scene._refresh_ui()
	await process_frame
	_check(scene.card_info_label.text == scene._hint_text, "_refresh_ui() 后提示文案仍在")

	# 返回 → 提示作废、按钮复位（选牌保留，方便玩家换牌型重新出）
	scene._on_back()
	_check(scene._hint_text == "", "返回后提示作废")
	_check(not scene.hint_button.button_pressed, "返回后提示按钮复位")
	_check(scene.selected_indices == [0, 1], "返回后保留已选牌（原行为：换牌型时不用重选）")
	_check(scene.card_info_label.text.begins_with("提示"), "返回后信息栏回到默认文案")

	# 点牌也清提示
	scene.hint_button.set_pressed_no_signal(true)
	scene._on_hint_toggled(true)
	_check(scene._hint_text != "", "再次点提示仍能给出建议")
	scene._on_back()
	scene._on_card_clicked(0)
	_check(scene._hint_text == "", "玩家点牌后提示作废")
	_check(scene.selected_indices == [1], "玩家点牌后按自己的选择取消 0 号牌")

	# 无解局面 → 提示「跳过」
	p.hand.clear()
	p.hand.append(_card("I"))
	var gm = scene.game_manager
	gm.is_round_starter = false
	gm.table_pattern = CardPatternsScript.CardPattern.ELEMENT
	gm.table_cards = [_card("Na")]
	gm.table_player_index = 1
	scene._step_reset()
	scene._refresh_ui()
	await process_frame
	scene.hint_button.set_pressed_no_signal(true)
	scene._on_hint_toggled(true)
	_check(scene._hint_text.find("跳过") >= 0, "无解时提示「跳过」：%s" % scene._hint_text)
	_check(scene.selected_indices.is_empty(), "无解时不乱选牌")


