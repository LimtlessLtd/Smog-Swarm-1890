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
##
## Also owns Phase 2.10's Food Satisfaction mechanic as part of that same
## daily tally, per the design doc's own instruction ("each day
## (BuildingManager._on_day_completed, already built)") — population is real
## per-instance state now (BuildingInstance.current_population), not just a
## fixed definition value, and can be lost to starvation or regrown from a
## surplus depending on how well-fed the colony was that day. Phase 2.11's
## Discontent (a separate manager, DiscontentManager, since it's a
## region-scoped concept BuildingManager itself has no reason to compute)
## is consulted here too — its per-hex production penalty is applied to
## each instance's own output as part of the same daily loop.
##
## Phase 5.12 (Building Destruction & Ruins): damage_building() reduces a
## BuildingInstance's own current_hp (BuildingDefinition.get_max_hp(), a
## construction-cost-derived toughness — "same spirit as walls' own
## toughness", design doc) and, at zero, flips is_ruined true — the
## instance stays in _instances forever after (never removed, "a visible
## scar rather than empty ground"), just skipped entirely by
## _on_day_completed()'s upkeep/output/population tally. Whoever called
## damage_building() (CombatCoordinator, Phase 5.4/5.9/5.10/5.12's siege
## trigger) never needs to know about ruination itself — building_ruined
## carries the population lost at that instant for HordeManager to convert
## to a casualty (Phase 5.9), same "manager emits, HordeManager listens"
## precedent civilians_starved already set. repair_building()/destroy_ruin()
## are the other half — gated on the optional TerritoryController reference
## ("Ruins are inert until the district is recaptured", design doc), same
## "queryable without side effects" get_*_error() pattern every other
## action in this project already follows.

signal building_placed(instance: BuildingInstance)
signal building_removed(instance: BuildingInstance)
signal placement_rejected(building_type: GameEnums.BuildingType, coord: Vector2i, reason: String)

## Design doc Phase 5.12. Fires on every damage_building() call, whether or
## not it actually ruins the building this time — mirrors
## WallManager.wall_segment_damaged's own "every hit, not just the fatal
## one" shape.
signal building_damaged(instance: BuildingInstance, amount: float)
signal building_repaired(instance: BuildingInstance)
signal repair_rejected(instance: BuildingInstance, reason: String)

## Design doc Phase 5.12: "whatever current_population the building held at
## the moment of destruction converts to zombies right there ... a Phase 5.9
## casualty event, same as a starvation death, just triggered by direct
## assault instead of hunger." HordeManager listens for this exactly the way
## it already listens to civilians_starved — see that signal's own doc
## comment for the precedent this follows.
signal building_ruined(instance: BuildingInstance, lost_population: int)

## Design doc Phase 2.10.2: the day's food_demand/available_food ratio,
## recomputed every day_completed — a future HUD indicator or Phase 2.11's
## Discontent can subscribe to this the same way ResourceManager's own
## signals are consumed, without recomputing the ratio themselves.
signal food_satisfaction_changed(ratio: float)

## Design doc Phase 2.10.3: emitted once per housing instance that lost
## population to starvation that day. No consumer exists yet — Phase 5.9's
## casualty conversion (starved civilians become zombies at their own
## building's hex) is blocked on Phase 5.2's HordeManager, which doesn't
## exist yet — but the event itself is real starting now rather than being
## retrofitted once that phase begins.
signal civilians_starved(hex_coord: Vector2i, count: int)

## Daily Food drained per unit of population — see design doc 2.2 "Food
## (population drain)". Multiplied against each instance's current_population
## (Phase 2.10.1's real, mutable per-instance count), not the static
## BuildingDefinition.population_provided baseline it starts from.
const FOOD_PER_POPULATION: float = 0.1

