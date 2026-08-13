class_name HexCellView
extends Node2D

## Visual for a single hex: a hex-shaped Polygon2D tinted/textured by
## biome/soil, with a thin outline. Real terrain art landed via
## TerrainVisuals.terrain_texture() — a biome with no art yet still falls
## back to the original flat TerrainVisuals.biome_color() fill, so art can
## land one biome at a time with zero code changes here.
##
## Both Strategic AND Tactical render the same way now: this class used to
## have two "GroundMode" looks — an ICON mode for Strategic zoom using an
## explicit 6-point uv array (one UV per hex corner, meant to paint the
## whole texture once as a map symbol) and a TILED mode for Tactical zoom
## using Godot's auto-generated per-vertex UV + texture_repeat. ICON mode
## never worked: a Polygon2D only SAMPLES a texture at each vertex's own UV
## coordinate and linearly interpolates those few samples across its
## interior — it does not warp/rasterize the source image into the
## polygon's screen shape. With only 6 sample points, all confined to a
## normalized [0,1] hex-corner mapping (the texture's own edges), most of a
## hand-drawn tile's real detail — concentrated away from the edges in
## every one of this project's seamlessly-tiling SVGs, by construction —
## never got sampled at all, rendering every Strategic hex as a near-flat
## blob instead of visible art (confirmed directly: 4 of urban.svg's 6
## corner-UV texels landed on nearly-identical tones). Fixed by using the
## SAME tiled draw parameters Tactical zoom already used correctly for
## every ground tile, Strategic included — GroundMode/HexCoord.corner_uvs()
## are gone; there's only one way to draw ground now. A Strategic hex's
## much smaller on-screen footprint just means more repeats are visible in
## fewer pixels — reads as a genuinely varied, textured surface instead of
## a flat color.
##
## Fog tinting (set_fog_state(), below) composes identically over either a
## flat-color or a textured hex — modulate multiplies whatever the node
## already rendered, independent of how that came to be.

const GROUND_TILE_SIZE: float = 128.0  ## World units per texture repeat — a quarter of HexCoord.HEX_SIZE, so a hex's true-scale footprint shows several repeats rather than one giant stretched copy.

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

## Tints the whole tile rather than touching the underlying biome/soil
## color, so FogOfWarManager can push updates here without this view
## needing to know anything about fog logic.
func set_fog_state(state: GameEnums.FogState) -> void:
	modulate = FogVisuals.tint_color(state)

## Re-draws against whatever `cell`'s fields currently hold — for a system
## that mutates a live HexCell after it was first spawned
## (ReclamationManager changing terrain_feature/biome_type/soil_fertility
## on drain) rather than HexGridMap regenerating the map from scratch.
func refresh() -> void:
	if cell and is_inside_tree():
		_redraw()

func _redraw() -> void:
	var points := HexCoord.corner_points(Vector2.ZERO)
	_polygon.polygon = points
	_outline.points = points

	var texture := TerrainVisuals.terrain_texture(cell.biome_type, cell.soil_fertility, cell.terrain_feature)
	_polygon.texture = texture
	_polygon.color = Color.WHITE if texture else TerrainVisuals.biome_color(cell.biome_type, cell.soil_fertility)

	# Empty uv (Godot's own local-vertex-position UV generation) + repeat
	# enabled + a tuned texture_scale — real per-pixel tiling, not a sparse
	# 6-point sample. See this class's own doc comment for why ICON mode
	# used to do this differently, and why that didn't work.
	_polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED if texture else CanvasItem.TEXTURE_REPEAT_DISABLED
	_polygon.texture_scale = (texture.get_size() / GROUND_TILE_SIZE) if texture else Vector2.ONE
	_polygon.uv = PackedVector2Array()
