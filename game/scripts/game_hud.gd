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
var shown_height := 0.0
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
var bag_panel: HBoxContainer
var pause_button: Button
var aim_overlay: AimOverlay
var base_theme: Theme
var body_font: Font
var heading_font: FontVariation
var backdrop: LobbyView.Backdrop
var layout_mode := "modal"
var menu_tab := "expedition"
# Equipment tab: "upgrades" (buy levels) or "supplies" (run profiles, items).
var equipment_view := "upgrades"
const MENU_TABS := ["expedition","equipment","settings"]
# Direction of the last menu change (-1 back, 1 forward, 0 none): the next
# LobbyView slides its body in from that side and moves the tab marker.
var menu_slide := 0
var menu_previous_tab := "expedition"
# Which control should take keyboard/controller focus after a swipe or key:
# "tab", "start" or "".
var menu_focus := ""
var upgrade_flash := -1
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
var touch_controls_hint := OS.has_feature("mobile")
var strong_font: FontVariation
var hud_chips: Array[PanelContainer] = []
var toast_chip: PanelContainer
const INK := MenuSurface.INK
const GOLD := MenuSurface.HOLD
const WHITE := MenuSurface.STONE
const MUTED := Color("c9d2d8")
const CYAN := MenuSurface.CRYSTAL_LIGHT
const CORAL := Color("ff8f70")
const INK_PANEL := MenuSurface.SLATE
const PLAY_PANEL := Color("24323deb")

class SlowmoIndicator extends Control:
	# Three readable states of the release slow motion: ready (quiet, shows the
	# upgraded duration), active (gold frame, seconds left) and cooldown.
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
		var cooling := not active and cooldown>0
		# Compact slab in the top bar: it reads at a glance over sky and sunlit
		# rock without covering the play area.
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color("141d24f2") if active else Color("24323dc8")
		panel.border_color = GOLD if active else Color(MUTED,.45) if cooling else Color(GOLD,.55)
		panel.set_border_width_all(2 if active else 1)
		panel.border_width_bottom = 4 if active else 3
		panel.set_corner_radius_all(8)
		panel.corner_detail = 1
		draw_style_box(panel,Rect2(Vector2.ZERO,size))
		var track := Rect2(12,size.y-15,size.x-24,6)
		draw_rect(track,Color(WHITE,.18))
		if active:
			draw_string(font,Vector2(12,25),"ЗАМЕДЛЕНИЕ",HORIZONTAL_ALIGNMENT_LEFT,size.x-80,15,WHITE)
			draw_string(digits,Vector2(12,26),("%.1f с" % remaining).replace(".",","),HORIZONTAL_ALIGNMENT_RIGHT,size.x-24,19,GOLD)
			draw_rect(Rect2(track.position,Vector2(track.size.x*clampf(remaining/maxf(.01,duration),0,1),track.size.y)),GOLD)
		elif cooling:
			draw_string(font,Vector2(12,25),"Перезарядка",HORIZONTAL_ALIGNMENT_LEFT,size.x-80,14,MUTED)
			draw_string(digits,Vector2(12,26),("%.1f с" % cooldown).replace(".",","),HORIZONTAL_ALIGNMENT_RIGHT,size.x-24,17,MUTED)
			draw_rect(Rect2(track.position,Vector2(track.size.x*clampf(1-cooldown/maxf(.01,cooldown_total),0,1),track.size.y)),Color(CYAN,.75))
		else:
			draw_string(font,Vector2(12,25),"Замедление готово",HORIZONTAL_ALIGNMENT_LEFT,size.x-70,14,WHITE)
			draw_string(digits,Vector2(12,26),LobbyView.seconds_text(ready_seconds),HORIZONTAL_ALIGNMENT_RIGHT,size.x-24,15,GOLD)
			draw_rect(track,Color(GOLD,.55))

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

