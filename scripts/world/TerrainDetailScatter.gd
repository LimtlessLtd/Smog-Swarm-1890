class_name TerrainDetailScatter
extends RefCounted

## Places scatter decoration — trees, bushes, rocks, reeds — inside the REAL
## terrain polygons of one baked chunk.
##
## Replaces LocalDetailGenerator, which scattered uniformly into a disc around
## each hex centre off `HexCell.biome_type`: one biome value per 512-unit
## macro hex, so a wood's trees spread evenly over the whole hex the wood
## happened to fall in rather than over the wood. With the vector mesh drawing
## the real OSM shape underneath, that put the trees visibly beside the forest
## instead of in it. This picks a triangle of the chunk's own triangulation,
## weighted by area, and a point inside it — so a prop lands exactly where its
## biome is drawn, and a dense wood is dense because the wood's polygon is
## what got filled.
##
## It is also the CLAUDE.md §3 rule applied: nothing here reads
## `HexCell.biome_type`, and the granularity is the triangulation's, not the
## hex grid's.
##
## Deterministic per chunk. Seeded from the chunk address, so a chunk streamed
## in, out and back scatters identically and a prop does not jump when the
## camera pans away and returns. Same reasoning LocalDetailGenerator's
## coord-seeded RNG had, one level up.

## Props per one million square world units, by biome. 0 means no scatter at
## all — open water and city streets get nothing.
##
## Read these as a SPACING, which is what actually decides whether ground
## reads as forest or as scattered dots: mean gap between props is
## sqrt(1e6 / density) world units, against a prop drawn
## TerrainDetailView.PROP_DIAMETER (20) across.
##
## The first cut used LocalDetailGenerator's own per-hex numbers converted to
## this unit (its 110 woodland props over a ~681,000-unit hex = ~161 per
## million). Rendered, that is a 79-unit gap between 20-unit trees — four
## tree-widths apart, which is parkland, and it read as confetti sprinkled
## over the map rather than as woods. The old scatter got away with it only
## because it never had to look like anything at range: it existed on a
## handful of settled hexes at a time.
##
## WOODLAND is now set so the gap is about one tree-width, which is a closed
## canopy ("thick forests", user request). The rest are spaced off that.
const _DENSITY_BY_BIOME: Dictionary = {
	GameEnums.BiomeType.WOODLAND: 2200.0,  ## ~21-unit gap: canopy, trees touching.
	GameEnums.BiomeType.HEATHLAND: 700.0,  ## ~38: continuous scrub, ground still visible between clumps.
	GameEnums.BiomeType.WETLAND: 520.0,    ## ~44: reed beds in stands, not a lawn.
	GameEnums.BiomeType.MOORLAND: 260.0,   ## ~62: open moor with occasional cover.
	GameEnums.BiomeType.HIGHLAND: 220.0,   ## ~67: thin, mostly bare rock.
	GameEnums.BiomeType.FARMLAND: 60.0,    ## ~129: tilled ground is cleared ground — what is left is field corners and hedge.
	GameEnums.BiomeType.URBAN: 0.0,
	GameEnums.BiomeType.INDUSTRIAL: 0.0,
	GameEnums.BiomeType.WATERWAY: 0.0,
}

const _SQUARE_UNITS_PER_DENSITY: float = 1_000_000.0

## Refuses to scatter more than this per chunk. Not a normal-play limit — a
## whole 4096-unit chunk of solid woodland is ~37,000 and no real chunk is
## solid woodland — but a density constant edited without doing the
## arithmetic must not be able to strand hundreds of thousands of instances.
const MAX_PROPS_PER_CHUNK: int = 48000

## Every currently-authored prop texture is a real illustrated thing with a
## natural "up" (a tree's canopy over its trunk), so a full 0..TAU spin
## renders half of them upside down — a real player report against the
## per-hex scatter this replaces. Only a rock has no meaningful orientation.
const _FREE_ROTATION_PROP_TYPES: Array[GameEnums.PropType] = [GameEnums.PropType.ROCK]
const _ORIENTED_PROP_JITTER_RAD: float = 0.349066  ## ~20 degrees either way — real trees do not grow perfectly vertical either, but every one still reads as upright.


