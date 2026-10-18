class_name HookFlight
extends RefCounted

# World units use upward Y. The projectile is lighter than the explorer, but
# still falls; throwing strength changes speed rather than available rope.
const GRAVITY := Vector2(0,-8.0)
const STEP := 1.0/120.0
const INHERITANCE := .28
const RETURN_SPEED := 42.0

var position := Vector2.ZERO
var velocity := Vector2.ZERO
var age := 0.0
var trail := PackedVector2Array()

static func inherited_velocity(hero_velocity: Vector2) -> Vector2:
	return (hero_velocity*INHERITANCE).limit_length(3.0)

func launch(origin: Vector2, direction: Vector2, speed: float, hero_velocity: Vector2) -> void:
	position = origin
	velocity = direction.normalized()*speed+inherited_velocity(hero_velocity)
	age = 0
	trail = PackedVector2Array([origin])

func advance(dt: float) -> void:
	position += velocity*dt+GRAVITY*(dt*dt*.5)
	velocity += GRAVITY*dt
	age += dt
	trail.append(position)
	if trail.size()>15: trail.remove_at(0)

static func range_fraction(from: Vector2, to: Vector2, hero: Vector2, maximum: float) -> float:
	var offset := from-hero
	if offset.length_squared()>maximum*maximum+.0001: return 0.0
	if to.distance_squared_to(hero)<=maximum*maximum: return 1.0
	var delta := to-from
	var a := delta.length_squared()
	if a<.000001: return 0.0
	var b := offset.dot(delta)
	return clampf((-b+sqrt(maxf(0,b*b-a*(offset.length_squared()-maximum*maximum))))/a,0,1)

static func aim_solution(origin: Vector2, target: Vector2, speed: float, hero_velocity: Vector2) -> Dictionary:
	var offset := target-origin
	if offset.length_squared()<.000001: return {"direction":Vector2.UP,"time":0.0}
	var inherited := inherited_velocity(hero_velocity)
	var low := .0001
	# First root is the fast, shallow arc. No homing or mid-flight steering.
	for index in range(1,401):
		var high := index*.005
		var required := offset/high-GRAVITY*high*.5-inherited
		if required.length()<=speed:
			for iteration in range(16):
				var middle := (low+high)*.5
				if (offset/middle-GRAVITY*middle*.5-inherited).length()>speed:
					low = middle
				else:
					high = middle
			return {"direction":(offset/high-GRAVITY*high*.5-inherited).normalized(),"time":high}
		low = high
	return {"direction":offset.normalized(),"time":offset.length()/speed}
