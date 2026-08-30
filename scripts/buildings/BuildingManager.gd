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
##
## It DOES gate on design_doc.md §2.1's infestation band, which is a different
## quantity and not a re-litigation of the paragraph above: the band is a real
## per-hex zombie population ratio that starts at 0% on the player's own hex
## and is lowered by killing, where District.is_contested defaults to TRUE
## everywhere and never moves. Checked at placement only (D9) — a standing
## building is destroyed by zombies attacking it, never by the ratio crossing
## a threshold, or one horde wandering past would brick an industrial hex
## without a fight.

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
## design_doc.md §2.1's "Going dark" (BuildingPowerController). Every listener
## that already recomputes a derived field off building_placed/removed/ruined
## — NoiseManager's aura, FogOfWarManager's vision — must listen to these two
## as well, or a switched-off building keeps emitting whatever it was emitting
## until something unrelated happens to touch the same field.
signal building_powered_down(instance: BuildingInstance)
signal building_powered_up(instance: BuildingInstance)
signal building_restart_started(instance: BuildingInstance, days: int)
signal building_restart_cancelled(instance: BuildingInstance)
signal building_restart_rejected(instance: BuildingInstance, reason: String)
signal power_down_rejected(instance: BuildingInstance, reason: String)
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
@export var infestation_manager_path: NodePath  ## Optional — unset means get_placement_error() never checks design_doc.md §2.1's band, so every hex is treated as Cleared.

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _discontent_manager: DiscontentManager
var _territory_controller: TerritoryController
var _tech_manager: TechManager
var _infestation_manager: InfestationManager

var _construction: BuildingConstructionController
var _health: BuildingHealthController
var _power: BuildingPowerController
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
	# get_node_or_null, not get_node: InfestationManager is a LATER Main.tscn
	# sibling than this one (it seeds its worldgen rings from the settlement
	# seed_starting_buildings() puts down below), so the node exists in the
	# tree by now but its own _ready() has not run. Resolving the reference is
	# safe; calling into it here would not be, and nothing does.
	if infestation_manager_path != NodePath():
		_infestation_manager = get_node_or_null(infestation_manager_path) as InfestationManager

	_capacity = CapacityAllocator.new(_resource_manager)

	_construction = BuildingConstructionController.new()
	_construction.progressed.connect(func(coord: Vector2i, days: int) -> void: construction_progressed.emit(coord, days))
	_construction.completed.connect(func(instance: BuildingInstance) -> void: building_construction_completed.emit(instance))

	_health = BuildingHealthController.new(_resource_manager, _territory_controller, _capacity, Callable(_construction, "days_for"))
	_health.damaged.connect(func(instance: BuildingInstance, amount: float) -> void: building_damaged.emit(instance, amount))
	# Not a bare relay, unlike its siblings: BuildingPowerController.on_ruined()
	# reconciles the going-dark state BEFORE the ruin is announced, so no
	# listener ever observes a ruin that is also flagged switched-off. _power is
	# constructed below, and this lambda only runs at ruin time, so the
	# ordering is safe.
	_health.ruined.connect(func(instance: BuildingInstance, lost_population: int) -> void:
		_power.on_ruined(instance)
		building_ruined.emit(instance, lost_population))
	_health.repair_started.connect(func(instance: BuildingInstance, days: int) -> void: repair_started.emit(instance, days))
	_health.repair_rejected.connect(func(instance: BuildingInstance, reason: String) -> void: repair_rejected.emit(instance, reason))
	_health.repaired.connect(func(instance: BuildingInstance) -> void: building_repaired.emit(instance))
	_health.demolished.connect(func(instance: BuildingInstance) -> void: building_demolished.emit(instance))

	_power = BuildingPowerController.new(_capacity)
	_power.powered_down.connect(func(instance: BuildingInstance) -> void: building_powered_down.emit(instance))
	_power.power_down_rejected.connect(func(instance: BuildingInstance, reason: String) -> void: power_down_rejected.emit(instance, reason))
	_power.restart_started.connect(func(instance: BuildingInstance, days: int) -> void: building_restart_started.emit(instance, days))
	_power.restart_rejected.connect(func(instance: BuildingInstance, reason: String) -> void: building_restart_rejected.emit(instance, reason))
	_power.restart_cancelled.connect(func(instance: BuildingInstance) -> void: building_restart_cancelled.emit(instance))
	_power.powered_up.connect(func(instance: BuildingInstance) -> void: building_powered_up.emit(instance))

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

