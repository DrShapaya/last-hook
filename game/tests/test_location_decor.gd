extends SceneTree

# Each location shows only its own decor: no cactus, skull or dry tree of the
# canyon on the standard mountain, no green bush on the snow peak. Scans every
# baked section of every route and preset, and a live run of each location
# started right after a run of another one (caches shared between worlds).
# LASTHOOK_SAVE_DIR must point to a throwaway save folder.

const FloraModels := preload("res://scripts/flora_models.gd")

# Sprite kinds only one climate may use. Grass tufts and blades are shared
# (the canyon uses their parched variants), so they are not listed.
const OWN := {
	"green":["bush","crystal_blue","scree_grey","stone_grey","tree_green","vine_green"],
	"dry":["cactus","crystal_amber","dry_plant","scree_desert","skull","stone_desert","tree_dead","vine_dry"],
	"cold":["crystal_ice","icicle","scree_snow","snow_plant","stone_snow","tree_snow","vine_frost"],
}
const CLIMATE := {0:"green",1:"dry",2:"cold"}
# Single pictures a climate must not show though their kind is its own: the
# bare thorny roots and the pod vine of the summer set are drawn as the
# canyon's dry vines.
const LOOKS_FOREIGN := {"green":["vine_root_1","vine_root_2","vine_root_3","vine_root_4","vine_root_5","vine_green_5"]}

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("LOCATION DECOR FAILED: "+description)

# Kind of every painted sprite under a node, by its texture file.
static func sprite_kinds(node: Node, found: Dictionary) -> void:
	if node is GeometryInstance3D:
		var material := (node as GeometryInstance3D).material_override
		if material is ShaderMaterial:
			var texture = (material as ShaderMaterial).get_shader_parameter("albedo_tex")
			if texture is Texture2D:
				var file := (texture as Texture2D).resource_path.get_file().get_basename()
				var kind := file.substr(0,file.rfind("_"))
				found[kind] = int(found.get(kind,0))+1
				found["file:"+file] = int(found.get("file:"+file,0))+1
	for child in node.get_children(): sprite_kinds(child,found)

static func _sprite_quads(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is QuadMesh:
		var material := (node as MeshInstance3D).material_override
		if material is ShaderMaterial and (material as ShaderMaterial).get_shader_parameter("albedo_tex") is Texture2D: out.append(node)
	for child in node.get_children(): _sprite_quads(child,out)

static func foreign(location: int, found: Dictionary) -> Array:
	var result: Array = []
	for climate in OWN.keys():
		if climate==CLIMATE[location]: continue
		for kind in OWN[climate]:
			if found.has(kind): result.append("%s x%d" % [kind,found[kind]])
	for file in LOOKS_FOREIGN.get(CLIMATE[location],[]):
		if found.has("file:"+file): result.append("%s x%d" % [file,found["file:"+file]])
	return result

func run_tests() -> void:
	baked_sections()
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		check(false,"LASTHOOK_SAVE_DIR is set")
	else:
		await live_runs()
	print("LOCATION_DECOR_TESTS %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func baked_sections() -> void:
	for location in range(3):
		for route in range(LevelCatalog.routes(location).size()):
			for quality in LevelBake.QUALITIES:
				var found := {}
				var sections := 0
				var key := 0
				while true:
					var path := LevelBake.chunk_path(location,route,quality,key)
					if not ResourceLoader.exists(path): break
					var scene := (load(path) as PackedScene).instantiate()
					sprite_kinds(scene,found)
					scene.free()
					sections += 1
					key += 1
				if sections==0: continue
				var own := 0
				for kind in OWN[CLIMATE[location]]: own += int(found.get(kind,0))
				check(own>0,"location %d route %d %s: its own decor is baked (%d sections)" % [location,route,quality,sections])
				var bad := foreign(location,found)
				check(bad.is_empty(),"location %d route %d %s: no other location's decor %s" % [location,route,quality,bad])

func live_runs() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["locations"] = [0,1,2]
	game.model.profile["summit_cleared"] = true
	# Each location after another one, as a player switches between runs.
	for step in [[1,false],[0,false],[2,false],[0,false],[1,true],[0,true]]:
		var location: int = step[0]
		game.model.set_route_choice(location,0)
		game.selected_location = location
		game.lobby_location = location
		game.start_run(step[1])
		for spot in [.15,.5,.85]:
			var route: Array = game.world.main_route
			if route.is_empty(): break
			var id: int = route[clampi(int(route.size()*spot),0,route.size()-1)]
			var at: Vector2 = game.world.anchor_by_id(id)["pos"]
			game.sim.pos = at+Vector2(0,-2.6)
			game.sim.vel = Vector2.ZERO
			game.sim.attach(at,4.0)
			for frame in range(40): await process_frame
		var found := {}
		sprite_kinds(game.world,found)
		# No loose stone or sand heap of the face lies across a piece (a
		# canyon cactus was cut in two by a heap in front of it).
		var crossed: Array = []
		var quads: Array = []
		_sprite_quads(game.world,quads)
		for quad: MeshInstance3D in quads:
			# Finds stand well in front of the stone; only scenery counts.
			if not (String(quad.name).begins_with("Растение_") or String(quad.name).begins_with("Декор_")): continue
			var size: Vector2 = (quad.mesh as QuadMesh).size
			var at := quad.global_position
			if game.world.visuals.has_method("_behind_lump") and game.world.visuals._behind_lump(Rect2(at.x-size.x*.5,at.y-size.y*.5,size.x,size.y).grow(-.12),at.z):
				crossed.append("%s at (%.1f, %.1f)" % [quad.name,at.x,at.y])
		check(crossed.is_empty(),"live run of location %d: no stone or sand heap lies across decor %s" % [location,crossed])
		var bad := foreign(location,found)
		check(bad.is_empty(),"live %s run of location %d after another location: no other location's decor %s" % ["endless" if step[1] else "summit",location,bad])
		game.show_menu()
		for frame in range(10): await process_frame
	game.queue_free()
	# The summer picks: never a dry root or pod vine, however often asked.
	var random := RandomNumberGenerator.new()
	var green := GripBiomeProfile.named("forest")
	var dry_picks := 0
	for attempt in range(400):
		for item in [FloraModels.pick_climber(green,random),FloraModels.pick_hanging(green,random)]:
			if not item.is_empty() and "%s_%d" % [item[0],item[1]] in LOOKS_FOREIGN["green"]: dry_picks += 1
	check(dry_picks==0,"summer climbers and hangers are green (%d dry picks)" % dry_picks)
	await process_frame
