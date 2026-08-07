class_name FogOfWarManager
extends Node

## Three-state Fog of War (design doc Phase 2.6): UNSEEN -> EXPLORED ->
## VISIBLE, per hex. Reads vision sources from BuildingManager
## (BuildingDefinition.vision_radius) and LogisticsNetwork (Military/Civilian
## Zone of Control coverage doubles as vision, per Phase 2.3's original
## "Military ZoC: Supply, Vision & Suppression" intent) — owns neither, only
## derives fog coverage from them, same relationship LogisticsNetwork itself
## has to HexGridMap/BuildingManager. Wired as a Main.tscn sibling of those
## systems (not under WorldRoot: unlike LocalDetailManager/
## StrategicOverlayManager it never spawns its own positioned Node2D
## children, it only pushes state into HexGridMap's existing HexCellViews).
##
## UNSEEN -> EXPLORED is one-way per hex, forever: once scouted, terrain is
## remembered. EXPLORED <-> VISIBLE toggles freely as vision sources come and
## go, EXCEPT losing a hex's last vision source doesn't drop it to EXPLORED
## instantly — it lingers VISIBLE for LOST_VISION_GRACE_SECONDS first
## (design doc, decided), so losing sight of a threat isn't instant/twitchy.
##
## Phase 5.1/2.6.4 night vision contraction: shrinks vision_radius at night
## for every building EXCEPT lit sources (BuildingDefinition.lit_at_night —
## Gas Streetlamp, Church Steeple Watchtower, Searchlight Tower), which hold
## or extend theirs instead (design doc, decided: extend). Recomputed
## whenever TimeCycleManager's phase flips, same trigger as a building being
## placed/removed. Deliberately scoped to building vision_radius only, not
## LogisticsNetwork's Zone-of-Control-derived coverage: ZoC vision represents
## patrol/logistics awareness over a hex, not light cast into the dark, so it
## isn't a "lit source" this contraction has any hook to apply to.
##
## Phase 2.12.2: HexCell.get_vision_penalty() shrinks a building's effective
## vision_radius further still, when that building itself sits on dense
## local vegetation (Moorland/Wetland) — "reduces, does not block", stacks
## with (applied after) the night-vision math above. The three-state
## UNSEEN/EXPLORED/VISIBLE machine this class owns is itself untouched by
## this — only the radius fed into it shrinks.

signal fog_state_changed(coord: Vector2i, state: GameEnums.FogState)

## "A few seconds" per the design doc's own decided grace period — a
## balancing number, not an architecture one.
const LOST_VISION_GRACE_SECONDS: float = 3.0

## Night vision contraction (design doc 2.6.4) — balancing numbers, not
## architecture ones, same as LOST_VISION_GRACE_SECONDS above.
const NIGHT_VISION_PENALTY: int = 1  ## Unlit sources lose this many hex-rings of vision_radius at night (floored at 0).
const NIGHT_LIT_BONUS: int = 1       ## Lit sources (BuildingDefinition.lit_at_night) gain this many instead — "hold or extend theirs".

@export var hex_grid_map_path: NodePath
@export var building_manager_path: NodePath
@export var logistics_network_path: NodePath

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _logistics_network: LogisticsNetwork

var _fog_state: Dictionary = {}        # Vector2i -> GameEnums.FogState
var _grace_remaining: Dictionary = {}  # Vector2i -> float; hexes counting down VISIBLE -> EXPLORED

