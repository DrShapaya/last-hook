class_name CharacterScreen
extends MenuSurface

# The character screen (docs/CHARACTER_PLAN.md, "Красота меню персонажа";
# docs/CHARACTER_3D_PLAN.md). The 3D hero stands on a ledge of the chosen
# location in front of its painting: he breathes, looks around, turns under
# a finger and answers a tap. The wardrobe below: a tab per slot, its colours
# as cards, try-on before buying, buying with gold (HeroOutfit). Opened from
# the lobby's character button.

signal closed

# Camera framings: [look-at point, distance]. The slots zoom in on their part.
const FRAMES := {
	"full":[Vector3(0,.6,0),4.5],
	"head":[Vector3(0,1.0,0),1.8],
	"jacket":[Vector3(0,.78,0),2.1],
	"backpack":[Vector3(0,.7,0),2.9],
	"pants":[Vector3(0,.38,0),2.1],
	"boots":[Vector3(0,.22,0),2.1],
	"gloves":[Vector3(0,.5,0),2.2],
}
# Body turn for the slot: the backpack shows from behind.
const SLOT_YAW := {"backpack":.5}
const REST_YAW := -.72 # Three-quarters toward the viewer.
const FRONT_YAW := -PI*.5
# The short action that shows a part just put on lasts this long (s).
const ACT_LENGTH := 1.0
# Top of the ledge per location: moss, sand, snow; and the rock under it.
const LEDGE_TOPS := [Color("6f9a4c"),Color("d9b07a"),Color("eef3f8")]
const LEDGE_ROCK := [Color("8d8a80"),Color("b8774f"),Color("8f9bb0")]

const LEDGE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 top_color : source_color;
uniform vec3 rock_color : source_color;
uniform vec3 key_dir = vec3(-.55, .65, .55);
varying vec3 world_normal;
varying float height;
void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	height = VERTEX.y;
}
void fragment() {
	vec3 n = normalize(world_normal);
	float key = clamp((dot(n, normalize(key_dir)) + .3) / 1.3, 0.0, 1.0);
	// The cap covers the flat top and spills a little over the edge.
	float cap = smoothstep(.55, .8, n.y) * smoothstep(-.12, -.02, height);
	vec3 base = mix(rock_color, top_color, cap);
	// Rock darkens and cools downward into the haze.
	float depth = clamp(-height / 1.4, 0.0, 1.0);
	vec3 lit = base * (.36 + .9 * key);
	ALBEDO = mix(lit, lit * vec3(.62, .68, .8), depth * .7);
}
"""
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	float d = length(UV - vec2(.5)) * 2.0;
	ALBEDO = vec3(.08, .06, .05);
	ALPHA = (1.0 - smoothstep(.2, 1.0, d)) * .45;
}
"""

var location := 0
var stage: Panel
var viewport: SubViewport
var holder: SubViewportContainer
var stage_inner := Vector2.ZERO
var camera: Camera3D
var hero: HeroModel
var ledge: MeshInstance3D
var hint: Panel
var slot_buttons := {}
var card_holder: Control
var cards := {} # id -> Button
var buy_button: Button
var choice_label: Label
var note_label: Label
var wallet_nodes: Array = []
var preview := {} # slot -> id tried on, not necessarily owned
var chosen := "" # The card picked in the current slot.
var flash := 0.0
var act_time := -1.0
var act_slot := ""
var bought := false # The lobby's wallet needs a rebuild on close.
var sparkles: CPUParticles2D
var still := RopeSim.new()
var clock := 0.0
var slot := ""
var framing_target := Vector3(0,.6,0)
var framing_distance := 4.5
var yaw := REST_YAW
var yaw_goal := REST_YAW
var spin := 0.0 # Fling speed after a drag (rad/s).
var idle_for := 10.0 # Seconds since the player touched the hero.
var look_goal := 0.0
var next_look := 1.5
var wave_time := -1.0 # Seconds into a greeting wave; -1 when not waving.
const WAVE_LENGTH := 1.7
var drag_pointer := -2
var drag_from := Vector2.ZERO
var drag_moved := false
var closing := false

