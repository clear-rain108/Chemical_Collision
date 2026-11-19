# ============================================================
# scripts/ui/HandView.gd
#
# 由 tools/move_funcs.gd 从 scripts/GameUI.gd 机械搬运（Slice 2a，纯搬运）。
# 约定：状态与常量留在 root，模块只经 _ui 读写；不缓存判定结果、不复制字段。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 搬运自 scripts/GameUI.gd 第 4398-4639 行 --------
# ============================================================
# 十二、手牌渲染（原子牌面）
# ============================================================
func _update_hand_buttons() -> void:
	if not _ui.hand_container or not _ui.game_manager: return
	var actor = _ui.game_manager.get_current_player()
	# 视角座位：单人类模式永远看自己（AI 回合只读）；热座模式只看当前人类。
	# 旧实现在 AI 回合直接把手牌区换成一句「等待 XX 行动中...」，
	# 玩家整轮看不到自己的牌 → 改成始终显示自己的手牌，只是不可操作。
	var view = _ui._hand_view_player(actor)
	if _ui.net_session != null:
		# 联机（Step 3，D6）：只读与否只看「是不是我这一手」，与 actor 无关：
		#   别人回合 / 已提交待裁决 / 待我选牌型 → 只读（看得到自己牌，点不动）
		_ui._hand_read_only = view == null or not _ui._net_can_operate()
	else:
		_ui._hand_read_only = view != null and actor != null and view != actor
	# 拖拽幽灵牌 / 指示线也是容器子节点，重建前必须收掉，否则引用悬空
	_ui._cancel_drag()

	# -------- 复用路径（Slice 2b）--------
	# 「牌还是那几张、顺序也没变」时，画面里真正会变的只有**状态**：选中 / 只读 /
	# 重叠间距（容器改宽）/ 紧凑档。旧实现一律整排重建：n 个 Button + 5n 个 Label
	# 全部销毁重造、价态文本逐张重新测量、入场补间全部 kill —— 一次点选、一次状态
	# 刷新就能卡一帧。这里改成节点零增删：只重刷样式 / 层级，再按当前几何重新落位。
	# 判据用**卡片对象**而不是索引：拖拽 / 排序后索引会变，对象不会。
	if _can_reuse_hand_buttons(view):
		# 悬停状态与旧行为保持一致：重建会清掉悬停，再按当前鼠标位置重新判定。
		# 复用路径同样清零 —— 否则 _hover_idx 会残留（状态机以为牌还抬着，
		# 玩家真移上去时 _set_hover_index 直接早退，牌就再也不浮起来）。
		_ui._restore_card_info()
		_ui._hover_idx = -1
		_ui._hover_pending_idx = -1
		_refresh_all_card_visuals()
		_ui._layout_hand_cards()
		# 抽牌 / 发牌入场（A3）：只对「没见过的卡片对象」播一次 —— 复用路径同样要判一次，
		# 因为手牌对象可能一个都没变、但玩家确实是刚抽到它（_hand_seen_cards 被清过）
		_ui._animate_new_hand_cards()
		if not _ui._hand_read_only:
			_ui._restore_hover_after_rebuild()
		_update_ai_schedule(actor)
		_ui._update_hand_reorder_button()
		return

	# -------- 重建路径：牌换了 / 顺序变了 / 视角空了 --------
	# 重建会销毁当前 hover 的按钮，先还原信息栏，避免详情文本滞留
	_ui._restore_card_info()
	# 选中快照必须抢在 hand_buttons.clear() 之前：旧按钮上的 card meta 是
	# 「玩家看见并点中的那张牌」的唯一可靠来源（数据层顺序可能已被拖拽 / 抽牌排序改过）
	var keep_selected: Array = _ui._selected_cards(view)
	# 旧按钮即将销毁，悬停状态机必须一并清零，否则会指向失效索引
	_ui._hover_idx = -1
	_ui._hover_pending_idx = -1
	# 先 remove_child 再 queue_free：避免旧牌残留在容器中干扰重叠布局
	# 发牌入场的补间挂在旧按钮上，重建前先杀掉 —— 否则补间会去碰已释放的节点（脚本报错）
	for child in _ui.hand_container.get_children():
		var old_deal = child.get_meta("deal_in_tween", false)
		if old_deal is Tween and old_deal.is_valid():
			old_deal.kill()
		_ui.hand_container.remove_child(child)
		child.queue_free()
	_ui.hand_buttons.clear()

	_update_ai_schedule(actor)

	if view == null:
		# 热座的 AI 回合：谁的牌都不能显示（同屏多人会互相看到手牌）
		if actor != null:
			var wl = Label.new()
			wl.text = "等待 %s 行动中..." % actor.player_name
			if _ui.net_session != null and _ui.net_session.is_watcher():
				wl.text = "观战中：不显示任何玩家的手牌"
			wl.add_theme_font_size_override("font_size", 28)
			# 手牌区背景是浅蓝，默认白色字几乎不可见
			wl.add_theme_color_override("font_color", Color(0.33, 0.4, 0.5, 1))
			# Control 容器不会自动布局子节点，需显式定位
			wl.position = Vector2(200, 20)
			wl.size = Vector2(420, 48)
			_ui.hand_container.add_child(wl)
		_ui._update_hand_reorder_button()
		return

	# 热座交接：多人类同屏时，轮到某个真人先盖住手牌区，
	# 由 TA 自己点一下再展示 —— 否则上一位玩家的牌会直接摊在下一位面前（同一块屏）。
	if _ui._hotseat_handoff_pending():
		_ui._render_hotseat_handoff(actor)
		_ui._update_hand_reorder_button()
		return

	# 只读视角不能排序：自动排序会把手动排列覆盖掉，而玩家此刻并不能操作
	if not _ui._hand_read_only:
		# 自动排列模式下这里会排序；手动排列模式直接返回，玩家排好的顺序得以保留
		view.sort_hand_by_atomic_number()
	# 顺序可能已变 → 用卡片对象把选中索引重算一遍
	_ui._remap_selection(view, keep_selected)
	for i in range(view.hand.size()):
		var card = view.hand[i]
		var btn = _ui._build_card_button(card, i)
		# 只读：不接鼠标（保持视觉不变，也不会误改选中态）
		if _ui._hand_read_only:
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.hand_container.add_child(btn)
		_ui.hand_buttons.append(btn)
	_ui._layout_hand_cards()
	if not _ui._hand_read_only:
		_ui._restore_hover_after_rebuild()
	# 抽牌 / 发牌入场（A3）：只对新出现的卡片对象做一次淡入
	_ui._animate_new_hand_cards()
	# 「按序」按钮只在「手动排列 + 可操作阶段」出现
	_ui._update_hand_reorder_button()


# 旧按钮能否直接复用：牌数相同、逐张对象相同（顺带覆盖了「顺序变了」）
# view 为 null（热座 AI 回合 / 观战）时一律走重建 —— 那时手牌区本来就不该有牌
func _can_reuse_hand_buttons(view) -> bool:
	if view == null or _ui.hand_buttons.is_empty():
		return false
	if _ui.hand_buttons.size() != view.hand.size():
		return false
	for i in range(view.hand.size()):
		var b = _ui.hand_buttons[i]
		if not is_instance_valid(b) or b.get_meta("card", null) != view.hand[i]:
			return false
	return true


# 复用路径：把每张牌的「状态相关」外观重刷一遍（样式 / 层级 / 鼠标过滤），
# 位置与缩放交给紧随其后的 _layout_hand_cards()（瞬时整排落位）。
func _refresh_all_card_visuals() -> void:
	for i in range(_ui.hand_buttons.size()):
		_apply_card_state_style(i)


# 选中 / 只读 / 悬停 三条状态 → 样式 + 层级 + 鼠标过滤（不动位置与缩放）
func _apply_card_state_style(idx: int) -> void:
	if idx < 0 or idx >= _ui.hand_buttons.size():
		return
	var btn = _ui.hand_buttons[idx]
	if not is_instance_valid(btn):
		return
	# 入场补间还没走完就来了状态刷新：旧实现是靠「重建 + kill」收尾的，
	# 复用路径必须自己做同样的事 —— 否则它会在之后 300ms 里一直改 position，
	# 把悬停抬起 / 选中落位的补间顶掉（实测：按住抬到 20 被拉回 18）。
	var old_deal = btn.get_meta("deal_in_tween", false)
	if old_deal is Tween and old_deal.is_valid():
		old_deal.kill()
		btn.modulate = Color(1, 1, 1, 1)
	var is_selected: bool = idx in _ui.selected_indices
	# 两套样式仍出自工厂（数值唯一真源）；高频重绘用共享模板，零分配
	var sb_normal = _ui._panel_style_template("card_selected" if is_selected else "card")
	var sb_hover = _ui._panel_style_template("card_hover_selected" if is_selected else "card_hover")
	btn.set_meta("sb_normal", sb_normal)
	btn.set_meta("sb_hover", sb_hover)
	# 悬停中的牌保持 hover 外观（否则刚选中的牌会被 normal 样式「按回」未悬停态）
	var sb = sb_hover if idx == _ui._hover_idx else sb_normal
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	# 层级：悬停 > 选中 > 普通（与 _apply_hover / _layout_hand_cards 同规则）
	if idx == _ui._hover_idx:
		btn.z_index = _ui.Z_HAND_HOVER
	else:
		btn.z_index = _ui.Z_HAND_SELECTED if is_selected else 0
	# 只读：牌只做展示，不接鼠标（否则会误改选中态）
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if _ui._hand_read_only else Control.MOUSE_FILTER_STOP
	# 触屏档字号（号码 / 族名 / 原子量）只在构建时写过一次：档位变了必须补刷，
	# 否则切到触屏后复用旧按钮，这三处还是桌面小字（符号 / 名称 / 价态由 layout 重算，不用管）
	if btn.get_meta("touch_fonts", not _ui._touch_ui) != _ui._touch_ui:
		_apply_card_build_fonts(btn)
		btn.set_meta("touch_fonts", _ui._touch_ui)


