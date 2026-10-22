class_name GripVisualSpec
extends RefCounted

# The visible volume of a grip, apart from its gameplay polygon. The polygon
# stays the hitbox and catch footprint; this descriptor only shapes the rock
# outcrop that juts out of the host face. Local axes of the outcrop:
#   X across the front face, Y up, Z out of the mountain along socket_normal.
# z = 0 is the host face, z < 0 is inside the rock, z = protrusion the front.
#
# The camera looks straight down -Z, so only what faces it reads: the
# silhouette, a top face sloping towards the camera (it carries the paint),
# flanks and an underside running back into the host rock. The outcrop is
# therefore much taller than the hitbox: its top lies on the hitbox top, its
# body drops below into the mountain (as far as the room below allows).

var visual_family := "stone"
var front_width := 1.6        # widest visible width of the outcrop
var front_height := .8        # top to bottom of the outcrop
var top_depth := .3           # how far the top face runs back from the front edge
var side_depth := .4          # protrusion of the front face out of the host face
var back_embed := .25         # how deep the outcrop runs into the host rock
var chamfer := .1             # corner cut of the top corners
var facet_count := 4          # large planes on the front face
var top_band_height := .16    # visible height of the top face (it carries the paint)
var under_height := .25       # visible height of the underside under the front face
var crack_pattern := "corners"
# Paint on the top face: colour, share of the width, wear amount.
var paint_profile := {"color":Color("e9a63a"),"width":.8,"wear":.15}
var rear_scale := .88         # rear footprint relative to the silhouette
var seed_value := 0
var bulge := .1               # how far the large facets rise over the front plane
# One or two cracks break the outcrop into stones; split_x is the main one.
var split := false
var split_x := 0.0
var cracks: Array[float] = []
# Silhouette (counter-clockwise from the top-left corner in screen terms) and
# the front face's rim, inset from it: the bands between them are the top
# face, the flanks and the underside.
var outline := PackedVector2Array()
var front := PackedVector2Array()
# Indices of the outline points that form the top edge.
var top_left := 0
var top_right := 1

# Per-type proportions: [width x W, drop below the hitbox (m), protrusion (m),
# top face (m), underside (m), bottom narrowing, facets].
const SHAPES := {
	"stone":[1.18,.42,.92,.30,.16,.92,8],
	"root":[1.16,.40,.86,.28,.17,.88,8],
	"spring":[1.20,.38,.94,.32,.15,.86,7],
	"ice":[1.18,.36,.88,.28,.14,.94,5],
	"crystal":[1.14,.44,.90,.28,.16,.90,9],
}
const FAMILIES := ["stone","root","spring","ice","crystal"]
# Lowest drop of the body below the hitbox, even in a tight spot.
const MIN_DROP := .22

static func for_grip(object: Dictionary, profile: GripBiomeProfile, room_below: float = INF) -> GripVisualSpec:
	var spec := GripVisualSpec.new()
	var kind := GripSpec.kind_of(object)
	var dimensions: Vector2 = object.get("dimensions",Vector2(1.6,.65))
	var w := dimensions.x
	var h := dimensions.y
	spec.visual_family = FAMILIES[kind]
	spec.seed_value = int(object.get("id",0))
	var random := RandomNumberGenerator.new()
	random.seed = spec.seed_value*48271+kind*977+11
	var shape: Array = SHAPES[spec.visual_family]
	spec.front_width = w*float(shape[0])*random.randf_range(.97,1.04)
	var drop := clampf(float(shape[1])*random.randf_range(.8,1.2)*(.8+w*.12),MIN_DROP,maxf(MIN_DROP,room_below))
	spec.front_height = h+.05+drop
	spec.side_depth = float(shape[2])*random.randf_range(.92,1.06)
	spec.back_embed = .42
	spec.top_band_height = float(shape[3])*random.randf_range(.9,1.1)
	spec.top_depth = spec.side_depth
	spec.under_height = minf(float(shape[4])*random.randf_range(.85,1.15),drop*.6+.1)
	spec.chamfer = minf(w,h)*.22
	spec.facet_count = int(shape[6])
	spec.rear_scale = random.randf_range(.86,.90)
	spec.bulge = random.randf_range(.07,.12)
	# Most outcrops break into two or three stones; ice stays one piece.
	spec.split = kind!=GripSpec.ICE and random.randf()<.85
	spec.split_x = w*random.randf_range(-.18,.18)
	if spec.split:
		spec.cracks.append(spec.split_x)
		if w>=1.5 and random.randf()<.5:
			var side := 1.0 if spec.split_x<0 else -1.0
			spec.cracks.append(spec.split_x+side*w*random.randf_range(.32,.42))
	spec.crack_pattern = "deep" if kind==GripSpec.ROOT else "vein" if kind==GripSpec.CRYSTAL else "corners"
	spec.paint_profile = {"color":profile.paint_color(kind),"width":random.randf_range(.78,.88)*w/spec.front_width,"wear":random.randf_range(.10,.18)}
	spec._build_outline(random,h,float(shape[5]))
	return spec

