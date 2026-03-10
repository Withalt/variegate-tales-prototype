extends Area2D

@export var kill_instant: bool = true
@export var damage: int = 999999

# Theo project bạn:
# Player = layer 2, Enemy = layer 3
@export var player_layer_bit: int = 2
@export var enemy_layer_bit: int = 3

# Nếu muốn chỉ giết player hoặc chỉ giết enemy thì tắt cái tương ứng
@export var affect_player: bool = true
@export var affect_enemy: bool = true

func _ready() -> void:
	monitoring = true
	monitorable = true

	# Auto-connect để khỏi quên connect trong editor
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	# Mask bắt đúng layer của player + enemy
	var mask := 0
	if affect_player:
		mask |= (1 << (player_layer_bit - 1))
	if affect_enemy:
		mask |= (1 << (enemy_layer_bit - 1))
	collision_mask = mask

	# Debug để bạn xác nhận
	print("[KillZone] ready name=", name,
		" mask=", collision_mask,
		" (player_bit=", player_layer_bit, " enemy_bit=", enemy_layer_bit, ")")

func _on_body_entered(body: Node) -> void:
	if body == null:
		return

	# Ưu tiên filter bằng group (bền), fallback bằng layer
	var is_player := body.is_in_group("player")
	var is_enemy := body.is_in_group("enemies") or body.is_in_group("enemy") or body.is_in_group("enemies_group")

	# Nếu bạn chưa set group cho enemy, vẫn có thể xử lý bằng method
	# Nhưng tốt nhất: enemy đã add_to_group("enemies") trong Enemy.gd (bạn đang có).

	if is_player and affect_player:
		_kill_or_damage(body)
		return

	if is_enemy and affect_enemy:
		_kill_or_damage(body)
		return

func _kill_or_damage(body: Node) -> void:
	# Kill ưu tiên (bypass guard/parry)
	if kill_instant:
		if body.has_method("kill"):
			body.call("kill")
			return
		if body.has_method("die"):
			body.call("die")
			return
		# fallback: damage cực lớn
	if body.has_method("take_damage"):
		body.call("take_damage", damage)
	elif body.has_method("receive_attack"):
		# nếu object dùng hệ receive_attack
		body.call("receive_attack", damage, global_position)
	elif body.has_method("kill"):
		body.call("kill")
