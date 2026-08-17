class_name BuildingIconButton
extends PanelContainer

## 60x60 icon-only clickable button for BuildMenuView's building/wall/
## infrastructure grid — replaces the always-expanded text block
## HUDStyles.build_card() drew inline, per user feedback ("should just show
## the icon of the building, and then when you mouse over each building, it
## should show a tooltip that displays all the information"). Owns its own
## rich BBCode tooltip via Control._make_custom_tooltip() (Godot's own hook
## for swapping in a custom Control instead of the default plain-text
## tooltip box) rather than laying details out as visible child Labels.
## `tooltip_builder` is a Callable invoked fresh every time the tooltip is
## about to show — resource affordability (red-highlighted per BuildMenuView's
## own cost formatter) always reflects CURRENT ResourceManager state this
## way, not a string baked in once when the grid was built.
##
## `enabled=false` (a building whose research prerequisite isn't met) dims
## the icon, swaps the cursor to CURSOR_FORBIDDEN, and swallows clicks — same
## "still visible, still hoverable, just unclickable" contract
## HUDStyles.build_card() established, not removed from the grid entirely
## (the tooltip is what a locked icon needs most: it's the only way to see
## what it costs/does before the prerequisite is even researched).

const SIZE: float = 60.0

var _tooltip_builder: Callable

func setup(icon_texture: Texture2D, enabled: bool, category_colors: Dictionary, on_pressed: Callable, tooltip_builder: Callable) -> void:
	_tooltip_builder = tooltip_builder
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_FORBIDDEN
	tooltip_text = " "  # Non-empty so Godot's tooltip system engages at all — _make_custom_tooltip() below replaces the actual displayed content.

	var fill: Color = category_colors.get("fill", HUDStyles.BUTTON_NORMAL)
	var hover_fill: Color = category_colors.get("hover_fill", HUDStyles.BUTTON_HOVER)
	var border: Color = category_colors.get("border", HUDStyles.PANEL_BORDER)

	var normal_box := StyleBoxFlat.new()
	normal_box.bg_color = fill if enabled else HUDStyles.BUTTON_DISABLED
	normal_box.border_color = border if enabled else Color("#67553b")
	normal_box.border_width_left = 1
	normal_box.border_width_top = 1
	normal_box.border_width_right = 1
	normal_box.border_width_bottom = 1
	normal_box.corner_radius_top_left = 6
	normal_box.corner_radius_top_right = 6
	normal_box.corner_radius_bottom_right = 6
	normal_box.corner_radius_bottom_left = 6
	normal_box.content_margin_left = 2.0
	normal_box.content_margin_right = 2.0
	normal_box.content_margin_top = 2.0
	normal_box.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", normal_box)

	if enabled:
		var hover_box := normal_box.duplicate() as StyleBoxFlat
		hover_box.bg_color = hover_fill
		mouse_entered.connect(func() -> void: add_theme_stylebox_override("panel", hover_box))
		mouse_exited.connect(func() -> void: add_theme_stylebox_override("panel", normal_box))
		gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				on_pressed.call()
		)

	if icon_texture:
		var icon_rect := TextureRect.new()
		# Tight-cropped to the model's own visible silhouette, not the source
		# render's full (padded-for-composition) canvas — "auto size to take
		# up all the available space within the box" (user request). See
		# TextureCropUtil's own doc comment for why a plain aspect-fit of the
		# UNCROPPED texture wasn't already doing this.
		icon_rect.texture = TextureCropUtil.tight_crop(icon_texture)
		# Same EXPAND_IGNORE_SIZE/STRETCH_KEEP_ASPECT_CENTERED fix
		# ResourceBarView's/HUDStyles.build_card()'s own icons need — source
		# art resolution shouldn't dictate the on-screen 60x60 footprint.
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## Clicks/hover go to this PanelContainer, not the icon texture on top of it.
		icon_rect.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.5)
		add_child(icon_rect)

func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := PanelContainer.new()
	HUDStyles.style_panel(panel)
	panel.custom_minimum_size.x = 260.0

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size.x = 244.0
	label.add_theme_color_override("default_color", HUDStyles.TEXT_COLOR)
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_font_size_override("bold_font_size", 15)
	label.text = _tooltip_builder.call()
	panel.add_child(label)
	return panel
