extends SceneTree

## Reports the height band of every hex belonging to a named MOUNTAIN_RANGE
## feature, through the real HexMapGenerator.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_mountain_ranges.gd
##
## `-s` is safe here for the same reason scripts/test/verify_elevation.gd uses
## it: this touches HexMapGenerator and HexCell only, neither of which
## references an autoload, so the compile cascade that makes `-s` unusable for
## anything holding a manager (see scripts/test/verify_gates.gd's own note)
## does not arise.
##
## Exists because BritishGeographyData's three MOUNTAIN_RANGE features used to
## stamp `cell.elevation = maxf(cell.elevation, 0.75)` = 750 m along a
## hand-drawn hex line, which clears ElevationLevels' 600 m threshold and made
## every hex on the line impassable to units, vehicles and hordes alike. Two of
## the three ranges are not mountains at all -- the Chilterns peak near 258 m
## and the Cotswolds near 321 m -- so that put impassable walls across southern
## England, which is what the relief overlay finally made visible ("what are
## these lines of red hexes on the map indicating?", user report).
##
## The override is gone and real sampled elevation now decides the band. This
## checks the outcome rather than the intent: a range should hold mountain
## hexes only where the ground genuinely is that high, and the two lowland
## ranges should hold none at all.
##
## Exits non-zero if a range that has no ground above the mountain threshold
## still reports a mountain hex, so this is usable as a gate rather than only
## as a report.

## Ranges with no real ground near 600 m -- any Level 4 hex here is an
## authoring artefact, not terrain.
const _EXPECTED_NO_MOUNTAIN: Array[String] = ["Chiltern Hills", "Cotswold Escarpment"]


func _initialize() -> void:
	var generator := HexMapGenerator.new()
	var cells := generator.generate()

	var by_region: Dictionary = {}  ## region_name -> Array[HexCell]
	for coord: Vector2i in cells:
		var cell: HexCell = cells[coord]
		if cell.biome_type != GameEnums.BiomeType.HIGHLAND:
			continue
		if cell.terrain_feature != GameEnums.TerrainFeature.ESCARPMENT:
			continue  ## The MOUNTAIN_RANGE stamp's own signature — real HIGHLAND biome elsewhere is not a named range.
		if not by_region.has(cell.region_name):
			by_region[cell.region_name] = []
		by_region[cell.region_name].append(cell)

	var failures: Array[String] = []
	var names: Array = by_region.keys()
	names.sort()
	for region_name: String in names:
		var region_cells: Array = by_region[region_name]
		var mountain := 0
		var peak_metres := 0.0
		for cell: HexCell in region_cells:
			if ElevationLevels.is_impassable(cell.height_level()):
				mountain += 1
			peak_metres = maxf(peak_metres, ElevationLevels.to_metres(cell.elevation))
		print("%-34s %2d hexes | impassable (Level 4): %2d | highest hex: %4.0f m" % [
			region_name, region_cells.size(), mountain, peak_metres])
		if _EXPECTED_NO_MOUNTAIN.has(region_name) and mountain > 0:
			failures.append("%s reports %d impassable hexes but has no ground near 600 m" % [region_name, mountain])

	for failure in failures:
		print("FAIL: %s" % failure)
	quit(1 if not failures.is_empty() else 0)
