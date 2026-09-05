extends CanvasLayer

## Map editor overlay shown at startup: seed, map size, terrain sliders with
## live regeneration on the map behind, and the "Found City" action.

signal found_city

const PANEL_BG := Color(0.075, 0.10, 0.145, 0.96)
const PANEL_BORDER := Color(0.24, 0.30, 0.38)
const ACCENT_GREEN := Color(0.35, 0.78, 0.47)
const TEXT_MAIN := Color(0.92, 0.94, 0.96)
const TEXT_DIM := Color(0.62, 0.68, 0.74)

var _iso_map: IsoMap
var _camera: Camera2D
var _seed_edit: LineEdit
var _size_option: OptionButton
var _sliders := {}   # key -> HSlider
var _value_labels := {}
var _regen_debounce := 0.0
var _dirty := false


func setup(iso_map: IsoMap, camera: Camera2D) -> void:
	_iso_map = iso_map
	_camera = camera
	_build_ui()
	_apply()  # initial generation with the random seed


func _process(delta: float) -> void:
	if _dirty:
		_regen_debounce -= delta
		if _regen_debounce <= 0.0:
			_dirty = false
			_apply()


func _params() -> Dictionary:
	var seed_value := int(_seed_edit.text.to_int()) if _seed_edit.text.is_valid_int() else 1234
	var sizes := [48, 96, 192]
	var size: int = sizes[_size_option.selected] if _size_option.selected >= 0 else 96
	return {
		"seed": seed_value,
		"size": size,
		"hills_pct": _sliders["hills"].value,
		"water_pct": _sliders["water"].value,
		"trees_pct": _sliders["trees"].value,
	}


func _apply() -> void:
	var params := _params()
	_iso_map.generate_map(params)
	_camera.position = Vector2(0, _iso_map.map_size * IsoMap.TILE_H * 0.5)
	_camera.zoom = Vector2(1.6, 1.6)


# -- UI --------------------------------------------------------------------

func _build_ui() -> void:
	layer = 20

	# left editor panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(14, 14)
	panel.custom_minimum_size = Vector2(240, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(_title("MAP EDITOR"))
	vbox.add_child(HSeparator.new())

	# seed row
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	var seed_lbl := _label("Seed")
	seed_lbl.custom_minimum_size.x = 42
	seed_row.add_child(seed_lbl)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi() % 999999999)
	_seed_edit.custom_minimum_size.x = 120
	_seed_edit.text_changed.connect(func(_t: String) -> void: _schedule_regen())
	seed_row.add_child(_seed_edit)
	var dice := Button.new()
	dice.text = "Rnd"
	dice.pressed.connect(func() -> void:
		_seed_edit.text = str(randi() % 999999999)
		_schedule_regen())
	seed_row.add_child(dice)
	vbox.add_child(seed_row)

	# map size
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	var size_lbl := _label("Size")
	size_lbl.custom_minimum_size.x = 42
	size_row.add_child(size_lbl)
	_size_option = OptionButton.new()
	for s in ["48×48", "96×96", "192×192"]:
		_size_option.add_item(s)
	_size_option.selected = 1
	_size_option.item_selected.connect(func(_i: int) -> void: _schedule_regen())
	size_row.add_child(_size_option)
	vbox.add_child(size_row)

	# terrain sliders (hills disabled: maps are flat for the traffic milestone)
	var hills_row := _slider_row("hills", "Hills", 50.0)
	var hills_slider: HSlider = hills_row.get_child(1)
	hills_slider.editable = false
	hills_slider.tooltip_text = "Flat maps for now — elevation returns after traffic"
	hills_row.modulate = Color(1, 1, 1, 0.45)
	vbox.add_child(hills_row)
	vbox.add_child(_slider_row("water", "Water", 22.0))
	vbox.add_child(_slider_row("trees", "Trees", 50.0))

	add_child(panel)

	# bottom-right: Found City (anchored offsets: robust to window size)
	var found := Button.new()
	found.text = "Found City"
	found.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	found.offset_left = -214
	found.offset_top = -68
	found.offset_right = -24
	found.offset_bottom = -24
	found.custom_minimum_size = Vector2(190, 44)
	var found_sb := StyleBoxFlat.new()
	found_sb.bg_color = Color(0.16, 0.42, 0.24)
	found_sb.set_corner_radius_all(8)
	found.add_theme_stylebox_override("normal", found_sb)
	found.add_theme_color_override("font_color", TEXT_MAIN)
	found.pressed.connect(func() -> void: found_city.emit())
	add_child(found)


func _title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 13)
	return lbl


func _label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", TEXT_MAIN)
	return lbl


func _slider_row(key: String, label: String, initial: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := _label(label)
	lbl.custom_minimum_size.x = 42
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = initial
	slider.custom_minimum_size = Vector2(110, 16)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(_v: float) -> void: _schedule_regen())
	row.add_child(slider)
	_sliders[key] = slider
	var value := Label.new()
	value.text = "%d%%" % int(initial)
	value.custom_minimum_size.x = 40
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", TEXT_DIM)
	slider.value_changed.connect(func(v: float) -> void: value.text = "%d%%" % int(v))
	row.add_child(value)
	return row


func _schedule_regen() -> void:
	_dirty = true
	_regen_debounce = 0.25


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb
