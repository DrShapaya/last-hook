extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("TEST FAILED: " + description)

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		push_error("Tests require LASTHOOK_SAVE_DIR to keep saves isolated")
		quit(2)
		return
	var path := directory.path_join("rules-tests.json")
	var model := GameModel.new(path)
	model.profile = GameModel.fresh_profile()
	check(model.level(GameModel.BAG)==1,"initial bag has exactly one slot")
	check(model.value(GameModel.RECOVERY)==25,"initial retention is 25 percent")
	var cheap := {"id":1,"tier":0,"value":40}
	var expensive := {"id":2,"tier":0,"value":200}
	check(model.try_pick(cheap),"first find enters an empty bag")
	check(not model.try_pick(expensive),"a more expensive find never replaces a full bag")
	check(model.bag_value()==40,"full bag remains unchanged")
	check(model.retained(false)==10,"one item retains a deterministic share of its value")
	check(model.retained(true)==40,"summit success retains all loot")
	model.discard(0)
	check(not model.try_pick(cheap),"discarded item cannot be re-collected")
	check(model.try_pick(expensive),"player can collect another find after discarding")
	model.set_level(GameModel.RECOVERY,5)
	check(model.retained(false)==160,"maximum retention is 80 percent, never the whole bag")
	model.bag.clear()
	check(model.try_pick({"id":3,"tier":5,"value":560}),"a reached valuable find fits an empty starter bag regardless of its tier")
	check(not model.try_pick({"id":4,"tier":0,"value":40}),"unrestricted find tiers do not bypass starter capacity")
	check(model.item_is_rare(expensive) and not model.item_is_rare(cheap),"rare and ordinary items of the same type remain distinguishable")
	model.profile["gold"] = 1000000
	model.set_level(GameModel.ROPE,2)
	model.purchase(GameModel.ROPE)
	check(model.level(GameModel.ROPE)==2,"bought gold cannot bypass the first-act gate of level 3")
	check(model.reach(20).size()==1,"entering zone 2 still pays its first-entry reward")
	check(model.reach_act(2) and model.purchase(GameModel.ROPE).begins_with("Улучшено") and model.level(GameModel.ROPE)==3,"clearing the first act opens level 3")
	check(model.purchase(GameModel.ROPE)=="Дойди до 3-го акта" and model.level(GameModel.ROPE)==3,"level 4 waits for the third act")
	model.reach_act(3)
	model.purchase(GameModel.ROPE)
	check(model.level(GameModel.ROPE)==4 and model.purchase(GameModel.ROPE).begins_with("Вершина или") and model.level(GameModel.ROPE)==4,"level 5 needs a summit or two contracts")
	model.profile["completed_contracts"] = ["root_impulse","open_arc"]
	model.purchase(GameModel.ROPE)
	check(model.level(GameModel.ROPE)==5 and model.cost(GameModel.ROPE)==0,"two contracts open the last level instead of a summit")
	model.purchase(GameModel.THROW)
	check(model.level(GameModel.THROW)==2,"unlocked upgrade can be purchased independently")
	var after_reach: int = model.profile["gold"]
	check(model.reach(20).is_empty() and int(model.profile["gold"])==after_reach,"zone first-entry rewards cannot be farmed")
	check(model.height_gold(50)>model.height_gold(20),"height rewards grow with progress")
	check(model.height_gold(0)==0,"standing at the start does not pay")
	model.profile = GameModel.fresh_profile()
	model.bag = [expensive]
	var first := model.settle("test-run-1","summit",30,false,0)
	check(first["loot"]==50,"failed finite run uses retention")
	var gold_after: int = model.profile["gold"]
	var diamonds_after: int = model.profile["diamonds"]
	var duplicate := model.settle("test-run-1","summit",30,false,0)
	check(duplicate["duplicate"] and int(model.profile["gold"])==gold_after,"result cannot be settled twice")
	check(model.profile["diamonds"]==diamonds_after and first["diamonds"]==0,"defeat and duplicate settlement never create diamonds")
	var endless := model.settle("test-run-2","endless",40,false,0)
	check(endless["loot"]==50 and not endless["success"],"endless also uses retention")
	var win := model.settle("test-run-3","summit",120,true,0)
	check(win["loot"]==200,"finite summit awards the complete bag")
	check(model.profile["summit_cleared"] and win["first"],"first summit unlocks endless and location shop")
	var win_again := model.settle("test-run-4","summit",120,true,0)
	check(not win_again["first"] and win_again["finish"]==300,"first-summit reward cannot repeat")
	check(win["diamonds"]==20 and win_again["diamonds"]==3,"first and repeat summit diamond rewards are separated")
	var repeat_wallet: int = model.profile["diamonds"]
	model.settle("test-run-4","summit",120,true,0)
	check(model.profile["diamonds"]==repeat_wallet,"reloading a repeat summit result cannot duplicate its diamonds")
	# Expeditions open by progress plus a moderate price (balance.json).
	var unlocks := GameModel.new(directory.path_join("unlock-tests.json"))
	unlocks.profile = GameModel.fresh_profile()
	unlocks.profile["gold"] = 100000
	unlocks.profile["diamonds"] = 100
	unlocks.purchase_location(1)
	check(not unlocks.profile["locations"].has(1) and unlocks.profile["gold"]==100000,"the second expedition waits for the first summit")
	unlocks.settle("first-peak","summit",120,true,0)
	unlocks.profile["gold"] = 2499
	unlocks.purchase_location(1)
	check(not unlocks.profile["locations"].has(1) and unlocks.profile["gold"]==2499,"the second expedition costs 2500 gold, not a partial charge")
	unlocks.profile["gold"] = 2500
	unlocks.purchase_location(1)
	check(unlocks.profile["locations"].has(1) and unlocks.profile["gold"]==0,"first summit plus 2500 gold opens the second expedition")
	unlocks.purchase_location(2)
	check(not unlocks.profile["locations"].has(2),"the third expedition waits for the second summit")
	unlocks.settle("second-peak","summit",140,true,1)
	unlocks.profile["diamonds"] = 14
	unlocks.purchase_location(2)
	check(not unlocks.profile["locations"].has(2) and unlocks.profile["diamonds"]==14,"the third expedition also needs 15 diamonds")
	unlocks.profile["diamonds"] = 20
	unlocks.purchase_location(2)
	check(unlocks.profile["locations"].has(2) and unlocks.profile["diamonds"]==5,"second summit and 15 diamonds open the third expedition")
	check(not unlocks.location_requirement(2).contains("жетон"),"the third expedition no longer asks for mastery tokens")
	model.profile["gold"] = 10000
	model.purchase_location(1)
	check(model.profile["locations"].has(1) and int(model.profile["gold"])==7500,"second location is purchased using gold")
	model.save()
	var reloaded := GameModel.new(path)
	check(reloaded.profile["locations"].has(1) and int(reloaded.profile["gold"])==7500,"profile survives save and reload")
	var corrupted := FileAccess.open(path,FileAccess.WRITE)
	corrupted.store_string("not valid JSON")
	corrupted.close()
	var recovered := GameModel.new(path)
	check(int(recovered.profile["version"])==GameModel.PROFILE_VERSION and int(recovered.profile["runs"])>0,"a broken primary save falls back to backup")
	var sim := RopeSim.new()
	sim.pos = Vector2(1,2)
	sim.attach(Vector2(0,6),5.5)
	var stable := true
	for step in range(6000):
		sim.tick(1.0/120,sin(step*.017),0)
		if sim.pos.distance_to(sim.anchor)>sim.length+.001 or not sim.pos.is_finite() or sim.vel.length()>18.01:
			stable = false
	check(stable,"rope constraint stays finite and inside speed/radius limits over 50 seconds")
	var velocity_before := sim.vel
	sim.release(1)
	check(not sim.attached and sim.vel.distance_to(velocity_before)<.001,"release preserves momentum")
	sim.grounded = false
	sim.flight_peak = 30
	sim.pos.y = 19
	check(sim.fallen()>=10,"historical fall distance remains measurable for old save compatibility")
	sim.attach(Vector2(sim.pos.x,22),5)
	check(sim.fallen()>=10,"a lower catch preserves historical height telemetry")
	check(RopeSim.hit_circle(Vector2(0,0),Vector2(10,0),Vector2(5,0),.2)>0,"swept projectile detects small anchors at high speed")
	check(RopeSim.hit_circle(Vector2(0,0),Vector2(10,0),Vector2(5,2),.2)<0,"projectile does not attach to a missed anchor")
	var contour := PackedVector2Array([Vector2(3,-1),Vector2(7,-1),Vector2(7,1),Vector2(3,1)])
	check(absf(RopeSim.hit_polygon(Vector2.ZERO,Vector2(10,0),contour)-.3)<.001,"rock contact is the first surface intersection, not the object's center")
	check(RopeSim.hit_capsule(Vector2(0,-3),Vector2(0,3),Vector2(-2,0),Vector2(2,0),.2)>0,"a branch catches along its length")
	check(RopeSim.hit_capsule(Vector2(3,-3),Vector2(3,3),Vector2(-2,0),Vector2(2,0),.2)<0,"the empty space past a branch does not catch")
	var adjustable := RopeSim.new()
	adjustable.pos = Vector2(0,2)
	adjustable.attach(Vector2(0,6),5.5)
	for frame in range(120):
		adjustable.tick(1.0/120,sin(frame*.1),0)
	check(absf(adjustable.length-4)<.001,"swinging alone never changes the deployed rope length")
	adjustable.request_length(2)
	adjustable.tick(1.0/120,0,0)
	check(adjustable.length<4 and adjustable.length>3.9,"rope shortening is rate limited rather than teleporting the player")
	for frame in range(120):
		adjustable.tick(1.0/120,0,0)
	check(absf(adjustable.length-2)<.001,"the rope stops at the selected length when input stops")
	adjustable.request_length(5)
	adjustable.tick(1.0/120,0,0)
	check(adjustable.length>2 and adjustable.length<2.1,"extension is smooth in the opposite direction")
	adjustable.request_length(99)
	check(adjustable.target_length==5.5,"lengthening cannot exceed the purchased rope's maximum")
	adjustable.request_length(-99)
	check(adjustable.target_length==RopeSim.MIN_LENGTH,"shortening cannot pull the character through the hook")
	adjustable.release(1)
	for frame in range(600):
		adjustable.tick(1.0/120,0,0)
	check(adjustable.vel.y>=-8.001,"free-fall speed remains slow enough for a visible rescue window")
	# Migration preserves paid reach without moving existing upgrade indices.
	var legacy_path := directory.path_join("legacy-v1.json")
	var legacy := GameModel.fresh_profile()
	legacy["version"] = 1
	legacy["levels"] = [4,3,2,5,2,6]
	legacy["gold"] = 1789
	var legacy_file := FileAccess.open(legacy_path,FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	var migrated := GameModel.new(legacy_path)
	# v1 -> v5 returns 1500+3015 (tips, maximum recovery); v5 -> v6 returns
	# what the new five-level tracks cost less: 970+46+400+4917+0+11959+970.
	var expected_levels := GameModel.default_levels()
	expected_levels.merge({GameModel.ROPE:4,GameModel.IMPULSE:3,GameModel.RADIUS:5,GameModel.BAG:5,GameModel.MAGNET:3,GameModel.RECOVERY:5,GameModel.THROW:5,GameModel.SLOWMO:3,GameModel.REEL_OUT:3,GameModel.SLOWMO_REST:3},true)
	check(migrated.profile["upgrade_levels"]==expected_levels and migrated.profile["gold"]==1789+1500+3015+19262+1360,"legacy saves keep purchases and return each net price difference once")
	migrated.save()
	var migrated_again := GameModel.new(legacy_path)
	check(migrated_again.profile["upgrade_levels"]==expected_levels and migrated_again.profile["gold"]==migrated.profile["gold"],"a migrated save loads unchanged")
	check(migrated_again.level(GameModel.RADIUS)==5 and migrated_again.hook_count()==1,"a purchased legacy grip keeps its wide catch across reloads")
	var future_path := directory.path_join("future-profile.json")
	var future_data := GameModel.fresh_profile()
	future_data["version"] = GameModel.PROFILE_VERSION+1
	future_data["gold"] = 98765
	var future_file := FileAccess.open(future_path,FileAccess.WRITE)
	future_file.store_string(JSON.stringify(future_data))
	future_file.close()
	var future_model := GameModel.new(future_path)
	check(future_model.save_blocked and not future_model.save() and future_model.save_error!="","a profile from a newer version is read-only and reports a migration warning")
	check(JSON.parse_string(FileAccess.get_file_as_string(future_path))["gold"]==98765,"a newer profile is never overwritten by the older build")
	var blocked_path := directory.path_join("blocked-profile.json")
	DirAccess.make_dir_recursive_absolute(blocked_path+".tmp")
	var blocked_model := GameModel.new(blocked_path)
	check(not blocked_model.save() and not blocked_model.save_error.is_empty(),"a failed save reports an error instead of claiming success")
	DirAccess.remove_absolute(blocked_path+".tmp")
	legacy["version"] = 2
	legacy["levels"] = [6,6,6,6,6,6,6]
	legacy_file = FileAccess.open(legacy_path,FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	var maximum_legacy := GameModel.new(legacy_path)
	check(maximum_legacy.level(GameModel.RADIUS)==5 and maximum_legacy.level(GameModel.DOUBLE)==2 and maximum_legacy.level(GameModel.ROPE)==5 and maximum_legacy.hook_count()==2,"maximum old grip becomes a wide double hook, other maximum tracks their new maximum")
	var tips := GameModel.new(directory.path_join("tip-tests.json"))
	tips.profile = GameModel.fresh_profile()
	tips.profile["gold"] = 2199
	tips.purchase(GameModel.DOUBLE)
	check(tips.level(GameModel.DOUBLE)==1 and tips.profile["gold"]==2199,"the double hook cannot be bought with a partial charge")
	tips.profile["gold"] = 2200
	check(tips.purchase(GameModel.DOUBLE).begins_with("Улучшено") and tips.profile["gold"]==0 and tips.hook_count()==2 and tips.hook_tips()==1,"the double hook costs 2200 and is taken at once")
	check(tips.set_choice("hook","1").begins_with("Крюк") and tips.hook_count()==1,"a single hook stays selectable between runs")
	tips.profile["active"] = {"id":"run"}
	check(tips.set_choice("hook","2")=="Сначала заверши текущую попытку" and tips.hook_count()==1,"the hook cannot change during a run")
	tips.profile["active"] = {}
	tips.set_choice("hook","2")
	tips.purchase(GameModel.DOUBLE)
	check(tips.level(GameModel.DOUBLE)==2 and tips.cost(GameModel.DOUBLE)==0,"two is the hard cap of the double hook")
	var saved_tips := GameModel.new(directory.path_join("tip-tests.json"))
	check(saved_tips.level(GameModel.DOUBLE)==2 and saved_tips.hook_count()==2 and saved_tips.profile["gold"]==0,"hook configuration and prices survive a profile reload")
	model.profile = GameModel.fresh_profile()
	check(model.value(GameModel.THROW)==15.0 and model.value_at(GameModel.THROW,5)==25.0,"throw range")
	check(model.value_at(GameModel.REEL_OUT,5)==3.5 and model.value_at(GameModel.SLOWMO,1)==0.0,"rope and slow motion ranges")
	check(model.price_at_level(GameModel.THROW,1)==100 and model.price_at_level(GameModel.BAG,4)==1760,"prices are ladder times weight")
	var total := 0
	for category in GameModel.CATEGORIES.values():
		for key in category:
			for step in range(1,model.max_level(key)): total += model.price_at_level(key,step)
	check(total>=33000 and total<=35000,"a full build costs about 34000: %d" % total)
	check(not model.upgrade_available(GameModel.ACCURACY) and not model.upgrade_available(GameModel.SLOWMO_REST),"dependent cards start closed")
	check(model.lock_reason(GameModel.ACCURACY)=="Нужен двойной крюк" and model.lock_reason(GameModel.SLOWMO_REST)=="Сначала купи замедление","closed cards say why")
	model.set_level(GameModel.DOUBLE,2)
	model.set_level(GameModel.SLOWMO,2)
	check(model.upgrade_available(GameModel.ACCURACY) and model.upgrade_available(GameModel.SLOWMO_REST),"dependencies open them")
	check(model.hook_count()==2 and model.hook_spread()==8.0 and model.hook_tips()==1,"double hook starts single-tipped")
	model.set_level(GameModel.RADIUS,3)
	check(model.hook_tips()==3 and is_equal_approx(model.hook_radius(),.54),"radius brings the three-tip hook")
	model.set_level(GameModel.ACCURACY,5)
	var pair := model.hook_directions(Vector2.UP)
	check(is_equal_approx(rad_to_deg(pair[0].angle_to(pair[1])),3.0),"accuracy narrows the two hooks")
	model.profile = GameModel.fresh_profile()
	model.set_level(GameModel.ROPE,5)
	check(model.shot_range()==8.0 and model.throw_speed()==15.0,"long rope extends reach without changing throwing speed")
	model.profile = GameModel.fresh_profile()
	model.set_level(GameModel.THROW,5)
	check(model.shot_range()==5.5 and model.throw_speed()==25.0,"stronger throw accelerates the projectile while respecting the short rope")
	model.profile = GameModel.fresh_profile()
	model.set_level(GameModel.IMPULSE,3)
	check(is_equal_approx(model.impulse_factor(),1.12),"impulse adds to every release")
	model.profile = GameModel.fresh_profile()
	check(model.reel_in_speed()==2.4 and model.reel_out_speed()==1.0 and model.swing_force()==11.0,"rope and swing start at their base values")
	check(model.set_choice("magnet","relic").begins_with("Откроется"),"the magnet priority waits for its level")
	model.set_level(GameModel.MAGNET,3)
	check(model.magnet_priority().is_empty() and not model.magnet_priority_open(),"level 3 of the magnet has no priority")
	model.set_level(GameModel.MAGNET,4)
	check(model.set_choice("magnet","relic").begins_with("Магнит") and model.magnet_priority()=="relic" and model.coin_radius()==1.2 and model.item_radius()==1.2,"level 4 opens the priority and one radius serves both")
	model.profile = GameModel.fresh_profile()
	model.learn_control("aim")
	model.learn_control("aim")
	model.save()
	var lessons := GameModel.new(model.save_path)
	check(lessons.profile["learned_controls"]==["aim"],"completed lessons persist once without repeating across runs")
	model.profile["reached_zones"] = 2
	model.profile["gold"] = 100
	check(model.recommended_upgrade()==GameModel.ROPE,"result can point a new player to an affordable unlocked rope upgrade")
	model.profile["reached_zones"] = 1
	model.purchase(GameModel.ROPE)
	check(model.level(GameModel.ROPE)==2 and model.profile["gold"]==0,"gold from early failed attempts can buy the first upgrade before reaching 200 m")
	model.profile["gold"] = 1000
	model.profile["reached_acts"] = 1
	model.set_level(GameModel.ROPE,2)
	model.purchase(GameModel.ROPE)
	check(model.level(GameModel.ROPE)==2 and model.profile["gold"]==1000,"higher upgrades still require their act")
	model.profile["gold"] = 100000
	model.profile["reached_acts"] = 3
	model.profile["active"] = {"id":"pending"}
	var before_levels: Dictionary = model.profile["upgrade_levels"].duplicate()
	model.purchase(GameModel.IMPULSE)
	check(model.profile["upgrade_levels"]==before_levels and model.profile["gold"]==100000,"an active saved run cannot buy upgrades through the model")
	model.profile["active"] = {}
	var descending := RopeSim.new()
	descending.pos = Vector2(0,40)
	descending.flight_peak = 40
	for y in [35,30,25,20]:
		descending.pos.y = y
		descending.attach(Vector2(0,y+2),5.5)
		descending.release(1)
	check(descending.fallen()==20,"successive lower catches preserve historical height telemetry")
	descending.land(18)
	check(descending.fallen()>20,"landing preserves historical fall telemetry without defining defeat")
	# Release slow motion: four levels read from balance.json.
	var slowmo := GameModel.new(directory.path_join("slowmo-tests.json"))
	slowmo.profile = GameModel.fresh_profile()
	check(slowmo.max_level(GameModel.SLOWMO)==5 and slowmo.slowmo_seconds()==0.0,"slow motion has five levels and starts absent")
	slowmo.profile["gold"] = 100000
	slowmo.profile["reached_acts"] = 3
	var slowmo_price := slowmo.cost(GameModel.SLOWMO)
	slowmo.purchase(GameModel.SLOWMO)
	check(slowmo.level(GameModel.SLOWMO)==2 and is_equal_approx(slowmo.slowmo_seconds(),.25) and slowmo.profile["gold"]==100000-slowmo_price and slowmo_price==90,"buying slow motion raises the window")
	var slowmo_saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slowmo.save_path))
	check(int(slowmo_saved["upgrade_levels"][GameModel.SLOWMO])==2,"purchased slow motion is written to the profile")
	slowmo.purchase(GameModel.SLOWMO)
	slowmo.purchase(GameModel.SLOWMO)
	check(slowmo.level(GameModel.SLOWMO)==4 and is_equal_approx(slowmo.slowmo_seconds(),.75),"the fourth level gives 0,75 s")
	slowmo.profile["summit_cleared"] = true
	slowmo.purchase(GameModel.SLOWMO)
	check(slowmo.level(GameModel.SLOWMO)==5 and is_equal_approx(slowmo.slowmo_seconds(),1.0) and slowmo.cost(GameModel.SLOWMO)==0,"slow motion stops at 1,0 s")
	check(slowmo.slowmo_cooldown()==2.4,"the rest starts at 2,4 s")
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"engine":Engine.get_version_info()["string"]}
	var output := FileAccess.open(directory.path_join("rules-test-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("RULES_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
