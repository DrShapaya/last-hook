extends SceneTree

# Authors the rest-platform models in assets/models/platforms: a timber deck
# in two support styles (timber braces, iron brackets) and every width of
# WoodPlatform.WIDTHS, exported as glTF so they can be reworked in Blender,
# plus the tileable wood grain they share. Wood, iron and rope carry light
# tones that each location tints (WoodPlatform.LOOKS); each model also holds
# the dressing of every location as parts of their own (snow cap and
# icicles, drifted sand, moss with grass and a vine), of which the game keeps
# only the location's (docs/LEVEL_OBJECTS_PLAN.md, stage 4). Every board is chamfered, the deck
# boards differ a little in width, length, height and tone, and the joints
# carry iron straps, bolts and rope lashings. The grain is its own texture. Fixed seeds: the files only
# change when this script does. After running it, reimport:
#   Godot --headless --path game --script res://tools/build_platform_models.gd
#   Godot --headless --path game --import

const WoodPlatform := preload("res://scripts/wood_platform.gd")
# Light base tones: the game's location tint multiplies them (WoodPlatform).
const PLANK := Color("e4cba4")
const BEAM := Color("bf9f7e")
const IRON := Color("8f8a86")
const ROPE := Color("f2e8d4")
const SNOW := Color("e2eaf2")
const SNOW_SHADE := Color("c4d2e2")
const ICE := Color("bfe4f4")
const SAND := Color("c99860")
const SAND_DARK := Color("a87442")
const MOSS := Color("6f8f3a")
const MOSS_DARK := Color("4a6428")
const LEAF := Color("7fa645")
# Grain repeats every metre across a board and every two along it.
const GRAIN_SCALE := Vector2(1.0,.5)

var random := RandomNumberGenerator.new()
var parts := {}
var used := {}
var shear := Transform3D(Basis(Vector3.RIGHT,Vector3.UP,Vector3(0,-WoodPlatform.DECK_FALL/WoodPlatform.DEPTH,1)),Vector3.ZERO)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out := ProjectSettings.globalize_path(WoodPlatform.DIR)
	DirAccess.make_dir_recursive_absolute(out)
	_grain().save_png(ProjectSettings.globalize_path(WoodPlatform.grain_path()))
	for style: String in WoodPlatform.STYLES:
		for width: float in WoodPlatform.WIDTHS:
			random.seed = hash(style)*31+roundi(width*100)
			var scene := _platform(style,width)
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			document.append_from_scene(scene,state)
			var path := ProjectSettings.globalize_path(WoodPlatform.model_path(style,width))
			var error := document.write_to_filesystem(state,path)
			print("PLATFORM ",path," ",error_string(error))
			scene.free()
	quit()

# --- Models -------------------------------------------------------------------------

func _platform(style: String, width: float) -> Node3D:
	parts = {}
	used = {}
	for part in WoodPlatform.PARTS:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[part] = surface
	var half := width*.5
	var depth := WoodPlatform.DEPTH
	var drop: float = WoodPlatform.DROP[style]
	_deck(half,depth)
	# Two joists under the deck, standing past it at both ends, with iron
	# straps round their ends.
	var joists := [depth-.17,.13]
	for z: float in joists:
		var joist := shear*Transform3D(Basis(),Vector3(0,-.145,z))
		_box("wood",joist,Vector3(half+.10,.07,.065),.016,BEAM.lightened(random.randf_range(-.04,.04)),0)
		for side in [-1,1]:
			_box("iron",joist*Transform3D(Basis(),Vector3(side*(half-.02),0,0)),Vector3(.03,.078,.073),.006,IRON,1)
			_bolt(joist*Vector3(side*(half-.02),0,.073),.024,.012)
	if style=="braced": _braces(half,depth,drop,joists[0])
	else: _brackets(half,depth,drop)
	_snow(half,depth)
	_sand(half,depth)
	_moss(half,depth,drop)
	var root := Node3D.new()
	root.name = "Platform_%s_%d" % [style,roundi(width*100)]
	# The grain stays a separate texture (wood_grain.png) that the game lays
	# over the wood; the models carry the UVs and vertex tones.
	var materials := {
		"wood":_material(.86,0.0),
		"iron":_material(.45,.55),
		"nail":_material(.45,.55),
		"rope":_material(.95,0.0),
		"snow":_material(.8,0.0),
		"ice":_material(.2,0.0),
		"sand":_material(.97,0.0),
		"moss":_material(.95,0.0),
		"vine":_material(.9,0.0)}
	for part: String in parts:
		var surface: SurfaceTool = parts[part]
		# A bracket platform has no rope.
		if not used.has(part): continue
		surface.index()
		surface.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.name = part.capitalize()
		mesh.mesh = surface.commit()
		mesh.mesh.surface_set_material(0,materials[part])
		root.add_child(mesh)
		mesh.owner = root
	return root

