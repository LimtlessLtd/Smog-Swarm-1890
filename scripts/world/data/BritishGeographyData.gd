class_name BritishGeographyData
extends RefCounted

## Seed data for the Phase 1 placeholder map: a stylized approximation of the
## Manchester -> Midlands -> London corridor described in the Phase 7
## campaign arc (Cottonopolis & Pennine Barrier -> Trent Valley & Fenland
## Corridors -> Thames Basin Citadel). Relative compass geography is
## preserved (Pennines north of Manchester, Fens east of the Trent Valley,
## Chilterns guarding London's approach, etc.) but hex placements are
## hand-authored for gameplay, NOT derived from real survey/GIS data.
## Swap this out for an imported dataset later if pixel-accurate geography
## is ever wanted.

const MAP_BOUNDS := Rect2i(0, 0, 40, 28)

static func get_features() -> Array[GeographyFeature]:
	var features: Array[GeographyFeature] = []

	# --- Settlements -----------------------------------------------------
	var manchester_center := Vector2i(6, 4)
	var manchester_hexes: Array[Vector2i] = [
		manchester_center,
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[3],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[4],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[5],
	]
	features.append(GeographyFeature.new("Manchester", GeographyFeature.FeatureType.SETTLEMENT, manchester_hexes))

	var birmingham_hexes: Array[Vector2i] = HexCoord.hex_disk(Vector2i(11, 13), 1).slice(0, 4)
	features.append(GeographyFeature.new("Birmingham", GeographyFeature.FeatureType.SETTLEMENT, birmingham_hexes))

	var london_center := Vector2i(29, 23)
	var london_hexes: Array[Vector2i] = [london_center]
	london_hexes.append_array(HexCoord.hex_ring(london_center, 1))
	london_hexes.append_array(HexCoord.hex_ring(london_center, 2).slice(0, 5))
	features.append(GeographyFeature.new("Greater London", GeographyFeature.FeatureType.SETTLEMENT, london_hexes))

	# --- Elevated Terrain & Natural Barriers ------------------------------
	features.append(GeographyFeature.new(
		"Pennine Chain / Peak District", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(8, 1), Vector2i(10, 9))
	))
	features.append(GeographyFeature.new(
		"Chiltern Hills", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(21, 18), Vector2i(27, 21))
	))
	features.append(GeographyFeature.new(
		"Cotswold Escarpment", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(13, 17), Vector2i(19, 19))
	))

	# --- Major Waterways & Canals ------------------------------------------
	features.append(GeographyFeature.new(
		"River Mersey", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(0, 5), Vector2i(6, 4))
	))

	var manchester_ship_canal := GeographyFeature.new(
		"Manchester Ship Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(6, 4), Vector2i(2, 6))
	)
	manchester_ship_canal.waterway_is_canal = true
	features.append(manchester_ship_canal)

	features.append(GeographyFeature.new(
		"River Trent", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(11, 13), Vector2i(20, 11))
	))

	features.append(GeographyFeature.new(
		"River Thames", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(18, 22), Vector2i(34, 24))
	))

	var grand_union_canal := GeographyFeature.new(
		"Grand Union Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(11, 13), Vector2i(29, 23))
	)
	grand_union_canal.waterway_is_canal = true
	features.append(grand_union_canal)

	# --- Swamps & Waterlogged Basins -----------------------------------------
	features.append(GeographyFeature.new(
		"Chat Moss", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(3, 3), 1)
	))
	features.append(GeographyFeature.new(
		"The Fens", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(24, 12), 2)
	))
	features.append(GeographyFeature.new(
		"Thames Estuary Marshes", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(35, 25), 1)
	))

	# --- Granular Soil Fertility baselines ------------------------------------
	features.append(GeographyFeature.new(
		"Cheshire Plain", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(4, 8), 2)
	))
	features.append(GeographyFeature.new(
		"Midlands Farmland", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(15, 14), 2)
	))
	features.append(GeographyFeature.new(
		"Industrial Slag Heaps", GeographyFeature.FeatureType.INDUSTRIAL_BLIGHT,
		HexCoord.hex_disk(Vector2i(7, 6), 1)
	))

	return features
