# ============================================================
# net/OnlineUI.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 4g，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null
# 已经接过信号的会话对象。attach_session 可能被重复调用（重连补拉 / 同一局重进牌桌），
# 而 Signal.is_connected() 在这种「同一 callable 二次 connect」上并不可靠 ——
# 只靠它会直接抛 "already connected" ERROR，所以这里再记一份实例身份兜底。
var _wired_session = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 1865-2162 行 --------
func _router():
	if _ui.action_router == null:
		_ui.action_router = _ui.ActionRouterScript.new()
		_ui.action_router.setup(_ui.game_manager, _ui.net_session)
	elif _ui.action_router.game != _ui.game_manager:
		_ui.action_router.setup(_ui.game_manager, _ui.net_session)
	return _ui.action_router


# 装配联机会话。session == null 表示退回单机（动作层同时切回直连 GameManager）。
func attach_session(session) -> void:
	_ui.net_session = session
	if _ui.action_router == null:
		_ui.action_router = _ui.ActionRouterScript.new()
	_ui.action_router.setup(_ui.game_manager, session)
	# --net-trace：每个新装配的会话都打开追踪（重建 / 重连后的新会话也不会漏）
	if session != null and _ui._net_trace:
		session.enable_trace(true)
	# 换座 / 重连后残留的热座认领与只读态必须清零（D7）
	_ui._hotseat_ready_seat = -1
	_ui._hand_read_only = false
	_ui._net_ai_wait = 0.0
	if session == null:
		_hide_sequence_overlay()
		_ui.ui_vote.hide_vote()          # D22：会话没了，投票遮罩也必须跟着消失
		_wired_session = null            # 别攥着已关闭的会话不放
		return
	_connect_online_signals(session)
	# 会话已经在对局中（重连 / 热加入）：直接切到牌桌，不必等 game_started
	if session.is_playing() and _ui.game_manager != null:
		_enter_online_game()
		# 重连那一刻可能正在投票：welcome / 快照里的 vote 字段在信号还没接上时
		# 就被 _client_on_vote 吃掉了（emit 无人接），这里补一次拉取。
		if session.has_method("vote_open") and session.vote_open():
			_ui.ui_vote.on_vote_opened(session.vote_state())


# -------- 座位 / 视图归属 --------
func _my_seat() -> int:
	if _ui.net_session == null:
		return -1
	return int(_ui.net_session.my_seat)


# 本地视角的玩家：单机 = 当前行动者；联机 = 自己座位（观战 = null）
func _view_player():
	if _ui.game_manager == null:
		return null
	if _ui.net_session == null:
		return _ui.game_manager.get_current_player()
	var seat = _my_seat()
	if seat < 0 or seat >= _ui.game_manager.players.size():
		return null
	return _ui.game_manager.players[seat]


# 现在这份手牌能不能动：对局中 + 轮到我 + 没有待处理两阶段 + 没有待裁决意图
func _net_can_operate() -> bool:
	if _ui.net_session == null or _ui.action_router == null:
		return false
	if not _ui.net_session.can_submit():
		return false
	if not _ui.net_session.is_my_turn():
		return false
	return not _ui.action_router.awaiting_reply()


# 操作面板的等待文案（"" = 该显示正常按钮）
func _net_wait_text() -> String:
	if _ui.net_session == null:
		return ""
	if _ui.net_session.is_watcher():
		return "观战中：本轮由其他玩家操作"
	# D22：投票裁定期间全场冻结 —— 面板必须说清楚「这不是卡住，是在等票」
	# has_method 兜底：测试里的假会话不一定实现投票读口（同 set_lobby_ai 口径）
	if _ui.net_session.has_method("vote_open") and _ui.net_session.vote_open():
		return "正在投票裁定上一手牌，等待结果…"
	if _ui.action_router != null and _ui.action_router.awaiting_reply():
		return "已提交，等待主机裁决…"
	if _ui.net_session.is_my_sequence_pending():
		return "请先在弹窗中选择牌型（或跳过指定）"
	if not _ui.net_session.is_my_turn():
		var actor = _ui.game_manager.get_current_player() if _ui.game_manager != null else null
		var who: String = actor.player_name if actor != null else "对手"
		return "等待 %s 行动…" % who
	return ""


