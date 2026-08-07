class_name HexCellView
extends Node2D

## Visual for a single hex: a hex-shaped Polygon2D tinted/textured by
## biome/soil, with a thin outline. Real terrain art landed via
## TerrainVisuals.terrain_texture() — a biome with no art yet still falls
## back to the original flat TerrainVisuals.biome_color() fill, so art can
## land one biome at a time with zero code changes here.
##
## Two GroundMode looks, drawn from the SAME texture resource via Polygon2D
## UV/repeat parameters — no duplicate art, no duplicate import config:
##   - ICON (Strategic): explicit `uv` (HexCoord.corner_uvs(), the hex's own
##     6 corners normalized to [0,1]) paints the whole texture once across
##     the hex — reads like a map symbol.
##   - TILED (Tactical): empty `uv` (Godot's own local-vertex-position UV
##     generation, see Polygon2D's engine source) + texture_repeat=ENABLED
##     + a tuned texture_scale — repeats the texture as a naturalistic
##     ground material across Phase 2.5.6's true-scale in-hex space, rather
##     than one image stretched blurrily across a real 5x5-mile hex.
## Fog tinting (set_fog_state(), below) composes identically over either
## mode — `modulate` multiplies whatever the node already rendered,
## independent of how that came to be (flat color vs. sampled texture).

enum GroundMode { ICON, TILED }

## World units per texture repeat in TILED mode — a quarter of HexCoord.HEX_SIZE,
## so a hex's true-scale footprint shows several repeats rather than one
## giant stretched copy. Pure visual-density tuning, no gameplay meaning.
const TACTICAL_GROUND_TILE_SIZE: float = 128.0

var cell: HexCell
var _ground_mode: GroundMode = GroundMode.ICON

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
## once the child Polygon2D/Line2D exist. `ground_mode` defaults to ICON —
## HexGridMap's own Strategic-view spawn call needs no changes; only
## TacticalHexView (its own ground layer) passes TILED explicitly.
func setup(p_cell: HexCell, ground_mode: GroundMode = GroundMode.ICON) -> void:
	cell = p_cell
	_ground_mode = ground_mode
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
	_outline.points = points

	var texture := TerrainVisuals.terrain_texture(cell.biome_type, cell.soil_fertility)
	_polygon.texture = texture
	_polygon.color = Color.WHITE if texture else TerrainVisuals.biome_color(cell.biome_type, cell.soil_fertility)

	var tiled := texture != null and _ground_mode == GroundMode.TILED
	_polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED if tiled else CanvasItem.TEXTURE_REPEAT_DISABLED
	_polygon.texture_scale = (texture.get_size() / TACTICAL_GROUND_TILE_SIZE) if tiled else Vector2.ONE
	_polygon.uv = PackedVector2Array() if tiled else HexCoord.corner_uvs()
