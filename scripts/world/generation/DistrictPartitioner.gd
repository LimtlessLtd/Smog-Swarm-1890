class_name DistrictPartitioner
extends RefCounted

## Assigns each HexCell its sub-district breakdown (see design doc: "District
## & Frontline Partitioning"). Phase 1 baseline rules are intentionally
## simple — settlement hexes get a safe civic/industrial core plus a
## contested wilderness fringe, everything else starts fully contested — and
## are meant to be driven by real combat/clearing systems from Phase 3+.

func partition_cell(cell: HexCell) -> void:
	cell.districts.clear()
	if cell.is_settlement:
		cell.districts.append(District.new(GameEnums.DistrictType.URBAN_CENTER, false))
		cell.districts.append(District.new(GameEnums.DistrictType.INDUSTRIAL_ESTATE, false))
		cell.districts.append(District.new(GameEnums.DistrictType.UNCLEARED_WILDERNESS, true))
	else:
		cell.districts.append(District.new(GameEnums.DistrictType.UNCLEARED_WILDERNESS, true))
