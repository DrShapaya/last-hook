extends RefCounted

# Rest platforms are authored timber models (assets/models/platforms, built by
# tools/build_platform_models.gd): a plank deck whose back edge is the walking
# line, falling a touch towards the camera so its top reads as a lit strip,
# carried either by long timber braces down to a wall plate or by short knee
# braces from cleats on the rock.
# Model space: x along the face, y up (0 = walking line), z out of the face
# from the back plane (0) to the deck's front (DEPTH).
# Every location shares the models (sizes and seating never change) and
# dresses them its own way (docs/LEVEL_OBJECTS_PLAN.md, stage 4): LOOKS tints
# the light base tones of wood, iron and rope, and each model carries every
# location's dressing as parts, of which only the location's own stay.

const DIR := "res://assets/models/platforms"
const STYLES := ["braced","bracket"]
const WIDTHS := [3.0,3.6,4.2,7.0]
const DEPTH := 1.0
const DECK_FALL := .12
# How far the boards reach past a ledge's left and right ends. The physics
# carries the hero exactly as far (mountain_world.move_player), so the hero
# never stands on air beside the boards.
const OVERHANG := .12
# How far each style's supports reach below the walking line.
const DROP := {"braced":1.32,"bracket":.62}
# Parts of a model, by mesh name. The timber itself, then the dressing.
const PARTS := ["wood","iron","nail","rope","snow","ice","sand","moss","vine"]
const TIMBER := ["wood","iron","nail","rope"]
# Each location's tint of the base tones and the dressing it keeps; "detail"
# parts go on the battery preset (with the nails).
const LOOKS := {
	# Warm boards, moss and grass along the front, a vine.
	"summer":{"wood":Color("c4a088"),"iron":Color("5a524c"),"rope":Color("d6bb8a"),"dress":["moss","vine"],"detail":["vine"]},
	# Sun-bleached pale boards, pale rope, sand drifted against the rock.
	"desert":{"wood":Color("e8cfae"),"iron":Color("6e6258"),"rope":Color("e8dcc0"),"dress":["sand"],"detail":[]},
	# Dark wet boards under a thick snow cap, slate iron, blue rope, icicles.
	"winter":{"wood":Color("8a6650"),"iron":Color("5f6e86"),"rope":Color("3a5aa8"),"dress":["snow","ice"],"detail":["ice"]},
}

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

static func part_of(mesh: MeshInstance3D) -> String:
	var name := str(mesh.name).to_lower()
	for part: String in PARTS:
		if name.begins_with(part): return part
	return ""

# An instance of the model for a ledge `width` wide, its parts dressed in the
# given materials (by part name), keeping the dressing of `look` (a key of
# LOOKS, or "" for bare timber). Without `detail` the nails and the look's
# small pieces go, so the battery preset draws no more than bare timber did.
static func instantiate(style: String, width: float, materials: Dictionary, shadows: bool, look: String = "", detail: bool = true) -> Node3D:
	var model := nearest_width(width)
	var scene := load(model_path(style,model)) as PackedScene
	var node := scene.instantiate() as Node3D
	node.name = "Деревянная площадка"
	node.scale.x = width/model
	node.set_meta("model",model_path(style,model))
	node.set_meta("look",look)
	var keep: Array = TIMBER.duplicate()
	if look!="": keep.append_array(LOOKS[look]["dress"])
	if not detail:
		keep.erase("nail")
		if look!="":
			for part in LOOKS[look]["detail"]: keep.erase(part)
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var part := part_of(mesh)
		if part!="" and not part in keep:
			mesh.get_parent().remove_child(mesh)
			mesh.free()
			continue
		if materials.has(part): mesh.material_override = materials[part]
		# Snow and sand lie on the deck: they take no part in its shadow.
		var casts := shadows and part in TIMBER
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("rise",cap_rise(node))
	return node

# Parts that cover the whole deck: the hero walks on their top, not on the
# boards under them.
const CAPS := ["snow"]

# How far a cap's visible top stands over the walking line: the mean, along
# the deck, of the highest point at each step (what the camera sees as the
# top edge). The game lowers the model by this, so the hero's boots rest on
# the snow instead of sinking into it.
static func cap_rise(node: Node3D) -> float:
	var tops := {}
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if not part_of(mesh) in CAPS or mesh.mesh==null: continue
		for point in mesh.mesh.get_faces():
			var key := roundi(point.x/.1)
			tops[key] = maxf(float(tops.get(key,-INF)),point.y)
	if tops.is_empty(): return 0.0
	var total := 0.0
	for key in tops: total += float(tops[key])
	return maxf(0.0,total/tops.size())
