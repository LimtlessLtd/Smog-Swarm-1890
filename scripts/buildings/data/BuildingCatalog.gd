class_name BuildingCatalog
extends RefCounted

## Static seed data for the authentic 19th-century building tree (design doc
## Phase 2.1) — plays the same "single source of truth" role for buildings
## that BritishGeographyData plays for the hex grid, kept separate from
## BuildingManager (the runtime system that places/tracks instances).
##
## Town Hall and Garrison are not named in the Phase 2.1 checklist, but 2.3
## requires Civilian ZoC from "Town Halls" and Military ZoC from "Garrisons"
## as a source — they're added here under Housing & Civil (civic seat /
## militia HQ) so those Zone of Control roles have a building to come from.
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
		_clay_brickworks(), _charcoal_kiln(), _coal_pithead(),
		_cast_iron_foundry(), _saltpetre_powder_mill(), _forward_ammo_dump(),
		_tenant_farm(), _grain_silo(), _cattle_yard(),
	]

# --- Housing & Civil -------------------------------------------------------

static func _terraced_tenement() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TERRACED_TENEMENT, "Terraced Tenement")
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

static func _church_steeple_watchtower() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CHURCH_STEEPLE_WATCHTOWER, "Church Steeple Watchtower")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 100, GameEnums.ResourceType.CAST_IRON: 10}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	# Doubles as a lookout post (Military) and a parish church (Civilian) — see class doc.
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY, GameEnums.ZoneOfControlType.CIVILIAN]
	d.vision_radius = 2  # Tallest structure in town — a proper watchtower lookout (Phase 2.6).
	return d

static func _gas_streetlamp() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GAS_STREETLAMP, "Gas Streetlamp")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.CAST_IRON: 15}
	d.daily_upkeep = {GameEnums.ResourceType.COAL: 1.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.vision_radius = 1  # Lights the surrounding street, not just its own hex (Phase 2.6).
	return d

static func _telegraph_relay_office() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TELEGRAPH_RELAY_OFFICE, "Telegraph Relay Office")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.WOOD: 20, GameEnums.ResourceType.CAST_IRON: 20}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.CIVILIAN]
	return d

static func _steam_printing_press() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.STEAM_PRINTING_PRESS, "Steam Printing Press")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.WOOD: 25, GameEnums.ResourceType.CAST_IRON: 30}
	d.daily_upkeep = {GameEnums.ResourceType.COAL: 2.0}
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
	return d

static func _garrison() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GARRISON, "Garrison")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 90, GameEnums.ResourceType.CAST_IRON: 25}
	d.daily_upkeep = {GameEnums.ResourceType.GUNPOWDER: 3.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	return d

# --- Industry & Extraction --------------------------------------------------

static func _clay_brickworks() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CLAY_BRICKWORKS, "Clay Brickworks")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 50}
	d.daily_output = {GameEnums.ResourceType.BRICKS: 8.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.URBAN]
	return d

static func _charcoal_kiln() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CHARCOAL_KILN, "Charcoal Kiln")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 35}
	d.daily_upkeep = {GameEnums.ResourceType.WOOD: 10.0}
	d.daily_output = {GameEnums.ResourceType.COAL: 6.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.FARMLAND]
	return d

static func _coal_pithead() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.COAL_PITHEAD, "Coal Pithead")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.WOOD: 60, GameEnums.ResourceType.CAST_IRON: 20}
	d.daily_output = {GameEnums.ResourceType.COAL: 10.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.HIGHLAND]
	return d

static func _cast_iron_foundry() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CAST_IRON_FOUNDRY, "Cast Iron Foundry")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 70, GameEnums.ResourceType.CAST_IRON: 30}
	d.daily_upkeep = {GameEnums.ResourceType.COAL: 8.0}
	d.daily_output = {GameEnums.ResourceType.CAST_IRON: 5.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.URBAN]
	return d

static func _saltpetre_powder_mill() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SALTPETRE_POWDER_MILL, "Saltpetre & Powder Mill")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.construction_cost = {GameEnums.ResourceType.BRICKS: 60, GameEnums.ResourceType.WOOD: 20}
	d.daily_upkeep = {GameEnums.ResourceType.COAL: 4.0}
	d.daily_output = {GameEnums.ResourceType.GUNPOWDER: 6.0}
	d.allowed_biomes = [GameEnums.BiomeType.INDUSTRIAL]
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

static func _tenant_farm() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TENANT_FARM, "Tenant Farm")
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
