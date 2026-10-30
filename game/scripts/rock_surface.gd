class_name RockSurface
extends RefCounted

# One continuous faceted rock face over a level's mask, for locations whose
# stone is no heap of boulders. Each location has its own subclass: it owes a
# height and a colour for any point of the face. A grid anchored to the world
# gives every band the same vertices at their seam; its corners are shaken
# apart so the facets lie unevenly, and those at the mask's edge are drawn
# onto it, so the outline is the mask's. The masses of MassifVisuals stay
# behind this face as an unseen frame that carries grips, finds and plants.

const BACK_Z := -4.2
# Height of the face at the mask's edge and the most it may reach, in front of
# which only grips and the hero stand.
const RIM_Z := -2.6
const FRONT_Z := 1.0

var field: PackedFloat32Array
var size := Vector2i.ZERO
var step := .5
var origin := Vector2.ZERO
var random_seed := 0
var layout: MaskLayout
# Shaken grid corners of the band being built.
var corners: Dictionary = {}

static func make(level: MaskLayout) -> RockSurface:
	match level.rock_form:
		"desert": return DesertRock.new(level)
		"winter": return WinterRock.new(level)
	return null

func _init(level: MaskLayout) -> void:
	layout = level
	field = level.rock_grid
	size = level.rock_grid_size
	step = level.rock_grid_step
	origin = level.rock_grid_origin
	random_seed = level.seed_value

# How far a point lies inside the mask, in units.
func distance(point: Vector2) -> float:
	var at := (point-origin)/step
	var x := int(floor(at.x))
	var y := int(floor(at.y))
	if x<0 or y<0 or x>=size.x-1 or y>=size.y-1: return -8.0
	var fx := at.x-x
	var fy := at.y-y
	var low := lerpf(field[y*size.x+x],field[y*size.x+x+1],fx)
	var high := lerpf(field[(y+1)*size.x+x],field[(y+1)*size.x+x+1],fx)
	return lerpf(low,high,fy)

func gradient(point: Vector2) -> Vector2:
	var result := Vector2(distance(point+Vector2(.4,0))-distance(point-Vector2(.4,0)),distance(point+Vector2(0,.4))-distance(point-Vector2(0,.4)))
	return result.normalized() if result.length_squared()>.0001 else Vector2.ZERO

# Grid of the facets: its scale across and up, and how far each row leans.
func _basis() -> Vector3:
	return Vector3(1,1,0)

# Loose rocks on the face in a band: [centre, half sizes].
func lumps(_low: float, _high: float) -> Array:
	return []

# No grip stands so close that a rock would hide it.
func _clear_of_grips(point: Vector2, reach: float) -> bool:
	for id in layout.nearby_ids(point.y-reach-1.0,point.y+reach+1.0):
		if layout.anchors[id]["pos"].distance_to(point)<reach: return false
	return true

# The face's depth at a point.
func height(_point: Vector2) -> float:
	return RIM_Z

# The colour of a facet from its centre and normal.
func facet_color(_center: Vector3, _normal: Vector3) -> Color:
	return Color.GRAY

# Places where something can stand: points where the face falls back above,
# as on the top of a ledge. As Vector3(x, y, depth).
func perches(low: float, high: float, random: RandomNumberGenerator, tries: int) -> Array:
	var result: Array = []
	for attempt in range(tries):
		var point := Vector2(random.randf_range(origin.x,origin.x+size.x*step),random.randf_range(low,high))
		if distance(point)<.5: continue
		var here := height(point)
		if height(point+Vector2(0,.5))<here-.3: result.append(Vector3(point.x,point.y,here))
	return result

# Places under an overhang, for what hangs: Vector3(x, y, depth).
func hangs(low: float, high: float, random: RandomNumberGenerator, tries: int) -> Array:
	var result: Array = []
	for attempt in range(tries):
		var point := Vector2(random.randf_range(origin.x,origin.x+size.x*step),random.randf_range(low,high))
		if distance(point)>.5 or distance(point)<.05 or distance(point+Vector2(0,-.9))>-.1 or distance(point+Vector2(0,1.0))<.3: continue
		result.append(Vector3(point.x,point.y,height(point)))
	return result

func _hash(i: int, j: int, salt: int) -> float:
	var value := hash(Vector3i(i,j,salt+random_seed%100003))
	return float(value%100000)/100000.0

func _corner(i: int, j: int, cell: float) -> Vector2:
	var key := Vector2i(i,j)
	if corners.has(key): return corners[key]
	var basis := _basis()
	var point := Vector2((i+(_hash(i,j,1)-.5)*.62)*basis.x+j*basis.y*basis.z,(j+(_hash(i,j,2)-.5)*.62)*basis.y)*cell
	var inside := distance(point)
	if inside< -cell*1.6: point = Vector2.INF
	elif inside<.1: point += gradient(point)*(.1-inside)
	corners[key] = point
	return point

