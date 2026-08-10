class_name MainHUD
extends CanvasLayer

## Root HUD coordinator — the essential slice of design doc Phase 6.1:
## resource display, the build/placement menu, unit training/orders panel,
## time controls, and the Strategic-layer minimap (shown only during
## Tactical zoom — see MinimapView's own doc comment for why). **The
## per-sector Threat Meter is implemented now too** — drawn on the minimap
## itself (MinimapView's own doc comment has the full mechanism), fed by
## the Phase 5.2 `NoiseManager` system this HUD's own optional
## `noise_manager_path` wires through.
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
## Quick Save/Load buttons stay for a one-click fixed campaign/slot, but a
## real campaign/slot browser now exists too (`SaveLoadView`, Phase 2.8.3,
## a "Browse Saves..." button opens it) — the deferred piece that phase's
## own note used to point at. Phase 2.9.3's Tech Tree screen (`TechTreeView`,
## a "Tech Tree..." button) follows the exact same toggleable-panel
## convention, the second view to do so. **`DisplayOptionsView`** (user
## request — "add options so we can enable and disable the overlays," a
## "Display..." button) is the third, letting the player toggle every
## `StrategicOverlayManager` marker layer AND the Threat Meter's two
## surfaces independently via the `DisplaySettings` autoload; all three
## centered panels close each other on open so they never visibly stack.
##
## Phase 5.3's Reconnaissance countdown (`_recon_label`) is a single status
## row, not a separate view class — deliberately as minimal as `_mode_label`
## already is for the same "one line of text, blank when nothing relevant"
## shape, not worth a fourth dumb-display-component class for one Label.

@export var resource_manager_path: NodePath
@export var building_manager_path: NodePath
@export var save_load_manager_path: NodePath
@export var build_placement_controller_path: NodePath
@export var unit_command_controller_path: NodePath
@export var unit_manager_path: NodePath
@export var hex_grid_map_path: NodePath
@export var fog_of_war_manager_path: NodePath
@export var camera_path: NodePath
@export var event_manager_path: NodePath  ## Optional — Phase 6.2's EventManager; without it, world events simply show no toast (AlertManager's own audio/auto-pause is unaffected either way).
@export var tech_manager_path: NodePath   ## Optional — Phase 2.9.3's Tech Tree screen; unset means the panel/button simply do nothing.
@export var horde_manager_path: NodePath  ## Optional — Phase 5.3's Reconnaissance countdown; unset means that HUD row stays permanently empty.
@export var noise_manager_path: NodePath  ## Optional — Phase 6.1's Threat Meter (drawn on the minimap); unset means no threat markers, everything else about the minimap is unaffected.
@export var wall_manager_path: NodePath   ## Optional — feeds UnitPanelView's wall-repair toast/live-refresh; unset means a selected wall's Repair button still works (UnitCommandController owns the actual call) but the panel won't live-refresh mid-repair and no toast fires.
@export var wall_placement_controller_path: NodePath  ## Optional — arms WallPlacementController from BuildMenuView's new Walls tab; unset means that tab's buttons simply do nothing (same "gracefully skip it" convention as every other optional MainHUD dependency).

const DEFAULT_CAMPAIGN := "Default"
const DEFAULT_SLOT := "QuickSave"
const TOAST_SECONDS := 3.0
const RECON_REFRESH_SECONDS := 1.0  ## Matches TimeControlsView's own "refreshed once a second" cadence — no need to recompute an ETA every frame.

const MARGIN := 8.0
const ROW_HEIGHT := 32.0
const TIME_CONTROLS_WIDTH := 520.0  ## Widened for Phase 5.1's date + phase countdown text alongside the day counter/speed buttons; widened again for the 50x speed button.
const SAVE_LOAD_WIDTH := 220.0
const TECH_BAR_WIDTH := 150.0
const DISPLAY_BAR_WIDTH := 150.0
const BUILD_MENU_SIZE := Vector2(320.0, 300.0)  ## Matches BuildMenuView's own custom_minimum_size (Phase 6.1 tab rework) — wide enough for its 4 category tabs, tall enough that a short category's list doesn't feel cramped.
const MINIMAP_SIZE := Vector2(220.0, 160.0)
const UNIT_PANEL_SIZE := Vector2(260.0, 260.0)
const SAVE_LOAD_VIEW_SIZE := Vector2(320.0, 320.0)
const TECH_TREE_VIEW_SIZE := Vector2(380.0, 360.0)
const DISPLAY_OPTIONS_VIEW_SIZE := Vector2(320.0, 300.0)

