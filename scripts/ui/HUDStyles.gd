class_name HUDStyles
extends RefCounted

const PANEL_COLOR: Color = Color("#1f150f")
const PANEL_BORDER: Color = Color("#8b6f44")
const TEXT_COLOR: Color = Color("#f4e7c5")
const MUTED_COLOR: Color = Color("#d7bc80")
const ACCENT_COLOR: Color = Color("#cfa24e")
const BUTTON_NORMAL: Color = Color("#3d2a1d")
const BUTTON_HOVER: Color = Color("#5a3d29")
const BUTTON_PRESSED: Color = Color("#24170f")
const BUTTON_DISABLED: Color = Color("#43372d")
const SHADOW_COLOR: Color = Color("#000000", 0.45)

static func style_label(label: Label, accent: bool = false, muted: bool = false) -> void:
	label.add_theme_color_override("font_color", ACCENT_COLOR if accent else (MUTED_COLOR if muted else TEXT_COLOR))
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 15 if accent else 13)
	label.add_theme_constant_override("line_spacing", 2)

static func style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_NORMAL
	normal.border_color = PANEL_BORDER
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_right = 8
	normal.corner_radius_bottom_left = 8
	normal.content_margin_left = 8.0
	normal.content_margin_right = 8.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BUTTON_HOVER

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BUTTON_PRESSED

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = BUTTON_DISABLED
	disabled.border_color = Color("#67553b")

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", Color("#fff2cb"))
	button.add_theme_color_override("font_pressed_color", Color("#f3e1a2"))
	button.add_theme_color_override("font_disabled_color", Color("#b8a27d"))
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(0, 30)
	# Real bug fix (playtest round 4, #11: pressing Space while already paused
	# "quickly flashes on 5x then flashes back to 0x"). Button's default
	# focus_mode is FOCUS_ALL — clicking ANY button (e.g. TimeControlsView's
	# own "0x" speed button, the most likely button a player clicks right
	# before trying Space) leaves it holding keyboard focus, and Godot's
	# built-in "ui_accept" handling on a focused Button (bound to Enter/Space
	# by default in every Godot project, this one included — see
	# project.godot's default input map) intercepts a later Space press
	# BEFORE it ever reaches TickManager's own `_unhandled_input` — a GUI
	# Control consuming an event (`accept_event()`, called internally by
	# BaseButton) stops it from propagating to unhandled input entirely, the
	# same "GUI gets first refusal" ordering TickManager's own doc comment on
	# `_unhandled_input` already documents. No HUD button in this project
	# needs keyboard/gamepad focus navigation (there is no such Tab-through-
	# controls UI flow anywhere here) — FOCUS_NONE on every button this
	# shared helper styles removes the entire class of "a previously-clicked
	# button silently steals a global keyboard shortcut" bugs at once, not
	# just this one report.
	button.focus_mode = Control.FOCUS_NONE

static func make_panel_stylebox() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_COLOR
	panel.border_color = PANEL_BORDER
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_right = 10
	panel.corner_radius_bottom_left = 10
	panel.shadow_color = Color("#000000", 0.28)
	panel.shadow_size = 4
	panel.content_margin_left = 10.0
	panel.content_margin_right = 10.0
	panel.content_margin_top = 8.0
	panel.content_margin_bottom = 8.0
	return panel

static func style_panel(control: Control) -> void:
	control.add_theme_stylebox_override("panel", make_panel_stylebox())

## BuildMenuView's tab bar (Phase 6.1 rework, user request) — Godot's
## default TabContainer theme is a blue/grey out of place against this
## project's brown/gold Victorian palette everywhere else, the same reason
## style_button()/style_panel() exist rather than leaving controls at
## engine-default theme.
static func style_tab_container(tabs: TabContainer) -> void:
	var selected := StyleBoxFlat.new()
	selected.bg_color = BUTTON_HOVER
	selected.border_color = ACCENT_COLOR
	selected.border_width_bottom = 2
	selected.content_margin_left = 10.0
	selected.content_margin_right = 10.0
	selected.content_margin_top = 5.0
	selected.content_margin_bottom = 5.0

	var unselected := selected.duplicate() as StyleBoxFlat
	unselected.bg_color = BUTTON_NORMAL
	unselected.border_color = PANEL_BORDER
	unselected.border_width_bottom = 1

	var panel := make_panel_stylebox()
	panel.bg_color = Color(PANEL_COLOR, 0.0)  # The tab content area sits directly on this panel's own already-styled background — no second layer needed, just enough of a stylebox to carry content_margin.
	panel.border_width_left = 0
	panel.border_width_top = 0
	panel.border_width_right = 0
	panel.border_width_bottom = 0

	tabs.add_theme_stylebox_override("tab_selected", selected)
	tabs.add_theme_stylebox_override("tab_unselected", unselected)
	tabs.add_theme_stylebox_override("tab_hovered", unselected)
	tabs.add_theme_stylebox_override("panel", panel)
	tabs.add_theme_color_override("font_selected_color", Color("#fff2cb"))
	tabs.add_theme_color_override("font_unselected_color", MUTED_COLOR)
	tabs.add_theme_color_override("font_hovered_color", TEXT_COLOR)
	tabs.add_theme_font_size_override("font_size", 13)

