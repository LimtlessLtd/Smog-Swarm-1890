extends SceneTree

## Checks whether HexCoord.corner_points()[i]/[i+1] (the edge _seed_boundary_edge()
## draws a wall/gate along for direction_index i) actually faces
## HexCoord.NEIGHBOR_DIRECTIONS[i] (the neighbor seed_starting_defenses() is
## walling FOR at that same i) -- suspected mismatch found while diagnosing
## the "Outrider cannot find a route" report (2026-08-20).
##
## Run: Godot_v4.7.1-stable_win64_console.exe --headless -s scripts/test/check_corner_neighbor_alignment.gd

func _init() -> void:
	var center := Vector2.ZERO
	var corners := HexCoord.corner_points(center)
	for i in 6:
		var neighbor_coord: Vector2i = HexCoord.NEIGHBOR_DIRECTIONS[i]
		var neighbor_world := HexCoord.axial_to_world(neighbor_coord)
		var neighbor_angle := rad_to_deg(neighbor_world.angle())

		var k := (6 - i) % 6
		var edge_mid := (corners[k] + corners[(k + 1) % 6]) * 0.5
		var edge_angle := rad_to_deg(edge_mid.angle())

		print("direction_index %d: NEIGHBOR_DIRECTIONS[%d]=%s at world angle %.1f deg | FIXED corner[%d]-corner[%d] midpoint at world angle %.1f deg | match=%s" % [
			i, i, neighbor_coord, neighbor_angle, k, (k + 1) % 6, edge_angle, absf(wrapf(neighbor_angle - edge_angle, -180.0, 180.0)) < 1.0])
	quit(0)
