class_name ResourceVisuals
extends RefCounted

## Shared display metadata for GameEnums.ResourceType — human-readable name
## and a stable left-to-right ordering, the same "single shared lookup"
## pattern as BuildingVisuals.category_color()/FogVisuals.tint_color() so
## the resource bar and the build menu's cost text (Phase 6.1) agree.

static func display_name(resource_type: GameEnums.ResourceType) -> String:
	match resource_type:
		GameEnums.ResourceType.FOOD:
			return "Food"
		GameEnums.ResourceType.COAL:
			return "Coal"
		GameEnums.ResourceType.GUNPOWDER:
			return "Gunpowder"
		GameEnums.ResourceType.WOOD:
			return "Wood"
		GameEnums.ResourceType.BRICKS:
			return "Bricks"
		GameEnums.ResourceType.CAST_IRON:
			return "Cast Iron"
		GameEnums.ResourceType.REINFORCED_CONCRETE:
			return "Concrete"
		_:
			return "Unknown"

## GameEnums.ResourceType's own declaration order (upkeep resources first,
## then construction materials) — used anywhere resources are listed so
## every UI element reads left-to-right the same way.
static func display_order() -> Array[GameEnums.ResourceType]:
	return [
		GameEnums.ResourceType.FOOD,
		GameEnums.ResourceType.COAL,
		GameEnums.ResourceType.GUNPOWDER,
		GameEnums.ResourceType.WOOD,
		GameEnums.ResourceType.BRICKS,
		GameEnums.ResourceType.CAST_IRON,
		GameEnums.ResourceType.REINFORCED_CONCRETE,
	]
