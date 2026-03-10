extends CanvasLayer

@onready var phase_label: Label = get_node_or_null("PhaseLabel") as Label
@onready var rt_bar: ProgressBar = get_node_or_null("RTBar") as ProgressBar
@onready var hp_label: Label = get_node_or_null("HPLabel") as Label
@onready var dash_cd_label: Label = get_node_or_null("DashCDLabel") as Label
@onready var parry_cd_label: Label = get_node_or_null("ParryCDLabel") as Label
@onready var freeze_label: Label = get_node_or_null("FreezeLabel") as Label

enum RTState { NONE, REGEN, DRAIN, EMPTY }

var _rt_enabled: bool = false


func _ready() -> void:
	if phase_label != null:
		phase_label.text = "PLAYER REACTION TIME"

	if rt_bar != null:
		rt_bar.min_value = 0
		rt_bar.max_value = 1
		rt_bar.value = 0

	set_rt_enabled(false)


func set_rt_enabled(on: bool) -> void:
	_rt_enabled = on
	if rt_bar == null:
		return

	if not on:
		_apply_rt_visual(RTState.NONE)
		rt_bar.value = 0
	else:
		_apply_rt_visual(RTState.DRAIN)
		rt_bar.value = 1


func set_rt(rt_current: float, rt_max: float, state: int) -> void:
	if rt_bar == null:
		return
	if not _rt_enabled:
		return

	var ratio := 0.0
	if rt_max > 0.0:
		ratio = clamp(rt_current / rt_max, 0.0, 1.0)

	rt_bar.value = ratio
	_apply_rt_visual(state)


func _apply_rt_visual(state: int) -> void:
	if rt_bar == null:
		return

	match state:
		RTState.NONE:
			rt_bar.modulate = Color("#374151")
		RTState.REGEN:
			rt_bar.modulate = Color("#9CA3AF")
		RTState.DRAIN:
			rt_bar.modulate = Color("#22D3EE")
		RTState.EMPTY:
			rt_bar.modulate = Color("#6B7280")
		_:
			rt_bar.modulate = Color("#9CA3AF")


func set_hp(current_hp: int, max_hp: int) -> void:
	if hp_label == null:
		return
	hp_label.text = "HP: %d / %d" % [current_hp, max_hp]


func set_dash_cd(cd: float) -> void:
	if dash_cd_label == null:
		return
	dash_cd_label.text = "Dash: READY" if cd <= 0.0 else "Dash CD: %.2fs" % cd


func set_parry_cd(cd: float) -> void:
	if parry_cd_label == null:
		return
	parry_cd_label.text = "Parry: READY" if cd <= 0.0 else "Parry CD: %.2fs" % cd


func set_enemy_freeze(on: bool) -> void:
	if freeze_label == null:
		return
	freeze_label.text = "ENEMY: FROZEN" if on else "ENEMY: ACTIVE"
