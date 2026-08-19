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
## — see SubHexTerrainQuery.is_passable_at()), same DI-via-parameter convention
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

## True if ANY point along the shared edge is crossable — the question
## HexPathfinder.is_boundary_impassable() asks, answered without building the
## portal list.
##
## Separate from find_portals() for cost, measured rather than assumed
## (scripts/test/bench_portal_blocking.gd): find_portals() must sample the
## whole edge because it returns every distinct crossing, which is ~167
## positions at 30 m spacing and measured 2.18 ms per cold edge and ~178
## stranded SubHexTerrainQuery cache entries per edge — 25 s and ~2M entries
## extrapolated across the corridor, paid lazily mid-session as hordes route
## into new ground. "Is there at least one" can stop at the first passable
## sample instead, and almost every edge is passable at its first sample, so
## the common case costs two lookups rather than 334.
##
## Sampled from the MIDDLE outward for the same reason: the centre of a shared
## edge is where an ordinary crossing is, so the early-out fires immediately
## there. A genuinely blocked edge still costs the full sweep — it has to, to
## prove the negative — but those are the rare ones.
##
## Cached as its own boolean per hex pair. It cannot reuse find_portals()'
## cache (that stores a portal Array; a hit here would mean having done the
## expensive work this exists to avoid), and at one bool per edge the whole
## corridor is ~11,600 entries.
static var _crossing_cache: Dictionary = {}  # Same canonical "<qa>_<ra>_<qb>_<rb>" key as _cache -> bool

static func has_any_crossing(hex_grid_map: HexGridMap, hex_a: Vector2i, hex_b: Vector2i) -> bool:
	if HexCoord.distance(hex_a, hex_b) != 1:
		return false
	var ordered_a := hex_a
	var ordered_b := hex_b
	if not _is_canonical_first(hex_a, hex_b):
		ordered_a = hex_b
		ordered_b = hex_a
	var key := "%d_%d_%d_%d" % [ordered_a.x, ordered_a.y, ordered_b.x, ordered_b.y]
	if _crossing_cache.has(key):
		return _crossing_cache[key]
	var result := _compute_has_crossing(hex_grid_map, ordered_a, ordered_b)
	_crossing_cache[key] = result
	return result


static func _compute_has_crossing(hex_grid_map: HexGridMap, hex_a: Vector2i, hex_b: Vector2i) -> bool:
	var cell_a := hex_grid_map.get_cell(hex_a) if hex_grid_map else null
	var cell_b := hex_grid_map.get_cell(hex_b) if hex_grid_map else null
	if _is_mountain_blocked(cell_a) or _is_mountain_blocked(cell_b):
		return false

	var center_a := HexCoord.axial_to_world(hex_a)
	var center_b := HexCoord.axial_to_world(hex_b)
	var mid := (center_a + center_b) * 0.5
	var to_b := (center_b - center_a).normalized()
	var along_edge := Vector2(-to_b.y, to_b.x)
	var half_edge := HexCoord.HEX_SIZE * 0.5
	var fallback_passable_a := cell_a == null or cell_a.is_passable()
	var fallback_passable_b := cell_b == null or cell_b.is_passable()

	# Offset 0 first, then -/+ one step, -/+ two steps, ... out to the edge's
	# own half-length — the same positions _compute_portals() visits, walked
	# from the middle outward so the early-out fires on the first sample for
	# an ordinary open edge.
	var steps := int(half_edge / _SAMPLE_STEP)
	for i in range(steps + 1):
		if _crosses_at(hex_a, hex_b, mid, along_edge, float(i), fallback_passable_a, fallback_passable_b):
			return true
		if i > 0 and _crosses_at(hex_a, hex_b, mid, along_edge, -float(i), fallback_passable_a, fallback_passable_b):
			return true
	return false


## One sample position, `steps` * _SAMPLE_STEP along the edge from its midpoint.
## Split out because the pair of calls above needs identical arguments in two
## places, and inlining it as a loop over a ternary array left `offset`
## untyped — GDScript cannot infer an element type through a conditional
## expression, which fails to parse rather than falling back to Variant.
static func _crosses_at(hex_a: Vector2i, hex_b: Vector2i, mid: Vector2, along_edge: Vector2,
		steps: float, fallback_a: bool, fallback_b: bool) -> bool:
	var world_pos := mid + along_edge * (steps * _SAMPLE_STEP)
	return SubHexTerrainQuery.is_passable_at(hex_a, world_pos, fallback_a) \
			and SubHexTerrainQuery.is_passable_at(hex_b, world_pos, fallback_b)


