class_name Haptics
extends Node

# Vibration as a small vocabulary: each game event has its own pattern, so a
# catch, a spring and a fall feel different. A pattern is a list of pulses
# [start ms, length ms, strength 0..1]. Phones vibrate, gamepads rumble.
# Pulses shorter than about 15 ms cannot be felt on most phone motors.

const PATTERNS := {
	"tap":[[0,15,.2]],
	"focus":[[0,16,.2]],
	"catch":[[0,24,.4]],
	"coin":[[0,15,.18]],
	"pickup":[[0,22,.35],[70,30,.5]],
	"rock":[[0,18,.3]],
	"land":[[0,30,.45]],
	"spring":[[0,20,.4],[50,60,.8]],
	"item":[[0,40,.5]],
	"knock":[[0,70,1.0]],
	"fail":[[0,90,1.0],[150,60,.5],[260,40,.25]],
	"win":[[0,40,.5],[110,40,.65],[220,110,1.0]],
	"revive":[[0,30,.4],[90,50,.7]]}
# A new pulse would cut the running one short, so the light events wait.
const MIN_GAP := .06
const HEAVY := ["spring","knock","fail","win","revive"]

var enabled := true
var clock := 0.0
var busy_until := 0.0
var pulses := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	clock += delta

func play(pattern: String) -> bool:
	if not enabled or not PATTERNS.has(pattern): return false
	if clock<busy_until and pattern not in HEAVY: return false
	var steps: Array = PATTERNS[pattern]
	var last: Array = steps[-1]
	busy_until = clock+(float(last[0])+float(last[1]))*.001+MIN_GAP
	for step in steps:
		if int(step[0])==0: _pulse(int(step[1]),float(step[2]))
		else: get_tree().create_timer(int(step[0])*.001,true,false,true).timeout.connect(_pulse.bind(int(step[1]),float(step[2])))
	return true

func _pulse(duration_ms: int, strength: float) -> void:
	pulses += 1
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms,strength)
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device,strength,strength*.6,duration_ms*.001)
