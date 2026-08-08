class_name BritishGeographyData
extends RefCounted

## Seed data for the playable map. **Expanded, user request: "ensure our
## hex tile map is representative of the entire UK and Ireland."** Was
## previously a small (40x28) stylized approximation of just the
## Manchester -> Midlands -> London corridor with no coastline at all — the
## whole bounding rectangle WAS land, by construction, since nothing
## outside England's story-relevant corridor existed yet. Grown roughly
## 4-5x per axis to a real-scale bounding box for the whole of Great
## Britain and Ireland (at the existing 5x5-mile/hex scale: real GB+Ireland
## spans roughly 600 miles north-south and 500 miles east-west at their
## combined widest, i.e. ~120x100 hexes — MAP_BOUNDS below adds margin
## around that for the surrounding sea).
##
## Relative compass geography is preserved (Scotland north, Wales bulging
## west of the Midlands, Cornwall's SW tail, East Anglia's eastward bulge,
## Ireland west across the Irish Sea, etc.) but — **same convention this
## class's own header already established for the original corridor,
## explicitly not re-litigated, just extended to the whole country** — hex
## placements are hand-authored by relative-compass feel for gameplay, NOT
## derived from real survey/GIS coordinate data. This is a first-pass
## stylized approximation; like every other visual system in this project
## that can't be confirmed in this headless environment, its actual
## on-screen silhouette hasn't been visually verified by a human yet.
##
## **Decided, this pass: Wales, Scotland and Ireland get landmass (so the
## map's own silhouette/scale is correct and Phase 7.2.1's future region
## lock has real geography to lock) but NOT real named content** — no
## rivers, mountain ranges or settlements of their own. They generate as
## plain open moorland (the same default the England corridor's own
## unclaimed countryside already uses), with the existing soil-fertility
## noise pass still giving them some texture variety for free. Authoring
## their own Highland/Snowdonia terrain identity and named settlements
## stays Phase 7.4/7.5's own future job, not redone here — same "region is
## locked/inaccessible until much later anyway" reasoning already
## established for why that content doesn't exist yet.

const MAP_BOUNDS := Rect2i(-10, -10, 120, 120)

## The landmass silhouette itself — Great Britain's mainland plus Ireland,
## as a union of "spine" auras (same `hex_disk()`-union technique Chat
## Moss/The Fens already use for a single wetland, just walked along a
## whole coastline's worth of `hex_line()` segments instead of sitting at
## one point) plus a handful of standalone bulge disks for features an
## open spine can't reach on its own (Wales, East Anglia, Kent, SW
## Scotland). `HexMapGenerator`'s base layer reads this to decide OCEAN vs.
## MOORLAND before any named feature stamps get applied on top.
##
## **Verified computationally, not visually** (this headless environment
## can't screenshot/render — same limitation flagged throughout this
## project's own history for terrain/building art and continuous
## movement). A real bug this method's own numbers would otherwise have
## shipped with: Wales' bulge and Ireland's original Dublin anchor summed
## their radii to EXACTLY the hex-distance between their centers (9+7=16),
## meaning zero actual sea gap — the Irish Sea would have silently fused
## Wales to Ireland into one landmass. Found and fixed only because a
## temporary self-test (reverted before commit) checked specific probe
## points inside the Irish Sea/North Channel gaps directly, not just "is
## Wales land" and "is Dublin land" in isolation — two landmasses can each
## independently look correct while still touching where they shouldn't.
static func get_landmass_hexes() -> Dictionary:
	var land: Dictionary = {}  # Vector2i -> true

	# Great Britain — a single open spine from the north Scottish coast down
	# to Cornwall's tip, each anchor (q, r, radius) in that order.
	var great_britain: Array[Vector3i] = [
		Vector3i(68, 2, 7),    # North coast (John o'Groats area).
		Vector3i(68, 10, 8),   # Inverness / NE Highlands.
		Vector3i(78, 18, 6),   # Aberdeen.
		Vector3i(65, 22, 8),   # Perth / central Scotland.
		Vector3i(64, 28, 9),   # Edinburgh / Glasgow belt.
		Vector3i(64, 34, 7),   # Southern Uplands / Borders.
		Vector3i(62, 40, 8),   # Cumbria / Lake District.
		Vector3i(62, 48, 9),   # Manchester / Lancashire.
		Vector3i(66, 58, 10),  # Midlands (Birmingham).
		Vector3i(70, 66, 9),   # Oxfordshire.
		Vector3i(78, 72, 10),  # London / Home Counties.
		Vector3i(75, 80, 8),   # Sussex / south coast.
		Vector3i(65, 82, 7),   # Dorset.
		Vector3i(55, 86, 6),   # Devon.
		Vector3i(42, 90, 5),   # Cornwall (tip).
	]
	_landmass_from_spine(great_britain, land)

	# Bulges the open spine above doesn't reach on its own — real
	# geography that sits well off to one side rather than along the
	# spine's own north-south line.
	_union_disk(land, Vector2i(48, 52), 9)   # Wales.
	_union_disk(land, Vector2i(92, 62), 8)   # East Anglia.
	_union_disk(land, Vector2i(90, 76), 6)   # Kent.
	_union_disk(land, Vector2i(52, 30), 6)   # SW Scotland / Kintyre.

	# Ireland — a closed loop of coastal anchors (the last entry repeats the
	# first, closing it) rather than an open spine: Ireland reads as a
	# rounded landmass, not an elongated one, so a perimeter loop of
	# overlapping disks fills in correctly. One extra central disk
	# guarantees the loop's own interior is fully covered rather than
	# relying solely on perimeter overlap.
	var ireland: Array[Vector3i] = [
		Vector3i(18, 32, 7),   # Donegal (NW).
		Vector3i(10, 42, 7),   # Sligo / Mayo.
		Vector3i(6, 52, 7),    # Galway (W bulge).
		Vector3i(10, 62, 6),   # Shannon / Limerick.
		Vector3i(2, 72, 5),    # Kerry (SW peninsula tip).
		Vector3i(16, 74, 6),   # Cork (S).
		Vector3i(28, 68, 6),   # Waterford / Wexford (SE).
		Vector3i(28, 54, 6),   # Dublin (E) — kept a real Irish Sea gap from Wales; see this class's own verification note below.
		Vector3i(30, 36, 6),   # Antrim / Belfast (NE, facing Scotland).
		Vector3i(18, 32, 7),   # Back to Donegal — closes the loop.
	]
	_landmass_from_spine(ireland, land)
	_union_disk(land, Vector2i(18, 54), 10)  # Central Ireland.

	return land

