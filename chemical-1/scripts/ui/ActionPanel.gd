# ============================================================
# scripts/ui/ActionPanel.gd
# 底部操作面板（出牌步骤流按钮）+ 按钮工厂 `_mkb` + 缩放接线 +
# 面板几何唯一出口 `_fit_action_panel`。
# 状态（action_panel / step_mode / selected_indices / _ap_refit_left）留在 root。
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 3，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 3333-3587 行 --------
func _update_action_panel() -> void:
	if not _ui.action_panel or not _ui.game_manager: return
	# 热座交接未认领前不给任何操作按钮：否则可以绕过遮罩直接点「跳过 / 出牌」
	if _ui._hotseat_handoff_pending():
		_ap_clear()
		_fit_action_panel()
		return
	# 联机（Step 3，D1/D6）：非我回合 / 已提交待裁决 / 观战 / 待选牌型
	#   → 只给一句等待提示，一个按钮都不给（客人绝不能替别人「点」出牌）
	if _ui.net_session != null:
		var wait_text = _ui._net_wait_text()
		if wait_text != "":
			# 同一句等待文案（每帧都会走到这里）就不重建那个 Label
			if not _ap_single_label_is(wait_text):
				_ap_clear()
				_ui.action_panel.add_child(_ui._mk_wait_label(wait_text))
			_fit_action_panel()
			return
	var cp = _ui.game_manager.get_current_player()
	if cp == null or cp.is_ai or _ui.game_manager.is_game_over():
		_ap_clear()
		_fit_action_panel()
		return

	# 化合价面板由 HandView._update_valence_buttons() 自建（每选一个价就是另一批
	# 按钮 + Label，且自带清空），这里只把它当成「不可复用的那一批」。
	if _ui.step_mode == 2:
		_ui._update_valence_buttons()
		_fit_action_panel()
		return

	# 先算清单，再决定「复用还是重建」——清单即这一帧的期望内容。
	var plan: Array = _ap_build_plan(cp)
	if not _ap_apply_plan(plan):
		_ap_clear()
		for item in plan:
			_ui.action_panel.add_child(_mkb(item["text"], item["cb"], item["dis"]))
	_fit_action_panel()


# 这一帧该有哪些按钮（文案 / 回调 / 禁用态）。
# 之所以不边算边 add_child：只有先有清单，才能判断「和上一帧是不是同一批」。
func _ap_build_plan(cp) -> Array:
	var plan: Array = []
	if _ui.step_mode == 0:
		# 先出后验（P14-C）：选好牌 → 点「直接出牌 ⚡」，引擎按固定优先级自己挑牌型
		# （有机物 → 单质 → 化合物 → 顺序 → 族炸），第一个合法候选才落子。
		# 老的三步流程（出牌(选牌型) → 单质/化合物/顺序/族炸）原样保留，
		# 教程文案（TutorialController 里的「出牌(选牌型)」）不用改。
		plan.append(_ap_item("直接出牌 ⚡", _ui._on_auto_play, _ui.selected_indices.is_empty()))
		plan.append(_ap_item("出牌(选牌型)", _ui._on_step_next, _ui.selected_indices.is_empty()))
		var hand_limit = _ui.game_manager.get_hand_limit()
		if cp.get_hand_count() >= hand_limit:
			plan.append(_ap_item("弃牌跳过(上限)", _ui._on_pass, false))
		else:
			plan.append(_ap_item("跳过", _ui._on_pass, false))
	elif _ui.step_mode == 1:
		var in_chain: bool = _ui.game_manager.is_clan_bomb_chain_active() \
				and _ui.game_manager.get_current_player_index() != _ui.game_manager.get_clan_bomb_owner()
		if in_chain:
			# 接炸链中：冷却期间同样不能出族炸，只能跳过（见 GAMEPLAY_RULES「族炸冷却」）
			if cp.clan_bomb_cooling:
				if cp.get_hand_count() >= _ui.game_manager.get_hand_limit():
					plan.append(_ap_item("弃牌跳过(上限)", _ui._on_pass, false))
				else:
					plan.append(_ap_item("跳过(❄冷却中不能接炸)", _ui._on_pass, false))
			else:
				plan.append(_ap_item("作为族炸打出", _ui._on_clan_bomb, false))
			plan.append(_ap_item("返回", _ui._on_back, false))
		else:
			plan.append(_ap_item("作为单质打出", _ui._on_element, false))
			plan.append(_ap_item("合成化合物", _on_choose_compound, false))
			if _ui.game_manager.get_sequence_rules_enabled():
				plan.append(_ap_item("作为顺序打出", _ui._on_sequence, false))
			# 冷却 / 禁炸时按钮保留但要置灰，避免「点了才报错」
			if cp.clan_bomb_cooling:
				plan.append(_ap_item("族炸❄冷却中", _ui._on_clan_bomb, true))
			elif _ui.game_manager.clan_bomb_disabled:
				plan.append(_ap_item("族炸已禁用", _ui._on_clan_bomb, true))
			else:
				plan.append(_ap_item("作为族炸打出", _ui._on_clan_bomb, false))
			plan.append(_ap_item("返回", _ui._on_back, false))
	elif _ui.step_mode == 3:
		plan.append(_ap_item("确认弃置", _ui._on_pass, _ui.selected_indices.size() != 1))
		plan.append(_ap_item("取消", _ui._on_back, false))
	return plan


