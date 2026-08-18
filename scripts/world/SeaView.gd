class_name SeaView
extends Node2D

## The open sea, as two flat polygons spanning the whole map: a blue fill and
## an animated fog haze over it. "I think the sea should be blue and be visible
## through the fog (like 60% opacity)" (user, 2026-08-18).
##
## Before this, sea was not drawn AT ALL. HexGridMap deliberately skips
## spawning a HexCellView for OCEAN hexes (most of a UK+Ireland bounding box is
## open water, and a textured node per ocean hex is pure waste), so everything
## outside the coastline fell through to the window's own clear colour and read
## as flat grey.
##
## Two polygons for the whole map, not one per hex. The sea has no per-hex
## detail to draw and no per-hex intel to reveal, so a per-hex treatment would
## cost ~22,900 nodes to express a state that is identical everywhere. It spans
## the entire map rather than only the water: every land layer above it is
## opaque, so land covers it exactly, and no coastline test is needed here —
## HexCoord/BritishGeographyData already own that shape and CoastlineOutlineView
## already draws it.
##
## Deliberately NOT fog-gated per hex, and it does not clear on exploration.
## Same reasoning CoastlineOutlineView already established for the coastline
## and for the same user request: where the sea is, is public knowledge, not a
## gameplay secret — it leaks nothing beyond "this is water", which the
## coastline outline states outright anyway. The haze is what keeps unexplored
## water from reading as brighter than the explored land beside it.

## Sea sits below every land layer. The full ground stack, lowest first:
##   -5 this fill, -4 this haze, -3 HexGridMap's per-hex tile,
##   -2 TerrainMeshView's vector mesh, -1 FogVisuals.TERRAIN_OVERLAY_Z_INDEX.
## Anything inserted below -3 will be hidden by land wherever land exists.
const FILL_Z_INDEX: int = -5
const HAZE_Z_INDEX: int = -4

## One hex radius of slack past the outermost hex centre, so the fill reaches
## past the last hex's own corners instead of stopping at its centre and
## leaving a fringe of background around the map's edge.
const MARGIN_WU: float = HexCoord.HEX_SIZE


func _ready() -> void:
	var rect := _map_world_rect()
	add_child(_build_layer(rect, FILL_Z_INDEX,
		TerrainVisuals.biome_color(GameEnums.BiomeType.OCEAN, GameEnums.SoilFertility.NOT_ARABLE), null))
	# Same shared ShaderMaterial machinery every hex's fog uses, at a reduced
	# opacity — one more instance, not a second fog implementation.
	add_child(_build_layer(rect, HAZE_Z_INDEX, Color.WHITE, FogVisuals.sea_overlay_material()))


## World-space rect covering every hex in BritishGeographyData.MAP_BOUNDS.
##
## Derived from the four CORNERS of the axial range, not from its min/max q and
## r read as x and y: axial_to_world() shears x by r (x = k * (q + r/2)), so the
## rectangle in axial space maps to a parallelogram in world space and the
## extreme x lives at a corner where q and r are both extreme.
func _map_world_rect() -> Rect2:
	var bounds := BritishGeographyData.MAP_BOUNDS
	var min_q := bounds.position.x
	var min_r := bounds.position.y
	var max_q := bounds.position.x + bounds.size.x - 1
	var max_r := bounds.position.y + bounds.size.y - 1
	var rect := Rect2(HexCoord.axial_to_world(Vector2i(min_q, min_r)), Vector2.ZERO)
	for corner in [Vector2i(max_q, min_r), Vector2i(min_q, max_r), Vector2i(max_q, max_r)]:
		rect = rect.expand(HexCoord.axial_to_world(corner))
	return rect.grow(MARGIN_WU)


func _build_layer(rect: Rect2, z: int, color: Color, material: ShaderMaterial) -> Polygon2D:
	var layer := Polygon2D.new()
	layer.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	layer.color = color
	layer.material = material
	# Absolute: this node is a plain child of WorldRoot today, but the band it
	# occupies is meaningful against HexGridMap's and TerrainMeshView's, which
	# are its siblings — inheriting a parent's depth would couple this ordering
	# to where in the tree someone happens to place it.
	layer.z_as_relative = false
	layer.z_index = z
	return layer
