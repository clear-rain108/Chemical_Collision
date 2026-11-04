# 验证触屏档案（A1 + B + C）：桌面 23 套测试依赖 const 基准值，真机依赖 *_touch() 放大值，
# 本套把两边一起钉住 —— 只要有人把「放大」写回 const，这里立刻红。
#   A1 屏幕适配：project.godot 的 aspect=keep + default_clear_color（无代码可测，见文档）
#   B  触控尺寸：工具行 48 / 间距 20 / 顶 542、出牌按钮 58、卡牌字号、页面按钮 ≥48
#   C  触控交互：命中 8px 缓冲、选中上浮、拖拽 10px 跟手 / 24px 确认（F2）、退出二次确认
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


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


# _mkb 需要一个非空 Callable（空 Callable 连接会报错），测试里用空实现占位
func _noop() -> void:
	pass


func _run():
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 1) 没开赛之前先验证「桌面基准」：这一层是 23 套老测试的契约
	_test_desktop_baseline(scene)

	# 2) 开赛拿真实手牌：卡牌字号 / 命中缓冲 / 选中上浮都要真实按钮才有意义
	scene.call("_on_start_game")
	for _w in range(5):
		await process_frame

	_test_touch_geometry(scene)
	_test_touch_typography(scene)
	_test_touch_hit_pad(scene)
	await _test_touch_select_lift(scene)
	_test_touch_drag_arm(scene)
	_test_touch_page_sizing(scene)
	_test_touch_quit_confirm(scene)
	_test_back_to_desktop(scene)

	if fails == 0:
		print("ALL TOUCH UI TESTS PASSED")
	else:
		print("%d TOUCH UI TEST(S) FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---------------- 1. 桌面基准（const 契约） ----------------
func _test_desktop_baseline(scene) -> void:
	_check(scene._touch_ui == false, "headless / 桌面默认不开触屏档（_touch_ui=false）")
	_check(_approx(scene._tool_btn_h(), scene.TOOL_BTN_H), "桌面：工具行高 = TOOL_BTN_H(32)")
	_check(_approx(scene._tool_btn_top(), scene.TOOL_BTN_TOP), "桌面：工具行顶 = TOOL_BTN_TOP(558)")
	_check(_approx(scene._tool_btn_gap(), scene.TOOL_BTN_GAP), "桌面：工具行间距 = TOOL_BTN_GAP(10)")
	_check(_approx(scene._tool_row_left(), scene.TOOL_ROW_LEFT), "桌面：工具行左界 = TOOL_ROW_LEFT(460)")
	_check(_approx(scene._reorder_btn_left(), scene.REORDER_BTN_LEFT), "桌面：按序按钮左界 = REORDER_BTN_LEFT(338)")
	var hl: Rect2 = scene._tool_row_hl_rect()
	_check(hl.position.is_equal_approx(scene.TOOL_ROW_HL_POS) and hl.size.is_equal_approx(scene.TOOL_ROW_HL_SIZE),
		"桌面：教程高亮框与 TOOL_ROW_HL_POS / SIZE 逐值相等（函数与常量同源）")
	_check(_approx(scene._drag_threshold(), scene.DRAG_THRESHOLD), "桌面：拖动阈值 = DRAG_THRESHOLD(6)")
	_check(_approx(scene._selected_lift(), 0.0), "桌面：选中牌不额外上浮（悬停 20 已足够）")
	_check(scene._touch_fs(14, 4) == 14 and scene._touch_btn_h(32) == 32,
		"桌面：字号 / 高度换算函数原样返回")

# ---------------- 2. 触控尺寸：工具行 ----------------
# 右界固定 820（与手牌列 / 信息栏同一条竖线），左界由宽度反推 → 132+96+112 + 20*2 = 380
func _test_touch_geometry(scene) -> void:
	scene._touch_ui = true
	_check(_approx(scene._tool_btn_h(), 48.0), "触屏：工具行高 32 → 48（≈32dp）")
	_check(_approx(scene._tool_btn_top(), 542.0), "触屏：工具行顶 558 → 542（48 高仍能塞进信息栏与出牌区之间）")
	_check(_approx(scene._tool_btn_gap(), 20.0), "触屏：工具行间距 10 → 20（帮助 / 退出不再贴脸）")
	_check(_approx(scene._tool_row_left(), 440.0), "触屏：右界固定 820 → 左界 440")
	_check(_approx(scene._reorder_btn_left(), 308.0), "触屏：「按序 ⇅」跟着左移，左界 308")

	scene._style_game_tool_buttons()
	var hint: Button = scene.hint_button
	var help_b: Button = scene.help_btn
	var quit_b: Button = scene.quit_button
	_check(_approx(hint.size.y, 48.0) and _approx(help_b.size.y, 48.0) and _approx(quit_b.size.y, 48.0),
		"触屏：三颗工具按钮实际高度都变成 48")
	_check(_approx(hint.position.y, 542.0) and _approx(help_b.position.y, 542.0) and _approx(quit_b.position.y, 542.0),
		"触屏：三颗工具按钮同一基线 y=542")
	_check(_approx(hint.position.x, 440.0) and _approx(help_b.position.x, 592.0) and _approx(quit_b.position.x, 708.0),
		"触屏：x 依次 440 / 592 / 708（间距 20）")
	_check(_approx(quit_b.position.x + quit_b.size.x, 820.0), "触屏：整行右边界仍对齐 x=820")
	_check(hint.get_theme_font_size("font_size") == 18, "触屏：工具按钮字号 14 → 18")

	# 上下让位：上不能压 CardInfoLabel（底 526），下不能压 ActionPanel（顶 599）
	var info_bottom: float = scene.card_info_label.position.y + scene.card_info_label.size.y
	var action_top: float = scene.action_panel.position.y
	_check(hint.position.y >= info_bottom,
		"触屏：工具行不压 CardInfoLabel（%s ≥ %s）" % [str(hint.position.y), str(info_bottom)])
	_check(hint.position.y + hint.size.y <= action_top,
		"触屏：工具行不压 ActionPanel（%s ≤ %s）" % [str(hint.position.y + hint.size.y), str(action_top)])

	# 教程高亮框必须跟着放大，否则教程第零关的框只圈住半行
	var hl: Rect2 = scene._tool_row_hl_rect()
	_check(hl.encloses(Rect2(hint.position, hint.size)), "触屏：教程高亮框完整包住「显示提示」")
	_check(hl.encloses(Rect2(help_b.position, help_b.size)), "触屏：教程高亮框完整包住「帮助」")
	_check(hl.encloses(Rect2(quit_b.position, quit_b.size)), "触屏：教程高亮框完整包住「退出游戏」")


# ---------------- 3. 触控尺寸：字号 ----------------
func _test_touch_typography(scene) -> void:
	var b: Button = scene._mkb("测试", Callable(self, "_noop"), false)
	_check(_approx(b.custom_minimum_size.y, 58.0), "触屏：出牌区按钮 45 → 58 高（≈39dp）")
	_check(b.get_theme_font_size("font_size") == 18, "触屏：出牌区按钮字号 16 → 18")

	# 重建手牌后看真实牌面字号（桌面基准：符号 21/28、中文名 12/14、原子序 12、价态 13、质量 9）
	scene._update_hand_buttons()
	_check(scene.hand_buttons.size() > 0, "触屏：手牌已重建（%d 张）" % scene.hand_buttons.size())
	if scene.hand_buttons.is_empty():
		return
	var hb: Button = scene.hand_buttons[0]
	var sym = hb.get_node_or_null("CardSymbol")
	var nm = hb.get_node_or_null("CardName")
	var num = hb.get_node_or_null("CardNumber")
	var val = hb.get_node_or_null("CardValence")
	var mass = hb.get_node_or_null("CardMass")
	_check(sym != null and sym.get_theme_font_size("font_size") >= 25,
		"触屏：符号字号放大（%d ≥ 25，桌面为 21 / 28）" % (sym.get_theme_font_size("font_size") if sym else -1))
	_check(nm != null and nm.get_theme_font_size("font_size") >= 14,
		"触屏：中文名字号放大（%d ≥ 14，桌面为 12 / 14）" % (nm.get_theme_font_size("font_size") if nm else -1))
	_check(num != null and num.get_theme_font_size("font_size") == 14,
		"触屏：原子序字号 12 → 14（左上角号码不再糊成一团）")
	# 价态字号会按卡宽自适应（Cl 的 5 个价在紧凑档放不下 → 降字号 / 只留两端价），
	# 因此只校验「落在 11~15 的放大区间内」，不再要求恒定 15（否则首张恰好是 Cl 时会误报）。
	var vfs: int = val.get_theme_font_size("font_size") if val else 0
	_check(vfs >= 11 and vfs <= 15,
		"触屏：价态字号落在 11~15 自适应区间（实际 %d，桌面基准 13）" % vfs)
	_check(mass != null and mass.get_theme_font_size("font_size") == 12,
		"触屏：原子量字号 9 → 12（桌面 9 在手机上看不清）")
	b.queue_free()


# ---------------- 4. 触控交互：命中 8px 缓冲 ----------------
# 手指比鼠标粗，落点常压在牌边缘外 3~6px；缓冲只在「严格几何谁都点不中」时兜底，
# 不能改变正常点选的判定（否则会选到旁边那张）。
func _test_touch_hit_pad(scene) -> void:
	if scene.hand_buttons.size() < 2:
		_check(false, "触屏命中：手牌不足 2 张，无法验证缓冲")
		return
	var r: Rect2 = scene._card_hover_rect(scene.hand_buttons[0])
	var outside: Vector2 = Vector2(r.position.x - 5.0, r.position.y + 40.0)
	scene._touch_ui = false
	_check(scene._hit_card_at(outside) == -1, "桌面：牌外 5px 不算命中（严格几何）")
	scene._touch_ui = true
	_check(scene._hit_card_at(outside) == 0, "触屏：牌外 5px 兜底判给第 1 张（TOUCH_HIT_PAD=8）")

	var inside: Vector2 = Vector2(r.position.x + 30.0, r.position.y + 60.0)
	scene._touch_ui = false
	var desktop_hit: int = scene._hit_card_at(inside)
	scene._touch_ui = true
	_check(desktop_hit >= 0, "牌内点击确实命中了一张牌（idx=%d）" % desktop_hit)
	_check(scene._hit_card_at(inside) == desktop_hit,
		"触屏：牌内点击与桌面判定一致（缓冲只兜底，不抢正常命中）")


# ---------------- 5. 触控交互：选中常驻上浮 ----------------
func _test_touch_select_lift(scene) -> void:
	scene._touch_ui = true
	scene.selected_indices.clear()
	scene.selected_indices.append(0)
	scene._layout_hand_cards()
	var hb: Button = scene.hand_buttons[0]
	var base: Vector2 = hb.get_meta("base_pos", hb.position)
	_check(_approx(base.y - hb.position.y, 10.0),
		"触屏：选中的牌常驻上浮 10px（触屏没有悬停，这是唯一的选中提示）")
	_check(hb.z_index == scene.Z_HAND_SELECTED, "触屏：选中牌同时在最上层（压住相邻牌）")
	_check(_approx(base.y, hb.get_meta("base_pos", Vector2.ZERO).y),
		"触屏：base_pos 仍存不上浮的静止位（命中 / 拖拽都基于它）")

	# 按住 → 抬到 20；松手 → 落回「选中上浮位」，而不是原静止位
	scene._set_hover_index(0)
	await create_timer(0.2).timeout
	_check(_approx(base.y - hb.position.y, 20.0), "触屏：按住时抬到 HOVER_LIFT(20)")
	scene._set_hover_index(-1)
	await create_timer(0.2).timeout
	_check(_approx(base.y - hb.position.y, 10.0), "触屏：松手落下仍停在选中位（提示不会消失）")

	scene.selected_indices.clear()
	scene._layout_hand_cards()
	_check(_approx(hb.position.y, base.y), "触屏：取消选中后落回原位（无残留偏移）")


# ---------------- 5b. 触控交互：拖拽跟手 + 点选回退（F2） ----------------
# 旧实现：按住 300ms 且移动 24px 才起拖 —— 按住后牌一直不动（最多 300ms 无反馈），
# 松手若未达门槛那次 pressed 又被 _drag_suppress_click 吞掉，表现为「点了没反应」。
# 新实现：10px 立即起拖（跟手），松手总位移 <24px 判为点选。
func _test_touch_drag_arm(scene) -> void:
	scene._touch_ui = true
	_check(_approx(scene._drag_arm_threshold(), 10.0) and _approx(scene._drag_threshold(), 24.0),
		"触屏：起拖 10px（跟手）/ 确认 24px（重排）两档分离")
	_check(scene._drag_arm_threshold() < scene._drag_threshold(),
		"触屏：起拖门槛低于确认门槛（留出「跟手了但松手仍算点选」的区间）")
	if scene.hand_buttons.size() < 2:
		_check(false, "触屏拖拽：手牌不足 2 张，无法验证回退")
		scene._touch_ui = false
		return
	var cp = scene.game_manager.get_current_player()
	var before: Array = cp.hand.duplicate()

	# 1) 只走 12px 就松手 → 回退成点选：牌被选中，手牌顺序不变
	scene.selected_indices.clear()
	scene._update_hand_buttons()
	scene._drag_press_idx = 0
	scene._drag_press_pos = scene.hand_container.get_global_mouse_position()
	scene._begin_drag(0)
	_check(scene._drag_active, "触屏：10px 起拖后立刻进入拖拽态（无长按等待）")
	_check(scene._drag_ghost != null and scene._drag_ghost.modulate.a > 0.85,
		"触屏：软启动幽灵牌接近实色（回退成点选时不会闪一下深灰）")
	scene._drag_max_move = 12.0
	scene._drag_slot = 1
	scene._finish_drag(scene.hand_container.get_global_rect().get_center())
	_check(0 in scene.selected_indices,
		"触屏：位移 <24px 松手回退成点选（牌被选中，不是「点了没反应」）")
	_check(cp.hand == before, "触屏：回退成点选时手牌顺序不动（不会误重排）")
	_check(not scene._drag_active and scene._drag_ghost == null and scene._drag_line == null,
		"触屏：回退后拖拽视觉已清理（无残留幽灵牌 / 指示线）")

	# 2) 走满 40px → 真正重排（仍不额外选中）
	scene.selected_indices.clear()
	scene._update_hand_buttons()
	scene._drag_press_idx = 0
	scene._drag_press_pos = scene.hand_container.get_global_mouse_position()
	scene._begin_drag(0)
	scene._drag_max_move = 40.0
	scene._drag_slot = 2
	scene._finish_drag(scene.hand_container.get_global_rect().get_center())
	_check(cp.hand != before, "触屏：位移 ≥24px 松手真的重排（数据层顺序已变）")
	_check(not (0 in scene.selected_indices), "触屏：重排后不会顺带选中（补发的 pressed 被吞）")
	scene.selected_indices.clear()
	scene._update_hand_buttons()
	scene._touch_ui = false


# ---------------- 6. 触控尺寸：开始页等页面按钮 ----------------
func _test_touch_page_sizing(scene) -> void:
	scene._touch_ui = true
	var sb: Button = scene._start_child("StartButton")
	if sb == null:
		_check(false, "开始页 StartButton 存在")
		return
	var fs0: int = sb.get_theme_font_size("font_size")
	scene._apply_touch_sizing(scene.start_page)
	var h1: float = sb.size.y
	var fs1: int = sb.get_theme_font_size("font_size")
	_check(h1 >= 48.0, "触屏：开始页按钮高度补到 ≥48（实际 %s）" % str(h1))
	_check(fs1 == fs0 + 2, "触屏：开始页按钮字号 +2（%d → %d）" % [fs0, fs1])
	scene._apply_touch_sizing(scene.start_page)
	_check(_approx(sb.size.y, h1) and sb.get_theme_font_size("font_size") == fs1,
		"触屏：重复调用幂等（不会 +2 +2 叠成 +4）")


# ---------------- 7. 触控交互：退出二次确认 ----------------
func _test_touch_quit_confirm(scene) -> void:
	scene._touch_ui = true
	scene._quit_confirm_pending = false
	scene.quit_button.text = "退出游戏"
	scene._on_quit_game()
	_check(scene._quit_confirm_pending == true, "触屏：第一次点「退出游戏」进入二次确认")
	_check(scene.quit_button.text == "确认退出?", "触屏：按钮文字变成「确认退出?」")
	_check(scene.game_page.visible, "触屏：此时还没离开游戏页（误触不会直接结束本局）")
	scene._reset_quit_confirm()
	_check(scene._quit_confirm_pending == false and scene.quit_button.text == "退出游戏",
		"触屏：确认超时后按钮文字自动回滚")

	# 桌面档保持原行为：点一次就进结算页
	scene._touch_ui = false
	scene._on_quit_game()
	_check(not scene.game_page.visible, "桌面：点「退出游戏」直接进结算页（行为不变）")
	scene._touch_ui = true


# ---------------- 8. 关档后必须完全回到桌面基准 ----------------
func _test_back_to_desktop(scene) -> void:
	scene._touch_ui = false
	_check(_approx(scene._tool_btn_h(), 32.0) and _approx(scene._tool_btn_gap(), 10.0)
			and _approx(scene._selected_lift(), 0.0) and _approx(scene._drag_threshold(), 6.0)
			and _approx(scene._drag_arm_threshold(), 6.0),
		"关掉触屏档后所有取值回到桌面基准（拖拽只剩 6px 一档）")
	scene._style_game_tool_buttons()
	_check(_approx(scene.quit_button.size.y, 32.0) and _approx(scene.quit_button.position.x, 708.0),
		"桌面：重新归一后工具行回到 32 高 / x=708")
