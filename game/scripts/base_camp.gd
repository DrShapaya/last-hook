class_name BaseCamp
extends RefCounted

# The base camp at the foot of a climb (docs/LEVEL_OBJECTS_PLAN.md, stage 6):
# the start reads as a place, not as the first grip. Each location sets up
# its own: a tent and a campfire with a log seat in summer, a striped awning,
# camel packs and a clay pot in the canyon, a tent in the snow and a loaded
# sled on the peak. Everything stands on the start deck behind the hero's
# plane, at its two ends, so the middle where the hero starts stays free.
# Low-poly parts in vertex colours; on battery nothing casts a shadow and the
# fire has no light.

const CANVAS := {"summer":Color("d9813a"),"winter":Color("c9473a")}
const CANVAS_DARK := {"summer":Color("8a4a22"),"winter":Color("7a2a24")}
const WOOD := Color("7a5234")
const WOOD_DARK := Color("4e3422")
const ROPE := Color("cdb27c")
const STONE := Color("8a8478")
const SNOW := Color("e8eef5")

var surface := SurfaceTool.new()
var random := RandomNumberGenerator.new()

# A camp on the deck from `left` to `right` at height `top`, its pieces
# centred `z` out of the face and no deeper than `depth`. `look` is
# "summer", "desert" or "winter".
static func build(parent: Node3D, look: String, left: float, right: float, top: float, z: float, depth: float, detail: bool) -> Node3D:
	var camp := Node3D.new()
	camp.name = "Базовый лагерь"
	parent.add_child(camp)
	camp.position = Vector3(0,top,z)
	var maker := BaseCamp.new()
	maker.random.seed = hash(look)
	var west := left+1.25
	var east := right-1.1
	match look:
		"summer":
			maker._tent(camp,"Палатка",Vector3(west,0,0),Vector2(1.5,1.2),minf(depth,.95),CANVAS["summer"],CANVAS_DARK["summer"],false)
			maker._campfire(camp,Vector3(east,0,0),detail)
			maker._log_seat(camp,Vector3(east-.75,0,-.12))
		"desert":
			maker._awning(camp,Vector3(west,0,0),minf(depth,.95))
			maker._packs(camp,Vector3(east,0,0))
			maker._pot(camp,Vector3(east-.75,0,.1))
		"winter":
			maker._tent(camp,"Палатка в снегу",Vector3(west,0,0),Vector2(1.5,1.15),minf(depth,.95),CANVAS["winter"],CANVAS_DARK["winter"],true)
			maker._sled(camp,Vector3(east,0,0))
		_:
			camp.free()
			return null
	for mesh: MeshInstance3D in camp.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if detail else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return camp

# --- Pieces -------------------------------------------------------------------------

# An A-frame tent seen from the front: a canvas prism, a dark door in its
# face, guy ropes to pegs; on the peak snow lies on the ridge and banks
# against its sides.
func _tent(camp: Node3D, title: String, at: Vector3, size: Vector2, depth: float, canvas: Color, dark: Color, snowed: bool) -> void:
	_begin()
	var half := size.x*.5
	var back := -depth*.5
	var front := depth*.5
	var ridge := size.y
	# The two sloping sides.
	_quad(Vector3(-half,0,front),Vector3(0,ridge,front),Vector3(0,ridge,back),Vector3(-half,0,back),canvas.darkened(.08))
	_quad(Vector3(0,ridge,front),Vector3(half,0,front),Vector3(half,0,back),Vector3(0,ridge,back),canvas)
	# The front gable and the door in it.
	_tri(Vector3(-half,0,front),Vector3(half,0,front),Vector3(0,ridge,front),canvas.lightened(.06))
	_tri(Vector3(-half*.42,0,front+.01),Vector3(half*.42,0,front+.01),Vector3(0,ridge*.72,front+.01),dark)
	# Ridge pole ends and pegs.
	_box(Vector3(0,ridge+.04,front+.04),Vector3(.03,.08,.03),WOOD_DARK)
	for side in [-1.0,1.0]:
		_box(Vector3(side*(half+.28),.04,front-.05),Vector3(.025,.05,.025),WOOD_DARK)
		_quad(Vector3(side*half*.5,ridge*.5,front+.005),Vector3(side*half*.5+side*.012,ridge*.5,front+.005),Vector3(side*(half+.28)+side*.012,.06,front-.05),Vector3(side*(half+.28),.06,front-.05),ROPE)
	if snowed:
		# Snow along the ridge and drifts against both sides.
		_quad(Vector3(-half*.45,ridge*.55,front+.02),Vector3(0,ridge+.05,front+.02),Vector3(0,ridge+.05,back),Vector3(-half*.45,ridge*.55,back),SNOW)
		_quad(Vector3(0,ridge+.05,front+.02),Vector3(half*.4,ridge*.6,front+.02),Vector3(half*.4,ridge*.6,back),Vector3(0,ridge+.05,back),SNOW.darkened(.04))
		for side in [-1.0,1.0]:
			_tri(Vector3(side*(half+.35),0,front+.02),Vector3(side*(half-.15),0,front+.02),Vector3(side*(half-.05),.22,front+.02),SNOW)
	_commit(camp,title,at)

