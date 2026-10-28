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
	if ResourceLoader.exists(path) and not regenerate:
		level = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as LevelBake
		if level!=null and (level.format!=LevelBake.FORMAT or level.generation_version!=version or (level.seed_value!=seed_value and not level.edited)): level = null
	if level==null:
		level = LevelBake.new()
		level.location = location
		level.route = route
		level.generation_version = version
		level.seed_value = seed_value
		level.height = height
		var source := MountainWorld.new()
		source.visuals_enabled = false
		root.add_child(source)
		source.setup(seed_value,location,version,false,route)
		source.generate_to(height+6,true,height)
		level.layout_data = LevelBake.capture(source.layout)
		source.free()
	var chunk_count := 0
	for quality in LevelBake.QUALITIES:
		var world := MountainWorld.new()
		world.visuals_enabled = false
		root.add_child(world)
		world.setup(level.seed_value,location,version,false,route)
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
			var scene := PackedScene.new()
			var error := scene.pack(scenery)
			if error==OK: error = ResourceSaver.save(scene,LevelBake.chunk_path(location,route,quality,key),ResourceSaver.FLAG_COMPRESS)
			if error!=OK: push_error("BAKE chunk %d %s failed: %d" % [key,quality,error])
			scenery.free()
		world.free()
	level.chunk_count = chunk_count
	var error := ResourceSaver.save(level,path)
	if error!=OK: push_error("BAKE layout %s failed: %d" % [path,error])
	print("BAKE %s chunks=%d edited=%s in %d ms" % [LevelBake.directory(location,route),chunk_count,level.edited,Time.get_ticks_msec()-started])
	return 1

# Every node becomes part of the section scene itself. Model instances are
# flattened: their parts carry materials and shadow settings set in code,
# which an instance reference would drop.
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		child.scene_file_path = ""
		_own(child,scene_root)

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
