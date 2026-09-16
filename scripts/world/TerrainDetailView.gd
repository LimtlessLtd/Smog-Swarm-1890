class_name TerrainDetailView
extends Node2D

## Draws the scatter decoration — trees, bushes, rocks, reeds — over the
## terrain mesh, streaming it with the same chunks the mesh streams.
##
## Replaces the per-hex prop scatter TacticalHexView used to draw. Two things
## were wrong with that and this fixes both:
##
##   - It only existed where LocalDetailManager hydrated a hex, which requires
##     a settlement, a building, or Zone of Control coverage. Wilderness — the
##     overwhelming majority of the map, and all of the ground a player scouts
##     across — had NO props at all. A wood five hexes out was a flat green
##     texture with nothing growing in it.
##   - Where it did exist it scattered into a disc off `HexCell.biome_type`,
##     ignoring the real polygon the mesh draws underneath. See
##     TerrainDetailScatter for what that looked like and why.
##
## One MultiMeshInstance2D per prop type per chunk, NOT a node per prop. A
## chunk of thick woodland carries thousands of trees, and a Sprite2D each
## would be thousands of nodes per chunk and tens of thousands on screen —
## which is why the old scatter had to be confined to a handful of hexes in
## the first place. Instanced, the whole visible map costs a few draw calls
## and the density can be set by what the terrain should look like rather than
## by what a node count can bear.
##
## Owns the props for GAMEPLAY too (get_props_at(), which
## LocalDetailManager forwards to UnitOrderController/HordeManager for local
## obstacle avoidance) rather than leaving a second scatter to do that. Two
## scatters would mean units dodging trees that are not drawn and walking
## through trees that are.

## Sprite size in world units at scale 1.0, matching what TacticalHexView drew
## props at so the change of mechanism is not also a change of size.
const PROP_DIAMETER: float = 20.0

## Below the entities and above the terrain mesh (-3). Props are ground
## dressing: a unit must draw over them, and they must draw over the ground
## they stand on.
##
## A distinct band below FogVisuals.TERRAIN_OVERLAY_Z_INDEX (-1), not tied to
## it: unlike ElevationReliefView/ReliefTileView (deliberately ABOVE fog —
## terrain shape is public knowledge, see that class's doc comment), tree
## cover is exactly the kind of gameplay detail fog should hide. This is one
## world-wide streamed layer, not a per-hex node, so — same as the ground
## mesh below it — the only way fog can cover it is by drawing OVER it, which
## an equal z_index can't guarantee (a tie resolves by tree/draw order, which
## is where "fog of war above the trees" broke: this shared -1 with the fog
## overlay and was added later in Main.tscn, so it always won the tie and drew
## over the mist regardless of fog state). See SeaView.gd's stack comment for
## the full band list this has to stay in step with.
const Z_INDEX: int = -2

## Chunks are kept loaded this far outside the visible rect so panning does not
## stream at the screen edge. Matches TerrainMeshView's own margin: the props
## and the ground they stand on should appear and disappear together.
const LOAD_MARGIN_WU: float = 2048.0

## Load and scatter run on worker threads (ChunkBuildQueue); what is left on
## the main thread is creating one MultiMesh per prop type and writing its
## instance transforms, so one per frame — same budget, and the same reason,
## as TerrainMeshView.CHUNKS_FINALIZED_PER_FRAME.
const CHUNKS_FINALIZED_PER_FRAME: int = 1

## Worker threads this view may occupy at once. TerrainMeshView takes the
## same number, so the two together leave pool threads free for everything
## else that uses WorkerThreadPool.
const MAX_BUILDS_IN_FLIGHT: int = 2

## Refuses to stream at all beyond this many chunks on screen, so a
## pathological zoom threshold or viewport cannot queue hundreds of scatters.
## Deliberately tighter than TerrainMeshView's own cap: the mesh is a few
## draw calls per chunk whatever the zoom, while this is thousands of
## instances whose detail is smaller than a pixel once the view is wide.
const MAX_CHUNKS_IN_VIEW: int = 25

@export var camera_path: NodePath

var _camera: CameraController
var _chunk_nodes: Dictionary = {}  ## Vector2i -> Node2D holding that chunk's MultiMeshInstance2Ds.
var _chunk_props: Dictionary = {}  ## Vector2i -> Dictionary[Vector2i hex -> Array[PropInstance]], built lazily by get_props_at().
var _chunk_scatter: Dictionary = {}  ## Vector2i -> Dictionary of the raw flat scatter arrays, kept so get_props_at() can answer without re-scattering.
var _builds := ChunkBuildQueue.new(TerrainDetailView.prepare_chunk, MAX_BUILDS_IN_FLIGHT)