## Design doc Phase 2.10.2's decided thresholds, and 2.10.4's surplus bonus —
## exact numbers are a balancing pass, not an architecture decision, per the
## design doc's own framing.
const FOOD_STARVATION_RATIO: float = 0.5  ## Below this, civilians actually starve to death (2.10.3); at/above it but below 1.0, buildings take a production penalty instead (2.10.2).
const FOOD_SURPLUS_RATIO: float = 1.5     ## Comfortably above 1.0 ("not just barely meeting it") — triggers 2.10.4's modest production bonus and population regrowth.
const MAX_DAILY_STARVATION_DEATH_FRACTION: float = 0.15  ## Fraction of a housing instance's current_population lost per day at the absolute worst case (ratio 0.0); scales down to 0 at FOOD_STARVATION_RATIO.
const SURPLUS_PRODUCTION_BONUS_MAX: float = 0.1   ## Cap on 2.10.4's production bonus — +10% at most.
const SURPLUS_PRODUCTION_BONUS_SLOPE: float = 0.2 ## Bonus grows this much per 1.0 of ratio above FOOD_SURPLUS_RATIO, capped at SURPLUS_PRODUCTION_BONUS_MAX.
const POPULATION_REGROWTH_PER_DAY: int = 1        ## Flat per-instance regrowth toward population_provided while in surplus (2.10.4) — deliberately small and gradual, not an instant restock.

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
## Optional — Phase 2.11's DiscontentManager. Unset gracefully skips the
## per-hex production penalty (get_production_multiplier() query) entirely,
## same as every other optional manager reference in this class.
@export var discontent_manager_path: NodePath
## Optional — Phase 5.8/5.12's ruin-repair gate. Unset means repair_building()/
## destroy_ruin() never check territory state at all (same "gracefully skip
## it" convention as every other optional dependency here).
@export var territory_controller_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _discontent_manager: DiscontentManager
var _territory_controller: TerritoryController
var _instances: Array[BuildingInstance] = []
var _instances_by_hex: Dictionary = {}  # Vector2i -> Array[BuildingInstance]
var _next_id: int = 1

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
	if discontent_manager_path != NodePath():
		_discontent_manager = get_node(discontent_manager_path)
	if territory_controller_path != NodePath():
		_territory_controller = get_node(territory_controller_path)
	TickManager.day_completed.connect(_on_day_completed)
	seed_starting_buildings()

## Seeds the colony with its first building on a truly fresh start. Without
## this, Fog of War (Phase 2.6) leaves the ENTIRE map UNSEEN at boot — no
## building placed anywhere means no vision source anywhere — so a new
## player has literally nothing rendered to look at or click on. Placed for
## free via _register_instance() directly (bypassing place_building()'s
## cost/validation, same as load_save_entries() does) rather than costing
## starting resources: this is the game's own opening move, not a player
## purchase. A future proper "New Game" flow (Phase 7.6) should call this
## explicitly instead of it running unconditionally here; until that exists,
## "the game just booted with nothing placed yet" and "this is a new game"
## are the same thing, so this is the right default. A load right after
## boot (SaveLoadManager.load_save_entries()) already clears every existing
## instance before restoring saved ones, so a seeded Town Hall never lingers
## once a real save is loaded.
## Manchester is the design doc's own canonical starting point (Phase 7.1
## Act I: "Secure Manchester") — matched by name (set from
## BritishGeographyData's GeographyFeature, see HexMapGenerator) rather than
## a hardcoded coordinate here, so this doesn't need to know Manchester's
## specific hex layout. Falls back to any qualifying settlement hex if a
## future alternate map seed doesn't use that name.
const _STARTING_REGION_NAME := "Manchester"

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
	if target:
		var definition := BuildingCatalog.get_definition(GameEnums.BuildingType.TOWN_HALL)
		_register_instance(definition, target.coord, _next_id, Vector2.ZERO, true)

func get_buildings_at(coord: Vector2i) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	result.assign(_instances_by_hex.get(coord, []))
	return result

func get_all_buildings() -> Array[BuildingInstance]:
	return _instances.duplicate()

## Exposed for SaveLoadManager (Phase 2.8) — the next id a freshly-placed
## building would get, so a save can restore it exactly on load instead of
## quietly renumbering everything placed afterward.
func get_next_id() -> int:
	return _next_id

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

## `local_position` is an offset from the hex's own center (Phase 2.5 Tactical
## view placement); leave it ZERO for hex-granularity placement (defaults to
## hex center — fine until a caller cares about exact positioning).
func place_building(building_type: GameEnums.BuildingType, coord: Vector2i, local_position: Vector2 = Vector2.ZERO) -> BuildingInstance:
	var error := get_placement_error(building_type, coord)
	if not error.is_empty():
		placement_rejected.emit(building_type, coord, error)
		return null

	var definition := BuildingCatalog.get_definition(building_type)
	if _resource_manager:
		_resource_manager.spend(definition.construction_cost)
		for resource_type in definition.storage_bonus:
			_resource_manager.add_storage_cap(resource_type, float(definition.storage_bonus[resource_type]))

	return _register_instance(definition, coord, _next_id, local_position, true)