# 等待提示用一个 Label（与按钮同高，_fit_action_panel 的行数计算对 Control 一视同仁）
func _mk_wait_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.33, 0.4, 0.5, 1))
	lbl.custom_minimum_size = Vector2(0, _ui._action_btn_h())
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


# -------- 动作结果分派（D1 / D2）--------
# 单机：原样交给 _handle_result（返回码 = 规则码，飞牌 / 弹窗 / 提示全靠它）
# 联机：客人侧 0 只代表「已发出」；主机侧规则码当场有效，但 1 = 轮到自己选牌型
func _dispatch_result(code: int) -> void:
	if _ui.net_session == null:
		_ui._handle_result(code)
		return
	if _ui.action_router != null and _ui.action_router.awaiting_reply():
		# 客人：等 state_applied / intent_rejected，先把自己刷成「已提交」态
		_ui._update_action_panel()
		_ui._update_card_info_label()
		return
	if int(code) == 0:
		return                      # 主机：_host_apply 已广播并触发 _online_on_state_applied
	if int(code) == 1:
		_ui._step_reset()
		_ui._show_sequence_constraint_dialog()
		return
	var why: String = _ui.action_router.last_reason() if _ui.action_router != null else ""
	if why == "":
		why = _ui.ActionRouterScript.describe_code(int(code))
	_ui._show_info("操作被拒绝：" + why)
	_ui._on_back()


# -------- 信号接线（attach_session 可能因重连被重复调用，必须只连一次）--------
func _connect_online_signals(session) -> void:
	# 同一个会话对象二次装配：信号已经在它身上接好了，别再连一遍
	if session == _wired_session:
		return
	_wired_session = session
	if not session.game_started.is_connected(_online_on_game_started):
		session.game_started.connect(_ui._online_on_game_started)
	if not session.state_applied.is_connected(_online_on_state_applied):
		session.state_applied.connect(_ui._online_on_state_applied)
	if not session.intent_rejected.is_connected(_online_on_intent_rejected):
		session.intent_rejected.connect(_ui._online_on_intent_rejected)
	if not session.sequence_pending.is_connected(_online_on_sequence_pending):
		session.sequence_pending.connect(_ui._online_on_sequence_pending)
	if not session.sequence_cleared.is_connected(_online_on_sequence_cleared):
		session.sequence_cleared.connect(_ui._online_on_sequence_cleared)
	if not session.session_closed.is_connected(_online_on_session_closed):
		session.session_closed.connect(_ui._online_on_session_closed)
	if not session.desync_detected.is_connected(_online_on_desync):
		session.desync_detected.connect(_ui._online_on_desync)
	if not session.error_raised.is_connected(_online_on_error):
		session.error_raised.connect(_ui._online_on_error)
	# D22：化合物质疑投票（遮罩层只读快照，判定全在 NetSession）
	if not session.vote_opened.is_connected(_online_on_vote_opened):
		session.vote_opened.connect(_online_on_vote_opened)
	if not session.vote_updated.is_connected(_online_on_vote_updated):
		session.vote_updated.connect(_online_on_vote_updated)
	if not session.vote_resolved.is_connected(_online_on_vote_resolved):
		session.vote_resolved.connect(_online_on_vote_resolved)


# -------- 信号回调 --------
func _online_on_game_started() -> void:
	_enter_online_game()


func _online_on_state_applied(_ev: Dictionary, _result: int) -> void:
	if _ui.game_manager == null:
		return
	# 主机自己的一手在 submit() 里当场落子（同步），客人靠重放；
	# 两条路径都在这里收口：清步骤态 → 整屏重画（_refresh_ui 负责结算页）
	_ui._step_reset()
	_ui._refresh_ui()


func _online_on_intent_rejected(_seq: int, code: int) -> void:
	_ui._show_info("主机拒绝：" + _ui.ActionRouterScript.describe_code(int(code)))
	_ui._step_reset()
	_ui._refresh_ui()


