extends SceneTree

## Diagnostic (needs a display): renders a square lake with its sand ring
## on flat grass, for shoreline quality checks.

func _initialize() -> void:
	var map := IsoMap.new()
	root.add_child(map)
	await process_frame
	await process_frame
	map.generate_flat(40, 0)
	for y in range(14, 22):
		for x in range(16, 24):
			var c := map._cell(Vector2i(x, y))
			c.terrain = "water"
			c.terrain_variant = map.catalog.pick_variant(map.catalog.get_tile(c.terrain))
	# the sand ring, same rule as the generation pass
	for y in range(12, 24):
		for x in range(14, 26):
			var c := map._cell(Vector2i(x, y))
			if map.is_water_cell(Vector2i(x, y)) or c.terrain == "terrain_sand_beach":
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if map.is_water_cell(Vector2i(x + dx, y + dy)):
						c.terrain = "terrain_sand_beach"
						c.terrain_variant = map.catalog.pick_variant(map.catalog.get_tile(c.terrain))
					if c.terrain == "terrain_sand_beach":
						break
				if c.terrain == "terrain_sand_beach":
					break
	map._rebuild_diagonals()
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.position = map.iso_to_screen(20, 18)
	cam.zoom = Vector2(2.0, 2.0)
	cam.make_current()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/shore_render.png")
	print("SHORE_SAVED")
	quit(0)
