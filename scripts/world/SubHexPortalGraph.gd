class_name SubHexPortalGraph
extends RefCounted

## Sub-Hex Mechanical Layer Phase 1c (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — the portal layer of the hierarchical (HPA*-style) pathfinding
## graph. The ABSTRACT per-cluster graph itself already exists: HexGridMap's
## macro-hex adjacency plus HexPathfinder's A* over it IS that top level, one
## node per macro-hex "cluster" exactly as the epic's roadmap describes. What
## was missing is the layer underneath it — real 30m-resolution crossing
## points (portals) along each pair of adjacent hexes' shared boundary, so a
## route chosen at the macro level can later be refined into an honest
## sub-hex-accurate path instead of assuming every hex-to-hex step crosses at
## the two hex centers. Phase 2 (movement) is the first real consumer of that
## refinement; this phase only builds and proves the portal structure itself
## — same "infra with no consumer yet" restraint Phase 1a's SubHexTerrainQuery
## took (read-only, no mutation store, until a phase actually needs one).
##
## Portals are found lazily and cached per unordered hex pair — same
## "sparse, on-demand, cached" convention SubHexTerrainQuery already
## established — NOT precomputed eagerly for the whole 3,876-hex corridor at
## once, which would force every corridor fine-tile PNG (decoded, ~333x333x3
## bytes each, ~1.3GB total uncompressed) resident in memory simultaneously
## for a graph most of which no single playthrough ever routes across.
##
## Portal-finding geometry: a regular hexagon's edge length equals its own
## circumradius (HexCoord.HEX_SIZE), so the boundary shared by two adjacent
## hex centers is the segment perpendicular to the line joining them, centred
## at its midpoint, spanning HEX_SIZE in total — true for any adjacent pair,
## no per-direction corner lookup table needed.
static var _cache: Dictionary = {}  # "<qa>_<ra>_<qb>_<rb>" (canonical order: hex_a's axial coord sorts before hex_b's) -> Array[SubHexPortal]

## Passable-run sample spacing along a shared edge — the same cell size the
## rest of the sub-hex layer addresses at (HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS),
## so a portal never claims finer precision than the mechanical grid itself has.
const _SAMPLE_STEP: float = HexCoord.SUB_HEX_CELL_SIZE_WORLD_UNITS

## Portals along the shared edge between two ADJACENT macro hexes
## (HexCoord.distance(hex_a, hex_b) == 1 — anything else returns an empty
## array, there's no shared edge to sample). `hex_grid_map` supplies the
## macro-level passability fallback for sub-cells outside the baked
## real-data corridor (RealTerrainSampler/SubHexTerrainQuery return {} there
## — see _is_sub_passable() below), same DI-via-parameter convention
## HexPathfinder.find_path() already uses rather than this class holding its
## own reference.
static func find_portals(hex_grid_map: HexGridMap, hex_a: Vector2i, hex_b: Vector2i) -> Array[SubHexPortal]:
	if HexCoord.distance(hex_a, hex_b) != 1:
		return []
	var ordered_a := hex_a
	var ordered_b := hex_b
	if not _is_canonical_first(hex_a, hex_b):
		ordered_a = hex_b
		ordered_b = hex_a
	var key := "%d_%d_%d_%d" % [ordered_a.x, ordered_a.y, ordered_b.x, ordered_b.y]
	if _cache.has(key):
		return _cache[key]
	var portals := _compute_portals(hex_grid_map, ordered_a, ordered_b)
	_cache[key] = portals
	return portals

static func _compute_portals(hex_grid_map: HexGridMap, hex_a: Vector2i, hex_b: Vector2i) -> Array[SubHexPortal]:
	var center_a := HexCoord.axial_to_world(hex_a)
	var center_b := HexCoord.axial_to_world(hex_b)
	var mid := (center_a + center_b) * 0.5
	var to_b := (center_b - center_a).normalized()
	var along_edge := Vector2(-to_b.y, to_b.x)  # Unit vector along the shared edge, perpendicular to the center-to-center line.
	var half_edge := HexCoord.HEX_SIZE * 0.5  # Regular-hexagon edge length == circumradius; see this file's own doc comment.

	var cell_a := hex_grid_map.get_cell(hex_a)
	var cell_b := hex_grid_map.get_cell(hex_b)
	var fallback_passable_a := cell_a == null or cell_a.is_passable()
	var fallback_passable_b := cell_b == null or cell_b.is_passable()

	var portals: Array[SubHexPortal] = []
	var run_positions: Array[Vector2] = []
	var t := -half_edge
	while t <= half_edge:
		var world_pos := mid + along_edge * t
		var passable := _is_sub_passable(hex_a, world_pos, fallback_passable_a) and _is_sub_passable(hex_b, world_pos, fallback_passable_b)
		if passable:
			run_positions.append(world_pos)
		else:
			_flush_run(run_positions, hex_a, hex_b, portals)
			run_positions = []
		t += _SAMPLE_STEP
	_flush_run(run_positions, hex_a, hex_b, portals)
	return portals

static func _flush_run(run_positions: Array[Vector2], hex_a: Vector2i, hex_b: Vector2i, out_portals: Array[SubHexPortal]) -> void:
	if run_positions.is_empty():
		return
	var mid_pos: Vector2 = run_positions[run_positions.size() / 2]
	var sub_a := HexCoord.sub_hex_index_within(hex_a, mid_pos)
	var sub_b := HexCoord.sub_hex_index_within(hex_b, mid_pos)
	out_portals.append(SubHexPortal.new(hex_a, hex_b, sub_a, sub_b, mid_pos))

## Sub-cell passability at `world_pos` resolved against `hex_coord`
## specifically (SubHexTerrainQuery.sample_at_world_within() — locks to THIS
## hex, doesn't re-derive which hex world_pos geometrically belongs to,
## matching how every other sub-hex-boundary caller already has to handle
## SUB_HEX_GRID_SPAN's overhang). Reapplies HexCell.is_passable()'s exact
## MARSH/PEAT_BOG/OCEAN rule at sub-hex granularity when real baked data
## exists for this position; falls back to the macro hex's OWN
## is_passable() (`fallback`) when it doesn't (outside the baked corridor —
## RealTerrainSampler returns {} there, the same "empty result -> fall back
## to flat default" contract HexMapGenerator already established, not a new
## rule invented here).
static func _is_sub_passable(hex_coord: Vector2i, world_pos: Vector2, fallback: bool) -> bool:
	var sample := SubHexTerrainQuery.sample_at_world_within(hex_coord, world_pos)
	if sample.is_empty():
		return fallback
	var terrain_feature: GameEnums.TerrainFeature = sample.get("terrain_feature", GameEnums.TerrainFeature.NONE)
	var biome_type: GameEnums.BiomeType = sample.get("biome_type", GameEnums.BiomeType.MOORLAND)
	return terrain_feature != GameEnums.TerrainFeature.MARSH and terrain_feature != GameEnums.TerrainFeature.PEAT_BOG and biome_type != GameEnums.BiomeType.OCEAN

## Canonical pair ordering for the cache key — arbitrary but consistent, so
## find_portals(a, b) and find_portals(b, a) share one cache entry instead of
## computing (and storing) the same edge twice.
static func _is_canonical_first(hex_a: Vector2i, hex_b: Vector2i) -> bool:
	if hex_a.x != hex_b.x:
		return hex_a.x < hex_b.x
	return hex_a.y <= hex_b.y

## Clears the cache — tests/tooling only, same rationale
## SubHexTerrainQuery.clear_cache() already documents.
static func clear_cache() -> void:
	_cache.clear()
