# ============================================================
# GameManager.gd - 游戏规则引擎
# 回合管理 / 出牌校验 / 族炸接炸链 / 上限弃牌
# 补充规则：有机物立即胜利 / 顺序牌型（方向反转+指定牌型）/ 允许卤族互化
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

# 联机地基（P11-B）常量 —— 事件返回码与哈希参数
const EVENT_UNKNOWN = -100        # 未知事件类型（与规则码 -1..-8 不冲突）
const EVENT_BAD_PAYLOAD = -101    # uid 不存在 / 重复 / 座位越界
const FNV_OFFSET_BASIS = 2166136261
const FNV_PRIME = 16777619

# ============================================================
# 二、核心变量 (牌库/玩家/桌面)
# ============================================================
var database: RefCounted = null
var players: Array = []
var current_player_index: int = 0
var turn_count: int = 0          # 本局换手次数（结束页「总回合」统计；init_* 归零）
var phase: int = 0
var winner_index: int = -1
var table_cards: Array = []
var table_player_index: int = -1
var table_pattern: int = -1    # 桌面牌型（用于限制接牌类型）
var table_custom_valences: Dictionary = {}  # 桌面化合物的实际化合价（渲染化学式/排序/化合价显示）
var is_round_starter: bool = true

# 最近一次 play_cards 被 -2（牌不够大）拒绝的具体原因。
# UI 只能拿到返回码，无法说明「是牌型被压制 / 张数不够 / 原子序数和不够」，
# 于是统一文案「牌不够大」。这里由引擎在拒绝点写好原因，UI 直接展示。
var last_reject_reason: String = ""

# 最近一次 play_cards / validate_play 判定出的牌型（-1 = 还没判定 / 非法）。
# 牌型有「二义性」（同一批牌既像族炸又能配成化合物），判定真相只在引擎里：
# UI / 提示 / AI 需要知道「这批牌被当成什么」时读这个字段，不要自己再 detect 一遍。
var last_evaluated_pattern: int = -1

# 信息记录（统一日志模块）
var logger: RefCounted = GameLoggerScript.new()
var log_messages: Array:
	get:
		return logger.log_messages

# ============================================================
# 三、规则状态变量
# ============================================================
var compound_immune: bool = false          # 溢出化合物免疫族炸
# 引擎自己「读出来」的化合价（_evaluate_play 里用价态搜索兜底时写入）。
# 非空 = 这次出牌没让玩家选价，引擎自己解出来了，桌面要用这套价显示。
var last_understood_valences: Dictionary = {}
var clan_bomb_chain_active: bool = false   # 族炸接炸链激活
var clan_bomb_owner: int = -1              # 接炸链引爆者索引
var clan_bomb_disabled: bool = false       # 禁用族炸（第一关）

# ============================================================
# 三之二、补充规则状态变量
# ============================================================
var organic_rules_enabled: bool = false        # 有机物规则开关
var sequence_rules_enabled: bool = false       # 顺序规则开关
# 允许卤族互化：默认 false（硬规则 —— F/Cl/Br/I 之间不可互相「化合」）。
# 仅放开「化合物」牌型；同族族炸（F+Cl 当族炸打出）本来就不是化合，始终合法。
var halogen_exchange_allowed: bool = false
# 元素限制：默认 false（29 种元素全上桌）。
# 打开后牌库 = 前 20 号元素（H~Ca）+ allowed_extra_elements（副族 / Br / I）。
var element_limit_enabled: bool = false
var allowed_extra_elements: Array = []
var direction_clockwise: bool = true           # 出牌方向（true=顺时针, false=逆时针）
var sequence_constraint: int = -1              # 顺序指定牌型约束（-1=无约束）
var sequence_constraint_active: bool = false   # 顺序约束是否激活
# 被指定的玩家索引（-1=无）。顺序牌会让方向先反转，再指定「反转后的下一名」，
# 只有这一名玩家受约束：必须打出指定牌型，否则罚抽 2 张。
# 别人出族炸、别人出牌、接炸链结束都不会解除该约束。
var sequence_constraint_target: int = -1

