# ============================================================
# GameManager.gd - 游戏规则引擎
# 回合管理 / 出牌校验 / 族炸接炸链 / 上限弃牌
# 补充规则：有机物立即胜利 / 顺序牌型（方向反转+指定牌型）
# ============================================================

const CardDatabaseScript = preload("res://scripts/CardDatabase.gd")
const CardDataScript = preload("res://scripts/CardData.gd")
const CardPatternsScript = preload("res://scripts/CardPatterns.gd")
const CompoundSolverScript = preload("res://scripts/CompoundSolver.gd")
const PlayerManagerScript = preload("res://scripts/PlayerManager.gd")
const GameLoggerScript = preload("res://scripts/GameLogger.gd")
const TutorialControllerScript = preload("res://scripts/TutorialController.gd")

# ============================================================
# 一、游戏常量
# ============================================================
const MIN_PLAYERS = PlayerManagerScript.MIN_PLAYERS
const MAX_PLAYERS = PlayerManagerScript.MAX_PLAYERS
const INITIAL_HAND_SIZE = PlayerManagerScript.INITIAL_HAND_SIZE

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
var table_custom_valences: Dictionary = {}  # 桌面化合物的实际化合价（渲染化学式/排序/化合价显示）
var is_round_starter: bool = true

# 信息记录（统一日志模块）
var logger: RefCounted = GameLoggerScript.new()
var log_messages: Array:
	get:
		return logger.log_messages

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
# 四、教程状态变量（委托到 TutorialController）
# ============================================================
var tutorial_controller: RefCounted = null
var tutorial_level: int = 0             # 0=自由模式, 1=第一关, 2=第二关
var tutorial_step: int = 0              # 当前教程步骤
var tutorial_guidance: String = ""      # 当前引导文本
var tutorial_success: String = ""       # 成功提示（一次性显示）
var tutorial_level0_phase: int = 0      # 第0关阶段: 0=未开始 1=UI介绍 2=流程介绍 3=牌局
var ai_no_draw: bool = false            # AI在第0关不抽牌
var level0_rule_tip: String = ""        # 第0关规则提示（越大越小/同类同出/牌权争夺）
var level0_last_player_action: String = ""  # 玩家上一次操作类型



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
	table_custom_valences.clear()
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
	logger.clear_logs()

	database = CardDatabaseScript.new()
	database.generate_deck()
	database.shuffle()

	# 创建玩家（人类在前，AI在后）
	var human_count = player_count - ai_count
	for i in range(player_count):
		var p_name = "玩家 %d" % (i + 1) if i < human_count else "AI %d" % (i + 1 - human_count)
		players.append(PlayerManagerScript.PlayerInfo.new(p_name, i >= human_count))

	# 每人发 8 张牌并排序
	for player in players:
		var cards = database.draw_cards(INITIAL_HAND_SIZE)
		for card in cards:
			player.add_card(card)
		player.sort_hand_by_atomic_number()

	phase = 1
	logger.add_log("===== 游戏开始 =====")
	if organic_rules_enabled or sequence_rules_enabled:
		var rules_list: Array = []
		if organic_rules_enabled: rules_list.append("有机物胜利")
		if sequence_rules_enabled: rules_list.append("顺序牌型")
		logger.add_log("【补充规则已启用】" + " + ".join(rules_list))
	logger.add_log("当前回合: %s (自由出牌)" % players[current_player_index].player_name)
	return true


# ============================================================
# 七、查询当前玩家
# ============================================================
func get_current_player() -> PlayerManagerScript.PlayerInfo:
	if players.is_empty():
		return null
	return players[current_player_index]

func get_current_player_index() -> int:
	return current_player_index


