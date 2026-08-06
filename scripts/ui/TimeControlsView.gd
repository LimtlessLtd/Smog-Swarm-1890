class_name TimeControlsView
extends HBoxContainer

## Top-right HUD strip (design doc Phase 6.1): day counter + 0x/1x/2x/3x/5x
## speed buttons. Pure UI over TickManager (autoload, globally accessible —
## no NodePath needed) with no simulation logic of its own.

const SPEED_LABELS: Array[String] = ["0x", "1x", "2x", "3x", "5x"]

var _day_label: Label
var _speed_buttons: Array[Button] = []

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_day_label = Label.new()
	add_child(_day_label)

	for i in range(SPEED_LABELS.size()):
		var button := Button.new()
		button.text = SPEED_LABELS[i]
		button.toggle_mode = true
		button.pressed.connect(_on_speed_button_pressed.bind(i))
		add_child(button)
		_speed_buttons.append(button)

	TickManager.day_completed.connect(_on_day_completed)
	TickManager.speed_changed.connect(_on_speed_changed)
	_on_day_completed(TickManager.current_day)
	_refresh_speed_buttons(TickManager.speed_index)

func _on_speed_button_pressed(index: int) -> void:
	TickManager.set_speed_index(index)

func _on_day_completed(day_number: int) -> void:
	_day_label.text = "Day %d" % day_number

func _on_speed_changed(_multiplier: float) -> void:
	_refresh_speed_buttons(TickManager.speed_index)

## Setting `button_pressed` directly (rather than via user interaction)
## deliberately does NOT re-fire the `pressed` signal we connected above, so
## this can't recurse into _on_speed_button_pressed().
func _refresh_speed_buttons(active_index: int) -> void:
	for i in range(_speed_buttons.size()):
		_speed_buttons[i].button_pressed = (i == active_index)
