# 验证手牌重叠布局：尺寸、居中、重叠步长、悬停上浮
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

	var hc = scene.get_node_or_null("GamePage/HandContainer")
	_check(hc != null, "HandContainer 节点存在")
	if hc == null:
		print("ABORT: 找不到 HandContainer")
		quit(1)
		return

	_check(not (hc is Container), "HandContainer 已改为 Control（非自动布局容器）")
	var sz: Vector2 = hc.size
	_check(abs(sz.x - 804.0) < 0.5 and abs(sz.y - 158.0) < 0.5,
		"手牌区尺寸应为 804x158，实际 %s" % str(sz))

	# 防抖验证必须在开赛之前：开赛后 AI 回合会刷新重建手牌，
	# 导致测试持有的按钮引用脱离 hand_buttons，观测不到状态机
	await _test_hover_debounce(scene, hc)
	# 流畅化验证复用上面这 8 张合成牌（开赛后引用会失效）
	await _test_hover_smoothness(scene)

	# 开始对局，生成真实手牌后再检查信息栏 / tooltip 行为
	scene.call("_on_start_game")
	for _w in range(5):
		await process_frame
	_test_info_and_tooltip(scene)
	_test_selected_style(scene)
	_test_layers(scene)
	_test_tutorial_layout(scene)
	_test_warning_toast(scene)
	_test_style_factory(scene)

	await _test_case(scene, hc, 16, true)
	await _test_case(scene, hc, 8, true)
	await _test_case(scene, hc, 7, false)
	await _test_case(scene, hc, 3, false)

	if fails == 0:
		print("ALL HAND LAYOUT TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


# 悬停详情改由下方信息栏显示（不再用原生 tooltip 遮挡手牌）
func _test_info_and_tooltip(scene) -> void:
	if scene.hand_buttons.is_empty() and scene.game_manager != null:
		scene.call("_update_hand_buttons")
	var reals: Array = scene.hand_buttons
	_check(reals.size() > 0, "真实手牌已生成 (n=%d)" % reals.size())
	if reals.is_empty(): return
	var rb = reals[0]
	_check(rb.tooltip_text == "", "手牌不使用原生 tooltip（tooltip_text 为空）")

	var info: Label = scene.card_info_label
	_check(info != null, "CardInfoLabel 存在")
	if info == null: return
	_check(abs(info.size.x - 804.0) < 0.5 and abs(info.position.x - 16.0) < 0.5,
		"信息栏已扩为手牌下方整宽区域 (x=%.1f w=%.1f)" % [info.position.x, info.size.x])

	var before: String = info.text
	# 悬停样式由状态机切换 normal；但引擎的 hover/pressed/focus 主题项必须显式接管，
	# 否则鼠标真的停在牌上时，引擎会回退到默认（深色）主题画一块半透明深灰
	# —— 那就是"选中后发黑"的根因。
	_check(rb.get_meta("sb_hover", null) != null and rb.get_meta("sb_normal", null) != null,
		"真实按钮保存了 normal/hover 两套样式")
	_check(rb.has_theme_stylebox_override("hover"),
		"已接管引擎 hover 主题项（避免回退默认深灰）")
	_check(rb.get_theme_stylebox("hover") == rb.get_theme_stylebox("normal"),
		"hover 与 normal 同源（引擎 hover 判定切换不可见）")
	_check(rb.get_theme_stylebox("pressed") == rb.get_theme_stylebox("normal"),
		"pressed 与 normal 同源（点击瞬间不变色）")
	_check(rb.get_theme_stylebox("focus") is StyleBoxEmpty,
		"focus 使用 StyleBoxEmpty（无焦点框）")
	scene.call("_on_hand_card_hover", rb, true)
	_check(rb.get_theme_stylebox("normal") == rb.get_meta("sb_hover"),
		"悬停时 normal 切换为悬停样式")
	_check(info.text.contains("原子序数") and info.text.contains("相对原子质量"),
		"悬停时信息栏显示卡牌详情：%s" % info.text)
	_check(not info.text.contains("\n"), "详情为单行文本")
	scene.call("_on_hand_card_hover", rb, false)
	_check(rb.get_theme_stylebox("normal") == rb.get_meta("sb_normal"),
		"移出后 normal 还原为基础样式")
	_check(info.text == before, "移出后信息栏还原为原提示文本")


# 选中态：浅黄底 + 橙金边；三个引擎状态同源，绝不会被默认深灰盖掉
# ---- 层级容器：浮层必须盖住手牌（z_index 优先于树顺序）----
# 历史 bug：手牌悬停 z=100 / 选中 z=50 会穿透「顺序指定」弹窗与警告提示框
func _test_layers(scene) -> void:
	var gp = scene.get_node_or_null("GamePage")
	_check(gp != null, "GamePage 节点存在")
	if gp == null:
		return
	var content = gp.get_node_or_null("ContentLayer")
	var overlay = gp.get_node_or_null("OverlayLayer")
	var toast = gp.get_node_or_null("ToastLayer")
	_check(content != null and overlay != null and toast != null,
		"层容器齐全 (ContentLayer / OverlayLayer / ToastLayer)")
	if content == null or overlay == null or toast == null:
		return
	_check(content.z_index == 0, "ContentLayer z=0 (实际 %d)" % content.z_index)
	_check(overlay.z_index == 100, "OverlayLayer z=100 (实际 %d)" % overlay.z_index)
	_check(toast.z_index == 110, "ToastLayer z=110 (实际 %d)" % toast.z_index)
	# 手牌最高 z（悬停 20）必须低于模态层，否则弹窗会被手牌打洞
	_check(20 < overlay.z_index and overlay.z_index < toast.z_index,
		"手牌最高 z < 模态层 < 提示层 (overlay=%d toast=%d)" % [overlay.z_index, toast.z_index])
	_check(content.anchor_right == 1.0 and content.anchor_bottom == 1.0,
		"层容器铺满全屏")
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"层容器自身不拦截鼠标（事件仍落到子节点）")

	# 顺序指定弹窗必须落在 OverlayLayer（手牌穿透弹窗的回归点）
	var ov_before: int = overlay.get_child_count()
	scene.call("_show_sequence_constraint_dialog")
	_check(overlay.get_child_count() == ov_before + 1, "顺序指定弹窗挂入 OverlayLayer")
	for ch in overlay.get_children():
		overlay.remove_child(ch)
		ch.queue_free()

	# 警告提示必须落在 ToastLayer（警告框被手牌盖住的回归点）
	var ts_before: int = toast.get_child_count()
	scene.call("_show_center_warning", "层级回归测试")
	_check(toast.get_child_count() == ts_before + 1, "警告提示挂入 ToastLayer")


