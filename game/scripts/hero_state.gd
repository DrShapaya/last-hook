class_name HeroState
extends RefCounted

# What the hero is doing, decided from events instead of guessed from speed.
#
# Each frame the caller passes what the game already knows (rope attached,
# standing, hook flying, aiming, the shot counter). HeroState turns the changes
# of those flags into events (aim started, thrown, caught, let go, landed) and
# keeps one state with the time spent in it. Speed is used only where the state
# itself is about motion: walking on a ledge and rising versus falling in the air,
# both with hysteresis so the state never flickers.
#
# The animation layer reads `state`, `time_in_state` and the parameters below;
# it never decides the state on its own.

signal state_changed(from: String, to: String)

const IDLE := "idle"
const WALK := "walk"
const AIM := "aim"
const THROW := "throw"
const HOOK_FLIGHT := "hook_flight"
const LATCH := "latch"
const SWING := "swing"
const RELEASE := "release"
const RISE := "rise"
const FALL := "fall"
const LAND := "land"
const SLIP := "slip"
const SUMMIT := "summit"
const REVIVE := "revive"
const STATES := [IDLE,WALK,AIM,THROW,HOOK_FLIGHT,LATCH,SWING,RELEASE,RISE,FALL,LAND,SLIP,SUMMIT,REVIVE]

# Short one-off states; when their time is up the hero returns to the state the
# situation calls for (swing on the rope, walk or idle on a ledge, rise or fall).
const THROW_TIME := .22
const LATCH_TIME := .18
const RELEASE_TIME := .20
const SLIP_TIME := .35
const REVIVE_TIME := .8
const LAND_TIME_SOFT := .16
const LAND_TIME_HARD := .38
# Downward speed at which a landing counts as fully hard.
const HARD_LANDING_SPEED := 8.0
# Walking on a ledge starts above WALK_ENTER and ends below WALK_EXIT.
const WALK_ENTER := .35
const WALK_EXIT := .18
# In the air the hero falls below FALL_ENTER and rises again above FALL_EXIT.
const FALL_ENTER := -.6
const FALL_EXIT := -.1
# Ways a grip can let go on its own (main.gd release reasons).
const SLIP_REASONS := ["root_break","ice_slip","crumble","timeout"]
const HISTORY_SIZE := 64

var state := IDLE
var previous_state := IDLE
var time_in_state := 0.0
# Parameters for the animation layer.
var aim_direction := Vector2.UP
var rope_angle := 0.0 # Angle of the rope from the hero toward the anchor.
var velocity := Vector2.ZERO
var speed := 0.0
var swing_power := 0.0 # RopeSim.pump_input, -1..1.
var reel_speed := 0.0 # Positive while the rope shortens.
var fall_height := 0.0
var land_strength := 0.0 # 0 soft .. 1 hard, set on touchdown.
var falling := false # Air phase under RELEASE/SLIP/RISE/FALL.
# Recent transitions as [from, to, time]; for tests and debugging.
var history: Array = []
var clock := 0.0

var _started := false
var _was_grounded := true
var _was_attached := false
var _was_aiming := false
var _was_tether := false
var _last_shot := -1
var _last_vertical_speed := 0.0
var _last_root_anchor := Vector2.INF
var _hook_flying := false
var _pending: Array[String] = []

# The frame the game hands to update(); built from the same data ExplorerView
# gets from main.gd, so no new wiring is needed in main.gd.
static func observe(sim: RopeSim, tether: bool, flight: Dictionary = {}) -> Dictionary:
	# main.gd aims only while no hook is out, and ExplorerView passes
	# "tether or aiming"; an aim alone is not a rope.
	var aiming := bool(flight.get("aiming",false)) and not sim.attached
	tether = tether and not aiming
	return {
		"grounded":sim.grounded,
		"attached":sim.attached,
		"tether":tether,
		"hook_flying":tether and not sim.attached,
		"aiming":aiming,
		"aim":flight.get("aim",Vector2.UP),
		"shot":int(flight.get("shot",-1)),
		"release_reason":str(flight.get("release_reason","")),
		"velocity":sim.vel,
		"position":sim.pos,
		"anchor":sim.effective_anchor(),
		"root_anchor":sim.anchor,
		"pump":sim.pump_input,
		"reel":-sim.reel_velocity,
		"fallen":sim.fallen(),
	}

# Events the flags cannot show (finish, revive, slip without a reason in the
# frame). They are applied on the next update().
func event(name: String) -> void:
	_pending.append(name)

func reset(to: String = IDLE) -> void:
	state = to
	previous_state = to
	time_in_state = 0.0
	history.clear()
	_pending.clear()
	_started = false

