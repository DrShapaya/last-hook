class_name SettingsPage
extends RefCounted

# The settings section of the menu: a fixed head with four subsections and a
# scrolling list of rows under it. A row is {"height","build"}; build receives
# the column slab, the row's y and the slab's width. Controls change one
# setting in place; only a preset rewrites the whole list.
const SECTIONS := ["graphics","controls","accessibility","about"]
const SECTION_NAMES := ["Графика","Звук","Доступность","О нас"]
const PRESET_KEYS := ["ultra","high","balanced","battery","custom"]
const HEAD_HEIGHT := 176.0
const ROW := 58.0
const WIDE_ROW := 92.0
const COLUMN_GAP := 16.0
const ABOUT_PATH := "res://data/about.json"
const CHANGELOG_PATH := "res://data/changelog.json"

var lobby: LobbyView
var hud
var game
var model: GameModel

func _init(owner_view: LobbyView) -> void:
	lobby = owner_view
	hud = lobby.hud
	game = lobby.game
	model = lobby.model

func settings() -> Dictionary:
	return model.profile["settings"]

func build() -> void:
	lobby.title(lobby,"Настройки",Vector2(28,80),500,32)
	var section: String = hud.settings_section
	if section=="keys":
		_build_keys()
		return
	lobby.segmented(lobby,Vector2(28,126),lobby.size.x-56,SECTION_NAMES,SECTIONS.find(section),_open_section,40)
	match section:
		"controls": _place(_controls_rows())
		"accessibility": _place(_accessibility_rows())
		"about": _build_about()
		_: _place(_graphics_rows())

func _open_section(index: int) -> void:
	hud.settings_section = SECTIONS[index]
	hud.show_menu_soon(.2)

# Rows fill one slab in portrait and two in landscape, in reading order.
func _place(rows: Array) -> void:
	var columns := 2 if lobby.landscape else 1
	var width: float = (lobby.size.x-56-COLUMN_GAP*(columns-1))/columns
	var total := 0.0
	for row in rows: total += float(row["height"])
	var split := rows.size()
	if columns==2:
		var running := 0.0
		for index in range(rows.size()):
			running += float(rows[index]["height"])
			if running>=total*.5:
				split = index+1
				break
	var parts := [rows.slice(0,split),rows.slice(split)]
	var tallest := 0.0
	for part in parts:
		var height := 24.0
		for row in part: height += float(row["height"])
		tallest = maxf(tallest,height)
	var content := lobby.scroll_page(HEAD_HEIGHT,tallest+12)
	for column in range(columns):
		var slab := lobby.slab(content,Vector2(28+column*(width+COLUMN_GAP),0),Vector2(width,tallest))
		var y := 14.0
		for row in parts[column]:
			(row["build"] as Callable).call(slab,y,width)
			y += float(row["height"])

func _changed(key: String, value: Variant) -> void:
	game.set_setting(key,value)
	if not lobby.preset_buttons.is_empty() and is_instance_valid(lobby.preset_buttons[0]):
		lobby.pick_segment(lobby.preset_buttons,PRESET_KEYS.find(str(model.profile["graphics_quality"])))

# --- Row kinds ----------------------------------------------------------------------

func _hint_height(hint: String) -> float:
	return ROW+(6.0 if not hint.is_empty() else 0.0)

func choice(title_text: String, hint: String, key: String, labels: Array, values: Array) -> Dictionary:
	return {"height":_hint_height(hint),"build":func(slab: Control, y: float, width: float):
		var holder := lobby.settings_row(slab,y,width,title_text,hint)
		var buttons := lobby.segmented(holder,Vector2.ZERO,holder.size.x,labels,values.find(settings()[key]),func(index: int): _changed(key,values[index]),40)
		for button in buttons: button.add_theme_font_size_override("font_size",13)
		lobby.sync_buttons[key] = {"buttons":buttons,"values":values}}

