class_name ExpeditionMenu
extends MenuSurface

func heading(section: String, title: String, subtitle: String, kind: int = 7) -> void:
	eyebrow(self,"LAST HOOK / "+section,Vector2(30,30),800 if landscape else 480)
	emblem(self,kind,Vector2(28,92))
	text(self,title,Vector2(108,92),Vector2(920 if landscape else 404,44),30,PAPER,true)
	paragraph(self,subtitle,Vector2(109,145),Vector2(900 if landscape else 403,44),14)
	rule(self,Vector2(28,197),size.x-56)

func build_pause() -> void:
	heading("ПЕРЕДЫШКА","Выше — после паузы.","Тренировочный маршрут · базовое оснащение" if game.run_mode=="practice" else "Твой зацеп и прогресс сохранены.",18)
	var summary_width := 436.0 if landscape else 484.0
	stat(self,"%d м" % maxi(0,roundi((game.sim.highest-game.START_Y)*10)),"ВЫСОТА ПОПЫТКИ",Vector2(28,222),Vector2((summary_width-12)*.5,78),7)
	stat(self,time_string(game.run_seconds),"ВРЕМЯ В ПУТИ",Vector2(28+(summary_width+12)*.5,222),Vector2((summary_width-12)*.5,78),19)
	var bag_x := 492.0 if landscape else 28.0
	var bag_y := 222.0 if landscape else 320.0
	var bag_width := 560.0 if landscape else 484.0
	var bag_height := maxf(150,72+game.model.bag.size()*42)
	var bag := card(self,Vector2(bag_x,bag_y),Vector2(bag_width,bag_height))
	eyebrow(bag,"РЮКЗАК / %d ИЗ %d" % [game.model.bag.size(),model.level(3)],Vector2(22,19),bag_width-44,TEAL)
	text(bag,"%d золота в находках" % model.bag_value(),Vector2(22,43),Vector2(bag_width-44,23),15,PAPER,true)
	if model.bag.is_empty():
		paragraph(bag,"Пока пусто. На следующем уступе может ждать что-то ценное.",Vector2(22,86),Vector2(bag_width-44,48),14)
	else:
		for index in range(model.bag.size()):
			var item: Dictionary = model.bag[index]
			var tier := clampi(int(item.get("tier",0)),0,5)
			var row_y := 77+index*42
			var slot := BagSlot.new()
			slot.item = item
			slot.rare = model.item_is_rare(item)
			slot.position = Vector2(22,row_y)
			slot.size = Vector2(32,32)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bag.add_child(slot)
			text(bag,GameModel.LOOT_NAMES[tier]+(" · редкая" if slot.rare else ""),Vector2(67,row_y+5),Vector2(bag_width-187,25),13,PAPER)
			text(bag,str(int(item["value"])),Vector2(bag_width-112,row_y+5),Vector2(88,25),15,GOLD,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var actions_y := 328.0 if landscape else maxf(540,bag_y+bag_height+20)
	action(self,"Продолжить восхождение",Vector2(28,actions_y),Vector2(summary_width,56),game.unpause,"primary")
	action(self,"В лагерь · выйти из тренировки" if game.run_mode=="practice" else "В лагерь · сохранить попытку",Vector2(28,actions_y+68),Vector2(summary_width,50),game.show_menu)
	action(self,"Завершить тренировку" if game.run_mode=="practice" else "Завершить и забрать награду",Vector2(28,actions_y+130),Vector2(summary_width,50),func(): game.finish_run(false),"ghost")
	var help_y := bag_y+bag_height+20
	if landscape:
		paragraph(self,"A / D — раскачка    W / S — канат\nПробел — отпустить    ЛКМ — следующий бросок" if not hud.touch_controls_hint else "Стик — направление. Отпускание — бросок / отцепление.\nКанат: держи строго вверх / вниз 0,28 секунды.",Vector2(bag_x,help_y),Vector2(bag_width,48),13)
	else:
		text(self,"Основной кошелёк и оснащение сохраняются." if game.run_mode=="practice" else "Можно вернуться позже. Попытка останется сохранённой.",Vector2(28,892),Vector2(484,24),11,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func build_revive(reason: String) -> void:
	heading("ЕЩЁ ОДИН ШАНС","Не отпускай высоту.",reason,2)
	var available: bool = game.revive_available()
	var return_y: float = game.safe_contact.y-2.8 if game.safe_anchor_id>=0 else game.safe_position.y
	var return_height := maxi(0,roundi((return_y-game.START_Y)*10))
	var left_width := 484.0
	var rescue := card(self,Vector2(28,228),Vector2(left_width,254),Color("21372d"),Color("5c6545"))
	eyebrow(rescue,"ТОЧКА ВОЗВРАТА",Vector2(24,22),430,TEAL)
	text(rescue,"%d м" % return_height if available else "Нет выхода",Vector2(24,54),Vector2(430,70),52,PAPER,true)
	paragraph(rescue,"Вернись к безопасной опоре.\nДостигнутая высота и рюкзак сохранятся." if available else "На этом участке больше нет безопасной цепочки опор.",Vector2(25,139),Vector2(430,56),16)
	rule(rescue,Vector2(24,215),436)
	text(rescue,"ОДНО ПРОДОЛЖЕНИЕ ЗА ПОПЫТКУ",Vector2(25,227),Vector2(430,20),10,GOLD,true)
	var x := 548.0 if landscape else 28.0
	var y := 237.0 if landscape else 508.0
	var width := 504.0 if landscape else 484.0
	eyebrow(self,"ВЫБЕРИ, КАК ПРОДОЛЖИТЬ",Vector2(x,y),width)
	var price := int(model.balance["diamond_revive_cost"])
	var diamonds := action(self,"Продолжить · %d алмаза" % price,Vector2(x,y+36),Vector2(width,58),func(): game.revive("diamonds"),"primary")
	diamonds.disabled = not available or int(model.profile["diamonds"])<price
	text(self,"В кошельке: %d алмазов" % int(model.profile["diamonds"]),Vector2(x,y+105),Vector2(width,22),12,TEAL)
	if game.ads.supported:
		var ad_ready: bool = game.ads.rewarded_ready
		var ad := action(self,"Смотреть рекламу · возродиться" if ad_ready else "Реклама пока недоступна · повторить",Vector2(x,y+148),Vector2(width,50),game.request_ad_revive)
		ad.disabled = not available or game.ads.fullscreen
		text(self,"Возрождение после полного просмотра",Vector2(x,y+208),Vector2(width,22),11,MUTED)
	elif OS.is_debug_build():
		var test_ad := action(self,"Тестовое продолжение",Vector2(x,y+148),Vector2(width,50),func(): game.revive("test_ad"))
		test_ad.disabled = not available
		text(self,"Тестовый режим · без просмотра рекламы",Vector2(x,y+208),Vector2(width,22),11,MUTED)
	else:
		var ad := action(self,"Реклама пока недоступна",Vector2(x,y+148),Vector2(width,50),func(): pass)
		ad.disabled = true
	action(self,"Завершить и получить награду",Vector2(x,y+250),Vector2(width,50),func(): game.finish_run(false),"ghost")

func build_result(result: Dictionary) -> void:
	var practice: bool = result.get("mode","")=="practice"
	var success: bool = result.get("success",false)
	eyebrow(self,"LAST HOOK / "+("ТРЕНИРОВКА" if practice else "ИТОГИ ЭКСПЕДИЦИИ"),Vector2(30,30),900 if landscape else 484)
	emblem(self,16 if success else 7,Vector2(28,85),GOLD if success else TEAL)
	var title := "Вершина твоя." if success else "Следующий раз — выше."
	if practice: title = "Маршрут освоен." if success else "Найди свою дугу."
	text(self,title,Vector2(108,88),Vector2(920 if landscape else 404,45),30,PAPER,true)
	var subtitle := "Тот же маршрут. Больше уверенности." if practice else "Каждый бросок привёл тебя сюда." if success else str(result.get("reason","Новая высота уже ждёт."))
	paragraph(self,subtitle,Vector2(109,145),Vector2(900 if landscape else 403,44),14)
	var left_width := 470.0 if landscape else 484.0
	var height_card := card(self,Vector2(28,212),Vector2(left_width,196),Color("253b2e"),Color("647052"))
	eyebrow(height_card,"ПОКОРЁННАЯ ВЫСОТА",Vector2(24,21),left_width-48,TEAL)
	text(height_card,str(int(result.get("highest",0))),Vector2(20,48),Vector2(left_width-90,96),76,PAPER,true)
	text(height_card,"МЕТРОВ",Vector2(left_width-112,113),Vector2(90,26),12,GOLD,true)
	var percent := clampf(float(result.get("highest",0))/(game.summit_height*10),0,1)
	var track := card(height_card,Vector2(24,160),Vector2(left_width-48,5),Color("41533c"),Color.TRANSPARENT,2)
	if percent>0: card(track,Vector2.ZERO,Vector2((left_width-48)*percent,5),GOLD,Color.TRANSPARENT,2)
	stat(self,time_string(float(result.get("seconds",0))),"ВРЕМЯ В ПУТИ",Vector2(28,422),Vector2((left_width-12)*.5,73),19)
	stat(self,"%d / %d" % [int(result.get("catches",0)),int(result.get("shots",0))],"ЗАЦЕПОВ / БРОСКОВ",Vector2(28+(left_width+12)*.5,422),Vector2((left_width-12)*.5,73),2)
	var right_x := 526.0 if landscape else 28.0
	var right_y := 212.0 if landscape else 515.0
	var right_width := 526.0 if landscape else 484.0
	var reward := card(self,Vector2(right_x,right_y),Vector2(right_width,220))
	if practice:
		eyebrow(reward,"ВЫСОТА НАЧИНАЕТСЯ С НАВЫКА",Vector2(24,20),right_width-48,TEAL)
		text(reward,"Попробуй ещё одну дугу.",Vector2(24,55),Vector2(right_width-48,34),23,PAPER,true)
		paragraph(reward,"Пройди увереннее, сохрани скорость или забери находку на боковом пути.",Vector2(24,103),Vector2(right_width-48,58),16)
		text(reward,"Основной кошелёк и оснащение сохранены",Vector2(24,178),Vector2(right_width-48,25),12,TEAL)
	else:
		eyebrow(reward,"НАГРАДА ЗА ВОСХОЖДЕНИЕ",Vector2(24,18),right_width-48)
		var rows := [["За высоту",int(result.get("height",0))],["Из рюкзака · %d / %d" % [int(result.get("loot",0)),int(result.get("carried",0))],int(result.get("loot",0))],["Бонус вершины",int(result.get("finish",0))],["Новые зоны · уже начислено",int(result.get("zone_bonus",0))]]
		for index in range(rows.size()):
			var row_y := 45+index*24
			text(reward,rows[index][0],Vector2(24,row_y),Vector2(right_width-130,25),14,MUTED)
			text(reward,"+%d" % rows[index][1],Vector2(right_width-112,row_y),Vector2(88,25),15,PAPER,true).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rule(reward,Vector2(24,148),right_width-48)
		text(reward,"+%d" % (int(result.get("total",0))+int(result.get("zone_bonus",0))),Vector2(24,163),Vector2(280,40),30,GOLD,true)
		text(reward,"золота",Vector2(24,204),Vector2(280,16),10,MUTED)
		var gems := int(result.get("diamonds",0))+int(result.get("zone_diamonds",0))
		if gems>0:
			symbol(reward,13,Vector2(right_width-114,170),Vector2(28,28),TEAL)
			text(reward,"+%d" % gems,Vector2(right_width-78,172),Vector2(58,32),23,TEAL,true)
	var action_y := 454.0 if landscape else 760.0
	var main_text := "Повторить тренировку" if practice else "Ещё одна попытка"
	action(self,main_text,Vector2(right_x,action_y),Vector2(right_width,54),func(): game.start_run(false if practice else game.run_mode=="endless"),"primary")
	if not practice:
		action(self,"Улучшить снаряжение",Vector2(right_x,action_y+66),Vector2((right_width-12)*.60,46),game.show_workshop)
		action(self,"В лагерь",Vector2(right_x+(right_width-12)*.60+12,action_y+66),Vector2((right_width-12)*.40,46),game.show_menu)
		var note := "Открыты новые маршруты и бесконечный режим." if result.get("first",false) else "За новые зоны +%d золота · уже начислено" % int(result.get("zone_bonus",0)) if int(result.get("zone_bonus",0))>0 else "Награда сохранена. Следующая высота ждёт."
		paragraph(self,note,Vector2(28,520 if landscape else 898),Vector2(left_width,48),12,TEAL)
	else:
		action(self,"Вернуться в лагерь",Vector2(right_x,action_y+66),Vector2(right_width,46),game.show_menu)
