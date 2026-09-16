class_name PropVisuals
extends RefCounted

## Lazily-loaded, cached lookup for real prop-species art (see
## `assets/props/README.md`) — same `ResourceLoader.exists()`-gated-null
## pattern every other `*Visuals.gd` in this project follows. Only
## consulted at MEDIUM/HIGH Tactical fidelity — LOW's uniform blob
## (`TacticalHexView._low_fidelity_blob()`) stays 100% procedural
## regardless of art, same "LOW never differentiates by type" call this
## project already made for units (`TacticalEntityLayer`) and zombies
## (`ZombieVisuals`).
##
## **Cropped to the prop's own ink, not to its render frame**, for the reason
## `UnitVisuals` records: `TerrainDetailView` sizes each prop by dividing
## `PROP_DIAMETER` by the texture's longest axis, so an unfitted frame draws
## the prop short. Props were never run through
## `render_common.frame_content()` — measured fill is 85.0% x 80.4% for
## `tree.png` and 57.1% x 48.8% for `rock.png`, so a rock was drawn at 57% of
## the diameter asked for. Mild next to the 22.3% a zombie frame carries, and
## the same one-line fix. `tight_crop_copy()` rather than `tight_crop()`
## because this feeds a MultiMesh, which drops an AtlasTexture's region.

static var _texture_cache: Dictionary = {}  # GameEnums.PropType -> Texture2D (nullable)

static func prop_texture(prop_type: GameEnums.PropType) -> Texture2D:
	if not _texture_cache.has(prop_type):
		_texture_cache[prop_type] = _load_texture(prop_type)
	return _texture_cache[prop_type]

## Matches assets/props/<key>.png exactly — see that folder's own file list.
static func _texture_key(prop_type: GameEnums.PropType) -> String:
	match prop_type:
		GameEnums.PropType.TREE:
			return "tree"
		GameEnums.PropType.BUSH:
			return "bush"
		GameEnums.PropType.ROCK:
			return "rock"
		GameEnums.PropType.REED:
			return "reed"
		_:
			return ""

static func _load_texture(prop_type: GameEnums.PropType) -> Texture2D:
	var key := _texture_key(prop_type)
	if key.is_empty():
		return null
	var path := "res://assets/props/%s.png" % key
	if not ResourceLoader.exists(path):
		return null
	return TextureCropUtil.tight_crop_copy(load(path) as Texture2D)