# A long choice takes the whole width under its title.
func wide_choice(title_text: String, hint: String, labels: Array, selected: int, callback: Callable, capture: bool = false) -> Dictionary:
	return {"height":WIDE_ROW,"build":func(slab: Control, y: float, width: float):
		lobby.text(slab,title_text,Vector2(20,y),Vector2(width*.36,22),15,INK(),"strong")
		if not hint.is_empty(): lobby.text(slab,hint,Vector2(width*.36+24,y+2),Vector2(width*.64-44,20),12,MenuSurface.INK_SOFT)
		var buttons := lobby.segmented(slab,Vector2(20,y+28),width-40,labels,selected,callback,40)
		for button in buttons: button.add_theme_font_size_override("font_size",14)
		if capture: lobby.preset_buttons = buttons}

func level(title_text: String, hint: String, key: String, minimum: float, maximum: float, step: float, format: Callable) -> Dictionary:
	return {"height":_hint_height(hint),"build":func(slab: Control, y: float, width: float):
		var holder := lobby.settings_row(slab,y,width,title_text,hint)
		lobby.slider(holder,Vector2.ZERO,holder.size.x,float(settings()[key]),minimum,maximum,step,format,func(value: float): _level_changed(key,value))}

func _level_changed(key: String, value: float) -> void:
	game.set_setting(key,float(value) if key=="hold_seconds" else roundi(value))

func flag(title_text: String, hint: String, enabled: bool, callback: Callable) -> Dictionary:
	return {"height":_hint_height(hint),"build":func(slab: Control, y: float, width: float):
		lobby.settings_switch(slab,title_text,hint,Vector2(20,y),width-40,enabled,callback)}

func setting_flag(title_text: String, hint: String, key: String) -> Dictionary:
	return {"height":_hint_height(hint),"build":func(slab: Control, y: float, width: float):
		lobby.sync_switches[key] = lobby.settings_switch(slab,title_text,hint,Vector2(20,y),width-40,bool(settings()[key]),func(): _changed(key,not bool(settings()[key])))}

static func INK() -> Color:
	return MenuSurface.INK

static func percent(value: float) -> String:
	return "%d%%" % roundi(value)

static func seconds(value: float) -> String:
	return ("%.2f с" % value).replace(".",",")

# --- Графика ------------------------------------------------------------------------

func _graphics_rows() -> Array:
	lobby.preset_buttons = []
	lobby.sync_buttons = {}
	lobby.sync_switches = {}
	var fps_values := [30,60,120,0]
	return [
		wide_choice("Пресет","",["Ультра","Высокая","Баланс","Экономия","Своя"],PRESET_KEYS.find(str(model.profile["graphics_quality"])),_pick_preset,true),
		choice("Тени","",  "shadows",["Выкл","Сред.","Выс.","Ультра"],GameSettings.SHADOWS),
		choice("Свет","Объём и блики на камне","lighting",["Обычный","Ультра"],GameSettings.LIGHTING),
		choice("Дальность декора","","decor",["Низкая","Средняя","Высокая"],GameSettings.DETAIL),
		choice("Качество неба","","sky",["Низкое","Среднее","Высокое"],GameSettings.DETAIL),
		choice("Частицы","Блики находок и удар крюка","particles",["Выкл","Снижены","Полные"],GameSettings.PARTICLES),
		setting_flag("Свечение","Мягкий ореол света","glow"),
		choice("Масштаб рендера","Меньше: быстрее, но мягче","render_scale",["60%","75%","85%","100%"],GameSettings.RENDER_SCALES),
		wide_choice("Ограничение FPS","Лимит ниже частоты экрана может мерцать",["30","60","120","Без лимита"],fps_values.find(int(settings()["fps_limit"])),func(index: int): _changed("fps_limit",fps_values[index]))]

func _pick_preset(index: int) -> Variant:
	if index>=PRESET_KEYS.size()-1: return false
	game.set_graphics_preset(PRESET_KEYS[index])
	_sync_rows()
	return true

# A preset rewrites several rows: they move in place, so the page stays put
# instead of fading out and back.
func _sync_rows() -> void:
	for key in lobby.sync_buttons.keys():
		var row: Dictionary = lobby.sync_buttons[key]
		lobby.pick_segment(row["buttons"],row["values"].find(settings()[key]))
	for key in lobby.sync_switches.keys():
		lobby.show_switch(lobby.sync_switches[key],bool(settings()[key]))

