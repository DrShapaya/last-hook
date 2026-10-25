class_name SolidGeometry
extends RefCounted

const EPSILON := .00001
const BODY_HALF := Vector2(.38,.48)

static func polygon(object: Dictionary) -> PackedVector2Array:
	if object.has("polygon"):
		var points := PackedVector2Array()
		for point in object["polygon"]: points.append(point+object["pos"])
		return points
	var p: Vector2 = object["pos"]
	var h: Vector2 = object["dimensions"]*.5
	return PackedVector2Array([p-h,p+Vector2(h.x,-h.y),p+h,p+Vector2(-h.x,h.y)])

static func planes(object: Dictionary, padding: Vector2 = Vector2.ZERO) -> Array:
	var result: Array = []
	var packed := _packed_planes(object,padding)
	for plane in packed: result.append({"normal":Vector2(plane.x,plane.y),"offset":plane.z})
	return result

# Planes as (normal.x, normal.y, offset), cached on the object per padding.
# Casts run many times per physics step (body sweeps, edge probes, rope routing,
# hook forecasts), so the contour is derived once while it stays unchanged.
static func _packed_planes(object: Dictionary, padding: Vector2) -> PackedVector3Array:
	var cache: Dictionary = _cache(object)
	var by_padding: Dictionary = cache["planes"]
	if by_padding.has(padding): return by_padding[padding]
	var points: PackedVector2Array = cache["points"]
	var area := 0.0
	for i in range(points.size()): area += points[i].cross(points[(i+1)%points.size()])
	var winding := 1.0 if absf(area)<EPSILON else signf(area)
	var result := PackedVector3Array()
	for i in range(points.size()):
		var a := points[i]
		var edge := points[(i+1)%points.size()]-a
		var normal := Vector2(edge.y,-edge.x).normalized()*winding
		result.append(Vector3(normal.x,normal.y,normal.dot(a)+absf(normal.x)*padding.x+absf(normal.y)*padding.y))
	if padding!=Vector2.ZERO:
		# A box Minkowski sum also contributes its axis-aligned faces. Without
		# these, padding a triangle creates oversized invisible corner regions.
		for normal in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
			var offset := -INF
			for point in points: offset = maxf(offset,normal.dot(point))
			result.append(Vector3(normal.x,normal.y,offset+absf(normal.x)*padding.x+absf(normal.y)*padding.y))
	by_padding[padding] = result
	return result

# Contour points and bounding radius, rebuilt only when the solid changes.
static func _cache(object: Dictionary) -> Dictionary:
	var cache: Dictionary = object.get("_solid",{})
	var shape = object.get("polygon",null)
	if not cache.is_empty() and cache["pos"]==object["pos"] and cache["dimensions"]==object["dimensions"] and cache["polygon"]==shape:
		return cache
	var points := polygon(object)
	var center: Vector2 = object["pos"]
	var radius := 0.0
	for point in points: radius = maxf(radius,point.distance_to(center))
	cache = {"pos":center,"dimensions":object["dimensions"],"polygon":shape,"points":points,"radius":radius,"planes":{}}
	object["_solid"] = cache
	return cache

# Clip a swept point against a convex solid expanded by the player's box.
# This same contour is used for drawing, hook casts and rope contacts.
static func cast(from: Vector2, to: Vector2, object: Dictionary, padding: Vector2 = Vector2.ZERO, body_motion: bool = false) -> Dictionary:
	var delta := to-from
	var enter := 0.0
	var leave := 1.0
	var enter_normal := Vector2.ZERO
	var nearest_normal := Vector2.UP
	var nearest := -INF
	var inside := true
	var cache := _cache(object)
	# The padded solid lies within radius+|padding| of its centre: a sweep that
	# never comes that close cannot touch it.
	var reach: float = float(cache["radius"])+padding.length()+.01
	var center: Vector2 = cache["pos"]
	if Geometry2D.get_closest_point_to_segment(center,from,to).distance_squared_to(center)>reach*reach: return {}
	for plane in _packed_planes(object,padding):
		var normal := Vector2(plane.x,plane.y)
		var distance: float = normal.dot(from)-plane.z
		if distance>nearest:
			nearest = distance
			nearest_normal = normal
		if distance>EPSILON: inside = false
		var speed := normal.dot(delta)
		if absf(speed)<EPSILON:
			if distance>EPSILON: return {}
			continue
		var fraction := -distance/speed
		if speed<0:
			if fraction>enter:
				enter = fraction
				enter_normal = normal
		else:
			leave = minf(leave,fraction)
		if enter>leave+EPSILON: return {}
	if inside:
		# Resting contact and motion along/out of a face must not re-collide at
		# fraction zero. Actual initial overlap is resolved separately.
		if body_motion and nearest>=-.003 and delta.dot(nearest_normal)>=-EPSILON:
			return {}
		return {"fraction":0.0,"normal":nearest_normal,"depth":maxf(0,-nearest),"object":object}
	if enter<0 or enter>1 or leave<0: return {}
	return {"fraction":enter,"normal":enter_normal,"depth":0.0,"object":object}

static func corners(object: Dictionary, margin: float = .085) -> PackedVector2Array:
	# The cached planes are shared; the margin is applied to local copies.
	var boundary := _packed_planes(object,Vector2.ZERO)
	var points := PackedVector2Array()
	for i in range(boundary.size()):
		var a := boundary[(i-1+boundary.size())%boundary.size()]
		var b := boundary[i]
		var n := Vector2(a.x,a.y)
		var m := Vector2(b.x,b.y)
		var a_offset := a.z+margin
		var b_offset := b.z+margin
		var determinant := n.cross(m)
		if absf(determinant)<EPSILON: continue
		points.append(Vector2(a_offset*m.y-n.y*b_offset,n.x*b_offset-a_offset*m.x)/determinant)
	return points

static func contour_cast(from: Vector2, to: Vector2, object: Dictionary, radius: float = 0.0) -> Dictionary:
	# Rope and hook obstacle probes share a contour, with separate clearances.
	return cast(from,to,object,Vector2.ONE*maxf(0,radius),false)
