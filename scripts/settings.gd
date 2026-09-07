class_name Settings
extends RefCounted

## Persisted user settings (user://settings.cfg).

const PATH := "user://settings.cfg"


static func load_settings() -> Dictionary:
	var defaults := {
		"music": 1.0, "music_muted": false,
		"sfx": 1.0, "sfx_muted": false,
		"fullscreen": false, "vsync": true,
	}
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return defaults
	for key in defaults:
		defaults[key] = cfg.get_value("general", key, defaults[key])
	return defaults


static func save_settings(d: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # preserve other sections (input bindings)
	for key in ["music", "music_muted", "sfx", "sfx_muted", "fullscreen", "vsync"]:
		cfg.set_value("general", key, d.get(key))
	cfg.save(PATH)


## Applies audio, video and vsync settings to the engine.
static func apply(d: Dictionary) -> void:
	var music := float(d.get("music", 1.0))
	var sfx := float(d.get("sfx", 1.0))
	var music_db := linear_to_db(clampf(music, 0.0, 1.0)) if music > 0.0 else -60.0
	var sfx_db := linear_to_db(clampf(sfx, 0.0, 1.0)) if sfx > 0.0 else -60.0
	if bool(d.get("music_muted", false)):
		music_db = -60.0
	if bool(d.get("sfx_muted", false)):
		sfx_db = -60.0
	if AudioServer.get_bus_index("Music") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_db)
	if AudioServer.get_bus_index("SFX") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), sfx_db)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if bool(d.get("fullscreen", false))
		else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(d.get("vsync", true))
		else DisplayServer.VSYNC_DISABLED)
