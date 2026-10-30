class_name LevelDesigner
extends RefCounted

# The automatic level designer (docs/LEVEL_PIPELINE.md): writes a level's
# source — brief and masks — from its place in the catalogue and a seed.
#
# It dresses the acts' beats in landforms. Every act climbs through the same
# beats (start, intro, teach, fork, rest, combo, exit); the designer works
# out where each beat's rows will stand, exactly as the generator lays them,
# and gives each beat a section of mountain that suits it:
#   intro            a broad wall, the route swaying gently;
#   teach            a wall, islands round a narrow trunk, or an overhang;
#   fork             an arch window or a split ridge beside a broad mass;
#   rest             a terrace with a resting shelf off the route;
#   combo (climax)   a traverse across the mountain, islands, or a chimney:
#                    a crevice of sky beside the route with a wall across;
#   exit             a neck that leads into the next act.
# No two neighbouring sections share a landform.
#
# Each act also splits in two from its fork beat to the end of its combo:
# the main route keeps to one ridge, a second way climbs another ridge across
# open sky — a "ledge" of long, gentle hops zigzagging across the face or a
# steep "ridge" — and rejoins at the top. The ridges stand far enough apart
# that no rope crosses between them. Widths and sway blend across
# section borders, edges carry noise, the top narrows to a peak.
#
# The result is a LevelSource with "generator": "masks"; MaskLayout builds
# the level from it.

const SECTION_HALF := {"wall":8.5,"islands":4.6,"overhang":6.5,"arch":9.5,"split":9.0,"terrace":10.0,"traverse":6.0,"chimney":7.5,"neck":4.8,"base":13.0}
const CORRIDOR_HALF := {"traverse":3.0,"neck":2.5}
const CORRIDOR_DEFAULT := 3.0
const MAX_CENTER := 8.5
const BEAT_FORMS := {
	"start":["wall"],"intro":["wall"],"teach":["wall","islands","overhang"],"fork":["arch","split"],
	"rest":["terrace"],"combo":["traverse","chimney","islands"],"exit":["neck"]}

var location := 0
var route := 0
var seed_value := 0
var height := 120.0
var random := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
# Sections bottom-up: {form, beat, act, y0, y1, center0, center1, half, corridor, bias, features}
var sections: Array = []
# Splits bottom-up: {y0, y1, side, main_x, path: PackedVector2Array, style}
var splits: Array = []
# The width of the stone band each shape of the far way runs on.
const SPLIT_BAND := {"ledge":2.3,"ridge":2.8,"arc":2.2,"stones":2.2,"diagonal":2.4,"butte":2.4}
# Stone kept beside the route corridor: forks lean up to 2 units out of it.
const ROUTE_ROCK := 2.6
# Zigzag width of the main route by landform (1 = the generator's): wide
# swings and near-level hops instead of a tight ladder. Every hop stays in
# base-kit reach (MaskLayout clamps it).
const SWAY := {"base":1.0,"wall":1.3,"islands":1.2,"overhang":1.25,"arch":1.3,"split":1.25,"terrace":1.2,"traverse":1.5,"chimney":1.15,"neck":1.0}
const SPLIT_RAMP := 4.0

# The designer of a location: each mountain is drawn by its own.
static func make(level_location: int, level_route: int, design_seed: int) -> LevelDesigner:
	match level_location:
		1: return DesertDesigner.new(level_location,level_route,design_seed)
		2: return WinterDesigner.new(level_location,level_route,design_seed)
	return LevelDesigner.new(level_location,level_route,design_seed)

func _init(level_location: int, level_route: int, design_seed: int) -> void:
	location = level_location
	route = level_route
	seed_value = design_seed
	height = float(LevelCatalog.level(location)["height_units"])
	random.seed = design_seed
	noise.seed = design_seed
	noise.frequency = .09
	noise.fractal_octaves = 3

# --- Plan -------------------------------------------------------------------------

