# ============================================================
# scripts/game/GameFlow.gd
# 开局（_on_start_game / _init_game / 开始页规则下发）、退出二次确认、
# 交互回调（直接出牌 / 选牌型 / 单质·顺序·族炸 / 返回 / 跳过 / 弃牌）、
# 结果处理（_handle_result / 顺序约束弹窗）、步骤重置（_step_reset）、AI 自动出牌。
# 状态（step_mode / selected_indices / compound_selections / game_manager / ai_triggered）
# 全部留在 root。
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 3，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 2490-2636 行 --------
func _on_start_game() -> void:
	# 联机（Step 3）：开局只能由房间页 → session.start_game() 驱动。
	# 这里若不拦住，会在本地 new 一个 GameManager，直接和会话手里的那份分叉。
	if _ui.net_session != null:
		_ui._show_info("联机对局请从房间页开局（本页仅用于单机 / 教程）")
		return
	_ui._clear_net_over_notice()       # 单机新局：清掉上一局（房间 / 联机）留下的终止提示
	var total = int(_ui.player_spin.value) if _ui.player_spin else 4
	var ai = int(_ui.ai_spin.value) if _ui.ai_spin else 3
	if total < _ui.GameManagerScript.MIN_PLAYERS or total > _ui.GameManagerScript.MAX_PLAYERS:
		total = 4
	# 防御：AI 至少 1 人（0 AI 时其余座位是没人操作的人类，开局即卡死），
	# 且最多 total-1（至少给人类留 1 个座位）
	if ai < 1:
		ai = 1
		if _ui.ai_spin:
			_ui.ai_spin.value = ai
	if ai > total - 1:
		ai = total - 1
		if _ui.ai_spin:
			_ui.ai_spin.value = ai   # 只压当前值，不动 max_value（否则会把上限永久锁死）
	_ui.start_page.visible = false
	_ui.game_page.visible = true
	_ui.end_page.visible = false
	if _ui.help_page: _ui.help_page.visible = false
	_ui._close_supp_rules()
	_ui._fade_in_page(_ui.game_page)
	_init_game(total, ai)


func _on_start_tutorial(level: int) -> void:
	_ui.game_manager = _ui.GameManagerScript.new()
	var ok = _ui.game_manager.init_tutorial(level)
	if not ok:
		_show_info_simple("教程初始化失败！")
		return
	_ui.start_page.visible = false
	_ui.game_page.visible = true
	_ui.end_page.visible = false
	if _ui.help_page: _ui.help_page.visible = false
	_ui._fade_in_page(_ui.game_page)
	_step_reset()
	_ui._hotseat_ready_seat = -1   # 教程单机：顺手清零，回到主开始页也不会带着旧座位
	_ui._hide_warning_toast()   # 清掉上一局残留的警告 toast
	_ui._level0_clear_rule_tips()   # 清掉上一局第零关的规则提醒（否则会盖在教程 1/2 或正常对局的日志上）

	if level == 0:
		_ui._level0_start_phase1()
	else:
		_ui._refresh_ui()


func _connect_node(btn, cb: Callable) -> void:
	if btn: btn.pressed.connect(cb)


# ============================================================
# 七、系统操作
# ============================================================
func _on_exit_program() -> void:
	_ui.get_tree().quit()

func _on_quit_game() -> void:
	# 触屏档（C）：工具行三颗按钮本来就挨得近，「帮助」和「退出游戏」很容易点串，
	# 而退出会直接结束本局（跳结算页）。触屏改成「二次确认」：
	# 第一次点 → 按钮自己变成「确认退出?」并 3 秒倒计时，再点一次才真的结束。
	if _ui._touch_ui and not _ui._quit_confirm_pending:
		_ui._quit_confirm_pending = true
		if _ui.quit_button != null and is_instance_valid(_ui.quit_button):
			_ui.quit_button.text = "确认退出?"
		_show_info_simple("再点一次「确认退出?」结束本局（3 秒内有效）")
		_ui.get_tree().create_timer(3.0).timeout.connect(_ui._reset_quit_confirm)
		return
	_ui._quit_confirm_pending = false
	if _ui.quit_button != null and is_instance_valid(_ui.quit_button):
		_ui.quit_button.text = "退出游戏"
	# 联机（Step 3，D11）：退出 = 关闭会话，绝不写 game.phase
	#   （本端写 phase 只是本地作废，主机那份局面不受影响，客人却以为自己结束了）
	if _ui.net_session != null:
		_ui.net_session.close("主动退出对局")
		_ui._show_end_page("已退出联机对局")
		return
	if _ui.game_manager: _ui.game_manager.phase = 2
	_ui._show_end_page("游戏已退出")


