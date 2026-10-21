class_name MountainLayout
extends RefCounted

# All coordinates are in the gameplay XY plane. No renderer or physics nodes here.
const HALF_WIDTH := 18.0
const CHUNK_HEIGHT := 24.0
const ROW_HEIGHT := 2.9
const LINK_REACH := 5.25
var seed_value := 0
var location := 0
var finite := false
var summit := 120.0
var row := 0
var anchors: Array[Dictionary] = []
var main_route: Array[int] = []
var edges: Array[Vector2i] = []
var obstacles: Array[Dictionary] = []
var ledges: Array[Dictionary] = []
var finds: Array[Dictionary] = []
var bins: Dictionary = {}
var features: Dictionary = {}
var summit_added := false
var route_points: Array[Vector2] = []
var loot_values: Array = []
var gentle_intro := true
var sparse_route := true
var safe_routes := false
var rescue_anchors: Dictionary = {}
var branches: Array[Dictionary] = []
# v12: grip types come from the scenario of each movement phrase (see
# EncounterLayout), never from a per-row random roll.
var scenario_routes := false
# v13: ice slides across its grip, auxiliary grips include springs, and a
# phrase may repeat a known risk on a second detour (see EncounterLayout).
var calibrated_routes := false
static var _base_kit: Dictionary = {}

func setup(world_seed: int, biome: int) -> void:
	seed_value = world_seed
	location = biome
	ledges.append({"left":-3.5,"right":3.5,"top":.15})

func rng(index: int, stream: int) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = seed_value*7919+index*104729+stream*15485863+location*32452843
	return result

func main_point(index: int) -> Vector2:
	# Repeatable movement phrases: traverses, reversals and taller transfers.
	# The base kit reaches adjacent grips, but hanging still is not enough.
	if route_points.is_empty():
		route_points.append(Vector2(1.6*(-1 if rng(0,18).randf()<.5 else 1),4))
	while route_points.size()<=index:
		var n := route_points.size()-1
		var previous := route_points[-1]
		var zone := clampi(int(previous.y/20),0,5)
		var random := rng(n,1)
		var pattern: Array = [[1,1,-1,-1],[1,1,1,-1,-1,-1],[1,-1,1,1,-1,-1],[1,1,-1,-1],[1,1,1,-1,-1,-1],[1,-1]][zone]
		var side := -1 if rng(0,18).randf()<.5 else 1
		var dx: float = [2.5,3.0,3.3,2.8,3.5,3.65][zone]*float(pattern[n%pattern.size()])*side
		var rise: float = [2.75,2.85,2.85,3.3,2.9,3.15][zone]+random.randf_range(-.1,.1)
		if sparse_route:
			dx = [2.8,3.3,3.5,3.0,3.65,3.8][zone]*float(pattern[n%pattern.size()])*side
			rise = [2.9,3.0,3.0,3.5,3.15,3.5][zone]+random.randf_range(-.1,.1)
		# Two gentle transfers let the player learn reeling and release before traverses.
		if gentle_intro and n<2:
			dx = (1.8 if n==0 else 2.2)*side
			rise = 2.4 if n==0 else 2.65
		var x := previous.x+dx+random.randf_range(-.12,.12)
		if absf(x)>12.5: x = previous.x-dx
		route_points.append(Vector2(x,previous.y+rise))
	return route_points[index]

func outer_edge(y: float, side: int) -> float:
	var phase := float(seed_value%997)*.017+location
	return side*(HALF_WIDTH+1.4*sin(y*.11+phase+side)+.65*sin(y*.31+phase*2))

func outside(point: Vector2, margin: float = .65) -> bool:
	return point.x<outer_edge(point.y,-1)-margin or point.x>outer_edge(point.y,1)+margin

