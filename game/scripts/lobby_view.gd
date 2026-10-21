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

func setup(owner_hud: GameHud) -> void:
	prepare(owner_hud)
	build_header()
	match hud.menu_tab:
		"equipment": build_equipment()
		"settings": build_settings()
		_: build_expedition()
	build_navigation()

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
	var entries := [["expedition","Восхождение",7],["equipment","Снаряжение",2],["settings","Настройки",15]]
	var each := (width-16)/3
	for index in range(3):
		var entry: Array = entries[index]
		var selected: bool = hud.menu_tab==entry[0]
		var tab := action(bar,str(entry[1]),Vector2(8+index*each,7),Vector2(each-(0 if index==2 else 4),50),func(): hud.select_menu(str(entry[0])),"selected" if selected else "ghost")
		tab.add_theme_font_size_override("font_size",14)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.add_theme_constant_override("h_separation",0)
		for state_name in ["normal","hover","pressed"]:
			var styled := tab.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
			styled.content_margin_left = 40
			styled.content_margin_right = 6
			tab.add_theme_stylebox_override(state_name,styled)
		symbol(tab,int(entry[2]),Vector2(10,12),Vector2(24,24),STONE if selected else INK_SOFT)

func scenic_card(at: Vector2, dimensions: Vector2) -> void:
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	var frame := slab(self,at,dimensions,STONE_SHADE,STONE_LIP,5)
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
		var lock := slab(frame,Vector2(16,16),Vector2(118,34),Color(SLATE,.88),SLATE_LIP,3)
		symbol(lock,14,Vector2(8,5),Vector2(24,24),STONE)
		text(lock,"Закрыто",Vector2(36,6),Vector2(78,22),14,STONE,"strong")
	text(frame,str(definition["name"]),Vector2(22,inner.y-94),Vector2(inner.x-44,48),36,STONE,"display")
	text(frame,["Тропа сквозь лес к большой высоте","Узкие уступы и длинные перелёты","Забытые руины над облаками"][game.lobby_location],Vector2(23,inner.y-46),Vector2(inner.x-120,24),15,Color("e3e8ea"))
	var total: int = model.balance["locations"].size()
	for index in range(total):
		var center := Vector2(inner.x-22-(total-1-index)*18,inner.y-34)
		var points := PackedVector2Array([center+Vector2(0,-6),center+Vector2(6,0),center+Vector2(0,6),center+Vector2(-6,0)])
		var marker := Polygon2D.new()
		marker.polygon = points
		marker.color = HOLD if index==game.lobby_location else Color(STONE,.45)
		frame.add_child(marker)
	for direction in [-1,1]:
		var arrow := action(frame,"",Vector2(14 if direction<0 else inner.x-62,inner.y*.40),Vector2(48,52),game.cycle_location.bind(direction))
		arrow.disabled = not model.profile["active"].is_empty()
		arrow.tooltip_text = "Предыдущий маршрут" if direction<0 else "Следующий маршрут"
		arrow.visible = not arrow.disabled
		symbol(arrow,10 if direction<0 else 11,Vector2(12,12),Vector2(24,24),INK)

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
	var price_name := "золота" if definition["currency"]=="gold" else "алмазов"
	var action_text := "Продолжить восхождение" if active else "Начать восхождение" if owned else "После первой вершины" if not model.profile["summit_cleared"] else "Открыть за %d %s" % [int(definition["price"]),price_name]
	var start := action(self,action_text,Vector2(x,mode_y+64),Vector2(width,66),game.lobby_action,"primary")
	start.add_theme_font_size_override("font_size",21)
	start.disabled = not active and not owned and not model.profile["summit_cleared"]
	var practice := action(self,"Тренировка: 16 зацепов",Vector2(x,mode_y+146),Vector2(width,52),game.start_practice)
	practice.disabled = active
	practice.tooltip_text = "Короткий маршрут с базовым снаряжением. Кошелёк не меняется."
	if active:
		paragraph(self,"Снаряжение можно улучшить после завершения попытки.",Vector2(x,mode_y+210),Vector2(width,40),13)
	elif landscape:
		paragraph(self,"Тренировка идёт с базовым снаряжением и не трогает кошелёк.",Vector2(x,mode_y+210),Vector2(width,40),13)

