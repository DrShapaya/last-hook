extends RefCounted

# Vegetation and flags of the face.
#   vegetation  painted low-poly sprites (assets/sprites/vegetation, cut from
#               references/vegetation by tools/slice_vegetation.py): grass,
#               bushes, desert plants and cacti, snow plants standing on the
#               lit tops, vines, roots, frosted vines and icicles hanging
#               under the overhangs. Each is a quad facing the camera, sized
#               for the face, swaying on the vegetation shader (tufts from
#               their root, vines from where they hang) and casting a cut-out
#               shadow.
#   flags       authored models (assets/models/flags, tools/build_flag_models
#               .gd): poles in three heights and cloths in seven shapes, the
#               cloth painted from the woven masks (assets/sprites/flags,
#               tools/paint_flag_cloth.py) in any colour, rippling on the
#               cloth shader.

const SPRITES := "res://assets/sprites"
const FLAG_DIR := "res://assets/models/flags"
const CLOTH_DIR := "res://assets/sprites/flags"

# The sprite catalogue, measured against the hero (about 1 m tall) and the
# grips (1.6-2 m wide). Per kind: folder, how it grows - "stand" on a top,
# "climb" up a wall from its foot, "hang" from an underside - its size range
# in metres, what the size measures ("height" or "extent", the larger side,
# for lumps such as stones) and its sway; variants may differ in mode or
# size. Variants left out of `use` are never picked.
const CATALOGUE := {
	"grass_tuft":{"folder":"vegetation","mode":"stand","size":[.5,.68],"measure":"height","sway":.07},
	"grass_blades":{"folder":"vegetation","mode":"stand","size":[.6,.82],"measure":"height","sway":.07},
	"bush":{"folder":"vegetation","mode":"stand","size":[.8,1.05],"measure":"extent","sway":.04,"sizes":{2:[.95,1.2]}},
	"dry_plant":{"folder":"vegetation","mode":"stand","size":[.7,.92],"measure":"height","sway":.04,"sizes":{4:[.8,1.0]}},
	"cactus":{"folder":"vegetation","mode":"stand","size":[1.05,1.5],"measure":"height","sway":.0,"sizes":{1:[.7,.9],3:[.85,1.1]}},
	"snow_plant":{"folder":"vegetation","mode":"stand","size":[.65,.85],"measure":"height","sway":.03,"use":[1,2,3,4],"sizes":{2:[1.1,1.4],3:[.75,.95],4:[.95,1.2]}},
	# Vines: most are painted growing upwards from a thick foot; the ivy,
	# the seed pods and the frosted ones with icicles hang.
	"vine_green":{"folder":"vegetation","mode":"climb","size":[1.5,2.1],"measure":"height","sway":.04,"modes":{3:"hang"},"sizes":{3:[1.7,2.4]}},
	"vine_root":{"folder":"vegetation","mode":"climb","size":[1.4,1.9],"measure":"height","sway":.03,"use":[1,2,3,4],"modes":{4:"hang"},"sizes":{4:[1.3,1.7]}},
	"vine_dry":{"folder":"vegetation","mode":"climb","size":[1.4,1.9],"measure":"height","sway":.03,"modes":{4:"hang"},"sizes":{4:[1.3,1.7]}},
	"vine_frost":{"folder":"vegetation","mode":"climb","size":[1.3,1.8],"measure":"height","sway":.03,"modes":{1:"hang",4:"hang"},"sizes":{1:[1.2,1.5],4:[1.3,1.7]}},
	"icicle":{"folder":"vegetation","mode":"hang","size":[.9,1.35],"measure":"height","sway":.0,"sizes":{2:[.75,1.0],5:[.7,.95]}},
	"stone_grey":{"folder":"stones","mode":"stand","size":[.55,.85],"measure":"extent","sway":.0},
	"scree_grey":{"folder":"stones","mode":"stand","size":[.75,1.05],"measure":"extent","sway":.0},
	"stone_desert":{"folder":"stones","mode":"stand","size":[.55,.85],"measure":"extent","sway":.0},
	"scree_desert":{"folder":"stones","mode":"stand","size":[.8,1.1],"measure":"extent","sway":.0},
	"stone_snow":{"folder":"stones","mode":"stand","size":[.55,.85],"measure":"extent","sway":.0},
	"scree_snow":{"folder":"stones","mode":"stand","size":[.75,1.05],"measure":"extent","sway":.0},
	"crystal_blue":{"folder":"crystals","mode":"stand","size":[.9,1.3],"measure":"extent","sway":.0},
	"crystal_ice":{"folder":"crystals","mode":"stand","size":[.95,1.4],"measure":"extent","sway":.0},
	"crystal_amber":{"folder":"crystals","mode":"stand","size":[.9,1.3],"measure":"extent","sway":.0},
	"tree_green":{"folder":"trees","mode":"stand","size":[3.8,4.8],"measure":"height","sway":.02},
	"tree_snow":{"folder":"trees","mode":"stand","size":[3.8,4.8],"measure":"height","sway":.015},
	"tree_dead":{"folder":"trees","mode":"stand","size":[3.2,4.2],"measure":"height","sway":.01},
	"skull":{"folder":"bones","mode":"stand","size":[.7,.95],"measure":"extent","sway":.0},
}
# What each climate grows and leaves lying about, by kind.
const TOPS := {"green":["grass_tuft","grass_tuft","grass_blades","grass_blades","bush"],"dry":["dry_plant","dry_plant","grass_tuft","grass_blades","cactus"],"cold":["snow_plant"]}
# Green tufts and blades a dry place can use: the parched ones.
const DRY_GRASS := {"grass_tuft":[4],"grass_blades":[5]}
const GREEN_GRASS := {"grass_tuft":[1,2,3,5],"grass_blades":[1,2,3,4]}
const CLIMBERS := {"green":["vine_green","vine_root"],"dry":["vine_dry"],"cold":["vine_frost"]}
const HANGERS := {"green":["vine_green","vine_root"],"dry":["vine_dry"],"cold":["vine_frost","icicle","icicle"]}
const STONES := {"green":["stone_grey","scree_grey"],"dry":["stone_desert","scree_desert"],"cold":["stone_snow","scree_snow"]}
const CRYSTALS := {"green":"crystal_blue","dry":"crystal_amber","cold":"crystal_ice"}
const TREES := {"green":"tree_green","dry":"tree_dead","cold":"tree_snow"}

