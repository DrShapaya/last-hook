class_name ExpeditionLayout
extends MassifLayout

# Generator v14: every location slot is an expedition of three acts
# (LevelCatalog). An act owns its height range, seed stream, silhouette,
# profile, beats and hazards:
#   start shelf -> intro links -> rule taught alone -> safe/risky fork ->
#   recovery shelf -> combination -> landmark and exit to the next act.
# Each act starts at a point fixed by its own seed and ends steering into the
# next act's start, so a route or decor variant never moves a neighbour act.
# Grip mechanics are GripSpec's; hazards are environment (see ActHazards).

const BASE_ROWS := {"start":1,"intro":1,"teach":3,"fork":3,"rest":2,"combo":2,"exit":2}
const MAX_ROWS := {"intro":3,"combo":4}
# Step templates: [dx, rise, mode]. `flip` reverses the horizontal direction,
# `same` keeps it, `bulge`/`back` draw the fork's safe detour, `exit` steers
# into the next act. A detour hangs beyond its exit grip, on the side the
# route zigzags to; the flips after it keep that side free of main transfers.
const STEPS := {
	"intro":[[2.8,2.9,"flip"],[2.9,3.0,"flip"],[2.7,2.85,"flip"]],
	"teach":[[2.9,2.95,"same"],[3.0,2.9,"flip"],[2.7,3.0,"flip"]],
	"fork":[[3.0,2.3,"bulge"],[.4,2.5,"bulge"],[3.1,2.4,"back"]],
	"rest":[[2.2,2.75,"flip"],[2.4,2.85,"flip"]],
	"combo":[[2.9,3.0,"flip"],[2.6,2.9,"flip"],[2.8,2.95,"flip"],[2.7,2.9,"flip"]],
	"exit":[[0.0,2.85,"exit"],[0.0,2.85,"exit"]],
}
const FINAL_RISE := 2.8
const LINK_RISE := 2.85
const OBSTACLE_KIND := {"shelf":4,"pillar":2,"wedge":0}
const START_DROP := 3.7
var height_units := 120.0
var spans: Array = []
var act_plans: Array[Dictionary] = []
var row_info: Array[Dictionary] = []
var reserved_spots: Dictionary = {}
# Contract variant per act index (L6); missing acts use the seed's choice.
var variant_override: Dictionary = {}
# v15 (chat 4): finds by placement role (LootPlacement) and the run's
# contract cargo. False keeps the v14 finds exactly.
var economy_loot := false
var contract: Dictionary = {}
var loot_plan: LootPlacement
# v16: the prepared route of a summit climb (LevelCatalog.ROUTES); empty for
# endless climbs and older generators.
var route: Dictionary = {}

func setup(world_seed: int, biome: int) -> void:
	super.setup(world_seed,biome)
	height_units = float(LevelCatalog.level(biome)["height_units"])
	spans = LevelCatalog.act_spans(biome,height_units)
	loot_plan = LootPlacement.new(self)

func generate_to(height: float, is_finite: bool, summit_height: float) -> void:
	super.generate_to(height,is_finite,summit_height)
	var complete := finite and (summit_added or main_point(row).y>=summit-.8)
	_rows_done(complete)
	if not economy_loot: return
	loot_plan.resolve_until(INF if complete else float(row-3))

# Called once rows are laid and before the remaining loot is placed; a
# subclass can add grips whose rewards join the same economy.
func _rows_done(_complete: bool) -> void:
	pass

# Main-path finds of the base generator become role requests in v15.
func _add_find(point: Vector2, zone: int, rare: bool) -> void:
	if economy_loot: loot_plan.request(row,point,"main_safe")
	else: super._add_find(point,zone,rare)

func _branch_find(index: int, point: Vector2, zone: int, rare: bool, role: String, from: Vector2 = Vector2.INF) -> void:
	if economy_loot: loot_plan.request(index,point,role,from)
	else: super._add_find(point,zone,rare)

# --- Acts ---------------------------------------------------------------------------

static func _key(text: String) -> int:
	var result := 7
	for index in range(text.length()): result = (result*131+text.unicode_at(index))%1000003
	return result

func span(act: int) -> Dictionary:
	var base: Dictionary = spans[posmod(act,spans.size())]
	var cycle := act/spans.size()
	var total: float = spans[-1]["y_end"]
	var definition := LevelCatalog.act(base["id"])
	return {"id":base["id"],"index":act,"local":int(base["index"]),"cycle":cycle,"def":definition,
		"y_start":float(base["y_start"])+cycle*total,"y_end":float(base["y_end"])+cycle*total}

func act_index_at(height: float) -> int:
	var total: float = spans[-1]["y_end"]
	# A summit climb ends in its last act, the summit shelf included.
	if finite and height>=total: return spans.size()-1
	var cycle := maxi(0,int(floor(height/total))) if height>=total else 0
	var local := height-cycle*total
	for base in spans:
		if local<float(base["y_end"]): return int(base["index"])+cycle*spans.size()
	return spans.size()-1+cycle*spans.size()

