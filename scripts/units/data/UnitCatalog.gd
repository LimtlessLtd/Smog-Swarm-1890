class_name UnitCatalog
extends RefCounted

## Static seed data for the design doc's decided 18-unit roster (Phase 5.4)
## — plays the same "single source of truth, built lazily and cached" role
## for units that BuildingCatalog plays for buildings, kept separate from
## UnitManager (the runtime system that trains/tracks instances).
##
## get_definition() is expected to be called on every training attempt (and
## by CombatEngine on every attack resolution), so definitions are built
## lazily and cached rather than rebuilt each call — same reasoning as
## BuildingCatalog.

static var _definitions_by_type: Dictionary = {}  # GameEnums.UnitType -> UnitDefinition

static func get_definition(unit_type: GameEnums.UnitType) -> UnitDefinition:
	_ensure_built()
	return _definitions_by_type.get(unit_type)

static func get_all_definitions() -> Array[UnitDefinition]:
	_ensure_built()
	var result: Array[UnitDefinition] = []
	result.assign(_definitions_by_type.values())
	return result

static func get_definitions_in_tier(tier: int) -> Array[UnitDefinition]:
	_ensure_built()
	var result: Array[UnitDefinition] = []
	for definition: UnitDefinition in _definitions_by_type.values():
		if definition.tier == tier:
			result.append(definition)
	return result

static func _ensure_built() -> void:
	if not _definitions_by_type.is_empty():
		return
	for definition in _build_definitions():
		_definitions_by_type[definition.unit_type] = definition

static func _build_definitions() -> Array[UnitDefinition]:
	return [
		# --- Tier 0 ("Free Ammo" — no tech needed) ---
		_unit(GameEnums.UnitType.TRUNCHEONEER, "Truncheoneer", 0, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.TOXOPHILITE, "Toxophilite", 0, GameEnums.UnitRole.RANGED),  # No Gunpowder upkeep by design — arrows aren't a tracked resource.
		# Outrider: unarmed mounted scout (user request) — damage_multiplier 0.0
		# means attack_damage works out to exactly 0.0 regardless of the tier
		# curve underneath, not a small residual number; it genuinely cannot
		# fight. move_speed_multiplier 1.6 is the payoff — fast reconnaissance,
		# not combat, same "does something special" framing every SPECIAL unit
		# below gets.
		_unit(GameEnums.UnitType.OUTRIDER, "Outrider", 0, GameEnums.UnitRole.SPECIAL, false, GameEnums.UnitAbility.UNARMED_SCOUT, 1.0, 0.0, 1.6),
		# --- Tier 1 (unit_tier_1) ---
		_unit(GameEnums.UnitType.NAVVY, "Navvy", 1, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.YEOMAN_MARKSMAN, "Yeoman Marksman", 1, GameEnums.UnitRole.RANGED, true),  # First firearm-era ranged unit — Gunpowder depletion penalty starts here.
		# Grenadier: grenades (user request) — a horde is already one
		# clustered "blob" target in this game's combat model (Horde.gd),
		# so there's no separate multi-target AOE to build; splash
		# effectiveness against a mob is expressed as a straight damage
		# bonus instead.
		_unit(GameEnums.UnitType.GRENADIER, "Grenadier", 1, GameEnums.UnitRole.SPECIAL, false, GameEnums.UnitAbility.EXPLOSIVE_SPLASH, 1.0, 1.5, 1.0),
		# --- Tier 2 (unit_tier_2) ---
		_unit(GameEnums.UnitType.REDCOAT, "Redcoat", 2, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.RIFLEMAN, "Rifleman", 2, GameEnums.UnitRole.RANGED, true),
		# Chasseur: mounted AND armed with a firearm (user request) — a real
		# damage_multiplier (not the Outrider's 0.0) makes it a genuine
		# combat option, strictly better/more useful than the Outrider it
		# shares a tier-progression role with, while keeping the same fast
		# move_speed_multiplier the "mounted" half of its identity implies.
		# Deliberately still exempt from requires_gunpowder, same as every
		# other SPECIAL-role unit (UnitDefinition.requires_gunpowder's own
		# doc comment: the depletion penalty is scoped to RANGED units by
		# design, not "every unit that logically uses a firearm") — not
		# re-litigating that standing decision just because this unit is
		# now explicitly armed.
		_unit(GameEnums.UnitType.CHASSEUR, "Chasseur", 2, GameEnums.UnitRole.SPECIAL, false, GameEnums.UnitAbility.MOUNTED_FIREARM, 1.0, 1.3, 1.4),
		# --- Tier 3 (unit_tier_3) ---
		_unit(GameEnums.UnitType.HIGHLANDER, "Highlander", 3, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.SHARPSHOOTER, "Sharpshooter", 3, GameEnums.UnitRole.RANGED, true),
		# Dragoon: a mounted charge (user request) — knocks a horde back a hex
		# and stuns it briefly on contact (CombatCoordinator, not a stat on
		# this Resource at all); attack_damage stays at the plain baseline
		# curve since the charge itself, not raw damage, is this unit's real
		# value. Still mounted (move_speed_multiplier), same as Outrider/Chasseur.
		_unit(GameEnums.UnitType.DRAGOON, "Dragoon", 3, GameEnums.UnitRole.SPECIAL, false, GameEnums.UnitAbility.CHARGE_KNOCKBACK, 1.0, 1.0, 1.3),
		# --- Tier 4 (unit_tier_4) — grounded heavy engineering, not battle-mechs (design doc, decided). ---
		_unit(GameEnums.UnitType.STEAM_PRAM_RAMMER, "Steam-Pram Rammer", 4, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.ARMORED_LOCOMOTIVE_GUNNER, "Armored Locomotive Gunner", 4, GameEnums.UnitRole.RANGED, true),
		# Steam-Tractor Landship: a big bulky tank (user request) — 2.5x the
		# baseline HP curve ("take significant amounts of damage before
		# dying"), plus the same knockback a Dragoon's charge applies
		# (CombatCoordinator) but with NO stun — this is a slow damage sponge
		# that shoves zombies aside on every contact, not a fast shock unit.
		_unit(GameEnums.UnitType.STEAM_TRACTOR_LANDSHIP, "Steam-Tractor Landship", 4, GameEnums.UnitRole.SPECIAL, false, GameEnums.UnitAbility.TRAMPLE_KNOCKBACK, 2.5, 1.0, 1.0),
		# --- Tier 5 (unit_tier_5) — same "no retro-futuristic steampunk tropes" rule as Tier 4. ---
		_unit(GameEnums.UnitType.STEAM_MACHINE_LEG, "Steam Machine-Leg", 5, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.RAILWAY_SIEGE_HOWITZER, "Railway Siege Howitzer", 5, GameEnums.UnitRole.RANGED, true),
		# War Machine Armored Car: a mobile ammo supply dump (user request) —
		# projects its own small Military ZoC/resupply aura wherever it
		# currently stands (LogisticsNetwork.recompute(), radius 0 vs. a
		# Forward Ammo Dump building's radius 1 — "much reduced" per the
		# request). 1.3x HP keeps it "a decent chunk of health like the
		# others," explicitly not the fragile pure-support framing its old
		# flavor text implied.
		_unit(GameEnums.UnitType.WAR_MACHINE_ARMORED_CAR, "War Machine Armored Car", 5, GameEnums.UnitRole.SPECIAL, false, GameEnums.UnitAbility.MOBILE_SUPPLY_DUMP, 1.3, 1.0, 1.0),
	]