# Row heights of every act, as ExpeditionLayout._plan_act sets them (without
# its ±0.08 jitter), grouped by beat into [beat, y0, y1].
func beat_spans() -> Array:
	var spans := LevelCatalog.act_spans(location,height)
	var result: Array = []
	for act in range(spans.size()):
		var start_y := 4.0 if act==0 else float(spans[act]["y_start"])+1.0
		var target_y := float(spans[act]["y_end"])+1.0 if act<spans.size()-1 else height+1.0
		var beats: Array = LevelCatalog.ACTS[spans[act]["id"]]["route_patterns"]
		var counts: Array[int] = []
		for beat in beats: counts.append(int(ExpeditionLayout.BASE_ROWS[beat["beat"]]))
		var total := 0
		for count in counts: total += count
		var wanted := roundi((target_y-start_y)/ExpeditionLayout.LINK_RISE)
		var guard := 0
		while total<wanted and guard<12:
			guard += 1
			for index in range(beats.size()):
				var kind: String = beats[index]["beat"]
				if total<wanted and ExpeditionLayout.MAX_ROWS.has(kind) and counts[index]<int(ExpeditionLayout.MAX_ROWS[kind]):
					counts[index] += 1
					total += 1
		var nominal := ExpeditionLayout.FINAL_RISE
		for index in range(beats.size()):
			var kind: String = beats[index]["beat"]
			if kind=="start": continue
			for step in range(counts[index]): nominal += float(ExpeditionLayout.STEPS[kind][step][1])
		var scale := (target_y-start_y)/nominal
		var y := start_y
		for index in range(beats.size()):
			var kind: String = beats[index]["beat"]
			var y0 := y
			if kind!="start":
				for step in range(counts[index]): y += float(ExpeditionLayout.STEPS[kind][step][1])*scale
			result.append([kind,y0,y,act])
	return result

func plan() -> void:
	sections.clear()
	var center := 0.0
	var previous_form := ""
	var lean := 0.0
	var lean_act := -1
	var spans := beat_spans()
	# The ground floor: a broad base the start platform stands on.
	sections.append({"form":"base","beat":"start","act":0,"y0":-2.0,"y1":3.0,"center0":0.0,"center1":0.0,"half":SECTION_HALF["base"],"corridor":CORRIDOR_DEFAULT,"bias":0.0,"features":[]})
	for entry in spans:
		var beat: String = entry[0]
		var y0: float = maxf(3.0,float(entry[1])-1.0)
		var y1: float = float(entry[2])+1.0
		if beat=="start" or y1-y0<2.0: continue
		var forms := _forms_of(beat)
		var choices: Array = forms.filter(func(form: String) -> bool: return form!=previous_form)
		if choices.is_empty(): choices = forms
		var form: String = choices[random.randi_range(0,choices.size()-1)]
		var act := int(entry[3])
		if act!=lean_act:
			# Every act leans the mountain somewhere new, so the whole is no
			# straight column.
			lean_act = act
			var target := random.randf_range(-6.0,6.0)
			while absf(target-lean)<3.0: target = random.randf_range(-6.0,6.0)
			lean = target
		var start := center
		var finish := lerpf(center,lean,random.randf_range(.35,.6))+random.randf_range(-1.2,1.2)
		if form=="traverse":
			# Across the mountain, towards the roomier side.
			var direction := -signf(center) if absf(center)>1.0 else (-1.0 if random.randf()<.5 else 1.0)
			finish = center+direction*random.randf_range(5.0,7.5)
		elif form=="chimney":
			finish = center
		elif form=="neck":
			finish = random.randf_range(-3.0,3.0)
		finish = clampf(_finish_of(form,center,finish,y1-y0),-MAX_CENTER,MAX_CENTER)
		var section := {"form":form,"beat":beat,"act":int(entry[3]),"y0":y0,"y1":y1,"center0":start,"center1":finish,
			"half":SECTION_HALF[form]*random.randf_range(.9,1.1),"corridor":float(CORRIDOR_HALF.get(form,CORRIDOR_DEFAULT)),
			"bias":random.randf_range(-1.5,1.5) if form in ["wall","terrace","arch"] else 0.0,"features":[]}
		_features(section)
		sections.append(section)
		center = finish
		previous_form = form
	_plan_splits(spans)
	_after_plan()

