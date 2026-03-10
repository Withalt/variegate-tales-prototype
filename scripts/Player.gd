extends CharacterBody2D

signal died

# ===== Movement =====
@export var move_speed: float = 220.0
@export var jump_velocity: float = -420.0
@export var gravity: float = 1200.0

# ===== HP =====
@export var max_hp: int = 100
var hp: int = 100

# ===== Attack (Player Phase) =====
@export var attack_damage: int = 25
@export var attack_range: float = 58.0

# ===== Guard / Knockback =====
@export var guard_damage_mult: float = 0.45
@export var guard_knockback: float = 140.0
@export var hit_knockback: float = 320.0

# ===== Evade (Dash) =====
@export var evade_speed: float = 520.0
@export var evade_time: float = 0.14
@export var evade_cooldown: float = 0.9
var evade_cd: float = 0.0
var evade_t: float = 0.0
var is_evading: bool = false

# ===== Parry =====
@export var parry_window: float = 0.14
@export var parry_cooldown: float = 1.0
@export var parry_counter_damage: int = 18
var parry_t: float = 0.0
var parry_active: bool = false
var parry_cd: float = 0.0

# ===== State =====
var is_guarding: bool = false

# ===== Visual =====
@export var base_color: Color = Color("#3B82F6")
@export var guard_color: Color = Color("#22D3EE")
@export var evade_color: Color = Color("#FBBF24")
@export var parry_color: Color = Color("#A78BFA")
@export var flash_color: Color = Color("#FFFFFF")

# ===== Scene refs (tree chuẩn hoá) =====
@onready var cm: Node = get_tree().current_scene.get_node_or_null("World/CombatManager")
@onready var hud: Node = get_tree().current_scene.get_node_or_null("UI/HUD")
@onready var enemies_root: Node2D = get_tree().current_scene.get_node_or_null("World/Enemies") as Node2D
@onready var debug_body: CanvasItem = get_node_or_null("DebugBody") as CanvasItem

var flash_t: float = 0.0
var _dead: bool = false


func _ready() -> void:
	hp = max_hp
	if not is_in_group("player"):
		add_to_group("player")
	_update_hud()
	_set_color(base_color)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_inside_tree():
		return

	# cooldowns
	if evade_cd > 0.0:
		evade_cd -= delta
	if parry_cd > 0.0:
		parry_cd -= delta

	# flash timer
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			_set_color(_current_state_color())

	# phase flags
	var enemy_phase: bool = false
	var player_phase: bool = true
	if cm != null:
		enemy_phase = cm.has_method("is_enemy_phase") and bool(cm.call("is_enemy_phase"))
		player_phase = cm.has_method("is_player_phase") and bool(cm.call("is_player_phase"))

	# HUD cooldown
	if hud != null:
		if hud.has_method("set_dash_cd"):
			hud.call("set_dash_cd", max(evade_cd, 0.0))
		if hud.has_method("set_parry_cd"):
			hud.call("set_parry_cd", max(parry_cd, 0.0))

	# guard chỉ meaningful trong enemy phase
	is_guarding = Input.is_action_pressed("guard") and enemy_phase and (not is_evading)

	# parry input chỉ trong enemy phase + cooldown
	if enemy_phase and Input.is_action_just_pressed("parry") and (not is_evading) and parry_cd <= 0.0:
		parry_active = true
		parry_t = parry_window
		parry_cd = parry_cooldown

	# tick parry window
	if parry_active:
		parry_t -= delta
		if parry_t <= 0.0:
			parry_active = false

	# gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and (not is_evading):
		velocity.y = jump_velocity

	# move
	var dir: float = Input.get_axis("move_left", "move_right")
	if not is_evading:
		velocity.x = dir * move_speed

	# evade dash
	if Input.is_action_just_pressed("evade") and (not is_evading) and evade_cd <= 0.0:
		_start_evade(dir)

	# attack chỉ trong player phase
	if Input.is_action_just_pressed("attack") and player_phase:
		_do_attack()

	# color by state
	if flash_t <= 0.0:
		_set_color(_current_state_color())

	move_and_slide()


