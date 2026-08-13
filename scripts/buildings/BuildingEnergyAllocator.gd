class_name BuildingEnergyAllocator
extends RefCounted

## One-time Energy grid allocation, shared by BuildingManager (construction)
## and BuildingHealthController (repair/demolish/ruin refund). A consumer's
## daily_upkeep[ENERGY] is paid once when it starts drawing power; a
## producer's daily_output[ENERGY] is granted once when it starts
## contributing. Both reverse the instant the building stops (ruin/demolish).
## Not a recurring per-day flow — BuildingSustenanceController excludes
## ResourceType.ENERGY from its daily tally so this is the only place ENERGY
## moves for these entries.

var _resource_manager: ResourceManager

func _init(resource_manager: ResourceManager) -> void:
	_resource_manager = resource_manager

func cost(definition: BuildingDefinition) -> Dictionary:
	var amount := float(definition.daily_upkeep.get(GameEnums.ResourceType.ENERGY, 0.0))
	return {GameEnums.ResourceType.ENERGY: amount} if amount > 0.0 else {}

func apply(definition: BuildingDefinition) -> void:
	if not _resource_manager:
		return
	var c := cost(definition)
	if not c.is_empty():
		_resource_manager.spend(c)
	var granted := float(definition.daily_output.get(GameEnums.ResourceType.ENERGY, 0.0))
	if granted > 0.0:
		_resource_manager.add(GameEnums.ResourceType.ENERGY, granted)

func refund(definition: BuildingDefinition) -> void:
	if not _resource_manager:
		return
	var refunded := float(definition.daily_upkeep.get(GameEnums.ResourceType.ENERGY, 0.0))
	if refunded > 0.0:
		_resource_manager.add(GameEnums.ResourceType.ENERGY, refunded)
	var withdrawn := float(definition.daily_output.get(GameEnums.ResourceType.ENERGY, 0.0))
	if withdrawn > 0.0:
		_resource_manager.remove(GameEnums.ResourceType.ENERGY, withdrawn)
