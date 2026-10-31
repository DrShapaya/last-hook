class_name DesertRock
extends RockSurface

# Sandstone as in references/location/desert_4k.png and desertClose.png: thick
# beds swelling into lenses with creases between them, rounded at the mask's
# edge, tilted and wavy, never ruled lines. Faces turned up catch pale light,
# undersides go a deep warm brown, and fine bands of colour run along the beds.

const BED_MIN := 1.6
const BED_MAX := 7.0
# How far in from the mask's edge the rock turns to face the viewer.
const ROLL := 2.4
# Depth of the face: at the mask's edge, far enough back to give the rock a
# side, then what a wall, a bed's swell and a ledge rise over it.
const EDGE_Z := -7.5
const WALL_RISE := 5.1
const BED_RISE := 1.2
const LEDGE_RISE := 8.5
# The hollow under a ledge: how far down it reaches and how deep it goes.
const HOLLOW_FALL := 2.6
const HOLLOW_DEPTH := 1.3
# The far wall of a cave, behind the face at its edge, and the size of its facets.
const CAVE_WALL_Z := -8.6
const CAVE_FACET := .8
const CAVE_LIP := 2.5
# Where the floor of a cave meets its far wall, in shares of its half height
# below the centre, and how far forward the floor comes.
const CAVE_FLOOR := .3
const CAVE_FLOOR_RISE := 3.2

var warp := FastNoiseLite.new()
var relief := FastNoiseLite.new()
var bands := FastNoiseLite.new()
var blocks := FastNoiseLite.new()
# Bed borders bottom-up, in warped height.
var beds := PackedFloat32Array()

func _init(level: MaskLayout) -> void:
	super(level)
	warp.seed = random_seed+11
	warp.frequency = .035
	warp.fractal_octaves = 2
	relief.seed = random_seed+12
	relief.frequency = .16
	relief.fractal_octaves = 3
	bands.seed = random_seed+13
	bands.frequency = .9
	bands.fractal_octaves = 1
	blocks.seed = random_seed+15
	blocks.noise_type = FastNoiseLite.TYPE_CELLULAR
	blocks.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	blocks.frequency = .07
	blocks.fractal_type = FastNoiseLite.FRACTAL_NONE
	var random := RandomNumberGenerator.new()
	random.seed = random_seed+14
	var y := origin.y-8.0
	var top := origin.y+size.y*step+8.0
	while y<top:
		beds.append(y)
		y += random.randf_range(BED_MIN,BED_MAX)

func holds_objects() -> bool:
	return true

func _fine_edge() -> bool:
	return true

func _closes_edge() -> bool:
	return false

func _warped(point: Vector2) -> float:
	# Blocks of rock have slipped against each other: beds do not run through.
	return point.y+warp.get_noise_2d(point.x,point.y)*9.0+point.x*.1+blocks.get_noise_2dv(point)*6.0

# Where a height falls in its bed, 0 to 1, and how thick the bed is.
func _in_bed(y: float) -> Vector2:
	var low := 0
	var high := beds.size()-1
	while high-low>1:
		var middle := (low+high)/2
		if beds[middle]<=y: low = middle
		else: high = middle
	return Vector2((y-beds[low])/maxf(.1,beds[high]-beds[low]),beds[high]-beds[low])

# A cave is an edge of the rock like the mask's own: the face rolls away into
# it and shows its side, and what lies behind it is the cave's far wall.
func distance(point: Vector2) -> float:
	return minf(super.distance(point),_to_cave(point))

# How far a point lies from the nearest cave's mouth, flat at the foot.
func _to_cave(point: Vector2) -> float:
	var nearest := INF
	for cave in layout.rock_caves:
		var half := Vector2(float(cave[2]),float(cave[3]))
		var local := (point-Vector2(float(cave[0]),float(cave[1])))/half
		if absf(local.x)>2.6 or absf(local.y)>2.6: continue
		if local.y<0.0: local.y *= 1.6
		var wander := relief.get_noise_2d(point.x*1.4,point.y*1.4)*.3
		nearest = minf(nearest,(local.length()+wander-1.0)*minf(half.x,half.y))
	return nearest

