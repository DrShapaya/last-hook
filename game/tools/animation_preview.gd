extends SceneTree

var rigs: Array[ExplorerSprite] = []
var elapsed := 0.0
var frame := 0
var frame_directory := ""
var frame_count := 120
var root_node: Node3D
var capturing := false

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	root.size = Vector2i(900,680)
	root.content_scale_size = Vector2i(900,680)
	root.title = "Last Hook — анимации персонажа"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): frame_directory = argument.trim_prefix("--frames=")
		if argument.begins_with("--count="): frame_count = int(argument.trim_prefix("--count="))
	if not frame_directory.is_empty(): DirAccess.make_dir_recursive_absolute(frame_directory)
	root_node = Node3D.new()
	root.add_child(root_node)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("223142")
	root_node.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.3
	camera.position = Vector3(0,0,10)
	root_node.add_child(camera)
	camera.current = true
	var overlay := CanvasLayer.new()
	root_node.add_child(overlay)
	var names := ["Ожидание","Бросок крюка","На канате","Полёт вверх","Падение","Приземление"]
	for index in range(6):
		var anchor := Node3D.new()
		anchor.position = Vector3((index%3-1)*1.9,.98 if index<3 else -1.03,0)
		root_node.add_child(anchor)
		var rig := ExplorerSprite.new()
		anchor.add_child(rig)
		rig.setup()
		rigs.append(rig)
		var label := Label.new()
		label.text = names[index]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(index%3*300,280 if index<3 else 600)
		label.size.x = 300
		label.add_theme_font_size_override("font_size",20)
		overlay.add_child(label)
	process_frame.connect(update)

func update() -> void:
	if capturing: return
	var dt := 1.0/30 if not frame_directory.is_empty() else minf(.05,root_node.get_process_delta_time())
	elapsed += dt
	for index in range(rigs.size()):
		var sim := RopeSim.new()
		sim.grounded = index==0 or (index==5 and fmod(elapsed,2.8)>.65)
		sim.attached = index==2
		sim.vel = Vector2(0,0)
		if index==2: sim.vel = Vector2(sin(elapsed*2)*6,cos(elapsed*2)*2)
		if index==3: sim.vel = Vector2(4,6)
		if index==4: sim.vel = Vector2(2,-7)
		if index==5 and not sim.grounded: sim.vel.y = -4
		rigs[index].animate(sim,Vector2(2,4),index==1 or index==2,elapsed)
	if not frame_directory.is_empty():
		capturing = true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(frame_directory.path_join("%04d.png" % frame))
		frame += 1
		capturing = false
		if frame>=frame_count:
			process_frame.disconnect(update)
			quit()
