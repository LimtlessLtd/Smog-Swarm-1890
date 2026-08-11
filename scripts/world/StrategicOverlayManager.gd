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
## Also draws under-attack alerts (2.7.5, a pulsing ring off Phase 6.2's
## `EventManager`) and wall segment markers (2.7.3, a `Line2D` per
## `WallSegment` — see that section's own doc comment for why a line, not a
## point icon like everything else here). Every marker type here follows
## the same pattern: a Dictionary of live marker nodes keyed by whatever
## uniquely identifies the source, added/removed/updated off that source's
## own signals, rather than a bespoke overlay system per source.
##
## Parented as a HexGridMap sibling under WorldRoot, same reasoning as
## LocalDetailManager: shares its coordinate space, and — added after both
## HexGridMap and LocalDetailManager in Main.tscn — draws its icons on top
## by plain sibling order.
##
## Also draws the Threat Meter's world-view surface (design doc Phase 6.1
## — MinimapView's own doc comment covers its minimap-side twin) — a
## translucent diamond per noisy hex, sized/colored by intensity via the
## shared NoiseVisuals lookup both surfaces read from.
##
## **Display Options (user request): every marker category here lives under
## its own Node2D layer** (`_building_layer`/`_frontier_layer`/
## `_wall_layer`/`_unit_layer`/`_horde_layer`/`_attack_layer`/
## `_threat_layer`/`_zoc_layer`), toggled on/off via the `DisplaySettings`
## autoload rather than each marker's own individual `visible` flag — Godot
## combines a child's visibility with its parent's, so hiding a layer hides
## every marker under it (present AND future) for free, no per-marker
## bookkeeping needed. `_sync_layer_visibility()` is the only place that
## reads `DisplaySettings` directly; every `_build_*_marker()`/`_on_*`
## handler below is completely unaware of it, same as before this feature
## existed.
##
## Also draws Zone of Control markers (design doc Phase 2.3, visualized for
## the first time this pass — user request) — see `ZoneOfControlVisuals.gd`'s
## own doc comment for the outline-vs-fill shape reasoning shared with
## `TacticalHexView`'s own copy on the Tactical view.

## Design doc Phase 6.2's EventManager: fires whenever a horde transitions
## INTO live-tracking (a fresh spot, or a ghost re-spotted) — see
## _reveal_live_marker()'s own doc comment for exactly which call sites that
## covers. Already implicitly filtered to "marker-worthy" hordes
## (size >= HORDE_MARKER_MIN_SIZE below) — EventManager reuses that filter
## rather than re-deriving "dangerous enough to interrupt play" itself.
signal horde_spotted(horde: Horde)

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

## Design doc Phase 2.7.5 — a pulsing marker at the hex under attack.
## **Simplification, documented:** the design doc's own wording is "cleared
## once the threat resolves"; tracking that precisely would need every
## combat-adjacent system (CombatCoordinator, WallManager, BuildingManager)
## to also signal "this specific threat is over", none of which exist today.
## A fixed-duration pulse — re-triggered (timer restarted, not stacked) by
## any further COMBAT event at the same hex while it's still showing — reads
## as "notice, then fade" without that plumbing, close enough to the
## design doc's intent for a first pass.
const ATTACK_ALERT_COLOR := Color(0.95, 0.75, 0.1, 0.9)  ## Amber ring — distinct from buildings' triangle, units' filled circle, and hordes' filled diamond (shape-and-color, never color alone).
const ATTACK_ALERT_RADIUS := 22.0
const ATTACK_ALERT_SECONDS: float = 8.0

