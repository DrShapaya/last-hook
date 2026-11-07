extends SceneTree

# Frames of the stage 2 slice for the owner's review (CHARACTER_PLAN.md).
#
#   --mode=sheet   current hero next to the slice in neutral, wind-up, release,
#                  follow-through and the deepest elbow bend (one PNG).
#   --mode=bends   the deepest elbow at 2x for several bend settings (one PNG).
#   --mode=throw   the throw loop next to the current hero (numbered PNGs).
#   --mode=body    the whole hero: stand, walk, hang, throw, landing (one PNG).
#   --mode=walk    the whole hero's walk and throw loops (numbered PNGs).
# Pass --out=<folder>. Needs a window (no --headless): it renders.

var out := ""
var mode := "sheet"
var frame := 0
var rigs: Array = []
var current: ExplorerSprite
var root_node: Node3D
var labels: Array = []

func _initialize() -> void:
	call_deferred("setup")

func _camera(size: float, at: Vector3) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.position = at+Vector3(0,0,10)
	root_node.add_child(camera)
	camera.current = true

func _label(text: String, at: Vector2, width: float) -> void:
	var overlay := CanvasLayer.new()
	root_node.add_child(overlay)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	label.size.x = width
	label.add_theme_font_size_override("font_size",22)
	overlay.add_child(label)

func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1800,600) if mode!="bends" else Vector2i(1500,620)
	root.content_scale_size = root.size
	root_node = Node3D.new()
	root.add_child(root_node)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("223142")
	root_node.add_child(environment)
	match mode:
		"sheet":
			_camera(2.0,Vector3(0,0,0))
			var names := ["Нынешний","Покой","Замах","Бросок","Проводка","Локоть 135°"]
			var poses := [null,"neutral","wind_up","release","follow","deep_elbow"]
			for index in range(names.size()):
				var x := (index-2.5)*1.0
				if index==0:
					current = ExplorerSprite.new()
					current.position = Vector3(x,0,0)
					root_node.add_child(current)
					current.setup()
					current.animate(RopeSim.new(),Vector2(2,3),false,0)
				else:
					var rig := HeroRig.new()
					rig.position = Vector3(x,0,0)
					root_node.add_child(rig)
					rig.setup()
					rig.set_pose(HeroPrototypePoses.POSES[poses[index]])
					if poses[index]=="wind_up": rig.arm_behind_head()
				_label(names[index],Vector2(index*300,540),300)
		"bends":
			# 2x close-up of the elbow: plain blend vs half-angle helpers, three widths.
			var settings := [[.25,false],[.55,false],[.55,true],[.8,true],[1.1,true]]
			_camera(1.0,Vector3(0,.15,0))
			for index in range(settings.size()):
				var rig := HeroRig.new()
				rig.position = Vector3((index-2)*.5,0,0)
				root_node.add_child(rig)
				rig.setup(["torso","sleeve_near","glove_near"],settings[index][0],settings[index][1])
				rig.set_pose(HeroPrototypePoses.DEEP_ELBOW)
				_label("смешивание %.2f%s" % [settings[index][0]," + полукость" if settings[index][1] else ""],Vector2(index*300,560),300)
		"body":
			_camera(2.0,Vector3(0,0,0))
			var names := ["Нынешний","Стоит","Шаг","Висит","Бросок","Приземление"]
			var poses := [null,HeroPrototypePoses.STAND,HeroPrototypePoses.walk_pose(.2),HeroPrototypePoses.HANG,HeroPrototypePoses.RELEASE,HeroPrototypePoses.LAND]
			for index in range(names.size()):
				var x := (index-2.5)*1.0
				if index==0:
					current = ExplorerSprite.new()
					current.position = Vector3(x,0,0)
					root_node.add_child(current)
					current.setup()
					current.animate(RopeSim.new(),Vector2(2,3),false,0)
				else:
					var rig := HeroRig.new()
					rig.position = Vector3(x,0,0)
					root_node.add_child(rig)
					rig.setup(HeroRig.FULL)
					rig.set_pose(poses[index])
					if index!=3: rig.plant_feet()
				_label(names[index],Vector2(index*300,540),300)
		"walk":
			_camera(2.0,Vector3(0,0,0))
			current = ExplorerSprite.new()
			current.position = Vector3(-1.5,0,0)
			root_node.add_child(current)
			current.setup()
			for index in range(2):
				var rig := HeroRig.new()
				rig.position = Vector3(index*1.3-.1,0,0)
				root_node.add_child(rig)
				rig.setup(HeroRig.FULL)
				rigs.append(rig)
			_label("Нынешний",Vector2(0,540),600)
			_label("Шаг",Vector2(600,540),600)
			_label("Бросок",Vector2(1200,540),600)
		"throw":
			_camera(2.0,Vector3(0,0,0))
			current = ExplorerSprite.new()
			current.position = Vector3(-1.2,0,0)
			root_node.add_child(current)
			current.setup()
			var rig := HeroRig.new()
			rig.position = Vector3(.9,0,0)
			root_node.add_child(rig)
			rig.setup()
			rigs.append(rig)
			_label("Нынешний",Vector2(150,540),600)
			_label("Срез на костях: бросок",Vector2(1050,540),600)
	process_frame.connect(update)

func update() -> void:
	if mode=="throw":
		var time := frame/30.0
		var rig: HeroRig = rigs[0]
		rig.set_pose(HeroPrototypePoses.throw_pose(time))
		rig.reset_layers()
		if HeroPrototypePoses.arm_behind_head(time): rig.arm_behind_head()
		var sim := RopeSim.new()
		current.animate(sim,Vector2(2,4),fmod(time,HeroPrototypePoses.THROW_TIME)>.3,time)
	if mode=="walk":
		var time := frame/30.0
		rigs[0].set_pose(HeroPrototypePoses.walk_pose(time))
		rigs[0].plant_feet()
		var pose := HeroPrototypePoses.STAND.duplicate()
		pose.merge(HeroPrototypePoses.throw_pose(time),true)
		rigs[1].set_pose(pose)
		rigs[1].reset_layers()
		if HeroPrototypePoses.arm_behind_head(time): rigs[1].arm_behind_head()
		var sim := RopeSim.new()
		current.animate(sim,Vector2(2,4),false,time)
	process_frame.disconnect(update)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if mode=="throw" or mode=="walk":
		image.save_png(out.path_join("%04d.png" % frame))
		frame += 1
		if frame>=54:
			quit()
			return
		process_frame.connect(update)
		return
	image.save_png(out.path_join("prototype-%s.png" % mode))
	quit()