func build_equipment() -> void:
	var active: bool = not model.profile["active"].is_empty()
	title(self,"Снаряжение",Vector2(28,84),500,32)
	paragraph(self,"Заверши попытку, чтобы улучшать снаряжение." if active else "Новые уровни открываются, когда ты доходишь до следующей зоны.",Vector2(29,128),Vector2(size.x-56,22),14)
	var order := [GameModel.THROW,0,1,2,3,4,5]
	# Slow motion joins the list once balance.json gives it more than one level.
	if model.max_level(GameModel.SLOWMO)>1: order.append(GameModel.SLOWMO)
	var columns := 2 if landscape else 1
	var row_width := 504.0 if landscape else 484.0
	var row_height := 84.0 if landscape else 90.0 if order.size()<=7 else 80.0
	var per_column := 4 if landscape else order.size()
	for index in range(order.size()):
		var column := index/per_column
		var row := index%per_column
		build_upgrade(order[index],Vector2(28+column*(row_width+16),164+row*(row_height+8)),Vector2(row_width,row_height),active)

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
	text(frame,short_names[kind],Vector2(70,middle-32),Vector2(dimensions.x-240,24),17,INK,"strong")
	var effects := ["%d м" % int(model.value("rope_lengths",0)*10),"+%d%%" % roundi((model.value("impulse_factors",1)-1)*100),GameModel.HOOK_NAMES[mini(level,4)-1],"%d %s" % [model.level(3),"слот" if model.level(3)==1 else "слота" if model.level(3)<5 else "слотов"],"при касании" if model.level(4)==1 else "%d м" % int(model.value("magnet_radii",4)*10),"%d%%" % int(model.value("recovery_percents",5)),"%d м/с" % int(model.value("throw_speeds",GameModel.THROW)*10),seconds_text(model.slowmo_seconds())]
	var current := text(frame,effects[kind],Vector2(70,middle-7),Vector2(dimensions.x-240,26),19,INK,"display")
	if not maximum:
		var next_values := ["%d м" % int(model.balance["rope_lengths"][mini(level,5)]*10),"+%d%%" % roundi((float(model.balance["impulse_factors"][mini(level,5)])-1)*100),GameModel.HOOK_NAMES[mini(level,3)],"%d %s" % [level+1,"слота" if level+1<5 else "слотов"],"%d м" % int(model.balance["magnet_radii"][mini(level,5)]*10),"%d%%" % int(model.balance["recovery_percents"][mini(level,5)]),"%d м/с" % int(model.balance["throw_speeds"][mini(level,5)]*10),seconds_text(float(model.balance["slowmo_seconds"][mini(level,model.max_level(GameModel.SLOWMO)-1)]))]
		var shown := current.get_theme_font("font").get_string_size(current.text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
		text(frame,"→ "+next_values[kind],Vector2(70+shown+8,middle-4),Vector2(maxf(40,dimensions.x-250-shown),24),15,INK_SOFT)
	var meter := UpgradeMeter.new()
	meter.filled = level
	meter.total = model.max_level(kind)
	meter.unlocked = model.max_level(kind) if kind==2 else model.unlocked_upgrade_level()
	meter.position = Vector2(70,middle+23)
	meter.size = Vector2(minf(150,dimensions.x-240),6)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(meter)
	var value := "Максимум" if maximum else "После попытки" if active else "Достигни %d м" % roundi(level*float(model.balance["zone_units"])*float(model.balance["meters_per_unit"])) if locked else "Улучшить"
	var button_size := Vector2(150,dimensions.y-24)
	var purchase := action(frame,value,Vector2(dimensions.x-button_size.x-12,middle-button_size.y*.5),button_size,hud._buy_upgrade.bind(kind),"buy" if can_buy else "secondary")
	purchase.add_theme_font_size_override("font_size",15)
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
	frame.tooltip_text = model.upgrade_text(kind)+("\nДалее: "+model.upgrade_text(kind,level+1) if not maximum else "\nМаксимальный уровень")
	frame.mouse_filter = Control.MOUSE_FILTER_PASS

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
	var graphics := slab(self,Vector2(28,138),Vector2(column_width,150))
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
	var feedback := slab(self,Vector2(28,302),Vector2(column_width,212))
	section(feedback,"Звук и отклик")
	settings_switch(feedback,"Звук","Бросок, зацеп и находки",Vector2(20,52),column_width-40,bool(model.profile.get("sound",true)),hud.toggle_sound)
	settings_switch(feedback,"Вибрация","Короткий отклик при зацепе",Vector2(20,104),column_width-40,bool(model.profile.get("vibration",true)),hud.toggle_vibration)
	settings_switch(feedback,"Подсказки","Сообщения внизу экрана",Vector2(20,156),column_width-40,bool(model.profile.get("notifications",true)),hud.toggle_notifications)
	var help_at := Vector2(552,138) if landscape else Vector2(28,528)
	var help_size := Vector2(500,376) if landscape else Vector2(484,312)
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
	text(self,"Версия "+GameModel.BUILD_VERSION,Vector2(help_at.x+2,help_at.y+help_size.y+10),Vector2(300,20),12,INK_SOFT)
