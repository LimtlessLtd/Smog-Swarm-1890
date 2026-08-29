class_name ZombieSwarmManager
extends Node

## Owns every live ZombieSwarm and decides how the ~60,000-entity budget is
## split between them — design_doc.md §2.1's tactical layer, decisions
## D12-D15.
##
## **Entity counts are a VIEW, never a source of truth.** Each frame a swarm's
## size is driven toward what the strategic layer already says is standing on
## that hex: Horde.size for a roaming horde, InfestationManager.resident_count_at()
## for the hex's own population. Nothing is ever transferred INTO the tactical
## layer, so nothing can be lost or double-counted by it, and §2.1's
## conservation requirement ("a horde dissolves into entities and re-condenses
## on exit, conserving its count") is structural rather than maintained.
##
## That is a narrower reading of D14 than "the horde is replaced by entities",
## and it is deliberate (D42): Horde is what CombatCoordinator fights,
## TerritoryController tests for, HordeManager paths and SaveLoadManager
## saves. Moving ownership into a packed array would have meant teaching all
## four about a second kind of enemy for no gameplay difference — the player
## sees individuals either way, kills them through the same combat, and
## watches the same count fall.
##
## Allocation is two passes, both nearest-observer-first:
##   1. Hordes, up to HORDE_BUDGET_FRACTION of the budget. A besieging horde
##      is the one thing on the map the player is definitely looking at, so it
##      is served before a Hive Core's resident millions can eat the budget.
##   2. Residents, with everything pass 1 did not use.
## §2.1's London figure falls out of pass 2: the camera hex takes what it can
## hold and the ~1.84 million behind it stay a number.
##
## Reallocation runs on a timer, not every frame — creating and destroying
## packed arrays is the expensive part, while moving zombies is not. Anchors
## and stepping ARE every frame, so a horde's crowd streams after it
## continuously.

## design_doc.md §2.1's measured budget. bench_zombie_scale.gd puts the hard
## ceiling at 250,000 packed movers spending the ENTIRE 16.6 ms frame on
## movement alone; scripts/test/bench_zombie_swarm.gd measures this class's
## real step, which does more than that benchmark's bare integration.
const ENTITY_BUDGET: int = 60_000

## Share of the budget reserved for hordes before residents get any. Not a
## floor a horde must reach — pass 2 takes back whatever pass 1 leaves — just
## a ceiling on how much of the frame one enormous horde may claim.
const HORDE_BUDGET_FRACTION: float = 0.5

const ALLOCATION_INTERVAL_SECONDS: float = 0.5

## A resident population fills its hex rather than clustering: three quarters
## of the circumradius, so a crowd reads as "this ground is infested" and not
## as "a horde is parked at the exact centre".
const RESIDENT_SPREAD: float = HexCoord.HEX_SIZE * 0.75

## A horde's crowd grows with its size — same sqrt fan-out
## TacticalEntityLayer._crowd_spread_radius() already applies, so a horde of
## 500 covers more ground than a horde of 5 instead of packing into one blob.
const HORDE_BASE_SPREAD: float = 20.0
const HORDE_SPREAD_REFERENCE_COUNT: int = 5

## Below this frame-to-frame anchor movement a group keeps its current facing,
## matching TacticalEntityLayer.MIN_FACING_MOVE_DISTANCE's purpose: a crowd
## jittering in place should not spin through all eight sprites.
const MIN_FACING_MOVE_DISTANCE: float = 0.5

## Source id reserved for a hex's own resident population. Horde ids start at
## 1 (HordeManager._next_id), so 0 can never collide with one.
const RESIDENT_SOURCE_ID: int = 0

signal allocation_changed(live_hexes: int, entities: int)

@export var live_hex_tracker_path: NodePath
@export var horde_manager_path: NodePath
@export var infestation_manager_path: NodePath  ## Optional — unset means only hordes instantiate individuals, never a hex's resident population.

var _live_hex_tracker: LiveHexTracker
var _horde_manager: HordeManager
var _infestation_manager: InfestationManager

