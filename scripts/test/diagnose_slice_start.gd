extends Node

## Lists starting-settlement candidates for the vertical slice, measured off the
## real map: for every URBAN settlement hex, its ring-1 neighbours' capacities
## (D3's `total_zombie_pop`), the zombies D7's rings would seed there (25%), and
## the kills a clear would take (down to D2's 5% threshold). A clear is
## `0.20 * capacity` kills; the slice wants one in the low hundreds.
##
## Headless: Godot --headless res://scenes/test/diagnose_slice_start.tscn

func _ready() -> void:
	var map: HexGridMap = HexGridMap.new()
	add_child(map)
	if map.get_all_cells().is_empty():
		await map.generation_completed
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--around="):
			var parts := arg.get_slice("=", 1).split(",")
			_print_around(map, Vector2i(int(parts[0]), int(parts[1])))
			get_tree().quit(0)
			return
	var rows: Array = []
	for cell: HexCell in map.get_all_cells():
		if not cell.is_settlement:
			continue
		var neighbours: Array = []
		for n in HexCoord.neighbors(cell.coord):
			var nc := map.get_cell(n)
			if nc == null or not nc.is_passable():
				continue
			neighbours.append({"coord": n, "cap": nc.total_zombie_pop, "biome": GameEnums.BiomeType.keys()[nc.biome_type], "region": nc.region_name})
		var ring_caps := [0, 0, 0, 0, 0]
		for r in range(1, 5):
			for c in HexCoord.hex_ring(cell.coord, r):
				var rc := map.get_cell(c)
				if rc:
					ring_caps[r] += rc.total_zombie_pop
		var min_cap := 1 << 30
		for n in neighbours:
			min_cap = mini(min_cap, int(n["cap"]))
		rows.append({"coord": cell.coord, "region": cell.region_name, "biome": GameEnums.BiomeType.keys()[cell.biome_type], "cap": cell.total_zombie_pop, "min_neighbour_cap": min_cap, "neighbours": neighbours, "ring_caps": ring_caps})
	rows.sort_custom(func(a, b): return int(a["min_neighbour_cap"]) < int(b["min_neighbour_cap"]))
	print("SLICE-START candidates: %d settlement hexes" % rows.size())
	for row in rows:
		var ns := []
		for n in row["neighbours"]:
			ns.append("%s cap=%d %s %s" % [n["coord"], n["cap"], n["biome"], n["region"]])
		print("SLICE-START %s %s [%s] cap=%d ring_caps=%s min_n=%d | %s" % [row["coord"], row["region"], row["biome"], row["cap"], row["ring_caps"], row["min_neighbour_cap"], "; ".join(ns)])
	get_tree().quit(0)


## `--around=q,r`: every hex within 5 of a candidate start, with the residents D7's
## rings would seed there measured from that start, and the terrain a horde would
## cross — the pool a slice horde's source hex is picked from.
func _print_around(map: HexGridMap, start: Vector2i) -> void:
	for radius in range(1, 6):
		for coord in HexCoord.hex_ring(start, radius):
			var cell := map.get_cell(coord)
			if cell == null:
				continue
			var seeded := int(round(InfestationManager.RING_SEED_PERCENT[mini(radius, 4)] / 100.0 * float(cell.total_zombie_pop)))
			print("SLICE-AROUND d=%d %s cap=%d seeded=%d biome=%s feature=%s passable=%s elev=%.2f region=%s waterway=%s" % [radius, coord, cell.total_zombie_pop, seeded, GameEnums.BiomeType.keys()[cell.biome_type], GameEnums.TerrainFeature.keys()[cell.terrain_feature], cell.is_passable(), cell.elevation, cell.region_name, cell.waterway_name])
