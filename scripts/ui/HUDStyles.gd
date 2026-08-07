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
