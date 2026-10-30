class_name GameHud
extends CanvasLayer

var game
var root: Control
var content: Control
var toast_label: Label
var height_label: Label
var record_label: Label
var danger_label: Label
var goal_label: Label
var aim_label: Label
var climb_bar: PlayGauges.RouteGauge
var rope_gauge: PlayGauges.RopeGauge
var danger_edge: PlayGauges.DangerEdge
var danger_timer: PlayGauges.TimerBar
var height_plate: Panel
var bag_tray: Panel
var bag_total_label: Label
var bag_count_label: Label
var bag_toggle: Button
var bag_icon: UiSymbol
var bag_chevron: UiSymbol
var bag_full_chip: PanelContainer
# Chat 4: the wallet (coins are banked at once), the run's contract, the two
# active-item buttons, the beacon's marks and the full-bag swap prompt.
var wallet_plate: Panel
var wallet_label: Label
var shown_wallet := 0.0
var contract_label: Label
var item_buttons: Array[ItemButton] = []
var beacon_marks: BeaconMarks
var swap_panel: Panel
var boosts_panel: Panel
var lobby_view: LobbyView
var shown_height := 0.0
var toast_placement: Array = []
var shown_bag_total := 0.0
var flying_value := 0
var shown_bag_ids: Array = []
var record_run := ""
var record_at_start := 0.0
var record_broken := false
var last_zone := -1
var slowmo_indicator: SlowmoIndicator
var slowmo_vignette: SlowmoVignette
var seen_focus_serial := 0
var item_check_time := -1.0
var bag_panel: VBoxContainer
var pause_button: Button
var aim_overlay: AimOverlay
var base_theme: Theme
var body_font: Font
var level_intro: Control
var heading_font: FontVariation
var backdrop: LobbyView.Backdrop
var layout_mode := "modal"
var menu_tab := "expedition"
# Equipment tab: "upgrades" (buy levels) or "supplies" (run profiles, items).
var equipment_view := "upgrades"
# Settings subsection: graphics, controls, keys, accessibility or about.
var settings_section := "graphics"
var about_version := ""
# Accessibility settings read while building text.
var text_scale := 1.0
var bold_outline := false
const MENU_TABS := ["equipment","expedition","settings"]
# Direction of the last menu change (-1 back, 1 forward, 0 none): the next
# LobbyView slides its body in from that side and moves the tab marker.
var menu_slide := 0
var menu_previous_tab := "expedition"
# Which control should take keyboard/controller focus after a swipe or key:
# "tab", "start" or "".
var menu_focus := ""
var upgrade_flash := ""
# The equipment category on show.
var equipment_category := "movement"
var last_swipe_msec := -100000
var result_data: Dictionary = {}
var revive_reason := "Падение"
var wide := false
var shot_preview: Dictionary = {}
const PREVIEW_INTERVAL := .05
const PREVIEW_TURN := .99966 # cos 1.5 degrees
var shot_preview_time := -1.0
var shot_preview_direction := Vector2.ZERO
var ad_blocker: Control
var exit_overlay: Control
var exit_dialog: Panel
var touch_controls_hint := OS.has_feature("mobile")
var strong_font: FontVariation
var hud_chips: Array[PanelContainer] = []
var toast_chip: Panel
const WHITE := MenuSurface.STONE
const MUTED := Color("c9d2d8")
const CYAN := MenuSurface.CRYSTAL_LIGHT
const CORAL := Color("ff8f70")
const INK_PANEL := MenuSurface.SLATE
const PLAY_PANEL := Color("24323deb")
const BUY_FACE := Color("fdefc3")
const BUY_RIM := Color("ecbe3a")

class SlowmoIndicator extends Control:
	# A compact chip that only appears while release slow motion runs (gold,
	# seconds left) or recharges (muted); when ready it stays out of the way.
	var remaining := 0.0
	var duration := .7
	var cooldown := 0.0
	var cooldown_total := 1.0
	var ready_seconds := .7
	var text_font: Font
	var number_font: Font
	func state_name() -> String:
		return "active" if remaining>0 else "cooldown" if cooldown>0 else "ready"
	func _draw() -> void:
		var font := text_font if text_font!=null else ThemeDB.fallback_font
		var digits := number_font if number_font!=null else font
		var active := remaining>0
		PlayGauges.slab(self,Rect2(Vector2.ZERO,size-Vector2(0,3)),Color("141d24f2") if active else Color("24323dd8"),MenuSurface.SLATE_LIP,3,8)
		var accent := MenuSurface.HOLD if active else MUTED
		# Hourglass mark.
		var mark := Vector2(18,size.y*.5-2)
		draw_colored_polygon(PackedVector2Array([mark+Vector2(-6,-9),mark+Vector2(6,-9),mark+Vector2(0,0)]),Color(accent,.9))
		draw_colored_polygon(PackedVector2Array([mark+Vector2(0,0),mark+Vector2(-6,9),mark+Vector2(6,9)]),Color(accent,.45))
		var value := remaining if active else cooldown
		draw_string(font,Vector2(32,size.y*.5+3),"Замедление" if active else "Перезарядка",HORIZONTAL_ALIGNMENT_LEFT,size.x-90,14,WHITE if active else MUTED)
		draw_string(digits,Vector2(0,size.y*.5+4),("%.1f с" % value).replace(".",","),HORIZONTAL_ALIGNMENT_RIGHT,size.x-12,16,accent)
		var track := Rect2(10,size.y-8,size.x-20,3)
		draw_rect(track,Color(WHITE,.12))
		var share := clampf(remaining/maxf(.01,duration),0,1) if active else clampf(1-cooldown/maxf(.01,cooldown_total),0,1)
		draw_rect(Rect2(track.position,Vector2(track.size.x*share,track.size.y)),accent)

# Release slow motion tints the screen edges cool blue with thin moving
# streaks, so the change of pace is obvious even out of the corner of the eye.
class SlowmoVignette extends Control:
	var strength := 0.0
	var time := 0.0
	var flash := 0.0
	func _draw() -> void:
		if strength<=.001 and flash<=.001: return
		# A light cool wash over the whole view plus deep blue edges.
		draw_rect(Rect2(Vector2.ZERO,size),Color(Color("3d7fb8"),.10*strength))
		var edge := Color(Color("0b2238"),.62*strength)
		var clear := Color(Color("0b2238"),0)
		var depth := minf(size.x,size.y)*.26
		var rim := Color(CYAN,.55*flash)
		for side in range(4):
			var outer: PackedVector2Array
			var inner: PackedVector2Array
			match side:
				0: outer = [Vector2.ZERO,Vector2(size.x,0)]; inner = [Vector2(size.x-depth,depth),Vector2(depth,depth)]
				1: outer = [Vector2(size.x,0),size]; inner = [Vector2(size.x-depth,size.y-depth),Vector2(size.x-depth,depth)]
				2: outer = [size,Vector2(0,size.y)]; inner = [Vector2(depth,size.y-depth),Vector2(size.x-depth,size.y-depth)]
				_: outer = [Vector2(0,size.y),Vector2.ZERO]; inner = [Vector2(depth,depth),Vector2(depth,size.y-depth)]
			draw_polygon(PackedVector2Array([outer[0],outer[1],inner[0],inner[1]]),PackedColorArray([edge,edge,clear,clear]))
		# Speed streaks drift slowly inward along the sides.
		for index in range(10):
			var side := -1.0 if index%2==0 else 1.0
			var y := fposmod(index*.137*size.y+time*size.y*.05,size.y)
			var x := size.x*.5+side*(size.x*.5-depth*(.15+.1*sin(index*1.7)))
			draw_line(Vector2(x,y),Vector2(x,y+size.y*.07),Color(CYAN,.35*strength),2.5,true)
		if flash>.001:
			draw_rect(Rect2(Vector2.ZERO,size),rim,false,6.0*flash+1)

