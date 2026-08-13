class_name BuildingCatalog
extends RefCounted

## Static seed data for the 19th-century building tree — plays the same
## "single source of truth" role for buildings that BritishGeographyData
## plays for the hex grid, kept separate from BuildingManager (the runtime
## system that places/tracks instances).
##
## Town Hall and Garrison are added under Housing & Civil (civic seat /
## militia HQ) so ZoneOfControlType.CIVILIAN/MILITARY have a source building
## to come from.
##
## Unlike BritishGeographyData (built once per map generation),
## get_definition() is expected to be called on every placement attempt, so
## the definitions are built lazily and cached rather than rebuilt each call.

const _POOR_SOIL_ONLY: Array[GameEnums.SoilFertility] = [GameEnums.SoilFertility.LUSH, GameEnums.SoilFertility.POOR]

static var _definitions_by_type: Dictionary = {}  # GameEnums.BuildingType -> BuildingDefinition

static func get_definition(building_type: GameEnums.BuildingType) -> BuildingDefinition:
	_ensure_built()
	return _definitions_by_type.get(building_type)

static func get_all_definitions() -> Array[BuildingDefinition]:
	_ensure_built()
	var result: Array[BuildingDefinition] = []
	result.assign(_definitions_by_type.values())
	return result

static func get_definitions_in_category(category: GameEnums.BuildingCategory) -> Array[BuildingDefinition]:
	_ensure_built()
	var result: Array[BuildingDefinition] = []
	for definition: BuildingDefinition in _definitions_by_type.values():
		if definition.category == category:
			result.append(definition)
	return result

static func _ensure_built() -> void:
	if not _definitions_by_type.is_empty():
		return
	for definition in _build_definitions():
		_definitions_by_type[definition.building_type] = definition

static func _build_definitions() -> Array[BuildingDefinition]:
	return [
		_terraced_tenement(), _workhouse(), _church_steeple_watchtower(),
		_gas_streetlamp(), _telegraph_relay_office(), _steam_printing_press(),
		_town_hall(), _garrison(),
		_timber_camp(),
		_clay_brickworks(), _charcoal_kiln(), _coal_pithead(),
		_cast_iron_foundry(), _saltpetre_powder_mill(), _forward_ammo_dump(),
		_tenant_farm(), _grain_silo(),
		_searchlight_tower(), _ditch(), _oil_pit(),
	]
	# _cattle_yard() deliberately omitted: "Remove Cattle Yard for now"
	# (user feedback) — the function stays below, unreferenced, so
	# re-adding it later is a one-line change.

# --- Housing & Civil -------------------------------------------------------

## Display name only — "terraced tenement can simply be called 'Houses'"
## (user feedback). BuildingType.TERRACED_TENEMENT (the enum/save-data
## identifier) is untouched.
static func _terraced_tenement() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TERRACED_TENEMENT, "Houses")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.WOOD: 40, GameEnums.ResourceType.BRICKS: 60}
	d.population_provided = 12
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

static func _workhouse() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.WORKHOUSE, "Workhouse")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.WOOD: 30, GameEnums.ResourceType.BRICKS: 80}
	d.population_provided = 20
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

## Display name only — "'Church steeple watchtower' should just be called
## 'Watchtower'" (user feedback). BuildingType stays CHURCH_STEEPLE_WATCHTOWER.
static func _church_steeple_watchtower() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CHURCH_STEEPLE_WATCHTOWER, "Watchtower")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 100, GameEnums.ResourceType.CAST_IRON: 10}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	# Doubles as a lookout post (Military) and a parish church (Civilian) — see class doc.
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY, GameEnums.ZoneOfControlType.CIVILIAN]
	d.vision_radius = 2  # Tallest structure in town — a proper watchtower lookout.
	d.lit_at_night = true  # "Watchtower searchlights" hold/extend vision after dark.
	return d

## Display name shortened per user feedback.
static func _gas_streetlamp() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GAS_STREETLAMP, "Streetlamp")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.CAST_IRON: 15}
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 1.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.vision_radius = 1  # Lights the surrounding street, not just its own hex.
	d.lit_at_night = true  # Literally the design doc's example of a lit source.
	return d

