class_name ExpeditionMenu
extends MenuSurface

static func plural(count: int, one: String, few: String, many: String) -> String:
	var tens := count%100
	var units := count%10
	if tens>=11 and tens<=14: return many
	if units==1: return one
	if units>=2 and units<=4: return few
	return many

func heading(value: String, subtitle: String, width: float, parent: Node = null) -> void:
	title(parent if parent!=null else self,value,Vector2(28,34),width,38)
	paragraph(parent if parent!=null else self,subtitle,Vector2(29,88),Vector2(width,44),15)

# Large height figure with its unit set smaller on the same baseline.
# It keeps its size at large text: it is already the largest thing on the
# screen, and scaled it ran into its unit and the route line under it.
func height_figure(parent: Node, meters: int, at: Vector2, font_size: int) -> void:
	var number := text(parent,str(meters),at,Vector2(400,font_size*1.2),font_size,INK,"display")
	number.add_theme_font_size_override("font_size",font_size)
	var shown: float = hud.heading_font.get_string_size(number.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var unit_size := int(font_size*.38)
	text(parent,"м",at+Vector2(shown+8,font_size*.72-unit_size*.6),Vector2(60,unit_size*1.3),unit_size,INK_SOFT,"display").add_theme_font_size_override("font_size",unit_size)

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

# Sizes the sheet to its content and docks it to the bottom safe edge: in the
# middle, or on the right beside a column (the result in landscape).
func close_sheet(sheet: Panel, content_height: float, right: bool = false) -> void:
	sheet.size = Vector2(sheet_width(),content_height+SHEET_PAD)
	var x := (size.x-sheet.size.x)*.5 if not right else size.x-sheet.size.x-maxf(16.0,(size.x-1080.0)*.5+24.0)
	sheet.position = Vector2(x,size.y-hud.safe_inset_bottom()-16-sheet.size.y)
	# The sheet comes up from the bottom edge it is docked to; it rises no
	# farther than the gap under it, so no part of it ever leaves the screen.
	reveal(sheet,0.0,14.0)

# Bag contents in one row of small cells with the total on the right.
func bag_strip(parent: Node, at: Vector2, width: float) -> float:
	var rows: int = model.bag.size()
	text(parent,"Рюкзак",at,Vector2(120,24),17,INK,"display")
	var after: float = hud.heading_font.get_string_size("Рюкзак",HORIZONTAL_ALIGNMENT_LEFT,-1,scaled(17)).x+10
	text(parent,"%d из %d" % [rows,model.bag_capacity()],at+Vector2(after,3),Vector2(90,20),13,INK_SOFT)
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
	# Room for the height tag that stands above the route line.
	y += 30 if practice else 44
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
	var restart := action(sheet,"Начать заново",Vector2(x,y),Vector2(half,52),func(): game.begin_run(game.restart_failed_run),"secondary" if available else "primary")
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

# The result: what the climb was on the backdrop above (heading, height,
# route, time), and below it the same stone sheet as the pause and the second
# chance, with the reward, one primary action and the way back. The wallet in
# the corner takes the reward: its coins fly in when the total has counted.
func build_result(result: Dictionary) -> void:
	var practice: bool = result.get("mode","")=="practice"
	var success: bool = result.get("success",false)
	var heading_text := "Вершина твоя" if success else "Следующий раз — выше"
	if practice: heading_text = "Маршрут освоен" if success else "Найди свою дугу"
	var subtitle := "Тот же маршрут, больше уверенности." if practice else "Каждый бросок привёл тебя сюда." if success else str(result.get("reason","Новая высота уже ждёт."))
	var gained := 0 if practice else int(result.get("total",0))+int(result.get("zone_bonus",0))+int(result.get("coins",0))
	var gems := 0 if practice else int(result.get("diamonds",0))+int(result.get("zone_diamonds",0))
	# --- The sheet.
	var sheet := open_sheet()
	var inner := sheet_width()-SHEET_PAD*2
	var x := SHEET_PAD
	var y := SHEET_PAD-4
	var total: Label
	var gem_label: Label
	if practice:
		text(sheet,"Попробуй ещё одну дугу",Vector2(x,y),Vector2(inner,30),22,INK,"display")
		y += 38
		var hint := paragraph(sheet,"Пройди увереннее, сохрани скорость или забери находку на боковом пути. Кошелёк и снаряжение не изменились.",Vector2(x,y),Vector2(inner,40),15)
		y += hint.size.y+16
	else:
		text(sheet,"Награда",Vector2(x,y),Vector2(200,26),18,INK,"display")
		y += 32
		var recovery := int(result.get("recovery",100))
		var loot_title := "Рюкзак продан" if success else "Рюкзак: сохранено %d%%" % recovery
		var rows := [["За высоту",int(result.get("height",0))],[loot_title,int(result.get("loot",0))],["Бонус вершины",int(result.get("finish",0))],
			["Контракт выполнен" if result.get("contract_done",false) else "Контракт",int(result.get("contract",0))],
			["Монеты, уже на счету",int(result.get("coins",0))],["Новые зоны, уже на счету",int(result.get("zone_bonus",0))]]
		# The lines arrive one after another and the total counts up to its
		# value; the buttons below work from the first frame.
		for index in range(rows.size()):
			var muted: bool = int(rows[index][1])==0
			var caption := text(sheet,rows[index][0],Vector2(x,y),Vector2(inner-110,22),14,INK_FAINT if muted else INK_SOFT)
			var amount := text(sheet,"+%d" % rows[index][1],Vector2(x+inner-100,y),Vector2(100,22),15,INK_FAINT if muted else INK,"display")
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			reveal(caption,.1+index*STAGGER,6)
			reveal(amount,.1+index*STAGGER,6)
			y += 23
		var progress := paragraph(sheet,progress_line(result),Vector2(x,y+2),Vector2(inner,20),12,INK_SOFT)
		progress.name = "Progress"
		y += progress.size.y+10
		rule(sheet,Vector2(x,y),inner)
		y += 10
		symbol(sheet,12,Vector2(x,y+8),Vector2(32,32),COIN).name = "TotalCoin"
		total = text(sheet,"",Vector2(x+40,y),Vector2(240,48),36,INK,"display")
		total.name = "Total"
		if gems>0:
			symbol(sheet,13,Vector2(x+inner-98,y+10),Vector2(28,28),CRYSTAL).name = "TotalGem"
			gem_label = text(sheet,"",Vector2(x+inner-64,y+4),Vector2(64,40),28,CRYSTAL,"display")
		y += 58
	var main_text := "Повторить тренировку" if practice else "Начать заново" if not success else "Новое восхождение"
	action(sheet,main_text,Vector2(x,y),Vector2(inner,64),func(): game.begin_run(func(): game.start_run(false if practice else game.run_mode=="endless")),"primary").add_theme_font_size_override("font_size",21)
	y += 76
	if not practice:
		var split := (inner-10)*.6
		action(sheet,"Улучшить снаряжение",Vector2(x,y),Vector2(split,52),game.show_workshop)
		action(sheet,"В лагерь",Vector2(x+split+10,y),Vector2(inner-split-10,52),game.show_menu)
		y += 52
		var note := "Открыты новые маршруты и бесконечный режим." if result.get("first",false) else "Награда сохранена. Следующая высота ждёт."
		var shown := paragraph(sheet,note,Vector2(x,y+10),Vector2(inner,20),14,MOSS if result.get("first",false) else INK_SOFT)
		shown.name = "Note"
		y += shown.size.y+10
	else:
		action(sheet,"Вернуться в лагерь",Vector2(x,y),Vector2(inner,52),game.show_menu)
		y += 52
	close_sheet(sheet,y,landscape)
	# --- The wallet, in the corner above everything.
	var top: float = hud.safe_inset_top()+12
	var wallet_at := Vector2(size.x-236-maxf(12.0,(size.x-(1080.0 if landscape else 540.0))*.5+20.0),top)
	wallet(wallet_at)
	# --- What the climb was, above the sheet (or beside it in landscape).
	var column := 480.0 if landscape else 484.0
	var head := Control.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.size = Vector2(column+56,0)
	add_child(head)
	heading(heading_text,subtitle,column,head)
	var highest := int(result.get("highest",0))
	height_figure(head,highest,Vector2(26,124),92)
	if not practice: route(head,Vector2(28,250),column,highest)
	var stats_y := 316.0 if not practice else 252.0
	inline_stat(head,time_string(float(result.get("seconds",0))),"в пути",Vector2(28,stats_y),180)
	inline_stat(head,"%d из %d" % [int(result.get("catches",0)),int(result.get("shots",0))],"бросков в цель",Vector2(28+column*.5,stats_y),column*.5)
	var head_height := stats_y+52
	head.size.y = head_height
	var left := (size.x-1080.0)*.5 if landscape else (size.x-540.0)*.5
	# Below the wallet, then centred in the room the sheet leaves (portrait),
	# or beside the sheet (landscape).
	var room_top: float = top+44+4
	var room_bottom: float = size.y-hud.safe_inset_bottom() if landscape else sheet.position.y-8
	head.position = Vector2(left,maxf(room_top-24,minf((room_top+room_bottom-head_height)*.5-24,room_bottom-head_height)))
	# --- Counting and the coins' flight.
	if practice: return
	var total_delay := .1+6*STAGGER
	count_up(total,gained,"+",total_delay)
	if gem_label!=null: count_up(gem_label,gems,"+",total_delay)
	if not lively() or (gained<=0 and gems<=0):
		return
	# The wallet shows what the player had before this reward and takes it
	# as the coins land.
	for key in WALLET_KEYS:
		var before := maxi(0,int(model.profile[key])-(gained if key=="gold" else gems))
		wallet_shown[key] = float(before)
		wallet_labels[key].text = str(before)
	var flight := get_tree().create_timer(total_delay+COUNT*.8)
	flight.timeout.connect(_fly_reward.bind(sheet.find_child("TotalCoin",true,false),sheet.find_child("TotalGem",true,false),gained,gems))

const FLIGHT := .5
const FLIGHT_COINS := 8

# Coins (and crystals) lift off the total and arc into the wallet; the
# wallet bumps as they land and counts up to the new sum.
func _fly_reward(coin_from: Control, gem_from: Control, gained: int, gems: int) -> void:
	if not is_inside_tree(): return
	var landed := 0
	var flights: Array = []
	if gained>0 and is_instance_valid(coin_from): flights.append(["gold",coin_from,12,COIN,mini(FLIGHT_COINS,maxi(3,gained/40))])
	if gems>0 and is_instance_valid(gem_from): flights.append(["diamonds",gem_from,13,CRYSTAL,mini(5,maxi(2,gems))])
	for entry in flights:
		var key: String = entry[0]
		var target: Label = wallet_labels[key]
		var start: Vector2 = (entry[1] as Control).get_global_rect().get_center()
		var end: Vector2 = target.get_parent().get_global_rect().position+Vector2(22,22)
		var count: int = entry[4]
		for index in range(count):
			var coin := UiSymbol.new()
			coin.kind = entry[2]
			coin.tint = entry[3]
			coin.size = Vector2(26,26)
			coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			coin.top_level = true
			add_child(coin)
			var from := start+Vector2(randf_range(-14,14),randf_range(-8,8))
			var lift := Vector2(randf_range(-60,60),-randf_range(90,160))
			coin.global_position = from-coin.size*.5
			coin.modulate.a = 0.0
			var tween := coin.create_tween()
			var delay := index*.05
			tween.tween_property(coin,"modulate:a",1.0,.08).set_delay(delay)
			tween.parallel().tween_method(func(t: float):
				# A quadratic arc that rises off the total, then drops into the wallet.
				var a := from.lerp(from+lift,t)
				var b := (from+lift).lerp(end,t)
				coin.global_position = a.lerp(b,t)-coin.size*.5
				coin.scale = Vector2.ONE*lerpf(1.0,.7,t),0.0,1.0,FLIGHT).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			var last: bool = index==count-1
			tween.tween_callback(func():
				coin.queue_free()
				hud.pulse(target.get_parent(),.06)
				if index==0: _count_wallet(key)
				if last: game._sfx("pickup"))

func _count_wallet(key: String) -> void:
	var node: Label = wallet_labels.get(key)
	if not is_instance_valid(node): return
	var from := float(wallet_shown.get(key,0.0))
	var target := float(int(model.profile[key]))
	wallet_shown[key] = target
	var tween := node.create_tween()
	wallet_tweens[key] = tween
	tween.tween_method(func(shown: float): node.text = str(roundi(shown)),from,target,FLIGHT+.1).set_trans(Tween.TRANS_SINE)
