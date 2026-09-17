class_name VerticalSliceSetup
extends RefCounted

## Hands the player the slice's starting position (VerticalSliceConfig) on top of
## the ordinary new-game seeding: the starting perimeter wall, the extra buildings
## and units, and the stockpile. Everything goes through public manager methods;
## nothing here writes another class's state.
##
## The wall is WallManager.seed_starting_defenses() — the function the campaign
## stopped calling on 2026-08-11 at the user's request and kept "for a possible
## future 'start with walls' option" (commit 5263e5e5). The slice is that option:
## the fight it builds toward is holding a wall.

static func apply(buildings: BuildingManager, units: UnitManager, resources: ResourceManager, walls: WallManager) -> void:
	var start := VerticalSliceConfig.START_HEX
	if walls:
		walls.seed_starting_defenses([VerticalSliceConfig.TARGET_HEX])
	for entry in VerticalSliceConfig.STARTING_BUILDINGS:
		buildings.grant_building(entry[0], start, entry[1])
	var index := 0
	for entry in VerticalSliceConfig.STARTING_UNITS:
		for i in range(int(entry[1])):
			units.grant_unit(entry[0], start, _formation_offset(index))
			index += 1
	for resource_type in VerticalSliceConfig.STARTING_RESOURCES:
		var wanted := float(VerticalSliceConfig.STARTING_RESOURCES[resource_type])
		var have := resources.get_amount(resource_type)
		if wanted > have:
			resources.add(resource_type, wanted - have)


## A loose two-row block just south-west of the town centre, so ten figures are
## not stacked on one point.
static func _formation_offset(index: int) -> Vector2:
	var column := index % 5
	var row := index / 5
	return Vector2(-120.0 + column * 22.0, 40.0 + row * 22.0)