# 一条清单项：文案 / 回调 / 禁用态 —— 三者全同才算「同一批按钮」。
func _ap_item(text: String, cb: Callable, dis: bool) -> Dictionary:
	return {"text": text, "cb": cb, "dis": dis}


# 复用：清单与现有子节点一一对应（同文案 / 同回调）时，只就地翻 disabled，绝不销毁节点。
# 为什么值得做：AI 每次行动、每张牌选中都会走 _update_action_panel()，
# 重建一次是 n 个 Button + 4n 个 StyleBoxFlat + n 次信号接线 + n 个 pivot/resized 回调；
# 而绝大多数情况下按钮文案完全没变（只有 disabled 翻一下，或者根本什么都没变）。
func _ap_apply_plan(plan: Array) -> bool:
	if plan.is_empty():
		return false
	var live: Array = []
	for c in _ui.action_panel.get_children():
		# 同一帧里可能还挂着上一批「已 queue_free 待删」的子节点：跳过即可
		# （它们本帧末就消失，_action_panel_rows() 也按同一口径跳过）
		if c.is_queued_for_deletion():
			continue
		if not c.visible:
			return false
		live.append(c)
	if live.size() != plan.size():
		return false
	for i in range(plan.size()):
		if not (live[i] is Button):
			return false
		var btn: Button = live[i]
		if btn.text != String(plan[i]["text"]):
			return false
		# 回调对不上也必须重建：否则点下去执行的是上一批的动作
		if not _ap_btn_bound_to(btn, plan[i]["cb"]):
			return false
	for i in range(plan.size()):
		var btn: Button = live[i]
		var dis: bool = bool(plan[i]["dis"])
		if btn.disabled != dis:
			btn.disabled = dis
	return true


# 按钮当前连的 pressed 回调是不是这一条（Callable 按「对象 + 方法」比较）
func _ap_btn_bound_to(btn: Button, cb: Callable) -> bool:
	for conn in btn.pressed.get_connections():
		if conn["callable"] == cb:
			return true
	return false


# 联机等待文字：面板上已经只有这一条同样的 Label 就不用重建
func _ap_single_label_is(text: String) -> bool:
	var live: Array = []
	for c in _ui.action_panel.get_children():
		if c.is_queued_for_deletion():
			continue
		live.append(c)
	if live.size() != 1:
		return false
	return live[0] is Label and (live[0] as Label).text == text


# 清空面板：只 queue_free（同帧内新按钮照常加在旧的后面，行数计算会跳过待删节点）
func _ap_clear() -> void:
	for child in _ui.action_panel.get_children():
		if not child.is_queued_for_deletion():
			child.queue_free()



# 面板行高：桌面 45，触屏 48（TOUCH_BTN_MIN_H，≈32dp；旧值 58 会让下沿出血 9px）
func _action_btn_h() -> float:
	return float(_ui._touch_btn_h(_ui.ACTION_PANEL_BTN_H))