# An active item of the run. Tap to use; ready, running (gold frame with the
# time left), passive (the strap triggers by itself) or spent.
class ItemButton extends Control:
	var index := 0
	var title := ""
	var used := false
	var passive := false
	var running := 0.0
	var text_font: Font
	var on_press := Callable()
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(event: InputEvent) -> void:
		# Touch arrives as emulated mouse, so one press is one activation.
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			if on_press.is_valid(): on_press.call(index)
	func _draw() -> void:
		var font := text_font if text_font!=null else ThemeDB.fallback_font
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color("141d24f2") if running>0 else Color("24323d",.55 if used else .86)
		panel.border_color = GOLD if running>0 else Color(MUTED,.3) if used else Color(CYAN,.7)
		panel.set_border_width_all(2 if running>0 else 1)
		panel.border_width_bottom = 4 if not used else 2
		panel.set_corner_radius_all(9)
		panel.corner_detail = 1
		draw_style_box(panel,Rect2(Vector2.ZERO,size))
		draw_string(font,Vector2(0,size.y*.46),title,HORIZONTAL_ALIGNMENT_CENTER,size.x,13,Color(WHITE,.45) if used else WHITE)
		var note := "исп." if used else "авто" if passive else "1"
		draw_string(font,Vector2(0,size.y-9),note,HORIZONTAL_ALIGNMENT_CENTER,size.x,11,Color(MUTED,.6) if used else GOLD)
		if running>0:
			draw_arc(size*.5,minf(size.x,size.y)*.5-3,-PI*.5,-PI*.5+TAU*running,40,GOLD,3,true)

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
	var aim_color := GOLD
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
			var color := CYAN if (vertical_progress>=1 if control_attached else walk_progress>=1) else GOLD
			var radius := 48*ui_scale
			var knob := control_origin+(control_target-control_origin).limit_length(ClimbGesture.STICK_RADIUS*ui_scale)*(48/ClimbGesture.STICK_RADIUS)
			# Layered ring treatment keeps the control legible over bright terrain while
			# preserving the original touch origin and travel distance.
			draw_circle(control_origin,radius+13*ui_scale,Color("121b22",.20))
			draw_circle(control_origin,radius+8*ui_scale,Color("24323d",.45))
			draw_arc(control_origin,radius+8*ui_scale,-PI*.15,PI*1.15,64,Color(color,.24),1.5*ui_scale,true)
			draw_circle(control_origin,radius,Color("24323d",.80))
			draw_circle(control_origin,radius,Color(color,.62),false,1.5*ui_scale,true)
			draw_circle(control_origin,radius-8*ui_scale,Color("efebe1",.16),false,1*ui_scale,true)
			draw_circle(control_origin,ClimbGesture.DEAD_ZONE*ui_scale,Color(color,.12))
			draw_circle(control_origin,ClimbGesture.DEAD_ZONE*ui_scale,Color(color,.52),false,1*ui_scale,true)
			if control_attached:
				for axis_angle in [-PI*.5,PI*.5]:
					for side in [-1,1]:
						var angle: float = axis_angle+side*deg_to_rad(15)
						draw_line(control_origin,control_origin+Vector2.from_angle(angle)*(radius-5*ui_scale),Color(color,.18),ui_scale,true)
				for angle in [-PI*.5,0,PI*.5,PI]:
					var tick := control_origin+Vector2.from_angle(angle)*(radius+3*ui_scale)
					draw_circle(tick,2*ui_scale,Color(color,.72))
			if vertical_direction!=0 and control_attached:
				draw_arc(control_origin,radius+7*ui_scale,-PI*.5,-PI*.5+TAU*maxf(.001,vertical_progress),64,color,3*ui_scale,true)
			elif walk_direction!=0 and not control_attached:
				# Holding left or right on a platform fills the ring, then walks.
				var start := 0.0 if walk_direction>0 else PI
				draw_arc(control_origin,radius+7*ui_scale,start,start+TAU*maxf(.001,walk_progress),64,color,3*ui_scale,true)
			# Direction rail and a raised, high-contrast thumb make the drag state obvious.
			draw_line(control_origin,knob,Color(color,.35),5*ui_scale,true)
			draw_circle(knob,13*ui_scale,Color("121b22",.60))
			draw_circle(knob,10*ui_scale,color)
			draw_circle(knob,5*ui_scale,Color("fff7df",.72))
			draw_arc(knob,10*ui_scale,-PI*.85,PI*.05,24,Color("fff7df",.8),1.5*ui_scale,true)

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
	toast_chip = chip(root,MenuSurface.SLATE)
	toast_label = label(toast_chip,"",15,WHITE)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ad_blocker = Control.new()
	ad_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ad_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	ad_blocker.visible = false
	add_child(ad_blocker)
	get_viewport().size_changed.connect(_resize)
	fit_viewport()

