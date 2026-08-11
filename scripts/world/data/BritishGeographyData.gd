class_name BritishGeographyData
extends RefCounted

## Seed data for the playable map. **Landmass silhouette baked from real
## open geographic data, correctly scaled to the game's own "~25 sq. mile
## per hex" constant (see `HexCell.gd`'s own doc comment).** User feedback,
## in two rounds: (1) after seeing the previous hand-placed-anchor version
## in an actual screenshot — "that looks nothing like a hex tile map of the
## UK and Ireland, is it possible if you use some open source data like from
## Ordnance Survey"; (2) after the first real-data re-bake — "remember the
## hex tiles are roughly 5 miles by 5 miles though so have you taken that
## into account?" They hadn't been: the first re-bake fit the real coastline
## to the OLD 120x120 `MAP_BOUNDS` (a leftover grid size from the
## hand-authored version), which worked out to ~8x7 real miles per hex
## (~49 sq mi, not 25) — MAP_BOUNDS has grown to fit the real landmass at
## the CORRECT scale instead, rather than fitting the landmass to a fixed
## grid.
##
## Source: Natural Earth's public-domain 10m-resolution Admin-0 Countries
## dataset (naturalearthdata.com), GBR + IRL features — chosen over Ordnance
## Survey's own OpenData layers because OS coverage stops at the GB
## coastline (no Ireland at all), and this project needs one consistent
## dataset for both islands. 7,113 points across GB's 57 sub-polygons
## (mainland + Hebrides + Orkney + Shetland + Isle of Wight + Anglesey, etc.)
## and 2,394 points across Ireland's 7.
##
## **Baking pipeline (offline, one-time — not run by the game itself):**
## 1. Downloaded GBR/IRL features from Natural Earth's 10m countries GeoJSON.
## 2. Projected lon/lat to a local equirectangular plane, longitude scaled by
##    cos(mean_latitude) so East-West distance isn't stretched relative to
##    North-South.
## 3. **Calibrated the hex grid's scale (`k`, projected-plane units per hex)
##    against real-world miles, not against a target grid size.** A
##    pointy-top hex with circumradius R has area `(3*sqrt(3)/2)*R^2` and a
##    fixed ratio between its row pitch (1.5*R miles N-S per hex row) and
##    column pitch (sqrt(3)*R miles E-W per hex column) — solving
##    `(3*sqrt(3)/2)*R^2 = 25 sq mi` gives `R ≈ 3.10 mi` (row pitch ≈4.65mi,
##    column pitch ≈5.37mi, i.e. genuinely "~5x5 miles"), and calibrating the
##    single uniform scale factor against real degrees-latitude-per-hex-row
##    makes the East-West axis correct too for free (same fixed hex-shape
##    ratio, and the projection itself introduces no extra stretch).
## 4. `MAP_BOUNDS` is sized to fit the real landmass at THIS scale plus an
##    8-hex ocean margin — no longer a fixed round number chosen for its own
##    sake. This roughly doubled the grid versus the first (incorrectly
##    scaled) re-bake: 154x179 (27,566 total hexes), landmass ~4,692 hexes
##    (~17%) — coincidentally close to the ORIGINAL hand-authored version's
##    ~4,700 land hexes, suggesting that version's hand-picked disk radii
##    had, by feel, landed close to the right scale even without deriving it
##    from a real mile figure.
## 5. For every hex in `MAP_BOUNDS`, sampled its center + 6 corners,
##    converted each sample back to the projected plane, and ran even-odd
##    point-in-polygon against every GBR/IRL sub-polygon (bbox-prefiltered
##    for speed). A hex is LAND if >=4 of its 7 samples land inside any
##    sub-polygon.
## 6. Named settlements/features below use the exact same projection to turn
##    real lon/lat into hex coordinates. Any anchor whose exact rounded hex
##    missed land (coastal cities/marshes right at the shoreline sometimes
##    round to the water-side hex) was snapped to the nearest actual land hex
##    by ring search; verified computationally that all twelve major-city
##    anchors and every feature anchor below landed on real LAND hexes after
##    snapping.
##
## The result is still a HEX-GRID silhouette, not a survey-accurate
## coastline — at ~5 real miles per hex, narrow estuaries, small headlands
## and individual skerries still don't fully resolve, the same resolution
## limit any hex/tile strategy game's real-world map has. What the two
## rounds of feedback fixed, in order: first the SOURCE (real coastline data
## instead of hand-placed anchors), then the SCALE (calibrated to the game's
## own stated miles-per-hex instead of fit to a leftover grid size).
##
## **2026-08-10 addendum: what's INSIDE this coastline is now real data too.**
## The `_LAND_RLE`/`MAP_BOUNDS`/`_build_features()` data below is UNCHANGED
## by this pass — this file's own lon/lat<->hex transform was never
## committed as code (only this prose description survives, see step 2-3
## above), so re-deriving it exactly isn't possible, and there was no need
## to: every hex's *biome/soil/elevation* (previously "default MOORLAND
## except 17 hand-placed named features") now comes from
## `RealTerrainSampler` (`scripts/world/RealTerrainSampler.gd`), sampling
## two whole-map-aligned rasters baked from OpenStreetMap land-cover/water
## data + AWS/Mapzen SRTM-derived elevation — see
## `tools/geo_bake/bake_landcover.py` (an actually-committed, reproducible
## script this time, unlike the coastline bake above). That script fits its
## OWN fresh affine transform, calibrated against this file's *existing*
## named-anchor hex positions and their real-world coordinates — safe
## because nothing outside this file hardcodes any anchor's literal
## coordinate (`BuildingManager.gd`'s own doc comment already resolves
## starting-settlement placement by `region_name`, not position, precisely
## because Manchester's hex has shifted before without incident).
## `HexMapGenerator._apply_real_terrain()` is where the two data sources
## meet: real data first, this file's 17 named-feature stamps still applied
## on top exactly as before.
const MAP_BOUNDS := Rect2i(0, 0, 154, 179)

