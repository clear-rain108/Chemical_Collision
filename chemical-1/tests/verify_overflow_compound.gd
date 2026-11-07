# 验证「溢出化合物」判定口径（B′）：按「一个分子的原子数」而不是「出了几张牌」
#   1) 2Na+2Br = 4 张牌，但每个 NaBr 只有 2 个原子 → 不免疫族炸
#   2) 4Na+4Cl = 8 张牌，同样是 NaCl 小分子 → 不免疫族炸
#   3) P₂O₅ / Fe₃O₄ / H₂O₂ 单分子 ≥4 个原子 → 免疫族炸
#   4) 溢出免疫生效后，族炸确实被引擎拒绝（-4）
# 运行：Godot --headless --path . -s tests/verify_overflow_compound.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")

var fails: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
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


# ---- 全新 GM（4 人局）+ 指定当前玩家手牌 ----
func _gm_with_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	var p = gm.get_current_player()
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))
	return gm


# 用当前手牌打化合物，返回 [结果码, 单分子原子数]
func _play_compound(gm, syms: Array) -> Array:
	var p = gm.get_current_player()
	var hand_before: int = p.get_hand_count()
	var code: int = gm.play_cards(gm.get_current_player_index(), p.hand.duplicate(), {},
		CardPatternsScript.CardPattern.COMPOUND)
	return [code, hand_before, CompoundSolverScript.get_formula_atom_count(_cards(syms))]


func _run() -> void:
	# ---- 1) 小分子叠着打：牌数 4，但单分子只有 2 个原子 ----
	var g1 = _gm_with_hand(["Na", "Na", "Br", "Br"])
	var r1: Array = _play_compound(g1, ["Na", "Na", "Br", "Br"])
	_check(int(r1[0]) == 0, "2Na+2Br 可以正常打出（实际 %d）" % int(r1[0]))
	_check(int(r1[2]) == 2, "2Na+2Br 单分子 2 个原子（实际 %d）" % int(r1[2]))
	_check(not g1.compound_immune, "2Na+2Br（4 张）不免疫族炸")

	# ---- 2) 8 张 NaCl 也一样：牌多 ≠ 分子大 ----
	var g2 = _gm_with_hand(["Na", "Na", "Na", "Na", "Cl", "Cl", "Cl", "Cl"])
	var r2: Array = _play_compound(g2, ["Na", "Na", "Na", "Na", "Cl", "Cl", "Cl", "Cl"])
	_check(int(r2[0]) == 0, "4Na+4Cl 可以正常打出（实际 %d）" % int(r2[0]))
	_check(int(r2[2]) == 2, "4Na+4Cl 单分子 2 个原子（实际 %d）" % int(r2[2]))
	_check(not g2.compound_immune, "4Na+4Cl（8 张）不免疫族炸")

	# ---- 3) 真正的多原子分子才免疫 ----
	var g3 = _gm_with_hand(["P", "P", "O", "O", "O", "O", "O"])
	var r3: Array = _play_compound(g3, ["P", "P", "O", "O", "O", "O", "O"])
	_check(int(r3[0]) == 0, "P₂O₅ 可以正常打出（实际 %d）" % int(r3[0]))
	_check(int(r3[2]) == 7, "P₂O₅ 单分子 7 个原子（实际 %d）" % int(r3[2]))
	_check(g3.compound_immune, "P₂O₅（7 个原子）免疫族炸")

	var g4 = _gm_with_hand(["Fe", "Fe", "Fe", "O", "O", "O", "O"])
	var r4: Array = _play_compound(g4, ["Fe", "Fe", "Fe", "O", "O", "O", "O"])
	_check(int(r4[0]) == 0, "Fe₃O₄ 可以正常打出（实际 %d）" % int(r4[0]))
	_check(int(r4[2]) == 7, "Fe₃O₄ 单分子 7 个原子（实际 %d）" % int(r4[2]))
	_check(g4.compound_immune, "Fe₃O₄（7 个原子）免疫族炸")

	# ---- 4) H₂O₂：4 张牌但单分子 4 个原子（过氧根不能按 gcd 约成 HO）----
	var g5 = _gm_with_hand(["H", "H", "O", "O"])
	var r5: Array = _play_compound(g5, ["H", "H", "O", "O"])
	_check(int(r5[0]) == 0, "H₂O₂ 可以正常打出（实际 %d）" % int(r5[0]))
	_check(int(r5[2]) == 4, "H₂O₂ 单分子 4 个原子（实际 %d）" % int(r5[2]))
	_check(g5.compound_immune, "H₂O₂（4 个原子 = 4 人局）免疫族炸")

	# ---- 5) 免疫生效后族炸被拒 ----
	var g6 = _gm_with_hand(["F", "Cl", "Br", "I"])
	g6.compound_immune = true
	var p6 = g6.get_current_player()
	var bomb_code: int = g6.play_cards(g6.get_current_player_index(), p6.hand.duplicate(), {},
		CardPatternsScript.CardPattern.CLAN_BOMB)
	_check(bomb_code == -4, "溢出免疫时族炸被拒（实际 %d）" % bomb_code)
	_check(g6.get_current_player().get_hand_count() == 4, "被拒后手牌不变（实际 %d）"
		% g6.get_current_player().get_hand_count())

	if fails == 0:
		print("ALL OVERFLOW COMPOUND TESTS PASSED")
	else:
		print("%d OVERFLOW COMPOUND TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)
