extends Node

var _main: Node
var _camera: CameraController
const OUT := "user://playtest_fix_shots"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GameLaunchState.request_vertical_slice()
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	_camera = _main.get_node("CameraController")
	_camera.set_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	TickManager.set_speed_index(0)
	_camera.global_position = HexCoord.axial_to_world(VerticalSliceConfig.START_HEX)
	_camera.set_zoom_level(0.7)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _capture("01_overview", 160)
	var commands: UnitCommandController = _main.get_node("WorldRoot/UnitCommandController")
	var units: UnitManager = _main.get_node("UnitManager")
	commands.select_units(units.get_all_units())
	await _capture("02_units", 30)
	var buildings: BuildingManager = _main.get_node("BuildingManager")
	commands.select_building(buildings.get_buildings_at(VerticalSliceConfig.START_HEX)[0])
	await _capture("03_building", 30)
	commands.set_hex_power(VerticalSliceConfig.START_HEX, false)
	await _capture("04_blackout", 30)
	var walls: WallManager = _main.get_node("WallManager")
	var orders: UnitOrderController = _main.get_node("UnitOrderController")
	var wall: WallSegment = walls.get_segments()[10]
	var midpoint := (wall.point_a + wall.point_b) * 0.5
	var inward := (HexCoord.axial_to_world(VerticalSliceConfig.START_HEX) - midpoint).normalized()
	var entries: Array[UnitSaveEntry] = [UnitSaveEntry.new(GameEnums.UnitType.TOXOPHILITE, VerticalSliceConfig.START_HEX, 1001, UnitCatalog.get_definition(GameEnums.UnitType.TOXOPHILITE).max_hp, GameEnums.UnitOrderType.HOLD, Vector2i.ZERO, [], 0, midpoint + inward * 8.0 - HexCoord.axial_to_world(VerticalSliceConfig.START_HEX))]
	units.load_save_entries(entries, 1002)
	var unit := units.get_all_units()[0]
	orders.issue_wall_move_order(unit, wall, midpoint)
	for i in 180:
		orders.advance_orders(1.0 / 60.0)
	commands.select_units([unit])
	_camera.global_position = midpoint
	_camera.set_zoom_level(4.0)
	await _capture("05_wall_access", 60)
	var hordes: HordeManager = _main.get_node("HordeManager")
	var horde := hordes.spawn_local_horde(unit.hex_coord, 80, midpoint - inward * 5.0 - HexCoord.axial_to_world(unit.hex_coord))
	var combat: CombatCoordinator = _main.get_node("CombatCoordinator")
	combat.strike_from_cover(unit, horde)
	await _capture("06_wall_combat", 2)
	for resident in hordes.get_hordes_at(VerticalSliceConfig.TARGET_HEX):
		if resident.resident_target_id != -1:
			continue
		var standing := resident.local_position - Vector2(12, 0)
		var holding: Array[UnitSaveEntry] = [UnitSaveEntry.new(GameEnums.UnitType.TOXOPHILITE, resident.hex_coord, 1002, 18.0, GameEnums.UnitOrderType.HOLD, Vector2i.ZERO, [], 0, standing)]
		units.load_save_entries(holding, 1003)
		unit = units.get_all_units()[0]
		commands.select_units([unit])
		_camera.global_position = HexCoord.axial_to_world(resident.hex_coord) + resident.local_position - Vector2(6, 0)
		_camera.set_zoom_level(8.0)
		await _capture("07_residents_before_contact", 30)
		combat.advance_combat(0.1)
		await _capture("08_stationary_fire", 2)
		break
	print("Screenshots: ", ProjectSettings.globalize_path(OUT))
	get_tree().quit(0)

func _capture(filename: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT.path_join(filename + ".png"))