func fit_viewport() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if layout_mode=="menu":
		var banner_pixels: int = game.ads.menu_banner_height()
		viewport_size.y -= banner_pixels*viewport_size.y/maxf(1,DisplayServer.window_get_size().y)
	wide = viewport_size.x/viewport_size.y>=1.2
	var design := Vector2(1080,660) if wide else Vector2(540,960)
	var factor := minf(viewport_size.x/design.x,viewport_size.y/design.y)
	root.scale = Vector2.ONE*factor
	root.size = viewport_size/factor
	content.size = root.size
	content.position = (root.size-Vector2(540,960))*.5 if layout_mode=="modal" else Vector2.ZERO
	backdrop.size = viewport_size
	if layout_mode!="play": slowmo_vignette.visible = false
	slowmo_vignette.size = get_viewport().get_visible_rect().size
	backdrop.visible = layout_mode!="play"
	backdrop.veil = layout_mode in ["pause","revive"]
	backdrop.queue_redraw()
	place_toast()

func _resize() -> void:
	if game.state=="play": game._reset_input()
	fit_viewport()
	if layout_mode=="menu": show_menu()
	elif layout_mode=="play": show_play()
	elif layout_mode=="pause": show_pause()
	elif layout_mode=="revive": show_revive(revive_reason)
	elif layout_mode=="result": show_result(result_data)

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

func place_toast() -> void:
	if not is_instance_valid(toast_chip): return
	var wide_text := body_font.get_string_size(toast_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x>440
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide_text else TextServer.AUTOWRAP_OFF
	toast_label.custom_minimum_size = Vector2(440 if wide_text else 0,0)
	toast_chip.reset_size()
	toast_chip.position = Vector2((root.size.x-toast_chip.size.x)*.5,root.size.y-(150 if layout_mode=="play" else 64)-toast_chip.size.y*.5)

func label(parent: Node, text: String, size: int = 17, color: Color = WHITE) -> Label:
	var node := Label.new()
	node.text = text
	if body_font!=null:
		node.add_theme_font_override("font",body_font)
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable, gold: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0,51)
	node.focus_mode = Control.FOCUS_NONE
	parent.add_child(node)
	node.pressed.connect(callback)
	skin_button(node,"primary" if gold else "secondary")
	return node

# Tones: primary (hold yellow), secondary (stone), buy (stone on a yellow
# lip), selected (slate), ghost (text only), dark (slate over the climb).
func skin_button(node: Button, tone: String = "secondary") -> void:
	var faces := {"primary":MenuSurface.HOLD,"secondary":MenuSurface.STONE,"buy":MenuSurface.STONE,"selected":MenuSurface.SLATE,"ghost":Color(MenuSurface.STONE,0),"dark":PLAY_PANEL}
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

func select_menu(tab: String) -> void:
	# A tap fades the section in; swipes and keys also slide it (menu_slide).
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

func toggle_sound() -> void:
	game.model.profile["sound"] = not game.model.profile.get("sound",true)
	game.model.save()
	if not game.model.profile["sound"]: game.audio.stop()
	show_menu()

func toggle_loot_prices() -> void:
	set_loot_prices("near" if str(game.model.profile.get("loot_prices","near"))=="always" else "always")

