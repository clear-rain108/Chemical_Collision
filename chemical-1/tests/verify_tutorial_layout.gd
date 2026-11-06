# 验证第零关的 UI 布局与「规则提醒」生命周期（触屏实机 4 个 bug 的回归锁）
#   1) 引导提示框 / 流程介绍框 / 文字全都在 1152×648 画布内（实机曾把字画到框外、把框推出屏幕）
#   2) 文字 Label 的 size 不被「autowrap 晚于 size」这个顺序问题撑大
#   3) 牌局练习阶段：规则提醒可见、日志让位（两者互斥可见 ⇒ 结构上不可能重叠）
#   4) 离开练习阶段 / 退出教学 / 开始正常对局后：规则提醒消失、日志复位、日志缓存清空
extends SceneTree

var fails: int = 0
var scene = null

const CANVAS := Vector2(1152, 648)
const TOL := 1.0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _finish() -> void:
	print("")
	if fails == 0:
		print("ALL TUTORIAL LAYOUT TESTS PASSED")
		quit(0)
	else:
		print("%d TUTORIAL LAYOUT TEST(S) FAILED" % fails)
		quit(1)


# overlay 里所有「绝对定位」的可见控件都必须落在画布内
# （全屏遮罩按锚点铺满，position 恒为 (0,0)，跳过）
func _check_overlay_inside(ov: Control, tag: String) -> void:
	if ov == null or not is_instance_valid(ov):
		_check(false, "%s：overlay 存在" % tag)
		return
	var bad: Array = []
	for c in ov.get_children():
		if not (c is Control) or not c.visible:
			continue
		if c.anchor_right != 0.0 or c.anchor_bottom != 0.0:
			continue
		var r := Rect2(c.position, c.size)
		if r.position.x < -TOL or r.position.y < -TOL \
				or r.end.x > CANVAS.x + TOL or r.end.y > CANVAS.y + TOL:
			bad.append("%s@%s" % [c.get_class(), str(r)])
	_check(bad.is_empty(), "%s：所有控件都在 %s 画布内%s"
		% [tag, str(CANVAS), ("" if bad.is_empty() else " ← " + str(bad))])


func _find_label(parent: Node, text: String) -> Label:
	if parent == null or not is_instance_valid(parent):
		return null
	for c in parent.get_children():
		if c is Label and c.text == text:
			return c
	return null


func _find_button(parent: Node, text: String) -> Button:
	if parent == null or not is_instance_valid(parent):
		return null
	for c in parent.get_children():
		if c is Button and c.text == text:
			return c
	return null


