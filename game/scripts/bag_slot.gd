class_name BagSlot
extends Control

var item: Dictionary = {}
var rare := false
# The last slot of a full-size bag takes only materials, relics and contracts.
var special := false
var on_discard := Callable()
var held_touch := -1
var hold_time := 0.0
var press_position := Vector2.ZERO
# Presentation only: `reveal` hides an item while its pickup is still flying
# in, `pop` is the landing bounce and `time` drives idle shimmer.
var reveal := true
var pop := 0.0
var time := 0.0
var value_font: Font
const HOLD_SECONDS := .65

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	time = randf()*4

func land() -> void:
	reveal = true
	pop = 1.0
	queue_redraw()

func _draw() -> void:
	var filled := not item.is_empty() and reveal
	var unit := minf(size.x,size.y)/54.0
	var accent := LootIcon.rarity_color(item) if filled else Color("121b22")
	var squash := 1.0+.16*sin(pop*PI)*pop
	draw_set_transform(size*.5,0,Vector2.ONE*squash)
	var half := size*.5
	# Slate slot with the HUD's chamfer; a filled slot takes its rarity colour
	# as the lip and a soft glow rising from the floor of the cell.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("24323d",.5 if not filled else .94)
	frame.border_color = accent if filled else Color("121b22",.8)
	frame.border_width_bottom = int(4*unit) if filled else int(3*unit)
	frame.set_corner_radius_all(int(9*unit))
	frame.corner_detail = 1
	draw_style_box(frame,Rect2(-half,size))
	if filled:
		var glow := PackedVector2Array([Vector2(-half.x+4*unit,half.y-5*unit),Vector2(half.x-4*unit,half.y-5*unit),Vector2(half.x-10*unit,0),Vector2(-half.x+10*unit,0)])
		draw_colored_polygon(glow,Color(accent,.16))
	else:
		# Empty cells show a faint socket so capacity reads at a glance.
		var socket := PackedVector2Array([Vector2(0,-9),Vector2(9,0),Vector2(0,9),Vector2(-9,0)])
		for index in range(4): socket[index] *= unit
		draw_polyline(PackedVector2Array([socket[0],socket[1],socket[2],socket[3],socket[0]]),Color("8fd8ee",.5) if special else Color("efebe1",.16),1.2*unit,true)
	if not filled:
		return
	var hold := clampf(hold_time/HOLD_SECONDS,0,1) if held_touch!=-1 else 0.0
	var shake := Vector2(sin(time*60)*2.2*hold*unit,0)
	var icon_size := 40.0*unit*(1-.25*hold)
	var icon_center := Vector2(0,-3*unit) if size.x>=48 else Vector2.ZERO
	LootIcon.draw(self,item,size*.5+(icon_center+shake)*squash,icon_size*squash,time)
	draw_set_transform(size*.5,0,Vector2.ONE*squash)
	if rare:
		# A diagonal light sweep crosses rare finds every few seconds.
		var sweep := fposmod(time*.45,1.6)-.3
		if sweep>=0 and sweep<=1:
			var x := lerpf(-half.x,half.x,sweep)
			var band := PackedVector2Array([Vector2(x-6*unit,-half.y+3*unit),Vector2(x+4*unit,-half.y+3*unit),Vector2(x-6*unit,half.y-6*unit),Vector2(x-16*unit,half.y-6*unit)])
			draw_colored_polygon(band,Color("fff6d6",.22*sin(sweep*PI)))
		var star := Vector2(half.x-9*unit,-half.y+9*unit)
		var twinkle := (2.2+1.4*absf(sin(time*2.6)))*unit
		draw_colored_polygon(PackedVector2Array([star+Vector2(0,-twinkle*1.8),star+Vector2(twinkle*.5,0),star+Vector2(0,twinkle*1.8),star+Vector2(-twinkle*.5,0)]),Color("fff1b8"))
		draw_colored_polygon(PackedVector2Array([star+Vector2(-twinkle*1.8,0),star+Vector2(0,twinkle*.5),star+Vector2(twinkle*1.8,0),star+Vector2(0,-twinkle*.5)]),Color("fff1b8"))
	if size.x>=48 and value_font!=null:
		var value := str(int(item.get("value",0)))
		var width := value_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,int(11*unit)).x
		var tab := Rect2(Vector2(-width*.5-5*unit,half.y-17*unit),Vector2(width+10*unit,13*unit))
		draw_rect(tab,Color("121b22",.85))
		draw_string(value_font,Vector2(-width*.5,half.y-6.5*unit),value,HORIZONTAL_ALIGNMENT_LEFT,-1,int(11*unit),Color("ffd15c"))
	if hold>0:
		draw_arc(Vector2.ZERO,24*unit,-PI*.5,-PI*.5+TAU*hold,48,Color("ff7a5c"),3.5*unit,true)
		var cross := 6*unit*hold
		draw_line(Vector2(-cross,-cross),Vector2(cross,cross),Color("ff7a5c",hold),2.5*unit,true)
		draw_line(Vector2(-cross,cross),Vector2(cross,-cross),Color("ff7a5c",hold),2.5*unit,true)

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
	time += delta
	if pop>0:
		pop = maxf(0,pop-delta*3.2)
	if not item.is_empty() and reveal:
		queue_redraw()
	if held_touch==-1:
		return
	hold_time += delta
	if hold_time>=HOLD_SECONDS:
		_cancel_hold()
		if on_discard.is_valid():
			on_discard.call()
	else:
		queue_redraw()
