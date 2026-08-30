extends Node

## Shuffled playlist of the original Cytopia soundtracks.

const MUSIC_DIR := "res://assets/audio/music"
const VOLUME_DB := -9.0

var _player: AudioStreamPlayer
var _playlist: Array[String] = []


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	_player.finished.connect(_play_next)
	add_child(_player)

	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("Music directory not found: %s" % MUSIC_DIR)
		return
	for file in dir.get_files():
		if file.ends_with(".ogg") and not file.contains("_mono"):
			_playlist.append(MUSIC_DIR.path_join(file))
	_playlist.shuffle()
	_play_next()


func _play_next() -> void:
	if _playlist.is_empty():
		return
	# Rotate the playlist: every track plays before any repeats.
	var path := _playlist[0]
	_playlist.remove_at(0)
	_playlist.append(path)
	_player.stream = load(path)
	_player.play()
