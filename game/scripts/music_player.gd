class_name MusicPlayer
extends Node

# Background music: a calm camp theme in the menus and one theme per
# expedition on the climb (assets/music, composed by tools/make_music.py).
# Two players cross-fade, so a switch never cuts a phrase off. Each frame moves
# both players towards where they should be, so a duck or a quick return can
# never leave an old theme running under the new one. A theme picks up at the
# phrase where it was left, so short climbs do not restart the same intro.
# Pause and the result screen only lower the volume. The music volume setting
# turns it off at zero without touching the sound effects.

const TRACKS := {
	"camp":{"path":"res://assets/music/camp.ogg","phrase":12.632,"root":5,"scale":[0,2,4,7,9]},
	"green_peak":{"path":"res://assets/music/mountain.ogg","phrase":10.0,"root":2,"scale":[0,2,4,7,9]},
	"stone_spires":{"path":"res://assets/music/desert.ogg","phrase":11.429,"root":2,"scale":[0,1,4,7,8]},
	"sky_city":{"path":"res://assets/music/winter.ogg","phrase":13.714,"root":-3,"scale":[0,3,5,7,10]}}
const VOLUME_DB := -8.0
const DUCK_DB := -8.0
const FADE := 1.6
const OFF_FADE := .5
const DUCK_SPEED := 14.0
const SILENT_DB := -60.0
const MUFFLED_CUTOFF := 750.0
const OPEN_CUTOFF := 12000.0

var players: Array[AudioStreamPlayer] = []
var gains: Array[float] = [0.0,0.0]
var current := 0
var track := ""
var enabled := true
var ducked := false
var duck_level := 0.0
var resume_at := {}
var filter: AudioEffectLowPassFilter
var filter_index := -1

func _ready() -> void:
	# Keeps fading while the tree is paused on the pause screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENT_DB
		player.bus = "Music"
		add_child(player)
		players.append(player)

static func track_for_location(location_id: String) -> String:
	return location_id if TRACKS.has(location_id) else "green_peak"

static func tonality(name: String) -> Dictionary:
	return TRACKS.get(name,TRACKS["green_peak"])

func target_db() -> float:
	return VOLUME_DB+DUCK_DB*duck_level

# Where a theme resumes: the start of the phrase it was in.
static func phrase_start(name: String, position: float) -> float:
	var phrase := float(TRACKS[name]["phrase"])
	return floorf(position/phrase)*phrase

func _remember(player: AudioStreamPlayer) -> void:
	for name in TRACKS:
		if player.playing and player.stream!=null and player.stream.resource_path==TRACKS[name]["path"]:
			resume_at[name] = phrase_start(name,player.get_playback_position())

func play(name: String) -> void:
	if not TRACKS.has(name): return
	if name==track and players[current].playing: return
	track = name
	if not enabled: return
	var stream := load(TRACKS[name]["path"]) as AudioStream
	if stream==null: return
	_remember(players[current])
	current = 1-current
	var incoming := players[current]
	# The player taken over may still be fading out an older theme.
	_remember(incoming)
	incoming.stream = stream
	gains[current] = 0.0
	incoming.volume_db = SILENT_DB
	var length := stream.get_length()
	var start := float(resume_at.get(name,0.0))
	incoming.play(start if start<length-1.0 else 0.0)

func set_enabled(on: bool) -> void:
	if on==enabled: return
	enabled = on
	if on and not track.is_empty():
		var name := track
		track = ""
		play(name)

# Lowered under pause and result screens, back up on the climb.
func duck(on: bool) -> void:
	ducked = on

# Time slowing down also dulls the music: 0 is open, 1 fully muffled.
func set_muffled(amount: float) -> void:
	if filter==null:
		var bus := AudioServer.get_bus_index("Music")
		if bus<0: return
		filter = AudioEffectLowPassFilter.new()
		filter_index = AudioServer.get_bus_effect_count(bus)
		AudioServer.add_bus_effect(bus,filter)
		AudioServer.set_bus_effect_enabled(bus,filter_index,false)
	var active := amount>.001
	var index := AudioServer.get_bus_index("Music")
	if AudioServer.is_bus_effect_enabled(index,filter_index)!=active:
		AudioServer.set_bus_effect_enabled(index,filter_index,active)
	if active: filter.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF),log(MUFFLED_CUTOFF),clampf(amount,0,1)))

# A full-screen ad plays its own sound: everything holds until it closes.
func set_suspended(on: bool) -> void:
	for player in players: player.stream_paused = on

func _process(delta: float) -> void:
	duck_level = move_toward(duck_level,1.0 if ducked else 0.0,delta*DUCK_SPEED/absf(DUCK_DB))
	for index in range(players.size()):
		var player := players[index]
		if not player.playing: continue
		var wanted := 1.0 if enabled and index==current else 0.0
		gains[index] = move_toward(gains[index],wanted,delta/(FADE if enabled else OFF_FADE))
		if gains[index]<=0.0 and wanted==0.0:
			_remember(player)
			player.stop()
			continue
		# The gain is linear so two themes add up to a steady level in a cross-fade.
		player.volume_db = target_db()+linear_to_db(gains[index])
