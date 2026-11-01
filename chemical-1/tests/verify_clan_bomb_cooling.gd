# 验证「族炸冷却」硬规则（冷却优先于接炸链）
#   1) 引擎：冷却 + 自由出牌 → 族炸被拒（-3）
#   2) 引擎：族炸 → 全员不接 → 出其他牌型 → 再族炸 → 仍被拒（出别的牌不解除冷却）
#   3) 引擎：别人接炸拉开接炸链 → 冷却玩家被轮询到 → 出族炸 → 被拒（历史漏洞回归点）
#   4) 引擎：未冷却玩家在接炸链中可以接炸（不误伤正常接炸）
#   5) 引擎：打出化合物解除冷却后可再出族炸
#   6) 提示：冷却玩家在链中不会得到族炸建议；未冷却才给
#   7) 文案：可用牌型提示在「链中 + 冷却」时明确说不能接炸
#   8) UI：链中冷却只给「跳过」；自由出牌冷却时族炸按钮置灰；链中未冷却仍给族炸
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const HintScript = preload("res://scripts/HintAdvisor.gd")

const CLAN_BOMB = CardPatternsScript.CardPattern.CLAN_BOMB
const ELEMENT = CardPatternsScript.CardPattern.ELEMENT
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
		print("ALL CLAN_BOMB_COOLING TESTS PASSED")
	else:
		print("%d CLAN_BOMB_COOLING TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源，保证化合价 / 原子序数一致）----
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


# 一路 pass 到指定座位拿牌权；pass 不会打出族炸，不会引入干扰
func _pass_until(gm, seat: int, max_steps: int = 24) -> bool:
	for _i in range(max_steps):
		if gm.phase == 2:
			return false
		if gm.current_player_index == seat:
			return true
		gm.player_pass(gm.current_player_index)
	return false


# 布置「座位0 冷却、座位1 是链主人、轮到座位0」的接炸链局面
func _gm_in_chain_with_cooling(seat0_hand: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, seat0_hand)
	_set_hand(gm, 1, ["He", "Ne", "Ar", "Na", "K"])
	# 座位0 先出族炸 H+Li → 进入冷却、链激活（init_game 后就是座位0 自由出牌）
	gm.play_cards(0, _take(gm, 0, ["H", "Li"]), {}, CLAN_BOMB)
	# 座位1 用 3 张 0 族接炸（3 张 > 2 张）→ 链主人变成座位1
	gm.play_cards(1, _take(gm, 1, ["He", "Ne", "Ar"]), {}, CLAN_BOMB)
	# 座位2 / 座位3 跳过 → 轮询回到座位0（链仍然激活）
	if gm.clan_bomb_chain_active and gm.current_player_index != 0:
		gm.player_pass(gm.current_player_index)
	if gm.clan_bomb_chain_active and gm.current_player_index != 0:
		gm.player_pass(gm.current_player_index)
	return gm


# ============================================================
# 一、引擎：冷却 + 自由出牌
# ============================================================
func _test_free_play() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["He", "Ne", "Ar", "O"])
	gm.players[0].clan_bomb_cooling = true

	var r = gm.play_cards(0, _take(gm, 0, ["He", "Ne"]), {}, CLAN_BOMB)
	_check(r == -3, "冷却 + 自由出牌 → 族炸被拒（期望 -3，实际 %d）" % r)
	_check(gm.players[0].get_hand_count() == 4, "被拒后手牌不变（实际 %d 张）" % gm.players[0].get_hand_count())

	var r2 = gm.play_cards(0, _take(gm, 0, ["O"]), {}, ELEMENT)
	_check(r2 == 0, "冷却期间其他牌型照常可出（期望 0，实际 %d）" % r2)
	_check(gm.players[0].clan_bomb_cooling, "出单质不会解除冷却 ❄")


# ============================================================
# 二、引擎：族炸 → 隔一手其他牌型 → 再族炸（冷却不因出别的牌而解除）
# ============================================================
func _test_other_pattern_then_bomb() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["H", "Li", "He", "Ne", "Ar", "O"])

	var r1 = gm.play_cards(0, _take(gm, 0, ["H", "Li"]), {}, CLAN_BOMB)
	_check(r1 == 0 and gm.players[0].clan_bomb_cooling, "座位0 出族炸成功并进入冷却 ❄")

	_pass_until(gm, 0)   # 全员不接炸 → 牌权回到座位0
	var r2 = gm.play_cards(0, _take(gm, 0, ["O"]), {}, ELEMENT)
	_check(r2 == 0, "冷却期间出单质（「间隔的一手」）成功（期望 0，实际 %d）" % r2)

	_pass_until(gm, 0)
	var r3 = gm.play_cards(0, _take(gm, 0, ["He", "Ne"]), {}, CLAN_BOMB)
	_check(r3 == -3, "隔一手其他牌型后再出族炸仍被拒（期望 -3，实际 %d）" % r3)


