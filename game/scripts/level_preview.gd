class_name LevelPreview
extends Control

# Postcard of the selected route in the same daylight palette as the climb:
# faceted limestone peaks, lit from the upper left, with the hold line drawn
# up the main face to the summit flag.
var world: MountainWorld

const ROCK_LIT := Color("e9e4d6")
const ROCK_MID := Color("cfc8b4")
const ROCK_SHADE := Color("a99f88")
const ROCK_DEEP := Color("8a8270")

func _draw() -> void:
	var w := size.x
	var h := size.y
	var location: int = world.location if is_instance_valid(world) else 0
	for band in range(40):
		draw_rect(Rect2(0,h*band/40,w,h/40+1),MenuSurface.SKY_TOP.lerp(MenuSurface.SKY_LOW,float(band)/39))
	var far := PackedVector2Array([Vector2(0,h)])
	for index in range(9):
		far.append(Vector2(index*w/8,h*(.52-.1*sin(index*1.9+location))))
	far.append(Vector2(w,h))
	draw_colored_polygon(far,MenuSurface.RIDGE_FAR)
	var peaks: Array = [[.5,.12,.40]]
	if location==1: peaks = [[.30,.30,.17],[.70,.24,.16],[.5,.10,.17]]
	elif location==2: peaks = [[.24,.40,.22],[.78,.36,.22],[.5,.14,.30]]
	for peak in peaks:
		facet_peak(Vector2(w*peak[0],h*peak[1]),w*peak[2],h)
	if location==2:
		for index in range(5):
			var at := Vector2(w*(.40+index*.05),h*(.15+absf(index-2)*.035))
			draw_rect(Rect2(at-Vector2(6,14),Vector2(12,14)),ROCK_LIT)
			draw_rect(Rect2(at-Vector2(6,14),Vector2(4,14)),ROCK_SHADE)
		for index in range(4):
			draw_circle(Vector2(w*(.1+index*.27),h*.58),h*.06,Color(1,1,1,.55))
	var summit: Array = peaks[-1]
	var top := Vector2(w*summit[0],h*summit[1])
	var spread: float = w*summit[2]
	for index in range(7):
		var t := float(index+1)/8
		var point := Vector2(top.x+sin(index*2.3)*spread*.32*(1-t*.6),h-(h-top.y)*t*.92)
		draw_colored_polygon(PackedVector2Array([point+Vector2(-7,-2),point+Vector2(7,-2),point+Vector2(5,2),point+Vector2(-5,2)]),[MenuSurface.HOLD,Color("62c46c"),Color("9b7be0")][index%3] if index%3!=0 else MenuSurface.HOLD)
	draw_line(top+Vector2(0,2),top+Vector2(0,-20),MenuSurface.INK,2,true)
	draw_colored_polygon(PackedVector2Array([top+Vector2(1,-20),top+Vector2(17,-15),top+Vector2(1,-10)]),MenuSurface.HOLD)
	for index in range(16):
		var base := Vector2(index*w/15+sin(index*3.1)*8,h*(.97+.02*sin(index)))
		var tuft := h*(.05+.02*sin(index*2.7))
		draw_colored_polygon(PackedVector2Array([base+Vector2(-9,0),base+Vector2(-2,-tuft),base+Vector2(3,-tuft*.6),base+Vector2(9,0)]),Color("4a9a52") if index%2 else Color("3c8446"))

func facet_peak(top: Vector2, half: float, bottom: float) -> void:
	var left := Vector2(top.x-half*1.15,bottom)
	var right := Vector2(top.x+half*1.15,bottom)
	var ridge := top.lerp(Vector2(top.x+half*.15,bottom),.45)
	var shoulder_l := top.lerp(left,.42)+Vector2(-half*.08,0)
	var shoulder_r := top.lerp(right,.38)+Vector2(half*.1,0)
	draw_colored_polygon(PackedVector2Array([top,shoulder_l,ridge]),ROCK_LIT)
	draw_colored_polygon(PackedVector2Array([top,ridge,shoulder_r]),ROCK_SHADE)
	draw_colored_polygon(PackedVector2Array([shoulder_l,left,Vector2(top.x-half*.2,bottom),ridge]),ROCK_MID)
	draw_colored_polygon(PackedVector2Array([ridge,Vector2(top.x-half*.2,bottom),Vector2(top.x+half*.5,bottom)]),ROCK_LIT.darkened(.05))
	draw_colored_polygon(PackedVector2Array([ridge,Vector2(top.x+half*.5,bottom),right,shoulder_r]),ROCK_DEEP)
