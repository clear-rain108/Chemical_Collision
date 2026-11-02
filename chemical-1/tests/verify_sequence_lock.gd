# 验证「顺序牌锁定」语义：约束只作用于被指定的那名玩家
#   1) 顺序牌先把方向反转，再指定「反转后的下一名」（4 人局 P0 → P3）
#   2) 只有 target 受约束：其他人出什么牌都不受限，也不替它解约束
#   3) 别人打族炸 / 出牌 / 接炸链结束 都不解除约束
#   4) target 打出指定牌型 → 完成；target 跳过 → 罚抽 2 张
#   5) 手牌达上限的 target：弃 1 张 + 罚抽 2 张
#   6) 新顺序牌覆盖旧约束；AI 自动放弃指定权时清空 target
#   7) 快照 / 可用牌型提示 都带上 target
# 运行：Godot --headless --path . -s tests/verify_sequence_lock.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const PlayerManagerScript = preload("res://scripts/PlayerManager.gd")
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
		print("ALL SEQUENCE LOCK TESTS PASSED")
	else:
		print("%d SEQUENCE LOCK TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


func _set_hand(gm, idx: int, syms: Array) -> void:
	var p = gm.players[idx]
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))


# 4 人局：P0 出顺序牌 C+N+O（返回 1 = 成功，等 UI 指定牌型）
# 注意：手牌必须多于 3 张，否则出完即获胜，play_cards 返回 0
func _open_sequence(gm) -> int:
	_set_hand(gm, 0, ["Fe", "C", "N", "O"])
	gm.current_player_index = 0
	gm.is_round_starter = true
	var cards = gm.players[0].hand.slice(1, 4)
	return gm.play_cards(0, cards, {}, CardPatternsScript.CardPattern.SEQUENCE)


# 标准场景：P0 出顺序 → 指定「化合物」→ 返回 target 座位
func _lock_compound(gm) -> int:
	var r = _open_sequence(gm)
	if r != 1:
		push_error("open_sequence failed: %d" % r)
		return -999
	gm.set_sequence_constraint(CardPatternsScript.CardPattern.COMPOUND)
	return gm.sequence_constraint_target


# ============================================================
# 一、顺序牌：方向反转 + target 落在反转后的下一名
# ============================================================
func _test_direction_and_target() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	var r = _open_sequence(gm)
	_check(r == 1, "P0 打出顺序牌成功并请求指定牌型（实际 %d）" % r)
	_check(not gm.direction_clockwise, "方向已反转（顺时针 → 逆时针）")
	_check(not gm.sequence_constraint_active, "顺序牌本身不预设约束，等 UI 指定")

	gm.set_sequence_constraint(CardPatternsScript.CardPattern.COMPOUND)
	_check(gm.sequence_constraint_active, "指定后约束激活")
	_check(gm.sequence_constraint_target == 3,
		"target = 反转后的下一名 = P3（实际 %d）" % gm.sequence_constraint_target)
	_check(gm.current_player_index == 3,
		"牌权交给 P3（实际 %d）" % gm.current_player_index)

	# 3 人局同样成立
	var gm3 = GameManagerScript.new()
	gm3.init_game(3, 2)
	_set_hand(gm3, 0, ["Fe", "C", "N", "O"])
	gm3.current_player_index = 0
	gm3.is_round_starter = true
	gm3.play_cards(0, gm3.players[0].hand.slice(1, 4), {},
		CardPatternsScript.CardPattern.SEQUENCE)
	gm3.set_sequence_constraint(CardPatternsScript.CardPattern.ELEMENT)
	_check(gm3.sequence_constraint_target == 2,
		"3 人局：target = 反转后的下一名 = P2（实际 %d）" % gm3.sequence_constraint_target)


# ============================================================
# 二、只有 target 受约束
# ============================================================
func _test_only_target_bound() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	var target = _lock_compound(gm)
	_check(target == 3, "布置：target = P3")

	# target 出单质（不是化合物）→ -6
	_set_hand(gm, 3, ["Fe"])
	var r1 = gm.play_cards(3, [gm.players[3].hand[0]])
	_check(r1 == -6, "target 出单质被拦（期望 -6，实际 %d）" % r1)
	_check(gm.players[3].get_hand_count() == 1, "被拦后 target 手牌不变")

	# 非 target 出单质 → 不受约束
	_set_hand(gm, 1, ["Fe"])
	var r2 = gm.play_cards(1, [gm.players[1].hand[0]])
	_check(r2 == 0, "非 target P1 出单质不受约束（实际 %d）" % r2)
	_check(gm.sequence_constraint_active, "别人出牌后约束仍在")
	_check(gm.sequence_constraint_target == 3, "别人出牌后 target 不变")


