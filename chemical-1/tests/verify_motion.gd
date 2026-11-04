# 验证动效与排版规范（P4）：
#   1) 页面淡入：常驻同色底 + 目标页 modulate 0→1，visible 语义保持同步
#   2) 按钮缩放：pivot 居中 / 悬停 1.05 / 按下 0.96 / 禁用不缩放
#   3) 卡牌字号：符号 28、中文名 14（紧凑牌面保持 21 / 12），且互不重叠
#   4) 手牌缩放（A2）：悬停 1.06 / 选中 1.04 / 常态 1.0，pivot 居中且重排清补间
#   5) 桌面区（A2）：牌型配色 + 文字淡入 + 小卡入场（0.9 → 1.0 + 淡入，不动 position）
extends SceneTree

const CardPatternsScript = preload("res://scripts/CardPatterns.gd")

var fails: int = 0

func _init():
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)

# headless 下不能用 create_timer（无帧推进），统一轮询 is_running()
func _wait_tween(tw) -> void:
	var guard: int = 0
	while tw is Tween and tw.is_valid() and tw.is_running() and guard < 600:
		await process_frame
		guard += 1

func _wait_meta_tween(node: Node, key: String) -> void:
	var tw = node.get_meta(key, false)
	var guard: int = 0
	while tw is Tween and tw.is_valid() and tw.is_running() and guard < 600:
		await process_frame
		guard += 1

func _run():
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	await _test_page_fade(scene)
	await _test_button_scale(scene)
	await _test_end_page_motion(scene)
	await _test_card_fonts(scene)
	await _test_hand_and_table_motion(scene)

	if fails == 0:
		print("ALL MOTION TESTS PASSED")
	else:
		print("%d MOTION TESTS FAILED" % fails)
	quit(1 if fails > 0 else 0)


# ---------------- 1. 页面淡入 ----------------
func _test_page_fade(scene) -> void:
	var backdrop = scene.get_node_or_null("PageBackdrop")
	_check(backdrop != null, "根节点存在常驻同色底 PageBackdrop")
	if backdrop == null:
		return
	_check(backdrop.color.is_equal_approx(scene.PAGE_BG_COLOR), "同色底使用 #E6F0FA 与各页背景一致")
	_check(backdrop.z_index < 0, "同色底位于所有页面之下 (z=%d)" % backdrop.z_index)
	_check(backdrop.get_index() == 0, "同色底是第一个子节点（先于页面绘制）")
	_check(backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE, "同色底不拦截鼠标")
	_check(backdrop.size.x >= 1152.0 and backdrop.size.y >= 648.0,
		"同色底铺满视口 (%s)" % str(backdrop.size))

	# 启动时 _show_start_page() 已触发一次淡入
	var start_page = scene.get_node("StartPage")
	_check(scene._page_fade_tween != null and scene._page_fade_tween.is_valid(), "启动即有一次页面淡入补间")
	await _wait_tween(scene._page_fade_tween)
	_check(abs(start_page.modulate.a - 1.0) < 0.01,
		"淡入结束后开始页不透明度为 1 (a=%.2f)" % start_page.modulate.a)

	# 切到教程页：visible 同步生效，新页从 0 淡入
	scene._on_show_tutorial_page()
	var tut = scene.get_node_or_null("TutorialPage")
	_check(tut != null and tut.visible, "教程页可见（visible 语义仍是同步的）")
	_check(not start_page.visible, "开始页已同步隐藏（未采用延迟隐藏）")
	_check(tut.modulate.a <= 0.2, "新页从透明开始淡入 (a=%.2f)" % tut.modulate.a)
	_check(start_page.modulate.a >= 0.99, "被切走的页 alpha 已复位（不会残留半透明）")
	await _wait_tween(scene._page_fade_tween)
	_check(abs(tut.modulate.a - 1.0) < 0.01, "淡入结束后教程页完全不透明")

	# 返回开始页
	scene._on_tutorial_back()
	_check(start_page.visible, "返回开始页 visible 同步生效")
	await _wait_tween(scene._page_fade_tween)
	_check(abs(start_page.modulate.a - 1.0) < 0.01, "返回后开始页完全不透明")

	# 淡入中途再切换：旧补间必须被杀掉，目标页不能被留在半透明
	scene._on_show_tutorial_page()
	await process_frame
	scene._on_tutorial_back()
	_check(scene._page_fade_tween != null and scene._page_fade_tween.is_valid(),
		"淡入中途切换：新补间已接管")
	await _wait_tween(scene._page_fade_tween)
	_check(abs(start_page.modulate.a - 1.0) < 0.01, "淡入中途切换：最终仍收敛到完全不透明")

	# 帮助页内部 tab 切换不打补间（同层切换即时更自然）
	scene._on_show_help()
	await _wait_tween(scene._page_fade_tween)
	var help_tween = scene._page_fade_tween
	scene._on_help_show_cards()
	await process_frame
	_check(scene._page_fade_tween == help_tween, "帮助页内部 tab 切换不新建淡入补间")
	scene._on_help_back()
	await _wait_tween(scene._page_fade_tween)
	_check(scene.start_page.visible or scene.game_page.visible, "帮助返回后回到某个主页面")


