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
## precedent civilians_starved already set. repair_building()/demolish_building()
## are the other half — gated on the optional TerritoryController reference
## ("Ruins are inert until the district is recaptured", design doc), same
## "queryable without side effects" get_*_error() pattern every other
## action in this project already follows.

signal building_placed(instance: BuildingInstance)
signal building_removed(instance: BuildingInstance)
signal placement_rejected(building_type: GameEnums.BuildingType, coord: Vector2i, reason: String)
## User report ("building things... should take some amount of time"):
## fires the moment a validated, paid-for placement is queued —
## building_placed (above) now only fires once construction actually
## finishes, `days` days later. See _construction_days() for how long.
signal construction_started(building_type: GameEnums.BuildingType, coord: Vector2i, days: int)
signal construction_progressed(coord: Vector2i, days_remaining: int)
## User report ("buildings should be visible while under construction") —
## building_placed itself now fires the moment place_building() registers the
## instance (see that function's own doc comment), not at completion, so
## every OTHER building_placed listener (Fog of War, ZoC, HUD counts...)
## still only reacts once a building is genuinely finished, this fires
## instead, purely so renderers (LocalDetailManager/StrategicOverlayManager)
## can drop their under-construction tint in place without re-triggering
## anything that assumes building_placed means "brand new, wire it up".
signal building_construction_completed(instance: BuildingInstance)
signal repair_started(instance: BuildingInstance, days: int)

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

## Adversarial code-review finding (this pass's own verification step):
## UnitPanelView's building-selection panel shows current_population, but
## nothing ever told it that value had changed after the panel first
## rendered — civilians_starved (above) carries a COUNT for HordeManager's
## own casualty conversion, not a "this building" reference a UI panel can
## match against its current selection, and _apply_population_regrowth()
## below fired no signal at all. One general "this building's
## current_population just changed, for any reason (starvation,
## regrowth, a future repair restocking a ruin)" event, fired alongside
## the more specific ones above rather than replacing them — same
## "multiple independent listeners, each hearing what they actually need"
## precedent every other signal in this class already follows.
signal building_population_changed(instance: BuildingInstance)

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

## Design doc Phase 5.1's Day Phase bullet: "Construction/gather +20% by day"
## (Night is unchanged, +0%). TimeCycleManager._phase_for_progress() splits
## the 40-minute in-game day into an EXACT 50/50 Day/Night division
## (`progress < 0.5` is Day) — given that fixed 50/50 weighting, a true
## continuous/per-phase implementation averages out, over a full day, to
## exactly 0.5 * 1.2 (Day half, +20%) + 0.5 * 1.0 (Night half, +0%) = 1.1.
## Since that average is mathematically IDENTICAL in observable outcome to a
## flat +10% applied once at the existing once-daily tally, this is
## implemented as that flat multiplier rather than as literal Day/Night
## phase-triggered ticks.
##
## Why not literal sub-day ticks: TickManager's day_completed signal fires
## from inside a "while elapsed_in_day >= DAY_LENGTH_SECONDS" loop that can
## fire MULTIPLE times in a single _process() frame during a large-delta
## catch-up (documented and empirically tested elsewhere in this codebase —
## see e.g. MovementStepper/HordeManager's own "multi-hex catch-up burst"
## handling). TimeCycleManager's own phase-change detection only runs once
## per _process() frame, so during such a burst it would silently miss
## intermediate Day/Night transitions — a signal-driven (day_phase_started/
## night_phase_started) production accumulator would then double-count or
## under-count that day's output. This flat multiplier sidesteps that whole
## risk class entirely while being observably identical to the "true"
## per-phase version under this game's own fixed 50/50 Day/Night split.
const DAY_NIGHT_AVERAGE_PRODUCTION_MULTIPLIER: float = 1.1

