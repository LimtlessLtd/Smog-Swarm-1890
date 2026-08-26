extends Node

## Direct playtest of the exact bug report: "units cannot move over hex tile
## borders". Builds a small flat, passable fixture (same load_cells()
## approach verify_gates.gd uses, to skip HexMapGenerator's multi-minute
## full-corridor generation), spawns one real UnitInstance via
## UnitManager.load_save_entries() (the same public entry point
## SaveLoadManager uses, so this exercises real UnitManager/
## UnitOrderController code, not a hand-rolled stand-in), issues a real
## issue_move_order() 5 hexes out, then lets the SceneTree actually run
## frames (await get_tree().process_frame) so UnitOrderController._process()
## ticks the same way it does in a live game — not a hand-simulated loop.
##
## Run (as a real scene, not `-s`, for the same autoload-resolution reason
## verify_gates.gd documents):
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_unit_border_crossing.tscn

const _FIXTURE_RADIUS := 10
const _START: Vector2i = Vector2i.ZERO
const _GOAL: Vector2i = Vector2i(5, 0)  ## 5 hexes out along one axis -- axial distance 5, so this crosses 5 hex borders.
const _MAX_FRAMES := 6000  ## Generous ceiling so a genuine hang still reports FAIL instead of running forever.

var _map: HexGridMap
var _units: UnitManager
var _orders: UnitOrderController


func _ready() -> void:
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_build_fixture_cells())

	_units = load("res://scenes/units/UnitManager.tscn").instantiate()
	_units.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(_units)

	_orders = load("res://scenes/units/UnitOrderController.tscn").instantiate()
	_orders.hex_grid_map_path = NodePath("../HexGridMap")
	_orders.unit_manager_path = NodePath("../UnitManager")
	add_child(_orders)

	var entry := UnitSaveEntry.new(GameEnums.UnitType.TRUNCHEONEER, _START, 1, 100.0)
	_units.load_save_entries([entry], 2)
	var instance := _units.get_all_units()[0]
	print("start: hex=%s local=%s order=%s" % [instance.hex_coord, instance.local_position, instance.order])

	_orders.issue_move_order(instance, _GOAL)
	print("issued move order to %s" % [_GOAL])

	var frame := 0
	var last_hex := instance.hex_coord
	var crossings := 0
	var stalled_frames := 0
	while frame < _MAX_FRAMES:
		await get_tree().process_frame
		frame += 1
		if instance.hex_coord != last_hex:
			crossings += 1
			print("frame %d: crossed into %s (order=%s, path_len=%d)" % [frame, instance.hex_coord, instance.order, instance.path.size()])
			last_hex = instance.hex_coord
			stalled_frames = 0
		else:
			stalled_frames += 1
		if instance.hex_coord == _GOAL and instance.order == GameEnums.UnitOrderType.HOLD:
			print("ARRIVED at frame %d" % frame)
			break
		if stalled_frames == 600:
			print("STALL WARNING: %d frames with no hex change (hex=%s local=%s order=%s path_len=%d)" % [stalled_frames, instance.hex_coord, instance.local_position, instance.order, instance.path.size()])

	print("final: hex=%s local=%s order=%s path_len=%d frames=%d crossings=%d" % [instance.hex_coord, instance.local_position, instance.order, instance.path.size(), frame, crossings])
	if instance.hex_coord == _GOAL:
		print("PASS: unit reached %s in %d frames, %d hex crossings" % [_GOAL, frame, crossings])
		get_tree().quit(0)
	else:
		print("FAIL: unit did not reach %s -- stuck at %s after %d frames" % [_GOAL, instance.hex_coord, frame])
		get_tree().quit(1)


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_START, _FIXTURE_RADIUS):
		cells[coord] = HexCell.new(coord)
	return cells
