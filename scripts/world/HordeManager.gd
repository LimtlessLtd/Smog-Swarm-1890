class_name HordeManager
extends Node

## Design doc Phase 5.2 (spawn) + the WANDERING slice of Phase 5.10
## (roaming) — "the world starts pre-populated with a handful of small
## roaming hordes ... deliberately modest ... so a brand-new colony has room
## to establish basic defenses before facing anything serious" (design doc,
## decided). Wired as a Main.tscn sibling of HexGridMap/BuildingManager,
## same pattern as every other top-level manager.
##
## Implemented now:
##   - Starting-horde seeding: a handful of small hordes placed on frontier
##     (uncleared wilderness) hexes at least MIN_SPAWN_DISTANCE_FROM_SETTLEMENT
##     away from any settlement, seeded (HORDE_SEED) the same way
##     HexMapGenerator's terrain/soil noise is (1890/1891) — this is that
##     same fixed-seed family's third member, kept deterministic for the
##     same reproducibility reason.
##   - WANDERING drift: each horde picks a random frontier hex within
##     DRIFT_TARGET_RADIUS of itself, routes to it via Phase 5.5's
##     HexPathfinder, then walks there continuously (real-time, world-space
##     — see this class's own doc comment further down on the continuous-
##     movement rewrite) rather than snapping hex to hex — "drifts across
##     passable uncleared wilderness ... biased toward open territory
##     rather than a deliberate beeline anywhere" per the design doc: the
##     omnidirectional ring pick supplies "no beeline", and restricting
##     targets to frontier hexes supplies "biased toward open territory"
##     (steers away from player-secured ground).
##   - Phase 5.9's starvation-casualty spawn source: add_casualty_zombies(),
##     wired to BuildingManager.civilians_starved — "every starved civilian
##     is a casualty for Phase 5.9's purposes ... same as a combat death"
##     (that signal's own doc comment). Finds-or-creates a WANDERING horde
##     at the hex a Tenement's population starved in and grows it by the
##     death count, rather than the loss vanishing into a generic
##     "contested" abstraction. The other two Phase 5.9 casualty sources —
##     a UnitInstance dying in combat, and now a BuildingInstance being
##     ruined (Phase 5.12) — both go through CombatCoordinator/
##     BuildingManager.building_ruined the same way, see those classes'
##     own doc comments.
##   - Phase 5.2's "lone zombie" decision: _on_ambient_spawn_day() rolls a
##     flat daily chance to seed one genuinely tiny (1-3) horde on ambient
##     wilderness, independent of the starting seed and casualty conversion
##     and independent of the noise system below — a flat chance is still
##     the real spawn-side path here, per that decision.
##   - Phase 5.10's merge/split: _check_merges()/_check_splits(), rolled
##     once per movement tick alongside the existing drift — co-located
##     hordes can combine, a large enough horde can fragment in two.
##   - Phase 4.1/5.10's ATTACKING state, now real: _advance_horde() checks
##     whether the next step in a horde's drift path crosses an unbreached
##     WallSegment (optional wall_manager_path) — if so, the horde doesn't
##     move, it sieges that segment instead (_siege_wall(), with the
##     decided siege-damage bonus and Ditch/Oil Pit counter-damage), only
##     reverting to WANDERING once the segment actually breaches and it
##     steps through. This is deliberately the SIMPLEST version of "wall
##     targeting" — whichever segment a horde's own drift happens to walk
##     into, not a deliberate seek-out-the-nearest-wall behavior — matching
##     "contact matters however it happens" (5.10's own already-decided
##     framing for unit combat, applied here to walls).
##   - Phase 5.2/5.10's ATTRACTED state, now real too: _replan() (called
##     whenever a horde's path empties) checks NoiseManager (optional
##     noise_manager_path) FIRST, before falling back to the unbiased
##     WANDERING pick — a horde within ATTRACTION_AWARENESS_RADIUS of a hex
##     whose noise clears ATTRACTION_THRESHOLD paths deliberately toward the
##     loudest one instead of drifting at random. See _pick_attraction_target()
##     for the full "local, not global" reasoning.
##
## **Real-time continuous movement (user request, this pass) replaces the
## old hex-stepping model** — a horde used to snap instantly from one hex
## to the next once every `MOVE_INTERVAL_SECONDS`; it now walks smoothly
## (`MovementStepper.advance_toward_hex()`, world-units/second, terrain-
## and logistics-scaled) toward the next hex's center every `_process()`
## frame, steering around static obstacles (props/buildings) the same way
## `UnitOrderController` does — see that class's own doc comment for the
## shared design, and `MovementStepper.gd` for the actual stepping/steering
## math. The wall-blocking peek above still happens per hex-crossing (not
## just once per old tick) — a multi-hex catch-up burst at very high
## `TickManager` speed must not glide through an un-breached wall on an
## intermediate hex. Siege damage against a blocked wall is now applied
## CONTINUOUSLY (scaled by however much of a frame's `delta` the horde
## spent blocked, converted against the same old per-`LOGIC_TICK_SECONDS`
## rate) rather than in one lump per periodic tick — same total
## damage-per-real-second as before, just smoother, and it no longer needs
## its own separate tick-driven special case now that `_advance_horde()`
## already runs every frame anyway.
##
## `LOGIC_TICK_SECONDS` (renamed from the old `MOVE_INTERVAL_SECONDS` — it
## no longer gates movement OR siege damage, only the two side-effects
## below) still drives `_check_merges()`/`_check_splits()` at the same
## real-world rate as before.
##
## Deliberately NOT wired here yet — each blocked on a system that doesn't
## exist, same "not implemented, deliberately" convention as every other
## forward-reference already in todo.md:
##   - ATTACKING's "deliberately besieging a HEX it sought out" half — an
##     ATTRACTED horde today still only ever besieges a WALL, and only as a
##     byproduct of its route happening to cross one (see the ATTACKING
##     bullet above); nothing yet lets a horde treat an undefended building
##     or ZoC-covered-but-unwalled hex itself as a deliberate siege target
##     the way Phase 5.10's own "or Military-ZoC-covered hex" framing wants
##     — that still needs Phase 5.12-style building-siege awareness wired
##     into the pathing/targeting layer, not just CombatCoordinator's
##     reactive contact-triggered siege.
##   - Reconnaissance & Early Warning (Phase 5.3) — an ETA/countdown
##     presentation layer over an ATTRACTED horde's route, once a UI exists
##     to show it (still Phase 6+ work); this phase only owns the
##     underlying attraction mechanic ATTRACTED now drives.
##   - Threat Meter HUD (Phase 6.1) — NoiseManager.get_noise_at() is a real,
##     queryable per-hex field now; nothing in MainHUD reads it yet.
##   - Horde-size/spawn-frequency ramp-up over time (Phase 7.1's Act pacing
##     / Phase 7.6's difficulty presets) — neither campaign system exists yet;
##     STARTING_HORDE_COUNT/SIZE below are a flat one-time seed, not a curve.
##   - LOD-based cheap/expensive simulation switching (design doc's own
##     "Performance" note under 5.10) — no consumer yet to profile against,
##     premature at this scale (a handful of hordes total).

