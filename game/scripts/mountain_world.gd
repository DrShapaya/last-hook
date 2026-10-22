class_name MountainWorld
extends Node3D

const GENERATION_VERSION := 15
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

# Every location slot starts new attempts on the expedition generator (v15:
# v14 geometry with role-based finds, coins and contracts). Saved attempts keep
# their own: v14 anywhere, v6-v13 on the first location, v4 elsewhere.
static func generation_version_for(_biome: int) -> int:
	return GENERATION_VERSION

static func resumable(version: int, biome: int) -> bool:
	if version in [14,GENERATION_VERSION]: return true
	return version in [6,7,8,9,10,11,12,13] if biome==0 else version==4

func setup(world_seed: int, world_location: int, saved_version: int = 0, practice: bool = false) -> void:
	seed_value = world_seed
	location = world_location
	generation_version = saved_version if saved_version>0 else generation_version_for(location)
	if generation_version>=10 and location==0: layout = EncounterLayout.new()
	if generation_version>=11 and location==0: layout = MassifLayout.new()
	# v14: acts of the level decide route, silhouette, profile and hazards.
	if generation_version>=14: layout = ExpeditionLayout.new()
	if practice: layout = PracticeLayout.new()
	# v15 changes only the finds layer; v14 geometry and hazards are kept.
	if layout is ExpeditionLayout: layout.economy_loot = generation_version>=15
	layout.gentle_intro = generation_version>=7
	layout.sparse_route = generation_version>=8
	layout.safe_routes = generation_version>=9
	# v12 assigns grip types from the movement phrase's scenario.
	layout.scenario_routes = generation_version>=12
	# v13 calibrates the type mix and slides ice across its grip.
	layout.calibrated_routes = generation_version>=13
	# Only a saved v4 attempt still regenerates on the old generator.
	if location!=0 and generation_version<14 and not practice: layout = LegacyMountainLayout.new()
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
	if visuals!=null and visuals.has_method("set_quality"):
		visuals.set_quality(visual_quality)
	# Decor density, loot glints and shadow casters are baked per chunk.
	if changed and visuals_enabled and not chunks.is_empty():
		for key in chunks.keys(): _release_chunk(key)
		update_visibility(camera_center.y,camera_center.x)

func seeded_rng(index: int, stream: int) -> RandomNumberGenerator:
	return layout.rng(index,stream)

func cliff_edge(index: int, side: int) -> float:
	return layout.outer_edge(index*4.0,side)

func outside_mountain(point: Vector2) -> bool:
	return layout.outside(point)

func generate_to(height: float, finite: bool, summit: float = 120) -> void:
	var target := minf(height,summit+6) if finite else height
	layout.generate_to(target,finite,summit)
	route_edges = layout.edges
	generated_height = maxf(generated_height,target)
	# The top chunk changes when the summit is added; refresh it if loaded.
	if layout.summit_added:
		var key := int(floor(summit/24))
		if chunks.has(key): _release_chunk(key)
	if visuals_enabled: update_visibility(camera_center.y,camera_center.x)

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
	visuals.build_anchor(object,chunk)
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
			bend.rotation.z = lerpf(bend.rotation.z,-pull*.07,.25)
			bend.scale.y = lerpf(bend.scale.y,1.0-.06*charge,.25)
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
		ring.material_override = mat("choice_exit",Color("bfe4ff"),true)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(ring)
	if marker!=null: marker.visible = on

const TIMER_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, shadows_disabled; uniform float remaining = 1.0; uniform vec4 ring : source_color = vec4(1.0,.62,.32,1.0); uniform vec4 face : source_color = vec4(.12,.10,.09,1.0); uniform vec4 rim : source_color = vec4(.97,.93,.85,1.0); void fragment(){ vec2 p=UV*2.0-1.0; p.y=-p.y; float d=length(p); if(d>1.0) discard; float angle=fract(atan(p.x,p.y)/6.2831853+1.0); vec3 color=face.rgb; if(d>.64) color=angle<=remaining?ring.rgb:mix(face.rgb,ring.rgb,.3); if(d>.9) color=rim.rgb; ALBEDO=color; }"

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
	var size := float(object.get("dial_size",.56))
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
	label.font_size = 56
	label.outline_size = 0
	label.pixel_size = .0042*size/.56
	label.modulate = Color("fff4e2")
	label.shaded = false
	label.double_sided = true
	label.position = face+Vector3(0,0,.02)
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
	if object.has("polygon"):
		var polygon := PackedVector2Array()
		var scale_value: Vector2 = Vector2.ONE+Vector2.ONE*tolerance*2/object["dimensions"]
		for p in object["polygon"]: polygon.append(p*scale_value+object["pos"])
		return RopeSim.hit_polygon(from,to,polygon)
	return rectangle_hit(from,to,object["pos"],object["dimensions"]*.5+Vector2.ONE*tolerance)

