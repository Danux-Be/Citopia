class_name Vehicle
extends Node2D

## One vehicle driving along the road network. The map hands it a path of
## cells; it follows the segments at cell granularity with a right-hand lane
## offset, picking the sprite frame that matches its heading. Its z_index is
## recomputed each frame so it slots between the map's diagonal layers.

const FRAME := 28
const LANE_OFFSET := 0.18   # lane center, as a fraction of a cell to the right
const BASE_SPEED := 2.2     # cells per second

## world direction -> sheet direction index (E, S, W, N)
const DIR_FRAMES := {
	Vector2i(1, 0): 0, Vector2i(0, 1): 1, Vector2i(-1, 0): 2, Vector2i(0, -1): 3,
}

var iso_map: IsoMap
var speed_scale := 1.0
var color_index := 0
var path: Array[Vector2i] = []
var path_i := 0
var t := 0.0

signal trip_finished(vehicle: Vehicle)

var _texture: Texture2D


func setup(p_iso_map: IsoMap, p_texture: Texture2D, p_color: int, p_path: Array[Vector2i]) -> void:
	iso_map = p_iso_map
	_texture = p_texture
	color_index = p_color
	path = p_path
	path_i = 0
	t = 0.0
	speed_scale = randf_range(0.85, 1.15)
	var start := path[0]
	position = iso_map.iso_to_screen(start.x, start.y)
	_update_z(start)


func _process(delta: float) -> void:
	if iso_map == null or path.size() < 2 or path_i >= path.size() - 1:
		return
	var a := path[path_i]
	var b := path[path_i + 1]
	# skip out from under a road that got bulldozed mid-drive
	if not iso_map.is_road(a) or not iso_map.is_road(b):
		trip_finished.emit(self)
		return
	t += BASE_SPEED * speed_scale * delta
	while t >= 1.0 and path_i < path.size() - 2:
		t -= 1.0
		path_i += 1
		a = path[path_i]
		b = path[path_i + 1]
		if not iso_map.is_road(a) or not iso_map.is_road(b):
			trip_finished.emit(self)
			return
	if t >= 1.0 and path_i >= path.size() - 2:
		trip_finished.emit(self)
		return

	var dir := b - a
	var lane := Vector2(-dir.y, dir.x) * LANE_OFFSET  # right-hand side of the heading
	var p := Vector2(a).lerp(Vector2(b), t) + lane
	position = iso_map.iso_to_screen(p.x, p.y)
	_update_z(a if t < 0.5 else b)
	queue_redraw()


func _update_z(cell: Vector2i) -> void:
	z_index = (cell.x + cell.y) * 2 + 1  # between diagonal layers


func _draw() -> void:
	if _texture == null or path.size() < 2 or path_i >= path.size() - 1:
		return
	var dir: Vector2i = path[path_i + 1] - path[path_i]
	var frame_idx: int = color_index * 4 + int(DIR_FRAMES.get(dir, 0))
	var region := Rect2(frame_idx * FRAME, 0, FRAME, FRAME)
	draw_texture_rect_region(_texture, Rect2(-FRAME * 0.5, -FRAME * 0.5, FRAME, FRAME), region)
