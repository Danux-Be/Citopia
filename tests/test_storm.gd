extends SceneTree

## Headless checks for thunderstorms: blackouts, fires, storm transitions.

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
	map.generate_map({"seed": 7, "water_pct": 0, "trees_pct": 10})
	for x in range(10, 22):
		map.place_road("road_paved", Vector2i(x, 20))
	for y in range(15, 25):
		if y != 20:
			map.paint_zone(Vector2i(12, y), "zone_residential_medium")
	var plant_id := ""
	for id in map.catalog.get_ids_by_category("Power"):
		plant_id = id
		break
	if plant_id != "":
		map.place(plant_id, Vector2i(16, 16), false)
	var plants := map.plant_origins()
	check(plants.size() > 0, "a plant exists (%d)" % plants.size())
	if plants.is_empty():
		print("TEST_RESULT failures=%d" % failures)
		quit(1)
		return
	var plant: Vector2i = plants[0]
	for tick in 200:
		map.grow_zones(3)
	check(map.get_population() > 0, "buildings grew (pop %d)" % map.get_population())

	# blackout: zones lose power, then it comes back exactly
	var served_before := 0
	for y in map.map_size:
		for x in map.map_size:
			if map._cell(Vector2i(x, y)).served_power:
				served_before += 1
	map.set_plant_disabled(plant, true)
	var served_off := 0
	for y in map.map_size:
		for x in map.map_size:
			if map._cell(Vector2i(x, y)).served_power:
				served_off += 1
	check(served_off < served_before, "blackout cuts power (%d -> %d)" % [served_before, served_off])
	map.set_plant_disabled(plant, false)
	var served_back := 0
	for y in map.map_size:
		for x in map.map_size:
			if map._cell(Vector2i(x, y)).served_power:
				served_back += 1
	check(served_back == served_before, "power restored exactly")

	# fire: burn a grown building
	var building := map.random_grown_building()
	check(building.x >= 0, "a grown building exists at %s" % building)
	map.set_burning(building, true)
	check(map._cell(building).burning, "building cell flagged burning")
	map.set_burning(building, false)
	check(not map._cell(building).burning, "fire extinguish clears the flag")

	# weather storm state + strike signal
	var weather := Weather.new()
	root.add_child(weather)
	weather._ready()
	weather.process_mode = Node.PROCESS_MODE_DISABLED
	weather.force_rain()
	var rain_total := 0
	for l in weather._rain_layers:
		rain_total += l.amount
	check(weather.state == Weather.State.RAIN and absi(rain_total - int(Weather.RAIN_AMOUNT)) <= 8,
		"rain keeps gentle intensity (%d)" % rain_total)
	var struck := [0]
	weather.lightning_struck.connect(func() -> void: struck[0] += 1)
	weather._enter(Weather.State.STORM)
	var storm_total := 0
	for l in weather._rain_layers:
		storm_total += l.amount
	check(weather.is_storm() and absi(storm_total - int(Weather.STORM_AMOUNT)) <= 8, "storm raises the rain (%d)" % storm_total)
	check(weather._tint_target == Weather.STORM_TINT_ALPHA, "storm gloom deeper")
	check(weather._next_thunder <= Weather.STORM_THUNDER_RANGE.y, "storm thunder frequent")
	weather._thunder_time = weather._next_thunder
	weather._process(0.016)
	check(struck[0] <= 1, "strike signal fired at most once per clap")
	weather._state_time = weather._next_change + 0.1
	weather._process(0.016)
	check(weather.state == Weather.State.SUNNY, "storm ends on schedule")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
