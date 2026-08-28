class_name BuildingCatalog
extends RefCounted

## Static seed data for the 19th-century building tree — plays the same
## "single source of truth" role for buildings that BritishGeographyData
## plays for the hex grid, kept separate from BuildingManager (the runtime
## system that places/tracks instances).
##
## Full rewrite reconciling this catalog against design_doc.md §3's
## Tier-0-to-5 building list (the authoritative spec — see todo.md's
## "Design Doc & Implementation Note"). Every building below is grouped by
## its design_doc.md tier (comment banners), transcribed cost/capacity/
## upkeep/output straight from that doc, with BuildingDefinition.tier set
## to match so BuildingManager.get_placement_error() can gate construction
## against TechManager.is_building_tier_unlocked(). Buildings with no doc
## equivalent (Gas Streetlamp, Telegraph Relay Office, Steam Printing
## Press, Grain Silo, Cattle Yard, Ditch, Oil Pit) were cut rather than
## carried over — design_doc.md's list is treated as exhaustive.
##
## "Capacity: -X Pop, -Y Energy" (a consumer) becomes
## daily_upkeep[POPULATION]/daily_upkeep[ENERGY]; "Capacity: +X Pop/Energy"
## (a producer) becomes daily_output[POPULATION]/daily_output[ENERGY] — both
## settled once at construction/repair via CapacityAllocator, not a
## daily flow (see BuildingDefinition.daily_upkeep's own doc comment).
## population_provided is set ONLY on the three dedicated housing buildings
## (Wooden Houses/Brick Houses/Tower Blocks) — it drives BOTH
## BuildingInstance.current_population (real housing occupancy, which feeds
## Food demand via BuildingSustenanceController.compute_daily_totals()'s
## total_population tally) and HordeManager's ruin-to-casualties snapshot.
## Every OTHER Pop-capacity producer/consumer (Town Hall, Garrison, mines,
## farms, plants, ...) only ever touches daily_output/daily_upkeep[POPULATION]
## — setting population_provided on them too would double-count Food demand
## on top of their own explicit Food upkeep line.
##
## Unlike BritishGeographyData (built once per map generation),
## get_definition() is expected to be called on every placement attempt, so
## the definitions are built lazily and cached rather than rebuilt each call.

const _POOR_SOIL_ONLY: Array[GameEnums.SoilFertility] = [GameEnums.SoilFertility.LUSH, GameEnums.SoilFertility.POOR]

## Raw-resource extraction buildings' allowed_biomes, taken from
## design_doc.md §1's per-biome Abundant/Common resource table — Rare
## sources excluded (a building shouldn't be placeable on a biome's worst
## yield tier when better ones exist). SULFUR_BIOMES is the one exception:
## every biome §1 lists for Sulfur (HIGHLAND, HEATHLAND) marks it Rare —
## there is no Abundant/Common Sulfur source anywhere in the doc, so
## excluding Rare here would leave Sulfur Mine with an empty (meaning
## "unrestricted") allowed_biomes list, the opposite of intended.
const _WOOD_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.WOODLAND, GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.WETLAND, GameEnums.BiomeType.HEATHLAND]
const _CLAY_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.WETLAND, GameEnums.BiomeType.WOODLAND, GameEnums.BiomeType.HEATHLAND]
const _COAL_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.HIGHLAND]
const _IRON_ORE_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.HIGHLAND, GameEnums.BiomeType.MOORLAND]
const _LIMESTONE_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.HIGHLAND]
const _SULFUR_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.HIGHLAND, GameEnums.BiomeType.HEATHLAND]  ## Both Rare — see class doc comment above.
const _FARM_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND]

