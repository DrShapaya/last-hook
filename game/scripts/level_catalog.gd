class_name LevelCatalog
extends RefCounted

# Three expeditions of three acts each (generator v14). Pure data: the layout
# reads an act's beats, grips, hazards and silhouette from here; visuals read
# its profile, landmarks and props. Mechanics of the five grip types stay in
# GripSpec and never change per act.
#
# LevelDefinition  id, location_slot, display_name, height_units, acts, unlock_rule
# ActDefinition    id, y_start, y_end, biome_profile, intro_rule, route_patterns,
#                  allowed_grips, hazards, landmarks, safe_route_rules,
#                  risky_route_rules, objectives (+ silhouette, props, tags)
# HazardDefinition id, telegraph_time, active_time, collision, damage,
#                  affected_edges, safe_exit_tags (+ kind, timing, force)
#
# Old location ids (green_peak, stone_spires, sky_city) stay the save keys;
# the expedition names are display aliases.

# A beat is one step of an act's topology (see ExpeditionLayout):
#   start  the act's safe shelf and permanent grip
#   intro  links with one known mechanic
#   teach  the act's new rule alone, on a detour or a hazard beside the path
#   fork   safe main detour against a short risky branch (or a choice)
#   rest   recovery shelf with a permanent grip
#   combo  familiar rules together
#   exit   landmark and the way up to the next act
# `branch` is the grip of the beat's detour, `hazard` a HazardDefinition id,
# `main` the special grip allowed on the main path (base kit never needs it).
const HAZARDS := {
	"wind_pocket":{"kind":"field","telegraph_time":0.0,"active_time":INF,"calm_time":0.0,"collision":"zone","damage":"drift",
		"affected_edges":"branch","safe_exit_tags":["sheltered_main"],"force":3.0,"telegraph":"flags and leaves stream along the pocket all the time"},
	"sand_storm":{"kind":"field","telegraph_time":1.3,"active_time":2.4,"calm_time":3.4,"collision":"zone","damage":"drift_and_haze",
		"affected_edges":"branch","safe_exit_tags":["covered_sector"],"force":3.4,"haze":true,"telegraph":"sand ribbons rise and the far dust thickens"},
	"storm_cycle":{"kind":"field","telegraph_time":1.5,"active_time":2.0,"calm_time":3.6,"collision":"zone","damage":"drift_and_haze",
		"affected_edges":"main_cyclic","safe_exit_tags":["calm_window"],"force":2.2,"haze":true,"telegraph":"mirrors flash and ribbons turn before each storm"},
	"blizzard_gust":{"kind":"field","telegraph_time":1.0,"active_time":.7,"calm_time":3.8,"collision":"zone","damage":"drift",
		"affected_edges":"branch","safe_exit_tags":["inner_anchors"],"force":6.0,"telegraph":"snow streaks run along the gust line"},
	"cactus":{"kind":"contact","telegraph_time":0.0,"active_time":INF,"calm_time":0.0,"collision":"circle","damage":"knock",
		"affected_edges":"branch_envelope","safe_exit_tags":["clear_lane"],"radius":.6,"telegraph":"a large cactus at one clear danger point"},
	"scorpion":{"kind":"contact","telegraph_time":.9,"active_time":.6,"calm_time":2.8,"collision":"circle","damage":"knock",
		"affected_edges":"branch_envelope","safe_exit_tags":["clear_lane"],"radius":.75,"telegraph":"the tail rises and glows before a strike"},
	"icicle":{"kind":"falling","telegraph_time":1.1,"active_time":.7,"calm_time":3.0,"collision":"line","damage":"knock",
		"affected_edges":"branch_envelope","safe_exit_tags":["clear_lane"],"radius":.45,"telegraph":"a crack, a shadow line and a delay before the fall"},
	"sand_bridge":{"kind":"collapse","telegraph_time":1.0,"active_time":0.0,"calm_time":0.0,"collision":"ledge","damage":"collapse_once",
		"affected_edges":"rest_shelf","safe_exit_tags":["revealed_exit","permanent_rest"],"telegraph":"sand pours and the bridge cracks under the hero"},
}

const LEVELS := [
	{"id":"green_peak","location_slot":0,"display_name":"Стандартная гора","height_units":120,
		"unlock_rule":{},"acts":["root_wall","wind_traverse","old_post"]},
	{"id":"stone_spires","location_slot":1,"display_name":"Пустынный каньон","height_units":140,
		"unlock_rule":{"cleared":0,"gold":2500},"acts":["dry_canyon","buried_caravan","storm_observatory"]},
	{"id":"sky_city","location_slot":2,"display_name":"Снежная вершина","height_units":160,
		"unlock_rule":{"cleared":1,"tokens":5,"diamonds":15},"acts":["white_saddle","blue_crevasse","shattered_crown"]},
]

