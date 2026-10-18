class_name LobbyView
extends MenuSurface

class UpgradeMeter extends Control:
	var filled := 1
	var unlocked := 1
	var total := 6
	func _draw() -> void:
		var width := (size.x-5*(total-1))/total
		for index in range(total):
			var box := StyleBoxFlat.new()
			box.set_corner_radius_all(3)
			box.bg_color = Color("efc779") if index<filled else Color("405548") if index<unlocked else Color("253a32")
			draw_style_box(box,Rect2(index*(width+5),0,width,size.y))

class Backdrop extends Control:
	func _draw() -> void:
		for band in range(80):
			draw_rect(Rect2(0,size.y*band/80,size.x,size.y/80+1),Color("203c35").lerp(Color("091b1d"),float(band)/79))
		var unit := minf(size.x,size.y)
		draw_circle(Vector2(size.x*.88,size.y*.12),unit*.48,Color(.77,.78,.49,.025))
		for contour in range(16):
			var points := PackedVector2Array()
			for index in range(70):
				var x := size.x*index/69
				points.append(Vector2(x,size.y*.30+contour*unit*.065+sin(index*.13+contour*.18)*unit*.09+cos(index*.25)*unit*.025))
			draw_polyline(points,Color(.65,.78,.59,.035),1,true)

func setup(owner_hud: GameHud) -> void:
	prepare(owner_hud)
	build_header()
	match hud.menu_tab:
		"equipment": build_equipment()
		"settings": build_settings()
		_: build_expedition()
	build_navigation()

func build_header() -> void:
	var mark := TextureRect.new()
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.texture = preload("res://assets/icon.svg")
	mark.position = Vector2(28,25)
	mark.size = Vector2(46,46)
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.material = rounded_material(mark.size,12)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	text(self,"LAST HOOK",Vector2(82,22),Vector2(230,34),25,PAPER,true)
	eyebrow(self,"ВЫШЕ С КАЖДЫМ БРОСКОМ",Vector2(83,57),235,MUTED)
	wallet(Vector2(844,29) if landscape else Vector2(304,29))

func build_navigation() -> void:
	var at := Vector2((size.x-496)*.5,size.y-84)
	var bar := card(self,at,Vector2(496,62),Color("122927"),Color("3b5145"),20)
	var entries := [["expedition","Восхождение",7],["equipment","Снаряжение",2],["settings","Настройки",15]]
	for index in range(3):
		var entry: Array = entries[index]
		var selected: bool = hud.menu_tab==entry[0]
		var tab := action(bar,str(entry[1]),Vector2(6+index*163,6),Vector2(158,50),func(): hud.select_menu(str(entry[0])),"selected" if selected else "ghost")
		tab.add_theme_font_size_override("font_size",13)
		tab.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		symbol(tab,int(entry[2]),Vector2(9,13),Vector2(23,23),GOLD if selected else MUTED)

