extends SceneTree
# ============================================================
# tools/move_funcs.gd - 机械搬运工具（UI 层拆分专用）
#
# 为什么需要它：GDScript 没有 IDE 级 Move Method，而手抄 1000+ 行必然出错。
# 本工具做的事极其机械、可逐条核对：
#   1. 从源文件按「行区间」整段取出（含注释）写进目标模块
#   2. 段内所有「借用 root 的标识符」（字段 / 常量 / 方法）自动改写成 _ui.X
#      —— 只改 root 上真实存在的符号，且跳过局部变量 / 参数 / 字符串 / 注释 / x.name
#   3. 源文件原位替换成同名转发方法（参数与返回类型一律照抄，调用点零改动）
#
# 用法（Windows）：
#   godot --headless --path . --script tools/move_funcs.gd -- \
#     --from=scripts/GameUI.gd --to=scripts/ui/CardMotion.gd --field=ui_motion \
#     --title="ui/CardMotion.gd - 牌面动效" --range=3435-3619
#
# 约定（与 UI_LAYER_REFACTOR.md 铁律一致）：
#   · 状态留在 root：本工具**不会**把 var 搬走，只会把段内对它们的引用加 _ui. 前缀
#   · 不搬 static 函数（模块里没有 self/root，static 用不上 _ui）→ 直接报错中止
#   · 段内不得有单行签名跨行（多行参数）的函数 → 直接报错中止
# ============================================================

var _from_path := ""
var _to_path := ""
var _field := ""
var _title := ""
var _ranges: Array = []          # [[a, b], ...] 1-based 闭区间
var _slice := "2a"               # 仅用于生成注释/转发横幅文字（--slice=3）
var _also: Array = []            # 额外要加 _ui. 前缀的标识符（引擎实例方法）
var _append := false             # --append=1：往已存在的模块末尾追加（同一片分几次搬）
var _failed := false


func _init() -> void:
	_parse_args()
	if not _failed:
		_run()
	quit(1 if _failed else 0)


func _fail(msg: String) -> void:
	_failed = true
	printerr("[move_funcs] " + msg)


func _parse_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--from="):
			_from_path = a.substr(7)
		elif a.begins_with("--to="):
			_to_path = a.substr(5)
		elif a.begins_with("--field="):
			_field = a.substr(8)
		elif a.begins_with("--title="):
			_title = a.substr(8)
		elif a.begins_with("--range="):
			for part in a.substr(8).split(",", false):
				var se := part.split("-", false)
				if se.size() != 2:
					_fail("--range 格式应为 a-b：%s" % part)
					return
				_ranges.append([int(se[0]), int(se[1])])
		elif a.begins_with("--slice="):
			_slice = a.substr(8)
		elif a.begins_with("--append="):
			_append = a.substr(9) != "0"
		elif a.begins_with("--also="):
			# 额外要加 _ui. 前缀的标识符：引擎自带实例方法（create_tween / get_tree …）
			# 它们不是 root 的自定义符号，但同样只能经 root 调用
			_also.append_array(a.substr(7).split(",", false))
	if _title == "":
		_title = _to_path
	if _from_path == "" or _to_path == "" or _field == "" or _ranges.is_empty():
		_fail("缺少参数：--from --to --field --range 都是必填")


