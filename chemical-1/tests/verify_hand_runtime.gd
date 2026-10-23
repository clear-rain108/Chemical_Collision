# 验证真实对局中手牌重叠布局生效（开始游戏 → 生成手牌 → 点击选牌）
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

	scene.call("_on_start_game")
	await process_frame
	await process_frame

	var hc: Control = scene.get_node_or_null("GamePage/HandContainer")
	var hb: Array = scene.hand_buttons
	_check(hb.size() > 0, "开始游戏后生成手牌 (%d 张)" % hb.size())
	if hb.is_empty():
		print("ABORT: 手牌为空")
		quit(1)
		return

	var ok_size := true
	var ok_bounds := true
	var ok_base_y := true
	for b in hb:
		if not is_instance_valid(b): continue
		if abs(b.size.x - 95.0) > 0.01 or abs(b.size.y - 118.0) > 0.01: ok_size = false
		if b.position.x < -0.01 or b.position.x + 95.0 > hc.size.x + 0.01: ok_bounds = false
		if abs(b.position.y - (hc.size.y - 118.0 - 20.0)) > 0.01: ok_base_y = false
	_check(ok_size, "实际手牌尺寸均为 95x118")
	_check(ok_bounds, "实际手牌全部在容器水平范围内")
	_check(ok_base_y, "实际手牌基准 y 预留了容器内的悬停上浮空间")

	# 真实卡牌必须包含紧凑模式所需的命名子节点
	var has_sym := true
	var has_nm := true
	var has_val := true
	for b in hb:
		if not is_instance_valid(b): continue
		if b.get_node_or_null("CardSymbol") == null: has_sym = false
		if b.get_node_or_null("CardName") == null: has_nm = false
		if b.get_node_or_null("CardValence") == null: has_val = false
	_check(has_sym, "真实卡牌含 CardSymbol 节点（重叠时可切换左对齐）")
	_check(has_nm, "真实卡牌含 CardName 节点")
	_check(has_val, "真实卡牌含 CardValence 节点")

	# 点击首张牌：选中 → 重建 → 数量不变、位置仍合法、无崩溃
	var n0: int = hb.size()
	scene.call("_on_card_clicked", 0)
	await process_frame
	await process_frame
	var hb2: Array = scene.hand_buttons
	_check(hb2.size() == n0, "点击选牌后手牌数量不变 (%d)" % hb2.size())
	_check(scene.selected_indices.has(0), "首张牌已被选中")
	var ok2 := true
	for b in hb2:
		if not is_instance_valid(b): continue
		if b.position.x < -0.01 or b.position.x + 95.0 > hc.size.x + 0.01: ok2 = false
	_check(ok2, "重建后手牌位置仍合法")

	# 再点一次取消选中
	scene.call("_on_card_clicked", 0)
	await process_frame
	_check(not scene.selected_indices.has(0), "再次点击已取消选中")

	# 满手牌 16 张：应自动重叠 + 紧凑牌面
	var cp = scene.game_manager.get_current_player()
	if not cp.is_ai and cp.hand.size() > 0:
		var guard := 0
		while cp.hand.size() < 16 and guard < 40:
			cp.hand.append(cp.hand[0])
			guard += 1
		scene.call("_update_hand_buttons")
		await process_frame
		var hb3: Array = scene.hand_buttons
		_check(hb3.size() == 16, "补满后手牌 16 张 (%d)" % hb3.size())
		if hb3.size() == 16:
			var f: Button = hb3[0]
			var l: Button = hb3[15]
			var st: float = (l.position.x - f.position.x) / 15.0
			_check(st < 95.0, "16 张时产生重叠 step=%.2f" % st)
			_check(st >= 40.0, "16 张时仍保留足够可读宽度 step=%.2f >= 40" % st)
			_check(l.position.x + 95.0 <= hc.size.x + 0.01, "16 张时末牌未溢出容器")
			var sym: Label = f.get_node_or_null("CardSymbol")
			_check(sym != null and sym.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
				"16 张时符号切换为左对齐（紧凑牌面）")
			# 悬停抬起不被裁剪（上浮 20 后仍 >= 0）
			scene.call("_on_hand_card_hover", f, true)
			_check(f.position.y >= -0.01, "16 张时悬停上浮后仍完整可见 (y=%.2f)" % f.position.y)
			scene.call("_on_hand_card_hover", f, false)

	if fails == 0:
		print("ALL HAND RUNTIME TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)
