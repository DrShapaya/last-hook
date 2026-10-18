class_name HookVolley
extends RefCounted

# Every projectile owns its flight and return state. Contact policy belongs
# to the climb controller; events are ordered by time, never by array index.
var shots: Array[Dictionary] = []

func launch(origin: Vector2, directions: Array[Vector2], speed: float, velocity: Vector2) -> void:
	shots.clear()
	for direction in directions:
		var flight := HookFlight.new()
		flight.launch(origin,direction,speed,velocity)
		shots.append({"flight":flight,"state":"flying","return_velocity":Vector2.ZERO,"anchor_id":-1})

func has_state(state: String) -> bool:
	for shot in shots:
		if shot["state"]==state: return true
	return false

func return_shot(index: int, rebound := Vector2.ZERO) -> void:
	shots[index]["state"] = "returning"
	shots[index]["return_velocity"] = rebound
	shots[index]["anchor_id"] = -1

func catch_shot(index: int, id: int, contact: Vector2) -> void:
	shots[index]["state"] = "attached"
	shots[index]["anchor_id"] = id
	var flight: HookFlight = shots[index]["flight"]
	flight.position = contact

func advance(dt: float, hero: Vector2, world: MountainWorld, maximum: float, radius: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index in range(shots.size()):
		var shot := shots[index]
		var flight: HookFlight = shot["flight"]
		if shot["state"]=="returning":
			var desired := (hero-flight.position).normalized()*HookFlight.RETURN_SPEED
			shot["return_velocity"] = Vector2(shot["return_velocity"]).lerp(desired,1-exp(-dt*24))
			var advance: Vector2 = shot["return_velocity"]*dt
			if flight.position.distance_to(hero)<=maxf(.3,advance.length()):
				flight.position = hero
				shot["state"] = "idle"
			else: flight.position += advance
			flight.age += dt
			flight.trail.append(flight.position)
			if flight.trail.size()>15: flight.trail.remove_at(0)
			continue
		if shot["state"]!="flying": continue
		var previous := flight.position
		flight.advance(dt)
		var fraction := HookFlight.range_fraction(previous,flight.position,hero,maximum)
		var end := previous.lerp(flight.position,fraction)
		var hit := world.cast_hook(previous,end,radius)
		if not hit.is_empty():
			flight.position = hit["contact"]
			flight.trail[-1] = flight.position
			shot["state"] = "contact"
			events.append({"index":index,"collision":hit,"time":float(hit["fraction"])*fraction*dt})
		elif fraction<1 or flight.age>2.0:
			flight.position = end
			flight.trail[-1] = end
			return_shot(index)
	events.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a["time"])<float(b["time"]))
	return events

func snapshot() -> Array:
	var result: Array = []
	for shot in shots:
		var flight: HookFlight = shot["flight"]
		var returning: Vector2 = shot["return_velocity"]
		result.append({"x":flight.position.x,"y":flight.position.y,"vx":flight.velocity.x,"vy":flight.velocity.y,
			"age":flight.age,"state":shot["state"],"anchor_id":shot["anchor_id"],"rx":returning.x,"ry":returning.y})
	return result

func restore(data: Array) -> void:
	shots.clear()
	for item in data.slice(0,2):
		var flight := HookFlight.new()
		flight.position = Vector2(item["x"],item["y"])
		flight.velocity = Vector2(item["vx"],item["vy"])
		flight.age = float(item["age"])
		flight.trail = PackedVector2Array([flight.position])
		shots.append({"flight":flight,"state":str(item["state"]),"anchor_id":int(item["anchor_id"]),
			"return_velocity":Vector2(item["rx"],item["ry"])})
