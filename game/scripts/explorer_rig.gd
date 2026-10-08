class_name ExplorerRig
extends Node3D

const ART := "res://assets/art/modular-pack-v1/"
const UPPER_ARM := .145
const FOREARM := .13
var head: Sprite3D
var torso: Sprite3D
var pelvis: Sprite3D
var head_open: Texture2D
var head_blink: Texture2D
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var hands: Array[Node3D] = []
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var boots: Array[Node3D] = []
var facing := 1.0

func joint(parent: Node3D, title: String, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = title
	node.position = at
	parent.add_child(node)
	return node

func part(parent: Node3D, title: String, height: float, at: Vector3, pivot := Vector2(.5,.5)) -> Sprite3D:
	var texture := load(ART+"sprites/character/"+title+".tres") as Texture2D
	return sprite(parent,texture,title,height,at,pivot)

func sprite(parent: Node3D, texture: Texture2D, title: String, height: float, at: Vector3, pivot := Vector2(.5,.5)) -> Sprite3D:
	var node := Sprite3D.new()
	node.name = title
	node.texture = texture
	node.pixel_size = height/texture.get_height()
	node.position = at+Vector3((.5-pivot.x)*texture.get_width()*node.pixel_size,(pivot.y-.5)*height,0)
	node.shaded = false
	node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	node.alpha_scissor_threshold = .20
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(node)
	return node

func segment(parent: Node3D, title: String, length: float, socket: Vector2, end: Vector2) -> Sprite3D:
	var texture := load(ART+"sprites/character/"+title+".tres") as Texture2D
	var span := (end-socket)*texture.get_size()*Vector2(1,-1)
	var angle := Vector2(0,-1).angle()-span.angle()
	var node := sprite(parent,texture,title,texture.get_height()*length/span.length(),Vector3.ZERO,socket)
	# Both the image and its offset rotate about the anatomical socket.
	node.position = node.position.rotated(Vector3.BACK,angle)
	node.rotation.z = angle
	return node

func socket_position(owner_part: Sprite3D, uv: Vector2, depth: float) -> Vector3:
	var pixels := (uv-Vector2(.5,.5))*owner_part.texture.get_size()
	return owner_part.transform*Vector3(pixels.x*owner_part.pixel_size,-pixels.y*owner_part.pixel_size,0)+Vector3(0,0,depth)

func limb_core(parent: Node3D, length: float, radius: float, color: Color) -> void:
	# Continuous cloth beneath the textured pieces closes their hollow sockets.
	var core := MeshInstance3D.new()
	core.name = "Основа рукава или штанины"
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length+radius*2
	mesh.radial_segments = 12
	mesh.rings = 3
	core.mesh = mesh
	core.position = Vector3(0,-length*.5,-radius-.005)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	core.material_override = material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(core)

func shoulder_cover(at: Vector3, size: Vector2, angle: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(24):
		for corner in [Vector2.ZERO,Vector2.from_angle(TAU*index/24.0),Vector2.from_angle(TAU*(index+1)/24.0)]:
			surface.set_color(Color.WHITE if corner==Vector2.ZERO else Color(.68,.68,.68))
			surface.set_uv((Vector2(184,457)+corner*Vector2(24,-43))/Vector2(1280,1280))
			surface.set_normal(Vector3.BACK)
			surface.add_vertex(Vector3(corner.x*size.x*.5,corner.y*size.y*.5,0))
	var cover := MeshInstance3D.new()
	cover.name = "Ткань плеча внутри проймы"
	cover.mesh = surface.commit()
	cover.position = at
	cover.rotation.z = angle
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load(ART+"character-parts.png") as Texture2D
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cover.material_override = material
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cover)

func setup() -> void:
	name = "Походный персонаж"
	var backpack := load(ART+"backpack.png") as Texture2D
	sprite(self,backpack,"Рюкзак со скаткой",.94,Vector3(-.20,-.025,-.12))
	torso = part(self,"torso",.31,Vector3(.015,-.075,0))
	torso.scale.x = 1.12
	pelvis = part(self,"pelvis",.17,Vector3(.015,-.255,.01))
	head = part(self,"head-open",.54,Vector3(.015,.26,.04))
	head_open = head.texture
	head_blink = load(ART+"sprites/character/head-blink.tres") as Texture2D
	for index in range(2):
		# In this three-quarter drawing the visible, near armhole is on the left.
		var near := index==0
		var suffix := "near" if near else "far"
		var shoulder_uv := Vector2(31.0/270,108.0/287) if near else Vector2(259.0/270,83.0/287)
		shoulder_cover(socket_position(torso,shoulder_uv,.012),Vector2(.056,.094) if near else Vector2(.028,.070),.10 if near else -.15)
		var shoulder := joint(self,"Плечо "+suffix,socket_position(torso,shoulder_uv,.025 if near else -.025))
		limb_core(shoulder,UPPER_ARM,.026,Color("4a4b2e"))
		segment(shoulder,"upper-arm-"+suffix,UPPER_ARM,Vector2(.68,.12),Vector2(.37,.87))
		var elbow := joint(shoulder,"Локоть",Vector3(0,-UPPER_ARM,.01 if near else .085))
		limb_core(elbow,FOREARM,.023,Color("4a4b2e"))
		segment(elbow,"forearm-"+suffix,FOREARM,Vector2(.55,.09),Vector2(.47,.88))
		var hand := joint(elbow,"Кисть",Vector3(0,-FOREARM,.015))
		segment(hand,"hand-"+suffix,.067,Vector2(.40,.13),Vector2(.57,.69))
		shoulders.append(shoulder)
		elbows.append(elbow)
		hands.append(hand)
		var hip_uv := Vector2(.23 if near else .77,.65)
		var hip := joint(self,"Бедро "+suffix,socket_position(pelvis,hip_uv,-.04 if near else -.06))
		limb_core(hip,.10,.029,Color("443a2d"))
		segment(hip,"thigh-"+suffix,.10,Vector2(.60,.12),Vector2(.42,.88))
		var knee := joint(hip,"Колено",Vector3(0,-.10,.01))
		limb_core(knee,.085,.025,Color("443a2d"))
		segment(knee,"shin-"+suffix,.085,Vector2(.57,.12),Vector2(.50,.86))
		var boot := joint(knee,"Стопа",Vector3(0,-.085,.01))
		part(boot,"boot-"+suffix,.13,Vector3.ZERO,Vector2(.34,.22))
		hips.append(hip)
		knees.append(knee)
		boots.append(boot)

func pose_arm(index: int, destination: Vector2, bend: float) -> void:
	var shoulder := shoulders[index]
	var delta := destination-Vector2(shoulder.position.x,shoulder.position.y)
	var distance := clampf(delta.length(),.09,UPPER_ARM+FOREARM-.008)
	delta = delta.normalized()*distance
	var angle := delta.angle()+bend*acos(clampf((UPPER_ARM*UPPER_ARM+distance*distance-FOREARM*FOREARM)/(2*UPPER_ARM*distance),-1,1))
	shoulder.rotation.z = angle+PI*.5
	var elbow := Vector2(cos(angle),sin(angle))*UPPER_ARM
	elbows[index].rotation.z = (delta-elbow).angle()+PI*.5-shoulder.rotation.z

func animate(sim: RopeSim, target: Vector2, tether: bool, time: float) -> void:
	var direction := target-sim.pos
	if tether and absf(direction.x)>.35:
		facing = signf(direction.x)
	elif not tether and absf(sim.vel.x)>.7:
		facing = signf(sim.vel.x)
	scale.x = facing
	rotation.z = clampf(-sim.vel.x*.025,-.18,.18)
	if sim.attached: rotation.z += clampf(-direction.x*.02,-.08,.08)
	var blink := fmod(time+1.1,4.8)<.13
	head.texture = head_blink if blink else head_open
	head.rotation.z = -rotation.z*.25
	var stride := sin(time*6)*clampf(sim.vel.length()/7,0,1)
	for index in range(2):
		var side := 1.0 if index==1 else -1.0
		hips[index].rotation.z = side*.12*stride+clampf(sim.vel.x*facing*.018,-.10,.10)
		knees[index].rotation.z = 0.0 if sim.grounded else .16+side*.08*stride
		boots[index].rotation.z = -knees[index].rotation.z*.45
	var far_shoulder := Vector2(shoulders[0].position.x,shoulders[0].position.y)
	pose_arm(0,far_shoulder+Vector2(-.015-.012*stride,-.264+.005*sin(time*3)),-1)
	if tether:
		var local_target := to_local(Vector3(target.x,target.y,global_position.z))
		var shoulder := Vector2(shoulders[1].position.x,shoulders[1].position.y)
		var reach := Vector2(local_target.x,local_target.y)-shoulder
		# Short arms reach beside the large head, rather than through its face.
		var reach_angle := minf(reach.angle(),.55) if reach.y>0 else reach.angle()
		pose_arm(1,shoulder+Vector2.from_angle(reach_angle)*(UPPER_ARM+FOREARM-.008),1)
		var wrist := to_local(hands[1].global_position)
		var wrist_angle := Vector2(local_target.x-wrist.x,local_target.y-wrist.y).angle()
		hands[1].rotation.z = wrist_angle+PI*.5-shoulders[1].rotation.z-elbows[1].rotation.z
	else:
		hands[1].rotation.z = 0
		var near_shoulder := Vector2(shoulders[1].position.x,shoulders[1].position.y)
		pose_arm(1,near_shoulder+Vector2(.015+.012*stride,-.264+.005*sin(time*3+1)),1)

func grip_position() -> Vector3:
	return hands[1].to_global(Vector3(0,-.067,.025))