# ---------------- 2. 按钮缩放 ----------------
func _test_button_scale(scene) -> void:
	scene.game_page.visible = true
	var btn = scene._mkb("测试按钮", func() -> void: pass, false)
	scene.action_panel.add_child(btn)
	await process_frame
	await process_frame

	_check(btn.pivot_offset.is_equal_approx(btn.size * 0.5),
		"按钮 pivot 居中 (pivot=%s size=%s)" % [str(btn.pivot_offset), str(btn.size)])
	_check(btn.mouse_entered.get_connections().size() > 0, "按钮已接入悬停缩放信号")
	_check(btn.button_down.get_connections().size() > 0, "按钮已接入按下缩放信号")

	scene._on_button_hover_scale(btn, true)
	await _wait_meta_tween(btn, "btn_scale_tween")
	_check(abs(btn.scale.x - scene.BUTTON_HOVER_SCALE) < 0.01,
		"悬停放大到 %.2f (实际 %.2f)" % [scene.BUTTON_HOVER_SCALE, btn.scale.x])
	_check(abs(btn.scale.y - btn.scale.x) < 0.001, "缩放等比（x=y）")

	scene._on_button_press_scale(btn, true)
	await _wait_meta_tween(btn, "btn_scale_tween")
	_check(abs(btn.scale.x - scene.BUTTON_PRESS_SCALE) < 0.01,
		"按下回缩到 %.2f (实际 %.2f)" % [scene.BUTTON_PRESS_SCALE, btn.scale.x])

	scene._on_button_hover_scale(btn, false)
	await _wait_meta_tween(btn, "btn_scale_tween")
	_check(abs(btn.scale.x - 1.0) < 0.01, "移出恢复 1.0 (实际 %.2f)" % btn.scale.x)

	# 每个按钮只保留一个缩放补间（快速进出不叠加）
	scene._on_button_hover_scale(btn, true)
	scene._on_button_hover_scale(btn, false)
	scene._on_button_hover_scale(btn, true)
	await process_frame
	var tw = btn.get_meta("btn_scale_tween", false)
	_check(tw is Tween and tw.is_valid(), "连续进出只保留一个有效补间")
	await _wait_meta_tween(btn, "btn_scale_tween")
	_check(abs(btn.scale.x - scene.BUTTON_HOVER_SCALE) < 0.01, "连续进出后收敛到最后一次目标")

	# 禁用按钮不缩放（避免暗示可点击）
	var dbtn = scene._mkb("禁用按钮", func() -> void: pass, true)
	scene.action_panel.add_child(dbtn)
	await process_frame
	scene._on_button_hover_scale(dbtn, true)
	await process_frame
	_check(dbtn.get_meta("btn_scale_tween", false) == false, "禁用按钮不产生缩放补间")
	_check(abs(dbtn.scale.x - 1.0) < 0.001, "禁用按钮保持 1.0 不放大")

	# 悬停发光走 StyleBoxFlat 的 shadow，且不改变圆角规范
	var hover_sb = btn.get_theme_stylebox("hover")
	_check(hover_sb is StyleBoxFlat, "悬停样式为 StyleBoxFlat")
	if hover_sb is StyleBoxFlat:
		_check(hover_sb.shadow_color.a > 0.3, "悬停发光：阴影为半透明亮色 (a=%.2f)" % hover_sb.shadow_color.a)
		_check(hover_sb.shadow_size >= 4, "悬停发光：阴影外扩 %d px" % hover_sb.shadow_size)
		_check(hover_sb.corner_radius_top_left == btn.get_theme_stylebox("normal").corner_radius_top_left,
			"悬停发光不改变圆角")

	btn.queue_free()
	dbtn.queue_free()
	await process_frame


