extends SceneTree

# Checks how the decor of a level sits on its rock, on the same world the bake
# builds:  Godot --headless --path game --script res://tools/decor_audit.gd -- [location:route ...] [--quality=balanced] [--list]
# A piece is a sprite, a pole or a string of a decor holder. For each:
#   floating  its foot has no stone under it
#   edge      less than half of its painted foot rests on stone
#   buried    stone in front of it hides a good part of it
#   crowded   too many pieces stand close round it
# Exits 1 when any piece of a checked level breaks a rule.

const CROWD_REACH := 2.6
const CROWD_LIMIT := 3
const BURIED_LIMIT := .18
const FOOT_LIMIT := .5

var quality := "balanced"
var listing := false
var painted := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var levels: Array = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--quality="): quality = argument.trim_prefix("--quality=")
		elif argument=="--list": listing = true
		else: levels.append(argument)
	if levels.is_empty(): levels = ["0:0","0:1","0:2"]
	var broken := 0
	for spec: String in levels:
		broken += await audit_level(int(spec.get_slice(":",0)),int(spec.get_slice(":",1)))
	print("DECOR_AUDIT broken=%d" % broken)
	quit(1 if broken>0 else 0)

func audit_level(location: int, route: int) -> int:
	var level := ResourceLoader.load(LevelBake.layout_path(location,route),"",ResourceLoader.CACHE_MODE_IGNORE) as LevelBake
	var world := MountainWorld.new()
	world.visuals_enabled = false
	root.add_child(world)
	world.setup(level.seed_value,location,MountainWorld.generation_version_for(location),false,route,level.generator=="masks")
	world.set_visual_quality(quality)
	world.load_bake(level)
	var visuals: MassifVisuals = world.visuals
	var pieces: Array = []
	var holders := {}
	for key in range(world._ready_chunk()+1):
		var scenery := Node3D.new()
		world.add_child(scenery)
		await visuals.build_chunk(key,scenery)
		for holder in scenery.get_children():
			var found := _pieces(holder)
			pieces.append_array(found)
			if not found.is_empty(): holders[found[0]["group"]] = int(holders.get(found[0]["group"],0))+1
		scenery.free()
	var marks := 0
	for mark in world.layout.landmarks: marks += 1 if mark.has("built_at") else 0
	var counts := {"floating":0,"edge":0,"buried":0,"crowded":0}
	for piece: Dictionary in pieces:
		var problems := _judge(visuals,piece,pieces)
		for problem in problems: counts[problem] = int(counts[problem])+1
		if listing and not problems.is_empty():
			print("  %s %s at (%.1f,%.1f) z=%.2f: %s" % [piece["group"],piece["name"],piece["foot"].x,piece["foot"].y,piece["z"],",".join(problems)])
	print("AUDIT %d:%d %s pieces=%d %s holders %s act marks %d of %d" % [location,route,quality,pieces.size(),str(counts),str(holders),marks,world.layout.landmarks.size()])
	world.free()
	return int(counts["floating"])+int(counts["edge"])+int(counts["buried"])+int(counts["crowded"])

