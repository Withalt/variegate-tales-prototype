extends Node2D

@onready var cm: Node = $World/CombatManager
@onready var player: CharacterBody2D = $World/Player
@onready var player_spawn: Node2D = $World/PlayerSpawn
@onready var floating_layer: Node2D = $World/FloatingTextLayer
@onready var enemies_root: Node2D = $World/Enemies
@onready var hud: CanvasLayer = $UI/HUD
@onready var hazards_root: Node2D = $World/Hazards
@onready var goal_flag: Area2D = $World/GoalFlag

var _encounter_count: int = 0

const LAYER_PLAYER_BIT := 1 << (2 - 1) # 2
const LAYER_ENEMY_BIT  := 1 << (3 - 1) # 4

# overlay ref
var _end_overlay: CanvasLayer = null


func _ready() -> void:
	call_deferred("_apply_spawn")

	# player chết -> gameover
	if player != null and player.has_signal("died"):
		if not player.is_connected("died", Callable(self, "_on_player_died")):
			player.connect("died", Callable(self, "_on_player_died"))

	_connect_combat_signals()
	_setup_goalflag()
	_setup_killzones()
	_setup_enemy_encounters()

	if hud != null and hud.has_method("set_rt_enabled"):
		hud.call("set_rt_enabled", false)

	if cm != null and cm.has_method("set_encounter_active"):
		cm.call("set_encounter_active", false)


func _apply_spawn() -> void:
	if player == null or player_spawn == null:
		return
	player.global_position = player_spawn.global_position
	player.velocity = Vector2.ZERO


func _on_player_died() -> void:
	_show_lose_overlay()


# =========================================================
# CM -> HUD
# =========================================================
func _connect_combat_signals() -> void:
	if cm == null:
		return
	if cm.has_signal("phase_changed"):
		cm.connect("phase_changed", Callable(self, "_on_phase_changed"))
	if cm.has_signal("rt_changed"):
		cm.connect("rt_changed", Callable(self, "_on_rt_changed"))

func _on_phase_changed(_phase_text: String, _is_enemy: bool) -> void:
	pass

func _on_rt_changed(rt_current: float, rt_max: float, state: int) -> void:
	if hud != null and hud.has_method("set_rt"):
		hud.call("set_rt", rt_current, rt_max, state)


# =========================================================
# GOAL
# =========================================================
func _setup_goalflag() -> void:
	if goal_flag == null:
		return
	goal_flag.collision_mask = LAYER_PLAYER_BIT
	if not goal_flag.is_connected("body_entered", Callable(self, "_on_goal_body_entered")):
		goal_flag.connect("body_entered", Callable(self, "_on_goal_body_entered"))

func _on_goal_body_entered(body: Node) -> void:
	if body == player:
		_show_win_overlay()


# =========================================================
# KILLZONES
# =========================================================
func _setup_killzones() -> void:
	if hazards_root == null:
		return
	for child in hazards_root.get_children():
		if child is Area2D:
			var a := child as Area2D
			a.collision_mask = LAYER_PLAYER_BIT | LAYER_ENEMY_BIT
			if not a.is_connected("body_entered", Callable(self, "_on_killzone_body_entered")):
				a.connect("body_entered", Callable(self, "_on_killzone_body_entered"))

func _on_killzone_body_entered(body: Node) -> void:
	if body == player:
		_show_lose_overlay()
		return
	if body != null and body.is_in_group("enemy"):
		body.queue_free()


# =========================================================
# ENCOUNTER (vào là enemy đuổi/đánh ngay)
# =========================================================
func _setup_enemy_encounters() -> void:
	if enemies_root == null:
		return
	for e in enemies_root.get_children():
		if e == null:
			continue

		var encounter := e.get_node_or_null("EncounterArea")
		if encounter == null:
			push_warning("Enemy missing child EncounterArea: %s" % [str(e.name)])
			continue

		if encounter is Area2D:
			var area := encounter as Area2D
			if not area.is_connected("body_entered", Callable(self, "_on_enemy_encounter_entered")):
				area.connect("body_entered", Callable(self, "_on_enemy_encounter_entered"))
			if not area.is_connected("body_exited", Callable(self, "_on_enemy_encounter_exited")):
				area.connect("body_exited", Callable(self, "_on_enemy_encounter_exited"))

func _on_enemy_encounter_entered(body: Node) -> void:
	if body != player:
		return

	_encounter_count += 1
	if _encounter_count == 1:
		# ép encounter bắt đầu ở Enemy Phase => enemy chase/attack ngay
		if cm != null:
			if cm.has_method("start_encounter_enemy_first"):
				cm.call("start_encounter_enemy_first")
			elif cm.has_method("set_encounter_active"):
				cm.set("start_enemy_phase", true)
				cm.call("set_encounter_active", true)

		if hud != null and hud.has_method("set_rt_enabled"):
			hud.call("set_rt_enabled", true)

func _on_enemy_encounter_exited(body: Node) -> void:
	if body != player:
		return

	_encounter_count = max(_encounter_count - 1, 0)
	if _encounter_count == 0:
		if cm != null and cm.has_method("set_encounter_active"):
			cm.call("set_encounter_active", false)

		if hud != null and hud.has_method("set_rt_enabled"):
			hud.call("set_rt_enabled", false)


# =========================================================
# FLOATING TEXT
# =========================================================
func spawn_floating_text(msg: String, world_pos: Vector2, hex_color: String = "#FFFFFF") -> void:
	if floating_layer == null:
		return

	var label := Label.new()
	label.text = msg
	label.modulate = Color(hex_color)
	label.position = world_pos + Vector2(-20, -70)
	label.z_index = 9999
	floating_layer.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -30), 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


# =========================================================
# FULLSCREEN WIN/LOSE OVERLAY + FREEZE GAMEPLAY (Retry only)
# =========================================================
func _show_win_overlay() -> void:
	_show_end_overlay_fullscreen("YOU WIN")

func _show_lose_overlay() -> void:
	_show_end_overlay_fullscreen("GAME OVER")


func _show_end_overlay_fullscreen(title: String) -> void:
	if _end_overlay != null:
		return

	# pause toàn bộ gameplay
	get_tree().paused = true

	# CanvasLayer UI chạy khi paused
	_end_overlay = CanvasLayer.new()
	_end_overlay.name = "EndOverlay"
	_end_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_end_overlay)

	# Root full screen
	var root := Control.new()
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 0.0
	root.offset_top = 0.0
	root.offset_right = 0.0
	root.offset_bottom = 0.0
	root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_end_overlay.add_child(root)

	# Dim background
	var dim := ColorRect.new()
	dim.anchor_left = 0.0
	dim.anchor_top = 0.0
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.offset_left = 0.0
	dim.offset_top = 0.0
	dim.offset_right = 0.0
	dim.offset_bottom = 0.0
	dim.color = Color(0, 0, 0, 0.65)
	dim.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	root.add_child(dim)

	# Center panel
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(520, 260)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -130
	panel.offset_right = 260
	panel.offset_bottom = 130
	panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	root.add_child(panel)

	var v := VBoxContainer.new()
	v.anchor_left = 0.0
	v.anchor_top = 0.0
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 24
	v.offset_top = 24
	v.offset_right = -24
	v.offset_bottom = -24
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	panel.add_child(v)

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	v.add_child(lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(1, 18)
	spacer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	v.add_child(spacer)

	var retry := Button.new()
	retry.text = "Retry"
	retry.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	retry.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
	)
	v.add_child(retry)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
