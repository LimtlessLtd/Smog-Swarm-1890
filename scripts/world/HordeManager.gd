class_name HordeManager
extends Node

## Horde spawn, drift (WANDERING), attraction to noise/light (ATTRACTED),
## and wall siege (ATTACKING). Wired as a Main.tscn sibling of
## HexGridMap/BuildingManager, same pattern as every other top-level manager.
##
## - Starting-horde seeding: a handful of small hordes placed on frontier
##   hexes at least MIN_SPAWN_DISTANCE_FROM_SETTLEMENT from any settlement,
##   seeded deterministically (HORDE_SEED — same fixed-seed family as
##   HexMapGenerator's terrain/soil noise, 1890/1891/1892).
## - WANDERING drift: each horde picks a random frontier hex within
##   DRIFT_TARGET_RADIUS, routes to it via HexPathfinder, then walks there
##   continuously in real-time world-space (MovementStepper), not hex-to-hex.
## - Casualty-conversion spawn source (add_casualty_zombies()), wired to
##   BuildingManager.building_ruined: finds-or-creates a WANDERING horde at a
##   ruined housing building's hex and grows it by its housed population at
##   the moment it fell.
## - _on_ambient_spawn_day() rolls a flat daily chance to seed one tiny (1-3)
##   horde on ambient wilderness, independent of the starting seed/casualty
##   conversion/noise system.
## - _check_merges()/_check_splits(): rolled once per movement tick — co-located
##   hordes can combine, a large enough horde can fragment in two.
## - ATTACKING: _advance_horde() checks whether the next step in a horde's
##   drift path crosses an unbreached WallSegment — if so, it sieges that
##   segment (_siege_wall(), with a siege-damage bonus and Ditch/Oil Pit
##   counter-damage) instead of moving, reverting to WANDERING once the
##   segment breaches and it steps through. This is whichever segment the
##   horde's own drift happens to walk into, not a deliberate seek-the-nearest-wall behavior.
## - ATTRACTED: _replan() (called whenever a horde's path empties) checks
##   NoiseManager first, before falling back to the unbiased WANDERING pick —
##   a horde within ATTRACTION_AWARENESS_RADIUS of a hex whose noise clears
##   ATTRACTION_THRESHOLD paths toward the loudest one instead. See
##   _pick_attraction_target() for the local-not-global scoping.
##
## Movement is continuous (MovementStepper.advance_toward_hex(), world-units/
## second, terrain- and logistics-scaled), walking smoothly toward the next
## hex's center every _process() frame and steering around static obstacles
## (props/buildings) the same way UnitOrderController does. The wall-blocking
## check happens per hex-crossing, not once per tick — a multi-hex catch-up
## burst at high TickManager speed must not glide through an un-breached
## wall on an intermediate hex. Siege damage against a blocked wall is
## continuous, scaled by however much of a frame's `delta` the horde spent
## blocked (converted against the old per-LOGIC_TICK_SECONDS rate) rather
## than applied once per periodic tick.
##
## LOGIC_TICK_SECONDS no longer gates movement or siege damage — it only
## drives _check_merges()/_check_splits() at a fixed real-world rate.
##
## Not wired here, each blocked on a system that doesn't exist yet:
##   - ATTACKING against a deliberately-sought hex (undefended building or
##     ZoC-covered-but-unwalled hex) — today ATTACKING only ever happens as a
##     byproduct of a route crossing a wall; needs building-siege awareness
##     wired into the pathing/targeting layer, not just CombatCoordinator's
##     reactive contact-triggered siege.
##   - Reconnaissance ETA/countdown presentation layer — the underlying
##     ATTRACTED mechanic is real, no UI reads it yet.
##   - Threat Meter HUD — NoiseManager.get_noise_at() is real and queryable;
##     nothing in MainHUD read it at the time this was written.
##   - Horde-size/spawn-frequency ramp-up over campaign time — no campaign
##     system exists yet; STARTING_HORDE_COUNT/SIZE are a flat one-time seed.
##
## Performance: the real per-horde expense isn't continuous movement itself
## (MovementStepper's per-frame math is a handful of vector ops) — it's
## HexPathfinder.find_path()'s A* search, called from _replan() every time a
## horde's drift path empties. That search's open set is a plain Dictionary
## scanned linearly for the lowest f_score, not a binary heap, and at
## real horde-scale (hundreds-to-thousands of Horde instances) that adds up
## for hordes nobody's anywhere near. FAR_SIMULATION_RADIUS/_is_far_from_player()/
## _replan_cheap() give a WANDERING horde outside that radius of every placed
## building a one-hex random-neighbor hop instead of a real A* search — still
## "no deliberate beeline anywhere" (WANDERING's own design intent), just
## without paying for the graph search. ATTRACTED and ATTACKING hordes are
## exempt regardless of distance: ATTRACTED needs to reach a real target
## efficiently, and ATTACKING only triggers by physically reaching a wall —
## already player-built, so already "near a building" in practice — and its
## `path` isn't empty (it's blocked), so _replan() never runs for it at all.