# ---------------- 3. 结束页入场 ----------------
# 页面级 modulate 归 _fade_in_page 独占；子节点入场由 _animate_page_intro 负责。
# 反复进入结束页（_refresh_ui 会重入）时基准位置不能累积上浮 +14
func _wait_intro(scene) -> void:
	var guard: int = 0
	while guard < 600:
		var running := false
		for t in scene._page_intro_tweens:
			if t is Tween and t.is_valid() and t.is_running():
				running = true
				break
		if not running:
			return
		await process_frame
		guard += 1


func _test_end_page_motion(scene) -> void:
	scene._init_game(4, 3)
	await process_frame
	var end_page = scene.get_node("EndPage")
	var card = end_page.get_node_or_null("EndCard")
	_check(card != null, "结束页有结算卡 EndCard")
	if card == null:
		return
	var base_y: float = card.position.y
	scene._on_quit_game()
	_check(end_page.visible, "退出后结束页可见")
	_check(end_page.modulate.a < 0.2, "结束页从透明淡入 (a=%.2f)" % end_page.modulate.a)
	_check(card.modulate.a < 0.2, "结算卡子节点错峰淡入从透明开始")
	_check(card.position.y > base_y, "结算卡入场自下方上浮 (%.1f > %.1f)" % [card.position.y, base_y])
	await _wait_tween(scene._page_fade_tween)
	await _wait_intro(scene)
	_check(abs(end_page.modulate.a - 1.0) < 0.01, "结束页淡入收敛到完全不透明")
	_check(abs(card.position.y - base_y) < 0.01, "结算卡落回基准位置 (y=%.1f)" % card.position.y)

	# 反复进入结束页：基准位置在首次入场时记录，不随重入累积偏移
	for i in range(3):
		scene._show_end_page("")
		await process_frame
	await _wait_intro(scene)
	_check(abs(card.position.y - base_y) < 0.01,
		"重入 3 次后结算卡不偏移 (y=%.1f / 基准 %.1f)" % [card.position.y, base_y])
	_check(abs(end_page.modulate.a - 1.0) < 0.01, "重入期间页面 alpha 不被子节点动画改写")


# ---------------- 4. 卡牌字号 ----------------
func _test_card_fonts(scene) -> void:
	scene._init_game(4, 3)
	await process_frame
	await process_frame

	if scene.game_manager == null or scene.game_manager.get_player_count() == 0:
		_check(false, "对局初始化失败，无法验证卡牌字号")
		return
	if scene.hand_buttons.is_empty():
		_check(false, "手牌未生成，无法验证卡牌字号")
		return

	var card = scene.game_manager.get_current_player().hand[0]
	var btn = scene._build_card_button(card, 0)
	scene.hand_container.add_child(btn)
	await process_frame

	var sym = btn.get_node_or_null("CardSymbol")
	var nm = btn.get_node_or_null("CardName")
	_check(sym != null and nm != null, "卡牌包含 CardSymbol / CardName")
	if sym == null or nm == null:
		btn.queue_free()
		return

	scene._apply_card_compact(btn, false)
	_check(sym.get_theme_font_size("font_size") == 28, "常规牌面元素符号 28px（文档 §4.2）")
	_check(nm.get_theme_font_size("font_size") == 14, "常规牌面中文名 14px（文档 §4.2）")
	# Label 的 size 会被字体最小高度撑大，但字形仍自顶部绘制，
	# 因此重叠判定用「字号推算的字形高度」而不是节点 size
	_check(sym.position.y + 28 <= nm.position.y + 4,
		"符号字形（28px）下沿不压中文名 (%.0f <= %.0f)" % [sym.position.y + 28, nm.position.y])
	_check(nm.position.y + 14 <= 72.0,
		"中文名字形（14px）下沿不压化合价 (%.0f <= 72)" % (nm.position.y + 14))
	_check(sym.position.x >= 0 and sym.size.x <= scene.CARD_W,
		"符号区不越出牌宽 (w=%.0f <= %.0f)" % [sym.size.x, scene.CARD_W])

	scene._apply_card_compact(btn, true)
	_check(sym.get_theme_font_size("font_size") == 21, "紧凑牌面元素符号保持 21px")
	_check(nm.get_theme_font_size("font_size") == 12, "紧凑牌面中文名保持 12px")
	_check(sym.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "紧凑牌面内容左对齐（露出的左条可读）")

	btn.queue_free()
	await process_frame


