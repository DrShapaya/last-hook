extends SceneTree

# Regressions of the interface polish and stutter pass (2026-11): notes that
# outlive their screen, the character screen's stage, shared shaders and
# style boxes, the prepared world's first draw in parts, motion timings.

var checks := 0
var failures: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("UI FLOW FAILED: "+description)

func frames(count: int) -> void:
	for i in range(count): await process_frame

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func lobby() -> LobbyView:
	return game.hud.lobby_view

func fresh_game() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames(2)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await frames(2)
	game.model.profile = GameModel.fresh_profile()
	game.model.profile["locations"] = [0,1,2]
	game.show_menu()
	await frames(2)

func hint_tests() -> void:
	await fresh_game()
	game.start_run(false)
	await frames(2)
	check(game.hint_context=="controls" and game.hint_timer>0,"a first run opens with the controls hint")
	game.pause_run()
	await frames(3)
	check(game.hint_timer>0,"the hint's clock stands still on the pause screen")
	game.show_menu()
	await frames(3)
	check(game.hint_timer<=0.0,"leaving a run for the camp drops the run's hint (timer %.2f)" % game.hint_timer)
	check(not game.hud.toast_chip.visible,"no run hint is shown over the camp")
	lobby().open_character()
	await frames(3)
	check(not game.hud.toast_chip.visible,"no run hint is shown over the character screen")
	lobby().character_screen.close()
	await frames(2)
	# A note raised for the camp itself stays.
	game.toast("Маршрут открыт",3.0,"menu")
	game.show_menu()
	await frames(2)
	check(game.hint_timer>0 and game.hud.toast_chip.visible,"a note meant for the camp survives opening the camp")
	game.hint_timer = 0
	# From the result screen too.
	game.model.profile["active"] = {}
	game.start_run(false)
	await frames(2)
	game.toast("Отпусти, чтобы бросить",4.0,"release")
	game.finish_run(false)
	await frames(2)
	game.show_menu()
	await frames(2)
	check(game.hint_timer<=0.0,"a throw hint does not follow the player from the result screen to the camp")