# ============================================================
# 八、出牌校验核心函数
# ============================================================
# intended_pattern: 玩家明确选择的牌型（CardPattern 枚举值，-1 表示自动检测）。
# 当牌组同时满足多种牌型（如"既是族炸也是顺序"）时，以玩家选择的为准。
func play_cards(player_index: int, cards: Array, custom_valences: Dictionary = {}, intended_pattern: int = -1) -> int:
	if player_index < 0 or player_index >= players.size() or cards.is_empty():
		return -1

	var player = players[player_index]
	var skip_bomb = custom_valences.size() >= 2
	# 合成有机物时也跳过族炸检测
	if custom_valences.has("_organic"):
		skip_bomb = true

	# 玩家明确选择"作为顺序"时，顺序优先于族炸（如 Fe+Co+Ni 既是 VIII 族族炸又是 26/27/28 顺序）
	var prefer_sequence = (intended_pattern == CardPatternsScript.CardPattern.SEQUENCE)
	var pattern = CardPatternsScript.detect_pattern(cards, skip_bomb, prefer_sequence)
	if pattern == -1:
		return -1

	# 若玩家明确选择了牌型，校验检测结果与意图一致
	if intended_pattern >= 0 and pattern != intended_pattern:
		# 启用有机物规则时，"合成化合物"路径可打出有机物（有机物是化合物子集）
		if organic_rules_enabled and pattern == CardPatternsScript.CardPattern.ORGANIC \
				and intended_pattern == CardPatternsScript.CardPattern.COMPOUND:
			pass
		else:
			return -1

	# -------- 第零关AI禁止出族炸 --------
	if tutorial_level == 0 and tutorial_level0_phase >= 1 and player.is_ai and pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
		return -3

	# -------- 顺序约束检查 --------
	if sequence_constraint_active and not is_round_starter and player_index != table_player_index:
		if sequence_constraint >= 0 and pattern != sequence_constraint:
			# 指定"化合物"时，有机物（化合物子类）同样满足约束
			var constraint_match = (sequence_constraint == CardPatternsScript.CardPattern.COMPOUND \
					and pattern == CardPatternsScript.CardPattern.ORGANIC)
			if not constraint_match:
				return -6  # 不符合顺序指定的牌型约束

	# -------- 族炸判定 --------
	if pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
		if clan_bomb_disabled:
			return -3  # 本局禁止族炸
		if not clan_bomb_chain_active and player.clan_bomb_cooling:
			return -3
		if compound_immune and not clan_bomb_chain_active:
			return -4  # 溢出化合物免疫族炸
		if clan_bomb_chain_active:
			if table_cards.size() > 0:
				var cmp = CardPatternsScript.compare_cards(cards, table_cards)
				if cmp <= 0:
					return -2
	else:
		# -------- 非族炸：检查是否可以接当前桌面 --------
		if clan_bomb_chain_active:
			return -1  # 接炸模式只能出族炸
		if not is_round_starter:
			if table_pattern == CardPatternsScript.CardPattern.ELEMENT and pattern != CardPatternsScript.CardPattern.ELEMENT:
				return -4  # 单质后只能接单质或族炸
			if table_pattern == CardPatternsScript.CardPattern.COMPOUND and pattern != CardPatternsScript.CardPattern.COMPOUND:
				return -4  # 化合物后只能接化合物或族炸
			if table_cards.size() > 0:
				# 桌面是顺序牌：无大小比较（顺序打出后复位桌面），下家仅受指定牌型约束
				if table_pattern == CardPatternsScript.CardPattern.SEQUENCE:
					pass
				# 顺序接顺序：无大小比较，直接通过
				elif table_pattern == CardPatternsScript.CardPattern.SEQUENCE and pattern == CardPatternsScript.CardPattern.SEQUENCE:
					pass
				else:
					var cmp = CardPatternsScript.compare_cards(cards, table_cards)
					if cmp <= 0:
						return -2

	# -------- 化合物比例校验（必须在移除卡牌之前） --------
	if pattern == CardPatternsScript.CardPattern.COMPOUND:
		var fi = CompoundSolverScript.get_compound_formula(cards, custom_valences)
		if not fi.is_empty() and not fi.get("ratio_ok", false):
			return -1  # 比例不匹配

	# -------- 从手牌移除，更新桌面 --------
	player.remove_cards(cards)
	table_cards = cards.duplicate()
	table_custom_valences = custom_valences.duplicate()
	table_pattern = pattern
	table_player_index = player_index
	compound_immune = false

	# -------- 构建日志 --------
	var pname = CardPatternsScript.get_pattern_name(pattern)
	var elem_name = CardPatternsScript.get_element_display(cards)
	var card_str = _cards_to_string(cards)
	var log_msg = "%s 打出了 %s (%s" % [player.player_name, card_str, pname]
	if pattern == CardPatternsScript.CardPattern.ELEMENT and elem_name != "":
		log_msg += " " + elem_name
	if pattern == CardPatternsScript.CardPattern.COMPOUND:
		var fi = CompoundSolverScript.get_compound_formula(cards, custom_valences)
		if not fi.is_empty():
			var formula = fi.get("formula", "??")
			log_msg += " " + formula
			# 附加 IUPAC 中文命名
			var comp_name = CompoundSolverScript.get_compound_name(cards, custom_valences)
			if comp_name != "":
				log_msg += "（" + comp_name + "）"
	if pattern == CardPatternsScript.CardPattern.ORGANIC:
		log_msg += " " + CompoundSolverScript.get_organic_name(cards)
	log_msg += ")"
	logger.add_log(log_msg)

	# -------- 第0关规则提示检测 --------
	if tutorial_level == 0 and not player.is_ai:
		level0_rule_tip = ""
		if pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
			level0_rule_tip = "牌权争夺"
		elif not is_round_starter and table_pattern == pattern:
			level0_rule_tip = "越大越小"
		elif is_round_starter:
			level0_rule_tip = "同类同出"
		if pattern == CardPatternsScript.CardPattern.ELEMENT or pattern == CardPatternsScript.CardPattern.COMPOUND:
			level0_last_player_action = "同类同出"

	# -------- 有机物：立即胜利 --------
	if pattern == CardPatternsScript.CardPattern.ORGANIC:
		phase = 2
		winner_index = player_index
		logger.add_log("===== 🎉 %s 打出有机物，立即获胜！=====" % player.player_name)
		clan_bomb_chain_active = false
		sequence_constraint_active = false
		return 0

	# -------- 族炸：启动接炸链 + 牌权移交 --------
	if pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
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
	if pattern == CardPatternsScript.CardPattern.SEQUENCE:
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
	if pattern == CardPatternsScript.CardPattern.COMPOUND:
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
	var pname = CardPatternsScript.get_pattern_name(constraint_pattern)
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

	# 顺序约束激活：被指定的下一名玩家跳过 → 罚抽2张并结束约束（下下名自由出牌）
	if sequence_constraint_active and not is_round_starter and player_index != table_player_index:
		# 手牌达上限时先弃1张（AI自动弃，人类由UI层处理）
		if player.get_hand_count() >= hand_limit and player.is_ai:
			var discard = _ai_pick_discard(player)
			if discard != null:
				player.remove_cards([discard])
				log_messages.append("%s 手牌达上限，自动弃置 %s 并跳过" % [player.player_name, discard.symbol])
		player_fail_sequence_constraint(player_index)
		return

	# 上限弃牌：手牌达上限时不能直接跳过，必须先弃 1 张
	# 人类玩家由 UI 层负责选牌弃置（_on_discard_mode）；AI 在此自动弃 1 张
	if player.get_hand_count() >= hand_limit:
		if player.is_ai:
			var discard = _ai_pick_discard(player)
			if discard != null:
				player.remove_cards([discard])
				log_messages.append("%s 手牌达上限，自动弃置 %s 并跳过" % [player.player_name, discard.symbol])
			else:
				if clan_bomb_chain_active:
					log_messages.append("%s 手牌达上限，不接炸" % player.player_name)
				else:
					log_messages.append("%s 手牌达上限，跳过" % player.player_name)
		else:
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