func open(lobby: Control) -> void:
	prepare(lobby.hud)
	# The lobby's own canvas: the same size, place and scale under the banner.
	size = lobby.size
	position = lobby.position
	scale = lobby.scale
	location = clampi(int(game.lobby_location),0,LEDGE_TOPS.size()-1)
	build()

func build() -> void:
	# Catches taps that miss the screen's parts, so nothing reaches the lobby.
	var cover := Control.new()
	cover.position = Vector2(-2000,-2000)
	cover.size = size+Vector2(4000,4000)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var top := 12.0
	var back := action(self,"",Vector2(20,top),Vector2(52,52),close,"secondary")
	back.tooltip_text = "Назад"
	var arrow := symbol(back,11,Vector2(14,14),Vector2(24,24),INK)
	arrow.pivot_offset = arrow.size*.5
	arrow.rotation = PI
	text(self,"Персонаж",Vector2(86,top+8),Vector2(200,36),26,STONE,"display")
	_build_wallet()
	var stage_rect: Rect2
	var panel_rect: Rect2
	if landscape:
		stage_rect = Rect2(20,80,560,size.y-100)
		panel_rect = Rect2(600,80,size.x-620,size.y-100)
	else:
		# The wardrobe takes what its rows need; the stage gets the rest.
		var panel_height := 344.0
		stage_rect = Rect2(20,80,size.x-40,maxf(300,size.y-80-14-panel_height-20))
		panel_rect = Rect2(20,stage_rect.end.y+14,size.x-40,size.y-stage_rect.end.y-34)
	build_stage(stage_rect)
	build_wardrobe(panel_rect)

