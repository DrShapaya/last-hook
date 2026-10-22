extends SceneTree

# Close-up of single grips for visual checks: each grip head-on and from
# above-right, so the boulder's volume, paint and footing can be judged.
#   Godot --path game --script res://tools/grip_closeup.gd -- --out=DIR
#         [--seed=58273] [--quality=balanced] [--count=4]

var out_dir := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var seed_value := 58273
	var quality := "balanced"
	var count := 4
	# --near=x,y: the grips closest to a point instead of the first ones.
	var near := Vector2.INF
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--quality="): quality = argument.trim_prefix("--quality=")
		if argument.begins_with("--count="): count = int(argument.trim_prefix("--count="))
		if argument.begins_with("--near="):
			var parts := argument.trim_prefix("--near=").split(",")
			near = Vector2(float(parts[0]),float(parts[1]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(640,480)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("88bfd9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b6c7d6")
	environment.environment.ambient_light_energy = .62
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(preload("res://scripts/main.gd").SUN_DIRECTION,Vector3.UP)
	sun.light_color = Color("fff0d2")
	sun.light_energy = preload("res://scripts/main.gd").SUN_ENERGY*(3.2 if quality=="battery" else 1.0)
	sun.shadow_enabled = quality!="battery"
	sun.shadow_opacity = .44
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	stage.add_child(camera)
	camera.current = true
	var world := MountainWorld.new()
	stage.add_child(world)
	world.setup(seed_value,0)
	world.set_visual_quality(quality)
	world.generate_to(80,true,80)
	var shot := 0
	var order: Array = world.anchors.duplicate()
	if near.is_finite(): order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].distance_to(near)<b["pos"].distance_to(near))
	for anchor in order:
		if anchor.get("broken",false): continue
		if shot>=count or anchor["pos"].y<10: continue
		var at: Vector2 = anchor["pos"]
		world.update_visibility(at.y,at.x)
		for view in ["front","angle","bare"]:
			# bare: the same angle with the grip hidden, to tell its own
			# geometry from the face round it.
			(anchor["visual"] as Node3D).visible = view!="bare"
			if view=="bare": view = "angle_bare"
			var eye := Vector3(at.x,at.y,28) if view=="front" else Vector3(at.x+10,at.y+14,22)
			camera.position = eye
			camera.look_at(Vector3(at.x,at.y,2.0))
			for wait in range(3): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("grip_%d_%s.png" % [shot,view]))
		(anchor["visual"] as Node3D).visible = true
		print("GRIP ",shot," id=",anchor["id"]," pos=",at)
		shot += 1
	quit()
