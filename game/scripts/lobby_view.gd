class_name LobbyView
extends MenuSurface

class UpgradeMeter extends Control:
	var filled := 1
	var unlocked := 1
	var total := 6
	func _draw() -> void:
		var width := (size.x-4*(total-1))/total
		for index in range(total):
			var color := HOLD if index<filled else STONE_LIP if index<unlocked else STONE_SHADE
			var left := index*(width+4)
			# Slanted ticks read as steps up a slope rather than a loading bar.
			draw_colored_polygon(PackedVector2Array([Vector2(left+3,0),Vector2(left+width,0),Vector2(left+width-3,size.y),Vector2(left,size.y)]),color)

# Same daylight as the climb: sky gradient with two faceted ridge bands. Over a
# paused run the sky turns into a veil so the climb stays faintly visible.
class Backdrop extends Control:
	var veil := false
	func _draw() -> void:
		var alpha := .9 if veil else 1.0
		for band in range(48):
			draw_rect(Rect2(0,size.y*band/48,size.x,size.y/48+1),Color(SKY_TOP.lerp(SKY_LOW,float(band)/47),alpha))
		if veil: return
		var unit := minf(size.x,size.y)
		ridge(size.y*.62,unit*.16,RIDGE_FAR,11,.7)
		ridge(size.y*.80,unit*.12,RIDGE_NEAR,8,2.3)

	func ridge(base: float, amplitude: float, color: Color, count: int, phase: float) -> void:
		var tops := PackedVector2Array()
		for index in range(count+1):
			var x := size.x*index/count
			tops.append(Vector2(x,base-amplitude*(.55+.45*sin(index*2.1+phase)*cos(index*.7+phase*2))))
		for index in range(count):
			var a := tops[index]
			var b := tops[index+1]
			var mid := Vector2((a.x+b.x)*.5+sin(index+phase)*size.x*.02,maxf(a.y,b.y)+amplitude*.6)
			draw_colored_polygon(PackedVector2Array([a,b,mid]),color.lightened(.06 if index%2==0 else 0))
			draw_colored_polygon(PackedVector2Array([a,mid,Vector2(a.x,size.y)]),color.darkened(.03))
			draw_colored_polygon(PackedVector2Array([b,Vector2(b.x,size.y),Vector2(a.x,size.y),mid]),color.darkened(.07 if index%2 else .02))

# Horizontal swipes: over the route card they pick the neighbouring route,
# anywhere else they switch sections. Distances are in design pixels, so the
# feel is the same on every screen size.
const SWIPE_DISTANCE := 64.0
const SWIPE_FLICK_DISTANCE := 36.0
const SWIPE_FLICK_SPEED := 500.0
const SWIPE_MAX_SECONDS := .7
const SWIPE_RATIO := 1.6
# Past this sideways drift a press is a swipe attempt and can no longer
# activate the button it started on.
const SWIPE_SLOP := 16.0
const SWIPE_PREVIEW_LIMIT := 42.0
const SWIPE_COOLDOWN_MSEC := 80

var swipe_pointer := -2
var swipe_from := Vector2.ZERO
var swipe_msec := 0
var swipe_dragging := false
var swipe_preview_offset := 0.0
var swipe_body_origins: Array[Vector2] = []
var card_rect := Rect2()
var body_nodes: Array[Control] = []
var transition_nodes: Array[Control] = []
var scenic_frame: Panel
var start_button: Button
var tab_buttons: Array[Button] = []
var navigation_bar: Control
var banner_inset := 0.0
var banner_tween: Tween

func setup(owner_hud: GameHud) -> void:
	prepare(owner_hud)
	_build_screen()

func _reset_build_state() -> void:
	swipe_pointer = -2
	swipe_dragging = false
	swipe_preview_offset = 0.0
	swipe_body_origins.clear()
	body_nodes.clear()
	transition_nodes.clear()
	tab_buttons.clear()
	start_button = null
	card_rect = Rect2()
	scenic_frame = null

func _build_screen() -> void:
	_reset_build_state()
	build_header()
	var first_body := get_child_count()
	match hud.menu_tab:
		"equipment": build_equipment()
		"settings": build_settings()
		_: build_expedition()
	for index in range(first_body,get_child_count()):
		var node := get_child(index)
		if node is Control: body_nodes.append(node)
	build_navigation()
	animate_entry()

func update_layout() -> void:
	var target_landscape: bool = hud.wide
	var target_size := Vector2(1080,660) if target_landscape else Vector2(540,960)
	if landscape != target_landscape:
		landscape = target_landscape
		for child in get_children():
			remove_child(child)
			child.queue_free()
		size = target_size
		position = (hud.root.size-size)*.5
		modulate.a = 1.0
		_build_screen()
	else:
		size = target_size
		position = (hud.root.size-size)*.5
		update_banner_inset(game.ads.menu_banner_height()/maxf(.1,hud.root.scale.x))

func update_banner_inset(pixels: float) -> void:
	banner_inset = maxf(0.0,pixels)
	if is_instance_valid(navigation_bar):
		var target_y := size.y-82-banner_inset
		if is_instance_valid(banner_tween): banner_tween.kill()
		# Keep hit testing above the banner immediately. The banner itself is
		# asynchronous, so delaying the layout would leave controls underneath it.
		navigation_bar.position.y = target_y

