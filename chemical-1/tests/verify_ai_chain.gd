# ============================================================
# tests/verify_ai_chain.gd - 单机 AI 接力链路（多台 AI 连续行动）
#
# 为什么要有这套：单机 AI 不是被 `_process` 驱动的，而是靠 HandView 的
# `_update_ai_schedule()` 起一个 1.5s 的 SceneTreeTimer 推到 `_ai_auto_play()`。
# 其余所有测试都是直接调 `AIPlayer.auto_play()`，正好绕开了「刷新 → 排程」这一步，
# 所以下面这个 bug 能在 48 套全绿的情况下上线：
#
#   Slice 2b（866ae54）加了手牌「复用路径」——人类手牌没变化就提前 return，
#   而 `ai_triggered = false` 的复位被留在重建分支里 → 第一台 AI 打完，
#   人类手牌当然没变 → 不重建 → 闸门永久停在 true → 第二台 AI 永远排不上定时器，
#   真机上单机对局第一手之后就卡在「等待 XX 行动中...」。
#
# 断言：
#   A 人类跳过 → 刷新 → 该 AI 被排程（ai_triggered / ai_armed_turn 记账）
#   B AI 回合里人类手牌未变时依然走复用路径，且「消费掉定时器之后」下一台 AI 被重新排程
#   C 真定时器跑两轮：turn_count 至少前进 2（回归的核心断言，绕过一切桩）
#   D 族炸接炸链终局（无人接炸）也要算换手：turn_count 推进 1 且 AI 重新排程
#
# 用法：godot --headless --path . --script tests/verify_ai_chain.gd
# ============================================================
extends SceneTree

# 单机 AI 计时器 1.5s（HandView._update_ai_schedule）；留 1.2s 余量等两轮
const CHAIN_WAIT := 4.2

var fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _ids(arr: Array) -> Array:
	var out: Array = []
	for o in arr:
		out.append(o.get_instance_id() if is_instance_valid(o) else -1)
	return out


