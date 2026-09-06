class_name IsoMap
extends Node2D

## Isometric map built from the legacy Cytopia tile database.
## v4: flat map generation (vehicle/road focus), a road layer with native
## autotile frames, and per-diagonal rendering so vehicles (and tall
## buildings) sort correctly with the painter's algorithm via z_index.

const TILE_W := 32
const TILE_H := 16
const HEIGHT_STEP := 8  # pixels per elevation level (legacy: (tileSize.x - 24))
const MAX_HEIGHT := 8

## The water sheet ships 3 ripple frames; cycling them at this rate gives a
## calm body of water (a full wave takes 1.5 s to cross a cell).
const WATER_FPS := 2.0

## Every terrain that behaves like a body of water: clear lakes plus the
## swampy MurkyWater pockets.
const WATER_TERRAINS := ["water", "liquid_MurkyWater"]

## Pseudo tool ids (not tiles from the database).
const DOZER := "&dozer"
const RAISE := "&raise"
const LOWER := "&lower"
const LEVEL := "&level"
const DEZONE := "&dezone"

## Zones grow buildings on their own. Zone tile ids start with this prefix.
const ZONE_PREFIX := "zone_"

## Moisture above which a depression fills with swamp water instead of a
## clear lake (calibrated on seed 7: ~6% of the water, a few pockets).
const SWAMP_MOISTURE := 0.35

@export var map_size: int = 96

var catalog: TileCatalog
var hovered := Vector2i(-1, -1)
var selected_tool := ""      # tile id, a pseudo tool, or "" (no tool)

var _cells: Array[Cell] = []
var _hover_valid := false
var _rng := RandomNumberGenerator.new()
var _growth_pool := {}       # zone id -> Array of 1x1 building tile ids

signal stats_changed
signal roads_changed
var _population := 0
var _funds := 20000

# -- Road autotile (decoded from the 24-frame legacy road strips) -------------
# The curb border on each diamond edge is broken exactly where the road
# connects, and the white markings belong to their mask: dashed centre line
# on straight runs, side arms' lines truncated at T/cross junctions.
# Connection bit per grid direction: E=1, N=2, W=4, S=8.
const ROAD_DIR_BIT := {
	Vector2i(0, -1): 2, Vector2i(1, 0): 1,
	Vector2i(0, 1): 8, Vector2i(-1, 0): 4,
}
## The legacy road sheets are bit-identity (verified against the original
## Cytopia TileOrientation enum): frame index == connection mask. Frames
## 16-19 are full RECT pads, never corners — our earlier mapping drew
## solid squares at every turn.
func road_frame(mask: int) -> int:
	return mask

# -- Zone growth requirements -------------------------------------------------
# A zoned cell only grows a building when it is served: a road within
# ROAD_ACCESS_RADIUS (Chebyshev) AND coverage by a power plant. Plants radiate
# over a radius derived from their `power` output (coal 16, solar 6).
const ROAD_ACCESS_RADIUS := 2
const PLANT_RADIUS_MIN := 5
const PLANT_RADIUS_MAX := 16
const ABANDON_GRACE := 20.0   # seconds unserved before a grown building collapses

var _plants := {}            # plant origin -> radiation radius in tiles
var _abandoning := {}        # cell pos -> seconds left before collapse


class Cell:
	var terrain := ""            # terrain tile id
	var terrain_variant := 0     # index among the flat variants
	var height := 0              # elevation level (terraced, ±1 per step)
	var zone := ""               # zone tile id painted on this cell ("" = none)
	var road := ""               # road tile id on this cell ("" = none)
	var road_variant := 0        # autotile frame index in the road strip
	var obj := ""                # object tile id covering this cell ("" = none)
	var obj_variant := 0
	var obj_origin := Vector2i() # origin cell of the object covering this cell
	var obj_size := Vector2i.ONE # footprint of that object
	var served_road := false     # a road lies within ROAD_ACCESS_RADIUS (zoned cells)
	var served_power := false    # a power plant covers this cell (zoned cells)
	var grown := false           # building spawned by zone growth (service required)
	var abandoned := false       # grown building that lost road/power service


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
##   trees_pct: 0..100  forest density
##   hills_pct: 0..100  IGNORED for now: maps are generated flat so roads
##                      and vehicle traffic stay simple
func generate_map(params: Dictionary = {}) -> void:
	var seed_value: int = params.get("seed", 1234)
	if params.has("size"):
		map_size = int(params.size)
	var water_pct: float = params.get("water_pct", 22.0)
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

	for y in map_size:
		for x in map_size:
			var cell := Cell.new()
			var e := elevation.get_noise_2d(x, y)
			cell.height = 0  # flat maps for the traffic milestone
			cell.terrain = _pick_terrain(e, moisture.get_noise_2d(x, y), water_cut, tree_cut)
			cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
			_cells[x + y * map_size] = cell

	_erosion_swamp()
	_place_water_flora()
	_place_trees()
	_place_ships()
	_population = 0
	_rebuild_diagonals()
	roads_changed.emit()


