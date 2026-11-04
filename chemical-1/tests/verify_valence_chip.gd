# 验证卡面化合价圆底（CardValenceChip）与文字严格对齐，且任何档位都不画出卡边。
# 历史 bug（截图回归）：
#   1) chip 按「居中于 label」定位，而紧凑牌面把 label 改成左对齐 → 粉底整体右偏，
#      纯文字"漂"在粉底左边；
#   2) 多价元素（N = -3 +3 +5）在紧凑档只有 38px 可用宽，文字压到相邻牌上。
# 现在的结构：CardValenceChip 是 CardValence 的父节点 —— 粉底与文字物理绑定，
# 不再存在"两个独立节点互相猜对齐"的可能。
extends SceneTree

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardDataScript = preload("res://scripts/CardData.gd")

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

	if scene.hand_container == null:
		print("ABORT: 找不到 HandContainer")
		quit(1)
		return

	_check_chip_structure(scene)
	_check_all_elements(scene, false)
	_check_all_elements(scene, true)
	await _check_live_hand(scene)

	if fails == 0:
		print("ALL VALENCE CHIP TESTS PASSED")
	else:
		print("%d VALENCE CHIP TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


# 结构：chip 必须是 label 的父节点，否则两者只能靠坐标公式对齐（就是这次的 bug）
func _check_chip_structure(scene) -> void:
	var card = _find_card("N")
	var btn = scene.call("_build_card_button", card, 0)
	scene.hand_container.add_child(btn)
	var chip = btn.get_node_or_null("CardValenceChip")
	var val: Label = chip.get_node_or_null("CardValence") if chip else null
	_check(chip != null, "价态圆底节点存在（CardValenceChip）")
	_check(val != null, "价态文字节点存在（CardValence，挂在圆底下）")
	if chip == null or val == null:
		btn.queue_free()
		return
	_check(val.get_parent() == chip, "CardValence 是 CardValenceChip 的子节点（粉底与文字同体）")
	_check(chip.get_parent() == btn, "CardValenceChip 挂在卡片按钮下")
	_check(chip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "价态圆底不吃鼠标")
	_check(val.mouse_filter == Control.MOUSE_FILTER_IGNORE, "价态文字不吃鼠标")
	var sb = chip.get_theme_stylebox("panel")
	_check(sb is StyleBoxFlat and sb.corner_radius_top_left == int(scene.CHIP_RADIUS),
		"价态圆底走工厂（圆角 CHIP_RADIUS=%d）" % int(scene.CHIP_RADIUS))
	btn.queue_free()


# 全量元素 × 两档：粉底必须完整包住文字，且整体留在卡内
func _check_all_elements(scene, compact: bool) -> void:
	var tag: String = "紧凑档" if compact else "常规档"
	var bad_align: Array = []
	var bad_overflow: Array = []
	var n: int = 0
	for e in CardDatabaseScript.get_element_data():
		var card = CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11], e[12])
		var btn = scene.call("_build_card_button", card, 0)
		scene.hand_container.add_child(btn)
		scene.call("_apply_card_compact", btn, compact)
		var chip = btn.get_node_or_null("CardValenceChip")
		var val: Label = chip.get_node_or_null("CardValence") if chip else null
		if chip == null or val == null:
			btn.queue_free()
			continue
		n += 1
		var text_rect: Rect2 = _text_rect(scene, val)
		var chip_rect: Rect2 = Rect2(chip.position, chip.size)
		# 文字必须在粉底内水平居中（本次 bug 的核心）
		if not _h_centered(text_rect, chip_rect):
			bad_align.append("%s \"%s\" text=%s chip=%s" % [card.symbol, val.text, str(text_rect), str(chip_rect)])
		# 粉底必须留在卡内（卡宽 CARD_W=95）
		if chip_rect.position.x < -0.5 or chip_rect.end.x > 95.5:
			bad_overflow.append("%s chip=%s" % [card.symbol, str(chip_rect)])
		print("  [%s] %-3s \"%s\" fs=%d fit=%.1f chip=(%.1f,%.1f,%.1f,%.1f) text_w=%.1f align=%d" % [
			tag, card.symbol, val.text, val.get_theme_font_size("font_size"),
			float(val.get_meta("fit_w", 0.0)), chip.position.x, chip.position.y,
			chip.size.x, chip.size.y, text_rect.size.x, val.horizontal_alignment])
		btn.queue_free()
	_check(n >= 20, "%s：扫过 %d 种元素" % [tag, n])
	_check(bad_align.is_empty(), "%s：粉底完整包住文字（错位 %d 张 %s）" % [tag, bad_align.size(), str(bad_align)])
	_check(bad_overflow.is_empty(), "%s：粉底不出卡（越界 %d 张 %s）" % [tag, bad_overflow.size(), str(bad_overflow)])