func build_stage(rect: Rect2) -> void:
	stage = slab(self,rect.position,rect.size,STONE_SHADE,STONE_LIP,5)
	var inner := rect.size-Vector2(0,5)
	var painting := TextureRect.new()
	painting.texture = LevelPreview.get_card_background(location)
	painting.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	painting.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	painting.size = inner
	painting.material = rounded_material(inner,10)
	painting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painting.modulate = Color(.86,.88,.92)
	stage.add_child(painting)
	# The hero renders at the screen's own pixels: a stretched container
	# renders at the 540x960 canvas units and the phone blows that up 2-3x,
	# which made the model look soapy. _fit_viewport keeps it sharp.
	holder = SubViewportContainer.new()
	holder.stretch = false
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_inner = inner
	stage.add_child(holder)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED if str(model.profile["settings"].get("shadows","high"))=="off" else Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 30
	viewport.add_child(camera)
	ledge = MeshInstance3D.new()
	ledge.mesh = ledge_mesh(7)
	var ledge_material := ShaderMaterial.new()
	ledge_material.shader = Shader.new()
	ledge_material.shader.code = LEDGE_SHADER
	ledge_material.set_shader_parameter("top_color",LEDGE_TOPS[location])
	ledge_material.set_shader_parameter("rock_color",LEDGE_ROCK[location])
	ledge.material_override = ledge_material
	viewport.add_child(ledge)
	var shadow := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(.95,.55)
	shadow.mesh = quad
	shadow.position = Vector3(0,.004,0)
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = Shader.new()
	shadow_material.shader.code = SHADOW_SHADER
	shadow.material_override = shadow_material
	viewport.add_child(shadow)
	hero = HeroModel.new()
	viewport.add_child(hero)
	hero.setup(true,str(model.profile["settings"].get("shadows","high"))!="off")
	HeroModel.showcase_environment(viewport)
	hero.position = Vector3(0,-HeroModel.FEET_Y,0)
	still.grounded = true
	still.attached = false
	# A soft fade under the stage edge so the panel below reads.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("1f2b3500"),Color("1f2b3566")])
	gradient.offsets = PackedFloat32Array([.7,1])
	var fade := GradientTexture2D.new()
	fade.gradient = gradient
	fade.fill_to = Vector2(0,1)
	shade.texture = fade
	shade.size = inner
	shade.material = rounded_material(inner,10)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(shade)
	var name_tag := slab(stage,Vector2(16,16),Vector2(170,34),Color(SLATE,.88),SLATE_LIP,3)
	text(name_tag,"Первопроходец",Vector2(0,5),Vector2(170,24),16,STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint = slab(stage,Vector2((inner.x-268)*.5,inner.y-50),Vector2(268,34),Color(SLATE,.78),SLATE_LIP,3)
	text(hint,"Крути пальцем · коснись героя",Vector2(0,6),Vector2(268,22),14,STONE,"strong").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sparkles = CPUParticles2D.new()
	sparkles.position = inner*Vector2(.5,.45)
	sparkles.emitting = false
	sparkles.one_shot = true
	sparkles.amount = 36
	sparkles.lifetime = 1.1
	sparkles.explosiveness = .9
	sparkles.direction = Vector2(0,-1)
	sparkles.spread = 70
	sparkles.initial_velocity_min = 140
	sparkles.initial_velocity_max = 280
	sparkles.gravity = Vector2(0,380)
	sparkles.scale_amount_min = 3
	sparkles.scale_amount_max = 6
	var fade_out := Gradient.new()
	fade_out.colors = PackedColorArray([COIN_LIGHT,Color(HOLD,0)])
	sparkles.color_ramp = fade_out
	stage.add_child(sparkles)
	_fit_viewport()
	_update_camera(1.0)
	_pose(0.0)

# Screen pixels per canvas unit at the stage, capped so a tablet does not
# render a huge target.
const MAX_PIXEL_SCALE := 3.0
func _fit_viewport() -> void:
	if not is_instance_valid(holder) or not holder.is_inside_tree(): return
	var pixel_scale := clampf((get_viewport().get_final_transform()*stage.get_global_transform_with_canvas()).get_scale().x,1.0,MAX_PIXEL_SCALE)
	var pixels := Vector2i((stage_inner*pixel_scale).round())
	if viewport.size==pixels: return
	viewport.size = pixels
	holder.size = Vector2(pixels)
	holder.scale = Vector2.ONE*(stage_inner.x/float(pixels.x))

func _build_wallet() -> void:
	for node in wallet_nodes:
		if is_instance_valid(node): node.queue_free()
	var first := get_child_count()
	wallet(Vector2(size.x-236,15))
	wallet_nodes = get_children().slice(first)

func build_wardrobe(rect: Rect2) -> void:
	var panel := slab(self,rect.position,rect.size)
	var inner := rect.size.x-36
	text(panel,"Гардероб",Vector2(18,10),Vector2(200,32),22,INK,"display")
	# Slot tabs: two rows of three keep the names whole on a phone.
	var per_row := 6 if inner>=640 else 3
	var gap := 6.0
	var each := (inner-gap*(per_row-1))/per_row
	for index in range(HeroOutfit.SLOTS.size()):
		var key: String = HeroOutfit.SLOTS[index]
		var at := Vector2(18+(index%per_row)*(each+gap),48+(index/per_row)*(44+gap))
		var tab := action(panel,str(HeroOutfit.SLOT_NAMES[key]),at,Vector2(each,40),pick_slot.bind(key),"secondary")
		tab.add_theme_font_size_override("font_size",15)
		slot_buttons[key] = tab
	var tabs_bottom := 48.0+ceili(HeroOutfit.SLOTS.size()/float(per_row))*(44+gap)
	card_holder = Control.new()
	card_holder.position = Vector2(18,tabs_bottom+4)
	card_holder.size = Vector2(inner,92)
	card_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(card_holder)
	var row := tabs_bottom+4+92+12
	choice_label = text(panel,"",Vector2(18,row+10),Vector2(inner-180,24),17,INK,"display")
	buy_button = action(panel,"",Vector2(rect.size.x-18-170,row),Vector2(170,46),_buy_pressed,"primary")
	note_label = text(panel,"",Vector2(18,row+52),Vector2(inner,20),13,INK_SOFT)
	_show_slot()

func _paint_slots() -> void:
	for key in slot_buttons:
		hud.skin_button(slot_buttons[key],"primary" if key==slot else "secondary")

# A slot zooms the camera onto its part (the backpack turns the hero round)
# and shows its colours. A second tap on the open slot goes back to full height.
func pick_slot(which: String) -> void:
	if which==slot and not which.is_empty(): which = ""
	# Leaving a slot takes off what was only tried on there: full height
	# shows what the hero really wears.
	if preview.has(slot):
		preview.erase(slot)
		_apply_preview()
	slot = which
	yaw_goal = float(SLOT_YAW.get(which,REST_YAW))
	spin = 0.0
	# The camera and the turn start at once, without the after-touch pause.
	idle_for = 2.5
	chosen = str(preview.get(slot,HeroOutfit.worn_id(model.profile,slot))) if not slot.is_empty() else ""
	note_label.text = ""
	_paint_slots()
	_show_slot()

func _show_slot() -> void:
	for child in card_holder.get_children(): child.queue_free()
	cards.clear()
	if slot.is_empty():
		paragraph(card_holder,"Выбери деталь: камера наведётся на неё, а цвета можно примерить до покупки.",Vector2(0,14),Vector2(card_holder.size.x,60),15,INK_SOFT)
		choice_label.text = ""
		buy_button.visible = false
		return
	var options: Array = HeroOutfit.COLOURS[slot]
	var gap := 8.0
	var per_row := mini(options.size(),6)
	var each := (card_holder.size.x-gap*(per_row-1))/per_row
	for index in range(options.size()):
		var option: Array = options[index]
		var id := str(option[0])
		var card := action(card_holder,"",Vector2(index*(each+gap),0),Vector2(each,88),pick_colour.bind(id),"secondary")
		card.tooltip_text = str(option[1])
		var colour: Color = option[2]
		slab(card,Vector2((each-40)*.5,8),Vector2(40,36),colour,colour.darkened(.35),4)
		var name_label := text(card,str(option[1]),Vector2(2,46),Vector2(each-4,18),12,INK,"strong")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var status := Control.new()
		status.position = Vector2(0,64)
		status.size = Vector2(each,20)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(status)
		if HeroOutfit.worn_id(model.profile,slot)==id:
			text(status,"Надето",Vector2.ZERO,Vector2(each,18),12,MOSS,"strong").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif HeroOutfit.owns(model.profile,id):
			text(status,"Есть",Vector2.ZERO,Vector2(each,18),12,INK_SOFT,"strong").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			var price := HeroOutfit.price(id)
			var width: float = hud.heading_font.get_string_size(str(price),HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+22
			coin_amount(status,price,Vector2((each-width)*.5,-1),13,COIN,12)
		if id==chosen:
			# The card on the hero now: a slate frame around it.
			var frame := Panel.new()
			var box := StyleBoxFlat.new()
			box.draw_center = false
			box.set_border_width_all(3)
			box.border_color = SLATE
			box.set_corner_radius_all(8)
			frame.add_theme_stylebox_override("panel",box)
			frame.position = Vector2(-3,-3)
			frame.size = Vector2(each+6,94)
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(frame)
		cards[id] = card
	_paint_choice()

func _paint_choice() -> void:
	var option := HeroOutfit.entry(chosen)
	if option.is_empty(): return
	choice_label.text = "%s · %s" % [HeroOutfit.SLOT_NAMES[slot],option[1]]
	buy_button.visible = true
	buy_button.disabled = false
	if HeroOutfit.worn_id(model.profile,slot)==chosen:
		buy_button.text = "Надето"
		buy_button.disabled = true
		hud.skin_button(buy_button,"secondary")
	elif HeroOutfit.owns(model.profile,chosen):
		buy_button.text = "Надеть"
		hud.skin_button(buy_button,"primary")
	else:
		buy_button.text = "Купить · %d" % HeroOutfit.price(chosen)
		hud.skin_button(buy_button,"primary")

# Try-on: the colour goes on the hero at once (not bought yet), the part
# glows and the hero shows it off.
func pick_colour(id: String) -> void:
	chosen = id
	preview[slot] = id
	note_label.text = "" if HeroOutfit.owns(model.profile,id) else "Примерка. Купи, чтобы носить в походе."
	_apply_preview()
	flash = 1.0
	act_slot = slot
	act_time = 0.0
	_show_slot()

func _apply_preview() -> void:
	var outfit: Dictionary = HeroOutfit.worn.duplicate()
	for key in preview: outfit[key] = preview[key]
	hero.set_outfit(outfit)

func _buy_pressed() -> void:
	if chosen.is_empty(): return
	var owned := HeroOutfit.owns(model.profile,chosen)
	var error := HeroOutfit.buy(model.profile,chosen)
	if not error.is_empty():
		# Short of gold: how much, where it comes from, and a nod of the button.
		note_label.text = "%s. Золото приносят восхождения." % error
		buy_button.pivot_offset = buy_button.size*.5
		var tween := buy_button.create_tween()
		tween.tween_property(buy_button,"rotation",.05,.05)
		tween.tween_property(buy_button,"rotation",-.04,.08)
		tween.tween_property(buy_button,"rotation",0.0,.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	model.save()
	preview.erase(slot)
	_apply_preview()
	note_label.text = "Надето." if owned else "Куплено и надето."
	if not owned:
		bought = true
		_build_wallet()
		_celebrate()
	_show_slot()

# A purchase: gold sparks over the hero, a sound and a buzz, and he waves.
func _celebrate() -> void:
	if is_instance_valid(sparkles):
		sparkles.restart()
		sparkles.emitting = true
	game._sfx("pickup")
	game._haptic("pickup")
	greet()

func close() -> void:
	if closing: return
	closing = true
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self,"modulate:a",0.0,.14)
	tween.tween_callback(queue_free)
	closed.emit()
	if bought and is_instance_valid(hud.lobby_view): hud.lobby_view.rebuild.call_deferred()

# ---------------------------------------------------------------- the ledge

# A faceted rock shelf: a flat irregular top that breaks into steep sides and
# runs down out of the frame. Flat-shaded like the menu's limestone slabs.
static func ledge_mesh(seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = .9
	const SEGMENTS := 26
	# Rings from the top centre outward and down: [radius scale, height].
	var rings := [[0.0,.0],[.35,.0],[.68,-.01],[.93,-.05],[1.0,-.17],[.94,-.5],[1.08,-.95],[1.25,-1.6]]
	var points: Array = []
	for ring_index in range(rings.size()):
		var ring: Array = rings[ring_index]
		var row: Array = []
		for segment in range(SEGMENTS):
			var angle := TAU*segment/SEGMENTS
			var bump := 1.0+(.16 if ring_index<4 else .3)*noise.get_noise_2d(cos(angle)*3,sin(angle)*3+ring_index*1.7)
			var radius: float = float(ring[0])*bump
			# The top is not a table: low swells and a dip toward the rim.
			var y: float = float(ring[1])+(.05*noise.get_noise_2d(angle*4,ring_index*5.0) if ring_index>2 else .025*noise.get_noise_2d(angle*2.5,ring_index*3.0+9.0))
			# Wider than deep: a shelf, not a pillar.
			row.append(Vector3(cos(angle)*radius*1.15,y,sin(angle)*radius*.62))
		points.append(row)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index in range(rings.size()-1):
		for segment in range(SEGMENTS):
			var next := (segment+1)%SEGMENTS
			var a: Vector3 = points[ring_index][segment]
			var b: Vector3 = points[ring_index][next]
			var c: Vector3 = points[ring_index+1][next]
			var d: Vector3 = points[ring_index+1][segment]
			for triangle in [[a,c,b],[a,d,c]]:
				var normal: Vector3 = (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
				if normal==Vector3.ZERO: continue
				for vertex in triangle:
					tool.set_normal(normal)
					tool.add_vertex(vertex)
	return tool.commit()

# ---------------------------------------------------------------- motion

func _process(delta: float) -> void:
	if not is_instance_valid(hero): return
	delta = minf(delta,.1)
	clock += delta
	idle_for += delta
	# A fling coasts and slows; then the hero settles back to his pose.
	if drag_pointer==-2:
		yaw += spin*delta
		spin *= exp(-delta*4)
		if absf(spin)<.05 and idle_for>2.5: yaw = lerp_angle(yaw,yaw_goal,1-exp(-delta*3))
	if wave_time>=0:
		wave_time += delta
		if wave_time>WAVE_LENGTH: wave_time = -1.0
	flash = maxf(0,flash-delta*2.8)
	hero.shader_material.set_shader_parameter("flash",flash)
	hero.shader_material.set_shader_parameter("flash_code",float(HeroOutfit.CODES.get(act_slot,0)))
	if act_time>=0:
		act_time += delta
		if act_time>ACT_LENGTH: act_time = -1.0
	hero.pose_offset = act_pose(act_slot,act_time) if act_time>=0 else {}
	# Looking around: a new glance every few seconds, toward the viewer after a tap.
	next_look -= delta
	if next_look<=0:
		next_look = randf_range(2.2,4.5)
		look_goal = 0.0 if randf()<.35 else randf_range(-.55,.45)
	_fit_viewport() # The window can change size (rotation, split screen).
	_update_camera(1-exp(-delta*5))
	_pose(delta)
	if is_instance_valid(hint) and idle_for<1.0 and hint.modulate.a>0:
		hint.modulate.a = move_toward(hint.modulate.a,0.0,delta*2)

func _update_camera(blend: float) -> void:
	var framing: Array = FRAMES.get(slot if not slot.is_empty() else "full",FRAMES["full"])
	framing_target = framing_target.lerp(framing[0],blend)
	framing_distance = lerpf(framing_distance,float(framing[1]),blend)
	# A little from below, as if looking up at the hero on the ledge.
	var offset := Vector3(.3,.02,1).normalized()*framing_distance
	camera.position = framing_target+offset
	camera.look_at(framing_target,Vector3.UP)

func _pose(delta: float) -> void:
	hero.look_yaw = lerpf(hero.look_yaw,look_goal,1-exp(-delta*4))
	hero.animate(still,still.pos+Vector2(1,0),false,clock)
	# HeroModel turns to its facing; the screen owns the body turn instead.
	hero.rotation.y = yaw
	if wave_time>=0: _wave(wave_time)

# The greeting: the near arm lifts out to the side and the hand waves. The
# clips only bend in the side plane (a raised arm hides behind the head seen
# from the front), so the wave turns the arm about the body's forward axis.
func _wave(t: float) -> void:
	var lift := smoothstep(0.0,.3,t)*smoothstep(WAVE_LENGTH,WAVE_LENGTH-.35,t)
	var shake := sin(maxf(0,t-.25)*13.0)
	var bones := {"upper_arm_near":-1.7*lift,"forearm_near":(-1.25+.35*shake)*lift,"hand_near":.2*shake*lift,"head":.12*lift,"chest":.06*lift}
	var skeleton := hero.skeleton
	for bone in bones:
		var index: int = hero.bone_index[bone]
		var forward: Vector3 = (skeleton.get_bone_global_rest(index).basis.inverse()*Vector3.RIGHT).normalized()
		skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index)*Quaternion(forward,float(bones[bone])))

# The small action that shows a part just tried on: bone angles added to the
# idle pose over t in 0..ACT_LENGTH.
static func act_pose(which: String, t: float) -> Dictionary:
	var swell := sin(PI*clampf(t/ACT_LENGTH,0,1))
	match which:
		"head": return {"head":.28*sin(t*TAU*1.6)*swell} # A nod or two.
		"jacket": return {"head":.35*swell,"upper_arm_near":.45*swell,"forearm_near":.9*swell,"chest":-.08*swell} # Looks it over.
		"backpack": return {"chest":.12*swell,"upper_arm_near":-.25*swell,"upper_arm_far":-.25*swell} # Shrugs the straps.
		"pants": return {"thigh_near":.8*swell,"shin_near":-1.1*swell,"head":.2*swell} # Lifts a knee to look.
		"boots": # Two stomps.
			var stomp := maxf(0,sin(t*TAU*2.0))*swell
			return {"thigh_near":.75*stomp,"shin_near":-1.0*stomp,"foot_near":.25*stomp}
		"gloves": return {"upper_arm_near":.75*swell,"forearm_near":1.6*swell,"hand_near":.3*sin(t*TAU*2)*swell,"head":.3*swell} # Looks at the hand.
	return {}

# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return
	var pointer := -2
	var pressed := false
	var released := false
	var position_value := Vector2.ZERO
	if event is InputEventScreenTouch:
		pointer = event.index
		pressed = event.pressed
		released = not event.pressed
		position_value = event.position
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
		pointer = -1
		pressed = event.pressed
		released = not event.pressed
		position_value = event.position
	elif event is InputEventScreenDrag:
		if event.index==drag_pointer: _drag(event.position,event.relative,event.velocity)
		return
	elif event is InputEventMouseMotion and drag_pointer==-1:
		_drag(event.position,event.relative,event.velocity)
		return
	else:
		return
	var local: Vector2 = stage.get_global_transform_with_canvas().affine_inverse()*position_value
	if pressed and drag_pointer==-2 and Rect2(Vector2.ZERO,stage.size).has_point(local):
		drag_pointer = pointer
		drag_from = position_value
		drag_moved = false
		spin = 0.0
		idle_for = 0.0
		get_viewport().set_input_as_handled()
	elif released and pointer==drag_pointer:
		drag_pointer = -2
		if not drag_moved and _on_hero(local): greet()
		get_viewport().set_input_as_handled()

func _drag(at: Vector2, relative: Vector2, velocity: Vector2) -> void:
	if at.distance_to(drag_from)>10: drag_moved = true
	var pixels_per_turn := 260.0/stage.get_global_transform_with_canvas().get_scale().x
	yaw += relative.x/pixels_per_turn*PI*.5
	spin = clampf(velocity.x/pixels_per_turn*PI*.5,-9,9)
	idle_for = 0.0
	get_viewport().set_input_as_handled()

# Roughly where the hero stands in the stage (the camera keeps him centred).
func _on_hero(local: Vector2) -> bool:
	var inner := stage.size
	var screen := camera.unproject_position(hero.global_position+Vector3(0,.0,0))
	var head := camera.unproject_position(hero.global_position+Vector3(0,.62,0))
	var feet := camera.unproject_position(hero.global_position+Vector3(0,-.56,0))
	var scale_x := inner.x/maxf(1,viewport.size.x)
	var scale_y := inner.y/maxf(1,viewport.size.y)
	var box := Rect2(Vector2(screen.x*scale_x-inner.x*.16,head.y*scale_y-20),Vector2(inner.x*.32,(feet.y-head.y)*scale_y+40))
	return box.has_point(local)

# A tap on the hero: he turns to the viewer and waves.
func greet() -> void:
	yaw_goal = FRONT_YAW if slot!="backpack" else yaw_goal
	spin = 0.0
	idle_for = 2.5
	look_goal = 0.0
	next_look = 3.0
	wave_time = 0.0
	get_tree().create_timer(3.5).timeout.connect(func():
		if is_instance_valid(self) and slot!="backpack": yaw_goal = REST_YAW)
