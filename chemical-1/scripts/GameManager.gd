extends Node

const CardDatabase = preload("res://scripts/CardDatabase.gd")
const Utils = preload("res://scripts/Utils.gd")

var player_hand = []
var ai_hand = []
var deck = []

func _ready():
    print("========== 游戏启动测试 ==========")
    deck = CardDatabase.generate_deck()
    deck.shuffle()
    print("牌库生成成功！总张数：", deck.size())
    
    player_hand = draw_cards(2)
    ai_hand = draw_cards(2)
    print("玩家手牌：", format_hand(player_hand))
    print("AI手牌：", format_hand(ai_hand))
    print("牌库剩余：", deck.size())
    
    var test_combo = []
    if player_hand.size() >= 2:
        test_combo = [player_hand[0], player_hand[1]]
        if Utils.can_form_compound(test_combo):
            print("测试：这两张牌可以组成化合物！")
        else:
            print("测试：这两张牌不能组成化合物。")
    
    print("========== 编译成功！环境正常！ ==========")

func draw_cards(count: int) -> Array:
    var hand = []
    for i in range(count):
        if deck.is_empty():
            break
        hand.append(deck.pop_back())
    return hand

func format_hand(hand: Array) -> String:
    var names = []
    for card in hand:
        names.append(card.symbol)
    return ", ".join(names)