# An active item of the run: a round hold-like button with its own icon and
# a short name. Ready (gold rim), armed (rim turns while it waits for flight),
# running (the rim drains), unavailable right now (dim) or spent.
class ItemButton extends Control:
	const CIRCLE := 64.0
	var index := 0
	var id := ""
	var title := ""
	var used := false
	var passive := false
	var running := 0.0
	var armed := false
	var blocked := false
	var unavailable := false
	var time := 0.0
	var text_font: Font
	var on_press := Callable()
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _process(delta: float) -> void:
		time += delta
		if armed: queue_redraw()
	func _gui_input(event: InputEvent) -> void:
		# Mouse is not emulated from touch in this project: a finger arrives as
		# a screen touch, a desktop click as a mouse button. Either is one press.
		var tapped: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.device!=InputEvent.DEVICE_ID_EMULATION)
		if tapped:
			accept_event()
			pivot_offset = Vector2(size.x*.5,CIRCLE*.5)
			var tween := create_tween()
			tween.tween_property(self,"scale",Vector2.ONE*.88,.06).set_trans(Tween.TRANS_SINE)
			tween.tween_property(self,"scale",Vector2.ONE,.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if on_press.is_valid(): on_press.call(index)
	func _draw() -> void:
		var font := text_font if text_font!=null else ThemeDB.fallback_font
		var center := Vector2(size.x*.5,CIRCLE*.5)
		var radius := CIRCLE*.5-2
		var live := running>0 or armed
		var dim := used or (blocked and not live)
		draw_circle(center+Vector2(0,3),radius,MenuSurface.SLATE_LIP)
		draw_circle(center,radius,Color("141d24f5") if live else Color("24323d",.6 if dim else .92))
		if armed:
			for dash in range(8):
				var from := time*2.4+dash*TAU/8
				draw_arc(center,radius-2,from,from+TAU/14,8,MenuSurface.HOLD,3,true)
		elif running>0:
			draw_arc(center,radius-2,0,TAU,48,Color(MenuSurface.HOLD,.22),3,true)
			draw_arc(center,radius-2,-PI*.5,-PI*.5+TAU*running,48,MenuSurface.HOLD,3.5,true)
		else:
			draw_arc(center,radius-2,0,TAU,48,Color(MUTED,.22) if dim else Color(MenuSurface.HOLD,.75),2,true)
		var tint := MenuSurface.HOLD if live else Color(WHITE,.35) if dim else WHITE
		draw_set_transform(center,0,Vector2.ONE*radius/26.0)
		match id:
			"beacon": _beacon(tint)
			"booster": _booster(tint)
			"glide": _glide(tint)
			_: _strap(tint)
		draw_set_transform(Vector2.ZERO)
		var note := "использован" if used else "ждёт полёта" if armed else "авто" if passive else title
		var color := Color(MUTED,.7) if used else MenuSurface.HOLD if armed else WHITE
		draw_string(font,Vector2(1,CIRCLE+18),note,HORIZONTAL_ALIGNMENT_CENTER,size.x,12,Color(MenuSurface.SLATE_LIP,.85))
		draw_string(font,Vector2(0,CIRCLE+17),note,HORIZONTAL_ALIGNMENT_CENTER,size.x,12,color)
	# Lantern with rays: it lights up the exits.
	func _beacon(tint: Color) -> void:
		for ray in range(5):
			var angle := -PI*.5+(ray-2)*.5
			draw_line(Vector2.from_angle(angle)*13,Vector2.from_angle(angle)*18,tint,2.2,true)
		draw_colored_polygon(PackedVector2Array([Vector2(-6,-6),Vector2(6,-6),Vector2(8,10),Vector2(-8,10)]),Color(tint,.35))
		draw_polyline(PackedVector2Array([Vector2(-6,-6),Vector2(6,-6),Vector2(8,10),Vector2(-8,10),Vector2(-6,-6)]),tint,2,true)
		draw_line(Vector2(-4,-9),Vector2(4,-9),tint,2.5,true)
		draw_circle(Vector2(0,3),3,tint)
	# Two chevrons: a push along the flight.
	func _booster(tint: Color) -> void:
		for step in range(2):
			var y := 6-step*11
			draw_polyline(PackedVector2Array([Vector2(-10,y+6),Vector2(0,y-4),Vector2(10,y+6)]),tint,4,true)
	# Canopy with lines: a slower fall.
	func _glide(tint: Color) -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(-15,-2),Vector2(-12,-10),Vector2(-5,-15),Vector2(5,-15),Vector2(12,-10),Vector2(15,-2)]),Color(tint,.35))
		draw_polyline(PackedVector2Array([Vector2(-15,-2),Vector2(-12,-10),Vector2(-5,-15),Vector2(5,-15),Vector2(12,-10),Vector2(15,-2),Vector2(-15,-2)]),tint,2,true)
		for x in [-15,-5,5,15]: draw_line(Vector2(x,-2),Vector2(0,10),Color(tint,.8),1.4,true)
		draw_rect(Rect2(-3,9,6,6),tint)
	# Shield with a strap: it catches one fall by itself.
	func _strap(tint: Color) -> void:
		var shield := PackedVector2Array([Vector2(-11,-12),Vector2(11,-12),Vector2(11,0),Vector2(0,14),Vector2(-11,0)])
		draw_colored_polygon(shield,Color(tint,.3))
		shield.append(shield[0])
		draw_polyline(shield,tint,2,true)
		draw_polyline(PackedVector2Array([Vector2(-5,0),Vector2(-1,4),Vector2(6,-5)]),tint,2.6,true)

