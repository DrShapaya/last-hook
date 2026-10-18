class_name MassifVisuals
extends MountainVisuals

const CELL_SIZE := .6
const COLUMNS := 120
const ROWS := 40
var massif: MassifLayout
var rock_material := ShaderMaterial.new()
var obstacle_material := ShaderMaterial.new()
var rear_material := ShaderMaterial.new()
var building_rear := false
var positions: Dictionary = {}
var normals: Dictionary = {}
var field_samples: Dictionary = {}
var emitted_vertices := 0

func _init(owner_world: Node3D, source: MountainLayout) -> void:
	super._init(owner_world,source)
	massif = source as MassifLayout
	rock_material.shader = preload("res://shaders/massif_rock.gdshader")
	obstacle_material.shader = rock_material.shader
	obstacle_material.set_shader_parameter("snow_override",0.0)
	obstacle_material.set_shader_parameter("aerial_depth",0.0)
	obstacle_material.set_shader_parameter("material_tint",.68)
	rear_material.shader = rock_material.shader
	rear_material.set_shader_parameter("aerial_depth",.28)

func zone_color(height: float) -> Color:
	var palette := [Color("657269"),Color("747b70"),Color("7c8179"),Color("8d989b"),Color("817970"),Color("a4adb0")]
	var t := clampf(height/20,0,5)
	var index := mini(int(t),4)
	return palette[index].lerp(palette[index+1],smoothstep(0,1,t-index))

func sample_point(x: int, y: int) -> Vector2:
	var jitter := Vector2(massif.grain_noise.get_noise_2d(x*31,y*37),massif.grain_noise.get_noise_2d(x*43+91,y*29))*.18
	return Vector2(-36.0+x*CELL_SIZE,y*CELL_SIZE)+jitter

func vertex(point: Vector2) -> Vector3:
	if not positions.has(point): positions[point] = Vector3(point.x,point.y,_depth(point))
	return positions[point]

func _depth(point: Vector2) -> float:
	return massif.rear_depth(point,_field(point)) if building_rear else massif.surface_depth(point,_field(point))

func _field(point: Vector2) -> float:
	if not field_samples.has(point): field_samples[point] = massif.rear_field(point) if building_rear else massif.rock_field(point)
	return field_samples[point]

func surface_normal(point: Vector2) -> Vector3:
	if not normals.has(point):
		var dx := (_depth(point+Vector2(.08,0))-_depth(point-Vector2(.08,0)))/.16
		var dy := (_depth(point+Vector2(0,.08))-_depth(point-Vector2(0,.08)))/.16
		normals[point] = Vector3(-dx,-dy,1).normalized()
	return normals[point]

func _emit(surface: SurfaceTool, point: Vector2) -> void:
	emitted_vertices += 1
	var color := zone_color(point.y).lightened(massif.relief_noise.get_noise_2d(point.x+9,point.y)*.065)
	surface.set_color(color.srgb_to_linear())
	surface.set_normal(Vector3.BACK)
	surface.add_vertex(vertex(point))

func _face(surface: SurfaceTool, points: Array[Vector2], fields: Array[float]) -> void:
	if maxf(fields[0],maxf(fields[1],fields[2]))<0: return
	var polygon: Array[Vector2] = []
	for i in range(3):
		var j := (i+1)%3
		if fields[i]>=0: polygon.append(points[i])
		if (fields[i]>=0)!=(fields[j]>=0):
			var a := points[i]
			var b := points[j]
			var fa := fields[i]
			# Refine the actual implicit contour instead of leaving a coarse
			# triangular staircase on a narrow rim or the mouth of an arch.
			for step in range(4):
				var middle := (a+b)*.5
				var fm := _field(middle)
				if (fm>=0)==(fa>=0):
					a=middle
					fa=fm
				else: b=middle
			polygon.append((a+b)*.5)
	for i in range(1,polygon.size()-1):
		_emit(surface,polygon[0])
		_emit(surface,polygon[i+1])
		_emit(surface,polygon[i])

func build_chunk(index: int, parent: Node3D) -> void:
	if index==0: _build_skin(-1,parent,true)
	_build_skin(index,parent,true)
	_build_skin(index,parent,false)

