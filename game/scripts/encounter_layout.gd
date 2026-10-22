class_name EncounterLayout
extends MountainLayout

const NAMES := ["Траверс","Смена дуги","Колодец","Длинный перелёт","Карман отдыха","Каменные ворота","Карниз","Обход за находкой"]
const HORIZONTAL := [[2.8,3.0,2.7],[3.0,-3.1,-2.7],[1.65,-1.9,1.7],[3.6,3.7,-2.8],[2.7,1.7,-2.6],[3.1,3.0,-3.2],[2.7,-2.9,3.2],[3.3,3.1,-3.0]]
const VERTICAL := [[2.85,2.95,3.0],[3.0,2.85,3.1],[3.65,3.7,3.55],[2.65,2.8,3.0],[2.9,3.4,2.8],[2.95,3.1,3.15],[3.25,3.05,3.15],[3.0,3.0,3.1]]
const REST_DROP := 3.7
const REST_GAP := 18.0
var encounters: Array[Dictionary] = []
var phrase_bags: Dictionary = {}

# --- Scenario routes (v12) ------------------------------------------------------
# Each three-transfer phrase gets a scenario before any grip type is chosen:
# the main path stays on the base kit, and a special type only appears where
# the scenario gives it a verified exit. Mechanics are introduced by height,
# one new risk per phrase.
const SCENARIO_MECHANIC := {"energy":GripSpec.SPRING,"risk":GripSpec.ROOT,"slide":GripSpec.ICE,"choice":GripSpec.CRYSTAL}
const SCENARIO_NAMES := {"intro":"Введение","energy":"Выходная энергия","risk":"Временный риск","slide":"Скольжение","choice":"Развилка"}
# Allowed scenarios per height zone (Лес, Скалы, Руины, Лёд, Вулкан, Небеса):
# low - stone and a rare bough; middle - one timed or impulse phrase and loot
# detours; top - ice and crystal forks after their introduction.
const ZONE_SCENARIOS := [["intro","intro","energy"],["intro","energy","risk","risk"],["energy","risk","risk","intro"],["slide","risk","energy","choice"],["choice","slide","risk","energy"],["choice","slide","energy","risk"]]
# A movement phrase prefers the scenario its geometry explains best.
const PHRASE_SCENARIO := {2:"slide",3:"energy",4:"intro",6:"risk",7:"choice"}
# Recovery after this many disposable main grips in a row (the old fixed
# interval of permanent grips), placed where the series actually ends.
const RECOVERY_STREAK := 9
var scenarios: Dictionary = {}
var introduced: Dictionary = {}
var disposable_streak := 0
var pending_choice: Dictionary = {}

func phrase_kind(block: int) -> int:
	if block<3: return [0,1,4][posmod(block+seed_value,3)]
	var cycle := (block-3)/8
	if not phrase_bags.has(cycle):
		var bag := range(8)
		var random := rng(cycle,201)
		for i in range(7,0,-1):
			var j := random.randi_range(0,i)
			var temp: int = bag[i]
			bag[i] = bag[j]
			bag[j] = temp
		if cycle==0 and bag[0]==phrase_kind(2):
			var temp: int = bag[0]
			bag[0] = bag[1]
			bag[1] = temp
		elif cycle>0 and bag[0]==phrase_kind(3+(cycle-1)*8+7):
			var temp: int = bag[0]
			bag[0] = bag[1]
			bag[1] = temp
		phrase_bags[cycle] = bag
	return int(phrase_bags[cycle][(block-3)%8])

