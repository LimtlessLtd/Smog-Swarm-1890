class_name BuildingSaveEntry
extends Resource

## One placed building's saveable footprint (design doc Phase 2.8.1) —
## deliberately NOT a full BuildingInstance snapshot. building_type +
## hex_coord + local_position + id are persisted so BuildingManager can
## re-look-up the live BuildingDefinition from BuildingCatalog by type on
## load instead of saving (and potentially staling) a definition copy, per
## the design doc's explicit decision. current_population (Phase 2.10.1) is
## the one exception saved alongside them — genuinely mutable per-instance
## state (starvation deaths, surplus regrowth) that can't be re-derived from
## the definition's fixed population_provided baseline once play has moved it.

@export var building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var local_position: Vector2 = Vector2.ZERO
@export var id: int = 0
@export var current_population: int = 0

func _init(p_building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_local_position: Vector2 = Vector2.ZERO, p_current_population: int = 0) -> void:
	building_type = p_building_type
	hex_coord = p_hex_coord
	id = p_id
	local_position = p_local_position
	current_population = p_current_population
