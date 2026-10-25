class_name RockMassSpec
extends RefCounted

# One rock mass of the mountain: a closed solid with its own faces, not a
# patch of a height field. Seen from the climbing camera (straight down -Z)
# it shows a faceted front, a bevel ring split by facing into a lit top,
# sides and a shaded underside, and, for arch pieces, an inner face towards
# the opening. A side wall closes the solid down to its back plane, so the
# mass casts a real shadow on whatever lies behind it.
#
# outer_contour is the silhouette in gameplay XY (convex, counter-clockwise).
# Depth lives in z_back / z_rim and in the raised inner ring and cap peaks.

const FACE := "face"
const TOP := "top"
const SIDE := "side"
const UNDERSIDE := "underside"
const INNER := "inner_arch"
const WALL := "wall"

var id := 0
var band := 0
var region := 0
var seed_stream := 0
var landform := "buttress"   # buttress, slab, overhang, arch, pillar, island, shelf, seat, rubble
var role := "trunk"
var outer_contour := PackedVector2Array()
var z_back := -3.2
var z_rim := -1.0
var inner_contour := PackedVector2Array()
var inner_z := PackedFloat32Array()
var cap_points := PackedVector3Array()
var cap_triangles := PackedInt32Array()
var top_edges := PackedInt32Array()
var bottom_edges := PackedInt32Array()
var side_edges := PackedInt32Array()
var inner_edges := PackedInt32Array()
# Arch pieces: edges whose outward normal points this way face the opening.
var inner_direction := Vector2.ZERO
var neighbors: Array[int] = []
var material_profile := ""
var tone := .5
# Lobes of one host share a group: one tone, no crease shade between them,
# so they fuse into a single body with a broken, concave outline.
var group := -1
# Sculpted front: when facet_size > 0 the cap is a field of facets about that
# size over a low dome (height `dome`) tilted by `slope` (z per metre), never
# in front of z_limit. Otherwise a few raised peaks (small pieces).
var facet_size := 0.0
var dome := 0.0
var slope := Vector2.ZERO
var z_limit := INF
var bounds := Rect2()
var front_z := 0.0
# Inward edge normals and offsets of the silhouette: signed distance.
var edge_normals := PackedVector2Array()
var edge_offsets := PackedFloat32Array()
# Every visible triangle: {"a","b","c": Vector3, "class": String, "edge": int}.
var faces: Array = []
# Indices of the non-wall faces by grid cell, built on the first surface
# query. Placing decor, mounts and hazard markers asks thousands of points,
# and each used to walk every face of the mass.
const FACE_CELL := .5
var _face_grid: Dictionary = {}

