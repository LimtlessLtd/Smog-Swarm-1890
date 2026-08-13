class_name BuildingConstructionController
extends RefCounted

## Construction job queue. BuildingManager.place_building() pays up front and
## calls queue(); process_day() ticks every job down by one and mutates the
## instance directly (is_under_construction, current_population) on
## completion, matching BuildingManager's existing "mutate the passed-in
## instance" convention. Duration is derived from total construction_cost
## (days_for()), not hand-authored per BuildingDefinition.

signal progressed(coord: Vector2i, days_remaining: int)
signal completed(instance: BuildingInstance)

const _DAYS_PER_COST_UNIT: float = 1.0 / 50.0
const _MIN_DAYS: int = 1
const _MAX_DAYS: int = 4

var _pending: Array[Dictionary] = []  # {instance: BuildingInstance, days_remaining: int}

func days_for(definition: BuildingDefinition) -> int:
	var total := 0.0
	for resource_type in definition.construction_cost:
		total += float(definition.construction_cost[resource_type])
	return clampi(ceili(total * _DAYS_PER_COST_UNIT), _MIN_DAYS, _MAX_DAYS)

func queue(instance: BuildingInstance, days: int) -> void:
	_pending.append({"instance": instance, "days_remaining": days})

func days_remaining_for(instance: BuildingInstance) -> int:
	for job in _pending:
		if job["instance"] == instance:
			return job["days_remaining"]
	return 0

func remove(instance: BuildingInstance) -> void:
	_pending = _pending.filter(func(job: Dictionary) -> bool: return job["instance"] != instance)

func process_day() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending:
		job["days_remaining"] -= 1
		var instance: BuildingInstance = job["instance"]
		if job["days_remaining"] <= 0:
			instance.is_under_construction = false
			instance.current_population = instance.definition.population_provided
			completed.emit(instance)
		else:
			progressed.emit(instance.hex_coord, job["days_remaining"])
			still_pending.append(job)
	_pending = still_pending