# 真实手牌（8 张 → 紧凑档）：逐张确认，并验证 compact 档文字起点靠左
func _check_live_hand(scene) -> void:
	scene.call("_on_start_game")
	for _i in range(5):
		await process_frame
	_check(scene.hand_buttons.size() > 0, "开局手牌已生成 (n=%d)" % scene.hand_buttons.size())
	if scene.hand_buttons.is_empty():
		return
	var bad: Array = []
	for b in scene.hand_buttons:
		if not is_instance_valid(b):
			continue
		var chip = b.get_node_or_null("CardValenceChip")
		var val: Label = chip.get_node_or_null("CardValence") if chip else null
		if chip == null or val == null:
			bad.append("缺节点")
			continue
		var text_rect: Rect2 = _text_rect(scene, val)
		var chip_rect: Rect2 = Rect2(chip.position, chip.size)
		if not _h_centered(text_rect, chip_rect):
			bad.append("%s \"%s\" text=%s chip=%s" % [b.get_meta("card").symbol, val.text, str(text_rect), str(chip_rect)])
		if chip_rect.end.x > 95.5:
			bad.append("%s 出卡 %s" % [b.get_meta("card").symbol, str(chip_rect)])
	_check(bad.is_empty(), "真实手牌 8 张：每张粉底都包住文字且不出卡（异常 %d 项 %s）" % [bad.size(), str(bad)])


# 文字在按钮坐标系内的实际矩形：label 已挂在 chip 下，所以要把父节点偏移算进来，
# 这样校验的是"真实渲染位置"，而不是 label 的外框 —— 后者正是旧 bug 骗过测试的原因。
func _text_rect(scene, lbl: Label) -> Rect2:
	var fs: int = lbl.get_theme_font_size("font_size")
	var font: Font = lbl.get_theme_font("font")
	var w: float = font.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h: float = font.get_height(fs)
	var base_y: float = (lbl.size.y - h) * 0.5
	if lbl.vertical_alignment == VERTICAL_ALIGNMENT_TOP:
		base_y = 0.0
	elif lbl.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		base_y = lbl.size.y - h
	var x: float = 0.0
	if lbl.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (lbl.size.x - w) * 0.5
	elif lbl.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = lbl.size.x - w
	return Rect2(lbl.position + lbl.get_parent().position + Vector2(x, base_y), Vector2(w, h))


# 文字是否在粉底内水平居中：左右都留出余量，且两侧余量相等（±0.5px）
func _h_centered(text_rect: Rect2, chip_rect: Rect2) -> bool:
	if text_rect.position.x < chip_rect.position.x - 0.5:
		return false
	if text_rect.end.x > chip_rect.end.x + 0.5:
		return false
	var text_c: float = text_rect.position.x + text_rect.size.x * 0.5
	var chip_c: float = chip_rect.position.x + chip_rect.size.x * 0.5
	return absf(text_c - chip_c) <= 0.5


func _find_card(symbol: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == symbol:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9], e[10], e[11], e[12])
	return null
