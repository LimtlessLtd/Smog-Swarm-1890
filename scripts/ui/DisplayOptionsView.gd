class_name DisplayOptionsView
extends Panel

## User request: "add options so we can enable and disable the overlays and
## add options for making them on the hex tile world view too." A
## toggleable centered panel — the third to follow `SaveLoadView`/
## `TechTreeView`'s own convention — with one
## checkbox per `DisplaySettings` flag: every `StrategicOverlayManager`
## marker layer on the Strategic hex-tile world view (buildings, frontier,
## walls, units, spotted hordes, under-attack alerts), plus the Threat
## Meter's and Zone of Control's own two independent surfaces each
## (world view AND minimap/Tactical, respectively).
##
## **Deliberate exception to this HUD's usual "dumb view, MainHUD owns the
## actual call" convention** (see SaveLoadView/TechTreeView's own doc
## comments for that convention's normal shape): `DisplaySettings` is pure
## client-side UI preference state, not campaign/game state — there's no
## resource cost, no validation, nothing for MainHUD to orchestrate the way
## it does for a save or a research request. Each checkbox calls
## `DisplaySettings.set_flag()` directly, the same way `CameraController`'s
## own zoom/pan already responds straight to input without going through a
## central orchestrator.

signal closed

var _layout: VBoxContainer

## (Display label, DisplaySettings property name) pairs — declaration
## order is display order. Grouped by surface (world view, then minimap)
## rather than DisplaySettings' own declaration order for readability here;
## the underlying flags don't care which order they're toggled in.
const OPTIONS: Array[Array] = [
	["Building Markers (World Map)", "show_building_markers"],
	["Frontier Indicators (World Map)", "show_frontier_markers"],
	["Wall Markers (World Map)", "show_wall_markers"],
	["Unit Markers (World Map)", "show_unit_markers"],
	["Spotted Horde Markers (World Map)", "show_horde_markers"],
	["Under-Attack Alerts (World Map)", "show_attack_alerts"],
	["Threat Meter (World Map)", "show_threat_meter_world"],
	["Zone of Control (World Map)", "show_zoc_world"],
	["Elevation / Impassable Terrain (Both Views)", "show_terrain_hazards"],  ## No longer World-Map-only — ElevationReliefView draws at Tactical zoom too.
	["Threat Meter (Minimap)", "show_threat_meter_minimap"],
	["Zone of Control (Tactical View)", "show_zoc_tactical"],
]

func _ready() -> void:
	visible = false
	HUDStyles.style_panel(self)

	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", 6)
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(_layout)

	var title := Label.new()
	title.text = "Display"
	HUDStyles.style_label(title, true)
	_layout.add_child(title)

	for option in OPTIONS:
		_layout.add_child(_build_row(option[0], option[1]))

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	HUDStyles.style_button(close_button)
	_layout.add_child(close_button)

## MainHUD's own `_place_center()` reads this to size the panel to its real
## content instead of trusting a hand-picked constant — see that function's
## own doc comment. `_layout` (a VBoxContainer, a real Container subtype)
## correctly reports its own combined minimum size from its children's
## layout needs regardless of whatever rect it currently occupies, unlike
## this Panel itself (Panel doesn't auto-size to children at all).
func get_content_min_size() -> Vector2:
	return _layout.get_combined_minimum_size()

func open() -> void:
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func _build_row(label_text: String, property_name: StringName) -> Control:
	var checkbox := CheckBox.new()
	checkbox.text = label_text
	checkbox.button_pressed = DisplaySettings.get_flag(property_name)
	HUDStyles.style_button(checkbox)  # CheckBox extends Button — style_label() expects a Label specifically and wouldn't type-check here.
	checkbox.toggled.connect(_on_toggled.bind(property_name))
	return checkbox

func _on_toggled(pressed: bool, property_name: StringName) -> void:
	DisplaySettings.set_flag(property_name, pressed)
