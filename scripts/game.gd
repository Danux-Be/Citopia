extends Node2D

## Root game node: wires mouse input to the map and the build bar.
## Terrain tools paint while the left button is held down.

const PAINT_INTERVAL := 0.12  # seconds between two raise/lower/level stamps

@onready var iso_map: IsoMap = $IsoMap
@onready var build_bar: CanvasLayer = $BuildBar

var _fail_stream: AudioStream
var _painting := false
var _paint_timer := 0.0
var _demo_steps: Array = []
var _demo_index := 0
var _demo_accum := 0.0


func _ready() -> void:
	_fail_stream = load("res://assets/audio/sound effects/game/fail_placement.ogg")
	build_bar.setup(iso_map.catalog)
	build_bar.tool_selected.connect(_on_tool_selected)

	var args := OS.get_cmdline_user_args()
	if "--demo" in args:
		_place_demo_village()
	if "--demo-elevation" in args:
		_demo_steps = _build_elevation_steps()
		# frame the demo area: ridge + hill around iso (30..61, 34..43)
		var cam: Camera2D = $GameCamera
		cam.position = Vector2(120, 690)
		cam.zoom = Vector2(2.2, 2.2)


func _on_tool_selected(tool_id: String) -> void:
	iso_map.selected_tool = tool_id
	iso_map.set_hovered(iso_map.hovered)  # refresh validity coloring


func _process(delta: float) -> void:
	_step_elevation_demo(delta)
	if get_viewport().gui_get_hovered_control() != null:
		iso_map.set_hovered(Vector2i(-1, -1))
		_painting = false
		return
	iso_map.set_hovered(iso_map.screen_to_iso(iso_map.get_local_mouse_position()))

	# Drag-painting for terrain tools.
	if _painting and iso_map.selected_tool in [IsoMap.RAISE, IsoMap.LOWER, IsoMap.LEVEL, IsoMap.DOZER]:
		_paint_timer -= delta
		if _paint_timer <= 0.0:
			_paint_timer = PAINT_INTERVAL
			_apply_tool(iso_map.hovered, false)


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
	if not iso_map.in_bounds(cell):
		return
	match iso_map.selected_tool:
		IsoMap.RAISE:
			iso_map.change_height(cell, 1)
		IsoMap.LOWER:
			iso_map.change_height(cell, -1)
		IsoMap.LEVEL:
			iso_map.level_terrain(cell)
		IsoMap.DOZER:
			iso_map.demolish(cell)
		"":
			pass
		_:
			if not iso_map.place(iso_map.selected_tool, cell) and play_fail:
				$FailSound.stream = _fail_stream
				$FailSound.play()


func _place_demo_village() -> void:
	var placements: Array = [
		["road_paved", Vector2i(40, 50)], ["road_paved", Vector2i(41, 50)],
		["road_paved", Vector2i(42, 50)], ["road_paved", Vector2i(43, 50)],
		["road_paved", Vector2i(44, 50)], ["road_paved", Vector2i(45, 50)],
		["road_paved", Vector2i(46, 50)], ["road_paved", Vector2i(47, 50)],
		["road_paved", Vector2i(48, 50)], ["road_paved", Vector2i(49, 50)],
		["road_paved", Vector2i(50, 50)], ["road_paved", Vector2i(51, 50)],
		["res_1x1_AnconaHome", Vector2i(41, 48)],
		["res_2x2_AnnasHouse", Vector2i(44, 47)],
		["com_1x1_CafeApartment_kt", Vector2i(48, 48)],
		["ind_1x1_GarageGonneVillela", Vector2i(51, 48)],
		["bush_green_dense", Vector2i(43, 49)],
		["bush_green_dense", Vector2i(47, 52)],
		["bush_green_dense", Vector2i(50, 46)],
	]
	for placement: Array in placements:
		_place_near(placement[0], placement[1])


## Places a tile at `center`, or on the closest valid cell nearby.
func _place_near(tile_id: String, center: Vector2i) -> void:
	for radius in range(0, 6):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if iso_map.place(tile_id, center + Vector2i(dx, dy)):
					return
	push_warning("Demo placement failed everywhere near %s: %s" % [center, tile_id])


## Animated showcase: two mountains and a plateau grow step by step.
func _build_elevation_steps() -> Array:
	var steps: Array = []
	# Mountain ridge (grows into terraces through the cascading rule).
	for i in 14:
		steps.append([IsoMap.RAISE, Vector2i(30 + i, 38 + i % 3)])
		steps.append([IsoMap.RAISE, Vector2i(31 + i, 40 + i % 2)])
	# A round hill.
	for ring in 3:
		for a in 12:
			var angle := TAU * a / 12.0
			var p := Vector2i(52, 40) + Vector2i(int(round(cos(angle) * (3 - ring))), int(round(sin(angle) * (3 - ring))))
			steps.append([IsoMap.RAISE, p])
	# A plateau for the village.
	for dx in 5:
		for dy in 4:
			steps.append([IsoMap.LEVEL, Vector2i(43 + dx, 49 + dy)])
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