var _building_manager: BuildingManager
var _save_load_manager: SaveLoadManager
var _build_placement_controller: BuildPlacementController
var _unit_command_controller: UnitCommandController
var _save_load_view: SaveLoadView
var _tech_manager: TechManager
var _tech_tree_view: TechTreeView
var _display_options_view: DisplayOptionsView
var _horde_manager: HordeManager
var _fog_of_war_manager: FogOfWarManager

var _mode_label: Label
var _recon_label: Label
var _toast_label: Label
var _toast_timer: Timer
var _wall_manager: WallManager
var _wall_placement_controller: WallPlacementController

func _ready() -> void:
	var resource_manager: ResourceManager = null
	if resource_manager_path != NodePath():
		resource_manager = get_node(resource_manager_path)
	if building_manager_path != NodePath():
		_building_manager = get_node(building_manager_path)
		_building_manager.placement_rejected.connect(_on_placement_rejected)
		# User report: building/repair now take real time (BuildingManager's
		# own doc comment) — without a toast at the moment a click is
		# accepted, spending resources with nothing else visibly happening
		# would read as broken, not "in progress."
		_building_manager.construction_started.connect(_on_construction_started)
		_building_manager.repair_started.connect(_on_building_repair_started)
	if wall_manager_path != NodePath():
		_wall_manager = get_node(wall_manager_path)
		_wall_manager.repair_started.connect(_on_wall_repair_started)
		_wall_manager.placement_rejected.connect(_on_wall_placement_rejected)
	if wall_placement_controller_path != NodePath():
		_wall_placement_controller = get_node(wall_placement_controller_path)
		_wall_placement_controller.placement_started.connect(_on_wall_placement_started)
		_wall_placement_controller.placement_ended.connect(_on_placement_ended)  ## Reused directly — it only ever clears _mode_label, doesn't care what was being placed, same as buildings.
	if save_load_manager_path != NodePath():
		_save_load_manager = get_node(save_load_manager_path)
		_save_load_manager.game_saved.connect(_on_game_saved)
		_save_load_manager.game_loaded.connect(_on_game_loaded)
		_save_load_manager.load_failed.connect(_on_load_failed)
	if build_placement_controller_path != NodePath():
		_build_placement_controller = get_node(build_placement_controller_path)
		_build_placement_controller.placement_started.connect(_on_placement_started)
		_build_placement_controller.placement_ended.connect(_on_placement_ended)
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
	_build_save_load_bar()
	_build_save_load_view()
	_build_tech_bar()
	_build_tech_tree_view()
	_build_display_bar()
	_build_display_options_view()
	_build_minimap(hex_grid_map, _fog_of_war_manager, camera, noise_manager)
	_build_mode_label()
	_build_recon_label()
	_build_build_menu()
	_build_unit_panel(unit_manager, _wall_manager)
	_build_toast()

func _build_resource_bar(resource_manager: ResourceManager) -> void:
	var resource_bar := ResourceBarView.new()
	resource_bar.name = "ResourceBar"
	add_child(resource_bar)
	_place_top_wide(resource_bar, 0)
	if resource_manager:
		resource_bar.setup(resource_manager)

func _build_time_controls() -> void:
	var time_controls := TimeControlsView.new()
	time_controls.name = "TimeControls"
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
	bar.name = "SaveLoadBar"
	add_child(bar)
	_place_top_right(bar, SAVE_LOAD_WIDTH, 2)  # Row 2: stacks below TimeControlsView in the same corner.

	var save_button := Button.new()
	save_button.text = "Quick Save"
	save_button.pressed.connect(_on_quick_save_pressed)
	HUDStyles.style_button(save_button)
	bar.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Quick Load"
	load_button.pressed.connect(_on_quick_load_pressed)
	HUDStyles.style_button(load_button)
	bar.add_child(load_button)

	var browse_button := Button.new()
	browse_button.text = "Browse Saves..."
	browse_button.pressed.connect(_on_browse_saves_pressed)
	HUDStyles.style_button(browse_button)
	bar.add_child(browse_button)

