class_name SplashScreen
extends Control

# Launch splash: the app icon pops in over the menu sky, bobs while the title
# types in beneath it, then the title and veil fade and the icon shrinks and
# flies into the profile button's mini icon in the top-left corner. A tap
# hurries it on. Emits `finished` once the icon has landed.

signal finished

const HOLD_SECONDS := 1.9
var hud: GameHud
var target: Control
var veil: ColorRect
var glow: Control
var icon: TextureRect
var title: Label
var tagline: Label
var timeline: Tween
var bob: Tween
var leaving := false
var icon_size := 220.0

class Glow extends Control:
	var strength := 0.0
	func _draw() -> void:
		var center := size*.5
		for ring in range(10):
			var t := float(ring)/9.0
			draw_circle(center,size.x*.5*(1.0-t*.7),Color(1.0,.95,.72,strength*.05*(1.0+t)))

func setup(owner_hud: GameHud, mini_icon: Control) -> void:
	hud = owner_hud
	target = mini_icon
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil = ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("2b74d6"),Color("8cc5f2")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0,1)
	var sky := TextureRect.new()
	sky.texture = texture
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color.TRANSPARENT
	veil.add_child(sky)
	add_child(veil)
	glow = Glow.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	icon = TextureRect.new()
	icon.texture = preload("res://assets/icon.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	title = Label.new()
	title.text = "Last Hook"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font",hud.heading_font)
	title.add_theme_color_override("font_color",MenuSurface.STONE)
	title.add_theme_color_override("font_shadow_color",Color(MenuSurface.SLATE_LIP,.45))
	title.add_theme_constant_override("shadow_offset_y",4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	tagline = Label.new()
	tagline.text = "Цепляйся. Раскачивайся. Вверх."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_override("font",hud.strong_font)
	tagline.add_theme_color_override("font_color",Color(MenuSurface.STONE,.85))
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tagline)
	_layout()
	if is_instance_valid(target): target.modulate.a = 0.0
	_play()

func _layout() -> void:
	var view := get_viewport_rect().size
	var unit := minf(view.x,view.y)
	icon_size = clampf(unit*.42,140,320)
	var center := Vector2(view.x*.5,view.y*.44)
	icon.size = Vector2.ONE*icon_size
	icon.pivot_offset = icon.size*.5
	icon.position = center-icon.size*.5
	glow.size = Vector2.ONE*icon_size*2.4
	glow.position = center-glow.size*.5
	var title_size := int(clampf(unit*.11,40,84))
	title.add_theme_font_size_override("font_size",title_size)
	title.size = Vector2(view.x,title_size*1.4)
	title.position = Vector2(0,center.y+icon_size*.5+unit*.06)
	tagline.add_theme_font_size_override("font_size",int(title_size*.32))
	tagline.size = Vector2(view.x,title_size*.6)
	tagline.position = Vector2(0,title.position.y+title_size*1.35)

func _play() -> void:
	icon.scale = Vector2.ONE*.35
	icon.modulate.a = 0.0
	icon.rotation = -.18
	title.visible_ratio = 0.0
	title.modulate.a = 0.0
	tagline.modulate.a = 0.0
	timeline = create_tween()
	timeline.set_parallel(true)
	timeline.tween_property(icon,"modulate:a",1.0,.25)
	timeline.tween_property(icon,"scale",Vector2.ONE,.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	timeline.tween_property(icon,"rotation",0.0,.75).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	timeline.tween_property(glow,"strength",1.0,.6).set_delay(.2)
	timeline.tween_property(title,"modulate:a",1.0,.3).set_delay(.45)
	timeline.tween_property(title,"visible_ratio",1.0,.55).set_delay(.45)
	timeline.tween_property(tagline,"modulate:a",1.0,.4).set_delay(1.0)
	timeline.chain().tween_interval(maxf(0.0,HOLD_SECONDS-1.0))
	timeline.chain().tween_callback(_leave)
	bob = create_tween().set_loops()
	bob.tween_property(icon,"position:y",icon.position.y-10,.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(.6)
	bob.tween_property(icon,"position:y",icon.position.y,.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(_delta: float) -> void:
	if is_instance_valid(glow): glow.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	# A tap or click hurries the splash on.
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and not leaving:
		accept_event()
		_leave()

# The icon shrinks and flies into the profile's mini icon while the veil,
# glow and title fade away.
func _leave() -> void:
	if leaving: return
	leaving = true
	if timeline!=null and timeline.is_valid(): timeline.kill()
	if bob!=null and bob.is_valid(): bob.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := create_tween().set_parallel(true)
	fade.tween_property(title,"modulate:a",0.0,.25)
	fade.tween_property(title,"position:y",title.position.y+16,.25)
	fade.tween_property(tagline,"modulate:a",0.0,.2)
	fade.tween_property(glow,"strength",0.0,.3)
	fade.tween_property(veil,"modulate:a",0.0,.55).set_delay(.15)
	var goal := Rect2(Vector2(28,22),Vector2(38,38))
	if is_instance_valid(target) and target.is_inside_tree(): goal = target.get_global_rect()
	var fly := create_tween()
	# A small wind-up, then a curved flight into the corner.
	fly.tween_property(icon,"scale",Vector2.ONE*1.08,.14).set_trans(Tween.TRANS_SINE)
	fly.tween_property(icon,"scale",Vector2.ONE,.08)
	fly.tween_callback(func(): icon.pivot_offset = Vector2.ZERO)
	var start := icon.position
	var start_size := icon.size.x
	fly.tween_method(func(t: float):
		var arc := start.lerp(goal.position,t)+Vector2(0,-60.0*sin(PI*t))
		icon.position = arc
		icon.size = Vector2.ONE*lerpf(start_size,goal.size.x,t)
		icon.rotation = -.5*sin(PI*t),0.0,1.0,.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fly.tween_callback(_land)

func _land() -> void:
	if is_instance_valid(target):
		target.modulate.a = 1.0
		target.pivot_offset = target.size*.5
		var pop := target.create_tween()
		pop.tween_property(target,"scale",Vector2.ONE*1.25,.1).set_trans(Tween.TRANS_SINE)
		pop.tween_property(target,"scale",Vector2.ONE,.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	finished.emit()
	queue_free()
