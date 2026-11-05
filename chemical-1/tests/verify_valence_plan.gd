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


func _finish() -> void:
	if fails == 0:
		print("ALL VALENCE PLAN TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d VALENCE PLAN TESTS FAILED" % [fails, total])
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
	var n := 0
	for s in syms:
		var c = _card(s)
		# 联机事件靠 uid 寻址：同一手牌里不能重复（apply_event 会拒重复 uid）
		c.uid = seat * 100 + n
		p.hand.append(c)
		n += 1


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
	# ---- 第二部分：混合价态 / 特殊命名 / 联机兼容 ----
	_test_plan_normalization()
	_test_mixed_valence_fe3o4()
	_test_mixed_illegal_forms()
	_test_uniform_preferred()
	_test_special_names()
	_test_net_compat()
	_test_mixed_performance()
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


# ============================================================
# 七、化合价表达式的规范化（统一价 / 混合价两种写法）
# ============================================================
func _test_plan_normalization() -> void:
	var S = CompoundSolverScript
	_check(S._valence_plan_of(3, 3) == [3, 3, 3], "int 写法 → 每张一个价 [3,3,3]")
	_check(S._valence_plan_of([2, 3, 3], 3) == [3, 3, 2],
		"数组写法降序规范化（[2,3,3] → [3,3,2]）")
	_check(S._valence_plan_of([-2, -2], 2) == [-2, -2], "负价数组保持不变")
	_check(S._valence_plan_of([3, 3], 3) == [], "长度 ≠ 张数 → 非法（少给一张）")
	_check(S._valence_plan_of([3, 3, 2, 2], 3) == [], "长度 ≠ 张数 → 非法（多给一张）")
	_check(S._valence_plan_of([3, -3], 2) == [], "同元素跨正负 → 非法")
	_check(S._valence_plan_of([3, 0, 2], 3) == [], "含 0 价 → 非法")
	_check(S._valence_plan_of(0, 2) == [], "单价 0 → 非法")
	_check(S._valence_plan_of(3, 0) == [], "张数 0 → 非法")
	_check(S._plan_is_mixed([3, 3, 2]), "Fe₃O₄ 的 Fe 计划被判为混合")
	_check(not S._plan_is_mixed([3, 3]), "同价计划不算混合")
	_check(not S._plan_is_mixed([2]), "单张不算混合")


# ============================================================
# 八、混合价态：Fe₃O₄（本作第一个必须混合才成立的化合物）
# ============================================================
func _test_mixed_valence_fe3o4() -> void:
	var S = CompoundSolverScript
	var syms := ["Fe", "Fe", "Fe", "O", "O", "O", "O"]
	var cards := _cards(syms)

	var uniform := S.get_uniform_valence_pairs(cards)
	_check(uniform.is_empty(), "Fe₃O₄ 无统一价态解（3 张 Fe 同价必是 3 的倍数，配不平 -8）")

	var cv := S.get_mixed_valence_pairs(cards)
	_check(cv.get("Fe", null) is Array and cv.get("Fe", []) == [3, 3, 2],
		"混合价态解 Fe = [+3, +3, +2]（实际 %s）" % str(cv))
	_check(int(cv.get("O", 0)) == -2, "O 仍是单一 -2（混合只发生在真需要的元素上）")
	_check(S.get_valence_pairs(cards) == cv, "统一无解时 get_valence_pairs 回落到混合解")

	var fi = S.get_compound_formula(cards, cv)
	_check(not fi.is_empty() and bool(fi.get("ratio_ok", false)), "Fe₃O₄ 电荷配平通过")
	_check(int(fi.get("total_positive", 0)) == 8 and int(fi.get("total_negative", 0)) == 8,
		"正负电荷各 8（实际 %s / %s）" % [str(fi.get("total_positive")), str(fi.get("total_negative"))])
	_check(str(fi.get("formula_key", "")) == "Fe3O4",
		"formula_key = Fe3O4（实际 %s）" % str(fi.get("formula_key")))
	_check(bool(fi.get("mixed", false)), "结果标记 mixed = true")

	var fe_name := S.get_compound_name(cards, cv)
	_check(fe_name == "四氧化三铁", "命名 = 四氧化三铁（实际 %s）" % fe_name)

	_check(S.is_compound(cards), "Fe₃O₄ 的牌组被判为化合物")
	_check(CardPatternsScript.detect_pattern(cards) == COMPOUND, "牌型检测 = 化合物")

	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, syms + ["Ar"])
	var picked := _take(gm, 0, syms)
	var r = gm.play_cards(0, picked, cv, COMPOUND)
	_check(r == 0, "引擎接受 Fe₃O₄（混合价态）（实际 %d）" % r)
	_check(gm.get_table_custom_valences().get("Fe", null) is Array,
		"桌面记录的化合价保留混合数组（桌面小卡 / 重连快照要用它）")
	_check(gm.get_table_pattern() == COMPOUND, "桌面牌型记为化合物（不是族炸 / 顺序）")


