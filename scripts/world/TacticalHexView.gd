class_name TacticalHexView
extends Node2D

## Close-zoom detail for one hex (Phase 2.5 "Tactical view"). Composes the
## same flat-color ground HexCellView already draws — biome/soil stays a
## single source of visual truth — with a scatter of placeholder props and
## every BuildingInstance in this hex rendered at its own precise position,
## instead of one flat tile standing in for the whole ~5x5 mile area.
## Spawned/freed by LocalDetailManager as the camera crosses the tactical
## zoom threshold and pans between hexes; only ever exists for a hex that
## has qualified as settled/frontier (see LocalDetailManager).

var cell: HexCell
var _props: Array[PropInstance] = []
var _buildings: Array[BuildingInstance] = []

func _ready() -> void:
	position = HexCoord.axial_to_world(cell.coord)
	if cell:
		_redraw()

## Call before this node enters the tree; mirrors HexCellView.setup()'s
## defer-to-_ready() pattern since child nodes don't exist until _ready() runs.
func setup(p_cell: HexCell, props: Array[PropInstance], buildings: Array[BuildingInstance]) -> void:
	cell = p_cell
	_props = props
	_buildings = buildings
	if is_inside_tree():
		_redraw()

func _redraw() -> void:
	for child in get_children():
		child.queue_free()

	var ground := HexCellView.new()
	ground.setup(cell)
	add_child(ground)

	for prop in _props:
		add_child(_build_prop_node(prop))

	for i in range(_buildings.size()):
		add_child(_build_building_node(_buildings[i], i))

func _build_prop_node(prop: PropInstance) -> Node2D:
	var shape := Polygon2D.new()
	shape.polygon = _prop_polygon(prop.prop_type)
	shape.color = _prop_color(prop.prop_type)
	shape.position = prop.local_position
	shape.rotation = prop.rotation
	shape.scale = Vector2.ONE * prop.scale
	return shape

func _prop_polygon(prop_type: GameEnums.PropType) -> PackedVector2Array:
	match prop_type:
		GameEnums.PropType.TREE:
			return PackedVector2Array([Vector2(0, -10), Vector2(6, 6), Vector2(-6, 6)])
		GameEnums.PropType.ROCK:
			return PackedVector2Array([Vector2(-5, 4), Vector2(0, -5), Vector2(5, 4), Vector2(2, 6), Vector2(-2, 6)])
		GameEnums.PropType.REED:
			return PackedVector2Array([Vector2(-1, 8), Vector2(1, 8), Vector2(0, -10)])
		_:  # BUSH
			return PackedVector2Array([Vector2(-5, 3), Vector2(-3, -4), Vector2(3, -4), Vector2(5, 3), Vector2(0, 5)])

func _prop_color(prop_type: GameEnums.PropType) -> Color:
	match prop_type:
		GameEnums.PropType.TREE:
			return Color(0.20, 0.35, 0.16)
		GameEnums.PropType.BUSH:
			return Color(0.28, 0.42, 0.22)
		GameEnums.PropType.ROCK:
			return Color(0.45, 0.44, 0.42)
		GameEnums.PropType.REED:
			return Color(0.42, 0.46, 0.20)
		_:
			return Color(0.3, 0.3, 0.3)

func _build_building_node(building: BuildingInstance, index: int) -> Node2D:
	var box := Polygon2D.new()
	box.color = _building_color(building.definition.category)
	var half := 10.0
	box.polygon = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	box.position = _resolved_building_position(building, index)
	return box

## Buildings placed through the plain hex-coordinate API (BuildingManager.place_building()
## with no explicit local_position) all default to the hex center, which
## would otherwise stack them directly on top of each other here. Spread
## those out into a small deterministic ring purely for legibility — a real
## placement UI (Phase 6+) will set distinct local_positions of its own and
## this fallback won't trigger.
func _resolved_building_position(building: BuildingInstance, index: int) -> Vector2:
	if building.local_position != Vector2.ZERO or index == 0:
		return building.local_position
	var ring_radius := 22.0
	var angle := TAU * float(index) / float(_buildings.size())
	return Vector2(cos(angle), sin(angle)) * ring_radius

func _building_color(category: GameEnums.BuildingCategory) -> Color:
	match category:
		GameEnums.BuildingCategory.HOUSING_CIVIL:
			return Color(0.55, 0.42, 0.30)
		GameEnums.BuildingCategory.INDUSTRY_EXTRACTION:
			return Color(0.35, 0.32, 0.34)
		GameEnums.BuildingCategory.AGRICULTURE:
			return Color(0.62, 0.55, 0.25)
		_:
			return Color(0.5, 0.5, 0.5)
