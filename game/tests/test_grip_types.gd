extends SceneTree

# The five grip types driven through the real game: catches, releases, timer,
# slide, spring throw and both crystal exits, flown by the base kit and by an
# upgraded hook, plus the state contract across save and load.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("GRIP TYPES FAILED: "+description)

func step(game, frames: int = 1) -> void:
	for frame in range(frames):
		if game.state!="play": return
		game._physics_process(1.0/120)
		game._move_camera(1.0/120)

# A seed may carry its location (v14: ice lives in the third expedition).
func new_run(game, seed_number: int, hook_level: int = 1, location: int = 0, version: int = 0) -> void:
	game.model.profile = GameModel.fresh_profile()
	game.model.set_level(GameModel.HOOKS,hook_level)
	game.selected_location = location
	game.start_run(false)
	game.run_seed = seed_number
	game._create_world(seed_number,location,game.summit_height+6,version)
	game._configure_rope()

# Test fixture: hang still under a grip, as after a catch, without flying there.
func hang_from(game, id: int) -> void:
	var grip: Dictionary = game.world.anchor_by_id(id)
	var contact: Vector2 = game.world.anchor_surface_point(grip,grip["pos"]+Vector2(0,-1),Vector2.UP)
	game.sim.pos = contact+Vector2(0,-2.8)
	game.sim.vel = Vector2.ZERO
	game.sim.attach(contact,game.model.shot_range())
	game.anchor_id = id
	game.anchor_time = 0.0
	game.anchor_contact = contact
	GripSpec.attach(grip)
	game.sim.highest = game.sim.pos.y
	game.camera_y = game.sim.pos.y+2.5
	game.camera_x = game.sim.pos.x

# Real swing, aim, release and hook flight from grip to grip (as in the
# foundation test). Timed and sliding grips are left at the first clear shot.
func traverse(game, route: Array) -> int:
	var reached := 1
	for target_id in route.slice(1):
		var target: Vector2 = game.world.anchor_by_id(target_id)["pos"]
		for frame in range(1200):
			if game.state!="play": return reached
			if game.sim.attached:
				game.reel = 1
				game.pump = signf(game.sim.vel.x) if absf(game.sim.vel.x)>.1 else signf(target.x-game.sim.anchor.x)
				var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
				var ignored: int = game.anchor_id if not current.get("permanent",true) else -1
				var sight: Dictionary = game.world.cast_hook(game.sim.pos,target,game.model.hook_radius(),ignored)
				var toward: Vector2 = (target-game.sim.pos).normalized()
				var hurry: bool = GripSpec.kind_of(current) in [GripSpec.ROOT,GripSpec.ICE]
				if int(sight.get("object",{}).get("id",-1))==target_id and game.sim.pos.distance_to(target)<5.2 and game.shot_window_open(target) and (game.sim.vel.dot(toward)>.5 or hurry):
					game.release_hook()
					game.fire_hook(game.direction_to_target(target))
			elif not game.bolt_active and not game.bolt_returning:
				game.fire_hook(game.direction_to_target(target))
			step(game)
			if game.sim.attached and game.anchor_id==target_id:
				reached += 1
				break
		if game.anchor_id!=target_id:
			print("GRIP_STOP target=",target_id," anchor=",game.anchor_id," state=",game.state," pos=",game.sim.pos)
			return reached
	return reached

