class_name CoastlineOutlineView
extends Node2D

## User request: "let's ensure our hex tile map is representative of the
## entire UK and Ireland and that we can at least see the outline of the
## UK even when it's in fog of war or completely undiscovered." Every
## other visual layer in this project (HexCellView's own terrain, every
## StrategicOverlayManager marker) is gated by Fog of War in some way —
## this one deliberately ISN'T: a landmass's own outline shape is public
## knowledge (recognizable to any player, not a gameplay secret the way
## biome detail, buildings or hordes are), so it draws once at generation
## time and stays visible regardless of UNSEEN/EXPLORED/VISIBLE state.
## It only ever draws a boundary LINE, never a filled interior — it can't
## leak more than "this coastline shape exists" no matter how
## undiscovered the country still is.
##
## Computed once from HexCell.biome_type (OCEAN vs. everything else) — the
## same data HexMapGenerator's landmass pass (BritishGeographyData) already
## produced, not a second source of truth. A coastal edge is any hex
## boundary between a land hex and an ocean-or-off-map neighbor. Drawn via
## plain CanvasItem.draw_line() calls in a single _draw() (cheap — called
## once at generation and cached by the renderer afterward, same as any
## other static _draw() content, not a per-frame cost) rather than a Line2D
## per segment: there's no single continuous polyline here (Great Britain
## and Ireland are two disconnected coastlines, each its own separate
## ring), and one static draw call per edge is simpler than stitching
## per-loop polylines back together from a flat edge set.
##
## Parented as a HexGridMap sibling under WorldRoot, same reasoning as
## LocalDetailManager/StrategicOverlayManager — shares its coordinate
## space. Placed right after HexGridMap in Main.tscn so it draws on top of
## (possibly UNSEEN-black) terrain by plain sibling order, underneath
## everything else.

const OUTLINE_COLOR: Color = Color(0.75, 0.72, 0.62, 0.85)
const OUTLINE_WIDTH: float = 3.0

@export var hex_grid_map_path: NodePath

var _hex_grid_map: HexGridMap
var _segments: PackedVector2Array = PackedVector2Array()  ## Pairs: [p0, p1, p0, p1, ...].

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
		_hex_grid_map.generation_completed.connect(_on_generation_completed)
		# HexGridMap generates synchronously in its OWN _ready() — if it's an
		# earlier sibling (it is), that's already run and generation_completed
		# already fired by the time this _ready() connects to it. Covers that
		# race directly rather than depending on sibling order never changing.
		if not _hex_grid_map.get_all_cells().is_empty():
			_on_generation_completed(0)

func _on_generation_completed(_cell_count: int) -> void:
	_rebuild_segments()
	queue_redraw()

func _rebuild_segments() -> void:
	_segments = PackedVector2Array()
	for cell: HexCell in _hex_grid_map.get_all_cells():
		if cell.biome_type == GameEnums.BiomeType.OCEAN:
			continue
		var corners := HexCoord.corner_points(HexCoord.axial_to_world(cell.coord))
		for i in range(6):
			var neighbor := _hex_grid_map.get_cell(cell.coord + HexCoord.NEIGHBOR_DIRECTIONS[i])
			var is_coastal_edge := neighbor == null or neighbor.biome_type == GameEnums.BiomeType.OCEAN
			if is_coastal_edge:
				_segments.append(corners[i])
				_segments.append(corners[(i + 1) % 6])

func _draw() -> void:
	for i in range(0, _segments.size(), 2):
		draw_line(_segments[i], _segments[i + 1], OUTLINE_COLOR, OUTLINE_WIDTH)
