extends Node

## Proves design_doc.md §2.1's resident population can actually be fought, and
## that fighting it neither creates nor loses zombies. Run (as a real scene,
## not `-s` — it needs the TickManager/TimeCycleManager autoloads the managers
## under test connect to and read):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_resident_defense.tscn
##
## ## What each check is guarding against
##
## The mechanism's whole claim is that residents become fightable WITHOUT a
## second kind of enemy and WITHOUT a second source of truth (D48). So the
## failures worth catching are:
##
## * **Condensation that does not conserve.** The count leaves `_resident` and
##   arrives as a `Horde` on the same hex; if the two halves are not exactly
##   equal, either infestation drops for free (D8's "killing is the only
##   suppression" is dead) or zombies appear from nowhere. Checks 2 and 3.
## * **A frontage that is a fraction of the population rather than an area of
##   its density.** Get that wrong and a London hex fields a wave of thousands
##   and ends the run on contact, or a rural hex fields zero and can never be
##   cleared at all. Check 1 pins the curve at the real map's own measured
##   counts.
## * **A grind that does not terminate.** The reason the frontage floors at 1:
##   below ~11,450 residents the engagement disc holds less than half a zombie.
##   Check 6 grinds a hex all the way to Cleared.
## * **A wave that keeps growing.** Top-up-to-frontage, not add-a-wave-per-tick
##   — otherwise a player could drain a Hive Core into a horde faster than they
##   could kill it. Check 5.
##
## Fixture rather than the real map, same reasoning verify_infestation.gd and
## verify_horde_infrastructure.gd both record: HexMapGenerator builds the whole
## UK+Ireland corridor on every run, which is minutes per launch. The real-map
## numbers are measured by scripts/test/diagnose_resident_combat.gd instead.

const _FIXTURE_RADIUS: int = 3
const _CAPACITY: int = 10_000
const _HOME := Vector2i.ZERO          ## Where the test unit stands.
const _ELSEWHERE := Vector2i(2, 0)    ## Populated, but never visited by a unit.

## One hex with a real city's capacity. A resident count is CLAMPED to its hex's
## own `total_zombie_pop` (InfestationManager._write_resident()), so the checks
## that need a frontage above the floor of 1 need somewhere that can hold the
## population which produces one — below ~11,450 residents the engagement disc
## holds less than half a zombie, which is exactly why the floor exists.
const _CITY := Vector2i(0, 2)
const _CITY_CAPACITY: int = 1_000_000

var _map: HexGridMap
var _hordes: HordeManager
var _infestation: InfestationManager
var _units: UnitManager
var _combat: CombatCoordinator
var _defense: ResidentDefenseController
var _failures: Array[String] = []


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	# Wired BEFORE add_child so each _ready() resolves its dependencies, same
	# ordering verify_infestation.gd records. HordeManager._ready() also calls
	# seed_starting_hordes(); this fixture's cells carry no districts, so
	# HexCell.is_frontier() is false everywhere and _spawnable_coords() comes
	# back empty. The assertion below is the guard rather than the comment.
	_hordes = load("res://scenes/world/HordeManager.tscn").instantiate()
	_hordes.name = "HordeManager"
	_hordes.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_hordes)
	if not _hordes.get_all_hordes().is_empty():
		_failures.append("the fixture seeded %d starting hordes — every count below is position-dependent" % _hordes.get_all_hordes().size())

	_infestation = load("res://scenes/world/InfestationManager.tscn").instantiate()
	_infestation.name = "InfestationManager"
	_infestation.hex_grid_map_path = NodePath("../HexGridMap")
	_infestation.horde_manager_path = NodePath("../HordeManager")
	add_child(_infestation)
	# No building_manager_path, so _seed_from_starting_settlement() is a no-op
	# and every resident count below is one this test put there on purpose.
	_infestation.seed_rings_from(_HOME)
	_zero_every_hex()  # Every count below is one a check put there on purpose, not a worldgen ring.

	_units = load("res://scenes/units/UnitManager.tscn").instantiate()
	_units.name = "UnitManager"
	_units.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_units)

	_combat = load("res://scenes/units/CombatCoordinator.tscn").instantiate()
	_combat.name = "CombatCoordinator"
	_combat.unit_manager_path = NodePath("../UnitManager")
	_combat.horde_manager_path = NodePath("../HordeManager")
	# No unit_order_controller_path / building_manager_path: this test drives
	# contact through engage_units_at(), never through movement, and there are
	# no buildings to siege.
	add_child(_combat)

	_defense = load("res://scenes/world/ResidentDefenseController.tscn").instantiate()
	_defense.name = "ResidentDefenseController"
	_defense.unit_manager_path = NodePath("../UnitManager")
	_defense.combat_coordinator_path = NodePath("../CombatCoordinator")
	_defense.infestation_manager_path = NodePath("../InfestationManager")
	_defense.horde_manager_path = NodePath("../HordeManager")
	add_child(_defense)

	get_tree().quit(_run())