## Phase 2.8.3's actual Save/Load UI — centered, hidden until
## "Browse Saves..." opens it (see SaveLoadView's own doc comment for why
## it's the first toggleable panel in this HUD rather than another
## always-visible corner view).
func _build_save_load_view() -> void:
	_save_load_view = SaveLoadView.new()
	_save_load_view.name = "SaveLoadView"
	add_child(_save_load_view)
	_place_center(_save_load_view, SAVE_LOAD_VIEW_SIZE)
	if _save_load_manager:
		_save_load_view.setup(_save_load_manager)
	_save_load_view.save_requested.connect(_on_save_load_view_save_requested)
	_save_load_view.load_requested.connect(_on_save_load_view_load_requested)

## Design doc Phase 2.9.3's Tech Tree screen — a single "Tech Tree..."
## button, same row-stacking convention as SaveLoadBar (row 3, directly
## below it in the same top-right corner). Gracefully no-ops if
## tech_manager_path wasn't wired, same convention as everything else here.
func _build_tech_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TechBar"
	add_child(bar)
	_place_top_right(bar, TECH_BAR_WIDTH, 3)  # Row 3: stacks below SaveLoadBar in the same corner.

	var tech_button := Button.new()
	tech_button.text = "Tech Tree..."
	tech_button.pressed.connect(_on_tech_tree_pressed)
	HUDStyles.style_button(tech_button)
	bar.add_child(tech_button)

## Centered, hidden until "Tech Tree..." opens it — same toggleable-panel
## convention SaveLoadView (Phase 2.8.3) already established; this is the
## second panel here to follow it, not a new pattern.
func _build_tech_tree_view() -> void:
	_tech_tree_view = TechTreeView.new()
	_tech_tree_view.name = "TechTreeView"
	add_child(_tech_tree_view)
	_place_center(_tech_tree_view, TECH_TREE_VIEW_SIZE)
	if _tech_manager:
		_tech_tree_view.setup(_tech_manager)
	_tech_tree_view.research_requested.connect(_on_research_requested)

## User request ("add options so we can enable and disable the overlays"):
## a single "Display..." button, row 4 — stacks below TechBar in the same
## top-right corner, same row-stacking convention as SaveLoadBar/TechBar.
func _build_display_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "DisplayBar"
	add_child(bar)
	_place_top_right(bar, DISPLAY_BAR_WIDTH, 4)

	var display_button := Button.new()
	display_button.text = "Display..."
	display_button.pressed.connect(_on_display_options_pressed)
	HUDStyles.style_button(display_button)
	bar.add_child(display_button)

## Centered, hidden until "Display..." opens it — the third panel here to
## follow SaveLoadView/TechTreeView's own toggleable convention. No
## `setup()` call needed (unlike those two) — DisplayOptionsView reads/
## writes the DisplaySettings autoload directly, see its own doc comment
## for why that's a deliberate exception to this HUD's usual pattern.
func _build_display_options_view() -> void:
	_display_options_view = DisplayOptionsView.new()
	_display_options_view.name = "DisplayOptionsView"
	add_child(_display_options_view)
	_place_center(_display_options_view, DISPLAY_OPTIONS_VIEW_SIZE)

## Design doc Phase 6.1's minimap — bottom-right corner is the only one of
## the four still unclaimed by another HUD element (top strip: resource
## bar/mode label; top-right: time controls/save-load; bottom-left: build
## menu; bottom strip: toast). Gracefully no-ops (an empty, permanently
## hidden Control) if any of the three optional NodePaths weren't wired —
## same "unset gracefully skips it" convention every other optional
## MainHUD dependency already follows. `noise_manager` (optional, Phase 6.1's
## Threat Meter) is the minimap's own fourth optional input — see
## MinimapView's own doc comment for what it draws.
func _build_minimap(hex_grid_map: HexGridMap, fog_of_war_manager: FogOfWarManager, camera: CameraController, noise_manager: NoiseManager) -> void:
	var minimap := MinimapView.new()
	minimap.name = "Minimap"
	add_child(minimap)
	_place_bottom_right(minimap, MINIMAP_SIZE)
	minimap.setup(hex_grid_map, _building_manager, fog_of_war_manager, camera, MINIMAP_SIZE, noise_manager)

func _build_mode_label() -> void:
	_mode_label = Label.new()
	_mode_label.name = "ModeLabel"
	add_child(_mode_label)
	_place_top_wide(_mode_label, 1)  # Row 1: below the resource bar, same top-wide strip.
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDStyles.style_label(_mode_label, true)

