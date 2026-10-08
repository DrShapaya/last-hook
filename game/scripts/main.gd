extends Node3D

const START_Y := .63
var model: GameModel
var sim := RopeSim.new()
var world: MountainWorld
var explorer: ExplorerView
var camera: Camera3D
var scene_environment: Environment
var hud: GameHud
var state := "menu"
var run_mode := "summit"
var selected_location := 0
var lobby_location := 0
var lobby_endless := false
var run_id := ""
var run_seed := 0
var summit_height := 120.0
var anchor_id := -1
var anchor_time := 0.0
var anchor_contact := Vector2.ZERO
var safe_contact := Vector2.ZERO
var safe_anchor_id := -1
var safe_position := Vector2(0,START_Y)
var revive_used := false
var bolt_active := false
var bolt_pos := Vector2.ZERO
var bolt_origin := Vector2.ZERO
var bolt_direction := Vector2.UP
var bolt_travel := 0.0
var pressed := false
var press_start := Vector2.ZERO
var pointer := Vector2.ZERO
var dragging := false
var primary_touch := -1
var rope_touch := -1
var rope_pointer := Vector2.ZERO
var rope_press_start := Vector2.ZERO
var rope_press_msec := 0
var rope_dragging := false
var used_second_finger := false
var pump := 0.0
var reel := 0.0
var focus_remaining := .7
var aim_direction := Vector2.UP
var elapsed := 0.0
var camera_y := 7.0
var camera_x := 0.0
var snapshot_timer := 0.0
var hint_timer := 0.0
var hint := ""
var settlement: Dictionary = {}
var capture_path := ""
var capture_screen := "play"
var capture_queued := false
var capture_overview := false
var capture_location := 0
var capture_tips := 1
var capture_left := false
var audio: AudioStreamPlayer
var preview := false
var run_seconds := 0.0
var shots := 0
var catches := 0
var failure_reason := ""
var zone_gold := 0

func _ready() -> void:
	Engine.max_fps = 60
	get_tree().auto_accept_quit = false
	model = GameModel.new()
	selected_location = int(model.profile.get("selected_location",0))
	if not model.profile["active"].is_empty():
		selected_location = int(model.profile["active"].get("location",0))
	lobby_location = selected_location
	_setup_lighting()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	camera.near = .1
	camera.far = 120
	add_child(camera)
	camera.current = true
	audio = AudioStreamPlayer.new()
	audio.volume_db = -18
	add_child(audio)
	hud = GameHud.new()
	add_child(hud)
	hud.setup(self)
	_create_world(58273,0,36)
	sim.pos = Vector2(-.7,8.9)
	sim.anchor = world.anchor_by_id(world.main_route[2])["pos"]
	sim.attached = true
	sim.length = sim.pos.distance_to(sim.anchor)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--screen="):
			capture_screen = argument.trim_prefix("--screen=")
		if argument.begins_with("--location="):
			capture_location = clampi(int(argument.trim_prefix("--location=")),0,model.balance["locations"].size()-1)
		if argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size()==2:
				get_window().size = Vector2i(maxi(320,int(dimensions[0])),maxi(320,int(dimensions[1])))
		if argument.begins_with("--tips="):
			capture_tips = clampi(int(argument.trim_prefix("--tips=")),1,3)
		if argument=="--overview": capture_overview = true
		if argument=="--left": capture_left = true
	if not capture_path.is_empty():
		preview = true
		model.profile = GameModel.fresh_profile()
		model.profile["levels"][2] = capture_tips
		selected_location = capture_location
		lobby_location = capture_location
		if capture_screen in ["play","rope","inventory","equipment","flight"]:
			start_run(false)
			run_seed = 58273
			_create_world(run_seed,selected_location,summit_height+6)
			var point: Dictionary = world.anchor_by_id(world.main_route[12])
			anchor_id = point["id"]
			sim.pos = point["pos"]+Vector2(2.5 if capture_left else -2.5,-3.5)
			var contact_fraction := world.hit_object(sim.pos,point["pos"],point,.32)
			sim.anchor = sim.pos.lerp(point["pos"],maxf(0,contact_fraction))
			anchor_contact = sim.anchor
			sim.length = sim.pos.distance_to(sim.anchor)
			sim.target_length = sim.length
			sim.attached = true
			sim.launched = true
			sim.highest = sim.pos.y
			model.reach(maxf(0,sim.highest-START_Y))
			catches = 12
			shots = 15
			for route_index in range(12):
				var previous_grip := world.anchor_by_id(world.main_route[route_index])
				if not previous_grip.get("permanent",true): previous_grip["broken"] = true
			model.profile["learned_controls"] = ["aim","swing","rope","release"]
			model.bag = [{"id":-10,"tier":0,"value":40}]
			if capture_screen=="rope":
				sim.length = model.value("rope_lengths",0)
				sim.target_length = sim.length
			elif capture_screen=="inventory":
				model.profile["levels"][3] = 6
				model.bag.append_array([{"id":-11,"tier":1,"value":75},{"id":-12,"tier":3,"value":220}])
			hud.refresh_bag()
			camera_y = sim.pos.y+2.5
			camera_x = sim.pos.x
			hint_timer = 0
			if capture_screen=="equipment":
				camera.size = 9
				hud.hide()
			if capture_screen=="flight":
				bolt_active = true
				bolt_pos = sim.anchor
				sim.attached = false
		elif capture_screen == "result":
			state = "result"
			model.profile["gold"] = 4540
			model.profile["reached_zones"] = 6
			model.profile["levels"] = [3,2,2,3,2,2,3]
			hud.show_result({"success":true,"highest":1200,"height":540,"loot":900,"carried":900,"finish":1300,"total":2740,"zone_bonus":1800,"first":true,"seconds":214,"shots":51,"catches":43})
		elif capture_screen == "workshop":
			model.profile["gold"] = 640
			model.profile["reached_zones"] = 4
			model.profile["levels"] = [3,2,2,3,2,2,3]
			show_workshop()
		else:
			_create_world(58273,selected_location,36)
			hud.show_menu()
		if capture_overview:
			get_window().content_scale_size = Vector2i(1280,800)
			get_window().size = Vector2i(1280,800)
			hud.hide()
			camera_x = 0
	else:
		hud.show_menu()

