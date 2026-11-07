extends SceneTree

# HeroState: the hero's state comes from events, not from guesses by speed.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("HERO STATE FAILED: "+description)

func frame(grounded: bool, attached: bool, velocity: Vector2, extra: Dictionary = {}) -> Dictionary:
	var result := {"grounded":grounded,"attached":attached,"tether":attached,"velocity":velocity,
		"position":Vector2.ZERO,"anchor":Vector2(0,3),"root_anchor":Vector2(0,3)}
	result.merge(extra,true)
	return result

func step(hero: HeroState, seconds: float, data: Dictionary) -> void:
	var frames := maxi(1,roundi(seconds*60))
	for index in range(frames): hero.update(1.0/60,data)

func run_tests() -> void:
	unit_events()
	no_flicker()
	await bot_attempt()
	sprite_follows_state()
	print("HERO_STATE_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("  FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)

func unit_events() -> void:
	var hero := HeroState.new()
	hero.update(1.0/60,frame(true,false,Vector2.ZERO))
	check(hero.state==HeroState.IDLE and hero.history.is_empty(),"first frame sets idle without a transition")
	hero.update(1.0/60,frame(true,false,Vector2.ZERO,{"aiming":true,"aim":Vector2(1,1)}))
	check(hero.state==HeroState.AIM and hero.aim_direction.is_equal_approx(Vector2(1,1).normalized()),"pressing to aim enters aim with its direction")
	step(hero,.5,frame(true,false,Vector2.ZERO,{"aiming":true}))
	check(hero.state==HeroState.AIM,"aim holds while the finger is down")
	hero.update(1.0/60,frame(true,false,Vector2.ZERO,{"shot":0,"aiming":false}))
	hero.update(1.0/60,frame(true,false,Vector2.ZERO,{"shot":1,"tether":true,"hook_flying":true}))
	check(hero.state==HeroState.THROW and hero.time_in_state<.02,"the release of the finger throws in the same frame")
	step(hero,HeroState.THROW_TIME+.05,frame(true,false,Vector2.ZERO,{"shot":1,"tether":true,"hook_flying":true}))
	check(hero.state==HeroState.HOOK_FLIGHT,"after the throw the hand follows the flying hook")
	hero.update(1.0/60,frame(false,true,Vector2(2,0),{"shot":1}))
	check(hero.state==HeroState.LATCH,"the catch is an event")
	step(hero,.3,frame(false,true,Vector2(2,0),{"shot":1,"pump":.7}))
	check(hero.state==HeroState.SWING and is_equal_approx(hero.swing_power,.7),"after the catch the hero swings and knows the pump")
	check(is_equal_approx(hero.rope_angle,PI*.5),"rope angle points from the hero to the anchor")
	hero.update(1.0/60,frame(false,true,Vector2(2,0),{"shot":2,"root_anchor":Vector2(4,6)}))
	check(hero.state==HeroState.LATCH,"a new grip caught straight from the rope is a new catch")
	step(hero,.3,frame(false,true,Vector2(2,0),{"shot":2,"root_anchor":Vector2(4,6)}))
	hero.update(1.0/60,frame(false,false,Vector2(3,5),{"shot":2}))
	check(hero.state==HeroState.RELEASE,"letting go is an event")
	step(hero,.3,frame(false,false,Vector2(3,5),{"shot":2}))
	check(hero.state==HeroState.RISE,"after letting go the hero rises")
	step(hero,.1,frame(false,false,Vector2(3,-.3),{"shot":2}))
	check(hero.state==HeroState.RISE,"a small sink at the top is not yet a fall")
	step(hero,.1,frame(false,false,Vector2(3,-7),{"shot":2}))
	check(hero.state==HeroState.FALL,"falling fast enters fall")
	hero.update(1.0/60,frame(true,false,Vector2(1,0),{"shot":2}))
	check(hero.state==HeroState.LAND and hero.land_strength>.8,"a fast touchdown is a hard landing")
	step(hero,HeroState.LAND_TIME_HARD+.05,frame(true,false,Vector2(1,0),{"shot":2}))
	check(hero.state==HeroState.WALK,"a hero moving on the ledge walks after landing")
	step(hero,.2,frame(true,false,Vector2(.25,0),{"shot":2}))
	check(hero.state==HeroState.WALK,"walking slows down without dropping to idle at once")
	step(hero,.2,frame(true,false,Vector2(.05,0),{"shot":2}))
	check(hero.state==HeroState.IDLE,"stopping ends the walk")
	var soft := HeroState.new()
	soft.update(1.0/60,frame(false,false,Vector2(0,-1)))
	soft.update(1.0/60,frame(true,false,Vector2.ZERO))
	check(soft.state==HeroState.LAND and soft.land_strength<.2,"a slow touchdown is a soft landing")
	var slipping := HeroState.new()
	slipping.update(1.0/60,frame(false,true,Vector2.ZERO))
	slipping.update(1.0/60,frame(false,false,Vector2(0,-1),{"release_reason":"ice_slip"}))
	check(slipping.state==HeroState.SLIP,"an icy grip letting go is a slip, not a release")
	slipping.event("summit")
	slipping.update(1.0/60,frame(true,false,Vector2.ZERO))
	step(slipping,2,frame(true,false,Vector2.ZERO))
	check(slipping.state==HeroState.SUMMIT,"the summit holds until the run ends")
	slipping.reset()
	slipping.update(1.0/60,frame(true,false,Vector2.ZERO))
	slipping.event("revive")
	slipping.update(1.0/60,frame(true,false,Vector2.ZERO))
	check(slipping.state==HeroState.REVIVE,"revive is an event")
	step(slipping,1,frame(true,false,Vector2.ZERO))
	check(slipping.state==HeroState.IDLE,"revive settles to idle")
	var signals: Array = []
	var watched := HeroState.new()
	watched.state_changed.connect(func(from: String, to: String): signals.append([from,to]))
	watched.update(1.0/60,frame(true,false,Vector2.ZERO))
	watched.update(1.0/60,frame(false,true,Vector2.ZERO))
	check(signals==[[HeroState.IDLE,HeroState.LATCH]],"state changes are announced by a signal")
	var paused := HeroState.new()
	paused.update(1.0/60,frame(false,false,Vector2(0,-3)))
	var before := [paused.state,paused.time_in_state]
	paused.update(0,frame(false,false,Vector2(0,-3)))
	check([paused.state,paused.time_in_state]==before,"a paused clock leaves the state alone")

