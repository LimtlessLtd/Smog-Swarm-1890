class_name LocalDetailManager
extends Node2D

## Orchestrates the Strategic <-> Tactical hard-cut zoom switch (Phase 2.5).
## Listens for CameraController crossing its tactical_zoom_threshold, then
## hydrates a small neighborhood of hexes around wherever the camera is
## centered into full TacticalHexView detail — and only for hexes that
## qualify as settled/frontier (see _hex_qualifies_for_detail); distant
## unclaimed wilderness stays an abstract HexCellView tile even at max zoom,
## which is what keeps this affordable for a map the size of Great Britain.
##
## Parented as a sibling of HexGridMap under WorldRoot (not under Main like
## the other Phase 2 systems) specifically so its spawned TacticalHexViews
## share HexGridMap's local coordinate space and render on top of it by
## plain sibling draw order — added after HexGridMap in Main.tscn.
##
## Phase 2.5.5: also tracks CameraController's internal Tactical fidelity
## band (GameEnums.TacticalFidelity) and pushes it to every hydrated
## TacticalHexView (see _on_fidelity_changed()) — a hex hydrating fresh
## picks up whatever band is current at that moment, an already-hydrated
## one updates live as the camera zooms deeper within Tactical view.

const DETAIL_RADIUS: int = 1  ## Hex disk radius hydrated around the camera; 1 = center + its 6 neighbors.

## Tactical-scale multiplier over WallVisuals.line_width()'s own Strategic-
## zoom values (3.0 + tier*2.0 world units — sized to read at Strategic's
## zoomed-way-out scale). Same rescale reasoning as
## TacticalHexView.BUILDING_HALF_SIZE's own doc comment: a Strategic-scale
## line width against a 512-unit hex would be a hairline, not a wall.
const WALL_TACTICAL_WIDTH_SCALE: float = 8.0

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var logistics_network_path: NodePath
@export var camera_path: NodePath
@export var fog_of_war_path: NodePath
## Optional — Tactical-zoom wall rendering (user report: "I can't see the
## walls on the maps"). Unset means walls simply don't render up close,
## same "gracefully skip it" convention as every other optional dependency
## here; StrategicOverlayManager's own thin markers are unaffected either way.
@export var wall_manager_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _logistics_network: LogisticsNetwork
var _camera: CameraController
var _fog_of_war: FogOfWarManager
var _wall_manager: WallManager

var _is_tactical_mode: bool = false
var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH  ## Phase 2.5.5 — pushed to every hydrated TacticalHexView; see _on_fidelity_changed().
var _last_centered_coord: Vector2i = Vector2i.ZERO
var _tactical_views: Dictionary = {}  # Vector2i -> TacticalHexView
var _wall_layer: Node2D
var _wall_markers: Dictionary = {}  # int (WallSegment.id) -> Line2D

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_buildings_changed)
		_building_manager.building_removed.connect(_on_buildings_changed)
		_building_manager.building_ruined.connect(_on_building_ruined)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_logistics_network.network_recomputed.connect(_on_network_recomputed)
	if camera_path != NodePath():
		_camera = get_node(camera_path)
		_camera.tactical_mode_changed.connect(_on_tactical_mode_changed)
		_camera.tactical_fidelity_changed.connect(_on_fidelity_changed)
		_fidelity = _camera.get_tactical_fidelity()
	if fog_of_war_path != NodePath():
		_fog_of_war = get_node(fog_of_war_path)
		_fog_of_war.fog_state_changed.connect(_on_fog_state_changed)

	_wall_layer = Node2D.new()
	_wall_layer.name = "TacticalWallLayer"
	_wall_layer.visible = false  # Only ever shown while _is_tactical_mode — see _on_tactical_mode_changed().
	add_child(_wall_layer)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_manager.wall_segment_placed.connect(_on_wall_segment_placed)
		_wall_manager.wall_segment_upgraded.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_breached.connect(_on_wall_segment_state_changed)
		_wall_manager.wall_segment_repaired.connect(_on_wall_segment_state_changed)
		for segment in _wall_manager.get_segments():
			_on_wall_segment_placed(segment)

func _process(_delta: float) -> void:
	if not _is_tactical_mode or not _hex_grid_map or not _camera:
		return
	var centered_coord := _hex_grid_map.world_to_coord(_camera.global_position)
	if centered_coord != _last_centered_coord:
		_last_centered_coord = centered_coord
		_refresh_hydrated_neighborhood(centered_coord)

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	_is_tactical_mode = is_tactical
	_wall_layer.visible = is_tactical  ## Strategic keeps its own thin StrategicOverlayManager markers; this thicker layer is Tactical-only, same hard-cut precedent CameraController's own zoom threshold already sets everywhere else.
	if not is_tactical:
		_dehydrate_all()
		return
	if _hex_grid_map and _camera:
		_last_centered_coord = _hex_grid_map.world_to_coord(_camera.global_position)
	_refresh_hydrated_neighborhood(_last_centered_coord)

