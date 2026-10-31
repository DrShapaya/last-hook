class_name GripSpec
extends RefCounted

# One contract for every grip, kept apart from how it looks:
#   type      - what the grip does (the numeric `kind` 0-4 stays the stored id,
#               so attempts and seeds from older versions regenerate unchanged);
#   lifetime  - disposable, permanent or reserve (from the existing flags);
#   role      - why the grip stands where it is in the route graph;
#   params    - the mechanic's own data (exit direction, slide, choice exits).
# Gameplay code asks this table instead of testing `kind==1` in several files.

enum {STONE, ROOT, SPRING, ICE, CRYSTAL}
const TYPES := ["stable","timed","spring","sliding","crystal_choice"]
const LIFETIMES := ["disposable","permanent","reserve"]
const ROLES := ["main","tutorial","branch","recovery","rest","reward","auxiliary"]

# Existing tuning gathered in one place; values are unchanged.
const ROOT_SECONDS := 2.6
const ROOT_WARNING := 2.1
# A spring throws the hero straight up at a fixed speed, even from a still
# hang: thrown towards the next grip, the hero left the mountain. A rising
# swing adds up to SPRING_TIMING of that speed, and most sideways speed is lost.
const SPRING_THROW := 11.0
const SPRING_TIMING := .2
const SPRING_FULL_SWING := 6.0
const SPRING_KEEP_SIDEWAYS := .25
# Ice: the contact starts at the old .18 m/s and accelerates down the grip's
# surface, never further than 1.2 m and never off the drawn stone. Releasing
# while it slides carries that motion into the flight.
const ICE_SLIDE_RATE := .18
const ICE_SLIDE_ACCEL := .9
const ICE_SLIDE_MAX := 1.2
const ICE_CARRY := 1.5
# Ice is a plate leaning along its slide. The hook hangs under it, so it holds
# for a moment and then runs down the lower edge and off the low end, about
# as long a hold as a root gives from the high end.
const ICE_GRACE := .9
const ICE_PLATE_ACCEL := .45
const ICE_LOWER_EDGE := .15
# Distance the spring's throw must keep clear of rock, in its exit direction.
const SPRING_LANE := 2.4
# Mask levels are drawn for the full throw; older worlds keep the short lane,
# so saved attempts regenerate unchanged.
const SPRING_THROW_LANE := 4.5

static func kind_of(object: Dictionary) -> int:
	return clampi(int(object.get("kind",STONE)),STONE,CRYSTAL)

static func type_of(object: Dictionary) -> String:
	return TYPES[kind_of(object)]

static func lifetime(object: Dictionary) -> String:
	if object.get("reserve",false): return "reserve"
	return "permanent" if object.get("permanent",true) else "disposable"

static func role(object: Dictionary) -> String:
	if object.has("role"): return str(object["role"])
	if object.get("reserve",false): return "recovery"
	return "main" if object.get("primary",false) else "auxiliary"

# Types the base kit can always use as a link: no timer, no slide, no choice.
static func network_kind(kind: int) -> bool:
	return kind==STONE or kind==SPRING

# The stable network excludes reserves and reward grips: a reward grip is
# reached only through its choice crystal and leaves forward on its own.
static func in_network(object: Dictionary) -> bool:
	return (network_kind(kind_of(object)) or fork(object)) and not object.get("reserve",false) and role(object)!="reward"

# A crystal on the main route where a level parts into two ways: it holds
# like stone, and both ways leave from it.
static func fork(object: Dictionary) -> bool:
	return kind_of(object)==CRYSTAL and object.has("fork")

static func timed(object: Dictionary) -> bool:
	return kind_of(object)==ROOT

static func seconds_left(object: Dictionary, held: float) -> float:
	return maxf(0,ROOT_SECONDS-held) if timed(object) else INF

static func expired(object: Dictionary, held: float) -> bool:
	return timed(object) and held>ROOT_SECONDS

static func warning(object: Dictionary, held: float) -> bool:
	return timed(object) and held>ROOT_WARNING