func _add_anchor(point: Vector2, kind: int, dimensions: Vector2, primary: bool = false) -> int:
	var id := anchors.size()
	var object := {"id":id,"pos":point,"kind":kind,"shape":"polygon","dimensions":dimensions,"polygon":grip_polygon(dimensions),"broken":false,"primary":primary,"role":"main" if primary else "auxiliary"}
	# A timer root is never permanent: the clock, not the release, ends it.
	object["permanent"] = (location!=0 and kind!=GripSpec.ROOT) or (GripSpec.network_kind(kind) and rng(id,91).randf()<.08)
	if kind==GripSpec.ICE: object["slide_dir"] = slide_direction_at(point)
	anchors.append(object)
	var key := int(floor(point.y/CHUNK_HEIGHT))
	if not bins.has(key):
		bins[key] = []
	bins[key].append(id)
	return id

static func grip_polygon(dimensions: Vector2) -> PackedVector2Array:
	var w := dimensions.x*.5
	var h := dimensions.y*.5
	return PackedVector2Array([Vector2(-w,-h*.25),Vector2(-w*.75,-h),Vector2(w*.72,-h),Vector2(w,h*.15),Vector2(w*.85,h),Vector2(-w*.85,h)])

func nearby_ids(low: float, high: float) -> Array[int]:
	var result: Array[int] = []
	for key in range(int(floor(low/CHUNK_HEIGHT)),int(floor(high/CHUNK_HEIGHT))+1):
		for id in bins.get(key,[]):
			result.append(id)
	return result

func generate_to(height: float, is_finite: bool, summit_height: float) -> void:
	finite = is_finite
	summit = summit_height
	# Complete a chunk plus its neighbour seam before rendering it.
	var planned_height: float = ceil(height/CHUNK_HEIGHT)*CHUNK_HEIGHT+6
	while main_point(row).y<planned_height and (not finite or main_point(row).y<summit-.8):
		_generate_row(row)
		row += 1
	if finite and height>=summit and not summit_added:
		var last: Vector2 = anchors[main_route[-1]]["pos"]
		var id := _add_anchor(Vector2(last.x,summit+.9),0,Vector2(2,.65),true)
		anchors[id]["permanent"] = true
		anchors[id]["role"] = "rest"
		edges.append(Vector2i(main_route[-1],id))
		main_route.append(id)
		ledges.append({"left":last.x-1.6,"right":last.x+1.6,"top":summit-.4})
		summit_added = true