# ============================================================
# 三之三、联机地基状态（P11-B）
# ============================================================
# 牌库种子：<0 = 随机（单机默认，行为与历史版本一致）；
#           >=0 = 确定性洗牌（联机时由主机下发，两端必得同一副牌序）
var deck_seed: int = -1
# 已成功推进局面的联机事件序列（主机广播日志 / 客人重放 / 回放 / 断线重连）
var event_log: Array = []

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
# rng_seed：牌库洗牌种子。默认 -1 = 随机（单机行为不变）；
#           联机时由主机下发，两端同一 seed → 同一副牌序（确定性前提）。
func init_game(player_count: int = 4, ai_count: int = 3, rng_seed: int = -1) -> bool:
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		push_error("init_game: player_count=%d out of range [%d,%d]" % [player_count, MIN_PLAYERS, MAX_PLAYERS])
		return false
	if ai_count >= player_count:
		push_error("init_game: ai_count=%d >= player_count=%d" % [ai_count, player_count])
		return false

	turn_count = 0
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
	sequence_constraint_target = -1
	tutorial_level = 0
	tutorial_step = 0
	tutorial_guidance = ""
	tutorial_success = ""
	tutorial_level0_phase = 0
	ai_no_draw = false
	level0_rule_tip = ""
	level0_last_player_action = ""
	logger.clear_logs()
	deck_seed = rng_seed
	event_log.clear()

	database = CardDatabaseScript.new()
	database.generate_deck(get_allowed_symbols())
	database.shuffle(rng_seed)

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
	if organic_rules_enabled or sequence_rules_enabled or halogen_exchange_allowed or element_limit_enabled:
		var rules_list: Array = []
		if organic_rules_enabled: rules_list.append("有机物胜利")
		if sequence_rules_enabled: rules_list.append("顺序牌型")
		if halogen_exchange_allowed: rules_list.append("允许卤族互化")
		if element_limit_enabled:
			var extra_txt = "无额外元素" if allowed_extra_elements.is_empty() else "/".join(allowed_extra_elements)
			rules_list.append("元素限制（前 20 号 + %s）" % extra_txt)
		logger.add_log("【补充规则已启用】" + " + ".join(rules_list))
	if element_limit_enabled:
		logger.add_log("【元素限制】牌库 %d 种元素 · %d 张牌" % [get_allowed_element_count(), get_deck_size()])
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
#
# 结构（P13 拆分）：
#   _evaluate_play()  只读判定（唯一规则源），返回码 + last_evaluated_pattern
#   validate_play()   对外只读入口（UI 置灰 / 提示 / AI 预检用，绝不改局面）
#   play_cards()      先判定、通过后才落子（改手牌 / 桌面 / 轮转）
# 为什么要拆：以前「能不能打」的规则散在 play_cards + HintAdvisor._check 两处，
# 两边稍有出入就会出现「提示说能打、点了却被拒」。现在规则只有一份，
# 提示 / AI / UI 直接问引擎，不再各自复读一遍条件。

# ---- 只读判定（不改变局面）----
# 返回：0 = 合法可出 / 1 = 合法且是顺序牌（出牌后要选指定牌型）/ 负数 = 非法（同 play_cards）
# 唯一的副作用是诊断字段 last_reject_reason / last_evaluated_pattern（不进 state_hash）。
func validate_play(player_index: int, cards: Array, custom_valences: Dictionary = {},
		intended_pattern: int = -1) -> int:
	return _evaluate_play(player_index, cards, custom_valences, intended_pattern)


func get_last_evaluated_pattern() -> int:
	return last_evaluated_pattern


# ============================================================
# 八之一、先出后验（P14-C）：玩家只选牌，牌型由引擎按固定优先级挑
# ============================================================
# 为什么需要：老流程是「出牌(选牌型) → 单质 / 化合物 / 顺序 / 族炸 → （化合物还要逐元素选价）」，
# 新手常在「该选哪一种」上卡住，选错就弹「非法出牌！」。真机截图里玩家连点两次都被拒。
# 现在给一条「直接出牌」的路径：候选顺序固定（决定同一组牌打出什么，必须稳定可解释），
# 每个候选都先用 validate_play() 只读预检，第一个通过的才落子。
#   1) 有机物   —— 打出即胜，最先
#   2) 单质     —— 1 张，或 2 张同种双原子（H₂/O₂/N₂/F₂/Cl₂/Br₂/I₂）
#   3) 化合物   —— 统一价态解优先，其次混合价态解（Fe₃O₄）
#   4) 顺序     —— 需本局开启顺序规则
#   5) 族炸     —— 同族不同元素，2 张起
# 化合物排在手顺序/族炸之前：同族元素往往也能配成化合物（N+P / B+P），
# 而化合物是「有化学意义」的那一种，也更容易接住桌面（P13 的牌型二义性同一考虑）。
func auto_play(player_index: int, cards: Array) -> int:
	var plan := auto_play_preview(player_index, cards)
	var code: int = int(plan["code"])
	if code < 0:
		# 把「最有用」的那条原因留下（化合物配不平 >> 「不能出族炸」）
		last_reject_reason = str(plan["reason"])
		return code
	return play_cards(player_index, cards, plan["custom_valences"], int(plan["pattern"]))