# ============================================================
# 九、混合价态的非法写法（一律 {}，引擎必须拒绝）
# ============================================================
func _test_mixed_illegal_forms() -> void:
	var syms := ["Fe", "Fe", "Fe", "O", "O", "O", "O"]
	var cases := [
		{"cv": {"Fe": [3, 3], "O": -2}, "why": "Fe 少给一张价（长度 2 ≠ 3）"},
		{"cv": {"Fe": [3, 3, 3, 2], "O": -2}, "why": "Fe 多给一张价（长度 4 ≠ 3）"},
		{"cv": {"Fe": [3, -3, 2], "O": -2}, "why": "同一元素跨正负"},
		{"cv": {"Fe": [3, 3, 0], "O": -2}, "why": "价态写成 0"},
		{"cv": {"Fe": [3, 3, 3], "O": -2}, "why": "全 +3 → 电荷 9 vs 8 不平"},
		{"cv": {"Fe": 3, "O": -2}, "why": "统一 +3 配 Fe₃O₄ 电荷不平"},
	]
	var ok := true
	var reasons: Array = []
	for c in cases:
		var gm = GameManagerScript.new()
		gm.init_game(4, 3)
		_set_hand(gm, 0, syms)
		var r = gm.play_cards(0, _take(gm, 0, syms), c["cv"], COMPOUND)
		if r != -1:
			ok = false
			reasons.append("%s → %d" % [c["why"], r])
	_check(ok, "6 种非法混合价写法全部被拒 -1%s" % ("" if ok else "（%s）" % str(reasons)))

	# 价态表里多给了本手牌没有的元素：忽略而不是整体作废（面板 / 提示的宽容度）
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	_set_hand(gm2, 0, syms)
	var r2 = gm2.play_cards(0, _take(gm2, 0, syms),
		{"Fe": [3, 3, 2], "O": -2, "Cu": 2}, COMPOUND)
	_check(r2 == 0, "价态表里多出的无关元素被忽略（实际 %d）" % r2)


# ============================================================
# 十、统一解优先（混合搜索不许抢戏），v3 不倒退
# ============================================================
func _test_uniform_preferred() -> void:
	var S = CompoundSolverScript
	var fe2o3 := S.get_valence_pairs(_cards(["Fe", "Fe", "O", "O", "O"]))
	_check(int(fe2o3.get("Fe", 0)) == 3 and not (fe2o3.get("Fe") is Array),
		"Fe₂O₃ 仍是单一 Fe(+3)（实际 %s）" % str(fe2o3))

	# 混合搜索本身也不会把「本来能统一的」拆成数组
	var mixed_fe2o3 := S.get_mixed_valence_pairs(_cards(["Fe", "Fe", "O", "O", "O"]))
	_check(int(mixed_fe2o3.get("Fe", 0)) == 3 and not (mixed_fe2o3.get("Fe") is Array),
		"混合搜索对 Fe₂O₃ 同样给出单一 +3（实际 %s）" % str(mixed_fe2o3))

	var cu2o := S.get_valence_pairs(_cards(["Cu", "Cu", "O"]))
	_check(int(cu2o.get("Cu", 0)) == 1, "Cu₂O 仍是 Cu(+1)（实际 %s）" % str(cu2o))
	_check(S.get_mixed_valence_pairs(_cards(["Na", "Cl"])).is_empty()
		or not (S.get_mixed_valence_pairs(_cards(["Na", "Cl"])).get("Na") is Array),
		"NaCl 这种单价组合不会被混合搜索改写")
	_check(S.get_mixed_valence_pairs(_cards(["N", "Cl"])).is_empty(), "NCl 混合搜索同样无解（假化合物不复活）")
	_check(S.is_compound(_cards(["Fe", "Fe", "O", "O", "O"])), "Fe₂O₃ 仍是化合物")


# ============================================================
# 十一、特殊命名表（只影响显示）
# ============================================================
func _name_with(syms: Array, cv: Dictionary) -> String:
	return CompoundSolverScript.get_compound_name(_cards(syms), cv)


