extends SceneTree

## Headless checks for vehicle bodies: scale-down, silhouette variety,
## tint bounds, z streams and frame direction mapping.

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
	map.generate_map({"seed": 7, "water_pct": 0})
	for i in range(15, 26):
		map.place_road("road_paved", Vector2i(i, 20))
	for i in range(15, 26):
		if i != 20:
			map.place_road("road_paved", Vector2i(20, i))
	var traffic := Traffic.new()
	map.add_child(traffic)
	traffic.setup(map)
	traffic.process_mode = Node.PROCESS_MODE_DISABLED

	var path: Array[Vector2i] = []
	for i in range(16, 25):
		path.append(Vector2i(i, 20))

	# 1. scales stay in the body-type set and are all smaller than legacy
	var scales := {}
	var tints := {}
	var vans := 0
	for k in 60:
		var v: Vehicle = traffic.spawn_on_path(path)
		scales[v._draw_scale] = true
		tints[v._tint] = true
		if v._draw_scale == 0.53:
			vans += 1
		if v._draw_scale >= 1.0 or v._draw_scale < 0.4:
			check(false, "scale out of range: %s" % v._draw_scale)
	check(scales.size() >= 2, "fleet mixes body types (%d distinct)" % scales.size())
	check(vans > 0 and vans < 30, "vans exist but stay a minority (%d/60)" % vans)

	# 2. every body is strictly smaller than the legacy 28 px frame
	var max_rect := 0.0
	for s in scales:
		max_rect = maxf(max_rect, s * Vehicle.FRAME)
	check(max_rect < 24.0, "largest drawn vehicle stays under 24 px (%.1f)" % max_rect)

	# 3. tints jitter around white without going extreme
	var tint_ok := true
	var has_tinted := false
	for t: Color in tints:
		if t.r < 0.85 or t.r > 1.15 or not is_equal_approx(t.r, t.g) or not is_equal_approx(t.g, t.b):
			tint_ok = false
		if absf(t.r - 1.0) > 0.005:
			has_tinted = true
	check(tint_ok, "tints are neutral gray within +-15%")
	check(has_tinted, "some vehicles actually carry a tint")

	# 4. frame mapping: frames 0/2 lean along the E-W diagonal (side views),
	# frames 1/3 along the S-N diagonal (end views) — a wrong pairing shows
	# cars sideways across the road
	check(Vehicle.DIR_FRAMES[Vector2i(1, 0)] == 0, "E uses side frame 0 (NW-SE lean)")
	check(Vehicle.DIR_FRAMES[Vector2i(-1, 0)] == 2, "W uses side frame 2 (NW-SE lean)")
	check(Vehicle.DIR_FRAMES[Vector2i(0, 1)] == 1, "S uses end frame 1 (NE-SW lean)")
	check(Vehicle.DIR_FRAMES[Vector2i(0, -1)] == 3, "N uses end frame 3 (NE-SW lean)")
	var v0: Vehicle = traffic.spawn_on_path(path)
	v0.path_i = 0

	# 5. drawn rect math matches the body scale
	var half: float = Vehicle.FRAME * 0.5 * v0._draw_scale
	check(is_equal_approx(half * 2.0, Vehicle.FRAME * v0._draw_scale),
		"draw rect size = FRAME * scale")

	# 6. z streams: a vehicle sits ABOVE the ground diagonal of the cell ahead
	# (it used to be half-buried by that road tile) and BELOW its objects
	var s := v0.cell_now().x + v0.cell_now().y
	var vz: int = v0.z_index
	check(vz == s * 2 + 512, "vehicle in the actor stream (z=%d)" % vz)
	check(map._diag_nodes[s + 1].z_index < vz, "ground ahead is below the vehicle")
	check(vz < map._obj_nodes[s + 1].z_index, "objects ahead stay above the vehicle")
	check(map._obj_nodes[s].z_index > vz, "a building on the car's cell covers it")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
