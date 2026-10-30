class_name GameModel
extends RefCounted

const THROW := "throw"
const SWING := "swing"
const IMPULSE := "impulse"
const ROPE := "rope"
const REEL_IN := "reel_in"
const REEL_OUT := "reel_out"
const ACCURACY := "accuracy"
const RADIUS := "radius"
const DOUBLE := "double"
const BAG := "bag"
const MAGNET := "magnet"
const RECOVERY := "recovery"
const SLOWMO := "slowmo"
const SLOWMO_REST := "slowmo_rest"
# Upgrades as the equipment screen shows them; values live in balance.json.
const CATEGORIES := {"movement":[THROW,SWING,IMPULSE],"rope":[ROPE,REEL_IN,REEL_OUT],"hook":[ACCURACY,RADIUS,DOUBLE],"gather":[BAG,MAGNET],"survival":[RECOVERY,SLOWMO,SLOWMO_REST]}
const CATEGORY_NAMES := {"movement":"Движение","rope":"Канат","hook":"Крюк","gather":"Сбор","survival":"Выживание"}
const PROFILE_VERSION := 7
const ZONE_NAMES = ["Лес", "Скалы", "Руины", "Лёд", "Вулкан", "Небеса"]
const ZONE_HINTS = ["Освой раскачку", "Длинные перелёты", "Меняй направление", "Следи за скольжением", "Береги высоту", "Последний рывок"]
const LOOT_NAMES = ItemCatalog.LEGACY_NAMES
const MATERIAL_NAMES = ["Камень", "Корень", "Пружинящая ветка", "Лёд", "Кристалл"]
# Frozen economy of older profiles. Migration is computed from these, never
# from the current balance.json, so a later price change cannot change what an
# old save is refunded.
const PREVIOUS_UPGRADE_PRICES = [90, 300, 1000, 3200, 15500]
const PREVIOUS_TIP_PRICES = [2400, 12000]
const V4_TIP_PRICES = [900, 4800]
const V5_UPGRADE_PRICES = [90, 450, 1800, 5400, 9000]
const V5_WEIGHTS = [1.0, 1.0, 0.9, 1.1, 0.75, 0.9, 1.0, 1.0]
const V5_TIP_PRICES = [900, 1800, 3000]
const V5_SLOWMO_SECONDS = [0.7, 0.85, 1.0, 1.15, 1.3, 1.5]
# Version 6 had eight numbered tracks: 0 rope, 1 impulse, 2 hooks, 3 bag,
# 4 magnet, 5 recovery, 6 throw, 7 slow motion.
const V6_PRICES = [120, 350, 900, 1900]
const V6_WEIGHTS = [1.0, 1.05, 1.0, 1.1, 0.9, 0.95, 1.0, 1.0]
const V6_HOOK_PRICES = [500, 1200, 2200]
const V6_ROPE = [5.5, 6.2, 7.0, 7.8, 8.8]
const V6_IMPULSE = [1.0, 1.07, 1.14, 1.21, 1.28]
const V6_MAGNET = [0.0, 0.9, 1.2, 1.5, 1.8]
const V6_RECOVERY = [30, 40, 55, 70, 82]
const V6_THROW = [16, 19, 23, 27, 31]
const V6_SLOWMO = [0.7, 1.0, 1.35, 1.75]
const V6_SWING := 11.5
const V6_REEL := 2.4
const V6_SLOWMO_REST := 1.2

var balance: Dictionary
var profile: Dictionary
var bag: Array = []
var picked: Array = []
var save_path: String
var save_error: String = ""
var save_blocked := false

static func loot_name(item: Dictionary) -> String:
	return ItemCatalog.name_of(item)

func _init(path: String = "") -> void:
	balance = ItemCatalog.balance().duplicate(true)
	var custom := OS.get_environment("LASTHOOK_SAVE_DIR")
	save_path = path if not path.is_empty() else (custom.path_join("profile.json") if not custom.is_empty() else "user://profile.json")
	profile = fresh_profile()
	load_profile()

static func default_choices() -> Dictionary:
	return {"hook":1,"magnet":str(ItemCatalog.balance()["magnet_priority"]["default"])}

static func default_levels() -> Dictionary:
	var levels := {}
	for keys in CATEGORIES.values():
		for key in keys: levels[key] = 1
	return levels

static func fresh_profile() -> Dictionary:
	var starter: Dictionary = ItemCatalog.balance().get("starter_stock",{}).duplicate()
	var loadout: Array = []
	for id in starter.keys():
		if loadout.size()<int(ItemCatalog.balance().get("active_slots",2)): loadout.append(id)
	while loadout.size()<int(ItemCatalog.balance().get("active_slots",2)): loadout.append("")
	return {"version": PROFILE_VERSION, "gold": 0, "diamonds": 0, "upgrade_levels": default_levels(), "upgrade_choices": default_choices(),
		"material_wallet": {}, "consumable_stock": starter, "active_loadout": loadout,
		"coin_ledger": {"run":"","ids":[],"gold":0,"lifetime":0}, "unlocked_sets": [], "set_parts": {}, "landmarks": [],
		"completed_contracts": [], "mastery_tokens": 0, "reached_acts": 1, "best": 0.0,
		"endless_best": 0.0, "reached_zones": 1, "summit_cleared": false, "locations": [0],
		"cleared_locations": [], "runs": 0, "wins": 0, "last_settled": "", "active": {},
		"vibration": true, "notifications": true, "graphics_quality": "high", "loot_prices": "always",
		"selected_location":0,"run_history":[],"learned_controls":[],"camera_zoom":1.0,
		"records":{},"route_choices":{},"settings":GameSettings.defaults()}

static func build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version",""))

# --- Save and migration -----------------------------------------------------------

