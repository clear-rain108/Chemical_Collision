# 验证开始页（P6）的交互接线 —— 覆盖三个真实踩过的坑：
#   1) 人数框 / AI 框 / 规则开关 / 补充规则入口都嵌在 SettingsCard 内，
#      必须能通过 _start_child() 递归取到（否则静默失效：AI 永远 3、开关永远关）
#   2) AI ≤ 总人数 - 1，改总人数时 AI 要跟着被压下来；开始游戏要按界面数字生效
#   3) 帮助页「看三张典型牌」示例卡第 4 行是常见化合价，29 种元素网格才是牌库张数 ×N
extends SceneTree

var fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _labels(node: Node, out: Array) -> void:
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels(c, out)


func _finish() -> void:
	if fails == 0:
		print("ALL START PAGE TESTS PASSED")
	else:
		print("%d START PAGE TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# ---------------- 1. 绑定 ----------------
	_check(scene.player_spin != null, "PlayerCountSpin 绑定成功（嵌在 SettingsCard 内也能取到）")
	_check(scene.ai_spin != null, "AiCountSpin 绑定成功")
	_check(scene.start_button != null, "StartButton 绑定成功")
	_check(scene._start_child("OrganicCheckBox") != null, "OrganicCheckBox 可取到")
	_check(scene._start_child("SequenceCheckBox") != null, "SequenceCheckBox 可取到")
	_check(scene._start_child("HalogenCheckBox") != null, "HalogenCheckBox 可取到")
	_check(scene._start_child("SupplementaryHelpBtn") != null, "SupplementaryHelpBtn 可取到")
	if scene.player_spin == null or scene.ai_spin == null:
		_finish()
		return
	_check(int(scene.player_spin.value) == 4, "默认总人数 4")
	_check(int(scene.ai_spin.value) == 3, "默认 AI 3")
	_check(int(scene.ai_spin.max_value) == 3,
		"AI 上限 = 总人数-1 = 3（实际 %d）" % int(scene.ai_spin.max_value))

	# ---------------- 2. 人数联动 ----------------
	scene.player_spin.value = 3
	await process_frame
	_check(int(scene.ai_spin.max_value) == 2, "总人数 3 → AI 上限 2（实际 %d）" % int(scene.ai_spin.max_value))
	_check(int(scene.ai_spin.value) == 2, "AI 自动降为 2（实际 %d）" % int(scene.ai_spin.value))
	scene.player_spin.value = 6
	await process_frame
	_check(int(scene.ai_spin.max_value) == 5, "总人数 6 → AI 上限 5（实际 %d）" % int(scene.ai_spin.max_value))
	scene.ai_spin.value = 5
	scene.player_spin.value = 4
	await process_frame
	_check(int(scene.ai_spin.value) == 3, "总人数改回 4 → AI 被压回 3（实际 %d）" % int(scene.ai_spin.value))
	# 绕过 UI 直接塞非法值（键盘输入 / 脚本），仍不能 AI ≥ 总人数
	scene.ai_spin.max_value = 7
	scene.ai_spin.value = 7
	scene.player_spin.value = 5
	await process_frame
	_check(int(scene.ai_spin.value) <= 4, "AI 不允许 >= 总人数（实际 %d）" % int(scene.ai_spin.value))
	# AI = 0 会让其余座位变成无人操作的人类（开局即卡死）→ 界面下限 1
	_check(int(scene.ai_spin.min_value) == 1, "AI 下限 1（实际 %d）" % int(scene.ai_spin.min_value))

	# ---------------- 3. 「查看补充规则」入口 ----------------
	scene._start_child("SupplementaryHelpBtn").pressed.emit()
	await process_frame
	_check(scene.help_page != null and scene.help_page.visible, "点「查看补充规则」打开帮助中心")
	_check(scene._help_tab == 2, "打开后停在第 3 个 Tab「补充规则」（实际 %d）" % scene._help_tab)
	scene.help_page.visible = false
	scene.start_page.visible = true

	# ---------------- 4. 规则开关 + 开局参数 ----------------
	var organic = scene._start_child("OrganicCheckBox")
	_check(organic.toggle_mode, "有机物开关是 toggle 按钮")
	organic.button_pressed = true
	await process_frame
	scene.player_spin.value = 5
	scene.ai_spin.value = 2
	await process_frame
	scene._on_start_game()
	await process_frame
	_check(scene.game_manager != null, "进入游戏")
	if scene.game_manager:
		_check(scene.game_manager.get_players().size() == 5,
			"总人数按设置生效 = 5（实际 %d）" % scene.game_manager.get_players().size())
		_check(scene.game_manager.organic_rules_enabled, "有机物规则按开关生效")
		_check(not scene.game_manager.get_sequence_rules_enabled(),
			"只勾有机物时，顺序规则保持关闭（两条开关互不影响）")
		_check(not scene.game_manager.get_halogen_exchange_allowed(),
			"只勾有机物时，卤族互化保持禁止（默认值）")
		_check(_count_ai(scene.game_manager) == 2,
			"AI 人数按设置生效 = 2（实际 %d）" % _count_ai(scene.game_manager))

	# 第二局：绕开下限把 AI 设成 0（模拟脚本 / 旧数据），开局必须抬到 1，
	# 否则剩下的座位是没人操作的人类，开局即卡死；同时验证「只勾顺序」也能独立生效
	scene._show_start_page()
	await process_frame
	organic.button_pressed = false
	var seq_cb = scene._start_child("SequenceCheckBox")
	seq_cb.button_pressed = true
	await process_frame
	scene.player_spin.value = 4
	scene.ai_spin.min_value = 0
	scene.ai_spin.value = 0
	await process_frame
	scene._on_start_game()
	await process_frame
	_check(scene.game_manager != null and _count_ai(scene.game_manager) == 1,
		"AI=0 被抬到 1，不会出现无人操作的人类（实际 %d）" % _count_ai(scene.game_manager))
	_check(scene.game_manager != null and scene.game_manager.get_sequence_rules_enabled()
			and not scene.game_manager.get_organic_rules_enabled(),
		"只勾顺序时，顺序规则生效且有机物规则关闭")

	# 第三局：卤族互化开关独立生效（默认禁止，勾选后放行）
	scene._show_start_page()
	await process_frame
	seq_cb.button_pressed = false
	var halogen_cb = scene._start_child("HalogenCheckBox")
	_check(halogen_cb != null and halogen_cb.toggle_mode, "HalogenCheckBox 是 toggle 按钮")
	if halogen_cb:
		var hal_rect := Rect2(halogen_cb.position, halogen_cb.size)
		var supp_node = scene._start_child("SupplementaryHelpBtn")
		var supp_rect := Rect2(supp_node.position, supp_node.size)
		_check(not hal_rect.intersects(supp_rect),
			"卤族开关与「查看补充规则」不重叠 %s / %s" % [str(hal_rect), str(supp_rect)])
		_check(hal_rect.end.x <= 580.0, "卤族开关在设置卡内（右边界 %.0f）" % hal_rect.end.x)
		halogen_cb.button_pressed = true
	await process_frame
	scene._on_start_game()
	await process_frame
	_check(scene.game_manager != null and scene.game_manager.get_halogen_exchange_allowed(),
		"卤族互化开关按设置生效（勾选后允许）")
	_check(scene.game_manager != null and not scene.game_manager.get_organic_rules_enabled()
			and not scene.game_manager.get_sequence_rules_enabled(),
		"只勾卤族互化时，另两条规则保持关闭")

	# ---------------- 5. 帮助页示例牌：化合价 vs 张数 ----------------
	scene._open_help_at_tab(1)
	await process_frame
	var lbs: Array = []
	_labels(scene.help_page, lbs)
	var texts: Array = []
	for l in lbs:
		texts.append(l.text)
	_check("+1" in texts, "示例牌显示 Na 常见化合价 +1")
	_check("-2" in texts, "示例牌显示 O 常见化合价 -2")

	# 「看三张典型牌」是唯一一个 3 张并排的 HBoxContainer
	var demo: Array = _demo_fourth_row(scene.help_bodies[1])
	_check(demo.size() == 3, "示例行有 3 张迷你卡（实际 %d）" % demo.size())
	_check(demo == ["+1", "-2", "-1 +1…"],
		"示例卡第 4 行是化合价 Na=+1 / O=-2 / Cl=-1 +1…（实际 %s）" % str(demo))
	# 29 种元素网格仍要显示牌库张数
	var grid_texts: Array = []
	for panel in _find_all(scene.help_bodies[1], "PanelContainer"):
		if panel.custom_minimum_size == Vector2(96, 124):
			for l in _labels_of(panel):
				if l.text.begins_with("×"):
					grid_texts.append(l.text)
	_check("×6" in grid_texts and "×10" in grid_texts,
		"图鉴网格仍显示张数 ×6 / ×10（实际 %d 个）" % grid_texts.size())

	_finish()


# AI 玩家数（用于核对开局参数是否真的按界面数字生效）
func _count_ai(gm) -> int:
	var n := 0
	for p in gm.get_players():
		if p.is_ai:
			n += 1
	return n


func _find_all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_all(c, cls))
	return out


func _labels_of(node: Node) -> Array:
	var out: Array = []
	_labels(node, out)
	return out


# 迷你卡结构：MarginContainer → PanelContainer → VBox[原子序数行/符号/中文名/第4行/原子量]
func _demo_fourth_row(body: Node) -> Array:
	var out: Array = []
	for hb in _find_all(body, "HBoxContainer"):
		if hb.get_child_count() != 3:
			continue
		var all_margin := true
		for ch in hb.get_children():
			if not (ch is MarginContainer):
				all_margin = false
		if not all_margin:
			continue
		for ch in hb.get_children():
			var vb = ch.get_child(0).get_child(0)
			if vb.get_child_count() < 4:
				out.append("")
			else:
				out.append(vb.get_child(3).text)
	return out

