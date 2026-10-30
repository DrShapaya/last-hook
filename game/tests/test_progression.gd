extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("PROGRESSION FAILED: "+description)

func write_profile(path: String, profile: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(profile))
	file.close()

func find(id: int, at: Vector2, value: int) -> Dictionary:
	return {"pos":at,"picked":false,"item":{"id":id,"tier":0,"value":value}}

func has_label(game, value: String) -> bool:
	for label in game.hud.content.find_children("*","Label",true,false):
		if label.text==value: return true
	return false

func has_text(node: Node, value: String) -> bool:
	for label in node.find_children("*","Label",true,false):
		if label.text==value: return true
	return false

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("progression-migration.json")
	var old := GameModel.fresh_profile()
	old["version"] = 3
	old["gold"] = 1234
	old["diamonds"] = 17
	old["levels"] = [6,6,3,6,6,6,6]
	old["active"] = {"id":"in-progress","bag":[{"id":23,"tier":5,"value":560},{"id":24,"tier":0,"value":40,"kind":"coin"}],"picked":[23,24],"broken":[1,2],"active_reserves":[],"seed":12345,"revive_used":true}
	write_profile(path,old)
	var migrated := GameModel.new(path)
	# v3 -> v5 returns 27962; v5 -> v6 returns the cheaper five-level tracks
	# (78435); the old coin still in the bag is banked once (+40).
	check(migrated.profile["gold"]==1234+27962+78435+40+3120,"maximum existing kit returns the net price reduction of every migration")
	var top := GameModel.default_levels()
	top.merge({GameModel.ROPE:5,GameModel.IMPULSE:5,GameModel.RADIUS:5,GameModel.DOUBLE:2,GameModel.BAG:5,GameModel.MAGNET:5,GameModel.RECOVERY:5,GameModel.THROW:5,GameModel.SLOWMO:3,GameModel.REEL_OUT:3,GameModel.SLOWMO_REST:3},true)
	check(migrated.profile["upgrade_levels"]==top and migrated.profile["diamonds"]==17 and migrated.hook_count()==2,"migration keeps every track at its new maximum and the double hook selected")
	var migrated_active: Dictionary = migrated.profile["active"]
	check(migrated_active["id"]=="in-progress" and migrated_active["bag"].size()==1 and int(migrated_active["bag"][0]["id"])==23 and migrated_active["bag"][0]["family"]=="valuable" and migrated_active["picked"]==[23,24] and migrated_active["broken"]==[1,2] and int(migrated_active["seed"])==12345,"migration keeps the active run, its loot, spent grips and picked ids")
	check(migrated.profile["coin_ledger"]["run"]=="in-progress" and migrated.profile["coin_ledger"]["ids"]==[24] and migrated.run_coins("in-progress")==40,"an old coin in the active bag moves to the ledger instead of the bag")
	check(migrated.profile["reached_acts"]==1 and migrated.stock("beacon")==1,"old profiles get acts reached from their best height and the trial beacon")
	migrated.save()
	var reloaded := GameModel.new(path)
	check(reloaded.profile==migrated.profile,"saving v4 makes compensation idempotent")
	# Backup may still be v3 when the primary is damaged. It must receive one
	# compensation relative to its own old wallet, never the new wallet twice.
	var damaged := FileAccess.open(path,FileAccess.WRITE)
	damaged.store_string("broken")
	damaged.close()
	var recovered := GameModel.new(path)
	check(recovered.profile["gold"]==migrated.profile["gold"],"fallback from a v3 backup cannot double the migration credit")
	old["levels"] = [3,3,1,3,3,3,3]
	old["active"] = {}
	write_profile(path,old)
	var middle := GameModel.new(path)
	check(middle.profile["gold"]==1234+302+288 and middle.level(GameModel.ROPE)==3 and middle.level(GameModel.THROW)==4 and middle.level(GameModel.MAGNET)==4,"middle levels are kept; only cheaper steps are refunded and dearer ones create no debt")
	old["levels"] = [1,1,1,1,1,1,1]
	write_profile(path,old)
	var starter := GameModel.new(path)
	check(starter.profile["gold"]==1234,"unbought equipment creates no migration windfall")
	for fixture in [{"version":6,"gold":0,"upgrade_levels":[1,1,1,1,1,1,1,1]}]:
		write_profile(path,fixture)
		var moved := GameModel.new(path)
		check(moved.level(GameModel.THROW)==1 and moved.level(GameModel.SLOWMO)==3 and moved.level(GameModel.REEL_OUT)==3 and moved.level(GameModel.SLOWMO_REST)==3,"free steps match the old feel")
		check(moved.level(GameModel.ROPE)==1 and moved.level(GameModel.SWING)==1 and int(moved.profile["gold"])==0,"a fresh save owes and gets nothing")
	write_profile(path,{"version":6,"gold":0,"upgrade_levels":[1,1,4,1,1,1,1,1],"upgrade_choices":{"hook":4}})
	var hooks := GameModel.new(path)
	check(hooks.level(GameModel.RADIUS)==5 and hooks.level(GameModel.DOUBLE)==2 and hooks.hook_count()==2,"two triple hooks stay")
	write_profile(path,{"version":6,"gold":0,"upgrade_levels":[3,1,1,1,1,1,1,1]})
	var refund := GameModel.new(path)
	check(int(refund.profile["gold"])==70,"a rope paid 470 and now worth 400 returns 70")
	refund.save()
	check(int(GameModel.new(path).profile["gold"])==70,"the refund happens once")
	for version in [1,3,4,5]:
		write_profile(path,{"version":version,"gold":10,"levels":[2,2,2,2,2,2,2,1],"best":0.0})
		check(int(GameModel.new(path).profile["version"])==GameModel.PROFILE_VERSION,"version %d walks the whole migration chain" % version)
	starter.profile["gold"] = 100000
	starter.profile["diamonds"] = 100
	starter.profile["summit_cleared"] = true
	starter.profile["cleared_locations"] = [0]
	starter.profile["active"] = {"id":"ongoing"}
	starter.purchase_location(1)
	check(starter.profile["locations"]==[0] and starter.profile["gold"]==100000,"model refuses a location purchase during an active attempt")
	starter.profile["active"] = {}
	starter.purchase_location(-1)
	starter.purchase_location(99)
	check(starter.profile["locations"]==[0] and starter.profile["gold"]==100000,"invalid location IDs cannot charge or unlock a different location")

	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["gold"] = 2200
	game.hud.equipment_category = "hook"
	game.hud.select_menu("equipment")
	await process_frame
	var double_button: Button
	for button in game.hud.content.find_children("*","Button",true,false):
		# The price is a label inside the button and the row is named by its card.
		if button.text=="Улучшить" and has_text(button.get_parent(),"Двойной крюк"): double_button = button
	check(double_button!=null and not double_button.disabled,"the double hook has an enabled real menu button")
	if double_button!=null: double_button.pressed.emit()
	game._process(.01)
	check(game.model.level(GameModel.DOUBLE)==2 and game.model.hook_count()==2,"a menu purchase updates the saved hook")
	game.model.set_level(GameModel.RADIUS,3)
	game.model.save()
	game.model.load_profile()
	game.start_run(false)
	game._process(.01)
	check(game.model.level(GameModel.DOUBLE)==2 and game.explorer.tip_count==3 and game.explorer.hook_count==2,"a wide double hook survives profile reload and a fresh run")
	game.hud.equipment_category = "movement"
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.world.finds.clear()
	game.sim.pos = Vector2(0,30)
	game.model.set_level(GameModel.MAGNET,5)
	game.world.finds.append(find(1,Vector2(1,30),40))
	game.world.finds.append(find(2,Vector2(1.8,30),200))
	game._collect_finds()
	check(game.model.bag.size()==1 and game.model.bag[0]["id"]==2,"one free slot collects the valuable magnetic find regardless of spawn order")
	check(not game.world.finds[0]["picked"],"uncollected cheaper loot remains in the world")
	game.model.bag.clear()
	game.model.picked.clear()
	game.world.finds.reverse()
	for item in game.world.finds: item["picked"] = false
	game._collect_finds()
	check(game.model.bag[0]["id"]==2,"magnet choice is independent of array ordering")
	game.world.finds.append(find(3,Vector2(.2,30),40))
	game._collect_finds()
	check(game.model.bag[0]["id"]==2,"a full bag is never automatically replaced")
	game.model.discard(0)
	game._collect_finds()
	check(game.model.bag[0]["id"]==3,"deliberate direct contact takes priority over distant magnetic loot")
	# Zone rewards enter the wallet once during play; resuming and showing the
	# result must account for them without a second currency award.
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.sim.pos = Vector2(0,21+game.START_Y)
	game.sim.highest = game.sim.pos.y
	game.camera_y = 23
	game._physics_process(1.0/120)
	check(game.zone_gold==200 and game.zone_diamonds==3,"zone reward bookkeeping includes both currencies")
	game.save_snapshot()
	game.model.load_profile()
	game.resume_run()
	check(game.zone_gold==200 and game.zone_diamonds==3,"zone reward breakdown survives saving and resuming")
	var diamonds_before := int(game.model.profile["diamonds"])
	game.finish_run(false)
	check(game.settlement["zone_diamonds"]==3 and game.model.profile["diamonds"]==diamonds_before,"result reports previously banked zone diamonds without paying them again")
	check(has_label(game,"Новые зоны, уже на счету") and has_label(game,"+3"),"result displays the zone gold row and its diamond reward")
	game.show_menu()
	game.hud.touch_controls_hint = true
	game.hud.settings_section = "controls"
	game.hud.select_menu("settings")
	check(has_label(game,"Отцепись"),"touch settings display the fourth control instruction")
	game.model.profile["gold"] = 100000
	game.model.set_level(GameModel.ROPE,2)
	game.hud.equipment_category = "rope"
	game.hud.select_menu("equipment")
	var act_gate := false
	for button in game.hud.content.find_children("*","Button",true,false):
		if button.text=="Пройди первый акт": act_gate = button.disabled
	check(act_gate,"locked upgrade names the act it waits for")
	var use_hint := false
	for label in game.hud.content.find_children("Use","Label",true,false):
		use_hint = use_hint or label.text=="Внешние карнизы"
	check(use_hint,"each upgrade row says where its next level helps")
	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("progression-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	print("PROGRESSION_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
