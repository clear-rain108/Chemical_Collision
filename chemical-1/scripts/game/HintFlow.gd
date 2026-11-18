# ============================================================
# scripts/game/HintFlow.gd
# 「显示提示」按钮：HintAdvisor.suggest() → 自动勾选手牌 + 推进 step_mode + 写一句说明。
# 提示状态（_hint_text / _hint_owner / _hint_hand_size / _hint_order_sig）全部留在 root ——
# _update_card_info_label() 要读它们判定「提示是否作废」。
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 3，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 4317-4397 行 --------
# ============================================================
# 十、提示按钮（P6：自动选中最优可出组合 + 说明）
# ============================================================
# 交互设计（方案 C）
#   点一下 → HintAdvisor 找出「马上就能打出去」的组合 → 自动勾选手牌
#   并把 step_mode 推到对应的下一步（化合物直接到「确认打出」）
#   → 玩家只需再点一次面板按钮即可出牌
# 再点一下（toggle 取消）→ 清空提示，不动已选的牌
func _on_hint_toggled(pressed: bool) -> void:
	if not pressed:
		_clear_hint()
		_ui._update_card_info_label()
		return
	# 热座交接未认领：提示会暴露「有没有能打的组合」，也等于替下一位玩家先看了牌
	if _ui._hotseat_handoff_pending():
		if _ui.hint_button != null and is_instance_valid(_ui.hint_button):
			_ui.hint_button.set_pressed_no_signal(false)
		return
	_apply_hint()


func _apply_hint() -> void:
	if _ui.game_manager == null or _ui.game_manager.is_game_over():
		return
	# 联机（Step 3）：只有轮到我、且没有待裁决 / 待选牌型时才给提示 ——
	# HintAdvisor 读的是「当前行动者」的手牌，别人回合点提示等于偷看别人的牌
	if _ui.net_session != null and not _ui._net_can_operate():
		return
	var cp = _ui.game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return

	var adv: Dictionary = _ui.HintAdvisorScript.suggest(_ui.game_manager)
	if adv.is_empty():
		_clear_hint()
		_ui._hint_text = "提示：当前没有能直接打出的组合，建议「跳过」或按上限弃牌。"
		_ui._hint_owner = _ui.game_manager.get_current_player_index()
		_ui._hint_hand_size = cp.hand.size()
		_ui._hint_order_sig = _ui._hand_order_sig(cp)
		_ui._update_card_info_label()
		return

	# 1) 勾选手牌（顺序稳定：按手牌下标升序，卡面重叠时高亮看起来更自然）
	var idxs: Array = adv["indices"].duplicate()
	idxs.sort()
	_ui.selected_indices.clear()
	for i in idxs:
		_ui.selected_indices.append(int(i))

	# 2) 化合物把化合价也填好，玩家直接点「确认打出」；其余牌型停在选牌型面板
	_ui.compound_selections.clear()
	var pattern: int = adv["pattern"]
	if pattern == _ui.CardPatternsScript.CardPattern.COMPOUND:
		var val: Dictionary = adv["valence"]
		for sym in val:
			_ui.compound_selections.append({"symbol": sym, "valence": val[sym]})
		_ui.step_mode = 2
	else:
		_ui.step_mode = 1
		_ui.compound_selections.clear()

	_ui._hint_text = adv["text"]
	_ui._hint_owner = _ui.game_manager.get_current_player_index()
	_ui._hint_hand_size = cp.hand.size()
	_ui._update_hand_buttons()
	# 重建时可能自动排序（自动排列模式），签名必须在刷新之后取，
	# 否则签名与真实顺序不一致，提示会在下一次刷新时被误判成"局面已变"而作废
	_ui._hint_order_sig = _ui._hand_order_sig(cp)
	_ui._update_action_panel()
	_ui._update_card_info_label()


func _clear_hint() -> void:
	_ui._hint_text = ""
	_ui._hint_owner = -1
	_ui._hint_hand_size = -1
	_ui._hint_order_sig = ""
	# 牌被改动 / 局面推进后，提示按钮不能继续按着，否则下次点击会先触发「取消」
	if _ui.hint_button != null and is_instance_valid(_ui.hint_button) and _ui.hint_button.button_pressed:
		_ui.hint_button.set_pressed_no_signal(false)

