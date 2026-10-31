# ============================================================
# PlayerManager.gd - 人数规划模块
# 职责：玩家数量规划 / 玩家信息 / 发牌 / 手牌上限
# 从 GameManager 拆出的独立模块（行为与原先完全一致）
# ============================================================
extends RefCounted

const MIN_PLAYERS = 3
const MAX_PLAYERS = 8
const INITIAL_HAND_SIZE = 8

# ============================================================
# 一、PlayerInfo 玩家信息类（独立，可复用）
# ============================================================
class PlayerInfo:
	var player_name: String = ""
	var hand: Array = []                 # 手牌，数组顺序 = 界面显示顺序（唯一真源）
	var is_ai: bool = false
	var has_passed: bool = false         # 本轮是否跳过
	var clan_bomb_cooling: bool = false  # 是否被族炸冷却
	# 手动排列模式：玩家拖动过手牌后置 true，此后自动排序全部失效，
	# 直到「按序」按钮（force=true）或新一局（init_game 重建 PlayerInfo）把它清掉。
	var hand_manual_order: bool = false

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

	# 手牌按原子序数升序排列。
	# force=false（默认）：玩家处于手动排列模式时直接返回 —— 抽牌 / 出牌 / 换人
	#   引发的刷新都不会打回按序，玩家排好的顺序得以保留。
	# force=true：只有「按序」按钮这类显式操作才用，排完即退出手动模式。
	func sort_hand_by_atomic_number(force: bool = false) -> void:
		if hand_manual_order and not force:
			return
		hand.sort_custom(func(a, b): return a.atomic_number < b.atomic_number)
		hand_manual_order = false

	# 拖拽重排：把 from_idx 的牌移到 to_idx（to_idx 是落定后的目标下标，非插入槽）。
	# 移动成功后进入手动排列模式；index 越界 / 原地不动一律返回 false，不动手牌
	# （返回 false 时调用方可以据此跳过整排重绘）。
	func move_card(from_idx: int, to_idx: int) -> bool:
		var n: int = hand.size()
		if from_idx < 0 or from_idx >= n:
			return false
		to_idx = clampi(to_idx, 0, n - 1)
		if to_idx == from_idx:
			return false
		var card = hand[from_idx]
		hand.remove_at(from_idx)
		hand.insert(to_idx, card)
		hand_manual_order = true
		return true

	func get_hand_display() -> String:
		if hand.is_empty():
			return "[空]"
		var names: Array = []
		for card in hand:
			names.append(card.symbol)
		return ", ".join(names)


# ============================================================
# 二、玩家创建与人数校验
# ============================================================
# 创建玩家列表（0号是玩家本人，其余为 AI）
static func create_players(player_count: int, ai_count: int) -> Array:
	var players: Array = []
	for i in range(player_count):
		var is_ai = i >= player_count - ai_count
		var p_name = "玩家" if i == 0 else ("AI-%d" % i)
		players.append(PlayerInfo.new(p_name, is_ai))
	return players


# 校验人数配置是否合法
static func validate_player_count(player_count: int, ai_count: int) -> bool:
	if player_count < MIN_PLAYERS or player_count > MAX_PLAYERS:
		return false
	if ai_count >= player_count:
		return false
	return true


# ============================================================
# 三、发牌
# ============================================================
# 给所有玩家发初始手牌（每人 INITIAL_HAND_SIZE 张）
static func deal_initial_hands(players: Array, database) -> void:
	for p in players:
		for _i in range(INITIAL_HAND_SIZE):
			p.add_card(database.draw_card())


# ============================================================
# 四、手牌上限
# ============================================================
static func get_hand_limit(player_count: int) -> int:
	return mini(player_count * 4, 18)
