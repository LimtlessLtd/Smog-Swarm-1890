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
##   - WANDERING drift: each horde periodically (MOVE_INTERVAL_SECONDS,
##     speed-scaled like everything else driven by Engine.time_scale) picks
##     a random frontier hex within DRIFT_TARGET_RADIUS of itself and routes
##     to it via Phase 5.5's HexPathfinder, advancing one hex per interval —
##     "drifts across passable uncleared wilderness ... biased toward open
##     territory rather than a deliberate beeline anywhere" per the design
##     doc: the omnidirectional ring pick supplies "no beeline", and
##     restricting targets to frontier hexes supplies "biased toward open
##     territory" (steers away from player-secured ground).
##
## Deliberately NOT wired here yet — each blocked on a system that doesn't
## exist, same "not implemented, deliberately" convention as every other
## forward-reference already in todo.md:
##   - ATTRACTED (industrial-noise/night-light attraction) — nothing tracks
##     a noise value per building/hex yet.
##   - ATTACKING (sieges, wall targeting, escalation on a won siege) — needs
##     Phase 5.4's CombatEngine.
##   - Casualty-conversion spawning (Phase 5.9) — needs Phase 5.4 combat to
##     produce a casualty from in the first place.
##   - Horde-size/spawn-frequency ramp-up over time (Phase 7.1's Act pacing
##     / Phase 7.6's difficulty presets) — neither campaign system exists yet;
##     STARTING_HORDE_COUNT/SIZE below are a flat one-time seed, not a curve.
##   - LOD-based cheap/expensive simulation switching (design doc's own
##     "Performance" note under 5.10) — no consumer yet to profile against,
##     premature at this scale (a handful of hordes total).

signal horde_spawned(horde: Horde)
signal horde_moved(horde: Horde, from_coord: Vector2i, to_coord: Vector2i)

@export var hex_grid_map_path: NodePath
@export var logistics_network_path: NodePath  ## Optional — same road/rail/canal discount HexPathfinder gives any other route.

var _hex_grid_map: HexGridMap
var _logistics_network: LogisticsNetwork
var _hordes: Array[Horde] = []
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
var _move_timer: float = 0.0

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
## driven off TickManager/TimeCycleManager) between a WANDERING horde
## advancing one hex step along its drift path.
const MOVE_INTERVAL_SECONDS: float = 20.0
## How far (in hexes) a fresh drift target is picked from a horde's current
## position when it needs to replan.
const DRIFT_TARGET_RADIUS: int = 5

func _ready() -> void:
	# Same reasoning as TickManager/TimeCycleManager: background-simulation
	# infrastructure that shouldn't freeze if a future system ever pauses
	# the SceneTree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	_rng.seed = HORDE_SEED
	seed_starting_hordes()

func _process(delta: float) -> void:
	if _hordes.is_empty():
		return
	_move_timer += delta
	while _move_timer >= MOVE_INTERVAL_SECONDS:
		_move_timer -= MOVE_INTERVAL_SECONDS
		for horde in _hordes:
			_advance_horde(horde)

func get_all_hordes() -> Array[Horde]:
	return _hordes.duplicate()

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

func _advance_horde(horde: Horde) -> void:
	if horde.path.is_empty():
		_replan(horde)
	if horde.path.is_empty():
		return  # No valid drift target found this cycle (e.g. boxed in) — try again next tick.
	var next_coord: Vector2i = horde.path.pop_front()
	var from_coord := horde.hex_coord
	horde.hex_coord = next_coord
	horde_moved.emit(horde, from_coord, next_coord)

func _replan(horde: Horde) -> void:
	var target := _pick_drift_target(horde.hex_coord)
	if target == horde.hex_coord:
		return
	var path := HexPathfinder.find_path(_hex_grid_map, horde.hex_coord, target, _logistics_network)
	if path.size() > 1:
		path.remove_at(0)  # path[0] is the horde's own current hex — the walk starts at path[1] onward.
		horde.path = path

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
	_move_timer = 0.0