## User report ("building things... should take some amount of time") —
## construction/repair duration derived from total resource cost, same
## "a placeholder number, not an architecture decision" framing every other
## balancing constant in this project uses. Deliberately NOT stored per
## BuildingDefinition (would mean hand-tuning 25+ individual entries for a
## first pass); a cost-derived formula gives every building a reasonable,
## consistent duration today and is trivial to override per-type later if a
## specific one ever needs its own hand-picked value.
const _DAYS_PER_COST_UNIT: float = 1.0 / 50.0
const _MIN_CONSTRUCTION_DAYS: int = 1
const _MAX_CONSTRUCTION_DAYS: int = 4

@export var hex_grid_map_path: NodePath
@export var resource_manager_path: NodePath
## Optional — Phase 2.11's DiscontentManager. Unset gracefully skips the
## per-hex production penalty (get_production_multiplier() query) entirely,
## same as every other optional manager reference in this class.
@export var discontent_manager_path: NodePath
## Optional — Phase 5.8/5.12's ruin-repair gate. Unset means repair_building()/
## demolish_building() never check territory state at all (same "gracefully
## skip it" convention as every other optional dependency here).
@export var territory_controller_path: NodePath

var _hex_grid_map: HexGridMap
var _resource_manager: ResourceManager
var _discontent_manager: DiscontentManager
var _territory_controller: TerritoryController
var _instances: Array[BuildingInstance] = []
var _instances_by_hex: Dictionary = {}  # Vector2i -> Array[BuildingInstance]
var _next_id: int = 1
## Paid-for placements/repairs not yet finished — see place_building()/
## repair_building() for how an entry is added and _process_pending_*()
## below for how it's ticked down and completed. Each entry:
## construction: {instance, days_remaining}
## repair: {instance, days_remaining}
## Bug fix: construction jobs now reference a real, already-registered
## BuildingInstance (see place_building()'s own doc comment) instead of raw
## building_type/coord/local_position — the instance needs to exist
## immediately so it can render (tinted) and be selected/demolished mid-build.
## Save/load round-trips this correctly (BuildingSaveEntry.is_under_construction/
## construction_days_remaining, get_save_entries()/load_save_entries() below) —
## no longer the documented gap it used to be, now that a mid-construction
## instance is already a real, saved BuildingInstance and getting this wrong
## would resurrect it as a finished building on load, not just lose a job.
var _pending_construction: Array[Dictionary] = []
var _pending_repair: Array[Dictionary] = []
## Exposed via get_starting_settlement_hexes() for WallManager.seed_starting_defenses()
## — the hex(es) making up the game's own free opening compound (Town Hall +
## Foundry, and the Farm + connecting corridor if one was found), so it
## knows what to wall the OUTER boundary of without re-deriving settlement
## placement logic of its own. Empty before seed_starting_buildings() has
## run (or on a map with no qualifying settlement at all).
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

## Economy-balance pass (user request: "start the game with an iron foundry
## already inside a set of walls") — a second free building alongside the
## Town Hall, same free-via-_register_instance() opening-move treatment,
## not a player purchase. Directly addresses the soft-lock this same pass's
## own economy simulation found: Cast Iron Foundry is the ONLY Cast Iron
## producer in the whole tree, but it itself costs 30 Iron + 70 Bricks to
## build, competing against every other early building that also wants
## Iron out of the same small 40-unit starting stock — a naive opening
## build order can spend past the point of ever affording it, permanently.
## Seeding it already-built removes that trap entirely: Iron production
## (5/day) starts from day one, for free, regardless of what the player
## chooses to build first. Offset local_position so it doesn't render
## exactly on top of the Town Hall at Tactical zoom — same hex, same
## Vector2.ZERO-is-hex-center convention, just nudged off-center.
const _STARTING_FOUNDRY_OFFSET := Vector2(150.0, -100.0)

