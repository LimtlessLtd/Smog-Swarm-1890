class_name GeographyFeature
extends Resource

## A named real-world-inspired feature (a settlement, a mountain chain, a
## river...) stamped onto the base hex grid by HexMapGenerator. See
## BritishGeographyData for the actual seed list.

enum FeatureType {
	SETTLEMENT,
	MOUNTAIN_RANGE,
	WATERWAY,
	WETLAND,
	FARMLAND,
	INDUSTRIAL_BLIGHT,
}

@export var feature_name: String = ""
@export var feature_type: FeatureType = FeatureType.SETTLEMENT
@export var hex_coords: Array[Vector2i] = []
@export var waterway_is_canal: bool = false  ## Only meaningful when feature_type == WATERWAY.

func _init(p_name: String = "", p_type: FeatureType = FeatureType.SETTLEMENT, p_coords: Array[Vector2i] = []) -> void:
	feature_name = p_name
	feature_type = p_type
	hex_coords = p_coords
