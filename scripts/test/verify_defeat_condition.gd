extends Node

## Proves vision.md P4 ("Losing is real") is actually implemented — that the
## campaign CAN end, that it does not end for the wrong reasons, and that the
## player is warned first. Run (as a real scene, not `-s`:
## DefeatConditionMonitor connects to the TickManager autoload, which script
## mode cannot resolve):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_defeat_condition.tscn
##
## ## What each check is guarding against
##
## A defeat check has two failure directions and they are not symmetric. Firing
## when it should not ends a campaign the player was still winning, which is
## unrecoverable and the worse of the two. Never firing is P4 going back to
## being aspirational.
##
## * **The trivial false positive.** A fresh colony, and every ordinary
##   setback, must not end the run. Checks 1 and 3.
## * **The startup false positive.** Between DefeatConditionMonitor._ready()
##   and BuildingManager.seed_starting_buildings() the player owns nothing, so
##   all three conditions hold and every campaign would end on day one. The
##   arming latch is the guard; check 2 is what stops the latch being removed
##   as redundant.
## * **Any single condition being treated as sufficient.** 7.6 is explicit
##   that holding one thread means the campaign continues. Check 3 runs each
##   condition alone and each pair.
## * **The check never firing at all.** Check 4.
## * **A campaign that un-ends.** Rebuilding after the loss must not resurrect
##   the run — the signal is one-shot and the verdict latched. Check 5.
## * **A loss with no warning.** P4 asks for "clear warning before the point of
##   no return", so the risk signal must arrive strictly before the loss, not
##   with it. Check 6.
##
## Fixture rather than the real map, for the reason verify_building_power.gd,
## verify_infestation.gd and verify_gates.gd all record: HexMapGenerator builds
## the whole UK+Ireland corridor on every run, which is minutes per launch.
## Buildings are registered through BuildingManager.load_save_entries() — the
## same public entry point SaveLoadManager uses — because placement legality
## resolves at sub-hex resolution against baked raster data a hand-built cell
## cannot control.

const _FIXTURE_RADIUS: int = 2
const _HOME := Vector2i.ZERO
const _HALL_HEX := Vector2i(1, 0)   ## Town Hall — the trainer, and a producer (RESEARCH_POINTS).
const _YARD_HEX := Vector2i(2, 0)   ## Lumber Yard — a producer that trains nothing.
const _TOWER_HEX := Vector2i(0, 1)  ## Watchtower — produces nothing, trains nothing.
const _GARRISON_HEX := Vector2i(0, 2)  ## Garrison — trains, produces nothing.

const _HALL := GameEnums.BuildingType.TOWN_HALL
const _YARD := GameEnums.BuildingType.LUMBER_YARD
const _TOWER := GameEnums.BuildingType.WATCHTOWER
## The trainer used for the "produces nothing" case, rather than a
## switched-off Town Hall: the Town Hall is always_powered (D54), so
## power_down_building() refuses it and the fixture silently tests nothing.
## That is what the condition-count assertion in _expect_alive() caught.
const _GARRISON := GameEnums.BuildingType.GARRISON

var _map: HexGridMap
var _resources: ResourceManager
var _buildings: BuildingManager
var _monitor: DefeatConditionMonitor
var _starting_stockpile: Dictionary = {}
var _starting_caps: Dictionary = {}
var _failures: Array[String] = []

## Signal traffic since the last _reset_signals(), so a check can assert on
## what was BROADCAST and not only on what the getters report — a latched flag
## with no signal would leave every consumer (EventManager, and the HUD behind
## it) silent.
var _lost_signals: Array = []
var _risk_signals: Array = []


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_resources = load("res://scenes/economy/ResourceManager.tscn").instantiate()
	_resources.name = "ResourceManager"
	add_child(_resources)
	_starting_stockpile = _resources.get_full_stockpile()
	_starting_caps = _resources.get_full_storage_caps()

	# Wired BEFORE add_child so _ready() resolves them, the ordering
	# verify_building_power.gd and verify_infestation.gd both record.
	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = NodePath("../HexGridMap")
	_buildings.resource_manager_path = NodePath("../ResourceManager")
	add_child(_buildings)
	if not _buildings.get_all_buildings().is_empty():
		_failures.append("the fixture seeded %d starting buildings — the arming check below would be meaningless" % _buildings.get_all_buildings().size())

	get_tree().quit(_run())


