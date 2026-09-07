class_name MainMenu
extends CanvasLayer

## Main menu: New game / Continue / Load / Settings / Quit. Drawn over the
## map editor at startup, or over the city when opened from the in-game
## menu button (then a Resume button leads the list).

signal new_game
signal continue_game
signal load_slot(slot: String)
signal quit_requested
signal resumed
signal settings_applied(music: float, sfx: float, fullscreen: bool)
signal opened
signal closed

const PANEL_BG := Color(0.05, 0.07, 0.11, 0.97)
const PANEL_BORDER := Color(0.24, 0.30, 0.38)
const ACCENT := Color(0.35, 0.78, 0.47)
const TEXT_MAIN := Color(0.92, 0.94, 0.96)

var _root: Control
var _title_box: VBoxContainer
var _menu_view: VBoxContainer
var _load_view: VBoxContainer
var _load_list: VBoxContainer
var _settings_view: VBoxContainer
var _resume_btn: Button
var _music_slider: HSlider
var _sfx_slider: HSlider
var _fullscreen_check: CheckBox
var _resume_mode := false
var _backdrop: TextureRect
var _music_muted: CheckBox
var _sfx_muted: CheckBox
var _vsync_check: CheckBox
var _rebind_rows := {}
var _listening := ""


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# soft backdrop: a downscaled capture of the city (real area-average
	# blur) shown stretched, slightly dimmed
	var dim := TextureRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	dim.modulate = Color(0.72, 0.75, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_backdrop = dim

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "CITOPIA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "the city we build together, in freedom"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", TEXT_MAIN)
	box.add_child(sub)

	# --- main view ---------------------------------------------------------
	_menu_view = VBoxContainer.new()
	_menu_view.add_theme_constant_override("separation", 6)
	box.add_child(_menu_view)

	_resume_btn = _menu_button("Reprendre", func() -> void: resumed.emit())
	_menu_view.add_child(_resume_btn)
	_menu_view.add_child(_menu_button("Nouvelle partie", func() -> void:
		close(); new_game.emit()))
	_menu_view.add_child(_menu_button("Continuer", func() -> void:
		close(); continue_game.emit()))
	_menu_view.add_child(_menu_button("Charger", func() -> void: _show_view("load")))
	_menu_view.add_child(_menu_button("Configuration", func() -> void: _show_view("settings")))
	_menu_view.add_child(_menu_button("Quitter", func() -> void: quit_requested.emit()))

	# --- load view ---------------------------------------------------------
	_load_view = VBoxContainer.new()
	_load_view.visible = false
	_load_view.add_theme_constant_override("separation", 6)
	box.add_child(_load_view)
	_load_view.add_child(_view_title("Charger une partie"))
	_load_list = VBoxContainer.new()
	_load_list.add_theme_constant_override("separation", 4)
	_load_view.add_child(_load_list)
	_load_view.add_child(_menu_button("Retour", func() -> void: _show_view("menu")))

	# --- settings view -----------------------------------------------------
	_settings_view = VBoxContainer.new()
	_settings_view.visible = false
	_settings_view.add_theme_constant_override("separation", 8)
	box.add_child(_settings_view)
	_settings_view.add_child(_view_title("Configuration"))

	var saved := Settings.load_settings()
	_music_slider = _slider_row("Musique", saved.music)
	_settings_view.add_child(_music_slider)
	_music_muted = CheckBox.new()
	_music_muted.text = "Couper la musique"
	_music_muted.button_pressed = bool(saved.get("music_muted", false))
	_settings_view.add_child(_music_muted)
	_sfx_slider = _slider_row("Effets sonores", saved.sfx)
	_settings_view.add_child(_sfx_slider)
	_sfx_muted = CheckBox.new()
	_sfx_muted.text = "Couper les effets sonores"
	_sfx_muted.button_pressed = bool(saved.get("sfx_muted", false))
	_settings_view.add_child(_sfx_muted)

	_fullscreen_check = CheckBox.new()
	_fullscreen_check.text = "Plein écran"
	_fullscreen_check.button_pressed = bool(saved.get("fullscreen", false))
	_settings_view.add_child(_fullscreen_check)
	_vsync_check = CheckBox.new()
	_vsync_check.text = "Synchronisation verticale (V-sync)"
	_vsync_check.button_pressed = bool(saved.get("vsync", true))
	_settings_view.add_child(_vsync_check)

	var binds_title := _view_title("Contrôles — cliquer puis presser une touche")
	binds_title.add_theme_font_size_override("font_size", 12)
	_settings_view.add_child(binds_title)
	var bind_scroll := ScrollContainer.new()
	bind_scroll.custom_minimum_size = Vector2(280, 132)
	var bind_box := VBoxContainer.new()
	bind_box.add_theme_constant_override("separation", 2)
	bind_scroll.add_child(bind_box)
	for action: String in Inputs.BINDABLE:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = Inputs.ACTION_LABELS[action]
		lbl.custom_minimum_size.x = 150
		lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(lbl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 22)
		btn.add_theme_font_size_override("font_size", 11)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_start_listening.bind(action, btn))
		bind_box.add_child(row)
		_rebind_rows[action] = btn
	_settings_view.add_child(bind_scroll)

	_settings_view.add_child(_menu_button("Appliquer", func() -> void:
		var d := Settings.load_settings()
		d.music = _music_slider.value
		d.music_muted = _music_muted.button_pressed
		d.sfx = _sfx_slider.value
		d.sfx_muted = _sfx_muted.button_pressed
		d.fullscreen = _fullscreen_check.button_pressed
		d.vsync = _vsync_check.button_pressed
		Settings.save_settings(d)
		Inputs.save_bindings()
		settings_applied.emit(d)
		_show_view("menu")))
	_settings_view.add_child(_menu_button("Retour", func() -> void: _show_view("menu")))

	_show_view("menu")


