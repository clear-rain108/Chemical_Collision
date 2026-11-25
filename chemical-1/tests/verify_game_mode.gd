# 验证「对局模式」引擎侧（scripts/GameModes.gd ↔ GameManager 四个判定点）
#   M0 模式表：默认表 = 标准局、覆盖表只写差异、未知 id 保守退回标准局
#   M1 标准局回归：族炸照旧进冷却，冷却中再出族炸被拒 -3
#   M2 骷髅局：族炸不进冷却，冷却判定整段失效（同一手牌再出族炸成功）
#   M3 骷髅局：接炸链中「自己的冷却」不存在 → 可以立刻再炸（标准局对照组 -3）
#   M4 骷髅局：溢出化合物既不置 compound_immune，也不免疫族炸（-4 消失）
#   M5 教程局：init_tutorial() 强制回标准局（特殊模式不参与教学）
#   M7 快照 / 指纹：game_mode 进快照、进 state_hash（不同模式指纹必须不同）
#   M8 开局日志 + getter：特殊模式留痕，标准局不刷屏
# 运行：Godot --headless --path . -s tests/verify_game_mode.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const GameModesScript = preload("res://scripts/GameModes.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")

const CLAN_BOMB = CardPatternsScript.CardPattern.CLAN_BOMB
const COMPOUND = CardPatternsScript.CardPattern.COMPOUND
const STANDARD = GameModesScript.Id.STANDARD
const SKELETON = GameModesScript.Id.SKELETON

var fails: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


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


# 全新 GM（4 人局）：**先设模式再 init_game**（与开始页 / NetSession 的时序一致）
func _gm(mode: int, seat0_hand: Array = []) -> RefCounted:
	var gm = GameManagerScript.new()
	gm.game_mode = mode
	gm.init_game(4, 3)
	if not seat0_hand.is_empty():
		_set_hand(gm, 0, seat0_hand)
	return gm


# ============================================================
# M0 模式表本身
# ============================================================
func _test_m0_table() -> void:
	var ids: Array = GameModesScript.ids()
	_check(ids.size() == GameModesScript.MODE_META.size(),
		"ORDER 与实际模式数一致（%d vs %d）" % [ids.size(), GameModesScript.MODE_META.size()])
	var all_valid := true
	for id in ids:
		if not GameModesScript.is_valid(id) or GameModesScript.name_of(id) == "" \
				or GameModesScript.desc_of(id) == "":
			all_valid = false
	_check(all_valid, "每个模式都有 name / desc 且 is_valid")
	_check(GameModesScript.is_valid(99) == false and GameModesScript.is_valid(-1) == false,
		"未知模式 id 判为非法（99 / -1）")

	# 默认表 = 标准局行为（改默认表等于偷偷改标准局）
	_check(bool(GameModesScript.DEFAULT_RULES[GameModesScript.R_CLAN_BOMB_COOLING]),
		"默认表：族炸冷却开着（标准局基线）")
	_check(bool(GameModesScript.DEFAULT_RULES[GameModesScript.R_BOMB_IMMUNITY]),
		"默认表：溢出免疫开着（标准局基线）")
	_check(GameModesScript.is_standard(STANDARD),
		"标准局覆盖表为空（is_standard = true）")
	_check(not GameModesScript.is_standard(SKELETON),
		"骷髅局覆盖表非空（is_standard = false）")

	# 四条开关的四种组合
	_check(GameModesScript.cooling_enabled(STANDARD) and GameModesScript.immunity_enabled(STANDARD),
		"标准局：冷却 / 免疫全开")
	_check(not GameModesScript.cooling_enabled(SKELETON),
		"骷髅局：冷却关")
	_check(not GameModesScript.immunity_enabled(SKELETON),
		"骷髅局：溢出免疫关")

	# 未知 id / 未知键都必须「保守」：退回默认（= 标准局），绝不放水
	_check(GameModesScript.rule(99, GameModesScript.R_CLAN_BOMB_COOLING),
		"未知模式 id → 退回默认（冷却仍开）")
	_check(GameModesScript.rule(SKELETON, "不存在的规则键"),
		"覆盖表缺键 → 退回默认（true）")
	_check(GameModesScript.name_of(99) == GameModesScript.name_of(STANDARD),
		"未知模式 id 的显示名兜底为标准局（%s）" % GameModesScript.name_of(99))

	# 摘要文案
	_check(GameModesScript.summary_of(STANDARD) == "",
		"标准局摘要为空（不刷屏）")
	var sk: String = GameModesScript.summary_of(SKELETON)
	_check(sk.find("族炸无冷却") >= 0 and sk.find("溢出化合物不免疫族炸") >= 0,
		"骷髅局摘要写清两条差异（实际: %s）" % sk)