# 二次确认超时回滚：按钮文字复位，下次点击重新从「退出游戏」开始
func _reset_quit_confirm() -> void:
	if not _ui._quit_confirm_pending:
		return
	_ui._quit_confirm_pending = false
	if _ui.quit_button != null and is_instance_valid(_ui.quit_button):
		_ui.quit_button.text = "退出游戏"

func _show_info_simple(text: String) -> void:
	if _ui.info_label: _ui.info_label.text = text
	else: push_warning(text)


# 开始页 4 条补充规则 → GameManager（Step 4 从 _init_game 抽出来，单机行为逐字不变）
# 联机：房主这份会进 game_start 的 config 下发给客人；客人建房时读到的值会被
# NetSession._apply_config() 用主机的配置覆盖，所以客人这边填什么都不影响牌库。
func _apply_start_page_rules(gm) -> void:
	if gm == null:
		return
	# 读取开始页的补充规则勾选框状态（三个独立勾选框，嵌在 SettingsCard 内）
	var organic_cb = _ui._start_child("OrganicCheckBox")
	if organic_cb:
		gm.organic_rules_enabled = organic_cb.button_pressed
	var seq_cb_node = _ui._start_child("SequenceCheckBox")
	if seq_cb_node:
		gm.sequence_rules_enabled = seq_cb_node.button_pressed
	var halogen_cb_node = _ui._start_child("HalogenCheckBox")
	if halogen_cb_node:
		gm.halogen_exchange_allowed = halogen_cb_node.button_pressed
	# 元素限制（P10）：前 20 号元素 + 小页里勾选的扩展元素
	var limit_cb_node = _ui._start_child("ElementLimitCheckBox")
	gm.element_limit_enabled = limit_cb_node != null and limit_cb_node.button_pressed
	gm.allowed_extra_elements = _ui._selected_extra_elements() if gm.element_limit_enabled else []


func _init_game(total: int, ai: int) -> void:
	# 新一局：教学局残留的规则提醒 / 日志缓存必须清掉，否则会跟着进正常对局
	_ui._level0_clear_rule_tips()
	_ui.log_lines.clear()
	if _ui.log_label:
		_ui.log_label.text = "游戏日志:"
	_ui.game_manager = _ui.GameManagerScript.new()
	# 读取开始页的补充规则勾选框状态（三个独立勾选框，嵌在 SettingsCard 内）
	_apply_start_page_rules(_ui.game_manager)
	var ok = _ui.game_manager.init_game(total, ai)
	if not ok:
		push_error("init_game failed with total=%d ai=%d, retrying defaults" % [total, ai])
		ok = _ui.game_manager.init_game(4, 3)
		if not ok:
			push_error("CRITICAL: init_game also failed with defaults!")
			_ui._show_end_page("初始化失败")
			return
	_step_reset()
	_ui._hotseat_ready_seat = -1   # 新一局：谁都没认领屏幕（热座第一步也要先点）
	_ui._hide_warning_toast()   # 新一局开始：隐藏上一局残留的警告 toast
	_ui._refresh_ui()


# ============================================================
# 七之一、第零关：Phase 1 — UI 标注介绍
# ============================================================


# -------- 搬运自 scripts/GameUI.gd 第 3761-3810 行 --------
func _on_auto_play() -> void:
	if _ui.game_manager == null:
		return
	var cp = _ui._view_player()
	if cp == null or cp.is_ai:
		return
	if _ui.net_session != null and not _ui._net_can_operate():
		return
	var cards = _ui._sel_cards()
	if cards.is_empty():
		_ui._show_info("请先选择要打出的牌")
		return
	_ui._clear_hint()
	var result: int = _ui._router().auto_play(cards)
	_ui._dispatch_result(result)

func _on_step_next() -> void:
	_ui._clear_hint()
	_ui.step_mode = 1
	_ui._update_action_panel()
	_ui._update_card_info_label()

func _on_element() -> void:
	var cards = _ui._sel_cards()
	if _ui.CardPatternsScript.detect_pattern(cards) != _ui.CardPatternsScript.CardPattern.ELEMENT:
		_ui._show_info("不是有效单质！")
		_on_back()
		return
	var result = _ui._router().play(cards, {}, _ui.CardPatternsScript.CardPattern.ELEMENT)
	_ui._dispatch_result(result)