# 只读预览（不落子、只写诊断字段）：UI 用它决定按钮状态，测试用它锁死候选顺序。
# 返回 {"code": 同 play_cards, "pattern": 命中的牌型, "custom_valences": 该牌型要用的价,
#      "reason": 全军覆没时的原因}
#
# 全败时的「原因」怎么挑（P14-E 修）：以前取的是**最后一个候选**（族炸）的 last_reject_reason，
# 于是「桌面 F、手牌 S」这种明明只是牌不够大的出牌，会显示「所选牌型与这组牌的实际牌型
# 不一致（实际是：单质）」—— 玩家走的是「直接出牌」，压根没选过牌型，这句话毫无意义。
# 现在按「谁最解释得清」排优先级：
#   1) 真实牌型那条候选 —— detect_pattern 认定的那种，-2 会带上原子序数和 / 张数 / 打平细分；
#   2) 化合物那条 —— H+H+C+N 这类 detect 认不出的组合，只有化合物求解器能说清「比例对不上」；
#   3) 按真实牌型再判一次（真实牌型没有对应候选时，如顺序规则关掉的 26/27/28）。
#      这次 intended_pattern == detect 的结论，绝不会再吐出「牌型不一致」；
#   4) 以上都没有 → 第一条候选兜底。
func auto_play_preview(player_index: int, cards: Array) -> Dictionary:
	var out := {"code": -1, "pattern": -1, "custom_valences": {}, "reason": ""}
	if cards.is_empty():
		out["reason"] = "请先选择要打出的牌"
		return out
	# 引擎眼里的「这组牌到底是什么」（与 _evaluate_play 里 detect 的口径一致：
	# 不跳族炸、不偏爱顺序，因为玩家没指定牌型）
	var actual: int = CardPatternsScript.detect_pattern(cards, false, false)
	var first_code: int = 0
	var first_reason: String = ""
	var actual_code: int = 0
	var actual_reason: String = ""
	var compound_code: int = 0
	var compound_reason: String = ""
	for cand in _auto_play_candidates(cards):
		var code: int = validate_play(player_index, cards, cand["cv"], int(cand["pattern"]))
		if code >= 0:
			out["code"] = code
			out["pattern"] = int(cand["pattern"])
			out["custom_valences"] = cand["cv"]
			return out
		if first_reason == "":
			first_code = code
			first_reason = last_reject_reason
		if actual >= 0 and int(cand["pattern"]) == actual and actual_reason == "":
			actual_code = code
			actual_reason = last_reject_reason
		if int(cand["pattern"]) == CardPatternsScript.CardPattern.COMPOUND and compound_reason == "":
			compound_code = code
			compound_reason = last_reject_reason

	var use_code: int = first_code
	var use_reason: String = first_reason
	if actual_reason != "":
		use_code = actual_code
		use_reason = actual_reason
	elif compound_reason != "":
		use_code = compound_code
		use_reason = compound_reason
	elif actual >= 0:
		var real_code: int = validate_play(player_index, cards, {}, actual)
		if real_code < 0 and last_reject_reason != "":
			use_code = real_code
			use_reason = last_reject_reason
	out["code"] = use_code
	out["reason"] = use_reason
	return out


# 候选列表（顺序即优先级）。每组牌最多 5 条，且都带 intended_pattern，
# 这样「既是族炸又能配成化合物」的牌不会被 detect_pattern 的口径带偏。
func _auto_play_candidates(cards: Array) -> Array:
	var out: Array = []
	if CardPatternsScript.detect_pattern(cards, true) == CardPatternsScript.CardPattern.ORGANIC:
		out.append({"pattern": CardPatternsScript.CardPattern.ORGANIC, "cv": {"_organic": true}})
	out.append({"pattern": CardPatternsScript.CardPattern.ELEMENT, "cv": {}})
	var uniform := CompoundSolverScript.get_uniform_valence_pairs(cards)
	if not uniform.is_empty():
		out.append({"pattern": CardPatternsScript.CardPattern.COMPOUND, "cv": uniform})
	var mixed := CompoundSolverScript.get_mixed_valence_pairs(cards)
	if not mixed.is_empty():
		out.append({"pattern": CardPatternsScript.CardPattern.COMPOUND, "cv": mixed})
	if sequence_rules_enabled:
		out.append({"pattern": CardPatternsScript.CardPattern.SEQUENCE, "cv": {}})
	out.append({"pattern": CardPatternsScript.CardPattern.CLAN_BOMB, "cv": {}})
	return out


