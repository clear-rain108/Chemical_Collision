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
	_test_hover_debounce(scene, hc)

	# 开始对局，生成真实手牌后再检查信息栏 / tooltip 行为
	scene.call("_on_start_game")
	for _w in range(5):
		await process_frame
	_test_info_and_tooltip(scene)
	_test_selected_style(scene)
	_test_layers(scene)
	_test_tutorial_layout(scene)

	_test_case(scene, hc, 16, true)
	_test_case(scene, hc, 8, true)
	_test_case(scene, hc, 7, false)
	_test_case(scene, hc, 3, false)

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

	# 悬停上浮 / 复位
	var b0: Button = arr[0]
	var base: Vector2 = b0.get_meta("base_pos", Vector2.ZERO)
	scene.call("_on_hand_card_hover", b0, true)
	_check(abs(b0.position.y - (base.y - 20.0)) < 0.01 and b0.z_index == 20,
		"n=%d 悬停：上浮 20 且 z_index=20" % n)
	_check(b0.position.y >= -0.01, "n=%d 悬停后未越出容器顶部 (y=%.2f)" % [n, b0.position.y])
	scene.call("_on_hand_card_hover", b0, false)
	_check(abs(b0.position.y - base.y) < 0.01 and b0.z_index == 0,
		"n=%d 移出：位置复位且 z_index=0" % n)

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

	# 3) 目标稳定后抬起（用确定性时间推进，不依赖真实等待）
	_hover_settle(scene, core)
	_check(int(scene.get("_hover_idx")) == 0 and abs(arr[0].position.y - (base.y - 20.0)) < 0.01,
		"目标稳定后抬起该牌 (idx=%d y=%.1f)" % [int(scene.get("_hover_idx")), arr[0].position.y])

	# 4) 移进重叠区（仍在牌0命中矩形内、但已不在其核心区）→ 可自然切到后一张
	_hover_settle(scene, probe)
	_check(int(scene.get("_hover_idx")) == 1, "重叠区可切换到后一张 (idx=%d)" % int(scene.get("_hover_idx")))
	_check(abs(arr[0].position.y - base.y) < 0.01, "切换后前一张已落下（无残留抬起）")

	# 5) 回到牌0核心区：任意时刻不得"两牌同时抬起"
	_hover_settle(scene, core)
	var lifted := 0
	for b in arr:
		if b.z_index == 20: lifted += 1
	_check(lifted <= 1, "任意时刻最多一张牌处于抬起态 (lifted=%d)" % lifted)
