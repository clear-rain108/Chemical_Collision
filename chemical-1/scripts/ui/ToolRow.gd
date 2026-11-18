# ============================================================
# scripts/ui/ToolRow.gd
# 游戏页工具行：「显示提示 / 帮助 / 退出游戏」三颗按钮的样式接管 + 几何归一。
# 几何常量（TOOL_BTN_* / REORDER_BTN_W / TOOL_ROW_HL_*）留在 root ——
# 测试直读 scene.TOOL_BTN_TOP 等，且 TouchMetrics 也读同一份。
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 3，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 4221-4315 行 --------
func _style_game_tool_buttons() -> void:
	if _ui.hint_button == null or _ui.help_btn == null or _ui.quit_button == null:
		return
	# 几何归一：等高、同基线、等间距，右边界固定 → 三颗按钮不会再「各自为政」
	# 触屏档：高 48、间距 20、顶边 542（_tool_btn_*() 取运行时值，const 仍是桌面基准）
	var row: Array = [
		[_ui.hint_button, _ui.TOOL_BTN_W_HINT, true, false],
		[_ui.help_btn, _ui.TOOL_BTN_W_HELP, false, false],
		[_ui.quit_button, _ui.TOOL_BTN_W_QUIT, false, true],
	]
	# 先刷样式（含字号）再定几何：字号会改变按钮的最小尺寸，若先设 size，
	# 它会被 clamp 到「旧字号」的 min —— 触屏档 48 切回桌面档时高度就僵在 ~40 回不到 32。
	for entry in row:
		_style_tool_btn(entry[0], entry[2], entry[3])
	var x: float = _ui._tool_row_left()
	var h: float = _ui._tool_btn_h()
	var top: float = _ui._tool_btn_top()
	for entry in row:
		var b: Button = entry[0]
		var w: int = entry[1]
		b.custom_minimum_size = Vector2(w, h)
		b.size = Vector2(w, h)
		b.position = Vector2(x, top)
		x += w + _ui._tool_btn_gap()


# 单颗工具按钮的四态样式（normal / hover / pressed / disabled / focus）
# is_toggle: toggle 按钮的 pressed 同时就是「ON」态 → 换成主题蓝实底
# danger:    半破坏性动作 → hover / pressed 走暖红
func _style_tool_btn(b: Button, is_toggle: bool, danger: bool) -> void:
	var normal = _ui._make_panel_style("button")
	b.add_theme_stylebox_override("normal", normal)

	# 悬停：提亮 + 主题蓝发光（参数与 _mkb 完全一致，见 P3「悬停时亮色发光」）
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	hover.shadow_color = Color(0.35, 0.55, 0.85, 0.55)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("hover", hover)

	# 按下：略暗（与 _mkb 同色）
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	b.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.173, 0.243, 0.314, 0.35)
	b.add_theme_stylebox_override("disabled", disabled)

	# 焦点框置空：否则键盘/点击后会出现默认主题的蓝框，跳出「白卡 + 深蓝灰按钮」的画风
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	b.add_theme_font_size_override("font_size", _ui._touch_fs(14, 4))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))

	if is_toggle:
		# 开启态（toggle ON）：主题蓝实底 + 深蓝边 + 蓝光晕
		var on_style = _ui._make_panel_style("button")
		on_style.bg_color = _ui.START_C_ACCENT
		on_style.border_color = _ui.START_C_ACCENT_DARK
		on_style.shadow_color = Color(0.176, 0.478, 0.702, 0.45)
		on_style.shadow_size = 6
		on_style.shadow_offset = Vector2.ZERO
		b.add_theme_stylebox_override("pressed", on_style)
		# 开启态 + 悬停：只把蓝色提亮一档，别退回深蓝灰，否则「按着 + 移入」会闪一下
		var on_hover := on_style.duplicate() as StyleBoxFlat
		on_hover.bg_color = _ui.START_C_ACCENT.lightened(0.12)
		on_hover.border_color = _ui.START_C_ACCENT
		on_hover.shadow_color = Color(0.176, 0.478, 0.702, 0.6)
		on_hover.shadow_size = 8
		b.add_theme_stylebox_override("hover_pressed", on_hover)

	if danger:
		# 「退出游戏」= 结束本局进结算页：悬停转暖红（BORDER_WARN 与警告 toast 同色）
		var danger_hover := normal.duplicate() as StyleBoxFlat
		danger_hover.bg_color = Color(1.0, 0.953, 0.925, 1.0)
		danger_hover.border_color = _ui.BORDER_WARN
		danger_hover.shadow_color = Color(0.906, 0.298, 0.235, 0.45)
		danger_hover.shadow_size = 6
		danger_hover.shadow_offset = Vector2.ZERO
		b.add_theme_stylebox_override("hover", danger_hover)
		b.add_theme_color_override("font_hover_color", _ui.BORDER_WARN)
		# 按下也走暖色：否则「悬停红 → 按下又变蓝灰」会割裂
		var danger_pressed := danger_hover.duplicate() as StyleBoxFlat
		danger_pressed.bg_color = Color(0.996, 0.902, 0.882, 1.0)
		b.add_theme_stylebox_override("pressed", danger_pressed)
		b.add_theme_color_override("font_pressed_color", _ui.BORDER_WARN)

	_ui._attach_btn_motion(b)