# ---- 规则正文：所有「能不能打」的判断都在这里 ----
# 注意：本函数绝不能改手牌 / 桌面 / 轮转 / 日志，否则 validate_play 就不再只读。
func _evaluate_play(player_index: int, cards: Array, custom_valences: Dictionary,
		intended_pattern: int) -> int:
	last_reject_reason = ""
	last_evaluated_pattern = -1
	if player_index < 0 or player_index >= players.size() or cards.is_empty():
		return -1

	var player = players[player_index]

	# -------- 元素限制（牌库构成规则，兜底校验）--------
	# 正常路径下越界元素不会出现在手牌里（牌库已按限制生成），
	# 这里只拦注入 / 存档 / 教程预设之类的意外情况。
	if element_limit_enabled:
		for c in cards:
			if not is_element_allowed(c.symbol):
				return -8

	var skip_bomb = custom_valences.size() >= 2
	# 合成有机物时也跳过族炸检测
	if custom_valences.has("_organic"):
		skip_bomb = true

	# 玩家明确选择"作为顺序"时，顺序优先于族炸（如 Fe+Co+Ni 既是 VIII 族族炸又是 26/27/28 顺序）
	var prefer_sequence = (intended_pattern == CardPatternsScript.CardPattern.SEQUENCE)
	var pattern = CardPatternsScript.detect_pattern(cards, skip_bomb, prefer_sequence)
	if pattern == -1:
		last_reject_reason = "这组牌不构成任何合法牌型（单质 / 化合物 / 顺序 / 族炸 / 有机物）"
		return -1

	# 若玩家明确选择了牌型，校验检测结果与意图一致
	if intended_pattern >= 0 and pattern != intended_pattern:
		# 启用有机物规则时，"合成化合物"路径可打出有机物（有机物是化合物子集）
		if organic_rules_enabled and pattern == CardPatternsScript.CardPattern.ORGANIC \
				and intended_pattern == CardPatternsScript.CardPattern.COMPOUND:
			pass
		else:
			last_reject_reason = "所选牌型与这组牌的实际牌型不一致（实际是：%s）" \
				% CardPatternsScript.get_pattern_name(pattern)
			return -1

	# -------- 卤族互化（仅化合物；族炸不受限）--------
	# 硬规则默认禁止：F/Cl/Br/I 之间不能互相「化合」（如 ClF）。
	# 允许卤族互化（补充规则）打开后放行；同族族炸不是化合，始终合法。
	if pattern == CardPatternsScript.CardPattern.COMPOUND and not halogen_exchange_allowed \
			and is_halogen_mix(cards):
		return -7

	# -------- 第零关AI禁止出族炸 --------
	if tutorial_level == 0 and tutorial_level0_phase >= 1 and player.is_ai and pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
		return -3

	# -------- 顺序约束检查 --------
	# 只有「被指定的那名玩家」受约束：其他人出什么牌都不受限，也不会替它解约束。
	if sequence_constraint_active and sequence_constraint_target == player_index:
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
		# 冷却优先于接炸链：冷却期间一律不能再出族炸（含接炸），
		# 只能出化合物解除，或跳过放弃接炸（见 GAMEPLAY_RULES「族炸冷却」）。
		# 若在此处放行接炸，冷却玩家可借别人的族炸反复接炸，冷却形同虚设。
		if player.clan_bomb_cooling:
			return -3
		if compound_immune and not clan_bomb_chain_active:
			return -4  # 溢出化合物免疫族炸
		if clan_bomb_chain_active:
			if table_cards.size() > 0:
				var cmp = CardPatternsScript.compare_cards(cards, table_cards, pattern, table_pattern)
				if cmp <= 0:
					last_reject_reason = _compare_fail_reason(cards, pattern, table_cards, table_pattern, cmp)
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
				# 桌面是顺序牌：无大小比较（下家只受指定牌型约束）
				if table_pattern != CardPatternsScript.CardPattern.SEQUENCE:
					# 显式传入双方牌型：table_pattern 是「桌面实际被当成的牌型」，
					# 不能用 detect_pattern() 重新推断（同一批牌可能既是族炸又像化合物）。
					var cmp = CardPatternsScript.compare_cards(cards, table_cards, pattern, table_pattern)
					if cmp <= 0:
						last_reject_reason = _compare_fail_reason(cards, pattern, table_cards, table_pattern, cmp)
						return -2

	# -------- 化合物比例校验 --------
	# 给不出化学式（无法配平 / 电负性倒置 / 含稀有气体）一律拒绝。
	# 旧实现「空式子就放行」会让 NCl / BrN / IN 这类假化合物混进桌面。
	if pattern == CardPatternsScript.CardPattern.COMPOUND:
		var fi = CompoundSolverScript.get_compound_formula(cards, custom_valences)
		last_understood_valences = {}
		# 默认配平只覆盖主流解（O 一律取 −2、非金属一律取最低负价）。
		# H₂O₂ / CaO₂ 这类过氧根、NCl₃ / BCl₃ 这类「非金属作正价」只能靠价态搜索找到 ——
		# 玩家 / AI 没显式选价时在这里补一次搜索解，否则这些牌永远打不出来。
		if custom_valences.is_empty() and (fi.is_empty() or not fi.get("ratio_ok", false)):
			var auto_cv: Dictionary = CompoundSolverScript.get_valence_pairs(cards)
			if not auto_cv.is_empty():
				var fi_auto = CompoundSolverScript.get_compound_formula(cards, auto_cv)
				if not fi_auto.is_empty() and bool(fi_auto.get("ratio_ok", false)):
					fi = fi_auto
					# 回写给桌面：否则 table_custom_valences 是空的，
					# 桌面小卡重新算化学式又会得到「2HO」而不是 H₂O₂。
					last_understood_valences = auto_cv.duplicate()
		if fi.is_empty() or not fi.get("ratio_ok", false):
			# P14-B：拒绝时写清原因（玩家唯一能自查的量是总电荷 Σ，见 _compound_reject_reason）
			last_reject_reason = _compound_reject_reason(cards, custom_valences)
			return -1  # 无法配平 / 比例不匹配

	last_evaluated_pattern = pattern
	return 1 if pattern == CardPatternsScript.CardPattern.SEQUENCE else 0


# 化合物被拒的「人话」解释（P14-B）：UI 的 _handle_result(-1) 直接把它拼在「非法出牌！」后面。
# 为什么需要：玩家选了化合价、点了「确认打出」，只看到一句「非法出牌！」——
# 真机截图里 H,H,C,N 两次都被拒，玩家完全不知道自己只是多带了一张 H。
# Σ 按「张数」累加（2 张 H 就是 2 份价），这才是玩家心里算的那个数。
func _compound_reject_reason(cards: Array, custom_valences: Dictionary) -> String:
	if custom_valences.is_empty() or custom_valences.has("_organic"):
		return "这组牌配不出任何已知化合物的化学式（原子比例不匹配）"
	var total: int = 0
	for c in cards:
		var v = custom_valences.get(c.symbol, 0)
		if v is Array:
			# 混合价态（Fe₃O₄ 之类）：本次配法无解，不是简单的 Σ 问题
			return "混合价态配不平：这组牌没有可行的价态组合"
		total += int(v)
	if total != 0:
		return "化合价配不平：Σ = %+d（需 0）" % total
	return "原子比例与任何化学式都对不上（化学价态配不平）"