signal horde_spawned(horde: Horde)
signal horde_moved(horde: Horde, from_coord: Vector2i, to_coord: Vector2i)
signal horde_size_changed(horde: Horde, delta: int)
signal horde_removed(horde: Horde)

@export var hex_grid_map_path: NodePath
@export var logistics_network_path: NodePath  ## Optional — same road/rail/canal discount HexPathfinder gives any other route (now a continuous SPEED bonus too, not just a path-preference one — see MovementStepper).
@export var building_manager_path: NodePath   ## Optional — Phase 5.9's starvation-casualty spawn source, AND (user request) local obstacle avoidance: buildings steer continuous movement around them regardless of Tactical hydration. Unset gracefully skips both.
@export var wall_manager_path: NodePath       ## Optional — Phase 4.1/5.10's horde-vs-wall siege; unset means walls simply never block a horde's drift (same "gracefully skip it" convention).
@export var local_detail_manager_path: NodePath  ## Optional — local obstacle avoidance: props (trees/rocks/etc.) only exist as live data while their hex is Tactical-hydrated (LocalDetailManager.get_props_at()) — unset (or a currently-dehydrated hex) just means no prop avoidance there.
@export var noise_manager_path: NodePath      ## Optional — Phase 5.2/5.10's ATTRACTED state; unset means a horde only ever WANDERs, never deliberately seeks out a noise/light source (same "gracefully skip it" convention).

var _hex_grid_map: HexGridMap
var _logistics_network: LogisticsNetwork
var _building_manager: BuildingManager
var _wall_manager: WallManager
var _local_detail_manager: LocalDetailManager
var _noise_manager: NoiseManager
var _hordes: Array[Horde] = []
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
var _logic_tick_timer: float = 0.0

## Same seed-numbering convention as HexMapGenerator's terrain/soil noise
## (1890/1891 — see that class's _init()) — deterministic starting
## conditions for the same reproducibility reason.
const HORDE_SEED: int = 1892

