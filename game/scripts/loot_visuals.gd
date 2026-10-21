class_name LootVisuals
extends RefCounted

# World models for finds. Every model is built from the item dictionary the
# loot system already stores ({"id","tier","kind","value"}) plus the find's
# "rare" flag, so pickup, the bag and run results stay untouched.

const TIER_COLORS := [Color("e7b347"),Color("e8913f"),Color("e9bf4f"),Color("8fd8ee"),Color("a98fdc"),Color("f3d478")]

static func kind_of(item: Dictionary) -> String:
	var kind := str(item.get("kind",""))
	if kind.is_empty():
		kind = ["coin","amber","relic","crystal","idol","star"][clampi(int(item.get("tier",0)),0,5)]
	return kind

static func build(world: MountainWorld, find: Dictionary, holder: Node3D, quality: String, wall_local_z: float) -> void:
	var item: Dictionary = find["item"]
	var tier := clampi(int(item.get("tier",0)),0,5)
	var rare := bool(find.get("rare",false))
	var kind := kind_of(item)
	var shadows := quality!="battery"
	# Every find rests on stone: a narrow shelf for coins and gems, a pedestal
	# for crown and chalice, a ledge for idols and relics, with a tuft beside.
	_pedestal(world,holder,wall_local_z,int(item.get("id",0)),shadows,kind,quality)
	match kind:
		"coin": _coin(world,holder,shadows)
		"amber": _gem(world,holder,Color("e8913f"),Color("ffd28a"),shadows)
		"crown": _crown(world,holder,shadows)
		"chalice": _chalice(world,holder,shadows)
		"idol": _idol(world,holder,shadows)
		"star", "crystal": _crystal(world,holder,Color("8fd8ee") if kind=="crystal" else Color("cfe9ff"),shadows)
		_: _relic(world,holder,shadows)
	if quality!="battery":
		_sparkle(world,holder,Vector3(.20,.20,.34),.30 if not rare else .42,float(int(item.get("id",0))%7)*.37)
	if rare:
		_halo(world,holder,TIER_COLORS[tier].lightened(.3),.95 if quality!="battery" else .7)

static func _metal(world: MountainWorld, key: String, color: Color, glow: float = .18) -> StandardMaterial3D:
	var material := world.mat("loot_v2_"+key,color,false)
	# Metals stay mostly diffuse: the compatibility renderer has no reflection
	# probes, so a fully metallic surface would read almost black.
	material.metallic = .35
	material.roughness = .32
	material.metallic_specular = .85
	material.emission_enabled = glow>0
	material.emission = color.darkened(.35)
	material.emission_energy_multiplier = glow
	return material

static func _mesh(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, shadows: bool, name: String = "") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if not name.is_empty(): instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _prism(points: PackedVector2Array, z_back: float, z_front: float, bevel: float = 0.0) -> ArrayMesh:
	# Flat-shaded extrusion with an optional chamfer on the front face.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2.ZERO
	for point in points: center += point
	center /= points.size()
	var inner := PackedVector2Array()
	for point in points: inner.append(center+(point-center)*(1.0-bevel))
	var face_z := z_front+(bevel*.35 if bevel>0 else 0.0)
	var indices := Geometry2D.triangulate_polygon(inner)
	for i in range(0,indices.size(),3):
		for k in [0,2,1]:
			var p := inner[indices[i+k]]
			surface.add_vertex(Vector3(p.x,p.y,face_z))
	for i in range(points.size()):
		var j := (i+1)%points.size()
		var a := points[i]
		var b := points[j]
		if bevel>0:
			for v in [Vector3(a.x,a.y,z_front),Vector3(inner[j].x,inner[j].y,face_z),Vector3(b.x,b.y,z_front),Vector3(a.x,a.y,z_front),Vector3(inner[i].x,inner[i].y,face_z),Vector3(inner[j].x,inner[j].y,face_z)]:
				surface.add_vertex(v)
		for v in [Vector3(a.x,a.y,z_back),Vector3(b.x,b.y,z_front),Vector3(b.x,b.y,z_back),Vector3(a.x,a.y,z_back),Vector3(a.x,a.y,z_front),Vector3(b.x,b.y,z_front)]:
			surface.add_vertex(v)
	surface.generate_normals()
	return surface.commit()

