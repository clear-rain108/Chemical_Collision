# ============================================================
# tests/verify_net_vote.gd - 化合物质疑投票（D22）端到端测试
#
# 四张牌桌各覆盖一段口径（每张桌都是「1 房主 + 2 真人客人」的真 ENet 三端）：
#   V0   规则层：质疑预检只放宽 -1 / -7，其余硬拒；白名单进指纹；驳回罚抽
#   A 桌：全票通过（V1 开票 / V2 通过落子 / V3 白名单三端一致 /
#         V6 出题人不能投 / V7 无票可投 / V8 冻结 / V9 AI 冻结 / V12 逐笔同指纹）
#   B 桌：一票反对 → 出牌撤销 + 罚抽 1 张（V4）
#   C 桌：超时不投 → 视同不通过 + 罚抽（V5）
#   D 桌：投票人掉线 → 立刻出分母，剩余全赞成照样通过（V10）
#
# 为什么每张桌都配**独立的 GameManager**：断言里的「三端同指纹」必须是各自
# 重放出来的，不能共享一个对象糊弄过去（与 verify_net_session.gd 同口径）。
#
# 关键前提：座位 0 手上必须真的有一组「化学性不合法但值得质疑」的牌。
# 做法不是硬编码牌面，而是先离线扫种子（同 seed → 同一副牌 → 三端一致），
# 找到后再把 host._seed 钉成那个值 —— 测试因此完全确定、不看运气。
#
# 运行：godot --headless --path . --script tests/verify_net_vote.gd
# ============================================================
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const PORT_A = 47852          # 全票通过
const PORT_B = 47854          # 一票否决
const PORT_C = 47856          # 超时
const PORT_D = 47858          # 投票人掉线
const CONNECT_TIMEOUT_MS = 6000
const IO_TIMEOUT_MS = 4000
const PLAYER_COUNT = 3
const COMPOUND = CardPatternsScript.CardPattern.COMPOUND

var fails: int = 0
var checks: int = 0
var events: Array = []


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
		print("ALL NET VOTE TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d NET VOTE TESTS FAILED" % [fails, checks])
	# ENet 客户端 close() 后立刻 quit 会卡在退出阶段（见 verify_net_session 的说明）
	OS.delay_msec(600)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	_part_rules()
	_part_pass()
	_part_reject()
	_part_timeout()
	_part_voter_offline()
	_finish()


