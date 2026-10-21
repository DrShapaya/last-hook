class_name LandmarkVisuals
extends RefCounted

# Large themed set pieces on the side islands of the massif, one family per
# zone (forest, cliffs, ruins, ice, volcano, sky). Purely visual: they are
# placed away from the route and every gameplay object by MassifVisuals.

const HEIGHTS := [4.2,4.0,3.2,3.0,3.4,3.6]

static func height_for(zone: int) -> float:
	return HEIGHTS[clampi(zone,0,5)]

static func build(visuals: MassifVisuals, zone: int, holder: Node3D, random: RandomNumberGenerator, shadows: bool) -> void:
	match clampi(zone,0,5):
		0: _pine(visuals,holder,random,shadows)
		1: _spire(visuals,holder,random,shadows)
		2: _column(visuals,holder,random,shadows)
		3: _ice(visuals,holder,random,shadows)
		4: _basalt(visuals,holder,random,shadows)
		_: _stele(visuals,holder,random,shadows)

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
