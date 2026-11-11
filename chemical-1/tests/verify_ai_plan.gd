# 验证 AIPlayer 只读计划层（P11-C1-c Step 2 / 决策 D3）
#   覆盖：plan() 只读性、计划合法性、
#         「单机落子（play_cards）」与「主机 apply_event 重放」逐步同指纹（联机不分叉的前提）、
#         三种动作的覆盖、边界返回值、_execute_local 的 sequence_skip 分支。
#
# 为什么 B 段要拿 apply_event 对拍而不是拿 auto_play 自身对拍：
#   auto_play 如今就是 plan() + _execute_local()，自己跟自己比是循环论证。
#   真正要证明的是「主机代 AI 走 apply_event 广播」与「单机直调 play_cards」
#   落在同一个局面上 —— 这两条路径共用 _evaluate_play，但落子顺序不同，
#   一旦哪边多点/少点副作用（抽牌、轮转、日志），state_hash 立刻分出来。
#
# 运行：godot --headless --path . --script tests/verify_ai_plan.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const AIPlayerScript = preload("res://scripts/AIPlayer.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const TURNS := 20
const SEEDS := [20261111, 777, 424242]
const SEQ_SCAN_MAX := 300

var fails: int = 0
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _finish() -> void:
	if fails == 0:
		print("ALL AI PLAN TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d AI PLAN TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


# 4 人 3 AI：座位 0 是人（脚本代打 pass），座位 1/2/3 是 AI
func _make_gm(seed: int):
	var gm = GameManagerScript.new()
	gm.init_game(4, 3, seed)
	return gm


func _uids(hand: Array) -> Array:
	var out: Array = []
	for c in hand:
		out.append(int(c.uid))
	return out


# 计划 → 主机侧事件（去掉 plan 里多的键不影响：make_intent 就是平铺）
func _to_event(seat: int, p: Dictionary) -> Dictionary:
	var ev: Dictionary = {"type": String(p.get("type", "")), "by": seat}
	for k in p:
		if String(k) != "type":
			ev[k] = p[k]
	return ev


func _run() -> void:
	_run_readonly()
	_run_equivalence()
	_run_coverage()
	_run_edges()
	_run_execute_local()
	_finish()


# ============================================================
# A 只读性：plan() 一个字节都不许改局面
# ============================================================
func _run_readonly() -> void:
	for s in SEEDS:
		var gm = _make_gm(int(s))
		for seat in [1, 2, 3]:
			var hash0: int = int(gm.state_hash())
			var ev0: int = int(gm.event_log.size())
			var log0: int = int(gm.log_messages.size())
			var hand0: Array = _uids(gm.players[seat].hand)
			var p: Dictionary = AIPlayerScript.plan(gm, seat)
			_check(not p.is_empty(), "A seed=%d 座位 %d plan() 给出计划（%s）"
				% [int(s), seat, String(p.get("type", "?"))])
			_check(int(gm.state_hash()) == hash0, "A seed=%d 座位 %d plan() 不改 state_hash" % [int(s), seat])
			_check(gm.event_log.size() == ev0, "A seed=%d 座位 %d plan() 不写 event_log" % [int(s), seat])
			_check(gm.log_messages.size() == log0, "A seed=%d 座位 %d plan() 不写 log_messages" % [int(s), seat])
			_check(_uids(gm.players[seat].hand) == hand0, "A seed=%d 座位 %d plan() 不动手牌" % [int(s), seat])


# ============================================================
# B 等价性：单机落子 vs 主机 apply_event 重放，逐步同指纹
# ============================================================
func _run_equivalence() -> void:
	for s in SEEDS:
		var a = _make_gm(int(s))     # 单机路径：auto_play → play_cards / player_pass
		var b = _make_gm(int(s))     # 联机路径：plan → apply_event（主机广播的那一笔）
		_check(int(a.state_hash()) == int(b.state_hash()), "B seed=%d 同 seed 开局指纹一致" % int(s))
		var steps := 0
		var same := true
		while steps < TURNS and not a.is_game_over():
			var seat_a: int = int(a.current_player_index)
			var seat_b: int = int(b.current_player_index)
			if seat_a != seat_b:
				same = false
				break
			if seat_a == 0:
				# 人类座位：两端各按自己的语义跳过（单机 player_pass / 联机 pass 事件）
				a.player_pass(0)
				b.apply_event({"type": "pass", "by": 0})
			else:
				var pa: Dictionary = AIPlayerScript.plan(a, seat_a)
				var pb: Dictionary = AIPlayerScript.plan(b, seat_b)
				if pa.is_empty() or str(pa) != str(pb):
					same = false
					break
				# 计划合法性：play 必须被引擎放行（用落子前的同一手牌复核）
				if String(pa.get("type", "")) == "play":
					var cards: Array = AIPlayerScript._cards_by_uids(b.players[seat_b].hand,
						pa.get("uids", []))
					var cv = pa.get("valences", {})
					var code: int = int(b.validate_play(seat_b, cards,
						cv if cv is Dictionary else {}, int(pa.get("pattern", -1))))
					_check(code >= 0, "C seed=%d 第 %d 手 play 计划复核放行（code=%d）"
						% [int(s), steps, code])
				AIPlayerScript.auto_play(a, Callable())
				b.apply_event(_to_event(seat_b, pb))
			steps += 1
			_check(int(a.state_hash()) == int(b.state_hash()),
				"B seed=%d 第 %d 手 单机落子 ≡ apply_event 重放（seat %d）" % [int(s), steps, seat_a])
		_check(same, "B seed=%d 两端 AI 计划逐步一致（跑了 %d 手）" % [int(s), steps])
		_check(steps >= TURNS or a.is_game_over(), "B seed=%d 跑满 %d 手或正常结束（实际 %d 手）"
			% [int(s), TURNS, steps])
		_check(b.event_log.size() == steps, "B seed=%d 重放侧事件数 = 手数（%d）" % [int(s), steps])
		_check(a.event_log.is_empty(), "B seed=%d 单机侧 event_log 保持为空" % int(s))


# ============================================================
# D 覆盖面 / E 边界 / F 单机落子辅助
# ============================================================
func _run_coverage() -> void:
	# D1 开局桌面空 → 出牌
	var gm = _make_gm(20261111)
	var p1: Dictionary = AIPlayerScript.plan(gm, 1)
	_check(String(p1.get("type", "")) == "play", "D1 开局（桌面空）→ 计划出牌")

	# D2 接炸链 + 本座位冷却 → 规则上只能跳过
	gm.clan_bomb_chain_active = true
	gm.players[1].clan_bomb_cooling = true
	var p2: Dictionary = AIPlayerScript.plan(gm, 1)
	_check(String(p2.get("type", "")) == "pass", "D2 接炸链 + 族炸冷却 → 计划跳过")
	gm.clan_bomb_chain_active = false
	gm.players[1].clan_bomb_cooling = false

	# D3 第0关：手牌只剩 1 张就收手（永不清空 → 玩家必胜）
	var gm3 = _make_gm(20261111)
	gm3.tutorial_level = 0
	gm3.tutorial_level0_phase = 1
	gm3.players[1].hand.resize(1)
	var p3: Dictionary = AIPlayerScript.plan(gm3, 1)
	_check(String(p3.get("type", "")) == "pass", "D3 第0关 AI 手牌 ≤1 → 计划跳过")

	# D4 桌面是顺序牌 + 手牌有 3 连 → 计划出顺序（pattern 明确写死）
	var st: Dictionary = _find_sequence_state()
	var ok4 := false
	if not st.is_empty():
		var gm4 = st["gm"]
		var p4: Dictionary = AIPlayerScript.plan(gm4, int(st["seat"]))
		ok4 = String(p4.get("type", "")) == "play" \
			and int(p4.get("pattern", -1)) == CardPatternsScript.CardPattern.SEQUENCE
		if ok4:
			_check(true, "D4 桌面顺序 + 手牌 3 连 → 计划出顺序牌（pattern=SEQUENCE）")
		else:
			_check(false, "D4 顺序局面下的计划不是顺序牌（%s）" % str(p4))
	else:
		_check(false, "D4 未能在 %d 个 seed 内构造出顺序局面" % SEQ_SCAN_MAX)

	# D5 AI 自己不碰两阶段：「放弃指定」的结算权在落子方 / 主机收窗处
	_check(not _plans_have_sequence_skip(), "D5 20 手内 AI 计划从未返回 sequence_skip")

	# D6 手牌空 → {}（与改造前一致：不是 pass，什么都不做）
	var gm6 = _make_gm(20261111)
	gm6.players[1].hand.clear()
	_check(AIPlayerScript.plan(gm6, 1).is_empty(), "D6 手牌空 → 空计划（与改造前一致）")


func _run_edges() -> void:
	_check(AIPlayerScript.plan(null).is_empty(), "E1 plan(null) → {}")
	var gm = _make_gm(20261111)
	_check(AIPlayerScript.plan(gm, 0).is_empty(), "E2 人类座位 → {}（AI 只替 AI 决策）")
	_check(AIPlayerScript.plan(gm, 99).is_empty(), "E3 座位越界 → {}")
	gm.phase = 2
	gm.winner_index = 0
	_check(AIPlayerScript.plan(gm, 1).is_empty(), "E4 对局已结束 → {}")


func _run_execute_local() -> void:
	# sequence_skip：单机侧唯一会用到它的场景是「AI 出顺序后的收窗」，
	# 语义必须与 GameManager.apply_event("sequence_skip") 完全一致。
	var gm = _make_gm(20261111)
	gm.current_player_index = 1
	gm.sequence_constraint_active = true
	gm.sequence_constraint = CardPatternsScript.CardPattern.ELEMENT
	gm.sequence_constraint_target = 1
	_check(int(AIPlayerScript._execute_local(gm, {"type": "sequence_skip"})) == 0,
		"F1 _execute_local(sequence_skip) 返回 0")
	_check(not gm.sequence_constraint_active and gm.sequence_constraint == -1
			and gm.sequence_constraint_target == -1,
		"F2 _execute_local(sequence_skip) 清空三项约束")
	_check(int(gm.current_player_index) != 1, "F3 _execute_local(sequence_skip) 牌权流转")
	_check(int(AIPlayerScript._execute_local(null, {})) == -1, "F4 _execute_local(null) → -1")
	var gm2 = _make_gm(20261111)
	_check(int(AIPlayerScript._execute_local(gm2, {"type": "play", "uids": []})) == -1,
		"F5 空 uids 的 play → -1（不猜牌）")


# ---- 工具：找一个「桌面是顺序牌、AI 手牌有 3 连」的种子 ----
func _find_sequence_state() -> Dictionary:
	for seed in range(1, SEQ_SCAN_MAX + 1):
		var gm = _make_gm(seed)
		var seat := 1
		if AIPlayerScript._find_sequence(gm.players[seat].hand).size() < 3:
			continue
		gm.is_round_starter = false
		gm.table_cards = [gm.players[seat].hand[0]].duplicate()
		gm.table_pattern = CardPatternsScript.CardPattern.SEQUENCE
		gm.table_player_index = 0
		gm.table_custom_valences = {}
		gm.current_player_index = seat
		return {"gm": gm, "seat": seat}
	return {}


# ---- 工具：跑 20 手，确认 AI 计划里从不出现 sequence_skip ----
func _plans_have_sequence_skip() -> bool:
	var gm = _make_gm(20261111)
	var steps := 0
	while steps < TURNS and not gm.is_game_over():
		var seat: int = int(gm.current_player_index)
		if seat == 0:
			gm.player_pass(0)
		else:
			var p: Dictionary = AIPlayerScript.plan(gm, seat)
			if p.is_empty():
				return false
			if String(p.get("type", "")) == "sequence_skip":
				return true
			AIPlayerScript.auto_play(gm, Callable())
		steps += 1
	return false
