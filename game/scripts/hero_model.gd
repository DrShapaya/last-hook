class_name HeroModel
extends ExplorerRig

# The 3D hero (docs/CHARACTER_3D_PLAN.md, stages 5-6): the model from
# tools/blender/export_hero.py, posed on its skeleton by clips per HeroState
# state. Same interface as ExplorerSprite (animate, grip_position, hero),
# so ExplorerView can drive either.
#
# Light: the model carries its own shading (HERO_SHADER): warm key from the
# upper left, cool fill, rim and baked normals. The level's light is weak and
# cold (the painted hero is unshaded), and with the Compatibility renderer each
# extra light is another pass, so the hero lights itself in one pass.

const MODEL := "res://assets/hero/model/hero.glb"
# Drawn as large as the painted hero reads on screen (ExplorerSprite is
# painted bigger than the physics body); the rope still leaves from the hand.
const HEIGHT := 1.16
const FEET_Y := -.56
const STRIDE_PER_UNIT := 3.4 # As ExplorerSprite: one leg cycle per 2*PI/3.4 units walked.
const BLEND_SPEED := 14.0 # How fast the pose follows a new clip (1/s).
const TURN_SPEED := 20.0 # Turning around is quick: fewer frames mid-turn.
const ROPE_STATES := ["latch","swing","release","slip"]

const HERO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 key_dir = vec3(-.55, .65, .55);
uniform vec3 key_color : source_color = vec3(1.0, .93, .80);
uniform float key_energy = 1.05;
uniform vec3 fill_dir = vec3(.8, .1, .6);
uniform vec3 fill_color : source_color = vec3(.62, .72, .86);
uniform float fill_energy = .32;
uniform vec3 ambient : source_color = vec3(.42, .43, .46);
uniform vec3 rim_color : source_color = vec3(1.0, .86, .62);
uniform float rim_energy = .35;
uniform float tint_mix = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb;
	// Z rebuilt from X and Y: correct however the normal map is compressed.
	vec2 nxy = texture(normal_tex, UV).rg * 2.0 - 1.0;
	vec3 nm = vec3(nxy, sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
	vec3 n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * nm.z);
	vec3 key = normalize((VIEW_MATRIX * vec4(key_dir, 0.0)).xyz);
	vec3 fill = normalize((VIEW_MATRIX * vec4(fill_dir, 0.0)).xyz);
	float rough = texture(rough_tex, UV).r;
	// Wrapped diffuse: soft terminator like the reference renders.
	float k = clamp((dot(n, key) + .25) / 1.25, 0.0, 1.0);
	float f = clamp((dot(n, fill) + .4) / 1.4, 0.0, 1.0);
	vec3 h = normalize(key + VIEW);
	float gloss = mix(60.0, 6.0, rough);
	float spec = pow(max(dot(n, h), 0.0), gloss) * (1.0 - rough) * .45;
	float rim = pow(1.0 - max(dot(n, VIEW), 0.0), 3.0) * rim_energy;
	vec3 light = ambient + key_color * key_energy * k + fill_color * fill_energy * f;
	vec3 color = albedo * light + key_color * spec + rim_color * rim * albedo;
	ALBEDO = mix(color, color * tint, tint_mix);
}
"""

# Dark outline: the back faces of a slightly inflated shell, so the hero
# reads against grey rock like the outlined painted hero. One extra pass.
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float width = .0075;
uniform vec3 color : source_color = vec3(.10, .07, .05);
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = color;
}
"""

# ---------------------------------------------------------------- poses
# Bone angles in radians around the camera axis, counter-clockwise for a hero
# looking right: + raises an arm forward, + swings a leg forward, - folds a
# knee, + tilts the body back. Timings follow docs/character/MOTION_REFERENCE.md.

const STAND := {"upper_arm_near":.08,"forearm_near":.22,"hand_near":.05,"upper_arm_far":-.06,"forearm_far":.2,
	"thigh_near":.05,"shin_near":-.04,"thigh_far":-.05,"shin_far":-.04}
const BREATH := {"upper_arm_near":.11,"forearm_near":.25,"upper_arm_far":-.03,"forearm_far":.23,"chest":.02,"head":-.02,
	"thigh_near":.05,"shin_near":-.04,"thigh_far":-.05,"shin_far":-.04}
# Arm cocked up behind the head, the far arm pointing the way (set live in aim).
const AIM := {"upper_arm_near":2.75,"forearm_near":1.45,"hand_near":.3,"spine":.05,"chest":.1,"head":.06,
	"thigh_near":.18,"shin_near":-.12,"thigh_far":-.16,"shin_far":-.1}
