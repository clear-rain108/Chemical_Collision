# ============================================================
# GameManager.gd - 游戏规则引擎
# 回合管理 / 出牌校验 / 族炸接炸链 / 教程关卡 / 上限弃牌
# 补充规则：有机物立即胜利 / 顺序牌型（方向反转+指定牌型）
# ============================================================

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const UtilsScript = preload("res://scripts/Utils.gd")

# ============================================================
# 一、游戏常量
# ============================================================
const MIN_PLAYERS = 3
const MAX_PLAYERS = 8
const INITIAL_HAND_SIZE = 8

# ============================================================
# 二、核心变量 (牌库/玩家/桌面)
# ============================================================
var database: RefCounted = null
var players: Array = []
var current_player_index: int = 0
var phase: int = 0
var winner_index: int = -1
var table_cards: Array = []
var table_player_index: int = -1
var table_pattern: int = -1    # 桌面牌型（用于限制接牌类型）
var is_round_starter: bool = true
var log_messages: Array = []

# ============================================================
# 三、规则状态变量
# ============================================================
var compound_immune: bool = false          # 溢出化合物免疫族炸
var clan_bomb_chain_active: bool = false   # 族炸接炸链激活
var clan_bomb_owner: int = -1              # 接炸链引爆者索引
var clan_bomb_disabled: bool = false       # 禁用族炸（第一关）

# ============================================================
# 三之二、补充规则状态变量
# ============================================================
var organic_rules_enabled: bool = false        # 有机物规则开关
var sequence_rules_enabled: bool = false       # 顺序规则开关
var direction_clockwise: bool = true           # 出牌方向（true=顺时针, false=逆时针）
var sequence_constraint: int = -1              # 顺序指定牌型约束（-1=无约束）
var sequence_constraint_active: bool = false   # 顺序约束是否激活

# ============================================================
# 四、教程状态变量
# ============================================================
var tutorial_level: int = 0             # 0=自由模式, 1=第一关, 2=第二关
var tutorial_step: int = 0              # 当前教程步骤
var tutorial_guidance: String = ""      # 当前引导文本
var tutorial_success: String = ""       # 成功提示（一次性显示）
var tutorial_level0_phase: int = 0      # 第0关阶段: 0=未开始 1=UI介绍 2=流程介绍 3=牌局
var ai_no_draw: bool = false            # AI在第0关不抽牌
var level0_rule_tip: String = ""        # 第0关规则提示（越大越小/同类同出/牌权争夺）
var level0_last_player_action: String = ""  # 玩家上一次操作类型

# ============================================================
# 五、PlayerInfo 内部类
# ============================================================
class PlayerInfo:
	var player_name: String = ""
	var hand: Array = []
	var is_ai: bool = false
	var has_passed: bool = false         # 本轮是否跳过
	var clan_bomb_cooling: bool = false  # 是否被族炸冷却

	func _init(p_name: String, ai: bool = false):
		player_name = p_name
		is_ai = ai

	func get_hand_count() -> int:
		return hand.size()

	func add_card(card) -> void:
		if card != null:
			hand.append(card)

	func remove_cards(cards: Array) -> void:
		for card in cards:
			var idx = hand.find(card)
			if idx >= 0:
				hand.remove_at(idx)

	func sort_hand_by_atomic_number() -> void:
		hand.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)

	func get_hand_display() -> String:
		if hand.is_empty():
			return "[空]"
		var names: Array = []
		for card in hand:
			names.append(card.symbol)
		return ", ".join(names)


