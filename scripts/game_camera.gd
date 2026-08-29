class_name GameCamera
extends Camera2D

## Pan (WASD / arrows / middle-or-right drag) and wheel zoom towards cursor.

const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.15
const PAN_SPEED := 900.0

var _dragging := false


func _ready() -> void:
	zoom = Vector2(1.0, 1.0)
	# center on the middle of the default 96x96 map
	position = Vector2(0, 96 * IsoMap.TILE_H * 0.5)
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at_cursor(ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at_cursor(1.0 / ZOOM_STEP, event.position)
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom


func _process(delta: float) -> void:
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	position += direction * PAN_SPEED * delta / zoom.x


func _zoom_at_cursor(factor: float, screen_anchor: Vector2) -> void:
	var new_zoom := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom.x):
		return
	var world_before := get_global_mouse_position()
	zoom = Vector2(new_zoom, new_zoom)
	# Keep the point under the cursor pinned while zooming.
	var world_after := get_global_mouse_position()
	position += world_before - world_after
