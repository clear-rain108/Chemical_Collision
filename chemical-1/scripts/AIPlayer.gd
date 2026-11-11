# ============================================================
# AIPlayer.gd - AI 出牌决策模块
# 职责：AI 自动出牌策略（族炸 / 化合物 / 双原子 / 单质 / 跳过）
# 从 GameUI 拆出的独立模块；只依赖 game_manager 的公开接口
# ============================================================
extends RefCounted

const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")

# L4a：AI 是否尝试「按最简比一次出多个分子」的化合物（2Na+2Br → 2NaBr）。
# 关掉就退回「只用 2 张牌对」的老策略（对局节奏更慢，但更容易复现旧局）。
const AI_RATIO_COMPOUND := true

# ============================================================
# 一、主入口：先出只读计划，再落子（P11-C1-c Step 2 / 决策 D3）
# ============================================================
# plan() 只读：绝不改手牌 / 桌面 / 轮转 / 日志 / rng，只返回「一笔意图」。
# 返回字段与 NetProtocol.make_intent 的 payload 对齐，主机可直接拿去广播重放：
#   {"type": "play", "uids": [...], "valences": {...}, "pattern": -1}
#   {"type": "pass"}
#   {"type": "sequence_skip"} / {"type": "sequence_pick", "pattern": n}
#   {}  = 无法决定（无对局 / 座位非法 / 不是 AI / 已结束）
# 为什么不直接落子：主机要把 AI 的动作变成可广播的意图，
# 「直接落子」在联机里等于「主机自己改局面」，客人重放不出来 → 立刻分叉。
# 判定一律走 validate_play()：它与 play_cards() 共用同一份 _evaluate_play，
# 预检通过 ⇒ 落子必然返回同一个码（顺序牌都是 1），逐步等价见 verify_ai_plan。
static func plan(game_manager, seat: int = -1) -> Dictionary:
	if game_manager == null or game_manager.is_game_over():
		return {}
	var gm_idx: int = int(seat) if seat >= 0 else int(game_manager.get_current_player_index())
	if gm_idx < 0 or gm_idx >= game_manager.players.size():
		return {}
	var p = game_manager.players[gm_idx]
	# 手牌空了就什么都不做（与改造前一致：出完最后一手由 play_cards 内部判胜）
	if p == null or not p.is_ai or p.hand.is_empty():
		return {}

	if game_manager.tutorial_level == 0 and game_manager.tutorial_level0_phase >= 1:
		if game_manager.clan_bomb_chain_active:
			return _plan_pass()
		return _plan_level0(game_manager, p, gm_idx)

	if game_manager.clan_bomb_chain_active:
		if p.clan_bomb_cooling:
			return _plan_pass()
		return _plan_clan_bomb(game_manager, p, gm_idx)

	return _plan_regular(game_manager, p, gm_idx)


# 单机入口：plan() + 落子。签名与改造前完全一致（GameUI / 测试直接调它）。
static func auto_play(game_manager, ui_refresh: Callable) -> void:
	var p: Dictionary = plan(game_manager)
	if not p.is_empty():
		_execute_local(game_manager, p)
	if ui_refresh.is_valid():
		ui_refresh.call()


# 单机落子：逐字复刻改造前的写路径（play_cards / player_pass），
# 刻意**不走** apply_event —— 那会往 event_log 里写联机事件，
# 单机对局不需要这份日志（GameManager.state_hash 只统计 log_messages）。
static func _execute_local(game_manager, p: Dictionary) -> int:
	if game_manager == null:
		return -1
	var gm_idx: int = int(game_manager.get_current_player_index())
	match String(p.get("type", "")):
		"play":
			var cards: Array = _cards_by_uids(game_manager.players[gm_idx].hand, p.get("uids", []))
			if cards.is_empty():
				return -1
			var cv = p.get("valences", {})
			var r: int = int(game_manager.play_cards(gm_idx, cards,
				cv if cv is Dictionary else {}, int(p.get("pattern", -1))))
			# 顺序牌（r == 1）：改造前就是「放弃指定牌型 + 轮到下一家」，逐字保留
			if r == 1:
				game_manager.sequence_constraint = -1
				game_manager.sequence_constraint_active = false
				game_manager.sequence_constraint_target = -1
				game_manager.next_turn()
			return r
		"sequence_skip":
			game_manager.sequence_constraint_active = false
			game_manager.sequence_constraint = -1
			game_manager.sequence_constraint_target = -1
			game_manager.next_turn()
			return 0
		"sequence_pick":
			game_manager.set_sequence_constraint(int(p.get("pattern", -1)))
			return 0
	game_manager.player_pass(gm_idx)
	return 0


