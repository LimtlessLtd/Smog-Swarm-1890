class_name BuildingSustenanceController
extends RefCounted

## Daily Food upkeep vs. production and the per-hex Discontent production
## penalty (DiscontentManager.get_production_multiplier). Operates on
## whatever instance list it's given each call (does not own the registry).
##
## Population is a capacity pool (design_doc.md §2, see
## CapacityAllocator) now, not a headcount this class tracks or
## mutates — low Food satisfaction cuts production via
## _production_multiplier() below, it no longer starves anyone to death, and
## surplus Food no longer regrows population. A housing instance's own
## current_population is fixed at definition.population_provided once
## construction/repair completes (BuildingConstructionController/
## BuildingHealthController) and zeroed only on ruin, matching every other
## building's "fixed once built" fields.

signal food_satisfaction_changed(ratio: float)

const FOOD_PER_POPULATION: float = 0.1
const FOOD_STARVATION_RATIO: float = 0.5  ## Below this, buildings take a production penalty; at/above but below 1.0, output tracks the ratio directly (see _production_multiplier()).
const FOOD_SURPLUS_RATIO: float = 1.5     ## Above this, a small production bonus applies.
const SURPLUS_PRODUCTION_BONUS_MAX: float = 0.1
const SURPLUS_PRODUCTION_BONUS_SLOPE: float = 0.2
## Day is +20% construction/gather, Night +0% (TimeCycleManager._phase_for_progress()
## splits the 40-minute day exactly 50/50): 0.5*1.2 + 0.5*1.0 = 1.1, applied
## once per daily tally instead of as literal per-phase ticks. TickManager's
## day_completed can fire multiple times in a single frame during a large-delta
## catch-up; a phase-triggered accumulator would double/under-count across
## that boundary, so this flat multiplier is used instead — observably
## identical given the fixed 50/50 split.
const DAY_NIGHT_AVERAGE_PRODUCTION_MULTIPLIER: float = 1.1

var _resource_manager: ResourceManager
var _discontent_manager: DiscontentManager
var _hex_grid_map: HexGridMap

func _init(resource_manager: ResourceManager, discontent_manager: DiscontentManager, hex_grid_map: HexGridMap) -> void:
	_resource_manager = resource_manager
	_discontent_manager = discontent_manager
	_hex_grid_map = hex_grid_map

## Returns {"consumed": Dictionary, "produced": Dictionary, "ratio": float}.
## Excludes CapacityAllocator.CAPACITY_RESOURCE_TYPES (ENERGY,
## POPULATION) on both sides — those are one-time capacity grants/reserves
## settled at construction, not a daily flow; including them here would
## double-count on top of CapacityAllocator.apply().
func compute_daily_totals(instances: Array[BuildingInstance]) -> Dictionary:
	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	var total_population := 0

	for instance in instances:
		if instance.is_ruined or instance.is_under_construction:
			continue
		var definition := instance.definition
		total_population += instance.current_population

		for resource_type in definition.daily_upkeep:
			if CapacityAllocator.CAPACITY_RESOURCE_TYPES.has(resource_type):
				continue
			consumed[resource_type] = consumed.get(resource_type, 0.0) + float(definition.daily_upkeep[resource_type])

		var cell: HexCell = null
		if _hex_grid_map:
			cell = _hex_grid_map.get_cell(instance.hex_coord)
		var output := instance.get_effective_output(cell)
		for resource_type in CapacityAllocator.CAPACITY_RESOURCE_TYPES:
			output.erase(resource_type)

		if _discontent_manager:
			var discontent_multiplier := _discontent_manager.get_production_multiplier(instance.hex_coord)
			if discontent_multiplier != 1.0:
				for resource_type in output:
					output[resource_type] = float(output[resource_type]) * discontent_multiplier

		for resource_type in output:
			produced[resource_type] = produced.get(resource_type, 0.0) + float(output[resource_type]) * DAY_NIGHT_AVERAGE_PRODUCTION_MULTIPLIER

	# food_demand is specifically the population-based upkeep computed here,
	# not the broader `consumed[FOOD]` total — currently the same value since
	# no building charges its own direct FOOD upkeep, kept separate in case
	# that changes.
	var food_demand := 0.0
	if total_population > 0:
		var food := GameEnums.ResourceType.FOOD
		food_demand = total_population * FOOD_PER_POPULATION
		consumed[food] = consumed.get(food, 0.0) + food_demand

	var ratio := _compute_food_satisfaction_ratio(food_demand, produced)

	var production_multiplier := _production_multiplier(ratio)
	if production_multiplier != 1.0:
		for resource_type in produced:
			produced[resource_type] = float(produced[resource_type]) * production_multiplier

	return {"consumed": consumed, "produced": produced, "ratio": ratio}

## Read-only preview of today's projected upkeep/output at current
## building/population state — same math apply_day() banks, not a second
## approximation.
func get_projected_daily_flow(instances: Array[BuildingInstance]) -> Dictionary:
	var totals := compute_daily_totals(instances)
	return {"consumed": totals["consumed"], "produced": totals["produced"]}

## food_demand <= 0 (no population yet) reports 1.0 — "fully fed" is the
## correct trivial answer with nobody to feed.
func _compute_food_satisfaction_ratio(food_demand: float, produced: Dictionary) -> float:
	if food_demand <= 0.0:
		return 1.0
	var available := _resource_manager.get_amount(GameEnums.ResourceType.FOOD) + float(produced.get(GameEnums.ResourceType.FOOD, 0.0))
	return available / food_demand

## Below full satisfaction, the multiplier tracks the ratio directly. At/above
## FOOD_SURPLUS_RATIO it grants a small capped bonus instead. Flat 1.0 between
## 1.0 and FOOD_SURPLUS_RATIO (fully fed, no penalty, no bonus yet).
func _production_multiplier(ratio: float) -> float:
	if ratio >= FOOD_SURPLUS_RATIO:
		return 1.0 + minf((ratio - FOOD_SURPLUS_RATIO) * SURPLUS_PRODUCTION_BONUS_SLOPE, SURPLUS_PRODUCTION_BONUS_MAX)
	if ratio >= 1.0:
		return 1.0
	return clampf(ratio, 0.0, 1.0)

## Applies this day's totals to ResourceManager. Below FOOD_STARVATION_RATIO
## that's a production penalty only now (_production_multiplier(), already
## folded into `produced` by compute_daily_totals()) — no population
## consequence to apply here anymore.
func apply_day(instances: Array[BuildingInstance]) -> void:
	if not _resource_manager:
		return
	var totals := compute_daily_totals(instances)
	var consumed: Dictionary = totals["consumed"]
	var produced: Dictionary = totals["produced"]
	var ratio: float = totals["ratio"]
	food_satisfaction_changed.emit(ratio)
	_resource_manager.apply_daily_flow(consumed, produced)
