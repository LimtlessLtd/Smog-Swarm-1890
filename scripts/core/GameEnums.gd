class_name GameEnums
extends RefCounted

## Central namespace for shared enum vocabulary used across the game's systems.
## Kept as a single static reference (no instances, no autoload) so every
## script speaks the same terms without cross-importing each other directly.

enum BiomeType {
	URBAN,        ## City streets / settlement footprint.
	INDUSTRIAL,   ## Slag heaps, mine spoil, blighted factory ground.
	FARMLAND,     ## Open, tillable countryside (fertility varies, see SoilFertility).
	MOORLAND,     ## Open, less fertile countryside.
	HIGHLAND,     ## Elevated terrain / mountain chains (Pennines, Chilterns, Cotswolds).
	WATERWAY,     ## River or canal hex.
	WETLAND,      ## Marsh, fen or peat bog.
}

enum SoilFertility {
	LUSH,        ## Prime farmland (e.g. Cheshire Plain, Midlands).
	POOR,        ## Marginal farmland (e.g. moorland fringe).
	DESOLATE,    ## Industrial blight or drained wetland; barely arable.
	NOT_ARABLE,  ## Urban, open water, etc. — farming is not applicable here.
}

enum DistrictType {
	URBAN_CENTER,          ## Civilian core: Town Halls, Churches, Telegraph Relays.
	INDUSTRIAL_ESTATE,     ## Production core: foundries, mills, workshops.
	UNCLEARED_WILDERNESS,  ## Contested ground; active zombie presence until cleared.
}

enum TerrainFeature {
	NONE,
	RIVER,
	CANAL,
	MARSH,
	PEAT_BOG,
	ESCARPMENT,  ## Mountain / hill chokepoint terrain.
}

enum CameraPerspective {
	TOP_DOWN,
	ISOMETRIC,
}

enum ResourceType {
	FOOD,                   ## Population upkeep drain.
	COAL,                   ## Boiler/heating/streetlamp upkeep.
	GUNPOWDER,              ## Ranged combat & garrison upkeep.
	WOOD,                   ## Construction material.
	BRICKS,                 ## Construction material.
	CAST_IRON,              ## Construction material.
	REINFORCED_CONCRETE,    ## Construction material — no Phase 2 building produces this yet.
}

enum BuildingCategory {
	HOUSING_CIVIL,       ## Terraced Tenements, Workhouses, Church Steeple Watchtowers, etc.
	INDUSTRY_EXTRACTION, ## Brickworks, kilns, pitheads, foundries, powder mills, ammo dumps.
	AGRICULTURE,         ## Tenant Farms, Grain Silos, Cattle Yards.
}

enum BuildingType {
	# --- Housing & Civil ---
	TERRACED_TENEMENT,
	WORKHOUSE,
	CHURCH_STEEPLE_WATCHTOWER,
	GAS_STREETLAMP,
	TELEGRAPH_RELAY_OFFICE,
	STEAM_PRINTING_PRESS,
	TOWN_HALL,   ## Not in the Phase 2.1 checklist by name, but required as a Civilian ZoC
	GARRISON,    ## projector by 2.3; added here as the civic-seat/militia-HQ pairing for it.
	# --- Industry & Extraction ---
	CLAY_BRICKWORKS,
	CHARCOAL_KILN,
	COAL_PITHEAD,
	CAST_IRON_FOUNDRY,
	SALTPETRE_POWDER_MILL,
	FORWARD_AMMO_DUMP,
	# --- Agriculture ---
	TENANT_FARM,
	GRAIN_SILO,
	CATTLE_YARD,
}

enum ZoneOfControlType {
	MILITARY,   ## Forward Ammo Dumps, Garrisons, Church Steeple Watchtowers, Combat Units.
	CIVILIAN,   ## Town Halls, Churches (the Watchtower's civilian half), Telegraph Relays.
}

enum SupplyLineType {
	ROAD,
	RAILWAY,
	CANAL,
}
