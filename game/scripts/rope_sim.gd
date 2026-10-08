class_name RopeSim
extends RefCounted

const MIN_LENGTH := 2.0

var pos := Vector2(0, 1.1)
var vel := Vector2.ZERO
var anchor := Vector2.ZERO
var attached := false
var length := 4.0
var target_length := 4.0
var maximum_length := 5.5
var adjust_speed := 3.0
var fall_speed_limit := 8.0
var flight_peak := 1.1
var highest := 1.1
var launched := false
var grounded := true
var gravity := 14.0
var pump_input := 0.0

func attach(point: Vector2, maximum: float) -> void:
	anchor = point
	maximum_length = maximum
	length = clampf(pos.distance_to(anchor), MIN_LENGTH, maximum_length)
	target_length = length
	attached = true
	grounded = false
	launched = true
	var radial := (pos - anchor).normalized()
	vel -= radial * maxf(0, vel.dot(radial))
	vel *= .96
	if vel.length_squared() < .7:
		vel += Vector2(-radial.y, radial.x) * 1.4
	flight_peak = maxf(flight_peak,pos.y)

func release(factor: float) -> void:
	if not attached:
		return
	attached = false
	vel = (vel * factor).limit_length(18)
	flight_peak = maxf(flight_peak,pos.y)

func tick(dt: float, pump: float, reel: float) -> void:
	var acceleration := Vector2(0, -gravity)
	pump_input = move_toward(pump_input,pump,dt*10)
	if attached:
		var radial := (pos-anchor).normalized()
		var force := Vector2(pump_input*10, 0)
		acceleration += force - radial * force.dot(radial)
		if absf(reel)>.001:
			request_length(target_length-reel*adjust_speed*dt)
		length = move_toward(length,target_length,adjust_speed*dt)
	vel += acceleration * dt
	vel *= exp(-.065*dt)
	vel = vel.limit_length(18)
	if not attached:
		vel.y = maxf(vel.y,-fall_speed_limit)
	pos += vel * dt
	if attached:
		var offset := pos-anchor
		var distance := offset.length()
		if distance > length and distance > .001:
			var radial := offset / distance
			pos = anchor + radial*length
			vel -= radial*maxf(0, vel.dot(radial))
	flight_peak = maxf(flight_peak, pos.y)
	highest = maxf(highest, pos.y)

func request_length(value: float) -> void:
	target_length = clampf(value,MIN_LENGTH,maximum_length)

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