# Ice: the contact slides over the grip surface along its local downslope.
static func slide_direction(object: Dictionary) -> Vector2:
	var direction: Vector2 = object.get("slide_dir",Vector2.DOWN)
	return direction.normalized() if direction.length_squared()>.0001 else Vector2.DOWN

# v13 ice slides across its grip towards one side, slightly downhill, so the
# hook really travels over the stone instead of pressing into its underside.
static func lateral_slide(side: float) -> Vector2:
	return Vector2(1.0 if side>=0 else -1.0,-.35).normalized()

static func slide_distance(object: Dictionary, held: float) -> float:
	if kind_of(object)!=ICE or held<=0: return 0.0
	return minf(ICE_SLIDE_MAX,held*ICE_SLIDE_RATE+.5*ICE_SLIDE_ACCEL*held*held)

# How far a hook has run down a plate `held` seconds after the plate let go.
static func plate_run(held: float) -> float:
	return held*ICE_SLIDE_RATE+.5*ICE_PLATE_ACCEL*held*held if held>0 else 0.0

# Ice sliding sideways is a leaning plate. Saved worlds from before v13 slide
# straight down and keep walking their contour.
static func plate(object: Dictionary) -> bool:
	return kind_of(object)==ICE and absf(slide_direction(object).x)>.5

# Lean of the plate: its long axis lies along the slide.
static func plate_tilt(object: Dictionary) -> float:
	if not plate(object): return 0.0
	var direction := slide_direction(object)
	return (direction if direction.x>0 else -direction).angle()

# In the plate's own frame: where the hook hangs on the lower edge, the length
# of edge left before the low end, and the frame's way back to the world.
static func _plate_path(object: Dictionary, contact: Vector2) -> Dictionary:
	var pos: Vector2 = object["pos"]
	var tilt := plate_tilt(object)
	var side := signf(slide_direction(object).rotated(-tilt).x)
	var contour := outline(object)
	var bottom := INF
	for point in contour: bottom = minf(bottom,(point-pos).rotated(-tilt).y)
	var low_end := -INF
	for point in contour:
		var local := (point-pos).rotated(-tilt)
		if local.y<=bottom+ICE_LOWER_EDGE: low_end = maxf(low_end,local.x*side)
	var at := (contact-pos).rotated(-tilt).x
	return {"start":pos+Vector2(at,bottom).rotated(tilt),"left":maxf(0,low_end-at*side)}

static func slipped(object: Dictionary, contact: Vector2, held: float) -> bool:
	return plate(object) and held>=seconds_to_slip(object,contact)

# How long the plate holds a hook caught at `contact`.
static func seconds_to_slip(object: Dictionary, contact: Vector2) -> float:
	if not plate(object): return INF
	var left: float = _plate_path(object,contact)["left"]
	return ICE_GRACE+(sqrt(ICE_SLIDE_RATE*ICE_SLIDE_RATE+2*ICE_PLATE_ACCEL*left)-ICE_SLIDE_RATE)/ICE_PLATE_ACCEL

static func slide_offset(object: Dictionary, held: float) -> Vector2:
	return slide_direction(object)*slide_distance(object,held)

# Every contact position an ice grip can reach, for route validation.
static func slide_samples(object: Dictionary, count: int = 3) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var steps := maxi(1,count-1) if kind_of(object)==ICE else 0
	for step in range(steps+1):
		result.append(object["pos"]+slide_direction(object)*ICE_SLIDE_MAX*(float(step)/maxf(1,steps)))
	return result

# --- Contact geometry on the drawn stone ----------------------------------------
# Shared by the running game (MountainWorld) and the route audit (RouteGraph).

static func outline(object: Dictionary) -> PackedVector2Array:
	var pos: Vector2 = object["pos"]
	var result := PackedVector2Array()
	if object.has("surface") or object.has("polygon"):
		var tilt := plate_tilt(object)
		for point in object["surface"] if object.has("surface") else object["polygon"]: result.append(point.rotated(tilt)+pos)
	else:
		var half: Vector2 = object["dimensions"]*.5
		result = PackedVector2Array([pos-half,pos+Vector2(half.x,-half.y),pos+half,pos+Vector2(-half.x,half.y)])
	return result

