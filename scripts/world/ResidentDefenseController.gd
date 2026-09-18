class_name ResidentDefenseController
extends Node

## Revealed residents become persistent, saved combat targets at terrain sites.
const WAVE_INTERVAL_SECONDS := 0.5
const GROUPS_PER_HEX := 32
const MIN_SPAWN_DISTANCE := 40.0
const ENGAGEMENT_RADIUS_METRES := HexCoord.SUB_HEX_CELL_SIZE_METERS
signal wave_resolved(hexes: int, condensed: int)

@export var unit_manager_path: NodePath
@export var combat_coordinator_path: NodePath
@export var infestation_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var fog_of_war_path: NodePath
@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath

var _unit_manager: UnitManager
var _infestation_manager: InfestationManager
var _horde_manager: HordeManager
var _fog: FogOfWarManager
var _map: HexGridMap
var _buildings: BuildingManager
var _elapsed := 0.0
var _navigation := LocalUnitNavigation.new()

func _ready() -> void:
	_unit_manager = get_node_or_null(unit_manager_path) as UnitManager
	_infestation_manager = get_node_or_null(infestation_manager_path) as InfestationManager
	_horde_manager = get_node_or_null(horde_manager_path) as HordeManager
	_fog = get_node_or_null(fog_of_war_path) as FogOfWarManager
	_map = get_node_or_null(hex_grid_map_path) as HexGridMap
	_buildings = get_node_or_null(building_manager_path) as BuildingManager
	_navigation.setup(_map, _buildings, null)
	if _fog:
		_fog.fog_state_changed.connect(func(coord: Vector2i, state: GameEnums.FogState) -> void:
			if state == GameEnums.FogState.VISIBLE:
				materialize_hex(coord))
	call_deferred("run_wave_tick")

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= WAVE_INTERVAL_SECONDS:
		_elapsed = 0.0
		run_wave_tick()

func run_wave_tick() -> void:
	var coords: Dictionary = {}
	if _fog:
		for coord in _fog.get_explored_hexes():
			if _fog.is_visible(coord):
				coords[coord] = true
	if _unit_manager:
		for unit in _unit_manager.get_all_units():
			if not unit.is_destroyed():
				coords[unit.hex_coord] = true
	var moved := 0
	for coord in coords:
		moved += materialize_hex(coord)
	wave_resolved.emit(coords.size(), moved)

func materialize_hex(coord: Vector2i) -> int:
	if not _infestation_manager or not _horde_manager:
		return 0
	var count := _infestation_manager.resident_count_at(coord)
	if count <= 0:
		return 0
	var sites := PackedVector2Array()
	var center := HexCoord.axial_to_world(coord)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coord) & 0x7fffffff
	for i in GROUPS_PER_HEX * 8:
		var offset := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(70.0, HexCoord.HEX_SIZE * 0.72)
		var world := center + offset
		if not _navigation.is_ground_passable(world) or not _site_is_clear(world):
			continue
		sites.append(offset)
		if sites.size() >= mini(count, GROUPS_PER_HEX):
			break
	if sites.is_empty():
		return 0
	var moved := 0
	for i in sites.size():
		var take := count / sites.size() + (1 if i < count % sites.size() else 0)
		moved += _infestation_manager.condense_defenders(coord, take, sites[i], -1, HordeManager.wall_contact_frontage(frontage_for(count)))
	return moved

func _site_is_clear(world: Vector2) -> bool:
	if _unit_manager:
		for unit in _unit_manager.get_all_units():
			if world.distance_to(HexCoord.axial_to_world(unit.hex_coord) + unit.local_position) < MIN_SPAWN_DISTANCE:
				return false
	if _buildings:
		for building in _buildings.get_buildings_at(HexCoord.world_to_axial(world)):
			if world.distance_to(HexCoord.axial_to_world(building.hex_coord) + building.local_position) < ObstacleRadii.BUILDING_RADIUS:
				return false
	return true

## Retained for population-density diagnostics; runtime uses persistent groups.
static func frontage_for(residents: int) -> int:
	if residents <= 0:
		return 0
	var density := float(residents) / HexCoord.hex_area_square_metres()
	return clampi(roundi(density * PI * ENGAGEMENT_RADIUS_METRES * ENGAGEMENT_RADIUS_METRES), 1, residents)

func reinforce(coord: Vector2i) -> int:
	if not _infestation_manager or not _horde_manager:
		return 0
	var shortfall := frontage_for(_infestation_manager.resident_count_at(coord)) - _horde_manager.get_zombie_count_at(coord)
	return _infestation_manager.condense_defenders(coord, shortfall)

func reinforce_near(instance: UnitInstance) -> int:
	return materialize_hex(instance.hex_coord)
