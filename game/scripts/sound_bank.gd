class_name SoundBank
extends Node

# Every sound effect goes through here. The takes are baked by tools/make_sfx.py.
# A small pool of players lets sounds overlap instead of cutting each other
# off; a repeated sound picks another take with a slight pitch change, and a
# minimum gap per sound stops bursts from rattling. Catches and coins are
# transposed into the key of the music, stepping along its scale.

# takes, volume in dB, minimum gap in seconds, random pitch spread, and
# "tonal": the pitch follows the music instead of the random spread.
const SOUNDS := {
	"launch":{"takes":3,"db":-13.0,"gap":.07,"spread":.05},
	"catch":{"takes":3,"db":-11.0,"gap":.05,"tonal":true},
	"release":{"takes":2,"db":-19.0,"gap":.08,"spread":.06},
	"return":{"takes":2,"db":-18.0,"gap":.1,"spread":.05},
	"rock":{"takes":3,"db":-12.0,"gap":.09,"spread":.05},
	"spring":{"takes":2,"db":-11.0,"gap":.12,"spread":.03},
	"ice":{"takes":2,"db":-14.0,"gap":.15,"spread":.04},
	"land":{"takes":3,"db":-13.0,"gap":.12,"spread":.05},
	"step":{"takes":4,"db":-24.0,"gap":.1,"spread":.05},
	"tap":{"takes":2,"db":-22.0,"gap":.04,"spread":.02},
	"focus_in":{"takes":1,"db":-17.0,"gap":.2,"spread":0.0},
	"focus_out":{"takes":1,"db":-19.0,"gap":.2,"spread":0.0},
	"coin":{"takes":1,"db":-16.0,"gap":.035,"tonal":true},
	"pickup":{"takes":1,"db":-13.0,"gap":.08,"tonal":true},
	"item_arm":{"takes":1,"db":-15.0,"gap":.1,"spread":.02},
	"item_fire":{"takes":1,"db":-13.0,"gap":.1,"spread":.02},
	"knock":{"takes":1,"db":-10.0,"gap":.3,"spread":.04},
	"fail":{"takes":1,"db":-10.0,"gap":.5,"tonal":true},
	"win":{"takes":1,"db":-9.0,"gap":1.0,"tonal":true},
	"revive":{"takes":1,"db":-12.0,"gap":.5,"tonal":true},
	"gust":{"takes":1,"db":-13.0,"gap":1.0,"spread":.03}}
const VOICES := 12
const WIND_DB := -15.0
const WIND_SILENT_DB := -50.0
const WEATHER_DB := -12.0
const CAMPFIRE_DB := -16.0
# The loop file of each weather kind (assets/sfx/weather_<name>_1.wav).
const WEATHER_LOOPS := {"wind":"weather_wind","sand":"weather_sand","blizzard":"weather_blizzard"}
# Steps of the scale: a run of catches wanders upwards like a small tune
# instead of repeating one note or climbing without end.
const CATCH_WALK := [0,2,1,3,2,4,3,5]
const COIN_RUN := 8
const COIN_STREAK_SECONDS := 1.2
const CATCH_STREAK_SECONDS := 4.0

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_voice := 0
var last_take := {}
var last_played := {}
var clock := 0.0
var rng := RandomNumberGenerator.new()
var key := {"root":0,"scale":[0,2,4,7,9]}
var catch_step := 0
var catch_time := -100.0
var coin_step := 0
var coin_time := -100.0
var wind: AudioStreamPlayer
var wind_goal := 0.0
var wind_level := 0.0
var weather: AudioStreamPlayer
var weather_kind := ""
var weather_want := ""
var weather_goal := 0.0
var weather_level := 0.0
var campfire: AudioStreamPlayer
var campfire_goal := 0.0
var campfire_level := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for index in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		players.append(player)
	wind = AudioStreamPlayer.new()
	wind.bus = "SFX"
	wind.volume_db = WIND_SILENT_DB
	add_child(wind)
	weather = AudioStreamPlayer.new()
	weather.bus = "SFX"
	weather.volume_db = WIND_SILENT_DB
	add_child(weather)
	campfire = AudioStreamPlayer.new()
	campfire.bus = "SFX"
	campfire.volume_db = WIND_SILENT_DB
	add_child(campfire)

func take_path(sound: String, take: int) -> String:
	return "res://assets/sfx/%s_%d.wav" % [sound,take]

func _stream(sound: String, take: int) -> AudioStream:
	var path := take_path(sound,take)
	if not streams.has(path): streams[path] = load(path)
	return streams[path]

