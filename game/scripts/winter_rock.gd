class_name WinterRock
extends RockSurface

# Ice-cut rock as in references/location/winter_4k.png and winterClose.png: a
# tower of big angular column blocks, all leaning with the wind, with deep
# cracks between the columns. Each block is a few flat planes, so the face
# reads as stone, not as a mesh. The rock rolls back at its edge as the
# desert's does, so the tower stands well out of the dark. Shelves are thick
# slabs out of the tower: a snow top tilted to the viewer, a dark front, and a
# shaded hollow with ice under them.

const LEAN := .24
# How far in from the mask's edge the rock turns to face the viewer, and how
# far back its edge lies.
const ROLL := 2.2
const EDGE_Z := -7.0
# Where the face of a column block stands, fully in from the edge.
const WALL_Z := .2
# Columns: their width across the lean and the length of a block up it.
const COLUMN := 4.2
const BLOCK_MIN := 4.0
const BLOCK_MAX := 8.5
# How far back a crack between columns cuts, and a joint between two blocks.
const SEAM := 2.6
const JOINT := 1.1
# Width of a crack's slope and of a joint's, in units.
const SEAM_SLOPE := .95
const JOINT_TOP := 1.3
const JOINT_FOOT := .9
# Shelves: the share of a slab that is its snow top, how far its front stands
# out, and the hollow under it.
const SHELF_SNOW := .38
const SHELF_Z := .85
const HOLLOW_FALL := 2.4
const HOLLOW_DEPTH := 2.0

const STONE_LIT := Color("8794a8")
const STONE := Color("67748a")
const STONE_SHADE := Color("3a4560")
const SNOW := Color("dde5ef")
const SNOW_SHADE := Color("9fb0c8")
const ICE := Color("5aa6e0")
const DEEP := Color("1f2a40")

var fine := FastNoiseLite.new()
var wobble := FastNoiseLite.new()
var along := Vector2(sin(LEAN),cos(LEAN))
var across := Vector2(cos(LEAN),-sin(LEAN))

func _init(level: MaskLayout) -> void:
	super(level)
	fine.seed = random_seed+22
	fine.frequency = .3
	fine.fractal_octaves = 2
	wobble.seed = random_seed+24
	wobble.frequency = .06
	wobble.fractal_octaves = 1

func holds_objects() -> bool:
	return true

func _fine_edge() -> bool:
	return true

# The face rolls far back at its edge by itself.
func _closes_edge() -> bool:
	return false

# Facets run long up the lean.
func _basis() -> Vector3:
	return Vector3(1.35,2.4,LEAN)

func _cell_hash(k: int, m: int, salt: int) -> float:
	return float(hash(Vector3i(k,m,salt+random_seed%100003))%100000)/100000.0

# The column block a point falls in: x is 0 in the crack beside a column and
# 1 on its face, y is 0 at a joint between two blocks and 1 on the face, z is
# the block's own depth: its offset and the tilt of its planes; w names the
# block, its column in whole multiples of 4096.
func _block(point: Vector2) -> Vector4:
	var u := point.dot(across)+wobble.get_noise_2d(point.x,point.y*.4)*1.1
	var v := point.dot(along)
	var k := int(floor(u/COLUMN))
	var t := u/COLUMN-k
	# The crest of a column stands off its middle, so its two sides differ.
	var crest := .3+_cell_hash(k,0,1)*.4
	var col := clampf(minf(t/crest,(1.0-t)/(1.0-crest))*COLUMN*crest/SEAM_SLOPE,0,1)
	var length := lerpf(BLOCK_MIN,BLOCK_MAX,_cell_hash(k,0,2))
	var shifted := v+_cell_hash(k,0,3)*length
	var m := int(floor(shifted/length))
	var s := (shifted-m*length)
	var row := clampf(minf(s/JOINT_FOOT,(length-s)/JOINT_TOP),0,1)
	var offset := (_cell_hash(k,m,4)-.5)*1.3
	var tilt := (t-crest)*(_cell_hash(k,m,5)-.5)*2.2+(s/length-.5)*(_cell_hash(k,m,6)-.5)*1.2
	return Vector4(col,row,offset+tilt,float(k*4096+posmod(m,4096)))

# Where a point falls on a shelf: x is 0 at its top edge and 1 at its foot,
# above 1 in the hollow under it, -1 off it; y fades to 0 at its ends.
func _on_shelf(point: Vector2) -> Vector2:
	for shelf in layout.rock_marks:
		var dx := point.x-float(shelf[0])
		var half := float(shelf[2])
		if absf(dx)>half: continue
		var top := float(shelf[1])+float(shelf[3])*dx
		var thick := float(shelf[4])
		if point.y>top or point.y<top-thick-HOLLOW_FALL: continue
		return Vector2((top-point.y)/thick,1.0-smoothstep(half-1.5,half,absf(dx)))
	return Vector2(-1,0)

