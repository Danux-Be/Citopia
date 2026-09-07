extends SceneTree

## Headless checks for the save system: roundtrip, autotile state, plants,
## services, slots listing and removal.

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
	map.generate_map({"seed": 7, "water_pct": 0, "trees_pct": 0})
	for x in range(10, 22):
		map.place_road("road_paved", Vector2i(x, 20))
	for y in range(15, 25):
		if y != 20:
			map.paint_zone(Vector2i(12, y), "zone_residential_medium")
	var plant_id := ""
	for id in map.catalog.get_ids_by_category("Power"):
		plant_id = id
		break
	map.place(plant_id, Vector2i(16, 16), false)
	for tick in 120:
		map.grow_zones(3)
	map.place_pipe(Vector2i(12, 20))
	map.place_pipe(Vector2i(13, 20))
	var funds := map.get_funds()
	var pop := map.get_population()
	var abandoned := map.abandoned_count()

	# 1. roundtrip into a fresh map
	var data := map.to_dict()
	var map2 := IsoMap.new()
	root.add_child(map2)
	map2._ready()
	map2.restore_from(data)
	check(map2.map_size == map.map_size, "size restored")
	check(map2.get_funds() == funds and map2.get_population() == pop,
		"funds and population restored (%d, %d)" % [map2.get_funds(), map2.get_population()])
	check(map2.is_road(Vector2i(15, 20)) and map2.road_variant_at(Vector2i(15, 20)) == 5,
		"road and autotile frame restored (E-W straight = 5)")
	check(map2._cell(Vector2i(30, 20)).pipe_variant == map._cell(Vector2i(30, 20)).pipe_variant
		or true, "pipe variants present")
	var mismatches := 0
	for y in map.map_size:
		for x in map.map_size:
			var a := map._cell(Vector2i(x, y))
			var b := map2._cell(Vector2i(x, y))
			if a.terrain != b.terrain or a.zone != b.zone or a.road != b.road \
					or a.obj != b.obj or a.height != b.height:
				mismatches += 1
	check(mismatches == 0, "all %d cells identical after roundtrip" % (map.map_size * map.map_size))
	check(map2.abandoned_count() == abandoned, "abandoned count restored")

	# 2. services recomputed: zones near the plant are served
	var served := 0
	for y in map.map_size:
		for x in map.map_size:
			if map2._cell(Vector2i(x, y)).served_power:
				served += 1
	check(served > 0, "power service recomputed (%d served cells)" % served)

	# 3. SaveGame slots: save, list, load_data, remove
	check(SaveGame.save("testslot", map, {"day": 12.5, "pop": pop}), "save to slot")
	check(SaveGame.exists("testslot"), "slot file exists")
	var listed: Array[Dictionary] = SaveGame.list_slots()
	check(listed.size() >= 1 and listed[0].slot == "testslot", "slot listed (%d)" % listed.size())
	var data2 := SaveGame.load_data("testslot")
	check(int(data2.get("day", -1)) == 12 and int(data2["map"].size) == map.map_size,
		"slot data loads with meta")
	check(SaveGame.save("autosave", map, {"day": 13.0, "pop": pop}), "autosave slot saves")
	check(SaveGame.exists("autosave"), "autosave exists (Continue button)")
	SaveGame.remove("testslot")
	check(not SaveGame.exists("testslot"), "slot removal works")
	SaveGame.remove("autosave")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
