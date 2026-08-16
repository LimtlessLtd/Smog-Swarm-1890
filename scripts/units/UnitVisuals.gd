class_name UnitVisuals
extends RefCounted

## Shared, lazily-loaded/cached unit_type -> Texture2D lookup, same
## ResourceLoader.exists()-gated-null contract as BuildingVisuals.building_texture()/
## TerrainVisuals.terrain_texture(): an unauthored type fails cleanly to
## null rather than throwing, so real art can land one unit at a time with
## zero code changes elsewhere — exactly the "art lands incrementally"
## precedent those two classes already established.
##
## Unlike terrain/buildings (both hand-authored SVG in the end — see
## todo.md), unit art is decided to stay AI-generated (user's explicit
## call) — hence PNG here, not SVG. PNG sidesteps the
## exact bug hand-authored SVG hit twice on this project (Godot's ThorVG
## importer silently rasterizes `<pattern>` fills as fully transparent) by
## construction: it's raster, there's no vector fill-rule involved at all.
## See assets/units/README.md for the full generation pipeline (style guide
## + one prompt per unit) — no image-generation tool exists in this Claude
## Code environment, so this lookup is real, tested infrastructure sitting
## ready for images nobody has generated yet. `ResourceLoader.exists()`
## returning false for all 18 today is the EXPECTED state, not a bug.
##
## Consumed by TacticalEntityLayer at MEDIUM and HIGH Tactical fidelity
## only — LOW fidelity is a deliberately uniform per-category blob
## regardless of unit type (see that class's own doc comment) and never
## calls this at all. One texture per unit, reused at both fidelity bands
## (scaled differently) rather than separate generated assets per band —
## see todo.md for why that's a decision, not a shortfall.

static var _texture_cache: Dictionary = {}  # GameEnums.UnitType -> Texture2D (nullable)

static func unit_texture(unit_type: GameEnums.UnitType) -> Texture2D:
	if not _texture_cache.has(unit_type):
		_texture_cache[unit_type] = _load_texture(unit_type)
	return _texture_cache[unit_type]

## Matches assets/units/<key>.png exactly — see that folder's own README
## for the generation prompt keyed to each of these.
static func _texture_key(unit_type: GameEnums.UnitType) -> String:
	match unit_type:
		GameEnums.UnitType.TRUNCHEONEER:
			return "truncheoneer"
		GameEnums.UnitType.TOXOPHILITE:
			return "toxophilite"
		GameEnums.UnitType.OUTRIDER:
			return "outrider"
		GameEnums.UnitType.NAVVY:
			return "navvy"
		GameEnums.UnitType.YEOMAN_MARKSMAN:
			return "yeoman_marksman"
		GameEnums.UnitType.GRENADIER:
			return "grenadier"
		GameEnums.UnitType.BAYONETEER:  # Renamed from REDCOAT (design_doc.md §4 Tier 2 rename) — same melee character art, "redcoat" key unchanged.
			return "redcoat"
		GameEnums.UnitType.REDCOAT:  # Renamed from RIFLEMAN (design_doc.md §4 Tier 2 rename) — same ranged character art, "rifleman" key unchanged.
			return "rifleman"
		GameEnums.UnitType.CHASSEUR:
			return "chasseur"
		GameEnums.UnitType.HIGHLANDER:
			return "highlander"
		GameEnums.UnitType.SHARPSHOOTER:
			return "sharpshooter"
		GameEnums.UnitType.DRAGOON:
			return "dragoon"
		GameEnums.UnitType.TRACTION_RAM:
			return "traction_ram"
		GameEnums.UnitType.MAXIM_QUADRICYCLE:
			return "maxim_quadricycle"
		GameEnums.UnitType.SEARCHLIGHT_TENDER:
			return "searchlight_tender"
		GameEnums.UnitType.HOLT_BREAKER:
			return "holt_breaker"
		GameEnums.UnitType.FIELD_HOWITZER_GUN_TRACTOR:
			return "field_howitzer_gun_tractor"
		GameEnums.UnitType.ARMOURED_COMMAND_CAR:
			return "armoured_command_car"
		_:
			return ""

static func _load_texture(unit_type: GameEnums.UnitType) -> Texture2D:
	var key := _texture_key(unit_type)
	if key.is_empty():
		return null
	var path := "res://assets/units/%s.png" % key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
