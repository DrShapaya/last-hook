class_name WeatherOverlay
extends CanvasLayer

# The weather over the whole screen, one layer under the HUD: wind streaks,
# flying leaves / sand / snow, the storm and blizzard haze round the hero and
# frost on the edges. One ColorRect per effect, blending only (no screen
# texture), each hidden while its strength is ~0 so calm weather costs nothing.
# main.gd feeds it WeatherBands.presence at the hero every frame.

const AMOUNTS := {"battery":40,"balanced":90,"high":160,"ultra":160}
const REDUCED_AMOUNT := 40
const SAND := Color(.85,.68,.45)
const SNOW := Color(.9,.94,1.0)
# Sand storm: clear round the hero (longer than the rope), thick above.
const SAND_CLEAR := 6.5
const SAND_TOP := .9
const SAND_SIDE := .6
# Inside the clear circle only a light veil (grips in reach stay sharp).
const SAND_VEIL := .12
const BLIZZARD_VEIL := .2
const BLIZZARD_CLEAR := 7.0
# Weight of the racing sheets inside the haze.
const SAND_SHEETS := 1.0
const BLIZZARD_SHEETS := .8
const BLIZZARD_MAX := .45
# Haze per second: rising, settling after a storm, leaving the band.
const HAZE_RISE := 1.0/1.4
const HAZE_SETTLE := 1.0/2.8
const HAZE_LEAVE := 1.0/1.9
const BLIZZARD_LINES := .7
const PARTICLE_RATE := 2.5
const STREAK_RATE := 2.0
const SHAKE_MAX := .08
const HIDDEN := .005
const KINDS := ["wind","sand_storm","blizzard"]

const STREAK_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 size = vec2(540.0, 1170.0);
uniform float strength = 0.0;
uniform float direction = 1.0;
uniform float t = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
float hash(float n) { return fract(sin(n*12.9898)*43758.5453); }
void fragment() {
	vec2 p = UV*size;
	// Lanes slant a little downwind, like gusts running down the face.
	p.y -= p.x*.10*direction;
	float lane_h = 7.0;
	float lane = floor(p.y/lane_h);
	float r = hash(lane);
	float r2 = hash(lane+31.7);
	float across = abs(fract(p.y/lane_h)-.5)*lane_h;
	float line = 1.0-smoothstep(.35, .35+.9*r2+.4, across);
	float speed = 520.0+r*900.0;
	float len = 140.0+r2*320.0;
	float d = fract((p.x*direction-t*speed)/len+r*7.13);
	float dash = smoothstep(0.0, .18, d)*(1.0-smoothstep(.22, .62, d));
	float sparse = step(.58, hash(lane*1.7+floor((p.x*direction-t*speed)/len+r*7.13)*3.1));
	COLOR = vec4(tint.rgb, line*dash*sparse*strength*tint.a);
}
"""

const HAZE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 size = vec2(540.0, 1170.0);
uniform vec2 hero = vec2(270.0, 700.0);
uniform float px_per_m = 22.0;
uniform float clear_m = 6.5;
uniform float cap_top = .9;
uniform float cap_side = .6;
uniform float strength = 0.0;
uniform float direction = 1.0;
uniform float t = 0.0;
uniform float breath = 0.0;
uniform float streaks = 0.0;
// A light veil inside the clear circle: the storm is all round, grips stay sharp.
uniform float veil = 0.0;
uniform vec4 tint : source_color = vec4(.85, .68, .45, 1.0);
float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7)))*43758.5453); }
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1.0, 0.0)), f.x), mix(hash(i+vec2(0.0, 1.0)), hash(i+vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 p = UV*size;
	vec2 d = (p-hero)/px_per_m;
	float up = -d.y;
	float ring = smoothstep(clear_m, clear_m+2.5, length(d));
	float cap = mix(cap_side, cap_top, clamp(up/13.0, 0.0, 1.0));
	// Billows in metres, blown downwind.
	vec2 m = p/px_per_m;
	float n = noise(vec2(m.x*.25-direction*t*2.2, m.y*.4+t*.15));
	float n2 = noise(vec2(m.x*.6-direction*t*4.5, m.y*1.1));
	float billow = n*.65+n2*.35;
	float drift = .84+.12*billow+breath*.04*sin(t*1.1);
	// Gusting sheets: long thin lanes racing downwind over the whole frame.
	float lane = m.y*1.6+m.x*.12*direction;
	float sheet = smoothstep(.62, .95, noise(vec2(m.x*.12-direction*t*5.0, lane)))*streaks;
	// Never past the cap of this pixel: the veil inside the clear circle,
	// 0.6 beside/below, 0.9 high above (WeatherOverlay.haze_alpha mirrors it).
	float body = max(cap*ring*drift, veil);
	float alpha = min(body+sheet*(.16+.24*ring), max(cap*ring, veil))*strength;
	COLOR = vec4(tint.rgb*(.76+.44*billow)+sheet*.16, alpha);
}
"""