## Swamp pockets from raw noise come out as scattered single cells, which
## pockmark the land with lone water tiles (unnatural corner shores). Erode
## any murky cell with fewer than two murky neighbours until stable, so only
## genuine clusters survive.
func _erosion_swamp() -> void:
	var changed := true
	var passes := 0
	while changed and passes < 6:
		changed = false
		passes += 1
		for y in map_size:
			for x in map_size:
				var cell_pos := Vector2i(x, y)
				if _cell(cell_pos).terrain != "liquid_MurkyWater":
					continue
				var wet := 0
				for n in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
						Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
					if is_water_cell(cell_pos + n) and _cell(cell_pos + n).terrain == "liquid_MurkyWater":
						wet += 1
				if wet < 2:
					_cell(cell_pos).terrain = "water"  # stays water: joins the lake
					changed = true


## Real trees from the legacy flora sheets on forest cells (which otherwise
## read as "different grass"). Trees are cell objects: bulldozable, and they
## block building/zone placement until cleared.
func _place_trees() -> void:
	var pool: Array[String] = []
	for id in catalog.get_ids_by_category("Flora"):
		if id.begins_with("tree_") and not id.contains("Chopped"):
			pool.append(id)
	if pool.is_empty():
		return
	for y in map_size:
		for x in map_size:
			var cell_pos := Vector2i(x, y)
			var cell := _cell(cell_pos)
			if cell.terrain != "terrain_grass_forest" or _rng.randf() > 0.30:
				continue
			cell.terrain = "terrain_grass"  # the tree object draws over plain grass
			cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
			cell.obj = pool[_rng.randi_range(0, pool.size() - 1)]
			cell.obj_origin = cell_pos
			cell.obj_size = Vector2i.ONE
			cell.obj_variant = catalog.pick_variant(catalog.get_tile(cell.obj))


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
	_rebuild_diagonals()
	roads_changed.emit()


## Water plants from the legacy pack: swamp rice and cattails hug the shores,
## lily pads drift on calm open water. They live as cell objects, so the
## bulldozer can clear them like any other decoration.
func _place_water_flora() -> void:
	for y in map_size:
		for x in map_size:
			var cell_pos := Vector2i(x, y)
			var cell := _cell(cell_pos)
			if cell.terrain not in WATER_TERRAINS:
				continue
			var flora := ""
			if _has_land_edge(cell_pos):
				if cell.terrain == "liquid_MurkyWater":
					flora = _pick_flora(["waterFlora_rice_light", "waterFlora_rice_medium", "waterFlora_rice_dense"], 0.30)
				else:
					flora = _pick_flora(["waterFlora_cattail_light", "waterFlora_cattail_medium", "waterFlora_cattail_dense"], 0.16)
			else:
				flora = _pick_flora(["waterFlora_lilypads_light", "waterFlora_lilypads_medium", "waterFlora_lilypads_dense"], 0.05)
			if flora != "":
				cell.obj = flora
				cell.obj_origin = cell_pos
				cell.obj_size = Vector2i.ONE
				cell.obj_variant = catalog.pick_variant(catalog.get_tile(flora))


func _pick_flora(ids: Array, chance: float) -> String:
	if _rng.randf() >= chance:
		return ""
	return ids[_rng.randi_range(0, ids.size() - 1)]


## Moored ships from the legacy decoration pack: wooden ships anchored in
## open water, occasionally a sunken wreck. Each needs a calm patch of clear
## water so hulls never touch the shore.
func _place_ships() -> void:
	# live count: the cached total may belong to a previous generation
	var afloat := 0
	for cell in _cells:
		if cell.obj.begins_with("BD_"):
			afloat += 1
	afloat = int(afloat / 4.0)
	var spots: Array[Vector2i] = []
	for y in range(1, map_size - 5):
		for x in range(1, map_size - 5):
			if _is_open_water_patch(Vector2i(x, y)):
				spots.append(Vector2i(x, y))
	spots.shuffle()
	var placed: Array[Vector2i] = []
	for spot in spots:
		if placed.size() + afloat >= 3:
			break
		var spread := false
		for p in placed:
			if absi(p.x - spot.x) + absi(p.y - spot.y) < 24:
				spread = true
				break
		if spread:
			continue
		var ship := "BD_2x2_sunkenship_kt" if _rng.randf() < 0.3 else "BD_2x2_WoodenShip"
		if place(ship, spot, false):
			placed.append(spot)


## A calm berth: the 2x2 hull sits on clear, object-free water and the
## mooring ring is water of any kind (reeds welcome, other hulls not).
func _is_open_water_patch(origin: Vector2i) -> bool:
	for dy in range(-1, 5):
		for dx in range(-1, 5):
			var c := _cell(origin + Vector2i(dx, dy))
			var in_hull := dx >= 0 and dx < 2 and dy >= 0 and dy < 2
			if in_hull:
				if c.terrain != "water" or c.obj != "":
					return false
			elif c.terrain not in WATER_TERRAINS or c.obj.begins_with("BD_"):
				return false
	return true


