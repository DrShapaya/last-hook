class_name RockSurfaceHit
extends RefCounted

# Answer of the single surface query (MassifVisuals.surface_query): the
# frontmost rock mass at a gameplay point and the face of it seen there.
# Grips, shelves, finds, plants and crystals are mounted only from this.

var mass_id := -1
var mass: RockMassSpec
var position := Vector3.ZERO
var normal := Vector3.BACK
var tangent := Vector3.RIGHT
var depth := 0.0             # distance inside the mass silhouette
var surface_class := ""      # face, top, side, underside, inner_arch
var material_profile := ""
var curvature := 0.0
var exposure := 1.0
var mount_root := Vector3.INF

func valid() -> bool:
	return mass_id>=0
