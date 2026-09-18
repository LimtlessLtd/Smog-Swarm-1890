class_name VerticalSliceHUD
extends CanvasLayer

## The slice's own screen furniture, built in code like MainHUD and hidden unless
## VerticalSliceDirector is running a slice:
##
## - **Objectives** (top left): each with its live detail and a progress bar, the
##   controls the slice needs, and army shortcuts — select every squad, train a
##   Toxophilite at the Garrison.
## - **Dispatch** (top centre): the director's latest dispatch, with "Go to" to put
##   the camera where it happened at the zoom that frames it. Urgent ones stop the
##   clock (TickManager.set_speed_index(0, true), the same automatic pause
##   AlertManager uses).
## - **What they see and hear** (right): every lit or noisy building in the town,
##   whether it is running, a switch for each, and how far the town is seen and
##   heard at night with what is running now — going dark, as a control with its
##   consequence printed beside it.
## - **Debrief**: on VerticalSliceDirector.slice_finished, VerticalSliceDebrief's
##   account of what happened and why it mattered.
##
## Everything it changes goes through public manager methods; it decides nothing
## about the game.

const MARGIN := 10.0
const TOP_OFFSET := 110.0  ## Below MainHUD's resource bar.
const OBJECTIVES_WIDTH := 270.0
const DISPATCH_WIDTH := 310.0
const EMISSIONS_WIDTH := 320.0
const EMISSIONS_TOP := 250.0  ## Below MainHUD's time controls and Menu/Tech Tree buttons.
const DEBRIEF_SIZE := Vector2(900.0, 700.0)
const REFRESH_REAL_SECONDS := 0.5
const GOOD_COLOR := Color(0.55, 0.95, 0.5)

@export var director_path: NodePath
@export var consequence_log_path: NodePath
@export var building_manager_path: NodePath
@export var unit_manager_path: NodePath
@export var infestation_manager_path: NodePath
@export var unit_command_controller_path: NodePath
@export var camera_path: NodePath

var _director: VerticalSliceDirector
var _log: ConsequenceLog
var _buildings: BuildingManager
var _units: UnitManager
var _infestation: InfestationManager
var _commands: UnitCommandController
var _camera: CameraController

var _root: Control
var _objectives_panel: PanelContainer
var _objectives_list: VBoxContainer
var _dispatch_panel: PanelContainer
var _dispatch_title: Label
var _dispatch_body: Label
var _dispatch_world := Vector2.ZERO
var _dispatch_zoom := 0.3
var _emissions_panel: PanelContainer
var _emissions_list: VBoxContainer
var _emissions_summary: Label
var _debrief: PanelContainer
var _last_refresh_ms: int = 0
var _emissions_signature: String = ""
var _started: bool = false


func _ready() -> void:
	layer = 5
	if director_path:
		_director = get_node_or_null(director_path) as VerticalSliceDirector
	if consequence_log_path:
		_log = get_node_or_null(consequence_log_path) as ConsequenceLog
	if building_manager_path:
		_buildings = get_node_or_null(building_manager_path) as BuildingManager
	if unit_manager_path:
		_units = get_node_or_null(unit_manager_path) as UnitManager
	if infestation_manager_path:
		_infestation = get_node_or_null(infestation_manager_path) as InfestationManager
	if unit_command_controller_path:
		_commands = get_node_or_null(unit_command_controller_path) as UnitCommandController
	if camera_path:
		_camera = get_node_or_null(camera_path) as CameraController
	visible = false
	if not _director or not _director.is_active():
		return
	_build()
	_director.objectives_changed.connect(_refresh_objectives)
	_director.dispatch.connect(_on_dispatch)
	_director.slice_finished.connect(_on_slice_finished)
	if _buildings:
		for signal_name in ["building_powered_down", "building_powered_up", "building_restart_started", "building_ruined", "building_placed"]:
			_buildings.connect(signal_name, func(_a = null, _b = null) -> void: _emissions_signature = "")
	visible = true
	_started = true
	_refresh_objectives()
	_refresh_emissions()