func _setup_lighting() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	scene_environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("88bfd9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b7d1df")
	environment.ambient_light_energy = .65
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = false
	environment.fog_light_color = Color("b8d1df")
	environment.fog_density = .0025
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28,-20,0)
	sun.light_color = Color("ffe8b7")
	sun.light_energy = .85
	sun.shadow_enabled = true
	sun.shadow_opacity = .55
	sun.directional_shadow_max_distance = 45
	add_child(sun)

func _create_world(seed_number: int, location_number: int, height: float, saved_version: int = 0) -> void:
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(explorer):
		explorer.queue_free()
	world = MountainWorld.new()
	add_child(world)
	world.setup(seed_number,location_number,saved_version)
	scene_environment.background_color = Color("88bfd9") if location_number==0 else Color("142438")
	world.generate_to(height,run_mode=="summit",summit_height)
	explorer = ExplorerView.new()
	add_child(explorer)
	explorer.setup(world)

func start_run(endless: bool) -> void:
	if endless and not model.profile["summit_cleared"]:
		toast("Бесконечный режим откроется после первой вершины")
		return
	run_mode = "endless" if endless else "summit"
	run_seed = randi_range(1000,999999)
	run_id = "%d-%d" % [Time.get_unix_time_from_system(),randi()]
	summit_height = float(model.balance["locations"][selected_location]["height_units"])
	_create_world(run_seed,selected_location,summit_height+6 if not endless else 65)
	sim = RopeSim.new()
	sim.pos = Vector2(0,START_Y)
	sim.highest = START_Y
	sim.flight_peak = START_Y
	_configure_rope()
	model.bag = []
	model.picked = []
	anchor_id = -1
	safe_anchor_id = -1
	anchor_time = 0
	safe_position = sim.pos
	revive_used = false
	bolt_active = false
	focus_remaining = .7
	camera_y = 4.8
	camera_x = 0
	_position_camera()
	state = "play"
	lobby_location = selected_location
	run_seconds = 0
	shots = 0
	catches = 0
	failure_reason = ""
	zone_gold = 0
	_reset_input()
	hud.show_play()
	if "aim" not in model.profile["learned_controls"]:
		toast("Прицелься в выступ и отпусти первый палец" if OS.has_feature("mobile") else "Прицелься мышью и отпусти ЛКМ",4)
	save_snapshot()

