class_name SupplyLineVisuals
extends RefCounted

## Texture lookup for Infrastructure (Road/Railway/Canal/Bridge) art — the
## `*Visuals.gd` texture-cache convention every other category already
## follows (BuildingVisuals.building_texture(), WallVisuals.tier_texture()).
## One texture per GameEnums.SupplyLineType, not per tier — BuildMenuView's
## own icon grid only ever shows one icon per line type
## (_build_infrastructure_column()), so a tier-specific set of textures
## would have no display-menu consumer yet; the rendered art itself picks
## one representative tier per type (see each models/infrastructure/*.py
## script's own doc comment) rather than rendering 9 separate tier images
## nothing currently shows.

static var _texture_cache: Dictionary = {}  # GameEnums.SupplyLineType -> Texture2D (nullable)

static func line_texture(line_type: GameEnums.SupplyLineType) -> Texture2D:
	if not _texture_cache.has(line_type):
		_texture_cache[line_type] = _load_texture(line_type)
	return _texture_cache[line_type]

static func _texture_key(line_type: GameEnums.SupplyLineType) -> String:
	match line_type:
		GameEnums.SupplyLineType.ROAD:
			return "road"
		GameEnums.SupplyLineType.RAILWAY:
			return "railway"
		GameEnums.SupplyLineType.CANAL:
			return "canal"
		GameEnums.SupplyLineType.BRIDGE:
			return "bridge"
		_:
			return ""

static func _load_texture(line_type: GameEnums.SupplyLineType) -> Texture2D:
	var key := _texture_key(line_type)
	if key.is_empty():
		return null
	var path := "res://assets/infrastructure/%s.png" % key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