# 面板「贴底 + 向上折行」的唯一几何出口。
# 顺序：宽度先定 → 数行数（必要时收窄）→ 高度 = 行数×行高 + (行数-1)×行距 → 整块贴到 BOTTOM。
# 之所以自己数行而不等容器排序：FlowContainer 的 sort 是 deferred 的，同一帧里读 size 还是旧值；
# 这里按同一套换行规则（累加最小宽 + h_separation，超宽换行）先算出来，测试就能同步断言。
func _fit_action_panel() -> void:
	if _ui.action_panel == null or not is_instance_valid(_ui.action_panel):
		return
	var want_h = _action_panel_h()
	_ui.action_panel.size = Vector2(_ui.ACTION_PANEL_W, want_h)
	# 贴底用「实际尺寸」而不是 want_h：Container 的最小高度是缓存值（FlowContainer 的最小高度
	# 取决于当前宽度），刚换掉一整批按钮时本帧还会夹在旧内容的高度上 —— 照样贴住 644，绝不出血。
	_ui.action_panel.position = Vector2(_ui.ACTION_PANEL_LEFT, _ui.ACTION_PANEL_BOTTOM - _ui.action_panel.size.y)
	_ui.action_panel.queue_sort()
	# 被夹住就等一帧缓存刷新后再算一次（重试有上限，不会死循环）
	if not is_equal_approx(_ui.action_panel.size.y, want_h) and _ui._ap_refit_left > 0:
		_ui._ap_refit_left -= 1
		_fit_action_panel.call_deferred()
	else:
		_ui._ap_refit_left = _ui.ACTION_PANEL_REFIT_TRIES


# 面板高度：行数 × 行高 + (行数-1) × 行距；行数超上限先收窄按钮再算
func _action_panel_h() -> float:
	var rows = _action_panel_rows()
	if rows > _ui.ACTION_PANEL_MAX_ROWS:
		# 极端局面（4 种元素 × 多价）：把按钮收窄，让面板不超过 3 行，
		# 否则上沿会盖住 CardInfoLabel（478~526）甚至手牌。
		# 注意 Button 的最小宽 = max(custom_minimum_size, 文字宽)，短文本（"Cl (+7)"）才收得动。
		for c in _ui.action_panel.get_children():
			if c is Button and not c.is_queued_for_deletion():
				c.custom_minimum_size = Vector2(_ui.ACTION_PANEL_BTN_W_NARROW, c.custom_minimum_size.y)
		rows = _action_panel_rows()
	var v_sep := float(_ui.action_panel.get_theme_constant("v_separation"))
	return _action_btn_h() * float(rows) + v_sep * float(maxi(rows - 1, 0))


# 折行行数：与 FlowContainer::_resort 同一套规则（累加最小宽 + h_separation，放不下就换行）。
# 必须跳过 queue_free() 掉的旧子节点 —— _update_action_panel 先 queue_free 再加新按钮，
# 同一帧里新旧同时在树上，不跳过行数会算成两倍。
func _action_panel_rows() -> int:
	var sep := float(_ui.action_panel.get_theme_constant("h_separation"))
	var rows := 1
	var row_w := 0.0
	for c in _ui.action_panel.get_children():
		if not (c is Control) or c.is_queued_for_deletion() or not c.visible:
			continue
		var cw: float = (c as Control).get_combined_minimum_size().x
		if row_w > 0.0 and row_w + sep + cw > _ui.ACTION_PANEL_W:
			rows += 1
			row_w = cw
		else:
			row_w = cw if row_w <= 0.0 else row_w + sep + cw
	return rows


# 1 行面板的设计矩形：教程第零关「出牌区」高亮框用它（触屏 48 高 → 顶边上移 3px）
func _action_panel_hl_rect() -> Rect2:
	var h = _action_btn_h()
	return Rect2(Vector2(_ui.ACTION_PANEL_LEFT, _ui.ACTION_PANEL_BOTTOM - h), Vector2(_ui.ACTION_PANEL_W, h))


# 教程第零关「其他细节（右面板）」的高亮矩形：右栏几何由 _layout_log_panel() / _layout_rule_tips()
# 决定（折叠、日志条数、规则提醒是否占用都会变），所以读节点实况再外扩 4px。
# 老实现写死 (750,10) 400×350 —— 框住的是状态栏下方一整片空白，日志面板反而只有下半截在框里。
func _right_panel_hl_rect() -> Rect2:
	var node: Control = null
	if _ui.level0_rule_tip_bg != null and is_instance_valid(_ui.level0_rule_tip_bg) and _ui.level0_rule_tip_bg.visible:
		node = _ui.level0_rule_tip_bg
	elif _ui._log_panel != null and is_instance_valid(_ui._log_panel) and _ui._log_panel.visible:
		node = _ui._log_panel
	if node == null or node.size.x <= 0.0:
		# 兜底（正常时序到不了：_ensure_log_panel() 在 _ready 里就建好了）：设计位置 + 折叠态高度
		var home: Vector2 = Vector2(824, 300)
		if _ui.log_label != null and is_instance_valid(_ui.log_label):
			home = _ui.log_label.get_meta("home", home)
		return Rect2(Vector2(home.x, home.y - _ui.LOG_PANEL_PAD),
				Vector2(_ui.LOG_W + _ui.LOG_PANEL_PAD, _ui.LOG_PANEL_PAD * 2.0 + _ui.LOG_TITLE_H))
	var pad: float = float(_ui.RIGHT_PANEL_HL_PAD)
	return Rect2(node.position - Vector2(pad, pad), node.size + Vector2(pad, pad) * 2.0)


