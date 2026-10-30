extends SceneTree

# Player settings: what a save may hold, presets, migration of the old sound
# switches, and the keyboard bindings.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("SETTINGS FAILED: "+description)

func load_fixture(directory: String, data: Dictionary) -> GameModel:
	var path := directory.path_join("settings-fixture.json")
	for stale in [path,path+".bak"]:
		if FileAccess.file_exists(stale): DirAccess.remove_absolute(stale)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return GameModel.new(path)

func test_sanitize() -> void:
	var dirty := {"master_volume":999,"sfx_volume":"громко","color_scheme":"neon","render_scale":.33,"key_bindings":5,"unknown":1}
	var clean := GameSettings.sanitize(dirty)
	check(clean["master_volume"]==100 and clean["sfx_volume"]==100,"bad volumes fall back")
	check(clean["color_scheme"]=="normal" and clean["render_scale"]==1.0,"bad choices fall back")
	check(clean["key_bindings"].is_empty() and not clean.has("unknown"),"unknown data is dropped")
	check(GameSettings.sanitize(null)==GameSettings.defaults(),"missing settings become defaults")
	var parsed := GameSettings.sanitize({"master_volume":45.0,"fps_limit":30.0,"text_scale":115.0,"hold_seconds":.4,"glow":false,"key_bindings":{"release":[32.0],"nope":[1]}})
	check(parsed["master_volume"]==45 and parsed["fps_limit"]==30 and parsed["text_scale"]==115,"JSON numbers stay valid")
	check(is_equal_approx(parsed["hold_seconds"],.4) and not parsed["glow"],"a saved hold and flag are kept")
	check(parsed["key_bindings"]=={"release":[32]},"bindings keep only known actions as whole numbers")
	check(GameSettings.defaults()["hold_seconds"]==ClimbGesture.VERTICAL_HOLD_SECONDS,"default hold matches the gesture")

func test_presets() -> void:
	var custom := GameSettings.defaults()
	check(GameSettings.detect_preset(custom)=="high","defaults are the high preset")
	GameSettings.apply_preset(custom,"battery")
	check(custom["shadows"]=="off" and custom["decor"]=="battery" and custom["sky"]=="battery" and custom["particles"]=="reduced" and not custom["glow"] and custom["render_scale"]==.75,"battery preset values")
	check(custom["fps_limit"]==0 and GameSettings.detect_preset(custom)=="battery","preset keeps the fps limit")
	custom["glow"] = true
	check(GameSettings.detect_preset(custom)=="custom","a manual change is custom")

func test_profile(directory: String) -> void:
	var fresh := GameModel.fresh_profile()
	check(fresh["graphics_quality"]=="high" and fresh["loot_prices"]=="always","new players get high quality and permanent prices")
	check(fresh["settings"]==GameSettings.defaults(),"a new profile has default settings")
	var moved := load_fixture(directory,{"version":6,"sound":false,"music":true,"graphics_quality":"balanced"})
	check(moved.profile["settings"]["sfx_volume"]==0 and moved.profile["settings"]["music_volume"]==100,"old sound switches become volumes")
	check(moved.profile["graphics_quality"]=="high","balanced becomes high once")
	var kept := load_fixture(directory,{"version":6,"graphics_quality":"battery"})
	check(kept.profile["graphics_quality"]=="battery","a chosen battery preset stays")
	var prices := load_fixture(directory,{"version":6,"loot_prices":"near"})
	check(prices.profile["loot_prices"]=="near","the loot price choice survives loading")
	var broken := load_fixture(directory,{"version":7,"settings":"сломано"})
	check(broken.profile["settings"]==GameSettings.defaults(),"broken settings in a save become defaults")