# ============================================================
# 一、规则层（不联网）：质疑预检的放行面 + 白名单 + 驳回
# ============================================================
func _part_rules() -> void:
	var gm = GameManagerScript.new()
	gm.init_game(3, 0, 20250101)
	_check(gm.players.size() == 3 and gm.players[0].get_hand_count() == 8,
		"V0 开局：3 人各 8 张")

	# ① -1 配不平：普通判定拒绝，质疑预检放行（投票才有意义）
	var bad := _find_claimable(gm, 0, -1)
	_check(not bad.is_empty(), "V0 找到一组「配不平」的牌（-1）")
	if not bad.is_empty():
		var bcards: Array = bad["cards"]
		var bcv: Dictionary = bad["cv"]
		_check(int(gm.validate_play(0, bcards, bcv, COMPOUND)) == -1,
			"V0 配不平：validate_play = -1")
		_check(int(gm.validate_play_claim(0, bcards, bcv, COMPOUND)) >= 0,
			"V0 配不平：validate_play_claim 放行")

	# ② -7 卤族互化：同一入口的第二个放行口（含卤素的组合不一定在座 0 手上，扫种子）
	var hal := {}
	var hal_gm = null
	for s in range(1, 120):
		var cand = GameManagerScript.new()
		cand.init_game(3, 0, s)
		var hit := _find_claimable(cand, 0, -7)
		if not hit.is_empty():
			hal = hit
			hal_gm = cand
			break
	_check(not hal.is_empty(), "V0 找到一组「卤族互化」的牌（-7）")
	if not hal.is_empty():
		_check(int(hal_gm.validate_play(0, hal["cards"], hal["cv"], COMPOUND)) == -7,
			"V0 卤族互化：validate_play = -7")
		_check(int(hal_gm.validate_play_claim(0, hal["cards"], hal["cv"], COMPOUND)) >= 0,
			"V0 卤族互化：validate_play_claim 放行")

	# ③ -2 牌不够大：与化学无关，投票没有立场推翻 → 一律硬拒
	var gm2 = GameManagerScript.new()
	gm2.init_game(3, 0, 20250102)
	var low = _min_atomic_card(gm2.players[1].hand)
	var high = _max_atomic_card(gm2.players[0].hand)
	gm2.is_round_starter = false
	gm2.table_pattern = CardPatternsScript.CardPattern.ELEMENT
	gm2.table_cards = [low]
	gm2.table_player_index = 1
	var code2: int = int(gm2.validate_play(0, [high], {},
		CardPatternsScript.CardPattern.ELEMENT))
	var code2c: int = int(gm2.validate_play_claim(0, [high], {},
		CardPatternsScript.CardPattern.ELEMENT))
	_check(code2 == -2, "V0 牌不够大：validate_play = -2（实得 %d）" % code2)
	_check(code2c == code2, "V0 牌不够大：质疑预检照样 -2（实得 %d）" % code2c)

	# ④ -4 接不上（桌面单质不能接化合物）：同样硬拒
	var gm3 = GameManagerScript.new()
	gm3.sequence_rules_enabled = true
	gm3.init_game(3, 0, 20250103)
	var two := _pair_non_element(gm3, 0)
	if two.size() == 2:
		gm3.is_round_starter = false
		gm3.table_pattern = CardPatternsScript.CardPattern.ELEMENT
		gm3.table_cards = [gm3.players[1].hand[0]]
		gm3.table_player_index = 1
		var code4: int = int(gm3.validate_play(0, two, {}, -1))
		var code4c: int = int(gm3.validate_play_claim(0, two, {}, -1))
		_check(code4 == -4, "V0 接不上：validate_play = -4（实得 %d）" % code4)
		_check(code4c == code4, "V0 接不上：质疑预检照样 -4（实得 %d）" % code4c)
	else:
		_check(false, "V0 该种子下没找到两张不同元素的牌（测试前提失败）")

	# ⑤ 通过事件：落子 + 白名单 + 进指纹 + 重放一致
	var gm4 = GameManagerScript.new()
	gm4.init_game(3, 0, 20250104)
	var win := _find_claimable(gm4, 0, -1)
	if win.is_empty():
		_check(false, "V0 通过事件用例没找到可质疑组合（测试前提失败）")
	else:
		var pcards: Array = win["cards"]
		var uids: Array = []
		for c in pcards:
			uids.append(int(c.uid))
		var hash_before: int = gm4.state_hash()
		var ev := {"type": "compound_ruling", "by": 0, "approved": true, "uids": uids,
			"valences": win["cv"], "pattern": COMPOUND}
		_check(int(gm4.apply_event(ev)) == 0, "V0 通过事件落子成功")
		_check(gm4.table_cards.size() == pcards.size(), "V0 桌面变成被裁定的那组牌")
		_check(int(gm4.table_player_index) == 0, "V0 桌面归属 = 出题人")
		_check(gm4.is_compound_legalized(pcards), "V0 该组成进入白名单")
		_check(gm4.compound_ruling_keys().size() == 1, "V0 白名单只有 1 条")
		_check(gm4.state_hash() != hash_before, "V0 白名单进指纹（hash 变了）")

		var gm5 = GameManagerScript.new()
		gm5.init_game(3, 0, 20250104)
		var applied: int = int(gm5.replay_events([ev]))
		_check(applied == 1 and gm5.state_hash() == gm4.state_hash(),
			"V0 同一笔事件重放后指纹一致（重连 / 中途加入的基础）")

	# ⑥ 驳回事件：罚抽 1 张，桌面与白名单都不动
	var gm6 = GameManagerScript.new()
	gm6.init_game(3, 0, 20250105)
	var n0: int = gm6.players[0].get_hand_count()
	var rej := {"type": "compound_ruling", "by": 0, "approved": false, "cause": "rejected"}
	_check(int(gm6.apply_event(rej)) == 0, "V0 驳回事件应用成功")
	_check(gm6.players[0].get_hand_count() == n0 + 1,
		"V0 驳回 → 罚抽 1 张（%d → %d）" % [n0, gm6.players[0].get_hand_count()])
	_check(gm6.table_cards.is_empty(), "V0 驳回 → 桌面没有被改写")
	_check(gm6.compound_ruling_keys().is_empty(), "V0 驳回 → 白名单仍为空")