## Run-length-encoded per-row land data baked by the pipeline above:
## `[r, [Vector2i(q_start, q_end_inclusive), ...]]` per row that has any
## land. Kept RLE rather than a flat hex list — real coastlines are mostly
## contiguous horizontal runs per row, so this compresses ~4,692 land hexes
## into 310 spans across 144 rows, and expands trivially back into the same
## `Vector2i -> true` Dictionary shape every other system here already
## expects from `get_landmass_hexes()`.
const _LAND_RLE: Array = [
	[10, [Vector2i(143, 144)]],
	[11, [Vector2i(142, 142)]],
	[12, [Vector2i(141, 141)]],
	[13, [Vector2i(138, 139)]],
	[14, [Vector2i(138, 139)]],
	[15, [Vector2i(138, 140)]],
	[16, [Vector2i(137, 139)]],
	[17, [Vector2i(136, 138)]],
	[20, [Vector2i(136, 136)]],
	[33, [Vector2i(116, 116)]],
	[34, [Vector2i(114, 116)]],
	[35, [Vector2i(114, 115)]],
	[36, [Vector2i(114, 116)]],
	[37, [Vector2i(113, 113), Vector2i(116, 116)]],
	[38, [Vector2i(112, 113)]],
	[41, [Vector2i(111, 112)]],
	[42, [Vector2i(98, 99), Vector2i(104, 111)]],
	[43, [Vector2i(97, 111)]],
	[44, [Vector2i(87, 87), Vector2i(97, 110)]],
	[45, [Vector2i(85, 87), Vector2i(96, 109)]],
	[46, [Vector2i(83, 86), Vector2i(95, 108)]],
	[47, [Vector2i(82, 85), Vector2i(93, 106)]],
	[48, [Vector2i(80, 84), Vector2i(93, 105)]],
	[49, [Vector2i(79, 83), Vector2i(92, 103)]],
	[50, [Vector2i(79, 83), Vector2i(92, 102)]],
	[51, [Vector2i(79, 82), Vector2i(92, 100)]],
	[52, [Vector2i(79, 79), Vector2i(89, 99)]],
	[53, [Vector2i(78, 79), Vector2i(87, 100)]],
	[54, [Vector2i(86, 99)]],
	[55, [Vector2i(86, 98), Vector2i(102, 104), Vector2i(107, 108), Vector2i(111, 111), Vector2i(113, 113)]],
	[56, [Vector2i(73, 75), Vector2i(81, 82), Vector2i(86, 97), Vector2i(100, 113)]],
	[57, [Vector2i(74, 74), Vector2i(80, 81), Vector2i(85, 95), Vector2i(98, 113)]],
	[58, [Vector2i(73, 73), Vector2i(78, 81), Vector2i(84, 113)]],
	[59, [Vector2i(72, 72), Vector2i(77, 81), Vector2i(84, 112)]],
	[60, [Vector2i(72, 72), Vector2i(78, 81), Vector2i(84, 111)]],
	[61, [Vector2i(71, 71), Vector2i(78, 80), Vector2i(84, 110)]],
	[62, [Vector2i(71, 71), Vector2i(78, 109)]],
	[63, [Vector2i(70, 70), Vector2i(80, 108)]],
	[64, [Vector2i(80, 80), Vector2i(82, 108)]],
	[65, [Vector2i(81, 107)]],
	[66, [Vector2i(80, 106)]],
	[67, [Vector2i(80, 105)]],
	[68, [Vector2i(79, 104)]],
	[69, [Vector2i(76, 103)]],
	[70, [Vector2i(77, 102)]],
	[71, [Vector2i(74, 79), Vector2i(81, 101)]],
	[72, [Vector2i(74, 78), Vector2i(80, 100)]],
	[73, [Vector2i(74, 77), Vector2i(80, 98)]],
	[74, [Vector2i(74, 76), Vector2i(79, 95), Vector2i(97, 97)]],
	[75, [Vector2i(73, 75), Vector2i(78, 97)]],
	[76, [Vector2i(77, 97)]],
	[77, [Vector2i(76, 96)]],
	[78, [Vector2i(76, 93)]],
	[79, [Vector2i(73, 73), Vector2i(75, 92)]],
	[80, [Vector2i(72, 72), Vector2i(74, 75), Vector2i(77, 79), Vector2i(81, 91), Vector2i(95, 97)]],
	[81, [Vector2i(71, 71), Vector2i(74, 78), Vector2i(80, 97)]],
	[82, [Vector2i(69, 70), Vector2i(73, 77), Vector2i(79, 99)]],
	[83, [Vector2i(68, 69), Vector2i(73, 74), Vector2i(77, 77), Vector2i(79, 99)]],
	[84, [Vector2i(68, 69), Vector2i(73, 73), Vector2i(78, 99)]],
	[85, [Vector2i(67, 68), Vector2i(72, 72), Vector2i(74, 75), Vector2i(78, 99)]],
	[86, [Vector2i(71, 74), Vector2i(79, 100)]],
	[87, [Vector2i(70, 71), Vector2i(73, 74), Vector2i(78, 100)]],
	[88, [Vector2i(70, 70), Vector2i(73, 74), Vector2i(78, 99)]],
	[89, [Vector2i(69, 70), Vector2i(76, 99)]],
	[90, [Vector2i(57, 57), Vector2i(68, 69), Vector2i(75, 98)]],
	[91, [Vector2i(56, 58), Vector2i(75, 98)]],
	[92, [Vector2i(52, 57), Vector2i(61, 64), Vector2i(74, 98)]],
	[93, [Vector2i(49, 56), Vector2i(58, 64), Vector2i(73, 97)]],
	[94, [Vector2i(48, 52), Vector2i(54, 55), Vector2i(57, 64), Vector2i(72, 97)]],
	[95, [Vector2i(46, 64), Vector2i(70, 97)]],
	[96, [Vector2i(46, 64), Vector2i(70, 81), Vector2i(84, 97)]],
	[97, [Vector2i(46, 64), Vector2i(70, 74), Vector2i(76, 79), Vector2i(82, 97)]],
	[98, [Vector2i(45, 64), Vector2i(70, 70), Vector2i(73, 74), Vector2i(82, 96)]],
	[99, [Vector2i(42, 63), Vector2i(73, 73), Vector2i(81, 96)]],
	[100, [Vector2i(42, 64), Vector2i(80, 96)]],
	[101, [Vector2i(45, 64), Vector2i(79, 97)]],
	[102, [Vector2i(44, 64), Vector2i(79, 99)]],
	[103, [Vector2i(43, 63), Vector2i(78, 100)]],
	[104, [Vector2i(41, 63), Vector2i(78, 100)]],
	[105, [Vector2i(40, 62), Vector2i(78, 99)]],
	[106, [Vector2i(29, 34), Vector2i(36, 38), Vector2i(40, 60), Vector2i(78, 99)]],
	[107, [Vector2i(29, 58), Vector2i(78, 99)]],
	[108, [Vector2i(28, 58), Vector2i(81, 100)]],
	[109, [Vector2i(29, 56), Vector2i(80, 99)]],
	[110, [Vector2i(28, 55), Vector2i(80, 99)]],
	[111, [Vector2i(27, 53), Vector2i(78, 98)]],
	[112, [Vector2i(30, 53), Vector2i(78, 98)]],
	[113, [Vector2i(28, 53), Vector2i(77, 98)]],
	[114, [Vector2i(26, 52), Vector2i(77, 98)]],
	[115, [Vector2i(26, 52), Vector2i(76, 98)]],
	[116, [Vector2i(24, 52), Vector2i(75, 96)]],
	[117, [Vector2i(23, 52), Vector2i(75, 97)]],
	[118, [Vector2i(23, 51), Vector2i(74, 97)]],
	[119, [Vector2i(23, 50), Vector2i(63, 64), Vector2i(73, 97)]],
	[120, [Vector2i(25, 50), Vector2i(62, 64), Vector2i(70, 71), Vector2i(73, 97)]],
	[121, [Vector2i(25, 25), Vector2i(29, 50), Vector2i(62, 97)]],
	[122, [Vector2i(29, 49), Vector2i(62, 97)]],
	[123, [Vector2i(26, 49), Vector2i(63, 96)]],
	[124, [Vector2i(25, 49), Vector2i(62, 95)]],
	[125, [Vector2i(24, 48), Vector2i(61, 93), Vector2i(98, 98)]],
	[126, [Vector2i(24, 48), Vector2i(59, 93), Vector2i(96, 102)]],
	[127, [Vector2i(23, 47), Vector2i(58, 59), Vector2i(62, 93), Vector2i(96, 102)]],
	[128, [Vector2i(22, 46), Vector2i(62, 103)]],
	[129, [Vector2i(21, 24), Vector2i(26, 45), Vector2i(62, 103)]],
	[130, [Vector2i(19, 23), Vector2i(25, 44), Vector2i(61, 103)]],
	[131, [Vector2i(19, 19), Vector2i(21, 44), Vector2i(60, 102)]],
	[132, [Vector2i(19, 43), Vector2i(60, 102)]],
	[133, [Vector2i(17, 42), Vector2i(59, 101)]],
	[134, [Vector2i(17, 41), Vector2i(59, 101)]],
	[135, [Vector2i(16, 40), Vector2i(58, 100)]],
	[136, [Vector2i(12, 40), Vector2i(57, 99)]],
	[137, [Vector2i(11, 35), Vector2i(55, 98)]],
	[138, [Vector2i(15, 31), Vector2i(52, 98)]],
	[139, [Vector2i(12, 30), Vector2i(51, 96)]],
	[140, [Vector2i(11, 28), Vector2i(48, 94)]],
	[141, [Vector2i(10, 23), Vector2i(25, 26), Vector2i(47, 94)]],
	[142, [Vector2i(9, 23), Vector2i(25, 25), Vector2i(47, 93)]],
	[143, [Vector2i(10, 23), Vector2i(47, 90)]],
	[144, [Vector2i(11, 12), Vector2i(14, 21), Vector2i(46, 49), Vector2i(52, 89)]],
	[145, [Vector2i(10, 10), Vector2i(13, 19), Vector2i(46, 47), Vector2i(53, 89)]],
	[146, [Vector2i(12, 16), Vector2i(51, 52), Vector2i(55, 61), Vector2i(63, 88)]],
	[147, [Vector2i(10, 11), Vector2i(55, 59), Vector2i(62, 86)]],
	[148, [Vector2i(56, 58), Vector2i(61, 86)]],
	[149, [Vector2i(60, 91)]],
	[150, [Vector2i(59, 90)]],
	[151, [Vector2i(51, 53), Vector2i(58, 90)]],
	[152, [Vector2i(49, 89)]],
	[153, [Vector2i(48, 87)]],
	[154, [Vector2i(48, 85)]],
	[155, [Vector2i(45, 85)]],
	[156, [Vector2i(45, 82)]],
	[157, [Vector2i(44, 69), Vector2i(71, 74), Vector2i(76, 79)]],
	[158, [Vector2i(43, 67), Vector2i(78, 78)]],
	[159, [Vector2i(42, 53), Vector2i(57, 61), Vector2i(65, 67)]],
	[160, [Vector2i(41, 50), Vector2i(57, 57), Vector2i(60, 61), Vector2i(66, 66)]],
	[161, [Vector2i(39, 49)]],
	[162, [Vector2i(38, 48)]],
	[163, [Vector2i(37, 48)]],
	[164, [Vector2i(36, 47)]],
	[165, [Vector2i(35, 37), Vector2i(45, 46)]],
	[166, [Vector2i(33, 36), Vector2i(45, 45)]],
	[167, [Vector2i(31, 34)]],
	[168, [Vector2i(30, 30), Vector2i(33, 34)]],
	[169, [Vector2i(33, 33)]],
]