# 牌面上「只在构建时写一次」的字号：触屏档需要整体放大
func _apply_card_build_fonts(btn: Button) -> void:
	var l_num = btn.get_node_or_null("CardNumber")
	if l_num != null:
		l_num.add_theme_font_size_override("font_size", _ui._touch_fs(12, 2))
	var l_group = btn.get_node_or_null("CardGroup")
	if l_group != null:
		l_group.add_theme_font_size_override("font_size", _ui._touch_fs(11, 2))
	var l_mass = btn.get_node_or_null("CardMass")
	if l_mass != null:
		l_mass.add_theme_font_size_override("font_size", _ui._touch_fs(9, 3))


# AI 调度与手牌渲染解耦：即使显示的是玩家自己的牌，也要继续推动 AI 行动。
# 联机（Step 3，D8）：AI 只能由主机 _update_net() 代打（走 host_step_ai → 广播）。
#   客人若也跑这个计时器，就是本地私自 play_cards → 立刻与主机分叉。
# 复用路径与重建路径都要走这里 —— 否则 AI 回合里手牌没变化 → 不重建 → AI 永远不动。
func _update_ai_schedule(actor) -> void:
	var gm = _ui.game_manager
	var ai_acting: bool = actor != null and actor.is_ai and not gm.is_game_over()
	# 非 AI 回合 / 联机：本地不该挂着 AI 定时器（联机一律由主机 host_step_ai 代打）
	if not ai_acting or _ui.net_session != null:
		_ui.ai_triggered = false
		_ui.ai_armed_turn = -1
		_ui.ai_armed_actor = -1
		return
	# 同一手只排一次。复位与置位都必须写在这里 —— 上面的「复用路径」会提前 return，
	# 把复位留在重建分支（Slice 2b 的回归）会让闸门永久停在 true：第一台 AI 打完，
	# 手牌没变化 → 不重建 → 第二台 AI 排不上定时器 → 整局卡死。
	# 令牌用 gm.turn_count：next_turn / _intercept_next / _start_new_round / _finish_clan_bomb_chain 四条换手
	# 路径都会 +1（set_sequence_constraint 也走 next_turn），是「这一手」的天然编号。
	# 令牌是「回合号 + 行动者」双键：单看回合号不够，_finish_clan_bomb_chain()
	# 是族炸接炸链终局那条换手路径：它曾经不推进回合号，只看回合号会误判「已排过」而卡死。
	if _ui.ai_armed_turn == gm.turn_count and _ui.ai_armed_actor == actor.get_instance_id():
		return
	_ui.ai_armed_turn = gm.turn_count
	_ui.ai_armed_actor = actor.get_instance_id()
	_ui.ai_triggered = true
	var timer = _ui.get_tree().create_timer(1.5)
	timer.timeout.connect(_ui._ai_auto_play)


# 人类座位列表（PlayerManager 保证人类排在 0..H-1，H = 总人数 - AI 数）
func _human_players() -> Array:
	var out: Array = []
	if _ui.game_manager == null:
		return out
	for p in _ui.game_manager.players:
		if p != null and not p.is_ai:
			out.append(p)
	return out


# 手牌视角座位：
#   单人类（1 人 + N AI）：永远看自己；AI 回合只读 → 修掉「AI 回合看不到自己的牌」
#   热座（多人类）    ：只看当前人类；AI 回合返回 null，由调用方显示等待提示
#                        （同屏多人绝不能同时显示各自手牌）
# 联机改造（P11-C1-c Step 3，D6）：联机时视角恒为「自己的座位」，
# 与「当前行动者」无关 —— 客人永远只看到自己的牌，轮到别人时手牌只读。
func _hand_view_player(actor):
	if _ui.game_manager == null:
		return null
	if _ui.net_session != null:
		return _ui._view_player()
	var a = actor
	if a == null:
		a = _ui.game_manager.get_current_player()
	if a == null:
		return null
	var humans: Array = _ui._human_players()
	if humans.size() <= 1:
		if a.is_ai:
			return humans[0] if humans.size() == 1 else a
		return a
	if a.is_ai:
		return null
	return a


# -------- 热座交接（B2）--------
# 同屏多人类时，谁轮到谁就得先「认领」屏幕：手牌默认盖住，本人点一下才展示。
# 单人类（1 人 + N AI）用不上 —— 只有一个能看牌的人，遮罩只会多一步点击。
# 联机（Step 3，D7）恒为 false：每个玩家盯自己那块屏，同屏交接遮罩只会把对局卡死。
func _is_hotseat() -> bool:
	if _ui.net_session != null:
		return false
	return _ui._human_players().size() >= 2


# 当前是否「该展示手牌但还没人认领」：只有热座 + 当前是人类时才成立
func _hotseat_handoff_pending() -> bool:
	if _ui.game_manager == null or not _ui._is_hotseat():
		return false
	var cp = _ui.game_manager.get_current_player()
	if cp == null or cp.is_ai:
		return false
	return _ui._hotseat_ready_seat != _ui.game_manager.get_current_player_index()


# 认领成功：记下座位并立刻重画手牌 / 操作面板
func _on_hotseat_handoff_confirmed() -> void:
	if _ui.game_manager == null:
		return
	_ui._hotseat_ready_seat = _ui.game_manager.get_current_player_index()
	_ui._update_hand_buttons()
	_ui._update_action_panel()
	_ui._update_card_info_label()


# 交接遮罩：整块盖住手牌区（此帧根本没有渲染任何牌，遮罩只是「请先认领」的入口）
func _render_hotseat_handoff(actor) -> void:
	if _ui.hand_container == null or not is_instance_valid(_ui.hand_container):
		return
	var who: String = actor.player_name if actor != null else "下一位玩家"
	var btn := Button.new()
	btn.name = "HotseatHandoffBtn"
	btn.position = Vector2.ZERO
	btn.size = _ui.hand_container.size
	btn.text = "轮到 %s · 点击查看手牌" % who
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	# 与操作面板按钮同一套样式，玩家一眼能认出「这是个要点的按钮」
	var style = _ui._make_panel_style("button")
	btn.add_theme_stylebox_override("normal", style)
	var style_hover = style.duplicate()
	style_hover.bg_color = Color(0.27, 0.38, 0.5, 1.0)
	style_hover.border_color = Color(0.55, 0.75, 0.95, 1.0)
	btn.add_theme_stylebox_override("hover", style_hover)
	var style_pressed = style.duplicate()
	style_pressed.bg_color = Color(0.12, 0.17, 0.23, 1.0)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.pressed.connect(_ui._on_hotseat_handoff_confirmed)
	_ui.hand_container.add_child(btn)

	# 副提示（Button 不支持多行文本）→ 单独 Label 盖在按钮内，不能吃鼠标
	var tip := Label.new()
	tip.name = "HotseatHandoffTip"
	tip.text = "请先把屏幕交给 %s，其他人回避后再点击" % who
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	tip.position = Vector2(0, _ui.hand_container.size.y - 44.0)
	tip.size = Vector2(_ui.hand_container.size.x, 26)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tip)


# -------- 选中状态：索引 ↔ 卡片对象 的双向保护 --------
# selected_indices 只能存索引（出牌 / 化合价等处都按索引用），
# 所以顺序一变就必须用卡片对象把索引重新算出来，不能直接沿用旧索引。
func _selected_cards(cp) -> Array:
	var out: Array = []
	if cp == null: return out
	for idx in _ui.selected_indices:
		var i: int = int(idx)
		if i < 0:
			continue
		var card = null
		# 优先用「上一帧渲染的按钮」取对象：数据层顺序可能已经被外部改掉
		# （拖拽落库、抽牌后自动排序），旧索引对不上新数组，但按钮 meta 里
		# 记的仍是玩家真正看见并点中的那张牌
		if i < _ui.hand_buttons.size() and is_instance_valid(_ui.hand_buttons[i]) \
				and _ui.hand_buttons[i].has_meta("card"):
			card = _ui.hand_buttons[i].get_meta("card")
		elif i < cp.hand.size():
			card = cp.hand[i]
		if card != null:
			out.append(card)
	return out


func _remap_selection(cp, cards: Array) -> void:
	_ui.selected_indices.clear()
	if cp == null: return
	for card in cards:
		var at: int = cp.hand.find(card)
		# 同一张牌在手牌里最多出现一次；重复引用（测试里补牌会出现）只保留首个
		if at >= 0 and not _ui.selected_indices.has(at):
			_ui.selected_indices.append(at)


# 手牌顺序签名：原子序数 + 符号按当前顺序拼起来。
# 提示（_hint_text）靠它判断"玩家是否动过这张牌的位置"，顺序一变提示立即作废。
func _hand_order_sig(cp) -> String:
	if cp == null:
		return ""
	var parts: Array = []
	for c in cp.hand:
		parts.append("%d%s" % [c.atomic_number, c.symbol])
	return ",".join(parts)



