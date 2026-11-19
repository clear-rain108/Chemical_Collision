# ============================================================
# pages/RoomPage.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4h，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 1953-2598 行 --------
func _build_room_page() -> void:
	if not _ui.start_page:
		return
	var page := Control.new()
	page.name = "RoomPage"
	page.visible = false
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.start_page.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui._room_page = page
	_ui._page_bg_into(page, "RoomBg", "RoomBand")

	var back = _ui._page_ghost_btn("‹ 返回", _close_room_page, Vector2(140, 34), "RoomBackBtn", 15)
	back.position = Vector2(46, 34)
	page.add_child(back)

	page.add_child(_room_label("RoomTitle", "联机对战", Vector2(0, 62), Vector2(1152, 46),
		34, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_CENTER))

	# D14：房号只是辨认用的 4 位数，不代表任何地址（发现层在 P11-C2）。
	# 副标题必须写死这句，别让人以为「输房号就能连」
	page.add_child(_room_label("RoomSubtitle",
		"局域网 / Tailscale 直连 · 3~8 人（房主可调座位数） · 房号仅用于辨认，客人需填房主 IP",
		Vector2(0, 110), Vector2(1152, 20), _ui.START_FS_META, _ui.START_C_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER))

	_room_host_card(page)
	_room_join_card(page)
	_room_seats_panel(page)

	_ui._room_hint_label = _room_label("RoomHintLabel", "", Vector2(46, 556), Vector2(1060, 22),
		_ui.START_FS_META, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	page.add_child(_ui._room_hint_label)

	page.add_child(_room_label("RoomAiLabel", "人机人数", Vector2(46, 592), Vector2(110, 34),
		_ui.START_FS_LABEL, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_ai_spin = _ui._start_make_spin(0, _ui.ROOM_MAX_SEATS - 1, 0, "RoomAiSpin")
	_ui._room_ai_spin.position = Vector2(162, 590)
	_ui._room_ai_spin.size = Vector2(150, 38)
	_ui._room_ai_spin.tooltip_text = "空座位由人机补上（人类座位在前，人机在后）"
	_ui._room_ai_spin.value_changed.connect(_ui._on_room_ai_changed)
	page.add_child(_ui._room_ai_spin)

	# D17：座位数建房前由房主定（3~8，默认 4），进房后锁定（客人只读显示房主的设置）
	page.add_child(_room_label("RoomSeatLabel", "座位数", Vector2(340, 592), Vector2(110, 34),
		_ui.START_FS_LABEL, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_seat_spin = _ui._start_make_spin(_ui.ROOM_MIN_SEATS, _ui.ROOM_MAX_SEATS, _ui.ROOM_DEFAULT_SEATS,
		"RoomSeatSpin")
	_ui._room_seat_spin.position = Vector2(456, 590)
	_ui._room_seat_spin.size = Vector2(150, 38)
	_ui._room_seat_spin.tooltip_text = "本房间总座位数（3~8）：创建后固定，人类坐满后空位由人机补"
	_ui._room_seat_spin.value_changed.connect(_ui._on_room_seat_changed)
	page.add_child(_ui._room_seat_spin)

	_ui._room_start_btn = _ui._page_primary_btn("开始对局", _room_start, Vector2(260, 50), "RoomStartBtn", 20)
	_ui._room_start_btn.position = Vector2(846, 586)
	_ui._room_start_btn.disabled = true
	page.add_child(_ui._room_start_btn)

	_room_refresh()


# 房间页统一的小标签工厂：_start_label() 只给字号 / 颜色 / 对齐，尺寸由调用点定
func _room_label(node_name: String, text: String, pos: Vector2, sz: Vector2, fs: int, col: Color, align: HorizontalAlignment) -> Label:
	var lb = _ui._start_label(text, fs, col, align)
	lb.name = node_name
	lb.position = pos
	lb.size = sz
	return lb


# 带白底 + 主题蓝焦点框的单行输入框（与 _start_make_spin 里的 LineEdit 同一套画风）
func _room_line_edit(node_name: String, text: String, pos: Vector2, sz: Vector2) -> LineEdit:
	var le := LineEdit.new()
	le.name = node_name
	le.text = text
	le.position = pos
	le.size = sz
	le.custom_minimum_size = sz
	le.add_theme_font_size_override("font_size", 17)
	le.add_theme_color_override("font_color", _ui.START_C_TITLE)
	var n = _ui._make_panel_style("mini_card")
	n.bg_color = Color(1, 1, 1, 1)
	n.content_margin_left = 10
	n.content_margin_right = 6
	le.add_theme_stylebox_override("normal", n)
	var f: StyleBoxFlat = n.duplicate()
	f.border_color = _ui.START_C_ACCENT
	f.set_border_width_all(_ui.BORDER_W_ACTIVE)
	le.add_theme_stylebox_override("focus", f)
	return le


# -------- 建房卡：昵称 / 端口 / 本机 IP / 创建 --------
func _room_host_card(page: Control) -> void:
	var card := Panel.new()
	card.name = "RoomHostCard"
	card.position = Vector2(46, 146)
	card.size = Vector2(520, 210)
	var cs = _ui._make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.94)
	card.add_theme_stylebox_override("panel", cs)
	page.add_child(card)

	card.add_child(_room_label("RoomHostTitle", "建房（房主）", Vector2(24, 10), Vector2(300, 24),
		_ui.START_FS_LABEL, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	card.add_child(_room_label("RoomHostNameLabel", "昵称", Vector2(24, 46), Vector2(60, 36),
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_host_name_edit = _room_line_edit("RoomHostNameEdit", "房主",
		Vector2(88, 46), Vector2(156, 36))
	card.add_child(_ui._room_host_name_edit)
	card.add_child(_room_label("RoomHostPortLabel", "端口", Vector2(256, 46), Vector2(56, 36),
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_host_port_spin = _ui._start_make_spin(1024, 65535, _ui.ROOM_DEFAULT_PORT, "RoomPortSpin")
	_ui._room_host_port_spin.position = Vector2(316, 46)
	_ui._room_host_port_spin.size = Vector2(130, 36)
	card.add_child(_ui._room_host_port_spin)

	_ui._room_host_ip_label = _room_label("RoomHostIpLabel", "本机 IP：检测中…",
		Vector2(24, 90), Vector2(470, 40), _ui.START_FS_META, _ui.START_C_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT)
	_ui._room_host_ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_ui._room_host_ip_label)

	_ui._room_create_btn = _ui._page_primary_btn("创建房间", _room_start_host, Vector2(200, 44), "RoomCreateBtn", 19)
	_ui._room_create_btn.position = Vector2(24, 140)
	card.add_child(_ui._room_create_btn)

	_ui._room_code_label = _room_label("RoomCodeLabel", "房号 ----", Vector2(240, 152), Vector2(260, 26),
		_ui.START_FS_LABEL, _ui.START_C_ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	card.add_child(_ui._room_code_label)


# -------- 加入卡：昵称 / 端口 / 房主 IP / 加入 + 离开 --------
func _room_join_card(page: Control) -> void:
	var card := Panel.new()
	card.name = "RoomJoinCard"
	card.position = Vector2(586, 146)
	card.size = Vector2(520, 210)
	var cs = _ui._make_panel_style("card")
	cs.bg_color = Color(1, 1, 1, 0.94)
	card.add_theme_stylebox_override("panel", cs)
	page.add_child(card)

	card.add_child(_room_label("RoomJoinTitle", "加入房间（客人）", Vector2(24, 10), Vector2(300, 24),
		_ui.START_FS_LABEL, _ui.START_C_TITLE, HORIZONTAL_ALIGNMENT_LEFT))
	card.add_child(_room_label("RoomJoinNameLabel", "昵称", Vector2(24, 46), Vector2(60, 36),
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_join_name_edit = _room_line_edit("RoomJoinNameEdit", "玩家",
		Vector2(88, 46), Vector2(156, 36))
	card.add_child(_ui._room_join_name_edit)
	card.add_child(_room_label("RoomJoinPortLabel", "端口", Vector2(256, 46), Vector2(56, 36),
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_join_port_spin = _ui._start_make_spin(1024, 65535, _ui.ROOM_DEFAULT_PORT, "RoomJoinPortSpin")
	_ui._room_join_port_spin.position = Vector2(316, 46)
	_ui._room_join_port_spin.size = Vector2(130, 36)
	card.add_child(_ui._room_join_port_spin)

	card.add_child(_room_label("RoomJoinAddrLabel", "房主 IP", Vector2(24, 92), Vector2(84, 36),
		_ui.START_FS_META, _ui.START_C_MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	_ui._room_addr_edit = _room_line_edit("RoomAddrEdit", "127.0.0.1",
		Vector2(112, 92), Vector2(210, 36))
	_ui._room_addr_edit.tooltip_text = "房主页面上「本机 IP」那一串（如 192.168.1.7）"
	card.add_child(_ui._room_addr_edit)
	card.add_child(_room_label("RoomJoinAddrHint", "例 192.168.1.7",
		Vector2(330, 96), Vector2(170, 24), _ui.START_FS_META, _ui.START_C_MUTED,
		HORIZONTAL_ALIGNMENT_LEFT))

	_ui._room_join_btn = _ui._page_primary_btn("加入房间", _room_join, Vector2(180, 44), "RoomJoinBtn", 19)
	_ui._room_join_btn.position = Vector2(24, 140)
	card.add_child(_ui._room_join_btn)
	_ui._room_leave_btn = _ui._page_secondary_btn("离开房间", _room_leave, Vector2(150, 44), "RoomLeaveBtn", 17)
	_ui._room_leave_btn.position = Vector2(216, 140)
	_ui._room_leave_btn.disabled = true
	card.add_child(_ui._room_leave_btn)



# -------- 座位表：一次建 8 张卡，按「当前容量」显隐 + 重排（D17）--------
# 为什么先全建再显隐：容量只在建房前变（3~8），重建节点会让测试按名字取控件
# 变得时序敏感；8 张卡一次性建好，刷新时只改 visible / 位置 / 字号最稳。
func _room_seats_panel(page: Control) -> void:
	var panel := Panel.new()
	panel.name = "RoomSeatsPanel"
	panel.position = Vector2(46, 372)
	panel.size = Vector2(1060, 176)
	var st = _ui._make_panel_style("card")
	st.bg_color = Color(1, 1, 1, 0.94)
	panel.add_theme_stylebox_override("panel", st)
	page.add_child(panel)

	panel.add_child(_room_label("RoomSeatsTitle", "座位表（人类座位在前，人机座位在后）",
		Vector2(24, 8), Vector2(700, 24), _ui.START_FS_LABEL, _ui.START_C_TITLE,
		HORIZONTAL_ALIGNMENT_LEFT))

	_ui._room_seat_cards.clear()
	_ui._room_seat_nos.clear()
	_ui._room_seat_names.clear()
	_ui._room_seat_states.clear()
	for i in range(_ui.ROOM_MAX_SEATS):
		var sc := Panel.new()
		sc.name = "RoomSeatCard_%d" % i
		sc.position = Vector2(24 + i * 256, 38)
		sc.size = Vector2(240, 122)
		var ss = _ui._make_panel_style("mini_card")
		ss.bg_color = Color(0.965, 0.976, 0.99, 1.0)
		ss.border_color = Color(0.85, 0.89, 0.94, 1.0)
		ss.set_border_width_all(1)
		sc.add_theme_stylebox_override("panel", ss)
		panel.add_child(sc)

		var no = _room_label("RoomSeatNo_%d" % i, "座位 %d" % (i + 1),
			Vector2(14, 8), Vector2(212, 18), _ui.START_FS_META, _ui.START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(no)
		var nm = _room_label("RoomSeatName_%d" % i, "空位",
			Vector2(14, 30), Vector2(212, 30), 20, _ui.START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(nm)
		var stt = _room_label("RoomSeatState_%d" % i, "—",
			Vector2(14, 72), Vector2(212, 20), _ui.START_FS_META, _ui.START_C_MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
		sc.add_child(stt)
		_ui._room_seat_cards.append(sc)
		_ui._room_seat_nos.append(no)
		_ui._room_seat_names.append(nm)
		_ui._room_seat_states.append(stt)
	_room_layout_seats(_ui.ROOM_DEFAULT_SEATS)


# 座位卡按容量重排：
#   3~4 张沿用老位置（24 + i*256，240×122）—— 牌桌手感 / 老截图 / 老测试都不变
#   5~8 张挤成一行（等分 1012px，间距 8）：n=8 时每张 119px，昵称 16px + 裁切
func _room_layout_seats(capacity: int) -> void:
	var n := clampi(int(capacity), _ui.ROOM_MIN_SEATS, _ui.ROOM_MAX_SEATS)
	var tight := n > 4
	var gap := 8.0 if tight else 16.0
	var w := 240.0
	if tight:
		w = floorf((1012.0 - float(n - 1) * gap) / float(n))
	var pad := 8.0 if tight else 14.0
	for i in range(_ui._room_seat_cards.size()):
		var card = _ui._room_seat_cards[i]
		if not (card is Control) or not is_instance_valid(card):
			continue
		card.visible = i < n
		if not card.visible:
			continue
		var x := 24.0 + float(i) * (w + gap) if tight else float(24 + i * 256)
		card.position = Vector2(x, 38.0)
		card.size = Vector2(w, 122.0)
		if i < _ui._room_seat_nos.size():
			var no = _ui._room_seat_nos[i]
			no.position = Vector2(pad, 8)
			no.size = Vector2(w - pad * 2.0, 18)
		if i < _ui._room_seat_names.size():
			var nm = _ui._room_seat_names[i]
			nm.position = Vector2(pad, 30)
			nm.size = Vector2(w - pad * 2.0, 30)
			nm.clip_text = true
			nm.add_theme_font_size_override("font_size", 16 if tight else 20)
		if i < _ui._room_seat_states.size():
			var stt = _ui._room_seat_states[i]
			stt.position = Vector2(pad, 72)
			stt.size = Vector2(w - pad * 2.0, 20)
			stt.clip_text = true


# -------- 整页刷新：座位表 / 房号 / 提示 / 4 颗按钮的可用态 --------
func _room_refresh() -> void:
	if _ui._room_page == null or not is_instance_valid(_ui._room_page):
		return
	var online = _room_online_humans()
	var offline = _room_offline_humans()
	var seat_total := int(_ui.net_session.seat_count()) if _ui.net_session != null else 0
	var my_seat := int(_ui.net_session.my_seat) if _ui.net_session != null else -1
	var capacity = _room_seat_capacity()
	var tight: bool = capacity > 4
	_room_layout_seats(capacity)

	# AI 上限 = 剩下的空座位（总座位 = 本房间容量）：真人坐满就一个 AI 也加不了
	# D19：在房里时 AI 数由房主定（NetSession.lobby_ai 广播同步），客人只读同一份值
	if _ui._room_ai_spin != null:
		var ai_cap := maxi(0, capacity - online)
		var want := mini(int(_ui._room_ai_spin.value), ai_cap)
		var follows_host: bool = _ui.net_session != null and _ui.net_session.has_method("set_lobby_ai")
		if follows_host:
			want = mini(int(_ui.net_session.lobby_ai), ai_cap)
		_ui._room_ai_sync = true                  # 写值会触发 value_changed，先挡住回推
		_ui._room_ai_spin.max_value = ai_cap
		if int(_ui._room_ai_spin.value) != want:
			_ui._room_ai_spin.value = want        # Range 会把超限值压回 max
		_ui._room_ai_sync = false
		# 大厅 AI 数只有房主能定：客人能点却改了不生效，比根本点不动更误导
		_ui._room_ai_spin.editable = not follows_host or _ui.net_session.is_host()
	var ai = _room_ai_value()
	var planned: int = online + ai

	for i in range(capacity):
		var name_text := "空位"
		var state_text := "—"
		var taken := false
		if i < seat_total:
			taken = true
			name_text = String(_ui.net_session.seat_name(i))
			if name_text == "":
				name_text = "玩家 %d" % (i + 1)
			if not _ui.net_session.seat_is_online(i):
				state_text = "掉线·保留" if tight else "掉线中 · 座位保留"
			elif i == 0 and _ui.net_session.is_host():
				state_text = "房主 · 你" if my_seat == i else "房主"
			elif my_seat == i:
				state_text = "你 · 在线"
			else:
				state_text = "在线"
		elif i >= online and (i - online) < ai:
			# 人类座位永远排在前面 → 第 online 个之后的空座位才是 AI
			taken = true
			name_text = "人机 %d" % (i - online + 1)
			state_text = "人机托管"
		if i >= _ui._room_seat_names.size():
			continue
		_ui._room_seat_names[i].text = name_text
		_ui._room_seat_names[i].add_theme_color_override("font_color",
			_ui.START_C_TITLE if taken else _ui.START_C_MUTED)
		_ui._room_seat_states[i].text = state_text
		_ui._room_seat_states[i].add_theme_color_override("font_color",
			_ui.START_C_ACCENT if taken else _ui.START_C_MUTED)

	if _ui._room_code_label != null:
		var code := String(_ui.net_session.room_code) if _ui.net_session != null else ""
		_ui._room_code_label.text = ("房号 " + code) if code != "" else "房号 ----"
	if _ui._room_host_ip_label != null:
		_ui._room_host_ip_label.text = _room_ip_text()

	var joined = _ui.net_session != null
	if _ui._room_seat_spin != null:
		_ui._room_seat_spin.value = capacity
		_ui._room_seat_spin.editable = not joined   # 进房后锁定：容量在建房时就定了
	if _ui._room_create_btn != null:
		_ui._room_create_btn.disabled = joined
	if _ui._room_join_btn != null:
		_ui._room_join_btn.disabled = joined
	if _ui._room_leave_btn != null:
		_ui._room_leave_btn.disabled = not joined
	if _ui._room_start_btn != null:
		var reason = _room_start_disabled_reason()
		_ui._room_start_btn.disabled = reason != ""
		if reason == "":
			_ui._room_start_btn.text = "开始对局"
		elif joined and not _ui.net_session.is_host():
			_ui._room_start_btn.text = "等待房主开始"
		elif joined:
			_ui._room_start_btn.text = "开始对局 · %d/%d 座位" % [mini(planned, capacity), capacity]
		else:
			_ui._room_start_btn.text = "开始对局"
	# 掉线提示只在提示区空着时补一句（否则会盖掉「xxx 加入了」这类操作反馈）
	if offline > 0 and _ui._room_hint_label != null and _ui._room_hint_label.text == "":
		_ui._room_hint_label.text = "有玩家掉线，座位会保留 %d 秒等重连" % int(int(_ui.net_session.reconnect_grace_ms) / 1000)


# -------- 本机 IP：房主要把这一串报给客人（D14：房号不是地址）--------
func _room_local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.find(":") >= 0:
			continue                 # IPv6 不列：手输太长，局域网 IPv4 够用
		if s.begins_with("127."):
			continue                 # 回环：本机自测用，别当房主地址报给客人
		if s.begins_with("169.254."):
			continue                 # 链路本地地址：实际连不通
		out.append(s)
	out.sort()
	return out


func _room_ip_text() -> String:
	var ips = _room_local_ips()
	if ips.is_empty():
		return "本机 IP：未检测到局域网地址（同一台机器自测可用 127.0.0.1）"
	var txt := ""
	for ip in ips:
		if txt != "":
			txt += " / "
		txt += String(ip)
	return "本机 IP：%s（客人填这一串）" % txt


# -------- 开局闸门（D12 / D15 / D17）--------
# 纯函数：只吃几个数，不碰会话 / 控件，测试可以逐格喂边界。
# capacity = 本房间座位数（3~8，默认 4 保持老行为）
# 返回 "" = 可以开局；其余 = 直接显示给用户的原因
func _room_start_block_reason(online_humans: int, ai_count: int, is_host: bool, room_state: int, offline_seats: int, capacity: int) -> String:
	if not is_host:
		return "等待房主开始"
	if room_state == _ui.NetSessionScript.State.PLAYING:
		return "对局已开始"
	if room_state != _ui.NetSessionScript.State.LOBBY:
		return "房间未就绪"
	var cap := clampi(int(capacity), _ui.ROOM_MIN_SEATS, _ui.ROOM_MAX_SEATS)
	var total := int(online_humans) + int(ai_count)
	if total < _ui.ROOM_MIN_SEATS:
		return "座位不足：至少 %d 个（当前 %d）" % [_ui.ROOM_MIN_SEATS, total]
	if total > cap:
		return "座位超限：最多 %d 个（当前 %d）" % [cap, total]
	if int(offline_seats) > 0:
		return "有玩家掉线，等重连后再开局"
	return ""


# 会话 → 闸门参数。state 用 is_playing() 反推，不去读会话内部字段
# （假会话只需要实现 is_host / is_playing / seat_count / seat_is_online / seat_capacity）
func _room_start_disabled_reason() -> String:
	if _ui.net_session == null:
		return "还没加入房间"
	var st = _ui.NetSessionScript.State.LOBBY
	if _ui.net_session.is_playing():
		st = _ui.NetSessionScript.State.PLAYING
	return _room_start_block_reason(_room_online_humans(), _room_ai_value(),
		_ui.net_session.is_host(), st, _room_offline_humans(), _room_seat_capacity())


func _room_can_start() -> bool:
	return _room_start_disabled_reason() == ""


func _room_online_humans() -> int:
	if _ui.net_session == null:
		return 0
	var n := 0
	for s in range(int(_ui.net_session.seat_count())):
		if _ui.net_session.seat_is_online(s):
			n += 1
	return n


func _room_offline_humans() -> int:
	if _ui.net_session == null:
		return 0
	var n := 0
	for s in range(int(_ui.net_session.seat_count())):
		if not _ui.net_session.seat_is_online(s):
			n += 1
	return n


func _room_ai_value() -> int:
	return int(_ui._room_ai_spin.value) if _ui._room_ai_spin != null else 0


# -------- 页面开关 --------
func _open_room_page() -> void:
	if _ui._room_page == null or not is_instance_valid(_ui._room_page):
		return
	_ui._room_page.visible = true
	_room_refresh()
	_ui._fade_in_page(_ui._room_page)


func _close_room_page() -> void:
	_room_teardown()
	if _ui._room_page != null and is_instance_valid(_ui._room_page):
		_ui._room_page.visible = false


# 离开房间 / 回开始页 / 连不上：唯一的收尾口（D13）
func _room_teardown() -> void:
	if _ui._room_closing:
		return
	_ui._room_closing = true
	_ui._room_mode = _ui.RoomMode.IDLE
	_ui._room_connect_wait = 0.0
	_ui._room_join_target = ""
	_ui._clear_net_over_notice()       # 离开房间 = 终止提示作废（房间页有自己的常驻提示行）
	var s = _ui.net_session
	if s != null:
		s.close("离开房间")
		_ui.attach_session(null)
	# 大厅那份 GameManager 只是给会话占位（players 为空）：留着会让下一次单机开局
	# 带着空 players 进 _refresh_ui。真打过的对局（players 非空）绝不在这里丢
	if _ui.game_manager != null and _ui.game_manager.get_player_count() == 0:
		_ui.game_manager = null
	_room_hint("")
	_ui._room_closing = false
	_room_refresh()


func _room_leave() -> void:
	if _ui.net_session == null:
		_room_hint("还不在房间里")
		return
	_room_teardown()
	_room_hint("已离开房间")


func _room_hint(text: String) -> void:
	if _ui._room_hint_label != null and is_instance_valid(_ui._room_hint_label):
		_ui._room_hint_label.text = text


# -------- 建房（房主 = seat 0）--------
func _room_start_host() -> void:
	if _ui.net_session != null:
		_room_hint("已经在房间里了：先「离开房间」再新建")
		return
	var port: int = int(_ui._room_host_port_spin.value) if _ui._room_host_port_spin != null else _ui.ROOM_DEFAULT_PORT
	var capacity = _room_seat_capacity()
	var nm := "房主"
	if _ui._room_host_name_edit != null and _ui._room_host_name_edit.text.strip_edges() != "":
		nm = _ui._room_host_name_edit.text.strip_edges()
	# 大厅也要一份 GameManager：补充规则要在开局前定下来，随 game_start 的 config 下发
	_ui.game_manager = _ui.GameManagerScript.new()
	_ui._apply_start_page_rules(_ui.game_manager)
	var s = _ui.NetSessionScript.new()
	s.setup(_ui.game_manager, _ui.ENetTransportScript.new())
	s.max_players = capacity
	# 观战者 UI 还没做（见 MULTIPLAYER_TASKS §5）：满员直接拒，别给个看不见的观战位
	s.allow_watchers = false
	_room_bind_session(s)
	if s.start_host(port, capacity, nm) != 0:
		_room_teardown()
		_room_hint("端口 %d 建不起来（多半被占用）：换一个端口再试" % port)
		return
	_ui._room_mode = _ui.RoomMode.HOSTING
	_room_hint("房间已创建（%d 座位）：把本机 IP + 端口 %d 告诉客人" % [capacity, port])
	_room_refresh()


# -------- 加入（客人）--------
func _room_join() -> void:
	if _ui.net_session != null:
		_room_hint("已经在房间里了：先「离开房间」再加入")
		return
	var addr := "127.0.0.1"
	if _ui._room_addr_edit != null:
		addr = _ui._room_addr_edit.text.strip_edges()
	if addr == "":
		_room_hint("请填房主 IP（房主页面「本机 IP」那一串，如 192.168.1.7）")
		return
	var port: int = int(_ui._room_join_port_spin.value) if _ui._room_join_port_spin != null else _ui.ROOM_DEFAULT_PORT
	var nm := "玩家"
	if _ui._room_join_name_edit != null and _ui._room_join_name_edit.text.strip_edges() != "":
		nm = _ui._room_join_name_edit.text.strip_edges()
	# 客人这份 GameManager 只为「手上有个对象」：牌库 / 规则最终由主机
	# game_start 的 config + seed 覆盖（NetSession._apply_config_and_init）
	_ui.game_manager = _ui.GameManagerScript.new()
	_ui._apply_start_page_rules(_ui.game_manager)
	var s = _ui.NetSessionScript.new()
	s.setup(_ui.game_manager, _ui.ENetTransportScript.new())
	# 客人还不知道房主的容量：先填默认值，收 welcome 时会被 max_players 覆盖成房主那档
	s.max_players = _ui.ROOM_DEFAULT_SEATS
	s.allow_watchers = false
	_room_bind_session(s)
	if s.start_client(addr, port, nm) != 0:
		_room_teardown()
		_room_hint("地址填错了：%s" % addr)
		return
	_ui._room_mode = _ui.RoomMode.CONNECTING
	_ui._room_connect_wait = 0.0
	_ui._room_join_target = "%s:%d" % [addr, port]
	_room_hint("正在连接 %s …（连不上 %d 秒后自动放弃）" % [_ui._room_join_target, int(_ui.ROOM_CONNECT_TIMEOUT_S)])
	_room_refresh()


# -------- 开局（只有房主能点，闸门见 _room_start_block_reason）--------
func _room_start() -> void:
	var reason = _room_start_disabled_reason()
	if reason != "":
		_room_hint(reason)
		_room_refresh()
		return
	var ai = _room_ai_value()
	var total = _room_online_humans() + ai
	if _ui.net_session.start_game(total, ai) != 0:
		_room_hint("开局失败：房间状态异常，请离开后重新建房")
		return
	_ui._room_mode = _ui.RoomMode.JOINED
	_room_refresh()   # game_started → _enter_online_game() 已把整页切走


# -------- 会话绑定 / 回调 --------
# 房间页唯一的会话装配口：既复用 Step 3 的 attach_session（视图归属 / 动作层 /
# 8 个对局信号），又额外挂 3 个大厅信号。D13：别在别处直接给 net_session 赋值。
func _room_bind_session(s) -> void:
	_ui.attach_session(s)
	if not s.room_changed.is_connected(_room_refresh):
		s.room_changed.connect(_ui._room_refresh)
	if not s.seat_assigned.is_connected(_room_on_seat_assigned):
		s.seat_assigned.connect(_ui._room_on_seat_assigned)
	if not s.peer_joined.is_connected(_room_on_peer_joined):
		s.peer_joined.connect(_ui._room_on_peer_joined)
	if not s.peer_left.is_connected(_room_on_peer_left):
		s.peer_left.connect(_ui._room_on_peer_left)


# 客人收到 welcome（含自己座位）+ 快照后到这儿；seat < 0 = 观战
func _room_on_seat_assigned(seat: int) -> void:
	_ui._room_mode = _ui.RoomMode.JOINED
	_ui._room_connect_wait = 0.0
	_ui._room_join_target = ""
	if int(seat) < 0:
		_room_hint("房间已满：你以观战身份进入（对局中只能看，不能出牌）")
	else:
		_room_hint("已加入：你是座位 %d，房主开局后自动进入牌桌" % (int(seat) + 1))
	_room_refresh()


func _room_on_peer_joined(seat: int, peer_name: String) -> void:
	_room_hint("%s 加入了（座位 %d）" % [String(peer_name), int(seat) + 1])
	_room_refresh()


func _room_on_peer_left(seat: int, peer_name: String, grace_ms: int) -> void:
	_room_hint("%s 离开了（座位 %d 保留 %d 秒等重连）" % [
		String(peer_name), int(seat) + 1, int(int(grace_ms) / 1000)])
	_room_refresh()


# 房主改 AI 数：先落到会话（clamp + 广播 MSG_LOBBY），再由 room_changed 回来刷新界面。
# 客人这份是只读的（_room_refresh 里 editable = false），就算走到这里也会被 set_lobby_ai 挡掉。
func _on_room_ai_changed(_value: float) -> void:
	if _ui._room_ai_sync:
		return                       # _room_refresh 同步值引起的回调，不要回推给会话
	if _ui.net_session != null and _ui.net_session.has_method("set_lobby_ai"):
		_ui.net_session.set_lobby_ai(_room_ai_value())
	_room_refresh()


# 座位数改了：AI 上限 / 座位卡张数 / 开局按钮文案都要跟着重算（D17）
func _on_room_seat_changed(_value: float) -> void:
	_room_refresh()


# 当前房间的座位容量：
#   在房里 → 会话定下的容量（客人靠 welcome 的 max_players 同步，和房主一致）
#   还没建房 → 座位数微调框的值（默认 4）
func _room_seat_capacity() -> int:
	if _ui.net_session != null:
		# has_method 兜底：测试里的假会话只实现自己用到的查询，缺这条就退回默认容量
		if _ui.net_session.has_method("seat_capacity"):
			return clampi(int(_ui.net_session.seat_capacity()), _ui.ROOM_MIN_SEATS, _ui.ROOM_MAX_SEATS)
		return _ui.ROOM_DEFAULT_SEATS
	if _ui._room_seat_spin != null:
		return clampi(int(_ui._room_seat_spin.value), _ui.ROOM_MIN_SEATS, _ui.ROOM_MAX_SEATS)
	return _ui.ROOM_DEFAULT_SEATS