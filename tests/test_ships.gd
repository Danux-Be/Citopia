extends SceneTree

## Headless checks for the demo-dry-land fix and the moored ships.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		failures += 1
		print("FAIL ", msg)


func _rect_wet(map: IsoMap, rect: Vector2i, w: int, h: int) -> int:
	var wet := 0
	for dy in h:
		for dx in w:
			if map._cell(rect + Vector2i(dx, dy)).terrain in IsoMap.WATER_TERRAINS:
				wet += 1
	return wet


func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	map._ready()

	# 1. ships spawn on lake-rich maps, inside open clear water
	map.generate_map({"seed": 5, "water_pct": 45})
	check(map.ships_count() >= 1, "ships moored on a lake-rich map (%d)" % map.ships_count())
	var hulls_ok := true
	var ship_cells := 0
	var ship_count := 0
	for y in map.map_size:
		for x in map.map_size:
			var c := map._cell(Vector2i(x, y))
			if not c.obj.begins_with("BD_"):
				continue
			ship_cells += 1
			if c.obj_origin == Vector2i(x, y):
				ship_count += 1
				for dy in range(-1, 5):
					for dx in range(-1, 5):
						var n := map._cell(c.obj_origin + Vector2i(dx, dy))
						var in_hull := dx >= 0 and dx < 2 and dy >= 0 and dy < 2
						if in_hull:
							if n.terrain != "water" or n.obj == "":
								hulls_ok = false
						elif n.terrain not in IsoMap.WATER_TERRAINS:
							hulls_ok = false  # mooring ring must be water (reeds welcome)
	check(hulls_ok, "every ship floats in a calm 6x6 clear-water patch")
	check(ship_count * 4 == ship_cells and ship_cells == map.ships_count(),
		"ship cells consistent (%d origins, %d cells, cached %d)" % [ship_count, ship_cells, map.ships_count()])

	# 2. find_dry_rect matches the brute-force optimum on a small map
	map.generate_map({"seed": 9, "size": 48, "water_pct": 40})
	var rect := map.find_dry_rect(12, 10)
	var wet := _rect_wet(map, rect, 12, 10)
	var best_wet := 999999
	for oy in range(2, map.map_size - 11):
		for ox in range(2, map.map_size - 13):
			var w := _rect_wet(map, Vector2i(ox, oy), 12, 10)
			if w < best_wet:
				best_wet = w
	check(wet == best_wet, "find_dry_rect hits the optimum (%d vs best %d)" % [wet, best_wet])

	# 3. carve_to_dry: ships inside are relocated, the rect ends up dry
	map.generate_map()
	var rect3 := map.find_dry_rect(26, 19)
	var before := _rect_wet(map, rect3, 26, 19)
	map.carve_to_dry(rect3, 26, 19)
	var after := 0
	for dy in 19:
		for dx in 26:
			if map._cell(rect3 + Vector2i(dx, dy)).terrain in IsoMap.WATER_TERRAINS:
				after += 1
	check(before > 0, "default demo map needed carving (%d wet cells)" % before)
	check(after == 0, "village rect fully dry after carve (%d wet left)" % after)
	check(map.ships_count() >= 4, "evicted ships re-moored elsewhere (%d hull cells)" % map.ships_count())

	# 4. the demo road grid fits entirely: 42 requests, none refused
	var map2 := IsoMap.new()
	root.add_child(map2)
	map2._ready()
	map2.generate_map()
	var r := map2.find_dry_rect(26, 19)
	map2.carve_to_dry(r, 26, 19)
	var o := r + Vector2i(6, 0)
	var placed := 0
	for x in range(o.x, o.x + 18):
		placed += int(map2.place_road("road_paved", Vector2i(x, o.y + 4)))
	for y in range(o.y + 4, o.y + 12):
		placed += int(map2.place_road("road_paved", Vector2i(o.x + 3, y)))
		placed += int(map2.place_road("road_paved", Vector2i(o.x + 9, y)))
		placed += int(map2.place_road("road_paved", Vector2i(o.x + 15, y)))
	check(placed == 42, "demo road grid complete on carved land (42/42, got %d)" % placed)

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