# --- What each location's designer sets its own way ----------------------------------

func _forms_of(beat: String) -> Array:
	return BEAT_FORMS[beat]

func _split_shapes() -> Array:
	return ["ledge","ridge","arc","stones","diagonal"]

func _sway_scale() -> float:
	return 1.0

func _finish_of(_form: String, _center: float, finish: float, _span: float) -> float:
	return finish

func _after_plan() -> void:
	pass

# How far a point is inside this mountain, in units (negative outside).
func _outline_at(point: Vector2) -> float:
	return _shape_at(point)

# A second way's own ridge, for a mountain that gives it one.
func _far_ridge(_point: Vector2, _split: Dictionary) -> float:
	return -INF

func _split_edge(_y: float) -> float:
	return 0.0

func _split_blend() -> float:
	return .01

func _dress_brief(_source: LevelSource) -> void:
	pass

func _route_stone(point: Vector2) -> float:
	return _blend(point.y,"corridor")+ROUTE_ROCK-absf(point.x-corridor_center(point.y))

# --- Shape helpers ------------------------------------------------------------------

static func rounded_box(point: Vector2, box: Rect2, radius: float) -> float:
	var q := (point-box.get_center()).abs()-box.size*.5+Vector2(radius,radius)
	return radius-minf(maxf(q.x,q.y),0.0)-Vector2(maxf(q.x,0.0),maxf(q.y,0.0)).length()

# The union of two masses with their meeting corner rounded over `blend`.
static func smooth_max(a: float, b: float, blend: float) -> float:
	if not is_finite(a) or not is_finite(b): return maxf(a,b)
	var h := clampf(.5+.5*(a-b)/blend,0,1)
	return lerpf(b,a,h)+blend*h*(1.0-h)

func _plan_splits(spans: Array) -> void:
	splits.clear()
	var acts := {}
	for entry in spans:
		if str(entry[0]) in ["fork","rest","combo"]:
			var act := int(entry[3])
			var range_y: Vector2 = acts.get(act,Vector2(INF,-INF))
			acts[act] = Vector2(minf(range_y.x,float(entry[1])),maxf(range_y.y,float(entry[2])))
	var shape := ""
	for act in acts:
		var y0: float = acts[act].x
		var y1: float = acts[act].y
		if y1-y0<14.0 or y1>height-4.0: continue
		var center := corridor_center(y0)
		# The second way goes to the roomier side, mostly; the main route
		# leans away.
		var side := -signf(center) if absf(center)>1.5 and random.randf()<.8 else (-1.0 if random.randf()<.5 else 1.0)
		var gap := random.randf_range(13.0,15.0)
		var main_x := clampf(center-side*random.randf_range(2.0,3.0),-6.0,6.0)
		if side>0: main_x = minf(main_x,15.0-gap)
		else: main_x = maxf(main_x,-15.0+gap)
		var choices: Array = _split_shapes().filter(func(name: String) -> bool: return name!=shape)
		shape = choices[random.randi_range(0,choices.size()-1)]
		splits.append({"y0":y0,"y1":y1,"side":side,"main_x":main_x,"far_x":main_x+side*gap,"style":shape,
			"path":_split_path(shape,main_x,side,gap,y0,y1),"band":float(SPLIT_BAND[shape])*random.randf_range(.85,1.15),
			"ridge":random.randf_range(4.4,6.0)})

