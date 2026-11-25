# ============================================================
# pages/ModePage.gd
# 对局模式小页（D24）：开始页「对局模式 ▸」→ 选模式 → 完成。
#
# 为什么单独一页而不是塞进补充规则页：模式不是「补充规则」。
# 补充规则是「加一条玩法」，模式改的是**既有判定的松紧**（族炸冷却 / 溢出免疫），
# 两者的勾选生命周期、默认值、联机归属（模式由房主定）都不同，
# 混在一页里玩家会以为「关了模式就没了补充规则」。
#
# 约定同 SuppRulesPage：选中的模式存在 GameUI._game_mode（root 持有），
# 本模块只经 _ui 读写；候选列表一律来自 GameModes.ORDER（加模式零改动）。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


func _build_mode_page() -> void:
	var page := Control.new()
	page.name = "ModePage"
	page.visible = false
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.start_page.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui._mode_page = page
	_ui._page_bg_into(page, "ModeBg", "ModeBand")

	var back = _ui._page_ghost_btn("‹ 返回", _close_mode_page, Vector2(140, 34), "ModeBackBtn", 15)
	back.position = Vector2(46, 34)
	page.add_child(back)

	var title = _ui._start_label("对局模式", 34, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "ModeTitle"
	title.position = Vector2(0, 62)
	title.size = Vector2(1152, 46)
	page.add_child(title)

	var sub = _ui._start_label("牌库与牌型完全相同，模式只改族炸相关判定；联机对局以房主选择为准",
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "ModeSubtitle"
	sub.position = Vector2(0, 110)
	sub.size = Vector2(1152, 20)
	page.add_child(sub)

	# 候选卡按 GameModes.ORDER 生成；同一 ButtonGroup 保证单选（点已选中的不会取消）
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in range(_ui.GameModesScript.ORDER.size()):
		_mode_card(page, int(_ui.GameModesScript.ORDER[i]), i, group)

	var tip = _ui._start_label("", _ui.START_FS_META, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	tip.name = "ModeTip"
	tip.position = Vector2(46, 316)
	tip.size = Vector2(1060, 44)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(tip)

	var done = _ui._page_primary_btn("完成", _close_mode_page, Vector2(260, 44), "ModeDoneBtn", 20)
	done.position = Vector2(846, 566)
	page.add_child(done)

	_sync_mode_summary()


# 一张模式卡：标题做成 toggle 按钮（与补充规则卡同一套样式）+ 说明 + 规则差异行
func _mode_card(page: Control, mode_id: int, idx: int, group: ButtonGroup) -> void:
	var card := Panel.new()
	card.name = "ModeCard_%d" % mode_id
	card.position = Vector2(46 + idx * 540, 146)
	card.size = Vector2(520, 150)
	var st = _ui._make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.96)
	card.add_theme_stylebox_override("panel", st)
	page.add_child(card)

	var btn = _ui._start_make_toggle("ModeChoice_%d" % mode_id,
		_ui.GameModesScript.name_of(mode_id), Vector2(18, 12))
	btn.size = Vector2(484, 34)
	btn.custom_minimum_size = Vector2(484, 34)
	btn.add_theme_font_size_override("font_size", 18)
	btn.button_group = group
	btn.button_pressed = (mode_id == _ui._game_mode)
	btn.toggled.connect(_on_mode_toggled.bind(mode_id))
	card.add_child(btn)

	var desc = _ui._start_label(_ui.GameModesScript.desc_of(mode_id),
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	desc.name = "ModeChoiceDesc_%d" % mode_id
	desc.position = Vector2(18, 52)
	desc.size = Vector2(484, 40)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(desc)

	# 差异行：标准局写「与默认完全一致」，特殊模式直接把差异列清楚
	var diff_txt: String = _ui.GameModesScript.summary_of(mode_id)
	if diff_txt == "":
		diff_txt = "与默认规则完全一致"
	var diff = _ui._start_label(diff_txt, 13,
		_ui.START_C_MUTED if diff_txt.find("完全一致") >= 0 else _ui.START_C_ACCENT,
		HORIZONTAL_ALIGNMENT_LEFT)
	diff.name = "ModeChoiceDiff_%d" % mode_id
	diff.position = Vector2(18, 100)
	diff.size = Vector2(484, 40)
	diff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(diff)


# 单选回写：状态存 root（GameUI._game_mode），本模块不另存一份
func _on_mode_toggled(pressed: bool, mode_id: int) -> void:
	if not pressed:
		return
	_ui.set_game_mode(mode_id)
	_ui._start_flash_rule_hint("已选择对局模式：%s" % _ui.GameModesScript.name_of(mode_id))


# 唯一出口：开始页摘要 / 小页提示同时刷，避免两处各写一套文案
func _sync_mode_summary() -> void:
	var mode_id: int = _ui._selected_game_mode()
	var name: String = _ui.GameModesScript.name_of(mode_id)
	var diff: String = _ui.GameModesScript.summary_of(mode_id)
	var standard: bool = _ui.GameModesScript.is_standard(mode_id)

	var sum = _ui._start_child("ModeSummary")
	if sum:
		sum.text = name if standard else name + "\n特殊模式"
		sum.add_theme_color_override("font_color",
			_ui.START_C_MUTED if standard else _ui.START_C_ACCENT)

	var entry = _ui._start_child("ModeEntryBtn")
	if entry:
		entry.text = "对局模式 ▸"

	var tip = _ui._mode_page.get_node_or_null("ModeTip") if _ui._mode_page else null
	if tip:
		tip.text = "当前：%s" % (name if standard else diff)


func _open_mode_page() -> void:
	if _ui._mode_page == null or not is_instance_valid(_ui._mode_page):
		return
	# 打开时以 root 里的选择为准重放一次（联机回房间后可能被主机配置改过）
	var btn = _ui._mode_page.get_node_or_null("ModeCard_%d/ModeChoice_%d" % [
		_ui._selected_game_mode(), _ui._selected_game_mode()])
	if btn and not btn.button_pressed:
		btn.button_pressed = true
	_sync_mode_summary()
	_ui._mode_page.visible = true


func _close_mode_page() -> void:
	if _ui._mode_page and is_instance_valid(_ui._mode_page):
		_ui._mode_page.visible = false
