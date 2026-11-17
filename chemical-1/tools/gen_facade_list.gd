# ============================================================
# tools/gen_facade_list.gd - 抽取「测试对 UI 根节点反射调用」的方法清单
#   UI_LAYER_REFACTOR.md §5.3 的清单来源；每次拆分后重生成一次，防止手写漂移。
#   用法：godot --headless --path . --script tools/gen_facade_list.gd
#   输出：可直接粘进 tests/verify_ui_facade.gd 的 GDScript 数组字面量
# ============================================================
extends SceneTree

# 只认「接收者是节点」的 call：scene / ui / host / guest / uis[i] / actor / fake
const RECEIVERS := ["scene", "ui", "host", "guest", "actor", "fake", "s", "small"]

func _init() -> void:
	var re := RegEx.new()
	# .call("_name"  或  .call( "_name"
	re.compile("\\.[Cc]all\\(\\s*\"([A-Za-z_][A-Za-z0-9_]*)\"")
	var names := {}
	var dir := DirAccess.open("res://tests")
	if dir == null:
		printerr("无法打开 res://tests")
		quit(1)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("verify_") and f.ends_with(".gd"):
			var txt := FileAccess.get_file_as_string("res://tests/" + f)
			for line in txt.split("\n"):
				# 只保留以已知接收者开头的行（排除 cond.call() / Callable 变量）
				var keep := false
				for r in RECEIVERS:
					if line.find(r + ".call(") >= 0 or line.find(r + ".call (") >= 0:
						keep = true
						break
				if not keep:
					continue
				for m in re.search_all(line):
					var n := m.get_string(1)
					if n.begins_with("_"):
						names[n] = true
		f = dir.get_next()
	dir.list_dir_end()

	var sorted_names: Array = names.keys()
	sorted_names.sort()
	print("# ---- 自动生成：%d 个私有方法（tools/gen_facade_list.gd）----" % sorted_names.size())
	var line := "\t"
	for n in sorted_names:
		var piece := "\"%s\", " % n
		if line.length() + piece.length() > 96:
			print(line.strip_edges())
			line = "\t"
		line += piece
	if line.strip_edges() != "":
		print(line.strip_edges())
	print("# ---- 结束 ----")
	quit(0)
