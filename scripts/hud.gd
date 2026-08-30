extends CanvasLayer

## Top HUD bar in the style of the reference UI: dark navy panels, date +
## speed controls, city name, population, funds and a mini RCI indicator.
## Also owns the minimap (top-left) with the camera viewport rectangle.

const PANEL_BG := Color(0.075, 0.10, 0.145, 0.96)
const PANEL_BORDER := Color(0.24, 0.30, 0.38)
const ACCENT_GREEN := Color(0.35, 0.78, 0.47)
const TEXT_MAIN := Color(0.92, 0.94, 0.96)
const TEXT_DIM := Color(0.62, 0.68, 0.74)
const START_DATE := "01/01/2002"
const DAY_SECONDS := 0.4  # real seconds per in-game day at speed 1

var speed := 1  # 0 = paused, 1..3
var day_count := 0.0

var _date_label: Label
var _pop_label: Label
var _funds_label: Label
var _rci_bars: Dictionary = {}
var _minimap: TextureRect
var _minimap_frame: Control
var _minimap_image: Image
var _minimap_timer := 0.0
var _iso_map: IsoMap
var _camera: Camera2D


func _ready() -> void:
	layer = 10
	_iso_map = null  # wired by game.gd via setup()
	_build_top_bar()
	_build_minimap()
	set_speed(1)


func setup(iso_map: IsoMap, camera: Camera2D) -> void:
	_iso_map = iso_map
	_camera = camera
	iso_map.stats_changed.connect(_refresh_stats)
	_refresh_stats()


func _process(delta: float) -> void:
	if speed > 0:
		day_count += delta * speed / DAY_SECONDS
		_date_label.text = _date_string(day_count)
	_minimap_timer -= delta
	if _minimap_timer <= 0.0:
		_minimap_timer = 0.5
		_redraw_minimap()
		_draw_minimap_frame()


func set_speed(s: int) -> void:
	speed = s
	get_tree().paused = false  # growth ticks are manual; pause handled in game.gd
	for i in range(1, 4):
		var b: Button = _top_bar.get_node("Speed%d" % i)
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT_GREEN if i == speed else Color(0.13, 0.17, 0.23)
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color(0.06, 0.09, 0.07) if i == speed else TEXT_DIM)


func is_paused() -> bool:
	return speed == 0


func _date_string(days: float) -> String:
	var total_days := int(days)
	var y := 2002 + total_days / 360
	var rem := total_days % 360
	var m := rem / 30 + 1
	var d := rem % 30 + 1
	return "%02d/%02d/%04d" % [d, m, y]


# -- Top bar ---------------------------------------------------------------

var _top_bar: HBoxContainer


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build_top_bar() -> void:
	var bar_panel := PanelContainer.new()
	bar_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_panel.add_theme_stylebox_override("panel", _panel_style())

	_top_bar = HBoxContainer.new()
	_top_bar.add_theme_constant_override("separation", 14)
	bar_panel.add_child(_top_bar)

	# speed controls
	_top_bar.add_child(_make_speed_button("⏸", 0))
	_top_bar.add_child(_make_speed_button("▶", 1, "Speed1"))
	_top_bar.add_child(_make_speed_button("▶▶", 2, "Speed2"))
	_top_bar.add_child(_make_speed_button("▶▶▶", 3, "Speed3"))

	# date
	_date_label = Label.new()
	_date_label.text = START_DATE
	_date_label.add_theme_color_override("font_color", TEXT_MAIN)
	_top_bar.add_child(_date_label)

	_top_bar.add_child(_vsep())

	# city name
	var city := Label.new()
	city.text = "Citopia"
	city.add_theme_color_override("font_color", ACCENT_GREEN)
	_top_bar.add_child(city)

	_top_bar.add_child(_vsep())

	# population
	_pop_label = Label.new()
	_pop_label.text = "Pop 0"
	_pop_label.add_theme_color_override("font_color", TEXT_MAIN)
	_top_bar.add_child(_pop_label)

	# funds
	_funds_label = Label.new()
	_funds_label.text = "C$20,000"
	_funds_label.add_theme_color_override("font_color", ACCENT_GREEN)
	_top_bar.add_child(_funds_label)

	_top_bar.add_child(_vsep())

	# mini RCI indicator: three tiny vertical bars
	_top_bar.add_child(_make_rci_bars())

	add_child(bar_panel)


func _make_speed_button(label: String, s: int, node_name := "") -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	if node_name != "":
		b.name = node_name
	b.pressed.connect(func() -> void: set_speed(s))
	return b


func _vsep() -> VSeparator:
	return VSeparator.new()