## Design doc: exact numbers are a balancing pass, not an architecture
## decision — same framing as every other placeholder constant table in
## this project.
const STARTING_HORDE_COUNT: int = 3
const STARTING_HORDE_SIZE_MIN: int = 10
const STARTING_HORDE_SIZE_MAX: int = 25
## Hordes never spawn within this many hexes of a settlement — the design
## doc's own "room to establish basic defenses" reasoning.
const MIN_SPAWN_DISTANCE_FROM_SETTLEMENT: int = 4

## Real-time seconds (scaled by Engine.time_scale, same as everything else
## driven off TickManager/TimeCycleManager) between the two remaining
## periodic side-effects below (_check_merges()/_check_splits()) — no
## longer gates movement itself (continuous now, every frame — see this
## class's own doc comment) or siege damage (also continuous now, scaled
## against this same rate rather than applied once per tick). Renamed from
## the old MOVE_INTERVAL_SECONDS now that it means something narrower;
## deliberately still matches UnitOrderController.LOGIC_TICK_SECONDS.
const LOGIC_TICK_SECONDS: float = 20.0
## How far (in hexes) a fresh drift target is picked from a horde's current
## position when it needs to replan.
const DRIFT_TARGET_RADIUS: int = 5

## Design doc Phase 5.10, decided: "attraction is local, not global" — how
## far (in hexes) a horde scans for a noise/light source (NoiseManager,
## Phase 5.2) above threshold when replanning. Deliberately the same order
## of magnitude as DRIFT_TARGET_RADIUS above, not colony-wide — a horde on
## the far side of the map has no way to know a distant city is loud.
const ATTRACTION_AWARENESS_RADIUS: int = 6
## The noise level (NoiseManager.get_noise_at()) a hex must clear before a
## horde within range treats it as worth deliberately walking toward,
## rather than continuing its unbiased WANDERING drift. Placeholder
## balancing number, not an architecture decision, same framing as every
## other constant table here.
const ATTRACTION_THRESHOLD: float = 3.0

## Rough clearance radius a horde presents to
## MovementStepper.steer_around_obstacles() — same placeholder value as
## UnitOrderController.ENTITY_RADIUS (a horde's own rendered figure cluster
## spreads across a similar radius, TacticalEntityLayer.FIGURE_SPREAD).
const ENTITY_RADIUS: float = 20.0

## Design doc Phase 5.1's Day/Night movement modifiers — unblocked now that
## movement is continuous (Phase 5.5) rather than a fixed per-hex timer,
## which is exactly what that phase's own note said it needed. "Zombies are
## slow/sluggish" (Day) has no exact number in the design doc — a
## placeholder balancing multiplier, same disclaimer every other constant
## table in this project already carries. "Zombie move speed +50%" (Night)
## IS an exact design-doc number, applied literally. Deliberately NOT
## modeling "aggression +100%" or "double noise-attraction multiplier" here
## — neither an aggression stat nor a noise-attraction system exists yet
## (still blocked exactly as this phase's own note already says), so those
## stay unbuilt; only the movement-speed half of the Night bullet is real.
const DAY_MOVE_SPEED_MULTIPLIER: float = 0.65
const NIGHT_MOVE_SPEED_MULTIPLIER: float = 1.5

## Design doc Phase 5.2, decided (grilling session): "a 'lone zombie' isn't
## a new entity type, it's just a Horde at small size ... ambient wilderness
## spawning needs a path to occasionally seed a genuinely tiny (1-3) horde,
## not just today's STARTING_HORDE_SIZE_MIN-MAX (10-25) range." No dedicated
## noise/attraction system exists to trigger this off yet (see this class's
## own "Deliberately NOT wired" list above) — a flat daily chance is the
## simplest real spawn-side path, reusing seed_starting_hordes()'s own
## _spawnable_coords()/Horde.new() machinery. Balancing numbers, not
## architecture, same framing as every other constant table here.
const AMBIENT_SPAWN_CHANCE_PER_DAY: float = 0.35
const AMBIENT_HORDE_SIZE_MIN: int = 1
const AMBIENT_HORDE_SIZE_MAX: int = 3

## Design doc Phase 5.10, decided (grilling session): "hordes get a small
## periodic chance to merge or split." Checked once per movement tick
## alongside the existing drift, not a separate timer. Balancing numbers,
## not architecture, same framing as every other constant table here.
const MERGE_CHANCE_PER_TICK: float = 0.1   ## Rolled once per co-located pair, per tick.
const SPLIT_CHANCE_PER_TICK: float = 0.05  ## Rolled once per eligible horde, per tick.
const SPLIT_MIN_SIZE: int = 20             ## A horde must be at least this big to be eligible to fragment.

