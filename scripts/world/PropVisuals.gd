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
	return load(path) as Texture2D