func character_stage_tests() -> void:
	# The stage's render target is bounded, whatever the screen.
	var phone := CharacterScreen.stage_pixels(Vector2(500,707),2.0)
	check(phone.x*phone.y<=CharacterScreen.MAX_STAGE_PIXELS*1.01 and phone.x>=500,"a 1080 px phone renders the stage within the pixel limit (%s)" % str(phone))
	var dense := CharacterScreen.stage_pixels(Vector2(500,707),2.67)
	check(dense.x*dense.y<=CharacterScreen.MAX_STAGE_PIXELS*1.01,"a 1440 px phone stays within the pixel limit (%s)" % str(dense))
	check(absf(float(dense.x)/dense.y-500.0/707.0)<.01,"the bounded stage keeps its proportions")
	check(CharacterScreen.stage_pixels(Vector2(500,707),.4)==Vector2i(500,707),"a small window never renders below the canvas size")
	check(CharacterScreen.stage_pixels(Vector2(500,707),NAN)==Vector2i(500,707),"a broken screen scale falls back to the canvas size")
	check(CharacterScreen.stage_msaa(true,true)==Viewport.MSAA_2X and CharacterScreen.stage_msaa(true,false)==Viewport.MSAA_4X and CharacterScreen.stage_msaa(false,true)==Viewport.MSAA_DISABLED,
		"phones smooth the stage with two samples, the battery preset with none")
	# What counts as an empty stage.
	var blank := Image.create(64,96,false,Image.FORMAT_RGBA8)
	check(CharacterScreen.stage_empty(blank) and CharacterScreen.stage_empty(null),"a transparent picture is an empty stage")
	blank.fill_rect(Rect2i(24,30,16,40),Color(.8,.6,.2,1))
	check(not CharacterScreen.stage_empty(blank),"a picture with the hero in the middle is not empty")
	await fresh_game()
	lobby().open_character()
	await frames(3)
	var first: CharacterScreen = lobby().character_screen
	check(is_instance_valid(first.hero) and first.check_in>0,"the stage is built and will look at its picture")
	# Reopened while the old screen fades: the old stage gives its target back.
	first.close()
	check(first.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"a closing screen stops drawing its stage")
	lobby().open_character()
	var second: CharacterScreen = lobby().character_screen
	check(second!=first and not second.closing,"a tap during the closing fade opens a fresh screen")
	check(first.viewport==null and first.hero==null,"the closing screen releases its stage when a new one opens")
	await frames(3)
	check(not is_instance_valid(first),"the old screen is gone")
	# A lost picture is rebuilt, the plain way the second time, and reported.
	second.yaw = .4
	second.pick_slot("jacket")
	second.pick_colour("jacket_glacier")
	second.stage_lost()
	check(second.rebuilds==1 and is_instance_valid(second.hero) and not second.plain_scene,"an empty stage is built again once as it was")
	check(is_equal_approx(second.yaw,.4) and second.slot=="jacket","the rebuilt stage keeps the turn and the open slot")
	var window: PackedFloat32Array = second.hero.shader_material.get_shader_parameter("slot_window")
	check(window[HeroOutfit.CODES["jacket"]]>0.0,"the rebuilt hero still wears what was tried on")
	second.stage_lost()
	check(second.rebuilds==2 and second.plain_scene and second.viewport.msaa_3d==Viewport.MSAA_DISABLED,"a second loss builds the plain stage")
	var before := second.hero
	second.stage_lost()
	check(second.rebuilds==2 and second.hero==before,"the stage is not rebuilt forever")
	await frames(2)
	# The banner arrives while the screen is open: the screen follows the lobby.
	game.ads.supported = true
	game.ads._menu = true
	game.ads.banner_height = 120
	game.hud._resize()
	await frames(2)
	var view := lobby()
	check(view.position.y>=100,"the lobby steps down under the banner (%.0f)" % view.position.y)
	check(second.position.is_equal_approx(view.position) and second.size.is_equal_approx(view.size),"the open character screen follows the lobby under the banner")
	check(is_instance_valid(second.hero) and second.slot=="jacket" and second.cards.size()==HeroOutfit.COLOURS["jacket"].size(),"the moved screen keeps its hero and its open slot")
	check(second.stage.get_global_rect().position.y>=view.get_global_rect().position.y,"the stage is not left under the banner")
	game.ads.banner_height = 0
	game.hud._resize()
	await frames(2)
	check(second.position.is_equal_approx(lobby().position),"and follows it back when the banner goes")
	second.close()
	await wait(.3)
	check(lobby().visible and not is_instance_valid(second),"closing returns to the lobby")

func header_wallet() -> Array:
	return [lobby().wallet_labels["gold"].text,lobby().wallet_labels["diamonds"].text]

func wallet_tests() -> void:
	await fresh_game()
	game.model.profile["gold"] = 1000
	game.model.profile["diamonds"] = 7
	# As after a run: the lobby is built anew and shows what the player has.
	game.hud.clear()
	game.hud.show_menu()
	await frames(2)
	check(header_wallet()==["1000","7"],"a fresh lobby shows the wallet (%s)" % str(header_wallet()))
	game.set_setting("reduce_effects",true)
	game.hud.select_menu("equipment")
	await frames(2)
	var price_before: int = game.model.profile["gold"]
	game.hud._buy_upgrade(GameModel.RADIUS)
	await frames(2)
	check(int(game.model.profile["gold"])<price_before,"an upgrade was bought")
	check(header_wallet()[0]==str(int(game.model.profile["gold"])),"the lobby wallet shows the gold left after an upgrade (%s of %d)" % [header_wallet()[0],int(game.model.profile["gold"])])
	# With effects on the number counts down and ends on the value.
	game.set_setting("reduce_effects",false)
	var gold_before: int = game.model.profile["gold"]
	game.hud._buy_upgrade(GameModel.RADIUS)
	await frames(2)
	if int(game.model.profile["gold"])<gold_before:
		check(header_wallet()[0]!=str(int(game.model.profile["gold"])),"the wallet counts instead of jumping")
		await wait(MenuSurface.COUNT+.15)
		check(header_wallet()[0]==str(int(game.model.profile["gold"])),"the count ends on the real value (%s)" % header_wallet()[0])
	# The wardrobe: its own wallet and the lobby's follow a purchase.
	game.hud.select_menu("expedition")
	await frames(2)
	lobby().open_character()
	await frames(2)
	var screen: CharacterScreen = lobby().character_screen
	screen.pick_slot("jacket")
	screen.pick_colour("jacket_glacier")
	game.model.profile["gold"] = 900
	screen.refresh_wallet()
	await wait(MenuSurface.COUNT+.15)
	screen._buy_pressed()
	await wait(MenuSurface.COUNT+.15)
	check(screen.wallet_labels["gold"].text==str(int(game.model.profile["gold"])) and int(game.model.profile["gold"])<900,"the wardrobe wallet counts down to the gold left (%s)" % screen.wallet_labels["gold"].text)
	screen.close()
	await wait(MenuSurface.COUNT+.3)
	check(header_wallet()[0]==str(int(game.model.profile["gold"])),"the lobby wallet follows a wardrobe purchase without a rebuild (%s)" % header_wallet()[0])

