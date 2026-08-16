class_name BuildingManager
extends Node

## Owns the registry of every placed BuildingInstance: which exist, where,
## and validation against terrain (HexGridMap) and cost (ResourceManager).
## The building *tree* itself (what each type costs/needs/produces) lives in
## BuildingCatalog. Construction/repair queueing, damage/ruin/demolish, and
## the daily Food/population tally are each owned by a dedicated collaborator
## (BuildingConstructionController, BuildingHealthController,
## BuildingSustenanceController) composed below — this class validates,
## mutates the registry, and relays their signals under its own existing
## names so every external caller/listener is unaffected by the split. See
## todo.md's "Technical Debt" section for why the split happened.
##
## Deliberately does not gate placement on district/Zone-of-Control state:
## the baseline district data marks every hex's wilderness fringe as
## permanently contested (HexCell.is_frontier), including settlements', so
## gating placement on "hex is fully secure" would make every rural
## Agriculture/Industry building unplaceable anywhere from day one.
## LogisticsNetwork instead tracks ZoC *coverage* as queryable data for other
## systems (walls, sieges) to gate against.

signal building_placed(instance: BuildingInstance)
signal building_removed(instance: BuildingInstance)
signal placement_rejected(building_type: GameEnums.BuildingType, coord: Vector2i, reason: String)
## Fires the moment a validated, paid-for placement is queued. building_placed
## (above) fires at the same moment now too (see place_building()) — every
## OTHER building_placed listener that means "operational" additionally
## checks is_under_construction and waits for building_construction_completed.
signal construction_started(building_type: GameEnums.BuildingType, coord: Vector2i, days: int)
signal construction_progressed(coord: Vector2i, days_remaining: int)
signal building_construction_completed(instance: BuildingInstance)
signal repair_started(instance: BuildingInstance, days: int)
signal building_damaged(instance: BuildingInstance, amount: float)
signal building_repaired(instance: BuildingInstance)
signal repair_rejected(instance: BuildingInstance, reason: String)
signal building_ruined(instance: BuildingInstance, lost_population: int)
signal building_demolished(instance: BuildingInstance)
signal food_satisfaction_changed(ratio: float)

## Re-exported for external callers (DiscontentManager, UnitPanelView) —
## BuildingSustenanceController owns the value.
const FOOD_PER_POPULATION := BuildingSustenanceController.FOOD_PER_POPULATION
const FOOD_STARVATION_RATIO := BuildingSustenanceController.FOOD_STARVATION_RATIO

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
@export var discontent_manager_path: NodePath  ## Optional — unset skips DiscontentManager.get_production_multiplier() entirely.
@export var territory_controller_path: NodePath  ## Optional — unset means repair_building()/demolish_building() never check territory state.
@export var tech_manager_path: NodePath  ## Optional — unset means get_placement_error() never checks BuildingDefinition.tier, so every building tier is placeable regardless of research.

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _discontent_manager: DiscontentManager
var _territory_controller: TerritoryController
var _tech_manager: TechManager

var _construction: BuildingConstructionController
var _health: BuildingHealthController
var _sustenance: BuildingSustenanceController
var _capacity: CapacityAllocator