# ---------------- 5. 手牌缩放 + 桌面区（A2） ----------------
# 手牌缩放的意义：整排手牌抬高 20px + 1.06 放大，视线一眼锁定「正在看的那张」；
# 命中判定用静态 _card_hover_rect()（不含 scale），所以放大不会引发自激抖动。
func _test_hand_and_table_motion(scene) -> void:
	if scene.hand_buttons.size() < 2:
		_check(false, "A2：手牌不足 2 张，无法验证缩放")
		return
	var hb: Button = scene.hand_buttons[0]
	_check(hb.pivot_offset.is_equal_approx(Vector2(scene.CARD_W, scene.CARD_H) * 0.5),
		"手牌 pivot 居中（放大不往右下偏）")
	_check(scene.HAND_SELECT_SCALE < scene.HAND_HOVER_SCALE,
		"选中档 %.2f < 悬停档 %.2f（悬停不能被选中态压制）" % [scene.HAND_SELECT_SCALE, scene.HAND_HOVER_SCALE])

	# 悬停 → 1.06
	scene._set_hover_index(0)
	await _wait_meta_tween(hb, "scale_tween")
	_check(abs(hb.scale.x - scene.HAND_HOVER_SCALE) < 0.01,
		"手牌悬停放大到 %.2f（实际 %.2f）" % [scene.HAND_HOVER_SCALE, hb.scale.x])
	_check(abs(hb.scale.x - hb.scale.y) < 0.001, "手牌缩放等比（x=y）")

	# 移出 + 选中 → 1.04
	scene.selected_indices.clear()
	scene.selected_indices.append(0)
	scene._set_hover_index(-1)
	await _wait_meta_tween(hb, "scale_tween")
	_check(abs(hb.scale.x - scene.HAND_SELECT_SCALE) < 0.01,
		"选中的手牌落在 %.2f（实际 %.2f）" % [scene.HAND_SELECT_SCALE, hb.scale.x])

	# 取消选中 + 重排 → 1.0，且不留缩放补间（重排是瞬时整排落位）
	scene.selected_indices.clear()
	scene._update_hand_buttons()
	await process_frame
	var hb2: Button = scene.hand_buttons[0]
	_check(abs(hb2.scale.x - 1.0) < 0.01, "取消选中并重排后缩放回到 1.0（实际 %.2f）" % hb2.scale.x)
	var tw = hb2.get_meta("scale_tween", false)
	_check(not (tw is Tween and tw.is_valid() and tw.is_running()), "重排后不残留缩放补间")

	# 桌面文字：按牌型上色 + 换行淡入
	var c_comp: Color = scene._table_type_color(CardPatternsScript.CardPattern.COMPOUND)
	var c_bomb: Color = scene._table_type_color(CardPatternsScript.CardPattern.CLAN_BOMB)
	var c_seq: Color = scene._table_type_color(CardPatternsScript.CardPattern.SEQUENCE)
	_check(c_comp.g > c_comp.r and c_bomb.r > c_bomb.g and c_seq.b > c_seq.g,
		"牌型配色可区分：化合物偏绿 / 族炸偏红 / 顺序偏紫")
	scene._set_table_text("桌面: 测试化合物", CardPatternsScript.CardPattern.COMPOUND)
	_check(scene.table_label.modulate.a < 0.5, "桌面文字换行时从半透明开始淡入")
	await _wait_meta_tween(scene.table_label, "reveal_tween")
	_check(abs(scene.table_label.modulate.a - 1.0) < 0.01, "桌面文字淡入收敛到不透明")
	scene._set_table_text("桌面: 测试化合物", CardPatternsScript.CardPattern.COMPOUND)
	_check(scene.table_label.modulate.a >= 0.99, "文本未变化时不重播淡入（否则每帧刷新都闪）")

	# 小卡入场：0.9 → 1.0 + 淡入，且 position 一个像素都不动（槽位是布局真值）
	var mini = scene._build_mini_card_button(scene.game_manager.get_current_player().hand[0])
	mini.position = Vector2(40, 186)
	scene._layer(0).add_child(mini)
	var pos0: Vector2 = mini.position
	scene._animate_mini_card_in(mini, 1)
	_check(mini.scale.x <= 0.91 and mini.modulate.a <= 0.01, "小卡入场从 0.9 / 透明开始")
	await _wait_meta_tween(mini, "mini_in_tween")
	_check(abs(mini.scale.x - 1.0) < 0.01 and abs(mini.modulate.a - 1.0) < 0.01,
		"小卡入场收敛到 1.0 / 不透明")
	_check(mini.position.is_equal_approx(pos0), "小卡入场不动 position（%s）" % str(pos0))
	mini.queue_free()
	await process_frame
