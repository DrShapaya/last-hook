class_name BagSlot
extends Control

var item: Dictionary = {}
var rare := false
var on_discard := Callable()
var held_touch := -1
var hold_time := 0.0
var press_position := Vector2.ZERO
const HOLD_SECONDS := .65

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	# Slate slot with the same chamfer and lip as the HUD; a filled slot gets
	# a hold-yellow lip so the carried value reads at a glance.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("24323d",.55 if item.is_empty() else .92)
	frame.border_color = Color("121b22") if item.is_empty() else Color("f6c32f")
	frame.border_width_bottom = 3 if item.is_empty() else 4
	frame.set_corner_radius_all(9)
	frame.corner_detail = 1
	draw_style_box(frame,Rect2(Vector2.ZERO,size))
	draw_set_transform(size*.5,0,Vector2.ONE*minf(size.x,size.y)/54)
	if not item.is_empty():
		var colors := [Color("e4b35e"),Color("f08f72"),Color("86c6a0"),Color("78d5d2"),Color("af9bdf"),Color("d7dcea")]
		var tier := clampi(int(item["tier"]),0,5)
		var color: Color = colors[tier]
		# A compact contact shadow separates the icon from the slot surface.
		_draw_contact_ellipse(Vector2(0,11),Vector2(15,5),Color("020814",.28))
		draw_loot_icon(tier,color,str(item.get("kind","")))
		if rare:
			draw_circle(Vector2(17,-17),3,Color("fff0a8"))
			draw_arc(Vector2.ZERO,21,-PI*.85,PI*.15,32,Color("fff0a8"),1.5,true)
	if held_touch!=-1 and not item.is_empty():
		draw_arc(Vector2.ZERO,24,-PI*.5,-PI*.5+TAU*clampf(hold_time/HOLD_SECONDS,0,1),48,Color("f19472"),3,true)

func _draw_contact_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU*float(index)/24.0
		points.append(center+Vector2(cos(angle)*radii.x,sin(angle)*radii.y))
	draw_colored_polygon(points,color)