# AI 自动选择弃置的牌：优先弃置"孤立单张"（出现次数最少且原子序数最大者），
# 保留可能组成化合物/族炸的牌。策略简单且行为一致，与人类玩家上限弃牌等价。
func _ai_pick_discard(player):
	if player.hand.is_empty():
		return null
	# 统计每种元素出现次数
	var count_by_symbol: Dictionary = {}
	for c in player.hand:
		count_by_symbol[c.symbol] = count_by_symbol.get(c.symbol, 0) + 1
	# 优先弃置出现次数最少、原子序数最大的单张
	var best = null
	var best_score = -1.0
	for c in player.hand:
		var cnt = count_by_symbol[c.symbol]
		var score = c.atomic_number * 1.0 - cnt * 100.0  # 次数多→保留；原子序数大→优先弃
		if best == null or score > best_score:
			best = c
			best_score = score
	return best


func _get_hand_limit() -> int:
	return PlayerManagerScript.get_hand_limit(players.size())


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
	table_custom_valences.clear()
	is_round_starter = true
	_reset_all_passes()
	current_player_index = owner_idx
	log_messages.append("无人接炸！%s 自由出牌" % players[owner_idx].player_name)


# -------- 新一轮开始 --------
func _start_new_round() -> void:
	table_cards.clear()
	table_pattern = -1
	table_player_index = -1
	table_custom_valences.clear()
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
# 十二、教程关卡系统（委托到 TutorialController）
# ============================================================
func init_tutorial(level: int) -> bool:
	phase = 0
	players.clear()
	table_cards.clear()
	table_player_index = -1
	table_pattern = -1
	table_custom_valences.clear()
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
	logger.clear_logs()
	tutorial_level0_phase = 0
	ai_no_draw = false
	level0_rule_tip = ""
	level0_last_player_action = ""

	database = CardDatabaseScript.new()
	database.generate_deck()

	# 创建教程控制器（若未创建）
	if tutorial_controller == null:
		tutorial_controller = TutorialControllerScript.new(self)

	# 委托教程初始化（含预设手牌、level0 牌库、引导文本）
	var ok = tutorial_controller.init_tutorial(level)
	if not ok:
		return false

	# 从控制器同步教程状态（外部仍通过 GameManager 访问）
	_sync_tutorial_state_from_controller()

	phase = 1
	logger.add_log("===== 教程关卡 %d 开始 =====" % level)
	logger.add_log("当前回合: %s (自由出牌)" % players[current_player_index].player_name)
	return true


