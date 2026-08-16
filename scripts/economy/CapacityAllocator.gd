class_name CapacityAllocator
extends RefCounted

## One-time capacity-resource allocation, shared by BuildingManager
## (construction)/BuildingHealthController (repair/demolish/ruin refund) and
## UnitManager (training/retraining/death). ENERGY and POPULATION are both
## design_doc.md §2 "Capacity & Yield Pools" resources, and both work
## identically here: a consumer's daily_upkeep[type] is paid once when it
## starts drawing capacity; a producer's daily_output[type] is granted once
## when it starts contributing capacity. Both reverse the instant the
## consumer/producer stops (building ruin/demolish, unit death/disband/
## retrain-swap). Not a recurring per-day flow — BuildingSustenanceController
## and UnitManager._on_day_completed() both exclude CAPACITY_RESOURCE_TYPES
## from their daily tallies, so this is the only place either one moves for
## these entries.
##
## Duck-typed on `definition` (accessed via Object.get(), not a static
## property read) rather than a shared base class — BuildingDefinition and
## UnitDefinition both expose `daily_upkeep`/`daily_output: Dictionary` but
## share no common typed ancestor beyond Resource. Was BuildingEnergyAllocator
## (ENERGY-only), then BuildingCapacityAllocator (building-only, POPULATION
## added), before UnitDefinition adopted the same capacity-pool mechanics —
## generalized here a second time rather than duplicating this logic into a
## parallel unit-only class.

const CAPACITY_RESOURCE_TYPES: Array[GameEnums.ResourceType] = [
	GameEnums.ResourceType.ENERGY,
	GameEnums.ResourceType.POPULATION,
]

var _resource_manager: ResourceManager

func _init(resource_manager: ResourceManager) -> void:
	_resource_manager = resource_manager

func cost(definition: Resource) -> Dictionary:
	var upkeep: Dictionary = definition.get("daily_upkeep")
	var result: Dictionary = {}
	for resource_type in CAPACITY_RESOURCE_TYPES:
		var amount := float(upkeep.get(resource_type, 0.0))
		if amount > 0.0:
			result[resource_type] = amount
	return result

func apply(definition: Resource) -> void:
	if not _resource_manager:
		return
	var c := cost(definition)
	if not c.is_empty():
		_resource_manager.spend(c)
	var output: Dictionary = definition.get("daily_output")
	for resource_type in CAPACITY_RESOURCE_TYPES:
		var granted := float(output.get(resource_type, 0.0))
		if granted > 0.0:
			_resource_manager.add(resource_type, granted)

func refund(definition: Resource) -> void:
	if not _resource_manager:
		return
	var upkeep: Dictionary = definition.get("daily_upkeep")
	var output: Dictionary = definition.get("daily_output")
	for resource_type in CAPACITY_RESOURCE_TYPES:
		var refunded := float(upkeep.get(resource_type, 0.0))
		if refunded > 0.0:
			_resource_manager.add(resource_type, refunded)
		var withdrawn := float(output.get(resource_type, 0.0))
		if withdrawn > 0.0:
			_resource_manager.remove(resource_type, withdrawn)
