# 验证「牌型二义性」修复：桌面牌型一律以「打出时记录的 table_pattern」为准
#   现场 Bug：Na + H 以化合物（NaH）打出 —— 牌面同时是 IA 族炸（不同元素同族）。
#   下家出合法化合物 HCl（原子序数和 10 < 12）却被判 -2「牌不够大」：
#   compare_cards() 用 detect_pattern() 重新推断桌面，把 table_pattern=COMPOUND 读成了 CLAN_BOMB，
#   于是走了「族炸压制一切」的分支。
#
#   1) compare_cards 支持显式牌型（默认 -1 = 自动检测，旧调用的语义完全不变）
#   2) 引擎：化合物压过「看着像族炸」的桌面化合物
#   3) 引擎：桌面真是族炸时，化合物仍被压制（不误伤族炸规则）
#   4) -2 的细分原因：打平 / 原子序数和不够 / 族炸张数不够 / 牌型压制
#   5) 显示：状态栏 / 桌面文本 / 全量状态都用 table_pattern，不再自相矛盾
#   6) 提示：建议过滤与引擎判定同源（不漏掉实际可出的化合物）
# 运行：Godot --headless --path . -s tests/verify_pattern_ambiguity.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const HintScript = preload("res://scripts/HintAdvisor.gd")

const ELEMENT = CardPatternsScript.CardPattern.ELEMENT
const COMPOUND = CardPatternsScript.CardPattern.COMPOUND
const CLAN_BOMB = CardPatternsScript.CardPattern.CLAN_BOMB

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
		print("ALL PATTERN AMBIGUITY TESTS PASSED")
	else:
		print("%d PATTERN AMBIGUITY TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---- 构造一张真卡（与牌库同源，保证原子序数 / 化合价一致）----
func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


func _cards(syms: Array) -> Array:
	var out: Array = []
	for s in syms:
		out.append(_card(s))
	return out


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


func _run():
	_test_compare_api()
	_test_compound_over_bomb_like_table()
	_test_bomb_still_suppresses()
	_test_reject_reasons()
	_test_hint_source()
	await _test_display_uses_table_pattern()
	_finish()


# ============================================================
# 一、compare_cards：显式牌型参数（默认 -1 保持旧语义）
# ============================================================
func _test_compare_api() -> void:
	var hcl := _cards(["H", "Cl"])      # HCl：化合物（原子序数和 18）
	var kh := _cards(["K", "H"])        # KH：化合物（20），牌面又像 IA 族炸
	var cmp_auto = CardPatternsScript.compare_cards(hcl, kh)
	_check(cmp_auto == -1,
		"对照：不传牌型时按牌面推断 → 化合物 vs 族炸 → 被压制（实际 %d，即旧 Bug 的来源）" % cmp_auto)

	_check(CardPatternsScript.compare_cards(hcl, kh, COMPOUND, COMPOUND) == 1,
		"显式 COMPOUND/COMPOUND：18 < 20 → 可压过（实际 %d）" %
		CardPatternsScript.compare_cards(hcl, kh, COMPOUND, COMPOUND))
	_check(CardPatternsScript.compare_cards(hcl, kh, COMPOUND, CLAN_BOMB) == -1,
		"显式 COMPOUND/CLAN_BOMB：族炸压制仍然生效")
	_check(CardPatternsScript.compare_cards(hcl, kh, -1, COMPOUND) == 1,
		"半显式（只给桌面牌型）也能修正")
	# 默认参数 = 旧行为：单质比大小
	_check(CardPatternsScript.compare_cards(_cards(["H"]), _cards(["Li"])) > 0,
		"默认参数下 compare_cards 行为不变（H 1 < Li 3 → H 更大）")


# 桌面摆一个「牌面看着像族炸、实际按化合物打出」的 KH（K / H 都是 IA）
# seat0 手里留一张 Ar，避免打出后手牌清空触发放毒（游戏结束会让提示直接返回空）
func _gm_compound_table(hand1: Array = ["H", "Cl"]) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 0, ["K", "H", "Ar"])
	_set_hand(gm, 1, hand1)
	# 两张不同元素同族（K / H 都是 IA）→ skip_clan_bomb=true 才能当化合物
	var r = gm.play_cards(0, _take(gm, 0, ["K", "H"]), {"K": 1, "H": -1}, COMPOUND)
	_check(r == 0, "布置：座位0 以化合物打出 KH（期望 0，实际 %d）" % r)
	_check(gm.get_table_pattern() == COMPOUND,
		"布置：table_pattern 记录为化合物（实际 %d）" % gm.get_table_pattern())
	_check(CardPatternsScript.detect_pattern(gm.table_cards) == CLAN_BOMB,
		"布置：同一批牌按牌面检测确实是 IA 族炸（二义性成立）")
	return gm



