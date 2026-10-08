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
	check(model.level(3)==1,"initial bag has exactly one slot")
	check(model.value("recovery_percents",5)==30,"initial retention is 30 percent")
	var cheap := {"id":1,"tier":0,"value":40}
	var expensive := {"id":2,"tier":0,"value":200}
	check(model.try_pick(cheap),"first find enters an empty bag")
	check(not model.try_pick(expensive),"a more expensive find never replaces a full bag")
	check(model.bag_value()==40,"full bag remains unchanged")
	check(model.retained(false)==12,"one item retains a deterministic share of its value")
	check(model.retained(true)==40,"summit success retains all loot")
	model.discard(0)
	check(not model.try_pick(cheap),"discarded item cannot be re-collected")
	check(model.try_pick(expensive),"player can collect another find after discarding")
	model.profile["levels"][5] = 6
	check(model.retained(false)==190,"maximum retention is 95 percent")
	model.bag.clear()
	check(not model.try_pick({"id":3,"tier":1,"value":75}),"a new find type requires a better backpack")
	model.profile["gold"] = 1000000
	model.profile["levels"][0] = 2
	model.purchase(0)
	check(model.level(0)==2,"bought gold cannot bypass a higher upgrade zone gate")
	check(model.reach(20).size()==1,"entering zone 2 opens the next tier immediately")
	model.purchase(GameModel.THROW)
	check(model.level(GameModel.THROW)==2,"unlocked upgrade can be purchased independently")
	var after_reach: int = model.profile["gold"]
	check(model.reach(20).is_empty() and int(model.profile["gold"])==after_reach,"zone first-entry rewards cannot be farmed")
	check(model.height_gold(50)>model.height_gold(20),"height rewards grow with progress")
	check(model.height_gold(0)==0,"standing at the start does not pay")
	model.profile = GameModel.fresh_profile()
	model.bag = [expensive]
	var first := model.settle("test-run-1","summit",30,false,0)
	check(first["loot"]==60,"failed finite run uses retention")
	var gold_after: int = model.profile["gold"]
	var duplicate := model.settle("test-run-1","summit",30,false,0)
	check(duplicate["duplicate"] and int(model.profile["gold"])==gold_after,"result cannot be settled twice")
	var endless := model.settle("test-run-2","endless",40,false,0)
	check(endless["loot"]==60 and not endless["success"],"endless also uses retention")
	var win := model.settle("test-run-3","summit",120,true,0)
	check(win["loot"]==200,"finite summit awards the complete bag")
	check(model.profile["summit_cleared"] and win["first"],"first summit unlocks endless and location shop")
	var win_again := model.settle("test-run-4","summit",120,true,0)
	check(not win_again["first"] and win_again["finish"]==300,"first-summit reward cannot repeat")
	model.profile["gold"] = 10000
	model.purchase_location(1)
	check(model.profile["locations"].has(1) and int(model.profile["gold"])==2000,"second location is purchased using gold")
	model.profile["diamonds"] = 45
	model.purchase_location(2)
	check(model.profile["locations"].has(2) and int(model.profile["diamonds"])==0,"third location is purchased using diamonds")
	model.save()
	var reloaded := GameModel.new(path)
	check(reloaded.profile["locations"].has(2) and int(reloaded.profile["gold"])==2000,"profile survives save and reload")
	var corrupted := FileAccess.open(path,FileAccess.WRITE)
	corrupted.store_string("not valid JSON")
	corrupted.close()
	var recovered := GameModel.new(path)
	check(int(recovered.profile["version"])==3 and int(recovered.profile["runs"])>0,"a broken primary save falls back to backup")
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
	check(migrated.profile["levels"]==[4,3,2,5,2,6,4] and migrated.profile["gold"]==1789,"legacy saves preserve all upgrades, wallet and the formerly bundled throw reach")
	migrated.save()
	var migrated_again := GameModel.new(legacy_path)
	check(migrated_again.profile["levels"].size()==7 and migrated_again.level(6)==4,"migration is idempotent across subsequent loads")
	check(migrated_again.level(2)==2,"a purchased legacy grip retains a useful two-prong hook across reloads")
	legacy["version"] = 2
	legacy["levels"] = [6,6,6,6,6,6,6]
	legacy_file = FileAccess.open(legacy_path,FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	var maximum_legacy := GameModel.new(legacy_path)
	check(maximum_legacy.level(2)==3 and maximum_legacy.level(0)==6,"maximum old grip becomes three tips while other maximum upgrades stay unchanged")
	var tips := GameModel.new(directory.path_join("tip-tests.json"))
	tips.profile = GameModel.fresh_profile()
	tips.profile["gold"] = 2399
	tips.purchase(2)
	check(tips.level(2)==1 and tips.profile["gold"]==2399,"two tips are an expensive purchase with no partial charge")
	tips.profile["gold"] = 14400
	var base_radius := tips.hook_radius()
	tips.purchase(2)
	check(tips.level(2)==2 and tips.profile["gold"]==12000 and tips.hook_radius()>base_radius,"two tips widen catches and cost exactly 2400 gold without a material or zone gate")
	tips.purchase(2)
	check(tips.level(2)==3 and tips.profile["gold"]==0 and tips.hook_radius()>.7,"three tips cost another 12000 gold and widen catches again")
	tips.purchase(2)
	check(tips.level(2)==3 and tips.cost(2)==0,"three is the hard upgrade cap, never a hidden fourth tip")
	var saved_tips := GameModel.new(tips.save_path)
	check(saved_tips.level(2)==3 and saved_tips.profile["gold"]==0,"new tip count and price survive a profile reload")
	model.profile = GameModel.fresh_profile()
	model.profile["levels"][0] = 6
	check(model.shot_range()==12 and model.value("throw_speeds",6)==16,"long rope immediately extends reach without changing throwing speed")
	model.profile["levels"] = [1,1,1,1,1,1,6]
	check(model.shot_range()==5.5 and model.value("rope_lengths",0)==5.5 and model.value("throw_speeds",6)==40,"stronger throw accelerates the projectile while respecting the short rope")
	model.profile["levels"][0] = 6
	check(model.shot_range()==12 and model.value("throw_speeds",6)==40,"long rope and strong throw combine independent reach and speed")
	model.profile["levels"] = [1,1,1,1,1,1,1]
	check(model.shot_range()==5.5 and model.value("throw_speeds",6)==16,"weak throw and short rope retain their separate base values")
	model.learn_control("aim")
	model.learn_control("aim")
	model.save()
	var lessons := GameModel.new(model.save_path)
	check(lessons.profile["learned_controls"]==["aim"],"completed lessons persist once without repeating across runs")
	model.profile["reached_zones"] = 2
	model.profile["gold"] = 90
	check(model.recommended_upgrade()==0,"result can point a new player to an affordable unlocked rope upgrade")
	model.profile["reached_zones"] = 1
	model.purchase(0)
	check(model.level(0)==2 and model.profile["gold"]==0,"gold from early failed attempts can buy the first upgrade before reaching 200 m")
	model.profile["gold"] = 1000
	model.purchase(0)
	check(model.level(0)==2 and model.profile["gold"]==1000,"higher upgrades still require their mountain zone")
	model.profile["gold"] = 100000
	model.profile["reached_zones"] = 6
	model.profile["active"] = {"id":"pending"}
	var before_levels: Array = model.profile["levels"].duplicate()
	model.purchase(1)
	check(model.profile["levels"]==before_levels and model.profile["gold"]==100000,"an active saved run cannot buy upgrades through the model")
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
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"engine":Engine.get_version_info()["string"]}
	var output := FileAccess.open(directory.path_join("rules-test-report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("RULES_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
