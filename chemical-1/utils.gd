extends Object
class_name Utils


static func can_form_compound(cards: Array) -> bool:
	if cards.is_empty():
		return false

	var sum: int = 0
	var has_positive: bool = false
	var has_negative: bool = false

	for card in cards:
		var valences: Array[int] = card.valences
		if valences.is_empty():
			continue

		# 取最大绝对值化合价，若绝对值相同则优先取正价
		var best_valence: int = valences[0]
		var best_abs: int = abs(valences[0])
		for v in valences:
			var a: int = abs(v)
			if a > best_abs or (a == best_abs and v > best_valence):
				best_valence = v
				best_abs = a

		sum += best_valence
		if best_valence > 0:
			has_positive = true
		elif best_valence < 0:
			has_negative = true

	return sum == 0 and has_positive and has_negative