# ---- 计划构造小工具 ----
static func _plan_pass() -> Dictionary:
	return {"type": "pass"}


# 出牌计划：pattern 必须是**本端**算好的（联机时随意图发走），
# 否则主机会自己再挑一次牌型，两端可能出成不同的牌 → state_hash 立刻分叉。
static func _plan_play(cards: Array, cv: Dictionary, pattern: int) -> Dictionary:
	return {
		"type": "play",
		"uids": _uids_of(cards),
		"valences": cv.duplicate(true),
		"pattern": pattern,
	}


static func _uids_of(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(int(c.uid))
	return out


# uid 列表 → 手牌卡对象；任一 uid 不在手里 → 空数组（整笔作废，不猜）
# 用「已用下标」而不是简单查找：测试 / 教程里手工 new 出来的牌 uid 可能重复（都是 0），
# 只按 uid 找会把同一张牌取两次 —— 「2 张牌的对子」变成「同一张出两次」→ 判非法。
static func _cards_by_uids(hand: Array, uids) -> Array:
	if not (uids is Array) or uids.is_empty():
		return []
	var used: Dictionary = {}
	var out: Array = []
	for raw in uids:
		var uid := int(raw)
		var hit := -1
		for i in range(hand.size()):
			if used.has(i):
				continue
			if int(hand[i].uid) == uid:
				hit = i
				break
		if hit < 0:
			return []
		used[hit] = true
		out.append(hand[hit])
	return out


# ============================================================
# 二、第0关 AI 策略（不抽牌，每回合只出 1 张单质）
# ============================================================
# P15-A：老实现先试「化合物对（2 张）」再试双原子，AI 8 张手牌 4 个回合就能清空；
# 而第0关 AI 不抽牌（GameManager 的 ai_no_draw）+ 清空手牌即判胜，于是新手常常
# 只出了 2~3 张牌就看到「本局结束」，练习被抢断。
# 现在第0关 AI 每回合只出 1 张单质，接不上就跳过：
#   1) AI 清空 8 张手牌最少要 8 个回合 → 玩家的练习回合从 4 提到 8；
#   2) 玩家一旦打出化合物，AI 接不上只能跳过 → 练习过程不会被打断。
# 注意：这是刻意放水 —— 第0关桌面出现化合物后 AI 基本不再出牌，不是 bug。
static func _plan_level0(game_manager, p, gm_idx: int) -> Dictionary:
	# 手牌只剩 1 张就收手：第零关 AI 永不清空手牌 → 玩家一定是获胜者（练习不会被打断）。
	# 不会因此死锁：全员跳过会走 GameManager._start_new_round()（清桌面 + 下一位自由出牌），
	# 玩家总能拿到「桌面为空、任意单牌都能出」的机会。
	if p.get_hand_count() <= 1:
		return _plan_pass()
	for c in p.hand:
		if game_manager.validate_play(gm_idx, [c]) >= 0:
			return _plan_play([c], {}, -1)

	return _plan_pass()


# ============================================================
# 三、族炸链 AI：打出更大的族炸或跳过
# ============================================================
static func _plan_clan_bomb(game_manager, p, gm_idx: int) -> Dictionary:
	var bg = _group_by_group(p.hand)
	for g in bg:
		if bg[g].size() >= 2:
			var cards: Array = bg[g].duplicate()
			if game_manager.validate_play(gm_idx, cards) >= 0:
				return _plan_play(cards, {}, -1)
	return _plan_pass()


# ============================================================
# 四、常规 AI 出牌策略
# ============================================================
static func _plan_regular(game_manager, p, gm_idx: int) -> Dictionary:
	# 接顺序：当桌面是顺序牌型且当前玩家需要接牌时，AI 才尝试出顺序
	if game_manager.table_pattern == CardPatternsScript.CardPattern.SEQUENCE \
			and not game_manager.is_round_starter:
		var seq = _find_sequence(p.hand)
		if seq.size() >= 3:
			# 顺序牌（validate_play 返回 1）：「放弃指定牌型」由落子方结算 ——
			# 单机在 _execute_local 里清约束 + next_turn，联机由主机 host_step_ai 当轮收窗
			if game_manager.validate_play(gm_idx, seq, {},
					CardPatternsScript.CardPattern.SEQUENCE) >= 0:
				return _plan_play(seq, {}, CardPatternsScript.CardPattern.SEQUENCE)

	if not p.clan_bomb_cooling:
		var bg = _group_by_group(p.hand)
		for g in bg:
			if bg[g].size() >= 2:
				var bomb_cards: Array = bg[g].duplicate()
				if game_manager.validate_play(gm_idx, bomb_cards) >= 0:
					return _plan_play(bomb_cards, {}, -1)

	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			# 卤族互化：默认禁止（与 play_cards 的 -7 一致），补充规则开启后放行
			if not game_manager.halogen_exchange_allowed and _is_ai_halogen_pair(pair):
				continue
			var cv: Dictionary = _pair_valences(pair)
			if not cv.is_empty() and game_manager.validate_play(gm_idx, pair, cv) >= 0:
				return _plan_play(pair, cv, -1)

	# L4a：一次出多个分子（2Na+2Br → 2NaBr、4H+2O → 2H₂O）。
	# 放在 2 张牌对之后：能用 2 张解决就不多甩牌，只有手牌够配方时才一次清掉 4~6 张。
	# 只做 2 元素 —— 3+ 元素的组合数 × 价态搜索会明显拖慢 AI 回合。
	if AI_RATIO_COMPOUND:
		var tried_ratio: Dictionary = {}
		for i in range(p.hand.size()):
			for j in range(i + 1, p.hand.size()):
				var ra = p.hand[i]
				var rb = p.hand[j]
				if ra.symbol == rb.symbol:
					continue
				var rkey: String = ra.symbol + "|" + rb.symbol if ra.symbol < rb.symbol \
						else rb.symbol + "|" + ra.symbol
				if tried_ratio.has(rkey):
					continue
				tried_ratio[rkey] = true
				if not game_manager.halogen_exchange_allowed and _is_ai_halogen_pair([ra, rb]):
					continue
				var rcv: Dictionary = _pair_valences([ra, rb])
				if rcv.is_empty():
					continue
				var rcards: Array = _ratio_cards(p.hand, ra, rb, rcv)
				if rcards.is_empty():
					continue
				if game_manager.validate_play(gm_idx, rcards, rcv) >= 0:
					return _plan_play(rcards, rcv, -1)

	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in CardPatternsScript.DIATOMIC_SYMBOLS:
			for j in range(p.hand.size()):
				if i != j and p.hand[j].symbol == c.symbol:
					var dp = [p.hand[i], p.hand[j]]
					if game_manager.validate_play(gm_idx, dp) >= 0:
						return _plan_play(dp, {}, -1)
					break

	for c in p.hand:
		if game_manager.validate_play(gm_idx, [c]) >= 0:
			return _plan_play([c], {}, -1)

	return _plan_pass()


# 在手牌中查找一组≥3张连续原子序数的牌（顺序牌型）
static func _find_sequence(hand: Array) -> Array:
	# 按原子序数分组并去重（同元素多张只算一次）
	var by_num: Dictionary = {}
	for c in hand:
		if not by_num.has(c.atomic_number):
			by_num[c.atomic_number] = c
	var nums: Array = by_num.keys()
	nums.sort()
	if nums.size() < 3:
		return []
	# 找最长的连续段
	var best: Array = []
	var cur: Array = [nums[0]]
	for i in range(1, nums.size()):
		if nums[i] == nums[i - 1] + 1:
			cur.append(nums[i])
		else:
			if cur.size() >= 3 and cur.size() > best.size():
				best = cur.duplicate()
			cur = [nums[i]]
	if cur.size() >= 3 and cur.size() > best.size():
		best = cur.duplicate()
	if best.size() < 3:
		return []
	# 从手牌中取对应牌（每张原子序数取一张）
	var result: Array = []
	for num in best:
		result.append(by_num[num])
	return result


# ============================================================
# 五、辅助方法
# ============================================================
static func _group_by_group(hand: Array) -> Dictionary:
	var r = {}
	for c in hand:
		if not r.has(c.group): r[c.group] = []
		r[c.group].append(c)
	return r


# 两元素化合物的化合价：统一交给 CompoundSolver.get_valence_pairs 裁决
# （默认配平优先；失败再按实际张数搜索「电荷平衡 + 电负性有序」的价态）。
# 假化合物（NCl / BrN / IN）在这里直接得到 {}，AI 不会再尝试打出。
static func _pair_valences(pair: Array) -> Dictionary:
	return CompoundSolverScript.get_valence_pairs(pair)


# L4a：按「最简整数比」从手牌收集一次出牌所需的卡牌（仅 2 元素）。
# 返回空数组 = 不走这条路（手牌不够凑第二个分子 / 比例算不出 / 与 2 张牌对等价）。
static func _ratio_cards(hand: Array, a, b, cv: Dictionary) -> Array:
	var unit: Dictionary = _ratio_unit_counts(a, b, cv)
	if unit.is_empty():
		return []
	var need_a: int = int(unit.get(a.symbol, 0))
	var need_b: int = int(unit.get(b.symbol, 0))
	if need_a < 1 or need_b < 1:
		return []
	var avail_a := 0
	var avail_b := 0
	for c in hand:
		if c.symbol == a.symbol: avail_a += 1
		elif c.symbol == b.symbol: avail_b += 1
	# 能凑几个完整分子；只凑得出 1 个时交给「2 张牌对」路径，这里只做 ≥2 个
	@warning_ignore("integer_division")
	var k: int = mini(avail_a / need_a, avail_b / need_b)
	if k < 2:
		return []
	var want_a: int = need_a * k
	var want_b: int = need_b * k
	var out: Array = []
	var got_a := 0
	var got_b := 0
	for c in hand:
		if c.symbol == a.symbol and got_a < want_a:
			out.append(c)
			got_a += 1
		elif c.symbol == b.symbol and got_b < want_b:
			out.append(c)
			got_b += 1
	if got_a < want_a or got_b < want_b:
		return []
	return out


# 单分子里 A、B 各需几张（最简整数比）。cv 必须是「每元素一个整数价」；
# 混合价（Array）不参与多分子化合 —— 价态分配要按张数逐张算，AI 侧不做这个猜测。
static func _ratio_unit_counts(a, b, cv: Dictionary) -> Dictionary:
	var va = cv.get(a.symbol, 0)
	var vb = cv.get(b.symbol, 0)
	if va is Array or vb is Array:
		return {}
	var ia := int(va)
	var ib := int(vb)
	if ia == 0 or ib == 0 or (ia > 0) == (ib > 0):
		return {}
	var g: int = CompoundSolverScript._gcd(absi(ia), absi(ib))
	if g < 1:
		return {}
	# 最简整数比：absi(ib)/g 与 absi(ia)/g 整除，整数除法即可
	@warning_ignore("integer_division")
	return {a.symbol: absi(ib) / g, b.symbol: absi(ia) / g}


# 纯卤族对（F+Cl / F+Br / Cl+Br …）——只用于「化合物」尝试路径。
# 族炸（_group_by_group）不是化合，按规则始终合法，因此这里不参与族炸过滤。
static func _is_ai_halogen_pair(pair: Array) -> bool:
	var halogen = ["F", "Cl", "Br", "I"]
	if pair[0].symbol != pair[1].symbol and pair[0].symbol in halogen and pair[1].symbol in halogen:
		return true
	return false