## Real time, not game time: a restart counts down and the summary changes while the
## player watches, including at speeds where a game-scaled delta would be huge or,
## paused, zero.
func _process(_delta: float) -> void:
	if not _started:
		return
	var now := Time.get_ticks_msec()
	if now - _last_refresh_ms >= int(REFRESH_REAL_SECONDS * 1000.0):
		_last_refresh_ms = now
		_refresh_emissions()


# --- Layout -------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_objectives_panel = _panel(Vector2(MARGIN, TOP_OFFSET), OBJECTIVES_WIDTH)
	var column := _column(_objectives_panel)
	var toggle := _button("MANCHESTER, 1890  ·  Objectives ▾", func() -> void:
		_objectives_list.visible = not _objectives_list.visible
		_objectives_panel.reset_size())
	column.add_child(toggle)
	_objectives_list = VBoxContainer.new()
	_objectives_list.add_theme_constant_override("separation", 6)
	column.add_child(_objectives_list)
	_objectives_list.visible = false
	column.add_child(HSeparator.new())
	var army := HBoxContainer.new()
	army.add_theme_constant_override("separation", 6)
	army.add_child(_button("Army", _on_select_all))
	army.add_child(_button("Archer · 30 Wood", _on_train_archer))
	column.add_child(army)


	_dispatch_panel = PanelContainer.new()
	HUDStyles.style_panel(_dispatch_panel)
	_dispatch_panel.anchor_left = 1.0
	_dispatch_panel.anchor_right = 1.0
	_dispatch_panel.offset_left = -DISPATCH_WIDTH - MARGIN
	_dispatch_panel.offset_right = -MARGIN
	_dispatch_panel.offset_top = 186.0
	_dispatch_panel.visible = false
	_root.add_child(_dispatch_panel)
	var dispatch_column := _column(_dispatch_panel)
	_dispatch_title = _label("", true)
	_dispatch_title.add_theme_font_size_override("font_size", 14)
	dispatch_column.add_child(_dispatch_title)
	_dispatch_body = _label("")
	_dispatch_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dispatch_body.custom_minimum_size = Vector2(DISPATCH_WIDTH - 24.0, 0.0)
	_dispatch_body.add_theme_font_size_override("font_size", 12)
	dispatch_column.add_child(_dispatch_body)
	var dispatch_buttons := HBoxContainer.new()
	dispatch_buttons.add_theme_constant_override("separation", 6)
	dispatch_buttons.add_child(_button("Go to", _on_go_to))
	dispatch_buttons.add_child(_button("Dismiss", func() -> void: _dispatch_panel.visible = false))
	dispatch_column.add_child(dispatch_buttons)



