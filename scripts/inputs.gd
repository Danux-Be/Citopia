class_name Inputs
extends RefCounted

## Input map management: registers the actions the project.godot file does
## not define yet, persists user rebindings in user://settings.cfg and
## renders human-readable labels for the settings screen.

const BINDABLE := [
	"camera_up", "camera_down", "camera_left", "camera_right",
	"camera_zoom_in", "camera_zoom_out",
	"pause", "speed_up", "speed_down", "clear_tool",
]

const ACTION_LABELS := {
	"camera_up": "Caméra — haut",
	"camera_down": "Caméra — bas",
	"camera_left": "Caméra — gauche",
	"camera_right": "Caméra — droite",
	"camera_zoom_in": "Zoom avant",
	"camera_zoom_out": "Zoom arrière",
	"pause": "Pause / reprendre",
	"speed_up": "Vitesse +",
	"speed_down": "Vitesse -",
	"clear_tool": "Annuler l'outil",
}

const PAD_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "Retour", 5: "Guide", 6: "Start",
	7: "Stick G", 8: "Stick D", 10: "Croix", 11: "D-pad haut",
	12: "D-pad bas", 13: "D-pad gauche", 14: "D-pad droite",
}

## Default bindings for every bindable action.
## "k:<code>" = physical keyboard key, "j:<index>" = pad button,
## "m:<button>" = mouse button.
const DEFAULTS := {
	"camera_up": ["k:87", "k:4194320"],
	"camera_down": ["k:83", "k:4194322"],
	"camera_left": ["k:65", "k:4194319"],
	"camera_right": ["k:68", "k:4194321"],
	"camera_zoom_in": ["m:4"],
	"camera_zoom_out": ["m:5"],
	"pause": ["k:80", "j:6"],          # P, Start
	"speed_up": ["j:11"],              # D-pad up
	"speed_down": ["j:12"],            # D-pad down
	"clear_tool": ["k:4194305"],       # Escape
}


static func ensure_actions() -> void:
	for action in BINDABLE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


## Applies defaults where the user has no stored override, and the stored
## rebindings everywhere else.
static func load_bindings() -> void:
	var cfg := ConfigFile.new()
	var has_file := cfg.load("user://settings.cfg") == OK
	for action in BINDABLE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var stored = cfg.get_value("bindings", action, null) if has_file else null
		if stored is Array and not (stored as Array).is_empty():
			_apply_events(action, stored)
		else:
			_apply_defaults(action)


## Restores the shipped defaults for every bindable action.
static func reset_bindings() -> void:
	for action in BINDABLE:
		_apply_defaults(action)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	if cfg.has_section("bindings"):
		cfg.erase_section("bindings")
	cfg.save("user://settings.cfg")


## Replaces every event of an action with the given one (rebinding UI).
static func rebind(action: String, ev: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)
	save_bindings()


static func save_bindings() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")  # keeps the other sections
	for action in BINDABLE:
		var stored: Array[String] = []
		for ev in InputMap.action_get_events(action):
			stored.append(var_to_str(ev))
		cfg.set_value("bindings", action, stored)
	cfg.save("user://settings.cfg")


static func _apply_events(action: String, stored: Array) -> void:
	InputMap.action_erase_events(action)
	for sv: String in stored:
		var ev = str_to_var(sv)
		if ev is InputEvent:
			InputMap.action_add_event(action, ev)


static func _apply_defaults(action: String) -> void:
	InputMap.action_erase_events(action)
	for code: String in DEFAULTS.get(action, []):
		var ev := make_event(code)
		if ev != null:
			InputMap.action_add_event(action, ev)


static func make_event(code: String) -> InputEvent:
	if code.begins_with("k:"):
		var key := InputEventKey.new()
		key.physical_keycode = int(code.substr(2)) as Key
		return key
	if code.begins_with("j:"):
		var pad := InputEventJoypadButton.new()
		pad.button_index = int(code.substr(2)) as JoyButton
		return pad
	if code.begins_with("m:"):
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(code.substr(2)) as MouseButton
		return mouse
	return null


static func _has_event(action: String, ev: InputEvent) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing.get_class() == ev.get_class():
			if ev is InputEventKey and existing is InputEventKey \
					and existing.physical_keycode == ev.physical_keycode:
				return true
			if ev is InputEventJoypadButton and existing is InputEventJoypadButton \
					and existing.button_index == ev.button_index:
				return true
			if ev is InputEventMouseButton and existing is InputEventMouseButton \
					and existing.button_index == ev.button_index:
				return true
	return false


## Human-readable label of the events bound to an action.
static func binding_label(action: String) -> String:
	var parts: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			parts.append(OS.get_keycode_string(
				DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode)))
		elif ev is InputEventJoypadButton:
			parts.append("Manette %s" % PAD_NAMES.get(ev.button_index, str(ev.button_index)))
		elif ev is InputEventMouseButton:
			parts.append("Molette" if ev.button_index in [4, 5] else "Souris %d" % ev.button_index)
	return " / ".join(parts) if not parts.is_empty() else "-"
