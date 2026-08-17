extends SceneTree

## Headless verification that the baked .tmesh chunks decode in-engine and
## agree with what the Python bake reported. Phase 1 of the vector terrain
## epic: proves the wire format round-trips across the language boundary
## before Phase 3 renders any of it.
##
## Run: Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_terrain_mesh.gd

## Summed triangle area may differ from the chunk box by this fraction. Slack
## for float32 accumulation over ~40k triangles only -- the bake snaps every
## vertex to a 1.0-wu grid, so an exact partition sums to the box area with no
## geometric error to absorb.
const COVERAGE_TOLERANCE: float = 0.001

func _init() -> void:
	var dir := DirAccess.open(TerrainMeshChunkData.CHUNK_DIR)
	if dir == null:
		push_error("no chunk dir at %s -- run tools/geo_bake/bake_vector_landcover.py first" % TerrainMeshChunkData.CHUNK_DIR)
		quit(1)
		return

	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".tmesh"):
			names.append(f)
	names.sort()
	print("found %d baked chunks in %s" % [names.size(), TerrainMeshChunkData.CHUNK_DIR])
	if names.is_empty():
		push_error("chunk dir exists but holds no .tmesh files")
		quit(1)
		return

	var total_tris := 0
	var total_verts := 0
	var failures := 0
	var biome_counts := {}
	var min_edge := INF
	var max_edge := 0.0
	var min_coverage := INF

	for name in names:
		var parts := name.trim_suffix(".tmesh").split("_")
		var chunk_x := int(parts[1])
		var chunk_y := int(parts[2])
		var data := TerrainMeshChunkData.load_chunk(chunk_x, chunk_y)
		if data == null:
			push_error("%s failed to decode" % name)
			failures += 1
			continue

		# Every vertex must land inside the chunk the file claims to be, which
		# catches an origin/quantization disagreement between the two sides of
		# the format rather than letting it render as displaced geometry.
		var lo := Vector2(chunk_x, chunk_y) * TerrainMeshChunkData.CHUNK_SIZE_WU
		var hi := lo + Vector2.ONE * TerrainMeshChunkData.CHUNK_SIZE_WU
		var outside := 0
		for v in data.vertices:
			if v.x < lo.x - 1.0 or v.x > hi.x + 1.0 or v.y < lo.y - 1.0 or v.y > hi.y + 1.0:
				outside += 1
		if outside > 0:
			push_error("%s: %d/%d vertices outside the chunk's own bounds" % [name, outside, data.vertices.size()])
			failures += 1

		if data.indices.size() != data.triangle_count() * 3:
			push_error("%s: %d indices for %d triangles" % [name, data.indices.size(), data.triangle_count()])
			failures += 1

		# Degenerate triangles would render as nothing and, once Phase 4
		# displaces vertices, produce zero-area normals. Indexes the packed
		# arrays directly rather than calling triangle_points() — that
		# allocates a PackedVector2Array per triangle, and across ~440k
		# triangles the allocation alone dominated the whole run.
		var degenerate := 0
		var area := 0.0
		var verts := data.vertices
		var idx := data.indices
		var tri_count := data.triangle_count()
		for t in tri_count:
			var base := t * 3
			var a := verts[idx[base]]
			var b := verts[idx[base + 1]]
			var c := verts[idx[base + 2]]
			var ab := b - a
			var ac := c - a
			var cross := ab.cross(ac)
			if absf(cross) <= 0.0:
				degenerate += 1
			area += absf(cross) * 0.5
			var e0 := ab.length()
			var e1 := (c - b).length()
			var e2 := ac.length()
			min_edge = minf(min_edge, minf(e0, minf(e1, e2)))
			max_edge = maxf(max_edge, maxf(e0, maxf(e1, e2)))
			var biome := RealTerrainSampler.biome_from_code(data.triangle_biomes[t])
			biome_counts[biome] = int(biome_counts.get(biome, 0)) + 1
		if degenerate > 0:
			push_error("%s: %d degenerate (zero-area) triangles" % [name, degenerate])
			failures += 1

		# The chunk's triangles must tile its whole box. A hole renders as
		# background showing through and, in Phase 2, as a position with no
		# terrain class at all. Overlap would push this above 100% and is
		# equally wrong: the arrangement is a partition, so triangle areas sum
		# to the box area exactly. Caught a face-area filter that was silently
		# dropping 3.2% of the map, 6.2% in the densest chunk.
		var box_area := TerrainMeshChunkData.CHUNK_SIZE_WU * TerrainMeshChunkData.CHUNK_SIZE_WU
		var coverage := area / box_area
		if absf(coverage - 1.0) > COVERAGE_TOLERANCE:
			push_error("%s: triangles cover %.2f%% of the chunk box, expected 100%%" % [name, coverage * 100.0])
			failures += 1
		min_coverage = minf(min_coverage, coverage)

		print("  %s: %d tris, %d verts, %.2f%% coverage" % [name, tri_count, verts.size(), coverage * 100.0])

		total_tris += data.triangle_count()
		total_verts += data.vertices.size()

		# chunk_address() must agree with the filename the bake chose.
		var mid := lo + Vector2.ONE * (TerrainMeshChunkData.CHUNK_SIZE_WU * 0.5)
		var addr := TerrainMeshChunkData.chunk_address(mid)
		if addr != Vector2i(chunk_x, chunk_y):
			push_error("%s: chunk_address(%s) returned %s" % [name, mid, addr])
			failures += 1

	print("total: %d triangles, %d vertices" % [total_tris, total_verts])
	print("edge length world units: min %.2f max %.2f" % [min_edge, max_edge])
	print("worst chunk coverage: %.3f%%" % [min_coverage * 100.0])
	print("biome distribution:")
	for biome in biome_counts:
		print("  %-12s %7d tris" % [GameEnums.BiomeType.keys()[biome], biome_counts[biome]])

	if failures > 0:
		print("FAILED: %d problems" % failures)
		quit(1)
	else:
		print("PASS")
		quit(0)