## Industrial processing plants (as opposed to raw extraction) sit on
## blighted/slag ground or in the settlement footprint itself — same
## INDUSTRIAL+URBAN pairing the pre-rework Brickworks/Foundry/Gunpowder Mill
## already used.
const _INDUSTRIAL_BIOMES: Array[GameEnums.BiomeType] = [GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.URBAN]

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
		_town_hall(),
		_lumber_yard(), _clay_pit(), _smallholding_farm(), _steam_furnace(), _wooden_houses(), _watchtower(),
		_coal_mine(), _limestone_quarry(), _brickworks(), _estate_farm(), _coal_powerplant(),
		_research_institute(), _brick_houses(), _garrison(), _supply_dump(),
		_iron_ore_mine(), _iron_foundry(), _concrete_plant(), _industrial_farm(), _tower_blocks(),
		_armory_and_barracks(), _search_light(),
		_sulfur_mine(), _deep_coal_shafts(), _sawmills(), _gunpowder_mill(), _steelworks(),
		_mechanised_farm(), _advanced_coal_powerplant(), _high_command_and_cavalry_depot(),
		_steam_excavator_depot(), _heavy_coal_washery_and_pulverizer(), _mechanized_maintenance_depot(),
		_macadamized_transport_hub(), _steam_turbine_power_plant(), _traction_works_and_workshop(),
		_bessemer_smelting_complex(), _automated_freight_marshalling_yard(), _synthetic_chemical_refinery(),
		_central_high_voltage_grid_station(), _ordnance_and_armament_complex(),
	]

# --- Town Hall (pre-built free at start; tier=3 gates further construction) -

static func _town_hall() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TOWN_HALL, "Town Hall")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 3  ## Gates player-driven construction only — see BuildingDefinition.tier's own doc comment for why the free starting instance is unaffected.
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.CONCRETE: 150, GameEnums.ResourceType.STEEL: 100}
	d.daily_upkeep = {GameEnums.ResourceType.FOOD: 10.0}
	d.daily_output = {GameEnums.ResourceType.POPULATION: 100.0, GameEnums.ResourceType.ENERGY: 20.0, GameEnums.ResourceType.RESEARCH_POINTS: 5.0}
	# Every dry-land biome, and deliberately NOT requires_settlement — a Town
	# Hall is the one building that CREATES a settlement rather than needing
	# one (design_doc.md §3: "Allows players to found far-flung cities
	# specialized in extracting specific resource nodes"), so gating it on an
	# existing settlement would make founding impossible. Listed positively
	# rather than left empty/"unrestricted": an empty list would also permit
	# WATERWAY, and a town founded mid-river would pave a crossing the
	# Bridge-mandatory rule (HexPathfinder.is_water_crossing_blocked()) exists
	# to forbid. OCEAN is already excluded by the passability check, WATERWAY
	# is not.
	d.allowed_biomes = [
		GameEnums.BiomeType.URBAN, GameEnums.BiomeType.INDUSTRIAL, GameEnums.BiomeType.FARMLAND,
		GameEnums.BiomeType.MOORLAND, GameEnums.BiomeType.HIGHLAND, GameEnums.BiomeType.WETLAND,
		GameEnums.BiomeType.WOODLAND, GameEnums.BiomeType.HEATHLAND,
	]
	d.max_per_hex = 1  ## design_doc.md §3: "Only 1 can be built per hex tile."
	d.zoc_roles = [GameEnums.ZoneOfControlType.CIVILIAN]
	# Without this, a brand-new colony's ONLY vision source is radius 0 (its
	# own single hex) — Town Hall is BuildingManager.seed_starting_buildings()'s
	# free opening move, so turn one would show one hex of a country-sized
	# map and nothing else. Smaller than the dedicated Watchtower lookout's 2.
	d.vision_radius = 1
	d.can_train_units = true  ## Trains Tier 0 units (design_doc.md §4: Truncheoneer, Toxophilite, Outrider).
	return d

# --- Tier 0: Wood Base / Settlement -----------------------------------------

## Bootstrap Wood producer — no raw-material input, matching TIMBER_CAMP's
## pre-rework role (the only Wood source with nothing upstream of it).
static func _lumber_yard() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.LUMBER_YARD, "Lumber Yard")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 0
	d.construction_cost = {GameEnums.ResourceType.WOOD: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 5.0, GameEnums.ResourceType.ENERGY: 5.0}
	d.daily_output = {GameEnums.ResourceType.WOOD: 200.0}
	d.allowed_biomes = _WOOD_BIOMES
	return d

static func _clay_pit() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CLAY_PIT, "Clay Pit")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 0
	d.construction_cost = {GameEnums.ResourceType.WOOD: 60}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 15.0, GameEnums.ResourceType.ENERGY: 10.0, GameEnums.ResourceType.FOOD: 10.0}
	d.daily_output = {GameEnums.ResourceType.CLAY: 200.0}
	d.allowed_biomes = _CLAY_BIOMES
	return d

