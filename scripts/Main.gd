extends Node

func _ready() -> void:
	call_deferred("_go_level")

func _go_level() -> void:
	get_tree().change_scene_to_file("res://scenes/Level_Proto_01.tscn")