signal horde_spawned(horde: Horde)
signal horde_moved(horde: Horde, from_coord: Vector2i, to_coord: Vector2i)
signal horde_size_changed(horde: Horde, delta: int)
signal horde_removed(horde: Horde)

@export var hex_grid_map_path: NodePath
@export var logistics_network_path: NodePath  ## Optional — road/rail/canal discount, applied as a continuous speed bonus (see MovementStepper).
@export var building_manager_path: NodePath   ## Optional — ruin-casualty spawn source (building_ruined), and local obstacle avoidance (buildings steer continuous movement around them regardless of Tactical hydration). Unset skips both.
@export var wall_manager_path: NodePath       ## Optional — horde-vs-wall siege; unset means walls never block a horde's drift.
@export var local_detail_manager_path: NodePath  ## Optional — prop obstacle avoidance; props (trees/rocks/etc.) only exist as live data while their hex is Tactical-hydrated (LocalDetailManager.get_props_at()).
@export var noise_manager_path: NodePath      ## Optional — ATTRACTED state; unset means a horde only ever WANDERs.

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

const HORDE_SEED: int = 1892  ## Same seed-numbering convention as HexMapGenerator's terrain/soil noise (1890/1891) — deterministic starting conditions.

const STARTING_HORDE_COUNT: int = 3
const STARTING_HORDE_SIZE_MIN: int = 10
const STARTING_HORDE_SIZE_MAX: int = 25
const MIN_SPAWN_DISTANCE_FROM_SETTLEMENT: int = 4  ## Hordes never spawn within this many hexes of a settlement.

## Real-time seconds (scaled by Engine.time_scale) between _check_merges()/
## _check_splits(). Doesn't gate movement or siege damage (both continuous,
## every frame). Deliberately matches UnitOrderController.LOGIC_TICK_SECONDS.
const LOGIC_TICK_SECONDS: float = 20.0
const DRIFT_TARGET_RADIUS: int = 5  ## Hex radius a fresh drift target is picked from when a horde needs to replan.

const ATTRACTION_AWARENESS_RADIUS: int = 6  ## Hex radius a horde scans for a noise/light source above threshold when replanning — same order of magnitude as DRIFT_TARGET_RADIUS, not colony-wide.

## A WANDERING horde farther than this many hexes from EVERY placed building
## skips real A* pathfinding (_replan_cheap()) for a one-hex random hop.
## >= ATTRACTION_AWARENESS_RADIUS so a horde within noise-attraction range of
## the player's buildings never reads as "far" while it's actively relevant.
##
## The far/near classification is re-derived fresh on every replan, purely
## positional — no hysteresis/debounce. A horde lingering right at this
## radius can alternate between a cheap one-hex hop and a real ~5-hex path
## replan to replan (confirmed via simulation). Harmless (both branches
## always leave path/state consistent) — a purely cosmetic bursty-direction
## movement signature at the boundary, not worth a stateful debounce.
const FAR_SIMULATION_RADIUS: int = 10