## Threat Meter (design doc Phase 6.1) — world-space marker radius bounds
## (hex-sized units, not minimap pixels — see NoiseVisuals.gd for the
## shared color/intensity curve this scales against, also used by
## MinimapView's own copy of the same overlay). Sized in the same rough
## ballpark as this class's other markers (horde diamond 12, attack ring
## 22) rather than the minimap's tiny fixed pixels.
const THREAT_MARKER_RADIUS_MIN := 8.0
const THREAT_MARKER_RADIUS_MAX := 26.0

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var unit_order_controller_path: NodePath  ## Optional — without it, unit icons still appear/disappear correctly but won't reposition as units move (unit_moved never fires here).
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Required for horde markers to do anything — without it every horde is treated as never-spotted (see _is_visible()).
@export var camera_path: NodePath
@export var event_manager_path: NodePath  ## Optional — without it, COMBAT events simply don't pulse a marker (Phase 6.2's EventManager is the source; see _on_event_raised()).
@export var wall_manager_path: NodePath  ## Optional — without it, wall segments simply have no Strategic marker (Phase 2.7.3).
@export var logistics_network_path: NodePath  ## Optional — without it, every wall marker just reads as "outer" forever (Phase 4.1's is_legacy_segment() distinction never refreshes).
@export var noise_manager_path: NodePath  ## Optional — Phase 6.1's Threat Meter, drawn here on the Strategic world view; unset means no threat markers here (MinimapView's own copy is independent).

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager
var _camera: CameraController
var _wall_manager: WallManager
var _logistics_network: LogisticsNetwork
var _noise_manager: NoiseManager

## Display Options (user request) — one layer Node2D per marker category;
## see this class's own doc comment for why a layer, not a per-marker
## visible flag.
var _building_layer: Node2D
var _frontier_layer: Node2D
var _wall_layer: Node2D
var _unit_layer: Node2D
var _horde_layer: Node2D
var _attack_layer: Node2D
var _threat_layer: Node2D
var _zoc_layer: Node2D

var _building_icons: Dictionary = {}    # int (BuildingInstance.id) -> Node2D
var _unit_icons: Dictionary = {}        # int (UnitInstance.id) -> Node2D
var _frontier_markers: Dictionary = {}  # Vector2i -> Node2D
var _wall_markers: Dictionary = {}      # int (WallSegment.id) -> Node2D (container: "Body" Line2D + "DefenseWork" Polygon2D)

var _horde_markers: Dictionary = {}            # int (Horde.id) -> Node2D (container: "Body" Polygon2D + "Direction" Line2D)
var _horde_live: Dictionary = {}               # int (Horde.id) -> bool; true while live-tracking a VISIBLE hex, false once ghosted
var _horde_last_known_coord: Dictionary = {}   # int (Horde.id) -> Vector2i; live position while tracked, frozen ghost position once not

var _attack_markers: Dictionary = {}  # Vector2i -> {"node": Node2D, "timer": Timer}
var _threat_markers: Dictionary = {}  # Vector2i -> Node2D
var _zoc_markers: Dictionary = {}     # Vector2i -> Node2D (container: "MilitaryOutline" Line2D + "CivilianFill" Polygon2D)

func _ready() -> void:
	_building_layer = _new_layer("BuildingLayer")
	_frontier_layer = _new_layer("FrontierLayer")
	_wall_layer = _new_layer("WallLayer")
	_unit_layer = _new_layer("UnitLayer")
	_horde_layer = _new_layer("HordeLayer")
	_attack_layer = _new_layer("AttackLayer")
	_threat_layer = _new_layer("ThreatLayer")
	_zoc_layer = _new_layer("ZocLayer")

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
	if event_manager_path != NodePath():
		var event_manager: EventManager = get_node(event_manager_path)
		event_manager.event_raised.connect(_on_event_raised)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_manager.wall_segment_placed.connect(_on_wall_segment_placed)
		_wall_manager.wall_segment_upgraded.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_breached.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_repaired.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_removed.connect(_on_wall_segment_removed)
		_wall_manager.defense_work_added.connect(_on_wall_defense_work_added)
		for segment in _wall_manager.get_segments():
			_on_wall_segment_placed(segment)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_logistics_network.network_recomputed.connect(_on_logistics_network_recomputed)
		_refresh_zoc_markers()
	if noise_manager_path != NodePath():
		_noise_manager = get_node(noise_manager_path)
		_noise_manager.noise_recomputed.connect(_refresh_threat_markers)
		_refresh_threat_markers()
	_refresh_frontier_markers()

	DisplaySettings.changed.connect(_sync_layer_visibility)
	_sync_layer_visibility()

func _new_layer(layer_name: String) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	return layer

