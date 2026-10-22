extends SceneTree

# Placement statistics of generator v15 (chat 4): finds per role and family,
# direct-coin budget, contracts and dropped requests, for N seeds per
# expedition. Run:
#   godot --headless --path game --script res://tools/loot_fixture.gd -- --seeds=30
# Output: JSON on stdout (LOOT_FIXTURE {...}) and user://loot-fixture.json.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var seeds := 30
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="): seeds = int(argument.trim_prefix("--seeds="))
	var report := {}
	for location in range(3):
		var total := float(LevelCatalog.level(location)["height_units"])
		var roles := {}
		var families := {}
		var dropped := {}
		var coin_gold := 0
		var bag_gold := 0
		var contracts := 0
		var sets := 0
		for seed_number in range(1000,1000+seeds):
			var world := MountainWorld.new()
			world.visuals_enabled = false
			root.add_child(world)
			world.setup(seed_number,location)
			world.generate_to(total+6,true,total)
			var layout := world.layout as ExpeditionLayout
			for find in world.finds:
				var item: Dictionary = find["item"]
				roles[find.get("role","?")] = int(roles.get(find.get("role","?"),0))+1
				families[item["family"]] = int(families.get(item["family"],0))+1
				if item["family"]=="coin": coin_gold += int(item["value"])
				elif GameModel.pays_gold(item): bag_gold += int(item["value"])
				if item["family"]=="relic" and item["use_tag"]=="set": sets += 1
			for role in layout.loot_plan.dropped.keys(): dropped[role] = int(dropped.get(role,0))+int(layout.loot_plan.dropped[role])
			contracts += 1 if not layout.contract.is_empty() else 0
			world.free()
		var per := func(value) -> float: return snappedf(float(value)/seeds,.01)
		var role_avg := {}
		for role in roles.keys(): role_avg[role] = per.call(roles[role])
		var family_avg := {}
		for family in families.keys(): family_avg[family] = per.call(families[family])
		var dropped_avg := {}
		for role in dropped.keys(): dropped_avg[role] = per.call(dropped[role])
		report[str(location)] = {"roles":role_avg,"families":family_avg,"dropped":dropped_avg,"coin_gold":per.call(coin_gold),"bag_gold_all":per.call(bag_gold),
			"set_parts":per.call(sets),"contract_share":per.call(contracts)}
	print("LOOT_FIXTURE ",JSON.stringify(report))
	var file := FileAccess.open("user://loot-fixture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	quit(0)
