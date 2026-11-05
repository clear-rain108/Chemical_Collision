# ============================================================
# HintAdvisor.gd - 「提示」按钮的只读建议器（P6）
# 职责：给定当前局面，找出一组「点了就能直接打出」的牌 + 一句话说明
#
# 设计约束
#   1. 全部 static、只读：绝不修改 GameManager / Player / Card 的任何状态
#      （选中哪些牌由 GameUI 自己写回 selected_indices / compound_selections）
#   2. 可用性判定必须与 GameManager.play_cards() 完全一致，
#      否则玩家照着提示点会被判「非法出牌」——见 _check() 的注释映射
#   3. 返回的 valence 是 UI 面板能吃下的形式：{symbol: +价 / -价}，
#      且 2 元素时按 gcd 精确给出张数，3+ 元素时每种恰好 1 张（同 _on_confirm_compound）
#
# 返回结构（suggest）
#   {
#     "indices": Array[int],     # 手牌下标，可直接填 selected_indices
#     "pattern": int,            # CardPatterns.CardPattern 枚举
#     "valence": Dictionary,     # 仅化合物非空
#     "organic": bool,           # 是否为有机物（需 custom_valences = {_organic: true}）
#     "label": String,           # 牌型短标签，如 "化合物 Fe2O3"
#     "text": String,            # 写进 CardInfoLabel 的完整提示
#   }
# ============================================================

extends RefCounted

const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")

const P_ELEMENT := CardPatternsScript.CardPattern.ELEMENT
const P_COMPOUND := CardPatternsScript.CardPattern.COMPOUND
const P_CLAN := CardPatternsScript.CardPattern.CLAN_BOMB
const P_ORGANIC := CardPatternsScript.CardPattern.ORGANIC
const P_SEQUENCE := CardPatternsScript.CardPattern.SEQUENCE


# ============================================================
# 一、对外接口
# ============================================================
static func suggest(gm) -> Dictionary:
	if gm == null or gm.is_game_over():
		return {}
	var cp = gm.get_current_player()
	if cp == null or cp.hand.is_empty():
		return {}

	var best: Dictionary = {}
	var best_score := -1
	for cand in _candidates(gm, cp):
		if not _check(gm, _cards_of(cp, cand["indices"]), cand["valence"], cand["pattern"]):
			continue
		var score := _score(cp, cand)
		if score > best_score:
			best_score = score
			best = cand
	if best.is_empty():
		return {}
	var cards := _cards_of(cp, best["indices"])
	best["label"] = _label_of(best, cards)
	best["text"] = _text_of(best, cards)
	return best


# 一组手牌下标当前能否打出（与 suggest 用同一套校验，测试可单独断言）
static func is_playable(gm, indices: Array) -> bool:
	if gm == null:
		return false
	var cp = gm.get_current_player()
	if cp == null or indices.is_empty():
		return false
	var cards := _cards_of(cp, indices)
	if cards.size() != indices.size():
		return false   # 有越界下标

	var tries: Array = [
		{"p": P_ELEMENT, "cv": {}},
		{"p": P_CLAN, "cv": {}},
		{"p": P_ORGANIC, "cv": {"_organic": true}},
	]
	if gm.get_sequence_rules_enabled():
		tries.append({"p": P_SEQUENCE, "cv": {}})
	var cv_auto := compound_valence_for(cards)
	if not cv_auto.is_empty():
		tries.append({"p": P_COMPOUND, "cv": cv_auto})
	for t in tries:
		if _check(gm, cards, t["cv"], t["p"]):
			return true
	return false


# UI 面板需要的化合价字典：{} 表示这组牌给不出可被面板接受的化合价
# 统一由 CompoundSolver.get_valence_pairs 裁决（默认配平优先，失败再按张数搜索），
# 保证「面板给得出的价」和「play_cards 能接受」是同一套规则。
static func compound_valence_for(cards: Array) -> Dictionary:
	return CompoundSolverScript.get_valence_pairs(cards)