## Display Options (user request) — the only place this class reads
## DisplaySettings; every marker builder/handler stays unaware of it. A
## layer's own `visible` combines with this whole node's (Strategic-vs-
## Tactical zoom, above) automatically — no interaction to handle.
func _sync_layer_visibility() -> void:
	_building_layer.visible = DisplaySettings.show_building_markers
	_frontier_layer.visible = DisplaySettings.show_frontier_markers
	_wall_layer.visible = DisplaySettings.show_wall_markers
	_unit_layer.visible = DisplaySettings.show_unit_markers
	_horde_layer.visible = DisplaySettings.show_horde_markers
	_attack_layer.visible = DisplaySettings.show_attack_alerts
	_threat_layer.visible = DisplaySettings.show_threat_meter_world
	_zoc_layer.visible = DisplaySettings.show_zoc_world

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = not is_tactical

func _on_building_placed(instance: BuildingInstance) -> void:
	var icon := _build_building_icon(instance)
	_building_layer.add_child(icon)
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
	_unit_layer.add_child(icon)
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
		_horde_layer.add_child(marker)
		_horde_markers[horde.id] = marker
	marker.position = HexCoord.axial_to_world(coord)
	marker.modulate = Color.WHITE
	(marker.get_node("Direction") as Line2D).visible = false
	_horde_live[horde.id] = true
	_horde_last_known_coord[horde.id] = coord
	horde_spotted.emit(horde)  ## Design doc Phase 6.2 — see this signal's own doc comment for why every call site here qualifies as "newly spotted".

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
			_frontier_layer.add_child(marker)
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

## --- Under-Attack Alerts (Phase 2.7.5) -------------------------------------

## EventManager.event_raised's own COMBAT category already covers exactly
## what 2.7.5 asks for (a wall breach, a unit engaged, a building ruined) —
## every one of those carries a real hex_coord (see EventManager's own
## handlers), so no further filtering is needed beyond the category check.
func _on_event_raised(event: GameEvent) -> void:
	if event.category == GameEnums.EventCategory.COMBAT:
		_pulse_attack_marker(event.hex_coord)

## Creates a pulsing ring at `coord`, or — if one's already showing there —
## just restarts its clear-timer rather than stacking a second marker.
func _pulse_attack_marker(coord: Vector2i) -> void:
	var existing: Dictionary = _attack_markers.get(coord, {})
	if not existing.is_empty():
		(existing["timer"] as Timer).start()
		return
	var ring := _build_attack_ring()
	ring.position = HexCoord.axial_to_world(coord)
	_attack_layer.add_child(ring)
	_start_attack_ring_pulse(ring)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = ATTACK_ALERT_SECONDS
	add_child(timer)  # Not a visual layer member — a Timer has nothing to hide/show.
	timer.timeout.connect(_on_attack_marker_timeout.bind(coord))
	timer.start()

	_attack_markers[coord] = {"node": ring, "timer": timer}

func _on_attack_marker_timeout(coord: Vector2i) -> void:
	var entry: Dictionary = _attack_markers.get(coord, {})
	if not entry.is_empty():
		(entry["node"] as Node2D).queue_free()
		(entry["timer"] as Timer).queue_free()
	_attack_markers.erase(coord)

func _build_attack_ring() -> Line2D:
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = ATTACK_ALERT_COLOR
	ring.closed = true
	ring.points = _circle_points(ATTACK_ALERT_RADIUS, 16)
	return ring

## `ring` must already be inside the tree (create_tween() requires it) —
## called right after add_child() above, never before.
func _start_attack_ring_pulse(ring: Line2D) -> void:
	var tween := ring.create_tween()
	tween.set_loops()
	tween.tween_property(ring, "modulate:a", 0.25, 0.5)
	tween.tween_property(ring, "modulate:a", 1.0, 0.5)