# -------- 搬运自 scripts/GameUI.gd 第 4641-4960 行 --------
# -------- 手牌重叠排列：一行居中，牌多时自动压缩间距 --------
func _layout_hand_cards() -> void:
	if not _ui.hand_container: return
	var n = _ui.hand_buttons.size()
	if n == 0: return
	var avail = _ui.hand_container.size.x
	# 不叠卡时能容纳的最大张数；超过后主动叠起（step 上限 CARD_STEP_MAX）
	var plain_max: int = int((avail + _ui.CARD_GAP) / (_ui.CARD_W + _ui.CARD_GAP))
	var step = _ui.CARD_W + _ui.CARD_GAP
	if n > plain_max and n > 1:
		step = min(_ui.CARD_STEP_MAX, (avail - _ui.CARD_W) / float(n - 1))
	var total = _ui.CARD_W + step * (n - 1)
	var start_x = max(0.0, (avail - total) * 0.5)
	var base_y = _ui.hand_container.size.y - _ui.CARD_H - _ui.HOVER_LIFT
	# 重叠到露出不足 72% 时切换紧凑牌面（内容靠左，保证露出的左条整齐可读）
	var compact = step < _ui.CARD_W * 0.72
	for i in range(n):
		var btn = _ui.hand_buttons[i]
		if not is_instance_valid(btn): continue
		btn.size = Vector2(_ui.CARD_W, _ui.CARD_H)
		# 重排会覆盖 position：先杀掉进行中的升降补间，否则动画会把牌拉回旧位置
		_ui._kill_hover_tween(btn)
		# 缩放同理：重排是「瞬时整排落位」，残留的缩放补间会把牌撑在 1.06 上
		_ui._kill_scale_tween(btn)
		btn.pivot_offset = Vector2(_ui.CARD_W, _ui.CARD_H) * 0.5
		# 悬停中的牌保持放大档（重建后 _hover_idx 不变，状态机不会重新触发）
		var sc: float = _ui.HAND_HOVER_SCALE if i == _ui._hover_idx else (_ui.HAND_SELECT_SCALE if i in _ui.selected_indices else 1.0)
		btn.scale = Vector2(sc, sc)
		var at_x: float = start_x + i * step
		# 触屏档（C）：选中的牌常驻上浮 TOUCH_SELECT_LIFT（≈7dp），与「悬停 20」区分 ——
		# 触屏没有悬停语义，不加这个就完全看不出选了哪几张，容易重复点/漏点。
		# base_pos 必须存「未上浮」的静止位置：命中判定 / 拖拽 / 悬停全都基于它。
		var lift: float = _ui._selected_lift() if i in _ui.selected_indices else 0.0
		btn.position = Vector2(at_x, base_y - lift)
		btn.set_meta("base_pos", Vector2(at_x, base_y))
		btn.set_meta("hand_idx", i)
		btn.z_index = _ui.Z_HAND_SELECTED if i in _ui.selected_indices else 0
		_ui._apply_card_compact(btn, compact)