# The act stream: its own seed, never the global row index, so variants of
# one act leave the others untouched.
func act_rng(act: int, local: int, stream: int) -> RandomNumberGenerator:
	var info := span(act)
	var result := RandomNumberGenerator.new()
	result.seed = seed_value*7919+local*104729+stream*15485863+_key(info["id"])*32452843+int(info["cycle"])*49979687+location*86028121
	return result

func variant_count(act: int) -> int:
	return 1+span(act)["def"].get("variants",[]).size()

# The authored settings of an act on a prepared route (first cycle only).
func route_act(act: int) -> Dictionary:
	if route.is_empty() or act<0 or act>=spans.size(): return {}
	var acts: Array = route.get("acts",[])
	return acts[act] if act<acts.size() else {}

func variant_of(act: int) -> int:
	if variant_override.has(act): return int(variant_override[act])
	if not route_act(act).is_empty(): return clampi(int(route_act(act).get("variant",0)),0,variant_count(act)-1)
	return act_rng(act,0,61).randi_range(0,variant_count(act)-1)

# Beats of an act with its contract variant applied (same row counts).
func beats_of(act: int) -> Array:
	var info := span(act)
	var result: Array = []
	for beat in info["def"]["route_patterns"]: result.append((beat as Dictionary).duplicate())
	var variant := variant_of(act)
	if variant>0:
		var patch: Dictionary = info["def"]["variants"][variant-1]
		for key in patch.get("beats",{}).keys():
			var beat: Dictionary = result[int(key)]
			for field in patch["beats"][key].keys(): beat[field] = patch["beats"][key][field]
			for field in patch.get("erase",{}).get(key,[]): beat.erase(field)
	return result

func act_at(height: float) -> Dictionary:
	var info := span(act_index_at(height))
	var definition: Dictionary = info["def"]
	var level := LevelCatalog.level(location)
	return {"id":info["id"],"index":info["index"],"local":info["local"],"display_name":definition["display_name"],
		"biome_profile":definition["biome_profile"],"intro_rule":definition["intro_rule"],"y_start":info["y_start"],"y_end":info["y_end"],
		"level_id":level["id"],"level_name":level["display_name"],"variant":variant_of(int(info["index"])),"hazards":definition["hazards"]}

func profile_id_at(height: float) -> String:
	return str(span(act_index_at(height))["def"]["biome_profile"])

func width_scale(y: float) -> float:
	# Blend the act widths over a few metres around each border.
	var here := act_index_at(y)
	var info := span(here)
	var width := float(info["def"].get("width",1.0))
	var below := y-float(info["y_start"])
	if below<4.0 and here>0: width = lerpf(float(span(here-1)["def"].get("width",1.0)),width,.5+below/8.0)
	var above := float(info["y_end"])-y
	if above<4.0: width = lerpf(float(span(here+1)["def"].get("width",1.0)),width,.5+above/8.0)
	return width

func landform(index: int) -> Dictionary:
	if landforms.has(index): return landforms[index]
	var random := rng(index,310)
	var y := index*REGION_HEIGHT+9.0
	var act := act_index_at(y)
	var forms: Array = span(act)["def"]["silhouette"]
	var name := str(forms[posmod(index+seed_value,forms.size())])
	landforms[index] = {"kind":FORMS.find(name),"name":name,"y":y+random.randf_range(-1,1),"side":-massif_side if random.randf()<.7 else massif_side,"strength":random.randf_range(.85,1.15),"act":act}
	return landforms[index]

# --- Route --------------------------------------------------------------------------

func start_point(act: int) -> Vector2:
	var info := span(act)
	var random := act_rng(act,0,18)
	var authored := route_act(act)
	if not authored.is_empty():
		var x := clampf(float(authored.get("x",0.0)),-1.6,1.6)
		return Vector2(x,4.0) if act==0 else Vector2(x,float(info["y_start"])+1.0)
	if act==0:
		return Vector2(random.randf_range(.9,1.6)*(-1 if random.randf()<.5 else 1),4.0)
	return Vector2(random.randf_range(-1.6,1.6),float(info["y_start"])+1.0)

func main_point(index: int) -> Vector2:
	while route_points.size()<=index: _plan_act(act_plans.size())
	return route_points[index]

