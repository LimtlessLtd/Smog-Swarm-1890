class_name BuildingVisuals
extends RefCounted

## Shared placeholder color-by-category lookup for anything that draws a
## building as a plain colored shape before real art exists — TacticalHexView's
## close-up building boxes and StrategicOverlayManager's zoomed-out building
## icons both call this, so a given category reads as the same color in both
## views instead of two copy-pasted match blocks silently drifting apart.
##
## Phase 6.3's real building art landed (same supersede-with-hand-authored-SVG
## call the user already made for terrain, 6.3.0): building_texture() below is
## the buildings equivalent of TerrainVisuals.terrain_texture() — additive,
## not a replacement. category_color()/ruin_color() are untouched and stay
## the fallback (StrategicOverlayManager's zoomed-out triangle marker is a
## symbolic map glyph, not a spot to show sprite detail at that scale — Phase
## 2.5.5 already decided Strategic's icon rendering doesn't consult fidelity
## at all, and the same "stay abstract" call applies here) and what
## TacticalHexView itself falls back to for any building type with no SVG
## authored yet.

static func category_color(category: GameEnums.BuildingCategory) -> Color:
	match category:
		GameEnums.BuildingCategory.HOUSING_CIVIL:
			return Color(0.55, 0.42, 0.30)
		GameEnums.BuildingCategory.INDUSTRY_EXTRACTION:
			return Color(0.35, 0.32, 0.34)
		GameEnums.BuildingCategory.AGRICULTURE:
			return Color(0.62, 0.55, 0.25)
		_:
			return Color(0.5, 0.5, 0.5)

## Design doc Phase 5.12: a ruined building's color — deliberately the SAME
## drab grey-brown regardless of what category it used to be (rubble
## doesn't read as "industrial" or "civic" anymore), shared between
## TacticalHexView's close-up rubble shape and StrategicOverlayManager's
## icon so a ruin reads the same way in both views, same reasoning
## category_color() itself already gives for intact buildings.
static func ruin_color() -> Color:
	return Color(0.4, 0.37, 0.34)

## Lazily-loaded, cached (same "build once, cache" convention TerrainVisuals'
## own terrain_texture() and BuildingCatalog/UnitCatalog's _ensure_built()
## already use) — the real sprite for a building type, or null if no SVG has
## been authored yet at assets/buildings/<key>.svg. ResourceLoader.exists()
## before load() means an unauthored type fails cleanly to null (no console
## error spam) rather than throwing, same reasoning as TerrainVisuals — this
## is what lets art land incrementally with zero code changes needed
## elsewhere. Never called for a ruin — TacticalHexView keeps drawing ruins as
## the jagged code-drawn silhouette (ruin_color() above), unchanged; a
## collapsed building doesn't have "art" the way a standing one does.
static var _texture_cache: Dictionary = {}  # GameEnums.BuildingType -> Texture2D (nullable)

static func building_texture(building_type: GameEnums.BuildingType) -> Texture2D:
	if not _texture_cache.has(building_type):
		_texture_cache[building_type] = _load_texture(building_type)
	return _texture_cache[building_type]

## Matches assets/buildings/<key>.svg exactly — see that folder's own file list.
static func _texture_key(building_type: GameEnums.BuildingType) -> String:
	match building_type:
		GameEnums.BuildingType.TERRACED_TENEMENT:
			return "terraced_tenement"
		GameEnums.BuildingType.WORKHOUSE:
			return "workhouse"
		GameEnums.BuildingType.CHURCH_STEEPLE_WATCHTOWER:
			return "church_steeple_watchtower"
		GameEnums.BuildingType.GAS_STREETLAMP:
			return "gas_streetlamp"
		GameEnums.BuildingType.TELEGRAPH_RELAY_OFFICE:
			return "telegraph_relay_office"
		GameEnums.BuildingType.STEAM_PRINTING_PRESS:
			return "steam_printing_press"
		GameEnums.BuildingType.TOWN_HALL:
			return "town_hall"
		GameEnums.BuildingType.GARRISON:
			return "garrison"
		GameEnums.BuildingType.CLAY_BRICKWORKS:
			return "clay_brickworks"
		GameEnums.BuildingType.CHARCOAL_KILN:
			return "charcoal_kiln"
		GameEnums.BuildingType.COAL_PITHEAD:
			return "coal_pithead"
		GameEnums.BuildingType.CAST_IRON_FOUNDRY:
			return "cast_iron_foundry"
		GameEnums.BuildingType.SALTPETRE_POWDER_MILL:
			return "saltpetre_powder_mill"
		GameEnums.BuildingType.FORWARD_AMMO_DUMP:
			return "forward_ammo_dump"
		GameEnums.BuildingType.TENANT_FARM:
			return "tenant_farm"
		GameEnums.BuildingType.GRAIN_SILO:
			return "grain_silo"
		GameEnums.BuildingType.CATTLE_YARD:
			return "cattle_yard"
		GameEnums.BuildingType.SEARCHLIGHT_TOWER:
			return "searchlight_tower"
		_:  # DITCH/OIL_PIT never reach here — placed via WallManager, never rendered as a BuildingInstance box (see WallManager's own doc comment).
			return ""

## User request (this pass): real AI-generated building art (see
## `assets/buildings/README.md`) is meant to eventually supersede the
## hand-drawn SVGs the same way those superseded the original flat-color
## placeholders — checked FIRST, not instead. A `.png` at this building's
## key wins if present; otherwise this falls through to the existing `.svg`
## exactly as before this pass; otherwise `null` (category_color() fallback,
## unchanged). No building loses its art the moment this shipped — every one
## of the 18 already-authored SVGs keeps rendering exactly as it does today
## until a nicer PNG actually replaces it, one building at a time, same
## "art lands incrementally, zero further code changes" contract every
## other `*Visuals.gd` in this project already follows.
static func _load_texture(building_type: GameEnums.BuildingType) -> Texture2D:
	var key := _texture_key(building_type)
	if key.is_empty():
		return null
	var png_path := "res://assets/buildings/%s.png" % key
	if ResourceLoader.exists(png_path):
		return load(png_path) as Texture2D
	var svg_path := "res://assets/buildings/%s.svg" % key
	if ResourceLoader.exists(svg_path):
		return load(svg_path) as Texture2D
	return null
