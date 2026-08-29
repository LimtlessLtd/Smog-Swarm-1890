extends Node

## What §2.1's resident fight actually costs on the REAL map, rather than on
## verify_resident_defense.gd's flat fixture. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless res://scenes/test/diagnose_resident_combat.tscn
##
## Not a gated verification, deliberately, and for the same reason
## diagnose_tactical_zombies.gd is not: every number below is a function of
## balancing knobs — ResidentDefenseController.ENGAGEMENT_RADIUS_METRES and
## WAVE_INTERVAL_SECONDS, Horde.HP_PER_ZOMBIE/DAMAGE_PER_ZOMBIE,
## UnitCatalog's stat curve — and asserting any of it would freeze a tuning
## knob into the gate. This exists so the person turning those knobs can see
## what they do, and so backlog.md's "infestation balance pass" has real
## survival and clearing times to tune against rather than intuitions.
##
## It boots the real Main.tscn (several minutes of map generation, per
## verify_gates.gd's own note) and then places units by hand rather than
## waiting for a player to march them across the island.
##
## Two stands are measured because they answer different questions. The bare
## one applies no healing at all — a unit caught on infested ground outside its
## own Zone of Control, the worst case. The garrison one applies
## UnitOrderController.GARRISON_REGEN_FRACTION_PER_TICK by hand, at the same
## rate and on the same 20-second interval that class already heals a
## GARRISON/HOLD unit standing on ZoC-covered ground; that is D8's "standing
## garrison" and it is the case that decides whether ground can be held at all.
## Applied here rather than by wiring UnitOrderController, which would need a
## LogisticsNetwork and real ZoC coverage over a hex the player does not hold.
##
## What neither models: retreat, reinforcement, walls, or a horde arriving from
## somewhere else mid-fight.

## The three cities the population bake places by hand (decisions.md D35) — the
## densest ground on the map, and therefore the hardest fight in the game.
const _CITY_NAMES: Array[String] = ["Manchester", "Birmingham", "Greater London"]

## The two ends of the roster: what the player opens with, and the heaviest
## thing they can ever field.
const _UNIT_TYPES: Array[GameEnums.UnitType] = [
	GameEnums.UnitType.TRUNCHEONEER,
	GameEnums.UnitType.HOLT_BREAKER,
]

## Garrison sizes worth pricing. One is the "can a lone picket hold this at all"
## question; the other two are what taking a city actually looks like.
const _GARRISON_SIZES: Array[int] = [1, 10, 50]

## Long enough to kill a lone unit many times over at every population level
## measured; a stand that survives this is reported as holding, and its kill
## rate over these rounds is what the clearing table extrapolates from.
const _MAX_ROUNDS: int = 400

var _main: Node


func _ready() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	var hex_grid_map: HexGridMap = _main.get_node("WorldRoot/HexGridMap")
	if not hex_grid_map.get_all_cells().is_empty():
		_report()
	else:
		hex_grid_map.generation_completed.connect(func(_count: int) -> void: _report())


func _report() -> void:
	var infestation: InfestationManager = _main.get_node("InfestationManager")
	var buildings: BuildingManager = _main.get_node("BuildingManager")

	print("=== The rule ===")
	print("  a wave is the residents inside a %.0f m disc of a hex's own density," % ResidentDefenseController.ENGAGEMENT_RADIUS_METRES)
	print("  against %.2f km2 per hex, one round every %.0f simulated seconds,"
			% [HexCoord.hex_area_square_metres() / 1.0e6, ResidentDefenseController.WAVE_INTERVAL_SECONDS])
	print("  topped back up between one unit's round and the next (D50).")
	print("  Garrison regen is %.0f%% of max HP per round (UnitOrderController)."
			% (UnitOrderController.GARRISON_REGEN_FRACTION_PER_TICK * 100.0))

	var targets: Array[Vector2i] = []
	var labels: Array[String] = []
	var start_hexes := buildings.get_starting_settlement_hexes()
	if not start_hexes.is_empty():
		# Ring 2 out from home: the first ground the player has to take, and the
		# only row here that is an early-game number rather than an endgame one.
		targets.append(start_hexes[0] + Vector2i(2, 0))
		labels.append("2 hexes from home")
	for city_name in _CITY_NAMES:
		var coord := _densest_hex_of(city_name, infestation)
		if coord != Vector2i.MAX:
			targets.append(coord)
			labels.append(city_name)

	print("\n=== What each hex fields ===")
	print("  %-22s %10s %10s %8s %10s" % ["where", "residents", "capacity", "wave", "% infest"])
	for i in targets.size():
		var coord: Vector2i = targets[i]
		print("  %-22s %10d %10d %8d %9.1f%%" % [
			labels[i], infestation.resident_count_at(coord), infestation.capacity_at(coord),
			ResidentDefenseController.frontage_for(infestation.resident_count_at(coord)),
			infestation.infestation_at(coord)])

	print("\n=== One unit alone, no healing — the worst case ===")
	print("  %-22s %-16s %8s %7s %9s %9s" % ["where", "unit", "rounds", "days", "killed", "outcome"])
	for i in targets.size():
		for unit_type in _UNIT_TYPES:
			var stand := _stand(targets[i], unit_type, 1, 0.0)
			print("  %-22s %-16s %8d %7.1f %9d %9s" % [
				labels[i], UnitCatalog.get_definition(unit_type).display_name,
				stand["rounds"], stand["days"], stand["killed"], stand["outcome"]])

	print("\n=== A garrison on secured ground — D8's price of holding ===")
	print("  'clears in' extrapolates the measured kill rate down to the 5%% Cleared")
	print("  threshold (D2). '-' means that garrison dies before it clears anything.")
	print("  %-22s %-16s %4s %8s %9s %12s %11s" % ["where", "unit", "n", "rounds", "outcome", "kills/round", "clears in"])
	for i in targets.size():
		for unit_type in _UNIT_TYPES:
			for size in _GARRISON_SIZES:
				var stand := _stand(targets[i], unit_type, size, UnitOrderController.GARRISON_REGEN_FRACTION_PER_TICK)
				var per_round := float(stand["killed"]) / maxf(1.0, float(stand["rounds"]))
				var clears := "-"
				if stand["outcome"] == "holds" and per_round > 0.0:
					var to_kill := maxi(0, infestation.resident_count_at(targets[i]) - int(InfestationManager.CLEARED_BELOW / 100.0 * float(infestation.capacity_at(targets[i]))))
					clears = "%.0f days" % (float(to_kill) / per_round * ResidentDefenseController.WAVE_INTERVAL_SECONDS / TickManager.DAY_LENGTH_SECONDS)
				print("  %-22s %-16s %4d %8d %9s %12.1f %11s" % [
					labels[i], UnitCatalog.get_definition(unit_type).display_name, size,
					stand["rounds"], stand["outcome"], per_round, clears])

	get_tree().quit(0)


