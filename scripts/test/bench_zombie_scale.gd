extends Node

## Measures what a literal per-zombie simulation actually costs in GDScript,
## before the "every zombie is a real entity" model (design_doc.md 2.1,
## user decision 2026-08-27) is trusted at population scale.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/bench_zombie_scale.tscn
##
## The question is specific. A London macro-hex's capacity is drawn from real
## 1890s population, so it holds order 1e6 zombies. Rendering is bounded by the
## camera and is not what this measures; MOVING them is not bounded by anything
## — a position update is per entity per frame whether or not it is on screen.
## So the number that decides the design is: how many entities can GDScript
## advance in one frame before it misses 16.6 ms?
##
## Three data layouts are timed because the choice between them is worth more
## than an order of magnitude, and the project's existing movers (Horde,
## UnitInstance) use the slowest one:
##   PACKED  - PackedVector2Array position/velocity pair (struct-of-arrays)
##   DICT    - Array[Dictionary], the usual middle ground
##   OBJECT  - Array[Resource] with @export fields, what Horde.gd actually is
##
## No rendering, no pathfinding, no AI: this is the floor. A real zombie needs
## strictly more than this per frame, so whatever N this reports is an
## optimistic upper bound, not a target.

const FRAME_BUDGET_MS: float = 16.6  ## 60 fps.
const WARM_FRAMES: int = 2
const TIMED_FRAMES: int = 10

const PACKED_SIZES: Array[int] = [10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_000_000]
const DICT_SIZES: Array[int] = [10_000, 50_000, 100_000, 250_000, 500_000]
const OBJECT_SIZES: Array[int] = [10_000, 50_000, 100_000, 250_000]

const DELTA: float = 1.0 / 60.0
const BOUND: float = 512.0  ## HexCoord.HEX_SIZE — one macro-hex of world units.


class Mover:
	extends Resource
	@export var position: Vector2 = Vector2.ZERO
	@export var velocity: Vector2 = Vector2.ONE


func _ready() -> void:
	print("=== zombie-scale simulation floor (GDScript, no render, no AI) ===")
	print("budget %.1f ms/frame, %d timed frames per size\n" % [FRAME_BUDGET_MS, TIMED_FRAMES])

	_report("PACKED (PackedVector2Array x2)", PACKED_SIZES, _time_packed)
	_report("DICT   (Array[Dictionary])", DICT_SIZES, _time_dict)
	_report("OBJECT (Array[Resource], = Horde.gd today)", OBJECT_SIZES, _time_object)

	get_tree().quit(0)


func _report(title: String, sizes: Array[int], timer: Callable) -> void:
	print(title)
	var last_fit: int = 0
	for n in sizes:
		var ms: float = timer.call(n)
		var fits: bool = ms <= FRAME_BUDGET_MS
		if fits:
			last_fit = n
		print("  %9d entities  %8.2f ms/frame  %s" % [n, ms, "ok" if fits else "OVER BUDGET"])
	print("  -> largest measured size inside budget: %d\n" % last_fit)


## Median-of-TIMED_FRAMES so one GC pause or scheduler hiccup cannot set the
## number the design decision gets made on.
static func _median(samples: Array[float]) -> float:
	samples.sort()
	return samples[samples.size() / 2]


func _time_packed(n: int) -> float:
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	pos.resize(n)
	vel.resize(n)
	for i in n:
		pos[i] = Vector2(float(i % 512), float(i % 384))
		vel[i] = Vector2(1.0, 0.5)

	var samples: Array[float] = []
	for f in (WARM_FRAMES + TIMED_FRAMES):
		var t0 := Time.get_ticks_usec()
		for i in n:
			var p: Vector2 = pos[i] + vel[i] * DELTA
			if p.x > BOUND:
				p.x -= BOUND
			if p.y > BOUND:
				p.y -= BOUND
			pos[i] = p
		var us := Time.get_ticks_usec() - t0
		if f >= WARM_FRAMES:
			samples.append(float(us) / 1000.0)
	return _median(samples)


func _time_dict(n: int) -> float:
	var movers: Array = []
	movers.resize(n)
	for i in n:
		movers[i] = {"pos": Vector2(float(i % 512), float(i % 384)), "vel": Vector2(1.0, 0.5)}

	var samples: Array[float] = []
	for f in (WARM_FRAMES + TIMED_FRAMES):
		var t0 := Time.get_ticks_usec()
		for m in movers:
			var p: Vector2 = m["pos"] + m["vel"] * DELTA
			if p.x > BOUND:
				p.x -= BOUND
			if p.y > BOUND:
				p.y -= BOUND
			m["pos"] = p
		var us := Time.get_ticks_usec() - t0
		if f >= WARM_FRAMES:
			samples.append(float(us) / 1000.0)
	return _median(samples)


func _time_object(n: int) -> float:
	var movers: Array = []
	movers.resize(n)
	for i in n:
		var m := Mover.new()
		m.position = Vector2(float(i % 512), float(i % 384))
		movers[i] = m

	var samples: Array[float] = []
	for f in (WARM_FRAMES + TIMED_FRAMES):
		var t0 := Time.get_ticks_usec()
		for m in movers:
			var p: Vector2 = m.position + m.velocity * DELTA
			if p.x > BOUND:
				p.x -= BOUND
			if p.y > BOUND:
				p.y -= BOUND
			m.position = p
		var us := Time.get_ticks_usec() - t0
		if f >= WARM_FRAMES:
			samples.append(float(us) / 1000.0)
	return _median(samples)
