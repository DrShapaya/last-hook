extends SceneTree

# Frames of a real attempt for reviewing the hero in the game: the movement bot
# from tests/test_hero_state.gd throws the hook and climbs grips while the game
# renders. The 3D hero (HeroModel) is the default; pass --hero2d for the painted
# one. --out=<folder> for the numbered PNGs, --frames=<n> (default 240, 30 per
# second). Needs a window.
# LASTHOOK_SAVE_DIR must point to a throwaway save folder.

var out := ""
var frames := 240
var game
var captured := 0
var step := 0
var route_index := 1
var target_id := -1
var target := Vector2.ZERO
var fired := false
var mid_turn := 0 # Frames that catch the hero turning around (body edge-on).

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument.begins_with("--frames="): frames = int(argument.trim_prefix("--frames="))
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(720,1280)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	var initial: Vector2 = game.world.anchors[0]["pos"]
	game.sim.pos = initial+Vector2(0,-2.8)
	game.sim.vel = Vector2.ZERO
	game.sim.attach(initial,5.5)
	game.anchor_id = 0
	game.anchor_contact = initial
	_next_target()
	process_frame.connect(_frame)

func _next_target() -> void:
	target_id = game.world.main_route[route_index]
	target = game.world.anchor_by_id(target_id)["pos"]
	fired = false
	step = 0

func _frame() -> void:
	process_frame.disconnect(_frame)
	for i in range(4): _bot_step()
	game._process(1.0/30)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join("%04d.png" % captured))
	# A close-up around the hero, to judge the hero itself at game scale.
	var camera := root.get_camera_3d()
	if camera and is_instance_valid(game.explorer) and is_instance_valid(game.explorer.body):
		# unproject_position works in the viewport's base resolution; the saved
		# frame is the window's size (content scaling), so scale the point.
		var at := camera.unproject_position(game.explorer.body.global_position)*Vector2(image.get_size())/root.get_visible_rect().size
		var half := 150
		var region := Rect2i(Vector2i(at)-Vector2i(half,half),Vector2i(half*2,half*2)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		if region.size.x>10 and region.size.y>10:
			image.get_region(region).save_png(out.path_join("hero-%04d.png" % captured))
	if is_instance_valid(game.explorer) and "turn" in game.explorer.body:
		if absf(sin(float(game.explorer.body.get("turn"))))>.3: mid_turn += 1
	captured += 1
	if captured>=frames or game.state!="play":
		print("HERO_RUN frames=%d mid_turn=%d" % [captured,mid_turn])
		game.queue_free()
		quit()
		return
	process_frame.connect(_frame)

# One physics step of the climbing bot (same gestures as the integration bot).
func _bot_step() -> void:
	step += 1
	if game.sim.attached:
		game.reel = 1.0 if step<240 else 0.0
		if step>=240: game.sim.request_length(3.3 if step%360<180 else 2.0)
		if absf(game.sim.vel.x)>.1: game.pump = signf(game.sim.vel.x)
		elif absf(game.pump)<.1: game.pump = signf(target.x-game.sim.anchor.x)
		var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
		var ignored: int = game.anchor_id if not current.get("permanent",true) else -1
		var sight: Dictionary = game.world.cast_hook(game.sim.pos,target,game.model.hook_radius(),ignored)
		var goal := target
		var clear := false
		if not sight.is_empty() and not sight.get("blocked",false):
			var hit: Dictionary = sight["object"]
			clear = int(hit["id"])==target_id
			if not clear and int(hit["id"])!=game.anchor_id and hit["pos"].distance_to(target)<game.sim.anchor.distance_to(target)-.3:
				goal = hit["pos"]
				clear = true
		if clear and game.sim.pos.distance_to(goal)<5.2 and game.sim.vel.dot((goal-game.sim.pos).normalized())>.5:
			_touch_throw(goal)
			fired = true
	game._physics_process(1.0/120)
	if game.anchor_id==target_id and game.sim.attached and route_index<game.world.main_route.size()-1:
		route_index += 1
		_next_target()
	elif fired and not game.bolt_active and not game.sim.attached:
		_touch_throw(target)

func _touch_throw(goal: Vector2) -> void:
	var origin := Vector2(150,400)
	if game.sim.attached:
		game.pointer_down(origin,true)
		game.pointer_up(origin)
	var direction: Vector2 = game.direction_to_target(goal)
	var end: Vector2 = origin+Vector2(direction.x,-direction.y)*82*game._gesture_scale()
	game.pointer_down(origin,true)
	game.pointer_move(end)
	game.pointer_up(end)