# ---- 教程引导文本：必须与桌面小卡槽 / 日志区错开 ----
# 历史 bug：TutorialLabel 原 (225,185)-(1125,225) 与桌面小卡槽 (20,186)-(600,276)
# 完全重叠，桌面打出牌后小卡直接压掉引导文本第一行；40px 高也装不下
# 「引导 2 行 + 成功提示 1 行」折行后的 4 行。
func _test_tutorial_layout(scene) -> void:
	var gp = scene.get_node_or_null("GamePage")
	if gp == null:
		_check(false, "教程文本布局：找不到 GamePage")
		return
	var tl = gp.get_node_or_null("TutorialLabel")
	_check(tl != null, "TutorialLabel 节点存在")
	if tl == null:
		return
	var tr := Rect2(tl.position, tl.size)

	# 桌面小卡槽：\"桌面: …\" 下方一行，单张 72x90，横向 20..600（见 _update_table_label）
	var tbl = gp.get_node_or_null("TableLabel")
	_check(tbl != null, "TableLabel 节点存在")
	if tbl:
		var slot := Rect2(20.0, tbl.position.y + tbl.size.y + 4.0, 580.0, 90.0)
		_check(not slot.intersects(tr),
			"教程文本不与桌面小卡槽重叠 (tutorial=%s slot=%s)" % [str(tr), str(slot)])

	# 右侧日志区：曾经与教程文本同处一段时间，导致文字互相压盖
	var lg = gp.get_node_or_null("LogLabel")
	if lg:
		var lr := Rect2(lg.position, lg.size)
		_check(not lr.intersects(tr),
			"教程文本不与日志区重叠 (tutorial=%s log=%s)" % [str(tr), str(lr)])

	for n in ["InfoLabel", "HandLabel", "HandContainer", "CardInfoLabel"]:
		var c = gp.get_node_or_null(n)
		if c:
			_check(not Rect2(c.position, c.size).intersects(tr), "教程文本不与 %s 重叠" % n)

	# 容量：字号 14 / 行高 20，最长引导折行后约 4 行 → 至少 96px 高、480px 宽
	_check(tr.size.y >= 96.0, "教程文本高度≥96 可容纳 4 行（实际 %.1f）" % tr.size.y)
	_check(tr.size.x >= 480.0, "教程文本宽度≥480 长句不被切碎（实际 %.1f）" % tr.size.x)


