class_name LandmarkVisuals
extends RefCounted

# Large themed set pieces on the side islands of the massif, one family per
# zone (forest, cliffs, ruins, ice, volcano, sky). Purely visual: they are
# placed away from the route and every gameplay object by MassifVisuals.

const HEIGHTS := [4.2,4.0,3.2,3.0,3.4,3.6]
const ZONE_FAMILIES := ["pine","spire","column","ice_needles","basalt","stele"]
# Acts of v14 bring their own families (LevelCatalog.ACTS[...]["landmarks"]).
const FAMILY_HEIGHTS := {"pine":4.2,"spire":4.0,"column":3.2,"ice_needles":3.0,"basalt":3.4,"stele":3.6,
	"root_bridge":2.6,"root_arch":3.4,"flag_line":2.6,"hanging_frame":3.0,"post_gate":3.4,"signal_flags":3.0,
	"bones":1.8,"cactus_grove":2.6,"wagon":2.4,"sail":3.4,"mirror_mast":3.6,"lens_ring":3.0,
	"snow_pines":4.0,"ice_columns":3.6,"chains":2.8,"tower_ring":3.8,"signal_light":3.0}

static func height_for(zone: int) -> float:
	return HEIGHTS[clampi(zone,0,5)]

static func family_height(family: String) -> float:
	return float(FAMILY_HEIGHTS.get(family,3.4))

