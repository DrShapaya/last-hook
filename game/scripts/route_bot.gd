class_name RouteBot
extends RefCounted

# A movement bot that plays a level through the real controls: from grip to
# grip along the main route, then up to the summit. It checks that a level
# is climbable with the kit it is given; it does not judge how hard or how
# pleasant that is for a person. Shared by tests and level tools.

# Throws with the one-finger gesture, as a player would.
static func touch_throw(game, target: Vector2) -> void:
	var origin := Vector2(150,400)
	if game.sim.attached:
		game.pointer_down(origin,true)
		game.pointer_up(origin)
	var direction: Vector2 = game.direction_to_target(target)
	var end: Vector2 = origin+Vector2(direction.x,-direction.y)*82*game._gesture_scale()
	game.pointer_down(origin,true)
	game.pointer_move(end)
	game.pointer_up(end)

# Climbs the main route from its first grip; returns how many grips were
# reached. `log` collects where it stopped.
static func climb_route(game, count: int, log: Array = []) -> int:
	var reached := 1
	for route_index in range(1,count):
		var target_id: int = game.world.main_route[route_index]
		var target: Vector2 = game.world.anchor_by_id(target_id)["pos"]
		var fired := false
		for frame in range(1200):
			if game.state!="play":
				log.append("stopped before grip %d (%s) at %s" % [route_index,game.state,str(game.sim.pos)])
				return reached
			if game.sim.attached:
				game.reel = 1.0 if frame<240 else 0.0
				if frame>=240: game.sim.request_length(3.3 if frame%360<180 else 2.0)
				if absf(game.sim.pos.x)>14 and game.sim.vel.x*game.sim.pos.x>0:
					game.pump = -signf(game.sim.pos.x)
				elif absf(game.sim.vel.x)>.1:
					game.pump = signf(game.sim.vel.x)
				elif absf(game.pump)<.1:
					game.pump = signf(target.x-game.sim.anchor.x)
				var current: Dictionary = game.world.anchor_by_id(game.anchor_id)
				var ignored: int = game.anchor_id if not current.get("permanent",true) else -1
				var sight: Dictionary = game.world.cast_hook(game.sim.pos,target,game.model.hook_radius(),ignored)
				var goal := target
				var clear_shot := false
				if not sight.is_empty() and not sight.get("blocked",false):
					var hit: Dictionary = sight["object"]
					clear_shot = int(hit["id"])==target_id
					if not clear_shot and int(hit["id"])!=game.anchor_id and hit["pos"].distance_to(target)<game.sim.anchor.distance_to(target)-.3:
						goal = hit["pos"]
						clear_shot = true
				var toward: Vector2 = (goal-game.sim.pos).normalized()
				if clear_shot and game.sim.pos.distance_to(goal)<5.2 and game.sim.vel.dot(toward)>.5:
					touch_throw(game,goal)
					fired = true
			game._physics_process(1.0/120)
			game._move_camera(1.0/120)
			if game.anchor_id==target_id and game.sim.attached:
				reached += 1
				break
			if fired and not game.bolt_active and not game.sim.attached:
				touch_throw(game,target)
		if reached!=route_index+1:
			log.append("could not reach grip %d at %s from %s" % [route_index,str(target),str(game.sim.pos)])
			return reached
	return reached

# A whole run of the current level from the start platform: true when the
# summit is reached and settled.
static func climb_to_summit(game, log: Array = []) -> bool:
	game.fire_hook(game.direction_to_target(game.world.anchors[0]["pos"]))
	for frame in range(120):
		game._physics_process(1.0/120)
		game._move_camera(1.0/120)
		if game.sim.attached: break
	var reached := climb_route(game,game.world.main_route.size(),log)
	for frame in range(1800):
		if game.state!="play": break
		game.reel = 1
		game.pump = signf(game.sim.vel.x) if absf(game.sim.vel.x)>.1 else 1.0
		game._physics_process(1.0/120)
		game._move_camera(1.0/120)
	log.append("reached %d/%d route grips" % [reached,game.world.main_route.size()])
	return game.state=="result" and bool(game.settlement.get("success",false))
