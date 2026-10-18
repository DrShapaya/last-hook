class_name MassifLayout
extends EncounterLayout

const REGION_HEIGHT := 18.0
const FORMS := ["buttress","overhang","ridge","ravine","shoulder","arch"]
var landforms: Dictionary = {}
var profile_samples: Dictionary = {}
var rear_samples: Dictionary = {}
var support_roots: Dictionary = {}
var relief_noise := FastNoiseLite.new()
var grain_noise := FastNoiseLite.new()
var massif_side := 1

func setup(world_seed: int, biome: int) -> void:
	super.setup(world_seed,biome)
	massif_side = -1 if rng(0,309).randf()<.5 else 1
	relief_noise.seed = world_seed ^ 0x61A73
	relief_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief_noise.frequency = .105
	relief_noise.fractal_octaves = 3
	grain_noise.seed = world_seed ^ 0x27F41
	grain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain_noise.frequency = .65
	grain_noise.fractal_octaves = 2

func landform(index: int) -> Dictionary:
	if landforms.has(index): return landforms[index]
	var random := rng(index,310)
	# A permutation visits all six forms; its seed offset prevents identical starts.
	var kind := posmod(index*5+seed_value,FORMS.size())
	landforms[index] = {"kind":kind,"name":FORMS[kind],"y":index*REGION_HEIGHT+9.0+random.randf_range(-1,1),"side":-massif_side if random.randf()<.7 else massif_side,"strength":random.randf_range(.85,1.15)}
	return landforms[index]

func route_x(height: float) -> float:
	var y := clampf(height,4,summit-1.5) if finite else maxf(4,height)
	var index := maxi(0,int(y/3.1)-3)
	while main_point(index+1).y<y: index += 1
	while index>0 and main_point(index).y>y: index -= 1
	var a := main_point(index)
	var b := main_point(index+1)
	return lerpf(a.x,b.x,clampf((y-a.y)/(b.y-a.y),0,1))

func spine_x(height: float) -> float:
	return route_x(height-7)*.25+route_x(height)*.5+route_x(height+7)*.25

static func pulse(y: float, center: float, radius: float) -> float:
	var t := absf(y-center)/radius
	return 0.0 if t>=1 else (1-t*t)*(1-t*t)

func _profile_sample(index: int) -> Vector2:
	if profile_samples.has(index): return profile_samples[index]
	var y := index*.5
	var center := spine_x(y)+massif_side*3.2+relief_noise.get_noise_2d(y*.45,91)*1.5
	var left := 10.4+relief_noise.get_noise_2d(19,y)*2.0
	var right := 10.4+relief_noise.get_noise_2d(71,y)*2.0
	for region in range(int(floor(y/REGION_HEIGHT))-1,int(floor(y/REGION_HEIGHT))+2):
		var form := landform(region)
		var cy: float = form["y"]
		var side: int = form["side"]
		var strength: float = form["strength"]
		var both := 0.0
		var edge := 0.0
		match int(form["kind"]):
			0:
				both = 5.0*pulse(y,cy-3,7)-2.4*pulse(y,cy+4,4)
			1:
				edge = 3.1*pulse(y,cy+1.5,2.5)-4.7*pulse(y,cy-2.8,3.3)
			2:
				both = -6.8*pulse(y,cy,6)
			3:
				edge = -6.1*pulse(y,cy,5.5)
			4:
				both = 4.2*pulse(y,cy-3,6)-4.0*pulse(y,cy+3.8,3.6)
			5:
				edge = 1.8*pulse(y,cy+2,5)-2.5*pulse(y,cy-3,3)
		left += (both+(edge if side<0 else 0))*strength
		right += (both+(edge if side>0 else 0))*strength
	left = maxf(2.8,left)
	right = maxf(2.8,right)
	left += grain_noise.get_noise_2d(y*1.8,21)*.25
	right += grain_noise.get_noise_2d(y*1.8,67)*.25
	# The summit tapers to the final route, rather than ending in a flat slab.
	if finite:
		var taper := smoothstep(summit-9,summit+.8,y)
		left = lerpf(left,1.4,taper)
		right = lerpf(right,1.4,taper)
		center = lerpf(center,route_x(summit-1.5),taper)
	var profile := Vector2(center-left,center+right)
	profile_samples[index] = profile
	return profile

func profile_at(y: float) -> Vector2:
	var step := int(floor(y*2))
	return _profile_sample(step).lerp(_profile_sample(step+1),y*2-step)