const RELEASE := {"upper_arm_near":1.75,"forearm_near":.25,"hand_near":-.15,"spine":-.05,"chest":-.14,"head":-.05,
	"upper_arm_far":-.5,"forearm_far":.3,"thigh_near":.25,"shin_near":-.1,"thigh_far":-.2,"shin_far":-.15}
const FOLLOW := {"upper_arm_near":.9,"forearm_near":.12,"hand_near":-.25,"spine":-.08,"chest":-.22,"head":-.1,
	"upper_arm_far":-.7,"forearm_far":.35,"thigh_near":.25,"shin_near":-.12,"thigh_far":-.2,"shin_far":-.15}
const HANG := {"upper_arm_near":2.95,"forearm_near":.12,"hand_near":.05,"upper_arm_far":2.75,"forearm_far":.3,"hand_far":.1,
	"thigh_near":.2,"shin_near":-.35,"thigh_far":-.05,"shin_far":-.25,"head":.12}
const SWING_FORWARD := {"upper_arm_near":2.9,"forearm_near":.1,"upper_arm_far":2.7,"forearm_far":.25,
	"thigh_near":.85,"shin_near":-.15,"thigh_far":.65,"shin_far":-.25,"spine":.1,"head":.1}
const SWING_BACK := {"upper_arm_near":2.95,"forearm_near":.2,"upper_arm_far":2.75,"forearm_far":.35,
	"thigh_near":-.15,"shin_near":-1.0,"thigh_far":-.3,"shin_far":-1.2,"spine":-.08,"head":.16}
const OPEN := {"upper_arm_near":2.1,"forearm_near":.3,"upper_arm_far":1.6,"forearm_far":.5,
	"thigh_near":.3,"shin_near":-.4,"thigh_far":-.2,"shin_far":-.5,"head":.1}
const TUCK := {"upper_arm_near":.9,"forearm_near":1.6,"upper_arm_far":.7,"forearm_far":1.5,
	"thigh_near":1.3,"shin_near":-1.8,"thigh_far":1.15,"shin_far":-1.7,"foot_near":.4,"foot_far":.4,"spine":-.15,"head":.2}
const SPREAD_A := {"upper_arm_near":2.3,"forearm_near":.4,"upper_arm_far":-1.0,"forearm_far":.5,
	"thigh_near":.45,"shin_near":-.6,"thigh_far":-.35,"shin_far":-.7,"head":.15,"spine":.08}
const SPREAD_B := {"upper_arm_near":1.9,"forearm_near":.6,"upper_arm_far":-1.3,"forearm_far":.3,
	"thigh_near":.25,"shin_near":-.8,"thigh_far":-.15,"shin_far":-.5,"head":.1,"spine":.04}
const LAND := {"thigh_near":1.05,"shin_near":-1.7,"foot_near":.65,"thigh_far":.85,"shin_far":-1.5,"foot_far":.65,
	"spine":-.28,"chest":-.12,"head":.2,"upper_arm_near":.75,"forearm_near":.6,"upper_arm_far":.45,"forearm_far":.7}
const SLIP := {"upper_arm_near":3.3,"forearm_near":.3,"hand_near":-.4,"upper_arm_far":3.1,"forearm_far":.5,
	"thigh_near":.1,"shin_near":-.3,"thigh_far":-.1,"shin_far":-.4,"head":-.2,"spine":.12}
const CHEER_A := {"upper_arm_near":2.9,"forearm_near":.35,"hand_near":.2,"upper_arm_far":.1,"forearm_far":.3,"head":.18,"chest":.06,
	"thigh_near":.05,"thigh_far":-.05}
const CHEER_B := {"upper_arm_near":2.5,"forearm_near":.9,"hand_near":-.3,"upper_arm_far":.15,"forearm_far":.3,"head":.12,"chest":.04,
	"thigh_near":.05,"thigh_far":-.05}
const CROUCH := {"thigh_near":1.3,"shin_near":-2.0,"foot_near":.75,"thigh_far":1.1,"shin_far":-1.9,"foot_far":.75,
	"spine":-.35,"chest":-.15,"head":.25,"upper_arm_near":.9,"forearm_near":.9,"upper_arm_far":.6,"forearm_far":.9}

