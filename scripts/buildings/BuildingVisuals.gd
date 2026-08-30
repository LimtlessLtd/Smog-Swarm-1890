class_name BuildingVisuals
extends RefCounted

## Shared placeholder color-by-category lookup for anything that draws a
## building as a plain colored shape before real art exists — TacticalHexView's
## close-up building boxes and BuildingMarkerRenderer's zoomed-out building
## icons both call this, so a given category reads as the same color in
## both views instead of two copy-pasted match blocks silently drifting apart.
##
## building_texture() below is the buildings equivalent of
## TerrainVisuals.terrain_texture() — additive, not a replacement.
## category_color()/ruin_color() stay the fallback (the Strategic-zoom
## triangle marker is a symbolic map glyph, not a spot to show sprite
## detail at that scale — Strategic's icon rendering doesn't consult
## fidelity at all) and what TacticalHexView itself falls back to for any
## building type with no SVG authored yet.

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

## A ruined building's color — the SAME drab grey-brown regardless of what
## category it used to be (rubble doesn't read as "industrial" or "civic"
## anymore), shared between TacticalHexView's close-up rubble shape and
## BuildingMarkerRenderer's icon so a ruin reads the same way in both
## views, same reasoning category_color() gives for intact buildings.
static func ruin_color() -> Color:
	return Color(0.4, 0.37, 0.34)

## "Buildings should be visible while under construction (tint them black
## or gray while under construction)" (user feedback) — a flat dark grey,
## distinct from ruin_color()'s warmer rubble tone so a half-built
## structure never reads as an already-destroyed one. Shared between
## TacticalHexView (multiplied into modulate, over whatever real
## sprite/category color the finished building will use) and
## BuildingMarkerRenderer (assigned directly to its flat icon color, same
## split ruin_color() has between the two call sites).
static func construction_color() -> Color:
	return Color(0.32, 0.32, 0.32)

## design_doc.md §2.1's "Going dark" — a switched-off building. A cold blue-
## grey, readable against both of the greys above at a glance:
## construction_color() is neutral-dark and ruin_color() is warm, so "off"
## reads as neither half-built nor destroyed. Shared between TacticalHexView
## (multiplied into modulate over the real sprite) and BuildingMarkerRenderer
## (assigned to the flat icon color), the same split ruin_color() and
## construction_color() already have.
##
## Value picked by rendering the candidates over a real building sprite
## (tools note: scripts/test/preview_going_dark.gd captures the pair), not by
## choosing numbers. The first try, 0.38/0.44/0.52, multiplied a warm wooden
## roof down to near-black and read as charred rather than idle — modulate
## MULTIPLIES, so a tint that looks mid-grey as a swatch lands much darker on
## a mid-tone sprite, and the game's own night ambient multiplies again on top
## of that. This is bright enough that the building stays identifiable (the
## player has to know WHICH thing they switched off) and blue enough that it
## cannot be mistaken for construction_color()'s neutral dark.
static func powered_down_color() -> Color:
	return Color(0.50, 0.56, 0.68)

## Lazily-loaded, cached (same "build once, cache" convention TerrainVisuals'
## own terrain_texture() and BuildingCatalog/UnitCatalog's _ensure_built()
## use) — the real sprite for a building type, or null if no SVG has been
## authored yet at assets/buildings/<key>.svg. ResourceLoader.exists()
## before load() means an unauthored type fails cleanly to null (no
## console error spam) rather than throwing — this is what lets art land
## incrementally with zero code changes needed elsewhere. Never called for
## a ruin — TacticalHexView keeps drawing ruins as the jagged code-drawn
## silhouette (ruin_color() above); a collapsed building doesn't have
## "art" the way a standing one does.
static var _texture_cache: Dictionary = {}  # GameEnums.BuildingType -> Texture2D (nullable)

static func building_texture(building_type: GameEnums.BuildingType) -> Texture2D:
	if not _texture_cache.has(building_type):
		_texture_cache[building_type] = _load_texture(building_type)
	return _texture_cache[building_type]

