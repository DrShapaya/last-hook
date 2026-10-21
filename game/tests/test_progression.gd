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
	old["active"] = {"id":"in-progress","bag":[{"id":23,"tier":5,"value":560}],"picked":[23],"broken":[1,2],"active_reserves":[],"seed":12345,"revive_used":true}
	write_profile(path,old)
	var migrated := GameModel.new(path)
	check(migrated.profile["gold"]==1234+27962,"maximum existing kit returns the complete net price reduction")
	check(migrated.profile["levels"]==[6,6,4,6,6,6,6,1] and migrated.profile["diamonds"]==17,"migration preserves all equipment and maps the old maximum hook to the new final stage")
	var migrated_active: Dictionary = migrated.profile["active"].duplicate(true)
	migrated_active["seed"] = int(migrated_active["seed"]) # JSON decodes numbers as floats.
	check(migrated_active==old["active"],"economic migration preserves an active run including loot and spent grips")
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
	check(middle.profile["gold"]==1234 and middle.profile["levels"]==old["levels"]+[1],"more expensive middle levels never create debt or remove purchased equipment")
	old["levels"] = [1,1,1,1,1,1,1]
	write_profile(path,old)
	var starter := GameModel.new(path)
	check(starter.profile["gold"]==1234,"unbought equipment creates no migration windfall")
	starter.profile["gold"] = 100000
	starter.profile["diamonds"] = 100
	starter.profile["summit_cleared"] = true
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
	game.model.profile["gold"] = 5700
	game.hud.select_menu("equipment")
	for expected in [2,3,4]:
		var tip_button: Button
		var price := 900 if expected==2 else 1800 if expected==3 else 3000
		for button in game.hud.content.find_children("*","Button",true,false):
			# The price is a label inside the button and the row is named by its card.
			if button.text=="Улучшить" and has_text(button.get_parent(),"Крюки") and has_text(button,str(price)): tip_button = button
		check(tip_button!=null and not tip_button.disabled,"tip purchase has an enabled real menu button for %d tips" % expected)
		if tip_button!=null: tip_button.pressed.emit()
		game._process(.01)
		var visible_tips := 0
		for piece in game.explorer.prongs:
			if piece.visible: visible_tips += 1
		var expected_tips := 3 if expected in [2,4] else 1
		var expected_count := 2 if expected>=3 else 1
		check(game.model.level(2)==expected and visible_tips==expected_tips and game.model.hook_count()==expected_count,"actual menu purchase updates the saved hook configuration to stage %d" % expected)
	game.model.load_profile()
	game.start_run(false)
	game._process(.01)
	check(game.model.level(2)==4 and game.explorer.tip_count==3 and game.explorer.hook_count==2,"two triple hooks survive profile reload and a fresh run")
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.world.obstacles.clear()
	game.world.ledges.clear()
	game.world.finds.clear()
	game.sim.pos = Vector2(0,30)
	game.model.profile["levels"][4] = 6
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
	game.hud.select_menu("settings")
	check(has_label(game,"Отцепись"),"touch settings display the fourth control instruction")
	game.model.profile["gold"] = 100000
	game.model.profile["levels"][0] = 2
	game.hud.select_menu("equipment")
	var height_gate := false
	for button in game.hud.content.find_children("*","Button",true,false):
		if button.text=="Достигни 400 м": height_gate = button.disabled
	check(height_gate,"locked upgrade tells the actual required height")
	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("progression-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	report.close()
	print("PROGRESSION_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
