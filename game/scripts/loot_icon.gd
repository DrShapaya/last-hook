class_name LootIcon
extends RefCounted

# Flat, faceted 2D portraits of the finds for the backpack, the flying pickup
# and the pause list. Kinds match LootVisuals so the icon in the bag is the
# same object the player just touched on the ledge. Each icon is authored in a
# 48 x 48 box around the origin and drawn at `origin`, `size` / 48 scale.

const RARITY := ItemCatalog.VISUAL_RARITY_COLORS
const MATERIAL_COLORS := ItemCatalog.VISUAL_MATERIAL_COLORS

static func rarity_color(item: Dictionary) -> Color:
	return ItemCatalog.visual_color(item)

static func draw(ci: CanvasItem, item: Dictionary, origin: Vector2, size: float, time: float = 0.0, rotation: float = 0.0) -> void:
	var kind := LootVisuals.kind_of(item)
	var scale := Vector2.ONE*size/48.0
	ci.draw_set_transform(origin,rotation,scale)
	_shadow(ci)
	match kind:
		"coin":
			# A slow edge-on turn keeps the coin alive without distracting.
			ci.draw_set_transform(origin,rotation,scale*Vector2(.82+.18*absf(cos(time*1.6)),1))
			_coin(ci)
		"amber": _amber(ci)
		"crown": _crown(ci)
		"chalice": _chalice(ci)
		"idol": _idol(ci,time)
		"star": _star(ci,time)
		"crystal": _crystal(ci)
		"material": _material(ci,MATERIAL_COLORS.get(str(item.get("set_id","")),Color("c9a46a")))
		_: _relic(ci)
	ci.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

static func poly(ci: CanvasItem, points: Array, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(points),color)

static func _shadow(ci: CanvasItem) -> void:
	var points := PackedVector2Array()
	for index in range(20):
		var angle := TAU*index/20
		points.append(Vector2(cos(angle)*15,17+sin(angle)*3.5))
	ci.draw_colored_polygon(points,Color("0b1218",.35))

static func _coin(ci: CanvasItem) -> void:
	var rim := PackedVector2Array()
	var face := PackedVector2Array()
	for index in range(16):
		var angle := TAU*index/16
		rim.append(Vector2(cos(angle),sin(angle))*16)
		face.append(Vector2(cos(angle),sin(angle))*12.5)
	ci.draw_colored_polygon(rim,Color("b9761a"))
	ci.draw_colored_polygon(face,Color("f2b52e"))
	poly(ci,[face[10],face[11],face[12],face[13],face[14],Vector2.ZERO,face[8],face[9]],Color("ffd65e"))
	poly(ci,[Vector2(-7,5),Vector2(-1,-6),Vector2(2,-1),Vector2(4,-4),Vector2(8,5)],Color("c4800f"))
	poly(ci,[Vector2(-1,-6),Vector2(1,-3),Vector2(-3,-2)],Color("fff1b8"))
	ci.draw_arc(Vector2.ZERO,14.3,-PI*.85,-PI*.35,10,Color("fff3c4"),1.6,true)

static func _amber(ci: CanvasItem) -> void:
	var outer := [Vector2(0,-17),Vector2(13,-8),Vector2(13,8),Vector2(0,17),Vector2(-13,8),Vector2(-13,-8)]
	poly(ci,outer,Color("b8561a"))
	poly(ci,[outer[0],outer[1],Vector2(6,-3),Vector2(-6,-3),outer[5]],Color("ffc27a"))
	poly(ci,[outer[5],Vector2(-6,-3),Vector2(-6,5),outer[4]],Color("f09a45"))
	poly(ci,[Vector2(-6,-3),Vector2(6,-3),Vector2(6,5),Vector2(-6,5)],Color("e8833a"))
	poly(ci,[outer[1],outer[2],Vector2(6,5),Vector2(6,-3)],Color("cf6a22"))
	poly(ci,[Vector2(-6,5),Vector2(6,5),outer[3]],Color("a8501a"))
	# A tiny trapped seed is what makes it amber rather than a ruby.
	ci.draw_circle(Vector2(1,1),2.2,Color("6b3410",.7))
	poly(ci,[Vector2(-4,-12),Vector2(0,-14),Vector2(-2,-8)],Color("fff0d0"))