# 出牌：先只读判定，通过后才落子。
func play_cards(player_index: int, cards: Array, custom_valences: Dictionary = {}, intended_pattern: int = -1) -> int:
	var code: int = _evaluate_play(player_index, cards, custom_valences, intended_pattern)
	if code < 0:
		return code
	var pattern: int = last_evaluated_pattern
	var player = players[player_index]

	# -------- 从手牌移除，更新桌面 --------
	player.remove_cards(cards)
	table_cards = cards.duplicate()
	# 引擎自己解出的价态优先（过氧根 / 非金属作正价这些默认配平覆盖不到的解）
	table_custom_valences = (last_understood_valences.duplicate()
		if not last_understood_valences.is_empty() else custom_valences.duplicate())
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
		# 必须用引擎最终认定的价态（table_custom_valences = 出牌时补出的搜索解），
		# 而不是玩家 / AI 传进来的 custom_valences：过氧根、准金属这类默认配平
		# 覆盖不到的解只存在于前者里，用后者重算会打印出另一个化学式（H₂O₂ → 2HO₂）。
		var fi = CompoundSolverScript.get_compound_formula(cards, table_custom_valences)
		if not fi.is_empty():
			var formula = fi.get("formula", "??")
			log_msg += " " + formula
			# 附加 IUPAC 中文命名
			var comp_name = CompoundSolverScript.get_compound_name(cards, table_custom_valences)
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
		sequence_constraint = -1
		sequence_constraint_target = -1
		return 0

	# -------- 族炸：启动接炸链 + 牌权移交 --------
	if pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
		player.clan_bomb_cooling = true
		clan_bomb_chain_active = true
		clan_bomb_owner = player_index
		# 族炸不解除顺序约束（约束只由被指定的玩家自己出牌 / 跳过才结束）——
		# 但若「被指定的玩家」自己打出族炸，且约束正是「族炸」，则约束完成。
		if sequence_constraint_active and sequence_constraint_target == player_index \
				and sequence_constraint == CardPatternsScript.CardPattern.CLAN_BOMB:
			sequence_constraint_active = false
			sequence_constraint = -1
			sequence_constraint_target = -1
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
		# 新的顺序牌覆盖旧约束（旧约束作废，等 UI 重新指定）
		sequence_constraint_active = false
		sequence_constraint = -1
		sequence_constraint_target = -1
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
		# B′：溢出按「一个分子的原子数」判，不按「出了几张牌」判。
		# 2Na+2Br 是 4 张牌但每分子只有 2 个原子，不该免疫族炸；
		# P₂O₅（7 个原子）、Fe₃O₄（7 个原子）这类大分子才免疫。
		var atom_count: int = CompoundSolverScript.get_formula_atom_count(cards)
		if atom_count >= players.size():
			compound_immune = true
			log_messages.append("⚠ 溢出化合物！单分子 %d 个原子≥%d人，免疫族炸" % [atom_count, players.size()])

	# -------- 非族炸/非顺序出牌完成：重置状态 --------
	clan_bomb_chain_active = false
	clan_bomb_owner = -1
	# 顺序约束只由「被指定的玩家」打出合规牌型来完成；别人出牌不影响它
	if sequence_constraint_active and sequence_constraint_target == player_index:
		sequence_constraint_active = false
		sequence_constraint = -1
		sequence_constraint_target = -1
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


# ---- 比大小失败的具体原因（-2 的细分文案）----
# 统一文案「牌不够大」会让玩家无法判断该换组合还是该换牌型：
#   牌型被压制 / 族炸张数不够 / 原子序数和不够 / 和相同但质量更大 / 与桌面打平
#   平手判定是两级的（CardPatterns._compare_by_total_atomic）：
#     ① 原子序数和：小的赢；② 和相同时比相对原子质量和：轻的赢。
#   P15-E 修：②这一档以前也报「原子序数和 20 大于桌面 20」，自相矛盾
#   —— 玩家看到 20 大于 20 完全不知道该改什么。
func _compare_fail_reason(cards: Array, pattern: int, table: Array, table_pat: int, cmp: int) -> String:
	var mine := _atomic_sum(cards)
	var theirs := _atomic_sum(table)
	var my_mass := _mass_sum(cards)
	var their_mass := _mass_sum(table)
	if cmp == 0:
		return "与桌面打平（原子序数和同为 %d、相对原子质量和同为 %.2f）；同类牌必须比桌面更小" % [
			mine, my_mass]
	if pattern == table_pat:
		if pattern == CardPatternsScript.CardPattern.CLAN_BOMB and cards.size() != table.size():
			return "族炸张数不够（%d 张 vs 桌面 %d 张）" % [cards.size(), table.size()]
		if mine == theirs:
			# 原子序数和打平 → 判定其实落在相对原子质量上（越轻牌越大），
			# 这时再说「原子序数过大」就是错的提示。
			return "原子序数和同为 %d，再比相对原子质量：%.2f 大于桌面 %.2f（越轻牌越大）" % [
				mine, my_mass, their_mass]
		return "原子序数和 %d 大于桌面 %d（数值越小牌越大）" % [mine, theirs]
	return "%s 压不过桌面的 %s（%d vs %d）" % [
		CardPatternsScript.get_pattern_name(pattern).trim_suffix("！"),
		CardPatternsScript.get_pattern_name(table_pat).trim_suffix("！"),
		mine, theirs,
	]


func _atomic_sum(cards: Array) -> int:
	var total := 0
	for c in cards:
		total += int(c.atomic_number)
	return total


# 相对原子质量和：原子序数和打平时用它分胜负（越轻牌越大），
# 也用于把「为什么这手牌不够大」讲清楚。
func _mass_sum(cards: Array) -> float:
	var total := 0.0
	for c in cards:
		total += float(c.atomic_weight)
	return total


func get_last_reject_reason() -> String:
	return last_reject_reason


