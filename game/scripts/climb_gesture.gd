class_name ClimbGesture
extends RefCounted

# Floating stick in logical UI pixels. Time is sampled every physics frame,
# so a stationary vertical hold works without new drag events.
const DEAD_ZONE := 9.0
const AIM_DEAD_ZONE := 12.0
const STICK_RADIUS := 82.0
const REEL_EXTENT := 118.0
const VERTICAL_MIN_DISTANCE := 24.0
const VERTICAL_HOLD_SECONDS := .28
const VERTICAL_ENTER_SLOPE := .267949 # 15 degrees from vertical.
const VERTICAL_EXIT_SLOPE := .404026 # 22 degrees; avoids boundary chatter.

var origin := Vector2.ZERO
var offset := Vector2.ZERO
var vertical_direction := 0
var vertical_since := -1.0
var last_time := 0.0

func begin(point: Vector2, time: float, scale: float) -> void:
	origin = point/maxf(.1,scale)
	offset = Vector2.ZERO
	vertical_direction = 0
	vertical_since = -1
	last_time = time

func reset() -> void:
	begin(Vector2.ZERO,0,1)

static func axis(value: float, extent: float) -> float:
	return signf(value)*clampf((absf(value)-DEAD_ZONE)/(extent-DEAD_ZONE),0,1)

func move(point: Vector2, time: float, scale: float) -> Dictionary:
	offset = point/maxf(.1,scale)-origin
	return sample(time)

func sample(time: float) -> Dictionary:
	last_time = maxf(last_time,time)
	var direction := int(signf(-offset.y))
	var slope := VERTICAL_EXIT_SLOPE if vertical_direction==direction and direction!=0 else VERTICAL_ENTER_SLOPE
	var vertical := absf(offset.y)>=VERTICAL_MIN_DISTANCE and absf(offset.x)<=absf(offset.y)*slope
	if not vertical:
		vertical_direction = 0
		vertical_since = -1
	elif vertical_direction!=direction:
		vertical_direction = direction
		vertical_since = last_time
	var progress := clampf((last_time-vertical_since)/VERTICAL_HOLD_SECONDS,0,1) if vertical_direction!=0 else 0.0
	return {
		"pump":0.0 if vertical_direction!=0 else axis(offset.x,STICK_RADIUS),
		"reel":axis(-offset.y,REEL_EXTENT) if progress>=1 else 0.0,
		"vertical_direction":vertical_direction,
		"vertical_progress":progress
	}
