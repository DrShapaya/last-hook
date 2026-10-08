class_name GameModel
extends RefCounted

const UPGRADE_NAMES = ["Макс. длина каната", "Импульс", "Наконечники", "Рюкзак", "Магнит", "Сохранение добычи", "Сила броска"]
const UPGRADE_COUNT := 7
const THROW := 6
const ZONE_NAMES = ["Лес", "Скалы", "Руины", "Лёд", "Вулкан", "Небеса"]
const ZONE_HINTS = ["Освой раскачку", "Длинные перелёты", "Меняй направление", "Следи за скольжением", "Береги высоту", "Последний рывок"]
const LOOT_NAMES = ["Медная находка", "Янтарь", "Древняя реликвия", "Ледяной кристалл", "Обсидиан", "Небесный осколок"]
const MATERIAL_NAMES = ["Камень", "Корень", "Пружинящая ветка", "Лёд", "Кристалл"]

var balance: Dictionary
var profile: Dictionary
var bag: Array = []
var picked: Array = []
var save_path: String
var save_error: String = ""

func _init(path: String = "") -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var custom := OS.get_environment("LASTHOOK_SAVE_DIR")
	save_path = path if not path.is_empty() else (custom.path_join("profile.json") if not custom.is_empty() else "user://profile.json")
	profile = fresh_profile()
	load_profile()

static func fresh_profile() -> Dictionary:
	return {"version": 3, "gold": 0, "diamonds": 0, "levels": [1, 1, 1, 1, 1, 1, 1], "best": 0.0,
		"endless_best": 0.0, "reached_zones": 1, "summit_cleared": false, "locations": [0],
		"cleared_locations": [], "runs": 0, "wins": 0, "last_settled": "", "active": {}, "sound": true,"selected_location":0,"run_history":[],"learned_controls":[]}

func load_profile() -> void:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		var parsed = parser.data
		if not parsed is Dictionary or int(parsed.get("version", 0)) not in [1,2,3]:
			continue
		var defaults := fresh_profile()
		for key in defaults:
			if parsed.has(key):
				defaults[key] = parsed[key]
		profile = defaults
		profile["gold"] = maxi(0, int(profile["gold"]))
		profile["diamonds"] = maxi(0, int(profile["diamonds"]))
		if profile["levels"] is Array and profile["levels"].size()==6:
			# Preserve the reach previously bought as part of rope length.
			profile["levels"].append(profile["levels"][0])
		if not profile["levels"] is Array or profile["levels"].size()!=UPGRADE_COUNT:
			profile["levels"] = [1,1,1,1,1,1,1]
		if int(parsed["version"])<3:
			# Keep the old material milestones as the new two/three-prong hooks.
			var old_grip := clampi(int(profile["levels"][2]),1,6)
			profile["levels"][2] = 1 if old_grip==1 else 2 if old_grip<5 else 3
		profile["version"] = 3
		if not profile["learned_controls"] is Array: profile["learned_controls"] = []
		profile["learned_controls"] = profile["learned_controls"].filter(func(action): return action in ["aim","swing","rope","release"])
		if not profile["run_history"] is Array: profile["run_history"] = []
		profile["run_history"] = profile["run_history"].slice(-30)
		for i in range(UPGRADE_COUNT):
			profile["levels"][i] = clampi(int(profile["levels"][i]), 1, max_level(i))
		for key in ["locations", "cleared_locations"]:
			if not profile[key] is Array:
				profile[key] = [0] if key=="locations" else []
			profile[key] = profile[key].map(func(id): return int(id))
		profile["reached_zones"] = clampi(int(profile["reached_zones"]), 1, 6)
		profile["selected_location"] = clampi(int(profile["selected_location"]),0,balance["locations"].size()-1)
		if not profile["locations"].has(profile["selected_location"]):
			profile["selected_location"] = 0
		if not profile["active"] is Dictionary:
			profile["active"] = {}
		if not profile["active"].is_empty():
			for key in ["picked", "broken"]:
				profile["active"][key] = profile["active"].get(key,[]).map(func(id): return int(id))
			for item in profile["active"].get("bag",[]):
				for key in ["id", "tier", "value"]:
					item[key] = int(item[key])
		if profile["active"].get("id", "unused") == profile["last_settled"]:
			profile["active"] = {}
		return

