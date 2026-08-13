class_name District
extends Resource

## A single sub-partition of a HexCell ("District & Frontline Partitioning"
## — design doc). A hex can hold several of these at once — e.g. a
## settlement hex is Urban Center + Industrial Estate (safe) plus a fringe of
## Uncleared Wilderness (contested) — enabling active combat in one part of a
## hex while the rest keeps harvesting/building undisturbed.

@export var type: GameEnums.DistrictType = GameEnums.DistrictType.UNCLEARED_WILDERNESS
@export var is_contested: bool = true  ## true = zombies active here; false = cleared/safe.

func _init(p_type: GameEnums.DistrictType = GameEnums.DistrictType.UNCLEARED_WILDERNESS, p_contested: bool = true) -> void:
	type = p_type
	is_contested = p_contested

func get_display_name() -> String:
	match type:
		GameEnums.DistrictType.URBAN_CENTER:
			return "Urban Center"
		GameEnums.DistrictType.INDUSTRIAL_ESTATE:
			return "Industrial Estate"
		GameEnums.DistrictType.UNCLEARED_WILDERNESS:
			return "Uncleared Wilderness"
		_:
			return "Unknown District"
