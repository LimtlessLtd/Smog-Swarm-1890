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
## UnitInstance/Horde by this phase). Read fresh every frame regardless of
## how that value is currently being written — continuous, real-time
## motion (MovementStepper, a later pass, user request) needed zero changes
## here as a result; this class was already "continuous-movement-ready".
##
## Squad headcount (UnitInstance.get_squad_headcount()) and zombie figure
## count are DERIVED, not separately tracked (design doc, decided) — no
## signal reliably covers every way current_hp/size can change (combat,
## Phase 2.5.4's own Garrison healing, Phase 5.9 casualty accumulation), so
## this class just re-polls UnitManager/HordeManager's live instance lists
## every frame while visible and diffs against what it drew last time,
## same "cheap self-healing full recompute" shape LocalDetailManager already
## uses for its own camera-driven neighborhood refresh — only redrawing a
## group's figures when its (headcount, fidelity) pair actually changed,
## not every frame.
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
##
## **Phase 2.5.5 (Multi-Tier Visual Fidelity/LOD):** this class owns all
## three of Tactical zoom's internal fidelity bands (GameEnums.
## TacticalFidelity), driven by CameraController.tactical_fidelity_changed —
## HIGH is exactly the per-figure rendering this class already did before
## 2.5.5; LOW/MEDIUM are new, coarser bands as the camera sits closer to
## tactical_zoom_threshold. A fidelity change clears both headcount caches
## outright (their cached value now encodes fidelity too, via a Vector2i
## key) so every currently-tracked group redraws under the new band on the
## very next _process() poll — no per-group bookkeeping needed beyond that.

const FIGURE_COLOR := Color(0.85, 0.8, 0.7)    ## Player-unit squad figures (HIGH) — pale "uniform" tone, distinct from terrain/prop/building colors.
const VEHICLE_COLOR := Color(0.5, 0.46, 0.32)  ## Tier 4-5 single-model units (HIGH) — a heavier, darker tone than a squad figure.
const ZOMBIE_COLOR := Color(0.33, 0.4, 0.27)   ## Sickly green-grey, distinct from both.

const FIGURE_RADIUS := 6.0
const VEHICLE_RADIUS := 16.0
const ZOMBIE_RADIUS := 5.0
const FIGURE_SPREAD := 20.0  ## How far individual squad/zombie figures scatter from their entity's own local_position.

## Performance safety net for this naive per-node approach — see this
## class's own doc comment on why the design doc's own much larger cap
## doesn't apply here.
const MAX_RENDERED_ZOMBIES := 30

## LOW fidelity (design doc: "simple silhouettes/blobs ... shape-and-color
## differentiated enough to tell unit from building from zombie") — one
## uniform blob per unit regardless of role/tier, one per horde regardless
## of size. Unit blob stays a circle (matches HIGH's own figure shape);
## the horde blob is deliberately a DIAMOND instead — the same shape
## StrategicOverlayManager's own horde marker already uses at Strategic
## zoom (2.7.6), so "unit vs zombie" reads by shape, not color alone, at
## the lowest Tactical fidelity too.
const LOW_UNIT_RADIUS := 10.0
const LOW_ZOMBIE_RADIUS := 10.0

## MEDIUM fidelity (design doc: "some discernible detail — enough to tell a
## unit's role or tier apart, not yet individual-figure detail") — one
## marker per unit, shaped by role (circle/triangle/diamond, the same
## "shape distinguishes, not just color" accessibility principle every
## other marker in this project already follows) and sized by tier. Hordes
## get a small FIXED-size cluster, deliberately not the true headcount —
## more detail than LOW's single blob, deliberately less than HIGH's full
## (capped) count.
const MEDIUM_UNIT_BASE_RADIUS := 7.0
const MEDIUM_UNIT_TIER_STEP := 1.5  ## Added per definition.tier, so a Tier 5 marker reads visibly larger than a Tier 0 one.
const MEDIUM_MELEE_COLOR := Color(0.72, 0.32, 0.28)   ## Rust red.
const MEDIUM_RANGED_COLOR := Color(0.35, 0.55, 0.78)  ## Blue.
const MEDIUM_SPECIAL_COLOR := Color(0.62, 0.5, 0.78)  ## Violet.
const MEDIUM_ZOMBIE_CLUSTER_SIZE := 5

@export var unit_manager_path: NodePath
@export var horde_manager_path: NodePath
@export var fog_of_war_manager_path: NodePath  ## Optional — unset renders every horde regardless of vision, same "gracefully skip it" convention as every other optional dependency in this project.
@export var camera_path: NodePath

var _unit_manager: UnitManager
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager
var _camera: CameraController

var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH

var _unit_groups: Dictionary = {}      # int (UnitInstance.id) -> Node2D
var _unit_draw_keys: Dictionary = {}   # int (UnitInstance.id) -> Vector2i(headcount, fidelity), last-drawn
var _horde_groups: Dictionary = {}     # int (Horde.id) -> Node2D
var _horde_draw_keys: Dictionary = {}  # int (Horde.id) -> Vector2i(display_count, fidelity), last-drawn

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
		_camera.tactical_fidelity_changed.connect(_on_fidelity_changed)
		visible = _camera.is_tactical_zoom()
		_fidelity = _camera.get_tactical_fidelity()

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_units()
	_refresh_hordes()

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	visible = is_tactical

