class_name DistrictPartitioner
extends RefCounted

## Assigns each HexCell its sub-district breakdown ("District & Frontline
## Partitioning" — design doc). Baseline rules are intentionally simple —
## settlement hexes get a safe civic/industrial core plus a contested
## wilderness fringe, everything else starts fully contested — and are
## meant to be driven by real combat/clearing systems once those exist.

func partition_cell(cell: HexCell) -> void:
	cell.districts.clear()
	if cell.is_settlement:
		cell.districts.append(District.new(GameEnums.DistrictType.URBAN_CENTER, false))
		cell.districts.append(District.new(GameEnums.DistrictType.INDUSTRIAL_ESTATE, false))
		cell.districts.append(District.new(GameEnums.DistrictType.UNCLEARED_WILDERNESS, true))
	else:
		cell.districts.append(District.new(GameEnums.DistrictType.UNCLEARED_WILDERNESS, true))
