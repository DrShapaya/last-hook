extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("MENUS FAILED: "+description)

func controls_inside(node: Node, area: Rect2) -> bool:
	for child in node.get_children():
		if child is Control and not area.encloses(child.get_global_rect()):
			push_warning("OUTSIDE: %s / %s / %s" % [child.get_class(),child.get("text"),child.get_global_rect()])
			return false
		if not controls_inside(child,area): return false
	return true

func buttons_do_not_overlap(node: Node) -> bool:
	var buttons: Array[Button] = []
	for child in node.find_children("*","Button",true,false): buttons.append(child)
	for i in range(buttons.size()):
		for j in range(i+1,buttons.size()):
			if buttons[i].get_global_rect().grow(-1).intersects(buttons[j].get_global_rect().grow(-1)):
				return false
	return true

func find_button(node: Node, prefix: String) -> Button:
	for child in node.find_children("*","Button",true,false):
		if child.text.begins_with(prefix): return child
	return null

func touch_event(point: Vector2, down: bool, index: int = 4) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	root.push_input(event,true)

func touch_tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	touch_event(point,true)
	await process_frame
	touch_event(point,false)
	await process_frame

func validate_screen(game, area: Rect2, description: String) -> void:
	var screen = game.hud.content.get_child(0)
	check(controls_inside(screen,area),description+" keeps every control on screen")
	check(buttons_do_not_overlap(screen),description+" keeps actions separate")

func validate_navigation(game, dimensions: Vector2i) -> void:
	var lobby := game.hud.content.get_child(0) as LobbyView
	var nav := lobby.navigation_bar
	var viewport := Rect2(Vector2.ZERO,game.get_viewport().get_visible_rect().size).grow(1)
	check(nav!=null and nav.get_global_rect().end.y>=viewport.size.y*.72 and nav.get_global_rect().end.y<=viewport.end.y,
		"section navigation stays anchored to the lower safe area at %s" % dimensions)
	check(nav!=null and nav.get_global_rect().size.x>=480,
		"section navigation keeps its full-width hit area at %s" % dimensions)
	if nav!=null:
		for tab in lobby.tab_buttons:
			check(nav.get_global_rect().encloses(tab.get_global_rect()),
				"section button stays inside navigation bar at %s" % dimensions)

