# 验证触屏档案的启动开关（A6-1）
#   1) `resolve_touch_profile(是否移动平台, 参数)` 的判定规则：命令行 > 平台，后者出现者赢
#   2) 当前进程的档案 = 本进程参数算出来的结果（--touch-ui 启动时整个游戏真的切到触控档）
#   3) 触控档下几何/手势取值真的换了（工具行 48、拖拽 24、选中上浮 10、按钮最小高 48）
#   4) 桌面档下这些值仍是 P11 基准（不会被新开关带歪）
# 运行（两种都跑一遍）：
#   Godot --headless --path . -s tests/verify_touch_flag.gd
#   Godot --headless --path . -s tests/verify_touch_flag.gd --touch-ui
extends SceneTree

const GameUIScript = preload("res://scripts/GameUI.gd")

var fails: int = 0
var total: int = 0
var _scene = null


func _init():
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	total += 1
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


func _run() -> void:
	_test_resolver()

	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame

	_test_live_profile()
	_test_geometry()

	if fails == 0:
		print("ALL TOUCH FLAG TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d TOUCH FLAG TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)


# ============================================================
# 一、纯函数：命令行 > 平台特性
# ============================================================
func _test_resolver() -> void:
	var R := GameUIScript.resolve_touch_profile
	_check(R.call(false, []) == false, "桌面 + 无参数 → 桌面档")
	_check(R.call(true, []) == true, "移动平台 + 无参数 → 触控档")
	_check(R.call(false, ["--touch-ui"]) == true, "--touch-ui 在桌面上也能开触控档")
	_check(R.call(true, ["--desktop-ui"]) == false, "--desktop-ui 在真机上能压回桌面档")
	_check(R.call(false, ["--touch-ui", "--desktop-ui"]) == false,
		"两个都给时后写的赢（touch → desktop = 桌面档）")
	_check(R.call(true, ["--desktop-ui", "--touch-ui"]) == true,
		"两个都给时后写的赢（desktop → touch = 触控档）")
	_check(R.call(false, ["--path", ".", "--touch-ui", "-s", "x.gd"]) == true,
		"夹在其它参数中间也认得（%s）" % str(GameUIScript.touch_profile_args()))
	_check(R.call(false, ["--touch_ui"]) == false, "拼错的参数（--touch_ui）不生效")
	_check(R.call(false, ["--touch-ui=1"]) == false, "带值的写法（--touch-ui=1）不生效（只认裸开关）")

	var args: Array = GameUIScript.touch_profile_args()
	_check(args is Array, "touch_profile_args() 返回数组（当前 %d 个参数）" % args.size())


# ============================================================
# 二、当前进程的档案：必须与本进程参数算出来的一致
# ============================================================
func _test_live_profile() -> void:
	var args: Array = GameUIScript.touch_profile_args()
	var expect: bool = GameUIScript.resolve_touch_profile(OS.has_feature("mobile"), args)
	_check(_scene._touch_ui == expect,
		"当前进程触屏档 = %s（参数 %s）" % [str(_scene._touch_ui), str(args)])

	var forced_on := "--touch-ui" in args
	_check(_scene._touch_ui == forced_on,
		"本进程%s触控档（--touch-ui %s）" % ["开了" if forced_on else "没开",
			"在参数里" if forced_on else "不在参数里"])


# ============================================================
# 三、几何 / 手势取值随档案切换
# ============================================================
func _test_geometry() -> void:
	var touch: bool = _scene._touch_ui

	var want_h: float = float(GameUIScript.TOUCH_TOOL_BTN_H if touch else GameUIScript.TOOL_BTN_H)
	_check(_approx(_scene._tool_btn_h(), want_h),
		"工具行高 = %.0f（触控档 = %s）" % [_scene._tool_btn_h(), str(touch)])

	var want_top: float = float(GameUIScript.TOUCH_TOOL_BTN_TOP if touch else GameUIScript.TOOL_BTN_TOP)
	_check(_approx(_scene._tool_btn_top(), want_top), "工具行顶 = %.0f" % _scene._tool_btn_top())

	var want_gap: float = float(GameUIScript.TOUCH_TOOL_BTN_GAP if touch else GameUIScript.TOOL_BTN_GAP)
	_check(_approx(_scene._tool_btn_gap(), want_gap), "工具行间距 = %.0f" % _scene._tool_btn_gap())

	var want_drag: float = GameUIScript.TOUCH_DRAG_THRESHOLD if touch else GameUIScript.DRAG_THRESHOLD
	_check(_approx(_scene._drag_threshold(), want_drag), "拖拽确认阈值 = %.0f" % _scene._drag_threshold())

	var want_lift: float = GameUIScript.TOUCH_SELECT_LIFT if touch else 0.0
	_check(_approx(_scene._selected_lift(), want_lift), "选中上浮 = %.0f" % _scene._selected_lift())

	# 临时切到另一档 → 取值必须跟着变（证明开关不是一次性的）
	_scene._touch_ui = not touch
	var flipped_h: float = _scene._tool_btn_h()
	var want_flipped: float = float(GameUIScript.TOOL_BTN_H if touch else GameUIScript.TOUCH_TOOL_BTN_H)
	_check(_approx(flipped_h, want_flipped), "临时切换档案后工具行高 = %.0f" % flipped_h)
	_scene._touch_ui = touch

	# 触控档下按钮最小高 = 48（≈32dp）；桌面档保持传入值
	_check(_approx(_scene._touch_btn_h(32),
		float(maxi(32, GameUIScript.TOUCH_BTN_MIN_H)) if touch else 32.0),
		"_touch_btn_h(32) = %.0f" % _scene._touch_btn_h(32))