# ============================================================
# 三、引擎：接炸链中 + 冷却（核心回归点）
#   旧实现：clan_bomb_chain_active 为真时跳过冷却校验 → 返回 0（漏洞）
# ============================================================
func _test_chain_cooling() -> void:
	var gm = _gm_in_chain_with_cooling(["H", "Li", "H", "Li", "Na", "O"])
	_check(gm.clan_bomb_chain_active, "布置：接炸链处于激活状态")
	_check(gm.get_current_player_index() == 0, "布置：轮询回到座位0（实际 %d）" % gm.get_current_player_index())
	_check(gm.get_clan_bomb_owner() == 1, "布置：链主人是座位1（实际 %d）" % gm.get_clan_bomb_owner())
	_check(gm.players[0].clan_bomb_cooling, "布置：座位0 仍处于冷却 ❄")

	var before_count: int = gm.players[0].get_hand_count()
	var cards: Array = _take(gm, 0, ["H", "Li", "Na"])
	var cmp = CardPatternsScript.compare_cards(cards, gm.table_cards)
	_check(cmp > 0, "对照：这组牌本身能压过桌面（cmp=%d），被拒只因冷却" % cmp)

	var r = gm.play_cards(0, cards, {}, CLAN_BOMB)
	_check(r == -3, "链中 + 冷却 → 族炸仍被拒（期望 -3，实际 %d）" % r)
	_check(gm.get_clan_bomb_owner() == 1, "被拒后链主人不变（实际 %d）" % gm.get_clan_bomb_owner())
	_check(gm.clan_bomb_chain_active, "被拒后接炸链仍激活（可继续被别人接/跳过）")
	_check(gm.players[0].get_hand_count() == before_count,
		"被拒后手牌不变（期望 %d 张，实际 %d 张）" % [before_count, gm.players[0].get_hand_count()])


# ============================================================
# 四、引擎：未冷却玩家可以正常接炸（不误伤）
# ============================================================
func _test_uncooled_can_intercept() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["H", "Li", "O", "Ar"])
	_set_hand(gm, 1, ["He", "Ne", "Ar", "Na"])
	gm.play_cards(0, _take(gm, 0, ["H", "Li"]), {}, CLAN_BOMB)
	_check(not gm.players[1].clan_bomb_cooling, "布置：座位1 未冷却")
	var r = gm.play_cards(1, _take(gm, 1, ["He", "Ne", "Ar"]), {}, CLAN_BOMB)
	_check(r == 0, "未冷却玩家在链中可以接炸（期望 0，实际 %d）" % r)
	_check(gm.get_clan_bomb_owner() == 1, "接炸成功后链主人变成座位1（实际 %d）" % gm.get_clan_bomb_owner())


# ============================================================
# 五、引擎：打出化合物解除冷却 → 可以再出族炸
# ============================================================
func _test_compound_clears_cooling() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["Na", "Cl", "He", "Ne", "Ar"])
	gm.players[0].clan_bomb_cooling = true

	var r1 = gm.play_cards(0, _take(gm, 0, ["Na", "Cl"]), {"Na": 1, "Cl": -1}, COMPOUND)
	_check(r1 == 0, "冷却期间可以出化合物（期望 0，实际 %d）" % r1)
	_check(not gm.players[0].clan_bomb_cooling, "打出化合物后冷却 ❄ 解除")

	_pass_until(gm, 0)
	var r2 = gm.play_cards(0, _take(gm, 0, ["He", "Ne", "Ar"]), {}, CLAN_BOMB)
	_check(r2 == 0, "解除冷却后可以再出族炸（期望 0，实际 %d）" % r2)


# ============================================================
# 六、提示：冷却玩家在链中不会得到族炸建议
# ============================================================
func _test_hint() -> void:
	var gm = _gm_in_chain_with_cooling(["H", "Li", "H", "Li", "Na", "O"])
	_check(gm.get_current_player_index() == 0 and gm.players[0].clan_bomb_cooling,
		"布置：座位0 冷却 + 链中轮到它")
	var adv: Dictionary = HintScript.suggest(gm)
	_check(int(adv.get("pattern", -1)) != CLAN_BOMB,
		"提示：链中冷却不推荐族炸（实际牌型 %d）" % int(adv.get("pattern", -1)))

	gm.players[0].clan_bomb_cooling = false
	var adv2: Dictionary = HintScript.suggest(gm)
	_check(int(adv2.get("pattern", -1)) == CLAN_BOMB,
		"提示：链中未冷却才推荐族炸（实际牌型 %d）" % int(adv2.get("pattern", -1)))