func load_profile() -> void:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		var parsed = parser.data
		if not parsed is Dictionary:
			continue
		var stored_version := int(parsed.get("version",0))
		if stored_version>PROFILE_VERSION:
			save_blocked = true
			save_error = "Сохранение создано более новой версией игры"
			return
		if stored_version not in [1,2,3,4,5,6,7]:
			continue
		var defaults := fresh_profile()
		var source_version := int(parsed["version"])
		for key in defaults:
			if parsed.has(key):
				defaults[key] = parsed[key]
		profile = defaults
		profile["gold"] = maxi(0, int(profile["gold"]))
		profile["diamonds"] = maxi(0, int(profile["diamonds"]))
		# Keys missing in an old save (stock, loadout, ledger...) keep their
		# fresh defaults, so an old profile gets the same trial item.
		if source_version<7: _migrate_upgrades(parsed,source_version)
		profile["settings"] = GameSettings.sanitize(profile["settings"])
		if source_version<7: _migrate_settings(parsed)
		if str(profile["loot_prices"]) not in ["near","always"]: profile["loot_prices"] = "always"
		_sanitize_progress()
		if not profile["learned_controls"] is Array: profile["learned_controls"] = []
		profile["learned_controls"] = profile["learned_controls"].filter(func(action): return action in ["aim","swing","rope","release"])
		if not profile["run_history"] is Array: profile["run_history"] = []
		profile["run_history"] = profile["run_history"].slice(-30)
		for key in ["locations", "cleared_locations"]:
			if not profile[key] is Array:
				profile[key] = [0] if key=="locations" else []
			profile[key] = profile[key].map(func(id): return int(id))
		profile["reached_zones"] = clampi(int(profile["reached_zones"]), 1, 6)
		_sanitize_records(parsed.has("records"))
		profile["camera_zoom"] = snap_camera_zoom(float(profile["camera_zoom"]) if (profile["camera_zoom"] is float or profile["camera_zoom"] is int) else 1.0)
		profile["selected_location"] = clampi(int(profile["selected_location"]),0,balance["locations"].size()-1)
		if not profile["locations"].has(profile["selected_location"]):
			profile["selected_location"] = 0
		if not profile["active"] is Dictionary:
			profile["active"] = {}
		if not profile["active"].is_empty():
			for key in ["picked", "broken", "active_reserves"]:
				profile["active"][key] = profile["active"].get(key,[]).map(func(id): return int(id))
			for item in profile["active"].get("bag",[]):
				ItemCatalog.normalize(item)
				# JSON reads every number as a float.
				for key in ["id", "tier", "value", "sell_value", "craft_value", "weight"]:
					item[key] = int(item[key])
			if source_version<6: _migrate_active_coins()
		if profile["active"].get("id", "unused") == profile["last_settled"]:
			profile["active"] = {}
		profile["version"] = PROFILE_VERSION
		return

# v7: the old on/off sound switches become volumes, and the old default
# quality moves up once. "battery" was always a deliberate choice.
func _migrate_settings(parsed: Dictionary) -> void:
	if not bool(parsed.get("sound",true)): profile["settings"]["sfx_volume"] = 0
	if not bool(parsed.get("music",true)): profile["settings"]["music_volume"] = 0
	if str(profile["graphics_quality"])=="balanced": profile["graphics_quality"] = "high"
	GameSettings.apply_preset(profile["settings"],str(profile["graphics_quality"]))

static func v5_paid(kind: int, at_level: int) -> int:
	var paid := 0
	if kind==2:
		for step in range(mini(at_level-1,V5_TIP_PRICES.size())): paid += int(V5_TIP_PRICES[step])
	else:
		for step in range(mini(at_level-1,V5_UPGRADE_PRICES.size())): paid += roundi(float(V5_UPGRADE_PRICES[step])*float(V5_WEIGHTS[kind]))
	return paid

static func v6_max_level(kind: int) -> int:
	return 4 if kind in [2,7] else 5

static func v6_price(kind: int, current_level: int) -> int:
	if current_level>=v6_max_level(kind): return 0
	if kind==2: return int(V6_HOOK_PRICES[current_level-1])
	return roundi(float(V6_PRICES[current_level-1])*float(V6_WEIGHTS[kind]))

static func v6_paid(kind: int, at_level: int) -> int:
	var paid := 0
	for step in range(1,at_level): paid += v6_price(kind,step)
	return paid

# v1-v4 become v5 levels (with their own refund), then v5 levels become the
# chat 4 tracks: standard tracks keep at most level 5, hooks keep their stage,
# slow motion keeps the longest window not above the bought one. The
# difference between what was paid and what the new levels cost is returned
# once; a level is never removed to create debt.
func _levels_to_v6(parsed: Dictionary, source_version: int) -> Array:
	var track_count := V6_WEIGHTS.size()
	var levels: Array = parsed.get("levels",[]).duplicate() if parsed.get("levels",[]) is Array else []
	if levels.size()==6: levels.append(levels[0])
	if levels.size()==7: levels.append(1)
	if levels.size()!=track_count: levels = [1,1,1,1,1,1,1,1]
	var old_hook_level := clampi(int(levels[2]),1,6)
	if source_version<3:
		levels[2] = 1 if old_hook_level==1 else 2 if old_hook_level<5 else 4
	elif source_version<5:
		levels[2] = 4 if old_hook_level>=3 else old_hook_level
	for kind in range(track_count):
		levels[kind] = clampi(int(levels[kind]),1,4 if kind==2 else 6)
	if source_version<5:
		for kind in range(track_count):
			var old_level := clampi(int(parsed.get("levels",[])[kind]) if parsed.get("levels",[]).size()>kind else 1,1,6)
			var old_paid := 0
			if kind==2:
				var old_prices: Array = V4_TIP_PRICES if source_version==4 else PREVIOUS_TIP_PRICES
				for step in range(mini(old_level-1,old_prices.size())): old_paid += int(old_prices[step])
			else:
				for step in range(old_level-1):
					var base_price: float = float(PREVIOUS_UPGRADE_PRICES[step] if source_version<4 else V5_UPGRADE_PRICES[step])
					old_paid += roundi(base_price*float(V5_WEIGHTS[kind]))
			profile["gold"] += maxi(0,old_paid-v5_paid(kind,int(levels[kind])))
	var upgraded: Array = []
	for kind in range(track_count):
		var old := int(levels[kind])
		var new_level := mini(old,v6_max_level(kind))
		if kind==7:
			new_level = 1
			var seconds: float = float(V5_SLOWMO_SECONDS[clampi(old-1,0,V5_SLOWMO_SECONDS.size()-1)])
			for index in range(V6_SLOWMO.size()):
				if float(V6_SLOWMO[index])<=seconds+.0001: new_level = index+1
		upgraded.append(new_level)
	for kind in range(track_count):
		profile["gold"] += maxi(0,v5_paid(kind,int(levels[kind]))-v6_paid(kind,upgraded[kind]))
	# Acts reached so far, read from the best height on the first expedition.
	var best_units := float(parsed.get("best",0.0))/float(balance["meters_per_unit"])
	var acts := 1
	for span in LevelCatalog.act_spans(0,float(balance["locations"][0]["height_units"])):
		if int(span["index"])>0 and float(span["y_start"])<=best_units: acts += 1
	profile["reached_acts"] = acts
	return upgraded

