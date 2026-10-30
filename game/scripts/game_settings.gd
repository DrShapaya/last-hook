class_name GameSettings
extends RefCounted

# Player settings kept in profile["settings"]. This file only describes them:
# what may be stored, the defaults and the graphics presets. main.gd applies
# them. A value read from a save is never trusted: anything outside the lists
# below falls back to its default, so a hand-edited profile cannot break a run.
const SHADOWS := ["off","medium","high"]
const DETAIL := ["battery","balanced","high"]
const PARTICLES := ["off","reduced","full"]
const RENDER_SCALES := [.6,.75,.85,1.0]
const FPS_LIMITS := [0,60,30]
const TEXT_SCALES := [100,115,130]
const COLOR_SCHEMES := ["normal","red_green","blue_yellow"]
const VOLUME_KEYS := ["master_volume","music_volume","sfx_volume"]
const FLAG_KEYS := ["glow","high_contrast","reduce_effects","persistent_hints"]
const SENSITIVITY_RANGE := [50,150]
const HOLD_RANGE := [.15,.5]
const DEFAULT_HOLD := .28
# What a preset fills in. The fps limit is frame pacing, not workload, so no
# preset touches it.
const PRESETS := {
	"high":{"shadows":"high","decor":"high","sky":"high","particles":"full","glow":true,"render_scale":1.0},
	"balanced":{"shadows":"medium","decor":"balanced","sky":"balanced","particles":"full","glow":true,"render_scale":1.0},
	"battery":{"shadows":"off","decor":"battery","sky":"battery","particles":"reduced","glow":false,"render_scale":.75}
}

static func defaults() -> Dictionary:
	var values: Dictionary = PRESETS["high"].duplicate()
	values.merge({"fps_limit":0,"master_volume":100,"music_volume":100,"sfx_volume":100,"sensitivity":100,"hold_seconds":DEFAULT_HOLD,
		"text_scale":100,"high_contrast":false,"color_scheme":"normal","reduce_effects":false,"persistent_hints":false,"key_bindings":{}})
	return values

# Numbers arrive from JSON as floats; a choice is matched by value.
static func _pick(value: Variant, options: Array, fallback: Variant) -> Variant:
	if value is String or value is StringName:
		return str(value) if str(value) in options else fallback
	if value is float or value is int:
		for option in options:
			if not option is String and is_equal_approx(float(option),float(value)): return option
	return fallback

static func _number(value: Variant, low: float, high: float, step: float, fallback: float) -> float:
	if not (value is float or value is int): return fallback
	var number := float(value)
	if is_nan(number) or number<low-.0001 or number>high+.0001: return fallback
	return number if step<=0.0 else snappedf(number,step)

static func _bindings(value: Variant) -> Dictionary:
	var clean := {}
	if not value is Dictionary: return clean
	for action in value.keys():
		if not str(action) in KeyBindings.ACTIONS or not value[action] is Array: continue
		var keys: Array = []
		for key in value[action]:
			if (key is float or key is int) and int(key)>0: keys.append(int(key))
		clean[str(action)] = keys
	return clean

static func sanitize(source: Variant) -> Dictionary:
	var clean := defaults()
	if not source is Dictionary: return clean
	clean["shadows"] = _pick(source.get("shadows"),SHADOWS,clean["shadows"])
	for key in ["decor","sky"]: clean[key] = _pick(source.get(key),DETAIL,clean[key])
	clean["particles"] = _pick(source.get("particles"),PARTICLES,clean["particles"])
	clean["render_scale"] = _pick(source.get("render_scale"),RENDER_SCALES,clean["render_scale"])
	clean["fps_limit"] = _pick(source.get("fps_limit"),FPS_LIMITS,clean["fps_limit"])
	clean["text_scale"] = _pick(source.get("text_scale"),TEXT_SCALES,clean["text_scale"])
	clean["color_scheme"] = _pick(source.get("color_scheme"),COLOR_SCHEMES,clean["color_scheme"])
	for key in VOLUME_KEYS: clean[key] = roundi(_number(source.get(key),0,100,5,clean[key]))
	clean["sensitivity"] = roundi(_number(source.get("sensitivity"),SENSITIVITY_RANGE[0],SENSITIVITY_RANGE[1],10,clean["sensitivity"]))
	clean["hold_seconds"] = _number(source.get("hold_seconds"),HOLD_RANGE[0],HOLD_RANGE[1],0.0,clean["hold_seconds"])
	for key in FLAG_KEYS:
		if source.get(key) is bool: clean[key] = source[key]
	clean["key_bindings"] = _bindings(source.get("key_bindings"))
	return clean

static func apply_preset(settings: Dictionary, preset: String) -> void:
	if PRESETS.has(preset): settings.merge(PRESETS[preset],true)

static func detect_preset(settings: Dictionary) -> String:
	for preset in PRESETS.keys():
		var matches := true
		for key in PRESETS[preset].keys():
			if settings.get(key)!=PRESETS[preset][key]: matches = false
		if matches: return preset
	return "custom"
