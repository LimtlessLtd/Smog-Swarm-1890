class_name LocationNames
extends RefCounted

## A hex as a player would name it, for any text a player reads. Alerts used to say
## "A large horde (1500 strong) has been spotted near (82, 119)!" — an axial
## coordinate nothing on screen labels. FB-2 asks that every alert say where.
##
## describe() returns a prepositional phrase built from what the map already knows:
##
##   "at your town"                                     — the player's starting hex
##   "at Chat Moss, 3 hexes north of your town"         — a hex with a real region name
##   "on the moor 2 hexes east of your town"            — unnamed ground, by its biome
##   "on the moor"                                      — no town to measure from
##
## Reads the map through BuildingManager (get_hex_cell(),
## get_starting_settlement_hexes()), which every caller already holds, so no class
## gains a HexGridMap dependency for a label.

const _BEARINGS: Array[String] = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


static func describe(coord: Vector2i, buildings: BuildingManager) -> String:
	var cell: HexCell = buildings.get_hex_cell(coord) if buildings else null
	var towns: Array[Vector2i] = buildings.get_starting_settlement_hexes() if buildings else []
	var town: Variant = towns[0] if not towns.is_empty() else null
	if town != null and coord == town:
		return "at your town"
	var relative := ""
	if town != null:
		var distance := HexCoord.distance(town, coord)
		relative = "%d hex%s %s of your town" % [distance, "" if distance == 1 else "es", bearing_word(town, coord)]
	var region := cell.region_name if cell else ""
	if not region.is_empty():
		return "at %s, %s" % [region, relative] if not relative.is_empty() else "at %s" % region
	var ground := "on %s" % ground_word(cell)
	return "%s %s" % [ground, relative] if not relative.is_empty() else ground


## One of eight compass words for the direction from one hex to another, as seen on
## the map (screen y grows downward, so +y is south).
static func bearing_word(from_coord: Vector2i, to_coord: Vector2i) -> String:
	var delta := HexCoord.axial_to_world(to_coord) - HexCoord.axial_to_world(from_coord)
	if delta.length() < 0.001:
		return "here"
	var index := int(round(fposmod(delta.angle(), TAU) / (TAU / 8.0))) % 8
	return _BEARINGS[index]


## "the moor", "farmland", "the river" — the ground a hex mostly is.
static func ground_word(cell: HexCell) -> String:
	if cell == null:
		return "open country"
	match cell.biome_type:
		GameEnums.BiomeType.MOORLAND:
			return "the moor"
		GameEnums.BiomeType.FARMLAND:
			return "farmland"
		GameEnums.BiomeType.WOODLAND:
			return "woodland"
		GameEnums.BiomeType.HEATHLAND:
			return "the heath"
		GameEnums.BiomeType.WETLAND:
			return "the marsh"
		GameEnums.BiomeType.HIGHLAND:
			return "high ground"
		GameEnums.BiomeType.URBAN:
			return "the streets"
		GameEnums.BiomeType.INDUSTRIAL:
			return "the works"
		GameEnums.BiomeType.WATERWAY:
			return "the canal" if cell.terrain_feature == GameEnums.TerrainFeature.CANAL else "the river"
		GameEnums.BiomeType.OCEAN:
			return "the coast"
	return "open country"
