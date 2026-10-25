class_name HazardVisuals
extends RefCounted

const FloraModels := preload("res://scripts/flora_models.gd")

# Telegraphs of the act hazards (ActHazards decides, this only shows):
#   wind      flags on posts and leaves streaming along the pocket, always
#   storm     ribbons and mirrors turn, dust streaks thicken, far haze
#   gust      snow streaks along the gust line before and during a gust
#   cactus    one large cactus with red-tipped spines
#   scorpion  the tail rises and glows before it strikes
#   icicle    crack, shadow line on the wall, delay, fall on that line
#   bridge    sand pours and the slab shakes, then it falls once
# Nothing here collides or changes a gameplay coordinate.

const STREAK_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled; uniform vec4 tint : source_color = vec4(1.0); uniform float strength = .3; uniform float speed = 1.0; uniform float seed = 0.0; void fragment(){ float dash = smoothstep(.0,.25,fract(UV.x*1.6-TIME*speed+seed))*smoothstep(1.0,.55,fract(UV.x*1.6-TIME*speed+seed)); float edge = smoothstep(0.0,.5,UV.y)*smoothstep(1.0,.5,UV.y); ALBEDO = tint.rgb; ALPHA = dash*edge*strength*tint.a; }"
const HAZE_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled; uniform vec4 tint : source_color = vec4(.85,.68,.45,1.0); uniform float strength = 0.0; uniform vec2 hero = vec2(0.0); uniform float clear_radius = 7.0; varying vec3 world_pos; void vertex(){ world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; } void fragment(){ float d = length(world_pos.xy-hero); float far = smoothstep(clear_radius,clear_radius+5.0,d); ALBEDO = tint.rgb; ALPHA = far*strength*.55; }"
const SHADOW_SHADER := "shader_type spatial; render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled; uniform float strength = 0.0; void fragment(){ float edge = smoothstep(0.0,.5,UV.x)*smoothstep(1.0,.5,UV.x); ALBEDO = vec3(.05,.10,.22); ALPHA = edge*strength*.6; }"
# Clear radius of the storm haze: always beyond the base rope, so a valid grip
# within reach is never veiled.
const HAZE_CLEAR := 7.0
var world: MountainWorld
var layout: MountainLayout
var built: Dictionary = {}
var haze: MeshInstance3D
var haze_material: ShaderMaterial
var haze_strength := 0.0
var last_update_frame := -1

func _init(owner_world: MountainWorld, source: MountainLayout) -> void:
	world = owner_world
	layout = source

static func hazard_y(hazard: Dictionary, ledges: Array) -> float:
	if hazard.has("rect"): return (hazard["rect"] as Rect2).get_center().y
	if hazard.has("pos"): return (hazard["pos"] as Vector2).y
	if hazard.has("top"): return float(hazard["top"])
	if hazard.has("ledge"): return float(ledges[int(hazard["ledge"])]["top"])
	return 0.0

# The top of the stone nearest to `spot` (within a couple of metres): stone
# right under it, open air above, clear of every grip; INF when there is none.
func _stand_point(spot: Vector2) -> Vector2:
	var visuals := world.visuals
	var offsets: Array = []
	for dy in [0.0,-.5,.5,-1.0,1.0,-1.5,1.5,-2.0]:
		for dx in [0.0,.6,-.6,1.2,-1.2,1.8,-1.8,2.4,-2.4]: offsets.append(Vector2(dx,dy))
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared()<b.length_squared())
	for offset: Vector2 in offsets:
		var probe: Vector2 = spot+offset
		if visuals.open_at(probe) or not visuals.open_at(probe+Vector2(0,.35)): continue
		# Walk up to the edge of the stone.
		var top := probe
		while not visuals.open_at(top+Vector2(0,.03)) and top.y<probe.y+.4: top.y += .03
		if visuals.open_at(top+Vector2(-.15,-.12)) or visuals.open_at(top+Vector2(.15,-.12)): continue
		if visuals is MassifVisuals and (visuals as MassifVisuals)._decor_blocked(top,-.9): continue
		return top-Vector2(0,.04)
	return Vector2.INF

func _surface_z(point: Vector2) -> float:
	if world.visuals is MassifVisuals:
		var hit := (world.visuals as MassifVisuals).surface_query(point)
		if hit.valid(): return hit.position.z
	return world.visuals.wall_depth(point)

