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
const DETAIL := "res://assets/hero/model/hero_detail.png"
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
// Tiling surface detail (tools/blender/make_detail_maps.py): R woven nylon,
// G twill, B leather grain, A suede, laid on the detail UV (hero units).
uniform sampler2D detail_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_tile = .05;
uniform float detail_depth = 1.0; // Relief strength; the climb's small hero needs less.
// Close-ups: a rim of light round the silhouette from one side (view space),
// so the hero stands off the painted background whichever way he turns.
uniform vec3 rim_color = vec3(0.0);
uniform vec3 rim_side = vec3(-.6, .55, 0.0);
uniform float rim_power = 3.0;
varying float slot_code;
varying float kind;
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
	// UV2 carries data (tools/blender/export_showcase.py): x = wardrobe slot
	// code + .05 + material kind / 10, y = roughness (glTF stores V flipped).
	// Import compresses UVs a little, so decode with margins.
	slot_code = floor(UV2.x + .02);
	kind = floor((UV2.x - slot_code) * 10.0 + .02);
	rough = 1.0 - UV2.y;
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
	// Detail per material kind: 1 nylon, 2 twill, 3 leather, 4 suede,
	// 5 rubber, 6 paint, 7 metal, 8 felt (0 plain).
	int k = int(kind + .5);
	vec4 pick = vec4(float(k == 1 || k == 8), float(k == 2), float(k == 3 || k == 5 || k == 6), float(k == 4));
	float scale = k == 6 ? 3.0 : (k == 8 ? 1.6 : (k == 5 ? .7 : 1.0));
	float amount = k == 6 ? .25 : (k == 5 ? .5 : (k == 4 ? .7 : (k == 2 ? .7 : (k == 0 || k == 7 ? 0.0 : 1.0))));
	float h = dot(texture(detail_map, UV / (detail_tile * scale)), pick);
	float relief = amount * detail_depth;
	// Bump from the height's screen derivatives (no tangents needed).
	vec3 n = normalize(NORMAL);
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec3 r1 = cross(dp2, n);
	vec3 r2 = cross(n, dp1);
	float det = dot(dp1, r1);
	float hs = h * .0007 * relief;
	vec3 grad = sign(det) * (dFdx(hs) * r1 + dFdy(hs) * r2);
	NORMAL = normalize(abs(det) * n - grad);
	// Weave hollows and grain cracks a little darker; raised threads catch light.
	srgb *= mix(1.0, .84 + .3 * h, relief * .4);
	ALBEDO = srgb;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = .5;
	ROUGHNESS = clamp(rough + (.5 - h) * .12 * relief, .3, 1.0);
	METALLIC = k == 7 ? .8 : 0.0;
	if (rim_color != vec3(0.0)) {
		float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float side = clamp(dot(NORMAL, normalize(rim_side)) * .7 + .3, 0.0, 1.0);
		EMISSION = rim_color * pow(facing, rim_power) * side * (.3 + .7 * srgb) * COLOR.a;
	}
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

# Wind-up before the throw: the arm cocked deeper, the body leaning back.
const WIND := {"upper_arm_near":3.05,"forearm_near":1.75,"hand_near":.45,"spine":.1,"chest":.18,"head":.1,
	"upper_arm_far":.6,"forearm_far":.6,"thigh_near":.22,"shin_near":-.18,"thigh_far":-.2,"shin_far":-.14}
# Let go of the rope: legs kick forward, arms open up.
const KICK := {"upper_arm_near":2.5,"forearm_near":.2,"upper_arm_far":2.1,"forearm_far":.35,
	"thigh_near":.7,"shin_near":-.25,"thigh_far":.45,"shin_far":-.35,"spine":.1,"head":.08}
const LAND_TOUCH := {"thigh_near":.45,"shin_near":-.6,"foot_near":.2,"thigh_far":.35,"shin_far":-.55,"foot_far":.2,
	"spine":-.08,"upper_arm_near":.6,"forearm_near":.4,"upper_arm_far":.4,"forearm_far":.5}
const STAND_TALL := {"upper_arm_near":.0,"forearm_near":.05,"upper_arm_far":-.08,"forearm_far":.05,"spine":.04,"head":-.04,
	"thigh_near":.04,"shin_near":-.02,"thigh_far":-.04,"shin_far":-.02}