func main_point(index: int) -> Vector2:
	if route_points.is_empty():
		route_points.append(Vector2(1.6*(-1 if rng(0,18).randf()<.5 else 1),4))
	while route_points.size()<=index:
		var step := route_points.size()-1
		var previous := route_points[-1]
		var side := -1 if rng(0,18).randf()<.5 else 1
		var dx := (1.8 if step==0 else 2.2)*side
		var rise := 2.4 if step==0 else 2.65
		if step>=2:
			var block := (step-2)/3
			var kind := phrase_kind(block)
			var beat := (step-2)%3
			var random := rng(block,203)
			var direction := side*(-1 if random.randf()<.5 else 1)
			dx = float(HORIZONTAL[kind][beat])*direction
			rise = float(VERTICAL[kind][beat])+rng(step,204).randf_range(-.09,.09)
		var next_x := previous.x+dx
		if absf(next_x)>12.0: next_x = previous.x-dx
		route_points.append(Vector2(next_x,previous.y+rise))
	return route_points[index]

func scenario(block: int) -> Dictionary:
	# Planned when the phrase's first row is generated. Rows are generated in
	# order, so the plan sees the same history for any request size.
	if scenarios.has(block): return scenarios[block]
	var entry := 2+block*3
	var zone := clampi(int(main_point(entry).y/20),0,5)
	var phrase := phrase_kind(block)
	var allowed: Array = ZONE_SCENARIOS[zone]
	var random := rng(block,410)
	var template := "intro"
	if block>0:
		var preferred: String = PHRASE_SCENARIO.get(phrase,"")
		template = preferred if allowed.has(preferred) else str(allowed[random.randi_range(0,allowed.size()-1)])
		var previous: String = scenarios.get(block-1,{}).get("template","")
		if template==previous and template!="intro":
			template = str(allowed[(allowed.find(template)+1)%allowed.size()])
	var mechanic: int = SCENARIO_MECHANIC.get(template,GripSpec.STONE)
	var fresh := mechanic!=GripSpec.STONE and not introduced.has(mechanic)
	# Known risks may combine with a bough on the middle beat, never with a
	# second new rule.
	var combo := zone>=3 and not fresh and template in ["risk","slide","choice"] and introduced.has(GripSpec.SPRING) and random.randf()<.35
	var plan := {"block":block,"template":template,"name":SCENARIO_NAMES[template],"mechanic":mechanic,"new":fresh,"combo":combo,"zone":zone,"placed":false}
	scenarios[block] = plan
	return plan

func scenario_for_row(index: int) -> Dictionary:
	return scenario(maxi(0,(index-2)/3)) if index>=2 else {}

func _main_kind(index: int, random: RandomNumberGenerator) -> int:
	var legacy := super._main_kind(index,random)
	if not scenario_routes: return legacy
	var plan := scenario_for_row(index)
	if plan.is_empty() or (index-2)%3!=1: return GripSpec.STONE
	return GripSpec.SPRING if plan["template"]=="energy" or plan["combo"] else GripSpec.STONE

func _main_created(index: int, id: int) -> void:
	if not scenario_routes: return
	var object := anchors[id]
	var plan := scenario_for_row(index)
	if index>0:
		object["permanent"] = false
		object["role"] = "main"
		# Recovery follows a long disposable series, and a permanent node
		# stands before a newly introduced mechanic; neither is a fixed ladder.
		if disposable_streak>=RECOVERY_STREAK:
			object["permanent"] = true
			object["role"] = "recovery"
		elif not plan.is_empty() and (index-2)%3==0 and plan["new"] and disposable_streak>=3:
			object["permanent"] = true
			object["role"] = "tutorial"
	disposable_streak = 0 if object["permanent"] else disposable_streak+1
	if not plan.is_empty() and GripSpec.kind_of(object)==GripSpec.SPRING:
		plan["placed"] = true
		introduced[GripSpec.SPRING] = introduced.get(GripSpec.SPRING,plan["block"])
	if pending_choice.has(index):
		var crystal: Dictionary = anchors[pending_choice[index]]
		crystal["choice_exits"].append(id)
		pending_choice.erase(index)

