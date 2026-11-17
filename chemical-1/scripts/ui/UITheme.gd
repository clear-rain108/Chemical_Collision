# ============================================================
# ui/UITheme.gd - 视觉规范工厂（样式 / 配色）
#
# 从 GameUI.gd 搬来（Slice 1）：_make_panel_style / _style_base / _get_card_color
#
# 约定（见 UI_LAYER_REFACTOR.md §4）：
#   · 状态与常量都留在 root：tests/verify_motion.gd 直读 scene.PAGE_BG_COLOR、
#     tests/verify_hand_view.gd 直读 scene.CARD_W，所以常量一个都不搬；
#     本文件通过 _ui 动态读取，**不复制任何数值**（数值只有一处真源）。
#   · _ui 刻意不写类型：常量是「实例上没有的成员」，静态类型基类会编译期报错。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# -------- 视觉规范工厂：卡牌 / 面板 / 按钮 / toast 的唯一样式来源 --------
# kind: card / card_selected / card_hover / card_hover_selected
#       mini_card / mini_card_hover / button / tab_on / tab_off
#       toast_warning / toast_info
#
# 两个入口，`match` 只有一份（数值仍只有一处真源）：
#   · _make_panel_style(kind)      → **全新实例**。要改属性的调用点必须用它
#     （hover / pressed / disabled 只是「同款换色」，改完挂在别的控件上）。
#   · _panel_style_template(kind)  → **共享缓存实例（只读）**。手牌 / 小卡这类
#     高频重绘点用它：同一 kind 全项目只有一份 → 重建一圈手牌不再产生 2n 个
#     StyleBoxFlat（20 张牌 = 40 次分配 → 0 次）。
# 坑：模板一旦被某个调用点改属性，全项目所有同款控件都会跟着变 —— 所以
# 「要改属性」与「只挂上去」两条路必须分开，不能只留一个函数。
var _style_cache: Dictionary = {}


func _make_panel_style(kind: String) -> StyleBoxFlat:
	return _build_style(kind)


func _panel_style_template(kind: String) -> StyleBoxFlat:
	if _style_cache.has(kind):
		return _style_cache[kind]
	var sb := _build_style(kind)
	_style_cache[kind] = sb
	return sb