static func _smallholding_farm() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SMALLHOLDING_FARM, "Smallholding Farm")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.tier = 0
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 10.0, GameEnums.ResourceType.ENERGY: 5.0}
	d.daily_output = {GameEnums.ResourceType.FOOD: 150.0}
	d.allowed_biomes = _FARM_BIOMES
	d.allowed_soil_fertility = _POOR_SOIL_ONLY
	d.soil_fertility_scales_output = true
	return d

static func _steam_furnace() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.STEAM_FURNACE, "Steam Furnace")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 0
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 5.0, GameEnums.ResourceType.WOOD: 30.0}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 100.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	return d

static func _wooden_houses() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.WOODEN_HOUSES, "Wooden Houses")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 0
	d.construction_cost = {GameEnums.ResourceType.WOOD: 40}
	d.population_provided = 50
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 5.0, GameEnums.ResourceType.FOOD: 20.0}
	d.daily_output = {GameEnums.ResourceType.POPULATION: 50.0}  ## Mirrors population_provided into the CapacityAllocator grant — see class doc comment.
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

static func _watchtower() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.WATCHTOWER, "Watchtower")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 0
	d.construction_cost = {GameEnums.ResourceType.WOOD: 80}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 5.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	# Doubles as a lookout post (Military) and a parish/civic watch (Civilian).
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY, GameEnums.ZoneOfControlType.CIVILIAN]
	d.vision_radius = 2  # Tallest structure in town at Tier 0 — a proper watchtower lookout.
	d.lit_at_night = true  # Watchtower searchlights hold/extend vision after dark.
	d.is_defensive = true  ## design_doc.md §2.1 names it in the Fringe allow-list.
	return d

# --- Tier 1: Brick Base / Borough -------------------------------------------

static func _coal_mine() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.COAL_MINE, "Coal Mine")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 120, GameEnums.ResourceType.BRICKS: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 25.0, GameEnums.ResourceType.ENERGY: 20.0, GameEnums.ResourceType.FOOD: 20.0}
	d.daily_output = {GameEnums.ResourceType.COAL: 100.0}
	d.allowed_biomes = _COAL_BIOMES
	d.noise_output = 5  # Winding gear/heavy machinery.
	return d

static func _limestone_quarry() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.LIMESTONE_QUARRY, "Limestone Quarry")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100, GameEnums.ResourceType.BRICKS: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 20.0, GameEnums.ResourceType.ENERGY: 15.0, GameEnums.ResourceType.FOOD: 15.0}
	d.daily_output = {GameEnums.ResourceType.LIMESTONE: 150.0}
	d.allowed_biomes = _LIMESTONE_BIOMES
	d.noise_output = 4
	return d

static func _brickworks() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.BRICKWORKS, "Brickworks")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 150}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 10.0, GameEnums.ResourceType.ENERGY: 30.0, GameEnums.ResourceType.CLAY: 100.0}
	d.daily_output = {GameEnums.ResourceType.BRICKS: 100.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 3  # Kilns firing.
	return d

static func _estate_farm() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.ESTATE_FARM, "Estate Farm")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 180, GameEnums.ResourceType.BRICKS: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 15.0, GameEnums.ResourceType.ENERGY: 30.0}
	d.daily_output = {GameEnums.ResourceType.FOOD: 450.0}
	d.allowed_biomes = _FARM_BIOMES
	d.allowed_soil_fertility = _POOR_SOIL_ONLY
	d.soil_fertility_scales_output = true
	return d

static func _coal_powerplant() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.COAL_POWERPLANT, "Coal Powerplant")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100, GameEnums.ResourceType.BRICKS: 250}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 15.0, GameEnums.ResourceType.COAL: 40.0}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 500.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 4
	return d