static func _compute_portals(hex_grid_map: HexGridMap, hex_a: Vector2i, hex_b: Vector2i) -> Array[SubHexPortal]:
	var cell_a := hex_grid_map.get_cell(hex_a) if hex_grid_map else null
	var cell_b := hex_grid_map.get_cell(hex_b) if hex_grid_map else null

	# The MOUNTAIN clause of passability is decided per macro hex here, not
	# per sub-cell, and this is the one place in the sub-hex layer where that
	# is correct rather than a granularity violation (CLAUDE.md §3).
	# MountainPassCarver lowers a blocking ridge hex's HexCell.elevation at
	# generation so a pass exists; that carve is written to hex data and is
	# absent from the baked elevation raster the sub-hex layer samples. Deriving
	# the mountain verdict from the raster per sub-cell would therefore re-seal
	# every carved pass and strand exactly the hexes MountainPassCarver exists
	# to keep reachable. Marsh, peat bog and ocean have no generated exception
	# and stay per-sub-cell below.
	if _is_mountain_blocked(cell_a) or _is_mountain_blocked(cell_b):
		return []

	var center_a := HexCoord.axial_to_world(hex_a)
	var center_b := HexCoord.axial_to_world(hex_b)
	var mid := (center_a + center_b) * 0.5
	var to_b := (center_b - center_a).normalized()
	var along_edge := Vector2(-to_b.y, to_b.x)  # Unit vector along the shared edge, perpendicular to the center-to-center line.
	var half_edge := HexCoord.HEX_SIZE * 0.5  # Regular-hexagon edge length == circumradius; see this file's own doc comment.

	var fallback_passable_a := cell_a == null or cell_a.is_passable()
	var fallback_passable_b := cell_b == null or cell_b.is_passable()

	var portals: Array[SubHexPortal] = []
	var run_positions: Array[Vector2] = []
	var t := -half_edge
	while t <= half_edge:
		var world_pos := mid + along_edge * t
		var passable := SubHexTerrainQuery.is_passable_at(hex_a, world_pos, fallback_passable_a) and SubHexTerrainQuery.is_passable_at(hex_b, world_pos, fallback_passable_b)
		if passable:
			run_positions.append(world_pos)
		else:
			_flush_run(run_positions, hex_a, hex_b, portals)
			run_positions = []
		t += _SAMPLE_STEP
	_flush_run(run_positions, hex_a, hex_b, portals)
	return portals

## A null cell (off-map) is NOT mountain-blocked — it has no elevation to
## judge and is already excluded by the macro graph's own has_cell() check.
static func _is_mountain_blocked(cell: HexCell) -> bool:
	return cell != null and ElevationLevels.is_impassable(cell.height_level())


static func _flush_run(run_positions: Array[Vector2], hex_a: Vector2i, hex_b: Vector2i, out_portals: Array[SubHexPortal]) -> void:
	if run_positions.is_empty():
		return
	var mid_pos: Vector2 = run_positions[run_positions.size() / 2]
	var sub_a := HexCoord.sub_hex_index_within(hex_a, mid_pos)
	var sub_b := HexCoord.sub_hex_index_within(hex_b, mid_pos)
	out_portals.append(SubHexPortal.new(hex_a, hex_b, sub_a, sub_b, mid_pos))

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
	_crossing_cache.clear()

## Local offset (relative to `to_hex`'s own center) a mover should aim for
## when crossing hex-to-hex from `from_hex` into `to_hex` — the real portal
## nearest the edge midpoint (the center-to-center line's own closest point
## to the shared edge, since that line is perpendicular to the edge by
## construction — see this file's own geometry doc comment), i.e. the
## least-detour crossing point when more than one portal exists. Returns
## Vector2.ZERO (the old plain-center behavior) when find_portals() returns
## none for this edge — HexPathfinder's macro graph only sees per-hex
## passability, not per-edge boundary detail, so a hex pair it considers
## traversable can still have a fully-impassable shared boundary (a
## marsh/cliff seam right at the edge); falling back to the center keeps
## movement working exactly as before Phase 2a rather than stalling.
##
## Sub-Hex Mechanical Layer Phase 2a (todo.md,
## [[sub-hex-mechanical-layer-epic]] memory) — the "hierarchical long-range
## routing" consumer Phase 1c built this graph for: UnitOrderController and
## HordeManager both call this per hex-to-hex leg so a multi-hex route
## crosses through the real 30m-resolution choke point instead of every
## hex's plain geometric center.
static func portal_offset_for_step(hex_grid_map: HexGridMap, from_hex: Vector2i, to_hex: Vector2i) -> Vector2:
	var portals := find_portals(hex_grid_map, from_hex, to_hex)
	if portals.is_empty():
		return Vector2.ZERO
	var to_center := HexCoord.axial_to_world(to_hex)
	var mid := (HexCoord.axial_to_world(from_hex) + to_center) * 0.5
	var best: SubHexPortal = portals[0]
	var best_dist := mid.distance_squared_to(best.world_pos)
	for portal in portals:
		var dist := mid.distance_squared_to(portal.world_pos)
		if dist < best_dist:
			best = portal
			best_dist = dist
	return best.world_pos - to_center
