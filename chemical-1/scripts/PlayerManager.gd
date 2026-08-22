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