## Noise level (NoiseManager.get_noise_at()) a hex must clear before a horde
## within range walks toward it instead of continuing WANDERING drift.
## This is the BASELINE — Horde.mean_susceptibility() modulates it per-horde
## (see _pick_attraction_target()): a horde with average susceptibility
## (mean ~1.0) reacts right at this value.
const ATTRACTION_THRESHOLD: float = 3.0

const ENTITY_RADIUS: float = 20.0  ## Clearance radius presented to MovementStepper.steer_around_obstacles() — matches UnitOrderController.ENTITY_RADIUS.

## Day/Night movement multipliers. Night's +50% is an exact design number,
## applied literally. Day's 0.35x was tuned down from 0.65x — a 0.65x
## day/0.65 night split still read as a brisk walk, not the sluggish shamble
## intended, especially stacked with terrain/logistics speed multipliers
## (was 1.5/0.65 ≈ 2.3x faster at night, now 1.5/0.35 ≈ 4.3x).
const DAY_MOVE_SPEED_MULTIPLIER: float = 0.35
const NIGHT_MOVE_SPEED_MULTIPLIER: float = 1.5

## Flat daily chance to seed a tiny ambient horde outside the starting seed
## and casualty conversion — reuses seed_starting_hordes()'s own
## _spawnable_coords()/Horde.new() machinery.
const AMBIENT_SPAWN_CHANCE_PER_DAY: float = 0.35
const AMBIENT_HORDE_SIZE_MIN: int = 1
const AMBIENT_HORDE_SIZE_MAX: int = 3

const MERGE_CHANCE_PER_TICK: float = 0.1   ## Rolled once per co-located pair, per tick.
const SPLIT_CHANCE_PER_TICK: float = 0.05  ## Rolled once per eligible horde, per tick.
const SPLIT_MIN_SIZE: int = 20             ## A horde must be at least this big to be eligible to fragment.

const WALL_SIEGE_DAMAGE_MULTIPLIER: float = 2.0  ## A horde hits a wall harder than it'd hit a unit.

## Zombie-side mirror of CombatCoordinator.DAY_DAMAGE_MULTIPLIER — doubles a
## horde's OUTGOING combat damage at night. Applied at every real attack:
## this class's own _siege_wall(), CombatCoordinator._engage() (unit-vs-horde),
## and CombatCoordinator._siege_buildings() (horde-vs-building).
const NIGHT_AGGRESSION_MULTIPLIER: float = 2.0

## Static so CombatCoordinator can reach it via the class name alone — no
## wired instance reference needed, same as this class reading
## TimeCycleManager.is_day()/is_night() directly rather than caching a flag.
static func get_night_aggression_multiplier() -> float:
	return NIGHT_AGGRESSION_MULTIPLIER if TimeCycleManager.is_night() else 1.0

## Flat headcount-worth chip damage per siege tick against a besieging
## horde, converted through Horde.HP_PER_ZOMBIE like any other combat
## damage — a sufficiently ditched-and-pitted wall can grind a small horde
## to nothing before it ever breaches.
const DITCH_COUNTER_DAMAGE: float = 3.0
const OIL_PIT_COUNTER_DAMAGE: float = 5.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  ## Background-simulation infrastructure — shouldn't freeze if the SceneTree is ever paused.
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
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

	# duplicate(): a horde can be removed mid-loop (ground down to 0 by
	# Ditch/Oil Pit counter-damage while sieging a wall) — iterating the live
	# array while erasing from it would skip entries.
	for horde: Horde in _hordes.duplicate():
		_advance_horde(horde, delta)

	_logic_tick_timer += delta
	while _logic_tick_timer >= LOGIC_TICK_SECONDS:
		_logic_tick_timer -= LOGIC_TICK_SECONDS
		_check_merges()
		_check_splits()

func get_all_hordes() -> Array[Horde]:
	return _hordes.duplicate()

