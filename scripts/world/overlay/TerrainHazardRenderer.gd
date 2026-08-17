class_name TerrainHazardRenderer
extends RefCounted

## Elevation/impassability overlay. Built once: neither elevation nor
## passability change mid-game (no reclamation system touches ocean/marsh's
## underlying terrain type; only WETLAND's passability via
## ReclamationManager, a whole-biome swap on HexMapGenerator's side, not a
## live per-cell flip) — so there's no signal to rebuild off.

const _IMPASSABLE_FILL_COLOR := Color(0.65, 0.12, 0.08, 0.28)
const _IMPASSABLE_OUTLINE_COLOR := Color(0.85, 0.25, 0.15, 0.85)
const _ELEVATION_OUTLINE_COLOR := Color(0.62, 0.48, 0.30)  ## Tinted toward white at the highest elevations.
const _ELEVATION_VISIBLE_THRESHOLD := 0.35  ## Below this, elevation is gentle enough not to be worth outlining.

func build(layer: Node2D, hex_grid_map: HexGridMap) -> void:
	for cell in hex_grid_map.get_all_cells():
		var marker := _build_marker(cell)
		if marker:
			layer.add_child(marker)

func _build_marker(cell: HexCell) -> Node2D:
	# OCEAN excluded from HexCell.is_passable()'s false result here — "how
	# come the overworld map sea is red and what are those strange lines
	# where certain hexes meet?" (user report, screenshot showed the whole
	# sea solid red with a diagonal grid pattern). Root cause: this marker
	# was being built for EVERY impassable hex including OCEAN, which is the
	# large majority of cells on a UK+Ireland bounding-box map — one
	# Polygon2D fill + Line2D outline per ocean hex, all permanently in the
	# tree with no fog/zoom gating, translucent-blending into a solid red
	# wash with the outlines aliasing into the reported "lines" at
	# zoomed-out scale. Also a real performance cost (StrategicOverlayManager's
	# own report of lag fully zoomed out): thousands of extra always-drawn
	# CanvasItems, all on-screen simultaneously at that zoom. OCEAN being
	# "impassable" is redundant information anyway — it's already obvious
	# from the tile's own ocean color/texture, unlike MARSH/PEAT_BOG (a real
	# hazard on what otherwise reads as ordinary land) which still needs the
	# marker.
	var is_impassable := not cell.is_passable() and cell.biome_type != GameEnums.BiomeType.OCEAN
	var show_elevation := cell.elevation >= _ELEVATION_VISIBLE_THRESHOLD
	if not is_impassable and not show_elevation:
		return null

	var container := Node2D.new()
	container.position = HexCoord.axial_to_world(cell.coord)
	var points := HexCoord.corner_points(Vector2.ZERO)

	if is_impassable:
		var fill := Polygon2D.new()
		fill.name = "ImpassableFill"
		fill.color = _IMPASSABLE_FILL_COLOR
		fill.polygon = points
		container.add_child(fill)

		var outline := Line2D.new()
		outline.name = "ImpassableOutline"
		outline.closed = true
		outline.default_color = _IMPASSABLE_OUTLINE_COLOR
		outline.width = 3.0
		outline.points = points
		container.add_child(outline)

	if show_elevation:
		# Brighter/more opaque toward the highest peaks (elevation 1.0), just
		# perceptible at the threshold — a gradient, not a flat on/off line.
		var elevation_fraction := (cell.elevation - _ELEVATION_VISIBLE_THRESHOLD) / (1.0 - _ELEVATION_VISIBLE_THRESHOLD)
		var outline := Line2D.new()
		outline.name = "ElevationOutline"
		outline.closed = true
		outline.default_color = _ELEVATION_OUTLINE_COLOR.lerp(Color.WHITE, elevation_fraction * 0.5)
		outline.default_color.a = 0.35 + elevation_fraction * 0.55
		outline.width = 2.0 + elevation_fraction * 2.5
		outline.points = points
		container.add_child(outline)

	return container
