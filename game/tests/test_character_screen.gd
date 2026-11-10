extends SceneTree

# The character screen (CharacterScreen): the lobby button opens it over the
# lobby, the 3D hero stands on the ledge of the chosen location, turns under
# a finger, greets on a tap, the slots move the camera, and back closes it.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("CHARACTER SCREEN FAILED: "+description)

func frames(count: int) -> void:
	for i in range(count): await process_frame

# Headless frames take a few milliseconds: easing needs real time.
func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = pressed
	root.push_input(event,true)

func drag(from: Vector2, to: Vector2) -> void:
	touch(from,true)
	var steps := 8
	for i in range(steps):
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = from.lerp(to,(i+1.0)/steps)
		event.relative = (to-from)/steps
		event.velocity = (to-from)*4
		root.push_input(event,true)
		await process_frame
	touch(to,false)

func wardrobe_tests(game, screen: CharacterScreen) -> void:
	var profile: Dictionary = game.model.profile
	profile["gold"] = 100
	profile["outfit"] = {}
	profile["outfit_owned"] = []
	HeroOutfit.worn = {}
	screen.pick_slot("jacket")
	await process_frame
	check(screen.cards.size()==HeroOutfit.COLOURS["jacket"].size(),"the jacket slot shows its colours (%d cards)" % screen.cards.size())
	check(screen.chosen=="jacket_moss","the worn colour is picked when a slot opens")
	check(screen.buy_button.disabled,"the worn colour cannot be bought again")
	# Try-on: on the hero at once, not owned yet.
	screen.cards["jacket_glacier"].pressed.emit()
	await process_frame
	var window: PackedFloat32Array = screen.hero.shader_material.get_shader_parameter("slot_window")
	check(window[HeroOutfit.CODES["jacket"]]>0,"a tried colour goes on the hero")
	check(screen.act_time>=0 and screen.act_slot=="jacket","the hero shows off the tried jacket")
	check(screen.buy_button.text.contains("300") and not screen.buy_button.disabled,"the buy button names the price")
	# Short of gold: nothing is spent, the note says how much is missing.
	screen.buy_button.pressed.emit()
	await process_frame
	check(int(profile["gold"])==100 and not HeroOutfit.owns(profile,"jacket_glacier"),"without enough gold nothing is bought")
	check(screen.note_label.text.contains("200"),"the note says how much gold is missing (%s)" % screen.note_label.text)
	# With gold: bought, worn, saved; the wallet and cards follow.
	profile["gold"] = 640
	screen.buy_button.pressed.emit()
	await process_frame
	check(int(profile["gold"])==340,"buying spends the price (%d)" % int(profile["gold"]))
	check(HeroOutfit.owns(profile,"jacket_glacier") and HeroOutfit.worn_id(profile,"jacket")=="jacket_glacier","the bought colour is owned and worn")
	check(HeroOutfit.worn.get("jacket","")=="jacket_glacier","the climb will wear it")
	check(screen.bought and screen.sparkles.emitting,"a purchase is celebrated")
	check(screen.buy_button.disabled,"the bought colour shows as worn")
	var stored := JSON.parse_string(FileAccess.get_file_as_string(game.model.save_path)) as Dictionary
	check(stored!=null and "jacket_glacier" in stored.get("outfit_owned",[]),"the purchase is saved")
	# Owned colours swap for free.
	screen.cards["jacket_moss"].pressed.emit()
	await process_frame
	check(screen.buy_button.text=="Надеть","an owned colour is put on, not bought")
	screen.buy_button.pressed.emit()
	await process_frame
	check(int(profile["gold"])==340 and HeroOutfit.worn_id(profile,"jacket")=="jacket_moss","putting on an owned colour is free")
	screen.cards["jacket_glacier"].pressed.emit()
	await process_frame
	screen.buy_button.pressed.emit()
	await process_frame
	# A try-on left unbought does not stay on.
	screen.pick_slot("head")
	await process_frame
	screen.cards["head_coral"].pressed.emit()
	await process_frame
	check(HeroOutfit.worn_id(profile,"head")=="head_sun","trying on does not buy")
	screen.pick_slot("")
	var shown: PackedFloat32Array = screen.hero.shader_material.get_shader_parameter("slot_window")
	check(shown[HeroOutfit.CODES["head"]]==0.0,"leaving a slot takes off what was only tried on")

