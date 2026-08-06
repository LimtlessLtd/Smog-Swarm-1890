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