func _test_special_names() -> void:
	var S = CompoundSolverScript
	_check(S.SPECIAL_NAMES.size() <= 30, "特殊命名表 ≤ 30 条（实际 %d 条）" % S.SPECIAL_NAMES.size())

	# key 必须与 formula_key 同口径：纯 ASCII、不带下标
	var bad_keys: Array = []
	for k in S.SPECIAL_NAMES:
		for ch in String(k):
			if ch in "₀₁₂₃₄₅₆₇₈₉":
				bad_keys.append(k)
				break
	_check(bad_keys.is_empty(), "表里 key 一律是无下标化学式（异常：%s）" % str(bad_keys))

	var cases := [
		{"syms": ["H", "H", "O"], "cv": {}, "name": "水"},
		{"syms": ["C", "O"], "cv": {"C": 2, "O": -2}, "name": "一氧化碳"},
		{"syms": ["C", "O", "O"], "cv": {}, "name": "二氧化碳"},
		{"syms": ["N", "H", "H", "H"], "cv": {}, "name": "氨"},
		{"syms": ["Na", "H"], "cv": {}, "name": "氢化钠"},
		{"syms": ["Ca", "H", "H"], "cv": {}, "name": "氢化钙"},
		{"syms": ["Fe", "O"], "cv": {"Fe": 2, "O": -2}, "name": "氧化亚铁"},
		{"syms": ["Fe", "Fe", "O", "O", "O"], "cv": {}, "name": "三氧化二铁"},
		{"syms": ["Cu", "O"], "cv": {}, "name": "氧化铜"},
		{"syms": ["Cu", "Cu", "O"], "cv": {"Cu": 1, "O": -2}, "name": "氧化亚铜"},
		{"syms": ["Mn", "O", "O"], "cv": {"Mn": 4, "O": -2}, "name": "二氧化锰"},
		{"syms": ["Cr", "Cr", "O", "O", "O"], "cv": {"Cr": 3, "O": -2}, "name": "三氧化二铬"},
		{"syms": ["Al", "Al", "O", "O", "O"], "cv": {}, "name": "三氧化二铝"},
		{"syms": ["Si", "O", "O"], "cv": {"Si": 4, "O": -2}, "name": "二氧化硅"},
		{"syms": ["S", "O", "O"], "cv": {"S": 4, "O": -2}, "name": "二氧化硫"},
		{"syms": ["S", "O", "O", "O"], "cv": {}, "name": "三氧化硫"},
	]
	var wrong: Array = []
	for c in cases:
		var got := _name_with(c["syms"], c["cv"])
		if got != c["name"]:
			wrong.append("%s → %s（期望 %s）" % [str(c["syms"]), got, c["name"]])
	_check(wrong.is_empty(), "%d 条特殊命名全部命中%s" % [cases.size(),
		"" if wrong.is_empty() else "（异常：%s）" % str(wrong)])

	# 表里没有的组合仍然走原命名逻辑（不能因为查表而丢失已有名字）
	_check(_name_with(["Na", "Cl"], {}) == "氯化钠", "NaCl 仍走默认命名（氯化钠）")
	_check(_name_with(["H", "H", "S"], {}) == "硫化氢",
		"H₂S 仍走默认命名（%s）" % _name_with(["H", "H", "S"], {}))
	var h2so4 := _name_with(["H", "H", "S", "O", "O", "O", "O"], {})
	_check(h2so4 != "", "表外的组合仍有名字（H₂SO₄ → %s，不会因为查表变空）" % h2so4)

	# 混合价态但表里没收录 → 不编假名字（返回空串，显示层只放化学式）
	var long_mixed := {"Fe": [3, 3, 2, 2], "O": -2}
	var no_name := CompoundSolverScript.get_compound_name(
		_cards(["Fe", "Fe", "Fe", "Fe", "O", "O", "O", "O", "O"]), long_mixed)
	_check(no_name == "", "未收录的混合价态不编造中文名（实际 %s）" % no_name)