## Design doc Phase 4.1/5.10, decided: "a horde attacks whichever specific
## segment it physically reaches" + "hordes get an explicit siege bonus
## against walls." Balancing numbers, not architecture, same framing as
## every other constant table here.
const WALL_SIEGE_DAMAGE_MULTIPLIER: float = 2.0  ## A horde hits a wall harder than it'd hit a unit — the "siege bonus".

## Design doc Phase 4.1: "Ditches and Oil Pits ... inflict damage on a
## besieging horde before/during a breach attempt" — flat headcount-worth
## chip damage per siege tick, converted through Horde.HP_PER_ZOMBIE the
## same way any other combat damage is. A sufficiently ditched-and-pitted
## wall can grind a small horde down to nothing before it ever breaches.
const DITCH_COUNTER_DAMAGE: float = 3.0
const OIL_PIT_COUNTER_DAMAGE: float = 5.0

func _ready() -> void:
	# Same reasoning as TickManager/TimeCycleManager: background-simulation
	# infrastructure that shouldn't freeze if a future system ever pauses
	# the SceneTree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.civilians_starved.connect(_on_civilians_starved)
		_building_manager.building_ruined.connect(_on_building_ruined)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
	if local_detail_manager_path != NodePath():
		_local_detail_manager = get_node(local_detail_manager_path)
	if noise_manager_path != NodePath():
		_noise_manager = get_node(noise_manager_path)
	TickManager.day_completed.connect(_on_ambient_spawn_day)
	_rng.seed = HORDE_SEED
	seed_starting_hordes()

func _process(delta: float) -> void:
	if _hordes.is_empty():
		return

	# Continuous movement — every frame, every horde. duplicate(): a horde
	# can be removed mid-loop (ground down to 0 by Ditch/Oil Pit
	# counter-damage while sieging a wall) — iterating the live array while
	# erasing from it would skip entries.
	for horde: Horde in _hordes.duplicate():
		_advance_horde(horde, delta)

	# The two remaining periodic side-effects — unchanged real-world cadence
	# from the old movement-tick rate.
	_logic_tick_timer += delta
	while _logic_tick_timer >= LOGIC_TICK_SECONDS:
		_logic_tick_timer -= LOGIC_TICK_SECONDS
		_check_merges()
		_check_splits()

func get_all_hordes() -> Array[Horde]:
	return _hordes.duplicate()

## Design doc Phase 5.3 (Reconnaissance & Early Warning): "an ETA along an
## ATTRACTED horde's path ... not just an abstract warning." Sums the
## real-time seconds remaining to walk `horde`'s current `path`, reusing the
## exact same per-edge `_movement_speed()` continuous movement already
## applies frame-by-frame — summed forward here instead of applied once.
## Purely a math query; "is this horde within observed range" (the design
## doc's own gating condition) is the CALLER's job (Fog of War VISIBLE, per
## this phase's own scope — see MainHUD's own consumer), not this method's.
## Returns 0.0 for a horde with an empty path (arrived, or never replanned
## yet) — a caller showing "ETA 0:00" for that case reads fine, same as any
## other just-arrived state.
func get_eta_seconds(horde: Horde) -> float:
	if horde.path.is_empty():
		return 0.0

	var total := 0.0
	var from_coord := horde.hex_coord

	# First leg is partial — the horde is already partway across it
	# (`local_position`), not starting fresh from the hex center.
	var current_world := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	var first_target := HexCoord.axial_to_world(horde.path[0])
	var first_speed := _movement_speed(from_coord, horde.path[0])
	if first_speed > 0.0:
		total += current_world.distance_to(first_target) / first_speed
	from_coord = horde.path[0]

	for i in range(1, horde.path.size()):
		var to_coord: Vector2i = horde.path[i]
		var speed := _movement_speed(from_coord, to_coord)
		if speed > 0.0:
			total += HexCoord.axial_to_world(from_coord).distance_to(HexCoord.axial_to_world(to_coord)) / speed
		from_coord = to_coord

	return total

## Exposed for CombatCoordinator (Phase 5.4/5.9/5.10's live combat
## trigger) — a horde reduced to 0 (Horde.apply_remaining_hp()) is that
## caller's cue to remove it, mirroring UnitManager.remove_unit()/
## BuildingManager.remove_building()'s own shape.
func remove_horde(horde: Horde) -> void:
	_hordes.erase(horde)
	horde_removed.emit(horde)

