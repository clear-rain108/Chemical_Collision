# 验证手牌视角 / 只读 / 重叠点击命中 / 稀有气体配色
#   1) 重叠区点击必须判给「视觉最上层」，不能因为悬停抬起而落到下层牌
#   2) 单人类（1 人 + N AI）：AI 回合仍显示自己的手牌，但整体只读
#   3) 热座（多人类）：AI 回合谁的牌都不显示（同屏不能互相看牌）
#   4) 稀有气体不再是近白色
extends SceneTree

var fails: int = 0

func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _run():
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_test_noble_color(scene)

	scene.call("_on_start_game")
	for _w in range(5):
		await process_frame

	_test_click_hit(scene)
	await _test_single_human_ai_turn(scene)
	await _test_hotseat_ai_turn(scene)

	if fails == 0:
		print("ALL HAND VIEW TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


# ------------------------------------------------------------
# 1) 重叠区点击命中
# ------------------------------------------------------------
func _test_click_hit(scene) -> void:
	var n: int = scene.hand_buttons.size()
	_check(n >= 2, "开局后手牌已生成 (n=%d)" % n)
	if n < 2:
		return
	var cw: float = scene.CARD_W

	# 信号接线：点击必须经「所见即所得」重算命中，
	# 若仍绑死索引（_on_card_clicked.bind(idx)）就会重现「点最上层却选中下层」
	var wired := false
	var conns: Array = scene.hand_buttons[0].pressed.get_connections()
	for c in conns:
		var cb = c.get("callable")
		if cb != null and cb.get_method() == "_on_card_pressed":
			wired = true
	_check(wired, "卡牌点击接到 _on_card_pressed（按指针位置重算命中）")

	var overlap_ok := true
	var strip_ok := true
	var sample := 0
	for i in range(mini(3, n - 1)):
		var p0: Vector2 = scene.hand_buttons[i].get_meta("base_pos")
		var p1: Vector2 = scene.hand_buttons[i + 1].get_meta("base_pos")
		if p1.x >= p0.x + cw:
			continue   # 两张没重叠（牌少时），跳过
		sample += 1
		# 静止堆叠（没有抬起牌）：后一张画在上面，重叠带归它
		var mx: float = (p1.x + p0.x + cw) * 0.5
		var got: int = scene.call("_hover_hit_index", Vector2(mx, p0.y + 50.0))
		if got != i + 1:
			overlap_ok = false
			print("  · 重叠带 x=%.1f 期望 %d 实际 %d" % [mx, i + 1, got])
		# 露出的左条：只属于自己
		var sx: float = (p0.x + p1.x) * 0.5
		var got2: int = scene.call("_hover_hit_index", Vector2(sx, p0.y + 50.0))
		if got2 != i:
			strip_ok = false
			print("  · 左条 x=%.1f 期望 %d 实际 %d" % [sx, i, got2])
	_check(sample > 0, "手牌确实处于重叠排列（采样 %d 对）" % sample)
	_check(overlap_ok, "静止堆叠：重叠带判给后一张")
	_check(strip_ok, "每张牌露出的左条判给自己")

	# 抬起后多出来的顶部容错带仍归最后一张
	var plast: Vector2 = scene.hand_buttons[n - 1].get_meta("base_pos")
	var top_mp := Vector2(plast.x + cw * 0.5, plast.y - 10.0)
	_check(scene.call("_hover_hit_index", top_mp) == n - 1,
		"抬起后的顶部容错带仍归最后一张")

	# 回归点（用户实测踩到）：第 i 张已抬起（z=20 压在右侧那张之上），
	# 鼠标落在两者重叠带里 —— 视觉上是抬起的这张，点击 / 拖拽起点就必须选中它。
	# 只按「取最大索引」会判给右侧那张，正是「悬停显示 Ca、点下去选中 Ni」。
	var raised_ok := true
	var fork_ok := true
	var fallback_ok := true
	var rc := 0
	for i in range(mini(3, n - 1)):
		var q0: Vector2 = scene.hand_buttons[i].get_meta("base_pos")
		var q1: Vector2 = scene.hand_buttons[i + 1].get_meta("base_pos")
		if q1.x >= q0.x + cw:
			continue
		scene.call("_set_hover_index", i)
		if scene._hover_idx != i:
			raised_ok = false
			print("  · _set_hover_index(%d) 未生效（当前 %d）" % [i, scene._hover_idx])
			continue
		rc += 1
		var band_x: float = (q1.x + q0.x + cw) * 0.5
		var band := Vector2(band_x, q0.y + 40.0)
		var hit_self: int = scene.call("_hit_card_at", band)
		if hit_self != i:
			raised_ok = false
			print("  · 抬起 %d 后点重叠带 x=%.1f 期望 %d 实际 %d"
				% [i, band_x, i, hit_self])
		# 同一点按「取最大索引」会落到右侧那张 —— 证明两条规则确实分叉
		if scene.call("_hover_hit_index", band) != i + 1:
			fork_ok = false
		# 右侧那张露在抬起牌外面的部分：不在抬起矩形内，仍归它自己
		# 露出条 = [第 i 张右边缘, 第 i+2 张左边缘)（步距 60、牌宽 95 → 宽 25px），
		# 取靠内侧 5px，避免落进第 i+2 张
		var right_x: float = q0.x + cw + 5.0
		var hit_next: int = scene.call("_hit_card_at", Vector2(right_x, q1.y + 50.0))
		if hit_next != i + 1:
			raised_ok = false
			print("  · 抬起 %d 时点右侧露出部分 x=%.1f 期望 %d 实际 %d"
				% [i, right_x, i + 1, hit_next])
		# 抬起牌让出的底部 20px（视觉上已是右侧那张）→ 判给右侧那张
		var under := Vector2(band_x, q0.y + scene.CARD_H - 5.0)
		var hit_under: int = scene.call("_hit_card_at", under)
		if hit_under != i + 1:
			fallback_ok = false
			print("  · 抬起 %d 后点其让出的底部带 期望 %d 实际 %d"
				% [i, i + 1, hit_under])
	_check(rc > 0, "已构造出「抬起牌 + 重叠带」场景（%d 组）" % rc)
	_check(raised_ok, "抬起牌压住的重叠带判给它自己，右侧露出部分判给右牌")
	_check(fork_ok, "同一点按“取最大索引”会落到右牌（两条规则已分叉）")
	_check(fallback_ok, "抬起牌让出的底部 20px 判给视觉上的右牌")
	scene.call("_set_hover_index", -1)


# ------------------------------------------------------------
# 2) 单人类模式：AI 回合仍显示自己的牌（只读）
# ------------------------------------------------------------
func _test_single_human_ai_turn(scene) -> void:
	var gm = scene.game_manager
	var humans: Array = scene.call("_human_players")
	_check(humans.size() == 1, "默认开局为单人类模式（人类 %d 人）" % humans.size())
	if humans.size() != 1:
		return
	var me = humans[0]
	var me_idx: int = gm.players.find(me)
	var ai_idx := -1
	for i in range(gm.players.size()):
		if gm.players[i].is_ai:
			ai_idx = i
			break
	if ai_idx < 0:
		_check(false, "找不到 AI 座位")
		return

	gm.current_player_index = ai_idx
	scene.call("_update_hand_buttons")
	await process_frame

	_check(scene.call("_hand_view_player", null) == me, "AI 回合的视角座位是玩家自己")
	_check(scene.hand_buttons.size() == me.hand.size(),
		"AI 回合仍显示自己的手牌 (渲染 %d / 实有 %d)"
			% [scene.hand_buttons.size(), me.hand.size()])
	_check(scene._hand_read_only == true, "AI 回合手牌为只读")
	if scene.hand_buttons.is_empty():
		return
	_check(scene.hand_buttons[0].mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"只读手牌不接收鼠标")
	_check(scene.call("_can_reorder_hand") == false, "只读时不允许重排")

	var sel_before: Array = scene.selected_indices.duplicate()
	scene.call("_on_card_clicked", 0)
	_check(scene.selected_indices == sel_before, "只读时点击不改变选中")

	# 悬停不得抬牌（唯一强制点在 _update_hover_at）
	var p0: Vector2 = scene.hand_buttons[0].get_meta("base_pos")
	scene.call("_update_hover_at", Vector2(p0.x + 10.0, p0.y + 50.0))
	_check(scene._hover_idx == -1, "只读时悬停不抬牌")

	scene.call("_update_card_info_label")
	_check(scene.card_info_label.text.contains("等待"),
		"信息栏说明在等谁：%s" % scene.card_info_label.text)

	# 回到人类回合：只读解除
	gm.current_player_index = me_idx
	scene.call("_update_hand_buttons")
	await process_frame
	_check(scene._hand_read_only == false, "人类回合恢复可操作")
	_check(scene.hand_buttons.size() == me.hand.size(), "人类回合手牌数不变")


# ------------------------------------------------------------
# 3) 热座模式：AI 回合不显示任何人的手牌
# ------------------------------------------------------------
func _test_hotseat_ai_turn(scene) -> void:
	var gm = scene.game_manager
	gm.init_game(4, 1, 20261101)   # 3 人类 + 1 AI（人类座位固定在前）
	scene.call("_update_hand_buttons")
	await process_frame

	var humans: Array = scene.call("_human_players")
	_check(humans.size() == 3, "热座：人类座位 %d 个" % humans.size())
	if humans.size() < 2:
		return

	# AI 回合
	gm.current_player_index = 3
	_check(scene.call("_hand_view_player", null) == null,
		"热座 AI 回合：视角为空（不显示任何人手牌）")
	scene.call("_update_hand_buttons")
	await process_frame
	_check(scene.hand_buttons.is_empty(),
		"热座 AI 回合：手牌区不渲染牌 (n=%d)" % scene.hand_buttons.size())
	var waiting := _label_text(scene.hand_container, "等待")
	_check(waiting != "", "热座 AI 回合：显示等待提示（%s）" % waiting)

	# 人类回合：显示当前玩家的手牌，可操作
	gm.current_player_index = 1
	scene.call("_update_hand_buttons")
	await process_frame
	_check(scene.hand_buttons.size() == gm.players[1].hand.size(),
		"热座人类回合：渲染当前玩家手牌 (渲染 %d / 实有 %d)"
			% [scene.hand_buttons.size(), gm.players[1].hand.size()])
	_check(scene._hand_read_only == false, "热座人类回合：可操作（非只读）")
	_check(scene.call("_can_reorder_hand") == true, "热座人类回合：允许重排")


func _label_text(root_node: Node, needle: String) -> String:
	for c in root_node.get_children():
		if c is Label and str(c.text).contains(needle):
			return str(c.text)
	return ""


# ------------------------------------------------------------
# 4) 稀有气体配色
# ------------------------------------------------------------
func _test_noble_color(scene) -> void:
	var cd = load("res://scripts/CardData.gd").new()
	cd.symbol = "He"
	cd.element_type = "稀有气体"
	cd.group = "0"
	var col: Color = scene.call("_get_card_color", cd)
	_check(col.get_luminance() < 0.6,
		"稀有气体不再是近白（亮度 %.2f）" % col.get_luminance())
	_check(col.b > col.r + 0.3,
		"稀有气体为青色系 (R=%.2f G=%.2f B=%.2f)" % [col.r, col.g, col.b])
	var card_bg := Color(0.973, 0.976, 0.988)
	_check(card_bg.get_luminance() - col.get_luminance() > 0.3,
		"与卡面底色有足够明度差 (%.2f)" % (card_bg.get_luminance() - col.get_luminance()))