## Shared instance-bookkeeping between a fresh place_building() (which has
## already validated placement and spent resources above) and
## load_save_entries() (Phase 2.8, which restores a building that was
## already paid for in a previous session and must not re-spend or
## re-validate it). `advance_next_id` is false for the latter — restoration
## sets `_next_id` once from the save's own record instead of per-instance.
## `current_population` defaults to -1 ("not specified" — a fresh placement
## seeds from definition.population_provided, see BuildingInstance._init());
## load_save_entries() passes the actual saved value instead, since Phase
## 2.10.1 makes population real mutable state that can differ from that
## baseline after starvation deaths/regrowth.
func _register_instance(definition: BuildingDefinition, coord: Vector2i, id: int, local_position: Vector2, advance_next_id: bool, current_population: int = -1, current_hp: float = -1.0, is_ruined: bool = false) -> BuildingInstance:
	var instance := BuildingInstance.new(definition, coord, id, local_position, current_population, current_hp, is_ruined)
	if advance_next_id:
		_next_id = id + 1
	_instances.append(instance)
	if not _instances_by_hex.has(coord):
		_instances_by_hex[coord] = []
	_instances_by_hex[coord].append(instance)

	building_placed.emit(instance)
	return instance

## Resolves `world_pos` to a hex + local offset and places there — the entry
## point a future click-to-place UI (or the Tactical view) calls instead of
## working out hex coordinates itself. No UI calls this yet (Phase 6+); it
## exists now so precise placement has a home as soon as one does.
func place_building_at_world(building_type: GameEnums.BuildingType, world_pos: Vector2) -> BuildingInstance:
	if not _hex_grid_map:
		placement_rejected.emit(building_type, Vector2i.ZERO, "No hex grid map wired to BuildingManager.")
		return null
	var coord := _hex_grid_map.world_to_coord(world_pos)
	var local_position := world_pos - HexCoord.axial_to_world(coord)
	return place_building(building_type, coord, local_position)

func remove_building(instance: BuildingInstance) -> void:
	_instances.erase(instance)
	if _instances_by_hex.has(instance.hex_coord):
		_instances_by_hex[instance.hex_coord].erase(instance)
	building_removed.emit(instance)

## Design doc Phase 5.12: reduces `instance.current_hp`, and at zero flips
## `is_ruined = true` — stops producing/consuming/housing (see
## _on_day_completed()'s own skip-ruined-instances guard) without removing
## the instance from BuildingManager's records, "a visible scar rather than
## empty ground" (design doc, decided). Mirrors WallManager.damage_segment()
## exactly — same "manager mutates a passed-in Resource directly" shape.
## A no-op against an already-ruined instance, same "can't re-breach a
## breached wall segment" guard that class already has.
func damage_building(instance: BuildingInstance, amount: float) -> void:
	if not instance or instance.is_ruined:
		return
	instance.current_hp = maxf(instance.current_hp - amount, 0.0)
	building_damaged.emit(instance, amount)
	if instance.is_destroyed():
		var lost_population := instance.current_population
		instance.current_population = 0
		instance.is_ruined = true
		building_ruined.emit(instance, lost_population)

## Design doc Phase 5.12: "cheaper than building it from scratch" — same
## framing WallManager.get_repair_cost() uses for the wall equivalent,
## reusing the same 50% fraction rather than inventing a second one.
const REPAIR_COST_FRACTION: float = 0.5

## Design doc Phase 5.12: "Ruins are inert until the district is
## recaptured (Phase 5.8), at which point the player can repair a ruin
## (rebuilds the original building) or destroy the ruin." Restores
## current_hp to a fresh get_max_hp() and current_population to the
## definition's own baseline — the same "seed from the definition" fresh-
## placement convention BuildingInstance._init() already uses, rather than
## a partial/regrowth-gated restore; a repaired building starts fully
## staffed again, not empty and waiting on Phase 2.10.4's regrowth.
func get_repair_error(instance: BuildingInstance) -> String:
	if not instance or not instance.is_ruined:
		return "This building isn't ruined."
	if _territory_controller and _territory_controller.is_lost(instance.hex_coord):
		return "%s's district must be recaptured before it can be repaired." % instance.definition.display_name
	if _resource_manager and not _resource_manager.can_afford(_repair_cost(instance.definition)):
		return "Not enough resources to repair %s." % instance.definition.display_name
	return ""

func can_repair_building(instance: BuildingInstance) -> bool:
	return get_repair_error(instance).is_empty()

func repair_building(instance: BuildingInstance) -> bool:
	var error := get_repair_error(instance)
	if not error.is_empty():
		repair_rejected.emit(instance, error)
		return false
	if _resource_manager:
		_resource_manager.spend(_repair_cost(instance.definition))
	instance.current_hp = instance.definition.get_max_hp()
	instance.is_ruined = false
	instance.current_population = instance.definition.population_provided
	building_repaired.emit(instance)
	return true