func _build_style(kind: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match kind:
		"card":
			_style_base(sb, Color(0.973, 0.976, 0.988, 1.0), _ui.BORDER_NEUTRAL, _ui.BORDER_W, _ui.CARD_RADIUS, true)
		"card_selected":
			_style_base(sb, Color(1.0, 1.0, 0.82, 1.0), _ui.BORDER_SELECT, _ui.BORDER_W_ACTIVE, _ui.CARD_RADIUS, true)
		"card_hover":
			_style_base(sb, Color(0.9, 0.93, 0.98, 1.0), _ui.BORDER_FOCUS, _ui.BORDER_W_ACTIVE, _ui.CARD_RADIUS, true)
		"card_hover_selected":
			_style_base(sb, Color(1.0, 0.98, 0.72, 1.0), _ui.BORDER_SELECT_HOVER, _ui.BORDER_W_ACTIVE, _ui.CARD_RADIUS, true)
		"mini_card":
			_style_base(sb, Color(0.973, 0.976, 0.988, 0.92), _ui.BORDER_NEUTRAL, _ui.BORDER_W, _ui.CARD_RADIUS, false)
		"mini_card_hover":
			_style_base(sb, Color(0.9, 0.93, 0.98, 0.95), _ui.BORDER_FOCUS, _ui.BORDER_W, _ui.CARD_RADIUS, false)
		"button":
			# 按钮圆角比卡牌小一档（BUTTON_RADIUS=6）：按钮尺寸更小，8px 在同一屏会显得过圆
			_style_base(sb, Color(0.173, 0.243, 0.314, 1.0), Color(0.4, 0.55, 0.7, 1.0), _ui.BORDER_W, _ui.BUTTON_RADIUS, true)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
		"log_panel":
			# 日志底板：白色半透明 + 中性描边，压在浅蓝背景上把日志框住。
			# 半透明是为了不切断右侧留白的整体感（不透明白卡会像多出一块面板）。
			_style_base(sb, Color(1.0, 1.0, 1.0, 0.62), _ui.BORDER_NEUTRAL, _ui.BORDER_W, _ui.PANEL_RADIUS, true)
		"log_title":
			# 右栏折叠标题条：半透明白底 + 底部 1px 分隔线（叠在同色底板上要能看出是「一条」）
			_style_base(sb, Color(1.0, 1.0, 1.0, 0.42), Color(0.83, 0.87, 0.92, 1.0), 0, _ui.BUTTON_RADIUS, false)
			sb.border_width_bottom = 1
			sb.content_margin_left = _ui.LOG_TEXT_PAD
			sb.content_margin_right = 8
		"log_title_hover":
			# 悬停只把底色提亮一档，不换描边（避免标题条跳动）
			_style_base(sb, Color(1.0, 1.0, 1.0, 0.72), Color(0.83, 0.87, 0.92, 1.0), 0, _ui.BUTTON_RADIUS, false)
			sb.border_width_bottom = 1
			sb.content_margin_left = _ui.LOG_TEXT_PAD
			sb.content_margin_right = 8
		"valence_chip":
			# 卡面价态圆底：极浅暖底，把 12~15px 的红色价态文字从白卡面上托起来
			_style_base(sb, Color(0.98, 0.93, 0.93, 1.0), Color(0, 0, 0, 0), 0, _ui.CHIP_RADIUS, false)
		"tab_on":
			# 帮助中心 Tab（选中）：白底 + 底部 3px 蓝色下划线
			_style_base(sb, Color(1.0, 1.0, 1.0, 1.0), Color(0, 0, 0, 0), 0, 0, false)
			sb.border_color = _ui.HELP_C_TAB_ON
			sb.border_width_bottom = 3
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
		"tab_off":
			# 帮助中心 Tab（未选中）：透明底 + 无描边
			_style_base(sb, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, false)
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
		"toast_warning":
			_style_base(sb, Color(1.0, 0.953, 0.851, 0.97), _ui.BORDER_WARN, _ui.BORDER_W_ACTIVE, _ui.PANEL_RADIUS, true)
		"toast_info":
			_style_base(sb, Color(1.0, 1.0, 0.85, 0.95), Color(1.0, 0.6, 0.0, 1.0), _ui.BORDER_W_ACTIVE, _ui.PANEL_RADIUS, true)
		_:
			_style_base(sb, Color(0.973, 0.976, 0.988, 1.0), _ui.BORDER_NEUTRAL, _ui.BORDER_W, _ui.CARD_RADIUS, true)
	return sb


# 统一填充底色 / 描边 / 圆角 / 阴影，避免各调用点各写一套数值
func _style_base(sb: StyleBoxFlat, bg: Color, border: Color, width: int, radius: int, shadow: bool) -> void:
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	if shadow:
		sb.shadow_color = _ui.SHADOW_COLOR
		sb.shadow_size = _ui.SHADOW_SIZE
		sb.shadow_offset = _ui.SHADOW_OFFSET


# ============================================================
# 十一、元素着色规则（原 GameUI.gd 同名小节）
# ============================================================
func _get_card_color(card) -> Color:
	var sym = card.symbol
	if sym == "H": return Color(0.4, 0.7, 1.0)
	if sym == "O": return Color(0.0, 0.3, 1.0)
	if sym == "N": return Color(0.4, 0.2, 0.8)
	if sym == "F": return Color(0.56, 1.0, 0.56)
	if sym == "Cl": return Color(0.56, 1.0, 0.56)
	if sym == "Br": return Color(0.6, 0.4, 0.2)
	if sym == "I": return Color(0.35, 0.0, 0.35)  # 紫黑色
	if sym in ["C", "B", "Si", "S"]: return Color(1.0, 0.9, 0.1)
	if sym == "P": return Color(1.0, 0.85, 0.85)
	if card.group in ["VIIA"]: return Color(0.0, 0.7, 0.2)
	match card.element_type:
		"金属": return Color(0.5, 0.5, 0.5)
		"非金属": return Color(0.0, 0.7, 0.2)
		"准金属": return Color(0.0, 0.7, 0.2)
		# 稀有气体：原为近白 (0.95)，在白卡面上与底色几乎融成一片 → 改青色。
		# 色相刻意与「非金属 / 准金属 = 绿 (0,0.7,0.2)」「N = 紫 (0.4,0.2,0.8)」拉开距离
		"稀有气体": return Color(0.0, 0.6, 0.65)
	return Color(0.8, 0.8, 0.8)
