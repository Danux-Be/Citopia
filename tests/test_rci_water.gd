extends SceneTree

## Headless checks for dynamic RCI demand and the water network.

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
	for y in range(18, 25):
		if y != 20:
			map.paint_zone(Vector2i(12, y), "zone_residential_medium")
			map.paint_zone(Vector2i(13, y), "zone_commercial_medium")
			map.paint_zone(Vector2i(14, y), "zone_industrial_medium")
	var plant_id := ""
	for id in map.catalog.get_ids_by_category("Power"):
		plant_id = id
		break
	map.place(plant_id, Vector2i(16, 16), false)

	# 1. no water network: zones stay unserved and nothing grows
	check(not map._cell(Vector2i(12, 20)).served_water, "no water before any pipe")
	map.place("reward_1x1_OldWaterTower", Vector2i(18, 19), false)
	for x in range(11, 21):
		map.place_pipe(Vector2i(x, 20))
		map.place_pipe(Vector2i(x, 21))
	check(map._water_adjacent(Vector2i(12, 20)), "zone cells by the pipes get water")
	for tick in 100:
		map.grow_zones(3)
	check(map.get_population() > 0, "the city grows with water (%d pop)" % map.get_population())

	# 2. RCI demands are within range and residential demand is positive early
	var d := map.rci_demand
	check(d.R > 0.0 and d.R <= 1.0, "residential demand positive (%.2f)" % d.R)
	check(d.C >= -1.0 and d.C <= 1.0 and d.I >= -1.0 and d.I <= 1.0,
		"commercial/industrial demands in range (%.2f/%.2f)" % [d.C, d.I])

	# 3. cutting the pipes dries the far end and abandons served buildings
	var cut := Vector2i(15, 20)
	check(map.is_pipe(cut), "pipe to cut exists")
	map.remove_pipe(cut)
	map.remove_pipe(Vector2i(15, 21))
	var dry_zone := 0
	for y in range(23, 25):
		if map._cell(Vector2i(12, y)).served_water == false and map._cell(Vector2i(12, y)).zone != "":
			dry_zone += 1
	check(dry_zone > 0, "cells beyond the cut lose water (%d checked)" % dry_zone)
	var lost := 0
	for y in map.map_size:
		for x in map.map_size:
			var pos := Vector2i(x, y)
			var c := map._cell(pos)
			if c.grown and c.abandoned and c.obj_origin == pos:
				lost += 1
	check(lost > 0, "buildings past the cut are abandoned (%d)" % lost)

	# 4. RCI gates growth: with demand forced negative, nothing grows
	var zone_free := Vector2i(19, 21)
	map._cell(zone_free).obj = ""
	check(map.rci_demand.C <= 1.0, "demand readable")
	var grew := 0
	var before := 0
	for y in map.map_size:
		for x in map.map_size:
			var c := map._cell(Vector2i(x, y))
			if c.grown and c.obj_origin == Vector2i(x, y):
				before += 1
	# starve residential demand: huge workforce vs no jobs
	map._population = 5000
	map.rci_demand.R = -1.0
	map.rci_demand.C = -1.0
	map.rci_demand.I = -1.0
	for tick in 30:
		map.grow_zones(3)
	var after := 0
	for y in map.map_size:
		for x in map.map_size:
			var c := map._cell(Vector2i(x, y))
			if c.grown and c.obj_origin == Vector2i(x, y):
				after += 1
	check(after == before, "negative demand stops growth (%d -> %d)" % [before, after])

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
