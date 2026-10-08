class_name UiSymbol
extends Control

var kind := 0
var tint := Color("f3c668")
var tip_count := 3

func stroke(points: Array, width: float = 2.0, color: Color = Color.TRANSPARENT) -> void:
	draw_polyline(PackedVector2Array(points),tint if color==Color.TRANSPARENT else color,width,true)

func plate(rect: Rect2, color: Color, radius: int = 4) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	draw_style_box(box,rect)

func _draw() -> void:
	draw_set_transform(size*.5,0,Vector2.ONE*minf(size.x,size.y)/32)
	var soft := Color(tint,.18)
	match kind:
		0: # Rope spool, separate from the hook.
			plate(Rect2(-7,-8,14,16),soft,3)
			for y in [-7,-3,1,5]: stroke([Vector2(-7,y),Vector2(7,y+3)],1.7)
			stroke([Vector2(-9,-11),Vector2(-9,10),Vector2(8,10)],2.3)
			stroke([Vector2(-9,-11),Vector2(9,-11),Vector2(9,5),Vector2(13,8),Vector2(13,12)])
		1:
			draw_colored_polygon(PackedVector2Array([Vector2(2,-13),Vector2(-9,2),Vector2(-1,2),Vector2(-4,13),Vector2(10,-3),Vector2(2,-3)]),tint)
			stroke([Vector2(-12,6),Vector2(-8,6)],1.5,Color(tint,.55))
			stroke([Vector2(7,-9),Vector2(12,-9)],1.5,Color(tint,.55))
		2:
			draw_arc(Vector2(0,-9),3,0,TAU,24,tint,2,true)
			stroke([Vector2(0,-6),Vector2(0,6)],2.4)
			stroke([Vector2(0,5),Vector2(5,9),Vector2(10,6),Vector2(11,0),Vector2(7,3)],2.2)
			if tip_count>=2:
				stroke([Vector2(0,5),Vector2(-5,9),Vector2(-10,6),Vector2(-11,0),Vector2(-7,3)],2.2)
			if tip_count>=3:
				stroke([Vector2(0,6),Vector2(0,12),Vector2(4,9)],2.2)
		3:
			plate(Rect2(-10,-8,20,21),soft,5)
			stroke([Vector2(-9,11),Vector2(-10,-3),Vector2(-7,-8),Vector2(7,-8),Vector2(10,-3),Vector2(9,11),Vector2(-9,11)])
			draw_arc(Vector2(0,-8),5,PI,TAU,20,tint,2,true)
			plate(Rect2(-6,2,12,7),Color(tint,.3),2)
			stroke([Vector2(-6,2),Vector2(6,2)],1.6)
		4:
			draw_arc(Vector2(0,2),8,0,PI,30,tint,5,true)
			stroke([Vector2(-8,2),Vector2(-8,-9)],5)
			stroke([Vector2(8,2),Vector2(8,-9)],5)
			stroke([Vector2(-10,-5),Vector2(-6,-5)],1.5,Color("edf7ef"))
			stroke([Vector2(6,-5),Vector2(10,-5)],1.5,Color("edf7ef"))
			for x in [-13,13]: stroke([Vector2(x,-5),Vector2(x,-1)],1,Color(tint,.5))
		5:
			var shield := PackedVector2Array([Vector2(-11,-11),Vector2(11,-11),Vector2(9,5),Vector2(0,13),Vector2(-9,5),Vector2(-11,-11)])
			draw_colored_polygon(shield,soft)
			draw_polyline(shield,tint,2,true)
			stroke([Vector2(-5,0),Vector2(-1,4),Vector2(6,-4)],2.4)
		6:
			stroke([Vector2(-10,9),Vector2(4,-5),Vector2(10,-5)],2.3)
			stroke([Vector2(4,-5),Vector2(4,-11),Vector2(10,-5),Vector2(4,1)],2.2)
			draw_arc(Vector2(-5,2),7,0,PI*.85,20,tint,2.2,true)
			stroke([Vector2(-13,-1),Vector2(-9,-5)],1.5,Color(tint,.55))
		7:
			var mountain := PackedVector2Array([Vector2(-13,10),Vector2(-2,-11),Vector2(12,10)])
			draw_colored_polygon(mountain,soft)
			draw_polyline(mountain,tint,2,true)
			stroke([Vector2(-6,-3),Vector2(-2,1),Vector2(1,-3),Vector2(5,0)],1.5)
		8:
			draw_arc(Vector2(-6,0),6,PI*.25,TAU-PI*.25,28,tint,2.3,true)
			draw_arc(Vector2(6,0),6,-PI*.75,PI*.75,28,tint,2.3,true)
			stroke([Vector2(-2,-4),Vector2(2,4)],2.3)
			stroke([Vector2(-2,4),Vector2(2,-4)],2.3)
		9:
			draw_colored_polygon(PackedVector2Array([Vector2(-6,-10),Vector2(10,0),Vector2(-6,10)]),tint)
		10,11:
			var side := -1 if kind==10 else 1
			stroke([Vector2(-side*3,-7),Vector2(side*4,0),Vector2(-side*3,7)],2.5)
		12:
			draw_circle(Vector2.ZERO,11,soft)
			draw_arc(Vector2.ZERO,10,0,TAU,32,tint,2,true)
			draw_arc(Vector2.ZERO,6,0,TAU,24,Color(tint,.65),1,true)
			stroke([Vector2(0,-4),Vector2(0,4)],2)
		13:
			var gem := PackedVector2Array([Vector2(-11,-4),Vector2(-6,-10),Vector2(6,-10),Vector2(11,-4),Vector2(0,12),Vector2(-11,-4)])
			draw_colored_polygon(gem,soft)
			draw_polyline(gem,tint,1.8,true)
			stroke([Vector2(-11,-4),Vector2(11,-4)],1.5)
			stroke([Vector2(-4,-10),Vector2(-3,-4),Vector2(0,12),Vector2(3,-4),Vector2(4,-10)],1.3)
		14:
			plate(Rect2(-9,-1,18,13),soft,3)
			stroke([Vector2(-9,10),Vector2(-9,-1),Vector2(9,-1),Vector2(9,10),Vector2(-9,10)])
			draw_arc(Vector2(0,-2),6,PI,TAU,20,tint,2,true)
			draw_circle(Vector2(0,5),1.5,tint)