# ============================================================
# M1 标准局回归：冷却照旧
# ============================================================
func _test_m1_standard_cooling() -> void:
	var gm = _gm(STANDARD, ["F", "Cl", "Br", "I"])
	var r1: int = gm.play_cards(0, _take(gm, 0, ["F", "Cl"]), {}, CLAN_BOMB)
	_check(r1 == 0, "标准局：F+Cl 族炸可以打出（实际 %d）" % r1)
	_check(gm.players[0].clan_bomb_cooling, "标准局：族炸后进入 ❄ 冷却")
	_check(_pass_until(gm, 0), "布置：全员不接炸 → 牌权回到座位 0")
	var r2: int = gm.play_cards(0, _take(gm, 0, ["Br", "I"]), {}, CLAN_BOMB)
	_check(r2 == -3, "标准局：冷却中再出族炸被拒 -3（实际 %d）" % r2)
	_check(gm.players[0].get_hand_count() == 2,
		"标准局：被拒后手牌不变（实际 %d）" % gm.players[0].get_hand_count())


# ============================================================
# M2 骷髅局：族炸不产生冷却
# ============================================================
func _test_m2_skeleton_no_cooling() -> void:
	var gm = _gm(SKELETON, ["F", "Cl", "Br", "I"])
	var r1: int = gm.play_cards(0, _take(gm, 0, ["F", "Cl"]), {}, CLAN_BOMB)
	_check(r1 == 0, "骷髅局：F+Cl 族炸可以打出（实际 %d）" % r1)
	_check(not gm.players[0].clan_bomb_cooling, "骷髅局：族炸后**不进**冷却")
	_check(gm.clan_bomb_chain_active and gm.clan_bomb_owner == 0,
		"骷髅局：族炸仍会开接炸链（抢牌权保留）")
	_check(_pass_until(gm, 0), "布置：全员不接炸 → 牌权回到座位 0")
	var r2: int = gm.play_cards(0, _take(gm, 0, ["Br", "I"]), {}, CLAN_BOMB)
	_check(r2 == 0, "骷髅局：自由出牌时可立刻再出族炸（实际 %d）" % r2)
	_check(not gm.players[0].clan_bomb_cooling, "骷髅局：第二次族炸后依然无冷却")


# ============================================================
# M3 骷髅局：接炸链里「自己的冷却」不存在
#   标准局同一局面必然 -3（冷却），骷髅局应当能立刻再炸
# ============================================================
func _chain_scenario(mode: int) -> Array:
	# 座位0 手牌全是 1 族（H/Li/Na/K）→ 先出 2 张，再出 4 张（> 座位1 的 3 张）
	var gm = _gm(mode, ["H", "Li", "H", "Li", "Na", "K"])
	_set_hand(gm, 1, ["He", "Ne", "Ar", "Na", "K"])
	var r1: int = gm.play_cards(0, _take(gm, 0, ["H", "Li"]), {}, CLAN_BOMB)
	# 座位1 用 3 张 0 族接炸（3 张 > 2 张）→ 链主人变成座位1
	var r2: int = gm.play_cards(1, _take(gm, 1, ["He", "Ne", "Ar"]), {}, CLAN_BOMB)
	# 座位2 / 3 跳过 → 轮询回到座位0（链仍激活）
	if gm.clan_bomb_chain_active and gm.current_player_index != 0:
		gm.player_pass(gm.current_player_index)
	if gm.clan_bomb_chain_active and gm.current_player_index != 0:
		gm.player_pass(gm.current_player_index)
	var back_to_0: bool = gm.clan_bomb_chain_active and gm.current_player_index == 0
	return [gm, r1, r2, back_to_0]


