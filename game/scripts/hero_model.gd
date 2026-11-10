class_name HeroModel
extends ExplorerRig

# The 3D hero (docs/CHARACTER_3D_PLAN.md, stages 5-6): the model from
# tools/blender/export_hero.py, posed on its skeleton by clips per HeroState
# state. Same interface as ExplorerSprite (animate, grip_position, hero),
# so ExplorerView can drive either.
#
# One model everywhere (the owner, 2026-11-10: no simplified game model):
# tools/blender/export_showcase.py exports the detailed hero with every
# buckle, lace and tread as geometry, colour and occlusion in its vertices.
# The hero brings his own lights, which light only him (HERO_LAYER): the
# level's light is weak and cold. Shadows only in close-ups.

const MODEL := "res://assets/hero/model/hero.glb"
const HERO_LAYER := 1 << 19 # Render layer 20: the hero's own lights reach only him.
# Drawn as large as the painted hero reads on screen (ExplorerSprite is
# painted bigger than the physics body); the rope still leaves from the hand.
const HEIGHT := 1.16
const FEET_Y := -.56
# Gait phase per unit walked. A planted foot stays put when the body covers
# one step while the leg sweeps back: half a cycle (PI) per 2*L*sin(swing)
# units, with leg L = .41 and the hips swinging WALK_SWING either way:
# PI/(2*.41*sin(.7)) = 5.9. The game's walk is about two body heights per
# second, so this is a brisk trot; the painted hero's 3.4 made 3D feet skate.
const STRIDE_PER_UNIT := 5.9
const WALK_SWING := .7
const BLEND_SPEED := 14.0 # How fast the pose follows a new clip (1/s).
const TURN_SPEED := 20.0 # Turning around is quick: fewer frames mid-turn.
const ROPE_STATES := ["latch","swing","release","slip"]

const HERO_SHADER := """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
uniform vec3 slot_base[7];
uniform vec3 slot_target[7];
uniform float slot_window[7];
uniform float flash_code = 0.0;
uniform float flash = 0.0;
varying float slot_code;
varying float metal;
varying float rough;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void vertex() {
	// UV carries data: x = wardrobe slot code (+ 0.5 for metal), y = roughness
	// (glTF stores V flipped).
	// Import compresses UVs: 1.0 arrives as 0.9997, so decode with margins
	// (floor/fract of the raw value made fabric read as dark metal in patches).
	slot_code = floor(UV.x + .25);
	metal = step(.25, abs(UV.x - slot_code));
	rough = 1.0 - UV.y;
}
void fragment() {
	// Vertex colours arrive linear (glTF); this renderer shades in the space
	// colours are stored in (sRGB, like the textures and the wardrobe's colours).
	vec3 srgb = pow(max(COLOR.rgb, vec3(0.0)), vec3(1.0 / 2.2));
	int code = clamp(int(slot_code + .5), 0, 6);
	float window = slot_window[code];
	if (window > 0.0) {
		vec3 hsv = rgb2hsv(srgb);
		vec3 base = slot_base[code];
		vec3 target = slot_target[code];
		float dh = abs(fract(hsv.x - base.x + .5) - .5);
		float fabric = (1.0 - smoothstep(window * .6, window, dh)) * smoothstep(.08, .2, hsv.y);
		vec3 dyed = vec3(fract(target.x + hsv.x - base.x), clamp(hsv.y * target.y / max(base.y, .01), 0.0, 1.0),
			clamp(hsv.z * target.z / max(base.z, .01), 0.0, 1.0));
		srgb = mix(srgb, hsv2rgb(dyed), fabric);
	}
	if (flash > 0.0 && abs(slot_code - flash_code) < .5) srgb = mix(srgb, vec3(1.0, .95, .8), flash * .6);
	ALBEDO = srgb;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = .5;
	ROUGHNESS = clamp(rough, .3, 1.0);
	METALLIC = metal * .8;
}
"""

