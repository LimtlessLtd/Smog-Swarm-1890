class_name SupplyLineSegment
extends Resource

## One edge of the logistics graph — a road, railway, canal, or bridge link
## between two adjacent hexes. Severed segments (zombies
## cutting the line) stop supply from flowing through them without deleting
## the segment itself, so reclaiming/repairing it later just
## flips `is_severed` back off.
##
## `tier` is an int looked up against SupplyLineCatalog on demand (same
## "index, not the resource itself" convention WallSegment.tier already
## uses against WallCatalog) — ROAD/BRIDGE both have multiple tiers,
## RAILWAY/CANAL are single-tier (SupplyLineCatalog.get_max_tier() returns
## 0 for both, so tier just stays 0 for the life of that segment).

@export var line_type: GameEnums.SupplyLineType = GameEnums.SupplyLineType.ROAD
@export var tier: int = 0
@export var hex_a: Vector2i = Vector2i.ZERO
@export var hex_b: Vector2i = Vector2i.ZERO
@export var is_severed: bool = false

func _init(p_line_type: GameEnums.SupplyLineType = GameEnums.SupplyLineType.ROAD, p_hex_a: Vector2i = Vector2i.ZERO, p_hex_b: Vector2i = Vector2i.ZERO, p_tier: int = 0) -> void:
	line_type = p_line_type
	hex_a = p_hex_a
	hex_b = p_hex_b
	tier = p_tier

func connects(coord: Vector2i) -> bool:
	return hex_a == coord or hex_b == coord

func other_end(coord: Vector2i) -> Vector2i:
	return hex_b if hex_a == coord else hex_a
