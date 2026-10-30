extends SceneTree

# Chat 4 acceptance: coins banked through the ledger, the item contract and
# its placement roles (generator v15), the full-bag swap, sets, contracts,
# settlement and the four active items with their save/load contract.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("ECONOMY FAILED: "+description)

func make_world(seed_number: int, location: int, version: int = 0) -> MountainWorld:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_number,location,version)
	var total := float(LevelCatalog.level(location)["height_units"])
	world.generate_to(total+6,true,total)
	return world

func find_at(item: Dictionary, at: Vector2) -> Dictionary:
	return {"item":item,"pos":at,"picked":false,"rare":false}

func saved_profile(game) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(game.model.save_path))

func attach_first(game) -> void:
	var first: Dictionary = game.world.anchor_by_id(game.world.main_route[0])
	game.sim.pos = first["pos"]+Vector2(0,-2.8)
	game.sim.vel = Vector2.ZERO
	game.sim.attach(first["pos"],game.model.shot_range())
	game.anchor_id = first["id"]
	game.anchor_contact = first["pos"]
	game.safe_anchor_id = first["id"]
	game.safe_contact = first["pos"]
	game.safe_position = game.sim.pos

func run_tests() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	placement_tests()
	model_tests()
	await scene_tests()
	await strap_in_flight_tests()
	var report := FileAccess.open(OS.get_environment("LASTHOOK_SAVE_DIR").path_join("economy-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	print("ECONOMY_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

# --- P3: item contract and placement -------------------------------------------------

func placement_tests() -> void:
	var fields := ["id","item_id","family","location_id","act_id","tier","sell_value","craft_value","set_id","use_tag","rarity","weight"]
	var complete := true
	var ids_ok := true
	var clear_ok := true
	var landmarks_ok := true
	var contract_ok := true
	var basics_ok := true
	var problems: Array = []
	for location in range(3):
		for seed_number in [58273,4242,777]:
			var world := make_world(seed_number,location)
			var layout := world.layout as ExpeditionLayout
			check(layout.economy_loot,"new attempts place v15 finds by role: location %d" % location)
			var per_act := {}
			for index in range(world.finds.size()):
				var find: Dictionary = world.finds[index]
				var item: Dictionary = find["item"]
				if find.get("withdrawn",false): continue
				for key in fields: complete = complete and item.has(key)
				ids_ok = ids_ok and int(item["id"])==index and not str(item["item_id"]).is_empty()
				var act := int(find["act"])
				if not per_act.has(act): per_act[act] = {}
				per_act[act][find["role"]] = int(per_act[act].get(find["role"],0))+1
				var at: Vector2 = find["pos"]
				# Clear of grips, obstacles, other finds and hazards that hit it.
				for anchor in world.anchors:
					if anchor["pos"].distance_to(at)<LootPlacement.GRIP_CLEARANCE: problems.append(["grip",location,seed_number,index])
				for obstacle in world.obstacles:
					if MountainLayout.blocked(at,at,obstacle,Vector2(.3,.3)): problems.append(["obstacle",location,seed_number,index])
				for other in world.finds.slice(0,index):
					if not other.get("withdrawn",false) and other["pos"].distance_to(at)<LootPlacement.FIND_SPACING-.001: problems.append(["find",location,seed_number,index])
				for hazard in layout.hazards:
					match str(hazard["kind"]):
						"field":
							if hazard.get("affects_main",false) and (hazard["rect"] as Rect2).has_point(at): problems.append(["storm",location,seed_number,index])
						"falling":
							if absf(at.x-float(hazard["x"]))<float(hazard["radius"])+.5 and at.y>float(hazard["bottom"]) and at.y<float(hazard["top"]): problems.append(["icicle",location,seed_number,index])
						"contact":
							if at.distance_to(hazard["pos"])<float(hazard["radius"])+1.4: problems.append(["contact",location,seed_number,index])
			for act in range(layout.spans.size()):
				var roles: Dictionary = per_act.get(act,{})
				landmarks_ok = landmarks_ok and int(roles.get("landmark",0))==1
				basics_ok = basics_ok and int(roles.get("main_safe",0))>=1 and (int(roles.get("detour",0))+int(roles.get("contract_target",0))+int(roles.get("choice",0))+int(roles.get("fork_collection",0))+int(roles.get("fork_risky_shortcut",0))+int(roles.get("fork_speed",0)))>=1
			var cargo: Array = world.finds.filter(func(f): return f["item"]["family"]=="contract")
			contract_ok = contract_ok and cargo.size()==1 and not layout.contract.is_empty() and int(layout.contract["find"])==int(cargo[0]["item"]["id"]) and cargo[0]["role"]=="contract_target" and not str(layout.contract["tag"]).is_empty()
			world.free()
	check(complete,"every v15 item carries the full item contract")
	check(ids_ok,"find ids are their indices and every item has a stable item_id")
	clear_ok = problems.is_empty()
	check(clear_ok,"finds keep clear of grips, obstacles, each other, main-path storms, icicle lines and contact hazards %s" % str(problems.slice(0,6)))
	check(landmarks_ok,"each act has exactly one landmark relic")
	check(basics_ok,"each act has a main-path find and at least one branch find")
	check(contract_ok,"each summit run has one contract cargo on a branch, named in the run goal")
	# The same seed resolves the same finds however generation is chunked.
	var whole := make_world(4242,1)
	var chunked := MountainWorld.new()
	chunked.visuals_enabled = false
	root.add_child(chunked)
	chunked.setup(4242,1)
	for height in [30.0,61.0,97.0,146.0]: chunked.generate_to(height,true,140)
	var same := whole.finds.size()==chunked.finds.size()
	for index in range(mini(whole.finds.size(),chunked.finds.size())):
		same = same and whole.finds[index]["pos"]==chunked.finds[index]["pos"] and whole.finds[index]["item"]==chunked.finds[index]["item"]
	check(same and (whole.layout as ExpeditionLayout).contract==(chunked.layout as ExpeditionLayout).contract,"placement is deterministic regardless of generation chunks")
	whole.free()
	chunked.free()
	# Saved v14 attempts keep their old finds; geometry of v15 equals v14.
	var old := make_world(58273,0,14)
	var fresh := make_world(58273,0)
	var same_grips := old.anchors.size()==fresh.anchors.size()
	for index in range(mini(old.anchors.size(),fresh.anchors.size())): same_grips = same_grips and old.anchors[index]["pos"]==fresh.anchors[index]["pos"]
	check(not (old.layout as ExpeditionLayout).economy_loot and old.finds.all(func(f): return not f["item"].has("family")) and same_grips,"a saved v14 attempt keeps its finds; v15 changes finds only, not grips")
	check(MountainWorld.resumable(14,2) and MountainWorld.resumable(15,1),"v14 and v15 attempts both resume")
	old.free()
	fresh.free()
	# Coin budget on one full summit: direct coins exist on every expedition.
	for location in range(3):
		var world := make_world(1000,location)
		var coins := 0
		var families := {}
		for f in world.finds:
			families[f["item"]["family"]] = true
			if f["item"]["family"]=="coin": coins += int(f["item"]["value"])
		check(coins>=250 and families.has("valuable") and families.has("relic") and families.has("material") and families.has("contract"),"location %d offers coins (%d gold) and all four bag families" % [location,coins])
		world.free()

# --- Model: bag, ledger, settlement, consumables ----------------------------------------

func model_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	var model := GameModel.new(directory.path_join("economy-model.json"))
	model.profile = GameModel.fresh_profile()
	var coin := ItemCatalog.coin(7,0,"root_wall",8)
	model.begin_run_ledger("run-a")
	check(not model.try_pick(coin) and model.bag.is_empty(),"a coin never enters the bag")
	check(model.collect_coin("run-a",coin) and model.profile["gold"]==8 and model.picked.has(7),"a coin is banked at once")
	check(not model.collect_coin("run-a",coin) and model.profile["gold"]==8,"a repeated coin callback pays nothing")
	model.bag = [ItemCatalog.valuable(1,0,"root_wall",2)]
	check(model.bag_value()==130 and model.run_coins("run-a")==8,"bag value ignores banked coins")
	var result := model.settle("run-a","summit",30,false,0)
	check(result["coins"]==8 and result["loot"]==32 and result["total"]==result["height"]+32 and model.profile["gold"]==8+result["total"],"defeat keeps banked coins and pays only the recovered bag; settlement never pays coins again")
	# Special slot of a level-5 bag.
	model.set_level(GameModel.BAG,5)
	model.bag.clear()
	model.picked.clear()
	for index in range(5): model.try_pick(ItemCatalog.valuable(100+index,0,"root_wall",0))
	check(model.bag_capacity()==6 and not model.try_pick(ItemCatalog.valuable(110,0,"root_wall",0)) and model.try_pick(ItemCatalog.material(111,0,"root_wall",0,"fiber")),"the last slot of a full bag takes a material, never a sixth valuable")
	check(not model.try_pick(ItemCatalog.relic(112,0,"root_wall",0,"forest_relic")),"a bag with every slot used refuses more")
	# Swap choice: the cheapest valuable may make room for an artifact.
	model.set_level(GameModel.BAG,1)
	model.bag = [ItemCatalog.valuable(200,0,"root_wall",0)]
	model.picked = [200]
	var artifact := ItemCatalog.valuable(201,0,"root_wall",2,"artifact")
	check(model.worth_prompt(artifact) and not model.worth_prompt(ItemCatalog.valuable(202,0,"root_wall",3)),"only rare and contract finds ask about a swap")
	check(model.swap_in(artifact,model.cheapest_index(artifact)) and model.bag.size()==1 and int(model.bag[0]["id"])==201,"an accepted swap replaces the cheapest item")
	# Sets, landmarks, materials and contracts at the summit.
	model.profile = GameModel.fresh_profile()
	model.set_level(GameModel.BAG,5)
	model.bag = [ItemCatalog.relic(1,0,"root_wall",1,"forest_relic"),ItemCatalog.relic(2,0,"root_wall",1,"forest_relic"),ItemCatalog.relic(3,0,"root_wall",1,"forest_relic"),
		ItemCatalog.relic(4,0,"root_wall",2,"forest_relic",true),ItemCatalog.material(5,0,"root_wall",0,"silk"),ItemCatalog.contract(6,0,"root_wall",3,"root_impulse")]
	var win := model.settle("run-b","summit",120,true,0,{"contract":"root_impulse","spent":["beacon"]})
	check(model.profile["unlocked_sets"]==["forest_relic"] and model.profile["set_parts"]["forest_relic"]==3 and model.profile["landmarks"]==["forest_relic"],"three parts complete the act's set; the landmark is recorded")
	check(model.materials("silk")==1 and win["materials"]=={"silk":1},"a material goes to the material wallet")
	check(win["contract_done"] and win["contract"]==250 and model.profile["completed_contracts"]==["root_impulse"] and win["tokens"]==2 and model.profile["mastery_tokens"]==2,"the contract cargo at the summit pays its reward; the set and the first contract give mastery tokens")
	check(win["spent"]==["beacon"] and win["total"]==win["height"]+win["loot"]+win["finish"]+250,"the result lists spent items and every gold source")
	model.bag = [ItemCatalog.contract(7,0,"root_wall",3,"root_impulse")]
	var again := model.settle("run-c","summit",120,true,0,{"contract":"root_impulse"})
	check(again["contract"]==125 and again["tokens"]==0,"a repeated contract pays half and no token")
	model.bag = [ItemCatalog.contract(8,0,"root_wall",3,"root_impulse")]
	check(model.settle("run-d","summit",60,false,0,{"contract":"root_impulse"})["contract"]==0,"a failed run completes no contract")
	model.bag = [ItemCatalog.relic(9,0,"old_post",1,"post_seal"),ItemCatalog.material(10,0,"old_post",0,"fiber")]
	var lost := model.settle("run-e","summit",60,false,0)
	check(lost["recovery"]==25 and model.profile["set_parts"].get("post_seal",0)==1 and model.materials("fiber")==0,"a defeat keeps the recovery share of whole items, relics first (30% of 2 -> 1)")
	# Consumables: stock, gold, materials, conflicts, charges.
	model.profile = GameModel.fresh_profile()
	check(model.stock("beacon")==1 and model.profile["active_loadout"]==["beacon",""],"a new profile has one trial beacon in its loadout")
	model.profile["gold"] = 1000
	check(model.buy_consumable("glide").begins_with("Куплено") and model.profile["gold"]==820 and model.stock("glide")==1,"glide costs 180 gold")
	model.buy_consumable("glide")
	check(model.buy_consumable("glide")=="В запасе уже 2" and model.stock("glide")==2,"stock holds at most two of a kind")
	model.profile["material_wallet"] = {"core":1}
	check(model.craft_consumable("tape").begins_with("Изготовлено") and model.materials("core")==0 and model.stock("tape")==1,"the strap is made from one rare material")
	check(model.craft_consumable("booster")=="Не хватает материалов","crafting needs the whole recipe")
	model.set_loadout(1,"glide")
	check(model.set_loadout(0,"tape").begins_with("Не сочетается") and model.profile["active_loadout"]==["beacon","glide"],"rescue items that do not stack cannot share the loadout")
	# Everything bought goes into the next run, one charge of each, taken from
	# the stock when the run starts.
	check(model.run_items().map(func(entry): return entry["id"])==["beacon","glide","tape"],"the next run carries one of every item in stock, no slots needed")
	var items := model.take_run_items()
	check(items.size()==3 and model.stock("beacon")==0 and model.stock("glide")==1 and model.stock("tape")==0,"starting a run takes one charge of each carried item from the stock")
	check(model.spend_item(items,0) and not model.spend_item(items,0),"a carried charge is used exactly once")
	model.profile["active"] = {"id":"busy"}
	check(model.buy_consumable("beacon")=="Сначала заверши текущую попытку","nothing is bought during a run")

# --- Scene: pickup, swap, items, strap, save/load ---------------------------------------

func scene_tests() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	attach_first(game)
	game.world.finds.clear()
	var hero: Vector2 = game.sim.pos
	var coin := ItemCatalog.coin(900,0,"root_wall",8)
	game.world.finds.append(find_at(coin,hero))
	game._collect_finds()
	# Coins are written together shortly after the pickup, not one write each.
	var before_flush := saved_profile(game)
	check(not (before_flush.get("coin_ledger",{}).get("ids",[]) as Array).has(900.0),"a picked coin waits for the shared snapshot instead of writing the file at once")
	game.world.finds.append(find_at(ItemCatalog.coin(907,0,"root_wall",8),hero))
	game._collect_finds()
	check(not (saved_profile(game).get("coin_ledger",{}).get("ids",[]) as Array).has(907.0),"a second coin in the same moment joins the pending write")
	game._process(.6)
	var disk := saved_profile(game)
	check((disk["coin_ledger"]["ids"] as Array).has(907.0) and int(disk["gold"])==16,"both coins reach disk in one write within half a second")
	game.model.profile["gold"] = 8
	game.model.profile["coin_ledger"]["ids"].erase(907)
	game.model.profile["coin_ledger"]["gold"] = 8
	game.model.picked.erase(907)
	game.world.finds.pop_back()
	game.save_snapshot()
	disk = saved_profile(game)
	check(game.model.profile["gold"]==8 and game.model.bag.is_empty() and int(disk["gold"])==8 and (disk["coin_ledger"]["ids"] as Array).has(900.0) and (disk["active"]["picked"] as Array).has(900.0),"direct contact banks the coin; wallet, ledger and picked id reach disk in one save")
	game.world.finds[0]["picked"] = false
	game._collect_finds()
	check(game.model.profile["gold"]==8 and game.world.finds[0]["picked"],"a repeated pickup callback pays nothing")
	# Magnet: one radius for coins and finds from level 2.
	game.model.set_level(GameModel.MAGNET,2)
	game.world.finds.append(find_at(ItemCatalog.coin(901,0,"root_wall",8),hero+Vector2(.8,0)))
	game.world.finds.append(find_at(ItemCatalog.valuable(902,0,"root_wall",1),hero+Vector2(-.8,0)))
	game._collect_finds()
	check(game.model.profile["gold"]==16 and game.model.bag.size()==1,"the level-2 magnet pulls coins and finds alike")
	# Full bag: coins still bank; a plain find stays; a more valuable artifact
	# replaces the cheapest eligible item automatically.
	game.model.bag = [ItemCatalog.valuable(903,0,"root_wall",0)]
	game.model.picked.append(903)
	game.world.finds.append(find_at(ItemCatalog.coin(904,0,"root_wall",8),hero))
	game.world.finds.append(find_at(ItemCatalog.valuable(905,0,"root_wall",0),hero+Vector2(.2,0)))
	game.world.finds.append(find_at(ItemCatalog.valuable(906,0,"root_wall",3,"artifact"),hero+Vector2(-.2,0)))
	game._collect_finds()
	check(game.model.profile["gold"]==24 and game.model.bag.size()==1 and int(game.model.bag[0]["id"])==906,"a full bag banks coins and automatically keeps the more valuable artifact")
	check(game.swap_offer.is_empty() and not is_instance_valid(game.hud.swap_panel),"automatic replacement leaves no pending comparison panel")
	# Restart: the ledger and picked coins survive; nothing pays twice.
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	game.world.finds.clear()
	game.world.finds.append(find_at(coin,game.sim.pos))
	game.world.finds[0]["picked"] = game.model.picked.has(900)
	game._collect_finds()
	check(game.model.profile["gold"]==24 and game.model.run_coins(game.run_id)==24,"after a restart the same coin cannot be banked again")
	# Active items: beacon in flight.
	game.model.profile["consumable_stock"] = {"beacon":1,"glide":1}
	game.run_items = game.model.take_run_items()
	game.hud.show_play()
	check(game.hud.item_buttons.size()==2 and game.model.stock("beacon")==0 and game.model.stock("glide")==0,"the HUD shows one button per carried item; their charges left the stock at the start")
	attach_first(game)
	game.activate_item(0)
	check(game.run_items[0]["used"]==false,"an item that needs flight is not used while hanging")
	game.release_hook(false,"test")
	game.sim.vel = Vector2(0,3)
	game.activate_item(0)
	check(game.run_items[0]["used"] and game.item_effect_id()=="beacon" and not game.beacon_targets.is_empty(),"the beacon starts in flight, is used up and marks valid exits")
	game.activate_item(1)
	check(not game.run_items[1]["used"],"a second item waits for the running effect")
	game.save_snapshot()
	var saved_items: Array = saved_profile(game)["active"]["run_items"]
	check(saved_items.size()==2 and bool(saved_items[0]["used"]) and not bool(saved_items[1]["used"]) and int(saved_profile(game)["consumable_stock"]["beacon"])==0,"used charges and the loadout are saved with the run")
	game._update_item_effect(3.1)
	check(game.item_effect.is_empty() and game.beacon_targets.is_empty(),"the beacon ends after 3 s")
	# Glide: slower fall, then normal physics again.
	game.sim.attached = false
	game.sim.grounded = false
	game.sim.vel = Vector2(0,-7)
	game.activate_item(1)
	game._apply_item_effect(1.0/120)
	check(game.item_effect_id()=="glide" and game.sim.vel.y>=-2.2001 and game.run_items[1]["used"],"glide caps the fall speed")
	game._update_item_effect(3.6)
	game.sim.vel = Vector2(0,-7)
	game._apply_item_effect(1.0/120)
	check(game.item_effect.is_empty() and game.sim.vel.y<-6.9,"after glide the fall is normal again")
	# Booster: tapped on the ground it waits for flight, then pushes the
	# flight along, capped. A second tap takes a waiting item back.
	game.run_items = [{"id":"booster","used":false},{"id":"tape","used":false}]
	game.sim.attached = false
	game.sim.grounded = true
	game.activate_item(0)
	check(not game.run_items[0]["used"] and game.item_armed() and game.item_effect_id()=="booster","on the ground the booster waits for flight without spending")
	game.activate_item(0)
	check(game.item_effect.is_empty() and not game.run_items[0]["used"],"a second tap cancels a waiting booster")
	game.activate_item(0)
	game._update_item_effect(1.0/120)
	check(game.item_armed(),"a waiting booster stays armed on the ground")
	game.sim.grounded = false
	game.sim.vel = Vector2(3,4)
	game._update_item_effect(1.0/120)
	var before: float = game.sim.vel.length()
	game._apply_item_effect(.1)
	check(game.run_items[0]["used"] and not game.item_armed() and game.sim.vel.length()>before and game.sim.vel.length()<=13.001,"the booster fires on take-off and speeds the flight, capped")
	game._end_item_effect()
	# A parachute nobody tapped opens by itself on a fall about to cross the
	# lower edge, so a bought item always does its job.
	var carried: Array = game.run_items
	game.run_items = [{"id":"glide","used":false}]
	game.item_effect = {}
	game.sim.attached = false
	game.sim.grounded = false
	game.sim.vel = Vector2(0,-9)
	game.sim.pos.y = game.screen_bottom_y()+2.0
	game._update_item_effect(1.0/120)
	check(game.item_running("glide") and game.run_items[0]["used"],"an untapped parachute opens by itself on a dangerous fall")
	game._end_item_effect()
	game.run_items = carried
	# Strap: a fatal fall returns to safety once; the last find falls out.
	attach_first(game)
	game.model.bag = [ItemCatalog.valuable(910,0,"root_wall",0),ItemCatalog.valuable(911,0,"root_wall",1)]
	game.sim.attached = false
	game.sim.pos += Vector2(0,-1)
	game.fail_run("strap fixture")
	check(game.state=="play" and game.run_items[1]["used"] and not game.revive_used and game.model.bag.size()==1 and int(game.model.bag[0]["id"])==910,"the strap returns to the safe point once and drops the last find, without using the continuation")
	game.fail_run("second fall")
	check(game.state in ["revive","result"],"the strap is single use; the next fall follows the normal rules")
	if game.state=="revive": game.finish_run(false)
	check(game.state=="result" and (game.settlement["spent"] as Array).has("tape") and (game.settlement["spent"] as Array).has("booster"),"the result lists the spent items")
	game.queue_free()
	await process_frame

# The strap fires while a thrown hook is still in the air: the rescue ends that
# shot, and nothing in flight may catch a grip once the hero hangs again.
func strap_in_flight_tests() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.run_seed = 58273
	game._create_world(58273,0,126)
	game.model.profile["consumable_stock"] = {"tape":1}
	game.run_items = [{"id":"tape","used":false}]
	attach_first(game)
	game.release_hook(false,"test")
	game.sim.vel = Vector2.ZERO
	game.fire_hook(Vector2(.15,1).normalized())
	game.sim.pos += Vector2(0,-1)
	game.fail_run("strap during a throw")
	check(game.state=="play" and game.sim.attached and not game.bolt_active and not game.bolt_returning and game.hook_volley==null,"the strap rescue ends a hook that was still flying")
	var catches_before: int = game.catches
	var held: int = game.anchor_id
	game.bolt_active = true
	game.bolt_pos = game.sim.pos
	game.hook_flight.launch(game.sim.pos,Vector2(.15,1).normalized(),game.model.throw_speed(),Vector2.ZERO)
	for step in range(240):
		if game.bolt_active: game._update_bolt(1.0/120)
		elif game.bolt_returning: game._update_return(1.0/120)
	check(game.catches==catches_before and game.anchor_id==held,"a hook in flight never catches while the hero already hangs on a grip")
	game.queue_free()
	await process_frame