func _make_rci_bars() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var colors := {"R": Color(0.35, 0.75, 0.4), "C": Color(0.35, 0.55, 0.9), "I": Color(0.9, 0.75, 0.3)}
	for key: String in ["R", "C", "I"]:
		var slot := VBoxContainer.new()
		slot.alignment = BoxContainer.ALIGNMENT_END
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(8, 4)
		bar.color = colors[key]
		bar.name = key
		slot.add_child(bar)
		var lbl := Label.new()
		lbl.text = key
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", TEXT_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(lbl)
		_rci_bars[key] = bar
		box.add_child(slot)
	return box


func _refresh_stats() -> void:
	if _iso_map == null:
		return
	_pop_label.text = "Pop %d" % _iso_map.get_population()
	_funds_label.text = "C$%s" % _iso_map.get_funds()
	# RCI bars: share of zoned cells per type (cap for display)
	var counts := {"R": 0, "C": 0, "I": 0}
	var prefixes := {"R": "zone_residential", "C": "zone_commercial", "I": "zone_industrial"}
	for y in _iso_map.map_size:
		for x in _iso_map.map_size:
			var z: String = _iso_map.zone_at(Vector2i(x, y))
			for key: String in prefixes:
				if z.begins_with(prefixes[key]):
					counts[key] += 1
	for key: String in _rci_bars:
		var bar: ColorRect = _rci_bars[key]
		bar.custom_minimum_size.y = 4.0 + minf(28.0, counts[key] * 0.4)


# -- Minimap ---------------------------------------------------------------

const MINIMAP_SIZE := 148.0

func _build_minimap() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(10, 10)
	panel.add_theme_stylebox_override("panel", _panel_style())

	_minimap = TextureRect.new()
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap.texture = ImageTexture.create_from_image(Image.create(96, 96, false, Image.FORMAT_RGB8))
	_minimap.gui_input.connect(_on_minimap_input)
	panel.add_child(_minimap)

	# camera viewport rectangle, drawn over the minimap
	_minimap_frame = Control.new()
	_minimap_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_frame.draw.connect(_draw_minimap_frame)
	_minimap.add_child(_minimap_frame)

	add_child(panel)


func _redraw_minimap() -> void:
	if _iso_map == null:
		return
	var size := _iso_map.map_size
	var img := _minimap_image
	if img == null or img.get_width() != size:
		img = Image.create(size, size, false, Image.FORMAT_RGB8)
		_minimap_image = img
	for y in size:
		for x in size:
			img.set_pixel(x, y, _cell_color(Vector2i(x, y)))
	_minimap.texture.update(img)


func _cell_color(cell_pos: Vector2i) -> Color:
	var terrain: String = _iso_map.terrain_at(cell_pos)
	if terrain == "water":
		return Color(0.16, 0.32, 0.55)
	if _iso_map.obj_at(cell_pos) != "":
		return Color(0.85, 0.3, 0.25)
	var zone: String = _iso_map.zone_at(cell_pos)
	if zone.begins_with("zone_residential"):
		return Color(0.3, 0.75, 0.35)
	if zone.begins_with("zone_commercial"):
		return Color(0.3, 0.45, 0.85)
	if zone.begins_with("zone_industrial"):
		return Color(0.85, 0.7, 0.25)
	if terrain == "terrain_sand_beach":
		return Color(0.82, 0.78, 0.6)
	var h: int = _iso_map.height_at(cell_pos)
	var g := 0.25 + 0.09 * h
	return Color(g * 0.85, g, g * 0.8)


func _draw_minimap_frame() -> void:
	if _iso_map == null or _camera == null:
		return
	var size := _iso_map.map_size
	var scale_f := MINIMAP_SIZE / size
	# camera center in world -> iso cell (float)
	var world := _camera.position
	var fx := world.x / (IsoMap.TILE_W * 0.5)
	var fy := world.y / (IsoMap.TILE_H * 0.5)
	var cx := (fy + fx) * 0.5
	var cy := (fy - fx) * 0.5
	# visible half-extent in tiles
	var half_w := 640.0 / _camera.zoom.x / (IsoMap.TILE_W * 0.5) * 0.5
	var half_h := 360.0 / _camera.zoom.y / (IsoMap.TILE_H * 0.5) * 0.5
	var rw := (absf(half_w) + absf(half_h)) * scale_f
	var rh := (absf(half_w) + absf(half_h)) * scale_f * 0.5
	var rect := Rect2(cx * scale_f - rw * 0.5, cy * scale_f - rh * 0.5, rw, rh)
	_minimap_frame.draw_rect(rect, Color(1, 1, 1, 0.9), false, 1.5)


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _iso_map == null or _camera == null:
			return
		var local: Vector2 = _minimap.get_local_mouse_position()
		var scale_f := _iso_map.map_size / MINIMAP_SIZE
		var cell := local * scale_f
		# iso cell (float) -> world position
		var world := Vector2((cell.x - cell.y) * IsoMap.TILE_W * 0.5, (cell.x + cell.y) * IsoMap.TILE_H * 0.5)
		_camera.position = world
