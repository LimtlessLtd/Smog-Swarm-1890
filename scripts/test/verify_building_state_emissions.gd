extends Node

## Proves what a building's own instance state gates in what it EMITS: a
## RUIN emits nothing, a CONSTRUCTION SITE emits what a work party emits and
## not what the finished building would, and every one of those transitions
## lands at the moment it happens rather than whenever something unrelated
## next rebuilds the field.
##
## Three systems read the same two definition fields (`vision_radius`,
## `lit_at_night`) off the same instance, so they are checked together rather
## than one per file: FogOfWarManager's visible set, LogisticsNetwork's Zone
## of Control coverage (which fog reads verbatim as a second vision source),
## and NoiseManager's attraction field.
##
## Run (as a real scene, not `-s`: every manager here reads the
## TimeCycleManager/TickManager autoloads, which script mode cannot resolve):
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_building_state_emissions.tscn
##
## ## What each check is guarding against
##
## Until 2026-08-30 `FogOfWarManager._compute_visible_set()` read
## `definition.vision_radius` off every instance in BuildingManager's records
## with no gate but the going-dark one, and connected none of the three
## signals that change the answer:
##
## * A burnt-out Search Light lit the map exactly as the intact one did —
##   including the `lit_at_night` bonus for a lamp that is no longer burning,
##   while NoiseManager, reading the same two fields one skip earlier, had
##   already stopped it attracting anything. Checks 2 and 4.
## * A construction site saw at the finished building's radius: scaffolding
##   with a Watchtower's lookout, and a lamp attracting hordes to a lamp that
##   was not installed yet. Check 3.
## * A gate nothing recomputes against is invisible. Fog rebuilt on
##   placed/removed/powered_down/powered_up and NoiseManager on those plus
##   ruin, so a destroyed tower's ring stayed lit and a repaired foundry
##   stayed silent until a day-phase flip — up to half an in-game day, and
##   forever while paused. Checks 4, 6 and 7 make the transitions the subject.
## * Vision has that second source. LogisticsNetwork's ruin gate was already
##   right ("rubble, not a functioning civic seat") and its trigger was
##   missing too, so gating fog's own loop alone would have left a destroyed
##   Watchtower lighting its hex and its neighbours through ZoC. Check 5.
##
## KNOWN GAP, stated rather than silently relied on: ZoC is gated on ruin but
## NOT on construction, so in the real game (where fog IS wired to
## LogisticsNetwork) a Watchtower or Search Light under construction still
## reveals a one-hex ring through its Military aura. Check 3 measures fog's
## own building loop with `logistics_network_path` left unset, so it cannot
## and does not claim otherwise. Filed in `backlog.md`.
##
## Fixture rather than the real map, and buildings registered through
## `load_save_entries()` rather than `place_building()`, for the reasons
## `verify_building_power.gd` records at length. Three constraints of its own:
##
## * Fixture cells are URBAN, not `HexCell`'s default MOORLAND, whose
##   `get_vision_penalty()` of 1 would silently shrink every radius asserted
##   below. Check 1 measures the penalty rather than trusting the biome table
##   to stay where it is.
## * Each scenario gets a FRESH FogOfWarManager. `recompute()` only ever
##   PROMOTES to VISIBLE synchronously — a hex losing its last source counts
##   down `LOST_VISION_GRACE_SECONDS` in `_process()` first — so a manager
##   carried across a fixture reset would spend three seconds still reporting
##   the previous scenario. Check 4 waits that grace out on purpose, because
##   "the ring goes dark when the tower falls" is exactly the claim.
##   NoiseManager needs none of this: it rebuilds its whole field per signal.
## * The clock is pinned, through TickManager's own save seam, to NIGHT at a
##   RUNNING speed. Night because every `lit_at_night` term this file exists
##   to check is night-only and would otherwise be vacuous by day; running
##   because that fog grace drains in `_process(delta)`, which
##   `Engine.time_scale` scales, so at speed 0 check 4 would wait forever.
##   Expectations are still derived from `TimeCycleManager.is_night()` at the
##   moment each check runs, so a phase flip mid-run weakens this file rather
##   than failing it falsely.

