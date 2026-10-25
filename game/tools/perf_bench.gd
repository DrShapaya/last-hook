extends SceneTree

# Headless CPU benchmark of a play session: physics ticks, frame updates,
# hook throws, aim forecasts and rope meshes. Run with LASTHOOK_SAVE_DIR set:
#   Godot --headless --path game --script res://tools/perf_bench.gd

func _initialize() -> void:
	call_deferred("run")

func _usec(callable: Callable, repeats: int) -> float:
	var start := Time.get_ticks_usec()
	for index in range(repeats): callable.call()
	return float(Time.get_ticks_usec()-start)/repeats

func run() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	seed(4242)
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	for index in range(30): game._process(1.0/60)
	print("obstacles=%d anchors=%d ledges=%d" % [game.world.obstacles.size(),game.world.anchors.size(),game.world.ledges.size()])
	var from: Vector2 = game.sim.pos
	print("predict_shot_us=%.1f" % _usec(func(): game.predict_shot(Vector2(.3,1).normalized()),40))
	print("cast_hook_us=%.2f" % _usec(func(): game.world.cast_hook(from,from+Vector2(.1,.2),game.model.hook_radius()),2000))
	print("move_player_us=%.2f" % _usec(func(): game.world.move_player(from,from+Vector2(.01,-.05),Vector2(0,-6)),2000))
	print("walk_velocity_us=%.2f" % _usec(func(): game.walk_velocity(0,1,1.0/120),300))
	var sim := RopeSim.new()
	sim.pos = from
	sim.attach(from+Vector2(1.5,4),6.0)
	game.explorer.draw(sim,sim.anchor,true,false,0.0,false,1,{})
	print("explorer_draw_attached_us=%.1f" % _usec(func(): game.explorer.draw(sim,sim.anchor,true,false,0.0,false,1,{}),300))
	# A scripted climb: throw toward the nearest higher grip, swing, release.
	var physics_time := 0
	var process_time := 0
	var worst_frame := 0
	var frames := 0
	var throws := 0
	for frame in range(1800):
		if game.state!="play": break
		if not game.sim.attached and not game.bolt_active and not game.bolt_returning and frame%20==0:
			var best := Vector2.INF
			for object in game.world.nearby_anchors(game.sim.pos.y+1,game.sim.pos.y+6):
				var point: Vector2 = object["pos"]
				if point.y>game.sim.pos.y+1 and (not best.is_finite() or point.distance_to(game.sim.pos)<best.distance_to(game.sim.pos)): best = point
			if best.is_finite():
				game.fire_hook(game.direction_to_target(best))
				throws += 1
		elif game.sim.attached and game.anchor_time>.9:
			game.release_hook(false,"bench")
		game.pressed = frame%90<30 and not game.sim.attached
		game.aim_direction = Vector2(.4,1).normalized()
		var start := Time.get_ticks_usec()
		game._physics_process(1.0/120)
		game._physics_process(1.0/120)
		var middle := Time.get_ticks_usec()
		game._process(1.0/60)
		var finish := Time.get_ticks_usec()
		physics_time += middle-start
		process_time += finish-middle
		worst_frame = maxi(worst_frame,finish-start)
		frames += 1
	print("frames=%d throws=%d physics_ms=%.3f process_ms=%.3f worst_ms=%.2f height=%.1f" % [frames,throws,physics_time/1000.0/maxi(1,frames),process_time/1000.0/maxi(1,frames),worst_frame/1000.0,game.sim.pos.y])
	# Streaming while the camera climbs at a brisk 6 m/s: the worst single
	# update is the hitch a player feels when a new section is built.
	var stream_worst := 0
	var stream_total := 0
	var updates := 0
	var y := 5.0
	while y<minf(game.summit_height,150.0):
		var start := Time.get_ticks_usec()
		game.world.update_visibility(y,0,1)
		var spent := Time.get_ticks_usec()-start
		if spent>15000 and OS.get_environment("LASTHOOK_BENCH_VERBOSE")=="1":
			print("  slow update y=%.1f %.1fms job=%d hazards_built=%d chunks=%s" % [y,spent/1000.0,game.world.build_job_key,game.world.hazard_visuals.built.size() if game.world.hazard_visuals!=null else -1,str(game.world.chunks.keys())])
		stream_worst = maxi(stream_worst,spent)
		stream_total += spent
		updates += 1
		y += .1
	print("stream_updates=%d stream_avg_ms=%.3f stream_worst_ms=%.2f" % [updates,stream_total/1000.0/maxi(1,updates),stream_worst/1000.0])
	game.queue_free()
	await process_frame
	quit(0)
