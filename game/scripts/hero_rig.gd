class_name HeroRig
extends Node3D

# Cut-out hero on bones (CHARACTER_PLAN.md, stage 2 prototype).
#
# The skeleton, the parts, their paint frames and the drawing order come from
# assets/hero/skeleton.json (tools/character_template.py). Every part is a flat
# mesh skinned to a Skeleton3D: a sleeve bends smoothly across the elbow by two
# bones, the torso by two spine bones; gloves, head and backpack stay rigid.
# Part pictures are loaded from assets/hero/pioneer/ and fall back to the
# placeholders in assets/hero/placeholder/.

const SKELETON_PATH := "res://assets/hero/skeleton.json"
const ART_DIRS := ["res://assets/hero/pioneer/","res://assets/hero/placeholder/"]
# World height of the hero; matches the painted hero inside ExplorerSprite.
const HEIGHT := .97
# Feet of the hero relative to this node, as in ExplorerSprite.
const FEET_Y := -.5
const FAR_TINT := Color(.62,.62,.66)
# Parts of the stage 2 slice: torso, one whole arm and the head.
const SLICE := ["torso","sleeve_near","glove_near","head","eyes"]
# The whole hero (stage 2, second half): every body layer of the template.
# Headwear and the hook are slots for later stages.
const FULL := ["glove_far","sleeve_far","boot_far","pant_leg_far","backpack","pelvis","pant_leg_near","boot_near","torso","head","eyes","glove_near","sleeve_near"]
# Half-width of the weight blend around a bending joint, as a share of the
# part width. Wider gives a rounder elbow, narrower a sharper crease.
var bend_blend := .65
# false: plain two-bone linear blend (for comparison in the prototype preview).
var use_helpers := true
# Both eyes as one picture (eyes.png, 160x240), measured on reference-v2.
const EYES_SIZE := Vector2(.056,.084)

var data: Dictionary
var skeleton: Skeleton3D
var bone_index := {}
var rest := {} # Bone positions in hero units.
var layers: Array = []
var parts := {} # Layer name -> MeshInstance3D.
var rest_vertices := {} # Layer name -> PackedVector3Array (skeleton space).
var vertex_bones := {} # Layer name -> PackedInt32Array, 4 per vertex.
var vertex_weights := {} # Layer name -> PackedFloat32Array, 4 per vertex.
var skin: Skin
var art_source := ""
# Helper bone in a bending joint -> the joint it follows at half the angle.
# Weights pass upper -> helper -> lower, so a deep bend keeps its volume
# instead of pinching (plain linear blending collapses the inner side).
var helpers := {}

func setup(slice: Array = SLICE, blend: float = -1.0, helpers_on: bool = true) -> void:
	if blend>0: bend_blend = blend
	use_helpers = helpers_on
	if is_instance_valid(skeleton): return
	name = "HeroRig"
	data = JSON.parse_string(FileAccess.get_file_as_string(SKELETON_PATH))
	layers = data["layers_back_to_front"]
	skeleton = Skeleton3D.new()
	skeleton.name = "Скелет"
	skeleton.position.y = FEET_Y
	add_child(skeleton)
	for bone in data["bones"]:
		rest[bone["name"]] = Vector2(bone["position"][0],bone["position"][1])
		bone_index[bone["name"]] = skeleton.add_bone(bone["name"])
	for bone in data["bones"]:
		var index: int = bone_index[bone["name"]]
		var local: Vector2 = rest[bone["name"]]
		if bone["parent"]!=null:
			skeleton.set_bone_parent(index,bone_index[bone["parent"]])
			local -= rest[bone["parent"]]
		skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,Vector3(local.x,local.y,0)*HEIGHT))
	for pair in _bending_joints():
		var upper: String = pair[0]
		var lower: String = pair[1]
		var helper := lower+"_mid"
		if bone_index.has(helper): continue
		var index := skeleton.add_bone(helper)
		bone_index[helper] = index
		rest[helper] = rest[lower]
		helpers[helper] = lower
		skeleton.set_bone_parent(index,bone_index[upper])
		var local: Vector2 = rest[lower]-rest[upper]
		skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,Vector3(local.x,local.y,0)*HEIGHT))
	skeleton.reset_bone_poses()
	skin = skeleton.create_skin_from_rest_transforms()
	for layer in slice: _build_layer(layer)
	_add_joint_shadow("shoulder_near",Vector2(.15,.13),Vector2(-.01,-.01))
	_add_joint_shadow("neck",Vector2(.24,.08),Vector2(0,.0))

# [upper, lower] bone pairs that some part bends across, for both sides.
func _bending_joints() -> Array:
	var result: Array = []
	for part in data["parts"]:
		if part.has("chain") and part["chain"].size()>=2:
			for side in ["near","far"]: result.append([sided(part["chain"][0],side),sided(part["chain"][1],side)])
		elif part["bones"].size()==2:
			result.append([part["bones"][0],part["bones"][1]])
	return result

func part_info(id: String) -> Dictionary:
	for part in data["parts"]:
		if part["id"]==id: return part
	return {}