# Stones in a ring, crossed logs and a flame of three tongues; a warm light
# where the preset allows it.
func _campfire(camp: Node3D, at: Vector3, detail: bool) -> void:
	_begin()
	for index in range(7):
		var angle := TAU*index/7.0
		var size := Vector3(random.randf_range(.07,.1),random.randf_range(.05,.08),random.randf_range(.06,.09))
		_box(Vector3(cos(angle)*.34,size.y,sin(angle)*.16),size,STONE.lightened(random.randf_range(-.08,.08)))
	for index in range(3):
		var turn := index*1.05
		_beam(Vector3(cos(turn)*.26,.05,sin(turn)*.12),Vector3(-cos(turn)*.26,.05,-sin(turn)*.12),.045,WOOD.darkened(.1*index))
	_commit(camp,"Костёр",at)
	_begin()
	for tongue in range(3):
		var x := (tongue-1)*.09
		var height := [.42,.58,.38][tongue] as float
		_tri(Vector3(x-.1,.06,.02),Vector3(x+.1,.06,.02),Vector3(x+random.randf_range(-.03,.03),.06+height,.02),Color("ffb23a") if tongue!=1 else Color("ffe07a"))
	var flame := _commit(camp.get_node("Костёр"),"Пламя",Vector3.ZERO)
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame.material_override = glow
	if detail:
		var light := OmniLight3D.new()
		light.name = "Свет костра"
		light.light_color = Color("ffb060")
		light.light_energy = 1.4
		light.omni_range = 3.2
		light.position = Vector3(0,.5,.3)
		camp.get_node("Костёр").add_child(light)

func _log_seat(camp: Node3D, at: Vector3) -> void:
	_begin()
	_beam(Vector3(-.32,.1,0),Vector3(.32,.1,0),.1,WOOD)
	_commit(camp,"Бревно",at)

# Two poles and a striped cloth leaning from them back to the rock, a rope
# from each pole to a peg.
func _awning(camp: Node3D, at: Vector3, depth: float) -> void:
	_begin()
	var half := .85
	var front := depth*.5
	var back := -depth*.5
	for side in [-1.0,1.0]:
		_box(Vector3(side*half,.62,front-.04),Vector3(.03,.62,.03),WOOD)
		_quad(Vector3(side*half,1.2,front-.02),Vector3(side*half+side*.012,1.2,front-.02),Vector3(side*(half+.35)+side*.012,.04,front),Vector3(side*(half+.35),.04,front),ROPE)
	var stripes := 6
	for index in range(stripes):
		var x0 := lerpf(-half-.08,half+.08,float(index)/stripes)
		var x1 := lerpf(-half-.08,half+.08,float(index+1)/stripes)
		var tone := Color("e9dcc0") if index%2==0 else Color("b8452e")
		_quad(Vector3(x0,1.26,front),Vector3(x1,1.26,front),Vector3(x1,1.0,back),Vector3(x0,1.0,back),tone)
		# The cloth's front edge hangs a little in a scallop.
		_tri(Vector3(x0,1.26,front+.005),Vector3(x1,1.26,front+.005),Vector3((x0+x1)*.5,1.16,front+.005),tone.darkened(.12))
	# A rug in its shade.
	_box(Vector3(0,.012,0),Vector3(.6,.012,depth*.38),Color("9a3e2c"))
	_commit(camp,"Навес",at)

