# ============================================================
# ui/VoteUI.gd - 化合物质疑投票遮罩（D22，仅联机）
#
# 谁来裁定「这一手化学上说不通」：单机是引擎一句话；联机交给**其他真人**投票。
# 本层只负责「把主机发来的投票快照画出来 + 两个按钮」，判定与收口全在
# NetSession（主机权威）与 VoteBox（纯逻辑）里 —— UI 绝不自作主张算票。
#
# 三条展示口径（与 VoteBox 的硬口径一一对应）：
#   · 分母 / 票型 / 剩余时间全部照抄快照：客人手里没有投票箱，永远只是镜像；
#   · 我不是投票人（出题人 / 观战 / AI 座位）就只显示「等待其他玩家裁定」，
#     两个按钮一律禁用 —— 别让人以为还能点；
#   · 已投就锁成「已投赞成 / 反对，等待其他玩家」，改票服务端也不生效。
#
# 遮罩挂 OverlayLayer（_layer(1)）：必须盖住手牌（手牌 z=20），并且
# mouse_filter = STOP —— 投票期间全场冻结（服务端另有 -111 兜底）。
# ============================================================
extends RefCounted

const PANEL_W := 640.0
const PANEL_H := 410.0

var _ui = null

# 遮罩与它里面的控件（每次开票重建，收口即销毁）
var _overlay: Control = null
var _cards_row: HBoxContainer = null
var _who: Label = null
var _reason: Label = null
var _tally: Label = null
var _timer: Label = null
var _hint: Label = null
var _yes: Button = null
var _no: Button = null


func _init(ui) -> void:
	_ui = ui


func is_open() -> bool:
	return _overlay != null and is_instance_valid(_overlay)


# ============================================================
# 一、信号入口（OnlineUI 把 vote_opened / vote_updated / vote_resolved 转过来）
# ============================================================
func on_vote_opened(state: Dictionary) -> void:
	_build()
	_render(state)
	# 全场冻结：操作面板 / 手牌立刻置灰（服务端也会用 -111 拒一切意图）
	_ui._update_action_panel()


func on_vote_updated(state: Dictionary) -> void:
	if not is_open():
		# 乱序 / 重连：先收到状态再收到开票，按开票处理，别让玩家看不到遮罩
		on_vote_opened(state)
		return
	_render(state)


func on_vote_resolved(result: Dictionary) -> void:
	hide_vote()
	_ui._show_info(_result_text(result))
	# 随后主机还会广播 authoritative 的 compound_ruling，
	# 那时 _online_on_state_applied 会再刷一次 —— 这里先刷是为了
	# 「结论一出，遮罩就得马上消失」，不能让玩家隔着半透明板看桌面。
	_ui._refresh_ui()


# 每帧一条：倒计时 + 「投票没了但遮罩还开着」的自愈
func tick(_delta: float) -> void:
	if not is_open():
		return
	var s = _ui.net_session
	if s == null or not s.has_method("vote_open") or not s.vote_open():
		hide_vote()
		return
	if _timer == null:
		return
	var ms: int = int(s.vote_remain_ms())
	_timer.text = "剩余 %d 秒（超时视为不通过）" % maxi(0, int(ceil(float(ms) / 1000.0)))


func hide_vote() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_cards_row = null
	_who = null
	_reason = null
	_tally = null
	_timer = null
	_hint = null
	_yes = null
	_no = null


# ============================================================
# 二、建 UI（只在开票那一刻建一次）
# ============================================================
func _build() -> void:
	if is_open():
		return
	var overlay := Control.new()
	overlay.name = "VoteOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# 半透明黑板：压暗牌桌，视线全落在面板上（同时吞掉所有点击）
	var bg := ColorRect.new()
	bg.name = "VoteScrim"
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	# 居中面板：四向居中锚点 + 半宽偏移 → 任何分辨率都居中，不写死窗口尺寸
	var panel := PanelContainer.new()
	panel.name = "VotePanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -PANEL_H * 0.5
	panel.offset_bottom = PANEL_H * 0.5
	panel.add_theme_stylebox_override("panel", _ui._make_panel_style("card"))
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	margin.add_child(col)

	var title := _label("⚖ 化合物质疑投票", _ui._touch_fs(22, 4), Color(0.82, 0.24, 0.18, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_who = _label("", _ui._touch_fs(15, 2), Color(0.25, 0.3, 0.38, 1.0))
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_who)

	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", 16)
	col.add_child(_cards_row)

	_reason = _label("", _ui._touch_fs(14, 2), Color(0.35, 0.35, 0.35, 1.0))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_reason)

	_tally = _label("", _ui._touch_fs(15, 2), Color(0.15, 0.42, 0.2, 1.0))
	_tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_tally)

	_timer = _label("", _ui._touch_fs(14, 2), Color(0.6, 0.35, 0.1, 1.0))
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_timer)

	_hint = _label("", _ui._touch_fs(13, 2), Color(0.4, 0.45, 0.52, 1.0))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(0, 44)
	col.add_child(_hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)

	_yes = _ui._mkb("赞成（化学上说得通）", func() -> void: _cast(true), false)
	_yes.name = "VoteYesButton"
	_yes.custom_minimum_size = Vector2(240, _ui._action_btn_h())
	row.add_child(_yes)

	_no = _ui._mkb("反对（维持原判）", func() -> void: _cast(false), false)
	_no.name = "VoteNoButton"
	_no.custom_minimum_size = Vector2(240, _ui._action_btn_h())
	row.add_child(_no)

	_ui._layer(1).add_child(overlay)
	_overlay = overlay


func _label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


