extends SceneTree

# One scripted climb with the real rope physics (RopeSim), the 3D hero
# (HeroModel) animated the way ExplorerView drives him, filmed side-on:
# a step left, aim up-right, throw, the hook flies, catch, reel in, pump the
# swing, let go at the top of a swing, fly, land, stand. Numbered PNGs at 30
# frames per second, for reviewing the hero's motion (before/after strips).
#   Godot --path game --script res://tools/hero_motion_strip.gd -- --out=<folder>
# Needs a window.

const DT := 1.0/60
const ANCHOR := Vector2(3.4,4.6)
const HOOK_SPEED := 18.0

var out := ""
var root_node: Node3D
var hero: HeroModel
var camera: Camera3D
var rope_mesh: MeshInstance3D
var sim := RopeSim.new()
var clock := 0.0
var frame := 0
var phase := "stand"
var phase_time := 0.0
var shot := 0
var aim := Vector2(.55,.83).normalized()
var bolt := Vector2.ZERO
var bolt_velocity := Vector2.ZERO
var landed_for := 0.0
var log_lines: PackedStringArray = [] # frame, phase, hero state, reel speed, velocity

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(900,900)
	root.content_scale_size = root.size
	root_node = Node3D.new()
	root.add_child(root_node)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("223142")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.6,.62,.66)
	environment.ambient_light_energy = .5
	var world := WorldEnvironment.new()
	world.environment = environment
	root_node.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = .5
	root_node.add_child(sun)
	sun.global_transform = Transform3D(Basis.looking_at(Vector3(.3,-.5,-.8),Vector3.UP),Vector3.ZERO)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40,.4,2)
	ground.mesh = box
	ground.position = Vector3(0,-.2,0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("5d6b4a")
	ground.material_override = ground_material
	root_node.add_child(ground)
	var pin := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .12
	sphere.height = .24
	pin.mesh = sphere
	pin.position = Vector3(ANCHOR.x,ANCHOR.y,0)
	root_node.add_child(pin)
	rope_mesh = MeshInstance3D.new()
	var rope_material := StandardMaterial3D.new()
	rope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_material.albedo_color = Color("c9a46a")
	rope_mesh.material_override = rope_material
	root_node.add_child(rope_mesh)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(1.5,2.2,10)
	root_node.add_child(camera)
	camera.current = true
	hero = HeroModel.new()
	root_node.add_child(hero)
	hero.setup()
	sim.pos = Vector2(0,.48)
	sim.grounded = true
	process_frame.connect(_step)

func _flight() -> Dictionary:
	return {"aiming":phase=="aim","aim":aim,"shot":shot,"velocity":bolt_velocity if phase=="hook" else Vector2.ZERO,"returning":false}

# One physics step of the scripted climb.
func _tick() -> void:
	clock += DT
	phase_time += DT
	match phase:
		"stand":
			sim.vel = Vector2(-1.4,0) if phase_time>.15 and phase_time<.55 else Vector2.ZERO
			sim.pos += sim.vel*DT
			if phase_time>.9: _go("aim")
		"aim":
			if phase_time>.5:
				shot += 1
				bolt = sim.pos+Vector2(0,.3)
				bolt_velocity = (ANCHOR-bolt).normalized()*HOOK_SPEED
				_go("hook")
		"hook":
			bolt += bolt_velocity*DT
			if bolt.distance_to(ANCHOR)<.3:
				sim.attach(ANCHOR,5.5)
				_go("reel")
		"reel":
			sim.tick(DT,0.0,1.0 if phase_time<.5 else 0.0)
			if phase_time>.6: _go("pump")
		"pump":
			var pump := signf(sim.vel.x) if absf(sim.vel.x)>.1 else 1.0
			sim.tick(DT,pump,0.0)
			if phase_time>2.4 and sim.vel.x>1.5 and sim.vel.y>.5:
				sim.release(1.0)
				_go("fly")
		"fly":
			sim.tick(DT,0.0,0.0)
			if sim.pos.y<=.48 and sim.vel.y<0:
				sim.land(0.0)
				_go("land")
		"land":
			sim.vel = Vector2.ZERO
			landed_for += DT

func _go(next: String) -> void:
	phase = next
	phase_time = 0.0

func _step() -> void:
	for i in range(2): _tick()
	hero.flight_info = _flight()
	var tether := phase in ["hook","reel","pump"]
	var target: Vector2 = sim.effective_anchor() if sim.attached else (sim.pos+aim*3 if phase=="aim" else bolt)
	hero.position = Vector3(sim.pos.x,sim.pos.y,0)
	hero.animate(sim,target,tether or phase=="aim",clock)
	_draw_rope(tether)
	# Centred on the hero: every frame shows his pose at the same size.
	camera.position.x = sim.pos.x
	camera.position.y = sim.pos.y+.1
	process_frame.disconnect(_step)
	for i in range(2): await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%04d.png" % frame))
	log_lines.append("%d %s %s %.2f %.2f %.2f" % [frame,phase,hero.state,hero.hero.reel_speed,sim.vel.x,sim.vel.y])
	frame += 1
	if landed_for>1.2 or frame>600:
		print("HERO_MOTION_STRIP frames=%d" % frame)
		var file := FileAccess.open(out.path_join("states.txt"),FileAccess.WRITE)
		file.store_string("
".join(log_lines))
		quit()
		return
	process_frame.connect(_step)

func _draw_rope(tether: bool) -> void:
	var mesh := ImmediateMesh.new()
	if tether:
		var from := hero.grip_position()
		var to := Vector3(ANCHOR.x,ANCHOR.y,0) if sim.attached else Vector3(bolt.x,bolt.y,0)
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for offset in [Vector3.ZERO,Vector3(.01,0,0),Vector3(0,.01,0)]:
			mesh.surface_add_vertex(from+offset)
			mesh.surface_add_vertex(to+offset)
		mesh.surface_end()
	rope_mesh.mesh = mesh
