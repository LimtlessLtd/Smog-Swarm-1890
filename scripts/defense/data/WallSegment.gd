class_name WallSegment
extends Resource

## One placed wall piece: a short (<=WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS,
## "no longer than 100 meters MAXIMUM" (user spec)) independently-HP'd chunk
## of a player-drawn defensive line — the chokepoint-defense equivalent of
## SupplyLineSegment.
##
## Chain-of-pieces model: "[walls] are not free hand to place/draw, and a
## wall segment is ~5 miles long, so that when a zombie... destroys it, the
## ENTIRE 5 mile full length of wall is destroyed" (user report) — matches
## *They Are Billions*, where a wall is a chain of small discrete pieces,
## each with its own HP, destroyed one piece at a time with no cascade.
## `point_a`/`point_b` (real world-space endpoints, freehand, not
## hex-edge-snapped) are this piece's actual placement geometry;
## `hex_a`/`hex_b` survive as a spatial-index/ZoC-classification convenience
## (which hex each endpoint falls in — WallManager.get_segments_at()/
## is_legacy_segment()'s own lookups), not a claim that this piece runs
## along that hex pair's shared edge. WallManager.place_wall_line() chops a
## drawn line into pieces this size; this class doesn't track which drawn
## run it belongs to.
##
## Unlike BuildingInstance (which needs a separate save-entry class to
## avoid saving a live BuildingDefinition reference), this Resource is
## saved directly — tier is an int looked up against WallCatalog on demand,
## nothing here references another live Resource.

@export var hex_a: Vector2i = Vector2i.ZERO
@export var hex_b: Vector2i = Vector2i.ZERO
@export var point_a: Vector2 = Vector2.ZERO  ## World-space start of this piece's line — see class doc comment.
@export var point_b: Vector2 = Vector2.ZERO  ## World-space end of this piece's line.
@export var tier: int = WallCatalog.WOODEN
@export var current_hp: float = 0.0
@export var has_ditch: bool = false    ## A Ditch stacks with the segment rather than replacing it.
@export var has_oil_pit: bool = false  ## Same for an Oil Pit.
## A Gate is the same segment at the same tier, blocks/sieges a horde
## exactly like a solid wall (WallManager.damage_segment() doesn't
## distinguish it) — the only difference is get_max_hp() below applying
## WallCatalog.GATE_HP_FRACTION. Not a separate tier or building type: same
## cost, same upgrade/repair path, just intrinsically weaker at whatever
## tier it is.
@export var is_gate: bool = false
@export var id: int = 0

func _init(p_hex_a: Vector2i = Vector2i.ZERO, p_hex_b: Vector2i = Vector2i.ZERO, p_point_a: Vector2 = Vector2.ZERO, p_point_b: Vector2 = Vector2.ZERO, p_tier: int = WallCatalog.WOODEN, p_id: int = 0, p_current_hp: float = -1.0, p_is_gate: bool = false) -> void:
	hex_a = p_hex_a
	hex_b = p_hex_b
	point_a = p_point_a
	point_b = p_point_b
	tier = p_tier
	id = p_id
	is_gate = p_is_gate
	# -1.0 is "not specified" (a fresh placement) — seed at the tier's full
	# health (get_max_hp() below, not WallCatalog.get_max_hp() directly, so a
	# fresh Gate correctly seeds at its own reduced max). A save-restore path
	# passes the actual saved value instead.
	current_hp = p_current_hp if p_current_hp >= 0.0 else get_max_hp()

func get_max_hp() -> float:
	var base := WallCatalog.get_max_hp(tier)
	return base * WallCatalog.GATE_HP_FRACTION if is_gate else base

func connects(coord: Vector2i) -> bool:
	return hex_a == coord or hex_b == coord

func other_end(coord: Vector2i) -> Vector2i:
	return hex_b if hex_a == coord else hex_a

## 0 HP is the point a horde has physically broken through — no wall is
## unbreachable.
func is_breached() -> bool:
	return current_hp <= 0.0