# ============================================================
# 二、引擎：合法化合物不再被误判为「牌不够大」
# ============================================================
func _test_compound_over_bomb_like_table() -> void:
	var gm = _gm_compound_table(["H", "Cl"])
	var r = gm.play_cards(1, _take(gm, 1, ["H", "Cl"]), {"H": 1, "Cl": -1}, COMPOUND)
	_check(r == 0, "下家 HCl（18）能压过桌面 KH（20）（修复前 -2，实际 %d）" % r)
	_check(gm.get_table_player_index() == 1, "HCl 成功上桌（桌面归属座位1）")
	_check(gm.get_last_reject_reason() == "", "成功出牌后不残留拒牌原因")

	# 反向：更大的化合物依然要被拒（不能因为「修 Bug」把大小规则搞没了）
	var gm2 = _gm_compound_table(["H", "Br"])
	var r2 = gm2.play_cards(1, _take(gm2, 1, ["H", "Br"]), {"H": 1, "Br": -1}, COMPOUND)
	_check(r2 == -2, "更大的 HBr（36）仍被拒 -2（实际 %d）" % r2)


# ============================================================
# 三、桌面真的是族炸 → 化合物照旧被压制
# ============================================================
# 用「已结束的接炸链」直接摆桌面状态：族炸打完后链是激活的（此时非族炸一律 -1），
# 全桌跳过才算收链，这里只验证「牌型压制」这一条判定，不重复测链流程。
func _test_bomb_still_suppresses() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(4, 3)
	_set_hand(gm, 1, ["H", "Cl"])
	gm.table_cards = _cards(["Na", "K"])
	gm.table_pattern = CLAN_BOMB
	gm.table_player_index = 0
	gm.is_round_starter = false
	gm.clan_bomb_chain_active = false

	var r1 = gm.play_cards(1, _take(gm, 1, ["H", "Cl"]), {"H": 1, "Cl": -1}, COMPOUND)
	_check(r1 == -2, "桌面是族炸时化合物仍被压制（期望 -2，实际 %d）" % r1)
	var why: String = gm.get_last_reject_reason()
	_check(why.contains("压不过"), "原因文案指明「牌型压制」（实际：%s）" % why)