static func build(visuals: MassifVisuals, zone: int, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	build_family(visuals,ZONE_FAMILIES[clampi(zone,0,5)],holder,random,shadows)

static func build_family(visuals: MassifVisuals, family: String, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	match family:
		"pine": _pine(visuals,holder,random,shadows)
		"spire": _spire(visuals,holder,random,shadows)
		"column": _column(visuals,holder,random,shadows)
		"ice_needles": _ice(visuals,holder,random,shadows)
		"basalt": _basalt(visuals,holder,random,shadows)
		"stele": _stele(visuals,holder,random,shadows)
		"root_bridge": _roots(visuals,holder,random,shadows,1.0)
		"root_arch": _roots(visuals,holder,random,shadows,1.45)
		"flag_line": _flag_line(visuals,holder,random,shadows)
		"hanging_frame": _hanging_frame(visuals,holder,random,shadows)
		"post_gate": _post_gate(visuals,holder,random,shadows)
		"signal_flags": _signal_flags(visuals,holder,random,shadows)
		"bones": _bones(visuals,holder,random,shadows)
		"cactus_grove": _cactus_grove(visuals,holder,random,shadows)
		"wagon": _wagon(visuals,holder,random,shadows)
		"sail": _sail(visuals,holder,random,shadows)
		"mirror_mast": _mirror_mast(visuals,holder,random,shadows)
		"lens_ring": _lens_ring(visuals,holder,random,shadows)
		"snow_pines": _snow_pine(visuals,holder,random,shadows)
		"ice_columns": _ice_columns(visuals,holder,random,shadows)
		"chains": _chains(visuals,holder,random,shadows)
		"tower_ring": _tower_ring(visuals,holder,random,shadows)
		"signal_light": _signal_light(visuals,holder,random,shadows)
		_: _stele(visuals,holder,random,shadows)

# --- Act families (v14) ---------------------------------------------------------------

static func _arc(points: PackedVector3Array, colors: PackedColorArray, from: Vector3, to: Vector3, lift: float, radius: float, segments: int, color: Color) -> void:
	# A bent beam of short prisms: roots, ribs and arches.
	var previous := from
	for index in range(1,segments+1):
		var t := float(index)/segments
		var at := from.lerp(to,t)+Vector3(0,sin(t*PI)*lift,0)
		var axis := at-previous
		if axis.length()>.01:
			_prism(points,colors,previous,axis.normalized(),radius*(1.0-t*.25),radius*(1.0-t*.3),axis.length(),5,color,false)
		previous = at

static func _roots(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool, size: float) -> void:
	# Living roots bent into a bridge (or a large arch at the post), moss on top.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var wood := Color("6b4a30")
	var span := 2.2*size
	for strand in range(3):
		var offset := (strand-1)*.18
		_arc(points,colors,Vector3(-span*.5,-.1,.1+offset),Vector3(span*.5,-.1,.1-offset),1.5*size+random.randf_range(-.15,.15),.16-strand*.02,9,wood.darkened(strand*.06))
	_commit(visuals,holder,"Корневая арка",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	for index in range(3):
		var tuft := Node3D.new()
		tuft.position = Vector3(lerpf(-span*.3,span*.3,index/2.0),1.4*size-.1,.2)
		tuft.scale = Vector3.ONE*.6
		holder.add_child(tuft)
		visuals._build_grass(tuft,random,false)

static func _flags(points: PackedVector3Array, colors: PackedColorArray, start: Vector3, finish: Vector3, count: int, sag: float) -> void:
	var palette := [Color("e3b95e"),Color("e8624d"),Color("70c995"),Color("78d8e5"),Color("a994df")]
	for index in range(count):
		var t := (index+.5)/count
		var at := start.lerp(finish,t)+Vector3(0,-sag*sin(t*PI),0)
		points.append_array(PackedVector3Array([at+Vector3(-.12,0,0),at+Vector3(.12,0,0),at+Vector3(0,-.32,.02)]))
		colors.append(palette[index%palette.size()])

static func _flag_line(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# Wind line: two posts and a sagging line of prayer flags.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var span := random.randf_range(2.2,2.8)
	for side in [-1,1]:
		_prism(points,colors,Vector3(side*span*.5,-.1,.1),Vector3(side*.08,1,0).normalized(),.07,.05,2.2,5,Color("6b4a30"))
	_flags(points,colors,Vector3(-span*.5,2.0,.15),Vector3(span*.5,2.0,.15),7,.45)
	_commit(visuals,holder,"Линия флагов",points,colors,visuals._vertex_material("landmark_vertex"),shadows)

static func _hanging_frame(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# A suspended timber frame with guy lines: an old wind gauge.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var wood := Color("7a5636")
	_prism(points,colors,Vector3(-.8,-.1,.1),Vector3(.3,1,0).normalized(),.08,.06,2.8,5,wood)
	_prism(points,colors,Vector3(.8,-.1,.1),Vector3(-.3,1,0).normalized(),.08,.06,2.8,5,wood)
	_prism(points,colors,Vector3(-.7,2.45,.12),Vector3.RIGHT,.06,.06,1.4,4,wood.darkened(.08))
	_prism(points,colors,Vector3(-.35,2.4,.14),Vector3.DOWN,.02,.02,.9,3,Color("d8d0b8"))
	_prism(points,colors,Vector3(.35,2.4,.14),Vector3.DOWN,.02,.02,.9,3,Color("d8d0b8"))
	_prism(points,colors,Vector3(-.45,1.5,.14),Vector3.RIGHT,.09,.09,.9,4,wood.lightened(.08))
	_flags(points,colors,Vector3(.7,2.5,.16),Vector3(1.8+random.randf()*.3,1.2,.16),3,.1)
	_commit(visuals,holder,"Подвесная рама",points,colors,visuals._vertex_material("landmark_vertex"),shadows)

static func _post_gate(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# Masonry gate of the old post: two block pillars and a timber lintel.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var stone := Color("b3ab97")
	for side in [-1,1]:
		for block in range(4):
			_prism(points,colors,Vector3(side*.9,-.15+block*.62,.1),Vector3.UP,.38,.36,.58,4,stone.darkened(random.randf_range(0,.12)),true,PI*.25)
	_prism(points,colors,Vector3(-1.45,2.55,.2),Vector3.RIGHT,.2,.2,2.9,4,Color("6e5236"),true,PI*.25)
	_prism(points,colors,Vector3(-.5,1.0,.05),Vector3.UP,.05,.05,1.4,4,Color("5c5348"))
	_prism(points,colors,Vector3(.5,1.0,.05),Vector3.UP,.05,.05,1.4,4,Color("5c5348"))
	_commit(visuals,holder,"Ворота поста",points,colors,visuals.stone_material,shadows)

static func _signal_flags(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	_prism(points,colors,Vector3(0,-.1,.1),Vector3.UP,.08,.06,2.9,5,Color("6b4a30"))
	var palette := [Color("e8624d"),Color("e3b95e"),Color("dfe6e8")]
	for index in range(3):
		var y := 2.6-index*.55
		var side := 1.0 if random.randf()<.5 else -1.0
		points.append_array(PackedVector3Array([Vector3(0,y,.14),Vector3(side*.75,y-.12,.16),Vector3(0,y-.4,.14)]))
		colors.append(palette[index])
	_prism(points,colors,Vector3(.5,-.15,.1),Vector3.UP,.32,.3,.5,4,Color("8f8a7c"),true,PI*.25)
	_commit(visuals,holder,"Сигнальные флаги",points,colors,visuals._vertex_material("landmark_vertex"),shadows)

static func _bones(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# Bleached ribs of a large animal half in the sand.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var bone := Color("e8dcc0")
	_prism(points,colors,Vector3(-1.3,.1,.2),Vector3.RIGHT,.09,.07,2.6,5,bone.darkened(.06))
	for index in range(5):
		var x := -1.0+index*.5
		_arc(points,colors,Vector3(x,.1,.2),Vector3(x+.15,.05,.55),1.1-absf(index-2)*.2,.05,5,bone)
	_prism(points,colors,Vector3(1.4,.05,.25),Vector3(1,.3,0).normalized(),.24,.12,.5,6,bone.lightened(.04))
	_commit(visuals,holder,"Кости",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	var mound := Node3D.new()
	mound.position = Vector3(random.randf_range(-.4,.4),-.05,.2)
	holder.add_child(mound)
	visuals._build_pebbles(mound,random,Color("cfa877"),false)

static func _cactus_grove(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var profile := visuals.profile_at(holder.position.y)
	for index in range(3):
		var cactus := Node3D.new()
		cactus.position = Vector3((index-1)*.8+random.randf_range(-.15,.15),-.05,.15+index*.05)
		cactus.scale = Vector3.ONE*random.randf_range(1.3,2.0)*(1.25 if index==1 else 1.0)
		holder.add_child(cactus)
		visuals._build_cactus(cactus,random,profile,shadows)

static func _wagon(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# A caravan wagon half buried in the rock: a plank body, one wheel up.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var wood := Color("7a5636")
	var tilt := Vector3(1,random.randf_range(-.12,.12),0).normalized()
	for plank in range(3):
		_prism(points,colors,Vector3(-1.2,.15+plank*.28,.15),tilt,.14,.14,2.4,4,wood.darkened(plank*.05),true,PI*.25)
	for index in range(10):
		var a0 := TAU*index/10.0
		var a1 := TAU*(index+1)/10.0
		var center := Vector3(.9,.35,.5)
		_prism(points,colors,center+Vector3(cos(a0),sin(a0),0)*.5,(Vector3(cos(a1),sin(a1),0)-Vector3(cos(a0),sin(a0),0)).normalized(),.05,.05,.32,4,wood.darkened(.12))
		if index%2==0: _prism(points,colors,center,Vector3(cos(a0),sin(a0),0),.03,.03,.5,3,wood.darkened(.2))
	_prism(points,colors,Vector3(-.9,.9,.12),Vector3.UP,.05,.04,1.5,4,wood)
	points.append_array(PackedVector3Array([Vector3(-.88,2.3,.16),Vector3(.2,1.2,.18),Vector3(-.88,1.05,.16)]))
	colors.append(Color("d8c08f"))
	_commit(visuals,holder,"Повозка каравана",points,colors,visuals._vertex_material("landmark_vertex"),shadows)

static func _sail(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var lean := Vector3(random.randf_range(-.15,.15),1,0).normalized()
	_prism(points,colors,Vector3(0,-.1,.1),lean,.07,.05,3.3,5,Color("6e5236"))
	var top := lean*3.1+Vector3(0,0,.12)
	points.append_array(PackedVector3Array([top,top+Vector3(1.4,-1.6,.05),lean*1.0+Vector3(0,0,.12)]))
	colors.append(Color("e2cfa0"))
	points.append_array(PackedVector3Array([top+Vector3(0,-.2,.02),top+Vector3(-.9,-1.2,.04),lean*1.4+Vector3(0,0,.13)]))
	colors.append(Color("c8784a"))
	_commit(visuals,holder,"Парус",points,colors,visuals._vertex_material("landmark_vertex"),shadows)

static func _metal(visuals: MassifVisuals, key: String, color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = visuals.world.mat(key,color,false)
	material.metallic = .75
	material.roughness = .25
	if glow>0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

static func _disc(holder: Node3D, radius: float, at: Vector3, material: Material, name: String, ring: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	if ring:
		var torus := TorusMesh.new()
		torus.inner_radius = radius*.82
		torus.outer_radius = radius
		instance.mesh = torus
	else:
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = .06
		instance.mesh = mesh
	instance.rotation.x = PI*.5
	instance.position = at
	instance.material_override = material
	holder.add_child(instance)
	return instance

static func _mirror_mast(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# A solar mirror on a mast with ribbons: it turns towards the storm.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	_prism(points,colors,Vector3(0,-.1,.1),Vector3.UP,.08,.06,3.2,6,Color("8a7a5c"))
	_prism(points,colors,Vector3(-.5,-.15,.1),Vector3.UP,.35,.3,.4,6,Color("b5a27e"))
	_flags(points,colors,Vector3(0,2.6,.18),Vector3(1.3,2.0,.18),3,.05)
	_commit(visuals,holder,"Мачта зеркала",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	var mirror := _disc(holder,.55,Vector3(0,3.2,.3),_metal(visuals,"observatory_mirror",Color("f0d898"),.4),"Солнечное зеркало")
	mirror.rotation.y = random.randf_range(-.5,.5)

static func _lens_ring(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	_prism(points,colors,Vector3(0,-.1,.1),Vector3.UP,.18,.12,1.4,6,Color("9a8a68"))
	_commit(visuals,holder,"Опора линзы",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	_disc(holder,.95,Vector3(0,2.2,.25),_metal(visuals,"observatory_ring",Color("b8913f")),"Кольцо обсерватории",true)
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(.85,.93,1.0,.45)
	lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens.metallic = .2
	lens.roughness = .05
	_disc(holder,.75,Vector3(0,2.2,.26),lens,"Линза").rotation.y = random.randf_range(-.3,.3)

static func _snow_pine(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var height := random.randf_range(3.2,4.2)
	_prism(points,colors,Vector3(0,-.1,.1),Vector3.UP,.15,.1,height*.3,6,Color("5a4030"))
	for tier in range(3):
		var y := height*(.22+tier*.22)
		var radius := (1.05-tier*.27)*random.randf_range(.9,1.1)
		_prism(points,colors,Vector3(0,y,.1),Vector3.UP,radius,0.0,height*(.4-tier*.06),7,Color("2f5040").lerp(Color("e8f2f6"),.35+tier*.12),false,random.randf()*TAU)
	_commit(visuals,holder,"Заснеженная ель",points,colors,visuals._vertex_material("landmark_vertex"),shadows)

static func _ice_material(visuals: MassifVisuals) -> StandardMaterial3D:
	var material := visuals._vertex_material("landmark_ice",.12)
	material.roughness = .15
	material.rim_enabled = true
	material.rim = .4
	return material

static func _ice_columns(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# Blue columns of the crevasse with a dark vein of old ice.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(3):
		var x := (index-1)*.7
		var height := random.randf_range(2.4,3.6)*(1.0 if index!=1 else 1.15)
		_prism(points,colors,Vector3(x,-.15,.1+index*.03),Vector3(random.randf_range(-.05,.05),1,0).normalized(),.3,.22,height,6,Color("5fa6d8").lerp(Color("bfe6fa"),random.randf()*.5),true,random.randf()*TAU)
	_prism(points,colors,Vector3(-.9,1.2,.35),Vector3(1,.15,0).normalized(),.04,.04,1.8,3,Color("1d4a78"))
	_commit(visuals,holder,"Ледяные колонны",points,colors,_ice_material(visuals),shadows)

static func _chains(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var span := random.randf_range(1.8,2.4)
	for side in [-1,1]:
		_prism(points,colors,Vector3(side*span*.5,-.1,.1),Vector3.UP,.09,.07,2.4,5,Color("5a646c"))
	_commit(visuals,holder,"Опоры цепи",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	var metal := _metal(visuals,"crevasse_chain",Color("6c7a84"))
	for index in range(9):
		var t := (index+.5)/9.0
		var link := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = .06
		torus.outer_radius = .11
		link.mesh = torus
		link.material_override = metal
		link.position = Vector3(lerpf(-span*.5,span*.5,t),2.2-sin(t*PI)*.7,.18)
		link.rotation = Vector3(PI*.5 if index%2==0 else 0.0,0,0)
		holder.add_child(link)

static func _tower_ring(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# Remains of the high station: a broken tower with iced rings.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var height := random.randf_range(2.8,3.6)
	_prism(points,colors,Vector3(0,-.15,0),Vector3.UP,.62,.5,height,8,Color("9aa3ab"),false)
	_prism(points,colors,Vector3(0,height-.15,0),Vector3(.3,1,0).normalized(),.5,.2,.5,8,Color("dfeef4"),true)
	_commit(visuals,holder,"Башня станции",points,colors,visuals.stone_material,shadows)
	var metal := _metal(visuals,"crown_ring",Color("8fa2b0"))
	for index in range(2):
		var ring := _disc(holder,.85-index*.1,Vector3(0,1.0+index*1.2,.05),metal,"Кольцо башни",true)
		ring.rotation = Vector3(0,0,0)

static func _signal_light(visuals: MassifVisuals, holder: Node3D, _random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	_prism(points,colors,Vector3(0,-.1,.1),Vector3.UP,.07,.05,2.6,5,Color("5a646c"))
	_prism(points,colors,Vector3(-.2,2.5,.1),Vector3.RIGHT,.05,.05,.4,4,Color("5a646c"))
	_commit(visuals,holder,"Сигнальный огонь",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	var lamp: StandardMaterial3D = visuals.world.mat("signal_lamp",Color("ffb347"),false)
	lamp.emission_enabled = true
	lamp.emission = Color("ff9a3a")
	lamp.emission_energy_multiplier = 1.2
	visuals.world.sphere("Фонарь",Vector3.ZERO,Vector3.ONE*.3,lamp,holder).position = Vector3(0,2.75,.2)

static func _shade(color: Color, facing: float) -> Color:
	# Faceted art light: faces turned to the upper-left sun are lighter.
	return color.lightened(.16*facing) if facing>0 else color.darkened(-.24*facing)

static func _prism(points: PackedVector3Array, colors: PackedColorArray, base: Vector3, axis: Vector3, bottom: float, top: float, height: float, sides: int, color: Color, cap: bool = true, turn: float = 0.0) -> void:
	# A tapered faceted prism along axis; top radius 0 makes a cone.
	var side := Vector3(axis.y,-axis.x,0).normalized()
	var depth := Vector3(0,0,1)
	var tip := base+axis*height
	for i in range(sides):
		var a0 := turn+TAU*i/sides
		var a1 := turn+TAU*(i+1)/sides
		var d0 := side*cos(a0)+depth*sin(a0)
		var d1 := side*cos(a1)+depth*sin(a1)
		var facing := -(cos(a0)+cos(a1))*.5*.8+(sin(a0)+sin(a1))*.5*.3
		var face := _shade(color,facing)
		var b0 := base+d0*bottom
		var b1 := base+d1*bottom
		if top<=.001:
			points.append_array(PackedVector3Array([b0,tip,b1]))
			colors.append(face)
			continue
		var t0 := tip+d0*top
		var t1 := tip+d1*top
		points.append_array(PackedVector3Array([b0,t0,t1]))
		colors.append(face)
		points.append_array(PackedVector3Array([b0,t1,b1]))
		colors.append(face.darkened(.03))
		if cap:
			points.append_array(PackedVector3Array([t0,tip,t1]))
			colors.append(color.lightened(.12))

static func _commit(visuals: MassifVisuals, holder: Node3D, name: String, points: PackedVector3Array, colors: PackedColorArray, material: Material, shadows: bool) -> MeshInstance3D:
	return visuals._flat_surface(holder,name,points,colors,material,shadows)

static func _pine(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var height := random.randf_range(3.6,4.6)
	var lean := Vector3(random.randf_range(-.08,.08),1,0).normalized()
	_prism(points,colors,Vector3(0,-.1,.1),lean,.16,.11,height*.35,6,Color("6b4a30"))
	var greens := [Color("2f5e2c"),Color("3d7432"),Color("4f8a3a")]
	for tier in range(3):
		var y := height*(.22+tier*.22)
		var radius := (1.15-tier*.28)*random.randf_range(.9,1.1)
		_prism(points,colors,lean*y+Vector3(0,0,.1),lean,radius,0.0,height*(.42-tier*.06),7,greens[tier],false,random.randf()*TAU)
	_commit(visuals,holder,"Ель",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	var bush := Node3D.new()
	bush.position = Vector3(random.randf_range(.4,.7)*(-1 if random.randf()<.5 else 1),-.05,.25)
	bush.scale = Vector3.ONE*1.3
	holder.add_child(bush)
	visuals._build_grass(bush,random,false)

static func _spire(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var stone := visuals.zone_color(30.0).darkened(.04)
	var height := random.randf_range(3.2,4.4)
	var lean := Vector3(random.randf_range(-.12,.12),1,0).normalized()
	_prism(points,colors,Vector3(0,-.2,0),lean,.85,.22,height,7,stone,true,random.randf()*TAU)
	_prism(points,colors,Vector3(.7,-.2,.1),Vector3(.25,1,0).normalized(),.45,.1,height*.45,5,stone.darkened(.06),true,random.randf()*TAU)
	_commit(visuals,holder,"Каменный шпиль",points,colors,visuals.stone_material,shadows)
	var crystals := Node3D.new()
	crystals.position = Vector3(-.7,-.1,.3)
	holder.add_child(crystals)
	visuals._build_crystal(crystals,random,shadows,4)

static func _column(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# A broken temple column with its capital and a fallen drum beside it.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var stone := Color("b3ab97")
	var height := random.randf_range(2.4,3.2)
	_prism(points,colors,Vector3(0,-.15,0),Vector3.UP,.62,.62,.28,8,stone.darkened(.05))
	_prism(points,colors,Vector3(0,.13,0),Vector3.UP,.42,.38,height,8,stone)
	if random.randf()<.6:
		_prism(points,colors,Vector3(0,height+.13,0),Vector3.UP,.58,.58,.26,4,stone.lightened(.04),true,PI*.25)
	var drum := Vector3(random.randf_range(.9,1.2)*(-1 if random.randf()<.5 else 1),.0,.2)
	_prism(points,colors,drum,Vector3(1,.12,0).normalized(),.36,.36,.7,8,stone.darkened(.08))
	_commit(visuals,holder,"Колонна руин",points,colors,visuals.stone_material,shadows)

static func _ice(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var count := random.randi_range(3,5)
	for index in range(count):
		var t := (float(index)/maxf(1,count-1)-.5)
		var axis := Vector3(sin(t*1.0),cos(t*1.0),0).normalized()
		var height := random.randf_range(1.8,3.0)*(1.0-absf(t)*.6)
		_prism(points,colors,Vector3(t*1.2,-.1,.1+index*.02),axis,.32*(1.0-absf(t)*.3),0.0,height,6,Color("8cc4e2").lerp(Color("d6f1ff"),random.randf()*.5),false,random.randf()*TAU)
	var material := visuals._vertex_material("landmark_ice",.12)
	material.roughness = .15
	material.rim_enabled = true
	material.rim = .4
	_commit(visuals,holder,"Ледяные шипы",points,colors,material,shadows)

static func _basalt(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# Basalt columns with glowing ember tops: the volcano band's landmark.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var glow_points := PackedVector3Array()
	var glow_colors := PackedColorArray()
	var count := random.randi_range(4,6)
	for index in range(count):
		var x := (float(index)/maxf(1,count-1)-.5)*1.9
		var height := random.randf_range(1.2,3.2)*(1.0-absf(x)*.25)
		var base := Vector3(x,-.15,.05+index*.02)
		_prism(points,colors,base,Vector3.UP,.30,.30,height,6,Color("4b4646"),false)
		_prism(glow_points,glow_colors,base+Vector3(0,height,0),Vector3.UP,.30,.0,.05,6,Color("ff8a3d"),false)
	_commit(visuals,holder,"Базальтовые столбы",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
	var glow: StandardMaterial3D = visuals.world.mat("landmark_ember",Color.WHITE,false)
	glow.vertex_color_use_as_albedo = true
	glow.vertex_color_is_srgb = true
	glow.emission_enabled = true
	glow.emission = Color("ff6a2a")
	glow.emission_energy_multiplier = .8
	_commit(visuals,holder,"Тлеющие вершины",glow_points,glow_colors,glow,false)

static func _stele(visuals: MassifVisuals, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	# A carved stele with a line of prayer flags towards a short post.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var stone := Color("c2bfb4")
	var height := random.randf_range(2.6,3.4)
	_prism(points,colors,Vector3(0,-.15,0),Vector3.UP,.55,.42,height,4,stone,true,PI*.25)
	_prism(points,colors,Vector3(0,height-.15,0),Vector3.UP,.42,0.0,.5,4,Color("d9b55a"),false,PI*.25)
	var post := Vector3(random.randf_range(1.6,2.1)*(-1 if random.randf()<.5 else 1),-.1,.15)
	_prism(points,colors,post,Vector3.UP,.07,.06,1.6,5,Color("6b4a30"))
	var flags := [Color("e3b95e"),Color("e8624d"),Color("70c995"),Color("78d8e5"),Color("a994df")]
	var start := Vector3(0,height*.85,.2)
	var finish := post+Vector3(0,1.55,.05)
	for index in range(5):
		var t := (index+.5)/5.0
		var at := start.lerp(finish,t)+Vector3(0,-.25*sin(t*PI),0)
		points.append_array(PackedVector3Array([at+Vector3(-.12,0,0),at+Vector3(.12,0,0),at+Vector3(0,-.32,.02)]))
		colors.append(flags[index%flags.size()])
	_commit(visuals,holder,"Стела с флажками",points,colors,visuals._vertex_material("landmark_vertex"),shadows)
