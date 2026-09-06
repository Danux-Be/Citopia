extends Node2D

## Root game node: wires mouse input to the map and the build bar.
## Terrain tools paint while the left button is held down.

const PAINT_INTERVAL := 0.12  # seconds between two raise/lower/level stamps
const GROWTH_INTERVAL := 1.2  # seconds between two zone growth ticks
const GROWTH_PER_TICK := 3    # buildings spawned per tick

@onready var iso_map: IsoMap = $IsoMap
@onready var build_bar: CanvasLayer = $BuildBar
@onready var hud: CanvasLayer = $HUD
@onready var map_editor: CanvasLayer = $MapEditor

var menu_mode := true  # map editor open, city not founded yet

var _fail_stream: AudioStream
var _painting := false
var _paint_timer := 0.0
var _growth_timer := 0.0
var _demo_steps: Array = []
var _demo_index := 0
var _demo_accum := 0.0
var _shot_frames := -1  # >0: save a screenshot after that many frames
var _shot2_frames := -1 # --shot2: second capture 30 frames later (animation proof)
var _shot2 := false
var _weather: Weather
var _pedestrians: Pedestrians


func _ready() -> void:
	_fail_stream = load("res://assets/audio/sound effects/game/fail_placement.ogg")
	build_bar.setup(iso_map.catalog)
	build_bar.tool_selected.connect(_on_tool_selected)
	hud.setup(iso_map, $GameCamera)
	map_editor.setup(iso_map, $GameCamera)
	map_editor.found_city.connect(found_city)
	$Traffic.setup(iso_map)
	_pedestrians = Pedestrians.new()
	add_child(_pedestrians)
	_pedestrians.setup(iso_map)
	build_bar.visible = false

	var args := OS.get_cmdline_user_args()
	if "--shot" in args:
		# let the active demo finish before capturing
		_shot_frames = 1100 if "--demo-elevation" in args else 300
		_shot2 = "--shot2" in args
	var weather := Weather.new()
	add_child(weather)
	_weather = weather
	if "--rain" in args:
		weather.force_rain()
	if "--demo" in args or "--demo-elevation" in args:
		found_city()  # demos skip the map editor
	if "--demo" in args:
		_place_demo_village()
		var cam: Camera2D = $GameCamera
		cam.position = Vector2(-112, 792)  # village center (46,53)
		cam.zoom = Vector2(2.4, 2.4)
	if "--demo-elevation" in args:
		# synthetic flat ground: the terraformed shapes read unambiguously
		iso_map.generate_flat(48, 2)
		_demo_steps = _build_elevation_steps()
		var cam: Camera2D = $GameCamera
		cam.position = Vector2(0, 384)
		cam.zoom = Vector2(2.0, 2.0)


## Captures the viewport and prints the smoke-test telemetry line.
func _save_shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	var traffic := $Traffic as Traffic
	print("DEBUG roads=%d vehicles=%d target=%d stopped=%d peds=%d pop=%d funds=%d unserved=%d abandoned=%d shores=%d flora=%d murky=%d weather=%s" % [
		traffic.road_count(), traffic.get_child_count(), traffic.target_fleet(),
		traffic.stopped_count(), _pedestrians.ped_count(),
		iso_map.get_population(), iso_map.get_funds(),
		iso_map.unserved_zone_count(), iso_map.abandoned_count(),
		iso_map.shore_count(), iso_map.water_flora_count(), iso_map.murky_count(),
		"rain" if _weather.is_raining() else "sunny"])


## Leaves the map editor and starts the actual game on the previewed map.
func found_city() -> void:
	menu_mode = false
	map_editor.visible = false
	build_bar.visible = true
	if "--demo" in OS.get_cmdline_user_args():
		build_bar._on_tab_changed(1)  # showcase the browsable tile grid

func _on_tool_selected(tool_id: String) -> void:
	iso_map.selected_tool = tool_id
	iso_map.set_hovered(iso_map.hovered)  # refresh validity coloring


func _process(delta: float) -> void:
	_step_elevation_demo(delta)
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			_save_shot("/tmp/citopia_shot.png")
			print("SHOT_SAVED")
			if _shot2:
				# 30 frames (0.5 s) later every water cell has advanced by
				# exactly one ripple frame: diffing the two shots proves the
				# animation runs (a full 3-frame cycle would look identical)
				_shot2_frames = 30
			else:
				get_tree().quit()
	if _shot2_frames > 0:
		_shot2_frames -= 1
		if _shot2_frames == 0:
			_save_shot("/tmp/citopia_shot2.png")
			print("SHOT2_SAVED")
			get_tree().quit()
	var over_ui := get_viewport().gui_get_hovered_control() != null
	if over_ui:
		iso_map.set_hovered(Vector2i(-1, -1))
		_painting = false
	else:
		iso_map.set_hovered(iso_map.screen_to_iso(iso_map.get_local_mouse_position()))

		# Drag-painting for terrain tools, zones and roads.
		var tool := iso_map.selected_tool
		var paintable := tool in [IsoMap.RAISE, IsoMap.LOWER, IsoMap.LEVEL, IsoMap.DOZER, IsoMap.DEZONE] \
				or iso_map.is_zone_tool(tool) or iso_map.is_road_tool(tool)
		if _painting and paintable:
			_paint_timer -= delta
			if _paint_timer <= 0.0:
				_paint_timer = PAINT_INTERVAL
				_apply_tool(iso_map.hovered, false)

	# Zone growth and traffic: buildings appear on zoned cells by themselves
	# and vehicles drive around — both stop while paused or in the editor.
	# Abandoned buildings collapse on the same clock.
	var paused: bool = menu_mode or hud.is_paused()
	$Traffic.process_mode = ProcessMode.PROCESS_MODE_DISABLED if paused else ProcessMode.PROCESS_MODE_INHERIT
	_pedestrians.process_mode = ProcessMode.PROCESS_MODE_DISABLED if paused else ProcessMode.PROCESS_MODE_INHERIT
	if paused:
		return
	iso_map.tick_abandonment(delta)
	_growth_timer -= delta
	if _growth_timer <= 0.0:
		_growth_timer = GROWTH_INTERVAL
		iso_map.grow_zones(GROWTH_PER_TICK)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_viewport().gui_get_hovered_control() != null:
				return
			_painting = true
			_paint_timer = 0.0
			_apply_tool(iso_map.screen_to_iso(iso_map.get_local_mouse_position()), true)
		else:
			_painting = false
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		build_bar.clear_selection()


