class_name StrategicOverlayManager
extends Node2D

## Strategic-zoom map markers: a small icon over every placed
## building, a token over every trained unit, a frontier indicator where
## secured and contested ground meet, spotted-horde markers, under-attack
## alerts, wall segment markers, the Threat Meter, Zone of Control markers,
## and a static elevation/impassable-terrain overlay. Hides itself entirely
## while the camera is in Tactical zoom, since Tactical view shows the real
## buildings/units/terrain directly instead of an abstract icon.
##
## This class is a coordinator, not a renderer: each marker category is
## implemented by its own collaborator under scripts/world/overlay/
## (BuildingMarkerRenderer, UnitMarkerRenderer, HordeMarkerRenderer,
## FrontierMarkerRenderer, WallMarkerRenderer, ZoneOfControlMarkerRenderer,
## ThreatMarkerRenderer, AttackAlertRenderer), each
## depending only on the manager(s) it actually needs. This class resolves
## the NodePath exports, builds one Node2D layer per category (Display
## Options visibility, below), constructs each renderer against its own
## layer + dependencies, and wires the relevant upstream manager signals to
## it — including cross-cutting refreshes (e.g. a building placement also
## refreshing the frontier line) as separate connections here rather than
## one renderer knowing about another. Public API/signals/NodePath exports
## are unchanged from before this split — see todo.md's "Technical Debt"
## section for why the split happened.
##
## **Display Options (user request): every marker category lives under its
## own Node2D layer**, toggled on/off via the `DisplaySettings` autoload
## rather than each marker's own individual `visible` flag — Godot combines a
## child's visibility with its parent's, so hiding a layer hides every
## marker under it (present AND future) for free. `_sync_layer_visibility()`
## is the only place that reads `DisplaySettings` directly; no renderer is
## aware of it.
##
## Parented as a HexGridMap sibling under WorldRoot, same reasoning as
## LocalDetailManager: shares its coordinate space, and — added after both
## HexGridMap and LocalDetailManager in Main.tscn — draws its icons on top by
## plain sibling order.

## Fires whenever a horde transitions INTO live-tracking (a fresh spot, or a
## ghost re-spotted) — relayed from HordeMarkerRenderer.spotted, already
## filtered to marker-worthy hordes (HordeMarkerRenderer.MIN_SIZE).
signal horde_spotted(horde: Horde)

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var unit_order_controller_path: NodePath  ## Optional — without it, unit icons still appear/disappear correctly but won't reposition as units move (unit_moved never fires here).
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Required for horde markers to do anything — without it every horde is treated as never-spotted.
@export var camera_path: NodePath
@export var event_manager_path: NodePath  ## Optional — without it, COMBAT events simply don't pulse a marker.
@export var wall_manager_path: NodePath  ## Optional — without it, wall segments have no Strategic marker.
@export var logistics_network_path: NodePath  ## Optional — without it, every wall marker reads as "outer" forever, and ZoC markers never appear.
@export var noise_manager_path: NodePath  ## Optional — without it, no Threat Meter markers here (MinimapView's own copy is independent).

var _hex_grid_map: HexGridMap
var _horde_manager: HordeManager
var _camera: CameraController
var _wall_manager: WallManager
var _logistics_network: LogisticsNetwork

var _building_renderer: BuildingMarkerRenderer
var _unit_renderer: UnitMarkerRenderer
var _horde_renderer: HordeMarkerRenderer
var _frontier_renderer: FrontierMarkerRenderer
var _wall_renderer: WallMarkerRenderer
var _zoc_renderer: ZoneOfControlMarkerRenderer
var _threat_renderer: ThreatMarkerRenderer
var _attack_renderer: AttackAlertRenderer

