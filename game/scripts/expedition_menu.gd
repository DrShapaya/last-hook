class_name ExpeditionMenu
extends MenuSurface

static func plural(count: int, one: String, few: String, many: String) -> String:
	var tens := count%100
	var units := count%10
	if tens>=11 and tens<=14: return many
	if units==1: return one
	if units>=2 and units<=4: return few
	return many

func heading(value: String, subtitle: String, width: float) -> void:
	title(self,value,Vector2(28,34),width,38)
	paragraph(self,subtitle,Vector2(29,88),Vector2(width,44),15)

# Large height figure with its unit set smaller on the same baseline.
func height_figure(parent: Node, meters: int, at: Vector2, font_size: int) -> void:
	var number := text(parent,str(meters),at,Vector2(400,font_size*1.2),font_size,INK,"display")
	var shown: float = hud.heading_font.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var unit_size := int(font_size*.38)
	text(parent,"м",at+Vector2(shown+8,font_size*.72-unit_size*.6),Vector2(60,unit_size*1.3),unit_size,INK_SOFT,"display")

func inline_stat(parent: Node, value: String, caption: String, at: Vector2, width: float) -> void:
	text(parent,value,at,Vector2(width,30),24,INK,"display")
	text(parent,caption,at+Vector2(0,30),Vector2(width,20),13,INK_SOFT)

# Pause and the second chance are bottom sheets over the frozen, veiled
# climb: everything sits in one stone sheet within thumb reach, with exactly
# one primary action.
const SHEET_PAD := 22.0

func sheet_width() -> float:
	return minf(hud.root.size.x-32,560.0)

# Covers the whole root (the climb shows through the veil above the sheet).
func open_sheet() -> Panel:
	size = hud.root.size
	position = Vector2.ZERO
	# A shade darker than the buttons, so stone actions stand out on it.
	return slab(self,Vector2.ZERO,Vector2(sheet_width(),100),STONE_SHADE,STONE_LIP,5)

# Sizes the sheet to its content and docks it to the bottom safe edge.
func close_sheet(sheet: Panel, content_height: float) -> void:
	sheet.size = Vector2(sheet_width(),content_height+SHEET_PAD)
	sheet.position = Vector2((size.x-sheet.size.x)*.5,size.y-hud.safe_inset_bottom()-16-sheet.size.y)

