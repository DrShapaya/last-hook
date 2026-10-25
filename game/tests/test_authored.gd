extends SceneTree

# Prepared routes (generator v16), per-route records, per-expedition treasure
# sets and the music/route profile keys.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("AUTHORED FAILED: "+description)

func make_route(location: int, index: int) -> MountainWorld:
	var spec := LevelCatalog.route(location,index)
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(int(spec["seed"]),location,0,false,index)
	var total := float(LevelCatalog.level(location)["height_units"])
	world.generate_to(total+6,true,total)
	return world

func signature(world: MountainWorld) -> String:
	var parts: Array = []
	for a in world.anchors: parts.append([a["pos"],a["kind"],a["permanent"]])
	for f in world.finds: parts.append([f["pos"],f["item"]["value"],f["item"].get("sprite","")])
	for l in world.layout.landmarks: parts.append([l["family"],l["pos"]])
	return str(parts).md5_text()

func run_tests() -> void:
	# --- Prepared routes -------------------------------------------------------------
	var all_clean := true
	var all_distinct := true
	var trails := true
	var extras := true
	for location in range(3):
		var routes := LevelCatalog.routes(location)
		check(routes.size()==3,"expedition %d has three prepared routes" % location)
		var seen := {}
		for index in range(routes.size()):
			var world := make_route(location,index)
			var layout: ExpeditionLayout = world.layout
			var audit := RouteGraph.audit(layout)
			if not audit["problems"].is_empty():
				all_clean = false
				print("AUTHORED_AUDIT ",location," ",index," ",audit["problems"].slice(0,3))
			for plan in layout.scenarios.values():
				if str(plan.get("template","")) in ["teach","fork","combo","intro_link"] and not bool(plan.get("placed",false)): all_clean = false
			var first := signature(world)
			world.free()
			var again := make_route(location,index)
			check(signature(again)==first,"route %d/%d is the same on every attempt" % [location,index])
			trails = trails and int(again.layout.loot_plan.placed.get("trail",0))>=8
			extras = extras and int(again.layout.loot_plan.placed.get("route_cache",0))>=1 and int(again.layout.loot_plan.placed.get("route_treasure",0))>=1
			var route_landmarks := 0
			for landmark in again.layout.landmarks: route_landmarks += 1 if str(landmark.get("role",""))=="route" else 0
			extras = extras and route_landmarks==routes[index]["decor"].size()
			all_distinct = all_distinct and not seen.has(first)
			seen[first] = true
			again.free()
	check(all_clean,"every prepared route passes the route audit and places every beat")
	check(all_distinct,"the three routes of an expedition differ")
	check(trails,"prepared routes keep their coin trails")
	check(extras,"prepared routes keep their caches, treasures and landmarks")
	# --- Per-route records -----------------------------------------------------------
	var model := GameModel.new("user://authored_test_profile.json")
	model.profile = GameModel.fresh_profile()
	check(model.note_record(1,"summit",420.0),"a first height is a record")
	check(not model.note_record(1,"summit",300.0),"a lower height is not")
	check(model.record(1,"summit")==420.0 and model.record(0,"summit")==0.0 and model.record(1,"endless")==0.0,"records are per route and mode")
	model.profile["best"] = 900.0
	model.profile["records"] = {}
	model.profile["run_history"] = [{"mode":"summit","location":2,"height":640},{"mode":"endless","location":0,"height":300}]
	model._sanitize_records(false)
	check(model.record(2,"summit")==640.0 and model.record(0,"endless")==300.0,"an old save rebuilds route records from its run history")
	model.set_route_choice(2,7)
	check(model.route_choice(2)==2,"a route choice is clamped to the routes there are")
	check(model.profile.has("music") and bool(model.profile["music"]),"music is on by default")
	# --- Treasure sets ---------------------------------------------------------------
	var leaks := false
	var named := true
	for location in range(3):
		var location_id := str(LevelCatalog.level(location)["id"])
		var other_sheets: Array = []
		for other in ["treasure_a","treasure_b","treasure_desert","treasure_winter"]:
			if not preload("res://scripts/treasure_models.gd").THEMES[location_id].has(other): other_sheets.append(other)
		for tier in range(6):
			for rarity in ["common","artifact"]:
				var item := ItemCatalog.valuable(tier*7+(1 if rarity=="artifact" else 0),location,"act",tier,rarity)
				item["item_id"] = "act/test/%d/%s" % [tier,rarity]
				ItemCatalog.dress(item)
				var sprite := str(item.get("sprite",""))
				named = named and not str(item["name"]).is_empty() and ResourceLoader.exists("res://assets/sprites/"+sprite+".png")
				for sheet in other_sheets:
					if sprite.get_file().begins_with(sheet+"_") and not (location==1 and sprite.ends_with("treasure_b_4")): leaks = true
		for material_id in ["fiber","silk","sinew","core"]:
			var material := ItemCatalog.dress(ItemCatalog.material(1,location,"act",1,material_id))
			named = named and ResourceLoader.exists("res://assets/sprites/"+str(material["sprite"])+".png")
	check(not leaks,"a find never shows a picture from another expedition's set")
	check(named,"every dressed find has a name and an existing picture")
	print("AUTHORED_TESTS %d checks, %d failures" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
