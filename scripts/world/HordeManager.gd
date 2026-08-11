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
##
## **Phase 5.10 "Performance" note, closed this pass: LOD-based cheap/
## expensive simulation switching.** The real per-horde expense was never
## continuous movement itself (MovementStepper's per-frame math is a
## handful of vector ops, and _gather_obstacles() is an O(1) hashed hex
## lookup) — it's HexPathfinder.find_path()'s A* search, called from
## _replan() every time a horde's drift path empties. That search's own
## open-set is a plain Dictionary scanned linearly for the lowest f_score
## (see that function's own doc comment — "not a binary heap"), and at
## real horde-scale (hundreds-to-thousands of Horde instances, each
## replanning independently, amplified further by however many hex legs a
## single TickManager high-speed frame can complete) that adds up fast for
## hordes nobody's anywhere near. FAR_SIMULATION_RADIUS/_is_far_from_player()/
## _replan_cheap() below give a WANDERING horde outside that radius of
## every placed building a trivial one-hex random-neighbor hop instead of a
## real A* search — every bit as "no deliberate beeline anywhere" as the
## real ring-target path used to be (WANDERING's whole design intent, see
## this class's own header above), just without ever paying for the graph
## search. ATTRACTED and ATTACKING hordes are deliberately EXEMPT
## regardless of distance: an ATTRACTED horde's whole point is reaching a
## real target efficiently, and ATTACKING only ever triggers by physically
## reaching a wall — which, being player-built, is already going to read as
## "near a building" under the same distance check in practice, so no
## special-case exemption is even needed there beyond the state check
## itself already gating _replan() out (an ATTACKING horde's `path` isn't
## empty, it's blocked — _replan() never runs for it at all).

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

## Design doc Phase 5.10 "Performance" note (see this class's own header
## doc comment for the full reasoning): a WANDERING horde farther than this
## many hexes from EVERY placed building skips real A* pathfinding
## (_replan_cheap() below) in favor of a trivial random-neighbor hop.
## Deliberately >= ATTRACTION_AWARENESS_RADIUS so a horde already close
## enough to be within noise-attraction range of the player's own noisy
## buildings never reads as "far" while it's actively relevant — the two
## radii describing overlapping, not contradictory, notions of "close to
## the player."
##
## **Disclosed, not solved this pass (adversarial review):** the far/near
## classification is re-derived fresh on every replan, purely positional —
## no hysteresis/debounce. A horde that lingers right around this radius
## can genuinely alternate between a cheap one-hex hop and a real ~5-hex
## path replan to replan (confirmed via simulation during review: real,
## non-negligible at exactly this boundary, not a one-in-a-million edge
## case). Harmless — no crash, no stuck state, both branches always leave
## `path`/`state` consistent — just a purely cosmetic "bursty direction
## changes near the boundary" movement signature nobody has reported
## noticing, not worth a stateful debounce mechanism for a placeholder
## balancing radius that's trivial to retune if it ever does look wrong
## in practice.
const FAR_SIMULATION_RADIUS: int = 10
## The noise level (NoiseManager.get_noise_at()) a hex must clear before a
## horde within range treats it as worth deliberately walking toward,
## rather than continuing its unbiased WANDERING drift. Placeholder
## balancing number, not an architecture decision, same framing as every
## other constant table here.
##
## **Real per-zombie susceptibility (user request, 2026-08-11) modulates
## this per-horde now** — see _pick_attraction_target() and
## Horde.mean_susceptibility(). This constant is still the BASELINE (a
## horde with exactly average susceptibility, mean == 1.0-ish midpoint,
## reacts right at this value) — individual hordes now genuinely react
## sooner or later than each other, not all identically.
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
## IS an exact design-doc number, applied literally. The Night bullet's
## other two clauses are ALSO real now, just not here: "aggression +100%" is
## NIGHT_AGGRESSION_MULTIPLIER/get_night_aggression_multiplier() below,
## applied to a horde's OUTGOING combat damage rather than movement (this
## constant pair stays movement-only); "double noise-attraction multiplier"
## is NoiseManager.NIGHT_NOISE_MULTIPLIER, already feeding this class's own
## ATTRACTED state via _pick_attraction_target().
## Balance pass (playtest report: "zombies move way too fast during the
## daytime") — the Day/Night SPLIT was already correctly oriented (Day was
## always the slower multiplier, Night the faster one — confirmed by
## re-reading this exact constant pair and _movement_speed()'s own
## TimeCycleManager.is_night() branch, not assumed), but 0.65x still read as
## a brisk walk rather than the "slow/sluggish" shamble the design doc calls
## for, especially stacked with terrain/logistics speed multipliers that can
## push it back up. Dropped to 0.35x — a much clearer day/night contrast
## (was 1.5/0.65 ≈ 2.3x faster at night, now 1.5/0.35 ≈ 4.3x) — rather than
## touching NIGHT_MOVE_SPEED_MULTIPLIER, which IS an exact design-doc number
## ("+50%") and shouldn't move.
const DAY_MOVE_SPEED_MULTIPLIER: float = 0.35
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

