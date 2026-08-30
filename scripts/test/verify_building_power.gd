extends Node

## Proves design_doc.md §2.1's "Going dark: buildings can be switched off"
## (D11) does the four things the spec names — no production, no upkeep, no
## noise, no light — and that the restart delay is a real cost rather than a
## label. Run (as a real scene, not `-s`: BuildingManager connects to the
## TickManager autoload, which script mode cannot resolve):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_building_power.tscn
##
## ## What each check is guarding against
##
## The feature is a third "this building is not operating" flag next to
## is_ruined and is_under_construction, so the failures worth catching are
## the ones where the three disagree:
##
## * A switched-off building that keeps producing, keeps paying upkeep, or
##   keeps making noise is the whole feature silently not working. Checks 2
##   and 5.
## * The occupants of a mothballed tenement still eat. Folding the power
##   skip into BuildingSustenanceController's existing ruin/construction skip
##   would let a player erase the colony's whole Food demand by switching off
##   housing — the building's own upkeep must stop, its residents' rations
##   must not. Check 3.
## * The Energy/Population ledger is the one place going dark can MINT
##   capacity rather than trade it. power_down() refunds the allocation, the
##   restart takes it back at completion, and demolish() must not top up an
##   allocation that was already released. Checks 4, 9 and 10.
## * "Restarting costs a delay proportional to building tier" is the only
##   thing stopping the switch being spammed on sight, so the delay has to be
##   tier-shaped AND the building has to stay dark for all of it. Checks 1
##   and 6.
## * A flag with no save field silently resurrects a dark foundry as a
##   running one. Check 8.
## * Ruin and going dark overlap in the ordinary case, not an exotic one —
##   switching off is the emergency move against an approaching horde, and
##   the horde then wrecks the building. A second capacity refund, or a
##   restart that completes on rubble, both mint capacity. Checks 11 and 12.
## * An ordered restart that cannot be stopped defeats the mechanic at the
##   one moment it matters. Check 13.
##
## Fixture rather than the real map, same reasoning verify_infestation.gd and
## verify_gates.gd both record: HexMapGenerator builds the whole UK+Ireland
## corridor on every run, which is minutes per launch.
##
## Buildings are registered through BuildingManager.load_save_entries() — the
## same public entry point SaveLoadManager uses — rather than
## place_building(), because placement legality is resolved at sub-hex
## resolution against baked raster data (SubHexTerrainQuery) that a hand-built
## fixture cell cannot control. The consequence, stated so no check quietly
## depends on the wrong thing: load_save_entries() does not settle capacity
## (nor does seed_starting_buildings()), so the Energy/Population pool does
## not start out reflecting these buildings' draw. Every capacity assertion
## below is therefore a DELTA across one action, never an absolute balance,
## and _reset_fixture() restores the ledger between checks so one check's
## drift cannot make the next one's affordability test lie.

const _FIXTURE_RADIUS: int = 3
const _HOME := Vector2i.ZERO
const _MINE_HEX := Vector2i(1, 0)      ## Coal Mine — the noise, production and capacity subject.
const _HOUSE_HEX := Vector2i(2, 0)     ## Wooden Houses — the "the residents still eat" subject.
const _TOWER_HEX := Vector2i(0, 1)     ## Watchtower — the lit_at_night subject.
const _EPSILON: float = 0.001

## Coal Mine (tier 1, noisy, real Energy/Population draw), Wooden Houses
## (tier 0, the only fixture member that houses anyone) and Watchtower
## (tier 0, lit_at_night, silent). Every number they carry is read from the
## catalog at runtime rather than restated here — a balance pass that moves
## them must not turn this into a false failure.
const _MINE := GameEnums.BuildingType.COAL_MINE
const _HOUSE := GameEnums.BuildingType.WOODEN_HOUSES
const _TOWER := GameEnums.BuildingType.WATCHTOWER