# 已排程回合号；字段不存在时回 -999（旧版本跑这套测试时不该直接抛错）
func _armed(scene) -> int:
	var v = scene.get("ai_armed_turn")
	return -999 if v == null else int(v)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 4 人 3 AI：座位 0 = 人类（脚本代打），座位 1/2/3 = AI
	scene.call("_init_game", 4, 3)
	for _w in range(5):
		await process_frame

	var gm = scene.game_manager
	if gm == null or gm.players.size() != 4:
		_check(false, "开局失败：game_manager=%s players=%d" % [str(gm), 0 if gm == null else gm.players.size()])
		quit(1)
		return
	_check(true, "开局 4 人（AI 数 = %d）" % (gm.players.size() - scene.call("_human_players").size()))

	_run_arm_after_human(scene, gm)
	await _run_reuse_chain(scene, gm)
	_run_chain_end_rearm(scene, gm)
	await _run_real_timers(scene, gm)

	if fails == 0:
		print("ALL AI CHAIN TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


# ------------------------------------------------------------
# A 人类动完（手牌变化 → 重建分支）→ 第一台 AI 被排程
# ------------------------------------------------------------
func _run_arm_after_human(scene, gm) -> void:
	gm.current_player_index = 0          # init_game 已保证，这里再钉一次
	var t0: int = int(gm.turn_count)
	gm.player_pass(0)                    # 人类跳过：抽 1 张 → 手牌变化 → 重建分支
	scene.call("_refresh_ui")
	var actor = gm.get_current_player()
	_check(actor != null and actor.is_ai,
		"A1 人类跳过后牌权交给 AI（座位 %d）" % int(gm.current_player_index))
	_check(int(gm.turn_count) > t0,
		"A2 player_pass 推进了回合号（%d → %d）" % [t0, int(gm.turn_count)])
	_check(scene.ai_triggered == true, "A3 重建路径：AI 定时器已排程（ai_triggered=true）")
	_check(_armed(scene) == int(gm.turn_count),
		"A4 ai_armed_turn 记到当前回合号（%d）" % int(gm.turn_count))


# ------------------------------------------------------------
# B 复用路径：手牌没变（不重建）时，定时器被消费后仍要给下一家排程
# ------------------------------------------------------------
func _run_reuse_chain(scene, gm) -> void:
	var ids0: Array = _ids(scene.hand_buttons)
	scene.call("_update_hand_buttons")
	_check(_ids(scene.hand_buttons) == ids0 and scene.hand_buttons.size() > 0,
		"B1 AI 回合里人类手牌未变 → 确实走复用路径（按钮 id 全同，n=%d）"
		% scene.hand_buttons.size())
	_check(_armed(scene) == int(gm.turn_count), "B2 复用路径不重复排程（同一手只排一次）")

	var t1: int = int(gm.turn_count)
	scene.call("_ai_auto_play")          # 等价于 1.5s 定时器到点
	await process_frame
	if gm.is_game_over():
		_check(true, "B3 AI 一手直接结束对局（跳过接力断言）")
		return
	_check(int(gm.turn_count) > t1,
		"B3 AI 一手之后回合号前进（%d → %d）" % [t1, int(gm.turn_count)])
	var nxt = gm.get_current_player()
	if nxt != null and nxt.is_ai:
		_check(scene.ai_triggered == true and _armed(scene) == int(gm.turn_count),
			"B4 第二台 AI 被重新排程（旧实现这里 ai_triggered 卡在 true、armed=-999 → 卡死）")
	else:
		_check(scene.ai_triggered == false and _armed(scene) == -1,
			"B4 落到人类回合 → 不挂本地 AI 定时器")


# ------------------------------------------------------------
# C 真定时器：两台 AI 在 4.2s 内各动一手（不碰任何内部状态，纯行为断言）
# ------------------------------------------------------------
func _run_real_timers(scene, gm) -> void:
	if gm.is_game_over():
		return
	# 把牌权挪到 AI 座位上（走 next_turn 保证 turn_count 不变量不被破坏）
	var guard: int = 0
	while not gm.is_game_over() and guard < 8:
		var cp = gm.get_current_player()
		if cp != null and cp.is_ai:
			break
		gm.next_turn()
		guard += 1
	scene.call("_refresh_ui")
	var head = gm.get_current_player()
	if head == null or not head.is_ai:
		_check(false, "C1 无法把牌权挪到 AI 上（座位 %d）" % int(gm.current_player_index))
		return
	_check(scene.ai_triggered == true, "C1 当前 AI 已排程（座位 %d）" % int(gm.current_player_index))

	var t2: int = int(gm.turn_count)
	await create_timer(CHAIN_WAIT).timeout
	_check(int(gm.turn_count) >= t2 + 2,
		"C2 %.1fs 内 AI 接力 ≥2 手（回合号 %d → %d）：第二台 AI 不会卡死"
		% [CHAIN_WAIT, t2, int(gm.turn_count)])


# ------------------------------------------------------------
# D 族炸接炸链终局：牌权交回炸弹主人，同样算「换手」 - 必须重新排程
#   第 4 条换手路径：GameManager._finish_clan_bomb_chain() 老实现只改
#   current_player_index、turn_count 原地不动 - 单机就停在「无人接炸！XX 自由出牌」。
# ------------------------------------------------------------
func _run_chain_end_rearm(scene, gm) -> void:
	if gm.is_game_over():
		return
	# 把牌权挪到 AI 座位上（走 next_turn，不自己造 turn_count）
	var moved: bool = false
	for _i in range(8):
		if gm.is_game_over():
			break
		var cp = gm.get_current_player()
		if not (cp == null) and cp.is_ai:
			moved = true
			break
		gm.next_turn()
	if not moved:
		_check(false, "D1 无法把牌权挪到 AI 座位上")
		return
	# 伪造「本手令牌已被上一台 AI 消费」：ai_triggered 已还，令牌记着同一个回合号，
	# 但行动者是别人 —— 这正是老实现只看回合号时区分不出来的那一手。
	scene.ai_triggered = false
	scene.ai_armed_turn = int(gm.turn_count)
	scene.ai_armed_actor = -1
	scene.call("_refresh_ui")
	_check(scene.ai_triggered == true, "D2 令牌是别的行动者：必须重新排程（只看回合号会卡在这里）")
	var owner: int = int(gm.current_player_index)
	_check(_armed(scene) == int(gm.turn_count) and int(scene.get("ai_armed_actor")) == gm.players[owner].get_instance_id(),
		"D3 令牌记到（回合号 + 行动者）")
	# 造接炸链终局：除 owner 外所有人都已 pass
	for i in range(gm.players.size()):
		gm.players[i].has_passed = not (i == owner)
	gm.clan_bomb_chain_active = true
	gm.clan_bomb_owner = owner
	# 伪装「定时器已被消费」：此刻令牌正是（本回合号, owner）—— 老实现不推进回合号时闸门会挡住这次重新排程
	scene.ai_triggered = false
	var t0: int = int(gm.turn_count)
	gm.next_turn()
	_check(int(gm.turn_count) == t0 + 1,
		"D4 无人接炸：换手推进回合号 " + str(t0) + " → " + str(int(gm.turn_count)))
	_check(int(gm.current_player_index) == owner, "D5 牌权交回炸弹主人（座位 " + str(owner) + "）")
	_check(gm.clan_bomb_chain_active == false, "D6 接炸链已关闭")
	# 关键断言：这一手没被上一条换手路径用掉 - 必须重新排程
	scene.call("_refresh_ui")
	_check(scene.ai_triggered == true, "D7 刷新后重新排程")
	_check(_armed(scene) == int(gm.turn_count)
		and int(scene.get("ai_armed_actor")) == gm.players[owner].get_instance_id(),
		"D8 令牌双键 = 回合号 + 行动者")
