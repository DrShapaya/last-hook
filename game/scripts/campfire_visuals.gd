class_name CampfireVisuals
extends RefCounted

# A blizzard campfire on a ledge: a few crossed logs, two or three crossed
# flame cards with an animated shader and a handful of sparks. The warm light
# is an OmniLight only above the battery preset; there it is emission alone.

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float seed = 0.0;
float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7)))*43758.5453); }
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1.0, 0.0)), f.x), mix(hash(i+vec2(0.0, 1.0)), hash(i+vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float t = mod(TIME, 600.0);
	vec2 uv = vec2(UV.x-.5, 1.0-UV.y);
	// Tongues rise and flicker; the flame narrows toward its tip.
	float n = noise(vec2(uv.x*5.0+seed, uv.y*3.2-t*3.4));
	float n2 = noise(vec2(uv.x*9.0-seed, uv.y*6.0-t*5.1));
	float width = (.42-.34*uv.y)*(.75+.5*n);
	float body = 1.0-smoothstep(width*.55, width, abs(uv.x+(n2-.5)*.12*uv.y));
	float height = 1.0-smoothstep(.45+.4*n, 1.0, uv.y);
	float f = body*height*smoothstep(0.0, .06, uv.y);
	vec3 hot = vec3(1.0, .93, .62);
	vec3 warm = vec3(1.0, .52, .14);
	vec3 deep = vec3(.75, .18, .05);
	vec3 c = mix(deep, warm, smoothstep(.0, .5, f));
	c = mix(c, hot, smoothstep(.55, .95, f)*(1.0-uv.y));
	ALBEDO = c*f*1.6;
	ALPHA = f;
}
"""

const LIGHT_ENERGY := 1.3
const WARM_SECONDS := .4

static var _shader: Shader
static var _materials := {}

# reduce_effects: the light burns steady (no flicker tween).
static func build(parent: Node3D, at: Vector2, z: float, with_light: bool, reduce_effects: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Костёр"
	root.add_to_group("campfire")
	parent.add_child(root)
	if parent.is_inside_tree(): root.global_position = Vector3(at.x,at.y,z)
	else: root.position = Vector3(at.x,at.y,z)
	_logs(root)
	_flames(root)
	_sparks(root)
	if with_light: _light(root,not reduce_effects)
	return root

# A campfire drawn once in a tiny offscreen view of its own world, so its
# flame, ember and spark shaders are compiled before the first one is met.
# Frees itself after WARM_SECONDS.
static func warm(host: Node) -> SubViewport:
	var view := SubViewport.new()
	view.name = "Прогрев костра"
	view.size = Vector2i(32,32)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var eye := Camera3D.new()
	eye.position = Vector3(0,.4,2.0)
	view.add_child(eye)
	var stage := Node3D.new()
	view.add_child(stage)
	host.add_child(view)
	eye.current = true
	var fire := build(stage,Vector2.ZERO,0.0,true,true)
	# Not a warming spot: kept out of the campfire group.
	fire.remove_from_group("campfire")
	if view.is_inside_tree(): view.get_tree().create_timer(WARM_SECONDS).timeout.connect(view.queue_free)
	return view

# Starts or stops the soft flicker of a campfire's light (settings change).
static func set_flicker(root: Node, on: bool) -> void:
	for light: OmniLight3D in root.find_children("*","OmniLight3D",true,false):
		if light.has_meta("flicker"):
			var old := light.get_meta("flicker") as Tween
			if old!=null and old.is_valid(): old.kill()
			light.remove_meta("flicker")
		light.light_energy = LIGHT_ENERGY
		if on: _flicker(light)

static func _material(key: String, color: Color, emission: float = 0.0) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	if emission>0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material

static func _logs(root: Node3D) -> void:
	var bark := _material("campfire_bark",Color("4a3122"))
	var ember := _material("campfire_ember",Color("ff7a2a"),2.2)
	# Logs leaning together over the fire, their tops meeting.
	var apex := Vector3(0,.36,0)
	for i in range(4):
		var turn := float(i)*PI*.5+.4
		var foot := Vector3(cos(turn)*.3,0,sin(turn)*.18)
		var axis := apex-foot
		var wood := MeshInstance3D.new()
		wood.name = "Полено_%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = .045
		mesh.bottom_radius = .06
		mesh.height = axis.length()+.08
		mesh.radial_segments = 6
		mesh.rings = 1
		wood.mesh = mesh
		wood.material_override = bark
		var up := axis.normalized()
		var side := up.cross(Vector3.BACK).normalized()
		wood.basis = Basis(side,up,side.cross(up))
		wood.position = (foot+apex)*.5
		wood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wood)
	# A ring of stones and the glowing bed under the flames.
	var stone := _material("campfire_stone",Color("6f6c69"))
	for i in range(7):
		var piece := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = .07
		mesh.height = .1
		mesh.radial_segments = 6
		mesh.rings = 3
		piece.mesh = mesh
		piece.material_override = stone
		var turn := float(i)/7.0*TAU
		piece.position = Vector3(cos(turn)*.32,.03,sin(turn)*.2)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
	var bed := MeshInstance3D.new()
	bed.name = "Угли"
	var bed_mesh := SphereMesh.new()
	bed_mesh.radius = .2
	bed_mesh.height = .08
	bed_mesh.radial_segments = 8
	bed_mesh.rings = 2
	bed.mesh = bed_mesh
	bed.material_override = ember
	bed.position = Vector3(0,.02,0)
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bed)

static func _flames(root: Node3D) -> void:
	if _shader==null:
		_shader = Shader.new()
		_shader.code = FLAME_SHADER
	for i in range(3):
		var card := MeshInstance3D.new()
		card.name = "Пламя_%d" % i
		var quad := QuadMesh.new()
		quad.size = Vector2(.62,.9) if i==0 else Vector2(.5,.74)
		card.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = _shader
		material.set_shader_parameter("seed",float(i)*3.7)
		card.material_override = material
		# Crossed cards: the front view always sees two of them wide.
		card.rotation.y = [0.0,.95,-.95][i]
		card.position = Vector3(0,quad.size.y*.5+.02,.02*i)
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(card)

static func _sparks(root: Node3D) -> void:
	var sparks := GPUParticles3D.new()
	sparks.name = "Искры"
	sparks.amount = 10
	sparks.lifetime = 1.4
	sparks.position = Vector3(0,.35,.05)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0,1,0)
	process.spread = 18.0
	process.initial_velocity_min = .5
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0,.25,0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = .12
	process.scale_min = .6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0,.2,1.0])
	fade.colors = PackedColorArray([Color(1,.85,.4,1),Color(1,.6,.2,1),Color(1,.3,.1,0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	sparks.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(.035,.035)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	sparks.draw_pass_1 = quad
	sparks.visibility_aabb = AABB(Vector3(-1,-.5,-1),Vector3(2,3,2))
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sparks)

static func _light(root: Node3D, flicker: bool) -> void:
	var light := OmniLight3D.new()
	light.name = "Свет костра"
	light.light_color = Color(1.0,.62,.3)
	light.light_energy = LIGHT_ENERGY
	light.omni_range = 3.6
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0,.55,.6)
	root.add_child(light)
	if flicker: _flicker(light)

# A slow, soft flicker; the tween lives and dies with the light.
static func _flicker(light: OmniLight3D) -> void:
	if not light.is_inside_tree(): return
	var tween := light.create_tween().set_loops()
	light.set_meta("flicker",tween)
	tween.tween_property(light,"light_energy",1.05,.23).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light,"light_energy",1.4,.31).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light,"light_energy",1.2,.19).set_trans(Tween.TRANS_SINE)
