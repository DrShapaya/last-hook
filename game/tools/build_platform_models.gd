extends SceneTree

# Authors the rest-platform models in assets/models/platforms: a timber deck
# in two support styles (timber braces, iron brackets) and every width of
# WoodPlatform.WIDTHS, exported as glTF so they can be reworked in Blender,
# plus the tileable wood grain they share. Every board is chamfered, the deck
# boards differ a little in width, length, height and tone, and the joints
# carry iron straps, bolts and rope lashings. The grain is its own texture. Fixed seeds: the files only
# change when this script does. After running it, reimport:
#   Godot --headless --path game --script res://tools/build_platform_models.gd
#   Godot --headless --path game --import

const WoodPlatform := preload("res://scripts/wood_platform.gd")
const PLANK := Color("b07e4c")
const BEAM := Color("7e5634")
const IRON := Color("47403b")
const ROPE := Color("cfae72")
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
	for part in ["wood","iron","rope"]:
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
	var root := Node3D.new()
	root.name = "Platform_%s_%d" % [style,roundi(width*100)]
	# The grain stays a separate texture (wood_grain.png) that the game lays
	# over the wood; the models carry the UVs and vertex tones.
	var materials := {
		"wood":_material(.86,0.0),
		"iron":_material(.45,.55),
		"rope":_material(.95,0.0)}
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
				_cylinder("iron",nail,Vector3.UP,.011,.004,6,IRON.lightened(.08))
		var fascia_nail := shear*Vector3(x,-.05,depth+.038)
		_cylinder("iron",fascia_nail,Vector3.BACK,.01,.004,6,IRON.lightened(.08))
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
