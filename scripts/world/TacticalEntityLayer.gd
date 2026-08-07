class_name TacticalEntityLayer
extends Node2D

## Design doc Phase 2.5.4: individual-figure rendering at Tactical zoom — a
## squad of UnitInstance.SQUAD_SIZE figures for Tier 0-3 units, one larger
## model for Tier 4-5 (the roster's named vehicles — "a squad of siege
## howitzers doesn't make sense the way a squad of Redcoats does"), and a
## capped cluster of individual zombie figures per Horde. This is the piece
## that was always missing from Tactical view: StrategicOverlayManager's own
## unit/horde markers (Phase 2.7.4/2.7.6) hide entirely while zoomed in
## (`visible = not is_tactical`), so before this class existed a unit or
## horde standing on a hex rendered as literally nothing the moment the
## camera crossed into Tactical zoom.
##
## Deliberately NOT gated on LocalDetailManager's hex-hydration set
## (settled/frontier-only, Phase 2.5.1) the way TacticalHexView's
## terrain/props/buildings are — a unit or horde crossing an otherwise-
## abstract wilderness hex still needs to be visible while the player is
## zoomed in looking straight at it, and gating on hydration would just
## reproduce the exact invisibility gap this class exists to close. Only
## camera zoom mode gates this layer; entities render at the same
## HexCoord.axial_to_world(hex_coord) + local_position world point props/
## buildings already use (Phase 2.5.3's local_position pattern, extended to
## UnitInstance/Horde by this phase — see HexCoord.entry_local_position()).
##
## Squad headcount (UnitInstance.get_squad_headcount()) and zombie figure
## count are DERIVED, not separately tracked (design doc, decided) — no
## signal reliably covers every way current_hp/size can change (combat,
## Phase 2.5.4's own Garrison healing, Phase 5.9 casualty accumulation), so
## this class just re-polls UnitManager/HordeManager's live instance lists
## every frame while visible and diffs against what it drew last time,
## same "cheap self-healing full recompute" shape LocalDetailManager already
## uses for its own camera-driven neighborhood refresh — only redrawing a
## group's figures when its headcount actually changed, not every frame.
##
## Parented as a WorldRoot sibling, same reasoning as every other Tactical-
## adjacent overlay (LocalDetailManager, StrategicOverlayManager,
## UnitCommandController): shares the same coordinate space, including
## whatever transform CameraController applies for the isometric toggle.
##
## Rendering-at-scale (the design doc's own ~5,000-100,000 GPU-batched-
## MultiMeshInstance2D note under Phase 5.10) is deliberately NOT built here
## — MAX_RENDERED_ZOMBIES below is a much smaller placeholder cap for this
## naive one-Polygon2D-per-figure approach, not that future system.

const FIGURE_COLOR := Color(0.85, 0.8, 0.7)    ## Player-unit squad figures — pale "uniform" tone, distinct from terrain/prop/building colors.
const VEHICLE_COLOR := Color(0.5, 0.46, 0.32)  ## Tier 4-5 single-model units — a heavier, darker tone than a squad figure.
const ZOMBIE_COLOR := Color(0.33, 0.4, 0.27)   ## Sickly green-grey, distinct from both.

const FIGURE_RADIUS := 6.0
const VEHICLE_RADIUS := 16.0
const ZOMBIE_RADIUS := 5.0
const FIGURE_SPREAD := 20.0  ## How far individual squad/zombie figures scatter from their entity's own local_position.

## Performance safety net for this naive per-node approach — see this
## class's own doc comment on why the design doc's own much larger cap
## doesn't apply here.
const MAX_RENDERED_ZOMBIES := 30

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Optional — unset renders every horde regardless of vision, same "gracefully skip it" convention as every other optional dependency in this project.
@export var camera_path: NodePath

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager
var _camera: CameraController

var _unit_groups: Dictionary = {}      # int (UnitInstance.id) -> Node2D
var _unit_headcounts: Dictionary = {}  # int (UnitInstance.id) -> int, last-drawn figure count
var _horde_groups: Dictionary = {}     # int (Horde.id) -> Node2D
var _horde_headcounts: Dictionary = {} # int (Horde.id) -> int, last-drawn (capped) figure count

