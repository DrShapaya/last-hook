class_name MountainVisuals
extends RefCounted

var world: Node3D
var layout: MountainLayout
const ROCK_COLORS := [Color("657478"),Color("777667"),Color("929387"),Color("3b4c59")]

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	world = owner_world
	layout = source

func rock_color() -> Color:
	return ROCK_COLORS[layout.location%4]

func zone_color(height: float) -> Color:
	if layout.location!=0: return rock_color()
	var colors := [Color("657478"),Color("77786f"),Color("888779"),Color("91aeb9"),Color("796660"),Color("9aa5b5")]
	var t := clampf(height/20,0,5)
	var index := mini(int(t),4)
	return colors[index].lerp(colors[index+1],smoothstep(.65,1.0,t-index))

func vertex(point: Vector2) -> Vector3:
	var depth := 1.1+.24*sin(point.x*1.7+point.y*.6)+.16*sin(point.y*2.1-point.x)
	return Vector3(point.x,point.y,depth)

func sample_point(x: int, y: int) -> Vector2:
	var random := layout.rng(x*9781+y*6271,66)
	var jitter := Vector2(random.randf_range(-.42,.42),random.randf_range(-.42,.42))
	return Vector2(-19.5+x*1.5,y*1.5)+jitter

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for p in [a,b,c]:
		surface.set_color(color)
		surface.add_vertex(p)

func _clip_triangle(surface: SurfaceTool, points: Array[Vector2], fields: Array[float], color: Color) -> void:
	var polygon: Array[Vector2] = []
	var cuts: Array[Vector2] = []
	for i in range(3):
		var j := (i+1)%3
		if fields[i]>=0: polygon.append(points[i])
		if (fields[i]>=0)!=(fields[j]>=0):
			var p := points[i].lerp(points[j],fields[i]/(fields[i]-fields[j]))
			polygon.append(p)
			cuts.append(p)
	for i in range(1,polygon.size()-1):
		_triangle(surface,vertex(polygon[0]),vertex(polygon[i]),vertex(polygon[i+1]),color)
	if cuts.size()==2:
		var a := vertex(cuts[0])
		var b := vertex(cuts[1])
		var back_a := Vector3(a.x,a.y,-3.8)
		var back_b := Vector3(b.x,b.y,-3.8)
		_triangle(surface,a,back_a,b,color.darkened(.22))
		_triangle(surface,b,back_a,back_b,color.darkened(.22))

