extends Node

signal phase_changed(phase_text: String, is_enemy: bool)
signal rt_changed(rt_current: float, rt_max: float, state: int)

enum Phase { ENEMY, PLAYER }
enum RTState { NONE, REGEN, DRAIN, EMPTY }

@export var player_rt_max: float = 2.5
@export var enemy_rt_max: float = 2.5

@export var player_rt_regen_per_sec: float = 2.4
@export var enemy_rt_regen_per_sec: float = 2.4

@export var start_enemy_phase: bool = true

var encounter_active: bool = false

var _phase: int = Phase.ENEMY
var _player_rt_current: float = 0.0
var _enemy_rt_current: float = 0.0


func _ready() -> void:
	_phase = Phase.ENEMY if start_enemy_phase else Phase.PLAYER
	_player_rt_current = 0.0
	_enemy_rt_current = 0.0


func set_encounter_active(on: bool) -> void:
	if on == encounter_active:
		return

	var was := encounter_active
	encounter_active = on

	if not was and on:
		# false -> true: reset FULL theo phase bắt đầu
		if start_enemy_phase:
			_phase = Phase.ENEMY
			_enemy_rt_current = enemy_rt_max
			_player_rt_current = 0.0
		else:
			_phase = Phase.PLAYER
			_player_rt_current = player_rt_max
			_enemy_rt_current = 0.0

		_emit_phase()
		_emit_rt()

	if was and not on:
		_player_rt_current = 0.0
		_enemy_rt_current = 0.0
		phase_changed.emit("", false)


# ✅ NEW: ép encounter bắt đầu bằng Enemy Phase (enemy đuổi/đánh ngay)
func start_encounter_enemy_first() -> void:
	if encounter_active:
		return
	start_enemy_phase = true
	set_encounter_active(true)


func _process(delta: float) -> void:
	if not encounter_active:
		return

	if _phase == Phase.ENEMY:
		_enemy_rt_current = max(_enemy_rt_current - delta, 0.0)
		_player_rt_current = min(_player_rt_current + player_rt_regen_per_sec * delta, player_rt_max)

		_emit_rt()

		if _enemy_rt_current <= 0.0:
			_phase = Phase.PLAYER
			_player_rt_current = player_rt_max
			_emit_phase()
			_emit_rt()

	else:
		_player_rt_current = max(_player_rt_current - delta, 0.0)
		_enemy_rt_current = min(_enemy_rt_current + enemy_rt_regen_per_sec * delta, enemy_rt_max)

		_emit_rt()

		if _player_rt_current <= 0.0:
			_phase = Phase.ENEMY
			_enemy_rt_current = enemy_rt_max
			_emit_phase()
			_emit_rt()


func _emit_rt() -> void:
	if not encounter_active:
		return

	# HUD đang hiển thị "PLAYER REACTION TIME"
	var state := RTState.DRAIN
	if _phase == Phase.PLAYER:
		state = RTState.DRAIN if _player_rt_current > 0.0 else RTState.EMPTY
	else:
		state = RTState.REGEN if _player_rt_current < player_rt_max else RTState.DRAIN

	rt_changed.emit(_player_rt_current, player_rt_max, state)


func _emit_phase() -> void:
	phase_changed.emit(phase_name(), is_enemy_phase())


func phase_name() -> String:
	return "ENEMY PHASE" if _phase == Phase.ENEMY else "PLAYER PHASE"

func is_enemy_phase() -> bool:
	return _phase == Phase.ENEMY

func is_player_phase() -> bool:
	return _phase == Phase.PLAYER

func is_draining() -> bool:
	return encounter_active and (_phase == Phase.ENEMY)