func _ready() -> void:
	z_index = Z_INDEX
	if camera_path.is_empty():
		push_error("TerrainDetailView: camera_path is unset, nothing will render")
		set_process(false)
		return
	_camera = get_node_or_null(camera_path) as CameraController
	if _camera == null:
		push_error("TerrainDetailView: camera_path does not resolve to a CameraController")
		set_process(false)
		return
	_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
	visible = _camera.is_tactical_zoom()


## Which chunks are wanted has to be polled: panning changes it continuously
## and CameraController has no per-move signal. TerrainMeshView and
## LocalDetailManager poll the same way for the same reason.
func _process(_delta: float) -> void:
	if not visible:
		return
	_sync_wanted_chunks()
	_builds.pump()
	for _i in CHUNKS_FINALIZED_PER_FRAME:
		var finished := _builds.take_finished()
		if finished.is_empty():
			return
		_finalize_chunk(finished[0], finished[1])


func _exit_tree() -> void:
	_builds.wait_all()


## True once nothing is queued or building. For capture scripts that must not
## photograph half-streamed props.
func is_streaming_idle() -> bool:
	return _builds.is_idle()


func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical
	if not is_tactical:
		_clear_all()


## Props near `coord`, positioned RELATIVE TO THAT HEX'S CENTRE — the contract
## LocalDetailManager.get_props_at() already had, so its own callers
## (UnitOrderController/HordeManager obstacle avoidance) are unchanged.
##
## Returns [] for a hex whose chunk is not currently streamed, exactly as the
## per-hex scatter did for a dehydrated hex: prop avoidance only applies near
## the camera, which is also the only place a player can see it happen.
##
## PropInstance objects are built lazily, per hex, on first ask and then
## cached — the scatter itself is flat arrays precisely so that thousands of
## Resources are not allocated for props nothing ever queries.
func get_props_at(coord: Vector2i) -> Array[PropInstance]:
	var address := TerrainMeshChunkData.chunk_address(HexCoord.axial_to_world(coord))
	if not _chunk_scatter.has(address):
		return []
	var by_hex: Dictionary = _chunk_props.get(address, {})
	if by_hex.is_empty():
		by_hex = _build_hex_index(address)
		_chunk_props[address] = by_hex
	var hit: Variant = by_hex.get(coord)
	return hit if hit != null else [] as Array[PropInstance]


func _build_hex_index(address: Vector2i) -> Dictionary:
	var scatter: Dictionary = _chunk_scatter[address]
	var positions: PackedVector2Array = scatter["positions"]
	var types: PackedByteArray = scatter["types"]
	var rotations: PackedFloat32Array = scatter["rotations"]
	var scales: PackedFloat32Array = scatter["scales"]

	var by_hex: Dictionary = {}
	for i in positions.size():
		var coord := HexCoord.world_to_axial(positions[i])
		var prop := PropInstance.new(types[i] as GameEnums.PropType, positions[i] - HexCoord.axial_to_world(coord))
		prop.rotation = rotations[i]
		prop.scale = scales[i]
		# Not by_hex.get(coord, []): GDScript evaluates the default eagerly,
		# allocating a throwaway Array for every prop.
		if not by_hex.has(coord):
			by_hex[coord] = [] as Array[PropInstance]
		(by_hex[coord] as Array).append(prop)
	return by_hex


## World rect the camera can currently see. Camera2D.zoom is a MAGNIFICATION
## factor, so visible size is viewport / zoom — see CameraController's own doc
## comment, which records getting this backwards once.
func _visible_world_rect() -> Rect2:
	var world_size := get_viewport_rect().size / _camera.zoom
	return Rect2(_camera.get_screen_center_position() - world_size * 0.5, world_size)


func _sync_wanted_chunks() -> void:
	var rect := _visible_world_rect().grow(LOAD_MARGIN_WU)
	var lo := TerrainMeshChunkData.chunk_address(rect.position)
	var hi := TerrainMeshChunkData.chunk_address(rect.end)
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > MAX_CHUNKS_IN_VIEW:
		_clear_all()
		return

	var wanted: Dictionary = {}
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var address := Vector2i(cx, cy)
			wanted[address] = true
			if not _chunk_nodes.has(address):
				_builds.request(address)

	for address in _chunk_nodes.keys():
		if not wanted.has(address):
			_free_chunk(address)

	# An address that left the view before its build finished is dropped
	# rather than built and immediately freed.
	_builds.retain_only(wanted)


