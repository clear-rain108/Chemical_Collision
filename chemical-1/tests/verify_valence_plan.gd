# 验证价态模型 v4 第一部分：数据修正 + 金属价态域开放
#   1) C 的常见化合价补上 +2（CO 需要：C(+2)/O(-2)）
#   2) 金属 / 准金属价域 = 全部正价，降序（高价优先 → 主流解优先命中）
#   3) 低价金属化合物终于可解：FeO / FeCl₂ / Cu₂O / MnO₂ / Cr₂O₃
#   4) 高价主流解优先：Fe₂O₃ 仍是 Fe(+3)，CuO 仍是 Cu(+2)
#   5) v3 的裁决不倒退：NCl/BrN/IN 仍拒绝，NCl₃/BCl₃/ClF 仍成立
#   6) 同一组牌反复求解结果一致（AI / 提示 / 面板 / 联机回放要可复现）
# 运行：Godot --headless --path . -s tests/verify_valence_plan.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")

const COMPOUND = CardPatternsScript.CardPattern.COMPOUND

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
		print("ALL VALENCE PLAN TESTS PASSED")
	else:
		print("%d VALENCE PLAN TESTS FAILED" % fails)
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


func _set_hand(gm, seat: int, syms: Array) -> void:
	var p = gm.players[seat]
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))


func _take(gm, seat: int, syms: Array) -> Array:
	var out: Array = []
	var p = gm.players[seat]
	for s in syms:
		for i in range(p.hand.size()):
			if p.hand[i].symbol == s:
				out.append(p.hand[i])
				break
	return out


# 从卡片列表里解出 {symbol: valence}
func _pairs(syms: Array) -> Dictionary:
	return CompoundSolverScript.get_valence_pairs(_cards(syms))


func _formula(syms: Array) -> String:
	var cards := _cards(syms)
	var cv := CompoundSolverScript.get_valence_pairs(cards)
	if cv.is_empty():
		return ""
	var fi = CompoundSolverScript.get_compound_formula(cards, cv)
	if fi.is_empty() or not bool(fi.get("ratio_ok", false)):
		return ""
	return str(fi.get("formula", ""))


func _run():
	_test_carbon_data()
	_test_carbon_oxides()
	_test_metal_domains()
	_test_low_valence_metals()
	_test_v3_not_regressed()
	_test_determinism()
	_finish()


# ============================================================
# 一、C 的化合价数据
# ============================================================
func _test_carbon_data() -> void:
	var raw: Array = []
	for e in CardDatabaseScript.get_element_data():
		if e[0] == "C":
			raw = e[9]
	var card = _card("C")
	_check(raw == [4, 2, -4], "牌库数据 C = [4, 2, -4]（实际 %s）" % str(raw))
	_check(card.common_valence == [4, 2, -4], "CardData 实例同步为 [4, 2, -4]（实际 %s）"
		% str(card.common_valence))
	_check(card.common_valence.has(2), "C 拥有 +2（CO 的先决条件）")
	_check(card.common_valence.has(-4), "C 仍保留 -4（CH₄ 等仍需它做负价）")


# ============================================================
# 二、碳的氧化物
# ============================================================
func _test_carbon_oxides() -> void:
	var co := _pairs(["C", "O"])
	_check(int(co.get("C", 0)) == 2 and int(co.get("O", 0)) == -2,
		"C + O 解出 C(+2)/O(-2)（实际 %s）" % str(co))
	_check(_formula(["C", "O"]) == "CO", "C + O 化学式 = CO（实际 %s）" % _formula(["C", "O"]))

	var co2 := _pairs(["C", "O", "O"])
	_check(int(co2.get("C", 0)) == 4, "C + 2O 仍取 C(+4)（实际 %s）" % str(co2))
	_check(_formula(["C", "O", "O"]).begins_with("CO"),
		"C + 2O 化学式以 CO 开头（实际 %s）" % _formula(["C", "O", "O"]))

	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["C", "O", "Ar"])
	var r = gm.play_cards(0, _take(gm, 0, ["C", "O"]), {"C": 2, "O": -2}, COMPOUND)
	_check(r == 0, "引擎接受 CO（C +2 / O -2）（实际 %d）" % r)
	_check(gm.get_table_pattern() == COMPOUND, "CO 上桌牌型 = 化合物")