# ============================================================
# 二、A 桌：全票通过
# ============================================================
func _part_pass() -> void:
	var found := _find_seed_for_claim()
	_check(not found.is_empty(), "V1 找到一个「座位 0 有可质疑组合」的种子")
	if found.is_empty():
		return
	var peers := _open_room(PORT_A)
	var host = peers[0]["s"]
	var c1 = peers[1]["s"]
	var c2 = peers[2]["s"]
	host._seed = int(found["seed"])
	host.vote_timeout_ms = 20000
	host.start_game(PLAYER_COUNT, 0)
	var ready := _pump(peers, func(): return c1.is_playing() and c2.is_playing(), IO_TIMEOUT_MS)
	_check(ready, "V1 三端都进入对局")
	if not ready:
		_close_all(peers)
		return
	var gm = host.game
	var uids: Array = found["uids"]
	var picked: Array = gm.get_cards_by_uids(0, uids)
	_check(picked.size() == 2, "V1 主机手里确实有那两张牌")
	if picked.size() != 2:
		_close_all(peers)
		return
	var payload := {"uids": uids, "valences": found["cv"], "pattern": COMPOUND}
	var code: int = int(host.submit(NetProtocolScript.INTENT_CLAIM, payload))
	_check(code == 0, "V1 主机发起质疑 → 返回 0（已受理，实得 %d）" % code)
	_check(host.vote_open(), "V1 主机侧投票已开启")
	var synced := _pump(peers, func(): return c1.vote_open() and c2.vote_open(), IO_TIMEOUT_MS)
	_check(synced, "V1 两台客人都收到 vote_request")
	var v1: Dictionary = c1.vote_state()
	var v2: Dictionary = c2.vote_state()
	var vh: Dictionary = host.vote_state()
	_check(int(v1.get("vid", 0)) == int(vh.get("vid", 0)) and int(v2.get("vid", 0)) == int(vh.get("vid", 0)),
		"V1 三端投票号一致（vid=%d）" % int(vh.get("vid", 0)))
	_check(int(vh.get("by", -1)) == 0, "V1 出题人 = 座位 0")
	_check((v1.get("voters", []) as Array) == [1, 2], "V1 分母 = 另外两个真人（不含出题人 / 不含 AI）")
	_check(int(v1.get("total", 0)) == 2, "V1 分母大小 = 2")
	_check(String(v1.get("reason", "")) != "", "V1 开票带上了引擎的人话原因（%s）" % String(v1.get("reason", "")))
	_check(not c1.can_submit(), "V8 投票期间客人不能操作（can_submit = false）")
	_check(not host.can_submit(), "V8 投票期间主机也不能操作")
	_check(c1.am_i_voter() and c2.am_i_voter(), "V1 两台客人都被算作投票人")
	_check(not host.am_i_voter(), "V6 出题人不算投票人")
	_check(int(host.host_step_ai(2)) == 0, "V9 投票期间 host_step_ai 冻结（0 步）")

	# V8：客人试图出牌 → 主机回 -111
	c1.submit(NetProtocolScript.INTENT_PASS, {})
	var frozen := _pump(peers, func(): return _has_code(int(NetProtocolScript.ERR_VOTE_PENDING)),
		IO_TIMEOUT_MS)
	_check(frozen, "V8 投票期间任何意图都被 -111 冻结")

	# V6b：出题人自己投票 → -113
	_check(int(host.cast_vote(true)) == NetProtocolScript.ERR_NOT_VOTER,
		"V6 出题人投票 → -113")
	_check(int(host.my_vote()) == -1, "V6 出题人没有票")

	# V2：两票赞成 → 通过
	_check(int(c1.cast_vote(true)) == 0, "V2 客人A 投赞成")
	var mid := _pump(peers, func(): return int(host.vote_state().get("approve_count", 0)) == 1,
		IO_TIMEOUT_MS)
	_check(mid, "V2 主机收到第 1 票")
	_check(host.vote_open(), "V2 1/2 票时仍在等第 2 票")
	_check(int(c1.my_vote()) == 1, "V2 客人A 侧也记下了自己的票")
	_check(int(c2.cast_vote(true)) == 0, "V2 客人B 投赞成")
	var done := _pump(peers, func(): return _has_resolved(true) \
		and _count_applied("compound_ruling") >= 3, IO_TIMEOUT_MS)
	_check(done, "V2 收口：三端都收到 vote_result + compound_ruling")
	_check(not host.vote_open(), "V2 收口后投票关闭（主机）")
	_check(not c1.vote_open(), "V2 收口后投票关闭（客人A）")
	_check(gm.table_cards.size() == 2, "V2 投票通过 → 那一手真的落子（桌面 2 张）")
	_check(int(gm.table_player_index) == 0, "V2 桌面归属 = 出题人座位")
	_check(gm.is_compound_legalized(picked), "V3 白名单记入该组成（主机）")
	_check(c1.game.is_compound_legalized(picked), "V3 白名单记入该组成（客人A）")
	_check(c2.game.is_compound_legalized(picked), "V3 白名单记入该组成（客人B）")
	_check(c1.game.compound_ruling_keys() == gm.compound_ruling_keys(),
		"V3 白名单三端一致（%s）" % str(gm.compound_ruling_keys()))
	_check(c1.game.state_hash() == gm.state_hash() and c2.game.state_hash() == gm.state_hash(),
		"V12 通过后三端指纹一致")
	_check(c1.game.event_log.size() == gm.event_log.size(),
		"V12 三端事件条数一致（%d）" % gm.event_log.size())
	_check(not _has_desync(), "V12 全程没有分叉")

	# V7：没有进行中的投票时再投票
	_check(int(c1.cast_vote(true)) == NetProtocolScript.ERR_NO_VOTE,
		"V7 没有进行中的投票 → -112")
	_close_all(peers)