func _rear_sample(index: int) -> Vector2:
	if rear_samples.has(index): return rear_samples[index]
	var y := index*.5
	var ascent := clampf(y/summit,0,1) if finite else .25+.15*sin(y*.018)
	var width := 45.0*pow(1-ascent,.85)+1.2
	var near := spine_x(y)+massif_side*lerpf(3.8,.2,ascent)
	var far := near+massif_side*maxf(1.2,width+relief_noise.get_noise_2d(138,y)*3.0)
	for region in range(int(floor(y/REGION_HEIGHT))-1,int(floor(y/REGION_HEIGHT))+2):
		var form := landform(region)
		var shoulder := 4.5*pulse(y,form["y"]-4,7)-3.5*pulse(y,form["y"]+3,4)
		far += massif_side*shoulder*(1-ascent)
	var bounds := Vector2(minf(near,far),maxf(near,far))
	rear_samples[index] = bounds
	return bounds

func rear_profile_at(y: float) -> Vector2:
	var step := int(floor(y*2))
	return _rear_sample(step).lerp(_rear_sample(step+1),y*2-step)

func rear_field(point: Vector2) -> float:
	var profile := rear_profile_at(point.y)
	var result := minf(point.x-profile.x,profile.y-point.x)
	# The wide mountain behind the climb has its own eroded outer valleys.
	for region in range(int(floor(point.y/REGION_HEIGHT))-1,int(floor(point.y/REGION_HEIGHT))+2):
		var form := landform(region)
		if form["kind"] not in [0,3,4]: continue
		var bounds := rear_profile_at(form["y"])
		var far_x: float = bounds.y if massif_side>0 else bounds.x
		var delta := point-Vector2(far_x,form["y"])
		result = minf(result,((delta/Vector2(7,4.5)).length()-1)*4.5)
	result = minf(result,point.y+24)
	if finite: result = minf(result,summit+.4-point.y)
	return result

func rear_depth(point: Vector2, clearance: float = INF) -> float:
	var relief := relief_noise.get_noise_2d(point.x,point.y)*2.2+grain_noise.get_noise_2d(point.x*.5,point.y*.5)*.4
	var edge := 1-exp(-maxf(0,rear_field(point) if is_inf(clearance) else clearance)*1.0)
	return lerpf(-8.5,-5.0+relief,edge)

func outer_edge(y: float, side: int) -> float:
	var profile := profile_at(y)
	return profile.x if side<0 else profile.y

func _add_anchor(point: Vector2, kind: int, dimensions: Vector2, primary: bool = false) -> int:
	var id := super._add_anchor(point,kind,dimensions,primary)
	if not primary:
		anchors[id]["permanent"] = kind in [0,2] and rng(id,391).randf()<.035
	return id

func auxiliary_point(_index: int, column: int, point: Vector2, random: RandomNumberGenerator) -> Vector2:
	var jitter := random.randf_range(-.25,.25)
	var y := point.y+random.randf_range(-.6,.6)
	var bounds := profile_at(y)
	var left := maxf(-17,bounds.x+1)
	var right := minf(17,bounds.y-1)
	return Vector2(lerpf(left,right,(column+.5+jitter)/4.0),y)

func branch_allowed(point: Vector2, index: int) -> bool:
	if not super.branch_allowed(point,index): return false
	for id in nearby_ids(point.y-2,point.y+2):
		if not anchors[id].get("reserve",false) and anchors[id]["pos"].distance_to(point)<1.65: return false
	return true

func body_field(point: Vector2) -> float:
	var profile := profile_at(point.y)
	var result := minf(point.x-profile.x,profile.y-point.x)
	# Open clefts and rounded arches are tied to the landform, not a repeated
	# diamond-hole stencil. A narrow spine keeps the climbing face connected.
	for region in range(int(floor(point.y/REGION_HEIGHT))-1,int(floor(point.y/REGION_HEIGHT))+2):
		var form := landform(region)
		if form["kind"] not in [3,5]: continue
		var cy: float = form["y"]
		var bounds := profile_at(cy)
		var side: float = form["side"]
		var center_x := lerpf(bounds.x,bounds.y,.24 if side<0 else .76)
		var delta := point-Vector2(center_x,cy)
		var size := Vector2(2.0,5.3) if form["kind"]==3 else Vector2(3.3,2.2)
		delta.x += delta.y*.18*side+relief_noise.get_noise_2d(point.x,point.y)*.65
		var hole := ((delta/size).length()-1)*minf(size.x,size.y)
		result = minf(result,hole)
	result = maxf(result,1.5-absf(point.x-route_x(point.y)))
	result = minf(result,point.y+2)
	if finite: result = minf(result,summit+.4-point.y)
	return result