func _ready() -> void:
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
	if fog_of_war_manager_path != NodePath():
		_fog_of_war_manager = get_node(fog_of_war_manager_path)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		visible = _camera.is_tactical_zoom()

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_units()
	_refresh_hordes()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical

## --- Units (squads / single vehicle models) --------------------------------

func _refresh_units() -> void:
	if not _unit_manager:
		return
	var seen: Dictionary = {}  # int -> true
	for instance in _unit_manager.get_all_units():
		seen[instance.id] = true
		if not _unit_groups.has(instance.id):
			var group := Node2D.new()
			add_child(group)
			_unit_groups[instance.id] = group
		_update_unit_group(instance)
	for id in _unit_groups.keys():
		if not seen.has(id):
			_unit_groups[id].queue_free()
			_unit_groups.erase(id)
			_unit_headcounts.erase(id)

func _update_unit_group(instance: UnitInstance) -> void:
	var group: Node2D = _unit_groups[instance.id]
	group.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position

	var headcount := instance.get_squad_headcount()
	if _unit_headcounts.get(instance.id, -1) == headcount:
		return
	_unit_headcounts[instance.id] = headcount

	for child in group.get_children():
		child.queue_free()
	if headcount <= 0:
		return  # Destroyed this frame, about to be removed via unit_removed — draw nothing rather than a stale figure.
	if instance.is_squad_rendered():
		for i in range(headcount):
			group.add_child(_build_figure(FIGURE_COLOR, FIGURE_RADIUS, _scatter_offset(i, headcount)))
	else:
		group.add_child(_build_figure(VEHICLE_COLOR, VEHICLE_RADIUS, Vector2.ZERO))

## --- Hordes (zombie clusters) -----------------------------------------------

func _refresh_hordes() -> void:
	if not _horde_manager:
		return
	var seen: Dictionary = {}  # int -> true
	for horde in _horde_manager.get_all_hordes():
		seen[horde.id] = true
		if not _horde_groups.has(horde.id):
			var group := Node2D.new()
			add_child(group)
			_horde_groups[horde.id] = group
		_update_horde_group(horde)
	for id in _horde_groups.keys():
		if not seen.has(id):
			_horde_groups[id].queue_free()
			_horde_groups.erase(id)
			_horde_headcounts.erase(id)

## Individual zombie figures are live-vision intel, not remembered-terrain
## intel — gated on VISIBLE (Fog of War, Phase 2.6), a strictly stricter bar
## than TacticalHexView's own at-least-EXPLORED requirement for terrain and
## buildings, matching the Strategic spotted-horde-marker's own "ghost once
## vision is lost" philosophy (Phase 2.7.6) rather than that class's
## specific ghost-rendering mechanism.
func _update_horde_group(horde: Horde) -> void:
	var group: Node2D = _horde_groups[horde.id]
	group.position = HexCoord.axial_to_world(horde.hex_coord) + horde.local_position
	group.visible = _fog_of_war_manager == null or _fog_of_war_manager.is_visible(horde.hex_coord)

	var headcount := mini(horde.size, MAX_RENDERED_ZOMBIES)
	if _horde_headcounts.get(horde.id, -1) == headcount:
		return
	_horde_headcounts[horde.id] = headcount

	for child in group.get_children():
		child.queue_free()
	for i in range(headcount):
		group.add_child(_build_figure(ZOMBIE_COLOR, ZOMBIE_RADIUS, _scatter_offset(i, headcount)))

## --- Shared figure drawing --------------------------------------------------

## Deterministic (index-seeded, not random) so the same figure count always
## scatters into the same shape — a ring around the group's own
## local_position, same "spread stacked entries out for legibility" idea
## TacticalHexView._resolved_building_position() already uses for multiple
## buildings sharing one hex.
func _scatter_offset(index: int, total: int) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var angle := TAU * float(index) / float(total)
	return Vector2(cos(angle), sin(angle)) * FIGURE_SPREAD

func _build_figure(color: Color, radius: float, offset: Vector2) -> Node2D:
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = _circle_points(radius)
	shape.position = offset
	return shape

func _circle_points(radius: float, segments: int = 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
