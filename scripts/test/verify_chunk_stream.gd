extends Node

## Locks down streamed chunk builds running on worker threads
## (ChunkBuildQueue, TerrainMeshView/TerrainDetailView.prepare_chunk()). Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_chunk_stream.tscn
##
## A scene rather than `-s`: CameraController is part of the live check, and
## script mode is where autoload-dependent classes fail to resolve.
##
## Four checks, each for a way the move off the main thread can be silently
## wrong:
##
## 1. The queue's own contract: bounded in-flight, no duplicate task per
##    address, and a build whose address left the wanted set — pending OR
##    already running — is never handed back.
## 2. A worker-thread prepare produces exactly what a main-thread prepare
##    does, with several running concurrently. A shared lazily-initialised
##    static (SubHexSoilQuery's noise was one) or any other cross-thread state
##    shows up here as a differing vertex, soil or prop.
## 3. The views, streaming for real around a camera that moves mid-build,
##    end with exactly the wanted chunks built and none of the stale ones.
## 4. What the views build from worker results matches the prepared data:
##    surface and prop counts per chunk, and get_props_at() answering.
##
## Exits non-zero on any failure.

## Enough chunks for several concurrent prepares and a spread of densities.
const _MAX_CHUNKS: int = 8
const _CONCURRENT_BUILDS: int = 4
## Tactical, and wide enough that the wanted set holds several chunks.
const _ZOOM: float = 0.3
const _STREAM_TIMEOUT_FRAMES: int = 3000

var _failures: Array[String] = []


func _ready() -> void:
	SubHexSoilQuery.ensure_initialized()
	_check_queue_contract()
	var addresses := _find_chunks()
	if addresses.is_empty():
		_fail("no baked chunks at %s" % TerrainMeshChunkData.CHUNK_DIR)
	else:
		_check_thread_equivalence(addresses)
		await _check_live_streaming(addresses)

	if _failures.is_empty():
		print("PASS: verify_chunk_stream")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("FAIL: verify_chunk_stream (%d)" % _failures.size())
		get_tree().quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
	print("  FAIL: " + message)


static func _slow_square(address: Vector2i) -> int:
	OS.delay_msec(30)
	return address.x * address.x + address.y


func _check_queue_contract() -> void:
	print("[1] ChunkBuildQueue contract")
	var queue := ChunkBuildQueue.new(_slow_square, 2)
	var a := Vector2i(1, 0)
	var b := Vector2i(2, 0)
	var c := Vector2i(3, 0)
	var d := Vector2i(4, 0)
	for address in [a, b, c, d, a]:
		queue.request(address)
	queue.pump()
	if not (queue.is_requested(a) and queue.is_requested(b) and queue.is_requested(c) and queue.is_requested(d)):
		_fail("a requested address is not reported as requested")

	# a and b are running (bound 2), c and d are pending. Drop b (running) and
	# d (pending); keep a and c.
	queue.retain_only({a: true, c: true})
	if queue.is_requested(d):
		_fail("a pending address dropped by retain_only() is still requested")

	var received: Dictionary = {}
	var started_at := Time.get_ticks_msec()
	while not queue.is_idle() and Time.get_ticks_msec() - started_at < 5000:
		queue.pump()
		var finished := queue.take_finished()
		if not finished.is_empty():
			if received.has(finished[0]):
				_fail("%s handed back twice" % finished[0])
			received[finished[0]] = finished[1]
		OS.delay_msec(1)

	if not queue.is_idle():
		_fail("queue did not drain within 5 s")
	if received.has(b):
		_fail("a running build dropped by retain_only() was handed back")
	if received.has(d):
		_fail("a pending build dropped by retain_only() was handed back")
	for address: Vector2i in [a, c]:
		if received.get(address) != _slow_square(address):
			_fail("%s handed back %s, expected %d" % [address, received.get(address), _slow_square(address)])

	# wait_all() must leave nothing running and nothing to hand back.
	queue.request(a)
	queue.request(b)
	queue.pump()
	queue.wait_all()
	if not queue.is_idle() or not queue.take_finished().is_empty():
		_fail("wait_all() left work behind")
	print("    handed back %d of 4 requested (2 dropped)" % received.size())


