extends Node


const Utils = preload("res://utils.gd")

var deck: Array = []
var player_hand: Array = []
var ai_hand: Array = []
var current_turn: String = ""

# 桌面状态
var table_cards: Array = []
var table_type: String = ""
var table_z_sum: int = 0
var table_mass_sum: float = 0.0


func _ready() -> void:
	start_game()
	game_loop()


func start_game() -> void:
	deck = CardDatabase.generate_deck()
	deck.shuffle()

	player_hand = draw_cards(8)
	ai_hand = draw_cards(8)

	print("牌库剩余: ", deck.size(), " 张")
	print("玩家手牌: ", format_hand(player_hand))
	for card in player_hand:
		print("  ", card)
	print("AI手牌: ", format_hand(ai_hand))
	for card in ai_hand:
		print("  ", card)

	determine_first_turn()


func determine_first_turn() -> void:
	var player_card: CardData = player_hand.pick_random()
	var ai_card: CardData = ai_hand.pick_random()

	print("========================================")
	print("定先手 —— 双方亮牌")
	print("玩家亮出: ", player_card, " (原子序数=%d, 相对原子质量=%.3f)" % [player_card.atomic_number, player_card.atomic_mass])
	print("AI亮出:   ", ai_card, " (原子序数=%d, 相对原子质量=%.3f)" % [ai_card.atomic_number, ai_card.atomic_mass])

	if player_card.atomic_number < ai_card.atomic_number:
		current_turn = "player"
	elif player_card.atomic_number > ai_card.atomic_number:
		current_turn = "ai"
	else:
		# 原子序数相同，比较相对原子质量
		if player_card.atomic_mass < ai_card.atomic_mass:
			current_turn = "player"
		elif player_card.atomic_mass > ai_card.atomic_mass:
			current_turn = "ai"
		else:
			# 极端情况完全相同，随机决定
			current_turn = "player" if randi() % 2 == 0 else "ai"

	if current_turn == "player":
		print("结果: 玩家先出牌")
	else:
		print("结果: AI先出牌")
	print("========================================")


func draw_cards(count: int) -> Array:
	var drawn: Array = []
	for _i in range(count):
		if deck.is_empty():
			break
		drawn.append(deck.pop_back())
	return drawn


func get_z_sum(cards: Array) -> int:
	var total: int = 0
	for card in cards:
		total += card.atomic_number
	return total


func get_mass_sum(cards: Array) -> float:
	var total: float = 0.0
	for card in cards:
		total += card.atomic_mass
	return total


func judge_type(cards: Array) -> String:
	if cards.size() == 1:
		return "单质"

	# 判断是否为族炸：≥2张、同族、不同元素
	var group_name: String = cards[0].group
	var seen_symbols: Array[String] = []
	for card in cards:
		if card.group != group_name:
			return "化合物"
		if card.symbol in seen_symbols:
			return "化合物"
		seen_symbols.append(card.symbol)

	return "族炸"


func can_beat_table(cards: Array) -> bool:
	if table_cards.is_empty():
		return true

	var new_z: int = get_z_sum(cards)
	var new_mass: float = get_mass_sum(cards)

	if new_z > table_z_sum:
		return true
	if new_z == table_z_sum and new_mass > table_mass_sum:
		return true
	return false


func play_cards(who: String, cards: Array) -> void:
	var hand: Array = player_hand if who == "player" else ai_hand
	var who_name: String = "玩家" if who == "player" else "AI"

	# 从手牌中移除
	for card in cards:
		hand.erase(card)

	# 更新桌面
	table_cards = cards.duplicate()
	table_type = judge_type(cards)
	table_z_sum = get_z_sum(cards)
	table_mass_sum = get_mass_sum(cards)

	print("----------------------------------------")
	print(who_name, " 出牌 [", table_type, "]: ", format_hand(cards))
	print("  Z总和=%d, 质量总和=%.3f" % [table_z_sum, table_mass_sum])

	# 族炸：清空桌面 + 抢夺牌权
	if table_type == "族炸":
		print("  >>> 抢夺牌权！桌面清空！")
		table_cards.clear()
		table_type = ""
		table_z_sum = 0
		table_mass_sum = 0.0


func find_bomb(hand: Array) -> Array:
	# 查找手牌中是否有 ≥2张同族且不同元素的牌（族炸）
	# 按族分组
	var groups: Dictionary = {}
	for card in hand:
		var g: String = card.group
		if not groups.has(g):
			groups[g] = []
		# 避免重复元素（同族但同元素只算一张）
		var symbols_in_group: Array[String] = []
		for c in groups[g]:
			symbols_in_group.append(c.symbol)
		if not card.symbol in symbols_in_group:
			groups[g].append(card)

	# 找数量最多的族组
	var best: Array = []
	for g in groups:
		var group_cards: Array = groups[g]
		if group_cards.size() >= 2 and group_cards.size() > best.size():
			best = group_cards
	return best