# ============================================================
# 二、候选生成（按牌型分别造「可能成立的组合」，再统一过 _check）
# ============================================================
static func _candidates(gm, cp) -> Array:
	var out: Array = []
	var n: int = cp.hand.size()
	var by_sym: Dictionary = {}
	for i in range(n):
		if not by_sym.has(cp.hand[i].symbol):
			by_sym[cp.hand[i].symbol] = []
		by_sym[cp.hand[i].symbol].append(i)

	# 1) 单张单质
	for i in range(n):
		out.append(_mk([i], P_ELEMENT, {}, false))

	# 2) 双原子单质（H2 / N2 / O2 / F2 / Cl2 / Br2 / I2）
	for sym in by_sym:
		var idxs: Array = by_sym[sym]
		if idxs.size() >= 2 and sym in CardPatternsScript.DIATOMIC_SYMBOLS:
			out.append(_mk([idxs[0], idxs[1]], P_ELEMENT, {}, false))

	# 3) 族炸：同族、每种元素各 1 张（整族 + 每种少一张的变体，方便压过桌面）
	#    第零关只演示单质/化合物（族炸是第二关的内容）：规则层仍允许玩家手动打出，
	#    但「提示」不替新手选族炸，避免第一次练习就被带偏节奏
	#    注意 tutorial_level==0 同时也是「自由模式」的默认值，必须靠 phase 区分
	var in_level0_tutorial: bool = gm.tutorial_level == 0 and gm.tutorial_level0_phase >= 1
	if not in_level0_tutorial:
		var by_group: Dictionary = {}
		for i in range(n):
			if not by_group.has(cp.hand[i].group):
				by_group[cp.hand[i].group] = []
			by_group[cp.hand[i].group].append(i)
		for g in by_group:
			var seen: Dictionary = {}
			var pick: Array = []
			for i in by_group[g]:
				var s = cp.hand[i].symbol
				if seen.has(s):
					continue
				seen[s] = true
				pick.append(i)
			if pick.size() < 2:
				continue
			out.append(_mk(pick, P_CLAN, {}, false))
			if pick.size() >= 3:
				for k in range(pick.size()):
					var sub: Array = pick.duplicate()
					sub.remove_at(k)
					out.append(_mk(sub, P_CLAN, {}, false))

	# 4) 顺序：原子序数连续段（仅顺序规则开启时 UI 才给「作为顺序」按钮）
	if gm.get_sequence_rules_enabled():
		out.append_array(_sequence_candidates(cp))

	# 5) 有机物：按 CH4 / C2H6 / C3H8 / 一卤代 / 含氧物模板取牌
	out.append_array(_organic_candidates(by_sym, cp))

	# 6) 化合物：2 元素按 gcd 配平，3 元素每种 1 张且总电荷为 0
	#    （卤族互化关闭时，纯卤素组合在 _compound_candidates 里直接跳过）
	out.append_array(_compound_candidates(gm, by_sym, cp))
	return out


static func _sequence_candidates(cp) -> Array:
	var order: Array = []
	for i in range(cp.hand.size()):
		order.append(i)
	order.sort_custom(func(a, b): return cp.hand[a].atomic_number < cp.hand[b].atomic_number)
	var out: Array = []
	var start := 0
	while start < order.size():
		var end := start
		while end + 1 < order.size() \
				and cp.hand[order[end + 1]].atomic_number == cp.hand[order[end]].atomic_number + 1:
			end += 1
		var seg: Array = order.slice(start, end + 1)
		if seg.size() >= 3:
			out.append(_mk(seg, P_SEQUENCE, {}, false))
			for take in range(3, seg.size()):
				out.append(_mk(seg.slice(0, take), P_SEQUENCE, {}, false))
		start = end + 1
	return out


static func _organic_candidates(by_sym: Dictionary, cp) -> Array:
	var out: Array = []
	var templates: Array = [
		{"C": 1, "H": 4}, {"C": 2, "H": 6}, {"C": 3, "H": 8},
		{"C": 1, "H": 2, "O": 1}, {"C": 1, "H": 4, "O": 1},
		{"C": 2, "H": 6, "O": 1}, {"C": 1, "H": 2, "O": 2}, {"C": 2, "H": 4, "O": 2},
	]
	for hal in ["F", "Cl", "Br", "I"]:
		templates.append({"C": 1, "H": 3, hal: 1})
		templates.append({"C": 2, "H": 5, hal: 1})
		templates.append({"C": 3, "H": 7, hal: 1})
	for tpl in templates:
		var idxs: Array = []
		var ok := true
		for sym in tpl:
			var need: int = tpl[sym]
			var pool: Array = by_sym.get(sym, [])
			if pool.size() < need:
				ok = false
				break
			for k in range(need):
				idxs.append(pool[k])
		if not ok:
			continue
		var cards := _cards_of(cp, idxs)
		if CardPatternsScript.detect_pattern(cards, true) == CardPatternsScript.CardPattern.ORGANIC:
			out.append(_mk(idxs, P_ORGANIC, {}, true))
	return out


