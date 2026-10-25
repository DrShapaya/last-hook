class_name MusicPlayer
extends Node

# Background music: a calm camp theme in the menus and one theme per
# expedition on the climb (assets/music, composed by tools/make_music.py).
# Two players cross-fade, so a switch never cuts a phrase off. Pause and the
# result screen only lower the volume. The "music" profile switch turns it
# off without touching the sound effects.

const TRACKS := {"camp":"res://assets/music/camp.wav","green_peak":"res://assets/music/mountain.wav",
	"stone_spires":"res://assets/music/desert.wav","sky_city":"res://assets/music/winter.wav"}
const VOLUME_DB := -11.0
const DUCK_DB := -8.0
const FADE := 1.6
const SILENT_DB := -60.0

var players: Array[AudioStreamPlayer] = []
var current := 0
var track := ""
var enabled := true
var ducked := false
var fade: Tween

func _ready() -> void:
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENT_DB
		add_child(player)
		players.append(player)

static func track_for_location(location_id: String) -> String:
	return location_id if TRACKS.has(location_id) else "green_peak"

func target_db() -> float:
	return VOLUME_DB+(DUCK_DB if ducked else 0.0)

func play(name: String) -> void:
	if not TRACKS.has(name): return
	if name==track and players[current].playing: return
	track = name
	if not enabled: return
	var stream := load(TRACKS[name]) as AudioStream
	if stream==null: return
	var outgoing := players[current]
	current = 1-current
	var incoming := players[current]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_fade_to(incoming,outgoing)

func _fade_to(incoming: AudioStreamPlayer, outgoing: AudioStreamPlayer) -> void:
	if fade!=null and fade.is_valid(): fade.kill()
	fade = create_tween().set_parallel(true)
	fade.tween_property(incoming,"volume_db",target_db(),FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if outgoing!=null and outgoing.playing:
		fade.tween_property(outgoing,"volume_db",SILENT_DB,FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		fade.chain().tween_callback(outgoing.stop)

func set_enabled(on: bool) -> void:
	if on==enabled: return
	enabled = on
	if not on:
		if fade!=null and fade.is_valid(): fade.kill()
		fade = create_tween().set_parallel(true)
		for player in players:
			if player.playing: fade.tween_property(player,"volume_db",SILENT_DB,.5)
		fade.chain().tween_callback(func():
			for player in players: player.stop())
	elif not track.is_empty():
		var name := track
		track = ""
		play(name)

# Lowered under pause and result screens, back up on the climb.
func duck(on: bool) -> void:
	if on==ducked: return
	ducked = on
	if not enabled or not players[current].playing: return
	if fade!=null and fade.is_valid(): fade.kill()
	fade = create_tween()
	fade.tween_property(players[current],"volume_db",target_db(),.6).set_trans(Tween.TRANS_SINE)