func _generate_row(index: int) -> void:
	var random := rng(index,3)
	var point := main_point(index)
	var first_id := anchors.size()
	var kind := _main_kind(index,random)
	var id := _add_anchor(point,kind,Vector2(random.randf_range(1.6,2.1),random.randf_range(.55,.75)),true)
	anchors[id]["permanent"] = index==0 or index%9==8
	if index==0: anchors[id]["role"] = "tutorial"
	elif index%9==8: anchors[id]["role"] = "recovery"
	if kind==GripSpec.SPRING:
		# The bough throws towards the next main grip; the base kit still
		# reaches that grip without the impulse.
		anchors[id]["exit_dir"] = (main_point(index+1)-point).normalized()
	_main_created(index,id)
	if not main_route.is_empty():
		edges.append(Vector2i(main_route[-1],id))
	main_route.append(id)
	# Stratified jitter avoids empty sides; it is not a fixed ladder of platforms.
	for column in range(4 if (index%4==2 if sparse_route else index%3==1) else 0):
		var candidate := auxiliary_point(index,column,point,random)
		if candidate.distance_to(point)<1.45:
			continue
		if not branch_allowed(candidate,index): continue
		if calibrated_routes and _reserved(candidate,index): continue
		var safe := true
		for obstacle in obstacles:
			if blocked(candidate+Vector2(0,-2),candidate,obstacle,Vector2(.8,.7)):
				safe = false
		if not safe: continue
		var supported := false
		for other in anchors:
			if GripSpec.in_network(other) and transition_clear(other["pos"],candidate):
				supported = true
				break
		if not supported: continue
		var auxiliary_kind := _auxiliary_kind(random)
		if auxiliary_kind==GripSpec.SPRING and calibrated_routes and not spring_lane_clear(candidate,auxiliary_exit(candidate)): auxiliary_kind = GripSpec.STONE
		var auxiliary := _add_anchor(candidate,auxiliary_kind,Vector2(random.randf_range(1.05,1.8),random.randf_range(.45,.7)))
		if auxiliary_kind==GripSpec.SPRING and calibrated_routes: anchors[auxiliary]["exit_dir"] = auxiliary_exit(candidate)
	for new_id in range(first_id,anchors.size()):
		var new_pos: Vector2 = anchors[new_id]["pos"]
		for other_id in nearby_ids(new_pos.y-4.2,new_pos.y+4.2):
			if other_id>=new_id:
				continue
			if not GripSpec.in_network(anchors[other_id]): continue
			var other_pos: Vector2 = anchors[other_id]["pos"]
			if new_pos.distance_to(other_pos)<=LINK_REACH and transition_clear(other_pos,new_pos):
				var edge := Vector2i(other_id,new_id)
				if not edges.has(edge):
					edges.append(edge)
		# Repair isolated samples with short, supported intermediate grips.
		var has_connection := false
		for edge in edges:
			if edge.x==new_id or edge.y==new_id:
				has_connection = true
				break
		if not has_connection:
			var closest := -1
			var best_distance := INF
			var bridge_clear := false
			for other_id in range(new_id):
				var other: Dictionary = anchors[other_id]
				var distance: float = new_pos.distance_to(other["pos"])
				if not GripSpec.in_network(other) or not transition_clear(other["pos"],new_pos): continue
				# v13 prefers a bridge that keeps clear of branch grips.
				var clear := not calibrated_routes or bridge_spacious(other["pos"],new_pos)
				if (clear and not bridge_clear) or (clear==bridge_clear and distance<best_distance):
					closest = other_id
					best_distance = distance
					bridge_clear = clear
			if closest>=0:
				var start: Vector2 = anchors[closest]["pos"]
				var steps := maxi(1,int(ceil(best_distance/3.8)))
				var previous := closest
				for step in range(1,steps):
					var bridge := _add_anchor(start.lerp(new_pos,float(step)/steps),0,Vector2(1.15,.5))
					edges.append(Vector2i(previous,bridge))
					previous = bridge
				edges.append(Vector2i(previous,new_id))
	if (index%9==8 if sparse_route else index%6==4):
		ledges.append({"left":point.x-1.3,"right":point.x+1.3,"top":point.y-2.5})
	var zone := clampi(int(point.y/20),0,5)
	if index%2==0: _add_find(point+Vector2(-.25,-2.05),zone,false)
	if scenario_routes:
		_scenario_branch(index,point,id,zone)
	elif (index%4==3 if sparse_route else index%3==2):
		var side := -1 if random.randf()<.5 else 1
		if absf(point.x+side*3.8)>16: side = -side
		var bonus := point+Vector2(side*3.8,.55)
		if safe_routes:
			var exit := main_point(index+1)
			side = int(signf(exit.x-point.x)) if absf(exit.x-point.x)>.1 else side
			bonus = point+Vector2(side*3.8,.55)
			# Every loot detour rejoins ahead, after its entry has been consumed.
			if (not finite or exit.y<summit-.8) and transition_clear(point,bonus) and transition_clear(bonus,exit) and bonus.distance_to(exit)<5.25:
				var branch_id := _add_anchor(bonus,1 if zone<3 else 3,Vector2(1.3,.6))
				anchors[branch_id]["role"] = "branch"
				record_branch(id,branch_id,index+1,exit)
				_add_find(bonus+Vector2(0,-2.05),zone,true)
		else:
			var bonus_id := _add_anchor(bonus,1 if zone<3 else 3 if zone<5 else 4,Vector2(1.3,.6))
			anchors[bonus_id]["role"] = "branch"
			_add_find(bonus+Vector2(0,-2.05),zone,true)
	if index>2:
		for attempt in range(3):
			var candidate := {"pos":Vector2(random.randf_range(-15.5,15.5),point.y+random.randf_range(.6,1.5)),"dimensions":Vector2(random.randf_range(.7,1.5),random.randf_range(.8,1.8))}
			if _try_obstacle(candidate,index):
				break
	if safe_routes and not anchors[id]["permanent"]:
		# Separate, dormant hardware: normal grips are never restored by revival.
		var reserve := _add_anchor(point+Vector2(0,-.2),0,anchors[id]["dimensions"])
		anchors[reserve]["reserve"] = true
		anchors[reserve]["role"] = "recovery"
		anchors[reserve]["permanent"] = false
		anchors[reserve]["broken"] = true
		rescue_anchors[id] = reserve