func motion_tests() -> void:
	await fresh_game()
	# A press and its release are one motion: the later one replaces the earlier.
	var start: Button = lobby().start_button
	start.button_down.emit()
	var sinking: Tween = start.get_meta("press_tween")
	start.button_up.emit()
	check(not sinking.is_valid() and (start.get_meta("press_tween") as Tween).is_valid(),"a release replaces the press tween instead of fighting it")
	await wait(MenuSurface.RELEASE+.1)
	check(start.scale.is_equal_approx(Vector2.ONE),"a tapped button comes back to rest (%s)" % str(start.scale))
	check(MenuSurface.PRESS<=.12 and MenuSurface.RELEASE<=.2 and MenuSurface.FADE<=.2 and MenuSurface.SLIDE<=.3 and MenuSurface.POP<=.3,"interface motion stays within 0.3 s")
	# The exit dialog: open and closed are states, the fade follows.
	game.go_back()
	check(game.hud.exit_confirmation_visible(),"Back opens the exit dialog")
	game.go_back()
	check(not game.hud.exit_confirmation_visible(),"a second Back closes it at once, before its fade ends")
	game.go_back()
	check(game.hud.exit_confirmation_visible() and game.hud.exit_overlay.visible,"a third Back during the fade opens it again")
	await wait(.3)
	check(is_equal_approx(game.hud.exit_overlay.modulate.a,1.0) and game.hud.exit_dialog.scale.is_equal_approx(Vector2.ONE),"the reopened dialog ends fully shown")
	game.hud.hide_exit_confirmation()
	await wait(.25)
	check(not game.hud.exit_overlay.visible,"the closed dialog is hidden once its fade ends")
	# Sheets and the result screen play their entrance once.
	game.start_run(false)
	await frames(2)
	game.pause_run()
	var pause: ExpeditionMenu = game.hud.content.get_child(game.hud.content.get_child_count()-1)
	check(pause.animated and pause.modulate.a<1.0,"the pause sheet fades in when it opens")
	await wait(MenuSurface.SLIDE+.1)
	var sheet: Panel = pause.get_child(0)
	check(is_equal_approx(sheet.modulate.a,1.0) and sheet.get_global_rect().end.y<=game.hud.root.get_global_rect().end.y,"the sheet ends in place on the screen")
	game.hud._resize()
	await frames(1)
	var again: ExpeditionMenu = game.hud.content.get_child(game.hud.content.get_child_count()-1)
	check(again!=pause and not again.animated and is_equal_approx(again.modulate.a,1.0),"a sheet rebuilt in place does not play its entrance again")
	# The pause route line: its height tag keeps clear of the note above.
	var note_bottom := 0.0
	var line: MenuSurface.RouteLine
	for node in again.get_child(0).get_children():
		if node is Label and node.text.begins_with("Попытка"): note_bottom = node.position.y+node.size.y
		if node is MenuSurface.RouteLine: line = node
	check(line!=null and line.position.y-16>=note_bottom,"the height tag above the pause route line clears the note (%.0f >= %.0f)" % [line.position.y-16 if line!=null else -1.0,note_bottom])
	game.unpause()
	await frames(2)
	game.fail_run("Упал ниже экрана")
	game.finish_run(false)
	await frames(1)
	var result: ExpeditionMenu = game.hud.content.get_child(game.hud.content.get_child_count()-1)
	var settled: int = int(game.settlement.get("total",0))+int(game.settlement.get("zone_bonus",0))+int(game.settlement.get("coins",0))
	await wait(MenuSurface.COUNT+.5)
	var total: Label = result.find_child("Total",true,false)
	check(total!=null and total.text=="+%d" % settled,"the result total ends on the settled gold (%s)" % (total.text if total!=null else "none"))
	var note: Label = result.find_child("Note",true,false)
	check(note!=null and note.get_parent() is Panel,"the note under the result buttons lies on the stone sheet, where its ink reads")
	# The count really plays, and "Без вспышек" shows the value at once.
	var sample := {"success":true,"highest":1200,"height":540,"loot":900,"finish":1300,"total":2740,"diamonds":20,"seconds":63,"shots":15,"catches":12}
	game.hud.clear()
	game.hud.show_result(sample)
	total = game.hud.content.get_child(game.hud.content.get_child_count()-1).find_child("Total",true,false)
	check(total.text=="+0","the total starts its count from zero")
	game.set_setting("reduce_effects",true)
	game.hud.clear()
	game.hud.show_result(sample)
	total = game.hud.content.get_child(game.hud.content.get_child_count()-1).find_child("Total",true,false)
	check(total.text=="+2740","without effects the total stands at once")
	game.set_setting("reduce_effects",false)
	game.model.profile["active"] = {}
	game.show_menu()
	await frames(2)