# ============================================================
# 三、金属 / 准金属价域：全部正价，降序
# ============================================================
func _domains_of(sym: String) -> Array:
	var elems = CompoundSolverScript._valence_domains(_cards([sym]))
	if elems.is_empty():
		return []
	return elems[0]["values"]


func _test_metal_domains() -> void:
	_check(_domains_of("Fe") == [3, 2], "Fe 价域 [3, 2]（实际 %s）" % str(_domains_of("Fe")))
	_check(_domains_of("Cu") == [2, 1], "Cu 价域 [2, 1]（实际 %s）" % str(_domains_of("Cu")))
	_check(_domains_of("Cr") == [6, 3, 2], "Cr 价域 [6, 3, 2]（实际 %s）" % str(_domains_of("Cr")))
	_check(_domains_of("Mn") == [7, 4, 2], "Mn 价域 [7, 4, 2]（实际 %s）" % str(_domains_of("Mn")))
	_check(_domains_of("Zn") == [2], "Zn 价域 [2]（单价的金属不受影响）")
	_check(_domains_of("B") == [3], "B（准金属）价域 [3]")
	_check(_domains_of("Cl") == [-1, 1, 3, 5, 7],
		"非金属 Cl 价域保持数据顺序 [-1, 1, 3, 5, 7]（实际 %s）" % str(_domains_of("Cl")))
	_check(_domains_of("S") == [-2, 4, 6],
		"非金属 S 价域保持数据顺序 [-2, 4, 6]（实际 %s）" % str(_domains_of("S")))

	# 全表体检：金属 / 准金属的价域只能有正价
	var bad: Array = []
	for e in CardDatabaseScript.get_element_data():
		if e[6] != CardDataScript.TYPE_METAL and e[6] != CardDataScript.TYPE_METALLOID:
			continue
		for v in _domains_of(e[0]):
			if int(v) <= 0:
				bad.append("%s:%d" % [e[0], int(v)])
	_check(bad.is_empty(), "所有金属 / 准金属价域均为正价（异常：%s）" % str(bad))


# ============================================================
# 四、低价金属化合物（v3 时代完全搜不出来）
# ============================================================
func _test_low_valence_metals() -> void:
	var feo := _pairs(["Fe", "O"])
	_check(int(feo.get("Fe", 0)) == 2, "Fe + O 解出 Fe(+2)（实际 %s）" % str(feo))
	_check(_formula(["Fe", "O"]) == "FeO", "Fe + O 化学式 = FeO（实际 %s）" % _formula(["Fe", "O"]))

	var fe2o3 := _pairs(["Fe", "Fe", "O", "O", "O"])
	_check(int(fe2o3.get("Fe", 0)) == 3, "2Fe + 3O 优先取 Fe(+3)（实际 %s）" % str(fe2o3))
	_check(_formula(["Fe", "Fe", "O", "O", "O"]) == "Fe" + CompoundSolverScript._to_subscript(2)
		+ "O" + CompoundSolverScript._to_subscript(3),
		"2Fe + 3O 化学式 = Fe₂O₃（实际 %s）" % _formula(["Fe", "Fe", "O", "O", "O"]))

	var fecl2 := _pairs(["Fe", "Cl", "Cl"])
	_check(int(fecl2.get("Fe", 0)) == 2 and int(fecl2.get("Cl", 0)) == -1,
		"Fe + 2Cl 自动解出 Fe(+2)/Cl(-1)（v3 时代返回空，实际 %s）" % str(fecl2))

	var cuo := _pairs(["Cu", "O"])
	_check(int(cuo.get("Cu", 0)) == 2, "Cu + O 优先取 Cu(+2)（实际 %s）" % str(cuo))
	var cu2o := _pairs(["Cu", "Cu", "O"])
	_check(int(cu2o.get("Cu", 0)) == 1, "2Cu + O 解出 Cu(+1)（实际 %s）" % str(cu2o))

	var mno2 := _pairs(["Mn", "O", "O"])
	_check(int(mno2.get("Mn", 0)) == 4, "Mn + 2O 解出 Mn(+4)（实际 %s）" % str(mno2))
	var cr2o3 := _pairs(["Cr", "Cr", "O", "O", "O"])
	_check(int(cr2o3.get("Cr", 0)) == 3, "2Cr + 3O 解出 Cr(+3)（实际 %s）" % str(cr2o3))

	# 引擎：低价金属化合物可以直接打出
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["Fe", "Cl", "Cl", "Ar"])
	var r = gm.play_cards(0, _take(gm, 0, ["Fe", "Cl", "Cl"]), fecl2, COMPOUND)
	_check(r == 0, "引擎接受 FeCl₂（Fe +2 / 2Cl -1）（实际 %d）" % r)

	# 电荷不平的显式价仍被拒
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	_set_hand(gm2, 0, ["Fe", "Cl", "Cl", "Ar"])
	var r2 = gm2.play_cards(0, _take(gm2, 0, ["Fe", "Cl", "Cl"]), {"Fe": 3, "Cl": -1}, COMPOUND)
	_check(r2 == -1, "Fe(+3)+2Cl(-1) 电荷不平 → 仍被拒 -1（实际 %d）" % r2)