const _FIXTURE_RADIUS: int = 4  ## One ring wider than the widest radius asserted below (Watchtower 2, +1 at night), so "nothing beyond the ring" has somewhere to fail.
const _TOWER_HEX := Vector2i.ZERO
const _TOWER := GameEnums.BuildingType.WATCHTOWER  ## The only fixture member: vision_radius 2, lit_at_night, and the Military ZoC role check 5 needs.
const _RUNNING_SPEED_INDEX: int = 1  ## TickManager's own default; named because check 4's grace countdown never drains at speed 0.
const _NIGHT_PROGRESS: float = 0.75  ## Mid-Night — TimeCycleManager splits the day at 0.5, so this leaves half a night of margin before the phase flips back.
const _PHASE_WAIT_MS: int = 5000  ## Real-time bound on the pinned phase actually reaching TimeCycleManager — see _await_night().
const _GRACE_WAIT_MS: int = 10000  ## Real-time bound on waiting out LOST_VISION_GRACE_SECONDS — ~16x what it needs at 5x speed, and a bound rather than a sleep so a fog manager that never demotes fails instead of hanging the gate.
const _MAX_REPAIR_DAYS: int = 10  ## Construction/repair length is clamped to 4 days; this is the runaway guard, not the expected count.
const _EPSILON: float = 0.001

var _map: HexGridMap
var _resources: ResourceManager
var _buildings: BuildingManager
var _logistics: LogisticsNetwork
var _noise: NoiseManager
var _fog: FogOfWarManager
var _failures: Array[String] = []


func _ready() -> void:
	TickManager.load_save_state({
		"current_day": 1,
		"elapsed_in_day": TickManager.DAY_LENGTH_SECONDS * _NIGHT_PROGRESS,
		"speed_index": _RUNNING_SPEED_INDEX,
	})

	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	_map.name = "HexGridMap"
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_resources = load("res://scenes/economy/ResourceManager.tscn").instantiate()
	_resources.name = "ResourceManager"
	add_child(_resources)

	# Wired BEFORE add_child so _ready() resolves them, same ordering
	# verify_building_power.gd and verify_resident_defense.gd both record.
	_buildings = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	_buildings.name = "BuildingManager"
	_buildings.hex_grid_map_path = NodePath("../HexGridMap")
	_buildings.resource_manager_path = NodePath("../ResourceManager")
	add_child(_buildings)
	if not _buildings.get_all_buildings().is_empty():
		_failures.append("the fixture seeded %d starting buildings — every hex count below would be off by them" % _buildings.get_all_buildings().size())

	# The OTHER vision source. Deliberately NOT wired into the FogOfWarManager
	# built per scenario below: check 5 measures ZoC coverage directly, and
	# feeding it into fog as well would leave every building-vision assertion
	# unable to say which of the two sources lit a hex.
	_logistics = load("res://scenes/logistics/LogisticsNetwork.tscn").instantiate()
	_logistics.name = "LogisticsNetwork"
	_logistics.hex_grid_map_path = NodePath("../HexGridMap")
	_logistics.building_manager_path = NodePath("../BuildingManager")
	add_child(_logistics)

	_noise = load("res://scenes/world/NoiseManager.tscn").instantiate()
	_noise.name = "NoiseManager"
	_noise.hex_grid_map_path = NodePath("../HexGridMap")
	_noise.building_manager_path = NodePath("../BuildingManager")
	add_child(_noise)

	get_tree().quit(await _run())


func _run() -> int:
	if not await _await_night():
		_failures.append("the clock did not reach night within %.1fs of being pinned there, so every lit_at_night term below is vacuous — TickManager.load_save_state() no longer drives TimeCycleManager's phase" % (float(_PHASE_WAIT_MS) / 1000.0))
	print("phase=%s  Watchtower vision radius %d, lamp attraction %.1f" % [
		"night" if TimeCycleManager.is_night() else "day", _expected_tower_radius(), _expected_tower_noise()])
	await _check_a_standing_watchtower_lights_its_ring()
	await _check_a_ruin_emits_nothing()
	await _check_a_construction_site_sees_its_own_hex_and_lights_no_lamp()
	await _check_the_ring_goes_dark_when_the_tower_falls()
	await _check_zoc_stops_projecting_at_the_moment_of_ruin()
	await _check_finishing_construction_lights_the_ring_and_the_lamp()
	await _check_repairing_a_ruin_lights_the_ring_and_the_lamp()

	print()
	if _failures.is_empty():
		print("All building state-emission checks passed.")
		return 0
	print("FAILED (%d):" % _failures.size())
	for failure in _failures:
		print("  " + failure)
	return 1