func _run() -> int:
	_check_fixture_premises()
	_check_a_healthy_colony_is_not_defeated()
	_check_nothing_fires_before_the_colony_exists()
	_check_no_single_condition_is_enough()
	_check_all_three_conditions_end_the_campaign()
	_check_the_verdict_is_latched()
	_check_the_warning_arrives_before_the_loss()

	print()
	if _failures.is_empty():
		print("All defeat-condition checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## Every check below is built on three catalog facts. Asserting them here
## means a balance pass that gives the Watchtower an output, or takes training
## off the Town Hall, produces a message naming the cause instead of a
## mysterious failure three checks later.
func _check_fixture_premises() -> void:
	var hall := BuildingCatalog.get_definition(_HALL)
	var yard := BuildingCatalog.get_definition(_YARD)
	var tower := BuildingCatalog.get_definition(_TOWER)
	if not hall.can_train_units:
		_failures.append("fixture premise: %s no longer trains units — pick another trainer for these checks" % hall.display_name)
	if yard.can_train_units:
		_failures.append("fixture premise: %s now trains units — it is used here as a producer that does NOT" % yard.display_name)
	if tower.can_train_units or not tower.daily_output.is_empty():
		_failures.append("fixture premise: %s is no longer inert (trains: %s, output: %s) — the defeat fixture needs a standing building that neither produces nor trains" % [
			tower.display_name, tower.can_train_units, tower.daily_output])
	var garrison := BuildingCatalog.get_definition(_GARRISON)
	if not garrison.can_train_units or not garrison.daily_output.is_empty():
		_failures.append("fixture premise: %s must train units and produce nothing (trains: %s, output: %s) — it is the only way to isolate the no-production condition" % [
			garrison.display_name, garrison.can_train_units, garrison.daily_output])


## A colony with a Town Hall, a Lumber Yard and a full stockpile is winning.
## Nothing here should so much as warn.
func _check_a_healthy_colony_is_not_defeated() -> void:
	_reset_fixture([_HALL, _YARD])
	_monitor.evaluate_now()
	var result := _monitor.evaluate()
	print("healthy colony: affordable=%s production=%s trainer=%s" % [
		not result["no_affordable_expansion"], not result["no_production"], not result["no_trainer"]])
	if _monitor.is_defeated():
		_failures.append("a colony with a Town Hall, a Lumber Yard and a full stockpile reads as defeated (%s)" % ", ".join(result["reasons"]))
	if _monitor.is_at_risk():
		_failures.append("a healthy colony reads as at risk (%s)" % ", ".join(result["reasons"]))
	if not _risk_signals.is_empty():
		_failures.append("a healthy colony emitted %d defeat_risk_changed signals" % _risk_signals.size())


## The arming latch. With no buildings and no resources every condition holds,
## which is exactly the state a campaign passes through before
## seed_starting_buildings() runs. If this fires, every new game ends on day
## one.
func _check_nothing_fires_before_the_colony_exists() -> void:
	_reset_fixture([])
	_resources.load_state(_zero_stockpile(), _starting_caps)
	_monitor.evaluate_now()
	print("before any building exists: defeated=%s" % _monitor.is_defeated())
	if _monitor.is_defeated():
		_failures.append("the campaign ended before the colony was ever placed — the arming latch is not holding")
	if not _lost_signals.is_empty():
		_failures.append("campaign_lost fired with no building ever placed")


## 7.6: "Holding even one settlement able to recruit/expand means the player
## still has a chance." Each condition alone, and each pair, must leave the
## campaign running.
func _check_no_single_condition_is_enough() -> void:
	# Resources gone, but a Town Hall still stands: produces and trains.
	_reset_fixture([_HALL])
	_resources.load_state(_zero_stockpile(), _starting_caps)
	_expect_alive("an empty stockpile alone", 1)

	# Producing and affording, but nothing can train: Lumber Yard only.
	_reset_fixture([_YARD])
	_expect_alive("no trainer alone", 1)

	# Trainer and stockpile intact, producing nothing: a Garrison trains Tier 1
	# units and has no daily_output at all.
	_reset_fixture([_GARRISON])
	_expect_alive("no production alone", 1)

	# Two of three: nothing produces and nothing trains, but the stockpile
	# can still buy a building — the player can rebuild.
	_reset_fixture([_TOWER])
	_expect_alive("no production and no trainer, stockpile intact", 2)

	# Two of three: nothing to spend and nothing to train with, but the
	# Lumber Yard is still cutting wood — the stockpile refills.
	_reset_fixture([_YARD])
	_resources.load_state(_zero_stockpile(), _starting_caps)
	_expect_alive("empty stockpile and no trainer, production intact", 2)


## The other direction: it must actually be possible to lose.
func _check_all_three_conditions_end_the_campaign() -> void:
	_reset_fixture([_HALL])           ## Arms the monitor — the colony has to have existed.
	_monitor.evaluate_now()
	_reset_fixture([_TOWER], false)   ## A Watchtower produces nothing and trains nothing.
	_resources.load_state(_zero_stockpile(), _starting_caps)
	_monitor.evaluate_now()
	var result := _monitor.evaluate()
	print("all three conditions: defeated=%s reasons=%s" % [_monitor.is_defeated(), result["reasons"]])
	if not _monitor.is_defeated():
		_failures.append("no stockpile, no production and no trainer did NOT end the campaign — P4 is still aspirational")
	if _lost_signals.size() != 1:
		_failures.append("campaign_lost fired %d times on the losing transition, expected exactly 1" % _lost_signals.size())
	elif (_lost_signals[0] as Array).size() != 3:
		_failures.append("campaign_lost carried %d reasons, expected all 3 — the player is owed why" % (_lost_signals[0] as Array).size())


## A defeat that un-ends is not a defeat. Two separate things have to hold and
## an earlier version of this check only tested the first, which mutation
## testing caught: deleting evaluate_now()'s `if _defeated: return` guard left
## every check here passing, because a REBUILT colony satisfies no conditions
## and so would not have re-emitted anyway. The guard's actual job is the
## second half below — the losing state re-entered.
func _check_the_verdict_is_latched() -> void:
	_reset_fixture([_HALL, _YARD], false)  ## Full colony back, WITHOUT rebuilding the monitor.
	_monitor.evaluate_now()
	print("after rebuilding post-defeat: defeated=%s" % _monitor.is_defeated())
	if not _monitor.is_defeated():
		_failures.append("rebuilding after the campaign ended un-ended it — the verdict is not latched")
	if not _lost_signals.is_empty():
		_failures.append("campaign_lost re-emitted %d times after the campaign had already ended" % _lost_signals.size())

	# Back into the losing state. A campaign already over must not end twice —
	# a second campaign_lost is a second game-over for the same run.
	_reset_fixture([_TOWER], false)
	_resources.load_state(_zero_stockpile(), _starting_caps)
	_monitor.evaluate_now()
	print("re-entering the losing state post-defeat: lost signals=%d" % _lost_signals.size())
	if not _lost_signals.is_empty():
		_failures.append("campaign_lost fired again (%d times) on re-entering the losing state — an ended campaign must not end twice" % _lost_signals.size())
	if not _risk_signals.is_empty():
		_failures.append("defeat_risk_changed fired %d times after the campaign had ended — there is no risk left to warn about" % _risk_signals.size())


## P4: "clear warning before the point of no return." The warning has to be a
## separate, earlier event than the loss — one that arrives while the player
## can still act on it.
func _check_the_warning_arrives_before_the_loss() -> void:
	_reset_fixture([_TOWER])  ## Two conditions: no production, no trainer. Stockpile intact.
	_monitor.evaluate_now()
	var warned_at_two := _risk_signals.size()
	var lost_at_two := _lost_signals.size()
	print("two conditions: risk signals=%d, lost signals=%d" % [warned_at_two, lost_at_two])
	if warned_at_two != 1:
		_failures.append("two conditions held and defeat_risk_changed fired %d times, expected 1 — the player gets no warning" % warned_at_two)
	elif not bool((_risk_signals[0] as Array)[0]):
		_failures.append("the risk signal fired with is_at_risk=false while two conditions held")
	if lost_at_two != 0:
		_failures.append("the campaign ended on two conditions — one thread left must not be a loss")

	# And the warning clears when the player recovers.
	_risk_signals.clear()
	_reset_fixture([_HALL, _YARD], false)
	_monitor.evaluate_now()
	if _monitor.is_at_risk():
		_failures.append("recovering to a full colony left the monitor still reporting at risk")
	if _risk_signals.size() != 1 or bool((_risk_signals[0] as Array)[0]):
		_failures.append("recovery did not emit a single defeat_risk_changed(false) — the warning never clears")


## Asserts the campaign is still running, and that exactly `expected` of the
## three conditions hold — so a check cannot pass because the fixture failed
## to produce the situation it was describing.
func _expect_alive(label: String, expected: int) -> void:
	_monitor.evaluate_now()
	var result := _monitor.evaluate()
	var satisfied := 0
	for key in ["no_affordable_expansion", "no_production", "no_trainer"]:
		if bool(result[key]):
			satisfied += 1
	print("%s: %d/3 conditions, defeated=%s" % [label, satisfied, _monitor.is_defeated()])
	if satisfied != expected:
		_failures.append("%s: expected %d of 3 conditions to hold, got %d (%s) — the fixture is not testing what it says" % [
			label, expected, satisfied, ", ".join(result["reasons"])])
	if _monitor.is_defeated():
		_failures.append("%s ended the campaign — 7.6 requires all three at once" % label)


## Rebuilds the fixture's buildings and stockpile. `fresh_monitor` rebuilds the
## monitor too, which is how a check gets an un-latched, un-armed one; the
## latch and warning checks pass false deliberately, because what they are
## testing is state carried ACROSS a change.
func _reset_fixture(types: Array, fresh_monitor: bool = true) -> void:
	var entries: Array[BuildingSaveEntry] = []
	var id := 1
	for building_type in types:
		entries.append(_entry(building_type, _hex_for(building_type), id))
		id += 1
	_buildings.load_save_entries(entries, 100)
	_resources.load_state(_starting_stockpile, _starting_caps)
	if fresh_monitor:
		_rebuild_monitor()
	_lost_signals.clear()
	_risk_signals.clear()


func _rebuild_monitor() -> void:
	if _monitor:
		_monitor.queue_free()
		remove_child(_monitor)
	_monitor = load("res://scenes/campaign/DefeatConditionMonitor.tscn").instantiate()
	_monitor.name = "DefeatConditionMonitor"
	_monitor.building_manager_path = NodePath("../BuildingManager")
	_monitor.resource_manager_path = NodePath("../ResourceManager")
	add_child(_monitor)
	_monitor.campaign_lost.connect(func(reasons: Array[String]) -> void: _lost_signals.append(reasons))
	_monitor.defeat_risk_changed.connect(func(is_at_risk: bool, reasons: Array[String]) -> void: _risk_signals.append([is_at_risk, reasons]))


func _hex_for(building_type: GameEnums.BuildingType) -> Vector2i:
	match building_type:
		_HALL:
			return _HALL_HEX
		_YARD:
			return _YARD_HEX
		_GARRISON:
			return _GARRISON_HEX
		_:
			return _TOWER_HEX


## Every resource at zero. Built from the live stockpile's own key set rather
## than a literal, so a new ResourceType added later is zeroed too instead of
## silently keeping its starting balance and making the affordability
## condition impossible to reach.
func _zero_stockpile() -> Dictionary:
	var zeroed: Dictionary = {}
	for resource_type in _starting_stockpile:
		zeroed[resource_type] = 0.0
	return zeroed


## current_hp is passed explicitly: BuildingSaveEntry defaults it to 0.0,
## which would restore every fixture building as an already-destroyed shell.
func _entry(building_type: GameEnums.BuildingType, coord: Vector2i, id: int) -> BuildingSaveEntry:
	var definition := BuildingCatalog.get_definition(building_type)
	return BuildingSaveEntry.new(building_type, coord, id, Vector2.ZERO, definition.population_provided, definition.get_max_hp())


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		cells[coord] = HexCell.new(coord)
	return cells