## Reuses the orphaned Steam Printing Press art (see BuildingVisuals) — the
## doc's sole Tier 1 Research producer, replacing Telegraph Relay
## Office/Steam Printing Press's now-cut role as the second Research source
## alongside Town Hall.
static func _research_institute() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.RESEARCH_INSTITUTE, "Research Institute")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100, GameEnums.ResourceType.BRICKS: 200}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 50.0, GameEnums.ResourceType.ENERGY: 150.0, GameEnums.ResourceType.FOOD: 80.0}
	d.daily_output = {GameEnums.ResourceType.RESEARCH_POINTS: 10.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

static func _brick_houses() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.BRICK_HOUSES, "Brick Houses")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 50, GameEnums.ResourceType.BRICKS: 50}
	d.population_provided = 200
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 10.0, GameEnums.ResourceType.FOOD: 80.0}
	d.daily_output = {GameEnums.ResourceType.POPULATION: 200.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

static func _garrison() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GARRISON, "Garrison")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 200, GameEnums.ResourceType.BRICKS: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 20.0, GameEnums.ResourceType.ENERGY: 20.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.can_train_units = true  ## Trains Tier 1 units (design_doc.md §4: Navvy, Yeoman Marksman, Grenadier).
	d.is_defensive = true  ## design_doc.md §2.1 names it in the Fringe allow-list.
	return d

## Field gunpowder/fuel resupply node — same role FORWARD_AMMO_DUMP played
## pre-rework. No biome/settlement restriction on purpose: it exists to
## project Military ZoC out into not-yet-secured frontier hexes.
static func _supply_dump() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SUPPLY_DUMP, "Supply Dump")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 1
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100, GameEnums.ResourceType.BRICKS: 50}
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.is_defensive = true  ## design_doc.md §2.1 names it in the Fringe allow-list, and it is the one building meant to be put down on hostile ground.
	return d

# --- Tier 2: Iron Base / Industrial District --------------------------------

static func _iron_ore_mine() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.IRON_ORE_MINE, "Iron Ore Mine")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 200, GameEnums.ResourceType.BRICKS: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 30.0, GameEnums.ResourceType.ENERGY: 40.0, GameEnums.ResourceType.FOOD: 25.0}
	d.daily_output = {GameEnums.ResourceType.IRON_ORE: 100.0}
	d.allowed_biomes = _IRON_ORE_BIOMES
	d.noise_output = 5
	return d

static func _iron_foundry() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.IRON_FOUNDRY, "Iron Foundry")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 200, GameEnums.ResourceType.BRICKS: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 150.0, GameEnums.ResourceType.IRON_ORE: 100.0, GameEnums.ResourceType.COAL: 25.0, GameEnums.ResourceType.FOOD: 30.0}
	d.daily_output = {GameEnums.ResourceType.IRON: 100.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 6  # Hammering/casting.
	return d

static func _concrete_plant() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CONCRETE_PLANT, "Concrete Plant")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 100, GameEnums.ResourceType.BRICKS: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 30.0, GameEnums.ResourceType.ENERGY: 80.0, GameEnums.ResourceType.LIMESTONE: 100.0, GameEnums.ResourceType.CLAY: 50.0, GameEnums.ResourceType.COAL: 20.0, GameEnums.ResourceType.FOOD: 30.0}
	d.daily_output = {GameEnums.ResourceType.CONCRETE: 150.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 4
	return d

static func _industrial_farm() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.INDUSTRIAL_FARM, "Industrial Farm")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 400, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.IRON: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 30.0, GameEnums.ResourceType.ENERGY: 20.0}
	d.daily_output = {GameEnums.ResourceType.FOOD: 1200.0}
	d.allowed_biomes = _FARM_BIOMES
	d.allowed_soil_fertility = _POOR_SOIL_ONLY
	d.soil_fertility_scales_output = true
	return d

static func _tower_blocks() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TOWER_BLOCKS, "Tower Blocks")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 150, GameEnums.ResourceType.BRICKS: 100, GameEnums.ResourceType.IRON: 50, GameEnums.ResourceType.CONCRETE: 50}
	d.population_provided = 500
	d.daily_upkeep = {GameEnums.ResourceType.ENERGY: 25.0, GameEnums.ResourceType.FOOD: 200.0}
	d.daily_output = {GameEnums.ResourceType.POPULATION: 500.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	return d

static func _armory_and_barracks() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.ARMORY_AND_BARRACKS, "Armory & Barracks")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 250, GameEnums.ResourceType.BRICKS: 150, GameEnums.ResourceType.IRON: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 30.0, GameEnums.ResourceType.ENERGY: 40.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.can_train_units = true  ## Trains Tier 2 units (design_doc.md §4: Bayoneteer, Redcoat, Chasseur).
	return d

