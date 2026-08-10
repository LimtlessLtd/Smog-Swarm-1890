class_name WallSegment
extends Resource

## One placed wall PIECE — a short (<=WallCatalog.MAX_SEGMENT_LENGTH_WORLD_UNITS,
## player spec: "no longer than 100 meters MAXIMUM") independently-HP'd
## chunk of a player-drawn defensive line, the chokepoint-defense
## equivalent of SupplyLineSegment.
##
## **Reworked (player report: walls "are not free hand to place/draw, and
## a wall segment is ~5 miles long, so that when a zombie... destroys it,
## the ENTIRE 5 mile full length of wall is destroyed" — confirmed against
## real *They Are Billions* mechanics, not invented: a wall there is a
## chain of small discrete pieces, each with its own HP, destroyed one
## piece at a time with zero cascade). `point_a`/`point_b` (real
## world-space endpoints — genuinely freehand, not hex-edge-snapped) are
## now this piece's actual placement geometry; `hex_a`/`hex_b` survive as
## a spatial-index/ZoC-classification convenience (which hex each endpoint
## falls in — WallManager.get_segments_at()/is_legacy_segment()'s own
## lookups), not a claim that this piece runs exactly along that hex pair's
## shared edge the way it used to. `WallManager.place_wall_line()` is what
## actually chops a drawn line into pieces this size; this class itself
## doesn't know or care that it's one piece of a longer drawn run — same
## "each segment is its own instance with its own health pool, never a
## monolithic per-wall abstraction" decision the design doc always made,
## just at a genuinely small scale now instead of a whole hex edge.
##
## Unlike BuildingInstance (which needs a separate save-entry class to
## avoid saving a live BuildingDefinition reference), this Resource is
## saved directly — tier is just an int looked up against WallCatalog on
## demand, nothing here references another live Resource.

@export var hex_a: Vector2i = Vector2i.ZERO
@export var hex_b: Vector2i = Vector2i.ZERO
@export var point_a: Vector2 = Vector2.ZERO  ## Real world-space start of this piece's own line — see class doc comment.
@export var point_b: Vector2 = Vector2.ZERO  ## Real world-space end of this piece's own line.
@export var tier: int = WallCatalog.WOODEN
@export var current_hp: float = 0.0
@export var has_ditch: bool = false    ## Design doc 4.1: a Ditch stacks with the segment rather than replacing it.
@export var has_oil_pit: bool = false  ## Same for an Oil Pit.
## Economy/start-of-game pass (user request): a Gate is the same segment at
## the same tier, still blocks/sieges a horde exactly like a solid wall
## (WallManager.damage_segment() doesn't distinguish it at all) — the only
## difference is get_max_hp() below applying WallCatalog.GATE_HP_FRACTION,
## the traditional "a gate is the weak point of a fortification" trade-off.
## Deliberately NOT a separate tier or building type: same cost, same
## upgrade/repair path, just intrinsically weaker at whatever tier it is.
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

## Design doc: "walls are never literally unbreachable" — 0 HP is the point
## a horde has physically broken through. Phase 5.10's siege AI and Phase
## 4.2's defense-in-depth cascade both key off this once they exist.
func is_breached() -> bool:
	return current_hp <= 0.0
