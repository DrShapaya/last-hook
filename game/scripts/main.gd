extends Node3D

const START_Y := .63
var model: GameModel
var sim := RopeSim.new()
var world: MountainWorld
var explorer: ExplorerView
# The world of the next likely attempt, generated and streamed in hidden
# while the lobby or the result screen is up, so a run starts on a mountain
# that is already standing (see _update_prepared_world).
var prepared_world: MountainWorld
var prepared_key: Dictionary = {}
var prepared_seed := 0
var prepared_rows_left := false
# Off in headless runs (tests, tools) unless a tool turns it on.
var prepare_worlds := DisplayServer.get_name()!="headless"
var camera: Camera3D
var scene_environment: Environment
var shadow_atlas_size := 0
var sun_light: DirectionalLight3D
var hud: GameHud
var state := "menu"
var run_mode := "summit"
var selected_location := 0
var lobby_location := 0
var lobby_endless := false
var run_id := ""
var run_seed := 0
# The prepared route of the current summit climb (LevelCatalog.ROUTES).
var run_route := -1
var summit_height := 120.0
const INITIAL_WORLD_HEIGHT := 65.0
const START_CAMERA_Y := 4.8
var anchor_id := -1
var anchor_time := 0.0
var anchor_contact := Vector2.ZERO
# Speed of the held contact over the stone (ice only), carried into a release.
var anchor_slide_velocity := Vector2.ZERO
var safe_contact := Vector2.ZERO
var safe_anchor_id := -1
var safe_position := Vector2(0,START_Y)
var revive_used := false
var bolt_active := false
var bolt_pos := Vector2.ZERO
var bolt_origin := Vector2.ZERO
var bolt_direction := Vector2.UP
var bolt_travel := 0.0
var hook_flight := HookFlight.new()
var hook_volley: HookVolley
var volley_primary := 0
var bolt_returning := false
var return_velocity := Vector2.ZERO
var shot_serial := 0
var impact_serial := 0
var hook_impact := Vector2.ZERO
var hook_impact_kind := ""
var pressed := false
var press_start := Vector2.ZERO
var pointer := Vector2.ZERO
var primary_touch := -1
var touch_gesture := false
var gesture_last_msec := 0
var climb_gesture := ClimbGesture.new()
const TOUCH_STICK_TOP_SHARE := .40
var touch_controls: Dictionary = {}
var aim_stick_valid := false
var gesture_suppressed := false
var aim_point := Vector2.ZERO
var pump := 0.0
var reel := 0.0
# Walking on a platform without a rope. A gesture that walked never throws.
var walk := 0.0
var walk_used := false
# Walking tuning comes from balance.json "movement" (see _configure_movement).
var WALK_SPEED := 2.6
var walk_acceleration := 12.0
var walk_deceleration := 16.0
var walk_turn_acceleration := 24.0
var walk_edge_braking := 9.0
var walk_edge_lookahead := .6
var landing_friction := 7.0
const EDGE_PROBE := .14
const EDGE_PROBE_STEP := .04
var focus_remaining := 0.0
# Real-time pause after a slow motion window before a release may start the
# next one, so quick catch/release chains cannot hold the world slowed.
var focus_cooldown := 0.0
var focus_duration := 0.0
var focus_serial := 0
var focus_blend := 0.0
var last_release_reason := ""
var aim_direction := Vector2.UP
var elapsed := 0.0
var animation_time := 0.0
# camera_y is the framing that defines the lower danger edge; it only rises
# during a run. After landing the view may sink by camera_dip to show the
# ground, without moving that edge.
var camera_y := 7.0
var camera_x := 0.0
var camera_dip := 0.0
const CAMERA_DIP_SHARE := .22
# Gameplay framing always uses camera_base_size: the danger edge, headroom and
# fall rules never depend on the zoom setting. Zoom only narrows what is drawn
# to a window inside that framing (camera_view_offset keeps the hero in it).
var camera_base_size := 24.0
var camera_zoom_current := 1.0
var camera_view_offset := 0.0
var snapshot_timer := 0.0
const SNAPSHOT_PERIOD := 3.0
const COIN_SAVE_DELAY := .5
var profile_save_pending := false
var profile_save_timer := 0.0
const PROFILE_SAVE_DEBOUNCE := .2
var hint_timer := 0.0
var hint := ""
var hint_context := ""
var settlement: Dictionary = {}
var capture_path := ""
var capture_screen := "play"
var capture_queued := false
var capture_overview := false
var capture_location := 0
var capture_tips := 1
var capture_left := false
var capture_grip := 12
var capture_seed := 58273
var capture_quality := ""
var loot_price_refresh_timer := 0.0
var last_loot_price_hero := Vector2.INF
var last_loot_price_aim := Vector2.INF
var last_loot_price_playing := false
var last_loot_price_always := false
const LAND_SOUND_SPEED := 4.0
const LAND_HAPTIC_SPEED := 11.0
const WALK_STEP_SECONDS := .34
# Air rushing past starts at this speed and is full at the second one.
const WIND_SPEED_MIN := 8.0
const WIND_SPEED_FULL := 30.0
var walk_step_clock := 0.0
var sounds: SoundBank
var haptics: Haptics
var music: MusicPlayer
var preview := false
var run_seconds := 0.0
var shots := 0
var catches := 0
var failure_reason := ""
var zone_gold := 0
var zone_diamonds := 0
var practice_return_model: GameModel
var ads := AdsService.new()
var ad_revive_run_id := ""
var ad_revive_authorized := false
var ad_revive_pending := false
# Act hazards (v14): a knock has a short grace time; the act is tracked to
# announce a new one.
var hazard_cooldown := 0.0
var current_act := -1
# The act hazards' own clock: it advances by the simulation step, so slow
# motion slows storms and icicles together with the hero. run_seconds stays
# real time for the result screen.
var hazard_clock := 0.0
# The grip the hero left last: a branch pocket keeps drifting it in flight.
var last_anchor_id := -1
# Chat 4: the active items carried this run ({"id","used"}), the running effect
# ({"id","remaining","duration"}), the beacon's highlighted exits, the run's
# contract and the pending full-bag swap.
var run_items: Array = []
var item_effect: Dictionary = {}
var beacon_targets: Array[Vector2] = []
var run_contract: Dictionary = {}
var swap_offer: Dictionary = {}
var swap_declined: Array = []

