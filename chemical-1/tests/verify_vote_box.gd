# ============================================================
# tests/verify_vote_box.gd - 化合物质疑投票箱（D22）纯逻辑测试
#
# 覆盖 11 项口径（与 VoteBox.gd 头部注释一一对应）：
#   分母冻结 / 投票记账 / 非投票人 / 已收口 / 幂等重复票 / 全票通过 /
#   一票否决 / 掉线出分母 / 分母清空 / 超时 / 快照与幂等收口
#
# 完全不碰 ENet / GameManager：投票箱是纯状态机，这一套是「逻辑对不对」，
# 端到端那套见 tests/verify_net_vote.gd（三端指纹逐笔一致）。
#
# 运行：godot --headless --path . --script tests/verify_vote_box.gd
# ============================================================
extends SceneTree

const VoteBoxScript = preload("res://scripts/net/VoteBox.gd")

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
		print("ALL VOTE BOX TESTS PASSED (%d checks)" % checks)
	else:
		print("%d/%d VOTE BOX TESTS FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)


func _run() -> void:
	_test_freeze_denominator()
	_test_cast_ok()
	_test_not_voter()
	_test_closed()
	_test_duplicate()
	_test_all_yes()
	_test_one_no()
	_test_offline_drops_vote()
	_test_empty_denominator()
	_test_timeout()
	_test_snapshot_and_idempotent()
	_finish()


func _mk(voters: Array = [1, 2], timeout_ms: int = 20000) -> RefCounted:
	var vb = VoteBoxScript.new()
	vb.open(7, 0, voters, {"uids": [11, 22], "valences": {}, "pattern": 2}, "配不平", 1000, timeout_ms)
	return vb


# ① 分母冻结：出题人自己不算、重复座位去重、按座位升序
func _test_freeze_denominator() -> void:
	var vb = VoteBoxScript.new()
	vb.open(1, 2, [3, 0, 2, 1, 1], {"uids": [5]}, "r", 0, 20000)
	_check(vb.voters == [0, 1, 3], "① 分母 = 除出题人外的在线人类，去重且升序（实际 %s）" % str(vb.voters))
	_check(vb.total() == 3 and vb.by == 2 and not vb.has_voter(2),
		"① 出题人不在分母里，分母 3 人")


# ② 记账：投票 / 计数 / 未投名单
func _test_cast_ok() -> void:
	var vb = _mk([1, 2])
	_check(vb.cast(1, true) == 0, "② 投票人投票返回 0")
	_check(vb.approve_count() == 1 and vb.reject_count() == 0 and vb.total() == 2,
		"② 赞成 1 / 反对 0 / 分母 2")
	_check(vb.has_voted(1) and not vb.has_voted(2), "② 已投 / 未投状态正确")
	_check(vb.pending_seats() == [2], "② 未投名单 = [2]")


# ③ 非投票人（观战者 / AI / 出题人）→ -113
func _test_not_voter() -> void:
	var vb = _mk([1, 2])
	_check(vb.cast(0, true) == VoteBoxScript.ERR_NOT_VOTER, "③ 出题人自己投票 → -113")
	_check(vb.cast(-1, true) == VoteBoxScript.ERR_NOT_VOTER, "③ 观战者投票 → -113")
	_check(vb.cast(9, false) == VoteBoxScript.ERR_NOT_VOTER, "③ 越界座位投票 → -113")


# ④ 已收口 → -112，且票不再变化
func _test_closed() -> void:
	var vb = _mk([1])
	var snap: Dictionary = vb.resolve()
	_check(bool(snap["resolved"]), "④ resolve 之后 resolved = true")
	_check(vb.cast(1, true) == VoteBoxScript.ERR_NO_VOTE, "④ 收口后投票 → -112")
	_check(not bool(vb.snapshot()["approved"]), "④ 单人未投就收口 → 不通过")


# ⑤ 幂等：第一票有效，重复 / 改票都不生效
func _test_duplicate() -> void:
	var vb = _mk([1, 2])
	vb.cast(1, true)
	_check(vb.cast(1, true) == 0, "⑤ 重复投同一值幂等返回 0")
	_check(vb.cast(1, false) == 0, "⑤ 想改票也返回 0（不允许翻牌）")
	_check(vb.approve_count() == 1 and vb.reject_count() == 0, "⑤ 第一票有效，改票不生效")


# ⑥ 全票赞成 → 通过
func _test_all_yes() -> void:
	var vb = _mk([1, 2])
	vb.cast(1, true)
	_check(vb.settle_cause() == "", "⑥ 还有人没投 → 不收口")
	vb.cast(2, true)
	_check(vb.settle_cause() == VoteBoxScript.CAUSE_ALL_YES, "⑥ 全票赞成 → all_yes")
	var snap: Dictionary = vb.resolve()
	_check(bool(snap["approved"]) and String(snap["cause"]) == "all_yes",
		"⑥ 收口结论 = 通过（cause=all_yes）")


# ⑦ 一票否决立即收口（不必等剩下的人）
func _test_one_no() -> void:
	var vb = _mk([1, 2])
	vb.cast(1, false)
	_check(vb.settle_cause() == VoteBoxScript.CAUSE_REJECTED, "⑦ 有人反对 → rejected（不等剩余票）")
	var snap: Dictionary = vb.resolve()
	_check(not bool(snap["approved"]), "⑦ rejected 收口 → 不通过")


# ⑧ 掉线投票人：出分母 + 作废已投的票（否则掉线者的反对票会永久卡住）
func _test_offline_drops_vote() -> void:
	var vb = _mk([1, 2, 3])
	vb.cast(1, true)
	vb.cast(2, false)
	_check(vb.remove_voter(2), "⑧ 移除分母成员返回 true")
	_check(vb.total() == 2 and not vb.has_voted(2), "⑧ 掉线者出分母且票作废")
	_check(not vb.remove_voter(2), "⑧ 重复移除返回 false（幂等）")
	vb.cast(3, true)
	_check(vb.settle_cause() == VoteBoxScript.CAUSE_ALL_YES,
		"⑧ 掉线者的反对票作废后，剩余全赞成 → 通过")


# ⑨ 分母清空 → 不通过（无人可投）
func _test_empty_denominator() -> void:
	var vb = _mk([1])
	vb.remove_voter(1)
	_check(vb.total() == 0, "⑨ 分母清空")
	_check(vb.settle_cause() == VoteBoxScript.CAUSE_NO_VOTER, "⑨ 无人可投 → no_voter")
	_check(not bool(vb.resolve()["approved"]), "⑨ no_voter 收口 → 不通过")


# ⑩ 超时：expired 判定 + 视同不通过
func _test_timeout() -> void:
	var vb = _mk([1, 2], 300)
	_check(not vb.expired(1000), "⑩ 刚开票不算超时")
	_check(vb.expired(1300), "⑩ 到点算超时")
	_check(vb.remain_ms(1100) == 200, "⑩ 剩余时间 200ms")
	var snap: Dictionary = vb.resolve(VoteBoxScript.CAUSE_TIMEOUT)
	_check(not bool(snap["approved"]) and String(snap["cause"]) == "timeout",
		"⑩ 超时收口 → 不通过（cause=timeout）")
	_check(vb.remain_ms(2000) == 0, "⑩ 收口后剩余时间归零")


# ⑪ 快照字段齐全 & resolve 幂等
func _test_snapshot_and_idempotent() -> void:
	var vb = _mk([1, 2])
	vb.cast(1, true)
	var snap: Dictionary = vb.snapshot(2000)
	for k in ["vid", "by", "voters", "votes", "claim", "reason", "total",
			"approve_count", "reject_count", "remain_ms", "resolved", "approved", "cause"]:
		_check(snap.has(k), "⑪ 快照字段 %s 存在" % k)
	_check(int(snap["vid"]) == 7 and int(snap["by"]) == 0, "⑪ 快照带投票号与出题人")
	_check((snap["claim"] as Dictionary).has("uids"), "⑪ 快照带待裁定的出牌 payload")
	_check(snap["votes"] == {1: true}, "⑪ 快照带逐人票型（int 键）")
	var first: Dictionary = vb.resolve()
	var second: Dictionary = vb.resolve(VoteBoxScript.CAUSE_TIMEOUT)
	_check(String(first["cause"]) == "timeout" and String(second["cause"]) == "timeout",
		"⑪ 重复 resolve 不改结论（幂等）")
	_check(int(second["vid"]) == 7, "⑪ 二次 resolve 仍返回同一个投票号")
