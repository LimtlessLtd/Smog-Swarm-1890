extends Node2D

## Root orchestrator — currently owns exactly one job: recentering the
## camera on the actual starting settlement the moment it's known, rather
## than trusting CameraController's own hand-placed `position` in
## Main.tscn to stay in sync with wherever the map generator actually put
## Manchester.
##
## **Found via a real user report** ("I still can't see any buildings I
## place") that turned out to have two independent causes — this is the
## first: CameraController.position was hand-set once and never touched
## again, while HexMapGenerator/DistrictPartitioner's own placement of
## Manchester can (and did) end up several hexes away from that fixed
## point. A headless diagnostic confirmed the drift directly: the
## hand-placed camera position was ~5.4 hex-radii from Town Hall's actual
## world position — enough that a player zooming in from boot never
## actually saw their own starting buildings, they saw neighboring empty
## terrain instead. Runs here (Main's own `_ready()`) rather than in
## CameraController or BuildingManager directly because Godot guarantees a
## parent's `_ready()` fires after every child's — the one point in the
## whole scene tree where "BuildingManager has definitely already seeded
## its starting buildings" is a safe assumption without an extra signal.

@export var camera_path: NodePath
@export var building_manager_path: NodePath

func _ready() -> void:
	if camera_path == NodePath() or building_manager_path == NodePath():
		return
	var camera: CameraController = get_node(camera_path)
	var building_manager: BuildingManager = get_node(building_manager_path)
	var hexes := building_manager.get_starting_settlement_hexes()
	if hexes.is_empty():
		return
	camera.position = HexCoord.axial_to_world(hexes[0])
