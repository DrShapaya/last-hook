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
var aim_overlay: AimOverlay
var base_theme: Theme
var backdrop: LobbyView.Backdrop
var layout_mode := "modal"
var wide := false
const INK := Color("152b38")
const GOLD := Color("f3c668")
const WHITE := Color("eff5f3")
const MUTED := Color("b7c9cd")

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
	var rope_active := false
	var rope_pointer := Vector2.ZERO
	var aim_color := Color("f3c668")
	func _draw() -> void:
		if active:
			var direction := target-origin
			var count := int(direction.length()/13)
			for index in range(count):
				var t := float(index)/maxi(1,count)
				draw_circle(origin+direction*t,2.1,Color(aim_color,1-t*.6))
			draw_circle(target,6,aim_color,false,1.5)
		if rope_active:
			var color := Color("f3c668")
			draw_line(rope_pointer+Vector2(0,-28),rope_pointer+Vector2(0,28),color,2,true)
			draw_polyline(PackedVector2Array([rope_pointer+Vector2(-5,-22),rope_pointer+Vector2(0,-28),rope_pointer+Vector2(5,-22)]),color,2,true)
			draw_polyline(PackedVector2Array([rope_pointer+Vector2(-5,22),rope_pointer+Vector2(0,28),rope_pointer+Vector2(5,22)]),color,2,true)
			draw_circle(rope_pointer,7,color,false,2,true)

func setup(controller) -> void:
	game = controller
	base_theme = Theme.new()
	base_theme.default_font_size = 17
	base_theme.set_color("font_color","Label",WHITE)
	base_theme.set_color("font_color","Button",WHITE)
	base_theme.set_stylebox("normal","Button",style(Color("253f4d"),12,Color("54717c")))
	base_theme.set_stylebox("hover","Button",style(Color("355a66"),12,Color("85b6c0")))
	base_theme.set_stylebox("pressed","Button",style(Color("162e3b"),12,Color("8bc6d2")))
	base_theme.set_stylebox("disabled","Button",style(Color("253743"),12,Color("3c505c")))
	base_theme.set_color("font_disabled_color","Button",Color("879ca5"))
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
	backdrop.size = viewport_size
	backdrop.visible = layout_mode=="menu"
	backdrop.queue_redraw()
	toast_label.position = Vector2((root.size.x-464)*.5,root.size.y-(154 if layout_mode=="play" else 59))

func _resize() -> void:
	fit_viewport()
	if layout_mode=="menu": show_menu()
	elif layout_mode=="play": show_play()

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
	return node

func panel(at: Vector2, dimensions: Vector2, parent: Node = null) -> VBoxContainer:
	var card := PanelContainer.new()
	card.position = at
	card.size = dimensions
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel",style(Color(.065,.12,.17,.94),18,Color(.40,.55,.62,.6)))
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
	bag_panel = null
	goal_label = null
	aim_label = null
	climb_bar = null
	aim_overlay.active = false
	aim_overlay.rope_active = false
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
	fit_viewport()
	var lobby := LobbyView.new()
	content.add_child(lobby)
	lobby.setup(self)

func show_play() -> void:
	clear()
	layout_mode = "play"
	fit_viewport()
	var top := panel(Vector2(20,22),Vector2(228,84))
	top.add_theme_constant_override("separation",2)
	height_label = label(top,"0 м",30)
	record_label = label(top,"Рекорд: 0 м",13,GOLD)
	var pause_button := button(content,"Ⅱ",game.pause_run)
	pause_button.position = Vector2(root.size.x-78,22)
	pause_button.size = Vector2(58,58)
	pause_button.add_theme_font_size_override("font_size",27)
	danger_label = label(content,"",14,Color("ffbe97"))
	danger_label.position = Vector2(23,119)
	danger_label.size = Vector2(275,28)
	goal_label = label(content,"",13,MUTED)
	goal_label.position = Vector2(24,151)
	goal_label.size = Vector2(root.size.x-48,24)
	goal_label.add_theme_color_override("font_color",WHITE)
	goal_label.add_theme_color_override("font_shadow_color",Color("13232b"))
	goal_label.add_theme_constant_override("shadow_outline_size",4)
	aim_label = label(content,"",14,GOLD)
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
			slot.on_discard = _discard.bind(index)
		bag_panel.add_child(slot)

func _discard(index: int) -> void:
	game.model.discard(index)
	refresh_bag()
	game.save_snapshot()