# The best new level that is not stronger than the old value. Slow motion's
# rest is the one track where less is better.
func _level_for(key: String, old_value: float) -> int:
	var values: Array = balance["upgrades"][key]["values"]
	var result := 1
	for index in range(values.size()):
		var fits: bool = float(values[index])>=old_value-.0001 if key==SLOWMO_REST else float(values[index])<=old_value+.0001
		if fits: result = index+1
	return result

func _paid(key: String, at_level: int) -> int:
	var paid := 0
	for step in range(1,at_level): paid += price_at_level(key,step)
	return paid

# v7: fourteen named tracks. Every track lands on the level closest to what
# the player had without exceeding it; what the old track cost above the new
# levels' price comes back once. The new tracks start where the old fixed
# values were, for free.
func _migrate_upgrades(parsed: Dictionary, source_version: int) -> void:
	var old: Array = _levels_to_v6(parsed,source_version) if source_version<6 else []
	if source_version==6:
		var stored = parsed.get("upgrade_levels",[])
		for kind in range(V6_WEIGHTS.size()):
			old.append(clampi(int(stored[kind]) if stored is Array and stored.size()>kind else 1,1,v6_max_level(kind)))
	var levels := default_levels()
	levels[ROPE] = _level_for(ROPE,V6_ROPE[old[0]-1])
	levels[IMPULSE] = _level_for(IMPULSE,V6_IMPULSE[old[1]-1])
	levels[BAG] = old[3]
	levels[MAGNET] = _level_for(MAGNET,V6_MAGNET[old[4]-1])
	levels[RECOVERY] = _level_for(RECOVERY,V6_RECOVERY[old[5]-1])
	levels[THROW] = _level_for(THROW,V6_THROW[old[6]-1])
	levels[SLOWMO] = _level_for(SLOWMO,V6_SLOWMO[old[7]-1])
	levels[RADIUS] = 5 if old[2]>=2 else 1
	levels[DOUBLE] = 2 if old[2]>=3 else 1
	levels[SWING] = _level_for(SWING,V6_SWING)
	levels[REEL_IN] = _level_for(REEL_IN,V6_REEL)
	levels[REEL_OUT] = _level_for(REEL_OUT,V6_REEL)
	levels[SLOWMO_REST] = _level_for(SLOWMO_REST,V6_SLOWMO_REST)
	profile["upgrade_levels"] = levels
	var tracks := {0:[ROPE],1:[IMPULSE],2:[RADIUS,DOUBLE],3:[BAG],4:[MAGNET],5:[RECOVERY],6:[THROW],7:[SLOWMO]}
	for kind in tracks.keys():
		var new_paid := 0
		for key in tracks[kind]: new_paid += _paid(key,int(levels[key]))
		profile["gold"] += maxi(0,v6_paid(kind,old[kind])-new_paid)
	var choices: Variant = parsed.get("upgrade_choices",{})
	var old_choice: int = int(choices.get("hook",old[2])) if source_version==6 and choices is Dictionary else int(old[2])
	profile["upgrade_choices"] = default_choices()
	profile["upgrade_choices"]["hook"] = 2 if old_choice>=3 else 1
	if choices is Dictionary and choices.has("magnet"): profile["upgrade_choices"]["magnet"] = str(choices["magnet"])

# A coin found before chat 4 is still in an active bag: it is banked once,
# through the ledger, and leaves the bag, so the settlement cannot pay it too.
func _migrate_active_coins() -> void:
	var active: Dictionary = profile["active"]
	var kept: Array = []
	for item in active.get("bag",[]):
		if ItemCatalog.is_coin(item):
			if str(profile["coin_ledger"].get("run",""))!=str(active.get("id","")):
				profile["coin_ledger"] = {"run":str(active.get("id","")),"ids":[],"gold":0,"lifetime":int(profile["coin_ledger"].get("lifetime",0))}
			_bank_coin(int(item["id"]),int(item["value"]))
		else:
			kept.append(item)
	active["bag"] = kept