func _plan_act(act: int) -> void:
	var info := span(act)
	var random := act_rng(act,0,20)
	var start := start_point(act)
	var target := start_point(act+1)
	var beats := beats_of(act)
	var counts: Array[int] = []
	for beat in beats: counts.append(int(BASE_ROWS[beat["beat"]]))
	var total := 0
	for count in counts: total += count
	var wanted := roundi((target.y-start.y)/LINK_RISE)
	# Longer acts get more intro and combination links, never more beats.
	var guard := 0
	while total<wanted and guard<12:
		guard += 1
		for index in range(beats.size()):
			var kind: String = beats[index]["beat"]
			if total<wanted and MAX_ROWS.has(kind) and counts[index]<int(MAX_ROWS[kind]):
				counts[index] += 1
				total += 1
	# Rows after the start, as [beat, step]; rises scaled to land on target.
	var steps: Array = []
	for index in range(beats.size()):
		var kind: String = beats[index]["beat"]
		if kind=="start": continue
		for step in range(counts[index]): steps.append([index,step])
	var rises: Array[float] = []
	var nominal := FINAL_RISE
	for entry in steps:
		var template: Array = STEPS[beats[entry[0]]["beat"]][entry[1]]
		nominal += float(template[1])
		rises.append(float(template[1]))
	var scale := (target.y-start.y)/nominal
	var first_row := route_points.size()
	route_points.append(start)
	row_info.append({"act":act,"beat":0,"step":0,"type":"start","def":beats[0]})
	var plan := {"index":act,"id":info["id"],"first_row":first_row,"start":start,"target":target,"beats":beats,"counts":counts,"variant":variant_of(act),"forks":[]}
	var point := start
	var direction := -1 if random.randf()<.5 else 1
	# A prepared route sets the first swing side and the zigzag width.
	var authored := route_act(act)
	var sway := clampf(float(authored.get("sway",1.0)),.8,1.2)
	if not authored.is_empty(): direction = -1 if int(authored.get("dir",1))<0 else 1
	var last_direction := 0
	var fork_side := 1
	var remaining := steps.size()
	for k in range(steps.size()):
		var entry: Array = steps[k]
		var beat: Dictionary = beats[entry[0]]
		var kind: String = beat["beat"]
		var template: Array = STEPS[kind][entry[1]]
		var rise := rises[k]*scale+(random.randf_range(-.08,.08) if kind!="exit" else 0.0)
		var dx := 0.0
		match str(template[2]):
			"flip", "same":
				if template[2]=="flip": direction = -direction
				# Close to the exit the route turns towards the next act.
				if remaining<=5 and absf(point.x-target.x)>3.0 and signf(target.x-point.x)!=direction: direction = -direction
				dx = float(template[0])*direction*sway
				if absf(point.x+dx)>11.0:
					direction = -direction
					dx = -dx
			"bulge":
				if entry[1]==0:
					fork_side = -last_direction if last_direction!=0 else (-1 if random.randf()<.5 else 1)
					if absf(point.x+3.4*fork_side)>12.0: fork_side = -fork_side
					plan["forks"].append({"entry_row":first_row+k,"side":fork_side,"beat":entry[0]})
				direction = fork_side
				dx = float(template[0])*fork_side
			"back":
				direction = -fork_side
				dx = float(template[0])*direction
			"exit":
				var ideal := _exit_x(point,target,random,direction)
				if entry[1]==0:
					var middle := (point.x+ideal)*.5
					dx = clampf(middle-point.x-direction*1.8*(1 if absf(ideal-point.x)<3.0 else 0),-3.6,3.6)
				else:
					dx = clampf(ideal-point.x,-3.6,3.6)
				if absf(dx)>.05: direction = int(signf(dx))
		if absf(dx)>.05: last_direction = int(signf(dx))
		var jitter := random.randf_range(-.12,.12) if kind in ["intro","teach","combo","rest"] else 0.0
		point = Vector2(point.x+dx+jitter,point.y+rise)
		route_points.append(point)
		row_info.append({"act":act,"beat":entry[0],"step":entry[1],"type":kind,"def":beat,"side":fork_side if kind=="fork" else direction})
		remaining -= 1
	# The fork branch spot is known as soon as the act is planned; auxiliary
	# grips keep out of it.
	for fork in plan["forks"]:
		var entry_row: int = int(fork["entry_row"])
		var low := route_points[entry_row]
		var high := route_points[entry_row+3]
		var spot := (low+high)*.5+Vector2(-int(fork["side"])*1.6,0)
		fork["spot"] = spot
		for row in range(entry_row,entry_row+4): reserved_spots[row] = reserved_spots.get(row,[])+[spot]
	act_plans.append(plan)

func _exit_x(point: Vector2, target: Vector2, random: RandomNumberGenerator, direction: int) -> float:
	# The last grip of an act stands beside the next act's start, on the side
	# the route arrives from.
	var side := signf(point.x-target.x)
	if absf(point.x-target.x)<.8: side = -direction if direction!=0 else (-1.0 if random.randf()<.5 else 1.0)
	return target.x+side*2.4

# Optional grips take their lifetime from their place, not from their id, so
# an act's variant (more or fewer grips) cannot change another act.
func _add_anchor(point: Vector2, kind: int, dimensions: Vector2, primary: bool = false) -> int:
	var id := super._add_anchor(point,kind,dimensions,primary)
	if economy_loot: loot_plan.on_grip_added(point)
	if not primary:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value*7919+roundi(point.x*100)*104729+roundi(point.y*100)*15485863+391
		anchors[id]["permanent"] = GripSpec.network_kind(kind) and random.randf()<.035
	return id

func row_of(index: int) -> Dictionary:
	main_point(index)
	return row_info[index]

# --- Row hooks ----------------------------------------------------------------------

func _main_kind(index: int, random: RandomNumberGenerator) -> int:
	var _roll := random.randf() if index>1 else 1.0
	var info := row_of(index)
	var beat: Dictionary = info["def"]
	if int(beat.get("main",-1))!=GripSpec.SPRING: return GripSpec.STONE
	# The bough sits on the last intro link or the first combination link.
	var wanted_step: int = act_plans[info["act"]]["counts"][info["beat"]]-1 if info["type"]=="intro" else 0
	if info["step"]!=wanted_step: return GripSpec.STONE
	var point := main_point(index)
	var next := main_point(index+1)
	if not spring_lane_clear(point,(next-point).normalized()): return GripSpec.STONE
	return GripSpec.SPRING

