extends Node2D

@onready var cm: Node = $CombatManager
@onready var hud: Node = $HUD
@onready var floating_layer: Node = $FloatingTextLayer

@onready var player: Node2D = $Player
@onready var enemy: Node2D = $Enemy

var enemy_frozen: bool = false
const FREEZE_ACTION := "toggle_enemy_freeze"

var _result_shown: bool = false
var _result_layer: CanvasLayer
var _result_root: Control

func _ready() -> void:
	_ensure_freeze_action_exists()

	# CombatManager -> HUD
	if cm != null:
		if cm.has_signal("phase_changed"):
			cm.connect("phase_changed", Callable(self, "_on_phase_changed"))
		if cm.has_signal("rt_changed"):
			cm.connect("rt_changed", Callable(self, "_on_rt_changed"))

	# Player/Enemy -> Result
	_connect_result_signals()

	# set trạng thái freeze lên HUD ngay từ đầu
	_update_freeze_hud()


func _connect_result_signals() -> void:
	if player != null and player.has_signal("died"):
		player.connect("died", Callable(self, "_on_player_died"))

	if enemy != null and enemy.has_signal("defeated"):
		enemy.connect("defeated", Callable(self, "_on_enemy_defeated"))


func _ensure_freeze_action_exists() -> void:
	if InputMap.has_action(FREEZE_ACTION):
		return

	InputMap.add_action(FREEZE_ACTION)
	var ev := InputEventKey.new()
	ev.keycode = KEY_F1
	InputMap.action_add_event(FREEZE_ACTION, ev)


func _unhandled_input(_event: InputEvent) -> void:
	# Toggle freeze enemy (debug)
	if Input.is_action_just_pressed(FREEZE_ACTION):
		enemy_frozen = not enemy_frozen

		if enemy != null and enemy.has_method("set_debug_frozen"):
			enemy.call("set_debug_frozen", enemy_frozen)

		_update_freeze_hud()


func _update_freeze_hud() -> void:
	if hud != null and hud.has_method("set_enemy_freeze"):
		hud.call("set_enemy_freeze", enemy_frozen)


func _on_phase_changed(phase_text: String, is_enemy: bool) -> void:
	if hud != null and hud.has_method("set_phase"):
		hud.call("set_phase", phase_text, is_enemy)


func _on_rt_changed(rt_current: float, rt_max: float) -> void:
	if hud != null and hud.has_method("set_rt"):
		hud.call("set_rt", rt_current, rt_max)


# =========================================================
# RESULT (WIN / GAME OVER) - cho prototype/vertical slice
# =========================================================
func _on_player_died() -> void:
	_show_result(false)

func _on_enemy_defeated() -> void:
	_show_result(true)

func _show_result(is_win: bool) -> void:
	if _result_shown:
		return
	_result_shown = true

	# Pause game, nhưng UI kết quả vẫn hoạt động (process_mode ALWAYS)
	get_tree().paused = true

	_build_result_overlay()

	var title := "YOU WIN!" if is_win else "GAME OVER"
	var subtitle := "Retry to play again." if is_win else "Try again."

	var title_label: Label = _result_root.get_node("Panel/VBox/Title") as Label
	var sub_label: Label = _result_root.get_node("Panel/VBox/Sub") as Label
	title_label.text = title
	sub_label.text = subtitle

	# Optional: show 1 floating text to emphasize
	if player != null:
		spawn_floating_text(title, player.global_position, "#FFFF66")
	elif enemy != null:
		spawn_floating_text(title, enemy.global_position, "#FFFF66")


func _build_result_overlay() -> void:
	if _result_layer != null and is_instance_valid(_result_layer):
		return

	_result_layer = CanvasLayer.new()
	_result_layer.name = "ResultLayer"
	_result_layer.layer = 50
	_result_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_result_layer)

	_result_root = Control.new()
	_result_root.name = "ResultRoot"
	_result_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_result_root.anchor_left = 0
	_result_root.anchor_top = 0
	_result_root.anchor_right = 1
	_result_root.anchor_bottom = 1
	_result_root.offset_left = 0
	_result_root.offset_top = 0
	_result_root.offset_right = 0
	_result_root.offset_bottom = 0
	_result_layer.add_child(_result_root)

	# Dim background
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.65)
	dim.anchor_left = 0
	dim.anchor_top = 0
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.offset_left = 0
	dim.offset_top = 0
	dim.offset_right = 0
	dim.offset_bottom = 0
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	_result_root.add_child(dim)

	# Panel container
	var panel := Panel.new()
	panel.name = "Panel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_top = -120
	panel.offset_right = 220
	panel.offset_bottom = 120
	_result_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.anchor_left = 0
	vbox.anchor_top = 0
	vbox.anchor_right = 1
	vbox.anchor_bottom = 1
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text = "RESULT"
	title.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(title)

	var sub := Label.new()
	sub.name = "Sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = ""
	sub.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	var btn_retry := Button.new()
	btn_retry.name = "RetryBtn"
	btn_retry.text = "Retry"
	btn_retry.process_mode = Node.PROCESS_MODE_ALWAYS
	btn_retry.pressed.connect(Callable(self, "_on_retry_pressed"))
	vbox.add_child(btn_retry)

	var btn_back := Button.new()
	btn_back.name = "BackBtn"
	btn_back.text = "Back"
	btn_back.process_mode = Node.PROCESS_MODE_ALWAYS
	btn_back.pressed.connect(Callable(self, "_on_back_pressed"))
	vbox.add_child(btn_back)


func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_back_pressed() -> void:
	get_tree().paused = false
	var menu_path := "res://scenes/MainMenu.tscn"
	get_tree().change_scene_to_file(menu_path)

# =========================================================
# FLOATING COMBAT TEXT (HIT / MISS / GUARD / PARRY / ...)
# =========================================================
func spawn_floating_text(msg: String, world_pos: Vector2, hex_color: String = "#FFFFFF") -> void:
	if floating_layer == null:
		return

	var label := Label.new()
	label.text = msg
	label.modulate = Color(hex_color)

	# Nếu layer là CanvasLayer thì cần chuyển world->screen
	if floating_layer is CanvasLayer:
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
		label.position = screen_pos + Vector2(-20, -70)
	else:
		label.position = world_pos + Vector2(-20, -70)

	# Không dùng z_index cực lớn nữa (tránh CANVAS_ITEM_Z_MAX spam)
	label.z_index = 0
	floating_layer.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -30), 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)