# Moves a point onto the visible grip surface: along the shot direction when
# it still meets the stone, otherwise to the nearest point of the contour.
static func surface_point(object: Dictionary, point: Vector2, direction: Vector2 = Vector2.ZERO) -> Vector2:
	var contour := outline(object)
	if contour.size()<3 or Geometry2D.is_point_in_polygon(point,contour): return point
	var best := contour[0]
	for index in range(contour.size()):
		var closest := Geometry2D.get_closest_point_to_segment(point,contour[index],contour[(index+1)%contour.size()])
		if closest.distance_squared_to(point)<best.distance_squared_to(point): best = closest
	if direction.length_squared()>.000001:
		# A grazing ray may meet the stone far along its path; then the nearest
		# point reads better than a hook sliding across the face.
		var limit := point.distance_to(best)*2+.05
		var reach := point+direction.normalized()*limit
		var fraction := RopeSim.hit_polygon(point,reach,contour)
		if fraction>=0: return point.lerp(reach,fraction)
	return best

# Contact after holding for `held` seconds: ice walks the hook along the drawn
# contour in its slide direction, never uphill, and stops in the lowest corner
# it reaches; every other type keeps the contact. The walk is continuous, so
# the hook can neither jump across a thin grip nor leave the stone.
static func contact_after(object: Dictionary, contact: Vector2, held: float) -> Vector2:
	if plate(object):
		var path := _plate_path(object,contact)
		if held<ICE_GRACE: return contact.lerp(path["start"],maxf(0,held)/ICE_GRACE)
		return path["start"]+slide_direction(object)*minf(path["left"],plate_run(held-ICE_GRACE))
	var remaining := slide_distance(object,held)
	if remaining<=0: return contact
	var contour := outline(object)
	if contour.size()<3: return contact
	var direction := slide_direction(object)
	var count := contour.size()
	var point := surface_point(object,contact)
	var segment := 0
	var best := INF
	for index in range(count):
		var closest := Geometry2D.get_closest_point_to_segment(point,contour[index],contour[(index+1)%count])
		if closest.distance_squared_to(point)<best:
			best = closest.distance_squared_to(point)
			segment = index
	# Walk towards whichever end of the segment lies down the slide.
	var a := contour[segment]
	var b := contour[(segment+1)%count]
	var step := 1 if (b-a).dot(direction)>=(a-b).dot(direction) else -1
	var target := (segment+1)%count if step>0 else segment
	for guard in range(count+1):
		var leg := contour[target]-point
		if leg.length_squared()<.000001:
			target = posmod(target+step,count)
			continue
		var heading := leg.normalized()
		if heading.dot(direction)<=0 or heading.y>.05: break
		if leg.length()>=remaining: return point+heading*remaining
		remaining -= leg.length()
		point = contour[target]
		target = posmod(target+step,count)
	return point

