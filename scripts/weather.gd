class_name Weather
extends CanvasLayer

## Screen-space gloom + lightning, and WORLD-space rain: three particle
## layers with depth (far drops are slower, smaller, fainter) follow the
## camera so the rain falls ON the map, plus ground splashes. The sounds are
## CC0 loops from OpenGameArt (see the README credits). Layer 1 draws above
## the world canvas (a layer-0 CanvasLayer renders below it) and over the
## build bar.

const DRY_RANGE := Vector2(90.0, 260.0)    # seconds of clear sky between showers
const RAIN_RANGE := Vector2(35.0, 110.0)   # shower length
const STORM_RANGE := Vector2(25.0, 60.0)   # thunderstorm length (rarer, meaner)
const STORM_CHANCE := 0.18                 # share of showers that turn into storms
const THUNDER_RANGE := Vector2(12.0, 40.0) # thunderclap spacing during a shower
const STORM_THUNDER_RANGE := Vector2(3.0, 9.0)
const STRIKE_CHANCE := 0.5                 # a clap may carry a city strike
const TINT_ALPHA := 0.34                   # shower gloom
const STORM_TINT_ALPHA := 0.48             # thunderstorm gloom
const FLASH_PEAK := 0.45                   # lightning brightness
const TINT_SPEED := 0.25                   # alpha per second
const AUDIO_FADE_DB := 36.0                # volume slide per second
const RAIN_AMOUNT := 340.0                 # drops across the three layers
const STORM_AMOUNT := 720.0

const RAIN_LOOP := "res://assets/audio/ambient/rain_loop.ogg"
const THUNDER_CLAP := "res://assets/audio/ambient/thunder_clap.ogg"

enum State { SUNNY, RAIN, STORM }

signal lightning_struck

var state: State = State.SUNNY

var _state_time := 0.0
var _next_change := 0.0
var _thunder_time := 0.0
var _next_thunder := -1.0
var _tint_target := 0.0
var _audio_target_db := -60.0

var _tint: ColorRect
var _flash: ColorRect
var _rain_audio: AudioStreamPlayer
var _thunder_audio: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

# world-space rain: depth layers + ground splashes, camera-following
var _camera: Camera2D
var _rain_world: Node2D
var _rain_layers: Array[CPUParticles2D] = []
var _splash: CPUParticles2D
var _layer_speed := [0.62, 0.85, 1.15]     # velocity multipliers far -> near
var _layer_share := [0.42, 0.35, 0.23]     # amount shares far -> near


func _ready() -> void:
	layer = 1
	_rng.seed = 20260906
	_build_overlays()
	_build_world_rain()
	_build_audio()
	_enter(State.SUNNY)


func is_raining() -> bool:
	return state != State.SUNNY


func is_storm() -> bool:
	return state == State.STORM


## Jump straight to a shower (demo flag / test seam).
func force_rain() -> void:
	_enter(State.RAIN)


func force_sunny() -> void:
	_enter(State.SUNNY)


## The world-space rain follows this camera (wired by game.gd).
func setup_camera(cam: Camera2D) -> void:
	_camera = cam


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
		if state == State.SUNNY:
			_enter(_pick_shower_kind())  # most showers are plain rain, some storm
		else:
			_enter(State.SUNNY)
	_follow_camera()


## Keeps the world-space emitters covering the camera view. The layers sit
## above the view top (drops fall in), the splash box spans the view.
func _follow_camera() -> void:
	if _camera == null or _rain_world == null:
		return
	_rain_world.position = _camera.position
	var ext: Vector2 = get_viewport().size * 0.5 / _camera.zoom.x * 1.15 + Vector2(80, 80)
	for l in _rain_layers:
		l.position = Vector2(0, -ext.y - 30)
		l.emission_rect_extents = Vector2(ext.x, 6)
	_splash.emission_rect_extents = ext


func _enter(next: State) -> void:
	state = next
	_state_time = 0.0
	match next:
		State.SUNNY:
			_next_change = _rng.randf_range(DRY_RANGE.x, DRY_RANGE.y)
			_set_rain_intensity(0.0, 1.0, false)
			_tint_target = 0.0
			_audio_target_db = -60.0
			_next_thunder = -1.0
		State.RAIN:
			_next_change = _rng.randf_range(RAIN_RANGE.x, RAIN_RANGE.y)
			_set_rain_intensity(RAIN_AMOUNT, 1.0, true)
			_tint_target = TINT_ALPHA
			_audio_target_db = -6.0
			if not _rain_audio.playing:
				_rain_audio.play()
			_schedule_thunder(THUNDER_RANGE)
		State.STORM:
			_next_change = _rng.randf_range(STORM_RANGE.x, STORM_RANGE.y)
			_set_rain_intensity(STORM_AMOUNT, 1.3, true)
			_tint_target = STORM_TINT_ALPHA
			_audio_target_db = -1.0
			if not _rain_audio.playing:
				_rain_audio.play()
			_schedule_thunder(STORM_THUNDER_RANGE)


