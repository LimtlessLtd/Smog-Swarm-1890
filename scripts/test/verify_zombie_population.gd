extends SceneTree

## Proves the baked `total_zombie_pop` layer is real 1890s population, that it
## agrees with the game's own land mask, and that the three cities the map names
## actually hold a city's worth of people. Run:
##
##   Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/verify_zombie_population.gd
##
## Why each check exists rather than "the bake printed a number":
##
## * The bake writes the whole MAP_BOUNDS rectangle from ITS OWN parse of
##   BritishGeographyData._LAND_RLE. Check 2 re-derives the land set through the
##   game's own get_landmass_hexes() and compares hex by hex, so a coastline
##   re-bake that moved the land under a stale population file is caught here
##   rather than showing up as a city in the sea.
## * Capacity IS the difficulty curve (decisions.md D3), so check 3 asserts the
##   total is really the 1891 census and not, say, modern population left
##   unscaled — a 2x error there doubles every zombie in the game.
## * geo_projection's affine has a 1,265-unit RMS residual against its own
##   anchors, which is 1.6 hex rows at Manchester. Check 4 is the guard on that:
##   the first cut of this bake left the player's own starting settlement with
##   84,000 people across its four hexes while an empty moorland hex two rows
##   north held 253,000.
##
## Exits non-zero on any failure, so it gates rather than only reporting.

## design_doc.md §2.1: capacity is baked from the 1891 census of the United
## Kingdom (37,802,400). The band is wide because the bake legitimately loses a
## little — a settlement whose projected point has no land within 8 hexes is
## dropped — and because the source extracts change as OSM does. It is narrow
## enough to catch the errors that matter: an unscaled modern population lands
## near 200%, and a bake that fell back to the floor everywhere lands near 12%.
const _MIN_CENSUS_SHARE: float = 0.85
const _MAX_CENSUS_SHARE: float = 1.15
const _CENSUS_1891_UK: int = 37_802_400

## A named settlement footprint has to read as a city, not as countryside. The
## floor is 1,000; measured on the 2026-08-28 bake the three footprints hold
## 333,075 (Manchester), 535,591 (Birmingham) and 3,397,536 (Greater London).
const _MIN_NAMED_SETTLEMENT_TOTAL: int = 100_000

## London was the largest city on earth in 1891 and its footprint is 12 hexes.
const _MIN_LONDON_TOTAL: int = 1_000_000

var _failures: Array[String] = []


func _initialize() -> void:
	if not ZombiePopulationData.is_available():
		print("FAIL: no baked population data. Bake it with:")
		print("  python tools/geo_bake/extract_place_nodes.py")
		print("  python tools/geo_bake/fetch_wikidata_population.py")
		print("  python tools/geo_bake/bake_population.py")
		quit(1)
		return

	var land := BritishGeographyData.get_landmass_hexes()
	_check_bounds()
	_check_land_agreement(land)
	_check_census_total(land)
	_check_named_settlements(land)
	_check_decoder_against_raw_bytes()

	print()
	if _failures.is_empty():
		print("All zombie-population checks passed.")
		quit(0)
	else:
		print("FAILED (%d):" % _failures.size())
		for failure in _failures:
			print("  " + failure)
		quit(1)


func _check_bounds() -> void:
	var baked := ZombiePopulationData.baked_bounds()
	print("baked rectangle %s, MAP_BOUNDS %s" % [baked, BritishGeographyData.MAP_BOUNDS])
	if baked != BritishGeographyData.MAP_BOUNDS:
		_failures.append("baked rectangle %s != BritishGeographyData.MAP_BOUNDS %s" % [baked, BritishGeographyData.MAP_BOUNDS])
	var population_floor := ZombiePopulationData.population_floor()
	print("floor read from the file: %d" % population_floor)
	if population_floor != ZombiePopulationData.FALLBACK_FLOOR:
		_failures.append("baked floor is %d, design_doc.md §2.1 says %d" % [population_floor, ZombiePopulationData.FALLBACK_FLOOR])


## Every hex the game calls land must hold at least the floor, and every hex it
## calls sea must hold nothing. Both directions matter: a land hex at 0 is a
## hole the infestation model would divide by, and a sea hex above 0 means the
## population bake and the coastline disagree about where Britain is.
func _check_land_agreement(land: Dictionary) -> void:
	var population_floor := ZombiePopulationData.population_floor()
	var land_below_floor := 0
	var sea_above_zero := 0
	var bounds := BritishGeographyData.MAP_BOUNDS
	for q in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for r in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var coord := Vector2i(q, r)
			var capacity := ZombiePopulationData.capacity_for(coord)
			if land.has(coord):
				if capacity < population_floor:
					land_below_floor += 1
			elif capacity != 0:
				sea_above_zero += 1
	print("land hexes below the floor: %d;  sea hexes above zero: %d" % [land_below_floor, sea_above_zero])
	if land_below_floor > 0:
		_failures.append("%d land hexes hold less than the %d floor" % [land_below_floor, population_floor])
	if sea_above_zero > 0:
		_failures.append("%d sea hexes hold a population — the bake and the coastline disagree" % sea_above_zero)


