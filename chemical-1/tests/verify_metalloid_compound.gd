# 验证「准金属配平丢元素」修复（P15-E）
#   现场 Bug：手牌 [Si, H, H, Cl, Cl] 以化合物打出后，桌面化学式显示成「2HCl」
#   —— Si 凭空消失，5 张牌被当成 2 个原子的 HCl，而且 ratio_ok=true 直接放行。
#
#   根因：CompoundSolver._assign_valences 的默认分支只把 TYPE_METAL 认作正价元素，
#   准金属（B 最高正价 +3 / Si +4）既不进 pos 也不进 neg，被静默丢弃；
#   而同一文件的 _valence_domains 用的是 METAL or METALLOID，两条路径口径不一致。
#
#   1) 准金属化合物能配出正确化学式：SiH₂Cl₂ / BCl₃ / SiCl₄ / SiO₂ / SiH₄ / BH₃
#   2) 元素守恒：化学式里的元素集合必须等于输入牌面的元素集合
#      （一次防住整类「某元素消失」）
#   3) 电荷对不上的组合仍然拒绝（B + 3O 不是 B₂O₃ 的合法原料比例）
#   4) 引擎层：COMPOUND 打出 BCl₃ / SiO₂ / SiH₂Cl₂ 成功，桌面化学式与牌面一致
#   5) 日志用引擎认定的价态重算：过氧根写 H₂O₂，不再写成 2HO₂
# 运行：Godot --headless --path . -s tests/verify_metalloid_compound.gd
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
		print("ALL METALLOID COMPOUND TESTS PASSED")
	else:
		print("%d METALLOID COMPOUND TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源，保证原子序数 / 化合价一致）----
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


# 从手牌取真实实例（play_cards → remove_cards 按对象身份匹配）
func _take(gm, seat: int, syms: Array) -> Array:
	var out: Array = []
	var p = gm.players[seat]
	for s in syms:
		for i in range(p.hand.size()):
			if p.hand[i].symbol == s:
				out.append(p.hand[i])
				break
	return out


func _gm_with_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, syms)
	return gm


# 配平结果里出现的元素（pos + neg），排序后便于和牌面比对
func _elements(fi: Dictionary) -> Array:
	var got: Array = []
	for e in fi.get("pos_list", []):
		if not got.has(str(e.symbol)):
			got.append(str(e.symbol))
	for e in fi.get("neg_list", []):
		if not got.has(str(e.symbol)):
			got.append(str(e.symbol))
	got.sort()
	return got


func _want_elements(syms: Array) -> Array:
	var want: Array = []
	for s in syms:
		if not want.has(s):
			want.append(s)
	want.sort()
	return want


func _run():
	_test_metalloid_formulas()
	_test_element_conservation()
	_test_charge_mismatch_rejected()
	_test_engine_plays_metalloid()
	_test_log_uses_engine_valences()
	_finish()


# ============================================================
# 一、准金属化合物的化学式
# ============================================================
func _test_metalloid_formulas() -> void:
	var cases := [
		{"syms": ["Si", "H", "H", "Cl", "Cl"], "formula": "SiH₂Cl₂"},
		{"syms": ["B", "Cl", "Cl", "Cl"], "formula": "BCl₃"},
		{"syms": ["Si", "Cl", "Cl", "Cl", "Cl"], "formula": "SiCl₄"},
		{"syms": ["Si", "O", "O"], "formula": "SiO₂"},
		{"syms": ["Si", "H", "H", "H", "H"], "formula": "SiH₄"},
		{"syms": ["B", "H", "H", "H"], "formula": "BH₃"},
	]
	for c in cases:
		var syms: Array = c["syms"]
		var tag: String = ",".join(syms)
		var fi: Dictionary = CompoundSolverScript.get_compound_formula(_cards(syms), {})
		var got := str(fi.get("formula", "<空>"))
		_check(got == c["formula"], "%s → %s（实际：%s）" % [tag, c["formula"], got])
		_check(bool(fi.get("ratio_ok", false)), "%s 电荷配平（ratio_ok=true）" % tag)
		_check(int(fi.get("coefficient", 0)) == 1, "%s 系数为 1（单分子）" % tag)

	# 修复前的具体症状：Si 被丢掉后只剩 H + Cl，硬凑出一个 HCl
	var broken: Dictionary = CompoundSolverScript.get_compound_formula(_cards(["Si", "H", "H", "Cl", "Cl"]), {})
	_check(not str(broken.get("formula", "")).contains("HCl"),
		"SiH₂Cl₂ 不允许退化成 HCl（元素不能被静默丢弃）")
	var atoms := CompoundSolverScript.get_formula_atom_count(_cards(["Si", "H", "H", "Cl", "Cl"]))
	_check(atoms == 5, "SiH₂Cl₂ 单分子 5 个原子（修复前误算成 2，实际 %d）" % atoms)


