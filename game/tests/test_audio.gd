extends SceneTree

# Music cross-fades, the sound bank and the vibration patterns.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func settle(music: MusicPlayer, seconds: float) -> void:
	var step := 1.0/60.0
	for index in range(int(seconds/step)): music._process(step)

func playing_tracks(music: MusicPlayer) -> Array:
	var paths := []
	for player in music.players:
		if player.playing: paths.append(player.stream.resource_path)
	return paths

func test_assets() -> void:
	for name in MusicPlayer.TRACKS:
		var stream := load(MusicPlayer.TRACKS[name]["path"]) as AudioStreamOggVorbis
		check(stream!=null and stream.loop,"%s loops" % name)
		check(stream!=null and stream.get_length()>120.0,"%s is a long track" % name)
		# A bar-aligned resume needs the whole track to be whole phrases.
		var phrases: float = stream.get_length()/float(MusicPlayer.TRACKS[name]["phrase"])
		check(absf(phrases-roundf(phrases))<.01,"%s is made of whole phrases" % name)
	for sound in SoundBank.SOUNDS:
		for take in range(1,int(SoundBank.SOUNDS[sound]["takes"])+1):
			check(ResourceLoader.exists("res://assets/sfx/%s_%d.wav" % [sound,take]),"%s take %d exists" % [sound,take])
	var wind := load("res://assets/sfx/wind_1.wav") as AudioStreamWAV
	check(wind!=null and wind.loop_mode==AudioStreamWAV.LOOP_FORWARD,"wind loops")

func test_music() -> void:
	var music := MusicPlayer.new()
	root.add_child(music)
	music.play("green_peak")
	settle(music,2.0)
	check(playing_tracks(music)==[MusicPlayer.TRACKS["green_peak"]["path"]],"one theme plays after a cross-fade")
	# A run ends: the result screen ducks, then the menu switches theme and
	# unducks in the same frame. This used to leave both themes running.
	music.duck(true)
	settle(music,1.0)
	check(music.players[music.current].volume_db<MusicPlayer.VOLUME_DB-3.0,"a duck lowers the music")
	music.play("camp")
	music.duck(false)
	settle(music,3.0)
	check(playing_tracks(music)==[MusicPlayer.TRACKS["camp"]["path"]],"the old theme stops when a duck and a switch land together")
	check(is_equal_approx(music.players[music.current].volume_db,MusicPlayer.VOLUME_DB),"the music returns to full volume")
	# Three quick switches never leave more than the newest theme behind.
	music.play("sky_city")
	settle(music,.2)
	music.play("stone_spires")
	settle(music,.2)
	music.play("camp")
	settle(music,3.0)
	check(playing_tracks(music)==[MusicPlayer.TRACKS["camp"]["path"]],"quick switches settle on one theme")
	music.set_enabled(false)
	settle(music,1.0)
	check(playing_tracks(music).is_empty(),"turning the music off stops it")
	music.set_enabled(true)
	settle(music,.1)
	check(playing_tracks(music)==[MusicPlayer.TRACKS["camp"]["path"]],"turning it back on resumes the theme")
	check(is_equal_approx(MusicPlayer.phrase_start("green_peak",34.0),30.0),"a theme resumes at the start of its phrase")
	check(MusicPlayer.track_for_location("unknown")=="green_peak","an unknown place gets the mountain theme")
	music.queue_free()

func test_sound_bank() -> void:
	var bank := SoundBank.new()
	root.add_child(bank)
	check(bank.play("launch"),"a sound plays")
	check(not bank.play("launch"),"the same sound cannot rattle inside its gap")
	check(not bank.play("nothing"),"an unknown sound is ignored")
	bank.clock += 1.0
	var overlap := bank.play("launch") and bank.play("rock") and bank.play("land")
	var busy := 0
	for player in bank.players:
		if player.playing: busy += 1
	check(overlap and busy>=3,"sounds overlap instead of cutting each other off")
	# A sound with several takes never repeats the same one twice in a row.
	var repeated := false
	for index in range(40):
		bank.clock += 1.0
		var before := int(bank.last_take.get("rock",0))
		bank.play("rock")
		repeated = repeated or int(bank.last_take["rock"])==before
	check(not repeated,"takes never repeat back to back")
	bank.set_key({"root":2,"scale":[0,2,4,7,9]})
	check(is_equal_approx(bank.note_pitch(0),pow(2.0,2.0/12.0)),"the root is the key of the music")
	check(is_equal_approx(bank.note_pitch(5),pow(2.0,14.0/12.0)),"the scale continues an octave up")
	check(is_equal_approx(bank.note_pitch(-1),pow(2.0,-1.0/12.0)),"the scale continues an octave down")
	var catch_pitches := []
	for index in range(SoundBank.CATCH_WALK.size()):
		bank.clock += .5
		bank.play_catch()
		catch_pitches.append(bank.catch_step)
	check(catch_pitches==[0,1,2,3,4,5,6,7],"a run of catches walks through the tune")
	bank.clock += 10.0
	bank.play_catch()
	check(bank.catch_step==0,"a pause starts the tune over")
	bank.set_wind(1.0)
	bank._process(.5)
	check(bank.wind.playing and bank.wind.volume_db>SoundBank.WIND_SILENT_DB,"wind rises with speed")
	var loudest := bank.wind.volume_db
	bank._process(.4)
	check(bank.wind.volume_db>loudest,"wind swells instead of popping in")
	bank.stop_all()
	check(not bank.wind.playing,"everything can be silenced")
	bank.queue_free()

func test_haptics() -> void:
	var haptics := Haptics.new()
	root.add_child(haptics)
	check(haptics.play("catch"),"a pattern plays")
	check(not haptics.play("rock"),"a light pattern waits for the running pulse")
	check(haptics.play("fail"),"a heavy pattern always gets through")
	haptics._process(1.0)
	haptics.enabled = false
	check(not haptics.play("win"),"the setting turns vibration off")
	haptics.enabled = true
	check(not haptics.play("nothing"),"an unknown pattern is ignored")
	var strongest := {}
	for name in Haptics.PATTERNS:
		var total := 0.0
		for step in Haptics.PATTERNS[name]:
			check(int(step[1])>=15 and float(step[2])<=1.0,"%s pulses can be felt" % name)
			total += float(step[1])*float(step[2])
		strongest[name] = total
	check(strongest["tap"]<strongest["catch"] and strongest["catch"]<strongest["fail"],"weight follows importance")
	haptics.queue_free()

func run_tests() -> void:
	test_assets()
	test_music()
	test_sound_bank()
	test_haptics()
	await process_frame
	print("AUDIO_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)
