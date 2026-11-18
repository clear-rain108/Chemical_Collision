# ============================================================
# scripts/ui/SidePanels.gd
# 桌面迷你卡（72×90 小卡）/ 右栏日志底板与折叠标题条 / 「按序 ⇅」按钮 /
# 信息栏（CardInfoLabel）与牌库·教程标签。
# 状态（_log_* / _net_over_notice / _reorder_tip / log_lines …）全部留在 root。
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 3，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 3254-3375 行 --------
func _build_mini_card_button(card, custom_valence) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(72, 90)
	btn.tooltip_text = card.get_full_info()
	# 出牌飞入按「卡片对象」配对小卡（化合物会按化学式重排，下标对不上）
	btn.set_meta("card", card)

	var style_normal = _ui._make_panel_style("mini_card")
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("pressed", style_normal)

	var style_hover = _ui._make_panel_style("mini_card_hover")
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var l_num = Label.new()
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", 8)
	l_num.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	l_num.position = Vector2(3, 1)
	btn.add_child(l_num)

	var l_group = Label.new()
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", 8)
	l_group.add_theme_color_override("font_color", Color(0.32, 0.34, 0.38, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(32, 10)
	l_group.position = Vector2(37, 2)
	btn.add_child(l_group)

	var l_sym = Label.new()
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", 15)
	l_sym.add_theme_color_override("font_color", _ui._get_card_color(card))
	l_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sym.size = Vector2(65, 18)
	l_sym.position = Vector2(4, 18)
	btn.add_child(l_sym)

	var l_name = Label.new()
	l_name.text = card.name_cn
	l_name.add_theme_font_size_override("font_size", 9)
	l_name.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1))
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_name.size = Vector2(65, 12)
	l_name.position = Vector2(4, 38)
	btn.add_child(l_name)

	# 化合价显示：如果提供了自定义化合价就用它，否则显示常见化合价
	if custom_valence != null:
		# 单质/双原子分子显示 0，化合物显示实际氧化态
		var v = custom_valence
		var val_str = ""
		if v > 0: val_str = "+%d" % v
		elif v < 0: val_str = "%d" % v
		else: val_str = "0"
		var l_val = Label.new()
		l_val.text = val_str
		l_val.add_theme_font_size_override("font_size", 8)
		l_val.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2, 1))
		l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l_val.size = Vector2(65, 10)
		l_val.position = Vector2(4, 52)
		btn.add_child(l_val)

	var l_mass = Label.new()
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", 7)
	l_mass.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	l_mass.position = Vector2(2, 78)
	btn.add_child(l_mass)

	return btn


# ============================================================
# 八之三、手牌「按序 ⇅」按钮（P7）
# ============================================================
# 只在「玩家手动拖拽过 + 当前可操作」时出现，是手动排列模式唯一的出口。
# 位置 (338,558) = 工具行（显示提示 / 帮助 / 退出游戏）左侧同一基线：
# 手动排列模式下整行变成 [按序 ⇅][显示提示][帮助][退出游戏]，间距与高度完全一致；
# 上不压 CardInfoLabel（底边 526）、下不压 ActionPanel（顶边 599）。
func _build_hand_reorder_button() -> void:
	if not _ui.game_page or is_instance_valid(_ui._reorder_btn):
		return
	var b = _ui._mkb("按序 ⇅", _on_hand_reorder, false)
	b.name = "HandReorderBtn"
	b.custom_minimum_size = Vector2(_ui.REORDER_BTN_W, _ui._tool_btn_h())
	b.size = Vector2(_ui.REORDER_BTN_W, _ui._tool_btn_h())
	b.position = Vector2(_ui._reorder_btn_left(), _ui._tool_btn_top())
	b.add_theme_font_size_override("font_size", _ui._touch_fs(14, 4))
	b.tooltip_text = "按原子序数升序重新排列手牌（恢复自动排序）"
	b.visible = false
	_ui._layer(0).add_child(b)
	_ui._reorder_btn = b