func _test_selected_style(scene) -> void:
	if scene.hand_buttons.is_empty():
		scene.call("_update_hand_buttons")
	if scene.hand_buttons.is_empty():
		_check(false, "选中态测试：手牌为空")
		return
	scene.selected_indices = [0]
	scene.call("_update_hand_buttons")
	if scene.hand_buttons.is_empty():
		_check(false, "选中态测试：重建后手牌为空")
		scene.selected_indices = []
		return
	var b = scene.hand_buttons[0]
	var sb = b.get_theme_stylebox("normal")
	_check(sb is StyleBoxFlat, "选中牌使用 StyleBoxFlat")
	if sb is StyleBoxFlat:
		_check(sb.bg_color.is_equal_approx(Color(1.0, 1.0, 0.82, 1.0)),
			"选中牌底色为浅黄 (%s)" % str(sb.bg_color))
		_check(sb.border_color.is_equal_approx(Color(0.9, 0.65, 0.1, 1.0)),
			"选中牌边框为橙金 (%s)" % str(sb.border_color))
	_check(b.z_index == 10, "选中牌置于相邻牌之上 (z_index=%d)" % b.z_index)
	_check(b.get_theme_stylebox("hover") == sb, "选中牌 hover 与 normal 同源")
	_check(b.get_theme_stylebox("pressed") == sb, "选中牌 pressed 与 normal 同源")
	_check(b.get_theme_stylebox("focus") is StyleBoxEmpty, "选中牌无焦点框")
	# 选中牌悬停时必须保持黄色系：否则悬停样式（浅蓝）会把"已选中"整个盖掉
	scene.call("_on_hand_card_hover", b, true)
	var hov = b.get_theme_stylebox("normal")
	if hov is StyleBoxFlat:
		_check(hov.bg_color.r > 0.9 and hov.bg_color.b < 0.9,
			"选中牌悬停时仍为黄色系 (%s)" % str(hov.bg_color))
		_check(hov.border_color.b < 0.5,
			"选中牌悬停时边框仍为暖色 (%s)" % str(hov.border_color))
	scene.call("_on_hand_card_hover", b, false)
	# 取消选中后应恢复基础白底
	scene.selected_indices = []
	scene.call("_update_hand_buttons")
	if not scene.hand_buttons.is_empty():
		var sb2 = scene.hand_buttons[0].get_theme_stylebox("normal")
		if sb2 is StyleBoxFlat:
			_check(sb2.bg_color.is_equal_approx(Color(0.973, 0.976, 0.988, 1.0)),
				"取消选中后恢复白底 (%s)" % str(sb2.bg_color))


