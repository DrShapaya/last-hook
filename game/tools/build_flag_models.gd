extends SceneTree

# Authors the flag models in assets/models/flags (see scripts/flora_models.gd):
#   cloths  pole flags - a banner with a sleeve round the pole, a pennant, a
#           swallowtail and a long streamer - and line flags for strings -
#           a bunting triangle, a prayer flag and a rounded bunting. Each is
#           a finely subdivided cloth with folds that deepen towards the free
#           edge and a slight droop there; its UVs carry the painted cloth
#           masks (tools/paint_flag_cloth.py).
#   poles   short, tall and mast: a faceted, tapering timber with an iron
#           foot spike and ferrule, rope lashings, two iron rings that hold
#           the cloth and a forged finial; the mast also has a yard with
#           stays.
# Model space: y up, z towards the camera. A pole stands on the origin; a
# pole flag's cloth starts at the pole (x = 0) under its top (y = 0) and
# runs to +x; a line flag hangs from its cord (y = 0) centred on x = 0.
# Fixed numbers only: the files change when this script does. Afterwards:
#   Godot --headless --path game --script res://tools/build_flag_models.gd
#   Godot --headless --path game --import

const Flora := preload("res://scripts/flora_models.gd")

var parts := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Flora.FLAG_DIR))
	for shape: String in Flora.CLOTH_SIZES:
		parts = {}
		_cloth(shape)
		_export("cloth_%s" % shape)
	for pole: String in Flora.POLE_HEIGHTS:
		parts = {}
		_pole(pole)
		_export("pole_%s" % pole)
	quit()

func _export(name: String) -> void:
	var root := Node3D.new()
	root.name = name.to_pascal_case()
	for part: String in parts:
		var surface: SurfaceTool = parts[part]
		surface.index()
		surface.generate_tangents()
		var mesh := MeshInstance3D.new()
		mesh.name = part.capitalize().replace(" ","")
		mesh.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = .8
		if part=="iron":
			material.metallic = .5
			material.roughness = .45
		mesh.mesh.surface_set_material(0,material)
		root.add_child(mesh)
		mesh.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root,state)
	var error := document.write_to_filesystem(state,ProjectSettings.globalize_path(Flora.FLAG_DIR.path_join("%s.glb" % name)))
	print("FLAG ",name," ",error_string(error))
	root.free()

func _surface(part: String) -> SurfaceTool:
	if not parts.has(part):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[part] = surface
	return parts[part]

# A quad with its normal facing away from `inside`; `uvs` per corner.
func _quad(part: String, points: Array, uvs: Array, color: Color, inside: Vector3, smooth_normals: Array = []) -> void:
	var p0: Vector3 = points[0]
	var p1: Vector3 = points[1]
	var p2: Vector3 = points[2]
	var p3: Vector3 = points[3]
	var normal := (p1-p0).cross(p2-p0)
	if normal.length_squared()<1e-14: normal = (p2-p0).cross(p3-p0)
	normal = normal.normalized()
	var order := [0,2,1,0,3,2]
	var center := (p0+p1+p2+p3)*.25
	if normal.dot(center-inside)<0:
		normal = -normal
		order = [0,1,2,0,2,3]
	var surface := _surface(part)
	for index in order:
		surface.set_color(color)
		surface.set_uv(uvs[index])
		surface.set_normal(smooth_normals[index] if not smooth_normals.is_empty() else normal)
		surface.add_vertex(points[index])

# --- Cloths -------------------------------------------------------------------------