# First branch of a hazard whose entry is consumed behind the player.
# The ice check keeps its v13 case on the first location: the mechanic is the
# same, and some v14 ice blocks have a drawn outline whose bump stops the
# slide early (see CHAT_3_REPORT).
func find_branch(seeds: Array, hazard: String, version: int = 0) -> Dictionary:
	for index in range(seeds.size()*3):
		var seed_number: int = seeds[index/3]
		var location := index%3 if version==0 else 0
		var total := float(LevelCatalog.level(location)["height_units"])
		var world := MountainWorld.new()
		world.visuals_enabled = false
		root.add_child(world)
		world.setup(seed_number,location,version)
		world.generate_to(total+6,true,total)
		for branch in world.layout.branches:
			if branch["hazard_state"]==hazard and branch["entry_consumed"] and world.main_route.has(branch["entry"]) and not branch.get("repeat",false):
				var found: Dictionary = branch.duplicate()
				found["seed"] = seed_number
				found["location"] = location
				found["exit_id"] = world.main_route[branch["exit_row"]]
				for other in world.layout.branches:
					if other.get("choice",false) and other["entry"]==branch["anchor"]: found["reward_exit_id"] = world.main_route[other["exit_row"]]
				world.free()
				return found
		world.free()
	return {}

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
	var seeds := range(40)

	# --- Stone: one consumption, permanent kept --------------------------------
	new_run(game,58273)
	var stone_id := -1
	for id in game.world.main_route.slice(1):
		var candidate: Dictionary = game.world.anchor_by_id(id)
		if GripSpec.kind_of(candidate)==GripSpec.STONE and not candidate["permanent"]:
			stone_id = id
			break
	var stone: Dictionary = game.world.anchor_by_id(stone_id)
	hang_from(game,stone_id)
	var swing := Vector2(2.5,1.5)
	game.sim.vel = swing
	game.release_hook()
	var after_release: Vector2 = game.sim.vel
	game.release_hook()
	check(stone["broken"] and GripSpec.state(stone)=="consumed","a released disposable stone is consumed")
	check(after_release==swing and game.sim.vel==after_release,"a stone keeps the swing velocity exactly and a second release changes nothing")
	check(not game.world.consume_anchor(stone_id) and game.world.cast_hook(stone["pos"]+Vector2(0,-3),stone["pos"],.76).get("object",{}).get("id",-1)!=stone_id,"a consumed stone is neither consumed again nor caught")

	# --- Spring: impulse along its exit, once ---------------------------------
	var spring_id := -1
	var spring_row := -1
	for row in range(3,game.world.main_route.size()-1):
		if GripSpec.kind_of(game.world.anchor_by_id(game.world.main_route[row]))==GripSpec.SPRING:
			spring_id = game.world.main_route[row]
			spring_row = row
			break
	check(spring_id>=0,"the test seed has a spring on its main path")
	var spring: Dictionary = game.world.anchor_by_id(spring_id)
	hang_from(game,spring_id)
	var loaded: Vector2 = GripSpec.exit_direction(spring)*4.0
	game.sim.vel = loaded
	game.release_hook()
	var thrown: Vector2 = game.sim.vel
	game.release_hook()
	check(absf(thrown.length()-4.0*(1+GripSpec.SPRING_BONUS))<.01 and game.sim.vel==thrown,"a loaded spring throws once with its bounded bonus (%.2f m/s)" % thrown.length())
	check(game.world.layout.spring_lane_clear(spring["pos"],GripSpec.exit_direction(spring)),"the spring's throw lane is clear of rock and points away from the fall zone")
	new_run(game,58273)
	hang_from(game,game.world.main_route[spring_row-1])
	var spring_route: Array = [game.world.main_route[spring_row-1],spring_id,game.world.main_route[spring_row+1]]
	check(traverse(game,spring_route)==3,"the base kit flies onto a spring and on to the next main grip")

	# --- Root: timer, break, save and load ------------------------------------
	var root_branch := find_branch(seeds,"timer")
	check(not root_branch.is_empty(),"a timed root detour exists in the first seeds")
	for hook_level in [1,2]:
		new_run(game,root_branch["seed"],hook_level,int(root_branch["location"]))
		hang_from(game,root_branch["entry"])
		var reached := traverse(game,[root_branch["entry"],root_branch["anchor"],root_branch["exit_id"]])
		check(reached==3,"hook radius %.2f: entry, timed root and exit are flown in time" % game.model.hook_radius())
		check(game.world.anchor_by_id(root_branch["anchor"])["broken"] and game.world.anchor_by_id(root_branch["entry"])["broken"],"the root and its entry are spent behind the player")
	new_run(game,root_branch["seed"],1,int(root_branch["location"]))
	var root_grip: Dictionary = game.world.anchor_by_id(root_branch["anchor"])
	hang_from(game,root_branch["anchor"])
	step(game,180)
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	root_grip = game.world.anchor_by_id(root_branch["anchor"])
	check(game.anchor_id==root_branch["anchor"] and absf(game.anchor_time-1.5)<.02 and GripSpec.state(root_grip)=="attached","a held root resumes with its clock (%.2f s) and attached state" % game.anchor_time)
	var warned := false
	for frame in range(150):
		if not game.sim.attached: break
		warned = warned or GripSpec.warning(root_grip,game.anchor_time)
		step(game)
	check(warned and root_grip["broken"] and game.last_release_reason=="root_break" and absf(game.anchor_time-GripSpec.ROOT_SECONDS)<.02,"the root warns, then breaks at %.1f s counted across the reload" % GripSpec.ROOT_SECONDS)
	if game.state=="play":
		game.save_snapshot()
		game.model.load_profile()
		game.resume_run()
	root_grip = game.world.anchor_by_id(root_branch["anchor"])
	check(root_grip["broken"] and GripSpec.state(root_grip)=="consumed" and game.world.cast_hook(root_grip["pos"]+Vector2(0,-3),root_grip["pos"],.76).get("object",{}).get("id",-1)!=root_branch["anchor"],"a broken root stays broken after reload and cannot be caught again")

	# --- Ice: slide, carried inertia, correction to the exit -------------------
	var ice_branch := find_branch(seeds,"slide",13)
	check(not ice_branch.is_empty(),"an ice detour exists in the first seeds")
	new_run(game,ice_branch["seed"],1,0,13)
	var ice: Dictionary = game.world.anchor_by_id(ice_branch["anchor"])
	hang_from(game,ice_branch["anchor"])
	var first_contact: Vector2 = game.sim.anchor
	step(game,96)
	var slid: Vector2 = game.sim.anchor
	var carried: Vector2 = game.anchor_slide_velocity
	var outline: PackedVector2Array = game.world.anchor_outline(ice)
	var on_stone: bool = Geometry2D.is_point_in_polygon(slid,outline) or game.world.anchor_surface_point(ice,slid).distance_to(slid)<.001
	check(slid.distance_to(first_contact)>.3 and on_stone and carried.length()>.3,"held ice slides the hook %.2f m over its stone and builds slide speed %.2f m/s" % [slid.distance_to(first_contact),carried.length()])
	var before: Vector2 = game.sim.vel
	game.release_hook()
	check(game.sim.vel.distance_to(before+carried)<.01,"releasing ice carries the slide into the flight")
	for hook_level in [1,2]:
		new_run(game,ice_branch["seed"],hook_level,0,13)
		hang_from(game,ice_branch["entry"])
		check(traverse(game,[ice_branch["entry"],ice_branch["anchor"],ice_branch["exit_id"]])==3,"hook radius %.2f: the ice detour is caught, slid and left for its exit" % game.model.hook_radius())

	# --- Crystal: both exits are flown ------------------------------------------
	var crystal_branch := find_branch(seeds,"choice")
	check(not crystal_branch.is_empty() and crystal_branch.has("reward_exit_id"),"a crystal fork with a reward exit exists in the first seeds")
	new_run(game,crystal_branch["seed"],1,int(crystal_branch["location"]))
	var crystal: Dictionary = game.world.anchor_by_id(crystal_branch["anchor"])
	check(GripSpec.choice_exits(crystal)==[crystal_branch["reward_exit"],crystal_branch["exit_id"]],"the crystal names its reward and main exits before it is used")
	hang_from(game,crystal_branch["entry"])
	check(traverse(game,[crystal_branch["entry"],crystal_branch["anchor"],crystal_branch["exit_id"]])==3,"the short exit of a crystal is flown")
	new_run(game,crystal_branch["seed"],1,int(crystal_branch["location"]))
	hang_from(game,crystal_branch["entry"])
	var reward_route: Array = [crystal_branch["entry"],crystal_branch["anchor"],crystal_branch["reward_exit"],crystal_branch["reward_exit_id"]]
	check(traverse(game,reward_route)==4,"the reward exit of a crystal is flown and rejoins the main path")
	check(game.world.anchor_by_id(crystal_branch["anchor"])["broken"],"choosing an exit consumes the crystal")

	# --- Biome variants keep the mechanic ----------------------------------------
	var looks := MountainWorld.new()
	root.add_child(looks)
	looks.setup(58273,0)
	looks.generate_to(40,true,120)
	var holder := Node3D.new()
	looks.add_child(holder)
	var profiles_ok := true
	var built := {}
	for biome in [["forest",10.0],["snow",70.0],["desert",90.0]]:
		var profile := GripBiomeProfile.named(biome[0])
		var materials := {}
		for kind in range(5):
			materials[profile.material_name(kind)] = true
			looks.layout._add_anchor(Vector2(0,float(biome[1])+kind*.1),kind,Vector2(1.3,.6))
			var grip: Dictionary = looks.layout.anchors[-1]
			looks.visuals.build_anchor(grip,holder)
			var cue: String = {GripSpec.STONE:"Полоса состояния",GripSpec.ROOT:"Трещина",GripSpec.SPRING:"Изгиб",GripSpec.ICE:"Трещина",GripSpec.CRYSTAL:"Кристалл"}[kind]
			if (grip["visual"] as Node3D).find_child(cue,true,false)!=null: built["%s_%d" % [biome[0],kind]] = true
		profiles_ok = profiles_ok and materials.size()==5 and GripBiomeProfile.id_for(0,float(biome[1]))==biome[0]
	check(profiles_ok and built.size()==15,"forest, snow and desert each give all five types their own material and cue (%d/15)" % built.size())
	looks.free()

	var report := FileAccess.open(directory.path_join("grip-types-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	game.queue_free()
	print("GRIP_TYPES_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
