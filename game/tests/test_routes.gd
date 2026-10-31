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

# A one-branch layout: a disposable entry under a 1.3 x 0.6 m ice grip that
# slides left and down, with one candidate exit.
func ice_branch_layout(exit_pos: Vector2, current: bool = true) -> MountainLayout:
	var layout: MountainLayout = ExpeditionLayout.new() if current else MountainLayout.new()
	layout.anchors.append({"id":0,"kind":GripSpec.STONE,"pos":Vector2(0,15),"dimensions":Vector2(1.8,.65),"permanent":false,"primary":true,"broken":false})
	layout.anchors.append({"id":1,"kind":GripSpec.ICE,"pos":Vector2(0,20),"dimensions":Vector2(1.3,.6),"slide_dir":Vector2(-.943858,-.33035),"permanent":false,"role":"branch","broken":false})
	layout.main_route.append(0)
	layout.branches.append({"entry":0,"anchor":1,"entry_consumed":true,"exit_row":-1,"exit_pos":exit_pos,"candidate_exits":[{"pos":exit_pos,"kind":"main"}]})
	return layout

# True when the audit of the current generator flags the ice exit.
func ice_exit_flagged(exit_pos: Vector2) -> bool:
	for problem in RouteGraph.audit(ice_branch_layout(exit_pos))["problems"]:
		if str(problem).contains("has no main exit"): return true
	return false

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
	# Spring: a fixed throw straight up, whatever speed the swing brought and
	# wherever the route goes on: a sideways throw leaves the mountain.
	var spring := {"kind":2,"exit_dir":Vector2(1,1).normalized()}
	var along := Vector2(3,3)
	check(GripSpec.release_velocity(spring,Vector2.ZERO)==Vector2(0,GripSpec.SPRING_THROW),"a spring throws a hero hanging still straight up at full force")
	check(GripSpec.release_velocity(spring,-along).y>=GripSpec.SPRING_THROW-.0001,"a release on the way down is still thrown up")
	check(absf(GripSpec.release_velocity(spring,Vector2(0,GripSpec.SPRING_FULL_SWING)).y-GripSpec.SPRING_THROW*(1+GripSpec.SPRING_TIMING))<.0001,"a full swing upwards adds the timing bonus")
	var fast := Vector2(0,GripSpec.SPRING_THROW*(1+GripSpec.SPRING_TIMING)+2)
	check(GripSpec.release_velocity(spring,fast)==fast,"a throw never slows a faster rise")
	var sideways: Vector2 = GripSpec.release_velocity(spring,Vector2(8,0))
	check(absf(sideways.x)<=2.0+.0001 and sideways.y>=GripSpec.SPRING_THROW and GripSpec.release_velocity(stone,along)==along,"a throw takes most of the sideways speed and other types add no impulse")
	check(GripSpec.spring_load(spring,Vector2(0,GripSpec.SPRING_FULL_SWING*.25))<GripSpec.spring_load(spring,Vector2(0,GripSpec.SPRING_FULL_SWING)) and GripSpec.spring_load(spring,Vector2(GripSpec.SPRING_FULL_SWING,0))==0,"only a rising swing loads the spring, a slow one in part")
	check(GripSpec.exit_direction({"kind":2}).y>0,"a spring without a stored exit throws up the mountain")
	# Ice: starts at .18 m/s, accelerates, never past 1.2 m, along a local direction.
	var slanted := {"kind":3,"slide_dir":Vector2(.3,-1),"pos":Vector2(2,5)}
	check(GripSpec.slide_offset(slanted,100).length()<=GripSpec.ICE_SLIDE_MAX+.0001 and absf(GripSpec.slide_distance(slanted,1)-(.18+.5*GripSpec.ICE_SLIDE_ACCEL))<.0001 and GripSpec.slide_offset(slanted,1).x>0,"ice accelerates from the old rate up to the old limit along its own downslope")
	check(GripSpec.slide_distance(slanted,.5)<GripSpec.slide_distance(slanted,1)-GripSpec.slide_distance(slanted,.5),"the slide speeds up the longer the hero holds on")
	check(GripSpec.release_velocity(slanted,Vector2(1,2),Vector2(.8,-.2))==Vector2(1,2)+Vector2(.8,-.2)*GripSpec.ICE_CARRY and GripSpec.release_velocity(stone,Vector2(1,2),Vector2(.8,-.2))==Vector2(1,2),"releasing a sliding ice contact carries the slide into the flight; no other type does")
	check(GripSpec.lateral_slide(-1).x<0 and GripSpec.lateral_slide(1).x>0 and GripSpec.lateral_slide(1).y<0,"v13 ice slides across its grip and slightly downhill")
	check(GripSpec.slide_samples(slanted).size()==3 and GripSpec.slide_samples(stone).size()==1,"route checks sample every slide position of ice and one contact elsewhere")
	check(GripSpec.choice_exits({"kind":4,"choice_exits":[3,4]})==[3,4] and GripSpec.choice_exits({"kind":0,"choice_exits":[3]}).is_empty(),"only crystals carry choice exits; the crystal never changes physics")
	# State contract: available -> attached -> acted -> consumed | available.
	var held := {"id":4,"kind":2,"permanent":false,"broken":false}
	check(GripSpec.state(held)=="available" and GripSpec.state(held,4)=="targeted" and GripSpec.state(held,5)=="available","a free grip is available, and targeted only while aimed at")
	check(GripSpec.attach(held) and not GripSpec.attach(held) and GripSpec.state(held)=="attached","a second hit on a held grip changes nothing")
	check(GripSpec.act(held) and not GripSpec.act(held) and GripSpec.state(held)=="acted","the release effect fires once per catch")
	check(GripSpec.settle(held) and not GripSpec.settle(held) and held["broken"] and GripSpec.state(held)=="consumed","a disposable grip is consumed exactly once")
	check(not GripSpec.attach(held) and not GripSpec.act(held),"a consumed grip can be neither caught nor acted on")
	var anchor_ring := {"id":5,"kind":0,"permanent":true,"broken":false}
	GripSpec.attach(anchor_ring)
	GripSpec.act(anchor_ring)
	check(not GripSpec.settle(anchor_ring) and GripSpec.state(anchor_ring)=="available" and GripSpec.attach(anchor_ring),"a permanent grip is not consumed by a release and can be caught again")
	var fixed_root := {"id":6,"kind":1,"permanent":true,"broken":false}
	GripSpec.attach(fixed_root)
	check(GripSpec.expire(fixed_root) and not GripSpec.expire(fixed_root) and not GripSpec.act(fixed_root),"a root clock ends the grip whatever its lifetime, once, and leaves no release effect")
	var resumed := {"id":7,"kind":3,"permanent":false,"broken":false}
	GripSpec.restore(resumed,true)
	check(GripSpec.state(resumed)=="attached" and GripSpec.act(resumed),"a grip held at save time is attached again after loading")
	var spent := {"id":8,"kind":0,"permanent":false,"broken":true}
	GripSpec.restore(spent,false)
	check(GripSpec.state(spent)=="consumed" and not GripSpec.attach(spent),"a consumed grip stays consumed after loading")

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
	# The plate leans along its slide, low end first, and a hook caught from
	# below runs down its lower edge to that end.
	var slope := GripSpec.slide_direction(ice)
	var high_end := Vector2(INF,0)
	var low_end := Vector2(-INF,0)
	for point in outline:
		if point.dot(slope)<high_end.dot(slope) or not high_end.is_finite(): high_end = point
		if point.dot(slope)>low_end.dot(slope) or not low_end.is_finite(): low_end = point
	check(GripSpec.plate(ice) and low_end.y<high_end.y-.3,"an ice plate leans down towards the end the hook slides to")
	var under := ice_world.anchor_surface_point(ice,Vector2(0,18.5),Vector2(0,1))
	var walk_ok := true
	var previous_contact := under
	var travelled := 0.0
	var slip_at := -1.0
	for frame in range(1,361):
		var moment := frame/120.0
		var now := ice_world.anchor_contact_after(ice,under,moment)
		walk_ok = walk_ok and now.distance_to(previous_contact)<.05 and (now-previous_contact).dot(slope)>=-.0001
		travelled += now.distance_to(previous_contact)
		previous_contact = now
		if slip_at<0 and GripSpec.slipped(ice,under,moment): slip_at = moment
	check(walk_ok and travelled>.3,"ice walks the hook continuously down the plate (%.2f m)" % travelled)
	check(absf(slip_at-GripSpec.seconds_to_slip(ice,under))<.02 and slip_at>GripSpec.ICE_GRACE,"the hook slips off the low end when the plate runs out (%.2f s)" % slip_at)
	var near_high := ice_world.anchor_surface_point(ice,under-slope*.35,Vector2(0,1))
	var near_low := ice_world.anchor_surface_point(ice,under+slope*.35,Vector2(0,1))
	check(GripSpec.seconds_to_slip(ice,near_high)>GripSpec.seconds_to_slip(ice,near_low)+.15,"a catch near the high end buys more time than one near the low end")
	check(GripSpec.seconds_to_slip(ice,low_end)>=GripSpec.ICE_GRACE,"even the very end of the plate holds the hook for a moment")
	check(ice_world.anchor_contact_after(ice,contact,100).distance_to(ice_world.anchor_contact_after(ice,under,100))<.01,"a hook that lands on top still ends at the low end of the plate")
	check(ice_world.cast_hook(low_end+Vector2(0,-3),low_end+Vector2(0,.05),.34).get("object",{}).get("id",-1)==ice["id"],"the hook catches the plate where it is drawn, on its low end")
	check(not GripSpec.slipped({"kind":0,"pos":Vector2(0,20)},contact,100),"other types never slip")
	check(ice_world.anchor_contact_after({"kind":0,"pos":Vector2(0,20)},contact,100)==contact,"other types never move the contact")
	ice_world.free()
	# The route audit judges an ice exit from the contacts the slide really
	# produces on the stone, not from points past its edge.
	var past_edge_only := Vector2(4.0,21.5)
	check(not ice_exit_flagged(past_edge_only),"an ice exit reachable from every real contact passes even if the straight slide line leaves the stone")
	var far_corner_blocked := Vector2(-4.9,19.0)
	check(ice_exit_flagged(far_corner_blocked),"an ice exit out of reach from a corner the hook can really hold is reported")
	var legacy_audit := RouteGraph.audit(ice_branch_layout(far_corner_blocked,false))
	check(legacy_audit["problems"].is_empty() and int(legacy_audit["stats"].get("legacy_ice_exit",0))==1,"a frozen generator keeps its own check; the real-slide gap is only counted")

	# --- v12/v13 scenario routes ------------------------------------------------
	# New attempts climb the expeditions (v14, test_levels); v13 stays the
	# generator of saved first-location attempts and keeps its whole contract.
	var first := make_world(58273,13)
	var partial := make_world(58273,13,0,20)
	partial.generate_to(64,true,120)
	partial.generate_to(126,true,120)
	check(signature(first)==signature(partial),"scenario routes are identical for any request size")
	var again := make_world(58273,13)
	check(signature(first)==signature(again),"the same seed recreates every scenario, type, role and choice exit")
	again.free()
	partial.free()
	# Saved v12 attempts regenerate exactly as before the v13 calibration.
	var v12_parts: Array = []
	for seed_number in range(25):
		var old := make_world(seed_number,12)
		for a in old.anchors: v12_parts.append([a["id"],a["pos"],a["kind"],a["permanent"],GripSpec.role(a),a.get("choice_exits",[]),a.get("exit_dir",Vector2.ZERO)])
		for f in old.finds: v12_parts.append([f["pos"],f["item"]["value"]])
		v12_parts.append(old.route_edges.size())
		v12_parts.append(old.obstacles.size())
		old.free()
	check(str(v12_parts).md5_text()=="1f6ad2a03c2b291e3a9cb95b1d8752ed","v12 attempts regenerate unchanged under v13")
	var v11 := make_world(58273,11)
	var same_route := v11.main_route.size()==first.main_route.size()
	for row in range(mini(v11.main_route.size(),first.main_route.size())):
		same_route = same_route and v11.anchors[v11.main_route[row]]["pos"]==first.anchors[first.main_route[row]]["pos"]
	check(first.layout.scenario_routes and first.layout.calibrated_routes and not v11.layout.scenario_routes and same_route,"v13 keeps the v11 main route geometry and only reassigns types; v11 saves keep their generator")
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
	var records_ok := true
	var repeats := 0
	var auxiliary_springs := 0
	var lateral_ice := true
	for seed_number in range(100):
		var world := make_world(seed_number,13)
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
		for branch in layout.branches:
			records_ok = records_ok and branch.has_all(["entry","entry_consumed","candidate_exits","safe_exit","risky_exit","reward_exit","exit_row","hazard_state"])
			records_ok = records_ok and (branch["reward_exit"]>=0)==(branch["hazard_state"]=="choice")
			if branch.get("repeat",false): repeats += 1
		for anchor in world.anchors:
			if GripSpec.kind_of(anchor)==GripSpec.SPRING and GripSpec.role(anchor)=="auxiliary": auxiliary_springs += 1
			if GripSpec.kind_of(anchor)==GripSpec.ICE: lateral_ice = lateral_ice and absf(GripSpec.slide_direction(anchor).x)>.9
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
	check(records_ok,"every branch stores entry, consumed entry, candidate exits, safe/risky/reward exit, exit row and hazard")
	check(repeats>50 and auxiliary_springs>200,"v13 repeats known risks on second detours (%d) and puts springs among auxiliary grips (%d)" % [repeats,auxiliary_springs])
	check(lateral_ice,"v13 ice slides across its grip")
	check(int(stats.get("risk",0))>100 and int(stats.get("energy",0))>100 and int(stats.get("slide",0))>40 and int(stats.get("choice",0))>40,"every scenario is actually generated: %s" % str(stats))
	print("ROUTE_TESTS %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