## Economy-balance pass (user request: "let's also start with a farm"). Town
## Hall's own hex is always URBAN (requires_settlement), which Tenant Farm
## can never be placed on (FARMLAND/MOORLAND only) — so this has to search
## outward. Reads TENANT_FARM's own BuildingCatalog entry for what counts as
## valid (biome + soil fertility) rather than duplicating that list here, so
## this stays correct if that definition ever changes. Searches ring by ring
## (HexCoord.hex_disk() is cumulative, so each radius is checked against
## everything already seen) up to _STARTING_FARM_SEARCH_RADIUS and returns
## the FIRST radius with any qualifying hex — among that radius's own
## candidates, prefers higher soil_fertility (LUSH doubles Tenant Farm's
## Food output over POOR, see BuildingInstance._fertility_multiplier())
## before falling back to raw distance as a final, deterministic tiebreak.
## Vector2i(-1, -1) (an off-map sentinel) means nothing qualified anywhere
## in range — a real possibility this can't paper over on a sufficiently
## unlucky map seed.
const _STARTING_FARM_SEARCH_RADIUS: int = 6
const _NO_FARM_HEX := Vector2i(-1, -1)

func _find_starting_farm_hex(from: Vector2i) -> Vector2i:
	var farm_definition := BuildingCatalog.get_definition(GameEnums.BuildingType.TENANT_FARM)
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
				return fa < fb  ## LOWER GameEnums.SoilFertility enum value == better (LUSH=0 is the best, declared first) — see that enum's own doc comment and BuildingInstance._fertility_multiplier().
			return HexCoord.distance(from, a) < HexCoord.distance(from, b))
		return candidates[0]
	return _NO_FARM_HEX

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
	var foundry := BuildingCatalog.get_definition(GameEnums.BuildingType.CAST_IRON_FOUNDRY)
	_register_instance(foundry, target.coord, _next_id, _STARTING_FOUNDRY_OFFSET, true)

	# **Deliberately just the one core hex** (user report: "the game starts
	# in this weird state where Manchester has many walls jutting out from
	# everywhere... I just want a local area where the player has his few
	# starting buildings to be walled off"). This used to extend to a whole
	# HexPathfinder corridor out to the starting Farm so WallManager.
	# seed_starting_defenses() would fence that too — technically correct
	# (one connected perimeter around everything reachable) but produced a
	# long, sprawling wall several hexes out from the actual settlement,
	# with enough total segment length that hordes found and breached parts
	# of it constantly. A compact single-hex perimeter around Town Hall is
	# what "a local area... walled off" actually asked for; the Farm sits
	# outside it, undefended, same as any other frontier resource building.
	_starting_settlement_hexes = [target.coord]
	var farm_hex := _find_starting_farm_hex(target.coord)
	if farm_hex != _NO_FARM_HEX:
		var farm := BuildingCatalog.get_definition(GameEnums.BuildingType.TENANT_FARM)
		_register_instance(farm, farm_hex, _next_id, Vector2.ZERO, true)

func get_starting_settlement_hexes() -> Array[Vector2i]:
	return _starting_settlement_hexes.duplicate()

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
	if _resource_manager and not _resource_manager.can_afford(_construction_energy_cost(definition)):
		return "Not enough Energy capacity to build %s." % definition.display_name
	return ""

## User request (playtest round 5): "if you click on a building you cannot
## afford to build yet, it should display an error saying how much more
## resources you need" — resource-only, deliberately NOT terrain/settlement
## legality (that's get_placement_error()'s job, and it needs a `coord`
## this doesn't have: BuildMenuView's card click fires BEFORE placement
## mode is even armed, well before the player has picked a hex). Returns ""
## when affordable (or no ResourceManager wired) so callers can treat an
## empty string as "nothing to report" the same way every other
## `get_*_error()` in this project already does.
func get_affordability_error(building_type: GameEnums.BuildingType) -> String:
	var definition := BuildingCatalog.get_definition(building_type)
	if not definition or not _resource_manager:
		return ""
	var shortfalls := _resource_shortfalls(definition.construction_cost)
	shortfalls.append_array(_resource_shortfalls(_construction_energy_cost(definition)))
	if shortfalls.is_empty():
		return ""
	return "Need %s more to build %s." % [", ".join(shortfalls), definition.display_name]

