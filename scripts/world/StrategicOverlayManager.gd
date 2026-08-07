class_name StrategicOverlayManager
extends Node2D

## Strategic-zoom (Phase 2.5) map markers: a small icon over every placed
## building, a token over every trained unit, and a frontier indicator over
## hexes where secured and contested ground meet. Hides itself entirely
## while the camera is in Tactical zoom, since Tactical view already shows
## the real buildings/units/terrain directly instead of an abstract icon
## standing in for them.
##
## Also draws spotted-horde markers (2.7.6): a horde only gets a marker once
## its hex has actually been `VISIBLE` at least once ("spotted", not
## omniscient tracking), tracks live while `VISIBLE`, and — decided — freezes
## as a dimmed "last known position" ghost with a direction-of-travel
## indicator once vision is lost, rather than vanishing. See
## `_reveal_live_marker()`/`_freeze_horde_marker()`'s own doc comments for
## the full state machine.
##
## This is the "buildable now" slice of the Phase 2.7 plan (todo.md) — wall
## markers and under-attack alerts still wait on systems this class doesn't
## read from yet (Phase 4.1/4.2's wall breach events, Phase 6.2's
## `EventManager`) and stay documented there rather than built here.
## Whichever of those eventually needs to raise a marker should follow this
## class's own pattern (a Dictionary of live marker nodes keyed by whatever
## uniquely identifies the source, added/removed off that source's own
## placed/removed-style signals) rather than invent a second overlay system
## — units and hordes (below) are the second and third systems to actually
## follow it, after buildings.
##
## Parented as a HexGridMap sibling under WorldRoot, same reasoning as
## LocalDetailManager: shares its coordinate space, and — added after both
## HexGridMap and LocalDetailManager in Main.tscn — draws its icons on top
## by plain sibling order.

## A consistent "friendly unit" color, distinct from any BuildingVisuals
## category color and shaped differently (a circle vs. buildings'
## triangle) — same accessibility principle BuildPlacementController's own
## hexagon-vs-diamond ghost already follows: never rely on color alone.
const UNIT_MARKER_COLOR := Color(0.3, 0.55, 0.85)
const UNIT_MARKER_RADIUS := 10.0  ## Smaller than a building icon's 16 — reads as a token, not a structure.

## Hordes read as hostile (red, diamond — distinct from buildings' triangle
## and units' circle) while live-tracked; ghosted (last-known-position,
## vision lost) dims the whole marker via `modulate`, same mechanism
## FogVisuals.tint_color() uses for EXPLORED terrain, and reveals a short
## direction-of-travel line in a third, distinct color so it doesn't blend
## into either the red body or whatever terrain color sits underneath.
const HORDE_MARKER_COLOR := Color(0.75, 0.15, 0.15)
const HORDE_GHOST_MODULATE := Color(1.0, 1.0, 1.0, 0.4)
const HORDE_DIRECTION_COLOR := Color(0.95, 0.85, 0.3, 0.9)
const HORDE_MARKER_RADIUS := 12.0
const HORDE_DIRECTION_LENGTH := 20.0

## Design doc Phase 2.7.6/5.10, decided (grilling session): only hordes at or
## above this size get a Strategic-map marker at all — small hordes and lone
## zombies (Phase 5.2) are meant to only be visible up close at Tactical
## zoom (Phase 2.5.4's TacticalEntityLayer), not as an overworld icon.
## Doesn't touch the spotting/ghost-tracking state machine below, only
## which hordes qualify for a marker in the first place.
const HORDE_MARKER_MIN_SIZE: int = 100

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var unit_order_controller_path: NodePath  ## Optional — without it, unit icons still appear/disappear correctly but won't reposition as units move (unit_moved never fires here).
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Required for horde markers to do anything — without it every horde is treated as never-spotted (see _is_visible()).
@export var camera_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager
var _camera: CameraController

var _building_icons: Dictionary = {}    # int (BuildingInstance.id) -> Node2D
var _unit_icons: Dictionary = {}        # int (UnitInstance.id) -> Node2D
var _frontier_markers: Dictionary = {}  # Vector2i -> Node2D

