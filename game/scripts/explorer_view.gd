class_name ExplorerView
extends Node3D

const ART := "res://assets/art/modular-pack-v1/"
const HOOK_EYE := Vector3(0,-.7072,0)
var body: ExplorerRig
var rope: MeshInstance3D
var rope_outer: MeshInstance3D
var bolt: Node3D
var prongs: Array[MeshInstance3D] = []
var tip_count := 0
var rope_material: StandardMaterial3D
var contact_glow: Sprite3D
var was_attached := false
var catch_time := -10.0
var rope_start := Vector3.ZERO
var rope_end := Vector3.ZERO

func setup(world: MountainWorld) -> void:
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
	# Polygon masks share the original texture, without duplicating its raster.
	# The central arrow is tip one; side hooks are enabled at levels two and three.
	var shaft := PackedVector2Array([Vector2(595,40),Vector2(710,265),Vector2(665,280),Vector2(665,565),Vector2(755,575),Vector2(755,700),Vector2(710,720),Vector2(715,820),Vector2(755,845),Vector2(755,980),Vector2(705,1010),Vector2(730,1100),Vector2(730,1195),Vector2(680,1255),Vector2(595,1280),Vector2(510,1255),Vector2(455,1195),Vector2(455,1100),Vector2(500,1010),Vector2(445,980),Vector2(445,845),Vector2(500,820),Vector2(500,720),Vector2(435,700),Vector2(435,575),Vector2(525,565),Vector2(518,280),Vector2(480,265)])
	var right := PackedVector2Array([Vector2(660,575),Vector2(685,370),Vector2(760,285),Vector2(835,275),Vector2(1060,395),Vector2(1090,570),Vector2(1050,685),Vector2(985,590),Vector2(900,480),Vector2(815,415),Vector2(770,450),Vector2(735,580)])
	var left := PackedVector2Array()
	for point in right: left.append(Vector2(1190-point.x,point.y))
	for polygon in [shaft,right,left]:
		var piece := MeshInstance3D.new()
		piece.mesh = hook_piece(polygon,Vector2(1189,1323))
		piece.material_override = metal
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bolt.add_child(piece)
		prongs.append(piece)
	set_tip_count(1)
	bolt.visible = false
	world._make_glow_texture()
	contact_glow = Sprite3D.new()
	contact_glow.texture = world.ghost_texture
	contact_glow.pixel_size = .007
	contact_glow.shaded = false
	contact_glow.modulate = Color(1,.78,.35,.32)
	world.add_child(contact_glow)

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
	if count==tip_count: return
	tip_count = clampi(count,1,3)
	for index in range(prongs.size()): prongs[index].visible = index<tip_count

func draw(sim: RopeSim, target: Vector2, tether: bool, flying_bolt: bool, time: float, warning: bool, tips: int = 1) -> void:
	position = Vector3(sim.pos.x,sim.pos.y,3.2)
	body.animate(sim,target,tether,time)
	var from := body.grip_position()
	var to := Vector3(target.x,target.y,3.5)
	set_tip_count(tips)
	bolt.visible = tether
	bolt.position = to
	bolt.rotation.z = Vector2(to.x-from.x,to.y-from.y).angle()-PI*.5
	rope_start = from
	rope_end = bolt.to_global(HOOK_EYE)
	rope.visible = tether
	rope_outer.visible = tether
	if tether:
		var slack := maxf(0,sim.length-sim.pos.distance_to(sim.anchor)) if sim.attached else 0.0
		var points := rope_points(rope_start,rope_end,slack)
		rope.mesh = rope_tube(points,.033)
		rope_outer.mesh = rope_strip(points,.047)
		rope_outer.position.z = -.045
	rope_material.albedo_color = Color("ff9d6d") if warning else Color.WHITE
	contact_glow.visible = sim.attached or flying_bolt
	contact_glow.position = to+Vector3(0,0,.15)
	if sim.attached and not was_attached: catch_time = time
	was_attached = sim.attached
	contact_glow.scale = Vector3.ONE*(.75+.30*exp(-maxf(0,time-catch_time)*9))

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