func _cloth(shape: String) -> void:
	var size: Vector2 = Flora.CLOTH_SIZES[shape]
	var line := shape in Flora.LINE_CLOTHS
	var nu := 18 if not line else 8
	var nv := 9 if not line else 12
	var grid: Array = []
	for i in range(nu+1):
		var column: Array = []
		for j in range(nv+1):
			column.append(_cloth_point(shape,size,float(i)/nu,float(j)/nv))
		grid.append(column)
	# Smooth normals from the grid itself, so the folds shade softly.
	var normals: Array = []
	for i in range(nu+1):
		var column: Array = []
		for j in range(nv+1):
			var du: Vector3 = grid[mini(i+1,nu)][j]-grid[maxi(i-1,0)][j]
			var dv: Vector3 = grid[i][mini(j+1,nv)]-grid[i][maxi(j-1,0)]
			var normal := dv.cross(du).normalized()
			if normal.z<0: normal = -normal
			column.append(normal)
		normals.append(column)
	for i in range(nu):
		for j in range(nv):
			var corners := [[i,j],[i+1,j],[i+1,j+1],[i,j+1]]
			var points: Array = []
			var uvs: Array = []
			var smooth: Array = []
			for corner in corners:
				var p: Vector3 = grid[corner[0]][corner[1]]
				points.append(p)
				uvs.append(Vector2(float(corner[0])/nu,float(corner[1])/nv))
				smooth.append(normals[corner[0]][corner[1]])
			var surface := _surface("cloth")
			for index in [0,2,1,0,3,2]:
				surface.set_color(Color.WHITE)
				surface.set_uv(uvs[index])
				surface.set_normal(smooth[index])
				surface.add_vertex(points[index])
	if not line:
		# The sleeve: the cloth wraps round the pole along its inner edge.
		for j in range(nv):
			var y0 := -float(j)/nv*size.y
			var y1 := -float(j+1)/nv*size.y
			for k in range(6):
				var a0 := PI*.5+PI*k/6.0
				var a1 := PI*.5+PI*(k+1)/6.0
				var r := Flora.SLEEVE
				var p := [Vector3(cos(a0)*r,y0,sin(a0)*r),Vector3(cos(a1)*r,y0,sin(a1)*r),Vector3(cos(a1)*r,y1,sin(a1)*r),Vector3(cos(a0)*r,y1,sin(a0)*r)]
				var uv := [Vector2(0,float(j)/nv),Vector2(0,float(j)/nv),Vector2(0,float(j+1)/nv),Vector2(0,float(j+1)/nv)]
				_quad("cloth",p,uv,Color.WHITE,Vector3(0,(y0+y1)*.5,0))
	else:
		# A folded hem over the cord.
		var hem := Color("e9e1cc")
		var half := size.x*.5
		var p := [Vector3(-half,.014,-.006),Vector3(half,.014,-.006),Vector3(half,-.035,.012),Vector3(-half,-.035,.012)]
		_quad("hem",p,[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],hem,Vector3(0,-.01,-.1))

func _cloth_point(shape: String, size: Vector2, u: float, v: float) -> Vector3:
	var x := 0.0
	var y := 0.0
	var free := u
	match shape:
		"banner":
			x = Flora.SLEEVE+u*size.x
			y = -v*size.y
		"pennant":
			x = Flora.SLEEVE+u*size.x
			y = -lerpf(u*.5,1.0-u*.5,v)*size.y
		"swallowtail":
			var notch := .3*size.x
			x = Flora.SLEEVE+u*(size.x-notch*(1.0-absf(v*2.0-1.0)))
			y = -v*size.y
		"streamer":
			var taper := lerpf(1.0,.45,u)
			var notch := .22*size.x
			x = Flora.SLEEVE+u*(size.x-notch*(1.0-absf(v*2.0-1.0)))
			y = -(.5+(v-.5)*taper)*size.y
		"bunting_tri":
			x = (u-.5)*size.x*(1.0-v*.96)
			y = -v*size.y
			free = v
		"prayer":
			x = (u-.5)*size.x
			y = -v*size.y
			free = v
		"bunting_round":
			var round := sqrt(maxf(0.0,1.0-pow(u*2.0-1.0,2.0)))
			x = (u-.5)*size.x
			y = -v*size.y*lerpf(.62,1.0,round)
			free = v
	# Folds deepen away from where the cloth is held; the free edge droops.
	var across := v if free==u else u
	var z := (sin(free*PI*2.6+across*1.1)*.055+sin(free*PI*5.3+across*2.4)*.018)*free
	if free==u: y -= .06*free*free*size.y
	return Vector3(x,y,z)

# --- Poles --------------------------------------------------------------------------