# Level start: the menu slate covers the screen with the place's name, then
# opens as an iris round the climber. Purely a picture: the mountain is
# already built and input goes straight through.
class LevelIntro extends Control:
	const DURATION := .66
	var iris := ColorRect.new()
	var iris_material := ShaderMaterial.new()
	var title := Label.new()
	var subtitle := Label.new()
	var focus := Vector2.ZERO
	func setup(origin: Vector2, heading: String, note: String, heading_font: Font, note_font: Font, ui_scale: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		focus = origin
		iris.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
		iris_material.shader = preload("res://shaders/level_intro.gdshader")
		iris_material.set_shader_parameter("tint",MenuSurface.SLATE)
		iris_material.set_shader_parameter("rim",MenuSurface.HOLD)
		iris.material = iris_material
		add_child(iris)
		for pair in [[title,heading,heading_font,34,MenuSurface.HOLD],[subtitle,note,note_font,17,MUTED]]:
			var line: Label = pair[0]
			line.text = pair[1]
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if pair[2]!=null: line.add_theme_font_override("font",pair[2])
			line.add_theme_font_size_override("font_size",roundi(int(pair[3])*ui_scale))
			line.add_theme_color_override("font_color",pair[4])
			add_child(line)
		_set_open(0.0)
		var tween := create_tween()
		# A beat on the name, the iris opens from the climber, the name lifts
		# away as it goes.
		tween.tween_method(_set_open,0.0,1.0,DURATION-.1).set_delay(.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.parallel().tween_property(title,"modulate:a",0.0,.26).set_delay(.22)
		tween.parallel().tween_property(subtitle,"modulate:a",0.0,.22).set_delay(.22)
		tween.tween_callback(queue_free)
	func _set_open(amount: float) -> void:
		var area := get_viewport_rect().size
		var far := 0.0
		for corner in [Vector2.ZERO,Vector2(area.x,0),Vector2(0,area.y),area]: far = maxf(far,focus.distance_to(corner))
		iris_material.set_shader_parameter("size",area)
		iris_material.set_shader_parameter("center",focus)
		# Closed means covered: the edge starts a full feather inside the centre.
		var feather := lerpf(10.0,46.0,amount)
		iris_material.set_shader_parameter("radius",lerpf(-feather*1.5,far+feather*1.5,amount))
		iris_material.set_shader_parameter("feather",feather)
		iris_material.set_shader_parameter("rim_strength",sin(clampf(amount,0,1)*PI)*.9)
		var middle := area.y*.42
		title.position = Vector2(0,middle-title.get_combined_minimum_size().y-amount*28.0)
		title.size.x = area.x
		subtitle.position = Vector2(0,middle+4-amount*28.0)
		subtitle.size.x = area.x

# Beacon: soft pulsing rings on the two valid exits it found.
class BeaconMarks extends Control:
	var points: Array[Vector2] = []
	var time := 0.0
	var strength := 0.0
	func _draw() -> void:
		for point in points:
			var pulse := 18+6*sin(time*6)
			draw_circle(point,pulse+8,Color(CYAN,.10*strength))
			draw_arc(point,pulse,0,TAU,40,Color(CYAN,.9*strength),3,true)
			draw_arc(point,pulse+9,time*2,time*2+TAU*.6,32,Color(WHITE,.5*strength),1.5,true)

class AimOverlay extends Control:
	var origin := Vector2.ZERO
	var target := Vector2.ZERO
	var active := false
	var control_active := false
	var control_origin := Vector2.ZERO
	var control_target := Vector2.ZERO
	var control_attached := false
	var vertical_direction := 0
	var vertical_progress := 0.0
	var walk_direction := 0
	var walk_progress := 0.0
	var aim_color := MenuSurface.HOLD
	# Screen direction of the held spring's throw, zero on any other grip.
	var throw_direction := Vector2.ZERO
	var throw_color := Color.WHITE
	var trajectory := PackedVector2Array()
	var branches: Array[Dictionary] = []
	var animation := 0.0
	var ui_scale := 1.0
	func _draw() -> void:
		if active and branches.size()>1:
			for branch in branches:
				draw_trajectory(branch["points"],branch["target"],branch["color"])
		elif active:
			draw_trajectory(trajectory,target,aim_color)
		if control_active:
			draw_controls()
		if throw_direction!=Vector2.ZERO:
			draw_throw()

	# Three chevrons running out of the hero along the throw.
	func draw_throw() -> void:
			var u := ui_scale
			var across := throw_direction.orthogonal()
			for index in range(3):
				var run := fposmod(animation*1.6+index/3.0,1.0)
				var tip := origin+throw_direction*(44+run*54)*u
				var shape := PackedVector2Array([tip-throw_direction*12*u+across*13*u,tip,tip-throw_direction*12*u-across*13*u])
				var fade := sin(run*PI)
				draw_polyline(shape,Color("121b22",.45*fade),9*u,true)
				draw_polyline(shape,Color(throw_color,fade),5*u,true)

	func draw_trajectory(points: PackedVector2Array, contact: Vector2, color: Color) -> void:
			var distance := 0.0
			var spacing := 14*ui_scale
			var next_dot := fposmod(animation*28*ui_scale,spacing)
			for index in range(1,points.size()):
				var a := points[index-1]
				var b := points[index]
				var segment := a.distance_to(b)
				while next_dot<=distance+segment:
					var point := a.lerp(b,clampf((next_dot-distance)/maxf(.001,segment),0,1))
					var fade := 1-float(index)/maxi(1,points.size())*.55
					draw_circle(point,2.0*ui_scale,Color(color,fade))
					next_dot += spacing
				distance += segment
			var pulse := (6+sin(animation*5)*.8)*ui_scale
			draw_arc(contact,pulse,animation,animation+TAU*.78,24,color,1.5*ui_scale,true)

	func draw_controls() -> void:
			# A light glass ring over the rock: a faint frosted disc, a thin bright
			# rim with a soft dark edge so it still reads on sunlit limestone,
			# direction cues and a glossy thumb. The touch origin and travel stay
			# exactly as before.
			var color := CYAN if (vertical_progress>=1 if control_attached else walk_progress>=1) else MenuSurface.HOLD
			var u := ui_scale
			var radius := 48*u
			var knob := control_origin+(control_target-control_origin).limit_length(ClimbGesture.STICK_RADIUS*u)*(48/ClimbGesture.STICK_RADIUS)
			draw_circle(control_origin,radius+10*u,Color("ffffff",.05))
			draw_circle(control_origin,radius,Color("eaf4fb",.13))
			draw_circle(control_origin,radius+1.5*u,Color("121b22",.22),false,3*u,true)
			draw_circle(control_origin,radius,Color("ffffff",.62),false,1.6*u,true)
			# A lit upper rim, as if the glass caught the sun.
			draw_arc(control_origin,radius-3*u,-PI*.95,-PI*.35,32,Color("ffffff",.38),2*u,true)
			draw_circle(control_origin,radius*.62,Color("ffffff",.16),false,1*u,true)
			draw_circle(control_origin,ClimbGesture.DEAD_ZONE*u,Color(color,.10))
			# Four soft chevrons: where a pull, a lower or a walk is read.
			for angle in [-PI*.5,0.0,PI*.5,PI]:
				var direction := Vector2.from_angle(angle)
				var across := direction.orthogonal()
				var tip := control_origin+direction*(radius-7*u)
				var lit := (control_attached and absf(direction.y)>.5) or (not control_attached and absf(direction.x)>.5)
				var tone := Color(color,.85) if lit else Color("ffffff",.42)
				draw_polyline(PackedVector2Array([tip-direction*5*u+across*5*u,tip,tip-direction*5*u-across*5*u]),tone,2*u,true)
			if vertical_direction!=0 and control_attached:
				draw_arc(control_origin,radius+5*u,-PI*.5,-PI*.5+TAU*maxf(.001,vertical_progress),64,color,3.5*u,true)
			elif walk_direction!=0 and not control_attached:
				# Holding left or right on a platform fills the ring, then walks.
				var start := 0.0 if walk_direction>0 else PI
				draw_arc(control_origin,radius+5*u,start,start+TAU*maxf(.001,walk_progress),64,color,3.5*u,true)
			# A soft rail to the thumb, then the thumb: a shadow, the coloured
			# body, a highlight and a bright core.
			draw_line(control_origin,knob,Color(color,.28),6*u,true)
			draw_circle(knob+Vector2(1.5,2.5)*u,15*u,Color("0b1218",.22))
			draw_circle(knob,15*u,Color("ffffff",.88))
			draw_circle(knob,13*u,color)
			draw_circle(knob+Vector2(-3,-4)*u,6*u,Color("ffffff",.38))
			draw_arc(knob,10*u,-PI*.95,-PI*.25,24,Color("fff7df",.85),2*u,true)
			draw_circle(knob,3.5*u,Color("fff7df",.9))

func font_weight(file: FontFile, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = file
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):weight}
	return variation

func setup(controller) -> void:
	game = controller
	base_theme = Theme.new()
	# Bundled OFL fonts: Russo One's squared, chunky forms carry headings,
	# numbers and buttons; variable Onest keeps body text calm and legible.
	var display_file: FontFile = load("res://assets/fonts/RussoOne.ttf")
	var body_file: FontFile = load("res://assets/fonts/Onest.ttf")
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Segoe UI Symbol","Segoe UI","Roboto","Noto Sans"])
	for file in [display_file,body_file]:
		file.fallbacks = [system_font]
		file.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		file.set("oversampling",3.0)
	body_font = font_weight(body_file,440)
	strong_font = font_weight(body_file,640)
	heading_font = FontVariation.new()
	heading_font.base_font = display_file
	base_theme.default_font = body_font
	base_theme.default_font_size = 17
	base_theme.set_color("font_color","Label",WHITE)
	base_theme.set_font("font","Button",heading_font)
	base_theme.set_font("font","TooltipLabel",body_font)
	base_theme.set_stylebox("panel","TooltipPanel",slab_style(MenuSurface.SLATE,MenuSurface.SLATE_LIP,3))
	base_theme.set_color("font_color","TooltipLabel",WHITE)
	backdrop = LobbyView.Backdrop.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	slowmo_vignette = SlowmoVignette.new()
	slowmo_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slowmo_vignette.visible = false
	add_child(slowmo_vignette)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = base_theme
	add_child(root)
	aim_overlay = AimOverlay.new()
	aim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(aim_overlay)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(content)
	toast_chip = Panel.new()
	toast_chip.name = "Уведомление"
	toast_chip.add_theme_stylebox_override("panel",slab_style(Color(MenuSurface.SLATE,.92),MenuSurface.SLATE_LIP,3,7))
	toast_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_chip)
	toast_chip.visible = false
	toast_label = label(toast_chip,"",15,WHITE)
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ad_blocker = Control.new()
	ad_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ad_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	ad_blocker.visible = false
	add_child(ad_blocker)
	_build_exit_confirmation()
	get_viewport().size_changed.connect(_resize)
	fit_viewport()

func fit_viewport() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	wide = viewport_size.x/viewport_size.y>=1.2
	var design := Vector2(1080,660) if wide else Vector2(540,960)
	var factor := minf(viewport_size.x/design.x,viewport_size.y/design.y)
	root.scale = Vector2.ONE*factor
	root.size = viewport_size/factor
	content.size = root.size
	content.position = (root.size-Vector2(540,960))*.5 if layout_mode=="modal" else Vector2.ZERO
	if is_instance_valid(exit_overlay):
		exit_overlay.size = root.size
		exit_overlay.position = Vector2.ZERO
		if is_instance_valid(exit_dialog): exit_dialog.position = (root.size-exit_dialog.size)*.5
	backdrop.size = viewport_size
	if layout_mode!="play": slowmo_vignette.visible = false
	slowmo_vignette.size = get_viewport().get_visible_rect().size
	backdrop.visible = layout_mode!="play"
	backdrop.veil = layout_mode in ["pause","revive"]
	backdrop.art = layout_mode in ["menu","result"]
	backdrop.queue_redraw()
	if layout_mode=="menu" and is_instance_valid(lobby_view):
		lobby_view.update_layout()
	place_toast()

func _resize() -> void:
	if game.state=="play": game._reset_input()
	fit_viewport()
	if layout_mode=="play": show_play()
	elif layout_mode=="pause": show_pause()
	elif layout_mode=="revive": show_revive(revive_reason)
	elif layout_mode=="result": show_result(result_data)
	# The banner's height arrives after the menu is built: lay the menu out
	# again below it, so the header never sits under the ad.
	elif layout_mode=="menu" and is_instance_valid(lobby_view): lobby_view.update_layout()