var _instances: Array[BuildingInstance] = []
var _instances_by_hex: Dictionary = {}  # Vector2i -> Array[BuildingInstance]
var _next_id: int = 1
## Set by seed_starting_buildings(); exposed via get_starting_settlement_hexes()
## for WallManager.seed_starting_defenses().
var _starting_settlement_hexes: Array[Vector2i] = []

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if discontent_manager_path != NodePath():
		_discontent_manager = get_node(discontent_manager_path)
	if territory_controller_path != NodePath():
		_territory_controller = get_node(territory_controller_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)

	_capacity = CapacityAllocator.new(_resource_manager)

	_construction = BuildingConstructionController.new()
	_construction.progressed.connect(func(coord: Vector2i, days: int) -> void: construction_progressed.emit(coord, days))
	_construction.completed.connect(func(instance: BuildingInstance) -> void: building_construction_completed.emit(instance))

	_health = BuildingHealthController.new(_resource_manager, _territory_controller, _capacity, Callable(_construction, "days_for"))
	_health.damaged.connect(func(instance: BuildingInstance, amount: float) -> void: building_damaged.emit(instance, amount))
	_health.ruined.connect(func(instance: BuildingInstance, lost_population: int) -> void: building_ruined.emit(instance, lost_population))
	_health.repair_started.connect(func(instance: BuildingInstance, days: int) -> void: repair_started.emit(instance, days))
	_health.repair_rejected.connect(func(instance: BuildingInstance, reason: String) -> void: repair_rejected.emit(instance, reason))
	_health.repaired.connect(func(instance: BuildingInstance) -> void: building_repaired.emit(instance))
	_health.demolished.connect(func(instance: BuildingInstance) -> void: building_demolished.emit(instance))

	_sustenance = BuildingSustenanceController.new(_resource_manager, _discontent_manager, _hex_grid_map)
	_sustenance.food_satisfaction_changed.connect(func(ratio: float) -> void: food_satisfaction_changed.emit(ratio))

	TickManager.day_completed.connect(_on_day_completed)
	seed_starting_buildings()

## Manchester is the canonical starting point, matched by name (set from
## BritishGeographyData's GeographyFeature, see HexMapGenerator) rather than a
## hardcoded coordinate, so this doesn't need to know Manchester's specific
## hex layout. Falls back to any qualifying settlement hex otherwise.
const _STARTING_REGION_NAME := "Manchester"

## Offsets the free starting Lumber Yard so it doesn't render on top of the
## Town Hall at Tactical zoom — same hex, nudged off-center.
const _STARTING_LUMBER_YARD_OFFSET := Vector2(150.0, -100.0)

const _STARTING_FARM_SEARCH_RADIUS: int = 6
const _NO_FARM_HEX := Vector2i(-1, -1)

## Searches outward ring-by-ring (HexCoord.hex_disk() is cumulative) up to
## _STARTING_FARM_SEARCH_RADIUS for the nearest hex SMALLHOLDING_FARM can
## legally occupy (Town Hall's own hex is always URBAN, which a farm can't be
## placed on). Among a ring's candidates, prefers higher soil_fertility, then
## distance as a tiebreak. Returns _NO_FARM_HEX if nothing qualifies in range.
func _find_starting_farm_hex(from: Vector2i) -> Vector2i:
	var farm_definition := BuildingCatalog.get_definition(GameEnums.BuildingType.SMALLHOLDING_FARM)
	if not farm_definition:
		return _NO_FARM_HEX
	var seen: Dictionary = {}  # Vector2i -> true
	for radius in range(1, _STARTING_FARM_SEARCH_RADIUS + 1):
		var candidates: Array[Vector2i] = []
		for coord in HexCoord.hex_disk(from, radius):
			if coord == from or seen.has(coord):
				continue
			seen[coord] = true
			var cell := _hex_grid_map.get_cell(coord)
			if not cell or not cell.is_passable():
				continue
			if not farm_definition.allowed_biomes.has(cell.biome_type):
				continue
			if not farm_definition.allowed_soil_fertility.is_empty() and not farm_definition.allowed_soil_fertility.has(cell.soil_fertility):
				continue
			candidates.append(coord)
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var fa := _hex_grid_map.get_cell(a).soil_fertility
			var fb := _hex_grid_map.get_cell(b).soil_fertility
			if fa != fb:
				return fa < fb  ## Lower GameEnums.SoilFertility value == better (LUSH=0).
			return HexCoord.distance(from, a) < HexCoord.distance(from, b))
		return candidates[0]
	return _NO_FARM_HEX

