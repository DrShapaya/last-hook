class_name ProceduralSkyBackdrop
extends MeshInstance3D

const UPDATE_INTERVAL := 1.0 / 30.0
# Share of the screen resolution the sky is painted at, per graphics preset.
# "high" paints every screen pixel each frame; the others paint a smaller
# texture at most UPDATE_INTERVAL apart. The sky is soft gradients and
# slow clouds, so it upscales cleanly, and its fbm noise is the costliest
# fragment work of a frame on phone GPUs.
const RENDER_SCALES := {"high":1.0,"balanced":.5,"battery":.34}

var sky_material := ShaderMaterial.new()
var sky_viewport: SubViewport
var sky_camera: Camera3D
var sky_canvas: MeshInstance3D
var cached_material: StandardMaterial3D
var cloud_offset := Vector2.ZERO
var ridge_offset := Vector2.ZERO
var render_accumulator := 0.0
var last_sky_time := -1.0
var render_scale := 1.0
var render_dirty := true
var location := 0
var view_size := Vector2.ZERO
var quad_size := Vector2.ZERO
var shown_params := {}

func setup(world_seed: int, _volumetric: bool = false, world_location: int = 0) -> void:
	name = "Процедурная атмосфера"
	var quad := QuadMesh.new()
	quad.size = Vector2(180,180)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	location = world_location

	sky_material.shader = preload("res://shaders/procedural_sky.gdshader")
	_apply_biome_palette(world_location)
	# Each world gets its own skyline.
	sky_material.set_shader_parameter("sky_seed",float(world_seed%997)*.37)
	material_override = sky_material
	get_viewport().size_changed.connect(_resize)

# Switches between painting the sky straight on screen and painting it into
# a smaller cached texture (see RENDER_SCALES).
func set_quality(quality: String) -> void:
	var scale_value: float = RENDER_SCALES.get(quality,RENDER_SCALES["balanced"])
	if is_equal_approx(scale_value,render_scale) and (scale_value>=1.0 or sky_viewport!=null): return
	render_scale = scale_value
	if render_scale>=1.0:
		material_override = sky_material
		if sky_viewport!=null:
			sky_viewport.queue_free()
			sky_viewport = null
		return
	if sky_viewport==null:
		sky_viewport = SubViewport.new()
		sky_viewport.name = "Небо"
		# Its own empty world: only the sky quad and an orthographic camera.
		sky_viewport.own_world_3d = true
		sky_viewport.transparent_bg = false
		sky_viewport.msaa_3d = Viewport.MSAA_DISABLED
		sky_viewport.positional_shadow_atlas_size = 0
		sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(sky_viewport)
		sky_camera = Camera3D.new()
		sky_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		sky_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		sky_camera.size = 1.0
		sky_camera.position = Vector3(0,0,1)
		sky_camera.current = true
		sky_viewport.add_child(sky_camera)
		sky_canvas = MeshInstance3D.new()
		sky_canvas.mesh = QuadMesh.new()
		sky_canvas.material_override = sky_material
		sky_canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky_viewport.add_child(sky_canvas)
		cached_material = StandardMaterial3D.new()
		cached_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cached_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		cached_material.albedo_texture = sky_viewport.get_texture()
	material_override = cached_material
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
			sky_material.set_shader_parameter("range_far",Color("d7a582"))
			sky_material.set_shader_parameter("range_mid",Color("b0705a"))
			sky_material.set_shader_parameter("range_near",Color("7e4a3a"))
			sky_material.set_shader_parameter("snow_amount",0.0)
		2: # Snowy Summit / Sky City
			sky_material.set_shader_parameter("top_color",Color("15386b"))
			sky_material.set_shader_parameter("horizon_color",Color("8fcbe8"))
			sky_material.set_shader_parameter("cloud_lit",Color("f4faff"))
			sky_material.set_shader_parameter("cloud_shadow",Color("526c88"))
			sky_material.set_shader_parameter("sun_color",Color("e8f5ff"))
			sky_material.set_shader_parameter("cloud_coverage",0.52)
			sky_material.set_shader_parameter("range_far",Color("b9c8e2"))
			sky_material.set_shader_parameter("range_mid",Color("7e95bd"))
			sky_material.set_shader_parameter("range_near",Color("53668c"))
			sky_material.set_shader_parameter("snow_amount",0.8)
		_: # Standard Alpine Mountain
			sky_material.set_shader_parameter("top_color",Color("1c4e8c"))
			sky_material.set_shader_parameter("horizon_color",Color("6cb0e8"))
			sky_material.set_shader_parameter("cloud_lit",Color("fffefa"))
			sky_material.set_shader_parameter("cloud_shadow",Color("5c728e"))
			sky_material.set_shader_parameter("sun_color",Color("fff2cf"))
			sky_material.set_shader_parameter("cloud_coverage",0.46)
			sky_material.set_shader_parameter("range_far",Color("8fb1d4"))
			sky_material.set_shader_parameter("range_mid",Color("5c82a8"))
			sky_material.set_shader_parameter("range_near",Color("355a63"))
			sky_material.set_shader_parameter("snow_amount",0.35)

func _resize() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x<1 or size.y<1: return
	_set_param("aspect",size.x/size.y)
	if sky_viewport==null: return
	var target := Vector2i((size*render_scale).round()).max(Vector2i(8,8))
	if sky_viewport.size!=target: sky_viewport.size = target
	(sky_canvas.mesh as QuadMesh).size = Vector2(size.x/size.y,1.0)
	render_dirty = true

func set_view(center: Vector2) -> void:
	position = Vector3(center.x,center.y,-22)
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera):
		var size := get_viewport().get_visible_rect().size
		if size!=view_size or not is_equal_approx(camera.size,float(shown_params.get("camera_size",-1.0))):
			# The quad covers the view; it only changes with the screen or zoom.
			# Resizing a QuadMesh rebuilds its buffers, so skip identical sizes.
			shown_params["camera_size"] = camera.size
			view_size = size
			var top_left := camera.project_position(Vector2.ZERO,50)
			var bottom_right := camera.project_position(size,50)
			var wanted := Vector2(absf(bottom_right.x-top_left.x),absf(bottom_right.y-top_left.y)) * 1.002
			if wanted!=quad_size:
				quad_size = wanted
				(mesh as QuadMesh).size = wanted
			if size.y > 0: _set_param("aspect",size.x/size.y)
			if sky_viewport!=null: _resize()
	cloud_offset = Vector2(center.x*.04,(center.y-7)*.02)
	_set_param("cloud_offset",cloud_offset)
	_set_param("altitude",maxf(0.0,center.y-8.0))
	_set_param("view_x",center.x)

func advance(time: float, delta: float) -> void:
	_set_param("sky_time",time)
	if sky_viewport==null: return
	render_accumulator += delta
	if render_dirty and render_accumulator>=UPDATE_INTERVAL:
		render_accumulator = 0.0
		render_dirty = false
		sky_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _set_param(key: String, value: Variant) -> void:
	if shown_params.has(key) and shown_params[key]==value: return
	shown_params[key] = value
	sky_material.set_shader_parameter(key,value)
	render_dirty = true
