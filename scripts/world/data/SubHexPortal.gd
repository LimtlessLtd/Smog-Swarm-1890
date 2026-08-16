class_name SubHexPortal
extends RefCounted

## One passable crossing point between two adjacent macro-hex clusters at
## sub-hex (30m) resolution — the node type Sub-Hex Mechanical Layer Phase
## 1c's abstract graph connects (todo.md, [[sub-hex-mechanical-layer-epic]]
## memory). A shared hex boundary can have zero portals (the whole edge is
## impassable — a marsh/cliff seam) or several (a passable edge broken into
## separate crossable stretches by an impassable patch in the middle) —
## SubHexPortalGraph.find_portals() collapses each contiguous passable run
## into exactly one of these, at the run's own midpoint, mirroring classic
## HPA*'s "one entrance = one node" simplification.

var hex_a: Vector2i
var hex_b: Vector2i
var sub_index_a: Vector2i  ## This portal's sub-cell address resolved against hex_a.
var sub_index_b: Vector2i  ## The SAME world location resolved against hex_b — not numerically mirrored, since each hex's own SUB_HEX_GRID_N indexing has its own local origin.
var world_pos: Vector2     ## Exact world position both sub_index_a/b were resolved from.

func _init(p_hex_a: Vector2i, p_hex_b: Vector2i, p_sub_index_a: Vector2i, p_sub_index_b: Vector2i, p_world_pos: Vector2) -> void:
	hex_a = p_hex_a
	hex_b = p_hex_b
	sub_index_a = p_sub_index_a
	sub_index_b = p_sub_index_b
	world_pos = p_world_pos