## Group key -> Array[ZombieSwarm] of ZombieSwarm.LANE_COUNT.
##
## A resident crowd is keyed by its hex, Vector3i(q, r, RESIDENT_SOURCE_ID); a
## horde's crowd is keyed by the HORDE, Vector3i(0, 0, horde.id). Keying a
## horde by its hex too would have re-scattered every crowd the moment its
## horde crossed a hex boundary, which is the one place §2.1 explicitly says
## the player must not see a pop ("the seam is a pure representation change,
## so the player never sees a horde 'pop' — it arrives as individuals").
var _groups: Dictionary = {}
## Insertion order of _groups' keys, so the renderer sees a stable sequence
## rather than Dictionary order changing under it every reallocation.
var _group_order: Array[Vector3i] = []
var _group_anchor: Dictionary = {}  # Vector3i -> Vector2, last frame's anchor, for facing.

## Positions restored from a save, consumed by the first allocation that
## builds groups on that hex and dropped afterwards. See load_save_state().
var _restored_positions: Dictionary = {}  # Vector2i -> PackedFloat32Array

var _elapsed: float = 0.0
var _entity_count: int = 0


func _ready() -> void:
	if live_hex_tracker_path != NodePath():
		_live_hex_tracker = get_node(live_hex_tracker_path)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
	if infestation_manager_path != NodePath():
		_infestation_manager = get_node(infestation_manager_path)
	if _live_hex_tracker:
		_live_hex_tracker.live_hexes_changed.connect(_on_live_hexes_changed)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= ALLOCATION_INTERVAL_SECONDS:
		_elapsed = 0.0
		allocate()
	step(delta)


## --- Public state -----------------------------------------------------------

func get_entity_count() -> int:
	return _entity_count


func get_group_count() -> int:
	return _group_order.size()


## Every live swarm, in stable group order. The renderer walks this and hands
## each swarm's buffer to a MultiMesh; nothing else should need it.
func get_swarms() -> Array:
	var out: Array = []
	for key: Vector3i in _group_order:
		for swarm: ZombieSwarm in _groups[key]:
			out.append(swarm)
	return out


## Total individuals instantiated on one hex, across every source on it.
## Reads each swarm's own hex_coord rather than its group key, because a
## horde's key is the horde (see _groups) and only the swarm tracks where that
## horde currently stands.
func entity_count_at(coord: Vector2i) -> int:
	var total := 0
	for key: Vector3i in _group_order:
		for swarm: ZombieSwarm in _groups[key]:
			if swarm.hex_coord == coord:
				total += swarm.size()
	return total


## --- Allocation -------------------------------------------------------------

func _on_live_hexes_changed(_live: Array[Vector2i]) -> void:
	_elapsed = 0.0
	allocate()


## Rebuilds the whole allocation. Public so a test can drive it without
## waiting on _process, and so a load can apply immediately.
func allocate() -> void:
	if not _live_hex_tracker:
		return
	var live := _live_hex_tracker.get_live_hexes()
	var observer := _live_hex_tracker.get_observer_position()
	var ordered := _sorted_by_distance(live, observer)

	var wanted: Dictionary = {}  # Vector3i -> int
	var horde_budget := int(ENTITY_BUDGET * HORDE_BUDGET_FRACTION)
	var spent := _allocate_hordes(ordered, wanted, horde_budget)
	spent += _allocate_residents(ordered, wanted, ENTITY_BUDGET - spent)

	_apply(wanted)
	_entity_count = spent
	# One division for every swarm, from the whole live population. See
	# ZombieSwarm.SLICE_TARGET_ENTITIES for the 4x measurement that moved this
	# decision out of the individual swarm and up here.
	var slices := ZombieSwarm.slices_for(spent)
	for key: Vector3i in _group_order:
		for swarm: ZombieSwarm in _groups[key]:
			swarm.slices = slices
	allocation_changed.emit(live.size(), spent)