func cast_hook(from: Vector2, to: Vector2, grip: float, ignore_anchor: int = -1) -> Dictionary:
	var best := 2.0
	var result: Dictionary = {}
	for object in nearby_anchors(minf(from.y,to.y)-2,maxf(from.y,to.y)+2):
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
	var wall_z := mount.wall_z()
	holder.position = mount.holder_position()
	holder.scale = Vector3.ONE*1.22
	find["visual"] = holder
	find["mount"] = mount
	# Contact offsets are in holder space; the holder is uniformly scaled.
	LootVisuals.build(self,find,holder,visual_quality,(wall_z-holder.position.z)/holder.scale.x)
	var price := Label3D.new()
	price.text = str(find["item"]["value"])
	price.font_size = 30
	price.pixel_size = .011
	price.outline_size = 10
	price.modulate = Color("fff1c4")
	price.outline_modulate = Color("1d3330dd")
	price.shaded = false
	price.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(price)
	price.position = Vector3(0,.62,.3)
	price.visible = show_loot_prices
	find["price_visual"] = price
	holder.visible = not find.get("picked",false)

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
	# A flat two-colour gradient on every platform. The volumetric cloud
	# shader is no longer used in game: a few Android GPUs abort while
	# compiling its nested noise loops.
	sky_backdrop = ProceduralSkyBackdrop.new()
	add_child(sky_backdrop)
	sky_backdrop.setup(seed_value)
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
	remove_child(chunk)
	chunk.queue_free()
	chunks.erase(key)

func update_visibility(center_y: float, center_x: float = 0) -> void:
	camera_center = Vector2(center_x,center_y)
	if is_instance_valid(sky_backdrop): sky_backdrop.set_view(camera_center)
	if not visuals_enabled: return
	_update_far_layers()
	var first := maxi(0,int(floor((center_y-32)/24)))
	var ready_chunk := int(floor((layout.main_point(layout.row).y-2)/24))-1
	# The massif of a chunk reads the objects of its neighbours, so a chunk is
	# built only once the generator has passed it.
	var legacy := layout is LegacyMountainLayout
	if legacy: ready_chunk = int(floor((generated_height-2)/24))-1
	if layout.finite and (layout.summit_added or (not legacy and layout.main_point(layout.row).y>=layout.summit-.8)):
		ready_chunk = int(floor(layout.summit/24))
	var last := mini(ready_chunk,int(floor((center_y+32)/24)))
	for key in chunks.keys():
		if key<first or key>last: _release_chunk(key)
	for key in range(first,last+1):
		if chunks.has(key): continue
		var chunk := Node3D.new()
		chunk.name = "Участок_%d" % key
		add_child(chunk)
		chunks[key] = chunk
		visuals.build_chunk(key,chunk)
		for object in nearby_anchors(key*24,(key+1)*24-.001):
			if int(floor(object["pos"].y/24))==key: build_anchor(object,chunk)
		for object in obstacles:
			if int(floor(object["pos"].y/24))==key: visuals.build_obstacle(object,chunk)
		for object in ledges:
			if int(floor(object["top"]/24))==key: visuals.build_ledge(object,chunk)
		for find in finds:
			if int(floor(find["pos"].y/24))==key: _build_find(find,chunk)
		if layout.summit_added and int(floor(layout.summit/24))==key:
			var p: Vector2 = anchors[main_route[-1]]["pos"]
			box("Флагшток",Vector3(p.x+.8,layout.summit+1,2),Vector3(.08,2,.1),mat("flagpole",Color("d8d8c3")),chunk)
			box("Флаг",Vector3(p.x+1.2,layout.summit+1.7,2),Vector3(.8,.5,.1),mat("flag",Color("e6b64b")),chunk)
	for object in nearby_anchors(center_y-40,center_y+40):
		if is_instance_valid(object.get("visual")): object["visual"].visible = not object["broken"]
	if hazard_visuals!=null: hazard_visuals.build_near(center_y)
	for find in finds:
		if is_instance_valid(find.get("visual")): find["visual"].visible = not find.get("picked",false)
func _update_far_layers() -> void:
	# Distant cliffs live in their own parallax space: each layer follows a
	# share of the camera motion, so it drifts slower than the climbing face.
	if not visuals is MassifVisuals: return
	var massif := visuals as MassifVisuals
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
			var node := Node3D.new()
			node.name = "Дальние скалы_%d" % band
			holder.add_child(node)
			far_bands[key] = node
			massif.build_far_band(far,band,node)

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