func _hex_qualifies_for_detail(coord: Vector2i) -> bool:
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return false
	# Fog of War (Phase 2.6): an UNSEEN hex has nothing known to draw, at any
	# zoom — it must be at least EXPLORED before Tactical detail hydrates.
	if _fog_of_war and not _fog_of_war.is_at_least_explored(coord):
		return false
	if cell.is_settlement:
		return true
	if _building_manager and not _building_manager.get_buildings_at(coord).is_empty():
		return true
	if _logistics_network:
		var zoc := _logistics_network.get_zoc_state(coord)
		if zoc.has_military_coverage() or zoc.has_civilian_coverage:
			return true
	return false

## Design doc, user request (local obstacle avoidance): props only exist as
## live `PropInstance` objects while their hex is hydrated — this returns
## `[]` for a dehydrated/unqualified/off-map hex rather than an error,
## exactly like `_hex_qualifies_for_detail()`'s own "distant wilderness
## just doesn't have detail" contract. `MovementStepper`'s callers
## (`UnitOrderController`/`HordeManager`) use this to gather steering
## obstacles — meaning prop avoidance only ever applies near the camera
## (where a hex is actually hydrated), which is also the only place a
## player can actually see it happen.
func get_props_at(coord: Vector2i) -> Array[PropInstance]:
	var view: TacticalHexView = _tactical_views.get(coord)
	return view.get_props() if view else []

func _refresh_hydrated_neighborhood(center: Vector2i) -> void:
	if not _hex_grid_map:
		return
	var wanted: Dictionary = {}  # Vector2i -> true
	for coord in HexCoord.hex_disk(center, DETAIL_RADIUS):
		if _hex_qualifies_for_detail(coord):
			wanted[coord] = true

	for coord in _tactical_views.keys():
		if not wanted.has(coord):
			_dehydrate_hex(coord)
	for coord in wanted:
		if not _tactical_views.has(coord):
			_hydrate_hex(coord)

func _hydrate_hex(coord: Vector2i) -> void:
	var cell := _hex_grid_map.get_cell(coord)
	if not cell:
		return
	var buildings: Array[BuildingInstance] = []
	if _building_manager:
		buildings = _building_manager.get_buildings_at(coord)
	var fog_state := GameEnums.FogState.VISIBLE
	if _fog_of_war:
		fog_state = _fog_of_war.get_fog_state(coord)
	var zoc_state: ZoneOfControlState = null
	if _logistics_network:
		zoc_state = _logistics_network.get_zoc_state(coord)
	var view := TacticalHexView.new()
	view.setup(cell, LocalDetailGenerator.generate(cell), buildings, fog_state, _fidelity, zoc_state)
	add_child(view)
	_tactical_views[coord] = view

func _dehydrate_hex(coord: Vector2i) -> void:
	var view: TacticalHexView = _tactical_views.get(coord)
	if view:
		view.queue_free()
	_tactical_views.erase(coord)

func _dehydrate_all() -> void:
	for coord in _tactical_views.keys():
		_dehydrate_hex(coord)

## Placing/removing a building can change what an already-hydrated hex looks
## like, or whether it should be hydrated at all (newly/no-longer qualifies).
## _refresh_hydrated_neighborhood() alone only adds/removes hexes it doesn't
## already have a view for, so an already-hydrated hex's stale view needs an
## explicit tear-down first to actually pick up the change.
func _on_buildings_changed(instance: BuildingInstance) -> void:
	if not _is_tactical_mode:
		return
	if _tactical_views.has(instance.hex_coord):
		_dehydrate_hex(instance.hex_coord)
	_refresh_hydrated_neighborhood(_last_centered_coord)

## Phase 5.12: a ruin doesn't change WHICH buildings exist at a hex, only
## how one of them looks — the same dehydrate/rehydrate _on_buildings_changed()
## already does is a valid (if slightly heavier-handed) way to pick that up,
## reusing that exact method rather than duplicating its body.
func _on_building_ruined(instance: BuildingInstance, _lost_population: int) -> void:
	_on_buildings_changed(instance)

