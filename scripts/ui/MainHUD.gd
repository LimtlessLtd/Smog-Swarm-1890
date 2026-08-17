class_name MainHUD
extends CanvasLayer

## Root HUD composition root: resource display, build/placement menu, unit
## training/orders panel, time controls, and the Strategic-layer minimap
## (Tactical zoom only — see MinimapView). Owns no game logic itself: wires
## the dumb display components (ResourceBarView / TimeControlsView /
## BuildMenuView / UnitPanelView / MinimapView / ...) to the systems they
## read from, forwards BuildMenuView's selection into BuildPlacementController
## and UnitPanelView's button presses into UnitCommandController. Every
## child Control is built in code, not scene-authored — there's no art pass
## to wait for and no editor session in this workflow to lay out a Control
## tree by hand.
##
## This class resolves every NodePath export (below) and constructs the
## child views, but four cross-cutting concerns are extracted into their own
## collaborators under scripts/ui/hud/ rather than living as a flat pile of
## handlers here: HUDToastRouter (toast display mechanics), HUDPlacementFeedback
## (building/wall placement mode text + construction/repair/rejection
## toasts — the largest cluster), HUDReconTracker (the Reconnaissance
## countdown label), HUDPanelSwitcher (mutual exclusion between the four
## centered panels). Each depends only on the manager(s) it actually needs.
## Tech/save-load/unit-training toasts stay as one-line handlers here — each
## already touches exactly one manager and doesn't warrant its own file. See
## todo.md's "Technical Debt" section for why this split happened.
##
## `SaveLoadView`, `DisplayOptionsView`, `TechTreeView`, and `InGameMenuView`
## are the four centered toggleable panels (HUDPanelSwitcher). Reconnaissance
## countdown (`_recon_label`, HUDReconTracker) is a single status row, not a
## dedicated view class — same "one line of text, blank when nothing
## relevant" shape as `_mode_label`.

@export var resource_manager_path: NodePath
@export var building_manager_path: NodePath
@export var save_load_manager_path: NodePath
@export var build_placement_controller_path: NodePath
@export var unit_command_controller_path: NodePath
@export var unit_manager_path: NodePath
@export var hex_grid_map_path: NodePath
@export var fog_of_war_manager_path: NodePath
@export var camera_path: NodePath
@export var event_manager_path: NodePath  ## Optional — without it, world events show no toast (AlertManager's own audio/auto-pause is unaffected).
@export var tech_manager_path: NodePath   ## Optional — unset means the Tech Tree panel/button do nothing.
@export var horde_manager_path: NodePath  ## Optional — unset means the Reconnaissance row stays permanently empty.
@export var noise_manager_path: NodePath  ## Optional — unset means no Threat Meter markers on the minimap; everything else about it is unaffected.
@export var wall_manager_path: NodePath   ## Optional — feeds UnitPanelView's wall-repair toast/live-refresh; unset means a selected wall's Repair button still works (UnitCommandController owns the call) but no live-refresh/toast.
@export var wall_placement_controller_path: NodePath  ## Optional — arms WallPlacementController from BuildMenuView's Walls tab; unset means that tab's buttons do nothing.
@export var supply_line_placement_controller_path: NodePath  ## Optional — arms SupplyLinePlacementController from BuildMenuView's Infrastructure tab; unset means that tab's buttons do nothing.
@export var logistics_network_path: NodePath  ## Optional — feeds a placement-rejected toast for Infrastructure; unset means placement rejections are silent (still blocked, just no on-screen reason).

const MARGIN := 8.0
const ROW_HEIGHT := 32.0
const TIME_CONTROLS_WIDTH := 420.0  ## Fallback only — _place_top_right() self-corrects to the real measured width.
const DAY_PHASE_VIEW_WIDTH := 260.0
const SAVE_LOAD_WIDTH := 220.0
const TECH_BAR_WIDTH := 150.0
## One full-width bottom strip holds BuildMenuView (SIZE_EXPAND_FILL) and
## MinimapView side by side. Height verified against a live screenshot: tall
## enough for a building card's icon + name + 2-3 line cost/upkeep/effect
## block without clipping (Garrison's card — 2-resource cost + upkeep +
## "Trains: ..." — is this tree's longest).
const BOTTOM_BAR_HEIGHT := 224.0
## Matches BOTTOM_BAR_HEIGHT exactly, paired with size_flags_vertical =
## SIZE_FILL at the minimap's own call site, so its rect exactly fills the
## bar's full height instead of floating centered with a gap.
const MINIMAP_SIZE := Vector2(200.0, 224.0)
const UNIT_PANEL_SIZE := Vector2(320.0, 320.0)
const SAVE_LOAD_VIEW_SIZE := Vector2(320.0, 320.0)
const TECH_TREE_VIEW_SIZE := Vector2(380.0, 360.0)
const DISPLAY_OPTIONS_VIEW_SIZE := Vector2(320.0, 300.0)
const IN_GAME_MENU_VIEW_SIZE := Vector2(240.0, 260.0)  ## Fallback only — get_content_min_size() resizes this to its real content.