# --- Звук и управление --------------------------------------------------------------

func _controls_rows() -> Array:
	var rows := [
		level("Общая громкость","","master_volume",0,100,5,percent),
		level("Музыка","","music_volume",0,100,5,percent),
		level("Звуковые эффекты","","sfx_volume",0,100,5,percent),
		flag("Вибрация","Отклик на зацепы, удары и падения",bool(model.profile.get("vibration",true)),hud.toggle_vibration)]
	if not hud.touch_controls_hint:
		rows.append({"height":ROW,"build":func(slab: Control, y: float, width: float):
			var holder := lobby.settings_row(slab,y,width,"Переназначение","")
			lobby.action(holder,"Клавиши",Vector2.ZERO,Vector2(holder.size.x,44),_open_keys,"buy")})
	rows.append_array([
		level("Чувствительность","Ход стика и шаг колеса","sensitivity",50,150,10,percent),
		level("Удержание для длины","Пауза перед сменой длины","hold_seconds",.15,.5,.01,seconds),
		_prices_row(),_zoom_row(),_help_row()])
	return rows

func _open_keys() -> void:
	hud.settings_section = "keys"
	hud.show_menu()

func _prices_row() -> Dictionary:
	var modes := ["near","always"]
	return {"height":ROW,"build":func(slab: Control, y: float, width: float):
		var holder := lobby.settings_row(slab,y,width,"Цены находок","")
		var buttons := lobby.segmented(holder,Vector2.ZERO,holder.size.x,["Рядом","Всегда"],modes.find(str(model.profile["loot_prices"])),func(index: int): hud.set_loot_prices(modes[index]),40)
		buttons[0].tooltip_text = "Цена видна у находок рядом и на линии прицела"}

# Camera scale: 100 % is the original framing. Larger values only narrow the
# picture; the fall edge and route rules stay the same.
func _zoom_row() -> Dictionary:
	var zooms := model.camera_zoom_levels()
	var names: Array = []
	for zoom in zooms: names.append("%d%%" % roundi(float(zoom)*100))
	return {"height":ROW,"build":func(slab: Control, y: float, width: float):
		var holder := lobby.settings_row(slab,y,width,"Масштаб камеры","")
		var buttons := lobby.segmented(holder,Vector2.ZERO,holder.size.x,names,zooms.find(model.camera_zoom()),func(index: int): game.set_camera_zoom(float(zooms[index])),40)
		for button in buttons:
			button.add_theme_font_size_override("font_size",13)
			button.tooltip_text = "Крупнее герой и опоры. Граница падения не меняется."}

func _help_row() -> Dictionary:
	var bindings: Dictionary = settings()["key_bindings"]
	var steps := [["Брось крюк","Коснись где удобно, потяни как стик и отпусти."],["Раскачайся","На канате веди палец влево или вправо."],["Выбери длину","Держи строго вверх или вниз, затем канат движется."],["Отцепись","Подними палец. Затем снова прицелься."]]
	if not hud.touch_controls_hint:
		steps = [["Брось крюк","Зажми ЛКМ, прицелься и отпусти."],
			["Раскачайся","%s / %s." % [KeyBindings.short_text(bindings,"swing_left"),KeyBindings.short_text(bindings,"swing_right")]],
			["Выбери длину","%s / %s или колесо мыши." % [KeyBindings.short_text(bindings,"rope_up"),KeyBindings.short_text(bindings,"rope_down")]],
			["Отцепись","%s, затем целься снова." % KeyBindings.short_text(bindings,"release")]]
	return {"height":40.0+steps.size()*56.0,"build":func(slab: Control, y: float, width: float):
		lobby.text(slab,"Как играть",Vector2(20,y+4),Vector2(300,24),17,INK(),"display")
		for index in range(steps.size()):
			var row_y: float = y+38+index*56
			var badge := lobby.slab(slab,Vector2(20,row_y+2),Vector2(32,32),MenuSurface.SLATE,MenuSurface.SLATE_LIP,3)
			lobby.text(badge,str(index+1),Vector2(0,2),Vector2(32,26),16,MenuSurface.STONE,"display").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lobby.text(slab,steps[index][0],Vector2(64,row_y),Vector2(width-84,20),15,INK(),"strong")
			lobby.paragraph(slab,steps[index][1],Vector2(64,row_y+20),Vector2(width-84,34),12)}

