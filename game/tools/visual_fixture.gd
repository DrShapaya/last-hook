extends SceneTree

# Visual fixture for the mountain: renders a fixed set of frames of one
# location without the HUD, the hero or the follow camera, so changes to the
# stone, mounts, decor and light can be compared frame by frame.
#   Godot --path game --script res://tools/visual_fixture.gd -- --out=DIR
#         [--location=0] [--quality=balanced] [--seed=58273] [--acts]
# --acts: the expedition of the location, one overview per act plus its
# fork, hazard (shown in its telegraph or active phase) and landmark.
# Lighting mirrors main.gd::_setup_lighting and _apply_shadow_preset.

const MainScript := preload("res://scripts/main.gd")
var out_dir := ""
var location := 0
var quality := "balanced"
var seed_value := 58273
var world: MountainWorld
var camera: Camera3D
var frames: Array = []
# --reference: the acceptance screen only, in three variants.
var reference := false
var acts := false
# --gameplay: four frames at the play camera size round finds and grips.
var gameplay := false

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
		if argument.begins_with("--location="): location = int(argument.trim_prefix("--location="))
		if argument.begins_with("--quality="): quality = argument.trim_prefix("--quality=")
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		if argument=="--reference": reference = true
		if argument=="--acts": acts = true
		if argument=="--gameplay": gameplay = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(540,960)
	var stage := Node3D.new()
	root.add_child(stage)
	_light(stage)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .1
	camera.far = 120
	stage.add_child(camera)
	camera.current = true
	world = MountainWorld.new()
	stage.add_child(world)
	world.setup(seed_value,location)
	world.set_visual_quality(quality)
	var total := float(LevelCatalog.level(location)["height_units"]) if acts else 120.0
	world.generate_to(total+6,true,total)
	_plan()
	_run()

func _light(stage: Node3D) -> void:
	var node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("88bfd9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c7d6")
	environment.ambient_light_energy = .62
	environment.glow_enabled = true
	environment.glow_intensity = .10
	environment.glow_strength = .45
	environment.glow_hdr_threshold = 1.15
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	node.environment = environment
	stage.add_child(node)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(MainScript.SUN_DIRECTION,Vector3.UP)
	sun.light_color = Color("fff0d2")
	sun.light_specular = .35
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_fade_start = .9
	sun.directional_shadow_pancake_size = 0.0
	sun.shadow_bias = .04
	sun.shadow_normal_bias = 1.2
	sun.light_energy = MainScript.SUN_ENERGY*(3.2 if quality=="battery" else 1.0)
	sun.shadow_enabled = quality!="battery"
	sun.shadow_opacity = .46 if quality=="high" else .44
	sun.shadow_blur = 1.8 if quality=="high" else 1.4
	sun.directional_shadow_max_distance = 46 if quality=="high" else 42
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality=="high" else 2048,true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	stage.add_child(sun)

func _reference_center() -> Vector2:
	# The acceptance screen: beside the first arch window above the start,
	# halfway to the route, so the window, the trunk with its grips, shelves
	# and finds, and the overhang or islands share one camera frame.
	var visuals := world.visuals as MassifVisuals
	for band in range(1,4): visuals.front_band(band)
	for opening in visuals.arch_openings:
		if opening.position.y<20: continue
		var at := opening.get_center()
		return Vector2(lerpf(at.x,visuals.route_x_at(at.y),.55),at.y+2.0)
	return Vector2(visuals.route_x_at(36),36)

func _act_frames() -> void:
	var layout := world.layout as ExpeditionLayout
	var visuals := world.visuals as MassifVisuals
	for act in range(3):
		var span := layout.span(act)
		var tag := "act_l%d_%d_%s" % [location,act+1,span["id"]]
		var middle := (float(span["y_start"])+float(span["y_end"]))*.5
		frames.append({"name":tag+"_overview","at":Vector2(visuals.route_x_at(middle),middle),"size":24.0})
		for branch in layout.branches:
			if int(branch.get("act",-1))!=act or branch.get("choice",false): continue
			if branch["route_tag"] in ["risky_shortcut","speed","choice"] or (branch["route_tag"]=="collection" and branch["beat"]=="fork"):
				var grip: Vector2 = world.anchors[branch["anchor"]]["pos"]
				frames.append({"name":tag+"_fork","at":grip+Vector2(0,1.0),"size":13.0})
				break
		for hazard in layout.hazards:
			if int(hazard["act"])!=act: continue
			var at := Vector2.ZERO
			if hazard.has("rect"): at = (hazard["rect"] as Rect2).get_center()
			elif hazard.has("pos"): at = hazard["pos"]
			elif hazard.has("x"): at = Vector2(hazard["x"],(float(hazard["top"])+float(hazard["bottom"]))*.5)
			else: at = Vector2((float(world.ledges[int(hazard["ledge"])]["left"])+float(world.ledges[int(hazard["ledge"])]["right"]))*.5,float(world.ledges[int(hazard["ledge"])]["top"]))
			frames.append({"name":"%s_hazard_%d_%s" % [tag,int(hazard["id"]),hazard["def"]],"at":at,"size":11.0,"hazard":hazard["id"]})
		for mark in layout.landmarks:
			if int(mark["act"])==act:
				frames.append({"name":"%s_landmark_%s" % [tag,mark["family"]],"mark":mark,"at":mark["pos"]+Vector2(0,1.4),"size":9.0})
				break