# ============================================================
# 六、游戏初始化
# ============================================================
func init_game(player_count: int = 4, ai_count: int = 3) -> bool:
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		push_error("init_game: player_count=%d out of range [%d,%d]" % [player_count, MIN_PLAYERS, MAX_PLAYERS])
		return false
	if ai_count >= player_count:
		push_error("init_game: ai_count=%d >= player_count=%d" % [ai_count, player_count])
		return false

	phase = 0
	players.clear()
	table_cards.clear()
	table_player_index = -1
	table_pattern = -1
	winner_index = -1
	current_player_index = 0
	is_round_starter = true
	compound_immune = false
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	clan_bomb_disabled = false
	direction_clockwise = true
	sequence_constraint = -1
	sequence_constraint_active = false
	tutorial_level = 0
	tutorial_step = 0
	tutorial_guidance = ""
	tutorial_success = ""
	tutorial_level0_phase = 0
	ai_no_draw = false
	level0_rule_tip = ""
	level0_last_player_action = ""
	log_messages.clear()

	database = CardDatabaseScript.new()
	database.generate_deck()
	database.shuffle()

	# 创建玩家（人类在前，AI在后）
	var human_count = player_count - ai_count
	for i in range(player_count):
		var p_name = "玩家 %d" % (i + 1) if i < human_count else "AI %d" % (i + 1 - human_count)
		players.append(PlayerInfo.new(p_name, i >= human_count))

	# 每人发 8 张牌并排序
	for player in players:
		var cards = database.draw_cards(INITIAL_HAND_SIZE)
		for card in cards:
			player.add_card(card)
		player.sort_hand_by_atomic_number()

	phase = 1
	log_messages.append("===== 游戏开始 =====")
	if organic_rules_enabled or sequence_rules_enabled:
		var rules_list: Array = []
		if organic_rules_enabled: rules_list.append("有机物胜利")
		if sequence_rules_enabled: rules_list.append("顺序牌型")
		log_messages.append("【补充规则已启用】" + " + ".join(rules_list))
	log_messages.append("当前回合: %s (自由出牌)" % players[current_player_index].player_name)
	return true


# ============================================================
# 七、查询当前玩家
# ============================================================
func get_current_player() -> PlayerInfo:
	if players.is_empty():
		return null
	return players[current_player_index]

func get_current_player_index() -> int:
	return current_player_index