var _map: HexGridMap
var _resources: ResourceManager
var _buildings: BuildingManager
var _noise: NoiseManager
var _starting_stockpile: Dictionary = {}
var _starting_caps: Dictionary = {}
var _failures: Array[String] = []
var _rejections: Array[String] = []


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

	# Wired BEFORE add_child so _ready() resolves them, same ordering
	# verify_infestation.gd and verify_resident_defense.gd both record. No
	# tech_manager_path or infestation_manager_path: unset means neither the
	# tier gate nor §2.1's band gate applies, which is what makes a fixture
	# with no research and no seeded infestation usable at all.
	# BuildingManager._ready() also calls seed_starting_buildings(); this
	# fixture's cells are not settlements, so it finds no target and places
	# nothing. The assertion below is the guard rather than the comment.
	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = NodePath("../HexGridMap")
	_buildings.resource_manager_path = NodePath("../ResourceManager")
	add_child(_buildings)
	if not _buildings.get_all_buildings().is_empty():
		_failures.append("the fixture seeded %d starting buildings — every tally below would be off by them" % _buildings.get_all_buildings().size())

	_noise = load("res://scenes/world/NoiseManager.tscn").instantiate()
	_noise.name = "NoiseManager"
	_noise.hex_grid_map_path = NodePath("../HexGridMap")
	_noise.building_manager_path = NodePath("../BuildingManager")
	add_child(_noise)

	_buildings.building_restart_rejected.connect(_on_rejected)
	_buildings.power_down_rejected.connect(_on_rejected)

	get_tree().quit(_run())


