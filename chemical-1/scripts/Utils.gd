extends Node

static func can_form_compound(cards: Array) -> bool:
    if cards.size() < 2:
        return false
    
    var total_pos = 0
    var total_neg = 0
    
    for card in cards:
        var max_pos = 0
        var max_neg = 0
        for v in card.valences:
            if v > 0:
                max_pos = max(max_pos, v)
            elif v < 0:
                max_neg = max(max_neg, abs(v))
        total_pos += max_pos
        total_neg += max_neg
    
    return total_pos > 0 and total_neg > 0 and total_pos == total_neg