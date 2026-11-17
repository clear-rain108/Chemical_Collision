# ============================================================
# ui/PageRouter.gd - 页面切换基础设施 + 三个层容器
#
# 从 GameUI.gd 搬来（Slice 1）：
#   _ensure_layers / _make_layer / _layer         （四之二、层容器）
#   _ensure_page_backdrop / _all_pages /
#   _fade_in_page / _show_start_page              （五、页面切换）
#
# 状态留在 root（测试直读）：
#   tests/verify_motion.gd、verify_help_page.gd 直接读 scene._page_fade_tween，
#   verify_motion 还会遍历 scene._page_intro_tweens —— 所以补间引用与层容器引用
#   都留在 root，模块只负责「怎么切」，不持有它们。
# ============================================================
extends RefCounted

var _ui = null


func _init(ui) -> void:
	_ui = ui


# ============================================================
# 四之二、层容器（Content / Overlay / Toast）
# ============================================================
# Main.tscn 里的静态节点全在 z=0；运行时新增节点按语义挂进三个层：
#   ContentLayer(z=0)   → 与静态节点同层，靠树序叠在静态节点之上
#   OverlayLayer(z=100) → 模态弹窗 + 全屏遮罩，必须盖住手牌（手牌最高 z=20）
#   ToastLayer(z=110)   → 警告 / 提示，必须盖住模态层
func _ensure_layers() -> void:
	if not _ui.game_page:
		return
	if not is_instance_valid(_ui.content_layer):
		_ui.content_layer = _make_layer("ContentLayer", _ui.Z_CONTENT)
	if not is_instance_valid(_ui.overlay_layer):
		_ui.overlay_layer = _make_layer("OverlayLayer", _ui.Z_SCRIM)
	if not is_instance_valid(_ui.toast_layer):
		_ui.toast_layer = _make_layer("ToastLayer", _ui.Z_TOAST)


func _make_layer(layer_name: String, z: int) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.z_index = z
	# 层自身不参与鼠标拾取，事件仍会落到其子节点
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.anchor_left = 0
	layer.anchor_top = 0
	layer.anchor_right = 1
	layer.anchor_bottom = 1
	layer.offset_left = 0
	layer.offset_top = 0
	layer.offset_right = 0
	layer.offset_bottom = 0
	_ui.game_page.add_child(layer)
	return layer


# 取层时必须保证已创建（脚本内各处直接调用，避免 _ready 之外的入口拿到 null）
func _layer(kind: int) -> Control:
	_ensure_layers()
	match kind:
		1: return _ui.overlay_layer
		2: return _ui.toast_layer
		_: return _ui.content_layer


# ============================================================
# 五、页面切换
# ============================================================
# -------- 页面淡入基础设施（P3） --------
# 根节点下的常驻同色底：页面淡入时 alpha 降到 0 露出的仍是 #E6F0FA，
# 因此不会闪出窗口默认清屏色（深灰）。挂在根节点而非 GamePage，
# 因为 GamePage 自身在切换时会被隐藏。
func _ensure_page_backdrop() -> void:
	if _ui.get_node_or_null("PageBackdrop") != null:
		return
	var bg := ColorRect.new()
	bg.name = "PageBackdrop"
	bg.color = _ui.PAGE_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -100
	_ui.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.move_child(bg, 0)


func _all_pages() -> Array:
	return [
		_ui.start_page, _ui.game_page, _ui.end_page, _ui.help_page,
		_ui.get_node_or_null("TutorialPage"),
	]


# 目标页淡入；其余页 alpha 复位（避免「淡入中途被切走」留下半透明页）
func _fade_in_page(page) -> void:
	if page == null or not is_instance_valid(page):
		return
	for p in _all_pages():
		if p != null and is_instance_valid(p) and p != page:
			p.modulate.a = 1.0
	if _ui._page_fade_tween != null and _ui._page_fade_tween.is_valid():
		_ui._page_fade_tween.kill()
	page.modulate.a = 0.0
	_ui._page_fade_tween = _ui.create_tween()
	_ui._page_fade_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ui._page_fade_tween.tween_property(page, "modulate:a", 1.0, _ui.PAGE_FADE_MS / 1000.0)


func _show_start_page() -> void:
	_ui._close_supp_rules()   # 从结束页 / 帮助页回来时不能还停在上一次打开的小页上
	# Step 4：回开始页 = 离开房间（关会话 + 断开装配，D13）。没有会话时是空操作
	_ui._close_room_page()
	# 回开始页 = 开新局：上一个房间 / 上一局的联机终止提示一律作废
	_ui._clear_net_over_notice()
	_ui._hide_warning_toast()
	if _ui.start_page: _ui.start_page.visible = true
	if _ui.game_page: _ui.game_page.visible = false
	if _ui.end_page: _ui.end_page.visible = false
	var tut_page = _ui.get_node_or_null("TutorialPage")
	if _ui.help_page: _ui.help_page.visible = false
	if tut_page: tut_page.visible = false
	# 回调必须指向 root 的同名方法（测试按名字反射/spy 的是 root，不能改成模块方法）
	_ui._ensure_end_button_connected(_ui._show_start_page)

	# 回到主界面时清空上一局日志，避免残留
	_ui.log_lines.clear()
	if _ui.log_label:
		_ui.log_label.text = "游戏日志:"
	# 教学局残留的规则提醒也一并清掉（它挂在 ContentLayer 上，会跟着进下一局）
	_ui._level0_clear_rule_tips()
	_fade_in_page(_ui.start_page)
	_ui._animate_start_page()   # 子节点错峰淡入 + 装饰牌浮动（不触碰 start_page.modulate）
