extends SceneTree

# Three expeditions, nine acts (generator v14): level contract, act context,
# act seed streams, topology of every act, hazards and their exits, contract
# variants, real base-kit traversal and the old generators kept for saves.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("LEVELS FAILED: "+description)

func make_world(seed_number: int, location: int, version: int = 0, height: float = -1.0, finite: bool = true) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_number,location,version)
	var total := float(LevelCatalog.level(location)["height_units"])
	world.generate_to(total+6 if height<0 else height,finite,total)
	return world

func fingerprint(version: int, location: int) -> String:
	var parts: Array = []
	for seed_number in range(25):
		var world := MountainWorld.new()
		world.visuals_enabled = false
		root.add_child(world)
		world.setup(seed_number,location,version)
		world.generate_to(126,true,120)
		for a in world.anchors: parts.append([a["id"],a["pos"],a["kind"],a["permanent"],GripSpec.role(a),a.get("choice_exits",[]),a.get("exit_dir",Vector2.ZERO)])
		for f in world.finds: parts.append([f["pos"],f["item"]["value"]])
		parts.append(world.route_edges.size())
		parts.append(world.obstacles.size())
		world.free()
	return str(parts).md5_text()

# Positions, types and lifetimes of the grips of one act, without ids.
func act_signature(world: MountainWorld, act: int) -> Array:
	var result: Array = []
	for a in world.anchors:
		if int(a.get("act",-1))==act: result.append([a["pos"],a["kind"],a["permanent"],GripSpec.role(a)])
	for h in world.layout.hazards:
		if int(h["act"])==act: result.append([h["def"],h.get("rect",Rect2()),h.get("pos",Vector2.ZERO),h.get("x",0.0)])
	for l in world.ledges:
		if int(l.get("act",-1))==act: result.append([l["left"],l["right"],l["top"]])
	return result

func traverse(game, route: Array) -> int:
	var reached := 1
	for target_id in route.slice(1):
		var target: Vector2 = game.world.anchor_by_id(target_id)["pos"]
		for frame in range(2400):
			if game.state!="play": return reached
			if game.sim.attached:
				game.reel = 1
				game.pump = signf(game.sim.vel.x) if absf(game.sim.vel.x)>.1 else signf(target.x-game.sim.anchor.x)
				var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
				var ignored: int = game.anchor_id if not current.get("permanent",true) else -1
				var sight: Dictionary = game.world.cast_hook(game.sim.pos,target,game.model.hook_radius(),ignored)
				var toward: Vector2 = (target-game.sim.pos).normalized()
				var timed_exit: bool = int(current.get("kind",0))==1
				# A careful player waits out a storm on the grip it holds.
				var calm: bool = game.world.hazards.calm_for(game.sim.pos,game.hazard_clock,1.6) and game.world.hazards.calm_for(target,game.hazard_clock,1.6)
				if calm and int(sight.get("object",{}).get("id",-1))==target_id and game.sim.pos.distance_to(target)<5.2 and game.shot_window_open(target) and (game.sim.vel.dot(toward)>.5 or timed_exit):
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
			print("LEVELS_STUCK target=%d at %s hero=%s attached=%s state=%s" % [target_id,target,game.sim.pos,game.sim.attached,game.debug_state()])
			return reached
	return reached

# The whole main line as a player climbs it: after a miss that catches a
# lower grip, carry on from the first main grip above it (counted).
var recoveries := 0

func climb(game, route: Array) -> int:
	var index := 1
	var guard := 0
	while index<route.size() and guard<route.size()+8:
		guard += 1
		var reached := traverse(game,[route[index-1],route[index]])
		if reached==2:
			index += 1
			continue
		if game.state!="play" or not game.sim.attached: return index
		var held: Vector2 = game.world.anchor_by_id(game.anchor_id)["pos"]
		var next := index
		for row in range(route.size()):
			if game.world.anchor_by_id(route[row])["pos"].y>held.y+.5:
				next = row
				break
		if next<=0 or next==index and game.anchor_id!=route[index-1]: return index
		recoveries += 1
		index = next
		route = route.duplicate()
		route[index-1] = game.anchor_id
	return index