# ============================================================
# 三、族炸 / 接炸链不解除约束
# ============================================================
func _test_bomb_and_others_do_not_clear() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_lock_compound(gm)

	# P1 打出族炸（Na + K 同族）→ 成功，但约束不该被清
	_set_hand(gm, 1, ["Na", "K"])
	var r = gm.play_cards(1, gm.players[1].hand.duplicate())
	_check(r == 0, "P1 打出族炸成功（实际 %d）" % r)
	_check(gm.get_table_pattern() == CardPatternsScript.CardPattern.CLAN_BOMB, "桌面是族炸")
	_check(gm.sequence_constraint_active, "族炸没有解除顺序约束")
	_check(gm.sequence_constraint_target == 3, "族炸后 target 仍是 P3")
	_check(gm.players[1].clan_bomb_cooling, "P1 进入族炸冷却")

	# 接炸链 + 顺序约束同时存在：目标的提示必须说「顺序约束」，
	# 其他人才看到「仅可出更大的族炸」（play_cards 里约束检查也优先于接炸链）
	_check(str(gm.get_available_patterns(3)).contains("顺序约束"),
		"接炸链中 target 的提示是「顺序约束」（实际 %s）" % gm.get_available_patterns(3))
	_check(str(gm.get_available_patterns(2)).contains("更大的族炸"),
		"接炸链中非 target 的提示仍是「更大的族炸」（实际 %s）" % gm.get_available_patterns(2))

	# 族炸接炸链结束后（_finish_clan_bomb_chain）约束同样保留
	gm._finish_clan_bomb_chain()
	_check(gm.sequence_constraint_active, "接炸链结束后约束仍保留")
	_check(gm.sequence_constraint_target == 3, "接炸链结束后 target 仍是 P3")


# ============================================================
# 三之二、target 用族炸满足「族炸」约束
# ============================================================
func _test_bomb_constraint() -> void:
	# 约束 = 族炸，target 自己打出族炸 → 约束完成
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_open_sequence(gm)
	gm.set_sequence_constraint(CardPatternsScript.CardPattern.CLAN_BOMB)
	_check(gm.sequence_constraint_target == 3, "布置：约束 P3 必须出族炸")
	_set_hand(gm, 3, ["Na", "K"])
	var r = gm.play_cards(3, gm.players[3].hand.duplicate())
	_check(r == 0, "target 打出族炸满足「族炸」约束（实际 %d）" % r)
	_check(not gm.sequence_constraint_active, "族炸满足约束后自动解除")
	_check(gm.sequence_constraint_target == -1, "族炸满足约束后 target 清空")

	# 约束 = 化合物，target 打族炸 → -6，约束保留
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	_lock_compound(gm2)
	_set_hand(gm2, 3, ["Na", "K"])
	var r2 = gm2.play_cards(3, gm2.players[3].hand.duplicate())
	_check(r2 == -6, "约束为化合物时 target 打族炸被拒（实际 %d）" % r2)
	_check(gm2.sequence_constraint_active, "被拒后约束仍保留")
	_check(gm2.sequence_constraint_target == 3, "被拒后 target 仍是 P3")


