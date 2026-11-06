# 验证触屏 UI 开关（P14-D）：开始页可随时切触控档，且**可逆**
#   1) 设置卡里有「触屏界面」开关，桌面启动默认关
#   2) 打开 → 工具行 48 / 顶 542、开始页按钮 48、手牌字号 +2、操作面板 48
#   3) 重复打开不会叠加（字号只 +2 一次）
#   4) 关掉 → 逐颗还原成桌面档（工具行 32 / 顶 558、按钮高度与字号回到原值、手牌字号回 21）
#   5) 直接点开关（button_pressed）与 set_touch_ui() 等价
# 运行：Godot --headless --path . -s tests/verify_touch_toggle.gd
extends SceneTree

const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")

var fails: int = 0
var total: int = 0


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	total += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


# 造一张 Na 卡读符号字号：卡面所有字号都走 _touch_fs()，触控档 +2。
# 自己造卡而不是读 hand_buttons —— AI 回合会换牌，读到的可能是另一张。
func _make_card_symbol_fs(scene) -> int:
	var card = null
	for e in CardDatabaseScript.get_element_data():
		if e[0] == "Na":
			card = CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
			break
	if card == null:
		return 0
	var btn = scene.call("_build_card_button", card, 0)
	scene.hand_container.add_child(btn)
	var sym = btn.get_node_or_null("CardSymbol")
	var fs: int = sym.get_theme_font_size("font_size") if sym else 0
	btn.queue_free()
	return fs


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	# 统一从桌面档起步（本进程可能带 --touch-ui 启动）
	if scene.is_touch_ui():
		scene.set_touch_ui(false)
	for _w in range(2):
		await process_frame

	var tg = scene.start_page.get_node_or_null("SettingsCard/TouchUIToggle")
	_check(tg != null, "设置卡里有「触屏界面」开关")
	_check(not scene.is_touch_ui(), "默认是桌面档（--touch-ui / mobile 之外）")
	_check(tg != null and not tg.button_pressed, "开关初始未按下")
	_check(tg != null and String(tg.text).find("关") >= 0, "开关文案写明「关」（实际「%s」）" % (String(tg.text) if tg else ""))

	scene._init_game(4, 3)
	for _w in range(3):
		await process_frame

	var exit_btn = scene.start_page.get_node_or_null("ExitButton")
	var base_exit_h: float = exit_btn.size.y
	var base_exit_fs: int = exit_btn.get_theme_font_size("font_size")
	var base_hint_h: float = scene.hint_button.size.y
	var base_hint_y: float = scene.hint_button.position.y
	# 手牌字号：自己造一张卡测（不依赖 AI 回合里的手牌变化）
	var base_sym_fs: int = _make_card_symbol_fs(scene)
	_check(is_equal_approx(base_hint_h, scene.TOOL_BTN_H), "桌面档工具行高 = %d（实际 %.1f）" % [scene.TOOL_BTN_H, base_hint_h])

	# ---- 打开 ----
	scene.set_touch_ui(true)
	for _w in range(2):
		await process_frame
	_check(scene.is_touch_ui(), "set_touch_ui(true) 后进入触控档")
	_check(tg.button_pressed and String(tg.text).find("开") >= 0, "开关同步为「开」（实际「%s」）" % String(tg.text))
	_check(is_equal_approx(scene.hint_button.size.y, float(scene.TOUCH_TOOL_BTN_H)),
		"工具行高变 %d（实际 %.1f）" % [scene.TOUCH_TOOL_BTN_H, scene.hint_button.size.y])
	_check(is_equal_approx(scene.hint_button.position.y, float(scene.TOUCH_TOOL_BTN_TOP)),
		"工具行顶边变 %d（实际 %.1f）" % [scene.TOUCH_TOOL_BTN_TOP, scene.hint_button.position.y])
	_check(is_equal_approx(exit_btn.size.y, float(scene.TOUCH_BTN_MIN_H)),
		"开始页小按钮补到 %d 高（实际 %.1f）" % [scene.TOUCH_BTN_MIN_H, exit_btn.size.y])
	var touch_exit_fs: int = exit_btn.get_theme_font_size("font_size")
	_check(touch_exit_fs == base_exit_fs + scene.TOUCH_FS_BONUS,
		"按钮字号 +%d（%d → %d）" % [scene.TOUCH_FS_BONUS, base_exit_fs, touch_exit_fs])
	_check(is_equal_approx(scene._action_btn_h(), float(scene.TOUCH_BTN_MIN_H)),
		"操作面板按钮高 %d（实际 %.1f）" % [scene.TOUCH_BTN_MIN_H, scene._action_btn_h()])
	var touch_sym_fs: int = _make_card_symbol_fs(scene)
	_check(touch_sym_fs == scene._touch_fs(base_sym_fs, 4),
		"卡面符号字号放大（%d → %d，卡面单独 +4）" % [base_sym_fs, touch_sym_fs])

	# ---- 幂等：再点一次不会叠加 ----
	var fs_after_first: int = exit_btn.get_theme_font_size("font_size")
	scene.set_touch_ui(true)
	await process_frame
	_check(exit_btn.get_theme_font_size("font_size") == fs_after_first,
		"重复开启不叠加字号（仍 %d）" % fs_after_first)

	# ---- 关掉：必须逐颗还原 ----
	scene.set_touch_ui(false)
	for _w in range(2):
		await process_frame
	_check(not scene.is_touch_ui(), "set_touch_ui(false) 后回到桌面档")
	_check(not tg.button_pressed and String(tg.text).find("关") >= 0, "开关同步为「关」")
	_check(is_equal_approx(scene.hint_button.size.y, base_hint_h),
		"工具行高还原 %.1f（实际 %.1f）" % [base_hint_h, scene.hint_button.size.y])
	_check(is_equal_approx(scene.hint_button.position.y, base_hint_y),
		"工具行顶边还原 %.1f（实际 %.1f）" % [base_hint_y, scene.hint_button.position.y])
	_check(is_equal_approx(exit_btn.size.y, base_exit_h) and exit_btn.get_theme_font_size("font_size") == base_exit_fs,
		"开始页按钮尺寸 / 字号还原（%.1f@%d，实际 %.1f@%d）" % [
			base_exit_h, base_exit_fs, exit_btn.size.y, exit_btn.get_theme_font_size("font_size")])
	_check(is_equal_approx(scene._action_btn_h(), float(scene.ACTION_PANEL_BTN_H)),
		"操作面板按钮高还原 %d（实际 %.1f）" % [scene.ACTION_PANEL_BTN_H, scene._action_btn_h()])
	_check(_make_card_symbol_fs(scene) == base_sym_fs,
		"卡面符号字号还原 %d（实际 %d）" % [base_sym_fs, _make_card_symbol_fs(scene)])

	# ---- 直接点开关 = set_touch_ui() ----
	tg.button_pressed = true
	await process_frame
	_check(scene.is_touch_ui(), "点开关（button_pressed=true）进入触控档")
	_check(scene._touch_ui_manual, "手动切换有记录（_touch_ui_manual）")
	tg.button_pressed = false
	await process_frame
	_check(not scene.is_touch_ui(), "再点一下回到桌面档")

	if fails == 0:
		print("ALL TOUCH TOGGLE TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d TOUCH TOGGLE TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)