# Builds the faces from the contour. widths: inset of the bevel ring for a
# top, side and bottom edge; lifts: how far that ring stands in front of the
# rim; peaks: extra cap points raised by cap_rise. Inner edges (arch sides)
# use the side width with a deeper lift so the opening shows its wall.
func build(widths: Vector3, lifts: Vector3, peaks: int, cap_rise: float, random: RandomNumberGenerator) -> bool:
	var count := outer_contour.size()
	if count<3: return false
	_edges()
	var center := centroid()
	var inradius := INF
	for i in range(count): inradius = minf(inradius,edge_normals[i].dot(center)-edge_offsets[i])
	if inradius<=.05: return false
	inner_edges.clear()
	if inner_direction!=Vector2.ZERO:
		for i in range(count):
			if (-edge_normals[i]).dot(inner_direction.normalized())>.6: inner_edges.append(i)
	top_edges.clear()
	bottom_edges.clear()
	side_edges.clear()
	var insets := PackedFloat32Array()
	var rises := PackedFloat32Array()
	for i in range(count):
		var outward := -edge_normals[i]
		var inner := inner_edges.has(i)
		if outward.y>.45 and not inner:
			top_edges.append(i)
			insets.append(widths.x)
			rises.append(lifts.x)
		elif outward.y<-.45 and not inner:
			bottom_edges.append(i)
			insets.append(widths.z)
			rises.append(lifts.z)
		else:
			if not inner: side_edges.append(i)
			insets.append(widths.y)
			rises.append(lifts.y*(1.5 if inner else 1.0))
		insets[i] *= random.randf_range(.85,1.15)
		rises[i] *= random.randf_range(.85,1.15)
	# The ring stays a convex polygon well inside the silhouette.
	var limit := inradius*.62
	var largest := 0.0
	for value in insets: largest = maxf(largest,value)
	if largest>limit:
		for i in range(count): insets[i] *= limit/largest
	inner_contour.clear()
	inner_z.clear()
	for i in range(count):
		var previous := (i-1+count)%count
		var n0 := edge_normals[previous]
		var n1 := edge_normals[i]
		var o0 := edge_offsets[previous]+insets[previous]
		var o1 := edge_offsets[i]+insets[i]
		var determinant := n0.cross(n1)
		# Collinear edges (a split long side) share one offset line.
		var point: Vector2 = outer_contour[i]+n1*(insets[previous]+insets[i])*.5
		if absf(determinant)>.05: point = Vector2(o0*n1.y-n0.y*o1,n0.x*o1-o0*n1.x)/determinant
		inner_contour.append(point)
		# A little twist per corner breaks each bevel into two planes.
		inner_z.append(z_rim+(rises[previous]+rises[i])*.5*random.randf_range(.82,1.18))
	# The cap: the inner ring plus a few raised peaks, so the front breaks into
	# a handful of large planes of different tilt.
	cap_points.clear()
	var flat := PackedVector2Array()
	var crest := -INF
	for i in range(count):
		cap_points.append(Vector3(inner_contour[i].x,inner_contour[i].y,inner_z[i]))
		flat.append(inner_contour[i])
		crest = maxf(crest,inner_z[i])
	var inner_center := Vector2.ZERO
	for point in inner_contour: inner_center += point
	inner_center /= count
	if facet_size>0:
		_sculpt(flat,inner_center,random)
	else:
		for peak in range(peaks):
			var reach := .45 if peaks>1 else .2
			var corner: Vector2 = inner_contour[random.randi_range(0,count-1)]
			var at := inner_center.lerp(corner,random.randf_range(0,reach))+Vector2(random.randf_range(-.15,.15),random.randf_range(-.15,.15))
			if not Geometry2D.is_point_in_polygon(at,inner_contour): at = inner_center
			var duplicate := false
			for existing in flat: duplicate = duplicate or existing.distance_to(at)<.2
			if duplicate: continue
			cap_points.append(Vector3(at.x,at.y,minf(crest+cap_rise*random.randf_range(.6,1.0),z_limit)))
			flat.append(at)
	cap_triangles = Geometry2D.triangulate_delaunay(flat)
	if cap_triangles.is_empty(): return false
	faces.clear()
	_face_grid.clear()
	for t in range(0,cap_triangles.size(),3):
		faces.append({"a":cap_points[cap_triangles[t]],"b":cap_points[cap_triangles[t+1]],"c":cap_points[cap_triangles[t+2]],"class":FACE,"edge":-1})
	for i in range(count):
		var j := (i+1)%count
		var face_class := TOP if top_edges.has(i) else UNDERSIDE if bottom_edges.has(i) else INNER if inner_edges.has(i) else SIDE
		var o_i := Vector3(outer_contour[i].x,outer_contour[i].y,z_rim)
		var o_j := Vector3(outer_contour[j].x,outer_contour[j].y,z_rim)
		var i_i := cap_points[i]
		var i_j := cap_points[j]
		faces.append({"a":o_i,"b":o_j,"c":i_j,"class":face_class,"edge":i})
		faces.append({"a":o_i,"b":i_j,"c":i_i,"class":face_class,"edge":i})
		var b_i := Vector3(o_i.x,o_i.y,z_back)
		var b_j := Vector3(o_j.x,o_j.y,z_back)
		faces.append({"a":b_i,"b":b_j,"c":o_j,"class":WALL,"edge":i})
		faces.append({"a":b_i,"b":o_j,"c":o_i,"class":WALL,"edge":i})
	front_z = z_rim
	for point in cap_points: front_z = maxf(front_z,point.z)
	bounds = Rect2(outer_contour[0],Vector2.ZERO)
	for point in outer_contour: bounds = bounds.expand(point)
	return true

