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

signal stats_changed
var _population := 0
var _funds := 20000


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

## Generates the terrain. Optional parameters (used by the map editor):
##   seed: int          noise seed
##   size: int          map side in tiles
##   water_pct: 0..100  share of the map under water
##   hills_pct: 0..100  how high/hilly the land gets
##   trees_pct: 0..100  forest density
func generate_map(params: Dictionary = {}) -> void:
	var seed_value: int = params.get("seed", 1234)
	if params.has("size"):
		map_size = int(params.size)
	var water_pct: float = params.get("water_pct", 28.0)
	var hills_pct: float = params.get("hills_pct", 50.0)
	var trees_pct: float = params.get("trees_pct", 50.0)

	var elevation := FastNoiseLite.new()
	elevation.seed = seed_value
	elevation.frequency = 0.045
	var moisture := FastNoiseLite.new()
	moisture.seed = seed_value + 1
	moisture.frequency = 0.07

	_cells.clear()
	_cells.resize(map_size * map_size)

	# thresholds derived from the editor percentages
	var water_cut := _water_cut(water_pct / 100.0)
	var tree_cut := lerpf(0.9, -0.2, trees_pct / 100.0)
	var hill_rich := lerpf(0.15, 0.65, hills_pct / 100.0)

	for y in map_size:
		for x in map_size:
			var cell := Cell.new()
			var e := elevation.get_noise_2d(x, y)
			cell.height = _elevation_level(e, water_cut, hill_rich)
			cell.terrain = _pick_terrain(e, moisture.get_noise_2d(x, y), water_cut, tree_cut)
			cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
			_cells[x + y * map_size] = cell

	_enforce_terraces()
	_population = 0
	queue_redraw()


## Fraction of the map under water -> noise cut, calibrated on FastNoiseLite
## (seed 1234, frequency 0.045) over a 96x96 sample.
func _water_cut(fraction: float) -> float:
	var curve := [
		[0.0, -0.5], [0.05, -0.45], [0.1, -0.4], [0.15, -0.35], [0.2, -0.3],
		[0.28, -0.2], [0.37, -0.1], [0.52, 0.0], [0.67, 0.1], [0.79, 0.2],
		[0.9, 0.3], [1.0, 0.45],
	]
	var f := clampf(fraction, 0.0, 1.0)
	for i in range(1, curve.size()):
		if f <= curve[i][0]:
			var t: float = (f - curve[i - 1][0]) / (curve[i][0] - curve[i - 1][0])
			return lerpf(curve[i - 1][1], curve[i][1], t)
	return curve[-1][1]


func _elevation_level(e: float, water_cut: float, hill_rich: float) -> int:
	if e < water_cut:
		return 0  # water level
	var land := (e - water_cut) / maxf(0.001, 1.0 - water_cut)  # 0..1 above water
	if land < hill_rich * 0.35:
		return 1
	if land < hill_rich * 0.65:
		return 2
	if land < hill_rich:
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


func _pick_terrain(elevation: float, moisture: float, water_cut: float, tree_cut: float) -> String:
	if elevation < water_cut:
		return "water"
	if elevation < water_cut + 0.08:
		return "terrain_sand_beach"
	if moisture > tree_cut:
		return "terrain_grass_forest"
	if moisture < tree_cut - 0.84:
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
	_population += int(tile.get("inhabitants", 0))
	_funds -= int(tile.get("price", 0))
	stats_changed.emit()
	queue_redraw()
	return true


## Removes the object covering the given cell (buildings of any size).
func demolish(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _cell(cell).obj == "":
		return false
	var obj_origin: Vector2i = _cell(cell).obj_origin
	var size: Vector2i = _cell(cell).obj_size
	var demolished := catalog.get_tile(_cell(obj_origin).obj)
	for dx in size.x:
		for dy in size.y:
			var c := _cell(obj_origin + Vector2i(dx, dy))
			c.obj = ""
			c.obj_origin = Vector2i()
			c.obj_size = Vector2i.ONE
	_population -= int(demolished.get("inhabitants", 0))
	stats_changed.emit()
	queue_redraw()
	return true


func terrain_at(cell: Vector2i) -> String:
	return _cell(cell).terrain if in_bounds(cell) else ""


func zone_at(cell: Vector2i) -> String:
	return _cell(cell).zone if in_bounds(cell) else ""


func obj_at(cell: Vector2i) -> String:
	return _cell(cell).obj if in_bounds(cell) else ""


func get_population() -> int:
	return _population


func get_funds() -> int:
	return _funds


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

	# Straight rise toward a single up-screen neighbor: the legacy ramp
	# frames are a clean green incline. Everything else: flat sprite, and
	# every height difference renders as a green face (the other legacy
	# frames bake brown dirt into their corners - not used).
	var higher_n := height_at(cell_pos + Vector2i(0, -1)) > cell.height
	var higher_w := height_at(cell_pos + Vector2i(-1, 0)) > cell.height
	var higher_single := (higher_n and not higher_w) or (higher_w and not higher_n)
	var region: Rect2
	if higher_single and catalog.has_slopes(tile):
		var ramp := TileCatalog.SlopeFrame.NE_RAMP_A if higher_n else TileCatalog.SlopeFrame.NW_RAMP_A
		region = catalog.get_slope_region(tile, ramp)
	else:
		region = catalog.get_region(tile, texture.get_height(), cell.terrain_variant)
	var pos := cell_screen_pos(cell_pos)
	draw_texture_rect_region(texture, catalog.get_draw_rect(region, pos, TILE_H), region)

	var base := catalog.get_surface_color(tile)
	# shared edges: N=(0,-1) up-right, W=(-1,0) up-left, E=(1,0) down-right, S=(0,1) down-left
	for side: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var n: Vector2i = cell_pos + side
		var diff: int = (height_at(n) - cell.height) * HEIGHT_STEP
		if diff == 0 or (cell.terrain == "water" and diff < 0):
			continue
		_draw_face(cell_pos, side, cell.height, diff, base)


## Vertical face on the shared edge with a neighbor of a different height:
## filled with the terrain surface color, shaded per direction
## (light from the north-west). Works for cliffs (neighbor lower) and for
## the wall of higher ground next to us (neighbor higher).
func _draw_face(cell_pos: Vector2i, side: Vector2i, h: int, diff: int, base: Color) -> void:
	var p := iso_to_screen(cell_pos.x, cell_pos.y)
	var lift := h * HEIGHT_STEP
	var n_pt := p - Vector2(0, lift)
	var e_pt := p + Vector2(TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)
	var s_pt := p + Vector2(0, TILE_H) - Vector2(0, lift)
	var w_pt := p + Vector2(-TILE_W * 0.5, TILE_H * 0.5) - Vector2(0, lift)

	var top_a: Vector2
	var top_b: Vector2
	var shade := 1.0
	match side:
		Vector2i(0, -1):  # up-right edge (NE face)
			top_a = n_pt; top_b = e_pt
			shade = 0.9
		Vector2i(-1, 0):  # up-left edge (NW face)
			top_a = w_pt; top_b = n_pt
			shade = 1.0
		Vector2i(1, 0):   # down-right edge (SE face)
			top_a = e_pt; top_b = s_pt
			shade = 0.7
		_:                # down-left edge (SW face)
			top_a = s_pt; top_b = w_pt
			shade = 0.82

	var drop := absi(diff)
	var quad := PackedVector2Array([
		top_a, top_b,
		top_b + Vector2(0, drop), top_a + Vector2(0, drop),
	])
	var col := Color(base.r * shade, base.g * shade, base.b * shade)
	draw_colored_polygon(quad, col)



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