func set_loot_prices(mode: String) -> void:
	game.model.profile["loot_prices"] = mode
	game.model.save()
	show_menu()

func toggle_vibration() -> void:
	game.model.profile["vibration"] = not game.model.profile.get("vibration",true)
	game.model.save()
	show_menu()

func toggle_notifications() -> void:
	game.model.profile["notifications"] = not game.model.profile.get("notifications",true)
	game.model.save()
	show_menu()

func clear() -> void:
	layout_mode = "modal"
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
	bag_full_chip = null
	slowmo_indicator = null
	wallet_plate = null
	wallet_label = null
	contract_label = null
	item_buttons.clear()
	beacon_marks = null
	swap_panel = null
	aim_overlay.active = false
	aim_overlay.control_active = false
	aim_overlay.queue_redraw()

func show_menu() -> void:
	clear()
	layout_mode = "menu"
	game.ads.set_main_menu(true)
	fit_viewport()
	var lobby := LobbyView.new()
	content.add_child(lobby)
	lobby.setup(self)

func show_play() -> void:
	game.ads.set_main_menu(false)
	clear()
	layout_mode = "play"
	fit_viewport()
	danger_edge = PlayGauges.DangerEdge.new()
	danger_edge.size = root.size
	danger_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(danger_edge)
	# In-run chrome is dark slate so it reads over the sunlit limestone; the
	# same chamfer and lip as the menus keep it part of one family.
	var top := Panel.new()
	top.position = Vector2(20,20)
	top.size = Vector2(196,74)
	top.pivot_offset = top.size*.5
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_stylebox_override("panel",slab_style(PLAY_PANEL,MenuSurface.SLATE_LIP,4,10))
	content.add_child(top)
	height_plate = top
	height_label = label(top,"0 м",34)
	height_label.add_theme_font_override("font",heading_font)
	height_label.position = Vector2(16,2)
	height_label.size = Vector2(170,44)
	record_label = label(top,"Рекорд 0 м",13,MUTED)
	record_label.position = Vector2(17,44)
	record_label.size = Vector2(170,20)
	pause_button = button(content,"",game.pause_run)
	skin_button(pause_button,"dark")
	pause_button.position = Vector2(root.size.x-76,20)
	pause_button.custom_minimum_size = Vector2(56,56)
	pause_button.size = Vector2(56,56)
	var bars := UiSymbol.new()
	bars.kind = 18
	bars.tint = WHITE
	bars.badge = false
	bars.position = Vector2(14,12)
	bars.size = Vector2(28,28)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_button.add_child(bars)
	climb_bar = PlayGauges.RouteGauge.new()
	climb_bar.position = Vector2(20,96)
	climb_bar.size = Vector2(root.size.x-40,24)
	climb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(climb_bar)
	rope_gauge = PlayGauges.RopeGauge.new()
	rope_gauge.font = heading_font
	rope_gauge.position = Vector2(root.size.x-64,176)
	rope_gauge.size = Vector2(44,170)
	rope_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rope_gauge.visible = false
	content.add_child(rope_gauge)
	var notes := VBoxContainer.new()
	notes.position = Vector2(20,128)
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
	contract_label = label(chip(notes,MenuSurface.SLATE),"",13,GOLD)
	contract_label.add_theme_font_override("font",strong_font)
	aim_label = label(chip(notes,MenuSurface.SLATE),"",14,GOLD)
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
	slowmo_indicator.size = Vector2(204,50)
	# Top bar, centred in the gap between the height plate and Pause, so it
	# stays clear of the climb.
	var gap_left := top.position.x+top.size.x+8
	var gap_right := pause_button.position.x-8
	slowmo_indicator.position = Vector2(clampf((gap_left+gap_right-slowmo_indicator.size.x)*.5,gap_left,maxf(gap_left,gap_right-slowmo_indicator.size.x)),32)
	slowmo_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slowmo_indicator.visible = false
	content.add_child(slowmo_indicator)
	# Wallet: banked gold, apart from the bag cells. Coins land here at once.
	wallet_plate = Panel.new()
	wallet_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wallet_plate.add_theme_stylebox_override("panel",slab_style(PLAY_PANEL,MenuSurface.SLATE_LIP,3,8))
	wallet_plate.size = Vector2(118,38)
	wallet_plate.position = Vector2(root.size.x-20-wallet_plate.size.x,128)
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
	wallet_label.position = Vector2(36,6)
	wallet_label.size = Vector2(76,26)
	shown_wallet = float(game.model.profile["gold"])
	wallet_plate.visible = game.run_mode!="practice"
	beacon_marks = BeaconMarks.new()
	beacon_marks.size = root.size
	beacon_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(beacon_marks)
	for index in range(game.run_items.size()):
		var entry: Dictionary = game.run_items[index]
		var definition := ItemCatalog.consumable(str(entry["id"]))
		var item_button := ItemButton.new()
		item_button.index = index
		item_button.title = str(definition.get("short",definition["name"])).get_slice(" ",0)
		item_button.passive = entry["id"]=="tape"
		item_button.text_font = strong_font
		item_button.on_press = game.activate_item
		item_button.size = Vector2(64,58)
		item_button.position = Vector2(root.size.x-20-64,root.size.y-84-14-(index+1)*64)
		item_button.tooltip_text = str(definition["name"])+" · "+str(definition.get("hint",""))
		content.add_child(item_button)
		item_buttons.append(item_button)
	bag_tray = Panel.new()
	bag_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_tray.add_theme_stylebox_override("panel",slab_style(Color("24323dc8"),MenuSurface.SLATE_LIP,4,12))
	content.add_child(bag_tray)
	var coin := UiSymbol.new()
	coin.kind = 12
	coin.tint = Color("ffd15c")
	coin.size = Vector2(22,22)
	coin.name = "Coin"
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bag_tray.add_child(coin)
	bag_total_label = label(bag_tray,"0",18,WHITE)
	bag_total_label.add_theme_font_override("font",heading_font)
	bag_full_chip = chip(content,MenuSurface.SLATE)
	label(bag_full_chip,"Рюкзак полон: удержи находку, чтобы выбросить",13,CORAL).add_theme_font_override("font",strong_font)
	bag_full_chip.visible = false
	bag_panel = HBoxContainer.new()
	bag_panel.add_theme_constant_override("separation",8)
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
		record_at_start = float(game.model.profile["best"])
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
			cell.custom_minimum_size = Vector2(54,54)
			cell.value_font = heading_font
			bag_panel.add_child(cell)
	var width: float = capacity*54+(capacity-1)*8
	var tray_width := width+16+92
	var tray_at := Vector2((root.size.x-tray_width)*.5,root.size.y-84)
	bag_tray.position = tray_at
	bag_tray.size = Vector2(tray_width,70)
	bag_tray.get_node("Coin").position = Vector2(width+24,15)
	bag_total_label.position = Vector2(width+22,36)
	bag_total_label.size = Vector2(84,24)
	bag_panel.position = tray_at+Vector2(8,8)
	bag_panel.size = Vector2(width,54)
	bag_full_chip.reset_size()
	bag_full_chip.position = Vector2((root.size.x-bag_full_chip.size.x)*.5,tray_at.y-bag_full_chip.size.y-48)
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