## Design doc Phase 5.1's Night Phase bullet: "aggression +100%" — the
## zombie-side mirror of CombatCoordinator.DAY_DAMAGE_MULTIPLIER, doubling a
## horde's OUTGOING combat damage at night instead of boosting a unit's.
## Applied everywhere Horde.get_combat_damage() feeds a real attack: this
## class's own _siege_wall() (horde-vs-wall, below), plus
## CombatCoordinator._engage() (unit-vs-horde) and
## CombatCoordinator._siege_buildings() (horde-vs-building) — see those two
## call sites for how each applies it. A placeholder-turned-literal design-
## doc number ("+100%" = double), same framing as DAY_DAMAGE_MULTIPLIER.
const NIGHT_AGGRESSION_MULTIPLIER: float = 2.0

## A static func (not instance state) so CombatCoordinator can reach it via
## the class name alone — HordeManager.get_night_aggression_multiplier() —
## with no wired instance reference needed, the same way this class already
## reads TimeCycleManager.is_day()/is_night() directly rather than caching a
## day/night flag of its own. A pure function of TimeCycleManager's own
## day/night state; nothing here is Horde-instance-specific.
static func get_night_aggression_multiplier() -> float:
	return NIGHT_AGGRESSION_MULTIPLIER if TimeCycleManager.is_night() else 1.0

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
##
## **Real bug found and fixed (adversarial review, Phase 5.10 pass): replan
## now happens INSIDE this loop (at the top of every iteration), not once
## before it.** The old shape called _replan() exactly once, then let the
## loop drain whatever path that single call produced, exiting the instant
## `path` emptied even with `remaining` budget left over — silently
## discarding it rather than replanning fresh and continuing. That was
## always a latent gap (a big enough lag-spike/catch-up `delta` could drain
## even a real ~DRIFT_TARGET_RADIUS-hex A* path before `remaining` hit
## zero), but FAR_SIMULATION_RADIUS's own _replan_cheap() made it acute:
## a cheap replan's path is ALWAYS exactly one hex, so a far horde used to
## hit that same wall roughly 5x more often per unit of `delta` than a near
## horde's ~5-hex real path — at high TickManager speed, far hordes
## measurably crawled slower than near ones, and slower than this SAME
## horde moved before FAR_SIMULATION_RADIUS existed. Re-checking
## `path.is_empty()` inside the loop instead closes both the new asymmetry
## AND the pre-existing gap: a far horde now takes several cheap 1-hex
## replans in the same frame budget a near horde spends on one real path,
## restoring the exact "advances several hexes per frame at high speed"
## behavior every horde already had before this optimization existed. No
## new infinite-loop risk: `_replan_cheap()`'s candidates are always real
## `HexCoord.neighbors()` (never the horde's own current hex, so distance
## is always > 0 — MovementStepper.advance_toward_hex()'s zero-distance
## instant-arrival branch can't fire), and a `_replan()` that finds no
## valid target at all leaves `path` empty, hitting the same early
## `return` below on the very next loop check rather than spinning.
func _advance_horde(horde: Horde, delta: float) -> void:
	# Design doc, user request: a Dragoon's charge stuns the horde it hits —
	# see Horde.stun_seconds_remaining's own doc comment. A stunned horde
	# doesn't move, doesn't progress a wall siege, full stop, for however
	# long remains; it resumes exactly where it left off (same path, same
	# ATTACKING/WANDERING/ATTRACTED state) the instant the stun expires.
	if horde.stun_seconds_remaining > 0.0:
		horde.stun_seconds_remaining = maxf(0.0, horde.stun_seconds_remaining - delta)
		return

	var remaining := delta
	while remaining > 0.0:
		if horde.path.is_empty():
			_replan(horde)
		if horde.path.is_empty():
			return  # No valid drift target found this cycle (e.g. boxed in) — try again next frame.

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
	_wall_manager.damage_segment(segment, horde.get_combat_damage() * WALL_SIEGE_DAMAGE_MULTIPLIER * get_night_aggression_multiplier() * tick_fraction)

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
	var attraction_target := _pick_attraction_target(horde.hex_coord, horde)
	var is_attracted := attraction_target != horde.hex_coord
	# Performance-at-scale (Phase 5.10, see this class's own header doc
	# comment): an ATTRACTED horde always gets the real path below — it has
	# a specific target to actually reach. A plain WANDERING horde far from
	# every building skips the expensive A* search entirely.
	if not is_attracted and _is_far_from_player(horde.hex_coord):
		_replan_cheap(horde)
		return
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
func _pick_attraction_target(from_coord: Vector2i, horde: Horde) -> Vector2i:
	if not _noise_manager:
		return from_coord
	var candidate := _noise_manager.get_loudest_hex_within(from_coord, ATTRACTION_AWARENESS_RADIUS)
	if candidate == from_coord:
		return from_coord
	# Real per-zombie susceptibility (user request): a horde whose zombies
	# skew jumpy (mean_susceptibility() > 1.0) reacts to fainter noise than
	# ATTRACTION_THRESHOLD alone would allow; a duller horde needs a louder
	# source to bother. Threshold scales INVERSELY with susceptibility so
	# "more susceptible" genuinely means "reacts to less," not more.
	var effective_threshold := ATTRACTION_THRESHOLD / maxf(0.01, horde.mean_susceptibility())
	if _noise_manager.get_noise_at(candidate) < effective_threshold:
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