# Hazards stream with the chunks: built near the view, freed far from it.
# `limit` caps how many are built in this call (streaming builds one per
# frame); returns true while some in range are still waiting.
func build_near(center_y: float, limit: int = -1) -> bool:
	for id in built.keys():
		if absf(hazard_y(layout.hazards[id],layout.ledges)-center_y)<=48: continue
		(built[id]["node"] as Node3D).queue_free()
		built.erase(id)
	var count := 0
	for hazard in layout.hazards:
		var id: int = hazard["id"]
		if built.has(id) or absf(hazard_y(hazard,layout.ledges)-center_y)>40: continue
		if limit>=0 and count>=limit: return true
		count += 1
		var node := Node3D.new()
		node.name = "Опасность_%d_%s" % [id,hazard["def"]]
		world.add_child(node)
		built[id] = {"node":node,"parts":{}}
		_build(hazard,built[id])
	return false

func _material(shader_code: String, key: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = world.shader(key,shader_code)
	return material

func _quad(parent: Node3D, size: Vector2, material: Material, at: Vector3, angle: float = 0.0) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	instance.rotation.z = angle
	parent.add_child(instance)
	return instance

func _vertex() -> StandardMaterial3D:
	return world.visuals._vertex_material("hazard_vertex")

func _build(hazard: Dictionary, entry: Dictionary) -> void:
	var node: Node3D = entry["node"]
	var random := RandomNumberGenerator.new()
	random.seed = int(hazard["id"])*7919+layout.seed_value
	match str(hazard["def"]):
		"wind_pocket": _build_field(hazard,entry,random,Color(.92,.97,.88,.9),"flag")
		"sand_storm": _build_field(hazard,entry,random,Color(.93,.78,.52,.9),"ribbon")
		"storm_cycle": _build_field(hazard,entry,random,Color(.95,.80,.55,.9),"mirror")
		"blizzard_gust": _build_field(hazard,entry,random,Color(.95,.98,1.0,.95),"snow")
		"cactus": _build_cactus(hazard,node,random)
		"scorpion": _build_scorpion(hazard,entry,random)
		"icicle": _build_icicle(hazard,entry,random)
		"sand_bridge": _build_bridge(hazard,entry,random)

# --- Fields -------------------------------------------------------------------------

func _build_field(hazard: Dictionary, entry: Dictionary, random: RandomNumberGenerator, tint: Color, marker: String) -> void:
	var node: Node3D = entry["node"]
	var rect: Rect2 = hazard["rect"]
	var force: Vector2 = hazard["force"]
	var direction := force.normalized() if force.length_squared()>.0001 else Vector2.RIGHT
	var material := _material(STREAK_SHADER,"hazard_streak")
	material.set_shader_parameter("tint",tint)
	material.set_shader_parameter("speed",1.2 if marker!="snow" else 2.2)
	entry["streak"] = material
	# Streaks fill the zone; a main-path storm keeps them thin and sparse.
	var count := 7 if not bool(hazard.get("affects_main",false)) else 12
	var width := minf(rect.size.x,14.0) if bool(hazard.get("affects_main",false)) else rect.size.x
	for index in range(count):
		var at := Vector2(rect.position.x+(rect.size.x-width)*.5+random.randf()*width,rect.position.y+random.randf()*rect.size.y)
		if bool(hazard.get("affects_main",false)): at.x = world.layout.main_point(int(hazard["row"])).x+random.randf_range(-7,7)
		var length := random.randf_range(1.4,2.6)
		var streak := _quad(node,Vector2(length,random.randf_range(.05,.09)),material,Vector3(at.x,at.y,2.75+random.randf()*.15),direction.angle())
		streak.name = "Поток_%d" % index
	# Markers stand at the pocket's edges and point where it blows.
	var markers: Array = []
	var spots: Array = [Vector2(rect.position.x+.4,rect.end.y-.3),Vector2(rect.end.x-.4,rect.end.y-.3),Vector2(rect.get_center().x,rect.position.y+.5)]
	if bool(hazard.get("affects_main",false)):
		var center := world.layout.main_point(int(hazard["row"]))
		spots = [center+Vector2(-6.0,1.0),center+Vector2(6.0,-.5)]
	var shadows := world.visual_quality!="battery"
	for spot in spots:
		# A marker stands on the stone near its spot, never in the air or on a
		# grip; a spot with no top close by gets none.
		var foot := _stand_point(spot)
		if not foot.is_finite(): continue
		var holder := Node3D.new()
		holder.name = "Указатель_%s" % marker
		holder.position = Vector3(foot.x,foot.y,_surface_z(foot+Vector2(0,-.15))+.08)
		node.add_child(holder)
		markers.append(holder)
		if marker!="mirror":
			# A flag on its pole flying downwind; the cloth is the part that
			# flaps (update).
			FloraModels.flag(holder,"flag" if marker=="flag" else "pennant","red" if marker=="flag" else "yellow",Vector3.ZERO,1.4,1.0 if direction.x>=0 else -1.0,shadows,"plain" if marker=="flag" else "stripes")
			continue
		var points := PackedVector3Array()
		var colors := PackedColorArray()
		LandmarkVisuals._prism(points,colors,Vector3(0,-.05,0),Vector3.UP,.05,.04,1.3,5,Color("6b4a30"))
		world.visuals._flat_surface(holder,"Шест",points,colors,_vertex(),false)
		var cloth := Node3D.new()
		cloth.name = "Полотно"
		cloth.position = Vector3(0,1.15,.04)
		holder.add_child(cloth)
		match marker:
			"mirror":
				var disc := MeshInstance3D.new()
				var mesh := CylinderMesh.new()
				mesh.top_radius = .32
				mesh.bottom_radius = .32
				mesh.height = .05
				disc.mesh = mesh
				disc.rotation.x = PI*.5
				var glass := StandardMaterial3D.new()
				glass.albedo_color = Color("e8d7a6")
				glass.metallic = .8
				glass.roughness = .15
				glass.emission_enabled = true
				glass.emission = Color("ffd27a")
				glass.emission_energy_multiplier = 0.0
				disc.material_override = glass
				disc.position = Vector3(direction.x*.15,.2,.05)
				cloth.add_child(disc)
				entry["parts"]["mirror_%d" % markers.size()] = glass
				var ribbon := world.box("Лента",Vector3.ZERO,Vector3(.7,.08,.02),world.mat("hazard_ribbon",Color("d9583a")),cloth)
				ribbon.position = Vector3(direction.x*.45,-.25,.02)
	entry["markers"] = markers
	entry["direction"] = direction

# --- Contact hazards ------------------------------------------------------------------

func _build_cactus(hazard: Dictionary, node: Node3D, random: RandomNumberGenerator) -> void:
	var at: Vector2 = hazard["pos"]
	var holder := Node3D.new()
	holder.name = "Крупный кактус"
	holder.position = Vector3(at.x,at.y-.55,_surface_z(at)+.1)
	holder.scale = Vector3.ONE*1.9
	node.add_child(holder)
	world.visuals._build_cactus(holder,random,world.profile_at(at.y),true)
	# Red spine tips mark the one point to keep away from.
	var spines := world.mat("cactus_spines",Color("e0452f"))
	for index in range(7):
		var angle := TAU*index/7.0
		world.sphere("Колючка",Vector3.ZERO,Vector3.ONE*.07,spines,holder).position = Vector3(cos(angle)*.17,.35+index*.12,.12+sin(angle)*.05)

func _build_scorpion(hazard: Dictionary, entry: Dictionary, random: RandomNumberGenerator) -> void:
	var node: Node3D = entry["node"]
	var at: Vector2 = hazard["pos"]
	var holder := Node3D.new()
	holder.name = "Скорпион"
	holder.position = Vector3(at.x,at.y,_surface_z(at)+.15)
	holder.scale = Vector3.ONE*1.5
	node.add_child(holder)
	var shell := world.mat("scorpion_shell",Color("4a3122"))
	world.sphere("Тело",Vector3.ZERO,Vector3(.62,.26,.3),shell,holder).position = Vector3.ZERO
	for side in [-1,1]:
		world.sphere("Клешня",Vector3.ZERO,Vector3(.2,.12,.12),shell,holder).position = Vector3(side*.36,.06,.08)
	var tail := Node3D.new()
	tail.name = "Хвост"
	tail.position = Vector3(-.28,.05,0)
	holder.add_child(tail)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("6a2e18")
	glow.emission_enabled = true
	glow.emission = Color("ff6a2a")
	glow.emission_energy_multiplier = 0.0
	for index in range(4):
		var segment := world.sphere("Сегмент",Vector3.ZERO,Vector3.ONE*(.13-index*.015),shell if index<3 else glow,tail)
		segment.position = Vector3(-.08*index,.12*index,0)
	entry["parts"]["tail"] = tail
	entry["parts"]["glow"] = glow

func _build_icicle(hazard: Dictionary, entry: Dictionary, _random: RandomNumberGenerator) -> void:
	var node: Node3D = entry["node"]
	var x: float = hazard["x"]
	var top: float = hazard["top"]
	var bottom: float = hazard["bottom"]
	var z := _surface_z(Vector2(x,top))+.25
	var cap := world.sphere("Ледяной нарост",Vector3(x,top+.15,z),Vector3(.9,.35,.5),world.visuals._ice_material(),node)
	cap.name = "Ледяной нарост"
	var spike := MeshInstance3D.new()
	spike.name = "Сосулька"
	var cone := CylinderMesh.new()
	cone.top_radius = .2
	cone.bottom_radius = .0
	cone.height = 1.1
	spike.mesh = cone
	spike.material_override = world.visuals._ice_material()
	spike.position = Vector3(x,top-.45,z)
	node.add_child(spike)
	# The fall line is drawn on the wall during the telegraph.
	var shadow_material := _material(SHADOW_SHADER,"icicle_shadow")
	# In front of the frontmost stone along the whole line, so it reads.
	var front := -INF
	for step in range(6): front = maxf(front,_surface_z(Vector2(x,lerpf(bottom,top,step/5.0))))
	var shadow := _quad(node,Vector2(.5,top-bottom),shadow_material,Vector3(x,(top+bottom)*.5,front+.06))
	shadow.name = "Тень падения"
	var crack := world.box("Трещина",Vector3(x,top+.05,z+.2),Vector3(.5,.04,.02),world.mat("icicle_crack",Color("1d3a5a")),node)
	crack.visible = false
	entry["parts"] = {"spike":spike,"shadow":shadow_material,"crack":crack,"z":z}

func _build_bridge(hazard: Dictionary, entry: Dictionary, random: RandomNumberGenerator) -> void:
	var node: Node3D = entry["node"]
	var ledge: Dictionary = layout.ledges[int(hazard["ledge"])]
	var left := float(ledge["left"])
	var right := float(ledge["right"])
	var top := float(ledge["top"])
	var center := Vector2((left+right)*.5,top)
	var z := _surface_z(center-Vector2(0,.3))
	var slab := Node3D.new()
	slab.name = "Песчаная перемычка"
	slab.position = Vector3(center.x,top,z+.35)
	node.add_child(slab)
	var palette: Dictionary = world.profile_at(top).rock_palette
	var sand := world.mat("bridge_sand",(palette["warm"] as Color).lerp(Color("d4a56a"),.5))
	var dark := world.mat("bridge_sand_dark",(palette["base"] as Color).darkened(.1))
	# A packed-sand span over a few wedged stones, its top a little uneven.
	for index in range(3):
		var part := world.box("Плита",Vector3.ZERO,Vector3((right-left)/3.0+.25,.3+random.randf_range(-.04,.06),1.3+random.randf_range(-.1,.1)),sand,slab)
		part.position = Vector3(lerpf(left-center.x,right-center.x,(index+.5)/3.0),-.15+random.randf_range(-.03,.03),0)
		part.rotation.z = random.randf_range(-.05,.05)
	for index in range(5):
		var piece := world.box("Каменный блок",Vector3.ZERO,Vector3(random.randf_range(.35,.6),.26,.55),dark,slab)
		piece.position = Vector3(lerpf(left-center.x+.3,right-center.x-.3,index/4.0),-.42,.3)
		piece.rotation.z = random.randf_range(-.3,.3)
	var cracks := world.box("Трещины",Vector3.ZERO,Vector3(right-left-.4,.03,.02),world.mat("bridge_crack",Color("4a3122")),slab)
	cracks.position = Vector3(0,.01,.72)
	cracks.visible = false
	entry["parts"] = {"slab":slab,"cracks":cracks,"rest":slab.position}
	if bool(ledge.get("collapsed",false)): slab.visible = false

func collapse(hazard: Dictionary, animate: bool = true) -> void:
	var entry: Dictionary = built.get(int(hazard["id"]),{})
	if entry.is_empty(): return
	var slab: Node3D = entry["parts"].get("slab")
	if slab==null or not slab.visible: return
	slab.visible = false
	if not animate: return
	var dark := world.mat("bridge_sand_dark",Color("a8784a"))
	for index in range(7):
		var chip := world.box("Обломок",Vector3.ZERO,Vector3(.3,.2,.3),dark,entry["node"])
		chip.position = slab.position+Vector3((index-3)*.32,-.2,.1)
		var tween := world.create_tween().set_parallel(true)
		tween.tween_property(chip,"position",chip.position+Vector3((index-3)*.2,-3.2,0),.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(chip,"scale",Vector3.ZERO,.7)
		tween.chain().tween_callback(chip.queue_free)

# --- Animation --------------------------------------------------------------------------

func update(time: float, hero: Vector2, haze_amount: float, camera: Vector2) -> void:
	# Called from every physics step; the scene only needs one pose per drawn
	# frame. The haze keeps easing per step, as before.
	var frame := Engine.get_process_frames()
	if frame==last_update_frame:
		_update_haze(hero,haze_amount,camera)
		return
	last_update_frame = frame
	for id in built.keys():
		var hazard: Dictionary = layout.hazards[id]
		var entry: Dictionary = built[id]
		var now := world.hazards.phase(hazard,time)
		var name: String = now["name"]
		var progress: float = now["progress"]
		match str(hazard["kind"]):
			"field":
				var strength := .32
				if not is_inf(float(hazard["active_time"])):
					strength = .06 if name=="calm" else lerpf(.12,.5,progress) if name=="telegraph" else .75
				(entry["streak"] as ShaderMaterial).set_shader_parameter("strength",strength)
				var flap := (.25 if name=="calm" and not is_inf(float(hazard["active_time"])) else 1.0)
				if not entry.has("cloths"):
					var cloths: Array[Node3D] = []
					for marker in entry.get("markers",[]):
						var found := (marker as Node3D).find_child("Полотно",true,false) as Node3D
						if found!=null: cloths.append(found)
					entry["cloths"] = cloths
				for cloth: Node3D in entry["cloths"]:
					if is_instance_valid(cloth):
						cloth.rotation.y = sin(time*7.0+float(id))*.35*flap
						cloth.scale.x = 1.0+.12*sin(time*11.0+float(id))*flap
				for key in entry["parts"].keys():
					if str(key).begins_with("mirror_"):
						(entry["parts"][key] as StandardMaterial3D).emission_energy_multiplier = 1.4*progress if name=="telegraph" else .5 if name=="active" else 0.0
			"contact":
				if hazard["def"]=="scorpion":
					var tail: Node3D = entry["parts"]["tail"]
					var raise := 0.0 if name=="calm" else progress if name=="telegraph" else 1.0
					tail.rotation.z = -raise*1.1
					(entry["parts"]["glow"] as StandardMaterial3D).emission_energy_multiplier = raise*1.6
			"falling":
				var parts: Dictionary = entry["parts"]
				var spike: MeshInstance3D = parts["spike"]
				var top: float = hazard["top"]
				(parts["shadow"] as ShaderMaterial).set_shader_parameter("strength",progress if name=="telegraph" else 1.0 if name=="active" else 0.0)
				(parts["crack"] as Node3D).visible = name in ["telegraph","active"]
				match name:
					"telegraph":
						spike.visible = true
						spike.scale = Vector3.ONE
						spike.position = Vector3(float(hazard["x"])+sin(time*40.0)*.03*progress,top-.45,parts["z"])
					"active":
						spike.position = Vector3(float(hazard["x"]),world.hazards.icicle_tip(hazard,time)+.55,parts["z"])
					"regrow":
						spike.position = Vector3(float(hazard["x"]),top-.45,parts["z"])
						spike.scale = Vector3.ONE*maxf(.05,progress)
						spike.visible = progress>.05
					_:
						spike.visible = true
						spike.scale = Vector3.ONE
						spike.position = Vector3(float(hazard["x"]),top-.45,parts["z"])
			"collapse":
				var parts: Dictionary = entry["parts"]
				var slab: Node3D = parts["slab"]
				(parts["cracks"] as Node3D).visible = name=="telegraph"
				if name=="telegraph" and slab.visible:
					slab.position = (parts["rest"] as Vector3)+Vector3(sin(time*45.0)*.04*progress,-.03*progress,0)
	_update_haze(hero,haze_amount,camera)

func _update_haze(hero: Vector2, amount: float, camera: Vector2) -> void:
	if amount<=.001 and haze==null: return
	if haze==null:
		haze_material = _material(HAZE_SHADER,"storm_haze")
		haze_material.set_shader_parameter("clear_radius",HAZE_CLEAR)
		haze = MeshInstance3D.new()
		haze.name = "Пыльная мгла"
		var mesh := QuadMesh.new()
		mesh.size = Vector2(70,70)
		haze.mesh = mesh
		haze.material_override = haze_material
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(haze)
	haze.position = Vector3(camera.x,camera.y,3.6)
	haze_material.set_shader_parameter("hero",hero)
	haze_strength = lerpf(haze_strength,amount,.08)
	haze_material.set_shader_parameter("strength",haze_strength)
	haze.visible = haze_strength>.01