## Top-left of a w x h block of dry land — the demo village layout needs one.
## Falls back to the least-wet spot so any map still gets its village.
func find_dry_rect(w: int, h: int) -> Vector2i:
	# integral image over the water indicator: O(1) per candidate rect
	var stride := map_size + 1
	var prefix := PackedInt32Array()
	prefix.resize(stride * (map_size + 1))
	for y in map_size:
		for x in map_size:
			prefix[(y + 1) * stride + x + 1] = prefix[y * stride + x + 1] \
					+ prefix[(y + 1) * stride + x] - prefix[y * stride + x] \
					+ (1 if _cells[x + y * map_size].terrain in WATER_TERRAINS else 0)
	var rect_wet := func(r: Vector2i) -> int:
		return prefix[(r.y + h) * stride + r.x + w] - prefix[r.y * stride + r.x + w] \
				- prefix[(r.y + h) * stride + r.x] + prefix[r.y * stride + r.x]
	var best := Vector2i(map_size / 2 - w / 2, map_size / 2 - h / 2)
	var best_wet := 1 << 30
	for oy in range(2, map_size - h - 1):
		for ox in range(2, map_size - w - 1):
			var wet: int = rect_wet.call(Vector2i(ox, oy))
			if wet == 0:
				return Vector2i(ox, oy)
			if wet < best_wet:
				best_wet = wet
				best = Vector2i(ox, oy)
	return best


## Turn the water cells of a rect into plain grass and strip vegetation
## (demo siting). Ships moored inside the rect are relocated to open water
## so the village never splits around a hull pond.
func carve_to_dry(origin: Vector2i, w: int, h: int) -> void:
	var changed := false
	var evicted := 0
	for dy in h:
		for dx in w:
			var cell_pos := origin + Vector2i(dx, dy)
			var cell := _cell(cell_pos)
			if cell.terrain in WATER_TERRAINS:
				if cell.obj.begins_with("BD_"):
					evicted += 1  # counts hull cells; cleared below via its origin
					continue
				cell.terrain = "terrain_grass"
				cell.terrain_variant = catalog.pick_variant(catalog.get_tile(cell.terrain))
				changed = true
			if cell.obj != "" and not cell.obj.begins_with("BD_"):
				cell.obj = ""  # flora and trees of the building site go too
				changed = true
	if evicted > 0:
		_clear_ships_in_rect(origin, w, h)
		changed = true
	if changed:
		_rebuild_diagonals()
		roads_changed.emit()
		_place_ships()  # refill up to the fleet cap in open water


func _clear_ships_in_rect(origin: Vector2i, w: int, h: int) -> void:
	for dy in h:
		for dx in w:
			var cell_pos := origin + Vector2i(dx, dy)
			var cell := _cell(cell_pos)
			if not cell.obj.begins_with("BD_") or cell.obj_origin != cell_pos:
				continue
			var size := tile_size(catalog.get_tile(cell.obj))
			for ddy in size.y:
				for ddx in size.x:
					_cell(cell_pos + Vector2i(ddx, ddy)).obj = ""


func _has_land_edge(cell_pos: Vector2i) -> bool:
	for n in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		if in_bounds(cell_pos + n) and _cell(cell_pos + n).terrain not in WATER_TERRAINS:
			return true
	return false


func _pick_terrain(elevation: float, moisture: float, water_cut: float, tree_cut: float) -> String:
	if elevation < water_cut:
		# swampy pockets: wet depressions fill with MurkyWater instead
		return "liquid_MurkyWater" if moisture > SWAMP_MOISTURE else "water"
	if elevation < water_cut + 0.035:
		return "terrain_sand_beach"
	if moisture > tree_cut:
		return "terrain_grass_forest"
	if moisture < tree_cut - 0.84:
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


## True for both clear and murky water cells (build rules, shores, animation).
func is_water_cell(cell: Vector2i) -> bool:
	return in_bounds(cell) and _cell(cell).terrain in WATER_TERRAINS


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
	if not in_bounds(origin) or is_water_cell(origin):
		return
	_change_height_rec(origin, delta, 0)
	_flush()


func _change_height_rec(cell_pos: Vector2i, delta: int, depth: int) -> void:
	if depth > MAX_HEIGHT + 2 or not in_bounds(cell_pos):
		return
	var cell := _cell(cell_pos)
	if cell.terrain in WATER_TERRAINS:
		return
	var target: int = clampi(cell.height + delta, 0, MAX_HEIGHT)
	if target == cell.height:
		return
	cell.height = target
	_mark(cell_pos)
	# Keep the ±1 terracing invariant: pull neighbors one step along.
	for n in [cell_pos + Vector2i(0, -1), cell_pos + Vector2i(-1, 0), cell_pos + Vector2i(1, 0), cell_pos + Vector2i(0, 1)]:
		if in_bounds(n) and _cell(n).terrain not in WATER_TERRAINS:
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
	_flush()


func _level_fill(cell_pos: Vector2i, target: int, filled: Dictionary, depth: int) -> void:
	if depth > MAX_HEIGHT * 2 or not in_bounds(cell_pos) or filled.has(cell_pos):
		return
	var cell := _cell(cell_pos)
	if cell.terrain in WATER_TERRAINS or cell.height >= target:
		return
	filled[cell_pos] = true
	cell.height = target
	_mark(cell_pos)
	_demolish_if_sloped(cell_pos)
	for n in [cell_pos + Vector2i(0, -1), cell_pos + Vector2i(-1, 0), cell_pos + Vector2i(1, 0), cell_pos + Vector2i(0, 1)]:
		_level_fill(n, target, filled, depth + 1)


