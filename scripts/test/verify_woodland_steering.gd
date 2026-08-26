extends SceneTree

## Isolates MovementStepper's obstacle-avoidance math from the rest of the
## movement stack (no UnitOrderController/LocalDetailManager/camera/chunk
## streaming needed -- MovementStepper/HexCoord/ObstacleRadii touch no
## autoload, so this runs as a plain `-s` script) to check a suspicion raised
## by the numbers alone: ENTITY_RADIUS (20) + PROP_RADIUS[TREE] (24) = 44
## required clearance, against TerrainDetailScatter's own WOODLAND density
## comment ("~21-unit gap: canopy, trees touching" between 20-unit-diameter
## trees, i.e. ~41 world units of mean TREE-CENTER spacing) -- the entity's
## clearance requirement is LARGER than the average gap between trees in the
## densest biome in the game. If true, steer_around_obstacles() has nowhere
## clear to route through on average, not just at unlucky spots.
##
## Two passes: PLAIN (steering only, no escape hatch -- isolates the raw
## math) and WITH the real UnitOrderController.STUCK_UNSTICK_SECONDS/
## STUCK_PROGRESS_FRACTION bypass-after-3s-stall logic reproduced faithfully,
## to check whether that escape hatch actually rescues a real playthrough or
## only produces a repeating stuck/bypass/re-stuck cycle.
##
## Run: Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_woodland_steering.gd

const ENTITY_RADIUS: float = 20.0
const TREE_RADIUS: float = 24.0
const WOODLAND_DENSITY_PER_M2: float = 2200.0  ## TerrainDetailScatter._DENSITY_BY_BIOME[WOODLAND], props per 1e6 wu^2.
const LEG_LENGTH: float = HexCoord.HEX_SIZE * 1.7320508075688772  ## Same hex-center-to-center distance BASE_MOVE_SPEED is derived from.
const CORRIDOR_HALF_WIDTH: float = 150.0  ## Trees placed within this perpendicular band of the straight-line path -- generous relative to STEERING_LOOKAHEAD (140).

## Mirrors UnitOrderController's own constants exactly.
const STUCK_UNSTICK_SECONDS: float = 3.0
const STUCK_PROGRESS_FRACTION: float = 0.25

const DT := 1.0 / 60.0
const MAX_FRAMES := 36000  ## 600 real seconds -- 30x the ~20s an unobstructed leg takes.

func _init() -> void:
	var mean_gap := sqrt(1000000.0 / WOODLAND_DENSITY_PER_M2)
	print("mean tree gap (edge-to-edge): %.1f wu, required clearance (entity+tree radius): %.1f wu" % [mean_gap, ENTITY_RADIUS + TREE_RADIUS])

	seed(12345)  ## Deterministic Poisson-ish scatter, reproducible failure if any.
	var obstacles := _scatter_woodland()
	print("scattered %d trees along a %.0f wu corridor (WOODLAND density)" % [obstacles.size(), LEG_LENGTH])

	print("\n--- PASS 1: plain steering, no stuck-bypass escape hatch ---")
	_run(obstacles, false)

	print("\n--- PASS 2: with UnitOrderController's real 3s-stall bypass logic ---")
	_run(obstacles, true)

	print("\n--- PASS 3: candidate fix -- bypass stays on until genuinely clear of any overlapping obstacle, not just one good frame ---")
	_run_sticky_bypass(obstacles)

	quit(0)


func _scatter_woodland() -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = []
	var trees_per_wu2 := WOODLAND_DENSITY_PER_M2 / 1000000.0
	var corridor_area := LEG_LENGTH * CORRIDOR_HALF_WIDTH * 2.0
	var tree_count := int(trees_per_wu2 * corridor_area)
	for i in tree_count:
		var x := randf() * LEG_LENGTH
		var y := (randf() - 0.5) * CORRIDOR_HALF_WIDTH * 2.0
		obstacles.append({"position": Vector2(x, y), "radius": TREE_RADIUS})
	return obstacles


