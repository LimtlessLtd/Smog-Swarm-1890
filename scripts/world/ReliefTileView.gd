class_name ReliefTileView
extends Node2D

## Streams the baked 30 m relief tiles around the camera and draws them as
## light and shadow over the terrain.
##
## The detail half of a two-layer relief scheme:
##   - ElevationReliefView draws ONE whole-corridor hillshade texture, always,
##     at the coarse raster's resolution. It covers the entire map for nothing
##     and is what a strategic-zoom overview needs.
##   - this class draws per-hex tiles at 30 m (assets/terrain_data/relief/,
##     written by tools/geo_bake/bake_fine_relief.py) for the handful of hexes
##     actually on screen, and only in Tactical.
##
## Same coarse-everywhere-plus-fine-nearby split TerrainMeshView already has
## against HexGridMap's flat per-hex tile, and for the same reason: the fine
## data is far too large to hold for the whole corridor at once (~160 MB of
## tiles), and at strategic zoom its detail is smaller than a pixel anyway.
##
## Drawing both layers together is deliberate and does not double-shade
## noticeably: the coarse layer is derived from a ~3.5 km sampling interval, so
## it carries only broad regional slope, while these tiles carry the valley and
## ridge detail that interval cannot represent. Where they overlap the coarse
## layer is close to flat (transparent) precisely because it has no detail to
## show there.
##
## Tiles are addressed exactly like the land-cover fine tiles
## (RealTerrainSampler's "Fine per-hex tiles"): one per hex coordinate, spanning
## HexCoord.SUB_HEX_GRID_SPAN, HexCoord.SUB_HEX_GRID_N pixels across. The origin
## is SNAPPED to a global lattice -- see tile_origin(), which must stay in step
## with bake_fine_relief.tile_origin_world().

## Must match bake_fine_relief.py's FINE_TILE_PIXELS / FINE_TILE_WORLD_SIZE,
## which are themselves HexCoord's own sub-hex constants. Named here rather
## than used inline so the correspondence is greppable from both sides.
const TILE_PIXELS: int = HexCoord.SUB_HEX_GRID_N
const TILE_WORLD_SIZE: float = HexCoord.SUB_HEX_GRID_SPAN

const TILE_DIR: String = "res://assets/terrain_data/relief"

## Shares ElevationReliefView's -1, rather than sitting between it and the
## entities: z_index is an integer and there is nothing between -1 and the 0
## every entity draws at, so a layer that must be above the coarse relief and
## below every unit has to tie and be resolved by tree order. This node is
## placed immediately after ElevationReliefView in Main.tscn, which is what puts
## the fine tiles on top of the coarse texture.
##
## Same tie applies to FogVisuals.TERRAIN_OVERLAY_Z_INDEX, also -1, and it
## resolves the same way it already does for the coarse layer: relief draws over
## fog. That is deliberate and inherited, not an oversight -- ElevationReliefView
## documents why the shape of the land is not fog-gated, and the two halves of
## one cue must not disagree about it. TerrainDetailView's props are the
## opposite case (tree cover should NOT show through fog) and sit in their own
## band below the fog overlay rather than sharing this tie -- see that class's
## own comment.
const Z_INDEX: int = -1

## Extra ring of hexes kept loaded outside the visible area, so panning does not
## stream at the screen edge.
const LOAD_MARGIN_HEXES: int = 1

## Tiles decoded per frame. Each is a 333x333 PNG read from disk and turned into
## a texture; several in one frame is a visible hitch while panning, and the
## coarse layer underneath already covers anything not yet loaded, so there is
## nothing to see while the queue drains.
const TILES_LOADED_PER_FRAME: int = 2

## Refuses to stream at all beyond this many tiles on screen. Not a normal-play
## limit -- at the Tactical band's widest framing the visible set is a couple of
## dozen -- but a pathological zoom threshold or viewport must not be able to
## queue hundreds of texture loads. Over the cap this layer simply switches off
## and ElevationReliefView's whole-map texture remains, which is the correct
## thing to show when zoomed that far out anyway.
const MAX_TILES_IN_VIEW: int = 96