func update_play() -> void:
	toast_label.visible = game.hint_timer>0
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
	goal_label.text = GameModel.ZONE_NAMES[zone]+" · "+game.model.next_goal()
	var lesson := tutorial_hint()
	if not lesson.is_empty(): goal_label.text = lesson
	aim_overlay.active = game.pressed and not game.sim.attached
	aim_overlay.rope_active = game.rope_touch>=0 and game.sim.attached
	aim_overlay.rope_pointer = game.rope_pointer
	aim_overlay.origin = game.camera.unproject_position(Vector3(game.sim.pos.x,game.sim.pos.y,0))
	var point: Vector2 = game.sim.pos+game.aim_direction*game.model.shot_range()
	aim_label.text = "Канат: %d / %d м" % [roundi(game.sim.length*10),roundi(game.model.shot_range()*10)] if game.sim.attached else ""
	if game.sim.attached:
		var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
		if not current.is_empty():
			aim_label.text += " · постоянная" if current.get("permanent",true) else " · исчезнет при отпускании"
	aim_overlay.aim_color = GOLD
	if aim_overlay.active:
		aim_label.text = "Канат до %d м · крюк %d м/с" % [roundi(game.model.shot_range()*10),roundi(game.model.value("throw_speeds",GameModel.THROW)*10)]
		var collision: Dictionary = game.world.cast_hook(game.sim.pos,point,game.model.hook_radius())
		if not collision.is_empty():
			point = collision["contact"]
			if collision.get("blocked",false):
				aim_label.text = "Выстрел перекрыт выступом"
				aim_overlay.aim_color = Color("ff987f")
			else:
				aim_label.text = game.world.object_description(collision["object"])
				aim_overlay.aim_color = Color("8ae0ac")
				aim_label.text += " · %.2f с" % (game.sim.pos.distance_to(point)/game.model.value("throw_speeds",GameModel.THROW))
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
	var mobile := OS.has_feature("mobile")
	if "aim" not in learned:
		return "Прицелься в выступ и отпусти первый палец" if mobile else "Зажми ЛКМ, прицелься в выступ и отпусти"
	if not game.sim.attached:
		return "В полёте прицелься и поймай следующую опору" if game.catches<2 else ""
	if "swing" not in learned:
		return "Первый палец влево/вправо: раскачайся в такт" if mobile else "A / D: раскачайся в такт движению"
	if "rope" not in learned:
		return "Веди второй палец вверх/вниз: измени канат" if mobile else "W / S или колесо: измени длину каната"
	if "release" not in learned:
		return "Тап вторым пальцем: отпусти на взлёте" if mobile else "Пробел: отпусти канат на взлёте и целься снова"
	return ""

func world_input_allowed(point: Vector2) -> bool:
	var local_point := root.get_global_transform_with_canvas().affine_inverse()*point
	return local_point.y>112 and local_point.y<root.size.y-86

func set_toast(text: String) -> void:
	toast_label.text = text

func show_workshop() -> void:
	show_menu()

func _buy_upgrade(kind: int) -> void:
	var message: String = game.model.purchase(kind)
	show_menu()
	game.toast(message)

func show_locations() -> void:
	show_menu()

func show_pause() -> void:
	clear()
	var column := panel(Vector2(45,280),Vector2(450,380))
	label(column,"Пауза",31)
	label(column,"Текущая попытка сохранена",16,MUTED)
	label(column,"Первый палец: прицел и раскачка.\nВторой: тап — отпустить, вверх/вниз — длина.\nУдерживай ячейку, чтобы выбросить предмет." if OS.has_feature("mobile") else "ЛКМ: прицел и бросок. A / D: раскачка.\nW / S или колесо: канат. Пробел: отпустить.\nУдерживай ячейку, чтобы выбросить предмет.",13,MUTED)
	button(column,"Продолжить",game.unpause,true)
	button(column,"Завершить и получить награду",func(): game.finish_run(false))
	button(column,"В меню · сохранить попытку",game.show_menu)

func show_revive(reason: String = "Падение") -> void:
	clear()
	var column := panel(Vector2(35,303),Vector2(470,365))
	label(column,"Ещё один зацеп?",30)
	label(column,reason,16,MUTED)
	var info := label(column,"Одно продолжение за попытку.\nВысота и рюкзак сохраняются.",16,MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if OS.is_debug_build():
		button(column,"Возродиться · тест рекламы",func(): game.revive("test_ad"),true)
	else:
		var advertisement := button(column,"Реклама пока не подключена",func(): pass)
		advertisement.disabled = true
	var diamonds := button(column,"Возродиться · 3 алмаза",func(): game.revive("diamonds"))
	diamonds.disabled = int(game.model.profile["diamonds"])<3
	button(column,"Завершить попытку",func(): game.finish_run(false))
	label(column,"Тест рекламы не показывает настоящий рекламный ролик",11,MUTED)

func show_result(result: Dictionary) -> void:
	clear()
	var column := panel(Vector2(30,204),Vector2(480,580))
	label(column,"Вершина достигнута!" if result.get("success",false) else "Новая попытка — выше",29)
	label(column,"Максимальная высота: %d м" % int(result.get("highest",0)),19,GOLD)
	var duration := int(result.get("seconds",0))
	label(column,"%d:%02d · зацепов %d из %d" % [duration/60,duration%60,int(result.get("catches",0)),int(result.get("shots",0))],13,MUTED)
	label(column,"За высоту                  +%d" % int(result.get("height",0)),17)
	label(column,"Из рюкзака                 +%d / %d" % [int(result.get("loot",0)),int(result.get("carried",0))],17)
	if int(result.get("finish",0))>0:
		label(column,"Награда за вершину          +%d" % int(result["finish"]),17)
	if int(result.get("zone_bonus",0))>0:
		label(column,"За новые зоны +%d · уже выдано" % int(result["zone_bonus"]),14,MUTED)
	label(column,"ЗА ПОПЫТКУ: %d ЗОЛОТА" % (int(result.get("total",0))+int(result.get("zone_bonus",0))),24,GOLD)
	var recommendation: int = game.model.recommended_upgrade()
	if recommendation>=0:
		label(column,"Доступно: %s · %d золота" % [GameModel.UPGRADE_NAMES[recommendation],game.model.cost(recommendation)],13,GOLD)
	if result.get("first",false):
		var text := label(column,"Открыты бесконечный режим и покупка локаций. +20 алмазов",14,Color("a8deee"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(column,"ЕЩЁ ОДНА ПОПЫТКА",func(): game.start_run(game.run_mode=="endless"),true)
	button(column,"Улучшить оснащение",game.show_workshop)
	button(column,"В меню",game.show_menu)