# -------- 紧凑牌面：重叠时内容左对齐，保证左侧可见区域信息完整 --------
func _apply_card_compact(btn: Button, compact: bool) -> void:
	var sym = btn.get_node_or_null("CardSymbol")
	if sym:
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		sym.position = Vector2(6, 22) if compact else Vector2(5, 20)
		sym.size = Vector2(44, 26) if compact else Vector2(85, 26)
		sym.add_theme_font_size_override("font_size", _ui._touch_fs(21 if compact else 28, 4))
	var nm = btn.get_node_or_null("CardName")
	if nm:
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
		nm.position = Vector2(6, 49) if compact else Vector2(5, 48)
		nm.size = Vector2(44, 15) if compact else Vector2(85, 15)
		nm.add_theme_font_size_override("font_size", _ui._touch_fs(12 if compact else 14, 2))
	var chip = btn.get_node_or_null("CardValenceChip")
	var vl = chip.get_node_or_null("CardValence") if chip else null
	if chip and vl:
		# 行几何交给 chip 的 meta：紧凑档左对齐（露出左条要读得到），常规档居中。
		# 文字自身永远在粉底内居中 —— 粉底就是它的父节点，不可能再错位。
		var row_w: float = 44.0 if compact else 85.0
		chip.set_meta("row_x", 6.0 if compact else 5.0)
		chip.set_meta("row_w", row_w)
		chip.set_meta("row_align", HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 行宽先扣掉两侧 padding，保证 fit 出来的文字两侧恒有 CHIP_PAD 的粉底余量
		var card = btn.get_meta("card") if btn.has_meta("card") else null
		_ui._fit_card_valence(vl, card, row_w - _ui.CARD_VAL_CHIP_PAD * 2.0, _ui._touch_fs(13, 2))


# ============================================================
# 十二之二、手牌拖拽重排（P7）
# ============================================================
# 为什么用 _process 轮询而不是 gui_input：
#   Control 的 gui_input 信号与 Button 内部的 _gui_input 处理作用在同一个控件上，
#   accept_event() 只能阻止事件继续传给其他控件，挡不住这个 Button 自己补发的
#   pressed —— 拖完松手会顺带把那张牌选中。这里沿用项目已有的 _process 轮询风格，
#   用 _drag_suppress_click 明确吞掉拖拽后的那次 pressed，行为可预测。
# 顺序真源：拖动只改 PlayerInfo.hand 的数组顺序，界面每次重建照抄，不存第二套顺序。

# 当前局面是否允许拖拽（教程关 / 非选牌阶段 / 非玩家回合一律禁止）
func _can_reorder_hand() -> bool:
	if _ui.game_manager == null or _ui.game_manager.is_game_over():
		return false
	# 只读视角（AI 回合查看自己的牌）不许改顺序
	if _ui._hand_read_only:
		return false
	# 联机（Step 3）：只有「轮到我、且没有待裁决 / 待选牌型」才允许拖
	if _ui.net_session != null and not _ui._net_can_operate():
		return false
	# 热座交接未认领：手牌还盖着，重排按钮 / 拖拽都该消失
	if _ui._hotseat_handoff_pending():
		return false
	# 教程关：只有第零关「UI 标注 / 流程介绍」阶段禁用（高亮框按固定坐标绘制，拖牌会让提示错位）；
	# 第零关练习阶段（phase 3）与第一 / 二关都允许重排 —— 实测反馈「教程里手牌不能拖」
	# 注意 tutorial_level==0 也是「自由模式」的默认值，必须看 tutorial_level0_phase 才能区分
	if _ui.game_manager.tutorial_level == 0 and _ui.game_manager.tutorial_level0_phase >= 1 \
			and _ui.game_manager.tutorial_level0_phase < 3:
		return false
	# 只在「选牌 / 弃牌」阶段允许，选牌型 / 选化合价时手牌是只读参照
	if _ui.step_mode != 0 and _ui.step_mode != 3:
		return false
	if _ui.hand_container == null or not is_instance_valid(_ui.hand_container):
		return false
	if not _ui.hand_container.is_visible_in_tree():
		return false
	if _ui.game_page == null or not _ui.game_page.visible:
		return false
	return true


# 每帧驱动拖拽状态机（headless 无真实鼠标，直接跳过）
func _update_hand_drag() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _ui._drag_active:
			_ui._finish_drag()
		_ui._drag_press_idx = -1
		return
	if _ui._drag_active:
		_ui._update_drag_follow()
		return
	if not _ui._can_reorder_hand():
		_ui._drag_press_idx = -1
		return
	if _ui._drag_press_idx < 0:
		# 首次检测到按下：直接用命中判定取源牌，不依赖悬停状态机是否已经抬起
		# （压在 60ms 稳定延迟内的快速拖动也能立刻生效）
		# 用 _hit_card_at：已抬起的牌压住相邻牌，它的绘制区归它自己
		var mp: Vector2 = _ui.hand_container.get_local_mouse_position()
		var hit: int = _ui._hit_card_at(mp)
		if hit >= 0:
			_ui._drag_press_idx = hit
			_ui._drag_press_pos = _ui.get_global_mouse_position()
			_ui._drag_max_move = 0.0
			_ui._drag_suppress_click = false
		return
	if _ui._drag_press_idx >= _ui.hand_buttons.size():
		_ui._drag_press_idx = -1
		return
	# 未达起拖位移 = 普通点击，交给 Button 自己的 pressed
	var moved: float = _ui.get_global_mouse_position().distance_to(_ui._drag_press_pos)
	_ui._drag_max_move = maxf(_ui._drag_max_move, moved)
	if moved >= _ui._drag_arm_threshold():
		# 触屏档（C）：10px 就起拖（手指一动牌就跟），不再等 300ms 长按 ——
		# 旧实现「长按 300ms + 24px」在真机上是「按住后牌不动、松手还点不中」，
		# 现在把判定挪到松手时：总位移 <24px 一律按点选处理（见 _finish_drag）。
		_ui._begin_drag(_ui._drag_press_idx)


func _begin_drag(idx: int) -> void:
	if idx < 0 or idx >= _ui.hand_buttons.size():
		return
	var btn = _ui.hand_buttons[idx]
	if not is_instance_valid(btn):
		return
	_ui._drag_active = true
	_ui._drag_from = idx
	_ui._drag_slot = idx
	# 拖拽期间吞掉 Button 补发的 pressed，避免"拖完顺带选中"
	_ui._drag_suppress_click = true
	# 收起悬停态：牌要淡出，抬起补间和详情文本都得先还原
	_ui._set_hover_index(-1)
	_ui._restore_card_info()
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	_ui._drag_grab = _ui.hand_container.get_local_mouse_position() - base
	# 触屏档：10px 就起拖（远早于 24px 的确认阈值），此刻可能只是「想点选但手抖」——
	# 所以软启动：源牌只淡到 0.55、幽灵牌提到 0.9；若最终回退成点选，视觉上不会闪一下深灰。
	if _ui._touch_ui:
		btn.modulate = Color(1, 1, 1, _ui.TOUCH_DRAG_SOURCE_ALPHA)
		_ui._drag_ghost = _ui._make_drag_ghost(btn, _ui.TOUCH_DRAG_GHOST_ALPHA)
	else:
		btn.modulate = Color(1, 1, 1, _ui.DRAG_SOURCE_ALPHA)
		_ui._drag_ghost = _ui._make_drag_ghost(btn)
	_ui._drag_line = _ui._make_drag_line()
	_ui._update_drag_follow()


# 幽灵牌：复制被拖的牌（复刻牌面），只要不吃鼠标就不会干扰判定
func _make_drag_ghost(src: Button, alpha: float) -> Control:
	var ghost := src.duplicate() as Control
	if ghost == null:
		return null
	ghost.name = "DragGhost"
	ghost.z_index = _ui.Z_DRAG
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.modulate = Color(1, 1, 1, alpha)
	_ui.hand_container.add_child(ghost)
	return ghost


# 插入位置指示线（主题蓝竖线，高度与牌同高）
func _make_drag_line() -> ColorRect:
	var line := ColorRect.new()
	line.name = "DragInsertLine"
	line.color = _ui.BORDER_FOCUS
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.z_index = _ui.Z_DRAG
	line.size = Vector2(_ui.DRAG_LINE_W, _ui.CARD_H)
	_ui.hand_container.add_child(line)
	return line


func _update_drag_follow() -> void:
	var mp: Vector2 = _ui.hand_container.get_local_mouse_position()
	# 累计最大位移：跟手位置可能来回晃，但「松手时判点选」只看这次按下走过多远
	_ui._drag_max_move = maxf(_ui._drag_max_move, _ui.get_global_mouse_position().distance_to(_ui._drag_press_pos))
	if is_instance_valid(_ui._drag_ghost):
		_ui._drag_ghost.position = mp - _ui._drag_grab
	_ui._drag_slot = _ui._insert_slot_at(mp.x)
	if is_instance_valid(_ui._drag_line):
		var lx: float = _ui._slot_x(_ui._drag_slot)
		_ui._drag_line.position = Vector2(lx - _ui.DRAG_LINE_W * 0.5, _ui._hand_base_y())
		_ui._drag_line.size = Vector2(_ui.DRAG_LINE_W, _ui.CARD_H)


# 插入槽位：鼠标落在哪张牌中点的左侧就插在它前面，全在右侧则插到末尾
func _insert_slot_at(x: float) -> int:
	var n: int = _ui.hand_buttons.size()
	for i in range(n):
		var b = _ui.hand_buttons[i]
		if not is_instance_valid(b):
			continue
		var bx: float = b.get_meta("base_pos", b.position).x
		if x < bx + _ui.CARD_W * 0.5:
			return i
	return n


# 槽位对应的 x（用静止坐标 base_pos，不受落下补间影响）
func _slot_x(slot: int) -> float:
	var n: int = _ui.hand_buttons.size()
	if n == 0:
		return _ui.hand_container.size.x * 0.5
	if slot < 0:
		slot = 0
	if slot < n:
		var b = _ui.hand_buttons[slot]
		if is_instance_valid(b):
			return b.get_meta("base_pos", b.position).x
	var last = _ui.hand_buttons[n - 1]
	if is_instance_valid(last):
		return last.get_meta("base_pos", last.position).x + _ui.CARD_W
	return _ui.hand_container.size.x * 0.5


func _hand_base_y() -> float:
	return _ui.hand_container.size.y - _ui.CARD_H - _ui.HOVER_LIFT


# 松手：槽位 → 目标下标 → 改数据层顺序 → 整排重建
# drop_pos 默认取真实鼠标位置；自动化测试（headless 鼠标恒在 0,0）可注入落点
func _finish_drag(drop_pos: Vector2) -> void:
	if not _ui._drag_active:
		return
	var from: int = _ui._drag_from
	var slot: int = _ui._drag_slot
	var gp: Vector2 = _ui.get_global_mouse_position() if drop_pos == Vector2.INF else drop_pos
	var in_zone: bool = _ui.hand_container.get_global_rect().has_point(gp)
	# 触屏档：起拖门槛只有 10px（为了跟手），松手时总位移仍不到 24px → 判为「点选」。
	# 这样手指小幅抖动既能看到牌跟手，也不会丢掉那次点击（历史 bug：点击被吞 = 点了没反应）。
	# 这里必须走 _apply_card_selection：pressed 已被 _drag_suppress_click 吞掉，不会重复选中。
	if _ui._touch_ui and from >= 0 and _ui._drag_max_move < _ui._drag_threshold():
		_ui._reset_drag_visuals()
		_ui._drag_active = false
		_ui._drag_from = -1
		_ui._drag_slot = -1
		_ui._drag_press_idx = -1
		_ui._apply_card_selection(from)
		call_deferred("_clear_drag_suppress")
		return
	_ui._reset_drag_visuals()
	_ui._drag_active = false
	_ui._drag_from = -1
	_ui._drag_slot = -1
	_ui._drag_press_idx = -1
	var cp = _ui.game_manager.get_current_player() if _ui.game_manager != null else null
	var moved: bool = false
	if in_zone and cp != null and not cp.is_ai and from >= 0 and slot >= 0:
		# 抽出源牌后，落在它后面的槽位整体左移一格
		var to: int = slot if slot <= from else slot - 1
		moved = cp.move_card(from, to)
	if moved:
		_ui._reorder_tip = "已切换为手动排列，点『按序 ⇅』可恢复自动排序"
	else:
		_ui._reorder_tip = ""
	# 顺序已变（或需要复位淡出效果）→ 整排重建；拖拽后的 pressed 由抑制标志吞掉
	_ui._update_hand_buttons()
	_ui._update_card_info_label()
	_ui._update_hand_reorder_button()
	# 抑制标志延后一帧清除：pressed 可能在本帧稍后由 Button 发出
	call_deferred("_clear_drag_suppress")


func _clear_drag_suppress() -> void:
	_ui._drag_suppress_click = false


# 清掉幽灵牌 / 指示线，并把原位牌的不透明度还原
func _reset_drag_visuals() -> void:
	if is_instance_valid(_ui._drag_ghost):
		_ui._drag_ghost.queue_free()
	_ui._drag_ghost = null
	if is_instance_valid(_ui._drag_line):
		_ui._drag_line.queue_free()
	_ui._drag_line = null
	if _ui._drag_from >= 0 and _ui._drag_from < _ui.hand_buttons.size():
		var b = _ui.hand_buttons[_ui._drag_from]
		if is_instance_valid(b):
			b.modulate = Color(1, 1, 1, 1)


# 重建手牌 / 切阶段时强制收尾（不落到数据层，顺序不变）
func _cancel_drag() -> void:
	_ui._reset_drag_visuals()
	_ui._drag_active = false
	_ui._drag_from = -1
	_ui._drag_slot = -1
	_ui._drag_press_idx = -1



# -------- 搬运自 scripts/GameUI.gd 第 4978-5727 行 --------
# 命中区 = 静止位置 ∪ 抬起位置（上扩 HOVER_LIFT）：上浮后的区域仍归属该牌
func _card_hover_rect(btn: Button) -> Rect2:
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	return Rect2(base - Vector2(0, _ui.HOVER_LIFT), Vector2(_ui.CARD_W, _ui.CARD_H + _ui.HOVER_LIFT))


# 抬起牌的"实际绘制矩形"：z_index=20 让抬起牌压住相邻牌，
# 因此这块区域里的指针必须归它，否则视觉在 A 上、判定却给了 B（顶栏滑过时逐张乱跳）
func _card_raised_rect(btn: Button) -> Rect2:
	if not is_instance_valid(btn): return Rect2()
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	return Rect2(base - Vector2(0, _ui.HOVER_LIFT), Vector2(_ui.CARD_W, _ui.CARD_H))


# 核心区 = 静止位置中「没被后一张牌盖住」的那一段；重叠区不算 → 实现滞回
func _card_core_rect(idx: int) -> Rect2:
	if idx < 0 or idx >= _ui.hand_buttons.size(): return Rect2()
	var btn = _ui.hand_buttons[idx]
	if not is_instance_valid(btn): return Rect2()
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	var w: float = _ui.CARD_W
	if idx + 1 < _ui.hand_buttons.size() and is_instance_valid(_ui.hand_buttons[idx + 1]):
		var nb = _ui.hand_buttons[idx + 1]
		var nb_base: Vector2 = nb.get_meta("base_pos", nb.position)
		w = clampf(nb_base.x - base.x, 8.0, _ui.CARD_W)
	return Rect2(base - Vector2(0, _ui.HOVER_LIFT), Vector2(w, _ui.CARD_H + _ui.HOVER_LIFT))


# 鼠标位置命中的牌：越靠后的牌画得越上，重叠区归它（取最大索引）
func _hover_hit_index(mp: Vector2) -> int:
	var hit := -1
	for i in range(_ui.hand_buttons.size()):
		var b = _ui.hand_buttons[i]
		if not is_instance_valid(b): continue
		if _ui._card_hover_rect(b).has_point(mp):
			hit = i
	return hit


# 指针真正指着的那张牌 —— 点击 / 拖拽起点都用它，保证「所见即所得」：
#   1) 已抬起的牌 z_index=20，压住了左右相邻牌，它的绘制矩形内一律归它；
#      若这里仍按最大索引取，玩家看着 Ca（已抬起）、点下去却选中被它盖住的右侧那张。
#   2) 没有抬起牌（刚移过来、还在 60ms 稳定延迟内快速点击）时，
#      按静止几何取最大索引 —— 静止堆叠时后一张本来就画在前一张上面。
func _hit_card_at(mp: Vector2) -> int:
	if _ui._hover_idx >= 0 and _ui._hover_idx < _ui.hand_buttons.size():
		var cur = _ui.hand_buttons[_ui._hover_idx]
		if is_instance_valid(cur) and _ui._card_raised_rect(cur).has_point(mp):
			return _ui._hover_idx
	var hit: int = _ui._hover_hit_index(mp)
	# 触屏档（C）：手指比鼠标粗，落点常压在牌边缘外 3~6px 或牌缝里，
	# 严格命中不到就白点一次。这里只做「兜底」——严格命中优先，
	# 否则才用外扩 TOUCH_HIT_PAD 的矩形找最近的一张，不会改变正常点选的判定。
	if hit < 0 and _ui._touch_ui:
		hit = _ui._hover_hit_index_padded(mp, _ui.TOUCH_HIT_PAD)
	return hit


# 命中矩形外扩版本（触屏兜底用）：仍按「越靠右的牌画得越上」取最大索引
func _hover_hit_index_padded(mp: Vector2, pad: float) -> int:
	var hit := -1
	for i in range(_ui.hand_buttons.size()):
		var b = _ui.hand_buttons[i]
		if not is_instance_valid(b): continue
		if _ui._card_hover_rect(b).grow(pad).has_point(mp):
			hit = i
	return hit


# 真正执行切换：先落下旧牌再抬起新牌，信息栏顺序才不会串
func _set_hover_index(idx: int) -> void:
	if idx == _ui._hover_idx: return
	if _ui._hover_idx >= 0 and _ui._hover_idx < _ui.hand_buttons.size():
		var old = _ui.hand_buttons[_ui._hover_idx]
		if is_instance_valid(old): _ui._apply_hover(old, false)
	_ui._hover_idx = idx
	_ui._hover_pending_idx = -1
	if idx >= 0 and idx < _ui.hand_buttons.size():
		var nb = _ui.hand_buttons[idx]
		if is_instance_valid(nb): _ui._apply_hover(nb, true)


func _update_hand_hover() -> void:
	if _ui.hand_container == null or not is_instance_valid(_ui.hand_container): return
	# headless（自动化测试）没有真实鼠标，跳过轮询，避免 (0,0) 误触发
	if DisplayServer.get_name() == "headless": return
	# 触屏档（C）：Android 把「最后一次手指位置」当成鼠标位置，手指抬起后没有
	# mouse_exited → 抬起状态永远粘在最后点过的那张牌上：牌不落、下方信息栏一直
	# 显示它的详情，再点别的牌还要先等 60ms 悬停切换，手感就是「慢半拍 / 不知道选没选」。
	# 所以触控下悬停只在「按住」期间存在：松手立即落下并还原信息栏。
	if _ui._touch_ui and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _ui._hover_idx != -1: _ui._set_hover_index(-1)
		_ui._hover_pending_idx = -1
	if not _ui.hand_container.is_visible_in_tree(): return
	if _ui.hand_buttons.is_empty():
		_ui._hover_idx = -1
		_ui._hover_pending_idx = -1
		return
	# 离开手牌区立即复位（离开要跟手，不加延迟）
	var gr: Rect2 = _ui.hand_container.get_global_rect()
	var gmp: Vector2 = _ui.get_global_mouse_position()
	if not gr.has_point(gmp):
		# 抬起牌顶边正好与容器顶边重合：沿顶边滑动时给 HOVER_EXIT_GRACE 的容错带，
		# 否则越界 1px 就落牌、再回来又要等一次延迟，表现为"抖动"
		if _ui._hover_idx >= 0 and _ui._hover_keep_above(gmp, gr):
			return
		if _ui._hover_idx != -1: _ui._set_hover_index(-1)
		_ui._hover_pending_idx = -1
		return
	var mp: Vector2 = _ui.hand_container.get_local_mouse_position()
	_ui._update_hover_at(mp)


# 顶边容错带：横向仍在手牌范围内，纵向略微越过容器的上沿
func _hover_keep_above(gmp: Vector2, gr: Rect2) -> bool:
	return gmp.y < gr.position.y \
		and gmp.y >= gr.position.y - _ui.HOVER_EXIT_GRACE \
		and gmp.x >= gr.position.x and gmp.x < gr.end.x


# 核心判定（鼠标位置可注入）：自动化测试用它脱离真实鼠标验证防抖
func _update_hover_at(mp: Vector2) -> void:
	# 只读视角不跑悬停状态机：牌不该抬起，否则看着像可点。
	# 唯一的强制点放在这里 —— _update_hand_hover 与测试注入都必须经过它。
	if _ui._hand_read_only:
		if _ui._hover_idx != -1: _ui._set_hover_index(-1)
		_ui._hover_pending_idx = -1
		return
	# 1) 已抬起的牌以 z=20 压住相邻牌：它画出来的矩形内必须归它自己，
	#    否则鼠标沿顶栏滑过时会不断判给被压住的后一张，形成来回跳
	if _ui._hover_idx >= 0 and _ui._hover_idx < _ui.hand_buttons.size():
		var cur = _ui.hand_buttons[_ui._hover_idx]
		if is_instance_valid(cur) and _ui._card_raised_rect(cur).has_point(mp):
			_ui._hover_pending_idx = -1
			return
	# 2) 仍在当前牌核心区内（哪怕别的牌也命中）= 保持，重叠窄条处不回跳
	if _ui._hover_idx >= 0 and _ui._card_core_rect(_ui._hover_idx).has_point(mp):
		_ui._hover_pending_idx = -1
		return
	var hit = _ui._hover_hit_index(mp)
	if hit == _ui._hover_idx:
		_ui._hover_pending_idx = -1
		return
	# 3) 分级稳定时间：命中某张牌 60ms（跟手）；
	#    仍在容器内但不在任何牌上（牌列下方）140ms，避免底边轻微抖动就落牌
	var delay = _ui.HOVER_LEAVE_DELAY_MS
	if hit >= 0 and _ui._card_core_rect(hit).has_point(mp):
		delay = _ui.HOVER_SWITCH_DELAY_MS
	if hit != _ui._hover_pending_idx:
		_ui._hover_pending_idx = hit
		_ui._hover_pending_at = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - _ui._hover_pending_at >= delay:
		_ui._set_hover_index(hit)


# -------- 悬停上浮 + 置顶（公共入口，保留原签名供测试/外部直接调用） --------
func _on_hand_card_hover(btn: Button, hovered: bool) -> void:
	if not is_instance_valid(btn): return
	var idx: int = _ui.hand_buttons.find(btn)
	if hovered:
		if _ui._hover_idx != idx:
			if _ui._hover_idx >= 0 and _ui._hover_idx < _ui.hand_buttons.size():
				var old = _ui.hand_buttons[_ui._hover_idx]
				if is_instance_valid(old): _ui._apply_hover(old, false)
			_ui._hover_idx = idx
		_ui._apply_hover(btn, true)
	else:
		if idx == _ui._hover_idx: _ui._hover_idx = -1
		_ui._apply_hover(btn, false)
	_ui._hover_pending_idx = -1


# -------- 抬起/落下：位置、层级、边框样式三者同源，避免各自闪烁 --------
func _apply_hover(btn: Button, hovered: bool) -> void:
	if not is_instance_valid(btn): return
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	if hovered:
		btn.z_index = _ui.Z_HAND_HOVER
		# 层级立即生效，位置交给补间： 80ms 三次缓出，抬起/落下不再一格跳
		_ui._tween_card_y(btn, base.y - _ui.HOVER_LIFT)
		# 缩放同拍：1.06 让"正在看的那张"从整排里跳出来（pivot 居中，命中判定不受影响）
		_ui._tween_card_scale(btn, _ui.HAND_HOVER_SCALE)
		_ui._show_card_detail(btn)
	else:
		var idx: int = btn.get_meta("hand_idx", -1)
		btn.z_index = _ui.Z_HAND_SELECTED if idx in _ui.selected_indices else 0
		# 落回时把「选中常驻上浮」一起算进去：否则触屏上刚选中的牌被悬停一次、
		# 松手后又落回原位，选中的视觉提示就消失了
		var rest_lift: float = _ui._selected_lift() if idx in _ui.selected_indices else 0.0
		_ui._tween_card_y(btn, base.y - rest_lift)
		_ui._tween_card_scale(btn, _ui.HAND_SELECT_SCALE if idx in _ui.selected_indices else 1.0)
		_ui._restore_card_info()
	# 悬停外观由本状态机驱动（引擎自带 hover 态是另一套判定，会独立闪）。
	# normal/hover/pressed 三者始终指向同一个 StyleBox：引擎无论认为是否悬停，
	# 画出来都一样 → 既不会闪，也不会回退到默认深色主题（那就是"选中后发黑"）。
	# 注意：get_meta 的第二参数不能用 null（Godot 会当作"无默认值"报错）
	var key: String = "sb_hover" if hovered else "sb_normal"
	var sb = btn.get_meta(key, false)
	if sb is StyleBox:
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)


