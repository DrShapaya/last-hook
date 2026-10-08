extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("RESPONSIVE FAILED: "+description)

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.preview = true
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	for dimensions in [Vector2i(486,864),Vector2i(432,960),Vector2i(800,800),Vector2i(1280,800),Vector2i(1600,720)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var viewport_size: Vector2 = game.get_viewport().get_visible_rect().size
		var area := Rect2(Vector2.ZERO,viewport_size).grow(.5)
		check(absf(viewport_size.aspect()-Vector2(dimensions).aspect())<.005,"world uses the complete window without letterboxing: %s" % dimensions)
		game.state = "menu"
		game.hud.show_menu()
		var lobby = game.hud.content.get_child(0)
		var contained := true
		for node in lobby.get_children():
			if node is Control:
				contained = contained and area.encloses(node.get_global_rect())
		check(contained and game.hud.backdrop.size==viewport_size,"all lobby controls fit and its background reaches every edge: %s" % dimensions)
		game.start_run(false)
		game.sim.pos = Vector2(0,7)
		game.camera_x = 0
		game.camera_y = 9
		game._position_camera()
		var point: Vector2 = game.camera.unproject_position(Vector3(1,8,0))
		check(game._screen_world(point).distance_to(Vector2(1,8))<.001,"camera projection and pointer coordinates agree: %s" % dimensions)
		check(game.hud.world_input_allowed(point) and not game.hud.world_input_allowed(game.hud.bag_panel.get_global_rect().get_center()),"world input works while inventory remains protected: %s" % dimensions)
		check(area.encloses(game.hud.bag_panel.get_global_rect()),"inventory stays fully inside the bottom edge: %s" % dimensions)
		game.pointer_down(point)
		game.pointer_up(point)
		check(game.bolt_active,"a real pointer gesture fires after the resize: %s" % dimensions)
		game.sim.attached = true
		game.sim.anchor = game.sim.pos+Vector2(1,3)
		game.model.profile["levels"][2] = 3
		game._process(.016)
		check(game.explorer.bolt.visible and game.explorer.tip_count==3,"attached rope keeps the three-prong hook visible: %s" % dimensions)
		var ends := mesh_ends(game.explorer.rope)
		check(ends[0].distance_to(game.explorer.body.grip_position())<.001 and ends[1].distance_to(game.explorer.bolt.to_global(ExplorerView.HOOK_EYE))<.001,"rendered braided rope joins the actual hand and hook eyelet: %s" % dimensions)
		game.bolt_active = true
		game.sim.attached = false
		game.bolt_pos = game.sim.pos+Vector2(1,3)
		game.model.profile["levels"][2] = 1
		game._process(.016)
		check(game.explorer.bolt.visible and game.explorer.tip_count==1,"the flying hook displays exactly the purchased tip count: %s" % dimensions)
		game.state = "pause"
		game.hud.show_pause()
		check(area.encloses(game.hud.content.get_child(0).get_global_rect()),"pause controls remain inside the resized viewport: %s" % dimensions)
	game.explorer.draw(game.sim,game.sim.pos+Vector2(-3,3),true,false,3.75,false,2)
	var mirrored_ends := mesh_ends(game.explorer.rope)
	check(game.explorer.body.facing==-1 and mirrored_ends[0].distance_to(game.explorer.body.grip_position())<.001,"the rig turns left while the rendered rope stays attached to the reaching hand")
	check(game.explorer.body.head.texture==game.explorer.body.head_blink,"the character closes its eyes during the blink")
	game.explorer.body.animate(game.sim,game.sim.pos+Vector2(3,3),true,4.0)
	check(game.explorer.body.facing==1 and game.explorer.body.head.texture==game.explorer.body.head_open,"the rig turns back right and opens its eyes after the blink")
	game.explorer.draw(game.sim,game.sim.pos+Vector2(0,3),true,false,4.0,false,1)
	var wrist_at_head: Vector3 = game.explorer.body.head.to_local(game.explorer.body.hands[1].global_position)
	check(absf(wrist_at_head.x)>game.explorer.body.head.texture.get_width()*game.explorer.body.head.pixel_size*.5,"a vertical reach keeps the wrist beside the face instead of intersecting the head")
	for index in range(2):
		var shoulder_local: Vector3 = game.explorer.body.torso.to_local(game.explorer.body.shoulders[index].global_position)
		var shoulder_pixel: Vector2 = Vector2(shoulder_local.x,-shoulder_local.y)/game.explorer.body.torso.pixel_size+game.explorer.body.torso.texture.get_size()*.5
		var opening_pixel := Vector2(31,108) if index==0 else Vector2(259,83)
		check(shoulder_pixel.distance_to(opening_pixel)<1,"shoulder %d is centred in the drawn armhole, rather than elsewhere on the jacket" % index)
		check(root_embedded(game.explorer.body.pelvis,game.explorer.body.hips[index]),"hip %d overlaps opaque shorts pixels and starts beneath the body" % index)
	game.sim.vel = Vector2.ZERO
	game.sim.attached = false
	game.sim.grounded = true
	game.explorer.body.animate(game.sim,game.sim.pos+Vector2(1,3),false,0)
	var hands_below_shoulders := true
	for index in range(2):
		var wrist: Vector3 = game.explorer.body.to_local(game.explorer.body.hands[index].global_position)
		hands_below_shoulders = hands_below_shoulders and absf(wrist.x-game.explorer.body.shoulders[index].position.x)<.025 and wrist.y<game.explorer.body.shoulders[index].position.y-.24
	check(hands_below_shoulders,"idle wrists hang below their shoulders instead of being splayed away from the torso")
	game.queue_free()
	await process_frame
	var output := FileAccess.open(directory.path_join("responsive-test-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	output.close()
	print("RESPONSIVE_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func root_embedded(owner_part: Sprite3D, limb_root: Node3D) -> bool:
	var image := owner_part.texture.get_image()
	var socket := owner_part.to_local(limb_root.global_position)
	if socket.z>=0: return false
	for offset in [Vector2.ZERO,Vector2(-.018,0),Vector2(.018,0),Vector2(0,-.018),Vector2(0,.018)]:
		var pixel := Vector2(socket.x+offset.x,-socket.y+offset.y)/owner_part.pixel_size+Vector2(image.get_size())*.5
		if pixel.x<0 or pixel.y<0 or pixel.x>=image.get_width() or pixel.y>=image.get_height(): return false
		if image.get_pixel(int(pixel.x),int(pixel.y)).a<.2: return false
	return true

func mesh_ends(mesh_node: MeshInstance3D) -> Array[Vector3]:
	var arrays := mesh_node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var end_v := 0.0
	for point in uv: end_v = maxf(end_v,point.y)
	var sums: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
	var counts := [0,0]
	for index in range(vertices.size()):
		for end in range(2):
			if absf(uv[index].y-(0.0 if end==0 else end_v))<.0001:
				sums[end] += mesh_node.to_global(vertices[index])
				counts[end] += 1
	return [sums[0]/maxi(1,counts[0]),sums[1]/maxi(1,counts[1])]
