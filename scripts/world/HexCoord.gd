class_name HexCoord
extends RefCounted

## Pointy-top axial hex coordinate math. Pure static utility — no state.
## Reference algorithms: https://www.redblobgames.com/grids/hexagons/
##
## Each hex represents a ~5x5 mile macro-region, but that scale is a
## gameplay/world-building fact, not a literal miles-per-unit conversion —
## the pixel radius below (HEX_SIZE) is a placeholder visual scale until
## real art defines tile dimensions.
##
## HEX_SIZE was increased 8x from the original 64.0 so a hydrated hex's own
## local space (Tactical view — props, buildings, squads/zombies) has room
## to spread out and read as spatially distinct, and room to actually pan
## across at close zoom. Chosen as a straight world-space scale multiplier
## rather than a dual-coordinate-space/floating-origin rearchitecture: every
## system that places or reads a world position already goes through this
## class (axial_to_world/world_to_axial), so a single constant change keeps
## Strategic click/render math, the minimap, fog of war and every marker
## system automatically consistent. CameraController's zoom-related
## constants (min_zoom/max_zoom/tactical_zoom_threshold/zoom_step) and
## Main.tscn's starting camera zoom were all scaled by 1/8 alongside this
## (Camera2D's visible world width is viewport/zoom.x, so a bigger world
## needs SMALLER zoom values to keep framing the same fraction of it),
## pan_speed was scaled by 8x^2 = 64x to compensate, and Main.tscn's
## starting camera *position* was scaled by the same 8x as HEX_SIZE itself
## (position is a world coordinate, not a zoom value — axial_to_world
## scales linearly with HEX_SIZE, so any previously-correct position stays
## correct after a uniform multiply).
##
## Float precision risk, disclosed and still open: the original 40x28 hex
## map (England's Manchester-Midlands-London corridor) spanned roughly
## 48,000x21,500 world units at its extremes, comfortably under the
## ~100,000 unit range where single-precision float jitter typically starts
## to show. The map now spans the whole UK and Ireland; at the current
## scale, MAP_BOUNDS (154x179 hexes, padded ocean margin included — what
## matters for jitter, since the camera can pan into that margin) spans
## roughly 214,600x136,700 world units — past the ~100,000 unit range that
## would call for a real floating-origin camera rebase instead of pushing
## this constant further. NOT done here — a floating-origin rebase is a
## separate architecture change (every system that reads a world position
## would need to rebase against a moving reference point), and its actual
## necessity can't be confirmed without seeing real rendered jitter at the
## map's far extremes. A live screenshot pass confirmed the map
## renders/scrolls correctly at every zoom level tested, including panning
## toward the ocean margin, with no visible jitter — but that was against a
## smaller landmass than the current one, and hasn't been repeated since
## the latest scale correction grew the grid further. See todo.md's own
## note under the map-expansion entry.
const HEX_SIZE: float = 512.0

## Real-world scale conversion (each hex is ~25 sq mi/~5mi across) —
## HEX_SIZE above IS a hex's real circumradius, so this is that ratio
## against the circumradius' real value in meters. Solving a pointy-top
## hex's area formula (area = 3*sqrt(3)/2 * r^2) for r with area=25 sq mi
## gives a real circumradius of ~3.1020161 mi (~4992.21 m, 1609.34 m/mi).
## sqrt(3) can't be called in a GDScript const initializer (same
## constraint MovementStepper.BASE_MOVE_SPEED's own doc comment
## documents), so the derived ratio is hardcoded here with the derivation
## spelled out. Shared here, not re-derived per call site — both
## TacticalHexView.BUILDING_HALF_SIZE (real building footprint) and
## WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS (the 100m-max wall-segment
## spec) need the exact same real-world/world-unit conversion.
const WORLD_UNITS_PER_REAL_METER: float = 0.1025599

