class_name MassifVisuals
extends MountainVisuals

const CELL_SIZE := .6
const COLUMNS := 120
const ROWS := 40
var massif: MassifLayout
var rock_material := ShaderMaterial.new()
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
	var color := base_color.lerp(tint,.62).lightened(.16)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(polygon)
	# Faceted front plane: each wedge catches a slightly different amount of
	# light, while the outer silhouette remains the exact collision polygon.
	var centroid := Vector2.ZERO
	for point in polygon: centroid += point
	centroid /= polygon.size()
	for i in range(polygon.size()):
		var a: Vector2 = centroid.lerp(polygon[i],.94)
		var b: Vector2 = centroid.lerp(polygon[(i+1)%polygon.size()],.94)
		var face_color := color.lightened((float((i+variant)%3)-1.0)*.055)
		_triangle(surface,Vector3(centroid.x,centroid.y,.66),Vector3(b.x,b.y,.66),Vector3(a.x,a.y,.66),face_color)
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		_triangle(surface,Vector3(a.x,a.y,-.65),Vector3(b.x,b.y,-.65),Vector3(b.x*.88,b.y*.88,.65),color)
		_triangle(surface,Vector3(a.x,a.y,-.65),Vector3(b.x*.88,b.y*.88,.65),Vector3(a.x*.88,a.y*.88,.65),color)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = rock_material
	holder.add_child(instance)
	# A bevel and a dark underside make the solid read as a protruding piece of
	# rock. The decorative lines sit on the same polygon and never change hits.
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		var edge_color := Color("c7bd91") if a.y<-.25 and b.y<-.25 else Color("353d3c")
		beam(Vector3(a.x*.92,a.y*.92,.79),Vector3(b.x*.92,b.y*.92,.79),.035 if shape=="shelf" else .025,edge_color,holder)
	if shape=="shelf":
		# Two short cantilever ribs explain why a wide shelf stays attached.
		var width: float = float(object["dimensions"].x)
		beam(Vector3(-width*.30,-object["dimensions"].y*.38,.58),Vector3(-width*.12,-object["dimensions"].y*1.15,-.05),.075,Color("4a514b"),holder)
		beam(Vector3(width*.28,-object["dimensions"].y*.34,.58),Vector3(width*.12,-object["dimensions"].y*1.05,-.05),.075,Color("4a514b"),holder)
	elif shape=="pillar":
		# Vertical strata and a broken cap communicate a column rather than a box.
		var height: float = float(object["dimensions"].y)
		for stripe in range(2):
			var x: float = -float(object["dimensions"].x)*.22+stripe*float(object["dimensions"].x)*.35
			beam(Vector3(x,-height*.30,.82),Vector3(x+.10,height*.30,.82),.018,Color("a69b7e"),holder)
	else:
		beam(Vector3(-object["dimensions"].x*.25,-object["dimensions"].y*.14,.82),Vector3(0,object["dimensions"].y*.22,.82),.018,Color("b39b7c"),holder)

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
	var rock := zone_color(top).darkened(.04)
	_extruded_polygon(polygon,.75,rock,holder)
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		if a.y>=-.08 and b.y>=-.08:
			beam(Vector3(a.x,a.y,.42),Vector3(b.x,b.y,.42),.045,Color("dfc985"),holder)
		elif a.y<-.2 and b.y<-.2:
			beam(Vector3(a.x,a.y,.36),Vector3(b.x,b.y,.36),.028,Color("3d4945"),holder)
	# Supports are decorative, angled into the rear cliff and remain behind the
	# real one-way platform plane.
	var support_color := Color("55483b")
	beam(Vector3(-width*.30,-.25,-.1),Vector3(-width*.16,-.94,-1.0),.085,support_color,holder)
	beam(Vector3(width*.27,-.24,-.1),Vector3(width*.10,-.84,-1.0),.085,support_color,holder)
	if style==1:
		beam(Vector3(-width*.05,-.18,.36),Vector3(width*.14,-.44,.36),.025,Color("9b8a63"),holder)
