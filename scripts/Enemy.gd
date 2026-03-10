extends CharacterBody2D

@export var max_hp: int = 80
var hp: int = 80

# ===== AI movement =====
@export var move_speed: float = 150.0
@export var stop_distance: float = 54.0
@export var retreat_speed: float = 90.0
@export var retreat_distance: float = 180.0
@export var gravity: float = 1200.0
@export var aggro_range: float = 260.0 # vẫn giữ để debug/đổi sau, nhưng không gate khi đã encounter

# ===== Attack =====
@export var hit_damage: int = 20
@export var hit_range: float = 56.0
@export var windup_time: float = 0.45
@export var active_time: float = 0.12
@export var recovery_time: float = 0.45

@export var attack_cooldown: float = 0.55
var attack_cd: float = 0.0

@export var need_rt_ratio: float = 0.12

# ===== Enemy guard (Player Phase) =====
@export var enemy_guard_damage_mult: float = 0.55
@export var enemy_guard_chance: float = 0.75
@export var enemy_guard_knockback: float = 80.0

# ===== Visual =====
@export var idle_color: Color = Color("#EF4444")
@export var chase_color: Color = Color("#FB7185")
@export var windup_color: Color = Color("#F59E0B")
@export var active_color: Color = Color("#FF2D2D")
@export var recovery_color: Color = Color("#B91C1C")
@export var guard_color: Color = Color("#60A5FA")

@onready var cm: Node = get_tree().current_scene.get_node_or_null("World/CombatManager")
@onready var player: Node2D = get_tree().current_scene.get_node_or_null("World/Player") as Node2D

@onready var debug_body: CanvasItem = get_node_or_null("DebugBody") as CanvasItem
@onready var hp_float: Label = get_node_or_null("HPFloat") as Label
@onready var windup_float: Label = get_node_or_null("WindupFloat") as Label
@onready var encounter_area: Area2D = get_node_or_null("EncounterArea") as Area2D
@onready var rt_bar: ProgressBar = get_node_or_null("EnemyRTBar/Bar") as ProgressBar

enum AttackState { IDLE, WINDUP, ACTIVE, RECOVERY }
var state: int = AttackState.IDLE
var t: float = 0.0
var did_hit: bool = false
var windup_left: float = 0.0

var _encounter_count: int = 0
var _in_encounter: bool = false

var rt_max: float = 2.5
var rt_current: float = 0.0

var debug_frozen: bool = false


func set_debug_frozen(on: bool) -> void:
	debug_frozen = on
	if debug_frozen:
		state = AttackState.IDLE
		t = 0.0
		did_hit = false
		windup_left = 0.0
		velocity = Vector2.ZERO


func _ready() -> void:
	add_to_group("enemy")

	if player == null:
		var arr := get_tree().get_nodes_in_group("player")
		if arr.size() > 0 and arr[0] is Node2D:
			player = arr[0] as Node2D

	hp = max_hp
	_set_color(idle_color)
	_update_float_text()

	if cm != null:
		rt_max = float(cm.get("player_rt_max"))
	else:
		rt_max = 2.5
	rt_current = rt_max

	if encounter_area != null:
		if not encounter_area.is_connected("body_entered", Callable(self, "_on_encounter_entered")):
			encounter_area.connect("body_entered", Callable(self, "_on_encounter_entered"))
		if not encounter_area.is_connected("body_exited", Callable(self, "_on_encounter_exited")):
			encounter_area.connect("body_exited", Callable(self, "_on_encounter_exited"))

	if rt_bar != null:
		rt_bar.min_value = 0.0
		rt_bar.max_value = 1.0
		rt_bar.value = 1.0
		rt_bar.show_percentage = false


func _on_encounter_entered(body: Node) -> void:
	if body != player:
		return
	_encounter_count += 1
	_in_encounter = (_encounter_count > 0)


func _on_encounter_exited(body: Node) -> void:
	if body != player:
		return
	_encounter_count = max(_encounter_count - 1, 0)
	_in_encounter = (_encounter_count > 0)


func _physics_process(delta: float) -> void:
	if debug_frozen:
		velocity = Vector2.ZERO
		windup_left = 0.0
		_update_float_text()
		_update_rtbar_visual(delta)
		move_and_slide()
		return

	if attack_cd > 0.0:
		attack_cd -= delta

	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	_update_rtbar_visual(delta)

	if not _in_encounter:
		velocity.x = 0.0
		state = AttackState.IDLE
		windup_left = 0.0
		_set_color(idle_color)
		_update_float_text()
		move_and_slide()
		return

	var enemy_phase: bool = false
	var player_phase: bool = false
	if cm != null:
		enemy_phase = bool(cm.call("is_enemy_phase"))
		player_phase = bool(cm.call("is_player_phase"))

	if enemy_phase:
		_enemy_phase_ai(delta)
	elif player_phase:
		_player_phase_behavior(delta)
	else:
		velocity.x = 0.0
		state = AttackState.IDLE
		windup_left = 0.0
		_set_color(idle_color)

	move_and_slide()


func _enemy_phase_ai(delta: float) -> void:
	var draining: bool = false
	if cm != null:
		draining = bool(cm.call("is_draining"))

	if state != AttackState.IDLE:
		velocity.x = 0.0
		_update_attack(delta)
		return

	if player == null:
		velocity.x = 0.0
		return

	# ✅ ĐÃ encounter thì luôn chase, KHÔNG gate bằng aggro_range nữa
	var dx: float = float(player.global_position.x - global_position.x)
	var dist_x: float = abs(dx)

	if dist_x > stop_distance:
		velocity.x = sign(dx) * move_speed
		_set_color(chase_color)
	else:
		velocity.x = 0.0
		var need_rt: float = rt_max * need_rt_ratio
		if draining and attack_cd <= 0.0 and rt_current >= need_rt:
			_start_attack()


