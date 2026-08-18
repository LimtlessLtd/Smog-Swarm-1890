extends SceneTree

## Renders the same world rect twice, side by side: left as SubHexGroundView
## draws it today (11x11 squares per hex, clipped to the hexagon), right from
## the baked .tmesh triangles. Writes PNGs; changes no game state and is never
## loaded by the game.
##
##   godot --path . -s scripts/test/preview_terrain_mesh.gd -- <out_dir>
##
## Not headless -- this needs a real RenderingServer to read the frame back.
##
## Both panels use the SAME palette, so the only difference between them is
## geometry. Soil-driven tinting is dropped for that reason: FARMLAND and
## MOORLAND take TerrainVisuals.soil_color() in game, which would introduce a
## per-panel colour difference unrelated to the boundary shapes being compared.

const PANEL_W: int = 900
const PANEL_H: int = 900
const GUTTER: int = 8

## SubHexGroundView's own render grid: this many cells across
## HexCoord.SUB_HEX_GRID_SPAN. Duplicated rather than read across the class
## boundary -- this script must keep showing what that view draws today even
## once that view is replaced, which is the whole point of the comparison.
const RASTER_GRID_N: int = 11

## Above this many hexes in view, the raster panel's per-cell polygon clipping
## costs more than the comparison is worth, so the view renders mesh-only.
const MAX_RASTER_HEXES: int = 80

const VIEWS: Array[Dictionary] = [
	{
		"name": "01_whole_corridor",
		"center": Vector2(131072.0, 94208.0),
		"span": 57344.0,
		"caption": "the whole baked corridor, 104 chunks (~560 km tall)",
	},
	{
		"name": "02_manchester_4096",
		"center": Vector2(123266.0, 90624.0),
		"span": 4096.0,
		"caption": "Manchester, one chunk (~4 km)",
	},
	{
		"name": "03_manchester_2048",
		"center": Vector2(123266.0, 90624.0),
		"span": 2048.0,
		"caption": "Manchester, ~4 hexes across",
	},
	{
		"name": "04_manchester_1024",
		"center": Vector2(123266.0, 90624.0),
		"span": 1024.0,
		"caption": "Manchester, ~2 hexes across (tactical zoom)",
	},
	{
		"name": "05_rural_2048",
		"center": Vector2(129024.0, 94208.0),
		"span": 2048.0,
		"caption": "rural east of the conurbation, ~4 hexes across",
	},
	{
		"name": "06_river_2048",
		"center": Vector2(120832.0, 91136.0),
		"span": 2048.0,
		"caption": "Mersey corridor, ~4 hexes across",
	},
]


func _init() -> void:
	var out_dir := "preview"
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		out_dir = user_args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	root.size = Vector2i(PANEL_W, PANEL_H)

	print("[preview] rendering %d views to %s" % [VIEWS.size(), out_dir])
	for view in VIEWS:
		await _render_view(view, out_dir)
	print("[preview] done")
	quit()


func _render_view(view: Dictionary, out_dir: String) -> void:
	var center: Vector2 = view["center"]
	var span: float = view["span"]
	var rect := Rect2(center - Vector2(span, span) * 0.5, Vector2(span, span))

	var hexes := _hexes_in(rect)
	var raster_ok := hexes.size() <= MAX_RASTER_HEXES

	var mesh_image := await _grab(_make_panel(
		_Panel.MODE_MESH, rect, hexes, "VECTOR MESH  (this PR)", view["caption"]))

	var composite: Image
	if raster_ok:
		var raster_image := await _grab(_make_panel(
			_Panel.MODE_RASTER, rect, hexes, "RASTER SQUARES  (today)", view["caption"]))
		composite = Image.create(PANEL_W * 2 + GUTTER, PANEL_H, false, raster_image.get_format())
		composite.fill(Color(0.0, 0.0, 0.0))
		composite.blit_rect(raster_image, Rect2i(0, 0, PANEL_W, PANEL_H), Vector2i(0, 0))
		composite.blit_rect(mesh_image, Rect2i(0, 0, PANEL_W, PANEL_H), Vector2i(PANEL_W + GUTTER, 0))
	else:
		composite = mesh_image

	var path := "%s/%s.png" % [out_dir, view["name"]]
	var error := composite.save_png(path)
	if error != OK:
		push_error("[preview] save_png failed for %s (%d)" % [path, error])
		return
	print("[preview] %s  span=%.0f wu  hexes=%d  %s" % [
		view["name"], span, hexes.size(),
		"side-by-side" if raster_ok else "mesh only (too many hexes to raster)"])


func _make_panel(mode: int, rect: Rect2, hexes: Array, title: String, caption: String) -> _Panel:
	var panel := _Panel.new()
	panel.mode = mode
	panel.world_rect = rect
	panel.hexes = hexes
	panel.title = title
	panel.caption = caption
	panel.panel_size = Vector2(PANEL_W, PANEL_H)
	panel.grid_n = RASTER_GRID_N
	panel.view_scale = float(PANEL_W) / rect.size.x
	return panel


## Draws `panel` into the root viewport and reads the frame back.
func _grab(panel: Node2D) -> Image:
	root.add_child(panel)
	panel.queue_redraw()
	# Two idle frames before the readback: the first lets _draw() run, the
	# second guarantees what it emitted reached the frame frame_post_draw fires
	# after.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	root.remove_child(panel)
	panel.queue_free()
	return image