## Sub-hex offsets (world units from the Town Hall's own hex centre) the
## starting farm is looked for at, before falling back to a whole different
## hex. "Move the Manchester starting farm to a valid biome within the hex
## tile that the starting manchester town hall exists in" (user report): the
## old search only ever considered NEIGHBOURING HEXES, because a settlement
## hex is URBAN and a farm cannot stand on URBAN — but that is a MACRO-hex
## fact, and a real ~25-square-mile hex around Manchester is not urban all
## the way across. The sub-hex layer can answer where the green ground
## inside it actually is, so the farm lands in the player's own starting hex
## instead of somewhere across the map with no vision of it.
##
## Rings, nearest first, so the farm sits close to the Town Hall without
## being drawn on top of it. The inner radius clears the Town Hall and the
## free Lumber Yard (_STARTING_LUMBER_YARD_OFFSET, ~180 units out); the
## outer stays inside the hex's own inradius (HEX_SIZE * sqrt(3)/2 ~ 443) so
## every candidate is genuinely within this hex rather than over its edge.
const _STARTING_FARM_RING_RADII: Array[float] = [220.0, 280.0, 340.0, 400.0]
const _STARTING_FARM_RING_SAMPLES: int = 24

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

## Nearest sub-hex offset within `coord` itself that a Smallholding Farm can
## legally occupy, or null if the hex has no legal green ground at all (a
## genuinely wall-to-wall built-up hex, or no baked sub-hex data there —
## SubHexTerrainQuery falls back to the macro biome, which for a settlement
## hex is URBAN, and the search correctly finds nothing).
##
## Ranks by soil within a ring before moving outward, the same "better soil
## first, then distance" preference _find_starting_farm_hex() applies across
## hexes — one rule, two granularities.
func _find_starting_farm_offset(coord: Vector2i) -> Variant:
	var definition := BuildingCatalog.get_definition(GameEnums.BuildingType.SMALLHOLDING_FARM)
	if not definition or not _hex_grid_map:
		return null
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return null
	for radius in _STARTING_FARM_RING_RADII:
		var best: Variant = null
		var best_soil := GameEnums.SoilFertility.NOT_ARABLE
		for i in range(_STARTING_FARM_RING_SAMPLES):
			var angle := TAU * float(i) / float(_STARTING_FARM_RING_SAMPLES)
			var offset := Vector2(cos(angle), sin(angle)) * radius
			if not get_terrain_placement_error(definition, coord, offset).is_empty():
				continue
			var soil := SubHexSoilQuery.soil_fertility_at(coord, offset, cell.soil_fertility)
			if best == null or soil < best_soil:  ## Lower GameEnums.SoilFertility value == better (LUSH=0).
				best = offset
				best_soil = soil
		if best != null:
			return best
	return null

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
	var farm := BuildingCatalog.get_definition(GameEnums.BuildingType.SMALLHOLDING_FARM)
	# Inside the Town Hall's own hex where the sub-hex layer can find legal
	# ground for it; only if it genuinely cannot does this fall back to the
	# old outward hex-by-hex search, which puts the farm outside the starting
	# perimeter and often outside vision entirely.
	var farm_offset: Variant = _find_starting_farm_offset(target.coord)
	if farm_offset != null:
		_register_instance(farm, target.coord, _next_id, farm_offset, true)
		return
	var farm_hex := _find_starting_farm_hex(target.coord)
	if farm_hex != _NO_FARM_HEX:
		_register_instance(farm, farm_hex, _next_id, Vector2.ZERO, true)

func get_starting_settlement_hexes() -> Array[Vector2i]:
	return _starting_settlement_hexes.duplicate()

func get_buildings_at(coord: Vector2i) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	result.assign(_instances_by_hex.get(coord, []))
	return result

func get_all_buildings() -> Array[BuildingInstance]:
	return _instances.duplicate()

## Nearest STANDING (not under construction, not ruined) building whose type
## is in `types`, by plain hex distance from `from`. A switched-off building
## still counts: its only caller is UnitOrderController's retreat target, and
## a dark Garrison is still somewhere to fall back to — going dark is about
## what a building emits and produces, not about whether it is there.
## Linear scan rather
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

