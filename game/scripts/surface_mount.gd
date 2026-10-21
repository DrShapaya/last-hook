class_name SurfaceMount
extends RefCounted

# Where and how an object is set into the mountain. Grips, shelves, hazards,
# finds, crystals, grass and scree all take their depth, tilt and socket from
# the same mount, so a detail can never stand at another depth than the stone
# it grows from. Visual only: gameplay stays in the XY plane, and the mount
# keeps the layout point it was made for without ever moving it.
#
# Contract of a mounted object, front to back (holder space, +Z to camera):
#   top edge   lit lip on the faces turned up (contour / bevel tint)
#   front face the object's own material, inside its gameplay outline
#   side face  the outcrop bevel from the rim back to the wall
#   under face the skirt below the object, darker, receding into the stone
#   contact    socket ring + contact shade on the wall plane (wall_local())

var layout_point := Vector2.ZERO  # gameplay coordinate the mount belongs to
var position := Vector3.ZERO      # point on the stone face
var normal := Vector3.BACK        # face normal at the point
var tangent := Vector3.RIGHT      # along the face, horizontal
var depth := .3                   # how deep the object is set into the stone
var standoff := .3                # holder distance in front of the face
var support_root := Vector3.INF   # where the body of the mountain holds it
var cavity_scale := Vector2.ONE   # half size of the socket around the object
var exposure := 1.0               # 1 open to the sky above, 0 under rock
var curvature := 0.0              # > 0 convex knob, < 0 hollow
var surface_color := Color.GRAY   # host stone around the socket
var chip_color := Color.GRAY      # fresh break of the same stone
var biome_material := ""
var profile: GripBiomeProfile
# Host of the object on a rock-mass mountain (RockSurfaceHit): which mass,
# which of its faces, where the socket opens and how deep the object sits.
var host_mass := -1
var surface_class := ""
var socket_center := Vector3.INF
var socket_normal := Vector3.BACK
var embed_depth := 0.0
var contact_bounds := Rect2()
var material_profile := ""

func wall_z() -> float:
	return position.z

# Holder origin: the layout point, set off the face by the standoff.
func holder_position() -> Vector3:
	return Vector3(layout_point.x,layout_point.y,position.z+standoff)

# The wall plane in holder space: sockets, skirts and contact shade sit here.
func wall_local() -> float:
	return -standoff

# Shade from rock overhanging the mount: 0 open sky above, 1 fully covered.
func overhang() -> float:
	return 1.0-exposure

# A small tilt that follows the face without moving the silhouette far from
# the gameplay polygon.
func tilt(limit: float = .12) -> Vector3:
	return Vector3(-clampf(normal.y,-1,1)*limit,clampf(normal.x,-1,1)*limit,0)

func downhill() -> Vector2:
	var slope := Vector2(normal.x*normal.y,-(1.0-normal.y*normal.y))
	return slope.normalized() if slope.length_squared()>.0001 else Vector2.DOWN

# Everything that decides the built geometry; equal seeds give equal values.
func signature() -> Array:
	return [layout_point,position,normal,depth,standoff,support_root,cavity_scale,exposure,curvature,surface_color,chip_color,biome_material,host_mass,surface_class,socket_center,embed_depth,contact_bounds]
