class_name IsoMap
extends Node2D

## Isometric map built from the legacy Cytopia tile database.
## v2: terrain + an object layer (buildings, flora, roads...), tile hover,
## placement with multi-cell footprints and a bulldozer.

const TILE_W := 32
const TILE_H := 16

## Pseudo tool id for the bulldozer (not a real tile from the database).
const DOZER := "&dozer"

@export var map_size: int = 96

var catalog: TileCatalog
var hovered := Vector2i(-1, -1)
var selected_tool := ""      # tile id, DOZER, or "" (no tool)

var _cells: Array[Cell] = []
var _hover_valid := false
var _rng := RandomNumberGenerator.new()


class Cell:
	var terrain := ""            # terrain tile id
	var terrain_variant := 0
	var obj := ""                # object tile id covering this cell ("" = none)
	var obj_variant := 0
	var obj_origin := Vector2i() # origin cell of the object covering this cell
	var obj_size := Vector2i.ONE # footprint of that object


func _ready() -> void:
	_rng.seed = 20260829
	catalog = TileCatalog.new()
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
			var cell := Cell.new()
			cell.terrain = _pick_terrain(elevation.get_noise_2d(x, y), moisture.get_noise_2d(x, y))
			cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
			_cells[x + y * map_size] = cell

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


# -- Geometry ------------------------------------------------------------

func iso_to_screen(x: float, y: float) -> Vector2:
	return Vector2((x - y) * TILE_W * 0.5, (x + y) * TILE_H * 0.5)


func screen_to_iso(screen_pos: Vector2) -> Vector2i:
	var fx := screen_pos.x / (TILE_W * 0.5)
	var fy := screen_pos.y / (TILE_H * 0.5)
	var ix := floorf((fy + fx) * 0.5)
	var iy := floorf((fy - fx) * 0.5)
	return Vector2i(ix, iy)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size and cell.y < map_size


func _cell(cell: Vector2i) -> Cell:
	return _cells[cell.x + cell.y * map_size]


# -- Building ------------------------------------------------------------

static func tile_size(tile: Dictionary) -> Vector2i:
	var required: Dictionary = tile.get("RequiredTiles", {})
	return Vector2i(int(required.get("width", 1)), int(required.get("height", 1)))


static func _covers_terrain(tile: Dictionary, terrain_id: String) -> bool:
	if terrain_id == "water":
		return bool(tile.get("placeOnWater", false))
	return bool(tile.get("placeOnGround", true))


func can_place(tile_id: String, origin: Vector2i) -> bool:
	var tile := catalog.get_tile(tile_id)
	if tile.is_empty() or not in_bounds(origin):
		return false
	var size := tile_size(tile)
	for dx in size.x:
		for dy in size.y:
			var cell_pos := origin + Vector2i(dx, dy)
			if not in_bounds(cell_pos):
				return false
			var cell := _cell(cell_pos)
			if cell.obj != "":
				return false
			if not _covers_terrain(tile, cell.terrain):
				return false
	return true


func place(tile_id: String, origin: Vector2i) -> bool:
	if not can_place(tile_id, origin):
		return false
	var tile := catalog.get_tile(tile_id)
	var size := tile_size(tile)
	var variant := catalog.pick_variant(tile)
	for dx in size.x:
		for dy in size.y:
			var cell := _cell(origin + Vector2i(dx, dy))
			cell.obj = tile_id
			cell.obj_variant = variant
			cell.obj_origin = origin
			cell.obj_size = size
	queue_redraw()
	return true


