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
# The spring used to scale the whole velocity by 1.13. It now adds the same
# share of speed along its exit direction, weighted by how well the swing
# loads the bough in that direction.
const SPRING_BONUS := .13
# Ice: the contact starts at the old .18 m/s and accelerates down the grip's
# surface, never further than 1.2 m and never off the drawn stone. Releasing
# while it slides carries that motion into the flight.
const ICE_SLIDE_RATE := .18
const ICE_SLIDE_ACCEL := .9
const ICE_SLIDE_MAX := 1.2
const ICE_CARRY := 1.0
# Distance the spring's throw must keep clear of rock, in its exit direction.
const SPRING_LANE := 2.4

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
	return network_kind(kind_of(object)) and not object.get("reserve",false) and role(object)!="reward"

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

static func slide_offset(object: Dictionary, held: float) -> Vector2:
	return slide_direction(object)*slide_distance(object,held)

# Every contact position an ice grip can reach, for route validation.
static func slide_samples(object: Dictionary, count: int = 3) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var steps := maxi(1,count-1) if kind_of(object)==ICE else 0
	for step in range(steps+1):
		result.append(object["pos"]+slide_direction(object)*ICE_SLIDE_MAX*(float(step)/maxf(1,steps)))
	return result

static func exit_direction(object: Dictionary) -> Vector2:
	var direction: Vector2 = object.get("exit_dir",Vector2.UP)
	return direction.normalized() if direction.length_squared()>.0001 else Vector2.UP

# How much of the spring's bonus a release at this velocity collects.
static func spring_load(object: Dictionary, velocity: Vector2) -> float:
	if kind_of(object)!=SPRING or velocity.length_squared()<.0001: return 0.0
	return clampf(velocity.normalized().dot(exit_direction(object)),0,1)

static func release_velocity(object: Dictionary, velocity: Vector2, slide_velocity: Vector2 = Vector2.ZERO) -> Vector2:
	if kind_of(object)==ICE: return velocity+slide_velocity*ICE_CARRY
	var load := spring_load(object,velocity)
	if load<=0: return velocity
	return velocity+exit_direction(object)*velocity.length()*SPRING_BONUS*load

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