## Returns "" if `building_type` can legally be built at `coord` (at exactly
## `local_position` within it — the offset from the hex's own center,
## defaulting to ZERO/the hex center) right now, or a human-readable
## rejection reason otherwise. Exposed separately from place_building() so
## UI can preview legality without attempting (and signalling a rejection
## for) a real placement.
##
## Passability/biome/soil-fertility are resolved at real sub-hex resolution
## under `local_position` (SubHexTerrainQuery/SubHexSoilQuery — Sub-Hex
## Mechanical Layer Phase 3b, todo.md, [[sub-hex-mechanical-layer-epic]]
## memory: local_position stops being cosmetic-only for placement legality
## too, matching Phase 3a's extraction-side change) rather than the macro
## hex's own aggregate values — a building could otherwise be legally
## placed on a marsh strip or non-arable patch that happens to sit inside
## an overall-passable/-farmland hex. Falls back to the macro hex's own
## `cell` fields outside the baked corridor, same "empty result -> fall
## back to flat default" contract every class in this epic already follows,
## so a caller passing the default ZERO local_position on an off-corridor
## hex behaves exactly as before this phase.
func get_placement_error(building_type: GameEnums.BuildingType, coord: Vector2i, local_position: Vector2 = Vector2.ZERO) -> String:
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
	var terrain_error := get_terrain_placement_error(definition, coord, local_position)
	if not terrain_error.is_empty():
		return terrain_error
	var infestation_error := get_infestation_placement_error(definition, coord)
	if not infestation_error.is_empty():
		return infestation_error
	if definition.max_per_hex > 0 and _count_at(building_type, coord) >= definition.max_per_hex:
		return "%s is limited to %d per hex." % [definition.display_name, definition.max_per_hex]
	if _resource_manager and not _resource_manager.can_afford(definition.construction_cost):
		return "Not enough resources to build %s." % definition.display_name
	if _resource_manager and not _resource_manager.can_afford(_capacity.cost(definition)):
		return "Not enough Energy/Population capacity to build %s." % definition.display_name
	return ""

## The purely GEOGRAPHIC half of get_placement_error(): can this building
## stand on this exact spot, ignoring what it costs, what's researched, and
## what's already there. Split out because seed_starting_buildings() places
## for free before the player has any resources or research, so it needs
## terrain legality without the affordability/tier clauses — and asking the
## same question through a second, hand-copied set of checks is how a seeded
## building ends up somewhere the player could never have built one.
##
## Every clause is resolved at SUB-HEX resolution (SubHexTerrainQuery /
## SubHexSoilQuery, Sub-Hex Mechanical Layer Phase 3b) against the exact
## world position, not the macro hex's single majority-voted value: a farm
## can legally stand on a green patch inside an otherwise URBAN hex, and
## cannot stand on a marsh inside an otherwise buildable one.
func get_terrain_placement_error(definition: BuildingDefinition, coord: Vector2i, local_position: Vector2) -> String:
	var cell := _hex_grid_map.get_cell(coord) if _hex_grid_map else null
	if not cell:
		return "%s is outside the map." % coord
	var world_pos := HexCoord.axial_to_world(coord) + local_position
	if not SubHexTerrainQuery.is_passable_at(coord, world_pos, cell.is_passable()):
		return "%s cannot be built on marsh or peat bog until it is drained." % definition.display_name
	if definition.requires_settlement and not cell.is_settlement:
		return "%s can only be built within a settlement." % definition.display_name
	if not definition.allowed_biomes.is_empty() and not definition.allowed_biomes.has(SubHexTerrainQuery.biome_at(coord, world_pos, cell.biome_type)):
		return "%s cannot be built on this terrain." % definition.display_name
	if not definition.allowed_soil_fertility.is_empty() and not definition.allowed_soil_fertility.has(SubHexSoilQuery.soil_fertility_at(coord, local_position, cell.soil_fertility)):
		return "%s needs better soil than this hex has." % definition.display_name
	return ""

## design_doc.md §2.1's Build Rights column, split out from
## get_placement_error() for the same reason get_terrain_placement_error() is:
## one question, askable on its own, rather than a clause a second caller has
## to hand-copy.
##
##   Cleared (< 5%)      unrestricted
##   Fringe (5-25%)      Defensive Tier only (BuildingDefinition.is_defensive)
##   Contested (25.1-75) nothing
##   Hive Core (75-100)  nothing
##
## Returns "" when the hex allows this building, and "" unconditionally when no
## InfestationManager is wired — a fixture or a scene without one treats every
## hex as Cleared rather than as unbuildable.
##
## Unlike get_terrain_placement_error()'s clauses this is a MACRO-hex question
## by specification (design_doc.md §2.1: "Each 5-mile strategic hex carries one
## mutable number and one static capacity"), so the two granularities meet
## inside get_placement_error() on purpose. It is not the CLAUDE.md §3
## flattening anti-pattern.
func get_infestation_placement_error(definition: BuildingDefinition, coord: Vector2i) -> String:
	if not _infestation_manager:
		return ""
	var band := _infestation_manager.band_at(coord)
	if band == GameEnums.InfestationBand.CLEARED:
		return ""
	var percent := _infestation_manager.infestation_at(coord)
	if band == GameEnums.InfestationBand.FRINGE:
		if definition.is_defensive:
			return ""
		return "%s cannot be built at %.0f%% infestation — only defensive structures until this hex is cleared." % [definition.display_name, percent]
	return "%s cannot be built at %.0f%% infestation — clear the zombies out first." % [definition.display_name, percent]

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