## The baseline every other check is measured against, and the guard on the
## fixture itself: on HexCell's default MOORLAND biome get_vision_penalty()
## would quietly cost the tower a ring, and every count below would then be
## measuring terrain rather than instance state.
func _check_a_standing_watchtower_lights_its_ring() -> void:
	if not await _arrange(false, false):
		return
	var penalty := _map.get_cell(_TOWER_HEX).get_vision_penalty()
	if penalty != 0:
		_failures.append("the fixture's own biome costs %d rings of vision — the radii below are measuring terrain, not instance state" % penalty)
	var radius := _expected_tower_radius()
	if radius < 1:
		_failures.append("an intact Watchtower is expected to see radius %d at this phase, so 'the ruin sees less' has nothing to measure" % radius)
	if _expected_tower_noise() <= 0.0:
		_failures.append("an intact Watchtower is expected to emit %.1f attraction at this phase, so every lamp assertion below is vacuous" % _expected_tower_noise())
	var visible := _visible_hexes()
	print("intact Watchtower: %d hexes visible out to distance %d (want %d out to %d), %.1f attraction on its hex" % [
		visible.size(), _furthest_visible(visible), _expected_disk_size(), radius, _noise.get_noise_at(_TOWER_HEX)])
	if visible.size() != _expected_disk_size() or _furthest_visible(visible) != radius:
		_failures.append("an intact Watchtower lit %d hexes out to distance %d, not the %d of its radius-%d disk" % [visible.size(), _furthest_visible(visible), _expected_disk_size(), radius])
	if absf(_noise.get_noise_at(_TOWER_HEX) - _expected_tower_noise()) > _EPSILON:
		_failures.append("an intact Watchtower put %.1f attraction on its own hex, not the %.1f its noise_source_db and lamp come to" % [_noise.get_noise_at(_TOWER_HEX), _expected_tower_noise()])


## Rubble is not a source of anything. LogisticsNetwork ("rubble, not a
## functioning civic seat — projects nothing"), NoiseManager and
## CombatCoordinator's Searchlight beam all already said so about the same
## instance; fog's building loop was the one that did not, and it granted a
## burnt-out lit tower the lit_at_night night BONUS on top.
func _check_a_ruin_emits_nothing() -> void:
	if not await _arrange(true, false):
		return
	var visible := _visible_hexes()
	print("ruined Watchtower: %d hexes visible (want 0), %.1f attraction on its hex (want 0.0)" % [visible.size(), _noise.get_noise_at(_TOWER_HEX)])
	if not visible.is_empty():
		_failures.append("a ruined Watchtower still lit %d hexes out to distance %d — rubble projects nothing" % [visible.size(), _furthest_visible(visible)])
	if _noise.get_noise_at(_TOWER_HEX) > _EPSILON:
		_failures.append("a ruined Watchtower still put %.1f attraction on its own hex" % _noise.get_noise_at(_TOWER_HEX))


## A construction site is a work party standing on open ground: present and
## loud, but not yet the lookout it is building and not yet the lamp. It sees
## its own hex — radius 0 still means that — and no further, and it draws
## nothing through the lit_at_night term. Its noise_source_db term is
## deliberately left alone (NoiseManager's own comment, §6's Building
## Construction at 8 tiles); the Watchtower's is 0.0, the catalogue's "not
## machinery" sentinel, so what this measures is the lamp on its own.
func _check_a_construction_site_sees_its_own_hex_and_lights_no_lamp() -> void:
	if not await _arrange(false, true):
		return
	var visible := _visible_hexes()
	var expected_noise := _construction_noise()
	print("Watchtower under construction: %d hexes visible (want 1, its own), %.1f attraction (want %.1f — machinery only, no lamp)" % [
		visible.size(), _noise.get_noise_at(_TOWER_HEX), expected_noise])
	if visible.size() != 1 or not _fog.is_visible(_TOWER_HEX):
		_failures.append("a Watchtower under construction lit %d hexes out to distance %d — a building site sees its own hex and no more" % [visible.size(), _furthest_visible(visible)])
	if absf(_noise.get_noise_at(_TOWER_HEX) - expected_noise) > _EPSILON:
		_failures.append("a Watchtower under construction put %.1f attraction on its hex, not the %.1f of its own construction racket — an unbuilt lamp is not lit" % [_noise.get_noise_at(_TOWER_HEX), expected_noise])