# ============================================================
# 七、文案：可用牌型提示
# ============================================================
func _test_text() -> void:
	var gm = _gm_in_chain_with_cooling(["H", "Li", "H", "Li", "Na", "O"])
	var s: String = gm.get_available_patterns(0)
	_check(s.find("不能接炸") >= 0, "链中冷却的可用牌型提示说明不能接炸（实际: %s）" % s)
	gm.players[0].clan_bomb_cooling = false
	var s2: String = gm.get_available_patterns(0)
	_check(s2.find("更大的族炸") >= 0, "链中未冷却的提示仍是「更大的族炸」（实际: %s）" % s2)


# ============================================================
# 八、UI：操作面板（冷却时不能给出可点的族炸入口）
# ============================================================
func _panel_buttons(scene) -> Array:
	var out: Array = []
	if scene.action_panel == null:
		return out
	for c in scene.action_panel.get_children():
		if is_instance_valid(c) and c is Button:
			out.append({"text": c.text, "disabled": c.disabled})
	return out


func _find_btn(btns: Array, text: String) -> Variant:
	for b in btns:
		if String(b["text"]) == text:
			return b
	return null


func _has_prefix(btns: Array, pref: String) -> bool:
	for b in btns:
		if String(b["text"]).begins_with(pref):
			return true
	return false


func _test_ui() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._init_game(4, 3)
	await process_frame
	var g = scene.game_manager
	_check(scene.action_panel != null, "布置：操作面板已创建")

	# (1) 接炸链中 + 冷却 → 只给「跳过」，不给族炸入口
	g.clan_bomb_chain_active = true
	g.clan_bomb_owner = 1
	g.current_player_index = 0
	g.players[0].clan_bomb_cooling = true
	scene.step_mode = 1
	scene._update_action_panel()
	await process_frame
	var b1: Array = _panel_buttons(scene)
	_check(not _has_prefix(b1, "作为族炸打出"), "UI：链中冷却不给「作为族炸打出」（实际 %s）" % str(b1))
	_check(_has_prefix(b1, "跳过"), "UI：链中冷却给「跳过」按钮（实际 %s）" % str(b1))

	# (2) 自由出牌 + 冷却 → 按钮存在但置灰（避免点了才报错）
	g.clan_bomb_chain_active = false
	g.clan_bomb_owner = -1
	scene.step_mode = 1
	scene._update_action_panel()
	await process_frame
	var b2: Array = _panel_buttons(scene)
	var bomb_btn: Variant = _find_btn(b2, "族炸❄冷却中")
	var bomb_disabled := false
	if bomb_btn is Dictionary:
		bomb_disabled = bool(bomb_btn["disabled"])
	_check(bomb_btn != null and bomb_disabled,
		"UI：自由出牌冷却时族炸按钮置灰（实际 %s）" % str(b2))

	# (3) 链中 + 未冷却 → 正常给族炸（不误伤）
	g.players[0].clan_bomb_cooling = false
	g.clan_bomb_chain_active = true
	g.clan_bomb_owner = 1
	scene.step_mode = 1
	scene._update_action_panel()
	await process_frame
	var b3: Array = _panel_buttons(scene)
	_check(_has_prefix(b3, "作为族炸打出"), "UI：链中未冷却仍给「作为族炸打出」（实际 %s）" % str(b3))


func _run() -> void:
	print("== 1. 引擎：冷却 + 自由出牌 ==")
	_test_free_play()
	print("== 2. 引擎：族炸 → 隔一手其他牌型 → 再族炸 ==")
	_test_other_pattern_then_bomb()
	print("== 3. 引擎：接炸链中 + 冷却（核心回归） ==")
	_test_chain_cooling()
	print("== 4. 引擎：未冷却玩家可以接炸（不误伤） ==")
	_test_uncooled_can_intercept()
	print("== 5. 引擎：化合物解除冷却 ==")
	_test_compound_clears_cooling()
	print("== 6. 提示：冷却玩家不推荐族炸 ==")
	_test_hint()
	print("== 7. 文案：可用牌型提示 ==")
	_test_text()
	print("== 8. UI：操作面板 ==")
	await _test_ui()
	_finish()