static func _coin(world: MountainWorld, holder: Node3D, shadows: bool) -> void:
	# A large coin facing the camera: thick rim, raised field with a stamped
	# mountain, and a soft highlight on the upper-left edge.
	var gold := _metal(world,"coin_gold",Color("e9b53f"),.22)
	var rim := _metal(world,"coin_rim",Color("c98a2b"),.12)
	var face := _metal(world,"coin_face",Color("f6cf62"),.26)
	var shine := _metal(world,"coin_shine",Color("fff0b8"),.55)
	var coin := Node3D.new()
	coin.name = "Золотая монетка"
	coin.rotation = Vector3(.04,.16,.05)
	holder.add_child(coin)
	var body := CylinderMesh.new()
	body.top_radius = .36
	body.bottom_radius = .36
	body.height = .09
	body.radial_segments = 20
	var disc := _mesh(coin,body,rim,Vector3.ZERO,shadows,"Ребро")
	disc.rotation.x = PI*.5
	var top := CylinderMesh.new()
	top.top_radius = .285
	top.bottom_radius = .335
	top.height = .04
	top.radial_segments = 20
	var bevel := _mesh(coin,top,gold,Vector3(0,0,.06),false,"Фаска")
	bevel.rotation.x = PI*.5
	# Stamped mountain emblem with a lit left slope and a darker right one.
	var peak := PackedVector2Array([Vector2(-.20,-.11),Vector2(-.06,.13),Vector2(.0,.06),Vector2(.07,.16),Vector2(.20,-.11)])
	_mesh(coin,_prism(peak,.07,.105,.0),face,Vector3.ZERO,false,"Чеканка")
	var ridge := PackedVector2Array([Vector2(-.06,.13),Vector2(.0,.06),Vector2(.07,.16),Vector2(.07,-.11),Vector2(-.06,-.11)])
	_mesh(coin,_prism(ridge,.10,.112,.0),rim,Vector3(.025,0,0),false)
	var crescent := PackedVector2Array()
	for step in range(7):
		var angle := lerpf(1.75,3.05,step/6.0)
		crescent.append(Vector2(cos(angle),sin(angle))*.33)
	for step in range(7):
		var angle := lerpf(3.05,1.75,step/6.0)
		crescent.append(Vector2(cos(angle),sin(angle))*.29)
	_mesh(coin,_prism(crescent,.09,.11,.0),shine,Vector3.ZERO,false,"Блик монеты")

static func _gem(world: MountainWorld, holder: Node3D, color: Color, light: Color, shadows: bool) -> void:
	var material := _metal(world,"gem_%s" % color.to_html(),color,.30)
	material.metallic = .05
	material.roughness = .18
	var outline := PackedVector2Array([Vector2(0,.27),Vector2(.2,.12),Vector2(.16,-.18),Vector2(0,-.27),Vector2(-.17,-.16),Vector2(-.2,.1)])
	var gem := _mesh(holder,_prism(outline,-.08,.08,.38),material,Vector3.ZERO,shadows,"Янтарь")
	gem.scale = Vector3.ONE*1.25
	var shine := _metal(world,"gem_shine_%s" % light.to_html(),light,.45)
	_mesh(holder,_prism(PackedVector2Array([Vector2(-.12,.08),Vector2(-.02,.2),Vector2(-.04,.04)]),.10,.115),shine,Vector3.ZERO,false)

static func _crown(world: MountainWorld, holder: Node3D, shadows: bool) -> void:
	var gold := _metal(world,"crown_gold",Color("efbb3e"),.24)
	var dark := _metal(world,"crown_band",Color("c7862a"),.14)
	var ruby := _metal(world,"crown_ruby",Color("d8443c"),.35)
	var crown := Node3D.new()
	crown.name = "Корона"
	crown.rotation = Vector3(.06,.18,0)
	holder.add_child(crown)
	var shape := PackedVector2Array([Vector2(-.32,-.16),Vector2(.32,-.16),Vector2(.36,.16),Vector2(.20,.02),Vector2(.11,.24),Vector2(0,.06),Vector2(-.11,.24),Vector2(-.20,.02),Vector2(-.36,.16)])
	_mesh(crown,_prism(shape,-.10,.10,.0),gold,Vector3.ZERO,shadows,"Зубцы")
	_mesh(crown,_prism(PackedVector2Array([Vector2(-.33,-.18),Vector2(.33,-.18),Vector2(.33,-.07),Vector2(-.33,-.07)]),-.11,.13,.0),dark,Vector3.ZERO,false,"Обод")
	for x in [-.36,-.11,.11,.36]:
		var ball := SphereMesh.new()
		ball.radius = .035
		ball.height = .07
		ball.radial_segments = 6
		ball.rings = 3
		_mesh(crown,ball,gold,Vector3(x,.17 if absf(x)>.2 else .25,.02),false)
	var gem := SphereMesh.new()
	gem.radius = .045
	gem.height = .09
	gem.radial_segments = 6
	gem.rings = 3
	_mesh(crown,gem,ruby,Vector3(0,-.12,.14),false,"Камень")