func _scenario_branch(index: int, point: Vector2, entry: int, zone: int) -> void:
	# Branch scenarios leave from the phrase's first main grip and rejoin at
	# the next one, after the entry has been consumed.
	var plan := scenario_for_row(index)
	if plan.is_empty() or plan["template"] not in ["risk","slide","choice"]: return
	# v13: once a timed or sliding rule is known, the phrase repeats it on its
	# middle beat as a second detour - the rule appears alone, then repeated,
	# and only later in a combination.
	var repeat: bool = calibrated_routes and (index-2)%3==1 and plan["template"] in ["risk","slide"] and not plan["new"] and plan.get("placed",false)
	if (index-2)%3!=0 and not repeat: return
	var exit := main_point(index+1)
	if finite and exit.y>=summit-.8: return
	var kinds: Array[int] = [int(plan["mechanic"])]
	# A crystal needs two verified exits; without them the fork becomes a
	# plain timed detour rather than an unexplained crystal.
	if plan["template"]=="choice" and introduced.has(GripSpec.ROOT) and not repeat: kinds.append(GripSpec.ROOT)
	var toward := int(signf(exit.x-point.x)) if absf(exit.x-point.x)>.1 else 1
	for kind in kinds:
		# v13 tries a wider spot on each side before giving the phrase up.
		var spans: Array = [3.8*toward,-3.8*toward,4.4*toward,-4.4*toward] if calibrated_routes else [3.8*toward,-3.8*toward]
		for span in spans:
			var side := int(signf(span))
			var bonus := point+Vector2(span,.55)
			if outside(bonus,0) or not transition_clear(point,bonus): continue
			if calibrated_routes and crowded(bonus): continue
			var probe := {"pos":bonus,"kind":kind,"slide_dir":slide_direction_at(bonus)}
			if not exit_reachable(probe,exit): continue
			var reward := Vector2.INF
			if kind==GripSpec.CRYSTAL:
				reward = _choice_reward(index,bonus,side)
				if not reward.is_finite(): continue
			var branch_id := _add_anchor(bonus,kind,Vector2(1.3,.6))
			anchors[branch_id]["role"] = "branch"
			if kind==GripSpec.CRYSTAL:
				var reward_id := _add_anchor(reward,GripSpec.STONE,Vector2(1.3,.6))
				anchors[reward_id]["role"] = "reward"
				anchors[reward_id]["permanent"] = false
				anchors[branch_id]["choice_exits"] = [reward_id]
				pending_choice[index+1] = branch_id
				record_branch(entry,branch_id,index+1,exit,plan["template"],reward_id)
				record_branch(branch_id,reward_id,index+2,main_point(index+2),"choice")["choice"] = true
				_add_find(reward+Vector2(0,-2.05),zone,true)
			else:
				record_branch(entry,branch_id,index+1,exit,plan["template"])["repeat"] = repeat
				# A repeated detour is practice, not a second relic.
				_add_find(bonus+Vector2(0,-2.05),zone,not repeat)
			plan["placed"] = true
			plan["kind"] = kind
			introduced[kind] = introduced.get(kind,plan["block"])
			return

