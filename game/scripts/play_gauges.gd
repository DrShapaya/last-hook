class_name PlayGauges
extends RefCounted

# In-run gauges and short-lived effects for GameHud. Everything here only
# draws; the run state is read by GameHud.update_play and pushed in.

const SLATE := Color("24323d")
const SLATE_LIP := Color("121b22")
const STONE := Color("efebe1")
const HOLD := Color("f6c32f")
const ROPE := Color("c27b31")
const WARN := Color("ff8f70")

static func slab(ci: CanvasItem, rect: Rect2, face: Color, lip: Color, lip_size: int = 3, cut: int = 7) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = face
	box.border_color = lip
	box.border_width_bottom = lip_size
	box.set_corner_radius_all(cut)
	box.corner_detail = 1
	ci.draw_style_box(box,rect)

# Route from start to summit: zone ticks, record marker, the hero's head at
# the current height and the summit flag. Crossing a zone flashes its tick.
class RouteGauge extends Control:
	var value := 0.0
	var record := 0.0
	var zones := 6
	var flash := 0.0
	var flash_at := 0.0
	var time := 0.0

	func _process(delta: float) -> void:
		time += delta
		flash = maxf(0,flash-delta*1.6)
		queue_redraw()

	func _draw() -> void:
		var y := size.y-9.0
		var left := 4.0
		var right := size.x-22.0
		# The same rope-on-a-path language as the menu route: a dark groove,
		# the climbed part as twisted rope, act notches, the record hold.
		draw_line(Vector2(left,y),Vector2(right,y),Color(SLATE_LIP,.75),10,true)
		draw_line(Vector2(left,y),Vector2(right,y),Color(SLATE,.92),7,true)
		var fill_x := lerpf(left,right,clampf(value,0,1))
		for index in range(1,zones):
			var x := lerpf(left,right,float(index)/zones)
			draw_line(Vector2(x,y-4),Vector2(x,y+4),Color(HOLD if x<=fill_x else STONE,.45),2)
		if fill_x>left+1:
			draw_line(Vector2(left,y),Vector2(fill_x,y),Color("7a4a1c"),6,true)
			draw_line(Vector2(left,y-1),Vector2(fill_x,y-1),ROPE,4,true)
			var twist := left+2
			while twist<fill_x-3:
				draw_line(Vector2(twist,y+2),Vector2(twist+3,y-3),Color("e0a15a",.8),1.2,true)
				twist += 5
		if flash>0:
			var x := lerpf(left,right,flash_at)
			draw_arc(Vector2(x,y),6+(1-flash)*16,0,TAU,24,Color(HOLD,flash),2.5,true)
		if record>0.01 and record<.995:
			var x := lerpf(left,right,record)
			draw_colored_polygon(PackedVector2Array([Vector2(x-6,y+1),Vector2(x-3,y-5),Vector2(x+4,y-5),Vector2(x+6,y+1),Vector2(x+2,y+5),Vector2(x-4,y+5)]),Color("b88a12"))
			draw_colored_polygon(PackedVector2Array([Vector2(x-5,y),Vector2(x-2,y-4),Vector2(x+3,y-4),Vector2(x+5,y),Vector2(x+1,y+3),Vector2(x-3,y+3)]),HOLD)
		# The climber's cube head rides the end of the rope.
		var bob := sin(time*5)*1.0
		var head := Rect2(fill_x-6,y-17+bob,12,11)
		draw_rect(head.grow(1),SLATE_LIP)
		draw_rect(head,Color("f7a72b"))
		draw_rect(Rect2(head.position,Vector2(12,3)),Color("ffd45f"))
		draw_rect(Rect2(head.position+Vector2(3,4),Vector2(2,4)),SLATE_LIP)
		draw_rect(Rect2(head.position+Vector2(7,4),Vector2(2,4)),SLATE_LIP)
		var pole := Vector2(size.x-12,y+5)
		draw_line(pole+Vector2(1,0),pole+Vector2(1,-22),SLATE_LIP,2.5)
		draw_line(pole,pole+Vector2(0,-22),STONE,2)
		draw_colored_polygon(PackedVector2Array([pole+Vector2(1,-22),pole+Vector2(12,-18),pole+Vector2(10,-15),pole+Vector2(1,-13)]),HOLD)

# Lower danger edge, shown only while the view has sunk below it after a
# landing: a dashed warning line with a dark veil over the ground under it.
class DangerEdge extends Control:
	var edge_y := INF
	var strength := 0.0

	func _draw() -> void:
		if strength<=.01 or edge_y>=size.y: return
		var top := maxf(0,edge_y)
		draw_rect(Rect2(0,top,size.x,size.y-top),Color(SLATE_LIP,.34*strength))
		var x := 0.0
		while x<size.x:
			draw_rect(Rect2(x,edge_y-2,22,4),Color(WARN,.9*strength))
			x += 34

