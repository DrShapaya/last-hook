class_name ExplorerRig
extends Node3D

const ART := "res://assets/art/modular-pack-v1/"
const UPPER_ARM := .12
const FOREARM := .11
var head: Sprite3D
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

func setup() -> void:
	name = "Походный персонаж"
	var backpack := load(ART+"backpack.png") as Texture2D
	sprite(self,backpack,"Рюкзак со скаткой",.90,Vector3(-.19,.015,-.10))
	part(self,"torso",.22,Vector3(0,-.11,0))
	part(self,"pelvis",.11,Vector3(0,-.24,.01))
	head = part(self,"head-open",.54,Vector3(0,.24,.04))
	head_open = head.texture
	head_blink = load(ART+"sprites/character/head-blink.tres") as Texture2D
	for index in range(2):
		var near := index==1
		var suffix := "near" if near else "far"
		var side := 1.0 if near else -1.0
		var depth := .09 if near else -.04
		var shoulder := joint(self,"Плечо "+suffix,Vector3(side*.12,-.045,depth))
		part(shoulder,"upper-arm-"+suffix,.155,Vector3.ZERO,Vector2(.64,.10)).rotation.z = .27
		var elbow := joint(shoulder,"Локоть",Vector3(0,-UPPER_ARM,.01))
		part(elbow,"forearm-"+suffix,.14,Vector3.ZERO,Vector2(.55,.08)).rotation.z = .075
		var hand := joint(elbow,"Кисть",Vector3(0,-FOREARM,.015))
		part(hand,"hand-"+suffix,.10,Vector3.ZERO,Vector2(.50,.13))
		shoulders.append(shoulder)
		elbows.append(elbow)
		hands.append(hand)
		var hip := joint(self,"Бедро "+suffix,Vector3(side*.075,-.26,depth*.6))
		part(hip,"thigh-"+suffix,.09,Vector3.ZERO,Vector2(.55,.10)).rotation.z = .09
		var knee := joint(hip,"Колено",Vector3(0,-.065,.01))
		part(knee,"shin-"+suffix,.08,Vector3.ZERO,Vector2(.50,.08))
		var boot := joint(knee,"Стопа",Vector3(0,-.055,.01))
		part(boot,"boot-"+suffix,.10,Vector3.ZERO,Vector2(.32,.25))
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
	rotation.z = clampf(-sim.vel.x*.035,-.32,.32)
	if sim.attached: rotation.z += clampf(-direction.x*.045,-.18,.18)
	var blink := fmod(time+1.1,4.8)<.13
	head.texture = head_blink if blink else head_open
	head.rotation.z = -rotation.z*.25
	var stride := sin(time*6)*clampf(sim.vel.length()/7,0,1)
	for index in range(2):
		var side := 1.0 if index==1 else -1.0
		hips[index].rotation.z = side*(.10+.18*stride)+clampf(sim.vel.x*facing*.025,-.16,.16)
		knees[index].rotation.z = .12 if sim.grounded else .30+side*.12*stride
		boots[index].rotation.z = -knees[index].rotation.z*.45
	pose_arm(0,Vector2(-.19,-.25)+Vector2(-.035*stride,.02*sin(time*3)),-1)
	if tether:
		var local_target := to_local(Vector3(target.x,target.y,global_position.z))
		pose_arm(1,Vector2(local_target.x,local_target.y),1)
	else:
		pose_arm(1,Vector2(.20,-.24)+Vector2(.04*stride,.02*sin(time*3+1)),1)

func grip_position() -> Vector3:
	return hands[1].to_global(Vector3(0,-.032,.025))