func _test_m3_chain_intercept() -> void:
	var st: Array = _chain_scenario(STANDARD)
	var gm_s = st[0]
	_check(int(st[1]) == 0 and int(st[2]) == 0,
		"布置（标准局）：两次族炸都成立（%d / %d）" % [int(st[1]), int(st[2])])
	_check(bool(st[3]), "布置（标准局）：链仍激活且轮到座位 0")
	_check(gm_s.players[0].clan_bomb_cooling, "标准局：链中座位 0 处于冷却")
	var rs: int = gm_s.play_cards(0, _take(gm_s, 0, ["H", "Li", "Na", "K"]), {}, CLAN_BOMB)
	_check(rs == -3, "标准局：链中冷却者接炸被拒 -3（实际 %d）" % rs)

	var sk: Array = _chain_scenario(SKELETON)
	var gm_k = sk[0]
	_check(int(sk[1]) == 0 and int(sk[2]) == 0,
		"布置（骷髅局）：两次族炸都成立（%d / %d）" % [int(sk[1]), int(sk[2])])
	_check(bool(sk[3]), "布置（骷髅局）：链仍激活且轮到座位 0")
	_check(not gm_k.players[0].clan_bomb_cooling, "骷髅局：链中座位 0 无冷却")
	var rk: int = gm_k.play_cards(0, _take(gm_k, 0, ["H", "Li", "Na", "K"]), {}, CLAN_BOMB)
	_check(rk == 0, "骷髅局：链中可立刻用更大的族炸接炸（实际 %d）" % rk)
	_check(gm_k.players[0].get_hand_count() == 0,
		"骷髅局：接炸后手牌打空（实际 %d）" % gm_k.players[0].get_hand_count())


# ============================================================
# M4 骷髅局：溢出化合物不再免疫族炸
#   两个半边分别验：① play_cards 不再置 compound_immune
#                  ② _evaluate_play 不再因 compound_immune 拒族炸（-4 消失）
# ============================================================
func _test_m4_overflow_immunity() -> void:
	# ① 置位侧
	var st = _gm(STANDARD, ["P", "P", "O", "O", "O", "O", "O"])
	var r_st: int = st.play_cards(0, st.players[0].hand.duplicate(), {}, COMPOUND)
	_check(r_st == 0 and st.compound_immune,
		"标准局：P2O5（7 原子 ≥ 4 人）置溢出免疫（%d / %s）" % [r_st, str(st.compound_immune)])

	var sk = _gm(SKELETON, ["P", "P", "O", "O", "O", "O", "O"])
	var r_sk: int = sk.play_cards(0, sk.players[0].hand.duplicate(), {}, COMPOUND)
	_check(r_sk == 0, "骷髅局：P2O5 依然可以正常打出（实际 %d）" % r_sk)
	_check(not sk.compound_immune, "骷髅局：P2O5 不再置溢出免疫")

	# ② 判定侧：直接摆好「桌上有溢出化合物」的状态（compound_immune=true）
	var st2 = _gm(STANDARD, ["F", "Cl", "Br", "I"])
	st2.compound_immune = true
	var b_st: int = st2.play_cards(0, st2.players[0].hand.duplicate(), {}, CLAN_BOMB)
	_check(b_st == -4, "标准局：溢出免疫时族炸被拒 -4（实际 %d）" % b_st)

	var sk2 = _gm(SKELETON, ["F", "Cl", "Br", "I"])
	sk2.compound_immune = true
	var b_sk: int = sk2.play_cards(0, sk2.players[0].hand.duplicate(), {}, CLAN_BOMB)
	_check(b_sk == 0, "骷髅局：溢出免疫开启也不挡族炸（实际 %d）" % b_sk)
	_check(sk2.players[0].get_hand_count() == 0,
		"骷髅局：族炸真的打出去了（手牌 %d）" % sk2.players[0].get_hand_count())


