class_name ZombieSwarm
extends RefCounted

## One crowd of individual zombies, held in packed arrays — design_doc.md
## §2.1's tactical layer, decision D14. Never a Resource per zombie: the
## benchmark (scripts/test/bench_zombie_scale.gd, table reproduced in
## design_doc.md §2.1) caps Array[Resource] at 50,000 movers and packed
## arrays at 250,000, and only the second number leaves room for anything
## else in the frame.
##
## A swarm is (one hex, one source, one art variant). ZombieSwarmManager
## creates LANE_COUNT of these per source so a crowd is not uniformly the same
## zombie sprite; every swarm in a group shares an anchor and a facing, and
## differs only in which texture the renderer hands its MultiMesh.
##
## **The step is sliced, and the slicing is the LOD.** Every measurement below
## is scripts/test/bench_zombie_swarm.gd at 60,000 zombies:
##
## | step | ms |
## | :--- | ---: |
## | first cut: whole crowd, `_retarget()` as its own function | 10.84 |
## | same, with the retarget inlined | 5.68 |
## | positions in PackedVector2Array instead of the MultiMesh buffer | 2.48 |
## | plus rebuilding the whole MultiMesh buffer each step | 5.57 |
## | sliced per swarm: move, publish and re-steer 1/N per step | 2.75 |
## | ...same 60,000 split across 30 crowds, so nothing sliced | 11.11 |
## | **sliced globally, one division for every crowd in the frame** | **2.79** |
##
## Two of those are worth stating plainly because neither is obvious. A
## GDScript function call per zombie cost 5 ms of the original 10.84 — half
## the step was call overhead, not movement. And integrating positions
## directly inside the 8-float MultiMesh buffer (2 float reads, 2 float
## writes, index arithmetic) is 2.5x slower than `PackedVector2Array[i] +=
## velocity * dt`, which is one VM operation on one 8-byte value. So position
## is the simulation's own array, and the MultiMesh buffer is a mirror written
## only for the slice that actually moved.
##
## Slicing is per swarm and sized by SLICE_TARGET_ENTITIES, so a 300-strong
## horde still moves every frame and looks smooth, while a city hex's 40,000
## residents move in MAX_SLICES passes. That is what "live-hex LOD" means
## here: the cost per crowd is bounded, not the crowd.
##
## The buffer layout is a Godot contract this project cannot check in the
## gate: under --headless the dummy rendering server backs no MultiMesh
## storage at all — MultiMesh.buffer reads back empty and
## set_instance_transform_2d() does nothing — so a headless round-trip proves
## nothing either way. scripts/test/verify_tactical_zombies.gd checks that
## this class writes what it says it writes; the layout itself is confirmed by
## looking at a windowed render (CLAUDE.md §0.1).

const LANE_COUNT: int = 3  ## Parallel swarms per source, one art variant each. Must equal ZombieVisuals.VARIANT_COUNT; the renderer asserts that rather than this data class importing a visuals constant.

## MultiMesh.TRANSFORM_2D buffer layout: 8 floats per instance, a 2x4 matrix
## whose third column is unused padding.
##   [0]=basis.x.x [1]=basis.y.x [2]=0 [3]=origin.x
##   [4]=basis.x.y [5]=basis.y.y [6]=0 [7]=origin.y
const TRANSFORM_FLOATS: int = 8
const ORIGIN_X_INDEX: int = 3
const ORIGIN_Y_INDEX: int = 7

## Roughly how many zombies one step should move. The division is decided
## GLOBALLY, from the whole budget rather than from one crowd's own size —
## see slices_for(). Sizing it per swarm was the first cut and was wrong by
## 4x: 60,000 zombies as one crowd sliced to 2.75 ms, and the same 60,000
## split across 30 crowds of 2,000 sliced not at all and cost 11.11 ms, which
## is two thirds of the frame. The frame does not care how the budget is
## divided; it cares how many zombies moved.
const SLICE_TARGET_ENTITIES: int = 4000

## Ceiling on the division, which is a ceiling on how stale a rendered
## position may be: at MAX_SLICES a zombie updates at 15 Hz and jumps
## MILL_SPEED / 15 ≈ 0.74 world units per update — under a metre of real
## ground, invisible at every zoom the game allows.
const MAX_SLICES: int = 4