## Real-world sampling/rendering footprint shared by RealTerrainSampler.
## sample_grid() and SubHexGroundView's own sub-cell grid — a single source
## of truth so the two can't silently drift (both previously hardcoded
## their own separate "HEX_SIZE * 1.6" literal).
##
## 1.6x HEX_SIZE (819.2) is SMALLER than a pointy-top hex's own bounding
## box at this circumradius (887 wide x 1024 tall — see corner_points()'s
## own vertex layout), so a square sample/render grid at that span
## under-covers a hex's own top/bottom vertices; that gap only looks
## "filled" because each NEIGHBORING hex's own square grid — whose corners
## sit at half_span*sqrt(2) ≈ 579 world units from center, past HEX_SIZE's
## own 512 circumradius — spills over the shared edge into it. Two effects
## masking each other: an under-covering grid on one hand, an overhanging
## one on the other, netting out to "looks about right, but the overhang is
## real and visible at the corners." 2.0x HEX_SIZE is the smallest span
## whose square fully CIRCUMSCRIBES the hex's own bounding box in both
## dimensions, so paired with SubHexGroundView's hex-shaped clip mask (see
## that class's own doc comment), the grid truly covers the whole hex with
## zero gaps, and the clip mask removes whatever the square's own corners
## still poke past the hex's real boundary.
const SUB_HEX_GRID_SPAN: float = HEX_SIZE * 2.0

## Sub-Hex Mechanical Layer (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — the target real-world size of one MECHANICAL sub-hex cell
## (movement/extraction/vision/ZoC/horde-AI granularity, Phase 2 onward),
## deliberately decoupled from SUB_HEX_GRID_SPAN's rendering/sampling
## resolution above (SubHexGroundView's 11x11 render grid, ~93 world units/
## ~909m per cell — fine for a mesh redrawn every frame, nowhere near
## mechanically granular). 30m chosen so play can zoom in on individual
## units/buildings while the simulation still reasons at real street/field-
## boundary scale, not a ~1km blur.
const SUB_HEX_CELL_SIZE_METERS: float = 30.0

## world_units = meters * WORLD_UNITS_PER_REAL_METER (that constant's own
## derivation above) ~= 3.0768 world units. Same "shared here, not
## re-derived per call site" reasoning WORLD_UNITS_PER_REAL_METER itself
## already documents.
const SUB_HEX_CELL_SIZE_WORLD_UNITS: float = SUB_HEX_CELL_SIZE_METERS * WORLD_UNITS_PER_REAL_METER

## Sub-cell grid resolution spanning SUB_HEX_GRID_SPAN (1024.0 world units)
## at SUB_HEX_CELL_SIZE_WORLD_UNITS (~3.0768) per cell: 1024.0 / 3.0768 ~=
## 332.9 -> 333. A literal, not ceili(SUB_HEX_GRID_SPAN /
## SUB_HEX_CELL_SIZE_WORLD_UNITS) — GDScript const initializers can't call
## non-constant-folded math functions (same constraint this file's own
## WORLD_UNITS_PER_REAL_METER doc comment already notes for sqrt()).
## 333x333 = 110,889 addressable sub-cells per macro-hex — see
## world_to_sub_hex()/sub_hex_to_world() below for why this is an
## addressing scheme, not 110,889 live per-hex objects (SubHexTerrainQuery
## answers cells sparsely/on demand, it does not instantiate this grid).
const SUB_HEX_GRID_N: int = 333

## Resolves `pos` to the sub-hex cell it falls within: which macro hex
## (world_to_axial(), unchanged) plus a local (sx, sy) index into that
## hex's own SUB_HEX_GRID_SPAN-sized square, 0..SUB_HEX_GRID_N-1 each axis,
## (0,0) at the square's own top-left corner (hex center minus half the
## span in both axes). Mirrors RealTerrainSampler.sample_grid()'s own span/
## step addressing, just indexable/invertible now instead of only
## iterable. Returns a Dictionary ({"hex_coord": Vector2i, "sub_index":
## Vector2i}) rather than a second Resource type — this is a coordinate
## conversion, not new persistent state (see SubHexTerrainQuery for the
## consumer).
static func world_to_sub_hex(pos: Vector2) -> Dictionary:
	var hex_coord := world_to_axial(pos)
	return {"hex_coord": hex_coord, "sub_index": sub_hex_index_within(hex_coord, pos)}

