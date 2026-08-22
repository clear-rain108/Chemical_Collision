# ============================================================
# TutorialUI.gd - 教程内容与引导模块
# 职责：教程关卡引导文本 / 成功提示 / 教程显示文本
# 从 GameManager 拆出的独立模块（行为与原先完全一致）
# ============================================================
extends RefCounted

const CardPatternsScript = preload("res://scripts/CardPatterns.gd")


# 获取教程引导文本（根据关卡与步骤）
static func get_guidance_text(tutorial_level: int, tutorial_step: int) -> String:
	if tutorial_level == 1:
		match tutorial_step:
			1: return "【第1步】观察手牌：每张牌显示元素符号+中文名。鼠标悬停可查看原子序数、族、化合价、相对质量。\n点击选中一张牌，再点「出牌(选牌型)」→「作为单质打出」试试！"
			2: return "【第2步】很好！现在试试合成化合物：选中两种不同元素(如Na和Cl)，点「合成化合物」→为每种选化合价→确认打出。\n金属优先正价，非金属优先负价。"
			3: return "【第3步】继续练习！尝试不同的单质和化合物组合。\n记住：原子序数和越小，牌力越大。桌面牌必须被你出的牌压过。"
			_: return "【练习中】继续出牌直到打光手牌！随时可跳过抽牌。"
	elif tutorial_level == 2:
		match tutorial_step:
			1: return "【第1步】熟悉族炸：选中同族≥2张不同元素(如H+Li都是IA族)，点「作为族炸打出」。\n族炸可以抢牌权，比普通牌更强！"
			2: return "【第2步】族炸打出后进入冷却❄，必须出一个化合物来解除冷却。\n选中两种元素合成化合物，像Na+Cl=NaCl。"
			3: return "【第3步】试试接炸！当AI打出族炸后，你如果也有同族牌可出更大族炸接炸。\n也可以跳过让AI接炸。"
			4: return "【第4步】注意手牌上限！手牌达到上限时不能跳过，需选择1张弃置。\n继续练习直到打完所有手牌！"
			_: return "【练习中】继续游戏！利用族炸+化合物完成对局。"
	return ""


# 获取第0关引导文本（根据阶段）
static func get_level0_guidance_text(tutorial_level: int, tutorial_level0_phase: int) -> String:
	if tutorial_level != 0:
		return ""
	match tutorial_level0_phase:
		1: return ""
		2: return ""
		3: return "【牌局中】尝试出牌！你可以打出单质、化合物或族炸。AI默认只出单质和化合物。"
	return ""


# 检查教程进度并返回 {advanced, success}（不修改任何状态，由调用方处理）
static func check_tutorial_progress(tutorial_level: int, tutorial_step: int, pattern: int) -> Dictionary:
	var result = {"advanced": false, "success": ""}
	if tutorial_level == 0:
		return result
	elif tutorial_level == 1:
		if tutorial_step == 1 and pattern == CardPatternsScript.CardPattern.ELEMENT:
			result.success = "✓ 正确！你打出了一张单质。"
			result.advanced = true
		elif tutorial_step == 2 and pattern == CardPatternsScript.CardPattern.COMPOUND:
			result.success = "✓ 正确！你成功合成了一个化合物。"
			result.advanced = true
		elif tutorial_step == 3 and pattern == CardPatternsScript.CardPattern.COMPOUND:
			result.success = "✓ 很好！继续练习。"
			result.advanced = true
	elif tutorial_level == 2:
		if tutorial_step == 1 and pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
			result.success = "✓ 正确！你打出了族炸，抢到了牌权！注意你进入了冷却❄。"
			result.advanced = true
		elif tutorial_step == 2 and pattern == CardPatternsScript.CardPattern.COMPOUND:
			result.success = "✓ 正确！打出化合物解除了族炸冷却。"
			result.advanced = true
		elif tutorial_step == 3 and pattern == CardPatternsScript.CardPattern.CLAN_BOMB:
			result.success = "✓ 正确！你成功接炸了！"
			result.advanced = true
		elif tutorial_step == 4:
			result.success = "继续练习！"
			result.advanced = true
	return result
