class_name TileCatalog
extends RefCounted

## Loads the Cytopia legacy TileData.json and exposes tiles, textures and
## sprite-strip regions to the engine.
##
## The legacy format stores sprites as horizontal strips:
##   frame i of a tile = Rect2((offset + i) * clip_width, 0, clip_width, clip_height)
## with `count` variants, optionally picked at random (`pickRandomTile`).

const TILE_DATA_PATH := "res://data/TileData.json"
const LEGACY_IMAGE_PREFIX := "res://assets/images/"

var _tiles: Dictionary = {}          # id -> tile dictionary
var _textures: Dictionary = {}       # file name -> Texture2D
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value if seed_value != 0 else hash("citopia")
	var file := FileAccess.open(TILE_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open %s" % TILE_DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Invalid TileData.json content")
		return
	for entry: Dictionary in parsed:
		if entry.has("id"):
			_tiles[entry["id"]] = entry


func tile_count() -> int:
	return _tiles.size()


func has_tile(id: String) -> bool:
	return _tiles.has(id)


func get_tile(id: String) -> Dictionary:
	return _tiles.get(id, {})


func get_ids_by_category(category: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in _tiles:
		if _tiles[id].get("category", "") == category:
			ids.append(id)
	ids.sort()
	return ids


## Returns the texture for a tile entry, loading it once.
func get_texture(tile: Dictionary) -> Texture2D:
	var file_name: String = tile.get("tiles", {}).get("fileName", "")
	if file_name.is_empty():
		return null
	if not _textures.has(file_name):
		var res_path := file_name.replace("resources/images/", LEGACY_IMAGE_PREFIX)
		_textures[file_name] = load(res_path)
	return _textures.get(file_name)


## Picks a stable variant index for a tile (random if the tile allows it).
## Store the result and pass it to get_region() so variants don't reshuffle
## on every redraw.
func pick_variant(tile: Dictionary) -> int:
	var tiles: Dictionary = tile.get("tiles", {})
	var count: int = int(tiles.get("count", 1))
	if tiles.get("pickRandomTile", false) and count > 1:
		return _rng.randi_range(0, count - 1)
	return 0


## Clip region for one variant of a tile.
## Strips are bottom-anchored: the clip sits at the BOTTOM of the sheet, the
## pixels above it are elevation headroom (legacy Sprite::refresh behavior).
func get_region(tile: Dictionary, texture_height: int, variant: int = 0) -> Rect2:
	var tiles: Dictionary = tile.get("tiles", {})
	var clip_w: int = int(tiles.get("clip_width", 32))
	var clip_h: int = int(tiles.get("clip_height", 16))
	var offset: int = int(tiles.get("offset", 0))
	var count: int = int(tiles.get("count", 1))
	variant = clampi(variant, 0, maxi(0, count - 1))
	var region_x := (offset + variant) * clip_w
	var region_y := maxi(0, texture_height - clip_h)
	return Rect2(region_x, region_y, clip_w, clip_h)


## Bottom-anchored draw rect so sprites stack upward from the tile base.
func get_draw_rect(region: Rect2, screen_pos: Vector2, tile_h: float) -> Rect2:
	return Rect2(screen_pos + Vector2(-region.size.x * 0.5, tile_h - region.size.y), region.size)
