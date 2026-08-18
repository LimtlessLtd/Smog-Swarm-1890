class_name TerrainMeshView
extends Node2D

## Draws the baked vector terrain mesh (TerrainMeshChunkData) as textured
## triangles, streaming chunks in and out around the camera.
##
## This is the rendering half of the Real-Geography Vector Terrain epic and
## the thing that makes the boundaries stop being squares: the triangles are
## the real OpenStreetMap polygon geometry, so a river is a river-shaped
## ribbon and a wood is a wood-shaped patch, neither of them quantized to a
## sample grid and neither of them cut off at a hex edge.
##
## It owns loading and drawing ONLY. It classifies nothing, samples nothing,
## and answers no queries about terrain -- SubHexTerrainQuery still owns that,
## and still reads the raster (epic Phase 2 moves it onto this same vector
## data; until then the two can disagree at a boundary by up to the raster's
## own cell size, which is what Phase 2 exists to remove).
##
## Textures are the SAME hand-drawn SVGs TerrainVisuals already provides, not
## new art -- the geometry changed, the look did not. Each biome's texture is
## tiled in WORLD space at TEXTURE_WORLD_SIZE, so it neither stretches with a
## triangle's size nor restarts at a chunk or hex boundary; a triangle is a
## window onto one continuous ground texture rather than a tile of its own.
##
## What this does NOT do yet, and where it goes: no blending across a biome
## boundary (Phase 3's N-texture weighted shader -- today a boundary is a hard
## edge, correct in shape but abrupt), no elevation displacement (Phase 4),
## and no runtime re-triangulation when SubHexTerrainOverride writes (Phase 6,
## so a Town Hall's urban disc does not yet appear in the mesh).

## Repeat distance for a terrain texture, in world units. Matches
## SubHexGroundView's own rendered cell (SUB_HEX_GRID_SPAN / its _GRID_N of
## 11) so texture density is unchanged from what the squares showed -- the
## point of this class is to change the SHAPE of the boundaries, and a
## simultaneous change in texture scale would confuse reading whether it
## worked.
const TEXTURE_WORLD_SIZE: float = HexCoord.SUB_HEX_GRID_SPAN / 11.0

## Terrain sits below every entity. -1 is the band TacticalHexView's square
## ground used to occupy; both it and HexGridMap's flat Strategic tile moved
## down one when this class took the band, so this draws over them rather
## than fighting them for the same key (z_index is a GLOBAL sort key, so
## sharing one with another ground layer resolves by tree order and would
## flicker as hexes hydrate).
const GROUND_Z_INDEX: int = -1

## Chunks are kept loaded this far outside the visible rect, so panning does
## not stream at the screen edge. Half a chunk.
const LOAD_MARGIN_WU: float = 2048.0

## Building a chunk walks tens of thousands of triangles in GDScript, which is
## a visible hitch if several land on one frame. One per frame keeps the cost
## bounded while panning; a chunk covers 40 km, so the queue is rarely deep.
const CHUNKS_BUILT_PER_FRAME: int = 1

## Above this many chunks in view the camera is too far out for the mesh to
## read as anything but noise, and building them would cost far more than it
## shows. Strategic zoom keeps HexGridMap's flat per-hex tiles.
const MAX_CHUNKS_IN_VIEW: int = 9

@export var camera_path: NodePath

var _camera: CameraController
var _chunk_nodes: Dictionary = {}  ## Vector2i -> Node2D holding that chunk's surfaces.
var _build_queue: Array[Vector2i] = []


func _ready() -> void:
	z_index = GROUND_Z_INDEX
	# The SVGs are small and tiled across whole chunks, so they must repeat
	# rather than clamp. texture_repeat inherits down the canvas tree, so
	# setting it here covers every MeshInstance2D this node creates.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	if camera_path.is_empty():
		push_error("TerrainMeshView: camera_path is unset, nothing will render")
		set_process(false)
		return
	_camera = get_node_or_null(camera_path) as CameraController
	if _camera == null:
		push_error("TerrainMeshView: camera_path does not resolve to a CameraController")
		set_process(false)
		return
	_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
	visible = _camera.is_tactical_zoom()


## Only the VISIBILITY of the whole layer is signal-driven; which chunks are
## wanted still has to be polled, because panning changes it continuously and
## CameraController has no per-move signal (LocalDetailManager polls the same
## way, for the same reason). The poll itself is a handful of integer
## comparisons -- work only happens when the wanted set actually changes.
func _process(_delta: float) -> void:
	if not visible:
		return
	_sync_wanted_chunks()
	for _i in CHUNKS_BUILT_PER_FRAME:
		if _build_queue.is_empty():
			return
		_build_chunk(_build_queue.pop_front())


func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical


## World rect the camera can currently see. Camera2D.zoom is a MAGNIFICATION
## factor, so visible size is viewport / zoom -- see CameraController's own
## doc comment, which records getting this backwards once.
func _visible_world_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	var world_size := viewport_size / _camera.zoom
	return Rect2(_camera.get_screen_center_position() - world_size * 0.5, world_size)


