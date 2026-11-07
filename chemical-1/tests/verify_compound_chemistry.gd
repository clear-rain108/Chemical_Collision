# 验证「假化合物」修复：只有化学上成立的组合才能合成
#   1) 假化合物：NCl / BrN / IN（非金属 1:1，电荷对不上或电负性倒置）→ 一律给不出化学式
#   2) 电负性倒置：Cl(+3) + N(-3) → 拒绝（旧实现会生成不存在的「ClN」）
#   3) 真实化合物：NaCl / CaCl₂ / NCl₃ / NI₃ / BCl₃ / ClF 仍然成立
#   4) 引擎 / 提示 / AI 三层同一判据（建议 = 可打出）
# 运行：Godot --headless --path . -s tests/verify_compound_chemistry.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")
const HintScript = preload("res://scripts/HintAdvisor.gd")
const AIPlayerScript = preload("res://scripts/AIPlayer.gd")

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
		print("ALL COMPOUND CHEMISTRY TESTS PASSED")
	else:
		print("%d COMPOUND CHEMISTRY TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源）----
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


# ---- 全新 GM + 指定人类玩家手牌 ----
func _gm_with_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	var p = gm.get_current_player()
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))
	return gm


# ---- 全新 GM + 指定 AI 手牌（AI = players[1]，回合交给他）----
func _gm_with_ai_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	gm.current_player_index = 1
	var p = gm.get_current_player()
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))
	return gm


