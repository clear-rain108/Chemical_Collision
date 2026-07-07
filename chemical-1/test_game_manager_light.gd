extends Node

const CardDatabase = preload("res://card_database.gd")

var deck: Array = []
var player_hand: Array = []
var ai_hand: Array = []


func _ready() -> void:
	start_game()


func start_game() -> void:
	deck = CardDatabase.generate_deck()
	deck.shuffle()

	player_hand = draw_cards(8)
	ai_hand = draw_cards(8)

	print("========================================")
	print("GameManager 轻量测试")
	print("========================================")
	print("牌库剩余: ", deck.size(), " 张 (期望: 92)")
	print("----------------------------------------")
	print("玩家手牌 (", player_hand.size(), "张):")
	for card in player_hand:
		print("  ", card)
	print("玩家符号列表: ", format_hand(player_hand))
	print("----------------------------------------")
	print("AI手牌 (", ai_hand.size(), "张):")
	for card in ai_hand:
		print("  ", card)
	print("AI符号列表: ", format_hand(ai_hand))
	print("========================================")

	if deck.size() == 92 and player_hand.size() == 8 and ai_hand.size() == 8:
		print("✅ 发牌测试通过！")
	else:
		print("❌ 发牌测试失败！")


func draw_cards(count: int) -> Array:
	var drawn: Array = []
	for _i in range(count):
		if deck.is_empty():
			break
		drawn.append(deck.pop_back())
	return drawn


func format_hand(hand: Array) -> String:
	var symbols: Array[String] = []
	for card in hand:
		symbols.append(card.symbol)
	return ", ".join(symbols)