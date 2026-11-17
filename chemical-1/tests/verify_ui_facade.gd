# ============================================================
# verify_ui_facade.gd - UI 层拆分的「门面完整性」守卫
#   UI_LAYER_REFACTOR.md §5.3
#
# 为什么需要它：拆分后 GameUI.gd 变成「装配 + 转发门面」，逻辑下沉到
# scripts/ui/*、scripts/pages/*、scripts/game/*、scripts/net/*。
# 76 个私有方法 + attach_session 都是测试用 scene.call("...") 反射调用的，
# 任何一处漏转发 => 对应那套测试在很深的位置报 "Invalid call"。
# 本测试在拆分的每一片之后跑一次，直接指出「哪个方法没了」，不用等 46 套跑完。
#
# 清单来源（机械生成，勿手改）：
#   godot --headless --path . --script tools/gen_facade_list.gd
#   之后把输出的数组粘到下面 MUST_HAVE_METHODS。
# ============================================================
extends SceneTree

var fails: int = 0

# ---- 测试反射调用的私有方法（tools/gen_facade_list.gd 生成，77 个）----
const MUST_HAVE_METHODS := [
	"_apply_card_compact", "_apply_card_selection", "_begin_drag", "_build_card_button", "_can_reorder_hand",
	"_card_core_rect", "_card_hover_rect", "_clear_net_over_notice", "_ensure_log_panel",
	"_finish_drag", "_get_card_color", "_hand_order_sig", "_hand_view_player",
	"_help_valence_text", "_hide_warning_toast", "_hit_card_at", "_hotseat_handoff_pending",
	"_hover_hit_index", "_hover_keep_above", "_human_players", "_init_game", "_insert_slot_at",
	"_is_hotseat", "_kill_hover_tween", "_layout_hand_cards", "_layout_log_panel",
	"_layout_rule_tips", "_level0_create_rule_tips", "_level0_make_tip_box",
	"_level0_rule_tips_text", "_level0_set_rule_tips_visible", "_level0_show_flow_step",
	"_level0_show_ui_step", "_level0_start_phase2", "_level0_update_rule_tips",
	"_make_panel_style", "_my_seat", "_net_can_operate", "_net_wait_text", "_on_card_clicked",
	"_on_discard_mode", "_on_hand_card_hover", "_on_hand_reorder", "_on_hint_toggled",
	"_on_hotseat_handoff_confirmed", "_on_pass", "_on_quit_game", "_on_start_game",
	"_on_start_tutorial", "_online_on_session_closed", "_open_room_page", "_panel_style_template",
	"_refresh_ui",
	"_room_bind_session", "_room_join", "_room_leave", "_room_refresh", "_room_start",
	"_room_start_host", "_room_teardown", "_sel_cards", "_set_hover_index", "_set_log_visible",
	"_show_center_warning", "_show_end_page", "_show_info", "_show_sequence_constraint_dialog",
	"_show_start_page", "_step_reset", "_update_action_panel", "_update_card_info_label",
	"_update_hand_buttons", "_update_hover_at", "_update_log_label", "_update_net",
	"_update_status_bar", "_update_table_label", "_view_player",
	# 公开方法（下划线过滤抓不到，手工补）
	"attach_session",
]

# ---- 测试直读 / 直写的字段（verify_ui_online:129/489、verify_hand_layout:250/350）----
const MUST_HAVE_FIELDS := ["hand_buttons", "selected_indices", "step_mode", "game_manager"]

# ---- 测试直读的常量（verify_hand_view:54、verify_motion:255/256/275）----
const MUST_HAVE_CONSTS := {"CARD_W": 95.0, "CARD_H": 118.0}


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		fails += 1
		print("FAIL: " + msg)


func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	_test_methods(scene)
	_test_fields(scene)
	_test_consts(scene)

	if fails == 0:
		print("ALL UI FACADE TESTS PASSED (%d methods / %d fields / %d consts)"
			% [MUST_HAVE_METHODS.size(), MUST_HAVE_FIELDS.size(), MUST_HAVE_CONSTS.size()])
	else:
		print("%d UI FACADE TEST(S) FAILED" % fails)
	quit(0 if fails == 0 else 1)


# ---------------- 一、方法门面 ----------------
func _test_methods(scene) -> void:
	var missing: Array = []
	for m in MUST_HAVE_METHODS:
		if not scene.has_method(m):
			missing.append(m)
	_check(missing.is_empty(),
		"根节点保留全部 %d 个测试可见方法" % MUST_HAVE_METHODS.size())
	if not missing.is_empty():
		print("  缺失: " + str(missing))
	# 数量下限：清单被误删时立刻暴露
	_check(MUST_HAVE_METHODS.size() >= 70, "门面清单规模 >= 70（实际 %d）" % MUST_HAVE_METHODS.size())



# ---------------- 二、字段门面（存在 + 可写）----------------
func _test_fields(scene) -> void:
	var props := {}
	for p in scene.get_property_list():
		props[String(p.get("name", ""))] = p
	for f in MUST_HAVE_FIELDS:
		_check(props.has(f), "字段 %s 存在于根节点" % f)

	# 可写性：验证脚本直接赋值（verify_hand_layout:250/350 就是这么干的）
	var hb_before: Array = scene.hand_buttons
	scene.hand_buttons = []
	_check(scene.hand_buttons.size() == 0, "hand_buttons 可从外部直接赋值")
	scene.hand_buttons = hb_before

	var sel_before: Array = scene.selected_indices
	scene.selected_indices = [0]
	_check(scene.selected_indices == [0], "selected_indices 可从外部直接赋值")
	scene.selected_indices = sel_before

	var sm_before: int = scene.step_mode
	scene.step_mode = 3
	_check(scene.step_mode == 3, "step_mode 可从外部直接赋值")
	scene.step_mode = sm_before

	# game_manager 只读存在性：测试会整体替换（verify_ui_online:129），这里不动状态
	_check(scene.game_manager == null or scene.game_manager != null, "game_manager 可读")


# ---------------- 三、常量门面 ----------------
func _test_consts(scene) -> void:
	var script: Script = scene.get_script()
	_check(script != null, "根节点挂有脚本")
	if script == null:
		return
	# 常量不是属性，Object.get() 读不到 —— 必须走脚本常量表
	var consts: Dictionary = script.get_script_constant_map()
	for k in MUST_HAVE_CONSTS:
		var want: float = MUST_HAVE_CONSTS[k]
		var has: bool = consts.has(k)
		_check(has and abs(float(consts[k]) - want) < 0.001,
			"常量 %s = %.1f（实际 %s）" % [k, want, str(consts.get(k, "缺失"))])

