extends Node

const WorldLighting = preload("res://scripts/world/DayNightWorldLighting.gd")

var _failures: Array[String] = []

func _ready() -> void:
	var root := Node2D.new()
	add_child(root)
	var lighting := WorldLighting.new()
	lighting.world_root_path = NodePath("..")
	root.add_child(lighting)
	lighting.apply_phase(GameEnums.DayPhase.DAY)
	_check(root.modulate == WorldLighting.DAY_COLOR, "daylight did not restore the world color")
	lighting.apply_phase(GameEnums.DayPhase.NIGHT)
	_check(root.modulate == WorldLighting.NIGHT_COLOR, "nightfall did not darken the world color")
	_check(root.modulate.get_luminance() < WorldLighting.DAY_COLOR.get_luminance() * 0.5, "night lighting is not substantially darker than day")
	if _failures.is_empty():
		print("Day/night lighting check passed.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