# ============================================================
# 八、出牌校验核心函数
# ============================================================
func play_cards(player_index: int, cards: Array, custom_valences: Dictionary = {}) -> int:
	if player_index < 0 or player_index >= players.size() or cards.is_empty():
		return -1

	var player = players[player_index]
	var skip_bomb = custom_valences.size() >= 2
	# 合成有机物时也跳过族炸检测
	if custom_valences.has("_organic"):
		skip_bomb = true
	var pattern = UtilsScript.detect_pattern(cards, skip_bomb)
	if pattern == -1:
		return -1

	# -------- 第零关AI禁止出族炸 --------
	if tutorial_level == 0 and tutorial_level0_phase >= 1 and player.is_ai and pattern == UtilsScript.CardPattern.CLAN_BOMB:
		return -3

	# -------- 顺序约束检查 --------
	if sequence_constraint_active and not is_round_starter and player_index != table_player_index:
		if sequence_constraint >= 0 and pattern != sequence_constraint:
			return -6  # 不符合顺序指定的牌型约束

	# -------- 族炸判定 --------
	if pattern == UtilsScript.CardPattern.CLAN_BOMB:
		if clan_bomb_disabled:
			return -3  # 本局禁止族炸
		if not clan_bomb_chain_active and player.clan_bomb_cooling:
			return -3
		if compound_immune and not clan_bomb_chain_active:
			return -4  # 溢出化合物免疫族炸
		if clan_bomb_chain_active:
			if table_cards.size() > 0:
				var cmp = UtilsScript.compare_cards(cards, table_cards)
				if cmp <= 0:
					return -2
	else:
		# -------- 非族炸：检查是否可以接当前桌面 --------
		if clan_bomb_chain_active:
			return -1  # 接炸模式只能出族炸
		if not is_round_starter:
			if table_pattern == UtilsScript.CardPattern.ELEMENT and pattern != UtilsScript.CardPattern.ELEMENT:
				return -4  # 单质后只能接单质或族炸
			if table_pattern == UtilsScript.CardPattern.COMPOUND and pattern != UtilsScript.CardPattern.COMPOUND:
				return -4  # 化合物后只能接化合物或族炸
			if table_cards.size() > 0:
				var cmp = UtilsScript.compare_cards(cards, table_cards)
				if cmp <= 0:
					return -2

	# -------- 化合物比例校验（必须在移除卡牌之前） --------
	if pattern == UtilsScript.CardPattern.COMPOUND:
		var fi = UtilsScript.get_compound_formula(cards, custom_valences)
		if not fi.is_empty() and not fi.get("ratio_ok", false):
			return -1  # 比例不匹配

	# -------- 从手牌移除，更新桌面 --------
	player.remove_cards(cards)
	table_cards = cards.duplicate()
	table_pattern = pattern
	table_player_index = player_index
	compound_immune = false

	# -------- 构建日志 --------
	var pname = UtilsScript.get_pattern_name(pattern)
	var elem_name = UtilsScript.get_element_display(cards)
	var card_str = _cards_to_string(cards)
	var log_msg = "%s 打出了 %s (%s" % [player.player_name, card_str, pname]
	if pattern == UtilsScript.CardPattern.ELEMENT and elem_name != "":
		log_msg += " " + elem_name
	if pattern == UtilsScript.CardPattern.COMPOUND:
		var fi = UtilsScript.get_compound_formula(cards, custom_valences)
		if not fi.is_empty():
			log_msg += " " + fi.get("formula", "??")
	if pattern == UtilsScript.CardPattern.ORGANIC:
		log_msg += " " + UtilsScript.get_organic_name(cards)
	log_msg += ")"
	log_messages.append(log_msg)

	# -------- 第0关规则提示检测 --------
	if tutorial_level == 0 and not player.is_ai:
		level0_rule_tip = ""
		if pattern == UtilsScript.CardPattern.CLAN_BOMB:
			level0_rule_tip = "牌权争夺"
		elif not is_round_starter and table_pattern == pattern:
			level0_rule_tip = "越大越小"
		elif is_round_starter:
			level0_rule_tip = "同类同出"
		if pattern == UtilsScript.CardPattern.ELEMENT or pattern == UtilsScript.CardPattern.COMPOUND:
			level0_last_player_action = "同类同出"

	# -------- 有机物：立即胜利 --------
	if pattern == UtilsScript.CardPattern.ORGANIC:
		phase = 2
		winner_index = player_index
		log_messages.append("===== 🎉 %s 打出有机物，立即获胜！=====" % player.player_name)
		clan_bomb_chain_active = false
		sequence_constraint_active = false
		return 0

	# -------- 族炸：启动接炸链 + 牌权移交 --------
	if pattern == UtilsScript.CardPattern.CLAN_BOMB:
		player.clan_bomb_cooling = true
		clan_bomb_chain_active = true
		clan_bomb_owner = player_index
		sequence_constraint_active = false  # 族炸打断顺序约束
		_check_tutorial_progress(pattern, not player.is_ai)
		for i in range(players.size()):
			if i != player_index:
				players[i].has_passed = false
		is_round_starter = false
		if player.get_hand_count() == 0:
			phase = 2
			winner_index = player_index
			log_messages.append("===== 游戏结束！获胜者: %s =====" % player.player_name)
			return 0
		next_turn()  # 牌权立即移交下一名玩家
		return 0

	# -------- 顺序：反转方向 + 指定牌型 --------
	if pattern == UtilsScript.CardPattern.SEQUENCE:
		direction_clockwise = not direction_clockwise
		var dir_name = "顺时针" if direction_clockwise else "逆时针"
		log_messages.append("↻ 出牌顺序反转为 %s！%s 可选择指定牌型" % [dir_name, player.player_name])
		# 返回特殊码 1 表示需要UI层弹出选择界面
		clan_bomb_chain_active = false
		clan_bomb_owner = -1
		_reset_all_passes()
		is_round_starter = false
		if player.get_hand_count() == 0:
			phase = 2
			winner_index = player_index
			log_messages.append("===== 游戏结束！获胜者: %s =====" % player.player_name)
			return 0
		return 1  # 特殊返回值：需要选择指定牌型

	# -------- 化合物：解除冷却 + 溢出检查 --------
	if pattern == UtilsScript.CardPattern.COMPOUND:
		player.clan_bomb_cooling = false
		if cards.size() >= players.size():
			compound_immune = true
			log_messages.append("⚠ 溢出化合物！牌数≥%d人，免疫族炸" % players.size())

	# -------- 非族炸/非顺序出牌完成：重置状态 --------
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	sequence_constraint_active = false  # 正常出牌后清除约束
	sequence_constraint = -1
	_reset_all_passes()
	is_round_starter = false

	if player.get_hand_count() == 0:
		phase = 2
		winner_index = player_index
		log_messages.append("===== 游戏结束！获胜者: %s =====" % player.player_name)
		return 0

	_check_tutorial_progress(pattern, not player.is_ai)
	next_turn()
	return 0