func _build_skin(index: int, parent: Node3D, rear: bool) -> void:
	building_rear = rear
	emitted_vertices = 0
	positions.clear()
	normals.clear()
	field_samples.clear()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var grid: Array[Vector2] = []
	var field := PackedFloat32Array()
	var columns := 180 if rear else COLUMNS
	var rows := 30 if rear else ROWS
	for x in range(columns+1):
		for y in range(rows+1):
			var point := sample_point(x,index*ROWS+y)
			if rear:
				var gy := index*rows+y
				var jitter := Vector2(massif.grain_noise.get_noise_2d(x*31,gy*37),massif.grain_noise.get_noise_2d(x*43+91,gy*29))*.18
				point = Vector2(-72+x*.8,gy*.8)+jitter
			grid.append(point)
			field.append(_field(point))
	for x in range(columns):
		for y in range(rows):
			var a := x*(rows+1)+y
			var b := (x+1)*(rows+1)+y
			var c := b+1
			var d := a+1
			_face(surface,[grid[a],grid[b],grid[c]],[field[a],field[b],field[c]])
			_face(surface,[grid[a],grid[c],grid[d]],[field[a],field[c],field[d]])
	if emitted_vertices==0:
		positions.clear()
		normals.clear()
		field_samples.clear()
		return
	var instance := MeshInstance3D.new()
	instance.name = ("Основание массива_%d" if rear else "Скальный массив_%d") % index
	surface.index()
	surface.generate_normals()
	var rock_mesh := surface.commit()
	var arrays := rock_mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var smooth_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# Interior normals are generated in native code. At chunk seams both sides
	# use the same analytic gradient, including the neighbour not loaded yet.
	for i in range(points.size()):
		if absf(points[i].y-index*24)<.14 or absf(points[i].y-(index+1)*24)<.14:
			smooth_normals[i] = surface_normal(Vector2(points[i].x,points[i].y))
	arrays[Mesh.ARRAY_NORMAL] = smooth_normals
	rock_mesh.clear_surfaces()
	rock_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	instance.mesh = rock_mesh
	instance.material_override = rear_material if rear else rock_material
	parent.add_child(instance)
	positions.clear()
	normals.clear()
	field_samples.clear()

func build_obstacle(object: Dictionary, parent: Node3D) -> void:
	if not object.get("massif",false):
		super.build_obstacle(object,parent)
		return
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	holder.position = Vector3(p.x,p.y,2)
	object["visual"] = holder
	var polygon: PackedVector2Array = object["polygon"]
	var shape := String(object.get("type","wedge"))
	var variant := int(object.get("variant",0))
	var base_color := zone_color(p.y)
	var palette := {
		"shelf": [Color("847e70"),Color("967d62"),Color("6e766f")],
		"pillar": [Color("596764"),Color("6d6862"),Color("4e626e")],
		"wedge": [Color("746d64"),Color("8b7560"),Color("5d6b67")]
	}
	var tint: Color = palette.get(shape,[Color("74756b")])[variant%3]
	# Obstacles are the darker, more contrasty forms in the scene. Their type
	# still changes the silhouette, while the route collision remains the
	# original polygon generated by MassifLayout.
	var color := base_color.lerp(tint,.72).darkened(.22)
	_faceted_shell(polygon,1.16,color,holder,variant,.23)