static func _chalice(world: MountainWorld, holder: Node3D, shadows: bool) -> void:
	# Polished silver with gold trim, a touch larger so it reads at a glance.
	var silver := _metal(world,"chalice_silver_v2",Color("a7adb2"),.10)
	silver.metallic = .55
	silver.roughness = .25
	var gold := _metal(world,"chalice_gold",Color("e2ad45"),.20)
	var cup := Node3D.new()
	cup.name = "Кубок"
	cup.scale = Vector3.ONE*1.25
	holder.add_child(cup)
	var bowl := CylinderMesh.new()
	bowl.top_radius = .23
	bowl.bottom_radius = .08
	bowl.height = .28
	bowl.radial_segments = 10
	_mesh(cup,bowl,silver,Vector3(0,.10,0),shadows,"Чаша")
	var band := CylinderMesh.new()
	band.top_radius = .235
	band.bottom_radius = .225
	band.height = .045
	band.radial_segments = 10
	_mesh(cup,band,gold,Vector3(0,.235,0),false)
	var stem := CylinderMesh.new()
	stem.top_radius = .035
	stem.bottom_radius = .05
	stem.height = .17
	stem.radial_segments = 6
	_mesh(cup,stem,gold,Vector3(0,-.12,0),shadows)
	var foot := CylinderMesh.new()
	foot.top_radius = .09
	foot.bottom_radius = .15
	foot.height = .05
	foot.radial_segments = 10
	_mesh(cup,foot,silver,Vector3(0,-.22,0),shadows,"Основание")
	for side in [-1,1]:
		var handle := TorusMesh.new()
		handle.inner_radius = .045
		handle.outer_radius = .075
		handle.rings = 8
		handle.ring_segments = 5
		var instance := _mesh(cup,handle,silver,Vector3(side*.25,.11,0),false,"Ручка")
		instance.rotation = Vector3(PI*.5,0,0)

static func _idol(world: MountainWorld, holder: Node3D, shadows: bool) -> void:
	var stone := _metal(world,"idol_stone",Color("8d8f80"),.0)
	stone.metallic = 0
	stone.roughness = .9
	var moss := _metal(world,"idol_eyes",Color("6fe0c8"),.9)
	var body := PackedVector2Array([Vector2(-.17,-.28),Vector2(.17,-.28),Vector2(.2,.06),Vector2(.14,.27),Vector2(-.14,.27),Vector2(-.2,.06)])
	_mesh(holder,_prism(body,-.12,.10,.28),stone,Vector3.ZERO,shadows,"Каменный идол")
	for x in [-.07,.07]:
		_mesh(holder,_prism(PackedVector2Array([Vector2(x-.035,.07),Vector2(x+.035,.07),Vector2(x+.03,.12),Vector2(x-.03,.12)]),.10,.145),moss,Vector3.ZERO,false,"Глаз")
	_mesh(holder,_prism(PackedVector2Array([Vector2(-.08,-.08),Vector2(.08,-.08),Vector2(.06,-.04),Vector2(-.06,-.04)]),.10,.14),_metal(world,"idol_mouth",Color("4c4f45"),.0),Vector3.ZERO,false)

static func _crystal(world: MountainWorld, holder: Node3D, color: Color, shadows: bool) -> void:
	var material := _metal(world,"crystal_%s" % color.to_html(),color,.55)
	material.metallic = .05
	material.roughness = .12
	material.rim_enabled = true
	material.rim = .7
	for index in range(3):
		var spike := CylinderMesh.new()
		spike.top_radius = 0
		spike.bottom_radius = .085 if index==0 else .06
		spike.height = .52 if index==0 else .34
		spike.radial_segments = 6
		var shard := _mesh(holder,spike,material,Vector3((index-1)*.11,-.02 if index==0 else -.08,0),shadows and index==0,"Редкий кристалл")
		shard.rotation.z = (1-index)*.42

