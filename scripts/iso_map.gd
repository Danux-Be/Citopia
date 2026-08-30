class_name IsoMap
extends Node2D

## Isometric map built from the legacy Cytopia tile database.
## v3: terrain elevation (terraced, ±1 step like the original), slope
## sprites, raise/lower/level tools.

const TILE_W := 32
const TILE_H := 16
const HEIGHT_STEP := 8  # pixels per elevation level (legacy: (tileSize.x - 24))
const MAX_HEIGHT := 8

## Pseudo tool ids (not tiles from the database).
const DOZER := "&dozer"
const RAISE := "&raise"
const LOWER := "&lower"
const LEVEL := "&level"
const DEZONE := "&dezone"

## Zones grow buildings on their own. Zone tile ids start with this prefix.
const ZONE_PREFIX := "zone_"

@export var map_size: int = 96

var catalog: TileCatalog
var hovered := Vector2i(-1, -1)
var selected_tool := ""      # tile id, a pseudo tool, or "" (no tool)

var _cells: Array[Cell] = []
var _hover_valid := false
var _rng := RandomNumberGenerator.new()
var _growth_pool := {}       # zone id -> Array of 1x1 building tile ids


class Cell:
	var terrain := ""            # terrain tile id
	var terrain_variant := 0     # index among the flat variants
	var height := 0              # elevation level (terraced, ±1 per step)
	var zone := ""               # zone tile id painted on this cell ("" = none)
	var obj := ""                # object tile id covering this cell ("" = none)
	var obj_variant := 0
	var obj_origin := Vector2i() # origin cell of the object covering this cell
	var obj_size := Vector2i.ONE # footprint of that object


func _ready() -> void:
	_rng.seed = 20260829
	catalog = TileCatalog.new()
	generate_map()
	_build_growth_pool()


## Maps each zone tile to the pool of 1x1 buildings that can grow on it
## (residential/commercial/industrial zones → buildings of that category).
func _build_growth_pool() -> void:
	var zone_categories := {
		"zone_residential_medium": "Residential",
		"zone_commercial_medium": "Commercial",
		"zone_industrial_medium": "Industrial",
	}
	for zone_id: String in zone_categories:
		var pool: Array[String] = []
		for id in catalog.get_ids_by_category(zone_categories[zone_id]):
			var tile := catalog.get_tile(id)
			var size := tile_size(tile)
			if size == Vector2i.ONE:
				pool.append(id)
		_growth_pool[zone_id] = pool


# -- Terrain generation ---------------------------------------------------

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
			var e := elevation.get_noise_2d(x, y)
			# Water level at 0; hills terraced 1..4 from the same noise field.
			cell.height = _elevation_level(e)
			cell.terrain = _pick_terrain(e, moisture.get_noise_2d(x, y))
			cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
			_cells[x + y * map_size] = cell

	_enforce_terraces()
	queue_redraw()


func _elevation_level(e: float) -> int:
	if e < -0.32:
		return 0  # water level
	if e < 0.0:
		return 1
	if e < 0.28:
		return 2
	if e < 0.5:
		return 3
	return 4


## Flat test map (elevation showcase): uniform grass at `base_height`.
func generate_flat(size: int, base_height: int) -> void:
	map_size = size
	_cells.clear()
	_cells.resize(size * size)
	for y in size:
		for x in size:
			var cell := Cell.new()
			cell.terrain = "terrain_grass"
			cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
			cell.height = base_height
			_cells[x + y * size] = cell
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


## Terracing rule (legacy changeHeight behavior): adjacent cells never differ
## by more than one level, so every step is drawable by a slope sprite.
func _enforce_terraces() -> void:
	for pass_n in 4:
		var changed := false
		for y in map_size:
			for x in map_size:
				var cell := _cell(Vector2i(x, y))
				for n in [Vector2i(x, y - 1), Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y + 1)]:
					if not in_bounds(n):
						continue
					var neighbor := _cell(n)
					if neighbor.height > cell.height + 1:
						neighbor.height = cell.height + 1
						changed = true
		if not changed:
			break


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


func height_at(cell: Vector2i) -> int:
	return _cell(cell).height if in_bounds(cell) else 0


