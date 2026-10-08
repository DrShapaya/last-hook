extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("GENERATION FAILED: "+description)

func make_world(seed_number: int, height: float, finite: bool = true, biome: int = 0, version: int = 0) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_number,biome,version)
	world.generate_to(height,finite,120)
	return world

func signature(world: MountainWorld) -> Array:
	var result: Array = []
	for anchor in world.anchors:
		result.append([anchor["id"],anchor["pos"],anchor["dimensions"],anchor["kind"]])
	for obstacle in world.obstacles:
		result.append([obstacle["pos"],obstacle["dimensions"]])
	for find in world.finds:
		result.append([find["item"],find["pos"]])
	result.append(world.route_edges.duplicate())
	return result

func run_tests() -> void:
	var first := make_world(58273,126)
	var duplicate := make_world(58273,126)
	check(signature(first)==signature(duplicate),"seed recreates every grip, barrier and find")
	duplicate.free()
	var partial := make_world(58273,15)
	partial.generate_to(38,true,120)
	partial.generate_to(71,true,120)
	partial.generate_to(126,true,120)
	check(signature(first)==signature(partial),"incremental finite generation equals a single full request")
	var count := partial.anchors.size()
	partial.generate_to(126,true,120)
	check(partial.anchors.size()==count,"repeating generation cannot duplicate the route or summit")
	partial.free()
	var other := make_world(410021,126)
	check(signature(first)!=signature(other) and first.cliff_edge(1,1)!=other.cliff_edge(1,1),"different seeds change the route and cliff silhouette")
	other.free()
	var endless := make_world(81,24,false)
	var prefix := signature(endless)
	endless.generate_to(72,false)
	var complete := make_world(81,72,false)
	check(signature(endless)==signature(complete),"endless extension is independent of request sizes")
	check(signature(endless).slice(0,endless.anchors.size()).slice(0,6)==prefix.slice(0,6),"endless extension preserves earlier grip IDs and positions")
	complete.free()
	endless.free()
	var reachable := true
	var stable := true
	var safe := true
	var varied := true
	var wide := true
	var connected := true
	var supported := true
	var obstacle_count := 0
	var new_grips := 0
	var old_grips := 0
	var rare_permanent := true
	var rare_ledges := true
	for seed_number in range(100):
		var world := make_world(seed_number,126)
		var previous := make_world(seed_number,126,true,0,7)
		new_grips += world.anchors.size()
		old_grips += previous.anchors.size()
		previous.free()
		var permanent_count := 0
		for object in world.anchors:
			if object["permanent"]: permanent_count += 1
		rare_permanent = rare_permanent and float(permanent_count)/world.anchors.size()<.22
		rare_ledges = rare_ledges and world.ledges.size()<=7
		var min_x := 99.0
		var max_x := -99.0
		for object in world.anchors:
			min_x = minf(min_x,object["pos"].x)
			max_x = maxf(max_x,object["pos"].x)
			supported = supported and world.layout.rock_field(object["pos"])>0
		wide = wide and min_x<-15 and max_x>15
		var is_connected := world.layout.stable_network_connected(world.route_edges)
		if not is_connected: print("DISCONNECTED seed=",seed_number)
		connected = connected and is_connected
		obstacle_count += world.obstacles.size()
		var last := Vector2(0,.63)
		var first_gap := -1.0
		var varying_gap := false
		for id in world.main_route:
			var grip := world.anchor_by_id(id)
			var point: Vector2 = grip["pos"]
			reachable = reachable and last.distance_to(point)<=5.5 and point.y>last.y
			stable = stable and grip["kind"] in [0,2]
			for obstacle in world.obstacles:
				safe = safe and MountainWorld.rectangle_hit(last,point,obstacle["pos"],obstacle["dimensions"]*.5+Vector2(.38,.48))<0
			if first_gap<0:
				first_gap = point.y-last.y
			elif absf((point.y-last.y)-first_gap)>.05:
				varying_gap = true
			last = point
		varied = varied and varying_gap
		world.free()
	print("GRIP_DENSITY v8=",new_grips," v7=",old_grips)
	check(new_grips<old_grips*.9,"100 mountains have at least ten percent fewer total grips than v7 including connective bridges")
	check(rare_permanent,"at least 78 percent of grips are disposable in every tested mountain")
	check(rare_ledges,"rest ledges stay rare instead of forming a permanent safety ladder")
	check(reachable,"100 complete mountains have rising base-rope distances including the final grip")
	check(stable,"100 mountains never force fragile or upgrade-gated grips on the primary path")
	check(safe,"100 mountains keep barriers clear of the primary corridor including player size")
	check(varied,"100 mountains vary vertical gaps rather than copy fixed rows")
	check(wide,"the first location populates left, centre and right across a three-screen world")
	check(connected,"all stable grips belong to the connected route network in 100 worlds")
	check(supported,"every hookable object has generated rock support, including openings")
	check(obstacle_count>100,"solid obstacles are actually generated across the test worlds")
	var masks: Array = []
	var holes := true
	for seed_number in [58273,101,410021,999999]:
		var world := make_world(seed_number,126)
		var mask: Array = []
		var void_count := 0
		for x in range(-14,15,2):
			for y in range(10,110,2):
				var solid := world.layout.rock_field(Vector2(x,y))>0
				mask.append(solid)
				if not solid: void_count += 1
		holes = holes and void_count>25
		masks.append(mask)
		check(world.outside_mountain(Vector2(22,50)) and not world.outside_mountain(Vector2(0,50)),"rock silhouette distinguishes exterior from internal holes without defining defeat, seed %d" % seed_number)
		world.free()
	check(holes,"the first location contains large internal voids across different seeds")
	var distinct := true
	for i in range(4):
		for j in range(i): distinct = distinct and masks[i]!=masks[j]
	check(distinct,"seeds change geometry and hole topology, not only materials")
	for biome in [1,2]:
		var world := make_world(58273,126,true,biome)
		var partial_legacy := make_world(58273,15,true,biome)
		partial_legacy.generate_to(126,true,120)
		check(world.layout is LegacyMountainLayout and MountainWorld.generation_version_for(biome)==4 and world.anchors[0]["shape"]=="rectangle","other location keeps generator v4 and old hook geometry: %d" % biome)
		check(signature(world)==signature(partial_legacy),"legacy location remains deterministic across generation requests: %d" % biome)
		partial_legacy.free()
		world.free()
	# Independent obstacle cases: ray blocking, swept body collision and sliding.
	var test_world := MountainWorld.new()
	test_world.visuals_enabled = false
	root.add_child(test_world)
	test_world.setup(7,0)
	test_world.add_obstacle(Vector2(0,10),Vector2(1,2))
	test_world.add_anchor(Vector2(3,10),0)
	var hit := test_world.cast_hook(Vector2(-3,10),Vector2(3,10),.32)
	check(hit.get("blocked",false),"a red barrier blocks a hook aimed at a grip behind it")
	var motion := test_world.move_player(Vector2(-3,10),Vector2(3,10),Vector2(18,0))
	check(motion["position"].x<-.87 and motion["velocity"].x==0,"fast movement cannot tunnel through a red barrier")
	motion = test_world.move_player(Vector2(-3,9.5),Vector2(2,10.5),Vector2(8,2))
	check(motion["position"].x<-.87 and motion["position"].y>10 and motion["velocity"].y==2,"collision preserves movement along the obstacle face")
	var clear := test_world.cast_hook(Vector2(-3,15),Vector2(3,15),.32)
	check(clear.is_empty(),"decorative cliff geometry is not a hookable surface")
	check(test_world.rope_blocked(Vector2(-3,10),Vector2(3,10)),"rope intersection uses the same solid obstacles as the hook")
	test_world.free()
	first.free()
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	DirAccess.make_dir_recursive_absolute(directory)
	var report := FileAccess.open(directory.path_join("generation-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"seeds":100},"\t"))
	report.close()
	print("GENERATION_TESTS ",checks," checks, ",failures.size()," failures; seeds=100")
	quit(0 if failures.is_empty() else 1)