## The gate is only half the change: fog rebuilt on building_placed/removed
## and on the two going-dark signals, none of which a ruin emits. Without
## building_ruined the ring stays lit until a day-phase flip or a unit
## crossing a hex boundary happens to force a rebuild — the same failure
## BuildingManager's own building_powered_down doc comment names.
##
## The one check that waits out LOST_VISION_GRACE_SECONDS, because losing a
## hex's last vision source is deliberately not instant.
func _check_the_ring_goes_dark_when_the_tower_falls() -> void:
	if not await _arrange(false, false):
		return
	var lit_before := _visible_hexes().size()
	if lit_before <= 1:
		_failures.append("the intact Watchtower lit %d hexes, so its ruin had nothing to take away" % lit_before)
		return
	_ruin_the_tower()
	var went_dark := await _await_all_dark()
	var visible := _visible_hexes()
	print("Watchtower destroyed: %d hexes visible, was %d; own hex fog state %d (%d=VISIBLE, %d=EXPLORED)" % [
		visible.size(), lit_before, _fog.get_fog_state(_TOWER_HEX), GameEnums.FogState.VISIBLE, GameEnums.FogState.EXPLORED])
	if not went_dark or not visible.is_empty():
		_failures.append("%d hexes were still lit %.1fs after the Watchtower was destroyed — nothing told fog the building had become a ruin" % [visible.size(), float(_GRACE_WAIT_MS) / 1000.0])
	# EXPLORED specifically, not merely "not VISIBLE": explored ground is
	# remembered forever, so the hex must land between the two states rather
	# than at either end of them.
	if _fog.get_fog_state(_TOWER_HEX) != GameEnums.FogState.EXPLORED:
		_failures.append("the destroyed Watchtower's own hex ended at fog state %d, not EXPLORED (%d) — live sight is what a ruin costs, map memory is not" % [_fog.get_fog_state(_TOWER_HEX), GameEnums.FogState.EXPLORED])


## FogOfWarManager reads LogisticsNetwork.get_covered_hexes() verbatim as a
## vision source, so the ruin gate in fog's own loop is worth nothing on a
## Watchtower — a Military ZoC source — unless ZoC drops the ruin too. It
## always meant to; it was never told when. No grace period is involved:
## this is LogisticsNetwork's own coverage, read directly.
func _check_zoc_stops_projecting_at_the_moment_of_ruin() -> void:
	if not await _arrange(false, false):
		return
	var covered_before := _logistics.get_covered_hexes().size()
	if covered_before == 0:
		_failures.append("the intact Watchtower projected no Zone of Control at all — this check is measuring nothing")
		return
	_ruin_the_tower()
	var covered_after := _logistics.get_covered_hexes().size()
	print("Zone of Control: %d hexes covered before the Watchtower was destroyed, %d after (want 0)" % [covered_before, covered_after])
	if covered_after != 0:
		_failures.append("a destroyed Watchtower still projected Zone of Control over %d hexes — and fog reads ZoC coverage as vision, so the map stayed lit" % covered_after)


## The return path, and the cheapest possible proof that
## building_construction_completed reaches both managers: promotion to
## VISIBLE is synchronous and the noise field is rebuilt per signal, so both
## have to be right inside the same call that finishes the building, with no
## frame waited and nothing else touched.
func _check_finishing_construction_lights_the_ring_and_the_lamp() -> void:
	if not await _arrange(false, true):
		return
	var lit_before := _visible_hexes().size()
	var noise_before := _noise.get_noise_at(_TOWER_HEX)
	_buildings.run_daily_tick()
	if _tower().is_under_construction:
		_failures.append("the fixture's Watchtower was still under construction after a day's tick — this check is measuring nothing")
		return
	var visible := _visible_hexes()
	print("construction finished: %d hexes visible (was %d, want %d), %.1f attraction (was %.1f, want %.1f)" % [
		visible.size(), lit_before, _expected_disk_size(), _noise.get_noise_at(_TOWER_HEX), noise_before, _expected_tower_noise()])
	if visible.size() != _expected_disk_size():
		_failures.append("a Watchtower that finished building lit %d hexes rather than its full radius-%d disk — building_construction_completed never reached fog" % [visible.size(), _expected_tower_radius()])
	if absf(_noise.get_noise_at(_TOWER_HEX) - _expected_tower_noise()) > _EPSILON:
		_failures.append("a Watchtower that finished building put %.1f attraction on its hex, not %.1f — building_construction_completed never reached NoiseManager" % [_noise.get_noise_at(_TOWER_HEX), _expected_tower_noise()])