func _build_outline(random: RandomNumberGenerator, h: float, narrowing: float) -> void:
	# A broken rock mass seen from the front: a broad top edge with its own
	# slope just above the hitbox, unequal cut corners, flanks with a step,
	# and a lopsided, narrower underside - never an oval or a slab.
	var shift := front_width*random.randf_range(-.06,.06)
	var left := -front_width*.5+shift
	var right := front_width*.5+shift
	var top := h*.5+.05
	var bottom := top-front_height
	var slope := random.randf_range(-.04,.04)
	var cut_left := chamfer*random.randf_range(.8,1.4)
	var cut_right := chamfer*random.randf_range(.7,1.3)
	var span := right-left
	# The top edge in three or four pieces, so the top face breaks into
	# several planes instead of one flat panel.
	var points: Array[Vector2] = [Vector2(left+cut_left,top-slope)]
	var pieces := random.randi_range(3,4)
	for piece in range(1,pieces):
		var t := (piece+random.randf_range(-.2,.2))/pieces
		points.append(Vector2(lerpf(left+cut_left,right-cut_right,t),top+slope*(2.0*t-1.0)+random.randf_range(-.025,.02)))
	points.append(Vector2(right-cut_right,top+slope))
	var last_top := points.size()-1
	points.append_array([
		Vector2(right,top-cut_right*random.randf_range(.8,1.2)),
		Vector2(right+span*random.randf_range(-.01,.02),minf(top-front_height*random.randf_range(.34,.46),top-cut_right*1.3-.06)),
		Vector2(right-span*random.randf_range(.02,.07),top-front_height*random.randf_range(.7,.8)),
		Vector2(lerpf(left,right,.5+narrowing*random.randf_range(.4,.47)),bottom+front_height*random.randf_range(.05,.14)),
		Vector2(lerpf(left,right,random.randf_range(.5,.66)),bottom),
		Vector2(lerpf(left,right,random.randf_range(.3,.42)),bottom+front_height*random.randf_range(.0,.05)),
		Vector2(lerpf(left,right,.5-narrowing*random.randf_range(.42,.5)),bottom+front_height*random.randf_range(.1,.2)),
		Vector2(left+span*random.randf_range(.0,.05),top-front_height*random.randf_range(.58,.7)),
		Vector2(left,minf(top-front_height*random.randf_range(.24,.36),top-cut_left*1.3-.06)),
		Vector2(left,top-cut_left*random.randf_range(.8,1.2)),
	])
	if visual_family=="root":
		# A fresh break on the lower left: one more notch on the flank.
		var below: Vector2 = points[last_top+7]
		var above: Vector2 = points[last_top+8]
		points.insert(last_top+8,Vector2(minf(below.x,above.x)+span*.08,lerpf(below.y,above.y,.5)))
	# Round the flanks and the underside a little: a bulging point on every
	# edge but the top one, kept inside the outcrop's width and height.
	var rounded: Array[Vector2] = []
	for index in range(points.size()):
		var a := points[index]
		var b := points[(index+1)%points.size()]
		rounded.append(a)
		if index<last_top: continue
		var normal := Vector2(a.y-b.y,b.x-a.x).normalized()
		var push := minf(.05,a.distance_to(b)*.08)*random.randf_range(.3,1.0)
		var mid := (a+b)*.5+normal*push
		rounded.append(Vector2(clampf(mid.x,left-span*.03,right+span*.03),maxf(mid.y,bottom)))
	outline = PackedVector2Array(rounded)
	if crosses(outline): outline = PackedVector2Array(points)
	top_left = 0
	top_right = last_top
	# The front face's rim: each silhouette point pulled towards the centre by
	# its own amount (here the front runs out almost to a sharp edge, there a
	# broad flank turns in - never a frame of one width), then the whole rim
	# fitted between the top face and the underside. Both steps keep the rim
	# a simple polygon.
	var center := Vector2((left+right)*.5,(top+bottom)*.5)
	var pulled := PackedVector2Array()
	var low_y := INF
	var high_y := -INF
	for index in range(outline.size()):
		var k := random.randf_range(.95,.99) if random.randf()<.4 else random.randf_range(.8,.9)
		var point := center+(outline[index]-center)*Vector2(k,1.0)
		pulled.append(point)
		low_y = minf(low_y,point.y)
		high_y = maxf(high_y,point.y)
	var rim_top := top-top_band_height
	var rim_low := bottom+under_height
	front = PackedVector2Array()
	for point in pulled:
		front.append(Vector2(point.x,lerpf(rim_low,rim_top,(point.y-low_y)/maxf(.01,high_y-low_y))))

# True when two edges of a closed polygon cross each other.
static func crosses(polygon: PackedVector2Array) -> bool:
	var n := polygon.size()
	for i in range(n):
		for j in range(i+2,n):
			if i==0 and j==n-1: continue
			if Geometry2D.segment_intersects_segment(polygon[i],polygon[(i+1)%n],polygon[j],polygon[(j+1)%n])!=null: return true
	return false

# The outline at another depth: smaller round its centre, the top edge kept
# level, so the outcrop runs back into the rock without a gap.
func ring(scale: float, sink: float = 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var top := outline[top_left].y
	var middle := 0.0
	for point in outline: middle += point.x
	middle /= outline.size()
	for point in outline:
		result.append(Vector2(middle+(point.x-middle)*scale,top-(top-point.y)*scale-sink))
	return result

func front_ring() -> PackedVector2Array:
	return front

func protrusion() -> float:
	return side_depth

# Depth of the silhouette: the flanks stand out a third of the way, the top
# and the underside meet the host face almost flush.
func shoulder() -> float:
	return side_depth*.35

func bounds() -> Rect2:
	var rect := Rect2(outline[0],Vector2.ZERO)
	for point in outline: rect = rect.expand(point)
	return rect