## Worker-thread half of a chunk build: file read, scatter, and grouping by
## prop type. Static and touching nothing but its arguments, per
## ChunkBuildQueue's contract. Returns {} for an unbaked or empty chunk.
static func prepare_chunk(address: Vector2i) -> Dictionary:
	var data := TerrainMeshChunkData.load_chunk(address.x, address.y)
	if data == null:
		return {}

	var positions := PackedVector2Array()
	var types := PackedByteArray()
	var rotations := PackedFloat32Array()
	var scales := PackedFloat32Array()
	TerrainDetailScatter.scatter(data, address, positions, types, rotations, scales)
	if positions.is_empty():
		return {}

	# Grouped by prop type, because a MultiMesh carries one mesh and one
	# texture: a tree and a rock cannot share an instance buffer. Not
	# `indices_by_type.get(type, [])`: the default is built eagerly, one
	# throwaway Array per prop, and an untyped Array boxes every index —
	# 6.10 ms -> 3.27 ms across 12 chunks (bench_chunk_build.gd).
	var indices_by_type: Dictionary = {}  ## int prop type -> PackedInt32Array
	for i in types.size():
		var prop_type := types[i]
		if not indices_by_type.has(prop_type):
			indices_by_type[prop_type] = PackedInt32Array()
		indices_by_type[prop_type].append(i)

	return {
		"positions": positions, "types": types,
		"rotations": rotations, "scales": scales,
		"indices_by_type": indices_by_type,
	}


## Main-thread half: nodes and MultiMeshes for a prepared chunk.
##
## A chunk with nothing to scatter is recorded as an empty node rather than
## retried: outside the baked corridor there is nothing to scatter into, and
## without the marker _sync_wanted_chunks() would re-request it forever.
func _finalize_chunk(address: Vector2i, prepared: Dictionary) -> void:
	var container := Node2D.new()
	container.name = "Detail_%d_%d" % [address.x, address.y]
	_chunk_nodes[address] = container
	add_child(container)
	if prepared.is_empty():
		return

	var positions: PackedVector2Array = prepared["positions"]
	var rotations: PackedFloat32Array = prepared["rotations"]
	var scales: PackedFloat32Array = prepared["scales"]
	_chunk_scatter[address] = {
		"positions": positions, "types": prepared["types"],
		"rotations": rotations, "scales": scales,
	}

	var indices_by_type: Dictionary = prepared["indices_by_type"]
	for prop_type: int in indices_by_type:
		var instance := _build_multimesh(prop_type, indices_by_type[prop_type], positions, rotations, scales)
		if instance != null:
			container.add_child(instance)


## One MultiMeshInstance2D for every prop of one type in one chunk.
##
## Returns null where the type has no authored art — the old per-prop path
## fell back to a procedural coloured polygon, which cannot be instanced and
## is not worth reviving: PropVisuals returns a texture for every type that
## exists today, and a type added without art should be invisible rather than
## drawn as a flat blob at forest density.
func _build_multimesh(prop_type: int, indices: PackedInt32Array, positions: PackedVector2Array,
		rotations: PackedFloat32Array, scales: PackedFloat32Array) -> MultiMeshInstance2D:
	var texture := PropVisuals.prop_texture(prop_type as GameEnums.PropType)
	if texture == null:
		return null

	# A unit quad in the XY plane; the per-instance transform does all the
	# sizing, so one mesh is shared by every prop of every type.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = quad
	multimesh.instance_count = indices.size()

	# Art is authored at whatever resolution it was drawn at, so the quad is
	# sized from the texture's aspect rather than assumed square — the same
	# reason ResourceBarView and HUDStyles.build_card() cannot just trust an
	# icon's own pixel size.
	var art_size := texture.get_size()
	var longest := maxf(art_size.x, art_size.y)
	var unit := Vector2(art_size.x / longest, art_size.y / longest) * PROP_DIAMETER

	for slot in indices.size():
		var i := indices[slot]
		multimesh.set_instance_transform_2d(slot,
			Transform2D(rotations[i], unit * scales[i], 0.0, positions[i]))

	var instance := MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.texture = texture
	return instance


func _free_chunk(address: Vector2i) -> void:
	_chunk_nodes[address].queue_free()
	_chunk_nodes.erase(address)
	_chunk_scatter.erase(address)
	_chunk_props.erase(address)


func _clear_all() -> void:
	for address in _chunk_nodes.keys():
		_chunk_nodes[address].queue_free()
	_chunk_nodes.clear()
	_chunk_scatter.clear()
	_chunk_props.clear()
	_builds.clear()
