extends Node

func _ready() -> void:
	# Tránh lỗi "Parent node is busy adding/removing children..."
	call_deferred("_go_level")

func _go_level() -> void:
	get_tree().change_scene_to_file("res://scenes/Level_Proto_01.tscn")