func _test_case(scene, hc: Control, n: int, expect_overlap: bool) -> void:
	for c in hc.get_children():
		hc.remove_child(c)
		c.queue_free()
	scene.selected_indices = []
	var arr: Array = []
	for i in range(n):
		var b := Button.new()
		b.size = Vector2(95, 118)
		for nm in ["CardSymbol", "CardName", "CardValence"]:
			var lbl := Label.new()
			lbl.name = nm
			b.add_child(lbl)
		hc.add_child(b)
		arr.append(b)
	scene.hand_buttons = arr
	scene.call("_layout_hand_cards")

	var first: Button = arr[0]
	var last: Button = arr[n - 1]
	var step: float = 0.0
	if n > 1:
		step = (last.position.x - first.position.x) / float(n - 1)

	_check(first.position.x >= -0.01, "n=%d 首牌 x>=0 (%.2f)" % [n, first.position.x])
	_check(last.position.x + 95.0 <= hc.size.x + 0.01,
		"n=%d 末牌右边界在容器内 (%.2f <= %.2f)" % [n, last.position.x + 95.0, hc.size.x])
	_check(abs(first.position.y - (hc.size.y - 118.0 - 20.0)) < 0.01,
		"n=%d 卡牌基准 y=高度-牌高-上浮量，上浮空间在容器内 (%.2f)" % [n, first.position.y])
	_check(abs(first.size.x - 95.0) < 0.01 and abs(first.size.y - 118.0) < 0.01,
		"n=%d 卡牌尺寸 95x118" % n)

	if n > 1 and expect_overlap:
		_check(step < 95.0, "n=%d 确实产生重叠 step=%.2f < 95" % [n, step])
		_check(95.0 - step >= 20.0, "n=%d 重叠量 %.2fpx >= 20px（叠卡效果明显）" % [n, 95.0 - step])
	if n > 1 and not expect_overlap:
		_check(step <= 103.01, "n=%d 间距不超过 卡宽+间隙 (%.2f)" % [n, step])
	if n == 8:
		_check(abs(step - 60.0) < 0.01, "n=8 步长命中叠卡上限 60（实际 %.2f）" % step)
	if n == 7:
		_check(abs(step - 103.0) < 0.01, "n=7 未达叠卡阈值，步长仍为 103（实际 %.2f）" % step)

	# 紧凑牌面：重叠时内容左对齐，否则居中
	var sym: Label = first.get_node("CardSymbol")
	var expect_compact: bool = step < 95.0 * 0.72
	if n > 1:
		var want = HORIZONTAL_ALIGNMENT_LEFT if expect_compact else HORIZONTAL_ALIGNMENT_CENTER
		_check(sym.horizontal_alignment == want,
			"n=%d 紧凑模式=%s（符号对齐正确）" % [n, str(expect_compact)])

	# 选中牌置顶（z_index=10，仅在手牌内部置顶；模态层 z=100 在其之上）
	scene.selected_indices = [1]
	scene.call("_layout_hand_cards")
	if n > 1:
		var b1: Button = arr[1]
		_check(b1.z_index == 10, "n=%d 被选中的牌 z_index=10（浮于未选中牌之上）" % n)
		_check(arr[0].z_index == 0, "n=%d 未选中的牌 z_index=0" % n)
	scene.selected_indices = []

	# 悬停上浮 / 复位（位置由 80ms 补间推进，z_index 立即切换）
	var b0: Button = arr[0]
	var base: Vector2 = b0.get_meta("base_pos", Vector2.ZERO)
	scene.call("_on_hand_card_hover", b0, true)
	_check(b0.z_index == 20, "n=%d 悬停：z_index=20 立即生效" % n)
	_check(abs(b0.position.y - base.y) < 0.01,
		"n=%d 悬停：位置由补间推进而非瞬移 (y=%.2f)" % [n, b0.position.y])
	await _wait_hover_anim(scene)
	_check(abs(b0.position.y - (base.y - 20.0)) < 0.01,
		"n=%d 悬停：补间结束上浮 20 (y=%.2f)" % [n, b0.position.y])
	_check(b0.position.y >= -0.01, "n=%d 悬停后未越出容器顶部 (y=%.2f)" % [n, b0.position.y])
	scene.call("_on_hand_card_hover", b0, false)
	_check(b0.z_index == 0, "n=%d 移出：z_index 立即归 0" % n)
	await _wait_hover_anim(scene)
	_check(abs(b0.position.y - base.y) < 0.01,
		"n=%d 移出：补间结束复位 (y=%.2f)" % [n, b0.position.y])

	# ---- 防抖：命中判定必须基于静止坐标，且覆盖上浮后的区域 ----
	# 若命中区随“抬起”变化，鼠标停在牌下沿时会出现 抬起→离开→落回→进入 的死循环
	var hr: Rect2 = scene.call("_card_hover_rect", b0)
	_check(hr.has_point(base + Vector2(47.0, -10.0)),
		"n=%d 命中区包含上浮后的 20px 区域（防抖动前提）" % n)
	_check(not hr.has_point(base + Vector2(47.0, 118.0 + 6.0)),
		"n=%d 命中区不含牌下沿之外" % n)
	if n > 1:
		var core0: Rect2 = scene.call("_card_core_rect", 0)
		var core1: Rect2 = scene.call("_card_core_rect", 1)
		_check(core0.end.x <= core1.position.x + 0.01,
			"n=%d 相邻牌核心区不重叠（滞回前提）" % n)
		if expect_overlap:
			var probe: Vector2 = base + Vector2(step + 1.0, 40.0)
			var hit: int = scene.call("_hover_hit_index", probe)
			_check(hit == 1, "n=%d 重叠区判定归属后一张牌 (hit=%d)" % [n, hit])
			_check(not core0.has_point(probe),
				"n=%d 重叠区不在前一张核心区（可自然切换，不会锁死）" % n)


# 让 pending 计时"瞬间到期"再判定：不依赖真实时间/定时器（headless 下 timer 按帧推进）
func _hover_settle(scene, mp: Vector2) -> void:
	scene.call("_update_hover_at", mp)   # 置 pending 目标
	scene.set("_hover_pending_at", int(scene.get("_hover_pending_at")) - 1000)
	scene.call("_update_hover_at", mp)   # 已稳定超过阈值 → 执行切换