func _deck(half: float, depth: float) -> void:
	# Boards run out of the face, each a hair lower than its neighbour and
	# its own tone, with one in a few weathered grey; a fascia board along
	# the front closes their ends into one rim.
	var count := roundi(half*2.0/.3)
	var pitch := half*2.0/count
	for index in range(count):
		var board := pitch-random.randf_range(.024,.036)
		var x := -half+pitch*(index+.5)+random.randf_range(-.008,.008)
		var length := depth-random.randf_range(0,.012)
		var sink := random.randf_range(0,.012)
		var tone := PLANK.lightened(random.randf_range(0,.10)) if random.randf()<.5 else PLANK.darkened(random.randf_range(0,.12))
		if random.randf()<.2: tone = tone.lerp(Color("8f8676"),.35)
		var turn := Basis(Vector3.UP,random.randf_range(-.012,.012))
		_box("wood",shear*Transform3D(turn,Vector3(x,-.035-sink,length*.5)),Vector3(board*.5,.035,length*.5),.014,tone,2)
		# Two nails into each joist, on the top just behind the front.
		for z in [depth-.17,.13]:
			for side in [-1,1]:
				var nail := shear*Vector3(x+side*board*.24,-sink+.001,z)
				_cylinder("nail",nail,Vector3.UP,.011,.004,6,IRON.lightened(.08))
		var fascia_nail := shear*Vector3(x,-.05,depth+.038)
		_cylinder("nail",fascia_nail,Vector3.BACK,.01,.004,6,IRON.lightened(.08))
	_box("wood",shear*Transform3D(Basis(),Vector3(0,-.048,depth+.019)),Vector3(half+.05,.054,.018),.01,PLANK.darkened(.06),0)

func _braces(half: float, depth: float, drop: float, joist_z: float) -> void:
	# Timber braces from under the front joist down and in to a wall plate
	# bolted to the rock; a long deck stands on two such frames, a wide one
	# gets a post in the middle too.
	var frames: Array = [[0.0,half-.34]] if half<2.5 else [[-half*.5,half*.5-.3],[half*.5,half*.5-.3]]
	var foot_y := -drop+.10
	for frame: Array in frames:
		var center: float = frame[0]
		var reach: float = frame[1]
		var foot := maxf(.3,reach*.36)
		var plate := Transform3D(Basis(),Vector3(center,foot_y-.02,.07))
		_box("wood",plate,Vector3(foot+.24,.06,.06),.014,BEAM.darkened(.08),0)
		for x in [center-foot-.14,center+foot+.14]: _bolt(Vector3(x,foot_y-.02,.13),.03,.014)
		var tops: Array = [center-reach,center+reach]
		if reach>1.4: tops.append(center)
		for top_x: float in tops:
			var top := shear*Vector3(top_x,-.215,joist_z)
			var low := Vector3(center+signf(top_x-center)*foot,foot_y+.04,.08)
			_timber("wood",top+Vector3(0,.04,0),low,Vector2(.055,.05),BEAM.lightened(random.randf_range(0,.07)))
			_bolt(shear*Vector3(top_x,-.145,joist_z+.065),.028,.014)
			# Rope wound round the joist beside the joint.
			if top_x!=center:
				for offset in [-.10,.10]: _lashing(shear*Transform3D(Basis(),Vector3(top_x+offset,-.145,joist_z)),Vector2(.072,.067))

