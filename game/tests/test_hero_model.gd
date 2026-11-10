extends SceneTree

# The 3D hero model (docs/CHARACTER_3D_PLAN.md): it loads, carries the skeleton
# the animations will need, stays within the mobile budget and is textured.

const MODEL := "res://assets/hero/model/hero.glb"
const BONES := ["root","pelvis","spine","chest","neck","head","backpack",
	"upper_arm_near","forearm_near","hand_near","upper_arm_far","forearm_far","hand_far",
	"thigh_near","shin_near","foot_near","thigh_far","shin_far","foot_far"]
# The detailed hero (export_showcase.py): buckles, laces and treads as
# geometry. One skinned mesh; the owner chose it over a simplified model.
const MIN_TRIANGLES := 150000
const MAX_TRIANGLES := 320000

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("HERO MODEL FAILED: "+description)

func find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := find(child,type)
		if found: return found
	return null

func run_tests() -> void:
	check(ResourceLoader.exists(MODEL),"the model file is imported")
	var hero: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(hero)
	var skeleton := find(hero,"Skeleton3D") as Skeleton3D
	check(skeleton!=null,"the model has a skeleton")
	if skeleton==null:
		finish()
		return
	for bone in BONES: check(skeleton.find_bone(bone)>=0,"bone %s exists" % bone)
	var mesh_instance := find(hero,"MeshInstance3D") as MeshInstance3D
	check(mesh_instance!=null and mesh_instance.skin!=null,"the mesh is skinned to the skeleton")
	var triangles := 0
	for surface in range(mesh_instance.mesh.get_surface_count()):
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size()/3 if indices.size()>0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3
	print("hero model: %d triangles, %d bones" % [triangles,skeleton.get_bone_count()])
	check(triangles>MIN_TRIANGLES and triangles<MAX_TRIANGLES,"the model keeps its details within budget (%d triangles)" % triangles)
	# Colour and occlusion in the vertices, slot and roughness in the UVs.
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_COLOR]!=null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size()>0,"the model carries its colour in the vertices")
	check(arrays[Mesh.ARRAY_TEX_UV]!=null,"the model carries slot and roughness")
	# Height: head top about 1.0 model units above the feet.
	var aabb := mesh_instance.get_aabb()
	check(absf(aabb.size.y-1.0)<.08,"the hero is one unit tall (%.2f)" % aabb.size.y)
	# A bent elbow moves the hand bone: the skeleton drives the arm.
	var hand := skeleton.find_bone("hand_near")
	var before := skeleton.get_bone_global_pose(hand).origin
	var elbow := skeleton.find_bone("forearm_near")
	skeleton.set_bone_pose_rotation(elbow,skeleton.get_bone_rest(elbow).basis.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,1.0))
	skeleton.force_update_all_bone_transforms()
	check(skeleton.get_bone_global_pose(hand).origin.distance_to(before)>.03,"bending the elbow moves the hand")
	hero.queue_free()
	hero_model_tests()
	finish()

