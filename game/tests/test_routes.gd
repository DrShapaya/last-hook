extends SceneTree

# Grip contracts and scenario routes: one GripSpec table for type, lifetime and
# role, the reworked mechanics, and v12 phrases audited as a directed graph.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("ROUTES FAILED: "+description)

func make_world(seed_number: int, version: int = 0, biome: int = 0, height: float = 126) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_number,biome,version)
	world.generate_to(height,true,120)
	return world

func signature(world: MountainWorld) -> Array:
	var result: Array = []
	for anchor in world.anchors:
		result.append([anchor["id"],anchor["pos"],anchor["kind"],anchor["permanent"],GripSpec.role(anchor),anchor.get("choice_exits",[])])
	for find in world.finds: result.append([find["item"],find["pos"]])
	result.append(world.route_edges.duplicate())
	return result

func run_tests() -> void:
	# --- The contract table ---------------------------------------------------
	var stone := {"kind":0,"permanent":false,"pos":Vector2.ZERO}
	var fixed_ice := {"kind":3,"permanent":true,"pos":Vector2.ZERO}
	var root_grip := {"kind":1,"permanent":false,"pos":Vector2.ZERO}
	check(GripSpec.type_of(stone)=="stable" and GripSpec.type_of(root_grip)=="timed" and GripSpec.type_of({"kind":2})=="spring" and GripSpec.type_of(fixed_ice)=="sliding" and GripSpec.type_of({"kind":4})=="crystal_choice","old numeric kinds 0-4 map to the five named types")
	check(GripSpec.lifetime(stone)=="disposable" and GripSpec.lifetime(fixed_ice)=="permanent" and GripSpec.lifetime({"kind":0,"reserve":true,"permanent":false})=="reserve","lifetime is read from the stored flags, separate from the type")
	check(GripSpec.role({"primary":true})=="main" and GripSpec.role({})=="auxiliary" and GripSpec.role({"reserve":true})=="recovery","grips from old saves without a role get one from their flags")
	var description := GripSpec.description(fixed_ice)
	check(description.contains("Скольз") and description.contains("постоян") and description.contains("скользит"),"a permanent ice grip still names its type and its lifetime: %s" % description)
	check(GripSpec.description(root_grip).contains("2,6 с"),"a root names its timer instead of a lifetime")
	check(not GripSpec.expired(root_grip,2.6) and GripSpec.expired(root_grip,2.61) and not GripSpec.expired(stone,99),"the root clock keeps the old 2.6 s and only roots expire")
	# Spring: same force as the old 1.13 multiplier along the exit, less off it.
	var spring := {"kind":2,"exit_dir":Vector2(1,1).normalized()}
	var along := Vector2(3,3)
	check(absf(GripSpec.release_velocity(spring,along).length()-along.length()*1.13)<.0001,"a release along the bough's exit keeps the former 1.13 speed")
	var across := Vector2(3,-3)
	check(GripSpec.release_velocity(spring,across)==across and GripSpec.release_velocity(stone,along)==along,"releasing against the exit or from another type adds no impulse")
	check(GripSpec.spring_load(spring,Vector2(5,0))>0 and GripSpec.spring_load(spring,Vector2(5,0))<1,"partial loading gives a partial bonus")
	# Ice: the same 1.2 m and .18 m/s, now along a local direction.
	var slanted := {"kind":3,"slide_dir":Vector2(.3,-1),"pos":Vector2(2,5)}
	check(GripSpec.slide_offset(slanted,100).length()<=GripSpec.ICE_SLIDE_MAX+.0001 and absf(GripSpec.slide_offset(slanted,1).length()-.18)<.0001 and GripSpec.slide_offset(slanted,1).x>0,"ice slides at the old rate and limit along its own downslope")
	check(GripSpec.slide_samples(slanted).size()==3 and GripSpec.slide_samples(stone).size()==1,"route checks sample every slide position of ice and one contact elsewhere")
	check(GripSpec.choice_exits({"kind":4,"choice_exits":[3,4]})==[3,4] and GripSpec.choice_exits({"kind":0,"choice_exits":[3]}).is_empty(),"only crystals carry choice exits; the crystal never changes physics")

	# --- World integration ----------------------------------------------------
	var timed_world := make_world(58273,0,1,140)
	var roots_ok := true
	var dial_rule := true
	for anchor in timed_world.anchors:
		if GripSpec.timed(anchor): roots_ok = roots_ok and not anchor["permanent"]
	check(roots_ok,"legacy locations no longer make timed roots permanent")
	check(timed_world.object_description({"kind":0,"permanent":true,"pos":Vector2(0,10)}).begins_with("Песчаник"),"a location's profile names its grips")
	timed_world.free()
	var ice_world := MountainWorld.new()
	ice_world.visuals_enabled = false
	root.add_child(ice_world)
	ice_world.setup(7,0)
	ice_world.add_anchor(Vector2(0,20),GripSpec.ICE,false,Vector2(1.3,.6))
	var ice: Dictionary = ice_world.anchors[-1]
	var contact := Vector2(0,20.3)
	var slid := ice_world.anchor_contact_after(ice,contact,100)
	var outline := ice_world.anchor_outline(ice)
	check(slid!=contact and (Geometry2D.is_point_in_polygon(slid,outline) or ice_world.anchor_surface_point(ice,slid)==slid),"held ice moves the hook but keeps it on the drawn grip")
	check(ice_world.anchor_contact_after({"kind":0,"pos":Vector2(0,20)},contact,100)==contact,"other types never move the contact")
	ice_world.free()

	# --- v12 scenario routes ----------------------------------------------------
	var first := make_world(58273)
	var partial := make_world(58273,0,0,20)
	partial.generate_to(64,true,120)
	partial.generate_to(126,true,120)
	check(signature(first)==signature(partial),"scenario routes are identical for any request size")
	var again := make_world(58273)
	check(signature(first)==signature(again),"the same seed recreates every scenario, type, role and choice exit")
	again.free()
	partial.free()
	var v11 := make_world(58273,11)
	var same_route := v11.main_route.size()==first.main_route.size()
	for row in range(mini(v11.main_route.size(),first.main_route.size())):
		same_route = same_route and v11.anchors[v11.main_route[row]]["pos"]==first.anchors[first.main_route[row]]["pos"]
	check(first.layout.scenario_routes and not v11.layout.scenario_routes and same_route,"v12 keeps the v11 main route geometry and only reassigns types; v11 saves keep their generator")
	v11.free()
	first.free()
	var problems: Array[String] = []
	var stats := {}
	var kinds_seen := {}
	var specials_on_branches := true
	var low_ice := true
	var low_crystal := true
	var permanent_ok := true
	var ledges_ok := true
	var choice_ok := true
	var choice_count := 0
	var new_per_phrase := true
	var streak_ok := true
	var intervals := {}
	for seed_number in range(100):
		var world := make_world(seed_number)
		var layout: EncounterLayout = world.layout
		var report := RouteGraph.audit(layout)
		for problem in report["problems"]:
			if problems.size()<12: problems.append("seed %d: %s" % [seed_number,problem])
		for key in report["stats"].keys(): stats[key] = int(stats.get(key,0))+int(report["stats"][key])
		var ordinary := 0
		var permanent := 0
		var main := {}
		for id in world.main_route: main[id] = true
		for anchor in world.anchors:
			if anchor.get("reserve",false): continue
			ordinary += 1
			if anchor["permanent"]: permanent += 1
			var kind := GripSpec.kind_of(anchor)
			kinds_seen[kind] = true
			var zone := clampi(int(anchor["pos"].y/20),0,5)
			if kind in [GripSpec.ROOT,GripSpec.ICE,GripSpec.CRYSTAL]: specials_on_branches = specials_on_branches and GripSpec.role(anchor)=="branch" and not main.has(anchor["id"])
			if kind==GripSpec.ICE: low_ice = low_ice and zone>=3
			if kind==GripSpec.CRYSTAL:
				low_crystal = low_crystal and zone>=3
				choice_count += 1
				var exits := GripSpec.choice_exits(anchor)
				choice_ok = choice_ok and exits.size()==2 and main.has(int(exits[1])) and GripSpec.role(world.anchors[int(exits[0])])=="reward"
		permanent_ok = permanent_ok and float(permanent)/ordinary<.22
		ledges_ok = ledges_ok and world.ledges.size()<=7
		var last := 0
		var streak := 0
		for row in range(world.main_route.size()):
			var grip: Dictionary = world.anchors[world.main_route[row]]
			if grip["permanent"]:
				if row>0: intervals[row-last] = true
				last = row
				streak = 0
			else:
				streak += 1
				streak_ok = streak_ok and streak<=EncounterLayout.RECOVERY_STREAK+1
		var fresh_blocks := {}
		for plan in layout.scenarios.values():
			if plan["new"] and plan["placed"]:
				new_per_phrase = new_per_phrase and not fresh_blocks.has(plan["block"])
				fresh_blocks[plan["block"]] = true
		world.free()
	print("ROUTE_SCENARIOS ",stats)
	check(problems.is_empty(),"100 v12 mountains pass the directed route audit: %s" % str(problems))
	check(kinds_seen.size()==5 and choice_count>40,"all five grip types appear, crystals as real forks (%d)" % choice_count)
	check(specials_on_branches,"roots, ice and crystals stand only on optional branches, never on the main line")
	check(low_ice and low_crystal,"ice and crystal forks wait for the upper zones")
	check(choice_ok,"every crystal offers a reward exit and the next main grip")
	check(permanent_ok and ledges_ok,"permanent grips stay under 22 percent and rest ledges at most seven")
	check(streak_ok and intervals.size()>3,"recovery breaks long disposable series without a fixed interval (%s)" % str(intervals.keys()))
	check(new_per_phrase,"a phrase introduces at most one new mechanic")
	check(int(stats.get("risk",0))>100 and int(stats.get("energy",0))>100 and int(stats.get("slide",0))>40 and int(stats.get("choice",0))>40,"every scenario is actually generated: %s" % str(stats))
	print("ROUTE_TESTS %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
