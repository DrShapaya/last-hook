extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error("HOOK FAILED: "+description)

func clear_shot(game) -> void:
	game.world.anchors.clear()
	game.world.layout.bins.clear()
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.sim = RopeSim.new()
	game._configure_rope()
	game.sim.pos = Vector2(0,20)
	game.sim.grounded = false
	game.bolt_active = false
	game.bolt_returning = false
	game.anchor_id = -1

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var flight := HookFlight.new()
	flight.launch(Vector2.ZERO,Vector2.RIGHT,16,Vector2.ZERO)
	flight.advance(.3)
	check(flight.position.distance_to(Vector2(4.8,-.36))<.0001,"a horizontal throw has a visible gravitational drop")
	check(flight.velocity.y<0 and flight.velocity.x==16,"the hook rotates with a changing flight tangent")
	var fine := HookFlight.new()
	fine.launch(Vector2.ZERO,Vector2.RIGHT,16,Vector2.ZERO)
	for index in range(36): fine.advance(HookFlight.STEP)
	check(fine.position.distance_to(flight.position)<.0001 and fine.velocity.distance_to(flight.velocity)<.0001,"ballistic motion is independent of frame subdivision")
	flight.launch(Vector2.ZERO,Vector2.UP,16,Vector2(9,0))
	check(flight.velocity.x>2 and flight.velocity.x<3,"throw inherits a bounded share of the explorer's momentum")
	var solved := true
	for velocity in [Vector2.ZERO,Vector2(7,-5),Vector2(-8,6)]:
		for target in [Vector2(4,2),Vector2(-4,3),Vector2(0,5),Vector2(10,1)]:
			var solution := HookFlight.aim_solution(Vector2.ZERO,target,16,velocity)
			flight.launch(Vector2.ZERO,solution["direction"],16,velocity)
			flight.advance(solution["time"])
			solved = solved and flight.position.distance_to(target)<.001
	check(solved,"point aiming solves the shallow arc while accounting for inherited momentum")
	check(is_equal_approx(HookFlight.range_fraction(Vector2.ZERO,Vector2(8,0),Vector2.ZERO,5.5),5.5/8),"payout clips the swept arc at the actual available rope")
	var wave := ExplorerView.flight_rope_points(Vector3.ZERO,Vector3(0,4,0),.12,false)
	check(wave[0]==Vector3.ZERO and wave[-1]==Vector3(0,4,0) and absf(wave[8].x)>.01,"flying rope has a visible wave while preserving both endpoints")
	var next_wave := ExplorerView.flight_rope_points(Vector3.ZERO,Vector3(0,4,0),.18,false)
	check(wave[8].distance_to(next_wave[8])>.02,"payout wave travels over time instead of drawing a static curve")
	var sim := RopeSim.new()
	sim.gravity = 0
	sim.pos = Vector2(0,2)
	sim.vel = Vector2(5,-2)
	sim.attach(Vector2(0,6),5.5,true)
	check(sim.vel==Vector2(5,-2) and sim.length>sim.target_length,"catch preserves momentum and leaves a short take-up before tension")
	sim.tick(HookFlight.STEP,0,0)
	check(sim.vel.y<0,"taking up slack does not kick the explorer upward before the rope becomes taut")
	for index in range(36): sim.tick(HookFlight.STEP,0,0)
	check(is_equal_approx(sim.length,sim.target_length) and sim.vel.x>4,"take-up settles promptly without discarding tangential speed")
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	clear_shot(game)
	var target := Vector2(4,22)
	game.world.add_anchor(target,0)
	var direction: Vector2 = game.direction_to_target(target)
	var before_position: Vector2 = game.sim.pos
	var before_velocity: Vector2 = game.sim.vel
	var prediction: Dictionary = game.predict_shot(direction)
	check(not prediction["collision"].is_empty() and not prediction["collision"].get("blocked",false),"curved preview detects the reachable grip")
	check(game.sim.pos==before_position and game.sim.vel==before_velocity and not game.bolt_active,"preview does not mutate live physics or launch a projectile")
	game.fire_hook(direction)
	for index in range(120):
		game._physics_process(HookFlight.STEP)
		if not game.bolt_active: break
	check(game.sim.attached and game.anchor_id==0,"a moving explorer catches the grip along the predicted ballistic arc")
	check(game.anchor_contact.distance_to(prediction["contact"])<.005,"preview and real throw agree on the first contact")
	clear_shot(game)
	game.world.add_obstacle(Vector2(2,19.94),Vector2(.10,1.5))
	game.fire_hook(Vector2.RIGHT)
	game._update_bolt(.35)
	check(not game.sim.attached and game.bolt_returning and game.hook_impact_kind=="rock","large frame sweeps still hit a thin wall and rebound into recovery")
	check(game.bolt_pos.x<2.1,"the projectile never tunnels through the wall")
	game.world.obstacles.clear()
	game.world.add_anchor(Vector2(0,23),0)
	game.fire_hook(game.direction_to_target(Vector2(0,23)))
	check(game.bolt_active and not game.bolt_returning and game.hook_flight.age==0,"another throw immediately interrupts recovery")
	game._update_bolt(.25)
	check(game.sim.attached,"interrupting recovery does not prevent a new catch")
	# Stage four launches two slightly fanned lines. The first valid contact
	# wins; the other line must wind back without creating a second attachment.
	game.model.profile = GameModel.fresh_profile()
	game.model.set_level(GameModel.HOOKS,4)
	game.start_run(false)
	clear_shot(game)
	var dual_target := Vector2(4,22)
	game.world.add_anchor(dual_target,0)
	game.fire_hook(game.direction_to_target(dual_target))
	for index in range(180):
		game._physics_process(HookFlight.STEP)
		if game.sim.attached: break
	var dual_states: Array = []
	if game.hook_volley!=null:
		for shot in game.hook_volley.shots: dual_states.append(shot["state"])
	check(game.sim.attached and dual_states.has("attached") and dual_states.has("returning"),"two-hook volley lets the first valid contact hold while the other returns")
	for index in range(180):
		if game.hook_volley==null: break
		game._physics_process(HookFlight.STEP)
	check(game.sim.attached and game.hook_volley==null,"losing hook finishes its return without disturbing the caught rope")
	game._process(HookFlight.STEP)
	check(not game.explorer.bolt_secondary.visible and not game.explorer.rope_secondary.visible,"the losing hook does not stay drawn after the volley ends")
	game.release_hook()
	clear_shot(game)
	game.fire_hook(Vector2.UP)
	game._physics_process(HookFlight.STEP)
	game.revive_used = true
	game.fail_run("test")
	check(game.hook_volley==null and not game.bolt_active and not game.bolt_returning,"a fall discards both lines so a revive cannot inherit a frozen hook")
	game.state = "play"
	# A wide grip radius may still catch, but the contact rests on the stone.
	game.world.add_anchor(Vector2(30,40),0)
	var grip: Dictionary = game.world.anchors[-1]
	var outline: PackedVector2Array = game.world.anchor_outline(grip)
	var graze: Dictionary = game.world.cast_hook(Vector2(26,40.3+grip["dimensions"].y*.5),Vector2(34,40.3+grip["dimensions"].y*.5),.76)
	check(not graze.is_empty() and not graze.get("blocked",false),"the upgraded grip radius still catches a near miss")
	if not graze.is_empty():
		var gap := INF
		for index in range(outline.size()):
			gap = minf(gap,Geometry2D.get_closest_point_to_segment(graze["contact"],outline[index],outline[(index+1)%outline.size()]).distance_to(graze["contact"]))
		check(gap<.01,"an assisted catch snaps onto the grip surface instead of hanging in the air")
	var slid: Vector2 = game.world.anchor_surface_point(grip,grip["pos"]+Vector2(0,-1.2-grip["dimensions"].y))
	check(Geometry2D.is_point_in_polygon(slid,outline) or slid.y>=grip["pos"].y-grip["dimensions"].y,"a slipping hook stops at the grip's lower edge")
	clear_shot(game)
	game.model.set_level(GameModel.HOOKS,1)
	game.fire_hook(Vector2.RIGHT)
	game._update_bolt(.8)
	check(not game.bolt_active and game.bolt_returning and game.bolt_pos.distance_to(game.sim.pos)<=5.501,"a miss stops at the live rope limit and begins winding back")
	var return_start: float = game.bolt_pos.distance_to(game.sim.pos)
	game._update_return(.04)
	check(game.bolt_pos.distance_to(game.sim.pos)<return_start and not game.sim.attached,"recovery moves toward the explorer without attaching or pulling")
	for index in range(60):
		if game.bolt_returning: game._update_return(HookFlight.STEP)
	check(not game.bolt_returning,"a missed hook returns promptly instead of disappearing at full extension")
	clear_shot(game)
	game.fire_hook(Vector2(1,1))
	game._update_bolt(.08)
	var saved_position: Vector2 = game.bolt_pos
	var saved_velocity: Vector2 = game.hook_flight.velocity
	var saved_age: float = game.hook_flight.age
	game.save_snapshot()
	game.resume_run()
	check(game.bolt_active and game.bolt_pos==saved_position and game.hook_flight.velocity==saved_velocity and is_equal_approx(game.hook_flight.age,saved_age),"mid-shot saves resume the same position, velocity and ballistic age")
	game._begin_hook_return("test")
	game._update_return(.02)
	saved_position = game.bolt_pos
	game.save_snapshot()
	game.resume_run()
	check(game.bolt_returning and not game.bolt_active and game.bolt_pos==saved_position,"save and resume preserve recovery without spawning a new shot")
	# Aim preview cost: a jittering finger does not rebuild the arc every frame,
	# a real turn does at once, and a steady aim still follows the moving hero.
	game.bolt_active = false
	game.bolt_returning = false
	game.sim.attached = false
	game.pressed = true
	game.touch_gesture = false
	game.aim_direction = Vector2.UP
	game.hud.shot_preview.clear()
	var refreshes := 0
	var last_refresh: float = game.hud.shot_preview_time
	for frame in range(60):
		game.elapsed += 1.0/60
		game.aim_direction = game.aim_direction.rotated(deg_to_rad(.3))
		game.hud.update_play()
		if game.hud.shot_preview_time!=last_refresh:
			refreshes += 1
			last_refresh = game.hud.shot_preview_time
	check(refreshes<=21,"a jittering aim rebuilds the arc preview at most about 20 times a second (%d)" % refreshes)
	game.elapsed += 1.0/60
	game.aim_direction = game.aim_direction.rotated(deg_to_rad(10))
	game.hud.update_play()
	check(is_equal_approx(game.hud.shot_preview_time,game.elapsed),"a real change of aim rebuilds the preview on the next frame")
	refreshes = 0
	last_refresh = game.hud.shot_preview_time
	for frame in range(60):
		game.elapsed += 1.0/60
		game.hud.update_play()
		if game.hud.shot_preview_time!=last_refresh:
			refreshes += 1
			last_refresh = game.hud.shot_preview_time
	check(refreshes>=15,"a steady aim still refreshes the preview as the hero moves (%d)" % refreshes)
	game.pressed = false
	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("hook-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	print("HOOK_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