## A shower has a chance to be a real thunderstorm.
func _pick_shower_kind() -> State:
	return State.STORM if _rng.randf() < STORM_CHANCE else State.RAIN


func _set_rain_intensity(amount: float, vel_scale: float, raining: bool) -> void:
	for i in _rain_layers.size():
		var l := _rain_layers[i]
		l.emitting = false
		l.amount = maxi(1, int(amount * _layer_share[i]))
		l.initial_velocity_min = 420.0 * vel_scale * _layer_speed[i]
		l.initial_velocity_max = 640.0 * vel_scale * _layer_speed[i]
		if raining:
			l.preprocess = l.lifetime  # already falling, not ramping up
		l.emitting = raining
	_splash.emitting = raining
	_splash.amount = 44 if state == State.STORM else 26


func _schedule_thunder(range_v: Vector2) -> void:
	_thunder_time = 0.0
	_next_thunder = _rng.randf_range(range_v.x, range_v.y)


func _thunder_clap() -> void:
	_thunder_audio.volume_db = -2.0 if state == State.STORM else -8.0
	_thunder_audio.play()
	_flash.color.a = FLASH_PEAK
	if state == State.STORM and _rng.randf() < STRIKE_CHANCE:
		lightning_struck.emit()
	_schedule_thunder(STORM_THUNDER_RANGE if state == State.STORM else THUNDER_RANGE)


func _build_overlays() -> void:
	if _tint != null:
		return
	_tint = ColorRect.new()
	# dark slate: source-over with a DARK color dims the whole scene — the
	# previous bluish-gray brightened dark tiles (water read brighter in rain!)
	_tint.color = Color(0.16, 0.19, 0.30, 0.0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tint)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


func _build_world_rain() -> void:
	if _rain_world != null:
		return  # _ready can fire twice (manual call in test harnesses)
	_rain_world = Node2D.new()
	_rain_world.z_index = 2600  # over buildings, under the hover ghost
	get_parent().add_child(_rain_world)
	for i in 3:
		var l := CPUParticles2D.new()
		l.texture = _streak_texture(12 + i * 4)
		l.lifetime = 1.1 + i * 0.15
		l.direction = Vector2(0.22, 1.0).normalized()
		l.spread = 3.0
		l.gravity = Vector2(0, 620)
		l.scale_amount_min = 0.55 + i * 0.3
		l.scale_amount_max = 0.75 + i * 0.45
		l.color = Color(0.85, 0.9, 1.0, 0.2 + i * 0.14)
		l.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		l.emission_rect_extents = Vector2(400, 6)
		l.emitting = false
		_rain_world.add_child(l)
		_rain_layers.append(l)

	# ground splashes: little fading puffs appearing across the view
	_splash = CPUParticles2D.new()
	_splash.texture = _splash_texture()
	_splash.lifetime = 0.28
	_splash.one_shot = false
	_splash.explosiveness = 0.0
	_splash.direction = Vector2(0, -1)
	_splash.spread = 60.0
	_splash.gravity = Vector2(0, 240)
	_splash.initial_velocity_min = 14.0
	_splash.initial_velocity_max = 34.0
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.85, 1.0, 0.55))
	ramp.set_color(1, Color(0.75, 0.85, 1.0, 0.0))
	_splash.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.3))
	_splash.scale_amount_curve = grow
	_splash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_splash.emission_rect_extents = Vector2(400, 240)
	_splash.emitting = false
	_rain_world.add_child(_splash)


## Vertical streak, fading at both ends. Longer for the nearer layers.
func _streak_texture(len_px: int) -> ImageTexture:
	var img := Image.create(3, len_px, false, Image.FORMAT_RGBA8)
	for y in len_px:
		var a := 0.25 + 0.75 * sin(PI * y / (len_px - 1))
		for x in 3:
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Tiny ring for ground splashes.
func _splash_texture() -> ImageTexture:
	var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	for y in 5:
		for x in 5:
			var d := Vector2(x - 2, y - 2).length()
			if d <= 2.2 and d >= 1.0:
				img.set_pixel(x, y, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)


func _build_audio() -> void:
	if _rain_audio != null:
		return
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
