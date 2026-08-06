class_name HexCellView
extends Node2D

## Placeholder visual for a single hex: a flat-colored polygon tinted by
## biome/soil, with a thin outline. No art assets exist yet — swap
## TerrainVisuals.biome_color()/soil_color() for a tile-texture lookup once
## they do; the rest of the pipeline (HexGridMap, HexMapGenerator) won't
## need to change.

var cell: HexCell

var _polygon: Polygon2D
var _outline: Line2D

func _ready() -> void:
	_polygon = Polygon2D.new()
	_outline = Line2D.new()
	_outline.width = 1.5
	_outline.default_color = Color(0.0, 0.0, 0.0, 0.35)
	_outline.closed = true
	add_child(_polygon)
	add_child(_outline)
	if cell:
		_redraw()

## Call before this node enters the tree; _ready() performs the actual draw
## once the child Polygon2D/Line2D exist.
func setup(p_cell: HexCell) -> void:
	cell = p_cell
	position = HexCoord.axial_to_world(cell.coord)
	if is_inside_tree():
		_redraw()

## Fog of War (Phase 2.6): tints the whole tile rather than touching the
## underlying biome/soil color, so FogOfWarManager can push updates here
## without this view needing to know anything about fog logic.
func set_fog_state(state: GameEnums.FogState) -> void:
	modulate = FogVisuals.tint_color(state)

## Re-draws against whatever `cell`'s fields currently hold — for a system
## that mutates a live HexCell after it was first spawned (Phase 4.2's
## ReclamationManager changing terrain_feature/biome_type/soil_fertility on
## drain) rather than HexGridMap regenerating the map from scratch.
func refresh() -> void:
	if cell and is_inside_tree():
		_redraw()

func _redraw() -> void:
	var points := HexCoord.corner_points(Vector2.ZERO)
	_polygon.polygon = points
	_polygon.color = TerrainVisuals.biome_color(cell.biome_type, cell.soil_fertility)
	_outline.points = points