func _run() -> void:
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# ============================================================
	# 一、Phase 1：UI 标注（6 步提示框）
	# ============================================================
	scene.call("_on_start_tutorial", 0)
	await process_frame
	await process_frame
	_check(scene.game_manager != null and scene.game_manager.tutorial_level0_phase == 1,
		"进入第零关 Phase 1（UI 标注）")

	var steps: int = scene.level0_ui_highlight_steps.size()
	_check(steps == 6, "Phase 1 共 6 步标注（实际 %d）" % steps)
	for i in range(steps):
		scene.call("_level0_show_ui_step", i)
		await process_frame
		await process_frame
		var tag := "UI 标注第 %d 步" % (i + 1)
		_check_overlay_inside(scene.level0_overlay, tag)
		var step_data: Dictionary = scene.level0_ui_highlight_steps[i]
		var desc_lbl := _find_label(scene.level0_overlay, step_data["desc"])
		_check(desc_lbl != null, "%s：提示正文 Label 已创建" % tag)
		if desc_lbl != null:
			# tbw(520) - 左右各 24 内边距 = 472：不能被最小尺寸撑大
			_check(absf(desc_lbl.size.x - 472.0) < 0.5,
				"%s：提示正文宽度=472 未被撑大（实际 %.1f）" % [tag, desc_lbl.size.x])
			_check(desc_lbl.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
				"%s：提示正文开启自动换行" % tag)
			_check(desc_lbl.position.x + desc_lbl.size.x <= CANVAS.x + TOL,
				"%s：提示正文右边界不出画布（%.1f）" % [tag, desc_lbl.position.x + desc_lbl.size.x])

	# ============================================================
	# 二、Phase 2：流程介绍（3 步对话框）
	# ============================================================
	scene.call("_level0_start_phase2")
	await process_frame
	await process_frame
	_check(scene.game_manager.tutorial_level0_phase == 2, "进入第零关 Phase 2（流程介绍）")
	var flow: int = scene.level0_flow_steps.size()
	_check(flow == 3, "Phase 2 共 3 步（实际 %d）" % flow)
	for i in range(flow):
		scene.call("_level0_show_flow_step", i)
		await process_frame
		await process_frame
		var tag := "流程介绍第 %d 步" % (i + 1)
		_check_overlay_inside(scene.level0_overlay, tag)
		var content_lbl := _find_label(scene.level0_overlay, scene.level0_flow_steps[i])
		_check(content_lbl != null, "%s：正文 Label 已创建" % tag)
		if content_lbl != null:
			_check(absf(content_lbl.size.x - 840.0) < 0.5,
				"%s：正文宽度=840 未被撑大（实际 %.1f）" % [tag, content_lbl.size.x])

	# ============================================================
	# 三、Phase 3：牌局练习 — 规则提醒独占右栏
	# ============================================================
	scene.call("_level0_show_flow_step", flow)   # idx 越界 → 自动进 Phase 3
	await process_frame
	await process_frame
	_check(scene.game_manager.tutorial_level0_phase == 3, "进入第零关 Phase 3（牌局练习）")
	_check(scene.game_manager.clan_bomb_disabled == false,
		"Phase 3 族炸仍可打出（保留玩家的选择自由）")

	var rule = scene.level0_rule_tip_label
	_check(rule != null and is_instance_valid(rule), "练习阶段创建了规则提醒 Level0RuleTips")
	if rule == null or not is_instance_valid(rule):
		_finish()
		return
	var rr := Rect2(rule.position, rule.size)
	_check(rr.end.x <= CANVAS.x + TOL and rr.end.y <= CANVAS.y + TOL,
		"规则提醒不出画布：%s" % str(rr))
	_check(rule.visible, "练习阶段规则提醒可见")
	_check(not scene.log_label.visible, "练习阶段日志让位（LogLabel 隐藏）")
	_check(not (rule.visible and scene.log_label.visible),
		"规则提醒与日志不会同时可见（不可能再出现文字重叠）")
	_check(rule.text.find("越大越小") >= 0 and rule.text.find("同类同出") >= 0,
		"规则提醒给出「越大越小 / 同类同出」两条主规则")
	_check(rule.text.find("族炸") < 0, "未打族炸时规则提醒不提族炸（新手引导聚焦）")

	# 只有玩家真的打出族炸，才补一条「牌权争夺」
	scene.game_manager.level0_rule_tip = "牌权争夺"
	_check(str(scene.call("_level0_rule_tips_text")).find("族炸") >= 0,
		"打出族炸后规则提醒才补「牌权争夺」说明")
	scene.game_manager.level0_rule_tip = ""
	scene.call("_level0_update_rule_tips")
	await process_frame
	_check(rule.text.find("族炸") < 0, "规则提醒回到「只教两条主规则」")

	# 练习阶段的引导文案先教单质 / 化合物（不再一上来就推荐族炸）
	var ctrl = scene.game_manager.tutorial_controller
	_check(ctrl != null and ctrl.tutorial_guidance.find("先练单质和化合物") >= 0,
		"第零关练习引导先教单质 / 化合物：%s" % ("" if ctrl == null else ctrl.tutorial_guidance))

	# ============================================================
	# 四、离开练习阶段 → 提醒隐藏、日志复位
	# ============================================================
	scene.game_manager.tutorial_level0_phase = 0
	scene.call("_level0_update_rule_tips")
	await process_frame
	_check(not rule.visible, "离开练习阶段后规则提醒隐藏")
	_check(rule.text == "", "离开练习阶段后规则提醒文本清空")
	_check(scene.log_label.visible, "离开练习阶段后日志复位")


	# ============================================================
	# 五、退出教学 → 第一关：提醒必须被彻底释放
	# ============================================================
	scene.call("_on_start_tutorial", 1)
	await process_frame
	await process_frame
	_check(scene.find_child("Level0RuleTips", true, false) == null,
		"切到第一关后规则提醒节点已移除（不再盖在日志上）")
	_check(scene.level0_rule_tip_label == null, "切到第一关后规则提醒引用已清空")
	_check(scene.log_label.visible, "切到第一关后日志恢复显示")

	# ============================================================
	# 六、退出教学 → 正常对局：提醒不再出现，日志缓存也清空
	# ============================================================
	scene.call("_init_game", 4, 3)
	await process_frame
	await process_frame
	_check(scene.find_child("Level0RuleTips", true, false) == null,
		"正常对局不显示第零关规则提醒")
	_check(scene.find_child("Level0RuleTipsBg", true, false) == null,
		"正常对局不显示规则提醒背景板")
	_check(scene.level0_rule_tip_label == null, "正常对局里规则提醒引用为空")
	_check(scene.log_label.visible, "正常对局日志可见")
	var logtxt: String = "\n".join(scene.log_lines)
	_check(logtxt.find("教程") < 0, "正常对局日志没有教学局残留：%s" % logtxt)
	_check(scene.game_manager.tutorial_level0_phase == 0, "正常对局 tutorial_level0_phase 归零")

	# 自由模式（tutorial_level==0 且 phase==0）刷新 UI 也不能冒出规则提醒
	scene.call("_refresh_ui")
	await process_frame
	_check(scene.find_child("Level0RuleTips", true, false) == null,
		"自由模式刷新 UI 后仍无规则提醒")
	_check(scene.log_label.visible, "自由模式刷新 UI 后日志保持可见")

	# ============================================================
	# 七、开场提示框（_level0_make_tip_box）几何 + Label 不被撑大
	# ============================================================
	var long_text := "【越大越小】同牌型比较时，原子序数和越小的牌越大。桌面牌必须被你出的牌压过（你的牌要更大）！"
	var box = scene.call("_level0_make_tip_box", long_text, 0.2)
	root.add_child(box)
	await process_frame
	var box_bg = null
	var box_lbl: Label = null
	for c in box.get_children():
		if c is Panel:
			box_bg = c
		elif c is Label:
			box_lbl = c
	_check(box_bg != null and box_bg.position.x + box_bg.size.x <= CANVAS.x + TOL,
		"开场提示背景板右边界在画布内（%.1f）"
		% (0.0 if box_bg == null else box_bg.position.x + box_bg.size.x))
	_check(box_lbl != null, "开场提示文字 Label 已创建")
	if box_lbl != null:
		_check(absf(box_lbl.size.x - 660.0) < 0.5,
			"开场提示文字宽度=660 未被撑大（实际 %.1f）" % box_lbl.size.x)
		_check(box_lbl.position.x + box_lbl.size.x <= CANVAS.x + TOL,
			"开场提示文字右边界不出画布（%.1f）" % (box_lbl.position.x + box_lbl.size.x))
	box.queue_free()
	await process_frame

	# ============================================================
	# 八、引导阶段必须有出口（P15-A）：跳过引导 / 返回关卡
	# 遮罩是 MOUSE_FILTER_STOP 全屏铺满，没有出口时玩家只能把 6+3 步点完才能摸牌。
	# ============================================================
	scene.call("_on_start_tutorial", 0)
	await process_frame
	await process_frame
	var ov = scene.level0_overlay
	_check(ov != null and is_instance_valid(ov), "引导出口：Phase 1 overlay 存在")
	_check(_find_button(ov, "跳过引导") != null, "Phase 1 有「跳过引导」按钮")
	_check(_find_button(ov, "返回关卡") != null, "Phase 1 有「返回关卡」按钮")
	_check(_find_button(ov, "下一步 →") != null, "Phase 1 第 1 步有「下一步 →」按钮")
	scene.call("_level0_show_ui_step", scene.level0_ui_highlight_steps.size() - 1)
	await process_frame
	_check(_find_button(scene.level0_overlay, "继续 →") != null,
		"Phase 1 最后一步按钮文案是「继续 →」")
	_check(_find_button(scene.level0_overlay, "跳过引导") != null,
		"Phase 1 最后一步仍带「跳过引导」出口")

	# 跳过引导 → 直接进牌局练习（不是回到第 1 步，也不是卡在遮罩里）
	var skip_btn := _find_button(scene.level0_overlay, "跳过引导")
	skip_btn.emit_signal("pressed")
	await process_frame
	await process_frame
	_check(scene.game_manager.tutorial_level0_phase == 3, "点「跳过引导」直接进 Phase 3（牌局练习）")
	_check(scene.level0_overlay == null, "跳过引导后 overlay 已释放")
	_check(scene.level0_rule_tip_label != null and is_instance_valid(scene.level0_rule_tip_label),
		"跳过引导后规则提醒照常创建")
	_check(scene.level0_ui_highlight_steps.is_empty(), "跳过引导后步骤数据已清理")

	# Phase 2 同样有两个出口
	scene.call("_on_start_tutorial", 0)
	await process_frame
	await process_frame
	scene.call("_level0_start_phase2")
	await process_frame
	await process_frame
	_check(_find_button(scene.level0_overlay, "跳过引导") != null, "Phase 2 有「跳过引导」按钮")
	_check(_find_button(scene.level0_overlay, "返回关卡") != null, "Phase 2 有「返回关卡」按钮")
	_check(_find_button(scene.level0_overlay, "下一步 →") != null, "Phase 2 第 1 步有「下一步 →」按钮")

	# 返回关卡 → 回教学引导页（GamePage 必须藏起来，否则引导页被压在下面像点了没反应）
	var back_btn := _find_button(scene.level0_overlay, "返回关卡")
	back_btn.emit_signal("pressed")
	await process_frame
	await process_frame
	var tut_page = scene.get_node_or_null("TutorialPage")
	_check(tut_page != null and tut_page.visible, "点「返回关卡」回到教学引导页")
	_check(not scene.game_page.visible, "返回关卡时游戏页已隐藏（引导页不会被压住）")
	_check(scene.level0_overlay == null, "返回关卡后 overlay 已释放")
	_check(scene.game_manager.phase == 2, "返回关卡后本局判为结束（AI 计时器不会再推进）")

	# ============================================================
	# 九、第 5 步「其他细节（右面板）」高亮框必须贴着右栏面板
	#   老实现写死 (750,10) 400×350：框住状态栏下方一片空白，日志面板只有下半截在框里
	# ============================================================
	scene.call("_on_start_tutorial", 0)
	await process_frame
	await process_frame
	scene.call("_level0_show_ui_step", 4)
	await process_frame
	await process_frame
	var step5: Dictionary = scene.level0_ui_highlight_steps[4]
	_check(step5.get("target", "") == "log_label", "第 5 步目标是右栏日志面板")
	var log_panel = scene._log_panel
	_check(log_panel != null and is_instance_valid(log_panel), "右栏日志底板 LogPanel 存在")
	if log_panel != null and is_instance_valid(log_panel):
		var hl := Rect2(step5["pos"], step5["size"])
		var pr := Rect2(log_panel.position, log_panel.size)
		print("  右面板高亮框 = %s / LogPanel = %s" % [str(hl), str(pr)])
		_check(hl.encloses(pr), "高亮框完整包住日志面板")
		var pad: float = float(scene.RIGHT_PANEL_HL_PAD)
		_check(absf(hl.position.x - (pr.position.x - pad)) < TOL
				and absf(hl.position.y - (pr.position.y - pad)) < TOL
				and absf(hl.size.x - (pr.size.x + pad * 2.0)) < TOL
				and absf(hl.size.y - (pr.size.y + pad * 2.0)) < TOL,
			"高亮框 = 面板外扩 %dpx（不再是写死的大矩形）" % int(pad))
		_check(hl.position.y > 250.0,
			"高亮框不再从状态栏下方开始（y=%.1f，老实现是 10）" % hl.position.y)
		_check(hl.size.y < 300.0,
			"高亮框高度贴合面板（%.1f < 300，老实现 350）" % hl.size.y)
		_check(hl.end.x <= CANVAS.x + TOL and hl.end.y <= CANVAS.y + TOL,
			"高亮框在画布内：%s" % str(hl))
		# overlay 里的描边框必须按同一矩形画（否则「数据对了、画出来还是歪的」）
		var outline: Control = null
		var tip_rect := Rect2()
		for c in scene.level0_overlay.get_children():
			if not (c is Control):
				continue
			var ctl := c as Control
			if ctl.anchor_right != 0.0 or ctl.anchor_bottom != 0.0:
				continue
			if ctl.get_child_count() == 4 and ctl.size == hl.size and ctl.position == hl.position:
				outline = ctl
			if c is ColorRect and (c as ColorRect).color.is_equal_approx(Color(1, 1, 0.85, 0.95)):
				tip_rect = Rect2(ctl.position, ctl.size)
		_check(outline != null, "overlay 里的高亮框按同一矩形绘制")
		_check(tip_rect.size != Vector2.ZERO and not tip_rect.intersects(hl),
			"提示框（左侧）与右面板高亮框不重叠")
		_check(not Rect2(Vector2(20, 60), Vector2(460, 88)).intersects(hl),
			"高亮框不再压到「玩家顺序和手牌数」那块（第 1 步的标注区）")

	_finish()