## Same argument for building_repaired, which is the only way out of the ruin
## state, and the one the backlog filed in its own right: a rebuilt foundry
## used to stay silent until the next phase flip. The fixture has to be
## handed Population capacity first — as verify_building_power.gd records,
## load_save_entries() settles no capacity, so the pool sits at 0 and the
## repair would be refused for a reason that has nothing to do with emissions.
func _check_repairing_a_ruin_lights_the_ring_and_the_lamp() -> void:
	if not await _arrange(true, false):
		return
	_resources.add(GameEnums.ResourceType.POPULATION, 100.0)
	_resources.add(GameEnums.ResourceType.WOOD, 500.0)
	var instance := _tower()
	if not _buildings.repair_building(instance):
		_failures.append("the fixture's ruined Watchtower refused to be repaired (%s) — the return path is untested" % _buildings.get_repair_error(instance))
		return
	var days := 0
	while instance.is_ruined and days < _MAX_REPAIR_DAYS:
		_buildings.run_daily_tick()
		days += 1
	if instance.is_ruined:
		_failures.append("the fixture's Watchtower was still a ruin after %d days of repair — the return path is untested" % days)
		return
	var visible := _visible_hexes()
	var covered := _logistics.get_covered_hexes().size()
	print("repaired after %d day(s): %d hexes visible (want %d), %.1f attraction (want %.1f), %d hexes under ZoC (want >0)" % [
		days, visible.size(), _expected_disk_size(), _noise.get_noise_at(_TOWER_HEX), _expected_tower_noise(), covered])
	if covered == 0:
		_failures.append("a repaired Watchtower projected no Zone of Control — building_repaired never reached LogisticsNetwork, the exact mirror of the ruin direction check 5 measures")
	if visible.size() != _expected_disk_size():
		_failures.append("a repaired Watchtower lit %d hexes rather than its full radius-%d disk — building_repaired never reached fog" % [visible.size(), _expected_tower_radius()])
	if absf(_noise.get_noise_at(_TOWER_HEX) - _expected_tower_noise()) > _EPSILON:
		_failures.append("a repaired Watchtower put %.1f attraction on its hex, not %.1f — building_repaired never reached NoiseManager, so a rebuilt district stays silent until the next phase flip" % [_noise.get_noise_at(_TOWER_HEX), _expected_tower_noise()])


## One Watchtower in the state this scenario needs, and a FogOfWarManager
## that has never seen anything else — see this file's own header for why the
## fog manager is rebuilt per scenario and the other managers are not.
##
## Returns false if the fixture did not register, and every caller returns on
## that. Without it, a future validation inside _register_instance() would
## leave _tower() null, the first dereference would abort the _run()
## coroutine mid-await, get_tree().quit() would never run, and the gate would
## report a 300s timeout — indistinguishable from a real hang.
func _arrange(is_ruined: bool, is_under_construction: bool) -> bool:
	_buildings.load_save_entries(_fixture_entries(is_ruined, is_under_construction), 100)
	if _fog:
		_fog.queue_free()
		_fog = null
		await get_tree().process_frame  ## Out of the tree before a second one starts pushing fog state into the same HexCellViews.
	_fog = load("res://scenes/world/FogOfWarManager.tscn").instantiate()
	_fog.name = "FogOfWarManager"
	_fog.hex_grid_map_path = NodePath("../HexGridMap")
	_fog.building_manager_path = NodePath("../BuildingManager")
	add_child(_fog)
	if _tower() == null:
		_failures.append("the fixture registered no Watchtower — load_save_entries() no longer produces an instance, and nothing below can measure anything")
		return false
	return true


