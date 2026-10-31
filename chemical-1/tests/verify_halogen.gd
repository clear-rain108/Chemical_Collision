# 验证「禁止卤族互化」硬规则 + 「允许卤族互化」补充规则（B 方案：只限化合物）
#   1) 引擎：play_cards() 是唯一判定点 —— 默认返回 -7；开关打开后放行
#   2) B 方案边界：F+Cl 作为「族炸」始终合法，不能被误伤
#   3) 提示：HintAdvisor 不生成纯卤素化合物候选，且建议一定真能打出（交叉验证）
#   4) AI：两元素化合物路径读开关；族炸冷却时不会偷偷合成 ClF
#   5) UI：合成化合物按钮提前拦；提示不会把面板推到「确认打出」
#   6) 教程局同样默认禁止
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")
const HintScript = preload("res://scripts/HintAdvisor.gd")
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
		print("ALL HALOGEN TESTS PASSED")
	else:
		print("%d HALOGEN TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源，保证化合价 / 原子序数一致）----
func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


# ---- 全新 GM + 指定手牌（人类玩家 = players[0]）----
func _gm_with_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	var p = gm.get_current_player()
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))
	return gm


# ---- 全新 GM + 指定 AI 手牌（AI 玩家 = players[1]，并把回合交给他）----
func _gm_with_ai_hand(syms: Array) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	gm.current_player_index = 1
	var p = gm.get_current_player()
	p.hand.clear()
	for s in syms:
		p.hand.append(_card(s))
	return gm


func _run() -> void:
	_test_engine()
	_test_hint()
	_test_ai()
	await _test_ui()
	_finish()


