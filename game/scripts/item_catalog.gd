class_name ItemCatalog
extends RefCounted

# Item contract (chat 4). Every find carries
#   id (runtime find id), item_id, family, kind (model), location_id, act_id,
#   tier, value (= sell_value), sell_value, craft_value, set_id, use_tag,
#   rarity, weight, name
# Families: valuable (sold after the run), relic (sold and counted towards
# its act's set), material (goes to the material wallet), contract (the goal
# of one run) and coin (banked at once, never enters the bag).
# Older saves store {"id","tier","value","kind"}; normalize() reads them as
# valuables by tier, and the old tier-0 "coin" as a coin.

const FAMILIES := ["valuable","relic","material","contract","coin"]
const VALUABLE_KINDS := ["amber","amber","crystal","crystal","star","star"]
const ARTIFACT_KINDS := ["crown","crown","chalice","chalice","idol","idol"]
const LEGACY_NAMES := ["Медная находка", "Янтарь", "Древняя реликвия", "Ледяной кристалл", "Обсидиан", "Небесный осколок"]
const VALUABLE_NAMES := ["Медный слиток", "Янтарь", "Древняя реликвия", "Ледяной кристалл", "Обсидиан", "Небесный осколок"]
const GRADE_NAMES := {"common":"общий","light":"лёгкий","medium":"средний","rare":"редкий"}
const VISUAL_RARITY_COLORS := [Color("e0a83a"),Color("e8833a"),Color("e9bf4f"),Color("6fc6e8"),Color("a98fdc"),Color("f3d478")]
const VISUAL_MATERIAL_COLORS := {"fiber":Color("c9a46a"),"silk":Color("e9e4f2"),"sinew":Color("7fc48a"),"core":Color("8fd8ee")}
static var _balance: Dictionary = {}

static func balance() -> Dictionary:
	if _balance.is_empty():
		_balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	return _balance

static func tier_value(tier: int, location: int = 0) -> int:
	var values: Array = balance()["loot_values"]
	var scales: Array = balance().get("location_value_scale",[1.0])
	return roundi(float(values[clampi(tier,0,values.size()-1)])*float(scales[clampi(location,0,scales.size()-1)]))

static func _base(id: int, family: String, location: int, act_id: String, tier: int, value: int) -> Dictionary:
	return {"id":id,"item_id":"","family":family,"kind":"","location_id":LevelCatalog.level(location)["id"],"act_id":act_id,
		"tier":tier,"value":value,"sell_value":value,"craft_value":0,"set_id":"","use_tag":"sell","rarity":"common","weight":1,"name":""}

static func valuable(id: int, location: int, act_id: String, tier: int, rarity: String = "common") -> Dictionary:
	var multiplier := float(balance()["items"]["rare_multiplier"]) if rarity=="artifact" else 1.0
	var item := _base(id,"valuable",location,act_id,tier,roundi(tier_value(tier,location)*multiplier))
	item["rarity"] = rarity
	item["kind"] = ARTIFACT_KINDS[clampi(tier,0,5)] if rarity=="artifact" else VALUABLE_KINDS[clampi(tier,0,5)]
	item["name"] = ("Артефакт · " if rarity=="artifact" else "")+VALUABLE_NAMES[clampi(tier,0,5)]
	return item

static func relic(id: int, location: int, act_id: String, tier: int, set_id: String, landmark: bool = false) -> Dictionary:
	var key := "landmark_multiplier" if landmark else "relic_multiplier"
	var item := _base(id,"relic",location,act_id,tier,roundi(tier_value(tier,location)*float(balance()["items"][key])))
	var definition: Dictionary = balance()["sets"].get(set_id,{})
	item["set_id"] = set_id
	item["rarity"] = "artifact" if landmark else "set"
	item["use_tag"] = "landmark" if landmark else "set"
	item["kind"] = "idol" if landmark else "relic"
	item["name"] = str(definition.get("landmark","Ориентир")) if landmark else "Часть: "+str(definition.get("name","комплект"))
	return item