# Full bag, a find worth a decision: take it instead of the cheapest item, or
# leave it. Nothing is replaced automatically.
func show_swap(item: Dictionary, cheapest: Dictionary) -> void:
	hide_swap()
	if layout_mode!="play": return
	swap_panel = Panel.new()
	swap_panel.add_theme_stylebox_override("panel",slab_style(MenuSurface.SLATE,MenuSurface.SLATE_LIP,4,10))
	swap_panel.size = Vector2(minf(420,root.size.x-40),104)
	swap_panel.position = Vector2((root.size.x-swap_panel.size.x)*.5,root.size.y-84-swap_panel.size.y-56)
	content.add_child(swap_panel)
	var text := label(swap_panel,"Взять «%s» (%d) вместо «%s» (%d)?" % [ItemCatalog.name_of(item),int(item["value"]),ItemCatalog.name_of(cheapest),int(cheapest["value"])],14,WHITE)
	text.position = Vector2(14,8)
	text.size = Vector2(swap_panel.size.x-28,40)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var take := button(swap_panel,"Взять",game.accept_swap,true)
	take.position = Vector2(14,54)
	take.size = Vector2((swap_panel.size.x-38)*.5,40)
	var leave := button(swap_panel,"Оставить",game.close_swap)
	leave.position = Vector2(24+(swap_panel.size.x-38)*.5,54)
	leave.size = Vector2((swap_panel.size.x-38)*.5,40)

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
	flyer.to = content_point(cell.get_global_rect().get_center())
	flyer.landed = _land_pickup.bind(cell,item)
	# The tray total waits for the find to arrive before counting it.
	flying_value += int(item.get("value",0))
	content.add_child(flyer)