static func _search_light() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SEARCH_LIGHT, "Search Light")
	d.category = GameEnums.BuildingCategory.DEFENSE_WORKS
	d.tier = 2
	d.construction_cost = {GameEnums.ResourceType.WOOD: 80, GameEnums.ResourceType.BRICKS: 50, GameEnums.ResourceType.CONCRETE: 30, GameEnums.ResourceType.IRON: 20}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 5.0, GameEnums.ResourceType.ENERGY: 50.0}
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.vision_radius = 2  # Illuminates the perimeter beyond its own hex, same role as the Watchtower.
	d.lit_at_night = true  # Holds/extends vision after dark — see CombatCoordinator's own Garrison-order night bonus, keyed off this building type.
	d.is_defensive = true  ## design_doc.md §2.1's Fringe allow-list reads "Watchtowers, Garrisons, Walls, Supply Dumps"; the Search Light is the same Defensive Tier role at Tier 2.
	return d

# --- Tier 3: Steel Base / Rail Network --------------------------------------

static func _sulfur_mine() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SULFUR_MINE, "Sulfur Mine")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 250, GameEnums.ResourceType.BRICKS: 150, GameEnums.ResourceType.CONCRETE: 100, GameEnums.ResourceType.IRON: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 35.0, GameEnums.ResourceType.ENERGY: 60.0, GameEnums.ResourceType.FOOD: 30.0}
	d.daily_output = {GameEnums.ResourceType.SULFUR: 60.0}  ## design_doc.md output raised 50->60/day this pass — see design_doc.md §3 Tier 3.
	d.allowed_biomes = _SULFUR_BIOMES
	d.noise_output = 5
	return d

## High-output Coal consolidator, added this pass so a late-game colony
## isn't forced to tile the map with dozens of small Tier 1 Coal Mines to
## keep up with Steel-era demand — roughly 5 Coal Mines' worth from one
## building. See design_doc.md §3 Tier 3.
static func _deep_coal_shafts() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.DEEP_COAL_SHAFTS, "Deep Coal Shafts")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.CONCRETE: 150, GameEnums.ResourceType.IRON: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 100.0, GameEnums.ResourceType.FOOD: 40.0}
	d.daily_output = {GameEnums.ResourceType.COAL: 500.0}
	d.allowed_biomes = _COAL_BIOMES
	d.noise_output = 6
	return d

## Same consolidator role as Deep Coal Shafts, for Wood — roughly 5 Lumber
## Yards' worth. See design_doc.md §3 Tier 3.
static func _sawmills() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SAWMILLS, "Sawmills")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.CONCRETE: 150, GameEnums.ResourceType.IRON: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 35.0, GameEnums.ResourceType.ENERGY: 80.0, GameEnums.ResourceType.FOOD: 30.0}
	d.daily_output = {GameEnums.ResourceType.WOOD: 1000.0}
	d.allowed_biomes = _WOOD_BIOMES
	d.noise_output = 4
	return d

## Reuses the pre-rework Saltpetre Powder Mill art/identifier role.
static func _gunpowder_mill() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.GUNPOWDER_MILL, "Gunpowder Mill")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 150, GameEnums.ResourceType.BRICKS: 100, GameEnums.ResourceType.IRON: 50}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 15.0, GameEnums.ResourceType.ENERGY: 40.0, GameEnums.ResourceType.SULFUR: 60.0, GameEnums.ResourceType.COAL: 40.0, GameEnums.ResourceType.FOOD: 20.0}
	d.daily_output = {GameEnums.ResourceType.GUNPOWDER: 120.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 4
	return d

static func _steelworks() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.STEELWORKS, "Steelworks")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.CONCRETE: 150, GameEnums.ResourceType.IRON: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 300.0, GameEnums.ResourceType.IRON: 100.0, GameEnums.ResourceType.COAL: 50.0, GameEnums.ResourceType.FOOD: 40.0}
	d.daily_output = {GameEnums.ResourceType.STEEL: 75.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 6
	return d

static func _mechanised_farm() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.MECHANISED_FARM, "Mechanised Farm")
	d.category = GameEnums.BuildingCategory.AGRICULTURE
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 800, GameEnums.ResourceType.BRICKS: 400, GameEnums.ResourceType.CONCRETE: 300, GameEnums.ResourceType.STEEL: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 50.0}
	d.daily_output = {GameEnums.ResourceType.FOOD: 3500.0}
	d.allowed_biomes = _FARM_BIOMES
	d.allowed_soil_fertility = _POOR_SOIL_ONLY
	d.soil_fertility_scales_output = true
	return d

