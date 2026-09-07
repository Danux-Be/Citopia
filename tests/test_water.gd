extends SceneTree

## Headless checks for the water milestone: animation, shoreline autotile,
## swamp water and water flora.

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

	# --- 1. both water sheets ship 3 ripple frames at columns 13..15 -------
	map.generate_map({"seed": 7, "size": 96, "water_pct": 30})
	for terrain in ["water", "liquid_MurkyWater"]:
		var tile: Dictionary = map.catalog.get_tile(terrain)
		var tex: Texture2D = map.catalog.get_texture(tile)
		check(int(tile.get("tiles", {}).get("count", 0)) == 3,
			"%s has 3 animation frames" % terrain)
		var r0: Rect2 = map.catalog.get_region(tile, tex.get_height(), 0)
		var r2: Rect2 = map.catalog.get_region(tile, tex.get_height(), 2)
		check(r0.position.x == 13 * 32 and r2.position.x == 15 * 32,
			"%s frames map to sheet columns 13..15" % terrain)

	# --- 2. swamp pockets exist and count as water -------------------------
	check(map.murky_count() > 20, "swamp pockets generated (%d cells)" % map.murky_count())
	var murky_sample: Vector2i
	for c in map._water_cells:
		if map._cell(c).terrain == "liquid_MurkyWater":
			murky_sample = c
			break
	check(map.is_water_cell(murky_sample), "is_water_cell true for murky water")
	check(not map.can_place_road("road_paved", murky_sample), "roads refused on murky water")
	check(not map.paint_zone(murky_sample, "zone_residential_medium"), "zones refused on murky water")

	# --- 3. shoreline corner mask, handcrafted patterns --------------------
	map.generate_flat(5, 0)
	map._cell(Vector2i(2, 2)).terrain = "water"
	check(map._shore_mask(Vector2i(2, 1)) == 9, "grid-S neighbor -> SE+SW corners (9)")
	check(map._shore_mask(Vector2i(2, 3)) == 6, "grid-N neighbor -> NE+NW corners (6)")
	check(map._shore_mask(Vector2i(3, 2)) == 12, "grid-W neighbor -> NW+SW corners (12)")
	check(map._shore_mask(Vector2i(1, 2)) == 3, "grid-E neighbor -> SE+NE corners (3)")
	check(map._shore_mask(Vector2i(1, 1)) == 1, "SE diagonal -> corner 1")
	check(map._shore_mask(Vector2i(1, 3)) == 2, "NE diagonal -> corner 2")
	check(map._shore_mask(Vector2i(3, 3)) == 4, "NW diagonal -> corner 4")
	check(map._shore_mask(Vector2i(3, 1)) == 8, "SW diagonal -> corner 8")
	check(map._shore_mask(Vector2i(0, 0)) == 0, "far cell sees no water")

	# --- 4. shore frame tables ----------------------------------------------
	var grass: Dictionary = map.catalog.get_tile("terrain_grass")
	var beach: Dictionary = map.catalog.get_tile("terrain_sand_beach")
	check(map.catalog.has_shoreline(grass) and map.catalog.has_shoreline(beach),
		"grass and beach have shoreline sheets")
	check(not map.catalog.has_shoreline(map.catalog.get_tile("water")),
		"water itself has no shoreline sheet")
	var g3: Rect2 = map.catalog.get_shore_region(grass, 3)
	check(g3.position.x == 3 * 32 and g3.size == Vector2(32, 15),
		"grass sheets: frame index = mask (mask 3 -> column 3)")
	var b3: Rect2 = map.catalog.get_shore_region(beach, 3)
	var b12: Rect2 = map.catalog.get_shore_region(beach, 12)
	var b1: Rect2 = map.catalog.get_shore_region(beach, 1)
	var b15: Rect2 = map.catalog.get_shore_region(beach, 15)
	check(b3.position.x == 1 * 32, "beach: edge mask 3 -> scrambled frame 1")
	check(b12.position.x == 0 * 32, "beach: edge mask 12 -> scrambled frame 0")
	check(b1.position.x == 4 * 32, "beach: corner mask 1 -> scrambled frame 4")
	check(b15.position.x == 14 * 32, "beach: mask 15 -> scrambled frame 14")

	# --- 5. water flora placement rules --------------------------------------
	map.generate_map({"seed": 7, "size": 96, "water_pct": 30})
	var cattail := 0; var rice := 0; var lilypads := 0
	var placement_ok := true
	for y in map.map_size:
		for x in map.map_size:
			var c := map._cell(Vector2i(x, y))
			if c.obj == "":
				continue
			if c.obj.begins_with("waterFlora_cattail"):
				cattail += 1
				if not map._has_land_edge(Vector2i(x, y)):
					placement_ok = false
			elif c.obj.begins_with("waterFlora_rice"):
				rice += 1
				if c.terrain != "liquid_MurkyWater" or not map._has_land_edge(Vector2i(x, y)):
					placement_ok = false
			elif c.obj.begins_with("waterFlora_lilypads"):
				lilypads += 1
				if map._has_land_edge(Vector2i(x, y)) or c.terrain not in IsoMap.WATER_TERRAINS:
					placement_ok = false
	check(cattail > 20 and rice > 5 and lilypads > 10,
		"flora spread (cattail=%d rice=%d lilypads=%d)" % [cattail, rice, lilypads])
	check(placement_ok, "flora respects its habitat (shore / swamp / open water)")
	check(map.water_flora_count() == cattail + rice + lilypads, "flora telemetry matches")
	check(map.shore_count() > 500, "shore tiles counted (%d)" % map.shore_count())

	# --- 6. animation still ticks, per terrain -------------------------------
	map._water_time = 0.0
	map._water_tick = -1
	map._process(0.1)
	map._process(0.2)
	check(map._water_tick == 0, "no frame change before 0.5 s")
	map._process(0.3)
	check(map._water_tick == 1, "tick advances at 2 fps")
	var v: int = map.water_variant_at("liquid_MurkyWater", Vector2i(4, 4), 3)
	check(v >= 0 and v <= 2, "murky variant in range at any step")

	# --- 7. flat map stays dry ------------------------------------------------
	map.generate_flat(16, 2)
	check(map._water_cells.is_empty() and map.shore_count() == 0, "flat map has no water or shores")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
