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

const SHARED := "res://levels/_shared"

var regenerate := false
var only := ""
var saved_resources := {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--regenerate": regenerate = true
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
	call_deferred("run")

func run() -> void:
	var model := GameModel.new()
	var total := 0
	for location in range(model.balance["locations"].size()):
		for route in range(LevelCatalog.routes(location).size()):
			if not only.is_empty() and only!="%d:%d" % [location,route]: continue
			total += bake_level(location,route,float(model.balance["locations"][location]["height_units"]))
	print("BAKE_DONE levels=%d" % total)
	quit(0)

func bake_level(location: int, route: int, height: float) -> int:
	var started := Time.get_ticks_msec()
	var version := MountainWorld.generation_version_for(location)
	var seed_value := int(LevelCatalog.route(location,route)["seed"])
	var path := LevelBake.layout_path(location,route)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LevelBake.directory(location,route)))
	var level: LevelBake = null
	# A source marked "generator": "masks" is the level's design: its layout
	# is rebuilt from the masks on every bake.
	var source_level := LevelSource.open(LevelSource.source_directory(location,route))
	var from_masks := source_level!=null and str(source_level.brief.get("generator","layout"))=="masks"
	if from_masks: seed_value = int(source_level.brief.get("seeds",{}).get("route",seed_value))
	if ResourceLoader.exists(path) and not regenerate and not from_masks:
		level = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as LevelBake
		if level!=null and (level.format!=LevelBake.FORMAT or level.generation_version!=version or level.generator!="layout" or (level.seed_value!=seed_value and not level.edited)): level = null
	if level==null:
		level = LevelBake.new()
		level.location = location
		level.route = route
		level.generation_version = version
		level.seed_value = seed_value
		level.height = height
		level.generator = "masks" if from_masks else "layout"
		var source := MountainWorld.new()
		source.visuals_enabled = false
		root.add_child(source)
		source.setup(seed_value,location,version,false,route,from_masks)
		if from_masks: (source.layout as MaskLayout).use_source(source_level)
		source.generate_to(height+6,true,height)
		level.layout_data = LevelBake.capture(source.layout)
		if from_masks:
			# What the masks could not get and what the route audit found go to
			# the log and to a report the level editor shows.
			var report: Array = []
			for note in (source.layout as MaskLayout).mask_notes: report.append(note)
			for problem in RouteGraph.audit(source.layout).get("problems",[]): report.append("Маршрут: %s" % problem)
			var level_id := LevelBake.directory(location,route).get_file()
			for line in report: print("BAKE_NOTE %s: %s" % [level_id,line])
			var file := FileAccess.open("user://bake_report_%s.txt" % level_id,FileAccess.WRITE)
			if file!=null:
				file.store_string("\n".join(report) if not report.is_empty() else "Замечаний нет")
				file.close()
		source.free()
	var chunk_count := 0
	for quality in LevelBake.QUALITIES:
		var world := MountainWorld.new()
		world.visuals_enabled = false
		root.add_child(world)
		world.setup(level.seed_value,location,version,false,route,level.generator=="masks")
		world.set_visual_quality(quality)
		world.load_bake(level)
		var folder := LevelBake.directory(location,route).path_join(quality)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		chunk_count = world._ready_chunk()+1
		for key in range(chunk_count):
			var scenery := Node3D.new()
			scenery.name = "Декорации участка_%d" % key
			world.add_child(scenery)
			world.visuals.build_chunk(key,scenery)
			_own(scenery,scenery)
			_externalize(scenery)
			_number_subresources(scenery)
			var scene := PackedScene.new()
			var error := scene.pack(scenery)
			var chunk_file := LevelBake.chunk_path(location,route,quality,key)
			# Godot names references and nodes with fresh random ids on every
			# save; an unchanged section keeps its file so git sees no change.
			var digest := _content_digest(scene) if error==OK else ""
			var slot := "%s/%d" % [quality,key]
			if error==OK and (level.chunk_digests.get(slot,"")!=digest or not FileAccess.file_exists(chunk_file)):
				error = _save_stable(scene,chunk_file)
				level.chunk_digests[slot] = digest
			if error!=OK: push_error("BAKE chunk %d %s failed: %d" % [key,quality,error])
			scenery.free()
		world.free()
	level.chunk_count = chunk_count
	var error := _save_stable(level,path)
	if error!=OK: push_error("BAKE layout %s failed: %d" % [path,error])
	print("BAKE %s chunks=%d edited=%s in %d ms" % [LevelBake.directory(location,route),chunk_count,level.edited,Time.get_ticks_msec()-started])
	return 1