# ============================================================
# 三、渲染（只读快照，不改任何状态）
# ============================================================
func _render(state: Dictionary) -> void:
	if not is_open():
		return
	_fill_cards(state)
	var by := int(state.get("by", -1))
	_who.text = "%s 提出：这一手在化学上说得通，请其他玩家裁定" % _seat_name(by)
	_reason.text = "引擎判定：" + String(state.get("reason", ""))
	var total := int(state.get("total", 0))
	var approve := int(state.get("approve_count", 0))
	var reject := int(state.get("reject_count", 0))
	_tally.text = "赞成 %d · 反对 %d · 分母 %d 人%s" % [
		approve, reject, total, _pending_text(state)]
	var s = _ui.net_session
	var voter: bool = s != null and s.am_i_voter()
	var my: int = int(s.my_vote()) if s != null else -1
	if _yes != null:
		_yes.disabled = (not voter) or my != -1
	if _no != null:
		_no.disabled = (not voter) or my != -1
	if not voter:
		_hint.text = "你不在这次投票的名单里（出题人 / 观战者 / AI 座位不参与裁定），等待其他玩家…"
	elif my == 1:
		_hint.text = "你已投赞成，等待其他玩家…"
	elif my == 0:
		_hint.text = "你已投反对，等待其他玩家…"
	else:
		_hint.text = "其他玩家全票赞成 → 这一手成立并落子；有任何一人反对 / 超时 → 出牌撤销 + 罚抽 1 张"


# 未投名单（快照里只给 voters 与 votes，两个一减就是「还在等的」）
func _pending_text(state: Dictionary) -> String:
	var voters = state.get("voters", [])
	var votes = state.get("votes", {})
	if not (voters is Array) or not (votes is Dictionary):
		return ""
	var names: Array = []
	for seat in voters:
		if not (votes as Dictionary).has(int(seat)):
			names.append(_seat_name(int(seat)))
	if names.is_empty():
		return ""
	return "，待投：" + "、".join(names)


func _seat_name(seat: int) -> String:
	var s = _ui.net_session
	if s != null:
		var nm := String(s.seat_name(int(seat)))
		if nm != "":
			return nm
	if _ui.game_manager != null:
		var players = _ui.game_manager.get_players()
		if int(seat) >= 0 and int(seat) < players.size():
			var p = players[int(seat)]
			if p != null and String(p.player_name) != "":
				return String(p.player_name)
	return "座位 %d" % (int(seat) + 1)


# 待裁定的那一手：能查到牌就按元素配色画大字，查不到（降级）就只画价态里的符号
func _fill_cards(state: Dictionary) -> void:
	if _cards_row == null:
		return
	for child in _cards_row.get_children():
		child.queue_free()
	var claim = state.get("claim", {})
	if not (claim is Dictionary):
		return
	var by := int(state.get("by", -1))
	var uids = claim.get("uids", [])
	var vals = claim.get("valences", {})
	var vals_dict: Dictionary = vals if vals is Dictionary else {}
	var cards: Array = []
	if _ui.game_manager != null and uids is Array and not (uids as Array).is_empty():
		cards = _ui.game_manager.get_cards_by_uids(by, uids)
	if cards.is_empty():
		for sym in vals_dict.keys():
			_cards_row.add_child(_tile(String(sym), vals_dict[sym], null))
		return
	for c in cards:
		_cards_row.add_child(_tile(String(c.symbol), vals_dict.get(c.symbol, ""), c))


func _tile(sym: String, valence, card) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var lab := Label.new()
	lab.text = sym
	lab.add_theme_font_size_override("font_size", _ui._touch_fs(30, 4))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if card != null:
		lab.add_theme_color_override("font_color", _ui._get_card_color(card))
	box.add_child(lab)
	var vt := _valence_text(valence)
	if vt != "":
		var v := Label.new()
		v.text = vt
		v.add_theme_font_size_override("font_size", _ui._touch_fs(13, 2))
		v.add_theme_color_override("font_color", Color(0.75, 0.2, 0.2, 1.0))
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(v)
	return box


# 快照里的 valences 是 symbol → int（玩家在面板上选的 +3 / −2 这种）；查不到就留空
func _valence_text(valence) -> String:
	if valence is int:
		var v := int(valence)
		if v == 0:
			return "0"
		return "+%d" % v if v > 0 else "%d" % v
	if valence is float:
		return "%+d" % int(valence)
	return ""


# ============================================================
# 四、投票 / 结论
# ============================================================
func _cast(approve: bool) -> void:
	var s = _ui.net_session
	if s == null:
		return
	var code: int = int(s.cast_vote(approve))
	if code == 0:
		# 本地立刻反馈（主机还会广播 vote_state 回来，这里只求「点了有反应」）
		if _yes != null:
			_yes.disabled = true
		if _no != null:
			_no.disabled = true
		if _hint != null:
			_hint.text = "你已投%s，等待其他玩家…" % ("赞成" if approve else "反对")
		return
	_ui._show_info("投票失败：" + _ui.ActionRouterScript.describe_code(code))


# 结论文案：通过 / 反对 / 超时 / 无人可投 —— 四种都要能一眼看出「牌去没出去、罚没罚」
func _result_text(result: Dictionary) -> String:
	if bool(result.get("approved", false)):
		return "⚖ 投票通过：这一手按认定落子（同组成本局不再投票）"
	match String(result.get("cause", "")):
		"rejected":
			return "⚖ 投票未通过（有人反对）：出牌撤销，罚抽 1 张"
		"timeout":
			return "⚖ 投票超时（未全票赞成）：出牌撤销，罚抽 1 张"
		"no_voter":
			return "⚖ 其他玩家都离线了，无法裁定：出牌撤销，罚抽 1 张"
	return "⚖ 投票未通过：出牌撤销，罚抽 1 张"
