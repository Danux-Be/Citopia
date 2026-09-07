class_name Vehicle
extends Node2D

## One vehicle driving along the road network. The map hands it a path of
## cells; it follows the segments at cell granularity with a right-hand lane
## offset, picking the sprite frame that matches its heading. Its z_index is
## recomputed each frame so it slots between the map's diagonal layers.

const FRAME_W := 32
const FRAME_H := 28
const LANE_PX := 3.0        # lane centre, screen px right of the road centre line
                            # (the art's asphalt band is only ~6 px wide across;
                            # 6 px put the wheels on the sidewalk)
const BASE_SPEED := 2.2     # cells per second, before the per-vehicle cruise roll
const ACCEL := 4.0          # cells/s^2 towards the frame's speed cap
const BRAKE := 10.0         # braking is firmer than engine response

## Body types rolled per trip: silhouette variety around the size the user
## picked, plus a subtle brightness tint layered over the 6 paint colors.
const BODY_TYPES := [
	{"scale": 0.44, "weight": 4, "jitter": 0.10},   # compact
	{"scale": 0.48, "weight": 4, "jitter": 0.08},   # sedan
	{"scale": 0.53, "weight": 2, "jitter": 0.06},   # van
]

## world direction -> orientation index inside the color block (8 per color,
## drawn by tools/gen_vehicles_pixel.py): 0/1 horizontal right/left, 2/3
## vertical up/down, 4-7 the road obliques down-right (E), down-left (S),
## up-left (W), up-right (N).
const DIR_FRAMES := {
	Vector2i(1, 0): 4, Vector2i(0, 1): 5, Vector2i(-1, 0): 6, Vector2i(0, -1): 7,
}

var iso_map: IsoMap
var cruise := BASE_SPEED    # personal top speed; rolled once per trip
var speed := BASE_SPEED     # current speed, cells per second
var speed_factor := 1.0     # 0..1 cap recomputed by Traffic every frame
var wait_time := 0.0        # seconds fully stopped (unlocks the yield timeout)
var ignore_yield := false   # latched: timeout expired, commit to crossing
var color_index := 0
var path: Array[Vector2i] = []
var path_i := 0
var t := 0.0

signal trip_finished(vehicle: Vehicle)

var _texture: Texture2D
var _draw_scale := 0.48
var _tint := Color.WHITE
var _heading := Vector2(0.894, 0.447)   # screen-space travel direction
var _braking := false                    # brake lights lit


func setup(p_iso_map: IsoMap, p_texture: Texture2D, p_color: int, p_path: Array[Vector2i]) -> void:
	iso_map = p_iso_map
	_texture = p_texture
	color_index = p_color
	path = p_path
	path_i = 0
	t = 0.0
	cruise = BASE_SPEED * randf_range(0.85, 1.15)  # everyone drives a bit differently
	speed = cruise
	speed_factor = 1.0
	wait_time = 0.0
	ignore_yield = false
	var body := _roll_body()
	_draw_scale = body.scale
	var jitter: float = body.jitter
	var brightness := randf_range(1.0 - jitter, 1.0 + jitter)
	_tint = Color(brightness, brightness, brightness)
	var start := path[0]
	position = iso_map.iso_to_screen(start.x, start.y)
	_update_z(start)


## Weighted pick of a body silhouette for this trip.
func _roll_body() -> Dictionary:
	var total := 0
	for body in BODY_TYPES:
		total += int(body.weight)
	var roll := randi() % total
	for body in BODY_TYPES:
		roll -= int(body.weight)
		if roll < 0:
			return body
	return BODY_TYPES[0]


