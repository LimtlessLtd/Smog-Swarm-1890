class_name DiscontentManager
extends Node

## Colony-wide (well, per-region) unrest tracker — a *population* mechanic,
## explicitly distinct from per-unit Morale & Veterancy. "A colony-economy
## mechanic" (design doc), so it lives alongside ResourceManager rather
## than under /scripts/world despite reading territory data from
## LogisticsNetwork.
##
## Scope: per contiguous Civilian Zone of Control region, not global and
## not per-hex. A "Civilian Region" is a maximal connected cluster of
## hexes currently carrying LogisticsNetwork's has_civilian_coverage —
## hex-adjacency flood fill (HexCoord.neighbors), recomputed whenever ZoC
## changes (LogisticsNetwork.network_recomputed). Multi-hex settlements
## (Manchester's 4 hexes, London's 12) share one Discontent value as long
## as they stay contiguously covered; a region physically split by lost
## territory splits into two independently-tracked regions.
##
## Discontent itself is stored PER HEX (`_discontent_by_hex`), not per a
## synthetic region id — every hex in a region is always driven to the same
## value on each daily update, but storing it per-hex means a region that
## splits naturally carries each half's already-earned value forward
## (each half just keeps evolving independently from where it was), and a
## region that merges seeds from the higher of its constituent hexes'
## values, rather than losing history to whatever id happened to survive a
## recompute.
##
## Drivers run on two different cadences, both anchored to existing signals
## rather than new bespoke plumbing:
## - Structural (region *membership*): LogisticsNetwork.network_recomputed —
##   immediate, since which hexes belong to which region is ZoC's own state.
## - Numeric (region *value*): TickManager.day_completed — once per day,
##   same cadence as BuildingManager's own daily tally, matching the
##   design doc's economic drivers (overcrowding, shortfalls) which are
##   themselves daily figures. Applied AFTER BuildingManager's own
##   day_completed handler runs (this node must be a LATER Main.tscn
##   sibling than BuildingManager — see Main.tscn) so today's production
##   penalty (queried by BuildingManager, see get_production_multiplier())
##   reads YESTERDAY's Discontent, not a value this same tick is still
##   computing — the same causality rule starvation/regrowth already uses.

signal region_discontent_changed(hex_coords: Array[Vector2i], discontent: float)

@export var logistics_network_path: NodePath
@export var building_manager_path: NodePath
@export var resource_manager_path: NodePath

var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _resource_manager: ResourceManager

var _discontent_by_hex: Dictionary = {}  # Vector2i -> float, 0.0 (content) .. 1.0 (max unrest)
var _regions: Array = []  # Array[Array[Vector2i]], cached from the most recent structural recompute

# Per-day accumulators, fed by signals as they fire and consumed/reset by
# _on_day_completed() — see class doc comment for why the two different
# cadences are safe to mix this way.
var _pending_shortfall_types: Dictionary = {}       # GameEnums.ResourceType -> true
var _pending_food_ratio: float = 1.0                # BuildingManager.food_satisfaction_changed's latest report.
var _pending_casualty_pressure_by_hex: Dictionary = {}  # Vector2i -> float

## Exact numbers are a balancing pass, not an architecture decision — every
## constant below is a documented placeholder, not a tuned value.
const OVERCROWDING_CAPACITY_PER_HEX: float = 40.0   ## Region capacity scales with hex count, so a 12-hex London isn't trivially "overcrowded" just for being large — matches multi-hex settlements sharing one Discontent value.
const OVERCROWDING_PRESSURE_SCALE: float = 0.5      ## Discontent gained per day per 1.0 of overcrowding_ratio above capacity.
const STARVATION_CASUALTY_PRESSURE_PER_DEATH: float = 0.02  ## Per starved civilian (BuildingManager.civilians_starved) within the region's own hexes that day — the one real "casualties" input available today; combat casualties/incursions aren't built yet.
const HUNGER_BAND_PRESSURE: float = 0.05            ## Flat daily pressure, applied to every region equally, while the colony's food ratio sits in the hungry-but-not-starving band (independent of BuildingManager's own direct production penalty, per the design doc).
const SHORTFALL_PRESSURE_PER_EVENT: float = 0.05    ## Flat daily pressure per distinct resource type that hit ResourceManager.upkeep_shortfall that day, applied to every region equally (the stockpile is one global pool — Discontent is region-scoped, the economy underneath it deliberately isn't).
const RECOVERY_PER_DAY: float = 0.03                ## Passive daily decay toward content when no drivers fire that day.
const HIGH_DISCONTENT_THRESHOLD: float = 0.7        ## Design doc's "high-Discontent region" — at/above this, buildings in the region take the Consequences production penalty.
const HIGH_DISCONTENT_PRODUCTION_PENALTY: float = 0.15  ## Flat output cut applied to buildings within a high-Discontent region.

func _ready() -> void:
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_logistics_network.network_recomputed.connect(_on_network_recomputed)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.civilians_starved.connect(_on_civilians_starved)
		_building_manager.food_satisfaction_changed.connect(_on_food_satisfaction_changed)
	if resource_manager_path != NodePath():
		_resource_manager = get_node(resource_manager_path)
		_resource_manager.upkeep_shortfall.connect(_on_upkeep_shortfall)
	TickManager.day_completed.connect(_on_day_completed)
	_recompute_regions()

func get_discontent_at(coord: Vector2i) -> float:
	return _discontent_by_hex.get(coord, 0.0)

func is_high_discontent(coord: Vector2i) -> bool:
	return get_discontent_at(coord) >= HIGH_DISCONTENT_THRESHOLD

