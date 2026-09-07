extends Node

## Proves a horde's merge/split rolls happen at the rate they claim to. Run
## (as a real scene, not `-s`: HordeManager connects to the TickManager
## autoload, which script mode cannot resolve):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_horde_fragmentation.tscn
##
## ## What this is guarding against
##
## MERGE_CHANCE_PER_DAY and SPLIT_CHANCE_PER_DAY are read once per
## LOGIC_TICK_SECONDS (20 s) and a day is TickManager.DAY_LENGTH_SECONDS
## (2400 s), so the two differ by a factor of 120. Rolling a per-day
## probability at per-tick cadence is not a small error and it is invisible in
## a diff — the constant looks right at both ends.
##
## Measured before the conversion, on the real map with no player action
## (scripts/test/diagnose_horde_contact.gd): 3 starting hordes became **1,092
## by day 15** while the zombies inside them went 33 -> 25,658. Mean horde size
## settled at 23.5, just above SPLIT_MIN_SIZE — the equilibrium unbounded
## splitting predicts. vision.md P5 wants the opposite of that: the threat has
## to arrive as a horde, not as confetti.
##
## Three checks, because the obvious two can both pass while the feature is
## broken:
##
##  1. **The conversion is exact.** Compounding per_tick_chance(p) over a
##     day's ticks must return p. This is the arithmetic that was wrong.
##  2. **Fragmentation stays bounded** over a real number of days.
##  3. **Fragmentation still happens.** Check 2 passes perfectly if splitting
##     is dead, which would be a different way of losing the mechanic. A rate
##     of zero must fail this file, not satisfy it.

## A radius small enough to keep the fixture cheap. Cells are plain HexCells
## with no terrain features, so HexCell.is_frontier() is false throughout and
## _pick_drift_target() finds no candidate — hordes hold position instead of
## pathfinding. That is deliberate: this file is about the merge/split rolls,
## and letting hordes wander would make the result depend on HordeFlowField.
const _FIXTURE_RADIUS: int = 3
const _DAYS: int = 20
const _SEED_HORDE_SIZE: int = 4000  ## Comfortably above SPLIT_MIN_SIZE, so it stays eligible through many halvings.
const _EPSILON: float = 1e-9

## The measured post-conversion count is 6 (see this file's own output). 40
## leaves an order of magnitude of headroom for RNG and for a future balance
## change to MERGE/SPLIT_CHANCE_PER_DAY, while the pre-conversion behaviour
## produced 1,092 in fewer days — the two are nowhere near each other, which
## is what makes this bound meaningful rather than a tripwire.
const _MAX_REASONABLE_HORDES: int = 40

var _map: HexGridMap
var _hordes: HordeManager
var _failures: Array[String] = []

## A member, not a local captured by a lambda: GDScript closures capture local
## variables BY VALUE, so counting into a local from a signal handler silently
## reports zero forever. The first version of check 3 did exactly that and
## claimed the mechanic was dead while check 2 was watching it work.
var _splits_observed: int = 0


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_hordes = load("res://scenes/world/HordeManager.tscn").instantiate()
	_hordes.name = "HordeManager"
	_hordes.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_hordes)

	get_tree().quit(_run())


func _run() -> int:
	_check_the_per_day_conversion_is_exact()
	_check_fragmentation_stays_bounded()
	_check_fragmentation_still_happens()

	print()
	if _failures.is_empty():
		print("All horde-fragmentation checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## The whole defect in one line: a probability rolled 120 times a day has to be
## the 120th-root of the daily one, not the daily one. Compounding the
## converted value back over a day must return what was asked for.
func _check_the_per_day_conversion_is_exact() -> void:
	var ticks_per_day := TickManager.DAY_LENGTH_SECONDS / HordeManager.LOGIC_TICK_SECONDS
	print("ticks per day: %.0f" % ticks_per_day)
	for per_day in [0.0, 0.05, 0.1, 0.5, 1.0]:
		var per_tick := HordeManager.per_tick_chance(per_day)
		var compounded := 1.0 - pow(1.0 - per_tick, ticks_per_day)
		print("  %.2f/day -> %.6f/tick -> %.6f/day recompounded" % [per_day, per_tick, compounded])
		if absf(compounded - per_day) > 1e-6:
			_failures.append("a %.2f/day chance compounds back to %.6f/day — the tick conversion is not the inverse of a day" % [per_day, compounded])
		if per_tick > per_day + _EPSILON:
			_failures.append("a %.2f/day chance became a LARGER %.6f per-tick chance — the conversion is inverted" % [per_day, per_tick])

	# The naive conversion (p / ticks) is close for small p and wrong as p
	# grows. Asserting the difference stops someone "simplifying" to it.
	var naive := 1.0 / ticks_per_day
	var exact := HordeManager.per_tick_chance(1.0)
	if absf(naive - exact) < 1e-6:
		_failures.append("per_tick_chance(1.0) matches the naive p/ticks — a certainty must convert to a certainty per tick, not to 1/%.0f" % ticks_per_day)


## The behavioural half. One large horde, driven for a real number of days,
## must not turn the map into fragments.
func _check_fragmentation_stays_bounded() -> void:
	_reset_with_one_horde()
	_drive_days(_DAYS)
	var count := _hordes.get_all_hordes().size()
	var total := _total_size()
	print("after %d days from 1 horde of %d: %d hordes, %d zombies" % [_DAYS, _SEED_HORDE_SIZE, count, total])
	if count > _MAX_REASONABLE_HORDES:
		_failures.append("1 horde became %d in %d days (bound %d) — splitting is outrunning merging again" % [
			count, _DAYS, _MAX_REASONABLE_HORDES])
	if total != _SEED_HORDE_SIZE:
		_failures.append("merging and splitting changed the zombie total from %d to %d — neither is supposed to create or destroy any" % [
			_SEED_HORDE_SIZE, total])


## The vacuity guard. A bound is satisfied just as well by a mechanic that
## never fires, so this drives long enough that at least one split is
## overwhelmingly likely and fails if none ever happened.
func _check_fragmentation_still_happens() -> void:
	_reset_with_one_horde()
	_splits_observed = 0
	_hordes.horde_spawned.connect(func(_horde: Horde) -> void: _splits_observed += 1)
	_drive_days(_DAYS * 10)
	print("over %d days: %d splits observed" % [_DAYS * 10, _splits_observed])
	if _splits_observed == 0:
		_failures.append("no horde ever split across %d days — the mechanic is dead, not merely slowed" % (_DAYS * 10))


## Drives whole logic ticks. Passing LOGIC_TICK_SECONDS exactly means each
## call is one merge/split roll, so the count of rolls is exact rather than
## dependent on a floating-point accumulator.
func _drive_days(days: int) -> void:
	var ticks := int(float(days) * TickManager.DAY_LENGTH_SECONDS / HordeManager.LOGIC_TICK_SECONDS)
	for _i in range(ticks):
		_hordes._process(HordeManager.LOGIC_TICK_SECONDS)


func _reset_with_one_horde() -> void:
	_hordes.load_save_state([] as Array[Horde], 1)
	_hordes.spawn_horde_at(Vector2i.ZERO, _SEED_HORDE_SIZE)


func _total_size() -> int:
	var total := 0
	for horde: Horde in _hordes.get_all_hordes():
		total += horde.size
	return total


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(Vector2i.ZERO, _FIXTURE_RADIUS):
		cells[coord] = HexCell.new(coord)
	return cells
