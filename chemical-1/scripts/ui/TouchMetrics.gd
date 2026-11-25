# ============================================================
# ui/TouchMetrics.gd - 触屏档（Android / 移动端）几何与字号取值
#
# 从 GameUI.gd 搬来（Slice 1）：九之一 / 九之二 两节全部函数
#   resolve_touch_profile / touch_profile_args / _touch_fs / _touch_btn_h /
#   _tool_btn_h / _tool_btn_top / _tool_btn_gap / _tool_row_left /
#   _reorder_btn_left / _tool_row_hl_rect / _drag_arm_threshold /
#   _drag_threshold / _selected_lift / _apply_touch_sizing /
#   _revert_touch_sizing / is_touch_ui / set_touch_ui /
#   _apply_touch_profile_everywhere / _reposition_reorder_button /
#   _sync_touch_toggle / _on_touch_ui_toggled / _collect_buttons
#
# 铁律（沿用原注释）：
#   · 桌面基准 const 一个都不改（24 套 headless 测试直接读它们做断言）
#   · 触屏放大值一律走这些取值函数；_touch_ui=false 时返回值与常量逐值相等
#   · _touch_ui / _touch_ui_manual **留在 root**（触屏开关随时可拨），
#     本模块只读不缓存判定结果 —— 否则运行时拨开关（verify_touch_toggle）会失效
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# ============================================================
# 九之一、触屏档取值函数（A1+B+C）
# ============================================================
# 为什么是函数而不是常量：本文件所有几何 const 都带自动化断言（tests/verify_*.gd），
# 直接改常量会把 24 套测试的期望值全部打翻。这里把「桌面值」和「触屏值」分成两层：
#   const ...         桌面基准（测试读它）
#   _xxx() -> float   运行时取值（触屏档换成放大后的值）
# 调用点因此全部改用函数，桌面下返回值与常量逐值相等。
#
# 注：原签名是 `bonus: int = TOUCH_FS_BONUS`，搬出 root 后默认值不再是编译期常量，
# 故模块内要求显式传入；root 的转发方法保留原默认值，外部调用点零改动。
func _touch_fs(base: int, bonus: int) -> int:
	return base + bonus if _ui._touch_ui else base


func _touch_btn_h(base_h: int) -> int:
	return maxi(base_h, _ui.TOUCH_BTN_MIN_H) if _ui._touch_ui else base_h


func _tool_btn_h() -> float:
	return float(_ui.TOUCH_TOOL_BTN_H) if _ui._touch_ui else float(_ui.TOOL_BTN_H)


func _tool_btn_top() -> float:
	return float(_ui.TOUCH_TOOL_BTN_TOP) if _ui._touch_ui else float(_ui.TOOL_BTN_TOP)


func _tool_btn_gap() -> float:
	return float(_ui.TOUCH_TOOL_BTN_GAP) if _ui._touch_ui else float(_ui.TOOL_BTN_GAP)


# 工具行左边界：右边界固定 820，间距变宽 → 左边界自动左移（教程高亮框跟着走）
func _tool_row_left() -> float:
	return _ui.TOOL_BTN_RIGHT - (_ui.TOOL_BTN_W_HINT + _ui.TOOL_BTN_W_HELP + _ui.TOOL_BTN_W_QUIT) - _tool_btn_gap() * 2.0


func _reorder_btn_left() -> float:
	return _tool_row_left() - _tool_btn_gap() - _ui.REORDER_BTN_W


# 教程第零关「按钮区」高亮框：工具行 bbox 外扩 TOOL_ROW_HL_PAD
# （DESKTOP 时与 TOOL_ROW_HL_POS / TOOL_ROW_HL_SIZE 逐值相等，见 verify_touch_ui）
func _tool_row_hl_rect() -> Rect2:
	var pad := float(_ui.TOOL_ROW_HL_PAD)
	var left := _tool_row_left()
	return Rect2(
			Vector2(left - pad, _tool_btn_top() - pad),
			Vector2(_ui.TOOL_BTN_RIGHT - left + pad * 2.0, _tool_btn_h() + pad * 2.0))


