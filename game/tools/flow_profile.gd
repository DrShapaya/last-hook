extends SceneTree

# Drives the real game through its screens in a window and reports every slow
# frame per step, with a screenshot of each screen:
#   Godot --path game --script res://tools/flow_profile.gd -- --out=<folder>
#   [--size=540x1170] [--text=100|115|130] [--shots] (screens only, no timing)
#   [--splash] (keep the launch splash) [--slow=25] (ms that count as slow)
#   [--preset=high] [--reduce] (reduce_effects on) [--ads] (a fake ad plugin
#   with a banner, so the layouts under a banner are seen)
# Vsync is off, so a frame's time is its real cost (script + draw).
# LASTHOOK_SAVE_DIR must point to a throwaway save folder.

class FakeAds extends RefCounted:
	signal initialized
	signal rewarded_loaded
	signal interstitial_loaded
	signal reward_earned
	signal rewarded_closed
	signal interstitial_closed
	signal ad_failed(kind: String, message: String)
	signal banner_slot_height_changed(slot: String, height: int)
	var banner := 110
	func initialize() -> void: initialized.emit()
	func loadRewarded(_id: String) -> void: rewarded_loaded.emit.call_deferred()
	func loadInterstitial(_id: String) -> void: interstitial_loaded.emit.call_deferred()
	func loadBannerSlot(slot: String, _id: String) -> void: banner_slot_height_changed.emit.call_deferred(slot,banner)
	func setBannerSlotVisible(_slot: String, _visible: bool) -> void: pass
	func showRewarded() -> void: pass
	func showInterstitial() -> void: pass
	func reportEvent(_event_name: String) -> void: pass

var out := "user://flow"
var window_size := Vector2i(540,1170)
var shots_only := false
var slow_ms := 25.0
var text_scale := 100
var preset := ""
var reduce := false
var fake_ads := false
var game
var label := "boot"
var last_usec := 0
var records := {} # label -> Array of frame ms
var parts := {} # label -> Array of [main ms, lobby ms]
var main_ms := 0.0
var lobby_ms := 0.0
var order: Array = []
var shot_index := 0
var fake := FakeAds.new()

func _initialize() -> void:
	call_deferred("run")

# The game's and the lobby's own _process are called from here and timed, so
# a slow frame says where it went: main, lobby, or the rest (draw, physics,
# other nodes).
func _tick() -> void:
	var now := Time.get_ticks_usec()
	if last_usec>0:
		if not records.has(label):
			records[label] = []
			parts[label] = []
			order.append(label)
		records[label].append((now-last_usec)/1000.0)
		parts[label].append([main_ms,lobby_ms])
	last_usec = now
	# The game turns vsync back on whenever graphics settings are applied.
	if DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main_ms = 0.0
	lobby_ms = 0.0
	if not is_instance_valid(game): return
	var delta := root.get_process_delta_time()
	if game.is_processing(): game.set_process(false)
	var t := Time.get_ticks_usec()
	game._process(delta)
	main_ms = (Time.get_ticks_usec()-t)/1000.0
	var view: LobbyView = game.hud.lobby_view if is_instance_valid(game.hud) else null
	if is_instance_valid(view):
		if view.is_processing(): view.set_process(false)
		t = Time.get_ticks_usec()
		view._process(delta)
		lobby_ms = (Time.get_ticks_usec()-t)/1000.0

func step(name: String) -> void:
	label = name

func frames(count: int) -> void:
	for i in range(count): await process_frame

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out.path_join("%02d-%s.png" % [shot_index,name])
	shot_index += 1
	root.get_texture().get_image().save_png(path)
	# Saving a PNG is slow and is not the game's cost.
	last_usec = 0

func lobby() -> LobbyView:
	return game.hud.lobby_view

