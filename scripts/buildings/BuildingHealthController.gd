class_name BuildingHealthController
extends RefCounted

## Damage/ruin/repair/demolish for BuildingInstance. Ruin: current_hp hits 0,
## is_ruined flips true, `ruined` reports the population lost at that instant
## for the caller to convert to casualties (HordeManager). Repair and
## demolish are gated on TerritoryController.is_lost() whenever a ruin is
## involved — a ruin is inert until its district is recaptured. Does not
## touch BuildingManager's instance registry; demolish()/damage() only
## mutate the instance and refund resources — the caller removes the
## instance from the registry and any queued jobs referencing it.

signal damaged(instance: BuildingInstance, amount: float)
signal ruined(instance: BuildingInstance, lost_population: int)
signal repair_started(instance: BuildingInstance, days: int)
signal repair_rejected(instance: BuildingInstance, reason: String)
signal repaired(instance: BuildingInstance)
signal demolished(instance: BuildingInstance)

const REPAIR_COST_FRACTION: float = 0.5

var _resource_manager: ResourceManager
var _territory_controller: TerritoryController
var _energy: BuildingEnergyAllocator
var _construction_days: Callable  ## BuildingConstructionController.days_for, injected so repair() uses the same cost-to-duration formula without depending on the whole construction controller.
var _pending_repair: Array[Dictionary] = []  # {instance: BuildingInstance, days_remaining: int}

func _init(resource_manager: ResourceManager, territory_controller: TerritoryController, energy: BuildingEnergyAllocator, construction_days: Callable) -> void:
	_resource_manager = resource_manager
	_territory_controller = territory_controller
	_energy = energy
	_construction_days = construction_days

func damage(instance: BuildingInstance, amount: float) -> void:
	if not instance or instance.is_ruined:
		return
	instance.current_hp = maxf(instance.current_hp - amount, 0.0)
	damaged.emit(instance, amount)
	if instance.is_destroyed():
		var lost_population := instance.current_population
		instance.current_population = 0
		instance.is_ruined = true
		_energy.refund(instance.definition)
		ruined.emit(instance, lost_population)

func repair_cost(definition: BuildingDefinition) -> Dictionary:
	var cost: Dictionary = {}
	for resource_type in definition.construction_cost:
		cost[resource_type] = float(definition.construction_cost[resource_type]) * REPAIR_COST_FRACTION
	return cost

func get_repair_error(instance: BuildingInstance) -> String:
	if not instance or not instance.is_ruined:
		return "This building isn't ruined."
	if _territory_controller and _territory_controller.is_lost(instance.hex_coord):
		return "%s's district must be recaptured before it can be repaired." % instance.definition.display_name
	if _resource_manager and not _resource_manager.can_afford(repair_cost(instance.definition)):
		return "Not enough resources to repair %s." % instance.definition.display_name
	# Full amount, not REPAIR_COST_FRACTION — repairing reconnects the same
	# operational power draw a fresh construction would; the 50% discount
	# only applies to physical rebuild material.
	if _resource_manager and not _resource_manager.can_afford(_energy.cost(instance.definition)):
		return "Not enough Energy capacity to repair %s." % instance.definition.display_name
	return ""

func can_repair(instance: BuildingInstance) -> bool:
	return get_repair_error(instance).is_empty()

func repair(instance: BuildingInstance) -> bool:
	var error := get_repair_error(instance)
	if not error.is_empty():
		repair_rejected.emit(instance, error)
		return false
	if _resource_manager:
		_resource_manager.spend(repair_cost(instance.definition))
		_energy.apply(instance.definition)
	var days: int = _construction_days.call(instance.definition)
	_pending_repair.append({"instance": instance, "days_remaining": days})
	repair_started.emit(instance, days)
	return true

func get_demolish_error(instance: BuildingInstance) -> String:
	if not instance:
		return "No such building."
	if instance.is_ruined and _territory_controller and _territory_controller.is_lost(instance.hex_coord):
		return "%s's district must be recaptured before its ruin can be cleared." % instance.definition.display_name
	return ""

func can_demolish(instance: BuildingInstance) -> bool:
	return get_demolish_error(instance).is_empty()

## Refund: construction_cost * REPAIR_COST_FRACTION, or 100% if the instance
## is still under construction (nothing built yet to have used up material
## on). Energy is a separate 100% top-up, only for a still-intact building —
## a ruin already had its Energy refunded once by damage()'s ruin branch, so
## a second refund here would create Energy from nothing.
func demolish(instance: BuildingInstance) -> bool:
	if not get_demolish_error(instance).is_empty():
		return false
	if _resource_manager:
		var refund: Dictionary = {}
		var refund_fraction := 1.0 if instance.is_under_construction else REPAIR_COST_FRACTION
		for resource_type in instance.definition.construction_cost:
			refund[resource_type] = float(instance.definition.construction_cost[resource_type]) * refund_fraction
		if not instance.is_ruined:
			var energy_refund := _energy.cost(instance.definition)
			for resource_type in energy_refund:
				refund[resource_type] = refund.get(resource_type, 0.0) + energy_refund[resource_type]
		for resource_type in refund:
			_resource_manager.add(resource_type, refund[resource_type])
	demolished.emit(instance)
	return true

func remove_pending(instance: BuildingInstance) -> void:
	_pending_repair = _pending_repair.filter(func(job: Dictionary) -> bool: return job["instance"] != instance)

func process_day() -> void:
	var still_pending: Array[Dictionary] = []
	for job in _pending_repair:
		job["days_remaining"] -= 1
		var instance: BuildingInstance = job["instance"]
		if job["days_remaining"] <= 0:
			instance.current_hp = instance.definition.get_max_hp()
			instance.is_ruined = false
			instance.current_population = instance.definition.population_provided
			repaired.emit(instance)
		else:
			still_pending.append(job)
	_pending_repair = still_pending