## --- Wall Markers (Phase 2.7.3) ---------------------------------------------
##
## The last of this phase's originally-planned marker types — blocked until
## now on Phase 4.1's `WallManager`/`WallSegment` existing at all (they do,
## as of that phase's own implementation pass). Follows the same "Dictionary
## of live marker nodes keyed by whatever uniquely identifies the source,
## added/removed off that source's own signals" pattern building/unit/horde
## markers above already established — walls are the fourth system to
## follow it, not a new shape.
##
## A wall defends the shared EDGE between two hexes, not a single hex the
## way every other marker here does — so unlike a point icon, this marker is
## a `Line2D` running from `hex_a`'s world center to `hex_b`'s. That's a
## deliberate, free accessibility win: a line is already visually distinct
## from buildings' triangle, units' circle, and hordes' diamond by SHAPE
## alone, without needing a fourth point-marker shape invented for it.
##
## No fog-of-war gating, matching building icons' own precedent (not spotted
## hordes' — a wall is always the player's own construction, same as a
## building; there's nothing to "spot" about your own perimeter).
##
## **No longer true (user request: a Demolish action for walls, mirroring
## buildings' own): a `wall_segment_removed` signal now exists** —
## `_on_wall_segment_removed()` below frees this marker exactly the way
## `_on_building_removed()` already does for building icons, the same
## "queue_free() + erase from the id->marker map" shape.
##
## Phase 4.1's outer/legacy-inner distinction, once decided: a legacy
## segment (WallManager.is_legacy_segment()) renders dimmed via the whole
## marker's `modulate`, an outer one at full brightness — see
## WallVisuals.legacy_modulate()'s own doc comment for why a dimmer, not a
## fourth color. 2.7.3 itself never needed this (a segment's marker only
## ever depended on its own tier/breached/defense-work state, all
## per-segment) — this is a real addition on top of that, not a correction
## to it, now that Phase 4.1 actually has an outer/inner concept to show.

func _on_wall_segment_placed(segment: WallSegment) -> void:
	var marker := _build_wall_marker(segment)
	_wall_layer.add_child(marker)
	_wall_markers[segment.id] = marker

## Shared by upgrade/breach/repair — all three change how the SAME segment
## should currently render (tier color/width, or the distinct breached
## look) without changing its position, so a single recolor-in-place
## handler covers all three rather than three near-identical ones.
func _on_wall_segment_state_changed(segment: WallSegment) -> void:
	var marker: Node2D = _wall_markers.get(segment.id)
	if not marker:
		return
	_apply_wall_segment_look(marker, segment)

## User request (Demolish): mirrors _on_building_removed()'s own
## "queue_free() + erase from the id->marker map" shape exactly — the
## first time a wall marker has ever needed to disappear rather than just
## recolor in place.
func _on_wall_segment_removed(segment: WallSegment) -> void:
	var marker: Node2D = _wall_markers.get(segment.id)
	if marker:
		marker.queue_free()
	_wall_markers.erase(segment.id)

func _on_wall_defense_work_added(segment: WallSegment, _work_type: GameEnums.BuildingType) -> void:
	var marker: Node2D = _wall_markers.get(segment.id)
	if marker:
		_update_defense_work_marker(marker, segment)

func _build_wall_marker(segment: WallSegment) -> Node2D:
	var container := Node2D.new()

	var body := Line2D.new()
	body.name = "Body"
	# Freehand wall rework: point_a/point_b are the piece's own real
	# placement geometry now, not always a whole hex edge — many small
	# collinear pieces from the same drawn line still render as one
	# continuous stroke, same as intended before this rework.
	body.points = PackedVector2Array([segment.point_a, segment.point_b])
	container.add_child(body)
	_apply_wall_segment_look(container, segment)

	var defense_work := Polygon2D.new()
	defense_work.name = "DefenseWork"
	defense_work.visible = false
	container.add_child(defense_work)
	_update_defense_work_marker(container, segment)

	return container

## User request, this pass: real tileable wall art (WallVisuals.tier_texture(),
## assets/walls/README.md) for an INTACT segment — Line2D natively tiles a
## texture along its own length (texture_mode = LINE_TEXTURE_TILE), so this
## needs no UV-mapping of its own the way a Polygon2D would. A breached
## segment always keeps the flat alarm-red look regardless of art (clear the
## texture rather than tile it red) — see WallVisuals.tier_texture()'s own
## doc comment for why. default_color still gets set even with a texture
## assigned: Line2D multiplies texture color by default_color, so leaving it
## at the tier color would tint real art an unintended hue — reset to plain
## white (no tint) whenever a real texture is in play, tier color only
## otherwise.
## texture_repeat fix (same root cause as LocalDetailManager's own Tactical
## wall marker — see that function's doc comment): LINE_TEXTURE_TILE only
## actually tiles when texture_repeat is ENABLED/MIRROR, which this never
## set, so it sat at the project default (Disabled) and clamped instead of
## repeating. Not the player-reported bug (that was Tactical specifically),
## but the same latent issue, fixed here too rather than left half-fixed.
func _apply_wall_segment_look(marker: Node2D, segment: WallSegment) -> void:
	var body := marker.get_node("Body") as Line2D
	var breached := segment.is_breached()
	var texture := WallVisuals.tier_texture(segment.tier) if not breached else null
	body.texture = texture
	body.texture_mode = Line2D.LINE_TEXTURE_TILE
	body.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	body.default_color = Color.WHITE if texture else (WallVisuals.breached_color() if breached else (WallVisuals.gate_color() if segment.is_gate else WallVisuals.tier_color(segment.tier)))
	body.width = WallVisuals.line_width(segment.tier, breached)
	var is_legacy := _wall_manager != null and _wall_manager.is_legacy_segment(segment)
	marker.modulate = WallVisuals.legacy_modulate() if is_legacy else WallVisuals.outer_modulate()