func _check_thread_equivalence(addresses: Array[Vector2i]) -> void:
	print("[2] worker-thread prepare == main-thread prepare, %d chunks, %d concurrent" % [addresses.size(), _CONCURRENT_BUILDS])
	var mesh_queue := ChunkBuildQueue.new(TerrainMeshView.prepare_chunk, _CONCURRENT_BUILDS)
	var detail_queue := ChunkBuildQueue.new(TerrainDetailView.prepare_chunk, _CONCURRENT_BUILDS)
	var wanted: Dictionary = {}
	for address in addresses:
		wanted[address] = true
		mesh_queue.request(address)
		detail_queue.request(address)
	mesh_queue.retain_only(wanted)
	detail_queue.retain_only(wanted)

	var mesh_results: Dictionary = {}
	var detail_results: Dictionary = {}
	var started_at := Time.get_ticks_msec()
	while (not mesh_queue.is_idle() or not detail_queue.is_idle()) and Time.get_ticks_msec() - started_at < 120000:
		mesh_queue.pump()
		detail_queue.pump()
		var finished := mesh_queue.take_finished()
		if not finished.is_empty():
			mesh_results[finished[0]] = finished[1]
		finished = detail_queue.take_finished()
		if not finished.is_empty():
			detail_results[finished[0]] = finished[1]
		OS.delay_msec(1)
	if mesh_results.size() != addresses.size() or detail_results.size() != addresses.size():
		_fail("worker prepares returned %d mesh / %d detail of %d" % [mesh_results.size(), detail_results.size(), addresses.size()])
		mesh_queue.wait_all()
		detail_queue.wait_all()
		return

	var surfaces_total := 0
	var props_total := 0
	for address in addresses:
		var expected_mesh := TerrainMeshView.prepare_chunk(address)
		var actual_mesh: Array = mesh_results[address]
		surfaces_total += actual_mesh.size()
		_compare_mesh(address, expected_mesh, actual_mesh)

		var expected_detail := TerrainDetailView.prepare_chunk(address)
		var actual_detail: Dictionary = detail_results[address]
		_compare_detail(address, expected_detail, actual_detail)
		if not actual_detail.is_empty():
			props_total += (actual_detail["positions"] as PackedVector2Array).size()
	print("    %d surfaces, %d props compared" % [surfaces_total, props_total])


func _compare_mesh(address: Vector2i, expected: Array, actual: Array) -> void:
	if expected.size() != actual.size():
		_fail("%s: %d surfaces on a worker, %d on main" % [address, actual.size(), expected.size()])
		return
	for i in expected.size():
		var e: Dictionary = expected[i]
		var a: Dictionary = actual[i]
		if e["biome"] != a["biome"] or e["soil"] != a["soil"]:
			_fail("%s surface %d: (%d,%d) on a worker, (%d,%d) on main" % [address, i, a["biome"], a["soil"], e["biome"], e["soil"]])
			return
		for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
			if (e["arrays"] as Array)[slot] != (a["arrays"] as Array)[slot]:
				_fail("%s surface %d: array slot %d differs between worker and main" % [address, i, slot])
				return


func _compare_detail(address: Vector2i, expected: Dictionary, actual: Dictionary) -> void:
	if expected.is_empty() != actual.is_empty():
		_fail("%s: detail empty on worker=%s, main=%s" % [address, actual.is_empty(), expected.is_empty()])
		return
	if expected.is_empty():
		return
	for key in ["positions", "types", "rotations", "scales"]:
		if expected[key] != actual[key]:
			_fail("%s: detail '%s' differs between worker and main" % [address, key])
			return

	# Grouping must be a partition of every prop by its own type.
	var types: PackedByteArray = actual["types"]
	var seen := 0
	var by_type: Dictionary = actual["indices_by_type"]
	for prop_type: int in by_type:
		for index in (by_type[prop_type] as PackedInt32Array):
			if types[index] != prop_type:
				_fail("%s: prop %d grouped under type %d but is %d" % [address, index, prop_type, types[index]])
				return
			seen += 1
	if seen != types.size():
		_fail("%s: grouping holds %d indices for %d props" % [address, seen, types.size()])