## Screen anchor of a cell: base position lifted by its elevation.
func cell_screen_pos(cell: Vector2i) -> Vector2:
	var base := iso_to_screen(cell.x, cell.y)
	return base - Vector2(0, height_at(cell) * HEIGHT_STEP)


# -- Elevation tools ------------------------------------------------------

## Raise a cell by one level, cascading so neighbors stay within one step
## (growing terraced mountains, like the legacy terrain raise tool).
func change_height(origin: Vector2i, delta: int) -> void:
	if not in_bounds(origin) or _cell(origin).terrain == "water":
		return
	_change_height_rec(origin, delta, 0)
	queue_redraw()


func _change_height_rec(cell_pos: Vector2i, delta: int, depth: int) -> void:
	if depth > MAX_HEIGHT + 2 or not in_bounds(cell_pos):
		return
	var cell := _cell(cell_pos)
	if cell.terrain == "water":
		return
	var target: int = clampi(cell.height + delta, 0, MAX_HEIGHT)
	if target == cell.height:
		return
	cell.height = target
	# Keep the ±1 terracing invariant: pull neighbors one step along.
	for n in [cell_pos + Vector2i(0, -1), cell_pos + Vector2i(-1, 0), cell_pos + Vector2i(1, 0), cell_pos + Vector2i(0, 1)]:
		if in_bounds(n) and _cell(n).terrain != "water":
			var diff: int = cell.height - _cell(n).height
			if absi(diff) > 1:
				_change_height_rec(n, signi(diff), depth + 1)
	# Buildings need flat ground.
	_demolish_if_sloped(cell_pos)


func _demolish_if_sloped(cell_pos: Vector2i) -> void:
	var cell := _cell(cell_pos)
	if cell.obj != "" and cell.obj_origin == cell_pos and not _is_flat_area(cell.obj_origin, cell.obj_size):
		demolish(cell_pos)


func _is_flat_area(origin: Vector2i, size: Vector2i) -> bool:
	var h := height_at(origin)
	# The footprint plus its surrounding ring must sit at one height.
	for dx in range(-1, size.x + 1):
		for dy in range(-1, size.y + 1):
			var p := origin + Vector2i(dx, dy)
			if in_bounds(p) and height_at(p) != h:
				return false
	return true


## Level: raise the surroundings up to the clicked cell's height.
func level_terrain(origin: Vector2i) -> void:
	if not in_bounds(origin):
		return
	var target := height_at(origin)
	var filled := {}
	_level_fill(origin, target, filled, 0)
	queue_redraw()


func _level_fill(cell_pos: Vector2i, target: int, filled: Dictionary, depth: int) -> void:
	if depth > MAX_HEIGHT * 2 or not in_bounds(cell_pos) or filled.has(cell_pos):
		return
	var cell := _cell(cell_pos)
	if cell.terrain == "water" or cell.height >= target:
		return
	filled[cell_pos] = true
	cell.height = target
	_demolish_if_sloped(cell_pos)
	for n in [cell_pos + Vector2i(0, -1), cell_pos + Vector2i(-1, 0), cell_pos + Vector2i(1, 0), cell_pos + Vector2i(0, 1)]:
		_level_fill(n, target, filled, depth + 1)


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
	# Buildings require a flat plateau (footprint + surrounding ring).
	if not _is_flat_area(origin, size):
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


# -- Zoning ----------------------------------------------------------------

func is_zone_tool(tool_id: String) -> bool:
	return tool_id.begins_with(ZONE_PREFIX)


## Paints a zone on one cell (land only, no building on top).
func paint_zone(cell: Vector2i, zone_id: String) -> bool:
	if not in_bounds(cell):
		return false
	var c := _cell(cell)
	if c.terrain == "water" or c.obj != "":
		return false
	if c.zone == zone_id:
		return false
	c.zone = zone_id
	queue_redraw()
	return true


