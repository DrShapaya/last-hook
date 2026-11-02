extends SceneTree

# Close pictures of a baked level, window by window from the foot up, for
# checking what stands on the rock:
#   Godot --path game --script res://tools/level_closeups.gd -- <level folder> <output prefix> [window height] [pixels per unit]
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if args.size()>0 else "res://levels/green_peak_r0"
	var prefix := args[1] if args.size()>1 else "user://closeup"
	var window := float(args[2]) if args.size()>2 else 20.0
	var scale := float(args[3]) if args.size()>3 else 32.0
	var source := LevelSource.open(folder.path_join("source"))
	var render = load("res://addons/level_editor/level_preview_render.gd").new()
	root.add_child(render)
	render.show_level(folder,"balanced",source.top(),LevelSource.X_MIN,LevelSource.X_MAX)
	var width: float = LevelSource.X_MAX-LevelSource.X_MIN
	render.size = Vector2i(roundi(width*scale),roundi(window*scale))
	render.camera.size = window
	for step in range(int(ceil(source.top()/window))):
		render.camera.position.y = (step+.5)*window
		render.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := "%s_%03d.png" % [prefix,step*int(window)]
		render.get_texture().get_image().save_png(file)
		print("CLOSEUP ",file)
	quit(0)