# 防抖运行时验证
func _test_hover_debounce(scene, hc: Control) -> void:
	for c in hc.get_children():
		hc.remove_child(c)
		c.queue_free()
	scene.selected_indices = []
	var arr: Array = []
	for i in range(8):
		var b := Button.new()
		b.size = Vector2(95, 118)
		hc.add_child(b)
		arr.append(b)
	scene.hand_buttons = arr
	scene.call("_layout_hand_cards")

	var base: Vector2 = arr[0].get_meta("base_pos", Vector2.ZERO)
	var step: float = arr[1].position.x - arr[0].position.x
	var probe: Vector2 = base + Vector2(step + 1.0, 30.0)   # 两张牌的重叠窄条

	# 1) 鼠标停在重叠区：命中结果必须恒定，不得在两张牌之间来回翻转
	var stable := true
	var first_hit: int = int(scene.call("_hover_hit_index", probe))
	for _i in range(40):
		if int(scene.call("_hover_hit_index", probe)) != first_hit:
			stable = false
	_check(stable, "鼠标停在重叠区连续 40 次判定结果恒定 (hit=%d)" % first_hit)
	_check(first_hit == 1, "重叠区归属后一张牌 (hit=%d)" % first_hit)

	# 2) 目标首次命中不得立即抬起（这是"过于灵敏"的根因）
	scene.set("_hover_idx", -1)
	scene.set("_hover_pending_idx", -1)
	var core: Vector2 = base + Vector2(20.0, 40.0)
	scene.call("_update_hover_at", core)
	_check(int(scene.get("_hover_idx")) == -1 and abs(arr[0].position.y - base.y) < 0.01,
		"命中首帧不立即抬起（需稳定 %d ms）" % int(scene.HOVER_SWITCH_DELAY_MS))

	# 3) 目标稳定后抬起（位置由补间推进，等动画结束再断言）
	_hover_settle(scene, core)
	_check(int(scene.get("_hover_idx")) == 0, "目标稳定后抬起该牌 (idx=0)")
	await _wait_hover_anim(scene)
	_check(abs(arr[0].position.y - (base.y - 20.0)) < 0.01,
		"抬起补间结束到达上浮位 (y=%.1f)" % arr[0].position.y)

	# 4a) 指针仍在抬起牌画出来的矩形里（重叠窄条）→ 视觉与判定一致，保持不跳
	_hover_settle(scene, probe)
	_check(int(scene.get("_hover_idx")) == 0,
		"抬起牌覆盖的重叠区不再判给后一张（视觉一致，idx=%d）" % int(scene.get("_hover_idx")))

	# 4b) 越过抬起牌右边缘 → 才自然切到后一张
	var beyond: Vector2 = base + Vector2(95.0 + 4.0, 30.0)
	_hover_settle(scene, beyond)
	_check(int(scene.get("_hover_idx")) == 1,
		"越过抬起牌右边缘后切换到后一张 (idx=%d)" % int(scene.get("_hover_idx")))
	await _wait_hover_anim(scene)
	_check(abs(arr[0].position.y - base.y) < 0.01, "切换后前一张已落下（无残留抬起）")

	# 5) 回到牌0核心区：任意时刻不得"两牌同时抬起"
	_hover_settle(scene, core)
	var lifted := 0
	for b in arr:
		if b.z_index == 20: lifted += 1
	_check(lifted <= 1, "任意时刻最多一张牌处于抬起态 (lifted=%d)" % lifted)


# 等升降补间跑完。
# Tween 以帧步进（delta 累加），headless 下单帧可能极慢也可能极快，
# 固定 create_timer 会在"一帧就超过 140ms"时提前返回、补间却一步都没走。
# 这里直接轮询 hand_buttons 上的升降补间，直到都不再运行为止（带帧数兜底）。
func _wait_hover_anim(scene) -> void:
	for _i in range(300):
		var busy := false
		for b in scene.hand_buttons:
			if not is_instance_valid(b):
				continue
			var tw = b.get_meta("hover_tween", false)
			if tw is Tween and tw.is_valid() and tw.is_running():
				busy = true
				break
		if not busy:
			return
		await scene.get_tree().process_frame


