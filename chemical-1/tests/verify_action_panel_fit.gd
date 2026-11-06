# 验证出牌区（ActionPanel）永远不出屏（A6-2：折行 + 触屏 48）
#   1) 面板本体：宽 1136（x 8..1144）、下沿贴 644、1 行高 45（触屏 48）
#   2) 内容超宽自动折行：2/6 个 → 1 行，7/10 个 → 2 行，21 个 → 收窄后仍 ≤3 行
#   3) 任意组合下每颗按钮的矩形都落在 1152×648 画布内
#      ← 这是老 bug 的直接反证：Cl + I 的第 10 颗按钮原本在 x≈1640（屏幕宽只有 1152）
#   4) 折行后按钮两两不重叠
#   5) 真实入口：开赛 2 颗按钮仍是 1 行、顶 599（与 P11 逐像素一致）；
#      Cl + I 的化合价面板 10 颗按钮 → 2 行，且「返回」真的够得着
# 运行：Godot --headless --path . -s tests/verify_action_panel_fit.gd
extends SceneTree

const CardDataScript = preload("res://scripts/CardData.gd")
const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")

const CANVAS := Vector2(1152.0, 648.0)

var fails: int = 0
var total: int = 0
var scene = null


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


func _noop() -> void:
	pass


func _card(sym: String):
	for e in CardDatabaseScript.get_element_data():
		if e[0] == sym:
			return CardDataScript.new(e[0], e[1], e[2], e[3], e[4], e[5],
				e[6], e[7], e[8], e[9].duplicate(), e[10], e[11], e[12])
	push_error("unknown symbol: " + sym)
	return null


func _run() -> void:
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._init_game(4, 3)
	for _w in range(3):
		await process_frame

	await _test_profile(false)
	await _test_profile(true)
	await _test_real_entries()

	if fails == 0:
		print("ALL ACTION PANEL FIT TESTS PASSED（%d 条）" % total)
	else:
		print("%d/%d ACTION PANEL FIT TESTS FAILED" % [fails, total])
	quit(1 if fails > 0 else 0)


# ---------------- 工具：重建面板内容 / 读几何 ----------------

# 清空并塞入 n 个真实 _mkb 按钮（宽 160 与线上一致，折行宽度才有意义）
func _fill(n: int) -> void:
	for c in scene.action_panel.get_children():
		scene.action_panel.remove_child(c)
		c.queue_free()
	for i in range(n):
		scene.action_panel.add_child(scene._mkb("Cl (+%d)" % i, Callable(self, "_noop"), false))
	scene._fit_action_panel()


# 面板里「活着」的子控件（queue_free 掉的旧按钮不算）
func _live_children() -> Array:
	var out: Array = []
	for c in scene.action_panel.get_children():
		if c is Control and not c.is_queued_for_deletion() and c.visible:
			out.append(c)
	return out


# 全局矩形：GamePage 铺满 1152×648 且位于原点，面板坐标 + 子节点坐标即为全局坐标
func _global_rects() -> Array:
	var out: Array = []
	for c in _live_children():
		out.append(Rect2(scene.action_panel.position + c.position, c.size))
	return out


func _rows() -> int:
	return scene._action_panel_rows()


# 1 行面板的顶边（贴底反推）
func _action_top_of(rows: int, row_h: float) -> float:
	return scene.ACTION_PANEL_BOTTOM - (row_h * float(rows) + 4.0 * float(maxi(rows - 1, 0)))


# 期望行数：160 宽一行 6 个；超过 3 行会收窄到 132 宽（一行 8 个）
func _expected_rows(n: int) -> int:
	var rows := int(ceil(float(n) / 6.0))
	if rows > scene.ACTION_PANEL_MAX_ROWS:
		rows = int(ceil(float(n) / 8.0))
	return rows


# ---------------- 1~4：两种档案下的折行几何 ----------------

