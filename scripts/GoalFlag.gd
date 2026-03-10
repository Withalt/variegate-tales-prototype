extends Area2D

signal reached

@export var player_layer_bit: int = 2

func _ready() -> void:
	monitoring = true
	monitorable = true

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	collision_mask = 1 << (player_layer_bit - 1)

func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		emit_signal("reached")
