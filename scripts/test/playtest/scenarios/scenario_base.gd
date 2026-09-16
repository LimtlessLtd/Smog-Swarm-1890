extends RefCounted

## Shared shape for playtest scenarios. A scenario scripts the player's actions
## and turns what happened into experience checks keyed to PLAYER_EXPERIENCE.md's
## acceptance criteria (the `criterion` id, e.g. "HORDE-2").
##
## A check's `status` is "ok" or "concern", never pass/fail: it says whether the
## measurement sits inside the range the criterion describes, which is evidence
## for a reader and not a verdict. Thresholds live next to each check with the
## reason they were chosen, so arguing with one means editing one line.

## Game-seconds per real second at TickManager's default speed (index 1).
const DEFAULT_SPEED: float = 5.0


func days() -> int:
	return 10


## Days (after the day completes) at which a windowed --shots run captures.
## 0 means before the first step.
func checkpoints() -> Array:
	return [0]


func setup(_ctx) -> void:
	pass


func on_step(_ctx, _step: int) -> void:
	pass


func on_day(_ctx, _day: int) -> void:
	pass


func assess(_ctx) -> Array:
	return []


func camera_focus(ctx) -> Vector2:
	return HexCoord.axial_to_world(ctx.start_hex)


## `concern` is true when the measurement is outside what the criterion asks for.
func check(criterion: String, question: String, measured: Variant, concern: bool, reading: String) -> Dictionary:
	return {
		"criterion": criterion,
		"question": question,
		"measured": measured,
		"status": "concern" if concern else "ok",
		"reading": reading,
	}


## Game-seconds rendered as real minutes at the default game speed, which is
## what a player sitting at the default speed actually waits.
static func real_minutes(game_seconds: float) -> float:
	return snappedf(game_seconds / DEFAULT_SPEED / 60.0, 0.1)
