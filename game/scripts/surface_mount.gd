class_name SurfaceMount
extends RefCounted

# Where and how an object is set into the mountain. Grips, shelves, crystals,
# grass, scree and finds all take their depth, tilt and socket from the same
# mount, so a detail can never stand at another depth than the stone it grows
# from. Visual only: gameplay stays in the XY plane.

var position := Vector3.ZERO      # point on the stone face
var normal := Vector3.BACK        # face normal at the point
var tangent := Vector3.RIGHT      # along the face, horizontal
var depth := .3                   # how deep the object is set into the stone
var support_root := Vector3.INF   # where the body of the mountain holds it
var cavity_scale := Vector2.ONE   # half size of the socket around the object
var exposure := 1.0               # 1 open to the sky above, 0 under rock
var curvature := 0.0              # > 0 convex knob, < 0 hollow
var biome_material := ""
var profile: GripBiomeProfile

func wall_z() -> float:
	return position.z

# A small tilt that follows the face without moving the silhouette far from
# the gameplay polygon.
func tilt(limit: float = .12) -> Vector3:
	return Vector3(-clampf(normal.y,-1,1)*limit,clampf(normal.x,-1,1)*limit,0)

func downhill() -> Vector2:
	var slope := Vector2(normal.x*normal.y,-(1.0-normal.y*normal.y))
	return slope.normalized() if slope.length_squared()>.0001 else Vector2.DOWN
