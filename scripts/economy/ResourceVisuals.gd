class_name ResourceVisuals
extends RefCounted

## Shared display metadata for GameEnums.ResourceType — human-readable name
## and a stable left-to-right ordering, the same "single shared lookup"
## pattern as BuildingVisuals.category_color()/FogVisuals.tint_color() so
## the resource bar and the build menu's cost text agree.

static func display_name(resource_type: GameEnums.ResourceType) -> String:
	match resource_type:
		GameEnums.ResourceType.FOOD:
			return "Food"
		GameEnums.ResourceType.ENERGY:
			return "Energy"
		GameEnums.ResourceType.POPULATION:
			return "Population"
		GameEnums.ResourceType.RESEARCH_POINTS:
			return "Research"
		GameEnums.ResourceType.WOOD:
			return "Wood"
		GameEnums.ResourceType.CLAY:
			return "Clay"
		GameEnums.ResourceType.COAL:
			return "Coal"
		GameEnums.ResourceType.LIMESTONE:
			return "Limestone"
		GameEnums.ResourceType.IRON_ORE:
			return "Iron Ore"
		GameEnums.ResourceType.SULFUR:
			return "Sulfur"
		GameEnums.ResourceType.BRICKS:
			return "Bricks"
		GameEnums.ResourceType.IRON:
			return "Iron"
		GameEnums.ResourceType.STEEL:
			return "Steel"
		GameEnums.ResourceType.CONCRETE:
			return "Concrete"
		GameEnums.ResourceType.GUNPOWDER:
			return "Gunpowder"
		_:
			return "Unknown"

## design_doc.md §2's own grouping (Capacity & Yield / Raw / Processed),
## capacity/yield first since that's what the resource bar has always led
## with — used anywhere resources are listed so every UI element reads
## left-to-right the same way.
static func display_order() -> Array[GameEnums.ResourceType]:
	return [
		GameEnums.ResourceType.FOOD,
		GameEnums.ResourceType.ENERGY,
		GameEnums.ResourceType.POPULATION,
		GameEnums.ResourceType.RESEARCH_POINTS,
		GameEnums.ResourceType.WOOD,
		GameEnums.ResourceType.CLAY,
		GameEnums.ResourceType.COAL,
		GameEnums.ResourceType.LIMESTONE,
		GameEnums.ResourceType.IRON_ORE,
		GameEnums.ResourceType.SULFUR,
		GameEnums.ResourceType.BRICKS,
		GameEnums.ResourceType.IRON,
		GameEnums.ResourceType.STEEL,
		GameEnums.ResourceType.CONCRETE,
		GameEnums.ResourceType.GUNPOWDER,
	]

## Lazily-loaded, cached icon for the resource bar (see assets/icons/README.md)
## — same ResourceLoader.exists()-gated-null pattern every other *Visuals.gd
## in this project follows. null (no icon authored yet) is a legitimate,
## expected steady state, not an error — ResourceBarView falls back to
## text-only for any resource with no icon yet. Most of the new raw
## resources (Clay/Coal/Limestone/Iron Ore/Sulfur/Steel/Population) have no
## icon asset yet — expected until the Building tree rework actually puts
## them into play.
static var _icon_cache: Dictionary = {}  # GameEnums.ResourceType -> Texture2D (nullable)

static func icon(resource_type: GameEnums.ResourceType) -> Texture2D:
	if not _icon_cache.has(resource_type):
		_icon_cache[resource_type] = _load_icon(resource_type)
	return _icon_cache[resource_type]

## Matches assets/icons/<key>.png exactly — see that folder's own file list.
## IRON/CONCRETE deliberately map to the pre-rework "cast_iron"/"concrete"
## filenames rather than requiring an asset rename — same "enum identifier
## and asset/display name can diverge" convention BuildingCatalog already
## uses (e.g. ARMORY_AND_BARRACKS displays as "Armory & Barracks").
static func _icon_key(resource_type: GameEnums.ResourceType) -> String:
	match resource_type:
		GameEnums.ResourceType.FOOD:
			return "food"
		GameEnums.ResourceType.ENERGY:
			return "energy"
		GameEnums.ResourceType.POPULATION:
			return "population"
		GameEnums.ResourceType.RESEARCH_POINTS:
			return "research"
		GameEnums.ResourceType.WOOD:
			return "wood"
		GameEnums.ResourceType.CLAY:
			return "clay"
		GameEnums.ResourceType.COAL:
			return "coal"
		GameEnums.ResourceType.LIMESTONE:
			return "limestone"
		GameEnums.ResourceType.IRON_ORE:
			return "iron_ore"
		GameEnums.ResourceType.SULFUR:
			return "sulfur"
		GameEnums.ResourceType.BRICKS:
			return "bricks"
		GameEnums.ResourceType.IRON:
			return "cast_iron"
		GameEnums.ResourceType.STEEL:
			return "steel"
		GameEnums.ResourceType.CONCRETE:
			return "concrete"
		GameEnums.ResourceType.GUNPOWDER:
			return "gunpowder"
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