func _online_on_sequence_pending(seat: int, remain_ms: int) -> void:
	if _ui.game_manager == null:
		return
	if seat != _my_seat():
		# 别人在选牌型：轮不到我，先把面板刷成等待态
		_ui._refresh_ui()
		return
	_ui._show_sequence_constraint_dialog()
	_ui._refresh_ui()
	_ui._show_info("请选择下一名玩家必须打出的牌型（%d 秒内）" % maxi(1, int(remain_ms / 1000)))


func _online_on_sequence_cleared() -> void:
	_hide_sequence_overlay()
	_ui._refresh_ui()


func _online_on_session_closed(reason: String) -> void:
	# 会话没了，此刻还开着的顺序牌型弹窗就永远等不到 sequence_cleared 了
	_hide_sequence_overlay()
	# D22：投票遮罩同理 —— 投票箱随会话一起没了，never 会再来 vote_resolved
	_ui.ui_vote.hide_vote()
	# 自己主动关的（离开房间 / 退出对局）：调用方已在收尾，别再刷一遍提示
	if _ui._room_closing:
		return
	_ui._room_mode = _ui.RoomMode.IDLE
	_ui._room_connect_wait = 0.0
	var msg := "联机已结束"
	if reason != "":
		msg += "：" + reason
	# 房间里掉线（房主离开 / 连不上 / 被拒）：留在房间页显示原因。
	# 大厅里 game_manager 的 players 是空的，这时 _refresh_ui() 会去读空局面，
	# 所以绝不能落到下面的通用分支（Step 4 修掉的隐患，见 D13）
	if _ui._room_page != null and is_instance_valid(_ui._room_page) and _ui._room_page.visible:
		_ui._room_teardown()
		_ui._room_hint(msg)
		return
	# 牌桌上房主退出 / 失联：把原因钉在界面上（D20）。只弹 toast 的话 2.5 秒后
	# 就只剩「等待 X 行动…」，看起来像卡死 —— 这正是真机反馈的那个问题。
	_ui._net_over_notice = msg
	_ui._show_info(msg)
	_ui._show_center_warning(msg, true)
	# 单机 / 房间页关着：只有真的有一局在打才刷新（0 玩家时刷 = 读空局面）
	if _ui.game_manager != null and _ui.game_manager.get_player_count() > 0:
		_ui._refresh_ui()


func _online_on_desync(local_hash: int, host_hash: int) -> void:
	# 分叉后不再推进，弹窗留着只会让人以为还能选
	_hide_sequence_overlay()
	_ui.ui_vote.hide_vote()          # 分叉后投票也无意义（can_submit 已 false）
	_ui._net_over_notice = "状态分叉（本端 %d / 主机 %d），已停止推进" % [int(local_hash), int(host_hash)]
	_ui._show_info(_ui._net_over_notice)
	# 终局提示必须常驻：toast 2.5 秒就没，牌桌上看不出「这局已经停了」（D20）
	_ui._show_center_warning(_ui._net_over_notice, true)
	_ui._refresh_ui()


func _online_on_error(code: int, detail: String) -> void:
	_ui._show_info("联机错误 %d：%s" % [int(code), String(detail)])


# -------- D22：化合物质疑投票（三个信号原样转发给遮罩层）--------
func _online_on_vote_opened(state: Dictionary) -> void:
	_ui.ui_vote.on_vote_opened(state)


func _online_on_vote_updated(state: Dictionary) -> void:
	_ui.ui_vote.on_vote_updated(state)


func _online_on_vote_resolved(result: Dictionary) -> void:
	_ui.ui_vote.on_vote_resolved(result)


# 顺序牌型弹窗的唯一关闭口（两个回调 / 超时 / 会话结束都走它）
func _hide_sequence_overlay() -> void:
	if _ui._seq_overlay != null and is_instance_valid(_ui._seq_overlay):
		_ui._seq_overlay.queue_free()
	_ui._seq_overlay = null


