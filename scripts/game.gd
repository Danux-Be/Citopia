extends Node2D

## Root game node: wires mouse input to the map and the build bar.

const FAIL_SOUND := "res://assets/audio/sound effects/game/fail_placement.ogg"

@onready var iso_map: IsoMap = $IsoMap
@onready var build_bar: CanvasLayer = $BuildBar

var _fail_stream: AudioStream


func _ready() -> void:
	_fail_stream = load(FAIL_SOUND)
	build_bar.setup(iso_map.catalog)
	build_bar.tool_selected.connect(_on_tool_selected)

	# `godot scenes/main.tscn ++ --demo` places a small village (screenshots).
	if "--demo" in OS.get_cmdline_user_args():
		_place_demo_village()


func _on_tool_selected(tool_id: String) -> void:
	iso_map.selected_tool = tool_id
	iso_map.set_hovered(iso_map.hovered)  # refresh validity coloring


func _process(_delta: float) -> void:
	if get_viewport().gui_get_hovered_control() != null:
		iso_map.set_hovered(Vector2i(-1, -1))
		return
	iso_map.set_hovered(iso_map.screen_to_iso(iso_map.get_local_mouse_position()))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_hovered_control() != null:
			return
		var cell := iso_map.screen_to_iso(iso_map.get_local_mouse_position())

		if iso_map.selected_tool == IsoMap.DOZER:
			iso_map.demolish(cell)
		elif not iso_map.selected_tool.is_empty():
			if not iso_map.place(iso_map.selected_tool, cell):
				$FailSound.stream = _fail_stream
				$FailSound.play()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		build_bar.clear_selection()


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
