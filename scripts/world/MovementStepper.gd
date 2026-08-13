class_name MovementStepper
extends RefCounted

## Continuous, real-time, world-coordinate movement — an entity walks
## smoothly from wherever it currently is toward the next hex's exact
## center, at a real speed, rather than teleporting between hex centers.
## Stateless RefCounted utility, same shape/role as HexPathfinder/
## CombatEngine: no NodePath exports, no reference to UnitManager/
## HordeManager/any runtime Node — a caller passes in plain values (or a
## HexCell/LogisticsNetwork reference to read, same as HexPathfinder does)
## and mutates its own UnitInstance/Horde with the result, the same
## "utility computes, manager mutates" split CombatEngine/
## WallManager.damage_segment() keep.
##
## Doesn't know about hexes, WallManager, BuildingManager, or
## LocalDetailManager — a caller (UnitOrderController/HordeManager) already
## owns the loop that walks a path hex-by-hex (see either file's own
## _advance_* doc comment) and re-checks anything caller-specific (hordes'
## wall-blocking) BETWEEN calls to advance_toward_hex() below — this class
## only ever advances toward ONE target hex at a time, by design,
## specifically so a multi-hex catch-up burst at high TickManager speed
## can't glide straight through an un-breached wall on an intermediate hex
## the caller never got a chance to re-check.
##
## hex_coord/local_position (the same two fields UnitInstance/Horde already
## have — no new position fields anywhere) together describe a world
## position (HexCoord.axial_to_world(hex_coord) + local_position); this
## class treats hex_coord purely as "which hex is local_position currently
## relative to" and never mutates it itself — the caller re-bases
## local_position onto the new hex once `arrived` is true.

## World-units/second at the unmodified baseline (no terrain/logistics
## multiplier) — derived, not guessed, to preserve the exact overall pace
## the old hex-stepping model had: the real distance between two adjacent
## hex centers (HexCoord.HEX_SIZE * sqrt(3), pointy-top hex geometry)
## divided by the old MOVE_INTERVAL_SECONDS (20.0) rate. Same speed for
## both units and hordes, matching how they already shared that same old
## constant. A placeholder balancing number — trivially retunable, this is
## about motion STYLE (continuous vs. teleporting), not repricing how fast
## the colony's world already felt.
const BASE_MOVE_SPEED: float = HexCoord.HEX_SIZE * 1.7320508075688772 / 20.0  ## sqrt(3) inlined — GDScript const initializers can't call sqrt().

## How far ahead of an entity's current position an obstacle is even worth
## considering — well past ObstacleRadii's largest radius plus a full
## frame's worth of travel at a brisk pace, so a fast-approaching obstacle
## still gets steered around in time rather than noticed too late.
const STEERING_LOOKAHEAD: float = 140.0

## Advances a point currently at `hex_coord`'s own local space
## (local_position, an offset from that hex's center) up to
## `available_seconds` of continuous travel toward `target_hex`'s center
## (or `target_local_offset` away from it), at `speed` world-units/second.
## Returns {"hex_coord": Vector2i, "local_position": Vector2, "arrived":
## bool, "seconds_used": float} — hex_coord/local_position together are
## ALWAYS the entity's new authoritative position, unconditionally safe for
## the caller to overwrite its own two fields with regardless of `arrived`:
## when true they describe target_hex (local_position exactly
## target_local_offset, ZERO — its plain center — unless the caller asked
## for a specific point within it); when false they're still the original
## hex_coord, with local_position advanced partway toward the target. No
## separate re-basing step needed either way.
##
## `obstacles` (Array of {"position": Vector2, "radius": float},
## world-space) only steers the FINAL, partial step within this call's own
## budget — see steer_around_obstacles()'s own doc comment for why a
## whole-hex commit (this call reaching target_hex outright) skips
## steering entirely: at extreme TickManager speeds a single frame can
## cover several hex-widths, and fine steering only matters for the last
## bit of motion a human is actually watching.
##
## `wobble_seed` — a per-entity constant (caller passes each Horde/
## UnitInstance's own .id, cast to float) that gives each entity a
## distinct, STABLE wobble pattern rather than every entity on the map
## sharing one identical wave. See _wobbled_direction()'s own doc comment
## for why this is safe against the wall-crossing invariant this class's
## own header doc comment describes.
##
## `target_local_offset` — an offset from `target_hex`'s own center, ZERO
## by default (every existing caller, and every INTERMEDIATE hex of a
## multi-hex path, still means exactly "walk to this hex's plain center").
## A caller advancing toward the FINAL hex of a player-issued move/patrol
## order can pass the real clicked offset instead, so the unit's true
## destination is the exact point clicked, not a hex-snapped
## approximation — pathfinding between hexes is unaffected either way,
## this only changes where the LAST leg's own arrival point is.
static func advance_toward_hex(hex_coord: Vector2i, local_position: Vector2, target_hex: Vector2i, available_seconds: float, speed: float, obstacles: Array[Dictionary], entity_radius: float, wobble_seed: float = 0.0, target_local_offset: Vector2 = Vector2.ZERO) -> Dictionary:
	if available_seconds <= 0.0:
		return {"hex_coord": hex_coord, "local_position": local_position, "arrived": false, "seconds_used": 0.0}

	var world_pos := HexCoord.axial_to_world(hex_coord) + local_position
	var target_world := HexCoord.axial_to_world(target_hex) + target_local_offset
	var to_target := target_world - world_pos
	var distance := to_target.length()

	if distance <= 0.01:
		return {"hex_coord": target_hex, "local_position": target_local_offset, "arrived": true, "seconds_used": 0.0}

	var safe_speed := maxf(speed, 0.01)  ## Guards the division below — a zero/negative speed multiplier should never happen in practice, but this avoids a hard crash if one ever does.
	var time_to_arrive := distance / safe_speed
	# A whole-leg commit (this call reaches target_hex outright, e.g. a
	# multi-hex TickManager catch-up burst) ALWAYS beelines exactly to the
	# real target — no wobble here, by design (see _wobbled_direction()'s
	# own doc comment): only the bounded partial-step branch below ever
	# wobbles, and it's re-evaluated fresh from the entity's real position
	# every single call, same re-check cadence the wall-crossing safety
	# property this class's header doc comment relies on.
	if time_to_arrive <= available_seconds:
		return {"hex_coord": target_hex, "local_position": target_local_offset, "arrived": true, "seconds_used": time_to_arrive}

	var direction := to_target / distance
	direction = _wobbled_direction(direction, world_pos, wobble_seed)
	if not obstacles.is_empty():
		direction = steer_around_obstacles(world_pos, direction, entity_radius, obstacles)
	var new_world_pos := world_pos + direction * safe_speed * available_seconds
	return {"hex_coord": hex_coord, "local_position": new_world_pos - HexCoord.axial_to_world(hex_coord), "arrived": false, "seconds_used": available_seconds}