## Counts every instance of `building_type` on `coord`, including ruined and
## still-under-construction ones — a ruin occupies its plot until demolished,
## and two queued Town Halls racing to finish on the same hex would break
## max_per_hex the moment both completed.
func _count_at(building_type: GameEnums.BuildingType, coord: Vector2i) -> int:
	var count := 0
	for instance in _instances_by_hex.get(coord, []):
		if instance.definition.building_type == building_type:
			count += 1
	return count

func _resource_shortfalls(cost: Dictionary) -> Array[String]:
	var shortfalls: Array[String] = []
	for resource_type in cost:
		var needed := float(cost[resource_type])
		var have := _resource_manager.get_amount(resource_type)
		if have < needed:
			var missing := String.num(needed - have, 1).rstrip("0").rstrip(".")
			shortfalls.append("%s %s" % [missing, ResourceVisuals.display_name(resource_type)])
	return shortfalls

func can_place_building(building_type: GameEnums.BuildingType, coord: Vector2i, local_position: Vector2 = Vector2.ZERO) -> bool:
	return get_placement_error(building_type, coord, local_position).is_empty()

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
	var error := get_placement_error(building_type, coord, local_position)
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
func _register_instance(definition: BuildingDefinition, coord: Vector2i, id: int, local_position: Vector2, advance_next_id: bool, current_population: int = -1, current_hp: float = -1.0, is_ruined: bool = false, is_under_construction: bool = false, is_powered_down: bool = false) -> BuildingInstance:
	var instance := BuildingInstance.new(definition, coord, id, local_position, current_population, current_hp, is_ruined, is_under_construction, is_powered_down)
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
	_power.remove_pending(instance)
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

func get_power_down_error(instance: BuildingInstance) -> String:
	return _power.get_power_down_error(instance)

func can_power_down_building(instance: BuildingInstance) -> bool:
	return _power.can_power_down(instance)

func power_down_building(instance: BuildingInstance) -> bool:
	return _power.power_down(instance)

func get_restart_error(instance: BuildingInstance) -> String:
	return _power.get_restart_error(instance)

func can_restart_building(instance: BuildingInstance) -> bool:
	return _power.can_restart(instance)

func restart_building(instance: BuildingInstance) -> bool:
	return _power.restart(instance)

## 0 when `instance` is not restarting — either running, or switched off and
## staying off. See BuildingPowerController.days_remaining_for().
func get_restart_days_remaining(instance: BuildingInstance) -> int:
	return _power.days_remaining_for(instance)

## Off AND already coming back up, as opposed to off and staying off — the
## two states BuildingInstance.is_powered_down alone cannot tell apart.
func is_building_restarting(instance: BuildingInstance) -> bool:
	return _power.is_restarting(instance)

func get_restart_days_for(definition: BuildingDefinition) -> int:
	return _power.restart_days_for(definition)

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
		result.append(BuildingSaveEntry.new(instance.definition.building_type, instance.hex_coord, instance.id, instance.local_position, instance.current_population, instance.current_hp, instance.is_ruined, instance.is_under_construction, days_remaining, instance.is_powered_down, _power.days_remaining_for(instance)))
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
		var instance := _register_instance(definition, entry.hex_coord, entry.id, entry.local_position, false, entry.current_population, entry.current_hp, entry.is_ruined, entry.is_under_construction, entry.is_powered_down)
		if entry.is_under_construction:
			_construction.queue(instance, maxi(1, entry.construction_days_remaining))
		if entry.is_powered_down and entry.restart_days_remaining > 0:
			_power.load_pending_restart(instance, entry.restart_days_remaining)
	_next_id = next_id

func _on_day_completed(_day_number: int) -> void:
	run_daily_tick()

## Every per-day building job, in the order they have to run: construction,
## repair and restart countdowns all tick BEFORE this day's Food/production
## tally, so a job finishing TODAY already counts toward it.
##
## Public so a verification can advance the simulation deterministically
## instead of waiting on real time, the same reason (and the same wording)
## InfestationManager.run_daily_tick() gives. TickManager.day_completed can
## fire several times in one frame during a large-delta catch-up, so nothing
## here may accumulate across calls — each collaborator's process_day() is
## already pure per-call arithmetic over its own queue.
func run_daily_tick() -> void:
	_construction.process_day()
	_health.process_day()
	_power.process_day()
	_sustenance.apply_day(_instances)