var _horde_markers: Dictionary = {}            # int (Horde.id) -> Node2D (container: "Body" Polygon2D + "Direction" Line2D)
var _horde_live: Dictionary = {}               # int (Horde.id) -> bool; true while live-tracking a VISIBLE hex, false once ghosted
var _horde_last_known_coord: Dictionary = {}   # int (Horde.id) -> Vector2i; live position while tracked, frozen ghost position once not

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_building_placed)
		_building_manager.building_removed.connect(_on_building_removed)
		_building_manager.building_ruined.connect(_on_building_ruined)
		for instance in _building_manager.get_all_buildings():
			_on_building_placed(instance)
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_trained.connect(_on_unit_trained)
		_unit_manager.unit_removed.connect(_on_unit_removed)
		for instance in _unit_manager.get_all_units():
			_on_unit_trained(instance)
	if unit_order_controller_path != NodePath():
		var unit_order_controller: UnitOrderController = get_node(unit_order_controller_path)
		unit_order_controller.unit_moved.connect(_on_unit_moved)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
		_horde_manager.horde_spawned.connect(_on_horde_spawned)
		_horde_manager.horde_moved.connect(_on_horde_moved)
		_horde_manager.horde_removed.connect(_on_horde_removed)
		_horde_manager.horde_size_changed.connect(_on_horde_size_changed)
	if fog_of_war_manager_path != NodePath():
		_fog_of_war_manager = get_node(fog_of_war_manager_path)
		_fog_of_war_manager.fog_state_changed.connect(_on_fog_state_changed)
	if _horde_manager:
		# Deferred until after _fog_of_war_manager is resolved above —
		# _on_horde_spawned() needs _is_visible() to already work.
		for horde in _horde_manager.get_all_hordes():
			_on_horde_spawned(horde)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		visible = not _camera.is_tactical_zoom()
	_refresh_frontier_markers()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = not is_tactical

func _on_building_placed(instance: BuildingInstance) -> void:
	var icon := _build_building_icon(instance)
	add_child(icon)
	_building_icons[instance.id] = icon
	_refresh_frontier_markers()  # a new building can flip a hex's safe/contested mix

func _on_building_removed(instance: BuildingInstance) -> void:
	var icon: Node2D = _building_icons.get(instance.id)
	if icon:
		icon.queue_free()
	_building_icons.erase(instance.id)
	_refresh_frontier_markers()

## Design doc Phase 5.12: recolors the existing icon in place (same "update
## live, don't tear down and rebuild" shape TacticalHexView.set_fidelity()/
## set_fog_state() already use) — the building stays on the map as a ruin,
## it doesn't vanish, so building_removed's queue_free()/erase() path isn't
## the right one here.
func _on_building_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	var icon: Polygon2D = _building_icons.get(instance.id)
	if icon:
		icon.color = BuildingVisuals.ruin_color()

func _build_building_icon(instance: BuildingInstance) -> Node2D:
	var icon := Polygon2D.new()
	icon.color = BuildingVisuals.ruin_color() if instance.is_ruined else BuildingVisuals.category_color(instance.definition.category)
	var r := 16.0  # Bigger than TacticalHexView's building boxes — needs to read at zoomed-out scale.
	icon.polygon = PackedVector2Array([Vector2(0, -r), Vector2(r, r * 0.6), Vector2(-r, r * 0.6)])
	icon.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position
	return icon

func _on_unit_trained(instance: UnitInstance) -> void:
	var icon := _build_unit_icon(instance)
	add_child(icon)
	_unit_icons[instance.id] = icon

func _on_unit_removed(instance: UnitInstance) -> void:
	var icon: Node2D = _unit_icons.get(instance.id)
	if icon:
		icon.queue_free()
	_unit_icons.erase(instance.id)

func _on_unit_moved(instance: UnitInstance, _from_coord: Vector2i, to_coord: Vector2i) -> void:
	var icon: Node2D = _unit_icons.get(instance.id)
	if icon:
		icon.position = HexCoord.axial_to_world(to_coord)

