extends SceneTree

# Authors the coin model in assets/models/treasures (see
# scripts/treasure_models.gd; every other treasure is a painted sprite), the
# shared animation library, and the coin's turntable atlas for the bag,
# rendered from the same model: flat-shaded facets, chamfered edges, metal
# with a little glow (the compatibility renderer has no reflections). Needs a
# window for the atlas; afterwards, reimport:
#   Godot --path game --script res://tools/build_treasure_models.gd
#   Godot --headless --path game --import

const Treasures := preload("res://scripts/treasure_models.gd")
# The climb's sun (main.gd SUN_DIRECTION / SUN_ENERGY).
const SUN_DIRECTION := Vector3(.30,-.50,-.81)
const SUN_ENERGY := .46

var parts := {}
var materials := {}
# Width or height on the face, whichever is larger: coins are the small
# change, treasures stand out from them.
const SIZES := {"coin":.46,"material":.5,"default":.56}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Treasures.DIR))
	_materials()
	var library := _animations()
	ResourceSaver.save(library,Treasures.animations_path())
	var models := {}
	# Painted treasures are sprites now (TreasureModels): only the coin is a
	# model.
	for kind: String in ["coin"]:
		var model := _model(kind)
		models[kind] = model
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		document.append_from_scene(model,state)
		var error := document.write_to_filesystem(state,ProjectSettings.globalize_path(Treasures.model_path(kind)))
		print("TREASURE ",kind," ",error_string(error))
	await _portraits(models,library)
	for kind: String in models: models[kind].free()
	quit()

# --- Materials ----------------------------------------------------------------------

func _materials() -> void:
	materials = {
		"gold":_metal(Color("f2b52e"),.22),
		"gold_light":_metal(Color("ffd65e"),.30),
		"gold_dark":_metal(Color("c98a1c"),.14),
		"amber":_glass(Color("f5a32e"),.9,Color("ff9a2a"),.85),
		"amber_core":_glow(Color("ffd27a"),1.1),
		"seed":_matte(Color("5a2a0c"),.6),
		"crystal":_glass(Color("8fd8ee"),.78,Color("6fc6e8"),.35),
		"star":_glass(Color("fff6d6"),1.0,Color("fff1b8"),1.0),
		"star_gold":_glass(Color("f3c94e"),1.0,Color("e9b23a"),.7),
		"ruby":_glass(Color("e2473c"),1.0,Color("e2473c"),.35),
		"sapphire":_glass(Color("3f8ee0"),1.0,Color("3f8ee0"),.35),
		"jade":_glass(Color("2fb5a6"),1.0,Color("2fb5a6"),.35),
		"pearl":_matte(Color("fff1d6"),.35),
		"idol":_matte(Color("8f86a8"),.85),
		"idol_dark":_matte(Color("625a7c"),.9),
		"eyes":_glow(Color("7ff0dd"),1.4),
		"relic":_matte(Color("b3a98f"),.9),
		"relic_dark":_matte(Color("7d735e"),.92),
		"basalt":_matte(Color("4b5560"),.9),
		"cloth":_matte(Color("c9a46a"),.95),
		"rope":_matte(Color("5a3b1e"),.95),
	}