# ============================================================
# M5 教程局强制标准模式
# ============================================================
func _test_m5_tutorial_forces_standard() -> void:
	var gm = GameManagerScript.new()
	gm.game_mode = SKELETON
	var ok: bool = gm.init_tutorial(1)
	_check(ok, "布置：第一关教程可以正常初始化")
	_check(gm.get_game_mode() == STANDARD,
		"教程局：模式被强制回标准局（实际 %d）" % gm.get_game_mode())
	_check(gm.is_standard_game_mode(), "教程局：is_standard_game_mode() = true")
	_check(GameModesScript.cooling_enabled(gm.get_game_mode()),
		"教程局：冷却规则按标准局生效")


# ============================================================
# M7 快照 / 一致性指纹
# ============================================================
func _test_m7_snapshot_hash() -> void:
	var gm = _gm(STANDARD)
	_check(int(gm.to_snapshot().get("game_mode", -1)) == STANDARD,
		"快照带上 game_mode（标准局 = %d）" % int(gm.to_snapshot().get("game_mode", -1)))
	var h1: int = gm.state_hash()
	_check(gm.state_hash() == h1, "指纹稳定：同一局面连算两次一致")
	_check(gm._canonical_string().find("mode=0") >= 0,
		"指纹串含 mode=0（规则开关必须进指纹）")

	gm.game_mode = SKELETON
	var h2: int = gm.state_hash()
	_check(gm._canonical_string().find("mode=1") >= 0, "指纹串含 mode=1")
	_check(h2 != h1, "同一局面只改模式 → 指纹立刻变（否则第一颗族炸才炸 -109）")

	gm.game_mode = STANDARD
	_check(gm.state_hash() == h1, "模式改回原值 → 指纹回到原值（无隐藏随机源）")

	var gm2 = _gm(SKELETON)
	_check(int(gm2.to_snapshot().get("game_mode", -1)) == SKELETON,
		"快照跟随模式（骷髅局 = %d）" % int(gm2.to_snapshot().get("game_mode", -1)))


# ============================================================
# M8 开局日志 / getter
# ============================================================
func _log_text(gm) -> String:
	var out: String = ""
	for line in gm.log_messages:
		out += str(line) + "\n"
	return out


func _test_m8_log_and_getters() -> void:
	var gm_st = _gm(STANDARD)
	var txt_st: String = _log_text(gm_st)
	_check(txt_st.find("【特殊模式】") < 0, "标准局：开局日志不出现「特殊模式」")
	_check(gm_st.get_game_mode_name() == "标准对局",
		"标准局：显示名 = 标准对局（实际 %s）" % gm_st.get_game_mode_name())
	_check(gm_st.is_standard_game_mode(), "标准局：is_standard_game_mode() = true")
	_check(gm_st.get_game_mode_summary() == "", "标准局：摘要为空（不刷屏）")

	var gm_sk = _gm(SKELETON)
	_check(gm_sk.get_game_mode() == SKELETON,
		"init_game 不重置模式（实际 %d）" % gm_sk.get_game_mode())
	var txt_sk: String = _log_text(gm_sk)
	_check(txt_sk.find("【特殊模式】") >= 0, "骷髅局：开局日志留痕")
	_check(txt_sk.find("骷髅炸金服") >= 0 and txt_sk.find("族炸无冷却") >= 0,
		"骷髅局：日志写清模式名与差异（实际含「骷髅炸金服」/「族炸无冷却」）")
	_check(gm_sk.get_game_mode_name() == "骷髅炸金服",
		"骷髅局：显示名 = 骷髅炸金服（实际 %s）" % gm_sk.get_game_mode_name())
	_check(not gm_sk.is_standard_game_mode(), "骷髅局：is_standard_game_mode() = false")
	_check(gm_sk.get_game_mode_summary() == GameModesScript.summary_of(SKELETON),
		"骷髅局：摘要与模式表一致（实际 %s）" % gm_sk.get_game_mode_summary())