## Sums the real-time seconds remaining to walk `horde`'s current `path`,
## reusing the same per-edge _movement_speed() continuous movement applies
## frame-by-frame — summed forward here instead of applied once. Purely a
## math query; "is this horde within observed range" is the caller's job
## (Fog of War VISIBLE — see MainHUD's own consumer), not this method's.
## Returns 0.0 for a horde with an empty path (arrived, or never replanned).
func get_eta_seconds(horde: Horde) -> float:
	if horde.path.is_empty():
		return 0.0

	var total := 0.0
	var from_coord := horde.hex_coord

	# First leg is partial — the horde is already partway across it
	# (local_position), not starting fresh from the hex center.
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

## Exposed for CombatCoordinator — a horde reduced to 0 (Horde.apply_remaining_hp())
## is that caller's cue to remove it, mirroring UnitManager.remove_unit()/
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

## Finds the first existing horde at `coord` and grows it by `count`, or
## spawns a fresh WANDERING one there if none exists — either way the loss
## becomes a real, trackable threat rather than a number disappearing.
## Public (not just a signal handler) so any future combat-casualty trigger
## can reuse this exact accumulation logic.
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

## `lost_population` may legitimately be 0 (an industrial/agricultural
## building with no housed population) — add_casualty_zombies() already
## no-ops on count <= 0.
func _on_building_ruined(instance: BuildingInstance, lost_population: int) -> void:
	add_casualty_zombies(instance.hex_coord, lost_population)

## Reuses _spawnable_coords() exactly as seed_starting_hordes() does, so the
## same "far enough from a settlement" rule applies.
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

## Scoped to hordes sharing the exact same hex_coord — the same granularity
## add_casualty_zombies() merges into — checked once per movement tick, one
## merge roll per co-located pair per tick rather than a guaranteed instant
## cascade on a crowded hex.
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

## Splits roughly in half; the new fragment starts WANDERING from the same
## hex and gets its own fresh drift replan next tick. Iterates a
## duplicate() snapshot since this appends fresh hordes to _hordes mid-loop.
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

## Mirrors BuildingManager.seed_starting_buildings()'s own "only if nothing's
## placed yet" guard. A load right after boot (SaveLoadManager.load_save_hordes())
## clears/replaces _hordes before this would otherwise run.
func seed_starting_hordes() -> void:
	if not _hordes.is_empty() or not _hex_grid_map:
		return
	var candidates := _spawnable_coords()
	for _i in range(STARTING_HORDE_COUNT):
		if candidates.is_empty():
			break  # Map too small/dense for enough valid spawn points — seed what we could.
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
## (more than one is possible at high TickManager speeds), emitting
## horde_moved once per boundary actually crossed, in order — CombatCoordinator/
## StrategicOverlayManager/TerritoryController all depend on that per-crossing contract.
##
## The wall peek happens on EVERY hex-crossing attempt within this loop, not
## just once per old tick, so a multi-hex catch-up burst can't glide through
## an un-breached wall on an intermediate hex.
##
## The replan check is INSIDE this loop (top of every iteration), not once
## before it: a single _replan() call followed by draining whatever path it
## produced would exit the instant `path` emptied even with `remaining`
## budget left over, silently discarding it instead of replanning fresh and
## continuing. This matters most for a far horde — _replan_cheap()'s path is
## always exactly one hex, so a far horde would hit that gap roughly 5x more
## often per unit of `delta` than a near horde's ~5-hex real path, measurably
## crawling slower at high TickManager speed than it did before
## FAR_SIMULATION_RADIUS existed. Re-checking path.is_empty() inside the loop
## lets a far horde take several cheap 1-hex replans in the same frame
## budget a near horde spends on one real path, restoring the "advances
## several hexes per frame at high speed" behavior every horde had before
## this optimization. No infinite-loop risk: _replan_cheap()'s candidates are
## always real HexCoord.neighbors() (never the horde's own current hex, so
## distance is always > 0), and a _replan() that finds no valid target
## leaves `path` empty, hitting the early return below on the next loop check.
func _advance_horde(horde: Horde, delta: float) -> void:
	# A Dragoon's charge stuns the horde it hits — see
	# Horde.stun_seconds_remaining's own doc comment. A stunned horde doesn't
	# move or progress a wall siege; it resumes the same path/state the
	# instant the stun expires.
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
			# point_a/point_b are real placement geometry, not hex-edge-locked
			# — get_blocking_segment() checks the horde's actual straight-line
			# travel this step against every nearby piece's own geometry.
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