# y_start / y_end are shares of the level height; ExpeditionLayout turns them
# into units. `known` lists the rules an act may use without introducing them.
# `variants` are contract variants (L6): each changes the choice at the fork
# (collection, speed or risky shortcut) and never the number of rows, so a
# variant of one act leaves every other act as it was.
const ACTS := {
	"root_wall":{"display_name":"Лесная корневая стена","share":[0.0,1.0/3.0],"biome_profile":"forest",
		"intro_rule":"Обычная, временная и пружинная опоры; ходьба по широким полкам",
		"silhouette":["buttress","shoulder","overhang"],"width":1.0,"obstacle":"shelf","shelf_width":2.1,
		"allowed_grips":[0,1,2],"known":[0,2],"hazards":[],
		"landmarks":["root_bridge","pine"],"props":["grass","bird","insects","stones"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","main":2},
			{"beat":"teach","branch":1,"tag":"collection"},
			{"beat":"fork","branch":2,"tag":"risky_shortcut","alt":"long_moss_detour"},
			{"beat":"rest"},
			{"beat":"combo","main":2,"branch":1,"tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"shortcut":"spring impulse branch skips the moss detour"},
		"variants":[{"name":"collection","beats":{"3":{"tag":"collection","branch":1}}},{"name":"speed","beats":{"3":{"tag":"speed","branch":2}}}],
		"objectives":["reach_post_shelf","take_root_detour"],"reward_tag":"forest_relic","contract_tag":"root_impulse"},
	"wind_traverse":{"display_name":"Ветровой траверс","share":[1.0/3.0,2.0/3.0],"biome_profile":"ridge",
		"intro_rule":"Постоянный направленный ветровой карман: флаги показывают сторону",
		"silhouette":["ridge","ravine","arch"],"width":.82,"obstacle":"pillar","shelf_width":1.5,
		"allowed_grips":[0,1,2],"known":[0,1,2],"hazards":["wind_pocket"],
		"landmarks":["flag_line","hanging_frame"],"props":["flag","leaves","grass"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","branch":1,"tag":"collection"},
			{"beat":"teach","branch":0,"hazard":"wind_pocket","tag":"collection"},
			{"beat":"fork","branch":0,"hazard":"wind_pocket","tag":"risky_shortcut","alt":"sheltered_low_detour"},
			{"beat":"rest"},
			{"beat":"combo","main":2,"branch":1,"hazard":"wind_pocket","tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"shortcut":"open arc through the wind pocket"},
		"variants":[{"name":"collection","beats":{"3":{"tag":"collection"}}},{"name":"speed","beats":{"3":{"tag":"speed","branch":2}}}],
		"objectives":["cross_open_arc","hold_in_wind"],"reward_tag":"ridge_flag","contract_tag":"open_arc"},
	"old_post":{"display_name":"Старый пост","share":[2.0/3.0,1.0],"biome_profile":"ruins",
		"intro_rule":"Ветер, временная опора и кристаллическая развилка вместе",
		"silhouette":["arch","buttress","shoulder"],"width":1.05,"obstacle":"wedge","shelf_width":1.6,
		"allowed_grips":[0,1,2,4],"known":[0,1,2],"hazards":["wind_pocket"],
		"landmarks":["post_gate","signal_flags"],"props":["block","flag","mechanism","grass"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","branch":0,"hazard":"wind_pocket","tag":"collection"},
			{"beat":"teach","branch":4,"tag":"choice"},
			{"beat":"rest"},
			{"beat":"combo","main":2,"branch":1,"hazard":"wind_pocket","tag":"collection"},
			{"beat":"fork","branch":4,"tag":"choice","alt":"root_arch","landmark":"root_arch"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"choice":"both crystal exits lead forward past the root arch"},
		"variants":[{"name":"risky","beats":{"5":{"tag":"risky_shortcut","branch":1,"hazard":"wind_pocket"}}},{"name":"speed","beats":{"5":{"tag":"speed","branch":2}}}],
		"objectives":["pass_root_arch","choose_crystal_exit"],"reward_tag":"post_seal","contract_tag":"crystal_arch"},
	"dry_canyon":{"display_name":"Сухой каньон","share":[0.0,1.0/3.0],"biome_profile":"desert",
		"intro_rule":"Песчаная корка держит недолго; крупный кактус колет",
		"silhouette":["ravine","ridge","arch"],"width":.95,"obstacle":"pillar","shelf_width":1.7,
		"allowed_grips":[0,1,2],"known":[0,2],"hazards":["cactus"],
		"landmarks":["bones","cactus_grove"],"props":["cactus","dry_bush","bones","sand_jet","scorpion_far"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","main":2},
			{"beat":"teach","branch":1,"tag":"collection"},
			{"beat":"rest"},
			{"beat":"fork","branch":1,"hazard":"cactus","tag":"risky_shortcut","alt":"safe_riverbed"},
			{"beat":"combo","main":2,"branch":1,"tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"shortcut":"sand crust and stones beside a large cactus"},
		"variants":[{"name":"collection","beats":{"4":{"tag":"collection"}}},{"name":"speed","beats":{"4":{"tag":"speed","branch":2}}}],
		"objectives":["cross_crust","avoid_cactus"],"reward_tag":"canyon_bone","contract_tag":"crust_shortcut"},
	"buried_caravan":{"display_name":"Погребённый караван","share":[1.0/3.0,2.0/3.0],"biome_profile":"caravan",
		"intro_rule":"Открытый сектор под бурей, укрытый — за повозками",
		"silhouette":["shoulder","buttress","overhang"],"width":1.0,"obstacle":"shelf","shelf_width":1.6,
		"allowed_grips":[0,1,2],"known":[0,1,2],"hazards":["sand_storm","scorpion"],
		"landmarks":["wagon","sail"],"props":["crate","sail","flag","dry_bush"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","branch":1,"tag":"collection"},
			{"beat":"teach","branch":0,"hazard":"sand_storm","tag":"collection"},
			{"beat":"rest"},
			{"beat":"fork","branch":0,"hazard":"sand_storm","extra":"scorpion","tag":"risky_shortcut","alt":"caravan_detour"},
			{"beat":"combo","main":2,"branch":1,"tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"shortcut":"short open window across the storm sector"},
		"variants":[{"name":"collection","beats":{"4":{"tag":"collection"}}},{"name":"speed","beats":{"4":{"tag":"speed","branch":2}}}],
		"objectives":["cross_open_window","pass_scorpion"],"reward_tag":"caravan_cargo","contract_tag":"open_window"},
	"storm_observatory":{"display_name":"Обсерватория пыльной бури","share":[2.0/3.0,1.0],"biome_profile":"observatory",
		"intro_rule":"Буря идёт циклами; зеркала и ленты показывают направление",
		"silhouette":["arch","ravine","shoulder"],"width":1.1,"obstacle":"wedge","shelf_width":1.8,
		"allowed_grips":[0,1,2,4],"known":[0,1,2],"hazards":["sand_storm","storm_cycle","sand_bridge"],
		"landmarks":["mirror_mast","lens_ring"],"props":["lens","ribbon","mast","sand_jet"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","branch":0,"hazard":"sand_storm","tag":"collection"},
			{"beat":"teach","hazard":"storm_cycle","main_hazard":true},
			{"beat":"fork","branch":4,"tag":"choice","alt":"mirror_ring"},
			{"beat":"rest","hazard":"sand_bridge"},
			{"beat":"combo","main":2,"branch":1,"hazard":"sand_storm","tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":["storm_cycle"],"wait":"stone grips hold through the storm"},
		"risky_route_rules":{"collapse":"the sand bridge falls once and opens a revealed exit"},
		"variants":[{"name":"risky","beats":{"3":{"tag":"risky_shortcut","branch":1,"hazard":"sand_storm"}}},{"name":"speed","beats":{"3":{"tag":"speed","branch":2}}}],
		"objectives":["wait_calm_window","survive_bridge"],"reward_tag":"observatory_lens","contract_tag":"calm_window"},
	"white_saddle":{"display_name":"Белая седловина","share":[0.0,1.0/3.0],"biome_profile":"snow",
		"intro_rule":"Короткое скольжение по гладкому льду; сосульки пока только висят",
		"silhouette":["shoulder","ridge","buttress"],"width":1.15,"obstacle":"shelf","shelf_width":1.9,
		"allowed_grips":[0,2,3],"known":[0,2],"hazards":[],
		"landmarks":["ice_needles","snow_pines"],"props":["snow_pocket","pine_snow","tracks","icicles_safe"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","main":2},
			{"beat":"teach","branch":3,"tag":"collection"},
			{"beat":"rest"},
			{"beat":"fork","branch":3,"tag":"risky_shortcut","alt":"rough_outer_cornice"},
			{"beat":"combo","main":2,"branch":3,"tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"shortcut":"smooth short ice transfer"},
		"variants":[{"name":"collection","beats":{"4":{"tag":"collection"}}},{"name":"speed","beats":{"4":{"tag":"speed","branch":2}}}],
		"objectives":["slide_and_leave","cross_saddle"],"reward_tag":"saddle_ice","contract_tag":"smooth_cut"},
	"blue_crevasse":{"display_name":"Синяя трещина","share":[1.0/3.0,2.0/3.0],"biome_profile":"crevasse",
		"intro_rule":"Сосулька трескается, бросает тень и только потом падает",
		"silhouette":["ravine","overhang","ravine"],"width":.9,"obstacle":"pillar","shelf_width":1.5,
		"allowed_grips":[0,2,3],"known":[0,2,3],"hazards":["icicle"],
		"landmarks":["ice_columns","chains"],"props":["chain","ice_vein","icicles_safe"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","branch":3,"tag":"collection"},
			{"beat":"teach","branch":0,"hazard":"icicle","tag":"collection"},
			{"beat":"rest"},
			{"beat":"fork","branch":3,"hazard":"icicle","tag":"risky_shortcut","alt":"long_outer_cornice"},
			{"beat":"combo","main":2,"branch":0,"hazard":"icicle","tag":"collection"},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[]},
		"risky_route_rules":{"shortcut":"inner crack with ice and a falling icicle"},
		"variants":[{"name":"collection","beats":{"4":{"tag":"collection","branch":0}}},{"name":"speed","beats":{"4":{"tag":"speed","branch":2}}}],
		"objectives":["read_icicle","inner_crack"],"reward_tag":"crevasse_core","contract_tag":"inner_crack"},
	"shattered_crown":{"display_name":"Расколотая корона","share":[2.0/3.0,1.0],"biome_profile":"crown",
		"intro_rule":"Скольжение, сосульки и короткие порывы метели — по очереди",
		"silhouette":["arch","overhang","ridge"],"width":.95,"obstacle":"wedge","shelf_width":1.7,
		"allowed_grips":[0,2,3],"known":[0,2,3],"hazards":["icicle","blizzard_gust"],
		"landmarks":["tower_ring","signal_light"],"props":["frozen_rope","signal_light","cornice","icicles_safe"],
		"route_patterns":[
			{"beat":"start"},
			{"beat":"intro","branch":3,"tag":"collection"},
			{"beat":"teach","branch":0,"hazard":"blizzard_gust","tag":"collection"},
			{"beat":"rest"},
			{"beat":"combo","main":2,"branch":3,"hazard":"icicle","tag":"collection"},
			{"beat":"fork","branch":0,"hazard":"blizzard_gust","tag":"speed","alt":"inner_permanent_anchors","permanent_main":true},
			{"beat":"exit"}],
		"safe_route_rules":{"main_grips":[0,2],"main_hazards":[],"permanent":"the inner fork path is on permanent anchors"},
		"risky_route_rules":{"speed":"outer fast path through the blizzard gusts"},
		"variants":[{"name":"collection","beats":{"5":{"tag":"collection"}}},{"name":"risky","beats":{"5":{"tag":"risky_shortcut","branch":3}}}],
		"objectives":["outer_fast_path","inner_anchors"],"reward_tag":"crown_signal","contract_tag":"outer_gust"},
}

static func level(location: int) -> Dictionary:
	return LEVELS[clampi(location,0,LEVELS.size()-1)]

static func act(act_id: String) -> Dictionary:
	return ACTS.get(act_id,{})

static func hazard(hazard_id: String) -> Dictionary:
	return HAZARDS.get(hazard_id,{})

# Acts of a level in climbing order with their height range in units. Beyond
# the level height (endless) the acts repeat in the same order.
static func act_spans(location: int, height_units: float = -1.0) -> Array:
	var definition := level(location)
	var total := float(definition["height_units"]) if height_units<=0 else height_units
	var result: Array = []
	for index in range(definition["acts"].size()):
		var id: String = definition["acts"][index]
		var share: Array = ACTS[id]["share"]
		result.append({"id":id,"index":index,"y_start":roundf(float(share[0])*total),"y_end":roundf(float(share[1])*total)})
	return result

# The act at a height: index counts repeats in endless mode (3, 4, ... after
# the third act), so every act instance has its own seed stream.
static func act_at(location: int, height: float, height_units: float = -1.0) -> Dictionary:
	var spans := act_spans(location,height_units)
	var total: float = spans[-1]["y_end"]
	var cycle := maxi(0,int(floor(height/total))) if height>=total else 0
	var local := height-cycle*total
	for span in spans:
		if local<float(span["y_end"]) or span==spans[-1]:
			var result: Dictionary = span.duplicate()
			result["index"] = int(span["index"])+cycle*spans.size()
			result["y_start"] = float(span["y_start"])+cycle*total
			result["y_end"] = float(span["y_end"])+cycle*total
			return result
	return spans[0]

# A fixed seed per act for contracts: the same seed always gives the same
# variant and route (see test_levels).
static func contract_seed(location: int, act_local: int) -> int:
	return 52000+location*100+act_local*7

static func display_name(location: int) -> String:
	return str(level(location)["display_name"])

static func act_names(location: int) -> Array:
	var result: Array = []
	for id in level(location)["acts"]: result.append(ACTS[id]["display_name"])
	return result
