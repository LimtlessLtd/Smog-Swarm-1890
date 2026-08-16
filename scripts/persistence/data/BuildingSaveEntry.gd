class_name BuildingSaveEntry
extends Resource

## One placed building's saveable footprint —
## deliberately NOT a full BuildingInstance snapshot. building_type +
## hex_coord + local_position + id are persisted so BuildingManager can
## re-look-up the live BuildingDefinition from BuildingCatalog by type on
## load instead of saving (and potentially staling) a definition copy, per
## the design doc's explicit decision. current_population and
## current_hp/is_ruined are the exceptions saved alongside them — real
## per-instance state (zeroed on ruin, siege damage) that can't be
## re-derived from the definition's fixed population_provided/get_max_hp()
## baselines once play has moved it.

@export var building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var local_position: Vector2 = Vector2.ZERO
@export var id: int = 0
@export var current_population: int = 0
@export var current_hp: float = 0.0
@export var is_ruined: bool = false

## Bug fix: mid-construction buildings are now real, saveable BuildingInstances
## (see BuildingInstance.is_under_construction's own doc comment) — without
## these two fields, get_save_entries()/load_save_entries() would silently
## resurrect a half-built construction site as a fully finished building on
## load (it's already in BuildingManager._instances, so it was never covered
## by the old, documented "_pending_construction isn't saved" gap; that gap
## only ever meant the job vanished, not that the instance itself came back
## wrong). construction_days_remaining is meaningless (0) while
## is_under_construction is false.
@export var is_under_construction: bool = false
@export var construction_days_remaining: int = 0

func _init(p_building_type: GameEnums.BuildingType = GameEnums.BuildingType.TERRACED_TENEMENT, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_local_position: Vector2 = Vector2.ZERO, p_current_population: int = 0, p_current_hp: float = 0.0, p_is_ruined: bool = false, p_is_under_construction: bool = false, p_construction_days_remaining: int = 0) -> void:
	building_type = p_building_type
	hex_coord = p_hex_coord
	id = p_id
	local_position = p_local_position
	current_population = p_current_population
	current_hp = p_current_hp
	is_ruined = p_is_ruined
	is_under_construction = p_is_under_construction
	construction_days_remaining = p_construction_days_remaining