func resume_run() -> void:
	var snapshot: Dictionary = model.profile["active"]
	if snapshot.is_empty():
		return
	var saved_version := int(snapshot.get("generation_version",0))
	var compatible_old := saved_version in [6,7] and int(snapshot.get("location",0))==0
	if not compatible_old and saved_version!=MountainWorld.generation_version_for(int(snapshot.get("location",0))):
		# Old contact IDs describe another route: settle its earned rewards once.
		model.bag = snapshot.get("bag",[]).duplicate(true)
		settlement = model.settle(snapshot["id"],snapshot.get("mode","summit"),maxf(0,float(snapshot["highest"])-START_Y),false,int(snapshot.get("location",0)))
		state = "result"
		hud.show_result(settlement)
		toast("Генератор обновлён. Награда старой попытки начислена.",6)
		return
	run_mode = snapshot.get("mode","summit")
	selected_location = int(snapshot.get("location",0))
	run_seed = int(snapshot["seed"])
	run_id = snapshot["id"]
	summit_height = float(model.balance["locations"][selected_location]["height_units"])
	_create_world(run_seed,selected_location,maxf(float(snapshot["highest"])+40,65) if run_mode=="endless" else summit_height+6,saved_version)
	sim = RopeSim.new()
	sim.pos = Vector2(snapshot["x"],snapshot["y"])
	sim.vel = Vector2(snapshot["vx"],snapshot["vy"])
	sim.length = float(snapshot["length"])
	_configure_rope()
	sim.target_length = clampf(float(snapshot.get("target_length",sim.length)),RopeSim.MIN_LENGTH,sim.maximum_length)
	sim.highest = float(snapshot["highest"])
	sim.flight_peak = float(snapshot["flight_peak"])
	run_seconds = float(snapshot.get("run_seconds",0))
	shots = int(snapshot.get("shots",0))
	catches = int(snapshot.get("catches",0))
	failure_reason = snapshot.get("failure_reason","")
	zone_gold = int(snapshot.get("zone_gold",0))
	sim.launched = bool(snapshot["launched"])
	sim.grounded = bool(snapshot.get("grounded",false))
	anchor_id = int(snapshot["anchor_id"])
	anchor_time = float(snapshot["anchor_time"])
	focus_remaining = float(snapshot.get("focus_remaining",.7))
	safe_anchor_id = int(snapshot["safe_anchor_id"])
	safe_position = Vector2(snapshot["safe_x"],snapshot["safe_y"])
	revive_used = bool(snapshot["revive_used"])
	model.bag = snapshot["bag"].duplicate(true)
	model.picked = snapshot["picked"].duplicate()
	for point in world.anchors:
		point["broken"] = snapshot["broken"].has(point["id"])
	for find in world.finds:
		find["picked"] = model.picked.has(find["item"]["id"])
	if anchor_id>=0:
		var point := world.anchor_by_id(anchor_id)
		if not point.is_empty() and not point["broken"]:
			sim.attached = true
			anchor_contact = Vector2(snapshot.get("contact_x",point["pos"].x),snapshot.get("contact_y",point["pos"].y))
			sim.anchor = anchor_contact
			if int(point["kind"])==3:
				sim.anchor.y -= minf(1.2,anchor_time*.18)
	var safe_object := world.anchor_by_id(safe_anchor_id)
	var safe_default: Vector2 = safe_object.get("pos",safe_position+Vector2(0,2.8))
	safe_contact = Vector2(snapshot.get("safe_contact_x",safe_default.x),snapshot.get("safe_contact_y",safe_default.y))
	if safe_anchor_id>=0 and (safe_object.is_empty() or safe_object.get("broken",false) or not safe_object.get("permanent",true)):
		safe_anchor_id = -1
		safe_position = Vector2(0,START_Y)
		for id in world.main_route:
			var candidate := world.anchor_by_id(id)
			if candidate.get("permanent",true) and not candidate["broken"] and candidate["pos"].y<sim.highest:
				safe_anchor_id = id
				safe_contact = candidate["pos"]
				safe_position = safe_contact+Vector2(0,-2.8)
	bolt_active = bool(snapshot.get("bolt_active",false))
	bolt_pos = Vector2(snapshot.get("bolt_x",0),snapshot.get("bolt_y",0))
	bolt_origin = Vector2(snapshot.get("bolt_ox",0),snapshot.get("bolt_oy",0))
	bolt_direction = Vector2(snapshot.get("bolt_dx",0),snapshot.get("bolt_dy",1))
	bolt_travel = float(snapshot.get("bolt_travel",0))
	camera_y = float(snapshot.get("camera_y",maxf(4.8,sim.pos.y+2.5)))
	camera_x = sim.pos.x
	_position_camera()
	state = "revive" if bool(snapshot.get("awaiting_revive",false)) else "play"
	_reset_input()
	if state=="revive":
		hud.show_revive()
	else:
		hud.show_play()