# Clip per HeroState state: [loops, [[time, pose], ...]]. walk, swing, aim and
# hook_flight are built live from the motion (see _target_pose).
const CLIPS := {
	"idle": [true,[[0.0,STAND],[1.8,BREATH],[3.6,STAND]]],
	"throw": [false,[[0.0,AIM],[.07,RELEASE],[.22,FOLLOW]]],
	"latch": [false,[[0.0,RELEASE],[.06,SLIP],[.18,HANG]]],
	"release": [false,[[0.0,HANG],[.2,OPEN]]],
	"rise": [true,[[0.0,TUCK],[1.0,TUCK]]],
	"fall": [true,[[0.0,SPREAD_A],[.4,SPREAD_B],[.8,SPREAD_A]]],
	"land": [false,[[0.0,LAND],[.12,LAND],[.38,STAND]]],
	"slip": [false,[[0.0,HANG],[.1,SLIP],[.35,SPREAD_A]]],
	"summit": [true,[[0.0,CHEER_A],[.3,CHEER_B],[.6,CHEER_A]]],
	"revive": [false,[[0.0,CROUCH],[.45,STAND],[.8,STAND]]],
}
const LIVE := ["walk","aim","hook_flight","swing"]

var model: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var shader_material: ShaderMaterial
var bone_index := {}
var bone_rest := {} # index -> Quaternion
var bone_axis := {} # index -> local axis of the camera direction
var hero := HeroState.new()
var flight_info: Dictionary = {}
var walk_speed := 2.6
var state := "idle"
var state_time := 0.0
var last_time := -1.0
var current := {} # bone -> applied angle
var turn := 0.0
var stride := 0.0
var lean := 0.0
var pack := 0.0
var impact := 0.0
var last_vertical_speed := 0.0
var previous_grounded := true
var forced_state := "" # Preview only: hold a state regardless of the motion.

func setup() -> void:
	if is_instance_valid(model): return
	name = "HeroModel"
	model = (load(MODEL) as PackedScene).instantiate()
	model.scale = Vector3.ONE*HEIGHT
	model.position.y = FEET_Y
	add_child(model)
	skeleton = _find(model,"Skeleton3D") as Skeleton3D
	mesh = _find(model,"MeshInstance3D") as MeshInstance3D
	for index in range(skeleton.get_bone_count()):
		bone_index[skeleton.get_bone_name(index)] = index
		bone_rest[index] = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		bone_axis[index] = (skeleton.get_bone_global_rest(index).basis.inverse()*Vector3(0,0,1)).normalized()
	var baked := mesh.mesh.surface_get_material(0) as BaseMaterial3D
	var shader := Shader.new()
	shader.code = HERO_SHADER
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("albedo_tex",baked.albedo_texture)
	shader_material.set_shader_parameter("normal_tex",baked.normal_texture)
	shader_material.set_shader_parameter("rough_tex",baked.roughness_texture)
	var outline_shader := Shader.new()
	outline_shader.code = OUTLINE_SHADER
	var outline := ShaderMaterial.new()
	outline.shader = outline_shader
	shader_material.next_pass = outline
	mesh.material_override = shader_material
	grip = Marker3D.new()
	add_child(grip)
	_apply(STAND)

static func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find(child,type)
		if found: return found
	return null

# ---------------------------------------------------------------- motion

func animate(sim: RopeSim, target: Vector2, tether: bool, time: float) -> void:
	var dt := clampf(time-last_time,0,.1) if last_time>=0 else 0.0
	last_time = time
	var direction := target-sim.pos
	var new_state := forced_state
	if new_state.is_empty():
		hero.update(dt,HeroState.observe(sim,tether,flight_info))
		new_state = hero.state
	if new_state!=state:
		state = new_state
		state_time = 0.0
	# On the rope the hero keeps the facing it caught with: the anchor passes
	# overhead every half swing, and following it turned the body around twice
	# a swing (a flat sprite hides that, a 3D body shows its back mid-turn).
	# Facing changes on the ground, while aiming or throwing, and in flight.
	if not state in ROPE_STATES:
		if tether and absf(direction.x)>1.0: facing = signf(direction.x)
		elif not tether and absf(sim.vel.x)>(.4 if sim.grounded and not sim.attached else 1.5): facing = signf(sim.vel.x)
	turn = lerpf(turn,0.0 if facing>0 else PI,1-exp(-dt*TURN_SPEED))
	rotation.y = turn
	state_time += dt
	if state=="walk": stride += absf(sim.vel.x)*dt*STRIDE_PER_UNIT
	elif sim.grounded:
		# Settle the gait to the nearest planted pose instead of freezing mid-step.
		stride = lerpf(stride,roundf(stride/PI)*PI,1-exp(-dt*8))
	# Touchdown squash grows with the fall speed (as ExplorerSprite).
	if sim.grounded and not previous_grounded: impact = lerpf(.03,.08,clampf(-last_vertical_speed/8.0,0,1))
	previous_grounded = sim.grounded
	last_vertical_speed = sim.vel.y
	impact *= exp(-dt*9)
	scale = Vector3(1+impact*.6,1-impact,1)
	var desired := _target_pose(sim,direction)
	var blend := 1-exp(-dt*BLEND_SPEED) if dt>0 else 1.0
	for bone in desired:
		current[bone] = lerpf(float(current.get(bone,0.0)),float(desired[bone]),blend)
	for bone in current.keys():
		if not desired.has(bone): current[bone] = lerpf(float(current[bone]),0.0,blend)
	# Secondary motion: the backpack lags the body, the heavy head nods.
	var desired_lean := clampf(-sim.vel.x*facing*.02,-.18,.18) if not sim.attached else 0.0
	# On the rope the body hangs along it: tilt toward the anchor. Lean is in
	# the hero's own frame (rotation.z is applied before the turn).
	if state=="swing": desired_lean = clampf((direction.angle()-PI*.5)*facing*.6,-.5,.5) if direction.length()>.1 else 0.0
	lean = lerpf(lean,desired_lean,1-exp(-dt*8))
	rotation.z = lean
	pack = lerpf(pack,clampf(sim.vel.x*facing*.03-sim.vel.y*.012,-.18,.18),1-exp(-dt*5))
	var applied := current.duplicate()
	applied["backpack"] = float(applied.get("backpack",0.0))+pack
	applied["head"] = float(applied.get("head",0.0))-pack*.25
	_apply(applied)
	grip.position = to_local(grip_position())