# HeroModel: every HeroState state has motion, the game's motion picks the
# right one, the pose follows it and the rope leaves from the hand.
func hero_model_tests() -> void:
	for state in HeroState.STATES:
		check(HeroModel.CLIPS.has(state) or state in HeroModel.LIVE,"state %s has a clip" % state)
	for clip in HeroModel.CLIPS.values():
		for key in clip[1]:
			for bone in key[1]: check(bone in BONES,"clip bone %s exists in the model" % bone)
	var model := HeroModel.new()
	root.add_child(model)
	model.setup()
	check(model.mesh.material_override is ShaderMaterial,"the hero carries its own shading")
	var shading := model.mesh.material_override as ShaderMaterial
	check(model.mesh.layers==HeroModel.HERO_LAYER,"the hero sits on his own light layer")
	check(model.lights.size()==2 and model.lights.all(func(l): return l.light_cull_mask==HeroModel.HERO_LAYER and not l.shadow_enabled),"in the climb two own lights, no shadows")
	check(shading.next_pass!=null,"the climb keeps the outline")
	var close := HeroModel.new()
	root.add_child(close)
	close.setup(true)
	check(close.lights.size()==4 and close.lights[0].shadow_enabled,"close-ups get a rim light, a front fill and shadows")
	check(close.lights[0].global_transform.basis.z.x>0,"the close-up key comes from the side the hero faces (+X)")
	check((close.mesh.material_override as ShaderMaterial).next_pass==null,"close-ups go without the outline")
	close.queue_free()
	var battery := HeroModel.new()
	root.add_child(battery)
	battery.setup(true,false)
	check(battery.lights.size()==1 and not battery.lights[0].shadow_enabled,"battery: one light, no shadows")
	battery.queue_free()
	var sim := RopeSim.new()
	var time := 0.0
	for i in range(30):
		time += 1.0/30
		model.animate(sim,sim.pos+Vector2(2,3),false,time)
	check(model.state=="idle","standing still is idle (%s)" % model.state)
	var hand_rest := model.skeleton.get_bone_global_pose(model.bone_index["hand_near"]).origin
	sim.vel = Vector2(2.6,0)
	for i in range(30):
		time += 1.0/30
		sim.pos += sim.vel/30
		model.animate(sim,sim.pos+Vector2(2,3),false,time)
	check(model.state=="walk","moving on the ground walks (%s)" % model.state)
	check(absf(float(model.current.get("thigh_near",0.0))-float(model.current.get("thigh_far",0.0)))>.05,"legs move apart while walking")
	var grip := model.grip_position()
	var hand := model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bone_index["hand_near"]).origin
	check(grip.distance_to(hand)<.1,"the rope leaves from the near hand")
	sim.grounded = false
	sim.vel = Vector2(1,-7)
	for i in range(20):
		time += 1.0/30
		sim.pos += sim.vel/30
		model.animate(sim,sim.pos+Vector2(2,3),false,time)
	check(model.state=="fall","dropping through the air falls (%s)" % model.state)
	var moved := model.skeleton.get_bone_global_pose(model.bone_index["hand_near"]).origin.distance_to(hand_rest)
	check(moved>.05,"the arms move with the state (%.2f)" % moved)
	# Walking: a foot on the ground barely slides, and the lower foot stays on
	# the ground (no floating while a leg swings).
	var walker := HeroModel.new()
	root.add_child(walker)
	walker.setup()
	var ground := RopeSim.new()
	ground.vel = Vector2(walker.walk_speed,0)
	var tracks := {"near":[],"far":[]}
	var lowest_heights: Array[float] = []
	for i in range(240):
		time += 1.0/60
		ground.pos += ground.vel/60
		walker.position.x = ground.pos.x
		walker.animate(ground,ground.pos+Vector2(2,3),false,time)
		walker.skeleton.force_update_all_bone_transforms()
		var low := INF
		for side in ["near","far"]:
			var foot: Vector3 = walker.skeleton.global_transform*walker.skeleton.get_bone_global_pose(walker.bone_index["foot_"+side]).origin
			tracks[side].append(foot)
			low = minf(low,foot.y)
		if i>60: lowest_heights.append(low)
	var floor_y: float = lowest_heights.min()
	var slide := 0.0
	var samples := 0
	for side in tracks:
		var track: Array = tracks[side]
		for i in range(61,track.size()):
			# Planted: on the ground now and a frame ago.
			if track[i].y<floor_y+.012 and track[i-1].y<floor_y+.012:
				slide += absf(track[i].x-track[i-1].x)*60
				samples += 1
	var skate := slide/maxf(1,samples)/walker.walk_speed
	print("walk: planted foot slides at %.0f%% of walking speed, lower foot rises up to %.3f" % [skate*100,lowest_heights.max()-floor_y])
	check(samples>30,"the walk plants its feet (%d planted frames)" % samples)
	check(skate<.35,"the planted foot does not skate (%.0f%% of walking speed)" % (skate*100))
	check(lowest_heights.max()-floor_y<.02,"the lower foot stays on the ground while walking")
	walker.queue_free()
	# Swinging: the anchor passes overhead back and forth; the facing holds.
	var swinger := HeroModel.new()
	root.add_child(swinger)
	swinger.setup()
	var rope := RopeSim.new()
	rope.grounded = false
	rope.attached = true
	rope.anchor = Vector2(0,4)
	var flips := 0
	var last_facing := 0.0
	var mid_turn := 0
	for i in range(240):
		time += 1.0/60
		var phase := sin(i/60.0*TAU/1.6)
		rope.pos = Vector2(-phase*2.2,4-3.4*cos(phase*.6))
		rope.vel = Vector2(-cos(i/60.0*TAU/1.6)*4.5,0)
		swinger.animate(rope,rope.anchor,true,time)
		if i>30:
			if last_facing!=0.0 and swinger.facing!=last_facing: flips += 1
			if absf(sin(swinger.turn))>.3: mid_turn += 1
		last_facing = swinger.facing
	check(swinger.state=="swing","the swinger is swinging (%s)" % swinger.state)
	check(flips==0,"swinging does not turn the hero around (%d turns)" % flips)
	check(mid_turn==0,"no frame shows the hero mid-turn while swinging (%d)" % mid_turn)
	swinger.queue_free()
	game_event_tests()
	model.forced_state = "summit"
	for i in range(10):
		time += 1.0/30
		model.animate(sim,sim.pos+Vector2(2,3),false,time)
	check(model.state=="summit","a forced state holds for previews")
	model.queue_free()