# --- Type assignment hooks ------------------------------------------------------
# Older generators keep their random rolls so saved attempts regenerate
# exactly. Scenario routes still consume each roll, which keeps grip sizes and
# auxiliary positions identical to v11, but ignore it for the type.

func _main_kind(index: int, random: RandomNumberGenerator) -> int:
	var roll := random.randf() if index>1 else 1.0
	return GripSpec.SPRING if roll<.2 else GripSpec.STONE

# Intermediate repair grips between two points stay out of the space of
# optional branch and reward grips.
func bridge_spacious(start: Vector2, end: Vector2) -> bool:
	var steps := maxi(1,int(ceil(start.distance_to(end)/3.8)))
	for step in range(1,steps):
		var point := start.lerp(end,float(step)/steps)
		for id in nearby_ids(point.y-2,point.y+2):
			if GripSpec.role(anchors[id]) in ["branch","reward"] and anchors[id]["pos"].distance_to(point)<RouteGraph.GRIP_SPACING: return false
	return true

func _auxiliary_kind(random: RandomNumberGenerator) -> int:
	var roll := random.randf()
	if calibrated_routes: return GripSpec.SPRING if roll<.15 else GripSpec.STONE
	if scenario_routes: return GripSpec.STONE
	return GripSpec.SPRING if roll<.17 else GripSpec.STONE

# An auxiliary bough throws up and in, towards the route.
func auxiliary_exit(point: Vector2) -> Vector2:
	return Vector2(-signf(point.x)*.5,1).normalized()

# The spring's throw neither rises into rock nor points at the fall zone.
func spring_lane_clear(point: Vector2, direction: Vector2, extra: Dictionary = {}) -> bool:
	return direction.y>.2 and not outside(point+direction*GripSpec.SPRING_LANE,0) and transition_clear(point,point+direction*GripSpec.SPRING_LANE,extra)

func _main_created(_index: int, _id: int) -> void:
	pass

func _scenario_branch(_index: int, _point: Vector2, _entry: int, _zone: int) -> void:
	pass

# Spots a scenario branch of this row will want; auxiliary grips leave them free.
func branch_spots(_index: int) -> Array[Vector2]:
	return []

func _reserved(point: Vector2, index: int) -> bool:
	for spot in branch_spots(index):
		if spot.distance_to(point)<RouteGraph.GRIP_SPACING+.2: return true
	return false

# Base kit from balance.json: the shortest rope, slowest throw and gravity.
static func base_kit() -> Dictionary:
	if _base_kit.is_empty():
		var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
		_base_kit = {"rope":float(balance["rope_lengths"][0]),"throw":float(balance["throw_speeds"][0]),"gravity":float(balance["gravity"])}
	return _base_kit

# Time to leave a grip for a target with the base kit: at most half a swing
# to face the target, then the throw itself.
static func exit_seconds(from: Vector2, to: Vector2) -> float:
	var kit := base_kit()
	return PI*sqrt(float(kit["rope"])/float(kit["gravity"]))+from.distance_to(to)/float(kit["throw"])

func slide_direction_at(point: Vector2) -> Vector2:
	if not calibrated_routes: return Vector2.DOWN
	return GripSpec.lateral_slide(-signf(point.x) if absf(point.x)>.05 else 1.0)