func _repair_cost(definition: BuildingDefinition) -> Dictionary:
	var cost: Dictionary = {}
	for resource_type in definition.construction_cost:
		cost[resource_type] = float(definition.construction_cost[resource_type]) * REPAIR_COST_FRACTION
	return cost

## The other Phase 5.12 recapture option: clear a ruin's rubble outright
## rather than rebuild it — same territory-recaptured gate as repair, no
## resource cost either way (demolition, not construction). Reuses
## remove_building() directly; no dedicated rejection signal since
## building_removed already gives a caller everything it needs to know a
## ruin is gone.
func get_destroy_ruin_error(instance: BuildingInstance) -> String:
	if not instance or not instance.is_ruined:
		return "This building isn't ruined."
	if _territory_controller and _territory_controller.is_lost(instance.hex_coord):
		return "%s's district must be recaptured before its ruin can be cleared." % instance.definition.display_name
	return ""

func can_destroy_ruin(instance: BuildingInstance) -> bool:
	return get_destroy_ruin_error(instance).is_empty()

func destroy_ruin(instance: BuildingInstance) -> bool:
	if not get_destroy_ruin_error(instance).is_empty():
		return false
	remove_building(instance)
	return true

## Every placed instance reduced to its saveable footprint (Phase 2.8.1) —
## see BuildingSaveEntry for why the full BuildingDefinition isn't included.
func get_save_entries() -> Array[BuildingSaveEntry]:
	var result: Array[BuildingSaveEntry] = []
	for instance in _instances:
		result.append(BuildingSaveEntry.new(instance.definition.building_type, instance.hex_coord, instance.id, instance.local_position, instance.current_population, instance.current_hp, instance.is_ruined))
	return result

## Restores placed instances from a save (Phase 2.8.2): clears whatever is
## currently placed, then recreates each entry via _register_instance()
## directly — bypassing place_building()'s cost/validation, since these
## buildings already exist and were already paid for. `next_id` is applied
## once at the end rather than derived per-instance, matching whatever
## BuildingManager's own counter was at save time.
func load_save_entries(entries: Array[BuildingSaveEntry], next_id: int) -> void:
	for instance in _instances.duplicate():
		remove_building(instance)
	for entry in entries:
		var definition := BuildingCatalog.get_definition(entry.building_type)
		if not definition:
			push_warning("BuildingManager: unknown building type %s in save data, skipping." % entry.building_type)
			continue
		_register_instance(definition, entry.hex_coord, entry.id, entry.local_position, false, entry.current_population, entry.current_hp, entry.is_ruined)
	_next_id = next_id

func _on_day_completed(_day_number: int) -> void:
	if not _resource_manager:
		return

	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	var total_population := 0

	for instance in _instances:
		if instance.is_ruined:
			continue  ## Phase 5.12: a ruin stops producing/consuming/housing entirely — current_population was already zeroed the moment it ruined (damage_building()).
		var definition := instance.definition
		total_population += instance.current_population  ## Phase 2.10.1: real mutable population, not the static definition value.

		for resource_type in definition.daily_upkeep:
			consumed[resource_type] = consumed.get(resource_type, 0.0) + float(definition.daily_upkeep[resource_type])

		var cell: HexCell = null
		if _hex_grid_map:
			cell = _hex_grid_map.get_cell(instance.hex_coord)
		var output := instance.get_effective_output(cell)

		# Design doc 2.11.1 Consequences: a high-Discontent region's own
		# buildings take a production penalty — applied per-instance, here,
		# BEFORE this building's output is folded into the colony-wide
		# `produced` total, since Discontent (unlike 2.10's food ratio) is
		# region-local rather than a single colony-wide multiplier. Reads
		# YESTERDAY's Discontent value — see DiscontentManager's own class
		# doc comment for why that's the correct causal ordering.
		if _discontent_manager:
			var discontent_multiplier := _discontent_manager.get_production_multiplier(instance.hex_coord)
			if discontent_multiplier != 1.0:
				for resource_type in output:
					output[resource_type] = float(output[resource_type]) * discontent_multiplier

		for resource_type in output:
			produced[resource_type] = produced.get(resource_type, 0.0) + float(output[resource_type])

	# Design doc 2.10.2: food_demand is specifically the population-based
	# upkeep computed just above (not the broader `consumed[FOOD]` total,
	# which today happens to be the same thing since no building charges its
	# own direct FOOD upkeep, but the doc calls out this exact value on
	# purpose in case that ever changes).
	var food_demand := 0.0
	if total_population > 0:
		var food := GameEnums.ResourceType.FOOD
		food_demand = total_population * FOOD_PER_POPULATION
		consumed[food] = consumed.get(food, 0.0) + food_demand

	var ratio := _compute_food_satisfaction_ratio(food_demand, produced)
	food_satisfaction_changed.emit(ratio)

	# 2.10.2/2.10.4: scale this day's total output by the satisfaction ratio
	# (a penalty below full satisfaction, a small bonus at a genuine surplus)
	# before it's banked — computed from the day's *raw* production above,
	# per the doc's own "available_food is stockpile + that day's
	# [unpenalized] production" definition of the ratio itself.
	var production_multiplier := _production_multiplier(ratio)
	if production_multiplier != 1.0:
		for resource_type in produced:
			produced[resource_type] = float(produced[resource_type]) * production_multiplier

	_resource_manager.apply_daily_flow(consumed, produced)

	# 2.10.3/2.10.4: population consequences apply AFTER this day's flow, so
	# they affect tomorrow's food_demand rather than today's — avoids a
	# same-tick circular dependency between "how many mouths to feed" and
	# "how many mouths starved because of how many there were".
	if ratio < FOOD_STARVATION_RATIO:
		_apply_starvation_deaths(ratio)
	elif ratio >= FOOD_SURPLUS_RATIO:
		_apply_population_regrowth()