# What main.gd sends: the release reason in the frame data, and the summit
# and revive events. Each one must show in the hero's state and pose.
func game_event_tests() -> void:
	var events := HeroModel.new()
	root.add_child(events)
	events.setup()
	var rope := RopeSim.new()
	rope.grounded = false
	rope.attached = true
	rope.anchor = Vector2(0,4)
	rope.pos = Vector2(0,1)
	var time := 0.0
	for i in range(30):
		time += 1.0/30
		events.animate(rope,rope.anchor,true,time)
	rope.attached = false
	events.flight_info = {"release_reason":"ice_slip"}
	time += 1.0/30
	events.animate(rope,rope.anchor,false,time)
	check(events.state=="slip","a grip that fails makes the hero slip (%s)" % events.state)
	events.flight_info = {"release_reason":"manual"}
	rope.attached = true
	for i in range(10):
		time += 1.0/30
		events.animate(rope,rope.anchor,true,time)
	rope.attached = false
	time += 1.0/30
	events.animate(rope,rope.anchor,false,time)
	check(events.state=="release","letting go by hand releases (%s)" % events.state)
	rope.grounded = true
	rope.vel = Vector2.ZERO
	for i in range(30):
		time += 1.0/30
		events.animate(rope,rope.pos+Vector2(2,3),false,time)
	events.hero_event("revive")
	time += 1.0/30
	events.animate(rope,rope.pos+Vector2(2,3),false,time)
	check(events.state=="revive","the revive event plays the revive (%s)" % events.state)
	for i in range(40):
		time += 1.0/30
		events.animate(rope,rope.pos+Vector2(2,3),false,time)
	# Summit: the result screen stops the game clock; the cheer still moves.
	events.hero_event("summit")
	var hand: int = events.bone_index["hand_near"]
	var poses: Array[Vector3] = []
	for i in range(12):
		OS.delay_msec(25)
		events.animate(rope,rope.pos+Vector2(2,3),false,time)
		events.skeleton.force_update_all_bone_transforms()
		poses.append(events.skeleton.get_bone_global_pose(hand).origin)
	check(events.state=="summit","the summit event plays the cheer (%s)" % events.state)
	check(poses[0].distance_to(poses[-1])>.03,"the cheer moves while the game clock is stopped")
	events.queue_free()

func finish() -> void:
	print("HERO_MODEL_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("  FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)
