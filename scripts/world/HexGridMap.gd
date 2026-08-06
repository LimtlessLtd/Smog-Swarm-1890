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
	var local_pos := to_local(world_pos)
	return get_cell(HexCoord.world_to_axial(local_pos))

func get_all_cells() -> Array[HexCell]:
	var result: Array[HexCell] = []
	result.assign(_cells.values())
	return result

func _spawn_view(cell: HexCell) -> void:
	var view := HexCellView.new()
	view.setup(cell)
	_cell_container.add_child(view)
	_views[cell.coord] = view

func _clear_views() -> void:
	if _cell_container:
		for child in _cell_container.get_children():
			child.queue_free()
	_views.clear()
