extends Node

## Player-facing places read as places, never as axial coordinates. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_location_names.tscn
##
## Alerts said "A large horde (1500 strong) has been spotted near (82, 119)!"; FB-2
## asks that every alert say where, and a coordinate is not a where. EventManager,
## ConsequenceLog and UnitPanelView now name hexes through LocationNames.describe().
##
## 1. The player's own hex is "at your town".
## 2. A hex with a region name uses it, with direction and distance from the town.
## 3. Unnamed ground is named by its biome, with direction and distance.
## 4. No description, for any hex in the fixture, contains "(q, r)".

const _HOME := Vector2i.ZERO
const _FIXTURE_RADIUS: int = 3

var _failures: Array[String] = []


func _ready() -> void:
	var map: HexGridMap = load("res://scenes/world/HexGridMap.tscn").instantiate()
	map.name = "HexGridMap"
	map.auto_generate_on_ready = false
	add_child(map)
	map.load_cells(_build_fixture_cells())
	var buildings: BuildingManager = load("res://scenes/buildings/BuildingManager.tscn").instantiate()
	buildings.name = "BuildingManager"
	buildings.hex_grid_map_path = NodePath("../HexGridMap")
	add_child(buildings)

	var home := LocationNames.describe(_HOME, buildings)
	var named := LocationNames.describe(Vector2i(0, -2), buildings)
	var moor := LocationNames.describe(Vector2i(2, 0), buildings)
	print("1. home: %s\n2. named: %s\n3. moor: %s" % [home, named, moor])
	_expect(home, "at your town", "the player's own hex")
	# Axial (0, -2) lies north-west on screen in this layout; the bearing is the
	# on-screen direction, which is what a player looking at the map checks it against.
	_expect(named, "at Chat Moss, 2 hexes north-west of your town", "a named hex two up-left")
	_expect(moor, "on the moor 2 hexes east of your town", "unnamed moorland two east")

	var coordinate := RegEx.create_from_string("\\(-?\\d+, -?\\d+\\)")
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		var text := LocationNames.describe(coord, buildings)
		if coordinate.search(text) != null:
			_failures.append("%s described with a raw coordinate: %s" % [coord, text])

	print()
	if _failures.is_empty():
		print("All location-name checks passed.")
		get_tree().quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		get_tree().quit(1)


func _expect(got: String, want: String, what: String) -> void:
	if got != want:
		_failures.append("%s described as '%s', want '%s'" % [what, got, want])


func _build_fixture_cells() -> Dictionary:
	var cells: Dictionary = {}
	for coord in HexCoord.hex_disk(_HOME, _FIXTURE_RADIUS):
		var cell := HexCell.new(coord)
		if coord == _HOME:
			cell.is_settlement = true
			cell.biome_type = GameEnums.BiomeType.URBAN
			cell.region_name = "Manchester"
		elif coord == Vector2i(0, -2):
			cell.biome_type = GameEnums.BiomeType.WETLAND
			cell.region_name = "Chat Moss"
		cells[coord] = cell
	return cells