## Design doc Phase 4.1: territory shifting (a hex gaining/losing ZoC
## coverage) can flip a segment's outer/legacy classification without the
## segment itself changing at all (no placed/upgraded/breached/repaired
## signal fires) — so this listens to LogisticsNetwork's own recompute
## signal directly, the same trigger FogOfWarManager/DiscontentManager
## already key their own ZoC-dependent recomputes off, rather than trying to
## infer it from wall-specific signals that wouldn't cover every case.
func _on_logistics_network_recomputed() -> void:
	_refresh_wall_marker_looks()
	_refresh_zoc_markers()

func _refresh_wall_marker_looks() -> void:
	if not _wall_manager:
		return
	for segment in _wall_manager.get_segments():
		_on_wall_segment_state_changed(segment)

## Ditch/Oil Pit (Phase 4.1) stack alongside a segment rather than replacing
## it — a small square at the segment's own midpoint, on top of the line,
## rather than a second line. Covers both a live `defense_work_added` signal
## AND a segment restored from a save that already had one (Phase 2.8's own
## `_wall_manager.get_segments()` loop in `_ready()` calls this indirectly
## via `_build_wall_marker()`, same as every other marker type's own
## "replay existing state on load" precedent).
func _update_defense_work_marker(marker: Node2D, segment: WallSegment) -> void:
	var work := marker.get_node("DefenseWork") as Polygon2D
	if not segment.has_ditch and not segment.has_oil_pit:
		work.visible = false
		return
	work.visible = true
	var midpoint := (segment.point_a + segment.point_b) / 2.0
	var half := 5.0
	work.polygon = PackedVector2Array([
		midpoint + Vector2(-half, -half), midpoint + Vector2(half, -half),
		midpoint + Vector2(half, half), midpoint + Vector2(-half, half),
	])
	# User request, this pass: real art (WallVisuals.defense_work_texture(),
	# assets/walls/README.md) where authored — a genuine 4-vertex quad (the
	# square built above), so a plain corner-to-corner uv mapping is exactly
	# the SAFE case TacticalHexView's own building-quad code already relies
	# on (not the hex-fan case that bit terrain art once — see that class's
	# own doc comment). Falls back to the flat blended color when no texture
	# exists yet, unchanged from before this pass.
	var texture := WallVisuals.defense_work_texture(segment.has_ditch, segment.has_oil_pit)
	work.texture = texture
	# Real bug fixed (see TacticalHexView.quad_uv()'s own doc comment):
	# Polygon2D.uv is texture-PIXEL-space, not normalized 0..1 - this
	# unit-square array only ever sampled a 1x1-pixel transparent
	# corner, rendering this icon's fill invisible whenever a texture
	# was set. Reuse the same shared fix.
	work.uv = TacticalHexView.quad_uv(texture)
	work.color = Color.WHITE if texture else WallVisuals.defense_work_color(segment.has_ditch, segment.has_oil_pit)

## --- Threat Meter (Phase 6.1) — world-view surface ---------------------
##
## MinimapView's own doc comment already covers the "why a diamond, why
## sized+colored by intensity, why NoiseVisuals is shared" reasoning — this
## is the same overlay's second surface, not a new design. Rebuilt from
## scratch on every NoiseManager.noise_recomputed (a building placed/
## removed/ruined, or a day/night flip) — same "small enough to just
## rebuild" reasoning _refresh_frontier_markers() already relies on (dozens
## of hexes at most, not thousands, since only hexes actually within some
## source's NOISE_RADIUS ever have nonzero noise).
##
## Same at-least-EXPLORED fog gate building icons already use — a noise
## source is the player's own industry, already-known territory reads the
## same way a building icon already does here.