func _brackets(half: float, depth: float, drop: float) -> void:
	# Knee braces: a short timber from a cleat bolted to the rock up and out
	# to the front joist under each end, an iron angle plate at the top joint;
	# a wide deck gets a pair in the middle too.
	var knees: Array = [[-(half-.62),-(half-.22)],[half-.62,half-.22]]
	if half>1.9: knees.append_array([[-.18,-.62],[.18,.62]])
	if half>3.0: knees.append_array([[-half*.5+.18,-half*.5+.58],[half*.5-.18,half*.5-.58]])
	var foot_y := -drop+.13
	for knee: Array in knees:
		var foot_x: float = knee[0]
		var top_x: float = knee[1]
		var cleat := Transform3D(Basis(),Vector3(foot_x,foot_y-.02,.07))
		_box("wood",cleat,Vector3(.1,.075,.06),.014,BEAM.darkened(.06),0)
		_bolt(Vector3(foot_x,foot_y-.02,.13),.026,.012)
		var top := shear*Vector3(top_x,-.215,depth-.17)
		_timber("wood",top+Vector3(0,.04,0),Vector3(foot_x,foot_y+.02,.09),Vector2(.05,.045),BEAM.lightened(random.randf_range(0,.07)))
		_box("iron",shear*Transform3D(Basis(),Vector3(top_x,-.17,depth-.17+.068)),Vector3(.07,.05,.005),.003,IRON,1)
		_bolt(shear*Vector3(top_x,-.17,depth-.17+.073),.02,.01)

# --- Location dressing ---------------------------------------------------------------

# The deck's top lies on the walking line (y 0) before the shear; the front
# fascia stands this far past the deck.
const DECK_TOP := .0
const FRONT := .038

# A low-poly cap over the deck from the back edge to just past the front:
# a height field `rows` deep whose top stands `thick(x, t)` over the deck
# (t: 0 at the back, 1 at the lip), a front skirt hanging `lip(x)` below the
# deck top and closed ends. Faces get `color(x, t, up)` (up: 1 on top, 0 on
# the skirt and ends).
func _cap(part: String, half: float, depth: float, step: float, rows: int, thick: Callable, lip: Callable, color: Callable) -> void:
	var count := maxi(2,roundi(half*2.0/step))
	var xs: Array[float] = []
	for index in range(count+1):
		var x := -half+half*2.0*index/count
		if index>0 and index<count: x += random.randf_range(-.3,.3)*half*2.0/count
		xs.append(x)
	var grid: Array = []
	for row in range(rows+1):
		var t := float(row)/rows
		var line: Array[Vector3] = []
		for x in xs: line.append(Vector3(x,DECK_TOP+float(thick.call(x,t)),t*(depth+FRONT+.02)))
		grid.append(line)
	for row in range(rows):
		for index in range(count):
			var a: Vector3 = grid[row][index]
			var b: Vector3 = grid[row][index+1]
			var c: Vector3 = grid[row+1][index+1]
			var d: Vector3 = grid[row+1][index]
			var tint: Color = color.call((a.x+b.x)*.5,(row+.5)/rows,1.0)
			_triangle(part,shear*a,shear*b,shear*c,tint)
			_triangle(part,shear*a,shear*c,shear*d,tint.darkened(.03))
	var front: Array = grid[rows]
	for index in range(count):
		var a: Vector3 = front[index]
		var b: Vector3 = front[index+1]
		var low_a := Vector3(a.x,DECK_TOP-float(lip.call(a.x)),a.z)
		var low_b := Vector3(b.x,DECK_TOP-float(lip.call(b.x)),b.z)
		var tone: Color = color.call((a.x+b.x)*.5,1.0,0.0)
		_triangle(part,shear*a,shear*b,shear*low_b,tone)
		_triangle(part,shear*a,shear*low_b,shear*low_a,tone)
	for side in [0,count]:
		var outward := -1.0 if side==0 else 1.0
		for row in range(rows):
			var a: Vector3 = grid[row][side]
			var b: Vector3 = grid[row+1][side]
			var low_a := Vector3(a.x,DECK_TOP-.01,a.z)
			var low_b := Vector3(b.x,DECK_TOP-.01,b.z)
			var tone: Color = color.call(a.x,.5,0.0).darkened(.08)
			if outward>0:
				_triangle(part,shear*a,shear*low_b,shear*b,tone)
				_triangle(part,shear*a,shear*low_a,shear*low_b,tone)
			else:
				_triangle(part,shear*a,shear*b,shear*low_b,tone)
				_triangle(part,shear*a,shear*low_b,shear*low_a,tone)

