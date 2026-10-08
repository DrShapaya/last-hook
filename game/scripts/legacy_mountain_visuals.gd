class_name LegacyMountainVisuals
extends MountainVisuals

func build_chunk(index: int, parent: Node3D) -> void:
	for slice in range(6):
		var sample := index*6+slice
		var y := sample*4.0
		var random := layout.rng(sample,32)
		for side in [-1,1]:
			var a := layout.outer_edge(y,side)
			var b := layout.outer_edge(y+4,side)
			var outer: float = side*10.0
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var vertices := [Vector3(minf(a,outer),y,-2),Vector3(maxf(a,outer),y,-2),Vector3(maxf(b,outer),y+4,-2),Vector3(minf(b,outer),y+4,-2)]
			for vertex_index in [0,2,1,0,3,2]: surface.add_vertex(vertices[vertex_index])
			var mesh := MeshInstance3D.new()
			mesh.mesh = surface.commit()
			var color := Color("263c52").lightened(random.randf_range(0,.1))
			mesh.material_override = world.mat("legacy_cliff_%s" % color.to_html(),color)
			mesh.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
			parent.add_child(mesh)
			world.box("Пласт скалы",Vector3(side*random.randf_range(5.5,6.5),y+random.randf_range(.5,3.5),-.8),Vector3(random.randf_range(1,2),random.randf_range(.35,1.2),.3),world.mat("legacy_facet_%d" % (sample%3),Color("38526b").lightened((sample%3)*.035)),parent)
		world.box("Дальний хребет",Vector3(random.randf_range(-2,2),y+2,-5),Vector3(random.randf_range(2,5),4.1,.1),world.mat("legacy_distant",Color("1a2b3e")),parent)

func build_anchor(object: Dictionary, parent: Node3D) -> void:
	var p: Vector2 = object["pos"]
	var d: Vector2 = object["dimensions"]
	var kind: int = object["kind"]
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(p.x,p.y,2)
	object["visual"] = holder
	world.box("Прямоугольник",holder.position,Vector3(d.x,d.y,.35),world.mat("legacy_kind_%d" % kind,MountainWorld.COLORS[kind]),holder)
	world.box("Верхняя грань",holder.position+Vector3(0,d.y*.5-.04,.2),Vector3(d.x,.08,.05),world.mat("legacy_highlight_%d" % kind,MountainWorld.COLORS[kind].lightened(.22)),holder)

func build_obstacle(object: Dictionary, parent: Node3D) -> void:
	var p: Vector2 = object["pos"]
	var d: Vector2 = object["dimensions"]
	object["visual"] = world.box("Препятствие",Vector3(p.x,p.y,2),Vector3(d.x,d.y,.5),world.mat("legacy_obstacle",Color("d75c67")),parent)

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	var start := float(object["top"])<1
	var center := Vector3((object["left"]+object["right"])*.5,object["top"]-(.3 if start else .15),1.8)
	world.box("Площадка",center,Vector3(object["right"]-object["left"],.6 if start else .3,.5 if start else .4),world.mat("legacy_ledge",Color("52667c") if start else Color("6c8099")),parent)