@export var camera_path: NodePath

var _camera: CameraController
var _material: ShaderMaterial
var _tiles: Dictionary = {}  ## Vector2i -> Sprite2D
var _load_queue: Array[Vector2i] = []
var _missing: Dictionary = {}  ## Vector2i -> true, hexes with no baked tile — cached so a miss is not retried every frame.


## World position of a tile's top-left pixel, snapped to the same global
## lattice bake_fine_relief.tile_origin_world() snaps to.
##
## Tiles span TILE_WORLD_SIZE but hex centres sit closer together than that, so
## neighbouring tiles overlap. The snap makes every tile's pixel grid a subset
## of one global lattice, so overlapping pixels hold identical values and the
## overlap is exact duplication rather than a seam. Verified against the bake:
## adjacent tiles differ by an integral pixel offset and agree bit-for-bit
## across their shared area.
static func tile_origin(coord: Vector2i) -> Vector2:
	var centre := HexCoord.axial_to_world(coord)
	var step := TILE_WORLD_SIZE / float(TILE_PIXELS)
	return Vector2(
		floor((centre.x - TILE_WORLD_SIZE * 0.5) / step) * step,
		floor((centre.y - TILE_WORLD_SIZE * 0.5) / step) * step)


func _ready() -> void:
	z_index = Z_INDEX
	# Linear, so the 30 m samples interpolate smoothly rather than showing as
	# 3-world-unit squares when the camera is zoomed right in.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var shader: Shader = load("res://assets/shaders/relief_hillshade.gdshader")
	_material = ShaderMaterial.new()
	_material.shader = shader

	DisplaySettings.changed.connect(_sync_visibility)
	if camera_path == NodePath():
		push_error("ReliefTileView: camera_path is unset, no tiles will stream")
		set_process(false)
		return
	# get_node_or_null + an explicit type check, not get_node(): a camera_path
	# that resolves to nothing (or to the wrong node) otherwise fails as a null
	# access inside _process, once per frame forever, rather than once at
	# startup where it can be read. Same guard TerrainMeshView already applies
	# to the identical export.
	_camera = get_node_or_null(camera_path) as CameraController
	if _camera == null:
		push_error("ReliefTileView: camera_path does not resolve to a CameraController")
		set_process(false)
		visible = false
		return
	_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
	_sync_visibility()


## Which tiles are wanted has to be polled: panning changes it continuously and
## CameraController has no per-move signal. TerrainMeshView and
## LocalDetailManager poll the same way for the same reason. The poll itself is
## a handful of integer comparisons, and work only happens when the wanted set
## actually changes.
func _process(_delta: float) -> void:
	if not visible:
		return
	_sync_wanted_tiles()
	for _i in TILES_LOADED_PER_FRAME:
		if _load_queue.is_empty():
			return
		_load_tile(_load_queue.pop_front())


func _on_tactical_mode_changed(_is_tactical: bool) -> void:
	_sync_visibility()


func _sync_visibility() -> void:
	# Shares DisplaySettings.show_terrain_hazards with ElevationReliefView: they
	# are two resolutions of one cue, and a player switching "terrain relief"
	# off means both, not the coarse half only.
	var wanted := DisplaySettings.show_terrain_hazards and _camera != null and _camera.is_tactical_zoom()
	if wanted == visible:
		return
	visible = wanted
	if not visible:
		_clear_all()


func _visible_hexes() -> Array[Vector2i]:
	var viewport_size := get_viewport_rect().size
	# Camera2D.zoom is a MAGNIFICATION factor, so visible size is viewport /
	# zoom -- CameraController's own doc comment records getting this backwards
	# once.
	var half_world := viewport_size / _camera.zoom / 2.0
	var centre := _camera.get_screen_center_position()
	var centre_hex := HexCoord.world_to_axial(centre)
	var hex_spacing := sqrt(3.0) * HexCoord.HEX_SIZE  ## Real centre-to-centre neighbour distance, NOT HEX_SIZE (the circumradius).
	var radius := int(ceil(maxf(half_world.x, half_world.y) / hex_spacing)) + LOAD_MARGIN_HEXES
	return HexCoord.hex_disk(centre_hex, radius)