# Dark outline: the back faces of a slightly inflated shell, so the hero
# reads against grey rock like the outlined painted hero. One extra pass.
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
// Width on screen in pixels, the same near and far: a model-space shell grew
// thick in the character screen's close-ups and thin in the climb.
uniform float width_px = 1.5;
uniform vec3 color : source_color = vec3(.12, .085, .06);
void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (dot(dir, dir) > 1e-8) clip.xy += normalize(dir) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}
void fragment() {
	ALBEDO = color;
}
"""

# ---------------------------------------------------------------- poses
# Bone angles in radians around the camera axis, counter-clockwise for a hero
# looking right: + raises an arm forward, + swings a leg forward, - folds a
# knee, + tilts the body back. Timings follow docs/character/MOTION_REFERENCE.md.

const STAND := {"upper_arm_near":.03,"forearm_near":.08,"hand_near":.05,"upper_arm_far":-.06,"forearm_far":.08,
	"thigh_near":.05,"shin_near":-.04,"thigh_far":-.05,"shin_far":-.04}
const BREATH := {"upper_arm_near":.05,"forearm_near":.11,"upper_arm_far":-.03,"forearm_far":.11,"chest":.02,"head":-.02,
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
# Catch: the body jerks toward the anchor, the head lags, the legs swing on.
const REACH := {"upper_arm_near":2.5,"forearm_near":.1,"hand_near":.05,"upper_arm_far":1.2,"forearm_far":.5,
	"thigh_near":.25,"shin_near":-.3,"thigh_far":-.1,"shin_far":-.3,"spine":.05}
const JOLT := {"upper_arm_near":3.0,"forearm_near":.18,"hand_near":.1,"upper_arm_far":2.6,"forearm_far":.4,"hand_far":.1,
	"thigh_near":.55,"shin_near":-.65,"thigh_far":.3,"shin_far":-.55,"spine":.14,"chest":.06,"head":-.16}
const CHEER_A := {"upper_arm_near":2.9,"forearm_near":.35,"hand_near":.2,"upper_arm_far":2.2,"forearm_far":.5,"head":.18,"chest":.06,
	"thigh_near":.05,"thigh_far":-.05}
const CHEER_B := {"upper_arm_near":2.5,"forearm_near":.9,"hand_near":-.3,"upper_arm_far":2.6,"forearm_far":.2,"head":.12,"chest":.04,
	"thigh_near":.05,"thigh_far":-.05}
const CROUCH := {"thigh_near":1.3,"shin_near":-2.0,"foot_near":.75,"thigh_far":1.1,"shin_far":-1.9,"foot_far":.75,
	"spine":-.35,"chest":-.15,"head":.25,"upper_arm_near":.9,"forearm_near":.9,"upper_arm_far":.6,"forearm_far":.9}

# Clip per HeroState state: [loops, [[time, pose], ...]]. walk, swing, aim and
# hook_flight are built live from the motion (see _target_pose).
const CLIPS := {
	"idle": [true,[[0.0,STAND],[1.8,BREATH],[3.6,STAND]]],
	"throw": [false,[[0.0,AIM],[.07,RELEASE],[.22,FOLLOW]]],
	"latch": [false,[[0.0,REACH],[.06,JOLT],[.18,HANG]]],
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
var last_real := -1.0
var current := {} # bone -> applied angle
var turn := 0.0
var stride := 0.0
var lean := 0.0
var pack := 0.0
var impact := 0.0
var last_vertical_speed := 0.0
var previous_grounded := true
var forced_state := "" # Preview only: hold a state regardless of the motion.
# Head turn to the side (radians, + toward the hero's left); the character
# screen sets it, the climb leaves it at 0.
var look_yaw := 0.0
# Extra bone angles on top of the clip (the character screen's small actions).
var pose_offset := {}
const LOOK_SHARE := {"head":.7,"neck":.2,"chest":.15}

var lights: Array[DirectionalLight3D] = []

# close_up: the character screen (shadows, rim light); full: false on the
# battery setting (one light, no shadows).
func setup(close_up: bool = false, full: bool = true) -> void:
	if is_instance_valid(model): return
	name = "HeroModel"
	model = (load(MODEL) as PackedScene).instantiate()
	model.scale = Vector3.ONE*HEIGHT
	model.position.y = FEET_Y
	add_child(model)
	skeleton = _find(model,"Skeleton3D") as Skeleton3D
	mesh = _find(model,"MeshInstance3D") as MeshInstance3D
	mesh.layers = HERO_LAYER
	for index in range(skeleton.get_bone_count()):
		bone_index[skeleton.get_bone_name(index)] = index
		bone_rest[index] = skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		bone_axis[index] = (skeleton.get_bone_global_rest(index).basis.inverse()*Vector3(0,0,1)).normalized()
	var shader := Shader.new()
	shader.code = HERO_SHADER
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	# The climb keeps a thin outline: the small hero must read on grey rock.
	# Close-ups go without (lights and shadows carry the form, as in Blender).
	if not close_up:
		var outline_shader := Shader.new()
		outline_shader.code = OUTLINE_SHADER
		var outline := ShaderMaterial.new()
		outline.shader = outline_shader
		shader_material.next_pass = outline
	mesh.material_override = shader_material
	_add_lights(close_up,full)
	set_outfit(HeroOutfit.worn)
	grip = Marker3D.new()
	add_child(grip)
	_apply(STAND)

# The hero's own lights, as in the Blender renders: a warm key from the upper
# left (with soft shadows in close-ups: buckles, laces and straps cast them),
# a cool fill from the right, a rim from behind in close-ups. They stay put
# while the hero turns (top_level) and light only the hero (HERO_LAYER).
func _add_lights(close_up: bool, full: bool) -> void:
	# In the climb the level's sun adds to the key, so it is weaker there.
	var specs: Array
	if close_up:
		# The character screen turns the hero three-quarters to the viewer's
		# right (+X); the key comes from the side he faces, high and in front,
		# so the face and chest are lit (from the left they sat in shadow).
		specs = [[Vector3(-.5,-.62,-.6),Color(1.0,.9,.78),1.35 if full else 1.8,full]]
		if full:
			specs.append([Vector3(.85,-.2,-.5),Color(.7,.78,.92),.45,false]) # Fill from the left.
			specs.append([Vector3(.35,-.35,1.0),Color(1.0,.92,.8),.8,false]) # Rim from behind.
			specs.append([Vector3(-.15,-.1,-1.0),Color(1,1,1),.18,false]) # A soft front fill.
	else:
		specs = [[Vector3(.55,-.65,-.55),Color(1.0,.86,.68),1.6,false]]
		if full: specs.append([Vector3(-.8,-.15,-.6),Color(.62,.72,.9),.55,false])
	for spec in specs:
		var light := DirectionalLight3D.new()
		light.top_level = true
		light.light_cull_mask = HERO_LAYER
		light.light_color = spec[1]
		light.light_energy = spec[2]
		light.shadow_enabled = spec[3]
		if light.shadow_enabled:
			# Biased off the surface: curved fabric shadowed itself in dashes.
			light.shadow_bias = .08
			light.shadow_normal_bias = 4.0
			light.shadow_blur = 1.6
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			light.directional_shadow_max_distance = 8.0
		add_child(light)
		light.global_transform = Transform3D(Basis.looking_at(spec[0],Vector3.UP),Vector3.ZERO)
		lights.append(light)

# The close-up world's sky light (the climb has the level's own).
static func showcase_environment(parent: Node) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Neutral-warm: a blue fill turned the white and yellow parts grey.
	environment.ambient_light_color = Color(.62,.63,.66)
	environment.ambient_light_energy = .5
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	parent.add_child(world)

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
	# The result screen stops the game clock; the summit cheer keeps going.
	var now := Time.get_ticks_usec()/1000000.0
	if dt==0.0 and state=="summit" and last_real>=0: dt = clampf(now-last_real,0,.1)
	last_real = now
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
	# A running gait is already smooth; easing it again lags the 1.8 Hz step
	# and shrinks the stride, which makes the planted foot skate.
	if state=="walk" and state_time>.15: blend = 1.0
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
	# On the ground the upper body leans from the hips and the feet stay planted;
	# in the air and on the rope the whole body tilts.
	rotation.z = 0.0 if sim.grounded else lean
	pack = lerpf(pack,clampf(sim.vel.x*facing*.03-sim.vel.y*.012,-.18,.18),1-exp(-dt*5))
	var applied := current.duplicate()
	if sim.grounded: applied["spine"] = float(applied.get("spine",0.0))+lean
	applied["backpack"] = float(applied.get("backpack",0.0))+pack
	applied["head"] = float(applied.get("head",0.0))-pack*.25
	for bone in pose_offset: applied[bone] = float(applied.get(bone,0.0))+float(pose_offset[bone])
	_apply(applied)
	_plant_feet(sim.grounded,dt)
	grip.position = to_local(grip_position())

func _target_pose(sim: RopeSim, direction: Vector2) -> Dictionary:
	if state=="walk":
		# Full stride from a modest speed: shrinking the swing at low speed with
		# the same cadence would make the feet skate while slowing down.
		return walk_pose(stride,clampf(absf(sim.vel.x)/maxf(.1,walk_speed)*2.5,0,1))
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

# One gait cycle per TAU of stride. Each leg spends half the cycle planted,
# its thigh sweeping back at a constant rate (a sine sweep raced at mid-step
# and skated), and half swinging forward with the knee folded so the foot
# clears the ground. The sole stays level while planted. Arms swing against
# the legs.
static func walk_pose(stride_phase: float, pace: float = 1.0) -> Dictionary:
	var pose := {"spine":-.08*pace,"head":.04*pace,"chest":-.02}
	for side in ["near","far"]:
		var p := fposmod(stride_phase/TAU+(0.0 if side=="near" else .5),1.0)
		var thigh: float
		var shin: float
		var foot: float
		if p<.5:
			var u := p/.5
			thigh = WALK_SWING*(1-2*u)
			shin = -.1
			foot = -(thigh+shin)
		else:
			var u := (p-.5)/.5
			# Thigh forward first, then the knee straightens with the foot still
			# up, then the foot sets down: a late knee snap slapped the foot
			# forward along the ground.
			var bend := smoothstep(0.0,.3,u)*smoothstep(.92,.55,u)
			thigh = -WALK_SWING+2*WALK_SWING*smoothstep(0.0,.7,u)
			shin = -.1-1.15*bend
			foot = -(thigh+shin)*.6+.25*bend
		pose["thigh_"+side] = thigh*pace
		pose["shin_"+side] = shin*pace
		pose["foot_"+side] = foot*pace
		var swing := sin(TAU*p)
		pose["upper_arm_"+side] = -.34*swing*pace+(.06 if side=="near" else -.04)
		pose["forearm_"+side] = .25+.2*maxf(0.0,swing)*pace
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

var plant := 0.0
# On the ground the body drops so the lower foot stays on the ground: a swinging
# leg lifts the planted foot otherwise (stiff hips), and a crouch floats.
func _plant_feet(grounded: bool, dt: float) -> void:
	var target := 0.0
	if grounded:
		skeleton.force_update_all_bone_transforms()
		var lowest := INF
		for side in ["near","far"]:
			lowest = minf(lowest,skeleton.get_bone_global_pose(bone_index["foot_"+side]).origin.y)
		var rest_y := skeleton.get_bone_global_rest(bone_index["foot_near"]).origin.y
		target = (lowest-rest_y)*HEIGHT
	plant = target if dt<=0 or grounded else lerpf(plant,target,1-exp(-dt*12))
	model.position.y = FEET_Y-plant

func _apply(angles: Dictionary) -> void:
	for bone in bone_index:
		var index: int = bone_index[bone]
		var rotation_: Quaternion = bone_rest[index]*Quaternion(bone_axis[index],float(angles.get(bone,0.0)))
		# Looking around (the character screen): the head and a little of the
		# chest turn about the body's up axis, which the side-on clips never use.
		if look_yaw!=0.0 and bone in LOOK_SHARE:
			var up: Vector3 = (skeleton.get_bone_global_rest(index).basis.inverse()*Vector3.UP).normalized()
			rotation_ = rotation_*Quaternion(up,look_yaw*float(LOOK_SHARE[bone]))
		skeleton.set_bone_pose_rotation(index,rotation_)

# Where the rope leaves the near hand, in world space.
func grip_position() -> Vector3:
	if not is_instance_valid(skeleton): return global_position
	var hand: Transform3D = skeleton.get_bone_global_pose(bone_index["hand_near"])
	var tip := hand*Vector3(0,.06,0) # Along the hand bone, inside the fist.
	return skeleton.global_transform*tip

# Recolours the wardrobe slots (HeroOutfit ids per slot).
func set_outfit(outfit: Dictionary) -> void:
	var values := HeroOutfit.shader_values(outfit)
	shader_material.set_shader_parameter("slot_base",values["base"])
	shader_material.set_shader_parameter("slot_target",values["target"])
	shader_material.set_shader_parameter("slot_window",values["window"])

func hero_event(name_: String) -> void:
	hero.event(name_)