# ============================================================
# 八之二、顺序指定牌型
# ============================================================
# 由UI层调用，设置顺序打出后指定的牌型约束
func set_sequence_constraint(constraint_pattern: int) -> void:
	sequence_constraint = constraint_pattern
	sequence_constraint_active = true
	# 顺序牌在 play_cards 里已经把方向反转了，所以「下一名玩家」= 反转方向上的下一名，
	# 也就是出顺序牌那名玩家的原上家（4 人局：P0 出顺序 → 约束 P3）。
	# 直接跳过手牌已空的玩家，保证约束落在真正会行动的人身上。
	var from_idx = table_player_index if table_player_index >= 0 else current_player_index
	var target_idx = from_idx
	for _i in range(players.size()):
		target_idx = _get_next_index_in_direction(target_idx)
		if target_idx != from_idx and players[target_idx].get_hand_count() > 0:
			break
	sequence_constraint_target = target_idx
	var pname = CardPatternsScript.get_pattern_name(constraint_pattern)
	var target_name = players[target_idx].player_name \
			if target_idx >= 0 and target_idx < players.size() else "下一名玩家"
	log_messages.append("指定 %s 必须打出：%s，否则罚抽2张" % [target_name, pname])
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
	sequence_constraint_target = -1
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

	# 顺序约束激活：被指定的玩家跳过 → 罚抽2张并结束约束（下下名自由出牌）
	if sequence_constraint_active and sequence_constraint_target == player_index:
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

	# 普通玩家跳过不解除别人的顺序约束（约束只由被指定者自己结算）
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
	# 手牌达上限又背着顺序约束：弃 1 张（上面已弃）+ 罚抽 2 张，约束随即结束
	if sequence_constraint_active and sequence_constraint_target == player_index:
		player_fail_sequence_constraint(player_index)
		return
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
			turn_count += 1
			current_player_index = next_idx
			return

	_start_new_round()


# -------- 族炸接炸链轮询 --------
func _intercept_next() -> void:
	var next_idx = clan_bomb_owner
	for _i in range(players.size()):
		next_idx = (next_idx + 1) % players.size()
		if next_idx != clan_bomb_owner and players[next_idx].get_hand_count() > 0 and not players[next_idx].has_passed:
			turn_count += 1
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
	sequence_constraint_target = -1

	turn_count += 1
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
	turn_count = 0
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
	sequence_constraint_target = -1
	halogen_exchange_allowed = false   # 教程局同样默认禁止卤族互化
	element_limit_enabled = false      # 教程局永远 29 种元素全量（预设手牌含 Fe 等副族）
	allowed_extra_elements.clear()
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
func set_tutorial_level0_phase(new_phase: int) -> void:
	tutorial_level0_phase = new_phase
	if tutorial_controller != null:
		tutorial_controller.tutorial_level0_phase = new_phase
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
		var bomb_tag = " [❄冷却]" if p.clan_bomb_cooling else ""
		info += "%s %s: %d 张牌%s%s%s\n" % [ai_tag, p.player_name, p.get_hand_count(), pass_tag, bomb_tag, marker]
	if table_player_index >= 0:
		var tp = players[table_player_index]
		# 用桌面记录的牌型，而不是按牌面重新检测：同一批牌可能既是族炸又能配成化合物，
		# 重新检测会显示出与实际打出的牌型不一致的名字（会误导玩家对输赢的判断）。
		var pat = table_pattern
		if pat < 0:
			pat = CardPatternsScript.detect_pattern(table_cards)
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
	# 顺序约束优先于接炸链：受约束的玩家要看到「必须打出什么」，
	# 而不是被接炸链的文案误导（play_cards 里也是先查约束、再查接炸链）。
	if sequence_constraint_active and sequence_constraint_target == player_idx:
		var cn = CardPatternsScript.get_pattern_name(sequence_constraint)
		return "顺序约束：必须打出 %s / 跳过(罚抽2张)" % cn
	if clan_bomb_chain_active:
		if player_idx == clan_bomb_owner:
			return "等待他人接炸..."
		if p.clan_bomb_cooling:
			return "❄ 族炸冷却中，不能接炸 / 跳过(抽1张)"
		return "仅可出: 更大的族炸 / 跳过(抽1张)"
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
		elif p.clan_bomb_cooling:
			s += " (族炸❄冷却中)"
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

func get_halogen_exchange_allowed() -> bool:
	return halogen_exchange_allowed

# -------- 元素限制（补充规则）--------
func get_element_limit_enabled() -> bool:
	return element_limit_enabled

func get_allowed_extra_elements() -> Array:
	return allowed_extra_elements.duplicate()

# 一张牌是否允许出现在本局：关闭限制 → 全放行；开启 → 前 20 号 + 勾选的扩展元素
func is_element_allowed(sym: String) -> bool:
	if not element_limit_enabled:
		return true
	var num := CardDatabaseScript.get_atomic_number(sym)
	if num > 0 and num <= CardDatabaseScript.BASE_ELEMENT_MAX_NUMBER:
		return true
	return sym in allowed_extra_elements

# 本局牌库的元素符号集合（空数组 = 29 种全量）
func get_allowed_symbols() -> Array:
	return CardDatabaseScript.get_allowed_symbols(element_limit_enabled, allowed_extra_elements)

# 本局牌库包含多少种元素
func get_allowed_element_count() -> int:
	var syms := get_allowed_symbols()
	if syms.is_empty():
		return CardDatabaseScript.get_element_data().size()
	return syms.size()

