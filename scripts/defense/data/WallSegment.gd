class_name WallSegment
extends Resource

## One placed wall segment defending the shared edge between two adjacent
## hexes (design doc Phase 4.1) — the chokepoint-defense equivalent of
## SupplyLineSegment, deliberately shaped the same way (hex_a/hex_b +
## connects()/other_end()) rather than a raw freeform world-space line:
## pixel-precise snapping across a geographic bottleneck (riverbanks, cliff
## passes) is a placement-UI concern for a future BuildPlacementController-
## style flow (Phase 6+), not this data class's job — it only needs to know
## which two hexes' shared edge it defends.
##
## **Decided (design doc):** each segment is its own instance with its own
## health pool, scaling with tier — never a monolithic per-wall or
## per-district abstraction. Unlike BuildingInstance (which needs a separate
## save-entry class to avoid saving a live BuildingDefinition reference),
## this Resource is saved directly — tier is just an int looked up against
## WallCatalog on demand, nothing here references another live Resource.

@export var hex_a: Vector2i = Vector2i.ZERO
@export var hex_b: Vector2i = Vector2i.ZERO
@export var tier: int = WallCatalog.WOODEN
@export var current_hp: float = 0.0
@export var has_ditch: bool = false    ## Design doc 4.1: a Ditch stacks with the segment rather than replacing it.
@export var has_oil_pit: bool = false  ## Same for an Oil Pit.
@export var id: int = 0

func _init(p_hex_a: Vector2i = Vector2i.ZERO, p_hex_b: Vector2i = Vector2i.ZERO, p_tier: int = WallCatalog.WOODEN, p_id: int = 0, p_current_hp: float = -1.0) -> void:
	hex_a = p_hex_a
	hex_b = p_hex_b
	tier = p_tier
	id = p_id
	# -1.0 is "not specified" (a fresh placement) — seed at the tier's full
	# health. A save-restore path passes the actual saved value instead.
	current_hp = p_current_hp if p_current_hp >= 0.0 else WallCatalog.get_max_hp(p_tier)

func get_max_hp() -> float:
	return WallCatalog.get_max_hp(tier)

func connects(coord: Vector2i) -> bool:
	return hex_a == coord or hex_b == coord

func other_end(coord: Vector2i) -> Vector2i:
	return hex_b if hex_a == coord else hex_a

## Design doc: "walls are never literally unbreachable" — 0 HP is the point
## a horde has physically broken through. Phase 5.10's siege AI and Phase
## 4.2's defense-in-depth cascade both key off this once they exist.
func is_breached() -> bool:
	return current_hp <= 0.0