# ============================================================
# 三、B 桌：一票否决 → 出牌撤销 + 罚抽
# ============================================================
func _part_reject() -> void:
	var found := _find_seed_for_claim()
	if found.is_empty():
		return
	var peers := _open_room(PORT_B)
	var host = peers[0]["s"]
	var c1 = peers[1]["s"]
	var c2 = peers[2]["s"]
	host._seed = int(found["seed"])
	host.start_game(PLAYER_COUNT, 0)
	var ready := _pump(peers, func(): return c1.is_playing() and c2.is_playing(), IO_TIMEOUT_MS)
	if not ready:
		_check(false, "V4 B 桌三端开局失败")
		_close_all(peers)
		return
	var gm = host.game
	var uids: Array = found["uids"]
	var hand_before: int = gm.players[0].get_hand_count()
	var code: int = int(host.submit(NetProtocolScript.INTENT_CLAIM,
		{"uids": uids, "valences": found["cv"], "pattern": COMPOUND}))
	_check(code == 0, "V4 B 桌开票成功（实得 %d）" % code)
	var opened := _pump(peers, func(): return c2.vote_open(), IO_TIMEOUT_MS)
	_check(opened, "V4 B 桌客人收到开票")
	_check(int(c1.cast_vote(false)) == 0, "V4 客人A 投反对")
	var done := _pump(peers, func(): return _has_resolved(false) \
		and _count_applied("compound_ruling") >= 3, IO_TIMEOUT_MS)
	_check(done, "V4 反对票立即收口（不等剩下的票）")
	_check(gm.table_cards.is_empty(), "V4 否决 → 出牌撤销（桌面仍为空）")
	_check(gm.players[0].get_hand_count() == hand_before + 1,
		"V4 否决 → 罚抽 1 张（%d → %d）" % [hand_before, gm.players[0].get_hand_count()])
	_check(gm.compound_ruling_keys().is_empty(), "V4 否决 → 白名单为空")
	_check(c1.game.state_hash() == gm.state_hash() and c2.game.state_hash() == gm.state_hash(),
		"V4 罚抽后三端仍同指纹（罚抽抽的是同一份 seed 牌堆）")
	_check(not _has_desync(), "V4 全程没有分叉")
	_close_all(peers)


# ============================================================
# 四、C 桌：超时不投 → 视同不通过
# ============================================================
func _part_timeout() -> void:
	var found := _find_seed_for_claim()
	if found.is_empty():
		return
	var peers := _open_room(PORT_C)
	var host = peers[0]["s"]
	var c1 = peers[1]["s"]
	var c2 = peers[2]["s"]
	host._seed = int(found["seed"])
	host.vote_timeout_ms = 400          # 压到 400ms，等 3s 足够判超时
	host.start_game(PLAYER_COUNT, 0)
	var ready := _pump(peers, func(): return c1.is_playing() and c2.is_playing(), IO_TIMEOUT_MS)
	if not ready:
		_check(false, "V5 C 桌三端开局失败")
		_close_all(peers)
		return
	var gm = host.game
	var hand_before: int = gm.players[0].get_hand_count()
	host.submit(NetProtocolScript.INTENT_CLAIM,
		{"uids": found["uids"], "valences": found["cv"], "pattern": COMPOUND})
	_check(host.vote_open(), "V5 C 桌开票成功")
	_check(host.vote_remain_ms() > 0, "V5 开票后剩余时间 > 0")
	var done := _pump(peers, func(): return _has_resolved(false) \
		and _count_applied("compound_ruling") >= 3, 3000)
	_check(done, "V5 超时自动收口（无人投票 → 不通过）")
	_check(host.vote_remain_ms() == 0, "V5 收口后剩余时间归零")
	_check(gm.table_cards.is_empty(), "V5 超时 → 出牌撤销")
	_check(gm.players[0].get_hand_count() == hand_before + 1, "V5 超时 → 罚抽 1 张")
	_check(c1.game.state_hash() == gm.state_hash(), "V5 超时罚抽后两端同指纹")
	_close_all(peers)


