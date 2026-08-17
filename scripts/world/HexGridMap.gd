class_name HexGridMap
extends Node2D

## Runtime owner of the hex grid: holds generated HexCell data plus their
## HexCellView visuals, and exposes the query API the rest of the game
## (camera picking, building placement, later combat/logistics systems)
## reads from. Generation algorithm itself lives in HexMapGenerator.

signal generation_completed(cell_count: int)

var _cells: Dictionary = {}  # Vector2i -> HexCell
var _views: Dictionary = {}  # Vector2i -> HexCellView
var _cell_container: Node2D

func _ready() -> void:
	_cell_container = Node2D.new()
	_cell_container.name = "Cells"
	add_child(_cell_container)
	generate_map()

func generate_map() -> void:
	_clear_views()
	var generator := HexMapGenerator.new()
	_cells = generator.generate()
	for coord in _cells:
		# The map spans the whole UK+Ireland bounding box, most of which is
		# open OCEAN — a real HexCellView per ocean hex (a Polygon2D/textured
		# ground node) would be pure waste, there's nothing to render there
		# beyond "not land" (CoastlineOutlineView draws that boundary
		# separately, once, not per-hex). Cuts total spawned view count
		# roughly to the actual landmass, not the full bounding rectangle.
		# HexCell DATA still exists for every hex in bounds either way
		# (get_cell()/has_cell() work the same) — only the VISUAL is skipped.
		if _cells[coord].biome_type != GameEnums.BiomeType.OCEAN:
			_spawn_view(_cells[coord])
	generation_completed.emit(_cells.size())

func get_cell(coord: Vector2i) -> HexCell:
	return _cells.get(coord)

func has_cell(coord: Vector2i) -> bool:
	return _cells.has(coord)

func get_neighbors(coord: Vector2i) -> Array[HexCell]:
	var result: Array[HexCell] = []
	for neighbor_coord in HexCoord.neighbors(coord):
		if _cells.has(neighbor_coord):
			result.append(_cells[neighbor_coord])
	return result

func world_to_cell(world_pos: Vector2) -> HexCell:
	return get_cell(world_to_coord(world_pos))

## Just the coordinate half of world_to_cell — useful to callers (LocalDetailManager,
## future click-to-place UI) that need the hex under a world position whether or
## not a HexCell has been generated there yet.
func world_to_coord(world_pos: Vector2) -> Vector2i:
	return HexCoord.world_to_axial(to_local(world_pos))

func get_all_cells() -> Array[HexCell]:
	var result: Array[HexCell] = []
	result.assign(_cells.values())
	return result

## The rendered HexCellView for `coord`, or null if nothing generated there.
## Lets a sibling system (FogOfWarManager) push a per-hex visual update
## directly rather than HexGridMap needing to know about fog itself.
func get_view(coord: Vector2i) -> HexCellView:
	return _views.get(coord)

func _spawn_view(cell: HexCell) -> void:
	var view := HexCellView.new()
	view.setup(cell)
	# z_index -2: this Strategic-zoom tile is NEVER hidden while Tactical is
	# active (no tactical_mode_changed toggle anywhere hides HexGridMap/
	# "Cells" — confirmed by grep, not assumed) — it sits permanently
	# underneath whatever LocalDetailManager hydrates on top of it.
	# TacticalHexView's own per-hex ground (SubHexGroundView, the real
	# sub-hex terrain mosaic) sits at z_index -1 for the same "must never
	# outrank a building" reason (see that class's own comment) — without
	# this hex's tile ALSO sinking below -1, the two were tied at the
	# default 0 and only tree-order (HexGridMap added before
	# LocalDetailManager) kept this flat tile hidden; z_index is a global
	# sort key (LocalDetailManager's own doc comment), so giving
	# SubHexGroundView a negative z_index without giving this an even MORE
	# negative one let this flat single-biome tile win outright and bury
	# the real sub-hex mosaic — exactly the "sub-hex biomes disappeared,
	# every hex reads as one biome" regression a user report caught.
	view.z_index = -2
	_cell_container.add_child(view)
	_views[cell.coord] = view

func _clear_views() -> void:
	if _cell_container:
		for child in _cell_container.get_children():
			child.queue_free()
	_views.clear()