func refresh_screen() -> void:
	# Keep the header, wallet and backdrop alive. Only the active body and the
	# navigation selection are replaced, so values at the top never blink.
	for node in transition_nodes:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	transition_nodes.clear()
	for node in body_nodes:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	body_nodes.clear()
	start_button = null
	card_rect = Rect2()
	if is_instance_valid(navigation_bar):
		remove_child(navigation_bar)
		navigation_bar.queue_free()
	navigation_bar = null
	var first_body := get_child_count()
	match hud.menu_tab:
		"equipment": build_equipment()
		"settings": build_settings()
		_: build_expedition()
	for index in range(first_body,get_child_count()):
		var node := get_child(index)
		if node is Control:
			body_nodes.append(node)
	var direction: int = hud.menu_slide
	hud.menu_slide = 0
	build_navigation()
	if direction!=0:
		hud.menu_slide = direction
	animate_entry()

func animate_entry() -> void:
	var direction: int = hud.menu_slide
	hud.menu_slide = 0
	if direction!=0:
		# The new section slides in from the side the finger moved toward.
		for node in body_nodes:
			var rest := node.position
			node.position.x += 64*direction
			create_tween().tween_property(node,"position",rest,.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var focus: String = hud.menu_focus
	hud.menu_focus = ""
	var target: Button = start_button if focus=="start" and is_instance_valid(start_button) and not start_button.disabled else null
	if focus!="" and target==null:
		var index: int = GameHud.MENU_TABS.find(hud.menu_tab)
		if index>=0 and index<tab_buttons.size(): target = tab_buttons[index]
	if target!=null:
		target.focus_mode = Control.FOCUS_ALL
		target.call_deferred("grab_focus")

func bounce(direction: int) -> void:
	# Feedback at the first/last section or route: a short elastic nudge.
	for node in body_nodes:
		if not is_instance_valid(node): continue
		var rest := node.position
		var tween := create_tween()
		tween.tween_property(node,"position:x",rest.x-18*direction,.08).set_trans(Tween.TRANS_SINE)
		tween.tween_property(node,"position:x",rest.x,.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func local_point(screen: Vector2) -> Vector2:
	return get_global_transform().affine_inverse()*screen

func begin_swipe_preview() -> void:
	swipe_body_origins.clear()
	for node in body_nodes:
		if is_instance_valid(node): swipe_body_origins.append(node.position)
	swipe_preview_offset = 0.0

func update_swipe_preview(offset: float) -> void:
	swipe_preview_offset = clampf(offset,-SWIPE_PREVIEW_LIMIT,SWIPE_PREVIEW_LIMIT)
	for index in range(mini(body_nodes.size(),swipe_body_origins.size())):
		var node := body_nodes[index]
		if is_instance_valid(node): node.position.x = swipe_body_origins[index].x+swipe_preview_offset

func reset_swipe_preview() -> void:
	for index in range(mini(body_nodes.size(),swipe_body_origins.size())):
		var node := body_nodes[index]
		if is_instance_valid(node): node.position = swipe_body_origins[index]
	swipe_preview_offset = 0.0
	swipe_body_origins.clear()

func _input(event: InputEvent) -> void:
	if not is_inside_tree() or hud.layout_mode!="menu" or game.state!="menu" or game.ads.fullscreen: return
	if event is InputEventKey or event is InputEventJoypadButton:
		_navigation_input(event)
		return
	var pointer := -2
	var position_value := Vector2.ZERO
	var pressed_value := false
	var released := false
	if event is InputEventScreenTouch:
		if event.canceled:
			if event.index==swipe_pointer:
				reset_swipe_preview()
				swipe_pointer = -2
				swipe_dragging = false
			return
		pointer = event.index
		position_value = event.position
		pressed_value = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.index
		position_value = event.position
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.device!=InputEvent.DEVICE_ID_EMULATION:
		pointer = -1
		position_value = event.position
		pressed_value = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and event.device!=InputEvent.DEVICE_ID_EMULATION:
		pointer = -1
		position_value = event.position
	else:
		return
	var at := local_point(position_value)
	if pressed_value:
		if swipe_pointer==-2:
			swipe_pointer = pointer
			swipe_from = at
			swipe_msec = Time.get_ticks_msec()
			swipe_dragging = false
			begin_swipe_preview()
		return
	if pointer!=swipe_pointer: return
	var travel := at-swipe_from
	if not released:
		if absf(travel.x)>SWIPE_SLOP and absf(travel.x)>absf(travel.y)*SWIPE_RATIO:
			if not swipe_dragging: get_viewport().set_input_as_handled()
			swipe_dragging = true
			update_swipe_preview(travel.x*.36)
		return
	swipe_pointer = -2
	var was_dragging := swipe_dragging
	reset_swipe_preview()
	swipe_dragging = false
	var seconds := maxf(.001,(Time.get_ticks_msec()-swipe_msec)*.001)
	var speed := absf(travel.x)/seconds
	var horizontal := absf(travel.x)>absf(travel.y)*SWIPE_RATIO
	var long_enough := absf(travel.x)>=SWIPE_DISTANCE or (absf(travel.x)>=SWIPE_FLICK_DISTANCE and speed>=SWIPE_FLICK_SPEED)
	if was_dragging:
		# The release belongs to the gesture, never to the button under it.
		get_viewport().set_input_as_handled()
	if not (horizontal and long_enough and seconds<=SWIPE_MAX_SECONDS): return
	if Time.get_ticks_msec()-hud.last_swipe_msec<SWIPE_COOLDOWN_MSEC: return
	hud.last_swipe_msec = Time.get_ticks_msec()
	get_viewport().set_input_as_handled()
	# Finger moving left reveals what is to the right.
	swipe(-1 if travel.x>0 else 1,card_rect.has_point(swipe_from))

func swipe(direction: int, on_card: bool, focus: String = "tab") -> void:
	if on_card and hud.menu_tab=="expedition" and model.profile["active"].is_empty():
		hud.menu_focus = "start"
		if not game.cycle_location(direction):
			hud.menu_focus = ""
			bounce(direction)
		return
	if not hud.step_menu(direction,focus): bounce(direction)

func _navigation_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	var direction := 0
	var routes := false
	if event is InputEventKey and event.keycode in [KEY_Q,KEY_PAGEUP]: direction = -1
	elif event is InputEventKey and event.keycode in [KEY_E,KEY_PAGEDOWN]: direction = 1
	elif event is InputEventJoypadButton and event.button_index==JOY_BUTTON_LEFT_SHOULDER: direction = -1
	elif event is InputEventJoypadButton and event.button_index==JOY_BUTTON_RIGHT_SHOULDER: direction = 1
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		direction = -1 if event.is_action_pressed("ui_left") else 1
		# Arrows pick routes on the expedition screen and sections elsewhere.
		routes = hud.menu_tab=="expedition" and model.profile["active"].is_empty()
	elif event.is_action_pressed("ui_accept") and hud.menu_tab=="expedition" and is_instance_valid(start_button) and not start_button.disabled:
		# Keyboard start never buys a locked route; that stays a deliberate tap.
		if not model.profile["active"].is_empty() or model.profile["locations"].has(game.lobby_location):
			get_viewport().set_input_as_handled()
			game.lobby_action()
		return
	if direction==0: return
	get_viewport().set_input_as_handled()
	swipe(direction,routes)

func build_header() -> void:
	# The icon's own sky would melt into the backdrop, so it sits on a slab.
	slab(self,Vector2(25,21),Vector2(50,54),STONE,STONE_LIP,4)
	var mark := TextureRect.new()
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.texture = preload("res://assets/icon.svg")
	mark.position = Vector2(28,24)
	mark.size = Vector2(44,44)
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.material = rounded_material(mark.size,10)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	text(self,"Last Hook",Vector2(84,26),Vector2(200,40),28,INK,"display")
	wallet(Vector2(size.x-236,24))

func build_navigation() -> void:
	var width := 484.0 if not landscape else 540.0
	var at := Vector2((size.x-width)*.5,size.y-82)
	var bar := slab(self,at,Vector2(width,66))
	navigation_bar = bar
	bar.position.y -= banner_inset
	var entries := [["expedition","Восхождение",7],["equipment","Снаряжение",2],["settings","Настройки",15]]
	var each := (width-16)/3
	for index in range(3):
		var entry: Array = entries[index]
		var selected: bool = hud.menu_tab==entry[0]
		var tab := action(bar,str(entry[1]),Vector2(8+index*each,7),Vector2(each-(0 if index==2 else 4),50),func(): hud.select_menu(str(entry[0])),"selected" if selected else "ghost")
		tab_buttons.append(tab)
		tab.add_theme_font_size_override("font_size",14)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.add_theme_constant_override("h_separation",0)
		for state_name in ["normal","hover","pressed"]:
			var styled := tab.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			styled.content_margin_left = 40
			styled.content_margin_right = 6
			tab.add_theme_stylebox_override(state_name,styled)
		symbol(tab,int(entry[2]),Vector2(10,12),Vector2(24,24),STONE if selected else INK_SOFT)
	# A hold-yellow marker under the active section glides from the previous one.
	var marker := ColorRect.new()
	marker.color = HOLD
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.size = Vector2(each-28,4)
	var current := maxi(0,GameHud.MENU_TABS.find(hud.menu_tab))
	var previous := maxi(0,GameHud.MENU_TABS.find(hud.menu_previous_tab))
	marker.position = Vector2(8+previous*each+12,58)
	bar.add_child(marker)
	if previous!=current:
		create_tween().tween_property(marker,"position:x",8+current*each+12,.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hud.menu_previous_tab = hud.menu_tab

func scenic_card(at: Vector2, dimensions: Vector2) -> Panel:
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	var frame := slab(self,at,dimensions,STONE_SHADE,STONE_LIP,5)
	scenic_frame = frame
	card_rect = Rect2(at,dimensions)
	var inner := dimensions-Vector2(0,5)
	var preview := LevelPreview.new()
	preview.world = game.world
	preview.size = inner
	preview.material = rounded_material(inner,10)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(preview)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("1f2b3500"),Color("1f2b35d8")])
	gradient.offsets = PackedFloat32Array([.5,1])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0,1)
	shade.texture = texture
	shade.size = inner
	shade.material = rounded_material(inner,10)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shade)
	var tag := slab(frame,Vector2(inner.x-104,16),Vector2(88,34),Color(SLATE,.88),SLATE_LIP,3)
	text(tag,"%d м" % (int(definition["height_units"])*10),Vector2(0,4),Vector2(88,24),16,STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not owned:
		# A locked route stays visible but is clearly veiled.
		var veil := ColorRect.new()
		veil.color = Color(SLATE,.32)
		veil.size = inner
		veil.material = rounded_material(inner,10)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(veil)
		var lock := slab(frame,Vector2(16,16),Vector2(118,34),Color(SLATE,.88),SLATE_LIP,3)
		symbol(lock,14,Vector2(8,5),Vector2(24,24),STONE)
		text(lock,"Закрыто",Vector2(36,6),Vector2(78,22),14,STONE,"strong")
	text(frame,str(definition["name"]),Vector2(22,inner.y-94),Vector2(inner.x-44,48),36,STONE,"display")
	var total: int = model.balance["locations"].size()
	# Act names wrap to a second line before the route pager.
	var pager_left := inner.x-22-(total-1)*18-6
	paragraph(frame," · ".join(LevelCatalog.act_names(game.lobby_location)),Vector2(23,inner.y-46),Vector2(pager_left-10-23,40),15,Color("e3e8ea"))
	for index in range(total):
		var center := Vector2(inner.x-22-(total-1-index)*18,inner.y-34)
		var points := PackedVector2Array([center+Vector2(0,-6),center+Vector2(6,0),center+Vector2(0,6),center+Vector2(-6,0)])
		var marker := Polygon2D.new()
		marker.polygon = points
		marker.color = HOLD if index==game.lobby_location else Color(STONE,.45)
		frame.add_child(marker)
	for direction in [-1,1]:
		var arrow := action(frame,"",Vector2(14 if direction<0 else inner.x-62,inner.y*.40),Vector2(48,52),game.cycle_location.bind(direction))
		var at_end: bool = game.lobby_location+direction<0 or game.lobby_location+direction>=total
		arrow.disabled = not model.profile["active"].is_empty() or at_end
		arrow.tooltip_text = "Предыдущий маршрут" if direction<0 else "Следующий маршрут"
		arrow.visible = model.profile["active"].is_empty()
		if at_end: arrow.modulate.a = .45
		symbol(arrow,10 if direction<0 else 11,Vector2(12,12),Vector2(24,24),INK)
	return frame

func refresh_location_card(direction: int) -> bool:
	if hud.menu_tab!="expedition" or not is_instance_valid(scenic_frame): return false
	var old := scenic_frame
	var old_at := old.position
	var old_size := old.size
	var index := body_nodes.find(old)
	remove_child(old)
	old.queue_free()
	var replacement := scenic_card(old_at,old_size)
	if index>=0: body_nodes[index] = replacement
	replacement.position.x += clampf(float(direction),-1,1)*24.0
	create_tween().tween_property(replacement,"position:x",old_at.x,.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return true

func build_expedition() -> void:
	var active: bool = not model.profile["active"].is_empty()
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	scenic_card(Vector2(28,90),Vector2(620,466) if landscape else Vector2(484,414))
	var x := 680.0 if landscape else 28.0
	var width := 372.0 if landscape else 484.0
	var y := 90.0
	if landscape:
		title(self,"Попытка ждёт" if active else "Пора наверх",Vector2(x,y),width,32)
		paragraph(self,"Продолжишь с того же зацепа." if active else "Брось крюк, раскачайся и лови следующую опору.",Vector2(x,y+46),Vector2(width,44),15)
		y = 196
	else:
		y = 524
	route(self,Vector2(x,y),width)
	var wins := int(model.profile["wins"])
	text(self,"Вершин покорено: %d" % wins if wins>0 else "Вершина ещё не покорена",Vector2(x,y+50),Vector2(width,20),13,INK_SOFT)
	var mode_y := y+86
	var mode_buttons := segmented(self,Vector2(x,mode_y),width,["Вершина","Бесконечно"],1 if game.lobby_endless else 0,func(index: int): game.lobby_endless = index==1; hud.show_menu(),48)
	for index in range(2):
		mode_buttons[index].disabled = active or (index==1 and not model.profile["summit_cleared"])
	mode_buttons[1].tooltip_text = "Откроется после первой вершины" if not model.profile["summit_cleared"] else "Без вершины: забирайся сколько сможешь"
	# A locked expedition names everything it needs; the button opens it as
	# soon as all of it is there.
	var ready: bool = model.location_ready(game.lobby_location)
	var unlock: Dictionary = model.location_unlock(game.lobby_location)
	var cost_parts: Array = []
	if unlock.has("gold"): cost_parts.append("%d золота" % int(unlock["gold"]))
	if unlock.has("diamonds"): cost_parts.append("%d алм." % int(unlock["diamonds"]))
	var action_text := "Продолжить восхождение" if active else "Начать восхождение" if owned else "Открыть за "+" + ".join(cost_parts) if ready else "Закрыто"
	var start := action(self,action_text,Vector2(x,mode_y+64),Vector2(width,66),game.lobby_action,"primary")
	start_button = start
	start.add_theme_font_size_override("font_size",21 if action_text.length()<26 else 16)
	start.disabled = not active and not owned and not ready
	if not owned and not active:
		paragraph(self,"Нужно: "+model.location_requirement(game.lobby_location),Vector2(x,mode_y+210),Vector2(width,40),13,DANGER if not ready else INK_SOFT).name = "Requirement"
	var practice := action(self,"Тренировка: 16 зацепов",Vector2(x,mode_y+146),Vector2(width,52),game.start_practice)
	practice.disabled = active
	practice.tooltip_text = "Короткий маршрут с базовым снаряжением. Кошелёк не меняется."
	if active:
		paragraph(self,"Снаряжение можно улучшить после завершения попытки.",Vector2(x,mode_y+210),Vector2(width,40),13)
	elif landscape and owned:
		paragraph(self,"Тренировка идёт с базовым снаряжением и не трогает кошелёк.",Vector2(x,mode_y+210),Vector2(width,40),13)

func build_equipment() -> void:
	var active: bool = not model.profile["active"].is_empty()
	title(self,"Снаряжение",Vector2(28,84),300,32)
	var views := ["upgrades","supplies"]
	var switch := segmented(self,Vector2(size.x-28-260,86),260,["Улучшения","Сборы"],views.find(hud.equipment_view),func(index: int): hud.equipment_view = views[index]; hud.show_menu(),42)
	switch[1].tooltip_text = "Профили, активные предметы, запас и материалы"
	if hud.equipment_view=="supplies":
		build_supplies(active)
		return
	paragraph(self,"Заверши попытку, чтобы улучшать снаряжение." if active else "Уровни 3–5 открываются актами, вершиной или контрактами.",Vector2(29,132),Vector2(size.x-56,22),13)
	var order := [GameModel.THROW,0,1,2,3,4,5,GameModel.SLOWMO]
	var columns := 2 if landscape else 1
	var row_width := 504.0 if landscape else 484.0
	var row_height := 84.0 if landscape else 80.0
	var per_column := 4 if landscape else order.size()
	for index in range(order.size()):
		var column := index/per_column
		var row := index%per_column
		build_upgrade(order[index],Vector2(28+column*(row_width+16),160+row*(row_height+8)),Vector2(row_width,row_height),active)

func effect_text(kind: int, at_level: int) -> String:
	var i := clampi(at_level-1,0,model.max_level(kind)-1)
	var balance: Dictionary = model.balance
	match kind:
		GameModel.ROPE: return "%d%% дальности" % roundi(float(balance["rope_lengths"][i])/float(balance["rope_lengths"][0])*100.0)
		GameModel.IMPULSE: return "+%d%%" % roundi((float(balance["impulse_factors"][i])-1)*100)
		GameModel.HOOKS: return GameModel.HOOK_NAMES[i]
		GameModel.BAG:
			var slots := int(balance["capacities"][i])
			return "%d %s" % [slots,"слот" if slots==1 else "слота" if slots<5 else "слотов"]+(" +1" if int(balance["special_slots"][i])>0 else "")
		GameModel.MAGNET:
			if i==0: return "касание"
			if float(balance["magnet_radii"][i])<=0: return "монеты %d м" % roundi(float(balance["magnet_coin_radii"][i])*10)
			return "%d / %d м" % [roundi(float(balance["magnet_coin_radii"][i])*10),roundi(float(balance["magnet_radii"][i])*10)]
		GameModel.RECOVERY: return "%d%%" % int(balance["recovery_percents"][i])
		GameModel.SLOWMO: return seconds_text(float(balance["slowmo_seconds"][i]))
	return "%d%% скорости" % roundi(float(balance["throw_speeds"][i])/float(balance["throw_speeds"][0])*100.0)

func build_upgrade(kind: int, at: Vector2, dimensions: Vector2, active: bool) -> void:
	var frame := slab(self,at,dimensions)
	var level := model.level(kind)
	var maximum := level>=model.max_level(kind)
	var locked := not maximum and not model.upgrade_available(kind)
	var can_buy := not active and not locked and not maximum and int(model.profile["gold"])>=model.cost(kind)
	var affordable := int(model.profile["gold"])>=model.cost(kind)
	var short_names := ["Длина каната","Импульс","Крюки","Рюкзак","Магнит","Защита добычи","Сила броска","Замедление"]
	var middle := (dimensions.y-4)*.5
	symbol(frame,19 if kind==GameModel.SLOWMO else kind,Vector2(16,middle-20),Vector2(40,40),INK)
	text(frame,short_names[kind],Vector2(70,middle-35),Vector2(dimensions.x-240,22),16,INK,"strong")
	# Where the next level matters: an act or situation of the expeditions.
	var use := text(frame,model.upgrade_use(kind,level if maximum else level+1),Vector2(70,middle-15),Vector2(dimensions.x-240,18),12,INK_SOFT)
	use.name = "Use"
	var current := text(frame,effect_text(kind,level),Vector2(70,middle+1),Vector2(dimensions.x-240,22),17,INK,"display")
	if not maximum:
		var shown := current.get_theme_font("font").get_string_size(current.text,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		text(frame,"→ "+effect_text(kind,level+1),Vector2(70+shown+8,middle+3),Vector2(maxf(40,dimensions.x-250-shown),20),14,INK_SOFT)
	var meter := UpgradeMeter.new()
	meter.filled = level
	meter.total = model.max_level(kind)
	meter.unlocked = model.max_level(kind) if kind==GameModel.HOOKS else mini(model.max_level(kind),model.unlocked_upgrade_level())
	meter.position = Vector2(70,middle+28)
	meter.size = Vector2(minf(150,dimensions.x-240),6)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(meter)
	# Level reads next to the meter; the last step says so in hold yellow.
	var level_label := text(frame,"Макс. ур. %d" % level if maximum else "Ур. %d/%d" % [level,model.max_level(kind)],Vector2(70+meter.size.x+8,middle+20),Vector2(90,20),12,COIN if maximum else INK_SOFT,"strong")
	level_label.name = "Level"
	var value := "Максимум" if maximum else "После попытки" if active else model.gate_text(level+1) if locked else "Улучшить"
	var button_size := Vector2(150,dimensions.y-24)
	var purchase := action(frame,value,Vector2(dimensions.x-button_size.x-12,middle-button_size.y*.5),button_size,hud._buy_upgrade.bind(kind),"buy" if can_buy else "secondary")
	purchase.add_theme_font_size_override("font_size",15 if value.length()<16 else 12)
	purchase.disabled = not can_buy
	if value=="Улучшить":
		# Price sits under the verb inside the hold, so cost and action are one target.
		for state_name in ["normal","hover","pressed","disabled"]:
			var styled := purchase.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			styled.content_margin_bottom += 22
			purchase.add_theme_stylebox_override(state_name,styled)
		var price := Control.new()
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.position = Vector2(0,button_size.y-34)
		purchase.add_child(price)
		var amount := str(model.cost(kind))
		var width: float = hud.heading_font.get_string_size(amount,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+24
		var left := (button_size.x-width)*.5
		symbol(price,12,Vector2(left,2),Vector2(19,19),INK if can_buy else COIN if affordable else INK_FAINT)
		text(price,amount,Vector2(left+24,0),Vector2(width,22),16,INK if can_buy or affordable else DANGER,"display")
	frame.tooltip_text = model.upgrade_text(kind)+("\nДалее: "+model.upgrade_text(kind,level+1)+"\nПолезно: "+model.upgrade_use(kind,level+1) if not maximum else "\nМаксимальный уровень")
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	if hud.upgrade_flash==kind:
		hud.upgrade_flash = -1
		celebrate_upgrade(frame,dimensions,level,maximum)

# --- Preparation: run profiles, active items, stock and progress ----------------------

func build_supplies(active: bool) -> void:
	var column_width := 504.0 if landscape else 484.0
	paragraph(self,"Выбери стиль и предметы до старта." if not active else "Попытка идёт: сбор изменится после её завершения.",Vector2(29,130),Vector2(size.x-56,20),13)
	var left := Vector2(28,162)
	var right := Vector2(28+column_width+16,162) if landscape else Vector2(28,left.y+304)
	# A preparation is a readable play style. It still drives the existing
	# rope/impulse/throw mechanics, but the player chooses one coherent intent.
	var profiles := slab(self,left,Vector2(column_width,292))
	text(profiles,"Стиль восхождения",Vector2(20,12),Vector2(300,24),17,INK,"display")
	var row_y := 40.0
	var owned: Array = []
	for index in range(model.level(GameModel.HOOKS)): owned.append(GameModel.HOOK_NAMES[index].replace("2 ","2×"))
	text(profiles,"Крюки",Vector2(20,row_y+11),Vector2(110,22),14,INK_SOFT,"strong")
	var hooks := segmented(profiles,Vector2(120,row_y),column_width-140,owned,model.hook_config()-1,func(index: int): _choose("hook",str(index+1)),40)
	for index in range(hooks.size()):
		var hook_count := int(model.balance["hook_counts"][index])
		var hook_tips := int(model.balance["hook_tips"][index])
		var tips_word := "наконечник" if hook_tips==1 else "наконечника" if hook_tips<5 else "наконечников"
		hooks[index].tooltip_text = "%d крюк%s · %d %s" % [hook_count,"а" if hook_count==2 else "",hook_tips,tips_word]
	for button in hooks:
		button.disabled = active
		button.add_theme_font_size_override("font_size",12 if owned.size()>2 else 14)
	row_y += 48
	text(profiles,"Профиль",Vector2(20,row_y+11),Vector2(110,22),14,INK_SOFT,"strong")
	var prep_keys := model.prep_profile_keys()
	var prep_names: Array[String] = []
	for profile_id in prep_keys: prep_names.append(model.prep_profile_name(profile_id))
	if model.prep_profiles_unlocked():
		var prep_buttons := segmented(profiles,Vector2(120,row_y),column_width-140,prep_names,prep_keys.find(model.prep_profile()),func(index: int): _choose_prep(prep_keys[index]),40)
		for index in range(prep_buttons.size()): prep_buttons[index].tooltip_text = model.prep_profile_hint(prep_keys[index])
	else:
		text(profiles,"Откроется после 3-го уровня каната, импульса и броска",Vector2(120,row_y+11),Vector2(column_width-140,22),12,INK_FAINT)
	row_y += 48
	paragraph(profiles,model.prep_profile_hint(),Vector2(120,row_y-4),Vector2(column_width-140,34),12,INK_SOFT)
	row_y += 38
	text(profiles,"Цель сбора",Vector2(20,row_y+11),Vector2(110,22),14,INK_SOFT,"strong")
	var magnet: Dictionary = model.balance["specializations"]["magnet"]
	if not model.spec_unlocked("magnet"):
		text(profiles,"Откроется на 5-м уровне магнита",Vector2(120,row_y+11),Vector2(column_width-140,22),12,INK_FAINT)
		paragraph(profiles,"До этого находки подбираются только в радиусе касания.",Vector2(120,row_y+42),Vector2(column_width-140,30),12,INK_SOFT)
	else:
		var magnet_keys: Array = magnet["options"].keys()
		var magnet_names: Array[String] = []
		for key in magnet_keys: magnet_names.append(str(magnet["options"][key]["name"]))
		var magnet_buttons := segmented(profiles,Vector2(120,row_y),column_width-140,magnet_names,magnet_keys.find(model.choice("magnet")),func(index: int): _choose("magnet",str(magnet_keys[index])),40)
		for index in range(magnet_buttons.size()): magnet_buttons[index].tooltip_text = str(magnet["options"][magnet_keys[index]].get("hint",""))
		paragraph(profiles,str(magnet["options"][model.choice("magnet")].get("hint","")),Vector2(120,row_y+42),Vector2(column_width-140,30),12,INK_SOFT)
	# Active items: two slots, stock up to two of each, bought with gold or
	# made from materials. Diamonds never buy consumables.
	var items := slab(self,right,Vector2(column_width,262))
	text(items,"Активные предметы",Vector2(20,12),Vector2(260,24),17,INK,"display")
	var loadout: Array = model.profile["active_loadout"]
	text(items,"Слоты: "+" · ".join(loadout.map(func(id): return "пусто" if str(id).is_empty() else str(ItemCatalog.consumable(str(id))["name"]))),Vector2(20,38),Vector2(column_width-40,20),12,INK_SOFT)
	var item_y := 62.0
	for definition in ItemCatalog.consumables():
		var id := str(definition["id"])
		var in_slot := loadout.has(id)
		text(items,str(definition["name"]),Vector2(20,item_y),Vector2(column_width-306,20),14,INK,"strong").tooltip_text = str(definition.get("hint",""))
		var recipe: Array = []
		for material_id in definition["recipe_materials"].keys(): recipe.append("%d %s" % [int(definition["recipe_materials"][material_id]),ItemCatalog.material_name(material_id).to_lower()])
		text(items,"%d/%d · %s" % [model.stock(id),model.stock_max(),str(definition.get("hint",""))],Vector2(20,item_y+20),Vector2(column_width-306,18),12,INK_SOFT)
		var slot_button := action(items,"В слоте" if in_slot else "В слот",Vector2(column_width-286,item_y),Vector2(78,40),_toggle_slot.bind(id),"selected" if in_slot else "ghost")
		slot_button.add_theme_font_size_override("font_size",12)
		slot_button.disabled = active
		var buy := action(items,"%d з." % int(definition["price_gold"]),Vector2(column_width-202,item_y),Vector2(86,40),_buy_item.bind(id),"secondary")
		buy.add_theme_font_size_override("font_size",13)
		buy.disabled = active or model.stock(id)>=model.stock_max() or int(model.profile["gold"])<int(definition["price_gold"])
		buy.tooltip_text = "Купить за золото"
		var craft := action(items,"Собрать",Vector2(column_width-110,item_y),Vector2(90,40),_craft_item.bind(id),"secondary")
		craft.add_theme_font_size_override("font_size",13)
		craft.disabled = active or model.stock(id)>=model.stock_max() or not model.can_craft(id)
		craft.tooltip_text = "Из материалов: "+", ".join(recipe)
		item_y += 48
	# Materials and long-term progress.
	var progress_at := right+Vector2(0,274)
	var progress := slab(self,progress_at,Vector2(column_width,120 if landscape else 100))
	var wallet_parts: Array = []
	for material_id in model.balance["materials"].keys(): wallet_parts.append("%s %d" % [ItemCatalog.material_name(material_id),model.materials(material_id)])
	paragraph(progress,"Материалы: "+" · ".join(wallet_parts),Vector2(20,10),Vector2(column_width-40,40),12,INK)
	var sets := int(model.profile["unlocked_sets"].size())
	text(progress,"Комплекты %d/%d · ориентиры %d · контракты %d · жетоны мастерства %d" % [sets,model.balance["sets"].size(),model.profile["landmarks"].size(),model.profile["completed_contracts"].size(),int(model.profile["mastery_tokens"])],Vector2(20,58),Vector2(column_width-40,20),12,INK_SOFT)

func _choose(track: String, option: String) -> void:
	var message := model.set_choice(track,option)
	if track=="hook" and is_instance_valid(game.explorer):
		game.explorer.set_hook_configuration(model.hook_tips(),model.hook_count())
	hud.show_menu()
	game.toast(message)

func _choose_prep(profile_id: String) -> void:
	var message := model.set_prep_profile(profile_id)
	hud.show_menu()
	game.toast(message)

func _toggle_slot(id: String) -> void:
	var loadout: Array = model.profile["active_loadout"]
	var message := ""
	if loadout.has(id): message = model.set_loadout(loadout.find(id),"")
	else:
		var slot := loadout.find("")
		message = model.set_loadout(slot if slot>=0 else loadout.size()-1,id)
	hud.show_menu()
	game.toast(message)

func _buy_item(id: String) -> void:
	var message := model.buy_consumable(id)
	hud.show_menu()
	game.toast(message)

func _craft_item(id: String) -> void:
	var message := model.craft_consumable(id)
	hud.show_menu()
	game.toast(message)

func celebrate_upgrade(frame: Control, dimensions: Vector2, level: int, maximum: bool) -> void:
	# Purchase confirmation: the row glows hold-yellow, bumps, and a burst and
	# the new level rise from it.
	var glow := ColorRect.new()
	glow.color = Color(HOLD,.55)
	glow.size = dimensions-Vector2(0,4)
	glow.material = rounded_material(glow.size,10)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(glow)
	create_tween().tween_property(glow,"modulate:a",0.0,.7).set_trans(Tween.TRANS_SINE).set_delay(.12)
	hud.pulse(frame,.04)
	var burst := PlayGauges.Burst.new()
	burst.color = HOLD
	burst.position = Vector2(dimensions.x-87,dimensions.y*.5)
	frame.add_child(burst)
	var rise := PlayGauges.FloatText.new()
	rise.text = "Максимум!" if maximum else "Ур. %d" % level
	rise.font = hud.heading_font
	rise.color = COIN
	rise.position = Vector2(dimensions.x-87,dimensions.y*.5-16)
	frame.add_child(rise)

static func seconds_text(seconds: float) -> String:
	return (str(snappedf(seconds,.01))+" с").replace(".",",")

func settings_switch(parent: Node, title_text: String, subtitle: String, at: Vector2, width: float, enabled: bool, callback: Callable) -> void:
	text(parent,title_text,at,Vector2(width-120,24),16,INK,"strong")
	text(parent,subtitle,at+Vector2(0,24),Vector2(width-120,20),13,INK_SOFT)
	var left := at.x+width-96
	slab(parent,Vector2(left,at.y),Vector2(96,44),STONE_SHADE,Color.TRANSPARENT,0)
	# A switch: the raised block sits right and turns slate when the option is on.
	var toggle := action(parent,"Вкл" if enabled else "Выкл",Vector2(left+(36 if enabled else 4),at.y+4),Vector2(56,36),callback,"selected" if enabled else "secondary")
	toggle.add_theme_font_size_override("font_size",15)

func section(parent: Node, value: String) -> void:
	text(parent,value,Vector2(20,14),Vector2(400,24),17,INK,"display")

func build_settings() -> void:
	title(self,"Настройки",Vector2(28,84),500,32)
	var column_width := 500.0 if landscape else 484.0
	var graphics := slab(self,Vector2(28,138),Vector2(column_width,198))
	section(graphics,"Графика")
	var control_x := 150.0
	var control_width := column_width-control_x-20
	text(graphics,"Качество",Vector2(20,58),Vector2(140,22),15,INK_SOFT)
	var quality := str(model.profile.get("graphics_quality","balanced"))
	var keys := ["high","balanced","battery"]
	segmented(graphics,Vector2(control_x,48),control_width,["Высокая","Баланс","Экономия"],keys.find(quality),func(index: int): game.set_graphics_quality(keys[index]),42)
	text(graphics,"Цены находок",Vector2(20,106),Vector2(140,22),15,INK_SOFT)
	var prices_always := str(model.profile.get("loot_prices","near"))=="always"
	var modes := ["near","always"]
	var prices := segmented(graphics,Vector2(control_x,96),control_width,["Рядом","Всегда"],1 if prices_always else 0,func(index: int): hud.set_loot_prices(modes[index]),42)
	prices[0].tooltip_text = "Цена видна у находок рядом и на линии прицела"
	# Camera scale: 100 % is the original framing. Larger values only narrow
	# the picture; the fall edge and route rules stay the same.
	text(graphics,"Масштаб",Vector2(20,154),Vector2(140,22),15,INK_SOFT)
	var zoom_levels := model.camera_zoom_levels()
	var zoom_names: Array = []
	for zoom in zoom_levels: zoom_names.append("%d%%" % roundi(float(zoom)*100))
	var zoom_buttons := segmented(graphics,Vector2(control_x,144),control_width,zoom_names,zoom_levels.find(model.camera_zoom()),func(index: int): game.set_camera_zoom(float(zoom_levels[index])); hud.show_menu(),42)
	for button in zoom_buttons: button.tooltip_text = "Крупнее герой и опоры. Граница падения не меняется."
	var feedback := slab(self,Vector2(28,350),Vector2(column_width,200))
	section(feedback,"Звук и отклик")
	settings_switch(feedback,"Звук","Бросок, зацеп и находки",Vector2(20,50),column_width-40,bool(model.profile.get("sound",true)),hud.toggle_sound)
	settings_switch(feedback,"Вибрация","Короткий отклик при зацепе",Vector2(20,98),column_width-40,bool(model.profile.get("vibration",true)),hud.toggle_vibration)
	settings_switch(feedback,"Подсказки","Сообщения внизу экрана",Vector2(20,146),column_width-40,bool(model.profile.get("notifications",true)),hud.toggle_notifications)
	var help_at := Vector2(552,138) if landscape else Vector2(28,564)
	var help_size := Vector2(500,412) if landscape else Vector2(484,302)
	var help := slab(self,help_at,help_size)
	section(help,"Управление")
	var instructions := [["Брось крюк","Коснись где удобно, потяни как стик и отпусти."],["Раскачайся","На канате веди палец влево или вправо."],["Выбери длину","Держи строго вверх или вниз 0,28 секунды."],["Отцепись","Подними палец. Новый бросок — новое касание."]]
	if not hud.touch_controls_hint:
		instructions = [["Брось крюк","Зажми ЛКМ, прицелься и отпусти."],["Раскачайся","A / D или стрелки."],["Выбери длину","W / S или колесо мыши."],["Отцепись","Пробел, затем целься снова."]]
	var step := (help_size.y-64)/instructions.size()
	for index in range(instructions.size()):
		var row_y := 54+index*step
		var badge := slab(help,Vector2(20,row_y+2),Vector2(34,34),SLATE,SLATE_LIP,3)
		text(badge,str(index+1),Vector2(0,3),Vector2(34,26),17,STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text(help,instructions[index][0],Vector2(68,row_y),Vector2(help_size.x-88,22),16,INK,"strong")
		paragraph(help,instructions[index][1],Vector2(68,row_y+22),Vector2(help_size.x-88,40),13)
	var version := text(help,"Версия "+GameModel.BUILD_VERSION,Vector2(help_size.x-180,18),Vector2(160,20),12,INK_SOFT)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