func _build_keys() -> void:
	var back := lobby.action(lobby,"Назад",Vector2(28,126),Vector2(130,40),_close_keys,"secondary")
	back.add_theme_font_size_override("font_size",15)
	var reset := lobby.action(lobby,"Сбросить",Vector2(lobby.size.x-28-150,126),Vector2(150,40),_reset_keys,"secondary")
	reset.add_theme_font_size_override("font_size",15)
	var rows: Array = []
	for action_name in KeyBindings.ACTIONS:
		rows.append(_key_row(action_name))
	_place(rows)

func _key_row(action_name: String) -> Dictionary:
	return {"height":ROW,"build":func(slab: Control, y: float, width: float):
		var holder := lobby.settings_row(slab,y,width,str(KeyBindings.NAMES[action_name]),"")
		var waiting: bool = lobby.rebinding_action==action_name
		var shown := "Нажми клавишу" if waiting else KeyBindings.key_text(settings()["key_bindings"],action_name)
		var button := lobby.action(holder,shown,Vector2.ZERO,Vector2(holder.size.x,44),lobby.begin_rebind.bind(action_name),"selected" if waiting else "buy")
		button.add_theme_font_size_override("font_size",14)}

func _close_keys() -> void:
	lobby.rebinding_action = ""
	hud.settings_section = "controls"
	hud.show_menu()

func _reset_keys() -> void:
	lobby.rebinding_action = ""
	game.set_setting("key_bindings",{})
	hud.show_menu()

# --- Доступность --------------------------------------------------------------------

func _accessibility_rows() -> Array:
	return [
		choice("Размер текста","","text_scale",["100%","115%","130%"],GameSettings.TEXT_SCALES),
		setting_flag("Высокий контраст","Темнее текст, контур в игре","high_contrast"),
		wide_choice("Цветовая схема","Редкость находок и акценты",["Обычная","Красно-зелёная","Сине-жёлтая"],GameSettings.COLOR_SCHEMES.find(settings()["color_scheme"]),func(index: int): game.set_setting("color_scheme",GameSettings.COLOR_SCHEMES[index])),
		setting_flag("Без вспышек","Убирает экранные эффекты","reduce_effects"),
		setting_flag("Подсказки управления","Показывать всегда","persistent_hints"),
		flag("Сообщения","Заметки внизу экрана",bool(model.profile.get("notifications",true)),hud.toggle_notifications)]

# --- О нас --------------------------------------------------------------------------

func _build_about() -> void:
	var rows: Array = [_identity_row()]
	rows.append_array(link_rows(read_json(ABOUT_PATH,{})))
	var history: Array = read_json(CHANGELOG_PATH,[])
	if not history.is_empty():
		rows.append({"height":44.0,"build":func(slab: Control, y: float, width: float):
			lobby.text(slab,"Список обновлений",Vector2(20,y+8),Vector2(width-40,26),17,INK(),"display")})
	for index in range(history.size()):
		rows.append(_version_row(history[index]))
	_place(rows)

static func read_json(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path): return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed)==typeof(fallback) else fallback

func _identity_row() -> Dictionary:
	return {"height":118.0,"build":func(slab: Control, y: float, width: float):
		var mark := TextureRect.new()
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.texture = preload("res://assets/icon.png")
		mark.position = Vector2(20,y+6)
		mark.size = Vector2(88,88)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.material = MenuSurface.chamfer_material(mark.size,12)
		slab.add_child(mark)
		lobby.text(slab,str(ProjectSettings.get_setting("application/config/name","Last Hook")),Vector2(124,y+6),Vector2(width-144,34),24,INK(),"display")
		lobby.text(slab,"Версия "+GameModel.build_version(),Vector2(124,y+38),Vector2(width-144,20),14,MenuSurface.INK_SOFT)
		var news := lobby.action(slab,"Что нового",Vector2(124,y+60),Vector2(width-144,40),show_news,"buy")
		news.add_theme_font_size_override("font_size",15)}

