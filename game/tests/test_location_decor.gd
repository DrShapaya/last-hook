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
	painted_tops()
	baked_sections()
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		check(false,"LASTHOOK_SAVE_DIR is set")
	else:
		await live_runs()
		await whole_canyon()
	print("LOCATION_DECOR_TESTS %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

# The painted desert plants themselves: a cactus whose trunk ran off the top
# of its picture ended in a flat cut (owner, 0.18.4), and a loose strip of
# roots under it kept the plant off the ground. Every standing plant picture
# is one piece reaching its bottom, and no trunk starts as a flat row.
func painted_tops() -> void:
	for kind in ["cactus","dry_plant","stone_desert","skull"]:
		for variant: int in FloraModels.variants(kind):
			var image := (load(FloraModels.sprite_path(kind,variant)) as Texture2D).get_image()
			if image.is_compressed(): image.decompress()
			var w := image.get_width()
			var h := image.get_height()
			var filled: Array[bool] = []
			for y in range(h):
				var any := false
				for x in range(0,w,2):
					if image.get_pixel(x,y).a>.16:
						any = true
						break
				filled.append(any)
			var first := filled.find(true)
			var last := filled.rfind(true)
			var gap := false
			var empty := 0
			for y in range(first,last+1):
				empty = 0 if filled[y] else empty+1
				if empty>3: gap = true
			check(not gap,"%s_%d: one piece, no loose strip under it" % [kind,variant])
			check(last>=h-12,"%s_%d: stands on the bottom of its picture (last row %d of %d)" % [kind,variant,last,h])
			if kind!="cactus": continue
			# A flat cut: a wide run exposed at once that is solid a few rows below.
			var flat := 0
			for y in range(maxi(first,1),last-8):
				var run := 0
				for x in range(w):
					var exposed := image.get_pixel(x,y).a>.5 and image.get_pixel(x,y-1).a<=.5 and image.get_pixel(x,y+6).a>.5
					run = run+1 if exposed else 0
					flat = maxi(flat,run)
			check(flat<w*.1,"cactus_%d: rounded tops, no flat cut (widest flat edge %d px)" % [variant,flat])

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

# Every desert route on every bake, top to bottom: no plant or stone stands
# behind a grip block or a sand heap, and a hazard cactus stands in front of
# the grips round it (cacti were cut in two on the phone presets, 0.18.4).
func whole_canyon() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["locations"] = [0,1,2]
	for quality in ["high","balanced","battery"]:
		game._apply_graphics_quality(quality,false)
		for route in range(LevelCatalog.routes(1).size()):
			game.model.set_route_choice(1,route)
			game.selected_location = 1
			game.start_run(false)
			game.set_process(false)
			var world = game.world
			var behind: Array = []
			var hazards_cut: Array = []
			var seen := {}
			var y := 0.0
			while y<world.layout.summit+8.0:
				world.update_visibility(y,0,-1)
				await process_frame
				y += 8.0
				var quads: Array = []
				_sprite_quads(world,quads)
				for quad: MeshInstance3D in quads:
					var at := quad.global_position
					var key := Vector3i(roundi(at.x*20),roundi(at.y*20),roundi(at.z*20))
					if seen.has(key): continue
					seen[key] = true
					var size: Vector2 = (quad.mesh as QuadMesh).size
					var rect := Rect2(at.x-size.x*.5,at.y-size.y*.5,size.x,size.y).grow(-.12)
					var name := String(quad.name)
					if name.begins_with("Растение_") or name.begins_with("Декор_"):
						if world.visuals._under_grip(rect) or world.visuals._behind_lump(rect,at.z): behind.append("%s (%.1f, %.1f) %s" % [name,at.x,at.y,"grip" if world.visuals._under_grip(rect) else "heap"])
				for hazard in world.find_children("Крупный кактус","Node3D",true,false):
					var h: Vector3 = (hazard as Node3D).global_position
					for anchor in world.nearby_anchors(h.y-1.5,h.y+4.0):
						var visual = anchor.get("visual")
						if visual==null or not is_instance_valid(visual) or not (visual as Node3D).is_visible_in_tree(): continue
						var p: Vector2 = anchor["pos"]
						var dims: Vector2 = anchor.get("dimensions",Vector2(1.6,.65))
						if absf(p.x-h.x)<dims.x*.65+.8 and p.y>h.y-.5 and p.y<h.y+3.5 and (visual as Node3D).global_position.z+1.2>h.z: hazards_cut.append("(%.1f, %.1f)" % [h.x,h.y])
			check(behind.is_empty(),"canyon route %d %s: no plant or stone behind a grip or heap %s" % [route,quality,behind])
			check(hazards_cut.is_empty(),"canyon route %d %s: hazard cacti stand in front of the grips %s" % [route,quality,hazards_cut])
	game.queue_free()
	await process_frame