# Clip per HeroState state: [loops, [[time, pose, ease], ...]]; the ease
# shapes the way into that key: "io" in and out, "out" a snap that settles,
# "in" a slow start, "back" an overshoot (follow-through). walk, aim, swing,
# hook_flight, rise and fall are built live from the motion (_target_pose).
const CLIPS := {
	"idle": [true,[[0.0,STAND],[1.8,BREATH],[3.6,STAND]]],
	# Wind-up, a snap through the release, then the arm follows through past
	# the target and settles.
	"throw": [false,[[0.0,AIM],[.05,WIND,"out"],[.1,RELEASE,"out"],[.22,FOLLOW,"back"]]],
	# Reach, the rope's jolt, then hanging with an overshoot.
	"latch": [false,[[0.0,REACH],[.05,JOLT,"out"],[.2,HANG,"back"]]],
	"release": [false,[[0.0,HANG],[.08,KICK,"out"],[.2,OPEN,"io"]]],
	"rise": [true,[[0.0,TUCK],[1.0,TUCK]]],
	"fall": [true,[[0.0,SPREAD_A],[.4,SPREAD_B],[.8,SPREAD_A]]],
	# Touch, sink into the squat, then rise past standing and settle.
	"land": [false,[[0.0,LAND_TOUCH],[.07,LAND,"out"],[.16,LAND],[.34,STAND_TALL,"io"],[.5,STAND,"io"]]],
	"slip": [false,[[0.0,HANG],[.1,SLIP,"out"],[.35,SPREAD_A,"io"]]],
	"summit": [true,[[0.0,CHEER_A],[.3,CHEER_B,"back"],[.6,CHEER_A,"back"]]],
	"revive": [false,[[0.0,CROUCH],[.38,STAND_TALL,"out"],[.6,STAND,"io"],[.8,STAND]]],
}
const LIVE := ["walk","aim","hook_flight","swing","rise","fall"]

# Each bone follows its pose through a damped spring: [frequency (rad/s),
# damping]. Heavy, loose parts (the head, the pack, hands and forearms) are
# slower and less damped, so they lag and overshoot: overlap and follow-through.
const SPRINGS := {"spine":[17.0,.85],"chest":[15.0,.8],"neck":[13.0,.75],"head":[10.0,.6],"backpack":[16.0,.85],
	"upper_arm_near":[16.0,.78],"upper_arm_far":[15.0,.78],"forearm_near":[14.0,.65],"forearm_far":[13.0,.65],
	"hand_near":[12.0,.6],"hand_far":[12.0,.6],"thigh_near":[15.0,.8],"thigh_far":[15.0,.8],
	"shin_near":[14.0,.72],"shin_far":[14.0,.72],"foot_near":[13.0,.75],"foot_far":[13.0,.75]}
const SPRING_DEFAULT := [14.0,.8]

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
var jolt := 0.0
var accel := Vector2.ZERO
var last_velocity := Vector2.ZERO
var spring_velocity := {}
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
	shader_material = ShaderMaterial.new()
	shader_material.shader = ShaderBank.of(HERO_SHADER)
	shader_material.set_shader_parameter("detail_map",load(DETAIL))
	# The small climbing hero shows the weave only as a texture, not relief.
	shader_material.set_shader_parameter("detail_depth",1.0 if close_up else .5)
	# The climb keeps a thin outline: the small hero must read on grey rock.
	# Close-ups go without (lights and shadows carry the form, as in Blender).
	if not close_up:
		var outline := ShaderMaterial.new()
		outline.shader = ShaderBank.of(OUTLINE_SHADER)
		shader_material.next_pass = outline
	mesh.material_override = shader_material
	_add_lights(close_up,full)
	set_outfit(HeroOutfit.worn)
	grip = Marker3D.new()
	add_child(grip)
	_apply(STAND)