# -------- 升降补间：每张牌只保留一个 tween，重排 / 反向移动时先 kill --------
# 本工程首个 Tween 用法，注意两点：
#   1) tween 由节点创建，节点释放后 tween 自动失效，回调里不必再判空；
#   2) meta 的第二参数不能用 null（Godot 会当作"无默认值"报错），这里用 false 兜底。
func _tween_card_y(btn: Button, target_y: float) -> void:
	if not is_instance_valid(btn): return
	_ui._kill_hover_tween(btn)
	var tw = _ui.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "position:y", target_y, _ui.HOVER_ANIM_MS / 1000.0)
	btn.set_meta("hover_tween", tw)


func _kill_hover_tween(btn: Button) -> void:
	if not is_instance_valid(btn): return
	var tw = btn.get_meta("hover_tween", false)
	if tw is Tween and tw.is_valid():
		tw.kill()


# -------- 手牌缩放补间（A2）：悬停 1.06 / 选中 1.04 / 常态 1.0 --------
# 为什么放在手牌上而不是给卡牌换更大的贴图：命中判定用的是静态 _card_hover_rect()，
# scale 不参与几何计算，所以放大既不会自激抖动，也不会把点数判给邻居。
# meta 键与 hover_tween 分开：重排只 kill 位移补间时，缩放能自己收敛到目标值。
func _tween_card_scale(btn: Button, target: float) -> void:
	if not is_instance_valid(btn): return
	_ui._kill_scale_tween(btn)
	var tw = _ui.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(target, target), _ui.HAND_SCALE_MS / 1000.0)
	btn.set_meta("scale_tween", tw)