# Directed record of an optional branch. Exits are stored as main rows (their
# grips may not exist yet) or reward grips; `hazard_state` is what the branch
# grip does to the player before an exit: a running clock, a slide, a throw
# or a choice. A timed or sliding branch has only a risky exit.
func record_branch(entry: int, grip: int, exit_row: int, exit_pos: Vector2, scenario: String = "", reward: int = -1) -> Dictionary:
	var hazard: String = {GripSpec.ROOT:"timer",GripSpec.ICE:"slide",GripSpec.SPRING:"impulse",GripSpec.CRYSTAL:"choice"}.get(GripSpec.kind_of(anchors[grip]),"none")
	var exits: Array = [{"row":exit_row,"pos":exit_pos,"kind":"main"}]
	if reward>=0: exits.append({"anchor":reward,"pos":anchors[reward]["pos"],"kind":"reward"})
	var risky := hazard in ["timer","slide"]
	var record := {"entry":entry,"entry_consumed":not anchors[entry]["permanent"],"anchor":grip,"candidate_exits":exits,
		"safe_exit":-1 if risky else exit_row,"risky_exit":exit_row if risky else -1,"reward_exit":reward,
		"exit_row":exit_row,"exit_pos":exit_pos,"hazard_state":hazard}
	if not scenario.is_empty(): record["scenario"] = scenario
	branches.append(record)
	return record

# Directed exit check from a grip, after its own effect: a root must be left
# before its clock ends, ice must reach the target from every slide position.
func exit_reachable(object: Dictionary, target: Vector2, reach: float = LINK_REACH) -> bool:
	for contact in GripSpec.slide_samples(object):
		if contact.distance_to(target)>=reach or not transition_clear(contact,target): return false
		if GripSpec.timed(object) and exit_seconds(contact,target)>GripSpec.ROOT_SECONDS: return false
	return true

func auxiliary_point(_index: int, column: int, point: Vector2, random: RandomNumberGenerator) -> Vector2:
	var candidate := Vector2(-15.6+column*10.4+random.randf_range(-.35,.35),point.y+random.randf_range(-.6,.6))
	candidate.x = clampf(candidate.x,outer_edge(candidate.y,-1)+1,outer_edge(candidate.y,1)-1)
	return candidate

func branch_allowed(point: Vector2, index: int) -> bool:
	# Keep auxiliary grips out of the primary shot and swing corridor.
	for step in range(maxi(0,index-1),index+2):
		if RopeSim.hit_capsule(point,point,main_point(step),main_point(step+1),2.0)>=0:
			return false
	return true

func _add_find(point: Vector2, zone: int, rare: bool) -> void:
	if loot_values.is_empty():
		var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
		loot_values = balance["loot_values"]
	var value := int(float(loot_values[zone])*(1.8 if rare else 1.0))
	var kinds := ["coin", "amber", "crown", "chalice", "idol", "star"]
	var kind: String = str(kinds[clampi(zone,0,kinds.size()-1)])
	# Rare finds become named relics instead of only being a larger value.
	if rare and zone==1: kind = "crown"
	if rare and zone==3: kind = "chalice"
	if rare and zone==4: kind = "idol"
	finds.append({"item":{"id":finds.size(),"tier":zone,"value":value,"kind":kind},"pos":point,"picked":false,"rare":rare})

static func blocked(a: Vector2, b: Vector2, object: Dictionary, padding: Vector2 = Vector2.ZERO) -> bool:
	var half: Vector2 = object["dimensions"]*.5+padding
	var center: Vector2 = object["pos"]
	return RopeSim.hit_polygon(a,b,PackedVector2Array([center-half,center+Vector2(half.x,-half.y),center+half,center+Vector2(-half.x,half.y)]))>=0

func transition_clear(a: Vector2, b: Vector2, extra: Dictionary = {}) -> bool:
	for object in obstacles:
		if absf(float(object["pos"].y)-(a.y+b.y)*.5)>7:
			continue
		if blocked(a,b,object,Vector2(.45,.55)) or blocked(a+Vector2(0,-1.5),b+Vector2(0,-1.5),object,Vector2(.45,.55)):
			return false
	return extra.is_empty() or (not blocked(a,b,extra,Vector2(.45,.55)) and not blocked(a+Vector2(0,-1.5),b+Vector2(0,-1.5),extra,Vector2(.45,.55)))

