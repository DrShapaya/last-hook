extends RefCounted

# Rest platforms are authored timber models (assets/models/platforms, built by
# tools/build_platform_models.gd): a plank deck whose back edge is the walking
# line, falling a touch towards the camera so its top reads as a lit strip,
# carried either by long timber braces down to a wall plate or by short knee
# braces from cleats on the rock.
# Model space: x along the face, y up (0 = walking line), z out of the face
# from the back plane (0) to the deck's front (DEPTH).

const DIR := "res://assets/models/platforms"
const STYLES := ["braced","bracket"]
const WIDTHS := [3.0,3.6,4.2,7.0]
const DEPTH := 1.0
const DECK_FALL := .12
# How far each style's supports reach below the walking line.
const DROP := {"braced":1.32,"bracket":.62}

static func model_path(style: String, width: float) -> String:
	return DIR.path_join("platform_%s_%d.glb" % [style,roundi(width*100)])

static func grain_path() -> String:
	return DIR.path_join("wood_grain.png")

# The authored width closest to a ledge; the model stretches the rest.
static func nearest_width(width: float) -> float:
	var best: float = WIDTHS[0]
	for candidate: float in WIDTHS:
		if absf(candidate-width)<absf(best-width): best = candidate
	return best

# The style whose supports fit the free stone under the ledge.
static func style_for(room_below: float) -> String:
	return "braced" if room_below>=float(DROP["braced"])+.12 else "bracket"

# An instance of the model for a ledge `width` wide, its parts dressed in the
# given materials ("wood", "iron", "rope").
static func instantiate(style: String, width: float, materials: Dictionary, shadows: bool) -> Node3D:
	var model := nearest_width(width)
	var scene := load(model_path(style,model)) as PackedScene
	var node := scene.instantiate() as Node3D
	node.name = "Деревянная площадка"
	node.scale.x = width/model
	node.set_meta("model",model_path(style,model))
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var part := str(mesh.name).to_lower()
		for key: String in materials:
			if part.begins_with(key): mesh.material_override = materials[key]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
