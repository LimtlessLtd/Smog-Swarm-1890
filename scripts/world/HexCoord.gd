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
	var q := (sqrt(3.0) / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / HEX_SIZE
	var r := (2.0 / 3.0 * pos.y) / HEX_SIZE
	return _cube_round_to_axial(Vector3(q, -q - r, r))

static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in NEIGHBOR_DIRECTIONS:
		result.append(coord + dir)
	return result

static func distance(a: Vector2i, b: Vector2i) -> int:
	var ac := _axial_to_cube(a)
	var bc := _axial_to_cube(b)
	return int((absf(ac.x - bc.x) + absf(ac.y - bc.y) + absf(ac.z - bc.z)) / 2.0)

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
