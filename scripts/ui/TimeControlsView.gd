class_name TimeControlsView
extends HBoxContainer

## Top-right HUD strip (design doc Phase 6.1): the 0x/5x/20x/50x/100x/1000x
## speed buttons. Pure UI over TickManager (an autoload, globally accessible
## — no NodePath needed) with no simulation logic of its own.
##
## **Date + Day/Night phase countdown moved OUT to `DayPhaseView` (user
## request, playtest round 5: "messages at the top of the screen overlap on
## the date and day/night countdown... move [them] to the bottom right...
## above where the minimap is")** — this view used to show both; the date/
## countdown reading now lives bottom-right instead, next to nothing else
## that could overlap it. This view keeps only the speed buttons, in their
## existing top-right spot, and is correspondingly narrower than before.

const SPEED_LABELS: Array[String] = ["0x", "5x", "20x", "50x", "100x", "1000x"]  ## Must stay index-parallel with TickManager.SPEED_MULTIPLIERS.

var _speed_buttons: Array[Button] = []

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	HUDStyles.style_panel(self)

	for i in range(SPEED_LABELS.size()):
		var button := Button.new()
		button.text = SPEED_LABELS[i]
		button.toggle_mode = true
		button.pressed.connect(_on_speed_button_pressed.bind(i))
		HUDStyles.style_button(button)
		add_child(button)
		_speed_buttons.append(button)

	TickManager.speed_changed.connect(_on_speed_changed)
	_refresh_speed_buttons(TickManager.speed_index)

func _on_speed_button_pressed(index: int) -> void:
	TickManager.set_speed_index(index)

func _on_speed_changed(_multiplier: float) -> void:
	_refresh_speed_buttons(TickManager.speed_index)

## Setting `button_pressed` directly (rather than via user interaction)
## deliberately does NOT re-fire the `pressed` signal we connected above, so
## this can't recurse into _on_speed_button_pressed().
func _refresh_speed_buttons(active_index: int) -> void:
	for i in range(_speed_buttons.size()):
		_speed_buttons[i].button_pressed = (i == active_index)