func _mkb(text: String, cb: Callable, dis: bool) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(_ui.ACTION_PANEL_BTN_W, _action_btn_h())   # 触屏 48 高 ≈ 32dp（旧 58 会出血）
	b.add_theme_font_size_override("font_size", _ui._touch_fs(16, 2))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.disabled = dis

	# 深蓝灰圆角按钮样式（P2：统一由 _make_panel_style("button") 产出）
	var style_normal = _ui._make_panel_style("button")
	b.add_theme_stylebox_override("normal", style_normal)

	# 悬停：背景变亮 + 主题蓝发光（P3 · 美术文档 §5.4「悬停时亮色发光」）
	# StyleBoxFlat 的 shadow 是背景外扩绘制，配合半透明亮蓝即可当光晕用
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	style_hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	style_hover.shadow_color = Color(0.35, 0.55, 0.85, 0.55)
	style_hover.shadow_size = 6
	style_hover.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("hover", style_hover)

	# 按下：略暗
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	b.add_theme_stylebox_override("pressed", style_pressed)

	# 禁用：半透明
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.173, 0.243, 0.314, 0.35)
	b.add_theme_stylebox_override("disabled", style_disabled)

	# 缩放交互（P3 · 美术文档 §7.4）：pivot 居中，悬停 1.05 / 按下 0.96
	# 与游戏页工具按钮共用同一套接线（见 _attach_btn_motion）
	_attach_btn_motion(b)

	b.pressed.connect(cb)
	return b


# -------- 缩放交互接线（P3）：pivot 居中 + 悬停 1.05 / 按下 0.96 --------
# 缩放只向外扩，不会把指针挤出原边界，因此 entered/exited 不会自激抖动。
# pivot 取值有讲究：_mkb 生成的按钮此刻还没进容器（size=0），直接读 size 会得到 0，
# 缩放就会绕着左上角甩 → 用 custom_minimum_size 兜底；工具按钮来自 Main.tscn，
# 进树前已有 size，直接用 size。两者随后都由 resized 校正到 size*0.5。
func _attach_btn_motion(b: Button) -> void:
	# 幂等：_mkb / _style_game_tool_buttons / _style_tool_btn 都可能被重复调用
	# （重排、切档、测试），重复 connect 会刷一串 "already connected" ERROR，
	# 并在 resized 上挂多个相同 lambda
	if b.has_meta("btn_motion_attached"):
		return
	b.set_meta("btn_motion_attached", true)
	b.pivot_offset = (b.size if b.size != Vector2.ZERO else b.custom_minimum_size) * 0.5
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	# 触屏档不接 hover：Android 把「最后一次触摸位置」当成鼠标位置，
	# mouse_entered 之后永远等不到 mouse_exited → 按钮会一直停在 1.05 倍。
	# 触控语义改成「按下 0.96、松手回 1.0」，见 _on_button_press_scale。
	if not _ui._touch_ui:
		b.mouse_entered.connect(_ui._on_button_hover_scale.bind(b, true))
		b.mouse_exited.connect(_ui._on_button_hover_scale.bind(b, false))
	b.button_down.connect(_ui._on_button_press_scale.bind(b, true))
	b.button_up.connect(_ui._on_button_press_scale.bind(b, false))


# -------- 按钮缩放补间（P3）：每个按钮只保留一个 tween --------
func _tween_button_scale(btn: Button, target: float) -> void:
	if not is_instance_valid(btn):
		return
	var tw = btn.get_meta("btn_scale_tween", false)
	if tw is Tween and tw.is_valid():
		tw.kill()
	tw = _ui.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2.ONE * target, _ui.BUTTON_SCALE_MS / 1000.0)
	btn.set_meta("btn_scale_tween", tw)


func _on_button_hover_scale(btn: Button, entered: bool) -> void:
	if not is_instance_valid(btn) or btn.disabled:
		return
	_tween_button_scale(btn, _ui.BUTTON_HOVER_SCALE if entered else 1.0)


