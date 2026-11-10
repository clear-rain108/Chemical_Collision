# 验证动作路由层（P11-C1-c Step 1 ActionRouter）
#   覆盖：
#     A. 单机等价性 —— 同 seed 双 GameManager 对拍，每一步的返回码 / state_hash 必须相同
#        （这是重构红线：单机行为一旦变了，41 套既有测试就全得跟着改）
#     B. 联机语义   —— 客人提交后本地不落子、等 applied；越权被主机拒；非法牌本地就不发包
#
# 为什么用真实 ENet：ActionRouter 的联机分支必须经过真实的 submit → 主机裁决 → applied
# 这条链路，「已发出 / 已裁决」的时序只有在真传输上才测得出（Loopback 一对一也不行）。
#
# 注意：联机会话的 seed 由主机每次开局随机挑，所以 B 段的手牌逐次不同 ——
# 「这一手有没有牌可出」的分支可能变，断言数量因此设计成恒定的（不按数据增减 check）。
#
# 运行：godot --headless --path . --script tests/verify_action_router.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const ActionRouterScript = preload("res://scripts/net/ActionRouter.gd")
const NetSessionScript = preload("res://scripts/net/NetSession.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const ENetTransportScript = preload("res://scripts/net/ENetTransport.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

const PORT = 47831                  # 与 verify_net_session（47821/47824）错开
const CONNECT_TIMEOUT_MS = 5000
const IO_TIMEOUT_MS = 3000
const SEED = 20261110

var fails: int = 0
var checks: int = 0


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
		print("ALL ACTION ROUTER TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d ACTION ROUTER TESTS FAILED" % [fails, checks])
	# ENet 客户端 close() 后异步收尾，立刻 quit() 会卡在退出阶段（附录 C.5）
	OS.delay_msec(600)
	quit(1 if fails > 0 else 0)


# ============================================================
# 工具
# ============================================================
# 按 uid 在某个座位的手牌里找牌对象（两端的牌是不同的对象，只能用 uid 对应）
func _card_by_uid(gm, seat: int, uid: int):
	if seat < 0 or seat >= gm.players.size():
		return null
	for c in gm.players[seat].hand:
		if int(c.uid) == uid:
			return c
	return null


# 该座位手牌里第一张「单张就能出」的牌（桌面万一是化合物就可能一张都出不了）
func _pick_playable(gm, seat: int):
	if seat < 0 or seat >= gm.players.size():
		return null
	for c in gm.players[seat].hand:
		if int(gm.validate_play(seat, [c])) >= 0:
			return c
	return null


# 找一组「auto_play 一定能出、且不是顺序牌」的牌（1~3 张）
# 为什么要限定 code == 0：code == 1 会打开两阶段的指定牌型窗口，
# 后续断言（无待处理才能收到 -105）就被搅乱了。
func _pick_auto_set(gm, seat: int) -> Array:
	if seat < 0 or seat >= gm.players.size():
		return []
	var hand: Array = gm.players[seat].hand
	var n := hand.size()
	for i in range(n):
		if _auto_ok(gm, seat, [hand[i]]):
			return [hand[i]]
	for i in range(n):
		for j in range(i + 1, n):
			if _auto_ok(gm, seat, [hand[i], hand[j]]):
				return [hand[i], hand[j]]
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				if _auto_ok(gm, seat, [hand[i], hand[j], hand[k]]):
					return [hand[i], hand[j], hand[k]]
	return []


func _auto_ok(gm, seat: int, cards: Array) -> bool:
	var plan: Dictionary = gm.auto_play_preview(seat, cards)
	if int(plan.get("code", -1)) != 0:
		return false
	return int(plan.get("pattern", -1)) != CardPatternsScript.CardPattern.SEQUENCE


func _make_peer() -> Dictionary:
	var gm = GameManagerScript.new()
	var tr = ENetTransportScript.new()
	var s = NetSessionScript.new()
	s.setup(gm, tr)
	return {"gm": gm, "tr": tr, "s": s}


func _pump(peers: Array, cond: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for p in peers:
			p["s"].poll()
		if bool(cond.call()):
			return true
		OS.delay_msec(3)
	return false


# 三端事件日志条数是否已对齐（内联 lambda 不能跨行，所以抽成函数）
func _logs_aligned(host: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var n: int = int(host["gm"].event_log.size())
	return int(a["gm"].event_log.size()) == n and int(b["gm"].event_log.size()) == n


func _run() -> void:
	_part_single()
	_part_online()
	_finish()


# ============================================================
# A. 单机等价性（session == null）：与直调 GameManager 逐步对拍
# ============================================================
func _part_single() -> void:
	var gm_a = GameManagerScript.new()      # 直调参照
	var gm_b = GameManagerScript.new()      # 走 ActionRouter
	_check(bool(gm_a.init_game(3, 0, SEED)), "A1 参照实例 init_game 成功")
	_check(bool(gm_b.init_game(3, 0, SEED)), "A1 路由实例 init_game 成功")

	var r = ActionRouterScript.new()
	r.setup(gm_b)
	_check(not r.is_online(), "A1 单机：is_online() = false")
	_check(not r.has_session(), "A1 单机：has_session() = false")
	_check(r.local_seat() == gm_b.current_player_index, "A1 单机：local_seat() 跟随当前行动者")
	_check(not r.awaiting_reply(), "A1 单机：从不出现「已发出」状态")
	_check(r.can_act(), "A1 单机：can_act() = true")
	_check(gm_a.state_hash() == gm_b.state_hash(), "A1 双实例开局指纹一致（对拍前提）")

	# 四类动作轮转，逐步比对「返回码 + 指纹」
	var steps := 0
	var code_mismatch := 0
	var hash_mismatch := 0
	for i in range(16):
		if gm_a.is_game_over():
			break
		var seat: int = gm_a.current_player_index
		var card = _pick_playable(gm_a, seat)
		var code_a: int = 0
		var code_b: int = 0
		var op := ""
		var mode: int = i % 4
		if card == null:
			mode = 2                       # 没有能出的单张 → 跳过（保证循环一定推进）
		if mode == 0:
			var cb0 = _card_by_uid(gm_b, seat, int(card.uid))
			code_a = int(gm_a.play_cards(seat, [card]))
			code_b = int(r.play([cb0]))
			op = "play"
		elif mode == 1:
			var cb1 = _card_by_uid(gm_b, seat, int(card.uid))
			code_a = int(gm_a.auto_play(seat, [card]))
			code_b = int(r.auto_play([cb1]))
			op = "auto_play"
		elif mode == 2:
			gm_a.player_pass(seat)
			code_b = int(r.pass_turn())
			op = "pass"
		else:
			var cb3 = _card_by_uid(gm_b, seat, int(card.uid))
			gm_a.player_discard_and_pass(seat, card)
			code_b = int(r.discard_and_pass(cb3))
			op = "discard_pass"
		steps += 1
		if code_a != code_b:
			code_mismatch += 1
			print("  [A2] 码不一致 %s seat=%d 直调=%d 路由=%d" % [op, seat, code_a, code_b])
		if gm_a.state_hash() != gm_b.state_hash():
			hash_mismatch += 1
			print("  [A2] 指纹不一致 %s seat=%d" % [op, seat])

	_check(steps >= 8, "A2 对拍走满 %d 步" % steps)
	_check(code_mismatch == 0, "A2 每一步返回码都与直调一致（不一致 %d 次）" % code_mismatch)
	_check(hash_mismatch == 0, "A2 每一步 state_hash 都与直调一致（不一致 %d 次）" % hash_mismatch)
	_check(gm_a.turn_count == gm_b.turn_count,
		"A2 回合数一致（%d / %d）" % [gm_a.turn_count, gm_b.turn_count])

	# 非法出牌：空选牌（两侧都不改局面、返回码相同）
	var hash_before := gm_a.state_hash()
	var bad_a: int = int(gm_a.play_cards(gm_a.current_player_index, []))
	var bad_b: int = int(r.play([]))
	_check(bad_a == bad_b, "A3 非法出牌两侧同码（直调 %d / 路由 %d）" % [bad_a, bad_b])
	_check(gm_a.state_hash() == hash_before and gm_b.state_hash() == hash_before,
		"A3 非法出牌不改局面")
	_check(r.last_code() == bad_b, "A3 last_code() 与返回值一致")

	_check(ActionRouterScript.describe_code(-1) != ""
		and ActionRouterScript.describe_code(NetProtocolScript.ERR_DESYNC) != "",
		"A4 describe_code 同时覆盖规则码与协议码")
	_check(ActionRouterScript.describe_code(0) == "", "A4 describe_code(0) 为空串（成功不提示）")

	# 两阶段两方法：单机直写，局面必须同步
	var pat: int = CardPatternsScript.CardPattern.ELEMENT
	gm_a.set_sequence_constraint(pat)
	var pick_code: int = int(r.pick_sequence(pat))
	_check(pick_code == 0 and gm_a.state_hash() == gm_b.state_hash(),
		"A5 pick_sequence 等价 set_sequence_constraint")
	gm_a.sequence_constraint_active = false
	gm_a.sequence_constraint = -1
	gm_a.sequence_constraint_target = -1
	gm_a.next_turn()
	var skip_code: int = int(r.skip_sequence())
	_check(skip_code == 0 and gm_a.state_hash() == gm_b.state_hash(),
		"A5 skip_sequence 等价 UI「跳过指定」")


# ============================================================
# B. 联机语义：已发出 / 已裁决 / 被拒 / 本地预检不发包
# ============================================================
func _part_online() -> void:
	var host = _make_peer()
	var cli = _make_peer()
	var cli2 = _make_peer()          # 第三个真人：让牌权能转回房主（GameManager 最少 3 人）
	var peers := [host, cli, cli2]

	_check(int(host["s"].start_host(PORT, 3, "房主")) == 0, "B1 房主监听 %d 成功" % PORT)
	_check(int(cli["s"].start_client("127.0.0.1", PORT, "客人A")) == 0, "B1 客人A 发起连接")
	_check(int(cli2["s"].start_client("127.0.0.1", PORT, "客人B")) == 0, "B1 客人B 发起连接")
	_check(_pump(peers, func(): return cli["s"].my_seat == 1 and cli2["s"].my_seat == 2,
		CONNECT_TIMEOUT_MS), "B1 两台客人拿到座位 1 / 2")
	_check(int(host["s"].start_game(3, 0)) == 0, "B1 房主 start_game（3 人类 / 0 AI）")
	_check(_pump(peers, func(): return cli["s"].is_playing() and cli2["s"].is_playing(), IO_TIMEOUT_MS),
		"B1 两台客人都进入 PLAYING")
	_check(host["gm"].current_player_index == 0, "B1 首手轮到房主（座位 0）")

	var rh = ActionRouterScript.new()
	rh.setup(host["gm"], host["s"])
	var rc = ActionRouterScript.new()
	rc.setup(cli["gm"], cli["s"])
	var r2 = ActionRouterScript.new()
	r2.setup(cli2["gm"], cli2["s"])
	_check(rh.is_online() and rc.is_online() and r2.is_online(), "B2 三端 is_online() = true")
	_check(rh.local_seat() == 0 and rc.local_seat() == 1 and r2.local_seat() == 2,
		"B2 三端本地座位 0 / 1 / 2")
	_check(rh.can_act() and rc.can_act() and r2.can_act(), "B2 三端 can_act() = true")
	_check(not rc.awaiting_reply(), "B2 起始没有待裁决意图")

	# ---- B3 主机出牌：当场裁决（返回值即规则码）----
	var card_h = _pick_playable(host["gm"], 0)
	_check(card_h != null, "B3 主机手里有可出的单张")
	var code_h: int = int(rh.play([card_h]))
	_check(code_h >= 0, "B3 主机 play 返回规则码（%d，不是「已发出」）" % code_h)
	_check(not rh.awaiting_reply(), "B3 主机不进入「已发出」状态")
	_pump(peers, func(): return cli["gm"].event_log.size() == host["gm"].event_log.size(),
		IO_TIMEOUT_MS)
	_check(cli["gm"].event_log.size() == host["gm"].event_log.size(),
		"B3 客人同步到主机的事件（%d 条）" % cli["gm"].event_log.size())
	_check(host["gm"].state_hash() == cli["gm"].state_hash(), "B3 裁决后两端指纹一致")

	# ---- B4 客人出牌：0 = 已发出，本地不落子 ----
	_check(cli["gm"].current_player_index == 1, "B4 牌权已交到客人（座位 1）")
	var hash_before := int(cli["gm"].state_hash())
	var play_set: Array = []
	var single = _pick_playable(cli["gm"], 1)
	if single != null:
		play_set = [single]
		_check(int(rc.play(play_set)) == 0, "B4 客人 play 返回 0（= 已发出，不是「已成功」）")
	else:
		play_set = _pick_auto_set(cli["gm"], 1)
		if not play_set.is_empty():
			_check(int(rc.auto_play(play_set)) == 0, "B4 客人 auto_play 返回 0（已发出）")
		else:
			_check(int(rc.pass_turn()) == 0, "B4 客人无牌可出 → pass 返回 0（已发出）")
	_check(rc.awaiting_reply(), "B4 awaiting_reply() = true")
	if play_set.is_empty():
		_check(rc.awaiting_type() == NetProtocolScript.INTENT_PASS, "B4 awaiting_type = pass")
		_check(rc.awaiting_uids().is_empty(), "B4 pass 意图不带 uid")
	else:
		_check(rc.awaiting_type() == NetProtocolScript.INTENT_PLAY, "B4 awaiting_type = play")
		var want_uids: Array = []
		for c in play_set:
			want_uids.append(int(c.uid))
		_check(rc.awaiting_uids() == want_uids,
			"B4 awaiting_uids 记录了本笔 %d 张牌的 uid" % want_uids.size())
	_check(int(cli["gm"].state_hash()) == hash_before, "B4 裁决前客人本地局面不变（绝不抢先落子）")
	_check(_pump(peers, func(): return not rc.awaiting_reply(), IO_TIMEOUT_MS),
		"B4 收到 applied 后解除等待")
	_check(rc.last_code() >= 0, "B4 last_code 为 applied 的结果码（%d）" % rc.last_code())
	_check(_pump(peers, func(): return host["gm"].state_hash() == cli["gm"].state_hash(), IO_TIMEOUT_MS),
		"B4 裁决后两端指纹一致")

	# ---- B5 越权操作：主机拒 -102，本端不落子 ----
	# 先等牌权真的交出去：applied 信号的发出与本地 apply_event 有先后，
	# 刚解除等待时客人这边的 current_player_index 可能还停在自己身上。
	_check(_pump(peers, func(): return int(cli["gm"].current_player_index) != 1, IO_TIMEOUT_MS),
		"B5 牌权已离开客人（现在座位 %d）" % int(cli["gm"].current_player_index))
	var hash_b5 := int(cli["gm"].state_hash())
	_check(int(rc.pass_turn()) == 0, "B5 越权跳过仍会发包（返回 0）")
	_check(rc.awaiting_reply(), "B5 越权提交同样进入等待")
	_check(_pump(peers, func(): return not rc.awaiting_reply(), IO_TIMEOUT_MS),
		"B5 主机回了 rejected")
	_check(rc.last_code() == NetProtocolScript.ERR_NOT_YOUR_TURN,
		"B5 拒绝码 = ERR_NOT_YOUR_TURN(-102)（实得 %d）" % rc.last_code())
	_check(rc.last_reason() == ActionRouterScript.describe_code(NetProtocolScript.ERR_NOT_YOUR_TURN),
		"B5 拒绝原因已翻译成人话")
	_check(int(cli["gm"].state_hash()) == hash_b5, "B5 被拒后客人局面不变")
	_check(cli["gm"].state_hash() == host["gm"].state_hash(), "B5 被拒后两端仍一致")

	# ---- B5b 客人B 在自己回合操作：把牌权转回房主，顺带验证第二台客人 ----
	_check(_pump(peers, func(): return int(cli2["gm"].current_player_index) == 2, IO_TIMEOUT_MS),
		"B5b 牌权在客人B（座位 %d）" % int(cli2["gm"].current_player_index))
	var card_b2 = _pick_playable(cli2["gm"], 2)
	if card_b2 != null:
		_check(int(r2.play([card_b2])) == 0, "B5b 客人B 出牌已发出")
	else:
		_check(int(r2.pass_turn()) == 0, "B5b 客人B 跳过已发出")
	_check(r2.awaiting_reply(), "B5b 客人B 进入等待")
	_check(_pump(peers, func(): return not r2.awaiting_reply(), IO_TIMEOUT_MS),
		"B5b 客人B 收到裁决")
	_pump(peers, func(): return _logs_aligned(host, cli, cli2), IO_TIMEOUT_MS)
	_check(host["gm"].state_hash() == cli["gm"].state_hash()
		and host["gm"].state_hash() == cli2["gm"].state_hash(),
		"B5b 三端指纹一致（事件 %d 条）" % host["gm"].event_log.size())

	# ---- B6 D1 红线：本地预检不过就绝不发包 ----
	var log_before := int(cli["gm"].event_log.size())
	var bad_code: int = int(rc.play([]))
	_check(bad_code == -1, "B6 空选牌本地预检返回 -1（实得 %d）" % bad_code)
	_check(not rc.awaiting_reply(), "B6 预检失败不产生待裁决状态")
	_check(int(cli["gm"].event_log.size()) == log_before, "B6 预检失败没有落地事件")
	_check(cli["gm"].state_hash() == host["gm"].state_hash(), "B6 预检失败不影响两端一致性")

	# ---- B7 主机 auto_play：候选牌型在本端算好后随意图落子 ----
	_check(_pump(peers, func(): return int(host["gm"].current_player_index) == 0, IO_TIMEOUT_MS),
		"B7 牌权回到房主（座位 %d）" % int(host["gm"].current_player_index))
	# 会话 seed 每次运行都是随机挑的（主机定），所以两家手牌每次都不一样 →
	# 这里必须「有牌打就测 auto_play、真没牌打就测 pass」，且只记 1 条断言，
	# 免得同一个用例在不同运行里 check 数忽多忽少。
	var auto_set: Array = _pick_auto_set(host["gm"], 0)
	var b7_ok := false
	var b7_msg := ""
	if auto_set.is_empty():
		b7_ok = int(rh.pass_turn()) == 0
		b7_msg = "B7 房主这一手无牌可出 → pass 分支（已发出 / 已裁决）"
	else:
		var code_ap: int = int(rh.auto_play(auto_set))
		b7_ok = code_ap >= 0
		b7_msg = "B7 房主 auto_play 成功（%d，%d 张牌）" % [code_ap, auto_set.size()]
		if b7_ok:
			var last_ev: Dictionary = host["gm"].event_log[host["gm"].event_log.size() - 1]
			b7_ok = int(last_ev.get("pattern", -1)) >= 0
			b7_msg += "，事件里写明 pattern（不靠对端重新检测）"
	_check(b7_ok, b7_msg)
	_pump(peers, func(): return cli["gm"].event_log.size() == host["gm"].event_log.size(),
		IO_TIMEOUT_MS)
	_check(host["gm"].state_hash() == cli["gm"].state_hash(), "B7 之后两端指纹一致")

	# ---- B8 无待处理却提交 sequence 意图 → ERR_NO_PENDING ----
	_check(int(rc.skip_sequence()) == 0, "B8 无待处理时仍会发包（返回 0）")
	_pump(peers, func(): return not rc.awaiting_reply(), IO_TIMEOUT_MS)
	_check(rc.last_code() == NetProtocolScript.ERR_NO_PENDING,
		"B8 拒绝码 = ERR_NO_PENDING(-105)（实得 %d）" % rc.last_code())

	_check(not host["s"].is_desynced() and not cli["s"].is_desynced(), "B9 全程未触发状态分叉")

	cli["s"].close("测试结束")
	host["s"].close("测试结束")
	_pump([host], func(): return false, 100)