func run() -> void:
	var keep_splash := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			window_size = Vector2i(int(parts[0]),int(parts[1]))
		if argument=="--shots": shots_only = true
		if argument=="--splash": keep_splash = true
		if argument=="--reduce": reduce = true
		if argument=="--ads": fake_ads = true
		if argument.begins_with("--slow="): slow_ms = float(argument.trim_prefix("--slow="))
		if argument.begins_with("--text="): text_scale = int(argument.trim_prefix("--text="))
		if argument.begins_with("--preset="): preset = argument.trim_prefix("--preset=")
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = window_size
	process_frame.connect(_tick)
	step("01 app start")
	var started := Time.get_ticks_usec()
	var packed := load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate()
	root.add_child(game)
	print("FLOW main scene load+ready %.1f ms, window %s, screen %s" % [(Time.get_ticks_usec()-started)/1000.0,str(root.size),str(DisplayServer.screen_get_size())])
	await frames(3)
	var profile: Dictionary = game.model.profile
	profile["locations"] = [0,1,2]
	profile["gold"] = 5000
	profile["diamonds"] = 30
	profile["learned_controls"] = ["aim"]
	if text_scale!=100: game.set_setting("text_scale",text_scale)
	if reduce: game.set_setting("reduce_effects",true)
	if not preset.is_empty(): game.set_graphics_preset(preset)
	if fake_ads:
		game.ads.attach_backend(fake,true)
		game.ads.set_main_menu(true)
	if keep_splash:
		await wait(1.0)
		await shot("splash")
		await wait(3.2)
	game.hud.show_menu()
	step("02 lobby idle")
	await wait(1.6)
	await shot("lobby")
	# Sections.
	for tab in ["equipment","expedition","settings"]:
		step("03 section -> "+tab)
		lobby().slide_to_tab(tab)
		await wait(.12)
		if tab=="equipment" and not shots_only: await shot("section-mid-slide")
		await wait(.7)
		await shot("section-"+tab)
		if tab=="equipment":
			step("03 equipment supplies")
			game.hud.equipment_view = "supplies"
			game.hud.show_menu()
			await wait(.5)
			await shot("equipment-supplies")
			game.hud.equipment_view = "upgrades"
			game.hud.show_menu()
			await wait(.3)
	for index in range(1,4):
		step("04 settings section %d" % index)
		if lobby().settings_page==null: break
		lobby().settings_page._open_section(index)
		await wait(.6)
		await shot("settings-%d" % index)
	if lobby().settings_page!=null: lobby().settings_page._open_section(0)
	await wait(.5)
	for index in range(4):
		step("05 preset %d" % index)
		if lobby().settings_page!=null: lobby().settings_page._pick_preset(index)
		await wait(.6)
	if lobby().settings_page!=null: lobby().settings_page._pick_preset(1)
	if not preset.is_empty(): game.set_graphics_preset(preset)
	await wait(.4)
	step("06 back to expedition")
	lobby().slide_to_tab("expedition")
	await wait(.8)
	for direction in [1,1,-1,-1]:
		step("07 location %+d" % direction)
		game.cycle_location(direction)
		await wait(.9)
		await shot("location-%d" % game.lobby_location)
	# Character screen.
	step("08 character open")
	lobby().open_character()
	await wait(1.2)
	await shot("character")
	var screen: CharacterScreen = lobby().character_screen
	step("08 character slot")
	screen.pick_slot("jacket")
	await wait(.8)
	step("08 character try-on")
	screen.pick_colour(str(HeroOutfit.COLOURS["jacket"][2][0]))
	await wait(.8)
	await shot("character-jacket")
	step("08 character buy")
	screen._buy_pressed()
	await wait(1.0)
	await shot("character-bought")
	step("08 character close")
	screen.close()
	await wait(.6)
	step("08 character reopen")
	lobby().open_character()
	await wait(.6)
	print("FLOW hero pixels after reopen: %d" % hero_pixels())
	lobby().character_screen.close()
	await wait(.4)
	# A run on every location.
	for location in [0,1,2]:
		game.selected_location = location
		game.lobby_location = location
		game.model.profile["selected_location"] = location
		game.hud.show_menu()
		step("09 lobby before run l%d" % location)
		await wait(3.0)
		step("10 start run l%d" % location)
		# As a tap on the start button: through the iris.
		game.hud.last_press = lobby().start_button.get_global_rect().get_center()
		game.press_lobby_action()
		await wait(.16)
		if location==0: await shot("iris-closing")
		await wait(game.hud.IrisClose.DURATION)
		if location==0: await shot("iris-opening")
		await wait(.5)
		if not shots_only and location==0: await shot("run-intro")
		await wait(1.6)
		await shot("run-l%d" % location)
		step("11 throw and swing l%d" % location)
		var grip: Dictionary = game.world.anchor_by_id(game.world.main_route[0])
		RouteBot.touch_throw(game,grip["pos"])
		await wait(2.0)
		step("12 pause l%d" % location)
		game.pause_run()
		await wait(.6)
		await shot("pause-l%d" % location)
		step("12 unpause l%d" % location)
		game.unpause()
		await wait(.6)
		step("13 fail l%d" % location)
		game.fail_run("Упал ниже экрана")
		await wait(.8)
		await shot("revive-l%d" % location)
		if location==0:
			step("13 revive")
			if game.state=="revive" and game.revive_available():
				game.revive("diamonds")
				await wait(1.2)
				game.fail_run("Упал ниже экрана")
				await wait(.5)
			step("14 restart from revive")
			game.begin_run(game.restart_failed_run)
			await wait(2.0)
			step("15 summit finish")
			game.finish_run(true)
			await wait(1.0)
			await shot("summit-scene")
			await wait(game.SUMMIT_SCENE_SECONDS+.8)
			await shot("result-summit")
			await wait(.9)
			await shot("result-summit-coins")
			await wait(1.0)
			await shot("result-summit-settled")
			step("16 result -> new run")
			game.start_run(false)
			await wait(2.0)
			game.fail_run("Упал ниже экрана")
			await wait(.4)
		step("17 take reward l%d" % location)
		game.finish_run(false)
		await wait(1.4)
		await shot("result-l%d" % location)
		step("18 result -> camp l%d" % location)
		game.show_menu()
		await wait(1.2)
	await shot("lobby-after-runs")
	step("19 character after runs")
	lobby().open_character()
	await wait(1.0)
	print("FLOW hero pixels after runs: %d" % hero_pixels())
	await shot("character-after-runs")
	lobby().character_screen.close()
	await wait(.4)
	step("20 exit dialog")
	game.go_back()
	await wait(.5)
	await shot("exit-dialog")
	game.go_back()
	await wait(.3)
	report()
	quit(0)

# Opaque pixels the character screen's own viewport drew (hero and ledge).
func hero_pixels() -> int:
	var screen: CharacterScreen = lobby().character_screen
	if not is_instance_valid(screen): return -1
	var image: Image = screen.viewport.get_texture().get_image()
	var count := 0
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			if image.get_pixel(x,y).a>.5: count += 1
	return count

func report() -> void:
	var lines: Array = []
	for name in order:
		var times: Array = records[name]
		var slow: Array = []
		var worst := 0.0
		for index in range(times.size()):
			worst = maxf(worst,times[index])
			if times[index]>=slow_ms: slow.append("#%d %.0f(m%.0f l%.0f)" % [index,times[index],parts[name][index][0],parts[name][index][1]])
		var sorted := times.duplicate()
		sorted.sort()
		lines.append("%-28s frames=%4d median=%5.1f worst=%6.1f slow(>=%d ms)=%d  %s" % [name,times.size(),sorted[sorted.size()/2],worst,int(slow_ms),slow.size()," ".join(slow.slice(0,14))])
	var text := "\n".join(lines)
	print(text)
	var file := FileAccess.open(out.path_join("report.txt"),FileAccess.WRITE)
	file.store_string(text+"\n")
