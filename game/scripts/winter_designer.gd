class_name WinterDesigner
extends LevelDesigner

# The snow peak's level masks, after references/location/winter_4k.png: one
# tall tower leaning with the wind, its flanks rough but never toothed; thick
# snow shelves winding up round it the same way, as a spiral seen from the
# front; loops and arms of rock bowing out beside it, cones along their tops;
# a stepped crown with cones; wide foothills with a lesser peak beside it; and
# islands of rock hanging in the air, flat on top, pointed below.

const LEAN := .24
const TOWER_HALF := Vector2(8.5,11.0)
# Units a split takes to grow out of the tower.
const SPLIT_MELT := 4.0
# Spacing of the cones along a loop or the crown, and the width of a crown step.
const TOOTH_STEP := 2.9
const CROWN_STEP := 4.5
const CROWN_DROP := 2.2
# The summit keeps a flat top this far either side of the route.
const SUMMIT_CLEAR := 3.2

# Shelves off the tower: [x, y, half, slope, thick].
var shelves: Array = []
# Islands in the air: [x, y, half, tall, cap].
var shards: Array = []
var side_peak := Vector3.ZERO
# One giant leaning horn beside each act: [x, y0, y1, half].
var horns: Array = []
# Cones on the tops of loops and the crown: [base, direction, tall, half].
var teeth: Array = []
var summit_x := 0.0
# The tower's axis, smoothed, every AXIS_STEP units from AXIS_FROM.
var axis_table := PackedFloat32Array()
const AXIS_FROM := -6.0
const AXIS_STEP := .25
const AXIS_SMOOTH := 12

func _forms_of(beat: String) -> Array:
	if beat=="teach": return ["wall","islands"]
	if beat=="combo": return ["traverse","wall"]
	return super._forms_of(beat)

# Loops bow out and back; arms slant out and come back level.
func _split_shapes() -> Array:
	return ["arc","diagonal"]

func _sway_scale() -> float:
	return .9

func _split_risk() -> String:
	return "blizzard_gust"

func _after_plan() -> void:
	# The tower has no windows: its sky is beside it, inside the loops.
	# Round lumps beside the trunk become islands of the peak's own shape.
	var lumps: Array = []
	for section in sections:
		if str(section["form"])=="islands":
			for feature in section["features"]:
				if str(feature[0])=="add": lumps.append(feature)
		section["features"] = (section["features"] as Array).filter(func(feature: Array) -> bool: return str(feature[0]) in ["rest","solid"] or (str(feature[0])=="add" and str(section["form"])!="islands"))
	_plan_axis()
	summit_x = corridor_center(height)
	_plan_shelves()
	_plan_islands()
	for lump in lumps:
		var at: Vector2 = lump[1]
		if _split_near(at.y).is_empty(): _add_island(at.x,at.y,(lump[2] as Vector2).x)
	horns.clear()
	var third := height/3.0
	for act in range(3):
		var foot := third*act+random.randf_range(6.0,third*.45)
		if not _split_near(foot+8.0).is_empty(): foot = maxf(8.0,foot-8.0)
		var side := -1.0 if act%2==0 else 1.0
		var x := clampf(_tower_axis(foot)+side*random.randf_range(11.0,13.0),-15.0,13.0)
		horns.append([x,foot,foot+random.randf_range(16.0,22.0),random.randf_range(2.8,3.6)])
	side_peak = Vector3((-1.0 if random.randf()<.5 else 1.0)*random.randf_range(10.0,13.0),random.randf_range(25.0,31.0),0.0)
	# The acts' own dangers on their far ways: none while the first act
	# teaches the choice, falling ice in the crevasse, gusts at the crown.
	for index in range(splits.size()):
		if index==1: splits[index]["risk"] = "icicle"
	teeth.clear()
	for split in splits: _plan_loop_teeth(split)
	_plan_crown_teeth()

# Shelves all rise the same way across the tower, turn after turn, so they
# read as one ledge winding up round it. Some span the tower and stand out on
# both sides, some only jut from one flank.
func _plan_shelves() -> void:
	shelves.clear()
	var rise := -1.0 if random.randf()<.5 else 1.0
	var y := 14.0
	while y<height-12.0:
		var thick := random.randf_range(2.6,3.4)
		var axis := _tower_axis(y)
		var half_tower := lerpf(TOWER_HALF.y,TOWER_HALF.x,clampf(y/height,0,1))
		var shelf: Array
		if random.randf()<.6: shelf = [axis+random.randf_range(-1.0,1.0),y,half_tower+random.randf_range(2.0,3.5),rise*random.randf_range(.16,.24),thick]
		else:
			var flank := -1.0 if random.randf()<.5 else 1.0
			shelf = [axis+flank*random.randf_range(half_tower*.55,half_tower*.8),y,random.randf_range(6.0,8.0),rise*random.randf_range(.12,.2),thick]
		var reach := float(shelf[2])*absf(float(shelf[3]))
		var split := _split_near(y)
		if not split.is_empty():
			# Within a split a shelf stands on the main ridge and juts away
			# from the far way, so the gap between them stays open.
			var side := float(split["side"])
			var half := random.randf_range(4.5,6.0)
			shelf = [float(split["main_x"])-side*(half-2.0),y,half,rise*random.randf_range(.1,.16),thick]
			reach = half*absf(float(shelf[3]))
		elif not _split_near(y-reach-thick).is_empty() or not _split_near(y+reach).is_empty():
			y += 3.0
			continue
		if absf(float(shelf[0]))+float(shelf[2])<19.0:
			shelves.append(shelf)
			y += random.randf_range(10.0,14.0)
		else: y += 3.0

