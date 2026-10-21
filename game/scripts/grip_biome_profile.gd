class_name GripBiomeProfile
extends RefCounted

# Look of grips, mounts and decor for one style of mountain. A profile changes
# shape, material, hardware, decor, light and weather cues only: the mechanic
# contracts in GripSpec are identical in every profile, so a skill learnt on
# one mountain transfers to the next.

const IDS := ["forest","desert","snow","ruins","sky"]

var id := "forest"
var title := ""
# base / warm / cool tones of the host rock; the grip stone leans on base.
var rock_palette: Dictionary = {}
# Material of every grip type: [name, colour, gloss 0..1].
var surface_material: Array = []
# Shape family the builder uses for each type (see MountainVisuals).
var silhouette_family_by_type: Array = []
# Fixings that mark a permanent grip: style, metal colour, accent colour.
var attachment_hardware: Dictionary = {}
var timer_style: Dictionary = {}
var vegetation_set: Dictionary = {}
var crystal_set: Dictionary = {}
var weathering_rules: Dictionary = {}
var light_and_shadow_tuning: Dictionary = {}
# HUD names per type, with grammatical gender for the lifetime word.
var type_titles: Array = []
# Material of the host rock masses: base and facet colours, roughness,
# strata, cavity shade, tints of lit tops and shaded undersides, weathering.
var rock_material: Dictionary = {}

