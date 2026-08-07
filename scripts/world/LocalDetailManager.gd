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

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var logistics_network_path: NodePath
@export var camera_path: NodePath
@export var fog_of_war_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _logistics_network: LogisticsNetwork
var _camera: CameraController
var _fog_of_war: FogOfWarManager

var _is_tactical_mode: bool = false
var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH  ## Phase 2.5.5 — pushed to every hydrated TacticalHexView; see _on_fidelity_changed().
var _last_centered_coord: Vector2i = Vector2i.ZERO
var _tactical_views: Dictionary = {}  # Vector2i -> TacticalHexView

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

func _process(_delta: float) -> void:
	if not _is_tactical_mode or not _hex_grid_map or not _camera:
		return
	var centered_coord := _hex_grid_map.world_to_coord(_camera.global_position)
	if centered_coord != _last_centered_coord:
		_last_centered_coord = centered_coord
		_refresh_hydrated_neighborhood(centered_coord)

func _on_tactical_mode_changed(is_tactical: bool) -> void:
	_is_tactical_mode = is_tactical
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
	var view := TacticalHexView.new()
	view.setup(cell, LocalDetailGenerator.generate(cell), buildings, fog_state, _fidelity)
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

func _on_network_recomputed() -> void:
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