## Design doc Phase 5.3 (Reconnaissance & Early Warning): "horde countdown
## timers... not just an abstract warning." Row 2, same top-wide strip as
## the resource bar/mode label above it — empty text (same "blank when
## nothing relevant" convention _mode_label already uses) whenever no
## ATTRACTED horde is currently within observed range. "Observed range" is
## this HUD's own interpretation of the design doc's "high ground
## observation posts & telegraph alerts" — Fog of War VISIBLE, reusing
## existing vision sources rather than inventing a new observation-post
## mechanic (every building already projects vision, Phase 2.6).
func _build_recon_label() -> void:
	_recon_label = Label.new()
	_recon_label.name = "ReconLabel"
	add_child(_recon_label)
	_place_top_wide(_recon_label, 2)
	_recon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HUDStyles.style_label(_recon_label)

	var timer := Timer.new()
	timer.wait_time = RECON_REFRESH_SECONDS
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_refresh_recon_label)
	_refresh_recon_label()

## Finds the soonest-arriving currently-observed ATTRACTED horde (if any)
## and shows its ETA — deliberately just the single most urgent one, not a
## scrolling list, matching this row's own "one line of status text" shape
## (same as _mode_label above it). Not gated on
## StrategicOverlayManager.HORDE_MARKER_MIN_SIZE (Phase 5.10's size>=100
## Strategic-marker threshold) on purpose: early warning is exactly the
## case where a smaller, not-yet-marker-worthy horde still matters.
func _refresh_recon_label() -> void:
	if not _horde_manager or not _fog_of_war_manager:
		_recon_label.text = ""
		return
	var best_eta := INF
	var best_horde: Horde = null
	for horde in _horde_manager.get_all_hordes():
		if horde.state != GameEnums.HordeState.ATTRACTED:
			continue
		if not _fog_of_war_manager.is_visible(horde.hex_coord):
			continue
		var eta := _horde_manager.get_eta_seconds(horde)
		if eta < best_eta:
			best_eta = eta
			best_horde = horde
	if not best_horde:
		_recon_label.text = ""
		return
	_recon_label.text = "⚠ Horde approaching (%d) — ETA %s" % [best_horde.size, _format_eta(best_eta)]

func _format_eta(seconds: float) -> String:
	var total := int(roundf(seconds))
	return "%02d:%02d" % [total / 60, total % 60]

func _build_build_menu() -> void:
	var build_menu := BuildMenuView.new()
	build_menu.name = "BuildMenu"
	add_child(build_menu)
	_place_bottom_left(build_menu, BUILD_MENU_SIZE)
	build_menu.building_selected.connect(_on_building_selected)
	build_menu.wall_placement_selected.connect(_on_wall_placement_selected)

## UnitPanelView (Phase 6.1's unit training/orders counterpart to the Build
## Menu) — top-left corner, the one spot nothing else in this HUD claims
## (top-wide strip: resource bar/mode label; top-right: time controls/
## save-load; bottom-left: build menu; bottom-right: minimap; bottom-wide:
## toast). Gracefully empty if unit_command_controller_path wasn't wired,
## same "unset gracefully skips it" convention every other optional MainHUD
## dependency already follows.
func _build_unit_panel(unit_manager: UnitManager, wall_manager: WallManager) -> void:
	var unit_panel := UnitPanelView.new()
	unit_panel.name = "UnitPanel"
	add_child(unit_panel)
	_place_top_left(unit_panel, UNIT_PANEL_SIZE)
	if _unit_command_controller:
		unit_panel.setup(_unit_command_controller, unit_manager, _building_manager, wall_manager)

func _build_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
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

