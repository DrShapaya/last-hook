extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("FOUNDATION FAILED: "+description)

func attach_first(game) -> void:
	var first: Dictionary = game.world.anchor_by_id(game.world.main_route[0])
	game.sim.pos = first["pos"]+Vector2(0,-2.8)
	game.sim.vel = Vector2.ZERO
	game.sim.attach(first["pos"],game.model.shot_range())
	game.anchor_id = first["id"]
	game.anchor_contact = first["pos"]
	game.safe_anchor_id = first["id"]
	game.safe_contact = first["pos"]
	game.safe_position = game.sim.pos

# Drives real movement, projectile, consumption and camera. No teleporting between targets.
func traverse(game, route: Array[int]) -> int:
	var reached := 1
	for target_id in route.slice(1):
		var target: Vector2 = game.world.anchor_by_id(target_id)["pos"]
		for frame in range(1200):
			if game.state!="play":
				print("FOUNDATION_STOP reached=",reached," target=",target_id," state=",game.state," pos=",game.sim.pos," reason=",game.failure_reason)
				return reached
			if game.sim.attached:
				game.reel = 1
				game.pump = signf(game.sim.vel.x) if absf(game.sim.vel.x)>.1 else signf(target.x-game.sim.anchor.x)
				var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
				var ignored: int = game.anchor_id if not current.get("permanent",true) else -1
				var sight: Dictionary = game.world.cast_hook(game.sim.pos,target,game.model.hook_radius(),ignored)
				var toward: Vector2 = (target-game.sim.pos).normalized()
				var window_open: bool = game.shot_window_open(target)
				var timed_exit: bool = int(current.get("kind",0))==1
				if int(sight.get("object",{}).get("id",-1))==target_id and game.sim.pos.distance_to(target)<5.2 and window_open and (game.sim.vel.dot(toward)>.5 or timed_exit):
					game.release_hook()
					game.fire_hook(game.direction_to_target(target))
			elif not game.bolt_active:
				game.fire_hook(game.direction_to_target(target))
			game._physics_process(1.0/120)
			game._move_camera(1.0/120)
			if game.sim.attached and game.anchor_id==target_id:
				reached += 1
				break
		if game.anchor_id!=target_id:
			print("FOUNDATION_STOP reached=",reached," target=",target_id," state=",game.state," pos=",game.sim.pos," anchor=",game.anchor_id)
			return reached
	return reached

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.balance["gravity"] = 18
	game._configure_rope()
	check(game.sim.gravity==18,"movement configuration reads the current gravity instead of relying on a default")
	game.model.balance["gravity"] = 14
	game._configure_rope()
	game.sim.pos = Vector2(0,12)
	game.sim.vel = Vector2(0,-8)
	var forecast_pos: Vector2 = game.sim.pos
	check(not game.shot_window_open(Vector2(0,17)) and game.sim.pos==forecast_pos,"aim forecast warns when a falling hero outruns the rope during projectile flight")
	game.sim.vel = Vector2(0,8)
	check(game.shot_window_open(Vector2(0,17)),"aim forecast allows the same target while moving toward it")
	# Validate directional branch exits and dormant reserves across generation variants.
	var exits_valid := true
	var dormant := true
	var branch_count := 0
	for seed_number in range(100):
		var layout := MountainLayout.new()
		layout.safe_routes = true
		layout.setup(seed_number,0)
		layout.generate_to(126,true,120)
		for branch in layout.branches:
			branch_count += 1
			var branch_point: Vector2 = layout.anchors[branch["anchor"]]["pos"]
			var exit: Vector2 = layout.anchors[layout.main_route[branch["exit_row"]]]["pos"]
			exits_valid = exits_valid and branch_point.distance_to(exit)<5.25 and layout.transition_clear(branch_point,exit)
		for id in layout.rescue_anchors.values():
			dormant = dormant and layout.anchors[id]["broken"] and not layout.anchors[id]["permanent"]
	check(branch_count>500 and exits_valid,"100 seeds give loot detours a clear forward exit independent of the consumed entry")
	check(dormant,"reserves never provide ordinary free safety or additional permanent grips")
	# Physically traverse a fragile loot detour, consuming its entry on the way.
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	attach_first(game)
	var branch: Dictionary = game.world.layout.branches[0]
	var branch_route: Array[int] = []
	for id in game.world.main_route:
		branch_route.append(id)
		if id==branch["entry"]:
			branch_route.append(branch["anchor"])
		if id==game.world.main_route[branch["exit_row"]]: break
	var detour_reached := traverse(game,branch_route)
	check(detour_reached==branch_route.size(),"base kit can enter and exit a timed-root loot detour through real flight")
	check(game.world.anchor_by_id(branch["entry"])["broken"],"detour exit does not require restoring its entry grip")
	# Reconstruct a failure after a spent primary sequence and prove the revived path.
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	attach_first(game)
	for index in range(1,8): game.world.consume_anchor(game.world.main_route[index])
	game.sim.attached = false
	game.sim.pos = game.world.anchor_by_id(game.world.main_route[7])["pos"]+Vector2(0,-2.8)
	game.sim.highest = game.sim.pos.y+3
	game.model.profile["diamonds"] = 10
	game.model.bag = [{"id":-50,"tier":5,"value":560}]
	game.model.picked = [-50,0]
	game.world.finds[0]["picked"] = true
	game.fail_run("spent route fixture")
	check(game.state=="revive" and game.revive_available(),"spent route offers a validated continuation rather than a dead return")
	game.revive("diamonds")
	check(game.revive_used and game.model.profile["diamonds"]==7,"safe continuation charges once only after validation")
	var route: Array[int] = [game.world.main_route[0]]
	var originals_spent := true
	for index in range(1,8):
		var original_id: int = game.world.main_route[index]
		if game.world.anchor_by_id(original_id).get("permanent",false):
			route.append(original_id)
		else:
			originals_spent = originals_spent and game.world.anchor_by_id(original_id)["broken"]
			route.append(game.world.layout.rescue_anchors[original_id])
	route.append(game.world.main_route[8])
	check(originals_spent and game.model.bag_value()==560 and game.world.finds[0]["picked"],"revival preserves consumed normal grips and collected loot")
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	var reserves_loaded := true
	for id in route.slice(1,8): reserves_loaded = reserves_loaded and not game.world.anchor_by_id(id)["broken"]
	check(reserves_loaded and game.run_seed==58273 and game.revive_used and game.world.finds[0]["picked"],"activated reserve path, exact seed and continuation allowance survive reload")
	check(traverse(game,route)==route.size(),"revived base kit physically traverses the reserves into the untouched route")
	# A blocked/obsolete exit must not debit currency or consume the allowance.
	game.revive_used = false
	game.state = "revive"
	game.model.profile["diamonds"] = 10
	var next: Vector2 = game.world.anchor_by_id(game.world.main_route[9])["pos"]
	game.world.add_obstacle((game.safe_contact+next)*.5,Vector2(2,2))
	game.revive("diamonds")
	check(game.model.profile["diamonds"]==10 and not game.revive_used and game.state=="revive","invalidated recovery route cannot take payment or consume revival")
	game.finish_run(false)
	game.show_menu()
	# Isolated training uses the same movement while protecting real purchases/wallet.
	var real: GameModel = game.model
	real.profile["gold"] = 1234
	real.profile["diamonds"] = 40
	real.profile["levels"] = [6,6,3,6,6,6,6]
	real.save()
	var real_profile: Dictionary = real.profile.duplicate(true)
	var real_file := FileAccess.get_file_as_string(real.save_path)
	game.start_practice()
	check(game.world.layout is PracticeLayout and game.world.main_route.size()==16,"training provides a fixed short route of sixteen primary grips")
	check(game.model!=real and game.model.profile["levels"]==[1,1,1,1,1,1,1],"training uses base equipment in a separate model")
	var first: Vector2 = game.world.anchor_by_id(game.world.main_route[0])["pos"]
	game.fire_hook(game.direction_to_target(first))
	for frame in range(120):
		game._physics_process(1.0/120)
		game._move_camera(1.0/120)
		if game.sim.attached: break
	check(game.sim.attached,"training starts with a real base-kit hook from the ground")
	check(traverse(game,game.world.main_route)==16,"base kit traverses the entire fixed training route")
	for frame in range(600):
		if game.state!="play": break
		game.reel = 1
		game.pump = signf(game.sim.vel.x) if absf(game.sim.vel.x)>.1 else 1
		game._physics_process(1.0/120)
		game._move_camera(1.0/120)
	check(game.state=="result" and game.settlement.get("success",false),"training reaches an actual finish with its own result")
	game.show_menu()
	check(game.model==real and real.profile==real_profile and FileAccess.get_file_as_string(real.save_path)==real_file,"training does not mutate the normal profile in memory or on disk")
	game.start_practice()
	game.fail_run("training mistake")
	check(game.state=="result" and not game.revive_used,"training retries do not require currency or revival")
	game.show_menu()
	var report := FileAccess.open(directory.path_join("foundation-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	game.queue_free()
	print("FOUNDATION_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