func scenic_card(at: Vector2, dimensions: Vector2) -> void:
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var frame := card(self,at,dimensions,Color("304e44"),Color("547263"),24)
	frame.clip_contents = true
	var preview := LevelPreview.new()
	preview.world = game.world
	preview.position = Vector2(1,1)
	preview.size = dimensions-Vector2(2,2)
	preview.material = rounded_material(preview.size)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(preview)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("183e3610"),Color("102a27f5")])
	gradient.offsets = PackedFloat32Array([.25,1])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0,1)
	shade.texture = texture
	shade.position = Vector2(1,1)
	shade.size = dimensions-Vector2(2,2)
	shade.material = rounded_material(shade.size)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shade)
	eyebrow(frame,"ЭКСПЕДИЦИЯ / %02d" % (game.lobby_location+1),Vector2(24,21),260,PAPER)
	var height_tag := card(frame,Vector2(dimensions.x-112,17),Vector2(92,30),Color("12342bca"),Color("b4c69c50"),10)
	text(height_tag,"%d м" % (int(definition["height_units"])*10),Vector2(0,5),Vector2(92,22),12,PAPER,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text(frame,str(definition["name"]),Vector2(24,dimensions.y-101),Vector2(dimensions.x-48,46),32,PAPER,true)
	text(frame,["Тропа сквозь лес к большой высоте","Узкие уступы. Длинные перелёты.","Забытые руины над облаками."][game.lobby_location],Vector2(25,dimensions.y-53),Vector2(dimensions.x-50,27),13,Color("c3d6bc"))
	for direction in [-1,1]:
		var arrow := action(frame,"",Vector2(16 if direction<0 else dimensions.x-62,dimensions.y*.40),Vector2(46,48),game.cycle_location.bind(direction))
		arrow.disabled = not model.profile["active"].is_empty()
		symbol(arrow,10 if direction<0 else 11,Vector2(11,12),Vector2(24,24),PAPER)

func build_expedition() -> void:
	var active: bool = not model.profile["active"].is_empty()
	var definition: Dictionary = model.balance["locations"][game.lobby_location]
	var owned: bool = model.profile["locations"].has(game.lobby_location)
	scenic_card(Vector2(28,104),Vector2(604,350) if landscape else Vector2(484,346))
	var x := 660.0 if landscape else 28.0
	var y := 106.0 if landscape else 470.0
	var width := 392.0 if landscape else 484.0
	eyebrow(self,"ТВОЯ СЛЕДУЮЩАЯ ВЫСОТА" if not active else "ЭКСПЕДИЦИЯ ЖДЁТ",Vector2(x,y),width)
	text(self,"Продолжим путь?" if active else "Пора наверх.",Vector2(x,y+24),Vector2(width,42),30,PAPER,true)
	paragraph(self,"Попытка сохранена. Вернись к своему зацепу." if active else "Выбери дугу. Поймай опору. Сохрани инерцию.",Vector2(x,y+72),Vector2(width,45),14)
	var mode_y := y+128
	for index in range(2):
		var selected: bool = game.lobby_endless==(index==1)
		var mode := action(self,"Вершина" if index==0 else "Бесконечно",Vector2(x+index*(width+10)*.5,mode_y),Vector2((width-10)*.5,48),func(): game.lobby_endless=index==1; hud.show_menu(),"selected" if selected else "secondary")
		mode.disabled = active or (index==1 and not model.profile["summit_cleared"])
		mode.tooltip_text = "Откроется после первой вершины" if index==1 and not model.profile["summit_cleared"] else ""
	var action_text := "Продолжить восхождение" if active else "Начать восхождение" if owned else "После первой вершины" if not model.profile["summit_cleared"] else "Открыть · %d %s" % [int(definition["price"]),"золота" if definition["currency"]=="gold" else "алмазов"]
	var start := action(self,action_text,Vector2(x,mode_y+62),Vector2(width,60),game.lobby_action,"primary")
	start.disabled = not active and not owned and not model.profile["summit_cleared"]
	var stats_y := 474.0 if landscape else 738.0
	var stats_width := 604.0 if landscape else 484.0
	stat(self,"%d м" % int(model.profile["best"]),"ЛИЧНЫЙ РЕКОРД",Vector2(28,stats_y),Vector2((stats_width-12)*.5,72),7)
	stat(self,str(int(model.profile["wins"])),"ПОКОРЁННЫХ ВЕРШИН",Vector2(28+(stats_width+12)*.5,stats_y),Vector2((stats_width-12)*.5,72),16)
	var practice := action(self,"Тренировка · 16 зацепов",Vector2(x,390 if landscape else 822),Vector2(width,50),game.start_practice)
	practice.disabled = active
	if landscape:
		paragraph(self,"Освой один палец на коротком маршруте.\nБазовое оснащение · без риска для кошелька.",Vector2(x,453),Vector2(width,46),13)
	if active:
		text(self,"Улучшения доступны после завершения попытки",Vector2(x,mode_y+126),Vector2(width,22),11,MUTED)

func build_equipment() -> void:
	eyebrow(self,"МАСТЕРСКАЯ / СНАРЯЖЕНИЕ",Vector2(28,105),700 if landscape else 484)
	text(self,"Собери свой подъём.",Vector2(28,131),Vector2(900 if landscape else 484,42),30,PAPER,true)
	var active: bool = not model.profile["active"].is_empty()
	text(self,"Заверши попытку, чтобы улучшать оснащение." if active else "Каждое улучшение — новая возможность в полёте.",Vector2(29,180),Vector2(900 if landscape else 484,26),13,MUTED)
	var order := [GameModel.THROW,0,1,2,3,4,5]
	var columns := 4 if landscape else 2
	var card_width := 244.0 if landscape else 234.0
	var card_height := 166.0 if landscape else 150.0
	for index in range(order.size()):
		build_upgrade(order[index],Vector2(28+(index%columns)*(card_width+16),222+(index/columns)*(card_height+14)),Vector2(card_width,card_height),active)
	var last_at := Vector2(808,402) if landscape else Vector2(278,714)
	var note := card(self,last_at,Vector2(card_width,card_height),Color("21352c"),Color("4a5740"))
	symbol(note,7,Vector2(17,16),Vector2(28,28),TEAL)
	eyebrow(note,"НОВЫЕ ВОЗМОЖНОСТИ",Vector2(17,56),card_width-34,TEAL)
	paragraph(note,"Достигай новых зон, чтобы открывать следующие уровни.",Vector2(17,82),Vector2(card_width-34,66),13)

func build_upgrade(kind: int, at: Vector2, dimensions: Vector2, active: bool) -> void:
	var frame := card(self,at,dimensions)
	var level := model.level(kind)
	var maximum := level>=model.max_level(kind)
	var locked := not maximum and not model.upgrade_available(kind)
	var can_buy := not active and not locked and not maximum and int(model.profile["gold"])>=model.cost(kind)
	var accent: Color = [GOLD,Color("dfa97a"),TEAL,Color("bfcd96"),Color("a4c5cf"),Color("c2afd3"),GOLD][kind]
	var short_names := ["Длина каната","Импульс","Крюки","Рюкзак","Магнит","Защита добычи","Сила броска"]
	symbol(frame,kind,Vector2(14,15),Vector2(28,28),accent)
	text(frame,short_names[kind],Vector2(52,13),Vector2(dimensions.x-64,24),15,PAPER,true)
	text(frame,"ШИРИНА ЗАЦЕПА / ДВОЙНОЙ БРОСОК" if kind==2 else "УРОВЕНЬ %d / %d" % [level,model.max_level(kind)],Vector2(53,39),Vector2(dimensions.x-65,18),10,MUTED)
	var hook_effect: String = GameModel.HOOK_NAMES[level-1] if kind==2 else ""
	var effects := ["%d м" % int(model.value("rope_lengths",0)*10),"+%d%%" % roundi((model.value("impulse_factors",1)-1)*100),hook_effect,"%d слотов" % model.level(3),"При касании" if model.level(4)==1 else "%d м" % int(model.value("magnet_radii",4)*10),"%d%%" % int(model.value("recovery_percents",5)),"%d м/с" % int(model.value("throw_speeds",GameModel.THROW)*10)]
	text(frame,GameModel.HOOK_NAMES[level-1] if kind==2 else effects[kind],Vector2(15,61),Vector2(138,29),16 if kind==2 else 20,accent,true)
	if not maximum:
		var next_values := ["%d м" % int(model.balance["rope_lengths"][mini(level,5)]*10),"+%d%%" % roundi((float(model.balance["impulse_factors"][mini(level,5)])-1)*100),GameModel.HOOK_NAMES[mini(level,3)],str(level+1),"%d м" % int(model.balance["magnet_radii"][mini(level,5)]*10),"%d%%" % int(model.balance["recovery_percents"][mini(level,5)]),str(int(model.balance["throw_speeds"][mini(level,5)]*10))]
		text(frame,"→ "+(str(level+1) if kind==2 else next_values[kind]),Vector2(148,69),Vector2(dimensions.x-164,23),12,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var meter := UpgradeMeter.new()
	meter.filled = level
	meter.total = model.max_level(kind)
	meter.unlocked = model.max_level(kind) if kind==2 else model.unlocked_upgrade_level()
	meter.position = Vector2(16,dimensions.y-58)
	meter.size = Vector2(dimensions.x-32,5)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(meter)
	var value := "Максимум" if maximum else "После попытки" if active else "Достигни %d м" % roundi(level*float(model.balance["zone_units"])*float(model.balance["meters_per_unit"])) if locked else "Улучшить · %d" % model.cost(kind)
	var purchase := action(frame,value,Vector2(10,dimensions.y-48),Vector2(dimensions.x-20,44),hud._buy_upgrade.bind(kind),"primary" if can_buy else "secondary")
	purchase.add_theme_font_size_override("font_size",13)
	purchase.disabled = not can_buy
	frame.tooltip_text = model.upgrade_text(kind)+( "\nДалее: "+model.upgrade_text(kind,level+1) if not maximum else "\nМаксимальный уровень")

func build_settings() -> void:
	eyebrow(self,"БАЗОВЫЙ ЛАГЕРЬ / НАСТРОЙКИ",Vector2(28,105),700 if landscape else 484)
	text(self,"В твоём ритме.",Vector2(28,131),Vector2(900 if landscape else 484,44),32,PAPER,true)
	paragraph(self,"Всё, что нужно перед следующим восхождением.",Vector2(29,183),Vector2(900 if landscape else 484,30),14)
	var audio_card := card(self,Vector2(28,238),Vector2(484,102))
	emblem(audio_card,17,Vector2(18,22),TEAL)
	text(audio_card,"Звук игры",Vector2(94,22),Vector2(220,28),20,PAPER,true)
	text(audio_card,"Бросок, зацеп и находки",Vector2(95,57),Vector2(235,23),13,MUTED)
	var enabled: bool = model.profile.get("sound",true)
	action(audio_card,"Вкл" if enabled else "Выкл",Vector2(370,29),Vector2(94,46),hud.toggle_sound,"selected" if enabled else "secondary")
	var help_at := Vector2(548,238) if landscape else Vector2(28,360)
	var help := card(self,help_at,Vector2(504 if landscape else 484,302))
	eyebrow(help,"УПРАВЛЕНИЕ",Vector2(24,21),440)
	text(help,"Один палец. Вся высота." if hud.touch_controls_hint else "Поймай свой ритм.",Vector2(24,51),Vector2(440,35),24,PAPER,true)
	var instructions := [["01","Брось крюк","Коснись где удобно, потяни как стик и отпусти."],["02","Раскачайся","На канате веди палец влево или вправо."],["03","Выбери длину","Держи строго вверх / вниз 0,28 секунды."],["04","Отцепись","Отпусти палец. Новый бросок — новое касание."]]
	if not hud.touch_controls_hint:
		instructions = [["01","Раскачайся","A / D или стрелки влево / вправо."],["02","Выбери длину","W / S или колесо мыши."],["03","Перелети","Пробел — отпустить. ЛКМ — прицел и бросок."]]
	for index in range(instructions.size()):
		var row_y := 104+index*(46 if instructions.size()==4 else 62)
		text(help,instructions[index][0],Vector2(24,row_y),Vector2(35,27),14,TEAL,true)
		text(help,instructions[index][1],Vector2(68,row_y-2),Vector2(400,25),16,PAPER,true)
		text(help,instructions[index][2],Vector2(68,row_y+23),Vector2(410,23),12,MUTED)
	var about := card(self,Vector2(28,362 if landscape else 686),Vector2(484,118),Color("102625"))
	eyebrow(about,"ТВОЙ ПРОГРЕСС",Vector2(23,18),430,TEAL)
	text(about,"%d попыток  /  %d вершин" % [int(model.profile["runs"]),int(model.profile["wins"])],Vector2(23,48),Vector2(430,30),21,PAPER,true)
	text(about,"Прогресс сохраняется автоматически",Vector2(23,85),Vector2(430,22),12,MUTED)
	text(self,"LAST HOOK  /  "+GameModel.BUILD_VERSION,Vector2(30,518 if landscape else 814),Vector2(480,26),11,MUTED)