## Removes the object covering the given cell (buildings of any size).
func demolish(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _cell(cell).obj == "":
		return false
	var obj_origin: Vector2i = _cell(cell).obj_origin
	var size: Vector2i = _cell(cell).obj_size
	for dx in size.x:
		for dy in size.y:
			var c := _cell(obj_origin + Vector2i(dx, dy))
			c.obj = ""
			c.obj_origin = Vector2i()
			c.obj_size = Vector2i.ONE
	queue_redraw()
	return true


## Updates the hovered cell; returns true if it changed.
func set_hovered(cell: Vector2i) -> bool:
	var changed := cell != hovered
	hovered = cell
	_hover_valid = _update_hover_validity()
	if changed:
		queue_redraw()
	return changed


func _update_hover_validity() -> bool:
	if selected_tool.is_empty() or not in_bounds(hovered):
		return false
	if selected_tool == DOZER:
		return _cell(hovered).obj != ""
	return can_place(selected_tool, hovered)


# -- Rendering -----------------------------------------------------------

func _draw() -> void:
	if catalog == null or _cells.is_empty():
		return

	# Painter's algorithm: draw diagonals (x + y) in ascending order so
	# bottom-anchored sprites overlap correctly.
	for sum in range(0, 2 * map_size - 1):
		var x_start := maxi(0, sum - map_size + 1)
		var x_end := mini(sum, map_size - 1)
		for x in range(x_start, x_end + 1):
			var y := sum - x
			var cell := _cell(Vector2i(x, y))

			_draw_terrain(Vector2i(x, y), cell)

			# Multi-cell objects are drawn once, at their origin cell.
			if cell.obj != "" and cell.obj_origin == Vector2i(x, y):
				_draw_object(cell)

	_draw_hover()


func _draw_terrain(cell_pos: Vector2i, cell: Cell) -> void:
	var tile := catalog.get_tile(cell.terrain)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return
	var region := catalog.get_region(tile, texture.get_height(), cell.terrain_variant)
	var screen_pos := iso_to_screen(cell_pos.x, cell_pos.y)
	draw_texture_rect_region(texture, catalog.get_draw_rect(region, screen_pos, TILE_H), region)


func _draw_object(cell: Cell) -> void:
	var tile := catalog.get_tile(cell.obj)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return
	var region := catalog.get_region(tile, texture.get_height(), cell.obj_variant)
	var size := cell.obj_size
	# Anchor the sprite to the bottom corner of its whole footprint.
	var center := iso_to_screen(cell.obj_origin.x + (size.x - 1) * 0.5, cell.obj_origin.y + (size.y - 1) * 0.5)
	var bottom := iso_to_screen(cell.obj_origin.x + size.x - 1, cell.obj_origin.y + size.y - 1).y + TILE_H
	var rect := Rect2(center.x - region.size.x * 0.5, bottom - region.size.y, region.size.x, region.size.y)
	draw_texture_rect_region(texture, rect, region)


func _draw_hover() -> void:
	if selected_tool.is_empty() or not in_bounds(hovered):
		return

	var tile := catalog.get_tile(selected_tool) if selected_tool != DOZER else {}
	var size := tile_size(tile) if not tile.is_empty() else Vector2i.ONE
	var origin := hovered if selected_tool != DOZER else hovered
	var color := Color(0.3, 0.95, 0.4, 0.35) if _hover_valid else Color(0.95, 0.2, 0.2, 0.35)

	var top := iso_to_screen(origin.x, origin.y)
	var right := iso_to_screen(origin.x + size.x - 1, origin.y) + Vector2(TILE_W * 0.5, TILE_H * 0.5)
	var bottom := iso_to_screen(origin.x + size.x - 1, origin.y + size.y - 1) + Vector2(0, TILE_H)
	var left := iso_to_screen(origin.x, origin.y + size.y - 1) + Vector2(-TILE_W * 0.5, TILE_H * 0.5)
	var polygon := PackedVector2Array([top, right, bottom, left])

	draw_colored_polygon(polygon, color)
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(color, 0.9), 1.0)

	# Ghost preview of the tile about to be placed.
	if selected_tool != DOZER and _hover_valid:
		var texture := catalog.get_texture(tile)
		if texture != null:
			var region := catalog.get_region(tile, texture.get_height(), 0)
			var center := iso_to_screen(origin.x + (size.x - 1) * 0.5, origin.y + (size.y - 1) * 0.5)
			var bottom_y := iso_to_screen(origin.x + size.x - 1, origin.y + size.y - 1).y + TILE_H
			var rect := Rect2(center.x - region.size.x * 0.5, bottom_y - region.size.y, region.size.x, region.size.y)
			draw_texture_rect_region(texture, rect, region, Color(1, 1, 1, 0.55))