func _update_hand_reorder_button() -> void:
	if not is_instance_valid(_ui._reorder_btn):
		return
	var cp = null
	if _ui.game_manager != null:
		cp = _ui.game_manager.get_current_player()
	# AI 回合 / 自动排列模式下没有「恢复自动排序」可言 → 直接隐藏
	_ui._reorder_btn.visible = cp != null and not cp.is_ai and cp.hand_manual_order and _ui._can_reorder_hand()


func _on_hand_reorder() -> void:
	if _ui.game_manager == null:
		return
	var cp = _ui.game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return
	_ui._cancel_drag()
	# force=true：只有这个显式入口能打断玩家排好的顺序，排完即退回自动模式
	cp.sort_hand_by_atomic_number(true)
	_ui._reorder_tip = "已按原子序数重新排列手牌"
	_ui._update_hand_buttons()
	_update_card_info_label()
	_update_hand_reorder_button()



# -------- 搬运自 scripts/GameUI.gd 第 3377-3493 行 --------
# -------- 右栏日志（A1 底板 + A4 可折叠标题条） --------
# 挂 GamePage 直接子节点（跟随页面显隐），插在 LogLabel 之前 —— 同级按树顺序绘制，
# 底板必须先画；mouse_filter = IGNORE 保证它不吃手牌 / 按钮的点击。
# 标题条是唯一新增的可点元素（折叠开关），也挂在 GamePage 上、紧跟底板。
func _ensure_log_panel() -> void:
	if _ui._log_panel != null and is_instance_valid(_ui._log_panel):
		return
	if _ui.log_label == null or not is_instance_valid(_ui.log_label):
		return
	var page = _ui.log_label.get_parent()
	if page == null:
		return
	# 记下 LogLabel 在 Main.tscn 里的设计位置：之后所有几何都从它推导，
	# 折叠只改 LogLabel 的 y / 高度，不会把自己的基准挪掉
	if not _ui.log_label.has_meta("home"):
		_ui.log_label.set_meta("home", _ui.log_label.position)
	var panel := Panel.new()
	panel.name = "LogPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _ui._make_panel_style("log_panel"))
	page.add_child(panel)
	page.move_child(panel, _ui.log_label.get_index())
	_ui._log_panel = panel

	var title = _ui._make_right_column_title("LogTitleBar", "游戏日志")
	title.pressed.connect(_ui._on_log_title_pressed)
	page.add_child(title)
	page.move_child(title, panel.get_index() + 1)
	_ui._log_title = title
	_layout_log_panel()


# 点标题条：折叠 / 展开。折叠状态跟着这个 GameUI 实例走（跨回合保留，不写存档）
func _on_log_title_pressed() -> void:
	_ui._log_collapsed = not _ui._log_collapsed
	_layout_log_panel()