## Removes the zone from one cell.
func clear_zone(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _cell(cell).zone == "":
		return false
	_cell(cell).zone = ""
	queue_redraw()
	return true


## Growth tick: a few random zoned empty cells spawn a matching building.
## Buildings only grow on flat, buildable ground (the usual placement rules).
func grow_zones(max_spawns: int = 3) -> void:
	var candidates: Array[Vector2i] = []
	for y in map_size:
		for x in map_size:
			var cell_pos := Vector2i(x, y)
			var zone_id: String = _cell(cell_pos).zone
			if zone_id != "" and _cell(cell_pos).obj == "":
				candidates.append(cell_pos)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var spawned := 0
	for cell_pos in candidates:
		if spawned >= max_spawns:
			break
		var zone_id: String = _cell(cell_pos).zone
		var pool: Array = _growth_pool.get(zone_id, [])
		if pool.is_empty():
			continue
		var building: String = pool[_rng.randi_range(0, pool.size() - 1)]
		if place(building, cell_pos):
			spawned += 1


# -- Hover ----------------------------------------------------------------

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
	match selected_tool:
		DOZER:
			return _cell(hovered).obj != "" or _cell(hovered).zone != ""
		DEZONE:
			return _cell(hovered).zone != ""
		RAISE, LOWER, LEVEL:
			return _cell(hovered).terrain != "water"
		_:
			if is_zone_tool(selected_tool):
				return _cell(hovered).terrain != "water" and _cell(hovered).obj == ""
			return can_place(selected_tool, hovered)


# -- Rendering ------------------------------------------------------------

func _draw() -> void:
	if catalog == null or _cells.is_empty():
		return

	# Painter's algorithm: draw diagonals (x + y) in ascending order so
	# later (front) tiles correctly cover the elevation steps behind them.
	for sum in range(0, 2 * map_size - 1):
		var x_start := maxi(0, sum - map_size + 1)
		var x_end := mini(sum, map_size - 1)
		for x in range(x_start, x_end + 1):
			var y := sum - x
			var cell := _cell(Vector2i(x, y))
			_draw_terrain(Vector2i(x, y), cell)
			if cell.zone != "":
				_draw_zone(Vector2i(x, y), cell)
			if cell.obj != "" and cell.obj_origin == Vector2i(x, y):
				_draw_object(cell)

	_draw_hover()


func _draw_terrain(cell_pos: Vector2i, cell: Cell) -> void:
	var tile := catalog.get_tile(cell.terrain)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return

	if cell.terrain == "water" or not catalog.has_slopes(tile):
		# Flat variant only (liquids have no slope sheets).
		var region := catalog.get_region(tile, texture.get_height(), cell.terrain_variant)
		var screen_pos := cell_screen_pos(cell_pos)
		draw_texture_rect_region(texture, catalog.get_draw_rect(region, screen_pos, TILE_H), region)
		return

	var frame := _slope_frame(cell_pos, cell)
	var region: Rect2
	if frame == TileCatalog.SlopeFrame.NONE:
		region = catalog.get_region(tile, texture.get_height(), cell.terrain_variant)
		var pos := cell_screen_pos(cell_pos)
		draw_texture_rect_region(texture, catalog.get_draw_rect(region, pos, TILE_H), region)
	else:
		region = catalog.get_slope_region(tile, frame)
		var pos2 := cell_screen_pos(cell_pos)
		var rect := Rect2(pos2.x - region.size.x * 0.5, pos2.y + TILE_H - region.size.y, region.size.x, region.size.y)
		draw_texture_rect_region(texture, rect, region)

	# Walls on the two camera-facing sides only (down-right / down-left);
	# the up-facing sides are back faces, occluded by the tile itself.
	# Out-of-bounds counts as level 0 so the map edges show a clean slab.
	var drops := {}  # side Vector2i -> depth in pixels
	for side: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var n: Vector2i = cell_pos + side
		if height_at(n) < cell.height and _cell(cell_pos).terrain != "water":
			var depth := (cell.height - height_at(n)) * HEIGHT_STEP
			drops[side] = depth
			_draw_wall(cell_pos, side, cell.height, height_at(n), texture, region)
	_draw_corner_walls(cell_pos, cell.height, drops, texture, region)


## Vertical corner patches: where two adjacent walls have different depths,
## a triangular gap would show — fill it down to the deeper wall's base.
func _draw_corner_walls(cell_pos: Vector2i, h: int, drops: Dictionary, texture: Texture2D, region: Rect2) -> void:
	if drops.size() < 2:
		return
	var p := iso_to_screen(cell_pos.x, cell_pos.y)
	var lift := h * HEIGHT_STEP
	var n_pt := p - Vector2(0, lift)
	var e_pt := p + Vector2(TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)
	var s_pt := p + Vector2(0, TILE_H) - Vector2(0, lift)
	var w_pt := p + Vector2(-TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)
	# corner position + the two wall sides meeting there
	var corners := [
		[s_pt, Vector2i(1, 0), Vector2i(0, 1)],     # S corner: SE & SW faces meet here
	]
	for entry: Array in corners:
		var d1: int = drops.get(entry[1], 0)
		var d2: int = drops.get(entry[2], 0)
		if d1 == 0 or d2 == 0 or d1 == d2:
			continue
		var corner: Vector2 = entry[0]
		var shallow := minf(d1, d2)
		var deep := maxf(d1, d2)
		var shade := 0.45  # deep shade: reads as the dark side of the corner
		var col := Color(shade, shade, shade)
		draw_colored_polygon(
			PackedVector2Array([corner, corner + Vector2(0, deep), corner + Vector2(0, shallow)]),
			col
		)


## Vertical cliff face between our surface edge and a lower neighbor,
## textured from the tile sheet and darkened per direction (light from NW).
## UVs are mapped inside `region` (the frame's slot on the sheet).
func _draw_wall(cell_pos: Vector2i, side: Vector2i, h: int, hn: int, texture: Texture2D, region: Rect2) -> void:
	var p := iso_to_screen(cell_pos.x, cell_pos.y)
	var lift := h * HEIGHT_STEP
	var lift_n := hn * HEIGHT_STEP
	# Diamond corners of this cell (P is the north corner).
	var n_pt := p - Vector2(0, lift)
	var e_pt := p + Vector2(TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)
	var s_pt := p + Vector2(0, TILE_H) - Vector2(0, lift)
	var w_pt := p + Vector2(-TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)

	var top_a: Vector2
	var top_b: Vector2
	var uv_a: Vector2
	var uv_b: Vector2
	var shade := 1.0

	match side:
		Vector2i(0, -1):  # north neighbor -> north-east face
			top_a = n_pt; top_b = e_pt
			uv_a = Vector2(16, 8); uv_b = Vector2(31, 15)
			shade = 0.72
		Vector2i(-1, 0):  # west neighbor -> north-west face
			top_a = w_pt; top_b = n_pt
			uv_a = Vector2(0, 15); uv_b = Vector2(16, 8)
			shade = 0.85
		Vector2i(1, 0):  # east neighbor -> south-east face
			top_a = e_pt; top_b = s_pt
			uv_a = Vector2(31, 15); uv_b = Vector2(16, 23)
			shade = 0.52
		_:  # south neighbor -> south-west face
			top_a = s_pt; top_b = w_pt
			uv_a = Vector2(16, 23); uv_b = Vector2(0, 15)
			shade = 0.62

	var drop := lift - lift_n
	var points := PackedVector2Array([
		top_a, top_b,
		top_b + Vector2(0, drop), top_a + Vector2(0, drop),
	])
	var tex_size := texture.get_size()
	# In 23px slope frames the surface diamond sits 8px lower than in the
	# 15px flat frames: compensate so we always sample the surface edges.
	var uv_shift := region.size.y - 15.0
	var uv_drop := minf(6.0, drop)
	# draw_polygon() expects normalized UVs: map local frame coords into the
	# region slot, then divide by the sheet size.
	var _uv := func(local: Vector2, dy: float) -> Vector2:
		var px := region.position + Vector2(clampf(local.x, 0, region.size.x - 1), clampf(local.y + uv_shift + dy, 0, region.size.y - 1))
		return px / tex_size
	var uvs := PackedVector2Array([
		_uv.call(uv_a, 0), _uv.call(uv_b, 0),
		_uv.call(uv_b, uv_drop), _uv.call(uv_a, uv_drop),
	])
	var col := Color(shade, shade, shade)
	draw_polygon(points, PackedColorArray([col, col, col, col]), uvs, texture)


## Chooses the slope sprite from the neighbors' heights.
## - neighbor (x, y-1) higher  → ramp rising toward the up-right screen edge
## - neighbor (x-1, y) higher  → ramp rising toward the up-left screen edge
## - both higher               → corner pyramid (isolated peak corner)
## - higher south/east neighbors draw AFTER us and cover the seam themselves.
func _slope_frame(cell_pos: Vector2i, cell: Cell) -> TileCatalog.SlopeFrame:
	var h := cell.height
	var higher_n := height_at(cell_pos + Vector2i(0, -1)) > h
	var higher_w := height_at(cell_pos + Vector2i(-1, 0)) > h

	if higher_n and higher_w:
		return TileCatalog.SlopeFrame.CORNER_PYRAMID
	if higher_n:
		return TileCatalog.SlopeFrame.NE_RAMP_A if cell.terrain_variant % 2 == 0 else TileCatalog.SlopeFrame.NE_RAMP_B
	if higher_w:
		return TileCatalog.SlopeFrame.NW_RAMP_A if cell.terrain_variant % 2 == 0 else TileCatalog.SlopeFrame.NW_RAMP_B
	return TileCatalog.SlopeFrame.NONE


## Zone overlay: drawn lifted with the tile, under any building.
func _draw_zone(cell_pos: Vector2i, cell: Cell) -> void:
	var tile := catalog.get_tile(cell.zone)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return
	var region := catalog.get_region(tile, texture.get_height(), 0)
	var screen_pos := cell_screen_pos(cell_pos)
	draw_texture_rect_region(texture, catalog.get_draw_rect(region, screen_pos, TILE_H), region)


func _draw_object(cell: Cell) -> void:
	var tile := catalog.get_tile(cell.obj)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return
	var region := catalog.get_region(tile, texture.get_height(), cell.obj_variant)
	var size := cell.obj_size
	var origin := cell.obj_origin
	var center := iso_to_screen(origin.x + (size.x - 1) * 0.5, origin.y + (size.y - 1) * 0.5)
	var bottom := iso_to_screen(origin.x + size.x - 1, origin.y + size.y - 1).y + TILE_H - height_at(origin) * HEIGHT_STEP
	var rect := Rect2(center.x - region.size.x * 0.5, bottom - region.size.y, region.size.x, region.size.y)
	draw_texture_rect_region(texture, rect, region)


func _draw_hover() -> void:
	if selected_tool.is_empty() or not in_bounds(hovered):
		return

	var is_terrain_tool := selected_tool in [RAISE, LOWER, LEVEL]
	var tile := catalog.get_tile(selected_tool) if not (is_terrain_tool or selected_tool == DOZER) else {}
	var size := tile_size(tile) if not tile.is_empty() else Vector2i.ONE
	var origin := hovered
	var color := Color(0.3, 0.95, 0.4, 0.35) if _hover_valid else Color(0.95, 0.2, 0.2, 0.35)

	var lift := height_at(origin) * HEIGHT_STEP
	var top := iso_to_screen(origin.x, origin.y) - Vector2(0, lift)
	var right := iso_to_screen(origin.x + size.x - 1, origin.y) + Vector2(TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)
	var bottom := iso_to_screen(origin.x + size.x - 1, origin.y + size.y - 1) + Vector2(0, TILE_H) - Vector2(0, lift)
	var left := iso_to_screen(origin.x, origin.y + size.y - 1) + Vector2(-TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)

	draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), color)
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(color, 0.9), 1.0)

	# Ghost preview of the tile about to be placed.
	if not is_terrain_tool and selected_tool != DOZER and _hover_valid:
		var texture := catalog.get_texture(tile)
		if texture != null:
			var region := catalog.get_region(tile, texture.get_height(), 0)
			var center := iso_to_screen(origin.x + (size.x - 1) * 0.5, origin.y + (size.y - 1) * 0.5) - Vector2(0, lift)
			var bottom_y := iso_to_screen(origin.x + size.x - 1, origin.y + size.y - 1).y + TILE_H - lift
			var rect := Rect2(center.x - region.size.x * 0.5, bottom_y - region.size.y, region.size.x, region.size.y)
			draw_texture_rect_region(texture, rect, region, Color(1, 1, 1, 0.55))
