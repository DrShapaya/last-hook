extends SceneTree

# Generation from masks (MaskLayout) on a level painted in code: a broad
# mountain with a sky window, an S-shaped route corridor, a spring pin, a
# painted solid block and a rest patch.

var checks := 0
var failures: Array[String] = []
# Points this far inside the mask stand clear of the rock's rounded edge.
const ROLL_CLEAR := 3.6

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
	await winter_decor_tests()
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
			1:
				check(designer is DesertDesigner and layout.rock_form=="desert" and not (designer as DesertDesigner).tiers.is_empty(),"the canyon has its own designer and rock")
				desert_outline_tests()
			2: check(designer is WinterDesigner and layout.rock_form=="winter" and not layout.rock_marks.is_empty(),"the snow peak has its own designer, rock and shelves")
		if location>0:
			var rock := RockSurface.make(layout)
			var mesh := rock.build(24.0,48.0,1.0)
			check(mesh.get_surface_count()==1 and mesh.get_faces().size()>300,"location %d builds one continuous rock face" % location)
			var a := rock.build(24.0,48.0,1.0).get_faces()
			check(a==mesh.get_faces(),"the rock face of location %d is the same every time" % location)
		if location==1: desert_depth_tests(world,layout)
		if location==2:
			winter_depth_tests(world,layout)
			winter_outline_tests(designer,layout)
			winter_play_tests(layout)
		world.free()
	# A climb has a rhythm, and the far way has its risk.
	var sample := LevelDesigner.make(1,0,int(LevelCatalog.route(1,0)["seed"])*31)
	var brief_source := sample.build()
	var tempos := {}
	for entry in brief_source.brief["pace"]: tempos[snappedf(float(entry["rise"]),.1)] = true
	check(tempos.size()>=3,"sections climb at different tempos %s" % str(tempos.keys()))
	var plain: Array = brief_source.brief["splits"]
	check(str(plain[0]["risk"])=="" and str(plain[1]["risk"])=="sand_storm","the first split teaches, the later ones carry the location's hazard")
	var risky_world := MountainWorld.new()
	risky_world.visuals_enabled = false
	root.add_child(risky_world)
	risky_world.setup(int(brief_source.brief["seeds"]["route"]),1,0,false,0,true)
	var risky := risky_world.layout as MaskLayout
	risky.use_source(brief_source)
	risky_world.generate_to(sample.height+6,true,sample.height)
	var on_far := 0
	for hazard in risky.hazards:
		if hazard.has("rect") and not hazard.get("affects_main",false) and (hazard["rect"] as Rect2).size.y>8.0: on_far += 1
	check(on_far>=1 or risky.splits_built.size()<3,"a storm stands over the second way (%d)" % on_far)
	risky_world.free()
	check(int(parted_rows[1])>0 and int(parted_rows[2])>0,"the canyon and the peak part into separate masses %s" % str(parted_rows))