# Camel packs: rounded bundles tied with rope, one lying on two others.
func _packs(camp: Node3D, at: Vector3) -> void:
	_begin()
	var places := [Vector3(-.28,.2,0),Vector3(.26,.18,.04),Vector3(0,.52,.02)]
	var sizes := [Vector3(.3,.2,.24),Vector3(.27,.18,.22),Vector3(.28,.15,.2)]
	var tones := [Color("a0683e"),Color("c28a52"),Color("8a5a36")]
	for index in range(3):
		var center: Vector3 = places[index]
		var half: Vector3 = sizes[index]
		_box(center,half,tones[index])
		_box(center+Vector3(0,0,half.z+.004),Vector3(.025,half.y+.01,.004),ROPE)
		_box(center+Vector3(0,half.y+.004,0),Vector3(.025,.004,half.z+.01),ROPE)
	_commit(camp,"Тюки",at)

func _pot(camp: Node3D, at: Vector3) -> void:
	_begin()
	_cylinder(Vector3(0,0,0),.14,.2,.24,Color("b56a3e"))
	_cylinder(Vector3(0,.24,0),.1,.08,.06,Color("9a5632"))
	_commit(camp,"Горшок",at)

# A wooden sled on two curled runners, a bundle lashed on it, snow on top.
func _sled(camp: Node3D, at: Vector3) -> void:
	_begin()
	for z in [-.16,.16]:
		_box(Vector3(0,.04,z),Vector3(.55,.025,.025),WOOD_DARK)
		_box(Vector3(.58,.1,z),Vector3(.03,.07,.025),WOOD_DARK)
		for x in [-.35,0.0,.35]: _box(Vector3(x,.12,z),Vector3(.02,.06,.02),WOOD)
	for x in range(5):
		_box(Vector3(-.44+x*.22,.19,0),Vector3(.09,.015,.2),WOOD.lightened(.05*(x%2)))
	_box(Vector3(-.05,.34,0),Vector3(.3,.14,.17),Color("3a5aa8"))
	_box(Vector3(-.05,.34,.175),Vector3(.02,.15,.004),ROPE)
	_box(Vector3(-.05,.49,0),Vector3(.28,.025,.15),SNOW)
	_commit(camp,"Сани",at)

# --- Mesh helpers -------------------------------------------------------------------

func _begin() -> void:
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

func _commit(parent: Node, title: String, at: Vector3) -> MeshInstance3D:
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = title
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	for v in [a,c,b]:
		surface.set_color(color)
		surface.add_vertex(v)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(a,b,c,color)
	_tri(a,c,d,color)

func _box(center: Vector3, half: Vector3, color: Color) -> void:
	var c := center
	var h := half
	var p := [c+Vector3(-h.x,-h.y,-h.z),c+Vector3(h.x,-h.y,-h.z),c+Vector3(h.x,h.y,-h.z),c+Vector3(-h.x,h.y,-h.z),
		c+Vector3(-h.x,-h.y,h.z),c+Vector3(h.x,-h.y,h.z),c+Vector3(h.x,h.y,h.z),c+Vector3(-h.x,h.y,h.z)]
	_quad(p[4],p[5],p[6],p[7],color)
	_quad(p[3],p[2],p[6],p[7],color.lightened(.08))
	_quad(p[0],p[3],p[7],p[4],color.darkened(.1))
	_quad(p[1],p[5],p[6],p[2],color.darkened(.06))
	_quad(p[0],p[1],p[2],p[3],color.darkened(.15))

# A log from a to b with a hexagonal section.
func _beam(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var axis := (b-a).normalized()
	var across := axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(across).normalized()
	for index in range(6):
		var t0 := TAU*index/6.0
		var t1 := TAU*(index+1)/6.0
		var o0 := (across*cos(t0)+up*sin(t0))*radius
		var o1 := (across*cos(t1)+up*sin(t1))*radius
		_quad(a+o0,b+o0,b+o1,a+o1,color.lightened(.05) if index%2==0 else color)
	for end in [a,b]:
		for index in range(6):
			var o0 := (across*cos(TAU*index/6.0)+up*sin(TAU*index/6.0))*radius
			var o1 := (across*cos(TAU*(index+1)/6.0)+up*sin(TAU*(index+1)/6.0))*radius
			_tri(end,end+o0,end+o1,Color("b08a5a"))

# A tapered pot or jar from `base` up `height`, eight sides.
func _cylinder(base: Vector3, bottom: float, top: float, height: float, color: Color) -> void:
	for index in range(8):
		var a := TAU*index/8.0
		var b := TAU*(index+1)/8.0
		_quad(base+Vector3(cos(a)*bottom,0,sin(a)*bottom),base+Vector3(cos(b)*bottom,0,sin(b)*bottom),base+Vector3(cos(b)*top,height,sin(b)*top),base+Vector3(cos(a)*top,height,sin(a)*top),color.darkened(.1) if index%2==0 else color)
