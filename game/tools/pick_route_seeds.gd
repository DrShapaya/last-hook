extends SceneTree

# Picks the fixed seed of every prepared route (LevelCatalog.ROUTES): tries
# candidate seeds and keeps the best one whose route passes RouteGraph.audit,
# places every act beat and keeps every hand-placed coin, cache and treasure.
# Run: godot --headless --path game --script res://tools/pick_route_seeds.gd

func score(location: int, index: int, seed_number: int) -> Dictionary:
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(seed_number,location,0,false,index)
	var total := float(LevelCatalog.level(location)["height_units"])
	world.generate_to(total+6,true,total)
	var layout: ExpeditionLayout = world.layout
	var audit := RouteGraph.audit(layout)
	var unplaced := 0
	for plan in layout.scenarios.values():
		if not bool(plan.get("placed",false)) and str(plan.get("template","")) in ["teach","fork","combo","intro_link"]: unplaced += 1
	var dropped := 0
	for role in ["trail","route_cache","route_treasure","landmark","detour","contract_target"]: dropped += int(layout.loot_plan.dropped.get(role,0))
	var branches := layout.branches.size()
	var result := {"seed":seed_number,"problems":audit["problems"].size(),"unplaced":unplaced,"dropped":dropped,"branches":branches,"hazards":layout.hazards.size(),"finds":world.finds.size()}
	world.free()
	return result

func _initialize() -> void:
	var picks := []
	for location in range(3):
		var row := []
		for index in range(LevelCatalog.routes(location).size()):
			var best := {}
			for attempt in range(60):
				var seed_number := 1000+location*100000+index*10000+attempt*37
				var s := score(location,index,seed_number)
				if s["problems"]>0: continue
				var value: float = -s["unplaced"]*100-s["dropped"]*10+s["branches"]+s["hazards"]*.5
				if best.is_empty() or value>best["value"]:
					s["value"] = value
					best = s
			print("ROUTE ",location," ",index," ",best)
			row.append(best.get("seed",-1))
		picks.append(row)
	print("ROUTE_SEEDS ",picks)
	quit()