## Performance-at-scale (Phase 5.10, see this class's own header doc
## comment) — is `coord` farther than FAR_SIMULATION_RADIUS from EVERY
## placed building? O(buildings) per call: genuinely cheap at this
## project's real building-count scale (a colony's whole roster is
## realistically dozens, not thousands — see HexPathfinder.find_path()'s
## own doc comment for the same "not worth a spatial index yet" call at a
## similar scale). No BuildingManager wired means there's no way to tell
## "near" from "far" at all; defaults to "not far" (full fidelity) rather
## than silently degrading every horde on the map the moment that optional
## dependency is left unset.
##
## **Cadence, corrected (adversarial review):** this used to be described
## as "once per horde per path completion, not every frame" as if that
## were rare — for a FAR horde specifically it isn't: _replan_cheap()'s
## path is always exactly one hex, so "per path completion" for a far
## horde means once per hex crossed, same order of frequency as
## MovementStepper's own per-frame math once _advance_horde()'s replan-
## inside-the-loop fix (see that function's own doc comment) lets a fast
## catch-up frame drain several cheap replans in a row. Still categorically
## cheaper than what it replaced — a flat O(buildings) linear scan beats
## HexPathfinder.find_path()'s O(explored²)-ish A* search (naive
## linearly-scanned open set, see that function's own doc comment) even
## called 5x as often — but "not every frame" specifically was an
## inaccurate reassurance, not a real cadence guarantee, and has been
## removed rather than left to mislead a future reader.
func _is_far_from_player(coord: Vector2i) -> bool:
	if not _building_manager:
		return false
	for building in _building_manager.get_all_buildings():
		if HexCoord.distance(coord, building.hex_coord) <= FAR_SIMULATION_RADIUS:
			return false
	return true

## The cheap half of the performance-at-scale split above — no
## HexPathfinder.find_path() call at all, just an immediate one-hex hop to
## a uniformly-random PASSABLE neighbor of the horde's own current hex.
## Every bit as "no deliberate beeline anywhere" as the real
## _pick_drift_target()'s own ring-pick (WANDERING's whole design intent,
## see this class's own header doc comment) — a random walk one hex at a
## time is qualitatively the same undirected wander a real A* path to a
## random DRIFT_TARGET_RADIUS-ring hex already produced, just without ever
## paying for the graph search that used to compute that route. Leaves
## `horde.path` empty (tried again next frame) if every neighbor happens to
## be impassable, same as _replan()'s own "no valid drift target" fallback
## just above this function's own call site.
func _replan_cheap(horde: Horde) -> void:
	var candidates: Array[Vector2i] = []
	for neighbor in HexCoord.neighbors(horde.hex_coord):
		var cell := _hex_grid_map.get_cell(neighbor)
		if cell and cell.is_passable():
			candidates.append(neighbor)
	if candidates.is_empty():
		return
	horde.path = [candidates[_rng.randi_range(0, candidates.size() - 1)]]
	horde.state = GameEnums.HordeState.WANDERING

## Exposed for SaveLoadManager (Phase 2.8) — mirrors WallManager's own
## get_save_state()'s {segments, next_id} shape.
func get_save_state() -> Dictionary:
	return {"hordes": _hordes.duplicate(), "next_id": _next_id}

## Restores hordes from a save. Each horde's in-flight drift path is
## deliberately discarded (see Horde.path's own doc comment) — HordeManager
## replans fresh the next time it moves, same "cheap to re-derive, not worth
## saving" call Zone of Control coverage makes.
##
## **Disclosed limitation (adversarial review, Phase 5.10 pass), not solved
## this pass:** a horde saved mid-ATTACKING (actively sieging a wall) keeps
## its `state` (an @export field, genuinely restored) but always loses its
## `path` here regardless of state — already true before FAR_SIMULATION_RADIUS
## existed, since _replan() has never read `state` before picking a fresh
## target either. What FAR_SIMULATION_RADIUS adds on top: if that wall
## happens to sit farther than FAR_SIMULATION_RADIUS from every placed
## building (a real, if unusual, "distant outpost perimeter" layout —
## WallManager has no proximity dependency on BuildingManager), the
## reloaded horde's fresh replan takes _replan_cheap()'s single undirected
## random-neighbor hop instead of a real A* search — modestly less likely
## to route back through the same wall edge than the old multi-hex search
## was, though neither path is actually wall-aware (wall-crossing is only
## ever checked per-step inside _advance_horde(), never inside pathfinding
## itself), so this was always a matter of odds, not a guarantee, even
## before this pass. A real fix would need saving which segment (if any) a
## horde was actively sieging and re-deriving a route back to it on load —
## a bigger, save-format-touching change than this pass's scope.
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