func _test_profile(touch: bool) -> void:
	var tag := "触屏" if touch else "桌面"
	var row_h: float = 48.0 if touch else 45.0
	scene._touch_ui = touch
	# headless 下 GamePage 默认不可见 —— 不可见的 Container 不会排版（子节点会一直停在 0,0），
	# 想量真实按钮矩形必须先让它可见（真机上它本来就是可见的）
	scene.game_page.visible = true

	# ---- 面板本体 ----
	_fill(2)
	await process_frame
	await process_frame
	var p: Control = scene.action_panel
	_check(_approx(p.position.x, scene.ACTION_PANEL_LEFT),
		"%s：面板左界 %d" % [tag, scene.ACTION_PANEL_LEFT])
	_check(_approx(p.size.x, scene.ACTION_PANEL_W),
		"%s：面板宽 %d（老布局只有 460，2 个按钮就到头）" % [tag, scene.ACTION_PANEL_W])
	_check(_approx(p.position.y + p.size.y, scene.ACTION_PANEL_BOTTOM),
		"%s：面板下沿贴 %.0f（实际 %.0f）" % [tag, scene.ACTION_PANEL_BOTTOM, p.position.y + p.size.y])
	_check(_approx(p.size.y, row_h),
		"%s：2 个按钮 → 1 行 %.0f 高（实际 %.0f）" % [tag, row_h, p.size.y])
	_check(_approx(_action_top_of(1, row_h), p.position.y),
		"%s：1 行时顶边 = %.0f" % [tag, _action_top_of(1, row_h)])

	# ---- 折行：每个上限都验一遍（1136 宽 / 160 宽按钮 / 间距 4 → 一行 6 个） ----
	for n in [6, 7, 10, 21]:
		_fill(n)
		await process_frame
		await process_frame
		var rects := _global_rects()
		_check(rects.size() == n, "%s：%d 个按钮全部在面板里（实际 %d）" % [tag, n, rects.size()])

		var max_right := 0.0
		var max_bottom := 0.0
		var outside := 0
		for r in rects:
			max_right = maxf(max_right, r.position.x + r.size.x)
			max_bottom = maxf(max_bottom, r.position.y + r.size.y)
			if r.position.x < -0.01 or r.position.y < -0.01 \
					or r.position.x + r.size.x > CANVAS.x + 0.01 \
					or r.position.y + r.size.y > CANVAS.y + 0.01:
				outside += 1
		_check(outside == 0,
			"%s：%d 个按钮全部落在 %dx%d 画布内（越界 %d，最右 %.0f / 最下 %.0f）"
				% [tag, n, int(CANVAS.x), int(CANVAS.y), outside, max_right, max_bottom])

		# 折行后不许互相压住
		var overlaps := 0
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j]):
					overlaps += 1
		_check(overlaps == 0, "%s：%d 个按钮两两不重叠（重叠 %d 对）" % [tag, n, overlaps])

		var rows := _rows()
		var want_rows := _expected_rows(n)
		_check(rows == want_rows, "%s：%d 个按钮 → %d 行（实际 %d）" % [tag, n, want_rows, rows])
		# 自算行数必须与实际排版一致（否则「面板高度」就是错的）
		var ys := {}
		for r in rects:
			ys[snappedf(r.position.y, 0.5)] = true
		_check(ys.size() == rows,
			"%s：%d 个按钮实际排成 %d 行（自算 %d 行）" % [tag, n, ys.size(), rows])
		_check(_approx(p.size.y, float(rows) * row_h + 4.0 * float(maxi(rows - 1, 0))),
			"%s：面板高 = 行数×%.0f + 行距（实际 %.0f，%d 行）" % [tag, row_h, p.size.y, rows])
		_check(p.position.y + p.size.y <= scene.ACTION_PANEL_BOTTOM + 0.01,
			"%s：%d 个按钮时面板下沿不放宽（%.0f ≤ %.0f）"
				% [tag, n, p.position.y + p.size.y, scene.ACTION_PANEL_BOTTOM])


# ---------------- 5：真实入口 ----------------

func _test_real_entries() -> void:
	scene._touch_ui = false

	# 5.1 开赛后的「出牌 / 跳过」两颗按钮：仍是一行、顶 599（与 P11 逐像素一致）
	scene._init_game(4, 3)
	scene.game_page.visible = true
	for _w in range(3):
		await process_frame
	scene.step_mode = 0
	scene.selected_indices = []
	scene._update_action_panel()
	await process_frame
	var cnt := _live_children().size()
	_check(cnt >= 2, "开赛后操作面板至少 2 颗按钮（实际 %d）" % cnt)
	_check(_approx(scene.action_panel.size.y, 45.0),
		"开赛 2 颗按钮 → 1 行 45 高（实际 %.0f）" % scene.action_panel.size.y)
	_check(_approx(scene.action_panel.position.y, 599.0),
		"开赛后面板顶边仍是 599（老布局逐像素一致，实际 %.0f）" % scene.action_panel.position.y)
	var r0: Rect2 = _global_rects()[0]
	_check(r0.position.x + r0.size.x <= CANVAS.x, "开赛按钮不越右界（%.0f ≤ 1152）" % (r0.position.x + r0.size.x))

	# 5.2 真实化合价面板：Cl(5 价) + I(4 价) + 返回 = 10 颗 → 老布局最右 1640，现在 2 行
	var pl = scene.game_manager.get_current_player()
	pl.hand.clear()
	var n := 0
	for s in ["Cl", "I"]:
		var c = _card(s)
		c.uid = 900 + n
		pl.hand.append(c)
		n += 1
	scene.selected_indices = []
	scene.compound_selections.clear()
	scene.step_mode = 2
	scene._refresh_ui()
	await process_frame
	# 选牌必须在 _refresh_ui 之后：它会重建手牌按钮并清空选中
	scene.selected_indices.clear()
	for i in range(pl.hand.size()):
		scene.selected_indices.append(i)
	scene._update_action_panel()
	await process_frame
	await process_frame

	var texts: Array = []
	var has_back := false
	var max_r := 0.0
	for c in _live_children():
		max_r = maxf(max_r, scene.action_panel.position.x + c.position.x + c.size.x)
		if c is Button:
			texts.append(String(c.text))
			if String(c.text) == "返回":
				has_back = true
	_check(_live_children().size() >= 10,
		"Cl + I 列出 %d 个价态按钮（5 + 4 + 返回）" % _live_children().size())
	_check(max_r <= scene.ACTION_PANEL_RIGHT + 0.01,
		"Cl + I 最右按钮 %.0f ≤ %d（老布局是 1640，屏幕只有 1152）"
			% [max_r, int(scene.ACTION_PANEL_RIGHT)])
	_check(has_back, "「返回」按钮仍在面板里（%s）" % " ".join(texts))
	_check(_rows() == 2, "Cl + I → 2 行（实际 %d）" % _rows())
	_check(_approx(scene.action_panel.size.y, 45.0 * 2.0 + 4.0),
		"Cl + I 面板高 94（2 行 + 行距，实际 %.0f）" % scene.action_panel.size.y)
	_check(scene.action_panel.position.y >= 526.0,
		"2 行面板顶 %.0f 不压 CardInfoLabel（底 526）" % scene.action_panel.position.y)