## Damages `segment` with the siege bonus (WALL_SIEGE_DAMAGE_MULTIPLIER), and
## applies Ditch/Oil Pit counter-damage back on the besieging horde,
## converted through the same Horde.apply_remaining_hp() every other
## combat-damage source uses — a sufficiently defended segment can grind a
## small horde to nothing before it ever breaches.
##
## `seconds` is whatever fraction of this frame the horde spent blocked,
## scaled against LOGIC_TICK_SECONDS so total damage-per-real-second matches
## the old once-per-tick lump exactly.
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

## ATTRACTED is checked FIRST on every replan, before falling back to the
## unbiased WANDERING pick — a horde within range of a noise/light source
## above threshold takes priority over "no deliberate beeline" once there's
## something to be deliberate about. Re-evaluated fresh every time a horde's
## path empties (cheap to re-derive, not a persistent commitment) rather
## than a mid-route redirect — a horde already walking somewhere doesn't
## abandon that route because a nearer hex got louder mid-walk; it picks
## that up on its next replan instead.
func _replan(horde: Horde) -> void:
	var attraction_target := _pick_attraction_target(horde.hex_coord, horde)
	var is_attracted := attraction_target != horde.hex_coord
	# An ATTRACTED horde always gets the real path below — it has a specific
	# target to reach. A plain WANDERING horde far from every building skips
	# the expensive A* search entirely.
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
		# Cosmetic gap, not functional: if this ATTRACTED walk later crosses
		# an unbreached wall, _advance_horde()'s breach-through code
		# unconditionally relabels the horde WANDERING again (it predates
		# ATTRACTED existing) — `path` is unaffected and keeps walking toward
		# the same target regardless, and the label self-corrects on this
		# method's next run.

## Purely positional, re-derived every time against NoiseManager's per-hex
## field — no persistent "am I currently attracted" flag to keep in sync,
## matching Zone of Control/Fog of War VISIBLE/WallManager.is_legacy_segment()'s
## own derived-not-stored convention. Returns `from_coord` itself (the same
## no-op sentinel _pick_drift_target() uses) when no NoiseManager is wired,
## nothing in range clears ATTRACTION_THRESHOLD, or the loudest hex in range
## is the horde's own current hex.
func _pick_attraction_target(from_coord: Vector2i, horde: Horde) -> Vector2i:
	if not _noise_manager:
		return from_coord
	var candidate := _noise_manager.get_loudest_hex_within(from_coord, ATTRACTION_AWARENESS_RADIUS)
	if candidate == from_coord:
		return from_coord
	# A horde whose zombies skew jumpy (mean_susceptibility() > 1.0) reacts
	# to fainter noise than ATTRACTION_THRESHOLD alone would allow; a duller
	# horde needs a louder source. Threshold scales inversely with
	# susceptibility so "more susceptible" means "reacts to less."
	var effective_threshold := ATTRACTION_THRESHOLD / maxf(0.01, horde.mean_susceptibility())
	if _noise_manager.get_noise_at(candidate) < effective_threshold:
		return from_coord
	return candidate