## Expands `_LAND_RLE` into the `Vector2i -> true` shape `HexMapGenerator`
## reads to decide OCEAN vs. MOORLAND before any named feature stamps get
## applied on top.
static func get_landmass_hexes() -> Dictionary:
	var land: Dictionary = {}  # Vector2i -> true
	for row in _LAND_RLE:
		var r: int = row[0]
		for span: Vector2i in row[1]:
			for q in range(span.x, span.y + 1):
				land[Vector2i(q, r)] = true
	return land

static func get_features() -> Array[GeographyFeature]:
	return _build_features()

static func _build_features() -> Array[GeographyFeature]:
	var features: Array[GeographyFeature] = []

	# --- Settlements -------------------------------------------------------
	# Coordinates below are each city's real lon/lat run through the same
	# baking pipeline as the coastline itself (see this class's own header) —
	# not hand-placed. Manchester, Birmingham and Greater London keep the
	# small hand-shaped footprints (cluster/ring) the original design used;
	# only the anchor each footprint is built around moved to its real spot.
	var manchester_center := Vector2i(80, 118)
	var manchester_hexes: Array[Vector2i] = [
		manchester_center,
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[3],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[4],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[5],
	]
	features.append(GeographyFeature.new("Manchester", GeographyFeature.FeatureType.SETTLEMENT, manchester_hexes))

	var birmingham_hexes: Array[Vector2i] = HexCoord.hex_disk(Vector2i(76, 132), 1).slice(0, 4)
	features.append(GeographyFeature.new("Birmingham", GeographyFeature.FeatureType.SETTLEMENT, birmingham_hexes))

	var london_center := Vector2i(81, 147)
	var london_hexes: Array[Vector2i] = [london_center]
	london_hexes.append_array(HexCoord.hex_ring(london_center, 1))
	london_hexes.append_array(HexCoord.hex_ring(london_center, 2).slice(0, 5))
	features.append(GeographyFeature.new("Greater London", GeographyFeature.FeatureType.SETTLEMENT, london_hexes))

	# --- Elevated Terrain & Natural Barriers --------------------------------
	features.append(GeographyFeature.new(
		"Pennine Chain / Peak District", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(91, 95), Vector2i(83, 119))  # Cumbria/Borders -> Peak District.
	))
	features.append(GeographyFeature.new(
		"Chiltern Hills", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(74, 146), Vector2i(81, 141))  # Goring -> Luton/Dunstable.
	))
	features.append(GeographyFeature.new(
		"Cotswold Escarpment", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(64, 149), Vector2i(73, 139))  # Bath -> Chipping Campden.
	))

	# --- Major Waterways & Canals -------------------------------------------
	features.append(GeographyFeature.new(
		"River Mersey", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(74, 120), Vector2i(80, 118))  # Mersey Estuary -> Manchester.
	))

	var manchester_ship_canal := GeographyFeature.new(
		"Manchester Ship Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(80, 118), Vector2i(74, 120))  # Manchester -> Mersey Estuary.
	)
	manchester_ship_canal.waterway_is_canal = true
	features.append(manchester_ship_canal)

	features.append(GeographyFeature.new(
		"River Trent", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(78, 123), Vector2i(93, 114))  # Stoke -> Humber mouth.
	))

	features.append(GeographyFeature.new(
		"River Thames", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(69, 144), Vector2i(86, 148))  # Thames Head -> Estuary.
	))

	var grand_union_canal := GeographyFeature.new(
		"Grand Union Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(76, 132), Vector2i(80, 147))  # Birmingham -> London Paddington.
	)
	grand_union_canal.waterway_is_canal = true
	features.append(grand_union_canal)

	# --- Swamps & Waterlogged Basins -----------------------------------------
	features.append(GeographyFeature.new(
		"Chat Moss", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(79, 118), 1)
	))
	features.append(GeographyFeature.new(
		"The Fens", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(90, 131), 2)  # Ely.
	))
	features.append(GeographyFeature.new(
		"Thames Estuary Marshes", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(87, 149), 1)  # Isle of Sheppey / North Kent Marshes.
	))

	# --- Granular Soil Fertility baselines ------------------------------------
	features.append(GeographyFeature.new(
		"Cheshire Plain", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(76, 122), 2)  # Nantwich.
	))
	features.append(GeographyFeature.new(
		"Midlands Farmland", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(80, 131), 2)  # Warwickshire.
	))
	features.append(GeographyFeature.new(
		"Industrial Slag Heaps", GeographyFeature.FeatureType.INDUSTRIAL_BLIGHT,
		HexCoord.hex_disk(Vector2i(81, 117), 1)  # Oldham/Rochdale, NE of Manchester.
	))

	return features
