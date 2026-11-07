extends SceneTree

# The 3D hero (HeroModel, docs/CHARACTER_3D_PLAN.md) in the game's light, for review.
#
#   --mode=compare   current hero next to the 3D hero, side and three-quarter (one PNG).
#   --mode=states    the 3D hero in several HeroState states (one PNG).
#   --mode=clips     the same states animated (numbered PNGs, 30 per second).
# Pass --out=<folder>. Needs a window (no --headless): it renders.
#
# Level light and environment copy main.gd, so the frame shows how the hero
# reads in a level; the hero's own shading comes from HeroModel.

const SUN_DIRECTION := Vector3(.30,-.50,-.81)
const SUN_ENERGY := .46
const FRAMES := 60

# State, label, motion of a stand-in RopeSim over time.
const STATES := [
	["idle","Стоит"],["walk","Идёт"],["aim","Целится"],["throw","Бросок"],
	["swing","Раскачка"],["fall","Падение"],["land","Приземление"],
]

var out := ""
var mode := "compare"
var root_node: Node3D
var heroes: Array = []
var current: ExplorerSprite
var frame := 0

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1800,700) if mode=="compare" else Vector2i(2100,640)
	root.content_scale_size = root.size
	root_node = Node3D.new()
	root.add_child(root_node)
	_game_light()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2 if mode=="compare" else 1.95
	camera.position = Vector3(0,.12,10)
	root_node.add_child(camera)
	camera.current = true
	if mode=="compare":
		current = ExplorerSprite.new()
		current.position = Vector3(-1.2,0,0)
		root_node.add_child(current)
		current.setup()
		current.animate(RopeSim.new(),Vector2(2,3),false,0)
		heroes = [_hero(Vector3(.3,0,0),"idle"),_hero(Vector3(1.6,0,0),"idle")]
		_label("Нынешний",Vector2(150,640),600)
		_label("3D: сбоку",Vector2(750,640),400)
		_label("3D: в три четверти",Vector2(1250,640),500)
	else:
		var spacing := 2.1*float(root.size.x)/root.size.y/STATES.size()*1.0
		for index in range(STATES.size()):
			var x := (index-(STATES.size()-1)/2.0)*spacing*.92
			heroes.append(_hero(Vector3(x,0,0),STATES[index][0]))
			_label(STATES[index][1],Vector2(index*root.size.x/STATES.size(),600),root.size.x/STATES.size())
	process_frame.connect(_step)

func _hero(at: Vector3, state: String) -> HeroModel:
	var hero := HeroModel.new()
	hero.position = at
	root_node.add_child(hero)
	hero.setup()
	hero.forced_state = state
	return hero

# A stand-in for the rope simulation: just enough motion for each state.
func _sim(state: String, time: float) -> Array:
	var sim := RopeSim.new()
	var target := Vector2(2,3)
	sim.grounded = state in ["idle","walk","aim","throw","land"]
	match state:
		"walk": sim.vel = Vector2(2.6,0)
		"swing":
			sim.attached = true
			var phase := sin(time*TAU/1.6)
			sim.vel = Vector2(4.5*cos(time*TAU/1.6),0)
			target = sim.pos+Vector2(-phase*1.2,3)
		"fall": sim.vel = Vector2(1,-6)
		"aim": target = sim.pos+Vector2(2,2.5)
	return [sim,target,state in ["aim","throw","swing"]]

func _step() -> void:
	var time := frame/30.0
	for index in range(heroes.size()):
		var hero: HeroModel = heroes[index]
		var state := hero.forced_state
		var motion := _sim(state,time)
		# One-shot clips loop in the preview so every frame shows motion.
		if mode!="compare" and state in ["throw","land"] and hero.state_time>(.6 if state=="throw" else .8):
			hero.state = ""
		hero.animate(motion[0],motion[1],motion[2],time)
	if mode=="compare":
		for hero in heroes: hero.animate(RopeSim.new(),Vector2(2,3),false,time)
		heroes[1].rotation.y = -.6
	process_frame.disconnect(_step)
	for i in range(2): await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if mode=="clips":
		image.save_png(out.path_join("%04d.png" % frame))
		frame += 1
		if frame>=FRAMES:
			quit()
			return
		process_frame.connect(_step)
		return
	if mode=="states" and frame<12:
		# Let the poses settle into their clips before the still.
		frame += 1
		process_frame.connect(_step)
		return
	image.save_png(out.path_join("hero-model-%s.png" % mode))
	quit()

func _game_light() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("223142")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c7d6")
	environment.ambient_light_energy = .62
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	root_node.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(SUN_DIRECTION,Vector3.UP)
	sun.light_color = Color("fff0d2")
	sun.light_energy = SUN_ENERGY
	sun.light_specular = .35
	root_node.add_child(sun)

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
