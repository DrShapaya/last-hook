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
	var object := {"id":id,"pos":point,"kind":kind,"shape":"polygon","dimensions":dimensions,"polygon":grip_polygon(dimensions),"broken":false,"primary":primary}
	object["permanent"] = location!=0 or (kind in [0,2] and rng(id,91).randf()<.08)
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
		edges.append(Vector2i(main_route[-1],id))
		main_route.append(id)
		ledges.append({"left":last.x-1.6,"right":last.x+1.6,"top":summit-.4})
		summit_added = true

func _generate_row(index: int) -> void:
	var random := rng(index,3)
	var point := main_point(index)
	var first_id := anchors.size()
	var kind := 2 if index>1 and random.randf()<.2 else 0
	var id := _add_anchor(point,kind,Vector2(random.randf_range(1.6,2.1),random.randf_range(.55,.75)),true)
	anchors[id]["permanent"] = index==0 or index%9==8
	if not main_route.is_empty():
		edges.append(Vector2i(main_route[-1],id))
	main_route.append(id)
	# Stratified jitter avoids empty sides; it is not a fixed ladder of platforms.
	for column in range(4 if (index%4==2 if sparse_route else index%3==1) else 0):
		var candidate := Vector2(-15.6+column*10.4+random.randf_range(-.35,.35),point.y+random.randf_range(-.6,.6))
		candidate.x = clampf(candidate.x,outer_edge(candidate.y,-1)+1,outer_edge(candidate.y,1)-1)
		if candidate.distance_to(point)<1.45:
			continue
		if not branch_allowed(candidate,index): continue
		var safe := true
		for obstacle in obstacles:
			if blocked(candidate+Vector2(0,-2),candidate,obstacle,Vector2(.8,.7)):
				safe = false
		if not safe: continue
		var supported := false
		for other in anchors:
			if other["kind"] in [0,2] and transition_clear(other["pos"],candidate):
				supported = true
				break
		if not supported: continue
		_add_anchor(candidate,2 if random.randf()<.17 else 0,Vector2(random.randf_range(1.05,1.8),random.randf_range(.45,.7)))
	for new_id in range(first_id,anchors.size()):
		var new_pos: Vector2 = anchors[new_id]["pos"]
		for other_id in nearby_ids(new_pos.y-4.2,new_pos.y+4.2):
			if other_id>=new_id:
				continue
			if anchors[other_id]["kind"] not in [0,2]: continue
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
			for other_id in range(new_id):
				var other: Dictionary = anchors[other_id]
				var distance: float = new_pos.distance_to(other["pos"])
				if other["kind"] in [0,2] and distance<best_distance and transition_clear(other["pos"],new_pos):
					closest = other_id
					best_distance = distance
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
	if (index%4==3 if sparse_route else index%3==2):
		var side := -1 if random.randf()<.5 else 1
		if absf(point.x+side*3.8)>16: side = -side
		var bonus := point+Vector2(side*3.8,.55)
		_add_anchor(bonus,1 if zone<3 else 3 if zone<5 else 4,Vector2(1.3,.6))
		_add_find(bonus+Vector2(0,-2.05),zone,true)
	if index>2:
		for attempt in range(3):
			var candidate := {"pos":Vector2(random.randf_range(-15.5,15.5),point.y+random.randf_range(.6,1.5)),"dimensions":Vector2(random.randf_range(.7,1.5),random.randf_range(.8,1.8))}
			if _try_obstacle(candidate,index):
				break

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
	finds.append({"item":{"id":finds.size(),"tier":zone,"value":value},"pos":point,"picked":false,"rare":rare})

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
			if not reached.has(neighbour) and anchors[neighbour]["kind"] in [0,2]:
				reached[neighbour] = true
				queue.append(neighbour)
	for object in anchors:
		if object["kind"] in [0,2] and not reached.has(object["id"]):
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