func _run() -> void:
	var src := _read_lines(_from_path)
	if src.is_empty():
		_fail("读不到源文件：%s" % _from_path)
		return
	var symbols := _collect_symbols(src)
	symbols.append_array(_also)
	var blocks: Array = []
	# 倒序处理：替换过的高行号区间不会影响尚未处理的行号
	var ordered: Array = _ranges.duplicate()
	ordered.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
	for rg in ordered:
		var a := int(rg[0])
		var b := int(rg[1])
		if a < 1 or b > src.size() or a > b:
			_fail("区间越界：%d-%d（文件共 %d 行）" % [a, b, src.size()])
			return
		var block: Array = src.slice(a - 1, b)
		var funcs: Array = _scan_funcs(block, a)
		if funcs.is_empty():
			_fail("区间 %d-%d 内没有 func 定义" % [a, b])
			return
		for f in funcs:
			if bool(f["is_static"]):
				_fail("不能搬 static 函数：%s（模块里没有 root 可用）" % String(f["name"]))
				return
		var moved := _transform(block, funcs, symbols)
		blocks.append({"a": a, "b": b, "lines": moved, "funcs": funcs})
		var fwd: Array = ["# -------- 以下方法已搬进 %s（Slice %s 纯搬运，这里只留同名转发） --------" % [_to_path, _slice]]
		for f in funcs:
			fwd.append_array(_forwarder(f))
		src = _splice(src, a - 1, b, fwd)
	# 按行号正序拼接模块，便于阅读
	blocks.sort_custom(func(x, y): return int(x["a"]) < int(y["a"]))
	_write_module(blocks)
	_write_lines(_from_path, src)
	var names: Array = []
	for blk in blocks:
		for f in blk["funcs"]:
			names.append(String(f["name"]))
	print("[move_funcs] %d 个函数已搬运：%s" % [names.size(), ", ".join(names)])
	print("[move_funcs] 模块：%s（root 字段名 %s）" % [_to_path, _field])


