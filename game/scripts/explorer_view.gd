class_name ExplorerView
extends Node3D

const ART := "res://assets/art/modular-pack-v1/"
const HOOK_EYE := Vector3(0,-.7072,0)
var body: ExplorerRig
var rope: MeshInstance3D
var rope_outer: MeshInstance3D
var rope_secondary: MeshInstance3D
var rope_outer_secondary: MeshInstance3D
var bolt: Node3D
var bolt_secondary: Node3D
var prongs: Array[MeshInstance3D] = []
var tip_count := 0
var hook_count := 1
var rope_material: StandardMaterial3D
var contact_glow: Sprite3D
var was_attached := false
var catch_time := -10.0
var rope_start := Vector3.ZERO
var rope_end := Vector3.ZERO
var trail_mesh: MeshInstance3D
var impact_mesh: MeshInstance3D
var last_shot := -1
var last_impact := -1
var shot_time := -10.0
var impact_time := -10.0
var impact_point := Vector2.ZERO
var impact_kind := ""

func setup(world: MountainWorld, tips: int = 1) -> void:
	body = preload("res://scenes/player_sprite.tscn").instantiate() as ExplorerRig
	add_child(body)
	body.setup()
	rope_material = world.mat("braided_rope",Color.WHITE,true)
	rope_material.albedo_texture = load(ART+"rope-albedo.png") as Texture2D
	rope_material.uv1_scale = Vector3(.20,1,1)
	rope_material.texture_repeat = true
	rope_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope = MeshInstance3D.new()
	rope.name = "Плетёный канат"
	rope.material_override = rope_material
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(rope)
	rope_outer = MeshInstance3D.new()
	rope_outer.name = "Контур каната"
	var edge := world.mat("rope_edge",Color("58412a"),true)
	edge.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope_outer.material_override = edge
	rope_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(rope_outer)
	rope_secondary = MeshInstance3D.new()
	rope_secondary.name = "Плетёный канат 2"
	rope_secondary.material_override = rope_material
	rope_secondary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(rope_secondary)
	rope_outer_secondary = MeshInstance3D.new()
	rope_outer_secondary.name = "Контур каната 2"
	rope_outer_secondary.material_override = edge
	rope_outer_secondary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(rope_outer_secondary)
	bolt = Node3D.new()
	bolt.name = "Кованый крюк"
	bolt.scale = Vector3.ONE*.5
	world.add_child(bolt)
	var metal := world.mat("painted_hook",Color.WHITE,true)
	metal.albedo_texture = load(ART+"hook-head.png") as Texture2D
	metal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	metal.alpha_scissor_threshold = .20
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	metal.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The shaft is not a tip: one curved hook, two side hooks, then a third
	# central point. Match the count shown in the equipment menu.
	var shaft := PackedVector2Array([Vector2(665,565),Vector2(755,575),Vector2(755,700),Vector2(710,720),Vector2(715,820),Vector2(755,845),Vector2(755,980),Vector2(705,1010),Vector2(730,1100),Vector2(730,1195),Vector2(680,1255),Vector2(595,1280),Vector2(510,1255),Vector2(455,1195),Vector2(455,1100),Vector2(500,1010),Vector2(445,980),Vector2(445,845),Vector2(500,820),Vector2(500,720),Vector2(435,700),Vector2(435,575),Vector2(525,565)])
	var center := PackedVector2Array([Vector2(595,40),Vector2(710,265),Vector2(665,280),Vector2(665,565),Vector2(525,565),Vector2(518,280),Vector2(480,265)])
	var right := PackedVector2Array([Vector2(660,575),Vector2(685,370),Vector2(760,285),Vector2(835,275),Vector2(1060,395),Vector2(1090,570),Vector2(1050,685),Vector2(985,590),Vector2(900,480),Vector2(815,415),Vector2(770,450),Vector2(735,580)])
	var left := PackedVector2Array()
	for point in right: left.append(Vector2(1190-point.x,point.y))
	var stem := MeshInstance3D.new()
	stem.mesh = hook_piece(shaft,Vector2(1189,1323))
	stem.material_override = metal
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.add_child(stem)
	for polygon in [right,left,center]:
		var piece := MeshInstance3D.new()
		piece.mesh = hook_piece(polygon,Vector2(1189,1323))
		piece.material_override = metal
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt.add_child(piece)
		prongs.append(piece)
	bolt_secondary = bolt.duplicate()
	bolt_secondary.name = "Кованый крюк 2"
	world.add_child(bolt_secondary)
	set_tip_count(tips)
	bolt.visible = false
	bolt_secondary.visible = false
	rope_secondary.visible = false
	rope_outer_secondary.visible = false
	world._make_glow_texture()
	contact_glow = Sprite3D.new()
	contact_glow.texture = world.ghost_texture
	contact_glow.pixel_size = .007
	contact_glow.shaded = false
	contact_glow.modulate = Color(1,.78,.35,.32)
	world.add_child(contact_glow)
	var effects := world.mat("hook_effects",Color.WHITE,true)
	effects.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	effects.vertex_color_use_as_albedo = true
	effects.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_mesh = MeshInstance3D.new()
	trail_mesh.material_override = effects
	trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(trail_mesh)
	impact_mesh = MeshInstance3D.new()
	impact_mesh.material_override = effects
	impact_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(impact_mesh)

