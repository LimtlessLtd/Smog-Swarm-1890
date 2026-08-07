class_name MovementStepper
extends RefCounted

## Design doc, user request: replaces the old "hex-stepping" movement
## (`UnitOrderController`/`HordeManager` used to snap an entity's position
## once every `MOVE_INTERVAL_SECONDS` via `HexCoord.entry_local_position()`)
## with genuinely continuous, real-time, world-coordinate movement — an
## entity walks smoothly from wherever it currently is toward the next
## hex's exact center, at a real speed, rather than teleporting. Stateless
## `RefCounted` utility, same shape/role as `HexPathfinder`/`CombatEngine`:
## no NodePath exports, no reference to `UnitManager`/`HordeManager`/any
## runtime Node — a caller passes in plain values (or a `HexCell`/
## `LogisticsNetwork` reference to read, same as `HexPathfinder` already
## does) and mutates its own `UnitInstance`/`Horde` with the result, the
## same "utility computes, manager mutates" split `CombatEngine`/
## `WallManager.damage_segment()` already keep.
##
## Deliberately does NOT know about hexes, `WallManager`, `BuildingManager`,
## or `LocalDetailManager` — a caller (`UnitOrderController`/`HordeManager`)
## already owns the loop that walks a path hex-by-hex (see either file's
## own `_advance_*` doc comment) and re-checks anything caller-specific
## (hordes' wall-blocking) BETWEEN calls to `advance_toward_hex()` below —
## this class only ever advances toward ONE target hex at a time, by
## design, specifically so a multi-hex catch-up burst at high
## `TickManager` speed can't glide straight through an un-breached wall on
## an intermediate hex the caller never got a chance to re-check.
##
## `hex_coord`/`local_position` (the same two fields `UnitInstance`/`Horde`
## already have — no new position fields anywhere) together describe a
## world position (`HexCoord.axial_to_world(hex_coord) + local_position`);
## this class treats `hex_coord` purely as "which hex is local_position
## currently relative to" and never mutates it itself — the caller re-bases
## `local_position` onto the new hex once `arrived` is true.

## World-units/second at the unmodified baseline (no terrain/logistics
## multiplier) — derived, not guessed, to preserve the exact overall pace
## the old hex-stepping model had: the real distance between two adjacent
## hex centers (`HexCoord.HEX_SIZE * sqrt(3)`, pointy-top hex geometry)
## divided by the old `MOVE_INTERVAL_SECONDS` (20.0) rate. Same speed for
## both units and hordes, matching how they already deliberately shared
## that same old constant. A placeholder balancing number like every other
## constant table in this project — trivially retunable, this is about
## motion STYLE (continuous vs. teleporting), not repricing how fast the
## colony's world already felt.
const BASE_MOVE_SPEED: float = HexCoord.HEX_SIZE * 1.7320508075688772 / 20.0  ## sqrt(3) inlined — GDScript const initializers can't call sqrt().

## How far ahead of an entity's current position an obstacle is even worth
## considering — well past ObstacleRadii's largest radius plus a full
## frame's worth of travel at a brisk pace, so a fast-approaching obstacle
## still gets steered around in time rather than noticed too late.
const STEERING_LOOKAHEAD: float = 140.0

