class_name DesertRock
extends RockSurface

# Sandstone as in references/location/desert_4k.png and desertClose.png: thick
# beds swelling into lenses with creases between them, rounded at the mask's
# edge, tilted and wavy, never ruled lines. Faces turned up catch pale light,
# undersides go a deep warm brown, and fine bands of colour run along the beds.

const BED_MIN := 1.6
const BED_MAX := 7.0

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

# Rounded boulders on the ledges and gravel spilled along them.
func lumps(low: float, high: float) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector2i(random_seed,roundi(low)))
	var result: Array = []
	for spot in perches(low,high,random,420):
		var at := Vector2(spot.x,spot.y)
		if not _clear_of_grips(at,1.7): continue
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

# Where a point falls on a ledge, 0 at its foot, 1 at its top, -1 off it.
func _on_ledge(point: Vector2) -> float:
	for ledge in layout.rock_marks:
		var low := float(ledge[0])-.7
		var high := float(ledge[1])+.5
		if point.y>=low and point.y<=high and absf(point.x-float(ledge[3]))<=float(ledge[2]): return (point.y-low)/(high-low)
	return -1.0

func height(point: Vector2) -> float:
	var inside := distance(point)
	# Rounded off at the edge, full and nearly flat further in.
	var body := 1.0-exp(-maxf(inside,0.0)/1.5)
	var bed := _in_bed(_warped(point))
	# Each bed swells to a lens: the crease between two is its low line.
	# Thick beds swell far; thin ones are hardly more than a line.
	var lens := pow(sin(PI*bed.x),.5)*clampf(bed.y*.28,.3,1.0)
	var z := RIM_Z+body*(2.2+lens*1.75)+relief.get_noise_2d(point.x,point.y*1.6)*.42
	# A ledge stands out of the wall: it leans back to a flat top and is cut
	# away underneath.
	var ledge := _on_ledge(point)
	if ledge>=0.0: z = maxf(z,RIM_Z+body*(3.75-pow(absf(ledge-.42)*2.0,1.6)*2.6))+relief.get_noise_2d(point.x*.8,point.y)*.18
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
	var shake := float(hash(Vector3i(roundi(center.x*9.0),roundi(center.y*9.0),3))%1000)/1000.0-.5
	return color.lightened(shake*.09) if shake>0 else color.darkened(-shake*.09)