# ============================================================
# 十二、联机 / 快照兼容（事件里带数组，重放必须一致）
# ============================================================
func _test_net_compat() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)

	# 1) JSON 往返：网络传输后数组元素是 float
	var wire = JSON.parse_string(JSON.stringify({"Fe": [3, 3, 2], "O": -2}))
	var cv: Dictionary = gm._valences_from(wire)
	_check(cv.get("Fe", null) is Array and cv.get("Fe", []) == [3, 3, 2],
		"JSON 往返后仍是 [3,3,2]（实际 %s）" % str(cv.get("Fe")))
	_check(typeof(cv.get("Fe", [])[0]) == TYPE_INT, "JSON 里的 float 被转回 int（重放要用整数算电荷）")
	_check(int(cv.get("O", 0)) == -2, "单一价在 JSON 往返后仍是 int -2")
	var rev: Dictionary = gm._valences_from({"Fe": [2, 3, 3], "O": -2})
	_check(rev.get("Fe", []) == [3, 3, 2], "输入顺序不同也规范化成同一数组（%s）" % str(rev.get("Fe")))

	# 2) 指纹口径：表示规范化，[3,2] 与 [2,3] 必须同哈希
	var a: Array = gm._sorted_pairs({"Fe": [3, 2], "O": -2})
	var b: Array = gm._sorted_pairs({"Fe": [2, 3], "O": -2})
	_check(a == b, "指纹里 [3,2] 与 [2,3] 视为同一状态（%s）" % str(a))
	_check(a != gm._sorted_pairs({"Fe": 3, "O": -2}),
		"int 与数组是不同价态表达，指纹不同（避免重连误判一致）")
	_check(gm._valence_key_of(true) == "true", "bool 值（_organic 标记）指纹格式不变")

	# 3) 事件重放：主机 / 客人各自解析同一笔带数组的事件 → 状态完全一致
	# （同一个 seed 才有同一副牌库；手牌在下面用固定 uid 覆盖，两端完全一致）
	var syms := ["Fe", "Fe", "Fe", "O", "O", "O", "O"]
	var host = GameManagerScript.new()
	var client = GameManagerScript.new()
	host.init_game(4, 3, 20260101)
	client.init_game(4, 3, 20260101)
	var seat: int = host.get_current_player_index()
	_set_hand(host, seat, syms)
	_set_hand(client, seat, syms)
	var uids: Array = []
	for c in host.players[seat].hand:
		uids.append(int(c.uid))
	var ev := {
		"type": "play", "by": seat, "uids": uids,
		"valences": {"Fe": [3, 3, 2], "O": -2}, "pattern": COMPOUND,
	}
	var rh: int = host.apply_event(ev)
	var rc: int = client.apply_event(ev)
	_check(rh == 0 and rc == 0, "混合价态事件在主机 / 客人上都被接受（%d / %d）" % [rh, rc])
	_check(host.state_hash() == client.state_hash(),
		"主机 / 客人 state_hash 一致（%d）" % host.state_hash())
	_check(JSON.stringify(host.to_snapshot()) == JSON.stringify(client.to_snapshot()),
		"双方快照 JSON 文本完全一致（重连可用）")

	# 4) 走网络通道（JSON 往返）后重放同一笔事件也必须成功
	var wire_ev = JSON.parse_string(JSON.stringify(ev))
	var host2 = GameManagerScript.new()
	host2.init_game(4, 3, 20260101)
	_set_hand(host2, seat, syms)
	var r2: int = host2.apply_event(wire_ev)
	_check(r2 == 0, "手写 JSON 事件（数组元素为 float）重放成功（%d）" % r2)



# ============================================================
# 十三、混合搜索的确定性与开销（联机不能卡帧）
# ============================================================
func _test_mixed_performance() -> void:
	var S = CompoundSolverScript
	var cards := _cards(["Fe", "Fe", "Fe", "O", "O", "O", "O"])
	var ref := str(S.get_mixed_valence_pairs(cards))
	var same := true
	for _i in range(100):
		if str(S.get_mixed_valence_pairs(cards)) != ref:
			same = false
	_check(same, "Fe₃O₄ 混合解连续求解 100 次完全一致（%s）" % ref)

	var t0 := Time.get_ticks_usec()
	for _i in range(20):
		S.get_valence_pairs(cards)
	var avg_ms := float(Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	_check(avg_ms < 50.0, "单次求解平均 %.2f ms（< 50ms，联机不卡帧）" % avg_ms)

	# 组合数超上限时直接放弃（宁可判非法，也不做指数爆炸）
	var hog := _cards(["Cl", "Cl", "Br", "Br", "Br", "I", "I", "I"])
	var t1 := Time.get_ticks_usec()
	var hog_cv := S.get_mixed_valence_pairs(hog)
	var hog_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	_check(hog_cv.is_empty(), "超过 MIXED_NODE_CAP 的组合直接返回无解（%s）" % str(hog_cv))
	_check(hog_ms < 50.0, "超限组合在 %.2f ms 内放弃（没有进入指数枚举）" % hog_ms)




