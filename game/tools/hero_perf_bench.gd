extends SceneTree

# What the hero costs per frame in a real attempt: render time (CPU and GPU,
# measured by the renderer) and the CPU time of a game frame (_process), for the 3D
# hero, the 3D hero without its outline pass, the painted hero and no hero.
# Needs a window (GPU timings). LASTHOOK_SAVE_DIR must point to a throwaway
# save folder:
#   Godot --path game --script res://tools/hero_perf_bench.gd

const FRAMES := 240
const WARMUP := 60

var game

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	root.size = Vector2i(720,1280)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results := {}
	for variant in ["3d","3d_no_outline","2d","none"]:
		results[variant] = await measure(variant)
	print("HERO_PERF variant   process_us  render_cpu_ms  render_gpu_ms")
	for variant in results:
		var r: Dictionary = results[variant]
		print("HERO_PERF %-13s %7.1f  %13.3f  %13.3f" % [variant,r["draw"],r["cpu"],r["gpu"]])
	quit()

func measure(variant: String) -> Dictionary:
	ExplorerView.use_3d_hero = variant.begins_with("3d")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	var body: Node3D = game.explorer.body
	if variant=="3d_no_outline": (body.get("shader_material") as ShaderMaterial).next_pass = null
	if variant=="none": body.visible = false
	var initial: Vector2 = game.world.anchors[0]["pos"]
	game.sim.pos = initial+Vector2(0,-2.8)
	game.sim.attach(initial,3.0)
	game.anchor_id = 0
	game.anchor_contact = initial
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	var draw_us := 0.0
	var cpu := 0.0
	var gpu := 0.0
	for frame in range(FRAMES):
		game.pump = 1.0 if frame%120<60 else -1.0
		for i in range(2): game._physics_process(1.0/120)
		var start := Time.get_ticks_usec()
		game._process(1.0/60)
		var spent := Time.get_ticks_usec()-start
		await RenderingServer.frame_post_draw
		if frame>=WARMUP:
			draw_us += spent
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	var counted := float(FRAMES-WARMUP)
	game.queue_free()
	await process_frame
	return {"draw":draw_us/counted,"cpu":cpu/counted,"gpu":gpu/counted}