## Design doc Consequences: "production penalty on buildings within a
## high-Discontent region (queried by BuildingManager at its existing
## daily-tally step)". Kept as a single queryable multiplier (mirrors
## BuildingManager._production_multiplier()'s own shape) so BuildingManager
## never needs to know Discontent's internal thresholds.
func get_production_multiplier(coord: Vector2i) -> float:
	if is_high_discontent(coord):
		return 1.0 - HIGH_DISCONTENT_PRODUCTION_PENALTY
	return 1.0

## Every currently-tracked region, each as its own hex list — exposed for a
## future HUD indicator or debug tooling; nothing in this class needs
## callers to have this today.
func get_regions() -> Array:
	return _regions.duplicate(true)

## Exposed for SaveLoadManager alongside SaveGameData — the per-hex
## Discontent map is the only state worth persisting; _regions itself is
## recomputed fresh from live ZoC on load (_recompute_regions(), called at
## the end of load_save_state()), same as ZoC coverage itself never being
## saved directly.
func get_save_state() -> Dictionary:
	return {"discontent_by_hex": _discontent_by_hex.duplicate()}

func load_save_state(state: Dictionary) -> void:
	_discontent_by_hex = state.get("discontent_by_hex", {}).duplicate()
	_recompute_regions()

## Structural recompute: which hexes belong to which region. Pure flood fill
## over LogisticsNetwork.get_civilian_covered_hexes() via hex adjacency —
## does NOT touch _discontent_by_hex's actual values, so a mid-day ZoC change
## (a Town Hall placed, a hex lost) reshapes region membership immediately
## without jumping any hex's earned Discontent value around.
func _recompute_regions() -> void:
	_regions.clear()
	if not _logistics_network:
		return

	var covered: Dictionary = {}  # Vector2i -> true
	for coord in _logistics_network.get_civilian_covered_hexes():
		covered[coord] = true

	var visited: Dictionary = {}
	for coord in covered:
		if visited.has(coord):
			continue
		var region: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [coord]
		visited[coord] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			region.append(current)
			for neighbor in HexCoord.neighbors(current):
				if covered.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					frontier.append(neighbor)
		_regions.append(region)

func _region_population(region: Array[Vector2i]) -> int:
	if not _building_manager:
		return 0
	var total := 0
	for coord in region:
		for instance in _building_manager.get_buildings_at(coord):
			total += instance.current_population
	return total

## Seed value for this day's update: the highest Discontent already stored
## across the region's member hexes. On a steady-state region (unchanged
## membership day to day) every member hex already shares one value, so this
## is a no-op; on a fresh merge it correctly carries forward the more
## discontented half rather than averaging away legitimate unrest.
func _region_discontent(region: Array[Vector2i]) -> float:
	var value := 0.0
	for coord in region:
		value = maxf(value, _discontent_by_hex.get(coord, 0.0))
	return value

func _on_day_completed(_day_number: int) -> void:
	# Design doc: "Food/Energy/Gunpowder shortfalls affect every region
	# equally, since the resource stockpile itself is deliberately one
	# global pool" — both of these pending accumulators are global, not
	# per-region, for exactly that reason.
	var global_pressure := _pending_shortfall_types.size() * SHORTFALL_PRESSURE_PER_EVENT
	if _pending_food_ratio >= BuildingManager.FOOD_STARVATION_RATIO and _pending_food_ratio < 1.0:
		global_pressure += HUNGER_BAND_PRESSURE

	for region: Array[Vector2i] in _regions:
		var region_population := _region_population(region)
		var region_capacity := maxf(region.size() * OVERCROWDING_CAPACITY_PER_HEX, 1.0)
		var overcrowding_ratio := float(region_population) / region_capacity
		var overcrowding_pressure := maxf(overcrowding_ratio - 1.0, 0.0) * OVERCROWDING_PRESSURE_SCALE

		var casualty_pressure := 0.0
		for coord in region:
			casualty_pressure += _pending_casualty_pressure_by_hex.get(coord, 0.0)

		var delta := overcrowding_pressure + casualty_pressure + global_pressure - RECOVERY_PER_DAY
		var updated := clampf(_region_discontent(region) + delta, 0.0, 1.0)
		for coord in region:
			_discontent_by_hex[coord] = updated
		region_discontent_changed.emit(region.duplicate(), updated)

	_pending_shortfall_types.clear()
	_pending_food_ratio = 1.0
	_pending_casualty_pressure_by_hex.clear()

	# A hex that's no longer part of any current civilian region stops being
	# tracked — Discontent is a property of currently-covered civilian
	# ground, not a memory of ground since lost (if it's ever recovered, it
	# starts fresh, same as a freshly-annexed hex would).
	var still_covered: Dictionary = {}
	for region: Array[Vector2i] in _regions:
		for coord in region:
			still_covered[coord] = true
	for coord in _discontent_by_hex.keys().duplicate():
		if not still_covered.has(coord):
			_discontent_by_hex.erase(coord)

func _on_network_recomputed() -> void:
	_recompute_regions()

func _on_civilians_starved(hex_coord: Vector2i, count: int) -> void:
	_pending_casualty_pressure_by_hex[hex_coord] = _pending_casualty_pressure_by_hex.get(hex_coord, 0.0) + count * STARVATION_CASUALTY_PRESSURE_PER_DEATH

func _on_upkeep_shortfall(resource_type: GameEnums.ResourceType, _shortfall: float) -> void:
	_pending_shortfall_types[resource_type] = true

func _on_food_satisfaction_changed(ratio: float) -> void:
	_pending_food_ratio = ratio