## Shared by get_affordability_error() for both the construction cost AND
## the (separately-tracked, see _construction_energy_cost()'s own doc
## comment) one-time Energy draw — one shortfall list per cost dictionary,
## trimmed to only the resources actually short (an affordable resource in
## the same cost dict isn't reported, same "only say what's actually
## wrong" restraint every other error message here already keeps).
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

## `local_position` is an offset from the hex's own center (Phase 2.5 Tactical
## view placement); leave it ZERO for hex-granularity placement (defaults to
## hex center — fine until a caller cares about exact positioning).
##
## Returns `true` once the placement is validated, paid for, and queued —
## NOT once it's actually standing/operational. Construction takes real time
## (user report): resources/storage/Energy are spent immediately (same "pay
## upfront" convention as before — a player shouldn't be able to cancel out
## of a started project for a refund).
##
## Bug fix (user report: "buildings should be visible while under
## construction... and demolishable while under construction"): the real
## BuildingInstance is now created and registered HERE, immediately —
## `is_under_construction = true` — rather than only at
## _process_pending_construction()'s completion. It's a fully real,
## selectable, demolishable instance from this moment on (see
## demolish_building()'s own doc comment for the 100% construction-site
## refund). `building_placed` still fires here (from _register_instance()) —
## every OTHER listener that treats building_placed as "this building is now
## operational" (Fog of War vision, ZoC, production tallies) additionally
## checks is_under_construction and skips it until
## building_construction_completed fires instead; see that signal's own doc
## comment. Returns `bool` rather than the BuildingInstance since the one
## real caller (BuildPlacementController) only ever checked this for
## truthiness anyway.
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
		_apply_construction_energy(definition)

	var days := _construction_days(definition)
	var instance := _register_instance(definition, coord, _next_id, local_position, true, -1, -1.0, false, true)
	_pending_construction.append({"instance": instance, "days_remaining": days})
	construction_started.emit(building_type, coord, days)
	return true

## Total resource cost (all types summed 1:1, a rough-but-consistent proxy
## for "how big a project is this") mapped to a whole number of days — see
## _DAYS_PER_COST_UNIT's own doc comment for why this is derived rather
## than hand-authored per building.
func _construction_days(definition: BuildingDefinition) -> int:
	var total := 0.0
	for resource_type in definition.construction_cost:
		total += float(definition.construction_cost[resource_type])
	return clampi(ceili(total * _DAYS_PER_COST_UNIT), _MIN_CONSTRUCTION_DAYS, _MAX_CONSTRUCTION_DAYS)

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
func _register_instance(definition: BuildingDefinition, coord: Vector2i, id: int, local_position: Vector2, advance_next_id: bool, current_population: int = -1, current_hp: float = -1.0, is_ruined: bool = false, is_under_construction: bool = false) -> BuildingInstance:
	var instance := BuildingInstance.new(definition, coord, id, local_position, current_population, current_hp, is_ruined, is_under_construction)
	if is_under_construction:
		instance.current_population = 0  ## No free population/housing capacity until construction actually finishes.
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
	# demolish_building() (below) can remove a ruin that's mid-repair
	# (get_repair_error() only ever gates on is_ruined, never on "already
	# queued") — without this, _process_pending_repair() would keep ticking
	# down a job pointing at an instance nothing else references anymore,
	# eventually firing building_repaired for a building that's already
	# gone. Shared here (in remove_building() itself, not duplicated in
	# demolish_building()) so any other future caller of remove_building()
	# gets the same correctness for free rather than needing to remember it.
	_pending_repair = _pending_repair.filter(func(job: Dictionary) -> bool: return job["instance"] != instance)
	# Same reasoning, construction side: demolish_building() can now remove a
	# building mid-construction (it's a real, selectable instance from the
	# moment place_building() registers it — see that function's own doc
	# comment) — without this, _process_pending_construction() would keep
	# ticking down a job pointing at an instance nothing else references.
	_pending_construction = _pending_construction.filter(func(job: Dictionary) -> bool: return job["instance"] != instance)
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
		_refund_construction_energy(instance.definition)
		building_ruined.emit(instance, lost_population)

