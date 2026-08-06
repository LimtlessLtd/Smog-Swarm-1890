class_name HexCellView
extends Node2D

## Placeholder visual for a single hex: a flat-colored polygon tinted by
## biome/soil, with a thin outline. No art assets exist yet — swap
## _biome_color()/_soil_color() for a tile-texture lookup once they do; the
## rest of the pipeline (HexGridMap, HexMapGenerator) won't need to change.

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

func _redraw() -> void:
	var points := HexCoord.corner_points(Vector2.ZERO)
	_polygon.polygon = points
	_polygon.color = _biome_color(cell.biome_type, cell.soil_fertility)
	_outline.points = points

func _biome_color(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility) -> Color:
	match biome:
		GameEnums.BiomeType.URBAN:
			return Color(0.42, 0.38, 0.35)
		GameEnums.BiomeType.INDUSTRIAL:
			return Color(0.25, 0.22, 0.22)
		GameEnums.BiomeType.HIGHLAND:
			return Color(0.48, 0.46, 0.38)
		GameEnums.BiomeType.WATERWAY:
			return Color(0.29, 0.46, 0.63)
		GameEnums.BiomeType.WETLAND:
			return Color(0.33, 0.40, 0.28)
		GameEnums.BiomeType.FARMLAND, GameEnums.BiomeType.MOORLAND:
			return _soil_color(soil)
		_:
			return Color(0.5, 0.5, 0.5)

func _soil_color(soil: GameEnums.SoilFertility) -> Color:
	match soil:
		GameEnums.SoilFertility.LUSH:
			return Color(0.36, 0.56, 0.27)
		GameEnums.SoilFertility.POOR:
			return Color(0.55, 0.52, 0.35)
		GameEnums.SoilFertility.DESOLATE:
			return Color(0.35, 0.32, 0.30)
		_:
			return Color(0.5, 0.5, 0.5)