## Nearest first. Distance is measured from the camera's own world position to
## each hex CENTER — a hex is 5 miles across, so its center is the only
## representative point that does not depend on which corner the camera
## happens to sit in.
func _sorted_by_distance(live: Array[Vector2i], observer: Vector2) -> Array[Vector2i]:
	var ordered := live.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := observer.distance_squared_to(HexCoord.axial_to_world(a))
		var db := observer.distance_squared_to(HexCoord.axial_to_world(b))
		if da == db:
			return a.x < b.x or (a.x == b.x and a.y < b.y)  ## Ties broken by axial order so the allocation is stable frame to frame.
		return da < db)
	return ordered


func _allocate_hordes(ordered: Array[Vector2i], wanted: Dictionary, budget: int) -> int:
	if not _horde_manager:
		return 0
	var spent := 0
	for coord in ordered:
		if spent >= budget:
			break
		for horde in _horde_manager.get_hordes_at(coord):
			if spent >= budget:
				break
			var take := mini(horde.size, budget - spent)
			if take <= 0:
				continue
			wanted[Vector3i(0, 0, horde.id)] = take
			spent += take
	return spent


## Residents are a hex's stored count only — a horde standing on the hex is
## already instantiated by pass 1, and InfestationManager.zombie_count_at()
## deliberately sums both (D37), so using it here would draw every horde
## zombie twice.
func _allocate_residents(ordered: Array[Vector2i], wanted: Dictionary, budget: int) -> int:
	if not _infestation_manager:
		return 0
	var spent := 0
	for coord in ordered:
		if spent >= budget:
			break
		var take := mini(_infestation_manager.resident_count_at(coord), budget - spent)
		if take <= 0:
			continue
		wanted[Vector3i(coord.x, coord.y, RESIDENT_SOURCE_ID)] = take
		spent += take
	return spent


## Creates, resizes and destroys groups to match `wanted`. A group that keeps
## existing keeps its zombies' positions — this is what makes a horde's crowd
## survive a reallocation rather than re-scattering twice a second.
func _apply(wanted: Dictionary) -> void:
	var hordes_by_id := _hordes_by_id()
	for key: Vector3i in _groups.keys():
		if not wanted.has(key):
			_groups.erase(key)
			_group_order.erase(key)
			_group_anchor.erase(key)

	for key: Vector3i in wanted:
		var count: int = wanted[key]
		var lanes: Array = _groups.get(key, [])
		var fresh := lanes.is_empty()
		if fresh:
			lanes = []
			for lane in ZombieSwarm.LANE_COUNT:
				var swarm := ZombieSwarm.new(_group_seed(key, lane))
				swarm.lane = lane
				lanes.append(swarm)
			_groups[key] = lanes
			_group_order.append(key)
		_update_group_shape(key, lanes, hordes_by_id)
		# Lane sizes sum to the group's count exactly: lane L takes every
		# (LANE_COUNT)th zombie starting at L, so the remainder is spread one
		# per lane rather than dumped on the last one.
		for lane in ZombieSwarm.LANE_COUNT:
			var lane_count := count / ZombieSwarm.LANE_COUNT
			if lane < count % ZombieSwarm.LANE_COUNT:
				lane_count += 1
			lanes[lane].set_count(lane_count)
		if fresh:
			_restore_positions(key, lanes)