# 起拖阈值：越过它就开始跟手（触屏 10px ≈7dp，桌面 6px）
# 触屏「起拖」与「确认重排」刻意分成两档：10px 起拖是为了手指一动牌就跟（消除 300ms 死区），
# 24px（_drag_threshold）才是松手时判定「真的换位」的门槛 —— 中间那 10~24px 松手会回退成点选。
func _drag_arm_threshold() -> float:
	return _ui.TOUCH_DRAG_ARM_MOVE if _ui._touch_ui else _ui.DRAG_THRESHOLD


# 确认阈值：鼠标 6px 就够，手指需要 24px 才算有意重排（<24px 视为点选，见 _finish_drag）
func _drag_threshold() -> float:
	return _ui.TOUCH_DRAG_THRESHOLD if _ui._touch_ui else _ui.DRAG_THRESHOLD


# 选中牌静止时相对 base_pos 的上浮量：触屏常驻上浮，桌面 0（悬停已足够表达）
func _selected_lift() -> float:
	return _ui.TOUCH_SELECT_LIFT if _ui._touch_ui else 0.0


# -------- 页面级触控放大：开始页 / 帮助页 / 结算页 / 教学页的按钮统一过一遍 --------
# 这些页面的按钮是代码生成的、尺寸由各调用点手写（220×56 / 150×38 / 270×32 ...），
# 逐个改调用点既啰嗦又容易漏；改为构建完成后统一兜底：
#   · 渲染高度 < TOUCH_BTN_MIN_H 的，拉到 48（位置按中心不变微调，不跳行）
#   · 字号 +TOUCH_FS_BONUS
# 容器内的按钮（PanelContainer / VBox）position 会被容器覆盖，改为靠 custom_minimum_size 生效。
func _apply_touch_sizing(root: Node) -> void:
	if not _ui._touch_ui or root == null:
		return
	for b in _collect_buttons(root):
		# 幂等：start_page 与补充规则小页是父子关系，会被递归扫两次；
		# 不打标记的话字号会 +2 +2 叠成 +4
		if b.has_meta("touch_sized"):
			continue
		# 记住原始几何 / 字号：P14-D 的开关可以随时关掉触控档，必须逐颗还原。
		# 只记第一次（开→关→开 反复切换时，原点始终是桌面档的值）。
		if not b.has_meta("touch_orig"):
			b.set_meta("touch_orig", {
				"size": b.size,
				"cms": b.custom_minimum_size,
				"pos": b.position,
				"fs": b.get_theme_font_size("font_size"),
			})
		b.set_meta("touch_sized", true)
		var old_h: float = b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y
		if old_h > 0.0 and old_h < float(_ui.TOUCH_BTN_MIN_H):
			var new_h: int = _ui.TOUCH_BTN_MIN_H
			b.custom_minimum_size = Vector2(b.custom_minimum_size.x, new_h)
			b.size = Vector2(b.size.x, new_h)
			b.position = Vector2(b.position.x, b.position.y - (new_h - old_h) * 0.5)
			b.pivot_offset = b.size * 0.5
		var fs: int = b.get_theme_font_size("font_size")
		if fs > 0:
			b.add_theme_font_size_override("font_size", fs + _ui.TOUCH_FS_BONUS)


# 还原：把 _apply_touch_sizing 改过的按钮逐颗恢复（size / 最小高 / 坐标 / 字号）。
# 为什么要还原而不是重建页面：这些按钮是代码生成的，位置写在各调用点，
# 重建一遍等于重跑 _setup_pages（会重连信号、重播入场动画），关个开关不该这么重。
func _revert_touch_sizing(root: Node) -> void:
	if root == null:
		return
	for b in _collect_buttons(root):
		if b.has_meta("touch_sized"):
			b.remove_meta("touch_sized")
		if not b.has_meta("touch_orig"):
			continue
		var orig: Dictionary = b.get_meta("touch_orig")
		b.remove_meta("touch_orig")
		# 顺序要紧：最小尺寸 → 字号 → size。
		# 反过来会被「当前」最小尺寸反复夹住（实测：先写 size 会停在 48，再停在 42 ——
		# 都是旧字号撑出来的最小高度，看着像没还原）。
		b.custom_minimum_size = orig["cms"]
		var fs: int = int(orig["fs"])
		if fs > 0:
			b.add_theme_font_size_override("font_size", fs)
		b.size = orig["size"]
		b.position = orig["pos"]
		b.pivot_offset = b.size * 0.5


