class_name ShaderBank
extends RefCounted

# Keeps compiled shaders alive for the whole session.
#
# 1. of(code): one Shader object per source text. A Shader made anew
#    (Shader.new() per world, hero or screen) is compiled anew by the GPU
#    driver the first time it is drawn.
# 2. hold_tree(root): the engine writes the shader of a StandardMaterial3D or
#    a ParticleProcessMaterial from its settings and drops it when the last
#    material with those settings is freed. Every new mountain then compiled
#    its particles, tags, coins and props again on its first draw: 13-40 ms
#    each on a PC, 130-340 ms in one lobby frame, far more on a phone, and
#    again in the middle of a climb when a new act came into view. One
#    material of each kind is kept here, so those shaders stay compiled.

static var _by_code := {}
static var _held := {} # signature -> Material
static var _known := {} # instance ids already looked at

static func of(code: String) -> Shader:
	var found: Shader = _by_code.get(code)
	if found==null:
		found = Shader.new()
		found.code = code
		_by_code[code] = found
	return found

# What decides the shader the engine writes for a material: its switches and
# choices, and which textures are set. Colours and numbers are only values.
static func signature(material: Material) -> String:
	var parts := PackedStringArray([material.get_class()])
	for property in material.get_property_list():
		if int(property["usage"])&PROPERTY_USAGE_STORAGE==0: continue
		var kind := int(property["type"])
		if kind==TYPE_BOOL or kind==TYPE_INT: parts.append(str(int(material.get(property["name"]))))
		elif kind==TYPE_OBJECT: parts.append("1" if material.get(property["name"])!=null else "0")
	return "|".join(parts)

static func hold(material: Material) -> void:
	if not (material is BaseMaterial3D or material is ParticleProcessMaterial): return
	var key := signature(material)
	if not _held.has(key): _held[key] = material

# Every engine-written material under `root`. Called once a world has been
# drawn, and when a climbed world is let go.
static func hold_tree(root: Node) -> void:
	var seen := {}
	_walk(root,seen)
	for id in seen:
		# A material met before costs nothing the second time.
		if _known.has(id): continue
		_known[id] = true
		hold(seen[id])

static func _note(material: Material, seen: Dictionary) -> void:
	if material==null: return
	seen[material.get_instance_id()] = material
	if material.next_pass!=null: _note(material.next_pass,seen)

static func _note_mesh(mesh: Mesh, seen: Dictionary) -> void:
	if mesh==null: return
	for surface in range(mesh.get_surface_count()): _note(mesh.surface_get_material(surface),seen)

static func _walk(node: Node, seen: Dictionary) -> void:
	if node is GeometryInstance3D:
		_note(node.material_override,seen)
		_note(node.material_overlay,seen)
	if node is MeshInstance3D:
		_note_mesh(node.mesh,seen)
		if node.mesh!=null:
			for surface in range(node.mesh.get_surface_count()): _note(node.get_surface_override_material(surface),seen)
	elif node is GPUParticles3D:
		_note(node.process_material,seen)
		for pass_index in range(node.draw_passes): _note_mesh(node.get_draw_pass_mesh(pass_index),seen)
	elif node is CPUParticles3D:
		_note_mesh(node.mesh,seen)
	elif node is MultiMeshInstance3D and node.multimesh!=null:
		_note_mesh(node.multimesh.mesh,seen)
	for child in node.get_children(): _walk(child,seen)

# Before the renderer shuts down: nothing of it may outlive the game.
static func clear() -> void:
	_by_code.clear()
	_held.clear()
	_known.clear()

static func held_count() -> int:
	return _held.size()