## An unbiased (any direction) pick from the ring of hexes exactly
## DRIFT_TARGET_RADIUS away, filtered to passable frontier ground. Returns
## `from_coord` itself (a no-op sentinel _replan() checks for) if nothing in
## the ring qualifies, e.g. near a map edge or deep inside secured territory.
func _pick_drift_target(from_coord: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for coord in HexCoord.hex_ring(from_coord, DRIFT_TARGET_RADIUS):
		var cell := _hex_grid_map.get_cell(coord)
		if cell and cell.is_passable() and cell.is_frontier():
			candidates.append(coord)
	if candidates.is_empty():
		return from_coord
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

## Is `coord` farther than FAR_SIMULATION_RADIUS from EVERY placed building?
## O(buildings) per call — cheap at this project's real building-count scale
## (dozens, not thousands; see HexPathfinder.find_path()'s own doc comment
## for the same "not worth a spatial index yet" call at a similar scale). No
## BuildingManager wired means no way to tell near from far — defaults to
## "not far" (full fidelity) rather than degrading every horde silently.
##
## Cadence: for a FAR horde specifically, _replan_cheap()'s path is always
## exactly one hex, so this runs about once per hex crossed — the same order
## of frequency as MovementStepper's own per-frame math once a fast catch-up
## frame drains several cheap replans in a row (see _advance_horde()'s own
## doc comment). Still categorically cheaper than what it replaced: a flat
## O(buildings) linear scan beats HexPathfinder.find_path()'s A* search
## (naive linearly-scanned open set) even called 5x as often.
func _is_far_from_player(coord: Vector2i) -> bool:
	if not _building_manager:
		return false
	for building in _building_manager.get_all_buildings():
		if HexCoord.distance(coord, building.hex_coord) <= FAR_SIMULATION_RADIUS:
			return false
	return true

## No HexPathfinder.find_path() call — an immediate one-hex hop to a
## uniformly-random passable neighbor of the horde's own current hex. Just as
## undirected as the real _pick_drift_target()'s ring-pick, without paying
## for the graph search. Leaves horde.path empty (tried again next frame) if
## every neighbor happens to be impassable.
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

## Mirrors WallManager's own get_save_state()'s {segments, next_id} shape.
func get_save_state() -> Dictionary:
	return {"hordes": _hordes.duplicate(), "next_id": _next_id}

## Restores hordes from a save. Each horde's in-flight drift path is
## deliberately discarded (see Horde.path's own doc comment) — HordeManager
## replans fresh the next time it moves, same "cheap to re-derive, not worth
## saving" choice Zone of Control coverage makes.
##
## Known limitation: a horde saved mid-ATTACKING (actively sieging a wall)
## keeps its `state` (an @export field, genuinely restored) but always loses
## its `path` here regardless of state — already true before
## FAR_SIMULATION_RADIUS existed, since _replan() has never read `state`
## before picking a fresh target. If that wall sits farther than
## FAR_SIMULATION_RADIUS from every placed building, the reloaded horde's
## fresh replan takes _replan_cheap()'s single undirected hop instead of a
## real A* search — modestly less likely to route back through the same wall
## edge, though neither path is wall-aware (wall-crossing is only checked
## per-step inside _advance_horde(), never inside pathfinding itself), so
## this was always a matter of odds. A real fix needs saving which segment
## (if any) a horde was actively sieging and re-deriving a route to it on
## load — a save-format-touching change out of this scope.
func load_save_state(hordes: Array[Horde], next_id: int) -> void:
	_hordes = hordes.duplicate()
	for horde in _hordes:
		horde.path.clear()
	_next_id = next_id
	_logic_tick_timer = 0.0

## Terrain (current hex) and logistics (this edge) speed multipliers stacked
## onto MovementStepper.BASE_MOVE_SPEED — the same table the drift route was
## chosen against, plus the Day/Night modifier, stacking multiplicatively
## with terrain/logistics like every other factor here.
func _movement_speed(from_coord: Vector2i, to_coord: Vector2i) -> float:
	var speed := MovementStepper.BASE_MOVE_SPEED
	if _hex_grid_map:
		speed *= HexPathfinder.get_terrain_speed_multiplier(_hex_grid_map.get_cell(from_coord))
	speed *= HexPathfinder.get_logistics_speed_multiplier(_logistics_network, from_coord, to_coord)
	speed *= NIGHT_MOVE_SPEED_MULTIPLIER if TimeCycleManager.is_night() else DAY_MOVE_SPEED_MULTIPLIER
	return speed

## Buildings (always queryable) + props (only where Tactical-hydrated) near
## both the hex a horde currently occupies and the one it's drifting toward.
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
