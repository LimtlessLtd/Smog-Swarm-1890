class_name ZoneOfControlState
extends Resource

## Computed (not authored) per-hex snapshot of Zone of Control coverage —
## rebuilt from scratch by LogisticsNetwork.recompute() whenever buildings or
## supply lines change. `military_coverage` is a 0..1 fraction of the hex's
## area (aura covers 66% of a tile); `has_civilian_coverage` is a
## flat bool since Civilian ZoC always covers the entire hex once granted.

@export var coord: Vector2i = Vector2i.ZERO
@export var military_coverage: float = 0.0
@export var has_civilian_coverage: bool = false

func _init(p_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = p_coord

func has_military_coverage() -> bool:
	return military_coverage > 0.0
