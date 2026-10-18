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
var climb_bar: ClimbMeter
var bag_panel: HBoxContainer
var pause_button: Button
var aim_overlay: AimOverlay
var base_theme: Theme
var heading_font: FontVariation
var backdrop: LobbyView.Backdrop
var layout_mode := "modal"
var menu_tab := "expedition"
var result_data: Dictionary = {}
var revive_reason := "Падение"
var wide := false
var shot_preview: Dictionary = {}
var shot_preview_time := -1.0
var shot_preview_direction := Vector2.ZERO
var ad_blocker: Control
var touch_controls_hint := OS.has_feature("mobile")
const INK := Color("19352d")
const GOLD := Color("efc779")
const WHITE := Color("f3eddb")
const MUTED := Color("a0b5ab")

class ClimbMeter extends Control:
	var value := 0.0
	func _draw() -> void:
		var track := StyleBoxFlat.new()
		track.bg_color = Color("30434a")
		track.set_corner_radius_all(3)
		draw_style_box(track,Rect2(Vector2.ZERO,size))
		var fill := track.duplicate() as StyleBoxFlat
		fill.bg_color = Color("f3c668")
		draw_style_box(fill,Rect2(Vector2.ZERO,Vector2(size.x*value/100,size.y)))

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
	var aim_color := Color("f3c668")
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
			var color := Color("96d9b4") if vertical_progress>=1 else Color("f3c668")
			var radius := 48*ui_scale
			var knob := control_origin+(control_target-control_origin).limit_length(ClimbGesture.STICK_RADIUS*ui_scale)*(48/ClimbGesture.STICK_RADIUS)
			draw_circle(control_origin,radius,Color("122c29",.28))
			draw_circle(control_origin,radius,Color(color,.38),false,ui_scale,true)
			draw_circle(control_origin,ClimbGesture.DEAD_ZONE*ui_scale,Color(color,.28),false,ui_scale,true)
			if control_attached:
				for axis_angle in [-PI*.5,PI*.5]:
					for side in [-1,1]:
						var angle: float = axis_angle+side*deg_to_rad(15)
						draw_line(control_origin,control_origin+Vector2.from_angle(angle)*radius,Color(color,.22),ui_scale,true)
			if vertical_direction!=0 and control_attached:
				draw_arc(control_origin,radius+4*ui_scale,-PI*.5,-PI*.5+TAU*maxf(.001,vertical_progress),48,color,3*ui_scale,true)
			draw_line(control_origin,knob,Color(color,.6),2*ui_scale,true)
			draw_circle(knob,8*ui_scale,color,false,2*ui_scale,true)

func setup(controller) -> void:
	game = controller
	base_theme = Theme.new()
	heading_font = FontVariation.new()
	heading_font.base_font = ThemeDB.fallback_font
	heading_font.variation_embolden = .65
	base_theme.default_font_size = 17
	base_theme.set_color("font_color","Label",WHITE)
	base_theme.set_color("font_color","Button",WHITE)
	base_theme.set_stylebox("normal","Button",style(Color("253f4d"),12,Color("54717c")))
	base_theme.set_stylebox("hover","Button",style(Color("355a66"),12,Color("85b6c0")))
	base_theme.set_stylebox("pressed","Button",style(Color("162e3b"),12,Color("8bc6d2")))
	base_theme.set_stylebox("disabled","Button",style(Color("253743"),12,Color("3c505c")))
	base_theme.set_color("font_disabled_color","Button",Color("879ca5"))
	base_theme.set_font("font","Button",heading_font)
	backdrop = LobbyView.Backdrop.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
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
	toast_label = label(root,"",15,MUTED)
	toast_label.position = Vector2(38,901)
	toast_label.size = Vector2(464,58)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_shadow_color",Color("12212d"))
	toast_label.add_theme_constant_override("shadow_outline_size",4)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	backdrop.visible = layout_mode!="play"
	backdrop.queue_redraw()
	toast_label.position = Vector2((root.size.x-464)*.5,root.size.y-(154 if layout_mode=="play" else 59))

func _resize() -> void:
	if game.state=="play": game._reset_input()
	fit_viewport()
	if layout_mode=="menu": show_menu()
	elif layout_mode=="play": show_play()
	elif layout_mode=="pause": show_pause()
	elif layout_mode=="revive": show_revive(revive_reason)
	elif layout_mode=="result": show_result(result_data)