func _refresh_threat_markers() -> void:
	if not _hex_grid_map or not _noise_manager:
		return
	var wanted: Dictionary = {}  # Vector2i -> float (noise level)
	for cell: HexCell in _hex_grid_map.get_all_cells():
		var noise := _noise_manager.get_noise_at(cell.coord)
		if noise > 0.0 and (not _fog_of_war_manager or _fog_of_war_manager.is_at_least_explored(cell.coord)):
			wanted[cell.coord] = noise

	for coord in _threat_markers.keys():
		if not wanted.has(coord):
			_threat_markers[coord].queue_free()
			_threat_markers.erase(coord)
	for coord in wanted:
		var noise: float = wanted[coord]
		if _threat_markers.has(coord):
			_apply_threat_marker_look(_threat_markers[coord], noise)
		else:
			var marker := _build_threat_marker(coord, noise)
			_threat_layer.add_child(marker)
			_threat_markers[coord] = marker

func _build_threat_marker(coord: Vector2i, noise: float) -> Node2D:
	var marker := Polygon2D.new()
	marker.position = HexCoord.axial_to_world(coord)
	_apply_threat_marker_look(marker, noise)
	return marker

func _apply_threat_marker_look(marker: Polygon2D, noise: float) -> void:
	var r := NoiseVisuals.radius(noise, THREAT_MARKER_RADIUS_MIN, THREAT_MARKER_RADIUS_MAX)
	marker.color = NoiseVisuals.color(noise)
	# A diamond — same shape MinimapView's own copy uses, and already
	# distinct here from buildings' triangle, units' circle, and hordes'
	# (larger, opaque) diamond by color/translucency alone.
	marker.polygon = PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])

## --- Zone of Control (Phase 2.3) — world-view surface -------------------
##
## `ZoneOfControlVisuals.gd`'s own doc comment covers the "why an outline
## for Military, why a fill for Civilian" reasoning — this is that overlay's
## Strategic surface, `TacticalHexView`'s own copy is the other. Rebuilt
## from scratch on every `LogisticsNetwork.network_recomputed` — same
## "small enough to just rebuild" reasoning `_refresh_frontier_markers()`/
## `_refresh_threat_markers()` above already rely on (dozens of ZoC-covered
## hexes at most). No fog-of-war gating, matching wall/building markers'
## own precedent — a ZoC aura is the player's own projected presence, same
## as a building or a wall, not something to "spot" about someone else's.

func _refresh_zoc_markers() -> void:
	if not _logistics_network:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for coord in _logistics_network.get_covered_hexes():
		wanted[coord] = true

	for coord in _zoc_markers.keys():
		if not wanted.has(coord):
			_zoc_markers[coord].queue_free()
			_zoc_markers.erase(coord)
	for coord in wanted:
		var state := _logistics_network.get_zoc_state(coord)
		if _zoc_markers.has(coord):
			_apply_zoc_marker_look(_zoc_markers[coord], state)
		else:
			var marker := _build_zoc_marker(coord, state)
			_zoc_layer.add_child(marker)
			_zoc_markers[coord] = marker

func _build_zoc_marker(coord: Vector2i, state: ZoneOfControlState) -> Node2D:
	var container := Node2D.new()
	container.position = HexCoord.axial_to_world(coord)

	var outline := Line2D.new()
	outline.name = "MilitaryOutline"
	outline.closed = true
	outline.default_color = ZoneOfControlVisuals.MILITARY_OUTLINE_COLOR
	outline.width = ZoneOfControlVisuals.MILITARY_OUTLINE_WIDTH
	outline.points = HexCoord.corner_points(Vector2.ZERO)
	container.add_child(outline)

	var fill := Polygon2D.new()
	fill.name = "CivilianFill"
	fill.color = ZoneOfControlVisuals.CIVILIAN_FILL_COLOR
	fill.polygon = HexCoord.corner_points(Vector2.ZERO)
	container.add_child(fill)

	_apply_zoc_marker_look(container, state)
	return container

func _apply_zoc_marker_look(marker: Node2D, state: ZoneOfControlState) -> void:
	(marker.get_node("MilitaryOutline") as Line2D).visible = state.has_military_coverage()
	(marker.get_node("CivilianFill") as Polygon2D).visible = state.has_civilian_coverage