# 本局牌库总张数（关闭限制 = 182）
func get_deck_size() -> int:
	return CardDatabaseScript.get_deck_size(get_allowed_symbols())

# 牌组是否含 ≥2 种卤素（F/Cl/Br/I）——「卤族互化」的唯一判据。
# HintAdvisor / AIPlayer / GameUI 全部复用本函数，避免多处拷贝判据走样。
func is_halogen_mix(cards: Array) -> bool:
	var seen: Array = []
	for c in cards:
		if c.symbol in CardDatabaseScript.HALOGEN_SYMBOLS and c.symbol not in seen:
			seen.append(c.symbol)
			if seen.size() >= 2:
				return true
	return false

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


# ============================================================
# 十二、联机地基 API（P11-B）
# 只读快照 / 事件寻址 / 一致性校验。单机流程一次都不调用这些函数，
# 规则逻辑与历史版本完全一致。设计说明见 MULTIPLAYER_ARCHITECTURE.md
# ============================================================

# 座位号是否合法（0 .. 人数-1）
func is_valid_seat(idx: int) -> bool:
	return idx >= 0 and idx < players.size()


# 某座位的手牌 uid 列表（协议层 / 快照用）
func get_hand_uids(player_index: int) -> Array:
	if not is_valid_seat(player_index):
		return []
	return _uids_of(players[player_index].hand)


# 全量快照：握手 / 重连 / 失配修复。
# 只用可 JSON 化的基础类型；手牌以 uid 表示，不复制卡牌对象。
func to_snapshot() -> Dictionary:
	var seats: Array = []
	for p in players:
		seats.append({
			"name": p.player_name,
			"is_ai": p.is_ai,
			"hand_uids": _uids_of(p.hand),
			"hand_count": p.get_hand_count(),
			"has_passed": p.has_passed,
			"clan_bomb_cooling": p.clan_bomb_cooling,
			"hand_manual_order": p.hand_manual_order,
		})
	return {
		"deck_seed": deck_seed,
		"current_player_index": current_player_index,
		"turn_count": turn_count,
		"phase": phase,
		"winner_index": winner_index,
		"is_round_starter": is_round_starter,
		"direction_clockwise": direction_clockwise,
		"compound_immune": compound_immune,
		"clan_bomb_chain_active": clan_bomb_chain_active,
		"clan_bomb_owner": clan_bomb_owner,
		"clan_bomb_disabled": clan_bomb_disabled,
		"sequence_constraint": sequence_constraint,
		"sequence_constraint_active": sequence_constraint_active,
		"sequence_constraint_target": sequence_constraint_target,
		"table": {
			"uids": _uids_of(table_cards),
			"pattern": table_pattern,
			"player_index": table_player_index,
			"custom_valences": _string_keys(table_custom_valences),
		},
		"deck_remaining": database.get_remaining_count() if database != null else 0,
		"players": seats,
		"log_count": log_messages.size(),
	}


