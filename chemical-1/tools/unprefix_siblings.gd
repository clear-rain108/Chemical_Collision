extends SceneTree
# ============================================================
# tools/unprefix_siblings.gd - move_funcs 的配套修正（UI 层拆分专用）
#
# 为什么需要它：move_funcs.gd 会把段内所有「root 上存在的符号」加 _ui. 前缀，
# 其中也包含**本次刚搬进同一个模块**的兄弟方法。那样调用会走
#   模块 → _ui（root 转发方法）→ 模块
# 多一跳，而且一旦漏掉转发就会无限递归。本工具把这类前缀还原。
#
# 规则：
#   · 只处理「本文件里真实定义过的 func 名」
#   · 跳过带 .connect( 的行 —— 信号仍指向 root（UI_LAYER_REFACTOR.md §4.1）
#
# 用法（Windows）：
#   godot --headless --path . --script tools/unprefix_siblings.gd -- --path=scripts/ui/ActionPanel.gd
# ============================================================

var _path := ""


func _init() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--path="):
			_path = a.substr(7)
	if _path == "":
		printerr("[unprefix_siblings] 缺少参数 --path=")
		quit(1)
		return
	var lines := _read_lines(_path)
	if lines.is_empty():
		printerr("[unprefix_siblings] 读不到文件：%s" % _path)
		quit(1)
		return
	var names: Array = []
	for ln in lines:
		var s := String(ln)
		if s.begins_with("func "):
			var sig := s.substr(5).strip_edges()
			var p := sig.find("(")
			if p > 0:
				names.append(sig.substr(0, p).strip_edges())
	var total := 0
	var out: Array = []
	for ln in lines:
		var s := String(ln)
		if s.contains(".connect(") or names.is_empty():
			out.append(s)
			continue
		var before := s
		for nm in names:
			var name := String(nm)
			# 前一个字符不是标识符字符/点，后一个字符不是标识符字符
			var re := RegEx.create_from_string("(?<![\\w.])_ui\\." + name + "(?![\\w])")
			s = re.sub(s, name, true)
		if s != before:
			total += 1
		out.append(s)
	_write_lines(_path, out)
	print("[unprefix_siblings] %s：还原 %d 行" % [_path, total])
	quit(0)


func _read_lines(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		out.append(f.get_line())
	f.close()
	if out.size() > 0 and String(out[out.size() - 1]) == "":
		out.remove_at(out.size() - 1)
	return out


func _write_lines(path: String, lines: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[unprefix_siblings] 写不了文件：%s" % path)
		return
	for i in lines.size():
		f.store_string(String(lines[i]))
		if i < lines.size() - 1:
			f.store_string("\n")
	f.close()
