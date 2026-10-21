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

func build_pause() -> void:
	var practice: bool = game.run_mode=="practice"
	var column := 480.0 if landscape else 484.0
	heading("Пауза","Тренировка: кошелёк и снаряжение не меняются." if practice else "Попытка сохранена. Можно выйти в лагерь и вернуться позже.",column)
	var climbed := maxi(0,roundi((game.sim.highest-game.START_Y)*10))
	height_figure(self,climbed,Vector2(28,136),64)
	inline_stat(self,time_string(game.run_seconds),"в пути",Vector2(28+column-110,150),110)
	if not practice: route(self,Vector2(28,226),column,climbed)
	var bag_x := 556.0 if landscape else 28.0
	var bag_y := 136.0 if landscape else 296.0
	var bag_width := 496.0 if landscape else 484.0
	var rows: int = model.bag.size()
	var bag_height := 64.0+maxf(1,rows)*42+(10 if rows>0 else 16)
	var bag := slab(self,Vector2(bag_x,bag_y),Vector2(bag_width,bag_height))
	text(bag,"Рюкзак",Vector2(20,16),Vector2(120,26),18,INK,"display")
	text(bag,"%d из %d" % [rows,model.level(3)],Vector2(106,19),Vector2(120,22),14,INK_SOFT)
	var total := str(model.bag_value())
	var total_width: float = hud.heading_font.get_string_size(total,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
	coin_amount(bag,model.bag_value(),Vector2(bag_width-20-total_width-27,16),18)
	if model.bag.is_empty():
		paragraph(bag,"Пусто. Находки на уступах попадут сюда.",Vector2(20,62),Vector2(bag_width-40,24),14)
	else:
		for index in range(rows):
			var item: Dictionary = model.bag[index]
			var row_y := 58+index*42
			var slot := BagSlot.new()
			slot.item = item
			slot.rare = model.item_is_rare(item)
			slot.position = Vector2(20,row_y)
			slot.size = Vector2(36,36)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bag.add_child(slot)
			text(bag,GameModel.loot_name(item),Vector2(68,row_y+6),Vector2(bag_width-200,24),15,INK)
			if slot.rare: text(bag,"редкая",Vector2(bag_width-188,row_y+8),Vector2(70,20),12,COIN,"strong")
			var value := text(bag,str(int(item["value"])),Vector2(bag_width-112,row_y+5),Vector2(92,26),17,INK,"display")
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var actions_y := 300.0 if landscape else bag_y+bag_height+22
	action(self,"Продолжить восхождение",Vector2(28,actions_y),Vector2(column,64),game.unpause,"primary").add_theme_font_size_override("font_size",21)
	action(self,"Выйти из тренировки" if practice else "В лагерь",Vector2(28,actions_y+78),Vector2(column,52),game.show_menu)
	action(self,"Завершить тренировку" if practice else "Завершить и забрать награду",Vector2(28,actions_y+140),Vector2(column,48),func(): game.finish_run(false),"ghost")
	if landscape:
		var help := "Стик задаёт направление, отпускание — бросок или отцепление. Канат: держи строго вверх или вниз 0,28 секунды." if hud.touch_controls_hint else "A / D — раскачка, W / S — длина каната.\nПробел — отцепиться, ЛКМ — следующий бросок."
		paragraph(self,help,Vector2(bag_x,bag_y+bag_height+18),Vector2(bag_width,48),13)

func build_revive(reason: String) -> void:
	var available: bool = game.revive_available()
	var return_y: float = game.safe_contact.y-2.8 if game.safe_anchor_id>=0 else game.safe_position.y
	var return_height := maxi(0,roundi((return_y-game.START_Y)*10))
	var column := 480.0 if landscape else 484.0
	heading("Ещё один шанс",reason,column)
	var rescue := slab(self,Vector2(28,140),Vector2(column,200))
	if available:
		text(rescue,"Вернёшься к опоре на высоте",Vector2(20,16),Vector2(column-40,22),14,INK_SOFT)
		height_figure(rescue,return_height,Vector2(20,38),58)
		paragraph(rescue,"Высота попытки и рюкзак сохранятся. Продолжить можно один раз за попытку.",Vector2(20,124),Vector2(column-40,48),14)
	else:
		text(rescue,"Опоры рядом нет",Vector2(20,18),Vector2(column-40,40),28,INK,"display")
		paragraph(rescue,"На этом участке не осталось безопасной цепочки опор. Заверши попытку, чтобы забрать награду.",Vector2(20,66),Vector2(column-40,72),15)
	var x := 556.0 if landscape else 28.0
	var y := 140.0 if landscape else 366.0
	var width := 496.0 if landscape else 484.0
	var price := int(model.balance["diamond_revive_cost"])
	var owned := int(model.profile["diamonds"])
	var diamonds := action(self,"Продолжить за %d %s" % [price,plural(price,"алмаз","алмаза","алмазов")],Vector2(x,y),Vector2(width,64),func(): game.revive("diamonds"),"primary")
	diamonds.add_theme_font_size_override("font_size",20)
	diamonds.disabled = not available or owned<price
	var wallet_line := slab(self,Vector2(x,y+76),Vector2(width,40),Color(STONE,.0),Color.TRANSPARENT,0)
	symbol(wallet_line,13,Vector2(0,8),Vector2(20,20),CRYSTAL)
	text(wallet_line,"У тебя %d %s" % [owned,plural(owned,"алмаз","алмаза","алмазов")] if owned>=price else "Не хватает алмазов: есть %d из %d" % [owned,price],Vector2(28,8),Vector2(width-28,22),14,INK_SOFT if owned>=price else DANGER)
	if game.ads.supported:
		var ad_ready: bool = game.ads.rewarded_ready
		var ad := action(self,"Посмотреть рекламу и продолжить" if ad_ready else "Реклама пока недоступна",Vector2(x,y+126),Vector2(width,52),game.request_ad_revive)
		ad.disabled = not available or game.ads.fullscreen
		paragraph(self,"Продолжение после полного просмотра." if ad_ready else "Нажми ещё раз через несколько секунд.",Vector2(x,y+186),Vector2(width,22),13)
	elif OS.is_debug_build():
		var test_ad := action(self,"Тестовое продолжение",Vector2(x,y+126),Vector2(width,52),func(): game.revive("test_ad"))
		test_ad.disabled = not available
		paragraph(self,"Отладочная сборка: без рекламы.",Vector2(x,y+186),Vector2(width,22),13)
	else:
		var ad := action(self,"Реклама пока недоступна",Vector2(x,y+126),Vector2(width,52),func(): pass)
		ad.disabled = true
	action(self,"Завершить и забрать награду",Vector2(x,y+226),Vector2(width,48),func(): game.finish_run(false),"ghost")

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
	var panel_height := 236.0 if not practice else 150.0
	var reward := slab(self,Vector2(right_x,right_y),Vector2(right_width,panel_height))
	if practice:
		text(reward,"Попробуй ещё одну дугу",Vector2(20,18),Vector2(right_width-40,30),22,INK,"display")
		paragraph(reward,"Пройди увереннее, сохрани скорость или забери находку на боковом пути. Кошелёк и снаряжение не изменились.",Vector2(20,58),Vector2(right_width-40,72),15)
	else:
		text(reward,"Награда",Vector2(20,16),Vector2(200,26),18,INK,"display")
		var rows := [["За высоту",int(result.get("height",0))],["Находки из рюкзака",int(result.get("loot",0))],["Бонус вершины",int(result.get("finish",0))],["Новые зоны, уже на счету",int(result.get("zone_bonus",0))]]
		for index in range(rows.size()):
			var row_y := 50+index*26
			var muted: bool = int(rows[index][1])==0
			text(reward,rows[index][0],Vector2(20,row_y),Vector2(right_width-140,24),15,INK_FAINT if muted else INK_SOFT)
			text(reward,"+%d" % rows[index][1],Vector2(right_width-120,row_y),Vector2(100,24),16,INK_FAINT if muted else INK,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var rule := ColorRect.new()
		rule.color = STONE_LIP
		rule.position = Vector2(20,160)
		rule.size = Vector2(right_width-40,2)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reward.add_child(rule)
		symbol(reward,12,Vector2(20,176),Vector2(32,32),COIN)
		text(reward,"+%d" % (int(result.get("total",0))+int(result.get("zone_bonus",0))),Vector2(60,168),Vector2(240,48),36,INK,"display")
		var gems := int(result.get("diamonds",0))+int(result.get("zone_diamonds",0))
		if gems>0:
			symbol(reward,13,Vector2(right_width-118,178),Vector2(28,28),CRYSTAL)
			text(reward,"+%d" % gems,Vector2(right_width-84,172),Vector2(64,40),28,CRYSTAL,"display")
	var action_y := right_y+panel_height+22
	var main_text := "Повторить тренировку" if practice else "Ещё одна попытка"
	action(self,main_text,Vector2(right_x,action_y),Vector2(right_width,64),func(): game.start_run(false if practice else game.run_mode=="endless"),"primary").add_theme_font_size_override("font_size",21)
	if not practice:
		var split := (right_width-10)*.6
		action(self,"Улучшить снаряжение",Vector2(right_x,action_y+76),Vector2(split,52),game.show_workshop)
		action(self,"В лагерь",Vector2(right_x+split+10,action_y+76),Vector2(right_width-split-10,52),game.show_menu)
		var note := "Открыты новые маршруты и бесконечный режим." if result.get("first",false) else "Награда сохранена. Следующая высота ждёт."
		paragraph(self,note,Vector2(28,stats_y+70) if landscape else Vector2(right_x,action_y+142),Vector2(column,40),14,MOSS if result.get("first",false) else INK_SOFT)
	else:
		action(self,"Вернуться в лагерь",Vector2(right_x,action_y+76),Vector2(right_width,52),game.show_menu)
