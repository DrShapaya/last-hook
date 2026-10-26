extends SceneTree

# Saves frames of the launch splash (the real main scene) for a visual check.
# Run (windowed): godot --path game --script res://tools/splash_frames.gd -- <out_prefix>
func _initialize() -> void:
	var prefix := OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var start := Time.get_ticks_msec()
	for at in Array(OS.get_cmdline_user_args()[1].split(",")).map(func(v): return int(v)):
		while Time.get_ticks_msec()-start<at: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_%d.png" % [prefix,at])
	quit()
