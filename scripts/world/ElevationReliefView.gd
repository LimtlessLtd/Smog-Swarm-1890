class_name ElevationReliefView
extends Node2D

## Draws the terrain relief/impassability overlay: one texture built by
## ReliefImageBuilder, stretched over the world rect it was sampled from.
## This class owns placement, visibility and the build lifecycle only — it
## computes no shading and classifies no terrain.
##
## "Is elevation implemented yet? Theres no visuals to tell the user which
## bits of the map are elevated and how much in comparison to its adjacent
## biomes", "Impassable terrain, its not clear which parts of the terrain/
## biomes are passable and which are impassable", and — after a first attempt
## at this that shaded whole hexes — "i still cannot clearly see elevation in
## the tactical view. things need to actually look as though they are higher/
## lower in elevation than their neighbours" (user reports).
##
## The first attempt drew per-hex polygons: a flat tint per elevation BAND,
## contour lines on hex edges facing a lower neighbour, and diagonal hatching
## over any hex whose HexCell.is_passable() was false. All three were wrong at
## the same point — they described a hex rather than the ground. A band tint
## shades a plateau and the cliff below it identically, hex-edge contours draw
## slopes that follow hex geometry instead of terrain, and one hatched hexagon
## claims a whole 25-square-mile tile is impassable because part of it is.
## Per CLAUDE.md §3 none of that should have read HexCell at all.
##
## The replacement is a hillshade at raster resolution (see ReliefImageBuilder
## for what that resolution actually is), which shades by SLOPE. Slope is what
## the eye reads as height, and it needs no band boundary, no legend, and no hex.
##
## This is the COARSE, whole-map half. ReliefTileView draws 30 m per-hex tiles
## on top of it in Tactical, for the hexes actually on screen; this layer covers
## the entire corridor in one texture and is what Strategic zoom needs. Both are
## gated on the same DisplaySettings.show_terrain_hazards, since they are two
## resolutions of one cue rather than two features.
##
## NOT fog-gated, on the precedent CoastlineOutlineView and SeaView already
## set: the shape of the land — where the coast is, where the mountains are —
## is public knowledge rather than a gameplay secret, unlike buildings, hordes
## or resource detail. It also stays useful exactly when it matters most,
## which is planning a route into ground you have not explored yet.
## design_doc.md §4 lists "macro elevation contours" as part of the Strategic
## overview for the same reason.
##
## Shown at BOTH zooms, unlike StrategicOverlayManager, whose whole node hides
## the moment the camera enters Tactical — the view the player actually fights
## in is the one that most needs to show which ground is high and which cannot
## be walked on.
##
## Placed in Main.tscn after CoastlineOutlineView and BEFORE LocalDetailManager/
## StrategicOverlayManager/TacticalEntityLayer. This draws at Z_INDEX above the
## terrain mesh but below every entity, so props, buildings, units and markers
## all stay on top of it.

## Above TerrainMeshView's GROUND_Z_INDEX (-3), HexGridMap's flat tile (-4) and
## TerrainDetailView's props (-2), below the default 0 every entity draws at.
## z_index is a GLOBAL sort key in this project (LocalDetailManager's own doc
## comment), so this is an ordering against those layers specifically, not
## just against siblings. See SeaView.gd's stack comment for the full list.
const Z_INDEX: int = -1

@export var hex_grid_map_path: NodePath

var _hex_grid_map: HexGridMap
var _texture: ImageTexture
var _rect: Rect2


func _ready() -> void:
	z_index = Z_INDEX
	# Bilinear, not nearest: the elevation samples are ~878 m apart and the
	# real surface between them genuinely is a smooth ramp, so interpolating
	# shows the slope the data implies. Nearest would show 878 m squares,
	# which is the per-tile look this class exists to get away from — just at
	# a smaller tile.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	DisplaySettings.changed.connect(_sync_visibility)
	_sync_visibility()
	if hex_grid_map_path == NodePath():
		return
	_hex_grid_map = get_node(hex_grid_map_path)
	_hex_grid_map.generation_completed.connect(_on_generation_completed)
	# HexGridMap generates synchronously in its own _ready(); if it is an
	# earlier sibling (it is) that has already happened and the signal has
	# already fired. Same race CoastlineOutlineView covers the same way.
	if not _hex_grid_map.get_all_cells().is_empty():
		_on_generation_completed(0)


## Elevation and passability are both fixed for the life of a map — nothing
## re-elevates ground, and the one system that changes passability
## (ReclamationManager draining WETLAND) does it by regenerating through
## HexMapGenerator, which re-emits generation_completed. So there is no
## per-cell signal to listen to and no reason to rebuild otherwise.
func _on_generation_completed(_cell_count: int) -> void:
	_rebuild()
	queue_redraw()


func _sync_visibility() -> void:
	visible = DisplaySettings.show_terrain_hazards


func _rebuild() -> void:
	var image := ReliefImageBuilder.build(_hex_grid_map)
	if image == null:
		_texture = null
		return
	_texture = ImageTexture.create_from_image(image)
	_rect = ReliefImageBuilder.world_rect(image)


func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(_texture, _rect, false)