func _main_created(index: int, id: int) -> void:
	var object := anchors[id]
	var info := row_of(index)
	object["permanent"] = false
	object["role"] = "main"
	object["act"] = info["act"]
	match str(info["type"]):
		"start":
			object["permanent"] = true
			object["role"] = "tutorial" if index==0 else "rest"
		"rest":
			if info["step"]==0:
				object["permanent"] = true
				object["role"] = "rest"
		"fork":
			if bool(info["def"].get("permanent_main",false)):
				object["permanent"] = true
				object["role"] = "recovery"
	if pending_choice.has(index):
		var crystal: Dictionary = anchors[pending_choice[index]]
		crystal["choice_exits"].append(id)
		pending_choice.erase(index)

func branch_spots(index: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var info := row_of(index)
	if info["step"]==0 and info["type"] in ["intro","teach","combo"] and info["def"].has("branch"):
		var point := main_point(index)
		for span_x in [3.8,-3.8,4.4,-4.4]: result.append(point+Vector2(span_x,.55))
	for spot in reserved_spots.get(index,[]): result.append(spot)
	return result

func _scenario_branch(index: int, point: Vector2, entry: int, zone: int) -> void:
	var info := row_of(index)
	var beat: Dictionary = info["def"]
	if info["step"]==0 and info["type"] in ["intro","teach","combo"]:
		if beat.has("branch"): _beat_detour(index,point,entry,zone,info)
		elif bool(beat.get("main_hazard",false)): _main_hazard(index,info)
	var next := row_of(index+1)
	if next["type"]=="fork" and next["step"]==0 and next["act"]==info["act"]:
		_fork(index,point,entry,zone,next)

func _plan_key(info: Dictionary) -> int:
	return int(info["act"])*100+int(info["beat"])

func _scenario_plan(info: Dictionary) -> Dictionary:
	var key := _plan_key(info)
	if not scenarios.has(key):
		var kind: String = info["type"]
		scenarios[key] = {"block":key,"template":kind if kind!="intro" else "intro_link","placed":false,"new":kind=="teach","combo":kind=="combo","act":info["act"],"beat":info["beat"]}
	return scenarios[key]

func _tag_branch(record: Dictionary, info: Dictionary, tag: String) -> void:
	var definition: Dictionary = span(info["act"])["def"]
	record["route_tag"] = tag
	record["act"] = info["act"]
	record["beat"] = info["type"]
	record["hazards"] = []
	record["reward_tag"] = definition.get("reward_tag","")
	record["contract_tag"] = definition.get("contract_tag","")
	record["alt_tag"] = info["def"].get("alt","safe_main")
	anchors[record["anchor"]]["act"] = info["act"]

# A detour beside a main grip that rejoins at the next one: a find, a known
# risk, a crystal choice or a hazard taught on its own.
func _beat_detour(index: int, point: Vector2, entry: int, zone: int, info: Dictionary) -> void:
	var beat: Dictionary = info["def"]
	var plan := _scenario_plan(info)
	var kind := int(beat["branch"])
	var exit := main_point(index+1)
	if finite and exit.y>=summit-.8: return
	var hazard_id := str(beat.get("hazard",""))
	var toward := signf(exit.x-point.x) if absf(exit.x-point.x)>.1 else 1.0
	# Beside the main grip first; on a narrow face a little lower and closer.
	var offsets: Array = []
	for direction in [toward,-toward]:
		for offset in [Vector2(3.8,.55),Vector2(4.4,.55),Vector2(3.3,.55),Vector2(3.2,-.4),Vector2(2.9,-.9)]:
			offsets.append(Vector2(offset.x*direction,offset.y))
	for offset in offsets:
		var side := int(signf(offset.x))
		var bonus: Vector2 = point+offset
		plan["reason"] = "outside, obstacle or crowded"
		if outside(bonus,0) or not transition_clear(point,bonus) or crowded(bonus): continue
		var probe := {"pos":bonus,"kind":kind,"slide_dir":slide_direction_at(bonus)}
		plan["reason"] = "exit"
		if not exit_reachable(probe,exit): continue
		plan["reason"] = "hazard or reward"
		if kind==GripSpec.SPRING and not spring_lane_clear(bonus,(exit-bonus).normalized()): continue
		var reward := Vector2.INF
		if kind==GripSpec.CRYSTAL:
			reward = _choice_reward(index,bonus,side)
			if not reward.is_finite(): continue
		var hazard := {}
		if not hazard_id.is_empty():
			hazard = _plan_hazard(hazard_id,info,bonus,point,exit,side,index)
			if hazard.is_empty(): continue
		var branch_id := _add_anchor(bonus,kind,Vector2(1.3,.6))
		anchors[branch_id]["role"] = "branch"
		anchors[branch_id]["permanent"] = false
		if kind==GripSpec.SPRING: anchors[branch_id]["exit_dir"] = (exit-bonus).normalized()
		if GripSpec.network_kind(kind): _add_edge(Vector2i(entry,branch_id))
		var record: Dictionary
		if kind==GripSpec.CRYSTAL:
			var reward_id := _add_anchor(reward,GripSpec.STONE,Vector2(1.3,.6))
			anchors[reward_id]["role"] = "reward"
			anchors[reward_id]["permanent"] = false
			anchors[branch_id]["choice_exits"] = [reward_id]
			pending_choice[index+1] = branch_id
			record = record_branch(entry,branch_id,index+1,exit,"choice",reward_id)
			var second := record_branch(branch_id,reward_id,index+2,main_point(index+2),"choice")
			second["choice"] = true
			_tag_branch(second,info,"collection")
			_branch_find(index,reward+Vector2(0,-2.05),zone,true,"choice")
		else:
			record = record_branch(entry,branch_id,index+1,exit,info["type"])
			_branch_find(index,bonus+Vector2(0,-2.05),zone,info["type"]!="combo","detour",point+Vector2(0,-2.05))
		_tag_branch(record,info,str(beat.get("tag","collection")))
		if not hazard.is_empty(): _commit_hazard(hazard,record)
		plan["placed"] = true
		plan["kind"] = kind
		return

# Safe main detour (the fork's three rows) against a short branch from the
# row before it straight to the detour's last row. Both leave forward.
func _fork(index: int, point: Vector2, entry: int, zone: int, info: Dictionary) -> void:
	var beat: Dictionary = info["def"]
	var kind := int(beat.get("branch",GripSpec.STONE))
	if kind==GripSpec.CRYSTAL:
		_beat_detour(index,point,entry,zone,info)
		_fork_landmark(index,info)
		return
	var plan := _scenario_plan(info)
	var exit := main_point(index+3)
	if finite and exit.y>=summit-.8: return
	var side := int(info["side"])
	var rope := float(base_kit()["rope"])
	var hazard_id := str(beat.get("hazard",""))
	# Outside the safe detour first; on a narrow face inside its bend.
	for offset in [1.6,2.0,1.25,-.5,-.2]:
		var spot := (point+exit)*.5+Vector2(-side*float(offset),0)
		plan["reason"] = "outside or obstacle"
		if outside(spot,0) or not transition_clear(point,spot) or not transition_clear(spot,exit): continue
		plan["reason"] = "reach or crowded"
		if point.distance_to(spot)>rope-.4 or crowded(spot): continue
		plan["reason"] = "spacing"
		if spot.distance_to(main_point(index+1))<RouteGraph.GRIP_SPACING+.4 or spot.distance_to(main_point(index+2))<RouteGraph.GRIP_SPACING+.4: continue
		var probe := {"pos":spot,"kind":kind,"slide_dir":slide_direction_at(spot)}
		plan["reason"] = "exit"
		if not exit_reachable(probe,exit): continue
		plan["reason"] = "spring lane"
		if kind==GripSpec.SPRING and not spring_lane_clear(spot,(exit-spot).normalized()): continue
		var hazard := {}
		var extra := {}
		if not hazard_id.is_empty():
			plan["reason"] = "hazard "+hazard_id
			hazard = _plan_hazard(hazard_id,info,spot,point,exit,-side,index,3)
			if hazard.is_empty(): continue
		if beat.has("extra"):
			extra = _plan_hazard(str(beat["extra"]),info,spot,point,exit,-side,index,3)
		var branch_id := _add_anchor(spot,kind,Vector2(1.3,.6))
		anchors[branch_id]["role"] = "branch"
		anchors[branch_id]["permanent"] = false
		if kind==GripSpec.SPRING: anchors[branch_id]["exit_dir"] = (exit-spot).normalized()
		if GripSpec.network_kind(kind): _add_edge(Vector2i(entry,branch_id))
		var record := record_branch(entry,branch_id,index+3,exit,"fork")
		_tag_branch(record,info,str(beat.get("tag","risky_shortcut")))
		# A collection fork carries a rare find on its short branch.
		if record["route_tag"]=="collection" or economy_loot: _branch_find(index,spot+Vector2(0,-2.05),zone,true,"fork_"+str(record["route_tag"]))
		record["shortcut"] = true
		record["skips_rows"] = 2
		if not hazard.is_empty(): _commit_hazard(hazard,record)
		if not extra.is_empty(): _commit_hazard(extra,record)
		plan["placed"] = true
		plan["kind"] = kind
		_fork_landmark(index,info)
		return

# The second exit of a crystal: a grip beside the next main grip (either side,
# or between it and the one after) that rejoins the main path a row later.
func _choice_reward(index: int, crystal: Vector2, side: int) -> Vector2:
	var after := main_point(index+2)
	if finite and after.y>=summit-.8: return Vector2.INF
	var next := main_point(index+1)
	for candidate in [next+Vector2(side*3.8,.55),next+Vector2(-side*3.8,.55),next+Vector2(side*2.8,1.2),(next+after)*.5+Vector2(side*2.6,0),(next+after)*.5+Vector2(-side*2.6,0)]:
		var reward: Vector2 = candidate
		if outside(reward,0) or reward.distance_to(crystal)>=LINK_REACH or reward.distance_to(after)>=LINK_REACH: continue
		if reward.distance_to(next)<RouteGraph.GRIP_SPACING+.2 or reward.distance_to(after)<RouteGraph.GRIP_SPACING+.2 or reward.distance_to(crystal)<RouteGraph.GRIP_SPACING+.2: continue
		if crowded(reward) or not transition_clear(crystal,reward) or not transition_clear(reward,after): continue
		if reward.y<=crystal.y: continue
		return reward
	return Vector2.INF

func _fork_landmark(index: int, info: Dictionary) -> void:
	var family := str(info["def"].get("landmark",""))
	if family.is_empty(): return
	var point := main_point(index)
	landmarks.append({"act":info["act"],"family":family,"pos":point+Vector2(int(info["side"])*-3.4,1.2),"role":"fork"})

# --- Hazards ------------------------------------------------------------------------

func _main_lanes(low: int, high: int) -> Array:
	var result: Array = []
	for row in range(maxi(0,low),high):
		result.append([main_point(row),main_point(row+1)])
	return result

static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b): return true
	var corners := [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]
	for index in range(4):
		if Geometry2D.segment_intersects_segment(a,b,corners[index],corners[(index+1)%4])!=null: return true
	return false