static func _crown(ci: CanvasItem) -> void:
	var band := [Vector2(-16,4),Vector2(16,4),Vector2(14,13),Vector2(-14,13)]
	poly(ci,[Vector2(-16,4),Vector2(-17,-11),Vector2(-8,-2),Vector2(0,-15),Vector2(8,-2),Vector2(17,-11),Vector2(16,4)],Color("f2b52e"))
	poly(ci,[Vector2(-17,-11),Vector2(-8,-2),Vector2(-10,4),Vector2(-16,4)],Color("ffd65e"))
	poly(ci,[Vector2(0,-15),Vector2(8,-2),Vector2(2,4),Vector2(-2,4),Vector2(-8,-2)],Color("ffd65e"))
	poly(ci,band,Color("c98412"))
	poly(ci,[band[0],band[1],Vector2(16,7),Vector2(-16,7)],Color("e9a925"))
	for at in [Vector2(-17,-12),Vector2(0,-16),Vector2(17,-12)]: ci.draw_circle(at,2.6,Color("fff1b8"))
	poly(ci,[Vector2(-3,6),Vector2(0,3),Vector2(3,6),Vector2(0,10)],Color("e2473c"))
	poly(ci,[Vector2(-11,7),Vector2(-9,5),Vector2(-7,7),Vector2(-9,10)],Color("3f8ee0"))
	poly(ci,[Vector2(7,7),Vector2(9,5),Vector2(11,7),Vector2(9,10)],Color("3f8ee0"))

static func _chalice(ci: CanvasItem) -> void:
	poly(ci,[Vector2(-14,-14),Vector2(14,-14),Vector2(10,-1),Vector2(4,4),Vector2(-4,4),Vector2(-10,-1)],Color("d79a24"))
	poly(ci,[Vector2(-14,-14),Vector2(0,-14),Vector2(0,4),Vector2(-4,4),Vector2(-10,-1)],Color("f5c044"))
	poly(ci,[Vector2(-14,-14),Vector2(14,-14),Vector2(12,-11),Vector2(-12,-11)],Color("8a5a12"))
	poly(ci,[Vector2(-2,4),Vector2(2,4),Vector2(2,11),Vector2(-2,11)],Color("c98412"))
	poly(ci,[Vector2(-10,15),Vector2(10,15),Vector2(6,10),Vector2(-6,10)],Color("b9761a"))
	poly(ci,[Vector2(-10,15),Vector2(0,15),Vector2(0,10),Vector2(-6,10)],Color("e9a925"))
	poly(ci,[Vector2(-3,-6),Vector2(0,-9),Vector2(3,-6),Vector2(0,-3)],Color("2fb5a6"))
	poly(ci,[Vector2(-11,-10),Vector2(-8,-10),Vector2(-6,-2),Vector2(-8,-1)],Color("fff1b8",.8))

static func _idol(ci: CanvasItem, time: float) -> void:
	# A squat stone figure with a cube head: a nod to the hero.
	poly(ci,[Vector2(-11,2),Vector2(11,2),Vector2(13,16),Vector2(-13,16)],Color("6f6788"))
	poly(ci,[Vector2(-11,2),Vector2(0,2),Vector2(0,16),Vector2(-13,16)],Color("8f86a8"))
	poly(ci,[Vector2(-12,-15),Vector2(10,-17),Vector2(12,2),Vector2(-11,3)],Color("9b93b5"))
	poly(ci,[Vector2(-12,-15),Vector2(-6,-20),Vector2(15,-21),Vector2(10,-17)],Color("bdb6d4"))
	poly(ci,[Vector2(10,-17),Vector2(15,-21),Vector2(16,-2),Vector2(12,2)],Color("6f6788"))
	var glow := Color("7ff0dd").lerp(Color("e8fffb"),.5+.5*sin(time*3))
	for x in [-6.0,3.0]:
		ci.draw_rect(Rect2(x,-11,4,8),glow)
	poly(ci,[Vector2(-6,8),Vector2(6,8),Vector2(5,11),Vector2(-5,11)],Color("4f4868"))