static func hook_piece(polygon: PackedVector2Array, texture_size: Vector2) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in Geometry2D.triangulate_polygon(polygon):
		var pixel := polygon[index]
		surface.set_uv(pixel/texture_size)
		surface.set_normal(Vector3.BACK)
		surface.add_vertex(Vector3((pixel.x-595)*.00105,(52-pixel.y)*.00065,0))
	return surface.commit()

func set_tip_count(count: int) -> void:
	tip_count = clampi(count,1,3)
	for index in range(prongs.size()): prongs[index].visible = tip_count>=3 or index==2
	if is_instance_valid(bolt_secondary):
		for piece in bolt_secondary.get_children():
			if piece is MeshInstance3D and piece.get_index()>=1: piece.visible = tip_count>=3 or piece.get_index()==3

func set_hook_configuration(tips: int, count: int) -> void:
	hook_count = clampi(count,1,2)
	set_tip_count(tips)

func draw(sim: RopeSim, target: Vector2, tether: bool, flying_bolt: bool, time: float, warning: bool, tips: int = 1, flight: Dictionary = {}) -> void:
	if int(flight.get("shot",last_shot))!=last_shot:
		last_shot = int(flight["shot"])
		shot_time = time
	if int(flight.get("impact",last_impact))!=last_impact:
		last_impact = int(flight["impact"])
		impact_time = time
		impact_point = flight["impact_position"]
		impact_kind = flight["impact_kind"]
	set_hook_configuration(tips,int(flight.get("hook_count",hook_count)))
	var volley: Array = flight.get("volley",[])
	if volley.size()>1:
		_draw_volley(sim,time,warning,volley)
		return
	position = Vector3(sim.pos.x,sim.pos.y,3.2)
	var aiming: bool = flight.get("aiming",false)
	var body_target: Vector2 = sim.pos+flight.get("aim",Vector2.UP)*3 if aiming else target
	body.position.x = 0
	body.animate(sim,sim.effective_anchor() if sim.attached else body_target,tether or aiming,time)
	var recoil := maxf(0,1-(time-shot_time)/.16)
	var shot_direction: Vector2 = flight.get("velocity",Vector2.ZERO).normalized()
	body.position += Vector3(-shot_direction.x,-shot_direction.y,0)*.07*recoil*recoil
	var from := body.grip_position()
	var to := Vector3(target.x,target.y,3.5)
	set_tip_count(tips)
	bolt.visible = tether
	bolt.position = to
	var hook_from := Vector3(sim.rope_pivots[0].x,sim.rope_pivots[0].y,3.5) if sim.attached and not sim.rope_pivots.is_empty() else from
	var facing := Vector2(to.x-hook_from.x,to.y-hook_from.y)
	if flying_bolt and flight.get("velocity",Vector2.ZERO).length_squared()>.01: facing = flight["velocity"]
	bolt.rotation.z = facing.angle()-PI*.5
	if flying_bolt: bolt.rotation.z += sin(float(flight.get("age",0))*35)*.10*exp(-float(flight.get("age",0))*9)
	rope_start = from
	rope_end = bolt.to_global(HOOK_EYE)
	rope.visible = tether
	rope_outer.visible = tether
	if tether:
		var slack := maxf(0,sim.length-sim.path_distance()) if sim.attached else 0.0
		var points := PackedVector3Array()
		var previous := rope_start
		# The routed path is already the shortest collision-safe polyline. A
		# second downward sag between its pivots would be a different path and
		# could visually dip through the obstacle it just avoided.
		if sim.attached and not sim.rope_pivots.is_empty(): slack = 0.0
		if sim.attached:
			for i in range(sim.rope_pivots.size()-1,-1,-1):
				var pivot := sim.rope_pivots[i]
				var corner := Vector3(pivot.x,pivot.y,3.5)
				var next_point := rope_end if i==0 else Vector3(sim.rope_pivots[i-1].x,sim.rope_pivots[i-1].y,3.5)
				var incoming := (corner-previous).normalized()
				var outgoing := (next_point-corner).normalized()
				# Keep the round-over just outside the collision contour.  A large
				# offset reads as a floating rope; this is only a few centimetres at
				# game scale and lets the line visibly rest against the stone.
				var approach := corner-incoming*.035
				var depart := corner+outgoing*.035
				points.append_array(rope_points(previous,approach,slack))
				points.append_array(rope_corner_points(approach,corner,depart))
				slack = 0
				previous = depart
		if flying_bolt:
			points.append_array(flight_rope_points(previous,rope_end,float(flight.get("age",0)),bool(flight.get("returning",false))))
		else:
			points.append_array(rope_points(previous,rope_end,slack))
			# The catch sends a small wave toward the hand, then settles.
			var catch_age := time-catch_time
			if catch_age<.35 and sim.rope_pivots.is_empty():
				var axis := Vector3(-(rope_end-rope_start).y,(rope_end-rope_start).x,0).normalized()
				for index in range(1,points.size()-1):
					var t := float(index)/(points.size()-1)
					points[index] += axis*sin(t*PI)*sin(t*TAU*2+catch_age*35)*.09*exp(-catch_age*12)
		rope.mesh = rope_tube(points,.033)
		rope_outer.mesh = rope_strip(points,.047)
		rope_outer.position.z = -.045
	rope_material.albedo_color = Color("ff9d6d") if warning else Color.WHITE
	contact_glow.visible = sim.attached or flying_bolt
	contact_glow.position = to+Vector3(0,0,.15)
	if sim.attached and not was_attached: catch_time = time
	was_attached = sim.attached
	contact_glow.scale = Vector3.ONE*(.75+.30*exp(-maxf(0,time-catch_time)*9))
	_draw_effects(flight,flying_bolt,time)