## Shared clickable "card" shape (user request, playtest round 4: buildings
## AND units should show their real art plus cost/upkeep/effect without
## needing to hover) — icon, name, and a multi-line details block, all
## visible at once. Originally BuildMenuView-only; UnitPanelView's own
## training/retrain buttons want the identical shape (art + cost/upkeep),
## so it lives here rather than as two copy-pasted implementations quietly
## drifting apart, same "single shared lookup" reasoning every other
## `HUDStyles`/`*Visuals.gd` helper in this project already follows.
##
## Built as a plain `PanelContainer` with manual `gui_input` rather than a
## stock `Button`: a `Button`'s icon has no reliable size-independent-of-
## source-resolution control in this project's own established pattern (see
## `ResourceBarView`'s own `TextureRect` + `EXPAND_IGNORE_SIZE` note — the
## same AI-generated art here is authored at non-trivial resolution), so a
## hand-built card reuses that exact pattern instead of fighting
## `Button.icon` for it. `on_pressed` takes no arguments — callers `.bind()`
## whatever payload they need. `enabled=false` (a tier-locked/unaffordable
## unit, same as the old disabled-Button convention) dims the card and
## swallows clicks instead of removing it from the row entirely — the
## player can still see what a locked option costs/does.
static func build_card(display_name: String, icon_texture: Texture2D, details: String, on_pressed: Callable, enabled: bool = true, card_width: float = 132.0, icon_size: float = 44.0) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_width, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_FORBIDDEN

	var normal_box := StyleBoxFlat.new()
	normal_box.bg_color = BUTTON_NORMAL if enabled else BUTTON_DISABLED
	normal_box.border_color = PANEL_BORDER
	normal_box.border_width_left = 1
	normal_box.border_width_top = 1
	normal_box.border_width_right = 1
	normal_box.border_width_bottom = 1
	normal_box.corner_radius_top_left = 6
	normal_box.corner_radius_top_right = 6
	normal_box.corner_radius_bottom_right = 6
	normal_box.corner_radius_bottom_left = 6
	normal_box.content_margin_left = 6.0
	normal_box.content_margin_right = 6.0
	normal_box.content_margin_top = 6.0
	normal_box.content_margin_bottom = 6.0
	card.add_theme_stylebox_override("panel", normal_box)
	if enabled:
		var hover_box := normal_box.duplicate() as StyleBoxFlat
		hover_box.bg_color = BUTTON_HOVER
		card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover_box))
		card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", normal_box))
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_pressed.call()
		)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)

	if icon_texture:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_texture
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
		# Same EXPAND_IGNORE_SIZE/STRETCH_KEEP_ASPECT_CENTERED fix
		# ResourceBarView's own icons already need — see that class's doc
		# comment for why a bare custom_minimum_size alone isn't enough.
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.5)
		content.add_child(icon_rect)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	style_label(name_label, enabled, not enabled)
	content.add_child(name_label)

	var details_label := Label.new()
	details_label.text = details
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	style_label(details_label, false, true)
	content.add_child(details_label)

	return card

## Shared cost/upkeep formatter (BuildMenuView's own cards and UnitPanelView's
## training/retrain cards all price things the exact same "N Resource, M
## Resource" way) — trims a whole-number float down to a clean integer-
## looking string ("40" not "40.0") while still showing real precision for
## a genuinely fractional value, same reasoning UnitPanelView's own
## _format_upkeep() already applies to building upkeep display.
static func format_resource_dict(costs: Dictionary) -> String:
	var text := ""
	var first := true
	for resource_type in costs:
		if not first:
			text += ", "
		text += "%s %s" % [String.num(float(costs[resource_type]), 1).rstrip("0").rstrip("."), ResourceVisuals.display_name(resource_type)]
		first = false
	return text