static func _advanced_coal_powerplant() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.ADVANCED_COAL_POWERPLANT, "Advanced Coal Powerplant")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 400, GameEnums.ResourceType.BRICKS: 400, GameEnums.ResourceType.CONCRETE: 200, GameEnums.ResourceType.STEEL: 200}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 20.0, GameEnums.ResourceType.COAL: 150.0}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 3000.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 5
	return d

static func _high_command_and_cavalry_depot() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.HIGH_COMMAND_AND_CAVALRY_DEPOT, "High Command & Cavalry Depot")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 3
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.CONCRETE: 100, GameEnums.ResourceType.STEEL: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 80.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.can_train_units = true  ## Trains Tier 3 units (design_doc.md §4: Highlander, Sharpshooter, Dragoon).
	return d

# --- Tier 4: Advanced Engineering / Automation & Maintenance Era -----------

## +50% raw node extraction yield across sector — no sector-wide yield
## multiplier system exists yet to read this; cost/capacity data lands here,
## the effect is a future consumer, same "mechanism exists, nothing reads it
## yet" scoping call PR #56 made for the raw resources themselves.
static func _steam_excavator_depot() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.STEAM_EXCAVATOR_DEPOT, "Steam Excavator Depot")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 4
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 300, GameEnums.ResourceType.CONCRETE: 250, GameEnums.ResourceType.STEEL: 150}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 20.0, GameEnums.ResourceType.ENERGY: 150.0, GameEnums.ResourceType.COAL: 40.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	return d

## +100% output of connected smelters/foundries — no "connected" adjacency
## system exists yet to read this; see _steam_excavator_depot()'s own note.
static func _heavy_coal_washery_and_pulverizer() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.HEAVY_COAL_WASHERY_AND_PULVERIZER, "Heavy Coal Washery & Pulverizer")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 4
	d.construction_cost = {GameEnums.ResourceType.WOOD: 350, GameEnums.ResourceType.BRICKS: 400, GameEnums.ResourceType.CONCRETE: 300, GameEnums.ResourceType.STEEL: 200}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 30.0, GameEnums.ResourceType.ENERGY: 200.0, GameEnums.ResourceType.COAL: 150.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	return d

## Continuous auto-repair in ZoC — no consumer reads this yet; see
## _steam_excavator_depot()'s own note.
static func _mechanized_maintenance_depot() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.MECHANIZED_MAINTENANCE_DEPOT, "Mechanized Maintenance Depot")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 4
	d.construction_cost = {GameEnums.ResourceType.WOOD: 250, GameEnums.ResourceType.BRICKS: 250, GameEnums.ResourceType.CONCRETE: 200, GameEnums.ResourceType.STEEL: 150}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 25.0, GameEnums.ResourceType.ENERGY: 100.0, GameEnums.ResourceType.IRON: 20.0, GameEnums.ResourceType.STEEL: 10.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	return d

## +50% transfer throughput and speed — no logistics-throughput multiplier
## system exists yet to read this; see _steam_excavator_depot()'s own note.
static func _macadamized_transport_hub() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.MACADAMIZED_TRANSPORT_HUB, "Macadamized Transport Hub")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 4
	d.construction_cost = {GameEnums.ResourceType.WOOD: 200, GameEnums.ResourceType.BRICKS: 200, GameEnums.ResourceType.CONCRETE: 200, GameEnums.ResourceType.STEEL: 100}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 20.0, GameEnums.ResourceType.ENERGY: 100.0, GameEnums.ResourceType.FOOD: 20.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	return d

static func _steam_turbine_power_plant() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.STEAM_TURBINE_POWER_PLANT, "Steam Turbine Power Plant")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 4
	d.construction_cost = {GameEnums.ResourceType.WOOD: 300, GameEnums.ResourceType.BRICKS: 500, GameEnums.ResourceType.CONCRETE: 400, GameEnums.ResourceType.STEEL: 400}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 30.0, GameEnums.ResourceType.COAL: 300.0}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 7500.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 6
	return d