func save() -> bool:
	var absolute := ProjectSettings.globalize_path(save_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var pending := absolute + ".tmp"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		save_error = "Не удалось сохранить прогресс"
		push_error(save_error + ": " + str(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	file.close()
	# Keep a recovery copy if the app closes between renames.
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(absolute + ".bak"):
			DirAccess.remove_absolute(absolute + ".bak")
		if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK:
			save_error = "Не удалось обновить сохранение"
			return false
	var error := DirAccess.rename_absolute(pending, absolute)
	save_error = "" if error == OK else "Не удалось записать сохранение"
	return error == OK

func level(kind: int) -> int:
	return int(profile["levels"][kind])

func max_level(kind: int) -> int:
	return 3 if kind==2 else 6

func hook_radius() -> float:
	return value("hook_radii",2)

func upgrade_available(kind: int) -> bool:
	return level(kind)<max_level(kind) and (kind==2 or level(kind)+1<=unlocked_upgrade_level())

func value(key: String, kind: int) -> float:
	return float(balance[key][level(kind) - 1])

func cost(kind: int) -> int:
	if level(kind) >= max_level(kind):
		return 0
	if kind==2:
		return int(balance["tip_prices"][level(kind)-1])
	return roundi(float(balance["upgrade_prices"][level(kind)-1]) * float(balance["upgrade_weights"][kind]))

func unlocked_upgrade_level() -> int:
	# Early failures earn usable progress before the first 200 m zone gate.
	return maxi(2,int(profile["reached_zones"]))

func purchase(kind: int) -> String:
	if not profile["active"].is_empty():
		return "Сначала заверши текущую попытку"
	if level(kind) >= max_level(kind):
		return "Уже максимальный уровень"
	if not upgrade_available(kind):
		return "Достигни зоны «" + ZONE_NAMES[level(kind)] + "»"
	var price := cost(kind)
	if int(profile["gold"]) < price:
		return "Не хватает %d золота" % (price - int(profile["gold"]))
	profile["gold"] -= price
	profile["levels"][kind] += 1
	save()
	return "Улучшено: " + UPGRADE_NAMES[kind]

func upgrade_text(kind: int, at_level: int = -1) -> String:
	var i := (level(kind) if at_level == -1 else at_level) - 1
	match kind:
		0: return "%d м" % roundi(float(balance["rope_lengths"][i]) * float(balance["meters_per_unit"]))
		1: return "+%d%% при отпускании" % roundi((float(balance["impulse_factors"][i])-1)*100)
		2: return "%d наконечн. · допуск ±%.1f м" % [i+1,(.04+float(balance["hook_radii"][i])-.32)*10]
		3: return "%d слотов · %d типов находок" % [i+1, i+1]
		4: return "сбор при касании" if i == 0 else "%d м притяжения" % roundi(float(balance["magnet_radii"][i])*10)
		5: return "%d%% стоимости при поражении" % int(balance["recovery_percents"][i])
		_: return "%d м/с · скорость крюка" % roundi(float(balance["throw_speeds"][i])*10)

func shot_range() -> float:
	return value("rope_lengths",0)

func learn_control(action: String) -> void:
	if action not in profile["learned_controls"]:
		profile["learned_controls"].append(action)

func recommended_upgrade() -> int:
	if not profile["active"].is_empty(): return -1
	var available: Array[int] = []
	for kind in [0,THROW,3,1,2,5,4]:
		if upgrade_available(kind) and cost(kind)<=int(profile["gold"]):
			available.append(kind)
	if available.is_empty(): return -1
	var lowest := 7
	var selected := -1
	for kind in available:
		if level(kind)<lowest:
			lowest = level(kind)
			selected = kind
	return selected

func next_goal() -> String:
	var stage := int(profile["reached_zones"])
	return "Следующая зона · %d м" % roundi(stage*float(balance["zone_units"])*10) if stage<6 else "Следующая цель · вершина"

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

func height_gold(units: float) -> int:
	var bands := maxi(0, floori(units * float(balance["meters_per_unit"]) / 10))
	var result := 0
	for band in range(1, bands + 1):
		result += 2 + mini((band-1) / 20, 7)
	return result

func try_pick(item: Dictionary) -> bool:
	# Intentionally no auto-replacement; a more valuable find stays in the world.
	if picked.has(item["id"]) or bag.size() >= level(3) or int(item["tier"]) >= level(3):
		return false
	bag.append(item.duplicate(true))
	picked.append(item["id"])
	return true

func discard(index: int) -> void:
	if index >= 0 and index < bag.size():
		bag.remove_at(index)
	# Picked IDs remain marked: discarded finds cannot be collected repeatedly.

func bag_value() -> int:
	var total := 0
	for item in bag:
		total += int(item["value"])
	return total

func retained(success: bool) -> int:
	return bag_value() if success else floori(bag_value() * value("recovery_percents", 5) / 100)

func settle(run_id: String, mode: String, highest: float, success: bool, location: int) -> Dictionary:
	if run_id.is_empty() or profile["last_settled"] == run_id:
		return {"duplicate": true, "total": 0}
	var summit_success := success and mode == "summit"
	var height := height_gold(highest)
	var loot := retained(summit_success)
	var finish := int(balance["summit_repeat_bonus"]) if summit_success else 0
	var first: bool = summit_success and not profile["cleared_locations"].has(location)
	if first:
		finish += int(balance["first_summit_gold"])
		profile["diamonds"] += int(balance["first_summit_diamonds"])
		profile["cleared_locations"].append(location)
	if summit_success:
		profile["summit_cleared"] = true
		profile["wins"] += 1
	if mode == "endless":
		profile["endless_best"] = maxf(float(profile["endless_best"]), highest * 10)
	profile["gold"] += height + loot + finish
	profile["runs"] += 1
	profile["last_settled"] = run_id
	profile["active"] = {}
	save()
	return {"duplicate": false, "height": height, "loot": loot, "carried": bag_value(), "finish": finish,
		"total": height+loot+finish, "first": first, "success": summit_success, "highest": roundi(highest*10)}

func purchase_location(index: int) -> String:
	if profile["locations"].has(index):
		return "Локация уже открыта"
	if not profile["summit_cleared"]:
		return "Сначала достигни первой вершины"
	var definition: Dictionary = balance["locations"][index]
	var currency: String = definition["currency"]
	var price: int = int(definition["price"])
	if int(profile[currency]) < price:
		return "Не хватает валюты для этой локации"
	profile[currency] -= price
	profile["locations"].append(index)
	save()
	return "Открыта: " + str(definition["name"])
