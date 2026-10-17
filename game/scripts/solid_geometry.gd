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
	var points := polygon(object)
	var area := 0.0
	for i in range(points.size()): area += points[i].cross(points[(i+1)%points.size()])
	var result: Array = []
	for i in range(points.size()):
		var a := points[i]
		var edge := points[(i+1)%points.size()]-a
		var normal := Vector2(edge.y,-edge.x).normalized()*signf(area)
		result.append({"normal":normal,"offset":normal.dot(a)+absf(normal.x)*padding.x+absf(normal.y)*padding.y})
	if padding!=Vector2.ZERO:
		# A box Minkowski sum also contributes its axis-aligned faces. Without
		# these, padding a triangle creates oversized invisible corner regions.
		for normal in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
			var offset := -INF
			for point in points: offset = maxf(offset,normal.dot(point))
			result.append({"normal":normal,"offset":offset+absf(normal.x)*padding.x+absf(normal.y)*padding.y})
	return result

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
	for plane in planes(object,padding):
		var normal: Vector2 = plane["normal"]
		var distance: float = normal.dot(from)-plane["offset"]
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
	var boundary := planes(object)
	for plane in boundary: plane["offset"] += margin
	var points := PackedVector2Array()
	for i in range(boundary.size()):
		var a: Dictionary = boundary[(i-1+boundary.size())%boundary.size()]
		var b: Dictionary = boundary[i]
		var n: Vector2 = a["normal"]
		var m: Vector2 = b["normal"]
		var determinant := n.cross(m)
		if absf(determinant)<EPSILON: continue
		points.append(Vector2(a["offset"]*m.y-n.y*b["offset"],n.x*b["offset"]-a["offset"]*m.x)/determinant)
	return points
