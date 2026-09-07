extends SceneTree

## Diagnostic (needs a display): renders one cruising car and one braking
## car on a road, to check the light effects (DRL dots vs bright brake
## taillights with glow).

func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	await process_frame
	await process_frame
	map.generate_flat(48, 0)
	for x in range(26, 38):
		map.place_road("road_paved", Vector2i(x, 20))
	# cruising car (color 0 = blue): lights at DRL intensity
	var path: Array[Vector2i] = [Vector2i(29, 20), Vector2i(30, 20)]
	var v := Vehicle.new()
	root.add_child(v)
	v.setup(map, load("res://assets/images/vehicles/vehicles_pixel.png"), 0, path)
	v._draw_scale = 0.53
	v._tint = Color(1, 1, 1)
	v.cruise = 1.0
	v.speed = 1.0
	for i in 8:
		v._process(1.0 / 60.0)
	v.speed = 0.6
	v.speed_factor = 1.0
	v._process(1.0 / 60.0)
	# braking car two cells ahead: decelerating hard
	var path2: Array[Vector2i] = [Vector2i(31, 20), Vector2i(32, 20)]
	var v2 := Vehicle.new()
	root.add_child(v2)
	v2.setup(map, load("res://assets/images/vehicles/vehicles_pixel.png"), 0, path2)
	v2._draw_scale = 0.53
	v2._tint = Color(1, 1, 1)
	v2.cruise = 1.0
	v2.speed = 1.0
	for i in 8:
		v2._process(1.0 / 60.0)
	v2.speed = 0.8
	v2.speed_factor = 0.0
	v2._process(1.0 / 60.0)
	print("CRUISER ", v.position, " braking=", v._braking, " | BRAKER ", v2.position, " braking=", v2._braking)
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/lights_shot.png")
	print("LIGHTS_SAVED")
	quit(0)