func _on_button_press_scale(btn: Button, down: bool) -> void:
	if not is_instance_valid(btn) or btn.disabled:
		return
	if down:
		_tween_button_scale(btn, _ui.BUTTON_PRESS_SCALE)
	else:
		# 松开后指针通常仍在按钮内（说明还悬停着），回到悬停尺寸；
		# 触屏档没有悬停语义，一律回 1.0，否则 is_hovered() 恒真 → 按钮永远放大
		_tween_button_scale(btn, 1.0 if _ui._touch_ui or not btn.is_hovered() else _ui.BUTTON_HOVER_SCALE)


# ============================================================
# 九之一、触屏档取值函数（A1+B+C）
# ============================================================
# 为什么是函数而不是常量：本文件所有几何 const 都带自动化断言（tests/verify_*.gd），
# 直接改常量会把 24 套测试的期望值全部打翻。这里把「桌面值」和「触屏值」分成两层：
#   const ...         桌面基准（测试读它）
#   _xxx() -> float   运行时取值（触屏档换成放大后的值）
# 调用点因此全部改用函数，桌面下返回值与常量逐值相等。


# -------- 搬运自 scripts/GameUI.gd 第 3811-3960 行 --------
func _on_choose_compound() -> void:
	var cp = _ui._view_player()
	var cards: Array = _ui._sel_cards()
	var symbols: Array = []
	for card in cards:
		var s = card.symbol
		if s not in symbols: symbols.append(s)
	if symbols.size() < 2:
		_ui._show_info("化合物至少需要两种不同元素！")
		_ui._on_back()
		return
	# 卤族互化：默认禁止（硬规则）；开始页勾选「允许卤族互化」后放行。
	# 引擎侧 play_cards() 同样会拦（返回 -7），这里只是提前给出更友好的提示。
	if not _ui.game_manager.get_halogen_exchange_allowed() and _ui._is_halogen_only(symbols):
		_ui._show_info("卤族元素(F/Cl/Br/I)之间不可互相化合！请加入金属或其他非金属元素，或在开始页勾选『允许卤族互化』。")
		_ui._on_back()
		return

	# 自动识别有机物：选中牌组若实际为有机物（甲醛/甲醇/乙醇/甲酸/乙酸/烷烃等），
	# 直接按有机物打出（跳过化合价选择），有机物打出即获胜
	if _ui.CardPatternsScript.detect_pattern(cards, true) == _ui.CardPatternsScript.CardPattern.ORGANIC:
		var custom_valences = {"_organic": true}
		var result = _ui._router().play(cards, custom_valences, _ui.CardPatternsScript.CardPattern.ORGANIC)
		# 日志只在本端真落子时写（联机要等主机裁决，写早了就是假消息）
		if _ui.net_session == null:
			if result == 0:
				_ui.log_lines.push_back("🎉 %s 打出有机物，立即获胜！" % cp.player_name)
			else:
				_ui._show_info("有机物打出失败！")
		_ui._dispatch_result(result)
		return

	_ui.step_mode = 2
	_ui.compound_selections.clear()
	_update_action_panel()

func _on_choose_organic() -> void:
	var cp = _ui._view_player()
	var cards: Array = _ui._sel_cards()
	# 检查是否为有机物
	if _ui.CardPatternsScript.detect_pattern(cards, true) != _ui.CardPatternsScript.CardPattern.ORGANIC:
		_ui._show_info("不是有效有机物！有机物包括：甲烷CH4、乙烷C2H6、丙烷C3H8及他们的单一卤代物。\n卤代物只能包含一种卤族元素(F/Cl/Br)。")
		_ui._on_back()
		return
	# 打出有机物，标记 _organic 跳过族炸检测
	var custom_valences = {"_organic": true}
	var result = _ui._router().play(cards, custom_valences, _ui.CardPatternsScript.CardPattern.ORGANIC)
	if _ui.net_session != null:
		_ui._dispatch_result(result)
		return
	if result == 0:
		# 有机物打出成功
		_ui.log_lines.push_back("🎉 %s 打出有机物，立即获胜！" % cp.player_name)
		_ui._handle_result(result)
	else:
		_ui._show_info("有机物打出失败！")
		_ui._on_back()

func _on_select_valence(symbol: String, valence: int) -> void:
	for sel in _ui.compound_selections:
		if sel.symbol == symbol: return
	_ui.compound_selections.append({"symbol": symbol, "valence": valence})
	_update_action_panel()