# Vertical rope meter beside the pause button: how much of the line is out,
# with chevrons while the rope is being reeled in or paid out.
class RopeGauge extends Control:
	var ratio := 0.0
	var meters := 0
	var direction := 0
	var active := false
	var shown := 0.0
	var time := 0.0
	var font: Font

	func _process(delta: float) -> void:
		time += delta
		shown = move_toward(shown,1.0 if active else 0.0,delta*6)
		modulate.a = shown
		visible = shown>0.01
		queue_redraw()

	func _draw() -> void:
		PlayGauges.slab(self,Rect2(Vector2.ZERO,size),Color("24323deb"),SLATE_LIP,4,8)
		var center := size.x*.5
		# Hook at the top of the meter.
		var tip := Vector2(center,9)
		draw_line(tip,tip+Vector2(0,12),STONE,2.2,true)
		draw_polyline(PackedVector2Array([tip+Vector2(-6,4),tip+Vector2(-6,8),tip+Vector2(0,12),tip+Vector2(6,8),tip+Vector2(6,4)]),STONE,2,true)
		var top := 28.0
		var bottom := size.y-30.0
		var track := Rect2(center-4,top,8,bottom-top)
		draw_rect(track,Color(SLATE_LIP,.9))
		var level := clampf(ratio,0,1)
		var color := WARN if level>.92 else ROPE
		var fill_top := lerpf(bottom,top,level)
		draw_rect(Rect2(center-4,fill_top,8,bottom-fill_top),color)
		# Twisted-rope texture scrolls with reeling so motion is visible.
		var offset := fposmod(time*14*direction,6.0)
		var y := fill_top+offset
		while y<bottom-1:
			draw_line(Vector2(center-4,y+3),Vector2(center+4,y),Color(color.lightened(.35),.8),1.2,true)
			y += 6
		draw_rect(Rect2(center-6,fill_top-2,12,3),STONE)
		if direction!=0:
			var phase := fposmod(time*2.2,1.0)
			for index in range(2):
				var t := fposmod(phase+index*.5,1.0)
				var cy := lerpf(top+6,bottom-6,t if direction<0 else 1-t)
				var dir := -1 if direction>0 else 1
				draw_polyline(PackedVector2Array([Vector2(center-6,cy-dir*3),Vector2(center,cy+dir*3),Vector2(center+6,cy-dir*3)]),Color(STONE,sin(t*PI)),2,true)
		if font!=null:
			var text := str(meters)
			var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
			draw_string(font,Vector2(center-width*.5,size.y-15),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,STONE)
			var unit_width := font.get_string_size("м",HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			draw_string(font,Vector2(center-unit_width*.5,size.y-5),"м",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(STONE,.7))

# Countdown strip under a warning chip (a root about to snap).
class TimerBar extends Control:
	var value := 1.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("00000040"))
		draw_rect(Rect2(Vector2.ZERO,Vector2(size.x*clampf(value,0,1),size.y)),Color("fff1e8"))

# A find flying from the ledge into its backpack cell along an arc.
class PickupFlyer extends Control:
	var item: Dictionary = {}
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var duration := .5
	var t := 0.0
	var landed := Callable()
	var trail: Array[Vector2] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func point_at(k: float) -> Vector2:
		var control := (from+to)*.5+Vector2(0,-minf(220,from.distance_to(to)*.45))
		return from.lerp(control,k).lerp(control.lerp(to,k),k)

	func _process(delta: float) -> void:
		t = minf(1,t+delta/duration)
		trail.append(point_at(ease(t,.6)))
		if trail.size()>7: trail.remove_at(0)
		queue_redraw()
		if t>=1:
			if landed.is_valid(): landed.call()
			queue_free()

	func _draw() -> void:
		var color := LootIcon.rarity_color(item)
		for index in range(trail.size()):
			var k := float(index+1)/trail.size()
			draw_circle(trail[index],2+4*k,Color(color,.35*k))
		var k := ease(t,.6)
		var scale := lerpf(1.5,1.0,k)*(1+.15*sin(t*PI))
		LootIcon.draw(self,item,point_at(k),40*scale,t*4)

# Rising "+80" over the backpack when a find lands.
class FloatText extends Control:
	var text := ""
	var color := HOLD
	var font: Font
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta/.9
		queue_redraw()
		if t>=1: queue_free()

	func _draw() -> void:
		if font==null: return
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x
		var at := Vector2(-width*.5,-ease(t,.4)*34)
		var alpha := 1.0-maxf(0,t-.55)/.45
		draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,22,6,Color(SLATE_LIP,alpha))
		draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color(color,alpha))

# Expanding ring where a find lands.
class Burst extends Control:
	var color := HOLD
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta/.4
		queue_redraw()
		if t>=1: queue_free()

	func _draw() -> void:
		var radius := 18+ease(t,.4)*22
		draw_arc(Vector2.ZERO,radius,0,TAU,32,Color(color,1-t),3*(1-t)+1,true)
		for index in range(6):
			var direction := Vector2.from_angle(TAU*index/6+.3)
			draw_line(direction*(radius-4),direction*(radius+5),Color(color,1-t),2,true)

# A discarded find tipping out of its cell and falling away.
class DiscardGhost extends Control:
	var item: Dictionary = {}
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta/.55
		queue_redraw()
		if t>=1: queue_free()

	func _draw() -> void:
		var drop := Vector2(10*t,-14*sin(t*PI*.6)+60*t*t)
		modulate.a = 1-t
		LootIcon.draw(self,item,drop,40*(1-.3*t),0,t*1.4)