## Connects consecutive spine anchors with `HexCoord.hex_line()` and unions
## a `hex_disk()` of the (linearly interpolated between anchors) radius at
## every hex along that line into `into`. `Vector3i(q, r, radius)` per
## anchor — GDScript has no named-tuple type, and a 4th parallel array
## would be easier to accidentally desync than packing radius into the
## same value.
static func _landmass_from_spine(spine: Array[Vector3i], into: Dictionary) -> void:
	for i in range(spine.size() - 1):
		var a := spine[i]
		var b := spine[i + 1]
		var line := HexCoord.hex_line(Vector2i(a.x, a.y), Vector2i(b.x, b.y))
		for j in range(line.size()):
			var t := float(j) / float(maxi(line.size() - 1, 1))
			var radius := int(round(lerpf(float(a.z), float(b.z), t)))
			_union_disk(into, line[j], radius)

static func _union_disk(into: Dictionary, center: Vector2i, radius: int) -> void:
	for coord in HexCoord.hex_disk(center, radius):
		into[coord] = true

static func get_features() -> Array[GeographyFeature]:
	return _build_features()

static func _build_features() -> Array[GeographyFeature]:
	var features: Array[GeographyFeature] = []

	# --- Settlements -----------------------------------------------------
	var manchester_center := Vector2i(62, 48)
	var manchester_hexes: Array[Vector2i] = [
		manchester_center,
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[3],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[4],
		manchester_center + HexCoord.NEIGHBOR_DIRECTIONS[5],
	]
	features.append(GeographyFeature.new("Manchester", GeographyFeature.FeatureType.SETTLEMENT, manchester_hexes))

	var birmingham_hexes: Array[Vector2i] = HexCoord.hex_disk(Vector2i(66, 58), 1).slice(0, 4)
	features.append(GeographyFeature.new("Birmingham", GeographyFeature.FeatureType.SETTLEMENT, birmingham_hexes))

	var london_center := Vector2i(78, 72)
	var london_hexes: Array[Vector2i] = [london_center]
	london_hexes.append_array(HexCoord.hex_ring(london_center, 1))
	london_hexes.append_array(HexCoord.hex_ring(london_center, 2).slice(0, 5))
	features.append(GeographyFeature.new("Greater London", GeographyFeature.FeatureType.SETTLEMENT, london_hexes))

	# --- Elevated Terrain & Natural Barriers ------------------------------
	features.append(GeographyFeature.new(
		"Pennine Chain / Peak District", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(64, 38), Vector2i(63, 50))
	))
	features.append(GeographyFeature.new(
		"Chiltern Hills", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(72, 68), Vector2i(77, 71))
	))
	features.append(GeographyFeature.new(
		"Cotswold Escarpment", GeographyFeature.FeatureType.MOUNTAIN_RANGE,
		HexCoord.hex_line(Vector2i(62, 62), Vector2i(68, 66))
	))

	# --- Major Waterways & Canals ------------------------------------------
	features.append(GeographyFeature.new(
		"River Mersey", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(56, 49), Vector2i(62, 48))
	))

	var manchester_ship_canal := GeographyFeature.new(
		"Manchester Ship Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(62, 48), Vector2i(57, 49))
	)
	manchester_ship_canal.waterway_is_canal = true
	features.append(manchester_ship_canal)

	features.append(GeographyFeature.new(
		"River Trent", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(66, 58), Vector2i(78, 52))
	))

	features.append(GeographyFeature.new(
		"River Thames", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(70, 66), Vector2i(86, 73))
	))

	var grand_union_canal := GeographyFeature.new(
		"Grand Union Canal", GeographyFeature.FeatureType.WATERWAY,
		HexCoord.hex_line(Vector2i(66, 58), Vector2i(78, 72))
	)
	grand_union_canal.waterway_is_canal = true
	features.append(grand_union_canal)

	# --- Swamps & Waterlogged Basins -----------------------------------------
	features.append(GeographyFeature.new(
		"Chat Moss", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(59, 48), 1)
	))
	features.append(GeographyFeature.new(
		"The Fens", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(84, 60), 2)
	))
	features.append(GeographyFeature.new(
		"Thames Estuary Marshes", GeographyFeature.FeatureType.WETLAND,
		HexCoord.hex_disk(Vector2i(88, 74), 1)
	))

	# --- Granular Soil Fertility baselines ------------------------------------
	features.append(GeographyFeature.new(
		"Cheshire Plain", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(60, 52), 2)
	))
	features.append(GeographyFeature.new(
		"Midlands Farmland", GeographyFeature.FeatureType.FARMLAND,
		HexCoord.hex_disk(Vector2i(68, 60), 2)
	))
	features.append(GeographyFeature.new(
		"Industrial Slag Heaps", GeographyFeature.FeatureType.INDUSTRIAL_BLIGHT,
		HexCoord.hex_disk(Vector2i(63, 46), 1)
	))

	return features
