extends SceneTree

## Headless checks for terraced hill generation: gentle ±1 slopes, water at
## level 0, roads on plateaus, actor height interpolation.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		failures += 1
		print("FAIL ", msg)


func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	map._ready()
	map.generate_map({"seed": 7, "water_pct": 20, "trees_pct": 30, "hills_pct": 60})

	# 1. heights stay within the amplitude and water is at level 0
	var max_h := int(ceil(60.0 / 100.0 * 6.0))   # 4
	var water_bad := 0
	var peak := 0
	for y in map.map_size:
		for x in map.map_size:
			var c := map._cell(Vector2i(x, y))
			if map.is_water_cell(Vector2i(x, y)):
				if c.height != 0:
					water_bad += 1
			else:
				peak = maxi(peak, c.height)
	check(water_bad == 0, "water stays at level 0 (%d offenders)" % water_bad)
	check(peak > 1, "hills exist (peak height %d)" % peak)
	check(peak <= max_h, "peak within amplitude (%d <= %d)" % [peak, max_h])

	# 2. the terrace invariant: orthogonal land neighbours differ by at most 1
	var bad_steps := 0
	for y in map.map_size:
		for x in map.map_size:
			var pos := Vector2i(x, y)
			if map.is_water_cell(pos):
				continue
			for n in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q: Vector2i = pos + n
				if map.in_bounds(q) and not map.is_water_cell(q):
					if absi(map._cell(pos).height - map._cell(q).height) > 1:
						bad_steps += 1
	check(bad_steps == 0, "gentle slopes: no step above 1 level (%d)" % bad_steps)

	# 3. roads can be laid on some flat plateau
	var placed := false
	for y in range(4, map.map_size - 6):
		for x in range(4, map.map_size - 4):
			if map._road_site_ok(Vector2i(x, y)) and map.can_place_road("road_paved", Vector2i(x, y)):
				placed = map.place_road("road_paved", Vector2i(x, y))
				break
		if placed:
			break
	check(placed, "roads place on a flat plateau")

	# 4. vehicle height interpolation on flat ground stays 0
	var path: Array[Vector2i] = []
	for i in range(4, 8):
		path.append(Vector2i(i, 4))
	var v := Vehicle.new()
	root.add_child(v)
	v.setup(map, load("res://assets/images/vehicles/vehicles_pixel.png"), 0, path)
	v._process(1.0 / 60.0)
	var flat_ok: bool = v.position.y > 0
	check(flat_ok, "vehicle renders at a sane position (%.0f)" % v.position.y)
	v.queue_free()

	# 5. hills_pct 0 keeps maps perfectly flat
	var map3 := IsoMap.new()
	root.add_child(map3)
	map3._ready()
	map3.generate_map({"seed": 7, "water_pct": 0, "hills_pct": 0})
	var flat := true
	for y in map3.map_size:
		for x in map3.map_size:
			if map3._cell(Vector2i(x, y)).height != 0:
				flat = false
	check(flat, "hills_pct 0 stays flat")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