## Display name shortened per user feedback.
static func _telegraph_relay_office() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TELEGRAPH_RELAY_OFFICE, "Telegraph Relay")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.WOOD: 20, GameEnums.ResourceType.CAST_IRON: 20}
	# Knowledge/civic source for the Tech Tree — telegraph traffic
	# between settlements is the natural in-fiction source of Research Points.
	d.daily_output = {GameEnums.ResourceType.RESEARCH_POINTS: 3.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.CIVILIAN]
	return d

## Display name shortened per user feedback.
static func _steam_printing_press() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.STEAM_PRINTING_PRESS, "Printing Press")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.WOOD: 25, GameEnums.ResourceType.CAST_IRON: 30}
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 2.0}
	# Knowledge/civic source for the Tech Tree — a press turning
	# out journals/pamphlets/technical bulletins is the other natural source.
	d.daily_output = {GameEnums.ResourceType.RESEARCH_POINTS: 4.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

static func _town_hall() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TOWN_HALL, "Town Hall")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 150, GameEnums.ResourceType.CAST_IRON: 40}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.CIVILIAN]
	# Without this, a brand-new colony's ONLY vision source is radius 0 (its
	# own single hex) — Town Hall is BuildingManager.seed_starting_buildings()'s
	# free opening move, so turn one would show one hex of a country-sized
	# map and nothing else. Smaller than the dedicated Watchtower lookout's 2.
	d.vision_radius = 1
	return d

static func _garrison() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GARRISON, "Garrison")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 90, GameEnums.ResourceType.CAST_IRON: 25}
	d.daily_upkeep = {GameEnums.ResourceType.GUNPOWDER: 3.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.can_train_units = true
	return d

# --- Industry & Extraction --------------------------------------------------

## "Add a timber camp please and balance it" (user feedback) — the ONLY Wood
## producer in the tree; every other raw construction material had a
## dedicated extractor already, Wood never did (simulating a realistic
## opening showed Wood running to zero with no income anywhere). Doesn't
## cost Wood itself (unlike Clay Brickworks, which spends Wood to make
## Bricks) — it's the resource's own bootstrap. FARMLAND/MOORLAND/HIGHLAND
## only (excluding URBAN/INDUSTRIAL, unlike Clay Brickworks/Cast Iron
## Foundry) — timber cut from wild land, not a refinery.
static func _timber_camp() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TIMBER_CAMP, "Timber Camp")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 20}
	d.daily_output = {GameEnums.ResourceType.WOOD: 10.0}
	d.allowed_biomes = [GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.HIGHLAND]
	d.noise_output = 2  # Axes/saws/cartage — quieter than a kiln or foundry, louder than nothing.
	return d

## Display name shortened per user feedback.
static func _clay_brickworks() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CLAY_BRICKWORKS, "Brickworks")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 50}
	# "Raise output of brickworks" (user feedback): 8 -> 14/day. Bricks was
	# the tightest early bottleneck — Workhouse (80), Garrison (90),
	# Saltpetre Mill (60), Church Watchtower (100) all draw the same
	# 100-unit starting stock; at 8/day a realistic opening never reached an
	# affordable Garrison within a simulated month. At 14/day: Garrison by
	# ~day 12, Saltpetre Mill by ~day 6.
	d.daily_output = {GameEnums.ResourceType.BRICKS: 14.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.URBAN]
	d.noise_output = 3  # Kilns firing — a Threat Meter source.
	return d

static func _charcoal_kiln() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CHARCOAL_KILN, "Charcoal Kiln")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 35}
	d.daily_upkeep = {GameEnums.ResourceType.WOOD: 10.0}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 6.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.FARMLAND]
	d.noise_output = 3
	return d

## Display name shortened per user feedback.
static func _coal_pithead() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.COAL_PITHEAD, "Coal Pit")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 60, GameEnums.ResourceType.CAST_IRON: 20}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 10.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.HIGHLAND]
	d.noise_output = 5  # Winding gear/heavy machinery — louder than a surface kiln.
	return d