# Sprites sit into the scene instead of on top of it: they sway, darken
# towards the stone they grow from (the foot of what stands or climbs, the
# root of what hangs), take a touch of the scene's cool light and cast real
# shadows on the rock.
const VEGETATION_SHADER := "shader_type spatial; render_mode cull_disabled; uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable; uniform vec4 tint : source_color = vec4(1.0); uniform float hanging = 0.0; uniform float sway = .06; uniform float wind = 1.0; uniform float contact = .42; void vertex(){ float w = hanging > .5 ? UV.y : 1.0-UV.y; w *= w; float phase = MODEL_MATRIX[3].x*.9 + MODEL_MATRIX[3].y*.37; VERTEX.x += sin(TIME*1.5+phase)*sway*w*wind; VERTEX.z += cos(TIME*1.1+phase)*sway*.3*w*wind; } void fragment(){ vec4 c = texture(albedo_tex, UV); float root = hanging > .5 ? smoothstep(.22, .0, UV.y) : smoothstep(.72, 1.0, UV.y); vec3 col = c.rgb*tint.rgb; float grey = dot(col, vec3(.299,.587,.114)); col = mix(vec3(grey), col, .88)*vec3(.93,.95,.98); col *= 1.0-root*contact; ALBEDO = col; ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = .5; ROUGHNESS = .9; NORMAL = FRONT_FACING ? NORMAL : -NORMAL; }"

static var _textures := {}
static var _materials := {}
static var _shaders := {}
static var _scenes := {}

static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var shader := Shader.new()
		shader.code = code
		_shaders[key] = shader
	return _shaders[key]

static func sprite_path(kind: String, variant: int) -> String:
	return SPRITES.path_join("%s/%s_%d.png" % [CATALOGUE[kind]["folder"],kind,variant])

static func variants(kind: String) -> Array:
	return CATALOGUE[kind].get("use",[1,2,3,4,5])

static func mode_of(kind: String, variant: int) -> String:
	return str(CATALOGUE[kind].get("modes",{}).get(variant,CATALOGUE[kind]["mode"]))

static func size_range(kind: String, variant: int) -> Array:
	return CATALOGUE[kind].get("sizes",{}).get(variant,CATALOGUE[kind]["size"])

# A sprite to place: [kind, variant, size], the size picked in its range.
static func entry(kind: String, variant: int, random: RandomNumberGenerator) -> Array:
	var range: Array = size_range(kind,variant)
	return [kind,variant,random.randf_range(float(range[0]),float(range[1]))]

# One of a kind's variants that grows the given way ("" for any).
static func pick(kind: String, random: RandomNumberGenerator, mode: String = "", only: Array = []) -> Array:
	var choices: Array = []
	for variant: int in variants(kind):
		if (mode.is_empty() or mode_of(kind,variant)==mode) and (only.is_empty() or variant in only): choices.append(variant)
	if choices.is_empty(): return []
	return entry(kind,choices[random.randi_range(0,choices.size()-1)],random)