func _hexes_in(rect: Rect2) -> Array:
	var result: Array = []
	# Pad by one hex so hexes only partly inside the rect still draw.
	var padded := rect.grow(HexCoord.HEX_SIZE)
	var corners := [
		padded.position,
		padded.position + Vector2(padded.size.x, 0.0),
		padded.position + Vector2(0.0, padded.size.y),
		padded.end,
	]
	var q_lo := 1 << 30
	var q_hi := -(1 << 30)
	var r_lo := 1 << 30
	var r_hi := -(1 << 30)
	for corner in corners:
		var axial := HexCoord.world_to_axial(corner)
		q_lo = mini(q_lo, axial.x)
		q_hi = maxi(q_hi, axial.x)
		r_lo = mini(r_lo, axial.y)
		r_hi = maxi(r_hi, axial.y)
	for q in range(q_lo - 1, q_hi + 2):
		for r in range(r_lo - 1, r_hi + 2):
			var coord := Vector2i(q, r)
			if padded.has_point(HexCoord.axial_to_world(coord)):
				result.append(coord)
	return result


class _Panel:
	extends Node2D

	const MODE_RASTER: int = 0
	const MODE_MESH: int = 1

	var mode: int
	var world_rect: Rect2
	var hexes: Array
	var title: String
	var caption: String
	var panel_size: Vector2
	var grid_n: int
	var view_scale: float

	## Palette shared by both panels. FARMLAND and MOORLAND are the two classes
	## TerrainVisuals.biome_color() defers to soil for; they take a fixed
	## soil_color() here so they stay distinguishable from each other.
	static func palette_for(biome: GameEnums.BiomeType) -> Color:
		match biome:
			GameEnums.BiomeType.FARMLAND:
				return TerrainVisuals.soil_color(GameEnums.SoilFertility.LUSH)
			GameEnums.BiomeType.MOORLAND:
				return TerrainVisuals.soil_color(GameEnums.SoilFertility.POOR)
			_:
				return TerrainVisuals.biome_color(biome, GameEnums.SoilFertility.POOR)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.04, 0.04, 0.06))
		# Points are handed over relative to world_rect.position, not in absolute
		# world space. Absolute coordinates here are ~1.2e5 while a clipped cell
		# is ~1 wu across, and float32 loses that difference: Godot's ear-clipper
		# read the sliver areas as zero and rejected 141 polygons per run with
		# "Invalid polygon data, triangulation failed".
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(view_scale, view_scale))
		if mode == MODE_RASTER:
			_draw_raster()
		else:
			_draw_mesh()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_caption()

	func _draw_caption() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(0.0, 0.0, panel_size.x, 56.0), Color(0.0, 0.0, 0.0, 0.62))
		draw_string(font, Vector2(14.0, 26.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 1.0, 1.0))
		draw_string(font, Vector2(14.0, 46.0), caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.78, 0.82))

	## Reproduces SubHexGroundView: a grid_n x grid_n grid of squares per hex,
	## each intersected with the hexagon. That intersection is what produces the
	## cut-off squares along every hex border.
	func _draw_raster() -> void:
		var span := HexCoord.SUB_HEX_GRID_SPAN
		var cell := span / float(grid_n)
		var start := -span * 0.5
		for coord: Vector2i in hexes:
			var center := HexCoord.axial_to_world(coord) - world_rect.position
			var hexagon := HexCoord.corner_points(center)
			var samples := RealTerrainSampler.sample_grid(coord, grid_n)
			if samples.size() < grid_n * grid_n:
				continue

			# Flat hex fill under the grid, standing in for HexCellView. Both
			# SubHexGroundView and this panel skip a sub-cell whose sample came
			# back empty -- which happens near the hex's corners, where the
			# square sample grid pokes outside the hexagon -- so without a layer
			# beneath, those skips read as holes that the game does not have.
			var majority := RealTerrainSampler.majority_biome(coord)
			if not majority.is_empty():
				draw_colored_polygon(hexagon, palette_for(majority["biome_type"]))
			for row in range(grid_n):
				for col in range(grid_n):
					var sample: Dictionary = samples[row * grid_n + col]
					if sample.is_empty():
						continue
					var square := PackedVector2Array([
						center + Vector2(start + col * cell, start + row * cell),
						center + Vector2(start + (col + 1) * cell, start + row * cell),
						center + Vector2(start + (col + 1) * cell, start + (row + 1) * cell),
						center + Vector2(start + col * cell, start + (row + 1) * cell),
					])
					var clipped := Geometry2D.intersect_polygons(square, hexagon)
					if clipped.is_empty():
						continue
					var color := palette_for(sample["biome_type"])
					for piece: PackedVector2Array in clipped:
						draw_colored_polygon(piece, color)

	## One canvas_item_add_triangle_array per chunk. The mesh is indexed with a
	## shared vertex per corner, but biome is per triangle, so the array is
	## expanded to 3 unindexed vertices each -- a shared corner would otherwise
	## have to pick one of its triangles' colours and the classes would blend.
	func _draw_mesh() -> void:
		var lo := TerrainMeshChunkData.chunk_address(world_rect.position)
		var hi := TerrainMeshChunkData.chunk_address(world_rect.end)
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				var chunk := TerrainMeshChunkData.load_chunk(cx, cy)
				if chunk == null:
					continue
				var tri_count := chunk.triangle_count()
				var points := PackedVector2Array()
				var colors := PackedColorArray()
				var indices := PackedInt32Array()
				points.resize(tri_count * 3)
				colors.resize(tri_count * 3)
				indices.resize(tri_count * 3)
				for tri in range(tri_count):
					var biome := RealTerrainSampler.biome_from_code(chunk.triangle_biomes[tri])
					var color := palette_for(biome)
					for corner in 3:
						var out_i := tri * 3 + corner
						points[out_i] = chunk.vertices[chunk.indices[out_i]] - world_rect.position
						colors[out_i] = color
						indices[out_i] = out_i
				RenderingServer.canvas_item_add_triangle_array(
					get_canvas_item(), indices, points, colors)
