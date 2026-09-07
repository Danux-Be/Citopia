extends SceneTree

## Headless checks for the weather system: state machine, visuals, audio,
## thunder scheduling and transitions.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		failures += 1
		print("FAIL ", msg)


func _initialize() -> void:
	var weather := Weather.new()
	root.add_child(weather)
	weather._ready()  # headless: no tree iteration, _ready never auto-fires
	weather.process_mode = Node.PROCESS_MODE_DISABLED  # manual stepping

	# 1. starts sunny
	check(weather.state == Weather.State.SUNNY and not weather.is_raining(),
		"starts sunny")
	check(not weather._rain.emitting, "no particles while sunny")

	# 2. rain loop is a looping stream
	check(weather._rain_audio.stream is AudioStreamOggVorbis
		and weather._rain_audio.stream.loop, "rain loop set to loop")

	# 3. forcing rain: particles, gloom target, audio armed, thunder armed
	weather.force_rain()
	check(weather.is_raining(), "force_rain switches state")
	check(weather._rain.emitting, "rain particles emit")
	check(weather._tint_target == Weather.TINT_ALPHA, "gloom tint targeted")
	check(weather._rain_audio.stream != null and weather._audio_target_db > -10.0,
		"rain loop stream loaded and volume armed")
	check(weather._next_thunder >= Weather.THUNDER_RANGE.x
		and weather._next_thunder <= Weather.THUNDER_RANGE.y, "thunder armed in range")

	# 4. fades progress with time
	weather._process(1.0)
	check(weather._tint.color.a > 0.1 and weather._tint.color.a < Weather.TINT_ALPHA,
		"tint fades in gradually")
	check(weather._rain_audio.volume_db > -60.0, "rain volume fades in")

	# 5. thunderclap fires when its timer elapses
	weather._thunder_time = weather._next_thunder
	weather._process(0.016)
	check(weather._thunder_audio.stream != null and weather._thunder_audio.volume_db > -9.0,
		"thunder clap volume armed")
	check(weather._flash.color.a > 0.3, "lightning flash lights up")
	check(weather._next_thunder >= Weather.THUNDER_RANGE.x, "thunder rescheduled")
	weather._process(1.0)
	check(weather._flash.color.a < 0.2, "flash decays")

	# 6. shower ends on schedule
	weather._state_time = weather._next_change + 0.1
	weather._process(0.016)
	check(weather.state == Weather.State.SUNNY, "rain returns to sunny on schedule")
	check(not weather._rain.emitting, "particles stop with the shower")

	# 7. dry spell ends with a new shower
	weather._state_time = weather._next_change + 0.1
	weather._process(0.016)
	check(weather.state == Weather.State.RAIN, "sunny turns to rain on schedule")
	check(weather._audio_target_db > -10.0, "loop re-arms with the next shower")

	# 8. rain fades out after the shower
	weather.force_sunny()
	var db := weather._rain_audio.volume_db
	weather._process(2.0)
	check(weather._rain_audio.volume_db < db, "rain volume fades out after rain")
	check(weather._audio_target_db < -59.0, "loop target silent after fading")

	# 9. layering: above the world canvas (layer-0 CanvasLayers render below
	# the world, measured on a live demo shot), under the HUD
	check(weather.layer == 1, "weather sits above the world, under the HUD")

	print("TEST_RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