# ============================================================
# M6 联机：config 下发 + 两端指纹一致
#   不需要真 transport：直接验 _make_config / _take_config / _apply_config
#   这条链 —— 模式漏传的后果不是当场报错，而是第一颗族炸才爆 -109。
# ============================================================
func _test_m6_net_config() -> void:
	_check(NetProtocolScript.PROTO_VERSION >= 4,
		"PROTO_VERSION ≥ 4（模式进 config 必须升版本，实际 %d）" % NetProtocolScript.PROTO_VERSION)

	var host_game = _gm(SKELETON)
	var host = NetSessionScript.new()
	host.game = host_game
	var cfg: Dictionary = host._make_config()
	_check(int(cfg.get("game_mode", -1)) == SKELETON,
		"主机 _make_config 带上 game_mode（实际 %d）" % int(cfg.get("game_mode", -1)))

	# 客人侧落地
	var client = NetSessionScript.new()
	var client_game = GameManagerScript.new()
	client.game = client_game
	client._take_config(cfg)
	client._apply_config()
	_check(client_game.get_game_mode() == SKELETON,
		"客人 _apply_config 落地模式（实际 %d）" % client_game.get_game_mode())
	_check(client_game.get_game_mode_summary() == host_game.get_game_mode_summary(),
		"两端模式摘要一致（%s）" % client_game.get_game_mode_summary())

	# 脏值 / 缺键兜底（宁保守：退回标准局）
	var bad = NetSessionScript.new()
	var bad_game = GameManagerScript.new()
	bad.game = bad_game
	bad._take_config({"game_mode": 99})
	bad._apply_config()
	_check(bad_game.get_game_mode() == STANDARD,
		"脏 game_mode=99 → 退回标准局（实际 %d）" % bad_game.get_game_mode())

	var old = NetSessionScript.new()
	var old_game = GameManagerScript.new()
	old.game = old_game
	old._take_config({"organic_rules_enabled": true})
	old._apply_config()
	_check(old_game.get_game_mode() == STANDARD,
		"缺 game_mode 键 → 标准局（实际 %d）" % old_game.get_game_mode())

	# 端到端：同 seed + 同 config → 两端指纹逐位一致（mode= 是最后一环）
	var seed_value: int = 424242
	var hg = GameManagerScript.new()
	hg.game_mode = SKELETON
	hg.init_game(4, 3, seed_value)
	var hsess = NetSessionScript.new()
	hsess.game = hg
	var cfg2: Dictionary = hsess._make_config()

	var cg = GameManagerScript.new()
	var csess = NetSessionScript.new()
	csess.game = cg
	csess._take_config(cfg2)
	csess._seed = seed_value
	csess._player_count = 4
	csess._ai_count = 3
	var ok: bool = csess._apply_config_and_init()
	_check(ok, "客人按 config + seed 初始化成功")
	_check(cg.state_hash() == hg.state_hash(),
		"两端指纹一致（%d vs %d）" % [cg.state_hash(), hg.state_hash()])
	_check(cg.get_game_mode() == SKELETON,
		"客人初始化后仍是骷髅局（实际 %d）" % cg.get_game_mode())