func _metal(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = .35
	material.roughness = .3
	material.metallic_specular = .85
	material.emission_enabled = true
	material.emission = color.darkened(.35)
	material.emission_energy_multiplier = glow
	return material

func _glass(color: Color, alpha: float, glow: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color,alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if alpha<1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.roughness = .12
	material.metallic_specular = .9
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = energy
	return material

func _matte(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := _matte(color,.4)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

# --- Models -------------------------------------------------------------------------

func _model(kind: String) -> Node3D:
	parts = {}
	match kind:
		"coin": _coin()
	var root := Node3D.new()
	root.name = "Treasure_%s" % kind
	var meshes := {}
	var box := AABB()
	for part: String in parts:
		var surface: SurfaceTool = parts[part]
		surface.index()
		meshes[part] = surface.commit()
		box = meshes[part].get_aabb() if box.size==Vector3.ZERO else box.merge(meshes[part].get_aabb())
	# Every kind to its size on the face, measured as the camera sees it.
	var factor: float = float(SIZES.get(kind,SIZES["default"]))/maxf(box.size.x,box.size.y)
	for part: String in meshes:
		var arrays: Array = (meshes[part] as ArrayMesh).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in range(vertices.size()): vertices[index] *= factor
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var scaled := ArrayMesh.new()
		scaled.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		meshes[part] = scaled
	for part: String in meshes:
		var mesh := MeshInstance3D.new()
		mesh.name = part.capitalize().replace(" ","")
		mesh.mesh = meshes[part]
		mesh.mesh.surface_set_material(0,materials[part])
		root.add_child(mesh)
		mesh.owner = root
	return root

func _coin() -> void:
	# A thick minted coin facing the camera: a raised rim, a slightly domed
	# field and the mountain of the expedition struck on both faces.
	var profile := [Vector2(0,.036),Vector2(.17,.032),Vector2(.196,.036),Vector2(.214,.046),Vector2(.236,.036),Vector2(.244,.012),Vector2(.244,-.012),Vector2(.236,-.036),Vector2(.214,-.046),Vector2(.196,-.036),Vector2(.17,-.032),Vector2(0,-.036)]
	_lathe("gold",profile,32,Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3.ZERO))
	var mountain := PackedVector2Array([Vector2(-.13,-.075),Vector2(-.04,.07),Vector2(.0,.015),Vector2(.045,.085),Vector2(.135,-.075)])
	var snow := PackedVector2Array([Vector2(-.04,.07),Vector2(-.012,.027),Vector2(-.026,.034),Vector2(-.05,.022)])
	for side in [1.0,-1.0]:
		var flip := Basis() if side>0 else Basis(Vector3.UP,PI)
		_extrude("gold_light",mountain,.034,.05,.006,Transform3D(flip,Vector3.ZERO))
		_extrude("gold_dark",PackedVector2Array([Vector2(-.16,-.095),Vector2(.16,-.095),Vector2(.16,-.075),Vector2(-.16,-.075)]),.034,.044,.004,Transform3D(flip,Vector3.ZERO))
		_extrude("pearl",snow,.05,.056,.003,Transform3D(flip,Vector3.ZERO))

func _surface(part: String) -> SurfaceTool:
	if not parts.has(part):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[part] = surface
	return parts[part]

# One flat facet; its normal points away from `inside`.
func _polygon(part: String, points: Array, inside: Vector3) -> void:
	var center := Vector3.ZERO
	for p: Vector3 in points: center += p
	center /= points.size()
	var p0: Vector3 = points[0]
	var p1: Vector3 = points[1]
	var p2: Vector3 = points[2]
	var normal := (p1-p0).cross(p2-p0)
	if normal.length_squared()<1e-14: return
	normal = normal.normalized()
	var ordered := points.duplicate()
	if normal.dot(center-inside)<0:
		normal = -normal
		ordered.reverse()
	var surface := _surface(part)
	for index in range(1,ordered.size()-1):
		# Godot winds front faces clockwise.
		for p in [ordered[0],ordered[index+1],ordered[index]]:
			surface.set_normal(normal)
			surface.set_uv(Vector2(p.x,p.y))
			surface.add_vertex(p)

# A turned body from a profile of (radius, height) round the y axis of
# `frame`. `side` says which way the profile's outside lies: +1 when the
# solid is on the right of its direction of travel, -1 on the left.
func _lathe(part: String, profile: Array, segments: int, frame: Transform3D, side: float = 1.0) -> void:
	var rings: Array = []
	for point: Vector2 in profile:
		var ring: Array[Vector3] = []
		for index in range(segments):
			var angle := TAU*(index+.5)/segments
			ring.append(frame*Vector3(cos(angle)*point.x,point.y,sin(angle)*point.x))
		rings.append(ring)
	for k in range(profile.size()-1):
		var travel: Vector2 = profile[k+1]-profile[k]
		var outward := Vector2(-travel.y,travel.x).normalized()*side
		var a: Array = rings[k]
		var b: Array = rings[k+1]
		for index in range(segments):
			var next := (index+1)%segments
			var flat: Array = []
			for p in [a[index],a[next],b[next],b[index]]:
				if flat.is_empty() or not (p as Vector3).is_equal_approx(flat[-1]): flat.append(p)
			if flat.size()>=3 and (flat[0] as Vector3).is_equal_approx(flat[-1]): flat.pop_back()
			if flat.size()<3: continue
			var center := Vector3.ZERO
			for p in flat: center += p
			center /= flat.size()
			var angle := TAU*(index+1.0)/segments
			var out3 := frame.basis*Vector3(cos(angle)*outward.x,outward.y,sin(angle)*outward.x)
			_polygon(part,flat,center-out3.normalized()*.01)

# A flat 2D outline extruded between z0 and z1 with chamfered front and
# back edges.
func _extrude(part: String, outline: PackedVector2Array, z0: float, z1: float, bevel: float, frame: Transform3D) -> void:
	var center := Vector2.ZERO
	for p in outline: center += p
	center /= outline.size()
	var inset := PackedVector2Array()
	for p in outline:
		var away := p-center
		inset.append(center+away*maxf(0,1.0-bevel/maxf(away.length(),.001)))
	var inside := frame*Vector3(center.x,center.y,(z0+z1)*.5)
	var rings := [[inset,z0],[outline,z0+bevel],[outline,z1-bevel],[inset,z1]]
	for k in range(3):
		var a: PackedVector2Array = rings[k][0]
		var b: PackedVector2Array = rings[k+1][0]
		var za: float = rings[k][1]
		var zb: float = rings[k+1][1]
		for index in range(outline.size()):
			var next := (index+1)%outline.size()
			_polygon(part,[frame*Vector3(a[index].x,a[index].y,za),frame*Vector3(a[next].x,a[next].y,za),frame*Vector3(b[next].x,b[next].y,zb),frame*Vector3(b[index].x,b[index].y,zb)],inside)
	var triangles := Geometry2D.triangulate_polygon(inset)
	for z in [z0,z1]:
		for index in range(0,triangles.size(),3):
			var points := []
			for k in range(3):
				var p := inset[triangles[index+k]]
				points.append(frame*Vector3(p.x,p.y,z))
			_polygon(part,points,inside)

# A chamfered box in `frame`.
func _box(part: String, frame: Transform3D, half: Vector3, bevel: float) -> void:
	bevel = minf(bevel,minf(half.x,minf(half.y,half.z))*.45)
	var inner := half-Vector3.ONE*bevel
	var center := frame*Vector3.ZERO
	for axis in range(3):
		var a := (axis+1)%3
		var c := (axis+2)%3
		for s in [-1.0,1.0]:
			var face := []
			for corner in [[-1,-1],[1,-1],[1,1],[-1,1]]:
				var p := Vector3.ZERO
				p[axis] = s*half[axis]
				p[a] = corner[0]*inner[a]
				p[c] = corner[1]*inner[c]
				face.append(frame*p)
			_polygon(part,face,center)
		for sa in [-1.0,1.0]:
			for sc in [-1.0,1.0]:
				var strip := []
				for step in range(4):
					var p := Vector3.ZERO
					p[axis] = (-1.0 if step in [0,3] else 1.0)*inner[axis]
					p[a] = sa*(half[a] if step<2 else inner[a])
					p[c] = sc*(inner[c] if step<2 else half[c])
					strip.append(frame*p)
				_polygon(part,strip,center)
	for sx in [-1.0,1.0]:
		for sy in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				_polygon(part,[frame*Vector3(sx*half.x,sy*inner.y,sz*inner.z),frame*Vector3(sx*inner.x,sy*half.y,sz*inner.z),frame*Vector3(sx*inner.x,sy*inner.y,sz*half.z)],center)

# A small faceted stone: an octahedron-like gem with a girdle.
func _gem(part: String, at: Vector3, radius: float, sides: int) -> void:
	var girdle: Array[Vector3] = []
	for index in range(sides):
		var angle := TAU*index/sides
		girdle.append(at+Vector3(cos(angle)*radius,sin(angle)*radius,0))
	var crown_ring: Array[Vector3] = []
	for p in girdle: crown_ring.append(at+(p-at)*.55+Vector3(0,0,radius*.55))
	var table := at+Vector3(0,0,radius*.8)
	var back := at-Vector3(0,0,radius*.9)
	for index in range(sides):
		var next := (index+1)%sides
		_polygon(part,[girdle[index],girdle[next],crown_ring[next],crown_ring[index]],at)
		_polygon(part,[crown_ring[index],crown_ring[next],table],at)
		_polygon(part,[girdle[index],girdle[next],back],at)

# A crystal: a hexagonal prism from `base` along `axis` with a pointed tip.
func _prism(part: String, base: Vector3, axis: Vector3, radius: float, length: float, tip: float, sides: int) -> void:
	var across := axis.cross(Vector3.BACK).normalized()
	var depth := axis.cross(across).normalized()
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	for index in range(sides):
		var angle := TAU*index/sides+.3
		var offset := (across*cos(angle)+depth*sin(angle))*radius
		low.append(base+offset)
		high.append(base+axis*length+offset)
	var center := base+axis*length*.5
	var apex := base+axis*(length+tip)
	for index in range(sides):
		var next := (index+1)%sides
		_polygon(part,[low[index],low[next],high[next],high[index]],center)
		_polygon(part,[high[index],high[next],apex],center)
	_polygon(part,low,center)

func _torus(part: String, at: Vector3, radius: float, tube: float, segments: int, sides: int, basis: Basis) -> void:
	for index in range(segments):
		var a := TAU*index/segments
		var b := TAU*(index+1)/segments
		for k in range(sides):
			var s := TAU*k/sides
			var t := TAU*(k+1)/sides
			var quad := []
			for pair in [[a,s],[b,s],[b,t],[a,t]]:
				var around := Vector3(cos(pair[0]),0,sin(pair[0]))
				quad.append(at+basis*(around*(radius+cos(pair[1])*tube)+Vector3(0,sin(pair[1])*tube,0)))
			var ring_center := at+basis*(Vector3(cos((a+b)*.5),0,sin((a+b)*.5))*radius)
			_polygon(part,quad,ring_center)

# --- Animations ---------------------------------------------------------------------

func _animations() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var cycle := Treasures.CYCLE
	# Sines sampled densely on linear tracks: cubic value tracks overshoot
	# wildly when an instance seeks to its own phase before its first frame.
	var steps := 16
	for name in ["idle_spin"]:
		var animation := Animation.new()
		animation.length = cycle
		animation.loop_mode = Animation.LOOP_LINEAR
		var bob := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(bob,"%s:position" % Treasures.PIVOT)
		var turn := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(turn,"%s:rotation" % Treasures.SPIN)
		# The price tag swings on its cord a little behind the bob.
		var tag := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(tag,"%s:rotation" % Treasures.TAG)
		for step in range(steps+1):
			var time := cycle*step/steps
			var wave := sin(TAU*step/steps)
			animation.track_insert_key(bob,time,Vector3(0,.035*wave,0))
			animation.track_insert_key(tag,time,Vector3(0,0,.05*cos(TAU*step/steps)))
			if name=="idle_sway": animation.track_insert_key(turn,time,Vector3(0,.38*wave,-.04*wave))
		if name=="idle_spin":
			animation.track_insert_key(turn,0.0,Vector3.ZERO)
			animation.track_insert_key(turn,cycle,Vector3(0,TAU,0))
		library.add_animation(name,animation)
	# A painted treasure bobs and rocks a little, never turning edge-on.
	var float_animation := Animation.new()
	float_animation.length = cycle
	float_animation.loop_mode = Animation.LOOP_LINEAR
	var lift := float_animation.add_track(Animation.TYPE_VALUE)
	float_animation.track_set_path(lift,"%s:position" % Treasures.PIVOT)
	var rock := float_animation.add_track(Animation.TYPE_VALUE)
	float_animation.track_set_path(rock,"%s:rotation" % Treasures.SPIN)
	var swing := float_animation.add_track(Animation.TYPE_VALUE)
	float_animation.track_set_path(swing,"%s:rotation" % Treasures.TAG)
	for step in range(steps+1):
		var time := cycle*step/steps
		var wave := sin(TAU*step/steps)
		float_animation.track_insert_key(lift,time,Vector3(0,.04*wave,0))
		float_animation.track_insert_key(rock,time,Vector3(0,0,.07*cos(TAU*step/steps)))
		float_animation.track_insert_key(swing,time,Vector3(0,0,.05*cos(TAU*step/steps+.6)))
	library.add_animation("idle_float",float_animation)
	var collect := Animation.new()
	collect.length = .42
	var rise := collect.add_track(Animation.TYPE_VALUE)
	collect.track_set_path(rise,"%s:position" % Treasures.PIVOT)
	collect.track_insert_key(rise,0.0,Vector3.ZERO)
	collect.track_insert_key(rise,.42,Vector3(0,.38,.2),.5)
	var size := collect.add_track(Animation.TYPE_VALUE)
	collect.track_set_path(size,"%s:scale" % Treasures.PIVOT)
	collect.track_insert_key(size,0.0,Vector3.ONE)
	collect.track_insert_key(size,.12,Vector3.ONE*1.28)
	collect.track_insert_key(size,.42,Vector3.ONE*.01,2.0)
	var spin := collect.add_track(Animation.TYPE_VALUE)
	collect.track_set_path(spin,"%s:rotation" % Treasures.SPIN)
	collect.track_insert_key(spin,0.0,Vector3.ZERO)
	collect.track_insert_key(spin,.42,Vector3(0,TAU,0))
	var hide := collect.add_track(Animation.TYPE_VALUE)
	collect.track_set_path(hide,"%s:visible" % Treasures.TAG)
	collect.value_track_set_update_mode(hide,Animation.UPDATE_DISCRETE)
	collect.track_insert_key(hide,0.0,false)
	library.add_animation("collect",collect)
	return library

# --- Portraits ----------------------------------------------------------------------

# Turntable atlases of the idle cycle: the same model, animation and light
# the climb uses, seen a little from above, on a clear background.
func _portraits(models: Dictionary, library: AnimationLibrary) -> void:
	var cell := Treasures.PORTRAIT_CELL
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cell,cell)*2
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b6c7d6")
	environment.environment.ambient_light_energy = .7
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(SUN_DIRECTION,Vector3.UP)
	sun.light_color = Color("fff0d2")
	sun.light_energy = SUN_ENERGY
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 26
	viewport.add_child(camera)
	camera.position = Vector3(0,.42,1.55)
	camera.look_at(Vector3(0,-.01,0))
	camera.current = true
	var keys: Array = [["coin","coin",null]]
	for entry: Array in keys:
		var holder := Node3D.new()
		var pivot := Node3D.new()
		pivot.name = Treasures.PIVOT
		holder.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var tag := Node3D.new()
		tag.name = "Tag"
		pivot.add_child(tag)
		var model: Node3D = (models[entry[1]] as Node3D).duplicate()
		spin.add_child(model)
		var player := AnimationPlayer.new()
		player.add_animation_library("",library)
		holder.add_child(player)
		viewport.add_child(holder)
		player.play(Treasures.idle_animation(entry[1]))
		var atlas := Image.create(cell*Treasures.PORTRAIT_FRAMES,cell,false,Image.FORMAT_RGBA8)
		for frame in range(Treasures.PORTRAIT_FRAMES):
			player.seek(Treasures.CYCLE*frame/Treasures.PORTRAIT_FRAMES,true)
			# Keep the bob out of the icon: the slot has its own motion.
			pivot.position = Vector3.ZERO
			for wait in range(2): await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			image.resize(cell,cell,Image.INTERPOLATE_LANCZOS)
			image.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(image,Rect2i(0,0,cell,cell),Vector2i(frame*cell,0))
		atlas.save_png(ProjectSettings.globalize_path(Treasures.portrait_path(entry[0])))
		print("PORTRAIT ",entry[0])
		holder.queue_free()
		await process_frame
