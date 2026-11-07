class_name HeroPrototypePoses
extends RefCounted

# Poses and the short throw used to judge the stage 2 slice (torso, near arm,
# head). Angles are radians relative to the rest pose, counter-clockwise for a
# hero looking right: + on the shoulder raises the arm forward and up, + on the
# elbow folds the forearm, - on the chest leans forward. Stage 3 replaces this
# with AnimationTree clips.

const NEUTRAL := {"shoulder_near":.10,"elbow_near":.30,"hand_near":.10}
# Throw wind-up: arm up behind the head, forearm folded back, body leaning back.
const WIND_UP := {"shoulder_near":3.15,"elbow_near":1.55,"hand_near":.35,"spine":.06,"chest":.12,"head":.10}
# Release: the arm whips forward along the throw, nearly straight.
const RELEASE := {"shoulder_near":1.75,"elbow_near":.30,"hand_near":-.15,"spine":-.04,"chest":-.12,"head":-.04}
# Follow-through: the arm goes past the line, the body turns into the throw.
const FOLLOW := {"shoulder_near":.85,"elbow_near":.15,"hand_near":-.25,"spine":-.08,"chest":-.22,"head":-.12}
# The hardest bend for the sleeve: elbow folded beyond 130 degrees.
const DEEP_ELBOW := {"shoulder_near":1.30,"elbow_near":2.35,"hand_near":.20}
const POSES := {"neutral":NEUTRAL,"wind_up":WIND_UP,"release":RELEASE,"follow":FOLLOW,"deep_elbow":DEEP_ELBOW}

const THROW_TIME := .9
# [time, pose, arm drawn behind the head]; the arm passes behind the head in
# the wind-up and comes out in front of it for the release.
const THROW_KEYS := [[0.0,NEUTRAL,false],[.28,WIND_UP,true],[.40,RELEASE,false],[.52,FOLLOW,false],[.9,NEUTRAL,false]]
# The head and the forearm lag the shoulder a little (overlapping action).
const HEAD_LAG := .05
const FOREARM_LAG := .025

static func sample(keys: Array, time: float) -> Dictionary:
	time = clampf(time,0,keys[-1][0])
	for index in range(keys.size()-1):
		var a: Array = keys[index]
		var b: Array = keys[index+1]
		if time<=b[0]:
			var t := smoothstep(0.0,1.0,(time-a[0])/maxf(.0001,b[0]-a[0]))
			var result := {}
			for bone in (a[1] as Dictionary).keys()+(b[1] as Dictionary).keys():
				result[bone] = lerpf(float(a[1].get(bone,0.0)),float(b[1].get(bone,0.0)),t)
			return result
	return keys[-1][1]

# Pose of the throw at `time` seconds into the loop.
static func throw_pose(time: float) -> Dictionary:
	time = fmod(time,THROW_TIME)
	var pose := sample(THROW_KEYS,time)
	pose["head"] = sample(THROW_KEYS,time-HEAD_LAG).get("head",0.0)
	pose["elbow_near"] = sample(THROW_KEYS,time-FOREARM_LAG).get("elbow_near",0.0)
	return pose

static func arm_behind_head(time: float) -> bool:
	time = fmod(time,THROW_TIME)
	return time>.12 and time<.36

# Whole-body poses. + on a hip swings the leg forward, - on a knee folds the
# shin back, + on a foot lifts the toe; far limbs take the same signs.
const STAND := {"shoulder_near":.10,"elbow_near":.30,"hand_near":.10,"shoulder_far":-.05,"elbow_far":.25,
	"hip_near":.06,"knee_near":-.04,"hip_far":-.06,"knee_far":-.04}
# Hanging on the rope: near arm straight up to the grip, the far arm and the
# legs dangle a little apart.
const HANG := {"shoulder_near":2.55,"elbow_near":.15,"hand_near":.10,"shoulder_far":.35,"elbow_far":.55,
	"hip_near":.30,"knee_near":-.45,"foot_near":.20,"hip_far":-.10,"knee_far":-.25,"foot_far":.10,"chest":.05,"head":.08}
# Hard landing: deep knee bend, body folds forward, arms out for balance.
const LAND := {"hip_near":1.05,"knee_near":-1.75,"foot_near":.70,"hip_far":.85,"knee_far":-1.55,"foot_far":.70,
	"spine":-.25,"chest":-.15,"head":.25,"shoulder_near":.70,"elbow_near":.60,"shoulder_far":.45,"elbow_far":.70}
const BODY_POSES := {"stand":STAND,"hang":HANG,"land":LAND,"release":RELEASE}

const WALK_TIME := .8
# Walk cycle at `time` seconds: legs swing opposite, the swinging shin folds
# back to clear the ground, arms swing against the legs.
static func walk_pose(time: float) -> Dictionary:
	var phase := fmod(time,WALK_TIME)/WALK_TIME*TAU
	var swing := sin(phase)
	var pose := {"spine":-.04,"head":.02}
	for side in ["near","far"]:
		var s := swing if side=="near" else -swing
		var lift := maxf(0.0,cos(phase if side=="near" else phase+PI))
		pose["hip_"+side] = .42*s
		pose["knee_"+side] = -.15-.75*lift
		pose["foot_"+side] = .25*lift-.1*s
		pose["shoulder_"+side] = -.32*s
		pose["elbow_"+side] = .35+.15*maxf(0.0,s)
	return pose