# The hero's own lights. They stay put while the hero turns (top_level) and
# light only the hero (HERO_LAYER).
#
# Close-ups (the character screen) get a studio setup tuned to its camera,
# which looks from the front and a little to the right (+X): a warm key high
# on the camera's right with soft shadows, a cool fill low on the left that
# keeps the shadow side readable (the face is never black, whichever way he
# turns), a strong back light for a bright edge, and in the shader a rim of
# sky light round the silhouette that separates him from the painting. Kept
# below clipping: the white "Пурга" jacket and the yellow head stay
# coloured, not burnt white.
func _add_lights(close_up: bool, full: bool) -> void:
	# In the climb the level's sun adds to the key, so it is weaker there.
	var specs: Array
	if close_up:
		specs = [[Vector3(-.78,-.55,-.34),Color(1.0,.95,.88),1.4 if full else 1.6,full]] # Key, from the right side.
		if full:
			specs.append([Vector3(.85,-.1,-.5),Color(.72,.8,.95),.4,false]) # Fill from the left.
			specs.append([Vector3(.45,-.4,1.0),Color(1.0,.9,.74),1.25,false]) # Back light: the bright edge.
			specs.append([Vector3(-.1,.2,-1.0),Color(.95,.95,1.0),.1,false]) # Low front fill: under the head.
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
			# A small, tight shadow box round the hero (sharp map), softened by
			# blur; a light bias so straps, the head and the arms cast shadows
			# without the curved cloth shadowing itself in dashes.
			light.shadow_bias = .03
			light.shadow_normal_bias = 1.2
			light.shadow_blur = 2.2
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			light.directional_shadow_max_distance = 6.5
		add_child(light)
		light.global_transform = Transform3D(Basis.looking_at(spec[0],Vector3.UP),Vector3.ZERO)
		lights.append(light)
	if close_up and full:
		shader_material.set_shader_parameter("rim_color",Color(.55,.62,.75))
		shader_material.set_shader_parameter("rim_power",2.6)

# The close-up world's sky light (the climb has the level's own).
static func showcase_environment(parent: Node) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Neutral-warm: a blue fill turned the white and yellow parts grey.
	environment.ambient_light_color = Color(.64,.65,.68)
	environment.ambient_light_energy = .46
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
	# A throw from the rope: the hero still hangs from the old anchor, so the
	# hook's own flight tells which way he throws.
	var toward := direction
	var bolt: Vector2 = flight_info.get("velocity",Vector2.ZERO)
	if state in ["throw","hook_flight"] and bolt.length_squared()>.01 and not bool(flight_info.get("returning",false)):
		toward = bolt.normalized()*maxf(direction.length(),1.0)
	facing = facing_for(state,facing,sim.pos,sim.vel,toward,tether,sim.grounded,sim.attached)
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
	# The rope's jolt on a catch stretches the body along it for a moment.
	if state=="latch" and state_time<=dt+.0001: jolt = 1.0
	jolt *= exp(-dt*11)
	# Fast flight stretches him a little along the way he flies.
	var stretch := clampf((sim.vel.length()-5.0)/8.0,0,1)*.045 if not sim.grounded and not sim.attached else 0.0
	scale = Vector3(1+impact*.6-jolt*.035-stretch*.5,1-impact+jolt*.06+stretch,1)
	# Inertia: how the body is being pushed (smoothed), in the hero's own
	# frame. The head, chest and the pack lag behind it.
	if dt>0:
		var raw := ((sim.vel-last_velocity)/dt).limit_length(60.0)
		accel = accel.lerp(raw,1-exp(-dt*18))
	last_velocity = sim.vel
	var push := Vector2(accel.x*facing,accel.y)
	var desired := _target_pose(sim,direction)
	desired["head"] = float(desired.get("head",0.0))+clampf(push.x*.012-push.y*.004,-.3,.3)
	desired["chest"] = float(desired.get("chest",0.0))+clampf(push.x*.004,-.12,.12)
	# The pack sits on the back under its straps: it only rocks a little
	# about where the straps hold it (a looser swing lifted it off the back).
	desired["backpack"] = float(desired.get("backpack",0.0))+clampf(sim.vel.x*facing*.008-sim.vel.y*.004+push.x*.003+push.y*.002,-.07,.07)
	# Each bone follows its pose through its spring (overlap and follow-
	# through). A running gait is already smooth: easing the legs again lags
	# the step and shrinks the stride, so the feet would skate.
	var direct := state=="walk" and state_time>.15
	for bone in desired.keys()+current.keys():
		var goal := float(desired.get(bone,0.0))
		var x := float(current.get(bone,goal))
		var v := float(spring_velocity.get(bone,0.0))
		if dt<=0 or (direct and not bone in ["head","chest","backpack","neck"]):
			x = goal
			v = 0.0
		else:
			var spec: Array = SPRINGS.get(bone,SPRING_DEFAULT)
			var omega: float = spec[0]
			var zeta: float = spec[1]
			var steps := maxi(1,ceili(dt/(1.0/120)))
			var h := dt/steps
			for i in range(steps):
				v += (omega*omega*(goal-x)-2*zeta*omega*v)*h
				x += v*h
		current[bone] = x
		spring_velocity[bone] = v
	var desired_lean := clampf(-sim.vel.x*facing*.02,-.18,.18) if not sim.attached else 0.0
	# On the rope the body hangs along it, toward the anchor. Lean is in the
	# hero's own frame (rotation.z is applied before the turn).
	if state in ["swing","latch"]: desired_lean = clampf((direction.angle()-PI*.5)*facing*.85,-.9,.9) if direction.length()>.1 else 0.0
	# Flying, the body tips along the flight.
	elif not sim.grounded and not sim.attached and sim.vel.length()>2.0:
		desired_lean = clampf(-sim.vel.x*facing*.04,-.35,.35)
	lean = lerpf(lean,desired_lean,1-exp(-dt*7))
	# On the ground the upper body leans from the hips and the feet stay planted;
	# in the air and on the rope the whole body tilts.
	rotation.z = 0.0 if sim.grounded else lean
	var applied := current.duplicate()
	if sim.grounded: applied["spine"] = float(applied.get("spine",0.0))+lean
	for bone in pose_offset: applied[bone] = float(applied.get(bone,0.0))+float(pose_offset[bone])
	_apply(applied)
	_plant_feet(sim.grounded,dt)
	grip.position = to_local(grip_position())