# -- Building ------------------------------------------------------------

static func tile_size(tile: Dictionary) -> Vector2i:
	var required: Dictionary = tile.get("RequiredTiles", {})
	return Vector2i(int(required.get("width", 1)), int(required.get("height", 1)))


static func _covers_terrain(tile: Dictionary, terrain_id: String) -> bool:
	if terrain_id in WATER_TERRAINS:
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
			if cell.obj != "" or cell.road != "":
				return false
			if not _covers_terrain(tile, cell.terrain):
				return false
	# Buildings require a flat plateau (footprint + surrounding ring).
	if not _is_flat_area(origin, size):
		return false
	return true


## Places a tile. `charge` is false for buildings that grow by themselves.
func place(tile_id: String, origin: Vector2i, charge := true) -> bool:
	if not can_place(tile_id, origin):
		return false
	var tile := catalog.get_tile(tile_id)
	var price := int(tile.get("price", 0))
	if charge and _funds < price:
		return false
	var size := tile_size(tile)
	var variant := catalog.pick_variant(tile)
	for dx in size.x:
		for dy in size.y:
			var cell := _cell(origin + Vector2i(dx, dy))
			cell.obj = tile_id
			cell.obj_variant = variant
			cell.obj_origin = origin
			cell.obj_size = size
			_mark(origin + Vector2i(dx, dy))
	if charge:
		_funds -= price
	_population += int(tile.get("inhabitants", 0))
	if _is_power_plant(tile):
		_plants[origin] = _plant_radius(tile)
		_update_power_service(origin, _plants[origin], false)
	stats_changed.emit()
	_flush()
	return true


