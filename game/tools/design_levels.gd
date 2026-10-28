extends SceneTree

# Designs the finite levels with LevelDesigner and writes their sources:
#   Godot --headless --path game --script res://tools/design_levels.gd
#   ... -- --only=0:1     one level (location:route)
#   ... -- --tries=8      design seeds tried per level
#   ... -- --variant=3    another family of design seeds (the editor's
#                         «Новый вариант» counts this up)
# Each candidate is generated from its masks and kept only when the route
# audit finds nothing and every object stands on painted stone; the first
# such design is saved. Bake afterwards with
# tools/bake_levels.gd.

var only := ""
var tries := 8
var variant := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
		if argument.begins_with("--tries="): tries = int(argument.trim_prefix("--tries="))
		if argument.begins_with("--variant="): variant = int(argument.trim_prefix("--variant="))
	call_deferred("run")

func run() -> void:
	var designed := 0
	for location in range(LevelCatalog.LEVELS.size()):
		for route in range(LevelCatalog.routes(location).size()):
			if not only.is_empty() and only!="%d:%d" % [location,route]: continue
			if design_level(location,route): designed += 1
	print("DESIGN_DONE levels=%d" % designed)
	quit(0)

func design_level(location: int, route: int) -> bool:
	var base_seed := int(LevelCatalog.route(location,route)["seed"])
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
		var problems: Array = RouteGraph.audit(layout)["problems"]
		var forms: Array = []
		for section in designer.sections: forms.append(section["form"])
		print("DESIGN %d:%d try %d: %d problems, %d notes, %d ms, %s" % [location,route,attempt,problems.size(),layout.mask_notes.size(),Time.get_ticks_msec()-started," ".join(forms)])
		for problem in problems.slice(0,3): print("    ",problem)
		world.free()
		for note in layout.mask_notes.slice(0,3): print("    ",note)
		# Clean route and every object on stone.
		if problems.is_empty() and layout.sky_objects==0:
			source.brief["design_variant"] = variant
			var error := source.save(LevelSource.source_directory(location,route))
			if error!=OK: push_error("DESIGN save failed: %d" % error)
			return error==OK
	push_error("DESIGN %d:%d: no clean design in %d tries" % [location,route,tries])
	return false
