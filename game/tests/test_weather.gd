extends SceneTree

# WeatherBands: bands, phases and force on the baked layouts of all routes.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("WEATHER FAILED: "+description)

func baked(location: int, route: int) -> MountainWorld:
	var spec := LevelCatalog.route(location,route)
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(int(spec["seed"]),location,0,false,route)
	var level := LevelBake.find(location,route,world.generation_version)
	if level!=null: world.load_bake(level)
	else: push_error("WEATHER no bake for %d/%d" % [location,route])
	return world

# A time at which the band's own clock reads `local` inside a cycle.
func time_for(band: Dictionary, local: float) -> float:
	var cycle := float(band["calm"])+float(band["telegraph"])+float(band["active"])
	return cycle*2.0-float(band["phase_shift"])+local

func run_tests() -> void:
	var worlds: Array[MountainWorld] = []
	for location in range(3):
		for route in range(3): worlds.append(baked(location,route))
	check(worlds.size()==9 and worlds[0].bake!=null,"all nine baked levels load")
	test_bands_per_location(worlds)
	test_deterministic(worlds)
	test_phase_cycle(worlds)
	test_wind_shape(worlds)
	test_presence_edges(worlds)
	test_endless_cycle(worlds)
	test_no_weather_layouts()
	test_campfires(worlds)
	test_fields_inert(worlds)
	test_other_hazards_kept(worlds)
	test_no_field_visuals()
	await test_wind_in_play()
	test_cold_rates()
	test_cold_only_blizzard()
	test_cold_slows()
	await test_cold_in_play()
	test_overlay_amounts()
	test_overlay_haze()
	test_overlay_reduce()
	test_haze_caps()
	test_campfire_built()
	await test_hud_chip()
	await test_hud_cold()
	await test_first_toast()
	await test_phase_feedback()
	test_band_memo(worlds)
	test_endless_campfires()
	test_direction_latch()
	test_overlay_warm_up()
	test_warm_up_emits_on_every_preset()
	await test_eased_drive()
	test_wind_scan_sliced()
	test_campfire_reduce()
	print("WEATHER ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func test_bands_per_location(worlds: Array[MountainWorld]) -> void:
	for i in range(worlds.size()):
		var location := i/3
		var weather := WeatherBands.new(worlds[i].layout)
		check(weather.enabled(),"route %d weather enabled" % i)
		var bands := weather.bands_of_cycle(0)
		check(bands.size()==2,"route %d has two bands" % i)
		for band in bands:
			check(band["kind"]==WeatherBands.KIND_BY_LOCATION[location],"route %d kind" % i)
		check(bands[0]["act"]==1 and bands[1]["act"]==2,"route %d acts 1 and 2" % i)
		var mid: Dictionary = weather.band_at((float(bands[0]["bottom"])+float(bands[0]["top"]))*.5)
		check(not mid.is_empty() and mid["act"]==1,"route %d band_at finds the act 1 band" % i)
		check(weather.band_at(float(bands[0]["bottom"])-1.0).is_empty(),"route %d no band below" % i)
		check(not weather.band_at(float(bands[0]["bottom"])-1.0,2.0).is_empty(),"route %d margin reaches the band" % i)
	var w := WeatherBands.new(worlds[0].layout)
	var b := w.bands_of_cycle(0)
	check(absf(b[0]["bottom"]-52.0)<.01 and absf(b[0]["top"]-70.0)<.01,"L0 act 1 is 52..70")
	check(absf(b[1]["bottom"]-86.0)<.01 and absf(b[1]["top"]-116.8)<.01,"L0 act 2 is 86..116.8")

func test_deterministic(worlds: Array[MountainWorld]) -> void:
	var a := WeatherBands.new(worlds[4].layout)
	var b := WeatherBands.new(worlds[4].layout)
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var same := true
	for n in range(50):
		var y := random.randf_range(0.0,170.0)
		var time := random.randf_range(0.0,200.0)
		var band_a := a.band_at(y)
		same = same and band_a==b.band_at(y)
		if not band_a.is_empty():
			var gust := int(a.phase(band_a,time)["gust"])
			same = same and a.direction(band_a,gust)==b.direction(band_a,gust) and a.strength(band_a,time)==b.strength(band_a,time)
	check(same,"two instances agree on bands, direction and strength")

func test_phase_cycle(worlds: Array[MountainWorld]) -> void:
	var weather := WeatherBands.new(worlds[0].layout)
	var band: Dictionary = weather.bands_of_cycle(0)[1]
	check(band["kind"]=="wind" and band["active"]==9.0,"L0 act 2 is the 9 s wind")
	var base := time_for(band,0.0)
	var first: Dictionary = weather.phase(band,base+.01)
	check(first["name"]=="calm" and absf(float(first["left"])-5.99)<.01,"calm starts the clock")
	check(weather.phase(band,base+5.9)["name"]=="calm" and weather.phase(band,base+6.1)["name"]=="telegraph","calm lasts 6 s")
	check(weather.phase(band,base+7.9)["name"]=="telegraph" and weather.phase(band,base+8.1)["name"]=="active","telegraph lasts 2 s")
	check(weather.phase(band,base+16.9)["name"]=="active" and weather.phase(band,base+17.1)["name"]=="calm","active lasts 9 s")
	check(float(weather.phase(band,base+1.0)["left"])>float(weather.phase(band,base+2.0)["left"]),"left decreases")
	check(int(weather.phase(band,base+17.1)["gust"])==int(weather.phase(band,base+.1)["gust"])+1,"gust grows by one per cycle")
	check(absf(float(weather.phase(band,base+12.5)["progress"])-(4.5/9.0))<.01,"active progress")

func test_wind_shape(worlds: Array[MountainWorld]) -> void:
	var weather := WeatherBands.new(worlds[0].layout)
	var band: Dictionary = weather.bands_of_cycle(0)[1]
	var point := Vector2(0.0,(float(band["bottom"])+float(band["top"]))*.5)
	var base := time_for(band,0.0)
	var nominal := float(band["force"])*WeatherBands.GRAVITY
	check(weather.wind_at(point,base+3.0)==Vector2.ZERO,"no wind in calm")
	check(weather.wind_at(point,base+7.0)==Vector2.ZERO,"no wind in telegraph")
	var start := base+8.0
	check(absf(weather.wind_at(point,start+.1).x)<.3*nominal,"gust ramps in")
	var strong := true
	for k in range(15):
		var x := weather.wind_at(point,start+1.0+float(k)*.4).x
		strong = strong and absf(x)>=.8*nominal-.001 and absf(x)<=1.15*nominal+.001
	check(strong,"mid-gust stays within the breath")
	check(absf(weather.wind_at(point,start+8.95).x)<.3*nominal,"gust ramps out")
	var gust := int(weather.phase(band,start+4.0)["gust"])
	check(signf(weather.wind_at(point,start+4.0).x)==weather.direction(band,gust),"wind follows direction")
	check(weather.wind_at(Vector2(0.0,float(band["bottom"])-1.0),start+4.0)==Vector2.ZERO,"no wind outside the band")
	var plus := 0
	for g in range(40): plus += 1 if weather.direction(band,g)>0.0 else 0
	check(plus>5 and plus<35,"both directions occur")

func test_presence_edges(worlds: Array[MountainWorld]) -> void:
	var weather := WeatherBands.new(worlds[0].layout)
	var band: Dictionary = weather.bands_of_cycle(0)[1]
	var time := time_for(band,0.0)+12.0
	var below := Vector2(0.0,float(band["bottom"])-2.0)
	var info := weather.presence(below,time)
	check(info["kind"]=="wind" and not info["inside"] and float(info["amount"])>0.0 and float(info["amount"])<1.0,"edge presence is partial")
	check(weather.wind_at(below,time)==Vector2.ZERO,"no force in the edge")
	var inside := weather.presence(Vector2(0.0,float(band["bottom"])+2.0),time)
	check(inside["inside"] and inside["amount"]==1.0,"full presence inside during the gust")
	check(weather.presence(Vector2(0.0,float(band["bottom"])-5.0),time)["kind"]=="","no presence beyond the edge")
	var calm_info := weather.presence(Vector2(0.0,float(band["bottom"])+2.0),time_for(band,1.0))
	check(calm_info["amount"]==0.0,"calm shows nothing")
	var tele := weather.presence(Vector2(0.0,float(band["bottom"])+2.0),time_for(band,7.0))
	check(absf(float(tele["amount"])-.2)<.01,"telegraph shows progress*0.4")
	var point := Vector2(0.0,float(band["bottom"])+2.0)
	check(weather.calm_for(point,time_for(band,1.0),3.0) and not weather.calm_for(point,time_for(band,1.0),5.5),"calm_for needs lead time")
	check(not weather.calm_for(point,time_for(band,7.0),0.0) and weather.calm_for(Vector2(0.0,1.0),time,5.0),"calm_for: telegraph no, no band yes")

func test_endless_cycle(worlds: Array[MountainWorld]) -> void:
	for i in range(worlds.size()):
		var layout: ExpeditionLayout = worlds[i].layout
		var weather := WeatherBands.new(layout)
		var total := float(layout.spans[-1]["y_end"])
		var first := weather.bands_of_cycle(0)[0]
		var y := (float(first["bottom"])+float(first["top"]))*.5
		var next := weather.band_at(y+total)
		check(not next.is_empty() and next["cycle"]==1 and next["act"]==1,"route %d band repeats in cycle 1" % i)
		check(absf((float(next["top"])-float(next["bottom"]))-(float(first["top"])-float(first["bottom"])))<.001,"route %d cycle 1 band has the same length" % i)
		check(next["seed"]!=first["seed"],"route %d cycle 1 has its own seed" % i)

func test_no_weather_layouts() -> void:
	for layout in [LegacyMountainLayout.new(),PracticeLayout.new()]:
		var weather := WeatherBands.new(layout)
		check(not weather.enabled() and weather.band_at(50.0)=={} and weather.wind_at(Vector2(0,50),3.0)==Vector2.ZERO,"layout without weather")
		check(weather.presence(Vector2(0,50),3.0)["kind"]=="" and weather.calm_for(Vector2(0,50),3.0,9.0) and weather.campfires().is_empty(),"no-weather layout is inert")

func test_campfires(worlds: Array[MountainWorld]) -> void:
	for i in range(worlds.size()):
		var weather := WeatherBands.new(worlds[i].layout)
		var fires := weather.campfires()
		if i/3==2:
			var covered := true
			for band in weather.bands_of_cycle(0):
				var has := false
				for fire in fires: has = has or (fire.y>=float(band["bottom"])-2.0 and fire.y<=float(band["top"])+2.0)
				covered = covered and has
			check(covered,"winter route %d has a campfire in each band" % i)
		else:
			check(fires.is_empty(),"route %d has no campfires" % i)

# The old small weather pockets (field hazards) are inert: weather is WeatherBands now.
func test_fields_inert(worlds: Array[MountainWorld]) -> void:
	var storms := 0
	for i in range(worlds.size()):
		var hazards: ActHazards = worlds[i].hazards
		for hazard in hazards.list:
			if hazard["kind"]!="field": continue
			storms += 1
			var rect: Rect2 = hazard["rect"]
			var moved := false
			var haze := 0.0
			for step in range(300):
				var effect := hazards.step(step*.1,rect.get_center(),false,int(hazard.get("branch_anchor",-1)),int(hazard.get("branch_anchor",-1)))
				moved = moved or effect["force"]!=Vector2.ZERO
				haze = maxf(haze,float(effect["haze"]))
			check(not moved and haze==0.0,"route %d field %d gives no force or haze" % [i,hazard["id"]])
	var l1 := worlds[3].hazards
	var storm := {}
	for hazard in l1.list:
		if hazard["def"]=="storm_cycle": storm = hazard
	check(storms>0 and not storm.is_empty(),"L1 r0 still lists its storm_cycle by id")
	if storm.is_empty(): return
	var centre: Vector2 = (storm["rect"] as Rect2).get_center()
	var phases := {}
	var calm_all := true
	for step in range(400):
		var time := step*.1
		phases[l1.phase(storm,time)["name"]] = true
		check(l1.step(time,centre,false)["force"]==Vector2.ZERO,"storm force is zero at t=%.1f" % time)
		calm_all = calm_all and l1.calm_for(centre,time,3.0)
		check(not l1.hint(centre,time).contains("Буря") and not l1.hint(centre,time).contains("Ветров") and not l1.hint(centre,time).contains("метели"),"no field hint at t=%.1f" % time)
	check(calm_all,"calm_for ignores fields")

# Contact, falling and collapse hazards keep working.
func test_other_hazards_kept(worlds: Array[MountainWorld]) -> void:
	var knocked := false
	var cracked := false
	var collapsed := false
	for world in worlds:
		var hazards: ActHazards = world.hazards
		for hazard in hazards.list:
			match str(hazard["kind"]):
				"contact":
					for step in range(400):
						if not hazards.step(step*.1,hazard["pos"],false)["knock"].is_empty(): knocked = true
				"falling":
					var branch := int(hazard.get("branch_anchor",-1))
					if branch<0: continue
					check(hazards.phase(hazard,0.0)["name"]=="calm","icicle %d starts calm" % hazard["id"])
					hazards.step(0.0,Vector2(0,0),false,branch)
					if hazards.phase(hazard,.5)["name"]=="telegraph": cracked = true
				"collapse":
					var ledge: Dictionary = world.layout.ledges[int(hazard["ledge"])]
					var spot := Vector2((float(ledge["left"])+float(ledge["right"]))*.5,float(ledge["top"])+SolidGeometry.BODY_HALF.y)
					hazards.step(1.0,spot,true)
					var done: Array = hazards.step(1.0+float(hazard["telegraph_time"])+.1,spot,true)["collapsed"]
					if done.has(hazard["id"]): collapsed = true
	# The baked levels carry no contact hazards: use seeded desert worlds for the cactus.
	for seed_number in range(20):
		var seeded := MountainWorld.new()
		seeded.visuals_enabled = false
		root.add_child(seeded)
		seeded.setup(900+seed_number,1,0)
		seeded.generate_to(146.0,true,float(LevelCatalog.level(1)["height_units"]))
		for hazard in seeded.hazards.list:
			if hazard["def"]!="cactus": continue
			var effect: Dictionary = seeded.hazards.step(0.0,hazard["pos"],false)
			check(not effect["knock"].is_empty() and effect["force"]==Vector2.ZERO,"a cactus knocks on contact")
			check(seeded.hazards.knock_message(int(hazard["id"]))=="Кактус уколол — крюк сорвался","cactus knock message")
			knocked = true
		seeded.free()
		if knocked: break
	check(knocked,"a contact hazard still knocks")
	check(cracked,"an icicle still cracks when its branch is held")
	check(collapsed,"a sand bridge still collapses under the hero")
	var l1 := worlds[3].hazards
	check(l1.knock_message(0)!="" ,"knock_message by id still works")

# Fields build no visuals at all.
func test_no_field_visuals() -> void:
	var spec := LevelCatalog.route(0,0)
	var world := MountainWorld.new()
	world.visuals_enabled = true
	root.add_child(world)
	world.setup(int(spec["seed"]),0,0,false,0)
	var level := LevelBake.find(0,0,world.generation_version)
	if level!=null: world.load_bake(level)
	check(world.hazard_visuals!=null,"visual world has hazard visuals")
	if world.hazard_visuals!=null:
		world.hazard_visuals.build_near(60.0,-1,80.0)
		var fields := 0
		for hazard in world.layout.hazards:
			if hazard["kind"]=="field": fields += 1
		check(fields>0,"L0 r0 still lists a wind pocket")
		for id in world.hazard_visuals.built.keys():
			check(world.layout.hazards[id]["kind"]!="field","built hazard %d is not a field" % id)
		for hazard in world.layout.hazards:
			if hazard["kind"]=="field": check(not world.hazard_visuals.built.has(hazard["id"]),"field %d has no visuals" % hazard["id"])
	world.queue_free()

# A run on L0 r0 with the main scene: wind pushes the airborne hero, the aim
# forecast and the real throw agree.
func test_wind_in_play() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.set_route_choice(0,0)
	game.selected_location = 0
	game.start_run(false)
	check("weather" in game.world and game.world.weather!=null and game.world.weather.enabled(),"the run world has its weather bands")
	if not ("weather" in game.world) or game.world.weather==null or not game.world.weather.enabled():
		game.queue_free()
		return
	var weather: WeatherBands = game.world.weather
	var band: Dictionary = weather.bands_of_cycle(0)[1]
	var gust_start := float(band["calm"])+float(band["telegraph"])
	var mid_gust := time_for(band,gust_start+float(band["active"])*.5)
	var gust := int(weather.phase(band,mid_gust)["gust"])
	var side := weather.direction(band,gust)
	test_hero_grounded_still(game,band,mid_gust)
	test_hero_pushed_airborne(game,band,mid_gust,side)
	test_forecast_matches_flight(game,band,mid_gust,true)
	test_forecast_matches_flight(game,band,time_for(band,gust_start+float(band["active"])-.2),false)
	game.queue_free()
	await process_frame

func reset_hero(game, start: Vector2, clock: float, grounded: bool) -> void:
	game.sim = RopeSim.new()
	game._configure_rope()
	game.sim.pos = start
	game.sim.highest = start.y
	game.sim.flight_peak = start.y
	game.sim.grounded = grounded
	game.bolt_active = false
	game.bolt_returning = false
	game.hook_volley = null
	game.anchor_id = -1
	game.focus_remaining = 0.0
	game.hazard_clock = clock
	game.state = "play"

func run_hero(game, start: Vector2, clock: float, grounded: bool, seconds: float) -> Vector2:
	reset_hero(game,start,clock,grounded)
	for index in range(roundi(seconds/HookFlight.STEP)): game._physics_process(HookFlight.STEP)
	return game.sim.pos

# On a support the wind does not move the hero.
func test_hero_grounded_still(game, band: Dictionary, clock: float) -> void:
	var best := {}
	for ledge in game.world.ledges:
		var top := float(ledge["top"])
		if top<float(band["bottom"])+1.0 or top>float(band["top"])-1.0: continue
		if best.is_empty() or float(ledge["right"])-float(ledge["left"])>float(best["right"])-float(best["left"]): best = ledge
	check(not best.is_empty(),"L0 act 2 band has a ledge")
	if best.is_empty(): return
	# A hair above the deck: Vector2 is float32 and would round the hero just under it.
	var spot := Vector2((float(best["left"])+float(best["right"]))*.5,float(best["top"])+SolidGeometry.BODY_HALF.y+.0005)
	var windy: Vector2 = run_hero(game,spot,clock,true,.5)
	var grounded: bool = game.sim.grounded
	var held: WeatherBands = game.world.weather
	game.world.weather = null
	var still: Vector2 = run_hero(game,spot,clock,true,.5)
	game.world.weather = held
	check(grounded and absf(windy.x-still.x)<.001,"a grounded hero is not pushed (%.4f)" % (windy.x-still.x))

func clear_geometry(game) -> void:
	game.world.anchors.clear()
	game.world.layout.bins.clear()
	game.world.obstacles.clear()
	game.world.ledges.clear()

# In the air the gust carries the hero toward its direction.
func test_hero_pushed_airborne(game, band: Dictionary, clock: float, side: float) -> void:
	clear_geometry(game)
	var start := Vector2(0,(float(band["bottom"])+float(band["top"]))*.5)
	var pushed: Vector2 = run_hero(game,start,clock,false,.5)
	var held: WeatherBands = game.world.weather
	game.world.weather = null
	var calm: Vector2 = run_hero(game,start,clock,false,.5)
	game.world.weather = held
	var drift := (pushed.x-calm.x)*side
	check(drift>.5,"the airborne hero drifts with the gust in 0.5 s (%.3f)" % drift)

# The aim forecast shows where the real throw catches, in and at the end of a gust.
func test_forecast_matches_flight(game, band: Dictionary, clock: float, mid: bool) -> void:
	clear_geometry(game)
	var start := Vector2(0,(float(band["bottom"])+float(band["top"]))*.5)
	reset_hero(game,start,clock,false)
	var label := "mid-gust" if mid else "gust end"
	check(game.weather_wind()!=Vector2.ZERO,"%s: wind blows at the throw" % label)
	var target := start+Vector2(4,2)
	game.world.add_anchor(target,0)
	var direction: Vector2 = game.direction_to_target(target)
	var prediction: Dictionary = game.predict_shot(direction)
	check(not prediction["collision"].is_empty(),"%s: the forecast reaches the grip" % label)
	if mid:
		var held: WeatherBands = game.world.weather
		game.world.weather = null
		var windless: Dictionary = game.predict_shot(direction)
		game.world.weather = held
		check(Vector2(windless["contact"]).distance_to(prediction["contact"])>.05,"%s: the forecast differs from a windless arc" % label)
	game.fire_hook(direction)
	for index in range(240):
		game._physics_process(HookFlight.STEP)
		if not game.bolt_active: break
	check(game.sim.attached,"%s: the real throw catches the grip" % label)
	var gap: float = game.anchor_contact.distance_to(prediction["contact"])
	check(gap<=.05,"%s: forecast and real contact agree (%.4f)" % [label,gap])
	game.release_hook()


func blizzard_presence(phase_name: String, inside: bool = true) -> Dictionary:
	return {"kind":"blizzard","amount":1.0,"phase":{"name":phase_name},"direction":1.0,"inside":inside}

func run_cold(meter: ColdMeter, seconds: float, presence: Dictionary, grounded: bool, fire: bool) -> void:
	for index in range(roundi(seconds*10)): meter.step(.1,presence,grounded,fire)

func test_cold_rates() -> void:
	var meter := ColdMeter.new()
	run_cold(meter,16.0,blizzard_presence("active"),false,false)
	check(absf(meter.cold-1.0)<.02,"16 s of active blizzard fills the cold")
	run_cold(meter,2.5,blizzard_presence("active"),false,true)
	check(absf(meter.cold)<.02,"2.5 s at a campfire clears it")
	meter.cold = .5
	run_cold(meter,3.0,blizzard_presence("calm"),true,false)
	check(absf(meter.cold-(.5-3.0/6.0))<.02,"grounded in calm drains 1/6 per second")
	meter.cold = .5
	run_cold(meter,4.0,{"kind":""},false,false)
	check(absf(meter.cold-(.5-.5))<.02,"outside the band drains 1/8 per second")
	meter.cold = .5
	run_cold(meter,4.0,blizzard_presence("telegraph"),false,false)
	check(absf(meter.cold-(.5+4.0/40.0))<.02,"telegraph adds 1/40 per second")
	meter.cold = .5
	run_cold(meter,6.0,blizzard_presence("calm"),false,false)
	check(absf(meter.cold-(.5-6.0/30.0))<.02,"calm in the air inside the band drains 1/30")
	meter.cold = .5
	run_cold(meter,4.0,blizzard_presence("active",false),false,false)
	check(absf(meter.cold-.0)<.02,"the 4 m edge counts as outside")

func test_cold_only_blizzard() -> void:
	for kind in ["wind","sand_storm"]:
		var meter := ColdMeter.new()
		run_cold(meter,10.0,{"kind":kind,"amount":1.0,"phase":{"name":"active"},"inside":true},false,false)
		check(meter.cold==0.0,"%s does not raise the cold" % kind)

func test_cold_slows() -> void:
	var meter := ColdMeter.new()
	meter.cold = 1.0
	check(is_equal_approx(meter.swing_scale(),.65) and is_equal_approx(meter.reel_scale(),.65),"full cold: swing and reel x0.65")
	check(is_equal_approx(meter.throw_scale(),.75) and is_equal_approx(meter.walk_scale(),.7),"full cold: throw x0.75, walk x0.7")
	meter.cold = 0.0
	check(meter.swing_scale()==1.0 and meter.throw_scale()==1.0 and meter.walk_scale()==1.0,"no cold, no slowdown")

func new_game(location: int, route: int):
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.set_route_choice(location,route)
	game.selected_location = location
	game.start_run(false)
	return game

# Fresh game runs: cold slows the real hero, survives save/resume, resets on start.
func test_cold_in_play() -> void:
	var game = await new_game(2,0)
	var base_swing: float = game.base_swing_force
	var length: float = game.sim.maximum_length
	game.cold.cold = 1.0
	game._physics_process(HookFlight.STEP)
	check(game.cold.cold<1.0 and game.cold.cold>.95,"cold drains outside the band in play")
	game.cold.cold = 1.0
	game.state = "play"
	game._physics_process(HookFlight.STEP)
	check(absf(game.sim.swing_force-base_swing*game.cold.swing_scale())<.0001 and game.sim.swing_force<base_swing,"swing force follows the cold")
	check(is_equal_approx(game.sim.maximum_length,length),"rope length is unchanged by cold")
	check(absf(game.throw_speed()-game.model.throw_speed()*game.cold.throw_scale())<.0001,"throw speed follows the cold")
	game.cold.cold = 1.0
	check(game.walk_velocity(0.0,1.0,10.0)<=game.WALK_SPEED*.7+.0001 or not game.ground_ahead(1.0),"walking target is slowed")
	var fire: Vector2 = game.world.weather.campfires()[0]
	game.sim.pos = fire
	check(game.near_campfire(),"near_campfire at a campfire")
	game.sim.pos = fire+Vector2(2.5,0)
	check(not game.near_campfire(),"not near a campfire 2.5 m away")
	game.cold.cold = .6
	var clock: float = game.hazard_clock
	var phase_name = game.world.weather.phase(game.world.weather.bands_of_cycle(0)[0],clock)["name"]
	game.run_id = "cold-test"
	game.save_snapshot()
	var snapshot: Dictionary = game.model.profile["active"].duplicate(true)
	check(not snapshot.is_empty() and is_equal_approx(float(snapshot.get("cold",-1.0)),.6),"snapshot keeps the cold")
	game.queue_free()
	await process_frame
	var again = await new_game(2,0)
	again.model.profile["active"] = snapshot
	again.resume_run()
	check(is_equal_approx(again.cold.cold,.6),"resume restores the cold")
	check(is_equal_approx(again.hazard_clock,clock),"resume restores the hazard clock")
	var band: Dictionary = again.world.weather.bands_of_cycle(0)[0]
	check(again.world.weather.phase(band,again.hazard_clock)["name"]==phase_name,"resume keeps the weather phase")
	again.cold.cold = .3
	again.start_run(false)
	check(again.cold.cold==0.0,"start_run resets the cold")
	again.queue_free()
	await process_frame

# --- Full-screen weather layer and campfires ---------------------------------

func storm(kind: String, phase_name: String, amount: float, strength: float = 1.0, inside: bool = true) -> Dictionary:
	return {"kind":kind,"amount":amount,"phase":{"name":phase_name,"progress":.5,"left":3.0,"gust":0},
		"direction":1.0,"inside":inside,"strength":strength}

func new_overlay(particles: String, preset: String, reduce: bool) -> WeatherOverlay:
	var overlay := WeatherOverlay.new()
	root.add_child(overlay)
	overlay.configure(particles,preset,reduce)
	return overlay

func run_overlay(overlay: WeatherOverlay, presence: Dictionary, seconds: float, cold: float = 0.0) -> void:
	for index in range(roundi(seconds*60.0)): overlay.update(presence,cold,Vector2(270,600),.045,1.0/60.0)

func test_overlay_amounts() -> void:
	var overlay := new_overlay("full","high",false)
	check(overlay.particle_amount()==160,"full/high: 160 particles (%d)" % overlay.particle_amount())
	overlay.configure("reduced","battery",false)
	check(overlay.particle_amount()==40,"reduced/battery: 40 particles (%d)" % overlay.particle_amount())
	overlay.configure("full","balanced",true)
	check(overlay.particle_amount()==45,"full/balanced with reduce_effects: 45 particles (%d)" % overlay.particle_amount())
	overlay.configure("full","ultra",false)
	check(overlay.particle_amount()==160,"ultra: 160 particles")
	overlay.configure("reduced","high",false)
	check(overlay.particle_amount()==40,"particles setting reduced: 40")
	var hud := GameHud.new()
	check(overlay.layer==hud.layer-1,"weather layer is right below the HUD")
	hud.free()
	for child in ["Штрихи","Частицы","Мгла","Иней"]:
		check(overlay.get_node_or_null(child)!=null,"overlay has %s" % child)
	run_overlay(overlay,{"kind":""},.5)
	for child in ["Штрихи","Частицы","Мгла","Иней"]:
		check(not (overlay.get_node(child) as CanvasItem).visible,"%s hidden without weather" % child)
	run_overlay(overlay,storm("wind","active",1.0),.5)
	check((overlay.get_node("Частицы") as GPUParticles2D).visible and is_equal_approx((overlay.get_node("Частицы") as GPUParticles2D).amount_ratio,1.0),"wind: particles at full ratio")
	check((overlay.get_node("Штрихи") as CanvasItem).visible,"wind: streaks shown")
	overlay.queue_free()

func test_overlay_haze() -> void:
	var overlay := new_overlay("full","high",false)
	run_overlay(overlay,storm("sand_storm","active",1.0),3.0)
	check(overlay.haze_strength()==1.0,"sand storm active: full haze within 3 s (%.3f)" % overlay.haze_strength())
	check((overlay.get_node("Мгла") as CanvasItem).visible,"sand storm: haze shown")
	run_overlay(overlay,storm("sand_storm","calm",0.0),3.0)
	check(overlay.haze_strength()<.05,"haze settles within 3 s after the storm (%.3f)" % overlay.haze_strength())
	run_overlay(overlay,storm("sand_storm","telegraph",.2),4.0)
	check(absf(overlay.haze_strength()-.2)<.01,"telegraph haze follows the warning (%.3f)" % overlay.haze_strength())
	run_overlay(overlay,storm("sand_storm","active",1.0),3.0)
	run_overlay(overlay,{"kind":""},2.0)
	check(overlay.haze_strength()<.05,"haze leaves within 2 s on leaving the band (%.3f)" % overlay.haze_strength())
	run_overlay(overlay,storm("wind","active",1.0),3.0)
	check(overlay.haze_strength()==0.0,"wind has no haze")
	run_overlay(overlay,storm("blizzard","active",1.0),4.0,.8)
	check(overlay.haze_strength()>.3 and overlay.haze_strength()<=.45,"blizzard haze at most 0.45 (%.3f)" % overlay.haze_strength())
	check((overlay.get_node("Иней") as CanvasItem).visible,"cold shows the frost")
	run_overlay(overlay,{"kind":""},3.0,0.0)
	check(not (overlay.get_node("Иней") as CanvasItem).visible,"no cold, no frost")
	overlay.queue_free()

# The haze never passes its caps, whatever billow, sheet and breath do:
# inside the clear circle the veil, beside/below the hero 0.6, from 13 m
# above 0.9; a blizzard 0.45 everywhere. The shader carries the same formula.
func test_haze_caps() -> void:
	check(WeatherOverlay.HAZE_SHADER.contains("min(body+sheet*(.16+.24*ring), max(cap*ring, veil))*strength") and WeatherOverlay.HAZE_SHADER.contains(".84+.12*billow+breath*.04"),"the haze shader keeps the capped formula")
	var worst_inside := [0.0,0.0]
	var worst_below := 0.0
	var worst_side := 0.0
	var worst_above := 0.0
	var worst_blizzard := 0.0
	var top_full := 1.0
	for billow in [0.0,.5,1.0]:
		for sheet in [0.0,.5,1.0]:
			for breath in [-1.0,0.0,1.0]:
				for radius in [0.0,3.0,6.4]:
					worst_inside[0] = maxf(worst_inside[0],WeatherOverlay.haze_alpha(Vector2(radius*.6,-radius*.8),billow,sheet,breath,true,1.0))
					worst_inside[1] = maxf(worst_inside[1],WeatherOverlay.haze_alpha(Vector2(0,radius),billow,sheet*.8,breath,false,1.0))
				for below in [7.0,9.0,12.0,20.0]:
					worst_below = maxf(worst_below,WeatherOverlay.haze_alpha(Vector2(0,-below),billow,sheet,breath,true,1.0))
					worst_side = maxf(worst_side,WeatherOverlay.haze_alpha(Vector2(below,0),billow,sheet,breath,true,1.0))
				for above in [8.0,10.0,13.0,18.0]:
					worst_above = maxf(worst_above,WeatherOverlay.haze_alpha(Vector2(1.0,above),billow,sheet,breath,true,1.0))
					worst_blizzard = maxf(worst_blizzard,WeatherOverlay.haze_alpha(Vector2(0,above),billow,sheet*.8,breath,false,WeatherOverlay.BLIZZARD_MAX))
					worst_blizzard = maxf(worst_blizzard,WeatherOverlay.haze_alpha(Vector2(0,-above),billow,sheet*.8,breath,false,WeatherOverlay.BLIZZARD_MAX))
				top_full = minf(top_full,WeatherOverlay.haze_alpha(Vector2(0,14.0),billow,sheet,0.0,true,1.0))
	check(worst_inside[0]<=WeatherOverlay.SAND_VEIL+.0001,"sand haze inside the clear circle stays at the veil (%.3f)" % worst_inside[0])
	check(worst_inside[1]<=WeatherOverlay.BLIZZARD_VEIL+.0001,"blizzard haze inside the clear circle stays at the veil (%.3f)" % worst_inside[1])
	check(worst_below<=.6+.0001 and worst_side<=.6+.0001,"sand haze below and beside the hero at most 0.6 (%.3f, %.3f)" % [worst_below,worst_side])
	check(worst_above<=.9+.0001,"sand haze above at most 0.9 (%.3f)" % worst_above)
	check(worst_blizzard<=.45+.0001,"blizzard haze at most 0.45 (%.3f)" % worst_blizzard)
	check(top_full>=.75,"13 m and more above the storm is thick (%.3f)" % top_full)
	check(WeatherOverlay.haze_alpha(Vector2(0,14.0),1.0,1.0,0.0,true,1.0)>=.89,"a sheet fills the top up to its cap")

func test_overlay_reduce() -> void:
	var plain := new_overlay("full","high",false)
	var reduced := new_overlay("full","high",true)
	for kind in ["wind","blizzard"]:
		run_overlay(plain,storm(kind,"active",1.0,1.15),1.0)
		run_overlay(reduced,storm(kind,"active",1.0,1.15),1.0)
		check(plain.shake()>0.0 and plain.shake()<=.08,"%s gust peak shakes the camera a little (%.3f)" % [kind,plain.shake()])
		check(reduced.shake()==0.0,"%s: no shake with reduce_effects" % kind)
	run_overlay(plain,storm("sand_storm","active",1.0,1.15),1.0)
	check(plain.shake()==0.0,"sand storm does not shake")
	run_overlay(plain,storm("wind","telegraph",.3,0.0),1.0)
	check(plain.shake()==0.0,"no shake outside a gust")
	plain.queue_free()
	reduced.queue_free()

func visual_world(location: int, route: int, quality: String) -> MountainWorld:
	var spec := LevelCatalog.route(location,route)
	var world := MountainWorld.new()
	world.visuals_enabled = true
	world.visual_quality = quality
	root.add_child(world)
	world.setup(int(spec["seed"]),location,0,false,route)
	var level := LevelBake.find(location,route,world.generation_version)
	if level!=null: world.load_bake(level)
	return world

func campfire_nodes(world: MountainWorld) -> Array[Node]:
	var found: Array[Node] = []
	for node in world.get_tree().get_nodes_in_group("campfire"):
		if world.is_ancestor_of(node): found.append(node)
	return found

func test_campfire_built() -> void:
	for quality in ["high","battery"]:
		var world := visual_world(2,0,quality)
		var fires := world.campfires()
		check(not fires.is_empty(),"L2 r0 has campfires (%s)" % quality)
		if fires.is_empty():
			world.queue_free()
			continue
		check(fires==world.weather.campfires(),"cached campfires match the weather bands")
		world.complete_view(fires[0].y,fires[0].x,16.0)
		var nodes := campfire_nodes(world)
		var near := false
		var lights := 0
		for node in nodes:
			var where := (node as Node3D).global_position
			near = near or Vector2(where.x,where.y).distance_to(fires[0])<=.5
			lights += node.find_children("*","OmniLight3D",true,false).size()
		check(near,"%s: a campfire stands at the first fire point (%d built)" % [quality,nodes.size()])
		if quality=="battery": check(lights==0,"battery campfire has no light")
		else: check(lights>0,"high campfire has a light")
		# One new section per call: enough calls for all of them.
		for n in range(world.chunks.size()+1): world.set_weather_wind(1.0)
		var plants: Array = []
		var cloths: Array = []
		for key in world.weather_materials.keys():
			plants.append_array(world.weather_materials[key]["plants"])
			cloths.append_array(world.weather_materials[key]["cloths"])
		check(not plants.is_empty(),"%s: loaded sections list their plant materials" % quality)
		var bent := true
		for material: ShaderMaterial in plants: bent = bent and is_equal_approx(float(material.get_shader_parameter("wind")),float(material.get_meta("weather_wind"))*4.0)
		for material: ShaderMaterial in cloths: bent = bent and is_equal_approx(float(material.get_shader_parameter("wind")),float(material.get_meta("weather_wind"))*3.0)
		check(bent,"%s: full wind bends plants x4 and flaps cloth x3" % quality)
		world.set_weather_wind(.97)
		check(plants.is_empty() or is_equal_approx(float(plants[0].get_shader_parameter("wind")),float(plants[0].get_meta("weather_wind"))*4.0),"a small change keeps the plant wind")
		world.set_weather_wind(0.0)
		var calm := true
		for material: ShaderMaterial in plants: calm = calm and is_equal_approx(float(material.get_shader_parameter("wind")),float(material.get_meta("weather_wind")))
		check(calm,"%s: calm restores the plant wind" % quality)
		world.queue_free()

# --- HUD chip, cold gauge and first-entry toasts ------------------------------

func hud_hero(game, y: float, clock: float) -> void:
	game.state = "play"
	game.sim.pos = Vector2(0,y)
	game.hazard_clock = clock
	game.hud.update_play()

func test_hud_chip() -> void:
	var game = await new_game(0,0)
	var weather: WeatherBands = game.world.weather
	var band: Dictionary = weather.bands_of_cycle(0)[1]
	var mid := (float(band["bottom"])+float(band["top"]))*.5
	check(game.hud.weather_chip!=null and game.hud.cold_gauge!=null,"the HUD builds the weather chip and cold gauge")
	hud_hero(game,mid,time_for(band,float(band["calm"])-3.0))
	check(game.hud.weather_chip.visible,"chip is visible inside a band")
	check(game.hud.weather_chip.kind=="wind" and game.hud.weather_chip.phase_name=="calm","chip shows the kind and phase")
	check(absf(game.hud.weather_chip.ring-.25)<.01,"ring starts 4 s before the telegraph (3 s left is .25)")
	hud_hero(game,mid,time_for(band,1.0))
	check(game.hud.weather_chip.visible and game.hud.weather_chip.ring==0.0,"calm far from the telegraph: chip visible, ring empty")
	hud_hero(game,mid,time_for(band,float(band["calm"])+float(band["telegraph"])*.5))
	check(absf(game.hud.weather_chip.ring-.5)<.01 and game.hud.weather_chip.blink,"telegraph: ring is the progress and it blinks")
	game.model.profile["settings"]["reduce_effects"] = true
	game.hud.update_play()
	check(not game.hud.weather_chip.blink,"reduce_effects stops the blinking")
	game.model.profile["settings"]["reduce_effects"] = false
	var active := time_for(band,float(band["calm"])+float(band["telegraph"])+float(band["active"])*.25)
	hud_hero(game,mid,active)
	var info := weather.phase(band,active)
	check(absf(game.hud.weather_chip.ring-.75)<.01,"active: ring drains from full")
	check(game.hud.weather_chip.direction==weather.direction(band,int(info["gust"])),"chip arrow is the gust direction")
	hud_hero(game,float(band["top"])+3.0,active)
	check(game.hud.weather_chip.visible,"chip stays visible in the soft edge")
	hud_hero(game,float(band["top"])+9.0,active)
	check(not game.hud.weather_chip.visible,"chip hides further than 6 m from the band")
	game.queue_free()
	await process_frame

func test_hud_cold() -> void:
	var game = await new_game(2,0)
	var band: Dictionary = game.world.weather.bands_of_cycle(0)[0]
	hud_hero(game,float(band["bottom"])-40.0,0.0)
	check(not game.hud.cold_gauge.visible,"no cold gauge without cold")
	game.cold.cold = .5
	game.hud.update_play()
	check(game.hud.cold_gauge.visible and is_equal_approx(game.hud.cold_gauge.value,.5),"cold gauge shows the cold")
	game.queue_free()
	await process_frame
	var summer = await new_game(0,0)
	hud_hero(summer,10.0,0.0)
	check(not summer.hud.cold_gauge.visible,"no cold gauge in the summer")
	summer.queue_free()
	await process_frame

func test_first_toast() -> void:
	var game = await new_game(0,0)
	var band: Dictionary = game.world.weather.bands_of_cycle(0)[0]
	var mid := (float(band["bottom"])+float(band["top"]))*.5
	game.hint_timer = 0.0
	game.hint = ""
	game.state = "play"
	game.sim.pos = Vector2(0,band["bottom"]-30.0)
	game.hazard_clock = 0.0
	game._update_weather(0.0)
	check(game.hint=="","no toast outside the band")
	game.sim.pos = Vector2(0,mid)
	game._update_weather(0.0)
	check(game.hint=="Ветер сносит в полёте — прыгай в затишье" and game.hint_timer>0.0,"first wind entry toasts")
	game.hint = ""
	game.hint_timer = 0.0
	game.sim.pos = Vector2(0,band["bottom"]-30.0)
	game._update_weather(0.0)
	game.sim.pos = Vector2(0,mid)
	game._update_weather(0.0)
	check(game.hint=="","second entry in the same run is silent")
	game.queue_free()
	await process_frame

# One warning pulse at calm -> telegraph and one hit at telegraph -> active,
# inside the band only.
func test_phase_feedback() -> void:
	var game = await new_game(0,0)
	var band: Dictionary = game.world.weather.bands_of_cycle(0)[0]
	var mid := (float(band["bottom"])+float(band["top"]))*.5
	var cycle := float(band["calm"])+float(band["telegraph"])+float(band["active"])
	game.state = "play"
	game.sim.pos = Vector2(0,mid)
	var before: int = game.haptics.pulses
	var step := .25
	var clock := time_for(band,0.0)
	var span := cycle*2.0
	var elapsed := 0.0
	while elapsed<span:
		game.hazard_clock = clock+elapsed
		game.haptics.clock += 5.0
		game._update_weather(0.0)
		elapsed += step
	check(game.haptics.pulses-before==4,"two full cycles in the band: two warnings and two hits (got %d)" % (game.haptics.pulses-before))
	# Outside the band nothing fires.
	game.sim.pos = Vector2(0,float(band["bottom"])-40.0)
	game._update_weather(0.0)
	before = game.haptics.pulses
	elapsed = 0.0
	while elapsed<span:
		game.hazard_clock = clock+elapsed
		game.haptics.clock += 5.0
		game._update_weather(0.0)
		elapsed += step
	check(game.haptics.pulses==before,"no weather feedback outside the band")
	game.sim.pos = Vector2(0,mid)
	game.hazard_clock = clock+float(band["calm"])+float(band["telegraph"])+1.0
	game.state = "play"
	game._update_weather(0.0)
	check(game.sounds.weather_goal>0.0,"the storm loop is wanted while playing")
	for paused in ["pause","revive"]:
		game.state = paused
		game._update_weather(0.0)
		check(game.sounds.weather_goal==0.0 and game.sounds.campfire_goal==0.0,"%s silences the storm loop" % paused)
	game.queue_free()
	await process_frame

# --- Final review fixes ------------------------------------------------------

# band_at reuses its band dictionaries (a pure cache): same answers as a fresh
# instance, from the cache.
func test_band_memo(worlds: Array[MountainWorld]) -> void:
	var cached := WeatherBands.new(worlds[6].layout)
	var total := float((worlds[6].layout as ExpeditionLayout).spans[-1]["y_end"])
	var same := true
	for n in range(60):
		var y := float(n)*total*3.0/60.0
		var first := cached.band_at(y,2.0)
		same = same and first==cached.band_at(y,2.0) and first==WeatherBands.new(worlds[6].layout).band_at(y,2.0)
	check(same,"memoized band_at equals a fresh instance")
	check(cached._cache.size()>0 and cached._cache.size()<=8,"bands are memoized per act and cycle (%d)" % cached._cache.size())

# An endless blizzard has campfires in later cycles too; the world lists the
# cycles round the view only.
func test_endless_campfires() -> void:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(4242,2)
	var layout := world.layout as ExpeditionLayout
	check(layout!=null and world.weather.enabled(),"endless winter world has weather")
	if layout==null or not world.weather.enabled():
		world.queue_free()
		return
	var total := float(layout.spans[-1]["y_end"])
	world.generate_to(total*2.0+10.0,false)
	var fires := world.weather.campfires(1,1,world.generated_height)
	var covered := true
	for band in world.weather.bands_of_cycle(1):
		var has := false
		for fire in fires: has = has or (fire.y>=float(band["bottom"])-2.0 and fire.y<=float(band["top"])+2.0)
		covered = covered and has
	check(not fires.is_empty() and covered,"endless cycle 1 has a campfire in each blizzard band (%d)" % fires.size())
	world.camera_center = Vector2(0,total*1.5)
	var listed := world.campfires()
	var has_first := false
	for fire in fires: has_first = has_first or listed.has(fire)
	check(has_first,"the world lists cycle 1 campfires round a cycle 1 view")
	world.camera_center = Vector2(0,10.0)
	var low := world.campfires()
	var beyond := true
	for fire in low: beyond = beyond and fire.y<total*2.0
	check(not low.is_empty() and beyond,"round the start only cycles 0 and 1 are listed")
	world.queue_free()

# The overlay keeps the gust's side while the gust fades: calm already
# carries the next gust's direction.
func test_direction_latch() -> void:
	var overlay := new_overlay("full","high",false)
	var gust := storm("wind","active",1.0)
	gust["direction"] = 1.0
	run_overlay(overlay,gust,.5)
	var calm := storm("wind","calm",0.0)
	calm["direction"] = -1.0
	run_overlay(overlay,calm,.3)
	check(overlay._direction==1.0,"calm does not turn the fading wind")
	var next := storm("wind","telegraph",.2)
	next["direction"] = -1.0
	run_overlay(overlay,next,.1)
	check(overlay._direction==-1.0,"the next gust's warning turns it")
	overlay.queue_free()

# Warm-up draws each weather shader once, invisibly, then leaves all hidden.
func test_overlay_warm_up() -> void:
	var overlay := new_overlay("full","high",false)
	overlay.warm_up()
	var seen := {}
	var invisible := true
	var kinds := {}
	for frame in range(8):
		overlay.update({"kind":""},0.0,Vector2(270,600),.045,1.0/60.0)
		for child in ["Штрихи","Мгла","Иней"]:
			var rect := overlay.get_node(child) as CanvasItem
			if rect.visible:
				seen[child] = true
				var material := rect.material as ShaderMaterial
				var key := "amount" if child=="Иней" else "strength"
				invisible = invisible and float(material.get_shader_parameter(key))==0.0
		if overlay.particles.visible:
			kinds[overlay._particle_kind] = true
			invisible = invisible and overlay.particles.self_modulate.a==0.0 and overlay.particles.amount_ratio<=.02
	check(seen.size()==3,"warm-up shows the three weather rects (%d)" % seen.size())
	check(kinds.size()==3,"warm-up emits each particle kind (%d)" % kinds.size())
	check(invisible,"warm-up draws at strength 0 and invisible particles")
	var hidden := true
	for child in ["Штрихи","Частицы","Мгла","Иней"]: hidden = hidden and not (overlay.get_node(child) as CanvasItem).visible
	check(hidden and overlay._particle_kind=="" and overlay.particles.self_modulate.a==1.0,"after warm-up all hidden and reset")
	run_overlay(overlay,storm("wind","active",1.0),.5)
	check(overlay.particles.visible and overlay._particle_kind=="wind","weather still shows after warm-up")
	overlay.queue_free()
	var host := Node.new()
	root.add_child(host)
	var view := CampfireVisuals.warm(host)
	check(view!=null and view.get_parent()==host and not view.find_children("*","GPUParticles3D",true,false).is_empty(),"campfire warm-up draws a fire offscreen")
	host.queue_free()

# The warm-up emits at least one particle (and only a few) on every preset,
# so each particle kind really compiles, even with 20 or 40 particles.
func test_warm_up_emits_on_every_preset() -> void:
	for setup in [["full","battery",false],["full","battery",true],["reduced","balanced",true],["full","high",false]]:
		var overlay := new_overlay(setup[0],setup[1],setup[2])
		overlay.warm_up()
		var least := INF
		var most := 0.0
		for frame in range(4):
			overlay.update({"kind":""},0.0,Vector2(270,600),.045,1.0/60.0)
			if overlay.particles.visible:
				var emitted := floorf(overlay.particles.amount*overlay.particles.amount_ratio)
				least = minf(least,emitted)
				most = maxf(most,emitted)
		check(least>=1.0 and most<=2.0,"warm-up emits 1-2 particles on %s (%s..%s)" % [str(setup),str(least),str(most)])
		overlay.queue_free()

# Plants and the rope follow an eased drive: same peak, no snap at the gust end.
func test_eased_drive() -> void:
	var game = await new_game(0,0)
	var band: Dictionary = game.world.weather.bands_of_cycle(0)[1]
	var mid := (float(band["bottom"])+float(band["top"]))*.5
	game.state = "play"
	game.sim.pos = Vector2(0,mid)
	var start := time_for(band,float(band["calm"]))
	var span := float(band["telegraph"])+float(band["active"])+2.0
	var step := 1.0/60.0
	var peak := 0.0
	var worst := 0.0
	var last := -1.0
	var flips := 0
	var side := 0.0
	for frame in range(roundi(span/step)):
		game.hazard_clock = start+frame*step
		game._update_weather(step)
		var drive: float = game.weather_drive
		if last>=0.0: worst = maxf(worst,absf(drive-last))
		last = drive
		peak = maxf(peak,drive)
		var bow: float = game.explorer.wind_bow
		if absf(bow)>.001:
			if side!=0.0 and signf(bow)!=side: flips += 1
			side = signf(bow)
	check(peak>=.99,"the eased drive still reaches the full gust (%.3f)" % peak)
	check(worst<=.05,"no step over 0.05 per frame in the drive (%.3f)" % worst)
	check(flips==0,"the rope bow keeps its side while the gust fades")
	game.queue_free()
	await process_frame

# Wind materials: one new section scanned per call, none without weather.
func test_wind_scan_sliced() -> void:
	var world := visual_world(0,0,"battery")
	world.complete_view(60.0,0.0,30.0)
	var complete := 0
	for key in world.chunks: complete += 1 if world.chunk_complete(key) else 0
	world.set_weather_wind(.5)
	check(complete<2 or world.weather_materials.size()==1,"one section scanned per call (%d of %d)" % [world.weather_materials.size(),complete])
	for n in range(complete): world.set_weather_wind(.5)
	check(world.weather_materials.size()==complete,"all complete sections scanned over a few calls")
	world.queue_free()
	var practice := MountainWorld.new()
	practice.visuals_enabled = true
	root.add_child(practice)
	practice.setup(77,0,0,true)
	practice.generate_to(60.0,true,60.0)
	practice.complete_view(20.0,0.0,20.0)
	practice.set_weather_wind(1.0)
	check(not practice.weather.enabled() and practice.weather_materials.is_empty(),"no weather: no material scan")
	practice.queue_free()

# reduce_effects keeps the campfire light steady.
func test_campfire_reduce() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var steady := CampfireVisuals.build(holder,Vector2.ZERO,2.0,true,true)
	var lively := CampfireVisuals.build(holder,Vector2(3,0),2.0,true,false)
	var steady_light := steady.find_children("*","OmniLight3D",true,false)[0] as OmniLight3D
	var lively_light := lively.find_children("*","OmniLight3D",true,false)[0] as OmniLight3D
	check(not steady_light.has_meta("flicker") and lively_light.has_meta("flicker"),"reduce_effects: no flicker tween")
	CampfireVisuals.set_flicker(lively,false)
	check(not lively_light.has_meta("flicker") and is_equal_approx(lively_light.light_energy,CampfireVisuals.LIGHT_ENERGY),"flicker stops on a settings change")
	CampfireVisuals.set_flicker(lively,true)
	check(lively_light.has_meta("flicker"),"flicker resumes")
	holder.queue_free()
