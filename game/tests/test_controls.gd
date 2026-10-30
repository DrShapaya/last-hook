extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error("CONTROLS FAILED: "+description)

func attached_fixture(game) -> void:
	game._reset_input()
	game.state = "play"
	game.sim = RopeSim.new()
	game._configure_rope()
	var anchor: Dictionary = game.world.anchors[0]
	anchor["broken"] = false
	game.sim.pos = anchor["pos"]+Vector2(0,-2.8)
	game.sim.attach(anchor["pos"],game.model.shot_range())
	game.anchor_id = anchor["id"]
	game.anchor_contact = anchor["pos"]
	game.bolt_active = false
	game.bolt_returning = false
	game.camera_y = anchor["pos"].y+2.5
	game.camera_x = anchor["pos"].x
	game._position_camera()

func free_fixture(game) -> void:
	game._reset_input()
	game.state = "play"
	game.sim.attached = false
	game.sim.pos = Vector2(0,20)
	game.sim.vel = Vector2.ZERO
	game.bolt_active = false
	game.bolt_returning = false
	game.camera_x = 0
	game.camera_y = 22
	game._position_camera()

func touch(index: int, point: Vector2, down: bool, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	event.canceled = canceled
	return event

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var gesture := ClimbGesture.new()
	gesture.begin(Vector2(300,400),0,1)
	var motion := gesture.move(Vector2(305,396),.05,1)
	check(motion["pump"]==0 and motion["reel"]==0,"thumb jitter remains neutral")
	gesture.move(Vector2(300,320),.1,1)
	motion = gesture.sample(.379)
	check(motion["reel"]==0 and motion["vertical_progress"]<1,"vertical input waits the full 0.28 seconds")
	motion = gesture.sample(.381)
	check(motion["reel"]>0 and motion["pump"]==0,"stationary upward hold starts reeling without another drag event")
	gesture.move(Vector2(300,480),.4,1)
	check(gesture.sample(.679)["reel"]==0,"changing from up to down restarts the intent delay")
	check(gesture.sample(.681)["reel"]<0,"stationary downward hold extends after its own delay")
	gesture.move(Vector2(301,402),.7,1)
	check(gesture.sample(2)["reel"]==0,"returning to neutral stops vertical intent")
	gesture.move(Vector2(300,377),2.1,1)
	check(gesture.sample(3)["reel"]==0,"a small vertical deviation below 24 logical pixels cannot reel")
	for offset in [Vector2(60,-80),Vector2(60,80),Vector2(80,0),Vector2(-80,-30)]:
		gesture.begin(Vector2(300,400),0,1)
		gesture.move(Vector2(300,400)+offset,.1,1)
		motion = gesture.sample(1)
		check(motion["reel"]==0 and absf(motion["pump"])>.1,"diagonal and horizontal stick input only swing: %s" % offset)
	gesture.begin(Vector2(300,400),0,1)
	gesture.move(Vector2(310,320),.1,1)
	gesture.move(Vector2(324,320),.2,1)
	check(gesture.sample(.39)["reel"]>0,"small angular jitter inside the 22-degree exit cone preserves the timer")
	gesture.move(Vector2(340,320),.4,1)
	check(gesture.sample(.8)["reel"]==0,"leaving the vertical cone cancels the motor")
	gesture.move(Vector2(300,320),.81,1)
	check(gesture.sample(1.08)["reel"]==0 and gesture.sample(1.10)["reel"]>0,"returning from a diagonal requires a new complete delay")
	for scale in [.45,1.0,1.8]:
		for rate in [10,30,60,120]:
			gesture.begin(Vector2(300,400)*scale,0,scale)
			gesture.move(Vector2(300,320)*scale,0,scale)
			var activated := -1.0
			for index in range(1,rate+1):
				var t: float = float(index)/rate
				motion = gesture.sample(t)
				if activated<0 and motion["reel"]>0: activated = t
			check(activated>=ClimbGesture.VERTICAL_HOLD_SECONDS and activated<ClimbGesture.VERTICAL_HOLD_SECONDS+1.0/rate+.001,"vertical timing is independent of event count / scale: %s / %s" % [rate,scale])
	var sim := RopeSim.new()
	sim.gravity = 0
	sim.pos = Vector2(0,2)
	sim.attach(Vector2(0,6),5.5)
	sim.request_length(2.5)
	var initial := sim.length
	sim.tick(HookFlight.STEP,0,0)
	check(initial-sim.length<.003 and sim.reel_velocity<0,"the reel accelerates without a length jump")
	for index in range(12): sim.tick(HookFlight.STEP,0,0)
	var previous_speed := sim.reel_velocity
	sim.request_length(5)
	sim.tick(HookFlight.STEP,0,0)
	check(sim.reel_velocity<0 and sim.reel_velocity>previous_speed,"reversing the reel brakes before accelerating the other way")
	var legal := true
	for index in range(240):
		sim.tick(HookFlight.STEP,0,0)
		legal = legal and sim.length>=RopeSim.MIN_LENGTH and sim.length<=sim.maximum_length
	check(legal and is_equal_approx(sim.length,5) and is_zero_approx(sim.reel_velocity),"reeling settles within legal length bounds")
	var velocity := sim.vel
	sim.release(1)
	check(sim.vel==velocity and sim.reel_velocity==0,"release preserves velocity and clears the motor")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.set_level(GameModel.SLOWMO,3)
	game.start_run(false)
	var expected := Vector2(.6,.8)
	for origin in [Vector2(80,240),Vector2(400,650),Vector2(25,30),Vector2(440,800)]:
		free_fixture(game)
		game.pointer_down(origin,true)
		check(game.pressed and not game.aim_stick_valid,"a stick can begin anywhere outside controls: %s" % origin)
		game.pointer_move(origin+Vector2(60,-80))
		check(game.aim_direction.distance_to(expected)<.0001,"translated touch origins produce the same launch angle: %s" % origin)
		game.pointer_up(origin+Vector2(60,-80))
		check(game.bolt_active and game.hook_flight.velocity.normalized().distance_to(expected)<.0001,"lifting throws in the chosen direction: %s" % origin)
	free_fixture(game)
	game.pointer_down(Vector2(300,400),true)
	game.pointer_move(Vector2(330,360))
	var short_direction: Vector2 = game.aim_direction
	game.pointer_move(Vector2(420,240))
	check(game.aim_direction.distance_to(short_direction)<.0001,"stick distance does not change the launch angle")
	game.camera_x += 3
	game.camera_y += 2
	game._position_camera()
	game.sim.pos += Vector2(2,1)
	game.sim.vel = Vector2(7,-3)
	game._refresh_aim()
	check(game.aim_direction.distance_to(expected)<.0001,"camera and hero movement cannot rotate a held launch direction")
	game.pointer_move(Vector2(302,400))
	var shots_before: int = game.shots
	game.pointer_up(Vector2(302,400))
	check(not game.bolt_active and game.shots==shots_before,"returning to the stick dead zone cancels the throw")
	free_fixture(game)
	game.pointer_down(Vector2(300,400),true)
	game.pointer_up(Vector2(300,400))
	check(not game.bolt_active,"a neutral tap does not throw toward the touch position")
	check(game.hud.touch_controls_hint,"touch hints remain active after the finger lifts, including on Windows")
	for scale in [.45,1.0,1.8]:
		for events in [1,4,16]:
			free_fixture(game)
			game.hud.root.scale = Vector2.ONE*scale
			var origin: Vector2 = Vector2(200,400)*scale
			game.pointer_down(origin,true)
			for index in range(1,events+1): game.pointer_move(origin+Vector2(60,-80)*scale*float(index)/events)
			check(game.aim_direction.distance_to(expected)<.0001,"stick aim is independent of UI scale and coalesced event count: %s / %s" % [scale,events])
	game.hud._resize()
	check(not game.pressed and not game.bolt_active,"layout changes cancel an aim without throwing")
	attached_fixture(game)
	game.pointer_down(Vector2(300,400),true)
	var begin: int = game.gesture_last_msec
	game.pointer_move(Vector2(300,320),begin+80)
	check(game.sim.attached and game.reel==0,"a fast upward swipe does not release or reel immediately")
	var old_target: float = game.sim.target_length
	game._update_touch_controls(begin+359)
	game.sim.tick(HookFlight.STEP,game.pump,game.reel)
	check(game.sim.target_length==old_target,"rope length stays unchanged until the complete vertical delay")
	game._update_touch_controls(begin+361)
	game.sim.tick(HookFlight.STEP,game.pump,game.reel)
	check(game.reel>0 and game.sim.target_length<old_target and game.sim.attached,"vertical hold starts the actual rope motor after the delay")
	shots_before = game.shots
	velocity = Vector2(3,2)
	game.sim.vel = velocity
	game.pointer_up(Vector2(300,320))
	check(not game.sim.attached and not game.bolt_active and game.shots==shots_before and game.sim.vel==velocity,"primary lift only detaches and preserves actual velocity")
	check(is_equal_approx(game.focus_remaining,game.model.slowmo_seconds()) and game.hud.slowmo_indicator.visible==false,"manual release starts the short focus window without keeping the stick pressed")
	game.hud.update_play()
	check(game.hud.slowmo_indicator.visible and game.hud.slowmo_indicator.remaining>0,"focus window is visible in the HUD while it is active")
	var focus_before: float = game.focus_remaining
	game._physics_process(.1)
	check(game.focus_remaining<focus_before,"focus window continues to expire after the finger is released")
	game.pointer_up(Vector2(300,320))
	check(game.shots==shots_before,"duplicate lift cannot fire a hook")
	game.pointer_down(Vector2(150,600),true)
	game.pointer_move(Vector2(210,520))
	game.pointer_up(Vector2(210,520))
	check(game.bolt_active and game.shots==shots_before+1,"the next new gesture throws one hook")
	attached_fixture(game)
	game.pointer_down(Vector2(300,400),true)
	game.pointer_move(Vector2(380,400))
	check(game.sim.attached and game.pump>.9 and game.reel==0,"horizontal hold immediately pumps without changing length")
	game.pointer_up(Vector2(380,400))
	check(not game.sim.attached and not game.bolt_active,"lifting after a swing detaches without a simultaneous throw")
	attached_fixture(game)
	game._unhandled_input(touch(3,Vector2(300,400),true))
	game._unhandled_input(touch(8,Vector2(410,450),true))
	var extra_drag := InputEventScreenDrag.new()
	extra_drag.index = 8
	extra_drag.position = Vector2(410,320)
	game._input(extra_drag)
	game._input(touch(8,Vector2(410,320),false))
	check(game.primary_touch==3 and game.pressed and game.sim.attached and game.reel==0,"extra finger motion and lift cannot control or detach the primary hook")
	game._input(touch(3,Vector2(300,920),false))
	check(not game.pressed and not game.sim.attached and game.primary_touch<0,"owned primary lift over the inventory still detaches and clears input")
	game._input(extra_drag)
	check(not game.pressed and not game.bolt_active,"an ignored held finger cannot inherit control after primary lift")
	attached_fixture(game)
	root.push_input(touch(4,Vector2(50,40),true),true)
	await process_frame
	check(game.primary_touch==4 and game.pressed,"native touch can start over the noninteractive height HUD")
	var pause_point: Vector2 = game.hud.pause_button.get_global_rect().get_center()
	var shots_held: int = game.shots
	root.push_input(touch(9,pause_point,true),true)
	root.push_input(touch(9,pause_point,false),true)
	await process_frame
	check(game.state=="pause" and game.primary_touch<0 and not game.pressed and game.sim.attached and game.shots==shots_held,"a second finger presses Pause during a stick gesture: the gesture drops without a shot and the hook holds")
	# The first finger lifting while paused changes nothing.
	root.push_input(touch(4,Vector2(50,40),false),true)
	await process_frame
	check(game.state=="pause" and game.sim.attached and game.shots==shots_held,"the steering finger lifting during the pause neither shoots nor detaches")
	game.unpause()
	root.push_input(touch(4,Vector2(50,40),true),true)
	await process_frame
	root.push_input(touch(4,Vector2(50,40),false,true),true)
	await process_frame
	check(not game.pressed and game.sim.attached,"native cancellation over the HUD keeps the attachment")
	root.push_input(touch(4,pause_point,true),true)
	root.push_input(touch(4,pause_point,false),true)
	await process_frame
	check(game.state=="pause" and not game.pressed,"Pause still works when the stick does not own a finger")
	game.unpause()
	free_fixture(game)
	shots_before = game.shots
	root.push_input(touch(5,Vector2(150,400),true),true)
	var native_drag := InputEventScreenDrag.new()
	native_drag.index = 5
	native_drag.position = Vector2(210,320)
	root.push_input(native_drag,true)
	root.push_input(touch(5,native_drag.position,false),true)
	await process_frame
	check(game.bolt_active and game.shots==shots_before+1 and game.primary_touch<0,"native GUI routing completes a stick throw once without mouse emulation")
	attached_fixture(game)
	game._unhandled_input(touch(7,Vector2(300,400),true))
	game._input(touch(7,Vector2(300,330),false,true))
	check(game.sim.attached and not game.pressed and game.primary_touch<0,"system cancellation does not detach")
	free_fixture(game)
	game._unhandled_input(touch(7,Vector2(300,400),true))
	game.pointer_move(Vector2(340,350))
	shots_before = game.shots
	game._input(touch(7,Vector2(340,350),false,true))
	check(not game.bolt_active and game.shots==shots_before,"system cancellation does not throw")
	attached_fixture(game)
	game.pointer_down(Vector2(300,400),true)
	game.pointer_move(Vector2(300,320),game.gesture_last_msec+80)
	game.pause_run()
	game.unpause()
	check(game.sim.attached and not game.pressed and game.reel==0,"pause and resume cancel vertical intent without releasing")
	attached_fixture(game)
	game.pointer_down(Vector2(300,400),true)
	game.pointer_move(Vector2(350,380))
	game.release_hook(true)
	game.pointer_up(Vector2(350,380))
	check(not game.bolt_active,"a naturally broken attachment cannot turn the existing lift into a surprise throw")
	free_fixture(game)
	var mouse_point: Vector2 = game.camera.unproject_position(Vector3(2,23,0))
	game.pointer_down(mouse_point)
	game.camera_x += 1
	game._position_camera()
	game._refresh_aim()
	check(game.aim_point.distance_to(game._screen_world(mouse_point))<.0001 and not game.hud.touch_controls_hint,"desktop mouse retains direct target aiming and mouse instructions")
	attached_fixture(game)
	game.pointer_down(Vector2(300,400))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	game._unhandled_input(space)
	game.pointer_up(Vector2(300,400))
	check(game.bolt_active,"desktop Space and held mouse retain their next-shot workflow")
	game.start_run(false)
	var first: Vector2 = game.world.anchors[0]["pos"]
	game.pointer_down(Vector2(300,400),true)
	game.pump = .9
	game.reel = .8
	game.sim.pump_input = .7
	game.fire_hook(game.direction_to_target(first))
	game._update_bolt(.3)
	check(game.sim.attached and game.pressed and game.pump==0 and game.reel==0 and game.sim.pump_input==0 and game.press_start==game.pointer and not game.aim_stick_valid,"a catch under a held finger recenters the stick and clears previous intent")
	free_fixture(game)
	game.sim.vel = Vector2(8,0)
	game.camera_y = 24
	game._move_camera(.3)
	check(game.camera_x>1,"camera makes room for horizontal transfers")
	var camera_before := Vector2(game.camera_x,game.camera_y)
	game.sim.vel.x = -8
	game._move_camera(1.0/60)
	check(absf(game.camera_x-camera_before.x)<.4,"a direction change does not snap the camera")
	for paused_state in ["pause","revive","result"]:
		game.state = paused_state
		camera_before = Vector2(game.camera_x,game.camera_y)
		game.sim.pos += Vector2(3,3)
		game._move_camera(.5)
		check(Vector2(game.camera_x,game.camera_y)==camera_before,"camera freezes in "+paused_state)
	game.state = "play"
	game.sim.pos = Vector2(5,20)
	game.sim.vel = Vector2(4,6)
	var camera_results: Array[Vector2] = []
	for rate in [30,60,120]:
		game.camera_x = 0
		game.camera_y = 7
		game._position_camera()
		for index in range(rate): game._move_camera(1.0/rate)
		camera_results.append(Vector2(game.camera_x,game.camera_y))
	check(camera_results[0].distance_to(camera_results[1])<.002 and camera_results[1].distance_to(camera_results[2])<.002,"camera framing is consistent across frame rates")
	game.sim.vel = Vector2(0,-8)
	var height_before: float = game.camera_y
	game.sim.pos.y -= 5
	game._move_camera(.5)
	check(game.camera_y>=height_before,"falling does not lower the camera")
	game._create_world(11,1,36)
	game.sim.pos = Vector2(10,15)
	game.sim.vel = Vector2(4,0)
	game.camera_x = 0
	game.camera_y = 18
	game._move_camera(.5)
	check(game.camera_x>8,"camera follows the other mountain locations")
	game._create_world(58273,0,126)
	attached_fixture(game)
	game.camera_x = 2.3
	game.sim.reel_velocity = -.8
	game.save_snapshot()
	game.resume_run()
	check(absf(game.camera_x-2.3)<.0001 and absf(game.sim.reel_velocity+.8)<.0001,"save and resume preserve framing and reel acceleration")
	check(game.hud.pause_button.tooltip_text.is_empty(),"the in-run Pause button shows no caption over the game")
	# Walking on a platform: a held horizontal stick walks, the hero stops at
	# the edge, and lifting the finger afterwards throws nothing.
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.world.add_ledge(Vector2(0,30),4.0)
	game.sim.pos = Vector2(0,30.15+SolidGeometry.BODY_HALF.y+.01)
	game.sim.vel = Vector2.ZERO
	game.sim.grounded = true
	game.sim.launched = true
	game.camera_y = 33
	game._position_camera()
	for frame in range(10): game._physics_process(1.0/60)
	check(game.state=="play" and game.sim.grounded and absf(game.sim.vel.x)<.01,"the hero stands still on a platform without input")
	game.pointer_down(Vector2(300,400),true)
	var walk_begin: int = game.gesture_last_msec
	game.pointer_move(Vector2(380,404),walk_begin+10)
	game._update_touch_controls(walk_begin+200)
	check(game.walk==0 and game.aim_stick_valid,"a short sideways hold on a platform still aims")
	game._update_touch_controls(walk_begin+300)
	check(game.walk>.9 and not game.aim_stick_valid,"holding right on a platform walks after the hold delay")
	var walk_from: float = game.sim.pos.x
	for frame in range(30): game._physics_process(1.0/60)
	check(game.sim.grounded and game.sim.pos.x>walk_from+.5 and game.sim.vel.x>game.WALK_SPEED*.9 and game.sim.vel.x<=game.WALK_SPEED,"the hero walks along the platform at walking speed")
	for frame in range(240): game._physics_process(1.0/60)
	check(game.state=="play" and game.sim.grounded and game.sim.pos.x<2.3 and absf(game.sim.vel.x)<.01,"walking stops at the platform edge instead of stepping off")
	var walk_shots: int = game.shots
	game.pointer_up(Vector2(380,404))
	check(game.shots==walk_shots and not game.bolt_active and game.walk==0,"lifting the finger after a walk throws no hook")
	game.sim.grounded = false
	game.pointer_down(Vector2(300,400),true)
	walk_begin = game.gesture_last_msec
	game.pointer_move(Vector2(220,404),walk_begin+10)
	game._update_touch_controls(walk_begin+400)
	check(game.walk==0,"a sideways hold in the air never walks")
	game._cancel_primary()
	game.sim.grounded = true
	# Landing low lowers the view, but the danger edge stays where it was.
	game.sim.pos = Vector2(0,30.15+SolidGeometry.BODY_HALF.y+.01)
	game.sim.vel = Vector2.ZERO
	game.camera_y = 36
	game.camera_dip = 0
	game._position_camera()
	var edge_before: float = game.screen_bottom_y()
	for frame in range(120): game._move_camera(1.0/60)
	check(game.camera_dip>.3 and absf(game.camera_y-36)<.001,"the view sinks a little after landing below the framing")
	check(absf(game.screen_bottom_y()-edge_before)<.001,"a lowered view does not move the danger edge")
	game.hud.update_play()
	check(game.hud.danger_edge.strength>0 and game.hud.danger_edge.edge_y<game.hud.root.size.y,"the danger edge is drawn when the view drops below it")
	var dip_before: float = game.camera_dip
	game.sim.grounded = false
	game.sim.vel = Vector2(0,-8)
	game.sim.pos.y -= 3
	game._move_camera(.5)
	check(game.camera_dip<=dip_before+.0001 and game.camera_y>=36,"a fall never drags the view down")
	game.sim.pos.y = edge_before-1.0
	game._physics_process(1.0/120)
	check(game.state in ["revive","result"],"leaving below the danger edge still ends the attempt with a lowered view")
	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("controls-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	print("CONTROLS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