# --- Sprites ------------------------------------------------------------------------

# The climate of a place: what it grows and what lies about.
static func climate(profile: GripBiomeProfile) -> String:
	var plants: Dictionary = profile.vegetation_set
	if bool(plants.get("frost",false)) or float(profile.weathering_rules.get("snow",0.0))>=.5: return "cold"
	if bool(plants.get("dry",false)) or float(profile.weathering_rules.get("dust",0.0))>=.5: return "dry"
	return "green"

static func pick_top(profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	var here := climate(profile)
	var kinds: Array = TOPS[here]
	var kind: String = kinds[random.randi_range(0,kinds.size()-1)]
	if kind in GREEN_GRASS: return pick(kind,random,"stand",DRY_GRASS[kind] if here=="dry" else GREEN_GRASS[kind])
	return pick(kind,random,"stand")

static func pick_cactus(random: RandomNumberGenerator) -> Array:
	return pick("cactus",random,"stand")

static func pick_stone(profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	var kinds: Array = STONES[climate(profile)]
	return pick(kinds[random.randi_range(0,kinds.size()-1)],random)

static func pick_crystal(profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	return pick(CRYSTALS[climate(profile)],random)

static func pick_tree(profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	return pick(TREES[climate(profile)],random)

static func pick_climber(profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	var kinds: Array = CLIMBERS[climate(profile)]
	return pick(kinds[random.randi_range(0,kinds.size()-1)],random,"climb")

static func pick_hanging(profile: GripBiomeProfile, random: RandomNumberGenerator) -> Array:
	var kinds: Array = HANGERS[climate(profile)]
	return pick(kinds[random.randi_range(0,kinds.size()-1)],random,"hang")

static func _material(kind: String, variant: int) -> ShaderMaterial:
	var key := "%s_%d" % [kind,variant]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = _shader("vegetation",VEGETATION_SHADER)
		material.set_shader_parameter("albedo_tex",_texture(kind,variant))
		material.set_shader_parameter("hanging",1.0 if mode_of(kind,variant)=="hang" else 0.0)
		material.set_shader_parameter("sway",float(CATALOGUE[kind]["sway"]))
		_materials[key] = material
	return _materials[key]

static func _texture(kind: String, variant: int) -> Texture2D:
	var key := "%s_%d" % [kind,variant]
	if not _textures.has(key): _textures[key] = load(sprite_path(kind,variant))
	return _textures[key]

# The size of a sprite on the face: its picked size (or the middle of its
# range) times `scale`, along the side its kind measures.
static func size_of(item: Array, scale: float = 1.0) -> Vector2:
	var kind: String = item[0]
	var variant: int = item[1]
	var texture := _texture(kind,variant)
	var range: Array = size_range(kind,variant)
	var size := (float(item[2]) if item.size()>2 else (float(range[0])+float(range[1]))*.5)*scale
	var aspect := texture.get_width()/float(texture.get_height())
	if CATALOGUE[kind]["measure"]=="extent" and aspect>1.0: return Vector2(size,size/aspect)
	if CATALOGUE[kind]["measure"]=="extent": return Vector2(size*aspect,size)
	return Vector2(size*aspect,size)

static func hangs(item: Array) -> bool:
	return mode_of(item[0],item[1])=="hang"

static func climbs(item: Array) -> bool:
	return mode_of(item[0],item[1])=="climb"

# A sprite on the holder: what stands or climbs has its foot on the origin,
# what hangs hangs from it; `scale` varies its size.
static func plant(holder: Node3D, item: Array, shadows: bool, scale: float = 1.0) -> MeshInstance3D:
	if item.is_empty(): return null
	var kind: String = item[0]
	var variant: int = item[1]
	var size := size_of(item,scale)
	var quad := QuadMesh.new()
	quad.size = size
	var mesh := MeshInstance3D.new()
	mesh.name = "Растение_%s_%d" % [kind,variant] if CATALOGUE[kind]["folder"]=="vegetation" else "Декор_%s_%d" % [kind,variant]
	mesh.mesh = quad
	mesh.material_override = _material(kind,variant)
	# The foot (or the point it hangs from) sits a hair inside the painted
	# outline, on the stone.
	mesh.position = Vector3(0,-size.y*.48 if hangs(item) else size.y*.48,.05)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh)
	return mesh

# --- Flags --------------------------------------------------------------------------

# Cloth shapes in model units (length along the flight, height) and which of
# them hang from a cord; the sleeve round the pole; where the cloth's top sits
# under the pole's top.
const CLOTH_SIZES := {"banner":Vector2(1.0,.62),"pennant":Vector2(1.1,.52),"swallowtail":Vector2(.95,.6),"streamer":Vector2(1.35,.3),
	"bunting_tri":Vector2(.34,.42),"prayer":Vector2(.3,.4),"bunting_round":Vector2(.32,.4)}
const LINE_CLOTHS := ["bunting_tri","prayer","bunting_round"]
const SLEEVE := .045
const FLAG_TOP := .12
const POLE_HEIGHTS := {"short":1.0,"tall":2.6,"mast":3.4}
# Flag kinds: [cloth, pole].
const FLAGS := {
	"flag":["banner","short"],"flag_wide":["swallowtail","short"],"pennant":["pennant","short"],
	"mast":["banner","tall"],"mast_pennant":["streamer","tall"],
	"mast_high":["swallowtail","mast"],"mast_high_pennant":["pennant","mast"],
}
const SMALL_FLAGS := ["flag","flag_wide","pennant"]
const MASTS := ["mast","mast_pennant"]
const HIGH_MASTS := ["mast_high","mast_high_pennant"]
const DESIGNS := ["peak","sun","stripes","chevron","hook","plain"]
const LINE_DESIGNS := ["plain","stripes","sun","peak"]
const COLORS := ["red","yellow","green","sky","purple","orange","white","blue"]
const COLOR_VALUES := {"red":Color("d9483a"),"yellow":Color("e7b13a"),"green":Color("4f9a56"),"sky":Color("4f9fd4"),"purple":Color("7f5cc4"),
	"orange":Color("e5733a"),"white":Color("ece6d8"),"blue":Color("3d5fb8")}

const CLOTH_SHADER := "shader_type spatial; render_mode cull_disabled; uniform sampler2D mask : source_color, filter_linear_mipmap, repeat_disable; uniform vec4 cloth_color : source_color = vec4(.85,.3,.25,1.0); uniform vec4 trim_color : source_color = vec4(.93,.74,.3,1.0); uniform float hang = 0.0; uniform float wind = 1.0; void vertex(){ float free = hang > .5 ? UV.y : UV.x; float phase = MODEL_MATRIX[3].x*.8 + MODEL_MATRIX[3].y*.5; float wave = sin(TIME*3.2 - free*6.0 + phase)*.07*free + sin(TIME*5.1 - free*11.0 + phase)*.015*free; VERTEX.z += wave*wind; VERTEX.y += (1.0-hang)*sin(TIME*2.3 - free*4.0 + phase)*.02*free*wind; } void fragment(){ vec4 m = texture(mask, UV); vec3 base = cloth_color.rgb*m.r; vec3 deep = cloth_color.rgb*.42*m.r; vec3 trim = trim_color.rgb*mix(.75,1.05,m.r); vec3 c = mix(base, deep, m.b); c = mix(c, trim, m.g); ALBEDO = c; ALPHA = m.a; ALPHA_SCISSOR_THRESHOLD = .5; ROUGHNESS = .88; NORMAL = FRONT_FACING ? NORMAL : -NORMAL; }"

static func _model(name: String) -> Node3D:
	if not _scenes.has(name): _scenes[name] = load(FLAG_DIR.path_join("%s.glb" % name))
	return (_scenes[name] as PackedScene).instantiate() as Node3D

static func _shadows(node: Node3D, shadows: bool) -> void:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func cloth_material(design: String, colour: String, line: bool) -> ShaderMaterial:
	var key := "cloth_%s_%s_%d" % [design,colour,int(line)]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = _shader("cloth",CLOTH_SHADER)
		material.set_shader_parameter("mask",load(CLOTH_DIR.path_join("cloth_%s.png" % design)))
		material.set_shader_parameter("cloth_color",COLOR_VALUES.get(colour,COLOR_VALUES["red"]))
		# Gold trim; a gold cloth gets a deep red one instead.
		material.set_shader_parameter("trim_color",Color("8e2f24") if colour in ["yellow","orange"] else Color("e6bc4c"))
		material.set_shader_parameter("hang",1.0 if line else 0.0)
		_materials[key] = material
	return _materials[key]

# The fittings' own materials: the models' vertex tones are only a preview.
const FITTINGS := {"iron":[Color("4a4540"),.35,.5],"brass":[Color("d6a640"),.5,.35],"rope":[Color("c9b183"),0.0,.95],"hem":[Color("ece4cf"),0.0,.9]}

static func _part_material(part: String) -> StandardMaterial3D:
	var key := "flag_%s" % part
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		if part=="wood":
			material.albedo_texture = load("res://assets/models/platforms/wood_grain.png")
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = true
			material.roughness = .85
		else:
			var fitting: Array = FITTINGS[part]
			material.albedo_color = fitting[0]
			material.metallic = fitting[1]
			material.roughness = fitting[2]
		_materials[key] = material
	return _materials[key]

static func _dress_parts(node: Node3D) -> void:
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var part := str(mesh.name).to_lower()
		if part=="wood" or FITTINGS.has(part): mesh.material_override = _part_material(part)

static func cloth(parent: Node3D, shape: String, design: String, colour: String, shadows: bool) -> Node3D:
	var node := _model("cloth_%s" % shape)
	node.name = "Полотно"
	parent.add_child(node)
	var material := cloth_material(design,colour,shape in LINE_CLOTHS)
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if str(mesh.name).to_lower().begins_with("cloth"): mesh.material_override = material
	_dress_parts(node)
	_shadows(node,shadows)
	return node

# A flag on its pole standing at `at` (the pole's foot), the pole `height`
# tall on the face, the cloth flying to `side` (+1 right, -1 left). The
# design follows the place unless one is given.
static func flag(parent: Node3D, kind: String, colour: String, at: Vector3, height: float, side: float, shadows: bool, design: String = "") -> Node3D:
	var entry: Array = FLAGS[kind]
	var root := Node3D.new()
	root.name = "Флаг на древке"
	root.position = at
	parent.add_child(root)
	var pole := _model("pole_%s" % entry[1])
	pole.name = "Древко"
	root.add_child(pole)
	_dress_parts(pole)
	_shadows(pole,shadows)
	if design.is_empty(): design = DESIGNS[posmod(int(absf(at.x*13.0+at.y*7.0)),DESIGNS.size())]
	var flag_cloth := cloth(root,entry[0],design,colour,shadows)
	flag_cloth.position = Vector3(0,float(POLE_HEIGHTS[entry[1]])-FLAG_TOP,0)
	var size := height/float(POLE_HEIGHTS[entry[1]])
	root.scale = Vector3(size*signf(side),size,size)
	return root

# A string of line flags between two points, sagging in the middle: a cord
# and flags of alternating shapes taking the colours in turn.
static func flag_string(parent: Node3D, start: Vector3, finish: Vector3, count: int, sag: float, seed_value: int, shadows: bool, long: bool = false) -> Node3D:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var root := Node3D.new()
	root.name = "Гирлянда флагов"
	parent.add_child(root)
	var points: Array[Vector3] = []
	for step in range(17):
		var t := step/16.0
		points.append(start.lerp(finish,t)+Vector3(0,-sag*sin(t*PI),0))
	root.add_child(rope(points,.012,Color("d8cfb4"),shadows))
	var first := random.randi_range(0,COLORS.size()-1)
	var shape: String = LINE_CLOTHS[random.randi_range(0,LINE_CLOTHS.size()-1)]
	var design: String = LINE_DESIGNS[random.randi_range(0,LINE_DESIGNS.size()-1)]
	var scale := 1.35 if long else 1.0
	for index in range(count):
		var t := (index+.5)/count
		var holder := Node3D.new()
		holder.name = "Флажок"
		holder.position = start.lerp(finish,t)+Vector3(0,-sag*sin(t*PI),.01)
		holder.scale = Vector3.ONE*scale
		root.add_child(holder)
		cloth(holder,shape,design,COLORS[(first+index)%COLORS.size()],shadows)
	return root

# A twisted cord along a path: a thin square tube.
static func rope(points: Array[Vector3], radius: float, color: Color, shadows: bool) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size()-1):
		var a := points[index]
		var b := points[index+1]
		var axis := (b-a).normalized()
		var across := axis.cross(Vector3.BACK).normalized()*radius
		var depth := axis.cross(across).normalized()*radius
		var ring_a := [a+across,a+depth,a-across,a-depth]
		var ring_b := [b+across,b+depth,b-across,b-depth]
		for k in range(4):
			var n := (k+1)%4
			var normal: Vector3 = ((ring_a[k]+ring_a[n])*.5-a).normalized()
			for p: Vector3 in [ring_a[k],ring_b[n],ring_a[n],ring_a[k],ring_b[k],ring_b[n]]:
				surface.set_color(color.darkened(.12*float(k%2)))
				surface.set_normal(normal)
				surface.add_vertex(p)
	if not _materials.has("rope"):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = .95
		_materials["rope"] = material
	var mesh := MeshInstance3D.new()
	mesh.name = "Верёвка"
	mesh.mesh = surface.commit()
	mesh.material_override = _materials["rope"]
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