# ============================================================
# 八之二、顺序指定牌型
# ============================================================
# 由UI层调用，设置顺序打出后指定的牌型约束
func set_sequence_constraint(constraint_pattern: int) -> void:
	sequence_constraint = constraint_pattern
	sequence_constraint_active = true
	var pname = UtilsScript.get_pattern_name(constraint_pattern)
	log_messages.append("指定下一名玩家必须打出：%s，否则罚抽2张" % pname)
	next_turn()


# ============================================================
# 八之三、玩家不满足顺序约束时的罚抽
# ============================================================
func player_fail_sequence_constraint(player_index: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	var player = players[player_index]
	# 罚抽2张牌
	var drawn = database.draw_cards(2)
	for card in drawn:
		player.add_card(card)
	player.sort_hand_by_atomic_number()
	player.has_passed = true
	log_messages.append("%s 未打出指定牌型，罚抽2张并跳过" % player.player_name)
	sequence_constraint_active = false  # 约束结束
	sequence_constraint = -1
	next_turn()


# ============================================================
# 九、玩家操作：跳过 / 上限弃牌
# ============================================================
func player_pass(player_index: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	var player = players[player_index]
	var hand_limit = _get_hand_limit()
	player.has_passed = true

	# 上限弃牌：不抽牌（UI 层负责选牌弃置）
	if player.get_hand_count() >= hand_limit:
		if clan_bomb_chain_active:
			log_messages.append("%s 手牌达上限，不接炸" % player.player_name)
		else:
			log_messages.append("%s 手牌达上限，跳过" % player.player_name)
	else:
		# 第0关AI不抽牌
		if ai_no_draw and player.is_ai:
			if clan_bomb_chain_active:
				log_messages.append("%s 不接炸，跳过（第0关AI不抽牌）" % player.player_name)
			else:
				log_messages.append("%s 跳过回合（第0关AI不抽牌）" % player.player_name)
		else:
			var drawn = database.draw_cards(1)
			if drawn.size() > 0:
				player.add_card(drawn[0])
				player.sort_hand_by_atomic_number()
			if clan_bomb_chain_active:
				log_messages.append("%s 不接炸，抽1张并跳过" % player.player_name)
			else:
				log_messages.append("%s 跳过回合" % player.player_name)

	# 跳过时清除顺序约束（下一名玩家自由出牌）
	sequence_constraint_active = false
	sequence_constraint = -1
	next_turn()


func _get_hand_limit() -> int:
	return min(players.size() * 4, 18)


func player_discard_and_pass(player_index: int, card_to_discard) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	var player = players[player_index]
	player.remove_cards([card_to_discard])
	player.has_passed = true
	log_messages.append("%s 手牌达上限，弃置 %s 并跳过" % [player.player_name, card_to_discard.symbol])
	sequence_constraint_active = false
	sequence_constraint = -1
	next_turn()


# ============================================================
# 十、牌权轮转（支持方向切换）
# ============================================================
# 根据方向获取下一个索引
func _get_next_index_in_direction(from_idx: int) -> int:
	if direction_clockwise:
		return (from_idx + 1) % players.size()
	else:
		return (from_idx - 1 + players.size()) % players.size()


func next_turn() -> void:
	# 族炸链中：进入接炸轮询
	if clan_bomb_chain_active:
		_intercept_next()
		return

	# 总人数-1 人连续跳过 → 新一轮
	var unpassed = _get_unpassed_players()
	if unpassed.size() <= 1:
		_start_new_round()
		return

	# 按当前方向找下一位有牌且未 pass 的玩家
	var next_idx = current_player_index
	for _i in range(players.size()):
		next_idx = _get_next_index_in_direction(next_idx)
		var p = players[next_idx]
		if p.get_hand_count() > 0 and not p.has_passed:
			current_player_index = next_idx
			return

	_start_new_round()


# -------- 族炸接炸链轮询 --------
func _intercept_next() -> void:
	var next_idx = clan_bomb_owner
	for _i in range(players.size()):
		next_idx = (next_idx + 1) % players.size()
		if next_idx != clan_bomb_owner and players[next_idx].get_hand_count() > 0 and not players[next_idx].has_passed:
			current_player_index = next_idx
			return

	# 所有非 owner 已 pass → 接炸链结束
	_finish_clan_bomb_chain()


func _finish_clan_bomb_chain() -> void:
	clan_bomb_chain_active = false
	var owner_idx = clan_bomb_owner
	clan_bomb_owner = -1
	table_cards.clear()
	table_pattern = -1
	table_player_index = -1
	is_round_starter = true
	_reset_all_passes()
	current_player_index = owner_idx
	log_messages.append("无人接炸！%s 自由出牌" % players[owner_idx].player_name)


# -------- 新一轮开始 --------
func _start_new_round() -> void:
	table_cards.clear()
	table_pattern = -1
	table_player_index = -1
	is_round_starter = true
	_reset_all_passes()
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	compound_immune = false
	sequence_constraint_active = false
	sequence_constraint = -1

	current_player_index = _get_next_index_in_direction(current_player_index)
	for _i in range(players.size()):
		var p = players[current_player_index]
		if p.get_hand_count() > 0:
			log_messages.append("====== 新一轮！%s 自由出牌 ======" % p.player_name)
			return
		current_player_index = _get_next_index_in_direction(current_player_index)

	var alive = _get_alive_players()
	if alive.size() == 1:
		phase = 2
		winner_index = players.find(alive[0])
		return
	for i in range(players.size()):
		if players[i].get_hand_count() > 0:
			current_player_index = i
			return


# ============================================================
# 十一、辅助函数
# ============================================================
func _reset_all_passes() -> void:
	for p in players:
		p.has_passed = false

func _get_unpassed_players() -> Array:
	var result: Array = []
	for p in players:
		if p.get_hand_count() > 0 and not p.has_passed:
			result.append(p)
	return result

func _get_alive_players() -> Array:
	var alive: Array = []
	for p in players:
		if p.get_hand_count() > 0:
			alive.append(p)
	return alive


# ============================================================
# 十二、教程关卡系统
# ============================================================
func init_tutorial(level: int) -> bool:
	phase = 0
	players.clear()
	table_cards.clear()
	table_player_index = -1
	table_pattern = -1
	winner_index = -1
	current_player_index = 0
	is_round_starter = true
	compound_immune = false
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	clan_bomb_disabled = false
	direction_clockwise = true
	sequence_constraint = -1
	sequence_constraint_active = false
	log_messages.clear()
	tutorial_level0_phase = 0
	ai_no_draw = false
	level0_rule_tip = ""
	level0_last_player_action = ""

	database = CardDatabaseScript.new()
	database.generate_deck()

	tutorial_level = level
	if level == 0:
		# ========== 第零关：界面熟悉 + 流程介绍 + 牌局体验 ==========
		_init_level0_deck()
		players.append(PlayerInfo.new("玩家", false))
		players.append(PlayerInfo.new("AI 1", true))
		players.append(PlayerInfo.new("AI 2", true))

		# AI 固定手牌：O, S, C, Si, H, Mg 各1张
		_set_preset_hand(players[1], ["O", "S", "C", "Si", "H", "Mg"])
		_set_preset_hand(players[2], ["O", "S", "C", "Si", "H", "Mg"])

		# AI 各补2张非0族随机牌
		for ai_idx in [1, 2]:
			var ai = players[ai_idx]
			var non_noble_pool: Array = []
			for card in database.deck:
				if card.group != "0":
					non_noble_pool.append(card)
			non_noble_pool.shuffle()
			for card in non_noble_pool:
				if ai.get_hand_count() >= 8:
					break
				var new_card = _copy_card(card)
				ai.add_card(new_card)
				database.deck.erase(card)

		var player_cards = database.draw_cards(8)
		for card in player_cards:
			players[0].add_card(card)
		players[0].sort_hand_by_atomic_number()

		ai_no_draw = true
		clan_bomb_disabled = false
		tutorial_level0_phase = 0
		tutorial_step = 0
		tutorial_success = ""
		tutorial_guidance = ""
		_update_tutorial_level0_guidance()

	elif level == 1:
		clan_bomb_disabled = true
		players.append(PlayerInfo.new("玩家", false))
		players.append(PlayerInfo.new("AI 1", true))
		players.append(PlayerInfo.new("AI 2", true))
		_set_preset_hand(players[0], ["Na","Cl","Ca","O","He","Li","F","Mg","S","Ne"])
		_set_preset_hand(players[1], ["K","Br","B","C","Al","Si","N","P"])
		_set_preset_hand(players[2], ["H","Be","Ar","Cr","Mn","Fe","Co","Ni"])
	elif level == 2:
		players.append(PlayerInfo.new("玩家", false))
		players.append(PlayerInfo.new("AI 1", true))
		players.append(PlayerInfo.new("AI 2", true))
		players.append(PlayerInfo.new("AI 3", true))
		_set_preset_hand(players[0], ["H","Li","Na","Cl","K","O","Ca","F","He","Ne"])
		_set_preset_hand(players[1], ["Mg","S","Al","P","B","Si","C","N","Br","Be"])
		_set_preset_hand(players[2], ["Ar","Cr","Mn","Fe","Co","Ni","Cu","Zn"])
		_set_preset_hand(players[3], ["He","Ne","O","F","Cl","Ar","K","Ca"])
	else:
		return false

	if level != 0:
		tutorial_step = 1
		tutorial_success = ""
		_update_tutorial_guidance()

	phase = 1
	log_messages.append("===== 教程关卡 %d 开始 =====" % level)
	log_messages.append("当前回合: %s (自由出牌)" % players[current_player_index].player_name)
	return true


func _init_level0_deck() -> void:
	var first18 = ["H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar"]
	var full_db = CardDatabaseScript.new()
	full_db.generate_deck()
	database.deck.clear()
	var counts: Dictionary = {}
	for sym in first18:
		counts[sym] = 0
	for card in full_db.deck:
		if card.symbol in first18 and counts[card.symbol] < 3:
			database.deck.append(_copy_card(card))
			counts[card.symbol] += 1
	database.shuffle()


func _copy_card(card):
	return CardDatabaseScript.CardDataScript.new(
		card.symbol, card.name_cn, card.name_en, card.atomic_number,
		card.group, card.period, card.element_type, card.single_form,
		card.valence_electrons, card.common_valence,
		card.electronegativity, card.atomic_weight, card.description
	)


func _set_preset_hand(player: PlayerInfo, symbols: Array) -> void:
	for sym in symbols:
		var card = _find_card_by_symbol(sym)
		if card != null:
			player.add_card(card)
	player.sort_hand_by_atomic_number()


func _find_card_by_symbol(sym: String):
	for card in database.deck:
		if card.symbol == sym:
			database.deck.erase(card)
			return CardDatabaseScript.CardDataScript.new(
				card.symbol, card.name_cn, card.name_en, card.atomic_number,
				card.group, card.period, card.element_type, card.single_form,
				card.valence_electrons, card.common_valence,
				card.electronegativity, card.atomic_weight, card.description
			)
	return null


# ============================================================
# 十三、教程引导与进度
# ============================================================
func _update_tutorial_guidance() -> void:
	if tutorial_level == 1:
		match tutorial_step:
			1: tutorial_guidance = "【第1步】观察手牌：每张牌显示元素符号+中文名。鼠标悬停可查看原子序数、族、化合价、相对质量。\n点击选中一张牌，再点「出牌(选牌型)」→「作为单质打出」试试！"
			2: tutorial_guidance = "【第2步】很好！现在试试合成化合物：选中两种不同元素(如Na和Cl)，点「合成化合物」→为每种选化合价→确认打出。\n金属优先正价，非金属优先负价。"
			3: tutorial_guidance = "【第3步】继续练习！尝试不同的单质和化合物组合。\n记住：原子序数和越小，牌力越大。桌面牌必须被你出的牌压过。"
			_: tutorial_guidance = "【练习中】继续出牌直到打光手牌！随时可跳过抽牌。"
	elif tutorial_level == 2:
		match tutorial_step:
			1: tutorial_guidance = "【第1步】熟悉族炸：选中同族≥2张不同元素(如H+Li都是IA族)，点「作为族炸打出」。\n族炸可以抢牌权，比普通牌更强！"
			2: tutorial_guidance = "【第2步】族炸打出后进入冷却❄，必须出一个化合物来解除冷却。\n选中两种元素合成化合物，像Na+Cl=NaCl。"
			3: tutorial_guidance = "【第3步】试试接炸！当AI打出族炸后，你如果也有同族牌可出更大族炸接炸。\n也可以跳过让AI接炸。"
			4: tutorial_guidance = "【第4步】注意手牌上限！手牌达到上限时不能跳过，需选择1张弃置。\n继续练习直到打完所有手牌！"
			_: tutorial_guidance = "【练习中】继续游戏！利用族炸+化合物完成对局。"


func _update_tutorial_level0_guidance() -> void:
	if tutorial_level != 0:
		return
	match tutorial_level0_phase:
		1: tutorial_guidance = ""
		2: tutorial_guidance = ""
		3: tutorial_guidance = "【牌局中】尝试出牌！你可以打出单质、化合物或族炸。AI默认只出单质和化合物。"


func _check_tutorial_progress(pattern: int, player_is_human: bool) -> void:
	if not player_is_human:
		return
	tutorial_success = ""
	var advanced = false

	if tutorial_level == 0:
		pass
	elif tutorial_level == 1:
		if tutorial_step == 1 and pattern == UtilsScript.CardPattern.ELEMENT:
			tutorial_success = "✓ 正确！你打出了一张单质。"
			advanced = true
		elif tutorial_step == 2 and pattern == UtilsScript.CardPattern.COMPOUND:
			tutorial_success = "✓ 正确！你成功合成了一个化合物。"
			advanced = true
		elif tutorial_step == 3 and pattern == UtilsScript.CardPattern.COMPOUND:
			tutorial_success = "✓ 很好！继续练习。"
			advanced = true
	elif tutorial_level == 2:
		if tutorial_step == 1 and pattern == UtilsScript.CardPattern.CLAN_BOMB:
			tutorial_success = "✓ 正确！你打出了族炸，抢到了牌权！注意你进入了冷却❄。"
			advanced = true
		elif tutorial_step == 2 and pattern == UtilsScript.CardPattern.COMPOUND:
			tutorial_success = "✓ 正确！打出化合物解除了族炸冷却。"
			advanced = true
		elif tutorial_step == 3 and pattern == UtilsScript.CardPattern.CLAN_BOMB:
			tutorial_success = "✓ 正确！你成功接炸了！"
			advanced = true
		elif tutorial_step == 4:
			tutorial_success = "继续练习！"
			advanced = true

	if advanced and tutorial_step < 5:
		tutorial_step += 1
		_update_tutorial_guidance()


func get_tutorial_display() -> String:
	var text = tutorial_guidance
	if tutorial_success != "":
		text += "\n" + tutorial_success
	return text


# ============================================================
# 十四、查询与辅助方法
# ============================================================
func get_all_players_info() -> String:
	var info = "===== 状态 =====\n"
	for i in range(players.size()):
		var p = players[i]
		var marker = ""
		if i == current_player_index:
			marker = " ← "
		var ai_tag = "[AI]" if p.is_ai else "[P]"
		var pass_tag = " [跳过]" if p.has_passed else ""
		var bomb_tag = " [禁炸]" if p.clan_bomb_cooling else ""
		info += "%s %s: %d 张牌%s%s%s\n" % [ai_tag, p.player_name, p.get_hand_count(), pass_tag, bomb_tag, marker]
	if table_player_index >= 0:
		var tp = players[table_player_index]
		var pat = UtilsScript.detect_pattern(table_cards)
		var pn = UtilsScript.get_pattern_name(pat)
		var el = UtilsScript.get_element_display(table_cards)
		info += "桌面: %s 打出 %s (%s" % [tp.player_name, _cards_to_string(table_cards), pn]
		if pat == UtilsScript.CardPattern.ELEMENT and el != "":
			info += " " + el
		info += ")"
		if compound_immune:
			info += " [免疫]"
		info += "\n"
	else:
		info += "桌面: 空 (自由出牌)\n"
	if clan_bomb_chain_active:
		info += "⚠ 接炸中！%s 的族炸等待被接\n" % players[clan_bomb_owner].player_name
	info += "牌库: %d 张\n" % database.get_remaining_count()
	if not direction_clockwise:
		info += "方向: 逆时针 ←\n"
	return info


func get_available_patterns(player_idx: int) -> String:
	if player_idx < 0 or player_idx >= players.size():
		return ""
	var p = players[player_idx]
	if clan_bomb_chain_active:
		if player_idx == clan_bomb_owner:
			return "等待他人接炸..."
		return "仅可出: 更大的族炸 / 跳过(抽1张)"
	if sequence_constraint_active and player_idx != table_player_index:
		var cn = UtilsScript.get_pattern_name(sequence_constraint)
		return "顺序约束：必须打出 %s / 跳过(罚抽2张)" % cn
	if is_round_starter or table_cards.is_empty():
		var s = "自由出牌: 单质+化合物"
		if organic_rules_enabled or sequence_rules_enabled:
			var extras: Array = []
			if organic_rules_enabled: extras.append("有机物")
			if sequence_rules_enabled: extras.append("顺序")
			s += "+" + "+".join(extras)
		if not p.clan_bomb_cooling and not clan_bomb_disabled:
			s += "+族炸"
		elif clan_bomb_disabled:
			s += " (族炸已禁用)"
		s += " / 跳过"
		return s
	if p.clan_bomb_cooling:
		return "需要打出更大的牌 / 跳过"
	if table_pattern == UtilsScript.CardPattern.ELEMENT:
		var s = "桌面是单质，只能出更大的单质"
		if not clan_bomb_disabled:
			s += "/族炸"
		s += " / 跳过"
		return s
	if table_pattern == UtilsScript.CardPattern.COMPOUND:
		if compound_immune:
			return "桌面溢出化合物(免疫族炸)，只能出更大的化合物 / 跳过"
		var s = "桌面是化合物，只能出更大的化合物"
		if not clan_bomb_disabled:
			s += "/族炸"
		s += " / 跳过"
		return s
	return "需要打出更大的牌 / 跳过"


func flush_logs() -> Array:
	var logs = log_messages.duplicate()
	log_messages.clear()
	return logs

func _cards_to_string(cards: Array) -> String:
	if cards.is_empty():
		return "[]"
	var syms: Array = []
	for c in cards:
		syms.append(c.symbol)
	return "[%s]" % ", ".join(syms)

func is_game_over() -> bool:
	return phase == 2

func get_winner() -> PlayerInfo:
	if winner_index < 0 or winner_index >= players.size():
		return null
	return players[winner_index]