## Removes the object or road covering the given cell (buildings of any size).
func demolish(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	if _cell(cell).obj == "" and _cell(cell).road != "":
		return remove_road(cell)
	if _cell(cell).obj == "":
		return false
	var obj_origin: Vector2i = _cell(cell).obj_origin
	var size: Vector2i = _cell(cell).obj_size
	var demolished := catalog.get_tile(_cell(obj_origin).obj)
	# an abandoned building already lost its inhabitants
	var occupied: bool = not _cell(obj_origin).abandoned
	for dx in size.x:
		for dy in size.y:
			var c := _cell(obj_origin + Vector2i(dx, dy))
			c.obj = ""
			c.obj_origin = Vector2i()
			c.obj_size = Vector2i.ONE
			c.grown = false
			c.abandoned = false
			_mark(obj_origin + Vector2i(dx, dy))
	_abandoning.erase(obj_origin)
	if occupied:
		_population -= int(demolished.get("inhabitants", 0))
	if _plants.has(obj_origin):
		var radius: int = _plants[obj_origin]
		_plants.erase(obj_origin)
		_update_power_service(obj_origin, radius, true)
	stats_changed.emit()
	_flush()
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


# -- Roads ------------------------------------------------------------------

func is_road_tool(tool_id: String) -> bool:
	return tool_id.begins_with("road_") and catalog.is_road_tile(tool_id)


func is_road(cell: Vector2i) -> bool:
	return in_bounds(cell) and _cell(cell).road != ""


## Sheet frame used at this cell (debug/minimap/tests).
func road_variant_at(cell: Vector2i) -> int:
	return _cell(cell).road_variant if in_bounds(cell) else -1


## Roads need the cell and its 4 neighbors at one height (no slope art for
## connections); always true on flat maps.
func _road_site_ok(cell: Vector2i) -> bool:
	var h := height_at(cell)
	for n: Vector2i in [cell + Vector2i(0, -1), cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(-1, 0)]:
		if in_bounds(n) and height_at(n) != h:
			return false
	return true


func can_place_road(road_id: String, cell: Vector2i) -> bool:
	if not in_bounds(cell) or not is_road_tool(road_id):
		return false
	var c := _cell(cell)
	if c.terrain in WATER_TERRAINS or c.obj != "" or not _road_site_ok(cell):
		return false
	if c.road == road_id:
		return true  # repainting the same road is a no-op, not a failure
	return c.road != "" or _funds >= int(catalog.get_tile(road_id).get("price", 0))


## Lays one road cell and refreshes the autotile frames around it.
func place_road(road_id: String, cell: Vector2i) -> bool:
	if not can_place_road(road_id, cell):
		return false
	var c := _cell(cell)
	if c.road == road_id:
		return true
	if c.road == "":
		_funds -= int(catalog.get_tile(road_id).get("price", 0))
		stats_changed.emit()
	c.road = road_id
	_refresh_road_frame(cell)
	for n: Vector2i in [cell + Vector2i(0, -1), cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(-1, 0)]:
		if is_road(n):
			_refresh_road_frame(n)
	_update_road_service(cell)
	roads_changed.emit()
	_flush()
	return true


func remove_road(cell: Vector2i) -> bool:
	if not is_road(cell):
		return false
	_cell(cell).road = ""
	_refresh_road_frame(cell)
	for n: Vector2i in [cell + Vector2i(0, -1), cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(-1, 0)]:
		if is_road(n):
			_refresh_road_frame(n)
	_update_road_service(cell)
	roads_changed.emit()
	_flush()
	return true


## Autotile: the frame is looked up from the exact connection mask, so curb
## gaps, centre-line dashes and junction markings always line up with the
## neighbouring road cells.
func _refresh_road_frame(cell: Vector2i) -> void:
	var mask := 0
	for n: Vector2i in ROAD_DIR_BIT:
		if is_road(cell + n):
			mask |= ROAD_DIR_BIT[n]
	_cell(cell).road_variant = road_frame(mask)
	_mark(cell)


# -- Zoning ----------------------------------------------------------------

func is_zone_tool(tool_id: String) -> bool:
	return tool_id.begins_with(ZONE_PREFIX)


## Paints a zone on one cell (land only, no building, no road on top).
func paint_zone(cell: Vector2i, zone_id: String) -> bool:
	if not in_bounds(cell):
		return false
	var c := _cell(cell)
	if c.terrain in WATER_TERRAINS or c.obj != "" or c.road != "":
		return false
	if c.zone == zone_id:
		return false
	c.zone = zone_id
	_eval_cell_services(cell)
	_mark(cell)
	_flush()
	return true


## Removes the zone from one cell.
func clear_zone(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _cell(cell).zone == "":
		return false
	_cell(cell).zone = ""
	_mark(cell)
	_flush()
	return true


## Growth tick: a few random zoned empty cells spawn a matching building.
## Buildings only grow on flat, buildable ground without roads, served by
## both a nearby road and a power plant.
func grow_zones(max_spawns: int = 3) -> void:
	var candidates: Array[Vector2i] = []
	for y in map_size:
		for x in map_size:
			var cell_pos := Vector2i(x, y)
			var c := _cell(cell_pos)
			if c.zone != "" and c.obj == "" and c.road == "" \
					and c.served_road and c.served_power:
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
		if place(building, cell_pos, false):
			_cell(cell_pos).grown = true  # zone-grown: needs road + power
			spawned += 1


# -- Services (road access + power) -------------------------------------------

func _is_power_plant(tile: Dictionary) -> bool:
	return tile.get("category", "") == "Power" and int(tile.get("power", 0)) > 0


func _plant_radius(tile: Dictionary) -> int:
	return clampi(int(tile.get("power", 0)) / 25, PLANT_RADIUS_MIN, PLANT_RADIUS_MAX)


## Recomputes served_road for the zoned cells around a road change. The
## incremental radius keeps drag-painting cheap (no full-map scans).
func _update_road_service(center: Vector2i) -> void:
	for dy in range(-ROAD_ACCESS_RADIUS, ROAD_ACCESS_RADIUS + 1):
		for dx in range(-ROAD_ACCESS_RADIUS, ROAD_ACCESS_RADIUS + 1):
			var pos := center + Vector2i(dx, dy)
			if not in_bounds(pos):
				continue
			var c := _cell(pos)
			if c.zone == "":
				continue
			_set_road_flag(c, pos)


func _set_road_flag(c: Cell, pos: Vector2i) -> void:
	var served := false
	for ddy in range(-ROAD_ACCESS_RADIUS, ROAD_ACCESS_RADIUS + 1):
		for ddx in range(-ROAD_ACCESS_RADIUS, ROAD_ACCESS_RADIUS + 1):
			if is_road(pos + Vector2i(ddx, ddy)):
				served = true
				break
		if served:
			break
	if served != c.served_road:
		c.served_road = served
		_mark(pos)
		_update_building_service(pos, served and c.served_power)


## Propagates (or retracts) a plant's coverage; on removal every cell in
## range is re-checked against the remaining plants.
func _update_power_service(plant_pos: Vector2i, radius: int, removed: bool) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var pos := plant_pos + Vector2i(dx, dy)
			if not in_bounds(pos):
				continue
			var c := _cell(pos)
			if c.zone == "":
				continue
			if not removed:
				if not c.served_power:
					c.served_power = true
					_mark(pos)
					_update_building_service(pos, c.served_road)
				continue
			var served := false
			for other_pos: Vector2i in _plants:
				if maxi(absi(other_pos.x - pos.x), absi(other_pos.y - pos.y)) <= _plants[other_pos]:
					served = true
					break
			if served != c.served_power:
				c.served_power = served
				_mark(pos)
				_update_building_service(pos, served and c.served_road)


## Evaluates both flags for one freshly zoned cell.
func _eval_cell_services(pos: Vector2i) -> void:
	var c := _cell(pos)
	_set_road_flag(c, pos)
	var served := false
	for plant_pos: Vector2i in _plants:
		if maxi(absi(plant_pos.x - pos.x), absi(plant_pos.y - pos.y)) <= _plants[plant_pos]:
			served = true
			break
	c.served_power = served


## Zone-grown buildings react to service loss: the population moves out
## immediately and the building collapses after ABANDON_GRACE seconds. If
## service returns in time, it recovers and the population moves back in.
func _update_building_service(pos: Vector2i, served: bool) -> void:
	var c := _cell(pos)
	if not c.grown or c.obj == "" or c.abandoned == (not served):
		return
	var inhabitants := int(catalog.get_tile(c.obj).get("inhabitants", 0))
	c.abandoned = not served
	if served:
		_abandoning.erase(pos)
		_population += inhabitants
	else:
		_abandoning[pos] = ABANDON_GRACE
		_population -= inhabitants
	_mark(pos)
	stats_changed.emit()


## Ages the abandon timers; expired buildings collapse but their zone stays
## painted, ready to grow again once the service is restored.
func tick_abandonment(delta: float) -> void:
	if _abandoning.is_empty():
		return
	var expired: Array[Vector2i] = []
	for pos: Vector2i in _abandoning:
		_abandoning[pos] -= delta
		if _abandoning[pos] <= 0.0:
			expired.append(pos)
	for pos in expired:
		_abandoning.erase(pos)
		var c := _cell(pos)
		if c.obj == "" or not c.abandoned:
			continue
		c.obj = ""
		c.obj_variant = 0
		c.obj_origin = Vector2i()
		c.obj_size = Vector2i.ONE
		c.grown = false
		c.abandoned = false
		_mark(pos)
	if not expired.is_empty():
		_flush()


func abandoned_count() -> int:
	return _abandoning.size()


## Number of zoned cells missing road access or power (debug / city advisor).
func unserved_zone_count() -> int:
	var count := 0
	for y in map_size:
		for x in map_size:
			var c := _cell(Vector2i(x, y))
			if c.zone != "" and not (c.served_road and c.served_power):
				count += 1
	return count


func is_cell_served(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var c := _cell(cell)
	return c.served_road and c.served_power


# -- Hover ----------------------------------------------------------------

func set_hovered(cell: Vector2i) -> bool:
	var changed := cell != hovered
	hovered = cell
	_hover_valid = _update_hover_validity()
	if changed:
		_hover_node.queue_redraw()
	return changed


func _update_hover_validity() -> bool:
	if selected_tool.is_empty() or not in_bounds(hovered):
		return false
	match selected_tool:
		DOZER:
			return _cell(hovered).obj != "" or _cell(hovered).zone != "" or _cell(hovered).road != ""
		DEZONE:
			return _cell(hovered).zone != ""
		RAISE, LOWER, LEVEL:
			return _cell(hovered).terrain not in WATER_TERRAINS
		_:
			if is_road_tool(selected_tool):
				return can_place_road(selected_tool, hovered)
			if is_zone_tool(selected_tool):
				return _cell(hovered).terrain not in WATER_TERRAINS and _cell(hovered).obj == "" and _cell(hovered).road == ""
			return can_place(selected_tool, hovered)


# -- Rendering ------------------------------------------------------------

## One canvas item per (x + y) diagonal, z-ordered so later diagonals paint
## over earlier ones. Vehicles slip between two diagonals with z = sum*2+1,
## which restores correct painter's-algorithm occlusion for moving sprites
## without redrawing the whole map every frame.
var _diag_nodes: Array[Node2D] = []
var _hover_node: Node2D
var _pending_sums := {}   # sum -> true, flushed to diagonal redraws

# Animated water: one canvas item for the whole body, redrawn only when the
# ripple frame advances (nothing buildable overlaps water, so it never needs
# to interleave with the per-diagonal painter's order).
var _water_node: Node2D
var _water_cells: Array[Vector2i] = []
var _water_time := 0.0
var _water_tick := -1     # last animation step displayed
var _murky_count := 0
var _water_flora_count := 0
var _shore_count := 0
var _ship_count := 0


func _process(delta: float) -> void:
	if _water_node == null or _water_cells.is_empty():
		return
	_water_time += delta
	var tick := int(_water_time * WATER_FPS)
	if tick != _water_tick:
		_water_tick = tick
		_water_node.queue_redraw()


func _rebuild_diagonals() -> void:
	for node in _diag_nodes:
		node.queue_free()
	_diag_nodes.clear()
	if _hover_node != null:
		_hover_node.queue_free()
	if _water_node != null:
		_water_node.queue_free()
	for sum in range(0, 2 * map_size - 1):
		var node := Node2D.new()
		node.z_index = sum * 2
		node.draw.connect(_draw_diagonal.bind(sum, node))
		add_child(node)
		_diag_nodes.append(node)
	_water_node = Node2D.new()
	_water_node.z_index = -1  # below every diagonal: land overlaps the shoreline
	_water_node.draw.connect(_draw_water.bind(_water_node))
	add_child(_water_node)
	_hover_node = Node2D.new()
	_hover_node.z_index = 4095  # Godot caps z_index at 4096
	_hover_node.draw.connect(_draw_hover)
	add_child(_hover_node)
	_cache_water_cells()
	_redraw_all()


## Snapshot of where the water is; the map is only regenerated wholesale, so
## the cache is refreshed together with the diagonals. Also tallies the
## smoke-test telemetry (swamp cells, water plants, shoreline tiles).
func _cache_water_cells() -> void:
	_water_cells.clear()
	_murky_count = 0
	_water_flora_count = 0
	_shore_count = 0
	_ship_count = 0
	for y in map_size:
		for x in map_size:
			var cell := _cells[x + y * map_size]
			if cell.terrain in WATER_TERRAINS:
				var cell_pos := Vector2i(x, y)
				_water_cells.append(cell_pos)
				if cell.terrain == "liquid_MurkyWater":
					_murky_count += 1
				if cell.obj.begins_with("BD_"):
					_ship_count += 1
				elif cell.obj != "":
					_water_flora_count += 1
			elif _shore_mask(Vector2i(x, y)) > 0:
				_shore_count += 1
	_water_tick = -1  # force a redraw on the next frame tick


func ships_count() -> int:
	return _ship_count


func murky_count() -> int:
	return _murky_count


func water_flora_count() -> int:
	return _water_flora_count


func shore_count() -> int:
	return _shore_count


func _redraw_all() -> void:
	for node in _diag_nodes:
		node.queue_redraw()
	if _hover_node != null:
		_hover_node.queue_redraw()


## Marks a changed cell; its diagonal is redrawn on the next flush.
func _mark(cell: Vector2i) -> void:
	_pending_sums[cell.x + cell.y] = true


func _flush() -> void:
	# during generation ships place tiles before the diagonals exist
	for sum: int in _pending_sums:
		if sum >= 0 and sum < _diag_nodes.size():
			_diag_nodes[sum].queue_redraw()
	_pending_sums.clear()


func _draw_diagonal(sum: int, canvas: CanvasItem) -> void:
	if catalog == null or _cells.is_empty():
		return
	var x_start := maxi(0, sum - map_size + 1)
	var x_end := mini(sum, map_size - 1)
	# ground pass: terrain, zone overlay, road
	for x in range(x_start, x_end + 1):
		var y := sum - x
		var cell_pos := Vector2i(x, y)
		var cell := _cell(cell_pos)
		_draw_terrain(canvas, cell_pos, cell)
		if cell.zone != "":
			_draw_zone(canvas, cell_pos, cell)
		if cell.road != "":
			_draw_road(canvas, cell_pos, cell)
	# object pass: a multi-tile object is drawn once, at the diagonal of its
	# SOUTH corner, so its own footprint cells never paint over its facade.
	for x in range(x_start, x_end + 1):
		var y := sum - x
		var cell_pos := Vector2i(x, y)
		var cell := _cell(cell_pos)
		if cell.obj != "" and cell.obj_origin == cell_pos:
			var south := cell.obj_origin + cell.obj_size - Vector2i.ONE
			if south.x + south.y == sum:
				_draw_object(canvas, cell)


func _ground_rect(region: Rect2, pos: Vector2) -> Rect2:
	## Ground-level sprites (terrain, zones, roads) share one surface line:
	## the flat diamond top sits at pos.y + 1; taller strips keep their
	## transparent elevation headroom above it.
	return Rect2(pos.x - region.size.x * 0.5, pos.y + TILE_H - region.size.y, region.size.x, region.size.y)


func _draw_terrain(canvas: CanvasItem, cell_pos: Vector2i, cell: Cell) -> void:
	if cell.terrain == "water":
		return  # drawn by the animated water layer below the diagonals
	var tile := catalog.get_tile(cell.terrain)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return

	var pos := cell_screen_pos(cell_pos)
	var h := cell.height

	# Legacy autotile table (TileSlopes): the frame is chosen from which
	# neighbors stand HIGHER — the art encodes the rise toward them plus the
	# cliff face toward lower ground on the down sides.
	var hn := height_at(cell_pos + Vector2i(0, -1)) > h
	var hw := height_at(cell_pos + Vector2i(-1, 0)) > h
	var he := height_at(cell_pos + Vector2i(1, 0)) > h
	var hs := height_at(cell_pos + Vector2i(0, 1)) > h

	# Priority: visible cliff faces toward lower down-screen neighbors
	# first, then the ramps toward higher up-screen neighbors, then the
	# far-diagonal transitions.
	var le := height_at(cell_pos + Vector2i(1, 0)) < h
	var ls := height_at(cell_pos + Vector2i(0, 1)) < h
	var slot := -1
	if le and ls: slot = 8   # double cliff SE+SW
	elif le: slot = 0       # cliff toward down-right
	elif ls: slot = 1       # cliff toward down-left
	elif hn: slot = 0       # ramp rising up-right
	elif hw: slot = 1       # ramp rising up-left
	elif he: slot = 2       # half-step toward the down-right
	elif hs: slot = 3       # half-step toward the down-left
	elif height_at(cell_pos + Vector2i(-1, -1)) > h: slot = 1
	elif height_at(cell_pos + Vector2i(1, -1)) > h: slot = 2
	elif height_at(cell_pos + Vector2i(-1, 1)) > h: slot = 3
	elif height_at(cell_pos + Vector2i(1, 1)) > h: slot = 4

	var region: Rect2
	var texture_used := texture
	if slot >= 0 and catalog.has_slopes(tile):
		region = catalog.get_slope_region(tile, slot)
	else:
		# flat ground: land hugging water shows the shoreline sprite whose
		# water pockets match the corners that touch it
		var mask := _shore_mask(cell_pos)
		if mask > 0 and catalog.has_shoreline(tile):
			region = catalog.get_shore_region(tile, mask)
			texture_used = catalog.get_shore_texture(tile)
		else:
			region = catalog.get_region(tile, texture.get_height(), cell.terrain_variant)

	canvas.draw_texture_rect_region(texture_used, _ground_rect(region, pos), region)


## Corner mask for the shoreline autotile, one bit per diamond corner:
## screen down-right corner (grid E+S) = 1, screen up-right (N+E) = 2,
## screen up-left (W+N) = 4, screen down-left (S+W) = 8. A bit is set when
## water touches that corner — either edge neighbor adjacent to it, or the
## diagonal neighbor sitting in the corner itself.
const SHORE_CORNERS := [
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), 1],      # SE
	[Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1), 2],    # NE
	[Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), 4],  # NW
	[Vector2i(-1, 0), Vector2i(0, 1), Vector2i(-1, 1), 8],    # SW
]