func _run() -> int:
	_check_restart_delay_is_tier_shaped()
	_check_production_and_upkeep_stop()
	_check_the_residents_still_eat()
	_check_capacity_is_released_and_retaken()
	_check_noise_and_light_stop()
	_check_the_building_stays_dark_for_the_whole_delay()
	_check_what_cannot_be_switched_off()
	_check_save_round_trip()
	_check_demolishing_a_dark_building_mints_nothing()
	_check_a_restart_the_grid_cannot_carry_is_cancelled()
	_check_ruining_a_dark_building_mints_nothing()
	_check_a_ruin_does_not_restart_itself()
	_check_a_restart_can_be_cancelled()

	print()
	if _failures.is_empty():
		print("All going-dark checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## D11: "Restarting costs a delay proportional to building tier." Tier is the
## stated axis, so the delay must be monotonic in tier and must actually
## differ across the tree — a formula returning a constant would satisfy
## "there is a delay" and nothing the decision was made for.
func _check_restart_delay_is_tier_shaped() -> void:
	var previous := -1
	for tier in range(0, 6):
		var definition := BuildingDefinition.new()
		definition.tier = tier
		var days := _buildings.get_restart_days_for(definition)
		print("tier %d restart: %d day%s" % [tier, days, "" if days == 1 else "s"])
		if days < 1:
			_failures.append("tier %d restarts in %d days — a free restart makes going dark a no-brainer (D11)" % [tier, days])
		elif days <= previous:
			_failures.append("tier %d restarts in %d days, no slower than tier %d's %d — the delay is not proportional to tier" % [tier, days, tier - 1, previous])
		previous = days


## "An off building produces nothing, consumes no upkeep." Measured through
## get_projected_daily_flow(), which is the same arithmetic apply_day() banks
## (BuildingSustenanceController's own doc comment), not a second model of it.
func _check_production_and_upkeep_stop() -> void:
	_reset_fixture()
	var definition := BuildingCatalog.get_definition(_MINE)
	var before := _buildings.get_projected_daily_flow()
	var coal_before := float(before["produced"].get(GameEnums.ResourceType.COAL, 0.0))
	var food_before := float(before["consumed"].get(GameEnums.ResourceType.FOOD, 0.0))
	if coal_before <= 0.0:
		_failures.append("the Coal Mine produced no Coal before being switched off — the fixture is not measuring anything")

	if not _buildings.power_down_building(_building_at(_MINE_HEX)):
		_failures.append("a running Coal Mine refused to switch off: %s" % _buildings.get_power_down_error(_building_at(_MINE_HEX)))
	var after := _buildings.get_projected_daily_flow()
	var coal_after := float(after["produced"].get(GameEnums.ResourceType.COAL, 0.0))
	var food_after := float(after["consumed"].get(GameEnums.ResourceType.FOOD, 0.0))
	print("Coal Mine: Coal/day %.1f -> %.1f, colony Food/day %.1f -> %.1f" % [coal_before, coal_after, food_before, food_after])

	if coal_after > _EPSILON:
		_failures.append("a switched-off Coal Mine still produced %.1f Coal/day" % coal_after)
	var mine_food := float(definition.daily_upkeep.get(GameEnums.ResourceType.FOOD, 0.0))
	if absf((food_before - food_after) - mine_food) > _EPSILON:
		_failures.append("switching the Coal Mine off changed Food upkeep by %.1f, not by its own %.1f/day" % [food_before - food_after, mine_food])


## The half that must NOT change. A mothballed house's residents still live
## there, so the population share of the Food bill stands even though the
## building's own upkeep line stops. The discriminating number is the delta:
## the building's own Food upkeep alone means the residents survived the
## skip, that PLUS their rations means they were deleted with it.
func _check_the_residents_still_eat() -> void:
	_reset_fixture()
	var house := _building_at(_HOUSE_HEX)
	var housed := house.current_population
	if housed <= 0:
		_failures.append("the fixture's Wooden Houses shelter nobody — the Food check below proves nothing")
		return
	var own_upkeep := float(house.definition.daily_upkeep.get(GameEnums.ResourceType.FOOD, 0.0))
	var rations := float(housed) * BuildingManager.FOOD_PER_POPULATION

	var before := float(_buildings.get_projected_daily_flow()["consumed"].get(GameEnums.ResourceType.FOOD, 0.0))
	_buildings.power_down_building(house)
	var after := float(_buildings.get_projected_daily_flow()["consumed"].get(GameEnums.ResourceType.FOOD, 0.0))
	print("Wooden Houses (%d housed): colony Food/day %.1f -> %.1f; own upkeep %.1f, residents' rations %.1f" % [housed, before, after, own_upkeep, rations])

	if absf((before - after) - own_upkeep) > _EPSILON:
		if absf((before - after) - (own_upkeep + rations)) <= _EPSILON:
			_failures.append("switching housing off also deleted its %d residents' %.1f Food/day — a mothballed house's residents still eat (design_doc.md §2.1)" % [housed, rations])
		else:
			_failures.append("switching housing off changed the Food bill by %.1f, not by its own %.1f upkeep" % [before - after, own_upkeep])
	if house.current_population != housed:
		_failures.append("switching a house off changed its occupancy from %d to %d — only ruin evicts anyone" % [housed, house.current_population])


## The Energy/Population ledger. power_down() refunds exactly the draw the
## building was holding; the restart takes exactly that back, and takes it at
## COMPLETION rather than when ordered (BuildingPowerController.restart()'s
## own doc comment explains why that ordering is load-bearing).
func _check_capacity_is_released_and_retaken() -> void:
	_reset_fixture()
	var definition := BuildingCatalog.get_definition(_MINE)
	var energy_cost := float(definition.daily_upkeep.get(GameEnums.ResourceType.ENERGY, 0.0))
	var population_cost := float(definition.daily_upkeep.get(GameEnums.ResourceType.POPULATION, 0.0))
	if energy_cost <= 0.0 or population_cost <= 0.0:
		_failures.append("the Coal Mine draws no Energy/Population capacity — this check measures nothing")
		return

	var energy_before := _resources.get_amount(GameEnums.ResourceType.ENERGY)
	var population_before := _resources.get_amount(GameEnums.ResourceType.POPULATION)
	_buildings.power_down_building(_building_at(_MINE_HEX))
	var energy_off := _resources.get_amount(GameEnums.ResourceType.ENERGY)
	var population_off := _resources.get_amount(GameEnums.ResourceType.POPULATION)
	print("power down: Energy %.1f -> %.1f (want +%.1f), Population %.1f -> %.1f (want +%.1f)" % [energy_before, energy_off, energy_cost, population_before, population_off, population_cost])
	if absf((energy_off - energy_before) - energy_cost) > _EPSILON:
		_failures.append("switching the Coal Mine off released %.1f Energy, not its %.1f draw" % [energy_off - energy_before, energy_cost])
	if absf((population_off - population_before) - population_cost) > _EPSILON:
		_failures.append("switching the Coal Mine off released %.1f Population, not its %.1f draw" % [population_off - population_before, population_cost])

	var mine := _building_at(_MINE_HEX)
	if not _buildings.restart_building(mine):
		_failures.append("a restart the grid can afford was refused: %s" % _buildings.get_restart_error(mine))
		return
	if absf(_resources.get_amount(GameEnums.ResourceType.ENERGY) - energy_off) > _EPSILON:
		_failures.append("ordering the restart moved the Energy pool — the draw is taken when the restart COMPLETES, which is what lets demolish() read 'still holds capacity' off the flag alone")

	_run_days(_buildings.get_restart_days_for(definition))
	var energy_back := _resources.get_amount(GameEnums.ResourceType.ENERGY)
	var population_back := _resources.get_amount(GameEnums.ResourceType.POPULATION)
	print("restart complete: Energy %.1f, Population %.1f (want %.1f / %.1f)" % [energy_back, population_back, energy_before, population_before])
	if absf(energy_back - energy_before) > _EPSILON or absf(population_back - population_before) > _EPSILON:
		_failures.append("a full off/on cycle left the ledger at Energy %.1f / Population %.1f instead of its starting %.1f / %.1f" % [energy_back, population_back, energy_before, population_before])


## "Emits no noise and no light." The Coal Mine half is phase-independent
## (noise_output is doubled at night, never zeroed), so it is a real
## assertion whenever this runs. The Watchtower half IS the light half and
## only bites at night — NoiseManager's lit_at_night term is night-only and
## no public API can force the phase — so it is written as an exact expected
## delta computed from the phase this run actually observed, rather than as
## an assumption about which phase that is. By day it is vacuous; it can
## never fail falsely, and at night it is the real thing.
func _check_noise_and_light_stop() -> void:
	_reset_fixture()
	var is_night := TimeCycleManager.is_night()
	var mine_definition := BuildingCatalog.get_definition(_MINE)
	var expected_mine := float(mine_definition.noise_output) * (NoiseManager.NIGHT_NOISE_MULTIPLIER if is_night else 1.0)
	var noise_before := _noise.get_noise_at(_MINE_HEX)
	if noise_before <= 0.0:
		_failures.append("the Coal Mine's own hex was silent before it was switched off — NoiseManager never saw the fixture")
	_buildings.power_down_building(_building_at(_MINE_HEX))
	var noise_after := _noise.get_noise_at(_MINE_HEX)
	print("phase=%s  Coal Mine hex noise %.1f -> %.1f (want -%.1f)" % ["night" if is_night else "day", noise_before, noise_after, expected_mine])
	if absf((noise_before - noise_after) - expected_mine) > _EPSILON:
		_failures.append("switching the Coal Mine off changed its hex's noise by %.1f, not by its own %.1f contribution" % [noise_before - noise_after, expected_mine])

	# The mine is already off, so whatever is left on the Watchtower's hex is
	# the tower's own light term and nothing else.
	var expected_light := NoiseManager.NIGHT_LIGHT_ATTRACTION if is_night else 0.0
	var tower_before := _noise.get_noise_at(_TOWER_HEX)
	_buildings.power_down_building(_building_at(_TOWER_HEX))
	var tower_after := _noise.get_noise_at(_TOWER_HEX)
	print("Watchtower hex attraction %.1f -> %.1f (want -%.1f; the light term is night-only)" % [tower_before, tower_after, expected_light])
	if absf((tower_before - tower_after) - expected_light) > _EPSILON:
		_failures.append("switching the Watchtower off changed its hex's attraction by %.1f, not by the %.1f a lit source contributes at this phase" % [tower_before - tower_after, expected_light])
	if tower_after > _EPSILON:
		_failures.append("a hex holding nothing but switched-off buildings still radiates %.1f attraction" % tower_after)


## The delay is the whole cost, so the building has to stay dark for all of
## it and come back on the last day — not on the first, and not a day late.
func _check_the_building_stays_dark_for_the_whole_delay() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var days := _buildings.get_restart_days_for(mine.definition)
	if days < 2:
		_failures.append("the Coal Mine restarts in %d day, so 'stays dark for the whole delay' has no interior to check — pick a higher-tier fixture building" % days)
		return
	_buildings.power_down_building(mine)
	_buildings.restart_building(mine)
	for day in range(1, days):
		_run_days(1)
		print("restart day %d/%d: powered_down=%s remaining=%d" % [day, days, mine.is_powered_down, _buildings.get_restart_days_remaining(mine)])
		if not mine.is_powered_down:
			_failures.append("the Coal Mine came back online on day %d of a %d-day restart" % [day, days])
		if mine.is_running():
			_failures.append("a mid-restart Coal Mine reported is_running() — it would produce and make noise %d days early" % [days - day])
	_run_days(1)
	print("restart day %d/%d: powered_down=%s" % [days, days, mine.is_powered_down])
	if mine.is_powered_down or not mine.is_running():
		_failures.append("the Coal Mine was still dark after its full %d-day restart" % days)
	if _buildings.get_restart_days_remaining(mine) != 0:
		_failures.append("a completed restart left %d days on the queue" % _buildings.get_restart_days_remaining(mine))


## Every refusal, each for its own reason. A silent accept here is worse than
## a rejection: a switched-off Town Hall zeroes the colony's whole capacity
## pool (BuildingDefinition.always_powered), and a ruin or a construction
## site has nothing running to switch off in the first place.
func _check_what_cannot_be_switched_off() -> void:
	_reset_fixture()
	var hall_definition := BuildingCatalog.get_definition(GameEnums.BuildingType.TOWN_HALL)
	var with_hall := _fixture_entries()
	with_hall.append(BuildingSaveEntry.new(GameEnums.BuildingType.TOWN_HALL, _HOME, 90, Vector2.ZERO, hall_definition.population_provided, hall_definition.get_max_hp()))
	_buildings.load_save_entries(with_hall, 100)

	var town_hall := _building_at(_HOME)
	if _buildings.can_power_down_building(town_hall):
		_failures.append("the Town Hall can be switched off — its +100 Population/+20 Energy grant seeds the whole capacity pool (BuildingDefinition.always_powered)")
	if _buildings.power_down_building(town_hall):
		_failures.append("power_down_building() switched the Town Hall off despite always_powered")

	var mine := _building_at(_MINE_HEX)
	_buildings.damage_building(mine, mine.definition.get_max_hp() * 2.0)
	if not mine.is_ruined:
		_failures.append("the fixture failed to ruin the Coal Mine — the ruin refusal below proves nothing")
	elif _buildings.can_power_down_building(mine):
		_failures.append("a ruined Coal Mine can be switched off — there is nothing left running")

	_reset_fixture()
	mine = _building_at(_MINE_HEX)
	_buildings.power_down_building(mine)
	if _buildings.power_down_building(mine):
		_failures.append("an already-dark Coal Mine was switched off a second time")
	_buildings.restart_building(mine)
	if _buildings.restart_building(mine):
		_failures.append("a Coal Mine already mid-restart accepted a second restart order")
	print("refusals collected: %d" % _rejections.size())
	if _rejections.size() < 2:
		_failures.append("only %d rejection reason(s) reached power_down_rejected/building_restart_rejected — the player would see a dead button with no explanation" % _rejections.size())

	_run_days(_buildings.get_restart_days_for(mine.definition))
	if _buildings.can_restart_building(mine):
		_failures.append("a running Coal Mine accepted a restart order")


## Without both saved fields a dark foundry comes back running on load, and a
## restart half served silently completes for free — the same failure
## is_under_construction + construction_days_remaining were added together to
## prevent (BuildingSaveEntry's own doc comment). The Watchtower carries the
## off-and-staying-off half and the Coal Mine the mid-restart half, because
## only the mine's tier gives a countdown with an interior to save.
func _check_save_round_trip() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var tower := _building_at(_TOWER_HEX)
	_buildings.power_down_building(tower)
	_buildings.power_down_building(mine)
	_buildings.restart_building(mine)
	_run_days(1)
	var days_left := _buildings.get_restart_days_remaining(mine)
	if days_left <= 0:
		_failures.append("the Coal Mine's restart finished within one day — there is no mid-restart state left to round-trip")
		return

	var entries := _buildings.get_save_entries()
	_buildings.load_save_entries(entries, _buildings.get_next_id())
	var mine_back := _building_at(_MINE_HEX)
	var tower_back := _building_at(_TOWER_HEX)
	print("after round trip: Watchtower off=%s, Coal Mine off=%s restarting=%d (was %d)" % [tower_back.is_powered_down, mine_back.is_powered_down, _buildings.get_restart_days_remaining(mine_back), days_left])
	if not tower_back.is_powered_down:
		_failures.append("a switched-off Watchtower came back running after a save round trip")
	if not mine_back.is_powered_down:
		_failures.append("a mid-restart Coal Mine came back running after a save round trip")
	if _buildings.get_restart_days_remaining(mine_back) != days_left:
		_failures.append("a mid-restart building came back with %d days left instead of %d" % [_buildings.get_restart_days_remaining(mine_back), days_left])

	_run_days(days_left - 1)
	if not mine_back.is_powered_down:
		_failures.append("the restored restart finished early — the saved countdown was not honoured")
	_run_days(1)
	if mine_back.is_powered_down:
		_failures.append("the restored restart never finished: %s" % ("; ".join(_rejections) if not _rejections.is_empty() else "no reason reported"))

	_check_the_fields_survive_a_real_disk_write(entries)


## The in-memory round trip above proves BuildingManager threads the two new
## fields; it does NOT prove they reach a file. `SaveGameData` holds
## `Array[BuildingSaveEntry]` and `SaveLoadManager` writes it with
## `ResourceSaver.save()`, so a new `@export` is only persisted if Godot
## serializes nested-resource exports — which is true, and is exactly the kind
## of "true because I reasoned it" the project's own gate rules say to verify
## instead. Same writer and reader SaveLoadManager uses, including
## CACHE_MODE_IGNORE (without it ResourceLoader hands back the in-memory
## objects that were just saved, and the test would pass without a file being
## read at all).
##
## There is no save migration mechanism to exercise: `save_format_version` is
## written and never read. Both new fields default to false/0, so a save
## written before they existed loads as a running building, which is the
## pre-existing behaviour.
func _check_the_fields_survive_a_real_disk_write(entries: Array[BuildingSaveEntry]) -> void:
	var path := "user://verify_building_power_roundtrip.tres"
	var data := SaveGameData.new()
	data.buildings = entries
	var save_error := ResourceSaver.save(data, path)
	if save_error != OK:
		_failures.append("could not write the round-trip file (%d) — the disk half of the save check did not run" % save_error)
		return
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveGameData
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not reloaded:
		_failures.append("the round-trip file did not load back as SaveGameData")
		return

	var off_on_disk := 0
	var restarting_on_disk := 0
	for entry in reloaded.buildings:
		if entry.is_powered_down:
			off_on_disk += 1
		if entry.restart_days_remaining > 0:
			restarting_on_disk += 1
	var off_in_memory := 0
	var restarting_in_memory := 0
	for entry in entries:
		if entry.is_powered_down:
			off_in_memory += 1
		if entry.restart_days_remaining > 0:
			restarting_in_memory += 1
	print("through a real file: %d/%d switched off, %d/%d restarting" % [off_on_disk, off_in_memory, restarting_on_disk, restarting_in_memory])
	if off_on_disk != off_in_memory:
		_failures.append("%d buildings were switched off but %d came back off through a real ResourceSaver write — is_powered_down is not being persisted" % [off_in_memory, off_on_disk])
	if restarting_on_disk != restarting_in_memory:
		_failures.append("%d restarts were in flight but %d came back through a real ResourceSaver write — restart_days_remaining is not being persisted" % [restarting_in_memory, restarting_on_disk])


## demolish() tops the Energy/Population draw back up for any instance still
## holding it. A switched-off building already had that allocation refunded by
## power_down(), so a second top-up would mint capacity out of nothing — the
## same double-refund a ruin is already guarded against. Demolishing
## mid-restart also has to drop the queued job, the way remove_building()
## already drops queued construction and repair.
func _check_demolishing_a_dark_building_mints_nothing() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var energy_cost := float(mine.definition.daily_upkeep.get(GameEnums.ResourceType.ENERGY, 0.0))
	_buildings.power_down_building(mine)
	_buildings.restart_building(mine)
	var energy_off := _resources.get_amount(GameEnums.ResourceType.ENERGY)
	_buildings.demolish_building(mine)
	var energy_gone := _resources.get_amount(GameEnums.ResourceType.ENERGY)
	print("demolish while dark: Energy %.1f -> %.1f (a second refund would add %.1f)" % [energy_off, energy_gone, energy_cost])
	if energy_gone - energy_off > _EPSILON:
		_failures.append("demolishing a switched-off Coal Mine minted %.1f Energy — its draw was already refunded when it went dark" % [energy_gone - energy_off])
	if _buildings.get_restart_days_remaining(mine) != 0:
		_failures.append("demolishing a building mid-restart stranded its restart job")


## The draw is taken when the restart COMPLETES, days after it was ordered, so
## the grid may no longer be able to carry it by then.
## CapacityAllocator.apply() discards spend()'s bool, so an unaffordable
## apply() would take the grant without the draw; the restart is cancelled and
## reported instead.
func _check_a_restart_the_grid_cannot_carry_is_cancelled() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var energy := GameEnums.ResourceType.ENERGY
	var draw := float(mine.definition.daily_upkeep.get(energy, 0.0))
	var days := _buildings.get_restart_days_for(mine.definition)
	_buildings.power_down_building(mine)
	if not _buildings.restart_building(mine):
		_failures.append("the restart was refused before the grid was drained: %s" % _buildings.get_restart_error(mine))
		return

	# Drain Energy below the mine's own draw while the restart is in flight.
	var drain := _resources.get_amount(energy) - draw * 0.5
	if drain > 0.0:
		_resources.spend({energy: drain})
	_rejections.clear()
	_run_days(days)
	print("restart under a drained grid: Energy %.1f (draw %.1f), still dark=%s, rejections=%d" % [_resources.get_amount(energy), draw, mine.is_powered_down, _rejections.size()])
	if not mine.is_powered_down:
		_failures.append("a restart completed on a grid that could not carry its %.1f Energy draw" % draw)
	if _rejections.is_empty():
		_failures.append("the cancelled restart reported nothing — the player waited %d days for silence" % days)
	if _buildings.get_restart_days_remaining(mine) != 0:
		_failures.append("a cancelled restart stayed on the queue as an invisible job")


## The mirror of the demolish check, and the sequence the mechanic makes
## ORDINARY rather than exotic: going dark is the emergency move against an
## approaching horde, so "switched off, then wrecked by that horde" is the
## expected path. damage()'s ruin branch refunds the Energy/Population
## allocation; doing that to a building whose allocation power_down() already
## released mints capacity out of nothing.
func _check_ruining_a_dark_building_mints_nothing() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var energy := GameEnums.ResourceType.ENERGY
	var population := GameEnums.ResourceType.POPULATION
	var draw := float(mine.definition.daily_upkeep.get(energy, 0.0))
	_buildings.power_down_building(mine)
	var energy_off := _resources.get_amount(energy)
	var population_off := _resources.get_amount(population)

	_buildings.damage_building(mine, mine.definition.get_max_hp() * 2.0)
	var energy_ruined := _resources.get_amount(energy)
	var population_ruined := _resources.get_amount(population)
	print("ruin while dark: Energy %.1f -> %.1f, Population %.1f -> %.1f (a second refund would add %.1f Energy)" % [energy_off, energy_ruined, population_off, population_ruined, draw])
	if not mine.is_ruined:
		_failures.append("the fixture failed to ruin the switched-off Coal Mine — this check proves nothing")
		return
	if absf(energy_ruined - energy_off) > _EPSILON or absf(population_ruined - population_off) > _EPSILON:
		_failures.append("ruining a switched-off Coal Mine moved the capacity ledger by Energy %.1f / Population %.1f — its allocation was already released when it went dark" % [energy_ruined - energy_off, population_ruined - population_off])

	# Rubble is not "switched off"; leaving the flag set would make a later
	# repair come back holding an allocation the flag says it does not hold,
	# and would let the UI offer a Restart that applies it a second time.
	if mine.is_powered_down:
		_failures.append("a ruined building is still flagged switched-off — repair would bring it back dark, holding capacity D53's invariant says it does not hold")

	# And the repair path has to land somewhere consistent: a rebuilt building
	# is a running building.
	_buildings.repair_building(mine)
	_run_days(4)
	print("after repair: ruined=%s powered_down=%s running=%s" % [mine.is_ruined, mine.is_powered_down, mine.is_running()])
	if mine.is_ruined or mine.is_powered_down or not mine.is_running():
		_failures.append("a Coal Mine switched off, ruined and then repaired came back ruined=%s off=%s instead of simply running" % [mine.is_ruined, mine.is_powered_down])


## A restart in flight when the building is destroyed must not complete. It
## would draw the full allocation for a building that no longer stands and
## clear the off-flag on a ruin, and demolish() would then refuse to refund
## what it is actually holding.
func _check_a_ruin_does_not_restart_itself() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var energy := GameEnums.ResourceType.ENERGY
	var days := _buildings.get_restart_days_for(mine.definition)
	_buildings.power_down_building(mine)
	_buildings.restart_building(mine)
	_run_days(1)
	_buildings.damage_building(mine, mine.definition.get_max_hp() * 2.0)
	var energy_ruined := _resources.get_amount(energy)
	var remaining := _buildings.get_restart_days_remaining(mine)
	_run_days(days + 1)
	print("ruined mid-restart: job left %d days, Energy %.1f -> %.1f after the countdown would have ended" % [remaining, energy_ruined, _resources.get_amount(energy)])
	if remaining != 0:
		_failures.append("ruining a building mid-restart left %d days queued — the countdown would complete on a ruin" % remaining)
	if absf(_resources.get_amount(energy) - energy_ruined) > _EPSILON:
		_failures.append("a ruin drew %.1f Energy when its abandoned restart came due" % [_resources.get_amount(energy) - energy_ruined])
	if not mine.is_ruined:
		_failures.append("the ruin repaired itself")


## The whole point of going dark is answering a horde that is already walking
## toward the noise. If an ordered restart cannot be stopped, a horde arriving
## partway through the countdown is met by a building that lights up on
## schedule — so "switch off" on an already-dark, restarting building cancels
## the restart rather than being refused.
func _check_a_restart_can_be_cancelled() -> void:
	_reset_fixture()
	var mine := _building_at(_MINE_HEX)
	var energy := GameEnums.ResourceType.ENERGY
	var days := _buildings.get_restart_days_for(mine.definition)
	if days < 2:
		_failures.append("the Coal Mine restarts in %d day, so there is no countdown to cancel partway through" % days)
		return
	_buildings.power_down_building(mine)
	_buildings.restart_building(mine)
	_run_days(1)
	if not _buildings.is_building_restarting(mine):
		_failures.append("the restart was not in flight — this check proves nothing")
		return

	var energy_before := _resources.get_amount(energy)
	if not _buildings.power_down_building(mine):
		_failures.append("a restart in flight could not be cancelled: %s" % _buildings.get_power_down_error(mine))
		return
	print("cancelled mid-restart: remaining %d, still dark=%s, Energy %.1f -> %.1f" % [_buildings.get_restart_days_remaining(mine), mine.is_powered_down, energy_before, _resources.get_amount(energy)])
	if _buildings.get_restart_days_remaining(mine) != 0:
		_failures.append("cancelling left %d days on the queue" % _buildings.get_restart_days_remaining(mine))
	if not mine.is_powered_down:
		_failures.append("cancelling a restart brought the building online instead of leaving it dark")
	if absf(_resources.get_amount(energy) - energy_before) > _EPSILON:
		_failures.append("cancelling a restart moved the Energy pool by %.1f — restart() took no capacity, so cancelling has nothing to release" % [_resources.get_amount(energy) - energy_before])

	_run_days(days + 1)
	if not mine.is_powered_down:
		_failures.append("a cancelled restart brought the building back online anyway")


func _on_rejected(_instance: BuildingInstance, reason: String) -> void:
	_rejections.append(reason)


## Re-registers the fixture's three buildings and restores the resource ledger
## to its boot state. load_save_entries() clears every existing instance
## first, and load_state() is the same public restore path SaveLoadManager
## uses — without the ledger reset, one check's capacity refund would decide
## whether the next check's restart is affordable.
func _reset_fixture() -> void:
	_buildings.load_save_entries(_fixture_entries(), 100)
	_resources.load_state(_starting_stockpile, _starting_caps)
	_rejections.clear()


func _fixture_entries() -> Array[BuildingSaveEntry]:
	var entries: Array[BuildingSaveEntry] = []
	entries.append(_entry(_MINE, _MINE_HEX, 1))
	entries.append(_entry(_HOUSE, _HOUSE_HEX, 2))
	entries.append(_entry(_TOWER, _TOWER_HEX, 3))
	return entries


## current_hp is passed explicitly: BuildingSaveEntry defaults it to 0.0,
## which would restore every fixture building as an already-destroyed shell.
func _entry(building_type: GameEnums.BuildingType, coord: Vector2i, id: int) -> BuildingSaveEntry:
	var definition := BuildingCatalog.get_definition(building_type)
	return BuildingSaveEntry.new(building_type, coord, id, Vector2.ZERO, definition.population_provided, definition.get_max_hp())


func _building_at(coord: Vector2i) -> BuildingInstance:
	var here := _buildings.get_buildings_at(coord)
	return here[0] if not here.is_empty() else null


func _run_days(days: int) -> void:
	for _i in range(days):
		_buildings.run_daily_tick()


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		cells[coord] = HexCell.new(coord)
	return cells
