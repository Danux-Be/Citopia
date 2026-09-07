extends SceneTree

## Headless checks for the input map: defaults, rebinding, persistence,
## reset. Self-cleaning: restores shipped defaults at the end.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		failures += 1
		print("FAIL ", msg)


func _pause_events() -> Array:
	return InputMap.action_get_events("pause")


func _has_start(events: Array) -> bool:
	for ev in events:
		if ev is InputEventJoypadButton and ev.button_index == 6:
			return true
	return false


func _initialize() -> void:
	Inputs.reset_bindings()      # clean slate, whatever previous runs left
	Inputs.ensure_actions()
	Inputs.load_bindings()

	# 1. defaults restored
	var evs := _pause_events()
	check(evs.size() == 2, "pause defaults: key + Start (%d events)" % evs.size())
	check(_has_start(evs), "pause bound to Start")
	var zoom := InputMap.action_get_events("camera_zoom_in")
	var wheel := false
	for ev in zoom:
		if ev is InputEventMouseButton and ev.button_index == 4:
			wheel = true
	check(wheel, "zoom in keeps the mouse wheel")

	# 2. rebinding replaces the events
	Inputs.rebind("pause", Inputs.make_event("k:75"))  # K
	var evs2 := _pause_events()
	check(evs2.size() == 1 and evs2[0] is InputEventKey and evs2[0].physical_keycode == 75,
		"rebind replaces events with K")
	check(Inputs.binding_label("pause") == "K", "label shows K (%s)" % Inputs.binding_label("pause"))

	# 3. persistence across save/load
	Inputs.save_bindings()
	Inputs.load_bindings()
	var evs3 := _pause_events()
	check(evs3.size() == 1 and evs3[0] is InputEventKey and evs3[0].physical_keycode == 75,
		"rebinding persisted after load")

	# 4. reset restores shipped defaults and clears persistence
	Inputs.reset_bindings()
	Inputs.load_bindings()
	check(_pause_events().size() == 2 and _has_start(_pause_events()),
		"reset restores defaults (key + Start)")
	check(Inputs.binding_label("camera_zoom_in").find("Molette") >= 0,
		"zoom label mentions the wheel (%s)" % Inputs.binding_label("camera_zoom_in"))

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