# A lane is a transfer and the hanging heights below it.
static func lane_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	for drop in [0.0,1.5,2.8]:
		if _segment_hits_rect(a-Vector2(0,drop),b-Vector2(0,drop),rect): return true
	return false

# Main transfers keep a wider berth: the hero swings well below and beside
# the straight lane on the rope.
const SWING_DROPS := [0.0,1.5,2.8,4.2]

static func lane_near_point(a: Vector2, b: Vector2, point: Vector2, radius: float, drops: Array = [0.0,1.5,2.8]) -> bool:
	for drop in drops:
		if Geometry2D.get_closest_point_to_segment(point,a-Vector2(0,drop),b-Vector2(0,drop)).distance_to(point)<radius: return true
	return false

static func lane_near_line(a: Vector2, b: Vector2, top: Vector2, bottom: Vector2, radius: float, drops: Array = [0.0,1.5,2.8]) -> bool:
	for drop in drops:
		var p := a-Vector2(0,drop)
		var q := b-Vector2(0,drop)
		if Geometry2D.segment_intersects_segment(p,q,top,bottom)!=null: return true
		var closest := Geometry2D.get_closest_points_between_segments(p,q,top,bottom)
		if closest[0].distance_to(closest[1])<radius: return true
	return false

func _plan_hazard(hazard_id: String, info: Dictionary, grip: Vector2, entry: Vector2, exit: Vector2, outward: int, index: int, span_rows: int = 1) -> Dictionary:
	var definition := LevelCatalog.hazard(hazard_id)
	if definition.is_empty(): return {}
	var in_act := 0
	for other in hazards: in_act += 1 if int(other["act"])==int(info["act"]) else 0
	var random := act_rng(info["act"],index,700+in_act)
	var lanes := _main_lanes(index-2,index+span_rows+2)
	var branch_lanes := [[entry,grip],[grip,exit]]
	var hazard := {"def":hazard_id,"kind":definition["kind"],"act":info["act"],"beat":info["type"],"row":index,
		"telegraph_time":definition["telegraph_time"],"active_time":definition["active_time"],"calm_time":definition["calm_time"],
		"collision":definition["collision"],"damage":definition["damage"],"safe_exit_tags":definition["safe_exit_tags"],
		"affected_edges":[],"affects_main":false,"phase":_weather_phase(info["act"],random),"grip":grip}
	match str(definition["kind"]):
		"field":
			# The pocket lies on the branch side; its inner edge moves out until
			# no main transfer (or hanging height below one) crosses it.
			for inner in [1.0,.6,.3]:
				var a: float = grip.x-outward*float(inner)
				var b: float = grip.x+outward*3.2
				for top_cut in [0.0,1.0,2.0]:
					var rect := Rect2(Vector2(minf(a,b),grip.y-3.4+top_cut*.5),Vector2(absf(a-b),5.0-top_cut))
					var clear := true
					for lane in lanes: clear = clear and not lane_hits_rect(lane[0],lane[1],rect)
					if not clear: continue
					if not rect.has_point(grip+Vector2(0,-1.0)): continue
					hazard["rect"] = rect
					# Wind blows out of the route, a gust across it; never into rock or down.
					hazard["force"] = Vector2(outward*float(definition["force"]),.0)
					hazard["affected_edges"] = branch_lanes
					hazard["haze"] = bool(definition.get("haze",false))
					return hazard
			return {}
		"contact":
			# Out beside the branch grip and above it: only a swing carried far
			# past the grip, away from the exit, reaches it.
			for attempt in [Vector2(2.4,1.4),Vector2(2.8,1.0),Vector2(2.1,1.8),Vector2(3.0,.6)]:
				var at: Vector2 = grip+Vector2(outward*attempt.x,attempt.y)
				var radius := float(definition["radius"])
				var clear := not outside(at,0)
				for lane in lanes: clear = clear and not lane_near_point(lane[0],lane[1],at,radius+1.1,SWING_DROPS)
				for lane in branch_lanes: clear = clear and not lane_near_point(lane[0],lane[1],at,radius+.55)
				if not clear: continue
				hazard["pos"] = at
				hazard["radius"] = radius
				return hazard
			return {}
		"falling":
			for dx in [1.7,1.9,1.5,2.1]:
				var x: float = grip.x+outward*dx
				var top := Vector2(x,grip.y+2.4)
				var bottom := Vector2(x,grip.y-3.6)
				var radius := float(definition["radius"])
				var clear := not outside(top,0)
				for lane in lanes: clear = clear and not lane_near_line(lane[0],lane[1],top,bottom,radius+1.1,SWING_DROPS)
				for lane in branch_lanes: clear = clear and not lane_near_line(lane[0],lane[1],top,bottom,radius+.25)
				if not clear: continue
				hazard["x"] = x
				hazard["top"] = top.y
				hazard["bottom"] = bottom.y
				hazard["radius"] = radius
				# Only the branch's own hanging zone starts the crack, never a main
				# transfer swinging past.
				var inner: float = grip.x-outward*.7
				var outer: float = x+outward*1.0
				hazard["trigger"] = Rect2(Vector2(minf(inner,outer),bottom.y-.5),Vector2(absf(outer-inner),top.y-bottom.y+.5))
				return hazard
			return {}
	return {}

