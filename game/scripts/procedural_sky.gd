class_name ProceduralSkyBackdrop
extends MeshInstance3D

const MAX_RENDER_EDGE := 640
const MOBILE_RENDER_EDGE := 448
const UPDATE_INTERVAL := 1.0 / 30.0

var sky_material := ShaderMaterial.new()
var sky_viewport := SubViewport.new()
var cloud_offset := Vector2.ZERO
var ridge_offset := Vector2.ZERO
var render_accumulator := 0.0
var last_sky_time := -1.0
var volumetric_sky := false
var location := 0

func setup(world_seed: int, volumetric: bool = false, world_location: int = 0) -> void:
	name = "Процедурная атмосфера"
	var quad := QuadMesh.new()
	quad.size = Vector2(180,180)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	location = world_location

	sky_material.shader = preload("res://shaders/procedural_sky.gdshader")
	_apply_biome_palette(world_location)

	if not volumetric:
		# Direct high-performance spatial shader on QuadMesh.
		# Zero subviewports, runs at 60-120 FPS on all devices.
		material_override = sky_material
		sky_viewport.free()
		return

	# Volumetric/viewport mode kept for tools/validate_sky.gd compatibility.
	volumetric_sky = true
	sky_viewport.name = "Небо_640"
	sky_viewport.disable_3d = true
	sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sky_viewport)

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x5C10D
	sky_material.set_shader_parameter("cloud_offset",Vector2(rng.randf_range(0,10),rng.randf_range(0,10)))

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

func _apply_biome_palette(loc: int) -> void:
	match loc:
		1: # Desert Canyon
			sky_material.set_shader_parameter("top_color",Color("284e78"))
			sky_material.set_shader_parameter("horizon_color",Color("e2a476"))
			sky_material.set_shader_parameter("cloud_lit",Color("fff6ec"))
			sky_material.set_shader_parameter("cloud_shadow",Color("856860"))
			sky_material.set_shader_parameter("sun_color",Color("ffdba3"))
			sky_material.set_shader_parameter("cloud_coverage",0.38)
		2: # Snowy Summit / Sky City
			sky_material.set_shader_parameter("top_color",Color("15386b"))
			sky_material.set_shader_parameter("horizon_color",Color("8fcbe8"))
			sky_material.set_shader_parameter("cloud_lit",Color("f4faff"))
			sky_material.set_shader_parameter("cloud_shadow",Color("526c88"))
			sky_material.set_shader_parameter("sun_color",Color("e8f5ff"))
			sky_material.set_shader_parameter("cloud_coverage",0.52)
		_: # Standard Alpine Mountain
			sky_material.set_shader_parameter("top_color",Color("1c4e8c"))
			sky_material.set_shader_parameter("horizon_color",Color("6cb0e8"))
			sky_material.set_shader_parameter("cloud_lit",Color("fffefa"))
			sky_material.set_shader_parameter("cloud_shadow",Color("5c728e"))
			sky_material.set_shader_parameter("sun_color",Color("fff2cf"))
			sky_material.set_shader_parameter("cloud_coverage",0.46)

func _resize() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x<1 or size.y<1: return
	var ratio := size.x / size.y
	var render_edge := MOBILE_RENDER_EDGE if OS.has_feature("mobile") else MAX_RENDER_EDGE
	if volumetric_sky and is_instance_valid(sky_viewport):
		sky_viewport.size = Vector2i((size * minf(1.0,render_edge/maxf(size.x,size.y))).round())
		sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	sky_material.set_shader_parameter("aspect",ratio)

func set_view(center: Vector2) -> void:
	position = Vector3(center.x,center.y,-22)
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		var size := get_viewport().get_visible_rect().size
		var top_left := camera.project_position(Vector2.ZERO,50)
		var bottom_right := camera.project_position(size,50)
		(mesh as QuadMesh).size = Vector2(absf(bottom_right.x-top_left.x),absf(bottom_right.y-top_left.y)) * 1.002
		if size.y > 0:
			sky_material.set_shader_parameter("aspect",size.x/size.y)
	cloud_offset = Vector2(center.x*.04,(center.y-7)*.02)
	sky_material.set_shader_parameter("cloud_offset",cloud_offset)

func advance(time: float, _delta: float) -> void:
	sky_material.set_shader_parameter("sky_time",time)
	if volumetric_sky and is_instance_valid(sky_viewport):
		sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
