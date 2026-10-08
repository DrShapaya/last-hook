class_name MountainWorld
extends Node3D

var anchors: Array[Dictionary] = []
var finds: Array[Dictionary] = []
var ledges: Array[Dictionary] = []
var chunks: Array[Node3D] = []
var materials: Dictionary = {}
var seed_value := 0
var location := 0
var generated_height := 0.0
var main_index := 0
var scenery_index := 0
var anchor_index := 0
var loot_index := 0
var scenery_parent: Node3D
var ghost_texture: ImageTexture
var environment_texture: Texture2D
var object_texture: Texture2D
var object_mask: Image
var backdrop_material: ShaderMaterial

func setup(world_seed: int, world_location: int) -> void:
	seed_value = world_seed
	location = world_location
	scenery_parent = self
	environment_texture = load("res://assets/art/canyon-v2.png")
	var backdrop_shader := Shader.new()
	backdrop_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D scene_texture : source_color, filter_linear_mipmap;
void fragment() {
    vec4 scene = texture(scene_texture, UV);
    ALBEDO = scene.rgb;
    ALPHA = smoothstep(0.0, 0.075, UV.y) * smoothstep(0.0, 0.075, 1.0-UV.y);
}"""
	backdrop_material = ShaderMaterial.new()
	backdrop_material.shader = backdrop_shader
	backdrop_material.set_shader_parameter("scene_texture",environment_texture)
	if ResourceLoader.exists("res://assets/art/natural-objects-v2.png"):
		object_texture = load("res://assets/art/natural-objects-v2.png")
		object_mask = object_texture.get_image()
		if object_mask.is_compressed():
			object_mask.decompress()
	ledges.append({"left": -5.8, "right": 5.8, "top": .15})
	object_sprite("Подножие",3,Vector3(0,-.35,1.8),Vector2(12,2.4),self)

func mat(key: String, color: Color, unlit: bool = false) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = .93
	if unlit:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = result
	return result

func stone_color(zone: int) -> Color:
	if location == 1:
		return Color("6f7887").lerp(Color("a4adbc"),zone/8.0)
	if location == 2:
		return Color("85786a")
	return [Color("7b7965"),Color("747f8b"),Color("a08a6d"),Color("a3c3ce"),Color("574c51"),Color("b8a78d")][clampi(zone,0,5)]

func mesh_node(node_name: String, mesh: Mesh, where: Vector3, scale_value: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	(parent if parent != null else scenery_parent).add_child(instance)
	instance.position = where if parent == null else parent.to_local(where)
	instance.scale = scale_value
	return instance

func box(node_name: String, where: Vector3, scale_value: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh_node(node_name,mesh,where,scale_value,material,parent)

func sphere(node_name: String, where: Vector3, scale_value: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh_node(node_name,mesh,where,scale_value,material,parent)

func cylinder(node_name: String, where: Vector3, radius: float, height: float, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius*.78
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	return mesh_node(node_name,mesh,where,Vector3.ONE,material,parent)

func rock(where: Vector3, scale_value: Vector3, salt: int, color: Color) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ salt
	var points: Array[Vector3] = []
	var triangles: Array[int] = []
	const SIDES := 7
	const RINGS := 4
	for ring in range(RINGS):
		for side in range(SIDES):
			var angle := side*TAU/SIDES + (.10 if ring%2==0 else -.12)
			var radius := rng.randf_range(.77,1.03) * (.8 if ring==0 or ring==RINGS-1 else 1.0)
			points.append(Vector3(cos(angle)*radius,-1+ring*2.0/(RINGS-1)+rng.randf_range(-.09,.09),sin(angle)*radius))
	for ring in range(RINGS-1):
		for side in range(SIDES):
			var a := ring*SIDES+side
			var b := ring*SIDES+(side+1)%SIDES
			triangles.append_array([a,a+SIDES,b,b,a+SIDES,b+SIDES])
	for side in range(1,SIDES-1):
		triangles.append_array([0,side,side+1,(RINGS-1)*SIDES,(RINGS-1)*SIDES+side+1,(RINGS-1)*SIDES+side])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(0,triangles.size(),3):
		var a := points[triangles[index]]
		var b := points[triangles[index+1]]
		var c := points[triangles[index+2]]
		var normal := (b-a).cross(c-a).normalized()
		if normal.dot((a+b+c)/3) < 0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		# Godot uses clockwise front-face winding; keep the outward normal.
		for vertex in [a,c,b]:
			surface.set_normal(normal)
			surface.add_vertex(vertex)
	var palette := absi(salt)%4
	var material := mat("%s_%d_%d" % ["distant" if where.z < -10 else "stone",clampi(int(where.y/20),0,5),palette],color*(.86+palette*.055))
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return mesh_node("Скала",surface.commit(),where,scale_value,material)

func grass(center: Vector3, radius: float, salt: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ salt
	for index in range(10):
		var position_value := center+Vector3(rng.randf_range(-radius,radius),rng.randf_range(0,.18),rng.randf_range(-radius*.5,radius*.5))
		var leaf := sphere("Мох",position_value,Vector3(.7,.22,.52),mat("green_%d" % (index%3),Color(.33+index%3*.055,.47+index%3*.055,.16)))
		leaf.rotation_degrees = Vector3(0,rng.randf()*360,rng.randf_range(-15,15))
	for index in range(5):
		var fern := box("Папоротник",center+Vector3(rng.randf_range(-radius*.6,radius*.6),.3,.4),Vector3(.08,.75,.05),mat("fern",Color("a2b44b")))
		fern.rotation_degrees.z = -32+index*16
		for blade in range(2):
			var branch := box("Лист",fern.position+Vector3((blade*2-1)*.15,.1,.02),Vector3(.35,.07,.07),mat("fern",Color("a2b44b")))
			branch.rotation_degrees.z = (blade*2-1)*25

func tree(where: Vector3, salt: int) -> void:
	var trunk := cylinder("Дерево",where+Vector3.UP*1.3,.15,2.6,mat("trunk",Color("735035")))
	trunk.rotation_degrees.z = -17
	for index in range(3):
		var branch := cylinder("Ветка",where+Vector3((index-1)*.55,2+index*.3,0),.075,1.4,mat("trunk",Color("735035")))
		branch.rotation_degrees.z = -55+index*45
		sphere("Крона",where+Vector3((index-1)*.8,2.8+index*.3,0),Vector3(2.0,1.15,1.35),mat("crown_%d" % index,Color(.28+index*.04,.43+index*.045,.12)))

func wooden_shelf(point: Vector2, is_ledge: bool) -> void:
	var side := 1.0 if point.x >= 0 else -1.0
	var center := Vector3(point.x+side*.7,point.y-.2,.6)
	object_sprite("Деревянный настил",3,center+Vector3(0,-.37,1),Vector2(3.4,2.1),self)
	if is_ledge:
		ledges.append({"left": center.x-1.2,"right": center.x+1.2,"top":point.y-.1})

func generate_to(height: float, finite: bool, summit: float = 120) -> void:
	var target := minf(height,summit+6) if finite else height
	while scenery_index*24 < target:
		var y := scenery_index*24.0
		var chunk := Node3D.new()
		chunk.name = "Участок_%d" % scenery_index
		add_child(chunk)
		chunks.append(chunk)
		scenery_parent = chunk
		var backdrop := Sprite3D.new()
		backdrop.name = "Фактурное ущелье"
		backdrop.texture = environment_texture
		backdrop.pixel_size = 24.0/environment_texture.get_height()
		backdrop.scale.y = 28.0/24
		backdrop.material_override = backdrop_material
		backdrop.shaded = false
		backdrop.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		chunk.add_child(backdrop)
		backdrop.position = Vector3(0,y+12,-4-scenery_index*.005)
		# These are world-space layers; camera movement scrolls past the scene.
		scenery_index += 1
	scenery_parent = self
	while 4.8+main_index*3.5 < target-1:
		var index := main_index
		main_index += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value+index*1741
		var y := 4.8+index*3.5+rng.randf_range(-.12,.12)
		var x := (1 if index%2==0 else -1)*(1.9+rng.randf_range(-.15,.15))
		var zone := clampi(int(y/20),0,5)
		var kind := 1 if index>2 and index%9==5 else 2 if index%4==2 else 0
		add_anchor(Vector2(x,y),kind,index%3==1)
		if index%3==0:
			wooden_shelf(Vector2(x,y-1),index%6==0)
		add_find(Vector2(x*.4,y-1.8),zone,[40,75,130,220,360,560][zone],false)
		if index%4==2:
			add_find(Vector2(-signf(x)*4.2,y+.4),zone,roundi([40,75,130,220,360,560][zone]*1.8),true)
			if zone>=3:
				add_anchor(Vector2(-signf(x)*4.0,y+1.6),4 if zone>=5 else 3)
	generated_height = target
	if finite and target>=summit and not has_node("Вершина"):
		var marker := Node3D.new()
		marker.name = "Вершина"
		add_child(marker)
		wooden_shelf(Vector2(0,summit+.25),true)
		var post := cylinder("Флаг вершины",Vector3(.4,summit+1,1),.05,3,mat("flagpost",Color("b8a178")))
		box("Знамя",post.position+Vector3(.6,.7,0),Vector3(1.1,.7,.06),mat("summitflag",Color("dc6e36")))

func _make_glow_texture() -> void:
	var image := Image.create(48,48,false,Image.FORMAT_RGBA8)
	for x in range(48):
		for y in range(48):
			var distance := Vector2(x-23.5,y-23.5).length()/24
			image.set_pixel(x,y,Color(1,1,1,pow(maxf(0,1-distance),2)*.6))
	ghost_texture = ImageTexture.create_from_image(image)

func object_sprite(node_name: String, cell: int, where: Vector3, dimensions: Vector2, parent: Node3D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = node_name
	parent.add_child(sprite)
	sprite.position = parent.to_local(where)
	if object_texture!=null:
		var atlas := AtlasTexture.new()
		atlas.atlas = object_texture
		var size := object_texture.get_size()/2
		atlas.region = Rect2(Vector2(cell%2,cell/2)*size,size)
		atlas.filter_clip = true
		sprite.texture = atlas
		sprite.pixel_size = dimensions.x/size.x
		sprite.scale.y = dimensions.y/dimensions.x
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = .12
	return sprite

func add_anchor(point: Vector2, kind: int, bush: bool = false) -> void:
	var holder := Node3D.new()
	holder.name = "Зацеп_%d" % anchor_index
	add_child(holder)
	holder.position = Vector3(point.x,point.y,2)
	var shape := "branch" if kind==1 or kind==2 else "bush" if bush and kind==0 else "rock"
	var cell := 2 if shape=="branch" else 1 if shape=="bush" else 0
	var dimensions := Vector2(3.2,1.9) if shape=="rock" else Vector2(2.8,2.6)
	var sprite := object_sprite("Корень" if kind==1 else "Ветка" if kind==2 else "Куст" if shape=="bush" else "Каменный выступ",cell,holder.position,dimensions,holder)
	if kind==3:
		sprite.modulate = Color("c5e8f2")
	elif kind==4:
		sprite.modulate = Color("c0a9d9")
	anchors.append({"id":anchor_index,"pos":point,"kind":kind,"shape":shape,"cell":cell,"dimensions":dimensions,"broken":false,"visual":holder})
	anchor_index += 1

func hit_object(from: Vector2, to: Vector2, object: Dictionary, grip: float) -> float:
	var center: Vector2 = object["pos"]
	var tolerance := .04+maxf(0,grip-.32)*.25
	if object_mask!=null:
		var dimensions: Vector2 = object["dimensions"]
		var half := dimensions*.5+Vector2.ONE*tolerance
		var bounds := PackedVector2Array([center-half,center+Vector2(half.x,-half.y),center+half,center+Vector2(-half.x,half.y)])
		var entry := RopeSim.hit_polygon(from,to,bounds)
		if entry<0:
			return -1.0
		# Collision reads the visible sprite's alpha, so a hook can catch either
		# end of a branch or any exposed rock face, but not its transparent gaps.
		var samples := maxi(1,ceili(from.distance_to(to)/.012))
		for index in range(maxi(0,floori(entry*samples)),samples+1):
			var t := float(index)/samples
			var local := from.lerp(to,t)-center
			for offset in [Vector2.ZERO,Vector2(tolerance,0),Vector2(-tolerance,0),Vector2(0,tolerance),Vector2(0,-tolerance)]:
				if mask_contains(local+offset,object):
					return t
		return -1.0
	match object.get("shape","rock"):
		"branch":
			return RopeSim.hit_capsule(from,to,center+Vector2(-1.05,-.95),center+Vector2(.85,.75),.27+tolerance)
		"bush":
			return RopeSim.hit_capsule(from,to,center+Vector2(-.45,.2),center+Vector2(.45,.2),.8+tolerance)
		_:
			var vertices := PackedVector2Array([Vector2(-1.12,-.23),Vector2(-1.28,.08),Vector2(-.9,.50),Vector2(.77,.48),Vector2(1.22,.16),Vector2(.91,-.48),Vector2(-.61,-.56)])
			for index in range(vertices.size()):
				vertices[index] = center+vertices[index]*(1+tolerance)
			return RopeSim.hit_polygon(from,to,vertices)

func mask_contains(local: Vector2, object: Dictionary) -> bool:
	var dimensions: Vector2 = object["dimensions"]
	var uv := Vector2(local.x/dimensions.x+.5,.5-local.y/dimensions.y)
	if uv.x<0 or uv.y<0 or uv.x>=1 or uv.y>=1:
		return false
	var width := object_mask.get_width()/2
	var height := object_mask.get_height()/2
	var cell: int = object["cell"]
	return object_mask.get_pixel(int(uv.x*width)+(cell%2)*width,int(uv.y*height)+(cell/2)*height).a>.35

func add_find(point: Vector2, tier: int, value: int, rare: bool) -> void:
	var holder := Node3D.new()
	holder.name = "Находка_%d" % loot_index
	add_child(holder)
	holder.position = Vector3(point.x,point.y,2.2)
	var mesh := box("Предмет",holder.position,Vector3(.28,.38,.26),mat("loot_%d" % int(rare),Color("ffca60") if rare else Color("e3b95e")),holder)
	mesh.rotation_degrees = Vector3(20,30,35)
	box("Ободок",holder.position+Vector3(0,0,.16),Vector3(.31,.07,.06),mat("band",Color("866331")),holder)
	var price := Label3D.new()
	price.text = str(value)
	price.font_size = 32
	price.pixel_size = .012
	price.outline_size = 9
	price.modulate = Color("ffda83")
	price.outline_modulate = Color("233743")
	price.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	holder.add_child(price)
	price.position = Vector3(0,.55,.2)
	finds.append({"item":{"id":loot_index,"tier":tier,"value":value},"pos":point,"visual":holder})
	loot_index += 1

func anchor_by_id(id: int) -> Dictionary:
	for point in anchors:
		if int(point["id"]) == id:
			return point
	return {}

func cast_hook(from: Vector2, to: Vector2, grip: float) -> Dictionary:
	var best := 2.0
	var result: Dictionary = {}
	for object in anchors:
		if object["broken"]:
			continue
		var fraction := hit_object(from,to,object,grip)
		if fraction>=0 and fraction<best:
			best = fraction
			result = {"object":object,"fraction":fraction,"contact":from.lerp(to,fraction)}
	return result

func object_description(object: Dictionary) -> String:
	match int(object["kind"]):
		1: return "Корень · хрупкий"
		2: return "Ветка · упругая"
		3: return "Ледяной выступ · захват ур. 3"
		4: return "Кристальный выступ · захват ур. 5"
	return "Древесный куст · надёжный" if object["shape"]=="bush" else "Каменный выступ · надёжный"

func update_visibility(center_y: float) -> void:
	for index in range(chunks.size()):
		chunks[index].visible = absf(index*24+12-center_y)<45
	for point in anchors:
		point["visual"].visible = not point["broken"] and absf(point["pos"].y-center_y)<30
	for find in finds:
		find["visual"].visible = not bool(find.get("picked",false)) and absf(find["pos"].y-center_y)<30
