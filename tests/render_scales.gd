extends SceneTree

## Diagnostic (needs a display): renders the same legacy car at four draw
## scales on a road, to pick the readability/size trade-off visually.

func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	await process_frame
	await process_frame
	map.generate_flat(48, 0)
	for x in range(24, 40):
		map.place_road("road_paved", Vector2i(x, 20))
	var scales := [0.46, 0.53, 0.61, 0.80, 1.00]
	var col := 0
	for s: float in scales:
		var path: Array[Vector2i] = [Vector2i(25 + col, 20), Vector2i(26 + col, 20)]
		var v := Vehicle.new()
		root.add_child(v)
		v.setup(map, load("res://assets/images/vehicles/vehicles.png"), 0, path)
		v._draw_scale = s
		v._tint = Color(1, 1, 1)
		v.cruise = 1.0
		v.speed = 1.0
		for i in int(8 / (s + 0.2)):
			v._process(1.0 / 60.0)
		v.speed = 0.0
		col += 1
	print("SCALES_SAVED")
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/vehicle_scales.png")
	quit(0)