## Seeds the colony with its first buildings on a fresh start. Without this,
## Fog of War leaves the entire map UNSEEN at boot (no vision source
## anywhere). Placed for free via _register_instance() directly, bypassing
## place_building()'s cost/validation, same as load_save_entries() does.
## A load right after boot clears every existing instance before restoring
## saved ones, so a seeded Town Hall never lingers once a real save loads.
func seed_starting_buildings() -> void:
	if not _instances.is_empty() or not _hex_grid_map:
		return
	var target: HexCell = null
	var fallback: HexCell = null
	for cell in _hex_grid_map.get_all_cells():
		if not (cell.is_settlement and cell.biome_type == GameEnums.BiomeType.URBAN):
			continue
		if cell.region_name == _STARTING_REGION_NAME:
			target = cell
			break
		if not fallback:
			fallback = cell
	target = target if target else fallback
	if not target:
		return

	var town_hall := BuildingCatalog.get_definition(GameEnums.BuildingType.TOWN_HALL)
	_register_instance(town_hall, target.coord, _next_id, Vector2.ZERO, true)
	# Lumber Yard, not a Foundry — the pre-rework free starting building was
	# CAST_IRON_FOUNDRY, whose new Tier 2 equivalent (Iron Foundry) draws 100
	# Iron Ore/day, 25 Coal/day upkeep design_doc.md §3 gives it. Handing that
	# out for free at Tier 0, with no Iron Ore Mine/Coal Mine built yet to
	# feed it, would run both stockpiles negative from day one. Lumber Yard
	# has no upstream input (design_doc.md §3 Tier 0) — same "free, no
	# prerequisite" role TIMBER_CAMP played pre-rework.
	var lumber_yard := BuildingCatalog.get_definition(GameEnums.BuildingType.LUMBER_YARD)
	_register_instance(lumber_yard, target.coord, _next_id, _STARTING_LUMBER_YARD_OFFSET, true)

	# Deliberately just the one core hex, not a corridor out to the starting
	# Farm — WallManager.seed_starting_defenses() fences this hex only, so the
	# starting perimeter stays compact instead of a long sprawling wall.
	_starting_settlement_hexes = [target.coord]
	var farm_hex := _find_starting_farm_hex(target.coord)
	if farm_hex != _NO_FARM_HEX:
		var farm := BuildingCatalog.get_definition(GameEnums.BuildingType.SMALLHOLDING_FARM)
		_register_instance(farm, farm_hex, _next_id, Vector2.ZERO, true)

func get_starting_settlement_hexes() -> Array[Vector2i]:
	return _starting_settlement_hexes.duplicate()

func get_buildings_at(coord: Vector2i) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	result.assign(_instances_by_hex.get(coord, []))
	return result

func get_all_buildings() -> Array[BuildingInstance]:
	return _instances.duplicate()

## Nearest OPERATIONAL (not under construction, not ruined) building whose
## type is in `types`, by plain hex distance from `from`. Linear scan rather
## than HexCoord.hex_disk()'s outward-ring search — this project's building
## count (dozens, not thousands) makes "check them all, keep the closest"
## simpler and equally fast. Null if none exist.
func find_nearest_building(from: Vector2i, types: Array) -> BuildingInstance:
	var best: BuildingInstance = null
	var best_distance := -1
	for instance in _instances:
		if instance.is_under_construction or instance.is_ruined:
			continue
		if not types.has(instance.definition.building_type):
			continue
		var distance := HexCoord.distance(from, instance.hex_coord)
		if best == null or distance < best_distance:
			best = instance
			best_distance = distance
	return best

## Null if unwired or `coord` is off-map, same as HexGridMap.get_cell() itself.
func get_hex_cell(coord: Vector2i) -> HexCell:
	if not _hex_grid_map:
		return null
	return _hex_grid_map.get_cell(coord)

## The next id a freshly-placed building would get — SaveLoadManager restores
## this exactly on load instead of renumbering everything placed afterward.
func get_next_id() -> int:
	return _next_id

func get_buildings_with_zoc_role(role: GameEnums.ZoneOfControlType) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	for instance in _instances:
		if instance.definition.zoc_roles.has(role):
			result.append(instance)
	return result

## Returns "" if `building_type` can legally be built at `coord` right now, or
## a human-readable rejection reason otherwise. Exposed separately from
## place_building() so UI can preview legality without attempting (and
## signalling a rejection for) a real placement.
func get_placement_error(building_type: GameEnums.BuildingType, coord: Vector2i) -> String:
	var definition := BuildingCatalog.get_definition(building_type)
	if not definition:
		return "Unknown building type."
	if not _hex_grid_map:
		return "No hex grid map wired to BuildingManager."
	if _tech_manager and not _tech_manager.is_building_tier_unlocked(definition.tier):
		return "%s requires Tier %d research first." % [definition.display_name, definition.tier]
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
	if _resource_manager and not _resource_manager.can_afford(_capacity.cost(definition)):
		return "Not enough Energy/Population capacity to build %s." % definition.display_name
	return ""