func hold_at(game, grip: Dictionary) -> void:
	game.sim = RopeSim.new()
	game._configure_rope()
	game.sim.pos = grip["pos"]+Vector2(0,-2.8)
	game.sim.vel = Vector2.ZERO
	game.sim.attach(grip["pos"],game.model.shot_range())
	game.anchor_id = grip["id"]
	game.anchor_contact = grip["pos"]
	game.anchor_time = 0
	game.run_seconds = 0.0
	game.hazard_clock = 0.0
	game.camera_y = grip["pos"].y+2.5
	game.state = "play"

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	# --- L1: the level contract ------------------------------------------------------
	var contract_ok := LevelCatalog.LEVELS.size()==3
	var act_fields := ["display_name","share","biome_profile","intro_rule","route_patterns","allowed_grips","hazards","landmarks","safe_route_rules","risky_route_rules","objectives","silhouette","variants","reward_tag","contract_tag"]
	var all_acts := {}
	for location in range(3):
		var level := LevelCatalog.level(location)
		contract_ok = contract_ok and level["id"]==balance["locations"][location]["id"] and int(level["location_slot"])==location
		contract_ok = contract_ok and float(level["height_units"])==float(balance["locations"][location]["height_units"]) and level["acts"].size()==3
		contract_ok = contract_ok and str(balance["locations"][location]["name"])==str(level["display_name"])
		var spans := LevelCatalog.act_spans(location)
		contract_ok = contract_ok and float(spans[0]["y_start"])==0.0 and float(spans[-1]["y_end"])==float(level["height_units"])
		for index in range(spans.size()):
			if index>0: contract_ok = contract_ok and float(spans[index]["y_start"])==float(spans[index-1]["y_end"])
			var definition := LevelCatalog.act(spans[index]["id"])
			all_acts[spans[index]["id"]] = location
			for field in act_fields: contract_ok = contract_ok and definition.has(field)
			contract_ok = contract_ok and str(definition["route_patterns"][0]["beat"])=="start" and str(definition["route_patterns"][-1]["beat"])=="exit"
			for hazard_id in definition["hazards"]: contract_ok = contract_ok and not LevelCatalog.hazard(hazard_id).is_empty()
	check(contract_ok and all_acts.size()==9,"three levels keep the old save ids and heights, nine acts cover each level without gaps")
	var hazard_fields := ["telegraph_time","active_time","collision","damage","affected_edges","safe_exit_tags","kind","telegraph"]
	var hazards_ok := true
	for hazard_id in LevelCatalog.HAZARDS.keys():
		for field in hazard_fields: hazards_ok = hazards_ok and LevelCatalog.HAZARDS[hazard_id].has(field)
		hazards_ok = hazards_ok and not str(LevelCatalog.HAZARDS[hazard_id]["telegraph"]).is_empty()
	check(hazards_ok,"every HazardDefinition has telegraph, timing, collision, damage, edges and safe exits")
	check(LevelCatalog.act_names(0)==["Лесная корневая стена","Ветровой траверс","Старый пост"] and LevelCatalog.act_names(1)==["Сухой каньон","Погребённый караван","Обсерватория пыльной бури"] and LevelCatalog.act_names(2)==["Белая седловина","Синяя трещина","Расколотая корона"],"the nine acts are the three expeditions in climbing order")
	# --- L1: generator choice and act context -----------------------------------------
	for location in range(3):
		var world := make_world(58273,location)
		check(world.layout is ExpeditionLayout and world.generation_version==15 and MountainWorld.generation_version_for(location)==15,"location %d starts new attempts on the expedition generator" % location)
		var shapes_ok := true
		for a in world.anchors: shapes_ok = shapes_ok and a.get("shape","polygon")!="rectangle"
		check(shapes_ok,"location %d grips use the shared polygon contract, no legacy rectangles" % location)
		var context_ok := true
		for span in LevelCatalog.act_spans(location):
			var middle := (float(span["y_start"])+float(span["y_end"]))*.5
			var act := world.act_at(middle)
			context_ok = context_ok and act["id"]==span["id"] and int(act["local"])==int(span["index"]) and world.layout.profile_id_at(middle)==LevelCatalog.act(span["id"])["biome_profile"]
			var state := world.debug_state(Vector2(0,middle))
			context_ok = context_ok and state["act_id"]==span["id"] and state["layout"]=="ExpeditionLayout" and state["level_id"]==LevelCatalog.level(location)["id"]
		check(context_ok,"location %d: the act at every height is in the debug state with its profile" % location)
		world.free()
	var shown := MountainWorld.new()
	root.add_child(shown)
	shown.setup(58273,1)
	shown.generate_to(30,true,140)
	check(shown.visuals is MassifVisuals and not shown.visuals is LegacyMountainVisuals,"a new attempt never switches to the legacy visuals")
	shown.free()
	# Saved attempts of older generators regenerate exactly as before.
	check(fingerprint(13,0)=="9a91ac02e4809532e93a4cb26d38c299","saved v13 attempts on the first location regenerate unchanged")
	check(fingerprint(4,1)=="91bb5b4fc0436903db35c0c7b384f27c" and fingerprint(4,2)=="958c4bbc6242d0b1058311684049ebc8","saved v4 attempts on locations 1 and 2 regenerate unchanged")
	var old := make_world(7,1,4,60)
	check(old.layout is LegacyMountainLayout and MountainWorld.resumable(4,1) and MountainWorld.resumable(13,0) and not MountainWorld.resumable(4,0) and not MountainWorld.resumable(13,1) and MountainWorld.resumable(14,2),"only saved attempts keep their old generator")
	old.free()
	# --- Determinism and act seed streams ---------------------------------------------
	for location in range(3):
		var first := make_world(4242,location)
		var again := make_world(4242,location)
		var partial := make_world(4242,location,0,30)
		partial.generate_to(90,true,float(LevelCatalog.level(location)["height_units"]))
		partial.generate_to(float(LevelCatalog.level(location)["height_units"])+6,true,float(LevelCatalog.level(location)["height_units"]))
		var same := true
		for act in range(3): same = same and act_signature(first,act)==act_signature(again,act) and act_signature(first,act)==act_signature(partial,act)
		check(same and first.anchors.size()==partial.anchors.size(),"location %d: one seed is one route for any request size" % location)
		for world in [first,again,partial]: world.free()
	var independent := true
	var variants_differ := false
	for location in range(3):
		for changed in range(3):
			var signatures: Array = []
			for variant in range(3):
				var world := MountainWorld.new()
				world.visuals_enabled = false
				root.add_child(world)
				world.setup(777,location)
				(world.layout as ExpeditionLayout).variant_override = {changed:variant}
				world.generate_to(float(LevelCatalog.level(location)["height_units"])+6,true,float(LevelCatalog.level(location)["height_units"]))
				var acts: Array = []
				for act in range(3): acts.append(act_signature(world,act))
				signatures.append(acts)
				world.free()
			for act in range(3):
				if act==changed: variants_differ = variants_differ or signatures[0][act]!=signatures[1][act] or signatures[0][act]!=signatures[2][act]
				else: independent = independent and signatures[0][act]==signatures[1][act] and signatures[0][act]==signatures[2][act]
	check(independent,"a contract variant of one act never moves a grip, shelf or hazard of another act")
	check(variants_differ,"contract variants change the act they belong to")
	# --- L2-L5: topology of every act, audit, hazards ------------------------------------
	var rope := float(MountainLayout.base_kit()["rope"])
	var audit_ok := true
	var topology := {"start":true,"exit":true,"alternative":true,"recovery":true}
	var tags := {}
	var hazard_clear := true
	var hazard_exit := true
	var crowded_mix := true
	var forms_ok := true
	var bridges := 0
	for location in range(3):
		var total := float(LevelCatalog.level(location)["height_units"])
		for seed_number in range(30):
			var world := make_world(seed_number*131+7,location)
			var layout: ExpeditionLayout = world.layout
			var audit := RouteGraph.audit(layout)
			if not audit["problems"].is_empty():
				audit_ok = false
				print("LEVELS_AUDIT location=%d seed=%d %s" % [location,seed_number*131+7,audit["problems"].slice(0,3)])
			for act in range(3):
				var span := layout.span(act)
				var start_row := int(layout.act_plans[act]["first_row"])
				var start: Dictionary = world.anchors[world.main_route[start_row]]
				var shelf := act==0
				for ledge in world.ledges: shelf = shelf or (int(ledge.get("act",-1))==act and ledge.get("role","")=="start")
				topology["start"] = topology["start"] and start["permanent"] and shelf
				# The main exit: the act's last grip leads into the next act (or the summit).
				var last_row := start_row+int(layout.act_plans[act]["counts"].reduce(func(a,b): return a+b))-1
				var next: Vector2 = world.anchors[world.main_route[mini(last_row+1,world.main_route.size()-1)]]["pos"]
				var last: Vector2 = world.anchors[world.main_route[last_row]]["pos"]
				topology["exit"] = topology["exit"] and next.y>last.y and last.distance_to(next)<=rope and layout.transition_clear(last,next)
				var alternative := false
				for branch in layout.branches:
					if int(branch.get("act",-1))==act:
						alternative = true
						tags[branch["route_tag"]] = int(tags.get(branch["route_tag"],0))+1
				topology["alternative"] = topology["alternative"] and alternative
				var rest := false
				for ledge in world.ledges:
					if int(ledge.get("act",-1))==act and ledge.get("role","")=="rest" and world.anchors[world.main_route[int(ledge["anchor_row"])]]["permanent"]: rest = true
				topology["recovery"] = topology["recovery"] and rest
				var forms: Array = span["def"]["silhouette"]
				for region in range(int(float(span["y_start"])/MassifLayout.REGION_HEIGHT)+1,int(float(span["y_end"])/MassifLayout.REGION_HEIGHT)):
					var form := layout.landform(region)
					if int(form["act"])==act: forms_ok = forms_ok and forms.has(form["name"])
			# Hazards keep off the main transfers and off every branch exit.
			var lanes: Array = []
			for row in range(1,world.main_route.size()): lanes.append([world.anchors[world.main_route[row-1]]["pos"],world.anchors[world.main_route[row]]["pos"]])
			for hazard in layout.hazards:
				match str(hazard["kind"]):
					"field":
						if not bool(hazard["affects_main"]):
							for lane in lanes: hazard_clear = hazard_clear and not ExpeditionLayout.lane_hits_rect(lane[0],lane[1],hazard["rect"])
						else: hazard_clear = hazard_clear and LevelCatalog.hazard(hazard["def"])["affected_edges"]=="main_cyclic" and not is_inf(float(hazard["active_time"]))
					"contact":
						for lane in lanes: hazard_clear = hazard_clear and not ExpeditionLayout.lane_near_point(lane[0],lane[1],hazard["pos"],float(hazard["radius"])+1.0,ExpeditionLayout.SWING_DROPS)
					"falling":
						for lane in lanes: hazard_clear = hazard_clear and not ExpeditionLayout.lane_near_line(lane[0],lane[1],Vector2(hazard["x"],hazard["top"]),Vector2(hazard["x"],hazard["bottom"]),float(hazard["radius"])+1.0,ExpeditionLayout.SWING_DROPS)
					"collapse":
						bridges += 1
						var reveal := world.anchor_by_id(int(hazard["reveal"]))
						var rest_grip: Dictionary = world.anchors[world.main_route[int(world.ledges[int(hazard["ledge"])]["anchor_row"])]]
						hazard_exit = hazard_exit and reveal["broken"] and reveal["permanent"] and rest_grip["permanent"] and reveal["pos"].distance_to(world.anchors[world.main_route[int(world.ledges[int(hazard["ledge"])]["anchor_row"])+1]]["pos"])<MountainLayout.LINK_REACH
				if hazard.has("branch_anchor") and int(hazard["branch_anchor"])>=0:
					for branch in layout.branches:
						if int(branch["anchor"])!=int(hazard["branch_anchor"]): continue
						var grip: Vector2 = world.anchors[branch["anchor"]]["pos"]
						if hazard.has("pos"): hazard_exit = hazard_exit and not ExpeditionLayout.lane_near_point(grip,branch["exit_pos"],hazard["pos"],float(hazard["radius"])+.3)
						if hazard.has("x"): hazard_exit = hazard_exit and not ExpeditionLayout.lane_near_line(grip,branch["exit_pos"],Vector2(hazard["x"],hazard["top"]),Vector2(hazard["x"],hazard["bottom"]),float(hazard["radius"]))
				# Never two different hazards on one small spot.
				for other in layout.hazards:
					if int(other["id"])<=int(hazard["id"]) or other["def"]==hazard["def"]: continue
					var a := HazardVisuals.hazard_y(hazard,world.ledges)
					var b := HazardVisuals.hazard_y(other,world.ledges)
					if absf(a-b)<2.0 and not bool(hazard.get("affects_main",false)) and not bool(other.get("affects_main",false)) and other.get("branch_anchor",-1)!=hazard.get("branch_anchor",-2): crowded_mix = false
			world.free()
	check(audit_ok,"RouteGraph audit has no problems on 90 expeditions of v14")
	check(topology["start"],"every act starts on a permanent grip above its own safe shelf")
	check(topology["exit"],"every act has a main exit into the next act or the summit")
	check(topology["alternative"],"every act has an alternative exit: a risky, speed, collection or choice branch")
	check(topology["recovery"],"every act has a recovery shelf under a permanent grip")
	check(forms_ok,"every act carves its own silhouette forms")
	check(tags.has("risky_shortcut") and tags.has("collection") and tags.has("choice") and tags.get("speed",0)+tags.get("risky_shortcut",0)>0,"route tags cover risky shortcuts, collections and choices (%s)" % str(tags))
	check(hazard_clear,"hazards never cross a main transfer; only a cyclic storm covers the main path")
	check(hazard_exit and bridges>0,"no hazard sits on a branch exit; every sand bridge reveals a permanent exit beside a permanent rest")
	check(crowded_mix,"two different hazards never share one small spot")
	# Each expedition differs in shape, material, objects and rules.
	var distinct := true
	for location in range(3):
		var ids: Array = LevelCatalog.level(location)["acts"]
		for i in range(3):
			for j in range(i):
				var a := LevelCatalog.act(ids[i])
				var b := LevelCatalog.act(ids[j])
				distinct = distinct and a["biome_profile"]!=b["biome_profile"] and a["silhouette"]!=b["silhouette"] and a["landmarks"]!=b["landmarks"] and a["intro_rule"]!=b["intro_rule"]
	var families := [GripBiomeProfile.data_of("forest"),GripBiomeProfile.data_of("desert"),GripBiomeProfile.data_of("snow")]
	distinct = distinct and families[0]["rock_material"]["base_color"]!=families[1]["rock_material"]["base_color"] and families[1]["vegetation_set"]["dry"] and not families[2]["vegetation_set"]["grass"]
	for id in GripBiomeProfile.ACT_IDS: distinct = distinct and GripBiomeProfile.named(id).id==id
	check(distinct,"acts of one expedition differ in profile, silhouette, landmarks and rule; forest, desert and ice differ in material")
	# --- Hazard runtime ---------------------------------------------------------------
	var storm_world := make_world(58273,1)
	var storm: Dictionary = {}
	for hazard in storm_world.layout.hazards:
		if hazard["def"]=="storm_cycle": storm = hazard
	var directions := {}
	var phases := {}
	for step in range(200):
		var time := step*.1
		var effect: Dictionary = storm_world.hazards.step(time,(storm["rect"] as Rect2).get_center(),false)
		phases[storm_world.hazards.phase(storm,time)["name"]] = true
		if (effect["force"] as Vector2).length()>.01: directions[signf(effect["force"].x)] = true
	check(phases.has("calm") and phases.has("telegraph") and phases.has("active") and directions.size()==1,"a storm cycles calm, telegraph and storm, and never turns after it starts")
	check(HazardVisuals.HAZE_CLEAR>rope+1.0,"storm haze never veils a grip within the base rope")
	storm_world.free()
	# --- Real runs: menu, hazards, bot traversal ------------------------------------------
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["locations"] = [0,1,2]
	var launched := true
	for location in range(3):
		game.lobby_location = location
		game.selected_location = location
		game.model.profile["selected_location"] = location
		game.start_run(false)
		launched = launched and game.state=="play" and game.world.layout is ExpeditionLayout and game.world.location==location and game.debug_state()["act_index"]==0
		game.model.profile["active"] = {}
		game.state = "menu"
	check(launched,"all three location slots start a run on their expedition from the menu")
	# A cactus knocks the hook off through the ordinary release.
	game.selected_location = 1
	game.start_run(false)
	var cactus_world: Dictionary = {}
	for seed_number in range(20):
		game._create_world(900+seed_number,1,146)
		for hazard in game.world.layout.hazards:
			if hazard["def"]=="cactus": cactus_world = hazard
		if not cactus_world.is_empty(): break
	if not cactus_world.is_empty():
		var grip: Dictionary = game.world.anchor_by_id(int(cactus_world["branch_anchor"]))
		hold_at(game,grip)
		game.sim.pos = cactus_world["pos"]
		game.sim.vel = Vector2.ZERO
		game._physics_process(1.0/120)
		check(not game.sim.attached and game.hazard_cooldown>0,"a large cactus knocks the hero off its grip")
	else: check(false,"a desert seed places a cactus")
	# A sand bridge collapses once, reveals its exit and stays collapsed after a reload.
	var bridge: Dictionary = {}
	var bridge_seed := 0
	for seed_number in range(20):
		bridge_seed = 1300+seed_number
		game._create_world(bridge_seed,1,146)
		for hazard in game.world.layout.hazards:
			if hazard["def"]=="sand_bridge": bridge = hazard
		if not bridge.is_empty(): break
	var ledge: Dictionary = game.world.ledges[int(bridge["ledge"])]
	game.run_id = "levels-bridge"
	game.run_seed = bridge_seed
	game.camera_y = float(ledge["top"])+2.5
	game.camera_x = (float(ledge["left"])+float(ledge["right"]))*.5
	game.sim = RopeSim.new()
	game._configure_rope()
	game.sim.attached = false
	game.anchor_id = -1
	game.sim.pos = Vector2((float(ledge["left"])+float(ledge["right"]))*.5,float(ledge["top"])+SolidGeometry.BODY_HALF.y)
	game.sim.vel = Vector2.ZERO
	game.sim.grounded = true
	game.state = "play"
	game.run_seconds = 0.0
	game.hazard_clock = 0.0
	# Normal time: a slow-motion window left from an earlier release would now
	# (correctly) slow the telegraph too.
	game.focus_remaining = 0.0
	var reveal: Dictionary = game.world.anchor_by_id(int(bridge["reveal"]))
	var hidden_before: bool = reveal["broken"]
	for frame in range(150):
		game.walk = 0.0
		game._physics_process(1.0/120)
	check(hidden_before and ledge.get("collapsed",false) and not reveal["broken"],"a sand bridge holds through its telegraph, then collapses once and reveals a new exit")
	game.state = "play"
	game.save_snapshot()
	var snapshot: Dictionary = game.model.profile["active"].duplicate(true)
	check(snapshot.get("collapsed_hazards",[]).has(bridge["id"]),"the collapse is saved with the attempt")
	game.model.profile["active"] = snapshot
	game.resume_run()
	check(game.world.ledges[int(bridge["ledge"])].get("collapsed",false) and not game.world.anchor_by_id(int(bridge["reveal"]))["broken"] and not game.world.anchor_by_id(int(bridge["reveal"]))["hidden"],"a resumed attempt keeps the bridge down and its exit open")
	game.model.profile["active"] = {}
	# Slow motion slows the act hazards with the hero: their clock runs on the
	# scaled step while the run timer stays real time, and the clock is saved.
	game.start_run(false)
	game.sim.attached = false
	game.sim.grounded = false
	game.sim.pos = Vector2(40,40)
	game.sim.vel = Vector2.ZERO
	game.camera_y = game.sim.pos.y+2.5
	game.run_seconds = 0.0
	game.set("hazard_clock",0.0)
	game.focus_cooldown = 0.0
	game.focus_remaining = 5.0
	for frame in range(120): game._physics_process(1.0/120)
	var slowed = game.get("hazard_clock")
	check(absf(game.run_seconds-1.0)<.01 and slowed!=null and absf(float(slowed)-game.model.slowmo_time_scale())<.01,"a real second of slow motion moves the hazard clock by the slow-motion scale (%s)" % str(slowed))
	game.focus_remaining = 0.0
	game.set("hazard_clock",0.0)
	for frame in range(120): game._physics_process(1.0/120)
	var normal = game.get("hazard_clock")
	check(normal!=null and absf(float(normal)-1.0)<.01,"outside slow motion the hazard clock keeps real time (%s)" % str(normal))
	game.save_snapshot()
	check(game.state=="play" and normal!=null and absf(float(game.model.profile["active"].get("hazard_clock",-1.0))-float(normal))<.0001,"the hazard clock is saved with the attempt")
	game.model.profile["active"] = {}
	# The base kit climbs the whole main line of every expedition, hazards on.
	for location in range(3):
		for seed_number in [58273,4242]:
			game.selected_location = location
			game.start_run(false)
			var total := float(LevelCatalog.level(location)["height_units"])
			game._create_world(seed_number,location,total+6)
			hold_at(game,game.world.anchor_by_id(game.world.main_route[0]))
			recoveries = 0
			var reached := climb(game,game.world.main_route)
			check(reached==game.world.main_route.size() and game.state=="play" and recoveries<=2,"location %d seed %d: base kit climbs every act's main line with hazards active (%d/%d, %d recoveries)" % [location,seed_number,reached,game.world.main_route.size(),recoveries])
			game.model.profile["active"] = {}
	# Risky and collection branches are physically flown, hazards on.
	var flown := 0
	var tried := 0
	for location in range(3):
		var total := float(LevelCatalog.level(location)["height_units"])
		game.selected_location = location
		game.summit_height = total
		game._create_world(777,location,total+6)
		var count: int = game.world.layout.branches.size()
		for index in range(count):
			game._create_world(777,location,total+6)
			var branch: Dictionary = game.world.layout.branches[index]
			if branch.get("choice",false) or branch["route_tag"] not in ["risky_shortcut","speed","collection"]: continue
			hold_at(game,game.world.anchor_by_id(branch["entry"]))
			tried += 1
			if traverse(game,[branch["entry"],branch["anchor"],game.world.main_route[branch["exit_row"]]])==3: flown += 1
	check(tried>=15 and flown>=tried-2,"risky, speed and collection branches are flown to their exits (%d/%d)" % [flown,tried])
	# --- L6: contract seeds -------------------------------------------------------------
	var contracts: Array = []
	var contract_stable := true
	for location in range(3):
		for act in range(3):
			var seed_number := LevelCatalog.contract_seed(location,act)
			var a := make_world(seed_number,location)
			var b := make_world(seed_number,location)
			contract_stable = contract_stable and act_signature(a,act)==act_signature(b,act) and (a.layout as ExpeditionLayout).variant_of(act)==(b.layout as ExpeditionLayout).variant_of(act)
			contracts.append([location,act,(a.layout as ExpeditionLayout).variant_of(act),act_signature(a,act).size()])
			a.free()
			b.free()
	check(contract_stable,"each act's contract seed reproduces one variant and one route")
	print("LEVELS_CONTRACTS ",contracts)
	DirAccess.make_dir_recursive_absolute(directory)
	print("LEVELS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