# Storms and gusts of one act follow one weather clock, so their calm windows
# coincide; contact hazards keep their own rhythm.
func _weather_phase(act: int, random: RandomNumberGenerator) -> float:
	var _own := random.randf()
	return act_rng(act,0,705).randf_range(0,4.0)

func _commit_hazard(hazard: Dictionary, record: Dictionary) -> void:
	hazard["id"] = hazards.size()
	hazard["branch_anchor"] = record["anchor"]
	hazards.append(hazard)
	record["hazards"].append(hazard["id"])

func _main_hazard(index: int, info: Dictionary) -> void:
	# A cyclic storm over the main transfers of the beat: stone grips hold,
	# so the calm window is always waited out on the route itself.
	var hazard_id := str(info["def"]["hazard"])
	var definition := LevelCatalog.hazard(hazard_id)
	var plan := _scenario_plan(info)
	var count: int = act_plans[info["act"]]["counts"][info["beat"]]
	var low := main_point(index-1)
	var high := main_point(index+count-1)
	var random := act_rng(info["act"],index,760)
	var direction := -1.0 if random.randf()<.5 else 1.0
	var rect := Rect2(Vector2(-18,low.y-1.0),Vector2(36,high.y-low.y+1.5))
	var hazard := {"def":hazard_id,"kind":definition["kind"],"act":info["act"],"beat":info["type"],"row":index,
		"telegraph_time":definition["telegraph_time"],"active_time":definition["active_time"],"calm_time":definition["calm_time"],
		"collision":definition["collision"],"damage":definition["damage"],"safe_exit_tags":definition["safe_exit_tags"],
		"affected_edges":_main_lanes(index-1,index+count-1),"affects_main":true,"phase":_weather_phase(info["act"],random),
		"rect":rect,"force":Vector2(direction*float(definition["force"]),0),"haze":bool(definition.get("haze",false)),"id":hazards.size(),"branch_anchor":-1}
	hazards.append(hazard)
	plan["placed"] = true

