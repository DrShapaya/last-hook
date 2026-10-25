extends SceneTree

# Prints what a prepared route holds and which finds its placement checks
# dropped. Run: godot --headless --path game --script res://tools/route_report.gd
func _initialize() -> void:
	for location in range(3):
		for index in range(LevelCatalog.routes(location).size()):
			var spec := LevelCatalog.route(location,index)
			var world := MountainWorld.new()
			world.visuals_enabled = false
			root.add_child(world)
			world.setup(int(spec["seed"]),location,0,false,index)
			var total := float(LevelCatalog.level(location)["height_units"])
			world.generate_to(total+6,true,total)
			var layout: ExpeditionLayout = world.layout
			var problems: Array = RouteGraph.audit(layout)["problems"]
			print("ROUTE %d/%d %s seed=%d grips=%d branches=%d hazards=%d landmarks=%d problems=%d placed=%s dropped=%s" % [location,index,spec["name"],int(spec["seed"]),world.main_route.size(),layout.branches.size(),layout.hazards.size(),layout.landmarks.size(),problems.size(),layout.loot_plan.placed,layout.loot_plan.dropped])
			world.free()
	quit()