func _pole(kind: String) -> void:
	var length: float = Flora.POLE_HEIGHTS[kind]
	var radius := .028 if kind=="short" else .04 if kind=="tall" else .05
	var wood := Color("8a6240")
	var sides := 8
	var steps := 10
	var rings: Array = []
	for step in range(steps+1):
		var t := float(step)/steps
		var r := radius*lerpf(1.0,.8,t)
		var ring: Array = []
		for index in range(sides):
			var angle := TAU*(index+.5)/sides
			ring.append(Vector3(cos(angle)*r,t*length,sin(angle)*r))
		rings.append(ring)
	for step in range(steps):
		for index in range(sides):
			var next := (index+1)%sides
			# Facets alternate a touch in tone: the timber is hewn, not turned.
			var tone := wood.lightened(.06*cos(TAU*index/sides+.8)).darkened(.04*float((step+index)%2))
			var u0 := float(index)/sides
			var u1 := float(index+1)/sides
			var v0 := float(step)/steps*length
			var v1 := float(step+1)/steps*length
			_quad("wood",[rings[step][index],rings[step][next],rings[step+1][next],rings[step+1][index]],[Vector2(u0,v0),Vector2(u1,v0),Vector2(u1,v1),Vector2(u0,v1)],tone,Vector3(0,(step+.5)/steps*length,0))
	var iron := Color("4a4540")
	# Foot: a ferrule and a spike driven into the rock.
	_band("iron",0.0,radius*1.25,.09,iron)
	_cone("iron",Vector3(0,0,0),Vector3(0,-.12,0),radius*1.1,iron.darkened(.1))
	# Rope lashings low on the pole.
	for y in [length*.2,length*.2+.05]: _band("rope",y,radius*1.18,.03,Color("cbb489"))
	# Rings that hold the cloth, and the finial.
	var top := length-Flora.FLAG_TOP
	for y in [top+.01,top-Flora.CLOTH_SIZES["banner"].y-.02]: _band("iron",y,radius*1.3,.025,iron.lightened(.1))
	_band("iron",length-.02,radius*1.2,.04,iron)
	match kind:
		"short": _ball("brass",Vector3(0,length+.04,0),radius*1.6,Color("d9b04a"))
		"tall":
			_ball("brass",Vector3(0,length+.05,0),radius*1.4,Color("d9b04a"))
			_cone("brass",Vector3(0,length+.09,0),Vector3(0,length+.22,0),radius*.9,Color("e6c25c"))
		"mast":
			_cone("iron",Vector3(0,length+.02,0),Vector3(0,length+.3,0),radius*1.3,iron.lightened(.15))
			# The yard sits below the flown cloth, its stays run up to the top.
			var yard := length-Flora.FLAG_TOP-Flora.CLOTH_SIZES["banner"].y-.3
			for side in [-1.0,1.0]:
				var tip := Vector3(side*.7,yard-.05,0)
				_beam("wood",Vector3(0,yard,0),tip,.024,wood.darkened(.08))
				_ball("brass",tip,.028,Color("d9b04a"))
				_beam("rope",tip,Vector3(0,length-.08,0),.006,Color("cbb489"))

func _band(part: String, y: float, radius: float, height: float, color: Color) -> void:
	var sides := 10
	for index in range(sides):
		var a := TAU*index/sides
		var b := TAU*(index+1)/sides
		var tone := color.lightened(.08*cos(a+.8))
		var p := [Vector3(cos(a)*radius,y,sin(a)*radius),Vector3(cos(b)*radius,y,sin(b)*radius),Vector3(cos(b)*radius,y+height,sin(b)*radius),Vector3(cos(a)*radius,y+height,sin(a)*radius)]
		_quad(part,p,[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],tone,Vector3(0,y+height*.5,0))
		var rim := radius*.7
		_quad(part,[Vector3(cos(a)*rim,y+height,sin(a)*rim),Vector3(cos(b)*rim,y+height,sin(b)*rim),p[2],p[3]],[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],tone.lightened(.1),Vector3(0,y,0))

func _cone(part: String, base: Vector3, tip: Vector3, radius: float, color: Color) -> void:
	var sides := 8
	var axis := (tip-base).normalized()
	var across := axis.cross(Vector3.BACK if absf(axis.z)<.9 else Vector3.RIGHT).normalized()
	var depth := axis.cross(across)
	for index in range(sides):
		var a := TAU*index/sides
		var b := TAU*(index+1)/sides
		var pa := base+(across*cos(a)+depth*sin(a))*radius
		var pb := base+(across*cos(b)+depth*sin(b))*radius
		_quad(part,[pa,pb,tip,tip],[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],color.lightened(.1*cos(a+.8)),base+(tip-base)*.3)

func _ball(part: String, at: Vector3, radius: float, color: Color) -> void:
	var rings := 5
	var sides := 10
	for ring in range(rings):
		var p0 := PI*ring/rings-PI*.5
		var p1 := PI*(ring+1)/rings-PI*.5
		for index in range(sides):
			var a := TAU*index/sides
			var b := TAU*(index+1)/sides
			var q := [Vector3(cos(p0)*cos(a),sin(p0),cos(p0)*sin(a)),Vector3(cos(p0)*cos(b),sin(p0),cos(p0)*sin(b)),Vector3(cos(p1)*cos(b),sin(p1),cos(p1)*sin(b)),Vector3(cos(p1)*cos(a),sin(p1),cos(p1)*sin(a))]
			var points: Array = []
			for p: Vector3 in q: points.append(at+p*radius)
			_quad(part,points,[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],color.lightened(.18*sin(p1)+.06*cos(a+.8)),at,q)

func _beam(part: String, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var axis := (b-a).normalized()
	var across := axis.cross(Vector3.BACK).normalized()
	var depth := axis.cross(across)
	var sides := 6
	for index in range(sides):
		var s := TAU*index/sides
		var t := TAU*(index+1)/sides
		var oa := (across*cos(s)+depth*sin(s))*radius
		var ob := (across*cos(t)+depth*sin(t))*radius
		_quad(part,[a+oa,a+ob,b+ob,b+oa],[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO],color.lightened(.08*cos(s+.8)),(a+b)*.5)