func _build_unit_icon(instance: UnitInstance) -> Node2D:
	var icon := Polygon2D.new()
	icon.color = UNIT_MARKER_COLOR
	icon.polygon = _circle_points(UNIT_MARKER_RADIUS)
	icon.position = HexCoord.axial_to_world(instance.hex_coord)
	return icon

func _circle_points(radius: float, segments: int = 10) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

## --- Spotted Horde Markers (Phase 2.7.6) ----------------------------------
##
## State machine, driven by two independent triggers (a horde moving, or a
## hex's fog state changing for any other reason — a new watchtower, a lost
## supply line, night contraction): a horde is either live-tracked (marker
## follows `Horde.hex_coord` exactly, full color) or ghosted (marker frozen
## at the last coord it was actually seen on, dimmed, with a direction line
## toward wherever it was heading when last seen). A horde with no marker
## at all yet has simply never been spotted.

func _on_horde_spawned(horde: Horde) -> void:
	if _qualifies_for_marker(horde) and _is_visible(horde.hex_coord):
		_reveal_live_marker(horde, horde.hex_coord)
	# else: not yet spotted (or too small to mark at all) — no marker until a
	# later _on_fog_state_changed()/_on_horde_moved()/_on_horde_size_changed()
	# call reveals one.

func _on_horde_removed(horde: Horde) -> void:
	_remove_marker_if_any(horde)

func _on_horde_moved(horde: Horde, from_coord: Vector2i, to_coord: Vector2i) -> void:
	if not _qualifies_for_marker(horde):
		_remove_marker_if_any(horde)  # A no-op if it never had one — e.g. was always below threshold.
		return
	if _horde_live.get(horde.id, false):
		if _is_visible(to_coord):
			_update_live_marker_position(horde, to_coord)
		else:
			# Walked out of sight this step — freeze at the LAST hex it was
			# actually seen on (`from_coord`, still visible), not the new
			# (unseen) one, with a direction line pointing toward where it
			# was headed.
			_freeze_horde_marker(horde, from_coord, to_coord)
	elif _is_visible(to_coord):
		_reveal_live_marker(horde, to_coord)  # Newly spotted (or re-spotted) while moving.

## Covers a horde that's stationary (or off-screen entirely) when the
## reason its visibility changes is something ELSE moving — a building
## placed/removed, a supply line cut, Phase 5.1's night contraction — none
## of which fire horde_moved.
func _on_fog_state_changed(coord: Vector2i, state: GameEnums.FogState) -> void:
	if not _horde_manager:
		return
	for horde in _horde_manager.get_hordes_at(coord):
		if not _qualifies_for_marker(horde):
			continue
		if state == GameEnums.FogState.VISIBLE:
			if not _horde_live.get(horde.id, false):
				_reveal_live_marker(horde, coord)
		elif _horde_live.get(horde.id, false):
			_freeze_horde_marker(horde, coord, coord)  # Stationary loss of vision — no known heading, so no direction line.

## Phase 5.10's merge/split (HordeManager) — and any other source of
## Horde.size changing outside of a move, e.g. Phase 5.9's casualty
## accumulation via add_casualty_zombies() — can cross HORDE_MARKER_MIN_SIZE
## in either direction without the horde itself moving or fog changing.
## Re-evaluate marker existence here rather than waiting for an unrelated
## trigger to catch up eventually. Note: CombatCoordinator shrinks a horde's
## size directly via Horde.apply_remaining_hp() without emitting this signal
## — a horde losing a fight specifically catches up to the threshold change
## on its next horde_moved instead, same as every other combat-driven state
## this class doesn't get a dedicated signal for.
func _on_horde_size_changed(horde: Horde, _delta: int) -> void:
	if not _qualifies_for_marker(horde):
		_remove_marker_if_any(horde)
		return
	if not _horde_markers.has(horde.id) and _is_visible(horde.hex_coord):
		_reveal_live_marker(horde, horde.hex_coord)

func _qualifies_for_marker(horde: Horde) -> bool:
	return horde.size >= HORDE_MARKER_MIN_SIZE

func _remove_marker_if_any(horde: Horde) -> void:
	var marker: Node2D = _horde_markers.get(horde.id)
	if marker:
		marker.queue_free()
	_horde_markers.erase(horde.id)
	_horde_live.erase(horde.id)
	_horde_last_known_coord.erase(horde.id)