func _panel(position: Vector2, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	HUDStyles.style_panel(panel)
	panel.position = position
	panel.custom_minimum_size = Vector2(width, 0.0)
	_root.add_child(panel)
	return panel


func _column(parent: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	return column


func _label(text: String, accent: bool = false, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	HUDStyles.style_label(label, accent, muted)
	if muted:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(OBJECTIVES_WIDTH - 24.0, 0.0)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	HUDStyles.style_button(button)
	button.pressed.connect(on_pressed)
	return button


# --- Objectives ---------------------------------------------------------------

func _refresh_objectives() -> void:
	if not _objectives_list:
		return
	for child in _objectives_list.get_children():
		child.queue_free()
	for objective in _director.get_objectives():
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var state: StringName = objective["state"]
		var mark := "☐" if state == &"active" else ("☑" if state == &"done" else "☒")
		var title := _label("%s  %s%s" % [mark, objective["title"], "" if objective["required"] else "  (optional)"])
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = OBJECTIVES_WIDTH - 24.0
		if state == &"done":
			title.add_theme_color_override("font_color", GOOD_COLOR)
		elif state == &"failed":
			title.add_theme_color_override("font_color", HUDStyles.DANGER_COLOR)
		row.add_child(title)
		if not String(objective["detail"]).is_empty():
			row.add_child(_label(objective["detail"], false, true))
		if state == &"active":
			var bar := ProgressBar.new()
			bar.min_value = 0.0
			bar.max_value = 1.0
			bar.value = float(objective["progress"])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(OBJECTIVES_WIDTH - 30.0, 8.0)
			row.add_child(bar)
		_objectives_list.add_child(row)


func _on_select_all() -> void:
	if _commands and _units:
		_commands.select_units(_units.get_all_units())


func _on_train_archer() -> void:
	if not _units:
		return
	var error := _units.get_training_error(GameEnums.UnitType.TOXOPHILITE, VerticalSliceConfig.START_HEX)
	if not error.is_empty():
		_show_dispatch("Cannot train", error, _dispatch_world, _dispatch_zoom)
		return
	_units.train_unit(GameEnums.UnitType.TOXOPHILITE, VerticalSliceConfig.START_HEX)


# --- Dispatch -----------------------------------------------------------------

func _on_dispatch(title: String, body: String, world: Vector2, zoom: float, urgent: bool) -> void:
	_show_dispatch(title, body, world, zoom)
	if urgent:
		TickManager.set_speed_index(0, true)


func _show_dispatch(title: String, body: String, world: Vector2, zoom: float) -> void:
	_dispatch_title.text = title
	_dispatch_body.text = body
	_dispatch_world = world
	_dispatch_zoom = zoom
	_dispatch_panel.visible = true
	_dispatch_panel.reset_size()


func _on_go_to() -> void:
	if not _camera:
		return
	_camera.global_position = _dispatch_world
	_camera.set_zoom_level(_dispatch_zoom)


# --- What they see and hear ---------------------------------------------------

func _refresh_emissions() -> void:
	if not _emissions_list or not _buildings:
		return
	# Rebuilt only when something shown changed, so a button is not freed and
	# recreated under the cursor twice a second.
	var signature := ""
	for instance in _buildings.get_buildings_at(VerticalSliceConfig.START_HEX):
		if instance.definition.lit_at_night or instance.definition.noise_source_db > 0.0:
			signature += "%d:%s:%s:%s:%d;" % [instance.id, instance.is_ruined, instance.is_running(), _buildings.is_building_restarting(instance), _buildings.get_restart_hours_remaining(instance)]
	if signature == _emissions_signature:
		return
	_emissions_signature = signature
	for child in _emissions_list.get_children():
		child.queue_free()
	var lamps := 0
	var loudest_night_reach := -1.0
	var loudest_name := ""
	var groups: Dictionary = {}  # BuildingType -> {definition, running: Array, off: Array, restarting: int}
	var order: Array = []
	for instance in _buildings.get_buildings_at(VerticalSliceConfig.START_HEX):
		var definition := instance.definition
		if not (definition.lit_at_night or definition.noise_source_db > 0.0) or instance.is_ruined:
			continue
		if not groups.has(definition.building_type):
			groups[definition.building_type] = {"definition": definition, "running": [], "off": [], "restarting": 0}
			order.append(definition.building_type)
		var group: Dictionary = groups[definition.building_type]
		if instance.is_running():
			group["running"].append(instance)
			if definition.lit_at_night:
				lamps += 1
			if definition.noise_source_db > 0.0:
				var reach := night_hearing_reach_hexes(definition.noise_source_db)
				if reach > loudest_night_reach:
					loudest_night_reach = reach
					loudest_name = definition.display_name
		elif _buildings.is_building_restarting(instance):
			group["restarting"] = int(group["restarting"]) + 1
		else:
			group["off"].append(instance)
	for building_type in order:
		var group: Dictionary = groups[building_type]
		var definition: BuildingDefinition = group["definition"]
		var running: Array = group["running"]
		var off: Array = group["off"]
		var total := running.size() + off.size() + int(group["restarting"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var state := "%d/%d on" % [running.size(), total]
		if int(group["restarting"]) > 0:
			state += ", %d restarting" % int(group["restarting"])
		var name_label := _label("%s%s · %s" % [definition.display_name, " ×%d" % total if total > 1 else "", state])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		if running.is_empty():
			name_label.add_theme_color_override("font_color", HUDStyles.MUTED_COLOR)
		row.add_child(name_label)
		if not running.is_empty():
			var first_running: BuildingInstance = running[0]
			row.add_child(_button("Off", func() -> void: _buildings.power_down_building(first_running)))
		if not off.is_empty():
			var first_off: BuildingInstance = off[0]
			row.add_child(_button("On (%d h)" % _buildings.get_restart_hours_for(definition), func() -> void: _buildings.restart_building(first_off)))
		_emissions_list.add_child(row)
	var light_reach := NoiseManager.light_reach_hexes(lamps, HordeManager.ATTRACTION_THRESHOLD)
	var lines: Array[String] = []
	if lamps == 0:
		lines.append("No lamps burning: at night the town is not seen.")
	elif light_reach < 0:
		lines.append("%d lamp burning: too dim to draw a horde on its own." % lamps)
	else:
		lines.append("%d lamp%s burning: at night the town is seen from %d hex%s." % [lamps, "" if lamps == 1 else "s", light_reach, "" if light_reach == 1 else "es"])
	if loudest_name.is_empty():
		lines.append("Nothing loud running.")
	elif loudest_night_reach < 1.0:
		lines.append("%s heard only inside the town." % loudest_name)
	else:
		lines.append("%s heard from %.1f hexes at night." % [loudest_name, loudest_night_reach])
	lines.append("A horde draws closer to whatever reaches it.")
	_emissions_summary.text = "\n".join(lines)
	# Deferred: the rows freed above are only queued, and still count toward the
	# panel's minimum size until the end of this frame.
	_emissions_panel.call_deferred("reset_size")


## Hexes from its source at which a machine's night noise still clears
## HordeManager.ATTRACTION_THRESHOLD, by NoisePropagation's own falloff with no
## terrain in the way.
static func night_hearing_reach_hexes(source_db: float) -> float:
	var metres := NoisePropagation.distance_to_level(source_db + NoisePropagation.NIGHT_PROPAGATION_BONUS_DB, NoisePropagation.HEARING_THRESHOLD_DB + HordeManager.ATTRACTION_THRESHOLD)
	return metres / (HexCoord.axial_to_world(Vector2i(1, 0)).length() / HexCoord.WORLD_UNITS_PER_REAL_METER)


# --- Debrief ------------------------------------------------------------------

func _on_slice_finished(outcome: StringName) -> void:
	TickManager.set_speed_index(0)
	_dispatch_panel.visible = false
	var report := VerticalSliceDebrief.build(outcome, _director, _log, _buildings, _infestation, _units)
	_debrief = PanelContainer.new()
	HUDStyles.style_panel(_debrief)
	_debrief.anchor_left = 0.5
	_debrief.anchor_right = 0.5
	_debrief.anchor_top = 0.5
	_debrief.anchor_bottom = 0.5
	_debrief.offset_left = -DEBRIEF_SIZE.x * 0.5
	_debrief.offset_right = DEBRIEF_SIZE.x * 0.5
	_debrief.offset_top = -DEBRIEF_SIZE.y * 0.5
	_debrief.offset_bottom = DEBRIEF_SIZE.y * 0.5
	_root.add_child(_debrief)
	var column := _column(_debrief)
	var title := _label(report["title"], true)
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	column.add_child(_label(report["subtitle"], false, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	body.add_child(_section("WHY IT WENT THE WAY IT DID"))
	for line in report["why"]:
		body.add_child(_wrapped("•  " + line, 15))
	body.add_child(_section("WHAT HAPPENED"))
	for line in report["timeline"]:
		body.add_child(_wrapped(line, 13, true))
	body.add_child(_section("NUMBERS"))
	for line in report["stats"]:
		body.add_child(_wrapped(line, 13))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.add_child(_button("Play again", _on_play_again))
	buttons.add_child(_button("Keep playing", func() -> void: _debrief.visible = false))
	buttons.add_child(_button("Main menu", func() -> void: get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")))
	column.add_child(buttons)


func _section(text: String) -> Label:
	var label := _label(text, true)
	label.add_theme_font_size_override("font_size", 16)
	return label


func _wrapped(text: String, font_size: int, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	HUDStyles.style_label(label, false, muted)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(DEBRIEF_SIZE.x - 60.0, 0.0)
	return label


func _on_play_again() -> void:
	GameLaunchState.request_vertical_slice()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


## For the playtest runner and a verification: the debrief the current state would
## produce, without building the panel.
func get_debrief_preview(outcome: StringName) -> Dictionary:
	return VerticalSliceDebrief.build(outcome, _director, _log, _buildings, _infestation, _units)