func _player_phase_behavior(_delta: float) -> void:
	state = AttackState.IDLE
	did_hit = false
	windup_left = 0.0
	_update_float_text()

	if player == null:
		velocity.x = 0.0
		_set_color(idle_color)
		return

	var dx: float = float(player.global_position.x - global_position.x)
	var dist: float = abs(dx)

	if dist < retreat_distance:
		velocity.x = -sign(dx) * retreat_speed
	else:
		velocity.x = 0.0

	_set_color(idle_color)


func _start_attack() -> void:
	state = AttackState.WINDUP
	t = windup_time
	windup_left = t
	did_hit = false
	attack_cd = attack_cooldown
	_set_color(windup_color)
	_update_float_text()


func _update_attack(delta: float) -> void:
	match state:
		AttackState.WINDUP:
			t -= delta
			windup_left = max(t, 0.0)
			_update_float_text()
			if t <= 0.0:
				state = AttackState.ACTIVE
				t = active_time
				windup_left = 0.0
				_set_color(active_color)
				_update_float_text()

		AttackState.ACTIVE:
			windup_left = 0.0
			if not did_hit:
				_try_hit_player_once()
				did_hit = true
			t -= delta
			if t <= 0.0:
				state = AttackState.RECOVERY
				t = recovery_time
				_set_color(recovery_color)

		AttackState.RECOVERY:
			windup_left = 0.0
			t -= delta
			if t <= 0.0:
				state = AttackState.IDLE
				_set_color(idle_color)


func _try_hit_player_once() -> void:
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist <= hit_range and player.has_method("receive_attack"):
		player.call("receive_attack", hit_damage, global_position)


func take_damage(amount: int) -> void:
	var is_player_phase: bool = true
	if cm != null:
		is_player_phase = bool(cm.call("is_player_phase"))
	if not is_player_phase:
		return

	var guarded: bool = (randf() < enemy_guard_chance)
	if guarded:
		var dmg_guard: int = int(round(float(amount) * enemy_guard_damage_mult))
		hp = max(hp - dmg_guard, 0)
		_set_color(guard_color)
		_enemy_show_text("ENEMY GUARD!", "#60A5FA")
		if player != null:
			var dir: float = -1.0 if global_position.x < float(player.global_position.x) else 1.0
			velocity.x = dir * enemy_guard_knockback
	else:
		hp = max(hp - amount, 0)
		_enemy_show_text("HIT!", "#FFFFFF")

	_update_float_text()
	if hp == 0:
		queue_free()


func _update_float_text() -> void:
	if hp_float != null:
		hp_float.text = "%d/%d" % [hp, max_hp]

	if windup_float != null:
		if windup_left > 0.0:
			windup_float.text = "WINDUP: %.2fs" % windup_left
			windup_float.visible = true
		else:
			windup_float.text = ""
			windup_float.visible = false


# ===== EnemyRTBar (ratio + lerp) =====
func _update_rtbar_visual(delta: float) -> void:
	if rt_bar == null:
		return

	if not _in_encounter:
		_apply_rtbar_state_ratio(0.0, "NONE", delta)
		return

	if cm != null:
		rt_max = float(cm.get("player_rt_max"))

	var enemy_phase: bool = false
	var player_phase: bool = false
	if cm != null:
		enemy_phase = bool(cm.call("is_enemy_phase"))
		player_phase = bool(cm.call("is_player_phase"))

	if player_phase:
		rt_current = clamp(rt_current - delta, 0.0, rt_max)
		if rt_current <= 0.0:
			_apply_rtbar_state_ratio(0.0, "EMPTY", delta)
		else:
			_apply_rtbar_state_ratio(rt_current / rt_max, "DRAIN", delta)
	elif enemy_phase:
		var regen: float = 2.4
		if cm != null:
			regen = float(cm.get("player_rt_regen_per_sec"))
		rt_current = clamp(rt_current + regen * delta, 0.0, rt_max)
		_apply_rtbar_state_ratio(rt_current / rt_max, "REGEN", delta)
	else:
		_apply_rtbar_state_ratio(rt_current / rt_max, "REGEN", delta)


func _apply_rtbar_state_ratio(target_ratio: float, mode: String, delta: float) -> void:
	rt_bar.min_value = 0.0
	rt_bar.max_value = 1.0

	var clamped: float = clamp(target_ratio, 0.0, 1.0)
	var smooth_speed: float = 16.0
	rt_bar.value = lerp(float(rt_bar.value), clamped, 1.0 - pow(0.001, smooth_speed * delta))

	match mode:
		"NONE":
			rt_bar.modulate = Color("#374151")
		"REGEN":
			rt_bar.modulate = Color("#9CA3AF")
		"DRAIN":
			rt_bar.modulate = Color("#22D3EE")
		"EMPTY":
			rt_bar.modulate = Color("#6B7280")
		_:
			rt_bar.modulate = Color("#9CA3AF")


func _enemy_show_text(msg: String, hex_color: String) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_floating_text"):
		scene.call("spawn_floating_text", msg, global_position, hex_color)


func _set_color(c: Color) -> void:
	if debug_body != null:
		debug_body.modulate = c