static func _compound_candidates(gm, by_sym: Dictionary, cp) -> Array:
	var out: Array = []
	var syms: Array = by_sym.keys()
	var seen: Dictionary = {}
	# ---- 2 元素：a×na + b×nb，na/nb 由 gcd 给出（与 _on_confirm_compound 完全一致）----
	for x in range(syms.size()):
		for y in range(x + 1, syms.size()):
			var sa: String = syms[x]
			var sb: String = syms[y]
			# 卤族互化关闭时：两种卤素之间不可化合（play_cards 会返回 -7，这里提前跳过）
			if not gm.halogen_exchange_allowed and _is_halogen_sym(sa) and _is_halogen_sym(sb):
				continue
			var ca = cp.hand[by_sym[sa][0]]
			var cb = cp.hand[by_sym[sb][0]]
			for va in ca.common_valence:
				for vb in cb.common_valence:
					if not ((va > 0 and vb < 0) or (va < 0 and vb > 0)):
						continue
					var na: int = abs(int(vb)) / _gcd(abs(int(va)), abs(int(vb)))
					var nb: int = abs(int(va)) / _gcd(abs(int(va)), abs(int(vb)))
					var pool_a: Array = by_sym[sa]
					var pool_b: Array = by_sym[sb]
					if pool_a.size() < na or pool_b.size() < nb:
						continue
					var idxs: Array = []
					for k in range(na):
						idxs.append(pool_a[k])
					for k in range(nb):
						idxs.append(pool_b[k])
					var key := str(idxs)
					if seen.has(key):
						continue
					seen[key] = true
					# 实际化合价交给 CompoundSolver 统一裁决（假化合物如 NCl 直接无解 → 不进候选）
					var cv: Dictionary = CompoundSolverScript.get_valence_pairs(_cards_of(cp, idxs))
					if not cv.is_empty():
						out.append(_mk(idxs, P_COMPOUND, cv, false))
	# ---- 3 元素：每种 1 张 + 电荷平衡（同样交给 CompoundSolver 裁决）----
	for x in range(syms.size()):
		for y in range(x + 1, syms.size()):
			for z in range(y + 1, syms.size()):
				var s1: String = syms[x]
				var s2: String = syms[y]
				var s3: String = syms[z]
				# 卤族互化关闭时：含 ≥2 种卤素的多元素化合物同样不可出（对齐 play_cards）
				if not gm.halogen_exchange_allowed:
					var hal_count := 0
					for s in [s1, s2, s3]:
						if _is_halogen_sym(s):
							hal_count += 1
					if hal_count >= 2:
						continue
				var idxs3: Array = [by_sym[s1][0], by_sym[s2][0], by_sym[s3][0]]
				var cv3: Dictionary = CompoundSolverScript.get_valence_pairs(_cards_of(cp, idxs3))
				if cv3.is_empty():
					continue
				out.append(_mk(idxs3, P_COMPOUND, cv3, false))
	return out


# 是否为卤族元素（F / Cl / Br / I）
static func _is_halogen_sym(sym: String) -> bool:
	return sym in CardDatabaseScript.HALOGEN_SYMBOLS


# ============================================================
# 三、可用性判定（逐条对齐 GameManager.play_cards，见每段注释）
# ============================================================
static func _check(gm, cards: Array, cv: Dictionary, intended: int) -> bool:
	if cards.is_empty():
		return false
	var cp = gm.get_current_player()
	if cp == null:
		return false

	# --- play_cards: skip_bomb / prefer_sequence ---
	var skip_bomb: bool = cv.size() >= 2 or cv.has("_organic")
	var prefer_seq: bool = intended == P_SEQUENCE
	var pattern: int = CardPatternsScript.detect_pattern(cards, skip_bomb, prefer_seq)
	if pattern == -1:
		return false

	# --- play_cards: intended_pattern 与检测结果必须一致 ---
	if intended >= 0 and pattern != intended:
		var organic_as_compound: bool = gm.organic_rules_enabled \
			and pattern == P_ORGANIC and intended == P_COMPOUND
		if not organic_as_compound:
			return false

	# --- play_cards: 卤族互化（仅化合物；族炸不受限） ---
	if pattern == P_COMPOUND and not gm.halogen_exchange_allowed and gm.is_halogen_mix(cards):
		return false

	# --- play_cards: 第零关 AI 禁出族炸（提示只服务人类玩家，保留同条件） ---
	if gm.tutorial_level == 0 and gm.tutorial_level0_phase >= 1 and cp.is_ai and pattern == P_CLAN:
		return false

	# --- play_cards: 顺序指定牌型的约束（只作用于被指定的那名玩家） ---
	if gm.sequence_constraint_active \
			and gm.get_current_player_index() == gm.sequence_constraint_target:
		if gm.sequence_constraint >= 0 and pattern != gm.sequence_constraint:
			var constraint_match: bool = gm.sequence_constraint == P_COMPOUND and pattern == P_ORGANIC
			if not constraint_match:
				return false

	# --- play_cards: 族炸 / 桌面接牌 ---
	if pattern == P_CLAN:
		if gm.clan_bomb_disabled:
			return false
		# 与 GameManager.play_cards 保持一致：冷却优先于接炸链（含链中接炸）
		if cp.clan_bomb_cooling:
			return false
		if gm.compound_immune and not gm.clan_bomb_chain_active:
			return false
		if gm.clan_bomb_chain_active and gm.table_cards.size() > 0:
			if CardPatternsScript.compare_cards(cards, gm.table_cards, pattern, gm.table_pattern) <= 0:
				return false
	else:
		if gm.clan_bomb_chain_active:
			return false
		if not gm.is_round_starter:
			if gm.table_pattern == P_ELEMENT and pattern != P_ELEMENT:
				return false
			if gm.table_pattern == P_COMPOUND and pattern != P_COMPOUND:
				return false
			if gm.table_cards.size() > 0 and gm.table_pattern != P_SEQUENCE:
				# 显式传入牌型：桌面可能「既是族炸又能配成化合物」，
				# 按牌面重新检测会让提示漏掉实际可出的合法出牌。
				if CardPatternsScript.compare_cards(cards, gm.table_cards, pattern, gm.table_pattern) <= 0:
					return false

	# --- play_cards: 化合物必须给出化学式且比例配平 ---
	if pattern == P_COMPOUND:
		var fi: Dictionary = CompoundSolverScript.get_compound_formula(cards, cv)
		if fi.is_empty() or not fi.get("ratio_ok", false):
			return false
	return true