func style(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	# A single straight segment per corner turns rounded boxes into chamfered,
	# faceted slabs that match the low-poly rock.
	box.corner_detail = 1
	box.anti_aliasing = true
	box.border_color = border
	box.set_border_width_all(1 if border.a>0 else 0)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box

# Face plus a darker lip along the bottom edge, like the lit top and shaded
# underside of a hold.
func slab_style(face: Color, lip: Color, lip_size: int = 4, cut: int = 10) -> StyleBoxFlat:
	var box := style(face,cut)
	box.border_color = lip
	box.set_border_width_all(0)
	box.border_width_bottom = lip_size
	box.border_blend = false
	return box

func chip(parent: Node, face: Color) -> PanelContainer:
	var node := PanelContainer.new()
	var box := slab_style(Color(face,.92),MenuSurface.SLATE_LIP,3,7)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 7
	node.add_theme_stylebox_override("panel",box)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

# Native overlays (the ad banner, display cut-outs) report physical pixels.
# The canvas is stretched, so convert through the window size before the root
# scale; otherwise a phone with a 2x canvas gets a double-height inset.
func screen_to_design(pixels: float) -> float:
	var ratio := 1.0
	if OS.has_feature("mobile"):
		var window := DisplayServer.window_get_size()
		if window.y>0: ratio = get_viewport().get_visible_rect().size.y/float(window.y)
	return pixels*ratio/maxf(.001,root.scale.y)

func safe_inset_top() -> float:
	if not OS.has_feature("mobile"): return 0.0
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.y<=0: return 0.0
	return screen_to_design(maxf(0.0,safe.position.y))

func safe_inset_bottom() -> float:
	if not OS.has_feature("mobile"): return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var window := DisplayServer.window_get_size()
	if safe.size.y<=0 or window.y<=0: return 0.0
	return screen_to_design(maxf(0.0,window.y-safe.end.y))

func place_toast() -> void:
	if not is_instance_valid(toast_chip): return
	var has_text: bool = not toast_label.text.is_empty() and game.hint_timer>0 and bool(game.model.profile.get("notifications",true))
	toast_chip.visible = has_text
	toast_label.visible = has_text
	if not has_text: return
	# Re-measure and re-place only when the note or the screen changes; this
	# runs every frame while a toast is shown.
	var placement := [toast_label.text,layout_mode,root.size,safe_inset_bottom(),safe_inset_top(),toast_chip.get_combined_minimum_size()]
	if placement==toast_placement: return
	toast_placement = placement
	var max_width := maxf(120.0,root.size.x-32.0)
	var text_width := body_font.get_string_size(toast_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	var wide_text := text_width>max_width-36.0
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide_text else TextServer.AUTOWRAP_OFF
	toast_label.custom_minimum_size = Vector2.ZERO
	var chip_width := maxf(120.0,minf(max_width,text_width+36.0))
	if wide_text: chip_width = max_width
	var lines := 1
	for line in toast_label.text.split("\n"):
		lines = maxi(lines,ceili(body_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x/maxf(1.0,chip_width-24.0)))
	var chip_height := 12.0+float(lines)*21.0
	toast_chip.size = Vector2(chip_width,chip_height)
	toast_label.position = Vector2(12,6)
	toast_label.size = Vector2(chip_width-24,chip_height-12)
	var safe_bottom := safe_inset_bottom()
	if layout_mode in ["pause","revive","result"]:
		# Those screens keep their actions at the bottom; the note goes on top.
		toast_chip.position = Vector2((root.size.x-toast_chip.size.x)*.5,24+safe_inset_top())
		return
	toast_chip.position = Vector2((root.size.x-toast_chip.size.x)*.5,root.size.y-(150 if layout_mode=="play" else 64)-toast_chip.size.y*.5 - safe_bottom)

func label(parent: Node, text: String, size: int = 17, color: Color = WHITE) -> Label:
	var node := Label.new()
	node.text = text
	if body_font!=null:
		node.add_theme_font_override("font",body_font)
	node.add_theme_font_size_override("font_size",roundi(size*text_scale))
	node.add_theme_color_override("font_color",color)
	# High contrast: light text over the mountain gets a dark rim.
	if bold_outline and color.get_luminance()>.5:
		node.add_theme_color_override("font_outline_color",MenuSurface.SLATE_LIP)
		node.add_theme_constant_override("outline_size",4)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable, gold: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0,51)
	node.focus_mode = Control.FOCUS_NONE
	parent.add_child(node)
	if callback.is_valid(): node.pressed.connect(callback)
	skin_button(node,"primary" if gold else "secondary")
	return node

# Tones: primary (hold yellow), secondary (stone), buy (stone on a yellow
# lip), selected (slate), ghost (text only), dark (slate over the climb).
func skin_button(node: Button, tone: String = "secondary") -> void:
	var faces := {"primary":MenuSurface.HOLD,"secondary":MenuSurface.STONE,"buy":BUY_FACE,"selected":MenuSurface.SLATE,"ghost":Color(MenuSurface.STONE,0),"dark":PLAY_PANEL}
	var lips := {"primary":MenuSurface.HOLD_LIP,"secondary":MenuSurface.STONE_LIP,"buy":MenuSurface.HOLD,"selected":MenuSurface.SLATE_LIP,"ghost":Color.TRANSPARENT,"dark":MenuSurface.SLATE_LIP}
	var inks := {"primary":MenuSurface.INK,"secondary":MenuSurface.INK,"buy":MenuSurface.INK,"selected":MenuSurface.STONE,"ghost":MenuSurface.INK_SOFT,"dark":MenuSurface.STONE}
	var face: Color = faces.get(tone,MenuSurface.STONE)
	var lip: Color = lips.get(tone,MenuSurface.STONE_LIP)
	var lip_size := 0 if tone=="ghost" else 5 if tone=="primary" else 4
	for state_name in ["normal","hover","pressed","disabled"]:
		var fill := face
		var edge := lip
		var depth := lip_size
		if state_name=="hover": fill = Color(MenuSurface.STONE,.55) if tone=="ghost" else face.lightened(.08)
		if state_name=="pressed":
			fill = Color(MenuSurface.STONE_SHADE,.7) if tone=="ghost" else face.darkened(.06)
			depth = mini(lip_size,1)
		if state_name=="disabled":
			fill = Color(MenuSurface.STONE,.0) if tone=="ghost" else Color(MenuSurface.STONE_SHADE,.75)
			edge = Color.TRANSPARENT
			depth = 0
		var box := slab_style(fill,edge,depth,9)
		# A purchase stands out from the stone row it sits on: a warm cream
		# face with a thin hold-yellow rim.
		if tone=="buy" and state_name!="disabled":
			box.border_color = BUY_RIM
			box.border_width_left = 2
			box.border_width_right = 2
			box.border_width_top = 2
		box.content_margin_left = 14
		box.content_margin_right = 14
		# Pressing sinks the face into its lip: the label moves down by the
		# depth it lost so the press reads as physical.
		box.content_margin_top = 6+lip_size-depth
		box.content_margin_bottom = 6
		if state_name=="pressed": box.expand_margin_top = -float(lip_size-depth)
		node.add_theme_stylebox_override(state_name,box)
	var focus := style(Color.TRANSPARENT,9,MenuSurface.INK)
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus",focus)
	var ink: Color = inks.get(tone,MenuSurface.INK)
	for color_name in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		node.add_theme_color_override(color_name,ink if not (tone=="ghost" and color_name!="font_color") else MenuSurface.INK)
	node.add_theme_color_override("font_disabled_color",MenuSurface.INK_FAINT)
	# The display face is reserved for the one primary action; every other
	# control uses the strong text weight so long labels still fit.
	node.add_theme_font_override("font",heading_font if tone=="primary" else strong_font)
	node.add_theme_font_size_override("font_size",18 if tone=="primary" else 16)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.clip_text = true
	if not node.has_meta("press_motion"):
		node.set_meta("press_motion",true)
		node.button_down.connect(_press_motion.bind(node,true))
		node.button_up.connect(_press_motion.bind(node,false))

# A pressed button sinks a little and springs back when released, so every
# tap answers in the same physical way.
func _press_motion(node: Button, down: bool) -> void:
	if not is_instance_valid(node): return
	node.pivot_offset = node.size*.5
	var tween := node.create_tween()
	if down: tween.tween_property(node,"scale",Vector2.ONE*.95,.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else: tween.tween_property(node,"scale",Vector2.ONE,.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func select_menu(tab: String) -> void:
	# Taps, swipes and keys slide the section in from its side (menu_slide).
	if tab not in MENU_TABS: tab = "expedition"
	menu_previous_tab = menu_tab
	menu_tab = tab
	show_menu()

# Moves one section left/right. Returns false at the first or last section.
func step_menu(direction: int, focus: String = "tab") -> bool:
	var index: int = MENU_TABS.find(menu_tab)+direction
	if index<0 or index>=MENU_TABS.size(): return false
	menu_slide = direction
	menu_focus = focus
	select_menu(MENU_TABS[index])
	return true

func effects_reduced() -> bool:
	return bool(game.model.profile["settings"]["reduce_effects"])

# Kept pages hold old fonts and colours: everything is built again.
func rebuild_all_pages() -> void:
	if layout_mode=="menu" and is_instance_valid(lobby_view): lobby_view.rebuild.call_deferred()

func toggle_loot_prices() -> void:
	set_loot_prices("near" if str(game.model.profile.get("loot_prices","always"))=="always" else "always")

func set_loot_prices(mode: String) -> void:
	game.model.profile["loot_prices"] = mode
	game.request_profile_save()

func toggle_vibration() -> void:
	game.model.profile["vibration"] = not game.model.profile.get("vibration",true)
	game.request_profile_save()

func toggle_notifications() -> void:
	game.model.profile["notifications"] = not game.model.profile.get("notifications",true)
	game.request_profile_save()

func clear() -> void:
	layout_mode = "modal"
	if is_instance_valid(level_intro): level_intro.queue_free()
	fit_viewport()
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	height_label = null
	pause_button = null
	bag_panel = null
	goal_label = null
	aim_label = null
	climb_bar = null
	rope_gauge = null
	danger_edge = null
	danger_timer = null
	height_plate = null
	bag_tray = null
	bag_total_label = null
	bag_count_label = null
	bag_toggle = null
	bag_full_chip = null
	boosts_panel = null
	slowmo_indicator = null
	wallet_plate = null
	wallet_label = null
	contract_label = null
	item_buttons.clear()
	beacon_marks = null
	swap_panel = null
	lobby_view = null
	aim_overlay.active = false
	aim_overlay.control_active = false
	aim_overlay.queue_redraw()

# Rebuilds the menu once a switch animation has played, so the new page
# lands with the control already in its final place.
func show_menu_soon(delay: float = .22) -> void:
	get_tree().create_timer(delay).timeout.connect(func():
		if layout_mode=="menu" and is_instance_valid(lobby_view): show_menu())

func show_menu() -> void:
	if layout_mode=="menu" and is_instance_valid(lobby_view):
		game.ads.set_main_menu(true)
		game.ads.set_gameplay(false)
		fit_viewport()
		lobby_view.refresh_screen()
		return
	clear()
	layout_mode = "menu"
	game.ads.set_main_menu(true)
	game.ads.set_gameplay(false)
	fit_viewport()
	var lobby := LobbyView.new()
	lobby_view = lobby
	content.add_child(lobby)
	lobby.setup(self)

# Launch splash over the menu (SplashScreen); its icon lands in the profile
# button's mini icon.
func show_splash() -> void:
	if not is_instance_valid(lobby_view): return
	var splash := SplashScreen.new()
	add_child(splash)
	splash.setup(self,lobby_view.profile_mark)

# Lowest edge of the display cut-outs (camera holes, notches) over a
# horizontal span, in design units. Bars hug the top edge and only step
# down where a cut-out actually covers them.
func cutout_bottom(x_from: float, x_to: float) -> float:
	if not OS.has_feature("mobile"): return 0.0
	var window := DisplayServer.window_get_size()
	if window.x<=0: return 0.0
	var per_pixel := root.size.x/float(window.x)
	var bottom := 0.0
	for rect in DisplayServer.get_display_cutouts():
		if rect.end.x*per_pixel>=x_from and rect.position.x*per_pixel<=x_to:
			bottom = maxf(bottom,screen_to_design(rect.end.y))
	return bottom

# Top of the climb's chrome over a span: below the display cut-outs and below
# the gameplay banner when one is shown.
func play_top(x_from: float, x_to: float, edge: float) -> float:
	var banner := screen_to_design(game.ads.play_banner_height())
	return maxf(edge+cutout_bottom(x_from,x_to),banner+(edge*.5 if banner>0.0 else 0.0))

# The level-start transition over a freshly shown play screen; the HUD
# itself fades in behind the opening iris.
func play_intro(origin: Vector2, heading: String, note: String) -> void:
	if is_instance_valid(level_intro): level_intro.queue_free()
	level_intro = LevelIntro.new()
	add_child(level_intro)
	level_intro.setup(origin,heading,note,heading_font,body_font,root.scale.x)
	content.modulate.a = 0.0
	create_tween().tween_property(content,"modulate:a",1.0,.3).set_delay(.26)

func show_play() -> void:
	game.ads.set_main_menu(false)
	game.ads.set_gameplay(true)
	clear()
	layout_mode = "play"
	fit_viewport()
	danger_edge = PlayGauges.DangerEdge.new()
	danger_edge.size = root.size
	danger_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(danger_edge)
	# In-run chrome is dark slate so it reads over the sunlit limestone; the
	# same chamfer and lip as the menus keep it part of one family. Only what
	# a climber needs mid-swing: height, route, coins, pause, bag and items.
	const EDGE := 12.0
	var width := root.size.x
	var top := Panel.new()
	top.size = Vector2(156,60)
	top.position = Vector2(EDGE,play_top(EDGE,EDGE+top.size.x,EDGE))
	top.pivot_offset = top.size*.5
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_stylebox_override("panel",slab_style(PLAY_PANEL,MenuSurface.SLATE_LIP,4,10))
	content.add_child(top)
	height_plate = top
	height_label = label(top,"0 м",30)
	height_label.add_theme_font_override("font",heading_font)
	height_label.position = Vector2(14,2)
	height_label.size = Vector2(134,38)
	record_label = label(top,"Рекорд 0 м",12,MUTED)
	record_label.position = Vector2(15,36)
	record_label.size = Vector2(134,18)
	pause_button = button(content,"",game.pause_run)
	skin_button(pause_button,"dark")
	pause_button.custom_minimum_size = Vector2(52,52)
	pause_button.size = Vector2(52,52)
	pause_button.position = Vector2(width-EDGE-52,play_top(width-EDGE-52,width-EDGE,EDGE))
	var bars := UiSymbol.new()
	bars.kind = 18
	bars.tint = WHITE
	bars.badge = false
	bars.position = Vector2(12,10)
	bars.size = Vector2(28,28)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_button.add_child(bars)
	# Coins banked during this run, beside Pause.
	wallet_plate = Panel.new()
	wallet_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_plate.add_theme_stylebox_override("panel",slab_style(PLAY_PANEL,MenuSurface.SLATE_LIP,3,8))
	wallet_plate.size = Vector2(96,40)
	var wallet_x := pause_button.position.x-8-wallet_plate.size.x
	wallet_plate.position = Vector2(wallet_x,6+play_top(wallet_x,wallet_x+wallet_plate.size.x,EDGE))
	wallet_plate.pivot_offset = wallet_plate.size*.5
	content.add_child(wallet_plate)
	var wallet_coin := UiSymbol.new()
	wallet_coin.kind = 12
	wallet_coin.tint = Color("ffd15c")
	wallet_coin.size = Vector2(20,20)
	wallet_coin.position = Vector2(10,8)
	wallet_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_plate.add_child(wallet_coin)
	wallet_label = label(wallet_plate,"0",17,WHITE)
	wallet_label.add_theme_font_override("font",heading_font)
	wallet_label.position = Vector2(35,6)
	wallet_label.size = Vector2(56,26)
	shown_wallet = float(game.model.run_coins(game.run_id))
	wallet_plate.visible = game.run_mode!="practice"
	var bar_top := maxf(top.position.y+top.size.y,pause_button.position.y+pause_button.size.y)+8.0
	climb_bar = PlayGauges.RouteGauge.new()
	climb_bar.position = Vector2(EDGE,bar_top)
	climb_bar.size = Vector2(width-EDGE*2,26)
	climb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(climb_bar)
	var below := bar_top+(climb_bar.size.y+10.0 if game.run_mode=="summit" else 0.0)
	rope_gauge = PlayGauges.RopeGauge.new()
	rope_gauge.font = heading_font
	rope_gauge.position = Vector2(width-EDGE-44,below+48.0)
	rope_gauge.size = Vector2(44,170)
	rope_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rope_gauge.visible = false
	content.add_child(rope_gauge)
	var notes := VBoxContainer.new()
	notes.position = Vector2(EDGE,below)
	notes.add_theme_constant_override("separation",6)
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(notes)
	var danger := chip(notes,MenuSurface.DANGER)
	var danger_column := VBoxContainer.new()
	danger_column.add_theme_constant_override("separation",4)
	danger_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger.add_child(danger_column)
	danger_label = label(danger_column,"",14,WHITE)
	danger_label.add_theme_font_override("font",strong_font)
	danger_timer = PlayGauges.TimerBar.new()
	danger_timer.custom_minimum_size = Vector2(0,3)
	danger_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger_column.add_child(danger_timer)
	goal_label = label(chip(notes,MenuSurface.SLATE),"",14,WHITE)
	contract_label = null
	aim_label = label(chip(notes,MenuSurface.SLATE),"",14,MenuSurface.HOLD)
	aim_label.add_theme_font_override("font",strong_font)
	for holder in notes.get_children():
		holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		holder.visible = false
	slowmo_indicator = SlowmoIndicator.new()
	slowmo_indicator.text_font = strong_font
	slowmo_indicator.number_font = heading_font
	slowmo_indicator.duration = game.model.slowmo_seconds()
	slowmo_indicator.ready_seconds = game.model.slowmo_seconds()
	slowmo_indicator.cooldown_total = maxf(.01,game.model.slowmo_cooldown())
	seen_focus_serial = game.focus_serial
	slowmo_indicator.size = Vector2(176,42)
	# Between the height plate and the coins when there is room and no
	# cut-out; otherwise centred under the route bar.
	var gap_left := top.position.x+top.size.x+8
	var gap_right := wallet_plate.position.x-8
	var centre := (gap_left+gap_right-slowmo_indicator.size.x)*.5
	if gap_right-gap_left>=slowmo_indicator.size.x and cutout_bottom(centre,centre+slowmo_indicator.size.x)<=0:
		slowmo_indicator.position = Vector2(centre,EDGE+9)
	else:
		slowmo_indicator.position = Vector2((width-slowmo_indicator.size.x)*.5,below)
	slowmo_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slowmo_indicator.visible = false
	content.add_child(slowmo_indicator)
	beacon_marks = BeaconMarks.new()
	beacon_marks.size = root.size
	beacon_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(beacon_marks)
	# Items: round buttons along the left edge, stacked up from the lower
	# corner; the bag lives on the right.
	boosts_panel = null
	var names := {"beacon":"Маяк","booster":"Ускорение","glide":"Парашют","tape":"Страховка"}
	var floor_y := root.size.y-safe_inset_bottom()-16.0
	for index in range(game.run_items.size()):
		var entry: Dictionary = game.run_items[index]
		var definition := ItemCatalog.consumable(str(entry["id"]))
		var item_button := ItemButton.new()
		item_button.index = index
		item_button.id = str(entry["id"])
		item_button.title = str(names.get(item_button.id,str(definition.get("short",definition["name"])).get_slice(" ",0)))
		item_button.passive = item_button.id=="tape"
		item_button.text_font = strong_font
		item_button.on_press = game.activate_item
		item_button.size = Vector2(84,88)
		item_button.custom_minimum_size = item_button.size
		item_button.position = Vector2(EDGE-10,floor_y-(game.run_items.size()-index)*(item_button.size.y+6))
		item_button.tooltip_text = str(definition["name"])+": "+str(definition.get("hint",""))
		content.add_child(item_button)
		item_buttons.append(item_button)
	bag_tray = Panel.new()
	bag_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_tray.add_theme_stylebox_override("panel",slab_style(Color("24323dc8"),MenuSurface.SLATE_LIP,4,12))
	content.add_child(bag_tray)
	var coin := UiSymbol.new()
	coin.kind = 12
	coin.tint = Color("ffd15c")
	coin.size = Vector2(18,18)
	coin.name = "Coin"
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_tray.add_child(coin)
	bag_total_label = label(bag_tray,"0",16,WHITE)
	bag_total_label.add_theme_font_override("font",heading_font)
	bag_count_label = label(bag_tray,"0/0",14,MUTED)
	bag_count_label.add_theme_font_override("font",strong_font)
	bag_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The header folds the bag down to its count and value and back; the
	# choice is remembered between runs.
	bag_toggle = button(bag_tray,"",toggle_bag)
	skin_button(bag_toggle,"dark")
	bag_toggle.custom_minimum_size = Vector2(60,34)
	bag_toggle.size = Vector2(60,34)
	bag_icon = UiSymbol.new()
	bag_icon.kind = 3
	bag_icon.tint = WHITE
	bag_icon.position = Vector2(8,5)
	bag_icon.size = Vector2(22,22)
	bag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_toggle.add_child(bag_icon)
	bag_chevron = UiSymbol.new()
	bag_chevron.tint = MUTED
	bag_chevron.position = Vector2(34,7)
	bag_chevron.size = Vector2(18,18)
	bag_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_toggle.add_child(bag_chevron)
	bag_full_chip = chip(content,MenuSurface.SLATE)
	label(bag_full_chip,"Рюкзак полон: удержи находку, чтобы выбросить",13,CORAL).add_theme_font_override("font",strong_font)
	bag_full_chip.visible = false
	bag_panel = VBoxContainer.new()
	bag_panel.add_theme_constant_override("separation",6)
	bag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bag_panel)
	# Opening the HUD (a new run, a resume, an unpause) shows the bag as it
	# is; only finds collected from now on get the landing bounce.
	shown_bag_ids = bag_ids()
	shown_bag_total = game.model.bag_value()
	flying_value = 0
	shown_height = maxf(0,(game.sim.pos.y-game.START_Y)*10)
	if record_run!=game.run_id:
		record_run = game.run_id
		record_at_start = game.model.record(game.selected_location if game.run_mode!="practice" else 0,game.run_mode)
		record_broken = false
		last_zone = -1
	refresh_bag()

func bag_ids() -> Array:
	var ids := []
	for item in game.model.bag: ids.append(item.get("id",-999))
	return ids

func refresh_bag() -> void:
	if not is_instance_valid(bag_panel):
		return
	var capacity: int = game.model.bag_capacity()
	if bag_panel.get_child_count()!=capacity:
		for child in bag_panel.get_children():
			bag_panel.remove_child(child)
			child.queue_free()
		for index in range(capacity):
			var cell := BagSlot.new()
			cell.custom_minimum_size = Vector2(46,46)
			cell.value_font = heading_font
			bag_panel.add_child(cell)
	var collapsed := bag_collapsed()
	var header := 34.0
	var height: float = capacity*46+(capacity-1)*6
	var tray_width := 60.0
	var tray_height := header+(52.0 if collapsed else height+48.0)
	var tray_at := Vector2(root.size.x-12-tray_width,clampf((root.size.y-tray_height)*.55,160,root.size.y-tray_height-18))
	bag_tray.position = tray_at
	bag_tray.size = Vector2(tray_width,tray_height)
	bag_chevron.kind = 10 if collapsed else 11
	bag_chevron.rotation = 0.0
	bag_chevron.queue_redraw()
	bag_panel.visible = not collapsed
	bag_count_label.visible = collapsed
	bag_count_label.text = "%d/%d" % [game.model.bag.size(),capacity]
	bag_count_label.position = Vector2(0,header+2)
	bag_count_label.size = Vector2(tray_width,20)
	var total_y := header+24.0 if collapsed else header+height+14.0
	bag_tray.get_node("Coin").position = Vector2(6,total_y+2)
	bag_total_label.position = Vector2(26,total_y-1)
	bag_total_label.size = Vector2(32,22)
	bag_panel.position = tray_at+Vector2(7,header+6)
	bag_panel.size = Vector2(46,height)
	bag_full_chip.reset_size()
	bag_full_chip.position = Vector2(tray_at.x-10-bag_full_chip.size.x,tray_at.y)
	# Cells are updated in place so their animations survive a pickup.
	for index in range(capacity):
		var cell: BagSlot = bag_panel.get_child(index)
		var item: Dictionary = game.model.bag[index] if index<game.model.bag.size() else {}
		cell.item = item
		cell.rare = not item.is_empty() and game.model.item_is_rare(item)
		cell.on_discard = _discard.bind(index) if not item.is_empty() else Callable()
		cell.special = index>=game.model.capacity()
		cell.reveal = true
		if not item.is_empty() and not shown_bag_ids.has(item.get("id",-999)): cell.pop = 1.0
		cell.queue_redraw()
	shown_bag_ids = bag_ids()

func bag_collapsed() -> bool:
	return bool(game.model.profile.get("bag_collapsed",false))

func toggle_bag() -> void:
	game.model.profile["bag_collapsed"] = not bag_collapsed()
	game.request_profile_save()
	refresh_bag()
	pulse(bag_tray,.05)

# A coin is banked at once: "+value" rises from the coin into the wallet.
func animate_coin(value: int, world_position: Vector2) -> void:
	if not is_instance_valid(wallet_plate): return
	var rise := PlayGauges.FloatText.new()
	rise.text = "+%d" % value
	rise.font = heading_font
	rise.color = Color("ffd15c")
	rise.position = content_point(game.camera.unproject_position(Vector3(world_position.x,world_position.y,0)))+Vector2(0,-20)
	content.add_child(rise)
	pulse(wallet_plate,.06)

# Kept as a compatibility entry point for older callers. Full-bag finds are
# resolved automatically by the run controller before this can be shown.
func show_swap(item: Dictionary, cheapest: Dictionary) -> void:
	hide_swap()

func hide_swap() -> void:
	if is_instance_valid(swap_panel): swap_panel.queue_free()
	swap_panel = null

func content_point(screen: Vector2) -> Vector2:
	return content.get_global_transform().affine_inverse()*screen

# A collected find arcs from the ledge into its cell, then the cell bounces,
# a ring bursts and the value floats up from the tray.
func animate_pickup(item: Dictionary, world_position: Vector2) -> void:
	if not is_instance_valid(bag_panel): return
	var index: int = bag_ids().find(item.get("id",-999))
	if index<0 or index>=bag_panel.get_child_count(): return
	var cell: BagSlot = bag_panel.get_child(index)
	cell.reveal = false
	cell.pop = 0
	var flyer := PlayGauges.PickupFlyer.new()
	flyer.item = item
	flyer.size = root.size
	flyer.from = content_point(game.camera.unproject_position(Vector3(world_position.x,world_position.y,0)))
	flyer.to = content_point(bag_tray.get_global_rect().get_center() if bag_collapsed() else cell.get_global_rect().get_center())
	flyer.landed = _land_pickup.bind(cell,item)
	# The tray total waits for the find to arrive before counting it.
	flying_value += int(item.get("value",0))
	content.add_child(flyer)

func _land_pickup(cell: BagSlot, item: Dictionary) -> void:
	flying_value = maxi(0,flying_value-int(item.get("value",0)))
	if not is_instance_valid(cell) or not is_instance_valid(content): return
	cell.land()
	var center := content_point(cell.get_global_rect().get_center())
	if bag_collapsed():
		center = content_point(bag_tray.get_global_rect().get_center())
		pulse(bag_tray,.08)
	var burst := PlayGauges.Burst.new()
	burst.color = LootIcon.rarity_color(item)
	burst.position = center
	content.add_child(burst)
	var rise := PlayGauges.FloatText.new()
	rise.text = "+%d" % int(item.get("value",0))
	rise.font = heading_font
	rise.color = Color("ffd15c")
	rise.position = center+Vector2(0,-14)
	content.add_child(rise)

func _discard(index: int) -> void:
	if is_instance_valid(bag_panel) and index<bag_panel.get_child_count() and index<game.model.bag.size():
		var ghost := PlayGauges.DiscardGhost.new()
		ghost.item = game.model.bag[index]
		ghost.position = content_point((bag_panel.get_child(index) as Control).get_global_rect().get_center())
		content.add_child(ghost)
	game.model.discard(index)
	refresh_bag()
	game.save_snapshot()

# Note chips wrap before the rope gauge instead of running under it or off
# the screen; short notes keep their natural single line.
func fit_notes() -> void:
	var notes: Control = aim_label.get_parent().get_parent()
	var limit := rope_gauge.position.x-8-notes.position.x-24
	for note in [danger_label,goal_label,aim_label]:
		var font: Font = note.get_theme_font("font")
		var wide := font.get_string_size(note.text,HORIZONTAL_ALIGNMENT_LEFT,-1,note.get_theme_font_size("font_size")).x>limit
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide else TextServer.AUTOWRAP_OFF
		note.custom_minimum_size.x = limit if wide else 0.0

func show_chip(holder: Control, wanted: bool) -> void:
	if wanted and not holder.visible:
		holder.modulate.a = 0
		create_tween().tween_property(holder,"modulate:a",1.0,.16)
	holder.visible = wanted

func pulse(node: Control, amount: float = .08) -> void:
	node.pivot_offset = node.size*.5
	var tween := create_tween()
	tween.tween_property(node,"scale",Vector2.ONE*(1+amount),.09).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node,"scale",Vector2.ONE,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func update_play() -> void:
	toast_label.visible = game.model.profile.get("notifications",true) and game.hint_timer>0 and game.state in ["play","menu","revive"]
	toast_chip.visible = toast_label.visible
	if toast_chip.visible: place_toast()
	if not is_instance_valid(height_label) or game.state!="play":
		return
	if is_instance_valid(slowmo_indicator):
		slowmo_indicator.remaining = game.focus_remaining if game.focus_active() else 0.0
		slowmo_indicator.duration = maxf(.01,game.focus_duration)
		slowmo_indicator.cooldown = game.focus_cooldown
		slowmo_indicator.visible = slowmo_indicator.state_name()!="ready"
		slowmo_indicator.queue_redraw()
		if game.focus_serial!=seen_focus_serial:
			# Activation: the chip pops and the screen rim flashes once.
			seen_focus_serial = game.focus_serial
			if game.focus_active():
				pulse(slowmo_indicator,.14)
				if not effects_reduced(): slowmo_vignette.flash = 1.0
	slowmo_vignette.visible = layout_mode=="play" and not effects_reduced()
	if slowmo_vignette.visible:
		slowmo_vignette.strength = game.focus_visual()
		slowmo_vignette.time = game.elapsed
		slowmo_vignette.flash = move_toward(slowmo_vignette.flash,0.0,get_process_delta_time()*3.5)
		slowmo_vignette.queue_redraw()
	var delta := get_process_delta_time()
	var height := maxf(0,(game.sim.pos.y-game.START_Y)*10)
	# The counter rolls toward the real height instead of jumping.
	shown_height = lerpf(shown_height,height,1-exp(-14*delta)) if absf(shown_height-height)>.5 else height
	height_label.text = "%d м" % int(shown_height)
	var climbed := maxf(0,(game.sim.highest-game.START_Y)*10)
	if record_at_start>0 and climbed>record_at_start and not record_broken and game.run_mode!="practice":
		record_broken = true
		pulse(height_plate,.12)
	record_label.text = "Новый рекорд!" if record_broken else "Рекорд %d м" % int(record_at_start)
	# A theme override notifies and re-lays out the label: set it only on change.
	var record_color := MenuSurface.HOLD if record_broken else MUTED
	if record_label.get_theme_color("font_color")!=record_color: record_label.add_theme_color_override("font_color",record_color)
	var remaining: float = game.sim.pos.y-game.screen_bottom_y()
	var danger: bool = game.sim.launched and remaining<4
	# Act hazards announce themselves here when the lower edge is not closer.
	danger_label.text = "Нижний край близко — цепляйся выше!" if danger else game.world.hazards.hint(game.sim.pos,game.hazard_clock) if game.world.hazards!=null else ""
	climb_bar.value = clampf((game.sim.highest-game.START_Y)/game.summit_height,0,1)
	climb_bar.record = clampf(record_at_start/(game.summit_height*10),0,1)
	climb_bar.visible = game.run_mode=="summit"
	var reached_zone := clampi(int(maxf(0,game.sim.highest-game.START_Y)/20),0,5)
	if last_zone>=0 and reached_zone>last_zone:
		climb_bar.flash = 0.0 if effects_reduced() else 1.0
		climb_bar.flash_at = float(reached_zone)/climb_bar.zones
		pulse(height_plate)
	last_zone = reached_zone
	# The goal chip only teaches: once the controls are learned it stays away.
	goal_label.text = tutorial_hint()
	aim_overlay.active = game.pressed and not game.sim.attached and not game.bolt_active and (not game.touch_gesture or game.aim_stick_valid)
	aim_overlay.ui_scale = root.scale.x
	aim_overlay.control_active = game.pressed and game.touch_gesture
	aim_overlay.control_origin = game.press_start
	aim_overlay.control_target = game.pointer
	aim_overlay.control_attached = game.sim.attached
	aim_overlay.vertical_direction = int(game.touch_controls.get("vertical_direction",0))
	aim_overlay.vertical_progress = float(game.touch_controls.get("vertical_progress",0))
	aim_overlay.walk_direction = int(game.touch_controls.get("horizontal_direction",0)) if game.can_walk() else 0
	aim_overlay.walk_progress = float(game.touch_controls.get("walk_progress",0))
	aim_overlay.origin = game.camera.unproject_position(Vector3(game.sim.pos.x,game.sim.pos.y,0))
	var point: Vector2 = game.sim.pos+game.aim_direction*game.model.shot_range()
	aim_label.text = ""
	# Rope length lives in the side gauge and the aim in the arc itself; the
	# chip speaks only when a grip behaves unusually.
	var reel := 0
	var throw_direction := Vector2.ZERO
	if game.sim.attached:
		var parts: Array[String] = []
		var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not current.is_empty():
			if not current.get("permanent",true): parts.append("Опора исчезнет при отпускании")
			if GripSpec.kind_of(current)==GripSpec.SPRING:
				parts.append("отпусти — подбросит по стрелке")
				var throw_exit := GripSpec.exit_direction(current)
				throw_direction = Vector2(throw_exit.x,-throw_exit.y)
				aim_overlay.throw_color = game.world.profile_at(current["pos"].y).paint_color(GripSpec.SPRING)
			elif GripSpec.plate(current):
				var slide := GripSpec.slide_direction(current)
				throw_direction = Vector2(slide.x,-slide.y)
				aim_overlay.throw_color = game.world.profile_at(current["pos"].y).paint_color(GripSpec.ICE)
		if game.pressed and game.touch_gesture and aim_overlay.vertical_direction!=0 and aim_overlay.vertical_progress>=1:
			reel = aim_overlay.vertical_direction
		aim_label.text = " · ".join(parts)
		if reel==0 and absf(game.sim.target_length-game.sim.length)>.02:
			reel = 1 if game.sim.target_length<game.sim.length else -1
	aim_overlay.throw_direction = throw_direction
	if throw_direction!=Vector2.ZERO: aim_overlay.animation = game.animation_time
	rope_gauge.active = game.sim.attached
	danger_edge.strength = clampf(game.camera_dip/.6,0,1)
	danger_edge.edge_y = content_point(game.camera.unproject_position(Vector3(game.sim.pos.x,game.screen_bottom_y(),0))).y
	danger_edge.queue_redraw()
	rope_gauge.ratio = game.sim.length/maxf(.1,game.model.shot_range())
	rope_gauge.meters = roundi(game.sim.length*10)
	rope_gauge.direction = reel
	aim_overlay.aim_color = MenuSurface.HOLD
	if aim_overlay.active:
		# The forecast sweeps up to 240 steps per hook. Rebuild it about 20 times
		# a second as the hero moves, and at once only for a real turn of aim:
		# finger jitter below PREVIEW_TURN waits for the next refresh.
		var age: float = game.elapsed-shot_preview_time
		if shot_preview.is_empty() or age>=PREVIEW_INTERVAL or age<0 or shot_preview_direction.dot(game.aim_direction)<PREVIEW_TURN:
			shot_preview = game.predict_shot(game.aim_direction)
			shot_preview_time = game.elapsed
			shot_preview_direction = game.aim_direction
		point = shot_preview["contact"]
		aim_overlay.trajectory = PackedVector2Array()
		for sample in shot_preview["points"]:
			aim_overlay.trajectory.append(game.camera.unproject_position(Vector3(sample.x,sample.y,0)))
		aim_overlay.branches.clear()
		for branch in shot_preview.get("branches",[]):
			var points := PackedVector2Array()
			for sample in branch["points"]: points.append(game.camera.unproject_position(Vector3(sample.x,sample.y,0)))
			var hit: Dictionary = branch["collision"]
			var color := MenuSurface.HOLD if hit.is_empty() else CORAL if hit.get("blocked",false) or not branch["reachable"] else Color("8ae0ac")
			var contact: Vector2 = branch["contact"]
			aim_overlay.branches.append({"points":points,"target":game.camera.unproject_position(Vector3(contact.x,contact.y,0)),"color":color})
		aim_overlay.animation = game.animation_time
		# The arc's colour already says hit or miss; words only for a miss.
		var collision: Dictionary = shot_preview["collision"]
		if not collision.is_empty():
			point = collision["contact"]
			if collision.get("blocked",false):
				aim_label.text = "Карниз: можно приземлиться сверху" if collision.get("object",{}).get("rest",false) else "Твёрдый выступ: крюк не зацепится"
				aim_overlay.aim_color = CORAL
			else:
				aim_overlay.aim_color = Color("8ae0ac")
				if not shot_preview["reachable"]:
					aim_overlay.aim_color = CORAL
					aim_label.text = "Каната не хватит до цели"
	else:
		shot_preview.clear()
		aim_overlay.branches.clear()
	aim_overlay.target = game.camera.unproject_position(Vector3(point.x,point.y,0))
	aim_overlay.queue_redraw()
	if game.sim.attached and not danger:
		var grip: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not grip.is_empty() and GripSpec.timed(grip):
			danger_label.text = "Корень сломается через %.1f с" % GripSpec.seconds_left(grip,game.anchor_time)
			danger_timer.value = GripSpec.seconds_left(grip,game.anchor_time)/GripSpec.ROOT_SECONDS
		elif not grip.is_empty() and GripSpec.kind_of(grip)==GripSpec.ICE:
			danger_label.text = "Лёд: сорвёшься через %s с" % GripSpec.timer_text(maxf(0,GripSpec.seconds_to_slip(grip,game.anchor_contact)-game.anchor_time)) if GripSpec.plate(grip) else "Лёд скользит — готовь следующий бросок"
		elif not grip.is_empty() and GripSpec.fork(grip):
			danger_label.text = "Развилка: в обход — сокровища, прямо — быстрее"
		elif not grip.is_empty() and not GripSpec.choice_exits(grip).is_empty():
			danger_label.text = "Кристалл: два выхода подсвечены — выбирай"
	danger_timer.visible = danger_label.text.begins_with("Корень")
	show_chip(danger_label.get_parent().get_parent(),not danger_label.text.is_empty())
	for note in [goal_label,aim_label]:
		show_chip(note.get_parent(),not note.text.is_empty())
	var total := float(game.model.bag_value()-flying_value)
	shown_bag_total = move_toward(shown_bag_total,total,maxf(40,absf(total-shown_bag_total)*6)*delta)
	bag_total_label.text = str(int(round(shown_bag_total)))
	bag_count_label.text = "%d/%d" % [game.model.bag.size(),game.model.bag_capacity()]
	bag_full_chip.visible = false
	var gold := float(game.model.run_coins(game.run_id))
	shown_wallet = move_toward(shown_wallet,gold,maxf(30,absf(gold-shown_wallet)*5)*delta)
	wallet_label.text = str(int(round(shown_wallet)))
	fit_notes()
	for button_index in range(item_buttons.size()):
		var item_button: ItemButton = item_buttons[button_index]
		var entry: Dictionary = game.run_items[button_index] if button_index<game.run_items.size() else {}
		var mine: bool = game.item_effect_id()==str(entry.get("id","")) and int(game.item_effect.get("index",button_index))==button_index
		item_button.used = bool(entry.get("used",false))
		item_button.armed = mine and game.item_armed()
		item_button.running = float(game.item_effect.get("remaining",0))/maxf(.01,float(game.item_effect.get("duration",1))) if mine and not game.item_armed() else 0.0
		# Dim while another item runs or this one has nothing to act on.
		# The beacon's exit search is costly, so it is refreshed a few times a second.
		if game.elapsed-item_check_time>=.25 or game.elapsed<item_check_time:
			item_button.unavailable = not game.item_blocked_reason(item_button.id).is_empty()
		item_button.blocked = not item_button.passive and ((not game.item_effect.is_empty() and not mine) or item_button.unavailable)
		item_button.queue_redraw()
	if game.elapsed-item_check_time>=.25 or game.elapsed<item_check_time: item_check_time = game.elapsed
	beacon_marks.points.clear()
	for target in game.beacon_targets: beacon_marks.points.append(content_point(game.camera.unproject_position(Vector3(target.x,target.y,0))))
	beacon_marks.time = game.elapsed
	beacon_marks.strength = clampf(float(game.item_effect.get("remaining",0))/.4,0,1) if game.item_effect_id()=="beacon" else 0.0
	beacon_marks.queue_redraw()

func contract_text() -> String:
	return ""

func tutorial_hint() -> String:
	var learned: Array = game.model.profile["learned_controls"]
	var mobile := touch_controls_hint
	if bool(game.model.profile["settings"]["persistent_hints"]) and learned.size()>=4: return _reminder_hint(mobile)
	if "aim" not in learned:
		return "Коснись где удобно, потяни как стик и отпусти" if mobile else "Зажми ЛКМ, прицелься в выступ и отпусти"
	if not game.sim.attached:
		return ("Потяни от места касания и отпусти" if mobile else "В полёте прицелься и поймай следующую опору") if game.catches<2 else ""
	if "swing" not in learned:
		return "Удерживай палец и веди влево/вправо: раскачайся" if mobile else "%s / %s: раскачайся в такт движению" % [_key("swing_left"),_key("swing_right")]
	if "rope" not in learned:
		return "Держи строго вверх / вниз: после паузы канат движется" if mobile else "%s / %s или колесо: измени длину каната" % [_key("rope_up"),_key("rope_down")]
	if "release" not in learned:
		return "Отпусти палец — отцепись. Затем снова прицелься" if mobile else "%s: отпусти канат на взлёте и целься снова" % _key("release")
	return ""

# Once everything is learned, the same chip keeps a one-line reminder.
func _reminder_hint(mobile: bool) -> String:
	if not game.sim.attached:
		return "Потяни от места касания и отпусти" if mobile else "Зажми ЛКМ, прицелься и отпусти"
	if mobile: return "Влево/вправо: раскачка · вверх/вниз: длина · отпусти: отцепись"
	return "%s / %s: раскачка · %s / %s: длина · %s: отцепись" % [_key("swing_left"),_key("swing_right"),_key("rope_up"),_key("rope_down"),_key("release")]

func _key(action_name: String) -> String:
	return KeyBindings.short_text(game.model.profile["settings"]["key_bindings"],action_name)

# The pause button, a little larger than drawn so a hurried second finger
# still finds it.
func pause_at(point: Vector2) -> bool:
	return is_instance_valid(pause_button) and pause_button.visible and pause_button.get_global_rect().grow(10).has_point(point)

func item_button_at(point: Vector2) -> bool:
	for item_button in item_buttons:
		if is_instance_valid(item_button) and item_button.get_global_rect().has_point(point): return true
	return false

func world_input_allowed(point: Vector2) -> bool:
	if not get_viewport().get_visible_rect().has_point(point): return false
	if is_instance_valid(pause_button) and pause_button.get_global_rect().has_point(point): return false
	if is_instance_valid(bag_panel) and bag_panel.get_global_rect().has_point(point): return false
	if is_instance_valid(bag_tray) and bag_tray.get_global_rect().has_point(point): return false
	if is_instance_valid(swap_panel) and swap_panel.get_global_rect().has_point(point): return false
	for item_button in item_buttons:
		if is_instance_valid(item_button) and item_button.get_global_rect().has_point(point): return false
	return true

func set_toast(text: String) -> void:
	toast_label.text = text
	var has_text: bool = not text.is_empty() and game.hint_timer>0 and bool(game.model.profile.get("notifications",true))
	toast_chip.visible = has_text
	toast_label.visible = has_text
	if has_text: place_toast()

func show_workshop() -> void:
	show_menu()

func _buy_upgrade(kind: String) -> void:
	var level_before: int = game.model.level(kind)
	var message: String = game.model.purchase(kind)
	# The rebuilt row celebrates a real level change only.
	upgrade_flash = kind if game.model.level(kind)>level_before else ""
	if kind in [GameModel.RADIUS,GameModel.DOUBLE]:
		# The climber is only built when hooks change, never on a section switch.
		if game.state=="menu": game.ensure_menu_explorer()
		if is_instance_valid(game.explorer): game.explorer.set_hook_configuration(game.model.hook_tips(),game.model.hook_count())
	show_menu()
	game.toast(message)

func show_locations() -> void:
	show_menu()

func menu_surface(mode: String) -> ExpeditionMenu:
	game.ads.set_main_menu(false)
	game.ads.set_gameplay(false)
	clear()
	layout_mode = mode
	fit_viewport()
	content.position = Vector2.ZERO
	var screen := ExpeditionMenu.new()
	content.add_child(screen)
	screen.prepare(self)
	return screen

func show_pause() -> void:
	menu_surface("pause").build_pause()

func show_revive(reason: String = "Падение") -> void:
	revive_reason = reason
	menu_surface("revive").build_revive(reason)

func show_result(result: Dictionary) -> void:
	result_data = result.duplicate(true)
	backdrop.show_route(game.selected_location)
	menu_surface("result").build_result(result)

func set_ad_blocked(blocked: bool) -> void:
	ad_blocker.visible = blocked

func _build_exit_confirmation() -> void:
	exit_overlay = Control.new()
	exit_overlay.name = "Подтверждение выхода"
	exit_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_overlay.visible = false
	root.add_child(exit_overlay)
	var veil := ColorRect.new()
	veil.color = Color("0b1218b8")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exit_overlay.add_child(veil)
	exit_dialog = Panel.new()
	exit_dialog.name = "Диалог выхода"
	exit_dialog.size = Vector2(430,230)
	exit_dialog.add_theme_stylebox_override("panel",slab_style(Color("24323df7"),MenuSurface.SLATE_LIP,5,12))
	exit_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_overlay.add_child(exit_dialog)
	var title := label(exit_dialog,"Выйти из игры?",22,WHITE)
	title.position = Vector2(24,24)
	title.size = Vector2(382,34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var message := label(exit_dialog,"Прогресс текущего восхождения сохранён.",15,MUTED)
	message.position = Vector2(24,68)
	message.size = Vector2(382,48)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stay := button(exit_dialog,"Остаться",hide_exit_confirmation)
	stay.position = Vector2(24,150)
	stay.size = Vector2(184,54)
	var leave := button(exit_dialog,"Выйти",game.exit_app,true)
	leave.position = Vector2(222,150)
	leave.size = Vector2(184,54)

func show_exit_confirmation() -> void:
	if not is_instance_valid(exit_overlay): return
	exit_overlay.visible = true
	exit_overlay.move_to_front()
	exit_dialog.position = (root.size-exit_dialog.size)*.5
	exit_dialog.pivot_offset = exit_dialog.size*.5
	exit_dialog.scale = Vector2.ONE*.92
	exit_dialog.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(exit_dialog,"scale",Vector2.ONE,.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(exit_dialog,"modulate:a",1.0,.16).set_trans(Tween.TRANS_SINE)

func hide_exit_confirmation() -> void:
	if not is_instance_valid(exit_overlay): return
	exit_overlay.visible = false

func exit_confirmation_visible() -> bool:
	return is_instance_valid(exit_overlay) and exit_overlay.visible
