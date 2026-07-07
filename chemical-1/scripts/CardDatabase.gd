extends Node

const CardData = preload("res://scripts/CardData.gd")

static func generate_deck() -> Array:
    var deck = []
    # 原始数据：名称, 符号, 序数, 族, 化合价列表, 相对质量
    var raw = [
        ["氢", "H", 1, "IA", [1, -1], 1.0],
        ["氦", "He", 2, "0族", [0], 4.0],
        ["锂", "Li", 3, "IA", [1], 7.0],
        ["铍", "Be", 4, "IIA", [2], 9.0],
        ["硼", "B", 5, "IIIA", [3], 11.0],
        ["碳", "C", 6, "IVA", [4, -4], 12.0],
        ["氮", "N", 7, "VA", [5, -3], 14.0],
        ["氧", "O", 8, "VIA", [-2, -1], 16.0],
        ["氟", "F", 9, "VIIA", [-1], 19.0],
        ["氖", "Ne", 10, "0族", [0], 20.0],
        ["钠", "Na", 11, "IA", [1], 23.0],
        ["镁", "Mg", 12, "IIA", [2], 24.0],
        ["铝", "Al", 13, "IIIA", [3], 27.0],
        ["硅", "Si", 14, "IVA", [4, -4], 28.0],
        ["磷", "P", 15, "VA", [5, -3], 31.0],
        ["硫", "S", 16, "VIA", [6, -2], 32.0],
        ["氯", "Cl", 17, "VIIA", [7, -1], 35.0],
        ["氩", "Ar", 18, "0族", [0], 40.0]
    ]
    
    for item in raw:
        var card = CardData.new(item[0], item[1], item[2], item[3], item[4], item[5])
        for i in range(6):
            deck.append(card)
    return deck