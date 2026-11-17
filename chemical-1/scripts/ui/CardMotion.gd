# ============================================================
# scripts/ui/CardMotion.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 2a，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 3435-3618 行 --------
# 桌面小卡入场：0.9 → 1.0 缩放 + 淡入（stagger 40ms）。
# 刻意不动 position —— 小卡位置是布局真值，测试与"桌面小卡槽"断言都按它算。
func _animate_mini_card_in(btn: Control, i: int) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.scale = Vector2(0.9, 0.9)
	btn.modulate = Color(1, 1, 1, 0)
	var old = btn.get_meta("mini_in_tween", false)
	if old is Tween and old.is_valid():
		old.kill()
	var tw: Tween = _ui.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var delay: float = _ui.MINI_CARD_IN_STAGGER * float(i)
	tw.tween_property(btn, "scale", Vector2.ONE, _ui.MINI_CARD_IN_MS / 1000.0).set_delay(delay)
	tw.tween_property(btn, "modulate:a", 1.0, _ui.MINI_CARD_IN_MS / 1000.0).set_delay(delay)
	btn.set_meta("mini_in_tween", tw)


# ============================================================
# 出牌 / 弃牌 / 抽牌（A3）
# ============================================================
# 为什么都走「幽灵牌」：_refresh_ui() 会把手牌整块重建（旧按钮 remove_child + queue_free），
# 任何「移动原按钮」的写法都会在半路凭空消失。duplicate 出来的副本挂在 ContentLayer 上
#（不随 hand_container 重建销毁），坐标一律用 global_position，跨容器也一致。
func _make_fly_ghost(btn: Control) -> Control:
	if btn == null or not is_instance_valid(btn):
		return null
	var ghost := btn.duplicate() as Control
	if ghost == null:
		return null
	ghost.name = "FlyGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = _ui.Z_DRAG
	# 手牌此刻可能正被悬停放大到 1.06，飞行统一从 1.0 起，避免终点缩放算不准
	ghost.scale = Vector2.ONE
	ghost.pivot_offset = Vector2(_ui.CARD_W, _ui.CARD_H) * 0.5
	_ui._layer(0).add_child(ghost)
	ghost.global_position = btn.global_position
	return ghost


# 二次贝塞尔取点（p = 0..1）：_fly_ghost 的抛物弧用它，避免手写两段 position 补间
func _bezier2(a: Vector2, c: Vector2, b: Vector2, p: float) -> Vector2:
	var q: float = 1.0 - p
	return a * (q * q) + c * (2.0 * q * p) + b * (p * p)


func _place_ghost(ghost: Control, to_pos: Vector2) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	ghost.global_position = to_pos


# arc > 0 时走抛物线（出牌）：中点抬高 arc，终点仍是 to_pos，落点精度不变
func _fly_ghost(ghost: Control, to_pos: Vector2, to_scale: float, ms: int, delay: float, arc: float) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	var dur: float = ms / 1000.0
	var from_pos: Vector2 = ghost.global_position
	var tw: Tween = _ui.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if arc > 0.0:
		var ctrl: Vector2 = (from_pos + to_pos) * 0.5 + Vector2(0, -arc)
		var steps = tw.tween_method(
			func(p: float): _place_ghost(ghost, _bezier2(from_pos, ctrl, to_pos, p)),
			0.0, 1.0, dur)
		steps.set_delay(delay)
	else:
		tw.tween_property(ghost, "global_position", to_pos, dur).set_delay(delay)
	tw.tween_property(ghost, "scale", Vector2(to_scale, to_scale), dur).set_delay(delay)
	# 末 40% 才淡出：前段要看清「是哪张牌飞过去了」
	tw.tween_property(ghost, "modulate:a", 0.0, dur * 0.6).set_delay(delay + dur * 0.4)
	tw.chain().tween_callback(ghost.queue_free)
	ghost.set_meta("fly_tween", tw)


# 出牌：抢在 _step_reset / _refresh_ui 之前拍下被选中手牌的位置（此时按钮还在）
func _capture_play_fly_in() -> Array:
	var snaps: Array = []
	if _ui.hand_container == null:
		return snaps
	for idx in _ui.selected_indices:
		if idx < 0 or idx >= _ui.hand_buttons.size():
			continue
		var btn = _ui.hand_buttons[idx]
		if not is_instance_valid(btn):
			continue
		var ghost: Control = _ui._make_fly_ghost(btn)
		if ghost == null:
			continue
		btn.visible = false          # 原位立刻空出来（旧按钮马上会被重建释放）
		snaps.append({"card": btn.get_meta("card", null), "ghost": ghost})
	return snaps