# The far way's line from where it leaves the main ridge to where it rejoins.
func _split_path(shape: String, main_x: float, side: float, gap: float, y0: float, y1: float) -> Array:
	var far_x := main_x+side*gap
	var length := y1-y0
	var near_x := main_x+side*4.2
	var path: Array = [Vector2(near_x,y0+2.0)]
	match shape:
		"ledge":
			# Long, gentle hops: out across the face, then side to side up the
			# far ridge's ledges, then back across.
			path.append(Vector2(far_x,y0+length*random.randf_range(.24,.32)))
			path.append(Vector2(far_x-side*random.randf_range(1.5,2.3),y0+length*.48))
			path.append(Vector2(far_x+side*random.randf_range(.9,1.6),y0+length*.66))
			path.append(Vector2(far_x-side*.6,y1-3.2))
		"ridge":
			# A steep ridge: one traverse out, straight up, one back.
			path.append(Vector2(far_x,y0+random.randf_range(3.0,4.5)))
			path.append(Vector2(far_x+side*random.randf_range(-.3,.8),y1-random.randf_range(3.5,5.0)))
		"arc":
			# One smooth bow out and back: every hop climbs a little and turns.
			var bulge := random.randf_range(.0,.25)
			for k in range(1,8):
				var t := k/8.0
				var x := near_x+side*(gap-4.2)*sin(PI*pow(t,1.0+bulge))
				path.append(Vector2(x,y0+2.0+(length-3.0)*t))
		"stones":
			# Out along a line of separate stones that waves up and down.
			var turn := random.randf_range(.45,.6)
			for k in range(1,6):
				var t := k/6.0
				path.append(Vector2(near_x+side*(gap-4.2)*minf(1.0,t/turn),y0+2.0+length*.42*t+sin(t*TAU*1.5)*1.2))
			path.append(Vector2(far_x+side*.3,y0+length*.62))
			path.append(Vector2(far_x-side*2.5,y1-3.5))
		"butte":
			# Out along a bed, up a free-standing pillar, back along its cap.
			path.append(Vector2(far_x,y0+2.0))
			path.append(Vector2(far_x,y1-2.5))
			path.append(Vector2(far_x-side*2.0,y1-1.6))
		"diagonal":
			# A long slant out and up, then one level traverse back.
			path.append(Vector2(far_x,y1-random.randf_range(4.5,6.0)))
			path.append(Vector2(far_x-side*random.randf_range(.5,1.5),y1-2.6))
	path.append(Vector2(near_x,y1-1.0))
	return path

# The split around a height, or {} outside every split.
func split_at(y: float) -> Dictionary:
	for split in splits:
		if y>=float(split["y0"])-1.0 and y<=float(split["y1"])+1.0: return split
	return {}

# Local shapes of a section: islands, windows, overhangs, shelves, blocks.
# Each is [kind, centre, radii] in world units; "add" joins the mass, "cut"
# opens the sky, "rest" and "solid" go to their masks.
func _features(section: Dictionary) -> void:
	var y0: float = section["y0"]
	var y1: float = section["y1"]
	var mid := (y0+y1)*.5
	var center := lerpf(float(section["center0"]),float(section["center1"]),.5)
	var side := -1.0 if random.randf()<.5 else 1.0
	var features: Array = section["features"]
	match str(section["form"]):
		"islands":
			for count in range(random.randi_range(2,3)):
				var flank := side if count%2==0 else -side
				var at := Vector2(center+flank*random.randf_range(9.0,12.5),lerpf(y0,y1,random.randf_range(.2,.8)))
				features.append(["add",at,Vector2(random.randf_range(1.8,2.8),random.randf_range(1.6,2.4))])
		"overhang":
			var at := Vector2(center+side*random.randf_range(8.0,10.0),mid+1.0)
			features.append(["add",at,Vector2(random.randf_range(3.5,4.5),random.randf_range(1.4,1.8))])
			features.append(["cut",at+Vector2(-side*1.0,-3.0),Vector2(3.2,1.8)])
		"arch":
			var at := Vector2(center+side*random.randf_range(6.0,7.0),mid)
			features.append(["cut",at,Vector2(random.randf_range(1.5,2.0),random.randf_range(2.2,2.8))])
		"split":
			# Two crowns with sky between them above the fork.
			features.append(["cut",Vector2(center+side*5.5,y1-1.5),Vector2(1.8,3.2)])
		"terrace":
			var shelf_x := center+side*random.randf_range(5.5,7.5)
			features.append(["add",Vector2(shelf_x,mid-1.0),Vector2(4.5,2.2)])
			features.append(["rest",Vector2(shelf_x,mid+1.1),Vector2(2.0,.3)])
		"chimney":
			# A deep crevice of sky beside the route: the climb runs up one of
			# its walls, the other stands across the gap.
			features.append(["chimney",Vector2(center+side*random.randf_range(4.6,5.4),(y0+y1)*.5),Vector2(.8,(y1-y0)*.5-1.0)])
			features.append(["add",Vector2(center+side*7.5,(y0+y1)*.5),Vector2(2.2,(y1-y0)*.5)])
		"wall":
			if random.randf()<.5:
				features.append(["solid",Vector2(center+side*random.randf_range(5.8,7.0),lerpf(y0,y1,random.randf_range(.3,.7))),Vector2(1.0,.8)])

