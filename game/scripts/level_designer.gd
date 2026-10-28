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
# No two neighbouring sections share a landform. Widths and sway blend across
# section borders, edges carry noise, the top narrows to a peak.
#
# The result is a LevelSource with "generator": "masks"; MaskLayout builds
# the level from it.

const SECTION_HALF := {"wall":8.5,"islands":4.6,"overhang":6.5,"arch":9.5,"split":9.0,"terrace":10.0,"traverse":6.0,"chimney":7.5,"neck":4.8,"base":13.0}
const CORRIDOR_HALF := {"traverse":2.5,"neck":2.5}
const CORRIDOR_DEFAULT := 2.7
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
	var spans := beat_spans()
	# The ground floor: a broad base the start platform stands on.
	sections.append({"form":"base","beat":"start","act":0,"y0":-2.0,"y1":3.0,"center0":0.0,"center1":0.0,"half":SECTION_HALF["base"],"corridor":CORRIDOR_DEFAULT,"bias":0.0,"features":[]})
	for entry in spans:
		var beat: String = entry[0]
		var y0: float = maxf(3.0,float(entry[1])-1.0)
		var y1: float = float(entry[2])+1.0
		if beat=="start" or y1-y0<2.0: continue
		var choices: Array = BEAT_FORMS[beat].filter(func(form: String) -> bool: return form!=previous_form)
		if choices.is_empty(): choices = BEAT_FORMS[beat]
		var form: String = choices[random.randi_range(0,choices.size()-1)]
		var start := center
		var finish := center+random.randf_range(-1.4,1.4)
		if form=="traverse":
			# Across the mountain, towards the roomier side.
			var direction := -signf(center) if absf(center)>1.0 else (-1.0 if random.randf()<.5 else 1.0)
			finish = center+direction*random.randf_range(5.0,7.5)
		elif form=="chimney":
			finish = center
		elif form=="neck":
			finish = random.randf_range(-3.0,3.0)
		finish = clampf(finish,-MAX_CENTER,MAX_CENTER)
		var section := {"form":form,"beat":beat,"act":int(entry[3]),"y0":y0,"y1":y1,"center0":start,"center1":finish,
			"half":SECTION_HALF[form]*random.randf_range(.9,1.1),"corridor":float(CORRIDOR_HALF.get(form,CORRIDOR_DEFAULT)),
			"bias":random.randf_range(-1.5,1.5) if form in ["wall","terrace","arch"] else 0.0,"features":[]}
		_features(section)
		sections.append(section)
		center = finish
		previous_form = form

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
	return lerpf(float(section["center0"]),float(section["center1"]),smoothstep(0.0,1.0,t))

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
	var top := height+1.5
	if point.y>top+.5 or point.y< -2.0: return -10.0
	var half := _blend(point.y,"half")
	# The top narrows to a peak over its last 14 units.
	if point.y>top-14.0: half = lerpf(half,1.2,smoothstep(top-14.0,top,point.y))
	var axis := corridor_center(point.y)+_blend(point.y,"bias")
	var amount := half+noise.get_noise_2d(point.x*1.0,point.y*1.0)*2.2-absf(point.x-axis)
	if point.y>top: amount = minf(amount,top+.5-point.y)
	# The route always runs on stone: the corridor and a margin beside it
	# stay inside the mountain whatever the noise and the cuts do.
	var route_rock := _blend(point.y,"corridor")+1.8-absf(point.x-corridor_center(point.y))
	if point.y<=top: amount = maxf(amount,route_rock)
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
	return maxf(amount,route_rock) if point.y<=top else amount

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
