extends SceneTree

# Records what the engine really mixes, to check the music after it has gone
# through import, decoding and resampling. Writes a raw 16-bit stereo WAV.
#   godot --headless --audio-driver Dummy --script res://tools/capture_audio.gd -- <stream> <out.wav> <from seconds> <seconds>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var stream: AudioStream = load(args[0])
	var from := float(args[2])
	var seconds := float(args[3])
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus,"Capture")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus,capture)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Capture"
	root.add_child(player)
	await process_frame
	player.play(from)
	var rate := AudioServer.get_mix_rate()
	var wanted := int(seconds*rate)
	var pcm := PackedByteArray()
	var taken := 0
	while taken<wanted:
		await process_frame
		var ready := capture.get_frames_available()
		if ready<=0: continue
		var frames := capture.get_buffer(ready)
		var start := pcm.size()
		pcm.resize(start+frames.size()*4)
		for index in range(frames.size()):
			pcm.encode_s16(start+index*4,int(clampf(frames[index].x,-1,1)*32767))
			pcm.encode_s16(start+index*4+2,int(clampf(frames[index].y,-1,1)*32767))
		taken += frames.size()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(rate)
	wav.data = pcm
	print("CAPTURED %d frames at %d" % [taken,int(rate)],", error ",wav.save_to_wav(args[1]))
	quit()