## Strip pinned to the top-right corner, `row` rows down — self-sizes to its
## own content's real width rather than trusting a hand-picked constant.
## `fallback_width` only matters for the single frame before that
## measurement lands (children don't exist to measure yet at the moment
## this is called from _build_*()); immediately after, a one-shot deferred
## pass re-measures get_combined_minimum_size() and re-anchors to it. This
## is the actual fix for the family of "TimeControlsView's speed buttons /
## SaveLoadBar's Browse Saves button ran off the right edge of a 1920px
## screen" bugs a real playtest caught — TIME_CONTROLS_WIDTH/SAVE_LOAD_WIDTH
## were both hand-picked guesses that fell behind the first time a button
## got added or re-labelled; auto-sizing can't go stale the same way.
##
## Deferred via `get_tree().process_frame` (a full frame later), not
## `call_deferred` alone — `call_deferred` still fires within the SAME
## frame's deferred-call flush, which is exactly the timing this class's own
## header comment already documents as too early for
## get_combined_minimum_size() to be valid right after `add_child()`.
func _place_top_right(control: Control, fallback_width: float, row: int) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_right = -MARGIN
	control.offset_left = -MARGIN - fallback_width
	control.offset_top = MARGIN + row * (ROW_HEIGHT + MARGIN)
	control.offset_bottom = control.offset_top + ROW_HEIGHT
	# A fresh lambda per call, NOT `_resize_top_right.bind(control)` on a
	# shared named method: four separate rows (TimeControls/SaveLoadBar/
	# TechBar/DisplayBar) all resolving through the same method+signal
	# within the same _ready() frame first threw "already connected"
	# (Godot's connect() dedupes by (object, method), ignoring the bound
	# argument), and even with CONNECT_REFERENCE_COUNTED added to silence
	# that, only the FIRST of the four ever actually fired — confirmed by
	# an actual windowed screenshot (1000x button fixed, Browse Saves
	# still clipped) after a --headless run alone reported zero errors,
	# not by reasoning about it. Each `func():` literal below is its own
	# distinct Callable even though the source is identical, so none of
	# this dedup logic ever engages in the first place.
	get_tree().process_frame.connect(func() -> void:
		if not is_instance_valid(control):
			return
		var real_width := control.get_combined_minimum_size().x
		if real_width > 0.0:
			control.offset_left = control.offset_right - real_width
	, CONNECT_ONE_SHOT)

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

