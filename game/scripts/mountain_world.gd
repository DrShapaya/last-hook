class_name MountainWorld
extends Node3D

const FloraModels := preload("res://scripts/flora_models.gd")

const GENERATION_VERSION := 16
# A timed root holds this long before it breaks (see GripSpec).
const FRAGILE_SECONDS := GripSpec.ROOT_SECONDS
const COLORS := [Color("e3b95e"),Color("e8624d"),Color("70c995"),Color("78d8e5"),Color("a994df"),Color("f1d27b")]
var layout := MountainLayout.new()
var visuals: MountainVisuals
var visuals_enabled := true
var anchors: Array[Dictionary] = []
var main_route: Array[int] = []
var route_edges: Array[Vector2i] = []
var obstacles: Array[Dictionary] = []
var finds: Array[Dictionary] = []
var ledges: Array[Dictionary] = []
var chunks: Dictionary = {}
var materials: Dictionary = {}
# Shared shaders live with the world, not in static vars, so they are freed
# before the renderer shuts down.
var shaders: Dictionary = {}
var seed_value := 0
var location := 0
var generation_version := GENERATION_VERSION
var generated_height := 0.0
# The level made in advance this world runs on (see LevelBake), or null when
# its layout comes from the generator.
var bake: LevelBake
var ghost_texture: ImageTexture
var sky_backdrop: ProceduralSkyBackdrop
var far_layers: Array[Node3D] = []
var far_bands: Dictionary = {}
var camera_center := Vector2(0,7)
# Environmental hazards of the acts (v14); empty on older generators.
var hazards: ActHazards
var hazard_visuals: HazardVisuals
var show_loot_prices := true
var visual_quality := "balanced"
# Loot glints and halos: "full", "reduced" or "off". Sky detail follows the
# decor unless a setting chose its own.
var effects_quality := "full"
var sky_quality := ""
# Runtime worlds build at most one visual chunk per visibility update. Tests and
# offline tools keep the default synchronous behaviour so their scene queries
# remain deterministic.
var visual_build_budget := -1
var generation_row_budget := -1
const MAX_CHUNK_BUILDS_PER_UPDATE := 1
const MAX_FAR_BAND_BUILDS_PER_UPDATE := 1
const STREAM_MOVE_THRESHOLD := .28
var stream_center := Vector2.INF
var stream_pending := true
var stream_dirty := true
# A streamed section is built over several frames (rock, decor, grips, finds
# take hundreds of milliseconds together): builders pause once the frame's
# slice is spent. Only the section of the running job ever pauses; direct
# builds (start of a run, tests, tools) stay synchronous.
const BUILD_SLICE_USEC := 4000
# Within this distance of the view centre a section is due on screen soon,
# so it gets a larger, but still bounded, slice.
const BUILD_URGENT_DISTANCE := 18.0
const BUILD_URGENT_SLICE_USEC := 6000
var build_job_key := -1
var build_job_band := NO_BAND
var build_job_parent_id := 0
var build_job_cancelled := false
var band_job_token := RefCounted.new()
const NO_BAND := -1000000
var build_deadline := 0
# Set while complete_view finishes a paused job in one go.
var build_rush := false
# Off for a world prepared out of sight: no section of it is due on screen,
# so every job keeps to its slice.
var build_urgency := true
var hazards_pending := false
# Resumes a paused section job; emitted once per streaming update. A world
# freed mid-job simply never resumes it.
signal build_tick

# Every location slot starts new attempts on the expedition generator (v15:
# v14 geometry with role-based finds, coins and contracts). Saved attempts keep
# their own: v14 anywhere, v6-v13 on the first location, v4 elsewhere.
static func generation_version_for(_biome: int) -> int:
	return GENERATION_VERSION

static func resumable(version: int, biome: int) -> bool:
	if version in [14,15,GENERATION_VERSION]: return true
	return version in [6,7,8,9,10,11,12,13] if biome==0 else version==4

# v16 summit climbs run on a prepared route (LevelCatalog.ROUTES): its index
# is `route_index`; -1 keeps the seed's own route (endless, menus, tests).
var route_index := -1

func setup(world_seed: int, world_location: int, saved_version: int = 0, practice: bool = false, route: int = -1, from_masks: bool = false) -> void:
	seed_value = world_seed
	location = world_location
	generation_version = saved_version if saved_version>0 else generation_version_for(location)
	if generation_version>=10 and location==0: layout = EncounterLayout.new()
	if generation_version>=11 and location==0: layout = MassifLayout.new()
	# v14: acts of the level decide route, silhouette, profile and hazards.
	if generation_version>=14: layout = MaskLayout.new() if from_masks else ExpeditionLayout.new()
	if practice: layout = PracticeLayout.new()
	# v15 changes only the finds layer; v14 geometry and hazards are kept.
	if layout is ExpeditionLayout: layout.economy_loot = generation_version>=15
	route_index = route if layout is ExpeditionLayout and generation_version>=16 else -1
	if route_index>=0: layout.route = LevelCatalog.route(world_location,route_index)
	layout.gentle_intro = generation_version>=7
	layout.sparse_route = generation_version>=8
	layout.safe_routes = generation_version>=9
	# v12 assigns grip types from the movement phrase's scenario.
	layout.scenario_routes = generation_version>=12
	# v13 calibrates the type mix and slides ice across its grip.
	layout.calibrated_routes = generation_version>=13
	# Only a saved v4 attempt still regenerates on the old generator.
	if location!=0 and generation_version<14 and not practice: layout = LegacyMountainLayout.new()
	layout.generation_version = generation_version
	layout.setup(world_seed,world_location)
	anchors = layout.anchors
	main_route = layout.main_route
	obstacles = layout.obstacles
	finds = layout.finds
	ledges = layout.ledges
	visuals = MountainVisuals.new(self,layout)
	if layout is MassifLayout: visuals = MassifVisuals.new(self,layout)
	# Locations on generator v4 and the practice route have no landforms of
	# their own; they get the same rock-mass mountain round their route line.
	if layout is LegacyMountainLayout or practice: visuals = LegacyMountainVisuals.new(self,layout)
	hazards = ActHazards.new(self,layout)
	if visuals_enabled:
		_build_sky()
		if layout is ExpeditionLayout: hazard_visuals = HazardVisuals.new(self,layout)

func set_visual_quality(quality: String) -> void:
	var selected := quality if quality in ["high","balanced","battery"] else "balanced"
	var changed := selected!=visual_quality
	visual_quality = selected
	if is_instance_valid(sky_backdrop): sky_backdrop.set_quality(_sky_detail())
	if visuals!=null and visuals.has_method("set_quality"):
		visuals.set_quality(visual_quality)
	# Decor density, loot glints and shadow casters are baked per chunk.
	if changed: _rebuild_chunks()

func set_effects_quality(value: String) -> void:
	if value==effects_quality: return
	effects_quality = value
	_rebuild_chunks()