# ============================================================
# 二、元素守恒（整类回归的护栏）
# ============================================================
func _test_element_conservation() -> void:
	# 金属基团是既有能力，放进来一起守住
	var cases := [
		["Na", "Cl"],
		["Ca", "Cl", "Cl"],
		["Al", "Cl", "Cl", "Cl"],
		["Si", "H", "H", "Cl", "Cl"],
		["B", "Cl", "Cl", "Cl"],
		["Si", "Cl", "Cl", "Cl", "Cl"],
		["Si", "O", "O"],
		["Si", "H", "H", "H", "H"],
		["B", "H", "H", "H"],
	]
	for syms in cases:
		var tag: String = ",".join(syms)
		var fi: Dictionary = CompoundSolverScript.get_compound_formula(_cards(syms), {})
		_check(not fi.is_empty(), "%s 能配出化学式" % tag)
		if fi.is_empty():
			continue
		var got := _elements(fi)
		var want := _want_elements(syms)
		_check(got == want,
			"%s 元素守恒：期望 %s，实际 %s（少一个元素 = 化学式在骗人）" % [tag, str(want), str(got)])


# ============================================================
# 三、电荷不配平的组合仍然拒绝
# ============================================================
func _test_charge_mismatch_rejected() -> void:
	var bad := [
		{"syms": ["B", "O", "O", "O"], "why": "B(+3) vs 3×O(-2) = 6"},
		{"syms": ["Si", "H"], "why": "Si(+4) vs H(-1)"},
		{"syms": ["B", "Cl"], "why": "B(+3) vs Cl(-1)"},
		{"syms": ["Si", "Cl"], "why": "Si(+4) vs Cl(-1)"},
	]
	for b in bad:
		var syms: Array = b["syms"]
		var fi: Dictionary = CompoundSolverScript.get_compound_formula(_cards(syms), {})
		_check(not bool(fi.get("ratio_ok", false)),
			"%s 电荷不配平必须拒绝（%s）" % [",".join(syms), b["why"]])


# ============================================================
# 四、引擎层：准金属化合物真的能打出去
# ============================================================
func _test_engine_plays_metalloid() -> void:
	var cases := [
		{"syms": ["B", "Cl", "Cl", "Cl"], "formula": "BCl₃"},
		{"syms": ["Si", "O", "O"], "formula": "SiO₂"},
		{"syms": ["Si", "H", "H", "Cl", "Cl"], "formula": "SiH₂Cl₂"},
	]
	for c in cases:
		var syms: Array = c["syms"]
		var tag: String = ",".join(syms)
		var gm = _gm_with_hand(syms)
		var r: int = gm.play_cards(0, _take(gm, 0, syms), {}, COMPOUND)
		_check(r == 0, "%s 能以化合物打出（期望 0，实际 %d：%s）" % [
			tag, r, gm.get_last_reject_reason()])
		if r != 0:
			continue
		var on_table: Dictionary = CompoundSolverScript.get_compound_formula(
			gm.table_cards, gm.table_custom_valences)
		_check(str(on_table.get("formula", "")) == c["formula"],
			"%s 桌面化学式 %s（实际：%s）" % [tag, c["formula"], str(on_table.get("formula", "<空>"))])
		var atoms := CompoundSolverScript.get_formula_atom_count(gm.table_cards)
		_check(atoms == syms.size(),
			"%s 单分子原子数 = 牌数（%d 张，实际 %d 个原子）" % [tag, syms.size(), atoms])


# ============================================================
# 五、日志与桌面同源：过氧根写 H₂O₂
# ============================================================
func _test_log_uses_engine_valences() -> void:
	var syms := ["H", "H", "O", "O"]
	var gm = _gm_with_hand(syms)
	var r: int = gm.play_cards(0, _take(gm, 0, syms), {}, COMPOUND)
	_check(r == 0, "H₂O₂ 能打出（期望 0，实际 %d：%s）" % [r, gm.get_last_reject_reason()])
	if r != 0:
		return
	# 引擎自己搜出来的价态（H +1 / O -1）才配得出 H₂O₂，玩家传参是空的
	_check(not gm.table_custom_valences.is_empty(),
		"桌面记录了引擎搜出的价态（实际：%s）" % str(gm.table_custom_valences))
	var last := ""
	for m in gm.logger.log_messages:
		if str(m).contains("打出了"):
			last = str(m)
	_check(last.contains("H₂O₂"),
		"日志化学式与桌面同源（期望含 H₂O₂，实际：%s）" % last)
	_check(not last.contains("2HO₂"),
		"日志不能再用玩家传参重算出 2HO₂（实际：%s）" % last)
	var on_table: Dictionary = CompoundSolverScript.get_compound_formula(
		gm.table_cards, gm.table_custom_valences)
	_check(str(on_table.get("formula", "")) == "H₂O₂",
		"桌面与日志化学式一致（桌面：%s）" % str(on_table.get("formula", "<空>")))