func update(dt: float, frame: Dictionary) -> String:
	clock += dt
	time_in_state += dt
	var grounded: bool = frame.get("grounded",true)
	var attached: bool = frame.get("attached",false)
	var tether: bool = frame.get("tether",attached)
	var aiming: bool = frame.get("aiming",false)
	var shot: int = frame.get("shot",-1)
	velocity = frame.get("velocity",Vector2.ZERO)
	speed = velocity.length()
	swing_power = frame.get("pump",0.0)
	reel_speed = frame.get("reel",0.0)
	fall_height = frame.get("fallen",0.0)
	_hook_flying = frame.get("hook_flying",false)
	var position: Vector2 = frame.get("position",Vector2.ZERO)
	var anchor: Vector2 = frame.get("anchor",position)
	if attached and anchor.distance_squared_to(position)>.0001: rope_angle = (anchor-position).angle()
	var aim: Vector2 = frame.get("aim",Vector2.UP)
	if aim.length_squared()>.0001: aim_direction = aim.normalized()
	# Air phase with hysteresis; kept up to date in every air state.
	if falling: falling = velocity.y<FALL_EXIT
	else: falling = velocity.y<FALL_ENTER
	if not _started:
		# The first frame sets the scene without playing any transition.
		_started = true
		_remember(frame,grounded,attached,aiming,tether,shot)
		_last_root_anchor = frame.get("root_anchor",anchor)
		_enter(_resting_state(grounded,attached),true)
		return state
	# Events from what changed since the last frame, in the order they happen.
	var root_anchor: Vector2 = frame.get("root_anchor",anchor)
	if attached and (not _was_attached or root_anchor.distance_squared_to(_last_root_anchor)>.0025):
		# A new catch, also when the next hook lands straight from the rope.
		_enter(LATCH)
	else:
		if _was_attached and not attached:
			var reason: String = frame.get("release_reason","")
			_enter(SLIP if reason in SLIP_REASONS else RELEASE)
		# Letting go and throwing the next hook can share one frame; the throw wins.
		if (shot>=0 and _last_shot>=0 and shot!=_last_shot) or (tether and not _was_tether and not attached):
			_enter(THROW)
		elif aiming and not _was_aiming:
			_enter(AIM)
	if grounded and not _was_grounded and not attached:
		land_strength = clampf(-_last_vertical_speed/HARD_LANDING_SPEED,0,1)
		_enter(LAND)
	for name in _pending:
		match name:
			"summit": _enter(SUMMIT)
			"revive": _enter(REVIVE)
			"slip": _enter(SLIP)
	_pending.clear()
	_remember(frame,grounded,attached,aiming,tether,shot)
	_last_root_anchor = root_anchor
	# Timed and conditional states end into what the situation calls for.
	var done := false
	match state:
		THROW: done = time_in_state>=THROW_TIME
		LATCH: done = time_in_state>=LATCH_TIME or not attached
		RELEASE: done = time_in_state>=RELEASE_TIME or grounded or attached
		SLIP: done = time_in_state>=SLIP_TIME or grounded or attached
		REVIVE: done = time_in_state>=REVIVE_TIME
		LAND: done = time_in_state>=lerpf(LAND_TIME_SOFT,LAND_TIME_HARD,land_strength) or not grounded
		AIM: done = not aiming
		HOOK_FLIGHT: done = not _hook_flying or attached
		SUMMIT: done = false
		_: done = true
	if done:
		var next := _resting_state(grounded,attached)
		# Aiming and a flying hook outrank resting poses.
		if aiming and not attached: next = AIM
		elif _hook_flying and state!=HOOK_FLIGHT: next = HOOK_FLIGHT
		if next!=state: _enter(next)
	return state

func _resting_state(grounded: bool, attached: bool) -> String:
	if attached: return SWING
	if grounded:
		var moving := absf(velocity.x)>(WALK_EXIT if state==WALK else WALK_ENTER)
		return WALK if moving else IDLE
	return FALL if falling else RISE

func _remember(frame: Dictionary, grounded: bool, attached: bool, aiming: bool, tether: bool, shot: int) -> void:
	_was_grounded = grounded
	_was_attached = attached
	_was_aiming = aiming
	_was_tether = tether
	_last_shot = shot
	_last_vertical_speed = velocity.y

func _enter(next: String, silent: bool = false) -> void:
	if next==state and not next in [THROW,LATCH,LAND,SLIP,RELEASE,REVIVE]: return
	previous_state = state
	state = next
	time_in_state = 0.0
	if silent: return
	history.append([previous_state,next,clock])
	if history.size()>HISTORY_SIZE: history.pop_front()
	state_changed.emit(previous_state,next)

# The pose family the current whole-image sprite can show for this state.
func sprite_pose() -> String:
	match state:
		AIM,THROW,HOOK_FLIGHT: return "throw"
		LATCH,SWING: return "swing"
		RELEASE,RISE,SLIP: return "fall" if falling else "flight"
		FALL: return "fall"
		LAND: return "land"
		WALK: return "walk"
	return "idle"