func set_sky_quality(value: String) -> void:
	sky_quality = value
	if is_instance_valid(sky_backdrop): sky_backdrop.set_quality(_sky_detail())

func _sky_detail() -> String:
	return sky_quality if not sky_quality.is_empty() else visual_quality

func _rebuild_chunks() -> void:
	if not visuals_enabled or chunks.is_empty(): return
	for key in chunks.keys(): _release_chunk(key)
	stream_pending = true
	stream_dirty = true
	update_visibility(camera_center.y,camera_center.x,visual_build_budget)

func seeded_rng(index: int, stream: int) -> RandomNumberGenerator:
	return layout.rng(index,stream)

func cliff_edge(index: int, side: int) -> float:
	return layout.outer_edge(index*4.0,side)

func outside_mountain(point: Vector2) -> bool:
	return layout.outside(point)

func generate_to(height: float, finite: bool, summit: float = 120) -> void:
	var target := minf(height,summit+6) if finite else height
	layout.generation_row_budget = generation_row_budget
	layout.generate_to(target,finite,summit)
	route_edges = layout.edges
	if generation_row_budget>=0 and not layout.summit_added and layout.row>0:
		# The layout may intentionally build only a few rows this call. Expose
		# the actual frontier so the caller can request the next slice next tick.
		generated_height = maxf(generated_height,layout.main_point(layout.row).y)
	else:
		generated_height = maxf(generated_height,target)
	stream_pending = true
	stream_dirty = true
	# The top chunk changes when the summit is added; refresh it if loaded.
	if layout.summit_added:
		var key := int(floor(summit/24))
		if chunks.has(key): _release_chunk(key)
	if visuals_enabled: update_visibility(camera_center.y,camera_center.x,visual_build_budget)

# Takes a finite level made in advance instead of generating it: the layout
# as stored, and from then on each section's scenery from its baked scene.
# Call after setup with the same location and route; ends where a full
# generate_to would.
func load_bake(level: LevelBake) -> void:
	bake = level
	LevelBake.apply(layout,level.layout_data)
	route_edges = layout.edges
	generated_height = maxf(generated_height,minf(level.height+6,layout.summit+6))
	stream_pending = true
	stream_dirty = true
	if visuals_enabled: update_visibility(camera_center.y,camera_center.x,visual_build_budget)

func _baked_chunk_path(key: int) -> String:
	if bake==null: return ""
	var path := LevelBake.chunk_path(bake.location,bake.route,visual_quality,key)
	return path if ResourceLoader.exists(path) else ""

# Puts a section's baked scenery under its node. The rock takes the world's shared material of its act.
func _attach_baked(key: int, chunk: Node3D, scene: PackedScene) -> void:
	var scenery := scene.instantiate()
	chunk.add_child(scenery)
	if visuals is MassifVisuals:
		var rock := scenery.get_node_or_null("Скальный массив_%d" % key) as MeshInstance3D
		if rock!=null: rock.material_override = (visuals as MassifVisuals).rock_material_at(key*24.0+12.0)

# Layout rows toward generate_to's target, `budget` at a time, without
# streaming anything; finish with generate_to. False for generators that
# cannot be split (they do everything in generate_to). True while rows remain.
func generate_rows(height: float, finite: bool, summit: float, budget: int) -> bool:
	if layout is LegacyMountainLayout: return false
	var target := minf(height,summit+6) if finite else height
	return layout.generate_rows(target,finite,summit,budget)

func add_anchor(point: Vector2, kind: int, _bush: bool = false, dimensions: Vector2 = Vector2(1.8,.65)) -> void:
	var id := layout._add_anchor(point,kind,dimensions)
	if visuals_enabled:
		var key := int(floor(point.y/24))
		if chunks.has(key): build_anchor(anchors[id],chunks[key])

func add_obstacle(point: Vector2, dimensions: Vector2) -> void:
	var object := {"pos":point,"dimensions":dimensions}
	obstacles.append(object)
	if visuals_enabled:
		var key := int(floor(point.y/24))
		if chunks.has(key): visuals.build_obstacle(object,chunks[key])

func add_ledge(point: Vector2, width: float) -> void:
	var object := {"left":point.x-width*.5,"right":point.x+width*.5,"top":point.y+.15}
	ledges.append(object)
	if visuals_enabled:
		var key := int(floor(point.y/24))
		if chunks.has(key): visuals.build_ledge(object,chunks[key])

