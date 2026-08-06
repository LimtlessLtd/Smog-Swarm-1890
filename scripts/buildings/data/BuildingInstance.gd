class_name BuildingInstance
extends Resource

## A single placed building: a reference to its BuildingDefinition template,
## the hex it occupies, an exact position within that hex (Phase 2.5 — for
## the Tactical view; ZERO/hex-center by default when placed through the
## plain hex-coordinate API), and a unique id assigned by BuildingManager.
## Deliberately thin — construction-site placeholder rendering and combat
## HP/damage state are later-phase concerns, not Phase 2's.

@export var definition: BuildingDefinition
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var local_position: Vector2 = Vector2.ZERO  ## Offset from hex_coord's center; see BuildingManager.place_building_at_world().
@export var id: int = 0

func _init(p_definition: BuildingDefinition = null, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_local_position: Vector2 = Vector2.ZERO) -> void:
	definition = p_definition
	hex_coord = p_hex_coord
	id = p_id
	local_position = p_local_position

## `daily_output` scaled by the occupied hex's soil fertility when the
## definition opts in (see BuildingDefinition.soil_fertility_scales_output).
## `hex_cell` may be null (e.g. caller has no live HexGridMap reference yet);
## output is returned unscaled in that case.
func get_effective_output(hex_cell: HexCell) -> Dictionary:
	var output: Dictionary = definition.daily_output.duplicate()
	if definition.soil_fertility_scales_output and hex_cell:
		var multiplier := _fertility_multiplier(hex_cell.soil_fertility)
		for resource_type in output:
			output[resource_type] = float(output[resource_type]) * multiplier
	return output

## POOR is the baseline (1.0) that BuildingDefinition.daily_output values are
## authored against; LUSH doubles yield, DESOLATE halves it, and NOT_ARABLE
## (open water, urban ground) yields nothing at all.
func _fertility_multiplier(soil: GameEnums.SoilFertility) -> float:
	match soil:
		GameEnums.SoilFertility.LUSH:
			return 2.0
		GameEnums.SoilFertility.POOR:
			return 1.0
		GameEnums.SoilFertility.DESOLATE:
			return 0.5
		_:
			return 0.0