func _sync_wanted_chunks() -> void:
	var rect := _visible_world_rect().grow(LOAD_MARGIN_WU)
	var lo := TerrainMeshChunkData.chunk_address(rect.position)
	var hi := TerrainMeshChunkData.chunk_address(rect.end)
	var span_x := hi.x - lo.x + 1
	var span_y := hi.y - lo.y + 1
	if span_x * span_y > MAX_CHUNKS_IN_VIEW:
		_clear_all()
		return

	var wanted: Dictionary = {}
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var address := Vector2i(cx, cy)
			wanted[address] = true
			if not _chunk_nodes.has(address) and not _build_queue.has(address):
				_build_queue.append(address)

	for address in _chunk_nodes.keys():
		if not wanted.has(address):
			_chunk_nodes[address].queue_free()
			_chunk_nodes.erase(address)
	# A queued address that left the view before its turn is dropped rather
	# than built and immediately freed. Rebuilt element by element, not via
	# Array.filter() -- that returns an untyped Array, and assigning one to an
	# Array[Vector2i] is a runtime error, not a compile-time one.
	var still_wanted: Array[Vector2i] = []
	for address in _build_queue:
		if wanted.has(address):
			still_wanted.append(address)
	_build_queue = still_wanted


func _clear_all() -> void:
	for address in _chunk_nodes:
		_chunk_nodes[address].queue_free()
	_chunk_nodes.clear()
	_build_queue.clear()


## One Node2D per chunk holding one MeshInstance2D per (biome, soil) pair.
## Grouping is what keeps this to a handful of draw calls for ~40,000
## triangles -- SubHexGroundView needs 121 Sprite2D nodes for a single hex.
##
## A chunk with no baked file is recorded as an empty node rather than
## retried: outside the baked corridor there is nothing to load, and without
## the marker _sync_wanted_chunks() would re-queue it every frame.
func _build_chunk(address: Vector2i) -> void:
	var container := Node2D.new()
	container.name = "Chunk_%d_%d" % [address.x, address.y]
	_chunk_nodes[address] = container
	add_child(container)

	var data := TerrainMeshChunkData.load_chunk(address.x, address.y)
	if data == null:
		return

	# Accumulates into plain Arrays, not PackedVector3Arrays: a Packed array is
	# copy-on-write and the Dictionary holds a reference, so the
	# read-append-write-back a Packed accumulator needs risks copying the whole
	# array per triangle. Array is a reference and appends in place, and the
	# one conversion to Packed happens per surface in _build_surface().
	var triangles_by_key: Dictionary = {}  ## Vector2i(biome, soil) -> Array[Vector2]
	var soil_cache: Dictionary = {}
	var vertices := data.vertices
	var indices := data.indices
	for tri in data.triangle_count():
		var base := tri * 3
		var a := vertices[indices[base]]
		var b := vertices[indices[base + 1]]
		var c := vertices[indices[base + 2]]
		var biome := RealTerrainSampler.biome_from_code(data.triangle_biomes[tri])
		# Soil is resolved at the triangle's centroid, not per vertex: it only
		# selects which of a biome's SVG variants to use, and a per-vertex
		# answer could not be honoured by a single-texture surface anyway.
		var soil := _soil_at(biome, (a + b + c) / 3.0, soil_cache)
		var key := Vector2i(int(biome), int(soil))
		var points: Array = triangles_by_key.get(key, [])
		if points.is_empty():
			triangles_by_key[key] = points
		points.append(a)
		points.append(b)
		points.append(c)

	for key: Vector2i in triangles_by_key:
		container.add_child(_build_surface(key.x, key.y, triangles_by_key[key]))


## SubHexSoilQuery.soil_for_biome_at() memoized per TEXTURE_WORLD_SIZE cell.
##
## For FARMLAND and MOORLAND -- 68% of the corridor's triangles -- that call
## evaluates a FastNoiseLite field, and per triangle it measured 85 ms of a
## 145 ms chunk build. The noise varies over hex-scale distances, so sampling
## it per ~25-wu triangle was resolving detail the field does not contain;
## one answer per rendered texture cell is exactly the granularity
## SubHexGroundView's square grid already had.
func _soil_at(biome: GameEnums.BiomeType, world_pos: Vector2, cache: Dictionary) -> GameEnums.SoilFertility:
	var cell := Vector2i((world_pos / TEXTURE_WORLD_SIZE).floor())
	var key := Vector3i(int(biome), cell.x, cell.y)
	var hit: Variant = cache.get(key)
	if hit != null:
		return hit
	var soil := SubHexSoilQuery.soil_for_biome_at(biome, world_pos)
	cache[key] = soil
	return soil


## One MeshInstance2D for one (biome, soil) pair's triangles.
##
## Vertices are absolute world positions and this node's transform is
## identity, so no per-chunk offset is applied or needed. Unlike the preview
## tool, the values stay in float32 range comfortably here: a mesh vertex is
## quantized to a 1.0-wu grid and never differenced against a neighbour on
## the CPU, so the precision that broke Godot's ear-clipper at ~1.2e5 in
## scripts/test/preview_terrain_mesh.gd does not arise.
func _build_surface(biome: GameEnums.BiomeType, soil: GameEnums.SoilFertility,
		world_points: Array) -> MeshInstance2D:
	# Both packed arrays are sized once and filled by index -- no append, so
	# no reallocation across tens of thousands of vertices.
	var count := world_points.size()
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	points.resize(count)
	uvs.resize(count)
	for i in count:
		var point: Vector2 = world_points[i]
		points[i] = Vector3(point.x, point.y, 0.0)
		uvs[i] = point / TEXTURE_WORLD_SIZE

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance := MeshInstance2D.new()
	instance.mesh = mesh
	# terrain_texture() returns null for any biome whose SVG has not been
	# authored (OCEAN today). Falling back to the flat biome colour is the
	# same "art lands one file at a time" contract HexCellView already
	# follows, and self_modulate tints the untextured white mesh directly.
	var texture := TerrainVisuals.terrain_texture(biome, soil)
	if texture != null:
		instance.texture = texture
	else:
		instance.self_modulate = TerrainVisuals.biome_color(biome, soil)
	return instance