# Islands of two or three blocks side by side, in the open air off the tower.
func _plan_islands() -> void:
	shards.clear()
	for count in range(random.randi_range(4,6)):
		var at := random.randf_range(20.0,height-10.0)
		var side := -1.0 if random.randf()<.5 else 1.0
		var x := corridor_center(at)+side*random.randf_range(12.5,15.0)
		if absf(x)>17.0 or not _split_near(at).is_empty(): continue
		_add_island(x,at,random.randf_range(2.6,3.4))

# An island of two or three blocks side by side about a point, `wide` units
# to either side.
func _add_island(x: float, y: float, wide: float) -> void:
	# A big middle block, smaller ones beside it standing a little higher.
	var middle := wide*random.randf_range(.5,.6)
	shards.append([x,y,middle,middle*random.randf_range(1.8,2.3),random.randf_range(1.0,1.4)])
	for flank in [-1.0,1.0]:
		if random.randf()<.25: continue
		var half := middle*random.randf_range(.5,.7)
		shards.append([x+flank*(middle+half*.6),y+random.randf_range(.2,.8),half,half*random.randf_range(1.6,2.2),random.randf_range(.6,1.0)])

# Cones stand along the top of a loop or an arm, leaning with the wind, where
# its band runs flat enough to have a top.
func _plan_loop_teeth(split: Dictionary) -> void:
	var path: Array = split["path"]
	var band := float(split.get("band",2.2))
	var start: Vector2 = path[0]
	var finish: Vector2 = path[path.size()-1]
	var walked := random.randf_range(0.0,TOOTH_STEP)
	for k in range(1,path.size()):
		var a: Vector2 = path[k-1]
		var b: Vector2 = path[k]
		var length := a.distance_to(b)
		while walked<length:
			var at := a.lerp(b,walked/length)
			walked += TOOTH_STEP*random.randf_range(.85,1.2)
			var along := (b-a)/length
			var normal := Vector2(-along.y,along.x)
			if normal.y<0.0: normal = -normal
			if normal.y<.55 or at.distance_to(start)<3.5 or at.distance_to(finish)<3.5: continue
			var up := (normal*.5+Vector2(sin(LEAN),cos(LEAN))*.5).normalized()
			teeth.append([at+normal*band*.6,up,random.randf_range(2.2,3.0),random.randf_range(1.2,1.5)])
		walked -= length

# The crown steps down from the summit to either side, cones along each step;
# the summit itself stays flat for the finish.
func _plan_crown_teeth() -> void:
	var x := -20.0+random.randf_range(0.0,TOOTH_STEP)
	while x<20.0:
		if absf(x-summit_x)>SUMMIT_CLEAR and _crown_inside(x):
			teeth.append([Vector2(x,_crown(x)-.3),Vector2(sin(LEAN),cos(LEAN)),random.randf_range(2.4,3.4),random.randf_range(1.3,1.6)])
		x += TOOTH_STEP*random.randf_range(.9,1.15)

func _crown_inside(x: float) -> bool:
	var y := _crown(x)-.6
	return _tower(Vector2(x,y))>.8

# Height of the crown's top over a column: steps falling away from the summit.
func _crown(x: float) -> float:
	var s := absf(x-summit_x)/CROWN_STEP
	var steps := floorf(s)+smoothstep(.7,1.0,s-floorf(s))
	return height+1.5-steps*CROWN_DROP

# The tower winds a little as it climbs, round the route but never stepping
# where the route's sections meet.
func _plan_axis() -> void:
	var raw := PackedFloat32Array()
	var count := int((height+16.0-AXIS_FROM)/AXIS_STEP)
	for index in range(count):
		var y := AXIS_FROM+index*AXIS_STEP
		raw.append(corridor_center(y)+sin(y/21.0+float(seed_value%7))*2.6)
	for pass_index in range(2):
		var smooth := PackedFloat32Array()
		smooth.resize(count)
		for index in range(count):
			var total := 0.0
			for k in range(-AXIS_SMOOTH,AXIS_SMOOTH+1): total += raw[clampi(index+k,0,count-1)]
			smooth[index] = total/(AXIS_SMOOTH*2+1)
		raw = smooth
	axis_table = raw