# The canyon has real depth, and what stands on it stands on the rock in view.
func desert_depth_tests(world: MountainWorld, layout: MaskLayout) -> void:
	var rock := RockSurface.make(layout)
	var depths: Array = []
	var y := 10.0
	while y<130.0:
		var x := -16.0
		while x<=16.0:
			if rock.distance(Vector2(x,y))>3.0: depths.append(rock.height(Vector2(x,y)))
			x += 1.0
		y += 1.0
	depths.sort()
	var low: float = depths[int(depths.size()*.05)]
	var high: float = depths[int(depths.size()*.95)]
	print("DESERT_DEPTH ",low," .. ",high)
	check(high-low>=3.0,"the canyon's face spans 3 units of depth (%.2f .. %.2f)" % [low,high])
	# A ledge overhangs: the rock falls far back under it, into a hollow deeper
	# than the wall further down.
	var drops: Array = []
	var hollows: Array = []
	for ledge in layout.rock_marks:
		var at := Vector2(float(ledge[3]),float(ledge[0])-1.0)
		if rock.distance(at)<ROLL_CLEAR or rock.distance(at+Vector2(0,-3.0))<ROLL_CLEAR: continue
		var crest := rock.height(Vector2(at.x,lerpf(float(ledge[0]),float(ledge[1]),.45)))
		drops.append(crest-rock.height(at))
		hollows.append(rock.height(at+Vector2(0,-3.0))-rock.height(at))
	drops.sort()
	hollows.sort()
	print("DESERT_UNDERCUT drop ",drops," hollow ",hollows)
	check(drops.size()>=2 and float(drops[drops.size()/2])>=3.0,"a ledge overhangs the rock under it by 3 units %s" % str(drops))
	check(float(hollows[hollows.size()/2])>=.5,"under a ledge lies a hollow, deeper than the wall below %s" % str(hollows))
	# The outline has no spikes: at the coarsest preset no vertex of the face
	# stands off the mask, and hardly any stone is a thin sharp tip.
	var worst := 0.0
	var boulders: Array = rock.lumps(48.0,72.0)
	for vertex in rock.build(48.0,72.0,1.0).get_faces():
		# The far wall of a cave lies behind the opening on purpose.
		if vertex.z<DesertRock.EDGE_Z-.2: continue
		var on_boulder := false
		for boulder in boulders:
			if Vector2(vertex.x,vertex.y).distance_to(Vector2(boulder[0].x,boulder[0].y))<=maxf(boulder[1].x,boulder[1].y)*1.3:
				on_boulder = true
				break
		if not on_boulder: worst = maxf(worst,-rock.distance(Vector2(vertex.x,vertex.y)))
	var stone := 0
	var tips := 0
	y = 6.0
	while y<130.0:
		var x := -19.0
		while x<=19.0:
			if rock.distance(Vector2(x,y))>0:
				stone += 1
				var deepest := rock.distance(Vector2(x,y))
				for turn in range(12): deepest = maxf(deepest,rock.distance(Vector2(x,y)+Vector2.RIGHT.rotated(TAU*turn/12.0)*.9))
				if deepest<.75: tips += 1
			x += .5
		y += .5
	var tip_share := float(tips)/stone
	print("DESERT_SPIKES off mask ",worst," tips ",tip_share)
	check(worst<=.2,"no vertex of the rock stands off the mask (%.2f)" % worst)
	# Thin arches and bridges count too, so some stone always falls here.
	check(tip_share<=.02,"thin sharp tips are rare (%.3f of the stone)" % tip_share)
	# Caves lie in thick rock, and nothing the player needs stands in one.
	check(layout.rock_caves.size()>=3,"the canyon has caves (%d)" % layout.rock_caves.size())
	var in_cave := 0
	var off_stone := 0
	for cave in layout.rock_caves:
		var at := Vector2(float(cave[0]),float(cave[1]))
		if layout.inside_distance(at)<float(cave[3]): off_stone += 1
		check(rock.distance(at)<0.0,"a cave opens the face, it is no paint on it")
		var spots: Array = []
		for anchor in layout.anchors: spots.append(anchor["pos"])
		for find in layout.finds: spots.append(find["pos"])
		for spot: Vector2 in spots:
			if ((spot-at)/Vector2(float(cave[2]),float(cave[3]))).length()<1.0: in_cave += 1
	check(off_stone==0,"every cave lies inside the rock (%d do not)" % off_stone)
	check(in_cave==0,"no grip or find stands in a cave (%d do)" % in_cave)
	# Near its edge the rock has a side: it faces away from the viewer, not at him.
	var sides: Array = []
	y = 6.0
	while y<130.0:
		var x := -19.0
		while x<=19.0:
			var inside := rock.distance(Vector2(x,y))
			if inside>.3 and inside<.9: sides.append(rock.normal_at(Vector2(x,y)).z)
			x += .5
		y += .5
	sides.sort()
	var side: float = sides[sides.size()/2]
	print("DESERT_SIDE ",side)
	check(side<=.55,"the rock turns away from the viewer at its edge (normal z %.2f)" % side)
	var visuals := MassifVisuals.new(world,layout)
	var off_face := 0
	for id in layout.main_route:
		var point: Vector2 = layout.anchors[id]["pos"]
		if rock.distance(point)>0 and absf(visuals.wall_depth(point)-rock.height(point))>.01: off_face += 1
	check(off_face==0,"grips take their depth from the rock in view (%d do not)" % off_face)

