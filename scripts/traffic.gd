class_name Traffic
extends Node2D

## Road traffic manager: keeps a cache of the road network, routes vehicles
## with breadth-first pathfinding (uniform grid cost) between road cells next
## to buildings, and grows/shrinks the fleet with the city's population.

const MAX_VEHICLES := 14
const SPAWN_INTERVAL := 1.6

const SHEET := "res://assets/images/vehicles/vehicles.png"
const FRAME := 28
const COLOR_COUNT := 6

var iso_map: IsoMap

var _vehicles: Array[Vehicle] = []
var _roads := {}            # Vector2i -> true, rebuilt on roads_changed
var _spawn_timer := 0.0
var _sheet: Texture2D
var _next_color := 0


func setup(p_iso_map: IsoMap) -> void:
	iso_map = p_iso_map
	_sheet = load(SHEET)
	iso_map.roads_changed.connect(_on_roads_changed)
	_rebuild_roads()


func _on_roads_changed() -> void:
	_rebuild_roads()
	# vehicles standing on removed road cells finish their trip immediately
	for vehicle in _vehicles.duplicate():
		if not _on_network(vehicle):
			_despawn(vehicle)


func _rebuild_roads() -> void:
	_roads.clear()
	if iso_map == null:
		return
	for y in iso_map.map_size:
		for x in iso_map.map_size:
			var cell := Vector2i(x, y)
			if iso_map.is_road(cell):
				_roads[cell] = true


func _on_network(vehicle: Vehicle) -> bool:
	return vehicle.path.size() < 2 \
			or (_roads.has(vehicle.path[vehicle.path_i]) and _roads.has(vehicle.path[vehicle.path_i + 1]))


func _process(delta: float) -> void:
	if iso_map == null:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_INTERVAL
	var target := _target_fleet()
	while _vehicles.size() > target:
		_despawn(_vehicles[0])
	if _vehicles.size() < target:
		_spawn_one()


## Fleet size follows the city: a couple of passers-by as soon as there is a
## road network, then roughly one vehicle per 30 inhabitants (capped).
func _target_fleet() -> int:
	if _roads.size() < 6:
		return 0
	var pop := iso_map.get_population()
	return clampi(2 + pop / 30, 2, MAX_VEHICLES)


func _spawn_one() -> void:
	var start := _pick_populated_road()
	var path := _longest_of_candidates(start)
	if path.size() < 2:
		return
	var vehicle := Vehicle.new()
	vehicle.trip_finished.connect(_on_trip_finished)
	add_child(vehicle)
	_vehicles.append(vehicle)
	vehicle.setup(iso_map, _sheet, _next_color % COLOR_COUNT, path)
	_next_color += 1


## Sample a few random goals and keep the longest route: trips spread over
## the network instead of hopping between two adjacent cells.
func _longest_of_candidates(start: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for _attempt in 3:
		var goal := _pick_populated_road() if randf() < 0.7 else _pick_road()
		var path := find_path(start, goal)
		if path.size() > best.size():
			best = path
	return best


func _on_trip_finished(vehicle: Vehicle) -> void:
	# reuse the car for a new trip unless the fleet should shrink
	if _vehicles.size() > _target_fleet() or not _vehicles.has(vehicle):
		_despawn(vehicle)
		return
	var start := vehicle.path[vehicle.path.size() - 1]
	var path := _longest_of_candidates(start)
	if path.size() < 2:
		_despawn(vehicle)
		return
	vehicle.setup(iso_map, _sheet, vehicle.color_index, path)


func _despawn(vehicle: Vehicle) -> void:
	_vehicles.erase(vehicle)
	vehicle.queue_free()


## Road cells that touch a building or a zone (trip generators), if any.
func _pick_populated_road() -> Vector2i:
	var populated: Array[Vector2i] = []
	for cell: Vector2i in _roads:
		for n: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if iso_map.obj_at(cell + n) != "" or iso_map.zone_at(cell + n) != "":
				populated.append(cell)
				break
	if not populated.is_empty():
		return populated[randi() % populated.size()]
	return _pick_road()


func _pick_road() -> Vector2i:
	var keys := _roads.keys()
	return keys[randi() % keys.size()]


## Debug/telemetry helpers (used by the --shot self-capture).
func road_count() -> int:
	return _roads.size()


func target_fleet() -> int:
	return _target_fleet()


## Breadth-first search over the 4-connected road grid. Returns the cell
## path including both ends, or an empty array when unreachable.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not _roads.has(start) or not _roads.has(goal) or start == goal:
		return path
	var came_from := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == goal:
			break
		for n: Vector2i in [current + Vector2i(0, -1), current + Vector2i(1, 0), current + Vector2i(0, 1), current + Vector2i(-1, 0)]:
			if _roads.has(n) and not came_from.has(n):
				came_from[n] = current
				queue.append(n)
	if not came_from.has(goal):
		return path
	var cell := goal
	while cell != start:
		path.push_front(cell)
		cell = came_from[cell]
	path.push_front(start)
	return path