# Render priority of a template layer; steps of LAYER_STEP leave room for the
# animation to slip a part between two layers (an arm behind the head).
const LAYER_STEP := 4
func layer_priority(layer: String) -> int:
	return layers.find(layer)*LAYER_STEP

static func sided(bone: String, side: String) -> String:
	return bone.replace("_near","_"+side)

func _texture(file: String) -> Texture2D:
	for directory in ART_DIRS:
		if ResourceLoader.exists(directory+file):
			if art_source.is_empty() or directory==ART_DIRS[0]: art_source = directory
			return load(directory+file) as Texture2D
	push_error("HeroRig: no art for "+file)
	return null

func _build_layer(layer: String) -> void:
	if layer=="eyes":
		var center := Vector2(0,0)
		for socket in data["sockets"]:
			if socket["name"]=="eyes": center = Vector2(socket["position"][0],socket["position"][1])
		_add_quad("eyes","eyes.png",center,EYES_SIZE,"head",layer_priority("eyes"))
		return
	var side := "far" if layer.ends_with("_far") else "near"
	var id := layer.trim_suffix("_far").trim_suffix("_near")
	var part := part_info(id)
	if part.is_empty(): return
	var texture := _texture(id+".png")
	var canvas := Vector2(part["canvas_px"][0],part["canvas_px"][1])
	var scale_px := 1.0/float(data["master_px"])
	var joints := {}
	for joint in part["joints_px"]: joints[joint] = Vector2(part["joints_px"][joint][0],part["joints_px"][joint][1])
	var pivot_name: String = part["pivot"]
	var pivot_px: Vector2 = joints[pivot_name]
	var pivot: Vector2 = rest[sided(pivot_name,side)]
	var angle := 0.0
	if part["axis"]!=null:
		var direction: Vector2 = rest[sided(part["axis"][1],side)]-rest[sided(part["axis"][0],side)]
		# Limbs are painted hanging down: -y in hero units (Vector2.DOWN is +y).
		angle = direction.angle()-Vector2(0,-1).angle()
	# Bones and the painted row where weight passes from one to the next.
	var bend_bones: Array = []
	var bend_rows: Array = []
	if part.has("chain") and part["chain"].size()>=2:
		var chain: Array = part["chain"]
		bend_bones = [sided(chain[0],side),sided(chain[1],side)]
		bend_rows = [joints[chain[1]].y]
	elif part["bones"].size()==2:
		bend_bones = [part["bones"][0],part["bones"][1]]
		bend_rows = [joints[part["bones"][1]].y]
	else:
		bend_bones = [sided(part["bones"][0]+"_near",side) if bone_index.has(part["bones"][0]+"_near") else part["bones"][0]]
	var columns := 4 if bend_rows.size()>0 else 1
	var rows := 24 if bend_rows.size()>0 else 1
	var blend := canvas.x*bend_blend
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var depth := layer_priority(layer)*.0005
	for row in range(rows+1):
		var y := canvas.y*row/rows
		var lower := 0.0
		if bend_rows.size()>0: lower = smoothstep(bend_rows[0]-blend,bend_rows[0]+blend,y)
		for column in range(columns+1):
			var x := canvas.x*column/columns
			var local := Vector2(x-pivot_px.x,-(y-pivot_px.y))*scale_px
			var point := local.rotated(angle)+pivot
			vertices.append(Vector3(point.x,point.y,0)*HEIGHT+Vector3(0,0,depth))
			uvs.append(Vector2(x/canvas.x,y/canvas.y))
			if bend_bones.size()==2 and not use_helpers:
				bones.append_array(PackedInt32Array([bone_index[bend_bones[0]],bone_index[bend_bones[1]],0,0]))
				weights.append_array(PackedFloat32Array([1-lower,lower,0,0]))
			elif bend_bones.size()==2:
				var helper: int = bone_index[bend_bones[1]+"_mid"]
				if lower<.5:
					bones.append_array(PackedInt32Array([bone_index[bend_bones[0]],helper,0,0]))
					weights.append_array(PackedFloat32Array([1-2*lower,2*lower,0,0]))
				else:
					bones.append_array(PackedInt32Array([helper,bone_index[bend_bones[1]],0,0]))
					weights.append_array(PackedFloat32Array([2-2*lower,2*lower-1,0,0]))
			else:
				bones.append_array(PackedInt32Array([bone_index[bend_bones[0]],0,0,0]))
				weights.append_array(PackedFloat32Array([1,0,0,0]))
	_add_mesh(layer,vertices,uvs,bones,weights,columns,rows,texture,side=="far",layer_priority(layer))

func _add_quad(layer: String, file: String, center: Vector2, size: Vector2, bone: String, priority: int) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for row in range(2):
		for column in range(2):
			var point := center+Vector2((column-.5)*size.x,(.5-row)*size.y)
			vertices.append(Vector3(point.x,point.y,0)*HEIGHT+Vector3(0,0,priority*.0005))
			uvs.append(Vector2(column,row))
			bones.append_array(PackedInt32Array([bone_index[bone],0,0,0]))
			weights.append_array(PackedFloat32Array([1,0,0,0]))
	_add_mesh(layer,vertices,uvs,bones,weights,1,1,_texture(file),false,priority)

