extends SceneTree

# Plays a baked level with the route bot and the base kit:
#   Godot --headless --path game --script res://tools/climb_level.gd -- <location>:<route>
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var spec := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "0:0"
	var location := int(spec.get_slice(":",0))
	var route := int(spec.get_slice(":",1))
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.set_route_choice(location,route)
	game.model.profile["locations"] = [0,1,2]
	game.selected_location = location
	game.start_run(false)
	var log: Array = []
	var started := Time.get_ticks_msec()
	var success := RouteBot.climb_to_summit(game,log)
	print("CLIMB %s baked=%s generator=%s success=%s seconds=%.1f shots=%d" % [spec,game.world.bake!=null,game.world.bake.generator if game.world.bake!=null else "-",success,game.run_seconds,game.shots])
	for line in log: print("  ",line)
	print("  wall time %d ms" % (Time.get_ticks_msec()-started))
	quit(0 if success else 1)
