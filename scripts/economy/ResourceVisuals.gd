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
		GameEnums.ResourceType.ENERGY:
			return "Energy"
		GameEnums.ResourceType.GUNPOWDER:
			return "Gunpowder"
		GameEnums.ResourceType.RESEARCH_POINTS:
			return "Research"
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
## then the Phase 2.9 Tech Tree's progression currency, then construction
## materials) — used anywhere resources are listed so every UI element reads
## left-to-right the same way.
static func display_order() -> Array[GameEnums.ResourceType]:
	return [
		GameEnums.ResourceType.FOOD,
		GameEnums.ResourceType.ENERGY,
		GameEnums.ResourceType.GUNPOWDER,
		GameEnums.ResourceType.RESEARCH_POINTS,
		GameEnums.ResourceType.WOOD,
		GameEnums.ResourceType.BRICKS,
		GameEnums.ResourceType.CAST_IRON,
		GameEnums.ResourceType.REINFORCED_CONCRETE,
	]

## Lazily-loaded, cached icon for the resource bar (user request, this pass
## — see `assets/icons/README.md`) — same `ResourceLoader.exists()`-gated-
## null pattern every other `*Visuals.gd` in this project already follows.
## `null` (no icon authored yet) is a legitimate, expected steady state, not
## an error — `ResourceBarView` falls back to text-only exactly as it does
## today for any resource with no icon yet.
static var _icon_cache: Dictionary = {}  # GameEnums.ResourceType -> Texture2D (nullable)

static func icon(resource_type: GameEnums.ResourceType) -> Texture2D:
	if not _icon_cache.has(resource_type):
		_icon_cache[resource_type] = _load_icon(resource_type)
	return _icon_cache[resource_type]

## Matches assets/icons/<key>.png exactly — see that folder's own file list.
static func _icon_key(resource_type: GameEnums.ResourceType) -> String:
	match resource_type:
		GameEnums.ResourceType.FOOD:
			return "food"
		GameEnums.ResourceType.ENERGY:
			return "energy"
		GameEnums.ResourceType.GUNPOWDER:
			return "gunpowder"
		GameEnums.ResourceType.RESEARCH_POINTS:
			return "research"
		GameEnums.ResourceType.WOOD:
			return "wood"
		GameEnums.ResourceType.BRICKS:
			return "bricks"
		GameEnums.ResourceType.CAST_IRON:
			return "cast_iron"
		GameEnums.ResourceType.REINFORCED_CONCRETE:
			return "concrete"
		_:
			return ""

static func _load_icon(resource_type: GameEnums.ResourceType) -> Texture2D:
	var key := _icon_key(resource_type)
	if key.is_empty():
		return null
	var path := "res://assets/icons/%s.png" % key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