# ---- 悬停流畅化：R1 视觉一致 / R2 分级延迟 / R3 补间 / R4 顶边容错 ----
# 复用 _test_hover_debounce 造出的 8 张合成牌（开赛后引用会失效）
func _test_hover_smoothness(scene) -> void:
	var arr: Array = scene.hand_buttons
	if arr.size() < 3:
		_check(false, "流畅化测试：手牌不足 3 张")
		return
	var b0: Button = arr[0]
	var base: Vector2 = b0.get_meta("base_pos", Vector2.ZERO)

	# 复位上个用例可能留下的抬起态
	scene.set("_hover_idx", -1)
	scene.set("_hover_pending_idx", -1)
	for i in range(arr.size()):
		var b: Button = arr[i]
		scene.call("_kill_hover_tween", b)
		b.position.y = b.get_meta("base_pos", b.position).y
		b.z_index = 0

	# R1：抬起牌"画出来的矩形"内必须归它自己（视觉与判定一致）
	scene.call("_on_hand_card_hover", b0, true)
	var raised_probe: Vector2 = base + Vector2(80.0, -8.0)   # 静止规则会判给后一张
	_check(int(scene.call("_hover_hit_index", raised_probe)) == 1,
		"R1 前提：静止命中规则在该点判给后一张")
	scene.call("_update_hover_at", raised_probe)
	_check(int(scene.get("_hover_idx")) == 0, "R1 抬起牌覆盖区域内保持自身（不跳到后一张）")
	var stable_r1 := true
	for _i in range(40):
		scene.call("_update_hover_at", raised_probe)
		if int(scene.get("_hover_idx")) != 0:
			stable_r1 = false
	_check(stable_r1, "R1 连续 40 次判定恒定（无自激抖动）")

	# R1b：越过抬起牌右边缘 → 才切到后一张，且前一张落回
	var leave_probe: Vector2 = base + Vector2(95.0 + 4.0, 30.0)
	_hover_settle(scene, leave_probe)
	_check(int(scene.get("_hover_idx")) == 1,
		"R1b 离开抬起牌绘制区后切换到后一张 (idx=%d)" % int(scene.get("_hover_idx")))
	await _wait_hover_anim(scene)
	_check(abs(b0.position.y - base.y) < 0.01, "R1b 切换后前一张已落回")

	# R2：命中某张牌 60ms 即切换（旧实现固定 110ms，跟手性差）
	scene.set("_hover_idx", -1)
	scene.set("_hover_pending_idx", -1)
	scene.call("_kill_hover_tween", b0)
	b0.position.y = base.y
	var core: Vector2 = base + Vector2(20.0, 40.0)
	scene.call("_update_hover_at", core)
	scene.set("_hover_pending_at",
		int(scene.get("_hover_pending_at")) - (int(scene.HOVER_SWITCH_DELAY_MS) + 1))
	scene.call("_update_hover_at", core)
	_check(int(scene.get("_hover_idx")) == 0,
		"R2 命中牌 %dms 即切换（跟手）" % int(scene.HOVER_SWITCH_DELAY_MS))
	_check(int(scene.HOVER_SWITCH_DELAY_MS) < 110, "R2 切换阈值已从 110ms 下调")

	# R2b：容器内但不在任何牌上（牌列下方）→ 用留出档延迟，底边抖动不落牌
	var below: Vector2 = base + Vector2(20.0, 140.0)
	scene.call("_update_hover_at", below)
	scene.set("_hover_pending_at",
		int(scene.get("_hover_pending_at")) - (int(scene.HOVER_SWITCH_DELAY_MS) + 1))
	scene.call("_update_hover_at", below)
	_check(int(scene.get("_hover_idx")) == 0, "R2b 牌列下方未达留出延迟，保持抬起")
	scene.set("_hover_pending_at",
		int(scene.get("_hover_pending_at")) - (int(scene.HOVER_LEAVE_DELAY_MS) + 1))
	scene.call("_update_hover_at", below)
	_check(int(scene.get("_hover_idx")) == -1, "R2b 超过留出延迟后落回")
	_check(int(scene.HOVER_LEAVE_DELAY_MS) > int(scene.HOVER_SWITCH_DELAY_MS),
		"R2b 留出档比切换档更保守")

	# R3：位置由补间推进，不再同帧瞬移
	scene.set("_hover_idx", -1)
	scene.call("_kill_hover_tween", b0)
	b0.position.y = base.y
	scene.call("_on_hand_card_hover", b0, true)
	_check(abs(b0.position.y - base.y) < 0.01, "R3 悬停当帧不瞬移（补间推进）")
	await _wait_hover_anim(scene)
	_check(abs(b0.position.y - (base.y - 20.0)) < 0.01,
		"R3 补间结束到达上浮位 (y=%.2f)" % b0.position.y)
	scene.call("_on_hand_card_hover", b0, false)
	await _wait_hover_anim(scene)
	_check(abs(b0.position.y - base.y) < 0.01, "R3 落下补间结束复位 (y=%.2f)" % b0.position.y)

	# R3b：重排必须先杀补间，否则牌会被动画拉回旧坐标
	scene.call("_on_hand_card_hover", b0, true)
	scene.call("_layout_hand_cards")
	_check(abs(b0.position.y - base.y) < 0.01, "R3b 重排立即覆盖补间位置（无回弹）")
	await _wait_hover_anim(scene)
	_check(abs(b0.position.y - base.y) < 0.01,
		"R3b 补间已终止，重排后位置稳定 (y=%.2f)" % b0.position.y)
	scene.set("_hover_idx", -1)

	# R4：手牌上沿 14px 容错带（贴边滑过不落牌，越界才复位）
	var gr: Rect2 = scene.hand_container.get_global_rect()
	_check(bool(scene.call("_hover_keep_above",
			Vector2(gr.position.x + 10.0, gr.position.y - 8.0), gr)),
		"R4 顶边 8px 内仍视为在牌上")
	_check(not bool(scene.call("_hover_keep_above",
			Vector2(gr.position.x + 10.0, gr.position.y - int(scene.HOVER_EXIT_GRACE) - 1.0), gr)),
		"R4 超出容错带即复位")
	_check(not bool(scene.call("_hover_keep_above",
			Vector2(gr.position.x - 2.0, gr.position.y - 8.0), gr)),
		"R4 横向移出牌列不复位判定（交回常规路径）")