func _draw_volley(sim: RopeSim, time: float, warning: bool, volley: Array) -> void:
	# Each line has its own head and rope. An attached shot remains on the
	# anchor while the losing shot visibly winds back to the hand.
	position = Vector3(sim.pos.x,sim.pos.y,3.2)
	var body_target := sim.effective_anchor() if sim.attached else Vector2(volley[0].get("position",sim.pos))
	body.position.x = 0
	body.animate(sim,body_target,sim.attached,time)
	var from := body.grip_position()
	for index in range(2):
		var shot: Dictionary = volley[index]
		var state := str(shot.get("state","idle"))
		var head: Node3D = bolt if index==0 else bolt_secondary
		var line: MeshInstance3D = rope if index==0 else rope_secondary
		var outline: MeshInstance3D = rope_outer if index==0 else rope_outer_secondary
		var active := state in ["flying","returning","attached"]
		head.visible = active
		line.visible = active
		outline.visible = active
		if not active: continue
		var point := sim.effective_anchor() if state=="attached" else Vector2(shot.get("position",sim.pos))
		var to := Vector3(point.x,point.y,3.5)
		head.position = to
		var velocity := Vector2(shot.get("velocity",Vector2.UP))
		var facing := velocity if state!="attached" and velocity.length_squared()>.01 else Vector2(to.x-from.x,to.y-from.y)
		head.rotation.z = facing.angle()-PI*.5
		var rope_from := from
		var points := PackedVector3Array()
		if state=="attached":
			for pivot in range(sim.rope_pivots.size()-1,-1,-1):
				var corner := Vector3(sim.rope_pivots[pivot].x,sim.rope_pivots[pivot].y,3.5)
				points.append_array(rope_points(rope_from,corner,0))
				rope_from = corner
			points.append_array(rope_points(rope_from,head.to_global(HOOK_EYE),0))
		else:
			points = flight_rope_points(rope_from,head.to_global(HOOK_EYE),float(shot.get("age",0)),state=="returning")
		line.mesh = rope_tube(points,.033)
		outline.mesh = rope_strip(points,.047)
		outline.position.z = -.045
	rope_material.albedo_color = Color("ff9d6d") if warning else Color.WHITE
	var any_flying := false
	for item in volley:
		if str(item.get("state","")) in ["flying","returning"]:
			any_flying = true
			break
	contact_glow.visible = sim.attached or any_flying
	contact_glow.position = Vector3(sim.effective_anchor().x,sim.effective_anchor().y,3.65) if sim.attached else Vector3(volley[0].get("position",sim.pos).x,volley[0].get("position",sim.pos).y,3.65)
	trail_mesh.visible = false

static func flight_rope_points(from: Vector3, to: Vector3, age: float, returning: bool) -> PackedVector3Array:
	var points := PackedVector3Array()
	var delta := to-from
	var axis := Vector3(-delta.y,delta.x,0).normalized()
	var amplitude := minf(.24,delta.length()*.06)
	for index in range(25):
		var t := index/24.0
		var envelope := sin(t*PI)
		var wave := sin(t*TAU*1.6-age*22)*amplitude*envelope
		var sag := .20*4*t*(1-t)*minf(1,delta.length()*.4)
		if returning: wave *= .45
		points.append(from.lerp(to,t)+axis*wave+Vector3.DOWN*sag)
	points[0] = from
	points[-1] = to
	return points