## Milling is bounded in real seconds regardless of game speed. TickManager
## drives speed through Engine.time_scale, so _process delta at 1000x is
## enormous; without this clamp a crowd would cross its own spread in one
## frame and read as static noise. The aggregate that actually matters —
## Horde.local_position — is still fully time-scaled by MovementStepper, so
## hordes cross the map at speed while their individuals shamble.
const MAX_STEP_SECONDS: float = 1.0 / 30.0

## A quarter of the speed a horde crosses a hex at (MovementStepper.BASE_MOVE_SPEED
## is one hex per 20 s). Slow enough to read as shambling at HIGH tactical zoom,
## fast enough that a crowd is visibly alive.
const MILL_SPEED: float = MovementStepper.BASE_MOVE_SPEED * 0.25

## What a zombie that has fallen outside `spread` moves at while catching up.
## It has to EXCEED the fastest a horde can travel or a crowd can never follow
## its own anchor — HordeManager.NIGHT_MOVE_SPEED_MULTIPLIER puts that at 1.5x
## BASE_MOVE_SPEED, so milling speed (0.25x) would have left every crowd
## trailing across the map. Caught by verify_tactical_zombies.gd's
## follow-the-anchor check while it was still failing.
const CHASE_SPEED: float = MovementStepper.BASE_MOVE_SPEED * 2.0

## Beyond this many multiples of `spread` a zombie is not chasing, it is lost:
## re-place it around the anchor instead. Three things cause that and none is a
## chase worth animating — a game speed high enough that one clamped step of
## crowd movement covers less ground than the horde crossed, a load, and a
## reallocation that moved a group. Snapping is the visible cost of
## MAX_STEP_SECONDS existing, and it only ever fires on a crowd whose aggregate
## has effectively teleported.
const SNAP_SPREAD_MULTIPLE: float = 6.0

## Per-zombie speed spread, same range Horde.individual_speed_variance() uses
## for the aggregate — a crowd whose members all move at one speed reads as a
## rigid formation. Computed once at spawn into _speed as a MULTIPLIER (not a
## speed), because the step loop picks between MILL_SPEED and CHASE_SPEED and a
## hash per zombie per step is exactly the kind of work the measurements above
## rule out.
const MIN_SPEED_VARIANCE: float = 0.85
const MAX_SPEED_VARIANCE: float = 1.2

## Wander directions come from a fixed table rather than an RNG: one
## RandomNumberGenerator.randf() per zombie is an engine call, and the table
## makes the whole simulation deterministic for the same seed and step
## sequence, which is what lets verify_tactical_zombies.gd assert on positions
## at all. Power of two so the index is a mask, not a modulo.
const WANDER_DIR_COUNT: int = 64

## A zombie keeps the same wander direction for this many of its own updates
## before drawing the next one. Without it a crowd re-picks a direction every
## time it is stepped and vibrates in place instead of shambling; with it, a
## direction holds for about half a second.
const WANDER_HOLD_STEPS: int = 8

## Odd multiplier, so successive entities land far apart in the wander table
## instead of marching through it in step.
const _WANDER_STRIDE: int = 7

## Mixing constants for _unit_hash(). Knuth's golden-ratio multiplier alone is
## an arithmetic progression across consecutive indices, which is exactly what
## a crowd's indices are — the avalanche steps below break that up. See
## _unit_hash() for what a weak hash looked like on screen.
const _HASH_MULTIPLIER: int = 2654435761
const _HASH_MIX_A: int = 2246822519
const _HASH_MIX_B: int = 3266489917
const _HASH_RANGE: int = 65536

static var _wander_dirs: PackedVector2Array = PackedVector2Array()

## How many steps this swarm takes to visit every zombie once. Written by
## ZombieSwarmManager from slices_for(the whole live population) — a swarm does
## not know how much company it has in the frame. Plain public var, same as
## `anchor` and `spread`; step() clamps it rather than a setter, so a manager
## that never writes it still behaves (every zombie, every step).
var slices: int = 1

## Which of LANE_COUNT this swarm is. The renderer maps it to a
## ZombieVisuals variant, which is the only reason lanes exist — a crowd
## drawn entirely from one sprite reads as a formation, not a mob.
var lane: int = 0

## The hex this crowd belongs to. Carried here rather than looked up so the
## renderer can apply Fog of War without a second dependency on the manager's
## internal keying.
var hex_coord: Vector2i = Vector2i.ZERO

## World position the crowd mills around. Written by the manager every frame
## from whatever owns this swarm's count — a Horde's own continuous position,
## or the hex center for a hex's resident population.
var anchor: Vector2 = Vector2.ZERO

