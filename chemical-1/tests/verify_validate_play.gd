# 验证只读判定 `GameManager.validate_play()`（P13 拆分的另一半）
#   1) 返回码与 play_cards 完全一致（0 合法 / 1 合法但需选指定牌型 / 负数非法）
#   2) 只读：判定前后手牌、桌面、日志、轮转、state_hash 全部不变
#   3) 幂等：同一局面连续判定两次返回码一致
#   4) `last_evaluated_pattern` 是牌型的唯一真相（同一批牌可被判成族炸或化合物）
#   5) 覆盖 -1 / -2 / -3 / -4 / -6 / -7 / -8 七条拒绝路径 + 顺序（1）+ 有机物（0）
# 运行：Godot --headless --path . -s tests/verify_validate_play.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const COMPOUND = CardPatternsScript.CardPattern.COMPOUND
const CLAN_BOMB = CardPatternsScript.CardPattern.CLAN_BOMB
const ORGANIC = CardPatternsScript.CardPattern.ORGANIC
const SEQUENCE = CardPatternsScript.CardPattern.SEQUENCE

# 固定种子：两个「完全相同」的局面才好互相对照（只判定 vs 真出牌）
const SEED := 424242

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


# ---- 造牌 / 造手牌（与牌库同源）----
func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


func _set_hand(gm, seat: int, syms: Array) -> void:
	var p = gm.players[seat]
	p.hand.clear()
	var n := 0
	for s in syms:
		var c = _card(s)
		c.uid = seat * 100 + n   # uid 唯一：联机事件寻址用
		p.hand.append(c)
		n += 1
	p.sort_hand_by_atomic_number()


func _take(gm, seat: int, syms: Array) -> Array:
	var out: Array = []
	var p = gm.players[seat]
	for s in syms:
		for c in p.hand:
			if c.symbol == s and c not in out:
				out.append(c)
				break
	return out


func _new_gm():
	var gm = GameManagerScript.new()
	gm.init_game(4, 3, SEED)
	return gm


# ---- 局面搭建（每个 case 都从同一个种子重来一遍）----
# 空桌首出：0 号位就是首出玩家
func _setup_fresh(gm) -> void:
	_set_hand(gm, 0, ["Na", "Cl", "Ar", "H"])


# 空桌首出 + 手里有卤素（卤族互化关闭 → F + Cl 化合非法）
func _setup_fresh_halogen(gm) -> void:
	_set_hand(gm, 0, ["F", "Cl", "Ar", "Na"])


# 桌面已有一张单质 Al（13），轮到 1 号位
func _setup_after_element(gm) -> void:
	_set_hand(gm, 0, ["Al", "Ar"])
	gm.play_cards(0, _take(gm, 0, ["Al"]))
	_set_hand(gm, 1, ["Si", "C", "Cl", "Cl"])


# 桌面已有化合物 NaCl，轮到 1 号位
func _setup_after_compound(gm) -> void:
	_set_hand(gm, 0, ["Na", "Cl", "Ar"])
	gm.play_cards(0, _take(gm, 0, ["Na", "Cl"]), {"Na": 1, "Cl": -1}, COMPOUND)
	_set_hand(gm, 1, ["Si", "C", "O", "O"])


# 0 号位处于族炸冷却
func _setup_cooling(gm) -> void:
	_set_hand(gm, 0, ["F", "Cl", "Ar", "H"])
	gm.players[0].clan_bomb_cooling = true


# 1 号位被顺序牌指定「必须出化合物」
func _setup_constraint(gm) -> void:
	_set_hand(gm, 0, ["Ar", "H"])
	gm.play_cards(0, _take(gm, 0, ["Ar"]))
	_set_hand(gm, 1, ["Si", "C", "O", "O"])
	gm.sequence_constraint = COMPOUND
	gm.sequence_constraint_active = true
	gm.sequence_constraint_target = 1


# 元素限制开启（只允许前 20 号 → Fe 越界）
func _setup_element_limit(gm) -> void:
	gm.element_limit_enabled = true
	gm.allowed_extra_elements = []
	_set_hand(gm, 0, ["Fe", "O", "Ar"])


# 26/27/28 连续 → 顺序（同时是 VIII 族族炸）
func _setup_sequence(gm) -> void:
	_set_hand(gm, 0, ["Fe", "Co", "Ni", "Ar"])


# 有机物：C + 4H = 甲烷（5 张，≤ 手牌 8 张）
func _setup_organic(gm) -> void:
	_set_hand(gm, 0, ["C", "H", "H", "H", "H", "Ar"])


# ---- 一个 case：先只读判定，再在同样的局面上真出牌，逐项对照 ----
func _run_case(why: String, expect: int, setup: Callable, seat: int, play_syms: Array,
		cv: Dictionary = {}, intended: int = -1, expect_reason: bool = false) -> void:
	var a = _new_gm()
	setup.call(a)
	var cards_a := _take(a, seat, play_syms)
	if cards_a.size() != play_syms.size():
		_check(false, "%s：setup 没准备齐手牌（期望 %s）" % [why, str(play_syms)])
		return

	var hash_before: int = a.state_hash()
	var logs_before: int = a.log_messages.size()
	var hand_before: int = a.players[seat].get_hand_count()
	var table_before: int = a.table_cards.size()

	var vcode: int = a.validate_play(seat, cards_a, cv, intended)
	var vpat: int = a.last_evaluated_pattern
	var reason: String = a.last_reject_reason

	var readonly: bool = a.state_hash() == hash_before \
		and a.log_messages.size() == logs_before \
		and a.players[seat].get_hand_count() == hand_before \
		and a.table_cards.size() == table_before
	var vcode2: int = a.validate_play(seat, cards_a, cv, intended)

	_check(vcode == expect, "%s：validate_play = %d（期望 %d）" % [why, vcode, expect])
	_check(readonly, "%s：判定只读（手牌 / 桌面 / 日志 / 指纹都没变）" % why)
	_check(vcode2 == vcode, "%s：连续两次判定一致（幂等）" % why)
	if expect_reason:
		_check(reason != "", "%s：拒绝原因已写入 last_reject_reason（%s）" % [why, reason])

	# 同样的局面上真出一次，返回码必须相同
	var b = _new_gm()
	setup.call(b)
	var cards_b := _take(b, seat, play_syms)
	var pcode: int = b.play_cards(seat, cards_b, cv, intended)
	_check(pcode == vcode, "%s：play_cards 与 validate_play 返回码一致（%d / %d）" % [why, pcode, vcode])
	_check(vpat == b.last_evaluated_pattern,
		"%s：last_evaluated_pattern 一致（%d / %d）" % [why, vpat, b.last_evaluated_pattern])