# ============================================================
# 一、CompoundSolver：假化合物被拒，真化合物保留
# ============================================================
func _test_solver() -> void:
	# ---- 假化合物：非金属 + 非金属，1:1 时电荷对不上 ----
	_check(not CompoundSolverScript.is_compound(_cards(["N", "Cl"])),
		"is_compound(N+Cl) = false（不再是化合物）")
	_check(not CompoundSolverScript.is_compound(_cards(["Br", "N"])),
		"is_compound(Br+N) = false")
	_check(not CompoundSolverScript.is_compound(_cards(["I", "N"])),
		"is_compound(I+N) = false")
	_check(CompoundSolverScript.get_compound_formula(_cards(["N", "Cl"])).is_empty(),
		"N+Cl 给不出化学式")
	_check(CompoundSolverScript.get_valence_pairs(_cards(["N", "Cl"])).is_empty(),
		"N+Cl 给不出化合价")
	_check(CompoundSolverScript.get_valence_pairs(_cards(["Br", "N"])).is_empty(),
		"Br+N 给不出化合价")
	_check(CompoundSolverScript.get_valence_pairs(_cards(["I", "N"])).is_empty(),
		"I+N 给不出化合价")

	# ---- 电负性倒置：正价元素电负性 > 负价元素 ----
	var fi_bad = CompoundSolverScript.get_compound_formula(_cards(["N", "Cl"]), {"Cl": 3, "N": -3})
	_check(fi_bad.is_empty(), "Cl(+3)+N(-3) 电负性倒置 → 拒绝（旧实现会得到 ClN）")

	# ---- 真实化合物 ----
	var fi_nacl = CompoundSolverScript.get_compound_formula(_cards(["Na", "Cl"]))
	_check(str(fi_nacl.get("formula", "")) == "NaCl",
		"Na+Cl 化学式 NaCl（实际 %s）" % str(fi_nacl.get("formula", "")))
	_check(bool(fi_nacl.get("ratio_ok", false)), "Na+Cl 比例配平")

	var fi_cacl2 = CompoundSolverScript.get_compound_formula(_cards(["Ca", "Cl", "Cl"]))
	_check(str(fi_cacl2.get("formula", "")).begins_with("CaCl"),
		"Ca+2Cl 化学式以 CaCl 开头（实际 %s）" % str(fi_cacl2.get("formula", "")))
	_check(bool(fi_cacl2.get("ratio_ok", false)), "Ca+2Cl 比例配平（1:2）")

	# NCl₃：N 作 +3、Cl 作 -1（旧实现会给 N(-3)/Cl(+3) → ClN 假化合物）
	var ncl3 := _cards(["N", "Cl", "Cl", "Cl"])
	_check(CompoundSolverScript.is_compound(ncl3), "N+3Cl 判为化合物（NCl₃）")
	var cv_ncl3 = CompoundSolverScript.get_valence_pairs(ncl3)
	_check(int(cv_ncl3.get("N", 0)) == 3 and int(cv_ncl3.get("Cl", 0)) == -1,
		"N+3Cl 化合价 = N(+3)/Cl(-1)（实际 %s）" % str(cv_ncl3))
	var fi_ncl3 = CompoundSolverScript.get_compound_formula(ncl3, cv_ncl3)
	_check(str(fi_ncl3.get("formula", "")).begins_with("NCl"),
		"N+3Cl 化学式以 NCl 开头（实际 %s）" % str(fi_ncl3.get("formula", "")))
	_check(bool(fi_ncl3.get("ratio_ok", false)), "N+3Cl 比例配平")

	# NI₃：I 电负性比 N 小 → N 作 -3、I 作 +1
	var ni3 := _cards(["N", "I", "I", "I"])
	var cv_ni3 = CompoundSolverScript.get_valence_pairs(ni3)
	_check(int(cv_ni3.get("N", 0)) == -3 and int(cv_ni3.get("I", 0)) == 1,
		"N+3I 化合价 = N(-3)/I(+1)（实际 %s）" % str(cv_ni3))

	# BCl₃：硼（准金属）作 +3
	var bcl3 := _cards(["B", "Cl", "Cl", "Cl"])
	var cv_bcl3 = CompoundSolverScript.get_valence_pairs(bcl3)
	_check(int(cv_bcl3.get("B", 0)) == 3 and int(cv_bcl3.get("Cl", 0)) == -1,
		"B+3Cl 化合价 = B(+3)/Cl(-1)（实际 %s）" % str(cv_bcl3))

	# ClF：卤素互化的价态本身化学合理（是否允许由规则开关管）
	var cv_clf = CompoundSolverScript.get_valence_pairs(_cards(["Cl", "F"]))
	_check(int(cv_clf.get("Cl", 0)) == 1 and int(cv_clf.get("F", 0)) == -1,
		"Cl+F 化合价 = Cl(+1)/F(-1)（实际 %s）" % str(cv_clf))

	# 面板显式指定低价金属：Fe(+2) + 2Cl(-1) → FeCl₂
	# （默认配平只给金属最高价，玩家在面板上能选 +2，play_cards 必须接受；
	#   v4 开放金属价域后，AI / 提示也能自动给出这个解，见下面的自动解断言）
	var fe_cl2 := _cards(["Fe", "Cl", "Cl"])
	var fi_fe = CompoundSolverScript.get_compound_formula(fe_cl2, {"Fe": 2, "Cl": -1})
	_check(not fi_fe.is_empty() and bool(fi_fe.get("ratio_ok", false)),
		"Fe(+2)+2Cl(-1) 显式价可配平（实际 %s）" % str(fi_fe.get("formula", "")))
	_check(str(fi_fe.get("formula", "")).begins_with("FeCl"),
		"Fe(+2)+2Cl(-1) 化学式以 FeCl 开头（实际 %s）" % str(fi_fe.get("formula", "")))
	# 同一个手牌，若显式给 Fe(+3) → 电荷 3-2=1 ≠ 0 → 不配平
	var fi_fe3 = CompoundSolverScript.get_compound_formula(fe_cl2, {"Fe": 3, "Cl": -1})
	_check(fi_fe3.is_empty() or not bool(fi_fe3.get("ratio_ok", false)),
		"Fe(+3)+2Cl(-1) 电荷不平 → 不配平")

	# v4：金属价域开放（全部正价，降序），这组牌不再需要手选
	var cv_fe_auto = CompoundSolverScript.get_valence_pairs(fe_cl2)
	_check(int(cv_fe_auto.get("Fe", 0)) == 2 and int(cv_fe_auto.get("Cl", 0)) == -1,
		"Fe+2Cl 自动解出 Fe(+2)/Cl(-1)（v4 金属价域开放，实际 %s）" % str(cv_fe_auto))
	var fi_fe_auto = CompoundSolverScript.get_compound_formula(fe_cl2, cv_fe_auto)
	_check(not fi_fe_auto.is_empty() and bool(fi_fe_auto.get("ratio_ok", false)),
		"自动价可直接配平（实际 %s）" % str(fi_fe_auto.get("formula", "")))