func _target_pose(sim: RopeSim, direction: Vector2) -> Dictionary:
	if state=="walk":
		return walk_pose(stride,clampf(absf(sim.vel.x)/maxf(.1,walk_speed),0,1))
	# Angle of the target above the horizon, in the hero's own facing.
	var aim := atan2(direction.y,absf(direction.x)) if direction.length()>.1 else .6
	match state:
		"aim":
			var pose := AIM.duplicate()
			pose["upper_arm_far"] = PI*.5+aim
			pose["forearm_far"] = .1
			return pose
		"hook_flight":
			var pose := FOLLOW.duplicate()
			pose["upper_arm_near"] = PI*.5+aim
			pose["forearm_near"] = .08
			pose["upper_arm_far"] = -.6
			return pose
		"swing":
			# Pendulum phase from the speed along the swing: legs thrown forward
			# when swinging forward, tucked on the way back.
			var forward := clampf(sim.vel.x*facing/5.0,-1,1)
			return blend_poses(SWING_BACK,SWING_FORWARD,forward*.5+.5)
	var clip: Array = CLIPS.get(state,CLIPS["idle"])
	return sample(clip[1],state_time,clip[0])

static func walk_pose(stride_phase: float, pace: float = 1.0) -> Dictionary:
	var swing := sin(stride_phase)
	var pose := {"spine":-.08*pace,"head":.04*pace,"chest":-.02}
	for side in ["near","far"]:
		var s := swing if side=="near" else -swing
		var lift := maxf(0.0,cos(stride_phase if side=="near" else stride_phase+PI))
		pose["thigh_"+side] = (.42*s+.02)*pace
		pose["shin_"+side] = (-.12-.8*lift)*pace
		pose["foot_"+side] = (.25*lift-.12*s)*pace
		pose["upper_arm_"+side] = (-.34*s)*pace+(.06 if side=="near" else -.04)
		pose["forearm_"+side] = .25+.2*maxf(0.0,s)*pace
	return pose

static func blend_poses(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var result := {}
	for bone in a.keys()+b.keys():
		result[bone] = lerpf(float(a.get(bone,0.0)),float(b.get(bone,0.0)),t)
	return result

static func sample(keys: Array, time: float, loop: bool) -> Dictionary:
	var length: float = keys[-1][0]
	time = fmod(time,length) if loop and length>0 else clampf(time,0,length)
	for index in range(keys.size()-1):
		var a: Array = keys[index]
		var b: Array = keys[index+1]
		if time<=b[0]:
			return blend_poses(a[1],b[1],smoothstep(0.0,1.0,(time-a[0])/maxf(.0001,b[0]-a[0])))
	return keys[-1][1]

func _apply(angles: Dictionary) -> void:
	for bone in bone_index:
		var index: int = bone_index[bone]
		skeleton.set_bone_pose_rotation(index,bone_rest[index]*Quaternion(bone_axis[index],float(angles.get(bone,0.0))))

# Where the rope leaves the near hand, in world space.
func grip_position() -> Vector3:
	if not is_instance_valid(skeleton): return global_position
	var hand: Transform3D = skeleton.get_bone_global_pose(bone_index["hand_near"])
	var tip := hand*Vector3(0,.06,0) # Along the hand bone, inside the fist.
	return skeleton.global_transform*tip

func hero_event(name_: String) -> void:
	hero.event(name_)