# 出牌收尾：桌面小卡已就位 → 幽灵牌飞到对应小卡上并淡出。
# 配对按「卡片对象」而不是下标：化合物的小卡会按化学式重排，下标对不上。
func _replay_play_fly_in(snaps: Array) -> void:
	if snaps.is_empty():
		return
	var used: Array = []
	for i in range(snaps.size()):
		var ghost = snaps[i].get("ghost", null)
		if ghost == null or not is_instance_valid(ghost):
			continue
		var card = snaps[i].get("card", null)
		var target: Rect2 = Rect2()
		for k in range(_ui.table_card_buttons.size()):
			if k in used:
				continue
			var mb = _ui.table_card_buttons[k]
			if is_instance_valid(mb) and mb.get_meta("card", null) == card:
				target = Rect2(mb.global_position, mb.size)
				used.append(k)
				break
		if target.size == Vector2.ZERO:
			# 桌面没对上（理论上不会）→ 至少朝桌面小卡槽飞过去，别原地消失
			var slot := Rect2(Vector2(20, 186), Vector2(72, 90))
			target = slot
		var to: Vector2 = target.position + (target.size - Vector2(_ui.CARD_W, _ui.CARD_H)) * 0.5
		_ui._fly_ghost(ghost, to, _ui.PLAY_FLY_SCALE, _ui.PLAY_FLY_MS, 0.03 * float(i), _ui.PLAY_FLY_ARC)


# 弃牌：从原位向上抬起并淡出 —— 「这张牌离开手牌」的唯一视觉出口
func _fly_discarded_card() -> void:
	if _ui.hand_container == null or _ui.selected_indices.size() != 1:
		return
	var idx: int = _ui.selected_indices[0]
	if idx < 0 or idx >= _ui.hand_buttons.size():
		return
	var btn = _ui.hand_buttons[idx]
	if not is_instance_valid(btn):
		return
	var ghost: Control = _ui._make_fly_ghost(btn)
	if ghost == null:
		return
	btn.visible = false
	_ui._fly_ghost(ghost, ghost.global_position + Vector2(0, -_ui.DISCARD_FLY_LIFT), 0.92, _ui.DISCARD_FLY_MS, 0.0)


# 抽牌 / 发牌：新出现的卡片对象从手牌区上方 DEAL_IN_DROP 处落下 + 淡入
#（开局 8 张全部算新增 → 自带一次发牌入场）。
# 只动 position / modulate：scale 归悬停 / 选中缩放补间管，两边同时改会互相拉扯。
# 落点用 _layout_hand_cards() 写好的 meta("base_pos")（真实布局结果）；
# 补间结束时强制归位 —— 入场途中若发生重排，base_pos 已是新值，这一句把牌钉回真值。
func _animate_new_hand_cards() -> void:
	var now_cards: Array = []
	var order: int = 0
	for b in _ui.hand_buttons:
		if not is_instance_valid(b):
			continue
		var c = b.get_meta("card", null)
		if c == null:
			continue
		now_cards.append(c)
		if c in _ui._hand_seen_cards:
			continue
		var base_pos: Vector2 = b.get_meta("base_pos", b.position)
		var old = b.get_meta("deal_in_tween", false)
		if old is Tween and old.is_valid():
			old.kill()
		b.position = base_pos + Vector2(0, -_ui.DEAL_IN_DROP)
		b.modulate = Color(1, 1, 1, 0.0)
		var tw: Tween = _ui.create_tween()
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var delay: float = _ui.DEAL_IN_STAGGER * float(order)
		tw.tween_property(b, "position", base_pos, _ui.DEAL_IN_MS / 1000.0).set_delay(delay)
		# 透明度比位移先走完（0.7 倍时长）：牌落到位时已经实心，不会有「落定才显形」的断层
		tw.tween_property(b, "modulate:a", 1.0, _ui.DEAL_IN_MS / 1000.0 * 0.7).set_delay(delay)
		tw.chain().tween_callback(func(): _ui._snap_card_position(b, base_pos))
		b.set_meta("deal_in_tween", tw)
		order += 1
	_ui._hand_seen_cards = now_cards


# 入场收尾：无论补间被谁打断，牌都必须停在布局真值上
func _snap_card_position(btn: Control, to_pos: Vector2) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.position = to_pos