# ============================================================
# 二、引擎：play_cards 是唯一判定点
# ============================================================
func _test_engine() -> void:
	# N+Cl 用任何价都打不出（旧实现会静默放行并生成 ClN）
	var gm = _gm_with_hand(["N", "Cl"])
	var p = gm.get_current_player()
	var r1 = gm.play_cards(0, [p.hand[0], p.hand[1]], {"N": -3, "Cl": 3},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r1 == -1, "N+Cl（Cl 作 +3）出牌被拒（实际 %d）" % r1)
	_check(p.hand.size() == 2, "被拒后手牌不变（实际 %d 张）" % p.hand.size())

	var gm2 = _gm_with_hand(["N", "Cl"])
	var p2 = gm2.get_current_player()
	var r2 = gm2.play_cards(0, [p2.hand[0], p2.hand[1]], {},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r2 == -1, "N+Cl 不填化合价也被拒（实际 %d）" % r2)

	var gm3 = _gm_with_hand(["Br", "N"])
	var p3 = gm3.get_current_player()
	var r3 = gm3.play_cards(0, [p3.hand[0], p3.hand[1]], {"Br": 3, "N": -3},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r3 == -1, "Br+N 出牌被拒（实际 %d）" % r3)

	# 真实化合物照常：NaCl 不填价也能自动配平
	var gm4 = _gm_with_hand(["Na", "Cl"])
	var p4 = gm4.get_current_player()
	var r4 = gm4.play_cards(0, [p4.hand[0], p4.hand[1]], {},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r4 == 0, "Na+Cl 不填价仍可出（自动配平，实际 %d）" % r4)

	# NCl₃ 通过面板给的化合价可出
	var gm5 = _gm_with_hand(["N", "Cl", "Cl", "Cl"])
	var p5 = gm5.get_current_player()
	var r5 = gm5.play_cards(0, p5.hand.duplicate(), {"N": 3, "Cl": -1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r5 == 0, "N+3Cl 以 N(+3)/Cl(-1) 可出 NCl₃（实际 %d）" % r5)

	# NCl₃ 若给错价（旧实现的 ClN 价态）仍然被拒
	var gm6 = _gm_with_hand(["N", "Cl", "Cl", "Cl"])
	var p6 = gm6.get_current_player()
	var r6 = gm6.play_cards(0, p6.hand.duplicate(), {"N": -3, "Cl": 1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r6 == -1, "N+3Cl 给 N(-3)/Cl(+1) 被拒（实际 %d）" % r6)


# ============================================================
# 三、提示：与 play_cards 同一判据
# ============================================================
func _test_hint() -> void:
	var gm = _gm_with_hand(["N", "Cl"])
	_check(not HintScript.is_playable(gm, [0, 1]), "提示：N+Cl 判为不可打出")
	var adv: Dictionary = HintScript.suggest(gm)
	_check(not adv.is_empty(), "N+Cl 仍有建议（只能出单质）")
	_check(int(adv.get("pattern", -1)) != CardPatternsScript.CardPattern.COMPOUND,
		"提示不给 NCl 化合物（实际牌型 %d）" % int(adv.get("pattern", -1)))
	if not adv.is_empty():
		var cp = gm.get_current_player()
		var cs: Array = []
		for i in adv["indices"]:
			cs.append(cp.hand[int(i)])
		var r = gm.play_cards(0, cs, adv.get("valence", {}), int(adv["pattern"]))
		_check(r == 0, "提示的建议真能打出（建议=可打出，返回 %d）" % r)

	# NCl₃ 手牌：提示应给出能打出的化合物（或单质），交叉验证必能打出
	var gm2 = _gm_with_hand(["N", "Cl", "Cl", "Cl"])
	var adv2: Dictionary = HintScript.suggest(gm2)
	_check(not adv2.is_empty(), "N+3Cl 有建议")
	if not adv2.is_empty():
		var cp2 = gm2.get_current_player()
		var cs2: Array = []
		for i in adv2["indices"]:
			cs2.append(cp2.hand[int(i)])
		var r2 = gm2.play_cards(0, cs2, adv2.get("valence", {}), int(adv2["pattern"]))
		_check(r2 == 0, "N+3Cl 的提示真能打出（返回 %d）" % r2)


# ============================================================
# 四、AI：不会合成假化合物
# ============================================================
func _test_ai() -> void:
	var gm = _gm_with_ai_hand(["N", "Cl"])
	AIPlayerScript.auto_play(gm, Callable())
	_check(gm.get_table_pattern() != CardPatternsScript.CardPattern.COMPOUND,
		"AI 手牌 N+Cl 不会合成 NCl（桌面牌型 %d）" % gm.get_table_pattern())

	var gm2 = _gm_with_ai_hand(["Br", "N"])
	AIPlayerScript.auto_play(gm2, Callable())
	_check(gm2.get_table_pattern() != CardPatternsScript.CardPattern.COMPOUND,
		"AI 手牌 Br+N 不会合成 BrN（桌面牌型 %d）" % gm2.get_table_pattern())

	var gm3 = _gm_with_ai_hand(["Na", "Cl"])
	AIPlayerScript.auto_play(gm3, Callable())
	_check(gm3.get_table_pattern() == CardPatternsScript.CardPattern.COMPOUND,
		"AI 手牌 Na+Cl 仍会合成 NaCl（桌面牌型 %d）" % gm3.get_table_pattern())

# ---- 多原子化合物 / 化学式约分（P15-B）----
# 旧实现 2Na+2Br 显示 Na₂Br₂、4H+2O 显示 H₄O₂ —— 既不是最简比，也不是真实分子式。
# 现在按最简整数比约分，系数写在前面：2NaBr / 2H₂O；
# 过氧根单独按「O 的个数/2」约分（H₂O₂ 的 H:O 是 1:1，用 gcd 会被约成 HO）。
func _test_multiatom() -> void:
	var cases := [
		{"hand": ["Na", "Na", "Br", "Br"], "formula": "2NaBr", "key": "NaBr", "coef": 2},
		{"hand": ["H", "H", "H", "H", "O", "O"], "formula": "2H₂O", "key": "H2O", "coef": 2},
		{"hand": ["Mg", "Mg", "Mg", "O", "O", "O"], "formula": "3MgO", "key": "MgO", "coef": 3},
		{"hand": ["Fe", "Fe", "Fe", "O", "O", "O", "O"], "formula": "Fe₃O₄", "key": "Fe3O4", "coef": 1},
	]
	for c in cases:
		var cards := _cards(c["hand"])
		var fi: Dictionary = CompoundSolverScript.get_compound_formula(cards, {})
		if fi.is_empty():
			_check(false, "%s 应能配平（实际给不出化学式）" % str(c["hand"]))
			continue
		_check(String(fi.get("formula", "")) == String(c["formula"]),
			"%s → %s（实际 %s）" % [str(c["hand"]), c["formula"], fi.get("formula", "")])
		_check(String(fi.get("formula_key", "")) == String(c["key"]),
			"%s 的 formula_key = %s（实际 %s）" % [str(c["hand"]), c["key"], fi.get("formula_key", "")])
		_check(int(fi.get("coefficient", 0)) == int(c["coef"]),
			"%s 的系数 = %d（实际 %d）" % [str(c["hand"]), c["coef"], int(fi.get("coefficient", 0))])

	# ---- 过氧根（L1/L2）：O 取 −1，且必须成对 ----
	var h2o2 := _cards(["H", "H", "O", "O"])
	var cv_h2o2: Dictionary = CompoundSolverScript.get_uniform_valence_pairs(h2o2)
	_check(int(cv_h2o2.get("O", 0)) == -1, "H+H+O+O 解出 O(-1)（实际 %s）" % str(cv_h2o2))
	var fi_h2o2: Dictionary = CompoundSolverScript.get_compound_formula(h2o2, cv_h2o2)
	_check(String(fi_h2o2.get("formula", "")) == "H₂O₂",
		"H+H+O+O → H₂O₂（实际 %s）" % fi_h2o2.get("formula", ""))
	_check(bool(fi_h2o2.get("peroxy", false)), "H₂O₂ 标记 peroxy = true")
	var name_h2o2: String = CompoundSolverScript.get_compound_name(h2o2, cv_h2o2)
	_check(name_h2o2 == "过氧化氢", "H₂O₂ 命名为过氧化氢（实际「%s」）" % name_h2o2)

	# Ca+2O → CaO₂；Ca+O 仍必须是 CaO（不能被过氧化物抢走）
	var cao2 := _cards(["Ca", "O", "O"])
	var cv_cao2: Dictionary = CompoundSolverScript.get_uniform_valence_pairs(cao2)
	var fi_cao2: Dictionary = CompoundSolverScript.get_compound_formula(cao2, cv_cao2)
	_check(String(fi_cao2.get("formula", "")) == "CaO₂",
		"Ca+2O → CaO₂（实际 %s）" % fi_cao2.get("formula", ""))
	var cao := _cards(["Ca", "O"])
	var cv_cao: Dictionary = CompoundSolverScript.get_uniform_valence_pairs(cao)
	var fi_cao: Dictionary = CompoundSolverScript.get_compound_formula(cao, cv_cao)
	_check(String(fi_cao.get("formula", "")) == "CaO",
		"Ca+O → CaO 而不是 CaO₂（实际 %s）" % fi_cao.get("formula", ""))

	# 成对约束：3 张 O 全取 −1 必须非法（H₃O₃ / Na₂O₃ 都不存在）
	var odd_ozone: Array = [{"symbol": "O", "count": 3, "card": _card("O")}]
	_check(not CompoundSolverScript._valence_assignment_ok(odd_ozone, {"O": -1}),
		"O 取 -1 时 3 张非法（过氧根必须成对）")

	# ---- 溢出判定口径（B′）：按「单分子原子数」，不按「出了几张牌」----
	_check(CompoundSolverScript.get_formula_atom_count(_cards(["Na", "Na", "Br", "Br"])) == 2,
		"2Na+2Br 单分子 2 个原子（实际 %d）"
		% CompoundSolverScript.get_formula_atom_count(_cards(["Na", "Na", "Br", "Br"])))
	_check(CompoundSolverScript.get_formula_atom_count(_cards(["H", "H", "O", "O"])) == 4,
		"H₂O₂ 单分子 4 个原子（实际 %d）"
		% CompoundSolverScript.get_formula_atom_count(_cards(["H", "H", "O", "O"])))
	_check(CompoundSolverScript.get_formula_atom_count(_cards(["P", "P", "O", "O", "O", "O", "O"])) == 7,
		"P₂O₅ 单分子 7 个原子（实际 %d）"
		% CompoundSolverScript.get_formula_atom_count(_cards(["P", "P", "O", "O", "O", "O", "O"])))



func _run() -> void:
	_test_solver()
	_test_engine()
	_test_hint()
	_test_ai()
	_test_multiatom()
	_finish()