# ============================================================
# 一、引擎层：play_cards() 是唯一判定点
# ============================================================
func _test_engine() -> void:
	var gm = _gm_with_hand(["F", "Cl"])
	_check(not gm.halogen_exchange_allowed, "开局默认禁止卤族互化（halogen_exchange_allowed=false）")
	_check(not gm.get_halogen_exchange_allowed(), "get_halogen_exchange_allowed() 与字段一致")

	_check(gm.is_halogen_mix([_card("F"), _card("Cl")]), "is_halogen_mix(F+Cl) = true")
	_check(not gm.is_halogen_mix([_card("F"), _card("F")]),
		"is_halogen_mix(F+F) = false（同种卤素不算互化）")
	_check(not gm.is_halogen_mix([_card("Na"), _card("Cl")]),
		"is_halogen_mix(Na+Cl) = false（卤族 + 金属不算互化）")

	# 化合物（带 cv → skip_bomb，必被判成 COMPOUND）→ -7
	var p = gm.get_current_player()
	var r1 = gm.play_cards(0, [p.hand[0], p.hand[1]], {"F": -1, "Cl": 1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r1 == -7, "默认：F+Cl 化合物被拦（返回 -7，实际 %d）" % r1)
	_check(p.hand.size() == 2, "被拦后手牌不变（实际 %d 张）" % p.hand.size())

	# 族炸：F+Cl 同族不同元素 → CLAN_BOMB，B 方案始终合法
	var gm2 = _gm_with_hand(["F", "Cl"])
	var p2 = gm2.get_current_player()
	var r2 = gm2.play_cards(0, [p2.hand[0], p2.hand[1]])
	_check(r2 == 0, "F+Cl 作为族炸始终合法（B 方案，返回 %d）" % r2)
	_check(gm2.get_table_pattern() == CardPatternsScript.CardPattern.CLAN_BOMB,
		"F+Cl 打出的牌型是族炸（实际 %d）" % gm2.get_table_pattern())

	# 卤族 + 金属：不受影响
	var gm3 = _gm_with_hand(["Na", "F"])
	var p3 = gm3.get_current_player()
	var r3 = gm3.play_cards(0, [p3.hand[0], p3.hand[1]], {"Na": 1, "F": -1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r3 == 0, "Na+F → NaF 不受卤族互化影响（返回 %d）" % r3)

	# 另一对卤素（Cl+Br）同样拦
	var gm4 = _gm_with_hand(["Cl", "Br"])
	var p4 = gm4.get_current_player()
	var r4 = gm4.play_cards(0, [p4.hand[0], p4.hand[1]], {"Cl": 1, "Br": -1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r4 == -7, "默认：Cl+Br 化合物被拦（返回 %d）" % r4)

	# 开关打开 → 放行，且化学式 ClF
	var gm5 = _gm_with_hand(["F", "Cl"])
	gm5.halogen_exchange_allowed = true
	var p5 = gm5.get_current_player()
	var cards5: Array = [p5.hand[0], p5.hand[1]]
	var r5 = gm5.play_cards(0, cards5, {"F": -1, "Cl": 1},
		CardPatternsScript.CardPattern.COMPOUND)
	_check(r5 == 0, "开关打开后 F+Cl 化合物可出（返回 %d）" % r5)
	var fi: Dictionary = CompoundSolverScript.get_compound_formula(cards5, {"F": -1, "Cl": 1})
	_check(str(fi.get("formula", "")) == "ClF",
		"F+Cl 化学式为 ClF（实际 %s）" % str(fi.get("formula", "")))

	# 教程局复位
	var gm6 = GameManagerScript.new()
	gm6.halogen_exchange_allowed = true
	gm6.init_tutorial(1)
	_check(not gm6.halogen_exchange_allowed, "教程局 init_tutorial 复位为禁止卤族互化")


# ============================================================
# 二、提示层：建议 = 可打出（与 play_cards 同一判据）
# ============================================================
func _test_hint() -> void:
	# 默认：只有 F/Cl → 建议应是合法的族炸，绝不给 ClF 化合物
	var gm = _gm_with_hand(["F", "Cl"])
	var adv: Dictionary = HintScript.suggest(gm)
	_check(not adv.is_empty(), "默认 F+Cl 仍有建议（族炸）")
	_check(int(adv.get("pattern", -1)) == CardPatternsScript.CardPattern.CLAN_BOMB,
		"默认建议牌型是族炸而不是化合物（实际 %d）" % int(adv.get("pattern", -1)))
	var val0: Dictionary = adv.get("valence", {})
	_check(val0.is_empty(), "族炸建议不填化合价")
	# 交叉验证：建议一定能真打出
	var cp = gm.get_current_player()
	var cs: Array = []
	for i in adv["indices"]:
		cs.append(cp.hand[int(i)])
	_check(gm.play_cards(0, cs, {}, int(adv["pattern"])) == 0, "提示的族炸 F+Cl 真能打出（建议=可打出）")

	# 族炸冷却（无法族炸）+ 开关关闭 → 不给 ClF 化合物
	var gm2 = _gm_with_hand(["F", "Cl"])
	gm2.get_current_player().clan_bomb_cooling = true
	_check(not HintScript.is_playable(gm2, [0, 1]), "冷却+禁止：F+Cl 不能以任何形式打出")
	var adv2: Dictionary = HintScript.suggest(gm2)
	_check(int(adv2.get("pattern", -1)) != CardPatternsScript.CardPattern.COMPOUND,
		"冷却时也不建议 ClF 化合物（实际牌型 %d）" % int(adv2.get("pattern", -1)))

	# 同样局面 + 开关打开 → 建议化合物 ClF，并真的能打出
	var gm3 = _gm_with_hand(["F", "Cl"])
	gm3.get_current_player().clan_bomb_cooling = true
	gm3.halogen_exchange_allowed = true
	var adv3: Dictionary = HintScript.suggest(gm3)
	_check(int(adv3.get("pattern", -1)) == CardPatternsScript.CardPattern.COMPOUND,
		"开关打开+冷却：建议化合物（实际 %d）" % int(adv3.get("pattern", -1)))
	_check(str(adv3.get("text", "")).find("ClF") >= 0,
		"提示文案写出 ClF：%s" % str(adv3.get("text", "")))
	var cp3 = gm3.get_current_player()
	var cs3: Array = []
	for i in adv3["indices"]:
		cs3.append(cp3.hand[int(i)])
	_check(gm3.play_cards(0, cs3, adv3["valence"], int(adv3["pattern"])) == 0,
		"开关打开后提示的 ClF 真能打出（建议=可打出）")


# ============================================================
# 三、AI：化合物路径读开关，冷却时不会偷偷合成 ClF
# ============================================================
func _test_ai() -> void:
	# AI 手牌只有 F+Cl：先出族炸（合法），不会走化合物
	var gm = _gm_with_ai_hand(["F", "Cl"])
	AIPlayerScript.auto_play(gm, Callable())
	_check(gm.get_table_pattern() == CardPatternsScript.CardPattern.CLAN_BOMB,
		"AI 优先用 F+Cl 打族炸（实际牌型 %d）" % gm.get_table_pattern())

	# 族炸冷却 + 桌面是化合物 → AI 不能偷偷合成 ClF，只能跳过
	var gm2 = _gm_with_ai_hand(["F", "Cl"])
	gm2.get_current_player().clan_bomb_cooling = true
	gm2.is_round_starter = false
	gm2.table_cards = [_card("Na"), _card("Cl")]
	gm2.table_pattern = CardPatternsScript.CardPattern.COMPOUND
	gm2.table_player_index = 0
	AIPlayerScript.auto_play(gm2, Callable())
	_check(gm2.get_table_pattern() == CardPatternsScript.CardPattern.COMPOUND
			and gm2.get_table_cards().size() == 2,
		"AI 冷却时不会打出 ClF 化合物（桌面未变）")
	_check(gm2.get_table_player_index() == 0, "桌面仍属于原玩家（AI 没抢到牌权）")

	# 开关打开 + 冷却 + 自由出牌 → AI 可以合成 ClF
	var gm3 = _gm_with_ai_hand(["F", "Cl"])
	gm3.halogen_exchange_allowed = true
	gm3.get_current_player().clan_bomb_cooling = true
	AIPlayerScript.auto_play(gm3, Callable())
	_check(gm3.get_table_pattern() == CardPatternsScript.CardPattern.COMPOUND,
		"开关打开后 AI 可以合成 ClF（实际牌型 %d）" % gm3.get_table_pattern())


# ============================================================
# 四、UI 层：合成化合物按钮提前拦；提示不推「确认打出」
# ============================================================
func _test_ui() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	scene._init_game(4, 3)
	await process_frame
	var p = scene.game_manager.get_current_player()
	p.hand.clear()
	p.hand.append(_card("F"))
	p.hand.append(_card("Cl"))
	scene.selected_indices = [0, 1]
	scene._refresh_ui()
	await process_frame

	# 「合成化合物」按钮：提前拦住，不进化合价面板
	scene._on_choose_compound()
	await process_frame
	_check(p.hand.size() == 2, "UI：F+Cl 点「合成化合物」被拦，手牌未减少（实际 %d 张）" % p.hand.size())
	_check(scene.step_mode == 0, "UI：被拦后停在选牌型面板（step_mode=%d）" % scene.step_mode)

	# 提示：默认不会把面板推到「确认打出」（会建议合法的族炸）
	scene.selected_indices = []
	scene._on_hint_toggled(true)
	await process_frame
	_check(scene.step_mode != 2, "UI：提示不会把 F+Cl 推到化合物面板（step_mode=%d）" % scene.step_mode)
	_check(scene.compound_selections.is_empty(), "UI：提示没有填卤素互化的化合价")

	# 开关打开后，同一组牌可以走进化合价面板
	scene.game_manager.halogen_exchange_allowed = true
	scene.selected_indices = [0, 1]
	scene._on_choose_compound()
	await process_frame
	_check(scene.step_mode == 2, "UI：开关打开后 F+Cl 可以进入化合价面板（step_mode=%d）" % scene.step_mode)