func _shore_mask(cell_pos: Vector2i) -> int:
	var mask := 0
	for corner in SHORE_CORNERS:
		if is_water_cell(cell_pos + corner[0]) or is_water_cell(cell_pos + corner[1]) \
				or is_water_cell(cell_pos + corner[2]):
			mask += corner[3]
	return mask


## Ripple frame a water cell shows at a given animation step. Cells are
## staggered by a position hash so waves travel across the body instead of
## the whole lake flashing in lockstep.
func water_variant_at(terrain_id: String, cell_pos: Vector2i, step: int) -> int:
	var tile := catalog.get_tile(terrain_id)
	var count: int = maxi(1, int(tile.get("tiles", {}).get("count", 1)))
	return (step + (cell_pos.x * 7 + cell_pos.y * 13) % count) % count


func _draw_water(canvas: CanvasItem) -> void:
	if catalog == null or _water_cells.is_empty():
		return
	var step := int(_water_time * WATER_FPS)
	# both water terrains cycle their own 3-frame sheet; prepare each once
	var prepared := {}  # terrain id -> [tile, texture]
	for cell_pos in _water_cells:
		var terrain: String = _cell(cell_pos).terrain
		if not prepared.has(terrain):
			var tile := catalog.get_tile(terrain)
			var texture := catalog.get_texture(tile)
			if texture == null:
				return
			prepared[terrain] = [tile, texture]
		var tile: Dictionary = prepared[terrain][0]
		var texture: Texture2D = prepared[terrain][1]
		var region := catalog.get_region(tile, texture.get_height(), water_variant_at(terrain, cell_pos, step))
		canvas.draw_texture_rect_region(texture, _ground_rect(region, cell_screen_pos(cell_pos)), region)


