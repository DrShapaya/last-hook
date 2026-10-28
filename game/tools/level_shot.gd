extends SceneTree

# A picture of a whole baked level as the level editor shows it, for checks
# and reports:  Godot --path game --script res://tools/level_shot.gd -- <level folder> <png>
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if args.size()>0 else "res://levels/green_peak_r0"
	var output := args[1] if args.size()>1 else "user://level.png"
	var source := LevelSource.open(folder.path_join("source"))
	var render = load("res://addons/level_editor/level_preview_render.gd").new()
	root.add_child(render)
	render.show_level(folder,"balanced",source.top(),LevelSource.X_MIN,LevelSource.X_MAX)
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	render.get_texture().get_image().save_png(output)
	print("LEVEL_SHOT ",output)
	quit(0)