# The far wall of a cave: dark faceted rock, the floor catching a little light.
func _emit_behind(low: float, high: float, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	for cave in layout.rock_caves:
		var center := Vector2(float(cave[0]),float(cave[1]))
		if center.y<low or center.y>=high: continue
		var reach := Vector2(float(cave[2]),float(cave[3]))*1.25
		var spot := func(i: int, j: int) -> Vector3:
			var at := center+Vector2(i+(_hash(i,j,21)-.5)*.7,j+(_hash(i,j,22)-.5)*.7)*CAVE_FACET
			# The floor runs forward to the lip; above it the wall stands far back.
			var ramp := clampf((-(at.y-center.y)/reach.y-CAVE_FLOOR)/(1.0-CAVE_FLOOR),0,1)
			return Vector3(at.x,at.y,CAVE_WALL_Z+ramp*CAVE_FLOOR_RISE+(_hash(i,j,23)-.5)*.5)
		for j in range(-int(reach.y/CAVE_FACET)-1,int(reach.y/CAVE_FACET)+1):
			for i in range(-int(reach.x/CAVE_FACET)-1,int(reach.x/CAVE_FACET)+1):
				var a: Vector3 = spot.call(i,j)
				var b: Vector3 = spot.call(i+1,j)
				var c: Vector3 = spot.call(i+1,j+1)
				var d: Vector3 = spot.call(i,j+1)
				for facet in [[a,b,c],[a,c,d]]: _emit_cave_wall(facet,center,reach,vertices,normals,colors)

func _emit_cave_wall(facet: Array, center: Vector2, reach: Vector2, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var a: Vector3 = facet[0]
	var b: Vector3 = facet[1]
	var c: Vector3 = facet[2]
	var middle := (a+b+c)/3.0
	var height_in := (middle.y-center.y)/reach.y
	var normal := (c-a).cross(b-a).normalized()
	if normal.z<0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	# Black under the roof, a little light on the far wall low down, and the
	# floor lit from the mouth, brightest at the front.
	var color := Color("0b0604").lerp(Color("1d0f08"),smoothstep(.7,-.3,height_in))
	color = color.lerp(Color("8f5c34"),smoothstep(CAVE_FLOOR*-.8,-.8,height_in))
	var shake := float(hash(Vector3i(roundi(middle.x*9.0),roundi(middle.y*9.0),5))%1000)/1000.0-.5
	color = color.lightened(shake*.06) if shake>0 else color.darkened(-shake*.2)
	for point in [a,b,c]:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)

func _near_cave(point: Vector2) -> bool:
	for cave in layout.rock_caves:
		if ((point-Vector2(float(cave[0]),float(cave[1])))/Vector2(float(cave[2])+.9,float(cave[3])+.9)).length()<1.0: return true
	return false

# Rounded boulders on the ledges and gravel spilled along them.
func lumps(low: float, high: float) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector2i(random_seed,roundi(low)))
	var result: Array = []
	for spot in perches(low,high,random,420):
		var at := Vector2(spot.x,spot.y)
		if not _clear_of_grips(at,1.7) or _near_cave(at): continue
		var roll := random.randf()
		if roll<.12:
			var size := random.randf_range(.55,1.1)
			result.append([Vector3(at.x,at.y+size*.62,spot.z+.2),Vector3(size*1.15,size*.85,size)])
		else:
			for stone in range(random.randi_range(2,5)):
				var small := random.randf_range(.09,.24)
				result.append([Vector3(at.x+random.randf_range(-.9,.9),at.y+small*.5+random.randf_range(-.08,.08),spot.z+.12),Vector3(small*1.3,small,small)])
		if result.size()>110: break
	return result

