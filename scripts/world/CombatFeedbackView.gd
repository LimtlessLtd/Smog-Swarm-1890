class_name CombatFeedbackView
extends Node2D

@export var combat_coordinator_path: NodePath
@export var building_manager_path: NodePath

var _shots: Array[Dictionary] = []
var _buildings: BuildingManager
var _dark_hexes: Array[Vector2i] = []

func _ready() -> void:
	z_index = 40
	var combat := get_node_or_null(combat_coordinator_path) as CombatCoordinator
	if combat:
		combat.engagement_resolved.connect(_on_engagement)
	_buildings = get_node_or_null(building_manager_path) as BuildingManager
	if _buildings:
		for event in ["building_powered_down", "building_powered_up", "building_placed", "building_removed", "building_ruined", "building_construction_completed", "building_repaired"]:
			_buildings.connect(event, func(_a = null, _b = null) -> void: _refresh_blackouts())
		_refresh_blackouts()

func _refresh_blackouts() -> void:
	_dark_hexes.clear()
	var states: Dictionary = {}
	for building in _buildings.get_all_buildings():
		if building.is_ruined or building.is_under_construction or building.definition.always_powered:
			continue
		states[building.hex_coord] = states.get(building.hex_coord, false) or building.is_running()
	for coord in states:
		if not states[coord]:
			_dark_hexes.append(coord)

func _on_engagement(unit: UnitInstance, horde: Horde, result: Dictionary) -> void:
	_shots.append({"from": HexCoord.axial_to_world(unit.hex_coord) + unit.local_position,
		"to": HexCoord.axial_to_world(horde.hex_coord) + horde.local_position,
		"expires": Time.get_ticks_msec() + 650, "kills": result.get("zombies_killed", 0)})

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_shots = _shots.filter(func(shot: Dictionary) -> bool: return shot["expires"] > now)
	queue_redraw()

func _draw() -> void:
	var pixel := 1.0 / maxf(0.001, get_viewport().get_canvas_transform().get_scale().x)
	for shot in _shots:
		var alpha := clampf(float(shot["expires"] - Time.get_ticks_msec()) / 650.0, 0.0, 1.0)
		draw_line(shot["from"], shot["to"], Color(1.0, 0.77, 0.35, alpha), 1.5 * pixel, true)
		draw_arc(shot["to"], 5.0 * pixel, 0, TAU, 12, Color(0.9, 0.3, 0.18, alpha), 2.0 * pixel, true)
	for coord in _dark_hexes:
		var at := HexCoord.axial_to_world(coord)
		draw_set_transform(at, 0.0, Vector2.ONE * pixel)
		draw_style_box(HUDStyles.make_panel_stylebox(), Rect2(-51, -13, 102, 23))
		draw_string(ThemeDB.fallback_font, Vector2(-43, 3), "BLACKOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HUDStyles.ACCENT_COLOR)
	draw_set_transform(Vector2.ZERO)