# ---- 警告 toast：右栏空白格，不压手牌 / 操作区 / 日志 ----
func _test_warning_toast(scene) -> void:
	var gp = scene.get_node_or_null("GamePage")
	var toast = gp.get_node_or_null("ToastLayer") if gp else null
	_check(toast != null, "警告 toast：ToastLayer 存在")
	if toast == null:
		return

	scene.call("_show_center_warning", "第一行提示\n第二行提示")
	var box = scene.get("_warning_toast")
	_check(box != null and is_instance_valid(box), "警告 toast 已创建")
	if box == null or not is_instance_valid(box):
		return
	_check(box.get_parent() == toast, "警告 toast 挂在 ToastLayer")
	_check(box.visible, "警告 toast 显示")

	var want: Rect2 = scene.WARNING_TOAST_RECT
	var got := Rect2(box.position, box.size)
	_check(got.position.is_equal_approx(want.position) and got.size.is_equal_approx(want.size),
		"toast 位于右栏空白格 %s（实际 %s）" % [str(want), str(got)])
	_check(box.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"toast 不拦截鼠标（不挡手牌点击）")

	var sb = box.get_theme_stylebox("panel")
	_check(sb is StyleBoxFlat, "toast 使用 StyleBoxFlat")
	if sb is StyleBoxFlat:
		_check(sb.corner_radius_top_left == int(scene.PANEL_RADIUS)
			and sb.border_width_left == int(scene.BORDER_W_ACTIVE),
			"toast 走视觉规范（圆角 %d / 描边 %dpx）"
				% [int(scene.PANEL_RADIUS), int(scene.BORDER_W_ACTIVE)])
		_check(sb.border_color.is_equal_approx(Color(0.906, 0.298, 0.235, 1.0)),
			"toast 描边为警告红 (%s)" % str(sb.border_color))

	for n in ["HandContainer", "ActionPanel", "CardInfoLabel", "InfoLabel",
			"LogLabel", "TutorialLabel", "TableLabel", "DeckCountLabel"]:
		var c = gp.get_node_or_null(n)
		if c == null or not c.visible:
			continue
		var cr := Rect2(c.position, c.size)
		_check(not cr.intersects(got),
			"toast 不与 %s 重叠 (toast=%s node=%s)" % [n, str(got), str(cr)])

	var vp: Rect2 = scene.get_viewport_rect()
	_check(vp.encloses(got), "toast 完整落在窗口内")

	# 单例复用：连续报错只更新文本，不叠框
	var cnt: int = toast.get_child_count()
	scene.call("_show_center_warning", "第二条（覆盖前一条）")
	_check(toast.get_child_count() == cnt,
		"连续报错不叠框（子节点数 %d）" % toast.get_child_count())
	var lbl = scene.get("_warning_label")
	_check(lbl != null and lbl.text == "第二条（覆盖前一条）", "toast 文本更新为最新一条")

	scene.call("_hide_warning_toast")
	_check(not box.visible, "开局/收尾时警告 toast 可隐藏")