# The snow tower has real depth: columns and the cracks between them, an edge
# rolling far back, shelves standing out over a hollow, and grips on the rock
# in view.
func winter_depth_tests(world: MountainWorld, layout: MaskLayout) -> void:
	var rock := RockSurface.make(layout)
	var depths: Array = []
	var edges: Array = []
	var sides: Array = []
	var y := 10.0
	while y<130.0:
		var x := -16.0
		while x<=16.0:
			var inside := rock.distance(Vector2(x,y))
			if inside>3.0: depths.append(rock.height(Vector2(x,y)))
			elif inside>.05 and inside<.3: edges.append(rock.height(Vector2(x,y)))
			if inside>.3 and inside<.9: sides.append(rock.normal_at(Vector2(x,y)).z)
			x += .5
		y += .5
	depths.sort()
	edges.sort()
	sides.sort()
	var low: float = depths[int(depths.size()*.05)]
	var high: float = depths[int(depths.size()*.95)]
	var middle: float = depths[depths.size()/2]
	var edge: float = edges[edges.size()/2]
	var side: float = sides[sides.size()/2]
	print("WINTER_DEPTH ",low," .. ",high," middle ",middle," edge ",edge," side ",side)
	check(high-low>=3.0,"the tower's face spans 3 units of depth (%.2f .. %.2f)" % [low,high])
	check(middle-edge>=4.0,"the tower stands well out from its own edge (%.2f over %.2f)" % [middle,edge])
	check(side<=.55,"the tower turns away from the viewer at its edge (normal z %.2f)" % side)
	# A shelf stands out of the tower over a hollow cut under it.
	var outs: Array = []
	for shelf in layout.rock_marks:
		var at := Vector2(float(shelf[0]),float(shelf[1])-float(shelf[4])*.7)
		if rock.distance(at)<3.0 or rock.distance(at+Vector2(0,-float(shelf[4])))<3.0: continue
		outs.append(rock.height(at)-rock.height(at-Vector2(0,float(shelf[4])*.5+.6)))
	outs.sort()
	print("WINTER_SHELVES ",outs)
	check(outs.size()>=2 and float(outs[outs.size()/2])>=1.5,"a shelf stands out over the hollow under it %s" % str(outs))
	var visuals := MassifVisuals.new(world,layout)
	var off_face := 0
	for id in layout.main_route:
		var point: Vector2 = layout.anchors[id]["pos"]
		if rock.distance(point)>0 and absf(visuals.wall_depth(point)-rock.height(point))>.01: off_face += 1
	check(off_face==0,"grips take their depth from the rock in view (%d do not)" % off_face)

# The peak's outline after winter_4k.png: shelves wind one way round the
# tower, cones stand only on the loops and the crown, and the tower's own
# flanks are rough but carry no sharp tips.
func winter_outline_tests(designer: LevelDesigner, layout: MaskLayout) -> void:
	var winter := designer as WinterDesigner
	var rising := 0
	var falling := 0
	for shelf in winter.shelves:
		if float(shelf[3])>0.0: rising += 1
		else: falling += 1
	check(winter.shelves.size()>=6 and mini(rising,falling)==0,"the shelves wind one way up the tower (%d up, %d down)" % [rising,falling])
	var loose := 0
	for tooth in winter.get("teeth") if "teeth" in winter else []:
		var y: float = (tooth[0] as Vector2).y
		if winter._split_near(y).is_empty() and y<winter.height-10.0: loose += 1
	check("teeth" in winter and (winter.get("teeth") as Array).size()>=8 and loose==0,"cones stand on the loops and the crown only (%d elsewhere)" % loose)
	# Tips are counted away from the cones, horns and islands, which are
	# pointed on purpose.
	var rock := RockSurface.make(layout)
	var pointed: Array = []
	for tooth in winter.get("teeth") if "teeth" in winter else []: pointed.append([tooth[0],4.0])
	for shard in winter.shards: pointed.append([Vector2(float(shard[0]),float(shard[1])),4.5])
	for horn in winter.horns: pointed.append([Vector2(float(horn[0]),(float(horn[1])+float(horn[2]))*.5),(float(horn[2])-float(horn[1]))*.6])
	var stone := 0
	var tips := 0
	var y := 6.0
	while y<winter.height-10.0:
		var x := -19.0
		while x<=19.0:
			var at := Vector2(x,y)
			if rock.distance(at)>0:
				var spared := false
				for spot in pointed:
					if at.distance_to(spot[0])<float(spot[1]):
						spared = true
						break
				if not spared:
					stone += 1
					var deepest := rock.distance(at)
					for turn in range(12): deepest = maxf(deepest,rock.distance(at+Vector2.RIGHT.rotated(TAU*turn/12.0)*.9))
					if deepest<.75: tips += 1
			x += .5
		y += .5
	var share := float(tips)/stone
	print("WINTER_TIPS ",share)
	check(share<=.01,"the tower's own outline has no sharp tips (%.3f of the stone)" % share)

