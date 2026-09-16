extends Node

## Splits one TerrainMeshView + TerrainDetailView chunk build into the part
## that now runs on a worker thread and the part still on the main thread,
## and times both over the real baked chunks. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/bench_chunk_build.tscn
##   Godot_v4.7.1-stable_win64_console.exe res://scenes/test/bench_chunk_build.tscn   (windowed: real RenderingServer uploads)
##
## Both views stream the same chunk addresses in the same order, so a chunk
## used to land whole on ONE frame in both at once: BEFORE is everything,
## summed. Since ChunkBuildQueue, only the finalize half does — AFTER is the
## two finalizes, which is still the worst case of both finishing together.
##
##   MESH PREP     TerrainMeshView.prepare_chunk() — load, soil, crossfades, packed arrays
##   MESH FINAL    ArrayMesh + MeshInstance2D + texture per surface
##   DETAIL PREP   TerrainDetailView.prepare_chunk() — load, scatter, grouping
##   DETAIL FINAL  MultiMesh + per-instance transforms per prop type
##
## The two FINAL columns mirror TerrainMeshView._surface_instance() and
## TerrainDetailView._build_multimesh() rather than calling them: both are
## private to their view. Headless, RenderingServer is a dummy and the FINAL
## columns understate the upload; run windowed for that.
##
## Measured 2026-09-07 before the split (12 chunks, detail half only): mean
## 61.7 ms per chunk, worst 359 ms on a cold file read.

const FRAME_BUDGET_MS: float = 16.6
const MAX_CHUNKS: int = 12  ## Enough for a spread of densities without a long run.


func _ready() -> void:
	SubHexSoilQuery.ensure_initialized()
	var addresses := _find_chunks()
	if addresses.is_empty():
		print("SKIP: no baked chunks at %s — run tools/geo_bake/bake_vector_landcover.py first."
			% TerrainMeshChunkData.CHUNK_DIR)
		get_tree().quit(0)
		return

	# Textures load once, on whichever chunk first uses them, before and after
	# the split alike. Loaded up front so that one-off cost is its own line
	# rather than inflating whichever chunk happens to be first.
	var warm_start := Time.get_ticks_usec()
	for prop_type: int in GameEnums.PropType.values():
		PropVisuals.prop_texture(prop_type as GameEnums.PropType)
	var props_ms := _ms_since(warm_start)
	warm_start = Time.get_ticks_usec()
	for biome: int in GameEnums.BiomeType.values():
		for soil: int in GameEnums.SoilFertility.values():
			TerrainVisuals.terrain_texture(biome as GameEnums.BiomeType, soil as GameEnums.SoilFertility)
	print("first-use texture load, once per session: props %.2f ms, terrain %.2f ms" % [props_ms, _ms_since(warm_start)])

	print("=== One chunk build, main thread before vs after (%d real chunks, budget %.1f ms/frame, %s) ===" % [
		addresses.size(), FRAME_BUDGET_MS, DisplayServer.get_name()])
	print("%-8s %6s %5s %10s %10s %11s %12s %9s %9s" % [
		"chunk", "props", "surf", "mesh prep", "mesh final", "detail prep", "detail final", "BEFORE", "AFTER"])

	var sums := {"before": 0.0, "after": 0.0}
	var worst_before := 0.0
	var worst_after := 0.0
	for address in addresses:
		var row := _time_chunk(address)
		var before: float = row["mesh_prep"] + row["mesh_final"] + row["detail_prep"] + row["detail_final"]
		var after: float = row["mesh_final"] + row["detail_final"]
		sums["before"] += before
		sums["after"] += after
		worst_before = maxf(worst_before, before)
		worst_after = maxf(worst_after, after)
		print("%-8s %6d %5d %10.2f %10.2f %11.2f %12.2f %9.2f %9.2f" % [
			"%d_%d" % [address.x, address.y], row["props"], row["surfaces"],
			row["mesh_prep"], row["mesh_final"], row["detail_prep"], row["detail_final"], before, after])

	var n := float(addresses.size())
	print()
	print("main thread per chunk, mean:  before %.2f ms (%.1f frames)  after %.2f ms (%.1f frames)" % [
		sums["before"] / n, sums["before"] / n / FRAME_BUDGET_MS, sums["after"] / n, sums["after"] / n / FRAME_BUDGET_MS])
	print("main thread per chunk, worst: before %.2f ms (%.1f frames)  after %.2f ms (%.1f frames)" % [
		worst_before, worst_before / FRAME_BUDGET_MS, worst_after, worst_after / FRAME_BUDGET_MS])
	get_tree().quit(0)


func _time_chunk(address: Vector2i) -> Dictionary:
	var start := Time.get_ticks_usec()
	var surfaces := TerrainMeshView.prepare_chunk(address)
	var mesh_prep := _ms_since(start)

	start = Time.get_ticks_usec()
	var holder := Node2D.new()
	for surface: Dictionary in surfaces:
		holder.add_child(_mesh_instance(surface))
	var mesh_final := _ms_since(start)
	holder.free()

	start = Time.get_ticks_usec()
	var prepared := TerrainDetailView.prepare_chunk(address)
	var detail_prep := _ms_since(start)

	var props := 0
	start = Time.get_ticks_usec()
	holder = Node2D.new()
	if not prepared.is_empty():
		var positions: PackedVector2Array = prepared["positions"]
		props = positions.size()
		var by_type: Dictionary = prepared["indices_by_type"]
		for prop_type: int in by_type:
			var instance := _multimesh_instance(prop_type, by_type[prop_type], positions,
				prepared["rotations"], prepared["scales"])
			if instance != null:
				holder.add_child(instance)
	var detail_final := _ms_since(start)
	holder.free()

	return {
		"props": props,
		"surfaces": surfaces.size(),
		"mesh_prep": mesh_prep,
		"mesh_final": mesh_final,
		"detail_prep": detail_prep,
		"detail_final": detail_final,
	}


## Mirrors TerrainMeshView._surface_instance().
func _mesh_instance(surface: Dictionary) -> MeshInstance2D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface["arrays"])
	var instance := MeshInstance2D.new()
	instance.mesh = mesh
	var texture := TerrainVisuals.terrain_texture(surface["biome"], surface["soil"])
	if texture != null:
		instance.texture = texture
	else:
		instance.self_modulate = TerrainVisuals.biome_color(surface["biome"], surface["soil"])
	return instance


## Mirrors TerrainDetailView._build_multimesh().
func _multimesh_instance(prop_type: int, indices: PackedInt32Array, positions: PackedVector2Array,
		rotations: PackedFloat32Array, scales: PackedFloat32Array) -> MultiMeshInstance2D:
	var texture := PropVisuals.prop_texture(prop_type as GameEnums.PropType)
	if texture == null:
		return null
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = quad
	multimesh.instance_count = indices.size()
	var art_size := texture.get_size()
	var longest := maxf(art_size.x, art_size.y)
	var unit := Vector2(art_size.x / longest, art_size.y / longest) * TerrainDetailView.PROP_DIAMETER
	for slot in indices.size():
		var i := indices[slot]
		multimesh.set_instance_transform_2d(slot, Transform2D(rotations[i], unit * scales[i], 0.0, positions[i]))
	var instance := MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.texture = texture
	return instance


func _ms_since(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _find_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir := DirAccess.open(TerrainMeshChunkData.CHUNK_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".tmesh"):
			continue
		var parts := file.get_basename().split("_")
		if parts.size() < 3:
			continue
		out.append(Vector2i(int(parts[1]), int(parts[2])))
		if out.size() >= MAX_CHUNKS:
			break
	return out