var _building_manager: BuildingManager
var _save_load_manager: SaveLoadManager
var _build_placement_controller: BuildPlacementController
var _unit_command_controller: UnitCommandController
var _save_load_view: SaveLoadView
var _tech_manager: TechManager
var _tech_tree_view: TechTreeView
var _display_options_view: DisplayOptionsView
var _in_game_menu_view: InGameMenuView
var _panel_switcher: HUDPanelSwitcher
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager

var _mode_label: Label
var _recon_label: Label
var _toast: HUDToastRouter
var _placement_feedback: HUDPlacementFeedback
var _wall_manager: WallManager
var _wall_placement_controller: WallPlacementController
var _supply_line_placement_controller: SupplyLinePlacementController
var _logistics_network: LogisticsNetwork

func _ready() -> void:
	var resource_manager: ResourceManager = null
	if resource_manager_path != NodePath():
		resource_manager = get_node(resource_manager_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
	if wall_placement_controller_path != NodePath():
		_wall_placement_controller = get_node(wall_placement_controller_path)
	if supply_line_placement_controller_path != NodePath():
		_supply_line_placement_controller = get_node(supply_line_placement_controller_path)
	if logistics_network_path != NodePath():
		_logistics_network = get_node(logistics_network_path)
	if save_load_manager_path != NodePath():
		_save_load_manager = get_node(save_load_manager_path)
		_save_load_manager.game_saved.connect(_on_game_saved)
		_save_load_manager.game_loaded.connect(_on_game_loaded)
		_save_load_manager.load_failed.connect(_on_load_failed)
	if build_placement_controller_path != NodePath():
		_build_placement_controller = get_node(build_placement_controller_path)
	if event_manager_path != NodePath():
		var event_manager: EventManager = get_node(event_manager_path)
		event_manager.event_raised.connect(_on_event_raised)
	if unit_command_controller_path != NodePath():
		_unit_command_controller = get_node(unit_command_controller_path)
	var unit_manager: UnitManager = null
	if unit_manager_path != NodePath():
		unit_manager = get_node(unit_manager_path)
		unit_manager.training_started.connect(_on_training_started)
		unit_manager.retrain_started.connect(_on_retrain_started)

	var hex_grid_map: HexGridMap = null
	if hex_grid_map_path != NodePath():
		hex_grid_map = get_node(hex_grid_map_path)
	if fog_of_war_manager_path != NodePath():
		_fog_of_war_manager = get_node(fog_of_war_manager_path)
	var camera: CameraController = null
	if camera_path != NodePath():
		camera = get_node(camera_path)
	if tech_manager_path != NodePath():
		_tech_manager = get_node(tech_manager_path)
		_tech_manager.tech_researched.connect(_on_tech_researched)
		_tech_manager.research_rejected.connect(_on_research_rejected)
	if horde_manager_path != NodePath():
		_horde_manager = get_node(horde_manager_path)
	var noise_manager: NoiseManager = null
	if noise_manager_path != NodePath():
		noise_manager = get_node(noise_manager_path)

	_build_resource_bar(resource_manager)
	_build_time_controls()
	_build_menu_bar()
	_build_save_load_view()
	_build_tech_bar()
	_build_tech_tree_view()
	_build_display_options_view()
	_build_in_game_menu_view()
	_panel_switcher = HUDPanelSwitcher.new(_save_load_view, _tech_tree_view, _display_options_view, _in_game_menu_view)
	_build_mode_label()
	_build_recon_label()
	_build_bottom_bar(hex_grid_map, _fog_of_war_manager, camera, noise_manager, resource_manager)
	_build_day_phase_view()
	_build_unit_panel(unit_manager, _wall_manager)
	# _build_toast() must stay LAST among the node-adding calls above: the
	# toast panel needs to draw on top of the bottom bar/build menu cards it
	# visually overlaps, and CanvasLayer siblings draw in add_child() order —
	# adding it earlier would bury it under later panels (found by actually
	# running the game, not the headless tests alone).
	_build_toast()

	_placement_feedback = HUDPlacementFeedback.new(_mode_label, _toast)
	if _building_manager:
		_placement_feedback.wire_building_manager(_building_manager)
	if _wall_manager:
		_placement_feedback.wire_wall_manager(_wall_manager)
	if _build_placement_controller:
		_placement_feedback.wire_build_placement_controller(_build_placement_controller)
	if _wall_placement_controller:
		_placement_feedback.wire_wall_placement_controller(_wall_placement_controller)
	if _logistics_network:
		_placement_feedback.wire_logistics_network(_logistics_network)
	if _supply_line_placement_controller:
		_placement_feedback.wire_supply_line_placement_controller(_supply_line_placement_controller)

func _build_resource_bar(resource_manager: ResourceManager) -> void:
	var resource_bar := ResourceBarView.new()
	resource_bar.name = "ResourceBar"
	add_child(resource_bar)
	_place_top_wide(resource_bar, 0)
	if resource_manager:
		resource_bar.setup(resource_manager, _building_manager)

func _build_time_controls() -> void:
	var time_controls := TimeControlsView.new()
	time_controls.name = "TimeControls"
	add_child(time_controls)
	_place_top_right(time_controls, TIME_CONTROLS_WIDTH, 1)  # Row 1: row 0 is the full-width resource bar.

func _build_day_phase_view() -> void:
	var day_phase_view := DayPhaseView.new()
	day_phase_view.name = "DayPhaseView"
	add_child(day_phase_view)
	_place_above_bottom_bar_right(day_phase_view, DAY_PHASE_VIEW_WIDTH)

func _build_menu_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "MenuBar"
	add_child(bar)
	_place_top_right(bar, SAVE_LOAD_WIDTH, 2)  # Row 2: stacks below TimeControlsView.

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.pressed.connect(func() -> void: _panel_switcher.open_menu())
	HUDStyles.style_button(menu_button)
	bar.add_child(menu_button)

func _build_save_load_view() -> void:
	_save_load_view = SaveLoadView.new()
	_save_load_view.name = "SaveLoadView"
	add_child(_save_load_view)
	_place_center(_save_load_view, SAVE_LOAD_VIEW_SIZE)
	if _save_load_manager:
		_save_load_view.setup(_save_load_manager)
	_save_load_view.save_requested.connect(_on_save_load_view_save_requested)
	_save_load_view.load_requested.connect(_on_save_load_view_load_requested)

func _build_tech_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TechBar"
	add_child(bar)
	_place_top_right(bar, TECH_BAR_WIDTH, 3)  # Row 3: stacks below MenuBar.

	var tech_button := Button.new()
	tech_button.text = "Tech Tree..."
	tech_button.pressed.connect(func() -> void: _panel_switcher.open_tech_tree())
	HUDStyles.style_button(tech_button)
	bar.add_child(tech_button)

func _build_tech_tree_view() -> void:
	_tech_tree_view = TechTreeView.new()
	_tech_tree_view.name = "TechTreeView"
	add_child(_tech_tree_view)
	_place_center(_tech_tree_view, TECH_TREE_VIEW_SIZE)
	if _tech_manager:
		_tech_tree_view.setup(_tech_manager)
	_tech_tree_view.research_requested.connect(_on_research_requested)

func _build_display_options_view() -> void:
	_display_options_view = DisplayOptionsView.new()
	_display_options_view.name = "DisplayOptionsView"
	add_child(_display_options_view)
	_place_center(_display_options_view, DISPLAY_OPTIONS_VIEW_SIZE)

func _build_in_game_menu_view() -> void:
	_in_game_menu_view = InGameMenuView.new()
	_in_game_menu_view.name = "InGameMenuView"
	add_child(_in_game_menu_view)
	_place_center(_in_game_menu_view, IN_GAME_MENU_VIEW_SIZE)
	_in_game_menu_view.save_load_requested.connect(func() -> void: _panel_switcher.open_save_load())
	_in_game_menu_view.display_options_requested.connect(func() -> void: _panel_switcher.open_display_options())
	_in_game_menu_view.resume_requested.connect(_on_in_game_menu_resume)
	_in_game_menu_view.quit_to_menu_requested.connect(_on_in_game_menu_quit_to_menu)
	_in_game_menu_view.exit_requested.connect(_on_in_game_menu_exit)

func _build_mode_label() -> void:
	_mode_label = Label.new()
	_mode_label.name = "ModeLabel"
	add_child(_mode_label)
	_place_top_wide(_mode_label, 1)  # Row 1: below the resource bar, same top-wide strip.
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDStyles.style_label(_mode_label, true)

func _build_recon_label() -> void:
	_recon_label = Label.new()
	_recon_label.name = "ReconLabel"
	add_child(_recon_label)
	_place_top_wide(_recon_label, 2)
	_recon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HUDStyles.style_label(_recon_label)
	HUDReconTracker.new(self, _recon_label, _horde_manager, _fog_of_war_manager)

func _build_bottom_bar(hex_grid_map: HexGridMap, fog_of_war_manager: FogOfWarManager, camera: CameraController, noise_manager: NoiseManager, resource_manager: ResourceManager) -> void:
	var bar := HBoxContainer.new()
	bar.name = "BottomBar"
	bar.add_theme_constant_override("separation", MARGIN)
	# MOUSE_FILTER_STOP "physically blocks any mouse input events from
	# reaching any other Control node behind it, INCLUDING THE VIEWPORT"
	# (Control.mouse_filter docs) — without it, scrolling through building
	# cards and drifting into a gap between cards (or onto the minimap)
	# leaks the wheel event through to CameraController's own zoom input,
	# covering the whole bar's rect in one place rather than relying on
	# every child control's own filter to add up to full coverage.
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	_place_bottom_wide_row(bar, BOTTOM_BAR_HEIGHT)

	var build_menu := BuildMenuView.new()
	build_menu.name = "BuildMenu"
	bar.add_child(build_menu)
	build_menu.building_selected.connect(_on_building_selected)
	build_menu.wall_placement_selected.connect(_on_wall_placement_selected)
	build_menu.infrastructure_placement_selected.connect(_on_infrastructure_placement_selected)
	build_menu.setup(_tech_manager, resource_manager)

	var minimap := MinimapView.new()
	minimap.name = "Minimap"
	minimap.custom_minimum_size = MINIMAP_SIZE
	minimap.size_flags_vertical = Control.SIZE_FILL  ## Flush against the bar's full height — see MINIMAP_SIZE's own doc comment.
	bar.add_child(minimap)
	minimap.setup(hex_grid_map, _building_manager, fog_of_war_manager, camera, MINIMAP_SIZE, noise_manager)

func _build_unit_panel(unit_manager: UnitManager, wall_manager: WallManager) -> void:
	var unit_panel := UnitPanelView.new()
	unit_panel.name = "UnitPanel"
	add_child(unit_panel)
	_place_top_left(unit_panel, UNIT_PANEL_SIZE)
	if _unit_command_controller:
		unit_panel.setup(_unit_command_controller, unit_manager, _building_manager, wall_manager, _tech_manager)

func _build_toast() -> void:
	_toast = HUDToastRouter.new(self, _place_above_bottom_bar_wide)

## --- Layout helpers ---------------------------------------------------
##
## Deliberately NOT using Control.set_anchors_and_offsets_preset(...,
## PRESET_MODE_MINSIZE, ...): that mode sizes offsets off
## get_combined_minimum_size() at the moment of the call, which for these
## code-built Controls (an HBoxContainer/ScrollContainer whose children were
## just added this same frame) can still read as the Control's initial
## (0, 0) rect — every bottom/right-anchored element ends up positioned just
## past the edge of the screen instead of inside it (found by actually
## running the game, not the headless logic tests alone). These compute
## every offset from an explicit size instead, so they can't go stale.

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

## Strip pinned to the top-right corner, `row` rows down — self-sizes to its
## own content's real width. `fallback_width` only matters for the single
## frame before that measurement lands (children don't exist to measure yet
## at the moment this is called from _build_*()); a one-shot deferred pass
## then re-measures get_combined_minimum_size() and re-anchors to it.
##
## Deferred via `get_tree().process_frame` (a full frame later), not
## `call_deferred` alone — `call_deferred` still fires within the same
## frame's deferred-call flush, before get_combined_minimum_size() is valid
## right after add_child().
func _place_top_right(control: Control, fallback_width: float, row: int) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_right = -MARGIN
	control.offset_left = -MARGIN - fallback_width
	control.offset_top = MARGIN + row * (ROW_HEIGHT + MARGIN)
	control.offset_bottom = control.offset_top + ROW_HEIGHT
	# A fresh lambda per call, not a shared bound method: connecting multiple
	# rows through one shared method+signal within the same _ready() frame
	# hits Godot's connect() dedupe-by-(object,method) — only the first
	# connection actually fires even with CONNECT_REFERENCE_COUNTED, since it
	# dedupes on the method identity, not the bound argument. Confirmed via
	# an actual windowed screenshot, not by reasoning about it. Each
	# `func():` literal below is its own distinct Callable, so the dedupe
	# never engages.
	get_tree().process_frame.connect(func() -> void:
		if not is_instance_valid(control):
			return
		var real_width := control.get_combined_minimum_size().x
		if real_width > 0.0:
			control.offset_left = control.offset_right - real_width
	, CONNECT_ONE_SHOT)

## Bottom-right corner, directly above the bottom bar (build menu + minimap)
## — DayPhaseView's own spot. Same self-measuring correction as
## _place_top_right() (see that function's own note on the fresh-lambda dedupe issue).
func _place_above_bottom_bar_right(control: Control, fallback_width: float) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_right = -MARGIN
	control.offset_left = -MARGIN - fallback_width
	control.offset_bottom = -MARGIN - BOTTOM_BAR_HEIGHT - MARGIN
	control.offset_top = control.offset_bottom - ROW_HEIGHT
	get_tree().process_frame.connect(func() -> void:
		if not is_instance_valid(control):
			return
		var real_width := control.get_combined_minimum_size().x
		if real_width > 0.0:
			control.offset_left = control.offset_right - real_width
	, CONNECT_ONE_SHOT)

## Full-width strip above the bottom bar — the toast's own spot. One row
## higher than _place_above_bottom_bar_right()'s row (DayPhaseView's spot),
## not the same one, so a shown toast doesn't cover the date/countdown.
func _place_above_bottom_bar_wide(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = MARGIN
	control.offset_right = -MARGIN
	control.offset_bottom = -MARGIN - BOTTOM_BAR_HEIGHT - MARGIN - ROW_HEIGHT - MARGIN
	control.offset_top = control.offset_bottom - ROW_HEIGHT

## Fixed-`size` rect pinned to the top-left corner, below the top-wide strip
## (2 rows tall) — UnitPanelView's own spot, the one corner nothing else here claims.
func _place_top_left(control: Control, size: Vector2) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = MARGIN
	control.offset_right = MARGIN + size.x
	control.offset_top = MARGIN + 2 * (ROW_HEIGHT + MARGIN)
	control.offset_bottom = control.offset_top + size.y

## Full-width strip pinned to the bottom edge, `height` tall — the build
## menu + minimap row's own spot.
func _place_bottom_wide_row(control: Control, height: float) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = MARGIN
	control.offset_right = -MARGIN
	control.offset_bottom = -MARGIN
	control.offset_top = -MARGIN - height

## Rect centered on screen — SaveLoadView's own spot, the first element here
## that isn't pinned to a corner/edge (a toggleable dialog, not an
## always-visible panel). Self-sizes to real content the same way
## _place_top_right() does, whenever `control` exposes get_content_min_size()
## (DisplayOptionsView/SaveLoadView/TechTreeView all do). `fallback_size`
## only matters for the single frame before that measurement lands.
##
## CENTER_VERTICAL_BIAS shifts every centered dialog's center point up by
## half the bottom bar's footprint: a screen-centered dialog anchored to the
## full viewport can be tall enough that its bottom portion (including its
## Close button) renders behind the full-width bottom bar — later in
## MainHUD's own child order, so it draws on top and eats the click too, not
## just the pixels.
const CENTER_VERTICAL_BIAS := (BOTTOM_BAR_HEIGHT + MARGIN) / 2.0

func _place_center(control: Control, fallback_size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -fallback_size.x / 2.0
	control.offset_right = fallback_size.x / 2.0
	control.offset_top = -fallback_size.y / 2.0 - CENTER_VERTICAL_BIAS
	control.offset_bottom = fallback_size.y / 2.0 - CENTER_VERTICAL_BIAS
	if control.has_method("get_content_min_size"):
		get_tree().process_frame.connect(func() -> void:
			if not is_instance_valid(control):
				return
			var content: Vector2 = control.get_content_min_size()
			if content.x <= 0.0 or content.y <= 0.0:
				return
			# HUDStyles.make_panel_stylebox()'s own content_margin_* (10
			# left/right, 8 top/bottom) — the panel background needs to
			# extend that far past the inner layout on every side.
			var size := content + Vector2(20.0, 16.0)
			control.offset_left = -size.x / 2.0
			control.offset_right = size.x / 2.0
			control.offset_top = -size.y / 2.0 - CENTER_VERTICAL_BIAS
			control.offset_bottom = size.y / 2.0 - CENTER_VERTICAL_BIAS
		, CONNECT_ONE_SHOT)

## Checked here, not inside BuildMenuView itself — that view stays a "dumb
## selector with no idea what a hex/resource state is" (BuildPlacementController/
## BuildingManager are MainHUD's job to consult). An unaffordable building
## never arms placement mode at all.
func _on_building_selected(building_type: GameEnums.BuildingType) -> void:
	if _building_manager:
		var error := _building_manager.get_affordability_error(building_type)
		if not error.is_empty():
			_toast.show(error)
			return
	if _build_placement_controller:
		_build_placement_controller.begin_placement(building_type)

func _on_wall_placement_selected(is_gate: bool) -> void:
	if _wall_placement_controller:
		_wall_placement_controller.begin_placement(is_gate)

func _on_infrastructure_placement_selected(line_type: GameEnums.SupplyLineType) -> void:
	if _supply_line_placement_controller:
		_supply_line_placement_controller.begin_placement(line_type)

func _on_training_started(unit_type: GameEnums.UnitType, _coord: Vector2i, days: int) -> void:
	var definition := UnitCatalog.get_definition(unit_type)
	var display_name := definition.display_name if definition else "Unit"
	_toast.show("Training %s — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_retrain_started(_instance: UnitInstance, new_type: GameEnums.UnitType, days: int) -> void:
	var definition := UnitCatalog.get_definition(new_type)
	var display_name := definition.display_name if definition else "unit"
	_toast.show("Retraining into %s — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_in_game_menu_resume() -> void:
	_in_game_menu_view.close()

## Godot frees the whole current scene tree on change_scene_to_file()
## (MainHUD included), so there's nothing else to tear down here first.
func _on_in_game_menu_quit_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")

func _on_in_game_menu_exit() -> void:
	get_tree().quit()

func _on_save_load_view_save_requested(campaign_name: String, slot_name: String) -> void:
	if _save_load_manager:
		_save_load_manager.save_game(campaign_name, slot_name)

func _on_save_load_view_load_requested(campaign_name: String, slot_name: String) -> void:
	if _save_load_manager:
		_save_load_manager.load_game(campaign_name, slot_name)

func _on_game_saved(_campaign_name: String, _slot_name: String) -> void:
	_toast.show("Game saved.")

func _on_game_loaded(_campaign_name: String, _slot_name: String) -> void:
	_toast.show("Game loaded.")

func _on_load_failed(_campaign_name: String, _slot_name: String, reason: String) -> void:
	_toast.show("Load failed: %s" % reason)

func _on_research_requested(tech_id: StringName) -> void:
	if _tech_manager:
		_tech_manager.start_research(tech_id)

func _on_tech_researched(tech_id: StringName) -> void:
	var definition := TechCatalog.get_definition(tech_id)
	_toast.show("%s researched." % (definition.display_name if definition else String(tech_id)))

func _on_research_rejected(_tech_id: StringName, reason: String) -> void:
	_toast.show(reason)

## An independent second listener on EventManager.event_raised alongside
## AlertManager's own audio/auto-pause. A CRITICAL/WARNING event pauses the
## game via AlertManager in the same frame, and the toast timer is
## Engine.time_scale-scaled like everything else here, so the toast stays up
## for as long as the game stays paused rather than ticking away unread.
func _on_event_raised(event: GameEvent) -> void:
	_toast.show(event.message)
