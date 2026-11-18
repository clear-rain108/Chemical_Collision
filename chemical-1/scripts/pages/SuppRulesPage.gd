# ============================================================
# pages/SuppRulesPage.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4c，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 793-958 行 --------
# ============================================================
# 五之二、补充规则小页（P10：四条补充规则合成一小页）
# ============================================================
# 为什么单独一页：SettingsCard 里已有「总人数 / AI 人数 / 开始游戏」三块，
# 再加第 4 条补充规则就会把开局按钮挤到卡外（旧布局 4 个开关已占满 210px 高的卡）。
# 这一页 = 4 张规则卡 + 元素池（前 20 号固定 / 9 种扩展可勾选）+ 说明入口。
func _build_supp_rules_page() -> void:
	var page := Control.new()
	page.name = "SuppRulesPage"
	page.visible = false
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.start_page.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui._supp_rules_page = page
	_ui._page_bg_into(page, "SuppRulesBg", "SuppRulesBand")

	var back = _ui._page_ghost_btn("‹ 返回", _close_supp_rules, Vector2(140, 34), "SuppRulesBackBtn", 15)
	back.position = Vector2(46, 34)
	page.add_child(back)

	var title = _ui._start_label("补充规则", 34, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "SuppRulesTitle"
	title.position = Vector2(0, 62)
	title.size = Vector2(1152, 46)
	page.add_child(title)

	var sub = _ui._start_label("默认全部关闭；勾选后仅对下一局生效",
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "SuppRulesSubtitle"
	sub.position = Vector2(0, 110)
	sub.size = Vector2(1152, 20)
	page.add_child(sub)

	_supp_rule_card(page, "OrganicCheckBox", "有机物胜利",
		"打出 CH4 / C2H6 / C3H8 或单一卤代物立即获胜", Vector2(46, 146))
	_supp_rule_card(page, "SequenceCheckBox", "顺序牌型",
		"≥3 张连续原子序数：抢牌权 + 反转方向 + 指定下家牌型", Vector2(586, 146))
	_supp_rule_card(page, "HalogenCheckBox", "允许卤族互化",
		"F/Cl/Br/I 之间可互相化合（如 ClF）；族炸始终不受影响", Vector2(46, 250))
	_supp_rule_card(page, "ElementLimitCheckBox", "元素限制",
		"牌库只保留前 20 号元素（H~Ca），可再挑副族 / 卤族加入", Vector2(586, 250))

	_build_element_pool(page)

	var supp_help_btn = _ui._page_ghost_btn("查看完整说明 >", _ui._on_help_show_supp,
		Vector2(240, 34), "SuppRulesHelpBtn", 15)
	supp_help_btn.position = Vector2(46, 570)
	page.add_child(supp_help_btn)

	var done = _ui._page_primary_btn("完成", _close_supp_rules, Vector2(260, 44), "SuppRulesDoneBtn", 20)
	done.position = Vector2(846, 566)
	page.add_child(done)

	_sync_supp_rules_summary()


# 一张规则卡：标题做成 toggle 按钮（与旧开始页开关同一套样式），下面一行说明
func _supp_rule_card(page: Control, node_name: String, title: String, desc: String, pos: Vector2) -> Button:
	var card := Panel.new()
	card.name = node_name + "Card"
	card.position = pos
	card.size = Vector2(520, 92)
	var st = _ui._make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.96)
	card.add_theme_stylebox_override("panel", st)
	page.add_child(card)

	var btn = _ui._start_make_toggle(node_name, title, Vector2(18, 12))
	btn.size = Vector2(484, 34)
	btn.custom_minimum_size = Vector2(484, 34)
	btn.add_theme_font_size_override("font_size", 17)
	card.add_child(btn)

	var d = _ui._start_label(desc, _ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	d.position = Vector2(18, 52)
	d.size = Vector2(484, 32)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(d)
	return btn


# 元素池：前 20 号固定加入；9 种扩展元素（副族 7 + Br/I）按 chip 勾选
func _build_element_pool(page: Control) -> void:
	var area := Panel.new()
	area.name = "ElementPoolPanel"
	area.position = Vector2(46, 356)
	area.size = Vector2(1060, 168)
	var st = _ui._make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.96)
	area.add_theme_stylebox_override("panel", st)
	page.add_child(area)

	var t = _ui._start_label("元素池", 17, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
	t.position = Vector2(20, 10)
	t.size = Vector2(160, 24)
	area.add_child(t)

	_ui._supp_element_stats = _ui._start_label("", _ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_ui._supp_element_stats.name = "ElementPoolStats"
	_ui._supp_element_stats.position = Vector2(180, 12)
	_ui._supp_element_stats.size = Vector2(860, 20)
	area.add_child(_ui._supp_element_stats)

	var tip = _ui._start_label("前 20 号元素（H ~ Ca）固定加入；勾选下面的元素可额外加进牌库",
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	tip.name = "ElementPoolTip"
	tip.position = Vector2(20, 36)
	tip.size = Vector2(1020, 18)
	area.add_child(tip)

	# chip 104×28 + 间距 8 → 9 个排一行（9*104 + 8*8 = 1000，池内宽 1020）
	var items = _ui.CardDatabaseScript.get_optional_elements()
	for i in range(items.size()):
		var info: Dictionary = items[i]
		var sym := str(info["symbol"])
		var chip = _ui._start_make_toggle("ElementChip_" + sym,
			"%s %s · %d" % [sym, str(info["name_cn"]), int(info["number"])],
			Vector2(20 + i * 112, 62))
		chip.add_theme_font_size_override("font_size", 13)
		# 104 宽 + 13px：内边距从 toggle 默认的 12 收到 10，避免 "Cr 铬 · 24" 贴边
		for st_name in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb := chip.get_theme_stylebox(st_name) as StyleBoxFlat
			if sb != null:
				sb.content_margin_left = 10
				sb.content_margin_right = 10
		chip.tooltip_text = "%s%s（原子序数 %d）；勾选后加入牌库" % [
			str(info["group_label"]), sym, int(info["number"])]
		area.add_child(chip)
		# 尺寸必须在入树后设置：树外 update_minimum_size() 不生效，
		# 会把 size 夹回 _start_make_toggle 的 270×32
		chip.custom_minimum_size = Vector2(104, 28)
		chip.size = Vector2(104, 28)
		_ui._supp_element_chips[sym] = chip

	# 分隔线 + 基础池清单：数据取自 CardDatabase，后续新增元素自动跟随，无需改 UI
	var div := ColorRect.new()
	div.name = "ElementPoolDivider"
	div.color = Color(0.886, 0.914, 0.945, 1.0)
	div.position = Vector2(20, 96)
	div.size = Vector2(1020, 1)
	area.add_child(div)

	var base_title = _ui._start_label("固定加入 · 前 20 号元素（H ~ Ca）",
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	base_title.name = "ElementPoolBaseTitle"
	base_title.position = Vector2(20, 102)
	base_title.size = Vector2(1020, 18)
	area.add_child(base_title)

	var base_syms = _ui.CardDatabaseScript.get_base_element_symbols()
	for line in range(2):
		var lbl = _ui._start_label(_symbols_joined(base_syms.slice(line * 10, line * 10 + 10)),
			13, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT)
		lbl.name = "ElementPoolBase%d" % line
		lbl.position = Vector2(20, 122 + line * 20)
		lbl.size = Vector2(1020, 18)
		area.add_child(lbl)


# 把符号数组拼成 "H  ·  He  ·  Li" 形式（元素池基础清单用）
func _symbols_joined(syms: Array) -> String:
	var parts := PackedStringArray()
	for s in syms:
		parts.append(str(s))
	return "  ·  ".join(parts)



# -------- 搬运自 scripts/GameUI.gd 第 1891-2001 行 --------
func _on_organic_toggled(pressed: bool) -> void:
	if pressed:
		_ui._show_info_simple("已启用有机物胜利规则")
	else:
		_ui._show_info_simple("已禁用有机物胜利规则")
	_ui._start_flash_rule_hint("已启用有机物胜利规则" if pressed else "已禁用有机物胜利规则")
	_sync_supp_rules_summary()

func _on_sequence_toggled(pressed: bool) -> void:
	if pressed:
		_ui._show_info_simple("已启用顺序牌型规则")
	else:
		_ui._show_info_simple("已禁用顺序牌型规则")
	_ui._start_flash_rule_hint("已启用顺序牌型规则" if pressed else "已禁用顺序牌型规则")
	_sync_supp_rules_summary()

# 允许卤族互化（补充规则）：默认关闭 = 沿用硬规则「F/Cl/Br/I 之间不可化合」
func _on_halogen_toggled(pressed: bool) -> void:
	if pressed:
		_ui._show_info_simple("已允许卤族互化（F/Cl/Br/I 之间可互相化合）")
	else:
		_ui._show_info_simple("已禁止卤族互化")
	_ui._start_flash_rule_hint("已允许卤族互化" if pressed else "已禁止卤族互化")
	_sync_supp_rules_summary()

# 元素限制（补充规则）：默认关闭 = 29 种元素全上桌
func _on_element_limit_toggled(pressed: bool) -> void:
	if pressed:
		_ui._show_info_simple("已启用元素限制（前 20 号元素 + 自选扩展）")
	else:
		_ui._show_info_simple("已关闭元素限制（29 种元素全部上桌）")
	_ui._start_flash_rule_hint("已启用元素限制" if pressed else "已关闭元素限制")
	_sync_supp_rules_summary()

# 点元素 chip 时自动打开「元素限制」，否则勾了也不生效，容易被当成 bug
func _on_element_chip_toggled(_pressed: bool) -> void:
	var limit_cb = _ui._start_child("ElementLimitCheckBox")
	if limit_cb and not limit_cb.button_pressed:
		limit_cb.button_pressed = true
	_sync_supp_rules_summary()


# 勾选状态 → 设置卡入口文字 / 摘要行 / 元素池统计（唯一出口，避免多处各写一套文案）
func _sync_supp_rules_summary() -> void:
	var on: Array = []
	var organic_cb = _ui._start_child("OrganicCheckBox")
	if organic_cb and organic_cb.button_pressed: on.append("有机物")
	var seq_cb = _ui._start_child("SequenceCheckBox")
	if seq_cb and seq_cb.button_pressed: on.append("顺序")
	var hal_cb = _ui._start_child("HalogenCheckBox")
	if hal_cb and hal_cb.button_pressed: on.append("卤族互化")
	var limit_cb = _ui._start_child("ElementLimitCheckBox")
	var limit_on: bool = limit_cb != null and limit_cb.button_pressed
	var extras = _selected_extra_elements()
	if limit_on:
		var parts: Array = ["前20号"]
		for s in extras:
			parts.append(str(s))
		on.append("元素限制 " + "/".join(parts))

	var entry = _ui._start_child("SupplementaryHelpBtn")
	if entry:
		if on.is_empty():
			entry.text = "补充规则 · 默认 ▸"
		else:
			entry.text = "补充规则 · %d 项已开启 ▸" % on.size()

	var sum_label = _ui._start_child("SuppRulesSummary")
	if sum_label:
		if on.is_empty():
			sum_label.text = "全部为默认：29 种元素 · 182 张牌 · 无特殊规则"
		else:
			sum_label.text = "已启用：" + " · ".join(on)

	if _ui._supp_element_stats:
		var syms = _ui.CardDatabaseScript.get_allowed_symbols(limit_on, extras)
		var kinds: int = syms.size() if not syms.is_empty() else _ui.CardDatabaseScript.get_element_data().size()
		var extra_txt := "额外元素：无" if extras.is_empty() else "额外元素：" + "/".join(extras)
		_ui._supp_element_stats.text = "%d 种 · %d 张 ｜ %s" % [
			kinds, _ui.CardDatabaseScript.get_deck_size(syms), extra_txt]

	# 未开限制时元素池只是「预选」：压暗提示尚未生效（仍可点，点了会自动开限制）
	for sym in _ui._supp_element_chips.keys():
		var chip = _ui._supp_element_chips[sym]
		if is_instance_valid(chip):
			chip.modulate.a = 1.0 if limit_on else 0.55


func _selected_extra_elements() -> Array:
	var out: Array = []
	for info in _ui.CardDatabaseScript.get_optional_elements():
		var sym := str(info["symbol"])
		var chip = _ui._supp_element_chips.get(sym)
		if chip == null or not is_instance_valid(chip):
			chip = _ui._start_child("ElementChip_" + sym)
		if chip and chip.button_pressed:
			out.append(sym)
	return out


func _open_supp_rules() -> void:
	if _ui._supp_rules_page == null or not is_instance_valid(_ui._supp_rules_page):
		return
	_sync_supp_rules_summary()
	_ui._supp_rules_page.visible = true


func _close_supp_rules() -> void:
	if _ui._supp_rules_page and is_instance_valid(_ui._supp_rules_page):
		_ui._supp_rules_page.visible = false