func _sanitize_progress() -> void:
	var stored_levels: Variant = profile["upgrade_levels"]
	var levels := default_levels()
	if stored_levels is Dictionary:
		for key in levels.keys(): levels[key] = clampi(int(stored_levels.get(key,1)),1,max_level(key))
	profile["upgrade_levels"] = levels
	var choices: Dictionary = default_choices()
	if profile["upgrade_choices"] is Dictionary:
		for key in choices.keys():
			if profile["upgrade_choices"].has(key): choices[key] = profile["upgrade_choices"][key]
	choices["hook"] = clampi(int(choices["hook"]),1,level(DOUBLE))
	if not balance["magnet_priority"]["options"].has(str(choices["magnet"])): choices["magnet"] = default_choices()["magnet"]
	choices["magnet"] = str(choices["magnet"])
	profile["upgrade_choices"] = choices
	for key in ["material_wallet","consumable_stock","set_parts"]:
		var source = profile[key]
		var clean := {}
		if source is Dictionary:
			for id in source.keys(): clean[str(id)] = maxi(0,int(source[id]))
		profile[key] = clean
	for id in profile["consumable_stock"].keys():
		if ItemCatalog.consumable(id).is_empty(): profile["consumable_stock"].erase(id)
		else: profile["consumable_stock"][id] = mini(int(profile["consumable_stock"][id]),stock_max())
	var loadout: Array = profile["active_loadout"] if profile["active_loadout"] is Array else []
	var clean_loadout: Array = []
	for index in range(active_slots()):
		var id := str(loadout[index]) if index<loadout.size() else ""
		clean_loadout.append(id if not ItemCatalog.consumable(id).is_empty() and not clean_loadout.has(id) else "")
	profile["active_loadout"] = clean_loadout
	var ledger = profile["coin_ledger"]
	if not ledger is Dictionary: ledger = {}
	profile["coin_ledger"] = {"run":str(ledger.get("run","")),"ids":(ledger.get("ids",[]) as Array).map(func(id): return int(id)) if ledger.get("ids",[]) is Array else [],
		"gold":maxi(0,int(ledger.get("gold",0))),"lifetime":maxi(0,int(ledger.get("lifetime",0)))}
	for key in ["unlocked_sets","completed_contracts","landmarks"]:
		profile[key] = (profile[key] as Array).map(func(id): return str(id)) if profile[key] is Array else []
	profile["mastery_tokens"] = maxi(0,int(profile["mastery_tokens"]))
	profile["reached_acts"] = clampi(int(profile["reached_acts"]),1,3)