func get_hordes_at(coord: Vector2i) -> Array[Horde]:
	var result: Array[Horde] = []
	for horde in _hordes:
		if horde.hex_coord == coord:
			result.append(horde)
	return result

## Design doc Phase 5.9: "every civilian and military unit lost becomes a
## zombie at the location it died ... converted zombies accumulate into
## that hex's own zombie population ... rather than vanishing into a
## generic 'contested' abstraction." Finds the first existing horde already
## sitting at `coord` and grows it by `count`, or spawns a fresh WANDERING
## one there if none exists yet — either way the loss becomes a real,
## trackable threat rather than a number disappearing. Public (not a signal
## handler only) so a future combat-casualty trigger can call this exact
## same accumulation logic once one exists, per this class's own doc
## comment on what's still missing.
func add_casualty_zombies(coord: Vector2i, count: int) -> void:
	if count <= 0:
		return
	var horde := _find_horde_at(coord)
	if horde:
		horde.size += count
		horde_size_changed.emit(horde, count)
		return
	horde = Horde.new(coord, count, _next_id)
	_next_id += 1
	_hordes.append(horde)
	horde_spawned.emit(horde)

func _find_horde_at(coord: Vector2i) -> Horde:
	for horde in _hordes:
		if horde.hex_coord == coord:
			return horde
	return null

func _on_civilians_starved(hex_coord: Vector2i, count: int) -> void:
	add_casualty_zombies(hex_coord, count)

## Design doc Phase 5.12/5.9: a ruined building's population "converts to
## zombies right there ... same as a starvation death, just triggered by
## direct assault instead of hunger." `count` may legitimately be 0 (an
## industrial/agricultural building with no housed population) —
## add_casualty_zombies() already no-ops on count <= 0, so no extra guard
## is needed here.
func _on_building_ruined(instance: BuildingInstance, lost_population: int) -> void:
	add_casualty_zombies(instance.hex_coord, lost_population)

## Design doc Phase 5.2's "lone zombie" decision: a flat daily chance to seed
## one genuinely tiny (1-3) horde on ambient wilderness, independent of the
## one-time starting seed and the casualty-conversion spawn source — reuses
## _spawnable_coords() exactly as seed_starting_hordes() does, so the same
## "far enough from a settlement" rule applies.
func _on_ambient_spawn_day(_day_number: int) -> void:
	if not _hex_grid_map or _rng.randf() >= AMBIENT_SPAWN_CHANCE_PER_DAY:
		return
	var candidates := _spawnable_coords()
	if candidates.is_empty():
		return
	var coord: Vector2i = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var size := _rng.randi_range(AMBIENT_HORDE_SIZE_MIN, AMBIENT_HORDE_SIZE_MAX)
	var horde := Horde.new(coord, size, _next_id)
	_next_id += 1
	_hordes.append(horde)
	horde_spawned.emit(horde)

## Design doc Phase 5.10: "two hordes that end up on/near the same hex can
## combine into one." Scoped to hordes sharing the EXACT same hex_coord —
## the same "same hex" granularity add_casualty_zombies() already merges
## casualties into — checked once per movement tick, one merge roll per
## co-located pair per tick rather than a guaranteed instant cascade on a
## crowded hex.
func _check_merges() -> void:
	var by_hex: Dictionary = {}  # Vector2i -> Array[Horde]
	for horde in _hordes:
		if not by_hex.has(horde.hex_coord):
			by_hex[horde.hex_coord] = []
		by_hex[horde.hex_coord].append(horde)
	for coord in by_hex:
		var group: Array = by_hex[coord]
		if group.size() < 2 or _rng.randf() >= MERGE_CHANCE_PER_TICK:
			continue
		var survivor: Horde = group[0]
		var absorbed: Horde = group[1]
		survivor.size += absorbed.size
		horde_size_changed.emit(survivor, absorbed.size)
		remove_horde(absorbed)

## Design doc Phase 5.10: "a large horde can fragment into two smaller
## ones." Splits roughly in half; the new fragment starts WANDERING from the
## same hex (no reason to displace it elsewhere) and gets its own fresh
## drift replan next tick, same as any other horde. Iterates a duplicate()
## snapshot since this appends fresh hordes to _hordes mid-loop.
func _check_splits() -> void:
	for horde: Horde in _hordes.duplicate():
		if horde.size < SPLIT_MIN_SIZE or _rng.randf() >= SPLIT_CHANCE_PER_TICK:
			continue
		var fragment_size := horde.size / 2
		if fragment_size <= 0:
			continue
		horde.size -= fragment_size
		horde_size_changed.emit(horde, -fragment_size)
		var fragment := Horde.new(horde.hex_coord, fragment_size, _next_id)
		_next_id += 1
		_hordes.append(fragment)
		horde_spawned.emit(fragment)