const DATA := {
	"forest":{
		"rock_material":{"base_color":Color("6f6e66"),"facet_palette":[Color("75746a"),Color("6a6a63"),Color("7a776b")],"roughness":.94,"normal_strength":.45,"strata_scale":.6,"cavity_strength":.32,"top_light_tint":Color("e6dfc4"),"underside_tint":Color("4f5d68"),"weathering_mask":{"moss":.6,"snow":0.0,"dust":0.0},"decor_palette":[Color("6fae3a"),Color("3f3527")]},
		"title":"Лес и обычная гора",
		"rock_palette":{"base":Color("6d6d63"),"warm":Color("e4dcc4"),"cool":Color("5d6a70")},
		"surface_material":[["известняк",Color("cfc7af"),.0],["живой корень",Color("7a5636"),.05],["гибкая ветка",Color("8a6a44"),.05],["мокрая плита",Color("6f8d96"),.75],["кварц",Color("5f8fe0"),.8]],
		"silhouette_family_by_type":["angular","fibrous_root","bough","wet_slab","quartz_cluster"],
		"attachment_hardware":{"style":"ring","metal":Color("4d555c"),"accent":Color("e2b558")},
		"timer_style":{"ring":Color("ffa052"),"alarm":Color("ff4a3a"),"face":Color("1f1a17"),"rim":Color("f7eed9")},
		"vegetation_set":{"grass":true,"moss":.6,"leaf":Color("6fae3a"),"tip":Color("9ccc55"),"root":Color("5a9134"),"soil":Color("3f3527"),"dry":false},
		"crystal_set":{"body":Color("2f6fd8"),"lit":Color("78b6f4"),"pale":Color("c4e3ff"),"emission":Color("2f7fd0"),"energy":.16},
		"weathering_rules":{"moss":.6,"snow":0.0,"dust":0.0,"strata":.2,"cracks":.5},
		"light_and_shadow_tuning":{"contact":.22,"socket":.30,"rim":.45,"emission_scale":1.0},
		"type_titles":[["Камень","m"],["Хрупкий корень","m"],["Упругая ветка","f"],["Скользкая плита","f"],["Кристалл выбора","m"]],
	},
	"desert":{
		"rock_material":{"base_color":Color("86705a"),"facet_palette":[Color("8f775c"),Color("7d6853"),Color("957d60")],"roughness":.97,"normal_strength":.55,"strata_scale":1.4,"cavity_strength":.30,"top_light_tint":Color("f1cf98"),"underside_tint":Color("6a5047"),"weathering_mask":{"moss":0.0,"snow":0.0,"dust":.6},"decor_palette":[Color("a49a55"),Color("5c4630")]},
		"title":"Пустыня",
		"rock_palette":{"base":Color("8a7356"),"warm":Color("e2b98a"),"cool":Color("7a6a5c")},
		"surface_material":[["песчаник",Color("d9a774"),.0],["сухая плита",Color("b5764a"),.0],["натянутая ткань",Color("d8c08f"),.05],["солевой выступ",Color("e9e2d2"),.7],["янтарная жеода",Color("e8913f"),.75]],
		"silhouette_family_by_type":["layered","dry_slab","cloth_band","salt_glass","amber_geode"],
		"attachment_hardware":{"style":"rivets","metal":Color("7a5a36"),"accent":Color("d9a24a")},
		"timer_style":{"ring":Color("ffb35a"),"alarm":Color("ff5a2e"),"face":Color("2a1b12"),"rim":Color("fbe9cc")},
		"vegetation_set":{"grass":true,"moss":0.0,"leaf":Color("a49a55"),"tip":Color("d2c27a"),"root":Color("6f6a3a"),"soil":Color("5c4630"),"dry":true},
		"crystal_set":{"body":Color("c4651e"),"lit":Color("f0a24a"),"pale":Color("ffd99a"),"emission":Color("c06a20"),"energy":.12},
		"weathering_rules":{"moss":0.0,"snow":0.0,"dust":.6,"strata":.8,"cracks":.7},
		"light_and_shadow_tuning":{"contact":.26,"socket":.34,"rim":.35,"emission_scale":.8},
		"type_titles":[["Песчаник","m"],["Сухая плита","f"],["Натянутая ткань","f"],["Солевой выступ","m"],["Жеода выбора","f"]],
	},
	"snow":{
		"rock_material":{"base_color":Color("6c727a"),"facet_palette":[Color("737a82"),Color("656b73"),Color("777c84")],"roughness":.85,"normal_strength":.4,"strata_scale":.4,"cavity_strength":.30,"top_light_tint":Color("f2f6f8"),"underside_tint":Color("4a5f78"),"weathering_mask":{"moss":0.0,"snow":.8,"dust":0.0},"decor_palette":[Color("dfeef0"),Color("6c7a82")]},
		"title":"Снег и лёд",
		"rock_palette":{"base":Color("6a7076"),"warm":Color("c9ced2"),"cool":Color("566676")},
		"surface_material":[["холодный гранит",Color("a7adb4"),.05],["замёрзшая ветвь",Color("6c5a4c"),.15],["ледяная корка",Color("bfe2f0"),.6],["прозрачный лёд",Color("a6d2e6"),.9],["ледяной кластер",Color("7fc4ee"),.85]],
		"silhouette_family_by_type":["frosted","frozen_branch","ice_crust","clear_ice","ice_cluster"],
		"attachment_hardware":{"style":"bracket","metal":Color("5a646c"),"accent":Color("d8e4ea")},
		"timer_style":{"ring":Color("ffa052"),"alarm":Color("ff4a3a"),"face":Color("18222a"),"rim":Color("eef6fa")},
		"vegetation_set":{"grass":false,"moss":0.0,"leaf":Color("7d9a86"),"tip":Color("dfeef0"),"root":Color("4f6658"),"soil":Color("6c7a82"),"dry":false,"frost":true},
		"crystal_set":{"body":Color("4f9fd8"),"lit":Color("9fd6f4"),"pale":Color("e6f6ff"),"emission":Color("3f8fd0"),"energy":.18},
		"weathering_rules":{"moss":0.0,"snow":.8,"dust":0.0,"strata":.1,"cracks":.4},
		"light_and_shadow_tuning":{"contact":.20,"socket":.26,"rim":.6,"emission_scale":1.0},
		"type_titles":[["Гранит","m"],["Замёрзшая ветвь","f"],["Ледяная корка","f"],["Скользкий лёд","m"],["Ледяной кристалл","m"]],
	},
	"ruins":{
		"rock_material":{"base_color":Color("6e6b66"),"facet_palette":[Color("74706a"),Color("67645f"),Color("78746c")],"roughness":.93,"normal_strength":.5,"strata_scale":.2,"cavity_strength":.34,"top_light_tint":Color("e4d8bc"),"underside_tint":Color("514f5c"),"weathering_mask":{"moss":.3,"snow":0.0,"dust":.3},"decor_palette":[Color("6e9a3e"),Color("4a4036")]},
		"title":"Руины",
		"rock_palette":{"base":Color("6e6c67"),"warm":Color("d4c8ae"),"cool":Color("5e6066")},
		"surface_material":[["тёсаный камень",Color("c9bfa6"),.0],["старая балка",Color("6e5236"),.0],["пружинная скоба",Color("8a8f94"),.4],["полированная плитка",Color("b8c3c4"),.75],["минерал в шве",Color("8a6ad0"),.8]],
		"silhouette_family_by_type":["masonry","cracked_beam","spring_bracket","polished_tile","seam_mineral"],
		"attachment_hardware":{"style":"dowel","metal":Color("5c5348"),"accent":Color("c8a25a")},
		"timer_style":{"ring":Color("ffa052"),"alarm":Color("ff4a3a"),"face":Color("1f1c19"),"rim":Color("efe6d2")},
		"vegetation_set":{"grass":true,"moss":.3,"leaf":Color("6e9a3e"),"tip":Color("a6c25e"),"root":Color("4e7a30"),"soil":Color("4a4036"),"dry":false,"sparse":true},
		"crystal_set":{"body":Color("6a3fc0"),"lit":Color("a98fdc"),"pale":Color("e2d6ff"),"emission":Color("6a3fc0"),"energy":.2},
		"weathering_rules":{"moss":.3,"snow":0.0,"dust":.4,"strata":0.0,"cracks":.8},
		"light_and_shadow_tuning":{"contact":.24,"socket":.32,"rim":.4,"emission_scale":.9},
		"type_titles":[["Тёсаный камень","m"],["Старая балка","f"],["Пружинная скоба","f"],["Гладкая плитка","f"],["Минерал выбора","m"]],
	},
	"sky":{
		"rock_material":{"base_color":Color("7b7f85"),"facet_palette":[Color("83878c"),Color("74787e"),Color("878a8e")],"roughness":.9,"normal_strength":.35,"strata_scale":.3,"cavity_strength":.26,"top_light_tint":Color("fbf6ea"),"underside_tint":Color("5a6a86"),"weathering_mask":{"moss":.1,"snow":.2,"dust":0.0},"decor_palette":[Color("7fbf8a"),Color("8a8478")]},
		"title":"Небеса",
		"rock_palette":{"base":Color("7e8285"),"warm":Color("eae6dc"),"cool":Color("8a96a6")},
		"surface_material":[["пористый камень",Color("e3dfd4"),.0],["канатный корень",Color("b08a5a"),.05],["подвесной крепёж",Color("c9c2ad"),.2],["облачная плита",Color("dceaf4"),.8],["светящийся кварц",Color("bfe4ff"),.85]],
		"silhouette_family_by_type":["pumice","rope_root","hanging_mount","cloud_glass","glow_quartz"],
		"attachment_hardware":{"style":"lashing","metal":Color("8a7a5c"),"accent":Color("f1d27b")},
		"timer_style":{"ring":Color("ffc06a"),"alarm":Color("ff5a4a"),"face":Color("26303a"),"rim":Color("ffffff")},
		"vegetation_set":{"grass":true,"moss":.1,"leaf":Color("7fbf8a"),"tip":Color("c8ecb0"),"root":Color("5a8f62"),"soil":Color("8a8478"),"dry":false,"sparse":true},
		"crystal_set":{"body":Color("8fc8f0"),"lit":Color("cfe9ff"),"pale":Color("ffffff"),"emission":Color("7fb8f0"),"energy":.24},
		"weathering_rules":{"moss":.1,"snow":.2,"dust":0.0,"strata":0.0,"cracks":.3},
		"light_and_shadow_tuning":{"contact":.18,"socket":.24,"rim":.6,"emission_scale":1.2},
		"type_titles":[["Пористый камень","m"],["Канатный корень","m"],["Подвесной крепёж","m"],["Облачная плита","f"],["Кварц выбора","m"]],
	},
}

