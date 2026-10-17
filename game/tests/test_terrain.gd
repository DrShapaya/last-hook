extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error("TERRAIN FAILED: "+description)

func empty_world() -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(44,0)
	world.ledges.clear()
	return world

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var kinds := {}
	var shapes := {}
	var count := 0
	var safe := true
	var empty_loot := true
	var non_overlapping := true
	var branch_exits := true
	var rare_rest := true
	var no_adjacent_phrases := true
	for seed_number in range(100):
		var layout := EncounterLayout.new()
		layout.safe_routes = true
		layout.setup(seed_number,0)
		layout.generate_to(126,true,120)
		rare_rest = rare_rest and layout.ledges.size()<=7
		for i in range(layout.encounters.size()):
			var encounter: Dictionary = layout.encounters[i]
			kinds[encounter["kind"]] = true
			if i>0: no_adjacent_phrases = no_adjacent_phrases and encounter["kind"]!=layout.encounters[i-1]["kind"]
		for i in range(layout.obstacles.size()):
			var obstacle: Dictionary = layout.obstacles[i]
			count += 1
			shapes[obstacle["type"]] = true
			for j in range(i):
				var previous: Dictionary = layout.obstacles[j]
				non_overlapping = non_overlapping and not Rect2(obstacle["pos"]-obstacle["dimensions"]*.5,obstacle["dimensions"]).intersects(Rect2(previous["pos"]-previous["dimensions"]*.5,previous["dimensions"]))
			for row in range(layout.main_route.size()-1):
				safe = safe and layout._transfer_clear(layout.anchors[layout.main_route[row]]["pos"],layout.anchors[layout.main_route[row+1]]["pos"],obstacle)
			for find in layout.finds:
				empty_loot = empty_loot and SolidGeometry.cast(find["pos"],find["pos"],obstacle,Vector2(.3,.3)).is_empty()
		for branch in layout.branches:
			branch_exits = branch_exits and layout.transition_clear(layout.anchors[branch["entry"]]["pos"],layout.anchors[branch["anchor"]]["pos"]) and layout.transition_clear(layout.anchors[branch["anchor"]]["pos"],branch["exit_pos"])
	check(kinds.size()==8 and no_adjacent_phrases,"all eight movement phrases appear without adjacent repeats across 100 mountains")
	check(shapes.size()==3 and count>120,"pillars, shelves and sloped rocks are actually placed as encounter obstacles")
	check(safe and branch_exits,"primary hanging/shot lanes and forward loot exits remain clear across 100 seeds")
	check(empty_loot and non_overlapping,"loot cannot spawn inside solid geometry and obstacles do not overlap")
	check(rare_rest,"rest pockets stay limited rather than becoming an unlimited safety ladder")

	var world := empty_world()
	world.add_obstacle(Vector2(0,10),Vector2(2,2))
	var falling := world.move_player(Vector2(0,15),Vector2(0,8),Vector2(0,-18))
	check(falling["grounded"] and falling["position"].y>11.47 and falling["velocity"].y==0,"fast falls land on the top of a solid instead of tunnelling through it")
	var pos: Vector2 = falling["position"]
	var stable_floor := true
	for frame in range(240):
		var motion := world.move_player(pos,pos+Vector2(0,-14.0/14400),Vector2(0,-14.0/120))
		pos = motion["position"]
		stable_floor = stable_floor and motion["grounded"] and absf(pos.y-11.4801)<.001
	check(stable_floor,"resting body remains grounded for two seconds without jitter or sinking")
	var slide := world.move_player(Vector2(-3,10),Vector2(3,11.5),Vector2(10,2.5))
	check(slide["position"].x<-1.37 and slide["position"].y>11.4 and slide["velocity"].x==0,"side collisions preserve motion along the face")
	var embedded := world.move_player(Vector2(0,10),Vector2(.1,10),Vector2(2,0))
	check(embedded["position"].is_finite() and SolidGeometry.cast(embedded["position"],embedded["position"],world.obstacles[0],SolidGeometry.BODY_HALF).is_empty(),"a body starting inside a solid is pushed to the nearest surface")
	world.obstacles.clear()
	var wedge := {"pos":Vector2(0,10),"dimensions":Vector2(4,2),"polygon":PackedVector2Array([Vector2(-2,-1),Vector2(2,-1),Vector2(2,1)])}
	world.obstacles.append(wedge)
	check(world.cast_hook(Vector2(-1.5,10.7),Vector2(-1.5,12),.32).is_empty(),"hook casts do not hit the empty corner of a sloped obstacle's bounding box")
	var slope := world.move_player(Vector2(0,14),Vector2(0,9),Vector2(0,-8))
	check(slope["grounded"] and slope["velocity"].length()>1 and absf(slope["velocity"].x)>1,"landing on an inclined face slides along its real normal")
	var ray := world.rope_contact(Vector2(0,14),Vector2(0,9))
	var shot := world.cast_hook(Vector2(0,14),Vector2(0,9),.32)
	check(not ray.is_empty() and shot.get("blocked",false) and absf(ray["fraction"]-shot["fraction"])<.0001,"rope and projectile use exactly the same obstacle contour")

	world.obstacles.clear()
	world.add_ledge(Vector2(0,5),4)
	check(not world.move_player(Vector2(0,3),Vector2(0,7),Vector2(0,8))["grounded"],"one-way rest platforms can be crossed from below")
	check(world.move_player(Vector2(0,8),Vector2(0,3),Vector2(0,-8))["grounded"],"one-way platforms catch a descending player")
	check(not world.move_player(Vector2(-6,8),Vector2(0,3),Vector2(6,-5))["grounded"],"a platform is not caught when the crossing point misses its edge")
	world.ledges.clear()
	world.add_obstacle(Vector2(0,10),Vector2(2,2))
	var sim := RopeSim.new()
	sim.pos = Vector2(3,10)
	sim.attach(Vector2(-3,10),12)
	sim.length = 10
	sim.target_length = 10
	check(world.update_rope_path(sim) and sim.rope_pivots.size()==2 and sim.attached,"rope wraps around both corners of a blocking pillar without dropping the hero")
	var path_clear := true
	var previous := sim.anchor
	for point in sim.rope_pivots:
		path_clear = path_clear and not world.rope_blocked(previous,point)
		previous = point
	check(path_clear and not world.rope_blocked(previous,sim.pos),"every visible rope segment stays outside the obstacle")
	var fixed := sim.fixed_length()
	sim.request_length(2)
	check(sim.target_length>=fixed+.59,"reeling respects length already used by wrapped rope")
	sim.pos = Vector2(-3,8)
	check(world.update_rope_path(sim) and sim.rope_pivots.is_empty(),"rope unwraps automatically when the previous anchor becomes visible")
	sim.release(1)
	check(sim.rope_pivots.is_empty(),"release clears all old wrap contacts")
	sim.pos = Vector2(3,10)
	sim.attach(Vector2(-3,10),12)
	sim.length = 10
	sim.target_length = 2
	check(world.update_rope_path(sim) and sim.target_length>=sim.fixed_length()+.59,"adding a bend clamps an already-running reel request before it can over-shorten the fixed path")
	var bends_valid := true
	for point in [Vector2(3,8),Vector2(1,7),Vector2(-2,7),Vector2(-3,12)]:
		sim.pos = point
		bends_valid = bends_valid and world.update_rope_path(sim)
		sim.constrain_rope()
		bends_valid = bends_valid and sim.path_distance()<=sim.length+.001
	check(bends_valid,"changing sides of a pillar keeps the full routed length within the deployed rope")
	world.free()

	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.add_obstacle(Vector2(0,10),Vector2(2,2))
	var first: Dictionary = game.world.anchor_by_id(game.world.main_route[0])
	game.anchor_id = first["id"]
	game.anchor_contact = first["pos"]
	game.sim.pos = first["pos"]+Vector2(0,-3)
	game.sim.attach(first["pos"],5.5)
	game.sim.rope_pivots.append(first["pos"]+Vector2(1,-.5))
	var pivots: Array[Vector2] = game.sim.rope_pivots.duplicate()
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	check(game.world.generation_version==10 and game.sim.rope_pivots==pivots,"rope contacts survive save and resume with their route version")
	# Magnet reach is never permission to pull an item through a wall.
	game.world.finds.clear()
	game.world.obstacles.clear()
	game.world.add_obstacle(Vector2(0,10),Vector2(.6,2))
	game.model.profile["levels"][4] = 6
	game.model.bag.clear()
	game.world.finds.append({"pos":Vector2(.7,10),"picked":false,"item":{"id":990,"tier":0,"value":40}})
	game.sim.pos = Vector2(-.7,10)
	game._collect_finds()
	check(game.model.bag.is_empty(),"magnet cannot collect a find through a solid wall")
	game.world.obstacles.clear()
	game._collect_finds()
	check(game.model.bag.size()==1,"the same visible find can be collected once the solid is clear")
	game.start_run(false)
	var summit: Dictionary = game.world.ledges[-1]
	game.sim.pos = Vector2((summit["left"]+summit["right"])*.5,summit["top"]+.49)
	game.sim.vel = Vector2(0,-2)
	game.camera_y = game.sim.pos.y+2
	game._position_camera()
	game._physics_process(1.0/120)
	check(game.state=="result" and game.settlement.get("success",false),"standing on the actual summit platform completes the climb without requiring an extra jump")
	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("terrain-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"seeds":100,"obstacles":count},"\t"))
	print("TERRAIN_TESTS ",checks," checks, ",failures.size()," failures; obstacles=",count)
	quit(0 if failures.is_empty() else 1)
