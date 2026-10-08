class_name ExplorerView
extends Node3D

var body: Node3D
var rope: MeshInstance3D
var rope_outer: MeshInstance3D
var bolt: Node3D
var prongs: Array[MeshInstance3D] = []
var prong_outlines: Array[MeshInstance3D] = []
var tip_count := 0
var rope_material: StandardMaterial3D
var contact_glow: Sprite3D
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var was_attached := false
var catch_time := -10.0

func setup(world: MountainWorld) -> void:
	body = Node3D.new()
	add_child(body)
	world.box("Тело",Vector3(0,.12,0),Vector3(.53,.58,.3),world.mat("hero_body",Color("eff5f8")),body)
	world.box("Голова",Vector3(0,.65,.02),Vector3(.58,.5,.35),world.mat("hero_head",Color("f4cd67")),body)
	for side in [-1,1]:
		world.box("Глаз",Vector3(side*.12,.65,.205),Vector3(.055,.075,.025),world.mat("hero_dark",Color("24394b")),body)
		var arm := Node3D.new()
		arm.position = Vector3(side*.32,.32,.05)
		body.add_child(arm)
		world.box("Рука",arm.to_global(Vector3(0,-.18,0)),Vector3(.15,.4,.2),world.mat("hero_body",Color("eff5f8")),arm)
		world.box("Перчатка",arm.to_global(Vector3(0,-.42,0)),Vector3(.18,.15,.23),world.mat("hero_dark",Color("24394b")),arm)
		arms.append(arm)
		var leg := Node3D.new()
		leg.position = Vector3(side*.16,-.14,.02)
		body.add_child(leg)
		world.box("Нога",leg.to_global(Vector3(0,-.17,0)),Vector3(.2,.34,.24),world.mat("hero_pants",Color("5b839d")),leg)
		world.box("Ботинок",leg.to_global(Vector3(side*.025,-.34,.04)),Vector3(.24,.13,.3),world.mat("hero_dark",Color("24394b")),leg)
		legs.append(leg)
	world.box("Рюкзак",Vector3(-.3,.08,-.04),Vector3(.25,.55,.4),world.mat("hero_bag",Color("7ab2e2")),body)
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = .023
	rope_mesh.bottom_radius = .023
	rope_mesh.height = 1
	rope_mesh.radial_segments = 6
	rope_material = world.mat("rope",Color("eadcff"),true)
	rope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope = MeshInstance3D.new()
	rope.mesh = rope_mesh
	rope.material_override = rope_material
	world.add_child(rope)
	var outer_mesh := CylinderMesh.new()
	outer_mesh.top_radius = .052
	outer_mesh.bottom_radius = .052
	outer_mesh.height = 1
	outer_mesh.radial_segments = 6
	rope_outer = MeshInstance3D.new()
	rope_outer.mesh = outer_mesh
	var outer_material := world.mat("rope_outer",Color(.35,.39,.94,.42),true)
	outer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope_outer.material_override = outer_material
	world.add_child(rope_outer)
	bolt = Node3D.new()
	bolt.name = "Крюк с наконечниками"
	world.add_child(bolt)
	var steel := world.mat("hook_steel",Color("e1eff1"),true)
	var collar := world.mat("hook_gold",Color("f3c668"),true)
	var edge := world.mat("hook_edge",Color("25394b"),true)
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge.cull_mode = BaseMaterial3D.CULL_DISABLED
	var eye := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = .065
	ring.outer_radius = .115
	ring.rings = 16
	ring.ring_segments = 8
	eye.mesh = ring
	eye.material_override = collar
	eye.rotation.x = PI*.5
	eye.position.y = -.42
	bolt.add_child(eye)
	var stem := MeshInstance3D.new()
	stem.mesh = rope_strip(PackedVector3Array([Vector3(0,-.35,0),Vector3(0,-.02,0)]),.045)
	stem.material_override = steel
	bolt.add_child(stem)
	var stem_outline := MeshInstance3D.new()
	stem_outline.mesh = rope_strip(PackedVector3Array([Vector3(0,-.35,0),Vector3(0,-.02,0)]),.075)
	stem_outline.material_override = edge
	stem_outline.position.z = -.02
	bolt.add_child(stem_outline)
	for index in range(3):
		var outline := MeshInstance3D.new()
		outline.material_override = edge
		outline.position.z = -.02
		bolt.add_child(outline)
		prong_outlines.append(outline)
		var prong := MeshInstance3D.new()
		prong.material_override = steel
		bolt.add_child(prong)
		prongs.append(prong)
	set_tip_count(1)
	bolt.visible = false
	world._make_glow_texture()
	contact_glow = Sprite3D.new()
	contact_glow.texture = world.ghost_texture
	contact_glow.pixel_size = .010
	contact_glow.shaded = false
	contact_glow.modulate = Color(.22,.72,1,.32)
	world.add_child(contact_glow)