func style(color: Color, radius: int = 16, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.border_color = border
	box.set_border_width_all(1 if border.a>0 else 0)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box

func label(parent: Node, text: String, size: int = 17, color: Color = WHITE) -> Label:
	var node := Label.new()
	node.text = text
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
	if gold:
		node.add_theme_stylebox_override("normal",style(GOLD,12))
		node.add_theme_stylebox_override("hover",style(Color("ffdb89"),12))
		node.add_theme_stylebox_override("pressed",style(Color("d7a949"),12))
		node.add_theme_color_override("font_color",INK)
		node.add_theme_color_override("font_hover_color",INK)
		node.add_theme_color_override("font_pressed_color",INK)
	parent.add_child(node)
	node.pressed.connect(callback)
	skin_button(node,"primary" if gold else "secondary")
	return node

func skin_button(node: Button, tone: String = "secondary") -> void:
	var primary := tone=="primary"
	var selected := tone=="selected"
	var ghost := tone=="ghost"
	for state_name in ["normal","hover","pressed","disabled"]:
		var fill := GOLD if primary else Color("314a3b") if selected else Color("1c3630")
		var edge := Color("f8dea3") if primary else Color("88996a") if selected else Color("3e584a")
		if ghost:
			fill = Color.TRANSPARENT
			edge = Color.TRANSPARENT
		if state_name=="hover": fill = fill.lightened(.09) if not ghost else Color("263f33")
		if state_name=="pressed": fill = fill.darkened(.12) if not ghost else Color("324e3d")
		if state_name=="disabled":
			fill = Color("1c302b")
			edge = Color("30463a")
		var box := style(fill,13,edge)
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		node.add_theme_stylebox_override(state_name,box)
	var focus := style(Color.TRANSPARENT,13,Color("e9d9a5"))
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus",focus)
	for color_name in ["font_color","font_hover_color","font_pressed_color"]:
		node.add_theme_color_override(color_name,INK if primary else WHITE)
	node.add_theme_color_override("font_disabled_color",Color("82998a"))
	node.add_theme_font_size_override("font_size",16)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.clip_text = true

func select_menu(tab: String) -> void:
	menu_tab = tab
	show_menu()

func toggle_sound() -> void:
	game.model.profile["sound"] = not game.model.profile.get("sound",true)
	game.model.save()
	if not game.model.profile["sound"]: game.audio.stop()
	show_menu()

func panel(at: Vector2, dimensions: Vector2, parent: Node = null) -> VBoxContainer:
	var card := PanelContainer.new()
	card.position = at
	card.size = dimensions
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel",style(Color("102a29ed"),18,Color("55725b80")))
	(parent if parent!=null else content).add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	card.add_child(column)
	return column

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
	aim_overlay.active = false
	aim_overlay.control_active = false
	aim_overlay.queue_redraw()

func wallet(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)
	var gold_label := label(row,"●  %d золота" % int(game.model.profile["gold"]),17,GOLD)
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(row,"◆  %d" % int(game.model.profile["diamonds"]),17,Color("a8deee"))

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
	var top := panel(Vector2(20,22),Vector2(228,84))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation",2)
	height_label = label(top,"0 м",30)
	record_label = label(top,"Рекорд: 0 м",13,GOLD)
	pause_button = button(content,"Ⅱ",game.pause_run)
	pause_button.position = Vector2(root.size.x-78,22)
	pause_button.size = Vector2(58,58)
	pause_button.add_theme_font_size_override("font_size",27)
	danger_label = label(content,"",14,Color("ffbe97"))
	danger_label.position = Vector2(23,119)
	danger_label.size = Vector2(275,28)
	goal_label = label(content,"",13,MUTED)
	goal_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	goal_label.position = Vector2(24,151)
	goal_label.size = Vector2(root.size.x-48,24)
	goal_label.add_theme_color_override("font_color",WHITE)
	goal_label.add_theme_color_override("font_shadow_color",Color("13232b"))
	goal_label.add_theme_constant_override("shadow_outline_size",4)
	aim_label = label(content,"",14,GOLD)
	aim_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	aim_label.position = Vector2(24,184)
	aim_label.size = Vector2(root.size.x-48,25)
	aim_label.add_theme_color_override("font_shadow_color",Color("13232b"))
	aim_label.add_theme_constant_override("shadow_outline_size",4)
	climb_bar = ClimbMeter.new()
	climb_bar.position = Vector2(24,109)
	climb_bar.size = Vector2(root.size.x-48,5)
	climb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(climb_bar)
	bag_panel = HBoxContainer.new()
	bag_panel.add_theme_constant_override("separation",7)
	bag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bag_panel)
	refresh_bag()

func refresh_bag() -> void:
	if not is_instance_valid(bag_panel):
		return
	for child in bag_panel.get_children():
		bag_panel.remove_child(child)
		child.queue_free()
	var capacity: int = game.model.level(3)
	var width: float = capacity*54+(capacity-1)*7
	bag_panel.position = Vector2((root.size.x-width)*.5,root.size.y-74)
	bag_panel.size = Vector2(width,54)
	for index in range(capacity):
		var slot := BagSlot.new()
		slot.custom_minimum_size = Vector2(54,54)
		if index<game.model.bag.size():
			slot.item = game.model.bag[index]
			slot.rare = game.model.item_is_rare(slot.item)
			slot.on_discard = _discard.bind(index)
		bag_panel.add_child(slot)