## Resource-only affordability check, deliberately NOT terrain/settlement
## legality (get_placement_error()'s job) — BuildMenuView's card click fires
## before placement mode is armed, before the player has picked a hex.
## Returns "" when affordable (or no ResourceManager wired).
func get_affordability_error(building_type: GameEnums.BuildingType) -> String:
	var definition := BuildingCatalog.get_definition(building_type)
	if not definition or not _resource_manager:
		return ""
	var shortfalls := _resource_shortfalls(definition.construction_cost)
	shortfalls.append_array(_resource_shortfalls(_capacity.cost(definition)))
	if shortfalls.is_empty():
		return ""
	return "Need %s more to build %s." % [", ".join(shortfalls), definition.display_name]

func _resource_shortfalls(cost: Dictionary) -> Array[String]:
	var shortfalls: Array[String] = []
	for resource_type in cost:
		var needed := float(cost[resource_type])
		var have := _resource_manager.get_amount(resource_type)
		if have < needed:
			var missing := String.num(needed - have, 1).rstrip("0").rstrip(".")
			shortfalls.append("%s %s" % [missing, ResourceVisuals.display_name(resource_type)])
	return shortfalls

func can_place_building(building_type: GameEnums.BuildingType, coord: Vector2i) -> bool:
	return get_placement_error(building_type, coord).is_empty()

## `local_position` is an offset from the hex's own center (Tactical view
## placement); leave it ZERO for hex-granularity placement.
##
## Returns true once the placement is validated, paid for, and queued — NOT
## once it's actually standing. Resources/storage/Energy are spent
## immediately; construction completes _construction.days_for() days later
## via _on_day_completed()/BuildingConstructionController.process_day().
##
## The BuildingInstance is created and registered here immediately
## (is_under_construction = true) rather than only at construction
## completion — it's a fully real, selectable, demolishable instance from
## this moment on. building_placed fires here (from _register_instance());
## listeners that treat building_placed as "operational" (Fog of War vision,
## ZoC, production tallies) check is_under_construction and wait for
## building_construction_completed instead.
func place_building(building_type: GameEnums.BuildingType, coord: Vector2i, local_position: Vector2 = Vector2.ZERO) -> bool:
	var error := get_placement_error(building_type, coord)
	if not error.is_empty():
		placement_rejected.emit(building_type, coord, error)
		return false

	var definition := BuildingCatalog.get_definition(building_type)
	if _resource_manager:
		_resource_manager.spend(definition.construction_cost)
		for resource_type in definition.storage_bonus:
			_resource_manager.add_storage_cap(resource_type, float(definition.storage_bonus[resource_type]))
		_capacity.apply(definition)

	var days := _construction.days_for(definition)
	var instance := _register_instance(definition, coord, _next_id, local_position, true, -1, -1.0, false, true)
	_construction.queue(instance, days)
	construction_started.emit(building_type, coord, days)
	return true

## Shared instance-bookkeeping between a fresh place_building() (already
## validated/paid above) and load_save_entries() (restoring a building
## already paid for in a previous session, must not re-spend or re-validate).
## `advance_next_id` is false for the latter — restoration sets `_next_id`
## once from the save's own record instead of per-instance. `current_population`
## defaults to -1 ("not specified" — a fresh placement seeds from
## definition.population_provided, see BuildingInstance._init());
## load_save_entries() passes the actual saved value since population is
## zeroed on ruin (BuildingHealthController.damage()) and can't otherwise be
## re-derived from the definition's fixed population_provided baseline.
func _register_instance(definition: BuildingDefinition, coord: Vector2i, id: int, local_position: Vector2, advance_next_id: bool, current_population: int = -1, current_hp: float = -1.0, is_ruined: bool = false, is_under_construction: bool = false) -> BuildingInstance:
	var instance := BuildingInstance.new(definition, coord, id, local_position, current_population, current_hp, is_ruined, is_under_construction)
	if is_under_construction:
		instance.current_population = 0  ## No free population/housing capacity until construction finishes.
	if advance_next_id:
		_next_id = id + 1
	_instances.append(instance)
	if not _instances_by_hex.has(coord):
		_instances_by_hex[coord] = []
	_instances_by_hex[coord].append(instance)

	building_placed.emit(instance)
	return instance

