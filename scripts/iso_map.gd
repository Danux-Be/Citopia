class_name IsoMap
extends Node2D

## Isometric terrain map built from the legacy Cytopia tile database.
## v0: elevation-free terrain with biomes from noise (grass, mint grass,
## forest ground, sand beaches, water).

const TILE_W := 32
const TILE_H := 16

const MAP_SIZE := 96

@export var map_size: int = MAP_SIZE

var _catalog: TileCatalog
var _cells: Array[Dictionary] = []    # flat array [x + y * map_size] -> { id: String, variant: int }
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260829
	_catalog = TileCatalog.new()
	generate_map()


func generate_map() -> void:
	var elevation := FastNoiseLite.new()
	elevation.seed = 1234
	elevation.frequency = 0.045
	var moisture := FastNoiseLite.new()
	moisture.seed = 5678
	moisture.frequency = 0.07

	_cells.clear()
	_cells.resize(map_size * map_size)

	for y in map_size:
		for x in map_size:
			var e := elevation.get_noise_2d(x, y)
			var m := moisture.get_noise_2d(x, y)
			var id := _pick_terrain(e, m)
			_cells[x + y * map_size] = {"id": id, "variant": -1}

	queue_redraw()


func _pick_terrain(elevation: float, moisture: float) -> String:
	if elevation < -0.32:
		return "water"
	if elevation < -0.24:
		return "terrain_sand_beach"
	if moisture > 0.42:
		return "terrain_grass_forest"
	if moisture < -0.42:
		return "terrain_grass_mint"
	return "terrain_grass"


func iso_to_screen(x: int, y: int) -> Vector2:
	return Vector2((x - y) * TILE_W * 0.5, (x + y) * TILE_H * 0.5)


func screen_to_iso(screen_pos: Vector2) -> Vector2i:
	var fx := screen_pos.x / (TILE_W * 0.5)
	var fy := screen_pos.y / (TILE_H * 0.5)
	var ix := floorf((fy + fx) * 0.5)
	var iy := floorf((fy - fx) * 0.5)
	return Vector2i(ix, iy)


func _draw() -> void:
	if _catalog == null or _cells.is_empty():
		return

	# Painter's algorithm: draw diagonals (x + y) in ascending order.
	for sum in range(0, 2 * map_size - 1):
		var x_start := maxi(0, sum - map_size + 1)
		var x_end := mini(sum, map_size - 1)
		for x in range(x_start, x_end + 1):
			var y := sum - x
			var cell: Dictionary = _cells[x + y * map_size]
			var tile: Dictionary = _catalog.get_tile(cell["id"])
			if tile.is_empty():
				continue
			var texture := _catalog.get_texture(tile)
			if texture == null:
				continue
			var region := _catalog.get_region(tile, texture.get_height())
			var screen_pos := iso_to_screen(x, y)
			draw_texture_rect_region(
				texture,
				_catalog.get_draw_rect(region, screen_pos, TILE_H),
				region
			)
