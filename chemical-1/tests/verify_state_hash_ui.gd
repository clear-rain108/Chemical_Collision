# ============================================================
# 验证 state_hash 与「UI 日志队列」解耦（D23 / 真机 -109 误报回归）
#
# 背景：v2 指纹末尾写的是 logs=<log_messages.size()>，而 log_messages 是
# GameLogger 里的**待消费队列** —— 牌桌右侧日志面板每刷新一帧就
# flush_logs() 把它清空（scripts/ui/SidePanels.gd:_update_log_label）。
# 于是同一个局面能算出两个指纹：
#   手机 _send_ready()：刚 init_game、UI 还没消费 → logs=2
#   主机 _host_on_ready()：poll 到 ready 时面板早已消费 → logs=0
# → 开局第 0 笔稳定误报 -109（真机：主机 3767668832 / 手机 3801224070）。
# 修复：指纹只放**规则状态**，不再放任何进度计数。进度由 turn= 覆盖，
# 精确的事件进度由联机层单独把关（ready 握手比 event_log 条数、每笔 applied
# 逐笔比）—— 所以也不能改用 event_log.size()：单机直调 play_cards 不写
# event_log，只有 apply_event 写，两条等价路径的指纹会分开。
#
#   S0 指纹里不再出现 logs= / events= 这类进度计数
#   S1 flush_logs 前后 state_hash 不变（本 bug 的直接回归断言）
#   S2 主机已 flush / 客人未 flush → 指纹相同；逐笔推进时两端 flush 节奏
#      不同也不许分叉
#   S3 主机边打边 flush，客人 replay_events → 指纹与 event_log 全对齐
#   S4 to_snapshot()["log_count"] 仍随 flush 归零（UI 语义没被误伤）
#   S5 复现 _host_on_ready：主机任意时刻重算 == 客人 ready 报的指纹
# 运行：godot --headless --path . --script tests/verify_state_hash_ui.gd
# ============================================================
extends SceneTree

const GameManagerScript = preload("res://scripts/GameManager.gd")

