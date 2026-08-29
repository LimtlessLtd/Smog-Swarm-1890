extends Node

## Measures ZombieSwarm.step() — the real per-frame cost of the tactical
## layer, as opposed to bench_zombie_scale.gd's bare integration floor.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/bench_zombie_swarm.tscn
##
## bench_zombie_scale.gd answered "what is the fastest a GDScript mover can
## possibly be" (250,000 packed movers at 14.69 ms, using the entire frame).
## That number set ZombieSwarmManager.ENTITY_BUDGET at ~60,000, but it was
## measured on a two-line loop with no steering, no anchor and no crowd
## containment. This one runs the actual step the game runs, so the budget is
## checked against the code rather than against its optimistic bound.
##
## Two costs are separated on purpose:
##   INTEGRATE  every entity, every step — O(count)
##   RETARGET   one slice, every step — O(count / RETARGET_SLICES)
## and a third row moves the anchor between steps, which is the case that
## matters in play: a horde advancing drags its whole crowd, so every
## retargeted zombie takes the "outside spread, head back" branch instead of
## the cheap wander branch.

const FRAME_BUDGET_MS: float = 16.6
const WARM_FRAMES: int = 2
const TIMED_FRAMES: int = 20
const DELTA: float = 1.0 / 60.0

const SIZES: Array[int] = [10_000, 30_000, 60_000, 120_000, 250_000]

## How many crowds the budget is split across in the many-swarms row below.
const GROUP_COUNTS: Array[int] = [30, 90, 270]

## How far the anchor moves per step in the moving-anchor row — a horde at
## MovementStepper.BASE_MOVE_SPEED covers this much in one 60 fps frame.
const ANCHOR_STEP: float = MovementStepper.BASE_MOVE_SPEED / 60.0


func _ready() -> void:
	print("=== ZombieSwarm.step() cost (GDScript, no render) ===")
	print("budget %.1f ms/frame, median of %d timed steps" % [FRAME_BUDGET_MS, TIMED_FRAMES])
	print("ZombieSwarmManager.ENTITY_BUDGET = %d\n" % ZombieSwarmManager.ENTITY_BUDGET)

	_report("stationary anchor (a hex's resident crowd)", false)
	_report("moving anchor (a horde advancing)", true)

	_report_many()

	print("Per-hex spread check — RESIDENT_SPREAD %.0f wu is %.2f of a hex circumradius"
			% [ZombieSwarmManager.RESIDENT_SPREAD, ZombieSwarmManager.RESIDENT_SPREAD / HexCoord.HEX_SIZE])
	get_tree().quit(0)


## The shape that broke the first cut. When each swarm sized its own slicing,
## a budget split across many small crowds sliced not at all and cost 11.11 ms
## against 2.75 ms for the same total as one crowd. The division is global now,
## so these rows should sit alongside the single-crowd rows above rather than
## 4x above them — that is what this row exists to catch if it regresses.
func _report_many() -> void:
	print("the same budget split across many small crowds")
	for group_count in GROUP_COUNTS:
		var per_swarm := ZombieSwarmManager.ENTITY_BUDGET / group_count
		var swarms: Array[ZombieSwarm] = []
		var slices := ZombieSwarm.slices_for(per_swarm * group_count)
		for i in group_count:
			var swarm := ZombieSwarm.new(i * 31)
			swarm.anchor = Vector2(float(i) * 900.0, 0.0)
			swarm.spread = 64.0
			swarm.slices = slices
			swarm.set_count(per_swarm)
			swarms.append(swarm)
		var samples: Array[float] = []
		for f in (WARM_FRAMES + TIMED_FRAMES):
			var t0 := Time.get_ticks_usec()
			for swarm in swarms:
				swarm.step(DELTA)
			var us := Time.get_ticks_usec() - t0
			if f >= WARM_FRAMES:
				samples.append(float(us) / 1000.0)
		var ms := _median(samples)
		print("  %3d swarms x %6d = %d zombies  %8.2f ms/step  %s"
				% [group_count, per_swarm, group_count * per_swarm, ms,
				"ok" if ms <= FRAME_BUDGET_MS else "OVER BUDGET"])
	print("")


func _report(title: String, move_anchor: bool) -> void:
	print(title)
	var last_fit: int = 0
	for n in SIZES:
		var ms := _time(n, move_anchor)
		var fits := ms <= FRAME_BUDGET_MS
		if fits:
			last_fit = n
		print("  %9d zombies  %2d slices  %8.2f ms/step  %s" % [n, _slices_for(n), ms, "ok" if fits else "OVER BUDGET"])
	print("  -> largest measured size inside budget: %d\n" % last_fit)


static func _slices_for(count: int) -> int:
	return ZombieSwarm.slices_for(count)


## Median, not mean: one GC pause must not be what a budget decision is made
## on. Same rule bench_zombie_scale.gd applies.
static func _median(samples: Array[float]) -> float:
	samples.sort()
	return samples[samples.size() / 2]


func _time(count: int, move_anchor: bool) -> float:
	var swarm := ZombieSwarm.new(count)
	swarm.anchor = Vector2.ZERO
	swarm.spread = ZombieSwarmManager.RESIDENT_SPREAD
	swarm.slices = ZombieSwarm.slices_for(count)
	swarm.set_count(count)

	var samples: Array[float] = []
	for f in (WARM_FRAMES + TIMED_FRAMES):
		if move_anchor:
			swarm.anchor += Vector2(ANCHOR_STEP, 0.0)
		var t0 := Time.get_ticks_usec()
		swarm.step(DELTA)
		var us := Time.get_ticks_usec() - t0
		if f >= WARM_FRAMES:
			samples.append(float(us) / 1000.0)
	return _median(samples)