func _sculpt(flat: PackedVector2Array, inner_center: Vector2, random: RandomNumberGenerator) -> void:
	# Facets of uneven size over a low tilted dome: jittered staggered grid
	# points inside the ring, raised by their distance from it. Delaunay then
	# gives large and small planes of different direction, like split rock.
	var count := inner_contour.size()
	var ring_mean := 0.0
	for z in inner_z: ring_mean += z
	ring_mean /= maxf(1,count)
	var radius := INF
	var box := Rect2(inner_contour[0],Vector2.ZERO)
	for i in range(count):
		box = box.expand(inner_contour[i])
		radius = minf(radius,Geometry2D.get_closest_point_to_segment(inner_center,inner_contour[i],inner_contour[(i+1)%count]).distance_to(inner_center))
	radius = maxf(radius,.2)
	var step := facet_size
	var row := 0
	var y := box.position.y+step*.5
	while y<box.end.y:
		var x := box.position.x+step*(.35 if row%2==0 else .85)
		while x<box.end.x:
			var size := step*random.randf_range(.75,1.3)
			var at := Vector2(x,y)+Vector2(random.randf_range(-.3,.3),random.randf_range(-.3,.3))*step
			x += size
			if not Geometry2D.is_point_in_polygon(at,inner_contour): continue
			var edge := INF
			for i in range(count): edge = minf(edge,Geometry2D.get_closest_point_to_segment(at,inner_contour[i],inner_contour[(i+1)%count]).distance_to(at))
			if edge<step*.35: continue
			# A spherical cap over the ring: the face keeps turning all the way
			# to the crown, so every facet of a boulder catches its own light.
			var t := clampf(edge/radius,0,1)
			var z := ring_mean+dome*sqrt(1.0-(1.0-t)*(1.0-t))+slope.dot(at-inner_center)+random.randf_range(-.16,.16)*maxf(dome,.2)
			cap_points.append(Vector3(at.x,at.y,minf(z,z_limit)))
			flat.append(at)
		y += step*.86
		row += 1

func _edges() -> void:
	# Contour counter-clockwise; normals point inwards.
	var area := 0.0
	var count := outer_contour.size()
	for i in range(count): area += outer_contour[i].cross(outer_contour[(i+1)%count])
	if area<0: outer_contour.reverse()
	edge_normals.clear()
	edge_offsets.clear()
	for i in range(count):
		var a := outer_contour[i]
		var b := outer_contour[(i+1)%count]
		var n := Vector2(-(b-a).y,(b-a).x).normalized()
		edge_normals.append(n)
		edge_offsets.append(n.dot(a))

func centroid() -> Vector2:
	var center := Vector2.ZERO
	for point in outer_contour: center += point
	return center/maxf(1,outer_contour.size())

# Signed distance to the silhouette: positive inside, straight edges.
func inside(point: Vector2) -> float:
	var result := INF
	for i in range(edge_normals.size()):
		result = minf(result,edge_normals[i].dot(point)-edge_offsets[i])
	return result

# Front surface of this mass at a point, or {} outside its silhouette.
func surface_at(point: Vector2) -> Dictionary:
	if not bounds.grow(.01).has_point(point) or inside(point)<-.0001: return {}
	if _face_grid.is_empty(): _build_face_grid()
	# Candidates in ascending face order: the first face holding the point
	# wins, exactly as a walk over all faces.
	for index in _face_grid.get(Vector2i((point/FACE_CELL).floor()),PackedInt32Array()):
		var face: Dictionary = faces[index]
		var a: Vector3 = face["a"]
		var b: Vector3 = face["b"]
		var c: Vector3 = face["c"]
		var weights := _barycentric(point,Vector2(a.x,a.y),Vector2(b.x,b.y),Vector2(c.x,c.y))
		if weights.x<-.0001 or weights.y<-.0001 or weights.z<-.0001: continue
		var normal := (b-a).cross(c-a).normalized()
		if normal.z<0: normal = -normal
		return {"z":a.z*weights.x+b.z*weights.y+c.z*weights.z,"normal":normal,"class":face["class"],"edge":face["edge"]}
	return {}

func _build_face_grid() -> void:
	for index in range(faces.size()):
		var face: Dictionary = faces[index]
		if face["class"]==WALL: continue
		var a: Vector3 = face["a"]
		var b: Vector3 = face["b"]
		var c: Vector3 = face["c"]
		# A hair wider than the triangle: the point test accepts a tiny margin.
		var low := (Vector2(minf(a.x,minf(b.x,c.x)),minf(a.y,minf(b.y,c.y)))-Vector2.ONE*.002)/FACE_CELL
		var high := (Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.y,maxf(b.y,c.y)))+Vector2.ONE*.002)/FACE_CELL
		for x in range(int(floor(low.x)),int(floor(high.x))+1):
			for y in range(int(floor(low.y)),int(floor(high.y))+1):
				var cell := Vector2i(x,y)
				if not _face_grid.has(cell): _face_grid[cell] = PackedInt32Array()
				var list: PackedInt32Array = _face_grid[cell]
				list.append(index)
				_face_grid[cell] = list
	if _face_grid.is_empty(): _face_grid[Vector2i(1<<30,1<<30)] = PackedInt32Array()

