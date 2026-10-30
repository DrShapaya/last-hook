class_name DesertDesigner
extends LevelDesigner

# The canyon's level masks, after references/location/desert_4k.png: wide
# rounded ledges stacked over pinched walls, arches and windows through them,
# pillars with caps, lenses of rock hanging off the sides. Each act sweeps
# from side to side across its benches.

const LEDGE_HALF := Vector2(13.0,17.0)
const WALL_HALF := Vector2(7.5,10.5)

# Bottom-up: [y0, y1, half, center, kind, skew]; kind 0 a wall, 1 a ledge. A
# positive skew moves both edges right, so no tier sits square on the last.
var tiers: Array = []
# Rocks hanging under the ledges: [x, y, half, tall].
var drops: Array = []
# Standing pillars: [x, y0, y1, half, phase].
var pillars: Array = []
# Round windows of sky: [center, radii].
var windows: Array = []

func _forms_of(beat: String) -> Array:
	if beat=="teach": return ["wall","islands"]
	if beat=="combo": return ["traverse","islands"]
	return super._forms_of(beat)

func _split_shapes() -> Array:
	return ["butte","ledge","stones"]

func _sway_scale() -> float:
	return 1.2

func _split_risk() -> String:
	return "sand_storm"

func _finish_of(form: String, center: float, finish: float, _span: float) -> float:
	if form=="neck": return finish
	return (-signf(center) if absf(center)>.5 else 1.0)*random.randf_range(3.5,7.5)

func _after_plan() -> void:
	tiers.clear()
	pillars.clear()
	windows.clear()
	drops.clear()
	var y := -2.0
	var ledge := false
	while y<height+8.0:
		var thick := random.randf_range(1.8,3.2) if ledge else random.randf_range(7.0,14.0)
		var range_half := LEDGE_HALF if ledge else WALL_HALF
		var half := random.randf_range(range_half.x,range_half.y)
		if y>height-14.0: half = minf(half,8.0)
		var center := clampf(corridor_center(minf(y+thick*.5,height))*.6+random.randf_range(-2.5,2.5),half-18.0,18.0-half)
		tiers.append([y,y+thick,half,center,1 if ledge else 0,random.randf_range(-3.0,3.0)])
		if ledge and random.randf()<.45:
			var flank := -1.0 if random.randf()<.5 else 1.0
			drops.append([center+flank*half*random.randf_range(.55,.8),y-1.5,random.randf_range(1.8,2.8),random.randf_range(3.0,5.0)])
		if not ledge and thick>9.0:
			var flank := -1.0 if random.randf()<.5 else 1.0
			if random.randf()<.6: windows.append([Vector2(center+flank*half*.55,y+thick*.48),Vector2(random.randf_range(2.0,3.4),thick*.34)])
			var x := center-flank*(half+random.randf_range(1.5,4.0))
			if absf(x)<17.5: pillars.append([x,y-1.0,y+thick*random.randf_range(.6,1.0),random.randf_range(1.4,2.4),random.randf()*TAU])
		y += thick
		ledge = not ledge
	_add_gates()

# One great gate through the rock in every act, the place it is remembered by.
func _add_gates() -> void:
	var step := height/3.0
	for act in range(3):
		var best: Array = []
		for tier in tiers:
			var middle := (float(tier[0])+float(tier[1]))*.5
			if int(tier[4])==0 and middle>=step*act and middle<step*(act+1) and split_at(middle).is_empty() and (best.is_empty() or float(tier[1])-float(tier[0])>float(best[1])-float(best[0])): best = tier
		if best.is_empty(): continue
		var thick: float = float(best[1])-float(best[0])
		var at := Vector2(float(best[3])+float(best[5]),float(best[0])+thick*.46)
		windows.append([at+Vector2(random.randf_range(-3.0,3.0),0),Vector2(random.randf_range(3.6,4.8),thick*.4)])

func _tier_at(y: float) -> Array:
	for tier in tiers:
		if y<float(tier[1]): return tier
	return tiers[-1]