func _tower_axis(y: float) -> float:
	var at := clampf((y-AXIS_FROM)/AXIS_STEP,0.0,axis_table.size()-1.001)
	var index := int(at)
	return lerpf(axis_table[index],axis_table[index+1],at-index)

# The tower: broad, leaning, its flanks rough with blocks but no teeth.
func _tower(point: Vector2) -> float:
	var half := lerpf(TOWER_HALF.y,TOWER_HALF.x,clampf(point.y/height,0,1))
	var rough := noise.get_noise_2d(point.x*.3,point.y*.35)*1.6+noise.get_noise_2d(point.x*1.1+40.0,point.y*1.1)*.4
	return half+rough-absf(point.x-_tower_axis(point.y))

func _split_weight(y: float, split: Dictionary) -> float:
	return smoothstep(float(split["y0"])-1.0-SPLIT_MELT,float(split["y0"])-1.0,y)*(1.0-smoothstep(float(split["y1"])+1.0,float(split["y1"])+1.0+SPLIT_MELT,y))

func _split_near(y: float) -> Dictionary:
	for split in splits:
		if y>float(split["y0"])-1.0-SPLIT_MELT and y<float(split["y1"])+1.0+SPLIT_MELT: return split
	return {}

# An island block: a flat snowy top, the sides tapering to a point below.
func _island(point: Vector2, shard: Array) -> float:
	var local := point-Vector2(float(shard[0]),float(shard[1]))
	local.x -= local.y*LEAN*.3
	var half := float(shard[2])
	if local.y>=0.0: return minf(half-absf(local.x)-local.y*.3,float(shard[4])-local.y)
	return half*(1.0-pow(-local.y/float(shard[3]),1.8))-absf(local.x)

# A cone, its foot sunk a unit into the rock it stands on.
static func _tooth(point: Vector2, tooth: Array) -> float:
	var local: Vector2 = point-(tooth[0] as Vector2)
	var up: Vector2 = tooth[1]
	var along := local.dot(up)
	var tall := float(tooth[2])
	if along< -1.0 or along>tall: return -INF
	var across := absf(local.dot(Vector2(up.y,-up.x)))
	return minf(float(tooth[3])*(1.0-maxf(along,0.0)/tall)-across,along+1.0)

func _outline_at(point: Vector2) -> float:
	var top := height+1.5
	if point.y>top+4.0 or point.y< -2.0: return -10.0
	var amount := _with_features(_tower(point),point)
	var split := _split_near(point.y)
	if not split.is_empty():
		# The tower stands whole on the side away from the far way; towards
		# it, only the main ridge, then sky, then the loop.
		var toward := (point.x-float(split["main_x"]))*float(split["side"])
		var parted := maxf(_split_inside(point,split,top+4.0),minf(amount,float(split.get("ridge",5.0))-toward))
		amount = lerpf(amount,parted,_split_weight(point.y,split))
	amount = minf(amount,_crown(point.x)-point.y)
	if point.y<=height: amount = maxf(amount,_route_stone(point))
	for shelf in shelves:
		var dx: float = point.x-float(shelf[0])
		var thick: float = shelf[4]
		var mid: float = float(shelf[1])+float(shelf[3])*dx-thick*.5
		amount = maxf(amount,minf(float(shelf[2])-absf(dx),thick*.5-absf(point.y-mid)))
	for shard in shards: amount = maxf(amount,_island(point,shard))
	for horn in horns:
		var y0: float = horn[1]
		var y1: float = horn[2]
		if point.y>=y0-1.0 and point.y<=y1:
			var rise: float = clampf((point.y-y0)/(y1-y0),0,1)
			var waist: float = float(horn[3])*(1.0-rise)*minf(1.0,(point.y-y0+1.0)/2.0)
			amount = maxf(amount,waist-absf(point.x-float(horn[0])-LEAN*(point.y-y0)))
	for tooth in teeth: amount = maxf(amount,_tooth(point,tooth))
	return _foot(point,amount)

# Foothills wider than the tower, with a lesser peak on one side.
func _foot(point: Vector2, amount: float) -> float:
	if point.y>side_peak.y+3.0: return amount
	var hill := 20.0*(1.0-clampf(point.y/17.0,0,1))+noise.get_noise_2d(point.x*.4,point.y*.5+70.0)*2.0-absf(point.x)
	var peak := (side_peak.y-point.y)*.46-absf(point.x-side_peak.x)+noise.get_noise_2d(point.x*.5+30.0,point.y*.5)*.8
	return maxf(amount,maxf(hill,peak))

func _dress_brief(source: LevelSource) -> void:
	source.brief["rock"] = "winter"
	source.brief["free_route"] = true
	var marks: Array = []
	for shelf in shelves: marks.append([snappedf(float(shelf[0]),.01),snappedf(float(shelf[1]),.01),snappedf(float(shelf[2]),.01),snappedf(float(shelf[3]),.001),snappedf(float(shelf[4]),.01)])
	source.brief["shelves"] = marks
