extends SceneTree

## Diagnostic (needs a display): renders 4 cars heading E/S/W/N on bare
## grass and saves one shot each. The sprite's principal axis must match
## the travel diagonal (mod 180 deg): E/W lean +26.6 deg, S/N lean -26.6 deg.

func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	await process_frame
	await process_frame
	map.generate_flat(48, 0)
	var dirs := {"E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0), "N": Vector2i(0, -1)}
	for tag: String in dirs:
		var v := Vehicle.new()
		root.add_child(v)
		var path: Array[Vector2i] = [Vector2i(30, 20), Vector2i(30, 20) + dirs[tag]]
		v.setup(map, load("res://assets/images/vehicles/vehicles.png"), 0, path)
		v._draw_scale = 0.61
		v._tint = Color(1, 1, 1)
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("/tmp/veh_dir_%s.png" % tag)
		v.queue_free()
		await process_frame
	var img2 := root.get_viewport().get_texture().get_image()
	img2.save_png("/tmp/veh_flat_ref.png")
	print("DIRS_SAVED")
	quit(0)