func lumps(low: float, high: float) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector2i(random_seed,roundi(low)))
	var result: Array = []
	for shelf in layout.rock_marks:
		var y := float(shelf[1])
		if y<low or y>=high: continue
		for stone in range(roundi(float(shelf[2])*6.0)):
			var x := float(shelf[0])+random.randf_range(-.9,.9)*float(shelf[2])
			var at := Vector2(x,y+float(shelf[3])*(x-float(shelf[0]))-float(shelf[4])*random.randf_range(.08,.3))
			if distance(at)<.6 or not _clear_of_grips(at,1.3): continue
			var small := random.randf_range(.1,.36)
			# Back against the shelf: plants on it stand in front.
			result.append([Vector3(at.x,at.y,height(at)-small-.25),Vector3(small*1.4,small,small)])
	return result

func _body(point: Vector2) -> float:
	var roll := 1.0-clampf(distance(point)/ROLL,0,1)
	return sqrt(1.0-roll*roll)

func height(point: Vector2) -> float:
	var body := _body(point)
	var block := _block(point)
	var face := WALL_Z+block.z-SEAM*(1.0-block.x)-JOINT*(1.0-block.y)
	var z := EDGE_Z+body*(face-EDGE_Z)+fine.get_noise_2d(point.x,point.y)*.04
	var shelf := _on_shelf(point)
	if shelf.x>=0.0 and shelf.y>0.0:
		var slab: float
		if shelf.x<=SHELF_SNOW:
			# The snow top falls towards the viewer from the wall behind.
			slab = lerpf(WALL_Z-.9,SHELF_Z,shelf.x/SHELF_SNOW)+fine.get_noise_2d(point.x*2.0,point.y*2.0)*.06
			slab = EDGE_Z+body*(slab-EDGE_Z)
			z = lerpf(z,slab,shelf.y)
		elif shelf.x<=1.0:
			# The front leans back a little to the slab's foot.
			slab = SHELF_Z-(shelf.x-SHELF_SNOW)*.7+fine.get_noise_2d(point.x*1.6,point.y)*.12
			slab = EDGE_Z+body*(slab-EDGE_Z)
			z = lerpf(z,slab,shelf.y)
		else:
			# Under the slab the wall is cut away, deepest right under it.
			var under := (shelf.x-1.0)*float(_shelf_thick(point))/HOLLOW_FALL
			z -= HOLLOW_DEPTH*body*shelf.y*(1.0-smoothstep(0.0,1.0,under))
	return minf(z,FRONT_Z-.1)

func _shelf_thick(point: Vector2) -> float:
	for shelf in layout.rock_marks:
		if absf(point.x-float(shelf[0]))<=float(shelf[2]): return float(shelf[4])
	return 3.0

func facet_color(center: Vector3, normal: Vector3) -> Color:
	var at := Vector2(center.x,center.y)
	var shake := float(hash(Vector3i(roundi(center.x*9.0),roundi(center.y*9.0),5))%1000)/1000.0-.5
	var shelf := _on_shelf(at)
	var up := clampf(normal.y,-1,1)
	if shelf.y>.3 and shelf.x>=0.0 and shelf.x<=SHELF_SNOW+.05 and up>.15:
		return SNOW_SHADE.lerp(SNOW,smoothstep(.15,.6,up)).lightened(shake*.04)
	var block := _block(at)
	# Each block has its own tone, so its planes read as one stone.
	var tone := _cell_hash(int(block.w),0,7)
	var column := int(floor(block.w/4096.0))
	var color := STONE.lerp(STONE_LIT,tone*.7)
	# Faces turned away fall into a cold shade, so blocks and the edge read round.
	color = color.lerp(STONE_SHADE,(1.0-smoothstep(.35,.9,normal.z))*.55)
	if up<0.0: color = color.lerp(STONE_SHADE,smoothstep(.05,.6,-up)*.7)
	# Deep in a crack the stone goes dark, and some cracks are full of ice.
	var crack := 1.0-block.x
	var icy := _cell_hash(column,0,8)<.22
	if icy: color = color.lerp(ICE,smoothstep(.7,1.0,crack)*.7)
	else: color = color.lerp(DEEP,smoothstep(.6,1.0,crack)*.5)
	# The front of a shelf is dark broken stone; the hollow under it is in
	# deep shade, with ice running down from the slab.
	if shelf.y>.3 and shelf.x>SHELF_SNOW and shelf.x<=1.0: color = color.lerp(STONE_SHADE,.55)
	elif shelf.y>.3 and shelf.x>1.0:
		var streak := float(hash(roundi(center.x*1.5)+random_seed)%100)/100.0
		color = color.lerp(DEEP,.55*shelf.y)
		if streak<.3: color = color.lerp(ICE,.55)
	# Snow settles on whatever faces the sky, thick on the tops of blocks.
	if up>.35:
		var drift := fine.get_noise_2d(center.x*.7,center.y*.7)*.5+.5
		color = color.lerp(SNOW_SHADE.lerp(SNOW,drift),smoothstep(.35,.75,up)*.9)
	return color.lightened(shake*.025) if shake>0 else color.darkened(-shake*.025)