func build_anchor(object: Dictionary, parent: Node3D) -> void:
	# Prototype rock grips: large low-poly masses with a few readable planes.
	# The gameplay polygon is untouched; this is only the visual shell.
	var holder := Node3D.new()
	parent.add_child(holder)
	var p: Vector2 = object["pos"]
	holder.position = Vector3(p.x,p.y,2)
	object["visual"] = holder
	var kind := int(object.get("kind",0))
	var palette := [Color("657269"),Color("7b705e"),Color("62777a"),Color("706978")]
	var color := zone_color(p.y).darkened(.28).lerp(palette[posmod(kind,palette.size())],.72)
	# EncounterLayout stores grip polygons in holder-local coordinates (the
	# world position is applied by holder.position below).
	var local: PackedVector2Array = object["polygon"]
	var d: Vector2 = object["dimensions"]
	# Keep the gameplay polygon intact, but give the shell a silhouette that
	# matches the grip's role in the route. This is why nearby grips no longer
	# look like copies of one rectangular placeholder.
	var w := d.x*.58
	var h := d.y*.72
	match posmod(int(object.get("id",0)),4):
		0: local = PackedVector2Array([Vector2(-w,-h*.18),Vector2(-w*.82,-h*.72),Vector2(-w*.28,-h),Vector2(w*.48,-h*.88),Vector2(w,-h*.18),Vector2(w*.82,h*.38),Vector2(w*.16,h),Vector2(-w*.76,h*.68)])
		1: local = PackedVector2Array([Vector2(-w*.72,-h*.20),Vector2(-w*.42,-h*.86),Vector2(-w*.05,-h),Vector2(w*.42,-h*.45),Vector2(w*.72,h*.02),Vector2(w*.20,h),Vector2(-w*.35,h*.72),Vector2(-w,h*.18)])
		2: local = PackedVector2Array([Vector2(-w*.86,-h*.14),Vector2(-w*.48,-h*.86),Vector2(w*.20,-h),Vector2(w*.82,-h*.56),Vector2(w,h*.10),Vector2(w*.52,h*.72),Vector2(-w*.12,h),Vector2(-w*.92,h*.48)])
		_: local = PackedVector2Array([Vector2(-w,-h*.10),Vector2(-w*.74,-h*.78),Vector2(-w*.14,-h),Vector2(w*.52,-h*.72),Vector2(w*.90,h*.02),Vector2(w*.42,h),Vector2(-w*.30,h*.74),Vector2(-w*.88,h*.38)])
	_faceted_shell(local,.92,color,holder,posmod(int(object.get("id",0)),4),.13)

func _faceted_shell(polygon: PackedVector2Array, depth: float, base_color: Color, parent: Node3D, variant: int, contrast: float = .14) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var facet_colors := [base_color.lightened(contrast),base_color.darkened(contrast*.45),base_color.lightened(contrast*.28),base_color.darkened(contrast)]
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0,indices.size(),3):
		var face_color: Color = facet_colors[posmod(i/3+variant,facet_colors.size())]
		_triangle(surface,Vector3(polygon[indices[i]].x,polygon[indices[i]].y,depth*.5),Vector3(polygon[indices[i+1]].x,polygon[indices[i+1]].y,depth*.5),Vector3(polygon[indices[i+2]].x,polygon[indices[i+2]].y,depth*.5),face_color)
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		var side_color: Color = facet_colors[posmod(i+variant,facet_colors.size())].darkened(.24)
		_triangle(surface,Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,-depth*.5),Vector3(b.x,b.y,depth*.5),side_color)
		_triangle(surface,Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(a.x,a.y,depth*.5),side_color.darkened(.18))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = world.mat("prototype_grip_vertex",Color.WHITE,false)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	parent.add_child(mesh)

func build_ledge(object: Dictionary, parent: Node3D) -> void:
	var left: float = object["left"]
	var right: float = object["right"]
	var top: float = object["top"]
	var center := Vector2((left+right)*.5,top)
	var width := right-left
	var style := int(object.get("style",posmod(int(absf(center.x*97.0+top*31.0)),3)))
	var polygon := PackedVector2Array()
	if style==0: # broad cantilever with a broken front lip
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(width*.40,0),Vector2(width*.50,-.16),Vector2(width*.34,-.48),Vector2(-width*.44,-.42),Vector2(-width*.54,-.16)])
	elif style==1: # saddle shaped shelf, slightly asymmetric
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(-width*.12,.07),Vector2(width*.46,0),Vector2(width*.50,-.22),Vector2(width*.28,-.5),Vector2(-width*.42,-.38)])
	else: # wedge anchored into the mountain
		polygon = PackedVector2Array([Vector2(-width*.50,0),Vector2(width*.50,.04),Vector2(width*.39,-.30),Vector2(width*.08,-.58),Vector2(-width*.47,-.35)])
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(center.x,center.y,1.75)
	# Rest ledges stay broad and readable: a lighter, quieter top mass separates
	# them from the darker hazard rocks without introducing wooden UI-like trims.
	var rock := zone_color(top).darkened(.08).lightened(.10)
	_faceted_shell(polygon,.86,rock,holder,style,.09)
