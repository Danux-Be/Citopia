extends SceneTree

## Headless checks for the underground water pipes layer.

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
	map.generate_map({"seed": 7, "water_pct": 30})
	var funds0: int = map.get_funds()

	# 1. pipes place on land, refused on water
	check(map.place_pipe(Vector2i(30, 20)), "pipe placed on land")
	check(not map.is_pipe(Vector2i(30, 21)), "single pipe is one cell")
	var water := Vector2i(-1, -1)
	for y in map.map_size:
		for x in map.map_size:
			if map.is_water_cell(Vector2i(x, y)):
				water = Vector2i(x, y)
				break
		if water.x >= 0:
			break
	check(water.x >= 0, "map has water")
	check(not map.place_pipe(water), "pipes refused on water")
	check(map.get_funds() < funds0, "pipes charge funds")

	# 2. autotile: straight + corner get bit-identity variants
	map.place_pipe(Vector2i(29, 20))
	map.place_pipe(Vector2i(31, 20))
	map.place_pipe(Vector2i(31, 21))
	check(map._cell(Vector2i(30, 20)).pipe_variant == 5, "straight pipe E-W -> mask 5")
	check(map._cell(Vector2i(31, 20)).pipe_variant == 12, "corner W+S -> mask 12")
	check(map._cell(Vector2i(31, 21)).pipe_variant == 2, "dead-end N -> mask 2")
	map.remove_pipe(Vector2i(31, 21))
	check(map._cell(Vector2i(31, 20)).pipe_variant == 4, "removing the tail re-autotiles the corner (W only)")

	# 3. pipes coexist with roads (that is the point of underground pipes)
	map.place_road("road_paved", Vector2i(30, 20))
	check(map.is_pipe(Vector2i(30, 20)) and map.is_road(Vector2i(30, 20)),
		"pipe and road coexist on one cell")

	# 4. bulldozer removes pipes (after buildings/roads)
	map.place_pipe(Vector2i(31, 21))
	check(map.demolish(Vector2i(31, 21)), "dozer removes a pipe")
	check(not map.is_pipe(Vector2i(31, 21)), "pipe gone after dozer")
	# pipe under a road: first doze removes the road, second the pipe
	map.place_pipe(Vector2i(30, 21))
	map.remove_road(Vector2i(30, 20))
	map.place_road("road_paved", Vector2i(30, 20))
	check(map.demolish(Vector2i(30, 20)), "doze road+pipe cell")
	check(map.is_road(Vector2i(30, 20)) == false, "road removed first")
	check(map.is_pipe(Vector2i(30, 20)), "pipe still there under the road")
	check(map.demolish(Vector2i(30, 20)), "second doze removes the pipe")
	check(not map.is_pipe(Vector2i(30, 20)), "pipe removed on the second pass")

	# 5. underground view is a pure display flag
	map.underground_view = true
	check(map.underground_view, "underground view toggles on")
	check(map.is_pipe(Vector2i(30, 21)), "toggling keeps the pipes")
	map.underground_view = false
	check(not map.underground_view, "underground view toggles off")

	# 6. funds stop pipe placement when broke
	map._funds = 0
	check(not map.place_pipe(Vector2i(32, 20)), "no funds, no pipes")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