## --- Energy grid allocation (design doc, decided) --------------------------
##
## Energy is deliberately NOT a recurring daily drain/income like Food or
## Gunpowder — a building's ENERGY entry in daily_upkeep/daily_output (see
## those fields' own doc comments on BuildingDefinition) is a one-time grid
## allocation: a consumer PAYS it once, when the building starts drawing
## power (fresh construction, or a repair reconnecting a ruin); a producer
## GRANTS it once, when the building starts contributing (same two
## moments). Both reverse — consumer refunded, producer's contribution
## withdrawn — the instant the building stops drawing/contributing (ruin).
## `_on_day_completed()` below explicitly skips ResourceType.ENERGY in its
## daily tally so these entries are never ALSO drained/produced per day —
## this pair of methods is the only place ENERGY moves for these buildings.
##
## Read directly from the BuildingDefinition rather than
## BuildingInstance.get_effective_output(): none of today's ENERGY
## producers/consumers have soil_fertility_scales_output, and a one-time
## grid allocation shouldn't fluctuate with a per-day Discontent production
## penalty the way a recurring daily output would — it's a capacity number,
## not a harvest.
func _construction_energy_cost(definition: BuildingDefinition) -> Dictionary:
	var amount := float(definition.daily_upkeep.get(GameEnums.ResourceType.ENERGY, 0.0))
	return {GameEnums.ResourceType.ENERGY: amount} if amount > 0.0 else {}

## Called once, at the moment a building starts drawing/contributing power —
## fresh placement (place_building()) or a ruin being reconnected
## (repair_building()). Affordability for the consumer side is the caller's
## job (get_placement_error()/get_repair_error() both already check
## _construction_energy_cost() before spending anything) — this method
## itself just performs the transaction.
func _apply_construction_energy(definition: BuildingDefinition) -> void:
	if not _resource_manager:
		return
	var cost := _construction_energy_cost(definition)
	if not cost.is_empty():
		_resource_manager.spend(cost)
	var granted := float(definition.daily_output.get(GameEnums.ResourceType.ENERGY, 0.0))
	if granted > 0.0:
		_resource_manager.add(GameEnums.ResourceType.ENERGY, granted)

## The exact reverse of _apply_construction_energy() — called the instant a
## building ruins (damage_building(), above): a consumer's allocation is
## freed back to the grid (ResourceManager.add(), always succeeds), a
## producer's contribution is withdrawn (ResourceManager.remove(),
## deliberately unconditional/uncapped — see that method's own doc comment
## for why a producer ruining while its capacity is still allocated to live
## consumers should be allowed to show as a real deficit).
func _refund_construction_energy(definition: BuildingDefinition) -> void:
	if not _resource_manager:
		return
	var refund := float(definition.daily_upkeep.get(GameEnums.ResourceType.ENERGY, 0.0))
	if refund > 0.0:
		_resource_manager.add(GameEnums.ResourceType.ENERGY, refund)
	var withdrawn := float(definition.daily_output.get(GameEnums.ResourceType.ENERGY, 0.0))
	if withdrawn > 0.0:
		_resource_manager.remove(GameEnums.ResourceType.ENERGY, withdrawn)

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
	# Full amount, not REPAIR_COST_FRACTION — repairing reconnects the SAME
	# operational power draw a fresh construction would (see
	# _apply_construction_energy()'s own doc comment), not half of one; the
	# 50% discount only ever applied to physical rebuilding material.
	if _resource_manager and not _resource_manager.can_afford(_construction_energy_cost(instance.definition)):
		return "Not enough Energy capacity to repair %s." % instance.definition.display_name
	return ""