## Advances a point currently at `hex_coord`'s own local space
## (`local_position`, an offset from that hex's center) up to
## `available_seconds` of continuous travel toward `target_hex`'s exact
## center, at `speed` world-units/second. Returns
## `{"hex_coord": Vector2i, "local_position": Vector2, "arrived": bool,
## "seconds_used": float}` — `hex_coord`/`local_position` together are
## ALWAYS the entity's new authoritative position, unconditionally safe for
## the caller to overwrite its own two fields with regardless of `arrived`:
## when true they describe `target_hex` (local_position exactly `ZERO`,
## its center); when false they're still the original `hex_coord`, with
## `local_position` advanced partway toward the target. No separate
## re-basing step needed either way — this is the one thing the old
## `HexCoord.entry_local_position()` write-site used to do in a single
## jump, computed continuously now instead.
##
## `obstacles` (Array of `{"position": Vector2, "radius": float}`,
## world-space) only steers the FINAL, partial step within this call's own
## budget — see `steer_around_obstacles()`'s own doc comment for why a
## whole-hex commit (this call reaching `target_hex` outright) skips
## steering entirely: at extreme `TickManager` speeds a single frame can
## cover several hex-widths, and fine steering only matters for the
## last bit of motion a human is actually watching.
static func advance_toward_hex(hex_coord: Vector2i, local_position: Vector2, target_hex: Vector2i, available_seconds: float, speed: float, obstacles: Array[Dictionary], entity_radius: float) -> Dictionary:
	if available_seconds <= 0.0:
		return {"hex_coord": hex_coord, "local_position": local_position, "arrived": false, "seconds_used": 0.0}

	var world_pos := HexCoord.axial_to_world(hex_coord) + local_position
	var target_world := HexCoord.axial_to_world(target_hex)
	var to_target := target_world - world_pos
	var distance := to_target.length()

	if distance <= 0.01:
		return {"hex_coord": target_hex, "local_position": Vector2.ZERO, "arrived": true, "seconds_used": 0.0}

	var safe_speed := maxf(speed, 0.01)  ## Guards the division below — a zero/negative speed multiplier should never happen in practice, but this avoids a hard crash if one ever does.
	var time_to_arrive := distance / safe_speed
	if time_to_arrive <= available_seconds:
		return {"hex_coord": target_hex, "local_position": Vector2.ZERO, "arrived": true, "seconds_used": time_to_arrive}

	var direction := to_target / distance
	if not obstacles.is_empty():
		direction = steer_around_obstacles(world_pos, direction, entity_radius, obstacles)
	var new_world_pos := world_pos + direction * safe_speed * available_seconds
	return {"hex_coord": hex_coord, "local_position": new_world_pos - HexCoord.axial_to_world(hex_coord), "arrived": false, "seconds_used": available_seconds}

## Pure steering-behavior obstacle avoidance (a Reynolds-style "avoidance"
## force, not a search algorithm) — nudges `desired_direction` (already
## unit length) away from any obstacle in `obstacles` whose clearance
## circle (`entity_radius + obstacle radius`) the straight line from `from`
## would clip within `STEERING_LOOKAHEAD`. Cheap enough to run every frame
## for every moving entity (a handful of vector ops per nearby obstacle, no
## grid/graph search), but genuinely NOT guaranteed to escape a dense
## obstacle cluster — props have no minimum-spacing guarantee against each
## other (see `LocalDetailGenerator`'s own doc comment on pure independent
## random placement) — an entity briefly getting stuck or grazing an
## obstacle near cluttered terrain is an accepted edge case of a cheap
## local steering behavior, not a bug to chase down with a full local
## pathfinding search nobody asked for.
static func steer_around_obstacles(from: Vector2, desired_direction: Vector2, entity_radius: float, obstacles: Array[Dictionary]) -> Vector2:
	var avoidance := Vector2.ZERO
	for obstacle in obstacles:
		var to_obstacle: Vector2 = obstacle["position"] - from
		var ahead: float = to_obstacle.dot(desired_direction)
		if ahead <= 0.0 or ahead > STEERING_LOOKAHEAD:
			continue  ## Behind us, or far enough ahead it isn't worth reacting to yet.
		var lateral: Vector2 = to_obstacle - desired_direction * ahead  ## Component of to_obstacle perpendicular to our direction of travel.
		var clearance: float = entity_radius + float(obstacle["radius"])
		var lateral_distance := lateral.length()
		if lateral_distance >= clearance:
			continue  ## Our straight line already clears this obstacle.
		var push := -lateral / lateral_distance if lateral_distance > 0.001 else Vector2(-desired_direction.y, desired_direction.x)  ## Dead-on collision course — pick either perpendicular side; ambiguous is fine, just needs to not be zero.
		avoidance += push * (clearance - lateral_distance)
	if avoidance == Vector2.ZERO:
		return desired_direction
	return (desired_direction + avoidance).normalized()