## Seeds the handful of starting hordes on a truly fresh start — mirrors
## BuildingManager.seed_starting_buildings()'s own "only if nothing's placed
## yet" guard. A load right after boot (SaveLoadManager.load_save_hordes())
## clears/replaces `_hordes` before this would otherwise run, same as that
## seeded Town Hall never lingering once a real save is loaded.
func seed_starting_hordes() -> void:
	if not _hordes.is_empty() or not _hex_grid_map:
		return
	var candidates := _spawnable_coords()
	for _i in range(STARTING_HORDE_COUNT):
		if candidates.is_empty():
			break  # Map too small/dense to have enough valid spawn points — seed what we could.
		var index := _rng.randi_range(0, candidates.size() - 1)
		var coord: Vector2i = candidates[index]
		candidates.remove_at(index)
		var size := _rng.randi_range(STARTING_HORDE_SIZE_MIN, STARTING_HORDE_SIZE_MAX)
		var horde := Horde.new(coord, size, _next_id)
		_next_id += 1
		_hordes.append(horde)
		horde_spawned.emit(horde)

func _spawnable_coords() -> Array[Vector2i]:
	var settlement_coords: Array[Vector2i] = []
	for cell in _hex_grid_map.get_all_cells():
		if cell.is_settlement:
			settlement_coords.append(cell.coord)

	var result: Array[Vector2i] = []
	for cell in _hex_grid_map.get_all_cells():
		if not cell.is_passable() or not cell.is_frontier():
			continue
		var far_enough := true
		for settlement_coord in settlement_coords:
			if HexCoord.distance(cell.coord, settlement_coord) < MIN_SPAWN_DISTANCE_FROM_SETTLEMENT:
				far_enough = false
				break
		if far_enough:
			result.append(cell.coord)
	return result

## Walks `horde` continuously toward whatever's next on its drift path,
## consuming up to `delta` seconds of travel this call —
## MovementStepper.advance_toward_hex() handles one hex-segment at a time;
## this loop threads through however many hex boundaries `delta` covers
## (more than one is possible at very high TickManager speeds), emitting
## horde_moved once per boundary actually crossed, in order — see this
## class's own doc comment on why that per-crossing signal contract matters
## to CombatCoordinator/StrategicOverlayManager/TerritoryController.
##
## Design doc Phase 4.1/5.10: "a horde attacks whichever specific segment it
## physically reaches" — the wall peek happens EVERY hex-crossing attempt
## within this loop (not just once per old tick), so a multi-hex catch-up
## burst can't glide through an un-breached wall on an intermediate hex
## just because the loop's first iteration found the immediate edge clear.
func _advance_horde(horde: Horde, delta: float) -> void:
	# Design doc, user request: a Dragoon's charge stuns the horde it hits —
	# see Horde.stun_seconds_remaining's own doc comment. A stunned horde
	# doesn't move, doesn't progress a wall siege, full stop, for however
	# long remains; it resumes exactly where it left off (same path, same
	# ATTACKING/WANDERING/ATTRACTED state) the instant the stun expires.
	if horde.stun_seconds_remaining > 0.0:
		horde.stun_seconds_remaining = maxf(0.0, horde.stun_seconds_remaining - delta)
		return
	if horde.path.is_empty():
		_replan(horde)
	if horde.path.is_empty():
		return  # No valid drift target found this cycle (e.g. boxed in) — try again next frame.

	var remaining := delta
	while remaining > 0.0 and not horde.path.is_empty():
		var next_coord: Vector2i = horde.path[0]
		var segment: WallSegment = null
		if _wall_manager:
			# Freehand wall rework: "the wall between these two hexes" isn't
			# a single lookup anymore (a real drawn line can cross a hex
			# boundary anywhere along it, in several independent <=100m
			# pieces) — get_blocking_segment() checks the horde's actual
			# straight-line travel this step against every nearby piece's
			# own real geometry instead. See that function's own doc
			# comment for the full reasoning.
			var from_world := HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
			var to_world := HexCoord.axial_to_world(next_coord)
			segment = _wall_manager.get_blocking_segment(horde.hex_coord, next_coord, from_world, to_world)
		if segment and not segment.is_breached():
			_siege_wall(horde, segment, remaining)
			return  # Blocked for the rest of this frame — no movement past this edge.

		var from_coord := horde.hex_coord  ## Captured BEFORE the call below overwrites it.
		var speed := _movement_speed(from_coord, next_coord)
		var obstacles := _gather_obstacles(from_coord, next_coord)
		var result := MovementStepper.advance_toward_hex(from_coord, horde.local_position, next_coord, remaining, speed, obstacles, ENTITY_RADIUS, float(horde.id))
		horde.hex_coord = result["hex_coord"]
		horde.local_position = result["local_position"]
		remaining -= float(result["seconds_used"])
		if not result["arrived"]:
			break  ## Used this frame's whole remaining budget without finishing the crossing.

		horde.path.pop_front()
		if horde.state == GameEnums.HordeState.ATTACKING:
			horde.state = GameEnums.HordeState.WANDERING  # Through the breach — back to roaming.
		horde_moved.emit(horde, from_coord, horde.hex_coord)

