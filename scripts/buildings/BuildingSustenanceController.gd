class_name BuildingSustenanceController
extends RefCounted

## Daily Food upkeep vs. production, population starvation/regrowth, and the
## per-hex Discontent production penalty (DiscontentManager.get_production_multiplier).
## Operates on whatever instance list it's given each call (does not own the
## registry) and mutates each BuildingInstance's current_population directly,
## matching BuildingManager's own "mutate the passed-in instance" convention.

signal food_satisfaction_changed(ratio: float)
signal civilians_starved(hex_coord: Vector2i, count: int)
signal population_changed(instance: BuildingInstance)

const FOOD_PER_POPULATION: float = 0.1
const FOOD_STARVATION_RATIO: float = 0.5  ## Below this, population starves to death; at/above but below 1.0, buildings take a production penalty instead.
const FOOD_SURPLUS_RATIO: float = 1.5     ## Above this, production bonus + population regrowth apply.
const MAX_DAILY_STARVATION_DEATH_FRACTION: float = 0.15  ## Fraction of a housing instance's current_population lost per day at ratio 0.0; scales to 0 at FOOD_STARVATION_RATIO.
const SURPLUS_PRODUCTION_BONUS_MAX: float = 0.1
const SURPLUS_PRODUCTION_BONUS_SLOPE: float = 0.2
const POPULATION_REGROWTH_PER_DAY: int = 1
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
## Excludes ResourceType.ENERGY on both sides (BuildingEnergyAllocator's
## one-time grid allocation, not a daily flow).
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
			if resource_type == GameEnums.ResourceType.ENERGY:
				continue
			consumed[resource_type] = consumed.get(resource_type, 0.0) + float(definition.daily_upkeep[resource_type])

		var cell: HexCell = null
		if _hex_grid_map:
			cell = _hex_grid_map.get_cell(instance.hex_coord)
		var output := instance.get_effective_output(cell)
		output.erase(GameEnums.ResourceType.ENERGY)

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

## Applies this day's totals to ResourceManager and, below/above the
## starvation/surplus thresholds, population consequences. Population changes
## apply to TOMORROW's food_demand, not today's, avoiding a same-tick
## circular dependency between mouths-to-feed and mouths-that-starved.
func apply_day(instances: Array[BuildingInstance]) -> void:
	if not _resource_manager:
		return
	var totals := compute_daily_totals(instances)
	var consumed: Dictionary = totals["consumed"]
	var produced: Dictionary = totals["produced"]
	var ratio: float = totals["ratio"]
	food_satisfaction_changed.emit(ratio)
	_resource_manager.apply_daily_flow(consumed, produced)
	if ratio < FOOD_STARVATION_RATIO:
		_apply_starvation_deaths(instances, ratio)
	elif ratio >= FOOD_SURPLUS_RATIO:
		_apply_population_regrowth(instances)

## Population lost from housing buildings proportional to each instance's own
## current_population, severity scaling with how far below
## FOOD_STARVATION_RATIO the day's ratio fell. Garrison/military buildings
## never carry population (population_provided is 0), so they're exempt from
## starvation death without a special case here.
func _apply_starvation_deaths(instances: Array[BuildingInstance], ratio: float) -> void:
	var severity := clampf((FOOD_STARVATION_RATIO - ratio) / FOOD_STARVATION_RATIO, 0.0, 1.0)
	var death_fraction := severity * MAX_DAILY_STARVATION_DEATH_FRACTION
	for instance in instances:
		if instance.current_population <= 0:
			continue
		var deaths := mini(roundi(instance.current_population * death_fraction), instance.current_population)
		if deaths <= 0:
			continue
		instance.current_population -= deaths
		civilians_starved.emit(instance.hex_coord, deaths)
		population_changed.emit(instance)

## Gradual recovery back toward population_provided during a surplus.
func _apply_population_regrowth(instances: Array[BuildingInstance]) -> void:
	for instance in instances:
		var definition := instance.definition
		if definition.population_provided <= 0 or instance.current_population >= definition.population_provided:
			continue
		instance.current_population = mini(instance.current_population + POPULATION_REGROWTH_PER_DAY, definition.population_provided)
		population_changed.emit(instance)
