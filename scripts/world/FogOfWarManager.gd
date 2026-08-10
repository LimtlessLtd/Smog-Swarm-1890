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
##
## Phase 2.6.2 (this pass): units are now a vision source too, read from
## UnitManager the identical way buildings are read from BuildingManager —
## same night-vision-contraction and terrain-penalty math applies to both,
## generic over "a vision source at a hex_coord with a vision_radius," not
## special-cased per source type. Closes the design doc's own long-standing
## disclosed gap ("Units still don't feed Fog of War — UnitInstance has no
## vision_radius field yet; FogOfWarManager only iterates buildings") and,
## as a direct consequence, Phase 2.12's matching unit-specific vision-
## reduction gap (it was blocked on this exact field not existing). Units
## have no `lit_at_night` concept (nothing in their own art/description
## frames any unit as a light source the way a Gas Streetlamp or Searchlight
## Tower is) — every unit gets the plain NIGHT_VISION_PENALTY contraction,
## no lit exemption branch.
##
## Recomputes on unit train/remove (building parity) AND on every
## `UnitOrderController.unit_moved` hex-boundary crossing — the same
## granularity vision already operates at (hex_coord, not sub-hex
## local_position), so a moving unit's fog contribution genuinely does
## change at that cadence, not more finely. recompute() rebuilds the ENTIRE
## visible set from scratch (see its own doc comment — "cheap enough...
## dozens of buildings"); wiring it to every unit's hex crossing multiplies
## how often that full rebuild fires, and at this project's higher
## TickManager speeds (up to 1000x) several units can each cross a boundary
## within the same engine frame — **adversarial review finding, fixed
## 2026-08-10:** those same-frame crossings were each triggering their own
## full rebuild even though nothing changes between them. The two unit-
## triggered handlers below (`_on_units_changed`/`_on_unit_moved`) now mark
## `_unit_recompute_pending` instead of calling `recompute()` directly, and
## `_process()` drains it at most once per frame — a real one-frame-max
## latency on units' fog contribution becoming visible (buildings/ZoC/day-
## night triggers are unaffected, left exactly as synchronous as before;
## this project's own established grace-period mechanism already tolerates
## several SECONDS of similar lag on the opposite transition, so a single
## frame here is a non-issue). A dirty-region incremental recompute — doing
## less work per call, rather than calling it less often — would be the
## real fix if per-frame coalescing ever stops being enough.

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
@export var unit_manager_path: NodePath  ## Optional — without it, units simply aren't a vision source (buildings/ZoC still work as before). See this class's own Phase 2.6.2 doc comment above.
@export var unit_order_controller_path: NodePath  ## Optional — without it, unit vision still computes correctly on train/remove/day-night, it just won't refresh live as a unit walks between hexes (unit_moved never fires here). Same "optional, degrades to static-only" contract StrategicOverlayManager's own copy of this path documents.

var _hex_grid_map: HexGridMap
var _building_manager: BuildingManager
var _logistics_network: LogisticsNetwork
var _unit_manager: UnitManager
var _unit_order_controller: UnitOrderController

var _fog_state: Dictionary = {}        # Vector2i -> GameEnums.FogState
var _grace_remaining: Dictionary = {}  # Vector2i -> float; hexes counting down VISIBLE -> EXPLORED

## Coalesces same-frame unit-triggered recompute() calls (Phase 2.6.2's own
## doc comment above explains why) — set by _on_units_changed()/
## _on_unit_moved() instead of calling recompute() directly, drained by
## _process() at most once per frame.
var _unit_recompute_pending: bool = false

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
	if unit_manager_path != NodePath():
		_unit_manager = get_node(unit_manager_path)
		_unit_manager.unit_trained.connect(_on_units_changed)
		_unit_manager.unit_removed.connect(_on_units_changed)
	if unit_order_controller_path != NodePath():
		_unit_order_controller = get_node(unit_order_controller_path)
		_unit_order_controller.unit_moved.connect(_on_unit_moved)
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
	if _unit_recompute_pending:
		_unit_recompute_pending = false
		recompute()
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
	var is_night := TimeCycleManager.is_night()
	if _building_manager:
		for instance in _building_manager.get_all_buildings():
			var radius := instance.definition.vision_radius
			if is_night:
				if instance.definition.lit_at_night:
					radius += NIGHT_LIT_BONUS
				else:
					radius = maxi(0, radius - NIGHT_VISION_PENALTY)
			# Phase 2.12.2: dense local terrain right around the vision source
			# itself shrinks its effective radius — reduces, never blocks
			# (design doc, decided; no stealth mechanic).
			radius = _apply_terrain_penalty(radius, instance.hex_coord)
			for coord in HexCoord.hex_disk(instance.hex_coord, radius):
				if not _hex_grid_map or _hex_grid_map.has_cell(coord):
					result[coord] = true
	if _unit_manager:
		# Phase 2.6.2: units are a vision source too, same radius/night/
		# terrain contract as buildings above — see this class's own doc
		# comment for why there's no lit_at_night branch here.
		for instance in _unit_manager.get_all_units():
			var radius := instance.definition.vision_radius
			if is_night:
				radius = maxi(0, radius - NIGHT_VISION_PENALTY)
			radius = _apply_terrain_penalty(radius, instance.hex_coord)
			for coord in HexCoord.hex_disk(instance.hex_coord, radius):
				if not _hex_grid_map or _hex_grid_map.has_cell(coord):
					result[coord] = true
	if _logistics_network:
		for coord in _logistics_network.get_covered_hexes():
			result[coord] = true
	return result

## Shared by both vision-source loops above (Phase 2.12.2) — dense local
## terrain right around the source itself shrinks its effective radius,
## "reduces, never blocks" (design doc, decided; no stealth mechanic).
func _apply_terrain_penalty(radius: int, coord: Vector2i) -> int:
	if not _hex_grid_map:
		return radius
	var source_cell := _hex_grid_map.get_cell(coord)
	if not source_cell:
		return radius
	return maxi(0, radius - source_cell.get_vision_penalty())

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

func _on_units_changed(_instance: UnitInstance) -> void:
	_unit_recompute_pending = true

func _on_unit_moved(_instance: UnitInstance, _from_coord: Vector2i, _to_coord: Vector2i) -> void:
	_unit_recompute_pending = true

func _on_network_recomputed() -> void:
	recompute()

func _on_phase_changed(_phase: GameEnums.DayPhase) -> void:
	recompute()