# The face between two heights, at about `cell` units a facet.
func build(low: float, high: float, cell: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	corners.clear()
	var basis := _basis()
	var left := int(floor((origin.x-1.0)/(cell*basis.x)))
	var right := int(ceil((origin.x+size.x*step+1.0)/(cell*basis.x)))
	for j in range(int(ceil(low/(cell*basis.y))),int(ceil(high/(cell*basis.y)))):
		var shift := roundi(j*basis.y*basis.z/basis.x)
		for i in range(left-shift,right-shift):
			var a := _corner(i,j,cell)
			var b := _corner(i+1,j,cell)
			var c := _corner(i+1,j+1,cell)
			var d := _corner(i,j+1,cell)
			var triangles := [[a,b,c],[a,c,d]] if _hash(i,j,3)<.5 else [[a,b,d],[b,c,d]]
			for triangle in triangles: _emit(triangle,vertices,normals,colors,cell)
	for lump in lumps(low,high): _emit_lump(lump[0],lump[1],vertices,normals,colors)
	var mesh := ArrayMesh.new()
	if vertices.is_empty(): return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _emit(triangle: Array, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, cell: float) -> void:
	var a: Vector2 = triangle[0]
	var b: Vector2 = triangle[1]
	var c: Vector2 = triangle[2]
	if not a.is_finite() or not b.is_finite() or not c.is_finite(): return
	var middle := (a+b+c)/3.0
	if distance(middle)<=.0: return
	var pa := Vector3(a.x,a.y,height(a))
	var pb := Vector3(b.x,b.y,height(b))
	var pc := Vector3(c.x,c.y,height(c))
	var normal := (pc-pa).cross(pb-pa).normalized()
	if normal.z<0:
		var swap := pb
		pb = pc
		pc = swap
		normal = -normal
	var color := facet_color((pa+pb+pc)/3.0,normal)
	for point in [pa,pb,pc]:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)
	# Where the mask ends the rock turns back into the mountain.
	for edge in [[pa,pb],[pb,pc],[pc,pa]]:
		var from: Vector3 = edge[0]
		var to: Vector3 = edge[1]
		var along := Vector2(to.x-from.x,to.y-from.y)
		var outward := Vector2(along.y,-along.x).normalized()
		var mid := Vector2(from.x+to.x,from.y+to.y)*.5
		if outward.dot(mid-middle)<0: outward = -outward
		if distance(mid+outward*cell*.7)>.0: continue
		_emit_wall(from,to,outward,vertices,normals,colors)

# A rough low stone: rings of shaken corners between two poles.
func _emit_lump(center: Vector3, half: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var seed_i := roundi(center.x*37.0)
	var seed_j := roundi(center.y*37.0)
	var rings := [Vector2(.92,.42),Vector2(.98,-.3)]
	var around := 6
	var points: Array = []
	for ring in range(rings.size()):
		var row: Array = []
		for k in range(around):
			var angle := TAU*(k+_hash(seed_i+k,seed_j+ring,7)*.5)/around
			var reach: float = rings[ring].x*(.84+_hash(seed_i+k,seed_j+ring,8)*.26)
			row.append(center+Vector3(cos(angle)*reach*half.x,float(rings[ring].y)*half.y,sin(angle)*reach*half.z))
		points.append(row)
	var top := center+Vector3(0,half.y,0)
	var bottom := center-Vector3(0,half.y*.8,0)
	for k in range(around):
		var next := (k+1)%around
		_emit_flat([top,points[0][k],points[0][next]],center,vertices,normals,colors)
		_emit_flat([points[0][k],points[1][k],points[1][next]],center,vertices,normals,colors)
		_emit_flat([points[0][k],points[1][next],points[0][next]],center,vertices,normals,colors)
		_emit_flat([points[1][k],bottom,points[1][next]],center,vertices,normals,colors)

func _emit_flat(triangle: Array, center: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var a: Vector3 = triangle[0]
	var b: Vector3 = triangle[1]
	var c: Vector3 = triangle[2]
	var normal := (c-a).cross(b-a).normalized()
	var middle := (a+b+c)/3.0
	if normal.dot(middle-center)<0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	if normal.z<-.2: return
	var color := facet_color(middle,normal)
	for point in [a,b,c]:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)

func _emit_wall(from: Vector3, to: Vector3, outward: Vector2, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var back_from := Vector3(from.x,from.y,BACK_Z)
	var back_to := Vector3(to.x,to.y,BACK_Z)
	var normal := Vector3(outward.x,outward.y,0)
	var color := facet_color((from+to+back_from+back_to)*.25,normal)
	var quad := [from,to,back_to,from,back_to,back_from]
	# Wound to face outwards.
	if (to-from).cross(back_to-from).dot(normal)>0: quad = [from,back_to,to,from,back_from,back_to]
	for point in quad:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)
