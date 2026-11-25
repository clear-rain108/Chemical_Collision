# ============================================================
# GameModes.gd - 对局模式表（纯数据 + 静态查询，不依赖任何其他脚本）
#
# 一个「模式」= 一组规则开关。引擎只问开关，不认识模式名：
#   GameManager._evaluate_play()  冷却判定 → cooling_enabled(game_mode)
#   GameManager._evaluate_play()  免疫判定 → immunity_enabled(game_mode)
#   GameManager.play_cards()      冷却置位 → cooling_enabled(game_mode)
#   GameManager.play_cards()      免疫置位 → immunity_enabled(game_mode)
#
# 为什么不用 `if game_mode == 1` 散落在引擎里：加第二种模式时要在每个判定点加
# 分支，还要反复确认「标准局行为逐字不变」。表驱动下新模式只写「与默认不同的
# 那几条」，漏写 = 走默认 = 与标准局一致，天然安全（tests/verify_game_mode M0
# 还会断言默认表本身就是标准局）。
#
# 加新模式三步：
#   1) Id 里加一项
#   2) MODE_OVERRIDES / MODE_META 各加一条
#   3) 开始页候选卡自动出现（scripts/pages/ModePage.gd 按 ORDER 生成）
# 引擎零改动。
#
# 落点：
#   · GameManager.game_mode（局配置，必须在 init_game() **之前**写入；init 不重置）
#   · NetSession._make_config() / _apply_config()（联机由房主定，game_start 下发）
#   · GameManager._canonical_string() 的 mode=%d（模式直接决定合法性，必须进指纹）
# ============================================================

extends RefCounted

enum Id { STANDARD = 0, SKELETON = 1 }

# ---- 规则开关键（模式表只认这些键；缺键 = 用 DEFAULT_RULES）----
const R_CLAN_BOMB_COOLING := "clan_bomb_cooling"   # 族炸后进入 ❄ 冷却（只能打化合物解除）
const R_BOMB_IMMUNITY := "bomb_immunity"           # 溢出化合物（单分子原子数 ≥ 人数）免疫族炸

# 标准局 = 两条全开。这是所有模式的基线：改这里等于改标准局（verify_game_mode M0 会拦）。
const DEFAULT_RULES := {
	R_CLAN_BOMB_COOLING: true,
	R_BOMB_IMMUNITY: true,
}

# 各模式「与默认不同」的条目。空表 = 完全标准局。
const MODE_OVERRIDES := {
	Id.STANDARD: {},
	# 骷髅炸金服：族炸没有冷却限制，只剩「抢牌权」作用（开接炸链 → 链终由 owner
	# 自由出牌）；溢出化合物也不再免疫族炸（大分子糊在桌上反而危险）。
	Id.SKELETON: {
		R_CLAN_BOMB_COOLING: false,
		R_BOMB_IMMUNITY: false,
	},
}

# UI 展示信息。desc 里的化学式一律 ASCII（项目字体缺下标字形）。
const MODE_META := {
	Id.STANDARD: {
		"name": "标准对局",
		"desc": "族炸后冷却，需打出一张化合物解除；溢出化合物免疫族炸",
		"tag": "",
	},
	Id.SKELETON: {
		"name": "骷髅炸金服",
		"desc": "族炸无冷却，只剩抢牌权；溢出化合物不再免疫族炸",
		"tag": "特殊模式",
	},
}

# 候选顺序（ModePage 按这个顺序出卡片，不依赖 Dictionary 遍历顺序）
const ORDER := [Id.STANDARD, Id.SKELETON]


static func ids() -> Array:
	return ORDER.duplicate()


static func is_valid(id: int) -> bool:
	return MODE_META.has(id)


static func name_of(id: int) -> String:
	var meta: Dictionary = MODE_META.get(id, MODE_META[Id.STANDARD])
	return str(meta.get("name", ""))


static func desc_of(id: int) -> String:
	var meta: Dictionary = MODE_META.get(id, MODE_META[Id.STANDARD])
	return str(meta.get("desc", ""))


# 非标准模式才有 tag（状态栏 / 结束页用它提醒「本局不是标准规则」）
static func tag_of(id: int) -> String:
	var meta: Dictionary = MODE_META.get(id, MODE_META[Id.STANDARD])
	return str(meta.get("tag", ""))


# 是否完全标准局（没有覆盖条目）—— UI 用它决定要不要显示模式标记
static func is_standard(id: int) -> bool:
	if not MODE_OVERRIDES.has(id):
		return true
	var ov = MODE_OVERRIDES[id]
	return ov is Dictionary and ov.is_empty()


# 单一真相：查规则开关。未知 id → 退回标准局（宁保守，不放水）
static func rule(id: int, key: String) -> bool:
	var base: bool = bool(DEFAULT_RULES.get(key, true))
	if not MODE_OVERRIDES.has(id):
		return base
	var ov = MODE_OVERRIDES[id]
	if ov is Dictionary and ov.has(key):
		return bool(ov[key])
	return base


static func cooling_enabled(id: int) -> bool:
	return rule(id, R_CLAN_BOMB_COOLING)


static func immunity_enabled(id: int) -> bool:
	return rule(id, R_BOMB_IMMUNITY)


# 开局日志 / 状态栏的一行摘要。标准局返回 ""（不刷屏）
static func summary_of(id: int) -> String:
	var parts: Array = []
	if not cooling_enabled(id):
		parts.append("族炸无冷却")
	if not immunity_enabled(id):
		parts.append("溢出化合物不免疫族炸")
	if parts.is_empty():
		return ""
	return "%s：%s" % [name_of(id), " · ".join(parts)]