func _kill_scale_tween(btn: Button) -> void:
	if not is_instance_valid(btn): return
	var tw = btn.get_meta("scale_tween", false)
	if tw is Tween and tw.is_valid():
		tw.kill()


# -------- 悬停详情写进下方固定信息栏（替代原生 tooltip，避免浮框遮挡整排手牌） --------
func _show_card_detail(btn: Button) -> void:
	if not _ui.card_info_label or not _ui.game_manager: return
	var idx: int = btn.get_meta("hand_idx", -1)
	var cp = _ui.game_manager.get_current_player()
	if cp == null or idx < 0 or idx >= cp.hand.size(): return
	if not _ui._card_info_detail_shown:
		_ui._card_info_backup = _ui.card_info_label.text
		_ui._card_info_detail_shown = true
	_ui.card_info_label.text = _ui._card_summary_text(cp.hand[idx])


func _restore_card_info() -> void:
	if not _ui.card_info_label or not _ui._card_info_detail_shown: return
	_ui.card_info_label.text = _ui._card_info_backup
	_ui._card_info_detail_shown = false


# -------- 卡牌详情压成单行，便于在信息栏一次读完 --------
func _card_summary_text(card) -> String:
	if card == null: return ""
	var vs: String = _ui._format_valence_full(card.common_valence)
	if vs == "":
		vs = "N/A"
	return "%s %s  |  原子序数 %d  |  族 %s  |  %s  |  化合价 %s  |  相对原子质量 %.2f" % [
		card.symbol, card.name_cn, card.atomic_number, card.group,
		card.element_type, vs, card.atomic_weight]


# ============================================================
# 化合价文本：格式化 + 按可用宽度自适应
# ============================================================
# 为什么需要这一层：card.common_valence 最多 5 个价（Cl = [-1,1,3,5,7]），
#   "-1 +1 +3 +5 +7" 在 13px 下实测 85px —— 正好等于整张卡宽（85），触屏 15px 达 98px，
#   Label 默认不裁剪，于是文字直接画到卡片右边界之外（多价元素卡面溢出 bug）。
# 帮助页图鉴（迷你卡 96 宽）早就有「只留两个价 + …」的裁剪，卡面一直没做；
# 本次把两处收敛到同一套：全价 → 去空格 → 降字号 → 两端价 + …。
func _valence_token(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)


func _format_valence_full(vals: Array) -> String:
	var parts: Array = []
	for v in vals:
		parts.append(_ui._valence_token(v))
	return " ".join(parts)


func _format_valence_tight(vals: Array) -> String:
	var s := ""
	for v in vals:
		s += _ui._valence_token(v)
	return s


# 放不下全价时只留「最低价 + 最高价」，**不再加省略号**（P14-A）：
#   "-1 +7…" 里的 "…" 既占宽度、又像渲染残缺（真机截图反馈「不美观」），
#   而 "首价 末价" 本身就是「区间」语义，读起来是「-1 到 +7」，不省略也不误导。
# 中间的 +1/+3/+5 不丢：悬停信息栏 _card_summary_text 仍显示全价，化合价选择面板是逐价按钮，
#   帮助页图鉴的迷你卡下方也有一行完整说明。
# 两个价以内原样返回（不动数据顺序，H 仍是 "+1 -1"，与历史显示一致）；
# 3 个以上才排序取首尾（数据顺序不保证升序，H 的数据就是 [1, -1]）。
func _format_valence_pair(vals: Array) -> String:
	if vals.is_empty():
		return "—"
	if vals.size() <= 2:
		return _ui._format_valence_full(vals)
	var sorted_vals: Array = _ui._sorted_valences(vals)
	return "%s %s" % [_ui._valence_token(sorted_vals[0]), _ui._valence_token(sorted_vals[-1])]


func _sorted_valences(vals: Array) -> Array:
	var out: Array = vals.duplicate()
	out.sort()
	return out


# 分级收缩（P14-A 重写）：全价 → 去空格 → 字距降 1 档 → 首末价（回原字号）
# 与旧实现的区别：
#   · 旧实现最后一档是「首末价 + … 且字号压到 10px」，紧凑档 3 价元素（C/N/P/S/Br）
#     显示成 10px 的 "+4+2-4"，糊在一起；5 价元素（Cl/I）变成 "-1 +7…" 截断。
#   · 现在改为：字号最多降 1 档（13 → 12，触屏 15 → 14），再放不下就退「首末价」并**回升原字号**，
#     所以同一排手牌里价态字号只有 12/13（触屏 14/15）两档，且永远不出现省略号。
# 末档落定后 clip_text=true 兜底：任何数据 / 字体 / 极端窄行下都不会画出卡片右边界。
# 实际文本宽写进 meta("fit_w")、档位写进 meta("val_mode")（full/tight/pair/clip），
# 圆底价态 chip（A1）与测试直接复用，不再各量一遍。
func _fit_card_valence(lbl: Label, card, max_w: float, base_fs: int) -> void:
	if lbl == null:
		return
	lbl.clip_text = true
	var vals: Array = card.common_valence if card != null else []
	if vals.is_empty():
		lbl.text = "N/A"
		lbl.add_theme_font_size_override("font_size", base_fs)
		lbl.set_meta("fit_w", 0.0)
		lbl.set_meta("val_mode", "none")
		_ui._sync_valence_chip(lbl)
		return
	var font: Font = lbl.get_theme_font("font")
	# 触屏档把收缩下限一起抬 1 档（11 → 12）：手机上 11px 已经读不清，
	# 宽度不够时宁可退到「首末价」，也不要缩成一团糊字。
	var min_fs: int = mini(_ui._touch_fs(_ui.CARD_VAL_MIN_FS, 1), base_fs)
	var txt_full: String = _ui._format_valence_full(vals)
	var txt_tight: String = _ui._format_valence_tight(vals)
	var txt_pair: String = _ui._format_valence_pair(vals)
	var best_text := ""
	var best_fs := 0
	var best_mode := ""
	if _ui._valence_fits(font, txt_full, base_fs, max_w):
		# 最常见的情况：单 / 双价元素原样显示（+2、+1 -1、+2 +3）
		best_text = txt_full
		best_fs = base_fs
		best_mode = "full"
	elif _ui._valence_fits(font, txt_tight, base_fs, max_w):
		# 3~5 个价、常规档：去掉空格就够（Cl 13px 全价 85 → 72）
		best_text = txt_tight
		best_fs = base_fs
		best_mode = "tight"
	else:
		# 紧凑档 / 触屏放大档：字距（tight）只降 1 档；再放不下就退「首末价」并**回升原字号**
		var fs: int = base_fs - 1
		if fs >= min_fs and _ui._valence_fits(font, txt_tight, fs, max_w):
			best_text = txt_tight
			best_fs = fs
			best_mode = "tight"
		if best_text == "":
			# 信息少了，字号就不该再小：首末价从原字号开始试，必要时才降到 min_fs
			fs = base_fs
			while fs >= min_fs:
				if _ui._valence_fits(font, txt_pair, fs, max_w):
					best_text = txt_pair
					best_fs = fs
					best_mode = "pair"
					break
				fs -= 1
		if best_text == "":
			# 极端窄行（44px 行宽 + 触屏字号）：连「首末价」都放不下 → 只留首价并 clip
			var sorted_vals: Array = _ui._sorted_valences(vals)
			best_text = _ui._valence_token(sorted_vals[0])
			best_fs = min_fs
			best_mode = "clip"
	lbl.text = best_text
	lbl.add_theme_font_size_override("font_size", best_fs)
	lbl.set_meta("fit_w", minf(_ui._valence_width(font, best_text, best_fs), max_w))
	lbl.set_meta("val_mode", best_mode)
	_ui._sync_valence_chip(lbl)


# 卡面价态圆底：chip 是 label 的父节点，因此只需定 chip 的矩形 ——
#   · 宽 = 实测文字宽 + 左右 padding（不超过整行宽，文字两侧恒留 CHIP_PAD）
#   · 横坐标 = 行起点（紧凑档左对齐）或 行内居中（常规档）
# 旧实现把 chip 当 label 的兄弟节点、按「居中于 label」算坐标，而紧凑牌面把 label
# 改成左对齐 → 粉底整体右偏 9~13px（截图里 +2 / 0 的粉块跑到文字右边）。
func _sync_valence_chip(lbl: Label) -> void:
	var chip := lbl.get_parent() as Control
	if chip == null or chip.name != "CardValenceChip":
		return
	var fit_w: float = float(lbl.get_meta("fit_w", 0.0))
	var row_x: float = float(chip.get_meta("row_x", 5.0))
	var row_w: float = float(chip.get_meta("row_w", 85.0))
	var align: int = int(chip.get_meta("row_align", HORIZONTAL_ALIGNMENT_CENTER))
	# 行宽已扣掉两侧 padding（见调用点），这里再加回来就是粉底宽
	var w: float = minf(fit_w + _ui.CARD_VAL_CHIP_PAD * 2.0, row_w)
	var x: float = row_x if align == HORIZONTAL_ALIGNMENT_LEFT else row_x + (row_w - w) * 0.5
	chip.position = Vector2(x, _ui.CARD_VAL_Y + 1.0)
	chip.size = Vector2(w, _ui.CARD_VAL_CHIP_H)
	chip.visible = fit_w > 0.0