## Anchor, spread and facing for a group, from whichever strategic object owns
## its count. Called on every reallocation and every frame (see _step()).
func _update_group_shape(key: Vector3i, lanes: Array, hordes_by_id: Dictionary) -> void:
	var coord := Vector2i(key.x, key.y)
	var anchor := HexCoord.axial_to_world(coord)
	var spread := RESIDENT_SPREAD
	if key.z != RESIDENT_SOURCE_ID:
		var horde: Horde = hordes_by_id.get(key.z)
		if horde == null:
			# Killed between reallocations. Leave the crowd exactly where it
			# is until the next allocate() erases the group — an anchor of
			# Vector2i.ZERO would drag it to the map's origin for up to
			# ALLOCATION_INTERVAL_SECONDS first.
			return
		coord = horde.hex_coord
		anchor = HexCoord.axial_to_world(coord) + horde.local_position
		spread = _horde_spread(horde.size)

	var previous: Vector2 = _group_anchor.get(key, anchor)
	var facing: GameEnums.Facing8 = lanes[0].facing
	var moved := anchor - previous
	if moved.length() >= MIN_FACING_MOVE_DISTANCE:
		facing = FacingUtil.from_delta(moved)
	_group_anchor[key] = anchor

	for swarm: ZombieSwarm in lanes:
		swarm.anchor = anchor
		swarm.spread = spread
		swarm.facing = facing
		swarm.hex_coord = coord


func _horde_spread(size: int) -> float:
	return HORDE_BASE_SPREAD * sqrt(maxf(1.0, float(size) / float(HORDE_SPREAD_REFERENCE_COUNT)))


## Built once per frame rather than per group: HordeManager.get_hordes_at() is
## a linear scan, so asking it per group per frame is O(groups x hordes) for a
## lookup that is O(1) once the map exists.
func _hordes_by_id() -> Dictionary:
	var out: Dictionary = {}
	if not _horde_manager:
		return out
	for horde in _horde_manager.get_all_hordes():
		out[horde.id] = horde
	return out


## Distinct per (hex, source, lane) so two crowds standing on the same hex do
## not scatter into identical shapes.
func _group_seed(key: Vector3i, lane: int) -> int:
	return absi(key.x * 73856093 + key.y * 19349663 + key.z * 83492791 + lane * 2654435761)


## --- Per-frame --------------------------------------------------------------

## Re-anchors every group (hordes move continuously) and advances every swarm.
## Public for the same reason allocate() is: a test needs to advance the layer
## a fixed number of steps rather than depend on how many frames elapsed.
func step(delta: float) -> void:
	if _group_order.is_empty():
		return
	var hordes_by_id := _hordes_by_id()
	for key: Vector3i in _group_order:
		var lanes: Array = _groups[key]
		_update_group_shape(key, lanes, hordes_by_id)
		for swarm: ZombieSwarm in lanes:
			swarm.step(delta)


## --- Save/load (D15) --------------------------------------------------------

## One flat float32 array of x,y pairs per hex, every group on that hex
## concatenated in group order. Deliberately not keyed by horde id: a horde
## that merged, split or was killed between save and load would strand its
## slice, and the point of saving positions is that a crowd does not visibly
## teleport, not that any individual zombie is the same one.
func get_save_state() -> Dictionary:
	var out: Dictionary = {}
	for key: Vector3i in _group_order:
		var lanes: Array = _groups[key]
		if lanes.is_empty():
			continue
		var coord: Vector2i = lanes[0].hex_coord
		var pool: PackedFloat32Array = out.get(coord, PackedFloat32Array())
		for swarm: ZombieSwarm in lanes:
			pool.append_array(swarm.get_positions())
		out[coord] = pool
	return out


## Positions are held until the allocation that needs them. Loading at
## Strategic zoom instantiates nothing at all (LiveHexTracker's live set is
## empty there), so the pool has to outlive the load itself; each hex's entry
## is consumed once, by the first group created on it.
func load_save_state(state: Dictionary) -> void:
	_restored_positions = state.duplicate()
	_groups.clear()
	_group_order.clear()
	_group_anchor.clear()
	_entity_count = 0
	allocate()


func _restore_positions(_key: Vector3i, lanes: Array) -> void:
	if lanes.is_empty():
		return
	var coord: Vector2i = lanes[0].hex_coord
	if not _restored_positions.has(coord):
		return
	var pool: PackedFloat32Array = _restored_positions[coord]
	var offset := 0
	for swarm: ZombieSwarm in lanes:
		offset = swarm.load_positions(pool, offset)
	if offset >= pool.size():
		_restored_positions.erase(coord)
	else:
		_restored_positions[coord] = pool.slice(offset)
