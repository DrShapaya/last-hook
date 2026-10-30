class_name WinterDesigner
extends LevelDesigner

# The snow peak's level masks, after references/location/winter_4k.png: one
# tall tower leaning with the wind, toothed along its flanks and crown, flat
# snow shelves wrapping its face, on wide foothills with a lesser peak beside
# it, and shards of rock hanging in the air around it.

const LEAN := .24
const TOWER_HALF := Vector2(8.5,11.0)

# Flat shelves off the tower: [x, y, half, slope, thick].
var shelves: Array = []
# Floating shards: [x, y, half, tall].
var shards: Array = []
var side_peak := Vector3.ZERO

func _forms_of(beat: String) -> Array:
	if beat=="teach": return ["wall","islands"]
	if beat=="combo": return ["traverse","wall"]
	return super._forms_of(beat)

func _split_shapes() -> Array:
	return ["ridge","diagonal","arc"]

func _sway_scale() -> float:
	return .9

func _after_plan() -> void:
	shelves.clear()
	shards.clear()
	# Shelves climb across the tower from side to side, winding up it.
	var y := 15.0
	var flank := -1.0 if random.randf()<.5 else 1.0
	while y<height-8.0:
		if split_at(y).is_empty():
			var half := random.randf_range(9.5,12.5)
			var slope := -flank*random.randf_range(.14,.24)
			shelves.append([_tower_axis(y)+flank*random.randf_range(3.0,5.0),y,half,slope,random.randf_range(2.8,3.6)])
			flank = -flank
		y += random.randf_range(9.0,14.0)
	for count in range(random.randi_range(4,6)):
		var at := random.randf_range(20.0,height-10.0)
		var side := -1.0 if random.randf()<.5 else 1.0
		var x := corridor_center(at)+side*random.randf_range(12.0,15.0)
		if absf(x)>17.0: continue
		for piece in range(random.randi_range(2,3)):
			shards.append([x+piece*2.1-2.0,at+random.randf_range(-.5,.5),random.randf_range(1.2,1.8),random.randf_range(2.6,3.6)])
	side_peak = Vector3((-1.0 if random.randf()<.5 else 1.0)*random.randf_range(10.0,13.0),random.randf_range(25.0,31.0),0.0)

# A kite-shaped shard hanging in the air, its tips up and down.
func _shard(point: Vector2, shard: Array) -> float:
	var local := point-Vector2(float(shard[0]),float(shard[1]))
	local.x += local.y*LEAN
	return 1.0-(absf(local.x)/float(shard[2])+absf(local.y)/float(shard[3]))

static func _peak(value: float) -> float:
	return 1.0-absf((value-floorf(value))*2.0-1.0)

# Teeth along every edge, raked with the wind: cones along the tops, a saw
# down the flanks.
func _spikes(point: Vector2) -> float:
	var across := Vector2(cos(LEAN),-sin(LEAN))
	var along := Vector2(sin(LEAN),cos(LEAN))
	return _peak(point.dot(across)/2.5)*2.2+_peak(point.dot(along)/5.0)*1.4-1.7

# The tower winds a little as it climbs.
func _tower_axis(y: float) -> float:
	return corridor_center(y)+sin(y/21.0+float(seed_value%7))*2.6

func _outline_at(point: Vector2) -> float:
	var top := height+1.5
	if point.y>top+3.0 or point.y< -2.0: return -10.0
	var amount: float
	if not split_at(point.y).is_empty(): amount = _shape_at(point)
	else:
		var half := lerpf(TOWER_HALF.y,TOWER_HALF.x,clampf(point.y/height,0,1))
		amount = half+noise.get_noise_2d(point.x*.8,point.y*.8)*1.2-absf(point.x-_tower_axis(point.y))
		amount = _with_features(amount,point)
	# The tower's flanks are only nicked; its crown and the arcs carry full teeth.
	var teeth := 1.4 if not split_at(point.y).is_empty() else 1.0 if point.y>top-5.0 else .45
	amount = minf(amount,top-point.y+1.0)+_spikes(point)*teeth
	for shelf in shelves:
		var dx: float = point.x-float(shelf[0])
		var thick: float = shelf[4]
		var mid: float = float(shelf[1])+float(shelf[3])*dx-thick*.5
		amount = maxf(amount,minf(float(shelf[2])-absf(dx),thick*.5-absf(point.y-mid)))
	for shard in shards: amount = maxf(amount,_shard(point,shard)*2.0)
	return _foot(point,amount)

# Foothills wider than the tower, with a lesser peak on one side.
func _foot(point: Vector2, amount: float) -> float:
	if point.y>side_peak.y+3.0: return amount
	var hill := 20.0*(1.0-clampf(point.y/17.0,0,1))+noise.get_noise_2d(point.x*.6,point.y+70.0)*2.2-absf(point.x)
	var peak := (side_peak.y-point.y)*.46-absf(point.x-side_peak.x)+_spikes(point)*.6
	return maxf(amount,maxf(hill+_spikes(point)*.5,peak))

func _dress_brief(source: LevelSource) -> void:
	source.brief["rock"] = "winter"
	source.brief["free_route"] = true
	var marks: Array = []
	for shelf in shelves: marks.append([snappedf(float(shelf[0]),.01),snappedf(float(shelf[1]),.01),snappedf(float(shelf[2]),.01),snappedf(float(shelf[3]),.001),snappedf(float(shelf[4]),.01)])
	source.brief["shelves"] = marks
