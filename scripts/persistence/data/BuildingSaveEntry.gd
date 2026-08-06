class_name BuildingSaveEntry
extends Resource

## One placed building's saveable footprint (design doc Phase 2.8.1) —
## deliberately NOT a full BuildingInstance snapshot. Only building_type +
## hex_coord + local_position + id are persisted; BuildingManager re-looks-up
## the live BuildingDefinition from BuildingCatalog by type on load instead
## of saving (and potentially staling) a definition copy, per the design
## doc's explicit decision.

@export var building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var local_position: Vector2 = Vector2.ZERO
@export var id: int = 0

func _init(p_building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_local_position: Vector2 = Vector2.ZERO) -> void:
	building_type = p_building_type
	hex_coord = p_hex_coord
	id = p_id
	local_position = p_local_position