## Design doc Phase 4.1/5.10: damages `segment` with the decided siege bonus
## (WALL_SIEGE_DAMAGE_MULTIPLIER), and — Phase 4.1's other still-unbuilt
## bullet, now real — Ditches/Oil Pits inflict counter-damage back on the
## besieging horde, converted through the same Horde.apply_remaining_hp()
## every other combat-damage source already uses; a sufficiently defended
## segment can grind a small horde down to nothing before it ever breaches.
##
## Continuous now (user request's own knock-on effect): `seconds` is
## whatever fraction of this frame the horde spent blocked, scaled against
## LOGIC_TICK_SECONDS so the total damage-per-real-second matches the old
## once-per-tick lump exactly — smoother, and no separate tick-driven
## special case needed now that _advance_horde() already runs every frame.
func _siege_wall(horde: Horde, segment: WallSegment, seconds: float) -> void:
	horde.state = GameEnums.HordeState.ATTACKING
	var tick_fraction := seconds / LOGIC_TICK_SECONDS
	_wall_manager.damage_segment(segment, horde.get_combat_damage() * WALL_SIEGE_DAMAGE_MULTIPLIER * tick_fraction)

	var counter_damage := 0.0
	if segment.has_ditch:
		counter_damage += DITCH_COUNTER_DAMAGE
	if segment.has_oil_pit:
		counter_damage += OIL_PIT_COUNTER_DAMAGE
	counter_damage *= tick_fraction
	if counter_damage <= 0.0:
		return
	horde.apply_remaining_hp(horde.get_combat_hp() - counter_damage)
	if horde.size <= 0:
		remove_horde(horde)

## Design doc Phase 5.10: ATTRACTED is checked FIRST on every replan, before
## falling back to the unbiased WANDERING pick below — "a horde within
## range of a noise or light source above threshold ... paths deliberately
## toward it" takes priority over "no deliberate beeline anywhere" once
## there's actually something to be deliberate ABOUT. Re-evaluated fresh
## every time a horde's path empties (same "cheap to re-derive, not a
## persistent commitment" philosophy the whole file already uses for
## WANDERING) rather than a mid-route redirect — a horde already walking
## somewhere doesn't abandon that route just because a nearer hex got
## louder mid-walk; it'll pick that up on its NEXT replan instead, same as
## a WANDERING horde would.
func _replan(horde: Horde) -> void:
	var attraction_target := _pick_attraction_target(horde.hex_coord)
	var is_attracted := attraction_target != horde.hex_coord
	var target := attraction_target if is_attracted else _pick_drift_target(horde.hex_coord)
	if target == horde.hex_coord:
		return
	var path := HexPathfinder.find_path(_hex_grid_map, horde.hex_coord, target, _logistics_network)
	if path.size() > 1:
		path.remove_at(0)  # path[0] is the horde's own current hex — the walk starts at path[1] onward.
		horde.path = path
		horde.state = GameEnums.HordeState.ATTRACTED if is_attracted else GameEnums.HordeState.WANDERING
		# Known cosmetic gap, not a functional one: if this ATTRACTED walk
		# later crosses an unbreached wall, _advance_horde()'s existing
		# breach-through code unconditionally relabels the horde WANDERING
		# again afterward (it predates ATTRACTED existing at all) — the
		# horde's `path` is completely unaffected by that mislabel and keeps
		# walking toward the same attraction target regardless, and the
		# label self-corrects the next time this method runs. Not worth a
		# special case for a purely cosmetic state-label inaccuracy on one
		# specific hex crossing.