# Profile rules: unknown or foreign ids are dropped, defaults are free.
func outfit_rules() -> void:
	var profile := {"gold":0,"outfit":{"jacket":"head_coral","pants":"pants_denim","boots":"nothing"},"outfit_owned":["pants_denim","nothing","jacket_moss"]}
	HeroOutfit.sanitize(profile)
	check(profile["outfit"]=={"pants":"pants_denim"},"only owned colours of their own slot stay worn (%s)" % str(profile["outfit"]))
	check(profile["outfit_owned"]==["pants_denim"],"unknown and free ids are not kept as bought")
	check(HeroOutfit.owns(profile,"boots_leather"),"the painted colours are always owned")
	check(HeroOutfit.buy(profile,"boots_red").begins_with("Не хватает"),"buying needs the gold")
	for slot in HeroOutfit.SLOTS:
		check(HeroOutfit.COLOURS[slot].size()>=4 and HeroOutfit.price(HeroOutfit.default_id(slot))==0,"slot %s offers colours and a free default" % slot)
	check(GameModel.fresh_profile().has("outfit") and GameModel.fresh_profile().has("outfit_owned"),"a new profile has a wardrobe")
	HeroOutfit.worn = {}

func run_tests() -> void:
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		push_error("Tests require LASTHOOK_SAVE_DIR to keep saves isolated")
		quit(2)
		return
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await frames(3)
	game.model.profile["selected_location"] = 2
	game.selected_location = 2
	game.show_menu()
	await frames(3)
	var lobby: LobbyView = game.hud.lobby_view
	lobby.open_character()
	await frames(3)
	var screen: CharacterScreen = lobby.character_screen
	check(is_instance_valid(screen) and screen.is_inside_tree(),"the character button opens the character screen")
	check(not lobby.visible and not lobby.is_processing_input(),"the lobby rests under the character screen")
	check(screen.location==2,"the stage shows the chosen location")
	check(is_instance_valid(screen.hero) and screen.hero.is_inside_tree(),"the 3D hero stands on the stage")
	check(screen.viewport.own_world_3d,"the stage has its own 3D world, apart from the climb")
	check(screen.ledge.mesh.get_faces().size()>300,"the ledge is a rock, not a plate")
	# Alive while nobody touches him: the idle breath moves the arms and the
	# head turns to look around.
	var hand: int = screen.hero.bone_index["hand_near"]
	var before: Vector3 = screen.hero.skeleton.get_bone_global_pose(hand).origin
	# A glance to the side: the head eases toward it (the next one is far off).
	screen.look_goal = .45
	screen.next_look = 10.0
	var until := Time.get_ticks_msec()+2500
	while Time.get_ticks_msec()<until:
		await process_frame
	screen.hero.skeleton.force_update_all_bone_transforms()
	check(screen.hero.state=="idle","the hero idles on the ledge (%s)" % screen.hero.state)
	check(screen.hero.skeleton.get_bone_global_pose(hand).origin.distance_to(before)>.002,"the hero breathes")
	check(screen.hero.look_yaw>.3,"the hero looks around (%.2f)" % screen.hero.look_yaw)
	# The schedule picks new glances by itself.
	var goals := {}
	for i in range(40):
		screen.next_look = 0.0
		await process_frame
		goals[snappedf(screen.look_goal,.01)] = true
	check(goals.size()>5,"the hero picks new glances")
	# The head turn reaches the head bone.
	screen.hero.look_yaw = .5
	screen.hero._apply({})
	var turned: Quaternion = screen.hero.skeleton.get_bone_pose_rotation(screen.hero.bone_index["head"])
	screen.hero.look_yaw = 0.0
	screen.hero._apply({})
	var straight: Quaternion = screen.hero.skeleton.get_bone_pose_rotation(screen.hero.bone_index["head"])
	check(turned.angle_to(straight)>.3,"looking around turns the head")
	# A drag across the stage turns the hero; he settles back afterwards.
	var stage_rect: Rect2 = screen.stage.get_global_rect()
	var canvas: Transform2D = screen.stage.get_global_transform_with_canvas()
	var middle: Vector2 = canvas*(screen.stage.size*Vector2(.5,.85))
	var yaw_before: float = screen.yaw
	await drag(middle,middle+Vector2(160,0)*canvas.get_scale().x)
	check(absf(screen.yaw-yaw_before)>.5,"a drag turns the hero (%.2f)" % (screen.yaw-yaw_before))
	check(stage_rect.size.x>0 and lobby.is_processing_input()==false,"the drag stays on the character screen")
	screen.idle_for = 10.0
	screen.spin = 0.0
	await wait(2.0)
	check(absf(angle_difference(screen.yaw,CharacterScreen.REST_YAW))<.15,"the hero settles back to three-quarters")
	# A tap on the hero: he turns to the viewer and cheers.
	var hero_point: Vector2 = screen.camera.unproject_position(screen.hero.global_position+Vector3(0,.1,0))
	hero_point = canvas*(hero_point*screen.stage.size/Vector2(screen.viewport.size))
	touch(hero_point,true)
	await process_frame
	touch(hero_point,false)
	await frames(4)
	check(screen.wave_time>=0,"a tap on the hero makes him wave")
	await wait(.6)
	var arm: Quaternion = screen.hero.skeleton.get_bone_pose_rotation(screen.hero.bone_index["upper_arm_near"])
	var arm_rest: Quaternion = screen.hero.bone_rest[screen.hero.bone_index["upper_arm_near"]]
	check(arm.angle_to(arm_rest)>1.5,"the waving arm is raised (%.2f)" % arm.angle_to(arm_rest))
	check(is_equal_approx(screen.yaw_goal,CharacterScreen.FRONT_YAW),"a tap turns the hero to the viewer")
	await wait(1.8)
	check(screen.wave_time<0 and screen.hero.state=="idle","the wave ends (%s)" % screen.hero.state)
	# Slots move the camera onto their part.
	var full_distance: float = screen.framing_distance
	screen.pick_slot("head")
	await wait(1.2)
	check(screen.framing_distance<full_distance-1.5,"the head slot zooms in on the head")
	check(screen.framing_target.y>.9,"the head slot frames the head")
	screen.pick_slot("backpack")
	check(screen.yaw_goal>0,"the backpack slot turns the hero round")
	screen.pick_slot("")
	await wait(1.2)
	check(absf(screen.framing_distance-full_distance)<.2,"full height frames the whole hero again")
	# Wardrobe: a slot shows its colours, a card tries one on, buying needs gold.
	await wardrobe_tests(game,screen)
	# Back closes the screen and gives the lobby back.
	game.go_back()
	await wait(.4)
	check(not is_instance_valid(lobby.character_screen),"back closes the character screen")
	check(lobby.visible and lobby.is_processing_input(),"the lobby returns after the character screen")
	check(not game.hud.exit_confirmation_visible(),"back from the character screen does not offer to quit")
	# The climb's hero wears what was bought.
	var climber := HeroModel.new()
	root.add_child(climber)
	climber.setup()
	var window: PackedFloat32Array = climber.shader_material.get_shader_parameter("slot_window")
	check(window[HeroOutfit.CODES["jacket"]]>0,"the climbing hero wears the bought jacket colour")
	check(window[HeroOutfit.CODES["head"]]==0.0,"slots left as they were keep the painted colour")
	climber.queue_free()
	outfit_rules()
	game.queue_free()
	await process_frame
	print("CHARACTER_SCREEN_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("  FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)