# Winter: a thick lumpy snow cap rolling over the front edge, icicles under it.
func _snow(half: float, depth: float) -> void:
	var swell := FastNoiseLite.new()
	swell.seed = random.randi()
	swell.frequency = 1.6
	_cap("snow",half+.04,depth,.24,3,
		func(x: float, t: float) -> float: return (.10+.07*sin(PI*minf(t*1.1,1.0)))*(1.0+swell.get_noise_1d(x)*.4)*(1.0 if t<.98 else .75),
		func(x: float) -> float: return .015+maxf(0,swell.get_noise_1d(x*1.7+40.0)-.15)*.16,
		func(x: float, t: float, up: float) -> Color: return SNOW.lerp(SNOW_SHADE,(1.0-up)*.7+t*.15+absf(swell.get_noise_1d(x*2.3+9.0))*.35))
	var x := -half+random.randf_range(.1,.3)
	while x<half-.08:
		_icicle(shear*Vector3(x,-.1,depth+FRONT-.005),random.randf_range(.022,.04),random.randf_range(.1,.34))
		x += random.randf_range(.18,.42)

func _icicle(base: Vector3, radius: float, length: float) -> void:
	var tip := base+Vector3(random.randf_range(-.015,.015),-length,0)
	var ring: Array[Vector3] = []
	for index in range(5):
		var angle := TAU*index/5.0
		ring.append(base+Vector3(cos(angle)*radius,0,sin(angle)*radius))
	for index in range(5):
		_triangle("ice",ring[index],tip,ring[(index+1)%5],ICE.lightened(.12) if index%2==0 else ICE)

# Desert: drifted sand banked against the rock, thinning to bare boards at
# the front, a low heap at one end and a thin trickle off the edge.
func _sand(half: float, depth: float) -> void:
	var drift := FastNoiseLite.new()
	drift.seed = random.randi()
	drift.frequency = 1.1
	var heap_x := random.randf_range(.35,.7)*half*(1.0 if random.randf()<.5 else -1.0)
	_cap("sand",half-.02,depth*.45,.3,3,
		func(x: float, t: float) -> float:
			var bank := (1.0-t)*(.035+maxf(0,drift.get_noise_1d(x))*.05)
			var heap := maxf(0,1.0-absf(x-heap_x)/.45)*(1.0-t*.7)*.07
			return maxf(.004,bank+heap),
		func(_x: float) -> float: return .0,
		func(x: float, t: float, up: float) -> Color: return SAND.lerp(SAND_DARK,(1.0-up)*.5+absf(drift.get_noise_1d(x*3.0))*.3+t*.1))
	# The trickle: a narrow ribbon falling from the lip, facing the camera.
	var at := clampf(heap_x+random.randf_range(-.3,.3),-half+.2,half-.2)
	var top := shear*Vector3(at,-.02,depth+FRONT+.01)
	var fall := random.randf_range(.35,.55)
	var tone := SAND.lightened(.06)
	_triangle("sand",top+Vector3(-.035,0,0),top+Vector3(.035,0,0),top+Vector3(.008,-fall,.02),tone)
	_triangle("sand",top+Vector3(-.035,0,0),top+Vector3(.008,-fall,.02),top+Vector3(-.008,-fall,.02),tone)

# Summer: a moss strip along the front edge and the ends of the deck, grass
# blades out of it, a vine hanging from one end.
func _moss(half: float, depth: float, drop: float) -> void:
	var x := -half-.02
	while x<half:
		var size := Vector3(random.randf_range(.07,.14),random.randf_range(.025,.045),random.randf_range(.05,.09))
		var at := Vector3(x+size.x,size.y*.4,depth+FRONT-size.z*.3)
		_box("moss",shear*Transform3D(Basis(Vector3.UP,random.randf_range(-.4,.4)),at),size,minf(size.y,size.z)*.45,MOSS.lerp(MOSS_DARK,random.randf()),0)
		if random.randf()<.55: _tuft(shear*Vector3(at.x+random.randf_range(-.04,.04),at.y,at.z-.02),random.randf_range(.09,.17))
		x += size.x*2.0+random.randf_range(.02,.22)
	for side in [-1.0,1.0]:
		for k in range(2):
			var size := Vector3(random.randf_range(.04,.07),random.randf_range(.03,.05),random.randf_range(.1,.2))
			_box("moss",shear*Transform3D(Basis(),Vector3(side*(half-size.x*.6),size.y*.3,random.randf_range(.2,depth-.1))),size,size.y*.45,MOSS_DARK.lerp(MOSS,random.randf()),0)
	# The vine hangs from the front corner of one end, within the supports' drop.
	var end := 1.0 if random.randf()<.5 else -1.0
	var hang := shear*Vector3(end*(half-.12),-.06,depth+FRONT+.02)
	var length := random.randf_range(.45,minf(.85,drop))
	var segments := 5
	var previous := hang
	for index in range(1,segments+1):
		var point := hang+Vector3(sin(index*1.3)*.035,-length*index/segments,.01)
		_timber("vine",previous,point,Vector2(.012,.012),MOSS_DARK.darkened(.1))
		var leaf_side := 1.0 if index%2==0 else -1.0
		_box("vine",Transform3D(Basis(Vector3.BACK,leaf_side*.7),point+Vector3(leaf_side*.035,.02,.012)),Vector3(.034,.018,.006),.004,LEAF.lerp(MOSS,random.randf()*.5),0)
		previous = point