# -------- 每帧驱动（_process 第一行）--------
func _update_net(delta: float) -> void:
	if _ui.net_session == null:
		return
	# ① 收包 / 超时 / 断线宽限：所有角色都必须 poll，否则永远收不到包
	_ui.net_session.poll()
	# ①之三 D22：投票遮罩的倒计时（也在这里自愈「投票已收口但遮罩还开着」）
	_ui.ui_vote.tick(delta)
	# ①之二 房间页：ENet 的 create_client 是异步的，连不上时一个回调都不会来，
	#       只能自己计时给条出路（否则客人会永远停在「正在连接…」）
	if _ui._room_mode == _ui.RoomMode.CONNECTING:
		_ui._room_connect_wait += delta
		if _ui._room_connect_wait >= _ui.ROOM_CONNECT_TIMEOUT_S:
			var target = _ui._room_join_target
			_ui._room_teardown()
			_ui._room_hint("连不上 %s：检查房主 IP / 端口 / 防火墙是否放行" % target)
			return
	if _ui.game_manager == null:
		return
	# ② 主机代打 AI 座位（D8）：单机那份「AI 计时器」在联机被关掉了，
	#    不在这里推进，AI 回合会永远停住
	if not _ui.net_session.is_host():
		return
	if not _ui.net_session.is_playing() or _ui.game_manager.is_game_over():
		return
	# 客人还没按快照重建完就替 AI 出牌 → 客人重放必分叉（host_step_ai 内部也有这道门，
	# 这里提前挡住，顺带清零节流，避免重建完成后立刻连打好几手）
	if not _ui.net_session.all_seats_ready():
		_ui._net_ai_wait = 0.0
		return
	var cp = _ui.game_manager.get_current_player()
	if cp == null or not cp.is_ai:
		_ui._net_ai_wait = 0.0
		return
	_ui._net_ai_wait += delta
	if _ui._net_ai_wait < _net_ai_delay():
		return
	_ui._net_ai_wait = 0.0
	# host_step_ai 内部走 host_act_for_seat → _host_apply → state_applied，
	# 界面刷新由 _online_on_state_applied 负责，这里不再重复刷
	_ui.net_session.host_step_ai(1)


# AI 节流按人数缩短（D17）：8 座位最多 7 个 AI，还按 1.2s 走一轮要 8 秒多，
# 真人对局里那是纯等待。3~4 个 AI 保持接近单机手感，5 个以上再压一档。
func _net_ai_delay() -> float:
	var ai := int(_ui.net_session.ai_count()) if _ui.net_session != null else 0
	if ai >= 5:
		return _ui.NET_AI_DELAY_S * 0.5          # 7 个 AI → 0.6s/手，一轮约 4 秒
	if ai >= 3:
		return _ui.NET_AI_DELAY_S * 0.66         # 3~4 个 AI → 0.8s/手
	return _ui.NET_AI_DELAY_S


# -------- 进牌桌（联机版 _on_start_game：局面由会话给，不在这里 new GameManager）--------
func _enter_online_game() -> void:
	if _ui.game_manager == null:
		return
	_ui.ui_vote.hide_vote()           # 新一局：上一局残留的投票遮罩必须清掉
	_ui.start_page.visible = false
	_ui.game_page.visible = true
	_ui.end_page.visible = false
	if _ui.help_page: _ui.help_page.visible = false
	# 教学关卡列表可能刚从开始页打开，会盖在 GamePage 上
	var tut_page = _ui.get_node_or_null("TutorialPage")
	if tut_page: tut_page.visible = false
	_ui._close_supp_rules()
	# Step 4：房间页挂在开始页下面，跟着 start_page 一起藏起来；
	# 这里只隐藏、绝不 teardown —— 开局后会话还要用
	if _ui._room_page != null and is_instance_valid(_ui._room_page):
		_ui._room_page.visible = false
	_ui._clear_net_over_notice()       # 新一局开局：上一局的终止提示作废
	_ui._hide_warning_toast()
	_ui._hotseat_ready_seat = -1
	_ui.log_lines.clear()
	if _ui.log_label:
		_ui.log_label.text = "游戏日志:"
	_ui._fade_in_page(_ui.game_page)
	_ui._step_reset()
	_ui._refresh_ui()