static var _cache: Dictionary = {}

static func named(profile_id: String) -> GripBiomeProfile:
	var key := profile_id if DATA.has(profile_id) else "forest"
	if not _cache.has(key):
		var profile := GripBiomeProfile.new()
		var data: Dictionary = DATA[key]
		profile.id = key
		profile.title = data["title"]
		profile.rock_palette = data["rock_palette"]
		profile.surface_material = data["surface_material"]
		profile.silhouette_family_by_type = data["silhouette_family_by_type"]
		profile.attachment_hardware = data["attachment_hardware"]
		profile.timer_style = data["timer_style"]
		profile.vegetation_set = data["vegetation_set"]
		profile.crystal_set = data["crystal_set"]
		profile.weathering_rules = data["weathering_rules"]
		profile.light_and_shadow_tuning = data["light_and_shadow_tuning"]
		profile.type_titles = data["type_titles"]
		profile.rock_material = data["rock_material"]
		_cache[key] = profile
	return _cache[key]

# The style of a place. The first location changes style with its height
# zones (Лес, Скалы, Руины, Лёд, Вулкан, Небеса), as its landmarks already do;
# the other locations keep one style along the whole climb.
static func id_for(location: int, height: float) -> String:
	match location:
		1: return "desert"
		2: return "sky"
	return ["forest","forest","ruins","snow","desert","sky"][clampi(int(height/20.0),0,5)]

static func for_place(location: int, height: float) -> GripBiomeProfile:
	return named(id_for(location,height))

func material_name(kind: int) -> String:
	return str(surface_material[clampi(kind,0,4)][0])

func material_color(kind: int) -> Color:
	return surface_material[clampi(kind,0,4)][1]

func gloss(kind: int) -> float:
	return float(surface_material[clampi(kind,0,4)][2])

func family(kind: int) -> String:
	return str(silhouette_family_by_type[clampi(kind,0,4)])