func _land_pickup(cell: BagSlot, item: Dictionary) -> void:
	flying_value = maxi(0,flying_value-int(item.get("value",0)))
	if not is_instance_valid(cell) or not is_instance_valid(content): return
	cell.land()
	var center := content_point(cell.get_global_rect().get_center())
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
	for note in [danger_label,goal_label,contract_label,aim_label]:
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
		slowmo_indicator.visible = true
		slowmo_indicator.queue_redraw()
		if game.focus_serial!=seen_focus_serial:
			# Activation: the chip pops and the screen rim flashes once.
			seen_focus_serial = game.focus_serial
			if game.focus_active():
				pulse(slowmo_indicator,.14)
				slowmo_vignette.flash = 1.0
	slowmo_vignette.visible = layout_mode=="play"
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
	record_label.text = "Новый рекорд!" if record_broken else "Рекорд %d м" % int(game.model.profile["best"])
	record_label.add_theme_color_override("font_color",GOLD if record_broken else MUTED)
	var remaining: float = game.sim.pos.y-game.screen_bottom_y()
	var danger: bool = game.sim.launched and remaining<4
	# Act hazards announce themselves here when the lower edge is not closer.
	danger_label.text = "Нижний край близко — цепляйся выше!" if danger else game.world.hazards.hint(game.sim.pos,game.hazard_clock) if game.world.hazards!=null else ""
	climb_bar.value = clampf((game.sim.highest-game.START_Y)/game.summit_height,0,1)
	climb_bar.record = clampf(record_at_start/(game.summit_height*10),0,1)
	climb_bar.visible = game.run_mode=="summit"
	var zone := clampi(int(maxf(0,game.sim.pos.y-game.START_Y)/20),0,5)
	var reached_zone := clampi(int(maxf(0,game.sim.highest-game.START_Y)/20),0,5)
	if last_zone>=0 and reached_zone>last_zone:
		climb_bar.flash = 1.0
		climb_bar.flash_at = float(reached_zone)/climb_bar.zones
		pulse(height_plate)
	last_zone = reached_zone
	# On the expeditions the place is the act; older routes keep the zone name.
	var act: Dictionary = game.world.act_at(game.sim.pos.y)
	var place: String = str(act["display_name"]) if not act.is_empty() else GameModel.ZONE_NAMES[zone]
	goal_label.text = "Тренировка · 16 зацепов" if game.run_mode=="practice" else place+" · "+game.model.next_goal()
	var lesson := tutorial_hint()
	if not lesson.is_empty(): goal_label.text = lesson
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
	aim_label.text = "Крюки: "+GameModel.HOOK_NAMES[game.model.hook_config()-1]
	# Rope length now lives in the side gauge; the chip only says what the
	# current grip will do.
	var reel := 0
	if game.sim.attached:
		var parts: Array[String] = []
		var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not current.is_empty():
			parts.append("Опора постоянная" if current.get("permanent",true) else "Опора исчезнет при отпускании")
			if GripSpec.kind_of(current)==GripSpec.SPRING: parts.append("отпусти по стрелке — ветка подбросит")
		if not game.sim.rope_pivots.is_empty(): parts.append("канат огибает выступ")
		if game.pressed and game.touch_gesture and aim_overlay.vertical_direction!=0:
			if aim_overlay.vertical_progress>=1: reel = aim_overlay.vertical_direction
			parts.append(("подтягивание" if aim_overlay.vertical_direction>0 else "спуск") if aim_overlay.vertical_progress>=1 else "держи вертикально…")
		aim_label.text = " · ".join(parts)
		if reel==0 and absf(game.sim.target_length-game.sim.length)>.02:
			reel = 1 if game.sim.target_length<game.sim.length else -1
	rope_gauge.active = game.sim.attached
	danger_edge.strength = clampf(game.camera_dip/.6,0,1)
	danger_edge.edge_y = content_point(game.camera.unproject_position(Vector3(game.sim.pos.x,game.screen_bottom_y(),0))).y
	danger_edge.queue_redraw()
	rope_gauge.ratio = game.sim.length/maxf(.1,game.model.shot_range())
	rope_gauge.meters = roundi(game.sim.length*10)
	rope_gauge.direction = reel
	aim_overlay.aim_color = GOLD
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
			var color := GOLD if hit.is_empty() else CORAL if hit.get("blocked",false) or not branch["reachable"] else Color("8ae0ac")
			var contact: Vector2 = branch["contact"]
			aim_overlay.branches.append({"points":points,"target":game.camera.unproject_position(Vector3(contact.x,contact.y,0)),"color":color})
		aim_overlay.animation = game.animation_time
		aim_label.text = "Дуга броска · отпусти для выстрела"
		var collision: Dictionary = shot_preview["collision"]
		if not collision.is_empty():
			point = collision["contact"]
			if collision.get("blocked",false):
				aim_label.text = "Карниз · можно приземлиться сверху" if collision.get("object",{}).get("rest",false) else "Твёрдый выступ · крюк не зацепится"
				aim_overlay.aim_color = CORAL
			else:
				aim_label.text = game.world.object_description(collision["object"])
				aim_overlay.aim_color = Color("8ae0ac")
				aim_label.text += " · %.2f с" % float(shot_preview["time"])
				if not shot_preview["reachable"]:
					aim_overlay.aim_color = CORAL
					aim_label.text = "Удаляешься от цели — каната не хватит"
	else:
		shot_preview.clear()
		aim_overlay.branches.clear()
		if game.pressed and game.touch_gesture and not game.sim.attached:
			aim_label.text = "Потяни от места касания — выбери направление"
	if game.bolt_active: aim_label.text = GameModel.HOOK_NAMES[game.model.hook_config()-1]+" · в полёте"
	elif game.bolt_returning: aim_label.text = "Крюк возвращается · можно бросать снова"
	aim_overlay.target = game.camera.unproject_position(Vector3(point.x,point.y,0))
	aim_overlay.queue_redraw()
	if game.sim.attached and not danger:
		var grip: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not grip.is_empty() and GripSpec.timed(grip):
			danger_label.text = "Корень сломается через %.1f с" % GripSpec.seconds_left(grip,game.anchor_time)
			danger_timer.value = GripSpec.seconds_left(grip,game.anchor_time)/GripSpec.ROOT_SECONDS
		elif not grip.is_empty() and GripSpec.kind_of(grip)==GripSpec.ICE:
			danger_label.text = "Лёд скользит — готовь следующий бросок"
		elif not grip.is_empty() and not GripSpec.choice_exits(grip).is_empty():
			danger_label.text = "Кристалл: два выхода подсвечены — выбирай"
	danger_timer.visible = danger_label.text.begins_with("Корень")
	show_chip(danger_label.get_parent().get_parent(),not danger_label.text.is_empty())
	for note in [goal_label,aim_label]:
		show_chip(note.get_parent(),not note.text.is_empty())
	var total := float(game.model.bag_value()-flying_value)
	shown_bag_total = move_toward(shown_bag_total,total,maxf(40,absf(total-shown_bag_total)*6)*delta)
	bag_total_label.text = str(int(round(shown_bag_total)))
	show_chip(bag_full_chip,game.model.bag.size()>=game.model.bag_capacity() and not is_instance_valid(swap_panel))
	var gold := float(game.model.profile["gold"])
	shown_wallet = move_toward(shown_wallet,gold,maxf(30,absf(gold-shown_wallet)*5)*delta)
	wallet_label.text = str(int(round(shown_wallet)))
	contract_label.text = contract_text()
	show_chip(contract_label.get_parent(),not contract_label.text.is_empty())
	fit_notes()
	for button_index in range(item_buttons.size()):
		var item_button: ItemButton = item_buttons[button_index]
		var entry: Dictionary = game.run_items[button_index] if button_index<game.run_items.size() else {}
		item_button.used = bool(entry.get("used",false))
		item_button.running = float(game.item_effect.get("remaining",0))/maxf(.01,float(game.item_effect.get("duration",1))) if game.item_effect_id()==str(entry.get("id","")) else 0.0
		item_button.queue_redraw()
	beacon_marks.points.clear()
	for target in game.beacon_targets: beacon_marks.points.append(content_point(game.camera.unproject_position(Vector3(target.x,target.y,0))))
	beacon_marks.time = game.elapsed
	beacon_marks.strength = clampf(float(game.item_effect.get("remaining",0))/.4,0,1) if game.item_effect_id()=="beacon" else 0.0
	beacon_marks.queue_redraw()