func _input(event: InputEvent) -> void:
	# Owned touches finish here even if they cross GUI controls. Their identity
	# is stable: lifting the first finger never promotes the rope finger.
	if state!="play" or preview:
		return
	if event is InputEventScreenTouch and not event.pressed:
		if event.index==primary_touch:
			pointer_up(event.position)
			primary_touch = -1
			get_viewport().set_input_as_handled()
		elif event.index==rope_touch:
			rope_pointer_up(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index==primary_touch:
			pointer_move(event.position)
			get_viewport().set_input_as_handled()
		elif event.index==rope_touch:
			rope_pointer_move(event.position)
			get_viewport().set_input_as_handled()
	elif not OS.has_feature("mobile") and pressed:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			pointer_up(event.position)
		elif event is InputEventMouseMotion:
			pointer_move(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			pause_run() if state=="play" else unpause() if state=="pause" else show_menu()
		elif event.keycode==KEY_SPACE and state=="play":
			if sim.attached: model.learn_control("release")
			release_hook()
	if state != "play" or preview:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if primary_touch<0:
				pointer_down(event.position)
				if pressed:
					primary_touch = event.index
			elif rope_touch<0 and sim.attached and hud.world_input_allowed(event.position):
				rope_touch = event.index
				rope_pointer = event.position
				rope_press_start = event.position
				rope_press_msec = Time.get_ticks_msec()
				rope_dragging = false
				used_second_finger = true
	elif event is InputEventMouseButton and not OS.has_feature("mobile"):
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				pointer_down(event.position)
			else:
				pointer_up(event.position)
		elif event.pressed and sim.attached:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:
				sim.request_length(sim.target_length-.4)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
				sim.request_length(sim.target_length+.4)
	elif event is InputEventMouseMotion and not OS.has_feature("mobile"):
		pointer_move(event.position)

func pointer_down(point: Vector2) -> void:
	if not hud.world_input_allowed(point):
		return
	pressed = true
	press_start = point
	pointer = point
	dragging = false
	used_second_finger = false
	if not sim.attached:
		aim_direction = (_screen_world(point)-sim.pos).normalized()

func pointer_move(point: Vector2) -> void:
	pointer = point
	if not pressed:
		return
	var difference := point-press_start
	if difference.length()>15:
		dragging = true
	if sim.attached:
		pump = clampf(difference.x/75,-1,1)
	else:
		aim_direction = Vector2(difference.x,-difference.y).normalized() if dragging else (_screen_world(point)-sim.pos).normalized()

func pointer_up(point: Vector2) -> void:
	if not pressed:
		return
	pointer_move(point)
	if sim.attached:
		pass # Only the second finger releases; the first owns aim and pumping.
	else:
		fire_hook(aim_direction)
	pressed = false
	dragging = false
	pump = 0
	reel = 0
	used_second_finger = false

func rope_pointer_move(point: Vector2) -> void:
	if rope_touch<0 or not sim.attached:
		return
	if not rope_dragging:
		if point.distance_to(rope_press_start)<=15:
			return
		rope_dragging = true
	var delta := point.y-rope_pointer.y
	rope_pointer = point
	sim.request_length(sim.target_length+delta*float(model.balance["rope_drag_units_per_pixel"]))

func rope_pointer_up(point: Vector2) -> void:
	# A tap is decided on release so holding/dragging cannot drop the player.
	var tap := not rope_dragging and point.distance_to(rope_press_start)<=15 and Time.get_ticks_msec()-rope_press_msec<=300
	rope_touch = -1
	rope_dragging = false
	if tap and sim.attached:
		model.learn_control("release")
		release_hook(true)

func _configure_rope() -> void:
	sim.maximum_length = model.value("rope_lengths",0)
	sim.adjust_speed = float(model.balance["rope_adjust_speed_units"])
	sim.fall_speed_limit = float(model.balance["fall_speed_limit_units"])
	sim.gravity = float(model.balance["gravity"])

func _reset_input() -> void:
	pressed = false
	dragging = false
	pump = 0
	reel = 0
	primary_touch = -1
	rope_touch = -1
	rope_dragging = false
	used_second_finger = false

func _screen_world(point: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var distance := -origin.z/direction.z
	var result := origin+direction*distance
	return Vector2(result.x,result.y)

func fire_hook(direction: Vector2) -> void:
	if bolt_active or sim.attached or direction.length()<.01:
		return
	bolt_active = true
	shots += 1
	bolt_origin = sim.pos
	bolt_pos = sim.pos
	bolt_direction = direction.normalized()
	bolt_travel = 0
	_sound(440,.065)

func _position_camera() -> void:
	camera.position = Vector3(camera_x,camera_y,28)
	camera.look_at(Vector3(camera_x,camera_y,0))

func screen_bottom_y() -> float:
	var viewport := get_viewport().get_visible_rect().size
	return _screen_world(Vector2(viewport.x*.5,viewport.y)).y

func below_screen() -> bool:
	return sim.pos.y+float(model.balance["fall_screen_margin_units"])<screen_bottom_y()

func release_hook(keep_primary: bool = false) -> void:
	if not sim.attached:
		return
	var factor := model.value("impulse_factors",1)
	var point := world.anchor_by_id(anchor_id)
	if not point.is_empty() and int(point["kind"])==2:
		factor *= 1.13
	world.consume_anchor(anchor_id)
	if anchor_id==safe_anchor_id and not point.get("permanent",true):
		safe_anchor_id = -1
		safe_position = Vector2(0,START_Y)
	sim.release(factor)
	anchor_id = -1
	focus_remaining = .7
	_sound(310,.07)
	if keep_primary:
		pump = 0
		reel = 0
		press_start = pointer
		dragging = false
		aim_direction = (_screen_world(pointer)-sim.pos).normalized()
	else:
		_reset_input()

func _physics_process(delta: float) -> void:
	if state!="play" or preview:
		return
	run_seconds += delta
	var step := delta
	if pressed and not sim.attached and focus_remaining>0:
		focus_remaining = maxf(0,focus_remaining-delta)
		step *= .32
	var keyboard_pump := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var keyboard_reel := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	var previous := sim.pos
	var previous_length := sim.length
	if sim.attached:
		anchor_time += step
		var point := world.anchor_by_id(anchor_id)
		if not point.is_empty():
			if int(point["kind"])==1 and anchor_time>2.6:
				point["broken"] = true
				release_hook()
				toast("Корень сломался — успей зацепиться!")
			elif int(point["kind"])==3:
				sim.anchor = anchor_contact+Vector2(0,-minf(1.2,anchor_time*.18))
	sim.grounded = false
	sim.tick(step,clampf(pump+keyboard_pump,-1,1),clampf(reel+keyboard_reel,-1,1))
	if sim.attached:
		if absf(pump+keyboard_pump)>.15 and absf(sim.vel.x)>1.5:
			model.learn_control("swing")
		if absf(sim.length-previous_length)>.0001:
			model.learn_control("rope")
	var motion := world.move_player(previous,sim.pos,sim.vel)
	sim.pos = motion["position"]
	sim.vel = motion["velocity"]
	if world.location==0 and sim.attached and world.rope_blocked(sim.pos,sim.anchor):
		release_hook()
		toast("Канат упёрся в выступ")
	if below_screen():
		fail_run("Упал ниже экрана")
		return
	if bolt_active:
		_update_bolt(step)
	_land(previous)
	_collect_finds()
	if state!="play":
		return
	var bank_before := int(model.profile["gold"])
	var opened := model.reach(maxf(0,sim.highest-START_Y))
	zone_gold += int(model.profile["gold"])-bank_before
	if not opened.is_empty():
		var zone_reward := int(model.profile["gold"])-bank_before
		var unlock := "Ступень %d · +%d золота" % [opened[-1]+1,zone_reward] if opened[-1]>=2 else "+%d золота за новую зону" % zone_reward
		toast("%s · %s\n%s" % [GameModel.ZONE_NAMES[opened[-1]],GameModel.ZONE_HINTS[opened[-1]],unlock],3)
		save_snapshot()
	if run_mode=="summit" and sim.pos.y-START_Y>=summit_height-.02:
		finish_run(true)
	elif run_mode=="endless" and sim.pos.y+35>world.generated_height:
		world.generate_to(world.generated_height+40,false)

func _land(previous: Vector2) -> void:
	sim.grounded = false
	if sim.attached or sim.vel.y>0:
		return
	for ledge in world.ledges:
		var top: float = ledge["top"]
		if sim.pos.x>=float(ledge["left"])-.2 and sim.pos.x<=float(ledge["right"])+.2 and previous.y-.48>=top-.04 and sim.pos.y-.48<=top:
			sim.land(top)
			safe_position = sim.pos
			safe_anchor_id = -1
			return

func _update_bolt(step: float) -> void:
	var previous := bolt_pos
	var maximum := model.shot_range()
	if previous.distance_to(sim.pos)>maximum+.001:
		bolt_active = false
		toast("Канат полностью размотан",1)
		return
	var advance := model.value("throw_speeds",GameModel.THROW)*step
	var offset := previous-sim.pos
	# The rope pays out from the moving hero, not from the original shot point.
	var projection := offset.dot(bolt_direction)
	var remaining := -projection+sqrt(maxf(0,projection*projection+maximum*maximum-offset.length_squared()))
	var reached_end := advance>=remaining
	advance = minf(advance,remaining)
	bolt_pos += bolt_direction*advance
	bolt_travel += advance
	var collision := world.cast_hook(previous,bolt_pos,model.hook_radius())
	if not collision.is_empty():
		if bool(collision.get("blocked",false)):
			bolt_pos = collision["contact"]
			bolt_active = false
			toast("Выстрел перекрыт выступом",1.3)
			return
		var hit: Dictionary = collision["object"]
		bolt_active = false
		var kind: int = hit["kind"]
		var contact: Vector2 = collision["contact"]
		if sim.pos.distance_to(contact)>model.value("rope_lengths",0)+.15:
			toast("Не хватает длины каната")
			return
		anchor_contact = contact
		sim.attach(contact,model.value("rope_lengths",0))
		model.learn_control("aim")
		catches += 1
		anchor_id = hit["id"]
		anchor_time = 0
		focus_remaining = .7
		if kind in [0,2] and hit.get("permanent",true):
			safe_anchor_id = anchor_id
			safe_position = sim.pos
			safe_contact = contact
		_sound(760,.08)
	elif reached_end:
		bolt_active = false
		toast("Канат полностью размотан — целься ближе",1.5)

func _collect_finds() -> void:
	var radius := .54+model.value("magnet_radii",4)
	for find in world.finds:
		if bool(find.get("picked",false)) or sim.pos.distance_to(find["pos"])>radius:
			continue
		if model.try_pick(find["item"]):
			find["picked"] = true
			if is_instance_valid(find.get("visual")): find["visual"].visible = false
			_sound(1000,.08)
			hud.refresh_bag()

func fail_run(reason: String) -> void:
	if state!="play":
		return
	if sim.attached: release_hook()
	state = "revive" if not revive_used else "result"
	failure_reason = reason
	_reset_input()
	bolt_active = false
	_sound(120,.2)
	if not revive_used:
		save_snapshot()
		hud.show_revive(reason)
	else:
		finish_run(false)

func revive(currency: String) -> void:
	if state!="revive" or revive_used:
		return
	if currency=="diamonds":
		var cost: int = int(model.balance["diamond_revive_cost"])
		if int(model.profile["diamonds"])<cost:
			toast("Не хватает алмазов")
			return
		model.profile["diamonds"] -= cost
	elif currency=="test_ad":
		# No simulated ad impression/revenue: the UI labels this as a developer test.
		if not OS.is_debug_build():
			toast("Рекламный сервис ещё не подключён")
			return
	else:
		return
	revive_used = true
	sim.vel = Vector2.ZERO
	sim.pos = safe_position
	sim.flight_peak = sim.pos.y
	sim.attached = false
	sim.grounded = true
	anchor_id = -1
	if safe_anchor_id>=0:
		var point := world.anchor_by_id(safe_anchor_id)
		if not point.is_empty() and not point["broken"] and point.get("permanent",true):
			sim.pos = safe_contact+Vector2(0,-2.8)
			anchor_contact = safe_contact
			sim.attach(safe_contact,model.value("rope_lengths",0))
			anchor_id = safe_anchor_id
	anchor_time = 0
	state = "play"
	sim.flight_peak = sim.pos.y
	camera_y = maxf(4.8,sim.pos.y+2.5)
	camera_x = sim.pos.x
	_position_camera()
	hud.show_play()
	toast("Продолжение использовано · следующая ошибка завершит попытку")
	save_snapshot()

func finish_run(success: bool) -> void:
	if run_id.is_empty():
		return
	state = "result"
	_reset_input()
	bolt_active = false
	var rewarded_height := maxf(0,sim.highest-START_Y)
	if success:
		rewarded_height = maxf(rewarded_height,summit_height)
	settlement = model.settle(run_id,run_mode,rewarded_height,success,selected_location)
	if settlement.get("duplicate",false):
		return
	settlement["seconds"] = run_seconds
	settlement["reason"] = failure_reason
	settlement["shots"] = shots
	settlement["catches"] = catches
	settlement["zone_bonus"] = zone_gold
	if not preview:
		model.profile["run_history"].append({"id":run_id,"seed":run_seed,"seconds":snappedf(run_seconds,.1),"height":settlement["highest"],"gold":int(settlement["total"])+zone_gold,"zone_bonus":zone_gold,"success":success,"shots":shots,"catches":catches,"reason":failure_reason,"levels":model.profile["levels"].duplicate()})
		model.profile["run_history"][-1].merge({"build":"0.10.3","mode":run_mode,"location":selected_location,"height_gold":settlement["height"],"loot_gold":settlement["loot"],"finish_gold":settlement["finish"],"first_summit":settlement["first"]})
		model.profile["run_history"] = model.profile["run_history"].slice(-30)
		model.save()
	hud.show_result(settlement)

func pause_run() -> void:
	if state=="play":
		state = "pause"
		_reset_input()
		save_snapshot()
		hud.show_pause()

func unpause() -> void:
	if state=="pause":
		state = "play"
		hud.show_play()

func show_menu() -> void:
	if state=="play" or state=="pause":
		save_snapshot()
	state = "menu"
	lobby_location = selected_location
	_reset_input()
	if model.profile["active"].is_empty():
		run_id = ""
		run_mode = "summit"
		_create_world(58273,selected_location,36)
		sim = RopeSim.new()
		sim.pos = Vector2(-.7,8.9)
		sim.anchor = world.anchor_by_id(world.main_route[2])["pos"]
		sim.attached = true
		sim.length = sim.pos.distance_to(sim.anchor)
		camera_y = 7
	hud.show_menu()

func show_workshop() -> void:
	show_menu()

func show_locations() -> void:
	show_menu()

func cycle_location(direction: int) -> void:
	if not model.profile["active"].is_empty():
		return
	lobby_location = posmod(lobby_location+direction,model.balance["locations"].size())
	_create_world(58273,lobby_location,36)
	if model.profile["locations"].has(lobby_location):
		selected_location = lobby_location
		model.profile["selected_location"] = selected_location
		if not preview:
			model.save()
	hud.show_menu()

func lobby_action() -> void:
	if not model.profile["active"].is_empty():
		resume_run()
	elif model.profile["locations"].has(lobby_location):
		selected_location = lobby_location
		start_run(lobby_endless)
	else:
		toast(model.purchase_location(lobby_location))
		if model.profile["locations"].has(lobby_location):
			selected_location = lobby_location
			model.profile["selected_location"] = selected_location
			model.save()
		hud.show_menu()

func save_snapshot() -> void:
	if preview or run_id.is_empty() or state not in ["play","pause","revive"]:
		return
	var broken: Array = []
	for point in world.anchors:
		if point["broken"]:
			broken.append(point["id"])
	model.profile["active"] = {"id":run_id,"seed":run_seed,"generation_version":world.generation_version,"mode":run_mode,"location":selected_location,
		"camera_y":camera_y,
		"x":sim.pos.x,"y":sim.pos.y,"vx":sim.vel.x,"vy":sim.vel.y,"length":sim.length,"target_length":sim.target_length,
		"highest":sim.highest,"flight_peak":sim.flight_peak,"launched":sim.launched,"grounded":sim.grounded,
		"run_seconds":run_seconds,"shots":shots,"catches":catches,"failure_reason":failure_reason,"zone_gold":zone_gold,
		"anchor_id":anchor_id,"anchor_time":anchor_time,"contact_x":anchor_contact.x,"contact_y":anchor_contact.y,
		"safe_contact_x":safe_contact.x,"safe_contact_y":safe_contact.y,"focus_remaining":focus_remaining,"safe_anchor_id":safe_anchor_id,
		"safe_x":safe_position.x,"safe_y":safe_position.y,"revive_used":revive_used,"awaiting_revive":state=="revive",
		"bag":model.bag.duplicate(true),"picked":model.picked.duplicate(),"broken":broken,
		"bolt_active":bolt_active,"bolt_x":bolt_pos.x,"bolt_y":bolt_pos.y,"bolt_ox":bolt_origin.x,"bolt_oy":bolt_origin.y,
		"bolt_dx":bolt_direction.x,"bolt_dy":bolt_direction.y,"bolt_travel":bolt_travel}
	model.save()

func _notification(what: int) -> void:
	if model==null:
		return
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_snapshot()
		get_tree().quit()
	elif what==NOTIFICATION_APPLICATION_PAUSED:
		pause_run()
		save_snapshot()
	elif what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and state=="play" and not preview:
		pause_run()

func _move_camera(delta: float) -> void:
	var desired := maxf(4.8,sim.pos.y+2.5+clampf(sim.vel.y*.13,-.8,1.6))
	if state!="menu": desired = maxf(camera_y,desired)
	if state=="menu" and model.profile["active"].is_empty():
		desired = 7
		if not preview:
			sim.pos = Vector2(-.7+sin(elapsed*.9)*.7,8.9+cos(elapsed*.9)*.15)
	camera_y = lerpf(camera_y,desired,1-exp(-delta*7.5))
	var horizontal := sim.pos.x+clampf(sim.vel.x*.15,-1.3,1.3)
	if state=="menu": horizontal = 0
	if world.location!=0: horizontal = 0
	if capture_overview: horizontal = 0
	camera_x = lerpf(camera_x,horizontal,1-exp(-delta*5))
	_position_camera()

func _process(delta: float) -> void:
	elapsed += delta
	hint_timer = maxf(0,hint_timer-delta)
	if state=="play" and not preview:
		snapshot_timer += delta
		if snapshot_timer>3:
			snapshot_timer = 0
			save_snapshot()
	_move_camera(delta)
	world.update_visibility(camera_y,camera_x)
	if world.show_loot_prices!=(state=="play"):
		world.set_loot_prices_visible(state=="play")
	var target := sim.anchor if sim.attached else bolt_pos
	var warning := sim.attached and anchor_id>=0 and anchor_time>2.1 and int(world.anchor_by_id(anchor_id).get("kind",0))==1
	explorer.draw(sim,target,sim.attached or bolt_active,bolt_active,elapsed,warning,model.level(2))
	hud.update_play()
	if not capture_path.is_empty() and elapsed>1.1 and not capture_queued:
		capture_queued = true
		_capture_frame()

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(capture_path)
	print("CAPTURE_RESULT ",error," ",capture_path)
	get_tree().quit(error)

func toast(text: String, duration: float = 2.5) -> void:
	hint = text
	hint_timer = duration
	if is_instance_valid(hud):
		hud.set_toast(text)

func _sound(frequency: float, duration: float) -> void:
	if not model.profile.get("sound",true) or preview or DisplayServer.get_name()=="headless":
		return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := int(duration*stream.mix_rate)
	var data := PackedByteArray()
	data.resize(count*2)
	for i in range(count):
		var envelope := pow(1-float(i)/count,2)
		var sample := int(sin(TAU*frequency*i/stream.mix_rate)*envelope*15000)
		data.encode_s16(i*2,sample)
	stream.data = data
	audio.stream = stream
	audio.play()