func _ready() -> void:
	Engine.max_fps = 0
	get_tree().auto_accept_quit = false
	# Android Back walks the menus (section -> main, run -> pause) and only
	# leaves the game from the main section.
	get_tree().quit_on_go_back = false
	# Climb art loads on worker threads from the start (see AssetWarmup).
	if DisplayServer.get_name()!="headless": AssetWarmup.start()
	model = GameModel.new()
	_configure_movement()
	_apply_graphics_quality(str(model.profile.get("graphics_quality","high")),false)
	selected_location = int(model.profile.get("selected_location",0))
	if not model.profile["active"].is_empty():
		selected_location = int(model.profile["active"].get("location",0))
	lobby_location = selected_location
	_setup_lighting()
	_apply_graphics_quality(str(model.profile.get("graphics_quality","high")),false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_base_size = clampf(float(model.camera_setting("base_size",24.0)),8.0,60.0)
	camera.size = camera_base_size
	camera.near = .1
	camera.far = 120
	add_child(camera)
	camera.current = true
	_setup_audio_buses()
	sounds = SoundBank.new()
	add_child(sounds)
	haptics = Haptics.new()
	add_child(haptics)
	music = MusicPlayer.new()
	add_child(music)
	music.enabled = int(_settings()["music_volume"])>0
	apply_audio()
	_apply_input()
	hud = GameHud.new()
	add_child(hud)
	_apply_accessibility()
	hud.setup(self)
	if model.save_blocked:
		toast(model.save_error,6.0,"save")
	_create_world(58273,0,36,0,true)
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
			capture_tips = clampi(int(argument.trim_prefix("--tips=")),1,4)
		if argument=="--overview": capture_overview = true
		if argument=="--left": capture_left = true
		if argument.begins_with("--seed="): capture_seed = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--grip="): capture_grip = maxi(2,int(argument.trim_prefix("--grip=")))
		if argument.begins_with("--quality="): capture_quality = argument.trim_prefix("--quality=")
	if not capture_path.is_empty():
		preview = true
		model.profile = GameModel.fresh_profile()
		if not capture_quality.is_empty(): _apply_graphics_quality(capture_quality,false)
		model.set_levels({GameModel.RADIUS:5 if capture_tips%2==0 else 1,GameModel.DOUBLE:2 if capture_tips>=3 else 1})
		selected_location = capture_location
		lobby_location = capture_location
		if capture_screen in ["play","rope","inventory","equipment","flight","slowmo"]:
			start_run(false)
			run_seed = capture_seed
			_create_world(run_seed,selected_location,summit_height+6)
			run_contract = world.contract_info()
			var point: Dictionary = world.anchor_by_id(world.main_route[mini(capture_grip,world.main_route.size()-1)])
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
			for route_index in range(mini(capture_grip,world.main_route.size()-1)):
				var previous_grip := world.anchor_by_id(world.main_route[route_index])
				if not previous_grip.get("permanent",true): previous_grip["broken"] = true
			model.profile["learned_controls"] = ["aim","swing","rope","release"]
			model.bag = [ItemCatalog.valuable(-10,0,"root_wall",1)]
			if capture_screen=="rope":
				sim.length = model.rope_length()
				sim.target_length = sim.length
			elif capture_screen=="inventory":
				model.set_level(GameModel.BAG,5)
				model.bag.append_array([{"id":-11,"tier":1,"value":75},{"id":-12,"tier":3,"value":220}])
			hud.refresh_bag()
			camera_y = sim.pos.y+2.5
			camera_x = sim.pos.x
			hint_timer = 0
			if capture_screen=="equipment":
				camera_base_size = 9
				camera.size = 9
				hud.hide()
			if capture_screen=="flight":
				bolt_active = true
				bolt_pos = sim.anchor
				sim.attached = false
			if capture_screen=="slowmo":
				sim.attached = false
				anchor_id = -1
				focus_duration = model.slowmo_seconds()
				focus_remaining = focus_duration*.6
				focus_blend = 1.0
		elif capture_screen == "result":
			state = "result"
			model.profile["gold"] = 4540
			model.profile["reached_zones"] = 6
			model.set_levels({GameModel.ROPE:3,GameModel.IMPULSE:2,GameModel.RADIUS:5,GameModel.BAG:3,GameModel.MAGNET:2,GameModel.RECOVERY:2,GameModel.THROW:3})
			hud.show_result({"success":true,"highest":1200,"height":540,"loot":900,"carried":900,"finish":1300,"contract":250,"contract_done":true,"coins":312,"recovery":100,
				"sets":[{"id":"forest_relic","name":"Метки старого лесника","parts":3,"completed":true}],"landmarks":["ridge_flag"],"materials":{"silk":1},"tokens":2,"spent":["beacon"],
				"total":2990,"diamonds":20,"zone_bonus":1800,"first":true,"seconds":214,"shots":51,"catches":43})
		elif capture_screen in ["practice","practice_result"]:
			start_practice()
			var grip := world.anchor_by_id(world.main_route[5])
			anchor_id = grip["id"]
			anchor_contact = grip["pos"]
			sim.pos = anchor_contact+Vector2(-2,-2.5)
			sim.attach(anchor_contact,5.5)
			camera_y = sim.pos.y+2.5
			camera_x = sim.pos.x
			model.profile["learned_controls"] = ["aim","swing","rope","release"]
			if capture_screen=="practice_result":
				sim.highest = START_Y+PracticeLayout.HEIGHT
				run_seconds = 72
				catches = 16
				shots = 19
				finish_run(true)
		elif capture_screen=="pause_bag":
			start_run(false)
			model.set_level(GameModel.BAG,5)
			for tier in range(6): model.bag.append({"id":-tier-1,"tier":tier,"value":int(model.balance["loot_values"][tier]*(1.8 if tier%2==1 else 1.0))})
			pause_run()
		elif capture_screen in ["workshop","supplies"] or capture_screen.begins_with("settings"):
			model.profile["gold"] = 640
			model.profile["reached_zones"] = 4
			model.profile["reached_acts"] = 2
			model.set_levels({GameModel.ROPE:3,GameModel.IMPULSE:2,GameModel.RADIUS:5,GameModel.BAG:3,GameModel.MAGNET:2,GameModel.RECOVERY:2,GameModel.THROW:3})
			model.profile["material_wallet"] = {"fiber":3,"silk":1}
			model.profile["consumable_stock"] = {"beacon":1,"glide":2}
			model.profile["active_loadout"] = ["beacon","glide"]
			model.profile["set_parts"] = {"forest_relic":2}
			hud.equipment_view = "supplies" if capture_screen=="supplies" else "upgrades"
			show_workshop()
			if capture_screen.begins_with("settings"):
				hud.settings_section = capture_screen.trim_prefix("settings_") if capture_screen!="settings" else "graphics"
				hud.select_menu("settings")
		elif capture_screen=="terrain":
			start_run(false)
			_create_world(58273,0,126)
			model.set_level(GameModel.ROPE,5)
			_configure_rope()
			var obstacle: Dictionary = world.obstacles[0]
			var center: Vector2 = obstacle["pos"]
			world.add_anchor(center+Vector2(-3,0),0)
			anchor_id = world.anchors[-1]["id"]
			anchor_contact = world.anchors[-1]["pos"]
			sim.pos = center+Vector2(3,-.4)
			sim.attach(anchor_contact,12)
			sim.length = 8.5
			sim.target_length = 8.5
			sim.highest = sim.pos.y
			model.reach(maxf(0,sim.highest-START_Y))
			world.update_rope_path(sim)
			camera_x = center.x
			camera_y = center.y+1
			camera_base_size = 16
			camera.size = 16
			hint_timer = 0
			model.profile["learned_controls"] = ["aim","swing","rope","release"]
		elif capture_screen in ["pause","revive","failure"]:
			start_run(false)
			if capture_screen=="pause":
				pause_run()
			elif capture_screen=="revive":
				model.profile["diamonds"] = 8
				state = "revive"
				hud.show_revive("Не хватило высоты для следующего зацепа")
			else:
				state = "result"
				hud.show_result({"highest":348,"height":128,"loot":24,"carried":80,"total":152,"seconds":63,"shots":15,"catches":12,"reason":"Упал ниже экрана"})
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
		if DisplayServer.get_name()!="headless" and OS.get_environment("LASTHOOK_NO_SPLASH").is_empty(): hud.show_splash()
	add_child(ads)
	ads.availability_changed.connect(_refresh_ad_actions)
	ads.rewarded_finished.connect(_on_ad_revive_finished)
	ads.reward_verified.connect(_on_ad_reward_verified)
	ads.fullscreen_changed.connect(_on_ad_fullscreen)
	ads.banner_layout_changed.connect(hud._resize)
	if not preview:
		ads.set_main_menu(state=="menu")
		# Let the first game frame appear before the optional ad SDK touches the
		# Android UI.  A few devices are slow or unstable during SDK startup.
		call_deferred("_setup_ads_deferred")

func _setup_ads_deferred() -> void:
	if not preview and is_instance_valid(ads):
		ads.setup()

func _setup_lighting() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	scene_environment = environment
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("2e739f")
	sky_material.sky_horizon_color = Color("a8d8e4")
	sky_material.ground_bottom_color = Color("244355")
	sky_material.ground_horizon_color = Color("8daeb3")
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = .08
	sky.sky_material = sky_material
	environment.sky = sky
	# One light model for every object on the climb: a warm sun from the upper
	# left in front of the wall, and a cool sky fill that keeps shaded facets
	# blue-grey instead of black.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Slightly cooler and higher than before, so the flanks of the volumes
	# stay readable and hollows never drop to near black.
	environment.ambient_light_color = Color("b6c7d6")
	environment.ambient_light_energy = .62
	environment.glow_enabled = true
	environment.glow_intensity = .10
	environment.glow_strength = .45
	environment.glow_hdr_threshold = 1.15
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = false
	environment.fog_light_color = Color("b8d1df")
	environment.fog_density = .0025
	environment_node.environment = environment
	add_child(environment_node)
	sun_light = DirectionalLight3D.new()
	sun_light.name = "Солнце"
	sun_light.basis = Basis.looking_at(SUN_DIRECTION,Vector3.UP)
	sun_light.light_color = Color("fff0d2")
	sun_light.light_energy = SUN_ENERGY
	sun_light.light_specular = .35
	sun_light.shadow_enabled = true
	# A single orthographic map: the camera is orthographic and moves only in
	# XY, so splits waste resolution and make edges swim between cascades.
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun_light.directional_shadow_fade_start = .9
	# Pancaking flattens casters in front of the shadow camera; with a flat
	# wall this misplaces the hero's and rope's shadows, so it is disabled.
	sun_light.directional_shadow_pancake_size = 0.0
	_apply_shadow_preset("balanced")
	add_child(sun_light)

const SUN_DIRECTION := Vector3(.30,-.50,-.81)
const SUN_ENERGY := .46

func _set_shadow_atlas(atlas_size: int) -> void:
	if atlas_size==shadow_atlas_size: return
	shadow_atlas_size = atlas_size
	RenderingServer.directional_shadow_atlas_set_size(atlas_size,true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)

func _apply_shadow_preset(preset: String) -> void:
	if not is_instance_valid(sun_light): return
	# Texel-scaled biases are tuned for objects floating 0.3-3 units in front
	# of the wall: low enough that shadows touch their casters, high enough
	# that facets never self-acne while the camera scrolls.
	match preset:
		"high":
			sun_light.shadow_enabled = true
			# Readable cast shadows between rock masses; ambient fill keeps them blue-grey.
			sun_light.shadow_opacity = .46
			sun_light.light_energy = SUN_ENERGY
			sun_light.shadow_bias = .04
			sun_light.shadow_normal_bias = 1.2
			sun_light.shadow_blur = 1.8
			sun_light.directional_shadow_max_distance = 46
			_set_shadow_atlas(4096)
		"off":
			sun_light.shadow_enabled = false
			sun_light.shadow_opacity = .28
			# Without shadows, unshadowed illumination covers all surfaces; keep exposure natural.
			sun_light.light_energy = SUN_ENERGY*1.1
			sun_light.directional_shadow_max_distance = 40
			# Shadows are off: the atlas and filter stay as they are, so a later
			# switch back does not recompile every 3D shader.
		_:
			sun_light.shadow_enabled = true
			sun_light.shadow_opacity = .44
			sun_light.light_energy = SUN_ENERGY
			sun_light.shadow_bias = .04
			sun_light.shadow_normal_bias = 1.2
			sun_light.shadow_blur = 1.4
			sun_light.directional_shadow_max_distance = 42
			_set_shadow_atlas(2048)

func _settings() -> Dictionary:
	return model.profile["settings"]

# A preset name fills the graphics settings; "custom" keeps them as they are.
func _apply_graphics_quality(quality: String, save: bool = true) -> void:
	if GameSettings.PRESETS.has(quality):
		GameSettings.apply_preset(_settings(),quality)
		model.profile["graphics_quality"] = quality
	_apply_graphics()
	if save and not preview: request_profile_save()

func _apply_graphics() -> void:
	# _ready calls this before lighting exists; it runs again once it does.
	if not is_instance_valid(sun_light): return
	var settings := _settings()
	# The workload changes freely, the frame pacing only on request: VSync
	# follows the display's refresh rate (60/90/120 Hz), and a 60 fps cap on a
	# 90/120 Hz screen alternates frame lengths and flickers like a strobe.
	Engine.max_fps = int(settings["fps_limit"])
	# Each of these recreates GPU targets and can drop a frame: only a real
	# change may touch them, or every setting would blink the screen.
	if DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_ENABLED: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_apply_shadow_preset(str(settings["shadows"]))
	# Glow is a chain of full-screen blur passes.
	if scene_environment!=null: scene_environment.glow_enabled = bool(settings["glow"])
	if not is_equal_approx(get_viewport().scaling_3d_scale,float(settings["render_scale"])): get_viewport().scaling_3d_scale = float(settings["render_scale"])
	if is_instance_valid(world): _world_graphics(world)
	if is_instance_valid(explorer): _explorer_graphics()

func _apply_accessibility() -> void:
	var settings := _settings()
	MenuSurface.apply_palette(str(settings["color_scheme"]),bool(settings["high_contrast"]))
	hud.text_scale = int(settings["text_scale"])*.01
	hud.bold_outline = bool(settings["high_contrast"])

func _apply_input() -> void:
	var settings := _settings()
	KeyBindings.apply(settings["key_bindings"])
	climb_gesture.hold_seconds = float(settings["hold_seconds"])
	climb_gesture.sensitivity = int(settings["sensitivity"])*.01

func _world_graphics(target: MountainWorld) -> void:
	var settings := _settings()
	target.set_sky_quality(str(settings["sky"]))
	target.set_effects_quality(str(settings["particles"]))
	target.set_visual_quality(str(settings["decor"]))

func _explorer_graphics() -> void:
	explorer.set_visual_quality("battery" if str(_settings()["shadows"])=="off" else "high")
	explorer.effects_quality = str(_settings()["particles"])

func set_graphics_preset(preset: String) -> void:
	_apply_graphics_quality(preset)

# One setting from the menu: stored, applied, saved. The controls update
# themselves in place, so no page is rebuilt.
func set_setting(key: String, value: Variant) -> void:
	_settings()[key] = value
	model.profile["settings"] = GameSettings.sanitize(_settings())
	if key in GameSettings.PRESETS["high"]:
		model.profile["graphics_quality"] = GameSettings.detect_preset(_settings())
	apply_setting(key)
	request_profile_save()

func apply_setting(key: String) -> void:
	if key in GameSettings.PRESETS["high"] or key=="fps_limit": _apply_graphics()
	elif key in GameSettings.VOLUME_KEYS: apply_audio()
	elif key in ["hold_seconds","sensitivity","key_bindings"]: _apply_input()
	elif key in ["text_scale","high_contrast","color_scheme"]:
		_apply_accessibility()
		hud.rebuild_all_pages()

func _create_world(seed_number: int, location_number: int, height: float, saved_version: int = 0, menu_preview: bool = false, visual_budget: int = -1, route: int = -1) -> void:
	if is_instance_valid(world):
		world.queue_free()
	if is_instance_valid(explorer):
		explorer.queue_free()
	world = MountainWorld.new()
	# Runtime worlds build visual chunks incrementally. Tests and offline tools
	# keep MountainWorld's default synchronous budget for deterministic queries.
	world.visual_build_budget = visual_budget
	# Build the initial playable area in one deterministic pass, then extend
	# endless/finite routes one generator row at a time during the run.
	world.generation_row_budget = -1
	world.visuals_enabled = not menu_preview
	add_child(world)
	var version := saved_version if saved_version>0 else MountainWorld.generation_version_for(location_number)
	var level := _level_bake(location_number,route,version,height) if not menu_preview and run_mode=="summit" else null
	# A baked level is set up exactly as it was baked: its seed and generator.
	if level!=null: world.setup(level.seed_value,location_number,saved_version,false,route,level.generator=="masks")
	else: world.setup(seed_number,location_number,saved_version,run_mode=="practice",route)
	_world_graphics(world)
	scene_environment.background_color = Color("88bfd9") if location_number==0 else Color("142438")
	if level!=null: world.load_bake(level)
	else: world.generate_to(height,run_mode in ["summit","practice"],summit_height)
	world.generation_row_budget = 1 if visual_budget>=0 and not (world.layout is LegacyMountainLayout) else -1
	if not menu_preview: _attach_explorer()

func _attach_explorer() -> void:
	explorer = ExplorerView.new()
	add_child(explorer)
	explorer.setup(world,model.hook_tips())
	_explorer_graphics()
	explorer.set_hook_configuration(model.hook_tips(),model.hook_count())
	explorer.set_walk_speed(WALK_SPEED)

# The level made in advance for this summit climb, when it matches the world
# being created (same generator and height); null to generate it instead.
func _level_bake(location: int, route: int, version: int, world_height: float) -> LevelBake:
	var level := LevelBake.find(location,route,version)
	if level==null or not is_equal_approx(level.height+6,world_height): return null
	return level

# What start_run would build for this location and mode, except a random
# seed: two equal keys give the same world. Empty when no run is likely.
func _run_world_key(location: int, endless: bool) -> Dictionary:
	if practice_return_model!=null or preview: return {}
	if not model.profile["locations"].has(location): return {}
	if endless and not model.profile["summit_cleared"]: return {}
	return {"location":location,"endless":endless,"route":-1 if endless else model.route_choice(location),
		"quality":str(_settings()["decor"]),"effects":str(_settings()["particles"]),"sky":str(_settings()["sky"]),"scheme":str(_settings()["color_scheme"]),"version":MountainWorld.generation_version_for(location)}

# The attempt the player would start next from the current screen.
func _next_run_key() -> Dictionary:
	if state=="menu":
		if not model.profile["active"].is_empty(): return {}
		return _run_world_key(lobby_location,lobby_endless)
	# Retry from the failure or reward screen starts the same summit again.
	if state in ["result","revive"]: return _run_world_key(selected_location,false)
	return {}

func _discard_prepared_world() -> void:
	if is_instance_valid(prepared_world): prepared_world.queue_free()
	prepared_world = null
	prepared_key = {}
	prepared_rows_left = false

# Off the run, builds the next attempt's world a slice per frame: the route
# graph in one pass when the screen changes, then the sections round the
# start through the usual streaming jobs. Nothing of it is shown until
# start_run takes it over.
func _update_prepared_world() -> void:
	var key := _next_run_key()
	if key!=prepared_key: _discard_prepared_world()
	if key.is_empty() or not prepare_worlds: return
	if not is_instance_valid(prepared_world):
		var endless: bool = key["endless"]
		var location: int = key["location"]
		var route: int = key["route"]
		prepared_key = key
		prepared_seed = int(LevelCatalog.route(location,route)["seed"]) if route>=0 else randi_range(1000,999999)
		var height := float(model.balance["locations"][location]["height_units"])
		prepared_world = MountainWorld.new()
		prepared_world.name = "Подготовленная гора"
		prepared_world.visible = false
		prepared_world.build_urgency = false
		prepared_world.visual_build_budget = 1
		prepared_world.generation_row_budget = -1
		add_child(prepared_world)
		var level := _level_bake(location,route,MountainWorld.generation_version_for(location),height+6) if not endless else null
		if level!=null: prepared_world.setup(level.seed_value,location,0,false,route,level.generator=="masks")
		else: prepared_world.setup(prepared_seed,location,0,false,route)
		_world_graphics(prepared_world)
		if level!=null:
			# A level made in advance: its layout is read, not generated.
			prepared_world.load_bake(level)
			prepared_world.generation_row_budget = -1
			return
		prepared_rows_left = true
		return
	if prepared_rows_left:
		# The route graph a few rows per frame, then the summit and loot.
		_prepare_rows(MountainWorld.BUILD_SLICE_USEC)
		return
	if prepared_world.stream_pending or prepared_world.stream_dirty:
		prepared_world.update_visibility(START_CAMERA_Y,0,1)

# Generates prepared rows for up to `slice` microseconds (0: all of them);
# the last step adds the summit and resolves the loot as generate_to does.
func _prepare_rows(slice: int) -> void:
	var endless: bool = prepared_key["endless"]
	var height := float(model.balance["locations"][int(prepared_key["location"])]["height_units"])
	var target := height+6 if not endless else INITIAL_WORLD_HEIGHT
	var deadline := Time.get_ticks_usec()+slice
	while prepared_rows_left and (slice<=0 or Time.get_ticks_usec()<deadline):
		prepared_rows_left = prepared_world.generate_rows(target,not endless,height,1)
	if prepared_rows_left: return
	prepared_world.generate_to(target,not endless,height)
	prepared_world.generation_row_budget = 1 if not (prepared_world.layout is LegacyMountainLayout) else -1

# A short start transition: the HUD's iris opens on the climber over the
# place's name while the camera settles back from a slightly closer view.
# The run is live from the first frame; this only dresses it.
func _play_level_intro() -> void:
	if preview: return
	var heading: String = LevelCatalog.level(selected_location)["display_name"]
	var note := "Тренировка" if run_mode=="practice" else "Бесконечный подъём" if run_mode=="endless" else ""
	if run_route>=0: note = str(LevelCatalog.route(selected_location,run_route).get("name",""))
	if run_mode=="practice": heading = "Тренировочная стена"
	hud.play_intro(camera.unproject_position(Vector3(sim.pos.x,sim.pos.y,0)),heading,note)
	camera_zoom_current = camera_zoom_target()*1.12
	_position_camera()

func _adopt_prepared_world() -> void:
	if prepared_rows_left: _prepare_rows(0)
	if is_instance_valid(world): world.queue_free()
	if is_instance_valid(explorer): explorer.queue_free()
	world = prepared_world
	world.build_urgency = true
	prepared_world = null
	prepared_key = {}
	world.name = "MountainWorld"
	scene_environment.background_color = Color("88bfd9") if world.location==0 else Color("142438")
	_attach_explorer()

func ensure_menu_explorer() -> void:
	if is_instance_valid(explorer) or not is_instance_valid(world):
		return
	explorer = ExplorerView.new()
	add_child(explorer)
	explorer.setup(world,model.hook_tips())
	_explorer_graphics()
	explorer.set_hook_configuration(model.hook_tips(),model.hook_count())
	explorer.set_walk_speed(WALK_SPEED)
	explorer.visible = false

func start_run(endless: bool) -> void:
	if ads.fullscreen: return
	ads.preload_fullscreen()
	if endless and not model.profile["summit_cleared"]:
		toast("Бесконечный режим откроется после первой вершины")
		return
	var practice := practice_return_model!=null
	run_mode = "practice" if practice else "endless" if endless else "summit"
	# The world prepared behind the lobby or result screen is taken over
	# when it matches this attempt; its random seed then is the run's.
	var key := _run_world_key(selected_location,endless) if not practice else {}
	var adopt := not key.is_empty() and is_instance_valid(prepared_world) and key==prepared_key
	run_seed = PracticeLayout.SEED if practice else prepared_seed if adopt else randi_range(1000,999999)
	# A summit climb runs on the prepared route chosen in the lobby; its seed
	# is fixed, so the route is the same on every attempt.
	run_route = model.route_choice(selected_location) if run_mode=="summit" else -1
	if run_route>=0: run_seed = int(LevelCatalog.route(selected_location,run_route)["seed"])
	run_id = "%d-%d" % [Time.get_unix_time_from_system(),randi()]
	summit_height = PracticeLayout.HEIGHT if practice else float(model.balance["locations"][selected_location]["height_units"])
	# Generate the finite route graph before play starts so the summit and its
	# final platform always exist in the same world snapshot. Visual chunks are
	# still streamed incrementally by MountainWorld.
	if adopt: _adopt_prepared_world()
	else:
		_discard_prepared_world()
		_create_world(run_seed,selected_location,summit_height+6 if not endless else INITIAL_WORLD_HEIGHT,0,false,1,run_route)
	sim = RopeSim.new()
	sim.pos = Vector2(0,START_Y)
	sim.highest = START_Y
	sim.flight_peak = START_Y
	_configure_rope()
	model.bag = []
	model.picked = []
	model.begin_run_ledger(run_id)
	run_items = model.take_run_items() if run_mode!="practice" else []
	item_effect = {}
	beacon_targets.clear()
	swap_offer = {}
	swap_declined = []
	run_contract = world.contract_info() if run_mode=="summit" else {}
	anchor_id = -1
	safe_anchor_id = -1
	anchor_time = 0
	safe_position = sim.pos
	revive_used = false
	ad_revive_pending = false
	ad_revive_run_id = ""
	bolt_active = false
	bolt_returning = false
	hook_flight = HookFlight.new()
	hook_volley = null
	volley_primary = 0
	focus_remaining = 0.0
	focus_cooldown = 0.0
	focus_duration = model.slowmo_seconds()
	focus_blend = 0.0
	camera_y = START_CAMERA_Y
	camera_x = 0
	camera_dip = 0.0
	_position_camera()
	# The first frame shows a finished mountain: whatever of the view is not
	# built yet (nothing, on a prepared world) is built now, not in sight.
	world.complete_view(camera_y,camera_x,camera.size*.5+2)
	state = "play"
	ads.report_event("run_started_%s" % run_mode)
	lobby_location = selected_location
	current_act = int(world.act_at(sim.pos.y).get("index",-1))
	hazard_cooldown = 0.0
	run_seconds = 0
	hazard_clock = 0.0
	shots = 0
	catches = 0
	failure_reason = ""
	zone_gold = 0
	zone_diamonds = 0
	_reset_input()
	hud.show_play()
	if is_instance_valid(world): world.visible = true
	if is_instance_valid(explorer): explorer.visible = true
	_play_level_intro()
	if "aim" not in model.profile["learned_controls"]:
		toast("Коснись где удобно, потяни как стик и отпусти" if hud.touch_controls_hint else "Прицелься мышью и отпусти ЛКМ",4,"controls")
	save_snapshot()

func start_practice() -> void:
	if not model.profile["active"].is_empty():
		toast("Сначала заверши или продолжи сохранённую попытку")
		return
	practice_return_model = model
	model = GameModel.new(model.save_path.get_basename()+"-practice.json")
	model.profile = GameModel.fresh_profile()
	model.profile["settings"] = practice_return_model.profile["settings"].duplicate(true)
	selected_location = 0
	start_run(false)

func resume_run() -> void:
	var snapshot: Dictionary = model.profile["active"]
	if snapshot.is_empty():
		return
	var saved_version := int(snapshot.get("generation_version",0))
	if not MountainWorld.resumable(saved_version,int(snapshot.get("location",0))):
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
	run_route = int(snapshot.get("route",-1))
	run_id = snapshot["id"]
	summit_height = PracticeLayout.HEIGHT if run_mode=="practice" else float(model.balance["locations"][selected_location]["height_units"])
	var resume_height := maxf(float(snapshot["highest"])+40,INITIAL_WORLD_HEIGHT) if run_mode=="endless" else summit_height+6
	_create_world(run_seed,selected_location,resume_height,saved_version,false,1,run_route)
	sim = RopeSim.new()
	sim.pos = Vector2(snapshot["x"],snapshot["y"])
	sim.vel = Vector2(snapshot["vx"],snapshot["vy"])
	_configure_rope()
	sim.length = minf(float(snapshot["length"]),sim.maximum_length)
	sim.target_length = clampf(float(snapshot.get("target_length",sim.length)),RopeSim.MIN_LENGTH,sim.maximum_length)
	sim.reel_velocity = clampf(float(snapshot.get("reel_velocity",0)),-sim.reel_in_speed,sim.reel_out_speed)
	sim.highest = float(snapshot["highest"])
	sim.flight_peak = float(snapshot["flight_peak"])
	run_seconds = float(snapshot.get("run_seconds",0))
	# Saves from before the separate clock ran the hazards on run_seconds.
	hazard_clock = float(snapshot.get("hazard_clock",run_seconds))
	shots = int(snapshot.get("shots",0))
	catches = int(snapshot.get("catches",0))
	failure_reason = snapshot.get("failure_reason","")
	zone_gold = int(snapshot.get("zone_gold",0))
	zone_diamonds = int(snapshot.get("zone_diamonds",0))
	sim.launched = bool(snapshot["launched"])
	sim.grounded = bool(snapshot.get("grounded",false))
	anchor_id = int(snapshot["anchor_id"])
	anchor_time = float(snapshot["anchor_time"])
	focus_remaining = clampf(float(snapshot.get("focus_remaining",0.0)),0.0,model.slowmo_seconds()) if bool(snapshot.get("focus_active",false)) else 0.0
	focus_duration = clampf(float(snapshot.get("focus_duration",model.slowmo_seconds())),focus_remaining,model.slowmo_seconds())
	focus_cooldown = clampf(float(snapshot.get("focus_cooldown",0.0)),0.0,model.slowmo_cooldown())
	safe_anchor_id = int(snapshot["safe_anchor_id"])
	safe_position = Vector2(snapshot["safe_x"],snapshot["safe_y"])
	revive_used = bool(snapshot["revive_used"])
	ad_revive_pending = bool(snapshot.get("ad_revive_earned",false))
	ad_revive_run_id = ""
	model.bag = snapshot["bag"].duplicate(true)
	model.picked = snapshot["picked"].duplicate()
	model.begin_run_ledger(run_id)
	run_items = []
	for entry in snapshot.get("run_items",[]):
		if entry is Dictionary and not ItemCatalog.consumable(str(entry.get("id",""))).is_empty():
			run_items.append({"id":str(entry["id"]),"used":bool(entry.get("used",false))})
	item_effect = {}
	var saved_effect = snapshot.get("item_effect",{})
	if saved_effect is Dictionary and not saved_effect.is_empty() and not ItemCatalog.consumable(str(saved_effect.get("id",""))).is_empty():
		item_effect = {"id":str(saved_effect["id"]),"remaining":maxf(0,float(saved_effect.get("remaining",0))),"duration":float(saved_effect.get("duration",1))}
		if bool(saved_effect.get("armed",false)): item_effect.merge({"armed":true,"index":int(saved_effect.get("index",-1))})
	beacon_targets.clear()
	swap_offer = {}
	swap_declined = []
	run_contract = world.contract_info() if run_mode=="summit" else {}
	for point in world.anchors:
		point["broken"] = not snapshot.get("active_reserves",[]).has(point["id"]) if point.get("reserve",false) else snapshot["broken"].has(point["id"])
		GripSpec.restore(point,int(point["id"])==anchor_id)
	for find in world.finds:
		find["picked"] = model.picked.has(find["item"]["id"]) or find.get("withdrawn",false)
	world.restore_hazards(snapshot.get("collapsed_hazards",[]))
	current_act = int(world.act_at(sim.pos.y).get("index",-1))
	hazard_cooldown = 0.0
	if anchor_id>=0:
		var point := world.anchor_by_id(anchor_id)
		if not point.is_empty() and not point["broken"]:
			sim.attached = true
			anchor_contact = Vector2(snapshot.get("contact_x",point["pos"].x),snapshot.get("contact_y",point["pos"].y))
			sim.anchor = anchor_contact
			sim.anchor = world.anchor_contact_after(point,anchor_contact,anchor_time)
			if world.generation_version>=10:
				for pivot in snapshot.get("rope_pivots",[]):
					if pivot is Array and pivot.size()==2: sim.rope_pivots.append(Vector2(pivot[0],pivot[1]))
				sim.request_length(sim.target_length)
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
	# Rebuild the beacon preview after loading a run so an active effect keeps
	# showing the same reachable exits as it did before the save.
	if item_effect_id()=="beacon": beacon_targets = reachable_exits()
	bolt_active = bool(snapshot.get("bolt_active",false))
	bolt_pos = Vector2(snapshot.get("bolt_x",0),snapshot.get("bolt_y",0))
	bolt_origin = Vector2(snapshot.get("bolt_ox",0),snapshot.get("bolt_oy",0))
	bolt_direction = Vector2(snapshot.get("bolt_dx",0),snapshot.get("bolt_dy",1))
	bolt_travel = float(snapshot.get("bolt_travel",0))
	hook_flight.position = bolt_pos
	hook_flight.velocity = Vector2(snapshot.get("bolt_vx",bolt_direction.x*model.throw_speed()),snapshot.get("bolt_vy",bolt_direction.y*model.throw_speed()))
	hook_flight.age = float(snapshot.get("bolt_age",0))
	hook_flight.trail = PackedVector2Array([bolt_pos])
	bolt_returning = bool(snapshot.get("bolt_returning",false)) and not sim.attached and not bolt_active
	return_velocity = Vector2(snapshot.get("return_vx",0),snapshot.get("return_vy",0))
	hook_volley = null
	if snapshot.get("hook_volley",[]).size()==2:
		hook_volley = HookVolley.new()
		hook_volley.restore(snapshot["hook_volley"])
		volley_primary = clampi(int(snapshot.get("volley_primary",0)),0,1)
		# A saved catch whose anchor did not survive must not leave a head on it.
		for index in range(hook_volley.shots.size()):
			var saved_state: String = hook_volley.shots[index]["state"]
			if saved_state=="contact" or (saved_state=="attached" and not sim.attached): hook_volley.return_shot(index)
		_sync_volley()
	camera_y = float(snapshot.get("camera_y",maxf(4.8,sim.pos.y+2.5)))
	camera_x = float(snapshot.get("camera_x",sim.pos.x))
	camera_dip = maxf(0,float(snapshot.get("camera_dip",0.0)))
	_position_camera()
	world.complete_view(camera_y,camera_x,camera.size*.5+2)
	state = "revive" if bool(snapshot.get("awaiting_revive",false)) else "play"
	_reset_input()
	if state=="revive":
		hud.show_revive()
		if bool(snapshot.get("ad_revive_earned",false)) and not revive_used:
			ad_revive_authorized = true
			revive("ad")
			ad_revive_authorized = false
	else:
		hud.show_play()

func _input(event: InputEvent) -> void:
	if ads.fullscreen:
		get_viewport().set_input_as_handled()
		return
	# Finish an owned touch even over GUI controls. Extra fingers never take
	# over the stick or turn an ignored touch into a later shot.
	if state!="play" or preview:
		return
	if primary_touch>=0 and (event is InputEventScreenTouch or event is InputEventScreenDrag) and event.index!=primary_touch:
		# Pause stays in reach of a second finger while the first one steers:
		# the held gesture is dropped without a shot and the run pauses.
		if event is InputEventScreenTouch and event.pressed and hud.pause_at(event.position):
			_cancel_primary()
			pause_run()
			get_viewport().set_input_as_handled()
			return
		# A second finger may still tap an item while the first one steers.
		if event is InputEventScreenTouch and hud.item_button_at(event.position): return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and not event.pressed:
		if event.index==primary_touch:
			if event.canceled: _cancel_primary()
			else: pointer_up(event.position)
			primary_touch = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index==primary_touch:
			pointer_move(event.position)
			get_viewport().set_input_as_handled()
	elif not OS.has_feature("mobile") and primary_touch<0 and pressed:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			pointer_up(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			pointer_move(event.position)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if ads.fullscreen: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if state=="menu":
				if hud.menu_tab!="expedition": go_back()
			else:
				pause_run() if state=="play" else unpause() if state=="pause" else show_menu()
		elif event.is_action_pressed("release") and state=="play":
			if sim.attached: model.learn_control("release")
			release_hook(pressed)
		elif event.is_action_pressed("item_1") and state=="play":
			activate_item(0)
		elif event.is_action_pressed("item_2") and state=="play":
			activate_item(1)
	if state != "play" or preview:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if primary_touch<0:
				pointer_down(event.position,true)
				if pressed:
					primary_touch = event.index
	elif event is InputEventMouseButton and not OS.has_feature("mobile") and primary_touch<0:
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				pointer_down(event.position)
			else:
				pointer_up(event.position)
		elif event.pressed and sim.attached:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:
				sim.request_length(sim.target_length-.4*climb_gesture.sensitivity)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
				sim.request_length(sim.target_length+.4*climb_gesture.sensitivity)
	elif event is InputEventMouseMotion and not OS.has_feature("mobile") and primary_touch<0:
		pointer_move(event.position)

func pointer_down(point: Vector2, from_touch: bool = false) -> void:
	if state!="play" or ads.fullscreen or pressed or not hud.world_input_allowed(point):
		return
	# Keep the floating touch stick out of the top HUD: on a phone its origin
	# may be placed only in the lower 60% of the viewport. Mouse aiming keeps
	# the desktop behaviour and is not subject to this touch-only safe area.
	if from_touch and OS.has_feature("mobile"):
		var viewport_height := get_viewport().get_visible_rect().size.y
		if viewport_height>0.0 and point.y<viewport_height*TOUCH_STICK_TOP_SHARE:
			return
	pressed = true
	gesture_suppressed = false
	press_start = point
	pointer = point
	touch_gesture = from_touch
	hud.touch_controls_hint = from_touch or OS.has_feature("mobile")
	if hint_context=="controls": hint_timer = 0
	gesture_last_msec = Time.get_ticks_msec()
	aim_stick_valid = false
	climb_gesture.begin(point,gesture_last_msec*.001,_gesture_scale())
	touch_controls = climb_gesture.sample(gesture_last_msec*.001)
	if not sim.attached:
		_refresh_aim()

func pointer_move(point: Vector2, timestamp_msec: int = -1) -> void:
	var now_msec := Time.get_ticks_msec() if timestamp_msec<0 else timestamp_msec
	pointer = point
	if not pressed:
		return
	var difference := point-press_start
	gesture_last_msec = maxi(gesture_last_msec,now_msec)
	if touch_gesture:
		touch_controls = climb_gesture.move(point,gesture_last_msec*.001,_gesture_scale())
		_update_touch_controls(gesture_last_msec)
	elif sim.attached:
		pump = ClimbGesture.axis(difference.x/_gesture_scale(),ClimbGesture.STICK_RADIUS/climb_gesture.sensitivity)
	_refresh_aim()

func _update_touch_controls(timestamp_msec: int = -1) -> void:
	if not pressed or not touch_gesture: return
	var now_msec := Time.get_ticks_msec() if timestamp_msec<0 else timestamp_msec
	touch_controls = climb_gesture.sample(maxi(now_msec,gesture_last_msec)*.001)
	pump = float(touch_controls["pump"]) if sim.attached else 0.0
	reel = float(touch_controls["reel"]) if sim.attached else 0.0
	walk = float(touch_controls.get("walk",0.0)) if can_walk() else 0.0
	if walk!=0.0:
		walk_used = true
		aim_stick_valid = false

func pointer_up(point: Vector2) -> void:
	if not pressed:
		return
	pointer_move(point)
	if sim.attached:
		if touch_gesture:
			model.learn_control("release")
			release_hook()
	elif not touch_gesture or (aim_stick_valid and not gesture_suppressed):
		fire_hook(aim_direction)
	_cancel_primary()

func _refresh_aim() -> void:
	if not pressed or sim.attached: return
	if touch_gesture:
		# The stick selects a launch angle, not a world target. Camera motion,
		# player velocity and touch location cannot rotate a held direction.
		var offset := climb_gesture.offset
		aim_stick_valid = offset.length()>=ClimbGesture.AIM_DEAD_ZONE and not walk_used
		if aim_stick_valid:
			aim_direction = Vector2(offset.x,-offset.y).normalized()
		aim_point = sim.pos+aim_direction*model.shot_range()
	else:
		aim_point = _screen_world(pointer)
	if not touch_gesture and aim_point.distance_squared_to(sim.pos)>.04:
		aim_direction = direction_to_target(aim_point)

func _recenter_climb_control(suppress_fire: bool = false) -> void:
	# Keep the floating stick's base where the finger started. Physical
	# releases (a broken root or a routed rope) can happen while the finger is
	# held high; moving the base to pointer makes the whole stick jump on
	# screen. Reset only the gesture state so the current touch becomes neutral.
	climb_gesture.begin(press_start,Time.get_ticks_msec()*.001,_gesture_scale())
	touch_controls = {}
	aim_stick_valid = false
	gesture_suppressed = suppress_fire
	pump = 0
	reel = 0

func _cancel_primary() -> void:
	pressed = false
	primary_touch = -1
	touch_gesture = false
	aim_stick_valid = false
	gesture_suppressed = false
	pump = 0
	reel = 0
	walk = 0
	walk_used = false
	touch_controls = {}
	climb_gesture.reset()

func _configure_movement() -> void:
	WALK_SPEED = maxf(.5,model.movement("walk_speed",2.6))
	walk_acceleration = maxf(.5,model.movement("walk_acceleration",12.0))
	walk_deceleration = maxf(.5,model.movement("walk_deceleration",16.0))
	walk_turn_acceleration = maxf(.5,model.movement("walk_turn_acceleration",24.0))
	walk_edge_braking = maxf(.5,model.movement("walk_edge_braking",9.0))
	walk_edge_lookahead = clampf(model.movement("walk_edge_lookahead",.6),0.0,2.0)
	landing_friction = maxf(.5,model.movement("landing_friction",7.0))
	if is_instance_valid(explorer): explorer.set_walk_speed(WALK_SPEED)

func _configure_rope() -> void:
	_configure_movement()
	sim.maximum_length = model.rope_length()
	sim.reel_in_speed = model.reel_in_speed()
	sim.reel_out_speed = model.reel_out_speed()
	sim.swing_force = model.swing_force()
	sim.fall_speed_limit = float(model.balance["fall_speed_limit_units"])
	sim.gravity = float(model.balance["gravity"])

func _gesture_scale() -> float:
	return maxf(.1,hud.root.scale.x)

func _reset_input() -> void:
	_cancel_primary()

func _screen_world(point: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var distance := -origin.z/direction.z
	var result := origin+direction*distance
	return Vector2(result.x,result.y)

func fire_hook(direction: Vector2) -> void:
	if bolt_active or sim.attached or direction.length()<.01:
		return
	if hint_context in ["release","hook"]: hint_timer = 0
	bolt_active = true
	shots += 1
	bolt_origin = sim.pos
	bolt_pos = sim.pos
	bolt_direction = direction.normalized()
	bolt_travel = 0
	bolt_returning = false
	hook_flight.launch(sim.pos,bolt_direction,model.throw_speed(),throw_carry_velocity())
	hook_volley = null
	volley_primary = 0
	if model.hook_count()==2:
		hook_volley = HookVolley.new()
		hook_volley.launch(sim.pos,model.hook_directions(direction),model.throw_speed(),throw_carry_velocity())
		_sync_volley()
	shot_serial += 1
	_sfx("launch")

func can_walk() -> bool:
	return sim.grounded and not sim.attached and not bolt_active

func ground_ahead(direction: float, distance: float = EDGE_PROBE) -> bool:
	# A short downward sweep just past the body centre in the walking direction.
	var probe := sim.pos+Vector2(direction*distance,.04)
	return bool(world.move_player(probe,probe+Vector2(0,-.5),Vector2(0,-1))["grounded"])

func edge_room(direction: float) -> float:
	# Free walking distance before the hero reaches the stopping point at the
	# edge, capped by the look-ahead. Walking speed follows this distance so the
	# hero brakes into the edge instead of stopping dead on it.
	var room := 0.0
	while room<walk_edge_lookahead:
		if not ground_ahead(direction,EDGE_PROBE+room+EDGE_PROBE_STEP):
			# Bisect the last interval so the braking curve is continuous.
			var low := room
			var high := room+EDGE_PROBE_STEP
			for iteration in range(4):
				var middle := (low+high)*.5
				if ground_ahead(direction,EDGE_PROBE+middle): low = middle
				else: high = middle
			return low
		room += EDGE_PROBE_STEP
	return walk_edge_lookahead

func walk_velocity(current: float, input: float, step: float) -> float:
	# Platform walking: eased start, quicker turn, braking stop. Landing momentum
	# above walking speed keeps the original, softer slide.
	var target := input*WALK_SPEED
	if input!=0:
		if not ground_ahead(signf(input)):
			# Safety net for steps and odd contours: never walk off a support.
			if current*input>0 and absf(current)<=WALK_SPEED+.05: return 0.0
			target = 0.0
		else:
			target = signf(input)*minf(absf(target),sqrt(2*walk_edge_braking*edge_room(signf(input))))
	var rate := landing_friction
	if absf(current)<=WALK_SPEED+.05 or input!=0:
		if target==0.0: rate = walk_deceleration if absf(current)<=WALK_SPEED+.05 else landing_friction
		elif current*target<0: rate = walk_turn_acceleration
		elif absf(target)<absf(current): rate = maxf(walk_deceleration,walk_edge_braking*2)
		else: rate = walk_acceleration
	return move_toward(current,target,step*rate)

# The share of the hero's motion a throw inherits ("steady" throw keeps less).
func throw_carry_velocity() -> Vector2:
	return sim.vel

func direction_to_target(target: Vector2) -> Vector2:
	return HookFlight.aim_solution(sim.pos,target,model.throw_speed(),throw_carry_velocity())["direction"]

func _shot_forecast_hero() -> RopeSim:
	var forecast := RopeSim.new()
	forecast.pos = sim.pos
	forecast.vel = sim.vel
	forecast.gravity = sim.gravity
	forecast.fall_speed_limit = sim.fall_speed_limit
	forecast.grounded = sim.grounded
	return forecast

func _advance_forecast(forecast: RopeSim, dt: float) -> void:
	var previous := forecast.pos
	if forecast.grounded: forecast.vel.x = move_toward(forecast.vel.x,0,dt*7)
	forecast.tick(dt,0,0)
	var motion := world.move_player(previous,forecast.pos,forecast.vel)
	forecast.pos = motion["position"]
	forecast.vel = motion["velocity"]
	forecast.grounded = motion["grounded"]

func predict_shot(direction: Vector2) -> Dictionary:
	var branches: Array[Dictionary] = []
	var selected := 0
	var first_contact := INF
	for shot_direction in model.hook_directions(direction):
		var branch := _predict_single_shot(shot_direction)
		branches.append(branch)
		if branch["reachable"] and not branch["collision"].is_empty() and not branch["collision"].get("blocked",false) and float(branch["time"])<first_contact:
			selected = branches.size()-1
			first_contact = float(branch["time"])
	var result := branches[selected].duplicate()
	result["branches"] = branches
	return result

func _predict_single_shot(direction: Vector2) -> Dictionary:
	var flight := HookFlight.new()
	flight.launch(sim.pos,direction,model.throw_speed(),throw_carry_velocity())
	var forecast := _shot_forecast_hero()
	var points := PackedVector2Array([sim.pos])
	var result := {"points":points,"contact":sim.pos,"time":0.0,"collision":{},"reachable":true}
	for index in range(240):
		var previous := flight.position
		_advance_forecast(forecast,HookFlight.STEP)
		flight.advance(HookFlight.STEP)
		var fraction := HookFlight.range_fraction(previous,flight.position,forecast.pos,model.shot_range())
		var end := previous.lerp(flight.position,fraction)
		var collision := world.cast_hook(previous,end,model.hook_radius())
		if not collision.is_empty(): end = collision["contact"]
		points.append(end)
		result["contact"] = end
		result["time"] = flight.age
		if not collision.is_empty():
			result["collision"] = collision
			result["reachable"] = not world.rope_blocked(forecast.pos,end)
			break
		if fraction<1:
			result["reachable"] = false
			break
	return result

func shot_window_open(contact: Vector2) -> bool:
	var solution := HookFlight.aim_solution(sim.pos,contact,model.throw_speed(),throw_carry_velocity())
	var flight := HookFlight.new()
	flight.launch(sim.pos,solution["direction"],model.throw_speed(),throw_carry_velocity())
	var forecast := _shot_forecast_hero()
	while flight.age<float(solution["time"])-.00001:
		var dt := minf(HookFlight.STEP,float(solution["time"])-flight.age)
		_advance_forecast(forecast,dt)
		flight.advance(dt)
		if flight.position.distance_to(forecast.pos)>model.shot_range()+.001: return false
	return true

func _position_camera() -> void:
	var view_y := camera_y-camera_dip+camera_view_offset
	camera.size = camera_base_size/maxf(1.0,camera_zoom_current)
	camera.position = Vector3(camera_x,view_y,28)
	camera.look_at(Vector3(camera_x,view_y,0))

func camera_zoom_target() -> float:
	if state=="menu" or (preview and capture_screen in ["equipment","terrain"]): return 1.0
	var punch := lerpf(1.0,maxf(1.0,float(model.camera_setting("slowmo_zoom",1.0))),focus_blend)
	return clampf(model.camera_zoom()*punch,1.0,1.6)

func zoom_view_offset() -> float:
	# Vertical shift of the zoomed window inside the gameplay framing: keep as
	# much of the climb above the hero as possible, but never let the hero (or
	# the ground under them) leave the bottom of the picture.
	var visual := camera_base_size/maxf(1.0,camera_zoom_current)
	var slack := maxf(0,(camera_base_size-visual)*.5)
	if slack<=.0001: return 0.0
	var center := camera_y-camera_dip
	var margin := clampf(float(model.camera_setting("zoomed_floor_margin",2.6)),.5,visual*.45)
	var hero_floor := sim.pos.y-margin+visual*.5
	return clampf(hero_floor-center,-slack,slack)

func set_camera_zoom(zoom: float) -> void:
	model.profile["camera_zoom"] = model.snap_camera_zoom(zoom)
	request_profile_save()

func request_profile_save() -> void:
	if model==null or model.save_blocked:
		return
	profile_save_pending = true
	profile_save_timer = PROFILE_SAVE_DEBOUNCE

func flush_profile_save() -> bool:
	if not profile_save_pending:
		return true
	profile_save_pending = false
	profile_save_timer = 0.0
	return model.save()

func screen_bottom_y() -> float:
	# The danger edge follows the undipped, unzoomed framing: lowering the view
	# after a landing or zooming in never moves the rescue margin.
	return camera_y-camera_base_size*.5

func below_screen() -> bool:
	return sim.pos.y+float(model.balance["fall_screen_margin_units"])<screen_bottom_y()

func release_hook(keep_primary: bool = false, reason: String = "manual") -> void:
	if not sim.attached:
		return
	var factor := model.impulse_factor()
	var point := world.anchor_by_id(anchor_id)
	# The type's effect belongs to the attached -> acted transition, so it is
	# applied once per catch: a spring adds its exit impulse, ice hands over
	# the slide, other types keep the swing velocity exactly. Only the player's
	# own release and the slip off a plate carry it: a knock or a blocked rope
	# grants no effect.
	var thrown := false
	if GripSpec.act(point) and reason in ["manual","ice_slip"]:
		sim.vel = GripSpec.release_velocity(point,sim.vel,anchor_slide_velocity)
		thrown = GripSpec.kind_of(point)==GripSpec.SPRING
	anchor_slide_velocity = Vector2.ZERO
	world.release_anchor_load(anchor_id)
	if thrown: world.spring_burst(anchor_id,sim.pos)
	last_anchor_id = anchor_id
	world.consume_anchor(anchor_id)
	if anchor_id==safe_anchor_id and not point.get("permanent",true):
		safe_anchor_id = -1
		safe_position = Vector2(0,START_Y)
	sim.release(factor)
	if hook_volley!=null:
		for shot in hook_volley.shots:
			if shot["state"]=="attached": shot["state"] = "idle"
	anchor_id = -1
	# Release focus is real-time and does not depend on the input still being held.
	_start_focus()
	last_release_reason = reason
	if reason!="manual":
		print("HOOK_RELEASE reason=%s keep_primary=%s position=%s" % [reason,keep_primary,sim.pos])
	if thrown:
		_sfx("spring")
		_haptic("spring")
	else: _sfx("release")
	if keep_primary:
		_recenter_climb_control(true)
		_refresh_aim()
	else:
		_reset_input()

# Boots on rock: a landing by how hard it was, steps in time with the walk.
func _ground_sounds(was_grounded: bool, fall_speed: float, step: float) -> void:
	if sim.grounded and not was_grounded:
		if fall_speed>=LAND_SOUND_SPEED:
			_sfx("land")
			sounds.reset_streaks()
		if fall_speed>=LAND_HAPTIC_SPEED: _haptic("land")
		walk_step_clock = 0.0
	elif sim.grounded and not sim.attached and absf(sim.vel.x)>WALK_SPEED*.5:
		walk_step_clock += step
		if walk_step_clock>=WALK_STEP_SECONDS:
			walk_step_clock = 0.0
			_sfx("step")

func _start_focus() -> void:
	# A release inside the cooldown keeps full speed; nothing can refill or
	# extend a running window.
	if focus_cooldown>0.0 or focus_remaining>0.0 or model.slowmo_seconds()<=0.0: return
	focus_duration = model.slowmo_seconds()
	focus_remaining = focus_duration
	focus_serial += 1
	_sfx("focus_in")
	_haptic("focus")

func _end_focus() -> void:
	if focus_remaining<=0.0: return
	focus_remaining = 0.0
	focus_cooldown = model.slowmo_cooldown()
	_sfx("focus_out")

func focus_active() -> bool:
	return focus_remaining>0.0 and not sim.attached

# Smoothed 0..1 presence of slow motion for visuals (tint, camera, animation).
func focus_visual() -> float:
	return focus_blend

func _physics_process(delta: float) -> void:
	if state!="play" or preview:
		return
	run_seconds += delta
	_update_touch_controls()
	_refresh_aim()
	var step := delta
	# Both timers use the unscaled physics delta: slow motion never slows its
	# own countdown or its cooldown.
	if focus_remaining<=0.0: focus_cooldown = maxf(0,focus_cooldown-delta)
	if not sim.attached and focus_remaining>0:
		step *= model.slowmo_time_scale()
		if focus_remaining<=delta: _end_focus()
		else: focus_remaining -= delta
	_update_item_effect(delta)
	var keyboard_pump := Input.get_axis("swing_left","swing_right")
	var keyboard_reel := Input.get_axis("rope_down","rope_up")
	var previous := sim.pos
	var previous_length := sim.length
	var previous_highest := sim.highest
	var previous_peak := sim.flight_peak
	if sim.attached:
		anchor_time += step
		var point := world.anchor_by_id(anchor_id)
		if not point.is_empty():
			# The held grip is always `attached`, including grips set by hand.
			if GripSpec.state(point)=="available": GripSpec.attach(point)
			if GripSpec.expired(point,anchor_time):
				world.break_anchor(anchor_id)
				release_hook(true,"root_break")
				toast("Корень сломался — успей зацепиться!",2.5,"release")
			elif GripSpec.kind_of(point)==GripSpec.ICE:
				# Ice slips the hook along its surface but never past the stone.
				var before_slide := sim.anchor
				sim.anchor = world.anchor_contact_after(point,anchor_contact,anchor_time)
				anchor_slide_velocity = (sim.anchor-before_slide)/step if step>0 else Vector2.ZERO
				if anchor_time>=GripSpec.ICE_GRACE: world.ice_scrape(sim.anchor,delta)
				if GripSpec.slipped(point,anchor_contact,anchor_time):
					release_hook(true,"ice_slip")
					_sfx("ice")
					toast("Крюк сорвался со льда — цепляйся!",2.0,"release")
	# Act hazards push an airborne hero, knock it off a grip or drop a bridge.
	hazard_cooldown = maxf(0,hazard_cooldown-delta)
	hazard_clock += step
	var hazard_effect := world.step_hazards(hazard_clock,sim.pos,sim.grounded,anchor_id if sim.attached else -1,last_anchor_id)
	sim.vel += (hazard_effect["force"] as Vector2)*step
	if not hazard_effect["knock"].is_empty() and hazard_cooldown<=0: _hazard_knock(hazard_effect["knock"])
	if not sim.attached and not sim.grounded: _apply_item_effect(step)
	var was_grounded := sim.grounded
	if was_grounded and not sim.attached:
		var walk_input := clampf(walk+(keyboard_pump if not pressed or not touch_gesture else 0.0),-1,1) if can_walk() else 0.0
		# The hero stops at the edge of the support instead of stepping off;
		# leaving a platform takes a hook. Landing momentum still slides.
		sim.vel.x = walk_velocity(sim.vel.x,walk_input,step)
	sim.grounded = false
	sim.tick(step,clampf(pump+keyboard_pump,-1,1),clampf(reel+keyboard_reel,-1,1))
	if sim.attached:
		if absf(pump+keyboard_pump)>.15 and absf(sim.vel.x)>1.5:
			model.learn_control("swing")
		if absf(sim.length-previous_length)>.0001:
			model.learn_control("rope")
	if item_running("glide") and not sim.attached: sim.vel.y = maxf(sim.vel.y,-float(ItemCatalog.consumable("glide")["fall_speed"]))
	var fall_speed := -sim.vel.y
	var motion := world.move_player(previous,sim.pos,sim.vel)
	sim.pos = motion["position"]
	sim.vel = motion["velocity"]
	sim.grounded = motion["grounded"]
	_ground_sounds(was_grounded,fall_speed,step)
	# Landing ends the aiming window: walking never runs in slow motion.
	if sim.grounded and not was_grounded and focus_remaining>0: _end_focus()
	if sim.grounded and motion["rest"] and not sim.attached:
		safe_position = sim.pos
		safe_anchor_id = -1
	if not (world.layout is LegacyMountainLayout) and sim.attached:
		if world.generation_version>=10:
			if not world.update_rope_path(sim):
				release_hook(true,"rope_path")
				toast("Не хватает каната для обхода выступа",1.5)
			else:
				# A rope correction is itself swept so it cannot pull the body
				# through a wall after resolving the ordinary movement.
				var before_constraint := sim.pos
				sim.constrain_rope()
				var correction := world.move_player(before_constraint,sim.pos,sim.vel)
				sim.pos = correction["position"]
				sim.vel = correction["velocity"]
				if sim.path_distance()>sim.length+.12:
					release_hook(true,"rope_pinned")
					toast("Канат зажат между выступами",1.5)
		elif world.rope_blocked(sim.pos,sim.anchor):
			release_hook(true,"rope_blocked")
			toast("Канат упёрся в выступ")
	if below_screen():
		fail_run("Упал ниже экрана")
		return
	if hook_volley!=null:
		_update_volley(step)
	elif bolt_active:
		_update_bolt(step)
	elif bolt_returning:
		_update_return(step)
	sim.highest = maxf(previous_highest,sim.pos.y)
	sim.flight_peak = maxf(previous_peak,sim.pos.y)
	_track_act()
	_collect_finds()
	if state!="play":
		return
	# Every route keeps its own record per mode (see GameModel.record).
	model.note_record(selected_location if run_mode!="practice" else 0,run_mode,maxf(0,sim.highest-START_Y)*10)
	if run_mode=="practice":
		model.profile["best"] = maxf(float(model.profile["best"]),maxf(0,sim.highest-START_Y)*10)
	else:
		var bank_before := int(model.profile["gold"])
		var diamonds_before := int(model.profile["diamonds"])
		var opened := model.reach(maxf(0,sim.highest-START_Y))
		zone_gold += int(model.profile["gold"])-bank_before
		zone_diamonds += int(model.profile["diamonds"])-diamonds_before
		if not opened.is_empty():
			var zone_reward := int(model.profile["gold"])-bank_before
			var unlock := "Ступень %d · +%d золота" % [opened[-1]+1,zone_reward] if opened[-1]>=2 else "+%d золота за новую зону" % zone_reward
			toast("%s · %s\n%s" % [GameModel.ZONE_NAMES[opened[-1]],GameModel.ZONE_HINTS[opened[-1]],unlock],3)
			save_snapshot()
	var summit_landed := world.layout.summit_added and sim.grounded and sim.pos.y-SolidGeometry.BODY_HALF.y>=summit_height-.45
	if run_mode in ["summit","practice"] and (sim.pos.y-START_Y>=summit_height-.02 or summit_landed):
		sim.highest = maxf(sim.highest,summit_height+START_Y)
		finish_run(true)
	# Keep a playable buffer ahead of the camera. Finite runs used to build the
	# whole summit synchronously before the first frame; extend the same streamed
	# path to finite runs to remove that startup hitch.
	elif sim.pos.y+35>world.generated_height and not world.layout.summit_added:
		if run_mode=="endless":
			world.generate_to(world.generated_height+40,false,summit_height)
		else:
			world.generate_to(minf(summit_height+6,world.generated_height+40),true,summit_height)

func _hazard_knock(knock: Dictionary) -> void:
	# The ordinary release path: a spring or ice effect is not granted, the
	# grip settles as on any release.
	hazard_cooldown = 1.2
	_sfx("knock")
	_haptic("knock")
	if sim.attached: release_hook(false,"hazard")
	sim.vel += knock["push"]
	toast(world.hazards.knock_message(int(knock["hazard"])),1.8,"hazard")

func _track_act() -> void:
	var act := world.act_at(sim.pos.y)
	if act.is_empty(): return
	var index := int(act["index"])
	if index==current_act: return
	var announce := current_act>=0 and index>current_act
	current_act = index
	# Entering an act opens the next workshop gate.
	if run_mode!="practice" and model.reach_act(int(act["local"])+1): save_snapshot()
	if announce and run_mode!="practice":
		print("ACT_ENTER location=%d act=%s index=%d" % [world.location,act["id"],index])
		toast("Акт %d · %s
%s" % [int(act["local"])+1,act["display_name"],act["intro_rule"]],3.2,"act")

# Compact run state for logs, captures and tests.
func debug_state() -> Dictionary:
	var result := world.debug_state(sim.pos,hazard_clock)
	result.merge({"state":state,"mode":run_mode,"seed":run_seed,"height":sim.pos.y,"attached":sim.attached,"anchor":anchor_id})
	return result

func _update_bolt(step: float) -> void:
	if hook_volley!=null:
		_update_volley(step)
		return
	# Substeps sweep every piece of the arc, including at low frame rates.
	var remaining := step
	while remaining>.00001 and bolt_active:
		var dt := minf(remaining,HookFlight.STEP)
		remaining -= dt
		var previous := bolt_pos
		hook_flight.advance(dt)
		var fraction := HookFlight.range_fraction(previous,hook_flight.position,sim.pos,model.shot_range())
		bolt_pos = previous.lerp(hook_flight.position,fraction)
		bolt_travel += previous.distance_to(bolt_pos)
		bolt_direction = hook_flight.velocity.normalized()
		var collision := world.cast_hook(previous,bolt_pos,model.hook_radius())
		if not collision.is_empty():
			bolt_pos = collision["contact"]
			hook_flight.position = bolt_pos
			hook_flight.trail[-1] = bolt_pos
			if bool(collision.get("blocked",false)):
				var normal: Vector2 = collision.get("normal",Vector2.DOWN)
				_begin_hook_return("Выстрел перекрыт выступом",hook_flight.velocity.bounce(normal)*.22,"rock")
				return
			var hit: Dictionary = collision["object"]
			var contact: Vector2 = collision["contact"]
			# Same rule as the volley: a hero already on a rope takes no second catch.
			if sim.attached:
				bolt_active = false
				bolt_returning = true
				return_velocity = Vector2.ZERO
				return
			if sim.pos.distance_to(contact)>model.shot_range()+.001:
				_begin_hook_return("Не хватает длины каната")
				return
			if world.rope_blocked(sim.pos,contact):
				_begin_hook_return("Выступ перекрывает канат до опоры",Vector2.ZERO,"rock")
				return
			_catch_contact(hit,contact)
			return
		if fraction<1 or hook_flight.age>2.0:
			hook_flight.position = bolt_pos
			hook_flight.trail[-1] = bolt_pos
			# Reaching the range limit is a normal miss. The returning head and
			# sound already communicate it; a toast here covers the aim area and
			# makes a routine miss look like a failure.
			_begin_hook_return()

func _catch_contact(hit: Dictionary, contact: Vector2) -> void:
	bolt_active = false
	bolt_returning = false
	anchor_contact = contact
	sim.attach(contact,model.rope_length(),true)
	model.learn_control("aim")
	catches += 1
	anchor_id = hit["id"]
	anchor_time = 0
	anchor_slide_velocity = Vector2.ZERO
	GripSpec.attach(hit)
	_end_focus()
	if hint_context=="release": hint_timer = 0
	if pressed: _recenter_climb_control()
	if GripSpec.network_safe_point(hit) and (world.generation_version<9 or hit.get("primary",false)):
		safe_anchor_id = anchor_id
		safe_position = sim.pos
		safe_contact = contact
	_register_hook_impact(contact,"catch")
	if _sound_on(): sounds.play_catch()

func _sync_volley() -> void:
	if hook_volley==null: return
	bolt_active = hook_volley.has_state("flying")
	bolt_returning = hook_volley.has_state("returning")
	if not sim.attached and hook_volley.shots[volley_primary]["state"] not in ["flying","returning"]:
		for index in range(hook_volley.shots.size()):
			if hook_volley.shots[index]["state"] in ["flying","returning"]:
				volley_primary = index
				break
	var shot: Dictionary = hook_volley.shots[volley_primary]
	hook_flight = shot["flight"]
	bolt_pos = hook_flight.position
	bolt_direction = hook_flight.velocity.normalized()
	return_velocity = shot["return_velocity"]

func _update_volley(step: float) -> void:
	var remaining := step
	while remaining>.00001:
		var dt := minf(remaining,HookFlight.STEP)
		remaining -= dt
		var events := hook_volley.advance(dt,sim.pos,world,model.shot_range(),model.hook_radius())
		for event in events:
			var index: int = event["index"]
			if hook_volley.shots[index]["state"]!="contact": continue
			var collision: Dictionary = event["collision"]
			var contact: Vector2 = collision["contact"]
			var flight: HookFlight = hook_volley.shots[index]["flight"]
			if collision.get("blocked",false):
				hook_volley.return_shot(index,flight.velocity.bounce(collision.get("normal",Vector2.DOWN))*.22)
				_register_hook_impact(contact,"rock")
				_sfx("rock")
				continue
			if sim.attached or sim.pos.distance_to(contact)>model.shot_range()+.001 or world.rope_blocked(sim.pos,contact):
				hook_volley.return_shot(index)
				continue
			volley_primary = index
			hook_volley.catch_shot(index,int(collision["object"]["id"]),contact)
			_catch_contact(collision["object"],contact)
			# First valid contact wins. The other line winds back without ever
			# catching, pulling, consuming an anchor, or awarding another catch.
			for other in range(hook_volley.shots.size()):
				if other!=index and hook_volley.shots[other]["state"] in ["flying","contact"]:
					hook_volley.return_shot(other)
		_sync_volley()
	if not bolt_active and not bolt_returning:
		# Once the losing line reaches the hand, keep the ordinary single rope
		# renderer for an attached catch and discard the volley state.
		hook_volley = null

func _register_hook_impact(point: Vector2, kind: String) -> void:
	impact_serial += 1
	hook_impact = point
	hook_impact_kind = kind
	if kind in ["catch","rock"]: _haptic(kind)

func _begin_hook_return(message: String = "", rebound := Vector2.ZERO, kind := "limit") -> void:
	bolt_active = false
	bolt_returning = true
	return_velocity = rebound
	_register_hook_impact(bolt_pos,kind)
	_sfx("rock" if kind=="rock" else "return")
	if not message.is_empty(): toast(message,1.3,"hook")

func _update_return(dt: float) -> void:
	if hook_volley!=null:
		_update_volley(dt)
		return
	# Recovery is quick and can be interrupted by the next throw. It never
	# catches anchors or pulls the player while winding back into the hand.
	var previous := bolt_pos
	var desired := (sim.pos-bolt_pos).normalized()*HookFlight.RETURN_SPEED
	return_velocity = return_velocity.lerp(desired,1-exp(-dt*24))
	var advance := return_velocity*dt
	if bolt_pos.distance_to(sim.pos)<maxf(.3,advance.length()):
		bolt_pos = sim.pos
		bolt_returning = false
	else:
		bolt_pos += advance
	bolt_direction = (bolt_pos-previous).normalized()
	hook_flight.age += dt
	hook_flight.trail.append(bolt_pos)
	if hook_flight.trail.size()>15: hook_flight.trail.remove_at(0)

func _collect_finds() -> void:
	var coin_reach := .54+model.coin_radius()
	var item_reach := .54+model.item_radius()
	var max_reach := maxf(coin_reach,item_reach)
	var priority := model.magnet_priority()
	var candidates: Array[Dictionary] = []
	for find in world.finds:
		if bool(find.get("picked",false)): continue
		if absf(find["pos"].y-sim.pos.y)>max_reach: continue
		var reach := coin_reach if ItemCatalog.is_coin(find["item"]) else item_reach
		if sim.pos.distance_squared_to(find["pos"])>reach*reach: continue
		if world.rope_blocked(sim.pos,find["pos"]): continue
		candidates.append(find)
	# Direct contact is deliberate. Among magnetic finds the chosen family
	# comes first, then value, so an upgraded magnet does not waste the last
	# free slot; the order never depends on the generator's array.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_touch := sim.pos.distance_squared_to(a["pos"])<=.54*.54
		var b_touch := sim.pos.distance_squared_to(b["pos"])<=.54*.54
		if a_touch!=b_touch: return a_touch
		var a_family := str(a["item"].get("family",""))==priority
		var b_family := str(b["item"].get("family",""))==priority
		if a_family!=b_family: return a_family
		if int(a["item"]["value"])!=int(b["item"]["value"]):
			return int(a["item"]["value"])>int(b["item"]["value"])
		var da := sim.pos.distance_squared_to(a["pos"])
		var db := sim.pos.distance_squared_to(b["pos"])
		return int(a["item"]["id"])<int(b["item"]["id"]) if is_equal_approx(da,db) else da<db)
	var banked := false
	for find in candidates:
		var item: Dictionary = find["item"]
		if ItemCatalog.is_coin(item):
			# Coins never enter the bag: they are banked at once, once per id.
			if model.collect_coin(run_id,item):
				_hide_find(find)
				banked = true
				if _sound_on(): sounds.play_coin()
				hud.animate_coin(int(item["value"]),find["pos"])
			elif model.picked.has(int(item["id"])):
				find["picked"] = true
			continue
		if not model.can_fit(item):
			# A full bag is silent: replace the cheapest eligible treasure only
			# when the incoming find is strictly more valuable.
			if _auto_swap_if_better(find):
				save_snapshot()
			continue
		if model.try_pick(item):
			_hide_find(find)
			_sfx("pickup")
			_haptic("pickup")
			hud.refresh_bag()
			hud.animate_pickup(model.bag[-1],find["pos"])
	# Ledger, wallet and picked id go to disk together in the next snapshot,
	# brought forward to COIN_SAVE_DELAY, so a run of coins costs one write.
	# Until then all three live only in memory and roll back together.
	if banked: snapshot_timer = maxf(snapshot_timer,SNAPSHOT_PERIOD-COIN_SAVE_DELAY)
	_update_swap_offer()

func _hide_find(find: Dictionary) -> void:
	world.collect_find(find)
	find["picked"] = true
	if is_instance_valid(find.get("visual")): find["visual"].visible = false

# Full bag handling is automatic. The cheapest eligible slot is replaced only
# when the incoming treasure is strictly more valuable.
func _auto_swap_if_better(find: Dictionary) -> bool:
	var item: Dictionary = find["item"]
	var index := model.cheapest_index(item)
	if index<0 or int(item.get("value",0))<=int(model.bag[index].get("value",0)):
		return false
	if not model.swap_in(item,index):
		return false
	_hide_find(find)
	_sfx("pickup")
	_haptic("pickup")
	hud.refresh_bag()
	hud.animate_pickup(model.bag[-1],find["pos"])
	return true

func _offer_swap(find: Dictionary) -> void:
	_auto_swap_if_better(find)

func _swap_in_reach() -> bool:
	if swap_offer.is_empty(): return false
	var find: Dictionary = swap_offer["find"]
	return not bool(find.get("picked",false)) and sim.pos.distance_to(find["pos"])<=.54+model.item_radius()+1.5 and not world.rope_blocked(sim.pos,find["pos"])

func _update_swap_offer() -> void:
	if not swap_offer.is_empty() and (state!="play" or not _swap_in_reach()): close_swap(false)

func accept_swap() -> void:
	if not _swap_in_reach():
		close_swap(false)
		return
	var find: Dictionary = swap_offer["find"]
	var index := model.cheapest_index(find["item"])
	if index>=0 and model.swap_in(find["item"],index):
		_hide_find(find)
		_sfx("pickup")
		_haptic("pickup")
		hud.refresh_bag()
		hud.animate_pickup(model.bag[-1],find["pos"])
		save_snapshot()
	close_swap(false)

func close_swap(declined: bool = true) -> void:
	if declined and not swap_offer.is_empty(): swap_declined.append(int(swap_offer["find"]["item"]["id"]))
	swap_offer = {}
	if is_instance_valid(hud): hud.hide_swap()

# --- Active items ---------------------------------------------------------------------

func spent_item_ids() -> Array:
	var result: Array = []
	for entry in run_items:
		if bool(entry["used"]): result.append(str(entry["id"]))
	return result

# Valid exits for the beacon and the booster: grips not spent, in rope reach,
# with a free line, not lower than the hero by more than half a metre.
func reachable_exits(limit: int = 2) -> Array[Vector2]:
	var found: Array[Dictionary] = []
	for point in world.nearby_anchors(sim.pos.y-1,sim.pos.y+model.shot_range()+1):
		if point.get("broken",false) or point.get("hidden",false) or int(point["id"])==anchor_id: continue
		if GripSpec.state(point)!="available": continue
		var at: Vector2 = point["pos"]
		if at.y<sim.pos.y-.5 or at.distance_to(sim.pos)>model.shot_range(): continue
		if world.rope_blocked(sim.pos,at): continue
		found.append(point)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_main := bool(a.get("primary",false))
		var b_main := bool(b.get("primary",false))
		if a_main!=b_main: return a_main
		return sim.pos.distance_squared_to(a["pos"])<sim.pos.distance_squared_to(b["pos"]))
	var result: Array[Vector2] = []
	for point in found.slice(0,limit): result.append(point["pos"])
	return result

# Glide and the booster can be tapped at any moment: on the rope or the ground
# they wait (armed, nothing spent) and fire as soon as the hero is airborne.
const ARMABLE := ["glide","booster"]

func item_blocked_reason(id: String) -> String:
	match id:
		"tape": return "Лента срабатывает сама при срыве"
		"beacon":
			if reachable_exits().is_empty(): return "Рядом нет доступных выходов"
	return ""

func airborne() -> bool:
	return not sim.attached and not sim.grounded

# The booster pushes along the current flight; it needs some motion to follow.
func _item_can_fire(id: String) -> bool:
	if id in ARMABLE and not airborne(): return false
	if id=="booster" and sim.vel.length()<.5: return false
	return true

func item_armed() -> bool:
	return bool(item_effect.get("armed",false))

func item_running(id: String) -> bool:
	return item_effect_id()==id and not item_armed()

func activate_item(index: int) -> void:
	if state!="play" or index<0 or index>=run_items.size(): return
	var entry: Dictionary = run_items[index]
	var id := str(entry["id"])
	var definition := ItemCatalog.consumable(id)
	if bool(entry["used"]):
		toast(str(definition["name"])+" уже использован",1.6,"item")
		return
	if item_armed() and int(item_effect.get("index",-1))==index:
		# A second tap takes back a waiting item.
		item_effect = {}
		toast(str(definition["name"])+": отменено",1.2,"item")
		return
	if not item_effect.is_empty():
		toast(("Уже ждёт полёта: " if item_armed() else "Дождись окончания: ")+str(ItemCatalog.consumable(item_effect_id())["name"]),1.6,"item")
		return
	var reason := item_blocked_reason(id)
	if not reason.is_empty():
		toast(reason,1.6,"item")
		return
	var duration := maxf(.01,float(definition["duration"]))
	if id in ARMABLE and not _item_can_fire(id):
		item_effect = {"id":id,"remaining":duration,"duration":duration,"armed":true,"index":index}
		_sfx("item_arm")
		toast(str(definition["name"])+": сработает в полёте",1.4,"item")
		save_snapshot()
		return
	_fire_item(index)

func _fire_item(index: int) -> void:
	var entry: Dictionary = run_items[index]
	var definition := ItemCatalog.consumable(str(entry["id"]))
	if not model.spend_item(run_items,index):
		item_effect = {}
		return
	item_effect = {"id":str(entry["id"]),"remaining":float(definition["duration"]),"duration":maxf(.01,float(definition["duration"]))}
	if entry["id"]=="beacon": beacon_targets = reachable_exits()
	print("ITEM_BEGIN id=%s position=%s" % [entry["id"],sim.pos])
	_sfx("item_fire")
	_haptic("item")
	toast(str(definition["name"]),1.2,"item")
	save_snapshot()

func _end_item_effect() -> void:
	if item_effect.is_empty(): return
	print("ITEM_END id=%s" % item_effect["id"])
	item_effect = {}
	beacon_targets.clear()

func item_effect_id() -> String:
	return str(item_effect.get("id",""))

# Begin/active/end: the effect counts down in real time and ends early once
# it no longer applies (a catch or a landing ends glide and booster). An
# armed item only waits for flight.
func _update_item_effect(delta: float) -> void:
	_auto_glide()
	if item_effect.is_empty(): return
	if item_armed():
		if _item_can_fire(item_effect_id()): _fire_item(int(item_effect.get("index",-1)))
		return
	if item_effect_id() in ARMABLE and (sim.attached or sim.grounded):
		_end_item_effect()
		return
	item_effect["remaining"] = float(item_effect["remaining"])-delta
	if float(item_effect["remaining"])<=0: _end_item_effect()

func _apply_item_effect(step: float) -> void:
	if item_armed(): return
	match item_effect_id():
		"glide":
			# Slower descent only: rope, bottom edge and fail rules are untouched.
			sim.vel.y = maxf(sim.vel.y,-float(ItemCatalog.consumable("glide")["fall_speed"]))
		"booster":
			var definition := ItemCatalog.consumable("booster")
			if sim.vel.length()>.1 and sim.vel.length()<float(definition["max_speed"]):
				sim.vel = (sim.vel+sim.vel.normalized()*float(definition["acceleration"])*step).limit_length(float(definition["max_speed"]))

# A carried parachute that was not tapped opens by itself on a fall that is
# about to cross the lower edge, so a bought item always does its job.
func _auto_glide() -> void:
	if not item_effect.is_empty() or not airborne() or sim.vel.y>-7.0: return
	if sim.pos.y-screen_bottom_y()>5.0: return
	for index in range(run_items.size()):
		if run_items[index]["id"]=="glide" and not bool(run_items[index]["used"]):
			_fire_item(index)
			toast("Парашют раскрылся сам",1.4,"item")
			return

# Safety strap: the first fatal fall returns to the last safe point and the
# last find falls out of the bag. It needs the same valid way back as a
# continuation and never counts as one.
func _tape_rescue() -> bool:
	if run_mode=="practice": return false
	var index := -1
	for slot in range(run_items.size()):
		if run_items[slot]["id"]=="tape" and not run_items[slot]["used"]: index = slot
	if index<0: return false
	var plan := world.revive_plan(safe_anchor_id,safe_position,model.shot_range(),safe_contact)
	if not plan.get("available",false) or not model.spend_item(run_items,index): return false
	var lost := ""
	for slot in range(model.bag.size()-1,-1,-1):
		if str(model.bag[slot].get("family",""))!="contract":
			lost = ItemCatalog.name_of(model.bag[slot])
			model.bag.remove_at(slot)
			break
	print("ITEM_BEGIN id=tape position=%s" % sim.pos)
	_return_to_safety(plan)
	hud.refresh_bag()
	toast("Страховочная лента: назад к опоре"+(" · выпало: "+lost if not lost.is_empty() else ""),3,"item")
	save_snapshot()
	return true

func fail_run(reason: String) -> void:
	if state!="play":
		return
	if sim.attached: release_hook(false,"fall")
	_end_item_effect()
	close_swap(false)
	# A start-of-run controls toast must never cover the revive/result modal.
	if hint_context=="controls":
		hint = ""
		hint_context = ""
		hint_timer = 0.0
	if _tape_rescue(): return
	var offer_revive := not revive_used and run_mode!="practice" and revive_available()
	state = "revive" if offer_revive else "result"
	failure_reason = reason
	_reset_input()
	bolt_active = false
	bolt_returning = false
	hook_volley = null
	volley_primary = 0
	sounds.reset_streaks()
	_sfx("fail")
	_haptic("fail")
	if offer_revive:
		save_snapshot()
		hud.show_revive(reason)
	else:
		finish_run(false)

func revive_available() -> bool:
	return bool(world.revive_plan(safe_anchor_id,safe_position,model.shot_range(),safe_contact).get("available",false))

func revive(currency: String) -> void:
	if state!="revive" or revive_used or ads.fullscreen:
		return
	var plan := world.revive_plan(safe_anchor_id,safe_position,model.shot_range(),safe_contact)
	if not plan.get("available",false):
		toast("Безопасный выход недоступен · алмазы не потрачены")
		return
	if currency=="diamonds":
		var cost: int = int(model.balance["diamond_revive_cost"])
		if int(model.profile["diamonds"])<cost:
			toast("Не хватает алмазов")
			return
		model.profile["diamonds"] -= cost
	elif currency=="test_ad":
		# No simulated ad impression/revenue: the UI labels this as a developer test.
		if not OS.is_debug_build() or ads.supported:
			toast("Рекламный сервис ещё не подключён")
			return
	elif currency=="ad":
		if not ad_revive_authorized: return
		ad_revive_authorized = false
		ad_revive_pending = false
	else:
		return
	revive_used = true
	_return_to_safety(plan)
	toast("Продолжение использовано · следующая ошибка завершит попытку")
	save_snapshot()

# Shared by the continuation and the safety strap: dormant rescue grips
# wake up and the hero returns to the last safe point.
func _return_to_safety(plan: Dictionary) -> void:
	world.activate_rescue_anchors(plan["anchors"])
	# A shot thrown before the fall ends here, like on any other rescue.
	_reset_input()
	bolt_active = false
	bolt_returning = false
	hook_volley = null
	volley_primary = 0
	focus_remaining = 0.0
	focus_cooldown = 0.0
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
			sim.attach(safe_contact,model.rope_length())
			anchor_id = safe_anchor_id
			GripSpec.attach(point)
	anchor_time = 0
	state = "play"
	sim.flight_peak = sim.pos.y
	camera_y = maxf(4.8,sim.pos.y+2.5)
	camera_x = sim.pos.x
	camera_dip = 0.0
	_position_camera()
	hud.show_play()
	_end_item_effect()

func request_ad_revive() -> void:
	if state!="revive" or revive_used or not revive_available() or ads.fullscreen: return
	ad_revive_run_id = run_id
	save_snapshot()
	if not ads.request_rewarded():
		ad_revive_run_id = ""
		toast("Реклама пока недоступна. Попробуй позже.")
		_refresh_ad_actions()

func _on_ad_revive_finished(earned: bool) -> void:
	var same_run := not ad_revive_run_id.is_empty() and ad_revive_run_id==run_id
	ad_revive_run_id = ""
	if earned and same_run and state=="revive" and not revive_used:
		ad_revive_authorized = true
		revive("ad")
		ad_revive_authorized = false
	elif state=="revive":
		ad_revive_pending = false
		save_snapshot()
		toast("Возрождение не получено. Рекламу нужно досмотреть.")
		_refresh_ad_actions()

func _on_ad_reward_verified() -> void:
	if state=="revive" and ad_revive_run_id==run_id and not revive_used:
		ad_revive_pending = true
		save_snapshot()

func _refresh_ad_actions() -> void:
	if is_instance_valid(hud) and state=="revive" and not ads.fullscreen:
		hud.show_revive(hud.revive_reason)

func _on_ad_fullscreen(active: bool) -> void:
	_reset_input()
	if active: sounds.stop_all()
	music.set_suspended(active)
	hud.set_ad_blocked(active)

func finish_run(success: bool) -> void:
	if run_id.is_empty() or ads.fullscreen:
		return
	state = "result"
	if success:
		_sfx("win")
		_haptic("win")
	ads.report_event("run_finished_%s" % ("success" if success else "failed"))
	_reset_input()
	bolt_active = false
	bolt_returning = false
	hook_volley = null
	volley_primary = 0
	if run_mode=="practice":
		model.profile["active"] = {}
		settlement = {"mode":"practice","success":success,"highest":maxi(0,roundi((sim.highest-START_Y)*10)),"seconds":run_seconds,"shots":shots,"catches":catches,"reason":failure_reason}
		hud.show_result(settlement)
		return
	var rewarded_height := maxf(0,sim.highest-START_Y)
	if success:
		rewarded_height = maxf(rewarded_height,summit_height)
	settlement = model.settle(run_id,run_mode,rewarded_height,success,selected_location,{"contract":str(run_contract.get("tag","")),"spent":spent_item_ids()})
	if settlement.get("duplicate",false):
		return
	settlement["seconds"] = run_seconds
	settlement["reason"] = failure_reason
	settlement["shots"] = shots
	settlement["catches"] = catches
	settlement["zone_bonus"] = zone_gold
	settlement["zone_diamonds"] = zone_diamonds
	if not preview:
		model.profile["run_history"].append({"id":run_id,"seed":run_seed,"seconds":snappedf(run_seconds,.1),"height":settlement["highest"],"gold":int(settlement["total"])+zone_gold,"zone_bonus":zone_gold,"success":success,"shots":shots,"catches":catches,"reason":failure_reason,"levels":model.profile["upgrade_levels"].duplicate(),"choices":model.profile["upgrade_choices"].duplicate()})
		model.profile["run_history"][-1].merge({"build":GameModel.build_version(),"mode":run_mode,"location":selected_location,"height_gold":settlement["height"],"loot_gold":settlement["loot"],"finish_gold":settlement["finish"],"diamond_reward":settlement["diamonds"],"coin_gold":settlement["coins"],"contract_gold":settlement["contract"],"items_spent":settlement["spent"],"zone_diamonds":zone_diamonds,"first_summit":settlement["first"]})
		model.profile["run_history"] = model.profile["run_history"].slice(-30)
		model.save()
	hud.show_result(settlement)
	if success and run_mode=="summit" and not preview:
		ads.show_level_complete()

func restart_failed_run() -> void:
	# The failure screen can start a fresh attempt directly. Settle the failed
	# ledger first so the old active snapshot is cleared without requiring the
	# player to visit the reward screen.
	if state=="revive" and not run_id.is_empty(): finish_run(false)
	if state=="result" or state=="revive": start_run(false)

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
	if ads.fullscreen: return
	hud.menu_tab = "expedition"
	if state=="play" or state=="pause":
		save_snapshot()
	if practice_return_model!=null:
		model = practice_return_model
		practice_return_model = null
		selected_location = int(model.profile.get("selected_location",0))
	state = "menu"
	ads.report_event("menu_opened")
	lobby_location = selected_location
	_reset_input()
	if model.profile["active"].is_empty():
		run_id = ""
		run_mode = "summit"
		# The menu never shows this world; it only needs the route data.
		_create_world(58273,selected_location,36,0,true)
		sim = RopeSim.new()
		sim.pos = Vector2(-.7,8.9)
		sim.anchor = world.anchor_by_id(world.main_route[2])["pos"]
		sim.attached = true
		sim.length = sim.pos.distance_to(sim.anchor)
		camera_y = 7
	camera_dip = 0.0
	hud.show_menu()
	if is_instance_valid(world): world.visible = false
	if is_instance_valid(explorer): explorer.visible = false

func exit_app() -> void:
	if ads.fullscreen: return
	flush_profile_save()
	save_snapshot()
	get_tree().quit()

func go_back() -> void:
	if ads.fullscreen: return
	if hud.exit_confirmation_visible():
		hud.hide_exit_confirmation()
		return
	match state:
		"play": pause_run()
		"pause": unpause()
		"revive": show_menu()
		"result": show_menu()
		"menu":
			if hud.menu_tab!="expedition":
				hud.menu_slide = -1
				hud.menu_focus = "tab"
				hud.select_menu("expedition")
			elif not preview:
				hud.show_exit_confirmation()

func show_workshop() -> void:
	show_menu()
	hud.select_menu("equipment")

func show_locations() -> void:
	show_menu()

func cycle_location(direction: int) -> bool:
	# Routes form a line: the first and last stay put instead of wrapping.
	var next := lobby_location+direction
	if not model.profile["active"].is_empty() or next<0 or next>=model.balance["locations"].size():
		return false
	lobby_location = next
	if model.profile["locations"].has(lobby_location):
		selected_location = lobby_location
		model.profile["selected_location"] = selected_location
		if not preview:
			model.save()
	# The lobby slides its card strip and swaps the route-dependent start
	# action in place; anything else rebuilds the expedition body.
	if not (hud.layout_mode=="menu" and is_instance_valid(hud.lobby_view) and hud.lobby_view.show_location()):
		hud.show_menu()
	if is_instance_valid(world): world.visible = false
	if is_instance_valid(explorer): explorer.visible = false
	return true

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

func finish_saved_run() -> void:
	if ads.fullscreen or model.profile["active"].is_empty():
		return
	# The menu can be shown after a restart, so first reconstruct the saved
	# runtime state before settling it. A stale generator is handled by
	# resume_run() and is settled exactly once there.
	if state=="menu":
		resume_run()
	if state in ["play","revive"] and not run_id.is_empty():
		failure_reason = "Завершено из меню"
		finish_run(false)

func save_snapshot() -> void:
	if preview or run_id.is_empty() or state not in ["play","pause","revive"]:
		return
	var broken: Array = []
	var active_reserves: Array = []
	var pivots: Array = []
	for point in sim.rope_pivots: pivots.append([point.x,point.y])
	for point in world.anchors:
		if point["broken"]:
			broken.append(point["id"])
		elif point.get("reserve",false):
			active_reserves.append(point["id"])
	model.profile["active"] = {"id":run_id,"seed":run_seed,"route":world.route_index,"generation_version":world.generation_version,"mode":run_mode,"location":selected_location,
		"camera_y":camera_y,"camera_x":camera_x,"camera_dip":camera_dip,
		"x":sim.pos.x,"y":sim.pos.y,"vx":sim.vel.x,"vy":sim.vel.y,"length":sim.length,"target_length":sim.target_length,"reel_velocity":sim.reel_velocity,
		"highest":sim.highest,"flight_peak":sim.flight_peak,"launched":sim.launched,"grounded":sim.grounded,
		"run_seconds":run_seconds,"hazard_clock":hazard_clock,"shots":shots,"catches":catches,"failure_reason":failure_reason,"zone_gold":zone_gold,"zone_diamonds":zone_diamonds,
		"anchor_id":anchor_id,"anchor_time":anchor_time,"contact_x":anchor_contact.x,"contact_y":anchor_contact.y,"rope_pivots":pivots,
		"safe_contact_x":safe_contact.x,"safe_contact_y":safe_contact.y,"focus_remaining":focus_remaining,"focus_active":focus_remaining>0.0,"focus_cooldown":focus_cooldown,"focus_duration":focus_duration,"safe_anchor_id":safe_anchor_id,
		"safe_x":safe_position.x,"safe_y":safe_position.y,"revive_used":revive_used,"awaiting_revive":state=="revive","ad_revive_earned":ad_revive_pending,
		"bag":model.bag.duplicate(true),"picked":model.picked.duplicate(),"broken":broken,"active_reserves":active_reserves,"collapsed_hazards":world.hazards.collapsed_ids(),
		"bolt_active":bolt_active,"bolt_x":bolt_pos.x,"bolt_y":bolt_pos.y,"bolt_ox":bolt_origin.x,"bolt_oy":bolt_origin.y,
		"bolt_dx":bolt_direction.x,"bolt_dy":bolt_direction.y,"bolt_travel":bolt_travel,
		"bolt_vx":hook_flight.velocity.x,"bolt_vy":hook_flight.velocity.y,"bolt_age":hook_flight.age,
		"bolt_returning":bolt_returning,"return_vx":return_velocity.x,"return_vy":return_velocity.y}
	model.profile["active"]["hook_volley"] = hook_volley.snapshot() if hook_volley!=null else []
	model.profile["active"]["volley_primary"] = volley_primary
	model.profile["active"]["run_items"] = run_items.duplicate(true)
	model.profile["active"]["item_effect"] = item_effect.duplicate()
	model.save()

func _notification(what: int) -> void:
	if model==null:
		return
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		flush_profile_save()
		save_snapshot()
		get_tree().quit()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()
	elif what==NOTIFICATION_APPLICATION_PAUSED:
		pause_run()
		flush_profile_save()
		save_snapshot()
	elif what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		flush_profile_save()
		if state=="play" and not preview:
			pause_run()

func _move_camera(delta: float) -> void:
	if state in ["pause","revive","result"]:
		_position_camera()
		return
	if preview and capture_screen=="terrain":
		_position_camera()
		return
	var viewport := get_viewport().get_visible_rect().size
	camera_zoom_current = lerpf(camera_zoom_current,camera_zoom_target(),1-exp(-delta*maxf(.5,float(model.camera_setting("zoom_smoothing",4.0)))))
	if absf(camera_zoom_current-camera_zoom_target())<.0005: camera_zoom_current = camera_zoom_target()
	var visible_height := camera_base_size
	var headroom := clampf(visible_height*.17,2.5,4.0)
	var desired := maxf(4.8,sim.pos.y+headroom+clampf(sim.vel.y*.13,0,1.6))
	if state!="menu": desired = maxf(camera_y,desired)
	if state=="menu" and model.profile["active"].is_empty():
		desired = 7
		if not preview:
			sim.pos = Vector2(-.7+sin(elapsed*.9)*.7,8.9+cos(elapsed*.9)*.15)
	camera_y = lerpf(camera_y,desired,1-exp(-delta*7.5))
	# Standing on a shelf below the framing lowers the view a little. In the
	# air the dip only shrinks, so a fall never drags the view after the hero.
	var room := maxf(0,camera_y-(sim.pos.y+headroom))
	var dip_target := minf(room,visible_height*CAMERA_DIP_SHARE) if state=="play" and sim.grounded and not sim.attached else minf(camera_dip,room)
	camera_dip = lerpf(camera_dip,dip_target,1-exp(-delta*3.0))
	camera_view_offset = lerpf(camera_view_offset,zoom_view_offset(),1-exp(-delta*6.0))
	var visible_width := absf(_screen_world(Vector2.ZERO).x-_screen_world(Vector2(viewport.x,0)).x)
	var lead := clampf(sim.vel.x*.24,-1.8,1.8)
	if sim.attached:
		lead += clampf((sim.effective_anchor().x-sim.pos.x)*.16,-.65,.65)
	elif pressed:
		lead += clampf((aim_point.x-sim.pos.x)*.20,-1.1,1.1)
	lead = clampf(lead,-visible_width*.16,visible_width*.16)
	var horizontal := sim.pos.x+lead
	if state=="menu": horizontal = 0
	if capture_overview: horizontal = 0
	# A small soft zone absorbs motion at the swing apex; larger movement and
	# looking ahead still bring the next transfer into view.
	var offset := horizontal-camera_x
	horizontal = camera_x+signf(offset)*maxf(0,absf(offset)-.22)
	camera_x = lerpf(camera_x,horizontal,1-exp(-delta*5))
	_position_camera()

func _process(delta: float) -> void:
	elapsed += delta
	_update_music()
	if not AssetWarmup.done(): AssetWarmup.poll()
	_update_prepared_world()
	if profile_save_pending:
		profile_save_timer -= delta
		if profile_save_timer<=0.0:
			flush_profile_save()
	var fade := maxf(.02,float(model.balance.get("slowmo",{}).get("fade_seconds",.12)))
	focus_blend = move_toward(focus_blend,1.0 if state in ["play","pause"] and focus_active() else 0.0,delta/fade) if state!="pause" else focus_blend
	if state not in ["pause","revive","result"]:
		# The hero and effects slow down with the world, so a slowed walk or
		# fall never looks like sliding.
		animation_time += delta*lerpf(1.0,model.slowmo_time_scale(),focus_blend)
		hint_timer = maxf(0,hint_timer-delta)
	if state=="play" and not preview:
		snapshot_timer += delta
		if snapshot_timer>SNAPSHOT_PERIOD:
			snapshot_timer = 0
			save_snapshot()
	_move_camera(delta)
	_refresh_aim()
	if is_instance_valid(world):
		world.update_visibility(camera_y,camera_x,1)
		if is_instance_valid(world.sky_backdrop): world.sky_backdrop.advance(animation_time,delta)
		# Prices show near the hero and along the aim, unless the player asked
		# for them always. Only the labels change; pickup rules are untouched.
		var aim_at := aim_point if pressed and not sim.attached and not bolt_active else Vector2.INF
		var prices_playing := state=="play"
		var prices_always := str(model.profile.get("loot_prices","always"))=="always"
		loot_price_refresh_timer -= delta
		var price_input_changed := (prices_playing!=last_loot_price_playing
			or prices_always!=last_loot_price_always
			or sim.pos.distance_squared_to(last_loot_price_hero)>.16
			or aim_at.distance_squared_to(last_loot_price_aim)>.16)
		if loot_price_refresh_timer<=0.0 or price_input_changed:
			world.update_loot_prices(prices_playing,prices_always,sim.pos,aim_at)
			loot_price_refresh_timer = .08
			last_loot_price_hero = sim.pos
			last_loot_price_aim = aim_at
			last_loot_price_playing = prices_playing
			last_loot_price_always = prices_always
	var target := sim.anchor if sim.attached else bolt_pos
	var held_grip := world.anchor_by_id(anchor_id) if sim.attached and anchor_id>=0 else {}
	var fragile := not held_grip.is_empty() and GripSpec.timed(held_grip)
	if fragile: world.update_anchor_timer(anchor_id,GripSpec.seconds_left(held_grip,anchor_time))
	if not held_grip.is_empty(): world.update_anchor_load(anchor_id,sim.pos-sim.anchor,sim.vel)
	var warning := fragile and GripSpec.warning(held_grip,anchor_time)
	var shot_visual := {"velocity":return_velocity if bolt_returning else hook_flight.velocity,"age":hook_flight.age,
		"trail":hook_flight.trail,"returning":bolt_returning,"shot":shot_serial,"impact":impact_serial,
		"impact_position":hook_impact,"impact_kind":hook_impact_kind,"aiming":pressed and not sim.attached and not bolt_active,"aim":aim_direction}
	shot_visual["hook_count"] = model.hook_count()
	if hook_volley!=null:
		var volley_visual: Array = []
		for shot in hook_volley.shots:
			var volley_flight: HookFlight = shot["flight"]
			volley_visual.append({"state":shot["state"],"position":volley_flight.position,"velocity":volley_flight.velocity,
				"age":volley_flight.age,"trail":volley_flight.trail,"returning":shot["state"]=="returning"})
		shot_visual["volley"] = volley_visual
	if is_instance_valid(explorer):
		explorer.draw(sim,target,sim.attached or bolt_active or bolt_returning,bolt_active or bolt_returning,animation_time,warning,model.hook_tips(),shot_visual)
		hud.update_play()
	if not capture_path.is_empty() and elapsed>1.1 and not capture_queued:
		capture_queued = true
		_capture_frame()

# The camp theme plays in the menus, the expedition's own theme on the climb;
# pause, revive and result screens lower it.
func _update_music() -> void:
	if music==null or preview or DisplayServer.get_name()=="headless": return
	var theme := "camp"
	if state!="menu":
		var location_id := "green_peak" if run_mode=="practice" else str(LevelCatalog.level(selected_location)["id"])
		theme = MusicPlayer.track_for_location(location_id)
	music.play(theme)
	music.duck(state in ["pause","revive","result"])
	music.set_muffled(focus_blend)
	sounds.set_key(MusicPlayer.tonality(theme))
	sounds.set_wind(_wind_level())

# Air rushing past the hero, quieter while time is slowed.
func _wind_level() -> float:
	if state!="play" or sim==null or sim.grounded or int(_settings()["sfx_volume"])<=0: return 0.0
	return clampf((sim.vel.length()-WIND_SPEED_MIN)/(WIND_SPEED_FULL-WIND_SPEED_MIN),0,1)*lerpf(1.0,.35,focus_blend)

func _setup_audio_buses() -> void:
	for bus_name in ["Music","SFX"]:
		if AudioServer.get_bus_index(bus_name)>=0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count-1
		AudioServer.set_bus_name(index,bus_name)
		AudioServer.set_bus_send(index,"Master")
	# A safety net: however many sounds pile up, the output never clips.
	if AudioServer.get_bus_effect_count(0)==0:
		AudioServer.add_bus_effect(0,AudioEffectHardLimiter.new())

func _set_bus(bus_name: String, percent: int) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(index,percent<=0)
	if percent>0: AudioServer.set_bus_volume_db(index,linear_to_db(percent*.01))

func apply_audio() -> void:
	var settings := _settings()
	_set_bus("Master",int(settings["master_volume"]))
	_set_bus("Music",int(settings["music_volume"]))
	_set_bus("SFX",int(settings["sfx_volume"]))
	var playing := int(settings["music_volume"])>0
	if music!=null and music.enabled!=playing: music.set_enabled(playing)
	if int(settings["sfx_volume"])<=0 and is_instance_valid(sounds): sounds.stop_all()

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(capture_path)
	print("CAPTURE_RESULT ",error," ",capture_path)
	get_tree().quit(error)

func toast(text: String, duration: float = 2.5, context: String = "") -> void:
	hint = text
	hint_context = context
	hint_timer = duration
	if is_instance_valid(hud):
		hud.set_toast(text)

func _sound_on() -> bool:
	return int(_settings()["sfx_volume"])>0 and not preview and DisplayServer.get_name()!="headless"

func _sfx(sound: String) -> void:
	if _sound_on(): sounds.play(sound)

func _haptic(pattern: String) -> void:
	if model.profile.get("vibration",true) and not preview: haptics.play(pattern)

# Buttons answer with a small tick and the lightest vibration.
func ui_tap() -> void:
	_sfx("tap")
	_haptic("tap")
