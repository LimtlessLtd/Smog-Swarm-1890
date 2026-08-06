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
		_unit(GameEnums.UnitType.OUTRIDER, "Outrider", 0, GameEnums.UnitRole.SPECIAL),
		# --- Tier 1 (unit_tier_1) ---
		_unit(GameEnums.UnitType.NAVVY, "Navvy", 1, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.YEOMAN_MARKSMAN, "Yeoman Marksman", 1, GameEnums.UnitRole.RANGED, true),  # First firearm-era ranged unit — Gunpowder depletion penalty starts here.
		_unit(GameEnums.UnitType.GRENADIER, "Grenadier", 1, GameEnums.UnitRole.SPECIAL),
		# --- Tier 2 (unit_tier_2) ---
		_unit(GameEnums.UnitType.REDCOAT, "Redcoat", 2, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.RIFLEMAN, "Rifleman", 2, GameEnums.UnitRole.RANGED, true),
		_unit(GameEnums.UnitType.CHASSEUR, "Chasseur", 2, GameEnums.UnitRole.SPECIAL),
		# --- Tier 3 (unit_tier_3) ---
		_unit(GameEnums.UnitType.HIGHLANDER, "Highlander", 3, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.SHARPSHOOTER, "Sharpshooter", 3, GameEnums.UnitRole.RANGED, true),
		_unit(GameEnums.UnitType.DRAGOON, "Dragoon", 3, GameEnums.UnitRole.SPECIAL),
		# --- Tier 4 (unit_tier_4) — grounded heavy engineering, not battle-mechs (design doc, decided). ---
		_unit(GameEnums.UnitType.STEAM_PRAM_RAMMER, "Steam-Pram Rammer", 4, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.ARMORED_LOCOMOTIVE_GUNNER, "Armored Locomotive Gunner", 4, GameEnums.UnitRole.RANGED, true),
		_unit(GameEnums.UnitType.STEAM_TRACTOR_LANDSHIP, "Steam-Tractor Landship", 4, GameEnums.UnitRole.SPECIAL),
		# --- Tier 5 (unit_tier_5) — same "no retro-futuristic steampunk tropes" rule as Tier 4. ---
		_unit(GameEnums.UnitType.STEAM_MACHINE_LEG, "Steam Machine-Leg", 5, GameEnums.UnitRole.MELEE),
		_unit(GameEnums.UnitType.RAILWAY_SIEGE_HOWITZER, "Railway Siege Howitzer", 5, GameEnums.UnitRole.RANGED, true),
		_unit(GameEnums.UnitType.WAR_MACHINE_ARMORED_CAR, "War Machine Armored Car", 5, GameEnums.UnitRole.SPECIAL),
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
static func _unit(type: GameEnums.UnitType, display_name: String, tier: int, role: GameEnums.UnitRole, requires_gunpowder: bool = false) -> UnitDefinition:
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
			pass  # Left at baseline — "exact combat identity ... is a balancing/design pass per unit, not fixed by this spec" (design doc, decided).
	return d