func _process(delta: float) -> void:
	if _dead:
		return
	if is_evading:
		evade_t -= delta
		if evade_t <= 0.0:
			is_evading = false


func _start_evade(dir: float) -> void:
	var d: float = dir
	if d == 0.0:
		d = 1.0
	is_evading = true
	evade_t = evade_time
	evade_cd = evade_cooldown + evade_time
	velocity.x = d * evade_speed


func _do_attack() -> void:
	_flash(0.08)

	var enemy := _find_closest_enemy_in_range(attack_range)
	if enemy == null:
		_show_text("MISS", "#9CA3AF")
		return

	if enemy.has_method("take_damage"):
		enemy.call("take_damage", attack_damage)
		_show_text("HIT!", "#FFFFFF")
	else:
		_show_text("MISS", "#9CA3AF")


func _find_closest_enemy_in_range(r: float) -> Node:
	if enemies_root == null:
		return _find_closest_enemy_in_range_by_group(r)

	var best: Node = null
	var best_d := INF

	for e in enemies_root.get_children():
		if e == null or not e.is_inside_tree():
			continue
		if not e.is_in_group("enemy"):
			continue

		var d := global_position.distance_to(e.global_position)
		if d <= r and d < best_d:
			best_d = d
			best = e

	return best


func _find_closest_enemy_in_range_by_group(r: float) -> Node:
	var best: Node = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == null or not (e is Node2D):
			continue
		var n := e as Node2D
		var d := global_position.distance_to(n.global_position)
		if d <= r and d < best_d:
			best_d = d
			best = e
	return best


func receive_attack(amount: int, attacker_pos: Vector2) -> void:
	if _dead:
		return

	# Parry success
	if parry_active:
		parry_active = false
		_show_text("PARRY!", "#A78BFA")
		var target := _find_closest_enemy_in_range(attack_range + 20.0)
		if target != null and target.has_method("take_damage"):
			target.call("take_damage", parry_counter_damage)
		return

	# Guard success
	if is_guarding:
		var dmg_guard: int = int(round(float(amount) * guard_damage_mult))
		_apply_damage(dmg_guard)

		var dir: float = -1.0 if global_position.x < float(attacker_pos.x) else 1.0
		velocity.x = dir * guard_knockback

		_show_text("GUARD!", "#22D3EE")
		_flash(0.10)
		return

	# HIT direct
	_apply_damage(amount)

	var dir2: float = -1.0 if global_position.x < float(attacker_pos.x) else 1.0
	velocity.x = dir2 * hit_knockback

	_show_text("HIT!", "#FFFFFF")
	_flash(0.12)


func take_damage(amount: int) -> void:
	if _dead:
		return
	_apply_damage(amount)
	_show_text("HIT!", "#FFFFFF")
	_flash(0.10)


func _apply_damage(amount: int) -> void:
	hp -= amount
	if hp < 0:
		hp = 0
	_update_hud()
	if hp == 0:
		_die()


func kill() -> void:
	_die()


func _show_text(msg: String, hex_color: String) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("spawn_floating_text"):
		scene.call("spawn_floating_text", msg, global_position, hex_color)


func _die() -> void:
	if _dead:
		return
	_dead = true
	set_physics_process(false)
	set_process(false)
	emit_signal("died")


func _update_hud() -> void:
	if hud != null and hud.has_method("set_hp"):
		hud.call("set_hp", hp, max_hp)


func _flash(t: float) -> void:
	flash_t = t
	_set_color(flash_color)


func _set_color(c: Color) -> void:
	if debug_body != null:
		debug_body.modulate = c


func _current_state_color() -> Color:
	if is_evading:
		return evade_color
	if is_guarding:
		return guard_color
	if parry_active:
		return parry_color
	return base_color