## `food_demand <= 0` (no population yet) reports a flat 1.0 — "fully fed" is
## the correct trivial answer when there's nobody to feed, and avoids
## treating a population-less colony as an infinite/undefined surplus.
func _compute_food_satisfaction_ratio(food_demand: float, produced: Dictionary) -> float:
	if food_demand <= 0.0:
		return 1.0
	var available := _resource_manager.get_amount(GameEnums.ResourceType.FOOD) + float(produced.get(GameEnums.ResourceType.FOOD, 0.0))
	return available / food_demand

## Design doc 2.10.2's worked examples ("~75% fed is a moderate hit, ~55% fed
## is severe") land exactly on multiplier == ratio, so below full
## satisfaction the multiplier simply tracks the ratio directly — no
## separate curve to tune. At/above FOOD_SURPLUS_RATIO it grants 2.10.4's
## small capped bonus instead; the flat band between 1.0 and
## FOOD_SURPLUS_RATIO ("fully fed, no penalty... see 2.10.4 for surplus
## above this") is neither.
func _production_multiplier(ratio: float) -> float:
	if ratio >= FOOD_SURPLUS_RATIO:
		return 1.0 + minf((ratio - FOOD_SURPLUS_RATIO) * SURPLUS_PRODUCTION_BONUS_SLOPE, SURPLUS_PRODUCTION_BONUS_MAX)
	if ratio >= 1.0:
		return 1.0
	return clampf(ratio, 0.0, 1.0)

## Design doc 2.10.3: population lost from housing buildings proportional to
## each instance's own current_population, severity scaling with how far
## below FOOD_STARVATION_RATIO the day's ratio fell. Garrison/military
## buildings never carry population (population_provided is 0 for them —
## see BuildingCatalog), so "military units are explicitly exempt from
## starvation death" (decided) falls out for free rather than needing a
## special case here; an actual trained unit (Phase 5.4) will need its own
## exemption once it exists to starve in the first place.
func _apply_starvation_deaths(ratio: float) -> void:
	var severity := clampf((FOOD_STARVATION_RATIO - ratio) / FOOD_STARVATION_RATIO, 0.0, 1.0)
	var death_fraction := severity * MAX_DAILY_STARVATION_DEATH_FRACTION
	for instance in _instances:
		if instance.current_population <= 0:
			continue
		var deaths := mini(roundi(instance.current_population * death_fraction), instance.current_population)
		if deaths <= 0:
			continue
		instance.current_population -= deaths
		civilians_starved.emit(instance.hex_coord, deaths)

## Design doc 2.10.4: gradual recovery back toward population_provided during
## a genuine surplus — deliberately small and flat rather than proportional
## ("modest, deliberately limited bonus... exact numbers are a balancing
## pass, not an architecture decision").
func _apply_population_regrowth() -> void:
	for instance in _instances:
		var definition := instance.definition
		if definition.population_provided <= 0 or instance.current_population >= definition.population_provided:
			continue
		instance.current_population = mini(instance.current_population + POPULATION_REGROWTH_PER_DAY, definition.population_provided)