func nearby_anchors(low: float, high: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in layout.nearby_ids(low,high): result.append(anchors[id])
	return result

func nearby_obstacles(low: float, high: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object in obstacles:
		if object["pos"].y+object["dimensions"].y*.5>=low and object["pos"].y-object["dimensions"].y*.5<=high:
			result.append(object)
	return result

func rope_blocked(from: Vector2, to: Vector2) -> bool:
	return not rope_contact(from,to).is_empty()

func rope_clearance_blocked(from: Vector2, to: Vector2, clearance: float = .11) -> bool:
	for obstacle in nearby_obstacles(minf(from.y,to.y)-.2,maxf(from.y,to.y)+.2):
		if not SolidGeometry.contour_cast(from,to,obstacle,clearance).is_empty(): return true
	return false

func rope_contact(from: Vector2, to: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for obstacle in nearby_obstacles(minf(from.y,to.y)-.1,maxf(from.y,to.y)+.1):
		var hit := SolidGeometry.contour_cast(from,to,obstacle,0)
		if not hit.is_empty() and (best.is_empty() or hit["fraction"]<best["fraction"]): best = hit
	return best

func update_rope_path(sim: RopeSim) -> bool:
	if not sim.attached: return true
	# The rope should route around the solid contour, but remain visually seated
	# on the rock instead of hovering away from it.  The swept hit test still
	# keeps a tiny radius so the tube cannot tunnel through a corner.
	const ROPE_CLEARANCE := .10
	var root := sim.anchor
	for point in sim.rope_pivots:
		if rope_clearance_blocked(root,point,.045):
			sim.rope_pivots.clear()
			break
		root = point
	# Unwrap only when the previous fixed point can see the body directly.
	# Keeping the intervening corners until then prevents side-to-side jumps.
	while not sim.rope_pivots.is_empty():
		var previous: Vector2 = sim.anchor if sim.rope_pivots.size()==1 else sim.rope_pivots[-2]
		# Discard temporary corners when the direct route is clear again.
		if rope_clearance_blocked(previous,sim.pos,.045): break
		sim.rope_pivots.pop_back()
	for iteration in range(6):
		var pivot := sim.effective_anchor()
		var collision := rope_contact(pivot,sim.pos)
		if collision.is_empty(): return true
		if sim.rope_pivots.size()>=4: return false
		var best := Vector2.INF
		var best_score := INF
		for corner in SolidGeometry.corners(collision["object"],ROPE_CLEARANCE):
			if corner.distance_to(pivot)<.05 or sim.rope_pivots.has(corner): continue
			if rope_clearance_blocked(pivot,corner,.045): continue
			if sim.fixed_length()+pivot.distance_to(corner)>sim.length-.4: continue
			var score := pivot.distance_to(corner)+corner.distance_to(sim.pos)
			if score<best_score:
				best = corner
				best_score = score
		if not best.is_finite(): return false
		sim.rope_pivots.append(best)
		sim.request_length(sim.target_length)
	return not rope_clearance_blocked(sim.effective_anchor(),sim.pos,.045)

func shader(key: String, code: String) -> Shader:
	if not shaders.has(key):
		var result := Shader.new()
		result.code = code
		shaders[key] = result
	return shaders[key]

func mat(key: String, color: Color, unlit: bool = false) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = .93
	if unlit:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = result
	return result

func box(node_name: String, where: Vector3, dimensions: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var owner_node: Node3D = self if parent==null else parent
	owner_node.add_child(instance)
	instance.position = owner_node.to_local(where)
	return instance

# The run's contract cargo ({} when the generator places none).
func contract_info() -> Dictionary:
	return (layout as ExpeditionLayout).contract.duplicate() if layout is ExpeditionLayout else {}

func profile_at(height: float) -> GripBiomeProfile:
	return GripBiomeProfile.named(layout.profile_id_at(height))

# The act at a height ({} before v14) and a compact state for logs and tests.
func act_at(height: float) -> Dictionary:
	return layout.act_at(height)

func debug_state(point: Vector2, time: float = 0.0) -> Dictionary:
	var act := act_at(point.y)
	return {"location":location,"generation_version":generation_version,"layout":layout.get_script().get_global_name(),
		"level_id":act.get("level_id",""),"act_id":act.get("id",""),"act_index":act.get("index",-1),"act_name":act.get("display_name",""),
		"profile":layout.profile_id_at(point.y),"variant":act.get("variant",0),"hazards":hazards.debug_near(point,time)}

func build_anchor(object: Dictionary, chunk: Node3D) -> void:
	await visuals.build_anchor(object,chunk)
	# Every root carries its clock, whatever its lifetime: the timer is the
	# root's mechanic, so it must never break without a visible countdown.
	if GripSpec.timed(object) and is_instance_valid(object.get("visual")):
		_add_timer_dial(object)

# Contact after holding for `held` seconds (see GripSpec.contact_after).
func anchor_contact_after(object: Dictionary, contact: Vector2, held: float) -> Vector2:
	return GripSpec.contact_after(object,contact,held)

# Visible reaction of the held grip: a spring bends towards the load and a
# choice crystal lights its two exits. Purely visual.
func update_anchor_load(id: int, rope: Vector2, velocity: Vector2) -> void:
	var object := anchor_by_id(id)
	if object.is_empty(): return
	_light_status(object,true)
	var holder = object.get("visual")
	if GripSpec.kind_of(object)==GripSpec.SPRING and is_instance_valid(holder):
		var bend: Node3D = (holder as Node3D).get_node_or_null("Изгиб")
		if bend!=null:
			var pull := clampf(rope.normalized().x,-1,1) if rope.length_squared()>.01 else 0.0
			var charge := GripSpec.spring_load(object,velocity)
			# The stone block leans and settles a little; it never squashes flat.
			bend.rotation.z = lerpf(bend.rotation.z,-pull*.12,.25)
			bend.scale.y = lerpf(bend.scale.y,1.0-.14*charge,.25)
	for exit_id in GripSpec.choice_exits(object): _highlight_exit(int(exit_id),true)

func release_anchor_load(id: int) -> void:
	var object := anchor_by_id(id)
	if object.is_empty(): return
	_light_status(object,false)
	var holder = object.get("visual")
	if GripSpec.kind_of(object)==GripSpec.SPRING and is_instance_valid(holder):
		var bend: Node3D = (holder as Node3D).get_node_or_null("Изгиб")
		if bend!=null:
			var tween := create_tween()
			tween.tween_property(bend,"rotation:z",0.0,.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(bend,"scale:y",1.0,.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	for exit_id in GripSpec.choice_exits(object): _highlight_exit(int(exit_id),false)

# The status strip shows the grip state: the shared dim strip at rest, its
# own brighter copy while the grip is held, and the timer's alarm colour in a
# root's last moments. Returns the lit material while held.
func _light_status(object: Dictionary, held: bool) -> StandardMaterial3D:
	var holder = object.get("visual")
	var strip: MeshInstance3D = null
	if is_instance_valid(holder): strip = (holder as Node3D).find_child("Полоса состояния",true,false) as MeshInstance3D
	if not held or strip==null:
		if strip!=null and object.has("status_rest"): strip.material_override = object["status_rest"]
		object.erase("status_rest")
		object.erase("status_lit")
		return null
	# A rebuilt chunk brings back the shared material; light a fresh copy.
	if strip.material_override!=object.get("status_lit"):
		object["status_rest"] = strip.material_override
		# Held: the paint warms up a little; at rest it is plain paint.
		var lit := (strip.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		lit.emission_enabled = true
		lit.emission = profile_at(object["pos"].y).paint_color(GripSpec.kind_of(object))
		lit.emission_energy_multiplier = .35
		strip.material_override = lit
		object["status_lit"] = lit
	return object["status_lit"]

func _highlight_exit(id: int, on: bool) -> void:
	var object := anchor_by_id(id)
	if object.is_empty(): return
	object["choice_lit"] = on
	var holder = object.get("visual")
	if not is_instance_valid(holder): return
	var marker: Node3D = (holder as Node3D).get_node_or_null("Выход кристалла")
	if marker==null and on:
		marker = Node3D.new()
		marker.name = "Выход кристалла"
		holder.add_child(marker)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = maxf(.45,float(object["dimensions"].x)*.5)
		torus.outer_radius = torus.inner_radius+.08
		ring.mesh = torus
		ring.rotation.x = PI*.5
		# A temporary hint while the crystal is held, just off the exit's face.
		ring.position = Vector3(0,0,float((object.get("face_point",Vector3(0,0,.92)) as Vector3).z)+.03)
		# The way with the treasure shines gold.
		ring.material_override = mat("choice_exit_gold",Color("ffd27a"),true) if object.has("split") else mat("choice_exit",Color("bfe4ff"),true)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(ring)
	if marker!=null: marker.visible = on

const TIMER_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform float remaining = 1.0; uniform vec4 ring : source_color = vec4(1.0,.62,.32,1.0); uniform vec4 face : source_color = vec4(.12,.10,.09,1.0); uniform vec4 rim : source_color = vec4(.97,.93,.85,1.0); void fragment(){ vec2 p=UV*2.0-1.0; p.y=-p.y; float d=length(p); if(d>1.0) discard; float angle=fract(atan(p.x,p.y)/6.2831853+1.0); vec3 color=mix(face.rgb,face.rgb*1.12,smoothstep(.08,.58,d)); if(d>.58 && d<=.64) color=mix(face.rgb,ring.rgb,.35); if(d>.64) color=angle<=remaining?ring.rgb:mix(face.rgb,ring.rgb,.3); if(d>.9) color=rim.rgb; ALBEDO=color; }"

func _add_timer_dial(object: Dictionary) -> void:
	# The fragile grip carries its own clock: a full dial at rest that drains
	# clockwise while the hero hangs on it.
	var holder: Node3D = object["visual"]
	var material := ShaderMaterial.new()
	material.shader = shader("timer_dial",TIMER_SHADER)
	var style: Dictionary = profile_at(object["pos"].y).timer_style
	material.set_shader_parameter("ring",style["ring"])
	material.set_shader_parameter("face",style["face"])
	material.set_shader_parameter("rim",style["rim"])
	var dial := MeshInstance3D.new()
	dial.name = "Таймер опоры"
	var quad := QuadMesh.new()
	var size := clampf(float(object.get("dial_size",.56))*1.15,.42,.72)
	quad.size = Vector2(size,size)
	dial.mesh = quad
	dial.material_override = material
	dial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# On the block's front face, below the paint.
	var face: Vector3 = object.get("face_point",Vector3(0,-.04,1.05))
	dial.position = face
	holder.add_child(dial)
	var label := Label3D.new()
	label.name = "Секунды опоры"
	label.text = _timer_text(GripSpec.ROOT_SECONDS)
	label.font_size = 50
	label.outline_size = 12
	label.outline_modulate = style["face"]
	label.pixel_size = .0042*size/.56
	label.modulate = style["ring"]
	label.shaded = false
	label.double_sided = true
	label.position = face+Vector3(0,0,.024)
	holder.add_child(label)
	object["timer_dial"] = {"material":material,"label":label,"shown":-1.0}

static func _timer_text(seconds: float) -> String:
	return GripSpec.timer_text(seconds)

func update_anchor_timer(id: int, seconds_left: float) -> void:
	var object := anchor_by_id(id)
	var dial: Dictionary = object.get("timer_dial",{})
	if dial.is_empty() or not is_instance_valid(dial["label"]): return
	var shown := snappedf(clampf(seconds_left,0,GripSpec.ROOT_SECONDS),.05)
	if is_equal_approx(float(dial["shown"]),shown): return
	dial["shown"] = shown
	var material: ShaderMaterial = dial["material"]
	var style: Dictionary = profile_at(object["pos"].y).timer_style
	material.set_shader_parameter("remaining",shown/GripSpec.ROOT_SECONDS)
	material.set_shader_parameter("ring",(style["ring"] as Color).lerp(style["alarm"],clampf(1.0-shown/1.2,0,1)))
	(dial["label"] as Label3D).text = _timer_text(shown)
	# Pre-break state: past the warning the held root's strip turns to alarm.
	var lit := _light_status(object,true)
	if lit!=null:
		var alarm := clampf((GripSpec.ROOT_SECONDS-shown-GripSpec.ROOT_WARNING)/(GripSpec.ROOT_SECONDS-GripSpec.ROOT_WARNING),0,1)
		lit.emission = profile_at(object["pos"].y).paint_color(GripSpec.ROOT).lerp(style["alarm"],alarm)
		lit.albedo_color = Color.WHITE.lerp(style["alarm"],alarm*.6)
	# The root's cracks open up in the same colour.
	var cracks: StandardMaterial3D = object.get("crack_material")
	if cracks!=null:
		var breaking := clampf((GripSpec.ROOT_SECONDS-shown-GripSpec.ROOT_WARNING)/(GripSpec.ROOT_SECONDS-GripSpec.ROOT_WARNING),0,1)
		cracks.albedo_color = Color.WHITE.lerp(style["alarm"],breaking)
		cracks.emission_enabled = breaking>0
		cracks.emission = style["alarm"]
		cracks.emission_energy_multiplier = .6*breaking

func sphere(node_name: String, where: Vector3, dimensions: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 8
	mesh.rings = 4
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	(self if parent==null else parent).add_child(instance)
	instance.name = node_name
	instance.position = where if parent==null else parent.to_local(where)
	instance.scale = dimensions
	return instance

static func rectangle_hit(from: Vector2, to: Vector2, center: Vector2, half: Vector2) -> float:
	return RopeSim.hit_polygon(from,to,PackedVector2Array([center-half,center+Vector2(half.x,-half.y),center+half,center+Vector2(-half.x,half.y)]))

func hit_object(from: Vector2, to: Vector2, object: Dictionary, grip: float) -> float:
	var tolerance := .04+maxf(0,grip-.32)
	var center: Vector2 = object["pos"]
	var dimensions: Vector2 = object["dimensions"]
	if object.has("polygon"):
		var scale_value: Vector2 = Vector2.ONE+Vector2.ONE*tolerance*2/dimensions
		# Hook sweeps test every nearby grip each substep and forecast step:
		# reject the ones the segment never comes near before building the
		# expanded contour, which is then reused while the grip stays put.
		var cache: Dictionary = object.get("_hit",{})
		if cache.is_empty() or cache["pos"]!=center or cache["scale"]!=scale_value or cache["source"]!=object["polygon"]:
			var polygon := PackedVector2Array()
			var radius := 0.0
			var tilt := GripSpec.plate_tilt(object)
			for p in object["polygon"]:
				polygon.append((p*scale_value).rotated(tilt)+center)
				radius = maxf(radius,(p*scale_value).length())
			cache = {"pos":center,"scale":scale_value,"source":object["polygon"],"polygon":polygon,"radius":radius+.001}
			object["_hit"] = cache
		var reach: float = cache["radius"]
		if Geometry2D.get_closest_point_to_segment(center,from,to).distance_squared_to(center)>reach*reach: return -1.0
		return RopeSim.hit_polygon(from,to,cache["polygon"])
	var half := dimensions*.5+Vector2.ONE*tolerance
	if Geometry2D.get_closest_point_to_segment(center,from,to).distance_squared_to(center)>half.length_squared()+.001: return -1.0
	return rectangle_hit(from,to,center,half)

func cast_hook(from: Vector2, to: Vector2, grip: float, ignore_anchor: int = -1) -> Dictionary:
	var best := 2.0
	var result: Dictionary = {}
	var low := minf(from.y,to.y)
	var high := maxf(from.y,to.y)
	for object in nearby_anchors(low-2,high+2):
		# The bins are a whole section tall: skip grips far outside the window
		# by height before the exact test (forecasts run this ~240 times).
		var y: float = object["pos"].y
		var margin: float = 2.0+object["dimensions"].y*.5
		if y<low-margin or y>high+margin: continue
		if object["broken"] or int(object["id"])==ignore_anchor:
			continue
		var fraction := hit_object(from,to,object,grip)
		if fraction>=0 and fraction<best:
			best = fraction
			result = {"object":object,"fraction":fraction,"contact":from.lerp(to,fraction)}
	for obstacle in nearby_obstacles(minf(from.y,to.y),maxf(from.y,to.y)):
		var contact := SolidGeometry.contour_cast(from,to,obstacle,grip)
		var fraction: float = contact.get("fraction",-1.0)
		if fraction>=0 and fraction<=best:
			best = fraction
			result = {"blocked":true,"object":obstacle,"fraction":fraction,"contact":from.lerp(to,fraction),"normal":contact["normal"]}
	# The grip radius only decides whether a shot catches. The hook itself
	# rests on the drawn stone, never on the invisible assist margin.
	if not result.is_empty() and not result.get("blocked",false):
		result["contact"] = anchor_surface_point(result["object"],result["contact"],to-from)
	return result

func anchor_outline(object: Dictionary) -> PackedVector2Array:
	return GripSpec.outline(object)

# Moves a point onto the visible grip surface (see GripSpec.surface_point).
func anchor_surface_point(object: Dictionary, point: Vector2, direction: Vector2 = Vector2.ZERO) -> Vector2:
	return GripSpec.surface_point(object,point,direction)

func move_player(from: Vector2, to: Vector2, velocity: Vector2) -> Dictionary:
	var position_value := from
	var remaining := to-from
	var grounded := false
	var rest := false
	var impact := 0.0
	var contacts: Array[Vector2] = []
	# Convex sweeps use the actual drawn contour expanded by body size.
	# Resolve the remaining motion along each face; never discard the whole
	# frame after a collision or reflect velocity into another solid.
	for iteration in range(6):
		var best: Dictionary = {}
		for obstacle in nearby_obstacles(minf(position_value.y,position_value.y+remaining.y)-1,maxf(position_value.y,position_value.y+remaining.y)+1):
			var hit := SolidGeometry.cast(position_value,position_value+remaining,obstacle,SolidGeometry.BODY_HALF,true)
			if not hit.is_empty() and (best.is_empty() or hit["fraction"]<best["fraction"]):
				best = hit
		if remaining.y<-.000001:
			for ledge in ledges:
				# A collapsed sand bridge no longer carries the hero.
				if ledge.get("collapsed",false): continue
				var top: float = ledge["top"]+SolidGeometry.BODY_HALF.y
				if position_value.y<top-.004: continue
				var fraction := (top-position_value.y)/remaining.y
				if fraction<-.001 or fraction>1: continue
				var x := position_value.x+remaining.x*maxf(0,fraction)
				if x<float(ledge["left"])-.24 or x>float(ledge["right"])+.24: continue
				if best.is_empty() or fraction<best["fraction"]:
					best = {"fraction":maxf(0,fraction),"normal":Vector2(0,1),"depth":0.0,"object":{"rest":true}}
		if best.is_empty():
			position_value += remaining
			break
		var normal: Vector2 = best["normal"]
		var fraction: float = best["fraction"]
		position_value += remaining*fraction+normal*(float(best["depth"])+.0001)
		remaining *= 1-fraction
		remaining -= normal*minf(0,remaining.dot(normal))
		impact = maxf(impact,-velocity.dot(normal))
		velocity -= normal*minf(0,velocity.dot(normal))
		contacts.append(normal)
		if normal.y>.6:
			grounded = true
			rest = bool(best["object"].get("rest",false))
	return {"position":position_value,"velocity":velocity,"grounded":grounded,"rest":rest,"impact":impact,"contacts":contacts}

func _build_find(find: Dictionary, parent: Node3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var point: Vector2 = find["pos"]
	# Finds stand well in front of deep stone, so the hero never passes behind
	# them; the pedestal reaches back to the wall through the same mount.
	var mount := visuals.mount_find(find)
	# A streamed section takes a find in three short steps.
	if not await build_pause(parent): return
	var wall_z := mount.wall_z()
	holder.position = mount.holder_position()
	holder.scale = Vector3.ONE*FIND_SCALE
	find["visual"] = holder
	find["mount"] = mount
	# Contact offsets are in holder space; the holder is uniformly scaled.
	var treasure := LootVisuals.build(self,find,holder,visual_quality,(wall_z-holder.position.z)/holder.scale.x)
	if not await build_pause(parent):
		find["visual"] = null
		return
	var price := LootVisuals.price_tag(self,treasure,find["item"],visual_quality!="battery")
	price.visible = show_loot_prices
	find["price_visual"] = price
	holder.visible = not find.get("picked",false)

# Treasure models are authored about half a metre tall; this brings them to
# their size on the face next to the hero and the grips.
const FIND_SCALE := 1.1

# The pickup in the world: a copy of the find's model hops, spins and shrinks
# away while its holder hides at once (a restored snapshot can show the
# holder again, untouched).
func collect_find(find: Dictionary) -> void:
	var holder = find.get("visual")
	if not is_instance_valid(holder) or not (holder as Node3D).visible: return
	var treasure := (holder as Node3D).get_node_or_null("Сокровище") as Node3D
	if treasure==null: return
	var ghost := treasure.duplicate() as Node3D
	ghost.name = "Подбор сокровища"
	(holder as Node3D).get_parent().add_child(ghost)
	ghost.transform = (holder as Node3D).transform*treasure.transform
	var player := ghost.get_node("Анимация") as AnimationPlayer
	player.play("collect")
	player.animation_finished.connect(func(_name: StringName) -> void: ghost.queue_free())

const PRICE_NEAR := 3.2
const PRICE_AIM := 1.6

func update_loot_prices(playing: bool, always: bool, hero: Vector2, aim: Vector2) -> void:
	show_loot_prices = playing and always
	for find in finds:
		var price = find.get("price_visual")
		if not is_instance_valid(price): continue
		var point: Vector2 = find["pos"]
		var near := hero.distance_to(point)<PRICE_NEAR
		var aimed := aim.is_finite() and Geometry2D.get_closest_point_to_segment(point,hero,aim).distance_to(point)<PRICE_AIM
		price.visible = playing and (always or near or aimed)

func set_loot_prices_visible(show_prices: bool) -> void:
	show_loot_prices = show_prices
	for find in finds:
		if is_instance_valid(find.get("price_visual")):
			find["price_visual"].visible = show_prices

func _build_sky() -> void:
	sky_backdrop = ProceduralSkyBackdrop.new()
	add_child(sky_backdrop)
	sky_backdrop.setup(seed_value, false, location)
	sky_backdrop.set_quality(_sky_detail())
	sky_backdrop.set_view(camera_center)

func _release_chunk(key: int) -> void:
	for object in nearby_anchors(key*24,(key+1)*24-.001):
		if int(floor(object["pos"].y/24))==key: object["visual"] = null
	for object in obstacles:
		if int(floor(object["pos"].y/24))==key: object["visual"] = null
	for object in finds:
		if int(floor(object["pos"].y/24))==key: object["visual"] = null
	for object in ledges:
		if int(floor(float(object["top"])/24))==key: object["visual"] = null
	var chunk: Node3D = chunks[key]
	if key==build_job_key: build_job_cancelled = true
	remove_child(chunk)
	chunk.queue_free()
	chunks.erase(key)
	if not layout.finite and key < int(floor((camera_center.y-32.0)/24.0)):
		var min_y := float((key+1)*24)
		finds = finds.filter(func(f: Dictionary) -> bool: return f["pos"].y>=min_y)
		obstacles = obstacles.filter(func(o: Dictionary) -> bool: return o["pos"].y>=min_y)
		ledges = ledges.filter(func(l: Dictionary) -> bool: return float(l.get("top",0.0))>=min_y)

func update_visibility(center_y: float, center_x: float = 0, build_budget: int = -1) -> void:
	camera_center = Vector2(center_x,center_y)
	if is_instance_valid(sky_backdrop): sky_backdrop.set_view(camera_center)
	if not visuals_enabled: return
	if build_job_parent_id!=0: build_tick.emit()
	var moved := stream_center==Vector2.INF or stream_center.distance_to(camera_center)>=STREAM_MOVE_THRESHOLD
	if not moved and not stream_pending and not stream_dirty:
		# Keep parallax transforms smooth even while mesh streaming is idle.
		_update_far_layers(build_budget<0)
		_update_dynamic_visibility(center_y)
		return
	var stream_was_dirty := stream_dirty
	stream_center = camera_center
	stream_dirty = false
	var far_pending := _update_far_layers(build_budget<0)
	var first := maxi(0,int(floor((center_y-32)/24)))
	var ready_chunk := _ready_chunk()
	var last := mini(ready_chunk,int(floor((center_y+32)/24)))
	for key in chunks.keys():
		if key<first or key>last: _release_chunk(key)
	var missing_keys: Array[int] = []
	for key in range(first,last+1):
		if not chunks.has(key): missing_keys.append(key)
	# Building the closest section first keeps the current view populated while
	# spreading the expensive mesh/decor work over later frames. Its own rock
	# bands come before it, and both before bands only farther sections need.
	var band_to_warm := _band_to_warm(center_y,ready_chunk,missing_keys) if build_budget>=0 else NO_BAND
	if band_to_warm!=NO_BAND and build_job_parent_id==0: _start_band_job(band_to_warm)
	var effective_budget := MAX_CHUNK_BUILDS_PER_UPDATE if build_budget<0 else maxi(0,build_budget)
	if build_budget<0: effective_budget = missing_keys.size()
	for pass_index in range(effective_budget):
		if missing_keys.is_empty(): break
		var closest_index := 0
		var closest_distance := absf(float(missing_keys[0])-center_y/24.0)
		for index in range(1,missing_keys.size()):
			var distance := absf(float(missing_keys[index])-center_y/24.0)
			if distance<closest_distance:
				closest_index = index
				closest_distance = distance
		var key: int = missing_keys[closest_index]
		if build_budget>=0:
			# Streaming: one job at a time, spread over frames. The rock bands a
			# section and the nearby hazards read come first, so neither
			# generates them in one go.
			if build_job_parent_id!=0 or band_to_warm!=NO_BAND: break
			missing_keys.remove_at(closest_index)
			_start_chunk_job(key)
			continue
		missing_keys.remove_at(closest_index)
		_build_chunk(key)
	if hazard_visuals!=null and (moved or stream_was_dirty or hazards_pending) and band_to_warm==NO_BAND:
		hazards_pending = hazard_visuals.build_near(center_y,1 if build_budget>=0 else -1)
	stream_pending = not missing_keys.is_empty() or far_pending or build_job_parent_id!=0 or hazards_pending or band_to_warm!=NO_BAND
	_update_dynamic_visibility(center_y)

# A section is complete once built and not still streaming in.
func chunk_complete(key: int) -> bool:
	return chunks.has(key) and key!=build_job_key

# The highest section the generator has passed: a massif reads the objects
# of its neighbours, so a section is built only once they exist.
func _ready_chunk() -> int:
	var ready_chunk := int(floor((layout.main_point(layout.row).y-2)/24))-1
	var legacy := layout is LegacyMountainLayout
	if legacy: ready_chunk = int(floor((generated_height-2)/24))-1
	if layout.finite and (layout.summit_added or (not legacy and layout.main_point(layout.row).y>=layout.summit-.8)):
		ready_chunk = int(floor(layout.summit/24))
	return ready_chunk

# Everything inside the view, built now: a paused job is finished in one go,
# missing sections and nearby hazards are built directly. Streaming then
# carries on with what lies beyond. On a prepared world this costs nothing.
func complete_view(center_y: float, center_x: float, half_height: float) -> void:
	if not visuals_enabled: return
	camera_center = Vector2(center_x,center_y)
	if build_job_parent_id!=0:
		build_rush = true
		build_tick.emit()
		build_rush = false
	var first := maxi(0,int(floor((center_y-half_height)/24)))
	var last := mini(_ready_chunk(),int(floor((center_y+half_height)/24)))
	for key in range(first,last+1):
		if not chunks.has(key): _build_chunk(key)
	if hazard_visuals!=null: hazards_pending = hazard_visuals.build_near(center_y,-1,half_height+4)
	stream_dirty = true

func _build_chunk(key: int) -> void:
	var chunk := Node3D.new()
	chunk.name = "Участок_%d" % key
	add_child(chunk)
	chunks[key] = chunk
	var baked := _baked_chunk_path(key)
	if baked.is_empty(): visuals.build_chunk(key,chunk)
	else: _attach_baked(key,chunk,load(baked) as PackedScene)
	_build_chunk_objects(key,chunk)

func _start_chunk_job(key: int) -> void:
	var chunk := Node3D.new()
	chunk.name = "Участок_%d" % key
	add_child(chunk)
	chunks[key] = chunk
	build_job_key = key
	build_job_parent_id = chunk.get_instance_id()
	build_job_cancelled = false
	build_deadline = Time.get_ticks_usec()+_build_slice()
	_run_chunk_job(key,chunk)

# The closest rock band that sections or hazards in reach will read and that
# is not generated yet; NO_BAND when all are ready.
func _band_to_warm(center_y: float, ready_chunk: int, missing_keys: Array[int] = []) -> int:
	if not visuals is MassifVisuals: return NO_BAND
	var massif := visuals as MassifVisuals
	if not missing_keys.is_empty():
		var closest: int = missing_keys[0]
		for key in missing_keys:
			if absf(key*24+12-center_y)<absf(closest*24+12-center_y): closest = key
		# Masses reach past their band, so queries at a section's edges read
		# two bands either side.
		for band in [closest,closest-1,closest+1,closest+2,closest-2]:
			if band>=-1 and band<=ready_chunk+2 and not massif.band_ready(band): return band
		# The closest section can be built now; farther bands wait for it.
		return NO_BAND
	var low := maxi(-1,int(floor((center_y-40)/24))-1)
	var high := mini(int(floor((center_y+40)/24))+2,ready_chunk+2)
	var best := NO_BAND
	for band in range(low,high+1):
		if massif.band_ready(band): continue
		if best==NO_BAND or absf(band*24+12-center_y)<absf(best*24+12-center_y): best = band
	return best

func _start_band_job(band: int) -> void:
	build_job_band = band
	build_job_parent_id = band_job_token.get_instance_id()
	build_job_cancelled = false
	build_deadline = Time.get_ticks_usec()+_build_slice()
	_run_band_job(band)

func _run_band_job(band: int) -> void:
	await (visuals as MassifVisuals).warm_band(band,band_job_token)
	build_job_band = NO_BAND
	build_job_parent_id = 0
	build_deadline = 0
	stream_dirty = true

func _run_chunk_job(key: int, chunk: Node3D) -> void:
	var baked := _baked_chunk_path(key)
	if baked.is_empty(): await visuals.build_chunk(key,chunk)
	else:
		# The scene file is read on a worker thread; the job waits for it
		# frame by frame and only instances it here.
		ResourceLoader.load_threaded_request(baked)
		while ResourceLoader.load_threaded_get_status(baked)==ResourceLoader.THREAD_LOAD_IN_PROGRESS and not build_rush:
			build_deadline = 0
			if not await build_pause(chunk): break
		var scene := ResourceLoader.load_threaded_get(baked) as PackedScene
		if not build_job_cancelled and is_instance_valid(chunk):
			if scene!=null: _attach_baked(key,chunk,scene)
			else: await visuals.build_chunk(key,chunk)
	if not build_job_cancelled: await _build_chunk_objects(key,chunk)
	build_job_key = -1
	build_job_parent_id = 0
	build_deadline = 0
	# Look again next frame: the next section may be waiting.
	stream_dirty = true

func _build_slice() -> int:
	if not build_urgency: return BUILD_SLICE_USEC
	# A band feeds the sections next to it, so it is due one band earlier.
	var urgent := BUILD_URGENT_DISTANCE
	var low := build_job_key*24.0
	if build_job_band!=NO_BAND:
		low = build_job_band*24.0
		urgent += 24.0
	elif build_job_key<0: return BUILD_SLICE_USEC
	var gap := absf(camera_center.y-clampf(camera_center.y,low,low+24.0))
	return BUILD_URGENT_SLICE_USEC if gap<urgent else BUILD_SLICE_USEC

# Called by builders between pieces. Synchronous builds return at once; the
# streamed section yields to the next frame when its slice is spent and stops
# (false) once the section was unloaded meanwhile.
func build_pause(owner) -> bool:
	# Untyped: a cancelled section's node may already be freed here.
	if typeof(owner)==TYPE_NIL: return true
	if not is_instance_valid(owner): return false
	if owner.get_instance_id()!=build_job_parent_id: return true
	if build_job_cancelled: return false
	if build_rush or Time.get_ticks_usec()<build_deadline: return true
	await build_tick
	if build_job_cancelled: return false
	build_deadline = Time.get_ticks_usec()+_build_slice()
	return true

func _build_chunk_objects(key: int, chunk: Node3D) -> void:
	for object in nearby_anchors(key*24,(key+1)*24-.001):
		if int(floor(object["pos"].y/24))!=key: continue
		if not await build_pause(chunk): return
		await build_anchor(object,chunk)
	for object in obstacles:
		if int(floor(object["pos"].y/24))!=key: continue
		if not await build_pause(chunk): return
		visuals.build_obstacle(object,chunk)
	for object in ledges:
		if int(floor(object["top"]/24))!=key: continue
		if not await build_pause(chunk): return
		visuals.build_ledge(object,chunk)
	for find in finds:
		if int(floor(find["pos"].y/24))!=key: continue
		if not await build_pause(chunk): return
		await _build_find(find,chunk)
	if layout.summit_added and int(floor(layout.summit/24))==key:
		var p: Vector2 = anchors[main_route[-1]]["pos"]
		# The summit flag: a tall mast with the expedition's hook on its cloth.
		FloraModels.flag(chunk,"mast_high","yellow",Vector3(p.x+.8,layout.summit,2),3.0,1.0,visual_quality!="battery","hook")

func _update_dynamic_visibility(center_y: float) -> void:
	for object in nearby_anchors(center_y-40,center_y+40):
		if is_instance_valid(object.get("visual")): object["visual"].visible = not object["broken"]
	for find in finds:
		if is_instance_valid(find.get("visual")): find["visual"].visible = not find.get("picked",false)
func _update_far_layers(build_all: bool = false) -> bool:
	# Distant cliffs live in their own parallax space: each layer follows a
	# share of the camera motion, so it drifts slower than the climbing face.
	if not visuals is MassifVisuals: return false
	var massif := visuals as MassifVisuals
	var built_count := 0
	var pending := false
	var far_budget := 999999 if build_all else MAX_FAR_BAND_BUILDS_PER_UPDATE
	for far in range(1,MassifVisuals.FAR_LAYERS.size()+1):
		var settings: Dictionary = MassifVisuals.FAR_LAYERS[far-1]
		if far_layers.size()<far:
			var node := Node3D.new()
			node.name = "Дальний слой_%d" % far
			add_child(node)
			far_layers.append(node)
		var holder := far_layers[far-1]
		var follow: float = settings["follow"]
		holder.position = Vector3(camera_center.x*follow,camera_center.y*follow,settings["z"])
		holder.visible = far<=massif.far_layer_count()
		var view := camera_center.y*(1.0-follow)
		var first := int(floor((view-20)/24))
		var last := int(floor((view+20)/24))
		for key in far_bands.keys():
			if key.x==far and (key.y<first or key.y>last or not holder.visible):
				far_bands[key].queue_free()
				far_bands.erase(key)
		if not holder.visible: continue
		for band in range(first,last+1):
			var key := Vector2i(far,band)
			if far_bands.has(key): continue
			if built_count>=far_budget:
				pending = true
				continue
			var node := Node3D.new()
			node.name = "Дальние скалы_%d" % band
			holder.add_child(node)
			far_bands[key] = node
			massif.build_far_band(far,band,node)
			built_count += 1
	return pending

func anchor_by_id(id: int) -> Dictionary:
	return anchors[id] if id>=0 and id<anchors.size() else {}

func revive_plan(safe_id: int, safe_pos: Vector2, maximum: float, contact: Vector2 = Vector2.INF) -> Dictionary:
	var safe := anchor_by_id(safe_id)
	if safe_id>=0 and (safe.is_empty() or safe["broken"] or not safe.get("permanent",false)):
		return {"available":false,"anchors":[]}
	var previous: Vector2 = safe["pos"] if safe_id>=0 else safe_pos
	if safe_id>=0 and contact.is_finite(): previous = contact
	var reserves: Array[int] = []
	var exits := 0
	for id in main_route:
		var object := anchor_by_id(id)
		if object["pos"].y<=previous.y+.01: continue
		var target: Vector2 = object["pos"]
		if object["broken"]:
			if not layout.rescue_anchors.has(id): return {"available":false,"anchors":[]}
			var reserve_id: int = layout.rescue_anchors[id]
			target = anchors[reserve_id]["pos"]
			reserves.append(reserve_id)
			exits = 0
		else:
			exits += 1
		if previous.distance_to(target)>maximum or not layout.transition_clear(previous,target):
			return {"available":false,"anchors":[]}
		previous = target
	return {"available":exits>0,"anchors":reserves}

func activate_rescue_anchors(ids: Array) -> void:
	for id in ids:
		var object := anchor_by_id(int(id))
		if not object.get("reserve",false): continue
		object["broken"] = false
		GripSpec.restore(object,false)
		if is_instance_valid(object.get("visual")): object["visual"].visible = true

# Release of a held grip: a disposable grip is consumed once, a permanent one
# becomes available again. Returns true when the grip was consumed now.
func consume_anchor(id: int) -> bool:
	var object := anchor_by_id(id)
	if not GripSpec.settle(object): return false
	_crumble(object)
	return true

# A root whose clock ran out breaks whatever its lifetime.
func break_anchor(id: int) -> bool:
	var object := anchor_by_id(id)
	if not GripSpec.expire(object): return false
	_crumble(object)
	return true

func _crumble(object: Dictionary) -> void:
	if is_instance_valid(object.get("visual")):
		object["visual"].visible = false
		if visuals_enabled:
			var p: Vector2 = object["pos"]
			# The whole holder goes: shell, socket, skirt and contact shade. The
			# chips fall from the grip's own depth, not from a fixed plane.
			var mount: SurfaceMount = object.get("mount")
			var z := mount.holder_position().z+.3 if mount!=null else 2.5
			for index in range(4):
				var crumb := profile_at(p.y).material_color(GripSpec.kind_of(object))
				var chip := box("Осколок",Vector3(p.x+(index-1.5)*.22,p.y,z),Vector3(.16,.13,.15),mat("crumb_%s" % crumb.to_html(),crumb))
				var tween := create_tween().set_parallel(true)
				tween.tween_property(chip,"position",chip.position+Vector3((index-1.5)*.35,-1.4,0),.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tween.tween_property(chip,"scale",Vector3.ZERO,.36)
				tween.chain().tween_callback(chip.queue_free)

# Ice shavings falling from the hook while it runs down a plate.
const ICE_SHAVING_SECONDS := .07
var ice_shaving_clock := 0.0

func ice_scrape(contact: Vector2, delta: float) -> void:
	ice_shaving_clock -= delta
	if ice_shaving_clock>0 or not visuals_enabled: return
	ice_shaving_clock = ICE_SHAVING_SECONDS
	var color := profile_at(contact.y).material_color(GripSpec.ICE).lightened(.3)
	var chip := box("Ледяная крошка",Vector3(contact.x,contact.y,HERO_PLANE_Z),Vector3(.13,.13,.08),mat("ice_shaving_%s" % color.to_html(),color))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(chip,"position",chip.position+Vector3(0,-1.0,0),.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(chip,"scale",Vector3.ZERO,.34)
	tween.chain().tween_callback(chip.queue_free)

# The throw of a spring: sparks of its paint leave the grip along the exit, and
# a shorter spray falls away behind the hero.
const HERO_PLANE_Z := 3.2

func spring_burst(id: int, hero: Vector2) -> void:
	var object := anchor_by_id(id)
	if object.is_empty() or not visuals_enabled: return
	var exit := GripSpec.exit_direction(object)
	var across := exit.orthogonal()
	var p: Vector2 = object["pos"]
	var mount: SurfaceMount = object.get("mount")
	var z := mount.holder_position().z+.5 if mount!=null else 2.5
	var color := profile_at(p.y).paint_color(GripSpec.SPRING)
	var spark := mat("throw_spark_%s" % color.to_html(),color)
	var burst := Node3D.new()
	burst.name = "Вспышка броска"
	add_child(burst)
	var tween := create_tween().set_parallel(true)
	for index in range(14):
		var from_grip := index<8
		var spread := (index%4-1.5)*(.42 if from_grip else .3)
		var origin := Vector3(p.x,p.y,z) if from_grip else Vector3(hero.x,hero.y,HERO_PLANE_Z)
		var flight := exit*(2.4+(index%3)*.7)+across*spread if from_grip else -exit*(1.1+(index%3)*.4)+across*spread
		var chip := box("Искра броска",origin,Vector3(.2,.2,.12),spark,burst)
		tween.tween_property(chip,"position",origin+Vector3(flight.x,flight.y,0),.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chip,"scale",Vector3.ZERO,.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(burst.queue_free)

# --- Act hazards (v14) ------------------------------------------------------------

# One physics step of the act hazards: drift, a knock and one-time collapses.
func step_hazards(time: float, hero: Vector2, grounded: bool, held_anchor: int = -1, last_anchor: int = -1) -> Dictionary:
	var result: Dictionary = hazards.step(time,hero,grounded,held_anchor,last_anchor)
	for id in result["collapsed"]: _collapse_bridge(int(id))
	if hazard_visuals!=null: hazard_visuals.update(time,hero,float(result["haze"]),camera_center)
	return result

func _collapse_bridge(id: int) -> void:
	var hazard: Dictionary = layout.hazards[id]
	var ledge: Dictionary = ledges[int(hazard["ledge"])]
	ledge["collapsed"] = true
	if hazard_visuals!=null: hazard_visuals.collapse(hazard)
	# The revealed grip becomes the new way on.
	var exit := anchor_by_id(int(hazard["reveal"]))
	if exit.is_empty(): return
	exit["broken"] = false
	exit["hidden"] = false
	GripSpec.restore(exit,false)
	if is_instance_valid(exit.get("visual")): exit["visual"].visible = true

func restore_hazards(collapsed: Array) -> void:
	hazards.restore_collapsed(collapsed)
	for id in collapsed:
		if int(id)<0 or int(id)>=layout.hazards.size(): continue
		var hazard: Dictionary = layout.hazards[int(id)]
		if hazard["kind"]!="collapse": continue
		var reveal := anchor_by_id(int(hazard.get("reveal",-1)))
		if not reveal.is_empty():
			reveal["broken"] = false
			reveal["hidden"] = false
			GripSpec.restore(reveal,false)
			if is_instance_valid(reveal.get("visual")): reveal["visual"].visible = true
		ledges[int(hazard["ledge"])]["collapsed"] = true
		if hazard_visuals!=null: hazard_visuals.collapse(hazard,false)

func object_description(object: Dictionary) -> String:
	# Type and lifetime are separate words: a permanent ice grip still reads as ice.
	return GripSpec.description(object,profile_at(object["pos"].y))

func _make_glow_texture() -> void:
	var image := Image.create(48,48,false,Image.FORMAT_RGBA8)
	for x in range(48):
		for y in range(48):
			var distance := Vector2(x-23.5,y-23.5).length()/24
			image.set_pixel(x,y,Color(1,1,1,pow(maxf(0,1-distance),2)*.6))
	ghost_texture = ImageTexture.create_from_image(image)