func _check_live_streaming(addresses: Array[Vector2i]) -> void:
	print("[3] live streaming around a moving camera")
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)
	var camera: CameraController = load("res://scenes/camera/CameraController.tscn").instantiate()
	camera.name = "CameraController"
	camera.edge_pan_enabled = false
	add_child(camera)

	# Start on the first baked chunk, then move a full chunk-grid span away
	# while its builds are running, then come back. The first framing's
	# unwanted chunks must never be built.
	var home := _chunk_center(addresses[0])
	var away := home + Vector2(TerrainMeshChunkData.CHUNK_SIZE_WU * 6.0, 0.0)
	camera.global_position = away
	camera.set_zoom_level(_ZOOM)

	var mesh := TerrainMeshView.new()
	mesh.name = "TerrainMeshView"
	mesh.camera_path = NodePath("../../CameraController")
	world.add_child(mesh)
	var detail := TerrainDetailView.new()
	detail.name = "TerrainDetailView"
	detail.camera_path = NodePath("../../CameraController")
	world.add_child(detail)

	# Two frames: enough for both views to request and start builds for `away`.
	await get_tree().process_frame
	await get_tree().process_frame
	camera.global_position = home

	var frames := 0
	var worst_frame_ms := 0.0
	var last_tick := Time.get_ticks_usec()
	while frames < _STREAM_TIMEOUT_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst_frame_ms = maxf(worst_frame_ms, float(now - last_tick) / 1000.0)
		last_tick = now
		frames += 1
		if frames > 2 and mesh.is_streaming_idle() and detail.is_streaming_idle():
			break
	if frames >= _STREAM_TIMEOUT_FRAMES:
		_fail("views still streaming after %d frames" % frames)
		return
	print("    idle after %d frames, worst frame %.1f ms (headless; reported, not gated)" % [frames, worst_frame_ms])

	var wanted := _wanted_addresses(camera)
	for view: Node2D in [mesh, detail]:
		var built: Dictionary = {}
		for child in view.get_children():
			if child.is_queued_for_deletion():
				continue
			var parts := String(child.name).split("_")
			built[Vector2i(int(parts[1]), int(parts[2]))] = child
		for address: Vector2i in built:
			if not wanted.has(address):
				_fail("%s holds stale chunk %s from the abandoned framing" % [view.name, address])
		for address: Vector2i in wanted:
			if not built.has(address):
				_fail("%s never built wanted chunk %s" % [view.name, address])

		print("[4] %s: %d chunks built" % [view.name, built.size()])
		for address: Vector2i in built:
			var node: Node = built[address]
			if view == mesh:
				var expected := TerrainMeshView.prepare_chunk(address).size()
				if node.get_child_count() != expected:
					_fail("%s: %d MeshInstance2Ds for %d prepared surfaces" % [address, node.get_child_count(), expected])
			else:
				var prepared := TerrainDetailView.prepare_chunk(address)
				var instances := 0
				for instance: MultiMeshInstance2D in node.get_children():
					instances += instance.multimesh.instance_count
				var expected_props := 0 if prepared.is_empty() else (prepared["positions"] as PackedVector2Array).size()
				if instances != expected_props:
					_fail("%s: %d prop instances for %d scattered props" % [address, instances, expected_props])

	# get_props_at() answers from the finalized scatter: some hex in a built
	# chunk with props must return them.
	var answered := false
	for address: Vector2i in wanted:
		var prepared := TerrainDetailView.prepare_chunk(address)
		if prepared.is_empty():
			continue
		var first: Vector2 = (prepared["positions"] as PackedVector2Array)[0]
		if not detail.get_props_at(HexCoord.world_to_axial(first)).is_empty():
			answered = true
			break
	if not answered:
		_fail("get_props_at() returned nothing for a hex holding a scattered prop")


## Mirrors the views' own wanted-set computation (_sync_wanted_chunks()).
func _wanted_addresses(camera: CameraController) -> Dictionary:
	var world_size := get_viewport().get_visible_rect().size / camera.zoom
	var rect := Rect2(camera.get_screen_center_position() - world_size * 0.5, world_size).grow(TerrainMeshView.LOAD_MARGIN_WU)
	var lo := TerrainMeshChunkData.chunk_address(rect.position)
	var hi := TerrainMeshChunkData.chunk_address(rect.end)
	var wanted: Dictionary = {}
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			wanted[Vector2i(cx, cy)] = true
	return wanted


func _chunk_center(address: Vector2i) -> Vector2:
	return (Vector2(address) + Vector2(0.5, 0.5)) * TerrainMeshChunkData.CHUNK_SIZE_WU


## Real baked chunks with some props in them, so every check has data.
func _find_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir := DirAccess.open(TerrainMeshChunkData.CHUNK_DIR)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for file in files:
		if not file.ends_with(".tmesh"):
			continue
		var parts := file.get_basename().split("_")
		if parts.size() < 3:
			continue
		var address := Vector2i(int(parts[1]), int(parts[2]))
		if TerrainDetailView.prepare_chunk(address).is_empty():
			continue
		out.append(address)
		if out.size() >= _MAX_CHUNKS:
			break
	return out