func _sync_wanted_tiles() -> void:
	var wanted_list := _visible_hexes()
	if wanted_list.size() > MAX_TILES_IN_VIEW:
		_clear_all()
		return

	var wanted: Dictionary = {}
	for coord in wanted_list:
		wanted[coord] = true
		if not _tiles.has(coord) and not _missing.has(coord) and not _load_queue.has(coord):
			_load_queue.append(coord)

	for coord in _tiles.keys():
		if not wanted.has(coord):
			_tiles[coord].queue_free()
			_tiles.erase(coord)

	# A queued tile that left the view before its turn is dropped rather than
	# loaded and immediately freed. Rebuilt element by element, not via
	# Array.filter() -- that returns an untyped Array, and assigning one to an
	# Array[Vector2i] is a runtime error rather than a compile-time one.
	var still_wanted: Array[Vector2i] = []
	for coord in _load_queue:
		if wanted.has(coord):
			still_wanted.append(coord)
	_load_queue = still_wanted


## Image.load() rather than ResourceLoader, matching how RealTerrainSampler
## reads the land-cover fine tiles: it bypasses the texture-import pipeline,
## which could re-encode an 8-bit greyscale ramp lossily and put false steps
## into shading whose whole purpose is to be smooth.
##
## A hex with no baked tile is recorded in _missing rather than retried --
## outside the baked corridor there is nothing to load, and without the marker
## _sync_wanted_tiles() would re-queue it every frame.
func _load_tile(coord: Vector2i) -> void:
	var path := "%s/%d_%d.png" % [TILE_DIR, coord.x, coord.y]
	if not FileAccess.file_exists(path):
		_missing[coord] = true
		return
	var image := Image.new()
	if image.load(path) != OK:
		_missing[coord] = true
		return

	# Clipped to the hexagon, NOT drawn as the full square the texture covers.
	#
	# A tile spans TILE_WORLD_SIZE while hex centres sit closer together, so
	# full-square tiles overlap — and overlapping alpha COMPOUNDS. Two tiles
	# agreeing exactly about a pixel still blend that pixel twice, which shaded
	# every doubly-covered region harder than its neighbours and drew a visible
	# rectangular grid across the map. (The bake's lattice snapping guarantees
	# the two tiles hold identical VALUES there; it cannot stop them being
	# composited twice. Verifying the values matched was not enough, and the
	# grid only showed up once the shading was strong enough to see.)
	#
	# One hexagon per hex tiles the plane exactly: no gaps, no overlap, so every
	# pixel is composited once. The data underneath is one continuous lattice,
	# so neighbouring hexagons agree across their shared edge and the seam is
	# invisible.
	var origin := tile_origin(coord)
	var scale_factor := TILE_WORLD_SIZE / float(TILE_PIXELS)
	var corners := HexCoord.corner_points(HexCoord.axial_to_world(coord))

	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	points.resize(corners.size())
	uvs.resize(corners.size())
	for i in corners.size():
		points[i] = corners[i] - origin  ## Node sits at the tile origin, so geometry is local to it — see position below.
		uvs[i] = points[i] / scale_factor  ## Polygon2D UVs are in TEXTURE PIXELS, not normalised.

	var polygon := Polygon2D.new()
	polygon.polygon = points
	polygon.uv = uvs
	polygon.texture = ImageTexture.create_from_image(image)
	polygon.material = _material  ## One shared material across every tile — nothing here is per-tile, and a material each would be a needless state change per draw.
	polygon.position = origin
	add_child(polygon)
	_tiles[coord] = polygon


func _clear_all() -> void:
	for coord in _tiles:
		_tiles[coord].queue_free()
	_tiles.clear()
	_load_queue.clear()