func _read_lines(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		out.append(f.get_line())
	f.close()
	# get_line 到 EOF 会多取一个空行
	if out.size() > 0 and String(out[out.size() - 1]) == "":
		out.remove_at(out.size() - 1)
	return out


func _write_lines(path: String, lines: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("写不了文件：%s" % path)
		return
	for i in lines.size():
		f.store_string(String(lines[i]))
		if i < lines.size() - 1:
			f.store_string("\n")
	f.close()


# from_idx: 0-based 起点；to_idx: 1-based 开区间终点（旧区间末尾的下一个下标）
func _splice(lines: Array, from_idx: int, to_idx: int, repl: Array) -> Array:
	var out: Array = []
	out.append_array(lines.slice(0, from_idx))
	out.append_array(repl)
	out.append_array(lines.slice(to_idx))
	return out


# 源文件里所有「能从模块经 _ui 访问到」的符号：常量 / 字段 / 方法
func _collect_symbols(lines: Array) -> Array:
	var out: Array = []
	for ln in lines:
		var s := String(ln)
		var body := ""
		if s.begins_with("const "):
			body = s.substr(6)
		elif s.begins_with("@onready var "):
			body = s.substr(13)
		elif s.begins_with("var "):
			body = s.substr(4)
		else:
			continue
		var name := _decl_name(body)
		if name != "":
			out.append(name)
	# 方法名单独扫一遍（先扫字段再扫方法，避免 var/func 混在一起的顺序问题）
	for ln in lines:
		var s := String(ln)
		if s.begins_with("func "):
			var sig := s.substr(5).strip_edges()
			var p := sig.find("(")
			if p > 0:
				out.append(sig.substr(0, p).strip_edges())
	return out


# 扫描块内的 func 定义（块内首列为 func 的行）
func _scan_funcs(block: Array, base_line: int) -> Array:
	var out: Array = []
	for i in block.size():
		var s := String(block[i])
		if not s.begins_with("func "):
			continue
		var sig := s.substr(5).strip_edges()
		var open := sig.find("(")
		var close := -1 if open < 0 else sig.rfind(")")
		if open < 0 or close < open:
			_fail("第 %d 行签名跨行或不合法（本工具只支持单行签名）：%s" % [base_line + i, s])
			return []
		var rest := sig.substr(close + 1).strip_edges()
		var ret := ""
		if rest.begins_with("->"):
			ret = rest.substr(2).strip_edges().trim_suffix(":").strip_edges()
		out.append({
			"name": sig.substr(0, open).strip_edges(),
			"args": sig.substr(open + 1, close - open - 1),
			"ret": ret,
			"is_static": sig.begins_with("static "),
			"line": base_line + i,
		})
	return out


# "foo: int = 1" / "foo := 1" / "foo = preload(...)" → "foo"
func _decl_name(body: String) -> String:
	var s := body.strip_edges()
	var name := ""
	for ch_i in s.length():
		var ch := s[ch_i]
		if ch == ":" or ch == "=" or ch == " ":
			break
		name += ch
	if name == "" or not name.is_valid_identifier():
		return ""
	return name


# 段内所有「借用 root 的标识符」加 _ui. 前缀；局部变量/参数/字符串/注释一律不动
func _transform(block: Array, _funcs: Array, symbols: Array) -> Array:
	var spans: Array = []
	for i in block.size():
		var s := String(block[i])
		if s.begins_with("func "):
			var sig := s.substr(5).strip_edges()
			spans.append({"start": i, "end": block.size() - 1, "sig": sig})
	for i in range(spans.size() - 1, 0, -1):
		spans[i - 1]["end"] = int(spans[i]["start"]) - 1
	for sp in spans:
		var locals := {}
		_collect_decls(String(block[int(sp["start"])]), locals)   # 参数
		for j in range(int(sp["start"]), int(sp["end"]) + 1):
			_collect_decls(_mask(String(block[j])), locals)
		sp["locals"] = locals
	var out: Array = []
	for i in block.size():
		var line := String(block[i])
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with("#"):
			out.append(line)
			continue
		if stripped.begins_with("func"):
			# 参数默认值里可能引用 root 常量（跨脚本 const 在默认值里不可用，见 Slice 1 教训）
			# → 模块签名一律去掉默认值，默认值继续由 root 的同名转发方法承担
			out.append(_module_header(line) if line.begins_with("func ") else line)
			continue
		var locals := {}
		for sp in spans:
			if i >= int(sp["start"]) and i <= int(sp["end"]):
				locals = sp["locals"]
				break
		out.append(_prefix_symbols(line, symbols, locals))
	return out


func _prefix_symbols(line: String, symbols: Array, locals: Dictionary) -> String:
	var masked := _mask(line)
	var hits: Array = []
	for sym in symbols:
		var name := String(sym)
		if locals.has(name):
			continue
		var re := RegEx.create_from_string("\\b" + name + "\\b")
		for m in re.search_all(masked):
			var p := m.get_start()
			if p > 0:
				var prev := masked[p - 1]
				if prev == "." or _is_word_char(prev) or prev == "$" or prev == "@":
					continue
			hits.append(p)
	if hits.is_empty():
		return line
	hits.sort()
	var res := line
	var last := -1
	for k in range(hits.size() - 1, -1, -1):
		var p := int(hits[k])
		if p == last:
			continue
		last = p
		res = res.substr(0, p) + "_ui." + res.substr(p)
	# := 只能从静态类型推断，而 _ui.x 是动态值 → 一律退回无类型声明（Slice 1 教训）
	if res.contains(":= _ui."):
		res = res.replace(":= _ui.", "= _ui.")
	return res


func _collect_decls(masked: String, dict: Dictionary) -> void:
	for pat in ["\\bvar\\s+([A-Za-z_]\\w*)", "\\bfor\\s+([A-Za-z_]\\w*)\\s+in\\b"]:
		var re := RegEx.create_from_string(pat)
		for m in re.search_all(masked):
			dict[m.get_string(1)] = true
	var lre := RegEx.create_from_string("\\bfunc\\s*\\(([^)]*)\\)")
	for m in lre.search_all(masked):
		for part in m.get_string(1).split(",", false):
			var nm := String(part).split(":", true, 1)[0].split("=", true, 1)[0].strip_edges()
			if nm != "" and nm.is_valid_identifier():
				dict[nm] = true


# 字符串内容与 # 之后的内容替换成 x（长度不变，便于按偏移回填原行）
func _mask(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote != "":
			if ch == "\\":
				out += "xx"
				i += 2
				continue
			if ch == quote:
				quote = ""
				out += ch
			else:
				out += "x"
			i += 1
			continue
		if ch == "\"" or ch == "'":
			quote = ch
			out += ch
			i += 1
			continue
		if ch == "#":
			out += "x".repeat(line.length() - i)
			break
		out += ch
		i += 1
	return out


# "func f(a: int, b: float = CARD_W) -> void:" → "func f(a: int, b: float) -> void:"
func _module_header(header_line: String) -> String:
	var indent := header_line.substr(0, header_line.find("func "))
	var sig := header_line.substr(header_line.find("func ") + 5)
	var open := sig.find("(")
	var close := sig.rfind(")")
	if open < 0 or close < open:
		return header_line
	return "%sfunc %s(%s)%s" % [indent, sig.substr(0, open),
		_strip_defaults(sig.substr(open + 1, close - open - 1)), sig.substr(close + 1)]


# 去掉顶层参数默认值（括号/引号内的逗号不算分隔符）
func _strip_defaults(args_txt: String) -> String:
	var out := ""
	var depth := 0
	var quote := ""
	var skipping := false
	var i := 0
	while i < args_txt.length():
		var ch := args_txt[i]
		if quote != "":
			if ch == "\\":
				if not skipping:
					out += ch + args_txt[i + 1]
				i += 2
				continue
			if ch == quote:
				quote = ""
			if not skipping:
				out += ch
			i += 1
			continue
		if ch == "\"" or ch == "'":
			quote = ch
			if not skipping:
				out += ch
			i += 1
			continue
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
		elif not skipping and depth == 0 and ch == "=":
			skipping = true
			while out.ends_with(" "):
				out = out.substr(0, out.length() - 1)
			i += 1
			continue
		elif skipping and depth == 0 and ch == ",":
			skipping = false
			out += ch
			i += 1
			continue
		if not skipping:
			out += ch
		i += 1
	# 末尾参数的默认值被剪掉后可能存在悬空逗号
	while out.strip_edges().ends_with(","):
		out = out.strip_edges().trim_suffix(",")
	return out


func _is_word_char(ch: String) -> bool:
	if ch == "_":
		return true
	var c := ch.unicode_at(0)
	return (c >= 48 and c <= 57) or (c >= 97 and c <= 122) \
		or (c >= 65 and c <= 90) or c > 127


func _forwarder(f: Dictionary) -> Array:
	var name := String(f["name"])
	var args_txt := String(f["args"])
	var ret := String(f["ret"])
	var call_args: Array = []
	for part in args_txt.split(",", false):
		var p := String(part).strip_edges()
		if p == "":
			continue
		call_args.append(p.split(":", true, 1)[0].split("=", true, 1)[0].strip_edges())
	var sig := "func %s(%s)" % [name, args_txt]
	if ret != "":
		sig += " -> " + ret
	sig += ":"
	var out: Array = [sig]
	if ret == "void":
		out.append("\t%s.%s(%s)" % [_field, name, ", ".join(call_args)])
	else:
		out.append("\treturn %s.%s(%s)" % [_field, name, ", ".join(call_args)])
	out.append("")
	return out


func _write_module(blocks: Array) -> void:
	var out: Array = []
	if _append:
		# 同一片的第二批函数：保留已有内容，只在末尾追加，避免覆盖前一批
		out = _read_lines(_to_path)
		if out.is_empty():
			_fail("--append 需要已存在的模块：%s" % _to_path)
			return
	else:
		out.append("# ============================================================")
		out.append("# " + _title)
		out.append("#")
		out.append("# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice %s，纯搬运）。" % _slice)
		out.append("# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。")
		out.append("# ============================================================")
		out.append("extends RefCounted")
		out.append("")
		out.append("var _ui = null")
		out.append("")
		out.append("")
		out.append("func _init(ui) -> void:")
		out.append("\t_ui = ui")
	for blk in blocks:
		out.append("")
		out.append("")
		out.append("# -------- 搬运自 scripts/GameUI.gd 第 %d-%d 行 --------" % [int(blk["a"]), int(blk["b"])])
		out.append_array(blk["lines"])
	out.append("")
	_write_lines(_to_path, out)


