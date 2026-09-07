extends Node

## Breaks one TerrainDetailView/TerrainMeshView chunk build into its parts and
## times each, over the real baked chunks. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/bench_chunk_build.tscn
##
## Why a chunk build is worth taking apart: both streamed views build
## CHUNKS_BUILT_PER_FRAME = 1 per frame, on the main thread, in _process(). So
## a chunk build does not average out — it lands whole inside one frame, and
## panning across new ground queues one per frame for as long as the pan lasts.
## smoke_screenshot.gd's own comment already puts a dense build at "~90-170 ms",
## which at 60 fps is six to ten frames' worth of budget spent in one.
##
## MAX_PROPS_PER_CHUNK is 48,000, so the parts scale very differently and the
## cheap-looking ones are not obviously cheap at that count. Measured
## separately:
##
##   LOAD      TerrainMeshChunkData.load_chunk() — file read + parse
##   SCATTER   TerrainDetailScatter.scatter() — weighted pick per prop
##   GROUP     bucketing prop indices by type, as TerrainDetailView does it
##   GROUP-B   the same bucketing without the per-iteration allocation
##
## GROUP-B exists because `indices_by_type.get(types[i], [])` allocates a fresh
## empty Array as the default argument on EVERY iteration — GDScript evaluates
## a call's arguments eagerly, so the default is built and thrown away even
## when the key is present. At 48,000 props that is 48,000 discarded
## allocations per chunk. Whether that matters is exactly what this measures;
## it is not obvious either way, which is why it is a row and not a patch.
##
## Reports per chunk and totalled, against a 16.6 ms frame.

const FRAME_BUDGET_MS: float = 16.6
const MAX_CHUNKS: int = 12  ## Enough for a spread of densities without a long run.


func _ready() -> void:
	var addresses := _find_chunks()
	if addresses.is_empty():
		print("SKIP: no baked chunks at %s — run tools/geo_bake/bake_vector_landcover.py first."
			% TerrainMeshChunkData.CHUNK_DIR)
		get_tree().quit(0)
		return

	print("=== One chunk build, by part (%d real chunks, budget %.1f ms/frame) ===" % [
		addresses.size(), FRAME_BUDGET_MS])
	print("%-14s %8s %9s %9s %9s %9s %9s" % [
		"chunk", "props", "load ms", "scatter", "group", "group-B", "total"])

	var totals := {"load": 0.0, "scatter": 0.0, "group": 0.0, "group_b": 0.0, "props": 0}
	var worst := 0.0
	var worst_name := ""
	for address in addresses:
		var row := _time_chunk(address)
		if row.is_empty():
			continue
		var total: float = row["load"] + row["scatter"] + row["group"]
		if total > worst:
			worst = total
			worst_name = "%d_%d" % [address.x, address.y]
		print("%-14s %8d %9.2f %9.2f %9.2f %9.2f %9.2f" % [
			"%d_%d" % [address.x, address.y], row["props"],
			row["load"], row["scatter"], row["group"], row["group_b"], total])
		for key in ["load", "scatter", "group", "group_b", "props"]:
			totals[key] += row[key]

	var n := float(addresses.size())
	print()
	print("mean per chunk: %.0f props, load %.2f ms, scatter %.2f ms, group %.2f ms  (total %.2f ms = %.1f frames)" % [
		float(totals["props"]) / n, totals["load"] / n, totals["scatter"] / n, totals["group"] / n,
		(totals["load"] + totals["scatter"] + totals["group"]) / n,
		(totals["load"] + totals["scatter"] + totals["group"]) / n / FRAME_BUDGET_MS])
	print("worst chunk:    %s at %.2f ms = %.1f frames of budget in one frame" % [
		worst_name, worst, worst / FRAME_BUDGET_MS])
	print("grouping without the per-iteration allocation: %.2f ms -> %.2f ms across all %d chunks (%.0f%%)" % [
		totals["group"], totals["group_b"], addresses.size(),
		100.0 * (totals["group"] - totals["group_b"]) / maxf(totals["group"], 0.001)])
	print()
	print("NOTE: this is the SCRIPT half only. Building the MultiMeshInstance2D nodes")
	print("and handing their buffers to the renderer is not counted here and needs a")
	print("windowed run (scripts/test/profile_tactical.gd) to see.")
	get_tree().quit(0)


func _time_chunk(address: Vector2i) -> Dictionary:
	var load_start := Time.get_ticks_usec()
	var data := TerrainMeshChunkData.load_chunk(address.x, address.y)
	var load_ms := float(Time.get_ticks_usec() - load_start) / 1000.0
	if data == null:
		return {}

	var positions := PackedVector2Array()
	var types := PackedByteArray()
	var rotations := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var scatter_start := Time.get_ticks_usec()
	TerrainDetailScatter.scatter(data, address, positions, types, rotations, scales)
	var scatter_ms := float(Time.get_ticks_usec() - scatter_start) / 1000.0

	# Exactly TerrainDetailView._build_chunk()'s own bucketing loop.
	var group_start := Time.get_ticks_usec()
	var indices_by_type: Dictionary = {}
	for i in types.size():
		var list: Array = indices_by_type.get(types[i], [])
		if list.is_empty():
			indices_by_type[types[i]] = list
		list.append(i)
	var group_ms := float(Time.get_ticks_usec() - group_start) / 1000.0

	# Same result, without allocating a throwaway Array per prop and without
	# boxing each index into a Variant.
	var group_b_start := Time.get_ticks_usec()
	var buckets: Dictionary = {}
	for i in types.size():
		var key := types[i]
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(i)
	var group_b_ms := float(Time.get_ticks_usec() - group_b_start) / 1000.0

	return {
		"props": positions.size(),
		"load": load_ms,
		"scatter": scatter_ms,
		"group": group_ms,
		"group_b": group_b_ms,
	}


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
