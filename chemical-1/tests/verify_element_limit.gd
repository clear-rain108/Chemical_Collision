# 验证补充规则「元素限制」（P10：前 20 号元素 + 自选副族 / 卤族扩展）
#   1) 数据层：基础池 = 前 20 号（20 种 / 134 张）；扩展池 = 副族 7 + Br/I
#   2) 引擎：is_element_allowed 判定 / 牌库按限制生成 / 越界牌返回 -8
#   3) 边界：限制局里族炸仍合法；教程局强制 29 种（预设手牌含 Fe，不能被误伤）
#   4) UI：补充规则小页（4 条开关 + 9 个 chip + 统计）/ 勾 chip 自动开限制 / 开局写入引擎
#   5) 帮助页：补充规则 Tab 第 6 张卡是「元素限制」
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const HelpContentScript = preload("res://scripts/HelpContent.gd")

var fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _finish() -> void:
	if fails == 0:
		print("ALL ELEMENT LIMIT TESTS PASSED")
	else:
		print("%d ELEMENT LIMIT TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源，保证原子序数 / 化合价一致）----
func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


# ---- 收集「手牌 + 剩余牌库」出现过的元素符号（验证牌库真的被限制）----
func _hand_and_deck_symbols(gm) -> Array:
	var syms: Array = []
	for p in gm.get_players():
		for c in p.hand:
			if not (c.symbol in syms):
				syms.append(c.symbol)
	var db = gm.get_database()
	for c in db.deck:
		if not (c.symbol in syms):
			syms.append(c.symbol)
	return syms


func _run() -> void:
	# ---------------- 1. 数据层 ----------------
	var base := CardDatabaseScript.get_base_element_symbols()
	_check(base.size() == 20, "基础池 = 前 20 号元素（实际 %d）" % base.size())
	_check("H" in base and "Ca" in base, "基础池含 H(1) 与 Ca(20)")
	_check(not ("Fe" in base) and not ("Br" in base) and not ("I" in base),
		"基础池不含 Fe / Br / I")
	_check(CardDatabaseScript.get_deck_size(base) == 134,
		"基础池牌库 134 张（实际 %d）" % CardDatabaseScript.get_deck_size(base))

	var opt := CardDatabaseScript.get_optional_elements()
	_check(opt.size() == 9, "扩展池 9 种（实际 %d）" % opt.size())
	var sub_n := 0
	var hal_n := 0
	for o in opt:
		if o["group_label"] == CardDatabaseScript.EXTRA_GROUP_SUB:
			sub_n += 1
		else:
			hal_n += 1
	_check(sub_n == 7 and hal_n == 2,
		"扩展池 = 副族 7 + 卤族 2（实际 %d / %d）" % [sub_n, hal_n])
	_check(CardDatabaseScript.get_allowed_symbols(false, ["Fe"]).is_empty(),
		"限制关闭 → 空集合（= 全部 29 种）")
	_check(CardDatabaseScript.get_allowed_symbols(true, []).size() == 20, "限制开启 → 20 种")
	_check(CardDatabaseScript.get_allowed_symbols(true, ["Fe", "I"]).size() == 22,
		"勾 2 个扩展 → 22 种")
	_check(CardDatabaseScript.get_deck_size([]) == 182, "不限制牌库 182 张")
	_check(CardDatabaseScript.get_deck_size(
		CardDatabaseScript.get_allowed_symbols(true, ["Fe"])) == 138,
		"前 20 号 + Fe = 138 张")

	var all_extra: Array = []
	for o in opt:
		all_extra.append(o["symbol"])
	_check(CardDatabaseScript.get_deck_size(
		CardDatabaseScript.get_allowed_symbols(true, all_extra)) == 182,
		"9 个扩展全勾 = 回到 182 张（与老玩法完全一致）")


	# ---------------- 2. 引擎 ----------------
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_check(not gm.get_element_limit_enabled(), "默认不限制（29 种全量）")
	_check(gm.get_allowed_element_count() == 29 and gm.get_deck_size() == 182,
		"默认 29 种 / 182 张")
	_check(gm.is_element_allowed("Fe") and gm.is_element_allowed("I"), "不限制时 Fe / I 都放行")

	gm = GameManagerScript.new()
	gm.element_limit_enabled = true
	gm.init_game(4, 3)
	_check(gm.is_element_allowed("H") and gm.is_element_allowed("Ca"), "限制时前 20 号放行")
	_check(not gm.is_element_allowed("Fe") and not gm.is_element_allowed("Br")
			and not gm.is_element_allowed("I"),
		"限制时未勾选的 Fe / Br / I 被拦")
	_check(gm.get_allowed_element_count() == 20 and gm.get_deck_size() == 134,
		"限制局 20 种 / 134 张")
	var syms := _hand_and_deck_symbols(gm)
	_check(syms.size() == 20, "牌库 + 手牌只出现 20 种元素（实际 %d）" % syms.size())
	_check(not ("Fe" in syms) and not ("Br" in syms) and not ("I" in syms),
		"牌库 + 手牌不含 Fe / Br / I")
	_check(gm.get_database().get_remaining_count() == 102,
		"4 人 × 8 张后牌库剩 102 张（实际 %d）" % gm.get_database().get_remaining_count())

	# 越界牌注入 → -8（防止存档 / 预设牌绕过牌库限制）
	var r_inject = gm.play_cards(0, [_card("Fe")], {}, CardPatternsScript.CardPattern.ELEMENT)
	_check(r_inject == -8, "越界元素出牌返回 -8（实际 %d）" % r_inject)

	# 勾选 Fe 后放行
	gm = GameManagerScript.new()
	gm.element_limit_enabled = true
	gm.allowed_extra_elements = ["Fe"]
	gm.init_game(4, 3)
	_check(gm.is_element_allowed("Fe"), "勾选 Fe 后放行")
	_check(not gm.is_element_allowed("Cu"), "未勾选的 Cu 仍被拦")
	_check(gm.get_allowed_element_count() == 21, "20 + Fe = 21 种")
	_check(gm.get_deck_size() == 138, "牌库 138 张")
	var syms2 := _hand_and_deck_symbols(gm)
	_check(not ("Cu" in syms2) and not ("Br" in syms2), "牌库不含未勾选元素")

	# 限制局里族炸仍合法（F/Cl 都在前 20 号）
	gm = GameManagerScript.new()
	gm.element_limit_enabled = true
	gm.init_game(4, 3)
	var p0 = gm.get_current_player()
	p0.hand.clear()
	p0.hand.append(_card("F"))
	p0.hand.append(_card("Cl"))
	var r_bomb = gm.play_cards(0, [p0.hand[0], p0.hand[1]], {},
		CardPatternsScript.CardPattern.CLAN_BOMB)
	_check(r_bomb == 0, "限制局里 F+Cl 族炸仍合法（实际 %d）" % r_bomb)

	# ---------------- 3. 教程局 ----------------
	var tut = GameManagerScript.new()
	tut.element_limit_enabled = true
	tut.allowed_extra_elements = ["Fe"]
	_check(tut.init_tutorial(0), "教程局初始化成功")
	_check(not tut.get_element_limit_enabled(), "教程局强制关闭元素限制")
	_check(tut.get_deck_size() == 182, "教程局牌库仍是 29 种 / 182 张")


	# ---------------- 4. UI：补充规则小页 ----------------
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var page = scene._start_child("SuppRulesPage")
	_check(page != null and not page.visible, "补充规则小页默认隐藏")
	scene._start_child("SupplementaryHelpBtn").pressed.emit()
	await process_frame
	_check(page != null and page.visible, "点「补充规则」打开小页")

	for n in ["OrganicCheckBox", "SequenceCheckBox", "HalogenCheckBox", "ElementLimitCheckBox"]:
		var cb = scene._start_child(n)
		_check(cb != null and cb.toggle_mode, "%s 是小页里的 toggle 开关" % n)
	var chip_fe = scene._start_child("ElementChip_Fe")
	_check(chip_fe != null and chip_fe.toggle_mode, "Fe chip 存在且可勾选")
	_check(scene._start_child("ElementChip_Cu") != null and scene._start_child("ElementChip_Br") != null,
		"副族 / 卤族扩展 chip 都在")
	var stats = scene._start_child("ElementPoolStats")
	_check(stats != null, "元素池有统计标签")

	# P10.1：chip 紧凑化（104×28、9 个单行、不越出元素池）+ 固定池清单
	var chip_y := -1.0
	var same_row := true
	var right_edge := 0.0
	for s in ["Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Br", "I"]:
		var c = scene._start_child("ElementChip_" + s)
		if c == null:
			same_row = false
			continue
		if chip_y < 0.0:
			chip_y = c.position.y
		elif absf(c.position.y - chip_y) > 0.01:
			same_row = false
		right_edge = maxf(right_edge, c.position.x + c.size.x)
	_check(chip_fe.size.x <= 110 and chip_fe.size.y <= 30,
		"chip 已紧凑化（%.0f×%.0f）" % [chip_fe.size.x, chip_fe.size.y])
	_check(same_row, "9 个 chip 排在同一行")
	_check(right_edge <= 1040.0, "最右 chip 不越出元素池（右边界 %.0f）" % right_edge)
	var base0 = scene._start_child("ElementPoolBase0")
	var base1 = scene._start_child("ElementPoolBase1")
	_check(base0 != null and base1 != null and base0.text.find("H") >= 0 and base1.text.find("Ca") >= 0,
		"元素池列出固定加入的 20 种基础元素")

	# 限制未开时 chip 只是预选 → 压暗
	_check(chip_fe.modulate.a < 0.7, "限制关闭时 chip 压暗（a=%.2f）" % chip_fe.modulate.a)

	# 勾 chip 自动打开「元素限制」
	chip_fe.button_pressed = true
	await process_frame
	_check(scene._start_child("ElementLimitCheckBox").button_pressed,
		"勾元素 chip 自动打开「元素限制」")
	_check(chip_fe.modulate.a > 0.9, "限制开启后 chip 恢复正常亮度")
	_check(stats.text.find("Fe") >= 0 and stats.text.find("138") >= 0,
		"统计显示 21 种 / 138 张（实际「%s」）" % stats.text)
	_check(scene._start_child("SuppRulesSummary").text.find("元素限制") >= 0,
		"开始页摘要显示元素限制（实际「%s」）" % scene._start_child("SuppRulesSummary").text)
	_check(scene._start_child("SupplementaryHelpBtn").text.find("1 项") >= 0,
		"入口按钮显示已开启项数（实际「%s」）" % scene._start_child("SupplementaryHelpBtn").text)

	# 完成 → 开局：设置真正写进引擎
	scene._start_child("SuppRulesDoneBtn").pressed.emit()
	await process_frame
	_check(not page.visible, "点「完成」关闭小页")
	scene._on_start_game()
	await process_frame
	_check(scene.game_manager != null and scene.game_manager.get_element_limit_enabled(),
		"开局后引擎读到元素限制")
	_check(scene.game_manager != null and scene.game_manager.get_allowed_extra_elements() == ["Fe"],
		"开局后额外元素 = Fe（实际 %s）" % str(scene.game_manager.get_allowed_extra_elements()))
	_check(scene.game_manager != null and scene.game_manager.get_deck_size() == 138,
		"本局牌库 138 张")
	_check(scene.game_manager != null and scene.game_manager.get_allowed_element_count() == 21,
		"本局 21 种元素")
	_check(scene._format_player_status().find("元素限制") >= 0, "信息栏显示元素限制")

	# ---------------- 5. 帮助页 ----------------
	var supp := HelpContentScript.get_supp_cards()
	_check(supp.size() == 6, "补充规则共 6 张卡（实际 %d）" % supp.size())
	var has_limit := false
	for c in supp:
		if str(c.get("title", "")) == "元素限制":
			has_limit = true
	_check(has_limit, "补充规则含「元素限制」卡")

	_finish()
