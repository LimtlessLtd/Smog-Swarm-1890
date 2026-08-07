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
##
## Phase 2.5.5 (LOD): `fidelity` only affects PROPS — at LOW it collapses
## every per-species polygon (tree/bush/rock/reed) down to one uniform
## blob shape, still colored by prop type, matching the design doc's own
## "simple silhouettes/blobs" language for the lowest Tactical band.
## MEDIUM and HIGH both draw today's real per-type polygons unchanged —
## the design doc's own tier descriptions only call out a MEDIUM-vs-HIGH
## distinction for UNITS ("tell a unit's role/tier apart" vs "individual-
## figure detail", see TacticalEntityLayer), not for props/buildings, so
## there's no fabricated difference to invent here without real art
## (Phase 6.3) to actually make HIGH "more elaborate" than MEDIUM.
## **Decided: buildings are NOT simplified at any fidelity** — their
## BuildingVisuals.category_color() box is already the single simplest
## shape that still carries the "which building category is this"
## signal LOW fidelity's own "tell unit from building from zombie apart"
## bar depends on; simplifying it further would remove exactly the cue
## that bar needs, not reduce needless detail.

var cell: HexCell
var _props: Array[PropInstance] = []
var _buildings: Array[BuildingInstance] = []
var _fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH

func _ready() -> void:
	position = HexCoord.axial_to_world(cell.coord)
	if cell:
		_redraw()

## Call before this node enters the tree; mirrors HexCellView.setup()'s
## defer-to-_ready() pattern since child nodes don't exist until _ready() runs.
## `fog_state` defaults to VISIBLE: LocalDetailManager only ever hydrates a
## hex that's at least EXPLORED (Phase 2.6), so the only two values that
## actually arrive here are EXPLORED (dimmed) and VISIBLE (full color).
func setup(p_cell: HexCell, props: Array[PropInstance], buildings: Array[BuildingInstance], fog_state: GameEnums.FogState = GameEnums.FogState.VISIBLE, fidelity: GameEnums.TacticalFidelity = GameEnums.TacticalFidelity.HIGH) -> void:
	cell = p_cell
	_props = props
	_buildings = buildings
	_fidelity = fidelity
	set_fog_state(fog_state)
	if is_inside_tree():
		_redraw()

## Fog of War (Phase 2.6): dims the whole hydrated hex (terrain, props and
## buildings together) rather than the inner ground HexCellView alone, so a
## remembered-but-not-currently-visible hex reads as one dimmed scene.
func set_fog_state(state: GameEnums.FogState) -> void:
	modulate = FogVisuals.tint_color(state)

## Phase 2.5.5: pushed live by LocalDetailManager on every LOW<->MEDIUM<->HIGH
## band crossing — mirrors set_fog_state()'s "update in place, only redraw if
## it actually changed" shape rather than a full dehydrate/rehydrate.
func set_fidelity(fidelity: GameEnums.TacticalFidelity) -> void:
	if fidelity == _fidelity:
		return
	_fidelity = fidelity
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
	shape.polygon = _low_fidelity_blob() if _fidelity == GameEnums.TacticalFidelity.LOW else _prop_polygon(prop.prop_type)
	shape.color = _prop_color(prop.prop_type)
	shape.position = prop.local_position
	shape.rotation = prop.rotation
	shape.scale = Vector2.ONE * prop.scale
	return shape

## LOW fidelity (Phase 2.5.5): one uniform blob shape for every prop
## species — still colored by prop type (_prop_color() below, untouched),
## just without the per-species silhouette MEDIUM/HIGH draw.
func _low_fidelity_blob() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := TAU * i / 6.0
		points.append(Vector2(cos(angle), sin(angle)) * 5.0)
	return points

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
	box.color = BuildingVisuals.category_color(building.definition.category)
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
