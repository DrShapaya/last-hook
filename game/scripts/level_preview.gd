class_name LevelPreview
extends Control

var world: MountainWorld

func project(point: Vector2) -> Vector2:
	return Vector2(size.x*.5+point.x*size.x/40,size.y-point.y*size.y/24)

func _draw() -> void:
	if is_instance_valid(world) and world.location!=0:
		_draw_legacy()
		return
	var w := size.x
	var h := size.y
	for band in range(40):
		var color := Color("395b69").lerp(Color("afc7bb"),float(band)/39)
		draw_rect(Rect2(0,h*band/40,w,h/40+1),color)
	draw_circle(Vector2(w*.76,h*.25),h*.32,Color(1,.84,.52,.06))
	draw_circle(Vector2(w*.76,h*.25),h*.19,Color(1,.88,.64,.12))
	draw_circle(Vector2(w*.76,h*.25),h*.105,Color("f7da9d"))
	for layer in range(3):
		var points := PackedVector2Array([Vector2(0,h)])
		for index in range(10):
			points.append(Vector2(index*w/9,h*(.46+layer*.13)-sin(index*1.8+layer*2)*h*.14))
		points.append(Vector2(w,h))
		draw_colored_polygon(points,[Color("74928e"),Color("537a79"),Color("365f64")][layer])
	var peak := Vector2(w*.52,h*.13)
	var left := Vector2(w*.12,h)
	var right := Vector2(w*.90,h)
	draw_colored_polygon(PackedVector2Array([left,peak,right]),Color("628378"))
	draw_colored_polygon(PackedVector2Array([peak,Vector2(w*.57,h*.47),Vector2(w*.38,h*.70),left]),Color("96a58b"))
	draw_colored_polygon(PackedVector2Array([peak,Vector2(w*.57,h*.47),Vector2(w*.73,h*.74),right]),Color("3f665e"))
	draw_colored_polygon(PackedVector2Array([peak,Vector2(w*.46,h*.30),Vector2(w*.51,h*.27),Vector2(w*.54,h*.35),Vector2(w*.59,h*.28)]),Color("e5e9d2"))
	for index in range(7):
		var t := float(index)/7
		var point := Vector2(w*(.42+.07*sin(index*1.6)),h*(.86-t*.56))
		draw_circle(point,2.2,Color("efcc84"))
	draw_line(peak+Vector2(0,2),peak+Vector2(0,-16),Color("dbe2cb"),1.4,true)
	draw_colored_polygon(PackedVector2Array([peak+Vector2(0,-16),peak+Vector2(15,-12),peak+Vector2(0,-8)]),Color("f8c969"))
	for index in range(24):
		var x := index*w/23
		var tree_height := h*(.08+.035*sin(index*3.2))
		var base := Vector2(x,h*.96+sin(index)*h*.03)
		draw_colored_polygon(PackedVector2Array([base+Vector2(-8,0),base+Vector2(0,-tree_height),base+Vector2(8,0)]),Color("234b49"))

func clip_triangle(points: Array[Vector2], color: Color) -> void:
	var fields: Array[float] = []
	for p in points: fields.append(world.layout.rock_field(p))
	var polygon := PackedVector2Array()
	for i in range(3):
		var j := (i+1)%3
		if fields[i]>=0: polygon.append(project(points[i]))
		if (fields[i]>=0)!=(fields[j]>=0):
			polygon.append(project(points[i].lerp(points[j],fields[i]/(fields[i]-fields[j]))))
	if polygon.size()>=3: draw_colored_polygon(polygon,color)

func _draw_legacy() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("142438"))
	var ratio := size.x/14
	for side in [-1,1]:
		var points := PackedVector2Array()
		points.append(Vector2(0 if side<0 else size.x,0))
		for index in range(7): points.append(Vector2(size.x*.5+world.cliff_edge(6-index,side)*ratio,index*size.y/6))
		points.append(Vector2(0 if side<0 else size.x,size.y))
		draw_colored_polygon(points,Color("354d66"))
	for anchor in world.anchors:
		var p: Vector2 = anchor["pos"]
		if p.y>24: continue
		var dimensions: Vector2 = anchor["dimensions"]*Vector2(ratio,size.y/24)
		draw_rect(Rect2(Vector2(size.x*.5+p.x*ratio,size.y-p.y*size.y/24)-dimensions*.5,dimensions),MountainWorld.COLORS[anchor["kind"]])
	for obstacle in world.obstacles:
		var p: Vector2 = obstacle["pos"]
		if p.y>24: continue
		var dimensions: Vector2 = obstacle["dimensions"]*Vector2(ratio,size.y/24)
		draw_rect(Rect2(Vector2(size.x*.5+p.x*ratio,size.y-p.y*size.y/24)-dimensions*.5,dimensions),Color("d75c67"))
