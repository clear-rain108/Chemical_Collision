# ============================================================
# tools/run_tests.gd - 测试运行器（UI_LAYER_REFACTOR.md §5.2）
#
# 为什么不用 .bat：cmd 要求批处理文件是 CRLF 换行，本仓库的文本文件是 LF，
# rem 注释行会被拆开执行、if errorlevel 判断会失效（已实测），
# 所以改成用 Godot 自己编排：OS.execute 逐个跑子进程，拿真实退出码。
#
# 用法：
#   全量：  godot --headless --path . --script tools/run_tests.gd
#   单套：  godot --headless --path . --script tools/run_tests.gd -- verify_hand_layout
#   多套：  godot --headless --path . --script tools/run_tests.gd -- verify_hand_layout verify_motion
#   全量耗时 ~100s，超过部分终端 30s 上限时用：
#           start /b <godot> ... > %TEMP%\cc_tests.log 2>&1   然后轮询日志
#
# 退出码：全部通过 0，否则 1
# ============================================================
extends SceneTree

func _init() -> void:
	var names := _collect()
	var only := OS.get_cmdline_user_args()
	if not only.is_empty():
		var picked: Array = []
		for o in only:
			var n := String(o)
			if n.ends_with(".gd"):
				n = n.substr(0, n.length() - 3)
			if not n.begins_with("verify_"):
				n = "verify_" + n
			picked.append(n)
		names = picked

	if names.is_empty():
		printerr("没找到任何 tests/verify_*.gd")
		quit(1)
		return

	var godot := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var ok: Array = []
	var bad: Array = []
	for name in names:
		var out: Array = []
		var code := OS.execute(godot,
			["--headless", "--path", proj, "--script", "tests/%s.gd" % name],
			out, true)
		var text: String = String(out[0]) if not out.is_empty() else ""
		var checks := 0
		var first_fail := ""
		for line in text.split("\n"):
			var l := line.strip_edges()
			if l.begins_with("PASS:"):
				checks += 1
			elif (l.begins_with("FAIL:") or l.begins_with("ABORT:")) and first_fail == "":
				first_fail = l
		if code == 0 and first_fail == "":
			print("PASS  %-32s (%d checks)" % [name, checks])
			ok.append(name)
		else:
			print("FAIL  %-32s exit=%d %s" % [name, code, first_fail])
			bad.append(name)

	print("")
	if bad.is_empty():
		print("RESULT: %d/%d PASSED" % [ok.size(), names.size()])
		quit(0)
	else:
		print("RESULT: %d failed / %d total -> %s" % [bad.size(), names.size(), str(bad)])
		quit(1)


func _collect() -> Array:
	var names: Array = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		return names
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("verify_") and f.ends_with(".gd"):
			names.append(f.substr(0, f.length() - 3))
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names
