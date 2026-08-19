extends Node2D

## Root orchestrator — currently owns exactly one job: recentering the
## camera on the actual starting settlement the moment it's known, rather
## than trusting CameraController's own hand-placed `position` in
## Main.tscn to stay in sync with wherever the map generator actually put
## Manchester.
##
## Found via user report ("I still can't see any buildings I place"), which
## turned out to have two independent causes — this is the first:
## CameraController.position was hand-set once and never touched again,
## while HexMapGenerator/DistrictPartitioner's own placement of Manchester
## can (and did) end up several hexes away from that fixed point. A
## headless diagnostic confirmed the drift directly: the hand-placed
## camera position was ~5.4 hex-radii from Town Hall's actual world
## position — enough that a player zooming in from boot never actually saw
## their own starting buildings, they saw neighboring empty terrain
## instead. Runs here (Main's own `_ready()`) rather than in
## CameraController or BuildingManager directly because Godot guarantees a
## parent's `_ready()` fires after every child's — the one point in the
## whole scene tree where "BuildingManager has definitely already seeded
## its starting buildings" is a safe assumption without an extra signal.

## "There should be a 'Main Menu' that has all the save/load functionality
## on it" (user request) — MainMenu.tscn is the project's boot scene; its
## own New Game / Continue screens can't touch managers that don't exist
## yet there, so they record the chosen campaign (and, for Continue, a
## slot) on the GameLaunchState autoload and change scene to THIS one.
## Consuming it here (rather than in SaveLoadManager itself) keeps
## GameLaunchState a dumb data-holder — same "owns neither, only
## reads/writes what's passed in" split every other cross-system reference
## in this project keeps — and reuses this exact `_ready()`'s own "runs
## after every sibling manager's `_ready()`" guarantee the camera-recenter
## logic below already depends on: SaveLoadManager.load_game() needs every
## manager it restores into to already exist.
@export var camera_path: NodePath
@export var building_manager_path: NodePath
@export var save_load_manager_path: NodePath  ## Optional — unset just means a GameLaunchState launch request is silently skipped rather than crashing (same "gracefully skip it" convention every optional NodePath in this project follows).

func _ready() -> void:
	if save_load_manager_path != NodePath() and GameLaunchState.has_pending_launch():
		var save_load_manager: SaveLoadManager = get_node(save_load_manager_path)
		var launch := GameLaunchState.consume_pending_launch()
		# Set FIRST, and for both launch paths: it decides which campaign
		# folder this session's saves land in, and load_game() below reads
		# out of the campaign it names. A New Game carries a campaign and no
		# slot, so it sets this and stops there.
		save_load_manager.set_active_campaign(launch["campaign"])
		if not (launch["slot"] as String).is_empty():
			save_load_manager.load_game(launch["slot"])
		# Deliberately falls through to the same camera recenter below —
		# SaveGameData doesn't capture camera position at all (nothing to
		# restore), so a freshly-loaded game needs exactly the same
		# "recenter on the starting settlement" fallback a brand-new game
		# already does, for the same reason.

	if camera_path == NodePath() or building_manager_path == NodePath():
		return
	var camera: CameraController = get_node(camera_path)
	var building_manager: BuildingManager = get_node(building_manager_path)
	var hexes := building_manager.get_starting_settlement_hexes()
	if hexes.is_empty():
		return
	camera.position = HexCoord.axial_to_world(hexes[0])
