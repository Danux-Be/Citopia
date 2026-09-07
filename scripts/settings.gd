class_name Settings
extends RefCounted

## Persisted user settings (user://settings.cfg).

const PATH := "user://settings.cfg"


static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {"music": 1.0, "sfx": 1.0, "fullscreen": false}
	return {
		"music": float(cfg.get_value("audio", "music", 1.0)),
		"sfx": float(cfg.get_value("audio", "sfx", 1.0)),
		"fullscreen": bool(cfg.get_value("video", "fullscreen", false)),
	}


static func save_settings(music: float, sfx: float, fullscreen: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)


static func apply(music: float, sfx: float, fullscreen: bool) -> void:
	var music_db := linear_to_db(clampf(music, 0.0, 1.0)) if music > 0.0 else -60.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_db)
	var sfx_db := linear_to_db(clampf(sfx, 0.0, 1.0)) if sfx > 0.0 else -60.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), sfx_db)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
