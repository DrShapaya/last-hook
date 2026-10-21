class_name ProceduralSkyBackdrop
extends MeshInstance3D

const MAX_RENDER_EDGE := 640
const MOBILE_RENDER_EDGE := 448
const UPDATE_INTERVAL := 1.0 / 24.0
var sky_material := ShaderMaterial.new()
var sky_viewport := SubViewport.new()
var cloud_offset := Vector2.ZERO
var ridge_offset := Vector2.ZERO
var render_accumulator := 0.0
var last_sky_time := -1.0
# The cloud shader is kept for tools/validate_sky.gd; the game uses the flat sky.
var volumetric_sky := false

func setup(world_seed: int, volumetric: bool = false) -> void:
	name = "Процедурная атмосфера"
	var quad := QuadMesh.new()
	quad.size = Vector2(180,180)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not volumetric:
		# Default sky: one flat, saturated blue that lightens towards the
		# horizon, without clouds. A two-colour gradient costs nothing on phones.
		var flat := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled; uniform vec3 top_color : source_color = vec3(.353,.663,.941); uniform vec3 bottom_color : source_color = vec3(.55,.77,.96); void fragment(){ ALBEDO=mix(top_color,bottom_color,smoothstep(.0,1.0,UV.y)); }"
		flat.shader = shader
		material_override = flat
		# The flat sky renders no texture: release the unused viewport, or
		# every world leaks one at exit.
		sky_viewport.free()
		return
	volumetric_sky = true
	sky_viewport.name = "Небо_640"
	sky_viewport.disable_3d = true
	sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sky_viewport)
	sky_material.shader = preload("res://shaders/sky_backdrop.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x5C10D
	sky_material.set_shader_parameter("seed_offset",Vector3(rng.randf_range(0,100),rng.randf_range(0,100),rng.randf_range(0,100)))
	var canvas := ColorRect.new()
	canvas.material = sky_material
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_viewport.add_child(canvas)
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.albedo_texture = sky_viewport.get_texture()
	surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material_override = surface
	get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x<1 or size.y<1: return
	var ratio := size.x / size.y
	var render_edge := MOBILE_RENDER_EDGE if OS.has_feature("mobile") else MAX_RENDER_EDGE
	sky_viewport.size = Vector2i((size * minf(1.0,render_edge/maxf(size.x,size.y))).round())
	sky_material.set_shader_parameter("aspect",ratio)
	sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_view(center: Vector2) -> void:
	position = Vector3(center.x,center.y,-22)
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		var size := get_viewport().get_visible_rect().size
		var top_left := camera.project_position(Vector2.ZERO,50)
		var bottom_right := camera.project_position(size,50)
		(mesh as QuadMesh).size = Vector2(absf(bottom_right.x-top_left.x),absf(bottom_right.y-top_left.y)) * 1.002
	if not volumetric_sky: return
	cloud_offset = Vector2(center.x*.19,(center.y-7)*.045)
	ridge_offset = Vector2(center.x*.065,clampf(log(1.0+maxf(center.y-7,0)*.03),0,3))
	sky_material.set_shader_parameter("cloud_offset",cloud_offset)
	sky_material.set_shader_parameter("ridge_offset",ridge_offset)

func advance(time: float, delta: float) -> void:
	if not volumetric_sky: return
	render_accumulator += delta
	if render_accumulator<UPDATE_INTERVAL or is_equal_approx(last_sky_time,time): return
	render_accumulator = fmod(render_accumulator,UPDATE_INTERVAL)
	last_sky_time = time
	sky_material.set_shader_parameter("sky_time",time)
	sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
