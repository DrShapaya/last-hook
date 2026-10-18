class_name EncounterLayout
extends MountainLayout

const NAMES := ["Траверс","Смена дуги","Колодец","Длинный перелёт","Карман отдыха","Каменные ворота","Карниз","Обход за находкой"]
const HORIZONTAL := [[2.8,3.0,2.7],[3.0,-3.1,-2.7],[1.65,-1.9,1.7],[3.6,3.7,-2.8],[2.7,1.7,-2.6],[3.1,3.0,-3.2],[2.7,-2.9,3.2],[3.3,3.1,-3.0]]
const VERTICAL := [[2.85,2.95,3.0],[3.0,2.85,3.1],[3.65,3.7,3.55],[2.65,2.8,3.0],[2.9,3.4,2.8],[2.95,3.1,3.15],[3.25,3.05,3.15],[3.0,3.0,3.1]]
const REST_DROP := 3.7
const REST_GAP := 18.0
var encounters: Array[Dictionary] = []
var phrase_bags: Dictionary = {}

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

func _generate_row(index: int) -> void:
	var ledges_before := ledges.size()
	super._generate_row(index)
	# Rest belongs to a movement phrase, with a minimum separation and a cap;
	# it is not another evenly spaced ladder of permanent platforms.
	ledges.resize(ledges_before)
	var kind := phrase_kind(maxi(0,(index-2)/3))
	var point := main_point(index)
	var last_top: float = ledges[-1]["top"]
	if index>3 and (kind==4 or index%9==8) and point.y-REST_DROP-last_top>=REST_GAP and (not finite or ledges.size()<6) and (not finite or point.y<summit-5):
		ledges.append({"left":point.x-1.4,"right":point.x+1.4,"top":point.y-REST_DROP,"style":int(rng(index,330).randi_range(0,2)),"anchor_row":index})
		anchors[main_route[-1]]["permanent"] = true
	if index>=2 and (index-2)%3==0:
		var block := (index-2)/3
		var encounter := {"row":index,"kind":kind,"name":NAMES[kind],"entry":main_route[-1],"obstacles":[]}
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
