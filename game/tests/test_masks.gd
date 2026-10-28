extends SceneTree

# Generation from masks (MaskLayout) on a level painted in code: a broad
# mountain with a sky window, an S-shaped route corridor, a spring pin, a
# painted solid block and a rest patch.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error("MASKS FAILED: "+description)

func corridor_x(y: float) -> float:
	return 5.5*sin(maxf(0.0,y-6.0)/22.0)

func paint(source: LevelSource, layer: String, inside: Callable) -> void:
	var image := source.new_mask()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if inside.call(source.to_world(Vector2(x+.5,y+.5))): image.set_pixel(x,y,Color.WHITE)
	source.masks[layer] = image

func make_source() -> LevelSource:
	var source := LevelSource.new()
	source.brief = {"id":"mask_test","location":0,"route":0,"height":120.0,"seeds":{"route":4242},
		"pins":[{"pos":[snappedf(corridor_x(50.0),.01),50.0],"type":"spring","lifetime":"disposable"}],"zones":[]}
	paint(source,"silhouette",func(p: Vector2) -> bool:
		var window := p.x>7.0 and p.x<10.5 and p.y>60.0 and p.y<66.0
		return absf(p.x)<12.5 and p.y<124.0 and not window)
	paint(source,"route",func(p: Vector2) -> bool: return absf(p.x-corridor_x(p.y))<2.2)
	paint(source,"solid",func(p: Vector2) -> bool: return p.x>-11.0 and p.x<-9.0 and p.y>40.0 and p.y<43.5)
	paint(source,"rest",func(p: Vector2) -> bool: return p.x>-10.0 and p.x<-6.5 and p.y>84.0 and p.y<84.5)
	return source

func generate(source: LevelSource) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(4242,0,0,false,0,true)
	(world.layout as MaskLayout).use_source(source)
	world.generate_to(126.0,true,120.0)
	return world

func run_tests() -> void:
	var source := make_source()
	var world := generate(source)
	var layout := world.layout as MaskLayout
	var audit := RouteGraph.audit(layout)
	check(audit["problems"].is_empty(),"the route from masks passes the route audit %s" % str(audit["problems"].slice(0,3)))
	# The route follows the painted corridor: every main grip within its
	# width (plus the forks' lean over their branch).
	var off := 0
	for id in layout.main_route:
		var point: Vector2 = layout.anchors[id]["pos"]
		if point.y>118.0: continue
		if absf(point.x-corridor_x(point.y))>2.2+2.0: off += 1
	check(off==0,"main grips stay in the painted corridor (%d off)" % off)
	var lefts := 0
	var rights := 0
	for id in layout.main_route:
		var x: float = layout.anchors[id]["pos"].x
		if x<-3.0: lefts += 1
		if x>3.0: rights += 1
	check(lefts>3 and rights>3,"the S-shaped corridor takes the route to both sides of the mountain")
	var pinned := false
	for id in layout.main_route:
		var grip: Dictionary = layout.anchors[id]
		if grip["pos"].distance_to(Vector2(corridor_x(50.0),50.0))<.05 and int(grip["kind"])==GripSpec.SPRING: pinned = true
	check(pinned,"a spring pin becomes the main route grip of its row")
	var painted_solid := 0
	var other_solid := 0
	for obstacle in layout.obstacles:
		if obstacle.get("mask",false): painted_solid += 1
		else: other_solid += 1
	check(painted_solid==1 and other_solid==0,"painted solid is the level's only obstacle (%d painted, %d generated)" % [painted_solid,other_solid])
	var rest := false
	for ledge in layout.ledges:
		if ledge.get("mask",false) and absf(float(ledge["top"])-84.5)<.3: rest = true
	var near: Array = []
	for grip in layout.anchors:
		if grip["pos"].x>-11.5 and grip["pos"].x<-5.0 and absf(grip["pos"].y-84.5)<1.6: near.append([grip["pos"],grip["role"]])
	check(rest,"a painted rest patch becomes a platform at its top %s %s" % [str(layout.mask_notes),str(near)])
	check(layout.outside(Vector2(8.5,63.0),0) and not layout.outside(Vector2(corridor_x(30.0),30.0),0),"the silhouette decides what is outside the mountain, its window included")
	check(absf(layout.outer_edge(30.0,-1)+12.5)<.3 and absf(layout.outer_edge(30.0,1)-12.5)<.3,"mountain edges come from the silhouette")
	var relief_inside := not layout.relief.is_empty()
	for entry in layout.relief:
		if layout.inside_distance(Vector2(entry[0],entry[1]))<=0.0: relief_inside = false
	check(relief_inside,"planned rock masses stand inside the painted silhouette")
	var data := LevelBake.capture(layout)
	check(data.has("relief") and data.has("edge_rows") and not data.has("_inside") and not data.has("source"),"the bake keeps the relief and edges, not the masks or scratch fields")
	var again := generate(make_source())
	check(str(again.layout.anchors)==str(layout.anchors) and str(again.layout.relief)==str(layout.relief),"the same masks give the same level")
	# A baked level carries no masks: its edges still answer from data.
	var baked := MountainWorld.new()
	baked.visuals_enabled = false
	root.add_child(baked)
	baked.setup(4242,0,0,false,0,true)
	var level := LevelBake.new()
	level.height = 120.0
	level.layout_data = data
	baked.load_bake(level)
	check(is_equal_approx(baked.layout.outer_edge(30.0,1),layout.outer_edge(30.0,1)) and baked.layout.main_route==layout.main_route,"a mask level loads from its bake without masks")
	designer_tests()
	print("MASKS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

# The automatic designer: beats dressed in landforms, the route on stone,
# the same seed giving the same source.
func designer_tests() -> void:
	var designer := LevelDesigner.new(1,0,777)
	var source := designer.build()
	check(source.masks["silhouette"].get_size()==source.size() and source.brief["generator"]=="masks","the designer writes a mask source of the level's size")
	var forms_ok := true
	var repeats := 0
	for index in range(1,designer.sections.size()):
		var section: Dictionary = designer.sections[index]
		if not LevelDesigner.BEAT_FORMS[section["beat"]].has(section["form"]): forms_ok = false
		if section["form"]==designer.sections[index-1]["form"]: repeats += 1
	check(forms_ok and repeats==0,"every section suits its beat and no two neighbours share a landform")
	var acts := {}
	for section in designer.sections: acts[section["act"]] = true
	check(acts.size()==3,"the designer dresses all three acts")
	var off_stone := 0
	var y := 2.0
	while y<designer.height:
		if source.sample("silhouette",Vector2(designer.corridor_center(y),y))<.5: off_stone += 1
		y += .5
	check(off_stone==0,"the designed route corridor runs on stone all the way up (%d gaps)" % off_stone)
	var again := LevelDesigner.new(1,0,777).build()
	check(again.masks["silhouette"].get_data()==source.masks["silhouette"].get_data() and again.masks["route"].get_data()==source.masks["route"].get_data(),"the same design seed gives the same masks")
	var other := LevelDesigner.new(1,0,778).build()
	check(other.masks["silhouette"].get_data()!=source.masks["silhouette"].get_data(),"another design seed gives another mountain")