## Phase 2.5.5: a band change alone doesn't change the map's true headcount/
## size numbers, so the plain per-entity redraw-skip check below would never
## notice — clearing both caches forces every currently-tracked group to
## redraw under the new band next poll (see this class's own doc comment).
func _on_fidelity_changed(fidelity: GameEnums.TacticalFidelity) -> void:
	_fidelity = fidelity
	_unit_draw_keys.clear()
	_horde_draw_keys.clear()

## --- Units (squads / single vehicle models / role markers / blobs) --------

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
			_unit_draw_keys.erase(id)

func _update_unit_group(instance: UnitInstance) -> void:
	var group: Node2D = _unit_groups[instance.id]
	group.position = HexCoord.axial_to_world(instance.hex_coord) + instance.local_position

	var headcount := instance.get_squad_headcount()
	var draw_key := Vector2i(headcount, _fidelity)
	if _unit_draw_keys.get(instance.id, Vector2i(-1, -1)) == draw_key:
		return
	_unit_draw_keys[instance.id] = draw_key

	for child in group.get_children():
		child.queue_free()
	if headcount <= 0:
		return  # Destroyed this frame, about to be removed via unit_removed — draw nothing rather than a stale figure.

	match _fidelity:
		GameEnums.TacticalFidelity.LOW:
			group.add_child(_build_figure(FIGURE_COLOR, LOW_UNIT_RADIUS, Vector2.ZERO))
		GameEnums.TacticalFidelity.MEDIUM:
			group.add_child(_build_role_marker(instance))
		_:  # HIGH — unchanged from before 2.5.5.
			if instance.is_squad_rendered():
				for i in range(headcount):
					group.add_child(_build_figure(FIGURE_COLOR, FIGURE_RADIUS, _scatter_offset(i, headcount)))
			else:
				group.add_child(_build_figure(VEHICLE_COLOR, VEHICLE_RADIUS, Vector2.ZERO))

## MEDIUM fidelity's "tell a unit's role or tier apart" marker — shape by
## role (never color alone, same accessibility principle every other marker
## in this project follows), radius by tier.
func _build_role_marker(instance: UnitInstance) -> Node2D:
	var radius := MEDIUM_UNIT_BASE_RADIUS + float(instance.definition.tier) * MEDIUM_UNIT_TIER_STEP
	var shape := Polygon2D.new()
	match instance.definition.role:
		GameEnums.UnitRole.MELEE:
			shape.color = MEDIUM_MELEE_COLOR
			shape.polygon = _circle_points(radius)
		GameEnums.UnitRole.RANGED:
			shape.color = MEDIUM_RANGED_COLOR
			shape.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius * 0.87, radius * 0.5), Vector2(-radius * 0.87, radius * 0.5)])  # Triangle.
		_:  # SPECIAL
			shape.color = MEDIUM_SPECIAL_COLOR
			shape.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])  # Diamond.
	return shape

## --- Hordes (zombie blobs / clusters) --------------------------------------

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
			_horde_draw_keys.erase(id)

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

	var display_count := _horde_display_count(horde.size)
	var draw_key := Vector2i(display_count, _fidelity)
	if _horde_draw_keys.get(horde.id, Vector2i(-1, -1)) == draw_key:
		return
	_horde_draw_keys[horde.id] = draw_key

	for child in group.get_children():
		child.queue_free()
	if display_count <= 0:
		return

	if _fidelity == GameEnums.TacticalFidelity.LOW:
		group.add_child(_build_diamond(ZOMBIE_COLOR, LOW_ZOMBIE_RADIUS))
	else:
		for i in range(display_count):
			group.add_child(_build_figure(ZOMBIE_COLOR, ZOMBIE_RADIUS, _scatter_offset(i, display_count)))

## How many individual zombie figures to actually draw for a horde of
## `size` — LOW collapses to a single blob (display_count itself doesn't
## matter beyond ">0", the LOW branch above always draws exactly one
## diamond), MEDIUM shows a small fixed cluster regardless of true size
## (more detail than LOW, deliberately less than the real count), HIGH
## shows the real (capped) count, unchanged from before 2.5.5.
func _horde_display_count(size: int) -> int:
	if size <= 0:
		return 0
	match _fidelity:
		GameEnums.TacticalFidelity.LOW:
			return 1
		GameEnums.TacticalFidelity.MEDIUM:
			return mini(size, MEDIUM_ZOMBIE_CLUSTER_SIZE)
		_:  # HIGH
			return mini(size, MAX_RENDERED_ZOMBIES)

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

func _build_diamond(color: Color, radius: float) -> Node2D:
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)])
	return shape

func _circle_points(radius: float, segments: int = 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