func _draw_road(canvas: CanvasItem, cell_pos: Vector2i, cell: Cell) -> void:
	var tile := catalog.get_tile(cell.road)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return
	var region := catalog.get_region(tile, texture.get_height(), cell.road_variant)
	canvas.draw_texture_rect_region(texture, _ground_rect(region, cell_screen_pos(cell_pos)), region)


## Zone overlay: drawn lifted with the tile, under any building. Zones
## missing road access or power show up darkened (SimCity visual language).
func _draw_zone(canvas: CanvasItem, cell_pos: Vector2i, cell: Cell) -> void:
	var tile := catalog.get_tile(cell.zone)
	var texture := catalog.get_texture(tile)
	if texture == null:
		return
	var region := catalog.get_region(tile, texture.get_height(), 0)
	var tint := Color(1, 1, 1) if cell.served_road and cell.served_power \
			else Color(0.45, 0.5, 0.62)
	canvas.draw_texture_rect_region(texture, _ground_rect(region, cell_screen_pos(cell_pos)), region, tint)


func _draw_object(canvas: CanvasItem, cell: Cell) -> void:
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
	var tint := Color(0.42, 0.42, 0.48) if cell.abandoned else Color(1, 1, 1)
	canvas.draw_texture_rect_region(texture, rect, region, tint)


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

	_hover_node.draw_colored_polygon(PackedVector2Array([top, right, bottom, left]), color)
	_hover_node.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(color, 0.9), 1.0)

	# Ghost preview of the tile about to be placed.
	if not is_terrain_tool and selected_tool != DOZER and _hover_valid:
		var texture := catalog.get_texture(tile)
		if texture != null:
			var region := catalog.get_region(tile, texture.get_height(), 0)
			var center := iso_to_screen(origin.x + (size.x - 1) * 0.5, origin.y + (size.y - 1) * 0.5) - Vector2(0, lift)
			var bottom_y := iso_to_screen(origin.x + size.x - 1, origin.y + size.y - 1).y + TILE_H - lift
			var rect := Rect2(center.x - region.size.x * 0.5, bottom_y - region.size.y, region.size.x, region.size.y)
			_hover_node.draw_texture_rect_region(texture, rect, region, Color(1, 1, 1, 0.55))
