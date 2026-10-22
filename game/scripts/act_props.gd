class_name ActProps
extends RefCounted

# Small decor of an act (LevelCatalog.ACTS[...]["props"]) grown on the lit
# tops of the masses next to plants and scree. Purely visual, away from the
# route like every decor piece (MassifVisuals._build_decor).

static func build(visuals: MassifVisuals, prop: String, holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, detail: bool) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var material := visuals._vertex_material("act_prop")
	match prop:
		"grass", "dry_bush":
			visuals._build_plant(holder,random,1.0,profile,detail)
			return
		"stones":
			visuals._build_pebbles(holder,random,visuals.zone_color(holder.position.y).darkened(.04),false)
			return
		"cactus":
			holder.scale = Vector3.ONE*random.randf_range(.8,1.1)
			visuals._build_cactus(holder,random,profile,false)
			return
		"snow_pocket", "cornice":
			visuals._build_snow_cap(holder,random,1.3 if prop=="cornice" else 1.0)
			return
		"icicles_safe":
			# The first icicles are only a picture: they hang and never fall.
			holder.position.y -= .1
			visuals._icicles(holder,.06,random.randf_range(.8,1.3),random.randi())
			return
		"ice_vein":
			visuals._build_crystal(holder,random,false,3,profile)
			return
		"bird":
			var body := Color("3b3f46")
			LandmarkVisuals._prism(points,colors,Vector3(0,.12,.1),Vector3(1,.15,0).normalized(),.07,.03,.26,5,body)
			LandmarkVisuals._prism(points,colors,Vector3(.24,.16,.1),Vector3(1,.1,0).normalized(),.04,0.0,.08,4,Color("e3a03a"))
			points.append_array(PackedVector3Array([Vector3(.05,.2,.12),Vector3(.18,.2,.12),Vector3(-.06,.42,.14)]))
			colors.append(body.lightened(.1))
			LandmarkVisuals._prism(points,colors,Vector3(.06,0,.1),Vector3.UP,.01,.01,.12,3,Color("6b4a30"))
		"insects":
			var glow: StandardMaterial3D = visuals.world.mat("prop_firefly",Color("f6e27a"),true)
			for index in range(3):
				visuals.world.sphere("Светлячок",Vector3.ZERO,Vector3.ONE*.06,glow,holder).position = Vector3(random.randf_range(-.4,.4),random.randf_range(.3,.8),.25)
			return
		"flag", "ribbon":
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3.UP,.03,.025,.9,4,Color("6b4a30"))
			var cloth := Color("e8624d") if prop=="flag" else Color("e3b95e")
			points.append_array(PackedVector3Array([Vector3(0,.85,.12),Vector3(.45,.75,.12),Vector3(0,.6 if prop=="flag" else .78,.12)]))
			colors.append(cloth)
		"leaves":
			for index in range(4):
				var at := Vector3(random.randf_range(-.4,.4),random.randf_range(.05,.5),.15)
				points.append_array(PackedVector3Array([at,at+Vector3(.12,.04,.01),at+Vector3(.05,.12,.0)]))
				colors.append(Color("c8a23a").lerp(Color("8fae3a"),random.randf()))
		"block", "crate":
			var color := Color("b3ab97") if prop=="block" else Color("8a6a44")
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3.UP,.32,.3,.42,4,color,true,PI*.25+random.randf_range(-.2,.2))
			if prop=="crate": LandmarkVisuals._prism(points,colors,Vector3(-.3,.15,.33),Vector3.RIGHT,.03,.03,.6,4,color.darkened(.2))
		"mechanism":
			var metal := Color("7a6a58")
			for index in range(8):
				var angle := TAU*index/8.0
				LandmarkVisuals._prism(points,colors,Vector3(0,.35,.15),Vector3(cos(angle),sin(angle),0),.03,.03,.32,3,metal)
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3.UP,.06,.06,.4,4,metal.darkened(.1))
		"bones":
			var bone := Color("e8dcc0")
			LandmarkVisuals._prism(points,colors,Vector3(-.3,.03,.12),Vector3(1,.1,0).normalized(),.04,.03,.6,4,bone)
			LandmarkVisuals._prism(points,colors,Vector3(.2,.03,.16),Vector3(.4,1,0).normalized(),.03,.02,.3,4,bone.darkened(.06))
		"sand_jet":
			var stream := ShaderMaterial.new()
			stream.shader = visuals.world.shader("hazard_streak",HazardVisuals.STREAK_SHADER)
			stream.set_shader_parameter("tint",Color(.92,.78,.52,.8))
			stream.set_shader_parameter("strength",.35)
			stream.set_shader_parameter("speed",1.6)
			var quad := QuadMesh.new()
			quad.size = Vector2(1.4,.12)
			var jet := MeshInstance3D.new()
			jet.name = "Песчаная струя"
			jet.mesh = quad
			jet.material_override = stream
			jet.rotation.z = -PI*.5
			jet.position = Vector3(0,-.6,.2)
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(jet)
			return
		"scorpion_far":
			var shell := Color("5a3a26")
			LandmarkVisuals._prism(points,colors,Vector3(-.12,.04,.1),Vector3.RIGHT,.06,.05,.24,5,shell)
			LandmarkVisuals._arc(points,colors,Vector3(-.12,.06,.1),Vector3(-.02,.2,.1),.12,.025,4,shell.darkened(.1))
		"sail":
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3(.15,1,0).normalized(),.03,.02,1.0,4,Color("6e5236"))
			points.append_array(PackedVector3Array([Vector3(.08,.95,.12),Vector3(.6,.4,.13),Vector3(.05,.35,.12)]))
			colors.append(Color("d8c08f"))
		"lens":
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3.UP,.04,.03,.5,4,Color("8a7a5c"))
			var brass := LandmarkVisuals._metal(visuals,"prop_lens",Color("d0a84a"),.1)
			LandmarkVisuals._disc(holder,.22,Vector3(0,.6,.16),brass,"Линза",true)
		"mast":
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3.UP,.04,.03,1.5,4,Color("8a7a5c"))
			LandmarkVisuals._flags(points,colors,Vector3(0,1.4,.12),Vector3(.7,1.0,.12),2,.02)
		"pine_snow":
			holder.scale = Vector3.ONE*.38
			LandmarkVisuals._snow_pine(visuals,holder,random,false)
			return
		"tracks":
			for index in range(4):
				var at := Vector3(-.45+index*.3,.02,.2+(index%2)*.06)
				LandmarkVisuals._prism(points,colors,at,Vector3(1,.0,0),.05,.05,.12,4,Color("7f93a6"),true)
		"chain", "frozen_rope":
			var metal := Color("6c7a84") if prop=="chain" else Color("b08a5a")
			for index in range(5):
				LandmarkVisuals._prism(points,colors,Vector3(0,-.05-index*.17,.2),Vector3.DOWN,.035,.035,.14,4,metal)
				if prop=="frozen_rope" and index%2==1: LandmarkVisuals._prism(points,colors,Vector3(-.05,-.1-index*.17,.22),Vector3.DOWN,.05,0.0,.12,4,Color("cfeaf6"))
		"signal_light":
			LandmarkVisuals._prism(points,colors,Vector3(0,-.05,.1),Vector3.UP,.03,.03,.7,4,Color("5a646c"))
			var lamp: StandardMaterial3D = visuals.world.mat("signal_lamp",Color("ffb347"),false)
			lamp.emission_enabled = true
			lamp.emission = Color("ff9a3a")
			lamp.emission_energy_multiplier = 1.2
			visuals.world.sphere("Фонарь",Vector3.ZERO,Vector3.ONE*.14,lamp,holder).position = Vector3(0,.78,.15)
		_:
			visuals._build_pebbles(holder,random,visuals.zone_color(holder.position.y).darkened(.04),false)
			return
	if not points.is_empty(): visuals._flat_surface(holder,"Предмет акта_%s" % prop,points,colors,material,false)
