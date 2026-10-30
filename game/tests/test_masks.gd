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
	split_tests()
	style_tests()
	print("MASKS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

# Each location has a generator of its own, with its own rock and mask.
func style_tests() -> void:
	var parted_rows := {}
	for location in range(3):
		var designer := LevelDesigner.make(location,0,int(LevelCatalog.route(location,0)["seed"])*31)
		var source := designer.build()
		var world := MountainWorld.new()
		world.visuals_enabled = false
		root.add_child(world)
		world.setup(int(source.brief["seeds"]["route"]),location,0,false,0,true)
		var layout := world.layout as MaskLayout
		layout.use_source(source)
		world.generate_to(designer.height+6,true,designer.height)
		var parted := 0
		var y := 8.0
		while y<designer.height-8.0:
			var spans := 0
			var inside := false
			for x in range(-20,21):
				var stone: bool = source.sample("silhouette",Vector2(x,y))>.5
				if stone and not inside: spans += 1
				inside = stone
			if spans>=2: parted += 1
			y += 1.0
		parted_rows[location] = parted
		var sky := 0
		for id in layout.main_route:
			if layout.inside_distance(layout.anchors[id]["pos"])<0.0: sky += 1
		check(sky==0,"every main grip finds stone in the mask of location %d (%d in the sky)" % [location,sky])
		match location:
			0: check(designer.get_script()==LevelDesigner and layout.rock_form=="boulder" and layout.rock_grid.is_empty(),"the summer mountain stays boulders and keeps no rock field")
			1: check(designer is DesertDesigner and layout.rock_form=="desert" and not (designer as DesertDesigner).tiers.is_empty(),"the canyon has its own designer and rock")
			2: check(designer is WinterDesigner and layout.rock_form=="winter" and not layout.rock_marks.is_empty(),"the snow peak has its own designer, rock and shelves")
		if location>0:
			var rock := RockSurface.make(layout)
			var mesh := rock.build(24.0,48.0,1.0)
			check(mesh.get_surface_count()==1 and mesh.get_faces().size()>300,"location %d builds one continuous rock face" % location)
			var a := rock.build(24.0,48.0,1.0).get_faces()
			check(a==mesh.get_faces(),"the rock face of location %d is the same every time" % location)
		world.free()
	check(int(parted_rows[1])>0 and int(parted_rows[2])>0,"the canyon and the peak part into separate masses %s" % str(parted_rows))

# The automatic designer: beats dressed in landforms, the route on stone,
# the same seed giving the same source.
func designer_tests() -> void:
	var designer := LevelDesigner.new(0,1,777)
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
	var again := LevelDesigner.new(0,1,777).build()
	check(again.masks["silhouette"].get_data()==source.masks["silhouette"].get_data() and again.masks["route"].get_data()==source.masks["route"].get_data(),"the same design seed gives the same masks")
	var other := LevelDesigner.new(0,1,778).build()
	check(other.masks["silhouette"].get_data()!=source.masks["silhouette"].get_data(),"another design seed gives another mountain")

# Splits: the designer plans one per act; the generator builds each as a
# second way on its own ridge that rejoins the main route, out of any
# rope's reach in its middle; no filler grips crowd the face.
func split_tests() -> void:
	var designer := LevelDesigner.new(0,0,int(LevelCatalog.route(0,0)["seed"])*31+4)
	var source := designer.build()
	check(designer.splits.size()==3 and source.brief["splits"].size()==3,"the designer plans a split in every act")
	# Splits take different shapes, and acts lean the mountain apart.
	var styles := {}
	var repeats := 0
	var leans := 0
	for design in range(6):
		var other := LevelDesigner.new(0,0,900+design)
		other.plan()
		for k in range(other.splits.size()):
			styles[other.splits[k]["style"]] = true
			if k>0 and other.splits[k]["style"]==other.splits[k-1]["style"]: repeats += 1
		var centers: Array = []
		for section in other.sections: centers.append(float(section["center1"]))
		if centers.max()-centers.min()>=4.0: leans += 1
	check(styles.size()>=4 and repeats==0,"splits come in many shapes, never twice in a row %s" % str(styles.keys()))
	check(leans>=5,"acts lean the mountain to different sides (%d of 6 designs)" % leans)
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(int(source.brief["seeds"]["route"]),0,0,false,0,true)
	var layout := world.layout as MaskLayout
	layout.use_source(source)
	world.generate_to(designer.height+6,true,designer.height)
	check(layout.splits_built.size()==3,"every planned split is built %s" % str(layout.mask_notes.slice(0,2)))
	var isolated := true
	var far_grips := 0
	for split in layout.splits_built:
		var rows: Array = []
		var inside := false
		for id in layout.main_route:
			if id==split["entry"]: inside = true
			elif id==split["exit"]: inside = false
			elif inside: rows.append(id)
		var axis: float = (layout.anchors[split["entry"]]["pos"].x+layout.anchors[split["exit"]]["pos"].x)*.5
		for grip_id in split["grips"]:
			var grip: Vector2 = layout.anchors[grip_id]["pos"]
			if absf(grip.x-axis)<MaskLayout.ISOLATION+2.4: continue
			far_grips += 1
			for row_id in rows:
				if layout.anchors[row_id]["pos"].distance_to(grip)<MaskLayout.ISOLATION: isolated = false
	check(far_grips>=6 and isolated,"the far part of every split is out of any rope's reach of the main route (%d far grips)" % far_grips)
	# A crystal points at both ways, and only real partings have one.
	var crystals := 0
	var forks_ok := true
	for anchor in layout.anchors:
		if GripSpec.kind_of(anchor)==GripSpec.CRYSTAL:
			crystals += 1
			if not GripSpec.fork(anchor): forks_ok = false
	for split in layout.splits_built:
		var exits: Array = layout.anchors[split["entry"]].get("choice_exits",[])
		if not GripSpec.fork(layout.anchors[split["entry"]]) or exits.size()!=2 or not exits.has(split["grips"][0]): forks_ok = false
	check(forks_ok and crystals==layout.splits_built.size(),"a crystal stands at every split and nowhere else (%d)" % crystals)
	# The long way pays better than the direct one.
	for split in layout.splits_built:
		var y0: float = layout.anchors[split["entry"]]["pos"].y
		var y1: float = layout.anchors[split["exit"]]["pos"].y
		var stretch: Array = []
		for id in layout.main_route:
			if layout.anchors[id]["pos"].y>y0 and layout.anchors[id]["pos"].y<y1: stretch.append(id)
		var direct := 0
		var detour := 0
		var treasure := false
		# Each find belongs to the way whose grips it is nearest to.
		for find in layout.finds:
			if find["pos"].y<y0 or find["pos"].y>y1: continue
			var to_main := INF
			var to_way := INF
			for id in stretch: to_main = minf(to_main,find["pos"].distance_to(layout.anchors[id]["pos"]))
			for id in split["grips"]: to_way = minf(to_way,find["pos"].distance_to(layout.anchors[id]["pos"]))
			if to_main<to_way: direct += int(find["item"]["value"])
			else:
				detour += int(find["item"]["value"])
				if find["role"]=="route_treasure": treasure = true
		check(treasure and detour>=direct*3,"the second way holds a treasure and at least three times the direct way's value (%d against %d)" % [detour,direct])
	var filler := 0
	for anchor in layout.anchors:
		if str(anchor.get("role",""))=="auxiliary" and not anchor.has("split") and not anchor.get("reserve",false): filler += 1
	check(filler<=6,"a drawn level has no filler grips across the face (%d left)" % filler)
	var verdict := LevelScore.evaluate(layout,source,designer.sections)
	check(verdict["usable"] and float(verdict["score"])>0.5,"the level scores as usable %s" % str(verdict["metrics"]))
	var path := []
	path.append_array(layout.main_route)
	check(path.size()>10,"the main route stays whole beside its splits")