static func material(id: int, location: int, act_id: String, tier: int, material_id: String) -> Dictionary:
	var definition: Dictionary = balance()["materials"][material_id]
	var item := _base(id,"material",location,act_id,tier,int(definition["sell_value"]))
	item["craft_value"] = int(definition["craft_value"])
	item["set_id"] = material_id
	item["use_tag"] = "craft"
	item["rarity"] = "rare" if definition["grade"]=="rare" else "common"
	item["kind"] = "material"
	item["name"] = str(definition["name"])
	return item

static func contract(id: int, location: int, act_id: String, tier: int, contract_tag: String) -> Dictionary:
	var item := _base(id,"contract",location,act_id,tier,roundi(tier_value(tier,location)*float(balance()["items"]["contract_multiplier"])))
	item["set_id"] = contract_tag
	item["use_tag"] = "contract"
	item["rarity"] = "contract"
	item["kind"] = "chalice"
	item["name"] = "Контрактный груз"
	return item

static func coin(id: int, location: int, act_id: String, value: int, use_tag: String = "single") -> Dictionary:
	var item := _base(id,"coin",location,act_id,0,value)
	item["kind"] = "coin"
	item["use_tag"] = use_tag
	item["name"] = "Тайник монет" if use_tag=="cache" else "Монетка"
	return item

# Items of older saves and older generators.
static func normalize(item: Dictionary) -> Dictionary:
	if item.has("family") and str(item["family"]) in FAMILIES: return item
	var tier := clampi(int(item.get("tier",0)),0,5)
	var value := int(item.get("value",0))
	if str(item.get("kind",""))=="coin":
		item["family"] = "coin"
		item["use_tag"] = "legacy"
	else:
		item["family"] = "valuable"
		item["use_tag"] = "sell"
	item["rarity"] = "artifact" if value>int(balance()["loot_values"][tier]) else "common"
	for key in ["item_id","location_id","act_id","set_id"]:
		if not item.has(key): item[key] = ""
	item["sell_value"] = value
	if not item.has("craft_value"): item["craft_value"] = 0
	if not item.has("weight"): item["weight"] = 1
	return item

static func is_coin(item: Dictionary) -> bool:
	return str(item.get("family",""))=="coin" or (not item.has("family") and str(item.get("kind",""))=="coin")

static func name_of(item: Dictionary) -> String:
	if not str(item.get("name","")).is_empty(): return str(item["name"])
	match str(item.get("kind","")):
		"coin": return "Золотая монетка"
		"crown": return "Корона ветров"
		"chalice": return "Кубок вершины"
		"idol": return "Каменный идол"
	return LEGACY_NAMES[clampi(int(item.get("tier",0)),0,LEGACY_NAMES.size()-1)]

static func family_name(item: Dictionary) -> String:
	match str(item.get("family","valuable")):
		"relic": return "ориентир" if str(item.get("use_tag",""))=="landmark" else "комплект"
		"material": return "материал"
		"contract": return "контракт"
		"coin": return "монеты"
	return "редкая" if str(item.get("rarity",""))=="artifact" else "ценность"

static func visual_color(item: Dictionary) -> Color:
	match str(item.get("family","")):
		"material": return VISUAL_MATERIAL_COLORS.get(str(item.get("set_id","")),Color("c9a46a"))
		"contract": return Color("ff9d5c")
		"relic": return Color("d8c27a")
	return VISUAL_RARITY_COLORS[clampi(int(item.get("tier",0)),0,VISUAL_RARITY_COLORS.size()-1)]

static func material_name(material_id: String) -> String:
	return str(balance()["materials"].get(material_id,{}).get("name",material_id))

static func set_name(set_id: String) -> String:
	return str(balance()["sets"].get(set_id,{}).get("name",set_id))

static func consumables() -> Array:
	return balance()["consumables"]

static func consumable(id: String) -> Dictionary:
	for definition in consumables():
		if definition["id"]==id: return definition
	return {}