# The baked snow peak dresses its own rock: rows of ice under the shelves,
# crystals on its tops, every piece seated on the outline the player sees and
# none in a heap.
func winter_decor_tests() -> void:
	var level := ResourceLoader.load(LevelBake.layout_path(2,0),"",ResourceLoader.CACHE_MODE_IGNORE) as LevelBake
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(level.seed_value,2,MountainWorld.generation_version_for(2),false,0,true)
	world.set_visual_quality("balanced")
	world.load_bake(level)
	var visuals: MassifVisuals = world.visuals
	var shelf_ice := 0
	var crystals := 0
	var hung := true
	var stood := true
	var spots: Array[Vector2] = []
	var snowing := 0
	var blowing := 0
	var chunks := world._ready_chunk()+1
	for key in range(chunks):
		var scenery := Node3D.new()
		world.add_child(scenery)
		await visuals.build_chunk(key,scenery)
		if not scenery.find_children("Снегопад_*","GPUParticles3D",true,false).is_empty(): snowing += 1
		blowing += scenery.find_children("Сдув_*","GPUParticles3D",true,false).size()
		for holder: Node3D in scenery.get_children():
			var name := String(holder.name)
			var at := Vector2(holder.position.x,holder.position.y)
			if name.begins_with("Подвес_"):
				hung = hung and not visuals.open_at(at+Vector2(0,.12))
				if name.begins_with("Подвес_полки"): shelf_ice += 1
			elif name.begins_with("Кристалл_"):
				crystals += 1
				# A foot may rest on a top that rises up to .35 under it.
				stood = stood and not visuals.open_at(at-Vector2(0,.1)) and visuals.open_at(at+Vector2(0,.45))
			else: continue
			spots.append(at)
		scenery.free()
	var heaped := 0
	for spot in spots:
		var near := 0
		for other in spots: if other!=spot and other.distance_to(spot)<1.0: near += 1
		if near>=2: heaped += 1
	var slabs := 0
	var rests := Node3D.new()
	world.add_child(rests)
	for ledge in world.layout.ledges:
		visuals.build_ledge(ledge,rests)
		if is_instance_valid(ledge.get("visual")) and (ledge["visual"] as Node).find_child("Снежная плита",false,false)!=null: slabs += 1
	check(slabs>0 and slabs==world.layout.ledges.size(),"every rest on the peak is a snow slab of its rock (%d of %d)" % [slabs,world.layout.ledges.size()])
	rests.free()
	print("WINTER_DECOR shelf ice ",shelf_ice," crystals ",crystals," heaped ",heaped)
	check(shelf_ice>=8,"ice hangs in rows under the snow shelves (%d)" % shelf_ice)
	check(crystals>=2,"crystals stand on the tops of the snow peak (%d)" % crystals)
	check(hung,"all ice hangs from the stone the player sees")
	check(stood,"every crystal stands on the stone the player sees, open air over it")
	check(heaped==0,"ice and crystals never pile up in one place (%d do)" % heaped)
	# Snow falls over the whole climb and the wind lifts it off the tops; the
	# battery preset goes without.
	print("WINTER_WEATHER snowing ",snowing," of ",chunks," blowing ",blowing)
	check(snowing==chunks,"snow falls over every band of the peak (%d of %d)" % [snowing,chunks])
	check(blowing>=chunks,"the wind lifts snow off the tops (%d puffs)" % blowing)
	world.set_visual_quality("battery")
	var light := Node3D.new()
	world.add_child(light)
	await visuals.build_chunk(1,light)
	check(light.find_children("Снегопад_*","GPUParticles3D",true,false).is_empty() and light.find_children("Сдув_*","GPUParticles3D",true,false).is_empty(),"the battery preset draws no snow particles")
	light.free()
	world.free()