## How far a zombie may drift from `anchor` before it is steered back.
var spread: float = 64.0

## Whole-swarm facing, matching the existing renderer's "a whole Horde shares
## one facing" rule (see ZombieVisuals.zombie_texture()). Changing it swaps
## the renderer's texture and touches no buffer entry.
var facing: GameEnums.Facing8 = GameEnums.Facing8.S

var _position: PackedVector2Array = PackedVector2Array()
var _velocity: PackedVector2Array = PackedVector2Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0
var _slice: int = 0
var _phase: int = 0
var _seed: int = 0


func _init(p_seed: int = 0) -> void:
	_seed = absi(p_seed)
	_ensure_wander_dirs()


static func _ensure_wander_dirs() -> void:
	if not _wander_dirs.is_empty():
		return
	_wander_dirs.resize(WANDER_DIR_COUNT)
	for i in WANDER_DIR_COUNT:
		var angle := TAU * float(i) / float(WANDER_DIR_COUNT)
		_wander_dirs[i] = Vector2(cos(angle), sin(angle))


func size() -> int:
	return _count


## How many passes a step should be divided into to move about
## SLICE_TARGET_ENTITIES zombies. `total` is the WHOLE live population, not one
## swarm's: every swarm shares the frame, so they must share one division.
static func slices_for(total: int) -> int:
	if total <= SLICE_TARGET_ENTITIES:
		return 1
	return mini(MAX_SLICES, (total + SLICE_TARGET_ENTITIES - 1) / SLICE_TARGET_ENTITIES)


func slice_count() -> int:
	return maxi(slices, 1)


## The MultiMesh-shaped render mirror. Returned by value like every packed
## array in GDScript, so the caller gets a copy-on-write handle it can hand
## straight to MultiMesh.buffer without being able to corrupt the simulation.
func buffer() -> PackedFloat32Array:
	return _buffer


func position_at(index: int) -> Vector2:
	return _position[index]


## Grows or shrinks the crowd to `count`. New zombies appear scattered inside
## `spread` around the current anchor; shrinking drops the highest indices, so
## a crowd that loses members does not re-scatter the ones that remain.
func set_count(count: int) -> void:
	var wanted := maxi(count, 0)
	if wanted == _count:
		return
	var previous := _count
	_count = wanted
	_position.resize(_count)
	_velocity.resize(_count)
	_speed.resize(_count)
	_buffer.resize(_count * TRANSFORM_FLOATS)
	for i in range(previous, _count):
		_spawn(i)


## Places one new zombie. sqrt() on the radius spreads a uniform sample over
## the disc's area rather than bunching it at the center.
##
## The ANGLE is drawn continuously here rather than from _wander_dirs, and that
## is not a detail: the first version placed every zombie on one of
## WANDER_DIR_COUNT table directions, so a crowd of 60,000 rendered as 64
## spokes radiating from its anchor. Perfectly correct data, obviously wrong
## picture — found by looking at smoke_screenshot.gd's 05_tactical_crowd.png,
## which is why that shot exists. Spawning is once per zombie, so it can
## afford the trig the step loop cannot.
func _spawn(index: int) -> void:
	var angle := TAU * _unit_hash(index * 2)
	var dir := Vector2(cos(angle), sin(angle))
	var radius := spread * sqrt(_unit_hash(index * 2 + 1))
	var variance := MIN_SPEED_VARIANCE + (MAX_SPEED_VARIANCE - MIN_SPEED_VARIANCE) * _unit_hash(index * 2 + 2)
	_position[index] = anchor + dir * radius
	_velocity[index] = dir * (MILL_SPEED * variance)
	_speed[index] = variance
	_write_basis(index)
	_publish(index)


## The 2x4 matrix's rotation half, written once. Nothing after this touches
## it — a zombie sprite's direction is the swarm's texture, not its transform.
func _write_basis(index: int) -> void:
	var base := index * TRANSFORM_FLOATS
	_buffer[base] = 1.0
	_buffer[base + 1] = 0.0
	_buffer[base + 2] = 0.0
	_buffer[base + 4] = 0.0
	_buffer[base + 5] = 1.0
	_buffer[base + 6] = 0.0


func _publish(index: int) -> void:
	var p := _position[index]
	var base := index * TRANSFORM_FLOATS
	_buffer[base + ORIGIN_X_INDEX] = p.x
	_buffer[base + ORIGIN_Y_INDEX] = p.y


