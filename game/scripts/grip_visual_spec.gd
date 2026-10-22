class_name GripVisualSpec
extends RefCounted

# The visible volume of a grip, apart from its gameplay polygon. The polygon
# stays the hitbox and catch footprint; this descriptor only shapes the stone
# block that juts out of the host rock. Local axes of the block:
#   X across the front face, Y up, Z out of the mountain along socket_normal.
# z = 0 is the host face, z < 0 is inside the rock, z = protrusion the front.

var visual_family := "stone"
var front_width := 1.6        # widest visible width of the block
var front_height := .8        # top to bottom of the block
var top_depth := .3           # depth of the flat top before the painted chamfer
var side_depth := .4          # protrusion of the block out of the host face
var back_embed := .25         # how deep the block runs into the host rock
var chamfer := .1             # corner cut of the front face
var facet_count := 4          # large planes on the front face
var top_band_height := .16    # height of the painted top-front chamfer
var crack_pattern := "corners"
# Paint on the top-front chamfer: colour, share of the width, wear amount.
var paint_profile := {"color":Color("e9a63a"),"width":.8,"wear":.15}
var rear_scale := .88         # rear footprint relative to the front outline
var seed_value := 0
# Front outline (6-10 points, counter-clockwise from the top-left corner).
var outline := PackedVector2Array()
# Indices of the outline points that form the flat top edge.
var top_left := 0
var top_right := 1

# Per-type proportions, all inside the ranges of the visual contract:
# [width x W, height x H, protrusion x H, embed x H, band x H, top x H, chamfer x min(W,H),
#  bottom narrowing, facets]
const SHAPES := {
	"stone":[1.10,1.28,.66,.40,.20,.26,.12,.80,4],
	"root":[1.08,1.24,.60,.42,.20,.22,.15,.74,5],
	"spring":[1.16,1.20,.70,.38,.22,.28,.10,.64,4],
	"ice":[1.12,1.30,.64,.36,.18,.22,.16,.84,3],
	"crystal":[1.06,1.35,.62,.46,.18,.24,.10,.72,6],
}
const FAMILIES := ["stone","root","spring","ice","crystal"]

static func for_grip(object: Dictionary, profile: GripBiomeProfile) -> GripVisualSpec:
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
	spec.front_width = w*float(shape[0])*random.randf_range(.98,1.02)
	spec.front_height = h*float(shape[1])*random.randf_range(.97,1.03)
	spec.side_depth = h*float(shape[2])
	spec.back_embed = h*float(shape[3])
	spec.top_band_height = h*float(shape[4])
	spec.top_depth = h*float(shape[5])
	spec.chamfer = minf(w,h)*float(shape[6])
	spec.facet_count = int(shape[8])
	spec.rear_scale = random.randf_range(.86,.90)
	spec.crack_pattern = "deep" if kind==GripSpec.ROOT else "vein" if kind==GripSpec.CRYSTAL else "corners"
	spec.paint_profile = {"color":profile.paint_color(kind),"width":random.randf_range(.76,.86)*w/spec.front_width,"wear":random.randf_range(.10,.18)}
	spec._build_outline(random,float(shape[7]))
	return spec

func _build_outline(random: RandomNumberGenerator, narrowing: float) -> void:
	# A broken block seen from the front: a broad, nearly level top edge with
	# its own slope, unequal cut corners, flanks that bulge a little and a
	# narrower underside with a chipped corner - never an oval or a wedge.
	var hw := front_width*.5
	var top := front_height*.5
	var bottom := -front_height*.5
	var slope := random.randf_range(-.05,.05)
	var cut_left := chamfer*random.randf_range(.8,1.3)
	var cut_right := chamfer*random.randf_range(.7,1.2)
	var low := hw*narrowing
	var points: Array[Vector2] = [
		Vector2(-hw+cut_left,top-slope*hw),
		Vector2(hw-cut_right,top+slope*hw),
		Vector2(hw,top-cut_right*random.randf_range(.9,1.3)),
		Vector2(hw*random.randf_range(.95,1.0),top-front_height*random.randf_range(.50,.58)),
		Vector2(low+hw*random.randf_range(.0,.08),bottom+front_height*random.randf_range(.08,.16)),
		Vector2(low*random.randf_range(.25,.45),bottom),
		Vector2(-low*random.randf_range(.35,.55),bottom+front_height*random.randf_range(.0,.04)),
		Vector2(-low-hw*random.randf_range(0,.06),bottom+front_height*random.randf_range(.10,.18)),
		Vector2(-hw*random.randf_range(.94,1.0),top-front_height*random.randf_range(.46,.56)),
		Vector2(-hw,top-cut_left*random.randf_range(.9,1.4)),
	]
	if visual_family=="root":
		# A fresh break on the lower left: one more notch on the flank.
		points.insert(7,Vector2(-hw*.82,bottom+front_height*.32))
	elif visual_family=="ice":
		# Ice rounds the lower corners off.
		points.insert(5,Vector2(hw*.38,bottom+front_height*.03))
	outline = PackedVector2Array(points)
	top_left = 0
	top_right = 1

# The outline at another depth: narrower and shorter from below, with the
# top edge kept level, so the top face runs flat back into the rock.
func ring(scale: float, sink: float = 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var top := outline[top_left].y
	for point in outline:
		result.append(Vector2(point.x*scale,top-(top-point.y)*scale-sink))
	return result

# Front face: the outline cut back by the chamfer on every side and lowered
# by the painted band along the top.
func front_ring() -> PackedVector2Array:
	var result := PackedVector2Array()
	var top := outline[top_left].y
	for index in range(outline.size()):
		var point := outline[index]
		var inset := Vector2(point.x-signf(point.x)*chamfer*.55,point.y)
		if index==top_left or index==top_right:
			inset.y = point.y-top_band_height
		elif point.y>top-top_band_height*1.2:
			inset.y = minf(point.y,top-top_band_height*1.05)
		else:
			inset.y = point.y+(chamfer*.5 if point.y<0 else -chamfer*.2)
		result.append(inset)
	return result

func protrusion() -> float:
	return side_depth

# Depth at which the full silhouette is reached; the top face lies behind it.
func shoulder() -> float:
	return side_depth-top_depth*.45

func bounds() -> Rect2:
	var rect := Rect2(outline[0],Vector2.ZERO)
	for point in outline: rect = rect.expand(point)
	return rect