static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b-a
	var v1 := c-a
	var v2 := p-a
	var d := v0.x*v1.y-v1.x*v0.y
	if absf(d)<.0000001: return Vector3(-1,-1,-1)
	var u := (v2.x*v1.y-v1.x*v2.y)/d
	var v := (v0.x*v2.y-v2.x*v0.y)/d
	return Vector3(1.0-u-v,u,v)

# A boulder of the reference: a squarish ellipse (superellipse) of 10-14
# corners with uneven radii and corner spacing, so it reads as one rounded
# cushion of rock with short straight facets on its rim, never a box. The
# foot is a little flatter than the crown. Always convex (build() needs it).
# fullness: superellipse exponent range; higher keeps fuller corners, for
# pieces that must carry a gameplay object's whole box.
static func boulder_contour(center: Vector2, size: Vector2, random: RandomNumberGenerator, turn: float = 0.0, fullness: Vector2 = Vector2(2.2,2.9)) -> PackedVector2Array:
	var half := size*.5
	var count := random.randi_range(10,14) if minf(size.x,size.y)>1.8 else random.randi_range(7,9)
	var exponent := random.randf_range(fullness.x,fullness.y)
	var phase := random.randf()*TAU/count
	var points := PackedVector2Array()
	for k in range(count):
		var angle := phase+TAU*(k+random.randf_range(-.2,.2))/count
		var c := cos(angle)
		var s := sin(angle)
		var radius := 1.0/pow(pow(absf(c),exponent)+pow(absf(s),exponent),1.0/exponent)
		var point := Vector2(c*half.x,s*half.y)*radius*random.randf_range(.98,1.09)
		if point.y<0: point.y *= .9
		points.append(center+point.rotated(turn))
	var hull := Geometry2D.convex_hull(points)
	if hull.size()>1 and hull[0]==hull[-1]: hull.remove_at(hull.size()-1)
	return hull

# A blocky convex contour: a rotated, slightly skewed box whose four corners
# are cut by different amounts, so masses read as broken blocks with long
# straight edges instead of round capsules.
static func block_contour(center: Vector2, size: Vector2, random: RandomNumberGenerator, turn: float = 0.0, chamfer: float = .38) -> PackedVector2Array:
	var half := size*.5
	var corners := [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y)]
	var skew := random.randf_range(-.26,.26)
	var points := PackedVector2Array()
	var shortest := minf(size.x,size.y)
	for i in range(4):
		var corner: Vector2 = corners[i]
		var previous: Vector2 = corners[(i+3)%4]
		var next: Vector2 = corners[(i+1)%4]
		# Some corners stay sharp, others are broken off hard.
		var cut := 0.02 if random.randf()<.3 else shortest*random.randf_range(.06,chamfer)
		var into_previous := (previous-corner).normalized()*cut*random.randf_range(.6,1.4)
		var into_next := (next-corner).normalized()*cut*random.randf_range(.6,1.4)
		for point in [corner+into_previous,corner+into_next]:
			var p: Vector2 = point
			p.x += p.y*skew
			points.append(center+p.rotated(turn))
	var hull := Geometry2D.convex_hull(points)
	if hull.size()>1 and hull[0]==hull[-1]: hull.remove_at(hull.size()-1)
	# Long sides break once with a slight outward kink: more, smaller bevel
	# planes, still a convex block.
	var result := PackedVector2Array()
	var middle := Vector2.ZERO
	for point in hull: middle += point
	middle /= maxf(1,hull.size())
	for i in range(hull.size()):
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i+1)%hull.size()]
		result.append(a)
		var outward := Vector2(-(b-a).y,(b-a).x).normalized()
		if outward.dot((a+b)*.5-middle)<0: outward = -outward
		var pieces := int(a.distance_to(b)/1.6)
		for piece in range(1,pieces+1):
			var t := (piece+random.randf_range(-.3,.3))/(pieces+1)
			result.append(a.lerp(b,t)+outward*random.randf_range(.02,.16)*minf(1.0,a.distance_to(b)/4.0))
	var convex := Geometry2D.convex_hull(result)
	if convex.size()>1 and convex[0]==convex[-1]: convex.remove_at(convex.size()-1)
	return convex
