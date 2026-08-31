class_name BuildingInstance
extends Resource

## A single placed building: a reference to its BuildingDefinition template,
## the hex it occupies, an exact position within that hex (for the
## Tactical view; ZERO/hex-center by default when placed through the plain
## hex-coordinate API), and a unique id assigned by BuildingManager.

@export var definition: BuildingDefinition
@export var hex_coord: Vector2i = Vector2i.ZERO
@export var local_position: Vector2 = Vector2.ZERO  ## Offset from hex_coord's center; see BuildingManager.place_building_at_world().
@export var id: int = 0

## Housing occupancy — distinct from ResourceManager's global POPULATION
## capacity pool (design_doc.md §2, see CapacityAllocator). Fixed at
## definition.population_provided once construction/repair completes, zeroed
## on ruin (BuildingHealthController.damage()) or while still under
## construction; nothing mutates it day to day otherwise. Real per-instance
## state rather than just reading population_provided directly because ruin
## needs a "how many were housed here at the moment it fell" snapshot
## (HordeManager's ruin-to-casualties conversion) that survives past the
## instant the building's baseline stops applying.
@export var current_population: int = 0

## A destroyed building doesn't disappear — it becomes a Ruins state.
## Seeded from definition.get_max_hp() on placement, same -1-sentinel
## convention current_population uses. At 0, is_ruined flips true
## (BuildingHealthController.damage()) — the instance stays in
## BuildingManager's records (never removed) but stops producing/
## consuming/housing anything.
@export var current_hp: float = 0.0
@export var is_ruined: bool = false

## True from the moment BuildingManager.place_building() registers the
## instance (immediately, not at completion) until
## BuildingConstructionController.process_day() finishes counting down its
## build time. A real, selectable, demolishable instance the whole time;
## this flag is purely "is it still a construction site" for rendering/
## production purposes, not a gate on whether the instance exists at all.
@export var is_under_construction: bool = false

## design_doc.md §2.1's "Going dark": the player switched this building off.
## Stays true across the whole restart delay too — the countdown lives in
## BuildingPowerController, exactly as is_under_construction's lives in
## BuildingConstructionController, so "off" and "coming back up" are one flag
## plus a pending job rather than two states on the instance.
##
## Unlike ruin, this does NOT zero current_population: the occupants of a
## mothballed tenement still live there, so they keep eating
## (BuildingSustenanceController counts them regardless), keep counting
## toward Discontent (DiscontentManager._region_population()) and keep
## counting toward settlement size (SettlementFoundingController). Switching
## off suspends what the BUILDING draws and produces, not the people inside
## it. Without that, mothballing every tenement during a famine would erase
## the colony's whole Food demand.
@export var is_powered_down: bool = false

func _init(p_definition: BuildingDefinition = null, p_hex_coord: Vector2i = Vector2i.ZERO, p_id: int = 0, p_local_position: Vector2 = Vector2.ZERO, p_current_population: int = -1, p_current_hp: float = -1.0, p_is_ruined: bool = false, p_is_under_construction: bool = false, p_is_powered_down: bool = false) -> void:
	definition = p_definition
	hex_coord = p_hex_coord
	id = p_id
	local_position = p_local_position
	# -1 is "not specified by the caller" (BuildingManager's normal placement
	# path) — seed from the definition's baseline. A save-restore path passes
	# the actual saved value explicitly instead, which may be 0 rather than
	# the baseline if the saved building was ruined (see BuildingManager.load_save_entries()).
	current_population = p_current_population if p_current_population >= 0 else (p_definition.population_provided if p_definition else 0)
	current_hp = p_current_hp if p_current_hp >= 0.0 else (p_definition.get_max_hp() if p_definition else 0.0)
	is_ruined = p_is_ruined
	is_under_construction = p_is_under_construction
	is_powered_down = p_is_powered_down

func is_destroyed() -> bool:
	return current_hp <= 0.0

## Intact, finished, and switched on — the single "this building is
## operating" test, for the sites that gate a building's own production,
## upkeep, effects or services on it (BuildingSustenanceController,
## UnitManager's training lookup, TacticalHexView's smoke/fire/light,
## CombatCoordinator's Searchlight beam).
##
## Deliberately NOT used at every is_ruined site. Three of them want a
## narrower answer than one bool and say so at the call site instead:
## NoiseManager leaves a construction site loud (design_doc.md §6 rates
## Building Construction at 8 tiles) while gating only its lamp term on
## construction; FogOfWarManager reads all three flags and gives a different
## answer to each — a ruin sees nothing, a site sees its own hex, a
## switched-off building keeps its base radius and loses only the
## lit_at_night bonus; and BuildingManager.find_nearest_building() wants
## "standing" rather than "operating", because a switched-off Garrison is
## still somewhere to retreat to.
func is_running() -> bool:
	return not is_ruined and not is_under_construction and not is_powered_down

## `daily_output` scaled by the soil fertility under this building's REAL
## sub-hex footprint (hex_coord + local_position — Sub-Hex Mechanical Layer
## Phase 3, todo.md, [[sub-hex-mechanical-layer-epic]] memory:
## local_position stops being cosmetic-only here) when the definition opts
## in (see BuildingDefinition.soil_fertility_scales_output).
## SubHexSoilQuery.soil_fertility_at() falls back to `hex_cell`'s own
## macro-hex soil_fertility outside the baked corridor — `hex_cell` may be
## null (e.g. caller has no live HexGridMap reference yet), in which case
## POOR (the baseline daily_output is authored against) is assumed rather
## than skipping the scale entirely.
func get_effective_output(hex_cell: HexCell) -> Dictionary:
	var output: Dictionary = definition.daily_output.duplicate()
	if definition.soil_fertility_scales_output:
		var fallback := hex_cell.soil_fertility if hex_cell else GameEnums.SoilFertility.POOR
		var soil := SubHexSoilQuery.soil_fertility_at(hex_coord, local_position, fallback)
		var multiplier := _fertility_multiplier(soil)
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