# Decides whether a sound may start now and which take it uses (0: skip it).
func _choose_take(sound: String) -> int:
	var spec: Dictionary = SOUNDS[sound]
	if clock-float(last_played.get(sound,-100.0))<float(spec["gap"]): return 0
	last_played[sound] = clock
	var takes := int(spec["takes"])
	var take := rng.randi_range(1,takes)
	if takes>1 and take==int(last_take.get(sound,0)): take = take%takes+1
	last_take[sound] = take
	return take

func play(sound: String, pitch := 0.0) -> bool:
	if not SOUNDS.has(sound): return false
	var take := _choose_take(sound)
	if take==0: return false
	var spec: Dictionary = SOUNDS[sound]
	var player := players[next_voice]
	next_voice = (next_voice+1)%players.size()
	var spread := float(spec.get("spread",0.0))
	if pitch<=0.0: pitch = note_pitch(0) if spec.get("tonal",false) else 1.0+rng.randf_range(-spread,spread)
	player.stream = _stream(sound,take)
	player.volume_db = float(spec["db"])
	player.pitch_scale = pitch
	player.play()
	return true

func set_key(tonality: Dictionary) -> void:
	key = tonality

# The pitch that moves a sample written on C to a step of the current scale.
func note_pitch(step: int) -> float:
	var scale: Array = key["scale"]
	var octave := floori(float(step)/scale.size())
	var degree: int = scale[posmod(step,scale.size())]
	return pow(2.0,(int(key["root"])+degree+12*octave)/12.0)

func play_catch() -> void:
	catch_step = (catch_step+1)%CATCH_WALK.size() if clock-catch_time<CATCH_STREAK_SECONDS else 0
	catch_time = clock
	play("catch",note_pitch(CATCH_WALK[catch_step]))

func play_coin() -> void:
	coin_step = (coin_step+1)%COIN_RUN if clock-coin_time<COIN_STREAK_SECONDS else 0
	coin_time = clock
	play("coin",note_pitch(coin_step))

func reset_streaks() -> void:
	catch_time = -100.0
	coin_time = -100.0

# 0 is calm air, 1 is falling or swinging as fast as the climb allows.
func set_wind(level: float) -> void:
	wind_goal = clampf(level,0,1)

# A storm of one kind ("wind", "sand", "blizzard"), 0..1; "" is clear air.
func set_weather(kind: String, level: float) -> void:
	weather_want = kind if WEATHER_LOOPS.has(kind) else ""
	weather_goal = clampf(level,0,1) if weather_want!="" else 0.0

# Embers crackling: 1 beside the fire, 0 out of earshot.
func set_campfire(level: float) -> void:
	campfire_goal = clampf(level,0,1)

func stop_all() -> void:
	for player in players: player.stop()
	wind_goal = 0.0
	wind_level = 0.0
	if wind!=null: wind.stop()
	weather_goal = 0.0
	weather_level = 0.0
	weather_want = ""
	campfire_goal = 0.0
	campfire_level = 0.0
	if weather!=null: weather.stop()
	if campfire!=null: campfire.stop()

func _process(delta: float) -> void:
	clock += delta
	if wind==null: return
	_update_loops(delta)
	# Gusts swell slowly and die away faster: the wind never pops in.
	wind_level = move_toward(wind_level,wind_goal,delta*(1.1 if wind_goal>wind_level else 1.8))
	if wind_level<=.001:
		if wind.playing: wind.stop()
		return
	if not wind.playing:
		wind.stream = _stream("wind",1)
		wind.play(rng.randf_range(0,7))
	wind.volume_db = lerpf(WIND_SILENT_DB,WIND_DB,sqrt(wind_level))
	wind.pitch_scale = 1.0+wind_level*.25

# The storm and campfire loops swell and fade like the wind. A storm of another
# kind first fades out, then the new loop starts.
func _update_loops(delta: float) -> void:
	if weather_level<=.001: weather_kind = weather_want
	var goal := weather_goal if weather_want==weather_kind else 0.0
	weather_level = move_toward(weather_level,goal,delta*(1.1 if goal>weather_level else 1.8))
	if weather_level<=.001:
		if weather.playing: weather.stop()
	elif weather_kind!="":
		if not weather.playing:
			weather.stream = _stream(WEATHER_LOOPS[weather_kind],1)
			weather.play(rng.randf_range(0,6))
		weather.volume_db = lerpf(WIND_SILENT_DB,WEATHER_DB,sqrt(weather_level))
		weather.pitch_scale = 1.0+.15*weather_level
	campfire_level = move_toward(campfire_level,campfire_goal,delta*(1.5 if campfire_goal>campfire_level else 2.0))
	if campfire_level<=.001:
		if campfire.playing: campfire.stop()
		return
	if not campfire.playing:
		campfire.stream = _stream("campfire",1)
		campfire.play(rng.randf_range(0,6))
	campfire.volume_db = lerpf(WIND_SILENT_DB,CAMPFIRE_DB,sqrt(campfire_level))