func _menu_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(action)
	return b


func _view_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ACCENT)
	return l


func _slider_row(label: String, value: float) -> HSlider:
	var row := VBoxContainer.new()
	var l := Label.new()
	l.text = "%s  %d%%" % [label, int(value * 100)]
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 14)
	slider.value_changed.connect(func(v: float) -> void:
		l.text = "%s  %d%%" % [label, int(v * 100)])
	row.add_child(slider)
	return slider


func _show_view(view: String) -> void:
	_menu_view.visible = view == "menu"
	_load_view.visible = view == "load"
	_settings_view.visible = view == "settings"
	if view == "load":
		_refresh_load_list()
	if view == "settings":
		_refresh_rebind_labels()


func _refresh_load_list() -> void:
	for child in _load_list.get_children():
		child.queue_free()
	var slots := SaveGame.list_slots()
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "Aucune sauvegarde pour le moment."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		_load_list.add_child(empty)
		return
	for s in slots:
		var label := "Sauvegarde du %s — population %d, jour %d" % [s.saved_at, s.pop, s.day]
		_load_list.add_child(_menu_button(label, func() -> void:
			close()
			load_slot.emit(s.slot)))


## Opens the menu. In resume mode (opened mid-game) a Resume button leads.
## The backdrop is a downscaled capture of the live view: a true area blur
## that stays silky instead of the harsh gaussian shader.
func open(resume_mode: bool) -> void:
	_resume_mode = resume_mode
	_resume_btn.visible = resume_mode
	_show_view("menu")
	_root.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.resize(maxi(1, img.get_width() / 12), maxi(1, img.get_height() / 12), Image.INTERPOLATE_BILINEAR)
	_backdrop.texture = ImageTexture.create_from_image(img)


func close() -> void:
	_root.visible = false
	closed.emit()


func is_open() -> bool:
	return _root != null and _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if _resume_mode and is_open() and event is InputEventKey \
			and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		resumed.emit()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode != KEY_ESCAPE:
			Inputs.rebind(_listening, event)
			Inputs.save_bindings()
		_listening = ""
		_refresh_rebind_labels()
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		Inputs.rebind(_listening, event)
		Inputs.save_bindings()
		_listening = ""
		_refresh_rebind_labels()


func _start_listening(action: String, btn: Button) -> void:
	_listening = action
	for a: String in _rebind_rows:
		_rebind_rows[a].text = Inputs.binding_label(a)
	btn.text = "Appuyez..."


func _refresh_rebind_labels() -> void:
	for a: String in _rebind_rows:
		_rebind_rows[a].text = Inputs.binding_label(a)
