extends SceneTree

# Level entry: how long start_run blocks, and how many frames pass before
# the section the hero stands in (and the rest of the view) is built.
#   Godot --headless --path game --script res://tools/perf_start.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	# As in the game: climb art is loaded and held before the first run.
	AssetWarmup.start()
	while not AssetWarmup.done():
		AssetWarmup.poll()
		await process_frame
	var prepared := OS.get_environment("LASTHOOK_PREPARED")=="1"
	game.prepare_worlds = prepared
	for attempt in range(3):
		if prepared:
			# The lobby is up: let the hidden world prepare as frames pass.
			game.state = "menu"
			game.model.profile["active"] = {}
			game.lobby_location = 0
			game.lobby_endless = false
			var menu_frames := 0
			var menu_worst := 0
			while menu_frames<1200 and not (is_instance_valid(game.prepared_world) and not game.prepared_world.stream_pending and menu_frames>2):
				var t := Time.get_ticks_usec()
				game._process(1.0/60)
				menu_worst = maxi(menu_worst,Time.get_ticks_usec()-t)
				if Time.get_ticks_usec()-t>12000: print("  menu frame %d: %.1fms job=%d band=%d" % [menu_frames,(Time.get_ticks_usec()-t)/1000.0,game.prepared_world.build_job_key if is_instance_valid(game.prepared_world) else -9,game.prepared_world.build_job_band if is_instance_valid(game.prepared_world) else -9])
				menu_frames += 1
				await process_frame
			print("prepared in %d menu frames, worst menu frame %.1fms" % [menu_frames,menu_worst/1000.0])
		var start := Time.get_ticks_usec()
		game.start_run(false)
		var entry := Time.get_ticks_usec()-start
		var world: MountainWorld = game.world
		var frames := 0
		var worst := 0
		var view_ready := -1
		var all_ready := -1
		var elapsed := entry
		while frames<600:
			var visible: bool = world.chunk_complete(0) and (game.camera_y+12<24 or world.chunk_complete(1))
			if visible and view_ready<0: view_ready = frames
			if not world.stream_pending and all_ready<0:
				all_ready = frames
				break
			var t := Time.get_ticks_usec()
			game._process(1.0/60)
			var spent := Time.get_ticks_usec()-t
			worst = maxi(worst,spent)
			elapsed += spent
			frames += 1
			await process_frame
		print("attempt %d: start_run=%.1fms view_ready_frame=%d all_ready_frame=%d worst_frame=%.1fms" % [attempt,entry/1000.0,view_ready,all_ready,worst/1000.0])
		game.state = "menu"
	quit(0)