func _process(delta: float) -> void:
	if iso_map == null or path.size() < 2 or path_i >= path.size() - 1:
		return
	var a := path[path_i]
	var b := path[path_i + 1]
	# skip out from under a road that got bulldozed mid-drive
	if not iso_map.is_road(a) or not iso_map.is_road(b):
		trip_finished.emit(self)
		return
	var target := cruise * clampf(speed_factor, 0.0, 1.0)
	speed = move_toward(speed, target, (BRAKE if target < speed else ACCEL) * delta)
	# brake lights: decelerating, or held at a stop by traffic
	_braking = (target < speed - 0.02) or (speed_factor < 0.2 and speed < 0.3)
	# count standing still: Traffic uses this to break priority deadlocks
	if speed < 0.15 and speed_factor < 0.2:
		wait_time += delta
	else:
		wait_time = 0.0
	t += speed * delta
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
	# lane offset in SCREEN space: the isometric projection does not keep
	# world perpendiculars perpendicular, and a world-space offset made cars
	# drift off the lane line depending on their heading. The +8 px ground
	# anchor moves the contact point from the cell's top corner (where
	# iso_to_screen of integer cells lands) to the diamond's centre, so both
	# lanes sit inside the road instead of riding its top edge.
	var heading := (iso_map.iso_to_screen(b.x, b.y) - iso_map.iso_to_screen(a.x, a.y)).normalized()
	_heading = heading
	var p := Vector2(a).lerp(Vector2(b), t)
	position = iso_map.iso_to_screen(p.x, p.y) + Vector2(0, IsoMap.TILE_H * 0.5) \
			+ Vector2(-heading.y, heading.x) * LANE_PX
	_update_z(a if t < 0.5 else b)
	queue_redraw()


func seg_from() -> Vector2i:
	return path[path_i]


func seg_to() -> Vector2i:
	return path[path_i + 1]


func dir() -> Vector2i:
	return path[path_i + 1] - path[path_i]


## The cell the sprite currently straddles the centre of.
func cell_now() -> Vector2i:
	return path[path_i] if t < 0.5 else path[path_i + 1]


func _update_z(cell: Vector2i) -> void:
	# actor stream: above every ground diagonal (the road ahead included —
	# cars were half-buried by it), below the object stream (iso_map 1024)
	z_index = (cell.x + cell.y) * 2 + 512


func _draw() -> void:
	if _texture == null or path.size() < 2 or path_i >= path.size() - 1:
		return
	var dir: Vector2i = path[path_i + 1] - path[path_i]
	var frame_idx: int = color_index * 8 + int(DIR_FRAMES.get(dir, 4))
	var region := Rect2(frame_idx * FRAME_W, 0, FRAME_W, FRAME_H)
	var half_w := FRAME_W * 0.5 * _draw_scale
	var half_h := FRAME_H * 0.5 * _draw_scale
	# the new art is centred in its frame: the anchor is the car's ground point
	draw_texture_rect_region(_texture, Rect2(-half_w, -half_h, FRAME_W * _draw_scale, FRAME_H * _draw_scale), region, _tint)
	_draw_lights()


## Daytime running lights at the nose, taillights at the rear — dim red
## while cruising, bright with a glow while braking.
func _draw_lights() -> void:
	var front := _heading
	var perp := Vector2(-front.y, front.x)
	var nose := front * (7.0 * _draw_scale)
	var tail := -nose
	var side := perp * (2.2 * _draw_scale)
	# headlights: two warm dots at the nose
	var drl := Color(1.0, 0.96, 0.72, 0.85)
	draw_circle(nose + side, 1.1 * _draw_scale, drl)
	draw_circle(nose - side, 1.1 * _draw_scale, drl)
	# taillights
	var brake_c := Color(1.0, 0.12, 0.08, 0.95 if _braking else 0.4)
	if _braking:
		draw_circle(tail + side, 3.2 * _draw_scale, Color(1.0, 0.1, 0.05, 0.22))
		draw_circle(tail - side, 3.2 * _draw_scale, Color(1.0, 0.1, 0.05, 0.22))
	draw_circle(tail + side, (1.4 if _braking else 1.0) * _draw_scale, brake_c)
	draw_circle(tail - side, (1.4 if _braking else 1.0) * _draw_scale, brake_c)