# --- Shelves, obstacles and the bridge ------------------------------------------------

func _place_rest(index: int) -> void:
	var info := row_of(index)
	var definition: Dictionary = span(info["act"])["def"]
	var point := main_point(index)
	var half := minf(float(definition.get("shelf_width",1.6)),2.1)
	if info["type"]=="start" and index>0:
		ledges.append({"left":point.x-half,"right":point.x+half,"top":point.y-START_DROP,"style":int(act_rng(info["act"],index,330).randi_range(0,2)),"anchor_row":index,"act":info["act"],"role":"start"})
	elif info["type"]=="rest" and info["step"]==0:
		var ledge := {"left":point.x-half,"right":point.x+half,"top":point.y-REST_DROP,"style":int(act_rng(info["act"],index,330).randi_range(0,2)),"anchor_row":index,"act":info["act"],"role":"rest"}
		ledges.append(ledge)
		for branch in branches:
			if branch["entry"]==main_route[-1]: branch["entry_consumed"] = false
		if str(info["def"].get("hazard",""))=="sand_bridge": _sand_bridge(index,info,ledge)

func _sand_bridge(index: int, info: Dictionary, ledge: Dictionary) -> void:
	# The rest shelf is a sand bridge: it collapses once under the hero and a
	# hidden permanent grip beside it becomes the new exit. The rest grip above
	# stays permanent, so the collapse never removes the only way on.
	var point := main_point(index)
	var next := main_point(index+1)
	var plan := _scenario_plan(info)
	var toward := signf(next.x-point.x) if absf(next.x-point.x)>.1 else 1.0
	for offset in [Vector2(2.3,-1.1),Vector2(2.0,-.6),Vector2(2.6,-1.5)]:
		var reveal := point+Vector2(toward*offset.x,offset.y)
		if outside(reveal,0) or crowded(reveal) or reveal.distance_to(next)>=LINK_REACH-.3 or not transition_clear(reveal,next): continue
		var stand := Vector2(clampf(reveal.x,float(ledge["left"]),float(ledge["right"])),float(ledge["top"])+.4)
		if stand.distance_to(reveal)>float(base_kit()["rope"])-.5: continue
		var id := _add_anchor(reveal,GripSpec.STONE,Vector2(1.3,.6))
		anchors[id]["role"] = "revealed"
		anchors[id]["permanent"] = true
		anchors[id]["broken"] = true
		anchors[id]["hidden"] = true
		anchors[id]["act"] = info["act"]
		_add_edge(Vector2i(main_route[-1],id))
		var definition := LevelCatalog.hazard("sand_bridge")
		var hazard := {"def":"sand_bridge","kind":"collapse","act":info["act"],"beat":"rest","row":index,
			"telegraph_time":definition["telegraph_time"],"active_time":0.0,"calm_time":0.0,
			"collision":"ledge","damage":definition["damage"],"safe_exit_tags":definition["safe_exit_tags"],
			"affected_edges":[[stand,reveal],[reveal,next]],"affects_main":false,"phase":0.0,
			"ledge":ledges.size()-1,"reveal":id,"id":hazards.size(),"branch_anchor":-1}
		ledge["bridge"] = hazard["id"]
		anchors[id]["revealed_by"] = hazard["id"]
		hazards.append(hazard)
		plan["placed"] = true
		return

