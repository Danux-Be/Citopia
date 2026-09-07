extends SceneTree

## Headless checks for pedestrians: figure slicing, walking, step bob,
## network adherence and bulldozer pruning.

var failures := 0
const DT := 1.0 / 60.0


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
	map.generate_map({"seed": 7, "water_pct": 0})
	for i in range(14, 27):
		map.place_road("road_paved", Vector2i(i, 20))
	for i in range(15, 26):
		if i != 20:
			map.place_road("road_paved", Vector2i(20, i))
	for i in range(14, 21):
		map.paint_zone(Vector2i(i, 21), "zone_residential_medium")

	var peds := Pedestrians.new()
	map.add_child(peds)
	peds.setup(map)
	peds.process_mode = Node.PROCESS_MODE_DISABLED

	# 1. figures were sliced from the crowd sheets
	check(peds.figure_count() >= 12, "figures sliced from crowd sheets (%d)" % peds.figure_count())

	# 2. spawn + walk: position advances, stays on the network
	var ped := peds.spawn_at(Vector2i(15, 20))
	var start_pos: Vector2 = ped.position
	var moved := false
	for step in 240:
		ped._process(DT)
		if ped.position.distance_to(start_pos) > 2.0:
			moved = true
		var cell := ped.cur_cell
		if cell.x < 13 or cell.x > 27 or cell.y < 18 or cell.y > 22:
			check(false, "wandered off network to %s" % cell)
			break
	check(moved, "pedestrian walks along the network")
	check(map.is_road(ped.cur_cell), "current cell is a road")

	# 3. never walks into the zoned grass: stays on road cells across the run
	var on_road := true
	for step in 600:
		ped._process(DT)
		if not map.is_road(ped.cur_cell) or not map.is_road(ped.prev_cell):
			on_road = false
			break
	check(on_road, "600 steps without leaving the roads")

	# 4. the step bob toggles while walking
	var p2 := peds.spawn_at(Vector2i(15, 20))
	var seen_states := {}
	for step in 90:
		p2._process(DT)
		seen_states[p2._bob] = true
	check(seen_states.size() == 2, "step bob alternates (walk animation)")

	# 5. corner rule: no immediate double-back except at dead ends
	var corners := {}
	for step in 1200:
		p2._process(DT)
		if p2.t >= 1.0:
			corners[p2.cur_cell] = true
	check(corners.size() >= 3, "explores several corners (%d)" % corners.size())

	# 6. pause behavior exists and freezes movement
	p2._pause_left = 1.0
	var frozen: Vector2 = p2.position
	for step in 30:
		p2._process(DT)
	check(p2.position == frozen, "pausing freezes the walker")

	# 7. bulldozing the road prunes walkers
	var p3 := peds.spawn_at(Vector2i(25, 20))
	check(peds.ped_count() >= 3, "three walkers alive")
	map.remove_road(Vector2i(25, 20))
	peds._on_roads_changed()
	check(not is_instance_valid(p3) or p3.is_queued_for_deletion(),
		"walker pruned when its road is removed")

	# 8. fleet target scales with population and is capped
	var house := "res_1x1_LonelyJohnsHouse"
	if map.catalog.has_tile(house):
		map._cell(Vector2i(15, 21)).obj = ""  # a generation tree may sit there
		check(map.place(house, Vector2i(15, 21), false), "house placed for population")
	check(peds.target_fleet() == clampi(map.get_population() / 25, 0, Pedestrians.MAX_PEDS),
		"fleet target follows population")
	check(peds.target_fleet() <= Pedestrians.MAX_PEDS, "fleet target capped")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