func _on_sequence() -> void:
	var cards = _ui._sel_cards()
	# 玩家选择"作为顺序"：顺序优先于族炸检测（如 Fe+Co+Ni 既是族炸又是顺序）
	if _ui.CardPatternsScript.detect_pattern(cards, false, true) != _ui.CardPatternsScript.CardPattern.SEQUENCE:
		_ui._show_info("不是有效顺序！需≥3张连续原子序数的牌。")
		_on_back()
		return
	var result = _ui._router().play(cards, {}, _ui.CardPatternsScript.CardPattern.SEQUENCE)
	_ui._dispatch_result(result)

func _on_clan_bomb() -> void:
	var cards = _ui._sel_cards()
	if _ui.CardPatternsScript.detect_pattern(cards) != _ui.CardPatternsScript.CardPattern.CLAN_BOMB:
		_ui._show_info("不是有效族炸！")
		_on_back()
		return
	var result = _ui._router().play(cards, {}, _ui.CardPatternsScript.CardPattern.CLAN_BOMB)
	_ui._dispatch_result(result)



# -------- 搬运自 scripts/GameUI.gd 第 3830-4064 行 --------
func _on_confirm_mixed_valence(cv: Dictionary) -> void:
	_play_selected_compound(cv)


# 「自动配平 ▶」（P14-B）：统一价态可行解一键打出，走的是与混合价态完全相同的一条路径。
# 有了它，玩家不必靠猜「到底该选哪个价」——被拒一次就点一下，引擎自己给答案。
func _on_confirm_auto_valence(cv: Dictionary) -> void:
	_play_selected_compound(cv)


# 用给定的 {symbol: valence} 把当前选中的牌当化合物打出（统一 / 混合价态共用）
func _play_selected_compound(cv: Dictionary) -> void:
	if _ui.game_manager == null:
		return
	var ccards = _ui._sel_cards()
	if ccards.size() < 2:
		_ui._show_info("请先选择要打出的化合物卡牌！")
		return
	var result = _ui._router().play(ccards, cv.duplicate(true), _ui.CardPatternsScript.CardPattern.COMPOUND)
	_ui._dispatch_result(result)


func _on_back() -> void:
	_ui._clear_hint()
	_ui.step_mode = 0
	_ui.compound_selections.clear()
	_ui._update_action_panel()
	_ui._update_card_info_label()

func _on_pass() -> void:
	if _ui.net_session != null and not _ui._net_can_operate():
		return
	var cp = _ui._view_player()
	if cp == null:
		return
	var hand_limit = _ui.game_manager.get_hand_limit()
	if cp.get_hand_count() >= hand_limit:
		_on_discard_mode()
		return
	var code: int = _ui._router().pass_turn()
	if _ui.net_session == null:
		# 单机：与重构前逐字一致（跳过不该走 _handle_result 的「出牌成功」提示与飞牌）
		_step_reset()
		_ui._refresh_ui()
		return
	_ui._dispatch_result(code)

func _on_discard_mode() -> void:
	if _ui.net_session != null and not _ui._net_can_operate():
		return
	var cp = _ui._view_player()
	if cp == null:
		return
	var hand_limit = _ui.game_manager.get_hand_limit()
	if cp.get_hand_count() < hand_limit:
		_ui.step_mode = 0
		_ui.selected_indices.clear()
		_ui._update_action_panel()
		_ui._update_hand_buttons()
		return
	if _ui.step_mode != 3:
		_ui.step_mode = 3
		_ui.selected_indices.clear()
		_ui._show_info("手牌已达上限 (%d张)，请选择1张牌弃置。" % hand_limit)
		_ui._update_action_panel()
		_ui._update_hand_buttons()
		return
	var picked: Array = _ui._sel_cards()
	if picked.size() != 1:
		_ui._show_info("请选择恰好1张牌弃置！")
		return
	var card = picked[0]
	# 弃牌抬起（A3）：同样抢在数据层改动 / 重建之前（hand_buttons 此时还是旧的一批）
	# 联机不播：局面要等主机裁决，先飞走会让人以为已经弃掉了
	if _ui.net_session == null:
		_ui._fly_discarded_card()
	var code: int = _ui._router().discard_and_pass(card)
	if _ui.net_session == null:
		_ui.step_mode = 0
		_step_reset()
		_ui._refresh_ui()
		return
	_ui._dispatch_result(code)