static func _relic(world: MountainWorld, holder: Node3D, shadows: bool) -> void:
	var bronze := _metal(world,"relic_bronze",Color("b0844a"),.12)
	var gold := _metal(world,"relic_gold",Color("efc35a"),.25)
	var tablet := PackedVector2Array([Vector2(-.2,-.24),Vector2(.2,-.24),Vector2(.22,.14),Vector2(0,.28),Vector2(-.22,.14)])
	var node := _mesh(holder,_prism(tablet,-.08,.08,.22),bronze,Vector3.ZERO,shadows,"Древняя реликвия")
	node.rotation.z = .12
	_mesh(holder,_prism(PackedVector2Array([Vector2(-.06,-.06),Vector2(.06,-.06),Vector2(.0,.12)]),.09,.12),gold,Vector3(0,0,0),false)

const PEDESTALS := {"coin":[.34,.12,-.47],"amber":[.30,.11,-.40],"crown":[.44,.17,-.40],"chalice":[.44,.17,-.40],"idol":[.40,.14,-.42],"relic":[.40,.14,-.40]}

static func _pedestal(world: MountainWorld, holder: Node3D, wall_local_z: float, id: int, shadows: bool, kind: String, quality: String) -> void:
	if world.visuals==null: return
	var visuals: MountainVisuals = world.visuals
	var size: Array = PEDESTALS.get(kind,[.32,.11,-.42])
	var random := RandomNumberGenerator.new()
	random.seed = id*271+5
	var outline := PackedVector2Array()
	for corner in range(7):
		var angle := TAU*corner/7.0+random.randf_range(-.2,.2)
		outline.append(Vector2(cos(angle)*float(size[0]),sin(angle)*float(size[1])))
	var pedestal := Node3D.new()
	pedestal.name = "Каменный постамент" if kind in ["crown","chalice"] else "Каменная полка"
	pedestal.position = Vector3(0,float(size[2]),0)
	holder.add_child(pedestal)
	var stone := visuals.zone_color(float(holder.position.y)).lightened(.06)
	var mesh := visuals._outcrop(pedestal,outline,minf(-.1,wall_local_z),.0,.22,float(size[1])*.75,float(size[1])*.6,.7,stone,visuals.stone_material)
	visuals._skirt(pedestal,outline,-.01,minf(-.1,wall_local_z-.06),visuals.zone_color(float(holder.position.y)),.08,.16)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if quality!="battery":
		var tuft := Node3D.new()
		tuft.position = Vector3(float(size[0])*(.85 if id%2==0 else -.85),float(size[1])*.4,.05)
		tuft.scale = Vector3.ONE*.55
		pedestal.add_child(tuft)
		visuals._build_grass(tuft,random,false,.6)

static func _sparkle(world: MountainWorld, holder: Node3D, at: Vector3, size: float, phase: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size,size)
	var material := ShaderMaterial.new()
	material.shader = world.shader("loot_sparkle","shader_type spatial; render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled; uniform float phase = 0.0; void fragment(){ vec2 p=abs(UV*2.0-1.0); float star=max(0.0,1.0-p.x*7.0-p.y*.9)+max(0.0,1.0-p.y*7.0-p.x*.9); float core=smoothstep(.35,0.0,length(p)); float pulse=.55+.45*sin(TIME*2.6+phase*6.28); ALBEDO=vec3(1.0,.93,.70); ALPHA=clamp(star*.9+core*.6,0.0,1.0)*pulse; }")
	material.set_shader_parameter("phase",phase)
	var sparkle := MeshInstance3D.new()
	sparkle.name = "Блеск"
	sparkle.mesh = quad
	sparkle.material_override = material
	sparkle.position = at
	sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(sparkle)

static func _halo(world: MountainWorld, holder: Node3D, color: Color, size: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(size,size)
	var material := ShaderMaterial.new()
	material.shader = world.shader("loot_halo","shader_type spatial; render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled; uniform vec4 tint : source_color = vec4(1.0,.9,.6,1.0); void fragment(){ float d=length(UV*2.0-1.0); float ring=smoothstep(1.0,.55,d)*smoothstep(.15,.6,d); float pulse=.8+.2*sin(TIME*1.7); ALBEDO=tint.rgb; ALPHA=ring*.42*pulse; }")
	material.set_shader_parameter("tint",color)
	var halo := MeshInstance3D.new()
	halo.name = "Ореол редкости"
	halo.mesh = quad
	halo.material_override = material
	halo.position = Vector3(0,0,-.16)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(halo)
