extends SceneTree
var failures: Array[String] = []
var samples: Dictionary = {}
var camera: Camera3D
func _initialize() -> void:
	call_deferred("run")
func capture(seed_value: int, time: float, center: Vector2, size: Vector2i) -> Dictionary:
	root.size = size
	await process_frame
	var sky := ProceduralSkyBackdrop.new()
	root.add_child(sky)
	sky.setup(seed_value,true)
	sky.set_view(center)
	camera.position = Vector3(center.x,center.y,28)
	sky.advance(time,1)
	for frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image := sky.sky_viewport.get_texture().get_image()
	var before: int = hash(image.get_data())
	sky.advance(time,1)
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var paused_same := hash(sky.sky_viewport.get_texture().get_image().get_data())==before
	var result := {"hash":before,"render_size":[image.get_width(),image.get_height()],"paused_same":paused_same,"quad_size":[sky.mesh.size.x,sky.mesh.size.y]}
	sky.queue_free()
	await process_frame
	return result
func run() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	root.add_child(camera)
	camera.current = true
	samples["base"] = await capture(58273,0,Vector2(0,7),Vector2i(1000,700))
	samples["repeat"] = await capture(58273,0,Vector2(0,7),Vector2i(1000,700))
	samples["other_seed"] = await capture(101,0,Vector2(0,7),Vector2i(1000,700))
	samples["wind"] = await capture(58273,30,Vector2(0,7),Vector2i(1000,700))
	samples["parallax"] = await capture(58273,0,Vector2(4,30),Vector2i(1000,700))
	samples["portrait"] = await capture(58273,0,Vector2(0,7),Vector2i(540,960))
	if samples.base.hash != samples.repeat.hash: failures.append("same seed/time must reproduce the same sky")
	for key in ["other_seed","wind","parallax"]:
		if samples.base.hash==samples[key].hash: failures.append(key+" must alter rendered pixels")
	for key in samples:
		if not samples[key].paused_same: failures.append(key+" changed with time frozen")
		if max(samples[key].render_size[0],samples[key].render_size[1])>640: failures.append("render budget exceeded")
	var ratio: float = float(samples.portrait.render_size[0])/samples.portrait.render_size[1]
	if absf(ratio-540.0/960)>0.003: failures.append("portrait aspect was stretched")
	var result := {"date":Time.get_date_string_from_system(),"renderer":"gl_compatibility","generation":"runtime shader, no image assets","samples":samples,"failures":failures,"mobile_performance":"not measured on device"}
	var report := FileAccess.open(ProjectSettings.globalize_path("res://../docs/validation/sky.json"),FileAccess.WRITE)
	if report==null:
		push_error("Unable to write sky validation report")
		quit(2)
		return
	report.store_string(JSON.stringify(result,"  "))
	print("SKY_VALIDATION ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