func _try_obstacle(candidate: Dictionary, index: int) -> bool:
	# Protect space below and beside the main route, not merely the centre ray.
	for step in range(maxi(0,index-2),index+3):
		var a := main_point(step)
		var b := main_point(step+1)
		var rect := Rect2(Vector2(minf(a.x,b.x)-2.5,minf(a.y,b.y)-4.5),Vector2(absf(a.x-b.x)+5,absf(a.y-b.y)+5.5))
		if rect.intersects(Rect2(candidate["pos"]-candidate["dimensions"]*.5,candidate["dimensions"])):
			return false
	for branch in branches:
		if not transition_clear(anchors[branch["entry"]]["pos"],anchors[branch["anchor"]]["pos"],candidate) or not transition_clear(anchors[branch["anchor"]]["pos"],branch["exit_pos"],candidate):
			return false
	for id in nearby_ids(candidate["pos"].y-5,candidate["pos"].y+5):
		var p: Vector2 = anchors[id]["pos"]
		if blocked(p+Vector2(0,-2),p,candidate,Vector2(.65,.65)):
			return false
	var kept: Array[Vector2i] = []
	for edge in edges:
		if transition_clear(anchors[edge.x]["pos"],anchors[edge.y]["pos"],candidate):
			kept.append(edge)
	if not stable_network_connected(kept):
		return false
	edges = kept
	obstacles.append(candidate)
	return true

func stable_network_connected(links: Array[Vector2i]) -> bool:
	if main_route.is_empty():
		return true
	var adjacency: Dictionary = {}
	for edge in links:
		if not adjacency.has(edge.x): adjacency[edge.x] = []
		if not adjacency.has(edge.y): adjacency[edge.y] = []
		adjacency[edge.x].append(edge.y)
		adjacency[edge.y].append(edge.x)
	var reached := {main_route[0]:true}
	var queue: Array[int] = [main_route[0]]
	var cursor := 0
	while cursor<queue.size():
		var id := queue[cursor]
		cursor += 1
		for neighbour in adjacency.get(id,[]):
			if not reached.has(neighbour) and GripSpec.in_network(anchors[neighbour]):
				reached[neighbour] = true
				queue.append(neighbour)
	for object in anchors:
		if GripSpec.in_network(object) and not reached.has(object["id"]):
			return false
	return true

func region_features(index: int) -> Array:
	if features.has(index): return features[index]
	var random := rng(index,50)
	var result: Array = []
	for n in range(3):
		result.append({"center":Vector2(-10+n*10+random.randf_range(-3,3),index*18+random.randf_range(3,15)),"size":Vector2(random.randf_range(3.2,5.4),random.randf_range(3.2,6)),"tilt":random.randf_range(-.9,.9)})
	features[index] = result
	return result

func rock_field(point: Vector2) -> float:
	var result := minf(point.x-outer_edge(point.y,-1),outer_edge(point.y,1)-point.x)
	if finite: result = minf(result,summit+.15-point.y)
	result = minf(result,point.y+2)
	for region in range(int(floor(point.y/18))-1,int(floor(point.y/18))+2):
		for feature in region_features(region):
			var delta: Vector2 = point-feature["center"]
			var extent: Vector2 = feature["size"]
			var hole: float
			var angled := Vector2(delta.x+delta.y*feature["tilt"],delta.y)
			hole = (absf(angled.x)/extent.x+absf(angled.y)/extent.y-1)*minf(extent.x,extent.y)
			result = minf(result,hole)
	# Small natural footholds remain where a route crosses a large opening.
	for id in nearby_ids(point.y-2,point.y+2):
		var object: Dictionary = anchors[id]
		var delta: Vector2 = point-object["pos"]+Vector2(0,.45)
		var radius := Vector2(object["dimensions"].x*.8,.95)
		if absf(delta.x)<radius.x and absf(delta.y)<radius.y:
			result = maxf(result,(1-(delta/radius).length())*.8)
	return result