# Soft shadow where one part sits on another; it moves with the joint, so it
# is never baked into a pose.
func _add_joint_shadow(bone: String, size: Vector2, offset: Vector2) -> void:
	if not bone_index.has(bone): return
	_add_quad("joint_shadow_"+bone,"joint_shadow.png",rest[bone]+offset,size,bone,layer_priority("joint_shadows"))

func _add_mesh(layer: String, vertices: PackedVector3Array, uvs: PackedVector2Array, bones: PackedInt32Array, weights: PackedFloat32Array, columns: int, rows: int, texture: Texture2D, far: bool, priority: int) -> void:
	var indices := PackedInt32Array()
	for row in range(rows):
		for column in range(columns):
			var a := row*(columns+1)+column
			indices.append_array(PackedInt32Array([a,a+1,a+columns+1,a+1,a+columns+2,a+columns+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.name = layer
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = texture
	if far: material.albedo_color = FAR_TINT
	material.render_priority = priority
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(instance)
	instance.skin = skin
	instance.skeleton = NodePath("..")
	# Skinned vertices move outside the rest box; keep the part from culling.
	instance.custom_aabb = AABB(Vector3(-2,-2,-1),Vector3(4,4,2))
	parts[layer] = instance
	rest_vertices[layer] = vertices
	vertex_bones[layer] = bones
	vertex_weights[layer] = weights

# Bone angles in radians relative to the rest pose; bones left out return to rest.
func set_pose(angles: Dictionary) -> void:
	for bone in bone_index:
		var angle := float(angles.get(helpers[bone],0.0))*.5 if helpers.has(bone) else float(angles.get(bone,0.0))
		skeleton.set_bone_pose_rotation(bone_index[bone],Quaternion(Vector3.BACK,angle))
	skeleton.force_update_all_bone_transforms()

# Keeps the lower foot on the ground after a pose: bones only rotate, so a
# crouch or a step would otherwise lift the feet. Returns the drop in hero units.
func plant_feet() -> float:
	var lowest := INF
	for side in ["near","far"]:
		var foot: Vector3 = skeleton.get_bone_global_pose(bone_index["foot_"+side]).origin
		lowest = minf(lowest,foot.y)
	var drop: float = lowest-(rest["foot_near"] as Vector2).y*HEIGHT
	skeleton.position.y = FEET_Y-drop
	return drop

# The animation decides when an arm passes behind or in front of the body.
func set_layer(layer: String, in_front_of: String) -> void:
	if not parts.has(layer): return
	var material := parts[layer].material_override as StandardMaterial3D
	material.render_priority = layer_priority(in_front_of)+(1 if in_front_of!=layer else 0)

# The whole near arm (sleeve and glove) passes behind the head and in front of
# the torso, keeping the glove under its own sleeve cuff.
func arm_behind_head(side: String = "near") -> void:
	set_layer("sleeve_"+side,"torso")
	if parts.has("glove_"+side):
		set_layer("glove_"+side,"torso")
		(parts["sleeve_"+side].material_override as StandardMaterial3D).render_priority = priority("glove_"+side)+1
	if priority("sleeve_"+side)>=priority("head"): push_error("HeroRig: no layer room between torso and head")

func reset_layers() -> void:
	for layer in parts:
		var base := layer_priority("joint_shadows") if layer.begins_with("joint_shadow_") else layer_priority(layer)
		(parts[layer].material_override as StandardMaterial3D).render_priority = base

func priority(layer: String) -> int:
	return (parts[layer].material_override as StandardMaterial3D).render_priority

# Where the rope leaves the hand, in world space (replaces ExplorerSprite's grip).
func grip_position(side: String = "near") -> Vector3:
	var socket_position := Vector2.ZERO
	for socket in data["sockets"]:
		if socket["name"]=="grip_"+side: socket_position = Vector2(socket["position"][0],socket["position"][1])
	var hand := "hand_"+side
	var local: Vector2 = (socket_position-rest[hand])*HEIGHT
	var pose := skeleton.get_bone_global_pose(bone_index[hand])
	return skeleton.global_transform*(pose*Vector3(local.x,local.y,0))

# Vertices after skinning, in skeleton space: what the GPU draws. For tests.
func skinned_vertices(layer: String) -> PackedVector3Array:
	var result := PackedVector3Array()
	var vertices: PackedVector3Array = rest_vertices[layer]
	var bones: PackedInt32Array = vertex_bones[layer]
	var weights: PackedFloat32Array = vertex_weights[layer]
	for index in range(vertices.size()):
		var point := Vector3.ZERO
		for k in range(4):
			var weight := weights[index*4+k]
			if weight<=0: continue
			var bone := bones[index*4+k]
			var transform := skeleton.get_bone_global_pose(bone)*skin.get_bind_pose(bone)
			point += transform*vertices[index]*weight
		result.append(point)
	return result