# One button per filled address; an empty one is simply not offered.
func link_rows(about: Dictionary) -> Array:
	var rows: Array = []
	var socials: Variant = about.get("socials",[])
	if socials is Array:
		for entry in socials:
			if entry is Dictionary and not str(entry.get("url","")).is_empty():
				rows.append(_link_row(str(entry.get("name","Ссылка")),str(entry["url"])))
	if not str(about.get("privacy_url","")).is_empty():
		rows.append(_link_row("Политика конфиденциальности",str(about["privacy_url"])))
	if not str(about.get("contact_email","")).is_empty():
		rows.append(_link_row("Написать разработчикам","mailto:%s?subject=%s" % [str(about["contact_email"]),("Last Hook "+GameModel.build_version()).uri_encode()]))
	return rows

func _link_row(label_text: String, address: String) -> Dictionary:
	return {"height":ROW,"build":func(slab: Control, y: float, width: float):
		var button := lobby.action(slab,label_text,Vector2(20,y),Vector2(width-40,46),OS.shell_open.bind(address),"secondary")
		button.add_theme_font_size_override("font_size",15)}

func _version_row(entry: Dictionary) -> Dictionary:
	var version := str(entry.get("version",""))
	var notes: Array = entry.get("notes",[])
	var open: bool = hud.about_version==version
	var column: float = (lobby.size.x-56-(COLUMN_GAP if lobby.landscape else 0.0))/(2 if lobby.landscape else 1)
	var note_height := 0.0
	for note in notes: note_height += _note_height(str(note),column-52)
	return {"height":ROW+(note_height+8 if open else 0.0),"build":func(slab: Control, y: float, width: float):
		var button := lobby.action(slab,"Версия "+version,Vector2(20,y),Vector2(width-40,46),_toggle_version.bind(version),"selected" if open else "secondary")
		button.add_theme_font_size_override("font_size",15)
		if not open: return
		var note_y: float = y+ROW
		for note in notes:
			lobby.paragraph(slab,"• "+str(note),Vector2(26,note_y),Vector2(width-52,18),13)
			note_y += _note_height(str(note),width-52)}

func _note_height(note: String, width: float) -> float:
	var font_size := roundi(13*hud.text_scale)
	var lines := ceili(hud.body_font.get_string_size("• "+note,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x/maxf(1.0,width)*1.12)
	return lines*(font_size*1.45)+6

func _toggle_version(version: String) -> void:
	hud.about_version = "" if hud.about_version==version else version
	hud.show_menu()

# The notes of the newest version over the page.
func show_news() -> void:
	var history: Array = read_json(CHANGELOG_PATH,[])
	if history.is_empty(): return
	var veil := ColorRect.new()
	veil.color = Color(MenuSurface.SLATE_LIP,.55)
	veil.size = lobby.size
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	lobby.page.add_child(veil)
	var width: float = minf(lobby.size.x-56,620.0)
	var notes: Array = history[0]["notes"]
	var body := 0.0
	for note in notes: body += _note_height(str(note),width-52)
	var height: float = minf(lobby.size.y-120,body+136)
	var card := lobby.slab(veil,Vector2((lobby.size.x-width)*.5,(lobby.size.y-height)*.5),Vector2(width,height))
	lobby.text(card,"Что нового в "+str(history[0]["version"]),Vector2(20,16),Vector2(width-40,30),20,INK(),"display")
	var y := 54.0
	for note in notes:
		if y+_note_height(str(note),width-52)>height-68: break
		lobby.paragraph(card,"• "+str(note),Vector2(26,y),Vector2(width-52,18),13)
		y += _note_height(str(note),width-52)
	lobby.action(card,"Закрыть",Vector2(20,height-60),Vector2(width-40,46),veil.queue_free,"primary")
