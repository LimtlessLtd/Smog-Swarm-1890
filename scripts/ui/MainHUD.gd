class_name MainHUD
extends CanvasLayer

## Root HUD coordinator — the essential slice of design doc Phase 6.1:
## resource display, the build/placement menu, unit training/orders panel,
## time controls, and the Strategic-layer minimap (shown only during
## Tactical zoom — see MinimapView's own doc comment for why). The
## per-sector Threat Meter bullet stays unbuilt (see todo.md — it needs
## Phase 5's horde-attraction system to have a level to show, which doesn't
## exist yet).
##
## Owns no game logic itself: only wires the dumb display components
## (ResourceBarView / TimeControlsView / BuildMenuView / UnitPanelView) to
## the systems they read from, and forwards BuildMenuView's selection into
## BuildPlacementController and UnitPanelView's button presses into
## UnitCommandController (which owns the actual map-click selection/order
## input — see its own doc comment). Every child Control is built in code rather
## than scene-authored, matching HexCellView/StrategicOverlayManager's
## "code-drawn placeholder" convention — there's no art pass to wait for
## before wiring this up, and no editor session in this workflow to lay out
## a Control tree by hand anyway.
##
## Quick Save/Load buttons use a single fixed campaign/slot rather than a
## real campaign browser — Phase 2.8.3's actual Save/Load UI (name a
## campaign, browse slots) is still deferred to fuller Phase 6 HUD work;
## this is just enough to prove the save system is reachable by a player at
## all, not the intended final UI for it.

@export var resource_manager_path: NodePath
@export var building_manager_path: NodePath
@export var save_load_manager_path: NodePath
@export var build_placement_controller_path: NodePath
@export var unit_command_controller_path: NodePath
@export var unit_manager_path: NodePath
@export var hex_grid_map_path: NodePath
@export var fog_of_war_manager_path: NodePath
@export var camera_path: NodePath

const DEFAULT_CAMPAIGN := "Default"
const DEFAULT_SLOT := "QuickSave"
const TOAST_SECONDS := 3.0

const MARGIN := 8.0
const ROW_HEIGHT := 32.0
const TIME_CONTROLS_WIDTH := 460.0  ## Widened for Phase 5.1's date + phase countdown text alongside the day counter/speed buttons.
const SAVE_LOAD_WIDTH := 220.0
const BUILD_MENU_SIZE := Vector2(260.0, 260.0)
const MINIMAP_SIZE := Vector2(220.0, 160.0)
const UNIT_PANEL_SIZE := Vector2(260.0, 260.0)

var _building_manager: BuildingManager
var _save_load_manager: SaveLoadManager
var _build_placement_controller: BuildPlacementController
var _unit_command_controller: UnitCommandController

var _mode_label: Label
var _toast_label: Label
var _toast_timer: Timer