## Display name shortened per user feedback.
static func _cast_iron_foundry() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CAST_IRON_FOUNDRY, "Iron Foundry")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 70, GameEnums.ResourceType.CAST_IRON: 30}
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 8.0}
	d.daily_output = {GameEnums.ResourceType.CAST_IRON: 5.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.URBAN]
	d.noise_output = 6  # Hammering/casting — the loudest single source in the tree today.
	return d

## Display name shortened per user feedback.
static func _saltpetre_powder_mill() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SALTPETRE_POWDER_MILL, "Gunpowder Mill")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 60, GameEnums.ResourceType.WOOD: 20}
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 4.0}
	d.daily_output = {GameEnums.ResourceType.GUNPOWDER: 6.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL]
	d.noise_output = 4
	return d

static func _forward_ammo_dump() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.FORWARD_AMMO_DUMP, "Forward Ammo Dump")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 25, GameEnums.ResourceType.CAST_IRON: 10}
	d.daily_upkeep = {GameEnums.ResourceType.GUNPOWDER: 2.0}
	# No biome/settlement restriction on purpose — its whole role (2.3) is projecting
	# Military ZoC out into not-yet-secured frontier hexes.
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	return d

# --- Agriculture -------------------------------------------------------------

## Display name shortened per user feedback.
static func _tenant_farm() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TENANT_FARM, "Farm")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.construction_cost = {GameEnums.ResourceType.WOOD: 30}
	d.daily_output = {GameEnums.ResourceType.FOOD: 10.0}
	d.allowed_biomes = [GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND]
	d.allowed_soil_fertility = _POOR_SOIL_ONLY
	d.soil_fertility_scales_output = true
	return d

static func _grain_silo() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GRAIN_SILO, "Grain Silo")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.construction_cost = {GameEnums.ResourceType.WOOD: 40, GameEnums.ResourceType.BRICKS: 20}
	d.storage_bonus = {GameEnums.ResourceType.FOOD: 150.0}
	d.allowed_biomes = [GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.URBAN]
	return d

static func _cattle_yard() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CATTLE_YARD, "Cattle Yard")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.construction_cost = {GameEnums.ResourceType.WOOD: 35}
	d.daily_output = {GameEnums.ResourceType.FOOD: 6.0}
	d.allowed_biomes = [GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND]
	d.allowed_soil_fertility = _POOR_SOIL_ONLY
	d.soil_fertility_scales_output = true
	return d

# --- Defense Works ----------------------------------------------

static func _searchlight_tower() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SEARCHLIGHT_TOWER, "Searchlight Tower")
	d.category = GameEnums.BuildingCategory.DEFENSE_WORKS
	d.construction_cost = {GameEnums.ResourceType.CAST_IRON: 35, GameEnums.ResourceType.BRICKS: 20}
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 3.0}
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.vision_radius = 2  # Illuminates the perimeter beyond its own hex, same role as the Watchtower.
	d.lit_at_night = true  # "Illuminate perimeter walls during night defense" — holds/extends vision after dark.
	# "granting combat bonuses to garrisoned units" still needs the unit and
	# garrison-order systems to exist before there's anything to grant a
	# bonus TO — not implemented, deliberately.
	return d

static func _ditch() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.DITCH, "Ditch")
	d.category = GameEnums.BuildingCategory.DEFENSE_WORKS
	d.construction_cost = {GameEnums.ResourceType.WOOD: 10}
	# Placed via WallManager.add_defense_work(), not BuildingManager.place_building()
	# — see WallManager's own class doc comment for why. This definition
	# exists purely so its construction_cost is authored in the same place
	# as every other building's, not because it occupies a hex position.
	return d

static func _oil_pit() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.OIL_PIT, "Oil Pit")
	d.category = GameEnums.BuildingCategory.DEFENSE_WORKS
	d.construction_cost = {GameEnums.ResourceType.WOOD: 15, GameEnums.ResourceType.ENERGY: 10}
	# See _ditch() — same "cost data only, placed via WallManager" note.
	return d
