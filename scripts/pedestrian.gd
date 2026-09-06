class_name Pedestrian
extends Node2D

## One tiny citizen (a 1x3 px figure sliced from the legacy crowd sheets)
## strolling along the curb line of the road network. Walking is rendered
## procedurally: a 1 px vertical bob at step frequency, plus idle pauses —
## at this scale that reads as a lively sidewalk.

const BOB_INTERVAL := 0.16    # seconds per step half-cycle
const CURB_OFFSET := 0.34     # fraction of a cell right of the heading (curb line)
const PAUSE_CHANCE := 0.06    # chance to stop for a moment at each corner

var iso_map: IsoMap
var figure: Texture2D
var speed := 0.6              # cells per second
var prev_cell := Vector2i()
var cur_cell := Vector2i()
var t := 0.0
var _bob := false
var _bob_timer := 0.0
var _pause_left := 0.0

signal left_network(ped: Pedestrian)


func setup(p_iso_map: IsoMap, p_figure: Texture2D, p_speed: float, start: Vector2i) -> void:
	iso_map = p_iso_map
	figure = p_figure
	speed = p_speed
	prev_cell = start
	cur_cell = start
	t = 1.0  # pick the first step immediately
	_bob_timer = randf_range(0.0, BOB_INTERVAL)
	position = iso_map.iso_to_screen(start.x, start.y)
	_update_z(start)


func _process(delta: float) -> void:
	if iso_map == null:
		return
	if not iso_map.is_road(prev_cell) or not iso_map.is_road(cur_cell):
		left_network.emit(self)  # the sidewalk was bulldozed away
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	if t >= 1.0:
		_step()
	t += speed * delta
	_bob_timer -= delta
	if _bob_timer <= 0.0:
		_bob_timer = BOB_INTERVAL
		_bob = not _bob  # the step: 1 px bounce while on the move
	var dir := cur_cell - prev_cell
	var curb := Vector2(-dir.y, dir.x) * CURB_OFFSET
	var p := Vector2(prev_cell).lerp(Vector2(cur_cell), t) + curb
	position = iso_map.iso_to_screen(p.x, p.y)
	_update_z(prev_cell if t < 0.5 else cur_cell)
	queue_redraw()


## Choose the next block corner: keep going, never double back unless the
## corner is a dead end; occasionally stop and look around.
func _step() -> void:
	var neighbors: Array[Vector2i] = []
	for n in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var c: Vector2i = cur_cell + n
		if c != prev_cell and iso_map.is_road(c):
			neighbors.append(c)
	if neighbors.is_empty():
		neighbors = [prev_cell]  # dead end: turn around
	prev_cell = cur_cell
	cur_cell = neighbors[randi() % neighbors.size()]
	t = 0.0
	if randf() < PAUSE_CHANCE:
		_pause_left = randf_range(0.8, 2.5)


func _update_z(cell: Vector2i) -> void:
	z_index = (cell.x + cell.y) * 2 + 1


func _draw() -> void:
	if figure == null:
		return
	var size := figure.get_size()
	# bottom-centred on the curb point; the bob lifts the figure 1 px
	var bob := -1.0 if _bob and _pause_left <= 0.0 else 0.0
	draw_texture(figure, Vector2(-size.x * 0.5, -size.y + bob))
