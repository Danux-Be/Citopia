class_name Weather
extends CanvasLayer

## Screen-space weather: rain showers with thunderclaps, driven by a small
## sunny/rain state machine. The rain streaks are procedural (a thin alpha
## gradient quad falling with the camera's slant); the sounds are CC0 loops
## from OpenGameArt (see the README credits). Layer 1 draws above the world
## canvas (a layer-0 CanvasLayer renders below it) and over the build bar.

const DRY_RANGE := Vector2(90.0, 260.0)    # seconds of clear sky between showers
const RAIN_RANGE := Vector2(35.0, 110.0)   # shower length
const THUNDER_RANGE := Vector2(12.0, 40.0) # thunderclap spacing during a shower
const TINT_ALPHA := 0.16                   # shower gloom
const FLASH_PEAK := 0.45                   # lightning brightness
const TINT_SPEED := 0.25                   # alpha per second
const AUDIO_FADE_DB := 36.0                # volume slide per second

const RAIN_LOOP := "res://assets/audio/ambient/rain_loop.ogg"
const THUNDER_CLAP := "res://assets/audio/ambient/thunder_clap.ogg"

enum State { SUNNY, RAIN }

var state: State = State.SUNNY
var _state_time := 0.0
var _next_change := 0.0
var _thunder_time := 0.0
var _next_thunder := -1.0
var _tint_target := 0.0
var _audio_target_db := -60.0

var _rain: CPUParticles2D
var _tint: ColorRect
var _flash: ColorRect
var _rain_audio: AudioStreamPlayer
var _thunder_audio: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 1
	# fixed seed: the weather calendar is reproducible (tests, demo shots)
	_rng.seed = 20260906
	_build_visuals()
	_build_audio()
	_enter(State.SUNNY)


func is_raining() -> bool:
	return state == State.RAIN


## Jump straight to a shower (demo flag / test seam).
func force_rain() -> void:
	_enter(State.RAIN)


func force_sunny() -> void:
	_enter(State.SUNNY)


func _process(delta: float) -> void:
	_state_time += delta
	# gloom and rain volume slide toward their targets (no tweens: this
	# stays deterministic under the headless test harness)
	_tint.color.a = move_toward(_tint.color.a, _tint_target, TINT_SPEED * delta)
	_rain_audio.volume_db = move_toward(_rain_audio.volume_db, _audio_target_db, AUDIO_FADE_DB * delta)
	if _rain_audio.volume_db <= -59.0 and _rain_audio.playing:
		_rain_audio.stop()
	if _thunder_audio.volume_db > -60.0:
		_thunder_audio.volume_db = move_toward(_thunder_audio.volume_db, -60.0, AUDIO_FADE_DB * delta)
	_flash.color.a = move_toward(_flash.color.a, 0.0, 2.2 * delta)
	if state == State.RAIN and _next_thunder > 0.0:
		_thunder_time += delta
		if _thunder_time >= _next_thunder:
			_thunder_clap()
	if _state_time >= _next_change:
		_enter(State.SUNNY if state == State.RAIN else State.RAIN)


func _enter(next: State) -> void:
	state = next
	_state_time = 0.0
	match next:
		State.SUNNY:
			_next_change = _rng.randf_range(DRY_RANGE.x, DRY_RANGE.y)
			_rain.emitting = false
			_tint_target = 0.0
			_audio_target_db = -60.0
			_next_thunder = -1.0
		State.RAIN:
			_next_change = _rng.randf_range(RAIN_RANGE.x, RAIN_RANGE.y)
			_rain.emitting = true
			_rain.preprocess = _rain.lifetime  # shower already falling, not ramping up
			_tint_target = TINT_ALPHA
			_audio_target_db = -6.0
			if not _rain_audio.playing:
				_rain_audio.play()
			_schedule_thunder()


func _schedule_thunder() -> void:
	_thunder_time = 0.0
	_next_thunder = _rng.randf_range(THUNDER_RANGE.x, THUNDER_RANGE.y)


func _thunder_clap() -> void:
	_thunder_audio.volume_db = -2.0
	_thunder_audio.play()
	_flash.color.a = FLASH_PEAK
	_schedule_thunder()


func _build_visuals() -> void:
	_tint = ColorRect.new()
	_tint.color = Color(0.45, 0.5, 0.62, 0.0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tint)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_rain = CPUParticles2D.new()
	_rain.texture = _streak_texture()
	_rain.amount = 340
	_rain.lifetime = 1.3
	_rain.preprocess = 1.3
	_rain.emitting = false
	_rain.direction = Vector2(0.22, 1.0).normalized()  # matches the camera slant
	_rain.spread = 3.0
	_rain.gravity = Vector2(0, 620)
	_rain.initial_velocity_min = 640
	_rain.initial_velocity_max = 860
	_rain.scale_amount_min = 0.7
	_rain.scale_amount_max = 1.3
	_rain.color = Color(0.85, 0.9, 1.0, 0.42)
	add_child(_rain)
	var viewport := get_viewport()
	if viewport != null:  # null under the headless test harness
		_fit_rain_to_viewport(viewport.size)
		viewport.size_changed.connect(
			func() -> void: _fit_rain_to_viewport(get_viewport().size))


## Emission band across the top of the screen, just out of view.
func _fit_rain_to_viewport(size: Vector2) -> void:
	_rain.position = Vector2(size.x * 0.5, -40)
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.emission_rect_extents = Vector2(size.x * 0.62, 6)


## A thin vertical streak fading out at both ends.
func _streak_texture() -> ImageTexture:
	var img := Image.create(3, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		var a := 0.25 + 0.75 * sin(PI * y / 13.0)
		for x in 3:
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _build_audio() -> void:
	_rain_audio = AudioStreamPlayer.new()
	var loop: AudioStreamOggVorbis = load(RAIN_LOOP)
	loop.loop = true
	_rain_audio.stream = loop
	_rain_audio.volume_db = -60.0
	add_child(_rain_audio)

	_thunder_audio = AudioStreamPlayer.new()
	_thunder_audio.stream = load(THUNDER_CLAP)
	_thunder_audio.volume_db = -60.0
	add_child(_thunder_audio)
