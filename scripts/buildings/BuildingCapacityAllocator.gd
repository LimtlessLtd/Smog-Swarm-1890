class_name BuildingCapacityAllocator
extends RefCounted

## One-time capacity-resource allocation, shared by BuildingManager
## (construction) and BuildingHealthController (repair/demolish/ruin refund).
## ENERGY and POPULATION are both design_doc.md §2 "Capacity & Yield Pools"
## resources, and both work identically here: a consumer's daily_upkeep[type]
## is paid once when it starts drawing capacity; a producer's
## daily_output[type] is granted once when it starts contributing capacity.
## Both reverse the instant the building stops (ruin/demolish). Not a
## recurring per-day flow — BuildingSustenanceController excludes both types
## from its daily tally so this is the only place either one moves for these
## entries. Was BuildingEnergyAllocator, ENERGY-only, before POPULATION
## adopted the same capacity-pool mechanics (design_doc.md §2).

const CAPACITY_RESOURCE_TYPES: Array[GameEnums.ResourceType] = [
	GameEnums.ResourceType.ENERGY,
	GameEnums.ResourceType.POPULATION,
]

var _resource_manager: ResourceManager

func _init(resource_manager: ResourceManager) -> void:
	_resource_manager = resource_manager

func cost(definition: BuildingDefinition) -> Dictionary:
	var result: Dictionary = {}
	for resource_type in CAPACITY_RESOURCE_TYPES:
		var amount := float(definition.daily_upkeep.get(resource_type, 0.0))
		if amount > 0.0:
			result[resource_type] = amount
	return result

func apply(definition: BuildingDefinition) -> void:
	if not _resource_manager:
		return
	var c := cost(definition)
	if not c.is_empty():
		_resource_manager.spend(c)
	for resource_type in CAPACITY_RESOURCE_TYPES:
		var granted := float(definition.daily_output.get(resource_type, 0.0))
		if granted > 0.0:
			_resource_manager.add(resource_type, granted)

func refund(definition: BuildingDefinition) -> void:
	if not _resource_manager:
		return
	for resource_type in CAPACITY_RESOURCE_TYPES:
		var refunded := float(definition.daily_upkeep.get(resource_type, 0.0))
		if refunded > 0.0:
			_resource_manager.add(resource_type, refunded)
		var withdrawn := float(definition.daily_output.get(resource_type, 0.0))
		if withdrawn > 0.0:
			_resource_manager.remove(resource_type, withdrawn)