# ---- 视觉规范工厂：卡牌 / 按钮 / 提示框共用同一套圆角 · 描边 · 阴影 ----
func _test_style_factory(scene) -> void:
	var card = scene.call("_make_panel_style", "card")
	_check(card is StyleBoxFlat, "工厂返回 StyleBoxFlat")
	if not (card is StyleBoxFlat):
		return
	_check(card.corner_radius_top_left == int(scene.CARD_RADIUS)
		and card.corner_radius_bottom_right == int(scene.CARD_RADIUS),
		"卡牌圆角统一为 %d" % int(scene.CARD_RADIUS))
	_check(card.border_width_left == int(scene.BORDER_W), "卡牌描边 1px")
	_check(card.shadow_size == int(scene.SHADOW_SIZE), "卡牌带轻投影")
	_check(card.bg_color.is_equal_approx(Color(0.973, 0.976, 0.988, 1.0)),
		"卡牌底色 #F8F9FC 未变")
	_check(card.border_color.is_equal_approx(Color(0.63, 0.66, 0.71, 1.0)),
		"卡牌描边 #A1A8B5 未变")

	var sel = scene.call("_make_panel_style", "card_selected")
	_check(sel.bg_color.is_equal_approx(Color(1.0, 1.0, 0.82, 1.0))
		and sel.border_color.is_equal_approx(Color(0.9, 0.65, 0.1, 1.0)),
		"选中态颜色不变（浅黄 / 橙金）")
	_check(sel.border_width_left == int(scene.BORDER_W_ACTIVE), "选中态描边 2px")

	var hov = scene.call("_make_panel_style", "card_hover")
	_check(hov.bg_color.is_equal_approx(Color(0.9, 0.93, 0.98, 1.0))
		and hov.border_color.is_equal_approx(Color(0.35, 0.55, 0.85, 1.0)),
		"悬停态颜色不变（浅蓝 / 主题蓝）")
	var hsel = scene.call("_make_panel_style", "card_hover_selected")
	_check(hsel.bg_color.is_equal_approx(Color(1.0, 0.98, 0.72, 1.0))
		and hsel.border_color.is_equal_approx(Color(0.85, 0.55, 0.0, 1.0)),
		"选中悬停仍是黄色系（不盖掉选中态）")

	var mini = scene.call("_make_panel_style", "mini_card")
	_check(mini.corner_radius_top_left == int(scene.CARD_RADIUS) and mini.shadow_size == 0,
		"桌面小卡同圆角、无投影（密度高）")
	var mini_h = scene.call("_make_panel_style", "mini_card_hover")
	_check(mini_h.bg_color.is_equal_approx(Color(0.9, 0.93, 0.98, 0.95)),
		"小卡悬停底色不变")

	var btn = scene.call("_make_panel_style", "button")
	_check(btn.corner_radius_top_left == int(scene.CARD_RADIUS)
		and btn.shadow_size == int(scene.SHADOW_SIZE),
		"按钮与卡牌同一圆角 / 投影规范")
	_check(btn.content_margin_left == 10 and btn.content_margin_top == 6, "按钮内边距 10/6")

	var warn = scene.call("_make_panel_style", "toast_warning")
	var info = scene.call("_make_panel_style", "toast_info")
	_check(warn.corner_radius_top_left == int(scene.PANEL_RADIUS)
		and info.corner_radius_top_left == int(scene.PANEL_RADIUS),
		"提示框圆角走面板规范 %d" % int(scene.PANEL_RADIUS))
	_check(warn.border_width_left == int(scene.BORDER_W_ACTIVE)
		and info.border_width_left == int(scene.BORDER_W_ACTIVE),
		"提示框描边 2px")

	# 真实控件必须来自工厂
	if not scene.hand_buttons.is_empty():
		var sb = scene.hand_buttons[0].get_theme_stylebox("normal")
		_check(sb is StyleBoxFlat and sb.corner_radius_top_left == int(scene.CARD_RADIUS),
			"手牌实际样式来自工厂（圆角 %d）" % int(scene.CARD_RADIUS))



