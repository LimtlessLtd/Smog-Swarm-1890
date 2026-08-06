class_name BuildingManager
extends Node

## Runtime owner of every placed BuildingInstance (design doc Phase 2.1).
## Validates placement against terrain (HexGridMap) and cost (ResourceManager),
## then on each in-game day (TickManager) tallies every instance's upkeep and
## output and pushes the totals into ResourceManager. The building *tree*
## itself (what each type costs/needs/produces) lives in BuildingCatalog —
## this class only tracks which instances exist and where.
##
## Deliberately does not gate placement on district/Zone-of-Control state:
## Phase 1's baseline district data marks every hex's wilderness fringe as
## permanently contested (see HexCell.is_frontier), including settlements',
## so gating placement on "hex is fully secure" would make every rural
## Agriculture/Industry building unplaceable anywhere from day one. Zone of
## Control (Phase 2.3, LogisticsNetwork) instead tracks *coverage* as
## queryable data for later phases (walls, sieges) to gate against.

signal building_placed(instance: BuildingInstance)
signal building_removed(instance: BuildingInstance)
signal placement_rejected(building_type: GameEnums.BuildingType, coord: Vector2i, reason: String)

## Daily Food drained per unit of BuildingDefinition.population_provided,
## across every housing building — see design doc 2.2 "Food (population drain)".
const FOOD_PER_POPULATION: float = 0.1

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _instances: Array[BuildingInstance] = []
var _instances_by_hex: Dictionary = {}  # Vector2i -> Array[BuildingInstance]
var _next_id: int = 1

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	TickManager.day_completed.connect(_on_day_completed)

func get_buildings_at(coord: Vector2i) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	result.assign(_instances_by_hex.get(coord, []))
	return result

func get_all_buildings() -> Array[BuildingInstance]:
	return _instances.duplicate()

func get_buildings_with_zoc_role(role: GameEnums.ZoneOfControlType) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	for instance in _instances:
		if instance.definition.zoc_roles.has(role):
			result.append(instance)
	return result

## Returns "" if `building_type` can legally be built at `coord` right now,
## or a human-readable rejection reason otherwise. Exposed separately from
## place_building() so UI can preview legality (e.g. ghost-building tint)
## without attempting (and signalling a rejection for) a real placement.
func get_placement_error(building_type: GameEnums.BuildingType, coord: Vector2i) -> String:
	var definition := BuildingCatalog.get_definition(building_type)
	if not definition:
		return "Unknown building type."
	if not _hex_grid_map:
		return "No hex grid map wired to BuildingManager."
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return "%s is outside the map." % coord
	if not cell.is_passable():
		return "%s cannot be built on marsh or peat bog until it is drained." % definition.display_name
	if definition.requires_settlement and not cell.is_settlement:
		return "%s can only be built within a settlement." % definition.display_name
	if not definition.allowed_biomes.is_empty() and not definition.allowed_biomes.has(cell.biome_type):
		return "%s cannot be built on this terrain." % definition.display_name
	if not definition.allowed_soil_fertility.is_empty() and not definition.allowed_soil_fertility.has(cell.soil_fertility):
		return "%s needs better soil than this hex has." % definition.display_name
	if _resource_manager and not _resource_manager.can_afford(definition.construction_cost):
		return "Not enough resources to build %s." % definition.display_name
	return ""

func can_place_building(building_type: GameEnums.BuildingType, coord: Vector2i) -> bool:
	return get_placement_error(building_type, coord).is_empty()

func place_building(building_type: GameEnums.BuildingType, coord: Vector2i) -> BuildingInstance:
	var error := get_placement_error(building_type, coord)
	if not error.is_empty():
		placement_rejected.emit(building_type, coord, error)
		return null

	var definition := BuildingCatalog.get_definition(building_type)
	if _resource_manager:
		_resource_manager.spend(definition.construction_cost)
		for resource_type in definition.storage_bonus:
			_resource_manager.add_storage_cap(resource_type, float(definition.storage_bonus[resource_type]))

	var instance := BuildingInstance.new(definition, coord, _next_id)
	_next_id += 1
	_instances.append(instance)
	if not _instances_by_hex.has(coord):
		_instances_by_hex[coord] = []
	_instances_by_hex[coord].append(instance)

	building_placed.emit(instance)
	return instance

func remove_building(instance: BuildingInstance) -> void:
	_instances.erase(instance)
	if _instances_by_hex.has(instance.hex_coord):
		_instances_by_hex[instance.hex_coord].erase(instance)
	building_removed.emit(instance)

func _on_day_completed(_day_number: int) -> void:
	if not _resource_manager:
		return

	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	var total_population := 0

	for instance in _instances:
		var definition := instance.definition
		total_population += definition.population_provided

		for resource_type in definition.daily_upkeep:
			consumed[resource_type] = consumed.get(resource_type, 0.0) + float(definition.daily_upkeep[resource_type])

		var cell: HexCell = null
		if _hex_grid_map:
			cell = _hex_grid_map.get_cell(instance.hex_coord)
		var output := instance.get_effective_output(cell)
		for resource_type in output:
			produced[resource_type] = produced.get(resource_type, 0.0) + float(output[resource_type])

	if total_population > 0:
		var food := GameEnums.ResourceType.FOOD
		consumed[food] = consumed.get(food, 0.0) + total_population * FOOD_PER_POPULATION

	_resource_manager.apply_daily_flow(consumed, produced)
