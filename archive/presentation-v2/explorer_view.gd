class_name ExplorerView
extends Node3D

var body: Node3D
var rope: MeshInstance3D
var rope_outer: MeshInstance3D
var bolt: MeshInstance3D
var rope_material: StandardMaterial3D
var character_sprite: Sprite3D
var contact_glow: Sprite3D

func setup(world: MountainWorld) -> void:
	body = Node3D.new()
	add_child(body)
	character_sprite = Sprite3D.new()
	character_sprite.texture = load("res://assets/art/explorer-v2.png")
	character_sprite.pixel_size = 2.1/character_sprite.texture.get_height()
	character_sprite.position.y = .2
	character_sprite.shaded = false
	character_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body.add_child(character_sprite)
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
	bolt = world.sphere("Крюк",Vector3.ZERO,Vector3(.18,.18,.18),world.mat("bolt",Color("bde9ff"),true),world)
	bolt.visible = false
	world._make_glow_texture()
	contact_glow = Sprite3D.new()
	contact_glow.texture = world.ghost_texture
	contact_glow.pixel_size = .020
	contact_glow.shaded = false
	contact_glow.modulate = Color(.22,.72,1,.8)
	world.add_child(contact_glow)

func draw(sim: RopeSim, target: Vector2, tether: bool, flying_bolt: bool, time: float, warning: bool) -> void:
	position = Vector3(sim.pos.x,sim.pos.y,2.4)
	var side := -1.0 if sim.attached and target.x<sim.pos.x else 1.0
	character_sprite.flip_h = side<0
	var lean := clampf(-sim.vel.x*2,-28,28)
	if sim.attached:
		lean = clampf(rad_to_deg((target-sim.pos).angle()-Vector2(side*.55,1).angle()),-40,40)
	body.rotation_degrees = Vector3(0,0,lean)
	var from := body.to_global(Vector3(side*.55,1,.1))
	var to := Vector3(target.x,target.y,2.25)
	rope.visible = tether
	rope_outer.visible = tether
	if tether:
		var slack := maxf(0,sim.length-sim.pos.distance_to(sim.anchor)) if sim.attached else 0.0
		var points := rope_points(from,to,slack)
		rope.mesh = rope_strip(points,.023)
		rope_outer.mesh = rope_strip(points,.052)
		rope_outer.position.z = -.04
	rope_material.albedo_color = Color("ff986f") if warning else Color("eadcff")
	bolt.visible = flying_bolt
	if flying_bolt:
		bolt.position = to
	contact_glow.visible = sim.attached or flying_bolt
	contact_glow.position = to+Vector3(0,0,.15)
	contact_glow.scale = Vector3.ONE*(.85+.06*sin(time*8))

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