func _valence_fits(font: Font, txt: String, fs: int, max_w: float) -> bool:
	return _ui._valence_width(font, txt, fs) <= max_w


func _valence_width(font: Font, txt: String, fs: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


# -------- 点击重排后鼠标未移动，需主动恢复悬停状态 --------
func _restore_hover_after_rebuild() -> void:
	if _ui.hand_buttons.is_empty(): return
	var mp: Vector2 = _ui.hand_container.get_local_mouse_position()
	# 用与轮询相同的命中矩形和「取最上层」规则，保证两条路径结果一致
	var hit = _ui._hover_hit_index(mp)
	if hit >= 0:
		_ui._set_hover_index(hit)


func _build_card_button(card, idx: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(_ui.CARD_W, _ui.CARD_H)
	btn.size = Vector2(_ui.CARD_W, _ui.CARD_H)   # Control 容器不分配尺寸，需显式设置
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# 牌对象本身也存一份：重建 / 重排后靠它确认"这个按钮画的是哪张牌"，
	# 不再依赖 hand_idx（索引会随重排变化）
	btn.set_meta("card", card)
	# 记录「这一批牌面字号是按哪个档位生成的」：复用路径靠它判断要不要补刷字号
	btn.set_meta("touch_fonts", _ui._touch_ui)
	# 不用原生 tooltip：它会浮在鼠标旁遮住整排手牌，改由下方 CardInfoLabel 显示

	var is_selected: bool = idx in _ui.selected_indices
	# 正常态 / 选中态走同一套规范（圆角 8、1px 中性边 / 2px 橙金边、轻投影）
	# 用共享模板（只读）：所有牌共用同一份 StyleBox，重建一圈不再产生 2n 次分配
	var style_base = _ui._panel_style_template("card_selected" if is_selected else "card")

	# 悬停样式：未选中 → 浅蓝；已选中 → 保留黄色系（只加深），
	# 否则悬停会把"已选中"的浅黄整个盖掉，用户看不出哪张被选了
	var style_hover = _ui._panel_style_template("card_hover_selected" if is_selected else "card_hover")

	btn.add_theme_stylebox_override("normal", style_base)
	# 引擎的 hover / pressed / focus 态必须一并接管，否则会回退到默认（深色）主题：
	# 鼠标停在牌上时整张牌被画成半透明深灰 —— 也就是"选中后发黑"的真正原因。
	# hover / pressed 与 normal 同源，引擎状态切换不可见，判定仍只由状态机负责。
	btn.add_theme_stylebox_override("hover", style_base)
	btn.add_theme_stylebox_override("pressed", style_base)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())   # 去掉点击后的焦点框
	# 两套样式存进 meta，_apply_hover() 在抬起/落下时切换
	btn.set_meta("sb_normal", style_base)
	btn.set_meta("sb_hover", style_hover)

	var l_num = Label.new()
	l_num.name = "CardNumber"          # 具名：触屏档测试按名字取字号（校验 12 → 14）
	l_num.text = str(card.atomic_number)
	l_num.add_theme_font_size_override("font_size", _ui._touch_fs(12, 2))
	l_num.add_theme_color_override("font_color", Color(0.25, 0.28, 0.32, 1))
	l_num.position = Vector2(4, 2)
	btn.add_child(l_num)

	var l_group = Label.new()
	l_group.name = "CardGroup"          # 具名：触屏档复用路径按名字补刷字号（11 → 13）
	l_group.text = card.group
	l_group.add_theme_font_size_override("font_size", _ui._touch_fs(11, 2))
	# 固定深灰：不跟随元素类别色（类别色深浅差异大，族名要保持稳定可读）
	l_group.add_theme_color_override("font_color", Color(0.3, 0.32, 0.36, 1))
	l_group.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_group.size = Vector2(52, 15)
	l_group.position = Vector2(38, 2)
	btn.add_child(l_group)

	var l_sym = Label.new()
	l_sym.name = "CardSymbol"
	l_sym.text = card.symbol
	l_sym.add_theme_font_size_override("font_size", _ui._touch_fs(28, 4))
	l_sym.add_theme_color_override("font_color", _ui._get_card_color(card))
	l_sym.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.25))
	l_sym.add_theme_constant_override("outline_size", 2)
	l_sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_sym.size = Vector2(85, 26)
	l_sym.position = Vector2(5, 20)
	btn.add_child(l_sym)

	var l_name = Label.new()
	l_name.name = "CardName"
	l_name.text = card.name_cn
	l_name.add_theme_font_size_override("font_size", _ui._touch_fs(14, 3))
	l_name.add_theme_color_override("font_color", Color(0.1, 0.12, 0.14, 1))
	l_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_name.size = Vector2(85, 15)
	l_name.position = Vector2(5, 48)
	btn.add_child(l_name)

	# 价态圆底（A1）：Panel 作为 Label 的父节点 —— 粉底与文字物理绑定，
	# 不会再出现「粉底按居中算、文字按左对齐排」的错位（截图回归：紧凑档粉底整体右偏）。
	# 行几何（起点 / 宽度 / 对齐）存在 chip 的 meta 上，宽度由 _fit_card_valence()
	# 实测的文字宽决定（见 _sync_valence_chip）。
	var l_val_chip := Panel.new()
	l_val_chip.name = "CardValenceChip"
	l_val_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_val_chip.set_meta("row_x", 5.0)
	l_val_chip.set_meta("row_w", 85.0)
	l_val_chip.set_meta("row_align", HORIZONTAL_ALIGNMENT_CENTER)
	l_val_chip.add_theme_stylebox_override("panel", _ui._panel_style_template("valence_chip"))
	btn.add_child(l_val_chip)

	var l_val = Label.new()
	l_val.name = "CardValence"
	l_val.add_theme_font_size_override("font_size", _ui._touch_fs(13, 2))
	l_val.add_theme_color_override("font_color", Color(0.55, 0.2, 0.2, 1))
	l_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l_val_chip.add_child(l_val)
	l_val.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 全价优先；放不下时自动去空格 / 降字号 / 只留两端价（不会画出卡边）
	_ui._fit_card_valence(l_val, card, 85.0 - _ui.CARD_VAL_CHIP_PAD * 2.0, _ui._touch_fs(13, 2))

	var l_mass = Label.new()
	l_mass.name = "CardMass"           # 具名：触屏档测试按名字取字号（校验 9 → 12）
	l_mass.text = "%.1f" % card.atomic_weight
	l_mass.add_theme_font_size_override("font_size", _ui._touch_fs(9, 3))
	l_mass.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5, 1))
	l_mass.position = Vector2(3, 102)
	btn.add_child(l_mass)

	# 点击目标由「静止几何 + 取最上层」重算（与悬停同规则），
	# 不直接用 Button 原生拾取：悬停抬升会把牌上移，原生拾取会落到被让开的下层牌
	btn.pressed.connect(_ui._on_card_pressed)
	# 不再连接 mouse_entered/mouse_exited：悬停由 _update_hand_hover() 轮询固定矩形判定，
	# 否则卡牌上浮会改变自身拾取几何，导致进入/离开无限翻转（抽搐）
	return btn


