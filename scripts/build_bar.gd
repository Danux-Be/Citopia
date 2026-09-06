extends CanvasLayer

## Bottom build UI, in the reference style: a persistent cluster (zones,
## terrain tools, bulldozer) plus category tabs opening a scrollable grid
## that exposes the whole legacy tile database.

signal tool_selected(tool_id: String)

## Zones grow buildings on their own.
const ZONES: Array[String] = [
	"zone_residential_medium",
	"zone_commercial_medium",
	"zone_industrial_medium",
]
const DOZER_ICON := "res://assets/images/ui/buttons/demolish.png"
const DEZONE_ICON := "res://assets/images/ui/buttons/dezone.png"
const RAISE_ICON := "res://assets/images/ui/buttons/raiseTerrain.png"
const LOWER_ICON := "res://assets/images/ui/buttons/lowerTerrain.png"
const LEVEL_ICON := "res://assets/images/ui/buttons/levelTerrain.png"
const ICON_SIZE := 40.0

## Tab title -> legacy database categories. Residential/Commercial/Industrial
## buildings are NOT placeable: they grow on their own from the zoning tools.
const CATEGORY_TABS := {
	"Transportation": ["Roads", "Trains"],
	"Power": ["Power"],
	"Utilities": ["Waterworks"],
	"Services": ["Emergency", "School"],
	"Recreation": ["Recreation"],
	"Nature": ["Flora", "Nature"],
	"Landscaping": ["Decoration", "Ground Decoration"],
	"Landmarks": ["Reward"],
	"Prison": ["Prison"],
}

const PANEL_BG := Color(0.075, 0.10, 0.145, 0.96)
const PANEL_BORDER := Color(0.24, 0.30, 0.38)

var _catalog: TileCatalog
var _group := ButtonGroup.new()
var _bar: HBoxContainer
var _current := ""
var _tabs: TabBar
var _grid_popup: PanelContainer
var _grid: GridContainer


func setup(catalog: TileCatalog) -> void:
	_catalog = catalog
	_build_ui()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# category tabs (open the browsable grid)
	_tabs = TabBar.new()
	_tabs.add_tab("Zones")
	for tab_title: String in CATEGORY_TABS:
		_tabs.add_tab(tab_title)
	_tabs.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tabs)

	# persistent cluster: zones, terrain tools, bulldozer
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 5)
	vbox.add_child(_bar)

	for zone_id: String in ZONES:
		var zone_tile := _catalog.get_tile(zone_id)
		if zone_tile.is_empty():
			push_warning("Toolbar zone not found: %s" % zone_id)
			continue
		var zone_label: String = zone_tile.get("title", zone_id)
		_bar.add_child(_make_tool_button(
			zone_id, _make_icon(zone_tile),
			"%s — grows only on served cells: road within 2 tiles + power coverage" % zone_label))

	_bar.add_child(_vsep())
	_bar.add_child(_make_tool_button(IsoMap.RAISE, load(RAISE_ICON), "Raise terrain — hold left click to paint"))
	_bar.add_child(_make_tool_button(IsoMap.LOWER, load(LOWER_ICON), "Lower terrain — hold left click to paint"))
	_bar.add_child(_make_tool_button(IsoMap.LEVEL, load(LEVEL_ICON), "Level terrain up to the clicked height"))
	_bar.add_child(_make_tool_button(IsoMap.DOZER, load(DOZER_ICON), "Bulldozer — remove buildings and zones"))
	_bar.add_child(_make_tool_button(IsoMap.DEZONE, load(DEZONE_ICON), "De-zone — remove zoning only"))

	# browsable tile grid (opens above the bar)
	_grid_popup = PanelContainer.new()
	_grid_popup.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_grid_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grid_popup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_grid_popup.offset_bottom = -104  # sit above the persistent bar
	_grid_popup.offset_top = -104 - 262
	_grid_popup.add_theme_stylebox_override("panel", _panel_style())
	_grid_popup.visible = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 12
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)
	_grid_popup.add_child(scroll)

	add_child(panel)
	add_child(_grid_popup)


func _on_tab_changed(tab: int) -> void:
	if tab == 0:  # "Zones" tab: the persistent cluster already shows them
		_grid_popup.visible = false
		return
	_fill_grid(CATEGORY_TABS[_tabs.get_tab_title(tab)])
	_grid_popup.visible = true


func _fill_grid(categories: Array) -> void:
	for child in _grid.get_children():
		child.queue_free()
	for category: String in categories:
		for tile_id in _catalog.get_ids_by_category(category):
			var tile := _catalog.get_tile(tile_id)
			var icon := _make_icon(tile)
			if icon == null:
				continue
			_grid.add_child(_make_tool_button(tile_id, icon, "%s (%s)" % [tile.get("title", tile_id), category]))


func _make_icon(tile: Dictionary) -> Texture2D:
	var texture := _catalog.get_texture(tile)
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = _catalog.get_region(tile, texture.get_height(), 0)
	return atlas


func _make_tool_button(tool_id: String, icon: Texture2D, tooltip: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = icon
	button.toggle_mode = true
	button.button_group = _group
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	button.tooltip_text = tooltip
	button.toggled.connect(_on_tool_toggled.bind(tool_id))
	return button


func _on_tool_toggled(on: bool, tool_id: String) -> void:
	if on:
		_current = tool_id
		tool_selected.emit(tool_id)
	elif _current == tool_id:
		_current = ""
		tool_selected.emit("")


func clear_selection() -> void:
	var pressed := _group.get_pressed_button()
	if pressed != null:
		pressed.set_pressed_no_signal(false)
	_current = ""
	tool_selected.emit("")


func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, ICON_SIZE)
	return sep
