class_name RopeSim
extends RefCounted

const MIN_LENGTH := 2.0
const MAX_SPEED := 18.0
const AIR_DRAG := .42
const TANGENTIAL_DRAG := .16
const MAX_REEL_SPEED := 4.5
const REEL_ACCELERATION := 18.0

var pos := Vector2(0, 1.1)
var vel := Vector2.ZERO
var anchor := Vector2.ZERO
var attached := false
var length := 4.0
var target_length := 4.0
var maximum_length := 5.5
var swing_force := 11.5
var reel_in_speed := 3.0
var reel_out_speed := 3.0
var reel_velocity := 0.0
var fall_speed_limit := 8.0
var flight_peak := 1.1
var highest := 1.1
var launched := false
var grounded := true
var gravity := 14.0
var pump_input := 0.0
var rope_pivots: Array[Vector2] = [] # From the root anchor toward the player.

func effective_anchor() -> Vector2:
	return rope_pivots[-1] if not rope_pivots.is_empty() else anchor

func fixed_length() -> float:
	var total := 0.0
	var previous := anchor
	for point in rope_pivots:
		total += previous.distance_to(point)
		previous = point
	return total

func path_distance() -> float:
	return fixed_length()+pos.distance_to(effective_anchor())

func constrain_rope() -> void:
	if not attached: return
	var pivot := effective_anchor()
	var offset := pos-pivot
	var available := maxf(.35,length-fixed_length())
	if offset.length()>available:
		var radial := offset.normalized()
		pos = pivot+radial*available
		vel -= radial*maxf(0,vel.dot(radial))

func attach(point: Vector2, maximum: float, take_up: bool = false) -> void:
	rope_pivots.clear()
	anchor = point
	pump_input = 0
	maximum_length = maximum
	length = clampf(pos.distance_to(anchor), MIN_LENGTH, maximum_length)
	target_length = length
	reel_velocity = 0
	if take_up: length = minf(maximum_length,length+.18)
	attached = true
	grounded = false
	launched = true
	var radial := (pos - anchor).normalized()
	if not take_up:
		vel -= radial * maxf(0, vel.dot(radial))
		vel *= .96
		if vel.length_squared() < .7:
			vel += Vector2(-radial.y, radial.x) * 1.4
	flight_peak = maxf(flight_peak,pos.y)

func release(factor: float) -> void:
	if not attached:
		return
	attached = false
	reel_velocity = 0
	rope_pivots.clear()
	# Keep the velocity vector intact at the hand-off. The smoother constraint
	# and radial reel velocity already remove the old snap without hiding the
	# timing skill in a release impulse.
	vel = (vel * factor).limit_length(MAX_SPEED)
	flight_peak = maxf(flight_peak,pos.y)

func tick(dt: float, pump: float, reel: float) -> void:
	var acceleration := Vector2(0, -gravity)
	pump_input = move_toward(pump_input,pump,dt*10)
	var previous_length := length
	if attached:
		var radial := (pos-effective_anchor()).normalized()
		var tangent := Vector2(-radial.y,radial.x)
		var force := Vector2(pump_input*swing_force, 0)
		# Only the component along the orbit can change the swing. A small
		# velocity drag keeps repeated corrections smooth instead of twitchy.
		acceleration += force - radial * force.dot(radial)
		acceleration -= tangent * vel.dot(tangent) * TANGENTIAL_DRAG
		if absf(reel)>.001:
			request_length(target_length-reel*(reel_in_speed if reel>0 else reel_out_speed)*dt)
		var error := target_length-length
		var desired_speed := signf(error)*minf(reel_in_speed if error<0 else reel_out_speed,sqrt(2*REEL_ACCELERATION*absf(error)))
		reel_velocity = move_toward(reel_velocity,desired_speed,REEL_ACCELERATION*dt)
		var advance := reel_velocity*dt
		if advance*error>0 and absf(advance)>=absf(error):
			length = target_length
			reel_velocity = 0
		else:
			length += advance
		var legal_length := clampf(length,minf(maximum_length,maxf(MIN_LENGTH,fixed_length()+.6)),maximum_length)
		if absf(legal_length-length)>.00001: reel_velocity = 0
		length = legal_length
	vel += acceleration * dt
	vel *= exp(-AIR_DRAG*dt)
	# Changing the length follows the current radial direction. Without this
	# term, shortening the rope leaves the body one frame behind the constraint
	# and creates a visible pop at the end of every reel gesture.
	if attached and absf(length-previous_length)>.00001 and pos.distance_to(effective_anchor())>=previous_length-fixed_length()-.025:
		var offset := pos-effective_anchor()
		if offset.length_squared()>.0001:
			var radial := offset.normalized()
			var reel_speed := clampf((length-previous_length)/maxf(dt,.0001),-MAX_REEL_SPEED,MAX_REEL_SPEED)
			var tangent_velocity := vel-radial*vel.dot(radial)
			vel = tangent_velocity+radial*reel_speed
	vel = vel.limit_length(MAX_SPEED)
	if not attached:
		vel.y = maxf(vel.y,-fall_speed_limit)
	pos += vel * dt
	constrain_rope()
	flight_peak = maxf(flight_peak, pos.y)
	highest = maxf(highest, pos.y)

func request_length(value: float) -> void:
	target_length = clampf(value,minf(maximum_length,maxf(MIN_LENGTH,fixed_length()+.6)),maximum_length)

func fallen() -> float:
	return maxf(0, flight_peak-pos.y)

func land(top: float) -> void:
	pos.y = top+.48
	vel = Vector2(vel.x*.78, 0)
	grounded = true
	flight_peak = maxf(flight_peak,pos.y)

static func hit_circle(from: Vector2, to: Vector2, center: Vector2, radius: float) -> float:
	var delta := to-from
	var squared := delta.length_squared()
	if squared < .000001:
		return 0.0 if from.distance_to(center) <= radius else -1.0
	var b := (from-center).dot(delta)
	var c := (from-center).length_squared()-radius*radius
	if c <= 0:
		return 0
	var discriminant := b*b-squared*c
	if discriminant < 0:
		return -1
	var fraction := (-b-sqrt(discriminant))/squared
	return fraction if fraction >= 0 and fraction <= 1 else -1

static func hit_polygon(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(from,polygon):
		return 0.0
	var direction := to-from
	var best := 2.0
	for index in range(polygon.size()):
		var a := polygon[index]
		var edge := polygon[(index+1)%polygon.size()]-a
		var denominator := direction.cross(edge)
		if absf(denominator)<.000001:
			continue
		var relative := a-from
		var t := relative.cross(edge)/denominator
		var u := relative.cross(direction)/denominator
		if t>=0 and t<=1 and u>=0 and u<=1:
			best = minf(best,t)
	return best if best<=1 else -1.0

static func hit_capsule(from: Vector2, to: Vector2, a: Vector2, b: Vector2, radius: float) -> float:
	var normal := (b-a).normalized().orthogonal()*radius
	var best := 2.0
	for fraction in [hit_circle(from,to,a,radius),hit_circle(from,to,b,radius),hit_polygon(from,to,PackedVector2Array([a+normal,b+normal,b-normal,a-normal]))]:
		if fraction>=0:
			best = minf(best,fraction)
	return best if best<=1 else -1.0