func set_tip_count(count: int) -> void:
	if count==tip_count: return
	tip_count = clampi(count,1,3)
	var radius: float = [.32,.53,.76][tip_count-1]
	for index in range(3):
		prongs[index].visible = index<tip_count
		prong_outlines[index].visible = index<tip_count
		if index>=tip_count: continue
		var side := 1.0 if index==0 else -1.0 if index==1 else .28
		var points := PackedVector3Array([Vector3(0,-.22,0),Vector3(side*radius*.45,-.25,0),Vector3(side*radius*.90,-.16,0),Vector3(side*radius,-.02,0),Vector3(side*radius*.91,.12,0),Vector3(side*radius*.73,.02,0)])
		prongs[index].mesh = rope_strip(points,.038)
		prong_outlines[index].mesh = rope_strip(points,.068)

func draw(sim: RopeSim, target: Vector2, tether: bool, flying_bolt: bool, time: float, warning: bool, tips: int = 1) -> void:
	position = Vector3(sim.pos.x,sim.pos.y,2.4)
	var side := -1.0 if sim.attached and target.x<sim.pos.x else 1.0
	var lean := clampf(-sim.vel.x*2,-28,28)
	if sim.attached:
		lean = clampf(rad_to_deg((target-sim.pos).angle()-Vector2(side*.55,1).angle()),-40,40)
	body.rotation_degrees = Vector3(0,0,lean)
	var reaching := 0 if side<0 else 1
	for index in range(2):
		var limb_side := -1.0 if index==0 else 1.0
		arms[index].rotation.z = (target-sim.pos).angle()+PI*.5-deg_to_rad(lean) if tether and index==reaching else limb_side*(.15+.06*sin(time*6))
		legs[index].rotation.z = limb_side*(.12+clampf(sim.vel.y*.025,-.12,.35))+.12*sin(time*7+index*PI)*clampf(sim.vel.length()/6,0,1)
	var from := arms[reaching].to_global(Vector3(0,-.44,.1)) if tether else body.to_global(Vector3(side*.4,.5,.1))
	var to := Vector3(target.x,target.y,2.25)
	set_tip_count(tips)
	var direction := (to-from).normalized()
	rope.visible = tether
	rope_outer.visible = tether
	if tether:
		var slack := maxf(0,sim.length-sim.pos.distance_to(sim.anchor)) if sim.attached else 0.0
		var points := rope_points(from,to-direction*.42,slack)
		rope.mesh = rope_strip(points,.023)
		rope_outer.mesh = rope_strip(points,.052)
		rope_outer.position.z = -.04
	rope_material.albedo_color = Color("ff986f") if warning else Color("eadcff")
	bolt.visible = tether
	if tether:
		bolt.position = to
		bolt.rotation.z = Vector2(direction.x,direction.y).angle()-PI*.5
	contact_glow.visible = sim.attached or flying_bolt
	contact_glow.position = to+Vector3(0,0,.15)
	if sim.attached and not was_attached: catch_time = time
	was_attached = sim.attached
	contact_glow.scale = Vector3.ONE*(.85+.06*sin(time*8)+.45*exp(-maxf(0,time-catch_time)*9))

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