# Which way the hero faces (+1 right, -1 left), from the state and the motion.
# `toward` points from the hero to what he is after: the aim, the flying hook
# or the anchor he hangs from. The hero looks where he is going through a
# whole throw: aiming and throwing toward the aim, watching the hook fly, on
# a catch toward the new anchor, through the swing as he caught, and in the air
# the way he flies. The rope used to keep the facing from before the throw:
# he flew left facing right after a throw to the left.
const AIM_TURN := .25 # Share of the aim that must point sideways to turn.
const SWING_TRAVEL := 2.2 # Horizontal speed above which the travel decides a catch.
const AIR_TURN := .8
static func facing_for(state_: String, current: float, _pos: Vector2, vel: Vector2, toward: Vector2, tether: bool,
		grounded: bool, attached: bool) -> float:
	match state_:
		"aim","throw":
			if toward.length()>.01 and absf(toward.normalized().x)>AIM_TURN: return signf(toward.x)
			return current
		"hook_flight":
			if absf(toward.x)>.3: return signf(toward.x)
			if absf(vel.x)>AIR_TURN: return signf(vel.x)
			return current
		"latch":
			if absf(toward.x)>.6: return signf(toward.x)
			if absf(vel.x)>SWING_TRAVEL: return signf(vel.x)
			return current
	if attached:
		# A swing keeps the facing of the catch: the anchor passes overhead
		# every half swing, and turning with it showed his back twice a swing.
		return current
	if grounded:
		if absf(vel.x)>.4: return signf(vel.x)
		if tether and absf(toward.x)>1.0: return signf(toward.x)
		return current
	if absf(vel.x)>AIR_TURN: return signf(vel.x)
	return current

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
		"swing": return swing_pose(sim,direction,facing,hero.reel_speed,state_time)
		"rise","fall": return air_pose(sim.vel,state_time)
	var clip: Array = CLIPS.get(state,CLIPS["idle"])
	var pose := sample(clip[1],state_time,clip[0])
	if state=="idle": pose = idle_life(pose,state_time)
	return pose

