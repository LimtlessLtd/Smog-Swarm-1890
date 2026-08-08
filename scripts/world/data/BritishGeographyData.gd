class_name BritishGeographyData
extends RefCounted

## Seed data for the playable map. **Landmass silhouette is now baked from
## real open geographic data, not hand-authored.** User feedback after
## seeing the previous hand-placed-anchor version in an actual screenshot:
## "that looks nothing like a hex tile map of the UK and Ireland, is it
## possible if you use some open source data like from Ordnance Survey."
##
## Source: Natural Earth's public-domain 10m-resolution Admin-0 Countries
## dataset (naturalearthdata.com), GBR + IRL features — chosen over Ordnance
## Survey's own OpenData layers because OS coverage stops at the GB
## coastline (no Northern Ireland/Ireland border data, no Ireland at all),
## and this project needs one consistent dataset for both islands. Natural
## Earth 10m is the standard free/open substitute GIS users reach for
## exactly this gap; it's public domain (no attribution required, though
## credited here anyway) and, at 7,113 points across GB's 57 sub-polygons
## (mainland + Hebrides + Orkney + Shetland + Isle of Wight + Anglesey, etc.)
## and 2,394 points across Ireland's 7, resolves real coastline detail well
## past what a ~5-6mi/hex grid can even display.
##
## **Baking pipeline (offline, one-time — not run by the game itself):**
## 1. Downloaded GBR/IRL features from Natural Earth's 10m countries GeoJSON.
## 2. Projected lon/lat to a local equirectangular plane, longitude scaled by
##    cos(mean_latitude) so East-West distance isn't stretched relative to
##    North-South (uncorrected equirectangular would visibly fatten the
##    country at this latitude).
## 3. Fit that projected plane to hex axial space with a single uniform
##    scale (same factor on both axes — preserves the real aspect ratio,
##    doesn't shear or stretch the silhouette) plus a centering offset, sized
##    so the real landmass occupies MAP_BOUNDS with a ~6-hex sea margin.
## 4. For every hex in MAP_BOUNDS, sampled its center + 6 corners, converted
##    each sample back to the projected plane, and ran even-odd
##    point-in-polygon against every GBR/IRL sub-polygon (bbox-prefiltered
##    for speed). A hex is LAND if >=4 of its 7 samples land inside any
##    sub-polygon — smooths single-sample noise without eroding real
##    features (Isle of Wight/Anglesey/Isle of Man-scale islands still
##    resolve to real hexes at this grid's resolution).
## 5. Named settlements/features below use the exact same projection to turn
##    real lon/lat (Manchester, London, the Pennines, real river mouths,
##    etc.) into hex coordinates, so they now sit in their real positions
##    relative to the real coastline — not just relative-compass placement.
##    Any anchor whose exact rounded hex missed land (coastal cities right at
##    the shoreline sometimes round to the water-side hex) was snapped to the
##    nearest actual land hex by ring search; verified computationally (not
##    visually — this headless environment still can't screenshot/render)
##    that all twelve major-city anchors and every feature anchor below
##    landed on real LAND hexes after snapping.
##
## The result is still a HEX-GRID silhouette, not a survey-accurate
## coastline — at ~6 real miles per hex, narrow estuaries, small headlands
## and individual skerries don't resolve, the same resolution limit any
## hex/tile strategy game's real-world map has (Civilization's Earth maps,
## for instance). What changed is the SOURCE: every hex's land/ocean status
## and every named feature's position now traces back to real coordinates,
## not a hand-picked approximation.
const MAP_BOUNDS := Rect2i(-10, -10, 120, 120)