func build_chunk(index: int, parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: Dictionary = {}
	var sample_positions: Dictionary = {}
	var bottom := index*24.0
	for x in range(27):
		for y in range(17):
			var point := sample_point(x,index*16+y)
			samples[Vector2i(x,y)] = layout.rock_field(point)
			sample_positions[Vector2i(x,y)] = point
	for x in range(26):
		for y in range(16):
			var a: Vector2 = sample_positions[Vector2i(x,y)]
			var b: Vector2 = sample_positions[Vector2i(x+1,y)]
			var c: Vector2 = sample_positions[Vector2i(x+1,y+1)]
			var d: Vector2 = sample_positions[Vector2i(x,y+1)]
			var random := layout.rng(index*1000+x*17+y,65)
			var color := zone_color((a.y+c.y)*.5).lightened(random.randf_range(-.055,.055))
			_clip_triangle(surface,[a,b,c],[samples[Vector2i(x,y)],samples[Vector2i(x+1,y)],samples[Vector2i(x+1,y+1)]],color)
			_clip_triangle(surface,[a,c,d],[samples[Vector2i(x,y)],samples[Vector2i(x+1,y+1)],samples[Vector2i(x,y+1)]],color.lightened(random.randf_range(-.045,.045)))
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("mountain_vertex",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	parent.add_child(instance)
	# Small mineral/vegetation accents, attached only to solid surface.
	var random := layout.rng(index,67)
	for n in range(24):
		var point := Vector2(random.randf_range(-17.5,17.5),bottom+random.randf_range(.3,23.7))
		if layout.rock_field(point)<1.0: continue
		var color := Color("7d9b55") if layout.location%4!=3 else Color("ab7750")
		world.box("Мох" if layout.location%4!=3 else "Минеральная жила",Vector3(point.x,point.y,1.25),Vector3(random.randf_range(.3,.9),.11,.12),world.mat("mineral_%d" % layout.location,color,false),parent)

func beam(a: Vector3, b: Vector3, radius: float, color: Color, parent: Node3D) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius*.8
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 7
	var instance := MeshInstance3D.new()
	instance.mesh = cylinder
	instance.material_override = world.mat("wood_%s" % color.to_html(),color,false)
	parent.add_child(instance)
	instance.position = (a+b)*.5
	instance.quaternion = Quaternion(Vector3.UP,(b-a).normalized())

func _extruded_polygon(polygon: PackedVector2Array, depth: float, color: Color, parent: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0,indices.size(),3):
		var a := polygon[indices[i]]
		var b := polygon[indices[i+1]]
		var c := polygon[indices[i+2]]
		_triangle(surface,Vector3(a.x,a.y,depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(c.x,c.y,depth*.5),color)
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		_triangle(surface,Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,-depth*.5),Vector3(b.x,b.y,depth*.5),color.darkened(.2))
		_triangle(surface,Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(a.x,a.y,depth*.5),color.darkened(.2))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("grip_vertex",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	parent.add_child(mesh)

func anchor_polygon(dimensions: Vector2) -> PackedVector2Array:
	return MountainLayout.grip_polygon(dimensions)

func build_anchor(object: Dictionary, parent: Node3D) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	holder.position = Vector3(p.x,p.y,2)
	object["visual"] = holder
	var d: Vector2 = object["dimensions"]
	var kind: int = object["kind"]
	var biome := 0
	var color := zone_color(p.y).lightened(.13)
	if kind==1: color = Color("92704b")
	if kind==3: color = Color("80b6bd")
	if kind==4: color = Color("9e85aa")
	var polygon: PackedVector2Array = object["polygon"]
	_extruded_polygon(polygon,.8,color,holder)
	# The support extends backward only, never inventing a collision in XY.
	world.box("Опора в скале",Vector3(p.x,p.y,1.3),Vector3(d.x*.75,d.y*.7,1.4),world.mat("support_%d" % biome,color.darkened(.12),false),holder)
	# A narrow material strip communicates mechanics without rectangular targets.
	world.box("Материал зацепа",Vector3(p.x,p.y+d.y*.35,2.43),Vector3(d.x*.7,.065,.06),world.mat("kind_%d" % kind,MountainWorld.COLORS[kind]),holder)
	if object.get("permanent",true):
		for side in [-1,1]:
			world.box("Золотое крепление",Vector3(p.x+side*d.x*.38,p.y,2.47),Vector3(.11,d.y*.75,.07),world.mat("fixed_grip",Color("ffda83"),true),holder)
	else:
		beam(Vector3(-d.x*.12,d.y*.35,.43),Vector3(d.x*.04,-d.y*.1,.43),.018,Color("655b48"),holder)
		beam(Vector3(d.x*.04,-d.y*.1,.43),Vector3(-d.x*.02,-d.y*.4,.43),.018,Color("655b48"),holder)

func build_obstacle(object: Dictionary, parent: Node3D) -> void:
	var p: Vector2 = object["pos"]
	var d: Vector2 = object["dimensions"]
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(p.x,p.y,2)
	object["visual"] = holder
	world.box("Твёрдый выступ",holder.position,Vector3(d.x,d.y,1.1),world.mat("solid_rock",rock_color().darkened(.25),false),holder)
	world.box("Опасная грань",holder.position+Vector3(0,d.y*.5-.06,.57),Vector3(d.x,.12,.05),world.mat("hazard",Color("cc795d")),holder)

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	var center := Vector3((object["left"]+object["right"])*.5,object["top"]-.15,1.8)
	var width: float = object["right"]-object["left"]
	world.box("Площадка отдыха",center,Vector3(width,.3,1),world.mat("platform",Color("9c845e"),false),parent)
	beam(center+Vector3(-width*.3,-.15,-.3),center+Vector3(0,-1,-1.3),.09,Color("6e533a"),parent)
	beam(center+Vector3(width*.3,-.15,-.3),center+Vector3(0,-1,-1.3),.09,Color("6e533a"),parent)
