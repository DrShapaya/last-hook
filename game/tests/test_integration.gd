extends SceneTree

var failures: Array[String] = []
var checks := 0
var summit_sessions: Array = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("INTEGRATION FAILED: " + description)

func run_tests() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(game.run_seed,0,126)
	game._process(.1)
	check(game.state=="play" and game.model.level(3)==1,"new run starts with the base kit")
	check(game.world.anchors.size()>30 and game.world.ledges.size()>2,"finite mountain has a continuous route and rest ledges")
	var rock: Dictionary = game.world.anchors[0]
	var center: Vector2 = rock["pos"]
	var left_from := center+Vector2(-.7,-1.2)
	var left_to := center+Vector2(-.7,1.2)
	var right_from := center+Vector2(.7,-1.2)
	var right_to := center+Vector2(.7,1.2)
	var left_hit: float = game.world.hit_object(left_from,left_to,rock,.32)
	var right_hit: float = game.world.hit_object(right_from,right_to,rock,.32)
	check(left_hit>=0 and right_hit>=0,"either side of the same visible rock can catch the hook")
	check(left_from.lerp(left_to,left_hit).distance_to(right_from.lerp(right_to,right_hit))>1.3,"different shots produce different rope contact positions on one rock")
	check(game.world.hit_object(center+Vector2(-2,1.1),center+Vector2(2,1.1),rock,.32)<0,"empty space above a rectangle is not a hidden anchor")
	var small_rock := {"pos":Vector2(0,3),"dimensions":Vector2(1,1)}
	check(game.world.hit_object(Vector2(.9,1),Vector2(.9,5),small_rock,.32)<0 and game.world.hit_object(Vector2(.9,1),Vector2(.9,5),small_rock,.53)<0 and game.world.hit_object(Vector2(.9,1),Vector2(.9,5),small_rock,.76)>=0,"three real prongs catch a near miss that one and two prongs cannot reach")
	check(game.world.hit_object(Vector2(.7,1),Vector2(.7,5),small_rock,.32)<0 and game.world.hit_object(Vector2(.7,1),Vector2(.7,5),small_rock,.53)>=0,"two prongs have a useful catch advantage over the base hook")
	var first: Vector2 = game.world.anchors[0]["pos"]
	var screen_point: Vector2 = game.camera.unproject_position(Vector3(first.x,first.y,0))
	game.pointer_down(screen_point)
	game.pointer_up(screen_point)
	for i in range(32):
		game._physics_process(1.0/120)
	check(game.sim.attached and game.anchor_id==0,"world input fires a swept hook and catches the first anchor")
	check("aim" in game.model.profile["learned_controls"],"the aim lesson completes only after an actual catch")
	game.pointer_down(Vector2(300,400))
	var old_length: float = game.sim.target_length
	game.pointer_move(Vector2(210,370))
	check(game.pump<0 and game.reel==0 and game.sim.target_length==old_length,"moving the first finger vertically never reels the rope")
	game.pointer_up(Vector2(210,370))
	check(game.sim.attached,"ending a swing drag does not detach the hook")
	game.pointer_down(Vector2(300,400))
	game.pointer_up(Vector2(300,400))
	check(game.sim.attached,"a first-finger tap cannot release the hook")
	var first_touch := InputEventScreenTouch.new()
	first_touch.index = 3
	first_touch.position = Vector2(300,400)
	first_touch.pressed = true
	game._unhandled_input(first_touch)
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = false
	touch.position = Vector2(300,920)
	game._input(touch)
	check(not game.pressed and game.pump==0,"a gesture ending over inventory cannot remain stuck")
	first_touch.pressed = true
	game._unhandled_input(first_touch)
	var second_touch := InputEventScreenTouch.new()
	second_touch.index = 8
	second_touch.position = Vector2(410,450)
	second_touch.pressed = true
	game._unhandled_input(second_touch)
	check(game.primary_touch==3 and game.rope_touch==8,"touch identities do not rely on index zero and assign an independent rope finger")
	var second_drag := InputEventScreenDrag.new()
	second_drag.index = 8
	second_drag.position = Vector2(410,425)
	game._input(second_drag)
	check(game.sim.target_length<old_length and game.sim.length==old_length,"second finger upward requests shortening without an instant length jump")
	var shortened_target: float = game.sim.target_length
	second_drag.position = Vector2(410,475)
	game._input(second_drag)
	check(game.sim.target_length>shortened_target,"second finger downward requests rope extension")
	second_touch.pressed = false
	second_touch.position = Vector2(410,920)
	game._input(second_touch)
	check(game.rope_touch==-1 and game.sim.attached,"ending the rope finger over inventory does not release the hook")
	first_touch.pressed = false
	game._input(first_touch)
	check(game.sim.attached and not game.pressed,"lifting the stationary primary after a two-finger gesture does not count as a release tap")
	first_touch.pressed = true
	game._unhandled_input(first_touch)
	second_touch.pressed = true
	second_touch.position = Vector2(410,450)
	game._unhandled_input(second_touch)
	var tap_length: float = game.sim.target_length
	second_drag.position = Vector2(412,452)
	game._input(second_drag)
	check(game.sim.target_length==tap_length and game.sim.attached,"tap jitter neither reels nor releases before the second finger lifts")
	game.rope_press_msec -= 500
	second_touch.pressed = false
	second_touch.position = Vector2(412,452)
	game._input(second_touch)
	check(game.sim.attached,"holding the second finger without dragging is not a release tap")
	second_touch.pressed = true
	game._unhandled_input(second_touch)
	second_touch.pressed = false
	game._input(second_touch)
	check(not game.sim.attached and game.primary_touch==3 and game.pressed,"a short second-finger tap releases and keeps the first finger available for the next shot")
	first_touch.pressed = false
	game._input(first_touch)
	check(game.bolt_active and not game.pressed,"the same primary finger can fire the next hook after second-finger release")
	# Restore a known initial grip before the movement bot.
	game.bolt_active = false
	game.sim.pos = first+Vector2(0,-2.8)
	game.sim.vel = Vector2.ZERO
	game.sim.attach(first,game.model.value("rope_lengths",0))
	game.anchor_id = 0
	game.anchor_contact = first
	var reached := climb_route(game,4)
	check(reached>=3,"base kit can climb consecutive anchors through swing/release rather than purchased reach")
	for seed_number in [101,58273,410021,999999]:
		game.start_run(false)
		game.run_seed = seed_number
		game._create_world(seed_number,0,126)
		var initial: Vector2 = game.world.anchors[0]["pos"]
		game.sim.pos = initial+Vector2(0,-2.8)
		game.sim.attach(initial,5.5)
		game.anchor_id = 0
		game.anchor_contact = initial
		var climbed := climb_route(game,8)
		check(climbed==8,"base-kit movement bot climbs eight generated grips, seed %d (reached %d)" % [seed_number,climbed])
	for seed_number in [58273,101,410021]:
		game.start_run(false)
		game._create_world(seed_number,0,126)
		var initial: Vector2 = game.world.anchors[0]["pos"]
		game.sim.pos = initial+Vector2(0,-2.8)
		game.sim.attach(initial,5.5)
		game.anchor_id = 0
		game.anchor_contact = initial
		var count: int = game.world.main_route.size()-1
		var climbed := climb_route(game,count)
		check(climbed==count,"movement bot climbs the complete primary route below the summit, seed %d (reached %d/%d)" % [seed_number,climbed,count])
	for side in [-1,1]:
		game.start_run(false)
		game._create_world(58273,0,126)
		var route := route_to_side(game.world,side)
		var initial: Vector2 = game.world.anchors[0]["pos"]
		game.sim.pos = initial+Vector2(0,-2.8)
		game.sim.attach(initial,5.5)
		game.anchor_id = 0
		game.anchor_contact = initial
		var climbed := climb_route(game,route.size(),route)
		check(route.size()>2 and climbed==route.size(),"movement bot traverses to the %s side of the wide mountain (%d/%d grips)" % ["left" if side<0 else "right",climbed,route.size()])
	for scenario in [[58273,1],[101,1],[410021,1],[58273,3],[101,6]]:
		var seed_number: int = scenario[0]
		var kit: int = scenario[1]
		game.model.profile = GameModel.fresh_profile()
		game.model.profile["levels"].fill(kit)
		game.model.profile["levels"][2] = mini(kit,3)
		game.start_run(false)
		game._create_world(seed_number,0,126)
		game.fire_hook(game.world.anchors[0]["pos"]-game.sim.pos)
		for frame in range(120):
			game._physics_process(1.0/120)
			game._move_camera(1.0/120)
			if game.sim.attached: break
		climb_route(game,game.world.main_route.size())
		for frame in range(1800):
			if game.state!="play": break
			game.reel = 1
			game.pump = signf(game.sim.vel.x) if absf(game.sim.vel.x)>.1 else 1.0
			game._physics_process(1.0/120)
			game._move_camera(1.0/120)
		check(game.state=="result" and game.settlement.get("success",false),"fresh base-kit run reaches and settles the actual summit from the starting platform, seed %d" % seed_number)
		check(game.model.profile["run_history"].size()==1 and game.model.profile["run_history"][0]["seconds"]>0,"completed run records local pace and shot metrics once, seed %d" % seed_number)
		print("FULL_SUMMIT seed=",seed_number," kit=",kit," seconds=",snappedf(game.run_seconds,.1)," shots=",game.shots," catches=",game.catches)
		summit_sessions.append(game.model.profile["run_history"][0].duplicate(true))
	game.start_run(false)
	game.world.anchors.clear()
	game.world.layout.bins.clear()
	game.world.obstacles.clear()
	game.world.add_anchor(game.sim.pos+Vector2(0,8),0)
	var long_rope_times: Array[float] = []
	for rope_level in [1,6]:
		for force_level in [1,6]:
			game.sim.attached = false
			game.bolt_active = false
			game.model.profile["levels"] = [rope_level,1,1,1,1,1,force_level]
			game.fire_hook(Vector2(0,1))
			game._update_bolt(.01)
			check(absf(game.bolt_pos.distance_to(game.bolt_origin)-(.16 if force_level==1 else .4))<.001,"projectile speed depends only on force, rope %d force %d" % [rope_level,force_level])
			var flight_time := .01
			for frame in range(100):
				if not game.bolt_active: break
				game._update_bolt(.01)
				flight_time += .01
			check(game.sim.attached==(rope_level==6),"only rope length determines whether the 80 m grip can be reached, rope %d force %d" % [rope_level,force_level])
			if rope_level==6: long_rope_times.append(flight_time)
	check(long_rope_times[0]>long_rope_times[1]*2,"strong throw catches the same far grip over twice as fast as weak throw")
	game.sim.attached = false
	game.world.anchors.clear()
	game.world.layout.bins.clear()
	var shot_start: Vector2 = game.sim.pos
	game.world.add_anchor(shot_start+Vector2(0,7),0)
	game.model.profile["levels"] = [1,1,1,1,1,1,1]
	game.fire_hook(Vector2(0,1))
	game._update_bolt(.1)
	game.sim.pos += Vector2(0,2)
	for frame in range(100):
		if game.bolt_active: game._update_bolt(.01)
	check(game.sim.attached,"moving toward a grip pays rope out from the current hero position, beyond the old shot origin")
	game.sim.attached = false
	game.sim.pos = shot_start
	game.fire_hook(Vector2(0,1))
	game._update_bolt(.1)
	game.sim.pos -= Vector2(0,5)
	game._update_bolt(1)
	check(not game.sim.attached and not game.bolt_active,"moving away cannot attach through a fully paid-out rope even with a large time step")
	for material in [3,4]:
		game.world.anchors.clear()
		game.world.layout.bins.clear()
		game.sim.pos = shot_start
		game.sim.attached = false
		game.bolt_active = false
		game.world.add_anchor(shot_start+Vector2(0,3),material)
		game.fire_hook(Vector2(0,1))
		game._update_bolt(.25)
		check(game.sim.attached,"a one-prong hook catches material %d without the removed grip gate" % material)
	game.toast("Проверка причины промаха")
	game.hud.update_play()
	check(game.hud.toast_label.visible,"play mode shows immediate feedback instead of hiding it")
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.sim.pos = Vector2(12,50)
	game.camera_x = 0
	game._process(.5)
	check(game.camera_x>8 and game.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"camera follows the player sideways without perspective scale changes")
	check(game.world.chunks.size()<=4,"only nearby terrain chunks have live visual nodes")
	game.world.update_visibility(100,12)
	check(not game.world.chunks.has(0) and game.world.chunks.size()<=4,"terrain behind the camera is unloaded")
	game.world.update_visibility(7,0)
	check(game.world.chunks.has(0),"returning to an unloaded section rebuilds its geometry")
	var grip: Dictionary = game.world.anchors[0]
	grip["broken"] = true
	game.world.update_visibility(100,0)
	game.world.update_visibility(7,0)
	check(not grip["visual"].visible,"broken grip state survives visual chunk unloading")
	grip["broken"] = false
	game.world.update_visibility(7,0)
	var far_layer: Node3D = game.world.parallax_layers[0]
	var near_layer: Node3D = game.world.parallax_layers[1]
	var far_before: float = far_layer.get_child(0).position.x
	var near_before: float = near_layer.get_child(0).position.x
	game.world.update_visibility(7,4)
	var far_shift: float = absf(fposmod(far_layer.get_child(0).position.x-far_before+40,80)-40)
	var near_shift: float = absf(fposmod(near_layer.get_child(0).position.x-near_before+40,80)-40)
	check(near_shift>far_shift+.5,"clouds move faster than distant mountains under orthographic parallax")
	game.start_run(false)
	game.sim.pos = Vector2(21,40)
	game._physics_process(1.0/120)
	check(game.state=="play","leaving the mountain silhouette into sky does not cause defeat")
	game.start_run(false)
	game.model.profile["levels"][3] = 3
	game.model.bag = [{"id":-5,"tier":0,"value":40},{"id":-6,"tier":1,"value":200}]
	game.hud.refresh_bag()
	check(game.hud.bag_panel.get_child_count()==3,"backpack upgrades expose usable inventory cells, including empty cells")
	var slot: BagSlot = game.hud.bag_panel.get_child(1)
	var slot_touch := InputEventScreenTouch.new()
	slot_touch.index = 7
	slot_touch.position = Vector2(25,25)
	slot_touch.pressed = true
	slot._gui_input(slot_touch)
	slot._process(.3)
	slot_touch.pressed = false
	slot._gui_input(slot_touch)
	check(game.model.bag_value()==240,"a short tap cannot discard inventory accidentally")
	slot_touch.pressed = true
	slot._gui_input(slot_touch)
	slot._process(.7)
	check(game.model.bag.size()==1 and game.model.bag_value()==40,"holding a specific cell discards that item, rather than automatically choosing the cheapest")
	game.model.profile["levels"][3] = 1
	game.state = "play"
	game.model.bag = [{"id":-7,"tier":0,"value":200}]
	game.model.picked = [-7]
	game.revive_used = false
	game.sim.highest = maxf(25,game.sim.highest)
	game.focus_remaining = .23
	game.sim.request_length(game.sim.length+.4)
	var saved_target: float = game.sim.target_length
	game.save_snapshot()
	var before: float = game.sim.highest
	var saved_seed: int = game.run_seed
	var saved_contact: Vector2 = game.sim.anchor
	game.model.load_profile()
	game.resume_run()
	check(game.sim.highest==before and game.run_seed==saved_seed,"active run preserves height and layout seed across reload")
	check(game.sim.anchor.distance_to(saved_contact)<.001,"the actual surface contact survives reload without snapping to the object center")
	check(absf(game.sim.target_length-saved_target)<.001,"a selected pending rope length survives reload without automatic reeling")
	check(absf(game.focus_remaining-.23)<.001,"reloading cannot refill the aiming window")
	check(game.model.picked.has(-7) and game.model.bag[0]["tier"] is int,"saved item IDs normalize to integers")
	game.fail_run("test fall")
	check(game.state=="revive","first failure offers a single continuation")
	game.show_menu()
	game.save_snapshot()
	game.resume_run()
	check(game.state=="revive","returning to the menu cannot erase an unresolved defeat")
	game.revive("test_ad")
	check(game.state=="play" and game.revive_used and game.model.bag_value()==200,"test continuation preserves inventory and consumes the allowance")
	check(game.sim.highest==before,"continuation cannot reset height reward bands")
	game.fail_run("second fall")
	check(game.state=="result","second failure settles the run immediately")
	check(int(game.settlement["loot"])==60,"scene applies 30 percent retention at defeat")
	var settled_gold: int = game.model.profile["gold"]
	game.finish_run(false)
	check(int(game.model.profile["gold"])==settled_gold,"repeated result calls cannot duplicate scene rewards")
	game.start_run(true)
	check(game.state=="result","endless mode cannot start before first summit")
	game.start_run(false)
	game.model.reach(120)
	game.sim.highest = 120.63
	game.finish_run(true)
	check(game.model.profile["summit_cleared"],"first summit unlock is wired through the scene")
	game.start_run(true)
	var original_height: float = game.world.generated_height
	game.sim.pos = Vector2(0,original_height-30)
	game.sim.highest = game.sim.pos.y
	game.sim.flight_peak = game.sim.pos.y
	game.sim.launched = false
	game._physics_process(1.0/120)
	check(game.world.generated_height>original_height,"endless route extends as the player approaches its edge")
	game.start_run(false)
	game.sim.pos = Vector2(0,2)
	game.sim.vel = Vector2(0,-2)
	game.sim.highest = 3
	game.sim.flight_peak = 3
	game.sim.launched = true
	for frame in range(100):
		game._physics_process(1.0/120)
	check(game.state=="play" and game.sim.grounded,"a short fall onto the starting platform is recoverable rather than instant defeat")
	# Defeat is tied to the rendered lower edge, never to sky or lateral distance.
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.camera_y = 42
	game._position_camera()
	var bottom: float = game.screen_bottom_y()
	game.sim.pos = Vector2(1000,bottom+.2)
	game.sim.flight_peak = 10000
	game.sim.launched = true
	game._physics_process(1.0/120)
	check(game.state=="play","visible hero survives in open sky far outside both lateral rock edges and below an old height record")
	game.sim.pos = Vector2(1000,bottom-.4)
	game.sim.vel = Vector2.ZERO
	game._physics_process(1.0/120)
	check(game.state=="play","partly visible hero below the lower edge still has time to catch")
	game.sim.pos.y = bottom-1.1
	game._physics_process(1.0/120)
	check(game.state=="revive" and game.failure_reason=="Упал ниже экрана","whole hero leaving the bottom of the viewport causes defeat")
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.camera_y = 42
	game._position_camera()
	game.sim.pos = Vector2(0,36)
	game.sim.vel = Vector2(0,-8)
	game._move_camera(.5)
	check(game.camera_y>=42,"camera does not follow a falling hero downward and erase the risk")
	game.sim.attach(Vector2(0,38),5.5)
	game.sim.flight_peak = 200
	game._physics_process(1.0/120)
	check(game.state=="play","catching a visible lower grip stays legal regardless of accumulated height loss")
	game.sim.attached = false
	game.sim.pos = Vector2(30,36)
	game.sim.vel = Vector2(5,0)
	game._move_camera(.5)
	game._physics_process(1.0/120)
	check(game.state=="play" and game.camera_x>20,"camera follows the hero horizontally beyond the former mountain limit")
	game.save_snapshot()
	var saved_camera: float = game.camera_y
	game.model.load_profile()
	game.resume_run()
	check(absf(game.camera_y-saved_camera)<.001,"saving and resuming cannot lower the camera to reopen a missed rescue")
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	var disposable_id: int = game.world.main_route[1]
	var disposable: Dictionary = game.world.anchor_by_id(disposable_id)
	game.sim.pos = disposable["pos"]+Vector2(0,-2.8)
	game.sim.attach(disposable["pos"],5.5)
	game.anchor_id = disposable_id
	game.anchor_contact = disposable["pos"]
	game.sim.highest = game.sim.pos.y
	game.release_hook()
	check(disposable["broken"] and not disposable["visual"].visible,"detaching immediately removes an ordinary grip from collision and rendering")
	var cast: Dictionary = game.world.cast_hook(game.sim.pos,disposable["pos"],.32)
	check(cast.is_empty() or int(cast.get("object",{}).get("id",-1))!=disposable_id,"removed grip cannot be caught again to undo a risky release")
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	check(game.world.anchor_by_id(disposable_id)["broken"],"consumed grip remains removed after save and reload")
	game.world.update_visibility(100,0)
	game.world.update_visibility(7,0)
	check(not game.world.anchor_by_id(disposable_id)["visual"].visible,"consumed grip stays invisible after its chunk is rebuilt")
	var permanent: Dictionary = game.world.anchors[0]
	game.sim.pos = permanent["pos"]+Vector2(0,-2.8)
	game.sim.attach(permanent["pos"],5.5)
	game.anchor_id = 0
	game.release_hook()
	check(permanent["permanent"] and not permanent["broken"] and permanent["visual"].visible,"rare permanent grip survives detaching and can be reused")
	for legacy_version in [6,7]:
		game.model.profile = GameModel.fresh_profile()
		game.start_run(false)
		game.run_seed = 58273
		game._create_world(58273,0,126,legacy_version)
		game.sim.pos = game.world.anchors[0]["pos"]+Vector2(0,-2.5)
		game.sim.attach(game.world.anchors[0]["pos"],5.5)
		game.anchor_id = 0
		game.anchor_contact = game.sim.anchor
		game.sim.highest = game.sim.pos.y
		game.save_snapshot()
		game.model.profile["active"].erase("camera_y")
		game.model.save()
		var old_next: Vector2 = game.world.anchor_by_id(game.world.main_route[1])["pos"]
		game.model.load_profile()
		game.resume_run()
		check(game.state=="play" and game.world.generation_version==legacy_version and game.world.anchor_by_id(game.world.main_route[1])["pos"]==old_next,"unfinished v%d attempts resume on their exact old geometry" % legacy_version)
		game.save_snapshot()
		check(game.model.profile["active"]["generation_version"]==legacy_version,"resaving an old attempt preserves its generator version")
		game.finish_run(false)
	game.start_run(false)
	check(game.world.generation_version==8,"new attempts use the sparse v8 route after an old attempt finishes")
	game.model.profile["learned_controls"] = ["aim"]
	game.sim.pos = game.world.anchors[0]["pos"]+Vector2(0,-3)
	game.sim.attach(game.world.anchors[0]["pos"],5.5)
	game.anchor_id = 0
	game.anchor_contact = game.sim.anchor
	game.sim.vel = Vector2(3,0)
	game.pump = 1
	game._physics_process(1.0/120)
	check("swing" in game.model.profile["learned_controls"] and "rope" not in game.model.profile["learned_controls"],"real pumping completes swing without completing the rope lesson")
	game.sim.request_length(game.sim.length-.4)
	game._physics_process(1.0/120)
	check("rope" in game.model.profile["learned_controls"],"manual rope adjustment completes its separate lesson")
	var release_key := InputEventKey.new()
	release_key.keycode = KEY_SPACE
	release_key.pressed = true
	game._unhandled_input(release_key)
	check("release" in game.model.profile["learned_controls"] and not game.sim.attached,"manual release completes the final control lesson")
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	game.catches = 3
	check(game.hud.tutorial_hint().is_empty(),"completed control hints stay completed after saving and resuming")
	game.audio.stop()
	game.audio.stream = null
	game.queue_free()
	await create_timer(.06).timeout
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	var sessions_file := FileAccess.open(directory.path_join("summit-test-sessions.json"),FileAccess.WRITE)
	sessions_file.store_string(JSON.stringify({"source":"automated_integration_bot","run_history":summit_sessions},"\t"))
	sessions_file.close()
	var output := FileAccess.open(directory.path_join("integration-test-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"bot_anchors":reached},"\t"))
	output.close()
	print("INTEGRATION_TESTS ",checks," checks, ",failures.size()," failures; bot anchors=",reached)
	quit(0 if failures.is_empty() else 1)

func climb_route(game, count: int, override_route: Array[int] = []) -> int:
	var reached := 1
	for route_index in range(1,count):
		var target_id: int = game.world.main_route[route_index] if override_route.is_empty() else override_route[route_index]
		var target: Vector2 = game.world.anchor_by_id(target_id)["pos"]
		var fired := false
		for frame in range(1200):
			if game.state!="play":
				print("BOT_STOP route=",route_index," state=",game.state," pos=",game.sim.pos," target=",target)
				return reached
			if game.sim.attached:
				game.reel = 1.0
				if absf(game.sim.pos.x)>14 and game.sim.vel.x*game.sim.pos.x>0:
					game.pump = -signf(game.sim.pos.x)
				elif absf(game.sim.vel.x)>.1:
					game.pump = signf(game.sim.vel.x)
				elif absf(game.pump)<.1:
					game.pump = signf(target.x-game.sim.anchor.x)
				var toward: Vector2 = (target-game.sim.pos).normalized()
				var sight: Dictionary = game.world.cast_hook(game.sim.pos,target,.32)
				var clear_shot: bool = not sight.is_empty() and not sight.get("blocked",false) and int(sight["object"]["id"])==target_id
				if clear_shot and game.sim.pos.distance_to(target)<5.2 and game.sim.vel.dot(toward)>.5:
					game.release_hook()
					game.fire_hook(target-game.sim.pos)
					fired = true
			game._physics_process(1.0/120)
			game._move_camera(1.0/120)
			if game.anchor_id==target_id and game.sim.attached:
				reached += 1
				break
			if fired and not game.bolt_active and not game.sim.attached:
				game.fire_hook(target-game.sim.pos)
		if reached!=route_index+1:
			print("BOT_TIMEOUT route=",route_index," pos=",game.sim.pos," target=",target," attached=",game.sim.attached," anchor=",game.anchor_id," expected=",target_id)
			return reached
	return reached

func route_to_side(world: MountainWorld, side: int) -> Array[int]:
	var adjacency: Dictionary = {}
	for edge in world.route_edges:
		if not adjacency.has(edge.x): adjacency[edge.x] = []
		if not adjacency.has(edge.y): adjacency[edge.y] = []
		adjacency[edge.x].append(edge.y)
		adjacency[edge.y].append(edge.x)
	var start: int = world.main_route[0]
	var parents := {start:-1}
	var queue: Array[int] = [start]
	var cursor := 0
	var goal := -1
	while cursor<queue.size():
		var id := queue[cursor]
		cursor += 1
		var point: Vector2 = world.anchors[id]["pos"]
		if point.x*side>14 and point.y>15 and point.y<30:
			goal = id
			break
		for neighbour in adjacency.get(id,[]):
			if not parents.has(neighbour):
				parents[neighbour] = id
				queue.append(neighbour)
	var route: Array[int] = []
	while goal>=0:
		route.push_front(goal)
		goal = parents[goal]
	return route