## Matches assets/buildings/<key>.png exactly (Blender pipeline — see
## tools/blender_pipeline/README.md; buildings are static, single-facing,
## no directional suffix). Extended to cover all 42 BuildingCatalog types
## (previously only 14 — the Building tree rework added 28 more
## BuildingType values that this function silently never routed to any
## art, permanently stuck on category_color() regardless of what existed
## in assets/buildings/). The 14 pre-rework keys below keep their existing,
## sometimes-divergent filenames (e.g. LUMBER_YARD -> "timber_camp") since
## real art already exists at those paths; every newly-routed key below is
## simply the enum's own BuildingCatalog._<key>() function name, no
## divergence to preserve.
static func _texture_key(building_type: GameEnums.BuildingType) -> String:
	match building_type:
		GameEnums.BuildingType.TOWN_HALL:
			return "town_hall"
		GameEnums.BuildingType.LUMBER_YARD:
			return "timber_camp"
		GameEnums.BuildingType.SMALLHOLDING_FARM:
			return "tenant_farm"
		GameEnums.BuildingType.WOODEN_HOUSES:
			return "terraced_tenement"
		GameEnums.BuildingType.WATCHTOWER:
			return "watchtower"
		GameEnums.BuildingType.COAL_MINE:
			return "coal_pithead"
		GameEnums.BuildingType.BRICKWORKS:
			return "clay_brickworks"
		GameEnums.BuildingType.RESEARCH_INSTITUTE:
			return "steam_printing_press"
		GameEnums.BuildingType.BRICK_HOUSES:
			return "workhouse"
		GameEnums.BuildingType.GARRISON:
			return "garrison"
		GameEnums.BuildingType.SUPPLY_DUMP:
			return "forward_ammo_dump"
		GameEnums.BuildingType.IRON_FOUNDRY:
			return "cast_iron_foundry"
		GameEnums.BuildingType.SEARCH_LIGHT:
			return "searchlight_tower"
		GameEnums.BuildingType.GUNPOWDER_MILL:
			return "saltpetre_powder_mill"
		# Below: previously unrouted (Building tree rework added these
		# BuildingType values without ever giving BuildingVisuals a key for
		# them) — key is just the enum's own catalog function name.
		GameEnums.BuildingType.CLAY_PIT:
			return "clay_pit"
		GameEnums.BuildingType.STEAM_FURNACE:
			return "steam_furnace"
		GameEnums.BuildingType.LIMESTONE_QUARRY:
			return "limestone_quarry"
		GameEnums.BuildingType.ESTATE_FARM:
			return "estate_farm"
		GameEnums.BuildingType.COAL_POWERPLANT:
			return "coal_powerplant"
		GameEnums.BuildingType.IRON_ORE_MINE:
			return "iron_ore_mine"
		GameEnums.BuildingType.CONCRETE_PLANT:
			return "concrete_plant"
		GameEnums.BuildingType.INDUSTRIAL_FARM:
			return "industrial_farm"
		GameEnums.BuildingType.TOWER_BLOCKS:
			return "tower_blocks"
		GameEnums.BuildingType.ARMORY_AND_BARRACKS:
			return "armory_and_barracks"
		GameEnums.BuildingType.SULFUR_MINE:
			return "sulfur_mine"
		GameEnums.BuildingType.DEEP_COAL_SHAFTS:
			return "deep_coal_shafts"
		GameEnums.BuildingType.SAWMILLS:
			return "sawmills"
		GameEnums.BuildingType.STEELWORKS:
			return "steelworks"
		GameEnums.BuildingType.MECHANISED_FARM:
			return "mechanised_farm"
		GameEnums.BuildingType.ADVANCED_COAL_POWERPLANT:
			return "advanced_coal_powerplant"
		GameEnums.BuildingType.HIGH_COMMAND_AND_CAVALRY_DEPOT:
			return "high_command_and_cavalry_depot"
		GameEnums.BuildingType.STEAM_EXCAVATOR_DEPOT:
			return "steam_excavator_depot"
		GameEnums.BuildingType.HEAVY_COAL_WASHERY_AND_PULVERIZER:
			return "heavy_coal_washery_and_pulverizer"
		GameEnums.BuildingType.MECHANIZED_MAINTENANCE_DEPOT:
			return "mechanized_maintenance_depot"
		GameEnums.BuildingType.MACADAMIZED_TRANSPORT_HUB:
			return "macadamized_transport_hub"
		GameEnums.BuildingType.STEAM_TURBINE_POWER_PLANT:
			return "steam_turbine_power_plant"
		GameEnums.BuildingType.TRACTION_WORKS_AND_WORKSHOP:
			return "traction_works_and_workshop"
		GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX:
			return "bessemer_smelting_complex"
		GameEnums.BuildingType.AUTOMATED_FREIGHT_MARSHALLING_YARD:
			return "automated_freight_marshalling_yard"
		GameEnums.BuildingType.SYNTHETIC_CHEMICAL_REFINERY:
			return "synthetic_chemical_refinery"
		GameEnums.BuildingType.CENTRAL_HIGH_VOLTAGE_GRID_STATION:
			return "central_high_voltage_grid_station"
		GameEnums.BuildingType.ORDNANCE_AND_ARMAMENT_COMPLEX:
			return "ordnance_and_armament_complex"
		_:
			return ""

## Real AI-generated building art (see assets/buildings/README.md)
## supersedes the hand-drawn SVGs, checked FIRST. A .png at this building's
## key wins if present; otherwise falls through to the existing .svg;
## otherwise null (category_color() fallback) — art lands incrementally,
## one building at a time, zero further code changes needed, same
## contract every other *Visuals.gd in this project follows.
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