func _fixture_entries(is_ruined: bool, is_under_construction: bool) -> Array[BuildingSaveEntry]:
	var definition := BuildingCatalog.get_definition(_TOWER)
	var entries: Array[BuildingSaveEntry] = []
	entries.append(BuildingSaveEntry.new(
		_TOWER, _TOWER_HEX, 1, Vector2.ZERO, 0,
		0.0 if is_ruined else definition.get_max_hp(),
		is_ruined, is_under_construction, 1, false, 0))
	return entries


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_TOWER_HEX, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		cell.biome_type = GameEnums.BiomeType.URBAN  ## get_vision_penalty() 0 — see check 1.
		cells[coord] = cell
	return cells


func _tower() -> BuildingInstance:
	var instances := _buildings.get_buildings_at(_TOWER_HEX)
	return instances[0] if not instances.is_empty() else null


func _ruin_the_tower() -> void:
	var instance := _tower()
	_buildings.damage_building(instance, instance.definition.get_max_hp() * 2.0)
	if not instance.is_ruined:
		_failures.append("the fixture's Watchtower survived twice its own max HP — nothing after this is measuring a ruin")


## Every fixture hex the current FogOfWarManager calls VISIBLE.
func _visible_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in HexCoord.hex_disk(_TOWER_HEX, _FIXTURE_RADIUS):
		if _fog.is_visible(coord):
			result.append(coord)
	return result


func _furthest_visible(visible: Array[Vector2i]) -> int:
	var furthest := -1
	for coord in visible:
		furthest = maxi(furthest, HexCoord.distance(_TOWER_HEX, coord))
	return furthest


func _expected_disk_size() -> int:
	return HexCoord.hex_disk(_TOWER_HEX, _expected_tower_radius()).size()


## The ring an intact Watchtower covers at whatever phase this run is in,
## read from the catalog and FogOfWarManager's own constants rather than
## restated — a balance pass moving either must not turn this into a false
## failure. Same reasoning for the two noise expectations below.
func _expected_tower_radius() -> int:
	var definition := BuildingCatalog.get_definition(_TOWER)
	if not TimeCycleManager.is_night():
		return definition.vision_radius
	if definition.lit_at_night:
		return definition.vision_radius + FogOfWarManager.NIGHT_LIT_BONUS
	return maxi(0, definition.vision_radius - FogOfWarManager.NIGHT_VISION_PENALTY)


## What an intact Watchtower puts on its own hex: its machinery term (0 for
## this building) plus, at night, the lamp.
func _expected_tower_noise() -> float:
	var lamp := NoiseManager.NIGHT_LIGHT_ATTRACTION if TimeCycleManager.is_night() and BuildingCatalog.get_definition(_TOWER).lit_at_night else 0.0
	return _construction_noise() + lamp


## What the same building emits while it is still a construction site: the
## machinery term only, which NoiseManager deliberately leaves running. Read
## through NoisePropagation rather than restated, so a change to the model or
## to the catalogue moves this with it instead of turning it into a false
## failure. 0.0 is the catalogue's "not machinery" sentinel, and a Watchtower
## carries it — which is exactly why this fixture can measure the lamp alone.
func _construction_noise() -> float:
	var source_db := BuildingCatalog.get_definition(_TOWER).noise_source_db
	if source_db <= 0.0:
		return 0.0
	if TimeCycleManager.is_night():
		source_db += NoisePropagation.NIGHT_PROPAGATION_BONUS_DB
	return maxf(0.0, NoisePropagation.level_at(source_db, 0.0) - NoisePropagation.HEARING_THRESHOLD_DB)


## True once the pinned clock has actually put TimeCycleManager in NIGHT.
## SceneTree's process_frame fires BEFORE node _process callbacks, and
## TimeCycleManager only re-reads TickManager there, so the phase is at least
## one full frame behind load_save_state() — awaiting a fixed frame count
## instead of the condition is what made the first run of this file measure
## two checks by day and the rest by night.
func _await_night() -> bool:
	var deadline := Time.get_ticks_msec() + _PHASE_WAIT_MS
	while not TimeCycleManager.is_night():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


## True once no fixture hex is VISIBLE any more, false if one still is after
## _GRACE_WAIT_MS of real time. Bounded rather than a fixed sleep, so a fog
## manager that never demotes fails the check instead of hanging the gate;
## and on the whole set rather than one hex, so it does not assume the grace
## countdowns all cross zero in the same _process() pass.
func _await_all_dark() -> bool:
	var deadline := Time.get_ticks_msec() + _GRACE_WAIT_MS
	while not _visible_hexes().is_empty():
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true