# ============================================================
# 四、-2 的细分原因
# ============================================================
func _test_reject_reasons() -> void:
	# 4.1 打平：同组成同原子量 → compare 返回 0
	var gm = _gm_compound_table(["H", "Cl"])
	var r_first = gm.play_cards(1, _take(gm, 1, ["H", "Cl"]), {"H": 1, "Cl": -1}, COMPOUND)
	_check(r_first == 0, "布置：HCl 先压过 KH 上桌（实际 %d）" % r_first)
	_set_hand(gm, 2, ["H", "Cl"])
	var r_tie = gm.play_cards(2, _take(gm, 2, ["H", "Cl"]), {"H": 1, "Cl": -1}, COMPOUND)
	_check(r_tie == -2, "同组成再出一次被拒 -2（实际 %d）" % r_tie)
	var why_tie: String = gm.get_last_reject_reason()
	_check(why_tie.contains("打平"), "原因文案说明「打平」（实际：%s）" % why_tie)

	# 4.2 原子序数和不够
	var gm2 = _gm_compound_table(["H", "Br"])
	var r3 = gm2.play_cards(1, _take(gm2, 1, ["H", "Br"]), {"H": 1, "Br": -1}, COMPOUND)
	_check(r3 == -2, "HBr 36 压不过 KH 20 → -2（实际 %d）" % r3)
	var why_sum: String = gm2.get_last_reject_reason()
	_check(why_sum.contains("36") and why_sum.contains("20"),
		"原因文案给出双方原子序数和（实际：%s）" % why_sum)

	# 4.3 族炸张数不够（接炸链）
	var gm3 = GameManagerScript.new()
	gm3.init_game(4, 3)
	_set_hand(gm3, 0, ["H", "Li", "Na"])
	_set_hand(gm3, 1, ["H", "Li"])
	var rb = gm3.play_cards(0, _take(gm3, 0, ["H", "Li", "Na"]), {}, CLAN_BOMB)
	_check(rb == 0 and gm3.clan_bomb_chain_active, "布置：座位0 出 3 张 IA 族炸，接炸链激活")
	var r4 = gm3.play_cards(1, _take(gm3, 1, ["H", "Li"]), {}, CLAN_BOMB)
	_check(r4 == -2, "2 张族炸接不过 3 张（期望 -2，实际 %d）" % r4)
	var why_count: String = gm3.get_last_reject_reason()
	_check(why_count.contains("张数"), "原因文案说明族炸张数不够（实际：%s）" % why_count)


# ============================================================
# 五、提示：过滤条件与引擎同源
# ============================================================
func _test_hint_source() -> void:
	# 手牌只留 H / Cl：这两种元素不同族（不会凑出族炸），唯一能压过 KH 的就是 HCl 化合物
	var gm = _gm_compound_table(["H", "Cl", "H", "Cl"])
	gm.current_player_index = 1
	var adv: Dictionary = HintScript.suggest(gm)
	_check(not adv.is_empty(),
		"提示在「桌面是像族炸的化合物」时仍给出建议（修复前会被族炸压制过滤为空）")
	_check(int(adv.get("pattern", -1)) == COMPOUND,
		"提示建议的是化合物（实际牌型 %d）" % int(adv.get("pattern", -1)))
	var idxs: Array = adv.get("indices", [])
	_check(HintScript.is_playable(gm, idxs), "提示给出的建议本身可打出（提示与引擎同源）")


# ============================================================
# 六、显示：状态栏 / 桌面文本 / 全量状态都用 table_pattern
# ============================================================
func _test_display_uses_table_pattern() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_on_start_game")
	for _w in range(4):
		await process_frame

	var gm = scene.game_manager
	_set_hand(gm, 0, ["K", "H", "Ar"])
	var r = gm.play_cards(0, _take(gm, 0, ["K", "H"]), {"K": 1, "H": -1}, COMPOUND)
	_check(r == 0, "UI 布置：真实对局里以化合物打出 KH（实际 %d）" % r)

	scene.call("_update_status_bar")
	scene.call("_update_table_label")

	var table_txt: String = scene.table_label.text
	_check(table_txt.contains("化合物"), "桌面文本显示「化合物」（实际：%s）" % table_txt)
	_check(not table_txt.contains("族炸"), "桌面文本不再误显示「族炸」（实际：%s）" % table_txt)

	var status_txt: String = scene.status_bar_label.text
	_check(status_txt.contains("化合物"), "状态栏显示「化合物」（实际：%s）" % status_txt)

	var info_txt: String = gm.get_all_players_info()
	_check(info_txt.contains("化合物"), "全量状态文本显示「化合物」")
	_check(not info_txt.contains("族炸"), "全量状态文本不再误显示「族炸」")

	scene.queue_free()

