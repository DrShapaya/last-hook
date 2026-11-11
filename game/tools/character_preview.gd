extends SceneTree

# Snapshots of the character screen (CharacterScreen) as the player sees it:
# the lobby opens, the character button is pressed, and frames are saved.
#   Godot --path game --script res://tools/character_preview.gd -- --out=<folder>
#   [--size=540x960] [--location=0..2] [--frames=1] [--lobby] (the lobby only)
#   [--outfit=id,id] (HeroOutfit colours to wear) [--tag=name] (file name)
#   [--slot=jacket] (open a wardrobe slot) [--try=id] (try a colour on)
#   [--gold=N]
#   [--demo] (a scripted visit, a frame every 1/15 s: idle, a spin, try-ons
#   and a purchase in the jacket slot, boots, the backpack, a tap; use --gold)
#   [--yaw=-1.57] (hold the hero turned: -.72 three-quarters, -1.57 front, 1.57 back)
# Needs a window. LASTHOOK_SAVE_DIR must point to a throwaway save folder.

var out := "user://character"
var frames := 1
var location := 0
var lobby_only := false
var demo := false
var outfit := {}
var tag := ""
var open_slot := ""
var try_on := ""
var gold := -1
var yaw := INF # --yaw=radians: hold the hero turned (REST_YAW is -.72, front -1.57).
var window_size := Vector2i(540,960)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		if argument.begins_with("--frames="): frames = maxi(1,int(argument.trim_prefix("--frames=")))
		if argument.begins_with("--location="): location = int(argument.trim_prefix("--location="))
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			window_size = Vector2i(int(parts[0]),int(parts[1]))
		if argument=="--lobby": lobby_only = true
		if argument=="--demo": demo = true
		if argument.begins_with("--tag="): tag = argument.trim_prefix("--tag=")
		if argument.begins_with("--slot="): open_slot = argument.trim_prefix("--slot=")
		if argument.begins_with("--try="): try_on = argument.trim_prefix("--try=")
		if argument.begins_with("--gold="): gold = int(argument.trim_prefix("--gold="))
		if argument.begins_with("--yaw="): yaw = float(argument.trim_prefix("--yaw="))
		if argument.begins_with("--outfit="):
			for id in argument.trim_prefix("--outfit=").split(","): outfit[HeroOutfit.slot_of(id)] = id
	DirAccess.make_dir_recursive_absolute(out)
	root.size = window_size
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in range(3): await process_frame
	game.model.profile["selected_location"] = location
	game.selected_location = location
	if not outfit.is_empty():
		game.model.profile["outfit"] = outfit.duplicate()
		HeroOutfit.worn = outfit.duplicate()
	if gold>=0: game.model.profile["gold"] = gold
	game.show_menu()
	for i in range(20): await process_frame
	var name := ("lobby" if lobby_only else "character")+("" if tag.is_empty() else "-"+tag)
	if not lobby_only:
		game.hud.lobby_view.open_character()
		var screen: CharacterScreen = game.hud.lobby_view.character_screen
		if not open_slot.is_empty(): screen.pick_slot(open_slot)
		if not try_on.is_empty(): screen.pick_colour(try_on)
		if yaw!=INF:
			screen.yaw = yaw
			screen.yaw_goal = yaw
		await create_timer(1.6).timeout
	if demo:
		await play_demo(game.hud.lobby_view.character_screen,name)
		quit()
		return
	for frame in range(frames):
		await RenderingServer.frame_post_draw
		var path := out.path_join("%s-%dx%d-l%d%s.png" % [name,window_size.x,window_size.y,location,"" if frames==1 else "-%03d" % frame])
		root.get_texture().get_image().save_png(path)
		print("CHARACTER_PREVIEW ",path)
		for i in range(6): await process_frame
	quit()

# Each step: [seconds, action]. Frames are taken every 1/15 s of real time.
func play_demo(screen: CharacterScreen, name: String) -> void:
	var steps := [[1.4,""],[1.6,"spin"],[1.4,"slot:jacket"],[1.3,"try:jacket_glacier"],[1.3,"try:jacket_rowan"],
		[2.2,"buy"],[1.3,"slot:boots"],[1.6,"try:boots_black"],[1.4,"slot:backpack"],[1.6,"try:backpack_pine"],
		[1.2,"slot:"],[2.2,"greet"]]
	var index := 0
	for step in steps:
		var command := str(step[1])
		if command.begins_with("slot:"): screen.pick_slot(command.trim_prefix("slot:") if command!="slot:" else screen.slot)
		elif command.begins_with("try:"): screen.pick_colour(command.trim_prefix("try:"))
		elif command=="buy": screen._buy_pressed()
		match command:
			"spin":
				screen.spin = 7.0
				screen.idle_for = 0.0
			"greet": screen.greet()
			"head": screen.pick_slot("head")
			"backpack": screen.pick_slot("backpack")
			"full": screen.pick_slot("")
		var until := Time.get_ticks_msec()+int(float(step[0])*1000)
		while Time.get_ticks_msec()<until:
			var next := Time.get_ticks_msec()+66
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s-demo-%04d.png" % [name,index]))
			index += 1
			while Time.get_ticks_msec()<next: await process_frame
	print("CHARACTER_PREVIEW demo frames ",index)