func find_best_compound(hand: Array) -> Array:
	if hand.size() < 2:
		return []

	var best_combo: Array = []
	var best_sum: int = -1

	# 穷举所有 2~3 张的组合
	var n: int = hand.size()

	# 2张组合
	for i in range(n):
		for j in range(i + 1, n):
			var combo: Array = [hand[i], hand[j]]
			if Utils.can_form_compound(combo):
				var atomic_sum: int = hand[i].atomic_number + hand[j].atomic_number
				if atomic_sum > best_sum:
					best_sum = atomic_sum
					best_combo = combo

	# 3张组合
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var combo: Array = [hand[i], hand[j], hand[k]]
				if Utils.can_form_compound(combo):
					var atomic_sum: int = hand[i].atomic_number + hand[j].atomic_number + hand[k].atomic_number
					if atomic_sum > best_sum:
						best_sum = atomic_sum
						best_combo = combo

	return best_combo


func find_best_single(hand: Array) -> Array:
	if hand.is_empty():
		return []

	var best_card: CardData = hand[0]
	for card in hand:
		if card.atomic_number > best_card.atomic_number:
			best_card = card
	return [best_card]


func switch_turn() -> void:
	current_turn = "ai" if current_turn == "player" else "player"


func player_turn() -> bool:
	# 1. 尝试族炸
	var bomb: Array = find_bomb(player_hand)
	if bomb.size() >= 2 and can_beat_table(bomb):
		play_cards("player", bomb)
		return true  # 族炸不切换回合

	# 2. 尝试化合物
	var compound: Array = find_best_compound(player_hand)
	if compound.size() >= 2 and can_beat_table(compound):
		play_cards("player", compound)
		switch_turn()
		return true

	# 3. 尝试单质
	var single: Array = find_best_single(player_hand)
	if single.size() == 1 and can_beat_table(single):
		play_cards("player", single)
		switch_turn()
		return true

	# 4. 无法出牌，摸牌
	if not deck.is_empty():
		var card: CardData = deck.pop_back()
		player_hand.append(card)
		print("玩家 无法出牌，摸牌: ", card)
	else:
		print("玩家 无法出牌，牌库已空！")
	switch_turn()
	return false


func ai_turn() -> bool:
	# 1. 尝试族炸
	var bomb: Array = find_bomb(ai_hand)
	if bomb.size() >= 2 and can_beat_table(bomb):
		play_cards("ai", bomb)
		return true  # 族炸不切换回合

	# 2. 尝试化合物
	var compound: Array = find_best_compound(ai_hand)
	if compound.size() >= 2 and can_beat_table(compound):
		play_cards("ai", compound)
		switch_turn()
		return true

	# 3. 尝试单质
	var single: Array = find_best_single(ai_hand)
	if single.size() == 1 and can_beat_table(single):
		play_cards("ai", single)
		switch_turn()
		return true

	# 4. 无法出牌，摸牌
	if not deck.is_empty():
		var card: CardData = deck.pop_back()
		ai_hand.append(card)
		print("AI 无法出牌，摸牌: ", card)
	else:
		print("AI 无法出牌，牌库已空！")
	switch_turn()
	return false


func game_loop() -> void:
	var pass_count: int = 0

	print("\n" + "=".repeat(40))
	print("           游戏开始！")
	print("=".repeat(40))

	while true:
		var played: bool = false
		if current_turn == "player":
			print("\n--- 玩家回合 (手牌%d张 | 牌库%d张) ---" % [player_hand.size(), deck.size()])
			played = player_turn()
			print("玩家剩余手牌: ", format_hand(player_hand), " (", player_hand.size(), "张)")
			if player_hand.is_empty():
				print("\n" + "=".repeat(40))
				print("         AI 获胜！玩家手牌已空！")
				print("=".repeat(40))
				break
		else:
			print("\n--- AI回合 (手牌%d张 | 牌库%d张) ---" % [ai_hand.size(), deck.size()])
			played = ai_turn()
			print("AI剩余手牌: ", format_hand(ai_hand), " (", ai_hand.size(), "张)")
			if ai_hand.is_empty():
				print("\n" + "=".repeat(40))
				print("         玩家获胜！AI手牌已空！")
				print("=".repeat(40))
				break

		# 安全机制：牌库空 + 桌面空 + 出牌失败 → 计数
		if deck.is_empty() and table_cards.is_empty() and not played:
			pass_count += 1
		else:
			pass_count = 0

		if pass_count >= 2:
			print("\n" + "=".repeat(40))
			print("         牌库已空且双方无法出牌，平局！")
			print("=".repeat(40))
			break


func format_hand(hand: Array) -> String:
	var symbols: Array[String] = []
	for card in hand:
		symbols.append(card.symbol)
	return ", ".join(symbols)