func _apply_tool(cell: Vector2i, play_fail: bool) -> void:
	if menu_mode or not iso_map.in_bounds(cell):
		return
	match iso_map.selected_tool:
		IsoMap.RAISE:
			iso_map.change_height(cell, 1)
		IsoMap.LOWER:
			iso_map.change_height(cell, -1)
		IsoMap.LEVEL:
			iso_map.level_terrain(cell)
		IsoMap.DOZER:
			# remove the building first, then the zone underneath
			if not iso_map.demolish(cell):
				iso_map.clear_zone(cell)
		IsoMap.DEZONE:
			iso_map.clear_zone(cell)
		"":
			pass
		_:
			if iso_map.is_zone_tool(iso_map.selected_tool):
				iso_map.paint_zone(cell, iso_map.selected_tool)
			elif iso_map.is_road_tool(iso_map.selected_tool):
				if not iso_map.place_road(iso_map.selected_tool, cell) and play_fail:
					$FailSound.stream = _fail_stream
					$FailSound.play()
			elif not iso_map.place(iso_map.selected_tool, cell) and play_fail:
				$FailSound.stream = _fail_stream
				$FailSound.play()


func _place_demo_village() -> void:
	# a small road network: main street, two side streets down to the zones
	for x in range(38, 56):
		iso_map.place_road("road_paved", Vector2i(x, 50))
	for y in range(50, 58):
		iso_map.place_road("road_paved", Vector2i(41, y))
		iso_map.place_road("road_paved", Vector2i(47, y))
		iso_map.place_road("road_paved", Vector2i(53, y))
	# coal plant west of town: its coverage powers the whole village
	_place_near("pow_5x5_Kohlekraftwerk_Durnrohr_FN", Vector2i(33, 46))
	var placements: Array = [
		["res_1x1_AnconaHome", Vector2i(41, 48)],
		["res_2x2_AnnasHouse", Vector2i(44, 47)],
		["com_1x1_CafeApartment_kt", Vector2i(48, 48)],
		["ind_1x1_GarageGonneVillela", Vector2i(51, 48)],
		["bush_green_dense", Vector2i(43, 49)],
		["bush_green_dense", Vector2i(50, 46)],
	]
	for placement: Array in placements:
		_place_near(placement[0], placement[1])
	# Zone patches: level the ground first so buildings can grow, then paint.
	for x in range(38, 44):
		for y in range(52, 63):
			iso_map.level_terrain(Vector2i(x, y))
	for x in range(38, 44):
		for y in range(52, 56):
			iso_map.paint_zone(Vector2i(x, y), "zone_residential_medium")
	for x in range(45, 49):
		for y in range(52, 55):
			iso_map.paint_zone(Vector2i(x, y), "zone_commercial_medium")
	for x in range(50, 54):
		for y in range(52, 55):
			iso_map.paint_zone(Vector2i(x, y), "zone_industrial_medium")
	# a far patch, off the road grid: it stays dark and never grows
	for x in range(38, 42):
		for y in range(60, 63):
			iso_map.paint_zone(Vector2i(x, y), "zone_residential_medium")


## Places a tile at `center`, or on the closest valid cell nearby.
func _place_near(tile_id: String, center: Vector2i) -> void:
	for radius in range(0, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if iso_map.place(tile_id, center + Vector2i(dx, dy)):
					return
	push_warning("Demo placement failed everywhere near %s: %s" % [center, tile_id])


## Animated showcase: a village plateau, then a straight ridge grows along
## its edge — continuous ramps on the flank, pyramids at the ridge ends.
func _build_elevation_steps() -> Array:
	var steps: Array = []
	# A plateau for the village.
	for dx in 6:
		for dy in 4:
			steps.append([IsoMap.LEVEL, Vector2i(18 + dx, 26 + dy)])
	# A straight ridge rising along the plateau's north edge: the plateau
	# tiles facing it draw continuous ramps; the ridge ends get pyramids.
	for height_step in 1:
		for x in range(20, 28):
			steps.append([IsoMap.RAISE, Vector2i(x, 25)])
	# A small round hill next to the plateau.
	for ring in 4:
		for a in 12:
			var angle := TAU * a / 12.0
			var p := Vector2i(33, 21) + Vector2i(int(round(cos(angle) * (3 - ring))), int(round(sin(angle) * (3 - ring))))
			steps.append([IsoMap.RAISE, p])
	return steps


func _step_elevation_demo(delta: float) -> void:
	if _demo_index >= _demo_steps.size():
		return
	_demo_accum += delta
	while _demo_accum >= 0.12 and _demo_index < _demo_steps.size():
		_demo_accum -= 0.12
		var step: Array = _demo_steps[_demo_index]
		_demo_index += 1
		if step[0] == IsoMap.RAISE:
			iso_map.change_height(step[1], 1)
		else:
			iso_map.level_terrain(step[1])