# ============================================================
# M9 UI 冒烟：开始页入口 → 模式小页 → 开局 → 状态栏 / 结算页
#   这一层只验「模式有没有一路传到玩家眼前」，规则正确性由 M1~M4 兜。
# ============================================================
func _test_m9_ui() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var card = scene.start_page.get_node_or_null("SettingsCard")
	_check(card != null, "设置卡存在")
	var entry = scene._start_child("ModeEntryBtn")
	_check(entry != null, "设置卡里有「对局模式」入口")
	_check(entry != null and card != null
		and Rect2(Vector2.ZERO, card.size).encloses(Rect2(entry.position, entry.size)),
		"入口完整落在设置卡内（%s）" % (str(entry.position) if entry else ""))
	var sum = scene._start_child("ModeSummary")
	_check(sum != null and sum.text == "标准对局",
		"默认摘要 = 标准对局（实际「%s」）" % (sum.text if sum else ""))

	var page = scene._start_child("ModePage")
	_check(page != null and not page.visible, "模式小页存在且默认隐藏")
	if entry == null:
		_finish()
		return
	entry.pressed.emit()
	await process_frame
	_check(page != null and page.visible, "点入口打开模式小页")
	var sk_btn = scene._start_child("ModeChoice_%d" % SKELETON)
	var st_btn = scene._start_child("ModeChoice_%d" % STANDARD)
	_check(sk_btn != null and st_btn != null, "两个候选卡都在页内")

	sk_btn.button_pressed = true
	await process_frame
	_check(scene._selected_game_mode() == SKELETON,
		"选中骷髅炸金服（实际 %d）" % scene._selected_game_mode())
	_check(sum != null and sum.text.find("骷髅炸金服") >= 0,
		"开始页摘要跟着变（实际「%s」）" % (sum.text if sum else ""))
	_check(st_btn != null and not st_btn.button_pressed, "单选互斥：标准卡已弹起")
	scene._start_child("ModeDoneBtn").pressed.emit()
	await process_frame
	_check(page != null and not page.visible, "点「完成」关闭小页")

	# 开局：模式必须落到 GameManager（init_game 不许把它重置掉）
	scene._on_start_game()
	await process_frame
	_check(scene.game_manager != null, "骷髅局：开局成功")
	if scene.game_manager == null:
		_finish()
		return
	_check(scene.game_manager.get_game_mode() == SKELETON,
		"开局后 game_manager 是骷髅局（实际 %d）" % scene.game_manager.get_game_mode())
	var bar_text: String = scene.status_bar_label.text if scene.status_bar_label else ""
	_check(bar_text.find("骷髅炸金服") >= 0, "状态栏挂上模式名（实际「%s」）" % bar_text)
	var info_text: String = scene.info_label.text if scene.info_label else ""
	_check(info_text.find("【特殊模式】") >= 0, "玩家链加一行【特殊模式】（实际「%s」）" % info_text)

	# 结算页：非标准局必须自己说明白，玩家回看才知道这局规则不同
	scene._show_end_page("")
	await process_frame
	var note = scene.end_page.get_node_or_null("EndCard/EndModeNote")
	_check(note != null and note.text.find("骷髅炸金服") >= 0,
		"结算页写明对局模式（实际「%s」）" % (note.text if note else ""))
	scene._show_start_page()
	await process_frame

	# 切回标准局：下一局界面必须干净（不多一个字，老玩家零感知）
	scene.set_game_mode(STANDARD)
	await process_frame
	_check(sum != null and sum.text == "标准对局", "切回标准后摘要还原（实际「%s」）" % (sum.text if sum else ""))
	scene._on_start_game()
	await process_frame
	_check(scene.game_manager.get_game_mode() == STANDARD,
		"标准局：game_manager.game_mode = 0（实际 %d）" % scene.game_manager.get_game_mode())
	var bar2: String = scene.status_bar_label.text if scene.status_bar_label else ""
	_check(bar2.find("模式 ") < 0, "标准局状态栏不挂模式名（实际「%s」）" % bar2)
	var info2: String = scene.info_label.text if scene.info_label else ""
	_check(info2.find("【特殊模式】") < 0, "标准局没有【特殊模式】行（实际「%s」）" % info2)
	scene.queue_free()


func _finish() -> void:
	if fails == 0:
		print("ALL GAME_MODE TESTS PASSED")
	else:
		print("%d GAME_MODE TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	print("== M0 模式表 ==")
	_test_m0_table()
	print("== M1 标准局：冷却回归 ==")
	_test_m1_standard_cooling()
	print("== M2 骷髅局：无冷却 ==")
	_test_m2_skeleton_no_cooling()
	print("== M3 骷髅局：链中可再炸 ==")
	_test_m3_chain_intercept()
	print("== M4 骷髅局：溢出免疫关闭 ==")
	_test_m4_overflow_immunity()
	print("== M5 教程局强制标准 ==")
	_test_m5_tutorial_forces_standard()
	print("== M6 联机：config 下发 / 指纹一致 ==")
	_test_m6_net_config()
	print("== M7 快照 / 指纹 ==")
	_test_m7_snapshot_hash()
	print("== M8 开局日志 / getter ==")
	_test_m8_log_and_getters()
	print("== M9 UI：开始页 → 模式页 → 状态栏 / 结算页 ==")
	await _test_m9_ui()
	_finish()