# ============================================================
# 四、评分与文案
# ============================================================
# 优先级：能赢 > 有机物（打出即胜）> 族炸 > 化合物 > 单质 > 顺序，
# 同档里出牌张数越多越好（更快清空手牌）
static func _score(cp, cand: Dictionary) -> int:
	var s := 0
	if cand["indices"].size() == cp.hand.size():
		s += 1000
	match cand["pattern"]:
		P_ORGANIC: s += 900
		P_CLAN: s += 400
		P_COMPOUND: s += 300
		P_ELEMENT: s += 100
		P_SEQUENCE: s += 50
	s += cand["indices"].size() * 10
	return s


static func _label_of(cand: Dictionary, cards: Array) -> String:
	match cand["pattern"]:
		P_ORGANIC:
			return "有机物 " + CompoundSolverScript.get_organic_name(cards)
		P_COMPOUND:
			var fi: Dictionary = CompoundSolverScript.get_compound_formula(cards, cand["valence"])
			return "化合物 " + str(fi.get("formula", ""))
		P_ELEMENT:
			return "单质 " + CardPatternsScript.get_element_display(cards)
		P_CLAN:
			return "族炸 " + _syms(cards)
		P_SEQUENCE:
			return "顺序 " + _syms(cards)
	return _syms(cards)


static func _text_of(cand: Dictionary, cards: Array) -> String:
	var n: int = cards.size()
	var label := _label_of(cand, cards)
	match cand["pattern"]:
		P_ORGANIC:
			return "提示：已选好 %s，点「合成化合物」自动识别并打出（立即获胜）。" % label
		P_COMPOUND:
			return "提示：已选好 %d 张并配好化合价 → %s，点「确认打出」。" % [n, label]
		P_ELEMENT:
			return "提示：已选好 %d 张 %s，点「作为单质打出」。" % [n, label]
		P_CLAN:
			return "提示：已选好 %d 张 %s，点「作为族炸打出」抢牌权。" % [n, label]
		P_SEQUENCE:
			return "提示：已选好 %d 张 %s，点「作为顺序打出」反转出牌方向。" % [n, label]
	return "提示：已选好 %d 张 %s。" % [n, label]


static func _syms(cards: Array) -> String:
	var parts: Array = []
	for c in cards:
		parts.append(c.symbol)
	return "+".join(parts)


# ============================================================
# 五、小工具
# ============================================================
static func _cards_of(cp, indices: Array) -> Array:
	var out: Array = []
	for i in indices:
		var idx := int(i)
		if idx < 0 or idx >= cp.hand.size():
			return []
		out.append(cp.hand[idx])
	return out


static func _mk(indices: Array, pattern: int, valence: Dictionary, organic: bool) -> Dictionary:
	return {
		"indices": indices.duplicate(),
		"pattern": pattern,
		"valence": valence.duplicate(),
		"organic": organic,
	}


static func _gcd(a: int, b: int) -> int:
	var x: int = abs(a)
	var y: int = abs(b)
	while y != 0:
		var t: int = y
		y = x % y
		x = t
	return maxi(x, 1)

