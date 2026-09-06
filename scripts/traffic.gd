class_name Traffic
extends Node2D

## Road traffic manager: keeps a cache of the road network, routes vehicles
## with breadth-first pathfinding (uniform grid cost) between road cells next
## to buildings, and grows/shrinks the fleet with the city's population.

const MAX_VEHICLES := 14
const SPAWN_INTERVAL := 1.6

## Driving rules (distances are fractions of a cell).
const JUNCTION_SLOW := 0.65    # top speed cap while closing on a junction cell
const TURN_SLOW := 0.55        # top speed cap while closing on a turn
const DECISION_DIST := 0.45    # start yielding when this close to the junction
const YIELD_TIMEOUT := 3.0     # stopped this long -> ignore right-of-way (no gridlock)
const FOLLOW_MIN_GAP := 0.30   # full stop when a car ahead is closer than this
const FOLLOW_FREE_GAP := 0.55  # no constraint beyond this gap

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
	_regulate()
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_INTERVAL
	var target := _target_fleet()
	while _vehicles.size() > target:
		_despawn(_vehicles[0])
	if _vehicles.size() < target:
		_spawn_one()


## Per-frame speed caps: car following, junction approach, priority to the
## right. Runs before the vehicles integrate their movement.
func _regulate() -> void:
	for v in _vehicles:
		v.speed_factor = 1.0
		if v.path.size() < 2 or v.path_i >= v.path.size() - 1:
			continue
		var factor := _follow_factor(v)
		var approaching := is_junction(v.seg_to())
		if not approaching:
			v.ignore_yield = false  # junction behind: fresh right-of-way next time
		if approaching:
			# close to a crossing: everyone slows, and only those with
			# right-of-way (or a deadlock timeout) may enter
			factor = minf(factor, JUNCTION_SLOW)
			if 1.0 - v.t <= DECISION_DIST:
				if v.wait_time >= YIELD_TIMEOUT:
					v.ignore_yield = true  # latch: commit instead of creeping
				if _junction_occupied(v, v.seg_to()):
					factor = 0.0  # someone is crossing: they always win
				elif not v.ignore_yield and _must_yield(v):
					factor = 0.0  # priorité à droite
		elif v.path_i < v.path.size() - 2 and v.t > 0.5 \
				and v.path[v.path_i + 2] - v.seg_to() != v.dir():
			factor = minf(factor, TURN_SLOW)
		v.speed_factor = factor


## Gap to the nearest vehicle ahead on the same or the next segment,
## mapped to a 0..1 speed cap so queues form instead of overlaps.
func _follow_factor(v: Vehicle) -> float:
	var factor := 1.0
	for other in _vehicles:
		if other == v or other.path.size() < 2 or other.path_i >= other.path.size() - 1:
			continue
		var gap := -1.0
		if other.seg_from() == v.seg_from() and other.seg_to() == v.seg_to() and other.t > v.t:
			gap = other.t - v.t
		elif other.seg_from() == v.seg_to() and other.seg_to() == v.seg_to() + v.dir():
			gap = (1.0 - v.t) + other.t
		if gap >= 0.0:
			factor = minf(factor, clampf(
					(gap - FOLLOW_MIN_GAP) / (FOLLOW_FREE_GAP - FOLLOW_MIN_GAP), 0.0, 1.0))
	return factor


## A road cell with 3+ connections (T junction or crossroads).
func is_junction(cell: Vector2i) -> bool:
	if not _roads.has(cell):
		return false
	var links := 0
	for n: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if _roads.has(cell + n):
			links += 1
	return links >= 3


## Is another vehicle committed to and still inside the junction v
## approaches? Only cars already crossing count: cars waiting at the
## entrance also straddle the junction cell (braking overshoot) but must
## never block each other.
func _junction_occupied(v: Vehicle, junction: Vector2i) -> bool:
	for other in _vehicles:
		if other != v and other.seg_from() == junction and other.t < 0.5:
			return true
	return false


## Right-of-way: v yields to anyone entering the same junction from its
## right-hand side. right(dir) = (-dir.y, dir.x), so a vehicle driving in
## direction -right(v.dir) comes from v's right.
func _must_yield(v: Vehicle) -> bool:
	var d := v.dir()
	var from_right := Vector2i(d.y, -d.x)
	for other in _vehicles:
		if other == v or other.path.size() < 2 or other.path_i >= other.path.size() - 1:
			continue
		if other.seg_to() == v.seg_to() and other.dir() == from_right and other.t > 0.3:
			return true
	return false


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
	spawn_on_path(path)


## Put a vehicle on an explicit cell path (also the test seam).
func spawn_on_path(path: Array[Vector2i]) -> Vehicle:
	var vehicle := Vehicle.new()
	vehicle.trip_finished.connect(_on_trip_finished)
	add_child(vehicle)
	_vehicles.append(vehicle)
	vehicle.setup(iso_map, _sheet, _next_color % COLOR_COUNT, path)
	_next_color += 1
	return vehicle


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


func stopped_count() -> int:
	var count := 0
	for v in _vehicles:
		if v.speed < 0.15:
			count += 1
	return count


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
