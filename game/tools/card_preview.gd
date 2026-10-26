extends SceneTree

# Renders the three level cards (LevelPreview) side by side for a visual check.
# Run (windowed): godot --path game --resolution 1500x420 --script res://tools/card_preview.gd -- out.png
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for location in range(3):
		var card := LevelPreview.new()
		card.route_location = location
		card.position = Vector2(location*500,0)
		card.size = Vector2(484,363)
		root.add_child(card)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