# Bag contents in one row of small cells with the total on the right.
func bag_strip(parent: Node, at: Vector2, width: float) -> float:
	var rows: int = model.bag.size()
	text(parent,"Рюкзак",at,Vector2(120,24),17,INK,"display")
	text(parent,"%d из %d" % [rows,model.bag_capacity()],at+Vector2(82,3),Vector2(80,20),13,INK_SOFT)
	var total := str(model.bag_value())
	var total_width: float = hud.heading_font.get_string_size(total,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
	coin_amount(parent,model.bag_value(),at+Vector2(width-total_width-27,0),18)
	if model.bag.is_empty():
		text(parent,"Пусто. Находки с уступов попадут сюда.",at+Vector2(0,34),Vector2(width,20),14,INK_SOFT)
		return 60.0
	for index in range(rows):
		var item: Dictionary = model.bag[index]
		var slot := BagSlot.new()
		slot.item = item
		slot.rare = model.item_is_rare(item)
		slot.position = at+Vector2(index*48,32)
		slot.size = Vector2(42,42)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.tooltip_text = GameModel.loot_name(item)
		parent.add_child(slot)
	return 82.0

func rule(parent: Node, at: Vector2, width: float) -> void:
	var line := ColorRect.new()
	line.color = Color(STONE_LIP,.8)
	line.position = at
	line.size = Vector2(width,2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func build_pause() -> void:
	var practice: bool = game.run_mode=="practice"
	var sheet := open_sheet()
	var inner := sheet_width()-SHEET_PAD*2
	var x := SHEET_PAD
	var y := SHEET_PAD
	text(sheet,"Пауза",Vector2(x,y-2),Vector2(inner*.6,40),30,INK,"display")
	var clock := text(sheet,time_string(game.run_seconds)+" в пути",Vector2(x+inner*.5,y+8),Vector2(inner*.5,22),15,INK_SOFT)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	y += 46
	paragraph(sheet,"Тренировка: кошелёк и снаряжение не меняются." if practice else "Попытка сохранится, даже если выйти в лагерь.",Vector2(x,y),Vector2(inner,20),14)
	y += 30
	var climbed := maxi(0,roundi((game.sim.highest-game.START_Y)*10))
	if not practice:
		route(sheet,Vector2(x,y),inner,climbed)
		y += RouteLine.HEIGHT+14
		rule(sheet,Vector2(x,y),inner)
		y += 16
		y += bag_strip(sheet,Vector2(x,y),inner)+14
	else:
		height_figure(sheet,climbed,Vector2(x,y),48)
		y += 70
	action(sheet,"Продолжить",Vector2(x,y),Vector2(inner,64),game.unpause,"primary").add_theme_font_size_override("font_size",22)
	y += 76
	var half := (inner-10)*.5
	action(sheet,"Выйти" if practice else "В лагерь",Vector2(x,y),Vector2(half,52),game.show_menu)
	var finish := action(sheet,"Завершить" if practice else "Забрать награду",Vector2(x+half+10,y),Vector2(half,52),func(): game.finish_run(false))
	finish.tooltip_text = "Завершить попытку и оформить награду за пройденное."
	y += 52
	close_sheet(sheet,y)

func build_revive(reason: String) -> void:
	var available: bool = game.revive_available()
	var return_y: float = game.safe_contact.y-2.8 if game.safe_anchor_id>=0 else game.safe_position.y
	var return_height := maxi(0,roundi((return_y-game.START_Y)*10))
	var sheet := open_sheet()
	var inner := sheet_width()-SHEET_PAD*2
	var x := SHEET_PAD
	var y := SHEET_PAD
	text(sheet,"Ещё один шанс" if available else "Опоры рядом нет",Vector2(x,y-2),Vector2(inner,40),30,INK,"display")
	y += 42
	paragraph(sheet,reason,Vector2(x,y),Vector2(inner,20),15)
	y += 34
	if available:
		# Where the climb resumes, as one clear line.
		var spot := slab(sheet,Vector2(x,y),Vector2(inner,64),Color(STONE,.7),Color.TRANSPARENT,0)
		text(spot,"Вернёшься к опоре",Vector2(16,10),Vector2(inner-150,22),16,INK,"strong")
		text(spot,"Высота и рюкзак сохранятся",Vector2(16,33),Vector2(inner-150,20),13,INK_SOFT)
		var figure := text(spot,"%d м" % return_height,Vector2(inner-150,12),Vector2(134,40),30,INK,"display")
		figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		y += 80
	else:
		paragraph(sheet,"На этом участке не осталось безопасной цепочки опор. Забери награду или начни заново.",Vector2(x,y),Vector2(inner,40),14)
		y += 56
	var price := int(model.balance["diamond_revive_cost"])
	var owned := int(model.profile["diamonds"])
	if available:
		var diamonds := action(sheet,"Продолжить за %d %s" % [price,plural(price,"алмаз","алмаза","алмазов")],Vector2(x,y),Vector2(inner,64),func(): game.revive("diamonds"),"primary")
		diamonds.add_theme_font_size_override("font_size",20)
		diamonds.disabled = owned<price
		y += 70
		symbol(sheet,13,Vector2(x,y+1),Vector2(18,18),CRYSTAL)
		text(sheet,"У тебя %d %s" % [owned,plural(owned,"алмаз","алмаза","алмазов")] if owned>=price else "Не хватает алмазов: есть %d из %d" % [owned,price],Vector2(x+24,y),Vector2(inner-24,20),13,INK_SOFT if owned>=price else DANGER)
		y += 30
		if game.ads.supported:
			var ad_ready: bool = game.ads.rewarded_ready
			var ad := action(sheet,"Посмотреть рекламу и продолжить" if ad_ready else "Реклама загружается…",Vector2(x,y),Vector2(inner,52),game.request_ad_revive)
			ad.disabled = game.ads.fullscreen or not ad_ready
			y += 64
		elif OS.is_debug_build():
			action(sheet,"Тестовое продолжение",Vector2(x,y),Vector2(inner,52),func(): game.revive("test_ad"))
			y += 64
	var half := (inner-10)*.5
	# Without a rescue, starting over is the way forward.
	var restart := action(sheet,"Начать заново",Vector2(x,y),Vector2(half,52),game.restart_failed_run,"secondary" if available else "primary")
	restart.add_theme_font_size_override("font_size",17)
	action(sheet,"Забрать награду",Vector2(x+half+10,y),Vector2(half,52),func(): game.finish_run(false))
	y += 52
	close_sheet(sheet,y)

# Sets, landmarks, materials and spent items: what changed beyond gold.
static func progress_line(result: Dictionary) -> String:
	var parts: Array = []
	for entry in result.get("sets",[]):
		parts.append(("Комплект собран: %s" if entry.get("completed",false) else "%s %d/3") % ([entry["name"]] if entry.get("completed",false) else [entry["name"],int(entry["parts"])]))
	for id in result.get("landmarks",[]): parts.append("ориентир: "+str(ItemCatalog.balance()["sets"].get(id,{}).get("landmark",id)))
	var materials: Dictionary = result.get("materials",{})
	for id in materials.keys(): parts.append("%s +%d" % [ItemCatalog.material_name(id),int(materials[id])])
	var spent: Array = result.get("spent",[])
	if not spent.is_empty(): parts.append("использовано: "+", ".join(spent.map(func(id): return str(ItemCatalog.consumable(str(id)).get("name",id)))))
	return " · ".join(parts) if not parts.is_empty() else "Комплекты, материалы и контракты — на боковых ветках."

func build_result(result: Dictionary) -> void:
	var practice: bool = result.get("mode","")=="practice"
	var success: bool = result.get("success",false)
	var column := 480.0 if landscape else 484.0
	var heading_text := "Вершина твоя" if success else "Следующий раз — выше"
	if practice: heading_text = "Маршрут освоен" if success else "Найди свою дугу"
	var subtitle := "Тот же маршрут, больше уверенности." if practice else "Каждый бросок привёл тебя сюда." if success else str(result.get("reason","Новая высота уже ждёт."))
	heading(heading_text,subtitle,column)
	var highest := int(result.get("highest",0))
	height_figure(self,highest,Vector2(26,124),92)
	if not practice: route(self,Vector2(28,250),column,highest)
	var stats_y := 316.0 if not practice else 252.0
	inline_stat(self,time_string(float(result.get("seconds",0))),"в пути",Vector2(28,stats_y),180)
	inline_stat(self,"%d из %d" % [int(result.get("catches",0)),int(result.get("shots",0))],"бросков в цель",Vector2(28+column*.5,stats_y),column*.5)
	var right_x := 556.0 if landscape else 28.0
	var right_y := 136.0 if landscape else 392.0
	var right_width := 496.0 if landscape else 484.0
	var panel_height := 312.0 if not practice else 150.0
	var reward := slab(self,Vector2(right_x,right_y),Vector2(right_width,panel_height))
	if practice:
		text(reward,"Попробуй ещё одну дугу",Vector2(20,18),Vector2(right_width-40,30),22,INK,"display")
		paragraph(reward,"Пройди увереннее, сохрани скорость или забери находку на боковом пути. Кошелёк и снаряжение не изменились.",Vector2(20,58),Vector2(right_width-40,72),15)
	else:
		text(reward,"Награда",Vector2(20,16),Vector2(200,26),18,INK,"display")
		var recovery := int(result.get("recovery",100))
		var loot_title := "Рюкзак продан" if success else "Рюкзак: сохранено %d%%" % recovery
		var rows := [["За высоту",int(result.get("height",0))],[loot_title,int(result.get("loot",0))],["Бонус вершины",int(result.get("finish",0))],
			["Контракт выполнен" if result.get("contract_done",false) else "Контракт",int(result.get("contract",0))],
			["Монеты, уже на счету",int(result.get("coins",0))],["Новые зоны, уже на счету",int(result.get("zone_bonus",0))]]
		for index in range(rows.size()):
			var row_y := 48+index*24
			var muted: bool = int(rows[index][1])==0
			text(reward,rows[index][0],Vector2(20,row_y),Vector2(right_width-140,22),14,INK_FAINT if muted else INK_SOFT)
			text(reward,"+%d" % rows[index][1],Vector2(right_width-120,row_y),Vector2(100,22),15,INK_FAINT if muted else INK,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		paragraph(reward,progress_line(result),Vector2(20,196),Vector2(right_width-40,40),12,INK_SOFT).name = "Progress"
		var rule := ColorRect.new()
		rule.color = STONE_LIP
		rule.position = Vector2(20,240)
		rule.size = Vector2(right_width-40,2)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reward.add_child(rule)
		symbol(reward,12,Vector2(20,256),Vector2(32,32),COIN)
		text(reward,"+%d" % (int(result.get("total",0))+int(result.get("zone_bonus",0))+int(result.get("coins",0))),Vector2(60,248),Vector2(240,48),36,INK,"display")
		var gems := int(result.get("diamonds",0))+int(result.get("zone_diamonds",0))
		if gems>0:
			symbol(reward,13,Vector2(right_width-118,258),Vector2(28,28),CRYSTAL)
			text(reward,"+%d" % gems,Vector2(right_width-84,252),Vector2(64,40),28,CRYSTAL,"display")
	var action_y := right_y+panel_height+22
	var main_text := "Повторить тренировку" if practice else "Начать заново" if not success else "Новое восхождение"
	action(self,main_text,Vector2(right_x,action_y),Vector2(right_width,64),func(): game.start_run(false if practice else game.run_mode=="endless"),"primary").add_theme_font_size_override("font_size",21)
	if not practice:
		var split := (right_width-10)*.6
		action(self,"Улучшить снаряжение",Vector2(right_x,action_y+76),Vector2(split,52),game.show_workshop)
		action(self,"В лагерь",Vector2(right_x+split+10,action_y+76),Vector2(right_width-split-10,52),game.show_menu)
		var note := "Открыты новые маршруты и бесконечный режим." if result.get("first",false) else "Награда сохранена. Следующая высота ждёт."
		paragraph(self,note,Vector2(28,stats_y+70) if landscape else Vector2(right_x,action_y+142),Vector2(column,40),14,MOSS if result.get("first",false) else INK_SOFT)
	else:
		action(self,"Вернуться в лагерь",Vector2(right_x,action_y+76),Vector2(right_width,52),game.show_menu)