## How far a wobbled direction is allowed to swing from the true, direct
## line to the target — an oscillating perpendicular deflection (a smooth
## function of the entity's own CURRENT WORLD POSITION, so it naturally
## advances as the entity actually moves — stateless, no per-entity memory
## needed the way a phase accumulator would) rather than a random walk: net
## progress toward the target every call is guaranteed (the deflection
## rotates the direction vector, it never reverses it), it's just no
## longer a ruler-straight line — the "traveling in random directions from
## seemingly random stimuli" look real animals have rather than a robot's.
## `wobble_seed` offsets each entity's own phase so a whole horde doesn't
## all swing the same way in lockstep.
##
## Stays safe against the "a horde's own per-edge peek... can't glide
## through an un-breached wall" invariant (see this class's own header doc
## comment and HordeManager._advance_horde()'s) because wobble ONLY ever
## applies to the bounded PARTIAL-step branch above — a step whose own
## distance-this-call is capped at speed * available_seconds, already
## short by construction (a whole-leg commit takes the separate no-wobble
## branch instead) — and every caller re-runs its own wall-crossing check
## from the entity's real, current position before each and every call
## into this function, wobbled position included. A small bounded per-call
## swing changes WHERE within that already-short step the entity ends up,
## not whether the next call's fresh check still runs.
##
## ~13 degrees either way. Empirically tuned: a temporary self-test walking
## one full hex-to-hex leg (~887 world units) measured the actual resulting
## max perpendicular deviation from the direct line at this value —
## comfortably visible (multiple wall-piece lengths,
## WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS's own ~10.26 units) without
## reading as an exaggerated snake-like weave; an earlier pass at 0.45 rad
## (~26 degrees) produced a ~65-unit swing, over 7% of the whole leg's own
## length — too much for organic wander.
const _WOBBLE_MAX_ANGLE_RAD: float = 0.22
const _WOBBLE_FREQUENCY: float = 0.015  ## Radians per world unit of position — tuned so the wave completes a full cycle roughly every ~420 world units (well under one hex width), reading as continuous drift rather than a slow, obviously-periodic sway.
static func _wobbled_direction(direction: Vector2, world_pos: Vector2, wobble_seed: float) -> Vector2:
	var phase := (world_pos.x + world_pos.y) * _WOBBLE_FREQUENCY + wobble_seed
	var wobble_angle := sin(phase) * _WOBBLE_MAX_ANGLE_RAD
	return direction.rotated(wobble_angle)

## Pure steering-behavior obstacle avoidance (a Reynolds-style "avoidance"
## force, not a search algorithm) — nudges `desired_direction` (already
## unit length) away from any obstacle in `obstacles` whose clearance
## circle (entity_radius + obstacle radius) the straight line from `from`
## would clip within STEERING_LOOKAHEAD. Cheap enough to run every frame
## for every moving entity (a handful of vector ops per nearby obstacle, no
## grid/graph search), but NOT guaranteed to escape a dense obstacle
## cluster — props have no minimum-spacing guarantee against each other
## (see LocalDetailGenerator's own doc comment on pure independent random
## placement) — an entity briefly getting stuck or grazing an obstacle near
## cluttered terrain is an accepted edge case of a cheap local steering
## behavior, not a bug to chase down with a full local pathfinding search.
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