func can_repair_building(instance: BuildingInstance) -> bool:
	return get_repair_error(instance).is_empty()

## Same "pay upfront, finish later" shape place_building() now uses — see
## that function's own doc comment. The ruin stays a ruin (rendering-wise,
## same code-drawn silhouette as before) until
## _process_pending_repair() below applies the actual restoration and
## fires building_repaired, `days` days from now.
func repair_building(instance: BuildingInstance) -> bool:
	var error := get_repair_error(instance)
	if not error.is_empty():
		repair_rejected.emit(instance, error)
		return false
	if _resource_manager:
		_resource_manager.spend(_repair_cost(instance.definition))
		_apply_construction_energy(instance.definition)
	var days := _construction_days(instance.definition)
	_pending_repair.append({"instance": instance, "days_remaining": days})
	repair_started.emit(instance, days)
	return true

func _repair_cost(definition: BuildingDefinition) -> Dictionary:
	var cost: Dictionary = {}
	for resource_type in definition.construction_cost:
		cost[resource_type] = float(definition.construction_cost[resource_type]) * REPAIR_COST_FRACTION
	return cost

## --- Demolish (user request: "there should also be a demolish button on
## every building (and wall) where you get 50% of the resources used to
## build it back EXCEPT energy where you always get 100% of the energy
## used to build a building back") ------------------------------------------
##
## The sole "clear a ruin" mechanism (superseded destroy_ruin(), a
## ruin-only/no-refund function this same pass removed as dead code — zero
## call sites anywhere in the codebase). demolish_building() works
## on ANY building the player still owns, ruined or not, and is always a
## refund, never a further loss: HALF of construction_cost — reusing
## REPAIR_COST_FRACTION's own existing 50% rather than inventing a second
## fraction constant for the same number — plus, only for a still-intact
## building, the FULL one-time ENERGY grid draw (_construction_energy_cost()).
## A ruined building does NOT get that Energy portion refunded again: the
## instant it ruined, damage_building() already called
## _refund_construction_energy() and gave it back once — refunding it a
## second time here would manufacture Energy from nothing. Energy is
## handled as this separate top-up (not folded into the construction_cost
## loop) because it structurally never lives in construction_cost to begin
## with — see BuildingDefinition.daily_upkeep's own doc comment for why
## Energy is tracked as a one-time draw there instead.
signal building_demolished(instance: BuildingInstance)

## A ruin still needs its district recaptured before the player can
## interact with it at all — same "Ruins are inert until the district is
## recaptured" gate get_repair_error() already enforces. An intact building
## has no such restriction (it's the player's own working structure, not
## contested rubble sitting in enemy-held ground).
func get_demolish_error(instance: BuildingInstance) -> String:
	if not instance:
		return "No such building."
	if instance.is_ruined and _territory_controller and _territory_controller.is_lost(instance.hex_coord):
		return "%s's district must be recaptured before its ruin can be cleared." % instance.definition.display_name
	return ""

func can_demolish_building(instance: BuildingInstance) -> bool:
	return get_demolish_error(instance).is_empty()

## User report ("you get 100% of your resources back if you manage to
## demolish a building thats not yet built") — a construction site refunds
## the FULL construction_cost, not REPAIR_COST_FRACTION's usual 50%: nothing
## has actually been built yet, so there's no partial structure whose
## materials were "used up" the way a completed building's would be. Energy
## stays the existing 100% refund either way (not_ruined is always true for
## an under-construction instance, so that branch already fires).
func demolish_building(instance: BuildingInstance) -> bool:
	if not get_demolish_error(instance).is_empty():
		return false
	if _resource_manager:
		var refund: Dictionary = {}
		var refund_fraction := 1.0 if instance.is_under_construction else REPAIR_COST_FRACTION
		for resource_type in instance.definition.construction_cost:
			refund[resource_type] = float(instance.definition.construction_cost[resource_type]) * refund_fraction
		if not instance.is_ruined:
			var energy_refund := _construction_energy_cost(instance.definition)
			for resource_type in energy_refund:
				refund[resource_type] = refund.get(resource_type, 0.0) + energy_refund[resource_type]
		for resource_type in refund:
			_resource_manager.add(resource_type, refund[resource_type])
	remove_building(instance)
	building_demolished.emit(instance)
	return true