# ============================================================
# 五、D 桌：投票人掉线 → 立刻出分母
# ============================================================
func _part_voter_offline() -> void:
	var found := _find_seed_for_claim()
	if found.is_empty():
		return
	var peers := _open_room(PORT_D)
	var host = peers[0]["s"]
	var c1 = peers[1]["s"]
	var c2 = peers[2]["s"]
	host._seed = int(found["seed"])
	host.start_game(PLAYER_COUNT, 0)
	var ready := _pump(peers, func(): return c1.is_playing() and c2.is_playing(), IO_TIMEOUT_MS)
	if not ready:
		_check(false, "V10 D 桌三端开局失败")
		_close_all(peers)
		return
	var gm = host.game
	host.submit(NetProtocolScript.INTENT_CLAIM,
		{"uids": found["uids"], "valences": found["cv"], "pattern": COMPOUND})
	var opened := _pump(peers, func(): return c1.vote_open() and c2.vote_open(), IO_TIMEOUT_MS)
	_check(opened and int(host.vote_state().get("total", 0)) == 2, "V10 开票时分母 = 2")
	# 客人B 掉线：主机应立刻把它移出分母（它没投过票，纯减法）
	c2.close("测试掉线")
	var dropped := _pump(peers, func(): return int(host.vote_state().get("total", -1)) == 1,
		IO_TIMEOUT_MS)
	_check(dropped, "V10 掉线者立刻出分母（2 → 1）")
	_check(host.vote_open(), "V10 分母还剩 1 人时投票继续（没有误判成 no_voter）")
	_check(int(c1.cast_vote(true)) == 0, "V10 活着的投票人投赞成")
	var done := _pump(peers, func(): return _has_resolved(true) \
		and _count_applied("compound_ruling") >= 2, IO_TIMEOUT_MS)
	_check(done, "V10 剩余投票人全赞成 → 通过（掉线者不拖住整局）")
	_check(gm.table_cards.size() == 2, "V10 通过后落子")
	_check(c1.game.state_hash() == gm.state_hash(), "V10 活着的两端同指纹")
	_check(not _has_desync(), "V10 全程没有分叉")
	_close_all(peers)


# ============================================================
# 工具
# ============================================================
func _open_room(port: int) -> Array:
	events.clear()                      # 每张桌独立记账，断言互不串味
	var host := _make_peer("HOST")
	var c1 := _make_peer("C1")
	var c2 := _make_peer("C2")
	host["s"].start_host(port, PLAYER_COUNT, "房主")
	c1["s"].start_client("127.0.0.1", port, "客人A")
	c2["s"].start_client("127.0.0.1", port, "客人B")
	var peers := [host, c1, c2]
	var seated := _pump(peers, func(): return int(c1["s"].my_seat) == 1 \
		and int(c2["s"].my_seat) == 2, CONNECT_TIMEOUT_MS)
	if not seated:
		print("WARN: 端口 %d 握手未完成（可能被占用）" % port)
	return peers