## Design doc Phase 5.10, decided: a purely POSITIONAL, re-derived-every-time
## check against NoiseManager's own per-hex field (Phase 5.2) — no persistent
## "am I currently attracted" flag to keep in sync, matching every other
## derived-not-stored decision already made throughout this project (Zone of
## Control, Fog of War's VISIBLE set, WallManager.is_legacy_segment()).
## Returns `from_coord` itself (the same no-op sentinel _pick_drift_target()
## already uses) when no NoiseManager is wired, nothing in range clears
## ATTRACTION_THRESHOLD, or the loudest hex in range turns out to be the
## horde's own current hex (nothing to walk toward).
func _pick_attraction_target(from_coord: Vector2i) -> Vector2i:
	if not _noise_manager:
		return from_coord
	var candidate := _noise_manager.get_loudest_hex_within(from_coord, ATTRACTION_AWARENESS_RADIUS)
	if candidate == from_coord or _noise_manager.get_noise_at(candidate) < ATTRACTION_THRESHOLD:
		return from_coord
	return candidate

## An unbiased (any direction) pick from the ring of hexes exactly
## DRIFT_TARGET_RADIUS away, filtered to passable frontier ground — "no
## deliberate beeline anywhere" plus "biased toward open territory" per the
## design doc. Returns `from_coord` itself (a no-op sentinel _replan()
## checks for) if nothing in the ring qualifies, e.g. near a map edge or
## deep inside secured territory.
func _pick_drift_target(from_coord: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for coord in HexCoord.hex_ring(from_coord, DRIFT_TARGET_RADIUS):
		var cell := _hex_grid_map.get_cell(coord)
		if cell and cell.is_passable() and cell.is_frontier():
			candidates.append(coord)
	if candidates.is_empty():
		return from_coord
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

## Exposed for SaveLoadManager (Phase 2.8) — mirrors WallManager's own
## get_save_state()'s {segments, next_id} shape.
func get_save_state() -> Dictionary:
	return {"hordes": _hordes.duplicate(), "next_id": _next_id}

## Restores hordes from a save. Each horde's in-flight drift path is
## deliberately discarded (see Horde.path's own doc comment) — HordeManager
## replans fresh the next time it moves, same "cheap to re-derive, not worth
## saving" call Zone of Control coverage makes.
func load_save_state(hordes: Array[Horde], next_id: int) -> void:
	_hordes = hordes.duplicate()
	for horde in _hordes:
		horde.path.clear()
	_next_id = next_id
	_logic_tick_timer = 0.0

## Terrain (current hex) and logistics (this specific edge) speed
## multipliers stacked onto MovementStepper.BASE_MOVE_SPEED — same
## HexPathfinder table the drift route itself was chosen against, now also
## shaping how fast continuous movement crosses it (Phase 2.12.1) — plus
## Phase 5.1's Day/Night modifier (sluggish by day, faster by night),
## stacking multiplicatively with terrain/logistics like every other factor
## here rather than replacing them.
func _movement_speed(from_coord: Vector2i, to_coord: Vector2i) -> float:
	var speed := MovementStepper.BASE_MOVE_SPEED
	if _hex_grid_map:
		speed *= HexPathfinder.get_terrain_speed_multiplier(_hex_grid_map.get_cell(from_coord))
	speed *= HexPathfinder.get_logistics_speed_multiplier(_logistics_network, from_coord, to_coord)
	speed *= NIGHT_MOVE_SPEED_MULTIPLIER if TimeCycleManager.is_night() else DAY_MOVE_SPEED_MULTIPLIER
	return speed

## Buildings (always queryable) + props (only where Tactical-hydrated) near
## both the hex a horde currently occupies and the one it's drifting
## toward — see this class's own doc comment and ObstacleRadii for why
## these two sources are treated differently.
func _gather_obstacles(coord: Vector2i, next_coord: Vector2i) -> Array[Dictionary]:
	var obstacles: Array[Dictionary] = []
	_add_hex_obstacles(coord, obstacles)
	if next_coord != coord:
		_add_hex_obstacles(next_coord, obstacles)
	return obstacles

func _add_hex_obstacles(coord: Vector2i, obstacles: Array[Dictionary]) -> void:
	var hex_center := HexCoord.axial_to_world(coord)
	if _building_manager:
		for building in _building_manager.get_buildings_at(coord):
			obstacles.append({"position": hex_center + building.local_position, "radius": ObstacleRadii.BUILDING_RADIUS})
	if _local_detail_manager:
		for prop in _local_detail_manager.get_props_at(coord):
			obstacles.append({"position": hex_center + prop.local_position, "radius": ObstacleRadii.for_prop(prop.prop_type)})
