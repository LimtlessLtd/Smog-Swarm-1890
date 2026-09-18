class_name DayNightWorldLighting
extends Node

## Tints WorldRoot only. HUD controls live outside that subtree, so the phase is
## visible in the terrain, units and structures without making interface text dim.

const DAY_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const NIGHT_COLOR := Color(0.26, 0.32, 0.48, 1.0)

@export var world_root_path: NodePath = NodePath("..")

var _world_root: CanvasItem

func _ready() -> void:
	_world_root = get_node_or_null(world_root_path) as CanvasItem
	TimeCycleManager.phase_changed.connect(_on_phase_changed)
	apply_phase(TimeCycleManager.get_current_phase())

func _on_phase_changed(phase: GameEnums.DayPhase) -> void:
	apply_phase(phase)

func apply_phase(phase: GameEnums.DayPhase) -> void:
	if _world_root:
		_world_root.modulate = color_for_phase(phase)

static func color_for_phase(phase: GameEnums.DayPhase) -> Color:
	return NIGHT_COLOR if phase == GameEnums.DayPhase.NIGHT else DAY_COLOR