func _make_peer(tag: String) -> Dictionary:
	var gm = GameManagerScript.new()
	var tr = ENetTransportScript.new()
	var s = NetSessionScript.new()
	s.setup(gm, tr)
	s.vote_opened.connect(func(state: Dictionary):
		events.append({"t": tag, "k": "opened", "vid": int(state.get("vid", 0))}))
	s.vote_updated.connect(func(state: Dictionary):
		events.append({"t": tag, "k": "updated", "total": int(state.get("total", 0)),
			"approve": int(state.get("approve_count", 0))}))
	s.vote_resolved.connect(func(result: Dictionary):
		events.append({"t": tag, "k": "resolved",
			"approved": bool(result.get("approved", false)),
			"cause": String(result.get("cause", ""))}))
	s.state_applied.connect(func(ev, r):
		events.append({"t": tag, "k": "applied", "type": String(ev.get("type", "")),
			"by": int(ev.get("by", -1)), "result": int(r)}))
	s.intent_rejected.connect(func(seq, code):
		events.append({"t": tag, "k": "rejected", "seq": int(seq), "code": int(code)}))
	s.desync_detected.connect(func(l, h):
		events.append({"t": tag, "k": "desync", "local": int(l), "host": int(h)}))
	s.error_raised.connect(func(code, detail):
		events.append({"t": tag, "k": "error", "code": int(code), "detail": String(detail)}))
	return {"tag": tag, "gm": gm, "tr": tr, "s": s}


func _close_all(peers: Array) -> void:
	for p in peers:
		p["s"].close("测试结束")
	OS.delay_msec(150)


func _pump(peers: Array, cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for p in peers:
			p["s"].poll()
		if bool(cond.call()):
			return true
		OS.delay_msec(5)
	return bool(cond.call())


func _has_resolved(approved: bool) -> bool:
	for e in events:
		if String(e.get("k", "")) == "resolved" and bool(e.get("approved", false)) == approved:
			return true
	return false


func _has_code(code: int) -> bool:
	for e in events:
		if String(e.get("k", "")) == "rejected" and int(e.get("code", 0)) == code:
			return true
	return false


func _count_applied(ev_type: String) -> int:
	var n := 0
	for e in events:
		if String(e.get("k", "")) == "applied" and String(e.get("type", "")) == ev_type:
			n += 1
	return n


func _has_desync() -> bool:
	for e in events:
		if String(e.get("k", "")) == "desync":
			return true
	return false


# ------------------------------------------------------------
# 规则层小工具
# ------------------------------------------------------------
# 在 seat 手上找一组「普通判定 = want_code、质疑预检放行」的两张牌。
# 价态怎么来的：化合物路径要看 skip_bomb（custom_valences ≥ 2 项才跳过族炸），
# 所以给一个「一正一负」的假价态就够 —— 真判定照样会因为它配不平而拒绝。
func _find_claimable(gm, seat: int, want_code: int) -> Dictionary:
	var hand: Array = gm.players[seat].hand
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			var a = hand[i]
			var b = hand[j]
			if String(a.symbol) == String(b.symbol):
				continue
			var cv := {String(a.symbol): 1, String(b.symbol): -1}
			var pair := [a, b]
			if int(gm.validate_play(seat, pair, cv, COMPOUND)) != want_code:
				continue
			if int(gm.validate_play_claim(seat, pair, cv, COMPOUND)) < 0:
				continue
			return {"cards": pair, "cv": cv}
	return {}


# 找一个「座位 0 手上有可质疑组合」的种子。
# 扫种子的理由：牌面随机，但同 seed 一定同一副牌，于是三端 + 测试都能对上，
# 不用把某张牌 uid 硬编码进测试（换牌库就全红）。
func _find_seed_for_claim() -> Dictionary:
	for s in range(1, 160):
		var gm = GameManagerScript.new()
		gm.init_game(PLAYER_COUNT, 0, s)
		var hit := _find_claimable(gm, 0, -1)
		if hit.is_empty():
			hit = _find_claimable(gm, 0, -7)
		if hit.is_empty():
			continue
		var uids: Array = []
		for c in hit["cards"]:
			uids.append(int(c.uid))
		return {"seed": s, "uids": uids, "cv": hit["cv"]}
	return {}


func _min_atomic_card(hand: Array):
	var best = null
	for c in hand:
		if best == null or int(c.atomic_number) < int(best.atomic_number):
			best = c
	return best


func _max_atomic_card(hand: Array):
	var best = null
	for c in hand:
		if best == null or int(c.atomic_number) > int(best.atomic_number):
			best = c
	return best


# 手上两张「不同元素、detect 结果不是单质」的牌（用来构造 -4 接不上的场景）
func _pair_non_element(gm, seat: int) -> Array:
	var hand: Array = gm.players[seat].hand
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			var a = hand[i]
			var b = hand[j]
			if String(a.symbol) == String(b.symbol):
				continue
			var pat: int = CardPatternsScript.detect_pattern([a, b], false, false)
			if pat >= 0 and pat != CardPatternsScript.CardPattern.ELEMENT:
				return [a, b]
	return []