# Three crossed grass blades from a base point, both sides.
func _tuft(base: Vector3, height: float) -> void:
	for blade in range(3):
		var lean := Vector3(random.randf_range(-.05,.05)+(blade-1)*.03,height,random.randf_range(-.015,.015))
		var across := Vector3(.012,0,0).rotated(Vector3.UP,blade*1.05)
		var tone := LEAF.lerp(MOSS,random.randf()*.6)
		_triangle("moss",base-across,base+lean,base+across,tone)
		_triangle("moss",base+across,base+lean,base-across,tone)

# One triangle, wound clockwise as seen from its front (Godot's front faces),
# its normal from that winding.
func _triangle(part: String, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var surface: SurfaceTool = parts[part]
	used[part] = true
	var normal := (c-a).cross(b-a).normalized()
	for p in [a,b,c]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.set_uv(Vector2(p.x,p.y))
		surface.add_vertex(p)

# --- Parts --------------------------------------------------------------------------

# Rope wrapped three times round a timber of the given half section (y, z).
func _lashing(frame: Transform3D, section: Vector2) -> void:
	for turn in range(3):
		var at := frame*Transform3D(Basis(),Vector3((turn-1)*.024,0,0))
		var tone := ROPE.darkened(random.randf_range(0,.12))
		var t := .011
		_box("rope",at*Transform3D(Basis(),Vector3(0,section.x+t,0)),Vector3(t,t,section.y+t*2),.004,tone,1)
		_box("rope",at*Transform3D(Basis(),Vector3(0,-section.x-t,0)),Vector3(t,t,section.y+t*2),.004,tone,1)
		_box("rope",at*Transform3D(Basis(),Vector3(0,0,section.y+t)),Vector3(t,section.x+t*2,t),.004,tone,1)

func _bolt(at: Vector3, radius: float, length: float) -> void:
	_cylinder("iron",at,Vector3.BACK,radius,length,6,IRON.lightened(.06))

# A square timber from a to b, its width (x) facing the camera.
func _timber(part: String, a: Vector3, b: Vector3, half: Vector2, color: Color) -> void:
	var axis := (b-a).normalized()
	var across := Vector3.BACK.cross(axis)
	across = across.normalized() if across.length_squared()>.0001 else Vector3.RIGHT
	var normal := axis.cross(across).normalized()
	var frame := Transform3D(Basis(across,normal,axis),(a+b)*.5)
	_box(part,frame,Vector3(half.x,half.y,a.distance_to(b)*.5),minf(half.x,half.y)*.28,color,2)

# A box with chamfered edges in `frame`: six faces inset by the bevel, a
# chamfer strip along each edge and a small triangle at each corner. The
# grain runs along the `long` axis; end grain is darker and the chamfers
# catch a little light like worn edges.
func _box(part: String, frame: Transform3D, half: Vector3, bevel: float, color: Color, long: int) -> void:
	bevel = minf(bevel,minf(half.x,minf(half.y,half.z))*.45)
	var inner := half-Vector3.ONE*bevel
	var offset := Vector2(random.randf(),random.randf())
	var polygons: Array = []
	for axis in range(3):
		var a := (axis+1)%3
		var c := (axis+2)%3
		for s in [-1.0,1.0]:
			var face: Array[Vector3] = []
			for corner in [[-1,-1],[1,-1],[1,1],[-1,1]]:
				var p := Vector3.ZERO
				p[axis] = s*half[axis]
				p[a] = corner[0]*inner[a]
				p[c] = corner[1]*inner[c]
				face.append(p)
			polygons.append([face,color.darkened(.12) if axis==long else color])
	for axis in range(3):
		var a := (axis+1)%3
		var c := (axis+2)%3
		for sa in [-1.0,1.0]:
			for sc in [-1.0,1.0]:
				var strip: Array[Vector3] = []
				for end in [-1.0,1.0,1.0,-1.0]:
					var p := Vector3.ZERO
					p[axis] = end*inner[axis]
					p[a] = sa*(half[a] if strip.size()<2 else inner[a])
					p[c] = sc*(inner[c] if strip.size()<2 else half[c])
					strip.append(p)
				polygons.append([strip,color.lightened(.07)])
	for sx in [-1.0,1.0]:
		for sy in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var corner: Array[Vector3] = [Vector3(sx*half.x,sy*inner.y,sz*inner.z),Vector3(sx*inner.x,sy*half.y,sz*inner.z),Vector3(sx*inner.x,sy*inner.y,sz*half.z)]
				polygons.append([corner,color.lightened(.05)])
	for entry: Array in polygons:
		_polygon(part,frame,entry[0],entry[1],long,offset)

func _polygon(part: String, frame: Transform3D, points: Array[Vector3], color: Color, long: int, offset: Vector2) -> void:
	var center := Vector3.ZERO
	for p in points: center += p
	center /= points.size()
	var normal := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if normal.dot(center)<0:
		normal = -normal
		points.reverse()
	var dominant := 0
	for axis in range(3):
		if absf(normal[axis])>absf(normal[dominant]): dominant = axis
	# Planar UVs on the face's own plane, V along the grain where it shows.
	var u_axis := (dominant+1)%3
	var v_axis := (dominant+2)%3
	if u_axis==long:
		u_axis = v_axis
		v_axis = long
	var world_normal := (frame.basis.inverse().transposed()*normal).normalized()
	var surface: SurfaceTool = parts[part]
	used[part] = true
	for index in range(1,points.size()-1):
		# Godot winds front faces clockwise.
		for p in [points[0],points[index+1],points[index]]:
			var uv := Vector2(p[u_axis],p[v_axis])
			surface.set_color(color)
			surface.set_normal(world_normal)
			surface.set_uv(uv*GRAIN_SCALE+offset)
			surface.add_vertex(frame*p)

func _cylinder(part: String, base: Vector3, axis: Vector3, radius: float, length: float, sides: int, color: Color) -> void:
	var across := axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT).normalized()
	var frame := Transform3D(Basis(across,axis.cross(across),axis),base)
	var ring: Array[Vector3] = []
	for index in range(sides):
		var angle := TAU*(index+.5)/sides
		ring.append(Vector3(cos(angle)*radius,sin(angle)*radius,0))
	var cap: Array[Vector3] = []
	for p in ring: cap.append(p+Vector3(0,0,length))
	_polygon(part,frame,cap,color.lightened(.06),2,Vector2.ZERO)
	for index in range(sides):
		var next := (index+1)%sides
		var side: Array[Vector3] = [ring[index],ring[next],cap[next],cap[index]]
		_polygon(part,frame,side,color,2,Vector2.ZERO)

