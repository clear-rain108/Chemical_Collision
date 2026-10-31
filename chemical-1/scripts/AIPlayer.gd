# ============================================================
# AIPlayer.gd - AI 出牌决策模块
# 职责：AI 自动出牌策略（族炸 / 化合物 / 双原子 / 单质 / 跳过）
# 从 GameUI 拆出的独立模块；只依赖 game_manager 的公开接口
# ============================================================
extends RefCounted

const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")

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
# 二、第0关 AI 策略（不抽牌，只做基础出牌）
# ============================================================
static func _try_play_level0(game_manager, p, gm_idx: int) -> void:
	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			# 卤族互化：默认禁止（与 play_cards 的 -7 一致），补充规则开启后放行
			if not game_manager.halogen_exchange_allowed and _is_ai_halogen_pair(pair):
				continue
			var cv: Dictionary = _pair_valences(pair)
			if not cv.is_empty() and game_manager.play_cards(gm_idx, pair, cv) == 0: return

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


# 两元素化合物的化合价：优先用默认配平（金属/非金属自动分正负价）；
# 默认配平失败时遍历常见价找一正一负，再用 get_compound_formula 复核比例。
# 例：F(只有 -1) + Cl(可 +1) —— 卤族互化开关打开后才有机会走到这里。
static func _pair_valences(pair: Array) -> Dictionary:
	var fi = CompoundSolverScript.get_compound_formula(pair)
	if not fi.is_empty() and fi.get("ratio_ok", false):
		var cv: Dictionary = {}
		for e in fi.get("pos_list", []):
			cv[e.symbol] = e.ox_state
		for e in fi.get("neg_list", []):
			cv[e.symbol] = e.ox_state
		return cv
	var a = pair[0]
	var b = pair[1]
	for va in a.common_valence:
		for vb in b.common_valence:
			if (va > 0 and vb < 0) or (va < 0 and vb > 0):
				var cv2: Dictionary = {a.symbol: va, b.symbol: vb}
				var fi2 = CompoundSolverScript.get_compound_formula(pair, cv2)
				if not fi2.is_empty() and fi2.get("ratio_ok", false):
					return cv2
	return {}


# 纯卤族对（F+Cl / F+Br / Cl+Br …）——只用于「化合物」尝试路径。
# 族炸（_group_by_group）不是化合，按规则始终合法，因此这里不参与族炸过滤。
static func _is_ai_halogen_pair(pair: Array) -> bool:
	var halogen = ["F", "Cl", "Br", "I"]
	if pair[0].symbol != pair[1].symbol and pair[0].symbol in halogen and pair[1].symbol in halogen:
		return true
	return false