## Local sub-cell index within a KNOWN `hex_coord`'s own SUB_HEX_GRID_SPAN
## square — does NOT re-derive which hex `pos` geometrically belongs to.
## world_to_sub_hex() above uses world_to_axial() for that, but
## world_to_axial() can disagree with a caller's own already-known
## hex_coord for a position in the square grid's overhanging corner area
## (SUB_HEX_GRID_SPAN necessarily pokes past a hex's true hexagonal
## boundary into whichever neighbor sits there — see that constant's own
## doc comment). A caller iterating a grid explicitly centered on one hex
## (SubHexGroundView's render grid, SubHexTerrainQuery's own
## sample_at_world_within()) needs every sample locked to THAT hex, not
## silently re-resolved to a neighbor near the edges.
static func sub_hex_index_within(hex_coord: Vector2i, pos: Vector2) -> Vector2i:
	var hex_center := axial_to_world(hex_coord)
	var half_span := SUB_HEX_GRID_SPAN * 0.5
	var local := pos - hex_center + Vector2(half_span, half_span)
	var sx := clampi(int(local.x / SUB_HEX_CELL_SIZE_WORLD_UNITS), 0, SUB_HEX_GRID_N - 1)
	var sy := clampi(int(local.y / SUB_HEX_CELL_SIZE_WORLD_UNITS), 0, SUB_HEX_GRID_N - 1)
	return Vector2i(sx, sy)

## Inverse of world_to_sub_hex() — the world-space CENTER of sub-cell
## `sub_index` within `hex_coord`, for feeding back into
## RealTerrainSampler.sample_at() or any other exact-position query.
static func sub_hex_to_world(hex_coord: Vector2i, sub_index: Vector2i) -> Vector2:
	var hex_center := axial_to_world(hex_coord)
	var half_span := SUB_HEX_GRID_SPAN * 0.5
	var origin := hex_center - Vector2(half_span, half_span)
	return origin + Vector2(
		(float(sub_index.x) + 0.5) * SUB_HEX_CELL_SIZE_WORLD_UNITS,
		(float(sub_index.y) + 0.5) * SUB_HEX_CELL_SIZE_WORLD_UNITS
	)

const NEIGHBOR_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func axial_to_world(coord: Vector2i) -> Vector2:
	var q := float(coord.x)
	var r := float(coord.y)
	var x := HEX_SIZE * (sqrt(3.0) * q + sqrt(3.0) / 2.0 * r)
	var y := HEX_SIZE * (3.0 / 2.0 * r)
	return Vector2(x, y)

static func world_to_axial(pos: Vector2) -> Vector2i:
	var frac := world_to_axial_fractional(pos)
	return _cube_round_to_axial(Vector3(frac.x, -frac.x - frac.y, frac.y))

