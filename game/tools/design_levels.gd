extends SceneTree

# Designs the finite levels with LevelDesigner, keeps the best and bakes it:
#   Godot --headless --path game --script res://tools/design_levels.gd
#   ... -- --only=0:1     one level (location:route)
#   ... -- --tries=8      design seeds tried per level
#   ... -- --variant=3    another family of design seeds (the editor's
#                         «Новый вариант» counts this up)
#   ... -- --no-bot       skip the movement bot
#
# Every candidate is generated from its masks and judged by LevelScore. Only
# usable ones count (clean route audit, every object on stone, every planned
# split built); they are ranked by score. The best is saved, baked and
# climbed by the bot twice — up the main route and through every split — and
# the next best takes its place when the bot falls.

var only := ""
var tries := 8
var variant := 0
var use_bot := true
var baker: LevelBaker
var game

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
		if argument.begins_with("--tries="): tries = int(argument.trim_prefix("--tries="))
		if argument.begins_with("--variant="): variant = int(argument.trim_prefix("--variant="))
		if argument=="--no-bot": use_bot = false
	call_deferred("run")

func run() -> void:
	baker = LevelBaker.new(root)
	if use_bot:
		game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(game)
		await process_frame
		game.set_physics_process(false)
		game.set_process(false)
	var designed := 0
	for location in range(LevelCatalog.LEVELS.size()):
		for route in range(LevelCatalog.routes(location).size()):
			if not only.is_empty() and only!="%d:%d" % [location,route]: continue
			if design_level(location,route): designed += 1
	print("DESIGN_DONE levels=%d" % designed)
	quit(0)

func design_level(location: int, route: int) -> bool:
	var base_seed := int(LevelCatalog.route(location,route)["seed"])
	var candidates: Array = []
	for attempt in range(tries):
		var started := Time.get_ticks_msec()
		var designer := LevelDesigner.new(location,route,base_seed*31+variant*1000+attempt)
		var source := designer.build()
		var world := MountainWorld.new()
		world.visuals_enabled = false
		root.add_child(world)
		world.setup(int(source.brief["seeds"]["route"]),location,0,false,route,true)
		var layout := world.layout as MaskLayout
		layout.use_source(source)
		world.generate_to(designer.height+6,true,designer.height)
		var verdict := LevelScore.evaluate(layout,source,designer.sections)
		var metrics: Dictionary = verdict["metrics"]
		print("DESIGN %d:%d try %d: %s score %.3f | level hops %d%%, mean hop %.2f, grips/10 %.1f, splits %d/%d, sky %d%% | %d ms" % [location,route,attempt,
			"usable" if verdict["usable"] else "rejected",float(verdict["score"]),roundi(float(metrics["level_hops"])*100),float(metrics["mean_hop"]),
			float(metrics["grips_per_10"]),int(metrics["splits"]),int(metrics["splits_planned"]),roundi(float(metrics["sky"])*100),Time.get_ticks_msec()-started])
		for problem in (verdict["problems"] as Array).slice(0,2): print("    ",problem)
		for note in layout.mask_notes.slice(0,3): print("    ",note)
		world.free()
		if verdict["usable"]:
			source.brief["design_variant"] = variant
			source.brief["score"] = {"score":verdict["score"],"terms":verdict["terms"],"metrics":metrics}
			candidates.append(source)
	candidates.sort_custom(func(a: LevelSource, b: LevelSource) -> bool: return float(a.brief["score"]["score"])>float(b.brief["score"]["score"]))
	for source: LevelSource in candidates:
		var error := source.save(LevelSource.source_directory(location,route))
		if error!=OK:
			push_error("DESIGN save failed: %d" % error)
			return false
		baker.bake_level(location,route,float(source.brief["height"]))
		if not use_bot: return true
		var main_ok := climb(location,route,false)
		var split_ok := climb(location,route,true)
		print("BOT %d:%d score %.3f: main %s, through splits %s" % [location,route,float(source.brief["score"]["score"]),main_ok,split_ok])
		if main_ok and split_ok: return true
	push_error("DESIGN %d:%d: no design the bot could climb (%d usable)" % [location,route,candidates.size()])
	return false

func climb(location: int, route: int, through_splits: bool) -> bool:
	# The bake just written replaces the cached one.
	ResourceLoader.load(LevelBake.layout_path(location,route),"",ResourceLoader.CACHE_MODE_REPLACE)
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["locations"] = [0,1,2]
	game.model.set_route_choice(location,route)
	game.selected_location = location
	game.start_run(false)
	var path: Array = RouteBot.route_through_splits(game.world) if through_splits else []
	var log: Array = []
	var success := RouteBot.climb_to_summit(game,log,path)
	if not success:
		for line in log: print("    bot: ",line)
	return success