## Scatter for one chunk. Returns parallel flat arrays rather than
## PropInstance objects: a chunk carries thousands of props and the renderer
## feeds them straight into a MultiMesh, so allocating a Resource each would
## cost more than the drawing does. TerrainDetailView builds PropInstances
## only for the handful of hexes actually asked about.
##
## `positions` are absolute world positions. `types` is one
## GameEnums.PropType per prop, `rotations` and `scales` likewise.
##
## Triangles are picked by AREA, via a running cumulative total and a binary
## search — picking uniformly among triangles instead would crowd props into
## whichever regions happen to be finely triangulated, which is the detailed
## urban ones, i.e. exactly where the density table says to put none.
static func scatter(data: TerrainMeshChunkData, address: Vector2i,
		positions: PackedVector2Array, types: PackedByteArray,
		rotations: PackedFloat32Array, scales: PackedFloat32Array) -> void:
	var cumulative := PackedFloat32Array()
	var tri_biomes: Array[GameEnums.BiomeType] = []
	# Weighted triangles are a SUBSET of the chunk's own (zero-density biomes
	# drop out), so their index is not the chunk's triangle index and the
	# mapping back has to be kept explicitly.
	var tri_indices := PackedInt32Array()
	var total_weight := 0.0

	# One pass: weight each triangle by its own area times its biome's
	# density, so a single draw from the cumulative total picks both the
	# triangle and (implicitly) the right number of props per biome.
	for tri in data.triangle_count():
		var points := data.triangle_points(tri)
		var biome := RealTerrainSampler.biome_from_code(data.triangle_biomes[tri])
		var density: float = _DENSITY_BY_BIOME.get(biome, 0.0)
		if density <= 0.0:
			continue
		var area := absf((points[1] - points[0]).cross(points[2] - points[0])) * 0.5
		if area <= 0.0:
			continue
		total_weight += area * density
		cumulative.append(total_weight)
		tri_biomes.append(biome)
		tri_indices.append(tri)

	if cumulative.is_empty():
		return
	var count := mini(int(total_weight / _SQUARE_UNITS_PER_DENSITY), MAX_PROPS_PER_CHUNK)
	if count <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(address)

	for _i in count:
		var pick := _pick_triangle(cumulative, rng.randf() * total_weight)
		var biome := tri_biomes[pick]
		var prop_type := _prop_type_for_biome(biome, rng)
		positions.append(_point_in_triangle(data, tri_indices[pick], rng))
		types.append(int(prop_type))
		rotations.append(rng.randf_range(0.0, TAU) if _FREE_ROTATION_PROP_TYPES.has(prop_type)
			else rng.randf_range(-_ORIENTED_PROP_JITTER_RAD, _ORIENTED_PROP_JITTER_RAD))
		scales.append(rng.randf_range(0.8, 1.3))


## Index into `cumulative` for a draw of `target`. Binary search, not a linear
## walk: a chunk can carry tens of thousands of weighted triangles and this
## runs once per prop.
static func _pick_triangle(cumulative: PackedFloat32Array, target: float) -> int:
	var low := 0
	var high := cumulative.size() - 1
	while low < high:
		var mid := (low + high) / 2
		if cumulative[mid] < target:
			low = mid + 1
		else:
			high = mid
	return low


## Uniform point inside triangle `tri_index` of the chunk, by the standard
## square-root barycentric warp — a plain (u, v) pair without it clusters
## points toward one corner instead of filling the triangle evenly.
static func _point_in_triangle(data: TerrainMeshChunkData, tri_index: int, rng: RandomNumberGenerator) -> Vector2:
	var points := data.triangle_points(tri_index)
	var u := rng.randf()
	var v := rng.randf()
	var root_u := sqrt(u)
	return points[0] * (1.0 - root_u) + points[1] * (root_u * (1.0 - v)) + points[2] * (root_u * v)


## Order-independent hash of the chunk address — the same chunk always
## scatters the same props regardless of load order.
static func _chunk_seed(address: Vector2i) -> int:
	return address.x * 73856093 ^ address.y * 19349663


static func _prop_type_for_biome(biome: GameEnums.BiomeType, rng: RandomNumberGenerator) -> GameEnums.PropType:
	match biome:
		GameEnums.BiomeType.WETLAND:
			return GameEnums.PropType.REED
		GameEnums.BiomeType.HIGHLAND:
			return GameEnums.PropType.ROCK if rng.randf() < 0.8 else GameEnums.PropType.BUSH
		GameEnums.BiomeType.WOODLAND:
			return GameEnums.PropType.TREE if rng.randf() < 0.9 else GameEnums.PropType.BUSH
		GameEnums.BiomeType.HEATHLAND:
			return GameEnums.PropType.BUSH if rng.randf() < 0.85 else GameEnums.PropType.TREE
		_:
			return GameEnums.PropType.TREE if rng.randf() < 0.5 else GameEnums.PropType.BUSH
