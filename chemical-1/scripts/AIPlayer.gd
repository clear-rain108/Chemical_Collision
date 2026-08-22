# ============================================================
# AIPlayer.gd - AI 出牌决策模块
# 职责：AI 自动出牌策略（族炸 / 化合物 / 双原子 / 单质 / 跳过）
# 从 GameUI 拆出的独立模块；只依赖 game_manager 的公开接口
# ============================================================
extends RefCounted

const UtilsScript = preload("res://scripts/CardPatterns.gd")
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
			if _is_ai_halogen_pair(pair):
				continue
			var fi = CompoundSolverScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				# 化合价直接取公式中已配平的正/负价（如 HCl 中 H=+1、Cl=-1）
				var cv: Dictionary = {}
				for e in fi.get("pos_list", []):
					cv[e.symbol] = e.ox_state
				for e in fi.get("neg_list", []):
					cv[e.symbol] = e.ox_state
				if game_manager.play_cards(gm_idx, pair, cv) == 0: return

	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in UtilsScript.DIATOMIC_SYMBOLS:
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
	if not p.clan_bomb_cooling:
		var bg = _group_by_group(p.hand)
		for g in bg:
			if bg[g].size() >= 2:
				if game_manager.play_cards(gm_idx, bg[g].duplicate()) == 0: return

	for i in range(p.hand.size()):
		for j in range(i + 1, p.hand.size()):
			var pair = [p.hand[i], p.hand[j]]
			if _is_ai_halogen_pair(pair):
				continue
			var fi = CompoundSolverScript.get_compound_formula(pair)
			if not fi.is_empty() and fi.get("ratio_ok", false):
				# 化合价直接取公式中已配平的正/负价（如 HCl 中 H=+1、Cl=-1）
				var cv: Dictionary = {}
				for e in fi.get("pos_list", []):
					cv[e.symbol] = e.ox_state
				for e in fi.get("neg_list", []):
					cv[e.symbol] = e.ox_state
				if game_manager.play_cards(gm_idx, pair, cv) == 0: return

	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c.symbol in UtilsScript.DIATOMIC_SYMBOLS:
			for j in range(p.hand.size()):
				if i != j and p.hand[j].symbol == c.symbol:
					var dp = [p.hand[i], p.hand[j]]
					if game_manager.play_cards(gm_idx, dp) == 0: return
					break

	for c in p.hand:
		if game_manager.play_cards(gm_idx, [c]) == 0: return

	game_manager.player_pass(gm_idx)


# ============================================================
# 五、辅助方法
# ============================================================
static func _group_by_group(hand: Array) -> Dictionary:
	var r = {}
	for c in hand:
		if not r.has(c.group): r[c.group] = []
		r[c.group].append(c)
	return r


static func _is_ai_halogen_pair(pair: Array) -> bool:
	var halogen = ["F", "Cl", "Br", "I"]
	if pair[0].symbol != pair[1].symbol and pair[0].symbol in halogen and pair[1].symbol in halogen:
		return true
	return false