func _run() -> int:
	_check_frontage_curve()
	_check_condensation_conserves()
	_check_condensation_is_bounded()
	_check_no_units_no_wave()
	_check_wave_tops_up_and_does_not_stack()
	_check_grinding_a_hex_clears_it()
	_check_a_stack_kills_in_proportion_to_its_size()
	_check_untouched_hexes_are_untouched()
	_check_save_round_trip_mid_grind()

	print()
	if _failures.is_empty():
		print("All resident-defense checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## The frontage is an AREA of the hex's density, not a share of its count. The
## four population rows are the real map's own measured resident counts
## (decisions.md D44); if hex area, the engagement radius or the rounding move,
## these move with them and the difficulty curve silently changes.
func _check_frontage_curve() -> void:
	var cases := [
		[446_729, 20],  # Greater London
		[321_008, 14],  # Birmingham
		[68_075, 3],    # Manchester
		[1_000, 1],     # A 1,000-floor hex at 100% — the floor, not the formula.
		[0, 0],         # Nothing there is nothing to fight.
	]
	for case in cases:
		var got := ResidentDefenseController.frontage_for(case[0])
		print("frontage: %8d residents -> %2d (want %d)" % [case[0], got, case[1]])
		if got != case[1]:
			_failures.append("%d residents field a wave of %d, the density curve says %d" % [case[0], got, case[1]])

	# The cap: a hex cannot field more defenders than it has people, however
	# the rounding falls.
	if ResidentDefenseController.frontage_for(1) != 1:
		_failures.append("a hex holding one resident fields %d defenders" % ResidentDefenseController.frontage_for(1))
	# Monotonic — a more populous hex never presses less hard.
	var previous := 0
	for residents in [1, 1_000, 50_000, 100_000, 321_008, 446_729, 2_000_000]:
		var wave := ResidentDefenseController.frontage_for(residents)
		if wave < previous:
			_failures.append("frontage fell from %d to %d as residents rose to %d" % [previous, wave, residents])
		previous = wave


## The conservation law the whole design rests on: the count leaves `_resident`
## and arrives as a `Horde` on the SAME hex, so `zombie_count_at()` — and
## therefore `infestation` and the band — do not move at all. Only killing
## moves them (D8).
func _check_condensation_conserves() -> void:
	_infestation.add_zombies(_HOME, 4_000)
	var total_before := _infestation.zombie_count_at(_HOME)
	var infestation_before := _infestation.infestation_at(_HOME)
	var band_before := _infestation.band_at(_HOME)

	var moved := _infestation.condense_defenders(_HOME, 250)
	var residents_after := _infestation.resident_count_at(_HOME)
	var roaming_after := _hordes.get_zombie_count_at(_HOME)
	print("condense: 4000 residents -> %d moved, %d resident + %d roaming = %d (was %d)" % [moved, residents_after, roaming_after, _infestation.zombie_count_at(_HOME), total_before])

	if moved != 250:
		_failures.append("asked to condense 250 defenders out of 4,000 residents, moved %d" % moved)
	if roaming_after != 250:
		_failures.append("250 condensed defenders arrived as %d roaming zombies" % roaming_after)
	if residents_after != 3_750:
		_failures.append("condensing 250 left %d residents, not 3,750" % residents_after)
	if _infestation.zombie_count_at(_HOME) != total_before:
		_failures.append("condensing changed the hex's total from %d to %d — it must only move zombies, never make or lose them" % [total_before, _infestation.zombie_count_at(_HOME)])
	if absf(_infestation.infestation_at(_HOME) - infestation_before) > 0.001:
		_failures.append("condensing moved infestation from %.3f%% to %.3f%%" % [infestation_before, _infestation.infestation_at(_HOME)])
	if _infestation.band_at(_HOME) != band_before:
		_failures.append("condensing changed the hex's band, so a conserving move is being treated as a population change")

	_reset_world()


## A hex cannot field defenders it does not have, and asking for more must not
## drive the resident count negative — the failure that would let a hex export
## zombies it never held.
func _check_condensation_is_bounded() -> void:
	_infestation.add_zombies(_HOME, 40)
	var moved := _infestation.condense_defenders(_HOME, 500)
	print("condense: asked 500 from a hex holding 40 -> %d moved, %d left" % [moved, _infestation.resident_count_at(_HOME)])
	if moved != 40:
		_failures.append("asked for 500 defenders from 40 residents, got %d" % moved)
	if _infestation.resident_count_at(_HOME) != 0:
		_failures.append("over-condensing left %d residents, not 0" % _infestation.resident_count_at(_HOME))
	if _infestation.condense_defenders(_HOME, 10) != 0:
		_failures.append("an emptied hex still condensed defenders")
	if _infestation.condense_defenders(_HOME, 0) != 0 or _infestation.condense_defenders(_HOME, -5) != 0:
		_failures.append("condense_defenders() acted on a non-positive count")

	_reset_world()


## §2.1's Contested band "spreads nothing". A populated hex with no player unit
## on it must therefore stay exactly as it was, however infested — the wave is
## a RESPONSE to the player, not a passive emission.
func _check_no_units_no_wave() -> void:
	_infestation.add_zombies(_ELSEWHERE, 5_000)
	var before := _infestation.resident_count_at(_ELSEWHERE)
	for i in 5:
		_defense.run_wave_tick()
	print("no units: %s held %d residents, holds %d after 5 wave ticks" % [_ELSEWHERE, before, _infestation.resident_count_at(_ELSEWHERE)])
	if _infestation.resident_count_at(_ELSEWHERE) != before:
		_failures.append("a hex with no player unit on it condensed defenders anyway")
	if not _hordes.get_hordes_at(_ELSEWHERE).is_empty():
		_failures.append("a hex with no player unit on it produced a horde")

	_reset_world()


## Top up to the frontage, never add a wave per tick. The failure this catches
## is the one that would let a player drain a Hive Core into a roaming horde
## simply by parking a unit on it and never killing anything.
##
## Driven through reinforce() directly rather than through a full tick: a tick
## also resolves combat, and combat feeds the unit's own lost squad figures back
## onto the hex as casualty zombies (CombatCoordinator._engage()), which is real
## behaviour but is not the rule under test here.
func _check_wave_tops_up_and_does_not_stack() -> void:
	_infestation.add_zombies(_CITY, 400_000)
	var frontage := ResidentDefenseController.frontage_for(400_000)
	var first := _defense.reinforce(_CITY)
	var second := _defense.reinforce(_CITY)
	var third := _defense.reinforce(_CITY)
	print("top-up: frontage %d, three reinforcements moved %d / %d / %d, standing %d" % [frontage, first, second, third, _hordes.get_zombie_count_at(_CITY)])
	if first != frontage:
		_failures.append("the first reinforcement fielded %d defenders, the frontage is %d" % [first, frontage])
	if second != 0 or third != 0:
		_failures.append("reinforcing an already-full hex fielded %d then %d more — waves are stacking, not topping up" % [second, third])
	if _hordes.get_zombie_count_at(_CITY) != frontage:
		_failures.append("%d defenders are standing against a frontage of %d" % [_hordes.get_zombie_count_at(_CITY), frontage])
	if _infestation.resident_count_at(_CITY) != 400_000 - frontage:
		_failures.append("400,000 residents became %d after fielding %d defenders" % [_infestation.resident_count_at(_CITY), frontage])

	# A hex already carrying more zombies than its frontage — a roaming horde
	# that wandered in — fields nobody new.
	_hordes.spawn_horde_at(_CITY, 5_000)
	if _defense.reinforce(_CITY) != 0:
		_failures.append("a hex under a 5,000-strong horde still condensed more defenders")

	# And the full tick does draw a wave, so the rule above is reachable.
	_reset_world()
	_infestation.add_zombies(_CITY, 400_000)
	var unit := _spawn_test_unit(_CITY)
	unit.current_hp = unit.definition.max_hp
	_defense.run_wave_tick()
	print("one tick with a unit present: %d standing" % _hordes.get_zombie_count_at(_CITY))
	if _hordes.get_zombie_count_at(_CITY) <= 0:
		_failures.append("a unit standing on 400,000 residents drew no defenders at all")

	_reset_world()


## The point of the whole feature: killing residents lowers infestation, and a
## hex can be ground all the way to Cleared. D8 ("killing is the only
## suppression") reaching the resident half is what was missing.
func _check_grinding_a_hex_clears_it() -> void:
	_infestation.add_zombies(_HOME, 600)  # 6% of _CAPACITY — Fringe, one point above the 5% Cleared threshold.
	var start_total := _infestation.zombie_count_at(_HOME)
	var unit := _spawn_test_unit(_HOME)
	if _infestation.is_cleared(_HOME):
		_failures.append("the fixture started Cleared — the grind below proves nothing")

	var ticks := 0
	while ticks < 400 and not _infestation.is_cleared(_HOME):
		unit.current_hp = unit.definition.max_hp
		_defense.run_wave_tick()
		ticks += 1
		if _infestation.zombie_count_at(_HOME) > start_total:
			_failures.append("the hex's total ROSE to %d from %d during the grind — the mechanism is creating zombies" % [_infestation.zombie_count_at(_HOME), start_total])
			break

	print("grind: %d%% -> %.2f%% over %d wave ticks (%d zombies killed)" % [
		int(round(float(start_total) / float(_CAPACITY) * 100.0)),
		_infestation.infestation_at(_HOME),
		ticks,
		start_total - _infestation.zombie_count_at(_HOME),
	])
	if not _infestation.is_cleared(_HOME):
		_failures.append("400 wave ticks left the hex at %.2f%% — a hex that cannot be ground to Cleared cannot be taken" % _infestation.infestation_at(_HOME))
	if _infestation.zombie_count_at(_HOME) >= start_total:
		_failures.append("grinding did not lower the hex's zombie count at all")

	_reset_world()


## D50: the wave is topped back up between one unit's round and the next, so a
## stack of units kills at a rate proportional to its size. Without that, the
## first unit wipes a small wave and every other unit on the hex engages nothing
## — ten units clear a hex exactly as slowly as one, and no amount of balancing
## the combat numbers can lift that ceiling, because it is a property of the
## wave rule rather than of the damage.
##
## Deliberately NOT asserted as exactly 10x: a wave large enough to survive one
## unit's damage leaves the next unit a partly-cut wave rather than a fresh one,
## so the relationship is proportional, not linear. 5x is comfortably below the
## proportional case and comfortably above the broken one (1x).
func _check_a_stack_kills_in_proportion_to_its_size() -> void:
	var solo := _kills_over_ticks(1, 10)
	_reset_world()
	var stack := _kills_over_ticks(10, 10)
	print("stack scaling: 1 unit killed %d over 10 ticks, 10 units killed %d (%.1fx)" % [solo, stack, float(stack) / maxf(1.0, float(solo))])
	if solo <= 0:
		_failures.append("a lone unit killed nothing over 10 ticks — the comparison below means nothing")
	if stack < solo * 5:
		_failures.append("ten units killed %d where one killed %d — a stack is not killing in proportion to its size" % [stack, solo])

	_reset_world()


## Parks `unit_count` units on _CITY, runs `ticks` wave ticks, and returns how
## many zombies left the hex. HP is topped up between ticks for the same reason
## every other check here does it — see _spawn_test_unit().
func _kills_over_ticks(unit_count: int, ticks: int) -> int:
	_infestation.add_zombies(_CITY, 400_000)
	var entries: Array[UnitSaveEntry] = []
	var definition := UnitCatalog.get_definition(GameEnums.UnitType.TRUNCHEONEER)
	for i in unit_count:
		entries.append(UnitSaveEntry.new(GameEnums.UnitType.TRUNCHEONEER, _CITY, i + 1, definition.max_hp))
	_units.load_save_entries(entries, unit_count + 1)

	var before := _infestation.zombie_count_at(_CITY)
	for tick in ticks:
		for unit: UnitInstance in _units.get_all_units():
			unit.current_hp = unit.definition.max_hp
		_defense.run_wave_tick()
	return before - _infestation.zombie_count_at(_CITY)


## Only the hex the player is standing on responds. A neighbour must not lose
## residents because a fight happened next door — the wave is per hex, and
## nothing about it propagates.
func _check_untouched_hexes_are_untouched() -> void:
	_infestation.add_zombies(_HOME, 5_000)
	_infestation.add_zombies(_ELSEWHERE, 5_000)
	var neighbour := Vector2i(1, 0)
	_infestation.add_zombies(neighbour, 5_000)
	var unit := _spawn_test_unit(_HOME)
	for i in 8:
		unit.current_hp = unit.definition.max_hp
		_defense.run_wave_tick()
	print("isolation: home %d, neighbour %d, far %d" % [
		_infestation.zombie_count_at(_HOME), _infestation.zombie_count_at(neighbour), _infestation.zombie_count_at(_ELSEWHERE)])
	for coord in [neighbour, _ELSEWHERE]:
		if _infestation.zombie_count_at(coord) != 5_000:
			_failures.append("%s holds %d zombies after a fight on a different hex, not 5,000" % [coord, _infestation.zombie_count_at(coord)])

	_reset_world()


## Nothing about the wave is saved, and nothing needs to be: a defending wave IS
## a horde, and both halves of a hex's population already round-trip. Saving
## mid-grind and reloading must put back exactly the fight that was in progress.
##
## The horde half is deep-copied here because HordeManager.get_save_state()
## returns a SHALLOW duplicate of its array — the real save path serialises to
## disk, which copies the Resources; an in-memory snapshot that did not would
## keep mutating along with the live hordes and the check would pass vacuously.
func _check_save_round_trip_mid_grind() -> void:
	_infestation.add_zombies(_CITY, 200_000)
	var unit := _spawn_test_unit(_CITY)
	for i in 3:
		unit.current_hp = unit.definition.max_hp
		_defense.run_wave_tick()

	var residents := _infestation.resident_count_at(_CITY)
	var standing := _hordes.get_zombie_count_at(_CITY)
	var total := _infestation.zombie_count_at(_CITY)
	if standing <= 0:
		_failures.append("no defending wave was standing when the save was taken — the round trip below proves nothing")

	var infestation_state := _infestation.get_save_state()
	var saved_hordes: Array[Horde] = []
	for horde: Horde in _hordes.get_all_hordes():
		saved_hordes.append(horde.duplicate())
	var saved_next_id := int(_hordes.get_save_state()["next_id"])

	# Move the world on before restoring, so a restore that silently does
	# nothing cannot pass.
	for i in 3:
		unit.current_hp = unit.definition.max_hp
		_defense.run_wave_tick()
	if _infestation.zombie_count_at(_CITY) == total:
		_failures.append("three more wave ticks changed nothing, so the restore below cannot be distinguished from a no-op")

	_infestation.load_save_state(infestation_state)
	_hordes.load_save_state(saved_hordes, saved_next_id)

	print("save round trip: %d resident + %d roaming = %d restored" % [
		_infestation.resident_count_at(_CITY), _hordes.get_zombie_count_at(_CITY), _infestation.zombie_count_at(_CITY)])
	if _infestation.resident_count_at(_CITY) != residents:
		_failures.append("residents restored to %d, saved %d" % [_infestation.resident_count_at(_CITY), residents])
	if _hordes.get_zombie_count_at(_CITY) != standing:
		_failures.append("the defending wave restored to %d, saved %d" % [_hordes.get_zombie_count_at(_CITY), standing])
	if _infestation.zombie_count_at(_CITY) != total:
		_failures.append("the hex restored holding %d zombies, saved %d" % [_infestation.zombie_count_at(_CITY), total])

	_reset_world()


## A Tier 0 Truncheoneer, injected through load_save_entries() rather than
## trained: training needs a Town Hall, a ResourceManager and a tech gate, none
## of which this fixture has, and the restore path is public and already
## bypasses cost/validation for exactly this reason.
##
## Callers top its HP back up between ticks on purpose. A unit that loses a
## derived squad figure spawns casualty zombies onto its own hex
## (CombatCoordinator._engage()), which is real behaviour but would make every
## count below depend on the unit's survivability rather than on the wave rule.
## How long a unit actually survives is measured on the real map by
## scripts/test/diagnose_resident_combat.gd instead.
func _spawn_test_unit(coord: Vector2i) -> UnitInstance:
	var entries: Array[UnitSaveEntry] = [UnitSaveEntry.new(GameEnums.UnitType.TRUNCHEONEER, coord, 1, UnitCatalog.get_definition(GameEnums.UnitType.TRUNCHEONEER).max_hp)]
	_units.load_save_entries(entries, 2)
	return _units.get_all_units()[0]


## Back to an empty world between checks: no residents, no hordes, no units. The
## checks share one fixture and each one states its own starting population, so
## a leftover from the previous check would read as a result of this one.
func _reset_world() -> void:
	_zero_every_hex()
	for horde in _hordes.get_all_hordes():
		_hordes.remove_horde(horde)
	var none: Array[UnitSaveEntry] = []
	_units.load_save_entries(none, 1)


func _zero_every_hex() -> void:
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		_infestation.remove_zombies(coord, _CITY_CAPACITY)


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		cell.biome_type = GameEnums.BiomeType.MOORLAND
		cell.soil_fertility = GameEnums.SoilFertility.POOR
		# Flat capacity across the fixture so every percentage below is a
		# statement about the model rather than about the population bake —
		# except _CITY, which has to be able to hold a city (see its own const).
		cell.total_zombie_pop = _CITY_CAPACITY if coord == _CITY else _CAPACITY
		cells[coord] = cell
	return cells