# --- Shape --------------------------------------------------------------------------

func _section_at(y: float) -> int:
	for index in range(sections.size()-1,-1,-1):
		if y>=float(sections[index]["y0"]): return index
	return 0

# Route centre: within a section it eases from its entry to its exit.
func corridor_center(y: float) -> float:
	var section: Dictionary = sections[_section_at(y)]
	var t := clampf((y-float(section["y0"]))/maxf(.1,float(section["y1"])-float(section["y0"])),0,1)
	var center := lerpf(float(section["center0"]),float(section["center1"]),smoothstep(0.0,1.0,t))
	# Within a split the main route keeps to its own ridge.
	for split in splits:
		var y0: float = split["y0"]
		var y1: float = split["y1"]
		var lean := smoothstep(y0-SPLIT_RAMP,y0,y)*(1.0-smoothstep(y1,y1+SPLIT_RAMP,y))
		if lean>0: center = lerpf(center,float(split["main_x"]),lean)
	return center

# A section property eased across the border with its neighbours over a few
# units, so widths and offsets never step.
func _blend(y: float, key: String) -> float:
	var index := _section_at(y)
	var here: Dictionary = sections[index]
	var value := float(here[key])
	var below := y-float(here["y0"])
	if index>0 and below<2.5: value = lerpf(float(sections[index-1][key]),value,.5+below/5.0)
	if index<sections.size()-1:
		var above := float(sections[index+1]["y0"])-y
		if above<2.5: value = lerpf(float(sections[index+1][key]),value,.5+above/5.0)
	return value

# How far a point is inside the mountain, in units (negative outside).
func inside(point: Vector2) -> float:
	return _outline_at(point)

func _shape_at(point: Vector2) -> float:
	var top := height+1.5
	if point.y>top+.5 or point.y< -2.0: return -10.0
	var split := split_at(point.y)
	if not split.is_empty(): return _split_inside(point,split,top)
	var half := _blend(point.y,"half")
	# The top narrows to a peak over its last 14 units.
	if point.y>top-14.0: half = lerpf(half,1.2,smoothstep(top-14.0,top,point.y))
	var axis := corridor_center(point.y)+_blend(point.y,"bias")
	var amount := half+noise.get_noise_2d(point.x*1.0,point.y*1.0)*2.2-absf(point.x-axis)
	if point.y>top: amount = minf(amount,top+.5-point.y)
	# The route always runs on stone: the corridor and a margin beside it
	# stay inside the mountain whatever the noise and the cuts do.
	var route_rock := _blend(point.y,"corridor")+ROUTE_ROCK-absf(point.x-corridor_center(point.y))
	if point.y<=top: amount = maxf(amount,route_rock)
	amount = _with_features(amount,point)
	return maxf(amount,route_rock) if point.y<=top else amount