# A time at which the hazard shows its telegraph (or its active phase).
func _hazard_time(hazard: Dictionary) -> float:
	match str(hazard["kind"]):
		"field", "contact":
			if is_inf(float(hazard["active_time"])): return 0.0
			return float(hazard["calm_time"])+float(hazard["telegraph_time"])+float(hazard["active_time"])*.4-float(hazard["phase"])+ActHazards.cycle(hazard)*2
		"falling":
			world.hazards._state(hazard)["triggered"] = 10.0
			return 10.0+float(hazard["telegraph_time"])*.7
		"collapse":
			world.hazards._state(hazard)["triggered"] = 10.0
			return 10.0+float(hazard["telegraph_time"])*.6
	return 0.0

func _plan() -> void:
	if acts and world.layout is ExpeditionLayout:
		_act_frames()
		return
	if gameplay:
		# Gameplay framing (camera_base_size 24) round finds that share the
		# screen with grips: platforms, strips and loot read together.
		var last := -INF
		for find in world.finds:
			var at: Vector2 = find["pos"]
			if at.y<8 or at.y-last<22 or frames.size()>=8: continue
			last = at.y
			frames.append({"name":"play_l%d_%s_s%d_%d" % [location,quality,seed_value,frames.size()/2],"at":Vector2(at.x,at.y+3.0),"size":24.0})
			frames.append({"name":"play_l%d_%s_s%d_%d_close" % [location,quality,seed_value,frames.size()/2],"at":Vector2(at.x,at.y+1.5),"size":11.0})
		return
	if reference and world.visuals is MassifVisuals:
		var at := _reference_center()
		var tag := "ref_l%d_%s" % [location,quality]
		frames.append({"name":tag+"_1_bare","at":at,"size":24.0,"show":"bare"})
		frames.append({"name":tag+"_2_objects","at":at,"size":24.0,"show":"objects"})
		frames.append({"name":tag+"_3_full","at":at,"size":24.0,"show":"full"})
		return
	# Two overviews, then close-ups of one grip of every kind on hand, a
	# shelf, a hazard and a find.
	var tag := "l%d_%s" % [location,quality]
	frames.append({"name":tag+"_overview_a","at":Vector2(world.layout.anchors[world.main_route[6]]["pos"].x,40),"size":24.0})
	frames.append({"name":tag+"_overview_b","at":Vector2(world.layout.anchors[world.main_route[min(20,world.main_route.size()-1)]]["pos"].x,78),"size":24.0})
	var kinds := {}
	for anchor in world.anchors:
		var kind := GripSpec.kind_of(anchor)
		if anchor["pos"].y<6 or anchor["pos"].y>110 or kinds.has(kind) or anchor.get("reserve",false): continue
		kinds[kind] = true
		frames.append({"name":"%s_grip_%d" % [tag,kind],"at":anchor["pos"],"size":7.0})
	for ledge in world.ledges:
		if float(ledge["top"])<6: continue
		frames.append({"name":tag+"_ledge","at":Vector2((float(ledge["left"])+float(ledge["right"]))*.5,float(ledge["top"])-.5),"size":7.0})
		break
	for obstacle in world.obstacles:
		if obstacle["pos"].y<6: continue
		frames.append({"name":tag+"_hazard","at":obstacle["pos"],"size":7.0})
		break
	for find in world.finds:
		if find["pos"].y<10: continue
		frames.append({"name":tag+"_find","at":find["pos"],"size":7.0})
		break
	# Landform set pieces of the rock-mass mountain.
	if world.visuals is MassifVisuals:
		var seen := {}
		for band in range(0,5):
			for mass in (world.visuals as MassifVisuals).front_band(band):
				if mass.landform in ["arch","overhang"] and not seen.has(mass.landform):
					seen[mass.landform] = true
					frames.append({"name":"%s_%s" % [tag,mass.landform],"at":mass.centroid()-Vector2(0,1.0),"size":11.0})
		# Without decor, the bare form (R2 acceptance).
		frames.append({"name":tag+"_bare","at":frames[0]["at"],"size":24.0,"bare":true})

func _run() -> void:
	for frame in frames:
		var at: Vector2 = frame["at"]
		# A landmark frame centres on where the face actually took it.
		if frame.has("mark"):
			world.update_visibility(at.y,at.x)
			if (frame["mark"] as Dictionary).has("built_at"): at = (frame["mark"]["built_at"] as Vector2)+Vector2(0,1.4)
		camera.size = frame["size"]
		camera.position = Vector3(at.x,at.y,28)
		camera.look_at(Vector3(at.x,at.y,0))
		world.update_visibility(at.y,at.x)
		if world.hazard_visuals!=null:
			var time := 0.0
			var haze := 0.0
			if frame.has("hazard"):
				var hazard: Dictionary = world.layout.hazards[int(frame["hazard"])]
				time = _hazard_time(hazard)
				haze = 1.0 if bool(hazard.get("haze",false)) else 0.0
			for repeat in range(60): world.hazard_visuals.update(time,at,haze,at)
		var show: String = frame.get("show","bare" if frame.get("bare",false) else "full")
		for chunk in world.chunks.values():
			for child in chunk.get_children():
				var node_name := String(child.name)
				var decor := node_name.begins_with("Процедурный декор") or node_name.begins_with("Крупный элемент")
				var rock := node_name.begins_with("Скальный массив")
				child.visible = show=="full" or rock or (show=="objects" and not decor)
		# Dormant reserve and hidden grips stay hidden, as in the game.
		for object in world.anchors:
			if is_instance_valid(object.get("visual")) and object["broken"]: object["visual"].visible = false
		for wait in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(frame["name"])+".png")
		root.get_texture().get_image().save_png(path)
		print("FIXTURE ",path," at=",at)
	world.queue_free()
	await process_frame
	quit()