func draw_loot_icon(tier: int, color: Color, kind: String = "") -> void:
	var highlight := color.lightened(.28)
	var shade := color.darkened(.28)
	if kind=="crown":
		var crown := PackedVector2Array([Vector2(-16,10),Vector2(-13,-11),Vector2(-5,-2),Vector2(0,-15),Vector2(6,-2),Vector2(14,-11),Vector2(16,10)])
		draw_colored_polygon(crown,Color("ffd45c"))
		draw_polyline(crown,Color("fff2a6"),2.2,true)
		draw_line(Vector2(-15,10),Vector2(15,10),Color("b86d25"),3,true)
		return
	if kind=="chalice":
		draw_colored_polygon(PackedVector2Array([Vector2(-12,-12),Vector2(12,-12),Vector2(8,5),Vector2(3,10),Vector2(-3,10),Vector2(-8,5)]),Color("d8a94f"))
		draw_line(Vector2(0,10),Vector2(0,16),Color("ffe4a0"),3,true)
		draw_line(Vector2(-8,16),Vector2(8,16),Color("a96b2d"),3,true)
		draw_arc(Vector2.ZERO,12,-PI,0,20,Color("fff2ab"),1.6,true)
		return
	match tier:
		0: # Copper find: a readable coin with a stamped centre.
			draw_circle(Vector2.ZERO,14,shade)
			draw_circle(Vector2(0,-1),12,color)
			draw_arc(Vector2(0,-1),12,-PI*.82,PI*.18,28,highlight,2,true)
			draw_arc(Vector2.ZERO,7,-PI*.65,PI*.65,20,Color("fff0ad",.8),1.4,true)
			draw_line(Vector2(-2,-6),Vector2(2,5),Color("fff0ad",.75),1.4,true)
		1: # Amber: a warm faceted gem.
			var gem := PackedVector2Array([Vector2(0,-16),Vector2(14,-6),Vector2(10,11),Vector2(0,16),Vector2(-11,9),Vector2(-14,-6)])
			draw_colored_polygon(gem,shade)
			draw_colored_polygon(PackedVector2Array([Vector2(0,-16),Vector2(14,-6),Vector2(0,2),Vector2(-14,-6)]),highlight)
			draw_colored_polygon(PackedVector2Array([Vector2(-14,-6),Vector2(0,2),Vector2(-11,9)]),color)
			draw_polyline(gem,Color("fff0c2",.68),1.2,true)
		2: # Relic: a small wrapped artefact.
			draw_colored_polygon(PackedVector2Array([Vector2(-11,-9),Vector2(9,-12),Vector2(13,8),Vector2(-8,13)]),shade)
			draw_colored_polygon(PackedVector2Array([Vector2(-11,-9),Vector2(9,-12),Vector2(8,-3),Vector2(-10,1)]),color)
			draw_line(Vector2(-7,1),Vector2(9,-2),Color("f3d27b"),3,true)
			draw_line(Vector2(-5,6),Vector2(9,3),highlight,1.5,true)
			draw_circle(Vector2(-1,-5),2.5,Color("f8e5a4"))
		3: # Ice crystal: tall, cool and translucent.
			var ice := PackedVector2Array([Vector2(-3,-17),Vector2(9,-7),Vector2(6,14),Vector2(0,17),Vector2(-8,5)])
			draw_colored_polygon(ice,shade)
			draw_colored_polygon(PackedVector2Array([Vector2(-3,-17),Vector2(9,-7),Vector2(0,3)]),highlight)
			draw_colored_polygon(PackedVector2Array([Vector2(-3,-17),Vector2(0,3),Vector2(-8,5)]),Color("c9ffff",.72))
			draw_polyline(ice,Color("e2ffff",.9),1.2,true)
		4: # Obsidian: dark shard with a violet edge.
			var obsidian := PackedVector2Array([Vector2(-3,-16),Vector2(12,-5),Vector2(7,13),Vector2(-5,10),Vector2(-12,-4)])
			draw_colored_polygon(obsidian,Color("25243b"))
			draw_colored_polygon(PackedVector2Array([Vector2(-3,-16),Vector2(12,-5),Vector2(2,-2)]),color)
			draw_line(Vector2(-3,-16),Vector2(2,-2),Color("d5b9ff",.82),1.4,true)
			draw_line(Vector2(2,-2),Vector2(7,13),Color("8065ad",.8),1.4,true)
			draw_polyline(obsidian,Color("a88bdc",.7),1.2,true)
		5: # Sky shard: a bright prism with an orbit ring.
			var shard := PackedVector2Array([Vector2(0,-17),Vector2(11,-4),Vector2(6,13),Vector2(-7,10),Vector2(-12,-4)])
			draw_colored_polygon(shard,shade)
			draw_colored_polygon(PackedVector2Array([Vector2(0,-17),Vector2(11,-4),Vector2(0,2),Vector2(-12,-4)]),Color("f6e8b5"))
			draw_colored_polygon(PackedVector2Array([Vector2(-12,-4),Vector2(0,2),Vector2(-7,10)]),color)
			draw_polyline(shard,Color("fff6cf"),1.3,true)
			draw_arc(Vector2.ZERO,20,-PI*.18,PI*.82,28,Color("ffe7a3",.8),1.2,true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and held_touch==-1:
			_begin_hold(event.index,event.position)
		elif not event.pressed and event.index==held_touch:
			_cancel_hold()
		accept_event()
	elif event is InputEventScreenDrag and event.index==held_touch:
		if event.position.distance_to(press_position)>18:
			_cancel_hold()
		accept_event()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_hold(-2,event.position)
		else:
			_cancel_hold()
		accept_event()
	elif event is InputEventMouseMotion and held_touch==-2 and event.position.distance_to(press_position)>18:
		_cancel_hold()

func _begin_hold(index: int, point: Vector2) -> void:
	if item.is_empty():
		return
	held_touch = index
	press_position = point
	hold_time = 0
	queue_redraw()

func _cancel_hold() -> void:
	held_touch = -1
	hold_time = 0
	queue_redraw()

func _process(delta: float) -> void:
	if held_touch==-1:
		return
	hold_time += delta
	if hold_time>=HOLD_SECONDS:
		_cancel_hold()
		if on_discard.is_valid():
			on_discard.call()
	else:
		queue_redraw()