## The SAME formula world_to_axial() rounds to the nearest hex, without the
## rounding — a continuous (q, r) that equals a hex's own integer coord
## exactly at that hex's center and varies smoothly within it. Extracted for
## SubHexSoilQuery (Sub-Hex Mechanical Layer Phase 3), which reruns
## HexMapGenerator's own per-macro-hex soil noise pass (originally sampled
## at the integer cell.coord) at this continuous coordinate instead, for
## real intra-hex variation using the identical noise field/scale.
static func world_to_axial_fractional(pos: Vector2) -> Vector2:
	var q := (sqrt(3.0) / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / HEX_SIZE
	var r := (2.0 / 3.0 * pos.y) / HEX_SIZE
	return Vector2(q, r)

static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in NEIGHBOR_DIRECTIONS:
		result.append(coord + dir)
	return result

static func distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _axial_to_cube(a)
	var bc := _axial_to_cube(b)
	return int((absf(ac.x - bc.x) + absf(ac.y - bc.y) + absf(ac.z - bc.z)) / 2.0)

## Same cube-distance metric as distance() above, but `from_pos` is a
## continuous world position instead of a hex already snapped to one — the
## "without the rounding" companion to world_to_axial_fractional() (that
## method's own doc comment), extended from raw coordinates to distance.
## Equals float(distance(world_to_axial(from_pos), to_hex)) exactly whenever
## from_pos sits at from_pos's own hex's precise center (the fractional
## coordinate then equals the integer one exactly), and varies smoothly for
## any other from_pos.
##
## fractional_hex_distance(p, own_hex) for a `p` strictly inside own_hex's
## true geometric boundary is bounded by [0, 2/3) — 2/3 only at the hex's
## own vertices (each shared 3 ways with its neighbors, equidistant from all
## three in this metric), NOT approaching 1 as a naive "world distance /
## hex size" intuition might suggest. Since this is a genuine metric (a
## scaled L1 norm on cube coordinates), the triangle inequality means an
## in-hex offset can shrink this metric's distance to any OTHER hex by at
## most that same 2/3 — a source confined to its own hex can never end up
## closer than (integer hex-distance - 2/3) to anything, so it can shift
## which boundary-ring hexes it reaches but never reach past its own
## naive-radius disk. Sub-Hex Mechanical Layer Phase 4 (todo.md,
## [[sub-hex-mechanical-layer-epic]] memory) — lets FogOfWarManager size a
## vision source's true reach by its exact sub-hex local_position instead of
## just which macro hex it occupies, an eccentric-vision-cone effect bounded
## exactly as described above (see that class's own doc comment).
static func fractional_hex_distance(from_pos: Vector2, to_hex: Vector2i) -> float:
	var frac := world_to_axial_fractional(from_pos)
	var from_cube := Vector3(frac.x, -frac.x - frac.y, frac.y)
	var to_cube := _axial_to_cube(to_hex)
	return (absf(from_cube.x - to_cube.x) + absf(from_cube.y - to_cube.y) + absf(from_cube.z - to_cube.z)) / 2.0

## Ring of hexes exactly `radius` steps from `center` (radius 0 == just the center).
static func hex_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	if radius <= 0:
		results.append(center)
		return results
	var coord := center + NEIGHBOR_DIRECTIONS[4] * radius
	for i in range(6):
		for _step in range(radius):
			results.append(coord)
			coord += NEIGHBOR_DIRECTIONS[i]
	return results

## Filled disk of hexes from `center` out to `radius` inclusive.
static func hex_disk(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for r in range(radius + 1):
		results.append_array(hex_ring(center, r))
	return results

## The sub-hex-accurate generalization of hex_disk(source_hex, radius): every
## hex within `radius` of a source sitting at `source_local_position` inside
## `source_hex`, instead of every source in a hex producing an identical disk
## regardless of where in the hex it actually sits. `source_hex` is always
## included first, unconditionally, regardless of radius or offset —
## hex_disk(coord, 0) never excluded its own center, and a `radius == 0`
## source's own fractional_hex_distance() to its own hex is nonzero (see that
## method's own doc comment), so it would otherwise fail its own "<= radius"
## test purely from being off-center. Candidates beyond that are gathered
## from a radius-widened-by-one hex_disk() as a defensive margin — proven in
## fractional_hex_distance()'s own doc comment that a source confined to its
## own hex's true boundary can never actually reach past the naive radius-N
## disk, but this tolerates a momentarily-larger offset for callers (a
## moving unit) whose local_position updates continuously between discrete
## recompute triggers, at no extra cost.
##
## Sub-Hex Mechanical Layer Phase 5a (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory) — extracted here after FogOfWarManager (Phase 4) and
## LogisticsNetwork (Phase 5a) both needed the identical "hex aura from a
## sub-hex-positioned source" membership test; NoiseManager (Phase 5b) reuses
## it too. One shared implementation instead of three copies of the same
## filtering loop.
static func sub_hex_disk(source_hex: Vector2i, source_local_position: Vector2, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [source_hex]
	if radius <= 0:
		return result
	var source_world_pos := axial_to_world(source_hex) + source_local_position
	for coord in hex_disk(source_hex, radius + 1):
		if coord == source_hex:
			continue
		if fractional_hex_distance(source_world_pos, coord) <= float(radius):
			result.append(coord)
	return result

## Straight hex line from `a` to `b` inclusive, used to lay out rivers, canals
## and mountain chains from a couple of hand-placed endpoints.
static func hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var results: Array[Vector2i] = []
	if n == 0:
		results.append(a)
		return results
	var ac := _axial_to_cube(a)
	var bc := _axial_to_cube(b)
	for i in range(n + 1):
		var t := float(i) / float(n)
		results.append(_cube_round_to_axial(ac.lerp(bc, t)))
	return results

## The six corner points of a hex centered at `center`, for drawing a Polygon2D/Line2D.
static func corner_points(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle_rad := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(HEX_SIZE * cos(angle_rad), HEX_SIZE * sin(angle_rad)))
	return points

static func _axial_to_cube(coord: Vector2i) -> Vector3:
	var x := float(coord.x)
	var z := float(coord.y)
	return Vector3(x, -x - z, z)

static func _cube_round_to_axial(cube: Vector3) -> Vector2i:
	var rx := roundf(cube.x)
	var ry := roundf(cube.y)
	var rz := roundf(cube.z)
	var x_diff := absf(rx - cube.x)
	var y_diff := absf(ry - cube.y)
	var z_diff := absf(rz - cube.z)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))