# Noisy input around every threshold must not make the state blink.
func no_flicker() -> void:
	var hero := HeroState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	hero.update(1.0/60,frame(true,false,Vector2.ZERO))
	for index in range(600):
		var walk_speed := .26+rng.randf_range(-.07,.07)
		hero.update(1.0/60,frame(true,false,Vector2(walk_speed,0)))
	check(count_blinks(hero.history,.1)==0,"walking speed near the threshold does not blink between walk and idle")
	hero.reset()
	hero.update(1.0/60,frame(false,false,Vector2(0,1)))
	for index in range(600):
		hero.update(1.0/60,frame(false,false,Vector2(1,-.35+rng.randf_range(-.2,.2))))
	check(count_blinks(hero.history,.1)==0,"vertical speed near the top of a jump does not blink between rise and fall")

static func count_blinks(history: Array, window: float) -> int:
	# A blink: a state left and re-entered within `window` seconds.
	var blinks := 0
	for index in range(1,history.size()):
		var a: Array = history[index-1]
		var b: Array = history[index]
		if a[0]==b[1] and float(b[2])-float(a[2])<window: blinks += 1
	return blinks

# A real attempt: the integration movement bot climbs grips while HeroState
# watches the same data ExplorerView gets.
func bot_attempt() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		check(false,"LASTHOOK_SAVE_DIR is set for the bot attempt")
		return
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
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
	var hero := HeroState.new()
	var seen := {}
	var catches := 0
	var reached := 1
	var throw_lag := 0
	var pending_shot := false
	for route_index in range(1,6):
		var target_id: int = game.world.main_route[route_index]
		var target: Vector2 = game.world.anchor_by_id(target_id)["pos"]
		var fired := false
		for index in range(1200):
			if game.state!="play": break
			var shots_before: int = game.shot_serial
			if pending_shot: shots_before -= 1
			pending_shot = false
			if game.sim.attached:
				game.reel = 1.0 if index<240 else 0.0
				if index>=240: game.sim.request_length(3.3 if index%360<180 else 2.0)
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
					touch_throw(game,goal)
					fired = true
			game._physics_process(1.0/120)
			var tether: bool = game.sim.attached or game.bolt_active or game.bolt_returning
			var state := hero.update(1.0/120,HeroState.observe(game.sim,tether,{"shot":game.shot_serial}))
			seen[state] = true
			if game.shot_serial!=shots_before and not state in [HeroState.THROW,HeroState.LATCH]: throw_lag += 1
			if hero.time_in_state==0.0 and state==HeroState.LATCH: catches += 1
			if game.anchor_id==target_id and game.sim.attached:
				reached += 1
				break
			if fired and not game.bolt_active and not game.sim.attached:
				var again: int = game.shot_serial
				touch_throw(game,target)
				if game.shot_serial!=again: pending_shot = true
		if reached!=route_index+1: break
	check(reached>=4,"bot climbs at least three grips for the state check (reached %d)" % reached)
	for name in [HeroState.LATCH,HeroState.SWING,HeroState.THROW]:
		check(seen.has(name),"bot attempt passes through %s" % name)
	check(catches>=reached-1,"every caught grip starts a catch (%d catches, %d grips)" % [catches,reached-1])
	check(throw_lag==0,"the throw state starts in the same frame as the shot")
	check(count_blinks(hero.history,.05)==0,"no state blinks during the bot attempt")
	for entry in hero.history: check(entry[1] in HeroState.STATES,"only known states appear")
	game.queue_free()

func sprite_follows_state() -> void:
	var sprite := ExplorerSprite.new()
	root.add_child(sprite)
	sprite.setup()
	var sim := RopeSim.new()
	sprite.animate(sim,Vector2(2,3),false,0)
	sprite.flight_info = {"aiming":true,"aim":Vector2(1,0),"shot":0}
	sprite.animate(sim,Vector2(2,3),true,1.0/60)
	check(sprite.hero.state==HeroState.AIM and sprite.state=="throw","aiming on the ledge shows the throw pose through HeroState")
	sprite.flight_info = {"shot":0,"release_reason":"ice_slip"}
	sim.grounded = false
	sim.attached = true
	sprite.animate(sim,Vector2(2,3),true,2.0/60)
	check(sprite.hero.state==HeroState.LATCH and sprite.state=="swing","the sprite reads the catch from HeroState")
	sprite.queue_free()

# Same gesture as the integration movement bot.
func touch_throw(game, target: Vector2) -> void:
	var origin := Vector2(150,400)
	if game.sim.attached:
		game.pointer_down(origin,true)
		game.pointer_up(origin)
	var direction: Vector2 = game.direction_to_target(target)
	var end: Vector2 = origin+Vector2(direction.x,-direction.y)*82*game._gesture_scale()
	game.pointer_down(origin,true)
	game.pointer_move(end)
	game.pointer_up(end)
