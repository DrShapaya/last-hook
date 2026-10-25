extends SceneTree

# Tester report fixes: smooth platform walking, menu swipes, slow motion
# feedback/upgrade/cooldown, and the camera zoom setting.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error("POLISH FAILED: "+description)

func touch_event(point: Vector2, down: bool, index: int = 3) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	root.push_input(event,true)

func drag_event(point: Vector2, index: int = 3) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event,true)

func lobby(game) -> LobbyView:
	return game.hud.content.get_child(0) as LobbyView

func screen_point(game, design: Vector2) -> Vector2:
	return lobby(game).get_global_transform()*design

func swipe(game, from_design: Vector2, travel_design: Vector2, steps: int = 4) -> void:
	var from := screen_point(game,from_design)
	var to := screen_point(game,from_design+travel_design)
	touch_event(from,true)
	await process_frame
	for step in range(1,steps+1):
		drag_event(from.lerp(to,float(step)/steps))
	await process_frame
	touch_event(to,false)
	await process_frame
	# Leave the anti-repeat window between deliberate swipes.
	await create_timer(.25).timeout

func walk_frames(game, frames: int, dt: float) -> Array[float]:
	var speeds: Array[float] = []
	for frame in range(frames):
		game._physics_process(dt)
		speeds.append(game.sim.vel.x)
	return speeds

func largest_step(values: Array[float], start: float) -> float:
	var largest := 0.0
	var previous := start
	for value in values:
		largest = maxf(largest,absf(value-previous))
		previous = value
	return largest

