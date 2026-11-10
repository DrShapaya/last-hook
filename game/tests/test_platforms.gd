extends SceneTree

# Rest platforms: the physics surface matches the drawn timber deck (no
# standing on air past the boards, no sinking, snagging or falling through),
# and a touch walk along a platform plays the hero's walk, not the aim pose.
# Platforms stand out of the rock: no boulder or sand heap of the rock stands
# on a deck, the deck's back is on the frontmost wall over it, and a snow cap
# is lowered so the hero's boots rest on the snow. The Start press finds the
# hero's model and textures already loaded (AssetWarmup).
# LASTHOOK_SAVE_DIR must point to a throwaway save folder.

const WoodPlatform := preload("res://scripts/wood_platform.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("PLATFORM FAILED: "+description)

func run_tests() -> void:
	model_matches_reach()
	snow_cap_is_walking_line()
	hero_assets_warm()
	if OS.get_environment("LASTHOOK_SAVE_DIR").is_empty():
		check(false,"LASTHOOK_SAVE_DIR is set")
	else:
		var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(game)
		await process_frame
		game.set_physics_process(false)
		game.set_process(false)
		game.model.profile = GameModel.fresh_profile()
		game.start_run(false)
		landing_and_walking(game)
		touch_walk_animates(game)
		await platforms_out_of_rock(game)
		game.queue_free()
	print("PLATFORM_TESTS ",checks," checks, ",failures.size()," failures")
	for failure in failures: print("  FAILED: ",failure)
	quit(0 if failures.is_empty() else 1)

# The boards of every authored model, stretched over a ledge as the game
# does, end exactly where the physics stops carrying the hero, and their top
# at the back is the walking line.
func model_matches_reach() -> void:
	check(is_equal_approx(MountainWorld.LEDGE_REACH,WoodPlatform.OVERHANG),"the physics reach past a ledge is the boards' overhang")
	for style: String in WoodPlatform.STYLES:
		for ledge_width in [2.6,3.2,4.2,7.0]:
			var width: float = ledge_width+WoodPlatform.OVERHANG*2.0
			var node := WoodPlatform.instantiate(style,width,{},false)
			var low := INF
			var high := -INF
			var top := -INF
			for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
				if WoodPlatform.part_of(mesh)!="wood": continue
				var faces := mesh.mesh.get_faces()
				for point in faces:
					# Deck boards only: the top layer, not joists or braces.
					if point.y<-.08: continue
					low = minf(low,point.x*node.scale.x)
					high = maxf(high,point.x*node.scale.x)
					top = maxf(top,point.y)
			node.free()
			var half: float = ledge_width*.5
			# The fascia board runs .05 past the boards at each end.
			check(absf(-low-(half+MountainWorld.LEDGE_REACH))<.08 and absf(high-(half+MountainWorld.LEDGE_REACH))<.08,
				"%s %.1f: boards end where the hero stops being carried (%.2f..%.2f vs ±%.2f)" % [style,ledge_width,low,high,half+MountainWorld.LEDGE_REACH])
			check(absf(top)<.02,"%s %.1f: the deck's top is the walking line (%.3f)" % [style,ledge_width,top])

func landing_and_walking(game) -> void:
	var world = game.world
	world.obstacles.clear()
	world.ledges.clear()
	world.add_ledge(Vector2(0,30),4.0)
	var ledge: Dictionary = world.ledges[0]
	var stand: float = float(ledge["top"])+SolidGeometry.BODY_HALF.y
	var board_end: float = float(ledge["right"])+WoodPlatform.OVERHANG
	# Drops straight down and fast diagonal landings across the deck.
	var x := -2.3
	var sank := 0
	var missed := 0
	while x<=2.3:
		for velocity in [Vector2(0,-3),Vector2(0,-25),Vector2(9,-14),Vector2(-9,-14)]:
			var to := Vector2(x,stand-1.2)
			var from: Vector2 = to-velocity*(2.0/velocity.length())
			var hit: Dictionary = world.move_player(from,to,velocity)
			# Where the path crosses the deck's top.
			var cross_x: float = lerpf(from.x,to.x,(from.y-stand)/(from.y-to.y))
			if hit["grounded"] and absf(hit["position"].y-stand)>.002: sank += 1
			if not hit["grounded"] and absf(cross_x)<board_end-.01: missed += 1
		x += .05
	check(sank==0,"landings on the deck stand exactly on its top (%d off)" % sank)
	check(missed==0,"no landing on the boards falls through (%d)" % missed)
	# Past the boards there is nothing to stand on.
	var past: Dictionary = world.move_player(Vector2(board_end+.04,stand+1),Vector2(board_end+.04,stand-1),Vector2(0,-5))
	check(not past["grounded"],"the hero does not stand on air past the boards")
	var edge: Dictionary = world.move_player(Vector2(board_end-.02,stand+1),Vector2(board_end-.02,stand-1),Vector2(0,-5))
	check(edge["grounded"],"the very end of the boards still carries the hero")
	# Walking the deck never snags: a level sweep end to end stays at height.
	var sweep: Dictionary = world.move_player(Vector2(-2,stand+.0002),Vector2(2,stand+.0002),Vector2(2.6,0))
	check(absf(sweep["position"].x-2)<.001 and absf(sweep["position"].y-(stand+.0002))<.001,"a walk along the deck is not snagged")
	# Real walking: the hero stays on the deck every step and stops at the
	# end of the boards, never past them and never short of the deck.
	game.sim.pos = Vector2(0,stand+.01)
	game.sim.vel = Vector2.ZERO
	game.sim.grounded = true
	game.sim.launched = true
	game.camera_y = 33
	game._position_camera()
	for frame in range(10): game._physics_process(1.0/60)
	var always_on := true
	game.walk = 1.0
	game.walk_used = true
	for frame in range(240):
		game._physics_process(1.0/60)
		if not game.sim.grounded or absf(game.sim.pos.y-stand)>.002: always_on = false
	game.walk = 0.0
	game.walk_used = false
	check(always_on,"walking the deck keeps the hero grounded on its top every frame")
	check(game.sim.pos.x<=board_end and game.sim.pos.x>board_end-.4,"walking stops at the end of the boards (x %.2f, boards end %.2f)" % [game.sim.pos.x,board_end])

# On a phone the walk is a held finger: that hold must not read as aiming,
# or the hero shows the aim pose and slides instead of walking.
func touch_walk_animates(game) -> void:
	var world = game.world
	world.obstacles.clear()
	world.ledges.clear()
	world.add_ledge(Vector2(0,30),6.0)
	var stand: float = 30.15+SolidGeometry.BODY_HALF.y
	game.sim.pos = Vector2(-2,stand+.01)
	game.sim.vel = Vector2.ZERO
	game.sim.grounded = true
	game.sim.launched = true
	game.camera_y = 33
	game._position_camera()
	for frame in range(10): game._physics_process(1.0/60)
	game.pointer_down(Vector2(300,400),true)
	check(game.hero_aiming(),"a fresh hold on a platform aims")
	var begin: int = game.gesture_last_msec
	game.pointer_move(Vector2(380,404),begin+10)
	game._update_touch_controls(begin+300)
	check(game.walk>.9 and not game.hero_aiming(),"a hold that walks is not aiming")
	var states := {}
	for frame in range(40):
		game._physics_process(1.0/60)
		game._process(1.0/60)
		states[str(game.explorer.body.get("state"))] = true
	check(game.sim.vel.x>2.0,"the touch walk moves the hero")
	check(states.has("walk") and not states.has("aim"),"the hero plays its walk while walking by touch (states %s)" % [states.keys()])
	game.pointer_up(Vector2(380,404))
	check(not game.hero_aiming(),"letting go ends the hold")

func snow_cap_is_walking_line() -> void:
	var bare: Node3D = WoodPlatform.instantiate("braced",3.6,{},false,"summer")
	check(is_zero_approx(float(bare.get_meta("rise"))),"a platform without a snow cap is not lowered")
	bare.free()
	var winter: Node3D = WoodPlatform.instantiate("braced",3.6,{},false,"winter")
	var rise := float(winter.get_meta("rise"))
	check(rise>.05 and rise<.25,"a snow cap lifts the walking surface (%.3f)" % rise)
	check(is_equal_approx(rise,WoodPlatform.cap_rise(winter)),"the rise is the cap's mean top")
	winter.free()

func hero_assets_warm() -> void:
	check("res://assets/hero" in AssetWarmup.FOLDERS,"the hero's model loads with the climb art")
	for path in ["res://assets/art/modular-pack-v1/rope-albedo.png","res://assets/art/modular-pack-v1/hook-head.png"]:
		check(path in AssetWarmup.FILES and ResourceLoader.exists(path),"%s loads ahead of the Start press" % path.get_file())

# On the desert route (rock with boulders and sand heaps on its ledges) and
# the snow peak: nothing of the rock stands on a deck, and the deck's back
# is on the frontmost wall under, at and just above it.
func platforms_out_of_rock(game) -> void:
	for location in [1,2]:
		for route in range(3):
			game.model.profile["locations"] = [0,1,2]
			game.model.set_route_choice(location,route)
			game.selected_location = location
			game.start_run(false)
			var world = game.world
			var rock = world.visuals._seen_rock() if world.visuals.has_method("_seen_rock") else null
			var on_deck := 0
			var embedded := 0
			for ledge in world.ledges:
				var left: float = ledge["left"]
				var right: float = ledge["right"]
				var top: float = ledge["top"]
				if rock!=null:
					for lump in rock.lumps(top-4.0,top+4.0):
						var at: Vector3 = lump[0]
						if at.x>left-.12 and at.x<right+.12 and at.y>top-.5 and at.y<top+1.0: on_deck += 1
				var back: float = world.visuals.platform_back(left,right,top,WoodPlatform.DROP["braced"])
				var x := left-.1
				while x<=right+.1:
					for y in [top-.2,top,top+.3]:
						if world.visuals.wall_depth(Vector2(x,y))>back+.001: embedded += 1
					x += .25
			check(on_deck==0,"location %d route %d: no boulder or sand heap stands on a platform (%d)" % [location,route,on_deck])
			check(embedded==0,"location %d route %d: platforms stand in front of the wall at the deck (%d)" % [location,route,embedded])
			await process_frame