func test_bindings() -> void:
	var moved := KeyBindings.rebind({},"release",KEY_W)
	check(moved["release"]==[KEY_W],"rebinding replaces the action keys")
	check(KEY_W not in moved["rope_up"] and KEY_UP in moved["rope_up"],"a taken key leaves the other action")
	var empty := KeyBindings.rebind({"item_1":[KEY_Q]},"swing_left",KEY_Q)
	check(KeyBindings.key_text(empty,"item_1")=="Нет клавиши","an empty action says so")
	check(KeyBindings.rebind(empty,"release",KEY_ESCAPE)==empty,"Esc stays reserved")
	var held := KeyBindings.rebind({},"item_1",KEY_SPACE)
	check(held.is_empty(),"the only way to let go keeps its last key")
	KeyBindings.apply(empty)
	check(InputMap.action_get_events("item_1").is_empty() and InputMap.action_get_events("swing_left").size()==1,"an empty action has no events")
	KeyBindings.apply({})
	check(InputMap.action_get_events("swing_left").size()==2,"reset returns the default keys")

func test_gesture() -> void:
	var gesture := ClimbGesture.new()
	gesture.hold_seconds = .5
	gesture.begin(Vector2.ZERO,0,1)
	gesture.move(Vector2(0,-80),0,1)
	check(float(gesture.sample(.4)["reel"])==0.0 and float(gesture.sample(.51)["reel"])>0.0,"hold delay follows the setting")
	var calm := ClimbGesture.new()
	calm.begin(Vector2.ZERO,0,1)
	var quick := ClimbGesture.new()
	quick.sensitivity = 1.5
	quick.begin(Vector2.ZERO,0,1)
	check(float(quick.move(Vector2(40,0),0,1)["pump"])>float(calm.move(Vector2(40,0),0,1)["pump"])*1.4,"sensitivity shortens the stick")

func test_input(game) -> void:
	game.set_setting("hold_seconds",.5)
	game.set_setting("sensitivity",150)
	check(is_equal_approx(game.climb_gesture.hold_seconds,.5) and is_equal_approx(game.climb_gesture.sensitivity,1.5),"gesture settings reach the climb")
	game.set_setting("hold_seconds",.28)
	game.set_setting("sensitivity",100)
	game.set_setting("key_bindings",KeyBindings.rebind({"item_1":[KEY_Q]},"swing_left",KEY_Q))
	check(InputMap.action_get_events("item_1").is_empty() and game.model.profile["settings"]["key_bindings"].has("item_1"),"bindings apply and stay in the profile")
	game._physics_process(1.0/60.0)
	game.set_setting("key_bindings",{})
	check(InputMap.action_get_events("item_1").size()==1,"an empty binding set restores the keys")