# ============================================================
# 十五、结果处理与状态重置
# ============================================================
func _handle_result(result: int) -> void:
	if result == 0:  # 成功打出（普通牌型）或有机物胜利/手牌出完
		if _ui.game_manager != null and _ui.game_manager.tutorial_level0_phase == 3:
			var tip = _ui.game_manager.level0_rule_tip
			if tip == "越大越小":
				var tip_box = _ui._level0_make_tip_box("【越大越小】\n同牌型比较时，原子序数和越小的牌越大。桌面牌必须被你出的牌压过（你的牌要更大）！", 4.0)
				_ui._layer(2).add_child(tip_box)
			elif tip == "牌权争夺":
				var tip_box = _ui._level0_make_tip_box("【牌权争夺】\n你打出了族炸！族炸可以超越牌型限制，直接抢到牌权。但注意：打出族炸后进入冷却❄，需要用化合物解除。", 4.5)
				_ui._layer(2).add_child(tip_box)

		# 出牌飞入（A3）：必须抢在 _step_reset / _refresh_ui 之前 —— 那时手牌按钮还在原位。
		# 幽灵牌挂在 ContentLayer 上，_refresh_ui 重建手牌后仍然存在，随后飞向桌面小卡。
		var fly_snaps: Array = _ui._capture_play_fly_in()
		_step_reset()
		_ui._refresh_ui()
		_ui._replay_play_fly_in(fly_snaps)
		return
	elif result == 1:  # 打出顺序，需要选择指定牌型
		_step_reset()
		_show_sequence_constraint_dialog()
		return
	var msg = "非法出牌！"
	if result == -1:
		# 化合物配不平 / 牌型不成立：引擎把人话原因写在 last_reject_reason 里（P14-B）。
		# 以前 -1 只有一句「非法出牌！」，玩家根本不知道是 Σ≠0 还是多带了一张牌。
		if _ui.game_manager != null:
			var why1: String = _ui.game_manager.get_last_reject_reason()
			if why1 != "":
				msg = "非法出牌！\n" + why1
	elif result == -2:
		# 引擎把 -2 的细分原因写在 last_reject_reason 里：
		# 牌型被压制 / 族炸张数不够 / 原子序数和不够 / 与桌面打平
		msg = "牌不够大！"
		if _ui.game_manager != null:
			var why: String = _ui.game_manager.get_last_reject_reason()
			if why != "":
				msg += "\n" + why
	elif result == -3:
		var cp_err = _ui.game_manager.get_current_player() if _ui.game_manager != null else null
		if cp_err != null and cp_err.clan_bomb_cooling:
			msg = "族炸冷却中 ❄：需先打出一张化合物才能解除冷却"
		else:
			msg = "不能出族炸！"
	elif result == -4: msg = "牌型不匹配！"
	elif result == -6: msg = "不符合顺序指定的牌型约束！"
	elif result == -7: msg = "卤族元素(F/Cl/Br/I)之间不可互相化合！（可在开始页勾选『允许卤族互化』）"
	elif result == -8: msg = "该元素不在本局牌库中（已开启『元素限制』：前 20 号元素 + 自选扩展）"
	_ui._show_info(msg)
	_on_back()
	# 兜底（P14-E）：toast 2.5 秒就自动消失，把同一条拒绝原因留在手牌下方的信息栏
	# （CardInfoLabel 是 804×48、autowrap，两行放得下），下一次操作刷新时自动回到「提示: …」。
	if _ui.card_info_label:
		_ui.card_info_label.text = msg