# 右栏日志几何的唯一出口：底板 / 标题条 / 正文一起算，「折叠」与「展开」只差正文高度。
# 高度按「行数 × 行高」推（日志最多 MAX_LOG_LINES 行），不再写死 300px 让右栏空一大片。
func _layout_log_panel() -> void:
	if _ui.log_label == null or not is_instance_valid(_ui.log_label):
		return
	if _ui._log_panel == null or not is_instance_valid(_ui._log_panel):
		return
	if _ui._log_title == null or not is_instance_valid(_ui._log_title):
		return
	var home: Vector2 = _ui.log_label.get_meta("home", _ui.log_label.position)
	var panel_w: float = _ui.LOG_W + _ui.LOG_PANEL_PAD
	var body_w: float = panel_w - _ui.LOG_TEXT_PAD - _ui.LOG_PANEL_PAD
	var body_h: float = _ui.LOG_CONTENT_MIN_H
	if not _ui._log_collapsed:
		# 先把宽度定下来，autowrap 的 Label 才能量出真实换行高度（长行折行时不会被裁）
		_ui.log_label.size = Vector2(body_w, _ui.LOG_CONTENT_MAX_H)
		var rows: int = maxi(_ui.log_lines.size(), 1)
		var need: float = maxf(float(rows) * _log_line_h(), _ui.log_label.get_minimum_size().y)
		body_h = clampf(need, _ui.LOG_CONTENT_MIN_H, _ui.LOG_CONTENT_MAX_H)
	var panel_h: float = _ui.LOG_PANEL_PAD + _ui.LOG_TITLE_H + _ui.LOG_PANEL_PAD
	if not _ui._log_collapsed:
		panel_h += _ui.LOG_BODY_GAP + body_h
	# 左边缘 = 正文设计位置（原 814 的底板会压到退出按钮右边缘 820）
	_ui._log_panel.position = Vector2(home.x, home.y - _ui.LOG_PANEL_PAD)
	_ui._log_panel.size = Vector2(panel_w, panel_h)
	# 标题条是 GamePage 的子节点（紧跟底板以便画在上面），所以位置要加回底板原点
	_ui._log_title.position = Vector2(home.x, home.y)
	_ui._log_title.size = Vector2(panel_w, _ui.LOG_TITLE_H)
	_ui._log_title.text = _log_title_text()
	_ui.log_label.position = Vector2(home.x + _ui.LOG_TEXT_PAD, home.y + _ui.LOG_TITLE_H + _ui.LOG_BODY_GAP)
	_ui.log_label.size = Vector2(body_w, body_h)
	_ui.log_label.visible = _ui._log_visible and not _ui._log_collapsed


func _log_title_text() -> String:
	var arrow: String = "▸" if _ui._log_collapsed else "▾"
	var n: int = _ui.log_lines.size()
	if n <= 0:
		return "游戏日志 %s" % arrow
	return "游戏日志 · %d 条 %s" % [n, arrow]


# 单行日志的行高：中文字体 ascent+descent 再加 2px 呼吸，宁可多给 1~2px 也不裁字
func _log_line_h() -> float:
	var fs: int = _ui.log_label.get_theme_font_size("font_size")
	var font: Font = _ui.log_label.get_theme_font("font")
	return maxf(font.get_height(fs) + 2.0, float(fs) + 4.0)


# 日志区显隐的唯一出口：规则提醒占用右栏同一格时，日志 / 底板 / 标题条一起让位
func _set_log_visible(on: bool) -> void:
	_ensure_log_panel()
	_ui._log_visible = on
	if _ui.log_label and is_instance_valid(_ui.log_label):
		_ui.log_label.visible = on and not _ui._log_collapsed
	if _ui._log_panel and is_instance_valid(_ui._log_panel):
		_ui._log_panel.visible = on
	if _ui._log_title and is_instance_valid(_ui._log_title):
		_ui._log_title.visible = on


func _update_log_label() -> void:
	if not _ui.log_label or not _ui.game_manager: return
	var new_logs = _ui.game_manager.flush_logs()
	if new_logs.is_empty(): return
	for msg in new_logs:
		_ui.log_lines.push_back(msg)
		while _ui.log_lines.size() > _ui.MAX_LOG_LINES:
			_ui.log_lines.pop_front()
	_ui.log_label.text = "\n".join(_ui.log_lines)
	_layout_log_panel()


# 清掉「联机已终止」的常驻提示（D20 / D21）。
# 四个入口共用：回开始页 / 单机新局 / 联机开局 / 离开房间。
# 单独抽成函数是为了能直接验证「清干净」：提示文本还挂在 card_info_label 上，
# 下一局一进牌桌就会顶着上一局的告警。
func _clear_net_over_notice() -> void:
	_ui._net_over_notice = ""