func _uids_of(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(int(c.uid))
	return out


func _string_keys(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src:
		out[String(k)] = src[k]
	return out


# ---- 一致性指纹（FNV-1a 32 位，自实现以保证跨平台 / 跨版本一致）----
# 不用 Godot 内建 hash()：其算法与 int 宽度不保证跨平台相同。
func state_hash() -> int:
	return _fnv1a(FNV_OFFSET_BASIS, _canonical_string())


func _fnv1a(h: int, text: String) -> int:
	var bytes := text.to_utf8_buffer()
	for b in bytes:
		h = (h ^ b) & 0xFFFFFFFF
		h = (h * FNV_PRIME) & 0xFFFFFFFF
	return h


# 规范化状态串：手牌按 uid 升序（手牌顺序是 UI 偏好，不影响规则），
# 化合价字典按键排序 —— 保证「同一个局面」在任何端得到同一个指纹。
func _canonical_string() -> String:
	var parts: Array = []
	parts.append("seed=%d" % deck_seed)
	parts.append("cur=%d" % current_player_index)
	parts.append("turn=%d" % turn_count)
	parts.append("phase=%d" % phase)
	parts.append("win=%d" % winner_index)
	parts.append("starter=%s" % str(is_round_starter))
	parts.append("dir=%s" % str(direction_clockwise))
	parts.append("immune=%s" % str(compound_immune))
	parts.append("chain=%s:%d" % [str(clan_bomb_chain_active), clan_bomb_owner])
	parts.append("no_bomb=%s" % str(clan_bomb_disabled))
	parts.append("cons=%d:%s:%d" % [sequence_constraint, str(sequence_constraint_active), sequence_constraint_target])
	parts.append("table=%s/%d/%d/%s" % [
		str(_uids_of(table_cards)),
		table_pattern,
		table_player_index,
		str(_sorted_pairs(table_custom_valences)),
	])
	parts.append("deck=%d" % (database.get_remaining_count() if database != null else -1))
	for p in players:
		var uids := _uids_of(p.hand)
		uids.sort()
		parts.append("seat=%s/%s/%s/%s/%s" % [
			p.player_name,
			str(uids),
			str(p.has_passed),
			str(p.clan_bomb_cooling),
			str(p.is_ai),
		])
	parts.append("logs=%d" % log_messages.size())
	return "\n".join(parts)


func _sorted_pairs(src: Dictionary) -> Array:
	var keys: Array = src.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append("%s=%s" % [String(k), _valence_key_of(src[k])])
	return out


# 指纹里化合价的文本形式：数组（混合价）先降序规范化再拼，
# 避免「[3,2] 与 [2,3]」这种表示差异导致 state_hash 失配；
# 单个数字保持 v3 的写法（老存档 / 老事件重放的指纹不变）。
func _valence_key_of(v) -> String:
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(int(x))
		arr.sort()
		arr.reverse()
		return str(arr)
	if v is bool:
		return str(v)
	return str(int(v))


# ---- 事件应用（客人重放 / 主机本地执行 / 自动化测试）----
# 事件格式（全部可 JSON 化）：
#   {"type":"play",          "by":0, "uids":[12,44], "valences":{"H":1}, "pattern":-1}
#   {"type":"pass",          "by":0}
#   {"type":"discard_pass",  "by":0, "uid":12}
#   {"type":"sequence_pick", "by":0, "pattern":2}
#   {"type":"sequence_skip", "by":0}
# 返回：play 透传 play_cards 的返回码（0 / 1 / -1..-8）；其它成功返回 0；
#       EVENT_UNKNOWN = 未知类型；EVENT_BAD_PAYLOAD = 座位 / uid 非法。
# 只有「成功推进局面」的事件才写入 event_log —— 失败事件不污染回放。
func apply_event(ev: Dictionary) -> int:
	var event_type := String(ev.get("type", ""))
	var by := int(ev.get("by", -1))
	var result := EVENT_UNKNOWN
	match event_type:
		"play":
			var cards = _cards_by_uids(by, ev.get("uids", []))
			if cards == null:
				return EVENT_BAD_PAYLOAD
			result = play_cards(by, cards, _valences_from(ev.get("valences", {})), int(ev.get("pattern", -1)))
		"pass":
			if not is_valid_seat(by):
				return EVENT_BAD_PAYLOAD
			player_pass(by)
			result = 0
		"discard_pass":
			if not is_valid_seat(by):
				return EVENT_BAD_PAYLOAD
			var card = _card_by_uid(by, int(ev.get("uid", -1)))
			if card == null:
				return EVENT_BAD_PAYLOAD
			player_discard_and_pass(by, card)
			result = 0
		"sequence_pick":
			if not is_valid_seat(by):
				return EVENT_BAD_PAYLOAD
			set_sequence_constraint(int(ev.get("pattern", -1)))
			result = 0
		"sequence_skip":
			if not is_valid_seat(by):
				return EVENT_BAD_PAYLOAD
			# 与 UI「跳过指定」按钮完全等价（清约束 + 轮转）
			sequence_constraint_active = false
			sequence_constraint = -1
			sequence_constraint_target = -1
			next_turn()
			result = 0
		_:
			return EVENT_UNKNOWN
	if result >= 0:
		event_log.append(ev.duplicate(true))
	return result


# ---- 事件序列重放（联机：中途加入 / 断线重连 / 失配修复 / 回放）----
# 调用约定：
#   1) 调用方必须已用**同一 seed + 同一配置**调过 init_game（牌序才能对上）；
#   2) events 是主机下发的 event_log（apply_event 已过滤掉失败事件）；
#   3) 返回「成功应用的条数」；<0 = 在某一处分叉（说明两端牌序或版本不一致）。
# 重放会重建 log_messages（apply_event 内部照常写日志），因此重放后
# state_hash() 里的 logs 计数也能与主机对齐 —— 这正是快照恢复做不到的。
func replay_events(events: Array) -> int:
	event_log.clear()
	var applied := 0
	for ev in events:
		if not (ev is Dictionary):
			return EVENT_BAD_PAYLOAD
		var code := apply_event(ev)
		if code < 0:
			return code
		applied += 1
	return applied


func _card_by_uid(player_index: int, uid: int):
	for c in players[player_index].hand:
		if int(c.uid) == uid:
			return c
	return null


# uid 列表 → 手牌卡对象；任一 uid 不存在 / 重复 / 越界 → null（整笔事件作废）
# 注意：返回类型不标注 Array —— 失败时返回 null，需要 Variant 承载
func _cards_by_uids(player_index: int, uids):
	if not is_valid_seat(player_index) or not (uids is Array) or uids.is_empty():
		return null
	var out: Array = []
	var seen: Dictionary = {}
	for raw in uids:
		var uid := int(raw)
		if seen.has(uid):
			return null
		seen[uid] = true
		var card = _card_by_uid(player_index, uid)
		if card == null:
			return null
		out.append(card)
	return out


# 化合价字典规范化：键转 String，值保持 bool（"_organic" 标记）/ 转 int（JSON 数字是 float）
# 混合价态（v4）的值是数组：[+3, +3, +2] = 该元素每张牌各取一个价。
# JSON 往返后数组里是 float，这里统一转 int 并降序规范化 —— 主机与客人
# 各自解析同一笔事件后必须得到同一个表示，否则 state_hash 会莫名其妙地对不上。
func _valences_from(src) -> Dictionary:
	var out: Dictionary = {}
	if not (src is Dictionary):
		return out
	for k in src:
		var v = src[k]
		if v is bool:
			out[String(k)] = v
		elif v is Array:
			var arr: Array = []
			for x in v:
				arr.append(int(x))
			arr.sort()
			arr.reverse()
			out[String(k)] = arr
		else:
			out[String(k)] = int(v)
	return out