func save() -> bool:
	if save_blocked:
		return false
	var absolute := ProjectSettings.globalize_path(save_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var pending := absolute + ".tmp"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		save_error = "Не удалось сохранить прогресс"
		print("SAVE_ERROR ",save_error,": ",str(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	file.close()
	# Keep a recovery copy if the app closes between renames.
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(absolute + ".bak"):
			DirAccess.remove_absolute(absolute + ".bak")
		if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK:
			DirAccess.remove_absolute(pending)
			save_error = "Не удалось обновить сохранение"
			return false
	var error := DirAccess.rename_absolute(pending, absolute)
	if error == OK:
		save_error = ""
		return true
	# The old file may already be in .bak. Restore it immediately so a failed
	# save never leaves the primary path missing until the next launch.
	DirAccess.remove_absolute(pending)
	if not FileAccess.file_exists(absolute) and FileAccess.file_exists(absolute + ".bak"):
		DirAccess.rename_absolute(absolute + ".bak",absolute)
	save_error = "Не удалось записать сохранение"
	return false

# --- Upgrade tracks -----------------------------------------------------------------

func upgrade(key: String) -> Dictionary:
	return balance["upgrades"][key]

func level(key: String) -> int:
	return int(profile["upgrade_levels"][key])

# Direct level change for tests, captures and fixtures (no price, no gate).
func set_level(key: String, value_level: int) -> void:
	profile["upgrade_levels"][key] = clampi(value_level,1,max_level(key))
	if key==DOUBLE: profile["upgrade_choices"]["hook"] = level(DOUBLE)

func set_levels(values: Dictionary) -> void:
	for key in values.keys(): set_level(key,int(values[key]))

func max_level(key: String) -> int:
	return upgrade(key)["values"].size()

func value_at(key: String, at_level: int) -> float:
	var values: Array = upgrade(key)["values"]
	return float(values[clampi(at_level-1,0,values.size()-1)])

func value(key: String) -> float:
	return value_at(key,level(key))

func slowmo_seconds() -> float:
	return value(SLOWMO)

# Release slow motion: the factor applied to the simulation step and the
# real-time pause before the next release may start it again.
func slowmo_time_scale() -> float:
	return clampf(float(balance.get("slowmo",{}).get("time_scale",.32)),.1,1.0)

func slowmo_cooldown() -> float:
	return value(SLOWMO_REST)

# Walking and camera tuning lives in balance.json; the fallbacks are the
# values the game shipped with before they were configurable.
func movement(key: String, fallback: float) -> float:
	return float(balance.get("movement",{}).get(key,fallback))

func camera_setting(key: String, fallback):
	return balance.get("camera",{}).get(key,fallback)

func camera_zoom_levels() -> Array:
	var levels: Array = camera_setting("zoom_levels",[1.0])
	return levels if not levels.is_empty() else [1.0]

# Zoom is a player setting: only the listed steps are valid, so a hand-edited
# or outdated profile snaps to the closest one instead of breaking framing.
func snap_camera_zoom(zoom: float) -> float:
	var best := float(camera_zoom_levels()[0])
	for option in camera_zoom_levels():
		if absf(float(option)-zoom)<absf(best-zoom): best = float(option)
	return best

func camera_zoom() -> float:
	return snap_camera_zoom(float(profile.get("camera_zoom",1.0)))

func choice(track: String) -> String:
	return str(profile["upgrade_choices"].get(track,""))

func set_choice(track: String, option: String) -> String:
	if not profile["active"].is_empty(): return "Сначала заверши текущую попытку"
	if track=="hook":
		var config := int(option)
		if config<1 or config>level(DOUBLE): return "Двойной крюк ещё не куплен"
		profile["upgrade_choices"]["hook"] = config
		save()
		return "Крюк · "+("двойной" if config==2 else "одинарный")
	var priority: Dictionary = balance["magnet_priority"]
	if track!="magnet" or not priority["options"].has(option): return "Нет такого выбора"
	if not magnet_priority_open(): return "Откроется на %d-м уровне магнита" % int(priority["unlock_level"])
	profile["upgrade_choices"]["magnet"] = option
	save()
	return "Магнит · "+str(priority["options"][option]["name"]).to_lower()

func magnet_priority_open() -> bool:
	return level(MAGNET)>=int(balance["magnet_priority"]["unlock_level"])

func hook_count() -> int:
	return clampi(int(profile["upgrade_choices"].get("hook",1)),1,level(DOUBLE))

func hook_tips() -> int:
	return 3 if level(RADIUS)>=3 else 1

func hook_spread() -> float:
	return value(ACCURACY)

func hook_directions(direction: Vector2) -> Array[Vector2]:
	if hook_count()==1: return [direction.normalized()]
	var half_spread := deg_to_rad(hook_spread()*.5)
	return [direction.normalized().rotated(-half_spread),direction.normalized().rotated(half_spread)]

func hook_radius() -> float:
	return value(RADIUS)

func rope_length() -> float:
	return value(ROPE)

func shot_range() -> float:
	return rope_length()

func swing_force() -> float:
	return value(SWING)

func reel_in_speed() -> float:
	return value(REEL_IN)

func reel_out_speed() -> float:
	return value(REEL_OUT)

func impulse_factor() -> float:
	return value(IMPULSE)

func throw_speed() -> float:
	return value(THROW)

func capacity() -> int:
	return int(value(BAG))

func special_slots() -> int:
	return int(upgrade(BAG)["special_slots"][level(BAG)-1])

func bag_capacity() -> int:
	return capacity()+special_slots()

func coin_radius() -> float:
	return value(MAGNET)

func item_radius() -> float:
	return value(MAGNET)

func magnet_priority() -> String:
	return choice("magnet") if magnet_priority_open() else ""

func recovery_percent() -> int:
	return int(value(RECOVERY))

# A card that means nothing yet stays closed until its base is bought.
func dependency_open(key: String) -> bool:
	if key==ACCURACY: return level(DOUBLE)>=2
	if key==SLOWMO_REST: return level(SLOWMO)>=2
	return true

func upgrade_available(key: String) -> bool:
	if level(key)>=max_level(key) or not dependency_open(key): return false
	return key==DOUBLE or level(key)+1<=unlocked_upgrade_level()

func lock_reason(key: String) -> String:
	if key==ACCURACY and not dependency_open(key): return "Нужен двойной крюк"
	if key==SLOWMO_REST and not dependency_open(key): return "Сначала купи замедление"
	return gate_text(level(key)+1)

func cost(key: String) -> int:
	return price_at_level(key,level(key))

func price_at_level(key: String, current_level: int) -> int:
	if current_level>=max_level(key): return 0
	if key==DOUBLE: return int(upgrade(key)["price"])
	return roundi(float(balance["upgrade_prices"][current_level-1])*float(upgrade(key)["weight"]))

func gate_met(gate: Dictionary) -> bool:
	if gate.has("acts") and int(profile["reached_acts"])<int(gate["acts"]): return false
	if gate.has("summit_or_contracts") and not profile["summit_cleared"] and profile["completed_contracts"].size()<int(gate["summit_or_contracts"]): return false
	return true

# The highest level any standard track may be bought to now.
func unlocked_upgrade_level() -> int:
	var gates: Array = balance["upgrade_gates"]
	var result := 1
	for target in range(2,gates.size()+1):
		if not gate_met(gates[target-1]): break
		result = target
	return result

func gate_text(target_level: int) -> String:
	var gate: Dictionary = balance["upgrade_gates"][clampi(target_level-1,0,balance["upgrade_gates"].size()-1)]
	if gate.has("acts"): return "Пройди первый акт" if int(gate["acts"])<=2 else "Дойди до 3-го акта"
	if gate.has("summit_or_contracts"): return "Вершина или %d контр." % int(gate["summit_or_contracts"])
	return ""

func purchase(key: String) -> String:
	if not profile["active"].is_empty():
		return "Сначала заверши текущую попытку"
	if level(key)>=max_level(key):
		return "Уже максимальный уровень"
	if not upgrade_available(key):
		return lock_reason(key)
	var price := cost(key)
	if int(profile["gold"])<price:
		return "Не хватает %d золота" % (price-int(profile["gold"]))
	profile["gold"] -= price
	profile["upgrade_levels"][key] += 1
	# A double hook is taken at once; the single one stays selectable.
	if key==DOUBLE: profile["upgrade_choices"]["hook"] = 2
	save()
	return "Улучшено: "+str(upgrade(key)["name"])

func upgrade_use(key: String, at_level: int) -> String:
	var uses: Array = upgrade(key).get("uses",[])
	return str(uses[clampi(at_level-1,0,uses.size()-1)]) if not uses.is_empty() else ""

func learn_control(action: String) -> void:
	if action not in profile["learned_controls"]:
		profile["learned_controls"].append(action)

func recommended_upgrade() -> String:
	if not profile["active"].is_empty(): return ""
	var lowest := 99
	var selected := ""
	for key in [ROPE,THROW,BAG,IMPULSE,RADIUS,RECOVERY,MAGNET,SWING,REEL_IN,REEL_OUT,SLOWMO,SLOWMO_REST,ACCURACY,DOUBLE]:
		if upgrade_available(key) and cost(key)<=int(profile["gold"]) and level(key)<lowest:
			lowest = level(key)
			selected = key
	return selected

func next_goal() -> String:
	var stage := int(profile["reached_zones"])
	return "Следующая зона · %d м" % roundi(stage*float(balance["zone_units"])*10) if stage<6 else "Следующая цель · вершина"

# --- Prepared routes: the one chosen per expedition ---------------------------------

func route_choice(location: int) -> int:
	var choices = profile.get("route_choices",{})
	var index := int(choices.get(str(location),0)) if choices is Dictionary else 0
	return clampi(index,0,LevelCatalog.routes(location).size()-1)

func set_route_choice(location: int, index: int) -> void:
	if not profile.get("route_choices",null) is Dictionary: profile["route_choices"] = {}
	profile["route_choices"][str(location)] = clampi(index,0,LevelCatalog.routes(location).size()-1)

# --- Records: one per route and mode ------------------------------------------------
# records = {"summit":{"0":m,"1":m,...},"endless":{...},"practice":{"0":m}}.
# "best" stays the overall record (save compatibility, act gates of old saves).

const RECORD_MODES := ["summit","endless","practice"]

func record(location: int, mode: String = "summit") -> float:
	var table = profile["records"].get(mode,{})
	return float(table.get(str(location),0.0)) if table is Dictionary else 0.0

# Returns true when the height is a new record of that route and mode.
func note_record(location: int, mode: String, meters: float) -> bool:
	if mode not in RECORD_MODES or meters<=record(location,mode): return false
	if not profile["records"].get(mode,null) is Dictionary: profile["records"][mode] = {}
	profile["records"][mode][str(location)] = snappedf(meters,.1)
	return true

# A record table read from a save keeps only known modes and numbers. A save
# from before per-route records rebuilds them from its run history; the old
# overall record goes to the first route when the history has no better one.
func _sanitize_records(stored: bool) -> void:
	var source = profile.get("records",{})
	var clean := {}
	if source is Dictionary:
		for mode in RECORD_MODES:
			if source.get(mode,null) is Dictionary:
				var table := {}
				for key in source[mode].keys():
					if str(key).is_valid_int() and int(key)>=0 and int(key)<balance["locations"].size(): table[str(int(key))] = maxf(0.0,float(source[mode][key]))
				clean[mode] = table
	profile["records"] = clean
	if stored: return
	for entry in profile["run_history"]:
		if not entry is Dictionary: continue
		var mode := str(entry.get("mode","summit"))
		note_record(clampi(int(entry.get("location",0)),0,balance["locations"].size()-1),mode,float(entry.get("height",0)))
	var overall := float(profile.get("best",0.0))
	if overall>0 and record(0,"summit")<=0 and record(1,"summit")<=0 and record(2,"summit")<=0: note_record(0,"summit",overall)
	if float(profile.get("endless_best",0.0))>0: note_record(0,"endless",float(profile["endless_best"]))

func reach(units: float) -> Array:
	profile["best"] = maxf(float(profile["best"]), units * float(balance["meters_per_unit"]))
	var stage := clampi(1 + floori(units / float(balance["zone_units"])), 1, 6)
	var opened: Array = []
	while int(profile["reached_zones"]) < stage:
		profile["reached_zones"] += 1
		var current: int = profile["reached_zones"]
		profile["gold"] += int(balance["new_zone_gold_per_index"]) * current
		profile["diamonds"] += int(balance["new_zone_diamonds"])
		opened.append(current-1)
	return opened

# Entering act `count` (1..3) of any expedition opens the next upgrade gate.
func reach_act(count: int) -> bool:
	if count<=int(profile["reached_acts"]): return false
	profile["reached_acts"] = clampi(count,1,3)
	return true

func height_gold(units: float) -> int:
	var bands := maxi(0, floori(units * float(balance["meters_per_unit"]) / 10))
	var result := 0
	for band in range(1, bands + 1):
		result += 2 + mini((band-1) / 20, 7)
	return result

# --- Coins: banked at once, once per id and run --------------------------------------

func begin_run_ledger(run_id: String) -> void:
	if str(profile["coin_ledger"]["run"])==run_id: return
	profile["coin_ledger"] = {"run":run_id,"ids":[],"gold":0,"lifetime":int(profile["coin_ledger"].get("lifetime",0))}

func _bank_coin(id: int, amount: int) -> void:
	var ledger: Dictionary = profile["coin_ledger"]
	ledger["ids"].append(id)
	ledger["gold"] = int(ledger["gold"])+amount
	ledger["lifetime"] = int(ledger["lifetime"])+amount
	profile["gold"] = int(profile["gold"])+amount

# Returns false for a repeated callback or a coin of another run. The caller
# saves the snapshot right away: ledger, wallet and picked id are one write.
func collect_coin(run_id: String, item: Dictionary) -> bool:
	if not ItemCatalog.is_coin(item) or run_id.is_empty(): return false
	begin_run_ledger(run_id)
	var id := int(item["id"])
	if profile["coin_ledger"]["ids"].has(id): return false
	_bank_coin(id,int(item["value"]))
	if not picked.has(id): picked.append(id)
	return true

func run_coins(run_id: String) -> int:
	return int(profile["coin_ledger"]["gold"]) if str(profile["coin_ledger"]["run"])==run_id else 0

# --- Bag ------------------------------------------------------------------------------

static func pays_gold(item: Dictionary) -> bool:
	return str(item.get("family","valuable")) in ["valuable","relic","contract"]

func valuable_count() -> int:
	var count := 0
	for item in bag: count += 1 if str(item.get("family","valuable"))=="valuable" else 0
	return count

# The last (special) slot takes a material, relic or contract, never a plain
# valuable.
func can_fit(item: Dictionary) -> bool:
	if ItemCatalog.is_coin(item) or bag.size()>=bag_capacity(): return false
	if str(item.get("family","valuable"))=="valuable" and valuable_count()>=capacity(): return false
	return true

func try_pick(item: Dictionary) -> bool:
	# Full-bag replacement is decided by the run controller, which can also
	# animate the incoming item at the correct world position.
	if picked.has(item["id"]) or not can_fit(item):
		return false
	bag.append(ItemCatalog.normalize(item.duplicate(true)))
	picked.append(item["id"])
	return true

func discard(index: int) -> void:
	if index >= 0 and index < bag.size():
		bag.remove_at(index)
	# Picked IDs remain marked: discarded finds cannot be collected repeatedly.

func cheapest_index(for_item: Dictionary = {}) -> int:
	var best := -1
	for index in range(bag.size()):
		var item: Dictionary = bag[index]
		if str(item.get("family",""))=="contract": continue
		# A valuable can only replace a valuable while the special slot is full.
		if str(for_item.get("family",""))=="valuable" and str(item.get("family","valuable"))!="valuable" and valuable_count()>=capacity(): continue
		if best<0 or int(item["value"])<int(bag[best]["value"]): best = index
	return best

# Explicit choice from the full-bag prompt: drop one item, take the find.
func swap_in(item: Dictionary, index: int) -> bool:
	if index<0 or index>=bag.size() or picked.has(item["id"]): return false
	var removed: Dictionary = bag[index]
	bag.remove_at(index)
	if try_pick(item): return true
	bag.insert(index,removed)
	return false

func bag_value() -> int:
	var total := 0
	for item in bag:
		if pays_gold(item): total += int(item["value"])
	return total

func item_is_rare(item: Dictionary) -> bool:
	if item.has("rarity"): return str(item["rarity"]) in ["artifact","contract","rare","set"]
	var tier := clampi(int(item.get("tier",0)),0,balance["loot_values"].size()-1)
	return int(item.get("value",0))>int(balance["loot_values"][tier])

# A full bag asks only about finds worth a decision.
func worth_prompt(item: Dictionary) -> bool:
	return str(item.get("rarity","")) in ["artifact","contract","rare"] or str(item.get("family",""))=="contract"

func retained(success: bool) -> int:
	return bag_value() if success else floori(bag_value() * recovery_percent() / 100.0)

# --- Consumables ------------------------------------------------------------------------

func active_slots() -> int:
	return int(balance.get("active_slots",2))

func stock_max() -> int:
	return int(balance.get("consumable_stock_max",2))

func stock(id: String) -> int:
	return int(profile["consumable_stock"].get(id,0))

func materials(id: String) -> int:
	return int(profile["material_wallet"].get(id,0))

func buy_consumable(id: String) -> String:
	var definition := ItemCatalog.consumable(id)
	if definition.is_empty(): return "Нет такого предмета"
	if not profile["active"].is_empty(): return "Сначала заверши текущую попытку"
	if stock(id)>=stock_max(): return "В запасе уже %d" % stock_max()
	var price := int(definition["price_gold"])
	if int(profile["gold"])<price: return "Не хватает %d золота" % (price-int(profile["gold"]))
	profile["gold"] -= price
	profile["consumable_stock"][id] = stock(id)+1
	save()
	return "Куплено: "+str(definition["name"])

func can_craft(id: String) -> bool:
	var definition := ItemCatalog.consumable(id)
	if definition.is_empty(): return false
	for material_id in definition["recipe_materials"].keys():
		if materials(material_id)<int(definition["recipe_materials"][material_id]): return false
	return true

func craft_consumable(id: String) -> String:
	var definition := ItemCatalog.consumable(id)
	if definition.is_empty(): return "Нет такого предмета"
	if not profile["active"].is_empty(): return "Сначала заверши текущую попытку"
	if stock(id)>=stock_max(): return "В запасе уже %d" % stock_max()
	if not can_craft(id): return "Не хватает материалов"
	for material_id in definition["recipe_materials"].keys():
		profile["material_wallet"][material_id] = materials(material_id)-int(definition["recipe_materials"][material_id])
	profile["consumable_stock"][id] = stock(id)+1
	save()
	return "Изготовлено: "+str(definition["name"])

# Rescue effects do not stack: conflicting items cannot share the loadout.
func set_loadout(slot: int, id: String) -> String:
	if not profile["active"].is_empty(): return "Сначала заверши текущую попытку"
	if slot<0 or slot>=active_slots(): return "Нет такого слота"
	if not id.is_empty():
		var definition := ItemCatalog.consumable(id)
		if definition.is_empty(): return "Нет такого предмета"
		for index in range(active_slots()):
			if index==slot: continue
			var other := str(profile["active_loadout"][index])
			if other==id: profile["active_loadout"][index] = ""
			elif other in definition["conflicts"]: return "Не сочетается: "+str(ItemCatalog.consumable(other)["name"])
	profile["active_loadout"][slot] = id
	save()
	return "Слот %d: %s" % [slot+1,str(ItemCatalog.consumable(id)["name"]) if not id.is_empty() else "пусто"]

# What the next run carries: one charge of every item in stock. Buying an
# item is buying it for the next run; there are no slots to fill.
func run_items() -> Array:
	var result: Array = []
	for definition in ItemCatalog.consumables():
		var id := str(definition["id"])
		if stock(id)>0: result.append({"id":id,"used":false})
	return result

# Starts a run: the carried charges leave the stock at once, so a bought
# item is always spent on the run it was bought for.
func take_run_items() -> Array:
	var result := run_items()
	for entry in result: profile["consumable_stock"][entry["id"]] = stock(str(entry["id"]))-1
	return result

# Uses a carried item during the run (its charge left the stock at the start).
func spend_item(items: Array, index: int) -> bool:
	if index<0 or index>=items.size() or bool(items[index]["used"]): return false
	items[index]["used"] = true
	return true

# --- Settlement -------------------------------------------------------------------------

func settle(run_id: String, mode: String, highest: float, success: bool, location: int, extras: Dictionary = {}) -> Dictionary:
	if run_id.is_empty() or profile["last_settled"] == run_id:
		return {"duplicate": true, "total": 0}
	var summit_success := success and mode == "summit"
	var height := height_gold(highest)
	var percent := 100 if summit_success else recovery_percent()
	var loot := retained(summit_success)
	var finish := int(balance["summit_repeat_bonus"]) if summit_success else 0
	var first: bool = summit_success and not profile["cleared_locations"].has(location)
	var diamonds := int(balance["first_summit_diamonds"]) if first else int(balance["summit_repeat_diamonds"]) if summit_success else 0
	profile["diamonds"] += diamonds
	if first:
		finish += int(balance["first_summit_gold"])
		profile["cleared_locations"].append(location)
	if summit_success:
		profile["summit_cleared"] = true
		profile["wins"] += 1
	if mode == "endless":
		profile["endless_best"] = maxf(float(profile["endless_best"]), highest * 10)
	# Relics, landmarks and materials are whole items: a defeat keeps the
	# recovery share of them, rounded, most valuable kind first.
	var pieces: Array = []
	for item in bag:
		if str(item.get("family","")) in ["relic","material"]: pieces.append(item)
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["family"]!=b["family"]: return a["family"]=="relic"
		return int(a["value"])>int(b["value"]))
	var kept := pieces.size() if summit_success else floori(pieces.size()*percent/100.0+.5)
	var gained_materials := {}
	var sets: Array = []
	var landmarks: Array = []
	var tokens := 0
	for index in range(kept):
		var item: Dictionary = pieces[index]
		var id := str(item.get("set_id",""))
		if item["family"]=="material":
			profile["material_wallet"][id] = materials(id)+1
			gained_materials[id] = int(gained_materials.get(id,0))+1
		elif str(item.get("use_tag",""))=="landmark":
			if not profile["landmarks"].has(id): profile["landmarks"].append(id)
			landmarks.append(id)
		elif not id.is_empty():
			var parts := mini(int(balance["set_parts"]),int(profile["set_parts"].get(id,0))+1)
			profile["set_parts"][id] = parts
			var completed: bool = parts>=int(balance["set_parts"]) and not profile["unlocked_sets"].has(id)
			if completed:
				profile["unlocked_sets"].append(id)
				tokens += int(balance["set_tokens"])
			sets.append({"id":id,"name":ItemCatalog.set_name(id),"parts":parts,"completed":completed})
	# The contract counts only when its cargo reaches the summit.
	var contract_tag := str(extras.get("contract",""))
	var contract_gold := 0
	var contract_done := false
	if summit_success and not contract_tag.is_empty():
		for item in bag:
			if str(item.get("family",""))=="contract" and str(item.get("set_id",""))==contract_tag: contract_done = true
	if contract_done:
		var rewards: Array = balance["contracts"]["gold"]
		var reward := int(rewards[clampi(location,0,rewards.size()-1)])
		if profile["completed_contracts"].has(contract_tag):
			contract_gold = roundi(reward*float(balance["contracts"]["repeat_share"]))
		else:
			contract_gold = reward
			profile["completed_contracts"].append(contract_tag)
			tokens += int(balance["contracts"]["tokens_first"])
	profile["mastery_tokens"] = int(profile["mastery_tokens"])+tokens
	profile["gold"] += height + loot + finish + contract_gold
	profile["runs"] += 1
	profile["last_settled"] = run_id
	profile["active"] = {}
	save()
	return {"duplicate": false, "height": height, "loot": loot, "carried": bag_value(), "finish": finish, "recovery": percent,
		"coins": run_coins(run_id), "contract": contract_gold, "contract_done": contract_done, "contract_tag": contract_tag,
		"materials": gained_materials, "sets": sets, "landmarks": landmarks, "tokens": tokens, "spent": extras.get("spent",[]),
		"total": height+loot+finish+contract_gold, "diamonds": diamonds, "first": first, "success": summit_success, "highest": roundi(highest*10)}

# --- Locations ----------------------------------------------------------------------------

func location_unlock(index: int) -> Dictionary:
	return balance["locations"][index].get("unlock",{})

func location_requirement(index: int) -> String:
	var unlock := location_unlock(index)
	var parts: Array = []
	if unlock.has("cleared"): parts.append("вершина «%s»" % str(balance["locations"][int(unlock["cleared"])]["name"]))
	if unlock.has("gold"): parts.append("%d золота" % int(unlock["gold"]))
	if unlock.has("diamonds"): parts.append("%d алмазов" % int(unlock["diamonds"]))
	return " + ".join(parts)

func location_ready(index: int) -> bool:
	var unlock := location_unlock(index)
	if unlock.has("cleared") and not profile["cleared_locations"].has(int(unlock["cleared"])): return false
	return int(profile["gold"])>=int(unlock.get("gold",0)) and int(profile["diamonds"])>=int(unlock.get("diamonds",0))

func purchase_location(index: int) -> String:
	if index<0 or index>=balance["locations"].size():
		return "Локация недоступна"
	if not profile["active"].is_empty():
		return "Сначала заверши текущую попытку"
	if profile["locations"].has(index):
		return "Локация уже открыта"
	var unlock := location_unlock(index)
	if unlock.has("cleared") and not profile["cleared_locations"].has(int(unlock["cleared"])):
		return "Сначала покори вершину «%s»" % str(balance["locations"][int(unlock["cleared"])]["name"])
	if not location_ready(index):
		return "Нужно: "+location_requirement(index)
	profile["gold"] -= int(unlock.get("gold",0))
	profile["diamonds"] -= int(unlock.get("diamonds",0))
	profile["locations"].append(index)
	save()
	return "Открыта: " + str(balance["locations"][index]["name"])
