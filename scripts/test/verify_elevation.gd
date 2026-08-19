extends SceneTree

## Measures what design_doc.md §5's height bands actually claim on the real
## baked map, and whether making Level 4 MOUNTAIN impassable severs the
## landmass. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_elevation.gd
##
## Same role scripts/test/verify_terrain_mesh.gd plays for the mesh format:
## the thresholds in ElevationLevels are balancing numbers, and the only way
## to know what a given set does to the map is to run it over every hex.
## Reachability is the part that cannot be eyeballed — a threshold that looks
## conservative can still wall a peninsula off behind one summit ridge, and
## the player would meet that as "my units refuse to go there" rather than as
## a visible mountain range.
##
## Reports the DELTA against the pre-elevation passability rule rather than a
## raw stranded count, because a raw count is unreadable: Ireland has no land
## bridge to Great Britain and so is legitimately unreachable on foot, and it
## alone is about a quarter of the map. The question worth answering is
## whether the new rule strands ground that used to be reachable.
##
## Exits non-zero if it does, so this is usable as a gate rather than only as
## a report.

const _START_REGION := "Manchester"

## What is walkable WITHOUT the elevation rule — deliberately a restatement of
## HexCell.is_passable()'s pre-elevation clauses rather than a call to it,
## since the whole measurement is the difference between the two. It has to be
## kept in step with that method by hand; that is the cost of measuring a rule
## against its own predecessor.
static func _passable_ignoring_elevation(cell: HexCell) -> bool:
	return cell.terrain_feature != GameEnums.TerrainFeature.MARSH \
		and cell.terrain_feature != GameEnums.TerrainFeature.PEAT_BOG \
		and cell.biome_type != GameEnums.BiomeType.OCEAN


## Builds the map straight from HexMapGenerator rather than through
## HexGridMap: a SceneTree script's `root` is not usable from _init(), and the
## grid's runtime container/views contribute nothing to a question about cell
## data.
func _init() -> void:
	var cells: Dictionary = HexMapGenerator.new().generate()

	var by_level: Dictionary = {}
	var land := 0
	var passable := 0
	var start := Vector2i.ZERO
	var found_start := false
	for cell: HexCell in cells.values():
		if cell.biome_type == GameEnums.BiomeType.OCEAN:
			continue
		land += 1
		var level := cell.height_level()
		by_level[level] = int(by_level.get(level, 0)) + 1
		if cell.is_passable():
			passable += 1
		if not found_start and cell.region_name == _START_REGION and cell.is_settlement:
			start = cell.coord
			found_start = true

	print("--- height_level histogram (land hexes only, %d total) ---" % land)
	for level in range(ElevationLevels.SEA_LEVEL, ElevationLevels.MOUNTAIN + 1):
		var count := int(by_level.get(level, 0))
		print("  %d %-9s %6d  (%5.2f%%)" % [level, ElevationLevels.display_name(level), count, 100.0 * float(count) / maxf(float(land), 1.0)])
	print("passable land hexes: %d of %d (%.2f%% blocked)" % [passable, land, 100.0 * float(land - passable) / maxf(float(land), 1.0)])

	if not found_start:
		print("FAIL: no %s settlement hex found to flood-fill from." % _START_REGION)
		quit(1)
		return

	var before := _flood(cells, start, true)
	var after := _flood(cells, start, false)
	print("reachable on foot from %s %s: %d hexes before the elevation rule, %d after" % [_START_REGION, start, before.size(), after.size()])

	# Ground that used to be walkable, is not a mountain itself, and can no
	# longer be reached at all — i.e. cut off BEHIND the new mountains rather
	# than claimed by them. This is the failure the rule could plausibly cause
	# and the only number here that should ever be nonzero-and-alarming.
	var stranded: Array[Vector2i] = []
	for coord: Vector2i in before:
		if after.has(coord):
			continue
		var cell: HexCell = cells[coord]
		if cell.is_passable():
			stranded.append(coord)
	print("newly stranded (walkable, not mountain, now unreachable): %d hexes" % stranded.size())
	if not stranded.is_empty():
		print("  sample: %s" % [stranded.slice(0, mini(8, stranded.size()))])
		quit(1)
		return
	quit(0)


## Hexes reachable on foot from `start`. `ignore_elevation` selects which
## passability rule to walk under, which is what makes the two runs comparable.
func _flood(cells: Dictionary, start: Vector2i, ignore_elevation: bool) -> Dictionary:
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for neighbor in HexCoord.neighbors(current):
			if seen.has(neighbor):
				continue
			var cell: HexCell = cells.get(neighbor)
			if not cell:
				continue
			var walkable := _passable_ignoring_elevation(cell) if ignore_elevation else cell.is_passable()
			if not walkable:
				continue
			seen[neighbor] = true
			frontier.append(neighbor)
	return seen