## Shared placeholder balancing curve — one formula for training cost/
## upkeep/HP/damage across all 18 units instead of 18 hand-picked numbers.
## Real per-unit tuning is exactly the "balancing pass, not an architecture
## decision" every other constant table in this project already disclaims
## (see e.g. WallCatalog, BuildingManager's starvation constants); this just
## makes the eventual retuning a one-function edit instead of an
## eighteen-function one. Deliberately avoids ResourceType.REINFORCED_CONCRETE
## — no building anywhere in the project produces it yet (see that enum
## entry's own comment), so requiring it here would make Tier 4-5 units
## uncraftable rather than merely expensive.
##
## `ability`/`hp_multiplier`/`damage_multiplier`/`move_speed_multiplier`
## (user request, this pass — "each special unit type should do something
## special") apply ON TOP of the shared curve/role multiplier below, not
## instead of it — every SPECIAL unit still starts from the same tier
## baseline every other unit does, these four just let six specific units
## (see their own call sites' comments) diverge from what used to be an
## identical, undifferentiated SPECIAL-role baseline. Every MELEE/RANGED
## unit and any not-yet-differentiated SPECIAL unit passes none of these,
## leaving all four at their neutral default (NONE/1.0/1.0/1.0) — this
## helper's signature grew, but every pre-existing call site above still
## reads exactly as it did before this pass.
static func _unit(type: GameEnums.UnitType, display_name: String, tier: int, role: GameEnums.UnitRole, requires_gunpowder: bool = false, ability: GameEnums.UnitAbility = GameEnums.UnitAbility.NONE, hp_multiplier: float = 1.0, damage_multiplier: float = 1.0, move_speed_multiplier: float = 1.0) -> UnitDefinition:
	var d := UnitDefinition.new(type, display_name, tier, role)
	d.requires_gunpowder = requires_gunpowder
	if requires_gunpowder:
		d.daily_upkeep = {GameEnums.ResourceType.GUNPOWDER: 0.5 + tier * 0.5}

	d.training_cost = {
		GameEnums.ResourceType.CAST_IRON: 15 + tier * 25,
		GameEnums.ResourceType.BRICKS: 10 * tier,
	}
	d.max_hp = 20.0 + tier * 15.0
	d.attack_damage = 3.0 + tier * 2.0
	match role:
		GameEnums.UnitRole.MELEE:
			d.max_hp *= 1.2      # Tankier — has to close to melee range to do anything.
		GameEnums.UnitRole.RANGED:
			d.max_hp *= 0.9      # Fragile — the Gunpowder-depletion "unarmored melee mode" penalty (UnitDefinition.requires_gunpowder) hits this role hardest.
			d.attack_damage *= 1.3
		GameEnums.UnitRole.SPECIAL:
			pass  # Baseline before the four per-unit overrides below apply — no role-wide multiplier of its own, unlike MELEE/RANGED.

	d.ability = ability
	d.move_speed_multiplier = move_speed_multiplier
	d.max_hp *= hp_multiplier
	d.attack_damage *= damage_multiplier
	return d