func support_root(grip: Dictionary) -> Vector2:
	var id: int = grip["id"]
	if support_roots.has(id): return support_roots[id]
	var p: Vector2 = grip["pos"]-Vector2(0,.25)
	if body_field(p)>.45 and body_field(grip["pos"])>.25:
		support_roots[id] = Vector2.INF
		return Vector2.INF
	# Search the real carved body, not its bounding edges. This prevents a
	# supported grip from becoming a floating island in the middle of an arch.
	var best := Vector2(route_x(p.y),p.y)
	for distance_step in range(1,11):
		var found := false
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
			var candidate: Vector2 = p+direction*distance_step*.5
			if body_field(candidate)>.45:
				best = candidate
				found = true
				break
		if found: break
	support_roots[id] = best
	return best

func rock_field(point: Vector2) -> float:
	var result := body_field(point)
	for id in nearby_ids(point.y-6,point.y+6):
		var grip: Dictionary = anchors[id]
		if absf(point.y-grip["pos"].y)>5.8: continue
		var root := support_root(grip)
		if not root.is_finite(): continue
		var p: Vector2 = grip["pos"]-Vector2(0,.25)
		var closest := Geometry2D.get_closest_point_to_segment(point,p,root)
		var radius := Vector2(maxf(.7,grip["dimensions"].x*.64),.76)
		result = maxf(result,(1-((point-closest)/radius).length())*.8)
	return result

func _try_obstacle(candidate: Dictionary, index: int) -> bool:
	if candidate.get("massif",false) and rock_field(candidate["pos"])<.5: return false
	return super._try_obstacle(candidate,index)

func surface_depth(point: Vector2, clearance: float = INF) -> float:
	var large := relief_noise.get_noise_2d(point.x,point.y)
	var fold := relief_noise.get_noise_2d(point.x*1.7+23,point.y*.65)
	var detail := grain_noise.get_noise_2d(point.x,point.y)
	var strata := point.y*.43+point.x*.11+large*.8
	var phase := fposmod(strata,1.0)
	var bedding := smoothstep(.02,.15,phase)*(1-smoothstep(.65,1.0,phase))
	var depth := clampf(-.15+large*3.1+fold*1.0+detail*.17+bedding*.26,-1.7,1.30)
	var edge := 1-exp(-maxf(0,rock_field(point) if is_inf(clearance) else clearance)*1.7)
	return lerpf(-2.2,depth,edge)

func _build_obstacles(index: int, encounter: Dictionary) -> void:
	# Foreground ledges are convex pieces of the massif, using the same polygon
	# for rendering, swept body collision, hook hits and rope routing.
	var point := main_point(index)
	var next := main_point(index+1)
	var random := rng(index,315)
	var side := -1 if next.x>point.x else 1
	var kind: int = encounter["kind"]
	var shape := "shelf" if kind in [4,6] else "pillar" if kind in [2,5] else "wedge"
	var dimensions := Vector2(4.0,1.15) if shape=="shelf" else Vector2(1.55,3.8) if shape=="pillar" else Vector2(2.7,2.25)
	for attempt in range(10):
		var direction := side if attempt<5 else -side
		var offset := 4.0+float(attempt%5)*.85
		var candidate := {"pos":point+Vector2(direction*offset,-.75+random.randf_range(-.25,.25)),"dimensions":dimensions,"type":shape,"encounter":true,"massif":true,"rest":shape=="shelf"}
		candidate["variant"] = int(random.randi_range(0,2))
		candidate["face_side"] = direction
		var w := dimensions.x*.5
		var h := dimensions.y*.5
		if shape=="shelf":
			candidate["polygon"] = PackedVector2Array([Vector2(-w*.78,-h),Vector2(w*.64,-h*.85),Vector2(w,h*.35),Vector2(w*.8,h),Vector2(-w*.94,h*.85),Vector2(-w,h*.05)])
		elif shape=="pillar":
			candidate["polygon"] = PackedVector2Array([Vector2(-w*.65,-h),Vector2(w*.75,-h*.85),Vector2(w,h*.65),Vector2(w*.35,h),Vector2(-w*.7,h*.72),Vector2(-w,h*.05)])
		else:
			candidate["polygon"] = PackedVector2Array([Vector2(-w,-h),Vector2(w*.6,-h),Vector2(w,h*.15),Vector2(-w*.4,h)])
		if _try_obstacle(candidate,index):
			encounter["obstacles"].append(obstacles.size()-1)
			return