static func _star(ci: CanvasItem, time: float) -> void:
	var pulse := 1.0+.06*sin(time*2.4)
	ci.draw_circle(Vector2.ZERO,15*pulse,Color("fff3c4",.18))
	var tips := [Vector2(0,-18),Vector2(16,0),Vector2(0,18),Vector2(-16,0)]
	var inner := [Vector2(5,-5),Vector2(5,5),Vector2(-5,5),Vector2(-5,-5)]
	for index in range(4):
		var a: Vector2 = tips[index]
		var b: Vector2 = inner[index]
		var c: Vector2 = inner[(index+3)%4]
		poly(ci,[a*pulse,b,Vector2.ZERO],Color("fff6d6"))
		poly(ci,[a*pulse,Vector2.ZERO,c],Color("f3d478"))
	ci.draw_circle(Vector2.ZERO,3,Color("ffffff"))

static func _crystal(ci: CanvasItem) -> void:
	poly(ci,[Vector2(-12,14),Vector2(-14,-2),Vector2(-9,-8),Vector2(-5,0),Vector2(-5,14)],Color("4aa3d6"))
	poly(ci,[Vector2(-14,-2),Vector2(-9,-8),Vector2(-9,14),Vector2(-12,14)],Color("8fd8ee"))
	poly(ci,[Vector2(-5,15),Vector2(-6,-6),Vector2(1,-18),Vector2(8,-6),Vector2(7,15)],Color("3d8fd0"))
	poly(ci,[Vector2(-6,-6),Vector2(1,-18),Vector2(1,15),Vector2(-5,15)],Color("b8ecff"))
	poly(ci,[Vector2(1,-18),Vector2(8,-6),Vector2(1,-3)],Color("e6f8ff"))
	poly(ci,[Vector2(7,15),Vector2(8,-1),Vector2(13,-5),Vector2(15,3),Vector2(13,15)],Color("5bb4e2"))
	poly(ci,[Vector2(8,-1),Vector2(13,-5),Vector2(13,15),Vector2(8,15)],Color("9fe0f6"))

# A tied bundle: regional material for the consumable recipes.
static func _material(ci: CanvasItem, color: Color) -> void:
	poly(ci,[Vector2(-14,-6),Vector2(-4,-15),Vector2(12,-10),Vector2(15,4),Vector2(5,15),Vector2(-11,11)],color.darkened(.35))
	poly(ci,[Vector2(-14,-6),Vector2(-4,-15),Vector2(12,-10),Vector2(2,-2)],color.lightened(.15))
	poly(ci,[Vector2(2,-2),Vector2(12,-10),Vector2(15,4),Vector2(5,15)],color)
	ci.draw_line(Vector2(-9,-12),Vector2(9,12),Color("5a3b1e"),3.0,true)
	ci.draw_line(Vector2(-12,2),Vector2(13,-3),Color("5a3b1e"),3.0,true)

static func _relic(ci: CanvasItem) -> void:
	poly(ci,[Vector2(-12,-15),Vector2(10,-16),Vector2(13,14),Vector2(-11,16)],Color("8a7f68"))
	poly(ci,[Vector2(-12,-15),Vector2(10,-16),Vector2(9,-1),Vector2(-11,0)],Color("b3a98f"))
	poly(ci,[Vector2(10,-16),Vector2(13,-13),Vector2(15,12),Vector2(13,14)],Color("6d6452"))
	var rune := Color("f2b52e")
	ci.draw_polyline(PackedVector2Array([Vector2(-5,-9),Vector2(0,-4),Vector2(5,-9)]),rune,2.2,true)
	ci.draw_line(Vector2(0,-4),Vector2(0,9),rune,2.2,true)
	ci.draw_line(Vector2(-5,4),Vector2(5,4),rune,2.2,true)