func air_release(game) -> void:
	# A hero hanging in open air, then released: the slow motion trigger.
	game._reset_input()
	game.state = "play"
	game.sim = RopeSim.new()
	game._configure_rope()
	game.sim.pos = Vector2(0,40)
	game.sim.attach(Vector2(0,43),4.0)
	game.anchor_id = -1
	game.bolt_active = false
	game.bolt_returning = false
	game.camera_y = 42
	game.release_hook()

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# Not a capture preview: the simulation and saves run as in the game.
	game.preview = false
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	root.size = Vector2i(540,960)
	await process_frame

	# --- 1. Platform walking ------------------------------------------------
	check(game.WALK_SPEED==float(game.model.balance["movement"]["walk_speed"]) and game.walk_acceleration==float(game.model.balance["movement"]["walk_acceleration"]),"walking parameters come from balance.json")
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.world.add_ledge(Vector2(0,30),4.0)
	game.sim.pos = Vector2(-1.2,30.15+SolidGeometry.BODY_HALF.y+.01)
	game.sim.vel = Vector2.ZERO
	game.sim.grounded = true
	game.sim.launched = true
	game.camera_y = 33
	game._position_camera()
	var dt := 1.0/120
	game.walk = 1.0
	var start_speeds := walk_frames(game,6,dt)
	check(start_speeds[0]>0 and start_speeds[0]<game.WALK_SPEED*.2,"walking eases in instead of jumping to full speed")
	var cruise := walk_frames(game,60,dt)
	check(cruise.max()<=game.WALK_SPEED+.0001 and cruise.max()>game.WALK_SPEED*.95,"walking reaches and never exceeds its configured speed")
	var approach := walk_frames(game,300,dt)
	var stop_x: float = game.sim.pos.x
	check(game.sim.grounded and absf(game.sim.vel.x)<.01 and stop_x<2.2 and stop_x>1.6,"the hero brakes to a stop at the platform edge without stepping off")
	var slowest_decline := largest_step(approach,cruise[-1])
	check(slowest_decline<=maxf(game.walk_deceleration,game.walk_edge_braking*2)*dt+.0001,"edge braking never stops the hero in a single frame")
	var braking_from := -1
	for index in range(approach.size()):
		if approach[index]<game.WALK_SPEED*.98: braking_from = index; break
	check(braking_from>0 and approach.slice(braking_from).max()<=approach[braking_from]+.0001,"edge braking is monotonic: no jitter or re-acceleration near the edge")
	for frame in range(60): game._physics_process(dt)
	check(absf(game.sim.pos.x-stop_x)<.01,"holding toward the edge keeps the hero still at the stop point")
	game.explorer.draw(game.sim,game.sim.pos,false,false,game.animation_time+1.0,false,1,{})
	game.walk = -1.0
	var turn := walk_frames(game,40,dt)
	check(turn[-1]<-game.WALK_SPEED*.9 and largest_step(turn,0.0)<=game.walk_turn_acceleration*dt+.0001,"reversing on a platform turns smoothly without a velocity jump")
	var animation_states: Array[String] = []
	var clock: float = game.animation_time
	for frame in range(20):
		game._physics_process(dt)
		clock += dt
		game.explorer.draw(game.sim,game.sim.pos,false,false,clock,false,1,{})
	animation_states.append(game.explorer.body.state)
	check(game.explorer.body.state=="walk" and game.explorer.body.facing<0,"the walk animation follows the actual walking direction")
	game.walk = 0.0
	var moving: float = game.sim.vel.x
	var stop := walk_frames(game,60,dt)
	check(absf(stop[-1])<.01 and absf(moving)>game.WALK_SPEED*.9 and largest_step(stop,moving)<=game.walk_deceleration*dt*1.15,"releasing the stick decelerates smoothly to a stop")
	for frame in range(90):
		clock += dt
		game.explorer.draw(game.sim,game.sim.pos,false,false,clock,false,1,{})
	check(game.explorer.body.state=="idle","standing still returns the animation to idle")
	var stride_rest: float = game.explorer.body.stride/PI
	check(absf(stride_rest-roundf(stride_rest))<.02,"the gait settles to a planted pose when the hero stops")
	game.walk = 0.0

	# --- 3. Slow motion -----------------------------------------------------
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.hud.show_play()
	air_release(game)
	var base_seconds: float = game.model.slowmo_seconds()
	check(game.focus_active() and is_equal_approx(game.focus_remaining,base_seconds),"releasing the rope starts slow motion")
	game.hud.update_play()
	check(game.hud.slowmo_indicator.state_name()=="active" and game.hud.slowmo_vignette.flash>.5,"activation shows the active timer and flashes the screen rim")
	var frames := 0
	var simulated := 0.0
	var before_y: float = game.sim.pos.y
	while game.focus_remaining>0 and frames<1000:
		game._physics_process(dt)
		frames += 1
	check(absf(frames*dt-base_seconds)<=dt*1.01,"slow motion lasts its duration in real time, not scaled time")
	check(game.focus_cooldown>0 and not game.focus_active(),"the end of slow motion starts its cooldown")
	game.hud.update_play()
	check(game.hud.slowmo_indicator.state_name()=="cooldown","the HUD shows the cooldown")
	air_release(game)
	check(not game.focus_active(),"a release during the cooldown cannot restart slow motion")
	var cooldown_frames := 0
	while game.focus_cooldown>0 and cooldown_frames<1000:
		game._physics_process(dt)
		cooldown_frames += 1
	check(absf(cooldown_frames*dt-game.model.slowmo_cooldown())<=dt*1.01,"the cooldown also counts real time")
	game.hud.update_play()
	check(game.hud.slowmo_indicator.state_name()=="ready","the HUD shows that slow motion is ready again")
	air_release(game)
	var remaining_before: float = game.focus_remaining
	game._physics_process(dt)
	game._start_focus()
	check(game.focus_remaining<remaining_before,"a running window can never be refilled")
	game.sim.attach(Vector2(0,43),4.0)
	game._end_focus()
	check(game.focus_remaining==0 and game.focus_cooldown>0,"catching a grip ends slow motion and starts the cooldown")
	game.sim.attached = false
	game.focus_cooldown = 0
	game.model.set_level(GameModel.SLOWMO,4)
	air_release(game)
	check(is_equal_approx(game.focus_remaining,float(game.model.balance["slowmo_seconds"][3])) and game.focus_remaining>base_seconds,"an upgraded level gives a longer window")
	frames = 0
	while game.focus_remaining>0 and frames<1000:
		game._physics_process(dt)
		frames += 1
	check(absf(frames*dt-float(game.model.balance["slowmo_seconds"][3]))<=dt*1.01,"the upgraded window also lasts exactly its real-time duration")
	# Landing ends the window: walking never runs slowed.
	game.focus_cooldown = 0
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.world.add_ledge(Vector2(0,30),4.0)
	game.sim = RopeSim.new()
	game._configure_rope()
	game.sim.pos = Vector2(0,30.15+SolidGeometry.BODY_HALF.y+.1)
	game.sim.attach(Vector2(0,34),3.0)
	game.release_hook()
	var landing_frames := 0
	while not game.sim.grounded and landing_frames<200:
		game._physics_process(dt)
		landing_frames += 1
	check(game.sim.grounded and not game.focus_active() and game.focus_cooldown>0 and landing_frames*dt<game.model.slowmo_seconds(),"landing ends slow motion")
	# Visual time slows with the world while the window is open.
	game.focus_cooldown = 0
	air_release(game)
	game.focus_blend = 1.0
	var anim_before: float = game.animation_time
	game._process(.1)
	check(absf(game.animation_time-anim_before-.1*game.model.slowmo_time_scale())<.02,"hero animation slows together with the world")

	# Upgrade: balance, persistence, max level and confirmation.
	var save_path := directory.path_join("polish-slowmo.json")
	for path in [save_path,save_path+".bak"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var economy := GameModel.new(save_path)
	economy.profile = GameModel.fresh_profile()
	check(economy.max_level(GameModel.SLOWMO)==4 and economy.balance["slowmo_seconds"]==[.7,1.0,1.35,1.75],"slow motion has four levels: 0,70 / 1,00 / 1,35 / 1,75 s")
	var durations: Array = economy.balance["slowmo_seconds"]
	var increasing := true
	for index in range(1,durations.size()): increasing = increasing and float(durations[index])>float(durations[index-1])
	check(increasing and float(durations[-1])<=1.8,"each level adds duration and the maximum stays short enough to stay fair")
	economy.profile["gold"] = 500
	check(economy.purchase(GameModel.SLOWMO).begins_with("Улучшено") and economy.level(GameModel.SLOWMO)==2 and economy.profile["gold"]==380,"the first slow motion level costs the same as other first steps")
	check(economy.purchase(GameModel.SLOWMO)=="Пройди первый акт","later levels wait for the next act like every track")
	var reloaded := GameModel.new(save_path)
	check(reloaded.level(GameModel.SLOWMO)==2 and is_equal_approx(reloaded.slowmo_seconds(),float(durations[1])),"the slow motion level survives a restart")
	reloaded.profile["gold"] = 100000
	reloaded.profile["reached_acts"] = 3
	reloaded.profile["summit_cleared"] = true
	for step in range(10): reloaded.purchase(GameModel.SLOWMO)
	check(reloaded.level(GameModel.SLOWMO)==4 and reloaded.cost(GameModel.SLOWMO)==0 and reloaded.purchase(GameModel.SLOWMO)=="Уже максимальный уровень","repeated purchases stop at the maximum level")
	check(GameModel.new(save_path).level(GameModel.SLOWMO)==4,"the maximum level is saved")
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["gold"] = 1000
	game.state = "menu"
	game.hud.select_menu("equipment")
	await process_frame
	var slowmo_row := false
	for label in game.hud.content.find_children("*","Label",true,false):
		if label.text=="Замедление": slowmo_row = true
	check(slowmo_row,"the equipment screen lists the slow motion upgrade")
	game.hud._buy_upgrade(GameModel.SLOWMO)
	await process_frame
	var bursts: Array = game.hud.content.find_children("*","Control",true,false).filter(func(node): return node is PlayGauges.Burst)
	var level_label := false
	for label in game.hud.content.find_children("*","Label",true,false):
		if label.text=="Ур. 2/4": level_label = true
	check(game.model.level(GameModel.SLOWMO)==2 and bursts.size()==1 and level_label,"a purchase is confirmed with a burst and the new level")
	game.model.set_level(GameModel.SLOWMO,4)
	game.hud.select_menu("equipment")
	await process_frame
	var max_label := false
	for label in game.hud.content.find_children("*","Label",true,false):
		if label.text=="Макс. ур. 4": max_label = true
	check(max_label,"the maximum level is labelled")

	# --- 4. Camera zoom -----------------------------------------------------
	var zoom_path := directory.path_join("polish-zoom.json")
	for path in [zoom_path,zoom_path+".bak"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var settings := GameModel.new(zoom_path)
	check(is_equal_approx(settings.camera_zoom(),1.0),"the default zoom keeps the original framing")
	settings.profile["camera_zoom"] = 1.3
	settings.save()
	check(is_equal_approx(GameModel.new(zoom_path).camera_zoom(),1.3),"the zoom setting persists across restarts")
	settings.profile["camera_zoom"] = "broken"
	settings.save()
	check(is_equal_approx(GameModel.new(zoom_path).camera_zoom(),1.0),"a corrupt zoom value falls back to the default")
	check(is_equal_approx(settings.snap_camera_zoom(9.0),float(settings.camera_zoom_levels()[-1])) and float(settings.camera_zoom_levels()[-1])<=1.35,"zoom is limited to safe steps")
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.focus_remaining = 0
	game.focus_blend = 0
	game.sim.pos = Vector2(0,20)
	game.sim.vel = Vector2.ZERO
	game.sim.grounded = false
	game.camera_dip = 0.0
	game.camera_y = 22.5
	for frame in range(120): game._move_camera(1.0/60)
	var base_size: float = game.camera.size
	var bottom_before: float = game.screen_bottom_y()
	check(is_equal_approx(base_size,game.camera_base_size),"100% zoom matches the original camera size")
	game.model.profile["camera_zoom"] = 1.3
	game._move_camera(1.0/60)
	check(game.camera.size<base_size and game.camera.size>base_size/1.3+.5,"zoom changes gradually rather than jumping")
	for frame in range(240): game._move_camera(1.0/60)
	check(absf(game.camera.size-base_size/1.3)<.05,"zoom settles at the selected scale")
	check(absf(game.screen_bottom_y()-bottom_before)<.001,"zoom never moves the fall edge")
	var view_bottom: float = game.camera.position.y-game.camera.size*.5
	var view_top: float = game.camera.position.y+game.camera.size*.5
	check(view_bottom>=bottom_before-.001 and view_top<=game.camera_y+game.camera_base_size*.5+.001,"the zoomed view stays inside the normal framing")
	check(game.sim.pos.y-view_bottom>=2.0 and view_top-game.sim.pos.y>8.0,"the hero stays visible with most of the view above them")
	# Falling toward the edge: the zoomed view follows down to the danger edge.
	game.sim.pos.y = bottom_before+.5
	for frame in range(120): game._move_camera(1.0/60)
	view_bottom = game.camera.position.y-game.camera.size*.5
	check(view_bottom<=game.sim.pos.y and absf(view_bottom-bottom_before)<.05,"near the fall edge the zoomed view shows the hero and the edge")
	# Slow motion adds a small punch-in on top of the setting.
	game.model.profile["camera_zoom"] = 1.0
	game.focus_blend = 1.0
	check(game.camera_zoom_target()>1.0 and game.camera_zoom_target()<1.1,"slow motion briefly tightens the view")
	game.focus_blend = 0.0
	# Landscape and narrow screens use the same vertical framing.
	for dimensions in [Vector2i(1280,800),Vector2i(432,960)]:
		root.size = dimensions
		await process_frame
		check(absf(game.screen_bottom_y()-(game.camera_y-game.camera_base_size*.5))<.001,"fall edge is independent of the %s screen" % dimensions)
	root.size = Vector2i(540,960)
	await process_frame
	# Settings UI: a segmented control that applies and saves the choice.
	game.model.profile = GameModel.fresh_profile()
	game.state = "menu"
	game.hud.menu_tab = "settings"
	game.hud.show_menu()
	await process_frame
	var zoom_button: Button = null
	for node in game.hud.content.find_children("*","Button",true,false):
		if node.text=="120%": zoom_button = node
	check(zoom_button!=null,"settings offer the camera scale")
	if zoom_button!=null:
		zoom_button.pressed.emit()
		check(is_equal_approx(game.model.camera_zoom(),1.2),"choosing a scale applies it")

	# --- 2. Menu swipes -----------------------------------------------------
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["active"] = {}
	game.state = "menu"
	game.lobby_location = 0
	game.hud.menu_tab = "expedition"
	game.hud.show_menu()
	await process_frame
	var start_center := lobby(game).start_button.position+lobby(game).start_button.size*.5
	# Sections run equipment | expedition | settings; the climb is the middle one.
	await swipe(game,start_center+Vector2(60,0),Vector2(-160,0))
	check(game.hud.menu_tab=="settings" and game.state=="menu","a left swipe over the start button switches section without starting a run")
	await process_frame
	var focused: Control = root.gui_get_focus_owner()
	check(not (focused is Button and (focused as Button).text in ["Снаряжение","Восхождение","Настройки"]),"after a swipe no section tab keeps a focus outline")
	await swipe(game,Vector2(270,600),Vector2(-160,0))
	check(game.hud.menu_tab=="settings","swiping past the last section stays there")
	await swipe(game,Vector2(270,600),Vector2(30,0),2)
	check(game.hud.menu_tab=="settings","a short drag is not a swipe")
	await swipe(game,Vector2(270,600),Vector2(60,-200))
	check(game.hud.menu_tab=="settings","a mostly vertical drag is not a swipe")
	await swipe(game,Vector2(270,600),Vector2(160,0))
	check(game.hud.menu_tab=="expedition","a right swipe goes back one section")
	await swipe(game,Vector2(270,600),Vector2(160,0))
	check(game.hud.menu_tab=="equipment","the next right swipe opens equipment")
	await swipe(game,Vector2(270,600),Vector2(160,0))
	check(game.hud.menu_tab=="equipment","swiping before the first section stays there")
	game.go_back()
	await process_frame
	check(game.hud.menu_tab=="expedition","Back returns to the main section")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	root.push_input(key)
	await process_frame
	check(game.hud.menu_tab=="settings","the keyboard switches sections too")
	await process_frame
	focused = root.gui_get_focus_owner()
	check(focused is Button and (focused as Button).text=="Настройки","after a key switch the new section's tab has focus")
	game.go_back()
	await process_frame
	# Swiping the route card selects neighbouring routes, including locked ones.
	await swipe(game,lobby(game).card_rect.get_center(),Vector2(-160,0))
	check(game.hud.menu_tab=="expedition" and game.lobby_location==1 and game.selected_location==0,"a swipe over the route card shows the next route without selecting a locked one")
	var locked_start: Button = lobby(game).start_button
	check(locked_start.disabled and not game.model.profile["locations"].has(1),"a locked route cannot be started")
	await swipe(game,lobby(game).card_rect.get_center(),Vector2(-160,0))
	await swipe(game,lobby(game).card_rect.get_center(),Vector2(-160,0))
	check(game.lobby_location==game.model.balance["locations"].size()-1,"route swipes stop at the last route")
	var right := InputEventKey.new()
	right.keycode = KEY_LEFT
	right.physical_keycode = KEY_LEFT
	right.pressed = true
	root.push_input(right)
	await process_frame
	check(game.lobby_location==game.model.balance["locations"].size()-2,"arrow keys pick routes on the main section")
	for step in range(4): game.cycle_location(-1)
	check(game.lobby_location==0 and game.selected_location==0,"routes stop at the first one and an owned route is selected")
	var tap_point := screen_point(game,lobby(game).start_button.position+lobby(game).start_button.size*.5)
	touch_event(tap_point,true)
	await process_frame
	touch_event(tap_point,false)
	await process_frame
	check(game.state=="play","a plain tap still starts the climb")

	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("polish-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	print("POLISH_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