func press(target: Control, point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = down
	target._gui_input(event)

func test_slider() -> void:
	var slider := MenuSurface.RopeSlider.new()
	slider.size = Vector2(300,44)
	slider.minimum = 0
	slider.maximum = 100
	slider.step = 5
	root.add_child(slider)
	var seen: Array = []
	var done: Array = []
	slider.changed.connect(func(value: float): seen.append(value))
	slider.committed.connect(func(value: float): done.append(value))
	press(slider,Vector2(slider.track_left()+slider.track_width()*.5,22),true)
	check(seen.is_empty(),"touching the slider changes nothing yet: it may be a scroll")
	press(slider,Vector2(slider.track_left()+slider.track_width()*.5,22),false)
	check(seen==[50.0] and done==[50.0],"a tap in the middle sets one value")
	done.clear()
	press(slider,Vector2(slider.track_left()+slider.track_width()*.5,22),true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(slider.track_left()+slider.track_width()*.5+4,60)
	slider._gui_input(motion)
	check(slider.value==50.0,"a drag that is not yet sideways changes nothing")
	motion.position = Vector2(900,22)
	slider._gui_input(motion)
	check(slider.value==100.0,"dragging past the end stops at the maximum")
	press(slider,Vector2(900,22),false)
	check(done==[100.0],"letting go commits once")
	motion.position = Vector2(0,22)
	slider._gui_input(motion)
	check(slider.value==100.0,"motion without a press changes nothing")
	check(slider.size.y>=44.0,"the slider is a comfortable touch target")
	slider.free()

func all_buttons(game) -> Dictionary:
	var found := {}
	for node in game.hud.content.find_children("*","Button",true,false):
		if node.is_visible_in_tree(): found[node.text] = node
	return found

func open_section(game, section: String) -> void:
	game.hud.settings_section = section
	game.hud.menu_tab = "settings"
	game.hud.show_menu()
	await process_frame
	await process_frame

func sliders(game) -> Array:
	return game.get_tree().get_nodes_in_group("menu_slider").filter(func(node): return node.is_visible_in_tree())

func touch(lobby, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 2
	event.position = point
	event.pressed = down
	lobby._input(event)

func drag(lobby, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 2
	event.position = point
	lobby._input(event)

func test_pages(game) -> void:
	game.state = "menu"
	await open_section(game,"graphics")
	all_buttons(game)["Доступность"].pressed.emit()
	await create_timer(.3).timeout
	check(game.hud.settings_section=="accessibility" and all_buttons(game).has("130%"),"a section tab opens its page")
	await open_section(game,"graphics")
	var names := all_buttons(game)
	for label in ["Графика","Звук","Доступность","О нас","Высокая","Баланс","Экономия","Своя"]:
		check(names.has(label),"the graphics page shows "+label)
	game.set_graphics_preset("high")
	await open_section(game,"graphics")
	var glow_off: Button = all_buttons(game)["Вкл"]
	glow_off.pressed.emit()
	check(game.model.profile["graphics_quality"]=="custom","a manual change moves the preset to custom")
	var preset_thumb: Panel = game.hud.lobby_view.preset_buttons[0].get_meta("thumb")
	check(int(preset_thumb.get_meta("index"))==3,"the preset switch shows Своя")
	game.set_graphics_preset("high")
	await open_section(game,"graphics")
	check(all_buttons(game).has("120") and all_buttons(game).has("Без лимита"),"the fps row offers 120")
	var settled: Control = game.hud.lobby_view.page
	all_buttons(game)["Экономия"].pressed.emit()
	await create_timer(.4).timeout
	check(game.hud.lobby_view.page==settled and settled.modulate.a==1.0,"a preset keeps the page on screen: nothing fades or is rebuilt")
	var shadow_thumb: Panel = game.hud.lobby_view.sync_buttons["shadows"]["buttons"][0].get_meta("thumb")
	check(int(shadow_thumb.get_meta("index"))==0,"the rows follow the preset in place")
	check(not bool(game.hud.lobby_view.sync_switches["glow"].get_meta("on")),"the glow switch follows the preset in place")
	game.hud.lobby_view.preset_buttons[0].pressed.emit()
	await create_timer(.4).timeout
	check(game.hud.lobby_view.page==settled and bool(game.hud.lobby_view.sync_switches["glow"].get_meta("on")),"switching back stays in place too")
	await open_section(game,"controls")
	check(sliders(game).size()==5,"three volumes, sensitivity and hold are sliders")
	check(all_buttons(game).has("Рядом") and all_buttons(game).has("120%"),"prices and camera live with the controls")
	check(all_buttons(game).has("Клавиши")!=bool(game.hud.touch_controls_hint),"keys exist only without touch")
	var lobby: LobbyView = game.hud.lobby_view
	var scroll: Control = lobby.scroll_content()
	check(scroll!=null and float(scroll.get_meta("range"))>0.0,"the long page scrolls")
	var volume: MenuSurface.RopeSlider = sliders(game)[0]
	var before: float = volume.value
	var start := Vector2(lobby.get_global_transform()*Vector2(60,400))
	touch(lobby,start,true)
	drag(lobby,start+Vector2(0,-120*game.hud.root.scale.y))
	touch(lobby,start+Vector2(0,-120*game.hud.root.scale.y),false)
	check(scroll.position.y<0.0 and volume.value==before and game.hud.menu_tab=="settings","a vertical drag only scrolls")
	lobby.scroll_to(0)
	var grab: Vector2 = volume.get_global_rect().get_center()
	touch(lobby,grab,true)
	drag(lobby,grab+Vector2(160*game.hud.root.scale.x,0))
	touch(lobby,grab+Vector2(160*game.hud.root.scale.x,0),false)
	check(game.hud.menu_tab=="settings" and not lobby.swipe_dragging,"a drag from a slider never swipes the menu")
	touch(lobby,grab,true)
	drag(lobby,grab+Vector2(0,-120*game.hud.root.scale.y))
	touch(lobby,grab+Vector2(0,-120*game.hud.root.scale.y),false)
	check(scroll.position.y<0.0 and volume.value==before,"a vertical drag starting on a slider scrolls the page")
	await open_section(game,"keys")
	check(all_buttons(game).has("Сбросить") and all_buttons(game).has("Назад"),"the keys page can reset and go back")
	lobby = game.hud.lobby_view
	lobby.begin_rebind("release")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.keycode = KEY_F
	key.pressed = true
	lobby._input(key)
	check(game.model.profile["settings"]["key_bindings"]["release"]==[KEY_F] and lobby.rebinding_action.is_empty(),"the next key is taken for the action")
	game.set_setting("key_bindings",{})
	lobby.begin_rebind("release")
	key.physical_keycode = KEY_ESCAPE
	key.keycode = KEY_ESCAPE
	lobby._input(key)
	check(game.model.profile["settings"]["key_bindings"].is_empty() and lobby.rebinding_action.is_empty(),"Esc cancels a rebind")
	await open_section(game,"graphics")

func luminance(color: Color) -> float:
	var channel := func(value: float) -> float: return value/12.92 if value<=.03928 else pow((value+.055)/1.055,2.4)
	return .2126*channel.call(color.r)+.7152*channel.call(color.g)+.0722*channel.call(color.b)

func contrast(a: Color, b: Color) -> float:
	var high := maxf(luminance(a),luminance(b))
	var low := minf(luminance(a),luminance(b))
	return (high+.05)/(low+.05)

func test_palette() -> void:
	var common := {"tier":0}
	var usual := ItemCatalog.visual_color(common)
	MenuSurface.apply_palette("red_green",false)
	check(ItemCatalog.visual_color(common)!=usual,"the scheme changes rarity colours")
	check(contrast(MenuSurface.DANGER,MenuSurface.STONE)>=3.0,"danger stays readable")
	MenuSurface.apply_palette("blue_yellow",false)
	check(contrast(MenuSurface.DANGER,MenuSurface.STONE)>=3.0,"danger stays readable in the second scheme")
	MenuSurface.apply_palette("normal",true)
	check(contrast(MenuSurface.INK_SOFT,MenuSurface.STONE)>=7.0,"high contrast darkens soft text")
	check(contrast(MenuSurface.INK_FAINT,MenuSurface.STONE)>=4.5,"high contrast keeps faint text legible")
	MenuSurface.apply_palette("normal",false)
	check(MenuSurface.INK_SOFT==Color("55636d") and ItemCatalog.visual_color(common)==usual,"the default palette returns")

func test_accessibility(game) -> void:
	await open_section(game,"accessibility")
	var cached: Control = game.hud.lobby_view.page_cache.get("equipment",null)
	game.set_setting("text_scale",130)
	await process_frame
	await process_frame
	check(is_equal_approx(game.hud.text_scale,1.3) and not is_instance_valid(cached),"text size rebuilds the kept pages")
	check(game.hud.label(game.hud.content,"x",20).get_theme_font_size("font_size")==26,"labels scale with the setting")
	game.set_setting("text_scale",100)
	game.set_setting("reduce_effects",true)
	check(game.hud.effects_reduced(),"the flash setting reaches the HUD")
	game.set_setting("reduce_effects",false)
	game.set_setting("color_scheme","red_green")
	await process_frame
	check(MenuSurface.MOSS!=Color("4a9a52"),"a scheme applies from the menu")
	game.set_setting("color_scheme","normal")
	await process_frame
	var learned: Array = game.model.profile["learned_controls"]
	game.model.profile["learned_controls"] = ["aim","swing","rope","release"]
	game.sim.attached = true
	check(game.hud.tutorial_hint().is_empty(),"learned controls hide the hints")
	game.set_setting("persistent_hints",true)
	check(not game.hud.tutorial_hint().is_empty(),"permanent hints stay")
	game.set_setting("persistent_hints",false)
	game.model.profile["learned_controls"] = learned

func test_about(game) -> void:
	await open_section(game,"about")
	var names := all_buttons(game)
	check(names.has("Что нового"),"the about page offers the news")
	var labels: Array = game.hud.content.find_children("*","Label",true,false).map(func(node): return node.text)
	check(("Версия "+GameModel.build_version()) in labels,"the about page shows the project version")
	var history: Array = SettingsPage.read_json(SettingsPage.CHANGELOG_PATH,[])
	check(not history.is_empty() and str(history[0]["version"])==GameModel.build_version() and not history[0]["notes"].is_empty(),"the changelog ships with the game, newest first")
	check(names.has("Версия "+str(history[1]["version"])),"older versions are listed")
	check(not names.has("Политика конфиденциальности") and not names.has("Написать разработчикам"),"links without an address stay hidden")
	check(SettingsPage.read_json("res://data/none.json",[])==[],"a missing file reads as the fallback")
	names["Что нового"].pressed.emit()
	await process_frame
	var opened: Array = game.hud.content.find_children("*","Label",true,false).map(func(node): return node.text)
	check(("• "+str(history[0]["notes"][0])) in opened and all_buttons(game).has("Закрыть"),"the news window shows the latest notes")
	all_buttons(game)["Закрыть"].pressed.emit()
	await process_frame
	await process_frame
	check(not all_buttons(game).has("Закрыть"),"the news window closes")
	var page := SettingsPage.new(game.hud.lobby_view)
	check(page.link_rows({"socials":[{"name":"VK","url":"https://vk.com/x"}],"privacy_url":"","contact_email":""}).size()==1,"one address gives one button")
	check(page.link_rows({"socials":[{"name":"Пусто","url":""}],"privacy_url":"https://a.b","contact_email":"a@b.c"}).size()==2,"an empty social link is skipped")
	await open_section(game,"graphics")

func test_resume(game, directory: String) -> void:
	game.model.profile = GameModel.fresh_profile()
	game.start_run(false)
	game.save_snapshot()
	var snapshot: Dictionary = game.model.profile["active"].duplicate(true)
	snapshot["length"] = 8.8
	snapshot["target_length"] = 8.8
	snapshot["attached"] = true
	game.model.profile["active"] = snapshot
	game.resume_run()
	check(game.sim.length<=game.model.rope_length() and game.sim.target_length<=game.model.rope_length(),"a run saved with a longer rope resumes inside the new limit")
	game.model.profile = GameModel.fresh_profile()
	game.model.set_level(GameModel.ROPE,4)
	game.start_run(false)
	game.save_snapshot()
	var long_rope: Dictionary = game.model.profile["active"].duplicate(true)
	long_rope["length"] = 7.0
	long_rope["target_length"] = 7.0
	game.model.profile["active"] = long_rope
	game.resume_run()
	check(is_equal_approx(game.sim.length,7.0),"a resumed run keeps a rope within its own limit")
	game.model.profile["active"] = {}
	game.state = "menu"
	var quality_key: Dictionary = game._run_world_key(0,false)
	game.set_setting("sky","battery")
	var sky_key: Dictionary = game._run_world_key(0,false)
	game.set_setting("sky","high")
	game.set_setting("color_scheme","red_green")
	var scheme_key: Dictionary = game._run_world_key(0,false)
	game.set_setting("color_scheme","normal")
	check(not quality_key.is_empty() and sky_key!=quality_key and scheme_key!=quality_key,"a prepared world is not reused after sky or colours change")

func loot_parts(game, particles: String) -> int:
	game.world.effects_quality = particles
	var holder := Node3D.new()
	game.world.add_child(holder)
	LootVisuals.build(game.world,{"item":ItemCatalog.valuable(-10,0,"root_wall",1),"rare":true},holder,"high",0.0)
	var parts := holder.get_child_count()
	holder.queue_free()
	return parts

func test_graphics(game) -> void:
	var fine := loot_parts(game,"full")
	check(loot_parts(game,"reduced")==fine-1 and loot_parts(game,"off")==fine-2,"particles are separate from decor")
	game.set_graphics_preset("high")
	game.set_setting("glow",false)
	check(not game.scene_environment.glow_enabled and game.model.profile["graphics_quality"]=="custom","a manual change applies and leaves the preset")
	game.set_setting("fps_limit",30)
	check(Engine.max_fps==30,"the fps limit applies")
	game.set_setting("fps_limit",120)
	check(Engine.max_fps==120 and game.model.profile["settings"]["fps_limit"]==120,"the 120 fps limit applies")
	check(GameSettings.sanitize({"fps_limit":120.0})["fps_limit"]==120,"a saved 120 fps limit stays")
	game.set_setting("fps_limit",0)
	check(Engine.max_fps==0,"no limit leaves the display pacing")
	game.set_setting("render_scale",.75)
	check(is_equal_approx(game.get_viewport().scaling_3d_scale,.75),"render scale reaches the viewport")
	game.set_setting("sky","battery")
	check(game.world._sky_detail()=="battery" and game.world.visual_quality=="high","sky quality is separate")
	game.set_setting("shadows","off")
	check(not game.sun_light.shadow_enabled,"shadows follow their own setting")
	game.set_graphics_preset("balanced")
	check(game.model.profile["graphics_quality"]=="balanced" and game.world.visual_quality=="balanced" and game.sun_light.shadow_enabled and game.scene_environment.glow_enabled,"a preset fills everything")
	check(is_equal_approx(game.get_viewport().scaling_3d_scale,1.0),"a preset restores render scale")
	game.set_graphics_preset("high")

func test_audio(game) -> void:
	check(game.sounds.players[0].bus=="SFX" and game.sounds.wind.bus=="SFX" and game.music.players[0].bus=="Music","players use their buses")
	var music_bus := AudioServer.get_bus_index("Music")
	game.set_setting("music_volume",0)
	check(AudioServer.is_bus_mute(music_bus) and not game.music.enabled,"silent music stops")
	game.set_setting("music_volume",50)
	check(game.music.enabled and not AudioServer.is_bus_mute(music_bus) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus),linear_to_db(.5)),"music returns at half volume")
	game.set_setting("master_volume",0)
	check(AudioServer.is_bus_mute(0),"master silence mutes everything")
	game.set_setting("master_volume",100)
	check(not AudioServer.is_bus_mute(0) and is_zero_approx(AudioServer.get_bus_volume_db(0)),"full master volume is unity")
	game.set_setting("sfx_volume",0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),"silent effects mute their bus")
	game.set_setting("sfx_volume",100)
	game.set_setting("music_volume",100)

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		push_error("Tests require LASTHOOK_SAVE_DIR to keep saves isolated")
		quit(2)
		return
	test_sanitize()
	test_presets()
	test_profile(directory)
	test_bindings()
	test_gesture()
	test_slider()
	test_palette()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	test_graphics(game)
	test_audio(game)
	test_input(game)
	await test_pages(game)
	await test_accessibility(game)
	await test_about(game)
	test_resume(game,directory)
	game.queue_free()
	await process_frame
	print("SETTINGS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