# ============================================================
# 十三、化合价选择面板
# ============================================================
func _update_valence_buttons() -> void:
	if not _ui.action_panel or not _ui.game_manager: return
	for child in _ui.action_panel.get_children():
		child.queue_free()
	var cp = _ui.game_manager.get_current_player()

	var elem_map: Dictionary = {}
	for _idx in _ui.selected_indices:
		var card = cp.hand[_idx]
		if not elem_map.has(card.symbol):
			elem_map[card.symbol] = card

	if elem_map.size() < 2:
		_ui.action_panel.add_child(_ui._mkb("至少选两种元素 (返回)", _ui._on_back, false))
		return

	# ---- 混合价态入口（v4）----
	# Fe₃O₄ 这类「同一元素每张牌取不同价」的组合，下面「每种元素一个价」的按钮
	# 永远配不平（3 张 Fe 同价时总电荷必是 3 的倍数，压不过 4 张 O 的 -8）。
	# 只在「统一价态无解 + 混合价态有解」时出现，平时不打扰玩家。
	var mixed_cv = _ui._mixed_valence_for_selection()
	if not mixed_cv.is_empty():
		_ui.action_panel.add_child(_ui._mkb("混合价态自动配平 ▶", _ui._on_confirm_mixed_valence.bind(mixed_cv), false))
		var mixed_lbl = Label.new()
		mixed_lbl.text = _ui._mixed_valence_text(mixed_cv)
		_ui.action_panel.add_child(mixed_lbl)

	var all_assigned = true
	for sym in elem_map:
		var card = elem_map[sym]
		var already = null
		for sel in _ui.compound_selections:
			if sel.symbol == sym:
				already = sel
				break
		if already == null:
			all_assigned = false
			for v in card.common_valence:
				_ui.action_panel.add_child(_ui._mkb("%s (%+d)" % [sym, v], _ui._on_select_valence.bind(sym, v), false))

	# ---- 一键配平（P14-B）----
	# 玩家不用再逐个猜价：求解器给出可行解（且引擎已确认 ratio_ok）就直接打出去。
	# 只在「还没选完」或「选完了但 Σ ≠ 0」时出现 —— 已经配平的组合不再多一颗按钮打扰。
	var sel_sum: int = _ui._selection_charge_sum()
	var uniform_cv = _ui._uniform_valence_for_selection()
	if not uniform_cv.is_empty() and (not all_assigned or sel_sum != 0):
		_ui.action_panel.add_child(_ui._mkb("自动配平 ▶", _ui._on_confirm_auto_valence.bind(uniform_cv), false))

	if not all_assigned:
		_ui.action_panel.add_child(_ui._mkb("返回", _ui._on_back, false))
	else:
		var info = ""
		for sel in _ui.compound_selections:
			info += "%s%+d " % [sel.symbol, sel.valence]
		var lbl = Label.new()
		lbl.text = info
		_ui.action_panel.add_child(lbl)
		# 总电荷 Σ（P14-B）：按「张数」累加，玩家唯一能自查的量。
		# 真机截图里 H,H,C,N 被拒就是因为 2×(-1)+4+(-3) = -1 —— 以前界面根本不显示这个数。
		var sum_lbl = Label.new()
		sum_lbl.name = "ValenceSumLabel"
		# 0 不写成 "+0"：配平时直接给一个正向反馈，比 "Σ = +0（需 0）" 好读
		sum_lbl.text = "Σ = 0（已配平 ✓）" if sel_sum == 0 else "Σ = %+d（需 0）" % sel_sum
		sum_lbl.tooltip_text = "总电荷 = Σ(每种元素的张数 × 所选化合价)，等于 0 才能配平"
		sum_lbl.add_theme_font_size_override("font_size", _ui._touch_fs(14, 2))
		sum_lbl.add_theme_color_override("font_color",
			Color(0.13, 0.45, 0.18, 1.0) if sel_sum == 0 else Color(0.76, 0.16, 0.13, 1.0))
		_ui.action_panel.add_child(sum_lbl)
		_ui.action_panel.add_child(_ui._mkb("确认打出", _ui._on_confirm_compound, false))
		_ui.action_panel.add_child(_ui._mkb("重选化合价", _ui._on_reset_valence, false))
		_ui.action_panel.add_child(_ui._mkb("返回", _ui._on_back, false))


# 当前选中的卡牌：复用 _selected_cards(cp)（P7 已有实现，优先取按钮 meta，
# 拖拽重排后索引对不上也不会取错牌）
func _sel_cards() -> Array:
	if _ui.game_manager == null:
		return []
	# 联机（Step 3，D6）：选中的永远是「自己手牌」里的牌 —— 用 get_current_player()
	# 会在别人回合读到别人的手牌（索引来自我这边的手牌按钮，取出来就是另一张牌）
	return _ui._selected_cards(_ui._view_player())


# 面板所选化合价的「总电荷 Σ」：按张数累加（2 张 H 就是 2 份价），
# 与 _on_confirm_compound() 的判定口径一致 —— 界面显示与引擎判定不再各算一套。
func _selection_charge_sum() -> int:
	var total: int = 0
	for card in _ui._sel_cards():
		for sel in _ui.compound_selections:
			if sel.symbol == card.symbol:
				total += int(sel.valence)
				break
	return total


# 统一价态可行解（每元素一个价）。有解且引擎确认比例 OK → 才给「自动配平 ▶」按钮。
# 与 _mixed_valence_for_selection() 互斥：统一解优先，混合解只在统一无解时出现。
func _uniform_valence_for_selection() -> Dictionary:
	var cards = _ui._sel_cards()
	if cards.size() < 2:
		return {}
	var cv: Dictionary = _ui.CompoundSolverScript.get_uniform_valence_pairs(cards)
	if cv.is_empty():
		return {}
	var fi = _ui.CompoundSolverScript.get_compound_formula(cards, cv)
	if fi.is_empty() or not bool(fi.get("ratio_ok", false)):
		return {}
	return cv


# 当前选中的牌组：统一价态无解、混合价态有解 → 返回混合价字典；否则 {}
# （返回的字典直接喂给 play_cards，形如 {"Fe": [3, 3, 2], "O": -2}）
func _mixed_valence_for_selection() -> Dictionary:
	var cards = _ui._sel_cards()
	if cards.size() < 2:
		return {}
	# 统一解已经能打 → 不提供混合入口（保持「主流解优先」）
	if not _ui.CompoundSolverScript.get_uniform_valence_pairs(cards).is_empty():
		return {}
	var mixed: Dictionary = _ui.CompoundSolverScript.get_mixed_valence_pairs(cards)
	if mixed.is_empty():
		return {}
	var has_array := false
	for sym in mixed:
		if mixed[sym] is Array:
			has_array = true
	if not has_array:
		return {}
	# 真正会用这个字典出牌 → 先确认它确实配平，避免玩家点了按钮又收到「非法出牌」
	var fi = _ui.CompoundSolverScript.get_compound_formula(cards, mixed)
	if fi.is_empty() or not bool(fi.get("ratio_ok", false)):
		return {}
	return mixed


# 混合价态的可读文本：{"Fe": [3,3,2], "O": -2} → "混合价态：Fe +3/+3/+2，O -2"
# 混合（数组）的元素排在前面 —— 玩家最需要核对的就是它。
func _mixed_valence_text(cv: Dictionary) -> String:
	var parts: Array = []
	for sym in cv:
		if not (cv[sym] is Array):
			continue
		parts.append(_ui._valence_text_of(sym, cv[sym]))
	for sym in cv:
		if cv[sym] is Array:
			continue
		parts.append(_ui._valence_text_of(sym, cv[sym]))
	return "混合价态：" + "，".join(parts)


func _valence_text_of(sym: String, v) -> String:
	if v is Array:
		var seg: Array = []
		for x in v:
			seg.append("%+d" % int(x))
		return "%s %s" % [sym, "/".join(seg)]
	return "%s %+d" % [sym, int(v)]




# ============================================================
# 十四、用户交互回调
# ============================================================
# Button 原生拾取用的是「当前几何」，而悬停抬起的牌已经上移了 HOVER_LIFT：
# 鼠标落在重叠区下沿时，抬起牌让出的那条带会判给被它压住的下层牌 ——
# 视觉上最上层是抬起的那张，点中的却是下面那张。
# 这里改用与悬停 / 拖拽同一套「所见即所得」规则重新定位（见 _hit_card_at）。
func _on_card_pressed() -> void:
	if _ui.hand_container == null or _ui.hand_buttons.is_empty():
		return
	var idx: int = _ui._hit_card_at(_ui.hand_container.get_local_mouse_position())
	if idx < 0 or idx >= _ui.hand_buttons.size():
		return
	_ui._on_card_clicked(idx)


func _on_card_clicked(index: int) -> void:
	# 拖拽结束后 Button 会补发一次 pressed：吞掉，避免"拖完顺带选中"
	if _ui._drag_suppress_click:
		_ui._drag_suppress_click = false
		return
	_ui._apply_card_selection(index)


# 选中 / 取消选中（Button 点击与触屏「起拖后回退成点选」共用同一条路径）
func _apply_card_selection(index: int) -> void:
	# 只读视角（AI 回合查看自己的手牌）不接受选牌
	if _ui._hand_read_only:
		return
	if _ui.step_mode != 0 and _ui.step_mode != 3: return
	# 玩家自己动牌 → 提示作废，回到用户自己的选择
	if _ui._hint_text != "":
		_ui._clear_hint()
	if index in _ui.selected_indices: _ui.selected_indices.erase(index)
	else: _ui.selected_indices.append(index)
	# 触屏档（C）：30ms 轻震，作为「选中 / 取消」的触摸反馈
	# （Android 需要在 export_presets 打开 permissions/vibrate，已开；桌面 / 无马达设备静默无效）
	if _ui._touch_ui:
		Input.vibrate_handheld(30)
	# 只刷新这一张（Slice 2b）：旧实现走 _update_hand_buttons() 整排重建 ——
	# 一次点选要重造 n 个 Button + 5n 个 Label、重测全部价态文本、kill 掉所有补间。
	_refresh_card_selection_visual(index)
	_ui._update_hand_reorder_button()
	_ui._update_action_panel()
	_ui._update_card_info_label()


# -------- 选中 / 取消选中：单张刷新（Slice 2b，不再整排重建）--------
# 选中只影响四件事：两套 stylebox、z_index、缩放、触屏档常驻上浮。
# 牌面内容（原子序数 / 族 / 符号 / 名称 / 价态 / 紧凑对齐 / base_pos）与选中无关，一律不动，
# 所以「点一下重建 200 个节点」是纯浪费 —— 这里只改这一张。
func _refresh_card_selection_visual(idx: int) -> void:
	_apply_card_state_style(idx)
	if idx < 0 or idx >= _ui.hand_buttons.size():
		return
	# 悬停中的牌位置交给悬停状态机（它已经抬起了），这里只换了样式与层级
	if idx == _ui._hover_idx:
		return
	var btn = _ui.hand_buttons[idx]
	if not is_instance_valid(btn):
		return
	var is_selected: bool = idx in _ui.selected_indices
	# 落位规则与 _apply_hover(btn, false) 一致：触屏常驻上浮 + 选中 1.04 缩放
	var base: Vector2 = btn.get_meta("base_pos", btn.position)
	var rest_lift: float = _ui._selected_lift() if is_selected else 0.0
	_ui._tween_card_y(btn, base.y - rest_lift)
	_ui._tween_card_scale(btn, _ui.HAND_SELECT_SCALE if is_selected else 1.0)

