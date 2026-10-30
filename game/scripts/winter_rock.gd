class_name WinterRock
extends RockSurface

# Ice-cut rock as in references/location/winter_4k.png: long diamond blades all
# raked the same way, neutral grey going blue in shade, ice streaks running
# down the walls. Shelves are slabs seen a little from above: a snow top with
# stones on it over a dark broken front.

const LEAN := .24
const SHELF_SNOW := .42

var blades := FastNoiseLite.new()
var fine := FastNoiseLite.new()
var along := Vector2(sin(LEAN),cos(LEAN))
var across := Vector2(cos(LEAN),-sin(LEAN))

func _init(level: MaskLayout) -> void:
	super(level)
	blades.seed = random_seed+21
	blades.noise_type = FastNoiseLite.TYPE_SIMPLEX
	blades.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	blades.fractal_octaves = 2
	blades.frequency = .3
	fine.seed = random_seed+22
	fine.frequency = .3
	fine.fractal_octaves = 2

# Facets run long up the lean.
func _basis() -> Vector3:
	return Vector3(1.0,2.7,LEAN)

# How far up a blade a point stands, 0 in a seam, 1 on the crest.
func _blade(point: Vector2) -> float:
	return clampf(.5+blades.get_noise_2d(point.dot(across),point.dot(along)*.2)*.75,0,1)

# Where a point falls on a shelf: 0 at its front edge, 1 at its back, -1 off.
func _on_shelf(point: Vector2) -> float:
	for shelf in layout.rock_marks:
		var x := float(shelf[0])
		var half := float(shelf[2])
		if absf(point.x-x)>half: continue
		var top := float(shelf[1])+float(shelf[3])*(point.x-x)
		var thick := float(shelf[4])
		if point.y<=top and point.y>=top-thick: return (point.y-top+thick)/thick
	return -1.0

func lumps(low: float, high: float) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector2i(random_seed,roundi(low)))
	var result: Array = []
	for shelf in layout.rock_marks:
		var y := float(shelf[1])
		if y<low or y>=high: continue
		for stone in range(roundi(float(shelf[2])*4.0)):
			var x := float(shelf[0])+random.randf_range(-1.0,1.0)*float(shelf[2])
			var at := Vector2(x,y+float(shelf[3])*(x-float(shelf[0]))-float(shelf[4])*random.randf_range(.1,.5))
			if not _clear_of_grips(at,1.3): continue
			var small := random.randf_range(.1,.34)
			result.append([Vector3(at.x,at.y,height(at)+.14),Vector3(small*1.4,small,small)])
	return result

func height(point: Vector2) -> float:
	var inside := distance(point)
	var body := 1.0-exp(-maxf(inside,0.0)/1.2)
	var shelf := _on_shelf(point)
	if shelf>=0.0: return lerpf(FRONT_Z,RIM_Z+body*3.0,shelf*.75)
	var z := RIM_Z+body*(1.7+_blade(point)*1.9)+fine.get_noise_2d(point.x,point.y)*.25
	return minf(z,FRONT_Z-.1)

func facet_color(center: Vector3, normal: Vector3) -> Color:
	var at := Vector2(center.x,center.y)
	var shelf := _on_shelf(at)
	var shake := float(hash(Vector3i(roundi(center.x*9.0),roundi(center.y*9.0),5))%1000)/1000.0
	if shelf>=SHELF_SNOW: return Color("9ea4bc").lerp(Color("868da8"),shake)
	if shelf>=0.0: return Color("3d4a58").lerp(Color("55636f"),shake)
	var crest := _blade(at)
	var color := Color("3b4856").lerp(Color("6c7a88"),crest).lightened(shake*.1)
	# Ice runs down the wall under a shelf and down the seams.
	var column := float(hash(roundi(center.x*2.0)+random_seed)%100)/100.0
	if column<.2 and _under_shelf(at): color = color.lerp(Color("4f8fbe"),.5)
	elif crest<.08: color = color.lerp(Color("4f8fbe"),.22)
	if normal.y>.72: color = color.lerp(Color("9aa3b8"),smoothstep(.72,.92,normal.y))
	elif normal.y< -.25: color = color.lerp(Color("26364a"),.6)
	return color

func _under_shelf(point: Vector2) -> bool:
	for shelf in layout.rock_marks:
		if absf(point.x-float(shelf[0]))>float(shelf[2]): continue
		var below := float(shelf[1])-float(shelf[4])-point.y
		if below>=0.0 and below<4.5: return true
	return false
