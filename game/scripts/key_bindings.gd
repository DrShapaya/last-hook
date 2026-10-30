class_name KeyBindings
extends RefCounted

# Keyboard actions of the climb. Saved bindings hold only the actions the
# player changed; the left mouse button and Esc are not rebindable.
const ACTIONS := ["swing_left","swing_right","rope_up","rope_down","release","item_1","item_2"]
const DEFAULTS := {"swing_left":[KEY_A,KEY_LEFT],"swing_right":[KEY_D,KEY_RIGHT],"rope_up":[KEY_W,KEY_UP],"rope_down":[KEY_S,KEY_DOWN],
	"release":[KEY_SPACE],"item_1":[KEY_1],"item_2":[KEY_2]}
const NAMES := {"swing_left":"Раскачка влево","swing_right":"Раскачка вправо","rope_up":"Смотать канат","rope_down":"Размотать канат",
	"release":"Отцепиться","item_1":"Предмет 1","item_2":"Предмет 2"}
const RESERVED := [KEY_ESCAPE]

static func keys_of(bindings: Dictionary, action: String) -> Array:
	return bindings.get(action,DEFAULTS[action])

static func apply(bindings: Dictionary) -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for key in keys_of(bindings,action):
			var event := InputEventKey.new()
			event.physical_keycode = int(key)
			InputMap.action_add_event(action,event)

# A key belongs to one action: taking it leaves the other action without it,
# and that action says so on the screen instead of quietly swapping keys. The
# release is the one exception: on a keyboard nothing else lets go of a grip,
# so its last key cannot be taken.
static func rebind(bindings: Dictionary, action: String, keycode: int) -> Dictionary:
	if keycode in RESERVED or not action in ACTIONS: return bindings
	if action!="release" and keys_of(bindings,"release")==[keycode]: return bindings
	var result := {}
	for other in ACTIONS:
		var keys: Array = keys_of(bindings,other).duplicate()
		if other==action: keys = [keycode]
		elif keycode in keys: keys.erase(keycode)
		elif not bindings.has(other): continue
		result[other] = keys
	return result

# Named by the Latin layout: the same key reads the same on every keyboard.
static func key_name(key: int) -> String:
	return OS.get_keycode_string(key)

static func key_text(bindings: Dictionary, action: String) -> String:
	var keys := keys_of(bindings,action)
	if keys.is_empty(): return "Нет клавиши"
	return " / ".join(keys.map(func(key): return key_name(int(key))))

# The first key alone, for a line of text.
static func short_text(bindings: Dictionary, action: String) -> String:
	var keys := keys_of(bindings,action)
	return key_name(int(keys[0])) if not keys.is_empty() else "Нет клавиши"