# The pieces of a holder: every sprite and every pole under it.
func _pieces(holder: Node) -> Array:
	var group := ""
	for prefix in ["Декор_","Крупный элемент","Ориентир акта","Растение_","Подвес_","Кристалл_"]:
		if str(holder.name).begins_with(prefix): group = prefix
	if group.is_empty() or not holder is Node3D: return []
	var result: Array = []
	for mesh: MeshInstance3D in holder.find_children("*","MeshInstance3D",true,false):
		var name := str(mesh.name)
		if not mesh.mesh is QuadMesh or not (name.begins_with("Растение_") or name.begins_with("Декор_")): continue
		var size: Vector2 = (mesh.mesh as QuadMesh).size
		var at := mesh.global_position
		var hanging := float((mesh.material_override as ShaderMaterial).get_shader_parameter("hanging"))>.5
		var parts := name.rsplit("_",true,1)
		var kind := parts[0].trim_prefix("Растение_").trim_prefix("Декор_")
		var extent := _extent(kind,int(parts[1]))
		var box := Rect2(at.x-size.x*.5+extent["left"]*size.x,at.y+size.y*.5-extent["bottom"]*size.y,(extent["right"]-extent["left"])*size.x,(extent["bottom"]-extent["top"])*size.y)
		var foot := Vector2(box.get_center().x,box.position.y)
		var span := Vector2(at.x-size.x*.5+extent["foot_left"]*size.x,at.x-size.x*.5+extent["foot_right"]*size.x)
		if hanging: foot = Vector2(box.get_center().x,box.end.y)
		result.append({"group":group,"name":name,"foot":foot,"span":span,"box":box,"z":at.z,"hanging":hanging,"climbing":FloraModels_climbs(kind,int(parts[1]))})
	for shaft: Node3D in holder.find_children("Древко","Node3D",true,false):
		var pole: Node3D = shaft.get_parent()
		var at := pole.global_position
		var foot := Vector2(at.x,at.y+pole.scale.y*.1)
		var tall := pole.scale.y*3.4
		result.append({"group":group,"name":"Флаг","foot":foot,"span":Vector2(foot.x-.08,foot.x+.08),"box":Rect2(foot.x-.08,foot.y,.16,tall),"z":at.z,"hanging":false,"climbing":false})
	return result

func FloraModels_climbs(kind: String, variant: int) -> bool:
	return preload("res://scripts/flora_models.gd").mode_of(kind,variant)=="climb"

# Where a sprite's paint is, in shares of its picture, and how wide the paint
# stands on its lowest rows.
func _extent(kind: String, variant: int) -> Dictionary:
	var key := "%s_%d" % [kind,variant]
	if painted.has(key): return painted[key]
	var image := Image.load_from_file(ProjectSettings.globalize_path(preload("res://scripts/flora_models.gd").sprite_path(kind,variant)))
	var width := image.get_width()
	var height := image.get_height()
	var low := Vector2i(width,height)
	var high := Vector2i(-1,-1)
	for y in range(height):
		for x in range(width):
			if image.get_pixel(x,y).a<.5: continue
			low = Vector2i(mini(low.x,x),mini(low.y,y))
			high = Vector2i(maxi(high.x,x),maxi(high.y,y))
	var foot_low := width
	var foot_high := -1
	for y in range(maxi(low.y,high.y-int((high.y-low.y)*.06)),high.y+1):
		for x in range(width):
			if image.get_pixel(x,y).a<.5: continue
			foot_low = mini(foot_low,x)
			foot_high = maxi(foot_high,x)
	painted[key] = {"left":low.x/float(width),"right":(high.x+1)/float(width),"top":low.y/float(height),"bottom":(high.y+1)/float(height),
		"foot_left":foot_low/float(width),"foot_right":(foot_high+1)/float(width)}
	return painted[key]

func _judge(visuals: MassifVisuals, piece: Dictionary, pieces: Array) -> Array:
	var problems: Array = []
	var foot: Vector2 = piece["foot"]
	var box: Rect2 = piece["box"]
	if piece["hanging"]:
		var root := foot+Vector2(0,.12)
		if visuals.open_at(root): problems.append("floating")
	else:
		var span: Vector2 = piece["span"]
		var held := 0
		var samples := 7
		for sample in range(samples):
			if not visuals.open_at(Vector2(lerpf(span.x,span.y,sample/float(samples-1)),foot.y-.1)): held += 1
		if held==0: problems.append("floating")
		elif held<samples*FOOT_LIMIT: problems.append("edge")
	var hidden := 0
	var looked := 0
	for row in range(7):
		for column in range(5):
			var probe := box.position+box.size*Vector2((column+.5)/5.0,(row+.5)/7.0)
			looked += 1
			if not visuals.open_at(probe) and visuals.wall_depth(probe)>float(piece["z"])+.02: hidden += 1
	if hidden/float(looked)>BURIED_LIMIT: problems.append("buried")
	var near := 0
	for other: Dictionary in pieces:
		if not other["box"].get_center().is_equal_approx(box.get_center()) and other["box"].get_center().distance_to(box.get_center())<CROWD_REACH: near += 1
	if near>CROWD_LIMIT: problems.append("crowded")
	return problems
