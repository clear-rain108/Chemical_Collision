# ============================================================
# ui/Toast.gd - 右栏警告 toast + 状态栏提示出口
#
# 从 GameUI.gd 搬来（Slice 1）：_show_info / _show_center_warning /
#   _ensure_warning_toast / _hide_warning_toast
#
# 状态留在 root（测试直读）：
#   tests/verify_ui_online.gd、verify_hand_layout.gd 直接读 scene._warning_toast /
#   scene._warning_label，所以这两个节点引用 + _warning_seq 计数**不搬进模块**，
#   模块通过 _ui._warning_toast 读写。
#
# 跨模块调用经 root 转发（_ui._make_panel_style / _ui._layer）：
#   只多一跳，且不构成递归（转发目标是别的模块的方法）。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


func _show_info(text: String) -> void:
	# 状态栏只刷新「常驻状态」（牌权链 / AI 手牌 / 补充规则 / 方向），不再把消息拼在后面。
	# 为什么（P14-E）：InfoLabel 高 88px 只够 4 行，_format_player_status() 本身就要 3~4 行，
	# 再拼一行拒绝原因就顶出边界、压在 y=152 的「桌面: …」上（真机截图里那团灰字）。
	# 消息的唯一出口是右栏 toast —— 本来两个地方就在显示同一句话，属于重复。
	if _ui.info_label and _ui.game_manager:
		_ui.info_label.text = _ui._format_player_status()
	# 同时显示居中的大号提示框（出牌不合理等错误提示醒目可见）
	_show_center_warning(text)


# 右栏警告 toast（黄底橙红边，2.5 秒自动消失）
# 位置固定在右栏上部空白格，不再压在手牌 / 操作区 / 卡牌信息之上。
# 单例复用：连续报错只更新文本并重置计时，不叠框、也不会被上一次的计时器提前熄灭。
func _show_center_warning(text: String, sticky: bool = false) -> void:
	_ensure_warning_toast()
	if not is_instance_valid(_ui._warning_toast) or not is_instance_valid(_ui._warning_label):
		return
	_ui._warning_label.text = text
	_ui._warning_toast.visible = true
	_ui._warning_seq += 1
	# sticky = 终局提示（联机终止 / 状态分叉）：不挂自动消失的计时器。
	# seq 已经自增，上一条未到期的计时器会自行作废，不会把它提前熄灭。
	if sticky:
		return
	var seq: int = _ui._warning_seq
	var timer: SceneTreeTimer = _ui.get_tree().create_timer(_ui.TOAST_DURATION)
	timer.timeout.connect(func():
		# 期间又弹了新提示（seq 变了）→ 这次计时作废
		if seq == _ui._warning_seq and is_instance_valid(_ui._warning_toast):
			_ui._warning_toast.visible = false
	)


func _ensure_warning_toast() -> void:
	if is_instance_valid(_ui._warning_toast):
		return

	var panel := Panel.new()
	panel.name = "WarningToast"
	panel.position = _ui.WARNING_TOAST_RECT.position
	panel.size = _ui.WARNING_TOAST_RECT.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _ui._make_panel_style("toast_warning"))

	var lbl := Label.new()
	lbl.position = Vector2(12, 8)
	lbl.size = _ui.WARNING_TOAST_RECT.size - Vector2(24, 16)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.05, 0.05, 1.0))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	_ui._layer(2).add_child(panel)
	_ui._warning_toast = panel
	_ui._warning_label = lbl


# 开局 / 进教程时清掉上一局残留的警告；seq 自增让未到期的计时器失效
func _hide_warning_toast() -> void:
	_ui._warning_seq += 1
	if is_instance_valid(_ui._warning_toast):
		_ui._warning_toast.visible = false
