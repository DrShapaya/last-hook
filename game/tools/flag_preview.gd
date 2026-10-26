extends SceneTree

# Renders every flag kind side by side on a stone ledge for a visual check.
# Run (windowed): godot --path game --script res://tools/flag_preview.gd -- out.png
const FloraModels := preload("res://scripts/flora_models.gd")

func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://flags.png"
	root.size = Vector2i(1600,700)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("88bfd9")
	environment.environment.ambient_light_color = Color(.7,.75,.8)
	environment.environment.ambient_light_energy = .8
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-30,0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(5.6,1.6,10)
	scene.add_child(camera)
	var ledge := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(13,.6,1.2)
	ledge.mesh = box
	ledge.position = Vector3(5.6,-.3,0)
	scene.add_child(ledge)
	var kinds := FloraModels.FLAGS.keys()
	for index in range(kinds.size()):
		FloraModels.flag(scene,kinds[index],FloraModels.COLORS[index%FloraModels.COLORS.size()],Vector3(index*1.6,0,.1),1.4 if kinds[index] in FloraModels.SMALL_FLAGS else 2.4,1.0,true,FloraModels.DESIGNS[index%FloraModels.DESIGNS.size()])
	FloraModels.flag_string(scene,Vector3(.2,3.3,.1),Vector3(10.8,3.3,.1),9,.35,7,true)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
