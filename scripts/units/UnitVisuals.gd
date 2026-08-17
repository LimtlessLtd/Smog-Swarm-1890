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
## calls this at all. One 8-facing set per unit, reused at both fidelity
## bands (scaled differently) rather than separate generated assets per
## band — see todo.md for why that's a decision, not a shortfall.
##
## `facing` picks which of a unit's 8 rendered directions to show
## (assets/units/<key>_<n|ne|e|se|s|sw|w|nw>.png — tools/blender_pipeline's
## render_directional_to() naming, FacingUtil.suffix() maps the enum to the
## suffix). Falls back to the old flat `<key>.png` if the specific facing
## hasn't been authored yet, then to null — the same incremental "art lands
## one piece at a time, zero code changes" contract this class always had,
## just with an extra rung.

static var _texture_cache: Dictionary = {}  # "<UnitType>_<Facing8>" -> Texture2D (nullable)

static func unit_texture(unit_type: GameEnums.UnitType, facing: GameEnums.Facing8 = GameEnums.Facing8.S) -> Texture2D:
	var cache_key := "%d_%d" % [unit_type, facing]
	if not _texture_cache.has(cache_key):
		_texture_cache[cache_key] = _load_texture(unit_type, facing)
	return _texture_cache[cache_key]

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

static func _load_texture(unit_type: GameEnums.UnitType, facing: GameEnums.Facing8) -> Texture2D:
	var key := _texture_key(unit_type)
	if key.is_empty():
		return null
	var directional_path := "res://assets/units/%s_%s.png" % [key, FacingUtil.suffix(facing)]
	if ResourceLoader.exists(directional_path):
		return load(directional_path) as Texture2D
	var flat_path := "res://assets/units/%s.png" % key  # Pre-directional single-facing art, if that's all that's been authored.
	if ResourceLoader.exists(flat_path):
		return load(flat_path) as Texture2D
	return null