## Run-length-encoded per-row land data baked by the pipeline above:
## `[r, [Vector2i(q_start, q_end_inclusive), ...]]` per row that has any
## land. Kept RLE rather than a flat hex list — real coastlines are mostly
## contiguous horizontal runs per row, so this compresses ~2,066 land hexes
## into 187 spans across 95 rows, and expands trivially back into the same
## `Vector2i -> true` Dictionary shape every other system here already
## expects from `get_landmass_hexes()`.
const _LAND_RLE: Array = [
	[-2, [Vector2i(94, 94)]],
	[-1, [Vector2i(91, 93)]],
	[0, [Vector2i(91, 92)]],
	[1, [Vector2i(91, 91)]],
	[2, [Vector2i(89, 90)]],
	[3, [Vector2i(90, 90)]],
	[4, [Vector2i(89, 89)]],
	[13, [Vector2i(76, 76)]],
	[14, [Vector2i(75, 75)]],
	[15, [Vector2i(74, 74)]],
	[18, [Vector2i(71, 71), Vector2i(73, 73)]],
	[19, [Vector2i(64, 73)]],
	[20, [Vector2i(57, 57), Vector2i(63, 72)]],
	[21, [Vector2i(55, 56), Vector2i(62, 71)]],
	[22, [Vector2i(54, 55), Vector2i(61, 69)]],
	[23, [Vector2i(52, 54), Vector2i(61, 68)]],
	[24, [Vector2i(52, 54), Vector2i(60, 66)]],
	[25, [Vector2i(51, 52), Vector2i(59, 65)]],
	[26, [Vector2i(51, 51), Vector2i(57, 65)]],
	[27, [Vector2i(56, 64), Vector2i(68, 68)]],
	[28, [Vector2i(48, 48), Vector2i(53, 53), Vector2i(56, 74)]],
	[29, [Vector2i(47, 47), Vector2i(51, 53), Vector2i(55, 74)]],
	[30, [Vector2i(50, 53), Vector2i(55, 73)]],
	[31, [Vector2i(46, 46), Vector2i(51, 53), Vector2i(55, 72)]],
	[32, [Vector2i(46, 46), Vector2i(52, 71)]],
	[33, [Vector2i(54, 70)]],
	[34, [Vector2i(53, 69)]],
	[35, [Vector2i(52, 69)]],
	[36, [Vector2i(51, 68)]],
	[37, [Vector2i(50, 67)]],
	[38, [Vector2i(49, 51), Vector2i(53, 66)]],
	[39, [Vector2i(49, 49), Vector2i(52, 64)]],
	[40, [Vector2i(48, 49), Vector2i(51, 63)]],
	[41, [Vector2i(50, 64)]],
	[42, [Vector2i(50, 62)]],
	[43, [Vector2i(49, 60)]],
	[44, [Vector2i(47, 47), Vector2i(49, 59), Vector2i(62, 63)]],
	[45, [Vector2i(45, 46), Vector2i(48, 64)]],
	[46, [Vector2i(44, 45), Vector2i(48, 48), Vector2i(51, 64)]],
	[47, [Vector2i(43, 44), Vector2i(47, 48), Vector2i(51, 64)]],
	[48, [Vector2i(46, 48), Vector2i(51, 65)]],
	[49, [Vector2i(46, 46), Vector2i(48, 48), Vector2i(51, 65)]],
	[50, [Vector2i(45, 45), Vector2i(50, 64)]],
	[51, [Vector2i(36, 37), Vector2i(49, 64)]],
	[52, [Vector2i(33, 33), Vector2i(35, 37), Vector2i(39, 42), Vector2i(48, 64)]],
	[53, [Vector2i(31, 33), Vector2i(35, 41), Vector2i(47, 63)]],
	[54, [Vector2i(30, 41), Vector2i(46, 53), Vector2i(55, 63)]],
	[55, [Vector2i(30, 41), Vector2i(45, 51), Vector2i(54, 63)]],
	[56, [Vector2i(28, 41), Vector2i(48, 48), Vector2i(50, 50), Vector2i(53, 63)]],
	[57, [Vector2i(27, 41), Vector2i(52, 63)]],
	[58, [Vector2i(29, 41), Vector2i(52, 64)]],
	[59, [Vector2i(28, 40), Vector2i(51, 65)]],
	[60, [Vector2i(27, 40), Vector2i(51, 65)]],
	[61, [Vector2i(19, 22), Vector2i(26, 39), Vector2i(51, 65)]],
	[62, [Vector2i(18, 37), Vector2i(51, 51), Vector2i(53, 65)]],
	[63, [Vector2i(18, 36), Vector2i(53, 65)]],
	[64, [Vector2i(17, 34), Vector2i(52, 64)]],
	[65, [Vector2i(19, 34), Vector2i(51, 64)]],
	[66, [Vector2i(17, 34), Vector2i(50, 64)]],
	[67, [Vector2i(16, 33), Vector2i(50, 63)]],
	[68, [Vector2i(15, 33), Vector2i(49, 63)]],
	[69, [Vector2i(14, 33), Vector2i(49, 63)]],
	[70, [Vector2i(16, 32), Vector2i(41, 41), Vector2i(47, 63)]],
	[71, [Vector2i(16, 16), Vector2i(18, 32), Vector2i(40, 63)]],
	[72, [Vector2i(18, 31), Vector2i(41, 63)]],
	[73, [Vector2i(16, 31), Vector2i(40, 62)]],
	[74, [Vector2i(15, 31), Vector2i(39, 61), Vector2i(64, 66)]],
	[75, [Vector2i(15, 30), Vector2i(38, 38), Vector2i(40, 60), Vector2i(63, 67)]],
	[76, [Vector2i(14, 29), Vector2i(40, 67)]],
	[77, [Vector2i(13, 28), Vector2i(40, 67)]],
	[78, [Vector2i(12, 28), Vector2i(39, 67)]],
	[79, [Vector2i(11, 27), Vector2i(39, 66)]],
	[80, [Vector2i(10, 26), Vector2i(38, 65)]],
	[81, [Vector2i(7, 25), Vector2i(37, 64)]],
	[82, [Vector2i(7, 22), Vector2i(34, 64)]],
	[83, [Vector2i(7, 19), Vector2i(33, 63)]],
	[84, [Vector2i(6, 17), Vector2i(31, 61)]],
	[85, [Vector2i(5, 15), Vector2i(31, 61)]],
	[86, [Vector2i(6, 13), Vector2i(30, 59)]],
	[87, [Vector2i(8, 11), Vector2i(30, 30), Vector2i(34, 58)]],
	[88, [Vector2i(8, 9), Vector2i(36, 38), Vector2i(40, 57)]],
	[89, [Vector2i(36, 37), Vector2i(40, 57)]],
	[90, [Vector2i(38, 59)]],
	[91, [Vector2i(33, 34), Vector2i(37, 58)]],
	[92, [Vector2i(31, 57)]],
	[93, [Vector2i(30, 55)]],
	[94, [Vector2i(29, 54)]],
	[95, [Vector2i(28, 48), Vector2i(50, 52)]],
	[96, [Vector2i(27, 40), Vector2i(43, 44)]],
	[97, [Vector2i(26, 32), Vector2i(37, 37), Vector2i(39, 39)]],
	[98, [Vector2i(25, 31)]],
	[99, [Vector2i(24, 30)]],
	[100, [Vector2i(23, 24), Vector2i(28, 29)]],
	[101, [Vector2i(21, 23)]],
	[102, [Vector2i(19, 21)]],
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
	var manchester_center := Vector2i(52, 69)
	var manchester_hexes: Array[Vector2i] = [
		manchester_center,
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[3],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[4],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[5],
	]
	features.append(GeographyFeature.new("Manchester", GeographyFeature.FeatureType.SETTLEMENT, manchester_hexes))

	var birmingham_hexes: Array[Vector2i] = HexCoord.hex_disk(Vector2i(49, 79), 1).slice(0, 4)
	features.append(GeographyFeature.new("Birmingham", GeographyFeature.FeatureType.SETTLEMENT, birmingham_hexes))

	var london_center := Vector2i(53, 88)
	var london_hexes: Array[Vector2i] = [london_center]
	london_hexes.append_array(HexCoord.hex_ring(london_center, 1))
	london_hexes.append_array(HexCoord.hex_ring(london_center, 2).slice(0, 5))
	features.append(GeographyFeature.new("Greater London", GeographyFeature.FeatureType.SETTLEMENT, london_hexes))

	# --- Elevated Terrain & Natural Barriers --------------------------------
	features.append(GeographyFeature.new(
		"Pennine Chain / Peak District", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(59, 54), Vector2i(54, 70))  # Cumbria/Borders -> Peak District.
	))
	features.append(GeographyFeature.new(
		"Chiltern Hills", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(48, 88), Vector2i(53, 84))  # Goring -> Luton/Dunstable.
	))
	features.append(GeographyFeature.new(
		"Cotswold Escarpment", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(41, 90), Vector2i(47, 83))  # Bath -> Chipping Campden.
	))

	# --- Major Waterways & Canals -------------------------------------------
	features.append(GeographyFeature.new(
		"River Mersey", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(48, 70), Vector2i(52, 69))  # Mersey Estuary -> Manchester.
	))

	var manchester_ship_canal := GeographyFeature.new(
		"Manchester Ship Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(52, 69), Vector2i(48, 70))  # Manchester -> Mersey Estuary.
	)
	manchester_ship_canal.waterway_is_canal = true
	features.append(manchester_ship_canal)

	features.append(GeographyFeature.new(
		"River Trent", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(51, 72), Vector2i(61, 66))  # Stoke -> Humber mouth.
	))

	features.append(GeographyFeature.new(
		"River Thames", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(44, 87), Vector2i(57, 88))  # Thames Head -> Estuary.
	))

	var grand_union_canal := GeographyFeature.new(
		"Grand Union Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(49, 79), Vector2i(52, 88))  # Birmingham -> London Paddington.
	)
	grand_union_canal.waterway_is_canal = true
	features.append(grand_union_canal)

	# --- Swamps & Waterlogged Basins -----------------------------------------
	features.append(GeographyFeature.new(
		"Chat Moss", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(51, 69), 1)
	))
	features.append(GeographyFeature.new(
		"The Fens", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(59, 78), 2)  # Ely.
	))
	features.append(GeographyFeature.new(
		"Thames Estuary Marshes", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(57, 89), 1)  # Isle of Sheppey / North Kent Marshes.
	))

	# --- Granular Soil Fertility baselines ------------------------------------
	features.append(GeographyFeature.new(
		"Cheshire Plain", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(49, 72), 2)  # Nantwich.
	))
	features.append(GeographyFeature.new(
		"Midlands Farmland", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(52, 77), 2)  # Warwickshire.
	))
	features.append(GeographyFeature.new(
		"Industrial Slag Heaps", GeographyFeature.FeatureType.INDUSTRIAL_BLIGHT,
		HexCoord.hex_disk(Vector2i(53, 68), 1)  # Oldham/Rochdale, NE of Manchester.
	))

	return features