# Where a point falls on a ledge: x is 0 at its foot, 1 at its top, -1 off it;
# y is 1 along the ledge, falling to 0 at its ends; z is how deep it lies in
# the hollow under the ledge, 0 to 1.
func _on_ledge(point: Vector2) -> Vector3:
	for ledge in layout.rock_marks:
		var low := float(ledge[0])-.7
		var high := float(ledge[1])+.5
		var along := absf(point.x-float(ledge[3]))
		if point.y<low-HOLLOW_FALL or point.y>high or along>float(ledge[2]): continue
		var fade := 1.0-smoothstep(float(ledge[2])-2.5,float(ledge[2]),along)
		var share := (point.y-low)/(high-low)
		return Vector3(share if share>=0.0 else -1.0,fade,fade*smoothstep(low-HOLLOW_FALL,low,minf(point.y,low+(low-point.y))))
	return Vector3(-1,0,0)

func height(point: Vector2) -> float:
	# A cave's mouth is a short sharp lip: a wide roll round it would read as
	# a mound, not a hollow.
	var inside := minf(super.distance(point),_to_cave(point)*CAVE_LIP)
	# The rock rolls away from the viewer towards its edge, a quarter of a
	# round, and stands full further in.
	var roll := 1.0-clampf(inside/ROLL,0,1)
	var body := sqrt(1.0-roll*roll)
	var bed := _in_bed(_warped(point))
	# Each bed swells to a lens: the crease between two is its low line.
	# Thick beds swell far; thin ones are hardly more than a line.
	var lens := pow(sin(PI*bed.x),.5)*clampf(bed.y*.28,.3,1.0)
	# Walls stand well back and swell slowly as whole masses.
	var swell := warp.get_noise_2d(point.x+200.0,point.y*.7)*1.2
	var z := EDGE_Z+body*(WALL_RISE+lens*BED_RISE+swell)+relief.get_noise_2d(point.x,point.y*1.6)*.42
	# A ledge stands out of the wall: it leans back to a flat top and overhangs
	# a hollow cut away underneath it.
	var ledge := _on_ledge(point)
	z -= ledge.z*HOLLOW_DEPTH*body
	if ledge.x>=0.0:
		var fall := pow((.42-ledge.x)/.42,1.3)*5.6 if ledge.x<.42 else pow((ledge.x-.42)/.58,1.6)*3.3
		var shelf := EDGE_Z+body*(LEDGE_RISE-fall)
		z = maxf(z,lerpf(z,shelf,ledge.y))+relief.get_noise_2d(point.x*.8,point.y)*.18
	return minf(z,FRONT_Z)

func facet_color(center: Vector3, normal: Vector3) -> Color:
	var at := Vector2(center.x,center.y)
	var wave := _warped(at)
	var band := bands.get_noise_2d(at.x*.05,wave)
	var color := Color("93592e").lerp(Color("a96d3c"),clampf(.5+band*1.6,0,1))
	# Thin darker veins between bands.
	if absf(band)<.05: color = color.lerp(Color("7f4d29"),.4)
	var up := clampf(normal.y,-1,1)
	if up>0: color = color.lerp(Color("b98a58"),smoothstep(.1,.7,up)*.75)
	else: color = color.lerp(Color("5a3119"),smoothstep(.05,.7,-up)*.9)
	# The crease between two beds lies in shade.
	var bed := _in_bed(wave)
	var crease := 1.0-sin(PI*bed.x)
	color = color.lerp(Color("5f351c"),smoothstep(.6,1.0,crease)*clampf(bed.y*.14,.12,.6))
	color = color.lerp(Color("6e4226"),clampf((RIM_Z+1.2-center.z)/2.6,0,.55))
	# The hollow under a ledge lies in deep shade, shadow map or not.
	color = color.lerp(Color("4c2815"),_on_ledge(at).z*.75)
	# Faces turning away to the side fall into shade, so the edge reads round.
	color = color.lerp(Color("6b3f22"),(1.0-smoothstep(.3,.85,normal.z))*.35)
	var shake := float(hash(Vector3i(roundi(center.x*9.0),roundi(center.y*9.0),3))%1000)/1000.0-.5
	return color.lightened(shake*.09) if shake>0 else color.darkened(-shake*.09)
