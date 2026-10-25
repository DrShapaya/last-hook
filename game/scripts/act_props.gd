class_name ActProps
extends RefCounted

const FloraModels := preload("res://scripts/flora_models.gd")

# Small decor of an act (LevelCatalog.ACTS[...]["props"]) grown on the lit
# tops of the masses next to plants and scree. Purely visual, away from the
# route like every decor piece (MassifVisuals._build_decor). Every prop is a
# painted sprite or a flag model (FloraModels); the few that are effects
# (fireflies, a jet of sand) stay effects.

static func build(visuals: MassifVisuals, prop: String, holder: Node3D, random: RandomNumberGenerator, profile: GripBiomeProfile, detail: bool) -> void:
	var side := 1.0 if random.randf()<.5 else -1.0
	match prop:
		"grass", "dry_bush", "leaves":
			visuals._build_plant(holder,random,1.0,profile,detail)
		"stones", "block", "crate", "mechanism", "tracks":
			visuals._build_pebbles(holder,random,profile,detail)
		"cactus":
			visuals._build_cactus(holder,random,profile,detail)
		"snow_pocket", "cornice":
			visuals._build_snow_cap(holder,random,1.15 if prop=="cornice" else 1.0)
		"icicles_safe":
			# The first icicles are only a picture: they hang and never fall.
			holder.position.y -= .1
			FloraModels.plant(holder,FloraModels.pick("icicle",random),detail,.8)
		"ice_vein", "lens":
			visuals._crystal_sprite(holder,random,profile,detail,.85)
		"chain", "frozen_rope":
			FloraModels.plant(holder,FloraModels.pick("vine_frost",random,"hang"),detail,.75)
		"bones", "scorpion_far":
			FloraModels.plant(holder,FloraModels.pick("skull",random),detail,.85)
		"pine_snow":
			FloraModels.plant(holder,FloraModels.pick("tree_snow",random),detail,.32)
		"flag", "ribbon":
			FloraModels.flag(holder,"flag" if prop=="flag" else "pennant","red" if prop=="flag" else "yellow",Vector3(0,-.05,.1),.95,side,detail)
		"mast", "sail", "signal_light":
			var colour: String = {"mast":FloraModels.COLORS[random.randi_range(0,FloraModels.COLORS.size()-1)],"sail":"white","signal_light":"orange"}[prop]
			FloraModels.flag(holder,FloraModels.MASTS[random.randi_range(0,1)],colour,Vector3(0,-.05,.1),1.5,side,detail)
		"insects":
			var glow: StandardMaterial3D = visuals.world.mat("prop_firefly",Color("f6e27a"),true)
			for index in range(3):
				visuals.world.sphere("Светлячок",Vector3.ZERO,Vector3.ONE*.06,glow,holder).position = Vector3(random.randf_range(-.4,.4),random.randf_range(.3,.8),.25)
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
		_:
			visuals._build_pebbles(holder,random,profile,detail)