# Every node becomes part of the section scene itself. Model instances are
# flattened: their parts carry materials and shadow settings set in code,
# which an instance reference would drop. Nodes left unnamed by code get a
# name from their place, not from a global counter, so an unchanged section
# bakes to the same bytes.
func _own(node: Node, scene_root: Node) -> void:
	var index := 0
	for child in node.get_children():
		if str(child.name).begins_with("@"): child.name = "%s_%d" % [child.get_class(),index]
		index += 1
		child.owner = scene_root
		child.scene_file_path = ""
		_own(child,scene_root)

# Resources embedded in a scene get ids from their order, not random ones.
func _number_subresources(scene_root: Node) -> void:
	var seen := {}
	var queue: Array[Node] = [scene_root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		var resources: Array = []
		if node is GeometryInstance3D:
			resources.append_array([(node as GeometryInstance3D).material_override,(node as GeometryInstance3D).material_overlay])
		if node is MeshInstance3D:
			var instance := node as MeshInstance3D
			resources.append(instance.mesh)
			if instance.mesh!=null:
				for surface in range(instance.mesh.get_surface_count()): resources.append(instance.mesh.surface_get_material(surface))
			for surface in range(instance.get_surface_override_material_count()): resources.append(instance.get_surface_override_material(surface))
		if node is SpriteBase3D: resources.append((node as SpriteBase3D).get("texture"))
		if node is Label3D: resources.append((node as Label3D).font)
		for resource in resources:
			if resource is Resource and (resource as Resource).resource_path.is_empty() and not seen.has(resource):
				seen[resource] = true
				(resource as Resource).resource_scene_unique_id = "r%d" % seen.size()
		queue.append_array(node.get_children())

# The scene's text form without the ids Godot draws at random on each save.
func _content_digest(scene: PackedScene) -> String:
	var temporary := "user://bake_digest.tscn"
	if ResourceSaver.save(scene,temporary)!=OK: return ""
	var text := FileAccess.get_file_as_string(temporary)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	var ids := RegEx.create_from_string("([0-9]+)_[a-z0-9]{5}\"")
	text = ids.sub(text,"$1\"",true)
	text = RegEx.create_from_string(" unique_id=[0-9]+").sub(text,"",true)
	text = RegEx.create_from_string("uid=\"uid://[a-z0-9]+\"").sub(text,"",true)
	return text.sha256_text()

# Saves keeping the file's previous UID: re-baking an unchanged level leaves
# its files untouched in git.
func _save_stable(resource: Resource, file: String) -> Error:
	var uid := ResourceLoader.get_resource_uid(file) if ResourceLoader.exists(file) else ResourceUID.INVALID_ID
	var error := ResourceSaver.save(resource,file,ResourceSaver.FLAG_COMPRESS)
	if error==OK and uid!=ResourceUID.INVALID_ID: error = ResourceSaver.set_uid(file,uid)
	return error

func _externalize(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		if geometry.material_override!=null: _save_material(geometry.material_override)
		if geometry.material_overlay!=null: _save_material(geometry.material_overlay)
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in range(instance.get_surface_override_material_count()):
			var material := instance.get_surface_override_material(surface)
			if material!=null: _save_material(material)
		if instance.mesh!=null and instance.mesh.resource_path.is_empty():
			for surface in range(instance.mesh.get_surface_count()):
				var material := instance.mesh.surface_get_material(surface)
				if material!=null: _save_material(material)
	for child in node.get_children(): _externalize(child)

func _save_material(material: Material) -> void:
	if not material.resource_path.is_empty() or saved_resources.has(material): return
	if material is ShaderMaterial and (material as ShaderMaterial).shader!=null:
		_save_shader((material as ShaderMaterial).shader)
	if material.next_pass!=null: _save_material(material.next_pass)
	var file := SHARED.path_join("materials").path_join("m_%s.tres" % _content_key(material))
	_save_shared(material,file)

func _save_shader(shader: Shader) -> void:
	if not shader.resource_path.is_empty() or saved_resources.has(shader): return
	_save_shared(shader,SHARED.path_join("shaders").path_join("s_%s.gdshader" % shader.code.sha256_text().left(16)))

func _save_shared(resource: Resource, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(file.get_base_dir()))
	# Shared files are named by content: an existing one is already right.
	if not FileAccess.file_exists(file):
		var error := ResourceSaver.save(resource,file)
		if error!=OK: push_error("BAKE shared %s failed: %d" % [file,error])
	resource.take_over_path(file)
	saved_resources[resource] = file

# A name from the stored properties: equal materials share one file.
func _content_key(resource: Resource) -> String:
	var parts := [resource.get_class()]
	for property in resource.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE): continue
		var value = resource.get(property["name"])
		if value is Resource: value = (value as Resource).resource_path if not (value as Resource).resource_path.is_empty() else (value as Resource).get_instance_id()
		parts.append("%s=%s" % [property["name"],str(value)])
	return "|".join(parts).sha256_text().left(16)