static func _traction_works_and_workshop() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.TRACTION_WORKS_AND_WORKSHOP, "Traction Works & Workshop")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 4
	d.construction_cost = {GameEnums.ResourceType.WOOD: 400, GameEnums.ResourceType.BRICKS: 300, GameEnums.ResourceType.CONCRETE: 200, GameEnums.ResourceType.STEEL: 200}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 50.0, GameEnums.ResourceType.ENERGY: 150.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.can_train_units = true  ## Trains Tier 4 vehicles (design_doc.md §4: Traction Ram, Maxim Quadricycle, Searchlight Tender).
	return d

# --- Tier 5: Heavy Industrial / Super-Complex Era ---------------------------

static func _bessemer_smelting_complex() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.BESSEMER_SMELTING_COMPLEX, "Bessemer Smelting Complex")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 5
	d.construction_cost = {GameEnums.ResourceType.WOOD: 500, GameEnums.ResourceType.BRICKS: 600, GameEnums.ResourceType.CONCRETE: 500, GameEnums.ResourceType.STEEL: 400}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 50.0, GameEnums.ResourceType.ENERGY: 600.0, GameEnums.ResourceType.IRON_ORE: 150.0, GameEnums.ResourceType.COAL: 50.0}
	d.daily_output = {GameEnums.ResourceType.STEEL: 250.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 6
	return d

## Global rail speed +500%, zero transfer delay — no rail-speed-bonus system
## exists yet to read this; see Tier 4's _steam_excavator_depot() own note.
static func _automated_freight_marshalling_yard() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.AUTOMATED_FREIGHT_MARSHALLING_YARD, "Automated Freight Marshalling Yard")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 5
	d.construction_cost = {GameEnums.ResourceType.WOOD: 400, GameEnums.ResourceType.BRICKS: 500, GameEnums.ResourceType.CONCRETE: 400, GameEnums.ResourceType.STEEL: 300}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 300.0, GameEnums.ResourceType.COAL: 50.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	return d

static func _synthetic_chemical_refinery() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.SYNTHETIC_CHEMICAL_REFINERY, "Synthetic Chemical Refinery")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 5
	d.construction_cost = {GameEnums.ResourceType.WOOD: 400, GameEnums.ResourceType.BRICKS: 400, GameEnums.ResourceType.CONCRETE: 300, GameEnums.ResourceType.STEEL: 300}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.ENERGY: 400.0, GameEnums.ResourceType.COAL: 150.0, GameEnums.ResourceType.SULFUR: 100.0}
	d.daily_output = {GameEnums.ResourceType.GUNPOWDER: 350.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 5
	return d

static func _central_high_voltage_grid_station() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.CENTRAL_HIGH_VOLTAGE_GRID_STATION, "Central High-Voltage Grid Station")
	d.category = GameEnums.BuildingCategory.INDUSTRY_EXTRACTION
	d.tier = 5
	d.construction_cost = {GameEnums.ResourceType.WOOD: 500, GameEnums.ResourceType.BRICKS: 800, GameEnums.ResourceType.CONCRETE: 600, GameEnums.ResourceType.STEEL: 600}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 40.0, GameEnums.ResourceType.COAL: 500.0}
	d.daily_output = {GameEnums.ResourceType.ENERGY: 18000.0}
	d.allowed_biomes = _INDUSTRIAL_BIOMES
	d.noise_output = 5
	return d

static func _ordnance_and_armament_complex() -> BuildingDefinition:
	var d := BuildingDefinition.new(GameEnums.BuildingType.ORDNANCE_AND_ARMAMENT_COMPLEX, "Ordnance & Armament Complex")
	d.category = GameEnums.BuildingCategory.HOUSING_CIVIL
	d.tier = 5
	d.construction_cost = {GameEnums.ResourceType.WOOD: 600, GameEnums.ResourceType.BRICKS: 500, GameEnums.ResourceType.CONCRETE: 500, GameEnums.ResourceType.STEEL: 500}
	d.daily_upkeep = {GameEnums.ResourceType.POPULATION: 60.0, GameEnums.ResourceType.ENERGY: 300.0}
	d.allowed_biomes = [GameEnums.BiomeType.URBAN]
	d.requires_settlement = true
	d.zoc_roles = [GameEnums.ZoneOfControlType.MILITARY]
	d.can_train_units = true  ## Trains Tier 5 vehicles (design_doc.md §4: Holt Breaker, Howitzer Gun Tractor, Armoured Command Car).
	return d