func run_tests() -> void:
	var directory := OS.get_environment("LASTHOOK_SAVE_DIR")
	if directory.is_empty():
		quit(2)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.preview = true
	game.set_physics_process(false)
	game.model.profile = GameModel.fresh_profile()
	for dimensions in [Vector2i(432,960),Vector2i(540,960),Vector2i(800,800),Vector2i(1280,800),Vector2i(1600,720)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var area := Rect2(Vector2.ZERO,game.get_viewport().get_visible_rect().size).grow(1)
		game.state = "menu"
		game.model.profile["active"] = {}
		game.hud.select_menu("expedition")
		await process_frame
		await touch_tap(find_button(game.hud.content,"Настройки"))
		check(game.hud.menu_tab=="settings","native touch opens settings without mouse emulation at %s" % dimensions)
		for tab in ["expedition","equipment","settings"]:
			game.hud.select_menu(tab)
			await process_frame
			validate_screen(game,area,"%s at %s" % [tab,dimensions])
			validate_navigation(game,dimensions)
			if tab=="settings":
				game.hud.touch_controls_hint = true
				game.hud.show_menu()
				await process_frame
				validate_screen(game,area,"four touch instructions at %s" % dimensions)
				var has_delay := false
				for label in game.hud.content.find_children("*","Label",true,false):
					if "0,28" in label.text: has_delay = true
				check(has_delay,"touch settings expose the vertical hold delay at %s" % dimensions)
				game.hud.touch_controls_hint = false
		game.hud.select_menu("expedition")
		await process_frame
		var route_tag_found := false
		for label in game.hud.content.find_children("*","Label",true,false):
			if label.text=="3 акта · ручной маршрут":
				route_tag_found = true
		check(not route_tag_found,"level cards omit the obsolete manual-route subtitle at %s" % dimensions)
		var lobby := game.hud.content.get_child(0) as LobbyView
		var card_before := lobby.scenic_frame.position
		var nav_before := lobby.navigation_bar.position
		var body_fixed := lobby.body_nodes.filter(func(node): return is_instance_valid(node) and node!=lobby.scenic_frame).map(func(node): return node.position)
		lobby.begin_swipe_preview()
		lobby.update_swipe_preview(-30)
		check(lobby.scenic_frame.position.x==card_before.x-30 and lobby.navigation_bar.position==nav_before,
			"level swipe previews only the scenic card at %s" % dimensions)
		check(lobby.body_nodes.filter(func(node): return is_instance_valid(node) and node!=lobby.scenic_frame).map(func(node): return node.position)==body_fixed,
			"level swipe keeps title, route and actions fixed at %s" % dimensions)
		lobby.reset_swipe_preview()
		game.start_run(false)
		game.model.set_level(GameModel.BAG,5)
		game.model.bag.clear()
		for tier in range(6):
			game.model.bag.append({"id":tier,"tier":tier,"value":int(game.model.balance["loot_values"][tier])*2})
		game.state = "pause"
		game.hud.show_pause()
		validate_screen(game,area,"full backpack at %s" % dimensions)
		game.state = "revive"
		game.hud.show_revive("Не хватило длины каната")
		validate_screen(game,area,"rescue at %s" % dimensions)
		check(find_button(game.hud.content,"Начать заново")!=null,"failure screen exposes a direct restart action at %s" % dimensions)
		game.state = "result"
		for success in [false,true]:
			game.hud.show_result({"success":success,"first":success,"highest":1200,"height":540,"loot":900,"carried":900,"finish":1300,"diamonds":20,"total":2740,"zone_bonus":1800,"seconds":214,"shots":51,"catches":43})
			validate_screen(game,area,"result %s at %s" % [success,dimensions])
		game.hud.show_result({"mode":"practice","success":false,"highest":124,"seconds":38,"shots":9,"catches":5})
		validate_screen(game,area,"practice at %s" % dimensions)
		# Resize callbacks must preserve the current modal, rather than showing
		# the lobby or leaving the old portrait controls in landscape.
		game.hud._resize()
		check(game.hud.layout_mode=="result" and game.hud.content.get_child_count()==1,"resize retains one current result screen")
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["gold"] = 2000
	game.state = "menu"
	game.hud.select_menu("equipment")
	var purchase := find_button(game.hud.content,"Улучшить")
	check(purchase!=null and not purchase.disabled,"available upgrades expose a purchase action")
	var gold_before := int(game.model.profile["gold"])
	purchase.pressed.emit()
	check(int(game.model.profile["gold"])<gold_before and game.hud.menu_tab=="equipment","purchase updates equipment and wallet without leaving the workshop")
	game.start_run(false)
	var snapshot: Dictionary = game.model.profile["active"].duplicate(true)
	game.hud.select_menu("equipment")
	var all_disabled := true
	for node in game.hud.content.find_children("*","Button",true,false):
		if node.text=="После попытки": all_disabled = all_disabled and node.disabled
	check(all_disabled and game.model.profile["active"]==snapshot,"menu navigation cannot spend gold or discard a saved climb")
	game.hud.select_menu("settings")
	var was_enabled: bool = game.model.profile["sound"]
	await touch_tap(find_button(game.hud.content,"Вкл" if was_enabled else "Выкл"))
	# Settings writes are coalesced for a short debounce window.
	await create_timer(.25).timeout
	var reloaded := GameModel.new(game.model.save_path)
	check(game.model.profile["sound"]!=was_enabled and reloaded.profile["sound"]==game.model.profile["sound"],"sound setting persists across reload")
	game.hud.select_menu("settings")
	await touch_tap(find_button(game.hud.content,"Высокая"))
	check(game.model.profile["graphics_quality"]=="high" and game.sun_light.shadow_enabled,"high graphics preset applies shadows and persists")
	await touch_tap(find_button(game.hud.content,"Экономия"))
	check(game.model.profile["graphics_quality"]=="battery" and Engine.max_fps==0 and not game.sun_light.shadow_enabled,"battery graphics preset keeps the display refresh target and disables shadows")
	var vibration_before: bool = game.model.profile["vibration"]
	game.hud.toggle_vibration()
	check(game.model.profile["vibration"]!=vibration_before,"vibration setting toggles")
	var notifications_before: bool = game.model.profile["notifications"]
	game.hud.toggle_notifications()
	check(game.model.profile["notifications"]!=notifications_before,"notifications setting toggles")
	game.model.profile["active"] = {}
	game.run_id = ""
	game.state = "menu"
	game.hud.select_menu("expedition")
	var settings := find_button(game.hud.content,"Настройки")
	var start := settings.get_global_rect().get_center()
	touch_event(start,true)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 4
	drag.position = start+Vector2(0,-120)
	root.push_input(drag,true)
	await process_frame
	touch_event(drag.position,false)
	await process_frame
	check(game.hud.menu_tab=="expedition","dragging outside cancels a menu tap")
	touch_event(start,true)
	touch_event(start,false,7)
	check(game.hud.menu_tab=="expedition","lifting an extra finger cannot activate the owned button")
	root.push_input(drag,true)
	await process_frame
	touch_event(start+Vector2(0,-100),false)
	await process_frame
	check(game.hud.menu_tab=="expedition","lifting outside a menu button safely cancels its touch")
	var cached_menu_world = game.world
	game.lobby_location = 0
	game.cycle_location(1)
	await process_frame
	var route_preview: LevelPreview = null
	for node in game.hud.content.find_children("*","Control",true,false):
		if node is LevelPreview:
			route_preview = node
			break
	check(game.world==cached_menu_world and route_preview!=null and route_preview.route_location==1,
		"switching a menu route reuses the cached world and only updates the lightweight preview")
	game.lobby_location = 0
	game.hud.show_menu()
	await process_frame
	var preview_before_finish: bool = game.preview
	game.preview = false
	game.start_run(false)
	game.show_menu()
	await process_frame
	var finish_run_button := find_button(game.hud.content,"Завершить забег")
	check(finish_run_button!=null,"an unfinished run exposes a finish button in the expedition menu")
	check(find_button(game.hud.content,"Продолжить восхождение")!=null,"an unfinished run keeps the resume action beside the finish button")
	if finish_run_button!=null:
		finish_run_button.pressed.emit()
		await process_frame
	check(game.state=="result" and game.model.profile["active"].is_empty() and not bool(game.settlement.get("success",true)),
		"finishing an unfinished run settles it once and clears the active snapshot")
	game.preview = preview_before_finish
	game.show_menu()
	await process_frame
	check(find_button(game.hud.content,"Завершить забег")==null,"a completed run no longer shows the finish button")
	var training := find_button(game.hud.content,"Тренировка")
	await touch_tap(training)
	check(game.run_mode=="practice" and game.state=="play","home training shortcut still opens an isolated practice run")
	game.queue_free()
	await process_frame
	var report := FileAccess.open(directory.path_join("menus-test-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	print("MENUS_TESTS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