func _pillar(point: Vector2, pillar: Array) -> float:
	var y0: float = pillar[1]
	var y1: float = pillar[2]
	if point.y<y0 or point.y>y1: return -INF
	var half := float(pillar[3])*(.74+.26*sin((point.y-y0)*.8+float(pillar[4])))
	if point.y>y1-1.2: half = float(pillar[3])*1.35
	return minf(half-absf(point.x-float(pillar[0])),y1-point.y)

# A rock hanging from a ledge, wide at its root, coming to a blunt point.
func _drop(point: Vector2, drop: Array) -> float:
	var fall := (float(drop[1])-point.y)/float(drop[3])
	if fall< -.3 or fall>1.0: return -INF
	return float(drop[2])*(1.0-pow(absf(fall-.15),1.4))-absf(point.x-float(drop[0]))

func _outline_at(point: Vector2) -> float:
	if not split_at(point.y).is_empty(): return _foot(point,_shape_at(point))
	var top := height+1.5
	if point.y>top+.5 or point.y< -2.0: return -10.0
	var tier := _tier_at(point.y)
	var wobble := noise.get_noise_2d(point.x*.3,point.y*.45)*3.0
	var rise := (point.y-float(tier[0]))/(float(tier[1])-float(tier[0]))
	var edge: float = float(tier[2])
	# A wall curves in to a waist; a ledge is a lens that ends in a point.
	if int(tier[4])==0: edge -= sin(PI*rise)*2.4
	else:
		edge -= pow(absf(rise-.5)*2.0,2.0)*6.0
		wobble *= .4
	var amount := edge+wobble-absf(point.x-float(tier[3])-float(tier[5]))
	for pillar in pillars: amount = smooth_max(amount,_pillar(point,pillar),1.6)
	for drop in drops: amount = smooth_max(amount,_drop(point,drop),1.2)
	amount = _with_features(amount,point)
	for window in windows:
		# An arch: flat at the foot, uneven all round.
		var local: Vector2 = (point-(window[0] as Vector2))/(window[1] as Vector2)
		local += Vector2(noise.get_noise_2d(point.x*.7,point.y*.7),noise.get_noise_2d(point.x*.7+40.0,point.y*.7))*.5
		if local.y<0.0: local.y *= 1.7
		amount = -smooth_max(-amount,-(local.length()-1.0)*float((window[1] as Vector2).x),1.4)
	if point.y>top: return minf(amount,top+.5-point.y)
	if point.y>height-8.0: amount = maxf(amount,_route_stone(point))
	return _foot(point,amount)

# The canyon stands on a broad tumble of rock.
func _foot(point: Vector2, amount: float) -> float:
	if point.y>16.0: return amount
	var foot := 19.0*(1.0-pow(clampf(point.y/16.0,0,1),1.5))+noise.get_noise_2d(point.x*.5,point.y*.8+70.0)*2.2-absf(point.x)
	return maxf(amount,foot)

func _split_edge(y: float) -> float:
	return -sin(y*.9)*.8

func _split_blend() -> float:
	return 6.0

func _far_ridge(point: Vector2, split: Dictionary) -> float:
	if split["style"]=="stones": return -INF
	var far: float = split["far_x"]
	var y0: float = split["y0"]
	var y1: float = split["y1"]
	var main: float = split["main_x"]
	var near := minf(main,far)
	var wide := maxf(main,far)
	var pillar := 4.6 if split["style"]=="ledge" else 3.4
	var amount := rounded_box(point,Rect2(far-pillar,y0,pillar*2.0,y1-y0),3.0)
	amount = smooth_max(amount,rounded_box(point,Rect2(near,y0-.5,wide-near,3.7),1.4),6.0)
	return smooth_max(amount,rounded_box(point,Rect2(near,y1-3.6,wide-near,4.6),1.4),6.0)

func _dress_brief(source: LevelSource) -> void:
	source.brief["rock"] = "desert"
	source.brief["free_route"] = true
	var marks: Array = []
	for tier in tiers:
		if int(tier[4])==1: marks.append([snappedf(float(tier[0]),.01),snappedf(float(tier[1]),.01),snappedf(float(tier[2]),.01),snappedf(float(tier[3])+float(tier[5]),.01)])
	source.brief["marks"] = marks