func branch_spots(index: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var plan := scenario_for_row(index)
	if plan.is_empty() or plan["template"] not in ["risk","slide","choice"] or (index-2)%3>1: return result
	var point := main_point(index)
	var exit := main_point(index+1)
	var toward := signf(exit.x-point.x) if absf(exit.x-point.x)>.1 else 1.0
	result.append(point+Vector2(3.8*toward,.55))
	if plan["template"]=="choice": result.append(exit+Vector2(3.8*toward,.55))
	return result

# A branch grip needs its own space: a hook aimed at it must not catch a
# neighbour instead.
func crowded(point: Vector2) -> bool:
	for id in nearby_ids(point.y-2,point.y+2):
		if not anchors[id].get("reserve",false) and anchors[id]["pos"].distance_to(point)<RouteGraph.GRIP_SPACING: return true
	return false

func _choice_reward(index: int, crystal: Vector2, side: int) -> Vector2:
	# The second exit of a crystal: the loot spot one row higher on the same
	# side, which then rejoins the main route a row later still.
	var after := main_point(index+2)
	if finite and after.y>=summit-.8: return Vector2.INF
	var reward := main_point(index+1)+Vector2(side*3.8,.55)
	if outside(reward,0) or reward.distance_to(crystal)>=LINK_REACH or reward.distance_to(after)>=LINK_REACH: return Vector2.INF
	if reward.distance_to(main_point(index+1))<1.45: return Vector2.INF
	if calibrated_routes and crowded(reward): return Vector2.INF
	if not transition_clear(crystal,reward) or not transition_clear(reward,after): return Vector2.INF
	return reward

func _generate_row(index: int) -> void:
	var ledges_before := ledges.size()
	super._generate_row(index)
	# Rest belongs to a movement phrase, with a minimum separation and a cap;
	# it is not another evenly spaced ladder of permanent platforms.
	ledges.resize(ledges_before)
	_place_rest(index)
	_place_encounter(index)

func _place_rest(index: int) -> void:
	var kind := phrase_kind(maxi(0,(index-2)/3))
	var point := main_point(index)
	var last_top: float = ledges[-1]["top"]
	if index>3 and (kind==4 or index%9==8) and point.y-REST_DROP-last_top>=REST_GAP and (not finite or ledges.size()<6) and (not finite or point.y<summit-5):
		ledges.append({"left":point.x-1.4,"right":point.x+1.4,"top":point.y-REST_DROP,"style":int(rng(index,330).randi_range(0,2)),"anchor_row":index})
		anchors[main_route[-1]]["permanent"] = true
		anchors[main_route[-1]]["role"] = "rest"
		disposable_streak = 0
		for branch in branches:
			if branch["entry"]==main_route[-1]: branch["entry_consumed"] = false

func _place_encounter(index: int) -> void:
	var kind := phrase_kind(maxi(0,(index-2)/3))
	if index>=2 and (index-2)%3==0:
		var block := (index-2)/3
		var encounter := {"row":index,"kind":kind,"name":NAMES[kind],"entry":main_route[-1],"obstacles":[]}
		if scenario_routes: encounter["scenario"] = scenario(block)
		encounters.append(encounter)
		if index>=5: _build_obstacles(index,encounter)

func _build_obstacles(index: int, encounter: Dictionary) -> void:
	var point := main_point(index)
	var next := main_point(index+1)
	var random := rng(index,205)
	var side := -1 if next.x>point.x else 1
	var dimensions := Vector2(1.15,3.0)
	var shape := "pillar"
	match int(encounter["kind"]):
		2,5:
			dimensions = Vector2(1.1,3.2)
		4,6:
			shape = "shelf"
			dimensions = Vector2(3.2,.9)
		_:
			shape = "wedge"
			dimensions = Vector2(2.0,1.8)
	# A barrier frames a deliberate swing pocket. Try each side and a small
	# set of offsets, never keep an arbitrary fallback in a protected lane.
	for attempt in range(8):
		var direction := side if attempt<4 else -side
		var offset := 3.8+float(attempt%4)*1.15
		var candidate := {"pos":point+Vector2(direction*offset,-.7+random.randf_range(-.2,.2)),"dimensions":dimensions,"type":shape,"encounter":true,"rest":shape=="shelf"}
		if shape=="wedge":
			var w := dimensions.x*.5
			var h := dimensions.y*.5
			candidate["polygon"] = PackedVector2Array([Vector2(-w,-h),Vector2(w*.65,-h),Vector2(w,h*.35),Vector2(-w*.55,h)])
		if _try_obstacle(candidate,index):
			encounter["obstacles"].append(obstacles.size()-1)
			return

func _try_obstacle(candidate: Dictionary, index: int) -> bool:
	# Ignore the old random scatter performed by the base generator.
	if not candidate.get("encounter",false): return false
	var p: Vector2 = candidate["pos"]
	var half: Vector2 = candidate["dimensions"]*.5
	if outside(p,0) or absf(p.x)+half.x>17.6: return false
	if p.y-half.y<10 or (finite and p.y+half.y>summit-4): return false
	for obstacle in obstacles:
		var bounds := Rect2(obstacle["pos"]-obstacle["dimensions"]*.5,obstacle["dimensions"]).grow(1.0)
		if bounds.intersects(Rect2(p-half,candidate["dimensions"])): return false
	# Test the shot lane, several hanging heights and a broad swinging envelope
	# on nearby primary transfers. Protected space also covers recovery grips.
	for step in range(maxi(0,index-3),index+4):
		var a := main_point(step)
		var b := main_point(step+1)
		var corridor := Rect2(Vector2(minf(a.x,b.x)-2.4,minf(a.y,b.y)-4.1),Vector2(absf(a.x-b.x)+4.8,absf(a.y-b.y)+5.1))
		if corridor.intersects(Rect2(p-half,candidate["dimensions"])): return false
	for id in nearby_ids(p.y-6,p.y+6):
		var grip: Vector2 = anchors[id]["pos"]
		if not SolidGeometry.cast(grip+Vector2(0,-2.7),grip,candidate,Vector2(.65,.65)).is_empty(): return false
	for find in finds:
		if not SolidGeometry.cast(find["pos"],find["pos"],candidate,Vector2(.8,.8)).is_empty(): return false
	for branch in branches:
		if not transition_clear(anchors[branch["entry"]]["pos"],anchors[branch["anchor"]]["pos"],candidate): return false
		if not transition_clear(anchors[branch["anchor"]]["pos"],branch["exit_pos"],candidate): return false
	if calibrated_routes:
		# Exits are protected from every contact the branch grip can slide to.
		for branch in branches:
			for contact in GripSpec.slide_samples(anchors[branch["anchor"]]):
				if not transition_clear(contact,branch["exit_pos"],candidate): return false
		for id in nearby_ids(p.y-6,p.y+6):
			var spring: Dictionary = anchors[id]
			if GripSpec.kind_of(spring)==GripSpec.SPRING and not transition_clear(spring["pos"],spring["pos"]+GripSpec.exit_direction(spring)*GripSpec.SPRING_LANE,candidate): return false
	var kept: Array[Vector2i] = []
	for edge in edges:
		if transition_clear(anchors[edge.x]["pos"],anchors[edge.y]["pos"],candidate): kept.append(edge)
	if not stable_network_connected(kept): return false
	edges = kept
	obstacles.append(candidate)
	return true

func transition_clear(a: Vector2, b: Vector2, extra: Dictionary = {}) -> bool:
	for object in obstacles:
		if not _transfer_clear(a,b,object): return false
	return extra.is_empty() or _transfer_clear(a,b,extra)

func _transfer_clear(a: Vector2, b: Vector2, object: Dictionary) -> bool:
	if absf(float(object["pos"].y)-(a.y+b.y)*.5)>8: return true
	for drop in [0.0,1.5,2.8]:
		if not SolidGeometry.cast(a+Vector2(0,-drop),b+Vector2(0,-drop),object,Vector2(.55,.6)).is_empty(): return false
	return true

func region_features(index: int) -> Array:
	if features.has(index): return features[index]
	var random := rng(index,208)
	var height := index*18.0+9
	var route_index := maxi(0,int(height/3.1)-2)
	while main_point(route_index).y<height: route_index += 1
	var route := main_point(route_index)
	var kind := phrase_kind(maxi(0,(route_index-2)/3))
	var result: Array = []
	# Side clefts and a movement-specific central opening give a phrase a
	# readable rock silhouette, instead of punching unrelated random holes.
	for side in [-1,1]:
		result.append({"center":Vector2(side*11.5+random.randf_range(-1.7,1.7),height+side*3.2),"size":Vector2(random.randf_range(3.8,5.4),random.randf_range(4,6)),"tilt":random.randf_range(-.55,.55)})
	var extent := Vector2(3.4,5.7) if kind==2 else Vector2(5.2,3.5) if kind==3 else Vector2(4.1,4.8)
	result.append({"center":Vector2(clampf(route.x*.45,-7,7),height-1.8),"size":extent,"tilt":.5 if kind in [0,6] else -.4})
	features[index] = result
	return result
