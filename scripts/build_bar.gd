extends CanvasLayer

## Bottom build bar: a row of tool buttons (tile stamps + bulldozer).

signal tool_selected(tool_id: String)

## Picked from the legacy tile database to showcase each category.
const TOOLS: Array[String] = [
	"road_paved",
	"res_1x1_AnconaHome",
	"res_2x2_AnnasHouse",
	"com_1x1_CafeApartment_kt",
	"ind_1x1_GarageGonneVillela",
	"bush_green_dense",
	"ND_1x1_Pond",
]
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
const ICON_SIZE := 44.0

var _catalog: TileCatalog
var _group := ButtonGroup.new()
var _bar: HBoxContainer
var _current := ""


func setup(catalog: TileCatalog) -> void:
	_catalog = catalog
	_build_ui()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.self_modulate = Color(0.08, 0.09, 0.11, 0.92)

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 6)
	panel.add_child(_bar)

	for tile_id: String in TOOLS:
		var tile := _catalog.get_tile(tile_id)
		if tile.is_empty():
			push_warning("Toolbar tile not found: %s" % tile_id)
			continue
		_bar.add_child(_make_tool_button(tile_id, _make_icon(tile), tile.get("title", tile_id)))

	_bar.add_child(VSeparator.new())
	for zone_id: String in ZONES:
		var zone_tile := _catalog.get_tile(zone_id)
		if zone_tile.is_empty():
			push_warning("Toolbar zone not found: %s" % zone_id)
			continue
		var zone_label: String = zone_tile.get("title", zone_id)
		_bar.add_child(_make_tool_button(
			zone_id, _make_icon(zone_tile),
			"%s — paint it, buildings grow on their own" % zone_label))

	_bar.add_child(VSeparator.new())
	_bar.add_child(_make_tool_button(IsoMap.RAISE, load(RAISE_ICON), "Raise terrain — hold left click to paint"))
	_bar.add_child(_make_tool_button(IsoMap.LOWER, load(LOWER_ICON), "Lower terrain — hold left click to paint"))
	_bar.add_child(_make_tool_button(IsoMap.LEVEL, load(LEVEL_ICON), "Level terrain up to the clicked height"))
	_bar.add_child(_make_tool_button(IsoMap.DOZER, load(DOZER_ICON), "Bulldozer — remove buildings and zones"))
	_bar.add_child(_make_tool_button(IsoMap.DEZONE, load(DEZONE_ICON), "De-zone — remove zoning only"))

	add_child(panel)


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