# 从控制器同步教程状态变量（保持外部接口一致）
func _sync_tutorial_state_from_controller() -> void:
	if tutorial_controller == null:
		return
	tutorial_level = tutorial_controller.tutorial_level
	tutorial_step = tutorial_controller.tutorial_step
	tutorial_guidance = tutorial_controller.tutorial_guidance
	tutorial_success = tutorial_controller.tutorial_success
	tutorial_level0_phase = tutorial_controller.tutorial_level0_phase
	ai_no_draw = tutorial_controller.ai_no_draw
	level0_rule_tip = tutorial_controller.level0_rule_tip
	level0_last_player_action = tutorial_controller.level0_last_player_action


# 出牌后的教程进度检查（委托到控制器）
func _check_tutorial_progress(pattern: int, player_is_human: bool) -> void:
	if tutorial_controller == null:
		return
	tutorial_controller.check_tutorial_progress(pattern, player_is_human)
	_sync_tutorial_state_from_controller()


func get_tutorial_display() -> String:
	if tutorial_controller == null:
		return ""
	return tutorial_controller.get_tutorial_display()


# UI 更新第0关阶段时调用（同步镜像与控制器）
func set_tutorial_level0_phase(phase: int) -> void:
	tutorial_level0_phase = phase
	if tutorial_controller != null:
		tutorial_controller.tutorial_level0_phase = phase
		tutorial_controller._update_tutorial_level0_guidance()
		_sync_tutorial_state_from_controller()


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
		var pat = CardPatternsScript.detect_pattern(table_cards)
		var pn = CardPatternsScript.get_pattern_name(pat)
		var el = CardPatternsScript.get_element_display(table_cards)
		info += "桌面: %s 打出 %s (%s" % [tp.player_name, _cards_to_string(table_cards), pn]
		if pat == CardPatternsScript.CardPattern.ELEMENT and el != "":
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
		var cn = CardPatternsScript.get_pattern_name(sequence_constraint)
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
	if table_pattern == CardPatternsScript.CardPattern.ELEMENT:
		var s = "桌面是单质，只能出更大的单质"
		if not clan_bomb_disabled:
			s += "/族炸"
		s += " / 跳过"
		return s
	if table_pattern == CardPatternsScript.CardPattern.COMPOUND:
		if compound_immune:
			return "桌面溢出化合物(免疫族炸)，只能出更大的化合物 / 跳过"
		var s = "桌面是化合物，只能出更大的化合物"
		if not clan_bomb_disabled:
			s += "/族炸"
		s += " / 跳过"
		return s
	return "需要打出更大的牌 / 跳过"


func flush_logs() -> Array:
	return logger.flush_logs()


# ============================================================
# 十四之二、只读接口（供 UI 层访问，避免直接操作内部状态）
# ============================================================
func get_players() -> Array:
	return players

func get_player_count() -> int:
	return players.size()

func get_hand_limit() -> int:
	return _get_hand_limit()

func get_table_cards() -> Array:
	return table_cards

func get_table_pattern() -> int:
	return table_pattern

func get_table_player_index() -> int:
	return table_player_index

func get_table_custom_valences() -> Dictionary:
	return table_custom_valences

func get_database() -> RefCounted:
	return database

func get_is_round_starter() -> bool:
	return is_round_starter

func get_phase() -> int:
	return phase

func get_organic_rules_enabled() -> bool:
	return organic_rules_enabled

func get_sequence_rules_enabled() -> bool:
	return sequence_rules_enabled

func get_direction_clockwise() -> bool:
	return direction_clockwise

func is_clan_bomb_chain_active() -> bool:
	return clan_bomb_chain_active

func get_clan_bomb_owner() -> int:
	return clan_bomb_owner

func is_compound_immune() -> bool:
	return compound_immune

func get_sequence_constraint() -> int:
	return sequence_constraint

func is_sequence_constraint_active() -> bool:
	return sequence_constraint_active

func _cards_to_string(cards: Array) -> String:
	if cards.is_empty():
		return "[]"
	var syms: Array = []
	for c in cards:
		syms.append(c.symbol)
	return "[%s]" % ", ".join(syms)

func is_game_over() -> bool:
	return phase == 2

func get_winner() -> PlayerManagerScript.PlayerInfo:
	if winner_index < 0 or winner_index >= players.size():
		return null
	return players[winner_index]