# Obstacles keep out of the lanes of forks planned ahead, before their branch
# grip exists.
func _try_obstacle(candidate: Dictionary, index: int) -> bool:
	if not candidate.get("encounter",false): return false
	for plan in act_plans:
		for fork in plan["forks"]:
			var entry_row := int(fork["entry_row"])
			if entry_row<index-6 or entry_row>index+6: continue
			var spot: Vector2 = fork["spot"]
			if not transition_clear(main_point(entry_row),spot,candidate) or not transition_clear(spot,main_point(entry_row+3),candidate): return false
	return super._try_obstacle(candidate,index)

func _place_encounter(index: int) -> void:
	var info := row_of(index)
	if info["step"]!=0 or info["type"] not in ["intro","teach","combo","rest"]: return
	var definition: Dictionary = span(info["act"])["def"]
	var kind: int = OBSTACLE_KIND.get(definition.get("obstacle","wedge"),0)
	var encounter := {"row":index,"kind":kind,"name":str(definition["display_name"]),"entry":main_route[-1],"obstacles":[],"act":info["act"],"beat":info["type"]}
	encounters.append(encounter)
	if index>=5: _build_obstacles(index,encounter)

# Hand-placed extras of a prepared route on the beat row they belong to.
func _route_extras(index: int, info: Dictionary) -> void:
	var act := int(info["act"])
	if route.is_empty() or act>=spans.size(): return
	var point := main_point(index)
	var key := func(entry: Array) -> bool: return int(entry[0])==act and str(entry[1])==str(info["type"]) and int(entry[2])==int(info["step"])
	for entry in route.get("decor",[]):
		if key.call(entry): landmarks.append({"act":act,"family":str(entry[4]),"pos":point+Vector2(int(entry[3])*5.0,.6),"role":"route"})
	if not economy_loot: return
	for entry in route.get("coins",[]):
		if key.call(entry) and not (finite and main_point(index+1).y>=summit-.8):
			loot_plan.request(index,point+Vector2(0,-2.05),"trail",main_point(index+1)+Vector2(0,-2.05),{"count":int(entry[3])})
	for entry in route.get("caches",[]):
		if key.call(entry): loot_plan.request(index,point+Vector2(int(entry[3])*2.4,-1.3),"route_cache")
	for entry in route.get("treasures",[]):
		if key.call(entry): loot_plan.request(index,point+Vector2(int(entry[3])*2.5,-1.1),"route_treasure")

func _generate_row(index: int) -> void:
	super._generate_row(index)
	var info := row_of(index)
	_route_extras(index,info)
	# The last grip of an act points at the landmark that marks the way on.
	var next := row_of(index+1)
	if info["type"]=="exit" and next["act"]!=info["act"] and (not finite or main_point(index).y<summit-1.0):
		var definition: Dictionary = span(info["act"])["def"]
		var families: Array = definition.get("landmarks",[])
		if not families.is_empty():
			var point := main_point(index)
			var side := -signf(point.x) if absf(point.x)>.5 else 1.0
			landmarks.append({"act":info["act"],"family":str(families[0]),"pos":point+Vector2(side*5.2,.4),"role":"exit"})
	if economy_loot:
		# One landmark relic per act, under the grip that leads out of it.
		if info["type"]=="exit" and info["step"]==0: loot_plan.request(index,main_point(index)+Vector2(.25,-2.05),"landmark")
		# Odd main rows carry a single coin; even rows already requested theirs.
		elif index%2==1: loot_plan.request(index,main_point(index)+Vector2(-.25,-2.05),"main_coin")
		loot_plan.resolve_until(float(index-2))