# A section's own shapes joined to and cut out of the mass.
func _with_features(mass: float, point: Vector2) -> float:
	var amount := mass
	var index := _section_at(point.y)
	var features: Array = []
	for neighbour in [index-1,index,index+1]:
		if neighbour>=0 and neighbour<sections.size(): features.append_array(sections[neighbour]["features"])
	for feature in features:
		var kind: String = feature[0]
		var shape := _ellipse(point,feature[1],feature[2])
		match kind:
			"add": amount = maxf(amount,shape+noise.get_noise_2d(point.x*2.0,point.y*2.0+50.0)*.6)
			"cut": amount = minf(amount,-shape)
			"chimney":
				var gap := float(feature[2].x)-absf(point.x-float(feature[1].x))
				var span := float(feature[2].y)-absf(point.y-float(feature[1].y))
				if span>0: amount = minf(amount,-minf(gap,span))
	return amount

# Within a split: a narrow main ridge round the route and a second ridge
# along the other way's line, with open sky between them.
func _split_inside(point: Vector2, split: Dictionary, top: float) -> float:
	var axis := corridor_center(point.y)
	var main := float(split.get("ridge",5.2))+noise.get_noise_2d(point.x,point.y)*1.2-absf(point.x-axis)
	main += _split_edge(point.y)
	var route_rock := _blend(point.y,"corridor")+ROUTE_ROCK-absf(point.x-axis)
	var path: Array = split["path"]
	var band := -INF
	var width := float(split.get("band",2.4))
	var stones := str(split["style"])=="stones"
	var walked := 0.0
	for k in range(1,path.size()):
		var near := Geometry2D.get_closest_point_to_segment(point,path[k-1],path[k])
		var here := width
		if stones:
			# Pinched every few units into a chain of separate stones.
			var along: float = walked+near.distance_to(path[k-1])
			here *= .55+.45*cos(along/4.2*TAU)
		band = maxf(band,here+noise.get_noise_2d(point.x*1.6,point.y*1.6+90.0)*.9-near.distance_to(point))
		walked += (path[k] as Vector2).distance_to(path[k-1])
	var amount := maxf(maxf(main,route_rock),band)
	amount = smooth_max(amount,_far_ridge(point,split),_split_blend())
	# Blend with the ordinary mountain over the split's first and last units.
	var y0: float = split["y0"]
	var y1: float = split["y1"]
	return amount if point.y<=top else minf(amount,top+.5-point.y)

# Inside amount of an ellipse in units (approximate, positive inside).
static func _ellipse(point: Vector2, center: Vector2, radii: Vector2) -> float:
	var local := (point-center)/radii
	return (1.0-local.length())*minf(radii.x,radii.y)

# --- Masks --------------------------------------------------------------------------

