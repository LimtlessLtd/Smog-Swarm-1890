class_name SupplyLineSegment
extends Resource

## One edge of the logistics graph — a road, railway or canal link between
## two adjacent hexes (design doc Phase 2.3). Severed segments (zombies
## cutting the line) stop supply from flowing through them without deleting
## the segment itself, so reclaiming/repairing it later (Phase 4.2) just
## flips `is_severed` back off.

@export var line_type: GameEnums.SupplyLineType = GameEnums.SupplyLineType.ROAD
@export var hex_a: Vector2i = Vector2i.ZERO
@export var hex_b: Vector2i = Vector2i.ZERO
@export var is_severed: bool = false

func _init(p_line_type: GameEnums.SupplyLineType = GameEnums.SupplyLineType.ROAD, p_hex_a: Vector2i = Vector2i.ZERO, p_hex_b: Vector2i = Vector2i.ZERO) -> void:
	line_type = p_line_type
	hex_a = p_hex_a
	hex_b = p_hex_b

func connects(coord: Vector2i) -> bool:
	return hex_a == coord or hex_b == coord

func other_end(coord: Vector2i) -> Vector2i:
	return hex_b if hex_a == coord else hex_a