## Resolves `world_pos` to a hex + local offset and places there.
func place_building_at_world(building_type: GameEnums.BuildingType, world_pos: Vector2) -> bool:
	if not _hex_grid_map:
		placement_rejected.emit(building_type, Vector2i.ZERO, "No hex grid map wired to BuildingManager.")
		return false
	var coord := _hex_grid_map.world_to_coord(world_pos)
	var local_position := world_pos - HexCoord.axial_to_world(coord)
	return place_building(building_type, coord, local_position)

func remove_building(instance: BuildingInstance) -> void:
	_instances.erase(instance)
	if _instances_by_hex.has(instance.hex_coord):
		_instances_by_hex[instance.hex_coord].erase(instance)
	_health.remove_pending(instance)
	_construction.remove(instance)
	building_removed.emit(instance)

func damage_building(instance: BuildingInstance, amount: float) -> void:
	_health.damage(instance, amount)

func get_repair_error(instance: BuildingInstance) -> String:
	return _health.get_repair_error(instance)

func can_repair_building(instance: BuildingInstance) -> bool:
	return _health.can_repair(instance)

func repair_building(instance: BuildingInstance) -> bool:
	return _health.repair(instance)

func get_demolish_error(instance: BuildingInstance) -> String:
	return _health.get_demolish_error(instance)

func can_demolish_building(instance: BuildingInstance) -> bool:
	return _health.can_demolish(instance)

func demolish_building(instance: BuildingInstance) -> bool:
	if not _health.demolish(instance):
		return false
	remove_building(instance)
	return true

## Read-only preview of today's projected upkeep/output at current
## building/population state, for the resource-bar tooltip.
func get_projected_daily_flow() -> Dictionary:
	return _sustenance.get_projected_daily_flow(_instances)

## Every placed instance reduced to its saveable footprint. Mid-construction
## instances round-trip too: days_remaining is read back out of
## BuildingConstructionController, matching whichever job (if any) currently
## references this instance.
func get_save_entries() -> Array[BuildingSaveEntry]:
	var result: Array[BuildingSaveEntry] = []
	for instance in _instances:
		var days_remaining := 0
		if instance.is_under_construction:
			days_remaining = _construction.days_remaining_for(instance)
		result.append(BuildingSaveEntry.new(instance.definition.building_type, instance.hex_coord, instance.id, instance.local_position, instance.current_population, instance.current_hp, instance.is_ruined, instance.is_under_construction, days_remaining))
	return result

## Restores placed instances from a save: clears whatever is currently
## placed, then recreates each entry via _register_instance() directly —
## bypassing place_building()'s cost/validation, since these buildings
## already exist and were already paid for. `next_id` is applied once at the
## end rather than derived per-instance. A mid-construction entry re-queues
## its own construction job (maxi(1, ...) guards against a corrupt/hand-edited
## 0-or-negative save value stalling forever).
func load_save_entries(entries: Array[BuildingSaveEntry], next_id: int) -> void:
	for instance in _instances.duplicate():
		remove_building(instance)
	for entry in entries:
		var definition := BuildingCatalog.get_definition(entry.building_type)
		if not definition:
			push_warning("BuildingManager: unknown building type %s in save data, skipping." % entry.building_type)
			continue
		var instance := _register_instance(definition, entry.hex_coord, entry.id, entry.local_position, false, entry.current_population, entry.current_hp, entry.is_ruined, entry.is_under_construction)
		if entry.is_under_construction:
			_construction.queue(instance, maxi(1, entry.construction_days_remaining))
	_next_id = next_id

## Runs before this day's Food/population tally so a construction/repair job
## finishing TODAY already counts toward it.
func _on_day_completed(_day_number: int) -> void:
	_construction.process_day()
	_health.process_day()
	_sustenance.apply_day(_instances)