# ============================================================
# 十五之二、顺序指定牌型弹窗
# ============================================================
func _show_sequence_constraint_dialog() -> void:
	# 创建弹窗
	var overlay = Control.new()
	overlay.anchor_left = 0
	overlay.anchor_top = 0
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.anchor_left = 0; bg.anchor_top = 0
	bg.anchor_right = 1; bg.anchor_bottom = 1
	overlay.add_child(bg)

	var panel = ColorRect.new()
	panel.color = Color(0.95, 0.95, 1, 0.97)
	panel.position = Vector2(300, 250)
	panel.size = Vector2(500, 250)
	overlay.add_child(panel)

	var title = Label.new()
	title.text = "选择下一名玩家必须打出的牌型"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.position = Vector2(320, 260)
	title.size = Vector2(460, 30)
	overlay.add_child(title)

	var desc = Label.new()
	desc.text = "打出「顺序」后，出牌方向已反转。\n请选择让下一名玩家打出哪种牌型（只约束这一名玩家，\n其他人出牌 / 族炸 / 跳过都不会替它解除），\n否则该玩家将被罚抽2张牌。"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1))
	desc.position = Vector2(320, 295)
	desc.size = Vector2(460, 65)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(desc)

	# 可选择：单质、化合物、族炸（有机物并入化合物，不单独列出）
	var patterns = [
		{"name": "单质", "pattern": _ui.CardPatternsScript.CardPattern.ELEMENT},
		{"name": "化合物", "pattern": _ui.CardPatternsScript.CardPattern.COMPOUND},
		{"name": "族炸", "pattern": _ui.CardPatternsScript.CardPattern.CLAN_BOMB},
	]

	for i in range(patterns.size()):
		var p = patterns[i].pattern
		var choose := func():
			var code: int = _ui._router().pick_sequence(p)
			overlay.queue_free()
			_ui._seq_overlay = null
			if _ui.net_session == null:
				_ui._refresh_ui()
			else:
				_ui._dispatch_result(code)
		# 与操作面板同一套按钮样式（P2 统一）
		var btn = _ui._mkb(patterns[i].name, choose, false)
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 15)
		btn.position = Vector2(320 + (i % 3) * 150, 370 + int(i / 3.0) * 50)
		overlay.add_child(btn)

	# 取消按钮（不指定，视为放弃权利）
	var cancel_cb := func():
		var code: int = _ui._router().skip_sequence()
		overlay.queue_free()
		_ui._seq_overlay = null
		if _ui.net_session == null:
			_ui._refresh_ui()
		else:
			_ui._dispatch_result(code)
	var cancel_btn = _ui._mkb("跳过指定", cancel_cb, false)
	cancel_btn.custom_minimum_size = Vector2(140, 40)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.position = Vector2(470, 370 + int(patterns.size() / 3.0) * 50 + 10)
	overlay.add_child(cancel_btn)

	_ui._layer(1).add_child(overlay)
	_ui._seq_overlay = overlay


# ============================================================
func _step_reset() -> void:
	_ui._clear_hint()
	_ui.selected_indices.clear()
	_ui.step_mode = 0
	_ui.compound_selections.clear()



# -------- 搬运自 scripts/GameUI.gd 第 4118-4159 行 --------
func _ai_auto_play() -> void:
	# 联机（Step 3，D8）：AI 只能由主机 _update_net() 代打，本入口仅单机可用
	if _ui.net_session != null:
		return
	# 定时器已消费：先还锁，auto_play() 内部那次 _refresh_ui 才会给下一家重新排程。
	# ai_armed_turn 不动 —— 万一这一手没推进回合，也不要原地空转重排。
	_ui.ai_triggered = false
	_ui.AIPlayerScript.auto_play(_ui.game_manager, _ui._refresh_ui)


# ============================================================
# 十七、验证函数（卤族互化检查）
# ============================================================
# UI 侧预检（符号数组）：与引擎 GameManager.is_halogen_mix(cards) 判据一致。
# 真正的规则判定在 play_cards()（返回 -7），这里只为「合成化合物」按钮提前挡住。
func _is_halogen_only(symbols: Array) -> bool:
	var halogen = ["F", "Cl", "Br", "I"]
	for sym in symbols:
		if sym not in halogen:
			return false
	return true


func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t = b
		b = a % b
		a = t
	return abs(a)


# ============================================================
# 十八、联机（P11-C1-c Step 3）
# ------------------------------------------------------------
# 三条不许破的线：
#   ① 单机红线：所有联机逻辑都在 `net_session != null` 分支里；不挂会话时本段代码
#      一次都不执行（44 套单机测试逐字不变）。
#   ② 视图归属（D6）：客人只看到自己的手牌 / 自己的可用牌型，与「当前行动者」无关。
#   ③ 主机权威（D1）：客人提交后返回 0 只代表「已发出」，界面一律停在
#      「已提交，等待主机裁决…」，直到 state_applied / intent_rejected 回来。
# 装配只有一个入口 attach_session()：房间页传入会话，测试传入假会话 / 真实会话。
# ============================================================

# 动作层懒装配：测试常常直接换 game_manager 而不走 attach_session，
# 这里保证「第一次动手时」router 一定指向当前的 GameManager（单机 session = null）。