class_name LiveHexTracker
extends Node

## Answers one question: which hexes is the player close enough to for
## individual zombies to be worth instantiating? design_doc.md §2.1's
## "a hex is live if..." rule, decision D13.
##
## A hex is live if it holds the camera, neighbours the camera's hex, or
## contains a player unit or building. Nothing else consults zoom, distance or
## fog — the rule is the spec's, verbatim, and lives in exactly one place so
## the budget allocator (ZombieSwarmManager) and anything that follows it
## cannot each grow their own version of it.
##
## **One addition the spec does not state and this class makes explicitly:
## the live set is empty outside Tactical zoom.** §2.1's justification for
## bounding instantiation is observation — "the player cannot detect the
## difference, because they cannot observe 60,000 zombies' worth of ground at
## once" — and at Strategic zoom the player observes no individuals at all
## (TacticalEntityLayer hides itself entirely below
## CameraController.tactical_zoom_threshold). Instantiating a crowd nothing
## can draw is pure cost. The visible consequence is that zooming out and back
## in re-scatters a crowd's internal arrangement; its POSITION does not move,
## because that is the anchor's, and the anchor belongs to the Horde or the
## hex.
##
## Deliberately NOT the same rule as LocalDetailManager's hydration set, which
## looks similar and is not: that one is settled/frontier ground at a
## zoom-derived radius, for terrain and props. This one is a fixed 1-hex
## neighbourhood plus wherever the player actually is. Two questions, two
## classes (CLAUDE.md §1).

## Camera-hex neighbourhood radius. 1 = the camera hex plus its six
## neighbours, exactly as §2.1 states it.
const CAMERA_RADIUS: int = 1

## The set is rebuilt on a timer rather than every frame: it changes only when
## the camera crosses a hex boundary or a unit does, and rebuilding costs
## O(units + buildings). _process delta is scaled by Engine.time_scale, so at
## high game speed this effectively becomes every frame — which is the safe
## direction to be wrong in.
const REFRESH_INTERVAL_SECONDS: float = 0.25

signal live_hexes_changed(live: Array[Vector2i])

@export var camera_path: NodePath
@export var hex_grid_map_path: NodePath
@export var unit_manager_path: NodePath  ## Optional — unset means units do not make their hex live.
@export var building_manager_path: NodePath  ## Optional — unset means buildings do not make their hex live.

var _camera: CameraController
var _hex_grid_map: HexGridMap
var _unit_manager: UnitManager
var _building_manager: BuildingManager

var _live: Dictionary = {}  # Vector2i -> true
var _live_list: Array[Vector2i] = []
var _observer_coord: Vector2i = Vector2i.ZERO
var _elapsed: float = 0.0


func _ready() -> void:
	if camera_path != NodePath():
		_camera = get_node(camera_path)
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if _camera:
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
	refresh()


## Hexes currently live, camera hex first — see get_live_hexes()'s ordering
## note. Returned by value; the caller cannot mutate this class's set.
func get_live_hexes() -> Array[Vector2i]:
	return _live_list.duplicate()


func is_live(coord: Vector2i) -> bool:
	return _live.has(coord)


## Where the player is looking, in world space. The budget allocator sorts by
## distance from this, so "nearest the observer first" is measured from the
## camera itself rather than from its hex center — a camera at the far edge of
## its own hex is genuinely nearer the neighbour it is looking at.
func get_observer_position() -> Vector2:
	if _camera and _camera.is_inside_tree():
		return _camera.global_position
	return HexCoord.axial_to_world(_observer_coord)


func get_observer_coord() -> Vector2i:
	return _observer_coord


func _on_tactical_mode_changed(_is_tactical: bool) -> void:
	_elapsed = 0.0
	refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL_SECONDS:
		return
	_elapsed = 0.0
	refresh()


## Replaces the live set outright. The only caller is
## scripts/test/verify_tactical_zombies.gd, which needs a hex to be live
## because the player owns it — the real signal for that is BuildingManager,
## and standing one up (with its ResourceManager, its costs and its placement
## rules) to assert a rule about zombies would test the wrong thing. The next
## refresh() overwrites whatever this set.
func override_live_hexes_for_test(coords: Array[Vector2i]) -> void:
	var next: Dictionary = {}
	var ordered: Array[Vector2i] = []
	for coord in coords:
		if not next.has(coord):
			next[coord] = true
			ordered.append(coord)
	_live = next
	_live_list = ordered
	live_hexes_changed.emit(get_live_hexes())


## Recomputes the live set now, emitting only if it actually changed. Public so
## a test can drive it a step at a time instead of waiting on
## REFRESH_INTERVAL_SECONDS of real frames.
func refresh() -> void:
	var next: Dictionary = {}
	var ordered: Array[Vector2i] = []
	if _camera and _camera.is_tactical_zoom():
		_observer_coord = _camera_coord()
		# Camera neighbourhood first, so the allocator's nearest-first walk
		# starts from what the player is actually looking at even before it
		# sorts by distance.
		for coord in HexCoord.hex_disk(_observer_coord, CAMERA_RADIUS):
			if not next.has(coord):
				next[coord] = true
				ordered.append(coord)
		_append_occupied(next, ordered)

	if next.size() == _live.size():
		var identical := true
		for coord: Vector2i in next:
			if not _live.has(coord):
				identical = false
				break
		if identical:
			return

	_live = next
	_live_list = ordered
	live_hexes_changed.emit(get_live_hexes())


## Every hex holding a player unit or a player building, however far from the
## camera. A distant one is still live by the spec's rule; the budget
## allocator is what makes it cheap, by handing it whatever share is left
## after the nearer hexes have taken theirs — which is usually nothing.
func _append_occupied(next: Dictionary, ordered: Array[Vector2i]) -> void:
	if _unit_manager:
		for unit in _unit_manager.get_all_units():
			if not next.has(unit.hex_coord):
				next[unit.hex_coord] = true
				ordered.append(unit.hex_coord)
	if _building_manager:
		for building in _building_manager.get_all_buildings():
			if not next.has(building.hex_coord):
				next[building.hex_coord] = true
				ordered.append(building.hex_coord)


func _camera_coord() -> Vector2i:
	if _hex_grid_map and _camera:
		return _hex_grid_map.world_to_coord(_camera.global_position)
	return _observer_coord