const TEST_SEED = 20261120

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
		print("ALL STATE HASH / UI DECOUPLING TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d STATE HASH / UI DECOUPLING TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


func _run() -> void:
	_test_s0_canonical_text()
	_test_s1_flush_keeps_hash()
	_test_s2_host_flushed_vs_client_fresh()
	_test_s3_replay_after_flush()
	_test_s4_snapshot_log_count()
	_test_s5_ready_scenario()
	_finish()


# ---- 工具：4 名人类玩家（ai_count = 0）→ 不依赖 AI 决策 ----
func _new_game(seed_value: int):
	var gm = GameManagerScript.new()
	if not gm.init_game(4, 0, seed_value):
		return null
	return gm


# ============================================================
# S0 指纹文本
# ============================================================
func _test_s0_canonical_text() -> void:
	var gm = _new_game(TEST_SEED)
	if gm == null:
		_check(false, "S0 引擎初始化失败")
		return
	var canon: String = gm._canonical_string()
	_check(not canon.contains("logs="), "S0 指纹不再含 UI 待消费队列长度（logs=）")
	_check(not canon.contains("events="), "S0 指纹也不含 event_log 条数（events=）")
	_check(canon.contains("turn=0"), "S0 进度维度由规则状态 turn= 承担")
	# 直接对拍旧公式：此刻同一局面加上待消费条数会得到另一个值
	var legacy: int = gm._fnv1a(int(GameManagerScript.FNV_OFFSET_BASIS),
		canon + "\nlogs=%d" % gm.log_messages.size())
	_check(legacy != int(gm.state_hash()),
		"S0 反向自检：旧公式（logs=待消费条数）确实会算出另一个指纹")


# ============================================================
# S1 flush_logs 不动指纹
# ============================================================
func _test_s1_flush_keeps_hash() -> void:
	var gm = _new_game(TEST_SEED)
	if gm == null:
		_check(false, "S1 引擎初始化失败")
		return
	_check(gm.log_messages.size() > 0,
		"S1 开局产生了待消费日志（%d 条）" % gm.log_messages.size())

	var before: int = gm.state_hash()
	var drained: Array = gm.flush_logs()
	_check(drained.size() > 0, "S1 flush_logs 取走 %d 条日志" % drained.size())
	_check(int(gm.state_hash()) == before,
		"S1 flush_logs 前后 state_hash 不变（%d → %d）" % [before, int(gm.state_hash())])

	# 出一张牌（会继续产生日志）→ 再 flush，指纹仍不许动
	var starter: int = gm.get_current_player_index()
	var uid: int = gm.get_hand_uids(starter)[0]
	gm.apply_event({"type": "play", "by": starter, "uids": [uid], "pattern": -1})
	var h2: int = gm.state_hash()
	var ev2: int = gm.event_log.size()
	gm.flush_logs()
	_check(int(gm.state_hash()) == h2, "S1 出牌后 flush 仍不动指纹")
	_check(gm.event_log.size() == ev2, "S1 flush 不影响 event_log（仍是 %d 条）" % ev2)


# ============================================================
# S2 两端 UI 帧序不同 → 指纹相同
# ============================================================
func _test_s2_host_flushed_vs_client_fresh() -> void:
	var host = _new_game(TEST_SEED)
	var client = _new_game(TEST_SEED)
	if host == null or client == null:
		_check(false, "S2 引擎初始化失败")
		return
	_check(int(host.state_hash()) == int(client.state_hash()),
		"S2 同 seed 开局指纹一致（对照）")

	# 主机：模拟牌桌日志面板刷新（真机上每帧都会发生）
	host.flush_logs()
	_check(client.log_messages.size() > 0,
		"S2 客人侧尚未消费日志（%d 条）" % client.log_messages.size())
	_check(int(host.state_hash()) == int(client.state_hash()),
		"S2 主机已消费日志 / 客人未消费 → 指纹仍相同（%d）" % int(host.state_hash()))

	# 逐笔推进：主机每笔都 flush，客人隔一笔 flush 一次 → 仍不许分叉
	var sim = _new_game(TEST_SEED)
	var events := _scripted_events(sim)
	var mismatch := -1
	for i in range(events.size()):
		host.apply_event(events[i])
		client.apply_event(events[i])
		host.flush_logs()
		if i % 2 == 0:
			client.flush_logs()
		if int(host.state_hash()) != int(client.state_hash()):
			mismatch = i
			break
	var msg := "S2 逐笔推进 + 两端 flush 节奏不同 → 指纹全程一致（%d 笔）" % events.size()
	if mismatch >= 0:
		msg = "S2 第 %d 笔因 UI flush 节奏不同出现指纹分叉" % mismatch
	_check(mismatch < 0, msg)


# ============================================================
# S3 重放对齐：主机边打边 flush vs 客人 replay_events
# ============================================================
func _test_s3_replay_after_flush() -> void:
	var sim = _new_game(TEST_SEED)
	var host = _new_game(TEST_SEED)
	var client = _new_game(TEST_SEED)
	if sim == null or host == null or client == null:
		_check(false, "S3 引擎初始化失败")
		return
	var events := _scripted_events(sim)
	for ev in events:
		host.apply_event(ev)
		host.flush_logs()          # 主机边打边刷面板
	var applied: int = client.replay_events(events)
	_check(applied == events.size(),
		"S3 客人重放成功 %d/%d 笔" % [applied, events.size()])
	_check(host.event_log.size() == client.event_log.size(),
		"S3 两端 event_log 长度一致（%d）" % host.event_log.size())
	_check(int(host.state_hash()) == int(client.state_hash()),
		"S3 主机（已 flush）与客人（重放）指纹一致")


# ============================================================
# S4 快照里的 log_count 仍是「待消费」语义
# ============================================================
func _test_s4_snapshot_log_count() -> void:
	var gm = _new_game(TEST_SEED)
	if gm == null:
		_check(false, "S4 引擎初始化失败")
		return
	var before := int(gm.to_snapshot().get("log_count", -1))
	_check(before > 0, "S4 to_snapshot() 的 log_count 反映待消费日志（%d）" % before)
	gm.flush_logs()
	_check(int(gm.to_snapshot().get("log_count", -1)) == 0,
		"S4 flush 后 log_count 归零（UI 语义保留，但不进指纹）")


# ============================================================
# S5 复现真机场景：ready 报的指纹 vs 主机重算
# ============================================================
func _test_s5_ready_scenario() -> void:
	var host = _new_game(TEST_SEED)
	var client = _new_game(TEST_SEED)
	if host == null or client == null:
		_check(false, "S5 引擎初始化失败")
		return
	# 客人 _send_ready()：init_game 完立刻算指纹，此刻它的 UI 还没消费日志
	var ready_hash: int = client.state_hash()
	var ready_events: int = client.event_log.size()
	# 主机 _host_on_ready()：poll 到 ready 时再算一次，此刻日志面板早已 flush
	host.flush_logs()
	var host_hash: int = host.state_hash()
	_check(ready_events == host.event_log.size(),
		"S5 ready 的 events 与主机进度相同（闸门放行）")
	_check(host_hash == ready_hash,
		"S5 主机重算 == 客人 ready 报的指纹（不再误报 -109：%d == %d）"
		% [host_hash, ready_hash])

	# 反向自检：旧公式（再追加 logs=<待消费条数>）在这条路径上确实分叉 ——
	# 若哪天有人把这一行改回 log_messages，S5 上面的断言会立刻转红。
	var legacy_host := "%s\nlogs=%d" % [host._canonical_string(), host.log_messages.size()]
	var legacy_client := "%s\nlogs=%d" % [client._canonical_string(), client.log_messages.size()]
	_check(legacy_host != legacy_client,
		"S5 反向自检：旧公式 logs=<待消费条数> 在此路径下确实会分叉")


# ---- 剧本：只用「必然合法」的动作（首轮单张 / 跳过），不依赖具体牌面 ----
func _scripted_events(sim) -> Array:
	var events: Array = []
	# 1) 首轮：当前玩家自由出牌 → 单张
	var starter: int = sim.get_current_player_index()
	var ev_play := {
		"type": "play", "by": starter,
		"uids": [sim.get_hand_uids(starter)[0]], "pattern": -1,
	}
	events.append(ev_play)
	sim.apply_event(ev_play)
	# 2) 其余 3 人依次跳过（跳过必然成功，各抽 1 张）
	for _i in range(3):
		var ev_pass := {"type": "pass", "by": sim.get_current_player_index()}
		events.append(ev_pass)
		sim.apply_event(ev_pass)
	# 3) 新一轮：再出一张单牌
	var second: int = sim.get_current_player_index()
	var ev_play2 := {
		"type": "play", "by": second,
		"uids": [sim.get_hand_uids(second)[0]], "pattern": -1,
	}
	events.append(ev_play2)
	sim.apply_event(ev_play2)
	# 4) 再跳过两人
	for _i in range(2):
		var ev_pass2 := {"type": "pass", "by": sim.get_current_player_index()}
		events.append(ev_pass2)
		sim.apply_event(ev_pass2)
	return events