func build(source_name: String = "") -> LevelSource:
	plan()
	var source := LevelSource.new()
	var route_data: Dictionary = LevelCatalog.route(location,route)
	source.brief = {"id":LevelBake.directory(location,route).get_file(),"location":location,"route":route,
		"name":str(route_data.get("name",source_name)),"height":height,"generator":"masks",
		"seeds":{"route":int(route_data.get("seed",seed_value)),"design":seed_value},"pins":[],"zones":[],
		"design":_design_notes()}
	var silhouette := source.new_mask()
	var depth := source.new_mask()
	var difficulty := source.new_mask()
	var dimensions := source.size()
	var spans := LevelCatalog.act_spans(location,height)
	for y in range(dimensions.y):
		var row_y := source.to_world(Vector2(0,y+.5)).y
		var act := 0
		for index in range(spans.size()):
			if row_y>=float(spans[index]["y_start"]): act = index
		var progress := clampf((row_y-float(spans[act]["y_start"]))/maxf(1.0,float(spans[act]["y_end"])-float(spans[act]["y_start"])),0,1)
		var easy := 1.0-clampf(.15+act*.2+progress*.3,0,1)
		for x in range(dimensions.x):
			var point := source.to_world(Vector2(x+.5,y+.5))
			var amount := inside(point)
			var cover := clampf(.5+amount*LevelSource.PX_PER_UNIT*.5,0,1)
			if cover>0:
				silhouette.set_pixel(x,y,Color(cover,cover,cover))
				var near := clampf(.3+clampf(amount/7.0,0,1)*.45+noise.get_noise_2d(point.x*3.0,point.y*3.0)*.15,0,1)
				depth.set_pixel(x,y,Color(near,near,near))
			difficulty.set_pixel(x,y,Color(easy,easy,easy))
	source.masks["silhouette"] = silhouette
	source.masks["depth"] = depth
	source.masks["difficulty"] = difficulty
	source.masks["route"] = _paint(source,func(point: Vector2) -> float:
		var half := _blend(point.y,"corridor")
		return clampf((half-absf(point.x-corridor_center(point.y)))*2.0+.5,0,1) if point.y<=height+1.0 else 0.0)
	source.masks["branch"] = _paint(source,func(point: Vector2) -> float:
		var best := 0.0
		for split in splits:
			var path: Array = split["path"]
			for k in range(1,path.size()):
				var near := Geometry2D.get_closest_point_to_segment(point,path[k-1],path[k])
				best = maxf(best,clampf((1.2-near.distance_to(point))*2.0+.5,0,1))
		return best)
	var specs: Array = []
	for split in splits:
		var line: Array = []
		for point in split["path"]: line.append([snappedf(point.x,.01),snappedf(point.y,.01)])
		specs.append({"style":split["style"],"path":line,"from":snappedf(float(split["y0"]),.1),"to":snappedf(float(split["y1"]),.1)})
	source.brief["splits"] = specs
	var pace: Array = []
	for section in sections:
		var sway: float = SWAY.get(section["form"],1.0)
		# On the main ridge of a split the route keeps a steadier rhythm.
		if not split_at((float(section["y0"])+float(section["y1"]))*.5).is_empty(): sway = 1.1
		pace.append({"from":snappedf(float(section["y0"]),.01),"to":snappedf(float(section["y1"]),.01),"sway":sway*_sway_scale()})
	source.brief["pace"] = pace
	_dress_brief(source)
	source.masks["rest"] = _paint_features(source,"rest")
	source.masks["solid"] = _paint_features(source,"solid")
	return source

func _paint(source: LevelSource, value: Callable) -> Image:
	var image := source.new_mask()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var amount: float = value.call(source.to_world(Vector2(x+.5,y+.5)))
			if amount>0: image.set_pixel(x,y,Color(amount,amount,amount))
	return image

func _paint_features(source: LevelSource, kind: String) -> Image:
	var image := source.new_mask()
	for section in sections:
		for feature in section["features"]:
			if feature[0]!=kind: continue
			# A split owns its stretch of mountain: no section pieces there.
			if not split_at(float(feature[1].y)).is_empty(): continue
			var center: Vector2 = feature[1]
			var radii: Vector2 = feature[2]
			var low := source.to_pixel(center+Vector2(-radii.x,radii.y)).floor()
			var high := source.to_pixel(center+Vector2(radii.x,-radii.y)).ceil()
			for y in range(maxi(0,int(low.y)),mini(image.get_height(),int(high.y)+1)):
				for x in range(maxi(0,int(low.x)),mini(image.get_width(),int(high.x)+1)):
					var point := source.to_world(Vector2(x+.5,y+.5))
					var inside_rect := absf(point.x-center.x)<=radii.x and absf(point.y-center.y)<=radii.y
					if kind=="rest" and inside_rect: image.set_pixel(x,y,Color.WHITE)
					elif kind=="solid" and _ellipse(point,center,radii)>0: image.set_pixel(x,y,Color.WHITE)
	return image

func _design_notes() -> Array:
	var result: Array = []
	for section in sections:
		result.append({"form":section["form"],"beat":section["beat"],"act":section["act"],"from":snappedf(float(section["y0"]),.1),"to":snappedf(float(section["y1"]),.1)})
	return result
