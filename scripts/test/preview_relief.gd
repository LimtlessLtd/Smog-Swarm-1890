extends Node

## Builds the ElevationReliefView overlay once and writes it to a PNG, so the
## hillshade can be looked at without launching the game and hunting for a
## slope.
##
## Run:
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/preview_relief.tscn
##
## Same role scripts/test/preview_terrain_mesh.gd plays for the mesh: the
## shading constants in ReliefImageBuilder (_VERTICAL_EXAGGERATION,
## _SLOPE_METRES_AT_FULL_SHADE, the two alpha caps) are presentation numbers
## whose only real test is looking at the result, and iterating on them through
## a full game launch is slow enough to discourage iterating at all.
##
## Also reports BUILD TIME, which is the number that decides whether this can
## stay a synchronous build in _ready() or has to be spread across frames —
## it walks every pixel of the raster in GDScript.
##
## Composited over mid-grey rather than written with its own alpha: every
## colour here is a low-alpha overlay meant to sit on terrain art, and an RGBA
## PNG of it viewed on a white page reads far lighter than it does in game.

const _OUT_PATH := "user://relief_preview.png"
const _BACKDROP := Color(0.42, 0.40, 0.36)

var _map: HexGridMap


func _ready() -> void:
	if not RealTerrainSampler.is_available():
		print("SKIP: baked rasters not present, nothing to build.")
		get_tree().quit(0)
		return

	# The builder reads HexGridMap only for each hex's MOUNTAIN verdict, so the
	# preview needs real elevation per hex but none of HexMapGenerator's other
	# passes — same shortcut scripts/test/verify_boundary_connectivity.gd takes,
	# and for the same reason (full generation is minutes per run).
	_map = load("res://scenes/world/HexGridMap.tscn").instantiate()
	_map.auto_generate_on_ready = false
	add_child(_map)
	_map.load_cells(_build_corridor())

	var started := Time.get_ticks_msec()
	var image := ReliefImageBuilder.build(_map)
	var build_ms := Time.get_ticks_msec() - started
	if image == null:
		print("FAIL: ReliefImageBuilder returned null despite the rasters being available.")
		get_tree().quit(1)
		return

	print("relief image: %dx%d, built in %d ms" % [image.get_width(), image.get_height(), build_ms])
	print("world rect:   %s" % ReliefImageBuilder.world_rect(image))
	_report_coverage(image)

	var flattened := _composite_over_backdrop(image)
	var error := flattened.save_png(_OUT_PATH)
	if error != OK:
		print("FAIL: could not write %s (error %d)" % [_OUT_PATH, error])
		get_tree().quit(1)
		return
	print("wrote %s" % ProjectSettings.globalize_path(_OUT_PATH))
	get_tree().quit(0)


## Coarse single-point sample_at() per hex, NOT majority_biome().
##
## The builder asks HexGridMap for exactly one thing — each hex's MOUNTAIN
## verdict — and that is derived from elevation, which always comes from the
## coarse raster anyway (the fine per-hex tiles bake biome and terrain_feature
## only, never elevation). majority_biome() would route through sample_grid()
## -> the fine tiles and decode all ~7,700 of them to produce a value this
## preview then throws away; measured, that was the entire runtime and ~1 GB of
## the memory. The connectivity verifier still uses majority_biome() because
## biome_type genuinely changes its answer there.
func _build_corridor() -> Dictionary:
	var q_range := RealTerrainSampler.get_corridor_q()
	var r_range := RealTerrainSampler.get_corridor_r()
	var cells: Dictionary = {}
	for q in range(q_range.x, q_range.y + 1):
		for r in range(r_range.x, r_range.y + 1):
			var coord := Vector2i(q, r)
			var sample := RealTerrainSampler.sample_at(HexCoord.axial_to_world(coord))
			if sample.is_empty():
				continue
			var cell := HexCell.new(coord)
			cell.biome_type = sample["biome_type"]
			cell.elevation = sample["elevation"]
			cells[coord] = cell
	MountainPassCarver.carve(cells)
	return cells


## How much of the image is actually doing something. An overlay that is
## ~entirely transparent is the failure mode worth catching automatically:
## it looks like a clean run and shows nothing on screen, which is exactly the
## complaint this whole layer exists to answer.
func _report_coverage(image: Image) -> void:
	var shaded := 0
	var strong := 0
	var total := image.get_width() * image.get_height()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := image.get_pixel(x, y).a
			if a > 0.02:
				shaded += 1
			if a > 0.15:
				strong += 1
	print("pixels with any shading:    %d (%.1f%%)" % [shaded, 100.0 * float(shaded) / float(total)])
	print("pixels clearly shaded:      %d (%.1f%%)" % [strong, 100.0 * float(strong) / float(total)])


func _composite_over_backdrop(image: Image) -> Image:
	var out := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			out.set_pixel(x, y, _BACKDROP.lerp(Color(c.r, c.g, c.b), c.a))
	return out