# The snow peak plays its own way: its far ways are glazed with ice, whose
# slide always leaves the next grip in reach; falling ice hangs over the
# crevasse act's far way; the main route never needs either.
func winter_play_tests(layout: MaskLayout) -> void:
	var main := {}
	for id in layout.main_route: main[id] = true
	var far_ice := 0
	var main_ice := 0
	var stuck := 0
	for split in layout.splits_built:
		var grips: Array = split["grips"]
		for k in range(grips.size()):
			var grip: Dictionary = layout.anchors[grips[k]]
			if GripSpec.kind_of(grip)!=GripSpec.ICE: continue
			far_ice += 1
			var next: Vector2 = layout.anchors[grips[k+1]]["pos"] if k+1<grips.size() else layout.anchors[split["exit"]]["pos"]
			if not RouteGraph.exit_after_effect(layout,grip,next): stuck += 1
	for id in layout.main_route:
		if GripSpec.kind_of(layout.anchors[id])==GripSpec.ICE: main_ice += 1
	var icicles := 0
	var far_icicles := 0
	for hazard in layout.hazards:
		if str(hazard["def"])!="icicle": continue
		icicles += 1
		for split in layout.splits_built:
			if int(hazard.get("branch_anchor",-1)) in split["grips"]: far_icicles += 1
	print("WINTER_PLAY far ice ",far_ice," main ice ",main_ice," stuck ",stuck," icicles ",icicles," on far ways ",far_icicles)
	check(far_ice>=6 and main_ice==0,"the far ways are glazed with ice, the main route never (%d far, %d main)" % [far_ice,main_ice])
	check(stuck==0,"every ice grip slides to where the next grip is in reach (%d do not)" % stuck)
	check(icicles>=2 and far_icicles>=1,"falling ice hangs over the climb and over a far way (%d, %d on far ways)" % [icicles,far_icicles])

# Rock has no ruled edges: no long dead-level rim and no long straight wall on
# any route of the canyon. The very top is left out, its cap carries the summit.
func desert_outline_tests() -> void:
	for route in range(3):
		var designer := LevelDesigner.make(1,route,int(LevelCatalog.route(1,route)["seed"])*31)
		var source := designer.build()
		var mask: Image = source.masks["silhouette"]
		var longest_rim := 0
		var rim_at := 0.0
		var longest_wall := 0
		var wall_at := 0.0
		var runs := [0,0]
		var edges := [-INF,-INF]
		var last_row := PackedByteArray()
		for row in range(mask.get_height()-1,-1,-1):
			var y := source.to_world(Vector2(0,row)).y
			if y>designer.height-2.0: continue
			var stone := PackedByteArray()
			stone.resize(mask.get_width())
			var first := -1
			var last := -1
			for x in range(mask.get_width()):
				if mask.get_pixel(x,row).r>.5:
					stone[x] = 1
					if first<0: first = x
					last = x
			if not last_row.is_empty():
				var run := 0
				for x in range(mask.get_width()):
					run = run+1 if stone[x]!=last_row[x] else 0
					if run>longest_rim:
						longest_rim = run
						rim_at = y
			last_row = stone
			for side in range(2):
				var edge: float = first if side==0 else last
				if edge<0 or absf(edge-float(edges[side]))>2.0:
					runs[side] = 0
					edges[side] = edge
				runs[side] += 1
				if runs[side]>longest_wall:
					longest_wall = runs[side]
					wall_at = y
		var rim := longest_rim/float(LevelSource.PX_PER_UNIT)
		var wall := longest_wall/float(LevelSource.PX_PER_UNIT)
		print("DESERT_OUTLINE route ",route," rim ",rim," at ",rim_at," wall ",wall," at ",wall_at)
		# The belly of a wide ledge may run level for a short way, as in the picture.
		check(rim<=4.0,"route %d has no dead-level rim over 4 units (%.1f at %.1f)" % [route,rim,rim_at])
		check(wall<=6.0,"route %d has no straight wall over 6 units (%.1f at %.1f)" % [route,wall,wall_at])

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