# The swing follows the pendulum. Swinging forward the legs kick out ahead
# (the pump), swinging back they fold under; at the slow ends of a swing the
# body gathers itself (knees in, arms pull) before the next sweep, and at the
# bottom, where the rope pulls hardest, it hangs long. The head looks the
# way he travels. Reeling in, the hands climb the rope one over the other.
static func swing_pose(sim: RopeSim, _toward: Vector2, facing_: float, reel: float, t: float) -> Dictionary:
	var forward := clampf(sim.vel.x*facing_/4.5,-1,1)
	var speed := clampf(sim.vel.length()/5.0,0,1)
	var pose := blend_poses(SWING_BACK,SWING_FORWARD,smoothstep(-1.0,1.0,forward))
	# Gathering at the ends (slow), long at the bottom (fast).
	var gather := 1.0-speed
	for side in ["near","far"]:
		pose["shin_"+side] = float(pose.get("shin_"+side,0.0))-.35*gather
		pose["thigh_"+side] = float(pose.get("thigh_"+side,0.0))+.2*gather
		pose["forearm_"+side] = float(pose.get("forearm_"+side,0.0))+.35*gather
	pose["spine"] = float(pose.get("spine",0.0))+.12*forward
	pose["head"] = float(pose.get("head",0.0))+.14*forward-.06*gather
	if reel>.3:
		# Hand over hand up the rope, the legs drawn up.
		var climb := sin(t*9.0)
		var pull := clampf(reel/2.0,0,1)
		pose["upper_arm_near"] = lerpf(float(pose["upper_arm_near"]),2.6+.45*climb,pull)
		pose["upper_arm_far"] = lerpf(float(pose["upper_arm_far"]),2.6-.45*climb,pull)
		pose["forearm_near"] = lerpf(float(pose["forearm_near"]),.7-.6*climb,pull)
		pose["forearm_far"] = lerpf(float(pose["forearm_far"]),.7+.6*climb,pull)
		pose["thigh_near"] = lerpf(float(pose["thigh_near"]),.75+.2*climb,pull)
		pose["thigh_far"] = lerpf(float(pose["thigh_far"]),.6-.2*climb,pull)
		pose["shin_near"] = lerpf(float(pose["shin_near"]),-1.0,pull)
		pose["shin_far"] = lerpf(float(pose["shin_far"]),-.9,pull)
	return pose

# In the air the pose follows the vertical speed: tucked while flying up,
# open at the top, spread and reaching while falling, with the arms and legs
# never quite still.
static func air_pose(vel: Vector2, t: float) -> Dictionary:
	var up := clampf(vel.y/5.0,0,1)
	var down := clampf(-vel.y/7.0,0,1)
	var pose := blend_poses(OPEN,TUCK,smoothstep(0.0,1.0,up))
	if down>0:
		var spread := blend_poses(SPREAD_A,SPREAD_B,.5+.5*sin(t*TAU/.8))
		pose = blend_poses(pose,spread,smoothstep(0.0,1.0,down))
	var flail := .08+.1*down
	pose["upper_arm_near"] = float(pose.get("upper_arm_near",0.0))+flail*sin(t*7.3)
	pose["upper_arm_far"] = float(pose.get("upper_arm_far",0.0))+flail*sin(t*6.1+1.7)
	pose["thigh_near"] = float(pose.get("thigh_near",0.0))+flail*.7*sin(t*5.2+.6)
	pose["thigh_far"] = float(pose.get("thigh_far",0.0))+flail*.7*sin(t*4.7+2.3)
	return pose

# Standing still is never frozen: the weight shifts from foot to foot and the
# head looks about now and then.
static func idle_life(pose: Dictionary, t: float) -> Dictionary:
	var sway := sin(t*TAU/4.3)
	var look := sin(t*TAU/7.1)*smoothstep(.3,.9,absf(sin(t*TAU/14.2)))
	pose = pose.duplicate()
	pose["thigh_near"] = float(pose.get("thigh_near",0.0))+.035*sway
	pose["thigh_far"] = float(pose.get("thigh_far",0.0))+.035*sway
	pose["spine"] = float(pose.get("spine",0.0))-.03*sway
	pose["head"] = float(pose.get("head",0.0))+.05*look
	pose["upper_arm_near"] = float(pose.get("upper_arm_near",0.0))+.03*sway
	pose["upper_arm_far"] = float(pose.get("upper_arm_far",0.0))-.03*sway
	return pose

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
			var u := clampf((time-a[0])/maxf(.0001,b[0]-a[0]),0,1)
			return blend_poses(a[1],b[1],ease_key(u,str(b[2]) if b.size()>2 else "io"))
	return keys[-1][1]

static func ease_key(u: float, kind: String) -> float:
	match kind:
		"out": return 1.0-pow(1.0-u,3.0)
		"in": return u*u*u
		"back":
			var c := 1.7
			return 1.0+(c+1.0)*pow(u-1.0,3.0)+c*pow(u-1.0,2.0)
	return smoothstep(0.0,1.0,u)

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
	# The jacket's hem bones (tools/blender/export_hero.py): the front follows
	# a thigh swinging forward, the back a thigh swinging back.
	angles = angles.duplicate()
	for side in ["near","far"]:
		var thigh := float(angles.get("thigh_"+side,0.0))
		angles["hem_fwd_"+side] = maxf(thigh,0.0)
		angles["hem_back_"+side] = minf(thigh,0.0)
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