func _run() -> void:
	# ---- 合法 ----
	_run_case("空桌出单张 Ar", 0, Callable(self, "_setup_fresh"), 0, ["Ar"])
	_run_case("空桌出化合物 NaCl", 0, Callable(self, "_setup_fresh"), 0, ["Na", "Cl"],
		{"Na": 1, "Cl": -1}, COMPOUND)
	_run_case("接桌面单质：C(6) 压过 Al(13)", 0, Callable(self, "_setup_after_element"), 1, ["C"])
	_run_case("顺序牌（26/27/28）→ 需要选指定牌型", 1, Callable(self, "_setup_sequence"), 0,
		["Fe", "Co", "Ni"], {}, SEQUENCE)
	_run_case("有机物 CH₄（打出即获胜）", 0, Callable(self, "_setup_organic"), 0,
		["C", "H", "H", "H", "H"], {"_organic": true}, ORGANIC)

	# ---- 非法 ----
	_run_case("空牌组", -1, Callable(self, "_setup_fresh"), 0, [])
	_run_case("假化合物 N + Cl", -1, Callable(self, "_setup_fresh"), 0, ["Na", "Cl"],
		{"N": -3, "Cl": -1}, COMPOUND)
	_run_case("接桌面单质：Si(14) 更大 → 压不过", -2, Callable(self, "_setup_after_element"), 1,
		["Si"], {}, -1, true)
	_run_case("桌面化合物，出单质", -4, Callable(self, "_setup_after_compound"), 1, ["Si"])
	_run_case("族炸冷却中", -3, Callable(self, "_setup_cooling"), 0, ["F", "Cl"])
	_run_case("顺序约束要求化合物，却出单质", -6, Callable(self, "_setup_constraint"), 1, ["Si"])
	_run_case("卤族互化关闭时 F + Cl 化合", -7, Callable(self, "_setup_fresh_halogen"), 0,
		["F", "Cl"], {"F": -1, "Cl": 1}, COMPOUND)
	_run_case("元素限制：Fe 不在允许集", -8, Callable(self, "_setup_element_limit"), 0, ["Fe", "O"],
		{"Fe": 2, "O": -2}, COMPOUND)

	# ---- 座位越界 / 牌型二义性 / 混合价态 ----
	var gm = _new_gm()
	_set_hand(gm, 0, ["Na", "Cl"])
	_check(gm.validate_play(99, _take(gm, 0, ["Na"])) == -1, "越界座位 → -1")
	_check(gm.validate_play(-1, []) == -1, "座位 -1 / 空牌 → -1")

	# N + P 既是 VA 族炸、又能配成 PN：判定真相只在引擎（last_evaluated_pattern）
	var gm2 = _new_gm()
	_set_hand(gm2, 0, ["N", "P", "Ar"])
	var np := _take(gm2, 0, ["N", "P"])
	_check(gm2.validate_play(0, np) == 0, "N + P 未给价态 → 可出（族炸）")
	_check(gm2.last_evaluated_pattern == CLAN_BOMB,
		"未给价态时牌型 = 族炸（实际 %d）" % gm2.last_evaluated_pattern)
	_check(gm2.validate_play(0, np, {"P": 3, "N": -3}, COMPOUND) == 0, "N + P 给价态 → 可出（化合物 PN）")
	_check(gm2.last_evaluated_pattern == COMPOUND,
		"给价态时牌型 = 化合物（实际 %d）" % gm2.last_evaluated_pattern)

	# 混合价态也能只读判定（Fe₃O₄）
	var gm3 = _new_gm()
	_set_hand(gm3, 0, ["Fe", "Fe", "Fe", "O", "O", "O", "O", "Ar"])
	var fe3o4 := _take(gm3, 0, ["Fe", "Fe", "Fe", "O", "O", "O", "O"])
	var hash3: int = gm3.state_hash()
	_check(gm3.validate_play(0, fe3o4, {"Fe": [3, 3, 2], "O": -2}, COMPOUND) == 0,
		"Fe₃O₄（混合价态）只读判定 = 0")
	_check(gm3.state_hash() == hash3, "Fe₃O₄ 判定后指纹不变")
	_check(gm3.players[0].get_hand_count() == 8, "Fe₃O₄ 判定后手牌还是 8 张（没被吃掉）")
	_check(gm3.validate_play(0, fe3o4, {"Fe": 3, "O": -2}, COMPOUND) == -1,
		"Fe₃O₄ 用统一 +3 判定 = -1（电荷不平）")

	if fails == 0:
		print("ALL VALIDATE PLAY TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d VALIDATE PLAY TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)