func _draw_effects(flight: Dictionary, flying: bool, time: float) -> void:
	var history: PackedVector2Array = flight.get("trail",PackedVector2Array())
	trail_mesh.visible = flying and history.size()>1
	if trail_mesh.visible:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(1,history.size()):
			var a := Vector3(history[index-1].x,history[index-1].y,3.42)
			var b := Vector3(history[index].x,history[index].y,3.42)
			var fade := float(index)/(history.size()-1)
			var normal := Vector3(-(b-a).y,(b-a).x,0).normalized()*.052*fade
			surface.set_color(Color(1,.84,.48,fade*.38))
			for point in [a+normal,a-normal,b-normal,a+normal,b-normal,b+normal]:
				surface.add_vertex(point)
		trail_mesh.mesh = surface.commit()
	var age := time-impact_time
	impact_mesh.visible = age>=0 and age<.28 and not impact_kind.is_empty()
	if not impact_mesh.visible: return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var color := Color("a8efcc") if impact_kind=="catch" else Color("ffd38b")
	color.a = pow(1-age/.28,2)
	surface.set_color(color)
	var radius := .12+age*1.9
	for index in range(8):
		var radial := Vector3(cos(index*TAU/8),sin(index*TAU/8),0)
		var tangent := Vector3(-radial.y,radial.x,0)*.018
		var center := Vector3(impact_point.x,impact_point.y,3.7)
		var a := center+radial*radius
		var b := center+radial*(radius+.12*(1-age/.28))
		for point in [a+tangent,a-tangent,b-tangent,a+tangent,b-tangent,b+tangent]: surface.add_vertex(point)
	impact_mesh.mesh = surface.commit()

static func rope_tube(points: PackedVector3Array, radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance := 0.0
	var sides := 8
	for index in range(points.size()-1):
		var a := points[index]
		var b := points[index+1]
		var segment_length := a.distance_to(b)
		var tangent_a := (points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]).normalized()
		var tangent_b := (points[mini(index+2,points.size()-1)]-points[index]).normalized()
		var axis_a := Vector3(-tangent_a.y,tangent_a.x,0).normalized()
		var axis_b := Vector3(-tangent_b.y,tangent_b.x,0).normalized()
		for side in range(sides):
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var angle: float = TAU*(side+corner.y)/sides
				var normal := (axis_a if corner.x==0 else axis_b)*cos(angle)+Vector3.BACK*sin(angle)
				surface.set_normal(normal)
				surface.set_uv(Vector2(float(side+corner.y)/sides,(distance+segment_length*corner.x)/.45))
				surface.add_vertex((a if corner.x==0 else b)+normal*radius)
		distance += segment_length
	return surface.commit()

static func rope_points(from: Vector3, to: Vector3, slack: float) -> PackedVector3Array:
	var desired := from.distance_to(to)+slack
	var low := 0.0
	var high := desired
	if slack>.005:
		for iteration in range(10):
			var sag := (low+high)*.5
			var distance := 0.0
			var previous := from
			for index in range(1,17):
				var t := index/16.0
				var point := from.lerp(to,t)+Vector3.DOWN*sag*4*t*(1-t)
				distance += previous.distance_to(point)
				previous = point
			if distance<desired:
				low = sag
			else:
				high = sag
	var sag := (low+high)*.5 if slack>.005 else 0.0
	var points := PackedVector3Array()
	for index in range(17):
		var t := index/16.0
		points.append(from.lerp(to,t)+Vector3.DOWN*sag*4*t*(1-t))
	return points

static func rope_corner_points(from: Vector3, corner: Vector3, to: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	# A short quadratic round-over removes the hard hinge at a rock corner while
	# keeping the rope outside the expanded collision contour.
	var incoming := (from-corner).normalized()
	var outgoing := (to-corner).normalized()
	var outward := (incoming+outgoing).normalized()
	if outward.length_squared()<.01: outward = Vector3.BACK
	var control := corner+outward*.014
	for index in range(7):
		var t := index/6.0
		var a := from.lerp(control,t)
		var b := control.lerp(to,t)
		points.append(a.lerp(b,t))
	return points

static func rope_strip(points: PackedVector3Array, radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size()-1):
		var a := points[index]
		var b := points[index+1]
		var normal := Vector3(-(b-a).y,(b-a).x,0).normalized()*radius
		for vertex in [a+normal,a-normal,b-normal,a+normal,b-normal,b+normal]:
			surface.set_normal(Vector3.BACK)
			surface.add_vertex(vertex)
	return surface.commit()
