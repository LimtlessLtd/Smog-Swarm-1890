class_name HexCoord
extends RefCounted

## Pointy-top axial hex coordinate math. Pure static utility — no state.
## Reference algorithms: https://www.redblobgames.com/grids/hexagons/
##
## Each hex represents a ~5x5 mile macro-region (see design overview), but
## that scale is a gameplay/world-building fact, not a literal miles-per-unit
## conversion — the pixel radius below (HEX_SIZE) is still a placeholder
## visual scale until real art defines tile dimensions.
##
## Phase 2.5.6 (grilling session — "25 square miles is a big place"):
## increased 8x from the original 64.0 so a hydrated hex's own local space
## (Phase 2.5 Tactical view — props, buildings, and Phase 2.5.4's future
## squads/zombies) has genuine room to spread out and read as spatially
## distinct, and enough room to actually pan across at close zoom instead of
## the whole hex fitting inside one small diorama. Chosen as a straight
## world-space scale multiplier rather than a dual-coordinate-space/
## floating-origin rearchitecture: every system that places or reads a world
## position already goes through this class (axial_to_world/world_to_axial),
## so a single constant change keeps Strategic click/render math, the
## minimap, fog of war and every marker system automatically consistent —
## nothing about them needed to change. CameraController's zoom-related
## constants (min_zoom/max_zoom/tactical_zoom_threshold/zoom_step) and
## Main.tscn's starting camera zoom were all scaled by 1/8 alongside this
## (Camera2D's visible world width is viewport/zoom.x — see
## CameraController's own zoom-direction doc comment — so a bigger world
## needs SMALLER zoom values to keep framing the same fraction of it),
## pan_speed was scaled by 8x^2 = 64x to compensate (see its own doc comment
## on CameraController), and Main.tscn's starting camera *position* was
## scaled by the same 8x as HEX_SIZE itself (position is a world coordinate,
## not a zoom value — axial_to_world scales linearly with HEX_SIZE, so any
## previously-correct position stays correct after a uniform multiply).
## Together these preserve the exact same Strategic-view experience (same
## relative pan speed, same fraction of the map visible at a given zoom
## level) even though the world-space numbers underneath got bigger.
## Verified safe against float precision: the full 40x28 hex map now spans
## roughly 48,000x21,500 world units at its extremes, comfortably under the
## ~100,000 unit range where single-precision float jitter typically starts
## to show. If the map ever grows dramatically larger than that, revisit
## with a real floating-origin camera rebase instead of pushing this
## constant further.
const HEX_SIZE: float = 512.0

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