const FROST_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 size = vec2(540.0, 1170.0);
uniform float amount = 0.0;
uniform float breath = 0.0;
uniform float t = 0.0;
float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7)))*43758.5453); }
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1.0, 0.0)), f.x), mix(hash(i+vec2(0.0, 1.0)), hash(i+vec2(1.0, 1.0)), f.x), f.y);
}
float ridge(vec2 q) { return 1.0-abs(noise(q)*2.0-1.0); }
void fragment() {
	vec2 p = UV*size;
	float ex = min(p.x, size.x-p.x);
	float ey = min(p.y, size.y-p.y);
	float reach = amount*min(size.x, size.y)*.26*(1.0+breath*.04*sin(t*1.2));
	// Corners freeze further in than the middle of an edge.
	float edge = min(min(ex, ey), length(vec2(ex, ey))*.62);
	float rag = noise(p/38.0)*.6+noise(p/13.0)*.4;
	float depth = 1.0-edge/max(reach, 1.0)+(rag-.5)*.55;
	float frost = smoothstep(0.0, .45, depth);
	// Feathered needles, one slant per patch (no cross-hatch).
	vec2 a = vec2(p.x*.6+p.y*.35, p.y*.6-p.x*.35);
	vec2 b = vec2(p.x*.6-p.y*.35, p.y*.6+p.x*.35);
	float pick = smoothstep(.4, .6, noise(p/70.0));
	float needles = mix(pow(ridge(a*vec2(.03, .22)), 14.0), pow(ridge(b*vec2(.03, .22)), 14.0), pick);
	float glints = needles*smoothstep(-.3, .2, depth);
	float alpha = clamp(frost*(.38+.22*rag)+glints*.5, 0.0, .85)*step(.001, amount);
	COLOR = vec4(mix(vec3(.80, .89, .98), vec3(1.0), glints), alpha);
}
"""

static var _shaders := {}
static var _textures := {}

var streaks: ColorRect
var particles: GPUParticles2D
var haze: ColorRect
var frost: ColorRect
var _particle_material: ParticleProcessMaterial
var _amount := 90
var _reduce := false
var _configured := false
var _cfg_particles := ""
var _cfg_preset := ""
var _time := 0.0
var _haze := 0.0
var _haze_kind := ""
var _streak := 0.0
var _ratio := 0.0
var _particle_kind := ""
var _direction := 1.0
var _shake := 0.0
var _frost := 0.0
# Static shader inputs are written only when these change (raw values, no
# per-frame strings).
var _haze_set := false
var _haze_set_kind := ""
var _haze_set_reduce := false
var _haze_set_size := Vector2.ZERO
var _haze_set_direction := 0.0
var _streak_set_size := Vector2.ZERO
var _streak_set_direction := 0.0
var _frost_size := Vector2.ZERO
var _emitter_kind := ""
var _emitter_size := Vector2.ZERO
var _emitter_direction := 0.0
# Warm-up frames left: each effect is drawn once at strength 0 (and each
# particle kind emitted invisibly) so its shader compiles before the climb.
var _warm := 0

func _init() -> void:
	name = "Погода"
	# Right under the HUD (GameHud keeps the default layer).
	layer = 0
	haze = _rect("Мгла",HAZE_SHADER)
	streaks = _rect("Штрихи",STREAK_SHADER)
	particles = GPUParticles2D.new()
	particles.name = "Частицы"
	particles.visible = false
	particles.emitting = false
	particles.local_coords = false
	_particle_material = ParticleProcessMaterial.new()
	_particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_particle_material.particle_flag_disable_z = true
	particles.process_material = _particle_material
	add_child(particles)
	frost = _rect("Иней",FROST_SHADER)

func _rect(node_name: String, code: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	var material := ShaderMaterial.new()
	if not _shaders.has(node_name):
		var shader := Shader.new()
		shader.code = code
		_shaders[node_name] = shader
	material.shader = _shaders[node_name]
	rect.material = material
	add_child(rect)
	return rect

func configure(particle_setting: String, preset: String, reduce_effects: bool) -> void:
	if _configured and particle_setting==_cfg_particles and preset==_cfg_preset and reduce_effects==_reduce: return
	_configured = true
	_cfg_particles = particle_setting
	_cfg_preset = preset
	_reduce = reduce_effects
	var amount: int = AMOUNTS.get(preset,AMOUNTS["balanced"])
	if particle_setting=="reduced": amount = mini(amount,REDUCED_AMOUNT)
	elif particle_setting=="off": amount = 0
	if reduce_effects: amount = int(amount*.5)
	_amount = amount
	# A new amount restarts the system: only on a settings change.
	if _amount>0 and particles.amount!=_amount: particles.amount = _amount
	if _amount==0:
		particles.visible = false
		particles.emitting = false

# The haze shader's opacity at `offset` metres from the hero (y up), for a
# billow and sheet value (0..1, sheet already times the streak weight) and
# the breath term (-1..1, 0 with reduce_effects). Mirrors HAZE_SHADER.
static func haze_alpha(offset: Vector2, billow: float, sheet: float, breath: float, sand: bool, strength: float) -> float:
	var ring := smoothstep(SAND_CLEAR if sand else BLIZZARD_CLEAR,(SAND_CLEAR if sand else BLIZZARD_CLEAR)+2.5,offset.length())
	var cap := lerpf(SAND_SIDE if sand else 1.0,SAND_TOP if sand else 1.0,clampf(offset.y/13.0,0.0,1.0))
	var veil := SAND_VEIL if sand else BLIZZARD_VEIL
	var drift := .84+.12*billow+breath*.04
	var body := maxf(cap*ring*drift,veil)
	return minf(body+sheet*(.16+.24*ring),maxf(cap*ring,veil))*strength

func particle_amount() -> int:
	return _amount

func haze_strength() -> float:
	return _haze

# Camera offset size (metres) right now; 0 with reduce_effects.
func shake() -> float:
	return 0.0 if _reduce else _shake

# The camera's shake this frame: smooth, never accumulating, at most shake().
func shake_offset() -> Vector2:
	if _reduce or _shake<=0.0: return Vector2.ZERO
	var t := _time
	return Vector2(sin(t*23.0)*.45+sin(t*37.0+1.3)*.25,sin(t*29.0+.7)*.4+sin(t*43.0)*.3)*_shake

func update(presence: Dictionary, cold: float, hero_screen: Vector2, metres_per_pixel: float, delta: float) -> void:
	_time = fposmod(_time+delta,1000.0)
	var kind := str(presence.get("kind",""))
	var amount := clampf(float(presence.get("amount",0.0)),0.0,1.0)
	var phase: Dictionary = presence.get("phase",{})
	# Calm already carries the next gust's side: turn only once it shows.
	if kind!="" and amount>0.0: _direction = 1.0 if float(presence.get("direction",1.0))>=0.0 else -1.0
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(540,1170)
	# Haze: the storm's own target, eased in and out.
	var target := 0.0
	if kind=="sand_storm": target = amount
	elif kind=="blizzard": target = amount*BLIZZARD_MAX
	if target>0.0: _haze_kind = kind
	var rate := HAZE_RISE if target>_haze else HAZE_SETTLE if kind!="" else HAZE_LEAVE
	_haze = move_toward(_haze,target,rate*delta)
	if _haze<HIDDEN and target==0.0: _haze = 0.0
	_update_haze(size,hero_screen,metres_per_pixel)
	# Wind lines: the wind's own picture; a blizzard drives snow lines too,
	# since white haze alone hardly shows over snow.
	var lines := amount if kind=="wind" else amount*BLIZZARD_LINES if kind=="blizzard" else 0.0
	_streak = move_toward(_streak,lines,STREAK_RATE*delta)
	_update_streaks(size)
	_update_particles(kind,amount,size,delta)
	_frost = clampf(cold,0.0,1.0)
	_update_frost(size)
	# A small shake at the peaks of a wind or blizzard gust.
	var peak := 0.0
	if kind in ["wind","blizzard"] and str(phase.get("name",""))=="active":
		peak = smoothstep(.95,1.12,float(presence.get("strength",0.0)))*amount
	_shake = move_toward(_shake,SHAKE_MAX*peak,SHAKE_MAX*3.0*delta)
	if _warm>0: _warm_frame()

# Compiles the weather shaders ahead (run start): a few frames in which the
# rects are drawn at strength 0 and each particle kind emits at a tiny,
# fully transparent ratio. Real weather is never in play meanwhile.
func warm_up() -> void:
	_warm = KINDS.size()+1

func _warm_frame() -> void:
	_warm -= 1
	if _warm<=0:
		haze.visible = _haze>HIDDEN
		streaks.visible = _streak>HIDDEN
		frost.visible = _frost>.01
		particles.self_modulate.a = 1.0
		# Real weather may have taken the particles over meanwhile.
		if _ratio>HIDDEN: return
		particles.visible = false
		particles.emitting = false
		particles.amount_ratio = 1.0
		_particle_kind = ""
		_ratio = 0.0
		_emitter_kind = ""
		particles.restart()
		return
	for rect in [haze,streaks,frost]:
		if rect.visible: continue
		var material := rect.material as ShaderMaterial
		material.set_shader_parameter("amount" if rect==frost else "strength",0.0)
		rect.visible = true
	if _amount<=0 or _ratio>HIDDEN: return
	var kind: String = KINDS[_warm-1]
	_set_particle_kind(kind)
	particles.self_modulate.a = 0.0
	# At least one particle even with 20 or 40 of them.
	particles.amount_ratio = maxf(.01,1.5/_amount)
	particles.visible = true
	particles.emitting = true

func _update_haze(size: Vector2, hero_screen: Vector2, metres_per_pixel: float) -> void:
	haze.visible = _haze>HIDDEN
	if not haze.visible: return
	var material := haze.material as ShaderMaterial
	var sand := _haze_kind=="sand_storm"
	if not _haze_set or _haze_kind!=_haze_set_kind or _reduce!=_haze_set_reduce or size!=_haze_set_size or _direction!=_haze_set_direction:
		_haze_set = true
		_haze_set_kind = _haze_kind
		_haze_set_reduce = _reduce
		_haze_set_size = size
		_haze_set_direction = _direction
		material.set_shader_parameter("size",size)
		material.set_shader_parameter("clear_m",SAND_CLEAR if sand else BLIZZARD_CLEAR)
		material.set_shader_parameter("cap_top",SAND_TOP if sand else 1.0)
		material.set_shader_parameter("cap_side",SAND_SIDE if sand else 1.0)
		material.set_shader_parameter("tint",SAND if sand else SNOW)
		material.set_shader_parameter("streaks",SAND_SHEETS if sand else BLIZZARD_SHEETS)
		material.set_shader_parameter("veil",SAND_VEIL if sand else BLIZZARD_VEIL)
		material.set_shader_parameter("direction",_direction)
		material.set_shader_parameter("breath",0.0 if _reduce else 1.0)
	material.set_shader_parameter("hero",hero_screen)
	material.set_shader_parameter("px_per_m",1.0/maxf(metres_per_pixel,.0001))
	material.set_shader_parameter("strength",_haze)
	material.set_shader_parameter("t",_time)

func _update_streaks(size: Vector2) -> void:
	streaks.visible = _streak>HIDDEN
	if not streaks.visible: return
	var material := streaks.material as ShaderMaterial
	if size!=_streak_set_size or _direction!=_streak_set_direction:
		_streak_set_size = size
		_streak_set_direction = _direction
		material.set_shader_parameter("size",size)
		material.set_shader_parameter("direction",_direction)
	material.set_shader_parameter("strength",_streak*.55)
	material.set_shader_parameter("t",_time)

func _update_frost(size: Vector2) -> void:
	frost.visible = _frost>.01
	if not frost.visible: return
	var material := frost.material as ShaderMaterial
	if size!=_frost_size:
		_frost_size = size
		material.set_shader_parameter("size",size)
	material.set_shader_parameter("amount",_frost)
	# The edge breathes a little once it is very cold (never with reduce_effects).
	material.set_shader_parameter("breath",0.0 if _reduce else smoothstep(.7,.85,_frost))
	material.set_shader_parameter("t",_time)

func _update_particles(kind: String, amount: float, size: Vector2, delta: float) -> void:
	if _amount<=0:
		_ratio = 0.0
		return
	var target := amount if kind in KINDS else 0.0
	if kind in KINDS and kind!=_particle_kind:
		# The old kind fades out before the new one takes over.
		if _particle_kind=="" or _ratio<=HIDDEN: _set_particle_kind(kind)
		else: target = 0.0
	_ratio = move_toward(_ratio,target,PARTICLE_RATE*delta)
	var shown := _ratio>HIDDEN and _particle_kind!=""
	if shown!=particles.visible:
		particles.visible = shown
		particles.emitting = shown
	if not shown: return
	particles.amount_ratio = _ratio
	if _particle_kind!=_emitter_kind or size!=_emitter_size or _direction!=_emitter_direction:
		_emitter_kind = _particle_kind
		_emitter_size = size
		_emitter_direction = _direction
		_place_emitter(size)

# Particles live over the whole frame: the box reaches upwind by the way one
# flies in its life, so the screen is evenly full.
func _place_emitter(size: Vector2) -> void:
	var travel := _particle_material.initial_velocity_max*.75*particles.lifetime
	_particle_material.direction = Vector3(_direction,_particle_material.direction.y,0)
	_particle_material.emission_box_extents = Vector3(size.x*.5+travel*.5+20.0,size.y*.5+30.0,0)
	particles.position = Vector2(size.x*.5-_direction*travel*.5,size.y*.5)
	particles.visibility_rect = Rect2(-size.x-travel,-size.y,size.x*2.0+travel*2.0,size.y*2.0)

func _set_particle_kind(kind: String) -> void:
	_particle_kind = kind
	var m := _particle_material
	m.angular_velocity_min = 0.0
	m.angular_velocity_max = 0.0
	m.particle_flag_align_y = false
	match kind:
		"wind":
			particles.texture = _texture("leaf")
			particles.lifetime = 1.8
			m.direction = Vector3(_direction,.22,0)
			m.spread = 14.0
			m.initial_velocity_min = 300.0
			m.initial_velocity_max = 560.0
			m.gravity = Vector3(0,70,0)
			m.angular_velocity_min = -320.0
			m.angular_velocity_max = 320.0
			m.angle_min = 0.0
			m.angle_max = 360.0
			m.scale_min = 1.1
			m.scale_max = 2.0
			m.color_initial_ramp = _ramp([Color(.47,.62,.24),Color(.66,.70,.26),Color(.82,.58,.22)])
		"sand_storm":
			particles.texture = _texture("grain")
			particles.lifetime = .9
			m.direction = Vector3(_direction,.08,0)
			m.spread = 5.0
			m.initial_velocity_min = 900.0
			m.initial_velocity_max = 1500.0
			m.gravity = Vector3(0,40,0)
			m.particle_flag_align_y = true
			m.angle_min = 0.0
			m.angle_max = 0.0
			m.scale_min = 1.0
			m.scale_max = 2.0
			m.color_initial_ramp = _ramp([Color(1.0,.92,.74),Color(.62,.44,.26),Color(.98,.86,.62)])
		"blizzard":
			particles.texture = _texture("flake")
			particles.lifetime = 1.6
			m.particle_flag_align_y = true
			m.direction = Vector3(_direction,.45,0)
			m.spread = 18.0
			m.initial_velocity_min = 380.0
			m.initial_velocity_max = 760.0
			m.gravity = Vector3(0,60,0)
			m.angle_min = 0.0
			m.angle_max = 0.0
			m.scale_min = .8
			m.scale_max = 2.0
			m.color_initial_ramp = _ramp([Color(1,1,1),Color(.88,.93,1.0)])
	# Each fades in and out over its life, so nothing pops at the edges.
	m.color_ramp = _fade()

static func _ramp(colors: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var values := PackedColorArray()
	for i in range(colors.size()):
		offsets.append(float(i)/maxf(1.0,colors.size()-1.0))
		values.append(colors[i])
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = values
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 32
	return texture

static func _fade() -> GradientTexture1D:
	if _textures.has("fade"): return _textures["fade"]
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,.12,.8,1.0])
	gradient.colors = PackedColorArray([Color(1,1,1,0),Color(1,1,1,1),Color(1,1,1,1),Color(1,1,1,0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 32
	_textures["fade"] = texture
	return texture

# Small textures drawn once: a leaf, a grain streak, a soft flake.
static func _texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var dims := {"leaf":Vector2i(14,8),"grain":Vector2i(4,22),"flake":Vector2i(6,12)}[kind] as Vector2i
	var image := Image.create(dims.x,dims.y,false,Image.FORMAT_RGBA8)
	var center := Vector2(dims)*.5
	for y in range(dims.y):
		for x in range(dims.x):
			var q := (Vector2(x,y)+Vector2(.5,.5)-center)/center
			var alpha := 0.0
			match kind:
				"leaf":
					# A pointed leaf with a darker midrib.
					var body := 1.0-(q.x*q.x+q.y*q.y*(1.0+absf(q.x)*1.6))
					alpha = clampf(body*4.0,0.0,1.0)
					var rib := 1.0-clampf(absf(q.y)*6.0,0.0,1.0)
					image.set_pixel(x,y,Color(1.0-rib*.25,1.0-rib*.25,1.0-rib*.25,alpha))
					continue
				"grain":
					alpha = clampf((1.0-absf(q.x))*1.6,0.0,1.0)*clampf((1.0-absf(q.y))*1.4,0.0,1.0)
				"flake":
					alpha = clampf((1.0-q.length())*2.4,0.0,1.0)
			image.set_pixel(x,y,Color(1,1,1,clampf(alpha,0.0,1.0)))
	var texture := ImageTexture.create_from_image(image)
	_textures[kind] = texture
	return texture