## Every placed instance reduced to its saveable footprint (Phase 2.8.1) —
## see BuildingSaveEntry for why the full BuildingDefinition isn't included.
## Mid-construction instances round-trip too (bug fix — see
## BuildingSaveEntry.is_under_construction's own doc comment): days_remaining
## is read back out of _pending_construction, matching whichever job (if any)
## currently references this instance.
func get_save_entries() -> Array[BuildingSaveEntry]:
	var result: Array[BuildingSaveEntry] = []
	for instance in _instances:
		var days_remaining := 0
		if instance.is_under_construction:
			for job in _pending_construction:
				if job["instance"] == instance:
					days_remaining = job["days_remaining"]
					break
		result.append(BuildingSaveEntry.new(instance.definition.building_type, instance.hex_coord, instance.id, instance.local_position, instance.current_population, instance.current_hp, instance.is_ruined, instance.is_under_construction, days_remaining))
	return result

## Restores placed instances from a save (Phase 2.8.2): clears whatever is
## currently placed, then recreates each entry via _register_instance()
## directly — bypassing place_building()'s cost/validation, since these
## buildings already exist and were already paid for. `next_id` is applied
## once at the end rather than derived per-instance, matching whatever
## BuildingManager's own counter was at save time. A mid-construction entry
## also re-queues its own _pending_construction job (maxi(1, ...) guards
## against a corrupt/hand-edited 0-or-negative save value stalling forever)
## so it keeps counting down after load instead of silently resurrecting as
## finished (see BuildingSaveEntry's own doc comment).
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
			_pending_construction.append({"instance": instance, "days_remaining": maxi(1, entry.construction_days_remaining)})
	_next_id = next_id

## Ticks every queued construction/repair down by one day, completing (and
## removing from the queue) anything that reaches zero. Runs before this
## same day's upkeep/output tally below so a building finishing TODAY
## already counts toward it — same "same-day" precedent damage/starvation
## handling elsewhere in this method doesn't fight.
func _process_pending_construction() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending_construction:
		job["days_remaining"] -= 1
		var instance: BuildingInstance = job["instance"]
		if job["days_remaining"] <= 0:
			instance.is_under_construction = false
			instance.current_population = instance.definition.population_provided
			building_construction_completed.emit(instance)
		else:
			construction_progressed.emit(instance.hex_coord, job["days_remaining"])
			still_pending.append(job)
	_pending_construction = still_pending

func _process_pending_repair() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending_repair:
		job["days_remaining"] -= 1
		var instance: BuildingInstance = job["instance"]
		if job["days_remaining"] <= 0:
			instance.current_hp = instance.definition.get_max_hp()
			instance.is_ruined = false
			instance.current_population = instance.definition.population_provided
			building_repaired.emit(instance)
		else:
			still_pending.append(job)
	_pending_repair = still_pending

func _on_day_completed(_day_number: int) -> void:
	_process_pending_construction()
	_process_pending_repair()
	if not _resource_manager:
		return

	var totals := _compute_daily_totals()
	var consumed: Dictionary = totals["consumed"]
	var produced: Dictionary = totals["produced"]
	var ratio: float = totals["ratio"]
	food_satisfaction_changed.emit(ratio)

	_resource_manager.apply_daily_flow(consumed, produced)

	# 2.10.3/2.10.4: population consequences apply AFTER this day's flow, so
	# they affect tomorrow's food_demand rather than today's — avoids a
	# same-tick circular dependency between "how many mouths to feed" and
	# "how many mouths starved because of how many there were".
	if ratio < FOOD_STARVATION_RATIO:
		_apply_starvation_deaths(ratio)
	elif ratio >= FOOD_SURPLUS_RATIO:
		_apply_population_regrowth()

