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

# Long texts stay inside their space: HUD notes left of the rope gauge, act
# names clear of the route pager, the training note shown in full.
func text_fit_tests(game) -> void:
	for dimensions in [Vector2i(486,864),Vector2i(360,640),Vector2i(432,960),Vector2i(960,540)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var area := Rect2(Vector2.ZERO,game.get_viewport().get_visible_rect().size).grow(.5)
		game.start_run(false)
		var spring: Dictionary = {}
		for anchor in game.world.anchors:
			if GripSpec.kind_of(anchor)==GripSpec.SPRING and not anchor.get("permanent",true): spring = anchor
		game.sim.attached = true
		game.anchor_id = int(spring.get("id",-1))
		game.sim.anchor = spring.get("pos",Vector2(0,9))
		game.sim.pos = game.sim.anchor+Vector2(0,-2.5)
		game.sim.rope_pivots.clear()
		game.sim.rope_pivots.append(game.sim.anchor+Vector2(.5,-.5))
		game._process(.016)
		await process_frame
		var gauge_left: float = game.hud.rope_gauge.get_global_rect().position.x
		var notes: Node = game.hud.aim_label.get_parent().get_parent()
		var fits: bool = not spring.is_empty() and game.hud.aim_label.text.contains("ветка подбросит")
		var widest := 0.0
		for holder in notes.get_children():
			if holder is Control and holder.visible:
				var rect: Rect2 = holder.get_global_rect()
				widest = maxf(widest,rect.end.x)
				fits = fits and rect.end.x<=gauge_left-4 and area.encloses(rect)
		check(fits,"HUD notes stay inside the screen and left of the rope gauge: %s (right edge %.0f, gauge %.0f)" % [dimensions,widest,gauge_left])
		game.sim.rope_pivots.clear()
		game.sim.attached = false
		game.anchor_id = -1
		game.model.profile["active"] = {}
		game.state = "menu"
		for location in range(3):
			game.lobby_location = location
			game.hud.show_menu()
			await process_frame
			var names := " · ".join(LevelCatalog.act_names(location))
			var label: Label = null
			for node in game.hud.content.find_children("*","Label",true,false):
				if node.text==names: label = node
			var marker_left := INF
			if label!=null:
				for node in label.get_parent().get_children():
					if node is Polygon2D:
						for point in node.polygon: marker_left = minf(marker_left,(node.get_global_transform()*point).x)
			check(label!=null and marker_left<INF and label.get_global_rect().end.x<=marker_left-4,"act names of route %d stay clear of the route pager: %s" % [location,dimensions])
			# Only the open first route offers training.
			if location!=0: continue
			var note: Label = null
			for node in game.hud.content.find_children("*","Label",true,false):
				if node.text.begins_with("Тренировка идёт"): note = node
			if note!=null: check(note.get_visible_line_count()>=note.get_line_count(),"the training note is shown in full: %s" % dimensions)
			elif dimensions==Vector2i(960,540): check(false,"the landscape lobby shows the training note")
	game.lobby_location = 0
	root.size = Vector2i(486,864)
	await process_frame

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
		var training_button: Button
		for node in lobby.find_children("*","Button",true,false):
			if node.text.begins_with("Тренировка"): training_button = node
		check(training_button!=null and training_button.get_parent().get_global_rect().encloses(training_button.get_global_rect()),"training button fits its lobby card without covering the footer: %s" % dimensions)
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
		game.model.set_level(GameModel.HOOKS,4)
		game._process(.016)
		check(game.explorer.bolt.visible and game.explorer.tip_count==3 and game.explorer.hook_count==2,"attached rope keeps the two triple hooks visible: %s" % dimensions)
		var ends := mesh_ends(game.explorer.rope)
		check(ends[0].distance_to(game.explorer.body.grip_position())<.001 and ends[1].distance_to(game.explorer.bolt.to_global(ExplorerView.HOOK_EYE))<.001,"rendered braided rope joins the actual hand and hook eyelet: %s" % dimensions)
		game.bolt_active = true
		game.sim.attached = false
		game.bolt_pos = game.sim.pos+Vector2(1,3)
		game.model.set_level(GameModel.HOOKS,1)
		game._process(.016)
		check(game.explorer.bolt.visible and game.explorer.tip_count==1,"the flying hook displays exactly the purchased tip count: %s" % dimensions)
		game.state = "pause"
		game.hud.show_pause()
		check(area.encloses(game.hud.content.get_child(0).get_global_rect()),"pause controls remain inside the resized viewport: %s" % dimensions)
		game.model.set_level(GameModel.BAG,5)
		game.model.bag.clear()
		for tier in range(6): game.model.bag.append({"id":tier,"tier":tier,"value":int(game.model.balance["loot_values"][tier])})
		game.hud.show_pause()
		await process_frame
		check(area.encloses(game.hud.content.get_child(0).get_global_rect()),"six inspected loot values fit the pause panel: %s" % dimensions)
		game.model.profile["active"] = {}
		game.model.profile["gold"] = 4540
		game.hud.show_result({"success":true,"first":true,"highest":1200,"height":540,"loot":900,"carried":900,"finish":1300,"diamonds":20,"total":2740,"zone_bonus":1800,"seconds":214,"shots":51,"catches":43})
		await process_frame
		check(area.encloses(game.hud.content.get_child(0).get_global_rect()),"summit reward and diamond labels fit without hiding action buttons: %s" % dimensions)
	await text_fit_tests(game)
	# Art regressions use the reference rig so intentional edits to player.tscn
	# do not prevent the user from building their own character.
	game.explorer.body.free()
	game.explorer.body = ExplorerRig.new()
	game.explorer.add_child(game.explorer.body)
	game.explorer.body.setup()
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
	var natural_rear_elbow := true
	for target_offset in [Vector2(3,3),Vector2(-3,3),Vector2(0,3),Vector2(3,-2),Vector2(-3,-2)]:
		game.explorer.body.animate(game.sim,game.sim.pos+target_offset,true,0)
		var shoulder: Vector3 = game.explorer.body.to_local(game.explorer.body.shoulders[1].global_position)
		var elbow: Vector3 = game.explorer.body.to_local(game.explorer.body.elbows[1].global_position)
		var wrist: Vector3 = game.explorer.body.to_local(game.explorer.body.hands[1].global_position)
		var reach := Vector2(wrist.x-shoulder.x,wrist.y-shoulder.y)
		var upper := Vector2(elbow.x-shoulder.x,elbow.y-shoulder.y)
		natural_rear_elbow = natural_rear_elbow and reach.cross(upper)<-.001
	check(natural_rear_elbow,"rear elbow stays on the flexion side of the shoulder-to-wrist line when reaching in either direction")
	game.queue_free()
	await process_frame
	var output := FileAccess.open(directory.path_join("responsive-test-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	output.close()
	print("RESPONSIVE_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func root_embedded(owner_part: Sprite3D, limb_root: Node3D) -> bool:
	var atlas := owner_part.texture as AtlasTexture
	var image := atlas.atlas.get_image() if atlas else owner_part.texture.get_image()
	if image.is_compressed(): image.decompress()
	if atlas: image = image.get_region(atlas.region)
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
