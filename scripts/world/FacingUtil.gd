class_name FacingUtil
extends RefCounted

## Pure math: world-space movement delta -> GameEnums.Facing8 bucket, and
## Facing8 -> the tools/blender_pipeline render_common.DIRECTIONS_8 filename
## suffix ("n".."nw"). Stateless by design so TacticalEntityLayer's
## per-unit facing tracking and its per-horde zombie facing tracking share
## one bucketing rule instead of two subtly different implementations.
##
## The bucket-to-screen-direction mapping is now exact rather than a guess:
## the camera applies no rotation or scale to the world (the isometric mode
## was removed 2026-09-15), so world-space "+X" IS screen-right, and the art
## is rendered by spinning the camera in-plane about a model built facing +Y
## (render_common.render_directional_to's base yaw of 0 for straight-down
## categories). Reasoned
## placeholder (standard 8-way atan2 split in world space, N first,
## clockwise, matching Facing8's own declared order) rather than a
## blocker — revisit once directional art actually exists to look at
## in-game.

const COUNT := 8

## Filenames render_common.DIRECTIONS_8 actually writes, indexed by
## GameEnums.Facing8's ordinal — kept in sync by hand since one list is
## GDScript and the other Python; no shared constant is possible across
## that boundary.
const SUFFIXES := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

static func suffix(facing: GameEnums.Facing8) -> String:
	return SUFFIXES[facing]

## `delta` is assumed non-negligible — callers gate on a minimum-movement
## threshold before calling this (see
## TacticalEntityLayer.MIN_FACING_MOVE_DISTANCE) so a stationary entity's
## floating-point-noise-level delta never reaches here and flickers facing.
static func from_delta(delta: Vector2) -> GameEnums.Facing8:
	# atan2(x, -y): 0 at north (-Y, "up" on screen), increasing clockwise —
	# lands exactly on Facing8's declared N/NE/E/SE/S/SW/W/NW order once
	# divided into 8 equal buckets, so the enum ordinal IS the bucket index.
	var angle_from_north := atan2(delta.x, -delta.y)
	var normalized := fposmod(angle_from_north, TAU)
	var index := int(round(normalized / (TAU / COUNT))) % COUNT
	return index as GameEnums.Facing8