func _run(obstacles: Array[Dictionary], use_bypass: bool) -> void:
	var speed := MovementStepper.BASE_MOVE_SPEED
	var pos := Vector2.ZERO
	var target := Vector2(LEG_LENGTH, 0.0)
	var elapsed := 0.0
	var frame := 0
	var last_dist := pos.distance_to(target)
	var stuck_seconds := 0.0
	var bypass_events := 0
	var stalled_frames := 0

	while frame < MAX_FRAMES:
		var bypass := use_bypass and stuck_seconds >= STUCK_UNSTICK_SECONDS
		if bypass:
			bypass_events += 1
		var direction := (target - pos).normalized()
		if not bypass:
			direction = MovementStepper.steer_around_obstacles(pos, direction, ENTITY_RADIUS, obstacles, 1.0)
		pos += direction * speed * DT
		elapsed += DT
		frame += 1

		var dist := pos.distance_to(target)
		var approached := last_dist - dist
		var expected := speed * DT
		if approached < expected * STUCK_PROGRESS_FRACTION:
			stuck_seconds += DT
		else:
			stuck_seconds = 0.0
		last_dist = dist

		if dist <= 1.0:
			break
		if approached < 0.01:
			stalled_frames += 1
		else:
			stalled_frames = 0
		if stalled_frames >= 1800:  ## 30 real seconds with under 0.01 wu/frame net progress -- generously past a single 3s stuck-timer cycle.
			print("STUCK at frame %d (t=%.1fs): pos=%s dist_to_target=%.1f, bypass_events_so_far=%d" % [frame, elapsed, pos, dist, bypass_events])
			break

	print("final: pos=%s dist_to_target=%.1f frames=%d elapsed=%.1fs bypass_events=%d" % [pos, pos.distance_to(target), frame, elapsed, bypass_events])
	if pos.distance_to(target) <= 1.0:
		print("PASS: crossed the woodland corridor in %.1fs (unobstructed would be ~%.1fs)" % [elapsed, LEG_LENGTH / speed])
	else:
		print("FAIL: did not reach the far side of the corridor")


## `sticky` bypass: once STUCK_UNSTICK_SECONDS of poor progress triggers a
## bypass, stays bypassed every subsequent frame until no obstacle's
## clearance circle (entity_radius + obstacle radius) still overlaps the
## entity's CURRENT position -- not just until one frame shows an
## isolated burst of progress, which is what PASS 2's "reset stuck_seconds
## the instant progress exceeds 25% of expected" does and why it flip-flops
## in and out of steering every ~4s without ever fully clearing the cluster.
func _run_sticky_bypass(obstacles: Array[Dictionary]) -> void:
	var speed := MovementStepper.BASE_MOVE_SPEED
	var pos := Vector2.ZERO
	var target := Vector2(LEG_LENGTH, 0.0)
	var elapsed := 0.0
	var frame := 0
	var last_dist := pos.distance_to(target)
	var stuck_seconds := 0.0
	var bypassing := false
	var bypass_activations := 0
	var stalled_frames := 0

	while frame < MAX_FRAMES:
		if bypassing and not _overlaps_any(pos, obstacles):
			bypassing = false
		if not bypassing and stuck_seconds >= STUCK_UNSTICK_SECONDS:
			bypassing = true
			bypass_activations += 1
		var direction := (target - pos).normalized()
		if not bypassing:
			direction = MovementStepper.steer_around_obstacles(pos, direction, ENTITY_RADIUS, obstacles, 1.0)
		pos += direction * speed * DT
		elapsed += DT
		frame += 1

		var dist := pos.distance_to(target)
		var approached := last_dist - dist
		var expected := speed * DT
		if approached < expected * STUCK_PROGRESS_FRACTION:
			stuck_seconds += DT
		else:
			stuck_seconds = 0.0
		last_dist = dist

		if dist <= 1.0:
			break
		if approached < 0.01:
			stalled_frames += 1
		else:
			stalled_frames = 0
		if stalled_frames >= 1800:
			print("STUCK at frame %d (t=%.1fs): pos=%s dist_to_target=%.1f, bypass_activations_so_far=%d" % [frame, elapsed, pos, dist, bypass_activations])
			break

	print("final: pos=%s dist_to_target=%.1f frames=%d elapsed=%.1fs bypass_activations=%d" % [pos, pos.distance_to(target), frame, elapsed, bypass_activations])
	if pos.distance_to(target) <= 1.0:
		print("PASS: crossed the woodland corridor in %.1fs (unobstructed would be ~%.1fs)" % [elapsed, LEG_LENGTH / speed])
	else:
		print("FAIL: did not reach the far side of the corridor")


func _overlaps_any(pos: Vector2, obstacles: Array[Dictionary]) -> bool:
	for obstacle in obstacles:
		var clearance: float = ENTITY_RADIUS + float(obstacle["radius"])
		if pos.distance_to(obstacle["position"]) < clearance:
			return true
	return false