func _discard(index: int) -> void:
	game.model.discard(index)
	refresh_bag()
	game.save_snapshot()

func update_play() -> void:
	toast_label.visible = game.hint_timer>0 and game.state in ["play","menu","revive"]
	toast_label.position.y = root.size.y-(154 if game.state=="play" else 59)
	if not is_instance_valid(height_label) or game.state!="play":
		return
	height_label.text = "%d м" % maxi(0,int((game.sim.pos.y-game.START_Y)*10))
	record_label.text = "♛ Рекорд: %d м" % int(game.model.profile["best"])
	var remaining: float = game.sim.pos.y-game.screen_bottom_y()
	var danger: bool = game.sim.launched and remaining<4
	danger_label.text = "Нижний край близко — цепляйся выше!" if danger else ""
	climb_bar.value = clampf((game.sim.highest-game.START_Y)/game.summit_height*100,0,100)
	climb_bar.queue_redraw()
	climb_bar.visible = game.run_mode=="summit"
	var zone := clampi(int(maxf(0,game.sim.pos.y-game.START_Y)/20),0,5)
	goal_label.text = "Тренировка · 16 зацепов" if game.run_mode=="practice" else GameModel.ZONE_NAMES[zone]+" · "+game.model.next_goal()
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
	aim_overlay.origin = game.camera.unproject_position(Vector3(game.sim.pos.x,game.sim.pos.y,0))
	var point: Vector2 = game.sim.pos+game.aim_direction*game.model.shot_range()
	aim_label.text = "Канат: %d / %d м" % [roundi(game.sim.length*10),roundi(game.model.shot_range()*10)] if game.sim.attached else "Крюки · "+GameModel.HOOK_NAMES[game.model.level(2)-1]
	if game.sim.attached:
		var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not current.is_empty():
			aim_label.text += " · постоянная" if current.get("permanent",true) else " · исчезнет при отпускании"
		if not game.sim.rope_pivots.is_empty(): aim_label.text += " · канат огибает выступ"
		if game.pressed and game.touch_gesture and aim_overlay.vertical_direction!=0:
			aim_label.text += (" · ↑ подтягивание" if aim_overlay.vertical_direction>0 else " · ↓ спуск") if aim_overlay.vertical_progress>=1 else " · держи вертикально…"
	aim_overlay.aim_color = GOLD
	if aim_overlay.active:
		if shot_preview.is_empty() or game.elapsed-shot_preview_time>.035 or game.elapsed<shot_preview_time or shot_preview_direction.dot(game.aim_direction)<.99999:
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
			var color := GOLD if hit.is_empty() else Color("ff987f") if hit.get("blocked",false) or not branch["reachable"] else Color("8ae0ac")
			var contact: Vector2 = branch["contact"]
			aim_overlay.branches.append({"points":points,"target":game.camera.unproject_position(Vector3(contact.x,contact.y,0)),"color":color})
		aim_overlay.animation = game.animation_time
		aim_label.text = "Дуга броска · отпусти для выстрела"
		var collision: Dictionary = shot_preview["collision"]
		if not collision.is_empty():
			point = collision["contact"]
			if collision.get("blocked",false):
				aim_label.text = "Карниз · можно приземлиться сверху" if collision.get("object",{}).get("rest",false) else "Твёрдый выступ · крюк не зацепится"
				aim_overlay.aim_color = Color("ff987f")
			else:
				aim_label.text = game.world.object_description(collision["object"])
				aim_overlay.aim_color = Color("8ae0ac")
				aim_label.text += " · %.2f с" % float(shot_preview["time"])
				if not shot_preview["reachable"]:
					aim_overlay.aim_color = Color("ff987f")
					aim_label.text = "Удаляешься от цели — каната не хватит"
	else:
		shot_preview.clear()
		aim_overlay.branches.clear()
		if game.pressed and game.touch_gesture and not game.sim.attached:
			aim_label.text = "Потяни от места касания — выбери направление"
	if game.bolt_active: aim_label.text = GameModel.HOOK_NAMES[game.model.level(2)-1]+" · в полёте"
	elif game.bolt_returning: aim_label.text = "Крюк возвращается · можно бросать снова"
	aim_overlay.target = game.camera.unproject_position(Vector3(point.x,point.y,0))
	aim_overlay.queue_redraw()
	if game.sim.attached and not danger:
		var grip: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not grip.is_empty() and grip["kind"]==1:
			danger_label.text = "Корень сломается через %.1f с" % maxf(0,2.6-game.anchor_time)
		elif not grip.is_empty() and grip["kind"]==3:
			danger_label.text = "Лёд скользит — готовь следующий бросок"

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
	return true

func set_toast(text: String) -> void:
	toast_label.text = text

func show_workshop() -> void:
	show_menu()

func _buy_upgrade(kind: int) -> void:
	var message: String = game.model.purchase(kind)
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
