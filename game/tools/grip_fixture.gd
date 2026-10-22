extends SceneTree

# Acceptance fixture for grip blocks (chat 2.1): the five types on one flat
# host rock surface, at one scale and light, without HUD, seen front,
# three-quarter and from the side, plus a front view with the paint hidden.
# One contact sheet per profile (forest, snow, desert): rows are types.
#   Godot --path game --script res://tools/grip_fixture.gd -- --out=DIR

const MainScript := preload("res://scripts/main.gd")
const CELL := Vector2i(400,300)
const BIOMES := [["forest",10.0],["snow",70.0],["desert",90.0]]
const VIEWS := ["front","three_quarter","side","bare"]
var out_dir := ""
var world: MountainWorld
var camera: Camera3D

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = CELL
	var stage := Node3D.new()
	root.add_child(stage)
	_light(stage)
	camera = Camera3D.new()
	camera.fov = 30
	camera.near = .05
	camera.far = 60
	stage.add_child(camera)
	camera.current = true
	world = MountainWorld.new()
	world.visuals_enabled = false
	stage.add_child(world)
	world.setup(58273,0)
	world.generate_to(40,true,120)
	world.visuals_enabled = true
	for biome in BIOMES: await _sheet(stage,biome[0],float(biome[1]))
	quit()

func _light(stage: Node3D) -> void:
	var node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("88bfd9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c7d6")
	environment.ambient_light_energy = .62
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	node.environment = environment
	stage.add_child(node)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(MainScript.SUN_DIRECTION,Vector3.UP)
	sun.light_color = Color("fff0d2")
	sun.light_specular = .35
	sun.light_energy = MainScript.SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_bias = .03
	stage.add_child(sun)

# A faceted wall of the profile's rock behind the grips, flat on average.
func _host(stage: Node3D, profile: GripBiomeProfile, y: float) -> Node3D:
	var host := Node3D.new()
	stage.add_child(host)
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var base := world.visuals.zone_color(y)
	var grid := {}
	for gx in range(-4,40):
		for gy in range(-4,5):
			grid[Vector2i(gx,gy)] = Vector3(gx*.9+random.randf_range(-.3,.3),y+gy*.9+random.randf_range(-.3,.3),random.randf_range(-.08,.08))
	for gx in range(-4,39):
		for gy in range(-4,4):
			var a: Vector3 = grid[Vector2i(gx,gy)]
			var b: Vector3 = grid[Vector2i(gx+1,gy)]
			var c: Vector3 = grid[Vector2i(gx+1,gy+1)]
			var d: Vector3 = grid[Vector2i(gx,gy+1)]
			points.append_array(PackedVector3Array([a,b,c,a,c,d]))
			colors.append(base.lightened(random.randf_range(-.04,.05)))
			colors.append(base.darkened(random.randf_range(0,.06)))
	world.visuals._flat_surface(host,"Порода",points,colors,world.visuals.stone_material,true)
	return host

func _grip(stage: Node3D, kind: int, x: float, y: float, profile: GripBiomeProfile) -> Dictionary:
	var dimensions := Vector2(1.6,.65)
	var object := {"id":900+kind,"pos":Vector2(x,y),"kind":kind,"dimensions":dimensions,"polygon":MountainLayout.grip_polygon(dimensions),"permanent":false,"broken":false,
		"exit_dir":Vector2(.45,1).normalized(),"slide_dir":GripSpec.lateral_slide(1)}
	if kind==GripSpec.CRYSTAL:
		# Two exits for the fork: up-left and up-right.
		var exits: Array = []
		for side in [-1,1]:
			world.layout.anchors.append({"id":world.layout.anchors.size(),"pos":Vector2(x+side*3.2,y+2.6),"kind":0})
			exits.append(world.layout.anchors.size()-1)
		object["choice_exits"] = exits
	var mount := SurfaceMount.new()
	mount.layout_point = object["pos"]
	mount.position = Vector3(x,y,0)
	mount.normal = Vector3.BACK
	mount.socket_normal = Vector3.BACK
	mount.host_mass = 0
	mount.standoff = MountainVisuals.GRIP_STANDOFF
	mount.profile = profile
	world.visuals.build_grip(object,stage,mount)
	if GripSpec.timed(object): world._add_timer_dial(object)
	return object

func _sheet(stage: Node3D, biome: String, y: float) -> void:
	var profile := GripBiomeProfile.named(biome)
	var host := _host(stage,profile,y)
	var grips: Array = []
	for kind in range(5): grips.append(_grip(stage,kind,kind*6.0,y,profile))
	var sheet := Image.create(CELL.x*VIEWS.size(),CELL.y*5,false,Image.FORMAT_RGBA8)
	for kind in range(5):
		var at: Vector2 = grips[kind]["pos"]
		var target := Vector3(at.x,at.y,.25)
		for view_index in range(VIEWS.size()):
			var view: String = VIEWS[view_index]
			var direction: Vector3 = {"front":Vector3(0,.08,1),"bare":Vector3(0,.08,1),"three_quarter":Vector3(.62,.42,.66),"side":Vector3(.97,.12,.2)}[view]
			camera.position = target+direction.normalized()*5.2
			camera.look_at(target,Vector3.UP)
			var band: Node3D = (grips[kind]["visual"] as Node3D).find_child("Полоса состояния",true,false)
			if band!=null: band.visible = view!="bare"
			for wait in range(3): await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image,Rect2i(Vector2i.ZERO,CELL),Vector2i(view_index*CELL.x,kind*CELL.y))
	var path := out_dir.path_join("grip_sheet_%s.png" % biome)
	sheet.save_png(path)
	print("GRIP_FIXTURE ",path)
	for grip in grips: (grip["visual"] as Node3D).queue_free()
	host.queue_free()
	await process_frame