# ============================================================
# 九之二、触屏档运行时开关（P14-D）
# ============================================================
# 为什么需要界面开关：--touch-ui 只在启动时生效，真机上玩家想「把按钮调大」只能改系统设置；
# 桌面上也总得开终端加参数。开始页「触屏界面」开关 = set_touch_ui()，
# 与命令行 / 平台判定共用同一个 _touch_ui 字段，几何取值函数自然跟着变。
func is_touch_ui() -> bool:
	return _ui._touch_ui


func set_touch_ui(on: bool) -> void:
	if on == _ui._touch_ui:
		_sync_touch_toggle()
		return
	_ui._touch_ui = on
	_ui._touch_ui_manual = true
	print("[UI] 触屏档案 = %s（开始页开关）" % str(on))
	_apply_touch_profile_everywhere()
	_sync_touch_toggle()


# 把当前档位刷到所有已构建的页面 + 游戏页（可逆：关掉时逐颗还原，不重建页面）
func _apply_touch_profile_everywhere() -> void:
	for p in [_ui.start_page, _ui.end_page, _ui.get_node_or_null("TutorialPage"), _ui.help_page, _ui._supp_rules_page, _ui._mode_page]:
		if p == null:
			continue
		if _ui._touch_ui:
			_apply_touch_sizing(p)
		else:
			_revert_touch_sizing(p)
	if _ui.game_page == null:
		return
	# 游戏页：工具行 / 按序按钮吃 _touch_btn_*() 几何，手牌与操作面板吃 _touch_fs()，
	# 都在下一次重建时取值 —— 这里主动触发一次重建。
	_ui._style_game_tool_buttons()
	_reposition_reorder_button()
	if _ui.game_manager != null and not _ui.game_manager.is_game_over():
		_ui._refresh_ui()


func _reposition_reorder_button() -> void:
	if not is_instance_valid(_ui._reorder_btn):
		return
	var h: float = _tool_btn_h()
	_ui._reorder_btn.custom_minimum_size = Vector2(_ui.REORDER_BTN_W, h)
	_ui._reorder_btn.size = Vector2(_ui.REORDER_BTN_W, h)
	_ui._reorder_btn.position = Vector2(_reorder_btn_left(), _tool_btn_top())
	_ui._reorder_btn.add_theme_font_size_override("font_size", _touch_fs(14, 4))


# 开始页开关的文字 / 按下态跟随 _touch_ui（命令行强制开启时也显示「开」）
func _sync_touch_toggle() -> void:
	var tg = _ui._start_child("TouchUIToggle")
	if tg == null:
		return
	if tg.button_pressed != _ui._touch_ui:
		# 不能用 button_pressed = _touch_ui：那会补发 toggled → 触发「已开启」提示 + 重复 set
		tg.set_pressed_no_signal(_ui._touch_ui)
	tg.text = "触屏界面 · 开" if _ui._touch_ui else "触屏界面 · 关"


func _on_touch_ui_toggled(pressed: bool) -> void:
	set_touch_ui(pressed)
	_ui._start_flash_rule_hint("触屏界面已开启（按钮更高、字号 +2）" if pressed else "触屏界面已关闭")


func _collect_buttons(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c.get_child_count() > 0:
			out.append_array(_collect_buttons(c))
	return out


# ============================================================
# 触屏档案判定（原 GameUI.gd 顶部 static 函数，纯函数）
# ============================================================
# --touch-ui  桌面 / CI 上强制打开触控档（自动化测试与截图都用它）
# --desktop-ui 真机上强制关掉 —— 排查「是不是触屏档导致的」时用
# 两者同时出现时**后写的那个赢**（与常见 CLI 习惯一致）。
# 纯函数（不读全局状态）：测试可以直接喂参数，不用真的重启进程。
static func resolve_touch_profile(is_mobile: bool, args: Array) -> bool:
	var profile := is_mobile
	for raw in args:
		var a := String(raw)
		if a == "--touch-ui":
			profile = true
		elif a == "--desktop-ui":
			profile = false
	return profile


# 当前进程的命令行参数：Godot 自带参数与「-- 之后的用户参数」都扫一遍，
# 于是 `godot --path . --touch-ui` 与 `godot --path . -- --touch-ui` 都能生效。
static func touch_profile_args() -> Array:
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	return args