var _building_layer: Node2D
var _frontier_layer: Node2D
var _wall_layer: Node2D
var _unit_layer: Node2D
var _horde_layer: Node2D
var _attack_layer: Node2D
var _threat_layer: Node2D
var _zoc_layer: Node2D

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

	_frontier_renderer = FrontierMarkerRenderer.new(_frontier_layer, _hex_grid_map)

	if building_manager_path != NodePath():
		var building_manager: BuildingManager = get_node(building_manager_path)
		_building_renderer = BuildingMarkerRenderer.new(_building_layer)
		building_manager.building_placed.connect(_building_renderer.on_placed)
		building_manager.building_placed.connect(func(_i: BuildingInstance) -> void: _frontier_renderer.refresh())
		building_manager.building_removed.connect(_building_renderer.on_removed)
		building_manager.building_removed.connect(func(_i: BuildingInstance) -> void: _frontier_renderer.refresh())
		building_manager.building_ruined.connect(_building_renderer.on_ruined)
		building_manager.building_construction_completed.connect(_building_renderer.on_construction_completed)
		_building_renderer.seed(building_manager.get_all_buildings())

	if unit_manager_path != NodePath():
		var unit_manager: UnitManager = get_node(unit_manager_path)
		_unit_renderer = UnitMarkerRenderer.new(_unit_layer)
		unit_manager.unit_trained.connect(_unit_renderer.on_trained)
		unit_manager.unit_removed.connect(_unit_renderer.on_removed)
		_unit_renderer.seed(unit_manager.get_all_units())
	if unit_order_controller_path != NodePath() and _unit_renderer:
		var unit_order_controller: UnitOrderController = get_node(unit_order_controller_path)
		unit_order_controller.unit_moved.connect(_unit_renderer.on_moved)

	var fog_of_war_manager: FogOfWarManager = null
	if fog_of_war_manager_path != NodePath():
		fog_of_war_manager = get_node(fog_of_war_manager_path)
	_horde_renderer = HordeMarkerRenderer.new(_horde_layer, fog_of_war_manager)
	_horde_renderer.spotted.connect(func(horde: Horde) -> void: horde_spotted.emit(horde))
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
		_horde_manager.horde_spawned.connect(_horde_renderer.on_spawned)
		_horde_manager.horde_moved.connect(_horde_renderer.on_moved)
		_horde_manager.horde_removed.connect(_horde_renderer.on_removed)
		_horde_manager.horde_size_changed.connect(_horde_renderer.on_size_changed)
	if fog_of_war_manager:
		fog_of_war_manager.fog_state_changed.connect(_on_fog_state_changed)
	if _horde_manager:
		# Deferred until after fog_of_war_manager is resolved above —
		# on_spawned() needs HordeMarkerRenderer's own visibility check to work.
		_horde_renderer.seed(_horde_manager.get_all_hordes())

	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		visible = not _camera.is_tactical_zoom()

	_attack_renderer = AttackAlertRenderer.new(_attack_layer, self)
	if event_manager_path != NodePath():
		var event_manager: EventManager = get_node(event_manager_path)
		event_manager.event_raised.connect(_attack_renderer.on_event_raised)

	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_renderer = WallMarkerRenderer.new(_wall_layer, _wall_manager)
		_wall_manager.wall_segment_placed.connect(_wall_renderer.on_placed)
		_wall_manager.wall_segment_upgraded.connect(_wall_renderer.on_state_changed)
		_wall_manager.wall_segment_breached.connect(_wall_renderer.on_state_changed)
		_wall_manager.wall_segment_repaired.connect(_wall_renderer.on_state_changed)
		_wall_manager.wall_segment_removed.connect(_wall_renderer.on_removed)
		_wall_renderer.seed(_wall_manager.get_segments())

	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_zoc_renderer = ZoneOfControlMarkerRenderer.new(_zoc_layer, _logistics_network)
		_logistics_network.network_recomputed.connect(_on_logistics_network_recomputed)
		_zoc_renderer.refresh()

	if noise_manager_path != NodePath():
		var noise_manager: NoiseManager = get_node(noise_manager_path)
		_threat_renderer = ThreatMarkerRenderer.new(_threat_layer, _hex_grid_map, noise_manager, fog_of_war_manager)
		noise_manager.noise_recomputed.connect(_threat_renderer.refresh)
		_threat_renderer.refresh()

	_frontier_renderer.refresh()

	DisplaySettings.changed.connect(_sync_layer_visibility)
	_sync_layer_visibility()

func _new_layer(layer_name: String) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	return layer

## The only place this class reads DisplaySettings — every renderer stays
## unaware of it. A layer's own `visible` combines with this whole node's
## (Strategic-vs-Tactical zoom, above) automatically.
func _sync_layer_visibility() -> void:
	_building_layer.visible = DisplaySettings.show_building_markers
	_frontier_layer.visible = DisplaySettings.show_frontier_markers
	_wall_layer.visible = DisplaySettings.show_wall_markers
	_unit_layer.visible = DisplaySettings.show_unit_markers
	_horde_layer.visible = DisplaySettings.show_horde_markers
	_attack_layer.visible = DisplaySettings.show_attack_alerts
	_threat_layer.visible = DisplaySettings.show_threat_meter_world
	_zoc_layer.visible = DisplaySettings.show_zoc_world
	# No terrain-hazard layer here any more: elevation/impassability moved to
	# ElevationReliefView, which is NOT gated on Tactical zoom the way this
	# whole node is. DisplaySettings.show_terrain_hazards still owns that
	# toggle, it is just read there instead.

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = not is_tactical

## Covers a horde stationary (or off-screen entirely) when the reason its
## visibility changes is something ELSE moving — a building placed/removed, a
## supply line cut, night contraction — none of which fire horde_moved.
func _on_fog_state_changed(coord: Vector2i, state: GameEnums.FogState) -> void:
	if not _horde_manager:
		return
	_horde_renderer.on_fog_state_changed(coord, state, _horde_manager.get_hordes_at(coord))

## Territory shifting can flip a wall segment's outer/legacy classification
## without the segment itself changing at all (no placed/upgraded/breached/
## repaired signal fires) — this listens to LogisticsNetwork's own recompute
## signal directly, the same trigger FogOfWarManager/DiscontentManager key
## their own ZoC-dependent recomputes off.
func _on_logistics_network_recomputed() -> void:
	if _wall_renderer:
		_wall_renderer.refresh_looks()
	if _zoc_renderer:
		_zoc_renderer.refresh()