# ============================================================
# 五、v3 的裁决不倒退
# ============================================================
func _test_v3_not_regressed() -> void:
	_check(_pairs(["N", "Cl"]).is_empty(), "N + Cl 仍无解（假化合物）")
	_check(_pairs(["Br", "N"]).is_empty(), "Br + N 仍无解")
	_check(_pairs(["I", "N"]).is_empty(), "I + N 仍无解")

	var ncl3 := _pairs(["N", "Cl", "Cl", "Cl"])
	_check(int(ncl3.get("N", 0)) == 3 and int(ncl3.get("Cl", 0)) == -1,
		"NCl₃ 仍是 N(+3)/Cl(-1)（实际 %s）" % str(ncl3))
	var bcl3 := _pairs(["B", "Cl", "Cl", "Cl"])
	_check(int(bcl3.get("B", 0)) == 3, "BCl₃ 仍是 B(+3)（实际 %s）" % str(bcl3))
	var clf := _pairs(["Cl", "F"])
	_check(int(clf.get("Cl", 0)) == 1 and int(clf.get("F", 0)) == -1,
		"ClF 仍是 Cl(+1)/F(-1)（实际 %s）" % str(clf))
	var nacl := _pairs(["Na", "Cl"])
	_check(int(nacl.get("Na", 0)) == 1 and int(nacl.get("Cl", 0)) == -1,
		"NaCl 仍是 Na(+1)/Cl(-1)（实际 %s）" % str(nacl))
	_check(_formula(["Al", "Al", "O", "O", "O"]) == "Al" + CompoundSolverScript._to_subscript(2)
		+ "O" + CompoundSolverScript._to_subscript(3),
		"Al₂O₃ 仍是 Al(+3)（实际 %s）" % _formula(["Al", "Al", "O", "O", "O"]))


# ============================================================
# 六、可复现性（AI / 提示 / 面板 / 联机回放共用同一解）
# ============================================================
func _test_determinism() -> void:
	var ref_fecl2 := str(_pairs(["Fe", "Cl", "Cl"]))
	var ref_co := str(_pairs(["C", "O"]))
	var ref_mn := str(_pairs(["Mn", "O", "O"]))
	var same := true
	for _i in range(30):
		if str(_pairs(["Fe", "Cl", "Cl"])) != ref_fecl2:
			same = false
		if str(_pairs(["C", "O"])) != ref_co:
			same = false
		if str(_pairs(["Mn", "O", "O"])) != ref_mn:
			same = false
	_check(same, "同一组牌连续求解 30 次结果完全一致（%s / %s / %s）"
		% [ref_fecl2, ref_co, ref_mn])

