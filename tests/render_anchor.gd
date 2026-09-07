extends SceneTree

## Diagnostic tool (needs a display): renders one car and one pedestrian on
## a road cell and saves before/after captures of the same view.
## Run: godot --path . --script tests/render_anchor.gd
## Then diff /tmp/anchor_ref.png vs /tmp/anchor_actors.png to check that the
## actors sit inside the road diamond (y 401..416 for cell (30,20)).

func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	await process_frame
	await process_frame
	map.generate_flat(48, 0)
	for x in range(28, 33):
		map.place_road("road_paved", Vector2i(x, 20))
	var peds := Pedestrians.new()
	map.add_child(peds)
	peds.setup(map)
	peds.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/anchor_ref.png")
	# car parked straddling cell (30,20) heading E
	var path: Array[Vector2i] = [Vector2i(29, 20), Vector2i(30, 20)]
	var v := Vehicle.new()
	root.add_child(v)
	v.setup(map, load("res://assets/images/vehicles/vehicles.png"), 0, path)
	v._draw_scale = 0.53
	v._tint = Color(1, 1, 1)
	v.cruise = 1.0
	v.speed = 1.0
	v._process(1.0 / 60.0 * 8)
	v.speed = 0.0
	v._process(1.0 / 60.0)
	# pedestrian mid-segment on the same road
	var ped := peds.spawn_at(Vector2i(32, 20))
	ped.prev_cell = Vector2i(31, 20)
	ped.cur_cell = Vector2i(32, 20)
	ped.t = 0.5
	ped._process(1.0 / 60.0)
	print("CAR_AT ", v.position, "  PED_AT ", ped.position)
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/anchor_actors.png")
	print("ANCHOR_SAVED")
	quit(0)