func _ready() -> void:
	if hex_grid_map_path != NodePath():
		_hex_grid_map = get_node(hex_grid_map_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.building_placed.connect(_on_buildings_changed)
		_building_manager.building_removed.connect(_on_buildings_changed)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
		_logistics_network.network_recomputed.connect(_on_network_recomputed)
	TimeCycleManager.phase_changed.connect(_on_phase_changed)

	# Every generated hex starts UNSEEN and needs its view pushed to match —
	# HexCellView's own default modulate is full color, not blank darkness,
	# so this can't rely on _set_state()'s "already at this state" no-op guard.
	if _hex_grid_map:
		for cell in _hex_grid_map.get_all_cells():
			_fog_state[cell.coord] = GameEnums.FogState.UNSEEN
			_push_view_state(cell.coord, GameEnums.FogState.UNSEEN)
	recompute()

func _process(delta: float) -> void:
	if _grace_remaining.is_empty():
		return
	for coord in _grace_remaining.keys():
		_grace_remaining[coord] -= delta
		if _grace_remaining[coord] <= 0.0:
			_grace_remaining.erase(coord)
			_set_state(coord, GameEnums.FogState.EXPLORED)

func get_fog_state(coord: Vector2i) -> GameEnums.FogState:
	return _fog_state.get(coord, GameEnums.FogState.UNSEEN)

func is_at_least_explored(coord: Vector2i) -> bool:
	return get_fog_state(coord) != GameEnums.FogState.UNSEEN

func is_visible(coord: Vector2i) -> bool:
	return get_fog_state(coord) == GameEnums.FogState.VISIBLE

## Exposed for SaveLoadManager (Phase 2.8) — explored/visible memory is
## genuinely earned by play and can't be re-derived like ZoC can (recompute()
## only ever re-derives the currently-VISIBLE set, never EXPLORED), so unlike
## most of this game's state, this one really does need saving as-is.
func get_save_state() -> Dictionary:
	return _fog_state.duplicate()

## Restores fog state from a save (Phase 2.8.2). Deliberately does NOT call
## recompute() afterward: the saved dictionary is authoritative for the exact
## moment it was saved (including EXPLORED hexes recompute() alone could
## never reproduce), and ongoing gameplay will recompute VISIBLE coverage
## naturally as buildings/ZoC signals fire from here on. Call this AFTER
## restoring buildings/supply lines, not before — otherwise their restoration
## signals would trigger transient recompute()s this then correctly overrides
## anyway, but there's no reason to race it.
func load_save_state(state: Dictionary) -> void:
	_grace_remaining.clear()
	for coord in state:
		_fog_state[coord] = state[coord]
		_push_view_state(coord, state[coord])

## Recomputes the current vision-source set from scratch and reconciles fog
## state against it. Cheap enough to call on every building/ZoC change at
## this scale (dozens of buildings, not thousands) — same reasoning as
## LogisticsNetwork.recompute().
func recompute() -> void:
	var currently_visible := _compute_visible_set()
	for coord in currently_visible:
		_grace_remaining.erase(coord)
		_set_state(coord, GameEnums.FogState.VISIBLE)
	for coord in _fog_state.keys():
		if _fog_state[coord] == GameEnums.FogState.VISIBLE and not currently_visible.has(coord):
			if not _grace_remaining.has(coord):
				_grace_remaining[coord] = LOST_VISION_GRACE_SECONDS

func _compute_visible_set() -> Dictionary:
	var result: Dictionary = {}  # Vector2i -> true
	if _building_manager:
		var is_night := TimeCycleManager.is_night()
		for instance in _building_manager.get_all_buildings():
			var radius := instance.definition.vision_radius
			if is_night:
				if instance.definition.lit_at_night:
					radius += NIGHT_LIT_BONUS
				else:
					radius = maxi(0, radius - NIGHT_VISION_PENALTY)
			# Phase 2.12.2: dense local terrain right around the vision source
			# itself shrinks its effective radius — reduces, never blocks
			# (design doc, decided; no stealth mechanic). Scoped to building
			# vision sources since that's the only vision_radius concept that
			# exists today — a UnitInstance-based version stays blocked on
			# Phase 2.6.2's own already-flagged gap ("Units still don't feed
			# this — UnitInstance has no vision_radius field").
			if _hex_grid_map:
				var source_cell := _hex_grid_map.get_cell(instance.hex_coord)
				if source_cell:
					radius = maxi(0, radius - source_cell.get_vision_penalty())
			for coord in HexCoord.hex_disk(instance.hex_coord, radius):
				if not _hex_grid_map or _hex_grid_map.has_cell(coord):
					result[coord] = true
	if _logistics_network:
		for coord in _logistics_network.get_covered_hexes():
			result[coord] = true
	return result

func _set_state(coord: Vector2i, state: GameEnums.FogState) -> void:
	if _fog_state.get(coord, GameEnums.FogState.UNSEEN) == state:
		return
	_fog_state[coord] = state
	_push_view_state(coord, state)
	fog_state_changed.emit(coord, state)

func _push_view_state(coord: Vector2i, state: GameEnums.FogState) -> void:
	if not _hex_grid_map:
		return
	var view := _hex_grid_map.get_view(coord)
	if view:
		view.set_fog_state(state)

func _on_buildings_changed(_instance: BuildingInstance) -> void:
	recompute()

func _on_network_recomputed() -> void:
	recompute()

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	recompute()
