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
# 一、主入口：当前 AI 自动操作
# ============================================================
static func auto_play(game_manager, ui_refresh: Callable) -> void:
	if game_manager == null or game_manager.is_game_over(): return
	var cp = game_manager.get_current_player()
	if cp == null or not cp.is_ai or cp.hand.is_empty(): return
	var gm_idx = game_manager.get_current_player_index()

	if game_manager.tutorial_level == 0 and game_manager.tutorial_level0_phase >= 1:
		if game_manager.clan_bomb_chain_active:
			game_manager.player_pass(gm_idx)
		else:
			_try_play_level0(game_manager, cp, gm_idx)
		if ui_refresh.is_valid():
			ui_refresh.call()
		return

	if game_manager.clan_bomb_chain_active:
		if cp.clan_bomb_cooling:
			game_manager.player_pass(gm_idx)
		else:
			_try_clan_bomb(game_manager, cp, gm_idx)
		if ui_refresh.is_valid():
			ui_refresh.call()
		return

	_try_play(game_manager, cp, gm_idx)
	if ui_refresh.is_valid():
		ui_refresh.call()


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
static func _try_play_level0(game_manager, p, gm_idx: int) -> void:
	# 手牌只剩 1 张就收手：第零关 AI 永不清空手牌 → 玩家一定是获胜者（练习不会被打断）。
	# 不会因此死锁：全员跳过会走 GameManager._start_new_round()（清桌面 + 下一位自由出牌），
	# 玩家总能拿到「桌面为空、任意单牌都能出」的机会。
	if p.get_hand_count() <= 1:
		game_manager.player_pass(gm_idx)
		return
	for c in p.hand:
		if game_manager.play_cards(gm_idx, [c]) == 0: return

	game_manager.player_pass(gm_idx)


# ============================================================
# 三、族炸链 AI：打出更大的族炸或跳过
# ============================================================
static func _try_clan_bomb(game_manager, p, gm_idx: int) -> void:
	var bg = _group_by_group(p.hand)
	for g in bg:
		if bg[g].size() >= 2:
			if game_manager.play_cards(gm_idx, bg[g].duplicate()) == 0: return
	game_manager.player_pass(gm_idx)


# ============================================================
# 四、常规 AI 出牌策略
# ============================================================
static func _try_play(game_manager, p, gm_idx: int) -> void:
	# 接顺序：当桌面是顺序牌型且当前玩家需要接牌时，AI 才尝试出顺序
	if game_manager.table_pattern == CardPatternsScript.CardPattern.SEQUENCE \
			and not game_manager.is_round_starter:
		var seq = _find_sequence(p.hand)
		if seq.size() >= 3:
			var r = game_manager.play_cards(gm_idx, seq, {}, CardPatternsScript.CardPattern.SEQUENCE)
			if r == 0 or r == 1:
				# 顺序打出成功（r==1 表示需要指定牌型）
				if r == 1:
					# AI 自动放弃指定牌型权利：清除约束并轮到下一家
					game_manager.sequence_constraint = -1
					game_manager.sequence_constraint_active = false
					game_manager.sequence_constraint_target = -1
					game_manager.next_turn()
				return

	if not p.clan_bomb_cooling:
		var bg = _group_by_group(p.hand)
		for g in bg:
			if bg[g].size() >= 2:
				if game_manager.play_cards(gm_idx, bg[g].duplicate()) == 0: return

	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			# 卤族互化：默认禁止（与 play_cards 的 -7 一致），补充规则开启后放行
			if not game_manager.halogen_exchange_allowed and _is_ai_halogen_pair(pair):
				continue
			var cv: Dictionary = _pair_valences(pair)
			if not cv.is_empty() and game_manager.play_cards(gm_idx, pair, cv) == 0: return

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
				if game_manager.play_cards(gm_idx, rcards, rcv) == 0: return

	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in CardPatternsScript.DIATOMIC_SYMBOLS:
			for j in range(p.hand.size()):
				if i != j and p.hand[j].symbol == c.symbol:
					var dp = [p.hand[i], p.hand[j]]
					if game_manager.play_cards(gm_idx, dp) == 0: return
					break

	for c in p.hand:
		if game_manager.play_cards(gm_idx, [c]) == 0: return

	game_manager.player_pass(gm_idx)


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
	return {a.symbol: absi(ib) / g, b.symbol: absi(ia) / g}


# 纯卤族对（F+Cl / F+Br / Cl+Br …）——只用于「化合物」尝试路径。
# 族炸（_group_by_group）不是化合，按规则始终合法，因此这里不参与族炸过滤。
static func _is_ai_halogen_pair(pair: Array) -> bool:
	var halogen = ["F", "Cl", "Br", "I"]
	if pair[0].symbol != pair[1].symbol and pair[0].symbol in halogen and pair[1].symbol in halogen:
		return true
	return false
