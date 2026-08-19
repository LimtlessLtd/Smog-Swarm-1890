class_name LandMask
extends RefCounted

## "Is this world position on land?" — one cached expansion of
## BritishGeographyData's land RLE, shared by everything that has to cull
## against the coastline.
##
## Extracted so the terrain mesh and the detail scatter cannot disagree about
## where the sea starts. They are drawn as one picture: a tree scattered onto
## ground the mesh dropped would stand in open water, and each keeping its own
## copy of this test is exactly how that starts happening.
##
## Same source HexMapGenerator decides OCEAN from and CoastlineOutlineView
## traces, so culling against it puts every layer's edge on the coastline
## already drawn rather than inventing a second, disagreeing shoreline. That
## shoreline is hex-resolution; a real sub-hex coastline is epic Phase 1b and
## belongs in the bake, not here.

## get_landmass_hexes() expands the RLE on every call and returns ~4,700
## entries, and a chunk build asks this question tens of thousands of times —
## so it is expanded once for the whole process, not per caller and not per
## chunk.
static var _land_hexes: Dictionary = {}

static func is_land(world_pos: Vector2) -> bool:
	if _land_hexes.is_empty():
		_land_hexes = BritishGeographyData.get_landmass_hexes()
	return _land_hexes.has(HexCoord.world_to_axial(world_pos))