func _check_census_total(land: Dictionary) -> void:
	var total := 0
	var above_floor := 0
	var population_floor := ZombiePopulationData.population_floor()
	for coord: Vector2i in land:
		var capacity := ZombiePopulationData.capacity_for(coord)
		total += capacity
		if capacity > population_floor:
			above_floor += 1
	var share := float(total) / float(_CENSUS_1891_UK)
	print("total capacity %d over %d land hexes (%.1f%% of the 1891 census); %d above the floor"
		% [total, land.size(), share * 100.0, above_floor])
	if share < _MIN_CENSUS_SHARE or share > _MAX_CENSUS_SHARE:
		_failures.append("total capacity is %.1f%% of the 1891 census, outside %.0f-%.0f%%"
			% [share * 100.0, _MIN_CENSUS_SHARE * 100.0, _MAX_CENSUS_SHARE * 100.0])
	# A bake that lost its settlement data still passes the total check by
	# flooring everything, so assert the spread too: 4,692 land hexes at the
	# floor come to 4.7M, well under the band, but a partial loss would not.
	if above_floor < 1000:
		_failures.append("only %d hexes hold more than the floor — the settlement layer is thin or missing" % above_floor)


## The three settlements BritishGeographyData names must each hold a real city's
## population across their own footprint, and the single most populous hex in
## Britain must be one of Greater London's. Read through get_features() rather
## than a copy of the hex lists, so a footprint edit cannot drift this check.
func _check_named_settlements(land: Dictionary) -> void:
	var totals: Dictionary = {}
	for feature: GeographyFeature in BritishGeographyData.get_features():
		if feature.feature_type != GeographyFeature.FeatureType.SETTLEMENT:
			continue
		var total := 0
		for coord: Vector2i in feature.hex_coords:
			total += ZombiePopulationData.capacity_for(coord)
		totals[feature.feature_name] = total
		print("%-16s %2d hexes, %d people" % [feature.feature_name, feature.hex_coords.size(), total])
		if total < _MIN_NAMED_SETTLEMENT_TOTAL:
			_failures.append("%s holds only %d people across %d hexes — the projection has moved it off its own footprint"
				% [feature.feature_name, total, feature.hex_coords.size()])
	if totals.is_empty():
		_failures.append("BritishGeographyData names no SETTLEMENT features at all")
		return
	if totals.has("Greater London") and int(totals["Greater London"]) < _MIN_LONDON_TOTAL:
		_failures.append("Greater London holds %d, under the %d a city of its 1891 size needs"
			% [totals["Greater London"], _MIN_LONDON_TOTAL])

	var busiest := Vector2i.ZERO
	var busiest_capacity := -1
	for coord: Vector2i in land:
		var capacity := ZombiePopulationData.capacity_for(coord)
		if capacity > busiest_capacity:
			busiest_capacity = capacity
			busiest = coord
	var london_hexes := _feature_hexes("Greater London")
	print("busiest hex on the map: %s at %d" % [busiest, busiest_capacity])
	if not london_hexes.is_empty() and not london_hexes.has(busiest):
		_failures.append("the busiest hex %s (%d) is not in Greater London's footprint" % [busiest, busiest_capacity])


## Decodes the file a second time, independently of ZombiePopulationData's
## cached read, and compares a spread of hexes. Catches a row/column transpose
## or an offset slip in the reader — the failure mode a wire format shared by
## two languages actually has (TerrainMeshChunkData's own doc comment).
func _check_decoder_against_raw_bytes() -> void:
	var file := FileAccess.open(ZombiePopulationData.DATA_PATH, FileAccess.READ)
	if file == null:
		_failures.append("cannot re-open %s for the raw comparison" % ZombiePopulationData.DATA_PATH)
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var origin := Vector2i(bytes.decode_s32(8), bytes.decode_s32(12))
	var size := Vector2i(int(bytes.decode_u32(16)), int(bytes.decode_u32(20)))
	var mismatches := 0
	var sampled := 0
	# A coprime stride over both axes so the sample walks the whole rectangle
	# rather than one band of it.
	for i in range(0, size.x * size.y, 97):
		var local := Vector2i(i % size.x, i / size.x)
		var raw := int(bytes.decode_u32(ZombiePopulationData.HEADER_SIZE + i * 4))
		sampled += 1
		if ZombiePopulationData.capacity_for(origin + local) != raw:
			mismatches += 1
	print("raw-byte comparison: %d hexes sampled, %d mismatched" % [sampled, mismatches])
	if mismatches > 0:
		_failures.append("%d of %d sampled hexes disagree with a raw decode of the same file" % [mismatches, sampled])


func _feature_hexes(feature_name: String) -> Dictionary:
	var out: Dictionary = {}
	for feature: GeographyFeature in BritishGeographyData.get_features():
		if feature.feature_name == feature_name:
			for coord: Vector2i in feature.hex_coords:
				out[coord] = true
	return out
