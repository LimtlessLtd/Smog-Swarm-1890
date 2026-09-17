extends Node

## Every settlement hex the map generator produces is passable. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/verify_settlement_passability.tscn
##
## HexMapGenerator stamps settlements last so "a settlement's identity should always
## win its own footprint", but the stamp used to keep an earlier stamp's
## terrain_feature. Chat Moss's PEAT_BOG survived under Manchester's (79, 119), and
## HexCell.is_passable() made the whole settlement hex impassable: no unit could
## route out of it (found choosing the vertical slice's start, 2026-09-16). A
## settlement hex that nothing can leave is a start, a scenario or a founded town
## that silently does not work.
##
## Runs the real generator rather than a fixture: the defect lives in the order the
## real geography features are stamped, which a fixture would not reproduce.

func _ready() -> void:
	var started := Time.get_ticks_msec()
	var cells: Dictionary = HexMapGenerator.new().generate()
	var settlements := 0
	var failures: Array[String] = []
	for cell: HexCell in cells.values():
		if not cell.is_settlement:
			continue
		settlements += 1
		if not cell.is_passable():
			failures.append("%s %s is a settlement but impassable (biome %s, feature %s, height level %d)" % [cell.coord, cell.region_name, GameEnums.BiomeType.keys()[cell.biome_type], GameEnums.TerrainFeature.keys()[cell.terrain_feature], cell.height_level()])
	print("%d settlement hexes checked in %d ms" % [settlements, Time.get_ticks_msec() - started])
	if settlements == 0:
		failures.append("the generator produced no settlement hexes, so nothing was checked")
	var manchester: HexCell = cells.get(Vector2i(79, 119))
	if manchester:
		print("(79, 119): %s, settlement %s, feature %s, passable %s" % [manchester.region_name, manchester.is_settlement, GameEnums.TerrainFeature.keys()[manchester.terrain_feature], manchester.is_passable()])
	if failures.is_empty():
		print("All settlement hexes are passable.")
		get_tree().quit(0)
		return
	print("FAILED (%d):" % failures.size())
	for failure in failures:
		print("  " + failure)
	get_tree().quit(1)