## Parks `unit_count` fresh units on `coord` and runs wave ticks until every one
## of them is dead or _MAX_ROUNDS elapses, restoring the hex and the real unit
## roster afterwards so the next row starts from the population this one did.
##
## `regen_fraction` of each unit's max HP is healed at the top of every round,
## which is what UnitOrderController does for a GARRISON/HOLD unit on friendly
## ground. 0.0 is the no-healing worst case.
##
## Units are injected through UnitManager.load_save_entries() rather than
## trained: training needs a Garrison, the resources and the tech tier, none of
## which the player has on day one at Greater London, which is exactly the
## question being asked.
func _stand(coord: Vector2i, unit_type: GameEnums.UnitType, unit_count: int, regen_fraction: float) -> Dictionary:
	var infestation: InfestationManager = _main.get_node("InfestationManager")
	var units: UnitManager = _main.get_node("UnitManager")
	var hordes: HordeManager = _main.get_node("HordeManager")
	var defense: ResidentDefenseController = _main.get_node("ResidentDefenseController")

	var residents_before := infestation.resident_count_at(coord)
	var existing := units.get_save_entries()
	var existing_next_id := units.get_next_id()
	var cleared_hordes := _clear_hordes_at(coord, hordes)

	var definition := UnitCatalog.get_definition(unit_type)
	var entries: Array[UnitSaveEntry] = []
	for i in unit_count:
		entries.append(UnitSaveEntry.new(unit_type, coord, i + 1, definition.max_hp))
	units.load_save_entries(entries, unit_count + 1)

	var rounds := 0
	var killed := 0
	while rounds < _MAX_ROUNDS and not units.get_all_units().is_empty():
		for instance: UnitInstance in units.get_all_units():
			instance.current_hp = minf(instance.current_hp + definition.max_hp * regen_fraction, definition.max_hp)
		var before := hordes.get_zombie_count_at(coord) + infestation.resident_count_at(coord)
		defense.run_wave_tick()
		killed += maxi(0, before - (hordes.get_zombie_count_at(coord) + infestation.resident_count_at(coord)))
		rounds += 1

	var survivors := units.get_all_units().size()

	# Put the hex and the unit roster back the way they were found.
	_clear_hordes_at(coord, hordes)
	for size in cleared_hordes:
		hordes.spawn_horde_at(coord, size)
	infestation.remove_zombies(coord, infestation.resident_count_at(coord))
	infestation.add_zombies(coord, residents_before)
	units.load_save_entries(existing, existing_next_id)

	return {
		"rounds": rounds,
		"days": float(rounds) * ResidentDefenseController.WAVE_INTERVAL_SECONDS / TickManager.DAY_LENGTH_SECONDS,
		"killed": killed,
		"survivors": survivors,
		"outcome": "holds" if survivors == unit_count else ("%d left" % survivors if survivors > 0 else "wiped"),
	}


## Removes every horde on `coord` and returns their sizes, so a stand measures
## the RESIDENT fight rather than whatever happened to be roaming past. The
## sizes go back afterwards.
func _clear_hordes_at(coord: Vector2i, hordes: HordeManager) -> Array[int]:
	var sizes: Array[int] = []
	for horde: Horde in hordes.get_hordes_at(coord):
		sizes.append(horde.size)
		hordes.remove_horde(horde)
	return sizes


## The busiest hex of a named settlement footprint, not its first — a city
## spans several hexes and only one of them carries the bulk of the population
## the bake put there (decisions.md D35). Vector2i.MAX means "this map has no
## such named feature", which is a real possibility rather than an error.
func _densest_hex_of(feature_name: String, infestation: InfestationManager) -> Vector2i:
	var best := Vector2i.MAX
	var best_count := -1
	for feature in BritishGeographyData.get_features():
		if feature.feature_name != feature_name:
			continue
		for coord in feature.hex_coords:
			var count := infestation.zombie_count_at(coord)
			if count > best_count:
				best_count = count
				best = coord
	return best
