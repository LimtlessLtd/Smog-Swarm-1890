class_name SiegeForecast
extends RefCounted

## Projects a siege forward with the rules that run it: HordeManager's
## contact-limited wall damage and WallDefenseController's volleys. Pure and cheap
## (at most a few thousand one-second steps), so a view can ask it every frame what
## happens if nothing changes, and a debrief can ask what would have happened with a
## different number of defenders.
##
## It is a projection, not the simulation: it holds the defender count and night
## fixed and ignores a horde that re-targets. That is what makes it readable — "at
## this rate the wall falls first" — and why nothing in the game reads it.

const STEP_SECONDS: float = 1.0
const MAX_SECONDS: float = 7200.0


## Game-seconds until the wall piece falls or the horde is gone.
## Returns {"outcome": &"breach" | &"destroyed" | &"undecided", "seconds": float,
## "horde_left": int, "hp_left": float}.
static func project(horde_size: int, segment_hp: float, defenders: int, kills_per_strike: int, is_night: bool) -> Dictionary:
	var size := horde_size
	var hp := segment_hp
	var night := HordeManager.NIGHT_AGGRESSION_MULTIPLIER if is_night else 1.0
	var t := 0.0
	var next_volley := WallDefenseController.VOLLEY_INTERVAL_SECONDS
	while t < MAX_SECONDS:
		if size <= 0:
			return {"outcome": &"destroyed", "seconds": t, "horde_left": 0, "hp_left": hp}
		if hp <= 0.0:
			return {"outcome": &"breach", "seconds": t, "horde_left": size, "hp_left": 0.0}
		hp -= float(HordeManager.wall_contact_frontage(size)) * HordeManager.WALL_DAMAGE_PER_CONTACT_ZOMBIE * HordeManager.WALL_SIEGE_DAMAGE_MULTIPLIER * night * STEP_SECONDS / HordeManager.LOGIC_TICK_SECONDS
		t += STEP_SECONDS
		if t >= next_volley:
			next_volley += WallDefenseController.VOLLEY_INTERVAL_SECONDS
			size -= defenders * kills_per_strike
	return {"outcome": &"undecided", "seconds": t, "horde_left": size, "hp_left": hp}


## Zombies one strike from cover by `definition` removes: CombatEngine takes the
## unit's damage off the horde's HP and Horde.apply_remaining_hp() floors the
## headcount, so a strike removes ceil(damage / HP_PER_ZOMBIE). The day bonus is
## applied because it is part of every real strike; morale and research are not,
## which makes this an estimate for a fresh, unresearched unit.
static func kills_per_strike(definition: UnitDefinition, is_day: bool) -> int:
	var damage := definition.attack_damage * (CombatCoordinator.DAY_DAMAGE_MULTIPLIER if is_day else 1.0)
	return maxi(0, int(ceil(damage / Horde.HP_PER_ZOMBIE - 0.0001)))
