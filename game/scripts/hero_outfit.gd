class_name HeroOutfit
extends RefCounted

# The hero's wardrobe (docs/CHARACTER_PLAN.md stage 7): colours per slot,
# bought with gold and kept in the profile ("outfit" worn, "outfit_owned").
# The model carries each part's slot in its vertex colour
# (tools/blender/export_hero.py); HeroModel's shader shifts that slot's fabric
# hue to the chosen colour and leaves straps, metal, stitches and eyes.

const SLOTS := ["head","jacket","backpack","pants","boots","gloves"]
const SLOT_NAMES := {"head":"Голова","jacket":"Куртка","backpack":"Рюкзак","pants":"Штаны","boots":"Ботинки","gloves":"Перчатки"}
# Vertex colour code of each slot: r + 2g + 4b.
const CODES := {"head":1,"jacket":2,"boots":3,"pants":4,"gloves":5,"backpack":6}
# The painted fabric of each slot: hue and saturation are the medians of the
# slot's saturated pixels on the baked colour texture; value is the lit
# fabric (the median sits in folds and occlusion, and the boots' in the dark
# soles), so a colour's swatch is what the lit part shows. The window is how
# far from that hue a pixel still counts as the fabric (straps and the head
# lamp fall outside).
const BASE := {
	"head":Vector3(.105,.935,.937),
	"jacket":Vector3(.185,.515,.42),
	"pants":Vector3(.073,.397,.31),
	"boots":Vector3(.069,.66,.66),
	"gloves":Vector3(.061,.465,.33),
	"backpack":Vector3(.074,.771,.58),
}
const WINDOW := {"head":.03,"jacket":.07,"pants":.07,"boots":.06,"gloves":.07,"backpack":.06}
# Colours per slot: [id, name, colour, price in gold]. The first is the
# hero's own colour: free and always owned. Picked to sit with the game's
# daylight palette: earthy, alpine and a few bright accents.
const COLOURS := {
	"head":[["head_sun","Солнечная",Color("f5c22b"),0],["head_coral","Коралл",Color("f08466"),250],
		["head_mint","Мята",Color("74d1ad"),250],["head_sky","Небо",Color("7db6ec"),250],
		["head_lilac","Сирень",Color("b39ae6"),400],["head_snow","Снег",Color("eef0f2"),400]],
	"jacket":[["jacket_moss","Мох",Color("5f6b30"),0],["jacket_rowan","Рябина",Color("a8402d"),300],
		["jacket_glacier","Ледник",Color("2f6aa0"),300],["jacket_dune","Дюна",Color("b79257"),300],
		["jacket_dusk","Сумерки",Color("5d4382"),450],["jacket_blizzard","Пурга",Color("d6dde3"),450]],
	"backpack":[["backpack_rust","Ржавчина",Color("94531f"),0],["backpack_pine","Хвоя",Color("2f6a3e"),200],
		["backpack_navy","Глубина",Color("2c3f6e"),200],["backpack_crimson","Вишня",Color("8c2433"),200],
		["backpack_ochre","Охра",Color("c08a22"),350],["backpack_slate","Сланец",Color("4d5761"),350]],
	"pants":[["pants_bark","Кора",Color("3a2a1e"),0],["pants_coal","Уголь",Color("2a2d33"),150],
		["pants_olive","Олива",Color("4a4d2a"),150],["pants_denim","Деним",Color("2e4566"),150],
		["pants_clay","Глина",Color("6e3b2a"),300],["pants_stone","Камень",Color("8a8478"),300]],
	"boots":[["boots_leather","Кожа",Color("b8682f"),0],["boots_black","Смоль",Color("26262b"),150],
		["boots_red","Брусника",Color("7a2026"),150],["boots_moss","Мшистые",Color("3c4a25"),150],
		["boots_sand","Песок",Color("8c6c42"),300],["boots_sky","Лазурь",Color("2e5a86"),300]],
	"gloves":[["gloves_leather","Кожа",Color("42281a"),0],["gloves_black","Смоль",Color("24242a"),120],
		["gloves_red","Сигнал",Color("9a2a22"),120],["gloves_yellow","Маяк",Color("b8901c"),120],
		["gloves_green","Лишайник",Color("3e5a2c"),250],["gloves_white","Иней",Color("c9d0d6"),250]],
}

# What the hero wears now; HeroModel.setup reads it. GameModel sets it from
# the profile; the character screen while choosing.
static var worn := {}

static func entry(id: String) -> Array:
	for slot in COLOURS:
		for option in COLOURS[slot]:
			if option[0]==id: return option
	return []

static func slot_of(id: String) -> String:
	for slot in COLOURS:
		for option in COLOURS[slot]:
			if option[0]==id: return slot
	return ""

static func default_id(slot: String) -> String:
	return str(COLOURS[slot][0][0])

static func price(id: String) -> int:
	var option := entry(id)
	return int(option[3]) if not option.is_empty() else 0

static func worn_id(profile: Dictionary, slot: String) -> String:
	return str(profile.get("outfit",{}).get(slot,default_id(slot)))

static func owns(profile: Dictionary, id: String) -> bool:
	return price(id)==0 or id in profile.get("outfit_owned",[])

# Keeps only known colours that the profile owns, worn in their own slot.
static func sanitize(profile: Dictionary) -> void:
	var owned: Array = []
	for id in profile.get("outfit_owned",[]):
		if not entry(str(id)).is_empty() and price(str(id))>0 and not str(id) in owned: owned.append(str(id))
	profile["outfit_owned"] = owned
	var outfit := {}
	var stored = profile.get("outfit",{})
	if stored is Dictionary:
		for slot in stored:
			var id := str(stored[slot])
			if slot in SLOTS and slot_of(id)==slot and owns(profile,id) and id!=default_id(slot): outfit[slot] = id
	profile["outfit"] = outfit
	worn = outfit.duplicate()

# Buys a colour and puts it on. Returns "" or what stopped the purchase.
static func buy(profile: Dictionary, id: String) -> String:
	var slot := slot_of(id)
	if slot.is_empty(): return "Нет такой детали"
	if owns(profile,id):
		wear(profile,id)
		return ""
	var cost := price(id)
	if int(profile.get("gold",0))<cost: return "Не хватает %d золота" % (cost-int(profile.get("gold",0)))
	profile["gold"] = int(profile["gold"])-cost
	profile["outfit_owned"].append(id)
	wear(profile,id)
	return ""

static func wear(profile: Dictionary, id: String) -> void:
	var slot := slot_of(id)
	if slot.is_empty() or not owns(profile,id): return
	if id==default_id(slot): profile["outfit"].erase(slot)
	else: profile["outfit"][slot] = id
	worn = profile["outfit"].duplicate()

# Shader values for an outfit: per slot code, the base fabric, the target
# colour as HSV and whether the slot is recoloured.
static func shader_values(outfit: Dictionary) -> Dictionary:
	var base := PackedVector3Array()
	var target := PackedVector3Array()
	var window := PackedFloat32Array()
	base.resize(7)
	target.resize(7)
	window.resize(7)
	for slot in SLOTS:
		var code: int = CODES[slot]
		base[code] = BASE[slot]
		var id := str(outfit.get(slot,default_id(slot)))
		var option := entry(id)
		if option.is_empty() or id==default_id(slot): continue
		var color: Color = option[2]
		target[code] = Vector3(color.h,color.s,color.v)
		window[code] = WINDOW[slot]
	return {"base":base,"target":target,"window":window}
