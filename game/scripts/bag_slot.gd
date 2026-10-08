class_name BagSlot
extends Control

var item: Dictionary = {}
var on_discard := Callable()
var held_touch := -1
var hold_time := 0.0
var press_position := Vector2.ZERO
const HOLD_SECONDS := .65

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(.055,.075,.095,.88)
	frame.border_color = Color("6f7980") if item.is_empty() else Color("d6b775")
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(5)
	frame.shadow_color = Color(0,0,0,.30)
	frame.shadow_size = 4
	draw_style_box(frame,Rect2(Vector2.ZERO,size))
	draw_line(Vector2(5,5),Vector2(size.x-5,5),Color(1,1,1,.20),1)
	if not item.is_empty():
		var center := size*.5
		var colors := [Color("dfa752"),Color("ed8f32"),Color("66a877"),Color("93d6ee"),Color("836c9d"),Color("d5dced")]
		var color: Color = colors[clampi(int(item["tier"]),0,5)]
		var corners := PackedVector2Array([center+Vector2(0,-16),center+Vector2(15,-5),center+Vector2(10,11),center+Vector2(-5,15),center+Vector2(-14,0)])
		draw_colored_polygon(corners,color)
		draw_colored_polygon(PackedVector2Array([corners[0],corners[1],center+Vector2(0,1),corners[4]]),color.lightened(.22))
		draw_colored_polygon(PackedVector2Array([corners[1],corners[2],corners[3],center+Vector2(0,1)]),color.darkened(.20))
		draw_polyline(PackedVector2Array([corners[4],center+Vector2(0,1),corners[1]]),color.lightened(.4),1.5,true)
	if held_touch!=-1 and not item.is_empty():
		draw_arc(size*.5,size.x*.46,-PI*.5,-PI*.5+TAU*clampf(hold_time/HOLD_SECONDS,0,1),48,Color("f19472"),3,true)

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