func contract_text() -> String:
	if game.run_contract.is_empty(): return ""
	var carried := false
	for item in game.model.bag: carried = carried or str(item.get("family",""))=="contract"
	var taken: bool = game.model.picked.has(int(game.run_contract["find"]))
	var status := "в рюкзаке — донеси до вершины" if carried else "потерян" if taken else "на ветке акта «%s»" % str(game.run_contract["act_name"])
	return "Контракт: груз · "+status

func tutorial_hint() -> String:
	var learned: Array = game.model.profile["learned_controls"]
	var mobile := touch_controls_hint
	if "aim" not in learned:
		return "Коснись где удобно, потяни как стик и отпусти" if mobile else "Зажми ЛКМ, прицелься в выступ и отпусти"
	if not game.sim.attached:
		return ("Новое касание → направление стиком → отпустить" if mobile else "В полёте прицелься и поймай следующую опору") if game.catches<2 else ""
	if "swing" not in learned:
		return "Удерживай палец и веди влево/вправо: раскачайся" if mobile else "A / D: раскачайся в такт движению"
	if "rope" not in learned:
		return "Держи строго вверх / вниз: после паузы канат движется" if mobile else "W / S или колесо: измени длину каната"
	if "release" not in learned:
		return "Отпусти палец — отцепись. Новый бросок — новое касание" if mobile else "Пробел: отпусти канат на взлёте и целься снова"
	return ""

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
	place_toast()

func show_workshop() -> void:
	show_menu()

func _buy_upgrade(kind: int) -> void:
	var level_before: int = game.model.level(kind)
	var message: String = game.model.purchase(kind)
	# The rebuilt row celebrates a real level change only.
	upgrade_flash = kind if game.model.level(kind)>level_before else -1
	if kind==2 and is_instance_valid(game.explorer):
		game.explorer.set_hook_configuration(game.model.hook_tips(),game.model.hook_count())
	show_menu()
	game.toast(message)

func show_locations() -> void:
	show_menu()

func menu_surface(mode: String) -> ExpeditionMenu:
	game.ads.set_main_menu(false)
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
	menu_surface("result").build_result(result)

func set_ad_blocked(blocked: bool) -> void:
	ad_blocker.visible = blocked