func _is_visible(coord: Vector2i) -> bool:
	return _fog_of_war_manager != null and _fog_of_war_manager.is_visible(coord)

## Creates the marker on first-ever spot, or un-dims/repositions an
## existing ghost on re-spot — either way ends live-tracking `horde` at `coord`.
func _reveal_live_marker(horde: Horde, coord: Vector2i) -> void:
	var marker: Node2D = _horde_markers.get(horde.id)
	if not marker:
		marker = _build_horde_marker()
		add_child(marker)
		_horde_markers[horde.id] = marker
	marker.position = HexCoord.axial_to_world(coord)
	marker.modulate = Color.WHITE
	(marker.get_node("Direction") as Line2D).visible = false
	_horde_live[horde.id] = true
	_horde_last_known_coord[horde.id] = coord

func _update_live_marker_position(horde: Horde, coord: Vector2i) -> void:
	var marker: Node2D = _horde_markers.get(horde.id)
	if marker:
		marker.position = HexCoord.axial_to_world(coord)
	_horde_last_known_coord[horde.id] = coord

## Freezes `horde`'s marker at `at_coord` (its last actually-seen position),
## dims it, and — if `heading_toward_coord` differs — draws a short line
## toward wherever it was heading when last seen. Assumes the marker
## already exists (freezing only ever follows a prior reveal); a defensive
## no-op otherwise.
func _freeze_horde_marker(horde: Horde, at_coord: Vector2i, heading_toward_coord: Vector2i) -> void:
	var marker: Node2D = _horde_markers.get(horde.id)
	if not marker:
		return
	marker.position = HexCoord.axial_to_world(at_coord)
	marker.modulate = HORDE_GHOST_MODULATE
	var direction := marker.get_node("Direction") as Line2D
	if at_coord != heading_toward_coord:
		var to_local := HexCoord.axial_to_world(heading_toward_coord) - HexCoord.axial_to_world(at_coord)
		direction.points = PackedVector2Array([Vector2.ZERO, to_local.normalized() * HORDE_DIRECTION_LENGTH])
		direction.visible = true
	else:
		direction.visible = false
	_horde_live[horde.id] = false
	_horde_last_known_coord[horde.id] = at_coord

func _build_horde_marker() -> Node2D:
	var container := Node2D.new()

	var body := Polygon2D.new()
	body.name = "Body"
	body.color = HORDE_MARKER_COLOR
	var r := HORDE_MARKER_RADIUS
	body.polygon = PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])  # Diamond — distinct from buildings' triangle and units' circle.
	container.add_child(body)

	var direction := Line2D.new()
	direction.name = "Direction"
	direction.width = 3.0
	direction.default_color = HORDE_DIRECTION_COLOR
	direction.visible = false
	container.add_child(direction)

	return container

func _refresh_frontier_markers() -> void:
	if not _hex_grid_map:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for cell: HexCell in _hex_grid_map.get_all_cells():
		if _is_frontier_hex(cell):
			wanted[cell.coord] = true

	for coord in _frontier_markers.keys():
		if not wanted.has(coord):
			_frontier_markers[coord].queue_free()
			_frontier_markers.erase(coord)
	for coord in wanted:
		if not _frontier_markers.has(coord):
			var marker := _build_frontier_marker(coord)
			add_child(marker)
			_frontier_markers[coord] = marker

## A hex counts as an active frontier once it has BOTH secured ground and a
## contested fringe — a fully wild hex is just unclaimed territory, not a
## line worth marking, and a fully secured hex has nothing contesting it.
func _is_frontier_hex(cell: HexCell) -> bool:
	return cell.is_frontier() and not cell.get_safe_districts().is_empty()

func _build_frontier_marker(coord: Vector2i) -> Node2D:
	var marker := Line2D.new()
	marker.width = 4.0
	marker.default_color = Color(0.85, 0.25, 0.15, 0.85)
	marker.closed = true
	marker.position = HexCoord.axial_to_world(coord)
	marker.points = HexCoord.corner_points(Vector2.ZERO)
	return marker