# ============================================================
# 四、target 完成 / 跳过罚抽 / 非 target 跳过
# ============================================================
func _test_target_completes_and_penalty() -> void:
	# (a) target 打出指定牌型 → 约束完成
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_lock_compound(gm)
	_set_hand(gm, 3, ["Na", "Cl"])
	var r = gm.play_cards(3, gm.players[3].hand.duplicate(), {"Na": 1, "Cl": -1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r == 0, "target 打出指定牌型（化合物）成功（实际 %d）" % r)
	_check(not gm.sequence_constraint_active, "target 完成后约束结束")
	_check(gm.sequence_constraint_target == -1, "target 完成后 target 清空")

	# (b) target 跳过 → 罚抽 2 张 + 约束结束
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	_lock_compound(gm2)
	var before = gm2.players[3].get_hand_count()
	gm2.player_pass(3)
	_check(gm2.players[3].get_hand_count() == before + 2,
		"target 跳过罚抽 2 张（%d → %d）" % [before, gm2.players[3].get_hand_count()])
	_check(not gm2.sequence_constraint_active, "target 跳过罚抽后约束结束")
	_check(gm2.sequence_constraint_target == -1, "target 跳过罚抽后 target 清空")

	# (c) 非 target 跳过 → 只抽 1 张，约束保留
	var gm3 = GameManagerScript.new()
	gm3.init_game(4, 3)
	_lock_compound(gm3)
	var before1 = gm3.players[1].get_hand_count()
	gm3.player_pass(1)
	_check(gm3.players[1].get_hand_count() == before1 + 1,
		"非 target 跳过只抽 1 张（%d → %d）" % [before1, gm3.players[1].get_hand_count()])
	_check(gm3.sequence_constraint_active, "非 target 跳过不解除约束")
	_check(gm3.sequence_constraint_target == 3, "非 target 跳过不改 target")


# ============================================================
# 五、手牌达上限的 target：弃 1 张 + 罚抽 2 张
# ============================================================
func _test_discard_and_pass() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_lock_compound(gm)
	var limit: int = PlayerManagerScript.get_hand_limit(4)
	var syms: Array = []
	for _i in range(limit):
		syms.append("H")
	_set_hand(gm, 3, syms)
	gm.player_discard_and_pass(3, gm.players[3].hand[0])
	_check(gm.players[3].get_hand_count() == limit - 1 + 2,
		"弃 1 张 + 罚抽 2 张 → 手牌 %d（上限 %d）" % [gm.players[3].get_hand_count(), limit])
	_check(not gm.sequence_constraint_active, "弃牌跳过后约束结束")
	_check(gm.sequence_constraint_target == -1, "弃牌跳过后 target 清空")


# ============================================================
# 六、新顺序覆盖旧约束 + AI 放弃指定权
# ============================================================
func _test_overwrite_and_ai() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_lock_compound(gm)
	_set_hand(gm, 2, ["Fe", "C", "N", "O"])
	var r = gm.play_cards(2, gm.players[2].hand.slice(1, 4), {},
		CardPatternsScript.CardPattern.SEQUENCE)
	_check(r == 1, "P2 打出顺序牌（实际 %d）" % r)
	_check(not gm.sequence_constraint_active, "新顺序牌作废旧约束")
	_check(gm.sequence_constraint_target == -1, "新顺序牌清空旧 target")

	# AI 在「接顺序」场景打出顺序后会自动放弃指定权，不应留下垃圾 target
	var gm2 = GameManagerScript.new()
	gm2.init_game(4, 3)
	_set_hand(gm2, 0, ["Fe", "C", "N", "O"])
	gm2.current_player_index = 0
	gm2.is_round_starter = true
	gm2.play_cards(0, gm2.players[0].hand.slice(1, 4), {},
		CardPatternsScript.CardPattern.SEQUENCE)
	_set_hand(gm2, 1, ["Fe", "C", "N", "O"])
	gm2.current_player_index = 1
	gm2.is_round_starter = false
	AIPlayerScript.auto_play(gm2, Callable())
	_check(not gm2.sequence_constraint_active, "AI 自动放弃指定权：约束不激活")
	_check(gm2.sequence_constraint_target == -1, "AI 自动放弃后 target = -1")


# ============================================================
# 七、快照 / 可用牌型提示
# ============================================================
func _test_snapshot_and_info() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_lock_compound(gm)
	var snap: Dictionary = gm.to_snapshot()
	_check(snap.has("sequence_constraint_target"), "快照含 sequence_constraint_target 字段")
	_check(int(snap.get("sequence_constraint_target", -2)) == 3,
		"快照里 target = 3（实际 %d）" % int(snap.get("sequence_constraint_target", -2)))
	_check(str(gm.get_available_patterns(3)).contains("顺序约束"),
		"target 的可用牌型提示含「顺序约束」（实际 %s）" % gm.get_available_patterns(3))
	_check(not str(gm.get_available_patterns(1)).contains("顺序约束"),
		"非 target 的可用牌型提示不含「顺序约束」（实际 %s）" % gm.get_available_patterns(1))


func _run() -> void:
	_test_direction_and_target()
	_test_only_target_bound()
	_test_bomb_and_others_do_not_clear()
	_test_bomb_constraint()
	_test_target_completes_and_penalty()
	_test_discard_and_pass()
	_test_overwrite_and_ai()
	_test_snapshot_and_info()
	_finish()


