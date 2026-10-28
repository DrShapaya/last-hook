extends SceneTree

# Makes the finite levels in advance (see LevelBake): every location and route
# gets its layout as data and the static scenery of each section, for every
# graphics preset, as scenes under res://levels.
#
#   Godot --headless --path game --script res://tools/bake_levels.gd
#   ... -- --regenerate        rewrite layouts from the generator, even edited ones
#   ... -- --only=0:1          one level (location:route)
#
# A layout already baked is kept as it is (it may have been tuned by hand);
# the scenery is always rebuilt from it. Shaders and materials go to shared
# files named by their content, so all sections use one copy of each.

var regenerate := false
var only := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--regenerate": regenerate = true
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
	call_deferred("run")

func run() -> void:
	var model := GameModel.new()
	var baker := LevelBaker.new(root,regenerate)
	var total := 0
	for location in range(model.balance["locations"].size()):
		for route in range(LevelCatalog.routes(location).size()):
			if not only.is_empty() and only!="%d:%d" % [location,route]: continue
			total += baker.bake_level(location,route,float(model.balance["locations"][location]["height_units"]))
	print("BAKE_DONE levels=%d" % total)
	quit(0)