# -------- 搬运自 scripts/GameUI.gd 第 3496-3576 行 --------
func _update_card_info_label() -> void:
	if not _ui.card_info_label or not _ui.game_manager: return
	# 联机终止（房主收房 / 失联 / 状态分叉）：这句优先于一切回合提示。
	# 不挡的话下一帧就被「等待 X 行动…」盖掉，原因只剩 toast 里闪 2.5 秒（D20）
	if _ui._net_over_notice != "":
		_ui.card_info_label.text = "⚠ " + _ui._net_over_notice
		return
	var pi: int = _ui.game_manager.get_current_player_index()
	var cp = _ui.game_manager.get_current_player()
	if cp == null:
		_ui.card_info_label.text = ""
		return
	# 联机（Step 3，D6）：视角与「可用牌型」都只按自己的座位算 ——
	# 用当前行动者的下标去查 get_available_patterns() 就是白送别人手牌情报。
	if _ui.net_session != null:
		if _ui.net_session.is_watcher():
			_ui.card_info_label.text = "观战中：不显示任何玩家的手牌"
			return
		cp = _ui._view_player()
		if cp == null:
			_ui.card_info_label.text = ""
			return
		if not _ui._net_can_operate():
			if _ui.action_router != null and _ui.action_router.awaiting_reply():
				_ui.card_info_label.text = "已提交，等待主机裁决…"
			else:
				var actor = _ui.game_manager.get_current_player()
				var who: String = actor.player_name if actor != null else "对手"
				_ui.card_info_label.text = "等待 %s 行动中… 现在不是你的回合，手牌仅供查看" % who
			return
		pi = int(_ui.net_session.my_seat)
	if cp.is_ai:
		# 手牌区此时显示玩家自己的牌（只读），这里说明在等谁，
		# 否则玩家会误以为界面卡住
		_ui.card_info_label.text = "等待 %s 行动中… 现在不是你的回合，手牌仅供查看" % cp.player_name
		return
	# 热座：手牌还盖着，先说清楚该把屏幕交给谁
	if _ui._hotseat_handoff_pending():
		_ui.card_info_label.text = "轮到 %s：请把屏幕交给 TA，自行点击上方按钮查看手牌" % cp.player_name
		return
	# 一次性提示（重排完成等）：只显示到下一次刷新，不占用提示按钮的状态
	if _ui._reorder_tip != "":
		_ui.card_info_label.text = _ui._reorder_tip
		_ui._reorder_tip = ""
		return
	# 提示（P6）：_apply_hint() 写入的建议优先于默认「可用牌型」，
	# 但局面一变（换人 / 手牌数变了 / 顺序被玩家重排）就作废，避免选中残留误导玩家
	if _ui._hint_text != "":
		if _ui._hint_owner == pi \
				and _ui._hint_hand_size == cp.hand.size() \
				and _ui._hint_order_sig == _ui._hand_order_sig(cp):
			_ui.card_info_label.text = _ui._hint_text
			return
		_ui._clear_hint()
	var hint = _ui.game_manager.get_available_patterns(pi)
	_ui.card_info_label.text = "提示: " + hint


func _update_deck_count() -> void:
	if not _ui.deck_count_label or not _ui.game_manager: return
	var db = _ui.game_manager.get_database()
	if db: _ui.deck_count_label.text = "牌库剩余: %d张" % db.get_remaining_count()
	else: _ui.deck_count_label.text = "牌库剩余: —"
	if _ui.game_manager:
		var hand_limit = _ui.game_manager.get_hand_limit()
		_ui.deck_count_label.text += "  手牌上限: %d张" % hand_limit


func _update_tutorial_label() -> void:
	if not _ui.tutorial_label or not _ui.game_manager: return
	if _ui.game_manager.tutorial_level > 0 or _ui.game_manager.tutorial_level0_phase >= 3:
		_ui.tutorial_label.visible = true
		if _ui.game_manager.tutorial_level == 0 and _ui.game_manager.tutorial_level0_phase == 3:
			_ui.tutorial_label.text = "【第零关】牌局练习 - 试试出牌！"
		else:
			var display = _ui.game_manager.get_tutorial_display()
			if _ui.game_manager.tutorial_success != "":
				_ui.game_manager.tutorial_success = ""
			_ui.tutorial_label.text = display
	else:
		_ui.tutorial_label.visible = false