func _material(roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = roughness
	material.metallic = metallic
	return material

# --- Wood grain ---------------------------------------------------------------------

# Light, tileable grain on a near-white base, so the vertex tones carry the
# colour: wavy growth lines along V, fine fibres and a few knots.
func _grain() -> Image:
	var size := Vector2i(256,512)
	var image := Image.create(size.x,size.y,false,Image.FORMAT_RGB8)
	var warp := FastNoiseLite.new()
	warp.seed = 17
	warp.frequency = .9
	var fibre := FastNoiseLite.new()
	fibre.seed = 29
	fibre.frequency = 2.2
	var knots: Array[Vector3] = [Vector3(.22,.18,.035),Vector3(.71,.55,.028),Vector3(.43,.86,.022)]
	for y in range(size.y):
		# V wraps round a circle so the grain tiles along the board.
		var t := TAU*y/size.y
		var loop := Vector2(cos(t),sin(t))
		for x in range(size.x):
			var u := float(x)/size.x
			var bend := warp.get_noise_3d(u*2.0,loop.x*1.2,loop.y*1.2)*.08
			var lines := sin((u+bend)*TAU*7.0)
			var fine := fibre.get_noise_3d(u*24.0,loop.x*.6,loop.y*.6)
			var value := .84+lines*.045+fine*.05
			for knot in knots:
				var d := Vector2((u-knot.x)*1.0,(float(y)/size.y-knot.y)*2.0)
				var r := d.length()/knot.z
				if r<3.0:
					value -= clampf(1.0-r,0,1)*.28
					value += sin(r*5.0)*.03*clampf(3.0-r,0,1)
			value = clampf(value,0,1)
			image.set_pixel(x,y,Color(value,value*.975,value*.94))
	return image