## The actual per-instance upkeep/output tally, extracted out of
## _on_day_completed() so a non-mutating preview (get_projected_daily_flow(),
## user request — a resource-bar tooltip showing "total daily income and
## total daily expenditure") can run the exact same math the real daily tick
## uses instead of a second, driftable approximation. Returns the SAME
## `consumed`/`produced` dictionaries _on_day_completed() used to feed
## ResourceManager.apply_daily_flow() with (already food-satisfaction-scaled
## on the produced side) — this function only computes, it never touches
## ResourceManager or BuildingInstance state itself.
func _compute_daily_totals() -> Dictionary:
	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	var total_population := 0

	for instance in _instances:
		if instance.is_ruined or instance.is_under_construction:
			continue  ## Phase 5.12: a ruin stops producing/consuming/housing entirely — current_population was already zeroed the moment it ruined (damage_building()). A construction site the same way — nothing to produce/consume/house until it's actually finished (current_population is already 0 the whole time — see _register_instance()).
		var definition := instance.definition
		total_population += instance.current_population  ## Phase 2.10.1: real mutable population, not the static definition value.

		for resource_type in definition.daily_upkeep:
			if resource_type == GameEnums.ResourceType.ENERGY:
				continue  ## A one-time grid allocation now (see _apply_construction_energy()), not a daily drain.
			consumed[resource_type] = consumed.get(resource_type, 0.0) + float(definition.daily_upkeep[resource_type])

		var cell: HexCell = null
		if _hex_grid_map:
			cell = _hex_grid_map.get_cell(instance.hex_coord)
		var output := instance.get_effective_output(cell)
		output.erase(GameEnums.ResourceType.ENERGY)  ## Same exception, output side — a one-time grid contribution, not a daily yield.

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
			# Phase 5.1's Day/Night average — see
			# DAY_NIGHT_AVERAGE_PRODUCTION_MULTIPLIER's own doc comment.
			produced[resource_type] = produced.get(resource_type, 0.0) + float(output[resource_type]) * DAY_NIGHT_AVERAGE_PRODUCTION_MULTIPLIER

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

	# 2.10.2/2.10.4: scale this day's total output by the satisfaction ratio
	# (a penalty below full satisfaction, a small bonus at a genuine surplus)
	# before it's banked — computed from the day's *raw* production above,
	# per the doc's own "available_food is stockpile + that day's
	# [unpenalized] production" definition of the ratio itself.
	var production_multiplier := _production_multiplier(ratio)
	if production_multiplier != 1.0:
		for resource_type in produced:
			produced[resource_type] = float(produced[resource_type]) * production_multiplier

	return {"consumed": consumed, "produced": produced, "ratio": ratio}

## User request (playtest round 4, resource bar tooltip: "total daily income
## and total daily expenditure"): today's projected upkeep/output at CURRENT
## building/population state, computed but never applied — a read-only
## preview via the exact same _compute_daily_totals() math the real daily
## tick banks, not a second approximation that could silently drift from it.
## Excludes ENERGY on both sides for the same reason _compute_daily_totals()
## itself does (a one-time grid draw/contribution, not a daily flow) — see
## BuildingDefinition.daily_upkeep/daily_output's own doc comments.
func get_projected_daily_flow() -> Dictionary:
	var totals := _compute_daily_totals()
	return {"consumed": totals["consumed"], "produced": totals["produced"]}

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
		building_population_changed.emit(instance)

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
		building_population_changed.emit(instance)