func _on_confirm_compound() -> void:
	# 选中牌一次性拍快照（重排 / 抽牌后 selected_indices 可能已对不上，_sel_cards 内部按按钮 meta 兜底）
	var sel_cards: Array = _ui._sel_cards()

	var custom_valences: Dictionary = {}
	for sel in _ui.compound_selections:
		custom_valences[sel.symbol] = sel.valence

	var has_pos = false
	var has_neg = false
	for sel in _ui.compound_selections:
		if sel.valence > 0: has_pos = true
		elif sel.valence < 0: has_neg = true
	if not has_pos or not has_neg:
		_ui._show_info("需要正价和负价元素！")
		return

	var available: Dictionary = {}
	for card in sel_cards:
		available[card.symbol] = available.get(card.symbol, 0) + 1

	var valence_list: Array = []
	for sel in _ui.compound_selections:
		valence_list.append({
			"symbol": sel.symbol,
			"v": abs(sel.valence),
			"sign": -1 if sel.valence < 0 else 1,
			"avail": available.get(sel.symbol, 0)
		})

	if valence_list.size() == 2:
		var a = valence_list[0]
		var b = valence_list[1]
		if a.sign * b.sign > 0:
			_ui._show_info("需要一正一负两种价态！")
			return
		var g = _ui._gcd(a.v, b.v)
		var na = b.v / g
		var nb = a.v / g
		if a.avail < na or b.avail < nb:
			_ui._show_info("手牌不足！需 %s×%d + %s×%d" % [a.symbol, na, b.symbol, nb])
			return
		var ccards: Array = []
		for card in sel_cards:
			if card.symbol == a.symbol:
				var already = 0
				for cc in ccards:
					if cc.symbol == a.symbol: already += 1
				if already < na: ccards.append(card)
			elif card.symbol == b.symbol:
				var already = 0
				for cc in ccards:
					if cc.symbol == b.symbol: already += 1
				if already < nb: ccards.append(card)
		if ccards.size() != na + nb:
			_ui._show_info("收集卡牌出错！")
			return
		var result = _ui._router().play(ccards, custom_valences, _ui.CardPatternsScript.CardPattern.COMPOUND)
		_ui._dispatch_result(result)
		return

	# 3+ 元素化合物：总电荷 Σ = 0 即可（不再要求「每种恰好 1 张」）。
	# 引擎侧同口径（_search_valences 支持 2~3 元素、按张数加权），所以
	# H×2 + S + O×4 能直接出 H₂SO₄，H×2 + O×2 能出 H₂O₂，Ca + O×2 能出 CaO₂。
	# P14-B：失败提示要说清是哪一项不对 —— 真机截图里玩家选了 H,H,C,N，
	# 旧提示只说「仅支持 2 元素化合物」，完全不知道问题在哪。
	var total_charge = 0
	for e in valence_list:
		total_charge += e.sign * e.v * e.avail   # 按张数累加：2 张 H 就是 2 份价
	if total_charge == 0:
		var ccards: Array = sel_cards.duplicate()
		var result = _ui._router().play(ccards, custom_valences, _ui.CardPatternsScript.CardPattern.COMPOUND)
		_ui._dispatch_result(result)
		return

	# D22：配不平也可能「化学上说得通」（玩家故意选了一组引擎配不出来的价态组合）。
	# 联机时这一手有资格交给其他真人裁定；单机 claimable 恒 false，行为完全不变。
	# 必须先 claimable 再报错：否则玩家永远只能看到「配不平」的死路。
	if _ui._router().claimable(sel_cards, custom_valences, _ui.CardPatternsScript.CardPattern.COMPOUND):
		var claim_code: int = _ui._router().claim_compound(sel_cards, custom_valences)
		_ui._dispatch_result(claim_code)
		return

	# 逐项列出「价 × 张数」，玩家一眼能看出哪个元素多带了 / 少带了
	var parts: Array = []
	for e in valence_list:
		parts.append("%s%+d×%d" % [e.symbol, e.sign * e.v, e.avail])
	_ui._show_info("化合价配不平：%s → Σ = %+d（需 0）。\n正负价按张数相乘相加必须为 0，例如 H(−1)×2+C(+4)+N(−3)=0。" \
		% [" + ".join(parts), total_charge])

func _on_reset_valence() -> void:
	_ui.compound_selections.clear()
	_update_action_panel()