## Zone of Control (Phase 2.3): a ZoC change can flip an already-hydrated
## hex's own overlay without that hex newly qualifying/disqualifying for
## detail at all (e.g. a Garrison two hexes away extends Military coverage
## in here — MILITARY_AURA_RADIUS, user request) — push the new state to
## every currently-hydrated view directly, same "update live" precedent
## _on_fog_state_changed() already sets, rather than relying solely on
## _refresh_hydrated_neighborhood()'s own add/remove-only pass below.
func _on_network_recomputed() -> void:
	if _logistics_network:
		for coord in _tactical_views:
			_tactical_views[coord].set_zoc_state(_logistics_network.get_zoc_state(coord))
	if _is_tactical_mode:
		_refresh_hydrated_neighborhood(_last_centered_coord)

## Phase 2.5.5: pushes the new band to every currently-hydrated hex in
## place (TacticalHexView.set_fidelity() itself no-ops/skips a redraw if
## nothing actually changed) — no dehydrate/rehydrate needed, same "update
## live" precedent _on_fog_state_changed() already sets for fog.
func _on_fidelity_changed(fidelity: GameEnums.TacticalFidelity) -> void:
	_fidelity = fidelity
	for view: TacticalHexView in _tactical_views.values():
		view.set_fidelity(fidelity)

## Fog of War (Phase 2.6): an already-hydrated hex just needs its dimming
## updated live (EXPLORED <-> VISIBLE); a newly-EXPLORED hex that wasn't
## hydrated before (was UNSEEN, blocked by _hex_qualifies_for_detail) may
## now qualify, so the neighborhood still needs a refresh either way.
func _on_fog_state_changed(coord: Vector2i, state: GameEnums.FogState) -> void:
	if _tactical_views.has(coord):
		_tactical_views[coord].set_fog_state(state)
	if _is_tactical_mode:
		_refresh_hydrated_neighborhood(_last_centered_coord)

## --- Tactical-zoom wall rendering (user report: walls were invisible) ------
##
## Mirrors StrategicOverlayManager's own wall-marker shape (a Line2D from
## hex_a's world center to hex_b's, recolored in place on
## placed/upgraded/breached/repaired) almost exactly — same geometry is
## correct at any zoom, a wall really does run between two hex centers
## through their shared edge. The only real difference is
## WALL_TACTICAL_WIDTH_SCALE: WallVisuals.line_width() was tuned to read at
## Strategic's zoomed-way-out scale, which is a hairline against a 512-unit
## Tactical hex — see that constant's own doc comment. No fog-of-war/
## hydration gating (matching StrategicOverlayManager's own precedent for
## walls specifically — "a wall is always the player's own construction,
## same as a building; there's nothing to spot about your own perimeter"):
## _wall_layer's visibility alone (Tactical-mode-only) is enough gating.
func _on_wall_segment_placed(segment: WallSegment) -> void:
	var marker := _build_wall_marker(segment)
	_wall_layer.add_child(marker)
	_wall_markers[segment.id] = marker

func _on_wall_segment_state_changed(segment: WallSegment) -> void:
	var marker: Line2D = _wall_markers.get(segment.id)
	if marker:
		_apply_wall_segment_look(marker, segment)

func _build_wall_marker(segment: WallSegment) -> Line2D:
	var body := Line2D.new()
	# Freehand wall rework: point_a/point_b are the piece's own real
	# placement geometry now, not always a whole hex edge.
	body.points = PackedVector2Array([segment.point_a, segment.point_b])
	_apply_wall_segment_look(body, segment)
	return body

## Deliberately flat-colored, no `WallVisuals.tier_texture()` — user report
## ("issues with the walls not repeating properly across the entire length
## of the wall"). That texture's own tile size was authored for
## StrategicOverlayManager's much-shorter, zoomed-way-out marker line;
## Tactical's own segments span a full hex-center-to-hex-center distance at
## real world scale (hundreds of units) and WALL_TACTICAL_WIDTH_SCALE's own
## 8x width on top of that, so the same texture tiled far more times than
## it was ever designed to and read as noise rather than a wall. A flat
## tier color (StrategicOverlayManager's own pre-art fallback, still
## perfectly legible for tier/breach/gate state) avoids the mismatch
## entirely rather than trying to re-tune tile scale to fit two very
## differently-scaled consumers — real Tactical-specific wall art is a
## future add, not a same-pass fix.
func _apply_wall_segment_look(body: Line2D, segment: WallSegment) -> void:
	var breached := segment.is_breached()
	body.texture = null
	body.default_color = WallVisuals.breached_color() if breached else (WallVisuals.gate_color() if segment.is_gate else WallVisuals.tier_color(segment.tier))
	body.width = WallVisuals.line_width(segment.tier, breached) * WALL_TACTICAL_WIDTH_SCALE
	var is_legacy := _wall_manager != null and _wall_manager.is_legacy_segment(segment)
	body.modulate = WallVisuals.legacy_modulate() if is_legacy else WallVisuals.outer_modulate()