func build_cost_tests() -> void:
	await fresh_game()
	# Buttons of one tone share their boxes; slabs of one look share theirs.
	var a: Button = lobby().action(lobby(),"А",Vector2.ZERO,Vector2(80,40),Callable())
	var b: Button = lobby().action(lobby(),"Б",Vector2.ZERO,Vector2(80,40),Callable())
	check(a.get_theme_stylebox("normal")==b.get_theme_stylebox("normal") and a.get_theme_stylebox("pressed")==b.get_theme_stylebox("pressed"),"two buttons of one tone share their style boxes")
	var primary: Button = lobby().action(lobby(),"В",Vector2.ZERO,Vector2(80,40),Callable(),"primary")
	check(primary.get_theme_stylebox("normal")!=a.get_theme_stylebox("normal"),"tones keep their own boxes")
	check(lobby().slab(lobby(),Vector2.ZERO,Vector2(60,40)).get_theme_stylebox("panel")==lobby().slab(lobby(),Vector2.ZERO,Vector2(90,50)).get_theme_stylebox("panel"),"slabs of one look share a box")
	for node in [a,b,primary]: node.queue_free()
	# A palette change gives new boxes, not the old colours.
	var yellow: Color = (primary.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	game.set_setting("color_scheme","blue_yellow")
	await frames(3)
	var recoloured: Button = lobby().action(lobby(),"Г",Vector2.ZERO,Vector2(80,40),Callable(),"primary")
	check(not (recoloured.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(yellow),"another colour scheme repaints the primary button")
	game.set_setting("color_scheme","normal")
	await frames(3)
	# Shaders: one object per source, shared by heroes and worlds.
	var hero_a := HeroModel.new()
	var hero_b := HeroModel.new()
	root.add_child(hero_a)
	root.add_child(hero_b)
	hero_a.setup(true,true)
	hero_b.setup(false,true)
	check(hero_a.shader_material.shader==hero_b.shader_material.shader,"two heroes share one shader")
	check(hero_a.shader_material!=hero_b.shader_material,"each hero keeps a material of his own")
	hero_a.queue_free()
	hero_b.queue_free()
	check(ShaderBank.of("shader_type spatial; void fragment(){ ALBEDO=vec3(1.0); }")==ShaderBank.of("shader_type spatial; void fragment(){ ALBEDO=vec3(1.0); }"),"the same source gives the same shader")
	# Engine-written material shaders are held: one material per kind.
	var holder := Node3D.new()
	root.add_child(holder)
	var held_before := ShaderBank.held_count()
	for index in range(3):
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(.1*index,.5,.5)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.disable_fog = true
		mesh.material_override = material
		holder.add_child(mesh)
	var particles := GPUParticles3D.new()
	particles.process_material = ParticleProcessMaterial.new()
	holder.add_child(particles)
	ShaderBank.hold_tree(holder)
	check(ShaderBank.held_count()==held_before+2,"three materials that differ only in colour are one kind; the particles are another (%d new)" % (ShaderBank.held_count()-held_before))
	ShaderBank.hold_tree(holder)
	check(ShaderBank.held_count()==held_before+2,"holding the same tree again adds nothing")
	holder.queue_free()
	# The prepared world's first draw in parts never loses a mesh.
	game.model.set_route_choice(0,0)
	game.start_run(false)
	await frames(2)
	var world: MountainWorld = game.world
	world.complete_view(game.camera_y,game.camera_x,20)
	var visible_before := {}
	for node in world.find_children("*","VisualInstance3D",true,false): visible_before[node.get_instance_id()] = node.visible
	world.warm_begin()
	check(world.warm_left()>20,"the first draw has parts to show (%d)" % world.warm_left())
	var steps := 0
	while world.warm_step(12): steps += 1
	check(steps>=1 and world.warm_left()==0,"the parts come in over several frames (%d steps)" % steps)
	var same := true
	for node in world.find_children("*","VisualInstance3D",true,false):
		if visible_before.get(node.get_instance_id(),node.visible)!=node.visible: same = false
	check(same,"after the first draw every mesh is shown or hidden as before")
	world.warm_begin()
	world.warm_step(5)
	world.warm_finish()
	same = true
	for node in world.find_children("*","VisualInstance3D",true,false):
		if visible_before.get(node.get_instance_id(),node.visible)!=node.visible: same = false
	check(same and world.warm_left()==0,"a run that starts in the middle of the first draw gets the whole mountain")
	# The wall behind a platform is measured once per level.
	var ledge: Dictionary = world.ledges[0]
	var visuals: MountainVisuals = world.visuals
	BuildCache.clear()
	var measured: float = visuals.platform_back(ledge["left"],ledge["right"],ledge["top"],1.32)
	check(BuildCache.platform_backs.size()==1,"a platform's wall is kept after it is measured")
	check(is_equal_approx(visuals.platform_back(ledge["left"],ledge["right"],ledge["top"],1.32),measured),"the kept wall is the measured wall")
	check(not is_equal_approx(visuals.platform_back(ledge["left"]+3.0,ledge["right"]+3.0,ledge["top"]+9.0,1.32),INF) and BuildCache.platform_backs.size()==2,"another platform is measured on its own")
	game.finish_run(false)
	game.model.profile["active"] = {}
	game.show_menu()
	await frames(2)

func iris_tests() -> void:
	await fresh_game()
	game.hud.transitions = true
	var starts := [0]
	var counted := func(): starts[0] += 1
	# A climb starts once, under the closed iris, however often it is pressed.
	game.begin_run(func():
		counted.call()
		game.start_run(false))
	check(game.state=="menu" and game.hud.transition_running(),"the climb waits for the iris to close")
	game.begin_run(func():
		counted.call()
		game.start_run(false))
	game.press_lobby_action()
	game.go_back()
	check(not game.hud.exit_confirmation_visible(),"Back does nothing while the iris closes")
	await wait(game.hud.IrisClose.DURATION+.15)
	check(starts[0]==1 and game.state=="play","three presses start one climb (%d)" % starts[0])
	check(is_instance_valid(game.hud.level_intro),"the level's own iris takes over")
	await frames(2)
	check(not is_instance_valid(game.hud.iris_close),"the closing iris is gone once the level's opens")
	await wait(game.hud.LevelIntro.DURATION+.1)
	check(not game.hud.transition_running() and not is_instance_valid(game.hud.level_intro),"nothing of the transition is left on the climb")
	# Nothing starts (an endless climb before the first summit): the iris
	# opens again and the menu is usable.
	game.show_menu()
	await frames(2)
	game.model.profile["active"] = {}
	game.begin_run(func(): game.start_run(true))
	await wait(game.hud.IrisClose.DURATION+.1)
	check(game.state=="menu","a refused start leaves the player in the camp")
	await wait(game.hud.IrisClose.DURATION+.15)
	check(not is_instance_valid(game.hud.iris_close) and not game.hud.transition_running(),"the iris opens again when nothing started")
	game.hud.transitions = false

func freeing_tests() -> void:
	await fresh_game()
	var holder := Node3D.new()
	for index in range(300):
		var child := Node3D.new()
		child.add_child(Node3D.new())
		holder.add_child(child)
	game.add_child(holder)
	var watch := holder.get_child(5)
	game.retire(holder)
	check(not holder.is_inside_tree() and is_instance_valid(holder),"a retired world leaves the tree at once")
	game._reap(-1)
	check(not is_instance_valid(holder) and not is_instance_valid(watch) and game.retired_count()==0,"and is freed to the last node")
	# Bounded: a large world takes several frames, never one long one.
	var big := Node3D.new()
	for index in range(3000): big.add_child(Node3D.new())
	game.add_child(big)
	game.retire(big)
	var t := Time.get_ticks_usec()
	game._reap(game.REAP_USEC)
	check((Time.get_ticks_usec()-t)<game.REAP_USEC*3,"one frame's share of freeing stays near its budget")
	game._reap(-1)
	# A location switch: the old mountain leaves the tree on the spot.
	game.prepare_worlds = true
	for i in range(4): game._update_prepared_world()
	var old: MountainWorld = game.prepared_world
	check(is_instance_valid(old),"a mountain is being prepared behind the camp")
	game.cycle_location(1)
	game._update_prepared_world()
	check(not old.is_inside_tree(),"switching the route lets the old mountain go out of the tree")
	check(game.prepared_level!=null and game.prepared_world.layout.anchors.is_empty(),"the new route's layout is laid in a frame of its own")
	game._update_prepared_world()
	check(game.prepared_level==null and not game.prepared_world.layout.anchors.is_empty(),"and laid in the next frame")
	game._reap(-1)
	game.cycle_location(-1)
	game.prepare_worlds = false
	# The layouts of every route are read ahead.
	check(AssetWarmup._started or DisplayServer.get_name()=="headless","the warm-up runs in the game")
	AssetWarmup._started = false
	AssetWarmup._pending.clear()
	AssetWarmup.start()
	var layouts := AssetWarmup._pending.filter(func(path: String): return path.ends_with("layout.res"))
	check(layouts.size()==9,"the warm-up reads the layouts of all nine routes (%d)" % layouts.size())
	while not AssetWarmup.done():
		AssetWarmup.poll()
		await process_frame

func wardrobe_tab_tests() -> void:
	await fresh_game()
	lobby().open_character()
	await frames(2)
	var screen: CharacterScreen = lobby().character_screen
	var tab: Button = screen.slot_buttons["jacket"]
	var other: Button = screen.slot_buttons["boots"]
	screen.pick_slot("jacket")
	check((tab.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(MenuSurface.SLATE),"the open slot is the slate plate")
	check((other.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a<.05,"the other slots are text in the groove")
	check(not (tab.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.is_equal_approx(MenuSurface.HOLD),"no yellow tab beside the yellow purchase button")
	screen.close()
	await frames(2)

func result_wallet_tests() -> void:
	await fresh_game()
	game.model.profile["gold"] = 2000
	game.model.profile["diamonds"] = 25
	var sample := {"success":true,"first":false,"highest":1200,"height":540,"loot":200,"finish":1300,"total":2040,"diamonds":20,"seconds":63,"shots":15,"catches":12}
	game.state = "result"
	game.hud.show_result(sample)
	var screen: ExpeditionMenu = game.hud.content.get_child(game.hud.content.get_child_count()-1)
	check(screen.wallet_labels["gold"].text=="0" and screen.wallet_labels["diamonds"].text=="5","the result wallet starts from what was there before the reward (%s, %s)" % [screen.wallet_labels["gold"].text,screen.wallet_labels["diamonds"].text])
	var sheet: Panel = screen.get_child(0)
	check(screen.find_child("Total",true,false).get_parent()==sheet and sheet.get_global_rect().end.y<=game.hud.root.get_global_rect().end.y+1,"the reward lies in the bottom sheet")
	var head_bottom := 0.0
	for node in screen.get_children():
		if node!=sheet and node is Control and node.get_child_count()>0 and not node is Panel: head_bottom = maxf(head_bottom,node.get_global_rect().end.y)
	check(head_bottom<=sheet.get_global_rect().position.y+1,"the climb's summary stays above the sheet (%.0f <= %.0f)" % [head_bottom,sheet.get_global_rect().position.y])
	await wait(.1+6*MenuSurface.STAGGER+MenuSurface.COUNT*.8+.1)
	var flying := screen.find_children("*","UiSymbol",true,false).filter(func(node): return node.top_level)
	check(flying.size()>=3,"coins take off from the total (%d)" % flying.size())
	await wait(ExpeditionMenu.FLIGHT+.5+.3)
	check(screen.wallet_labels["gold"].text=="2000" and screen.wallet_labels["diamonds"].text=="25","the wallet ends on the real sums")
	check(screen.find_children("*","UiSymbol",true,false).filter(func(node): return node.top_level).is_empty(),"no coin is left in the air")
	# Without effects: no flight, the wallet stands on its value.
	game.set_setting("reduce_effects",true)
	game.hud.clear()
	game.hud.show_result(sample)
	screen = game.hud.content.get_child(game.hud.content.get_child_count()-1)
	check(screen.wallet_labels["gold"].text=="2000","without effects the wallet shows the sum at once")
	game.set_setting("reduce_effects",false)
	game.state = "menu"
	game.show_menu()
	await frames(2)

func control_tests() -> void:
	await fresh_game()
	# The slider: keys step it, a tap never leaves it focused.
	var slider := MenuSurface.RopeSlider.new()
	slider.size = Vector2(300,44)
	slider.minimum = 0
	slider.maximum = 100
	slider.step = 5
	slider.value = 50
	root.add_child(slider)
	var seen: Array = []
	slider.changed.connect(func(value: float): seen.append(value))
	slider.grab_focus()
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	slider._gui_input(key)
	check(slider.value==55.0 and seen==[55.0],"the right arrow steps a focused slider (%.0f)" % slider.value)
	key.keycode = KEY_LEFT
	key.physical_keycode = KEY_LEFT
	slider._gui_input(key)
	slider._gui_input(key)
	check(slider.value==45.0,"the left arrow steps it back (%.0f)" % slider.value)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(slider.track_left(),22)
	slider._gui_input(tap)
	check(not slider.has_focus(),"a touch takes the focus ring off")
	await wait(MenuSurface.PRESS+.05)
	check(slider.held>.9,"a held knob is raised")
	tap.pressed = false
	slider._gui_input(tap)
	check(slider.value==0.0,"a tap at the start sets the minimum")
	await wait(MenuSurface.RELEASE+.05)
	check(slider.held<.05,"and the knob settles")
	slider.queue_free()
	# The switch.
	var toggle := MenuSurface.Toggle.new()
	root.add_child(toggle)
	toggle.set_on(true,false)
	check(toggle.on and bool(toggle.get_meta("on")) and toggle.knob==1.0,"a switch set on shows on at once")
	toggle.set_on(false)
	await wait(MenuSurface.POP+.05)
	check(not toggle.on and is_zero_approx(toggle.knob),"and slides off")
	check(toggle.size.y>=44.0,"a switch is a comfortable touch target")
	toggle.queue_free()
	# The route bar: the track runs into the summit badge, never over it.
	var line: MenuSurface.RouteLine = lobby().route(lobby(),Vector2.ZERO,484,600.0)
	check(line.trail_end()<=line.peak().x-MenuSurface.RouteLine.BADGE,"the track ends at the summit badge")
	check(is_equal_approx(line.x_of(line.summit),line.trail_end()) and is_equal_approx(line.x_of(0),line.track_left()),"the summit is at the end of the track, the start at its beginning")
	line.queue_free()

func run_tests() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		quit(2)
		return
	await control_tests()
	await iris_tests()
	await freeing_tests()
	await wardrobe_tab_tests()
	await result_wallet_tests()
	await hint_tests()
	await character_stage_tests()
	await wallet_tests()
	await motion_tests()
	await build_cost_tests()
	game.queue_free()
	await frames(2)
	print("UI_FLOW_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("  FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)