## Rect centered on screen — SaveLoadView's own spot, the first HUD element
## here that isn't pinned to a corner/edge (it's a toggleable dialog, not an
## always-visible panel like everything above). Self-sizes to real content
## the same way _place_top_right() does (see that function's own doc
## comment) whenever `control` exposes get_content_min_size()
## (DisplayOptionsView/SaveLoadView/TechTreeView all do) — this is what
## actually fixes "Close renders past the bottom of the panel" for the
## first two: DISPLAY_OPTIONS_VIEW_SIZE/SAVE_LOAD_VIEW_SIZE were both
## hand-picked guesses that fell behind the real content (an extra
## checkbox, a taller list); auto-sizing can't go stale the same way.
## `fallback_size` only matters for the single frame before that
## measurement lands.
func _place_center(control: Control, fallback_size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -fallback_size.x / 2.0
	control.offset_right = fallback_size.x / 2.0
	control.offset_top = -fallback_size.y / 2.0
	control.offset_bottom = fallback_size.y / 2.0
	if control.has_method("get_content_min_size"):
		# A fresh lambda per call, not a shared bound method — see
		# _place_top_right()'s own note on why (three panels here —
		# SaveLoadView/TechTreeView/DisplayOptionsView — resolving through
		# one shared method+signal hit the exact same "only the first one
		# actually fires" problem).
		get_tree().process_frame.connect(func() -> void:
			if not is_instance_valid(control):
				return
			var content: Vector2 = control.get_content_min_size()
			if content.x <= 0.0 or content.y <= 0.0:
				return
			# HUDStyles.make_panel_stylebox()'s own content_margin_* (10
			# left/right, 8 top/bottom) — the panel background needs to
			# extend that far past the inner layout on every side, or
			# content would render flush against (or outside) the panel's
			# own border.
			var size := content + Vector2(20.0, 16.0)
			control.offset_left = -size.x / 2.0
			control.offset_right = size.x / 2.0
			control.offset_top = -size.y / 2.0
			control.offset_bottom = size.y / 2.0
		, CONNECT_ONE_SHOT)

func _on_building_selected(building_type: GameEnums.BuildingType) -> void:
	if _build_placement_controller:
		_build_placement_controller.begin_placement(building_type)

func _on_wall_placement_selected(is_gate: bool) -> void:
	if _wall_placement_controller:
		_wall_placement_controller.begin_placement(is_gate)

func _on_placement_started(building_type: GameEnums.BuildingType) -> void:
	var definition := BuildingCatalog.get_definition(building_type)
	var display_name := definition.display_name if definition else "building"
	_mode_label.text = "Placing: %s — click the map (Shift-click for more, Right-click/Esc to cancel)" % display_name

func _on_placement_ended() -> void:
	_mode_label.text = ""

func _on_placement_rejected(_building_type: GameEnums.BuildingType, _coord: Vector2i, reason: String) -> void:
	_show_toast(reason)

func _on_wall_placement_started(_tier: int) -> void:
	_mode_label.text = "Placing wall — click and drag along the map (Shift-drag for more, Right-click/Esc to cancel)"

func _on_wall_placement_rejected(_hex_a: Vector2i, _hex_b: Vector2i, reason: String) -> void:
	_show_toast(reason)

func _on_construction_started(building_type: GameEnums.BuildingType, _coord: Vector2i, days: int) -> void:
	var definition := BuildingCatalog.get_definition(building_type)
	var display_name := definition.display_name if definition else "Building"
	_show_toast("%s under construction — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_building_repair_started(instance: BuildingInstance, days: int) -> void:
	var display_name := instance.definition.display_name if instance and instance.definition else "Building"
	_show_toast("Repairing %s — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_wall_repair_started(_segment: WallSegment, days: int) -> void:
	_show_toast("Repairing wall segment — ready in %d day%s." % [days, "" if days == 1 else "s"])

func _on_training_started(unit_type: GameEnums.UnitType, _coord: Vector2i, days: int) -> void:
	var definition := UnitCatalog.get_definition(unit_type)
	var display_name := definition.display_name if definition else "Unit"
	_show_toast("Training %s — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_retrain_started(_instance: UnitInstance, new_type: GameEnums.UnitType, days: int) -> void:
	var definition := UnitCatalog.get_definition(new_type)
	var display_name := definition.display_name if definition else "unit"
	_show_toast("Retraining into %s — ready in %d day%s." % [display_name, days, "" if days == 1 else "s"])

func _on_quick_save_pressed() -> void:
	if _save_load_manager:
		_save_load_manager.save_game(DEFAULT_CAMPAIGN, DEFAULT_SLOT)

func _on_quick_load_pressed() -> void:
	if _save_load_manager:
		_save_load_manager.load_game(DEFAULT_CAMPAIGN, DEFAULT_SLOT)

## Each of the three centered panels (SaveLoadView/TechTreeView/
## DisplayOptionsView) shares the same screen position — closing the other
## two before opening this one keeps them from visibly stacking on top of
## each other. Harmless to call close() on an already-closed panel (it's
## just a redundant visible = false).
func _on_browse_saves_pressed() -> void:
	_tech_tree_view.close()
	_display_options_view.close()
	_save_load_view.open()

func _on_save_load_view_save_requested(campaign_name: String, slot_name: String) -> void:
	if _save_load_manager:
		_save_load_manager.save_game(campaign_name, slot_name)

func _on_save_load_view_load_requested(campaign_name: String, slot_name: String) -> void:
	if _save_load_manager:
		_save_load_manager.load_game(campaign_name, slot_name)

func _on_game_saved(_campaign_name: String, _slot_name: String) -> void:
	_show_toast("Game saved.")

func _on_game_loaded(_campaign_name: String, _slot_name: String) -> void:
	_show_toast("Game loaded.")

func _on_load_failed(_campaign_name: String, _slot_name: String, reason: String) -> void:
	_show_toast("Load failed: %s" % reason)

func _on_tech_tree_pressed() -> void:
	_save_load_view.close()
	_display_options_view.close()
	_tech_tree_view.open()

func _on_display_options_pressed() -> void:
	_save_load_view.close()
	_tech_tree_view.close()
	_display_options_view.open()

func _on_research_requested(tech_id: StringName) -> void:
	if _tech_manager:
		_tech_manager.start_research(tech_id)

func _on_tech_researched(tech_id: StringName) -> void:
	var definition := TechCatalog.get_definition(tech_id)
	_show_toast("%s researched." % (definition.display_name if definition else String(tech_id)))

func _on_research_rejected(_tech_id: StringName, reason: String) -> void:
	_show_toast(reason)

## Design doc Phase 6.2 — an independent second listener on EventManager.
## event_raised alongside AlertManager's own audio/auto-pause; see
## AlertManager's own doc comment for why that's not a coincidence. A
## CRITICAL/WARNING event pauses the game via AlertManager in the same
## frame, and _toast_timer's own countdown is Engine.time_scale-scaled like
## everything else here, so the toast naturally stays up for as long as the
## game stays paused rather than ticking away unread.
func _on_event_raised(event: GameEvent) -> void:
	_show_toast(event.message)

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_timer.start()

func _on_toast_timeout() -> void:
	_toast_label.text = ""