func _ready() -> void:
	var resource_manager: ResourceManager = null
	if resource_manager_path != NodePath():
		resource_manager = get_node(resource_manager_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.placement_rejected.connect(_on_placement_rejected)
	if save_load_manager_path != NodePath():
		_save_load_manager = get_node(save_load_manager_path)
		_save_load_manager.game_saved.connect(_on_game_saved)
		_save_load_manager.game_loaded.connect(_on_game_loaded)
		_save_load_manager.load_failed.connect(_on_load_failed)
	if build_placement_controller_path != NodePath():
		_build_placement_controller = get_node(build_placement_controller_path)
		_build_placement_controller.placement_started.connect(_on_placement_started)
		_build_placement_controller.placement_ended.connect(_on_placement_ended)
	if unit_command_controller_path != NodePath():
		_unit_command_controller = get_node(unit_command_controller_path)
	var unit_manager: UnitManager = null
	if unit_manager_path != NodePath():
		unit_manager = get_node(unit_manager_path)

	var hex_grid_map: HexGridMap = null
	if hex_grid_map_path != NodePath():
		hex_grid_map = get_node(hex_grid_map_path)
	var fog_of_war_manager: FogOfWarManager = null
	if fog_of_war_manager_path != NodePath():
		fog_of_war_manager = get_node(fog_of_war_manager_path)
	var camera: CameraController = null
	if camera_path != NodePath():
		camera = get_node(camera_path)

	_build_resource_bar(resource_manager)
	_build_time_controls()
	_build_save_load_bar()
	_build_minimap(hex_grid_map, fog_of_war_manager, camera)
	_build_mode_label()
	_build_build_menu()
	_build_unit_panel(unit_manager)
	_build_toast()

func _build_resource_bar(resource_manager: ResourceManager) -> void:
	var resource_bar := ResourceBarView.new()
	add_child(resource_bar)
	_place_top_wide(resource_bar, 0)
	if resource_manager:
		resource_bar.setup(resource_manager)

func _build_time_controls() -> void:
	var time_controls := TimeControlsView.new()
	add_child(time_controls)
	# Row 1, not 0: ResourceBarView (row 0) is a full-width top-wide strip
	# whose resource chips can run most of the screen's width (8 resource
	# types), and TimeControlsView (Phase 5.1) is wide enough now (date +
	# phase countdown + speed buttons, TIME_CONTROLS_WIDTH) that sharing row
	# 0 with it visibly overlapped the resource bar's own text — caught by
	# actually playing, not just the headless logic tests, same as the
	# original Phase 6.1 HUD layout bug. Row 1 (top-right) is clear of the
	# full-width resource bar above it.
	_place_top_right(time_controls, TIME_CONTROLS_WIDTH, 1)

func _build_save_load_bar() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	_place_top_right(bar, SAVE_LOAD_WIDTH, 2)  # Row 2: stacks below TimeControlsView in the same corner.

	var save_button := Button.new()
	save_button.text = "Quick Save"
	save_button.pressed.connect(_on_quick_save_pressed)
	bar.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Quick Load"
	load_button.pressed.connect(_on_quick_load_pressed)
	bar.add_child(load_button)

## Design doc Phase 6.1's minimap — bottom-right corner is the only one of
## the four still unclaimed by another HUD element (top strip: resource
## bar/mode label; top-right: time controls/save-load; bottom-left: build
## menu; bottom strip: toast). Gracefully no-ops (an empty, permanently
## hidden Control) if any of the three optional NodePaths weren't wired —
## same "unset gracefully skips it" convention every other optional
## MainHUD dependency already follows.
func _build_minimap(hex_grid_map: HexGridMap, fog_of_war_manager: FogOfWarManager, camera: CameraController) -> void:
	var minimap := MinimapView.new()
	add_child(minimap)
	_place_bottom_right(minimap, MINIMAP_SIZE)
	minimap.setup(hex_grid_map, _building_manager, fog_of_war_manager, camera, MINIMAP_SIZE)

func _build_mode_label() -> void:
	_mode_label = Label.new()
	add_child(_mode_label)
	_place_top_wide(_mode_label, 1)  # Row 1: below the resource bar, same top-wide strip.
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_build_menu() -> void:
	var build_menu := BuildMenuView.new()
	add_child(build_menu)
	_place_bottom_left(build_menu, BUILD_MENU_SIZE)
	build_menu.building_selected.connect(_on_building_selected)

## UnitPanelView (Phase 6.1's unit training/orders counterpart to the Build
## Menu) — top-left corner, the one spot nothing else in this HUD claims
## (top-wide strip: resource bar/mode label; top-right: time controls/
## save-load; bottom-left: build menu; bottom-right: minimap; bottom-wide:
## toast). Gracefully empty if unit_command_controller_path wasn't wired,
## same "unset gracefully skips it" convention every other optional MainHUD
## dependency already follows.
func _build_unit_panel(unit_manager: UnitManager) -> void:
	var unit_panel := UnitPanelView.new()
	add_child(unit_panel)
	_place_top_left(unit_panel, UNIT_PANEL_SIZE)
	if _unit_command_controller:
		unit_panel.setup(_unit_command_controller, unit_manager)

func _build_toast() -> void:
	_toast_label = Label.new()
	add_child(_toast_label)
	_place_bottom_wide(_toast_label)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = TOAST_SECONDS
	add_child(_toast_timer)
	_toast_timer.timeout.connect(_on_toast_timeout)

## --- Layout helpers ---------------------------------------------------
##
## Deliberately NOT using Control.set_anchors_and_offsets_preset(...,
## PRESET_MODE_MINSIZE, ...): that mode sizes offsets off
## get_combined_minimum_size() at the moment of the call, which for these
## code-built Controls (an HBoxContainer/ScrollContainer whose children were
## *just* added this same frame) can still read as the Control's initial
## (0, 0) rect — every bottom/right-anchored element ended up positioned
## just past the edge of the screen instead of inside it (caught by actually
## running the game and looking at it, not just the headless logic tests —
## see the Phase 6.1 commit). These compute every offset from an explicit
## size instead, so they can't go stale.

## Full-width strip pinned to the top, `row` rows down (0 = topmost) at a
## fixed ROW_HEIGHT each.
func _place_top_wide(control: Control, row: int) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = MARGIN
	control.offset_right = -MARGIN
	control.offset_top = MARGIN + row * (ROW_HEIGHT + MARGIN)
	control.offset_bottom = control.offset_top + ROW_HEIGHT

## Full-width strip pinned to the bottom edge.
func _place_bottom_wide(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = MARGIN
	control.offset_right = -MARGIN
	control.offset_bottom = -MARGIN
	control.offset_top = -MARGIN - ROW_HEIGHT

## Fixed-`width` strip pinned to the top-right corner, `row` rows down.
func _place_top_right(control: Control, width: float, row: int) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_right = -MARGIN
	control.offset_left = -MARGIN - width
	control.offset_top = MARGIN + row * (ROW_HEIGHT + MARGIN)
	control.offset_bottom = control.offset_top + ROW_HEIGHT

## Fixed-`size` rect pinned to the top-left corner, below the top-wide
## resource bar/mode label strip (2 rows tall) — UnitPanelView's own spot,
## the one corner nothing else in this HUD claims.
func _place_top_left(control: Control, size: Vector2) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = MARGIN
	control.offset_right = MARGIN + size.x
	control.offset_top = MARGIN + 2 * (ROW_HEIGHT + MARGIN)
	control.offset_bottom = control.offset_top + size.y

## Fixed-`size` rect pinned to the bottom-left corner.
func _place_bottom_left(control: Control, size: Vector2) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = MARGIN
	control.offset_right = MARGIN + size.x
	control.offset_bottom = -MARGIN
	control.offset_top = -MARGIN - size.y

## Fixed-`size` rect pinned to the bottom-right corner — the minimap's own
## spot, the one corner nothing else in this HUD claims.
func _place_bottom_right(control: Control, size: Vector2) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_right = -MARGIN
	control.offset_left = -MARGIN - size.x
	control.offset_bottom = -MARGIN
	control.offset_top = -MARGIN - size.y

func _on_building_selected(building_type: GameEnums.BuildingType) -> void:
	if _build_placement_controller:
		_build_placement_controller.begin_placement(building_type)

func _on_placement_started(building_type: GameEnums.BuildingType) -> void:
	var definition := BuildingCatalog.get_definition(building_type)
	var display_name := definition.display_name if definition else "building"
	_mode_label.text = "Placing: %s — click the map (Shift-click for more, Right-click/Esc to cancel)" % display_name

func _on_placement_ended() -> void:
	_mode_label.text = ""

func _on_placement_rejected(_building_type: GameEnums.BuildingType, _coord: Vector2i, reason: String) -> void:
	_show_toast(reason)

func _on_quick_save_pressed() -> void:
	if _save_load_manager:
		_save_load_manager.save_game(DEFAULT_CAMPAIGN, DEFAULT_SLOT)

func _on_quick_load_pressed() -> void:
	if _save_load_manager:
		_save_load_manager.load_game(DEFAULT_CAMPAIGN, DEFAULT_SLOT)

func _on_game_saved(_campaign_name: String, _slot_name: String) -> void:
	_show_toast("Game saved.")

func _on_game_loaded(_campaign_name: String, _slot_name: String) -> void:
	_show_toast("Game loaded.")

func _on_load_failed(_campaign_name: String, _slot_name: String, reason: String) -> void:
	_show_toast("Load failed: %s" % reason)

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_timer.start()

func _on_toast_timeout() -> void:
	_toast_label.text = ""