## Advances one slice: move, publish to the render mirror, re-steer. All three
## in a single pass over the slice, with no function call inside the loop —
## see this class's own doc comment for what the call overhead measured.
##
## Three cases, cheapest first:
##   inside `spread`            wander at MILL_SPEED
##   outside it                 head back at CHASE_SPEED, which exceeds the
##                              fastest a horde travels, so a crowd streams
##                              after its own anchor instead of trailing off
##   past SNAP_SPREAD_MULTIPLE  re-place around the anchor; see that constant
func step(delta: float) -> void:
	if _count == 0:
		return
	var slice_total := slice_count()
	_slice = (_slice + 1) % slice_total
	_phase += 1
	# Each zombie is visited once every `slices` steps, so it must be advanced
	# by that much time to keep the crowd's speed independent of its size.
	var dt := minf(delta, MAX_STEP_SECONDS) * float(slice_total)
	var spread_squared := spread * spread
	var snap_squared := spread_squared * (SNAP_SPREAD_MULTIPLE * SNAP_SPREAD_MULTIPLE)
	var wander_step := _phase / WANDER_HOLD_STEPS
	var mask := WANDER_DIR_COUNT - 1

	var positions := _position
	_position = PackedVector2Array()  ## Drops this object's reference so the loop below writes in place instead of triggering copy-on-write.

	var i := _slice
	while i < _count:
		var p: Vector2 = positions[i] + _velocity[i] * dt
		var offset := anchor - p
		var distance_squared := offset.length_squared()
		var dir: Vector2
		var speed := _speed[i]
		if distance_squared > spread_squared:
			if distance_squared > snap_squared:
				# Re-placed along the bearing it already had, at a radius its
				# own gait varies — so a crowd whose anchor teleported
				# re-forms as a crowd. Placing it on a table direction here
				# would rebuild the spoke pattern _spawn() documents, all at
				# once, in the one frame the player is most likely to notice.
				p = anchor - offset * (spread * speed * 0.7 / sqrt(distance_squared))
				dir = _wander_dirs[(_seed + i * _WANDER_STRIDE) & mask]
				speed *= MILL_SPEED
			else:
				dir = offset / sqrt(distance_squared)
				speed *= CHASE_SPEED
		else:
			dir = _wander_dirs[(_seed + i * _WANDER_STRIDE + wander_step) & mask]
			speed *= MILL_SPEED
		positions[i] = p
		var base := i * TRANSFORM_FLOATS
		_buffer[base + ORIGIN_X_INDEX] = p.x
		_buffer[base + ORIGIN_Y_INDEX] = p.y
		_velocity[i] = dir * speed
		i += slice_total

	_position = positions


## Deterministic value in [0, 1). The same index always gives the same number,
## so a zombie keeps its own gait for as long as it exists.
##
## A plain multiply-and-modulo was not good enough and the screen said so:
## consecutive indices differ by a constant under it, so the "random" angles a
## crowd spawned at marched round the circle in even steps. The avalanche
## rounds below are the standard fix. Only _spawn() calls this — nothing in
## the step loop hashes anything.
func _unit_hash(index: int) -> float:
	var h := (_seed + index) * _HASH_MULTIPLIER
	h = (h ^ (h >> 15)) * _HASH_MIX_A
	h = (h ^ (h >> 13)) * _HASH_MIX_B
	h = h ^ (h >> 16)
	return float(absi(h) % _HASH_RANGE) / float(_HASH_RANGE)


## --- Save/load (D15) --------------------------------------------------------

## Positions only, as x,y float32 pairs. Velocity is re-chosen within one step
## of a load anyway, and the basis is a constant.
func get_positions() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_count * 2)
	for i in _count:
		var p := _position[i]
		out[i * 2] = p.x
		out[i * 2 + 1] = p.y
	return out


## Overwrites this swarm's positions from `pool`, starting at float index
## `offset`, and returns the new offset. Consumes at most this swarm's own
## count; a pool that runs out leaves the remaining zombies where set_count()
## scattered them, which is what makes a load whose counts have drifted from
## the save (a horde that bred, or was killed down) still land correctly.
func load_positions(pool: PackedFloat32Array, offset: int) -> int:
	var available := (pool.size() - offset) / 2
	var restored := mini(available, _count)
	for i in restored:
		_position[i] = Vector2(pool[offset + i * 2], pool[offset + i * 2 + 1])
		_publish(i)
	return offset + restored * 2
