class_name Pedestrians
extends Node2D

## Pedestrian life: slices individual 1x3 px citizens out of the legacy
## crowd decoration sheets (BD_1x1_People_kt, BD_1x1_Villagers) and keeps a
## wandering fleet on the road network's curb line, scaling with the city's
## population like the vehicle fleet does.

const SHEETS := [
	"res://assets/images/decoration/buildings/BD_1x1_People_kt.png",
	"res://assets/images/decoration/buildings/BD_1x1_Villagers.png",
]
const TILE_W := 32
const TILE_H := 15
const SPAWN_INTERVAL := 0.4
const MAX_PEDS := 40

var iso_map: IsoMap

var _figures: Array[Texture2D] = []
var _peds: Array[Pedestrian] = []
var _roads := {}            # Vector2i -> true, rebuilt on roads_changed
var _spawn_timer := 0.0


func setup(p_iso_map: IsoMap) -> void:
	iso_map = p_iso_map
	iso_map.roads_changed.connect(_on_roads_changed)
	_extract_figures()
	_rebuild_roads()


func figure_count() -> int:
	return _figures.size()


func ped_count() -> int:
	return _peds.size()


func target_fleet() -> int:
	return clampi(iso_map.get_population() / 25, 0, MAX_PEDS)


func _process(delta: float) -> void:
	if iso_map == null:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_INTERVAL
	var target := target_fleet()
	while _peds.size() > target:
		_despawn(_peds[0])
	if _peds.size() < target:
		_spawn_one()


# -- Figure extraction ------------------------------------------------------

## Flood-fills every crowd tile and keeps each opaque blob >= 2 px tall as
## its own pedestrian texture, so walkers differ in color and stance.
func _extract_figures() -> void:
	_figures.clear()
	for sheet_path in SHEETS:
		var texture := load(sheet_path) as Texture2D
		if texture == null:
			continue
		var img := texture.get_image()
		if img.is_compressed():
			img.decompress()
		for tile in range(img.get_width() / TILE_W):
			_slice_tile(img, tile * TILE_W)


func _slice_tile(img: Image, x0: int) -> void:
	var seen := {}
	for y in TILE_H:
		for x in TILE_W:
			var p := Vector2i(x, y)
			if seen.has(p) or img.get_pixelv(p + Vector2i(x0, 0)).a < 0.4:
				continue
			var blob := _flood_fill(img, x0, p, seen)
			if blob.size.y >= 2 and blob.size.x <= 2:
				_figures.append(_crop_figure(img, x0, blob))
			else:
				for q: Vector2i in blob.pixels:
					seen[q] = true  # merged blob or stray pixel: skip


func _flood_fill(img: Image, x0: int, start: Vector2i, seen: Dictionary) -> Dictionary:
	var pixels: Array[Vector2i] = []
	var stack := [start]
	var min_c := start
	var max_c := start
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if seen.has(p) or img.get_pixelv(p + Vector2i(x0, 0)).a < 0.4:
			continue
		seen[p] = true
		pixels.append(p)
		min_c = Vector2i(mini(min_c.x, p.x), mini(min_c.y, p.y))
		max_c = Vector2i(maxi(max_c.x, p.x), maxi(max_c.y, p.y))
		for n in [p + Vector2i(1, 0), p + Vector2i(-1, 0), p + Vector2i(0, 1), p + Vector2i(0, -1)]:
			if n.x >= 0 and n.x < TILE_W and n.y >= 0 and n.y < TILE_H:
				stack.append(n)
	return {"pixels": pixels, "min": min_c, "max": max_c, "size": max_c - min_c + Vector2i.ONE}


func _crop_figure(img: Image, x0: int, blob: Dictionary) -> ImageTexture:
	var size: Vector2i = blob.size
	var min_c: Vector2i = blob.min
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for p: Vector2i in blob.pixels:
		out.set_pixelv(p - min_c, img.get_pixelv(p + Vector2i(x0, 0)))
	return ImageTexture.create_from_image(out)


# -- Fleet ------------------------------------------------------------------

func _spawn_one() -> void:
	var start := _pick_spot()
	if start.x < 0:
		return
	var ped := Pedestrian.new()
	ped.left_network.connect(_despawn)
	add_child(ped)
	_peds.append(ped)
	ped.setup(iso_map, _figures[randi() % _figures.size()], randf_range(0.5, 0.75), start)


## Test seam: drop a pedestrian on an explicit road cell.
func spawn_at(cell: Vector2i) -> Pedestrian:
	var ped := Pedestrian.new()
	ped.left_network.connect(_despawn)
	add_child(ped)
	_peds.append(ped)
	ped.setup(iso_map, _figures[randi() % _figures.size()], 0.6, cell)
	return ped


func _despawn(ped: Pedestrian) -> void:
	_peds.erase(ped)
	ped.queue_free()


## Prefers road cells bordering zoned land (where sidewalks see foot
## traffic), falls back to anywhere on the network.
func _pick_spot() -> Vector2i:
	if _roads.is_empty():
		return Vector2i(-1, -1)
	var keys := _roads.keys()
	for attempt in 40:
		var cell: Vector2i = keys[randi() % keys.size()]
		for n in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			if iso_map.zone_at(cell + n) != "":
				return cell
	return keys[randi() % keys.size()]


func _on_roads_changed() -> void:
	_rebuild_roads()
	for ped in _peds.duplicate():
		if not _roads.has(ped.cur_cell) or not _roads.has(ped.prev_cell):
			_despawn(ped)


func _rebuild_roads() -> void:
	_roads.clear()
	if iso_map == null:
		return
	for y in iso_map.map_size:
		for x in iso_map.map_size:
			var cell := Vector2i(x, y)
			if iso_map.is_road(cell):
				_roads[cell] = true