# Every contact an ice grip can really give the hook, for the route audit:
# each landing spot on the drawn stone (corners and edge midpoints) and where
# the full slide carries it from there. Generation keeps `slide_samples`, so
# saved attempts regenerate unchanged.
static func slide_contacts(object: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var contour := outline(object)
	var full_slide := 10.0 # seconds; well past ICE_SLIDE_MAX
	for index in range(contour.size()):
		for landing in [contour[index],(contour[index]+contour[(index+1)%contour.size()])*.5]:
			result.append(landing)
			result.append(contact_after(object,landing,full_slide))
	return result

# World heights grow upwards, so Godot's Vector2.UP would point down the mountain.
const MOUNTAIN_UP := Vector2(0,1)

static func exit_direction(object: Dictionary) -> Vector2:
	var direction: Vector2 = object.get("exit_dir",MOUNTAIN_UP)
	return direction.normalized() if direction.length_squared()>.0001 else MOUNTAIN_UP

# How much of the spring's timing bonus a release at this velocity collects.
static func spring_load(object: Dictionary, velocity: Vector2) -> float:
	if kind_of(object)!=SPRING or velocity.length_squared()<.0001: return 0.0
	return clampf(velocity.y/SPRING_FULL_SWING,0,1)

static func release_velocity(object: Dictionary, velocity: Vector2, slide_velocity: Vector2 = Vector2.ZERO) -> Vector2:
	if kind_of(object)==ICE: return velocity+slide_velocity*ICE_CARRY
	if kind_of(object)!=SPRING: return velocity
	var throw := SPRING_THROW*(1+SPRING_TIMING*spring_load(object,velocity))
	return Vector2(velocity.x*SPRING_KEEP_SIDEWAYS,maxf(velocity.y,throw))

static func choice_exits(object: Dictionary) -> Array:
	return object.get("choice_exits",[]) if kind_of(object)==CRYSTAL else []

# --- State contract -----------------------------------------------------------
# Every type walks the same states:
#   available -> (targeted) -> attached -> acted -> consumed | available
# `consumed` is the stored `broken` flag, so saves and the hook cast keep
# reading one field. `targeted` is derived from the aim and never stored.
# Each transition returns true only when it really happens, so a repeated
# release, a second hit or a resumed run never applies an effect twice.
const STATES := ["available","targeted","attached","acted","consumed"]

static func state(object: Dictionary, aimed_id: int = -1) -> String:
	if object.get("broken",false): return "consumed"
	var stored := str(object.get("grip_state","available"))
	if stored=="available" and aimed_id>=0 and int(object.get("id",-1))==aimed_id: return "targeted"
	return stored

static func attach(object: Dictionary) -> bool:
	if object.is_empty() or object.get("broken",false) or object.get("grip_state","available")=="attached": return false
	object["grip_state"] = "attached"
	return true

# Release: the type's effect (the spring impulse) belongs to this transition.
static func act(object: Dictionary) -> bool:
	if object.is_empty() or object.get("broken",false) or object.get("grip_state","available")!="attached": return false
	object["grip_state"] = "acted"
	return true

# After acting a disposable grip is consumed; a permanent one is free again.
static func settle(object: Dictionary) -> bool:
	if object.is_empty() or object.get("broken",false): return false
	if object.get("permanent",true) and not timed(object):
		object["grip_state"] = "available"
		return false
	object["grip_state"] = "consumed"
	object["broken"] = true
	return true

# A root clock ends the grip whatever its lifetime and wherever it is held.
static func expire(object: Dictionary) -> bool:
	if object.is_empty() or object.get("broken",false): return false
	object["grip_state"] = "consumed"
	object["broken"] = true
	return true

# A reserve woken by a revival, or a held grip restored from a save.
static func restore(object: Dictionary, held: bool) -> void:
	if object.get("broken",false):
		object["grip_state"] = "consumed"
	else:
		object["grip_state"] = "attached" if held else "available"

static func network_safe_point(object: Dictionary) -> bool:
	# Catching a permanent stable main grip records the revival point.
	return network_kind(kind_of(object)) and object.get("permanent",true)

# --- Labels -------------------------------------------------------------------

const LIFETIME_WORDS := {"disposable":{"m":"одноразовый","f":"одноразовая"},"permanent":{"m":"постоянный","f":"постоянная"},"reserve":{"m":"резервный","f":"резервная"}}

static func timer_text(seconds: float) -> String:
	return ("%.1f" % seconds).replace(".",",")

# Two independent parts: what the grip is, and how long it lasts.
static func type_label(object: Dictionary, profile: GripBiomeProfile = null) -> String:
	var used := profile if profile!=null else GripBiomeProfile.named("forest")
	return str(used.type_titles[kind_of(object)][0])

static func lifetime_label(object: Dictionary, profile: GripBiomeProfile = null) -> String:
	var used := profile if profile!=null else GripBiomeProfile.named("forest")
	if timed(object): return timer_text(ROOT_SECONDS)+" с"
	var gender := str(used.type_titles[kind_of(object)][1])
	return str(LIFETIME_WORDS[lifetime(object)][gender])

static func description(object: Dictionary, profile: GripBiomeProfile = null) -> String:
	var parts := PackedStringArray([type_label(object,profile)])
	match kind_of(object):
		ICE: parts.append("скользит")
		CRYSTAL:
			if not choice_exits(object).is_empty(): parts.append("два выхода")
	parts.append(lifetime_label(object,profile))
	return " · ".join(parts)
