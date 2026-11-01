# 验证联机地基（P11-B）
#   1) 牌库 uid：= 生成下标、连续、唯一（默认牌库 / 元素限制牌库）
#   2) 种子化洗牌：同 seed 同序、异 seed 异序、无参调用行为不变
#   3) 引擎确定性：同 seed 初始化 → state_hash 相等；异 seed → 不等
#   4) 事件重放：主机 / 客人逐事件应用，返回码与 state_hash 全程一致
#   5) apply_event 边界：未知类型 / 不存在 uid / 重复 uid / 越界座位 / 别人的牌
#   6) 快照裁剪：只保留本人手牌 uid、保留对手张数、深拷贝不污染原快照
#   7) 回环传输：host/join/send/poll/断线信号
# 运行：godot --headless --path . --script tests/verify_net_foundation.gd
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const NetProtocolScript = preload("res://scripts/net/NetProtocol.gd")
const LoopbackTransportScript = preload("res://scripts/net/LoopbackTransport.gd")

const TEST_SEED = 20261101

var fails: int = 0
var checks: int = 0
var script_results: Array = []


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
		print("ALL NET FOUNDATION TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d NET FOUNDATION TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


func _run() -> void:
	_test_deck_uid()
	_test_seeded_shuffle()
	_test_default_shuffle_keeps_working()
	_test_engine_determinism()
	_test_event_replay_consistency()
	_test_apply_event_errors()
	_test_snapshot_strip()
	_test_loopback_transport()
	_finish()


# ---- 工具：4 名人类玩家（ai_count = 0）→ 不依赖任何 AI 决策 ----
func _new_game(seed_value: int):
	var gm = GameManagerScript.new()
	if not gm.init_game(4, 0, seed_value):
		return null
	return gm


func _deck_uids(db) -> Array:
	var out: Array = []
	for card in db.deck:
		out.append(int(card.uid))
	return out


# ============================================================
# 1) uid 语义
# ============================================================
func _test_deck_uid() -> void:
	var db = CardDatabaseScript.new()
	db.generate_deck()
	var n: int = db.deck.size()
	_check(n == CardDatabaseScript.get_deck_size([]), "默认牌库张数 = get_deck_size(全量) = %d" % n)

	var seen: Dictionary = {}
	var ok := true
	for card in db.deck:
		var uid: int = int(card.uid)
		if uid < 0 or uid >= n or seen.has(uid):
			ok = false
			break
		seen[uid] = true
	_check(ok, "uid 落在 [0, %d) 且互不重复" % n)

	var db2 = CardDatabaseScript.new()
	db2.generate_deck(CardDatabaseScript.get_allowed_symbols(true, ["Fe", "Cu"]))
	var continuous := true
	for i in range(db2.deck.size()):
		if int(db2.deck[i].uid) != i:
			continuous = false
			break
	_check(continuous, "元素限制牌库 uid = 生成下标（从 0 连续），张数 %d" % db2.deck.size())


# ============================================================
# 2) 种子化洗牌
# ============================================================
func _test_seeded_shuffle() -> void:
	var a := _shuffled_uids(TEST_SEED)
	var b := _shuffled_uids(TEST_SEED)
	var c := _shuffled_uids(TEST_SEED + 1)
	_check(a == b, "同一 seed 两次洗牌 → uid 序列完全相同")
	_check(a != c, "不同 seed → uid 序列不同")
	_check(a.size() == b.size() and a.size() > 0, "洗牌不改变牌库张数")


func _shuffled_uids(seed_value: int) -> Array:
	var db = CardDatabaseScript.new()
	db.generate_deck()
	db.shuffle(seed_value)
	return _deck_uids(db)


# ============================================================
# 3) 无参 shuffle() 保持旧行为（仍是原牌库的一个排列）
# ============================================================
func _test_default_shuffle_keeps_working() -> void:
	var db = CardDatabaseScript.new()
	db.generate_deck()
	var before := _deck_uids(db)
	db.shuffle()   # 无参 → 全局 randi() 路径（单机默认）
	var after := _deck_uids(db)
	after.sort()
	_check(after.size() == before.size() and after == before,
		"无参 shuffle() 仍可用，且结果是原牌库的排列（%d 张）" % after.size())


# ============================================================
# 4) 引擎确定性
# ============================================================
func _test_engine_determinism() -> void:
	var a = _new_game(TEST_SEED)
	var b = _new_game(TEST_SEED)
	var c = _new_game(TEST_SEED + 7)
	_check(a != null and b != null and c != null, "三个引擎均以 4 人 / 无 AI 成功初始化")
	if a == null or b == null or c == null:
		return
	_check(a.deck_seed == TEST_SEED, "deck_seed 被记录在引擎上")
	_check(a.state_hash() == b.state_hash(), "同 seed 初始化 → state_hash 相等")
	_check(a.get_hand_uids(0) == b.get_hand_uids(0), "同 seed → 0 号座位手牌 uid 完全相同")
	_check(a.state_hash() != c.state_hash(), "不同 seed → state_hash 不同")
	_check(a.state_hash() != 0, "state_hash 不为 0（FNV 已生效）")


# ============================================================
# 5) 事件重放一致性（核心）
# ============================================================
func _test_event_replay_consistency() -> void:
	var sim = _new_game(TEST_SEED)
	if sim == null:
		_check(false, "剧本引擎初始化失败")
		return
	var events := _scripted_events(sim)

	var all_results_ok := true
	for r in script_results:
		if int(r) < 0:
			all_results_ok = false
			break
	_check(all_results_ok, "剧本内 %d 笔事件在生成阶段全部合法（返回码 >= 0）" % events.size())

	var host = _new_game(TEST_SEED)
	var client = _new_game(TEST_SEED)
	var mismatch := -1
	for i in range(events.size()):
		var ev = events[i]
		var r1: int = host.apply_event(ev)
		var r2: int = client.apply_event(ev)
		if r1 != r2 or host.state_hash() != client.state_hash():
			mismatch = i
			break
	if mismatch < 0:
		_check(true, "主机 / 客人逐事件应用：返回码与 state_hash 全程一致（%d 步）" % events.size())
	else:
		_check(false, "第 %d 笔事件出现主机 / 客人不一致" % mismatch)
	_check(host.event_log.size() == events.size(),
		"成功事件全部写入 event_log（%d/%d）" % [host.event_log.size(), events.size()])
	_check(host.event_log.size() == client.event_log.size(), "双方 event_log 长度一致")

	# 快照也必须一致（重连 / 失配修复才用，但必须可信）
	_check(JSON.stringify(host.to_snapshot()) == JSON.stringify(client.to_snapshot()),
		"双方 to_snapshot() 的 JSON 文本完全相同")


# 剧本：只使用「必然合法」的动作（首轮单张 / 跳过），不依赖具体牌面
func _scripted_events(sim) -> Array:
	script_results.clear()
	var events: Array = []

	# 1) 首轮：当前玩家自由出牌 → 单张（is_round_starter = true）
	var starter: int = sim.get_current_player_index()
	_push_event(events, sim, {
		"type": "play", "by": starter,
		"uids": [sim.get_hand_uids(starter)[0]], "pattern": -1,
	})
	# 2) 其余 3 人依次跳过（跳过一定成功，且各抽 1 张）
	for _i in range(3):
		_push_event(events, sim, {"type": "pass", "by": sim.get_current_player_index()})
	# 3) 新一轮：再出一张单牌
	var second: int = sim.get_current_player_index()
	_push_event(events, sim, {
		"type": "play", "by": second,
		"uids": [sim.get_hand_uids(second)[0]], "pattern": -1,
	})
	# 4) 再跳过两人
	for _i in range(2):
		_push_event(events, sim, {"type": "pass", "by": sim.get_current_player_index()})
	return events


func _push_event(events: Array, sim, ev: Dictionary) -> void:
	script_results.append(sim.apply_event(ev))
	events.append(ev)


# ============================================================
# 6) apply_event 边界
# ============================================================
func _test_apply_event_errors() -> void:
	var gm = _new_game(TEST_SEED)
	if gm == null:
		_check(false, "边界测试引擎初始化失败")
		return
	_check(gm.apply_event({"type": "no_such_type", "by": 0}) == GameManagerScript.EVENT_UNKNOWN,
		"未知事件类型 → EVENT_UNKNOWN(%d)" % GameManagerScript.EVENT_UNKNOWN)
	_check(gm.apply_event({"type": "play", "by": 0, "uids": [999999]}) == GameManagerScript.EVENT_BAD_PAYLOAD,
		"不存在的 uid → EVENT_BAD_PAYLOAD(%d)" % GameManagerScript.EVENT_BAD_PAYLOAD)
	var first_uid: int = gm.get_hand_uids(0)[0]
	_check(gm.apply_event({"type": "play", "by": 0, "uids": [first_uid, first_uid]}) == GameManagerScript.EVENT_BAD_PAYLOAD,
		"重复 uid → EVENT_BAD_PAYLOAD")
	_check(gm.apply_event({"type": "pass", "by": 99}) == GameManagerScript.EVENT_BAD_PAYLOAD,
		"越界座位 → EVENT_BAD_PAYLOAD")
	var other_uid: int = gm.get_hand_uids(1)[0]
	_check(gm.apply_event({"type": "play", "by": 0, "uids": [other_uid]}) == GameManagerScript.EVENT_BAD_PAYLOAD,
		"拿别人的牌出牌 → EVENT_BAD_PAYLOAD")

	var log_before: int = gm.event_log.size()
	gm.apply_event({"type": "play", "by": 0, "uids": [999999]})
	gm.apply_event({"type": "no_such_type", "by": 0})
	_check(gm.event_log.size() == log_before, "失败 / 未知事件不写入 event_log")

	# 回合归属 / 代操作 由协议层把关（GameManager 本身不做这一层校验）
	_check(NetProtocolScript.validate_intent({"type": "play", "by": 0}, 0, 4, 0, false) == 0,
		"合法意图 → 0")
	_check(NetProtocolScript.validate_intent({"type": "play", "by": 2}, 2, 4, 0, false) == NetProtocolScript.ERR_NOT_YOUR_TURN,
		"非当前玩家意图 → ERR_NOT_YOUR_TURN(%d)" % NetProtocolScript.ERR_NOT_YOUR_TURN)
	_check(NetProtocolScript.validate_intent({"type": "play", "by": 2}, 1, 4, 2, false) == NetProtocolScript.ERR_WRONG_SEAT,
		"替别人操作 → ERR_WRONG_SEAT(%d)" % NetProtocolScript.ERR_WRONG_SEAT)
	_check(NetProtocolScript.validate_intent({"type": "play", "by": 0}, 0, 4, 0, true) == NetProtocolScript.ERR_GAME_OVER,
		"终局拒绝意图 → ERR_GAME_OVER(%d)" % NetProtocolScript.ERR_GAME_OVER)
	_check(NetProtocolScript.validate_intent({"type": "bogus", "by": 0}, 0, 4, 0, false) == NetProtocolScript.ERR_BAD_EVENT,
		"未知意图类型 → ERR_BAD_EVENT(%d)" % NetProtocolScript.ERR_BAD_EVENT)
	_check(NetProtocolScript.validate_intent({"type": "sequence_pick", "by": 0}, 0, 4, 1, false) == 0,
		"顺序指定：牌权已移交，提交者仍可确认（靠 pending 状态判断）")
	_check(NetProtocolScript.is_known_message("intent") and not NetProtocolScript.is_known_message("evil"),
		"消息类型白名单生效")


# ============================================================
# 7) 快照裁剪
# ============================================================
func _test_snapshot_strip() -> void:
	var gm = _new_game(TEST_SEED)
	if gm == null:
		_check(false, "快照测试引擎初始化失败")
		return
	var snap: Dictionary = gm.to_snapshot()
	_check(int(snap.get("deck_seed", 0)) == TEST_SEED, "快照记录 deck_seed")
	_check(snap["players"][0]["hand_uids"].size() == 8, "快照 0 号手牌 8 张 uid")

	var stripped: Dictionary = NetProtocolScript.strip_snapshot(snap, 1)
	_check(stripped["players"][0]["hand_uids"].is_empty(), "裁剪后 0 号（他人）手牌 uid 被清空")
	_check(stripped["players"][1]["hand_uids"].size() == 8, "裁剪后 1 号（本人）手牌保留")
	_check(int(stripped["players"][0]["hand_count"]) == 8, "裁剪后仍保留对手手牌张数")
	_check(int(stripped.get("view_seat", -1)) == 1, "裁剪后标记 view_seat = 1")
	_check(snap["players"][0]["hand_uids"].size() == 8, "裁剪是深拷贝，不污染原快照")
	var parsed = JSON.parse_string(JSON.stringify(snap))
	_check(parsed is Dictionary, "快照可 JSON 往返（可直接走网络 / 存档）")


# ============================================================
# 8) 回环传输（无网络验证协议往返 / 断线流程）
# ============================================================
func _test_loopback_transport() -> void:
	var a = LoopbackTransportScript.new()
	var b = LoopbackTransportScript.new()
	a.link(b)

	var connected: Array = []
	var packets: Array = []
	var left: Array = []
	b.peer_connected.connect(func(pid): connected.append(pid))
	b.packet_received.connect(func(pid, data): packets.append([pid, data]))
	b.peer_disconnected.connect(func(pid): left.append(pid))

	_check(a.host(0) == 0, "回环 host 成功")
	_check(b.join("", 0) == 0, "回环 join 成功")
	b.poll()
	_check(connected == [1], "客人收到 peer_connected(1)")

	var payload := PackedByteArray([1, 2, 3, 250])
	_check(a.send_to(2, payload) == 0, "主机 send_to(2) 成功")
	b.poll()
	_check(packets.size() == 1, "客人收到 1 个包")
	if packets.size() == 1:
		_check(int(packets[0][0]) == 1, "包来源 peer_id = 1（主机）")
		_check(packets[0][1] == payload, "包内容字节一致")

	_check(b.get_transport_name() == "loopback", "传输层标识 = loopback")
	_check(b.is_connected_to(1), "客人认为与 1 号相连")
	_check(a.get_peers() == [2], "主机 peer 列表 = [2]")

	# 反向：客人 → 主机
	var back: Array = []
	a.packet_received.connect(func(pid, data): back.append([pid, data]))
	_check(b.send_to(1, PackedByteArray([9])) == 0, "客人 send_to(1) 成功")
	a.poll()
	_check(back.size() == 1 and int(back[0][0]) == 2, "主机收到客人（peer_id=2）的包")

	_check(a.send_to(99, payload) == -1, "向不存在的 peer 发送 → -1")

	# 断线
	a.close()
	b.poll()
	_check(left == [1], "主机 close → 客人收到 peer_disconnected(1)")
	_check(not b.is_connected_to(1), "断开后 is_connected_to 返回 false")
